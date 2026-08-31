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

use crate::cell::{HxDynRef, HxRc, HxRef};
use crate::dynamic::Dynamic;
use crate::{dynamic, exception};
use parking_lot::{Condvar, Mutex as ParkMutex};
use std::cell::Cell;
use std::collections::{HashMap, VecDeque};
use std::io::Write;
use std::sync::atomic::AtomicU64;
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::Duration;
use std::time::Instant;

fn throw_msg(msg: &str) -> ! {
    exception::throw(dynamic::from(crate::string::HxString::from(msg)))
}

const THREAD_NOT_ALIVE_ERROR: &str = "HXRT-THREAD-NOT-ALIVE: thread is not alive";
const THREAD_SPAWN_ERROR: &str = "HXRT-THREAD-SPAWN";
const THREAD_UNCAUGHT_ERROR: &str = "HXRT-THREAD-UNCAUGHT";
const EVENT_LOOP_PROMISE_UNDERFLOW_ERROR: &str =
    "HXRT-EVENTLOOP-PROMISE-UNDERFLOW: runPromised requires one unmatched promise";
const EVENT_LOOP_PROMISE_OVERFLOW_ERROR: &str =
    "HXRT-EVENTLOOP-PROMISE-OVERFLOW: promise count exceeded the runtime limit";

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

/// Own a spawned thread's registration for exactly the callback/event-loop lifetime.
///
/// Why
/// - A Haxe `throw` and an unexpected Rust panic both unwind the spawned OS thread.
/// - Ordinary cleanup after the callback is skipped during unwind, leaving a dead thread in the
///   global registry and accepting messages that can never be read.
///
/// What
/// - Removes one non-main thread id from the registry when the registered execution scope ends.
///
/// How
/// - Rust drops this guard on normal return and during panic unwinding. It deliberately owns no
///   callback or queue value, so cleanup cannot retain application state.
struct ThreadRegistrationGuard {
    id: i32,
}

impl ThreadRegistrationGuard {
    fn new(id: i32) -> Self {
        Self { id }
    }
}

impl Drop for ThreadRegistrationGuard {
    fn drop(&mut self) {
        remove_thread_state(self.id);
    }
}

/// Report an uncaught Haxe exception without converting a child-only failure into a Rust panic.
///
/// The public `Thread` API has no join/result channel, so an uncaught callback exception terminates
/// only that child. Reporting is best-effort: a broken stderr must not panic while handling another
/// failure. The identifier is stable; the payload's human-readable formatting is not.
fn report_uncaught_thread_exception(error: &Dynamic) {
    let stderr = std::io::stderr();
    let mut handle = stderr.lock();
    let _ = writeln!(handle, "[{THREAD_UNCAUGHT_ERROR}] {error}");
}

/// Run one registered spawned-thread lifecycle.
///
/// Why
/// - Plain threads and event-loop threads need identical liveness and uncaught-exception behavior.
///
/// What
/// - Installs the thread-local id, owns the registry guard, runs the job, optionally drains the
///   thread EventLoop, and reports an uncaught Haxe exception.
///
/// How
/// - `exception::catch_unwind` consumes only Haxe throw payloads. A non-Haxe Rust panic is resumed,
///   while `ThreadRegistrationGuard` still removes the dead registration during unwind.
/// - The guard scope ends before best-effort diagnostic I/O, so reporting cannot extend liveness.
fn run_registered_thread(id: i32, job: HxRc<dyn Fn() + Send + Sync>, with_event_loop: bool) {
    CURRENT_THREAD_ID.with(|current| current.set(id));
    let outcome = {
        let _registration = ThreadRegistrationGuard::new(id);
        exception::catch_unwind(|| {
            job();
            if with_event_loop {
                event_loop_loop(id);
            }
        })
    };
    if let Err(error) = outcome {
        report_uncaught_thread_exception(&error);
    }
}

fn spawn_registered_thread(job: HxRc<dyn Fn() + Send + Sync>, with_event_loop: bool) -> i32 {
    let id = NEXT_THREAD_ID.fetch_add(1, Ordering::Relaxed);
    let _ = ensure_thread_state(id);
    let spawn = std::thread::Builder::new().spawn(move || {
        run_registered_thread(id, job, with_event_loop);
    });
    if let Err(error) = spawn {
        remove_thread_state(id);
        throw_msg(&format!("{THREAD_SPAWN_ERROR}: {error}"));
    }
    id
}

