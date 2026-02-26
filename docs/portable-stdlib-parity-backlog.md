# Portable Stdlib Parity Backlog

This backlog is generated from `docs/portable-stdlib-candidates.json` and triaged into
implementation tracks so Tier2 expansion is deliberate.

## Likely-Portable Candidates (Runtime-Oriented)

These are the first tranche to validate/promote into Tier2 sweeps.

### Tranche A (`haxe.rust-hss.1`)

Status:
- Promoted into Tier2: 20/20 modules.

- `Math`
- `Std`
- `haxe.EntryPoint`
- `haxe.EnumFlags`
- `haxe.Int32`
- `haxe.Int64Helper`
- `haxe.NativeStackTrace`
- `haxe.SysTools`
- `haxe.Template`
- `haxe.Ucs2`
- `haxe.Utf8`
- `haxe.ValueException`
- `haxe.crypto.BaseCode`
- `haxe.exceptions.ArgumentException`
- `haxe.exceptions.NotImplementedException`
- `haxe.exceptions.PosException`
- `haxe.io.BufferInput`
- `haxe.io.Mime`
- `haxe.io.Scheme`
- `haxe.io.StringInput`

### Tranche B (`haxe.rust-hss.2`)

Status:
- Promoted into Tier2: 20/20 modules.

- `haxe.ds.Either`
- `haxe.ds.HashMap`
- `haxe.ds.ListSort`
- `haxe.ds.Map`
- `haxe.ds.WeakMap`
- `haxe.format.JsonParser`
- `haxe.format.JsonPrinter`
- `haxe.http.HttpMethod`
- `haxe.http.HttpStatus`
- `haxe.iterators.DynamicAccessIterator`
- `haxe.iterators.DynamicAccessKeyValueIterator`
- `haxe.iterators.HashMapKeyValueIterator`
- `haxe.iterators.RestIterator`
- `haxe.iterators.RestKeyValueIterator`
- `haxe.iterators.StringIteratorUnicode`
- `haxe.iterators.StringKeyValueIteratorUnicode`
- `haxe.rtti.Rtti`
- `haxe.rtti.XmlParser`
- `haxe.xml.Fast`
- `haxe.zip.FlushMode`

## Long-Term / Separate Tracks (`haxe.rust-hss.3`)

### Macro + Display Buckets (compile-time tooling surface)

- `haxe.display.Diagnostic`
- `haxe.display.Display`
- `haxe.display.FsPath`
- `haxe.display.JsonModuleTypes`
- `haxe.display.Position`
- `haxe.display.Protocol`
- `haxe.display.Server`
- `haxe.macro.CompilationServer`
- `haxe.macro.Compiler`
- `haxe.macro.ComplexTypeTools`
- `haxe.macro.Context`
- `haxe.macro.DisplayMode`
- `haxe.macro.ExampleJSGenerator`
- `haxe.macro.Expr`
- `haxe.macro.Format`
- `haxe.macro.JSGenApi`
- `haxe.macro.MacroStringTools`
- `haxe.macro.MacroType`
- `haxe.macro.PlatformConfig`
- `haxe.macro.PositionTools`
- `haxe.macro.Printer`
- `haxe.macro.Tools`
- `haxe.macro.Type`
- `haxe.macro.TypeTools`
- `haxe.macro.TypedExprTools`

### Target-Adapter Required Buckets

- `haxe.atomic.AtomicBool`
- `haxe.atomic.AtomicInt`
- `haxe.atomic.AtomicObject`
- `haxe.extern.AsVar`
- `haxe.extern.EitherType`
- `haxe.extern.Rest`
- `haxe.http.HttpJs`
- `haxe.http.HttpNodeJs`
- `haxe.io.Float32Array`
- `haxe.io.Float64Array`
- `haxe.io.Int32Array`
- `haxe.io.UInt16Array`
- `haxe.io.UInt32Array`
- `haxe.iterators.ArrayIterator`
- `haxe.iterators.ArrayKeyValueIterator`
- `haxe.zip.Huffman`
- `haxe.zip.InflateImpl`
- `haxe.zip.Tools`
