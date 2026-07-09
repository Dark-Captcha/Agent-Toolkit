# Rust

The language layer for Rust; load it together with [`coding.md`](coding.md).
What Rust wants is proof at compile time — the borrow checker, the type system, and `Result` exist so that whole categories of failure become impossible to write down, and fighting them is almost always a smell in the design rather than in the language.

> Rust 1.96.1 · edition 2024 · verified 2026-07-09

## Contents

- [Gates](#gates)
- [Modern defaults](#modern-defaults)
- [Casing](#casing)
- [Errors](#errors)
- [Types](#types)
- [Functions](#functions)
- [Async](#async)
- [Unsafe](#unsafe)
- [Forbidden](#forbidden)

## Gates

```bash
cargo fmt
cargo clippy -- -D warnings
cargo test
```

All three pass after every change, with clippy at `-D warnings` — a warning allowed to merge is a warning nobody ever comes back to fix.

## Modern defaults

The standard library keeps swallowing the ecosystem; let it, because every crate it replaces is a marriage annulled for free.

- New crates are edition 2024 — `cargo new` already does this, and an edition is opt-in modernity at zero runtime cost.
- `std::sync::LazyLock` and `OnceLock` cover what `lazy_static` and most of `once_cell` used to do; drop the dependency the next time the file is open.
- `async fn` in traits is native now — reach for `async-trait` only when `dyn Trait` is genuinely needed.
- `let Some(x) = value else { return; };` is the guard clause from `coding.md`, written in Rust — prefer it to a nest of `if let`.

## Casing

| Item            | Convention        | Example                 |
| --------------- | ----------------- | ----------------------- |
| Types, traits   | `PascalCase`      | `UserId`, `HttpClient`  |
| Functions       | `snake_case`      | `find_user`, `is_valid` |
| Constants       | `SCREAMING_SNAKE` | `MAX_CONNECTIONS`       |
| Modules         | `snake_case`      | `user_service`          |
| Type parameters | single uppercase  | `T`, `E`, `Item`        |

## Errors

No panics on the production path: `unwrap()`, `expect()`, and `panic!()` turn a recoverable situation into a crash the caller never got a vote on.
Propagate with `?`; turn absence into an error with `ok_or_else`.

Split by audience — `thiserror` for a library, `anyhow` for an application:

```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum Error {
    #[error("not found: {resource} with id {id}")]
    NotFound { resource: &'static str, id: String },

    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
}

pub type Result<T> = std::result::Result<T, Error>;
```

A library's errors are API — callers match on them, so they get a typed enum.
An application's errors are diagnostics — a human reads them, so `anyhow::Context` adding "while loading configuration from {path}" is worth more than another variant.

Panics are licensed in exactly three places: tests, an invariant proven unreachable and documented right there, and a truly unrecoverable state where carrying on would corrupt data.

## Types

Give every domain concept its own type — IDs, units, anything validated:

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct UserId(u64);
```

A bare `u64` accepted where a `UserId` was meant is a bug the compiler would have caught for free; the newtype is how that catch gets collected.

| Role          | Derives                                           |
| ------------- | ------------------------------------------------- |
| Value types   | `Debug, Clone, Copy, PartialEq, Eq, Hash`         |
| Data structs  | `Debug, Clone, PartialEq, Serialize, Deserialize` |
| Error types   | `Debug, Error` (thiserror)                        |
| Configuration | `Debug, Clone, Default, Serialize, Deserialize`   |

Share ownership across threads with `Arc<Inner>` — clone the `Arc`, never the data behind it.

## Functions

- Borrow at the boundary: `&[u8]` over `Vec<u8>`, `&str` over `&String`, `impl Read` over a concrete `&mut File`.
- Return owned data, or a borrow tied to a lifetime spelled out explicitly — never one the caller has to reverse-engineer.
- Prefer iterators to index loops: the iterator carries the proof that the bounds hold, where the index loop asks the reader to re-derive it.

## Async

- Never block the executor: `tokio::fs` rather than `std::fs` inside async code, `spawn_blocking` for CPU-bound work — one blocked worker stalls every task queued behind it.
- Run independent futures together with `tokio::join!`.
- Wrap every external call in a `timeout()` — the network's own timeout is forever.

## Unsafe

Every `unsafe` block owes three things: a `// SAFETY:` comment explaining why the invariants hold, the smallest scope that will do, and a safe wrapper around it.
`unsafe` moves a proof obligation off the compiler and onto the agent, and that comment is the proof.
It is licensed for FFI, measured hot paths, and genuine low-level primitives — never for convenience, a hunch about speed, or beating the borrow checker into silence, because the borrow checker is usually right and the real fix is a redesign.

## Forbidden

| Pattern                  | Why                                   | Instead             |
| ------------------------ | ------------------------------------- | ------------------- |
| `unwrap()` in production | a panic without the caller's consent  | `?`, `ok_or_else`   |
| `expect()` in production | the same panic, with a better epitaph | `?` with context    |
| `panic!()` in production | crash as control flow                 | return a `Result`   |
| `use foo::*`             | every name becomes a research project | explicit imports    |
| `println!` logging       | unstructured, unfilterable            | `tracing`           |
| undocumented `unsafe`    | a proof obligation with no proof      | a `// SAFETY:` note |
| `&String` parameter      | double indirection, narrower callers  | `&str`              |

Exceptions: `unwrap`/`expect` in tests; `expect` on an invariant proven right at the site; `panic!` in tests, or on genuinely unrecoverable corruption.
