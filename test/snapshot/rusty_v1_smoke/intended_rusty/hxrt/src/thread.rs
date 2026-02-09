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
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::Duration;

fn throw_msg(msg: &str) -> ! {
    exception::throw(dynamic::from(String::from(msg)))
}

// ---- Threads + messages ----------------------------------------------------

#[derive(Debug)]
struct ThreadState {
    queue: ParkMutex<VecDeque<Dynamic>>,
    cv: Condvar,
}

impl ThreadState {
    fn new() -> Self {
        Self {
            queue: ParkMutex::new(VecDeque::new()),
            cv: Condvar::new(),
        }
    }
}

static NEXT_THREAD_ID: AtomicI32 = AtomicI32::new(1);
static THREADS: OnceLock<ParkMutex<HashMap<i32, Arc<ThreadState>>>> = OnceLock::new();

thread_local! {
    static CURRENT_THREAD_ID: Cell<i32> = const { Cell::new(0) };
}

fn threads() -> &'static ParkMutex<HashMap<i32, Arc<ThreadState>>> {
    THREADS.get_or_init(|| ParkMutex::new(HashMap::new()))
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
