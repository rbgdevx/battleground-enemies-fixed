---@class Data
local Data = select(2, ...)
if not Data.L then
  Data.L = setmetatable({}, {
    __index = function(_, k)
      return k
    end,
  })
  print("|cffff0000BattleGroundEnemiesFixed|r: Locales.lua failed to load. Reinstall the addon.")
end
local L = Data.L
local LSM = LibStub("LibSharedMedia-3.0")

local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
-- local LibChangelog = LibStub("LibChangelog") -- Removed

--upvalues
local _G = _G
local math_random = math.random
local math_min = math.min
local pairs = pairs
-- local print = print
local time = time
local type = type
local unpack = unpack

local C_PvP = C_PvP
local C_Spell = C_Spell
local CreateFrame = CreateFrame
local CTimerNewTicker = C_Timer.NewTicker
local GetBattlefieldTeamInfo = GetBattlefieldTeamInfo
-- local GetBestMapForUnit = C_Map.GetBestMapForUnit
local GetNumBattlefieldScores = GetNumBattlefieldScores
local GetNumGroupMembers = GetNumGroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local GetSpellName = C_Spell and C_Spell.GetSpellName or GetSpellName
local GetTime = GetTime
local GetUnitName = GetUnitName
local InCombatLockdown = InCombatLockdown
local IsInInstance = IsInInstance
local IsInRaid = IsInRaid
local RequestBattlefieldScoreData = RequestBattlefieldScoreData
local SetBattlefieldScoreFaction = SetBattlefieldScoreFaction
local UnitExists = UnitExists
local UnitFactionGroup = UnitFactionGroup
local UnitGUID = UnitGUID
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsGhost = UnitIsGhost
local UnitName = UnitName
local UnitRace = UnitRace
local UnitRealmRelationship = UnitRealmRelationship

local IsRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
local IsClassic = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
local IsWrath = WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC

local HasSpeccs = not not GetSpecialization -- Mists of Pandaria

local MaxLevel = GetMaxPlayerLevel()

-- local LGIST -- Removed LibGroupInSpecT

-- binding definitions
--BINDING_HEADER_BATTLEGROUNDENEMIES = "BattleGroundEnemies"
_G["BINDING_NAME_CLICK BGEAllies:Button4"] = L.TargetPreviousAlly
_G["BINDING_NAME_CLICK BGEAllies:Button5"] = L.TargetNextAlly
_G["BINDING_NAME_CLICK BGEEnemies:Button4"] = L.TargetPreviousEnemy
_G["BINDING_NAME_CLICK BGEEnemies:Button5"] = L.TargetNextEnemy

-- Secret-safe GetUnitName replacement, used on ALL clients (not just Classic).
-- In instanced PvP, UnitName returns SECRET name/realm strings for enemies, and
-- Blizzard's stock GetUnitName does an unguarded `server ~= ""` (plus
-- name.."-"..server) on them — which EMITS taint and is blocked. Wrapping the
-- call in pcall does NOT prevent that taint (it only hides the error), so we
-- must never reach a comparison/concat on a secret. We override it everywhere
-- with an issecretvalue-guarded version: when name/realm is secret we return the
-- bare (possibly secret) name, which callers only pass to SetText or to
-- issecretvalue-guarded table lookups.
GetUnitName = function(unit, showServerName)
  local name, server = UnitName(unit)
  if not name then
    return nil
  end
  if issecretvalue and (issecretvalue(name) or issecretvalue(server)) then
    return name
  end
  if server and server ~= "" then
    if showServerName then
      return name .. "-" .. server
    else
      local relationship = UnitRealmRelationship(unit)
      if relationship == LE_REALM_RELATION_VIRTUAL then
        return name
      else
        return name .. FOREIGN_SERVER_LABEL
      end
    end
  else
    return name
  end
end

LSM:Register("statusbar", "UI-StatusBar", "Interface\\TargetingFrame\\UI-StatusBar")

---@class BattleGroundEnemies: frame
BattleGroundEnemies = CreateFrame("Frame", "BattleGroundEnemies", UIParent)
BattleGroundEnemies.Counter = {}
BattleGroundEnemies.PlayerGUIDs = {}
BattleGroundEnemies.DuplicateLog = {}

-- Player-name canonicalization helper.
-- Players[] dict was historically keyed by whatever the API returned:
--   PVPScoreInfo.name / GetRaidRosterInfo / UnitName(unit, true) all return
--   "Name" for same-realm players and "Name-Realm" for cross-realm.
-- Chat messages (BG system events) ALWAYS emit the full "Name-Realm" form.
-- That format mismatch caused the chat-bind handler to miss same-realm
-- carriers (e.g. "Känägäwä-Tichondrius" failing to find Players["Känägäwä"]
-- — diagnosed in-game 2026-05-01).
--
-- Fix: canonicalize ALL Players[] keys + name comparisons to the full
-- "Name-Realm" form by appending the player's own normalized realm to
-- short-name inputs. GetNormalizedRealmName is non-secret, takes no unit
-- token, and returns the same normalized form ("Tichondrius", no spaces)
-- used by chat messages and the scoreboard.
--
-- Safe behavior:
--   - nil / non-string / secret-tagged → returned as-is (caller deals)
--   - already contains "-" → returned as-is (already canonical)
--   - realm not yet available (between LOADING_SCREEN_ENABLED and
--     LOADING_SCREEN_DISABLED) → returned as-is. Wiki note on
--     GetNormalizedRealmName: it may be nil during the loading window.
--     We don't fabricate a partial canonicalization in that window —
--     would create a third inconsistent key format.
function BattleGroundEnemies:CanonicalName(name)
  if not name or type(name) ~= "string" then
    return name
  end
  if issecretvalue and issecretvalue(name) then
    return name
  end
  if name:find("-", 1, true) then
    return name
  end
  local realm = GetNormalizedRealmName and GetNormalizedRealmName()
  if not realm or realm == "" then
    return name
  end
  return name .. "-" .. realm
end

