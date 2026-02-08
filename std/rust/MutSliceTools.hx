package rust;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypeTools;
#end

/**
 * MutSliceTools
 *
 * Borrow-first helpers for `rust.MutSlice<T>` (mutable `&mut [T]`).
 *
 * Why:
 * - We want to mutate Rust data structures without cloning/moving in app code.
 * - TUIs and other systems code often benefits from in-place mutation.
 *
 * What:
 * - A small set of helpers for common operations (`len`, `get`, `set`) plus a macro helper (`with`)
 *   to create a short-lived mutable slice.
 *
 * How:
 * - The `with(...)` macro expands to `rust.Borrow.withMut(...)` and casts the borrow to `MutSlice<T>`.
 * - Non-trivial Rust operations live behind `untyped __rust__` in non-inline functions (framework code).
 */
class MutSliceTools {
	/**
	 * Borrow a `Vec<T>` or `Array<T>` as a `rust.MutSlice<T>` for the duration of the callback.
	 *
	 * Example:
	 * ```haxe
	 * var v = new rust.Vec<Int>();
	 * v.push(1); v.push(2);
	 *
	 * rust.MutSliceTools.with(v, s -> {
	 *   rust.MutSliceTools.set(s, 0, 10);
	 * });
	 * ```
	 *
	 * IMPORTANT:
	 * - This is Rusty/profile-oriented; keep the borrow inside the callback.
	 * - Avoid returning or storing the `MutSlice<T>` outside the callback.
	 *
	 * Implementation notes:
	 * - For `rust.Vec<T>`, this expands to `rust.Borrow.withMut(...)` and **inlines** the callback body.
	 * - For `Array<T>`, this delegates to `rust.ArrayBorrow.withMutSlice(...)`, which calls into the runtime
	 *   to borrow the underlying storage as `&mut [T]` **without cloning**.
	 *
	 * Borrow rules:
	 * - Keep the slice inside the callback; never store/return it.
	 * - Avoid nested borrows of the same array; `RefCell` will panic on invalid re-borrows.
	 */
	public static macro function with(value: Expr, fn: Expr): Expr {
		#if macro
		var f = switch (fn.expr) {
			case EFunction(_, f): f;
			case _:
				Context.error("MutSliceTools.with expects a function expression: (s) -> { ... }", fn.pos);
				return macro null;
		}

		if (f.args.length != 1) {
			Context.error("MutSliceTools.with callback must take exactly one argument", fn.pos);
		}

		var typedValue = Context.typeExpr(value);
		var valueIsArray = false;
		var elemT: Null<Type> = switch (TypeTools.follow(typedValue.t)) {
			case TInst(clsRef, params): {
				var cls = clsRef.get();
				// Array<T>
				if (cls != null && cls.pack.length == 0 && cls.module == "Array" && cls.name == "Array" && params.length == 1) {
					valueIsArray = true;
					params[0];
				} else if (cls != null && cls.isExtern && cls.pack.join(".") == "rust" && cls.name == "Vec" && params.length == 1) {
					params[0];
				} else {
					null;
				}
			}
			case _:
				null;
		}

		if (elemT == null) {
			Context.error("MutSliceTools.with only supports rust.Vec<T> or Array<T> values", value.pos);
		}

		var elemCt = TypeTools.toComplexType(elemT);
		var argName = f.args[0].name;

		// Expand to:
		// `rust.Borrow.withMut(value, r -> { var s: rust.MutSlice<T> = cast r; body; })`
		var decl: Expr = {
			expr: EVars([{
				name: argName,
				type: TPath({
					pack: ["rust"],
					name: "MutSlice",
					params: [TPType(elemCt)]
				}),
				expr: { expr: ECast({ expr: EConst(CIdent("__hx_ref")), pos: fn.pos }, null), pos: fn.pos }
			}]),
			pos: fn.pos
		};

		if (valueIsArray) {
			// For `Array<T>`, borrow the underlying Vec as a mutable slice without cloning.
			// This delegates to `rust.ArrayBorrow`, which calls into `hxrt::array::with_mut_slice(...)`.
			var sliceParam = "__hx_slice";
			var arrayDecl: Expr = {
				expr: EVars([{
					name: argName,
					type: TPath({
						pack: ["rust"],
						name: "MutSlice",
						params: [TPType(elemCt)]
					}),
					expr: { expr: ECast({ expr: EConst(CIdent(sliceParam)), pos: fn.pos }, null), pos: fn.pos }
				}]),
				pos: fn.pos
			};

			return macro rust.ArrayBorrow.withMutSlice($value, function(__hx_slice) {
				$arrayDecl;
				${f.expr};
			});
		}

		return macro rust.Borrow.withMut($value, function(__hx_ref) {
			$decl;
			${f.expr};
		});
		#else
		return macro null;
		#end
	}

	#if !macro
	public static function len<T>(s: MutSlice<T>): Int {
		return untyped __rust__("{0}.len() as i32", s);
	}

	public static function get<T>(s: MutSlice<T>, index: Int): Option<Ref<T>> {
		return untyped __rust__("{0}.get({1} as usize)", s, index);
	}

	public static function set<T>(s: MutSlice<T>, index: Int, value: T): Void {
		untyped __rust__("{0}[{1} as usize] = {2};", s, index, value);
	}
	#else
	// Macro compilation stubs: these are only used in Rust output, never during macro typing/execution.
	public static function len<T>(s: MutSlice<T>): Int return 0;
	public static function get<T>(s: MutSlice<T>, index: Int): Option<Ref<T>> return None;
	public static function set<T>(s: MutSlice<T>, index: Int, value: T): Void {}
	#end
}
