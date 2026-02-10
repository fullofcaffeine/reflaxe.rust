//! Threading primitives used by `std/sys/thread/*` overrides.
//!
//! Why
//! - Haxe's `sys.thread.*` implies real OS threads with message queues and synchronization.
//! - The Rust target implements these primitives inside `hxrt` so generated crates remain small and
//!   consistent.
//!
//! What
//! - `thread_spawn` + message queues (`thread_send_message`, `thread_read_message`).
//! - Synchronization primitives compatible with Haxe std semantics:
//!   - `Lock` (counting lock: `release` unblocks exactly one `wait`)
//!   - `Mutex` (re-entrant by owner thread, per Haxe docs)
//!   - `Condition` (internal mutex + signal/broadcast + wait)
//!   - `Semaphore` (counting semaphore with optional timeout)
//!
//! How
//! - We use `parking_lot` for fast primitives and explicit control over timeouts.
//! - Threads are identified by a small `i32` id (0 = main thread), stored thread-locally.
//! - Message queues store `hxrt::dynamic::Dynamic`, which is `Send + Sync` in this runtime.

use crate::cell::{HxCell, HxRc, HxRef};
use crate::dynamic::Dynamic;
use crate::{dynamic, exception};
use parking_lot::{Condvar, Mutex as ParkMutex};
use std::cell::Cell;
use std::collections::{HashMap, VecDeque};
use std::sync::atomic::AtomicU64;
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::Duration;
use std::time::Instant;

fn throw_msg(msg: &str) -> ! {
    exception::throw(dynamic::from(String::from(msg)))
}

// ---- Threads + messages ----------------------------------------------------

struct ThreadState {
    queue: ParkMutex<VecDeque<Dynamic>>,
    cv: Condvar,

    // Per-thread event loop (used by `sys.thread.EventLoop`).
    events: ParkMutex<EventLoopState>,
    events_cv: Condvar,
}

impl ThreadState {
    fn new() -> Self {
        Self {
            queue: ParkMutex::new(VecDeque::new()),
            cv: Condvar::new(),
            events: ParkMutex::new(EventLoopState::default()),
            events_cv: Condvar::new(),
        }
    }
}

static NEXT_THREAD_ID: AtomicI32 = AtomicI32::new(1);
static NEXT_EVENT_ID: AtomicU64 = AtomicU64::new(1);
static THREADS: OnceLock<ParkMutex<HashMap<i32, Arc<ThreadState>>>> = OnceLock::new();
static START: OnceLock<Instant> = OnceLock::new();

thread_local! {
    static CURRENT_THREAD_ID: Cell<i32> = const { Cell::new(0) };
}

fn threads() -> &'static ParkMutex<HashMap<i32, Arc<ThreadState>>> {
    THREADS.get_or_init(|| {
        // The main thread (id 0) is always considered alive.
        let mut map = HashMap::new();
        map.insert(0, Arc::new(ThreadState::new()));
        ParkMutex::new(map)
    })
}

fn now_seconds() -> f64 {
    START.get_or_init(Instant::now).elapsed().as_secs_f64()
}

fn ensure_thread_state(id: i32) -> Arc<ThreadState> {
    let mut map = threads().lock();
    if let Some(s) = map.get(&id) {
        return s.clone();
    }
    let s = Arc::new(ThreadState::new());
    map.insert(id, s.clone());
    s
}

fn remove_thread_state(id: i32) {
    if id == 0 {
        return;
    }
    let mut map = threads().lock();
    map.remove(&id);
}

pub fn thread_current_id() -> i32 {
    CURRENT_THREAD_ID.with(|c| c.get())
}

pub fn thread_spawn(job: HxRc<dyn Fn() + Send + Sync>) -> i32 {
    let id = NEXT_THREAD_ID.fetch_add(1, Ordering::Relaxed);
    let _ = ensure_thread_state(id);
    let job2 = job.clone();
    std::thread::spawn(move || {
        CURRENT_THREAD_ID.with(|c| c.set(id));
        job2();
        remove_thread_state(id);
    });
    id
}

