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

  Enforcement (a prompt before a known configuration-file edit, and CORE.md injected each
  session) — copy the settings, or merge its keys into an existing settings.json:

    cp -n /ABSOLUTE/PATH/TO/Agent-Toolkit/setup/claude-code/settings.example.json  ~/.claude/settings.json
    (then set the cat path inside it to /ABSOLUTE/PATH/TO/Agent-Toolkit/CORE.md)

  The full walkthrough, the copy fallback for Windows, and a "check it worked"
  list live in the repository README.
-->

**Before the first response of every session, read `/ABSOLUTE/PATH/TO/Agent-Toolkit/AGENTS.md`.**

That file is the entry point: it directs the load of `CORE.md` — the constitution, always in force — and maps out what else to read for the task at hand.
The clone path above is the only place the local path lives; everything else is found relative to it, so `git pull` keeps the toolkit current without touching this file.
