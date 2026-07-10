# Agent-Toolkit

The entry point for any coding agent working under this toolkit.
It does one job: point to the law, then map out what to read for the task at hand.

## Start here

[`CORE.md`](CORE.md) — the constitution — is in force every session.
The Claude Code setup imports it whole through the `@` line in `~/.claude/CLAUDE.md`, so it is already in context there; read it from disk only when it is not.
Everything else is loaded only when a task calls for it.

## The load map

Each document is read from disk the first time a task touches its area, and again whenever it has dropped out of context — after a compaction, or deep into a long session — because "already read this once" stops being true the moment the content is gone.
Read from disk, never from memory of what it once said.
`standards/coding.md` is loaded before the first `Edit` or `Write` to code — from disk, unless it is already in context.
Language and domain files load alongside the craft file they extend.

| When the task involves…                              | Read                                    |
| ---------------------------------------------------- | --------------------------------------- |
| an ambiguous request, or one naming its own solution | `thinking/intent.md`                    |
| designing anything new — an API, a schema, a system  | `thinking/design.md`                    |
| duplication, a growing diff, or the urge to abstract | `thinking/economy.md`                   |
| debugging, testing, or claiming that something works | `thinking/verification.md`              |
| reporting, explaining, asking, or disagreeing        | `thinking/communication.md`             |
| writing or changing code in any language             | `standards/coding.md`                   |
| a specific language                                  | `standards/<language>.md` + `coding.md` |
| the OXC compiler ecosystem                           | `reference/oxc.md`                      |