pub fn thread_spawn_with_event_loop(job: HxRc<dyn Fn() + Send + Sync>) -> i32 {
    let id = NEXT_THREAD_ID.fetch_add(1, Ordering::Relaxed);
    let _ = ensure_thread_state(id);
    let job2 = job.clone();
    std::thread::spawn(move || {
        CURRENT_THREAD_ID.with(|c| c.set(id));
        job2();
        event_loop_loop(id);
        remove_thread_state(id);
    });
    id
}

pub fn thread_send_message(thread_id: i32, msg: Dynamic) {
    let state = {
        let map = threads().lock();
        map.get(&thread_id).cloned()
    };
    let Some(state) = state else {
        throw_msg("Thread is not alive");
    };
    let mut q = state.queue.lock();
    q.push_back(msg);
    state.cv.notify_one();
}

pub fn thread_read_message(block: bool) -> Dynamic {
    let id = thread_current_id();
    let state = ensure_thread_state(id);
    let mut q = state.queue.lock();
    if let Some(v) = q.pop_front() {
        return v;
    }
    if !block {
        return Dynamic::null();
    }
    loop {
        state.cv.wait(&mut q);
        if let Some(v) = q.pop_front() {
            return v;
        }
    }
}

// ---- EventLoop ------------------------------------------------------------

#[derive(Clone)]
struct RegularEvent {
    id: u64,
    next_run: f64,
    interval: f64,
    callback: HxRc<dyn Fn() + Send + Sync>,
}

#[derive(Default)]
struct EventLoopState {
    one_time: VecDeque<HxRc<dyn Fn() + Send + Sync>>,
    promised: i32,
    regular: Vec<RegularEvent>, // kept sorted by `next_run`
}

fn with_thread_state_or_throw<R>(thread_id: i32, f: impl FnOnce(&Arc<ThreadState>) -> R) -> R {
    let state = {
        let map = threads().lock();
        map.get(&thread_id).cloned()
    };
    let Some(state) = state else {
        throw_msg("Thread is not alive");
    };
    f(&state)
}

pub fn event_loop_promise(thread_id: i32) {
    with_thread_state_or_throw(thread_id, |state| {
        let mut st = state.events.lock();
        st.promised += 1;
    });
}

pub fn event_loop_run(thread_id: i32, event: HxRc<dyn Fn() + Send + Sync>) {
    with_thread_state_or_throw(thread_id, |state| {
        let mut st = state.events.lock();
        st.one_time.push_back(event);
        state.events_cv.notify_one();
    });
}

pub fn event_loop_run_promised(thread_id: i32, event: HxRc<dyn Fn() + Send + Sync>) {
    with_thread_state_or_throw(thread_id, |state| {
        let mut st = state.events.lock();
        st.one_time.push_back(event);
        st.promised -= 1;
        state.events_cv.notify_one();
    });
}

pub fn event_loop_repeat(
    thread_id: i32,
    event: HxRc<dyn Fn() + Send + Sync>,
    interval_ms: i32,
) -> i32 {
    // `interval_ms == 0` would cause `event_loop_progress()` to spin forever because the event is
    // always due immediately after re-scheduling. Clamp to 1ms to keep semantics sane and prevent
    // hangs.
    let interval = (interval_ms.max(1) as f64) / 1000.0;
    let id = NEXT_EVENT_ID.fetch_add(1, Ordering::Relaxed);
    let next_run = now_seconds() + interval;
    with_thread_state_or_throw(thread_id, |state| {
        let mut st = state.events.lock();
        let ev = RegularEvent {
            id,
            next_run,
            interval,
            callback: event,
        };
        // Insert sorted by next_run.
        let idx = st
            .regular
            .iter()
            .position(|x| ev.next_run < x.next_run)
            .unwrap_or(st.regular.len());
        st.regular.insert(idx, ev);
        state.events_cv.notify_one();
    });
    id as i32
}

pub fn event_loop_cancel(thread_id: i32, event_id: i32) {
    let id = event_id as u64;
    with_thread_state_or_throw(thread_id, |state| {
        let mut st = state.events.lock();
        st.regular.retain(|e| e.id != id);
    });
}

