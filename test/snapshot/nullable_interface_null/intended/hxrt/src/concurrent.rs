//! Rust-native concurrency helpers for `std/rust/concurrent/*`.
//!
//! Why
//! - `sys.thread.*` provides Haxe-portable threading semantics.
//! - Rust-first code also needs a typed, idiomatic layer for channels/tasks/locks without
//!   dropping into raw injection from application code.
//!
//! What
//! - `ChannelHandle<T>`: typed MPSC channel helper (`send`/`recv`/`try_recv`).
//! - `TaskHandle<T>`: spawn + join one-shot thread tasks.
//! - `MutexHandle<T>` / `RwLockHandle<T>`: closure-scoped lock helpers.
//!
//! How
//! - Runtime values are wrapped in `HxRef<...>` so they follow nullable/shared semantics expected
//!   by generated Haxe code.
//! - Callback-based lock helpers avoid leaking Rust guard lifetimes into Haxe code.

use crate::cell::{HxDynRef, HxRc, HxRef};
use crate::{dynamic, exception};
use parking_lot::{Mutex as ParkMutex, RwLock as ParkRwLock};
use std::sync::mpsc;

fn throw_msg(msg: &str) -> ! {
    exception::throw(dynamic::from(String::from(msg)))
}

/// Typed multi-producer, single-consumer channel handle.
#[derive(Debug)]
pub struct ChannelHandle<T> {
    sender: mpsc::Sender<T>,
    receiver: ParkMutex<mpsc::Receiver<T>>,
}

/// One-shot task join handle.
#[derive(Debug)]
pub struct TaskHandle<T> {
    join: ParkMutex<Option<std::thread::JoinHandle<T>>>,
}

/// Shared mutex-backed value.
#[derive(Debug)]
pub struct MutexHandle<T> {
    value: ParkMutex<T>,
}

/// Shared read/write-locked value.
#[derive(Debug)]
pub struct RwLockHandle<T> {
    value: ParkRwLock<T>,
}

pub fn channel_new<T>() -> HxRef<ChannelHandle<T>> {
    let (sender, receiver) = mpsc::channel::<T>();
    HxRef::new(ChannelHandle {
        sender,
        receiver: ParkMutex::new(receiver),
    })
}

pub fn channel_send<T>(channel: &HxRef<ChannelHandle<T>>, value: T) {
    let sender = {
        let channel_borrow = channel.borrow();
        channel_borrow.sender.clone()
    };
    if sender.send(value).is_err() {
        throw_msg("Channel is disconnected");
    }
}

pub fn channel_recv<T>(channel: &HxRef<ChannelHandle<T>>) -> T {
    let recv_result = {
        let channel_borrow = channel.borrow();
        let receiver = channel_borrow.receiver.lock();
        receiver.recv()
    };
    match recv_result {
        Ok(value) => value,
        Err(_) => throw_msg("Channel is disconnected"),
    }
}

pub fn channel_try_recv<T>(channel: &HxRef<ChannelHandle<T>>) -> Option<T> {
    let recv_result = {
        let channel_borrow = channel.borrow();
        let receiver = channel_borrow.receiver.lock();
        receiver.try_recv()
    };
    match recv_result {
        Ok(value) => Some(value),
        Err(mpsc::TryRecvError::Empty) => None,
        Err(mpsc::TryRecvError::Disconnected) => throw_msg("Channel is disconnected"),
    }
}

pub fn task_spawn<T>(job: HxDynRef<dyn Fn() -> T + Send + Sync>) -> HxRef<TaskHandle<T>>
where
    T: Send + 'static,
{
    let job: HxRc<dyn Fn() -> T + Send + Sync> = match job.as_arc_opt() {
        Some(rc) => rc.clone(),
        None => throw_msg("Null Access"),
    };

    let join = std::thread::spawn(move || job());
    HxRef::new(TaskHandle {
        join: ParkMutex::new(Some(join)),
    })
}

pub fn task_join<T>(task: &HxRef<TaskHandle<T>>) -> T {
    let join = {
        let task_borrow = task.borrow();
        let mut slot = task_borrow.join.lock();
        match slot.take() {
            Some(join) => join,
            None => throw_msg("Task already joined"),
        }
    };

    match join.join() {
        Ok(value) => value,
        Err(_) => throw_msg("Task panicked"),
    }
}

pub fn mutex_new<T>(value: T) -> HxRef<MutexHandle<T>> {
    HxRef::new(MutexHandle {
        value: ParkMutex::new(value),
    })
}

