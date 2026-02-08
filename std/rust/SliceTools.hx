package rust;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypeTools;
#end

/**
 * SliceTools
 *
 * Helpers for working with `rust.Slice<T>` without `__rust__` in apps.
 *
 * IMPORTANT: keep these as non-inline so injections stay in framework code.
 */
class SliceTools {
	/**
	 * Convert a borrowed `&Vec<T>` into a borrowed slice (`&[T]`).
	 *
	 * Why:
	 * - Rust has an implicit coercion from `&Vec<T>` to `&[T]`.
	 * - Keeping this conversion injection-free lets app code stay “pure Haxe”.
	 *
	 * How:
	 * - In Rust output, this is a no-op expression and relies on Rust's deref coercions.
	 */
	public static inline function fromVec<T>(v: Ref<Vec<T>>): Slice<T> {
		return cast v;
	}

	/**
	 * Borrow a `Vec<T>` or `Array<T>` as a `rust.Slice<T>` for the duration of the callback.
	 *
	 * This is the slice equivalent of `rust.StrTools.with(...)`.
	 *
	 * Implementation notes:
	 * - For `rust.Vec<T>`, this expands to `rust.Borrow.withRef(...)` and **inlines** the callback body
	 *   (no closure allocation).
	 * - For `Array<T>`, this delegates to `rust.ArrayBorrow.withSlice(...)`, which calls into the runtime
	 *   to borrow the underlying storage as `&[T]` **without cloning**.
	 *
	 * Borrow rules:
	 * - Keep the slice inside the callback; never store/return it.
	 * - Avoid nested borrows of the same array (the runtime uses `RefCell` and will panic on invalid re-borrows).
	 */
	public static macro function with(value: Expr, fn: Expr): Expr {
		#if macro
		var f = switch (fn.expr) {
			case EFunction(_, f): f;
			case _:
				Context.error("SliceTools.with expects a function expression: (s) -> { ... }", fn.pos);
				return macro null;
		}

		if (f.args.length != 1) {
			Context.error("SliceTools.with callback must take exactly one argument", fn.pos);
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
			Context.error("SliceTools.with only supports rust.Vec<T> or Array<T> values", value.pos);
		}

		var elemCt = TypeTools.toComplexType(elemT);
		var argName = f.args[0].name;

		var decl: Expr = {
			expr: EVars([{
				name: argName,
				type: TPath({
					pack: ["rust"],
					name: "Slice",
					params: [TPType(elemCt)]
				}),
				expr: { expr: ECast({ expr: EConst(CIdent("__hx_ref")), pos: fn.pos }, null), pos: fn.pos }
			}]),
			pos: fn.pos
		};

		// Expand to (Vec case):
		// `rust.Borrow.withRef(value, r -> { var s: rust.Slice<T> = cast r; body; })`
		if (valueIsArray) {
			// For `Array<T>`, borrow the underlying Vec as a slice without cloning.
			// This delegates to `rust.ArrayBorrow`, which calls into `hxrt::array::with_slice(...)`.
			var sliceParam = "__hx_slice";
			var arrayDecl: Expr = {
				expr: EVars([{
					name: argName,
					type: TPath({
						pack: ["rust"],
						name: "Slice",
						params: [TPType(elemCt)]
					}),
					expr: { expr: ECast({ expr: EConst(CIdent(sliceParam)), pos: fn.pos }, null), pos: fn.pos }
				}]),
				pos: fn.pos
			};

			return macro rust.ArrayBorrow.withSlice($value, function(__hx_slice) {
				$arrayDecl;
				${f.expr};
			});
		}

		return macro rust.Borrow.withRef($value, function(__hx_ref) {
			$decl;
			${f.expr};
		});
		#else
		return macro null;
		#end
	}

	#if !macro
	public static function len<T>(s: Slice<T>): Int {
		return untyped __rust__("{0}.len() as i32", s);
	}

	public static function get<T>(s: Slice<T>, index: Int): Option<Ref<T>> {
		return untyped __rust__("{0}.get({1} as usize)", s, index);
	}

	@:rustGeneric("T: Clone")
	public static function toArray<T>(s: Slice<T>): Array<T> {
		return untyped __rust__("hxrt::array::Array::<T>::from_vec({0}.to_vec())", s);
	}
	#else
	// Macro compilation stubs: these are only used in Rust output, never during macro typing/execution.
	public static function len<T>(s: Slice<T>): Int return 0;
	public static function get<T>(s: Slice<T>, index: Int): Option<Ref<T>> return None;
	public static function toArray<T>(s: Slice<T>): Array<T> return [];
	#end
}