/// Progress the event loop once.
///
/// Returns a float "next event time" marker:
/// - `-2.0` => Now (one or more events executed)
/// - `-1.0` => Never (no more events expected)
/// - `-3.0` => AnyTime(null) (promised events exist, but no scheduled time)
/// - `>= 0` => At(time) in seconds since program start
pub fn event_loop_progress(thread_id: i32) -> f64 {
    let mut to_run: Vec<HxRc<dyn Fn() + Send + Sync>> = Vec::new();
    let mut next_at: f64 = -1.0;
    let mut promised: i32 = 0;
    let now = now_seconds();

    with_thread_state_or_throw(thread_id, |state| {
        let mut st = state.events.lock();

        // Drain regular events due.
        while let Some(first) = st.regular.first() {
            if first.next_run > now {
                break;
            }
            let mut ev = st.regular.remove(0);
            to_run.push(ev.callback.clone());
            ev.next_run += ev.interval;
            // Reinsert.
            let idx = st
                .regular
                .iter()
                .position(|x| ev.next_run < x.next_run)
                .unwrap_or(st.regular.len());
            st.regular.insert(idx, ev);
        }

        // Drain one-time events.
        while let Some(ev) = st.one_time.pop_front() {
            to_run.push(ev);
        }

        promised = st.promised;
        if let Some(first) = st.regular.first() {
            next_at = first.next_run;
        } else {
            next_at = -1.0;
        }
    });

    for ev in to_run.iter() {
        ev();
    }

    if !to_run.is_empty() {
        return -2.0;
    }
    if next_at >= 0.0 {
        return next_at;
    }
    if promised > 0 {
        return -3.0;
    }
    -1.0
}

pub fn event_loop_wait(thread_id: i32, timeout_seconds: Option<f64>) -> bool {
    with_thread_state_or_throw(thread_id, |state| {
        let mut st = state.events.lock();

        let has_any_pending = !st.one_time.is_empty() || !st.regular.is_empty() || st.promised > 0;
        if !has_any_pending {
            return false;
        }
        let has_ready_now = !st.one_time.is_empty()
            || st
                .regular
                .first()
                .map(|e| e.next_run <= now_seconds())
                .unwrap_or(false);
        if has_ready_now {
            return true;
        }

        match timeout_seconds {
            None => {
                state.events_cv.wait(&mut st);
                true
            }
            Some(t) => {
                if t < 0.0 {
                    state.events_cv.wait(&mut st);
                    true
                } else {
                    let dur = Duration::from_millis((t * 1000.0).max(0.0) as u64);
                    !state.events_cv.wait_for(&mut st, dur).timed_out()
                }
            }
        }
    })
}

pub fn event_loop_loop(thread_id: i32) {
    loop {
        let next = event_loop_progress(thread_id);
        if next == -2.0 {
            continue;
        }
        if next == -1.0 {
            break;
        }
        if next == -3.0 {
            let _ = event_loop_wait(thread_id, None);
            continue;
        }
        // At(time)
        let timeout = (next - now_seconds()).max(0.0);
        let _ = event_loop_wait(thread_id, Some(timeout));
    }
}

// ---- Lock -----------------------------------------------------------------

#[derive(Debug, Default)]
pub struct LockHandle {
    // Number of available "releases".
    count: ParkMutex<i32>,
    cv: Condvar,
}

pub fn lock_new() -> HxRef<LockHandle> {
    HxRc::new(HxCell::new(LockHandle::default()))
}

impl LockHandle {
    pub fn wait(&self, timeout_seconds: Option<f64>) -> bool {
        let mut count = self.count.lock();
        if *count > 0 {
            *count -= 1;
            return true;
        }
        let Some(t) = timeout_seconds else {
            while *count <= 0 {
                self.cv.wait(&mut count);
            }
            *count -= 1;
            return true;
        };
        if t < 0.0 {
            while *count <= 0 {
                self.cv.wait(&mut count);
            }
            *count -= 1;
            return true;
        }
        let dur = Duration::from_millis((t * 1000.0).max(0.0) as u64);
        let mut remaining = dur;
        let start = std::time::Instant::now();
        while *count <= 0 {
            let timed_out = self.cv.wait_for(&mut count, remaining).timed_out();
            if *count > 0 {
                break;
            }
            if timed_out {
                return false;
            }
            let elapsed = start.elapsed();
            if elapsed >= dur {
                return false;
            }
            remaining = dur - elapsed;
        }
        *count -= 1;
        true
    }

