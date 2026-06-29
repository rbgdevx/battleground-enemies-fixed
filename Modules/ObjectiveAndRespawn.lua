---@class BattleGroundEnemies
local BattleGroundEnemies = BattleGroundEnemies

---@class Data
local Data = select(2, ...)
local GetTime = GetTime
local GetSpellTexture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture

local IsCataClassic = WOW_PROJECT_ID == WOW_PROJECT_CATACLYSM_CLASSIC

local L = Data.L

local defaultSettings = {
  Enabled = true,
  Parent = "Button",
  ActivePoints = 1,
  Points = {
    {
      Point = "LEFT",
      RelativeFrame = "Button",
      RelativePoint = "RIGHT",
      OffsetX = 0,
    },
  },
  Cooldown = {
    FontSize = 15,
    FontOutline = "OUTLINE", -- matches the global Cooldown default; preserves current look
    JustifyV = "MIDDLE",
    EnableShadow = true,
    ShadowColor = { 0, 0, 0, 0.8 },
    ShadowOffsetX = 1,
    ShadowOffsetY = -1,
  },
  Text = {
    FontSize = 15,
    FontOutline = "OUTLINE", -- Normal (overrides the global Text default of None)
    EnableShadow = true,
    ShadowColor = { 0, 0, 0, 0.8 },
    ShadowOffsetX = 1,
    ShadowOffsetY = -1,
  },
  UseButtonHeightAsHeight = true,
  UseButtonHeightAsWidth = true,
}

local options = function(location)
  return {
    TextSettings = {
      type = "group",
      name = L.Text,
      inline = true,
      order = 4,
      get = function(option)
        return Data.GetOption(location.Text, option)
      end,
      set = function(option, ...)
        return Data.SetOption(location.Text, option, ...)
      end,
      args = Data.AddNormalTextSettings(location.Text, nil, true, true),
    },
    CooldownTextSettings = {
      type = "group",
      name = L.Countdowntext,
      inline = true,
      get = function(option)
        return Data.GetOption(location.Cooldown, option)
      end,
      set = function(option, ...)
        return Data.SetOption(location.Cooldown, option, ...)
      end,
      order = 2,
      args = Data.AddCooldownSettings(location.Cooldown, true, true, true),
    },
  }
end

-- Map-type helpers. After the 2026-05-02 source migration, both
-- CheckAllOrbs and CheckAllFlags read from Data.BattlegroundspezificBuffs
-- (the user moved orbs into Buffs alongside flags so there's a single
-- source of truth). The historical bug — CheckAllOrbs reading
-- Data.BattlegroundspezificDebuffs[206] = {46392, 46393} (Focused/Brutal
-- Assault) and stamping those icons onto Twin Peaks flag carriers — is
-- structurally impossible now. These helpers remain to gate the unconditional
-- event-handler sweeps to the maps they target: small perf win (skip
-- non-existent arena3/4 in flag BGs) and explicit map-type intent.
local function IsFlagBG(mapId)
  return mapId == 206 -- Twin Peaks
    or mapId == 1339 -- Warsong Gulch
    or mapId == 112 -- Eye of the Storm
    or mapId == 397 -- Eye of the Storm RBG
    or mapId == 2345 -- Deephaul Ravine
end

local function IsOrbBG(mapId)
  return mapId == 417 -- Temple of Kotmogu
end

-- Helper: Find the correct button for an arena orb carrier
-- Enemy side uses PID matching (needed — arena tokens to unknown-identity
-- enemies). Ally side uses the direct token map — no PID for allies, ever.
local function GetOrbCarrierButton(unitID)
  -- Trust existing mapping unless live data contradicts it.
  -- The chat handler binds carriers by NAME (definitive identity); the
  -- matcher used below binds by FINGERPRINT (probabilistic). When chat
  -- already correctly bound this slot, we must NOT let a fingerprint
  -- match overwrite that authoritative result. Only re-resolve when:
  --   (a) no mapping exists yet, or
  --   (b) the existing mapping is concretely contradicted by live
  --       class/race on this unitID (handles real carrier swaps where
  --       chat for some reason failed to fire).
  local currentMapping = BattleGroundEnemies.ArenaIDToPlayerButton[unitID]
  if currentMapping and not BattleGroundEnemies:ArenaMappingContradicted(currentMapping, unitID) then
    return currentMapping
  end

  BattleGroundEnemies:ClearScanCycleCache()
  local matchedButton = BattleGroundEnemies:GetPlayerbuttonByUnitID(unitID, "Enemies", true)
    or BattleGroundEnemies.Allies:GetAllyButtonByUnitID(unitID)

  if not matchedButton then
    return nil
  end

  if currentMapping == matchedButton then
    return matchedButton -- Mapping is already correct
  end

  -- Bidirectional cleanup needed

  -- 1. Clear stale mapping FROM the arena token (old button that had this token)
  if currentMapping and currentMapping ~= matchedButton then
    currentMapping:UpdateEnemyUnitID("Arena", false)
    currentMapping:DispatchEvent("ArenaOpponentHidden") -- Reset trinket, etc.
  end

  -- 2. Clear stale mapping FROM the matched button (if it had a different arena token)
  local oldArena = matchedButton.UnitIDs and matchedButton.UnitIDs.Arena
  if oldArena and oldArena ~= unitID then
    BattleGroundEnemies.ArenaIDToPlayerButton[oldArena] = nil
    -- Note: matchedButton will get ArenaOpponentShown below, which handles the transition
  end

  -- 3. Assign fresh mapping
  matchedButton:ArenaOpponentShown(unitID)

  return matchedButton
end

-- Module-level function to check orbs for all arena units
-- In Kotmogu BG, WoW assigns arena tokens (arena1-5) to orb carriers
local isCheckingOrbs = false
local function CheckAllOrbs()
  if isCheckingOrbs then
    return
  end
  isCheckingOrbs = true

  local ok, err = pcall(function()
    -- No "clear stale" sweep here: ARENA_OPPONENT_UPDATE with
    -- unitEvent=="cleared" is the authoritative signal for arena-token
    -- invalidation (see Main.lua:1268). Using UnitExists as our own
    -- invalidation check produces false positives (e.g., user dies, all
    -- arena tokens report nonexistent, we wrongly wipe the carrier icon).

    -- Show orbs on players who have them.
    --
    -- 2026-05-02 source migration: orbs now live in BattlegroundspezificBuffs
    -- alongside flags (single source of truth). KEY-FORMAT NOTE: the old
    -- Debuffs[417] was a Lua sequence with 1-based keys ({1=Blue, 2=Purple,
    -- 3=Green, 4=Orange}); the new Buffs[417] uses explicit 0-based keys
    -- ({[0]=Blue, [1]=Purple, [2]=Green, [3]=Orange}). The loop counter i
    -- runs 1..4 for arenaN, so we offset to (i-1) to land on the right
    -- 0-based key — same pattern flags already use.
    for i = 1, 4 do
      local unitID = "arena" .. i
      if UnitExists(unitID) then
        local battlegroundBuffs = BattleGroundEnemies:GetBattlegroundAuras()
        local button = GetOrbCarrierButton(unitID)
        if button and button.ObjectiveAndRespawn and battlegroundBuffs then
          local spellId = battlegroundBuffs[i - 1]
          if spellId then
            button.ObjectiveAndRespawn.Icon:SetTexture(GetSpellTexture(spellId))
            button.ObjectiveAndRespawn:Show()
          end
        end
      end
    end
  end)

  isCheckingOrbs = false
  if not ok then
    error(err)
  end
end

-- Helper: Find the correct button for a flag carrier
-- Enemy side uses PID matching. Ally side uses the direct token map — no PID.
local function GetFlagCarrierButton(unitID)
  -- Trust existing mapping unless live data contradicts it. Same reasoning
  -- as GetOrbCarrierButton above — chat handler is the authoritative
  -- name-based binder; matcher below is fingerprint-based and must not
  -- overwrite a chat-set mapping that's still consistent with live data.
  local currentMapping = BattleGroundEnemies.ArenaIDToPlayerButton[unitID]
  if currentMapping and not BattleGroundEnemies:ArenaMappingContradicted(currentMapping, unitID) then
    return currentMapping
  end

  BattleGroundEnemies:ClearScanCycleCache()
  local matchedButton = BattleGroundEnemies:GetPlayerbuttonByUnitID(unitID, "Enemies", true)
    or BattleGroundEnemies.Allies:GetAllyButtonByUnitID(unitID)

  if not matchedButton then
    return nil
  end

  if currentMapping == matchedButton then
    return matchedButton -- Mapping is already correct
  end

  -- Bidirectional cleanup needed

  -- 1. Clear stale mapping FROM the arena token (old button that had this token)
  if currentMapping and currentMapping ~= matchedButton then
    currentMapping:UpdateEnemyUnitID("Arena", false)
    currentMapping:DispatchEvent("ArenaOpponentHidden") -- Reset trinket, etc.
  end

  -- 2. Clear stale mapping FROM the matched button (if it had a different arena token)
  local oldArena = matchedButton.UnitIDs and matchedButton.UnitIDs.Arena
  if oldArena and oldArena ~= unitID then
    BattleGroundEnemies.ArenaIDToPlayerButton[oldArena] = nil
  end

  -- 3. Assign fresh mapping
  matchedButton:ArenaOpponentShown(unitID)

  return matchedButton
end

-- Module-level function to check flags for all arena units (WSG, Twin Peaks, Deephaul Ravine)
local isCheckingFlags = false
local function CheckAllFlags()
  if isCheckingFlags then
    return
  end
  isCheckingFlags = true

  local ok, err = pcall(function()
    -- No "clear stale" sweep here: ARENA_OPPONENT_UPDATE with
    -- unitEvent=="cleared" is the authoritative signal for arena-token
    -- invalidation (see Main.lua:1268). Using UnitExists as our own
    -- invalidation check produces false positives (e.g., user dies, all
    -- arena tokens report nonexistent, we wrongly wipe the carrier icon).

    -- Show flags on players who have them.
    --
    -- Source: BattlegroundspezificBuffs (single source of truth post the
    -- 2026-05-02 source migration). Buffs is 0-keyed:
    --   arena1 = Horde-team carrier (carrying Alliance flag) → buffs[0]
    --   arena2 = Alliance-team carrier (carrying Horde flag)  → buffs[1]
    -- Same (i-1) indexing pattern as CheckAllOrbs / frame:ArenaOpponentShown.
    for i = 1, 2 do
      local unitID = "arena" .. i
      if UnitExists(unitID) then
        local battlegroundBuffs = BattleGroundEnemies:GetBattlegroundAuras()
        local button = GetFlagCarrierButton(unitID)
        if button and button.ObjectiveAndRespawn and battlegroundBuffs then
          local spellId = battlegroundBuffs[i - 1]
          if spellId then
            button.ObjectiveAndRespawn.Icon:SetTexture(GetSpellTexture(spellId))
            button.ObjectiveAndRespawn:Show()
          end
        end
      end
    end
  end)

  isCheckingFlags = false
  if not ok then
    error(err)
  end
