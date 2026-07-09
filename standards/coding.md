# Coding

How the doctrine turns into actual code, in any language.
Load it whenever code gets written or changed, alongside the matching `standards/<language>.md`.
These rules lean on the type system and the gates first, and on a human reading them only second — a rule a compiler or a linter can hold is worth far more than one a person has to remember.

## Contents

- [Data first](#data-first)
- [Naming](#naming)
- [The shape of a unit](#the-shape-of-a-unit)
- [Errors are API](#errors-are-api)
- [Comments](#comments)
- [State and dependence](#state-and-dependence)
- [Project shape](#project-shape)
- [Tests](#tests)
- [Security floor](#security-floor)
- [Library APIs](#library-apis)
- [Style mechanics](#style-mechanics)
- [The finishing pass](#the-finishing-pass)
- [Limits](#limits)

## Data first

Get the data model right and the functions almost write themselves; get it wrong and no amount of cleverness at the call sites will save them.
So design the types before the logic.

**Make illegal states unrepresentable.**
Reach for a sum type instead of a boolean pair with a combination that must never occur, an enum instead of a magic string, a non-empty collection type instead of a comment begging callers never to pass empty.
Every invariant the type holds is one nobody has to remember at three in the morning.

**Parse, don't validate.**
At the boundary, turn untrusted input into a type that can only hold the valid shape — once.
After that the interior trusts its own types and never re-checks, because validation sprinkled through the interior is validation that someone, somewhere, forgot.

**Type everything that is not text.**
A typed selector instead of string-parsing, a typed `LATEST` member instead of a `"latest"` sentinel.
Strings are for text; everything else has earned a type.

## Naming

Names are the units a codebase is read in, one at a time.

- Full words, no abbreviations — an abbreviation saves the writer a keystroke and charges every later reader a lookup.
- Borrow the domain's own vocabulary: a value filling the HTTP header `sec-ch-ua-platform` is named `sec_ch_ua_platform`, not `ch_ua_platform`, because the spec owns the names of its own fields.
- Booleans read as questions: `is_mobile`, `has_session`, `should_retry`.
- Name the role, not the type: `retry_budget`, never `count`.
- A name that will not come is a concept not yet finished thinking — trouble naming something is a design smell, not a thesaurus problem.
- The moment a name starts to lie, rename it, because a wrong name misleads with the full weight of the compiler behind it.

Construction and conversion share one grammar across every language; only the casing shifts:

| Prefix         | Meaning                             |
| -------------- | ----------------------------------- |
| `is_` / `has_` | boolean question                    |
| `from_`        | build from another form             |
| `to_`          | lossless conversion, self unchanged |
| `as_`          | a borrowed or zero-cost view        |
| `try_`         | the fallible version of a total one |
| `with_`        | a copy with one thing changed       |

## The shape of a unit

**Guard clauses first.**
Turn the invalid cases away at the top, and let the real work run straight down the left margin, unindented.
Nesting is debt — every level is one more thing the reader holds in mind just to follow the line in front of them.

**Named steps over clever chains.**
A step with a name can be printed, logged, and stopped at; a long chain is one held breath with no room to look inside.

```text
request  = build_request(user_id, command)
response = connection.send(request)
result   = response.into_result()
```

**One job per unit — but keeping things together beats splitting them apart.**
No reader should have to jump across five files to follow one thought.
Pull a piece out when it has earned a name and a second caller, not to satisfy a line count, and let a constant or helper used exactly once live right where it is used.

## Errors are API

Design the errors with the same care as the return values, because that is exactly what they are.

**Sort them by what the caller will do.**
Two errors that lead the caller to the same response are one kind; one error that hides two different responses has to split.
That single question sizes the whole error type.

**Two different animals.**
An expected failure — a missing file, malformed input, a peer that is down — travels as a typed error the caller can catch and handle.
An impossible state — a broken invariant, a branch that "cannot happen" — crashes right where the impossibility surfaced, because a visible crash beats a silent corrupted write.

**Context builds up on the way out.**
Each layer adds the piece only it knows — the path, the id, the attempt number — so the error that finally surfaces reads like a story instead of a stack of "operation failed."

**Catch at the edges, propagate through the middle.**
Catch at the process, request, or job boundary: log it once, and shape the message for whoever receives it.
A catch-all buried in the interior destroys the story before anyone who could act on it ever sees it — an error is never swallowed.

## Comments

Comment the why, the constraint, the invariant — never narrate the what.
The code is already the what, and narration rots the first time the code changes without it.

A comment is code too: a wrong one is a bug the compiler will never catch.
So when the code beside it changes, the comment is fixed or deleted in the same motion.

Suppression directives are banned at the line ([`CORE.md`](../CORE.md), standing constraints).
When a formatter fights an intended layout, restructure until the formatter agrees; when a lint is wrong for the whole project, change the project's configuration, with permission — never silence the single line.

## State and dependence

Keep the side effects at the edges: a pure core that computes, wrapped in a thin shell that talks to the world.
Pure logic can be tested with no stage set, reasoned about with no debugger, and reused without dragging its whole environment along behind it.

Keep mutation small: constant by default, reassignment only where the algorithm truly needs it.
Global mutable state is a bug that simply has not happened yet — it makes every function's behavior depend on history, and history is the one input no test can control.

Dependencies inside the codebase point strictly downward, and gather in one place ([`../thinking/design.md`](../thinking/design.md)).

## Project shape

The directory tree is the first document a stranger reads.

- A filename predicts its contents — a reader guesses most of what is inside from the name alone, or the file is misnamed.
- Where a file sits predicts what it may import.
- Bucket names are banned, as files or directories: `utils`, `helpers`, `common`, `misc`, `shared`, `types`. A bucket collects whatever has no proper home, and then hides it.

Documentation grows in tiers as they are earned, and then it stops:

| Tier     | Files                                           | Earned when                                         |
| -------- | ----------------------------------------------- | --------------------------------------------------- |
| Always   | `README.md`, `LICENSE`, `.gitignore`            | the repository exists                               |
| Earned   | `ARCHITECTURE.md`, `ROADMAP.md`, `CHANGELOG.md` | layers settle; direction matters; the first release |
| Featured | `SECURITY.md`, `PERF.md`, `AUDIT.md`            | the property has become a feature                   |
| Scaled   | `docs/`, `docs/adr/`                            | single files stop fitting                           |

Stop around seven documents — the eighth is usually a bucket in disguise.
Banned document names: `NOTES.md`, `TODO.md`, `MISC.md`, `STATUS.md` — a status file rots within a day of being written, while `git log` never does.

## Tests

The reasoning lives in [`../thinking/verification.md`](../thinking/verification.md); the mechanics live here.

- The test's name states its claim: `test_parse_rejects_trailing_garbage`, not `test_parse_3`.
- Arrange, act, assert — in that order, and visibly so.
- A failed assertion carries the context with it: the expected value, the actual one, and which case produced them; a bare "assertion failed" makes the reader run the whole hunt again.
- Every unit gets the edge list: zero, one, the maximum, empty, absent, malformed — and concurrent, wherever concurrency is real.
- Tests get the same care as production, with one licensed exception: repetition that keeps a test readable on its own beats a maze of shared helpers ([`../thinking/economy.md`](../thinking/economy.md)).

## Security floor

The minimum, in any language, on any task:

- Trust nothing that crossed a boundary — network, file, environment, user. Parse it into a type at the edge.
- Parameterize anything that reaches a shell, a query, an interpreter, or a rendered page. Gluing strings into an executor is injection with extra steps.
- Secrets never appear in source, logs, error text, or history — they live in the environment or a secret store, and anything ever printed is assumed copied.
- Least privilege on every token, scope, and grant — the breach that stays contained is the one whose blast radius was sized ahead of time.

## Library APIs

Design the public surface for a human on a deadline, not for a machine or a diagram.

- Ready to use over ready to configure: sensible fixed defaults, keyword arguments instead of positional puzzles.
- Fold the cross-cutting behavior into one opinionated setup, and expose only what genuinely varies from call to call.
- A published API is a one-way door ([`../thinking/design.md`](../thinking/design.md)) — write the README example before the implementation, and let the awkwardness of that example redesign the API while redesigning is still free.

## Style mechanics

Pure mechanics, kept only because inconsistency costs more than any one convention:

- Imports are explicit and at the top of the file, grouped standard library, then external, then internal. Wildcard imports are banned everywhere — they turn every unfamiliar name into a research project.
- A string that is naturally one piece — a URL, a header value — stays on one line however long it runs; splitting it to hit a width limit trades real greppability for cosmetic neatness.
- A value that is a list joined by a separator — ciphers, feature flags — reads one item to a line, down the page.

## The finishing pass

Before any change gets called done:

1. Re-read the diff hunk by hunk, as if reviewing it — would this be approved, coming from a stranger?
2. Clear out the orphans the change created: imports, variables, functions, and files now unused.
3. Run the language gates — format, lint, types, tests — from the matching `standards/<language>.md`.
4. Verify the real claim end to end ([`../thinking/verification.md`](../thinking/verification.md)), and report it at the strength of its evidence.

## Limits

- **The house style wins.** Where a codebase already has a convention, its naming, its idioms, and its layout outrank these defaults — a patch that reads foreign gets reverted ([`CORE.md`](../CORE.md), the loop).
- **A throwaway script** earns none of this ceremony past the security floor; durability poured into code that lives for minutes is wasted.
- **A measured exception** — a hot path, a platform quirk — is fine when a measurement or a hard requirement names the reason, and the code says so right at the spot.
