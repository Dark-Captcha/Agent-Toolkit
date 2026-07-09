# TypeScript

The language layer for TypeScript; load it together with [`coding.md`](coding.md).
What TypeScript wants: the type system is the whole point — every `any` is a hole cut in it, and a program with holes cut in its types is a JavaScript program with extra build steps.

> TypeScript 7.0 · Node 24 LTS (26 Current) · Bun 1.3.14 · verified 2026-07-09

## Contents

- [Gates](#gates)
- [The compiler](#the-compiler)
- [Running without a build](#running-without-a-build)
- [Strictness](#strictness)
- [Casing](#casing)
- [Types](#types)
- [Modules](#modules)
- [Functions](#functions)
- [Async](#async)
- [Testing](#testing)
- [Forbidden](#forbidden)

## Gates

```bash
tsc --noEmit      # the type gate — runtimes strip types, they do not check them
eslint .
node --test       # or: bun test
```

All three pass after every change.

## The compiler

TypeScript 7.0 is the current release: a native port of the compiler written in Go, roughly ten times faster than 6.0, with type-checking logic structurally identical to it — the same language and the same semantics behind a much faster `tsc`.
It installs from the `typescript` package on npm like any other release.
Because every runtime erases types rather than checking them, `tsc --noEmit` stays the type gate no matter what executes the code.

## Running without a build

Node (24 LTS and 26 Current) and Bun both execute `.ts` files directly, stripping the types at load — so running code needs no build step.
Node 26 removed the `--experimental-transform-types` flag entirely: stripping is the only path now, and any TypeScript construct that carries _runtime_ semantics — `enum`, a runtime `namespace`, parameter properties — simply does not run.
`erasableSyntaxOnly` turns that reality into a compile error instead of a crash at load, which is why it is on in the baseline below.

## Strictness

New projects start strict, with these three flags as the floor:

```json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "erasableSyntaxOnly": true
  }
}
```

`tsconfig.json` is a configuration file — it changes through tooling or with explicit permission, never a silent hand-edit ([`CORE.md`](../CORE.md), standing constraints).
`noUncheckedIndexedAccess` earns its noise: an index may always miss, and this makes the type admit it.
`erasableSyntaxOnly` keeps every file runnable under type-stripping, and it turns the const-object-over-`enum` rule below into a compile error rather than a review comment.

## Casing

| Item              | Convention        | Example               |
| ----------------- | ----------------- | --------------------- |
| Types, interfaces | `PascalCase`      | `User`, `HttpClient`  |
| Functions, vars   | `camelCase`       | `findUser`, `isValid` |
| Constants         | `SCREAMING_SNAKE` | `MAX_RETRIES`         |
| Files, folders    | `kebab-case`      | `user-service.ts`     |

## Types

Reach for `unknown` plus a narrowing guard wherever `any` tempts — `unknown` forces the proof that `any` skips.

Brand IDs so two string-shaped values cannot be swapped:

```typescript
type UserId = string & { readonly __brand: "UserId" };
```

Model results and states as discriminated unions, so the compiler forces every consumer to handle every case:

```typescript
type Result<T> =
  { type: "success"; data: T } | { type: "error"; error: string };
```

Prefer a const object over an `enum` — an enum emits runtime code and cannot survive type-stripping, while a const object erases to nothing and stays a plain union:

```typescript
export const UserStatus = {
  Active: "active",
  Inactive: "inactive",
} as const;

export type UserStatus = (typeof UserStatus)[keyof typeof UserStatus];
```

Use `interface` for object shapes and extendable contracts; use `type` for unions, intersections, and computed types.

## Modules

- Named exports only in project code, and named imports wherever the package offers them — a dependency that ships only a default export is imported as it ships. A default export renames itself at every import site, and refactoring tools lose its trail.
- `import type { T }` for type-only imports — it states intent and erases cleanly.
- Explicit `.js` extensions on relative ESM imports — the resolver resolves files, not guesses.

## Functions

- An explicit return type on every exported function — inference serves the body's reader, the signature serves everyone else, and it pins the contract against drift.
- Three or more parameters become a single options object — positional booleans are unreadable at the call site.
- Expected failures travel as a `Result` union; exceptions are for the unexpected; catch at boundaries — route handlers, event loops — and let the interior propagate ([`coding.md`](coding.md), Errors are API).

## Async

- `async/await` everywhere; a `.then()` chain reintroduces the callback shape the syntax was built to kill.
- Independent work runs together: `Promise.all([a(), b(), c()])`.
- Fire-and-forget is marked: `void send()` — an unmarked floating promise swallows its own rejection.
- External calls carry a timeout via `AbortSignal.timeout(ms)` (`fetch(url, { signal: AbortSignal.timeout(5000) })`), because the network's default timeout is forever.

## Testing

`node:test` or `bun test` first — the built-in runner is a dependency never married; Vitest when a project already uses it.
Write `describe` / `it("should ...")`, arrange–act–assert, and specific matchers (`toEqual`, `toHaveLength`) over `toBeTruthy`, which passes for a dozen wrong reasons.

## Forbidden

| Pattern                                           | Why                                                                    | Instead                                    |
| ------------------------------------------------- | ---------------------------------------------------------------------- | ------------------------------------------ |
| `any`                                             | cuts the hole the language exists to close                             | `unknown` + narrow                         |
| `@ts-ignore`                                      | silences without stating a reason                                      | fix the type, or `@ts-expect-error` + note |
| `enum`, runtime `namespace`, parameter properties | runtime semantics break type-stripping; banned by `erasableSyntaxOnly` | const objects, ES modules, explicit fields |
| `import * as`                                     | unclear surface, defeats tree-shaking                                  | named imports                              |
| default exports                                   | self-renaming, refactor-hostile                                        | named exports                              |
| `==` / `!=`                                       | coercion rules nobody fully remembers                                  | `===` / `!==`                              |
| `var`                                             | function scope and hoisting traps                                      | `const`, then `let`                        |
| `console.log` in production                       | unstructured, unfilterable                                             | a logger                                   |
| `eval()`                                          | a code-injection surface                                               | anything else                              |

Exceptions: `any` at an untyped third-party boundary, narrowed immediately; `@ts-expect-error` with a reason comment, which fails the build when the error disappears; `console` in development scripts.
