# JavaScript

The language layer for plain JavaScript; load it together with [`coding.md`](coding.md).
What JavaScript will do if it is allowed: coerce silently, hoist invisibly, and swallow the errors inside floating promises — so the whole job here is switching every one of those defaults off.

> Node 24 LTS (26 Current) · Bun 1.3.14 · verified 2026-07-09

## Contents

- [Gates](#gates)
- [Runtime](#runtime)
- [Modules](#modules)
- [Casing](#casing)
- [Types via JSDoc](#types-via-jsdoc)
- [Errors](#errors)
- [Async](#async)
- [Testing](#testing)
- [Forbidden](#forbidden)

## Gates

```bash
eslint .
prettier --check .
node --test      # or: bun test
```

All three pass after every change.

## Runtime

Target the current Node line — 24 is the Active LTS, 26 is Current — and use what it hands over instead of a dependency.
Node 26 ships the **Temporal** API on by default, with no flag: new date and time code uses `Temporal`, and legacy `Date` arithmetic is finally obsolete.
`fetch` and `WebSocket` are built in (Undici 8), `node:test` is a runner never installed, and `--env-file` loads a `.env` with no library.
Bun (1.3.14) is a fine alternative for scripts and tooling: `bun install`, `bun test`, `bunx`.
Pick one runtime and one test runner per repository — mixing them turns every bug into a which-runtime question first.

## Modules

ESM everywhere it is possible: `"type": "module"` for a new project, CommonJS only when a dependency forces it, and never both syntaxes in one file, because the interop seam is where the strange bugs live.

```javascript
import { readFile } from "node:fs/promises";
import express from "express";
import { validate } from "./validation.js";
```

- The `node:` prefix on built-ins — a package cannot shadow it.
- Explicit file extensions on relative imports — the ESM resolver resolves files, not guesses.

## Casing

| Item      | Convention        | Example               |
| --------- | ----------------- | --------------------- |
| Classes   | `PascalCase`      | `UserService`         |
| Functions | `camelCase`       | `findUser`, `isValid` |
| Constants | `SCREAMING_SNAKE` | `MAX_RETRIES`         |
| Files     | `kebab-case`      | `user-service.js`     |
| Private   | `#field`          | `#cache`              |

`#private` fields over an underscore prefix — the underscore is a request, the hash is a wall.

## Types via JSDoc

The public API carries JSDoc types — editor help and `tsc --checkJs` verification, with no build step. This excerpt elides the body, and `User` and `FindOptions` stand for project types:

```javascript
/**
 * @param {string} email
 * @param {FindOptions} [options]
 * @returns {Promise<User | null>}
 */
export async function findByEmail(email, options) {
  return null;
}
```

An untyped public function makes every caller re-derive its contract from the body.

## Errors

Custom error classes carry a machine-readable `code`, so a handler can branch without parsing prose:

```javascript
export class AppError extends Error {
  /** @param {string} message @param {string} code @param {number} [statusCode] */
  constructor(message, code, statusCode = 500) {
    super(message);
    this.name = this.constructor.name;
    this.code = code;
    this.statusCode = statusCode;
  }
}
```

Catch at the boundaries, check `instanceof` before handling, and never swallow — the reasoning is in [`coding.md`](coding.md), Errors are API.

## Async

- `async/await` with `try/catch`; no `.then()` chains.
- Independent work runs together: `Promise.all([a(), b(), c()])`.
- Fire-and-forget is marked `void send()` — an unmarked floating promise eats its own rejection.
- External calls carry a timeout via `AbortSignal.timeout(ms)`, because the default is forever.

## Testing

`node:test` or `bun test` first — the built-in runner is a dependency never married; Vitest or Jest when the project already leans on them.
Write `describe` / `it("should ...")`, arrange–act–assert, specific matchers over `toBeTruthy`, and import the runner explicitly, because implicit globals make the test file lie about what it depends on.

## Forbidden

| Pattern                              | Why                                         | Instead                            |
| ------------------------------------ | ------------------------------------------- | ---------------------------------- |
| legacy `Date` arithmetic in new code | mutable, timezone-hostile, off by one       | `Temporal` (default-on in Node 26) |
| `var`                                | hoisting and function scope, both invisible | `const`, then `let`                |
| `==` / `!=`                          | coercion rules nobody fully remembers       | `===` / `!==`                      |
| `eval()`, `new Function()`           | a code-injection surface                    | anything else                      |
| `with`                               | makes every name ambiguous                  | explicit references                |
| `arguments`                          | array-shaped, but not an array              | rest parameters `...args`          |
| implicit globals                     | a typo becomes a global variable            | always declare                     |
| `console.log` in production          | unstructured, unfilterable                  | a logger                           |

One coercion worth keeping: `value == null` catches both `null` and `undefined` in a single idiomatic check.
