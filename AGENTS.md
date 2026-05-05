<!-- BEGIN:wow-agent-rules -->

# World of Warcraft: ALWAYS read docs before coding

Before any World of Warcraft work, find and read the relevant doc in `../.libraries/wow-ui-source/`. Your training data is outdated — the docs are the source of truth.

<!-- END:wow-agent-rules -->

## Deploy to live client

When the user says **"ok im ready to test"** (or any clear deploy intent), run:

```
./deploy-to-wow.sh
```

The script:
1. Bumps the trailing `## Version:` segment in `BattleGroundEnemiesFixed.toc` (e.g. `12.0.5.8` → `12.0.5.9`). Prefix `12.0.5` is preserved — edit manually when WoW patches.
2. Wipes `/Applications/World of Warcraft/_retail_/Interface/AddOns/BattleGroundEnemiesFixed`.
3. Mirrors this repo into it, excluding dev-only files (`.git`, `AGENTS.md`, `DEFERRED.md`, `.libraries/`, etc. — see the script's header for the full list).

After running it, remind the user to `/reload` in-game (or relaunch the client) to pick up the changes.
