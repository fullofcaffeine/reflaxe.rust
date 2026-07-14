use hxrt::cell::{HxRc, HxRef};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

#[derive(Debug)]
struct DropProbe {
    drops: Arc<AtomicUsize>,
}

impl Drop for DropProbe {
    fn drop(&mut self) {
        self.drops.fetch_add(1, Ordering::SeqCst);
    }
}

#[derive(Debug)]
struct CycleNode {
    next: HxRef<CycleNode>,
    drops: Arc<AtomicUsize>,
}

impl Drop for CycleNode {
    fn drop(&mut self) {
        self.drops.fetch_add(1, Ordering::SeqCst);
    }
}

/// Why: aliasing, identity, and shared mutation are the observable Haxe contract rather than the
/// current `Arc`/lock representation.
/// What: cloning a handle preserves pointer identity and exposes one shared payload.
/// How: mutate through one alias and read through the other without inspecting layout.
#[test]
fn hxref_contract_aliases_share_identity_and_mutation() {
    let original = HxRef::new(vec![1_i32]);
    let alias = original.clone();
    let distinct = HxRef::new(vec![1_i32]);

    assert!(original.ptr_eq(&alias));
    assert!(!original.ptr_eq(&distinct));
    alias.borrow_mut().push(2);
    assert_eq!(&*original.borrow(), &[1, 2]);
}

/// Why: ordinary acyclic Haxe reference graphs must retain Rust's deterministic owner cleanup.
/// What: the payload drops once, and only after the final strong handle is released.
/// How: use a `Drop` counter and a weak observer rather than timing or process-memory sampling.
#[test]
fn hxref_contract_acyclic_payload_drops_after_last_owner() {
    let drops = Arc::new(AtomicUsize::new(0));
    let original = HxRef::new(DropProbe {
        drops: drops.clone(),
    });
    let weak = HxRc::downgrade(original.as_arc_opt().expect("non-null HxRef"));
    let alias = original.clone();

    drop(original);
    assert_eq!(drops.load(Ordering::SeqCst), 0);
    assert!(weak.upgrade().is_some());

    drop(alias);
    assert_eq!(drops.load(Ordering::SeqCst), 1);
    assert!(weak.upgrade().is_none());
}

/// Why: reference-counted handles deliberately do not pretend to provide tracing-GC cycle
/// collection; production users need an executable boundary rather than an RSS heuristic.
/// What: a two-node strong cycle remains alive after external handles drop, then releases after an
/// explicit break of both strong edges.
/// How: weak observers prove retention without adding a runtime inspection API, and the test breaks
/// the cycle before exit so its own evidence does not leak.
#[test]
fn hxref_contract_strong_cycle_is_retained_until_explicitly_broken() {
    let drops = Arc::new(AtomicUsize::new(0));
    let left = HxRef::new(CycleNode {
        next: HxRef::null(),
        drops: drops.clone(),
    });
    let right = HxRef::new(CycleNode {
        next: HxRef::null(),
        drops: drops.clone(),
    });
    let left_weak = HxRc::downgrade(left.as_arc_opt().expect("non-null left HxRef"));
    let right_weak = HxRc::downgrade(right.as_arc_opt().expect("non-null right HxRef"));

    left.borrow_mut().next = right.clone();
    right.borrow_mut().next = left.clone();
    drop(left);
    drop(right);

    assert_eq!(drops.load(Ordering::SeqCst), 0);
    let retained_left = HxRef::from(left_weak.upgrade().expect("strong cycle retains left"));
    let retained_right = HxRef::from(right_weak.upgrade().expect("strong cycle retains right"));

    retained_left.borrow_mut().next = HxRef::null();
    retained_right.borrow_mut().next = HxRef::null();
    drop(retained_left);
    drop(retained_right);

    assert_eq!(drops.load(Ordering::SeqCst), 2);
    assert!(left_weak.upgrade().is_none());
    assert!(right_weak.upgrade().is_none());
}
