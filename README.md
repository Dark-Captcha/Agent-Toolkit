# Agent-Toolkit

A small set of rules that give AI coding agents judgment instead of a checklist — one plain-markdown source of truth that every coding tool can read.

## Contents

- [For AI agents](#for-ai-agents)
- [Why it exists](#why-it-exists)
- [How it's organized](#how-its-organized)
- [Agents and skills](#agents-and-skills)
- [Get started](#get-started)
- [Check it worked](#check-it-worked)
- [The idea behind it](#the-idea-behind-it)
- [License](#license)

## For AI agents

**To operate under this toolkit,** load [`AGENTS.md`](AGENTS.md) — the map — and [`CORE.md`](CORE.md) — the law — before the first response, then pull a `thinking/`, `standards/`, or `reference/` file only when the task at hand touches its area, never all of them at once.

**To install it for someone,** follow [Get started](#get-started) below. The clone path is filled in twice — the `<toolkit>` token in the commands, and the `/ABSOLUTE/PATH/TO/Agent-Toolkit` placeholder inside the two copied files. If the path is unknown, ask the user where the repository should live, and never overwrite an existing `~/.claude` file without confirming first.

## Why it exists

Most instruction files for AI agents are checklists: do this, never that.
A checklist can be obeyed or broken, but it cannot be reasoned with — the moment a situation appears that its author never imagined, it falls silent.
Agent-Toolkit makes the opposite bet.
Every rule carries the reason behind it and the boundary where it stops, so an agent can re-derive the right behavior when the world stops matching the script.

What results is a body of doctrine rather than a list of commands: small, tool-agnostic, and written to stay correct while the tools and fashions around it change.

## How it's organized

The repository falls into three layers, sorted by how a reader reaches for them.

**The spine — read first, always.**

- `README.md` — this file, for humans.
- `AGENTS.md` — the entry point for agents: a map of what to load and when.
- `CORE.md` — the constitution: seven principles, the work loop, and the hard constraints.

**The library — loaded on demand, by topic.**

- `thinking/` — how to approach a problem: intent, design, economy, verification, communication, each file expanding one principle from CORE.
- `standards/` — how to write code: shared craft in `coding.md`, plus one file per language (Rust, TypeScript, JavaScript, Python, Mojo), each carrying a probed, dated toolchain pin.
- `reference/` — facts about specific external tools; `oxc.md` today.

**The wiring — everything tool-specific.**

- `setup/<tool>/` — how to connect the toolkit to one coding tool, one folder per tool. `setup/claude-code/` holds Claude Code's bootstrap, its agents, its skills, and a status line.

Every fact lives in exactly one file; everywhere else points to it with a link.
A copy drifts in silence; a link stays honest.

## Agents and skills

For Claude Code, the toolkit ships seven agents under `setup/claude-code/agents/`:

| Agent                        | What it does                                                     |
| ---------------------------- | ---------------------------------------------------------------- |
| `code-reviewer`              | adversarial review of a diff, verified findings only             |
| `bug-hunter`                 | sweep existing code for latent defects, no symptom needed        |
| `debugger`                   | a known failure to root cause, minimal fix, regression test      |
| `refactorer`                 | behavior-preserving restructure toward a stated finish line      |
| `experiment-runner`          | an autonomous single-metric optimization loop                    |
| `machine-learning-scientist` | diagnose why a model is wrong, then improve it by measured steps |
| `document-writer`            | write or reformat technical docs to a project's conventions      |

The `reverse-engineering` skill under `setup/claude-code/skills/` covers reverse engineering and binary or malware analysis with threat triage, and runs as the `/reverse-engineering` command.

## Get started

Clone the repository anywhere, and keep it current with `git pull`.
In the commands below, replace `<toolkit>` with the clone's absolute path.

```bash
git clone https://github.com/Dark-Captcha/Agent-Toolkit.git
```

**Claude Code** reads global files under `~/.claude/`:

```bash
mkdir -p ~/.claude ~/.claude/agents ~/.claude/skills

# bootstrap, agents, the skill, and the enforcement settings
cp -n <toolkit>/setup/claude-code/CLAUDE.example.md ~/.claude/CLAUDE.md
ln -sfn <toolkit>/setup/claude-code/agents/*.md ~/.claude/agents/
ln -sfn <toolkit>/setup/claude-code/skills/reverse-engineering ~/.claude/skills/
cp -n <toolkit>/setup/claude-code/settings.example.json ~/.claude/settings.json

# a status line — context (exact tokens), cost, plan tier, and rate-limit windows (needs jq)
cp -n <toolkit>/setup/claude-code/statusline-command.example.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

Then fill in the path: in the two copied files — `~/.claude/CLAUDE.md` and `~/.claude/settings.json` — replace every `/ABSOLUTE/PATH/TO/Agent-Toolkit` with the clone path, in an editor or with the installing agent's own file-editing tool (not a blind `sed -i`, which this toolkit's rules discourage).

If `~/.claude/CLAUDE.md` or `~/.claude/settings.json` already exists, `cp -n` leaves it untouched — **merge by hand** rather than overwrite: add the "read `AGENTS.md`" line to the CLAUDE.md, and the `permissions.ask` array, the `hooks.SessionStart` entry, and the `statusLine` key to the settings.json. (The toolkit's own "look before you destroy" rule applies to a config file too.)

What the enforcement actually buys: an `Edit` or `Write` to a known configuration file now prompts for approval, and `CORE.md` is injected at the start of every session and after a compaction — no read to skip. It is a strong backstop, not a wall: an in-place `sed -i` is gated too, but a configuration change written through some other `Bash` path — a heredoc, a `tee` — can still slip past, and the ask-list covers common configuration files, not every conceivable one.

**Windows, or anywhere symlinks are awkward:** copy the folders instead of linking. But a copied `agents/` or `skills/` folder loses the `../../../thinking/*.md` cross-references the agents depend on, so copy `thinking/`, `standards/`, and `reference/` next to them — or keep the full clone in place and copy only the leaf folders' contents beside it. Re-copy after each `git pull`.

**Any tool that reads the `AGENTS.md` standard** — Codex, Cursor, Cline, Windsurf — reads it from the project root, or from that tool's own rules location; place or symlink `<toolkit>/AGENTS.md` there. Those tools get the doctrine, but not the Claude-Code-only wiring: no `CORE.md` injection and no config-edit prompt, so on them those guarantees rest on the agent's discipline rather than a hook.

## Check it worked

After installing for Claude Code, confirm it before relying on it:

```bash
# no placeholder left behind (prints nothing, then "clean")
grep -R ABSOLUTE ~/.claude/CLAUDE.md ~/.claude/settings.json || echo "clean"

# the agents and skill resolve — not nested, not dangling
ls ~/.claude/agents/bug-hunter.md ~/.claude/skills/reverse-engineering/SKILL.md

# the injected file is real and prints its title
head -1 <toolkit>/CORE.md            # -> "# The Core"

# the settings file is valid JSON
python3 -m json.tool ~/.claude/settings.json > /dev/null && echo "settings OK"

# the status line runs (needs jq) and prints a box
echo '{"model":{"display_name":"Opus"}}' | ~/.claude/statusline-command.sh
```

Then start a **new** Claude Code session — agents, skills, and hooks load at session start, not mid-session — and check three things:

- `/agents` lists the seven agents, and typing `/reverse-engineering` offers the skill.
- Ask "what is your constitution, and what are its seven principles?" — a grounded answer proves `CORE.md` reached the model.
- Ask Claude to add a line to a scratch `test.toml` — the approval prompt should appear, proving the config gate is live.

## The idea behind it

One image anchors the whole toolkit: a heavy stone door.
Asked to make it easy to move, one builder bolts on a motor — impressive today, dead the day the motor fails.
Another rebalances the door on a pivot, so a child can swing it with one finger, for a thousand years.
Both answer the request; only one understands it.
The toolkit is built for the second kind of answer, and the full reasoning lives in [`CORE.md`](CORE.md).

## License

MIT — see [LICENSE](LICENSE).
