# Python

The language layer for Python 3.14+; load it together with [`coding.md`](coding.md).
What Python asks is readability as a contract — the language will allow almost anything, so the discipline is picking the one obvious way and typing it, because "it runs" is the weakest thing Python can ever say about the code.

> Python 3.14.6 · free-threaded build available (`python3.14t`) · verified 2026-07-09

## Contents

- [Gates](#gates)
- [The 3.14 baseline](#the-314-baseline)
- [Free threading](#free-threading)
- [Casing](#casing)
- [Types](#types)
- [Functions](#functions)
- [Errors](#errors)
- [Async](#async)
- [Testing](#testing)
- [Forbidden](#forbidden)

## Gates

```bash
ruff check .
ruff format --check .
mypy .
pytest
```

All of these pass after every change.

## The 3.14 baseline

Write to the language as it is now, not to its ancestors:

- Generics are syntax (PEP 695): `def first[T](items: list[T]) -> T:` and `class Repo[T]:`, with no `TypeVar` boilerplate; an alias is a `type` statement, `type UserMap = dict[UserId, User]`.
- Annotations are deferred by default (PEP 649/749) — **never** add `from __future__ import annotations`, which on 3.14 only pins the old stringified behavior; write forward references directly.
- Template strings (PEP 750, `t"..."`) carry structure instead of pre-mixed text: use them for anything that reaches an interpreter — SQL, a shell, HTML — so the receiving API gets the template and the values apart. This is the parameterize rule from `coding.md`, now built into the language; an f-string dropped into a query is still injection with extra steps.
- `str | int` unions, `list[str]` builtins, `StrEnum`, `asyncio.timeout` — all long stable; use them, never their `typing`-module ancestors.

## Free threading

The free-threaded build (`python3.14t`) runs threads in true parallel, with the GIL out of the way — supported in 3.14, and shipped as a separate `python3.14t` build alongside the default one.

- Code that was "thread-safe" only because the GIL serialized it is now racy: guard every shared mutable structure with an explicit lock, or better, do not share — pass immutable messages through a queue.
- CPU-bound parallelism finally works on plain threads (`ThreadPoolExecutor`); reach for it before paying the serialization tax of multiprocessing.
- Before adopting it, check that every C-extension dependency ships `cp314t` wheels — a GIL-only extension re-enables the GIL on import and quietly cancels the win.
- The two builds coexist; confirm which one is running with `sys._is_gil_enabled()` — measured, not assumed.

## Casing

| Item            | Convention         | Example                    |
| --------------- | ------------------ | -------------------------- |
| Modules         | `lower_with_under` | `user_service`             |
| Classes         | `CapWords`         | `HttpClient`               |
| Functions, vars | `lower_with_under` | `find_user`, `max_retries` |
| Constants       | `UPPER_WITH_UNDER` | `DEFAULT_TIMEOUT`          |
| Private         | leading `_`        | `_parse_token`             |

## Types

Every public signature is annotated — an untyped public function makes every caller re-derive its contract:

```python
def parse_id(value: str | int) -> int: ...
def process[T](items: list[T], lookup: dict[str, int]) -> list[tuple[T, int]]: ...
```

| Pattern                   | Use for                                                            |
| ------------------------- | ------------------------------------------------------------------ |
| `NewType("UserId", int)`  | domain IDs — a plain `int` where an ID was meant is a free bug     |
| `@dataclass(frozen=True)` | structured data — immutability matters double under free threading |
| `TypedDict`               | structured dicts crossing a boundary, typed `**kwargs`             |
| `class Status(StrEnum)`   | enumerations that serialize as their own names                     |

Prefer `pathlib.Path` to `os.path` string surgery — a path is a value with operations, not a string with conventions.

## Functions

Google-style docstrings on the public API; the signature carries the types, the docstring carries the meaning:

```python
def find_user(user_id: UserId, include_deleted: bool = False) -> User | None:
    """Load a user by ID from the store.

    Args:
        user_id: The user's unique identifier.
        include_deleted: If True, include soft-deleted users.

    Returns:
        The user if found, otherwise None.
    """
```

- Mutable default arguments are banned — the default is built once and shared across every call; take `None` and assign in the body.
- Three or more same-typed arguments go keyword-only (`def fn(a: int, *, b: int, c: int)`) — a positional call site stops being readable at two.

## Errors

```python
class AppError(Exception):
    """Base exception for this application."""

class NotFoundError(AppError):
    """Resource was not found."""
```

- Catch the specific exception — a bare `except:` catches `KeyboardInterrupt` and typos alike, and hides both.
- Re-raise with the chain intact: `raise AppError(...) from e` — the chain is the diagnosis, and breaking it throws the evidence away.
- `assert` is not validation: it vanishes under `-O`, so real checks `raise` real exceptions, and asserts stay in tests.
- The taxonomy and propagation live in [`coding.md`](coding.md), Errors are API.

## Async

- Never block the event loop: `asyncio.to_thread()` for blocking I/O, async-native libraries (`httpx`, `aiofiles`) over their blocking twins — one blocking call stalls every coroutine behind it.
- Independent work runs together: `asyncio.gather(a(), b())`.
- Every external call sits inside `async with asyncio.timeout(...)` — the default is forever.
- Async and free threading solve different problems — async for many slow I/O waits, threads for CPU parallelism; choose by the bottleneck, not the fashion.

## Testing

pytest; names state the claim (`test_parse_rejects_trailing_garbage`); assertion messages carry the case (`assert actual == expected, f"mismatch for {case}"`); async tests under `@pytest.mark.asyncio`.

## Forbidden

| Pattern                              | Why                                           | Instead                                |
| ------------------------------------ | --------------------------------------------- | -------------------------------------- |
| `from __future__ import annotations` | obsolete on 3.14; it pins the legacy behavior | delete it; forward-reference directly  |
| f-string into SQL / shell / HTML     | injection with extra steps                    | `t"..."` templates, parameterized APIs |
| `from x import *`                    | every name becomes a research project         | explicit imports                       |
| bare `except:`                       | catches interrupts and typos, hides both      | `except SpecificError`                 |
| a swallowed exception                | a lie about the state of the system           | handle it, or re-raise `from`          |
| mutable default arguments            | shared state across calls                     | `None` + assign in the body            |
| `assert` for validation              | deleted by `-O`                               | an explicit `raise`                    |
| `TypeVar` boilerplate in new code    | PEP 695 syntax is the native form             | `def f[T](...)`, `type X = ...`        |
| an untyped public API                | every caller re-derives the contract          | annotate it                            |

Exceptions: a broad catch at a top-level boundary that logs and re-raises; `assert` for invariants inside tests.
