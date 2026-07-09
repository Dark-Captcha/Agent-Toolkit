# Mojo

The language layer for Mojo; load it together with [`coding.md`](coding.md).
Mojo is a fast-moving beta with a closed compiler, so every fact here was **probed, not remembered** — read straight off eight real packages on the date below, never recalled from documentation.
When the compiler moves, re-probe against the project's own `.probe/` files before trusting a single line of this.

> Mojo `>=1.0.0b3.dev2026070506,<2` · formatter `mblack` · probed against 8 packages on 2026-07-09

## Contents

- [Gates](#gates)
- [Declarations](#declarations)
- [Types and traits](#types-and-traits)
- [Memory and ownership](#memory-and-ownership)
- [Errors](#errors)
- [FFI](#ffi)
- [Project layout](#project-layout)
- [Removed and renamed](#removed-and-renamed)
- [Gotchas](#gotchas)
- [Limits](#limits)

## Gates

```bash
mojo run -I . tests/public_surface.mojo   # newer packages gate the public surface first
mojo run -I . tests/run_tests.mojo        # then the full suite
mblack <package>/ tests/                   # format
mojo doc --diagnose-missing-doc-strings -Werror -o /tmp/pkg-doc.json <package>
```

All of these pass after every change.

Cross-package dependencies are passed with repeated `-I ../other-mojo`.
Missing docstrings fail the doc gate, so a public symbol without one does not ship.

## Declarations

- **Functions are `def`.** `fn` was removed. A `def` that can raise says `raises` on its signature, explicitly.
- **Types are `struct`.** No `class` in library code; static methods take `@staticmethod`, and `Self` names the type.
- **Bindings are `var`.** `let` does not exist. A `var` may be declared without a value and then assigned in every branch that follows.
- **Constants are `comptime`.** `comptime X = ...` replaces the deprecated `alias` — at module scope, at local scope, and as a typed struct member:

```mojo
comptime SECONDS_PER_DAY = 86_400
comptime TLS_1_3 = Version(value=0x0304)
comptime K: InlineArray[UInt32, 4] = [1, 2, 3, 4]
```

Module-level mutable `var` does not exist — globals are unsupported; pass state down, and keep module constants as `comptime`.

## Types and traits

Declare conformance as a parenthesized base list, and build owned types on the trio `Copyable, Movable, ImplicitlyDeletable`:

```mojo
trait Sink(Copyable, Movable, ImplicitlyDeletable):
    def write(mut self, bytes: Span[UInt8]): ...

struct StdoutSink(Sink):
    ...
```

- Compile-time parameters go in `[...]`: `def emit[W: Writer](mut writer: W)`, `struct HMAC[H: Hasher]`.
- Inside a generic struct, refer to the parameter as `Self.H`, never bare `H` — bare is a compile error.
- Keep protocol trait methods declaration-only (`...`); default bodies exist but break generic conformance through `__extension`.
- Traits seen in real use: `Copyable`, `Movable`, `ImplicitlyDeletable`, `Sized`, `Defaultable`, `Comparable`, `Writer`, `Writable`, `TrivialRegisterPassable`.
- An existential parameter reads `mut writer: Some[Writer]`.

## Memory and ownership

| Form                   | Meaning                                                    |
| ---------------------- | ---------------------------------------------------------- |
| `self`                 | borrowed receiver, read-only                               |
| `mut self`             | mutable borrow of the receiver                             |
| `out self`             | receiver being constructed (`def __init__(out self, ...)`) |
| `deinit self`          | consuming receiver — the destructor and consuming methods  |
| `var x: T` (parameter) | the function takes ownership (this replaced `owned`)       |
| `value^`               | move — transfer ownership                                  |

```mojo
def __del__(deinit self):
    _ = external_call["close", Int32](self.fd)
```

- Move heavy values with `^` (`self.sink = s^`, `return next^`); returning a local needs the move unless the type is `ImplicitlyCopyable`.
- Implement `__del__(deinit self)` on any struct that owns a resource — a file descriptor, a pointer, a region.
- Arguments are exclusive: the same mutable buffer cannot pass through two parameters at once, nor can a span of `self.field` go into a `mut self` method.

## Errors

- `raise Error("pkg.module: what is wrong (expected X), got Y")` — every message names its own origin, because a stack trace will not always be there.
- `raises` is explicit on the signature; `try` / `except e` catches, and a bare `except:` compiles and is licensed here, because Mojo has a single `Error` type and no interrupt to swallow — the Python ban does not carry over.
- `Optional[T]` is the idiom for absence — a lookup, a queue pop, a nullable pointer as `Optional[UnsafePointer[...]]`.
- There is no `Result` type, and a mixed-type tuple return fails on this compiler — return one value plus `mut` out-parameters instead.

## FFI

Bind C symbols directly, with no shim library in between:

```mojo
from std.ffi import external_call

var rc = external_call["clock_gettime", Int32](clockid, timespec.unsafe_ptr())
var n = external_call["getrandom", Int](ptr, length, UInt32(0))
```

- The import is `std.ffi`; intrinsics come from `std.sys.intrinsics`.
- **Prefer the standard library to FFI wherever both exist.** `external_call["write", ...]` collides with the standard library's own declaration and fails at lowering — use `from std.io import FileDescriptor; FileDescriptor(2).write(s)`, and `from std.os import getenv, isatty`.
- Document the syscall or libc contract in the module header, because the struct shapes are invisible from the call site.

## Project layout

The shape that emerged across all eight packages:

```text
pkg-mojo/                    # repo is kebab-case
├── pixi.toml                # workspace, tasks, dependencies
├── pkg/                     # package dir, snake_case, one concern per file
├── tests/
│   ├── run_tests.mojo       # aggregates and reports failures
│   └── public_surface.mojo  # newer packages gate the public API separately
├── benchmarks/
├── examples/
└── .probe/                  # committed, verified-on-disk language facts
```

Docstrings are mandatory (the doc gate enforces it), error strings are prefixed `pkg.module:`, and each test is a `def run() raises` registered in `run_tests.mojo`.

## Removed and renamed

The beta churns, so this is the current-versus-gone table, verified against the packages:

| Old form                           | Now                                                             |
| ---------------------------------- | --------------------------------------------------------------- |
| `fn name(...)`                     | `def name(...)`                                                 |
| `let x`                            | `var x`                                                         |
| `alias NAME = ...`                 | `comptime NAME = ...`                                           |
| `@parameter if` / `@parameter for` | `comptime if` / `comptime for`                                  |
| `@register_passable("trivial")`    | conform to `TrivialRegisterPassable`                            |
| `def f(owned x: T)`                | `def f(var x: T)`                                               |
| `def __del__(owned self)`          | `def __del__(deinit self)`                                      |
| `__origin_of(...)`                 | `origin_of(...)`                                                |
| `MutableAnyOrigin`                 | `MutAnyOrigin`                                                  |
| `ImplicitlyDestructible`           | `ImplicitlyDeletable`                                           |
| `Stringable`, `EqualityComparable` | gone — use `Writer` / `Writable`; `Comparable` implies equality |
| `mojo package` → `.mojopkg`        | `mojo precompile` → `.mojoc`                                    |

## Gotchas

- String slicing is keyed: `s[byte=a:b]` or `s[codepoint=a:b]`; a plain `s[a:b]` is rejected. Length is `s.byte_length()`, not `len(s)`.
- `ref` and `case` are reserved words and cannot be used as identifiers.
- Wrap `Int → UInt8` explicitly (`UInt8(ord("x"))`) — the implicit conversion is deprecated.
- A SIMD shift or mask needs its right-hand side in the operand's own type: `x >> Scalar[W](n)`.
- A trait used as a generic field type must extend `ImplicitlyDeletable`.

## Limits

- **Every fact here has a shelf life.** It was probed on 2026-07-09 against packages pinned from `dev2026061206` to `dev2026070506`; the compiler moves weekly, and what was true then may be false now. Re-probe against a fresh `.probe/` run before relying on any of it — never update this file from memory.
- **The pins themselves disagree.** Newer packages use `mojo = ">=...dev2026070506,<2"`; older ones hard-pin `mojo-compiler == ...`. Standardize new work on the range form at the newest pin, and migrate the exact pins when a package is next touched.
