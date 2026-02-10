#[cfg(test)]
mod tests {
    use hxrt::bytes;

    fn hx_bytes_from_str(s: &str) -> crate::HxRef<hxrt::bytes::Bytes> {
        crate::HxRef::new(hxrt::bytes::Bytes::of_string(s))
    }

    #[test]
    fn bytes_get_set_sub_get_string_blit() {
        let b = hx_bytes_from_str("hello");
        assert_eq!(b.borrow().length(), 5);
        assert_eq!(b.borrow().get(0), 'h' as i32);
        assert_eq!(b.borrow().get_string(1, 3), "ell");
        assert_eq!(b.borrow().sub(1, 3).to_string(), "ell");

        let out: crate::HxRef<hxrt::bytes::Bytes> = crate::HxRef::new(hxrt::bytes::Bytes::alloc(5));
        bytes::blit(&out, 0, &b, 0, 5);
        assert_eq!(out.borrow().to_string(), "hello");

        out.borrow_mut().set(0, 'H' as i32);
        assert_eq!(out.borrow().to_string(), "Hello");
    }

    #[test]
    fn bytes_oob_is_catchable_haxe_throw() {
        let b = hx_bytes_from_str("hi");

        let r = hxrt::exception::catch_unwind(|| b.borrow().get(99));
        let err = r.expect_err("expected hxrt::exception::throw to be caught");
        let boxed = err
            .downcast::<hxrt::io::Error>()
            .expect("expected hxrt::io::Error payload");
        assert!(matches!(*boxed, hxrt::io::Error::OutsideBounds));

        let out: crate::HxRef<hxrt::bytes::Bytes> = crate::HxRef::new(hxrt::bytes::Bytes::alloc(2));
        let r2 = hxrt::exception::catch_unwind(|| bytes::blit(&out, 0, &b, 0, 99));
        let err2 = r2.expect_err("expected blit oob to be caught");
        let boxed2 = err2
            .downcast::<hxrt::io::Error>()
            .expect("expected hxrt::io::Error payload");
        assert!(matches!(*boxed2, hxrt::io::Error::OutsideBounds));
    }
}