pub fn mutex_get<T>(mutex: &HxRef<MutexHandle<T>>) -> T
where
    T: Clone,
{
    let mutex_borrow = mutex.borrow();
    let guard = mutex_borrow.value.lock();
    guard.clone()
}

pub fn mutex_set<T>(mutex: &HxRef<MutexHandle<T>>, value: T) {
    let mutex_borrow = mutex.borrow();
    let mut guard = mutex_borrow.value.lock();
    *guard = value;
}

pub fn mutex_replace<T>(mutex: &HxRef<MutexHandle<T>>, value: T) -> T {
    let mutex_borrow = mutex.borrow();
    let mut guard = mutex_borrow.value.lock();
    std::mem::replace(&mut *guard, value)
}

pub fn mutex_update<T>(
    mutex: &HxRef<MutexHandle<T>>,
    callback: HxDynRef<dyn Fn(T) -> T + Send + Sync>,
) -> T
where
    T: Clone,
{
    let callback: HxRc<dyn Fn(T) -> T + Send + Sync> = match callback.as_arc_opt() {
        Some(rc) => rc.clone(),
        None => throw_msg("Null Access"),
    };
    let mutex_borrow = mutex.borrow();
    let mut guard = mutex_borrow.value.lock();
    let next = callback(guard.clone());
    *guard = next.clone();
    next
}

pub fn rw_lock_new<T>(value: T) -> HxRef<RwLockHandle<T>>
where
    T: Send + Sync,
{
    HxRef::new(RwLockHandle {
        value: ParkRwLock::new(value),
    })
}

pub fn rw_lock_read<T>(lock: &HxRef<RwLockHandle<T>>) -> T
where
    T: Clone + Send + Sync,
{
    let lock_borrow = lock.borrow();
    let guard = lock_borrow.value.read();
    guard.clone()
}

pub fn rw_lock_write<T>(lock: &HxRef<RwLockHandle<T>>, value: T)
where
    T: Send + Sync,
{
    let lock_borrow = lock.borrow();
    let mut guard = lock_borrow.value.write();
    *guard = value;
}

pub fn rw_lock_replace<T>(lock: &HxRef<RwLockHandle<T>>, value: T) -> T
where
    T: Send + Sync,
{
    let lock_borrow = lock.borrow();
    let mut guard = lock_borrow.value.write();
    std::mem::replace(&mut *guard, value)
}

pub fn rw_lock_update<T>(
    lock: &HxRef<RwLockHandle<T>>,
    callback: HxDynRef<dyn Fn(T) -> T + Send + Sync>,
) -> T
where
    T: Clone + Send + Sync,
{
    let callback: HxRc<dyn Fn(T) -> T + Send + Sync> = match callback.as_arc_opt() {
        Some(rc) => rc.clone(),
        None => throw_msg("Null Access"),
    };
    let lock_borrow = lock.borrow();
    let mut guard = lock_borrow.value.write();
    let next = callback(guard.clone());
    *guard = next.clone();
    next
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn channel_roundtrip() {
        let channel = channel_new::<i32>();
        channel_send(&channel, 7);
        assert_eq!(channel_try_recv(&channel), Some(7));
        assert_eq!(channel_try_recv(&channel), None);
    }

    #[test]
    fn task_spawn_join() {
        let job_rc: HxRc<dyn Fn() -> i32 + Send + Sync> = HxRc::new(|| 42);
        let task = task_spawn(HxDynRef::new(job_rc));
        assert_eq!(task_join(&task), 42);
    }

    #[test]
    fn mutex_with_lock_mutates() {
        let mutex = mutex_new::<i32>(1);
        let inc_rc: HxRc<dyn Fn(i32) -> i32 + Send + Sync> = HxRc::new(|value: i32| value + 4);
        let out = mutex_update(&mutex, HxDynRef::new(inc_rc));
        assert_eq!(out, 5);
        assert_eq!(mutex_get(&mutex), 5);
        assert_eq!(mutex_replace(&mutex, 9), 5);
    }

    #[test]
    fn rw_lock_read_write_roundtrip() {
        let lock = rw_lock_new::<i32>(3);
        assert_eq!(rw_lock_read(&lock), 3);
        rw_lock_write(&lock, 6);
        assert_eq!(rw_lock_read(&lock), 6);
        assert_eq!(rw_lock_replace(&lock, 10), 6);
        let update_rc: HxRc<dyn Fn(i32) -> i32 + Send + Sync> = HxRc::new(|value: i32| value + 2);
        let out = rw_lock_update(&lock, HxDynRef::new(update_rc));
        assert_eq!(out, 12);
    }
}