    pub fn release(&self) {
        let mut count = self.count.lock();
        *count += 1;
        self.cv.notify_one();
    }
}

// ---- Mutex (re-entrant) ---------------------------------------------------

#[derive(Debug, Default)]
struct ReMutexState {
    owner: Option<std::thread::ThreadId>,
    depth: u32,
}

#[derive(Debug, Default)]
pub struct MutexHandle {
    state: ParkMutex<ReMutexState>,
    cv: Condvar,
}

pub fn mutex_new() -> HxRef<MutexHandle> {
    HxRc::new(HxCell::new(MutexHandle::default()))
}

impl MutexHandle {
    pub fn acquire(&self) {
        let tid = std::thread::current().id();
        let mut st = self.state.lock();
        loop {
            match st.owner {
                None => {
                    st.owner = Some(tid);
                    st.depth = 1;
                    return;
                }
                Some(o) if o == tid => {
                    st.depth += 1;
                    return;
                }
                Some(_) => {
                    self.cv.wait(&mut st);
                }
            }
        }
    }

    pub fn try_acquire(&self) -> bool {
        let tid = std::thread::current().id();
        let mut st = self.state.lock();
        match st.owner {
            None => {
                st.owner = Some(tid);
                st.depth = 1;
                true
            }
            Some(o) if o == tid => {
                st.depth += 1;
                true
            }
            Some(_) => false,
        }
    }

    pub fn release(&self) {
        let tid = std::thread::current().id();
        let mut st = self.state.lock();
        match st.owner {
            Some(o) if o == tid => {
                st.depth -= 1;
                if st.depth == 0 {
                    st.owner = None;
                    self.cv.notify_one();
                }
            }
            _ => throw_msg("Mutex.release called by non-owner thread"),
        }
    }
}

// ---- Condition ------------------------------------------------------------

#[derive(Debug, Default)]
struct ConditionState {
    locked_by: Option<std::thread::ThreadId>,
    // Generation counter used to avoid spurious wakeups.
    gen: u64,
}

#[derive(Debug, Default)]
pub struct ConditionHandle {
    state: ParkMutex<ConditionState>,
    lock_cv: Condvar,
    cond_cv: Condvar,
}

pub fn condition_new() -> HxRef<ConditionHandle> {
    HxRc::new(HxCell::new(ConditionHandle::default()))
}

impl ConditionHandle {
    pub fn acquire(&self) {
        let tid = std::thread::current().id();
        let mut st = self.state.lock();
        while st.locked_by.is_some() && st.locked_by != Some(tid) {
            self.lock_cv.wait(&mut st);
        }
        st.locked_by = Some(tid);
    }

    pub fn try_acquire(&self) -> bool {
        let tid = std::thread::current().id();
        let mut st = self.state.lock();
        if st.locked_by.is_none() || st.locked_by == Some(tid) {
            st.locked_by = Some(tid);
            true
        } else {
            false
        }
    }

    pub fn release(&self) {
        let tid = std::thread::current().id();
        let mut st = self.state.lock();
        if st.locked_by != Some(tid) {
            throw_msg("Condition.release called by non-owner thread");
        }
        st.locked_by = None;
        self.lock_cv.notify_one();
    }

    pub fn wait(&self) {
        let tid = std::thread::current().id();
        let mut st = self.state.lock();
        if st.locked_by != Some(tid) {
            throw_msg("Condition.wait called without holding the internal mutex");
        }
        let my_gen = st.gen;
        st.locked_by = None;
        self.lock_cv.notify_one();
        while st.gen == my_gen {
            self.cond_cv.wait(&mut st);
        }
        while st.locked_by.is_some() && st.locked_by != Some(tid) {
            self.lock_cv.wait(&mut st);
        }
        st.locked_by = Some(tid);
    }

