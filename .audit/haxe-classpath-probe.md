# Haxe 4.3.7 classpath probe

## Question

Can a haxe.rust compiler macro obtain active classpath roots as opaque directory
handles or identities, without receiving filesystem path strings?

## Probe

The read-only macro used `haxe.macro.Context.getClassPath()` and printed every
returned value. It ran with one relative test classpath and one temporary macro
classpath.

```haxe
import haxe.macro.Context;
import haxe.macro.Expr;

class ClassPathProbe {
  public static macro function run():Expr {
    for (path in Context.getClassPath())
      Sys.println(path);
    return macro null;
  }
}
```

The command used Haxe 4.3.7 through the repository's reviewed Lix installation:

```text
<haxe-4.3.7> -cp /tmp \
  -cp test/positive/support_crate_recursive_generic_no_metadata \
  --macro 'ClassPathProbe.run()' --no-output
```

## Result

The API returned four strings:

1. The relative test classpath.
2. The absolute temporary macro classpath.
3. An empty classpath entry.
4. The absolute Haxe 4.3.7 standard-library classpath.

A second probe supplied one readable parent-relative classpath. Haxe accepted
the entry and returned its original form, including `..`:

```text
../<sibling>/src/
```

The local absolute installation path is intentionally omitted from this public
evidence file. Its spelling is irrelevant to the result.

## Conclusion

Haxe 4.3.7 gives the compiler path strings. It does not give open directory
handles or opaque filesystem identities. A native source-admission helper
therefore needs a reviewed way to bind each private path string to the opaque
classpath ID used in durable plans and responses. Alternatively, haxe.rust
would need a new upstream Haxe handle-transfer API. Opaque IDs alone cannot
locate the classpath roots. The helper must preserve valid parent-relative
classpath behavior. The stricter authored `sourceRoot` grammar can still reject
all `..` segments.