end

-- Forward declaration: defined after BindChatCarrierToArenaSlot (which it
-- depends on). Assigned (not re-declared with `local function`) so this upvalue
-- is the one RefreshObjectiveCarriers below closes over.
local ReplayPersistedCarriers

-- Public refresh: re-scans orb and flag carriers right now.
-- Called by BGEF's UBS handler so mid-match joiners / reloads pick up state
-- that was established before their per-button PLAYER_ENTERING_WORLD fired.
function BattleGroundEnemies:RefreshObjectiveCarriers()
  CheckAllOrbs()
  CheckAllFlags()

  -- Reload-while-dead replay (see the PersistChatCarriers comment block).
  -- This is the roster-ready hook: RefreshObjectiveCarriers is called from the
  -- UBS roster rebuild (Main.lua) and on resurrect, so by the time it runs the
  -- enemy buttons exist. ReplayPersistedCarriers is defined further down (after
  -- BindChatCarrierToArenaSlot, which it relies on); it's forward-declared as a
  -- file-local so this earlier closure can see it.
  if ReplayPersistedCarriers then
    ReplayPersistedCarriers()
  end
end

-- ----------------------------------------------------------------------------
-- Chat-message-driven flag-carrier identification.
--
-- The arena-token PID matcher in CheckAllFlags can attribute the objective
-- icon to the wrong same-class enemy button when class+race+gender+honor+guild
-- don't disambiguate (PvP secrecy denies the matcher anything more granular).
-- BG system messages emit the carrier's full Name-Realm in non-secret form
-- (verified empirically 2026-05-01: secret=false). That gives us authoritative
-- name lookup via Players[name], bypassing the fingerprint resolver.
--
-- Coexistence with CheckAllFlags: when chat tracks any carrier, CheckAllFlags
-- skips its arena-token sweep so it can't override the chat-set icon onto a
-- wrong button. When no chat-tracked carriers exist (e.g. non-English client
-- where the patterns below don't match), CheckAllFlags runs as before.
--
-- Pickup is fully implemented and tested. Drop / capture / return patterns
-- are best-effort guesses — confirmed text from real BGs may need pattern
-- tweaks. ChatMessages are non-localized here; if a non-English locale needs
-- support, swap the patterns to use Blizzard's localized global strings.
-- ----------------------------------------------------------------------------

-- name → arenaIndex (the slot we bound for them).
local chatFlagCarriers = {}
-- arenaIndex → name. Kotmogu's 4 orbs are statically bound to arena slots:
--   arena1 = Blue, arena2 = Purple, arena3 = Green, arena4 = Orange.
-- Same convention used by CheckAllOrbs / battleGroundDebuffs[i].
local chatOrbCarriers = {}

-- Reload-while-dead recovery (mirrors the oracle's RestoreCarriersOnEntering).
-- A /reload destroys every objective icon and wipes ArenaIDToPlayerButton + the
-- chat tables + the roster, and ARENA_OPPONENT_UPDATE does NOT replay — so a
-- still-held enemy carrier shows nothing until the viewer respawns. We persist
-- the chat carrier bindings to a SavedVariable; on a same-match reload-while-
-- dead we keep them and, once the enemy roster has rebuilt (~5s post-reload via
-- UPDATE_BATTLEFIELD_SCORE -> RefreshObjectiveCarriers), REPLAY each binding
-- name-authoritatively. This is one-shot and event-driven (never the 1s
-- ticker), uses only non-secret chat names (no taint), and is naturally bounded
-- by roster rebuild (BGEF draws per-player buttons, so an icon cannot exist
-- before its player's button does — this delay is inherent to BGEF's per-button
-- architecture, unlike the oracle's dedicated arena frames; accept it).
local pendingReplay = false
local MAX_REPLAY_ATTEMPTS = 20 -- ~20 UBS ticks; ample for the ~5s roster rebuild
local replayAttempts = 0

-- Snapshot the current chat bindings + map to db.global so a /reload can
-- restore them. Non-secret chat names only. Called after every chat-driven
-- mutation (HandleObjectiveChatMessage) and after the ARENA "cleared" teardown.
local function PersistChatCarriers()
  local db = BattleGroundEnemies.db
  if not (db and db.global) then
    return
  end
  if not next(chatFlagCarriers) and not next(chatOrbCarriers) then
    db.global.ObjectiveCarriers = nil
    return
  end
  local states = BattleGroundEnemies:GetActiveStates()
  local mapId = states and states.currentMapId
  local flag, orb = {}, {}
  for name, slot in pairs(chatFlagCarriers) do
    flag[name] = slot
  end
  for slot, name in pairs(chatOrbCarriers) do
    orb[slot] = name
  end
  db.global.ObjectiveCarriers = { mapId = mapId, flag = flag, orb = orb }
end

local orbColorToArenaIndex = {
  Blue = 1,
  Purple = 2,
  Green = 3,
  Orange = 4,
}

-- The "|cAARRGGBB" color-code prefix as a Lua pattern: literally 8 hex digits.
-- Shared by every orb-pickup matcher below (carrier identity AND the stack
-- clock) so the "exactly 8, not a greedy %x+" fix — a greedy class once ate the
-- leading "B" of "Blue" because B is a hex digit — can never drift out of sync
-- between the call sites. Verified in Lua.
local ORB_COLOR_CODE_PATTERN = "|c%x%x%x%x%x%x%x%x"

-- Flag FACTION -> arena slot. Keyed by the faction word alone (parsed
-- case-insensitively from the pickup message, mirroring follow-the-flag's
-- battle-tested "The (%a+) [Ff]lag was picked up by (.+)") so a casing/wording
-- change to "flag"/"Flag" can't silently drop the bind — the previous exact
-- "Alliance Flag"/"Horde Flag" string lookup would.
--   Slot convention (verified by user testing original code):
--   arena1 = Horde-team carrier  (a Horde player carrying the Alliance flag)
--   arena2 = Alliance-team carrier (an Alliance player carrying the Horde flag)
local flagFactionToArenaIndex = {
  Alliance = 1, -- Alliance flag (carried by a Horde player) → arena1
  Horde = 2, -- Horde flag (carried by an Alliance player) → arena2
}

local function GetButtonForCarrier(name)
  -- Players[] is canonicalized to "Name-Realm" form by the CanonicalName
  -- helper (Main.lua), and BG chat messages always emit "Name-Realm". So
  -- a direct lookup hits on both cross-realm and same-realm carriers.
  -- Pass through CanonicalName for idempotency / safety against any
  -- future caller that hands us a short form.
  if not name then
    return nil
  end
  local key = BattleGroundEnemies:CanonicalName(name)
  return BattleGroundEnemies.Enemies.Players[key] or BattleGroundEnemies.Allies.Players[key]
end

-- Bind a chat-named carrier to an arena slot via the existing
-- ArenaOpponentShown event infrastructure, so the icon-spell mapping in
-- frame:ArenaOpponentShown picks the right texture and other modules
-- (Trinket, etc.) get notified consistently. Mirrors the cleanup logic
-- that GetOrbCarrierButton/GetFlagCarrierButton already do for the
-- arena-token / PID path: tear down stale mappings before binding new.
local function BindChatCarrierToArenaSlot(name, arenaIndex)
  local newButton = GetButtonForCarrier(name)
  if not newButton then
    -- DIAG (TEMP, 2026-05-02): cross-realm carrier-icon miss hunt.
    -- Cross-realm hypothesis: chat emits bare "Name", CanonicalName appends
    -- the LOCAL player's realm, but Players[] keyed under carrier's actual
    -- realm. Dump the canonical key we tried, plus any Players[] entry
    -- whose short form matches — that pair confirms or denies the theory.
    -- Remove this block (and the WRONG-BUTTON one below, plus the matcher
    -- wrapper in Main.lua) once root cause is identified.
    -- local canonicalTried = BattleGroundEnemies:CanonicalName(name)
    -- local nearMatches = {}
    -- local function scan(side, dict)
    --   if not dict then
    --     return
    --   end
    --   for k, _ in pairs(dict) do
    --     local short = type(k) == "string" and k:match("^([^%-]+)") or nil
    --     if short == name or k == name then
    --       table.insert(nearMatches, side .. ":" .. tostring(k))
    --     end
    --   end
    -- end
    -- scan("E", BattleGroundEnemies.Enemies and BattleGroundEnemies.Enemies.Players)
    -- scan("A", BattleGroundEnemies.Allies and BattleGroundEnemies.Allies.Players)
    -- local nearStr = (#nearMatches > 0) and table.concat(nearMatches, ", ") or "(none)"
    -- Diagnostic: re-enable to debug a chat-name-to-Players[] miss.
    -- print(string.format(
    --   "|cffff5555[BGE diag]|r chat-bind FAILED: name=%s arena=%d canonicalTried=%s shortMatchesInPlayers=%s",
    --   tostring(name), arenaIndex, tostring(canonicalTried), nearStr
    -- ))
    return false
  end

  local arenaToken = "arena" .. arenaIndex
  local prevButton = BattleGroundEnemies.ArenaIDToPlayerButton[arenaToken]

  -- DIAG (TEMP, 2026-05-01): same-class-twin health-misroute hunt. Only
  -- fires on the suspicious case — chat says NameX but Players[NameX]
  -- returned a button whose stored PlayerName is something else (would
  -- indicate Players-dict corruption). Successful binds (chatName matches
  -- button name) are silent. Pair with the matcher-wrapper print in
  -- Main.lua. Remove BOTH together once root cause is identified.
  -- local newName = newButton.PlayerDetails and newButton.PlayerDetails.PlayerName
  -- local canonicalChat = BattleGroundEnemies:CanonicalName(name)
  -- if newName and canonicalChat and newName ~= canonicalChat then
  --   local prevName = prevButton and prevButton.PlayerDetails and prevButton.PlayerDetails.PlayerName
  --   -- Diagnostic: re-enable to debug Players[] dict corruption.
  --   print(string.format(
  --     "|cffff5555[BGE diag]|r chat-bind WRONG-BUTTON: chatName=%s (canonical=%s) arena=%d -> button[%s] (prev=%s)",
  --     tostring(name), tostring(canonicalChat), arenaIndex, tostring(newName), tostring(prevName)
  --   ))
  -- end

  if prevButton == newButton then
    -- Already bound. Re-dispatch to refresh icon state in case the
    -- button's frame just initialized.
    newButton:ArenaOpponentShown(arenaToken)
    return true
  end

  -- 1. The arena slot's previous button (if any): tear down its arena
  --    binding + dispatch hidden so its icon clears.
  if prevButton then
    prevButton:UpdateEnemyUnitID("Arena", false)
    prevButton:DispatchEvent("ArenaOpponentHidden")
  end
  -- 2. The new button's previous arena slot (if it had one bound to a
  --    different slot): un-key the old slot.
  local oldArena = newButton.UnitIDs and newButton.UnitIDs.Arena
  if oldArena and oldArena ~= arenaToken then
    BattleGroundEnemies.ArenaIDToPlayerButton[oldArena] = nil
  end

  newButton:ArenaOpponentShown(arenaToken)
  return true
end

-- Reload-while-dead replay body (assigned to the forward-declared upvalue so
-- RefreshObjectiveCarriers can drive it). One-shot, retried across UBS ticks
-- until the roster has rebuilt the carriers' buttons. Re-binds each persisted
-- chat carrier name-authoritatively (BindChatCarrierToArenaSlot is name-based:
-- no UnitExists, no secret reads, wrong-twin-proof). Returns false while a
-- carrier's button isn't built yet, so we keep pendingReplay set and try again.
--
-- FIX A — LIVENESS GATE (mirrors the oracle's RestoreCarriersOnEntering idiom
-- `not UnitExists(unit) and UnitName(unit)`): only re-bind a saved slot when its
-- arena token is still genuinely present, i.e. UnitName("arenaN") resolves
-- (non-nil). UnitName works while the viewer is dead so long as the carrier is
-- still there, and goes nil once the token was CLEARED during the reload gap. So
-- a carrier who DROPPED the objective mid-reload is NOT resurrected — its dead
-- saved entry is pruned instead of kept pending forever. The UnitName return is
-- used ONLY as a boolean liveness predicate; it is passed to no string op, and
-- identity resolution stays name-authoritative via GetButtonForCarrier /
-- CanonicalName inside BindChatCarrierToArenaSlot (NOT the stock UnitName).
local function replaySavedSlot(name, arenaIndex, dropEntry)
  -- Liveness gate: token cleared during the reload gap -> carrier is gone.
  -- Prune the stale saved binding (resolved, not pending) and persist.
  if not UnitName("arena" .. arenaIndex) then
    dropEntry()
    PersistChatCarriers()
    return false -- not "still pending": this slot is resolved (dead)
  end
  -- Token still live: re-bind name-authoritatively. Returns false (still
  -- pending) only while the carrier's button hasn't been rebuilt yet.
  return not BindChatCarrierToArenaSlot(name, arenaIndex)
end

ReplayPersistedCarriers = function()
  if not pendingReplay then
    return
  end
  replayAttempts = replayAttempts + 1
  local stillPending = false
  for name, arenaIndex in pairs(chatFlagCarriers) do
    if replaySavedSlot(name, arenaIndex, function()
      chatFlagCarriers[name] = nil
    end) then
      stillPending = true
    end
  end
  for arenaIndex, name in pairs(chatOrbCarriers) do
    if replaySavedSlot(name, arenaIndex, function()
      chatOrbCarriers[arenaIndex] = nil
    end) then
      stillPending = true
    end
  end
  if not stillPending or replayAttempts >= MAX_REPLAY_ATTEMPTS then
    pendingReplay = false
    replayAttempts = 0
  end
end

-- Tear down a chat-tracked carrier's arena binding (mirror of
-- BindChatCarrierToArenaSlot's setup). Does NOT remove the entry from
-- the chatFlagCarriers / chatOrbCarriers tables — callers handle that
-- so we don't have to know which table owns this name.
local function UnbindChatCarrier(name, arenaIndex)
  local button = GetButtonForCarrier(name)
  if not button then
    return
  end
  button:UpdateEnemyUnitID("Arena", false)
  button:DispatchEvent("ArenaOpponentHidden")
  if arenaIndex then
    local arenaToken = "arena" .. arenaIndex
    if BattleGroundEnemies.ArenaIDToPlayerButton[arenaToken] == button then
      BattleGroundEnemies.ArenaIDToPlayerButton[arenaToken] = nil
    end
  end
end

-- Tear down all chat-tracked flag carriers (capture / return / wins / start).
local function ClearAllChatFlagCarriers()
  for name, arenaIndex in pairs(chatFlagCarriers) do
    UnbindChatCarrier(name, arenaIndex)
  end
  wipe(chatFlagCarriers)
end

-- Tear down all chat-tracked orb carriers (wins).
local function ClearAllChatOrbCarriers()
  for arenaIndex, name in pairs(chatOrbCarriers) do
    UnbindChatCarrier(name, arenaIndex)
  end
  wipe(chatOrbCarriers)
end

local function HandleObjectiveChatMessage(msg)
  if not msg or type(msg) ~= "string" then
    return
  end
  if issecretvalue and issecretvalue(msg) then
    return
  end

  -- Patterns are taken from BattlegroundWinConditions/predictions/{flags,orbs}.lua
  -- where they're battle-tested in production. Messages use the same forms
  -- across the ALLIANCE / HORDE / NEUTRAL channels — we match on text
  -- regardless of channel. NEUTRAL covers global state events (start of
  -- match, both flags placed, game wins); ALLIANCE/HORDE cover team-specific
  -- pickup / drop / capture / return events.
  --
  -- Carriers are bound to the appropriate arenaN slot via
  -- BindChatCarrierToArenaSlot so the existing ArenaOpponentShown event
  -- chain handles the icon-spell mapping (the per-button frame:ArenaOpponentShown
  -- handler reads playerButton.UnitIDs.Arena and picks the right
  -- battlegroundBuffs / battleGroundDebuffs index).

  -- Flag pickup: "The Horde Flag was picked up by NAME!" / "The Alliance Flag was picked up by NAME!"
  local pickedUpBy = msg:match("picked up by (.+)%!")
  if pickedUpBy then
    -- Faction word, case-insensitive on "flag"/"Flag" (ftf's proven pattern);
    -- strict superset of the old exact "The Alliance Flag was picked up" lookup.
    local faction = msg:match("The (%a+) [Ff]lag was picked up")
    local arenaIndex = faction and flagFactionToArenaIndex[faction]
    if arenaIndex and BindChatCarrierToArenaSlot(pickedUpBy, arenaIndex) then
      chatFlagCarriers[pickedUpBy] = arenaIndex
    end
    return
  end

  -- Deephaul Ravine crystal pickup: "NAME has taken the crystal!"
  -- Single shared crystal (either team can carry, like Eye of the Storm), so
  -- there's no flag-name → arena-slot mapping to consult — just bind to slot
  -- 1. Both Data.BattlegroundspezificBuffs[2345][0] and [1] point at the same
  -- spell (434339 Deephaul Crystal), so the slot choice is cosmetic.
  -- Capture is handled by the existing "captured the" reset branch below;
  -- Deephaul Ravine's deposit message is "NAME has captured the flag!" which
  -- already matches that filter.
  local crystalCarrier = msg:match("^(.-) has taken the crystal!")
  if crystalCarrier then
    if BindChatCarrierToArenaSlot(crystalCarrier, 1) then
      chatFlagCarriers[crystalCarrier] = 1
    end
    return
  end

  -- Eye of the Storm flag pickup: "NAME has taken the flag!" (verified in-game).
  -- EotS uses ONE neutral flag (Netherstorm Flag) and the message names the
  -- player, so — like the Deephaul crystal — bind to slot 1; the icon spell is
  -- Data.BattlegroundspezificBuffs[112/397][0] (34976, Netherstorm Flag).
  -- Distinct from "has taken the crystal" and the colored orb message, and from
  -- "has captured the flag" (handled by the "captured the" reset below).
  -- Drop/return surfaces as "The flag has been reset" (un-gated for EotS below)
  -- or the binding-agnostic arena-token "cleared".
  local eotsFlagCarrier = msg:match("^(.-) has taken the flag")
  if eotsFlagCarrier then
    if BindChatCarrierToArenaSlot(eotsFlagCarrier, 1) then
      chatFlagCarriers[eotsFlagCarrier] = 1
    end
    return
  end

  -- Flag drop with explicit carrier: "X Flag was dropped by NAME!"
  local droppedBy = msg:match("dropped by (.+)%!")
  if droppedBy then
    local arenaIndex = chatFlagCarriers[droppedBy]
    chatFlagCarriers[droppedBy] = nil
    UnbindChatCarrier(droppedBy, arenaIndex)
    return
  end

  -- Orb pickup (Kotmogu): "NAME has taken the |cAARRGGBBColor|r orb!"
  -- We only need the bare color name (Blue / Purple / Green / Orange) to
  -- map to the static arena slot — capture it directly out of the color
  -- codes rather than match-then-strip. If that slot already had a
  -- chat-tracked carrier (the previous holder before they dropped it),
  -- tear down that binding first.
  local orbCarrierName = msg:match("^(.-) has taken the")
  -- Color code matched via the shared ORB_COLOR_CODE_PATTERN (exactly 8 hex
  -- digits) so this and the stack-clock matcher can't drift apart.
  local orbColor = msg:match("the " .. ORB_COLOR_CODE_PATTERN .. "(%a+)|r orb")
  if orbCarrierName and orbColor then
    local arenaIndex = orbColorToArenaIndex[orbColor]
    if arenaIndex then
      local prevCarrier = chatOrbCarriers[arenaIndex]
      if prevCarrier and prevCarrier ~= orbCarrierName then
        UnbindChatCarrier(prevCarrier, arenaIndex)
      end
      if BindChatCarrierToArenaSlot(orbCarrierName, arenaIndex) then
        chatOrbCarriers[arenaIndex] = orbCarrierName
      end
      return
    end
  end

  -- Global state-reset events. None of these reliably embed a single carrier
  -- name, and they all imply ALL chat-tracked carriers should be cleared.
  --   "captured the" / "returned to its base by" / "placed at their bases"
  --     — flag-only resets in Warsong Gulch / Twin Peaks / Deephaul Ravine.
  --   "wins" — game over (any BG); resets both flag and orb tracking.
  if msg:find("captured the") or msg:find("returned to its base by") or msg:find("placed at their bases") then
    ClearAllChatFlagCarriers()
    return
  end
  -- "The flag has been reset" — confirmed in Deephaul Ravine (dropped crystal
  -- returns to spawn) AND Eye of the Storm (verified in-game: the neutral flag
  -- returns to center after a drop/death). Gated to those maps only because
  -- Warsong Gulch / Twin Peaks aren't confirmed to avoid the same string, and a
  -- global match there could wrongly clear a real carrier.
  if msg:find("The flag has been reset") then
    local states = BattleGroundEnemies:GetActiveStates()
    local mapId = states and states.currentMapId
    if mapId == 2345 or mapId == 112 or mapId == 397 then
      ClearAllChatFlagCarriers()
    end
    return
  end
  if msg:find("wins") then
    ClearAllChatFlagCarriers()
    ClearAllChatOrbCarriers()
    return
  end
end

-- ============================================================================
-- Objective stack-value simulation
--
-- Ported from objective-frames/core/stacks.lua (the validated oracle) and
-- battleground-win-conditions. Carrier stacks can't be read off enemy units
-- (no aura data out of render range + PvP secret restrictions in 12.0), so they
-- are simulated from event time. The OG BattleGroundEnemies read these straight
-- off auras (SearchForDebuffs -> aura.points[2] / aura.applications); that path
-- is dead for secret / out-of-range carriers, so we keep its UI (frame.AuraText
-- + the Text settings group) and drive it from simulated time instead.
--
-- Two shapes:
--   ORBS (Kotmogu): one clock per carrier slot. Value = damage-taken-increase %
--     (base on pickup, +base per interval held). Pickup = chat "X has taken the
--     <color> orb" (authoritative, resets the clock) or an arena-token seed on
--     late join. Removal = arena "cleared" (a dropped orb resets to base).
--     Match end = the NEUTRAL "wins" message.
--   FLAGS (WSG / Twin Peaks): one SHARED clock (Focused Assault). It starts when
--     BOTH flags are held and gains a stack per interval (no cap). Both carriers
--     show the same raw COUNT. Drops do NOT stop the clock (a re-pick keeps the
--     stacks); only a return-with-both-home, a capture, "placed at their bases",
--     or match end resets it. Channel semantics mirror bgwc: the ALLIANCE
--     channel announces the alliance flag (horde's carrier, arena1), the HORDE
--     channel the horde flag (alliance's carrier, arena2).
--
-- Times are epoch (time(), not GetTime()) and persist in db.global.stacksState
-- so values stay accurate through /reload — even a client crash — validated
-- against the map + live match clock so stale state from an earlier match is
-- discarded. Eye of the Storm / Deephaul Ravine are intentionally absent (no
-- stacking objective buff): their carriers show the icon but no number.
-- ============================================================================

local STACK_NUM_SLOTS = 4 -- Kotmogu has 4 orb slots; flag maps use 1-2 (shared clock)

-- Which maps get simulated stacks, and how (mirrors objective-frames
-- ns.objectiveStackConfig exactly so the two addons stay in lockstep).
local stackConfig = {
  [417] = { mode = "orb", increment = 30, interval = 15 }, -- Kotmogu: 30% on pickup, +30% per 15s held
  [1339] = { mode = "flag", interval = 30, blitzInterval = 15 }, -- Warsong Gulch: 1 stack / 30s (15s Blitz)
  [206] = { mode = "flag", interval = 30, blitzInterval = 15 }, -- Twin Peaks: 1 stack / 30s (15s Blitz)
}

-- Kotmogu arena tokens are fixed orb colors. Chat is the only signal that names
-- the orb, as a color-coded word ("|cFF01DFD7Blue|r"). English clients only,
-- same limitation as bgwc / objective-frames.
local STACK_ORB_COLOR_TO_INDEX = { Blue = 1, Purple = 2, Green = 3, Orange = 4 }

-- Flags: held state from UI widget 1640 (bgwc FlagTracker parity). Server-driven
-- and correct while dead or out of render range, unlike the arena tokens.
local STACK_FLAG_WIDGET = 1640

local stackCfg -- stackConfig entry for the current map (nil = inactive)
local stackMapId
local stackPickup = {} -- orbs: [arenaIndex] = pickup epoch seconds
local stackAssaultStart -- flags: epoch the shared Focused Assault clock started (nil = idle)
local stackAllyHasFlag, stackHordeHasFlag = false, false -- flags: which teams hold one
local stackFlagInterval -- flags: seconds per stack this match (interval or blitzInterval)
local stackFlagIntervalSaved = false -- flags: interval came from a validated restore
-- Flags: whether we've had continuous knowledge of the assault cycle since a
-- known state (validated same-match save, or both flags confirmed home). Joining
-- mid-match with a flag up means an unseen cycle may already be running and its
-- true count is unknowable (auras are secret), so the clock must NOT start on
-- later pickups until the next confirmed both-home.
local stackStateTrusted = false
local stackTicker

-- The SavedVariable lives in db.global alongside ObjectiveCarriers. Created
-- lazily (AceDB only copies declared defaults; dynamic keys persist fine).
local function GetStackSV()
  local db = BattleGroundEnemies.db
  if not (db and db.global) then
    return nil
  end
  local saved = db.global.stacksState
  if not saved then
    saved = { pickup = {} }
    db.global.stacksState = saved
  end
  saved.pickup = saved.pickup or {}
  return saved
end

local function StackSaveState()
  local saved = GetStackSV()
  if not saved then
    return
  end
  saved.mapId = stackMapId or 0
  saved.assault = stackAssaultStart or 0
  saved.interval = stackFlagInterval or 0
  -- Write stamp: lets a restore prove the save came from THIS match even when
  -- no clock was running (assault/pickups all zero).
  saved.written = time()
  for i = 1, STACK_NUM_SLOTS do
    saved.pickup[i] = stackPickup[i] or 0
  end
end

-- Trust saved times only if they're from THIS map and fall inside the current
-- match (epoch elapsed <= live match clock). Pickups/stacks can only exist while
-- the match clock runs (objectives unlock after the gates), so a 0/nil duration
-- at restore time always means stale state: discard it. Returns true when the
-- save provably belongs to the CURRENT match (write stamp inside the live clock)
-- — i.e. we were here when it was written, so it represents continuous knowledge.
local function StackRestoreState(mapId)
  local saved = GetStackSV()
  if not (saved and saved.mapId == mapId) then
    return false
  end
  local matchDuration = C_PvP and C_PvP.GetActiveMatchDuration and C_PvP.GetActiveMatchDuration()
  if not matchDuration or matchDuration == 0 then
    return false
  end
  local now = time()
  -- +5s slop: the match clock and our epoch stamps tick independently.
  local function valid(t)
    local elapsed = now - t
    return t > 0 and elapsed >= 0 and elapsed <= matchDuration + 5
  end
  if saved.assault and valid(saved.assault) then
    stackAssaultStart = saved.assault
    -- The interval resolved at assault time is authoritative — re-deriving
    -- Blitz-ness right after a reload can misread (instance info not yet
    -- populated) and halve/double the restored stack count.
    if saved.interval and saved.interval > 0 then
      stackFlagInterval = saved.interval
      stackFlagIntervalSaved = true
    end
  end
  if saved.pickup then
    for i = 1, STACK_NUM_SLOTS do
      local t = saved.pickup[i] or 0
      if valid(t) then
        stackPickup[i] = t
      end
    end
  end
  return valid(saved.written or 0)
end

local function StackValue(idx)
  if not stackCfg then
    return nil
  end
  if stackCfg.mode == "flag" then
    -- Shared clock: both carriers show the same STACK COUNT (not a %); nothing
    -- shows until the first stack actually applies.
    if not stackAssaultStart then
      return nil
    end
    local stacks = math.floor((time() - stackAssaultStart) / stackFlagInterval)
    if stacks < 1 then
      return nil
    end
    return stacks
  end
  local t = stackPickup[idx]
  if not t then
    return nil
  end
  return stackCfg.increment + math.floor((time() - t) / stackCfg.interval) * stackCfg.increment
end

-- Resolve the carrier button currently bound to an arena slot and write (or
-- clear) its objective-icon AuraText. Reuses the OG shownValue dedup + HideText
-- convention so we never fight the icon/respawn code that also owns AuraText.
-- Only a slot with a bound carrier resolves to a button here, so an unbound slot
-- simply has nothing to paint.
local function PaintStackSlot(idx)
  local button = BattleGroundEnemies.ArenaIDToPlayerButton and BattleGroundEnemies.ArenaIDToPlayerButton["arena" .. idx]
  local f = button and button.ObjectiveAndRespawn
  if not (f and f.AuraText) then
    return
  end
  -- AuraText only has a font once ApplyAllSettings has run (enabled modules
  -- only). Painting a number onto a fontstring with no font throws "Font not
  -- set", so skip until it exists -- the next paint after setup fills it in.
  if not f.AuraText:GetFont() then
    return
  end
  -- Don't paint over a death/respawn swirl: the ghost visual owns the icon and
  -- HideText already cleared the number when it took over.
  if f.ActiveRespawnTimer then
    return
  end
  local value = StackValue(idx)
  if not value then
    if f.shownValue ~= false then
      f:HideText()
    end
    return
  end
  local text = (stackCfg.mode == "flag") and tostring(value) or (value .. "%")
  if f.shownValue ~= text then
    f.AuraText:SetText(text)
    f.shownValue = text
  end
end

-- Repaint all slots. The 1s ticker drives this; it also runs on every state
-- mutation so a fresh value lands without waiting for the next tick.
local function RefreshStackTexts()
  for i = 1, STACK_NUM_SLOTS do
    PaintStackSlot(i)
  end
end

-- Flags: the shared clock starts once both flags are held. Re-pickups while it
-- is already running must not restart it, and an untrusted state (joined
-- mid-match, unseen cycle possibly running) must not start it at all.
local function MaybeStartStackAssault()
  if stackStateTrusted and stackAllyHasFlag and stackHordeHasFlag and not stackAssaultStart then
    stackAssaultStart = time()
    StackSaveState()
  end
end

-- Flags: full reset — capture, all flags home, or match end. Every caller
-- corresponds to a confirmed both-flags-home moment, so the cycle state is
-- definitionally idle from here: even a mid-match joiner can trust it now.
local function ResetStackAssault()
  stackAssaultStart = nil
  stackAllyHasFlag, stackHordeHasFlag = false, false
  stackStateTrusted = true
  StackSaveState()
  RefreshStackTexts()
end

local function StackOnFlagChat(event, message)
  if event == "CHAT_MSG_BG_SYSTEM_NEUTRAL" then
    -- "The flags are now placed at their bases." — full reset.
    if message:find("placed at their bases") or message:find("wins") then
      ResetStackAssault()
    end
    return
  end
  -- The ALLIANCE channel announces the alliance flag (horde's carrier), the
  -- HORDE channel the horde flag (alliance's carrier) — bgwc parity.
  local allianceChannel = event == "CHAT_MSG_BG_SYSTEM_ALLIANCE"
  if message:find("picked up by") then
    if allianceChannel then
      stackHordeHasFlag = true
    else
      stackAllyHasFlag = true
    end
    MaybeStartStackAssault()
  elseif message:find("dropped by") then
    -- Clock keeps running — the flag can be re-picked before it returns.
    if allianceChannel then
      stackHordeHasFlag = false
    else
      stackAllyHasFlag = false
    end
  elseif message:find("returned to its base by") then
    if allianceChannel then
      stackHordeHasFlag = false
    else
      stackAllyHasFlag = false
    end
    -- A return only kills the stacks when the other flag is home too. Both home
    -- is also the resync point for a mid-match joiner (ResetStackAssault marks
    -- the state trusted) — run it even when no clock is on.
    if not stackAllyHasFlag and not stackHordeHasFlag then
      ResetStackAssault()
    end
  elseif message:find("captured the") or message:find("wins") then
    ResetStackAssault()
  end
end

local function StackOnOrbChat(event, message)
  if event == "CHAT_MSG_BG_SYSTEM_NEUTRAL" then
    -- "X wins!" — match over, all orbs reset.
    if message:find("wins") then
      for i = 1, STACK_NUM_SLOTS do
        stackPickup[i] = nil
      end
      StackSaveState()
      RefreshStackTexts()
    end
    return
  end
  -- "Name has taken the |cFF01DFD7Blue|r orb!" — authoritative pickup. Color
  -- code matched via the shared ORB_COLOR_CODE_PATTERN (exactly 8 hex digits;
  -- same fragment the identity matcher uses).
  local coded = message:match("the (" .. ORB_COLOR_CODE_PATTERN .. "%a+|r) orb")
  if coded then
    local color = coded:gsub(ORB_COLOR_CODE_PATTERN, ""):gsub("|r", "")
    local idx = STACK_ORB_COLOR_TO_INDEX[color]
    if idx then
      stackPickup[idx] = time()
      StackSaveState()
      PaintStackSlot(idx)
    end
  end
end

-- Called from the module chat handler (same events that drive carrier identity).
-- Independent of the identity binding above — this only advances the clocks.
local function StacksOnChat(event, message)
  if not stackCfg or type(message) ~= "string" then
    return
  end
  if issecretvalue and issecretvalue(message) then
    return
  end
  if stackCfg.mode == "flag" then
    StackOnFlagChat(event, message)
  else
    StackOnOrbChat(event, message)
  end
end

-- Orbs only: arena "cleared" is authoritative removal (a dropped orb resets to
-- base). Flags deliberately ignore arena churn — it can't tell drop-then-return
-- from drop-then-repick (see the retired handler in bgwc predictions/flags.lua).
local function StacksOnArenaCleared(idx)
  if not stackCfg or stackCfg.mode ~= "orb" or idx > STACK_NUM_SLOTS then
    return
  end
  if not UnitExists("arena" .. idx) then
    stackPickup[idx] = nil
    StackSaveState()
    PaintStackSlot(idx)
  end
end

-- Orbs only: an orb carrier coming into render range whose pickup chat we missed
-- gets seeded at the base value (real pickup time unknowable — accepted
-- inaccuracy, same as bgwc / the late-join arena scan in StartStackTracking).
-- Re-"seen" churn must not reset a known clock, so only seed when no pickup time
-- exists yet. Flags ignore arena churn entirely.
local function StacksOnArenaSeen(idx)
  if not stackCfg or stackCfg.mode ~= "orb" or idx > STACK_NUM_SLOTS then
    return
  end
  if UnitExists("arena" .. idx) and not stackPickup[idx] then
    stackPickup[idx] = time()
    StackSaveState()
    PaintStackSlot(idx)
  end
end

-- Blitz (ported from bgwc NS.isBlitz): small match + small group + solo queue.
local function IsStackBlitzMatch()
  local maxPlayers = select(5, GetInstanceInfo()) or 0
  local isSolo = C_PvP and C_PvP.IsSoloRBG and C_PvP.IsSoloRBG() == true
  return maxPlayers < 10 and GetNumGroupMembers() <= 8 and isSolo
end

-- leftIcons = alliance team holds a flag (carrier arena2), rightIcons = horde
-- does (carrier arena1). Token fallback only if the widget isn't populated yet.
local function SeedStackHeldFlags()
  stackAllyHasFlag, stackHordeHasFlag = false, false
  local flagInfo = C_UIWidgetManager
    and C_UIWidgetManager.GetDoubleStateIconRowVisualizationInfo
    and C_UIWidgetManager.GetDoubleStateIconRowVisualizationInfo(STACK_FLAG_WIDGET)
  if flagInfo and flagInfo.leftIcons and flagInfo.rightIcons then
    for _, v in pairs(flagInfo.leftIcons) do
      if v.iconState == Enum.IconState.ShowState1 then
        stackAllyHasFlag = true
      end
    end
    for _, v in pairs(flagInfo.rightIcons) do
      if v.iconState == Enum.IconState.ShowState1 then
        stackHordeHasFlag = true
      end
    end
  else
    stackHordeHasFlag = UnitExists("arena1")
    stackAllyHasFlag = UnitExists("arena2")
  end
end

-- bgwc checkMaxPlayers parity: instance info (and the solo-queue flag) may not be
-- populated right at zone-in — poll until it is, then lock in the Blitz-aware
-- interval. StackValue recomputes from elapsed on every paint, so a late
-- correction retroactively fixes the displayed count. A validated restore
-- (stackFlagIntervalSaved) is authoritative and skips this.
local function ResolveStackFlagInterval(token)
  if stackMapId ~= token or not stackCfg or stackFlagIntervalSaved then
    return
  end
  if (select(5, GetInstanceInfo()) or 0) == 0 then
    C_Timer.After(1, function()
      ResolveStackFlagInterval(token)
    end)
    return
  end
  stackFlagInterval = (IsStackBlitzMatch() and stackCfg.blitzInterval) or stackCfg.interval
  StackSaveState()
end

-- Also runs when entering any non-stack zone while already inactive — that still
-- clears carried-over DB state (e.g. crashed in Kotmogu, restarted elsewhere) so
-- it can't sit around until the next visit.
local function StopStackTracking()
  stackCfg = nil
  stackMapId = nil
  for i = 1, STACK_NUM_SLOTS do
    stackPickup[i] = nil
  end
  stackAssaultStart = nil
  stackAllyHasFlag, stackHordeHasFlag = false, false
  stackFlagIntervalSaved = false
  stackStateTrusted = false
  StackSaveState()
  if stackTicker then
    stackTicker:Cancel()
    stackTicker = nil
  end
  RefreshStackTexts()
end

-- restore: only login/reload zone-ins may consult carried-over state —
-- everything else hard-resets. The wipe below also keeps two stack-tracked maps
-- (or two matches on the same map) from merging clocks.
local function StartStackTracking(mapId, restore)
  stackMapId = mapId
  stackCfg = stackConfig[mapId]
  for i = 1, STACK_NUM_SLOTS do
    stackPickup[i] = nil
  end
  stackAssaultStart = nil
  stackAllyHasFlag, stackHordeHasFlag = false, false
  stackFlagIntervalSaved = false
  stackStateTrusted = false
  stackFlagInterval = stackCfg.interval -- provisional until instance info resolves
  local restoredThisMatch = false
  if restore then
    restoredThisMatch = StackRestoreState(mapId)
  end
  if stackCfg.mode == "flag" then
    -- Recover held state so a later "returned" can evaluate the both-flags-home
    -- stop condition, then decide whether the clock may run at all: continuous
    -- knowledge means a validated same-match save (reload/relog) or both flags
    -- currently home (cycle definitionally idle — fine even for a mid-match
    -- join). Otherwise an unseen cycle may be running and its count is
    -- unknowable — show nothing, never a wrong number, until the next confirmed
    -- both-home resyncs us (ResetStackAssault).
    SeedStackHeldFlags()
    stackStateTrusted = restoredThisMatch or (not stackAllyHasFlag and not stackHordeHasFlag)
    ResolveStackFlagInterval(mapId)
  else
    -- Late join / reload: chat doesn't replay, so seed any carrier the restore
    -- didn't cover from the live arena tokens. The real pickup time is
    -- unknowable here — base value, same accepted inaccuracy as bgwc.
    for i = 1, STACK_NUM_SLOTS do
      if not stackPickup[i] and UnitExists("arena" .. i) then
        stackPickup[i] = time()
      end
    end
  end
  StackSaveState()
  if not stackTicker then
    stackTicker = C_Timer.NewTicker(1, RefreshStackTexts)
  end
  RefreshStackTexts()
end

-- Same late-join race as the carrier sweeps: right after PLAYER_ENTERING_WORLD
-- the map may not resolve yet — retry briefly.
local STACK_MAX_MAP_RETRIES = 10
local STACK_MAP_RETRY_INTERVAL = 0.5

-- restore: true only for login/reload zone-ins (PLAYER_ENTERING_WORLD's
-- isInitialLogin/isReloadingUi payload).
local function StacksCheckZone(restore, retryCount)
  local mapId = C_Map.GetBestMapForUnit("player")
  if not mapId then
    retryCount = retryCount or 0
    if retryCount < STACK_MAX_MAP_RETRIES then
      C_Timer.After(STACK_MAP_RETRY_INTERVAL, function()
        StacksCheckZone(restore, retryCount + 1)
      end)
    end
    return
  end
  if stackConfig[mapId] then
    -- Same map ~= same match: a direct BG-to-BG transfer can land in another
    -- match on the same map with no map change, so only a login/reload may skip
    -- the restart — every fresh zone-in forces a hard reset + rescan.
    if stackMapId ~= mapId or not restore then
      StartStackTracking(mapId, restore)
    end
  else
    StopStackTracking()
  end
end

-- Module-level event frame for objective detection triggers
-- Supplements per-button UPDATE_UI_WIDGET handlers with additional event sources
local objectiveEventFrame = CreateFrame("Frame")
objectiveEventFrame:RegisterEvent("UPDATE_UI_WIDGET")
objectiveEventFrame:RegisterEvent("UNIT_CLASSIFICATION_CHANGED")
objectiveEventFrame:RegisterEvent("ARENA_OPPONENT_UPDATE")
objectiveEventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")
objectiveEventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_ALLIANCE")
objectiveEventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_HORDE")
objectiveEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
objectiveEventFrame:SetScript("OnEvent", function(self, event, ...)
  if event == "PLAYER_ENTERING_WORLD" then
    local isInitialLogin, isReloadingUi = ...

    -- Stack-value simulation: re-evaluate the tracked zone on every world entry.
    -- restore (login/reload) may consult carried-over pickup times; any other
    -- entry hard-resets. StacksCheckZone self-gates on the map, so calling it
    -- unconditionally here (before the IsInPvPInstance gate below) also clears
    -- carried-over state when we log back in outside a stack BG.
    StacksCheckZone(isInitialLogin or isReloadingUi)

    -- Boundary teardown (finding 16): Main.lua's PEW already wiped
    -- ArenaIDToPlayerButton, so NO objective icon has a valid binding now.
    -- Allies are NOT torn down at PEW (roster-driven), so an ally carrier's
    -- icon would otherwise linger across a reload / match boundary. Reset every
    -- ally+enemy ObjectiveAndRespawn frame; the next CheckAll / replay re-shows
    -- any still-valid carrier. Iterate PlayerList (numeric, secret-key-safe).
    for _, side in ipairs({ BattleGroundEnemies.Allies, BattleGroundEnemies.Enemies }) do
      local list = side and side.PlayerList
      if list then
        for _, btn in ipairs(list) do
          if btn.ObjectiveAndRespawn then
            btn.ObjectiveAndRespawn:Reset()
          end
        end
      end
    end

    -- Reload-while-dead recovery: on a same-match /reload (or reconnect) while
    -- the viewer is dead, ARENA_OPPONENT_UPDATE does NOT replay, so a still-
    -- held enemy carrier would show nothing until respawn. Keep the persisted
    -- chat bindings, load them back into the in-memory tables (so `next(chat*)`
    -- gating keeps the PID sweeps from fighting them), and arm a one-shot
    -- replay that fires once the roster rebuilds (RefreshObjectiveCarriers).
    -- Any OTHER PEW (fresh BG entry / match boundary) hard-wipes as before.
    local db = BattleGroundEnemies.db
    local saved = db and db.global and db.global.ObjectiveCarriers
    local liveMapId = C_Map.GetBestMapForUnit("player")
    if
      isReloadingUi
      and BattleGroundEnemies:IsInPvPInstance()
      and saved
      and saved.mapId
      and saved.mapId == liveMapId
      and UnitIsDeadOrGhost("player")
    then
      wipe(chatFlagCarriers)
      wipe(chatOrbCarriers)
      if saved.flag then
        for name, slot in pairs(saved.flag) do
          chatFlagCarriers[name] = slot
        end
      end
      if saved.orb then
        for slot, name in pairs(saved.orb) do
          chatOrbCarriers[slot] = name
        end
      end
      pendingReplay = next(chatFlagCarriers) ~= nil or next(chatOrbCarriers) ~= nil
      replayAttempts = 0
    else
      -- Match boundary: clear chat-tracked carriers so old-match names don't
      -- linger and cause stale Players[name] lookups in the new match.
      wipe(chatFlagCarriers)
      wipe(chatOrbCarriers)
      pendingReplay = false
      replayAttempts = 0
      if db and db.global then
        db.global.ObjectiveCarriers = nil
      end
    end
    return
  end
  -- PvE hard gate: UPDATE_UI_WIDGET fires constantly for raid boss widgets.
  -- Stop all objective processing outside PvP instances.
  if not BattleGroundEnemies:IsInPvPInstance() then
    return
  end
  if event == "UPDATE_UI_WIDGET" then
    local widgetInfo = ...
    if not widgetInfo or not widgetInfo.widgetID then
      return
    end
    local id = widgetInfo.widgetID
    -- 1683: Kotmogu (Orbs), 1640: WSG/Twin Peaks (Flags), 1672: EotS (Flags)
    --
    -- Race window: when an objective changes hands, both UPDATE_UI_WIDGET
    -- AND CHAT_MSG_BG_SYSTEM_* fire in close succession. The order between
    -- them is set by Blizzard's internal scheduling, not us. If WIDGET
    -- arrives first while chat carriers are empty, CheckAllOrbs/Flags
    -- runs immediately and PID-binds — possibly to the wrong same-class
    -- twin. The chat handler then arrives ~milliseconds later and tears
    -- down the wrong binding, but during that gap the user can see the
    -- icon on the wrong button.
    --
    -- Defer the widget-driven sweep by 0.1s so the chat handler — if it's
    -- going to fire at all for this event — has time to populate
    -- chatOrbCarriers / chatFlagCarriers first. If chat fires within the
    -- window, the deferred sweep no-ops (chat carriers populated). If
    -- chat is silent for this BG type / locale, the deferred sweep runs
    -- as the original fallback path. Net cost: 0.1s of "icon not yet
    -- shown" on first pickup, vs. flicker-to-wrong-then-correct.
    if id == 1683 then
      C_Timer.After(0.1, function()
        if not next(chatOrbCarriers) then
          CheckAllOrbs()
        end
      end)
    elseif id == 1640 or id == 1672 then
      C_Timer.After(0.1, function()
        if not next(chatFlagCarriers) then
          CheckAllFlags()
        end
      end)
    end
  elseif event == "UNIT_CLASSIFICATION_CHANGED" then
    -- May fire when a unit picks up or drops an orb/flag. Defer the
    -- fallback sweeps for the same reason as UPDATE_UI_WIDGET above —
    -- gives chat the chance to bind authoritatively first so we don't
    -- flicker through a wrong-button binding.
    --
    -- Map-type gating: only run the sweep that matches the current map.
    -- Pre-2026-05-02, both ran unconditionally — harmless for orb maps but
    -- a real bug for flag maps because CheckAllOrbs read Debuffs[mapId]
    -- which contained Focused/Brutal Assault for flag BGs and stamped
    -- those icons onto carriers. Source migration to Buffs eliminated
    -- the data hazard, but gating still saves wasted iteration on
    -- non-existent arena slots and makes intent explicit.
    local mapId = BattleGroundEnemies:GetActiveStates() and BattleGroundEnemies:GetActiveStates().currentMapId
    C_Timer.After(0.1, function()
      if IsOrbBG(mapId) and not next(chatOrbCarriers) then
        CheckAllOrbs()
      end
      if IsFlagBG(mapId) and not next(chatFlagCarriers) then
        CheckAllFlags()
      end
    end)
  elseif event == "ARENA_OPPONENT_UPDATE" then
    -- Fires when arena units appear/disappear. Two responsibilities:
    --   1. On a slot CLEAR (carrier died / orb back on ground / flag dropped /
    --      cap / return), tear the slot down — binding-agnostically, even while
    --      the viewer is dead. This is the authoritative removal signal and is
    --      the only path for silent removals (e.g. Kotmogu orb drops emit no
    --      chat). Done IMMEDIATELY (no defer); cleared state is unambiguous.
    --   2. Run CheckAllOrbs/Flags as the chat-silent fallback (deferred 0.1s for
    --      the same race-avoidance reason as the other widget paths).
    --
    -- Trigger ONLY on "cleared". "cleared" is authoritative removal.
    -- "unseen"/"destroyed" are lost-visibility — the carrier may still be alive
    -- (viewer died, or carrier left render range), so tearing down on them would
    -- wipe a still-live carrier's binding (R2). The oracle hides only on
    -- "cleared" (core/events.lua); we mirror that here.
    local unitToken, updateReason = ...
    if unitToken and updateReason == "cleared" then
      local arenaIndex = tonumber(string.match(unitToken, "^arena(%d+)$"))
      if arenaIndex then
        -- Stack-value simulation: a cleared orb slot resets that orb's clock
        -- (no-op for flag maps, which ignore arena churn).
        StacksOnArenaCleared(arenaIndex)

        -- Chat-tracked teardown.
        local orbCarrier = chatOrbCarriers[arenaIndex]
        if orbCarrier then
          UnbindChatCarrier(orbCarrier, arenaIndex)
          chatOrbCarriers[arenaIndex] = nil
        end
        for name, slot in pairs(chatFlagCarriers) do
          if slot == arenaIndex then
            UnbindChatCarrier(name, slot)
            chatFlagCarriers[name] = nil
          end
        end
        PersistChatCarriers()

        -- Binding-AGNOSTIC teardown: a PID/fingerprint-bound carrier is in
        -- neither chat table, so clear whatever button currently owns this slot
        -- via the slot map. Death-proof (no dead-guard — this handler is only
        -- IsInPvPInstance-gated) and slot-keyed, so it's correct even for a
        -- same-class twin: the icon's lifetime equals the slot's lifetime. We
        -- Reset the objective frame DIRECTLY (not only via DispatchEvent) so the
        -- visual clear can't be swallowed by BattleGroundEnemies.betweenRounds
        -- (DispatchEvent early-returns in that window).
        local btn = BattleGroundEnemies.ArenaIDToPlayerButton[unitToken]
        if btn then
          BattleGroundEnemies.ArenaIDToPlayerButton[unitToken] = nil
          btn:UpdateEnemyUnitID("Arena", false)
          if btn.ObjectiveAndRespawn then
            btn.ObjectiveAndRespawn:Reset()
          end
          btn:DispatchEvent("ArenaOpponentHidden")
        end
      end
    elseif unitToken and updateReason == "seen" then
      -- Stack-value simulation: an orb carrier entering render range seeds its
      -- clock at base value when we have no pickup time yet (the chat-missed
      -- fallback; no-op for flag maps, which ignore arena churn). Identity is
      -- still resolved by the deferred CheckAllOrbs / chat paths below — this
      -- only advances the simulated clock, never binds a button.
      local arenaIndex = tonumber(string.match(unitToken, "^arena(%d+)$"))
      if arenaIndex then
        StacksOnArenaSeen(arenaIndex)
      end
    end
    -- Map-type gating: same rationale as in UNIT_CLASSIFICATION_CHANGED above.
    local mapId = BattleGroundEnemies:GetActiveStates() and BattleGroundEnemies:GetActiveStates().currentMapId
    C_Timer.After(0.1, function()
      if IsOrbBG(mapId) and not next(chatOrbCarriers) then
        CheckAllOrbs()
      end
      if IsFlagBG(mapId) and not next(chatFlagCarriers) then
        CheckAllFlags()
      end
    end)
  elseif
    event == "CHAT_MSG_BG_SYSTEM_NEUTRAL"
    or event == "CHAT_MSG_BG_SYSTEM_ALLIANCE"
    or event == "CHAT_MSG_BG_SYSTEM_HORDE"
  then
    HandleObjectiveChatMessage(...)
    -- Snapshot the (now-updated) bindings so a /reload-while-dead can replay
    -- them. Chat names are non-secret; this is the only persistence point that
    -- covers every chat-driven bind AND clear.
    PersistChatCarriers()
    -- Stack-value simulation: the same messages drive the simulated clocks
    -- (pickup / drop / capture / return / wins). Runs after the identity bind
    -- above so an immediate repaint lands on the now-bound carrier button.
    StacksOnChat(event, ...)
  end
end)

local objectiveAndRespawn = BattleGroundEnemies:NewButtonModule({
  moduleName = "ObjectiveAndRespawn",
  localizedModuleName = L.ObjectiveAndRespawnTimer,
  defaultSettings = defaultSettings,
  options = options,
  events = {
    "UnitDied",
    "UnitRevived",
    "ArenaOpponentShown",
    "ArenaOpponentHidden",
    "UPDATE_UI_WIDGET",
    "PLAYER_ENTERING_WORLD",
    "OnTestmodeEnabled",
    "OnTestmodeDisabled",
    "OnTestmodeTick",
  },
  enabledInThisExpansion = true,
  attachSettingsToButton = false,
  flags = {
    SetZeroWidthWhenDisabled = true,
  },
})

function objectiveAndRespawn:AttachToPlayerButton(playerButton)
  local frame = CreateFrame("frame", nil, playerButton)
  frame:SetFrameLevel(playerButton:GetFrameLevel() + 5)

  frame.Icon = frame:CreateTexture(nil, "BORDER")
  frame.Icon:SetAllPoints()

  frame:SetScript("OnSizeChanged", function(self, width, height)
    BattleGroundEnemies.CropImage(self.Icon, width, height)
  end)
  frame:Hide()

  -- Explicitly register the event and set the script handler
  frame:RegisterEvent("UPDATE_UI_WIDGET")
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")

  frame:SetScript("OnEvent", function(self, event, ...)
    if not BattleGroundEnemies:IsInPvPInstance() then
      return
    end
    if self[event] then
      self[event](self, ...)
    end
  end)

  frame.AuraText = BattleGroundEnemies.MyCreateFontString(frame)
  -- Anchor the text by its center to the icon's center instead of SetAllPoints.
  -- A single anchor (no opposing edges) lets the fontstring auto-size to its
  -- content and overflow the icon symmetrically rather than being clipped to
  -- the icon's bounds. WordWrap off keeps it a single centered line.
  frame.AuraText:SetPoint("CENTER", frame, "CENTER")
  frame.AuraText:SetJustifyH("CENTER")
  frame.AuraText:SetJustifyV("MIDDLE")
  frame.AuraText:SetWordWrap(false)

  frame.Cooldown = BattleGroundEnemies.MyCreateCooldown(frame)
  frame.Cooldown:Hide()

  frame.Cooldown:SetScript("OnCooldownDone", function()
    -- Respawn timer expired, mark the player as alive
    if playerButton.isDead then
      playerButton:PlayerIsAlive()
      -- No unitID available so push a full-health update directly;
      -- spirit healer always resurrects at 100% health
      playerButton:UpdateHealth(nil, 1, 0, 100, 1)
    end
  end)

  function frame:Reset()
    self:Hide()
    self.Icon:SetTexture()
    if self.AuraText:GetFont() then
      self:HideText()
    end
    self.ActiveRespawnTimer = false
    self.Cooldown:Clear() -- this doesn't seem to trigger OnCooldownDone for some reason, i am sure it used to in the past
    -- Cooldown:Clear() stops the countdown but leaves the last-rendered number
    -- frozen in the native fontstring (Blizzard only refreshes it on the
    -- cooldown's own OnUpdate, which no longer ticks once cleared -- the same
    -- quirk behind the OnCooldownDone note above). In a live match the Hide()
    -- above masks it, but test mode re-Shows this frame for the next objective,
    -- exposing a stale respawn number over the new stack text. Blank it so a
    -- cleared cooldown never carries a leftover number.
    if self.Cooldown.Text then
      self.Cooldown.Text:SetText("")
    end
  end

  function frame:HideText()
    -- AuraText gets its font from ApplyAllSettings, which only runs while the
    -- module is enabled on this button. On a disabled button (or before setup
    -- applies after a mid-combat reload) the fontstring has no font, and
    -- SetText() then throws "Font not set". Guard so HideText is safe from every
    -- caller; shownValue still updates so the dedup stays correct.
    if self.AuraText:GetFont() then
      self.AuraText:SetText("")
    end
    self.shownValue = false
  end

  function frame:ApplyAllSettings()
    if not self.config then
      return
    end
    local conf = self.config
    self.AuraText:ApplyFontStringSettings(conf.Text)
    self.Cooldown:ApplyCooldownSettings(conf.Cooldown, true, { 0, 0, 0, 0.75 })

    -- if not playerButton.isDead then
    --   self:UnitRevived()
    -- end

    -- -- In Kotmogu, don't reset if this player has an orb (avoids hiding orb on nameplate update)
    -- local states = BattleGroundEnemies:GetActiveStates()
    -- if states.currentMapId == 417 then
    --   local arenaID = playerButton.UnitIDs and playerButton.UnitIDs.Arena
    --   if arenaID and UnitExists(arenaID) then
    --     local classification = UnitPvpClassification(arenaID)
    --     if classification and orbSpells[classification] then
    --       -- Player has orb, don't reset - just re-apply the orb display
    --       self.Icon:SetTexture(orbSpells[classification])
    --       self:Show()
    --       return
    --     end
    --   end
    -- end

    -- self:Reset()
  end

  function frame:UnitRevived()
    -- Mirror the UnitDied carrier-protection: in an objective BG, a still-bound
    -- carrier's objective icon must survive a revive — its removal is handled by
    -- the authoritative "cleared", not by Reset. (Objective-BG scoped so it can't
    -- touch the normal revive/Reset in arenas / non-objective BGs.) If the slot
    -- binding is already gone, the carrier really dropped, so Reset runs.
    local states = BattleGroundEnemies:GetActiveStates()
    local arenaToken = playerButton.UnitIDs and playerButton.UnitIDs.Arena
    if
      arenaToken
      and states
      and (IsFlagBG(states.currentMapId) or IsOrbBG(states.currentMapId))
      and BattleGroundEnemies.ArenaIDToPlayerButton[arenaToken] == playerButton
    then
      return
    end
    frame:Reset()
  end

  function frame:UnitDied()
    -- Don't clobber a live objective icon with the death/respawn placeholder
    -- (findings 18/21): the objective icon and the ghost icon share frame.Icon.
    -- If this button still owns an arena slot, it is a bound carrier — its
    -- removal is handled by the authoritative "cleared" (ArenaOpponentHidden),
    -- NOT by a respawn paint over the objective texture. Oracle parity: a
    -- carrier's death is removed by "cleared", never shown as a respawn timer.
    -- FIX B: compare against `playerButton` (the enclosing upvalue), NOT `self`.
    -- Inside `function frame:UnitDied()` self is the ObjectiveAndRespawn child
    -- frame, but ArenaIDToPlayerButton stores the player BUTTON (assigned at
    -- PlayerButton.lua:1274, where its `self` is the button). `== self` would be
    -- always-false dead code; `== playerButton` actually fires when this button
    -- is the bound carrier.
    -- Scope to OBJECTIVE BGs only: in regular arenas / Solo Shuffle EVERY
    -- opponent gets an arena token + ArenaIDToPlayerButton entry, so without
    -- this map gate the guard would fire for every dying enemy and suppress
    -- BGEF's normal death/ghost visual outside objective BGs (regression).
    local states = BattleGroundEnemies:GetActiveStates()
    local arenaToken = playerButton.UnitIDs and playerButton.UnitIDs.Arena
    if
      arenaToken
      and states
      and (IsFlagBG(states.currentMapId) or IsOrbBG(states.currentMapId))
      and BattleGroundEnemies.ArenaIDToPlayerButton[arenaToken] == playerButton
    then
      return
    end

    -- Force show death visual for all battlegrounds
    self:Show()
    self:SetFrameLevel(playerButton:GetFrameLevel() + 10) -- Ensure on top
    self.Icon:SetTexture(GetSpellTexture(8326)) -- Ghost/death icon
    self:HideText()
    self.ActiveRespawnTimer = true

    -- Set respawn timer based on BG type (from original BGE)
    local respawnTime = 26 -- Default RBG respawn time
    if IsCataClassic then
      respawnTime = 45 -- Cata Classic has longer respawn
    else
      if states.isSoloRBG then
        if states.currentMapId ~= 2345 then -- Not Deephaul Ravine (map ID 2345; 2656 is the *instance* ID — currentMapId is the map ID, so the old `~= 2656` check was always true and Deephaul Ravine wrongly got the 16s Blitz respawn)
          respawnTime = 16 -- Blitz has faster respawn
        end
      end
    end
    self.Cooldown:SetCooldown(GetTime(), respawnTime)
  end

  function frame:ArenaOpponentShown()
    self:HideText()

    -- Set the icon based on THIS button's bound arena slot rather than
    -- iterating all slots via CheckAllOrbs/CheckAllFlags. The previous
    -- implementation re-derived bindings via PID matching every time
    -- ArenaOpponentShown fired, which is exactly the wrong-button bug
    -- on same-class twins. The slot-to-spell mapping is the same as the
    -- iteration paths use; we just look up only our own slot.
    --
    -- Whoever bound this button — chat handler (BindChatCarrierToArenaSlot),
    -- ARENA_OPPONENT_UPDATE handler (Main.lua), or the CheckAll* fallback —
    -- has already set playerButton.UnitIDs.Arena before dispatching this
    -- event, so it's authoritative here.
    local arenaToken = playerButton.UnitIDs and playerButton.UnitIDs.Arena
    if not arenaToken then
      return
    end
    local arenaIndex = tonumber(string.match(arenaToken, "arena(%d+)"))
    if not arenaIndex then
      return
    end

    local states = BattleGroundEnemies:GetActiveStates()
    -- Single source: BattlegroundspezificBuffs (post-2026-05-02 migration).
    -- Both orb maps and flag maps now key 0-based — orbs by arena slot
    -- (arena1=Blue=[0], arena2=Purple=[1], …), flags by faction-of-carrier
    -- ([0]=Horde-carrier-buff, [1]=Alliance-carrier-buff). The (i-1) offset
    -- works for both since the loop counter is 1-based and the data is
    -- 0-based. See CheckAllOrbs/CheckAllFlags for the matching iteration paths.
    local battlegroundBuffs = BattleGroundEnemies:GetBattlegroundAuras()

    local spellId
    if IsOrbBG(states.currentMapId) and battlegroundBuffs then
      -- Kotmogu: arenaN → buffs[N-1]
      spellId = battlegroundBuffs[arenaIndex - 1]
    elseif IsFlagBG(states.currentMapId) and battlegroundBuffs then
      -- WSG / Twin Peaks / Deephaul Ravine / EotS:
      --   arena1 = Horde-team carrier (carrying Alliance flag) → buffs[0]
      --   arena2 = Alliance-team carrier (carrying Horde flag)  → buffs[1]
      spellId = battlegroundBuffs[arenaIndex - 1]
    end

    -- Don't repaint the objective texture over an active death/respawn cooldown
    -- (finding 14): if a re-dispatch lands during the death window, leave the
    -- ghost/respawn visual alone. The next sweep restores the objective once the
    -- respawn timer completes (OnCooldownDone -> UnitRevived -> Reset).
    if spellId and not self.ActiveRespawnTimer then
      self.Icon:SetTexture(GetSpellTexture(spellId))
      self:Show()
    end

    -- HideText() above cleared the simulated stack number; restore it in the same
    -- frame instead of waiting up to ~1s for the next RefreshStackTexts tick (the
    -- flag drop+repick rebind path otherwise leaves this button's count blank).
    -- PaintStackSlot self-guards ActiveRespawnTimer and a nil StackValue, so this
    -- is safe in every branch (non-stack BGs simply have nothing to paint).
    PaintStackSlot(arenaIndex)
  end

  function frame:ArenaOpponentHidden()
    -- -- In Kotmogu, don't reset orbs when arena opponent "hides" (goes out of range)
    -- -- The orb classification persists even when out of nameplate range
    -- -- Kotmogu: check if this player still has an orb via their arena token
    -- local arenaID = playerButton.UnitIDs and playerButton.UnitIDs.Arena
    -- if arenaID and UnitExists(arenaID) then
    --   local classification = UnitPvpClassification(arenaID)
    --   if classification and orbSpells[classification] then
    --     -- Still has orb, don't hide
    --     return
    --   end
    -- end

    self:Reset()

    -- Respawn-timer recovery: when a BOUND carrier died, frame:UnitDied's
    -- objective-BG guard suppressed the death visual (so a respawn swirl never
    -- flashed over the live objective icon) — which also skipped starting the
    -- respawn Cooldown, the only revive path for an out-of-range enemy. Now
    -- that the carrier is unbound (both "cleared" teardown paths nil the slot
    -- mapping BEFORE dispatching this event), re-run UnitDied: the guard no
    -- longer fires, so the normal death/ghost visual + respawn timer + auto-
    -- revive run. Gated on isDead so it only fires for a carrier who actually
    -- died (a live drop/handoff isDead==false → no-op), and it can't double-
    -- run: in the "cleared"-before-death ordering isDead is still false here.
    if playerButton.isDead then
      self:UnitDied()
    end
  end

  function frame:PLAYER_ENTERING_WORLD()
    -- Just check everything on load (map checks handle if it runs or not)
    local states = BattleGroundEnemies:GetActiveStates()
    -- UI map IDs (from C_Map.GetBestMapForUnit), see Data.BattlegroundspezificBuffs:
    --   1339 = Warsong Gulch, 206 = Twin Peaks, 112 = Eye of the Storm,
    --   397 = Eye of the Storm RBG, 2345 = Deephaul Ravine
    if
      states.currentMapId == 206
      or states.currentMapId == 1339
      or states.currentMapId == 112
      or states.currentMapId == 397
      or states.currentMapId == 2345
    then
      CheckAllFlags()

      -- Start ticker for frequent updates (widget events unreliable).
      -- Gate on `not next(chatFlagCarriers)` like every other CheckAll call site
      -- (627/650/692/970/974): when chat is authoritative the ungated ticker
      -- would re-run the PID matcher during the post-drop token-lag window and
      -- re-Show the icon (possibly on the wrong same-class twin) before the
      -- authoritative "cleared" hides it — the hide->show->hide flicker (finding
      -- 8). Chat-tracked maps clear via the chat handler; this ticker only
      -- covers the chat-silent fallback.
      if not self.FlagTicker then
        self.FlagTicker = C_Timer.NewTicker(1, function()
          if not next(chatFlagCarriers) then
            CheckAllFlags()
          end
        end)
      end
    elseif states.currentMapId == 417 then
      -- Temple of Kotmogu (417)
      CheckAllOrbs()

      -- Start ticker for frequent updates if not already running. Gated like
      -- FlagTicker above (and every other CheckAll call site) so the PID sweep
      -- can't override a chat-authoritative binding during a drop window.
      if not self.OrbTicker then
        self.OrbTicker = C_Timer.NewTicker(1, function()
          if not next(chatOrbCarriers) then
            CheckAllOrbs()
          end
        end)
      end
    else
      -- Cancel tickers if we leave objective BGs
      if self.OrbTicker then
        self.OrbTicker:Cancel()
        self.OrbTicker = nil
      end
      if self.FlagTicker then
        self.FlagTicker:Cancel()
        self.FlagTicker = nil
      end
    end
  end

  function frame:UPDATE_UI_WIDGET(widgetInfo)
    if not widgetInfo or not widgetInfo.widgetID then
      return
    end

    local widgetID = widgetInfo.widgetID

    -- This handler is dispatched per-button, so it fires N times for
    -- one widget update. The module-level objectiveEventFrame:OnEvent
    -- already handles these widgets ONCE with proper deferral and
    -- chat-tracker gating. Skip here when chat is authoritative — an
    -- ungated CheckAllOrbs/Flags would PID-match and override any
    -- chat-set binding on a same-class twin. When chat is silent,
    -- defer to the global handler's fallback path; this per-button
    -- redundant call is no longer needed.
    --
    -- 1640: WSG/Twin Peaks (Flags)
    -- 1672: Eye of the Storm (Flags)
    -- 1683: Kotmogu (Orbs)
    if widgetID == 1640 or widgetID == 1672 then
      if not next(chatFlagCarriers) then
        CheckAllFlags()
      end
    elseif widgetID == 1683 then
      if not next(chatOrbCarriers) then
        CheckAllOrbs()
      end
    end
  end

  -- Test mode: simulate flag/orb carrying and death/respawn. Each objective icon
  -- also previews its stack-text format (flags = bare Focused Assault count,
  -- orbs = damage-taken %) so the OG Text settings can be tuned outside a live
  -- BG. The ghost icon shows no number. Real-match painting is slot-keyed
  -- (PaintStackSlot only touches arena-bound buttons), so it never collides with
  -- these test buttons.
  local testObjectiveSpells = { 156618, 156621, 8326, 121164 } -- Horde flag, Alliance flag, Ghost, Kotmogu orb (Blue)
  local testObjectiveStackText = {
    [156618] = "15", -- Horde flag → bare stack count
    [156621] = "15", -- Alliance flag → bare stack count
    [121164] = "60%", -- Kotmogu orb → damage-taken increase %
  }

  function frame:OnTestmodeEnabled()
    self.testmodeEnabled = true
  end

  function frame:OnTestmodeDisabled()
    self.testmodeEnabled = false
    self:Reset()
  end

  function frame:OnTestmodeTick()
    if not self.testmodeEnabled then
      self.testmodeEnabled = true
    end
    -- Start every tick from a fully-reset slate so exactly ONE visual is ever
    -- active in this row: a prior tick's objective stack number can't linger
    -- over a respawn swirl, nor a respawn countdown over a fresh objective's
    -- stacks (the user-reported overlaps). Reset() hides the frame, clears the
    -- icon, blanks the stack text AND the cooldown number; each branch below
    -- then builds up only its own icon + text.
    self:Reset()
    -- Randomly show an objective or respawn, or leave hidden.
    local roll = math.random(1, 5)
    if roll <= 2 then
      -- Show a flag/objective icon, previewing its stack-text format.
      local spellId = testObjectiveSpells[math.random(1, #testObjectiveSpells)]
      self.Icon:SetTexture(GetSpellTexture(spellId))
      self:Show()
      local sample = testObjectiveStackText[spellId]
      if sample then
        -- OG shownValue convention, same as PaintStackSlot.
        self.AuraText:SetText(sample)
        self.shownValue = sample
      end
    elseif roll == 3 then
      -- Simulate death with respawn timer (Reset() already cleared the stack
      -- text, mirroring the real frame:UnitDied HideText() before the ghost).
      self.Icon:SetTexture(GetSpellTexture(8326))
      self:Show()
      self.ActiveRespawnTimer = true
      self.Cooldown:SetCooldown(GetTime(), 16)
    end
    -- roll >= 4: stay reset (no objective shown this tick).
  end

  playerButton.ObjectiveAndRespawn = frame
  return playerButton.ObjectiveAndRespawn
end
