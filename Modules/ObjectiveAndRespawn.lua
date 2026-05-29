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
    FontSize = 12,
  },
  Text = {
    FontSize = 17,
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
      args = Data.AddNormalTextSettings(location.Text),
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
      args = Data.AddCooldownSettings(location.Cooldown),
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
  return mapId == 206         -- Twin Peaks
      or mapId == 1339        -- Warsong Gulch
      or mapId == 112         -- Eye of the Storm
      or mapId == 397         -- Eye of the Storm RBG
      or mapId == 2345        -- Deephaul Ravine
end

local function IsOrbBG(mapId)
  return mapId == 417         -- Temple of Kotmogu
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

-- Public refresh: re-scans orb and flag carriers right now.
-- Called by BGEF's UBS handler so mid-match joiners / reloads pick up state
-- that was established before their per-button PLAYER_ENTERING_WORLD fired.
function BattleGroundEnemies:RefreshObjectiveCarriers()
  CheckAllOrbs()
  CheckAllFlags()
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

local orbColorToArenaIndex = {
  Blue = 1,
  Purple = 2,
  Green = 3,
  Orange = 4,
}

local flagNameToArenaIndex = {
  -- Slot convention (verified by user testing original code):
  --   arena1 = Horde-team carrier  (a Horde player carrying the Alliance flag)
  --   arena2 = Alliance-team carrier (an Alliance player carrying the Horde flag)
  -- Chat message names the FLAG, so:
  --   "Alliance Flag" picked up → carried by a Horde player → arena1
  --   "Horde Flag"    picked up → carried by an Alliance player → arena2
  ["Alliance Flag"] = 1,
  ["Horde Flag"] = 2,
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
  return BattleGroundEnemies.Enemies.Players[key]
      or BattleGroundEnemies.Allies.Players[key]
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
    local flagName = msg:match("The (.-) was picked up")
    local arenaIndex = flagName and flagNameToArenaIndex[flagName]
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
  local orbColor = msg:match("the |c%x+(%a+)|r orb")
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
  if msg:find("captured the")
      or msg:find("returned to its base by")
      or msg:find("placed at their bases") then
    ClearAllChatFlagCarriers()
    return
  end
  -- "The flag has been reset" — confirmed in Deephaul Ravine (fires when a
  -- dropped crystal returns to spawn without pickup). Gated to mapId 2345
  -- because we haven't verified Warsong Gulch / Twin Peaks don't emit the
  -- same string in some flow; if they do, a global match would wrongly clear
  -- a real carrier. Widen later if we confirm safety on other maps.
  if msg:find("The flag has been reset") then
    local mapId = BattleGroundEnemies:GetActiveStates()
        and BattleGroundEnemies:GetActiveStates().currentMapId
    if mapId == 2345 then
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
    -- Match boundary: clear chat-tracked carriers so old-match names don't
    -- linger and cause stale Players[name] lookups in the new match. (The
    -- tracked names belong to the previous match's roster which is wiped
    -- by the addon's own PEW handler in Main.lua.)
    wipe(chatFlagCarriers)
    wipe(chatOrbCarriers)
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
    --
    -- 1. When a slot CLEARS (carrier died, orb back on ground, flag
    --    dropped), no chat message fires for some BG types (notably
    --    Kotmogu — orb drops are silent). Without explicit cleanup our
    --    chat-tracked carrier would linger and the icon would stay on
    --    a dead/uninvolved player. Clear chat-tracked carriers tied to
    --    the cleared arena slot — IMMEDIATELY (no defer); the cleared
    --    state is unambiguous and we want stale tracking gone fast.
    --
    -- 2. Run CheckAllOrbs/Flags as fallback for slots where chat is
    --    silent. Defer this for the same race-avoidance reason as the
    --    other widget paths.
    local unitToken, updateReason = ...
    if unitToken and (updateReason == "cleared" or updateReason == "destroyed"
        or updateReason == "unseen") then
      local arenaIndex = tonumber(string.match(unitToken, "^arena(%d+)$"))
      if arenaIndex then
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
  elseif event == "CHAT_MSG_BG_SYSTEM_NEUTRAL"
      or event == "CHAT_MSG_BG_SYSTEM_ALLIANCE"
      or event == "CHAT_MSG_BG_SYSTEM_HORDE" then
    HandleObjectiveChatMessage(...)
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
  frame.AuraText:SetAllPoints()
  frame.AuraText:SetJustifyH("CENTER")

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
  end

  function frame:HideText()
    self.AuraText:SetText("")
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
    frame:Reset()
  end

  function frame:UnitDied()
    local states = BattleGroundEnemies:GetActiveStates()

    -- Force show death visual for all battlegrounds
    self:Show()
    self:SetFrameLevel(playerButton:GetFrameLevel() + 10) -- Ensure on top
    self.Icon:SetTexture(GetSpellTexture(8326))           -- Ghost/death icon
    self:HideText()
    self.ActiveRespawnTimer = true

    -- Set respawn timer based on BG type (from original BGE)
    local respawnTime = 26 -- Default RBG respawn time
    if IsCataClassic then
      respawnTime = 45     -- Cata Classic has longer respawn
    else
      if states.isSoloRBG then
        if states.currentMapId ~= 2345 then -- Not Deephaul Ravine (map ID 2345; 2656 is the *instance* ID — currentMapId is the map ID, so the old `~= 2656` check was always true and Deephaul Ravine wrongly got the 16s Blitz respawn)
          respawnTime = 16                  -- Blitz has faster respawn
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

    if spellId then
      self.Icon:SetTexture(GetSpellTexture(spellId))
      self:Show()
    end
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

      -- Start ticker for frequent updates (widget events unreliable)
      if not self.FlagTicker then
        self.FlagTicker = C_Timer.NewTicker(1, function()
          CheckAllFlags()
        end)
      end
    elseif states.currentMapId == 417 then
      -- Temple of Kotmogu (417)
      CheckAllOrbs()

      -- Start ticker for frequent updates if not already running
      if not self.OrbTicker then
        self.OrbTicker = C_Timer.NewTicker(1, function()
          CheckAllOrbs()
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

  -- Test mode: simulate flag/orb carrying and death/respawn
  local testObjectiveSpells = { 156618, 156621, 8326 } -- Horde flag, Alliance flag, Ghost

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
    -- Randomly show an objective or respawn, or hide
    local roll = math.random(1, 5)
    if roll <= 2 then
      -- Show a flag/objective icon
      local spellId = testObjectiveSpells[math.random(1, #testObjectiveSpells)]
      self.Icon:SetTexture(GetSpellTexture(spellId))
      self:Show()
      self.ActiveRespawnTimer = false
      self.Cooldown:Clear()
    elseif roll == 3 then
      -- Simulate death with respawn timer
      self.Icon:SetTexture(GetSpellTexture(8326))
      self:Show()
      self.ActiveRespawnTimer = true
      self.Cooldown:SetCooldown(GetTime(), 16)
    else
      -- Hide (no objective)
      self:Reset()
    end
  end

  playerButton.ObjectiveAndRespawn = frame
  return playerButton.ObjectiveAndRespawn
end
