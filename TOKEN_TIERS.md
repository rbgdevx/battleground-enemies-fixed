# Unit token tiers (12.0.7) — docs-driven reference

Maintainer reference for which unit tokens can be trusted for what, derived
from Blizzard_APIDocumentationGenerated + Blizzard's own frame code
(CompactUnitFrame / NamePlateDriverMixin) + in-game verification (the
BGE_TokenRig experiment, 2026-07). Written down 2026-07-20 during the enemy
health-bar jumping investigation.

## Two hard classes of token

**Direct (base) tokens** — `arenaN`, `target`, `focus`, `nameplateN`,
`mouseover`, `softenemy`, `raidN`/`partyN` (allies):

- The event system fires FOR them: `UNIT_HEALTH("nameplate5")`,
  `UNIT_HEALTH("target")`, etc. Fresh at the moment something changes.
- Identity is single-hop: the token IS the unit.

**Compound (through-unit) tokens** — `targettarget`, `focustarget`,
`pettarget`, `raidNtarget`, `raidpetNtarget`, `nameplateNtarget`,
`arenaNtarget`:

- **No events, ever — poll-only.** WoW never fires `UNIT_HEALTH("raid3target")`.
  Their data is only as fresh as our own scan cadence (0.3–0.6s).
- Weakest-link secrecy: results are secret if ANY unit in the chain fails the
  identity check.
- Comparisons involving compound tokens are ALWAYS secret — they can never be
  cross-checked against anything (this is why the matcher cannot verify them).
- **In-game (rig-verified, 3+ games): their HEALTH reads render values that
  diverge from direct-token reads of the same unit at the same instant**, in
  both directions (stuck-full and stuck-low). E.g. `raid10target` vs `target`
  where raid10 IS the viewer — same unit by construction, different fill.

## The tier order

| Tier | Tokens | Why |
|---|---|---|
| 1 | `arenaN` | Direct, evented, persistent for the whole match; the ONLY token for objective icons + secure click targeting. Nothing else is close. |
| 2 | `target`, `focus` | Direct, evented, identity user-verified (you clicked that player) — but volatile: must detach the instant PLAYER_TARGET_CHANGED / PLAYER_FOCUS_CHANGED fires. |
| 3 | `nameplateN` | Direct, evented, pinned to ONE unit for the plate's lifetime (validated: Blizzard NamePlateDriverMixin sets unit once on ADDED / clears on REMOVED; oUF identical; both events synchronous). Only limit: plate range. |
| 4 | `softenemy`, `mouseover` | Direct but the most volatile (move with mouse / soft-targeting); mouseover has no ongoing events after the initial one. |
| 5 | ALL compound tokens | No events, always-secret comparisons, weakest-link secrecy, and rig-proven divergent health values. Last-resort feeds: good for keeping a frame alive at all, never preferable over any direct token. |

## UpdateEnemyUnitID chain (docs-corrected order — applied)

The chain (PlayerButton.lua ~line 708): Arena > Target > Focus > Nameplate >
SoftEnemy > Mouseover > TargetTarget > FocusTarget > PetTarget > GroupTarget >
GroupPetTarget > NameplateTarget > ArenaTarget.

Both docs-suggested corrections are IN as of v12.0.7.2x (2026-07-20):
1. `Nameplate` outranks `SoftEnemy`/`Mouseover` (pinned + evented beats
   mouse-volatile).
2. `PetTarget` sits down in the compound block (it is a through-unit token),
   below TargetTarget/FocusTarget.

## The core consequence (the health-jumping bug)

The chain ELECTS an active token but never gated WRITES — every scan/event
painted every bar (30–87% of writes per bar via compound tokens, alternating
with correct direct writes up to ~1,000×/game on hot buttons). Fix direction
(pure priority, never distance): writes land only from the elected token /
best-available family; compound paints only when nothing direct is attached.
