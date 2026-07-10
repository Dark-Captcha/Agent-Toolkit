# Agent-Toolkit — Claude Code bootstrap

<!--
  SETUP — this is a template. Copy it to ~/.claude/CLAUDE.md, fill in the path,
  then delete this comment block from the live file.

    1. Clone Agent-Toolkit anywhere, and keep it current with `git pull`.
    2. mkdir -p ~/.claude ~/.claude/agents ~/.claude/skills
    3. cp -n this file to ~/.claude/CLAUDE.md   (cp -n leaves an existing one intact)
    4. Replace every /ABSOLUTE/PATH/TO/Agent-Toolkit below with the clone path.

  Wire the agents and the skill — one link each, so they sit beside your own:

    ln -sfn /ABSOLUTE/PATH/TO/Agent-Toolkit/setup/claude-code/agents/*.md               ~/.claude/agents/
    ln -sfn /ABSOLUTE/PATH/TO/Agent-Toolkit/setup/claude-code/skills/reverse-engineering  ~/.claude/skills/

  Enforcement (a prompt before a known configuration-file edit) — copy the
  settings, or merge its keys into an existing settings.json:

    cp -n /ABSOLUTE/PATH/TO/Agent-Toolkit/setup/claude-code/settings.example.json  ~/.claude/settings.json

  The full walkthrough, the copy fallback for Windows, and a "check it worked"
  list live in the repository README.
-->

@/ABSOLUTE/PATH/TO/Agent-Toolkit/CORE.md

The `@` line above imports `CORE.md` — the constitution, always in force — whole into context at the start of every session.
It is an import rather than a SessionStart hook because Claude Code truncates hook output at ten kilobytes, silently, while an import always loads in full.

**Before the first response of every session, read `/ABSOLUTE/PATH/TO/Agent-Toolkit/AGENTS.md`.**

That file is the entry point: it maps out what to read for the task at hand.
The clone path on the lines above is the only place the local path lives; everything else is found relative to it, so `git pull` keeps the toolkit current without touching this file.