    pub fn signal(&self) {
        let mut st = self.state.lock();
        st.gen = st.gen.wrapping_add(1);
        self.cond_cv.notify_one();
    }

    pub fn broadcast(&self) {
        let mut st = self.state.lock();
        st.gen = st.gen.wrapping_add(1);
        self.cond_cv.notify_all();
    }
}

// ---- Semaphore ------------------------------------------------------------

#[derive(Debug, Default)]
pub struct SemaphoreHandle {
    count: ParkMutex<i32>,
    cv: Condvar,
}

pub fn semaphore_new(value: i32) -> HxRef<SemaphoreHandle> {
    HxRc::new(HxCell::new(SemaphoreHandle {
        count: ParkMutex::new(value.max(0)),
        cv: Condvar::new(),
    }))
}

impl SemaphoreHandle {
    pub fn acquire(&self) {
        let mut count = self.count.lock();
        while *count <= 0 {
            self.cv.wait(&mut count);
        }
        *count -= 1;
    }

    pub fn try_acquire(&self, timeout_seconds: Option<f64>) -> bool {
        let mut count = self.count.lock();
        if *count > 0 {
            *count -= 1;
            return true;
        }
        let Some(t) = timeout_seconds else {
            return false;
        };
        if t < 0.0 {
            return false;
        }
        let dur = Duration::from_millis((t * 1000.0).max(0.0) as u64);
        let mut remaining = dur;
        let start = std::time::Instant::now();
        while *count <= 0 {
            let timed_out = self.cv.wait_for(&mut count, remaining).timed_out();
            if *count > 0 {
                break;
            }
            if timed_out {
                return false;
            }
            let elapsed = start.elapsed();
            if elapsed >= dur {
                return false;
            }
            remaining = dur - elapsed;
        }
        *count -= 1;
        true
    }

    pub fn release(&self) {
        let mut count = self.count.lock();
        *count += 1;
        self.cv.notify_one();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering as AtomicOrdering};

    #[test]
    fn thread_spawn_can_send_to_main_queue() {
        let job: HxRc<dyn Fn() + Send + Sync> = HxRc::new(|| {
            thread_send_message(0, dynamic::from(String::from("child_ready")));
        });
        let _id = thread_spawn(job);
        let msg = thread_read_message(true);
        assert_eq!(msg.downcast::<String>().unwrap().as_str(), "child_ready");
    }

    #[test]
    fn event_loop_run_executes_on_progress() {
        let tid = NEXT_THREAD_ID.fetch_add(1, Ordering::Relaxed);
        let _ = ensure_thread_state(tid);
        let seen = HxRc::new(AtomicBool::new(false));
        let seen2 = seen.clone();
        event_loop_run(
            tid,
            HxRc::new(move || {
                seen2.store(true, AtomicOrdering::SeqCst);
            }),
        );
        assert_eq!(event_loop_progress(tid), -2.0);
        assert!(seen.load(AtomicOrdering::SeqCst));
        remove_thread_state(tid);
    }

    #[test]
    fn event_loop_repeat_clamps_zero_interval() {
        let tid = NEXT_THREAD_ID.fetch_add(1, Ordering::Relaxed);
        let _ = ensure_thread_state(tid);
        let hits = HxRc::new(AtomicUsize::new(0));
        let hits2 = hits.clone();
        let _id = event_loop_repeat(
            tid,
            HxRc::new(move || {
                hits2.fetch_add(1, AtomicOrdering::SeqCst);
            }),
            0,
        );

        // Must not hang. With a clamped interval (>= 1ms), the next scheduled time must be `At(t)`.
        let next = event_loop_progress(tid);
        assert!(
            next >= 0.0,
            "expected At(time) (>= 0.0 seconds since start), got {next}"
        );
        assert_eq!(hits.load(AtomicOrdering::SeqCst), 0);
        remove_thread_state(tid);
    }

    #[test]
    fn mutex_is_reentrant_on_same_thread() {
        let m = mutex_new();
        {
            let guard = m.borrow();
            guard.acquire();
            guard.acquire();
            guard.release();
            guard.release();
        }
    }
}