pub fn thread_current_id() -> i32 {
    CURRENT_THREAD_ID.with(|c| c.get())
}

pub fn thread_spawn(job: HxDynRef<dyn Fn() + Send + Sync>) -> i32 {
    let job: HxRc<dyn Fn() + Send + Sync> = match job.as_arc_opt() {
        Some(rc) => rc.clone(),
        None => throw_msg("Null Access"),
    };
    spawn_registered_thread(job, false)
}

pub fn thread_spawn_with_event_loop(job: HxDynRef<dyn Fn() + Send + Sync>) -> i32 {
    let job: HxRc<dyn Fn() + Send + Sync> = match job.as_arc_opt() {
        Some(rc) => rc.clone(),
        None => throw_msg("Null Access"),
    };
    spawn_registered_thread(job, true)
}

pub fn thread_send_message(thread_id: i32, msg: Dynamic) {
    let state = {
        let map = threads().lock();
        map.get(&thread_id).cloned()
    };
    let Some(state) = state else {
        throw_msg(THREAD_NOT_ALIVE_ERROR);
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
    promised: u32,
    regular: Vec<RegularEvent>, // kept sorted by `next_run`
}

fn with_thread_state_or_throw<R>(thread_id: i32, f: impl FnOnce(&Arc<ThreadState>) -> R) -> R {
    let state = {
        let map = threads().lock();
        map.get(&thread_id).cloned()
    };
    let Some(state) = state else {
        throw_msg(THREAD_NOT_ALIVE_ERROR);
    };
    f(&state)
}

pub fn event_loop_promise(thread_id: i32) {
    with_thread_state_or_throw(thread_id, |state| {
        let mut st = state.events.lock();
        let Some(next) = st.promised.checked_add(1) else {
            drop(st);
            throw_msg(EVENT_LOOP_PROMISE_OVERFLOW_ERROR);
        };
        st.promised = next;
    });
}

pub fn event_loop_run(thread_id: i32, event: HxDynRef<dyn Fn() + Send + Sync>) {
    let event: HxRc<dyn Fn() + Send + Sync> = match event.as_arc_opt() {
        Some(rc) => rc.clone(),
        None => throw_msg("Null Access"),
    };
    with_thread_state_or_throw(thread_id, |state| {
        let mut st = state.events.lock();
        st.one_time.push_back(event);
        state.events_cv.notify_one();
    });
}

pub fn event_loop_run_promised(thread_id: i32, event: HxDynRef<dyn Fn() + Send + Sync>) {
    let event: HxRc<dyn Fn() + Send + Sync> = match event.as_arc_opt() {
        Some(rc) => rc.clone(),
        None => throw_msg("Null Access"),
    };
    with_thread_state_or_throw(thread_id, |state| {
        let mut st = state.events.lock();
        if st.promised == 0 {
            drop(st);
            throw_msg(EVENT_LOOP_PROMISE_UNDERFLOW_ERROR);
        }
        st.one_time.push_back(event);
        st.promised -= 1;
        state.events_cv.notify_one();
    });
}

pub fn event_loop_repeat(
    thread_id: i32,
    event: HxDynRef<dyn Fn() + Send + Sync>,
    interval_ms: i32,
) -> i32 {
    let event: HxRc<dyn Fn() + Send + Sync> = match event.as_arc_opt() {
        Some(rc) => rc.clone(),
        None => throw_msg("Null Access"),
    };
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
        state.events_cv.notify_one();
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
    let mut regular_to_run: Vec<(u64, HxRc<dyn Fn() + Send + Sync>)> = Vec::new();
    let mut next_at: f64 = -1.0;
    let mut promised: u32 = 0;
    let now = now_seconds();

    with_thread_state_or_throw(thread_id, |state| {
        let mut st = state.events.lock();

        // Advance every due repeat exactly once before callbacks run. This mirrors the upstream
        // Haxe EventLoop transition: a callback throw propagates, but does not silently delete its
        // repeating registration. Advancing from the prior deadline preserves cadence without
        // running the same overdue event more than once in this progress pass.
        let due_count = st
            .regular
            .iter()
            .take_while(|event| event.next_run <= now)
            .count();
        for event in st.regular.iter_mut().take(due_count) {
            regular_to_run.push((event.id, event.callback.clone()));
            event.next_run += event.interval;
        }
        st.regular
            .sort_by(|left, right| left.next_run.total_cmp(&right.next_run));
    });

    for (event_id, event) in regular_to_run.iter() {
        let still_registered = with_thread_state_or_throw(thread_id, |state| {
            state
                .events
                .lock()
                .regular
                .iter()
                .any(|candidate| candidate.id == *event_id)
        });
        if still_registered {
            event();
        }
    }

    let mut one_time_to_run: Vec<HxRc<dyn Fn() + Send + Sync>> = Vec::new();
    with_thread_state_or_throw(thread_id, |state| {
        let mut st = state.events.lock();
        while let Some(event) = st.one_time.pop_front() {
            one_time_to_run.push(event);
        }
        promised = st.promised;
        next_at = st
            .regular
            .first()
            .map(|event| event.next_run)
            .unwrap_or(-1.0);
    });

    for event in one_time_to_run.iter() {
        event();
    }

    if !regular_to_run.is_empty() || !one_time_to_run.is_empty() {
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
    HxRef::new(LockHandle::default())
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
    HxRef::new(MutexHandle::default())
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
    HxRef::new(ConditionHandle::default())
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
    HxRef::new(SemaphoreHandle {
        count: ParkMutex::new(value.max(0)),
        cv: Condvar::new(),
    })
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

    fn test_thread_id() -> i32 {
        let id = NEXT_THREAD_ID.fetch_add(1, Ordering::Relaxed);
        let _ = ensure_thread_state(id);
        id
    }

    fn assert_haxe_error_prefix(error: Dynamic, prefix: &str) {
        let message = error.to_haxe_string();
        assert!(
            message.starts_with(prefix),
            "expected error prefix {prefix:?}, got {message:?}"
        );
    }

    #[test]
    fn thread_registration_guard_removes_state_on_rust_unwind() {
        let id = test_thread_id();
        let unwind = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _registration = ThreadRegistrationGuard::new(id);
            panic!("injected child panic");
        }));
        assert!(unwind.is_err());
        assert!(!threads().lock().contains_key(&id));
    }

    #[test]
    fn thread_spawn_can_send_to_main_queue() {
        let job_rc: HxRc<dyn Fn() + Send + Sync> = HxRc::new(|| {
            thread_send_message(0, dynamic::from(String::from("child_ready")));
        });
        let job: HxDynRef<dyn Fn() + Send + Sync> = HxDynRef::new(job_rc);
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
        let event_rc: HxRc<dyn Fn() + Send + Sync> = HxRc::new(move || {
            seen2.store(true, AtomicOrdering::SeqCst);
        });
        event_loop_run(tid, HxDynRef::new(event_rc));
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
        let event_rc: HxRc<dyn Fn() + Send + Sync> = HxRc::new(move || {
            hits2.fetch_add(1, AtomicOrdering::SeqCst);
        });
        let _id = event_loop_repeat(tid, HxDynRef::new(event_rc), 0);

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
    fn event_loop_repeat_cancel_from_callback_stops_requeue() {
        let tid = NEXT_THREAD_ID.fetch_add(1, Ordering::Relaxed);
        let _ = ensure_thread_state(tid);
        let hits = HxRc::new(AtomicUsize::new(0));
        let event_id = HxRef::new(None::<i32>);

        let hits2 = hits.clone();
        let event_id2 = event_id.clone();
        let event_rc: HxRc<dyn Fn() + Send + Sync> = HxRc::new(move || {
            let seen = hits2.fetch_add(1, AtomicOrdering::SeqCst) + 1;
            if seen == 2 {
                let id =
                    (*event_id2.borrow()).expect("event id must be assigned before callback runs");
                event_loop_cancel(tid, id);
            }
        });

        let id = event_loop_repeat(tid, HxDynRef::new(event_rc), 1);
        *event_id.borrow_mut() = Some(id);

        std::thread::sleep(Duration::from_millis(10));
        assert_eq!(event_loop_progress(tid), -2.0);
        std::thread::sleep(Duration::from_millis(5));
        assert_eq!(event_loop_progress(tid), -2.0);
        std::thread::sleep(Duration::from_millis(5));
        assert_eq!(event_loop_progress(tid), -1.0);
        assert_eq!(hits.load(AtomicOrdering::SeqCst), 2);

        remove_thread_state(tid);
    }

    #[test]
    fn event_loop_repeat_survives_haxe_throw_and_can_cancel_next_run() {
        let tid = test_thread_id();
        let hits = HxRc::new(AtomicUsize::new(0));
        let event_id = HxRef::new(None::<i32>);
        let hits2 = hits.clone();
        let event_id2 = event_id.clone();
        let event_rc: HxRc<dyn Fn() + Send + Sync> = HxRc::new(move || {
            let seen = hits2.fetch_add(1, AtomicOrdering::SeqCst) + 1;
            if seen == 1 {
                exception::throw(dynamic::from(String::from("repeat failure")));
            }
            let id = (*event_id2.borrow()).expect("repeat id must be initialized");
            event_loop_cancel(tid, id);
        });
        let id = event_loop_repeat(tid, HxDynRef::new(event_rc), 1);
        *event_id.borrow_mut() = Some(id);

        std::thread::sleep(Duration::from_millis(5));
        let first = exception::catch_unwind(|| event_loop_progress(tid));
        assert_haxe_error_prefix(
            first.expect_err("first repeat callback must throw"),
            "repeat failure",
        );

        std::thread::sleep(Duration::from_millis(5));
        assert_eq!(event_loop_progress(tid), -2.0);
        assert_eq!(hits.load(AtomicOrdering::SeqCst), 2);
        assert_eq!(event_loop_progress(tid), -1.0);
        remove_thread_state(tid);
    }

    #[test]
    fn event_loop_cancel_then_throw_leaves_no_regular_state() {
        let tid = test_thread_id();
        let event_id = HxRef::new(None::<i32>);
        let event_id2 = event_id.clone();
        let event_rc: HxRc<dyn Fn() + Send + Sync> = HxRc::new(move || {
            let id = (*event_id2.borrow()).expect("repeat id must be initialized");
            event_loop_cancel(tid, id);
            exception::throw(dynamic::from(String::from("cancel failure")));
        });
        let id = event_loop_repeat(tid, HxDynRef::new(event_rc), 1);
        *event_id.borrow_mut() = Some(id);

        std::thread::sleep(Duration::from_millis(5));
        let thrown = exception::catch_unwind(|| event_loop_progress(tid));
        assert_haxe_error_prefix(
            thrown.expect_err("cancel callback must throw"),
            "cancel failure",
        );
        let state = ensure_thread_state(tid);
        assert!(state.events.lock().regular.is_empty());
        remove_thread_state(tid);
    }

    #[test]
    fn event_loop_run_promised_rejects_underflow_without_queueing() {
        let tid = test_thread_id();
        let ran = HxRc::new(AtomicBool::new(false));
        let ran2 = ran.clone();
        let event_rc: HxRc<dyn Fn() + Send + Sync> = HxRc::new(move || {
            ran2.store(true, AtomicOrdering::SeqCst);
        });

        let underflow = exception::catch_unwind(|| {
            event_loop_run_promised(tid, HxDynRef::new(event_rc));
        });
        assert_haxe_error_prefix(
            underflow.expect_err("unmatched runPromised must fail"),
            "HXRT-EVENTLOOP-PROMISE-UNDERFLOW",
        );
        assert_eq!(event_loop_progress(tid), -1.0);
        assert!(!ran.load(AtomicOrdering::SeqCst));
        let state = ensure_thread_state(tid);
        let events = state.events.lock();
        assert_eq!(events.promised, 0);
        assert!(events.one_time.is_empty());
        drop(events);
        remove_thread_state(tid);
    }

    #[test]
    fn event_loop_promised_callback_throw_consumes_exactly_one_promise() {
        let tid = test_thread_id();
        event_loop_promise(tid);
        let event_rc: HxRc<dyn Fn() + Send + Sync> = HxRc::new(move || {
            exception::throw(dynamic::from(String::from("promised failure")));
        });
        event_loop_run_promised(tid, HxDynRef::new(event_rc));

        let thrown = exception::catch_unwind(|| event_loop_progress(tid));
        assert_haxe_error_prefix(
            thrown.expect_err("promised callback must throw"),
            "promised failure",
        );
        assert_eq!(event_loop_progress(tid), -1.0);
        let state = ensure_thread_state(tid);
        assert_eq!(state.events.lock().promised, 0);
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