-- Track scoreboard faction filter so we can re-assert after the user (or
-- Blizzard's own PVPMatch UI) clicks a faction tab. factionEnum -1 = both
-- teams, 0 = Horde, 1 = Alliance. BGEF needs -1 to see both teams' rows.
-- Server-side sort is no longer tracked: enemies are sorted by class+name
-- on our end via PlayerSortingByClassName, so the row order from
-- SortBattlefieldScoreData is irrelevant to the addon.
BattleGroundEnemies._scoreboardFaction = nil
hooksecurefunc("SetBattlefieldScoreFaction", function(factionEnum)
  BattleGroundEnemies._scoreboardFaction = factionEnum
end)

--move unitID update for allies

-- for Clique Support
ClickCastFrames = ClickCastFrames or {}

--[[
Ally frames use Scoreboard, FakePlayers, GroupMembers,
Enemy frames use Scoreboard, FakePlayers, ArenaPlayers
]]

BattleGroundEnemies.consts = {}
BattleGroundEnemies.consts.PlayerSources = {
  Scoreboard = "Scoreboard",
  GroupMembers = "GroupMembers",
  ArenaPlayers = "ArenaPlayers",
  FakePlayers = "FakePlayers",
}
BattleGroundEnemies.consts.PlayerTypes = {
  Allies = "Allies",
  Enemies = "Enemies",
}

-- Battleground max player corrections (GetInstanceInfo returns wrong values for some BGs)
-- Maps instance ID to correct max players per team
local bgMaxPlayerCorrections = {
  -- Classic/Legacy IDs (may still be used in some contexts)
  [443] = 10, -- Warsong Gulch (Classic)
  [461] = 15, -- Arathi Basin (Classic)
  [401] = 40, -- Alterac Valley (Classic)
  [607] = 15, -- Strand of the Ancients

  -- Epic Battlegrounds (40v40)
  [30] = 40, -- Alterac Valley
  [628] = 40, -- Isle of Conquest
  [2118] = 40, -- Battle for Wintergrasp
  [2197] = 40, -- Korrak's Revenge (Brawl)
  [1280] = 40, -- Tarren Mill vs Southshore (Brawl)
  [1191] = 40, -- Ashran

  -- 15v15 Battlegrounds
  [566] = 15, -- Eye of the Storm
  [968] = 15, -- Eye of the Storm (alternate)
  [2107] = 15, -- Arathi Basin
  [2245] = 15, -- Deepwind Gorge
  [1105] = 15, -- Deepwind Gorge (alternate ID)

  -- 10v10 Battlegrounds
  [726] = 10, -- Twin Peaks
  [761] = 10, -- Battle for Gilneas
  [998] = 10, -- Temple of Kotmogu
  [727] = 10, -- Silvershard Mines
  [1803] = 10, -- Seething Shore
  [2656] = 10, -- Deephaul Ravine
  [2106] = 10, -- Warsong Gulch
}

-- Corrected GetInstanceInfo max-players. GetInstanceInfo mis-reports maxPlayers
-- for several BGs -- notably epics return the TOTAL (80) instead of the per-team
-- bracket size (40), which would trip SelectPlayerCountProfile's ">40 -> no
-- profile" guard and hide all frames. Map known instance IDs to the per-team
-- count, and pin Solo Blitz (Solo RBG) to 8v8 regardless of map. Returns 0 when
-- nothing is known yet (instanceID nil during the load transition). The caller
-- (SelectPlayerCountProfile) treats 0 as "no profile" (no enemies until it
-- settles) and any >40 total-misreport from an UNLISTED map as an epic ->
-- defaults to the 16-40 bracket (clamps to 40) rather than guessing a small
-- bracket from a partial roster. Listing a NEW epic here is still preferred (so
-- the bracket is exact and custom brackets resolve precisely), but an unlisted
-- one degrades gracefully to 16-40 instead of blanking. A method on
-- BattleGroundEnemies (not a file-local) so Mainframe.lua's
-- SelectPlayerCountProfile can reach the Main.lua-local corrections table.
function BattleGroundEnemies:GetCorrectedMaxPlayers()
  if C_PvP and C_PvP.IsSoloRBG and C_PvP.IsSoloRBG() then
    return 8
  end
  local _, _, _, _, maxPlayers, _, _, instanceID = GetInstanceInfo()
  if instanceID and bgMaxPlayerCorrections[instanceID] then
    return bgMaxPlayerCorrections[instanceID]
  end
  return maxPlayers or 0
end

local previousCvarRaidOptionIsShown

--variables used in multiple functions, if a variable is only used by one function its declared above that function
BattleGroundEnemies.currentTarget = false
BattleGroundEnemies.currentFocus = false

BattleGroundEnemies.Testmode = {
  PlayerCountTestmode = 10,
  FakePlayerAuras = {}, --key = playerbutton, value = {}
  FakePlayerDRs = {}, --key = playerButtonTable, value = {categoryname = {state = 0, expirationTime}
  RandomTrinkets = false, -- key = number, value = spellId-- key = number, value = spellId
}

BattleGroundEnemies.ButtonModules = {} --contains moduleFrames, key is the module name
BattleGroundEnemies.UserFaction = UnitFactionGroup("player")
BattleGroundEnemies.UserButton = false --the button of the Player himself
BattleGroundEnemies.specCache = {} -- key = GUID, value = specName (localized)

-- ButtonEventLog: ring buffer of recent button-lifecycle events. Used by the
-- watchdog to dump a timeline when PlayerList exceeds NumPlayers, so we can
-- diagnose the duplicate-button bug without users running anything manually.
-- Captured automatically; only printed when the watchdog fires.

-- BattleGroundEnemies._buttonEventLog = {}
-- local BUTTON_EVENT_LOG_MAX = 200

-- local function safeStr(v)
--   if v == nil then return "<nil>" end
--   if issecretvalue and issecretvalue(v) then return "<secret>" end
--   if type(v) == "string" then return v end
--   return tostring(v)
-- end

-- function BattleGroundEnemies:LogButtonEvent(event, mfType, btn, extra)
--   local pd = btn and btn.PlayerDetails
--   local entry = {
--     t = GetTime(),
--     event = event,
--     mfType = mfType,
--     name = pd and safeStr(pd.PlayerName) or "<no-pd>",
--     class = pd and safeStr(pd.PlayerClass) or "<no-pd>",
--     race = pd and safeStr(pd.PlayerRace) or "<no-pd>",
--     status = btn and btn.status,
--     extra = extra,
--   }
--   local log = self._buttonEventLog
--   log[#log + 1] = entry
--   if #log > BUTTON_EVENT_LOG_MAX then
--     table.remove(log, 1)
--   end
-- end

-- function BattleGroundEnemies:DumpButtonEventLog(reason)
--   local log = self._buttonEventLog
--   print("BGE Event Log Dump (" .. (reason or "manual") .. ") — last", #log, "events:")
--   local now = GetTime()
--   for i = math.max(1, #log - 60), #log do
--     local e = log[i]
--     if e then
--       print(
--         string.format(
--           "  [-%05.2fs] %-15s %-8s name=%s class=%s race=%s status=%s%s",
--           now - e.t,
--           e.event,
--           e.mfType or "?",
--           e.name,
--           e.class,
--           e.race,
--           tostring(e.status),
--           e.extra and (" " .. tostring(e.extra)) or ""
--         )
--       )
--     end
--   end
-- end

local playerSpells

---@class bgeState
---@field WOW_PROJECT_ID number
---@field isInArena boolean
---@field isInBattleground boolean
---@field currentMapId number|boolean
---@field isRatedBG boolean
---@field isSoloRBG boolean

BattleGroundEnemies.states = {
  testmodeActive = false,
  userIsAlive = not UnitIsDeadOrGhost("player"),
  ---@type bgeState
  real = {
    WOW_PROJECT_ID = WOW_PROJECT_ID,
    isInArena = false,
    isInBattleground = false,
    currentMapId = false,
    isRatedBG = false,
    isSoloRBG = false,
  },
  ---@type bgeState
  test = {
    WOW_PROJECT_ID = WOW_PROJECT_ID,
    isInArena = false,
    isInBattleground = false,
    currentMapId = false,
    isRatedBG = false,
    isSoloRBG = false,
  },
}

---@return bgeState
function BattleGroundEnemies:GetActiveStates()
  if self:IsTestmodeActive() then
    return self.states.test
  else
    return self.states.real
  end
end

function BattleGroundEnemies:GetBattlegroundAuras()
  local states = self:GetActiveStates()
  if not states then
    return
  end
  -- Returns only the Buffs table for the current map. Pre-2026-05-02 this
  -- also returned Data.BattlegroundspezificDebuffs[mapId] as a second value;
  -- that table is now commented out (orbs migrated into Buffs as the single
  -- source of truth) and no caller used the second return anymore. Outer
  -- nil-check guards against the table itself being absent.
  return Data.BattlegroundspezificBuffs and Data.BattlegroundspezificBuffs[states.currentMapId]
end

function BattleGroundEnemies:IsTestmodeActive()
  return self.states.testmodeActive
end

function BattleGroundEnemies:FlipButtonModuleSettingsHorizontally(moduleName, dbLocation)
  local newSettings = {}

  local moduleFrame = self.ButtonModules[moduleName]
  if not moduleFrame or moduleFrame.attachSettingsToButton then
    newSettings = CopyTable(dbLocation, false)
  else
    for k, v in pairs(dbLocation) do
      if type(v) == "table" then
        if k == "Points" then
          local newPointsData = CopyTable(v, false)
          for i = 1, #v do
            local pointsData = v[i]
            if pointsData.Point then
              newPointsData[i].Point = Data.Helpers.getOppositeHorizontalPoint(pointsData.Point) or pointsData.Point
            end
            if pointsData.RelativePoint then
              newPointsData[i].RelativePoint = Data.Helpers.getOppositeHorizontalPoint(pointsData.RelativePoint)
                or pointsData.RelativePoint
            end
            if pointsData.OffsetX then
              newPointsData[i].OffsetX = -pointsData.OffsetX
            end
          end
          newSettings[k] = newPointsData
        elseif k == "Container" then
          local newContainerSettings = CopyTable(v, false)
          local newHorizontalGrowDirection

          local horizontalGrowdirection = v.HorizontalGrowDirection
          if horizontalGrowdirection then
            newHorizontalGrowDirection = Data.Helpers.getOppositeDirection(horizontalGrowdirection)
              or horizontalGrowdirection
          end
          newContainerSettings.HorizontalGrowDirection = newHorizontalGrowDirection
          newSettings[k] = newContainerSettings
        else
          newSettings[k] = self:FlipButtonModuleSettingsHorizontally(moduleName, v)
        end
      else
        newSettings[k] = v
      end
    end
  end

  return newSettings
end

function BattleGroundEnemies:FlipSettingsHorizontallyRecursive(dblocation)
  local dbLocationFlippedHorizontally = {}
  for k, v in pairs(dblocation) do
    if type(v) == "table" then
      if k == "ButtonModules" then
        dbLocationFlippedHorizontally[k] = {}
        for moduleName, moduleSettings in pairs(v) do
          dbLocationFlippedHorizontally[k][moduleName] =
            self:FlipButtonModuleSettingsHorizontally(moduleName, moduleSettings)
        end
      else
        dbLocationFlippedHorizontally[k] = self:FlipSettingsHorizontallyRecursive(v)
      end
    else
      dbLocationFlippedHorizontally[k] = v
    end
  end
  return dbLocationFlippedHorizontally
end

function BattleGroundEnemies:GetPlayerCountsFromConfig(playerCountConfig)
  if type(playerCountConfig) ~= "table" then
    error("playerCountConfig must be a table")
  end
  local minPlayers = playerCountConfig.minPlayerCount
  local maxPlayers = playerCountConfig.maxPlayerCount
  return minPlayers, maxPlayers
end

function BattleGroundEnemies:GetPlayerCountConfigNameLocalized(playerCountConfig, isCustom)
  local minPlayers, maxPlayers = self:GetPlayerCountsFromConfig(playerCountConfig)
  return (isCustom and "*" or "") .. minPlayers .. "–" .. maxPlayers .. " " .. L.players
end

function BattleGroundEnemies:GetPlayerCountConfigName(playerCountConfig)
  local minPlayers, maxPlayers = self:GetPlayerCountsFromConfig(playerCountConfig)
  return minPlayers .. "–" .. maxPlayers .. " " .. "players"
end

-- returns true if <frame> or one of the frames that <frame> is dependent on is anchored to <otherFrame> and nil otherwise
-- dont ancher to otherframe is
function BattleGroundEnemies:IsFrameDependentOnFrame(frame, otherFrame)
  if frame == nil then
    return false
  end

  if otherFrame == nil then
    return false
  end

  if frame == otherFrame then
    return true
  end

  local points = frame:GetNumPoints()
  for i = 1, points do
    local _, relFrame = frame:GetPoint(i)
    if relFrame and self:IsFrameDependentOnFrame(relFrame, otherFrame) then
      return true
    end
  end
end

--BattleGroundEnemies.EnemyFaction
--BattleGroundEnemies.AllyFaction

--each module can heave one of the different types
--dynamicContainer == the container is only as big as the children its made of, the container sets only 1 point
--buttonHeightLengthVariable = a attachment that has the height of the button and a variable width (the module will set the width itself). when unused sets to 0.01 width
--buttonHeightSquare = a attachment that has the height of the button and the same width, when unused sets to 0.01 width
--HeightAndWidthVariable

function BattleGroundEnemies:IsModuleEnabledOnThisExpansion(moduleName)
  local moduleFrame = self.ButtonModules[moduleName]
  if moduleFrame then
    return moduleFrame.enabledInThisExpansion
  end
  return false
end

local function copySettingsWithoutOverwrite(src, dest)
  if not src or type(src) ~= "table" then
    return
  end
  if type(dest) ~= "table" then
    dest = {}
  end

  for k, v in pairs(src) do
    if type(v) == "table" then
      dest[k] = copySettingsWithoutOverwrite(v, dest[k])
    elseif type(v) ~= type(dest[k]) then -- only overwrite if the type in dest is different
      dest[k] = v
    end
  end

  return dest
end

local function copyModuleDefaultsIntoDefaults(location, moduleName, moduleDefaults)
  location.ButtonModules = location.ButtonModules or {}
  location.ButtonModules[moduleName] = location.ButtonModules[moduleName] or {}
  copySettingsWithoutOverwrite(moduleDefaults, location.ButtonModules[moduleName])
end

function BattleGroundEnemies:NewButtonModule(moduleSetupTable)
  if type(moduleSetupTable) ~= "table" then
    return error("Tried to register a Module but the parameter wasn't a table")
  end
  if not moduleSetupTable.moduleName then
    return error("NewButtonModule error: No moduleName specified")
  end
  local moduleName = moduleSetupTable.moduleName
  if not moduleSetupTable.localizedModuleName then
    return error("NewButtonModule error for module: " .. moduleName .. " No localizedModuleName specified")
  end
  if moduleSetupTable.enabledInThisExpansion == nil then
    return error("NewButtonModule error for module: " .. moduleName .. " enabledInThisExpansion is nil")
  end

  if self.ButtonModules[moduleName] then
    return error("module " .. moduleName .. " is already registered")
  end
  local moduleFrame = CreateFrame("Frame", nil, UIParent)

  moduleSetupTable.flags = moduleSetupTable.flags or {}
  Mixin(moduleFrame, moduleSetupTable)

  for k in pairs(self.consts.PlayerTypes) do
    for j = 1, #Data.defaultSettings.profile[k].playerCountConfigs do
      local playerCountConfig = Data.defaultSettings.profile[k].playerCountConfigs[j]
      copyModuleDefaultsIntoDefaults(playerCountConfig, moduleName, moduleSetupTable.defaultSettings)
    end

    local customPlayerCountConfigGeneric = Data.defaultSettings.profile[k].customPlayerCountConfigs["**"]
    copyModuleDefaultsIntoDefaults(customPlayerCountConfigGeneric, moduleName, moduleSetupTable.defaultSettings)
  end

  if moduleSetupTable.generalDefaults then
    copyModuleDefaultsIntoDefaults(Data.defaultSettings.profile, moduleName, moduleSetupTable.generalDefaults)
  end

  self.ButtonModules[moduleName] = moduleFrame
  return moduleFrame
end

function BattleGroundEnemies:GetBigDebuffsSpellPriority(spellId)
  if not BattleGroundEnemies.db.profile.UseBigDebuffsPriority then
    return
  end
  if not BigDebuffs then
    return
  end
  local priority = BigDebuffs.GetDebuffPriority and BigDebuffs:GetDebuffPriority(spellId)
  if not priority then
    return
  end
  if priority == 0 then
    return
  end
  return priority
end

function BattleGroundEnemies:GetSpellPriority(spellId)
  local priority = nil
  pcall(function()
    priority = self:GetBigDebuffsSpellPriority(spellId) or Data.SpellPriorities[spellId]
  end)
  return priority
end

-- Old synchronous PLAYER_TARGET_CHANGED handler removed — it called
-- UserButton:UpdateTarget() which ran the matcher with unitID="target"
-- IMMEDIATELY (same frame as the click), racing the proper deferred
-- handler defined further down. When the matcher returned the wrong
-- same-class twin (which it can on first encounter or with poisoned
-- stored attrs), the wrong button briefly received the target token
-- and showed the actual unit's health — visible as a 1-2 frame flash
-- on the wrong frame before the deferred handler corrected it via the
-- click stash. The deferred handler at PLAYER_TARGET_CHANGED below
-- does the same work but smarter (stash > arena-token > matcher), so
-- the sync handler was pure liability with no upside.

-- Hard gate: this addon is strictly PvP-only. A crash report involving raid bosses
-- (Chimaerus) traced to module-level event handlers that kept processing outside
-- PvP instances. IsInPvPInstance is the single source of truth consulted by every
-- OnEvent dispatcher below; PLAYER_LOGIN and PLAYER_ENTERING_WORLD are the only
-- events that must flow through regardless (they are what *detect* the zone).
function BattleGroundEnemies:IsInPvPInstance()
  local _, zone = IsInInstance()
  return zone == "pvp" or zone == "arena"
end

BattleGroundEnemies:SetScript("OnEvent", function(self, event, ...)
  if event ~= "PLAYER_LOGIN" and event ~= "PLAYER_ENTERING_WORLD" then
    if not self:IsInPvPInstance() then
      return
    end
  end
  if self[event] then
    self[event](self, ...)
  end
end)

function BattleGroundEnemies:ShowTooltip(owner, func)
  if self.db.profile.ShowTooltips then
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT", 0, 0)
    func()
    GameTooltip:Show()
  end
end

function BattleGroundEnemies:GetColoredName(playerButton)
  if not playerButton.PlayerDetails then
    return
  end
  local name = playerButton.PlayerDetails.PlayerName
  local tbl = playerButton.PlayerDetails.PlayerClassColor
  return ("|cFF%02x%02x%02x%s|r"):format(tbl.r * 255, tbl.g * 255, tbl.b * 255, name)
end

-- BattleGroundEnemies.Fake_ARENA_OPPONENT_UPDATE()
-- 	BattleGroundEnemies:ARENA_OPPONENT_UPDATE()
-- end

---@type FunctionContainer
BattleGroundEnemies.FakePlayersUpdateTicker = nil

local function stopFakePlayersTicker()
  if BattleGroundEnemies.FakePlayersUpdateTicker then
    BattleGroundEnemies.FakePlayersUpdateTicker:Cancel()
    BattleGroundEnemies.FakePlayersUpdateTicker = nil
  end
end

local function createFakePlayersTicker(seconds, callback)
  local ticker = CTimerNewTicker(seconds, callback)
  stopFakePlayersTicker()
  BattleGroundEnemies.FakePlayersUpdateTicker = ticker
  return ticker
end

function BattleGroundEnemies:SetupTestmode()
  if not self.Testmode.RandomTrinkets then
    self.Testmode.RandomTrinkets = {}
    for triggerSpellID, trinketData in pairs(Data.TrinketData) do
      if type(triggerSpellID) == "string" then --support for classic, IsClassic
        table.insert(self.Testmode.RandomTrinkets, triggerSpellID)
      else
        local spellExists = GetSpellName(triggerSpellID)

        if spellExists and spellExists ~= "" then
          table.insert(self.Testmode.RandomTrinkets, triggerSpellID)
        end
      end
    end
  end

  wipe(self.Testmode.FakePlayerAuras)
  wipe(self.Testmode.FakePlayerDRs)

  -- Iterate Buffs, not Debuffs — Buffs is the single source of truth post
  -- the 2026-05-02 migration (orbs moved in alongside flags). If the user
  -- comments out the legacy Debuffs table, iterating it would error.
  local mapIDs = {}
  if Data.BattlegroundspezificBuffs then
    for mapID, data in pairs(Data.BattlegroundspezificBuffs) do
      table.insert(mapIDs, mapID)
    end
  end
  local mandomm = math_random(1, #mapIDs)
  local randomMapID = mapIDs[mandomm]

  BattleGroundEnemies.states.test.currentMapId = randomMapID
  BattleGroundEnemies.states.test.isInBattleground = true
  BattleGroundEnemies.states.test.isRatedBG = true

  self:CreateFakePlayers()
  self:CheckEnableState()
end

do
  local counter

  function BattleGroundEnemies:FillFakePlayerData(amount, mainFrame, role)
    for i = 1, amount do
      local name, classToken, specName

      if HasSpeccs then
        local randomSpec
        randomSpec = Data.RolesToSpec[role][math_random(1, #Data.RolesToSpec[role])]
        classToken = randomSpec.classToken
        specName = randomSpec.specName
      else
        classToken = Data.ClassList[math_random(1, #Data.ClassList)]
      end
      local nameprefix = mainFrame.PlayerType == self.consts.PlayerTypes.Enemies and "Enemy" or "Ally"
      name = L[nameprefix] .. counter .. "-Realm" .. counter

      mainFrame:AddPlayerToSource(self.consts.PlayerSources.FakePlayers, {
        name = name,
        raceName = nil,
        classToken = classToken,
        specName = specName,
        additionalData = {
          isFakePlayer = true,
          PlayerLevel = i == 1 and MaxLevel or math_random(MaxLevel - 10, MaxLevel - 1),
        },
      })
      counter = counter + 1
    end
  end

  function BattleGroundEnemies:CreateFakePlayers()
    local count = self.Testmode.PlayerCountTestmode or 10

    for number, mainFrame in pairs({ self.Allies, self.Enemies }) do
      local remaining = count
      if mainFrame == self.Allies then
        remaining = remaining - 1
      end
      mainFrame:BeforePlayerSourceUpdate(self.consts.PlayerSources.FakePlayers)

      local healerAmount = math_random(2, 3)
      healerAmount = math_min(healerAmount, remaining)
      remaining = remaining - healerAmount
      local tankAmount = math_random(1)
      tankAmount = math_min(tankAmount, remaining)
      remaining = remaining - tankAmount
      local damagerAmount = remaining

      counter = 1
      BattleGroundEnemies:FillFakePlayerData(healerAmount, mainFrame, "HEALER")
      BattleGroundEnemies:FillFakePlayerData(tankAmount, mainFrame, "TANK")
      BattleGroundEnemies:FillFakePlayerData(damagerAmount, mainFrame, "DAMAGER")

      mainFrame:AfterPlayerSourceUpdate()

      for name, playerButton in pairs(mainFrame.Players) do
        -- if IsRetail then
        -- 	playerButton.Covenant:UpdateCovenant(math_random(1, #Data.CovenantIcons))
        -- end
      end
    end
  end
end

local function fakePlayersTestmodeTicker()
  for number, mainFrame in pairs({ BattleGroundEnemies.Allies, BattleGroundEnemies.Enemies }) do
    mainFrame:OnTestmodeTick()
  end
end

local function setupFakePlayersTestmodeTicker()
  createFakePlayersTicker(1, fakePlayersTestmodeTicker)
end

function BattleGroundEnemies.ToggleTestmodeOnUpdate()
  local enabled = not BattleGroundEnemies.FakePlayersUpdateTicker
  if enabled then
    setupFakePlayersTestmodeTicker()
    BattleGroundEnemies:Information(L.FakeEventsEnabled)
  else
    stopFakePlayersTicker()
    BattleGroundEnemies:Information(L.FakeEventsDisabled)
  end
end

function BattleGroundEnemies:EnableTestMode()
  if InCombatLockdown() then
    return BattleGroundEnemies:Information(L.ErrorTestmodeInCombat)
  end
  self.states.testmodeActive = true
  self:SetupTestmode()

  self.Allies:OnTestmodeEnabled()
  self.Enemies:OnTestmodeEnabled()
  self:Information(L.TestmodeEnabled)
end

function BattleGroundEnemies:DisableTestMode()
  self.states.testmodeActive = false
  self:Information(L.TestmodeDisabled)
  self.Allies:OnTestmodeDisabled()
  self.Enemies:OnTestmodeDisabled()
  self:CheckEnableState()
end

function BattleGroundEnemies.ToggleTestmode()
  if BattleGroundEnemies.states.testmodeActive then --disable testmode
    BattleGroundEnemies:DisableTestMode()
  else --enable Testmode
    BattleGroundEnemies:EnableTestMode()
  end
end

local RequestFrame = CreateFrame("Frame", nil, BattleGroundEnemies)
RequestFrame:Hide()
do
  local TimeSinceLastOnUpdate = 0
  local UpdatePeroid = 2 --update every second
  local function RequestTicker(self, elapsed) --OnUpdate runs if the frame RequestFrame is shown
    TimeSinceLastOnUpdate = TimeSinceLastOnUpdate + elapsed
    if TimeSinceLastOnUpdate > UpdatePeroid then
      RequestBattlefieldScoreData()
      TimeSinceLastOnUpdate = 0
    end
  end
  RequestFrame:SetScript("OnUpdate", RequestTicker)
end

-- function BattleGroundEnemies:GetDebugFrame()
--   if not self.DebugFrame then
--     local f = CreateFrame("ScrollingMessageFrame", "BGE_DebugFrame", UIParent, "BackdropTemplate")
--     f:SetSize(600, 300)
--     f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
--     f:SetMaxLines(2500)
--     f:SetFontObject(ChatFontNormal)
--     f:SetJustifyH("LEFT")
--     f:SetFading(false)
--     f:EnableMouseWheel(true)
--     f:SetScript("OnMouseWheel", function(self, delta)
--       if delta > 0 then
--         self:ScrollUp()
--       else
--         self:ScrollDown()
--       end
--     end)
--     f:SetMovable(true)
--     f:EnableMouse(true)
--     f:RegisterForDrag("LeftButton")
--     f:SetScript("OnDragStart", f.StartMoving)
--     f:SetScript("OnDragStop", f.StopMovingOrSizing)
--     f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
--     f:SetBackdropColor(0, 0, 0, 0.8)
--     f:Show()
--     self.DebugFrame = f
--   end
--   return self.DebugFrame
-- end

---@type PlayerButton[]
BattleGroundEnemies.ArenaIDToPlayerButton = {} --key = arenaID: arenaX, value = playerButton of that unitID

BattleGroundEnemies:RegisterEvent("PLAYER_LOGIN") --Fired on reload UI and on initial loading screen

BattleGroundEnemies.GeneralEvents = {
  "LOSS_OF_CONTROL_ADDED",
  "LOSS_OF_CONTROL_UPDATE",
  "UNIT_HEALTH_FREQUENT",
  "UPDATE_MOUSEOVER_UNIT",
  "PLAYER_TARGET_CHANGED",
  "PLAYER_FOCUS_CHANGED",
  "ARENA_OPPONENT_UPDATE", --fires when a arena enemy appears and a frame is ready to be shown
  "ARENA_CROWD_CONTROL_SPELL_UPDATE", --fires when data requested by C_PvP.RequestCrowdControlSpell(unitID) is available
  "ARENA_COOLDOWNS_UPDATE", --fires when a arenaX enemy used a trinket or racial to break cc, C_PvP.GetArenaCrowdControlInfo(unitID) shoudl be called afterwards to get used CCs
  "UNIT_TARGET",
  "UNIT_HEALTH",
  "UNIT_MAXHEALTH",
  "UNIT_POWER_FREQUENT",
  "UNIT_POWER_UPDATE",
  "UNIT_MAXPOWER",
  -- PLAYER_REGEN_ENABLED and PLAYER_REGEN_DISABLED are registered permanently
  -- in PLAYER_LOGIN so they survive UnregisterEvents(). This ensures the combat
  -- lockdown queue drains even after Disable() unregisters other events.
  "PLAYER_SOFT_ENEMY_CHANGED",
  "PVP_MATCH_STATE_CHANGED",
  "UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED",
  "RAID_TARGET_UPDATE",
  "UNIT_AURA", -- real-time CC detection for allies and enemies
}

BattleGroundEnemies.RetailEvents = {
  "UNIT_HEAL_PREDICTION",
  "UNIT_ABSORB_AMOUNT_CHANGED",
  "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
}

BattleGroundEnemies.ClassicEvents = {
  "UNIT_HEALTH_FREQUENT",
}

BattleGroundEnemies.WrathEvents = {
  "UNIT_HEALTH_FREQUENT",
}

function BattleGroundEnemies:RegisterEvents()
  local allEvents = Data.Helpers.JoinArrays(self.GeneralEvents, self.ClassicEvents, self.WrathEvents, self.RetailEvents)
  if C_EventUtils and C_EventUtils.IsEventValid then
    for i = 1, #allEvents do
      local event = allEvents[i]
      if C_EventUtils.IsEventValid(event) then
        pcall(function()
          self:RegisterEvent(event)
        end)
      end
    end
  else
    for i = 1, #self.GeneralEvents do
      pcall(function()
        self:RegisterEvent(self.GeneralEvents[i])
      end)
    end
    if IsClassic then
      for i = 1, #self.ClassicEvents do
        pcall(function()
          self:RegisterEvent(self.ClassicEvents[i])
        end)
      end
    end
    if IsWrath then
      for i = 1, #self.WrathEvents do
        pcall(function()
          self:RegisterEvent(self.WrathEvents[i])
        end)
      end
    end
    if IsRetail then
      for i = 1, #self.RetailEvents do
        pcall(function()
          self:RegisterEvent(self.RetailEvents[i])
        end)
      end
    end
  end
end

function BattleGroundEnemies:UnregisterEvents()
  local allEvents = Data.Helpers.JoinArrays(self.GeneralEvents, self.ClassicEvents, self.WrathEvents, self.RetailEvents)
  for i = 1, #allEvents do
    if self:IsEventRegistered(allEvents[i]) then
      self:UnregisterEvent(allEvents[i])
    end
  end
end

-- if lets say raid1 leaves all remaining players get shifted up, so raid2 is the new raid1, raid 3 gets raid2 etc.

local function EnableShadowColor(fontString, enableShadow, shadowColor)
  if shadowColor then
    fontString:SetShadowColor(unpack(shadowColor))
  end
  if enableShadow then
    fontString:SetShadowOffset(1, -1)
  else
    fontString:SetShadowOffset(0, 0)
  end
end

function BattleGroundEnemies.CropImage(texture, width, height, hasTexcoords)
  local left, right, top, bottom = 0.075, 0.925, 0.075, 0.925
  local ratio = height / width
  if ratio > 1 then --crop the sides
    ratio = 1 / ratio
    texture:SetTexCoord(left + ((1 - ratio) / 2), right - ((1 - ratio) / 2), top, bottom)
  elseif ratio == 1 then
    texture:SetTexCoord(left, right, top, bottom)
  else
    -- crop the height
    texture:SetTexCoord(left, right, top + ((1 - ratio) / 2), bottom - ((1 - ratio) / 2))
  end
end

local function ApplyFontStringSettings(fs, settings, isCooldown)
  local globals = Mixin({}, BattleGroundEnemies.db.profile.Text)
  if isCooldown then
    globals = Mixin({}, globals, BattleGroundEnemies.db.profile.Cooldown)
  end

  local configTable = Mixin({}, globals, settings)

  fs:SetFont(LSM:Fetch("font", configTable.Font), configTable.FontSize, configTable.FontOutline)

  --idk why, but without this the SetJustifyH and SetJustifyV dont seem to work sometimes even tho GetJustifyH returns the new, correct value
  fs:GetRect()
  fs:GetStringHeight()
  fs:GetStringWidth()

  if configTable.JustifyH then
    fs:SetJustifyH(configTable.JustifyH)
  end

  if configTable.JustifyV then
    fs:SetJustifyV(configTable.JustifyV)
  end

  if configTable.WordWrap ~= nil then
    fs:SetWordWrap(configTable.WordWrap)
  end

  if configTable.FontColor then
    fs:SetTextColor(unpack(configTable.FontColor))
  end

  fs:EnableShadowColor(configTable.EnableShadow, configTable.ShadowColor)
end

local function ApplyCooldownSettings(self, config, cdReverse, swipeColor)
  -- Manual merge instead of Mixin() to avoid Lua taint
  local configTable = {}
  for k, v in pairs(BattleGroundEnemies.db.profile.Cooldown) do
    configTable[k] = v
  end
  for k, v in pairs(config) do
    configTable[k] = v
  end
  self:SetReverse(cdReverse)
  self:SetDrawSwipe(configTable.DrawSwipe)
  self:SetDrawEdge(configTable.DrawSwipe)
  if swipeColor then
    self:SetSwipeColor(unpack(swipeColor))
  end
  self:SetHideCountdownNumbers(not configTable.ShowNumber)
  if self.Text then
    self.Text:ApplyFontStringSettings(config, true)
  end
end

---comment
---@param parent Frame
function BattleGroundEnemies.MyCreateFontString(parent)
  ---@class MyFontString: fontstring
  ---@field DisplayedName string
  local fontString = parent:CreateFontString(nil, "OVERLAY")
  fontString.ApplyFontStringSettings = ApplyFontStringSettings
  fontString.EnableShadowColor = EnableShadowColor
  fontString:SetDrawLayer("OVERLAY", 2)
  return fontString
end

---comment
---@param frame cooldown
---@return fontstring?
function BattleGroundEnemies.GrabFontString(frame)
  for _, region in pairs({ frame:GetRegions() }) do
    if region:GetObjectType() == "FontString" then
      return region
    end
  end
end

function BattleGroundEnemies.AttachCooldownSettings(cooldown)
  cooldown.ApplyCooldownSettings = ApplyCooldownSettings
  -- Find fontstring of the cooldown
  local fontstring = BattleGroundEnemies.GrabFontString(cooldown)
  if fontstring then
    ---@class MyFontString
    cooldown.Text = fontstring
    cooldown.Text.ApplyFontStringSettings = ApplyFontStringSettings
    cooldown.Text.EnableShadowColor = EnableShadowColor
  end
end

function BattleGroundEnemies.MyCreateCooldown(parent)
  local cooldown = CreateFrame("Cooldown", nil, parent)
  cooldown:SetAllPoints()
  cooldown:SetSwipeTexture("Interface/Buttons/WHITE8X8")

  BattleGroundEnemies.AttachCooldownSettings(cooldown)

  return cooldown
end

-- Shared button update ticker: single timer updates all active buttons
-- instead of each button having its own OnUpdate handler.
local buttonUpdateTicker = nil
local BUTTON_UPDATE_PERIOD = 0.2

local function UpdateAllPlayerButtons()
  if not BattleGroundEnemies.enabled or not BattleGroundEnemies.states.userIsAlive then
    return
  end
  local containers = { BattleGroundEnemies.Enemies, BattleGroundEnemies.Allies }
  for c = 1, #containers do
    local container = containers[c]
    if container and container.enabled and container.Players then
      for _, playerButton in pairs(container.Players) do
        if not playerButton.PlayerDetails.isFakePlayer then
          if playerButton.PlayerIsEnemy then
            playerButton:UpdateAll()
          else
            if playerButton ~= BattleGroundEnemies.UserButton then
              playerButton:UpdateRangeViaLibRangeCheck(playerButton.unitID)
            else
              playerButton:UpdateRange(true)
            end
          end
        end
      end
    end
  end
end

local function StartButtonUpdateTicker()
  if buttonUpdateTicker then
    buttonUpdateTicker:Cancel()
  end
  buttonUpdateTicker = CTimerNewTicker(BUTTON_UPDATE_PERIOD, UpdateAllPlayerButtons)
end

local function StopButtonUpdateTicker()
  if buttonUpdateTicker then
    buttonUpdateTicker:Cancel()
    buttonUpdateTicker = nil
  end
end

function BattleGroundEnemies:Disable()
  self.enabled = false
  self:UnregisterEvents()
  RequestFrame:Hide()
  stopFakePlayersTicker()
  StopButtonUpdateTicker()
  -- Cancel persistent tickers explicitly so they don't keep firing no-op
  -- wakeups while the user is outside PvP. Re-armed by the corresponding
  -- Start* calls in Enable() below.
  self:StopTargetScanTicker()
  self:StopCombatIndicatorTicker()
  -- Cancel the ally-roster loading retry ticker if it's mid-run. It is
  -- otherwise only cancelled inside GROUP_ROSTER_UPDATE, which the IsInInstance
  -- gate now early-returns out of once we're in the world -- so a ticker still
  -- armed at leave-time would orphan-wake ~1/s until its 30-tick self-limit.
  -- Cancelling here also guarantees a fresh retry budget on the next match.
  if self.allyRosterRetryTimer then
    self.allyRosterRetryTimer:Cancel()
    self.allyRosterRetryTimer = nil
  end
  self.Allies:Disable()
  self.Enemies:Disable()

  -- #5: empty BOTH rosters whenever the addon disables, so no buttons (incl.
  -- the ally self-button) linger in the world/city. Disable() always runs when
  -- you leave an instance (PLAYER_ENTERING_WORLD -> CheckEnableState), so this
  -- is the reliable teardown point — unlike the PEW leavingPvP gate, which can
  -- be skipped on some leave paths. HarvestPlayerHistory has already run before
  -- any Disable on match Complete (harvest at the top of the Complete branch,
  -- Disable at the bottom), so this never races the harvest. The
  -- GROUP_ROSTER_UPDATE IsInInstance gate prevents any rebuild once we're out of
  -- the instance; Enable() rebuilds the roster on the next entry.
  self.Allies:RemoveAllPlayersFromAllSources()
  self.Enemies:RemoveAllPlayersFromAllSources()
end

function BattleGroundEnemies:Enable()
  self.enabled = true

  -- Reset the per-match harvest gate on every enable. Normally this is
  -- cleared by the PVP_MATCH_STATE_CHANGED -> Inactive transition, but
  -- since Disable() now fires on match Complete (perf: stop the post-match
  -- UBS allocation storm), we may not be registered when the *next* match's
  -- Inactive event fires. Clearing here guarantees each fresh BG entry
  -- starts with a clean gate regardless. The harvest itself is idempotent
  -- (entries get re-written as honorLevel/spec/role evolve), so an extra
  -- clear is always safe.
  self._harvestedThisMatch = nil

  self:RegisterEvents()
  StartButtonUpdateTicker()
  -- Re-arm persistent tickers cancelled by Disable(). Explicit start here
  -- guarantees they resume without depending on PEW (TargetScanTicker) or
  -- the ApplyButtonSettings chain (CombatIndicator) firing first.
  self:StartTargetScanTicker()
  self:StartCombatIndicatorTicker()
  if BattleGroundEnemies:IsTestmodeActive() then
    setupFakePlayersTestmodeTicker()
    RequestFrame:Hide()
  else
    RequestFrame:Show()
    stopFakePlayersTicker()
  end
  self.Allies:CheckEnableState()
  self.Enemies:CheckEnableState()

  -- Build the ally roster now that we're enabled. GROUP_ROSTER_UPDATE
  -- early-returns while disabled (the roster doesn't exist outside an
  -- instance), so any group-change events that fired before this Enable were
  -- ignored. Rebuild explicitly here so allies populate on instance entry
  -- regardless of whether GROUP_ROSTER_UPDATE happened to fire before or after
  -- Enable(). Idempotent (mark-and-sweep reuses pooled buttons); harmless in
  -- test mode (AfterPlayerSourceUpdate uses the FakePlayers source there).
  self:GROUP_ROSTER_UPDATE()
end

function BattleGroundEnemies:CheckEnableState()
  local states = BattleGroundEnemies:GetActiveStates()
  if states.isInArena and BattleGroundEnemies.db.profile.ShowBGEInArena then
    return self:Enable()
  end
  if states.isInBattleground and BattleGroundEnemies.db.profile.ShowBGEInBattleground then
    return self:Enable()
  end
  self:Disable()
end

function BattleGroundEnemies:ApplyAllSettings()
  BattleGroundEnemies:CheckEnableState()
  if BattleGroundEnemies.Allies then
    BattleGroundEnemies.Allies:SelectPlayerCountProfile(true)
  end
  if BattleGroundEnemies.Enemies then
    BattleGroundEnemies.Enemies:SelectPlayerCountProfile(true)
  end
  BattleGroundEnemies:ToggleArenaFrames()
  BattleGroundEnemies:ToggleRaidFrames()
end

local function PVPMatchScoreboard_OnHide()
  if PVPMatchScoreboard.selectedTab ~= 1 then
    -- user was looking at another tab than all players
    SetBattlefieldScoreFaction() -- request a UPDATE_BATTLEFIELD_SCORE
  end
end

--Triggered immediately before PLAYER_ENTERING_WORLD on login and UI Reload, but NOT when entering/leaving instances.
function BattleGroundEnemies:PLAYER_LOGIN()
  self.UserDetails = {
    -- Canonicalize so this matches Players[] keys (which are canonical
    -- since the CanonicalName refactor). UnitName("player") returns the
    -- short form; CanonicalName appends our own realm.
    PlayerName = self:CanonicalName(UnitName("player")),
    PlayerClass = select(2, UnitClass("player")),
    isGroupLeader = UnitIsGroupLeader("player"),
    isGroupAssistant = UnitIsGroupAssistant("player"),
    unit = "player",
    GUID = UnitGUID("player"),
  }

  self.db = LibStub("AceDB-3.0"):New("BattleGroundEnemiesDB", Data.defaultSettings, true)

  self.db.RegisterCallback(self, "OnProfileChanged", "ProfileChanged")
  self.db.RegisterCallback(self, "OnProfileCopied", "ProfileChanged")
  self.db.RegisterCallback(self, "OnProfileReset", "ProfileReset")

  -- Prune stale PlayerHistory entries (>6mo unseen). Bounds the SavedVariables
  -- file from growing forever. 6 months covers ~1 PvP season (TWW seasons run
  -- ~5-6 months each), so players you face at any point in a season stay
  -- pre-warmed for the rest of it. Pruned entries get re-harvested if
  -- encountered again — losing them only costs the next first-encounter
  -- pre-warm.
  if self.db.global and self.db.global.PlayerHistory then
    local cutoff = time() - (180 * 86400)
    for k, v in pairs(self.db.global.PlayerHistory) do
      if type(v) ~= "table" or not v.lastSeenAt or v.lastSeenAt < cutoff then
        self.db.global.PlayerHistory[k] = nil
      end
    end
  end

  if self.db.profile then
    if self.db.profile.DebugToSV_ResetOnPlayerLogin then
      self.db.profile.log = nil
    end
  end

  BattleGroundEnemies:UpgradeProfiles(self.db)

  BattleGroundEnemies:UpgradeProfiles(self.db)

  if self.ApplyAllSettings then
    self:ApplyAllSettings()
  end

  -- self:RegisterEvent("GROUP_ROSTER_UPDATE") ... (Keeping event registration flow intact)

  self:RegisterEvent("GROUP_ROSTER_UPDATE") --Fired whenever a group or raid is formed or disbanded, players are leaving or joining the group or raid.
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  self:RegisterEvent("PARTY_LEADER_CHANGED") --Fired when the player's leadership changed.
  self:RegisterEvent("PLAYER_ALIVE") --Fired when the player releases from death to a graveyard; or accepts a resurrect before releasing their spirit. Does not fire when the player is alive after being a ghost. PLAYER_UNGHOST is triggered in that case.
  self:RegisterEvent("PLAYER_UNGHOST") --Fired when the player is alive after being a ghost.
  self:RegisterEvent("PLAYER_DEAD") --Fired when the player has died.
  self:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
  -- self:RegisterEvent("PVP_MATCH_STATE_CHANGED")

  self:SetupOptions()

  AceConfigDialog:SetDefaultSize("BattleGroundEnemiesFixed", 800, 700)

  AceConfigDialog:AddToBlizOptions("BattleGroundEnemiesFixed", "BattleGroundEnemiesFixed")

  if PVPMatchScoreboard then -- for TBCC, IsTBCC
    PVPMatchScoreboard:HookScript("OnHide", PVPMatchScoreboard_OnHide)
  end

  --DBObjectLib:ResetProfile(noChildren, noCallbacks)

  self:GROUP_ROSTER_UPDATE() --Scan again, the user could have reloaded the UI so GROUP_ROSTER_UPDATE didnt fire

  -- Register permanently so the combat lockdown queue always drains,
  -- even after UnregisterEvents() runs during Disable().
  self:RegisterEvent("PLAYER_REGEN_ENABLED")
  self:RegisterEvent("PLAYER_REGEN_DISABLED")

  self:UnregisterEvent("PLAYER_LOGIN")
end

--Notes about UnitIDs
--priority of unitIDs:
--1. Arena, detected by UNIT_HEALTH (health upate), ARENA_OPPONENT_UPDATE (this units exist, don't exist anymore), we need to check for UnitExists() since there is a small time frame after the objective isn't on that target anymore where UnitExists returns false for that unitID
--2. nameplates, detected by UNIT_HEALTH, NAME_PLATE_UNIT_ADDED, NAME_PLATE_UNIT_REMOVED
--3. player's target
--4. player's focus
--5. ally targets, UNIT_TARGET fires if the target changes, we need to check for UnitExists() since there is a small time frame after an ally lost that enemy where UnitExists returns false for that unitID

function BattleGroundEnemies:NotifyChange()
  AceConfigRegistry:NotifyChange("BattleGroundEnemiesFixed")
  self:ProfileChanged()
end

function BattleGroundEnemies:ProfileChanged()
  self:UpgradeProfile(self.db.profile, self.db:GetCurrentProfile())
  self:SetupOptions()
  self:ApplyAllSettings()
end

function BattleGroundEnemies:ProfileReset()
  self:SetCurrentDbVerion(self.db.profile)
  BattleGroundEnemies:NotifyChange()
end

local timer = nil
function BattleGroundEnemies:ApplyAllSettingsDebounce()
  if timer then
    timer:Cancel()
  end -- use a timer to apply changes after 0.2 second, this prevents the UI from getting laggy when the user uses a slider option
  timer = CTimerNewTicker(0.2, function()
    BattleGroundEnemies:ApplyAllSettings()
    timer = nil
  end, 1)
end

local playerCountChangedTimer = nil
function BattleGroundEnemies:TestModePlayerCountChanged(value)
  if playerCountChangedTimer then
    playerCountChangedTimer:Cancel()
  end -- use a timer to apply changes after 0.2 second, this prevents the UI from getting laggy when the user uses a slider option
  self.Testmode.PlayerCountTestmode = value
  playerCountChangedTimer = CTimerNewTicker(0.2, function()
    if self:IsTestmodeActive() then
      self:CreateFakePlayers()
    end
    playerCountChangedTimer = nil
  end, 1)
end

-- ApplyAllSettings moved up

-- local function stringifyMultitArgs(...)
--   local args = { ... }
--   local text = ""

--   for i = 1, #args do
--     text = text .. " " .. tostring(args[i])
--   end
--   return text
-- end

-- local function getTimestamp()
--   local timestampFormat = "[%I:%M:%S] " --timestamp format
--   local stamp = BetterDate(timestampFormat, time())
--   return stamp
-- end

local sentDebugMessages = {}
function BattleGroundEnemies:OnetimeDebug(...)
  local message = table.concat({ ... }, ", ")
  if sentDebugMessages[message] then
    return
  end
  sentDebugMessages[message] = true
end

-- function BattleGroundEnemies:EnableDebugging()
--   self.db.profile.Debug = true
--   self:NotifyChange()
-- end

local sentMessages = {}
function BattleGroundEnemies:OnetimeInformation(...)
  local message = table.concat({ ... }, ", ")
  if sentMessages[message] then
    return
  end
  print("|cff0099ffBattleGroundEnemies:|r", message)
  sentMessages[message] = true
end

function BattleGroundEnemies:Information(...)
  print("|cff0099ffBattleGroundEnemies:|r", ...)
end

--fires when a arena enemy appears and a frame is ready to be shown
function BattleGroundEnemies:ARENA_OPPONENT_UPDATE(unitID, unitEvent)
  --unitEvent can be: "seen", "unseen", "destroyed", "cleared"
  if unitEvent == "cleared" then --"unseen", "cleared" or "destroyed"
    local playerButton = self.ArenaIDToPlayerButton[unitID]
    if playerButton then
      -- Skip the wipe when the local player is dead/ghost AND the bound
      -- carrier is NOT the local player. Blizzard fires "cleared" for
      -- arena tokens when the dead user loses visibility — but other
      -- carriers may still be alive and holding the objective. Wiping
      -- here makes their icon disappear until you respawn.
      --
      -- If the bound carrier IS the local user (user dropped the
      -- objective by dying), the wipe IS correct and runs.
      if UnitIsDeadOrGhost("player") and playerButton ~= self.UserButton then
        return
      end
      self.ArenaIDToPlayerButton[unitID] = nil
      playerButton:UpdateEnemyUnitID("Arena", false)
      playerButton:DispatchEvent("ArenaOpponentHidden")
    end
  end
  self:CheckForArenaEnemies()
end

-- Deprecated/Removed SanitizeName to prevent secret value crashes.
BattleGroundEnemies.SanitizeName = nil
-- Logic is now handled locally in GetPlayerbuttonByUnitID via 'clean' helper.

function BattleGroundEnemies:SafeGetUnitName(unitID)
  if type(unitID) ~= "string" then
    return nil
  end
  local func = _G.UnitName or UnitName
  if not func then
    return nil
  end -- Extra safety
  local ok, name, server = pcall(func, unitID)
  if not ok or not name then
    return nil
  end

  -- name/server can be SECRET in instanced PvP. Comparing (server ~= "") or
  -- concatenating (name.."-"..server) a secret EMITS taint and is blocked — and
  -- the old pcall did NOT suppress that taint, it only hid the error. When either
  -- is secret, return the bare name (callers pass it only to SetText or to
  -- issecretvalue-guarded lookups).
  if issecretvalue and (issecretvalue(name) or issecretvalue(server)) then
    return name
  end
  if server and server ~= "" then
    return name .. "-" .. server
  end
  return name
end

-- New helper to safely access player buttons with potential secret keys
function BattleGroundEnemies:SafeGetPlayerButton(playerTable, key)
  if not key then
    return nil
  end
  local ok, button = pcall(function()
    return playerTable[key]
  end)
  if ok then
    return button
  end
  return nil
end

-- Faction check helper: returns true if the unit belongs to the enemy faction.
-- Uses UnitFactionGroup (string-based) instead of UnitIsEnemy (can return secret values in 12.0).
-- Returns true when the unit is likely an enemy.
-- In BGs (including cross-faction Blitz): uses UnitIsFriend which correctly
-- reflects team assignment regardless of actual player faction.
-- In arena: returns true (don't filter — ArenaIDToPlayerButton and structural
-- checks handle correctness; faction/reaction APIs are unreliable in solo shuffle).
local function IsEnemyUnit(unitID)
  local _, instanceType = IsInInstance()
  if instanceType == "pvp" then
    return not UnitIsFriend("player", unitID)
  end
  return true
end
-- Expose for Mainframe.lua
BattleGroundEnemies.IsEnemyUnit = IsEnemyUnit

-- PID Matching System (hoisted to module scope to avoid per-call allocations)
do
  -- Class token to numeric ID (matches UnitClass 3rd return)
  local ClassTokenToID = {
    WARRIOR = 1,
    PALADIN = 2,
    HUNTER = 3,
    ROGUE = 4,
    PRIEST = 5,
    DEATHKNIGHT = 6,
    SHAMAN = 7,
    MAGE = 8,
    WARLOCK = 9,
    MONK = 10,
    DRUID = 11,
    DEMONHUNTER = 12,
    EVOKER = 13,
  }

  -- Public predicate: does an ArenaIDToPlayerButton entry contradict live
  -- data on `token`? Returns true ONLY when the button's stored class or
  -- race differs from a non-secret live read. nil/secret/Unknown values
  -- short-circuit to false ("can't disprove") so we don't invalidate on
  -- missing data. Used inside the matcher (arena-fast-path / arena-cross-
  -- identity) and externally by GetOrbCarrierButton/GetFlagCarrierButton
  -- to decide whether to keep an existing mapping or re-resolve.
  function BattleGroundEnemies:ArenaMappingContradicted(btn, token)
    local pd = btn and btn.PlayerDetails
    if not pd or not token then
      return false
    end
    local okClass, _, liveClassID = pcall(UnitClassBase, token)
    if okClass and liveClassID then
      local storedClassID = ClassTokenToID[pd.PlayerClass or ""]
      if storedClassID and storedClassID ~= liveClassID then
        return true
      end
    end
    local okRace, liveRace = pcall(UnitRace, token)
    if okRace and liveRace and not (issecretvalue and issecretvalue(liveRace)) then
      local storedRace = pd.PlayerRace
      if storedRace and storedRace ~= "Unknown" and storedRace ~= liveRace then
        return true
      end
    end
    return false
  end

  -- Race token to numeric ID (built once from C_CreatureInfo at load time)
  local RaceTokenToID = {}
  do
    local playableRaces =
      { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 22, 25, 27, 28, 29, 30, 31, 32, 34, 35, 36, 37, 52, 84, 85, 86 }
    for i = 1, #playableRaces do
      local raceInfo = C_CreatureInfo.GetRaceInfo(playableRaces[i])
      if raceInfo and raceInfo.clientFileString then
        RaceTokenToID[raceInfo.clientFileString] = raceInfo.raceID
      end
    end
    -- Some code paths feed in localized race names (e.g. "Undead", "Earthen")
    -- rather than the C_CreatureInfo clientFileString ("Scourge", "EarthenDwarf").
    -- Add aliases so the lookup succeeds for both formats.
    RaceTokenToID["Undead"] = RaceTokenToID["Scourge"] or 5
    RaceTokenToID["Earthen"] = RaceTokenToID["EarthenDwarf"] or 85
  end

  -- Collapse faction-variant race IDs to a single canonical ID
  local RaceCollapseMap = {
    [24] = 25, -- Pandaren (Neutral)
    [26] = 25, -- Pandaren (Horde)
    [70] = 52, -- Dracthyr (Horde)
    [84] = 85, -- Earthen (Horde)
    [91] = 86, -- Harronir (Alt ID)
  }

  -- PID = Player ID (unique identifier using bit-shifting)
  -- Gender:     × 2^32 - positions 33+
  -- Race:       × 2^24 - positions 25-32
  -- Class:      × 2^16 - positions 17-24
  -- HonorLevel: × 2^0  - positions 0-15
  -- Returns fullPID, basePID, corePID, classGenderPID, classPID
  --   fullPID        = gender + race + class + honor (most specific)
  --   basePID        = gender + race + class (honor stripped)
  --   corePID        = race + class only (gender stripped)
  --   classGenderPID = gender + class (race stripped, for when race is nil/mismatched)
  --   classPID       = class only (race+gender stripped, broadest match)
  local function EN_CalculatePID(raceID, classID, gender, honorLevel)
    if not classID then
      return 0, 0, 0, 0, 0
    end
    local classPID = classID * 65536
    local genderComponent = (gender or 0) * 4294967296
    local classGenderPID = genderComponent + classPID
    if not raceID then
      -- Race unavailable (combat secret) -- classGenderPID and classPID are usable
      return 0, 0, 0, classGenderPID, classPID
    end
    local collapsedRaceID = RaceCollapseMap[raceID] or raceID
    if not collapsedRaceID then
      return 0, 0, 0, classGenderPID, classPID
    end
    local corePID = (collapsedRaceID * 16777216) + classPID
    local basePID = genderComponent + corePID
    local honor = (honorLevel and honorLevel > 0) and honorLevel or 0
    return basePID + honor, basePID, corePID, classGenderPID, classPID
  end

  local function EN_UnitPID(unit)
    if not UnitExists(unit) then
      return 0, 0, 0, 0, 0
    end
    local _, _, raceID = UnitRace(unit)
    local _, _, classID = UnitClass(unit)
    local gender = UnitSex(unit)
    if not classID then
      return 0, 0, 0, 0, 0
    end
    local unitHonor = UnitHonorLevel(unit)
    -- Detect placeholder data: WARRIOR class (1) with no race suggests incomplete API data.
    -- WoW may return classID=1 as default before real data loads. Skip matching to avoid
    -- false positives; retry mechanisms will catch it once proper data is available.
    -- Only check for players (UnitIsPlayer) to avoid false positives from NPCs/objects.
    if classID == 1 and (not raceID or raceID == 0) then
      return 0, 0, 0, 0, 0
    end
    return EN_CalculatePID(raceID, classID, gender, unitHonor)
  end

  local function EN_ScoreboardPID(p)
    -- Race: use PlayerRace from scoreboard. Format matches
    -- C_CreatureInfo.GetRaceInfo().clientFileString (e.g. "BloodElf").
    local raceID = RaceTokenToID[p.PlayerRace or ""] or 0
    local classID = ClassTokenToID[p.PlayerClass or ""] or 0
    if raceID == 0 and p.PlayerRace and p.PlayerRace ~= "Unknown" then
      -- Only warn once per race token to avoid spam
      local warnKey = "race_" .. p.PlayerRace
      if not (BattleGroundEnemies.DuplicateLog or {})[warnKey] then
        BattleGroundEnemies.DuplicateLog = BattleGroundEnemies.DuplicateLog or {}
        BattleGroundEnemies.DuplicateLog[warnKey] = true
      end
    end
    -- Gender: try GetPlayerInfoByGUID (may return nil for unseen enemies)
    local gender
    if p.guid then
      local _, cachedGender = GetCachedPlayerInfo(p.guid)
      gender = cachedGender
    end
    return EN_CalculatePID(raceID, classID, gender, p.honorLevel)
  end

  -- Per-scan-cycle cache: avoids redundant PID matching for the same unit
  -- across ScanTargets iterations. Cleared at the start of each ScanTargets call.
  local scanCycleCache = {}

  -- Dynamic single-word tokens that WoW fires UNIT_HEALTH / UNIT_POWER_FREQUENT
  -- for and that can reassign to a different player at any time (target click,
  -- focus change, mouse move, soft-target switch). Caching these in
  -- scanCycleCache is a correctness hazard: a stale entry from a prior event
  -- gets reused before the deferred PLAYER_TARGET_CHANGED handler wipes it,
  -- and the matcher returns the previous owner of the token while
  -- UnitHealth(token) reads the new owner's value — cross-attaching the new
  -- player's health onto the previous player's bar. Compound tokens
  -- (raidNtarget, nameplateNtarget, pettarget, focustarget) are also dynamic
  -- but are never the unitID of a fired event, so their cache entries can't
  -- be reached through the event flow — keep caching them.
  -- Exposed on BattleGroundEnemies so PlayerButton.lua can reuse the same
  -- list for stale-token validation in UpdateUnitID.
  BattleGroundEnemies.DYNAMIC_TOKENS = {
    target = true,
    focus = true,
    mouseover = true,
    softenemy = true,
    softfriend = true,
  }
  local DYNAMIC_TOKENS = BattleGroundEnemies.DYNAMIC_TOKENS

  -- Cross-tick sticky cache: prevents PID oscillation between scan cycles.
  -- Once a unitID resolves to a button, it stays pinned until:
  --   1) ClearPIDCaches (roster change)
  --   2) UNIT_TARGET fires for the source unit (target changed)
  --   3) Class validation fails (definitely a different player)
  local stickyPIDCache = {}

  -- Per-unitID record of the last (button, path) we logged via _logTierMatch.
  -- Used to suppress duplicate success-log spam: if a unitID resolves to the
  -- same button via the same code path as last call, stay silent. Logs only
  -- fire on transitions (different button OR different path). Never wiped —
  -- subsequent wrong-button matches still log naturally because they differ.
  -- local _lastLoggedMatch = {}
  -- Per-unitID signature of the last mismatch we logged. Suppresses
  -- duplicate spam when the matcher is called many times per click
  -- (ScanTargets sweeps, UNIT_TARGET, PLAYER_TARGET_CHANGED_Deferred all
  -- run the matcher for the same unitID within a few ticks).
  -- local _lastLoggedMismatch = {}

  function BattleGroundEnemies:ClearPIDCaches()
    wipe(scanCycleCache)
    wipe(stickyPIDCache)
    self.DuplicateLog = {}
    self.PlayerGUIDs = {}
  end

  function BattleGroundEnemies:ClearScanCycleCache()
    wipe(scanCycleCache)
  end

  -- Invalidate a specific sticky cache entry (called when UNIT_TARGET fires
  -- for the source unit, meaning the compound token now points to someone else)
  function BattleGroundEnemies:InvalidateStickyPID(unitID)
    stickyPIDCache[unitID] = nil
  end

  -- Capture live unit attrs onto a button. Authoritative-only: caller must
  -- be CERTAIN btn = the live unit at unitID. Wrong calls poison the
  -- button's stored attrs (which feed the matcher's tier comparisons).
  -- Safe call sites: matcher's tier 5 (sole same-class), tier 6 (race
  -- uniquely identifies via authoritative scoreboard race), arena fast-path
  -- (Blizzard ArenaIDToPlayerButton), name lookup (definitive when name
  -- is non-secret), AND PostClick/focus stash bypass (user clicked that
  -- exact frame, secure macro targeted that exact name → unit IS that
  -- player). Captures gender, honorLevel, GuildName (with three-state
  -- nil/false/string semantics), and lastPowerType.
  function BattleGroundEnemies:CaptureUnitAttrs(btn, unitID)
    if not btn or not btn.PlayerDetails or not unitID then
      return
    end
    local pd = btn.PlayerDetails
    -- gender
    local g = pd.gender
    if g == nil or (issecretvalue and issecretvalue(g)) or pd._genderSource == "harvest" then
      local sex = UnitSexBase(unitID)
      if sex and (g == nil or (issecretvalue and issecretvalue(g)) or sex ~= g) then
        pd.gender = sex
        pd._genderSource = "live"
      elseif sex and sex == g and pd._genderSource == "harvest" then
        pd._genderSource = "live"
      end
    end
    -- honorLevel
    local h = pd.honorLevel
    if h == nil or (issecretvalue and issecretvalue(h)) or pd._honorLevelSource == "harvest" then
      local honor = UnitHonorLevel(unitID)
      if honor and honor > 0 and (h == nil or (issecretvalue and issecretvalue(h)) or honor ~= h) then
        pd.honorLevel = honor
        pd._honorLevelSource = "live"
      elseif honor and honor > 0 and honor == h and pd._honorLevelSource == "harvest" then
        pd._honorLevelSource = "live"
      end
    end
    -- GuildName: three-state (nil=unknown, false=confirmed guildless, "X"=in guild "X")
    local currentGuild = pd.GuildName
    if currentGuild == nil or (issecretvalue and issecretvalue(currentGuild)) or pd._GuildNameSource == "harvest" then
      local gn = GetGuildInfo(unitID)
      if gn then
        if currentGuild == nil or currentGuild == false or (issecretvalue and issecretvalue(currentGuild)) or gn ~= currentGuild then
          pd.GuildName = gn
          pd._GuildNameSource = "live"
        elseif gn == currentGuild and pd._GuildNameSource == "harvest" then
          pd._GuildNameSource = "live"
        end
      else
        -- gn nil: could be "no guild" or "can't read". UnitSexBase as readability proxy.
        local sexProbe = UnitSexBase(unitID)
        if sexProbe then
          if currentGuild ~= false then
            pd.GuildName = false
            pd._GuildNameSource = "live"
          elseif pd._GuildNameSource == "harvest" then
            pd._GuildNameSource = "live"
          end
        end
      end
    end
    -- lastPowerType: pcall because UnitPowerType errors on compound tokens
    local okPower, pt = pcall(UnitPowerType, unitID)
    if okPower and pt and pt ~= pd.lastPowerType then
      pd.lastPowerType = pt
      pd._lastPowerTypeSource = "live"
    elseif okPower and pt and pd._lastPowerTypeSource == "harvest" then
      pd._lastPowerTypeSource = "live"
    end
  end

  -- Enemy-only matcher. Allies are resolved by direct raidN/partyN/player
  -- token lookup via BattleGroundEnemies.Allies:GetAllyButtonByUnitID — no
  -- PID, no fingerprinting, no scoreboard. This function must never return
  -- an ally button under any circumstances.
  -- @param playerType: legacy parameter; kept for call-site compatibility.
  --   Always treated as "Enemies" internally.
  -- @param ignoreExistingArena: if true, consider ALL buttons even those with arena tokens
  --   (used for Kotmogu orb detection where arena tokens shift between players)
  function BattleGroundEnemies:GetPlayerbuttonByUnitID(unitID, playerType, ignoreExistingArena)
    if not unitID or not UnitExists(unitID) then
      return nil
    end
    -- Hard-pin to enemies. Any caller passing "Allies" is a bug — return nil
    -- rather than silently fall through, so regressions surface immediately.
    if playerType == "Allies" then
      return nil
    end
    playerType = "Enemies"

    -- Reject non-players (pets, NPCs, totems, objects) at the door. Without
    -- this, the matcher happily processes anything, and stale sticky-PID /
    -- fallback class-match tiers can attribute a pet's identity to a random
    -- same-class player button. UnitIsPlayer is NOT in the
    -- SecretWhenUnitComparisonRestricted family (that tag covers Friend /
    -- Enemy / UnitIsUnit), but wrap in pcall anyway for compound-token
    -- safety (raid1target, nameplate1target, etc). Only reject on an
    -- EXPLICIT false. nil/secret returns fall through — downstream guards
    -- (GUID/name lookups, class checks) still refuse to match when identity
    -- data is unknown.
    local okPlayer, isPlayer = pcall(UnitIsPlayer, unitID)
    if okPlayer and isPlayer == false then
      return nil
    end

    -- Capture non-secret identity from the live token and stash on the matched
    -- button's PlayerDetails. Future matches against the same button get more
    -- discriminators (gender + honor) than scoreboard alone provides.
    -- UnitSex and UnitHonorLevel return non-secret numbers for targetable units;
    -- overwrites nil OR secret-tagged values (scoreboard honorLevel is secret).
    --
    -- NOTE: we deliberately do NOT capture a short-name-only (UnitName first
    -- return) here anymore. Any time a token produced a wrong-button match
    -- (stale sticky, fingerprint fallback, etc.), the captured short-name
    -- permanently polluted the wrong frame — e.g. the flag-carrier rogue's
    -- name "Luxnocis" would stamp onto an unrelated warlock's frame and
    -- survive scoreboard refreshes. ShowRealmnames=false is honoured by
    -- splitting the scoreboard-supplied PlayerName via strsplit.
    local function captureLiveAttrs(btn)
      -- Thin wrapper — delegate to the module-level method so other
      -- code paths (PostClick stash bypass, focus stash bypass) can
      -- capture from the same authoritative source without going
      -- through the matcher.
      return BattleGroundEnemies:CaptureUnitAttrs(btn, unitID)
    end

    -- Gated write into scanCycleCache. Skips writes for orb/flag carrier
    -- lookups (need fresh resolves) and for dynamic tokens (target/focus/
    -- mouseover/softenemy/softfriend — caching those caused cross-attach
    -- when the token reassigned between events).
    local function recordCycleMatch(button)
      if not ignoreExistingArena and not DYNAMIC_TOKENS[unitID] then
        scanCycleCache[unitID] = button
      end
    end

    -- Gated write into stickyPIDCache. Same dynamic-token rule as the cycle
    -- cache: sticky validates by class match, which is meaningless for same-
    -- class twins when a dynamic token reassigns between them.
    local function recordStickyMatch(button, classID)
      if DYNAMIC_TOKENS[unitID] then
        return
      end
      stickyPIDCache[unitID] = { button = button, classID = classID }
    end

    -- Reject friendly units entirely — this matcher is enemy-only. In BGs
    -- (including cross-faction Blitz) UnitIsFriend correctly reflects team
    -- assignment regardless of actual faction. In arena, skip the guard —
    -- arena tokens use ArenaIDToPlayerButton and ally-side lookups don't
    -- call here at all.
    local _, instanceType = IsInInstance()
    if instanceType == "pvp" then
      if UnitIsFriend("player", unitID) then
        return nil
      end
    end

    -- Successful-match diag (target clicks + orb/flag-carrier resolves
    -- only). Tags the path that produced the match so we can see whether
    -- a wrong button came from sticky cache, name lookup, a specific tier,
    -- arena peer elimination, or fallback. Call at every return-button
    -- site below.
    -- local function _logTierMatch(button, path)
    --   -- Trigger filter: target click, orb/flag carrier resolves, AND any
    --   -- arena/compound token (the misroute hunt for Grant/Viejito is most
    --   -- likely via these — e.g. raidNtarget where an ally targets the
    --   -- carrier, or a nameplate slot reused).
    --   local triggerable = unitID == "target"
    --       or unitID == "playertarget"
    --       or ignoreExistingArena
    --       or unitID:match("^arena%d+$")
    --       or unitID:match("^nameplate%d+$")
    --       or unitID:match("^raid%d+target$")
    --       or unitID:match("^party%d+target$")
    --       or unitID == "pettarget"
    --       or unitID == "focustarget"
    --   if not triggerable then
    --     return
    --   end
    --   -- Skip cache-hit paths entirely — they only mean "we kept what
    --   -- tier-N or arena-X decided earlier", no new diagnostic info.
    --   -- Without this filter the chat floods with alternating scan-cycle
    --   -- and sticky-cache lines for any stable target.
    --   if path == "scan-cycle-cache" or path == "sticky-cache" or path == "sticky-cache(fallback)" then
    --     return
    --   end
    --   -- De-dupe by button only: if the same button is being matched, it
    --   -- doesn't matter which tier produced it this tick — the diagnostic
    --   -- value of repeated identical resolves is zero. Logs only fire when
    --   -- the matched button changes.
    --   local last = _lastLoggedMatch[unitID]
    --   if last and last.button == button then
    --     return
    --   end
    --   _lastLoggedMatch[unitID] = { button = button, path = path }
    --   -- local trigger = unitID
    --   -- local nm = (button and button.PlayerDetails and button.PlayerDetails.PlayerName) or "<unnamed>"
    --   -- local _GAM = C_AddOns and C_AddOns.GetAddOnMetadata or _G.GetAddOnMetadata
    --   -- local _ver = _GAM and _GAM("BattleGroundEnemiesFixed", "Version")
    --   -- local _verTag = "v?"
    --   -- if type(_ver) == "string" then
    --   --   local trailing = _ver:match("(%d+)$")
    --   --   if trailing then
    --   --     _verTag = "v" .. trailing
    --   --   end
    --   -- end
    --   -- Diagnostic: re-enable to debug a future matcher misroute. Prints
    --   -- which tier produced the match for arena/compound/target tokens.
    --   -- print(
    --   --   string.format(
    --   --     "|cff66ccff[BGEF %s - matched - %s]|r %s via %s",
    --   --     _verTag,
    --   --     trigger,
    --   --     nm,
    --   --     path
    --   --   )
    --   -- )
    -- end

    -- Use BattleGroundEnemies:ArenaMappingContradicted so closures inside
    -- this function reference the same predicate that's exposed publicly
    -- (used by GetOrbCarrierButton/GetFlagCarrierButton in ObjectiveAndRespawn
    -- to gate overwriting an existing chat-set mapping).
    local function arenaMappingContradicted(btn, token)
      return BattleGroundEnemies:ArenaMappingContradicted(btn, token)
    end

    -- For arena tokens, check the direct ArenaIDToPlayerButton mapping first.
    -- This is authoritative for stable assignments. For flag/orb carrier
    -- lookups (ignoreExistingArena=true) the mapping may point at the
    -- *previous* carrier — skip this fast-path and resolve fresh.
    if not ignoreExistingArena and unitID:match("^arena%d+$") and self.ArenaIDToPlayerButton[unitID] then
      local arenaBtn = self.ArenaIDToPlayerButton[unitID]
      if arenaMappingContradicted(arenaBtn, unitID) then
        -- Mapping points at a button whose stored class/race contradicts the
        -- live unit at this token. Wipe the wrong mapping and fall through
        -- to the proper tiers so the matcher can re-resolve.
        self.ArenaIDToPlayerButton[unitID] = nil
      else
        recordCycleMatch(arenaBtn)
        captureLiveAttrs(arenaBtn)
        -- _logTierMatch(arenaBtn, "arena-fast-path")
        return arenaBtn
      end
    end

    -- Arena-token cross-identity: if this unit is the same real player as
    -- a known arena token (flag/orb carrier), return the button mapped to
    -- that arena token. Strong identity — UnitIsUnit compares underlying
    -- players across token types. Fixes the "same-class duplicates both
    -- track the carrier" bug where e.g. nameplate5 for a flag-carrying
    -- druid fingerprint-matches Curly but arena1 is mapped to Rotagem;
    -- this resolves nameplate5 to Rotagem too.
    -- UnitIsUnit is SecretWhenUnitComparisonRestricted — return may be a
    -- secret bool — so use truthy-check only (no equality compare).
    if self.ArenaIDToPlayerButton then
      for i = 1, 5 do
        local arenaID = "arena" .. i
        local arenaBtn = self.ArenaIDToPlayerButton[arenaID]
        if arenaBtn and arenaBtn.PlayerType == "Enemies" then
          -- UnitIsUnit is SecretWhenUnitComparisonRestricted. In 12.0.5 PvP
          -- it can return a SECRET BOOLEAN for cross-side token pairs
          -- (e.g. raid1 ↔ arenaN) — touching a secret value in a boolean
          -- test would taint the entire call stack. Pre-filter with
          -- issecretvalue before any truthy check. Only trust EXPLICIT
          -- booleans; treat nil/secret as "can't determine" and skip.
          local ok, same = pcall(UnitIsUnit, unitID, arenaID)
          if ok and not (issecretvalue and issecretvalue(same)) and same then
            -- Validate the cached mapping isn't contradicted by live data
            -- on THIS unitID before returning. If stored class/race on
            -- arenaBtn doesn't match what UnitClassBase/UnitRace report at
            -- unitID, the mapping was wrong (likely from a misroute at
            -- carrier-pickup time when data was sparse). Wipe it and let
            -- the matcher fall through to the proper tiers.
            if arenaMappingContradicted(arenaBtn, unitID) then
              self.ArenaIDToPlayerButton[arenaID] = nil
              -- continue the loop; another arena slot might match cleanly
            else
              recordCycleMatch(arenaBtn)
              -- captureLiveAttrs deliberately omitted: UnitIsUnit can return
              -- secret booleans in 12.0.5 PvP and we've seen wrong-twin
              -- positives. Don't poison the matched button's stored attrs.
              -- _logTierMatch(arenaBtn, "arena-cross-identity")
              return arenaBtn
            end
          end
        end
      end
    end

    -- Check per-cycle cache (same unitID already resolved this scan tick).
    -- Skip cache when ignoreExistingArena is set (need fresh lookup for orb
    -- detection) or when the token is dynamic (see DYNAMIC_TOKENS — caching
    -- target/focus/mouseover causes cross-attach when the token reassigns).
    if not ignoreExistingArena and not DYNAMIC_TOKENS[unitID] then
      local cached = scanCycleCache[unitID]
      if cached ~= nil then
        if cached then
          -- Same class+race contradiction guard as sticky/arena tiers. The
          -- cache is wiped per-ScanTargets tick, but a UNIT_HEALTH/POWER
          -- event firing between ticks can hit a stale entry when a
          -- compound token (nameplateN/raidNtarget) has reassigned to a
          -- same-class twin since the cache was written.
          if BattleGroundEnemies:ArenaMappingContradicted(cached, unitID) then
            scanCycleCache[unitID] = nil
            -- fall through to re-resolve via tiers below
          else
            -- _logTierMatch(cached, "scan-cycle-cache")
            return cached
          end
        else
          return nil -- cached false means "no match found this tick"
        end
      end
    end

    -- GUID fast-path removed: GUIDs are effectively always secret in
    -- 12.0.5 PvP. UnitGUID returns a secret value that's unusable as a
    -- table key, and the PlayerGUIDs table can never be populated with
    -- a real key (CreateOrUpdatePlayerDetails stopped doing that).
    -- Fall straight through to name-based lookup.

    local okName, unitName = pcall(GetUnitName, unitID, true)
    if okName and unitName and not (issecretvalue and issecretvalue(unitName)) then
      -- Canonicalize: GetUnitName returns "Name" for same-realm units,
      -- but Players[] stores under "Name-Realm" form (CanonicalName at
      -- storage). Without this, same-realm enemies fall through this
      -- name tier and end up matched via the lower PID/fallback tiers,
      -- which can attribute the token to a wrong same-class twin.
      local nameButton = self[playerType].Players[BattleGroundEnemies:CanonicalName(unitName)]
      if nameButton then
        recordCycleMatch(nameButton)
        captureLiveAttrs(nameButton)
        -- _logTierMatch(nameButton, "name-lookup")
        return nameButton
      end
    end

    -- Check cross-tick sticky cache (prevents PID oscillation between scan cycles).
    -- Only used when GUID lookup failed (combat taint, compound tokens, etc.).
    -- Validates that the cached button still exists in the roster and class still matches.
    -- ignoreExistingArena=true → flag/orb carrier lookup; bypass sticky so the
    -- carrier resolves fresh (arena token identity can change mid-match).
    -- Dynamic tokens (target/focus/mouseover/softenemy/softfriend) bypass too:
    -- sticky validates on class match, which is meaningless for same-class
    -- twins when the token reassigns between them. PLAYER_TARGET_CHANGED
    -- does invalidate the sticky for "target" but only one frame later, after
    -- the synchronous UNIT_HEALTH("target") has already cross-attached.
    local sticky = (not ignoreExistingArena) and not DYNAMIC_TOKENS[unitID] and stickyPIDCache[unitID] or nil
    if sticky then
      local stickyValid = false
      -- Button still in roster check — look at PlayerList (secret-safe) instead of Players dict
      local buttonInRoster = false
      if sticky.button and self[playerType].PlayerList then
        local roster = self[playerType].PlayerList
        for i = 1, #roster do
          if roster[i] == sticky.button then
            buttonInRoster = true
            break
          end
        end
      end
      if buttonInRoster then
        -- Verify class still matches the unit via numeric classID (no string
        -- compare). UnitClassBase is non-secret post-12.0.5 — if it returns
        -- nil/fails, the token isn't pointing at a valid unit right now, so
        -- the sticky is unverifiable. Invalidate rather than blindly trust:
        -- compound/nameplate tokens can silently switch to a different
        -- player, and captureLiveAttrs on a wrong-match button writes that
        -- player's name onto the wrong frame (seen in-game: warlock's
        -- frame labelled "Luxnocis" because a stale sticky got captured
        -- against a rogue-occupied token).
        --
        -- ALSO check race (class+race must not contradict). Class-only is
        -- insufficient for same-class twins — when nameplate1 reassigns
        -- between two hunters of different races, class still matches but
        -- the sticky points at the wrong hunter. Use the same contradiction
        -- predicate that arena tiers use; it short-circuits to "valid" when
        -- live race is unreadable, so we don't over-invalidate.
        local okClass, _, classID = pcall(UnitClassBase, unitID)
        if okClass and classID and sticky.classID == classID
            and not BattleGroundEnemies:ArenaMappingContradicted(sticky.button, unitID) then
          stickyValid = true
        end
      end
      if stickyValid then
        recordCycleMatch(sticky.button)
        -- captureLiveAttrs deliberately omitted: sticky perpetuates the
        -- prior tier's decision, which may have been a tier-6+ narrow-down
        -- rather than a tier-5 unique-class. Capturing here would re-poison
        -- the button each tick. The original tier match (if it was tier-5)
        -- already captured authoritatively.
        -- _logTierMatch(sticky.button, sticky.fallback and "sticky-cache(fallback)" or "sticky-cache")
        return sticky.button
      else
        stickyPIDCache[unitID] = nil
      end
    end

    -- Unique-class match: if only one button on this side has the unit's class, it's unambiguous.
    -- If multiple share the class, narrow by race (class+race unique match).
    -- 12.0.5: compare via numeric classID (third return of UnitClass) instead of
    -- the classToken string — strings may be secret and comparison would taint.
    local hasMultipleCandidates = false
    local okClass, _, unitClassID = pcall(UnitClassBase, unitID)
    local list = self[playerType].PlayerList
    if okClass and unitClassID and list then
      local match = nil
      local count = 0
      for i = 1, #list do
        local button = list[i]
        if button.PlayerDetails and ClassTokenToID[button.PlayerDetails.PlayerClass or ""] == unitClassID then
          count = count + 1
          match = button
        end
      end
      -- arena-skip removed: previous code excluded buttons with
      -- UnitIDs.Arena set ("already identified via arena token, skip"). That
      -- was wrong when a compound token (raid5target, nameplate1, etc.)
      -- points at the arena-claimed carrier — arena cross-identity tier
      -- above can't always confirm it (UnitIsUnit returns secret in 12.0.5
      -- PvP for compound tokens), so tiers below MUST be able to resolve
      -- the carrier as a candidate. Without this fix, a same-class twin
      -- becomes the "unique" tier-5 match, misrouting compound tokens to
      -- the wrong button (the cross-attach Grant/Viejito symptom).
      if count == 1 and match then
        recordCycleMatch(match)
        recordStickyMatch(match, unitClassID)
        captureLiveAttrs(match)
        -- _logTierMatch(match, "tier-5-class-unique")
        return match
      end
      hasMultipleCandidates = count > 1
    end

    -- Helper: numeric classID match without tainting on secret classToken strings
    local function buttonClassMatches(button)
      return button.PlayerDetails and ClassTokenToID[button.PlayerDetails.PlayerClass or ""] == unitClassID
    end

    -- Build the same-class candidate set ONCE for reuse across tiers 7-9.
    -- Mirrors the per-tier filtering logic (skip arena-claimed when not
    -- ignoreExistingArena). The strict-rule check (allCandidatesHaveAttr)
    -- needs this set to know whether all candidates have data for a given
    -- comparator before the tier fires.
    local sameClassCandidates
    if hasMultipleCandidates and list then
      sameClassCandidates = {}
      for i = 1, #list do
        local b = list[i]
        -- arena-skip removed (see tier-5 comment above): arena-claimed
        -- buttons must remain candidates so the strict-rule gate has the
        -- correct count and tiers below can resolve compound tokens that
        -- point at the carrier.
        if buttonClassMatches(b) then
          sameClassCandidates[#sameClassCandidates + 1] = b
        end
      end
    end
    -- Generic safe-equality: post-12.0.5 both strings AND numbers can be secret.
    -- Returns false if either side is secret OR either side is nil.
    local function safeEq(a, b)
      if a == nil or b == nil then
        return false
      end
      if issecretvalue and (issecretvalue(a) or issecretvalue(b)) then
        return false
      end
      return a == b
    end
    -- Soft-equality for the dominated cascade (inner tiebreakers in tiers
    -- 7/8/8.5/9). Returns true when either side is nil/secret (no opinion)
    -- OR both sides match. Returns false ONLY when both sides have
    -- definite non-nil non-secret values that differ.
    -- Without this, the cascade rejects candidates whose stored attrs
    -- haven't been populated yet by captureLiveAttrs — e.g., tier 9
    -- guild-match unique-pick gets blocked because the candidate's
    -- gender/honor were never captured. Outer key (the tier's primary
    -- attr) still uses strict safeEq so the tier itself is gated correctly.
    local function softEq(a, b)
      if a == nil or b == nil then
        return true
      end
      if issecretvalue and (issecretvalue(a) or issecretvalue(b)) then
        return true
      end
      return a == b
    end
    -- Guild equality with three-state semantics:
    --   nil   = unknown (we haven't established whether the unit is in a guild)
    --   false = confirmed guildless
    --   "X"   = in guild "X"
    -- Returns true when the values match (both string and equal, or both false),
    -- false when they definitively differ (string vs different string, or string
    -- vs false, or false vs string), nil when at least one side is unknown.
    local function guildCmp(a, b)
      if a == nil or b == nil then
        return nil -- unknown
      end
      if issecretvalue and (issecretvalue(a) or issecretvalue(b)) then
        return nil -- secret = unknown
      end
      return a == b -- handles string==string, false==false, and the cross cases
    end
    -- Strict-rule helper: returns true if EVERY candidate has comparable
    -- (non-nil, non-secret) stored data for the given field. If any
    -- candidate has nil/secret, the tier shouldn't fire — we'd be picking
    -- the only candidate WITH data, which is a guess (the others might
    -- actually be the unit, we just can't compare).
    -- For GuildName specifically, `false` (confirmed guildless) counts as
    -- comparable data — Lua's `v == nil` correctly excludes only nil
    -- without flagging false as missing.
    local function allCandidatesHaveAttr(candidates, field)
      for i = 1, #candidates do
        local pd = candidates[i].PlayerDetails
        local v = pd and pd[field]
        if v == nil then
          return false
        end
        if issecretvalue and issecretvalue(v) then
          return false
        end
      end
      return true
    end
    -- Race from scoreboard (raceName, localized) and UnitRace(unit) 1st return
    -- are both non-secret post-12.0.5 — direct string compare is safe.
    -- IMPORTANT: `unitRace` MUST be declared as a local BEFORE the function
    -- so the function captures it as a proper upvalue. If declared after,
    -- Lua resolves the name to a global (always nil) and every call to
    -- raceComparableAndEqual returns false — silently breaking the race
    -- tier (6) AND the race component of every higher tier (7/8/8.5/9).
    local unitRace = nil
    local function raceComparableAndEqual(button)
      local pr = button.PlayerDetails and button.PlayerDetails.PlayerRace
      return pr ~= nil and unitRace ~= nil and pr == unitRace
    end

    -- Class+race unique match: disambiguate same-class candidates by race.
    if hasMultipleCandidates then
      local okRace, unitRaceLocalized = pcall(UnitRace, unitID)
      if okRace and unitRaceLocalized then
        unitRace = unitRaceLocalized
        local match = nil
        local count = 0
        for i = 1, #list do
          local button = list[i]
          if buttonClassMatches(button) and raceComparableAndEqual(button) then
            count = count + 1
            match = button
          end
        end
        if count == 1 and match then
          recordCycleMatch(match)
          recordStickyMatch(match, unitClassID)
          captureLiveAttrs(match)
          -- _logTierMatch(match, "tier-6-race")
          return match
        end
      end
    end

    -- Refine the candidate set after tier 6: same-class candidates whose
    -- stored race is compatible with the unit's live race. Same-class but
    -- different-race candidates are already known NOT to be the unit (race
    -- is NeverSecret on scoreboard, so PlayerRace is authoritative). Strict
    -- rule checks in tiers 7-9 should use this narrower set so a different-
    -- race candidate's nil gender/honor/power doesn't block the tier from
    -- firing for the actual could-be-the-unit subset.
    -- Falls back to full sameClassCandidates if unit race wasn't readable
    -- (unitRace is nil — tier 6 couldn't run) or if no candidate matches
    -- the unit race (shouldn't happen given scoreboard race authority, but
    -- defensive in case unit race is wrong).
    -- "Unknown" stored race counts as compatible — we can't rule them out.
    local refinedCandidates = sameClassCandidates
    if unitRace and sameClassCandidates then
      local filtered = {}
      for _, c in ipairs(sameClassCandidates) do
        local pr = c.PlayerDetails and c.PlayerDetails.PlayerRace
        if pr == nil or pr == "Unknown" or pr == unitRace then
          filtered[#filtered + 1] = c
        end
      end
      if #filtered > 0 then
        refinedCandidates = filtered
      end
    end

    -- Gender disambiguation: class+race+gender if race available, class+gender otherwise.
    -- STRICT RULE: every same-class+matching-race candidate must have
    -- non-nil/non-secret stored gender, otherwise we'd be picking the only
    -- candidate WITH gender data by default — that's a guess (the others
    -- might be the unit, we just couldn't compare). Skip when data sparse.
    if hasMultipleCandidates and refinedCandidates and allCandidatesHaveAttr(refinedCandidates, "gender") then
      local okGender, unitGender = pcall(UnitSexBase, unitID)
      -- `unitGender ~= nil` (NOT `> 0`): UnitSexBase returns the modern
      -- UnitSex enum where 0 = Male, 1 = Female, 2 = None, ... A `> 0`
      -- guard would silently exclude Male players. The legacy UnitSex
      -- (not Base) used 1 = unknown / 2 = male / 3 = female where `> 0`
      -- was meaningless and `> 1` was the correct "exclude unknown" check.
      if okGender and unitGender ~= nil then
        local match = nil
        local count = 0
        for i = 1, #list do
          local button = list[i]
          if buttonClassMatches(button) and safeEq(button.PlayerDetails.gender, unitGender) then
            local dominated = true
            if unitRace then
              dominated = softEq(button.PlayerDetails.PlayerRace, unitRace)
            end
            if dominated then
              count = count + 1
              match = button
              if count > 1 then
                break
              end
            end
          end
        end
        if count == 1 and match then
          recordCycleMatch(match)
          recordStickyMatch(match, unitClassID)
          -- captureLiveAttrs deliberately omitted: tier 7+ relies on
          -- stored attrs that may have been seeded from an earlier wrong
          -- match. If the unique-match here is wrong, capturing would
          -- poison the button with another player's live attrs. Only
          -- tier 5 (sole same-class candidate), tier 6 (authoritative
          -- scoreboard race uniquely identifies), and the arena fast-path
          -- are safe enough to capture from.
          -- _logTierMatch(match, "tier-7-gender")
          return match
        end
      end
    end

    -- Honor level disambiguation: class + race/gender/honor when available.
    -- unitHonor > 0 guard: UnitHonorLevel can return 0 transiently when the
    -- unit's data isn't fully ready. 0 is truthy in Lua so the bare check
    -- lets the tier run with useless input; filter it out so we fall
    -- through cleanly to the guild tier instead of silently matching nothing.
    -- STRICT RULE: every same-class candidate must have stored honor.
    if hasMultipleCandidates and refinedCandidates and allCandidatesHaveAttr(refinedCandidates, "honorLevel") then
      local okHonor, unitHonor = pcall(UnitHonorLevel, unitID)
      if okHonor and unitHonor and unitHonor > 0 then
        local okGender, unitGender = pcall(UnitSexBase, unitID)
        local firstMatch = nil
        local count = 0
        for i = 1, #list do
          local button = list[i]
          if buttonClassMatches(button) and safeEq(button.PlayerDetails.honorLevel, unitHonor) then
            local dominated = true
            if dominated and unitRace then
              dominated = softEq(button.PlayerDetails.PlayerRace, unitRace)
            end
            if dominated and okGender and unitGender ~= nil then
              dominated = softEq(button.PlayerDetails.gender, unitGender)
            end
            if dominated then
              count = count + 1
              if not firstMatch then
                firstMatch = button
              end
              if count > 1 then
                break
              end
            end
          end
        end
        if count == 1 and firstMatch then
          recordCycleMatch(firstMatch)
          recordStickyMatch(firstMatch, unitClassID)
          -- captureLiveAttrs omitted: see tier-7 comment above.
          -- _logTierMatch(firstMatch, "tier-8-honor")
          return firstMatch
        end
      end
    end

    -- Power-type disambiguation: class + race/gender/honor/powerType.
    -- For hybrid classes (DH, Shaman, Priest, Monk, Druid) different specs
    -- often use different primary power types — UnitPowerType returns are
    -- non-secret on hostile units, so we can compare live read against
    -- a stored lastPowerType captured by captureLiveAttrs (or seeded from
    -- harvest). Caveat: shapeshift forms (Druid) cause the live value to
    -- drift mid-match. We do NOT gate on class — the tier just won't
    -- unique-match in that tick and falls through to the guild tier.
    -- Misroute risk: druid A in caster (Mana) vs druid B (lastPowerType=Mana)
    -- — captureLiveAttrs refreshes on every successful resolve, so the
    -- staleness window is bounded.
    -- STRICT RULE: every same-class candidate must have stored lastPowerType.
    if hasMultipleCandidates and refinedCandidates and allCandidatesHaveAttr(refinedCandidates, "lastPowerType") then
      -- pcall: UnitPowerType errors on compound tokens, doesn't return nil.
      local okPower, unitPowerType = pcall(UnitPowerType, unitID)
      if okPower and unitPowerType then
        local okGender, unitGender = pcall(UnitSexBase, unitID)
        local okHonor, unitHonor = pcall(UnitHonorLevel, unitID)
        local match = nil
        local count = 0
        for i = 1, #list do
          local button = list[i]
          if buttonClassMatches(button) and safeEq(button.PlayerDetails.lastPowerType, unitPowerType) then
            local dominated = true
            if dominated and unitRace then
              dominated = softEq(button.PlayerDetails.PlayerRace, unitRace)
            end
            if dominated and okGender and unitGender ~= nil then
              dominated = softEq(button.PlayerDetails.gender, unitGender)
            end
            if dominated and okHonor and unitHonor and unitHonor > 0 then
              dominated = softEq(button.PlayerDetails.honorLevel, unitHonor)
            end
            if dominated then
              count = count + 1
              match = button
              if count > 1 then
                break
              end
            end
          end
        end
        if count == 1 and match then
          recordCycleMatch(match)
          recordStickyMatch(match, unitClassID)
          -- captureLiveAttrs omitted: see tier-7 comment above.
          -- _logTierMatch(match, "tier-8.5-power")
          return match
        end
      end
    end

    -- Guild disambiguation: class + race/gender/honor/guild when available.
    -- STRICT RULE: every same-class candidate must have stored guild data
    -- (either a real guild name string OR `false` = confirmed guildless).
    -- nil stored = unknown → tier doesn't fire.
    --
    -- Live unit guild also uses the three-state model:
    --   GetGuildInfo returns string → unit is in that guild
    --   GetGuildInfo returns nil + UnitSexBase returns a value → unit
    --     is readable, the nil guild means CONFIRMED guildless → use false
    --   GetGuildInfo returns nil + UnitSexBase returns nil → can't read
    --     unit at all, treat as unknown → skip tier
    if hasMultipleCandidates and refinedCandidates and allCandidatesHaveAttr(refinedCandidates, "GuildName") then
      local okGuild, unitGuild = pcall(GetGuildInfo, unitID)
      if not okGuild then
        unitGuild = nil
      elseif unitGuild and issecretvalue and issecretvalue(unitGuild) then
        unitGuild = nil -- secret = unusable
      end
      -- Detect "confirmed guildless" on the live unit side (same heuristic
      -- as captureLiveAttrs): if guild read returned nil but unit IS
      -- readable per UnitSexBase, the nil is a real "no guild" answer.
      if unitGuild == nil then
        local sexProbe = UnitSexBase(unitID)
        if sexProbe then
          unitGuild = false
        end
      end
      -- Tier 9 only fires if we have ANY guild signal for the unit
      -- (string or false). nil = unknown unit guild → skip.
      if unitGuild ~= nil then
        local okGender, unitGender = pcall(UnitSexBase, unitID)
        local okHonor, unitHonor = pcall(UnitHonorLevel, unitID)
        local match = nil
        local count = 0
        for i = 1, #list do
          local button = list[i]
          if buttonClassMatches(button) and guildCmp(button.PlayerDetails.GuildName, unitGuild) == true then
            local dominated = true
            if dominated and unitRace then
              dominated = softEq(button.PlayerDetails.PlayerRace, unitRace)
            end
            if dominated and okGender and unitGender ~= nil then
              dominated = softEq(button.PlayerDetails.gender, unitGender)
            end
            if dominated and okHonor and unitHonor then
              dominated = softEq(button.PlayerDetails.honorLevel, unitHonor)
            end
            if dominated then
              count = count + 1
              match = button
              if count > 1 then
                break
              end
            end
          end
        end
        if count == 1 and match then
          recordCycleMatch(match)
          recordStickyMatch(match, unitClassID)
          -- captureLiveAttrs omitted: see tier-7 comment above.
          -- _logTierMatch(match, "tier-9-guild")
          return match
        end
      end
    end

    -- Fallback: all disambiguation tiers exhausted, return first class match.
    -- This may attach to the wrong same-class button, but "sometimes wrong
    -- button" is better than "nothing gets wired up at all" — without the
    -- fallback, nameplate/target/etc. linkage fails entirely when no live
    -- disambiguator (gender/honor/guild) has been captured yet.
    -- IMPORTANT: do NOT call captureLiveAttrs on a fallback match. Stamping
    -- gender/honor/unitNameOnly from the live token onto a guessed button
    -- would permanently pollute that button with another player's data.
    --
    -- Ambiguity diag. Fires when:
    --   1) user clicked a frame (unitID="target"), OR
    --   2) orb/flag-carrier code is trying to match an arena token
    --      (ignoreExistingArena=true — set by GetOrbCarrierButton and
    --      GetFlagCarrierButton in Modules/ObjectiveAndRespawn.lua)
    -- and we reached fallback because tiers 5-9 + power couldn't unique-match.
    -- Shows which candidates collide and on which attributes — only attrs
    -- that ALL candidates share with non-nil equal values are listed;
    -- missing/nil/secret values are omitted entirely. No throttle, no
    -- debug-flag gate.
    -- if (unitID == "target" or ignoreExistingArena) and hasMultipleCandidates then
    --   -- local candidates = {}
    --   -- for i = 1, #list do
    --   --   local b = list[i]
    --   --   if buttonClassMatches(b) then
    --   --     candidates[#candidates + 1] = b
    --   --   end
    --   -- end
    --   -- if #candidates >= 2 then
    --   --   -- local POWER_TYPE_NAMES = {
    --   --   --   [0] = "Mana",
    --   --   --   [1] = "Rage",
    --   --   --   [2] = "Focus",
    --   --   --   [3] = "Energy",
    --   --   --   [6] = "Runic Power",
    --   --   --   [8] = "Lunar Power",
    --   --   --   [11] = "Maelstrom",
    --   --   --   [13] = "Insanity",
    --   --   --   [17] = "Fury",
    --   --   --   [18] = "Pain",
    --   --   --   [19] = "Essence",
    --   --   -- }
    --   --   -- Returns shared value if all candidates have same non-nil non-secret
    --   --   -- value for the given PlayerDetails key, else nil.
    --   --   -- local function sharedAttr(field)
    --   --   --   local first
    --   --   --   for i = 1, #candidates do
    --   --   --     local pd = candidates[i].PlayerDetails
    --   --   --     local v = pd and pd[field]
    --   --   --     if v == nil or (issecretvalue and issecretvalue(v)) then
    --   --   --       return nil
    --   --   --     end
    --   --   --     if i == 1 then
    --   --   --       first = v
    --   --   --     elseif v ~= first then
    --   --   --       return nil
    --   --   --     end
    --   --   --   end
    --   --   --   return first
    --   --   -- end
    --   --   -- Per-candidate "Name (Race)" — race is non-secret, always show it
    --   --   -- so the user can see when 2+ candidates share a race vs. when the
    --   --   -- candidate set is split (which is why the race tier failed to
    --   --   -- unique-match).
    --   --   -- local names = {}
    --   --   -- for i = 1, #candidates do
    --   --   --   local pd = candidates[i].PlayerDetails
    --   --   --   local nm = (pd and pd.PlayerName) or "<unnamed>"
    --   --   --   local race = (pd and pd.PlayerRace) or "<unknown race>"
    --   --   --   names[i] = string.format("%s (%s)", nm, race)
    --   --   -- end
    --   --   -- local firstPd = candidates[1].PlayerDetails
    --   --   -- local parts = {
    --   --   --   string.format("class (%s)", tostring(firstPd and firstPd.PlayerClass)),
    --   --   -- }
    --   --   -- -- race is shown inline next to each name above, no need to repeat
    --   --   -- -- it in the "same X" list.
    --   --   -- local sharedGender = sharedAttr("gender")
    --   --   -- if sharedGender then
    --   --   --   parts[#parts + 1] = string.format("gender (%s)", tostring(sharedGender))
    --   --   -- end
    --   --   -- local sharedHonor = sharedAttr("honorLevel")
    --   --   -- if sharedHonor then
    --   --   --   parts[#parts + 1] = string.format("honor level (%s)", tostring(sharedHonor))
    --   --   -- end
    --   --   -- local sharedPower = sharedAttr("lastPowerType")
    --   --   -- if sharedPower then
    --   --   --   local pname = POWER_TYPE_NAMES[sharedPower] or tostring(sharedPower)
    --   --   --   parts[#parts + 1] = string.format("power type (%s)", pname)
    --   --   -- end
    --   --   -- local sharedGuild = sharedAttr("GuildName")
    --   --   -- if sharedGuild then
    --   --   --   parts[#parts + 1] = string.format("guild (%s)", sharedGuild)
    --   --   -- end
    --   --   -- local trigger = ignoreExistingArena and unitID or "target"

    --   --   -- Live unit reads at the moment of mismatch — exposes which live
    --   --   -- attrs the disambiguation tiers actually had to work with. If a
    --   --   -- field shows nil here, that tier silently skipped (e.g., race=nil
    --   --   -- means tier 6 couldn't fire even when candidates have distinct
    --   --   -- races stored). Power-type token shown as name when known.
    --   --   -- local POWER_TYPE_NAMES = {
    --   --   --   [0] = "Mana",
    --   --   --   [1] = "Rage",
    --   --   --   [2] = "Focus",
    --   --   --   [3] = "Energy",
    --   --   --   [6] = "Runic Power",
    --   --   --   [8] = "Lunar Power",
    --   --   --   [11] = "Maelstrom",
    --   --   --   [13] = "Insanity",
    --   --   --   [17] = "Fury",
    --   --   --   [18] = "Pain",
    --   --   --   [19] = "Essence",
    --   --   -- }
    --   --   -- local function fmt(v)
    --   --   --   if v == nil then
    --   --   --     return "nil"
    --   --   --   end
    --   --   --   if issecretvalue and issecretvalue(v) then
    --   --   --     return "<secret>"
    --   --   --   end
    --   --   --   return tostring(v)
    --   --   -- end
    --   --   -- local _, uRace = pcall(UnitRace, unitID)
    --   --   -- local _, uGender = pcall(UnitSexBase, unitID)
    --   --   -- local _, uHonor = pcall(UnitHonorLevel, unitID)
    --   --   -- local okPow, uPower = pcall(UnitPowerType, unitID)
    --   --   -- local powerStr = "nil"
    --   --   -- if okPow and uPower then
    --   --   --   powerStr = POWER_TYPE_NAMES[uPower] or tostring(uPower)
    --   --   -- end
    --   --   -- local _, uGuild = pcall(GetGuildInfo, unitID)
    --   --   -- local unitRead = string.format(
    --   --   --   "race=%s gender=%s honor=%s power=%s guild=%s",
    --   --   --   fmt(uRace), fmt(uGender), fmt(uHonor), powerStr, fmt(uGuild)
    --   --   -- )

    --   --   -- Per-candidate stored attrs — appended after unit read, separated
    --   --   -- by <<<>>> so the whole diag stays on one line. Lets us tell apart
    --   --   -- "genuine collision (all candidates have same stored values)"
    --   --   -- from "candidates not yet populated by captureLiveAttrs".
    --   --   -- local candidateBlocks = {}
    --   --   -- for i = 1, #candidates do
    --   --   --   local pd = candidates[i].PlayerDetails or {}
    --   --   --   local nm = pd.PlayerName or "<unnamed>"
    --   --   --   local cgPower = "nil"
    --   --   --   if pd.lastPowerType then
    --   --   --     cgPower = POWER_TYPE_NAMES[pd.lastPowerType] or tostring(pd.lastPowerType)
    --   --   --   end
    --   --   --   candidateBlocks[i] = string.format(
    --   --   --     "%s: gender=%s honor=%s power=%s guild=%s",
    --   --   --     nm,
    --   --   --     fmt(pd.gender),
    --   --   --     fmt(pd.honorLevel),
    --   --   --     cgPower,
    --   --   --     fmt(pd.GuildName)
    --   --   --   )
    --   --   -- end

    --   --   -- De-dupe: skip if this exact same mismatch (same names + same
    --   --   -- unit reads + same candidate stored attrs) was already logged
    --   --   -- for this unitID. Without this, every matcher call (ScanTargets,
    --   --   -- UNIT_TARGET, PLAYER_TARGET_CHANGED_Deferred — multiple per
    --   --   -- second) re-fires the diag for the same unresolvable case.
    --   --   -- local mismatchSignature = table.concat(names, ",")
    --   --   --   .. "|"
    --   --   --   .. unitRead
    --   --   --   .. "|"
    --   --   --   .. table.concat(candidateBlocks, "|")
    --   --   -- if _lastLoggedMismatch[unitID] == mismatchSignature then
    --   --   --   return nil
    --   --   -- end
    --   --   -- _lastLoggedMismatch[unitID] = mismatchSignature

    --   --   -- Version-tag the prefix so logs are unambiguous about which build
    --   --   -- emitted them. Extract the trailing segment of the toc Version
    --   --   -- ("12.0.5.27" → "v27"); falls back to "v?" if the lookup fails.
    --   --   -- local _GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or _G.GetAddOnMetadata
    --   --   -- local _ver = _GetAddOnMetadata and _GetAddOnMetadata("BattleGroundEnemiesFixed", "Version")
    --   --   -- local _verTag = "v?"
    --   --   -- if type(_ver) == "string" then
    --   --   --   local trailing = _ver:match("(%d+)$")
    --   --   --   if trailing then
    --   --   --     _verTag = "v" .. trailing
    --   --   --   end
    --   --   -- end
    --   --   -- Diagnostic: re-enable to debug a future ambiguous-twin fallback.
    --   --   -- print(
    --   --   --   string.format(
    --   --   --     "|cffff8800[BGEF %s - mismatch - %s]|r %s — all have same %s; unit read: %s <<<>>> %s",
    --   --   --     _verTag,
    --   --   --     trigger,
    --   --   --     table.concat(names, ", "),
    --   --   --     table.concat(parts, ", "),
    --   --   --     unitRead,
    --   --   --     table.concat(candidateBlocks, " <<<>>> ")
    --   --   --   )
    --   --   -- )
    --   -- end
    -- end

    -- Arena-peer disambiguation: if a same-class candidate has an arena token,
    -- try UnitIsUnit(unitID, arenaN) to decide. This works for simple tokens
    -- (target, focus, mouseover, arena↔arena). For nameplate and compound
    -- tokens (raidNtarget, etc.) UnitIsUnit returns nil even when equal
    -- (12.0.5 PvP lockdown, diagnosed in-game) — so we can't prove the unit
    -- ISN'T the arena peer, and fallback-picking the non-arena peer would
    -- misroute the carrier's health to the duplicate's frame. In that
    -- unresolvable case, refuse to match.
    if hasMultipleCandidates then
      local arenaPeers
      for i = 1, #list do
        local button = list[i]
        if buttonClassMatches(button) and button.UnitIDs and button.UnitIDs.Arena then
          arenaPeers = arenaPeers or {}
          arenaPeers[#arenaPeers + 1] = button
        end
      end

      if arenaPeers then
        local disambiguated = false
        for _, peer in ipairs(arenaPeers) do
          local arenaToken = peer.UnitIDs.Arena
          local ok, same = pcall(UnitIsUnit, unitID, arenaToken)
          -- Same secret-boolean hazard as the cross-identity loop above.
          -- Pre-filter via issecretvalue before any boolean test on `same`.
          local sameIsSecret = issecretvalue and issecretvalue(same)
          if ok and not sameIsSecret and same then
            -- Positive match — this unit IS the arena peer.
            recordCycleMatch(peer)
            -- captureLiveAttrs deliberately omitted: same hazard as
            -- arena-cross-identity above. UnitIsUnit can return secret
            -- bools in 12.0.5 PvP. Don't poison stored attrs from a
            -- match that may itself be wrong.
            -- _logTierMatch(peer, "arena-peer-elimination")
            return peer
          end
          if ok and not sameIsSecret and same == false then
            -- Clean negative: UnitIsUnit fired and returned non-secret false.
            -- The unit is definitively not this arena peer. Safe to eliminate.
            disambiguated = true
          end
          -- ok && same==nil, ok && secret, or !ok → API blocked/restricted for
          -- this token pair; can't eliminate this peer. Leaves `disambiguated`
          -- at its current value.
        end

        if not disambiguated then
          -- No arena peer could be ruled out via UnitIsUnit, and none matched.
          -- Can't tell if unit is one of the arena peers or the non-arena peer.
          -- Refuse rather than misroute.
          return nil
        end
        -- Fall through: all arena peers definitively ruled out, match a
        -- non-arena same-class candidate.
      end

      -- Fallback-first-class loop REMOVED — was a low-confidence guess
      -- that picked the first same-class candidate when no tier could
      -- uniquely resolve. Per the strict-rule design: if no tier produced
      -- a unique match, return nil instead of guessing. Trade-off:
      -- ambiguous twins get empty frames (no health/power updates) until
      -- one of them ends up on an arena token, dies, or harvest data
      -- accumulates enough to enable tier 7-9 strict comparisons.
      -- Better than wrong-frame attaches.
    end

    return nil
  end
end

-- ============================================================================
-- DIAGNOSTIC: same-class-twin health-misroute hunt (2026-05-01)
--   Prints ONLY when the matcher attaches a unit token to a button whose
--   recorded PlayerName differs from the unit's live name. That's the exact
--   wrong-twin event we're trying to catch. Throttled to once per
--   (token,button) pair per 2s. Remove this block once the root cause is
--   identified and fixed.
-- ============================================================================
-- do
--   local _origMatcher = BattleGroundEnemies.GetPlayerbuttonByUnitID
--   local _seenAt = {}
--   function BattleGroundEnemies:GetPlayerbuttonByUnitID(unitID, playerType, ignoreExistingArena)
--     local btn = _origMatcher(self, unitID, playerType, ignoreExistingArena)
--     if btn and unitID then
--       local okName, liveName = pcall(GetUnitName, unitID, true)
--       if okName and liveName and not (issecretvalue and issecretvalue(liveName)) then
--         local btnName = btn.PlayerDetails and btn.PlayerDetails.PlayerName
--         -- btnName is canonical "Name-Realm" (post-CanonicalName refactor).
--         -- liveName from GetUnitName(unit, true) is short for same-realm —
--         -- canonicalize it before comparing or this fires for every
--         -- same-realm enemy on a correct match (false positive).
--         local liveCanonical = self:CanonicalName(liveName)
--         if btnName and not (issecretvalue and issecretvalue(btnName)) and liveCanonical ~= btnName then
--           local key = tostring(unitID) .. ">" .. tostring(btnName)
--           local now = GetTime()
--           if not _seenAt[key] or now - _seenAt[key] > 2 then
--             _seenAt[key] = now
--             -- Diagnostic: re-enable to debug a future wrong-twin matcher
--             -- mismatch. Only fires when stored name vs live name differ.
--             -- print(string.format(
--             --   "|cffff5555[BGE diag]|r matcher mismatch: token=%s -> button[%s] but unit name = %s",
--             --   tostring(unitID), tostring(btnName), tostring(liveName)
--             -- ))
--           end
--         end
--       end
--     end
--     return btn
--   end
-- end

-- Pre-built unit ID tables to avoid string concatenation every scan cycle
local arenaUnits = {}
for i = 1, 5 do
  arenaUnits[i] = "arena" .. i
end

local nameplateUnits = {}
for i = 1, 40 do
  nameplateUnits[i] = "nameplate" .. i
end

local nameplateTargetUnits = {}
for i = 1, 40 do
  nameplateTargetUnits[i] = "nameplate" .. i .. "target"
end

local raidTargetUnits = {}
for i = 1, 40 do
  raidTargetUnits[i] = "raid" .. i .. "target"
end

local partyTargetUnits = {}
for i = 1, 5 do
  partyTargetUnits[i] = "party" .. i .. "target"
end

local arenaTargetUnits = {}
for i = 1, 5 do
  arenaTargetUnits[i] = "arena" .. i .. "target"
end

local raidPetTargetUnits = {}
for i = 1, 40 do
  raidPetTargetUnits[i] = "raidpet" .. i .. "target"
end

local partyPetTargetUnits = {}
for i = 1, 5 do
  partyPetTargetUnits[i] = "partypet" .. i .. "target"
end

-- Secret-safe "Name-Realm" builders, lifted out of the per-call
-- pcall(function() ... end) closures that used to live inline in ScanTargets
-- (4 sites) and UNIT_TARGET (1 site). Those closures were allocated fresh on
-- every nameplate-target / raid-target iteration and every UNIT_TARGET event
-- — a real per-frame allocation source in dense combat (ScanTargets measured
-- at +500K/fight). Defined here (above ScanTargets) so both call families see
-- them. Each returns nil when a field is secret (bailing exactly as the old
-- inline closures did); callers still pcall-wrap in case comparing a secret
-- value taints. Behaviour is identical to the previous inline closures.
local function buildTargetNameNonSecret(name, server)
  if issecretvalue and (issecretvalue(name) or (server and issecretvalue(server))) then
    return nil
  end
  if server and server ~= "" then
    return name .. "-" .. server
  else
    return name
  end
end

local function buildTargetNameNonSecretNoRealm(name)
  if issecretvalue and issecretvalue(name) then
    return nil
  end
  return name
end

function BattleGroundEnemies:ScanTargets()
  if not self.states.userIsAlive then
    return
  end

  -- Periodic scan for ally targets (raid1target, etc.), arena units, and nameplates.
  -- Pulls health/power/CC data for units that don't push events to us.
  --
  -- Range checking is done for ALL unit types here, matching the working v12.0.0.2.
  -- UnitInRange + CheckInteractDistance handles indirect refs (raidXtarget etc.) fine.

  self:ClearScanCycleCache()

  -- Scan allies' targets (raidXtarget / partyXtarget)
  -- Faction check required: raidXtarget could resolve to a friendly unit
  -- (e.g. healer targeting friendly mage) which would PID-match to the enemy mage button.
  -- Persist GroupTarget tokens to fill gaps when UNIT_TARGET event missed in combat.
  self.Enemies.UnitTargets = self.Enemies.UnitTargets or {}
  if IsInRaid() then
    local numMembers = GetNumGroupMembers()
    for i = 1, numMembers do
      local targetUnitID = raidTargetUnits[i]
      local sourceUnit = "raid" .. i
      if targetUnitID and UnitExists(targetUnitID) and IsEnemyUnit(targetUnitID) then
        local btn = self:GetPlayerbuttonByUnitID(targetUnitID, "Enemies")
        local oldButton = self.Enemies.UnitTargets[sourceUnit]

        if oldButton and oldButton ~= btn then
          self.Enemies:RemoveGroupTarget(oldButton, sourceUnit)
        end

        if btn then
          self.Enemies:AddGroupTarget(btn, sourceUnit, targetUnitID)
          self.Enemies.UnitTargets[sourceUnit] = btn
          btn:UNIT_HEALTH(targetUnitID)
          btn:UNIT_POWER_FREQUENT(targetUnitID)
          btn:UpdateRangeViaLibRangeCheck(targetUnitID)
        else
          self.Enemies.UnitTargets[sourceUnit] = nil
        end
      else
        local oldButton = self.Enemies.UnitTargets[sourceUnit]
        if oldButton then
          self.Enemies:RemoveGroupTarget(oldButton, sourceUnit)
          self.Enemies.UnitTargets[sourceUnit] = nil
        end
      end
    end
  elseif IsInGroup() then
    local numMembers = GetNumGroupMembers() - 1
    for i = 1, numMembers do
      local targetUnitID = partyTargetUnits[i]
      local sourceUnit = "party" .. i
      if targetUnitID and UnitExists(targetUnitID) and IsEnemyUnit(targetUnitID) then
        local btn = self:GetPlayerbuttonByUnitID(targetUnitID, "Enemies")
        local oldButton = self.Enemies.UnitTargets[sourceUnit]

        if oldButton and oldButton ~= btn then
          self.Enemies:RemoveGroupTarget(oldButton, sourceUnit)
        end

        if btn then
          self.Enemies:AddGroupTarget(btn, sourceUnit, targetUnitID)
          self.Enemies.UnitTargets[sourceUnit] = btn
          btn:UNIT_HEALTH(targetUnitID)
          btn:UNIT_POWER_FREQUENT(targetUnitID)
          btn:UpdateRangeViaLibRangeCheck(targetUnitID)
        else
          self.Enemies.UnitTargets[sourceUnit] = nil
        end
      else
        local oldButton = self.Enemies.UnitTargets[sourceUnit]
        if oldButton then
          self.Enemies:RemoveGroupTarget(oldButton, sourceUnit)
          self.Enemies.UnitTargets[sourceUnit] = nil
        end
      end
    end
  end

  -- Scan arena units (direct refs — exist in arena AND objective BGs like flags/orbs)
  for i = 1, 5 do
    local unitID = arenaUnits[i]
    if UnitExists(unitID) then
      local btn = self:GetPlayerbuttonByUnitID(unitID, "Enemies")
      if btn then
        btn:UNIT_HEALTH(unitID)
        btn:UNIT_POWER_FREQUENT(unitID)
        btn:UpdateRangeViaLibRangeCheck(unitID)
        if btn.SpecClassPriority then
          btn.SpecClassPriority:UpdateLossOfControl(unitID)
        end
      end
    end
  end

  -- Scan nameplates (enemy only)
  local maxNameplate = self.maxNameplateIndex or 40
  for i = 1, maxNameplate do
    local unitID = nameplateUnits[i]
    if UnitExists(unitID) and IsEnemyUnit(unitID) then
      local btn = self:GetPlayerbuttonByUnitID(unitID, "Enemies")
      if btn then
        -- Persist the Nameplate token if not already assigned to this button.
        -- Catches tokens that NAME_PLATE_UNIT_ADDED missed (combat PID failure).
        if btn.UnitIDs and btn.UnitIDs.Nameplate ~= unitID then
          -- Clean up any other button that had this nameplate token
          if self.Enemies and self.Enemies.Players then
            for _, otherBtn in pairs(self.Enemies.Players) do
              if otherBtn ~= btn and otherBtn.UnitIDs and otherBtn.UnitIDs.Nameplate == unitID then
                otherBtn:UpdateEnemyUnitID("Nameplate", false)
                break
              end
            end
          end
          btn:UpdateEnemyUnitID("Nameplate", unitID)
        end
        btn:UNIT_HEALTH(unitID)
        btn:UNIT_POWER_FREQUENT(unitID)
        btn:UpdateRangeViaLibRangeCheck(unitID)
        if btn.SpecClassPriority then
          btn.SpecClassPriority:UpdateLossOfControl(unitID)
        end
      end
    end
  end

  -- Scan nameplate targets (what visible enemies are targeting)
  self.Enemies.NameplateTargets = self.Enemies.NameplateTargets or {}
  self.Allies.NameplateTargets = self.Allies.NameplateTargets or {}

  for i = 1, maxNameplate do
    local sourceUnit = nameplateUnits[i]
    local targetUnitID = nameplateTargetUnits[i]

    -- Track enemy nameplates targeting other enemies
    if UnitExists(targetUnitID) and IsEnemyUnit(targetUnitID) then
      local btn = self:GetPlayerbuttonByUnitID(targetUnitID, "Enemies")
      local oldButton = self.Enemies.NameplateTargets[sourceUnit]

      if oldButton and oldButton ~= btn then
        self.Enemies:RemoveNameplateTarget(oldButton, sourceUnit)
      end

      if btn then
        btn:UNIT_HEALTH(targetUnitID)
        btn:UNIT_POWER_FREQUENT(targetUnitID)
        btn:UpdateRangeViaLibRangeCheck(targetUnitID)
        self.Enemies:AddNameplateTarget(btn, sourceUnit, targetUnitID)
        self.Enemies.NameplateTargets[sourceUnit] = btn
      else
        self.Enemies.NameplateTargets[sourceUnit] = nil
      end

      -- Track enemy nameplates targeting allies (for ally target indicators)
    elseif UnitExists(targetUnitID) and UnitIsFriend("player", targetUnitID) then
      -- Get the enemy button for the nameplate doing the targeting
      local enemyBtn = self:GetPlayerbuttonByUnitID(sourceUnit, "Enemies")

      -- Get the ally button being targeted
      -- Use pcall to protect against taint from nameplate/arena targets
      -- Try with realm first
      local ok, name, server = pcall(GetUnitName, targetUnitID, true)
      local targetName = nil
      if ok and name then
        local ok2, computed = pcall(buildTargetNameNonSecret, name, server)
        if ok2 then
          targetName = computed
        else
          targetName = nil
        end
      end

      local allyBtn = targetName and self.Allies.Players and self:SafeGetPlayerButton(self.Allies.Players, targetName)

      if not allyBtn and not targetName then
        -- If first call failed, try without realm
        ok, name, server = pcall(GetUnitName, targetUnitID, false)
        if ok and name then
          local ok2, computed = pcall(buildTargetNameNonSecretNoRealm, name)
          if ok2 then
            targetName = computed
          else
            targetName = nil
          end
        end
        if targetName then
          allyBtn = self:SafeGetPlayerButton(self.Allies.Players, targetName)
        end
      elseif not allyBtn and targetName then
        -- Try stripping realm from sanitized name
        -- Use string.match instead of :match to avoid indexing secret strings
        local ok3, nameOnly = pcall(string.match, targetName, "^([^%-]+)")
        if ok3 and nameOnly then
          allyBtn = self:SafeGetPlayerButton(self.Allies.Players, nameOnly)
        end
      end

      local oldAllyButton = self.Allies.NameplateTargets[sourceUnit]
      if oldAllyButton then
        -- Get the old enemy button to remove
        local oldEnemyBtn = self.Allies.NameplateTargetMap and self.Allies.NameplateTargetMap[oldAllyButton]
        if oldEnemyBtn and type(oldEnemyBtn) == "table" then
          for oldEnemy in pairs(oldEnemyBtn) do
            if oldEnemy ~= enemyBtn then
              self.Allies:RemoveNameplateTarget(oldAllyButton, oldEnemy)
            end
          end
        end
      end

      if allyBtn and enemyBtn then
        -- Pass the enemy button (not the sourceUnit string)
        self.Allies:AddNameplateTarget(allyBtn, enemyBtn)
        self.Allies.NameplateTargets[sourceUnit] = allyBtn
      else
        self.Allies.NameplateTargets[sourceUnit] = nil
      end

      -- Clear any enemy→enemy target for this nameplate
      local oldEnemyButton = self.Enemies.NameplateTargets[sourceUnit]
      if oldEnemyButton then
        self.Enemies:RemoveNameplateTarget(oldEnemyButton, sourceUnit)
        self.Enemies.NameplateTargets[sourceUnit] = nil
      end
    else
      -- Clear both if no valid target
      local oldButton = self.Enemies.NameplateTargets[sourceUnit]
      if oldButton then
        self.Enemies:RemoveNameplateTarget(oldButton, sourceUnit)
        self.Enemies.NameplateTargets[sourceUnit] = nil
      end
      local oldAllyButton = self.Allies.NameplateTargets[sourceUnit]
      if oldAllyButton then
        -- Get the enemy button that was targeting this ally
        local enemyBtn = self:GetPlayerbuttonByUnitID(sourceUnit, "Enemies")
        if enemyBtn then
          self.Allies:RemoveNameplateTarget(oldAllyButton, enemyBtn)
        end
        self.Allies.NameplateTargets[sourceUnit] = nil
      end
    end
  end

  -- Scan pettarget (your pet's target — direct reference)
  -- Persist PetTarget token to fill gaps when UNIT_TARGET event missed in combat.
  if UnitExists("pettarget") and IsEnemyUnit("pettarget") then
    local btn = self:GetPlayerbuttonByUnitID("pettarget", "Enemies")
    local oldBtn = self.Enemies.PetTargetButton
    if oldBtn and oldBtn ~= btn then
      oldBtn:UpdateEnemyUnitID("PetTarget", nil)
      self.Enemies.PetTargetButton = nil
    end
    if btn then
      btn:UpdateEnemyUnitID("PetTarget", "pettarget")
      self.Enemies.PetTargetButton = btn
      btn:UNIT_HEALTH("pettarget")
      btn:UNIT_POWER_FREQUENT("pettarget")
      btn:UpdateRangeViaLibRangeCheck("pettarget")
    end
  else
    local oldBtn = self.Enemies.PetTargetButton
    if oldBtn then
      oldBtn:UpdateEnemyUnitID("PetTarget", nil)
      self.Enemies.PetTargetButton = nil
    end
  end

  -- Scan focustarget (your focus's target — indirect)
  -- Persist FocusTarget token to fill gaps when UNIT_TARGET event missed in combat.
  if UnitExists("focustarget") and IsEnemyUnit("focustarget") then
    local btn = self:GetPlayerbuttonByUnitID("focustarget", "Enemies")
    local oldBtn = self.Enemies.FocusTargetButton
    if oldBtn and oldBtn ~= btn then
      oldBtn:UpdateEnemyUnitID("FocusTarget", nil)
      self.Enemies.FocusTargetButton = nil
    end
    if btn then
      btn:UpdateEnemyUnitID("FocusTarget", "focustarget")
      self.Enemies.FocusTargetButton = btn
      btn:UNIT_HEALTH("focustarget")
      btn:UNIT_POWER_FREQUENT("focustarget")
      btn:UpdateRangeViaLibRangeCheck("focustarget")
    end
  else
    local oldBtn = self.Enemies.FocusTargetButton
    if oldBtn then
      oldBtn:UpdateEnemyUnitID("FocusTarget", nil)
      self.Enemies.FocusTargetButton = nil
    end
  end

  -- Scan arena targets (what arena enemies are targeting)
  self.Enemies.ArenaTargets = self.Enemies.ArenaTargets or {}
  self.Allies.ArenaTargets = self.Allies.ArenaTargets or {}

  for i = 1, 5 do
    local sourceUnit = arenaUnits[i]
    local targetUnitID = arenaTargetUnits[i]

    -- Track arena enemies targeting other enemies
    if UnitExists(targetUnitID) and IsEnemyUnit(targetUnitID) then
      local btn = self:GetPlayerbuttonByUnitID(targetUnitID, "Enemies")
      local oldButton = self.Enemies.ArenaTargets[sourceUnit]

      if oldButton and oldButton ~= btn then
        self.Enemies:RemoveArenaTarget(oldButton, sourceUnit)
      end

      if btn then
        btn:UNIT_HEALTH(targetUnitID)
        btn:UNIT_POWER_FREQUENT(targetUnitID)
        btn:UpdateRangeViaLibRangeCheck(targetUnitID)
        self.Enemies:AddArenaTarget(btn, sourceUnit, targetUnitID)
        self.Enemies.ArenaTargets[sourceUnit] = btn
      else
        self.Enemies.ArenaTargets[sourceUnit] = nil
      end

      -- Track arena enemies targeting allies (for ally target indicators)
    elseif UnitExists(targetUnitID) and UnitIsFriend("player", targetUnitID) then
      -- Get the enemy button for the arena unit doing the targeting
      local enemyBtn = self.ArenaIDToPlayerButton[sourceUnit]
      if not enemyBtn then
        enemyBtn = self:GetPlayerbuttonByUnitID(sourceUnit, "Enemies")
      end

      -- Get the ally button being targeted
      -- Use pcall to protect against taint from nameplate/arena targets
      -- Try with realm first
      local ok, name, server = pcall(GetUnitName, targetUnitID, true)
      local targetName = nil
      if ok and name then
        local ok2, computed = pcall(buildTargetNameNonSecret, name, server)
        if ok2 then
          targetName = computed
        else
          targetName = nil
        end
      end

      local allyBtn = targetName and self.Allies.Players and self:SafeGetPlayerButton(self.Allies.Players, targetName)

      if not allyBtn and not targetName then
        -- If first call failed, try without realm
        ok, name, server = pcall(GetUnitName, targetUnitID, false)
        if ok and name then
          local ok2, computed = pcall(buildTargetNameNonSecretNoRealm, name)
          if ok2 then
            targetName = computed
          else
            targetName = nil
          end
        end
        if targetName then
          allyBtn = self:SafeGetPlayerButton(self.Allies.Players, targetName)
        end
      elseif not allyBtn and targetName then
        -- Try stripping realm from sanitized name
        -- Use string.match instead of :match to avoid indexing secret strings
        local ok3, nameOnly = pcall(string.match, targetName, "^([^%-]+)")
        if ok3 and nameOnly then
          allyBtn = self:SafeGetPlayerButton(self.Allies.Players, nameOnly)
        end
      end

      local oldAllyButton = self.Allies.ArenaTargets[sourceUnit]
      if oldAllyButton then
        -- Get the old enemy button to remove
        local oldEnemyBtns = self.Allies.ArenaTargetMap and self.Allies.ArenaTargetMap[oldAllyButton]
        if oldEnemyBtns and type(oldEnemyBtns) == "table" then
          for oldEnemy in pairs(oldEnemyBtns) do
            if oldEnemy ~= enemyBtn then
              self.Allies:RemoveArenaTarget(oldAllyButton, oldEnemy)
            end
          end
        end
      end

      if allyBtn and enemyBtn then
        -- Pass the enemy button (not the sourceUnit string)
        self.Allies:AddArenaTarget(allyBtn, enemyBtn)
        self.Allies.ArenaTargets[sourceUnit] = allyBtn
      else
        self.Allies.ArenaTargets[sourceUnit] = nil
      end

      -- Clear any enemy→enemy target for this arena unit
      local oldEnemyButton = self.Enemies.ArenaTargets[sourceUnit]
      if oldEnemyButton then
        self.Enemies:RemoveArenaTarget(oldEnemyButton, sourceUnit)
        self.Enemies.ArenaTargets[sourceUnit] = nil
      end
    else
      -- Clear both if no valid target
      local oldButton = self.Enemies.ArenaTargets[sourceUnit]
      if oldButton then
        self.Enemies:RemoveArenaTarget(oldButton, sourceUnit)
        self.Enemies.ArenaTargets[sourceUnit] = nil
      end
      local oldAllyButton = self.Allies.ArenaTargets[sourceUnit]
      if oldAllyButton then
        -- Get the enemy button that was targeting this ally
        local enemyBtn = self.ArenaIDToPlayerButton[sourceUnit]
        if not enemyBtn then
          enemyBtn = self:GetPlayerbuttonByUnitID(sourceUnit, "Enemies")
        end
        if enemyBtn then
          self.Allies:RemoveArenaTarget(oldAllyButton, enemyBtn)
        end
        self.Allies.ArenaTargets[sourceUnit] = nil
      end
    end
  end

  -- Scan group pet targets (what allies' pets are targeting)
  self.Enemies.GroupPetTargets = self.Enemies.GroupPetTargets or {}
  if IsInRaid() then
    local numMembers = GetNumGroupMembers()
    for i = 1, numMembers do
      local sourceUnit = "raidpet" .. i
      local targetUnitID = raidPetTargetUnits[i]
      if targetUnitID and UnitExists(targetUnitID) and IsEnemyUnit(targetUnitID) then
        local btn = self:GetPlayerbuttonByUnitID(targetUnitID, "Enemies")
        local oldButton = self.Enemies.GroupPetTargets[sourceUnit]

        if oldButton and oldButton ~= btn then
          self.Enemies:RemoveGroupPetTarget(oldButton, sourceUnit)
        end

        if btn then
          btn:UNIT_HEALTH(targetUnitID)
          btn:UNIT_POWER_FREQUENT(targetUnitID)
          btn:UpdateRangeViaLibRangeCheck(targetUnitID)
          self.Enemies:AddGroupPetTarget(btn, sourceUnit, targetUnitID)
          self.Enemies.GroupPetTargets[sourceUnit] = btn
        else
          self.Enemies.GroupPetTargets[sourceUnit] = nil
        end
      else
        local oldButton = self.Enemies.GroupPetTargets[sourceUnit]
        if oldButton then
          self.Enemies:RemoveGroupPetTarget(oldButton, sourceUnit)
          self.Enemies.GroupPetTargets[sourceUnit] = nil
        end
      end
    end
  elseif IsInGroup() then
    local numMembers = GetNumGroupMembers() - 1
    for i = 1, numMembers do
      local sourceUnit = "partypet" .. i
      local targetUnitID = partyPetTargetUnits[i]
      if targetUnitID and UnitExists(targetUnitID) and IsEnemyUnit(targetUnitID) then
        local btn = self:GetPlayerbuttonByUnitID(targetUnitID, "Enemies")
        local oldButton = self.Enemies.GroupPetTargets[sourceUnit]

        if oldButton and oldButton ~= btn then
          self.Enemies:RemoveGroupPetTarget(oldButton, sourceUnit)
        end

        if btn then
          btn:UNIT_HEALTH(targetUnitID)
          btn:UNIT_POWER_FREQUENT(targetUnitID)
          btn:UpdateRangeViaLibRangeCheck(targetUnitID)
          self.Enemies:AddGroupPetTarget(btn, sourceUnit, targetUnitID)
          self.Enemies.GroupPetTargets[sourceUnit] = btn
        else
          self.Enemies.GroupPetTargets[sourceUnit] = nil
        end
      else
        local oldButton = self.Enemies.GroupPetTargets[sourceUnit]
        if oldButton then
          self.Enemies:RemoveGroupPetTarget(oldButton, sourceUnit)
          self.Enemies.GroupPetTargets[sourceUnit] = nil
        end
      end
    end
  end
end

function BattleGroundEnemies:StartTargetScanTicker()
  if self.TargetScanTicker then
    self.TargetScanTicker:Cancel()
  end
  self.TargetScanTicker = C_Timer.NewTicker(0.3, function()
    if not self.enabled then
      return
    end
    self:ScanTargets()
  end)
end

function BattleGroundEnemies:StopTargetScanTicker()
  if self.TargetScanTicker then
    self.TargetScanTicker:Cancel()
    self.TargetScanTicker = nil
  end
end

function BattleGroundEnemies:PLAYER_SOFT_ENEMY_CHANGED()
  if not self.states.userIsAlive then
    return
  end
  local btn = self:GetPlayerbuttonByUnitID("softenemy", "Enemies")
  if btn then
    btn:UNIT_HEALTH("softenemy")
    btn:UNIT_POWER_FREQUENT("softenemy")
    btn:UpdateRangeViaLibRangeCheck("softenemy")
  end
end

function BattleGroundEnemies:GetPlayerbuttonByName(name)
  if not name then
    return
  end
  -- Canonicalize input: callers may pass either short "Name" (same-realm)
  -- or full "Name-Realm" (cross-realm or chat-derived). Players[] is
  -- keyed canonically — go through CanonicalName so both inputs converge.
  local key = self:CanonicalName(name)
  return self.Enemies.Players[key] or self.Allies.Players[key]
end

function BattleGroundEnemies:GetPlayerbuttonByGUID(GUID)
  if not self.PlayerGUIDs then
    return nil
  end

  if not GUID then
    return nil
  end

  -- Force taint check on GUID and safely access table
  local ok, guidData = pcall(function()
    return self.PlayerGUIDs[GUID]
  end)

  if not ok or not guidData then
    return nil
  end

  return self:GetPlayerbuttonByName(guidData.name)
end

function BattleGroundEnemies:HandleAllyTargetChanged(newTarget)
  -- Hide previous ally target highlight
  if BattleGroundEnemies.currentAllyTarget then
    BattleGroundEnemies.currentAllyTarget.MyTarget:Hide()
  end

  if newTarget then
    -- Show target highlight on ally button
    newTarget.MyTarget:Show()
    BattleGroundEnemies.currentAllyTarget = newTarget
  else
    BattleGroundEnemies.currentAllyTarget = false
  end
end

function BattleGroundEnemies:HandleAllyFocusChanged(newFocus)
  -- Hide previous ally focus highlight
  if BattleGroundEnemies.currentAllyFocus then
    BattleGroundEnemies.currentAllyFocus.MyFocus:Hide()
  end

  if newFocus then
    -- Show focus highlight on ally button
    newFocus.MyFocus:Show()
    BattleGroundEnemies.currentAllyFocus = newFocus
  else
    BattleGroundEnemies.currentAllyFocus = false
  end
end

function BattleGroundEnemies:HandleTargetChanged(newTarget)
  local targetName = self:SafeGetUnitName("target")

  if BattleGroundEnemies.currentTarget then
    BattleGroundEnemies.currentTarget:UpdateEnemyUnitID("Target", false)

    if self.UserButton then
      self.UserButton:IsNoLongerTarging(BattleGroundEnemies.currentTarget)
    end
    BattleGroundEnemies.currentTarget.MyTarget:Hide()
  end

  if newTarget then --i target an existing player
    if self.UserButton then
      newTarget:UpdateEnemyUnitID("Target", "target")

      self.UserButton:IsNowTargeting(newTarget)
    end
    newTarget.MyTarget:Show()
    BattleGroundEnemies.currentTarget = newTarget

    -- if BattleGroundEnemies.states.real.isRatedBG and self.db.profile.RBG.TargetCalling_SetMark and IamTargetcaller() then -- i am the target caller
    -- 	SetRaidTarget("target", 8)
    -- end
  else
    BattleGroundEnemies.currentTarget = false
  end
end

function BattleGroundEnemies:PLAYER_TARGET_CHANGED()
  -- Defer off the secure execution path to avoid tainting Blizzard UnitFrame.
  --
  -- Debounce: a single click on a player button runs "/cleartarget\n
  -- /targetexact NAME", which fires PLAYER_TARGET_CHANGED TWICE in the
  -- same frame (once for cleartarget, once for targetexact). Without
  -- debouncing, two deferred resolutions run back-to-back: the first
  -- correctly consumes the PostClick stash, but the second sees an
  -- empty stash and falls through to the PID fingerprint resolver,
  -- which can overwrite the highlight with the wrong same-class
  -- button. Cancel any pending resolution so only the LAST event in
  -- the burst lands.
  if self._targetChangeTimer then
    self._targetChangeTimer:Cancel()
  end
  self._targetChangeTimer = C_Timer.NewTimer(0, function()
    self._targetChangeTimer = nil
    self:PLAYER_TARGET_CHANGED_Deferred()
  end)
end

function BattleGroundEnemies:PLAYER_TARGET_CHANGED_Deferred()
  -- Clear stale scan-cycle cache for "target" so we do a fresh lookup
  -- (the previous ScanTargets tick may have cached a different/nil result)
  self:ClearScanCycleCache()
  -- Also invalidate sticky cross-tick cache for "target" — without this, an
  -- earlier (possibly wrong) resolution would be reused and we'd never
  -- re-run the unique-class matcher.
  self:InvalidateStickyPID("target")

  local btn = nil
  local isAlly = false

  -- Structural ally check FIRST — in solo shuffle everyone is the same faction,
  -- so faction-based checks can't distinguish. Unit token identity is reliable:
  -- party*/player = always allies, arena* = always enemies (Blizzard's own approach).
  if UnitExists("target") then
    if UnitIsUnit("target", "player") then
      isAlly = true
    else
      for i = 1, 4 do
        if UnitIsUnit("target", "party" .. i) then
          isAlly = true
          break
        end
      end
    end
    -- In BGs, allies are on raid tokens (raid1-raid40), not party tokens.
    -- UnitIsFriend works correctly in BGs (different factions). Only skip it
    -- in arena where solo shuffle puts everyone on the same faction.
    if not isAlly then
      if self.cachedInstanceType == "pvp" and UnitIsFriend("player", "target") then
        isAlly = true
      end
    end
  end

  if isAlly then
    -- Ally target — look up in Allies.Players by name. Canonicalize each
    -- lookup so the storage key format ("Name-Realm" canonical) matches
    -- regardless of whether GetUnitName returned the short or long form.
    -- Both fallback paths still queried — defensive against any edge case
    -- where the (true)/(false) returns differ in ways canonicalization
    -- doesn't paper over (e.g. one returns nil).
    local targetName = GetUnitName("target", true)
    if
      type(targetName) == "string"
      and not (issecretvalue and issecretvalue(targetName))
      and self.Allies
      and self.Allies.Players
    then
      btn = self.Allies.Players[self:CanonicalName(targetName)]
      if not btn then
        targetName = GetUnitName("target", false)
        if type(targetName) == "string" and not (issecretvalue and issecretvalue(targetName)) then
          btn = self.Allies.Players[self:CanonicalName(targetName)]
        end
      end
    end
  else
    -- Enemy target. The macrotext for Target bindings is
    -- "/cleartarget\n/targetexact NAME", which fires PLAYER_TARGET_CHANGED
    -- TWICE — first with no target (from /cleartarget), then with the
    -- real target (from /targetexact). Only consume the click stash on
    -- the second event (UnitExists("target")). If we consumed on the
    -- first, the second would lose the stash and fall through to PID
    -- fingerprinting — exactly the bug we're trying to avoid.
    if UnitExists("target") then
      local lastClicked = self._lastClickedEnemyTarget
      local lastClickedTime = self._lastClickedEnemyTargetTime or 0
      local stashAge = GetTime() - lastClickedTime
      -- local resolvedVia
      if lastClicked and lastClicked.PlayerDetails and stashAge < 0.5 then
        btn = lastClicked
        -- resolvedVia = string.format("stash (age=%.3fs)", stashAge)
        -- Stash bypass is as authoritative as tier-5/6/arena/name resolves
        -- (the user clicked that exact frame, the secure macro targeted
        -- that exact name, the live "target" unit IS that player). Capture
        -- live attrs onto the button so future tier-7/8/9 strict-rule
        -- comparisons have data — without this, click-only encounters
        -- never populate stored gender/honor/power/guild and same-class
        -- twins stay forever undisambiguated.
        self:CaptureUnitAttrs(btn, "target")
      end
      self._lastClickedEnemyTarget = nil
      self._lastClickedEnemyTargetTime = nil

      -- Arena token mapping next, then PID matching as the last resort.
      if not btn then
        for i = 1, 5 do
          local arenaID = "arena" .. i
          if UnitIsUnit("target", arenaID) then
            btn = self.ArenaIDToPlayerButton[arenaID]
            -- resolvedVia = "arena-token-direct (" .. arenaID .. ")"
            break
          end
        end
      end
      if not btn then
        btn = self:GetPlayerbuttonByUnitID("target", "Enemies")
        -- if btn then
        --   resolvedVia = "matcher"
        -- end
      end

      -- Click-path log: one line per enemy target change. Tells us how
      -- the deferred handler decided which button to attach the target
      -- token to. Pair with the matcher's [BGEF vN - matched] line to
      -- follow the full chain on misroutes.
      -- do
      --   -- local _GAM = C_AddOns and C_AddOns.GetAddOnMetadata or _G.GetAddOnMetadata
      --   -- local _ver = _GAM and _GAM("BattleGroundEnemiesFixed", "Version")
      --   -- local _verTag = "v?"
      --   -- if type(_ver) == "string" then
      --   --   local trailing = _ver:match("(%d+)$")
      --   --   if trailing then
      --   --     _verTag = "v" .. trailing
      --   --   end
      --   -- end
      --   -- local btnName = (btn and btn.PlayerDetails and btn.PlayerDetails.PlayerName) or "<no btn>"
      --   -- local liveName = self:SafeGetUnitName("target") or "<no name>"
      --   -- if issecretvalue and issecretvalue(liveName) then
      --   --   liveName = "<secret>"
      --   -- end
      --   -- Commented out for now — re-enable to debug click-path issues.
      --   -- print(
      --   --   string.format(
      --   --     "|cff44ff44[BGEF %s - target-resolve]|r unit=%s, btn=%s, via=%s",
      --   --     _verTag,
      --   --     tostring(liveName),
      --   --     tostring(btnName),
      --   --     tostring(resolvedVia or "none")
      --   --   )
      --   -- )
      -- end
    end
  end

  -- Clear both highlights, then set the appropriate one
  -- This ensures when clicking away (no target), both are cleared
  if not btn then
    self:HandleTargetChanged(nil)
    self:HandleAllyTargetChanged(nil)
  elseif isAlly then
    self:HandleTargetChanged(nil) -- Clear enemy highlight
    self:HandleAllyTargetChanged(btn)
  else
    self:HandleAllyTargetChanged(nil) -- Clear ally highlight
    self:HandleTargetChanged(btn)
  end
end

function BattleGroundEnemies:HandleFocusChanged(newFocus)
  if BattleGroundEnemies.currentFocus then
    BattleGroundEnemies.currentFocus:UpdateEnemyUnitID("Focus", false)

    BattleGroundEnemies.currentFocus.MyFocus:Hide()
  end
  if newFocus then
    newFocus:UpdateEnemyUnitID("Focus", "focus")

    newFocus.MyFocus:Show()
    BattleGroundEnemies.currentFocus = newFocus
  else
    BattleGroundEnemies.currentFocus = false
  end
end

function BattleGroundEnemies:PLAYER_FOCUS_CHANGED()
  local btn = nil
  local isAlly = false

  -- Structural ally check FIRST — same approach as PLAYER_TARGET_CHANGED.
  -- Unit token identity is reliable in solo shuffle where factions are shared.
  if UnitExists("focus") then
    if UnitIsUnit("focus", "player") then
      isAlly = true
    else
      for i = 1, 4 do
        if UnitIsUnit("focus", "party" .. i) then
          isAlly = true
          break
        end
      end
    end
    -- In BGs, allies are on raid tokens (raid1-raid40), not party tokens.
    -- UnitIsFriend works correctly in BGs (different factions). Only skip it
    -- in arena where solo shuffle puts everyone on the same faction.
    if not isAlly then
      if self.cachedInstanceType == "pvp" and UnitIsFriend("player", "focus") then
        isAlly = true
      end
    end
  end

  if isAlly then
    -- Ally focus — look up in Allies.Players by name. Canonicalize for the
    -- same reason as the ally-target lookup above.
    local focusName = GetUnitName("focus", true)
    if
      type(focusName) == "string"
      and not (issecretvalue and issecretvalue(focusName))
      and self.Allies
      and self.Allies.Players
    then
      btn = self.Allies.Players[self:CanonicalName(focusName)]
      if not btn then
        focusName = GetUnitName("focus", false)
        if type(focusName) == "string" and not (issecretvalue and issecretvalue(focusName)) then
          btn = self.Allies.Players[self:CanonicalName(focusName)]
        end
      end
    end
  else
    -- Enemy focus — same logic as the target-change handler. Only consume
    -- the click stash when there's an actual focus to map (a /clearfocus
    -- variant would otherwise burn the stash on the no-focus event).
    if UnitExists("focus") then
      local lastClicked = self._lastClickedEnemyFocus
      local lastClickedTime = self._lastClickedEnemyFocusTime or 0
      if lastClicked and lastClicked.PlayerDetails and (GetTime() - lastClickedTime) < 0.5 then
        btn = lastClicked
        -- Same authoritative-capture as the target stash bypass above —
        -- user clicked that exact frame, secure macro set focus to that
        -- exact name. Capture live attrs to populate matcher's stored data.
        self:CaptureUnitAttrs(btn, "focus")
      end
      self._lastClickedEnemyFocus = nil
      self._lastClickedEnemyFocusTime = nil

      -- Arena token mapping next, then PID matching as the last resort.
      if not btn then
        for i = 1, 5 do
          local arenaID = "arena" .. i
          if UnitIsUnit("focus", arenaID) then
            btn = self.ArenaIDToPlayerButton[arenaID]
            break
          end
        end
      end
      if not btn then
        btn = self:GetPlayerbuttonByUnitID("focus", "Enemies")
      end
    end
  end

  -- Clear both highlights, then set the appropriate one
  -- This ensures when clearing focus (no focus), both are cleared
  if not btn then
    self:HandleFocusChanged(nil)
    self:HandleAllyFocusChanged(nil)
  elseif isAlly then
    self:HandleFocusChanged(nil) -- Clear enemy highlight
    self:HandleAllyFocusChanged(btn)
  else
    self:HandleAllyFocusChanged(nil) -- Clear ally highlight
    self:HandleFocusChanged(btn)
  end
end

function BattleGroundEnemies:UPDATE_MOUSEOVER_UNIT()
  -- Snapshot read of health/power/auras using the mouseover token.
  -- Sibling handler at BattleGroundEnemies.Enemies:UPDATE_MOUSEOVER_UNIT
  -- in Mainframe.lua handles the persistent Mouseover UnitID attachment.
  -- Both run on the same event; the second matcher call hits scanCycleCache
  -- so cost is a table lookup. Don't consolidate — different abstractions.
  local enemyButton = self.Enemies:GetPlayerbuttonByUnitID("mouseover", "Enemies")
  if enemyButton then --unit is a shown enemy
    enemyButton:UpdateAll("mouseover")
  end
end

function BattleGroundEnemies:RAID_TARGET_UPDATE()
  local containers = { self.Enemies, self.Allies }
  for c = 1, #containers do
    local container = containers[c]
    if container and container.Players then
      for _, playerButton in pairs(container.Players) do
        playerButton:UpdateRaidTargetIcon()
      end
    end
  end
end

-- Helper to check if current map is an objective BG (flags/orbs)
-- In these BGs, arena tokens are only assigned to objective carriers.
-- IDs below are UI *map* IDs (C_Map.GetBestMapForUnit), NOT instance IDs.
-- 417=Kotmogu, 1339=Warsong Gulch, 206=Twin Peaks, 112=Eye of the Storm,
-- 397=Eye of the Storm Rated, 2345=Deephaul Ravine.
local function IsObjectiveBG(mapId)
  return mapId == 417 or mapId == 206 or mapId == 1339 or mapId == 112 or mapId == 397 or mapId == 2345
end

function BattleGroundEnemies:LOSS_OF_CONTROL_ADDED(unitID, effectIndex)
  local playerButton = nil
  local isArenaUnit = unitID and unitID:match("^arena%d")

  -- Check ArenaIDToPlayerButton first for arena units (same fix as target/focus)
  if isArenaUnit then
    playerButton = self.ArenaIDToPlayerButton[unitID]
  end

  -- Fall back to PID matching - but NOT in objective BGs for arena units
  -- In objective BGs, arena tokens are only assigned to flag/orb carriers, so if not in
  -- ArenaIDToPlayerButton, this player doesn't have an objective and shouldn't get trinket updates
  if not playerButton then
    local states = self:GetActiveStates()
    local isObjectiveMap = states and IsObjectiveBG(states.currentMapId)

    if not (isArenaUnit and isObjectiveMap) then
      playerButton = self:GetPlayerbuttonByUnitID(unitID, "Enemies")
    end
  end

  -- Also check Allies (e.g. party1, raid2 getting CC'd) via the direct
  -- token map — no PID matching on the ally side.
  if not playerButton then
    playerButton = self.Allies:GetAllyButtonByUnitID(unitID)
  end

  if playerButton and playerButton.SpecClassPriority then
    playerButton.SpecClassPriority:UpdateLossOfControl(unitID)
  end
end

BattleGroundEnemies.LOSS_OF_CONTROL_UPDATE = BattleGroundEnemies.LOSS_OF_CONTROL_ADDED

-- UNIT_AURA: real-time CC trigger for ally and enemy buttons.
-- C_LossOfControl is unreliable for party/raid members in tainted addon code, so we use
-- UNIT_AURA as the trigger and let UpdateLossOfControl fall back to C_UnitAuras when needed.
function BattleGroundEnemies:UNIT_AURA(unitID, updateInfo)
  if not unitID then
    return
  end

  -- Route by unit token pattern, NOT UnitIsFriend — UnitIsFriend can return a
  -- secret value in arena (Midnight PvP secrecy). Secret values are truthy in
  -- Lua so "if UnitIsFriend(...)" would match enemy arena units as allies,
  -- causing enemy CC to appear on ally buttons.
  -- Since we use RegisterUnitEvent for specific tokens we know exactly what each is.
  --
  -- string.find returns integer indices (no allocation), unlike string.match
  -- which allocates the matched substring on every successful hit. UNIT_AURA
  -- fires constantly in combat (food buffs, procs, HoTs, CC), so this is a hot
  -- path. Same anchored-pattern semantics ("party"/"raid"/"arena" + a digit),
  -- zero per-call garbage. Matches the string.find idiom used in UNIT_TARGET.
  local isAlly = (unitID == "player") or (unitID:find("^party%d") ~= nil) or (unitID:find("^raid%d") ~= nil)
  local isArenaEnemy = (unitID:find("^arena%d") ~= nil)

  if isAlly then
    -- Direct token lookup — unitID is party/raid/player (RegisterUnitEvent
    -- guarantees it). No PID, no matcher.
    local btn = self.Allies:GetAllyButtonByUnitID(unitID)
    if btn and btn.SpecClassPriority then
      btn.SpecClassPriority:UpdateLossOfControl(unitID, updateInfo)
    end
    return
  end

  if isArenaEnemy then
    local btn = self.ArenaIDToPlayerButton[unitID] or self:GetPlayerbuttonByUnitID(unitID, "Enemies")
    if btn and btn.SpecClassPriority then
      btn.SpecClassPriority:UpdateLossOfControl(unitID, updateInfo)
    end
    return
  end

  -- Other units (nameplates, BG enemies, etc.)
  local btn = self:GetPlayerbuttonByUnitID(unitID, "Enemies")
  if btn and btn.SpecClassPriority then
    btn.SpecClassPriority:UpdateLossOfControl(unitID, updateInfo)
  end
end

--fires when data requested by C_PvP.RequestCrowdControlSpell(unitID) is available
function BattleGroundEnemies:ARENA_CROWD_CONTROL_SPELL_UPDATE(unitID, ...)
  local playerButton = nil
  local isArenaUnit = unitID and unitID:match("^arena%d")
  local states = self:GetActiveStates()
  local isObjectiveMap = states and IsObjectiveBG(states.currentMapId)

  -- In objective BGs, ONLY process arena units - skip target/raid/nameplate/etc entirely
  -- This prevents duplicate trinket display when the same spell triggers for multiple unit types
  if isObjectiveMap and not isArenaUnit then
    return
  end

  -- Check ArenaIDToPlayerButton first for arena units
  if isArenaUnit then
    playerButton = self.ArenaIDToPlayerButton[unitID]
  end

  -- Fall back to PID matching - but NOT in objective BGs for arena units
  -- In objective BGs, arena tokens are only assigned to flag/orb carriers, so if not in
  -- ArenaIDToPlayerButton, this player doesn't have an objective and shouldn't get trinket updates
  if not playerButton then
    if not (isArenaUnit and isObjectiveMap) then
      playerButton = self:GetPlayerbuttonByUnitID(unitID, "Enemies")
    end
  end

  local spellId, itemID = ...

  -- Cache the spell data keyed by unitID. This handles the race condition where
  -- ARENA_CROWD_CONTROL_SPELL_UPDATE fires before the ally button has its unitID assigned
  -- (common for "player" which Blizzard fires automatically on zone-in). When the button
  -- registers its unitID later, it checks this cache and applies the icon immediately.
  self._ccSpellCache = self._ccSpellCache or {}
  if unitID then
    self._ccSpellCache[unitID] = { spellId = spellId, itemID = itemID }
  end

  -- Also check ally buttons — RequestCrowdControlSpell is now called for party members
  -- and "player" so this event fires for allies too, letting us show their trinket icon
  -- in the lobby just like enemies. Ally-side lookup uses the direct token map.
  if not playerButton then
    playerButton = self.Allies:GetAllyButtonByUnitID(unitID)
  end

  if playerButton and playerButton.Trinket then
    -- For allies: show the trinket icon so we can see what CC-break they have.
    -- For enemies: do NOT show the icon here. This event only announces which
    -- trinket the unit HAS, not that they used it. Showing it preemptively is
    -- misleading (especially in solo shuffle where CDs reset between rounds).
    -- Enemy trinket icons are set in ARENA_COOLDOWNS_UPDATE when actually used.
    if not playerButton.PlayerIsEnemy then
      playerButton.Trinket:DisplayTrinket(spellId, itemID)
    end
  end

  --if spellId ~= 72757 then --cogwheel (30 sec cooldown trigger by racial)
  --end
end

--fires when a arenaX enemy used a trinket or racial to break cc, C_PvP.GetArenaCrowdControlInfo(unitID) shoudl be called afterwards to get used CCs
--this event is kinda stupid, it doesn't say which unit used which cooldown, it justs says that somebody used some sort of trinket
function BattleGroundEnemies:ARENA_COOLDOWNS_UPDATE(unitID)
  local states = self:GetActiveStates()
  local isObjectiveMap = states and IsObjectiveBG(states.currentMapId)

  if unitID then
    -- Specific unit fired — this unit likely used their trinket
    local playerButton = nil
    local isArenaUnit = unitID and unitID:match("^arena%d")

    -- Check ArenaIDToPlayerButton first for arena units (same fix as target/focus)
    if isArenaUnit then
      playerButton = self.ArenaIDToPlayerButton[unitID]
    end

    -- Fall back to PID matching - but NOT in objective BGs for arena units
    -- In objective BGs, arena tokens are only assigned to flag/orb carriers, so if not in
    -- ArenaIDToPlayerButton, this player doesn't have an objective and shouldn't get trinket updates
    if not playerButton then
      if not (isArenaUnit and isObjectiveMap) then
        playerButton = self:GetPlayerbuttonByUnitID(unitID, "Enemies")
      end
    end

    if playerButton then
      local gotRealData = playerButton:UpdateCrowdControlCooldown(unitID)
      if not gotRealData then
        -- API returned nothing (taint-restricted, not in arena, etc.)
        -- Use a fake cooldown since we know THIS specific unit triggered the event.
        -- StartFakeCooldown() guards against re-triggers internally.
        playerButton:ApplyFakeTrinketCooldown()
      end
    end

    -- Also check allies (party/raid members using their trinket) — direct
    -- token map, no PID fallback.
    if not playerButton then
      local allyButton = self.Allies:GetAllyButtonByUnitID(unitID)
      if allyButton then
        allyButton:UpdateAllyCrowdControlCooldown(unitID)
      end
    end
  else
    -- No unitID: general refresh. Only apply real API data, never fake.
    for i = 1, 4 do
      local arenaUnit = "arena" .. i
      -- Use ArenaIDToPlayerButton directly for arena units
      local playerButton = self.ArenaIDToPlayerButton[arenaUnit]
      -- Skip PID fallback in objective BGs (no objective = no trinket updates)
      if not playerButton and not isObjectiveMap then
        playerButton = self:GetPlayerbuttonByUnitID(arenaUnit, "Enemies")
      end
      if playerButton then
        playerButton:UpdateCrowdControlCooldown(arenaUnit)
      end
    end

    -- Refresh all ally trinkets on general update
    if self.Allies and self.Allies.Players then
      for _, allyButton in pairs(self.Allies.Players) do
        local allyUnitID = allyButton.unitID
        if allyUnitID and UnitExists(allyUnitID) then
          allyButton:UpdateAllyCrowdControlCooldown(allyUnitID)
        end
      end
    end
  end
end

-- DR tracking: route C_SpellDiminish events to the correct playerButton's DRTracking container
function BattleGroundEnemies:UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED(unitToken, stateInfo)
  if not unitToken or not stateInfo then
    return
  end

  -- DR data is unusable in BGs: C_SpellDiminish returns a secret-tagged
  -- category in BG context (the DiminishStateUpdated handler bails on it
  -- downstream), and the LoC poll fallback gets no usable spellID for
  -- enemy units. Skip the matcher lookup + per-button DispatchEvent
  -- fan-out entirely in BGs. DR still works in arena / world PvP.
  if self.states.real.isInBattleground then
    return
  end

  -- Find the playerButton that owns this unitToken
  local playerButton = self.ArenaIDToPlayerButton[unitToken]
  if not playerButton then
    playerButton = self:GetPlayerbuttonByUnitID(unitToken, "Enemies")
  end

  if playerButton then
    playerButton:DispatchEvent("DiminishStateUpdated", unitToken, stateInfo)
  end
end

function BattleGroundEnemies:UNIT_HEALTH(unitID) --gets health of nameplates, player, target, focus, raid1 to raid40, partymember
  local playerButton = self:GetPlayerbuttonByUnitID(unitID, "Enemies")

  -- If not found (rejected friendly unit), check ally buttons by unitID
  if not playerButton and UnitIsFriend("player", unitID) then
    if self.Allies and self.Allies.Players then
      for _, allyButton in pairs(self.Allies.Players) do
        if allyButton.unitID == unitID then
          playerButton = allyButton
          break
        end
      end
    end
  end

  if playerButton then --unit is a shown player
    playerButton:UNIT_HEALTH(unitID)
  end
end

BattleGroundEnemies.UNIT_HEALTH_FREQUENT = BattleGroundEnemies.UNIT_HEALTH --used to be used only in tbc, now its only used in classic and wrath
BattleGroundEnemies.UNIT_MAXHEALTH = BattleGroundEnemies.UNIT_HEALTH
BattleGroundEnemies.UNIT_HEAL_PREDICTION = BattleGroundEnemies.UNIT_HEALTH
BattleGroundEnemies.UNIT_ABSORB_AMOUNT_CHANGED = BattleGroundEnemies.UNIT_HEALTH
BattleGroundEnemies.UNIT_HEAL_ABSORB_AMOUNT_CHANGED = BattleGroundEnemies.UNIT_HEALTH

function BattleGroundEnemies:UNIT_POWER_FREQUENT(unitID, powerToken)
  local playerButton = self:GetPlayerbuttonByUnitID(unitID, "Enemies")

  -- If not found (rejected friendly unit), check ally buttons by unitID
  if not playerButton and UnitIsFriend("player", unitID) then
    if self.Allies and self.Allies.Players then
      for _, allyButton in pairs(self.Allies.Players) do
        if allyButton.unitID == unitID then
          playerButton = allyButton
          break
        end
      end
    end
  end

  if playerButton then
    playerButton:UNIT_POWER_FREQUENT(unitID, powerToken)
  end
end

BattleGroundEnemies.UNIT_POWER_UPDATE = BattleGroundEnemies.UNIT_POWER_FREQUENT
BattleGroundEnemies.UNIT_MAXPOWER = BattleGroundEnemies.UNIT_POWER_FREQUENT

BattleGroundEnemies.PendingUpdates = {}
function BattleGroundEnemies:QueueForUpdateAfterCombat(tbl, funcName)
  --dont add the same function twice
  for i = 1, #BattleGroundEnemies.PendingUpdates do
    local pendingUpdate = BattleGroundEnemies.PendingUpdates[i]
    if pendingUpdate.tbl == tbl and pendingUpdate.funcName == funcName then
      return
    end
  end

  table.insert(self.PendingUpdates, { tbl = tbl, funcName = funcName })
end

function BattleGroundEnemies:PLAYER_REGEN_ENABLED()
  --Check if there are any outstanding updates that have been hold back due to being in combat
  for i = 1, #self.PendingUpdates do
    local tbl = self.PendingUpdates[i].tbl
    local funcName = self.PendingUpdates[i].funcName
    tbl[funcName](tbl)
  end
  wipe(self.PendingUpdates)

  -- Hide any buttons that were deferred during combat
  for _, buttons in pairs({
    self.Enemies and self.Enemies.InactivePlayerButtons,
    self.Allies and self.Allies.InactivePlayerButtons,
  }) do
    if buttons then
      for _, btn in ipairs(buttons) do
        if btn.pendingHide then
          btn:Hide()
          btn.pendingHide = nil
        end
      end
    end
  end

  -- Self-heal: Mainframe.lua:491 gates the post-UBS Show() on InCombatLockdown
  -- but never queues a retry. When UBS populates enemies while the player is in
  -- combat (common on mid-match reload / late join), the frame stays enabled but
  -- invisible. Toggling test mode forces a re-Show(), which is the workaround
  -- users kept hitting. Do it automatically now that combat ended.
  for _, mf in ipairs({ self.Enemies, self.Allies }) do
    if mf and mf.enabled and (mf.NumPlayers or 0) > 0 and not mf:IsShown() then
      mf:Show()
    end
  end

  -- Button-count watchdog: if combat-deferred cleanup or some other state
  -- drift left more buttons in PlayerList than the authoritative NumPlayers,
  -- force a clean rebuild now that combat is over. This is a safety net for
  -- the duplicate-frame bug that's been hard to reproduce on demand —
  -- whatever path leaks extra buttons, we self-correct here.
  for _, mf in ipairs({ self.Enemies, self.Allies }) do
    if mf and mf.PlayerList and mf.NumPlayers and #mf.PlayerList > mf.NumPlayers and mf.NumPlayers > 0 then
      -- DIAGNOSTIC (commented out — re-enable if duplicate-button bug
      -- returns. Prints + dumps event log when PlayerList exceeds
      -- NumPlayers post-combat):
      -- local dictCount = 0
      -- for _ in pairs(mf.Players or {}) do
      --   dictCount = dictCount + 1
      -- end
      -- print(
      --   string.format(
      --     "BGE Watchdog: %s PlayerList=%d > NumPlayers=%d (Dict=%d, Inactive=%d) — forcing rebuild",
      --     mf.PlayerType,
      --     #mf.PlayerList,
      --     mf.NumPlayers,
      --     dictCount,
      --     #(mf.InactivePlayerButtons or {})
      --   )
      -- )
      -- if BattleGroundEnemies.DumpButtonEventLog then
      --   BattleGroundEnemies:DumpButtonEventLog("watchdog:" .. mf.PlayerType)
      -- end
      -- Force the next UBS / GROUP_ROSTER_UPDATE to fully process by
      -- clearing the signature gate and re-running AfterPlayerSourceUpdate.
      -- AfterPlayerSourceUpdate's CreateOrRemovePlayerButtons will now
      -- (out of combat) actually remove untouched buttons.
      if mf.PlayerType == BattleGroundEnemies.consts.PlayerTypes.Enemies then
        BattleGroundEnemies._lastEnemyCount = nil
        if BattleGroundEnemies.UPDATE_BATTLEFIELD_SCORE then
          BattleGroundEnemies:UPDATE_BATTLEFIELD_SCORE()
        end
      else
        if BattleGroundEnemies.GROUP_ROSTER_UPDATE then
          BattleGroundEnemies:GROUP_ROSTER_UPDATE()
        end
      end
    end
  end
end

function BattleGroundEnemies:PLAYER_REGEN_DISABLED()
  if self.states.testmodeActive then
    self:DisableTestMode()
  end
end

function BattleGroundEnemies:PlayerDead()
  self.states.userIsAlive = false
  -- Force all enemy AND ally frames to out-of-range alpha when user is
  -- dead — you can't cast on anyone from a corpse, friendly or hostile.
  -- Iterate PlayerList (source-of-truth ordered list) rather than the
  -- Players name-keyed dict — secret-named buttons live ONLY in
  -- PlayerList (see SetupButtonForNewPlayer) and would otherwise stay
  -- at their pre-death bright alpha forever.
  local mainframes = { self.Enemies, self.Allies }
  for _, mf in ipairs(mainframes) do
    if mf and mf.PlayerList then
      for i = 1, #mf.PlayerList do
        mf.PlayerList[i]:UpdateRange(false, true)
      end
    end
  end
end

function BattleGroundEnemies:PlayerAlive()
  -- Force everyone to out-of-range on resurrect so nothing appears lit
  -- up before the real-range check runs. The ticker will naturally
  -- update range as we target/focus/see nameplates.
  -- PlayerList iteration (not Players dict) — same reason as PlayerDead.
  local mainframes = { self.Enemies, self.Allies }
  for _, mf in ipairs(mainframes) do
    if mf and mf.PlayerList then
      for i = 1, #mf.PlayerList do
        mf.PlayerList[i]:UpdateRange(false, true)
      end
    end
  end
  --recheck the targets of groupmembers
  for allyName, allyButton in pairs(self.Allies.Players) do
    allyButton:UpdateTarget()
  end
  self.states.userIsAlive = true

  -- Re-scan orb/flag carriers on resurrect. While dead, UnitExists(arenaN)
  -- returns false so CheckAllOrbs/CheckAllFlags skip every slot and the
  -- icon never gets attached visually — even if the chat handler correctly
  -- bound the carrier to ArenaIDToPlayerButton during death. PEW doesn't
  -- fire on resurrect, and UPDATE_BATTLEFIELD_SCORE's signature gate
  -- skips when player count is unchanged. This is the only reliable hook
  -- to re-display carrier icons after a graveyard rez.
  if self.RefreshObjectiveCarriers then
    self:RefreshObjectiveCarriers()
  end
end

function BattleGroundEnemies:PLAYER_ALIVE()
  if UnitIsGhost("player") then --Releases his ghost to a graveyard.
    self:PlayerDead()
  else --alive (revived while not being a ghost)
    self:PlayerAlive()
  end
end

function BattleGroundEnemies:PLAYER_DEAD()
  self:PlayerDead()
end

-- Reset isDead on all buttons and force a health refresh.
-- Used between solo shuffle rounds so bars don't stay empty.
function BattleGroundEnemies:ResetAllDeadStates()
  local mainframes = { self.Allies, self.Enemies }
  for _, mf in ipairs(mainframes) do
    if mf and mf.Players then
      for _, playerButton in pairs(mf.Players) do
        if playerButton.isDead then
          playerButton:PlayerIsAlive()
        end
        -- Push synthetic 100% directly via UpdateHealth (bypassing
        -- UNIT_HEALTH, which is blocked by the betweenRounds guard).
        -- The 3-second timer will clear betweenRounds and re-query
        -- real health once units have respawned.
        playerButton:UpdateHealth(nil, 1, 0, 100, 1)
        -- Clear stale raid target icons — players swap sides between
        -- rounds so old markers are no longer valid.
        playerButton.RaidTargetIconIndex = nil
        playerButton:DispatchEvent("UpdateRaidTargetIcon", nil)
        -- Clear trinket icons — players swap sides between rounds
        -- so an ally's trinket shouldn't carry over to their enemy button.
        if playerButton.Trinket then
          playerButton.Trinket:Reset()
        end
      end
    end
  end
end

function BattleGroundEnemies:UNIT_TARGET(unitID)
  -- Invalidate sticky PID cache — this unit changed target so the compound
  -- token (unitID.."target") now points to a different player.
  self:InvalidateStickyPID(unitID .. "target")

  local playerButton = self:GetPlayerbuttonByUnitID(unitID, "Enemies")

  if playerButton and playerButton ~= self.UserButton then --we use Player_target_changed for the player
    playerButton:UpdateTarget()
  end

  -- Enhancement: Snapshot update for the unit being targeted
  -- Restriction: Only check targets of friendly players (party/raid) to avoid secret value crashes for nameplates
  if string.find(unitID, "^party") or string.find(unitID, "^raid") or unitID == "player" then
    local targetUnitID = unitID .. "target"
    if UnitExists(targetUnitID) then
      local ok, name, server = pcall(GetUnitName, targetUnitID, true)
      local targetName = nil
      if ok and name then
        local ok2, computed = pcall(buildTargetNameNonSecret, name, server)
        if ok2 then
          targetName = computed
        else
          targetName = nil
        end
      end

      if targetName and type(targetName) == "string" then
        local enemyButton = self:SafeGetPlayerButton(self.Enemies.Players, targetName)
        if enemyButton then
          -- Force an update since we have a valid unitID pointing to them right now
          enemyButton:UNIT_HEALTH(targetUnitID)
          enemyButton:UNIT_POWER_FREQUENT(targetUnitID)
        end
      end
    end
  end
end

local function changeVisibility(frame, visible)
  if visible then
    frame:SetAlpha(1)
    frame:SetScale(1)
  else
    frame:SetAlpha(0)
    frame:SetScale(0.001)
  end
end

local function disableArenaFrames()
  if ArenaEnemyFrames then
    if ArenaEnemyFrames_Disable then
      ArenaEnemyFrames_Disable(ArenaEnemyFrames)
    end
  elseif ArenaEnemyFramesContainer then
    changeVisibility(ArenaEnemyFramesContainer, false)
  end
  if CompactArenaFrame then
    changeVisibility(CompactArenaFrame, false)
  end
end

local function checkEffectiveEnableStateForArenaFrames()
  if ArenaEnemyFrames then
    if ArenaEnemyFrames_CheckEffectiveEnableState then
      ArenaEnemyFrames_CheckEffectiveEnableState(ArenaEnemyFrames)
    end
  elseif ArenaEnemyFramesContainer then
    changeVisibility(ArenaEnemyFramesContainer, true)
  end
  if CompactArenaFrame then
    changeVisibility(CompactArenaFrame, true)
  end
end

function BattleGroundEnemies:ToggleArenaFrames()
  if InCombatLockdown() then
    return self:QueueForUpdateAfterCombat(self, "ToggleArenaFrames")
  end
  if
    (BattleGroundEnemies.states.real.isInArena and self.db.profile.DisableArenaFramesInArena)
    or (BattleGroundEnemies.states.real.isInBattleground and self.db.profile.DisableArenaFramesInBattleground)
  then
    return disableArenaFrames()
  end

  checkEffectiveEnableStateForArenaFrames()
end

local function restoreShowRaidFrameCVar()
  if not previousCvarRaidOptionIsShown then
    return
  end --we didn't modify it so no need to restore it
  SetCVar("raidOptionIsShown", previousCvarRaidOptionIsShown)
end

local function disableRaidFrames()
  if previousCvarRaidOptionIsShown == nil then
    previousCvarRaidOptionIsShown = GetCVar("raidOptionIsShown")
  end
  if GetCVar("raidOptionIsShown") == "1" then
    SetCVar("raidOptionIsShown", false)
  end
end

function BattleGroundEnemies:ToggleRaidFrames()
  if InCombatLockdown() then
    return self:QueueForUpdateAfterCombat(self, "ToggleRaidFrames")
  end
  if
    (BattleGroundEnemies.states.real.isInArena and self.db.profile.DisableRaidFramesInArena)
    or (BattleGroundEnemies.states.real.isInBattleground and self.db.profile.DisableRaidFramesInBattleground)
  then
    return disableRaidFrames()
  end

  restoreShowRaidFrameCVar()
end

function BattleGroundEnemies:UpdateArenaPlayers()
  self.Enemies:CreateArenaEnemies()

  -- In BGs with objective carriers (flags/orbs), arena tokens are only for carriers.
  -- Skip the normal arena token assignment here - CheckAllOrbs/CheckAllFlags handles it properly
  -- with full PID matching and bidirectional cleanup.
  -- Previously this site had an inlined list that mixed map IDs and instance
  -- IDs (e.g. 2106/726/566/968/2656), so the skip only matched for Kotmogu
  -- (whose map ID is 417) — every other objective BG silently ran the normal
  -- arena-token assignment in parallel with the carrier path. Routing through
  -- the IsObjectiveBG helper (correct map IDs) skips all six as intended.
  local states = self:GetActiveStates()
  local mapId = states and states.currentMapId
  if IsObjectiveBG(mapId) then
    return
  end

  if #BattleGroundEnemies.Enemies.CurrentPlayerOrder > 0 or #BattleGroundEnemies.Allies.CurrentPlayerOrder > 0 then --this ensures that we checked for enemies and the flag carrier will be shown (if its an enemy)
    for i = 1, GetNumArenaOpponents() do
      local unitID = "arena" .. i
      -- Try PID matching first (works when GUID/name aren't secret)
      local playerButton = BattleGroundEnemies:GetPlayerbuttonByUnitID(unitID, "Enemies")

      -- Fallback: find the button directly by its PlayerArenaUnitID.
      -- In 12.0 combat, GUID and names are secret so PID matching fails.
      -- CreateArenaEnemies already tagged each button with PlayerArenaUnitID.
      if not playerButton then
        for _, btn in pairs(BattleGroundEnemies.Enemies.Players) do
          if btn.PlayerDetails and btn.PlayerDetails.PlayerArenaUnitID == unitID then
            playerButton = btn
            break
          end
        end
      end

      if playerButton then
        playerButton:ArenaOpponentShown(unitID)
      end
    end
  elseif self.Enemies:ShouldBeEnabled() then
    -- Both player orders are empty. Only keep retrying while enemy frames are
    -- ENABLED for this bracket -- i.e. we're genuinely waiting for arena
    -- opponents to load. If enemies are disabled for the bracket (the
    -- ghost-frame gate tore the ArenaPlayers source down), both orders are
    -- empty BY DESIGN, and without this guard the C_Timer.After below would
    -- self-reschedule every second for the entire match.
    C_Timer.After(1, function()
      self:UpdateArenaPlayers()
    end)
  end
end

local UpdateArenaPlayersTicker

--too avoid calling UpdateArenaPlayers too many times within a second
function BattleGroundEnemies:DebounceUpdateArenaPlayers()
  if UpdateArenaPlayersTicker then
    UpdateArenaPlayersTicker:Cancel()
  end -- use a timer to apply changes after half second, this prevents from too many updates after each player is found

  if not self.states.real.isInArena and not self.states.real.isInBattleground then
    return
  end
  UpdateArenaPlayersTicker = CTimerNewTicker(0.5, function()
    BattleGroundEnemies:UpdateArenaPlayers()
    UpdateArenaPlayersTicker = nil
  end, 1)
end

function BattleGroundEnemies:CheckForArenaEnemies()
  -- returns valid data on PLAYER_ENTERING_WORLD
  if GetNumArenaOpponents() == 0 then
    C_Timer.After(2, function()
      self:DebounceUpdateArenaPlayers()
    end)
  else
    self:DebounceUpdateArenaPlayers()
  end
end

BattleGroundEnemies.PLAYER_UNGHOST = BattleGroundEnemies.PlayerAlive --player is alive again

function BattleGroundEnemies:GetBuffsAndDebuffsForMap(mapId)
  if not mapId then
    return
  end
  -- Returns only the Buffs table for the given map. The second-return
  -- (Debuffs) was dropped on 2026-05-02 — see GetBattlegroundAuras above
  -- for the migration rationale. Function name kept for source-history
  -- continuity even though it now returns just the buffs.
  return Data.BattlegroundspezificBuffs and Data.BattlegroundspezificBuffs[mapId]
end

function BattleGroundEnemies:UpdateMapID(retries)
  retries = retries or 0
  --	SetMapToCurrentZone() apparently removed in 8.0
  local mapId = C_Map.GetBestMapForUnit("player")

  if mapId and mapId ~= -1 and mapId ~= 0 then -- when this values occur the map ID is not real
    self.states.real.currentMapId = mapId
  else
    self.states.real.currentMapId = false
    if retries > 5 then
      return
    end
    C_Timer.After(2, function() --Delay this check, since its happening sometimes that this data is not ready yet
      self:UpdateMapID(retries + 1)
    end)
  end
end

local function parseBattlefieldScore(index)
  local scoreInfo = C_PvP.GetScoreInfo(index)
  if not scoreInfo then
    return
  end

  -- Explicit field copy instead of Mixin({}, scoreInfo).
  -- Mixin does `for k, v in pairs(scoreInfo)` — but in 12.0.5 PvP the table
  -- returned by C_PvP.GetScoreInfo is a protected/secret table that CANNOT
  -- be iterated while our execution is tainted ("attempted to iterate a
  -- table that cannot be accessed while tainted (execution tainted by
  -- BattleGroundEnemiesFixed)"). Field ACCESS is still allowed (the rest of
  -- this function and UBS already read scoreInfo.guid / row.name directly),
  -- so copy each documented PVPScoreInfo field by name. Every assignment is a
  -- pure pass-through, so possibly-secret fields (talentSpec, rating,
  -- honorGained, damageDone, etc.) carry over EXACTLY as Mixin did — no
  -- comparison, no arithmetic, no use as a table key. Behaviorally identical
  -- to the old Mixin, minus the taint crash. Also eliminates the per-row
  -- Mixin pairs-copy allocation (improvement #10), which in a 40-row epic
  -- lobby ran for every row on every UBS tick.
  -- Field list mirrors PVPScoreInfo in
  -- Blizzard_APIDocumentationGenerated/PvpInfoDocumentation.lua.
  local result = {
    name = scoreInfo.name,
    guid = scoreInfo.guid,
    killingBlows = scoreInfo.killingBlows,
    honorableKills = scoreInfo.honorableKills,
    deaths = scoreInfo.deaths,
    honorGained = scoreInfo.honorGained,
    faction = scoreInfo.faction,
    raceName = scoreInfo.raceName,
    className = scoreInfo.className,
    classToken = scoreInfo.classToken,
    damageDone = scoreInfo.damageDone,
    healingDone = scoreInfo.healingDone,
    rating = scoreInfo.rating,
    ratingChange = scoreInfo.ratingChange,
    prematchMMR = scoreInfo.prematchMMR,
    mmrChange = scoreInfo.mmrChange,
    postmatchMMR = scoreInfo.postmatchMMR,
    talentSpec = scoreInfo.talentSpec,
    honorLevel = scoreInfo.honorLevel,
    roleAssigned = scoreInfo.roleAssigned,
    stats = scoreInfo.stats,
  }

  if not scoreInfo.guid then
    return result
  end

  local ok, localizedClass, englishClass, localizedRace, englishRace, sex, _, realmName =
    pcall(GetPlayerInfoByGUID, scoreInfo.guid)

  if ok then
    result.localizedClass = localizedClass
    result.englishClass = englishClass
    result.localizedRace = localizedRace
    result.englishRace = englishRace
    result.sex = sex
    result.realmName = realmName
  end

  -- Debug: Log what GetPlayerInfoByGUID returned for sex (only for enemies)
  -- if result.name then
  --   local isEnemy = (result.faction ~= BattleGroundEnemies.AllyFaction)
  --   if isEnemy then
  --     print(result.name, scoreInfo.honorLevel)
  --   end
  -- end

  return result
end

-- Lobby-only diagnostic watchdog: every few seconds while the match state
-- is Inactive (gates closed, pre-game), check whether our enemy PlayerList
-- count matches what GetBattlefieldTeamInfo reports for the enemy team.
-- If they differ, PRINT a warning and dump the recent button-event log.
-- DOES NOT auto-fix anything — purely diagnostic until we have a confirmed
-- root cause for the "enemies disappear in lobby after alt-tab" report.
-- Stops automatically when state leaves Inactive (gates open) or when the
-- user leaves the BG/arena.

-- local function startLobbyEnemyWatchdog(self)
--   if self._lobbyEnemyWatchdog then
--     return -- already running
--   end
--   self._lobbyEnemyWatchdog = C_Timer.NewTicker(5, function()
--     -- Re-check state inside the callback to handle timing overlaps.
--     local s = C_PvP and C_PvP.GetActiveMatchState and C_PvP.GetActiveMatchState()
--     if s ~= Enum.PvPMatchState.Inactive then
--       return
--     end
--     local mf = self.Enemies
--     if not mf or not mf.PlayerList or not self.EnemyFaction then
--       return
--     end
--     local _, _, _, _, expected = GetBattlefieldTeamInfo(self.EnemyFaction)
--     if not expected or expected <= 0 then
--       return
--     end
--     if #mf.PlayerList < expected then
--       -- DIAGNOSTIC (commented out — re-enable if "enemies disappear in
--       -- lobby" returns. Prints + dumps event log when lobby-phase
--       -- PlayerList undercount detected):
--       -- print(
--       --   string.format(
--       --     "BGE Lobby Watch: PlayerList=%d but scoreboard expects %d enemies (lobby phase) — diagnostic only, NOT auto-fixing",
--       --     #mf.PlayerList,
--       --     expected
--       --   )
--       -- )
--       -- if self.DumpButtonEventLog then
--       --   self:DumpButtonEventLog("lobby-watch")
--       -- end
--     end
--   end)
-- end

-- local function stopLobbyEnemyWatchdog(self)
--   if self._lobbyEnemyWatchdog then
--     self._lobbyEnemyWatchdog:Cancel()
--     self._lobbyEnemyWatchdog = nil
--   end
-- end

-- BattleGroundEnemies._stopLobbyEnemyWatchdog = stopLobbyEnemyWatchdog

function BattleGroundEnemies:PVP_MATCH_STATE_CHANGED()
  local state = C_PvP.GetActiveMatchState()

  if state == Enum.PvPMatchState.Complete or state == Enum.PvPMatchState.Inactive then
    -- Clear cached trinket spells so stale data doesn't bleed into the next match.
    self._ccSpellCache = nil
  end

  -- Lobby diagnostic watchdog lifecycle:
  -- start when state becomes Inactive (in lobby/gates), stop on any other
  -- state transition. Match-end (Complete) and PostRound also stop it.

  -- if state == Enum.PvPMatchState.Inactive then
  --   startLobbyEnemyWatchdog(self)
  -- else
  --   stopLobbyEnemyWatchdog(self)
  -- end

  if state == Enum.PvPMatchState.Engaged then
    self.betweenRounds = false
    -- Refresh raid target icons — updates during the lobby were
    -- swallowed by the DispatchEvent block, so icons may be stale
    -- (e.g. a player swapped sides but kept their old marker).
    self:RAID_TARGET_UPDATE()
  elseif state == Enum.PvPMatchState.Complete or state == Enum.PvPMatchState.PostRound then
    self:UPDATE_BATTLEFIELD_SCORE()

    -- Harvest non-secret player identity from the now-readable scoreboard.
    -- SecretInActivePvPMatch only applies to StartUp/Engaged; PostRound
    -- and Complete return full PVPScoreInfo (talentSpec, roleAssigned,
    -- honorLevel, guid, ...) non-secret. PostRound runs every solo-shuffle
    -- round so leavers get captured before they vanish on Complete.
    --
    -- On Complete, clear the per-match harvest gate first so every player
    -- gets re-written with the freshest scoreboard data — and as a safety
    -- net for anyone PostRound had to skip (e.g. still-secret guid).
    if state == Enum.PvPMatchState.Complete then
      self._harvestedThisMatch = nil
    end
    self:HarvestPlayerHistory()

    if state == Enum.PvPMatchState.PostRound then
      -- Clear cached trinket spells so stale data from the previous round
      -- doesn't get applied to buttons that swap sides in solo shuffle.
      self._ccSpellCache = nil

      self:ResetAllDeadStates()
      self.betweenRounds = true
    else
      -- Match Complete (NOT PostRound — solo shuffle continues between
      -- rounds). Harvest above has already run, so all post-match data
      -- is captured. Now stop all tickers and unregister combat events:
      -- the live frames have nothing useful left to show, and continuing
      -- to run keeps UPDATE_BATTLEFIELD_SCORE firing as the results UI
      -- churns / players leave, which is the +10-45 MB/s post-match
      -- allocation storm (and its 50-342ms GC-pause stutters). Disable()
      -- also makes per-match state eligible for GC, so the heap doesn't
      -- keep accumulating ~50 MB per BG across a no-/reload session.
      -- Re-enables automatically on next zone-in via PLAYER_ENTERING_WORLD
      -- -> CheckEnableState() -> Enable().
      self:Disable()
    end
  elseif state == Enum.PvPMatchState.Inactive then
    self.betweenRounds = false
    -- New match coming. Clear the per-match harvest set so the next
    -- PostRound/Complete window can re-write entries (honorLevel, lastSpec,
    -- lastRole all evolve over time — let them refresh).
    self._harvestedThisMatch = nil
  end
end

-- Account-shared player identity harvest. Called from PVP_MATCH_STATE_CHANGED
-- on PostRound and Complete (non-secret scoreboard window). Idempotent within
-- a match via _harvestedThisMatch (cleared on Inactive). Reads survive across
-- sessions in db.global.PlayerHistory; pruned on PLAYER_LOGIN.
function BattleGroundEnemies:HarvestPlayerHistory()
  local db = self.db and self.db.global
  if not db then
    return
  end
  db.PlayerHistory = db.PlayerHistory or {}
  self._harvestedThisMatch = self._harvestedThisMatch or {}

  -- Force factionEnum -1 so GetNumBattlefieldScores / GetScoreInfo see
  -- BOTH teams. If the user (or Blizzard's PVPMatch UI) had a single-faction
  -- tab selected, our iteration would silently miss half the players.
  -- SetBattlefieldScoreFaction fires UBS synchronously; the existing UBS
  -- handler honors _reassertingScoreboard to avoid recursion.
  if self._scoreboardFaction ~= -1 then
    self._reassertingScoreboard = true
    self._scoreboardFaction = -1
    SetBattlefieldScoreFaction(-1)
    self._reassertingScoreboard = false
  end

  -- Build a name→button map once so we can pull GuildName captured by
  -- captureLiveAttrs during the match. PVPScoreInfo has no guild field;
  -- the only source for an enemy's guild is a unit-token resolve, which
  -- captureLiveAttrs has already done by the time we're here.
  local nameToButton = {}
  for _, mf in ipairs({ self.Enemies, self.Allies }) do
    if mf and mf.Players then
      for nm, btn in pairs(mf.Players) do
        nameToButton[nm] = btn
      end
    end
  end

  local now = time()
  local numScores = GetNumBattlefieldScores()
  for i = 1, numScores do
    local scoreInfo = C_PvP.GetScoreInfo(i)
    -- Filter to real player characters only. In comp stomp / Brawl /
    -- training grounds the enemy "team" is bots that ALSO use the
    -- "Player-" GUID prefix — but with extra segments. Real player GUIDs
    -- are exactly "Player-{realmID}-{characterHex}" (2 hyphens, 3 parts).
    -- Bot GUIDs are "Player-3021-2-8402-{hex}" (4 hyphens, 5 parts) where
    -- the 3021-2-8402 segment identifies the bot server. The strict
    -- 3-part pattern catches both — let bots pollute PlayerHistory and
    -- the disambiguation tiers would think bots are known players in
    -- real BGs (bot names are often reused across matches).
    -- guid is *usually* non-secret in PostRound/Complete (past
    -- SecretInActivePvPMatch), but solo shuffle has produced cases where
    -- it remains secret — calling :match() on a secret string taints
    -- execution, so gate explicitly.
    local nameOk = scoreInfo
      and type(scoreInfo.name) == "string"
      and not (issecretvalue and issecretvalue(scoreInfo.name))
      and scoreInfo.classToken
      and type(scoreInfo.guid) == "string"
      and not (issecretvalue and issecretvalue(scoreInfo.guid))
      and scoreInfo.guid:match("^Player%-%d+%-[%dA-Fa-f]+$") ~= nil
    if nameOk then
      local key = self:CanonicalName(scoreInfo.name)
      if key and not self._harvestedThisMatch[key] then
        local existing = db.PlayerHistory[key] or {}

        -- Pull non-scoreboard fields. Three sources by preference:
        --   1) Same-name button's PlayerDetails (captureLiveAttrs already
        --      populated these via UnitSexBase/GetGuildInfo/UnitPowerType
        --      mid-match, all in the modern enum where applicable).
        --   2) GetPlayerInfoByGUID for sex/realm if button source missed.
        --   3) Existing harvest entry as last fallback.
        -- IMPORTANT: GetPlayerInfoByGUID returns the LEGACY sex enum
        -- (1=None, 2=Male, 3=Female), NOT the modern UnitSex enum
        -- (0=Male, 1=Female, 2=None, 3=Both, 4=Neutral). The matcher's
        -- tier 7 compares against UnitSexBase returns (modern enum), so
        -- we must convert before storing — otherwise harvest-seeded
        -- gender never matches live unit reads.
        local LEGACY_TO_MODERN_SEX = { [1] = 2, [2] = 0, [3] = 1 }
        local sex, realm, guild, powerType
        local btn = nameToButton[key]
        if btn and btn.PlayerDetails then
          local g = btn.PlayerDetails.gender
          if g and not (issecretvalue and issecretvalue(g)) then
            sex = g -- already modern enum
          end
          local gn = btn.PlayerDetails.GuildName
          -- `gn ~= nil` (not `if gn`) so `false` (confirmed guildless)
          -- is captured as a real value, not skipped as falsy.
          if gn ~= nil and not (issecretvalue and issecretvalue(gn)) then
            guild = gn
          end
          local pt = btn.PlayerDetails.lastPowerType
          if pt then
            powerType = pt
          end
        end
        -- GetPlayerInfoByGUID: realm always; sex only if button source
        -- didn't have it. Convert legacy → modern.
        if scoreInfo.guid and not (issecretvalue and issecretvalue(scoreInfo.guid)) then
          local ok, _lc, _ec, _lr, _er, gpiSex, _nm, rl = pcall(GetPlayerInfoByGUID, scoreInfo.guid)
          if ok then
            realm = realm or rl
            if not sex and gpiSex then
              sex = LEGACY_TO_MODERN_SEX[gpiSex] or gpiSex
            end
          end
        end

        -- `guild` may be `false` (confirmed guildless). Lua's `a or b`
        -- short-circuits on falsy values so `guild or existing.GuildName`
        -- would silently discard a `false` value. Use explicit nil check.
        local guildToStore
        if guild ~= nil then
          guildToStore = guild
        else
          guildToStore = existing.GuildName
        end
        db.PlayerHistory[key] = {
          name = key,
          guid = scoreInfo.guid,
          classToken = scoreInfo.classToken,
          raceName = scoreInfo.raceName,
          gender = sex or existing.gender,
          GuildName = guildToStore,
          lastPowerType = powerType or existing.lastPowerType,
          realmName = realm or existing.realmName,
          lastSpec = scoreInfo.talentSpec,
          lastRole = scoreInfo.roleAssigned,
          honorLevel = scoreInfo.honorLevel,
          seenCount = (existing.seenCount or 0) + 1,
          lastSeenAt = now,
        }
        self._harvestedThisMatch[key] = true
      end
    end
  end
end

-- Companion to HarvestPlayerHistory: harvests your party/raid members during
-- the BG. Complements end-of-match harvest by capturing data even when:
--   - You DC or leave before PostRound/Complete fires
--   - A teammate leaves the BG mid-match (may not be in final scoreboard)
--   - You haven't reached end-of-match yet (data available immediately
--     for any same-match cross-faction or merc encounter)
--
-- All reads are non-secret on raid/party tokens (UnitClassBase, UnitRace,
-- UnitSexBase, UnitHonorLevel, GetGuildInfo, UnitPowerType, UnitFactionGroup,
-- UnitGUID, GetPlayerInfoByGUID), so this is safe to run any time we're in
-- a PvP instance.
--
-- IMPORTANT: every value stored here MUST match the type/format that
-- HarvestPlayerHistory writes from PVPScoreInfo, because the matcher's tier
-- comparators read PlayerHistory entries assuming scoreboard-shaped data.
-- Conversions:
--   GuildName: GetGuildInfo nil → store as `false` (matches scoreboard
--              "confirmed guildless" three-state semantics).
-- Skipped (raid source can't reliably match scoreboard format; preserved
-- from existing entry instead so end-of-match scoreboard refresh fills them):
--   lastSpec: requires async NotifyInspect.
--   lastRole: scoreboard `roleAssigned` is a bitmask (1=Leader, 2=Tank,
--             4=Healer, 8=Damage) including the leader bit; UnitGroupRoles-
--             Assigned ("TANK"/"HEALER"/"DAMAGER"/"NONE") doesn't expose
--             leader status, so a converted value would mismatch.
-- Faction is intentionally NOT stored: it was vestigial in PlayerHistory
-- (written by both harvests but read by no real code path). Removing the
-- field saves storage and removes a maintenance liability. If a future
-- feature needs it, both harvests are trivial to amend.
-- seenCount is preserved (not incremented). seenCount means "matches I've
-- completed where this player was on the final scoreboard" — only end-of-
-- match harvest touches it. Raid harvest can fire many times per match
-- (every GROUP_ROSTER_UPDATE) and double-counting would skew the value.
function BattleGroundEnemies:HarvestRaidRoster()
  local db = self.db and self.db.global
  if not db then
    return
  end
  if not self:IsInPvPInstance() then
    return
  end
  db.PlayerHistory = db.PlayerHistory or {}

  local now = time()

  local function harvestUnit(unit)
    if not UnitExists(unit) then
      return
    end
    -- Real player characters only — skip pets, NPCs, vehicles.
    local okPlayer, isPlayer = pcall(UnitIsPlayer, unit)
    if not okPlayer or not isPlayer then
      return
    end
    local guid = UnitGUID(unit)
    -- Real-player GUIDs are exactly "Player-{realmID}-{characterHex}". Bot
    -- GUIDs in comp stomp / Brawl have extra segments and would pollute
    -- PlayerHistory if accepted.
    if type(guid) ~= "string" or guid:match("^Player%-%d+%-[%dA-Fa-f]+$") == nil then
      return
    end

    -- Canonical "Name-Realm" key. GetUnitName(unit, true) returns short
    -- "Name" for same-realm members; CanonicalName appends the user's realm
    -- so the storage key matches what HarvestPlayerHistory writes.
    local rawName = GetUnitName(unit, true)
    if type(rawName) ~= "string" then
      return
    end
    local key = self:CanonicalName(rawName)
    if not key then
      return
    end

    local existing = db.PlayerHistory[key] or {}

    -- UnitClassBase and UnitRace are both flagged MayReturnNothing in the
    -- API docs — they return nothing (nil) for valid raid tokens whose
    -- player data hasn't fully loaded yet (mid-zone-in window). If neither
    -- basic identity field is readable, the unit isn't ready; skip and
    -- let the existing GROUP_ROSTER_UPDATE retry loop fire again with
    -- complete data. Without this guard, GetGuildInfo also returns nil
    -- for an unloaded unit and we'd incorrectly write GuildName=false
    -- ("confirmed guildless") into PlayerHistory.
    local _, classToken = UnitClassBase(unit)
    local raceName = UnitRace(unit) -- 1st return: localized; matches scoreboard.raceName
    if not classToken and not raceName then
      return
    end

    local _, gender = pcall(UnitSexBase, unit) -- modern enum (0=Male, 1=Female, 2=None); Nilable=true
    local _, honor = pcall(UnitHonorLevel, unit)
    local _, powerType = pcall(UnitPowerType, unit) -- numeric enum; MayReturnNothing

    local guildName = GetGuildInfo(unit)
    local guildToStore
    if guildName then
      guildToStore = guildName
    else
      -- Guildless: scoreboard semantics use `false` to mean "confirmed
      -- guildless" (three-state nil/false/string). Safe to store false
      -- here because the loaded-unit guard above already passed — i.e.
      -- this unit's data IS available, so GetGuildInfo nil means actually
      -- guildless rather than "unit not ready."
      guildToStore = false
    end

    -- Realm via GetPlayerInfoByGUID (same source HarvestPlayerHistory uses).
    -- Note: GetPlayerInfoByGUID returns LEGACY sex enum, but we already have
    -- modern-enum gender from UnitSexBase, so we ignore its sex return.
    local realm
    local okGpi, _lc, _ec, _lr, _er, _gpiSex, _nm, rl = pcall(GetPlayerInfoByGUID, guid)
    if okGpi and type(rl) == "string" and rl ~= "" then
      realm = rl
    end

    db.PlayerHistory[key] = {
      name = key,
      guid = guid,
      classToken = classToken or existing.classToken,
      raceName = raceName or existing.raceName,
      gender = gender or existing.gender,
      GuildName = guildToStore,
      lastPowerType = powerType or existing.lastPowerType,
      realmName = realm or existing.realmName,
      lastSpec = existing.lastSpec, -- raid source can't provide; preserve
      lastRole = existing.lastRole, -- bitmask format mismatch; preserve
      honorLevel = honor or existing.honorLevel,
      seenCount = existing.seenCount or 0, -- only end-of-match increments
      lastSeenAt = now,
    }
  end

  harvestUnit("player")
  if IsInRaid() then
    local n = GetNumGroupMembers() or 0
    for i = 1, n do
      harvestUnit("raid" .. i)
    end
  elseif IsInGroup() then
    -- party1..N (excludes self; "player" was already harvested above)
    local n = (GetNumGroupMembers() or 0) - 1
    for i = 1, n do
      harvestUnit("party" .. i)
    end
  end
end

function BattleGroundEnemies:SetAllyFaction(allyFaction)
  local changed = self.AllyFaction ~= allyFaction
  self.EnemyFaction = allyFaction == 0 and 1 or 0
  self.AllyFaction = allyFaction
  -- Propagate label update on flip. Without this, merc-detection (UBS) or
  -- the PLAYER_ENTERING_WORLD correction flips state AFTER SetRealPlayerCount
  -- has already rendered the panel header with the pre-flip value — leaving
  -- labels stuck in the wrong Horde/Alliance state until a count changes.
  -- Cross-faction note: this is still just a legacy label; mixed-faction
  -- teams will always be imprecise here. Team-assignment correctness (which
  -- is what scoreboard/roster buckets depend on) comes from the user's own
  -- C_PvP.GetScoreInfoByPlayerGuid lookup in UBS / PEW, not from this.
  if changed then
    if self.Enemies and self.Enemies.UpdatePlayerCountText then
      self.Enemies:UpdatePlayerCountText()
    end
    if self.Allies and self.Allies.UpdatePlayerCountText then
      self.Allies:UpdatePlayerCountText()
    end
  end
end

function BattleGroundEnemies:UPDATE_BATTLEFIELD_SCORE()
  -- Re-assert factionEnum -1 if the user (or Blizzard's PVPMatch UI) clicked
  -- a faction tab and filtered the scoreboard to one team — without -1 our
  -- GetNumBattlefieldScores / GetScoreInfo iteration would only see that
  -- team's rows. Skip while the user is actively looking at the scoreboard
  -- so we don't yank their tab view out from under them; the next UBS tick
  -- after they close it will re-assert.
  local scoreboardShown = (PVPMatchScoreboard and PVPMatchScoreboard:IsShown())
    or (PVPMatchResults and PVPMatchResults:IsShown())
  -- Hard re-entry guard: SetBattlefieldScoreFaction fires UPDATE_BATTLEFIELD_SCORE
  -- synchronously (plus Blizzard's scoreboard UI updates may also fire UBS
  -- mid-call). Without this, we recurse infinitely:
  -- handler → SetFaction → UBS → handler → SetFaction → ... stack overflow.
  if self._reassertingScoreboard then
    return
  end
  if not scoreboardShown then
    if self._scoreboardFaction ~= -1 then
      self._reassertingScoreboard = true
      self._scoreboardFaction = -1
      SetBattlefieldScoreFaction(-1)
      self._reassertingScoreboard = false
      return
    end
  end

  -- Leaver detection: iterate known players, remove any whose GUID
  -- is no longer present in the scoreboard.
  -- Old leaver-detection via C_PvP.GetScoreInfoByPlayerGuid removed —
  -- GUIDs are effectively always secret in 12.0.5 PvP, making the API
  -- unusable (it errors on secret args). Leaver detection is handled
  -- entirely by the BeforePlayerSourceUpdate / AfterPlayerSourceUpdate
  -- mark-and-sweep cycle further down — any button whose scoreboard row
  -- is missing this tick gets status=2 (untouched) and is removed.

  -- AllyFaction is only used to identify which scoreboard rows belong to
  -- the enemy team. Ally frames themselves are driven entirely by
  -- raidN/partyN tokens from GROUP_ROSTER_UPDATE — scoreboard is never
  -- read for allies.
  --
  -- AUTHORITATIVE source: the user's own scoreboard row via
  -- C_PvP.GetScoreInfoByPlayerGuid(UnitGUID("player")). info.faction =
  -- team number for THIS match (correct for mercenary mode and
  -- cross-faction Blitz where the character's home faction differs
  -- from the assigned team).
  --
  -- Cross-validation. A single C_PvP.GetScoreInfoByPlayerGuid call can
  -- return a wrong team number while the scoreboard is still populating
  -- (observed in the wild: every real teammate ended up bucketed as
  -- enemy because the early lookup said the player was on the opposite
  -- team). To prevent that, we only commit AllyFaction once a known
  -- raid peer's scoreboard row reports the same team.
  --
  -- Validation is name-based, NOT GUID-based. UnitGUID("raidN") is
  -- documented as SecretWhenUnitIdentityRestricted, which by spec
  -- shouldn't fire for party/raid members — but the addon's own
  -- AddGroupMember already has an issecretvalue(GUID) guard for raid
  -- units, suggesting it has been observed empirically. PVPScoreInfo.name
  -- is NeverSecret per Blizzard's API docs, and GetRaidRosterInfo names
  -- are what the addon already trusts as the ally roster source — both
  -- are reliable here.
  --
  -- If we can't confirm yet (own row not populated, no raid peer found
  -- in the scoreboard yet, or the player is somehow not in a group),
  -- AllyFaction stays nil — every consumer is gated on AllyFaction being
  -- set, so an empty enemy panel for a tick or two is the explicit
  -- trade-off against ever showing real teammates as enemies.
  if self.AllyFaction == nil then
    -- Grace period: skip validation entirely until the 3s post-zone-in
    -- timer has fired. The scoreboard takes time to populate and
    -- querying it sooner is wasted work. While we're in this window we
    -- bail out of UBS entirely (consumers below all gate on AllyFaction
    -- != nil anyway, and an empty enemy panel is correct behavior
    -- during the grace period). The flag is set true by the C_Timer
    -- scheduled in PLAYER_ENTERING_WORLD when entering PvP.
    if not self._pvpGracePeriodElapsed then
      return
    end

    local ok, myInfo = pcall(C_PvP.GetScoreInfoByPlayerGuid, UnitGUID("player"))
    -- myInfo.name is documented as NeverSecret but in practice has been
    -- observed flagged as secret while the addon's execution is tainted.
    -- Comparing a secret string to anything taints the entire call stack —
    -- pre-check and bail out of validation entirely if our own name reads
    -- back as secret. AllyFaction stays nil, enemy panel stays empty, the
    -- "never wrong" trade-off holds.
    if ok and myInfo and myInfo.faction ~= nil and type(myInfo.name) == "string"
        and not (issecretvalue and issecretvalue(myInfo.name)) then
      local raidNames = nil
      if IsInRaid() then
        raidNames = {}
        for i = 1, GetNumGroupMembers() or 0 do
          local memberName = GetRaidRosterInfo(i)
          if type(memberName) == "string"
              and not (issecretvalue and issecretvalue(memberName))
              and memberName ~= myInfo.name then
            raidNames[memberName] = true
          end
        end
      end

      if raidNames and next(raidNames) then
        -- Require >= 2 raid peers' scoreboard rows to agree with our team
        -- number before committing. With one peer it's still possible for
        -- both rows to be transiently wrong with the same default value;
        -- requiring two distinct peers makes that essentially impossible.
        -- ANY disagreement (even one peer reporting a different team)
        -- means the scoreboard is mid-populate and inconsistent — bail
        -- and retry on the next UBS tick.
        local REQUIRED_PEERS = 2
        local agreed = 0
        for i = 1, GetNumBattlefieldScores() do
          local row = C_PvP.GetScoreInfo(i)
          if row and type(row.name) == "string" and row.faction ~= nil and raidNames[row.name] then
            if row.faction == myInfo.faction then
              agreed = agreed + 1
              if agreed >= REQUIRED_PEERS then
                self:SetAllyFaction(myInfo.faction)
                break
              end
            else
              -- Disagreement: at least one peer says different team.
              -- Don't commit; retry next tick.
              agreed = 0
              break
            end
          end
        end
      end
    end
  end

  -- If still unknown (scoreboard not populated, or no peer to validate
  -- against yet), bail. Empty enemy panel for one or more ticks is the
  -- explicit, deliberate behavior — never show real teammates as enemies.
  if self.AllyFaction == nil then
    return
  end

  local _, _, _, _, numEnemies = GetBattlefieldTeamInfo(self.EnemyFaction)

  if numEnemies then
    self.Enemies:SetRealPlayerCount(numEnemies)
  end

  -- #1 ghost-frame gate (enemy side): if the enemy container is disabled for
  -- the current player-count bracket (user turned enemy frames off for this
  -- size), don't build enemy buttons. SetRealPlayerCount above recomputed
  -- self.Enemies.enabled via SelectPlayerCountProfile -> CheckEnableState. Tear
  -- down any existing enemy buttons (recycled to the pool) and bail before the
  -- parse / match / create work below. Placed BEFORE the signature gate so the
  -- teardown happens even when numEnemies is unchanged. Harvesting is
  -- unaffected: HarvestPlayerHistory reads the scoreboard (GetScoreInfo)
  -- directly, not these buttons. Reset the signature cache so a re-enable
  -- (bracket change) rebuilds. Inert when enemy frames are on (the common case).
  if not self.Enemies:ShouldBeEnabled() then
    -- Enemy frames off for this bracket: tear down enemy buttons ONCE. UBS fires
    -- on every combat event and this gate sits BEFORE the signature gate, so
    -- without a guard RemoveAllPlayersFromAllSources (re-inits all sources +
    -- runs the full AfterPlayerSourceUpdate -> SetPlayerCount ->
    -- SelectPlayerCountProfile pipeline) would run every tick -- wasted
    -- CPU/alloc in a busy epic BG. We CANNOT gate on #PlayerList: in combat the
    -- button removal (CreateOrRemovePlayerButtons) defers via
    -- QueueForUpdateAfterCombat, so PlayerList stays non-empty for the whole
    -- fight and a #PlayerList guard would re-wipe every tick anyway. But
    -- RemoveAll's InitializeAllPlayerSources runs SYNCHRONOUSLY (sources emptied
    -- immediately, even in combat) and the deferred button removal flushes on
    -- PLAYER_REGEN_ENABLED, so issuing the wipe ONCE is sufficient -- a flag
    -- tracks it. _lastEnemyCount stays nil while disabled (the gate returns
    -- before the `_lastEnemyCount = numEnemies` line), so a later re-enable
    -- rebuilds via the signature gate. The flag is cleared on the enabled path
    -- just below, so a later disable re-tears-down.
    if not self.Enemies._disabledTeardownDone then
      self.Enemies:RemoveAllPlayersFromAllSources()
      self._lastEnemyCount = nil
      self.Enemies._disabledTeardownDone = true
    end
    return
  end
  self.Enemies._disabledTeardownDone = nil

  -- Signature gate: UBS fires constantly during combat because damage /
  -- healing / killing blows / bases assaulted / etc. churn — but we don't
  -- display any of that. The only scoreboard change we care about is the
  -- roster: how many enemies are on the team. If that hasn't changed, the
  -- button list is already correct and all the parsing / matching /
  -- creation below is redundant work. Skip.
  -- First run has nil cache → proceeds. Nil numEnemies (API hiccup) also
  -- proceeds so we don't get stuck if the API briefly misbehaves.
  if numEnemies and self._lastEnemyCount == numEnemies then
    return
  end
  self._lastEnemyCount = numEnemies

  local battlefieldScores = {}
  local numScores = GetNumBattlefieldScores()
  for i = 1, numScores do
    local score = parseBattlefieldScore(i)
    if score then
      table.insert(battlefieldScores, score)
    end
  end

  -- Merc-detection loop removed: AllyFaction is now derived authoritatively
  -- from the user's own scoreboard row via C_PvP.GetScoreInfoByPlayerGuid
  -- earlier in this function. info.faction already returns the user's
  -- TEAM number for this match (merc-safe). Name-based merc-detection was
  -- both redundant and unreliable (silently skipped for secret names).

  -- Wipe the scoreboard source and rebuild from current rows. The
  -- mark-and-sweep in AfterPlayerSourceUpdate (status 1/2 cycle) handles
  -- both additions and removals — buttons whose scoreboard row disappeared
  -- this tick stay at status 2 and get cleaned up by CreateOrRemovePlayerButtons.
  --
  -- The old "never-shrink" guard (`newEnemyCount >= currentEnemyButtons`)
  -- was added to prevent enemies vanishing on transient scoreboard blips
  -- when names were SecretInActivePvPMatch. Post-12.0.5, PVPScoreInfo.name
  -- is NeverSecret, so scoreboard rows reliably populate. The signature
  -- gate above (GetBattlefieldTeamInfo count) already short-circuits
  -- redundant ticks, making the shrink guard both unnecessary and harmful —
  -- it permanently prevented removal of leavers.
  BattleGroundEnemies.Enemies:BeforePlayerSourceUpdate(self.consts.PlayerSources.Scoreboard)

  for i = 1, #battlefieldScores do
    local score = battlefieldScores[i]

    local faction = score.faction
    local name = score.name
    local classToken = score.classToken

    -- Allies are driven exclusively by GROUP_ROSTER_UPDATE (raidN/partyN
    -- tokens). Scoreboard is enemy-only here.
    if faction and name and classToken and faction == self.EnemyFaction then
      BattleGroundEnemies.Enemies:AddPlayerToSource(self.consts.PlayerSources.Scoreboard, score)
    end
  end

  BattleGroundEnemies.Enemies:AfterPlayerSourceUpdate()

  -- Re-scan orb/flag carriers after buttons are refreshed. Covers mid-match
  -- joiners (whose per-button PLAYER_ENTERING_WORLD fired before buttons
  -- existed) and scoreboard shuffles (button identities may have changed).
  -- Idempotent: updates ArenaIDToPlayerButton via the matcher.
  if self.RefreshObjectiveCarriers then
    self:RefreshObjectiveCarriers()
  end
end

function BattleGroundEnemies:GROUP_ROSTER_UPDATE()
  -- Only maintain the ally roster while actually inside a BG/arena instance.
  -- We gate on IsInInstance() — GROUND TRUTH — rather than self.enabled, which
  -- can lag or get stuck true across the leave transition and let the
  -- unconditional self-add (below) rebuild the hidden self-button in the
  -- world/city. Outside an instance there is nothing to display, so skip the
  -- whole build. Test mode runs in the world but drives a fake roster through
  -- this function, so allow it. Enable() re-fires this on entry so allies
  -- populate; Disable() tears the roster down on exit. Also no-ops the
  -- permanently-registered GROUP_ROSTER_UPDATE / PARTY_LEADER_CHANGED events
  -- while in the world.
  local _, instanceType = IsInInstance()
  if instanceType ~= "pvp" and instanceType ~= "arena" and not self:IsTestmodeActive() then
    return
  end
  self.Allies:BeforePlayerSourceUpdate(self.consts.PlayerSources.GroupMembers)
  self.Allies.groupLeader = nil
  self.Allies.assistants = {}

  --IsInGroup returns true when user is in a Raid and In a 5 man group

  -- GetRaidRosterInfo also works when in a party (not raid) but i am not 100% sure how the party unitID maps to the index in GetRaidRosterInfo()

  local numGroupMembers = GetNumGroupMembers()
  self.Allies:SetRealPlayerCount(numGroupMembers)

  local addedCount = 0

  -- Capture the user's own raid role so we can pass it to the explicit
  -- self-add below (the raid loop skips self, but GetRaidRosterInfo is
  -- the only source for raid-assigned MAINTANK / MAINASSIST).
  local selfRaidRole = nil

  -- #1 ghost-frame gate: only BUILD ally buttons when the ally container is
  -- enabled for the current player-count bracket. We use ShouldBeEnabled()
  -- (config-derived) NOT self.Allies.enabled, because the latter LAGS in combat
  -- (mainframe:Enable / ApplyPlayerCountProfileSettings defer past
  -- InCombatLockdown), which would make an in-combat instance entry / reload
  -- skip the build and leave allies empty. SetRealPlayerCount above already ran
  -- SelectPlayerCountProfile, which sets playerType/playerCountConfig
  -- synchronously (not combat-deferred), so ShouldBeEnabled is correct here.
  -- When friendly frames are off for this size we skip every AddGroupMember
  -- below. The GroupMembers source then stays
  -- empty and the AfterPlayerSourceUpdate further down tears any existing ally
  -- buttons back into the pool -- no "ghost frames", and the central
  -- UNIT_HEALTH/AURA/POWER dispatch finds an empty ally roster (zero work on
  -- hidden frames). Everything else still runs: HarvestRaidRoster (reads
  -- GetRaidRosterInfo, not buttons), the arena trinket refresh (which also
  -- updates ENEMY cooldowns), and the leader/assist flags below.
  local buildAllies = self.Allies:ShouldBeEnabled()

  if buildAllies then
    if IsInRaid() then
      for i = 1, numGroupMembers do -- the player itself only shows up here when he is in a raid
        local name, rank, subgroup, level, localizedClass, classToken, zone, online, isDead, role, isML, combatRole =
          GetRaidRosterInfo(i)

        -- Canonicalize the GetRaidRosterInfo name so it can be compared with
        -- UserDetails.PlayerName (canonical post-refactor). For same-realm
        -- members (always true for the user themselves) GetRaidRosterInfo
        -- returns short "Name"; UserDetails.PlayerName is "Name-Realm". The
        -- old direct compare would have silently missed self-identification
        -- after the canonicalization refactor.
        if type(name) == "string" and self:CanonicalName(name) == self.UserDetails.PlayerName then
          selfRaidRole = role
        elseif type(name) == "string" and rank and classToken then
          -- `role` is the 10th return: "MAINTANK", "MAINASSIST", or "" for
          -- regular members. Pass it through so the sort comparator can
          -- put MT/MA tiers before plain TANK.
          self.Allies:AddGroupMember(name, rank == 2, rank == 1, classToken, "raid" .. i, role)
          addedCount = addedCount + 1
        end
      end
    else
      -- we are in a party, 5 man group — no raid-assigned roles exist here.
      for i = 1, numGroupMembers do
        local unitID = "party" .. i
        local name = GetUnitName(unitID, true)

        local classToken = select(2, UnitClass(unitID))

        if type(name) == "string" and classToken then
          self.Allies:AddGroupMember(name, UnitIsGroupLeader(unitID), UnitIsGroupAssistant(unitID), classToken, unitID)
          addedCount = addedCount + 1
        end
      end
    end
  end

  self.UserDetails.isGroupLeader = UnitIsGroupLeader("player")
  self.UserDetails.isGroupAssistant = UnitIsGroupAssistant("player")
  if buildAllies then
    self.Allies:AddGroupMember(
      self.UserDetails.PlayerName,
      self.UserDetails.isGroupLeader,
      self.UserDetails.isGroupAssistant,
      self.UserDetails.PlayerClass,
      "player",
      selfRaidRole
    )
  end
  self.Allies:AfterPlayerSourceUpdate()
  self.Allies:UpdateAllUnitIDs()

  -- unitIDs are now assigned — refresh raid target icons on ally buttons
  if self.Allies.Players then
    for _, allyButton in pairs(self.Allies.Players) do
      allyButton:UpdateRaidTargetIcon()
    end
  end

  -- unitIDs are now assigned — refresh trinket icons if we're in an arena.
  local _, instanceType = IsInInstance()
  if instanceType == "arena" then
    self:ARENA_COOLDOWNS_UPDATE()
  end

  -- Retry if some group members had nil data (still loading into the instance).
  -- GetRaidRosterInfo / GetUnitName / UnitGUID can return nil or secret values
  -- for members who haven't loaded yet, and GROUP_ROSTER_UPDATE does not re-fire
  -- when they finish loading.
  --
  -- Count ACTUAL buttons in self.Allies.Players (source of truth), not the
  -- outer-loop addedCount. AddGroupMember has an internal short-circuit on
  -- nil/secret GUIDs (Mainframe.lua guard in AddGroupMember) that can silently
  -- drop a member even when the outer name+classToken guard passed — so
  -- addedCount would claim success while the button is missing. Common in
  -- arena gate phase where UnitGUID("party1") returns nil before reveal.
  local actualAllies = 0
  for _ in pairs(self.Allies.Players or {}) do
    actualAllies = actualAllies + 1
  end
  if buildAllies and actualAllies < numGroupMembers and not self.betweenRounds then
    if not self.allyRosterRetryTimer then
      local retries = 0
      self.allyRosterRetryTimer = C_Timer.NewTicker(1, function()
        retries = retries + 1
        self:GROUP_ROSTER_UPDATE()
        -- The recursive call may have already cancelled the timer (all members found),
        -- so guard before accessing it again.
        if self.allyRosterRetryTimer and retries >= 30 then
          self.allyRosterRetryTimer:Cancel()
          self.allyRosterRetryTimer = nil
        end
      end)
    end
  else
    -- All members found, cancel any pending retry
    if self.allyRosterRetryTimer then
      self.allyRosterRetryTimer:Cancel()
      self.allyRosterRetryTimer = nil
    end
  end

  -- Harvest non-secret identity attrs from the raid roster into PlayerHistory.
  -- Self-gates on IsInPvPInstance; cheap no-op when called outside a BG.
  -- Fires on every GROUP_ROSTER_UPDATE (initial join + every late-joiner /
  -- leaver) so we capture data before anyone DCs or before end-of-match.
  if self.HarvestRaidRoster then
    self:HarvestRaidRoster()
  end
end

BattleGroundEnemies.PARTY_LEADER_CHANGED = BattleGroundEnemies.GROUP_ROSTER_UPDATE

--Fires when the player logs in, /reloads the UI or zones between map instances. Basically whenever the loading screen appears.
-- function BattleGroundEnemies:PVP_MATCH_STATE_CHANGED()
--   if C_PvP and C_PvP.GetActiveMatchState and C_PvP.GetActiveMatchState() == (Enum and Enum.PvPMatchState and Enum.PvPMatchState.StartUp or 2) then
--     print("[BGEF debug] PVP_MATCH_STATE_CHANGED (StartUp) GetBattlefieldArenaFaction()=",
--       GetBattlefieldArenaFaction and GetBattlefieldArenaFaction())
--   end
-- end

function BattleGroundEnemies:PLAYER_ENTERING_WORLD()
  -- print("[BGEF debug] PLAYER_ENTERING_WORLD GetBattlefieldArenaFaction()=",
  --   GetBattlefieldArenaFaction and GetBattlefieldArenaFaction())

  -- TargetScanTicker is now started/stopped by Enable()/Disable(), invoked
  -- via CheckEnableState below. Don't start it here unconditionally —
  -- otherwise it would be created on every world load (including non-PvP
  -- zones) and stay alive until the next BG.

  if self.states.testmodeActive then
    self:DisableTestMode()
  end

  self:ClearPIDCaches()
  wipe(self.ArenaIDToPlayerButton)
  self.Enemies:RemoveAllPlayersFromAllSources()
  -- Allies are roster-driven (GROUP_ROSTER_UPDATE); never sourced from scoreboard.
  -- Reset UBS signature cache so the first UBS of this match always processes.
  self._lastEnemyCount = nil

  local prevInstanceType = self.cachedInstanceType
  local _, zone = IsInInstance()
  self.cachedInstanceType = zone

  -- Detect if we just crossed a BG/arena boundary (entering OR leaving).
  -- PLAYER_ENTERING_WORLD also fires for mid-match transitions like
  -- vehicle phases or /reload — those should NOT wipe faction state since
  -- we're still in the same match and the cached value is valid.
  local enteringPvP = (zone == "pvp" or zone == "arena") and prevInstanceType ~= zone
  local leavingPvP = (prevInstanceType == "pvp" or prevInstanceType == "arena") and zone ~= prevInstanceType
  if enteringPvP or leavingPvP then
    -- Clear stale faction cache from the previous match. UBS handles
    -- faction derivation now; AllyFaction stays nil until peer-validated.
    self.AllyFaction = nil
    self.EnemyFaction = nil
    -- Grace period before UBS attempts validation. The scoreboard isn't
    -- usually populated enough in the first ~3 seconds for the
    -- peer-cross-check to succeed, so polling earlier is just wasted
    -- work. A C_Timer.After sets the "elapsed" flag once; UBS gates its
    -- validation block on that flag. On leave-PvP we cancel any pending
    -- timer and clear the flag so a subsequent re-entry starts fresh.
    if self._pvpGraceTimer then
      self._pvpGraceTimer:Cancel()
      self._pvpGraceTimer = nil
    end
    self._pvpGracePeriodElapsed = false
    if enteringPvP then
      self._pvpGraceTimer = C_Timer.NewTimer(3, function()
        self._pvpGracePeriodElapsed = true
        self._pvpGraceTimer = nil
      end)
      -- Reset the per-side "no custom profile covers this size" warning throttle
      -- so SelectPlayerCountProfile's gap hint can fire once for this new match.
      self.Allies._warnedNoCustomProfile = nil
      self.Enemies._warnedNoCustomProfile = nil
    end

    -- Stop the lobby diagnostic watchdog if it was running. It will get
    -- restarted by PVP_MATCH_STATE_CHANGED if we enter a new BG/arena lobby.
    -- if self._stopLobbyEnemyWatchdog then
    --   self:_stopLobbyEnemyWatchdog()
    -- end
  end

  if zone == "pvp" or zone == "arena" then
    -- AllyFaction is derived (and cross-validated) in UPDATE_BATTLEFIELD_SCORE.
    -- Don't pre-set it here — a single C_PvP.GetScoreInfoByPlayerGuid call
    -- this early in zone-in can return the wrong team number when the
    -- scoreboard isn't fully populated yet, and a wrong cached value would
    -- mis-bucket every teammate as an enemy until match end. UBS waits for
    -- a peer's scoreboard row to confirm; AllyFaction stays nil and the
    -- enemy panel stays empty until validation succeeds.

    if zone == "arena" then
      BattleGroundEnemies.states.real.isInArena = true
      -- Refresh trinket icons on zone-in. GROUP_ROSTER_UPDATE also does this but may
      -- fire before units are fully available; this catches the zone-in case cleanly.
      self:ARENA_COOLDOWNS_UPDATE()
    else
      BattleGroundEnemies.states.real.isInBattleground = true

      C_Timer.After(5, function() --Delay this check, since its happening sometimes that this data is not ready yet
        if C_PvP then
          self.states.real.isRatedBG = not not C_PvP.IsRatedBattleground and C_PvP.IsRatedBattleground()
          self.states.real.isSoloRBG = not not C_PvP.IsSoloRBG and C_PvP.IsSoloRBG()
        else
          self.states.real.isRatedBG = not not IsRatedBattleground and IsRatedBattleground()
          self.states.real.isSoloRBG = false
        end

        self:UPDATE_BATTLEFIELD_SCORE() --trigger the function again because since 10.0.0 UPDATE_BATTLEFIELD_SCORE doesnt fire reguralry anymore and RequestBattlefieldScore doesnt trigger the event

        -- Re-settle the ALLY bracket now that the load screen is done. The enemy
        -- bracket is recomputed constantly by UBS (above), but the ally bracket
        -- is only recomputed by GROUP_ROSTER_UPDATE, which does NOT re-fire when
        -- members finish loading -- so a premature first read on entry
        -- (GetNumGroupMembers()==0 and/or GetInstanceInfo not ready) could stick
        -- the ally container at "no profile" with frames missing, with nothing
        -- to recover it (the retry ticker is gated on the ally being enabled,
        -- which the stuck "no profile" makes false). By now the raid roster and
        -- instance info are stable: force the bracket re-eval, then rebuild.
        self.Allies:SelectPlayerCountProfile(true)
        self:GROUP_ROSTER_UPDATE()
      end)
    end
  else
    self.states.real.isInArena = false
    self.states.real.isInBattleground = false
    self.states.real.isSoloRBG = false
    self.states.real.isRatedBG = false
    -- Roster teardown on leaving an instance is handled in Disable() (reached
    -- via CheckEnableState below), which always runs here — more reliable than
    -- gating on leavingPvP.
    --
    -- Cosmetic cleanup: force BOTH brackets to re-evaluate now that we're out of
    -- the instance, so the HUD reads "no profile" out of an instance instead of a
    -- stale in-match value (e.g. enemy "16-40", ally "6-15"). Counts were already
    -- zeroed (RemoveAllPlayersFromAllSources at the top of this handler), but
    -- SetPlayerCount's change-guard no-ops a same-value 0->0, so the brackets
    -- don't update on their own. BOTH sides need the explicit force:
    --   * the enemy's normal re-settle (UBS) doesn't fire in the city, and
    --   * the ally's normal re-settle (GROUP_ROSTER_UPDATE) EARLY-RETURNS out of
    --     an instance via its IsInInstance gate -- so it never runs here either.
    -- SelectPlayerCountProfile out of an instance hits the not-in-pvp branch ->
    -- NoActivePlayercountProfile -> "no profile".
    self.Enemies:SelectPlayerCountProfile(true)
    self.Allies:SelectPlayerCountProfile(true)
  end

  self:CheckEnableState()
  self:UpdateMapID()
  self:ToggleArenaFrames()
  self:ToggleRaidFrames()
end
