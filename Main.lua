---@type string
local AddonName = ...
---@class Data
local Data = select(2, ...)
if not Data.L then
  Data.L = setmetatable({}, { __index = function(_, k) return k end })
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
local print = print
local table_insert = table.insert
local table_remove = table.remove
local time = time
local type = type
local unpack = unpack

local C_PvP = C_PvP
local C_Spell = C_Spell
local CreateFrame = CreateFrame
local CTimerNewTicker = C_Timer.NewTicker
local GetArenaOpponentSpec = GetArenaOpponentSpec
local GetBattlefieldArenaFaction = GetBattlefieldArenaFaction
local GetBattlefieldScore = GetBattlefieldScore
local GetBattlefieldTeamInfo = GetBattlefieldTeamInfo
local GetBestMapForUnit = C_Map.GetBestMapForUnit
local GetNumBattlefieldScores = GetNumBattlefieldScores
local GetNumGroupMembers = GetNumGroupMembers
local GetNumSpellTabs = C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines or GetNumSpellTabs
local GetRaidRosterInfo = GetRaidRosterInfo
local GetSpecializationInfoByID = GetSpecializationInfoByID
local GetSpellBookItemName = C_SpellBook and C_SpellBook.GetSpellBookItemName or GetSpellBookItemName
local GetSpellName = C_Spell and C_Spell.GetSpellName or GetSpellName
local GetSpellTabInfo = GetSpellTabInfo
local GetSpellTexture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
local C_SpellBook = C_SpellBook
local GetTime = GetTime
local GetUnitName = GetUnitName
local InCombatLockdown = InCombatLockdown
local IsInBrawl = C_PvP.IsInBrawl
local IsInInstance = IsInInstance
local IsInRaid = IsInRaid
local RequestBattlefieldScoreData = RequestBattlefieldScoreData
local RequestCrowdControlSpell = C_PvP.RequestCrowdControlSpell
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
local IsTBCC = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC
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

if not GetUnitName then
  GetUnitName = function(unit, showServerName)
    local name, server = UnitName(unit)

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
end

LSM:Register("font", "PT Sans Narrow Bold", [[Interface\AddOns\BattleGroundEnemiesFixed\Fonts\PT Sans Narrow Bold.ttf]])
LSM:Register("statusbar", "UI-StatusBar", "Interface\\TargetingFrame\\UI-StatusBar")

---@class BattleGroundEnemies: frame
BattleGroundEnemies = CreateFrame("Frame", "BattleGroundEnemies", UIParent)
BattleGroundEnemies.Counter = {}
BattleGroundEnemies.PlayerGUIDs = {}
BattleGroundEnemies.DuplicateLog = {}

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

-- Helper function to get corrected max players from GetInstanceInfo()
local function GetCorrectedMaxPlayers()
  -- Blitz (Solo RBG) is always 8v8 regardless of map
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

local playerSpells

---@class bgeState
---@field WOW_PROJECT_ID number
---@field isInArena boolean
---@field isInBattleground boolean
---@field currentMapId number|boolean
---@field isRatedBG boolean
---@field isSoloRBG boolean

BattleGroundEnemies.scoreboardFrozen = false

BattleGroundEnemies.states = {
  editmodeActive = false,
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
  if self:IsTestmodeOrEditmodeActive() then
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
  return Data.BattlegroundspezificBuffs[states.currentMapId], Data.BattlegroundspezificDebuffs[states.currentMapId]
end

function BattleGroundEnemies:IsTestmodeOrEditmodeActive()
  return self.states.testmodeActive or self.states.editmodeActive
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

function BattleGroundEnemies:PLAYER_TARGET_CHANGED()
  if self.UserButton then
    self.UserButton:UpdateTarget()
  end
end
BattleGroundEnemies:RegisterEvent("PLAYER_TARGET_CHANGED")

BattleGroundEnemies:SetScript("OnEvent", function(self, event, ...)
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

Data.FoundAuras = {
  HELPFUL = {
    foundPlayerAuras = {},
    foundNonPlayerAuras = {},
  },
  HARMFUL = {
    foundPlayerAuras = {},
    foundNonPlayerAuras = {},
    foundDRAuras = {},
  },
}

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

  local mapIDs = {}
  for mapID, data in pairs(Data.BattlegroundspezificDebuffs) do
    table.insert(mapIDs, mapID)
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

local function fakePlayersEditmodeTicker() end

local function setupFakePlayersEditmodeTicker()
  createFakePlayersTicker(1, fakePlayersEditmodeTicker)
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
  if BattleGroundEnemies.states.editmodeActive then
    BattleGroundEnemies:DisableEditmode()
  end
  if BattleGroundEnemies.states.testmodeActive then --disable testmode
    BattleGroundEnemies:DisableTestMode()
  else --enable Testmode
    BattleGroundEnemies:EnableTestMode()
  end
end

function BattleGroundEnemies:EnableEditmode()
  if InCombatLockdown() then
    return BattleGroundEnemies:Information(L.ErrorTestmodeInCombat)
  end
  self.states.editmodeActive = true
  self:SetupTestmode()
  self:OnEditmodeEnabled()

  BattleGroundEnemies.EditMode.EditModeManager:OpenEditmode()
  self:Information(L.EditmodeEnabled)
  self:Information(L.EditModeIntroduction)
end

function BattleGroundEnemies:UpdateAllButtonsModuleSettings()
  for _, mainFrame in pairs({ self.Allies, self.Enemies }) do
    if mainFrame and mainFrame.Players then
      for _, playerButton in pairs(mainFrame.Players) do
        if playerButton.ApplyModuleSettings then
          playerButton:ApplyModuleSettings()
        end
      end
    end
  end
end

function BattleGroundEnemies:OnEditmodeEnabled()
  self.Allies:OnEditmodeEnabled()
  self.Enemies:OnEditmodeEnabled()
  self:UpdateAllButtonsModuleSettings()
end

function BattleGroundEnemies:DisableEditmode()
  self.states.editmodeActive = false
  self:Information(L.EditmodeDisabled)
  self.Allies:OnEditmodeDisabled()
  self.Enemies:OnEditmodeDisabled()
  self:UpdateAllButtonsModuleSettings()
  BattleGroundEnemies.EditMode.EditModeManager:CloseEditmode()
  self:CheckEnableState()
end

function BattleGroundEnemies.ToggleEditmode()
  if BattleGroundEnemies.states.testmodeActive then
    BattleGroundEnemies:DisableTestMode()
  end
  if BattleGroundEnemies.states.editmodeActive then --disable testmode
    BattleGroundEnemies:DisableEditmode()
  else --enable Testmode
    BattleGroundEnemies:EnableEditmode()
  end
end

function BattleGroundEnemies:DisableTestOrEditmode()
  if self.states.editmodeActive then
    return self:DisableEditmode()
  end
  if self.states.testmodeActive then
    return self:DisableTestMode()
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

function BattleGroundEnemies:GetDebugFrame()
  if not self.DebugFrame then
    local f = CreateFrame("ScrollingMessageFrame", "BGE_DebugFrame", UIParent, "BackdropTemplate")
    f:SetSize(600, 300)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetMaxLines(2500)
    f:SetFontObject(ChatFontNormal)
    f:SetJustifyH("LEFT")
    f:SetFading(false)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
      if delta > 0 then
        self:ScrollUp()
      else
        self:ScrollDown()
      end
    end)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
    f:SetBackdropColor(0, 0, 0, 0.8)
    f:Show()
    self.DebugFrame = f
  end
  return self.DebugFrame
end

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
local BUTTON_UPDATE_PERIOD = 0.1

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
  if self.rosterCheckFrame then
    self.rosterCheckFrame:Hide()
  end
  stopFakePlayersTicker()
  StopButtonUpdateTicker()
  self.Allies:Disable()
  self.Enemies:Disable()
end

function BattleGroundEnemies:Enable()
  self.enabled = true

  self:RegisterEvents()
  StartButtonUpdateTicker()
  if BattleGroundEnemies:IsTestmodeOrEditmodeActive() then
    if self.states.editmodeActive then
      setupFakePlayersEditmodeTicker()
    else
      setupFakePlayersTestmodeTicker()
    end
    RequestFrame:Hide()
  else
    RequestFrame:Show()
    stopFakePlayersTicker()
    local matchState = C_PvP.GetActiveMatchState and C_PvP.GetActiveMatchState()
    if not self.states.real.isInArena and matchState and matchState < Enum.PvPMatchState.Engaged then
      self:ShowRosterCheck()
    elseif self.rosterCheckFrame then
      self.rosterCheckFrame:Hide()
    end
  end
  self.Allies:CheckEnableState()
  self.Enemies:CheckEnableState()
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
    PlayerName = UnitName("player"),
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

  self:SetupOptions()

  AceConfigDialog:SetDefaultSize("BattleGroundEnemies", 800, 700)

  AceConfigDialog:AddToBlizOptions("BattleGroundEnemies", "BattleGroundEnemies")

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
  AceConfigRegistry:NotifyChange("BattleGroundEnemies")
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
    if self:IsTestmodeOrEditmodeActive() then
      self:CreateFakePlayers()
    end
    if self.states.editmodeActive then
      self:OnEditmodeEnabled()
      BattleGroundEnemies.EditMode.EditModeManager:OpenEditmode()
    end
    playerCountChangedTimer = nil
  end, 1)
end

-- ApplyAllSettings moved up

local function stringifyMultitArgs(...)
  local args = { ... }
  local text = ""

  for i = 1, #args do
    text = text .. " " .. tostring(args[i])
  end
  return text
end

local function getTimestamp()
  local timestampFormat = "[%I:%M:%S] " --timestamp format
  local stamp = BetterDate(timestampFormat, time())
  return stamp
end

local sentDebugMessages = {}
function BattleGroundEnemies:OnetimeDebug(...)
  local message = table.concat({ ... }, ", ")
  if sentDebugMessages[message] then
    return
  end
  sentDebugMessages[message] = true
  self:Debug(...)
end

function BattleGroundEnemies:Debug(...)
  if not self.db then
    return
  end
  if not self.db.profile then
    return
  end
  if not self.db.profile.Debug then
    return
  end

  self:OnetimeInformation(
    "Debugging is enabled. Depending on the amount of messages or debug settings it can cause decrased performance. Please disable it after you are done debugging."
  )

  if self.db.profile.DebugToChat then
    if not self.DebugFrame then
      self.DebugFrame = self:GetDebugFrame()
    end

    local text
    if self.db.profile.DebugToChat_AddTimestamp then
      text = stringifyMultitArgs(getTimestamp(), ...)
    else
      text = stringifyMultitArgs(...)
    end

    self.DebugFrame:AddMessage(text)
  end

  if self.db.profile.DebugToSV then
    self.db.profile.log = self.db.profile.log or {}
    local t = { ... }

    table.insert(self.db.profile.log, { [getTimestamp()] = t })
  end
end

function BattleGroundEnemies:EnableDebugging()
  self.db.profile.Debug = true
  self:NotifyChange()
end

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

  local fullName
  local ok2 = pcall(function()
    if name then
      name = tostring(name)
    end
    if server then
      server = tostring(server)
    end

    if server and server ~= "" then
      fullName = name .. "-" .. server
    else
      fullName = name
    end
  end)

  return ok2 and fullName or nil
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
    -- LibRaces:GetRaceToken returns names that may differ from C_CreatureInfo clientFileString.
    -- Add aliases so lookup works with either format.
    RaceTokenToID["Undead"] = RaceTokenToID["Scourge"] or 5 -- LibRaces says "Undead", client says "Scourge"
    RaceTokenToID["Earthen"] = RaceTokenToID["EarthenDwarf"] or 85 -- LibRaces says "Earthen", client may say "EarthenDwarf"
  end

  -- Collapse faction-variant race IDs to a single canonical ID
  local RaceCollapseMap = {
    [24] = 25, -- Pandaren (Neutral)
    [26] = 25, -- Pandaren (Horde)
    [70] = 52, -- Dracthyr (Horde)
    [84] = 85, -- Earthen (Horde)
    [91] = 86, -- Harronir (Alt ID)
  }

  -- Cache for GetPlayerInfoByGUID results (race/gender never change per GUID)
  local guidInfoCache = {}

  local function GetCachedPlayerInfo(guid)
    local cached = guidInfoCache[guid]
    if cached then
      return cached[1], cached[2]
    end
    local _, _, _, englishRaceName, gender = GetPlayerInfoByGUID(guid)
    -- Only cache successful results; nil means the client hasn't seen this player yet
    -- and may return valid data on a future call
    if gender then
      guidInfoCache[guid] = { englishRaceName, gender }
    end
    return englishRaceName, gender
  end

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
    -- Race: use PlayerRace from scoreboard (LibRaces token, always available)
    -- This matches C_CreatureInfo.GetRaceInfo().clientFileString format (e.g. "BloodElf")
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

  -- Cross-tick sticky cache: prevents PID oscillation between scan cycles.
  -- Once a unitID resolves to a button, it stays pinned until:
  --   1) ClearPIDCaches (roster change)
  --   2) UNIT_TARGET fires for the source unit (target changed)
  --   3) Class validation fails (definitely a different player)
  local stickyPIDCache = {}

  function BattleGroundEnemies:ClearPIDCaches()
    wipe(guidInfoCache)
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

  -- @param playerType: "Enemies" or "Allies" - specifies which player table to search
  -- @param ignoreExistingArena: if true, consider ALL buttons even those with arena tokens
  --   (used for Kotmogu orb detection where arena tokens shift between players)
  function BattleGroundEnemies:GetPlayerbuttonByUnitID(unitID, playerType, ignoreExistingArena)
    if not unitID or not UnitExists(unitID) then
      return nil
    end

    -- Reject units of the wrong side to prevent PID match cross-contamination.
    -- In BGs (including cross-faction Blitz), use UnitIsFriend/UnitIsEnemy which
    -- correctly reflect team assignment regardless of actual faction.
    -- In arena, skip guards entirely — arena tokens use ArenaIDToPlayerButton,
    -- and target/focus use structural ally checks in the event handlers.
    local _, instanceType = IsInInstance()
    if instanceType == "pvp" then
      if playerType == "Enemies" and UnitIsFriend("player", unitID) then
        return nil
      end
      if playerType == "Allies" and UnitIsEnemy("player", unitID) then
        return nil
      end
    end

    -- For arena tokens, check the direct ArenaIDToPlayerButton mapping first.
    -- This is authoritative (set by UpdateArenaPlayers from CreateArenaEnemies data)
    -- and avoids ambiguity when multiple enemies share the same class.
    if playerType == "Enemies" and unitID:match("^arena%d+$") and self.ArenaIDToPlayerButton[unitID] then
      local arenaBtn = self.ArenaIDToPlayerButton[unitID]
      if not ignoreExistingArena then
        scanCycleCache[unitID] = arenaBtn
      end
      return arenaBtn
    end

    -- Check per-cycle cache (same unitID already resolved this scan tick)
    -- Skip cache when ignoreExistingArena is set (need fresh lookup for orb detection)
    if not ignoreExistingArena then
      local cached = scanCycleCache[unitID]
      if cached ~= nil then
        return cached or nil -- cached false means "no match found"
      end
    end

    -- Try GUID lookup first (fastest path, works out of combat).
    -- In combat UnitGUID returns a secret value, so pcall handles the taint.
    -- 12.0: Compound tokens (e.g. "arena1target") are rejected by UnitGUID.
    -- GOOD:
    -- - arena{N}
    -- - nameplate{N}
    -- - focus
    -- - target
    -- - targettarget
    -- - focustarget
    -- - mouseover
    -- - anyenemy
    -- - softenemy
    -- BAD:
    -- - raid{N}target
    -- - raidpet{N}target
    -- - nameplate{N}target
    -- - party{N}target
    -- - partypet{N}target
    -- - arena{N}target
    -- - arenapet{N}target
    -- - {N}target

    local okGUID, unitGUID = pcall(UnitGUID, unitID)
    if okGUID and unitGUID then
      local okLookup, _guidData = pcall(function()
        return self.PlayerGUIDs[unitGUID]
      end)
      if okLookup and _guidData then
        local _name = _guidData.name
        local guidButton = self[playerType].Players[_name]
        if guidButton and guidButton.PlayerType == playerType then
          if not ignoreExistingArena then
            scanCycleCache[unitID] = guidButton
          end
          return guidButton
        end
      end
    end

    local okName, unitName = pcall(GetUnitName, unitID, true)
    if okName and unitName then
      local okLookup, nameButton = pcall(function()
        return self[playerType].Players[unitName]
      end)
      if okLookup and nameButton then
        if not ignoreExistingArena then
          scanCycleCache[unitID] = nameButton
        end
        return nameButton
      end
    end

    -- Check cross-tick sticky cache (prevents PID oscillation between scan cycles).
    -- Only used when GUID lookup failed (combat taint, compound tokens, etc.).
    -- Validates that the cached button still exists in the roster and class still matches.
    local sticky = stickyPIDCache[unitID]
    if sticky then
      local stickyValid = false
      if
        sticky.button
        and self[playerType].Players
        and self[playerType].Players[sticky.button.PlayerName] == sticky.button
      then
        -- Button still in roster — verify class still matches the unit
        local okClass, _, classToken = pcall(UnitClass, unitID)
        if okClass and classToken and sticky.classToken == classToken then
          stickyValid = true
        elseif not okClass or not classToken then
          -- Can't verify class (combat taint on compound token) — trust the sticky cache
          -- This is the exact scenario that causes oscillation: PID re-resolves differently
          -- each tick because UnitClass/UnitGUID fail intermittently in combat.
          stickyValid = true
        end
      end
      if stickyValid then
        if not ignoreExistingArena then
          scanCycleCache[unitID] = sticky.button
        end
        return sticky.button
      else
        stickyPIDCache[unitID] = nil
      end
    end

    -- Unique-class match: if only one button on this side has the unit's class, it's unambiguous.
    -- If multiple share the class, narrow by race (class+race unique match).
    local hasMultipleCandidates = false
    local okClass, _, unitClassToken = pcall(UnitClass, unitID)
    if okClass and unitClassToken and self[playerType].Players then
      local match = nil
      local count = 0
      for _, button in pairs(self[playerType].Players) do
        if not ignoreExistingArena and button.UnitIDs and button.UnitIDs.Arena then
        -- Already identified via arena token, skip
        elseif button.PlayerDetails and button.PlayerDetails.PlayerClass == unitClassToken then
          count = count + 1
          match = button
        end
      end
      if count == 1 and match then
        scanCycleCache[unitID] = match
        stickyPIDCache[unitID] = {
          button = match,
          classToken = unitClassToken,
        }
        return match
      end
      hasMultipleCandidates = count > 1
    end

    -- Class+race unique match: disambiguate same-class candidates by race.
    -- Uses first return of UnitRace (localized name) which always returns the real race,
    -- even in mercenary mode (second return / raceID are disguised).
    local unitRace = nil
    if hasMultipleCandidates then
      local okRace, unitRaceLocalized = pcall(UnitRace, unitID)
      if okRace and unitRaceLocalized then
        unitRace = unitRaceLocalized
        local match = nil
        local count = 0
        for _, button in pairs(self[playerType].Players) do
          if not ignoreExistingArena and button.UnitIDs and button.UnitIDs.Arena then
          -- Already identified via arena token, skip
          elseif button.PlayerDetails and button.PlayerDetails.PlayerClass == unitClassToken then
            if (button.PlayerDetails.PlayerRace or "") == unitRace then
              count = count + 1
              match = button
            end
          end
        end
        if count == 1 and match then
          scanCycleCache[unitID] = match
          stickyPIDCache[unitID] = {
            button = match,
            classToken = unitClassToken,
          }
          return match
        end
      end
    end

    -- Gender disambiguation: class+race+gender if race available, class+gender otherwise.
    if hasMultipleCandidates then
      local okGender, unitGender = pcall(UnitSex, unitID)
      if okGender and unitGender and unitGender > 0 then
        local match = nil
        local count = 0
        for _, button in pairs(self[playerType].Players) do
          if not ignoreExistingArena and button.UnitIDs and button.UnitIDs.Arena then
          -- Already identified via arena token, skip
          elseif
            button.PlayerDetails
            and button.PlayerDetails.PlayerClass == unitClassToken
            and button.PlayerDetails.gender == unitGender
          then
            local dominated = true
            if unitRace then
              dominated = ((button.PlayerDetails.PlayerRace or "") == unitRace)
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
          scanCycleCache[unitID] = match
          stickyPIDCache[unitID] = {
            button = match,
            classToken = unitClassToken,
          }
          return match
        end
      end
    end

    -- Honor level disambiguation: class + race/gender/honor when available.
    if hasMultipleCandidates then
      local okHonor, unitHonor = pcall(UnitHonorLevel, unitID)
      if okHonor and unitHonor then
        local okGender, unitGender = pcall(UnitSex, unitID)
        local firstMatch = nil
        local count = 0
        for _, button in pairs(self[playerType].Players) do
          if not ignoreExistingArena and button.UnitIDs and button.UnitIDs.Arena then
          -- Already identified via arena token, skip
          elseif
            button.PlayerDetails
            and button.PlayerDetails.PlayerClass == unitClassToken
            and button.PlayerDetails.honorLevel == unitHonor
          then
            local dominated = true
            if dominated and unitRace then
              dominated = ((button.PlayerDetails.PlayerRace or "") == unitRace)
            end
            if dominated and okGender and unitGender and unitGender > 0 then
              dominated = (button.PlayerDetails.gender == unitGender)
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
          scanCycleCache[unitID] = firstMatch
          stickyPIDCache[unitID] = {
            button = firstMatch,
            classToken = unitClassToken,
          }
          return firstMatch
        end
      end
    end

    -- Guild disambiguation: class + race/gender/honor/guild when available.
    if hasMultipleCandidates then
      local okGuild, unitGuild = pcall(GetGuildInfo, unitID)
      if okGuild and unitGuild then
        local okGender, unitGender = pcall(UnitSex, unitID)
        local okHonor, unitHonor = pcall(UnitHonorLevel, unitID)
        local match = nil
        local count = 0
        for _, button in pairs(self[playerType].Players) do
          if not ignoreExistingArena and button.UnitIDs and button.UnitIDs.Arena then
          -- Already identified via arena token, skip
          elseif
            button.PlayerDetails
            and button.PlayerDetails.PlayerClass == unitClassToken
            and button.PlayerDetails.GuildName == unitGuild
          then
            local dominated = true
            if dominated and unitRace then
              dominated = ((button.PlayerDetails.PlayerRace or "") == unitRace)
            end
            if dominated and okGender and unitGender and unitGender > 0 then
              dominated = (button.PlayerDetails.gender == unitGender)
            end
            if dominated and okHonor and unitHonor then
              dominated = (button.PlayerDetails.honorLevel == unitHonor)
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
          scanCycleCache[unitID] = match
          stickyPIDCache[unitID] = {
            button = match,
            classToken = unitClassToken,
          }
          return match
        end
      end
    end

    -- Fallback: all disambiguation tiers exhausted, return first class match.
    if hasMultipleCandidates then
      for _, button in pairs(self[playerType].Players) do
        if not ignoreExistingArena and button.UnitIDs and button.UnitIDs.Arena then
        -- Already identified via arena token, skip
        elseif button.PlayerDetails and button.PlayerDetails.PlayerClass == unitClassToken then
          scanCycleCache[unitID] = button
          stickyPIDCache[unitID] = {
            button = button,
            classToken = unitClassToken,
          }
          return button
        end
      end
    end

    return nil
  end
end

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
        local ok2 = pcall(function()
          name = tostring(name)
          if server then
            server = tostring(server)
          end
          if issecretvalue and (issecretvalue(name) or (server and issecretvalue(server))) then
            return
          end
          if server and server ~= "" then
            targetName = name .. "-" .. server
          else
            targetName = name
          end
        end)
        if not ok2 then
          targetName = nil
        end
      end

      local allyBtn = targetName and self.Allies.Players and self:SafeGetPlayerButton(self.Allies.Players, targetName)

      if not allyBtn and not targetName then
        -- If first call failed, try without realm
        ok, name, server = pcall(GetUnitName, targetUnitID, false)
        if ok and name then
          local ok2 = pcall(function()
            name = tostring(name)
            -- Check if value is still secret after tostring
            if issecretvalue and issecretvalue(name) then
              return
            end
            targetName = name
          end)
          if not ok2 then
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
        local ok2 = pcall(function()
          name = tostring(name)
          if server then
            server = tostring(server)
          end
          if issecretvalue and (issecretvalue(name) or (server and issecretvalue(server))) then
            return
          end
          if server and server ~= "" then
            targetName = name .. "-" .. server
          else
            targetName = name
          end
        end)
        if not ok2 then
          targetName = nil
        end
      end

      local allyBtn = targetName and self.Allies.Players and self:SafeGetPlayerButton(self.Allies.Players, targetName)

      if not allyBtn and not targetName then
        -- If first call failed, try without realm
        ok, name, server = pcall(GetUnitName, targetUnitID, false)
        if ok and name then
          local ok2 = pcall(function()
            name = tostring(name)
            -- Check if value is still secret after tostring
            if issecretvalue and issecretvalue(name) then
              return
            end
            targetName = name
          end)
          if not ok2 then
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
  self.TargetScanTicker = C_Timer.NewTicker(0.25, function()
    if not self.enabled then
      return
    end
    self:ScanTargets()
  end)
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
  return self.Enemies.Players[name] or self.Allies.Players[name]
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
  -- Defer off the secure execution path to avoid tainting Blizzard UnitFrame
  C_Timer.After(0, function()
    self:PLAYER_TARGET_CHANGED_Deferred()
  end)
end

function BattleGroundEnemies:PLAYER_TARGET_CHANGED_Deferred()
  -- Clear stale scan-cycle cache for "target" so we do a fresh lookup
  -- (the previous ScanTargets tick may have cached a different/nil result)
  self:ClearScanCycleCache()

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
      local _, instanceType = IsInInstance()
      if instanceType == "pvp" and UnitIsFriend("player", "target") then
        isAlly = true
      end
    end
  end

  if isAlly then
    -- Ally target — look up in Allies.Players by name
    local targetName = GetUnitName("target", true)
    if targetName and self.Allies and self.Allies.Players then
      btn = self.Allies.Players[targetName]
      if not btn then
        targetName = GetUnitName("target", false)
        btn = self.Allies.Players[targetName]
      end
    end
  else
    -- Enemy target — check arena token mapping first, then PID matching
    local matchedArena = nil
    for i = 1, 5 do
      local arenaID = "arena" .. i
      if UnitIsUnit("target", arenaID) then
        matchedArena = arenaID
        btn = self.ArenaIDToPlayerButton[arenaID]
        break
      end
    end
    if not btn then
      btn = self:GetPlayerbuttonByUnitID("target", "Enemies")
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
  --self:Debug("playerButton focus", playerButton, GetUnitName("focus", true))
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
      local _, instanceType = IsInInstance()
      if instanceType == "pvp" and UnitIsFriend("player", "focus") then
        isAlly = true
      end
    end
  end

  if isAlly then
    -- Ally focus — look up in Allies.Players by name
    local focusName = GetUnitName("focus", true)
    if focusName and self.Allies and self.Allies.Players then
      btn = self.Allies.Players[focusName]
      if not btn then
        focusName = GetUnitName("focus", false)
        btn = self.Allies.Players[focusName]
      end
    end
  else
    -- Enemy focus — check arena token mapping first, then PID matching
    for i = 1, 5 do
      local arenaID = "arena" .. i
      if UnitIsUnit("focus", arenaID) then
        btn = self.ArenaIDToPlayerButton[arenaID]
        break
      end
    end
    if not btn then
      btn = self:GetPlayerbuttonByUnitID("focus", "Enemies")
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
-- In these BGs, arena tokens are only assigned to objective carriers
local function IsObjectiveBG(mapId)
  -- 417=Kotmogu, 2106=WSG, 726=Twin Peaks, 566=EOTS, 968=EOTS Rated, 2656=Deephaul Ravine
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

  -- Also check Allies (e.g. party1, raid2 getting CC'd)
  if not playerButton then
    playerButton = self:GetPlayerbuttonByUnitID(unitID, "Allies")
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
  local isAlly = (unitID == "player") or (unitID:match("^party%d") ~= nil) or (unitID:match("^raid%d") ~= nil)
  local isArenaEnemy = (unitID:match("^arena%d") ~= nil)

  if isAlly then
    local btn = self:GetPlayerbuttonByUnitID(unitID, "Allies")
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
  -- in the lobby just like enemies.
  if not playerButton then
    playerButton = self:GetPlayerbuttonByUnitID(unitID, "Allies")
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

    -- Also check allies (party/raid members using their trinket)
    if not playerButton then
      local allyButton = self:GetPlayerbuttonByUnitID(unitID, "Allies")
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
end

function BattleGroundEnemies:PLAYER_REGEN_DISABLED()
  self:DisableTestOrEditmode()
end

function BattleGroundEnemies:PlayerDead()
  self.states.userIsAlive = false
  -- Force all enemy frames to out-of-range alpha when user is dead
  if self.Enemies and self.Enemies.Players then
    for _, playerButton in pairs(self.Enemies.Players) do
      playerButton:UpdateRange(false, true)
    end
  end
end

function BattleGroundEnemies:PlayerAlive()
  -- Force all enemies to out-of-range so nothing appears lit up on resurrect.
  -- The ticker will naturally update range as we target/focus/see nameplates.
  if self.Enemies and self.Enemies.Players then
    for _, playerButton in pairs(self.Enemies.Players) do
      playerButton:UpdateRange(false, true)
    end
  end
  --recheck the targets of groupmembers
  for allyName, allyButton in pairs(self.Allies.Players) do
    allyButton:UpdateTarget()
  end
  self.states.userIsAlive = true
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
        local ok2 = pcall(function()
          name = tostring(name)
          if server then
            server = tostring(server)
          end
          if issecretvalue and (issecretvalue(name) or (server and issecretvalue(server))) then
            return
          end
          if server and server ~= "" then
            targetName = name .. "-" .. server
          else
            targetName = name
          end
        end)
        if not ok2 then
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
  -- Map IDs: 417=Kotmogu, 2106=WSG, 726=Twin Peaks, 566=EOTS, 968=EOTS Rated, 2656=Deephaul Ravine
  local states = self:GetActiveStates()
  local mapId = states and states.currentMapId
  if mapId == 417 or mapId == 2106 or mapId == 726 or mapId == 566 or mapId == 968 or mapId == 2656 then
    return
  end

  if #BattleGroundEnemies.Enemies.CurrentPlayerOrder > 0 or #BattleGroundEnemies.Allies.CurrentPlayerOrder > 0 then --this ensures that we checked for enemies and the flag carrier will be shown (if its an enemy)
    for i = 1, GetNumArenaOpponents() do
      local unitID = "arena" .. i
      self:Debug(unitID, UnitName(unitID))
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
  else
    C_Timer.After(1, function()
      self:UpdateArenaPlayers()
    end)
  end
end

local UpdateArenaPlayersTicker

--too avoid calling UpdateArenaPlayers too many times within a second
function BattleGroundEnemies:DebounceUpdateArenaPlayers()
  self:Debug("DebounceUpdateArenaPlayers")
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
  self:Debug("CheckForArenaEnemies")

  -- returns valid data on PLAYER_ENTERING_WORLD
  self:Debug(GetNumArenaOpponents())
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
  return Data.BattlegroundspezificBuffs[mapId], Data.BattlegroundspezificDebuffs[mapId]
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

  -- Helper: Debug Scoreboard Data for Secret/Realm
  local result = Mixin({}, scoreInfo)

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

function BattleGroundEnemies:ShowRosterCheck()
  if self.db.profile.DisableRoleCheckWarning then
    return
  end
  if not self.rosterCheckFrame then
    local f = CreateFrame("Frame", "BGERosterCheckFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(350, 155)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    f.TitleText:SetText(AddonName)
    f.TitleText:SetTextColor(1, 1, 1)

    f.heading = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.heading:SetText("Roster Check")
    f.heading:SetTextColor(1, 1, 1)

    f.message = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.message:SetText("All players must be present before gates open\nfor BGE to track enemies (and be clickable).")
    f.message:SetJustifyH("CENTER")

    f.progress = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")

    -- Anchor all content relative to the frame itself so it moves when dragged
    f.message:SetPoint("CENTER", f, "CENTER", 0, -10)
    f.heading:SetPoint("BOTTOM", f.message, "TOP", 0, 6)
    f.progress:SetPoint("TOP", f.message, "BOTTOM", -12, -8)

    f.statusIcon = f:CreateTexture(nil, "OVERLAY")
    f.statusIcon:SetSize(24, 24)
    f.statusIcon:SetPoint("LEFT", f.progress, "RIGHT", 6, 0)
    f.statusIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")

    f.ticker = C_Timer.NewTicker(1, function()
      if f:IsShown() then
        BattleGroundEnemies:UpdateRosterCheck()
      end
    end)

    self.rosterCheckFrame = f
  else
    self.rosterCheckFrame:Show()
  end
  self:UpdateRosterCheck()
end

function BattleGroundEnemies:UpdateRosterCheck()
  local f = self.rosterCheckFrame
  if not f or not f:IsShown() then
    return
  end
  local matchState = C_PvP.GetActiveMatchState and C_PvP.GetActiveMatchState()
  if matchState and matchState >= Enum.PvPMatchState.Engaged then
    f:Hide()
    return
  end

  if next(self.Enemies.Players) then
    f:Hide()
    return
  end

  local numGroupMembers = GetNumGroupMembers() or 0
  local maxPlayers = GetCorrectedMaxPlayers()

  local yellow = "|cFFFFFF00"
  local white = "|cFFFFFFFF"
  f.progress:SetText(yellow .. numGroupMembers .. white .. " of " .. yellow .. maxPlayers .. white .. " joined|r")

  if maxPlayers > 0 and numGroupMembers >= maxPlayers then
    f.statusIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
  else
    f.statusIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
  end
end

function BattleGroundEnemies:PVP_MATCH_STATE_CHANGED()
  local state = C_PvP.GetActiveMatchState()

  -- Hide roster check popup once past lobby (state >= Engaged)
  if state and state >= Enum.PvPMatchState.Engaged then
    if self.rosterCheckFrame then
      self.rosterCheckFrame:Hide()
    end
  end

  if state == Enum.PvPMatchState.Complete or state == Enum.PvPMatchState.Inactive then
    -- Clear cached trinket spells so stale data doesn't bleed into the next match.
    self._ccSpellCache = nil
  end

  if state == Enum.PvPMatchState.Engaged or state == Enum.PvPMatchState.StartUp then
    self.scoreboardFrozen = true
    self.betweenRounds = false
    -- Refresh raid target icons — updates during the lobby were
    -- swallowed by the DispatchEvent block, so icons may be stale
    -- (e.g. a player swapped sides but kept their old marker).
    self:RAID_TARGET_UPDATE()
  elseif state == Enum.PvPMatchState.Complete or state == Enum.PvPMatchState.PostRound then
    self.scoreboardFrozen = false
    self:UPDATE_BATTLEFIELD_SCORE() -- Full refresh with readable data

    -- Solo shuffle: reset dead states so health bars don't stay empty
    -- when a previously-dead player respawns for the next round.
    -- Block health events briefly so stale UNIT_HEALTH (still reporting
    -- the unit as dead/0-hp) can't immediately undo the reset.
    -- Use a short timer rather than waiting for Engaged, which may not
    -- fire again between solo shuffle rounds.
    if state == Enum.PvPMatchState.PostRound then
      -- Clear cached trinket spells so stale data from the previous round
      -- doesn't get applied to buttons that swap sides in solo shuffle.
      self._ccSpellCache = nil

      -- Push synthetic 100% then freeze all visual updates until
      -- the next PVP_MATCH_STATE_CHANGED fires (Engaged/Complete).
      self:ResetAllDeadStates()
      self.betweenRounds = true
    end
  elseif state == Enum.PvPMatchState.Inactive then
    self.scoreboardFrozen = false
    self.betweenRounds = false
  end
end

function BattleGroundEnemies:SetAllyFaction(allyFaction)
  self.EnemyFaction = allyFaction == 0 and 1 or 0
  self.AllyFaction = allyFaction
end

function BattleGroundEnemies:UPDATE_BATTLEFIELD_SCORE()
  -- Leaver detection: runs even when scoreboard is frozen, since it only
  -- removes players and never overwrites the cached enemy list.
  if self.scoreboardFrozen then
    local removedAny = false
    for playerName, playerButton in pairs(self.Enemies.Players) do
      local guid = playerButton.PlayerDetails and playerButton.PlayerDetails.guid
      if guid then
        local info = C_PvP.GetScoreInfoByPlayerGuid(guid)
        if not info then
          self.Enemies:RemovePlayer(playerButton)
          removedAny = true
        end
      end
    end
    if removedAny then
      self.Enemies:SortPlayers()
      -- Update the displayed player count
      local remainingCount = 0
      for _ in pairs(self.Enemies.Players) do
        remainingCount = remainingCount + 1
      end
      self.Enemies:SetPlayerCount(remainingCount)
      self.Enemies:SetRealPlayerCount(remainingCount)
    end
  end

  -- Guard 1: If scoreboard is frozen (active match), skip entirely
  if self.scoreboardFrozen then
    return
  end

  -- Guard 2: Fallback secret detection in case PVP_MATCH_STATE_CHANGED didn't fire
  local numScoresCheck = GetNumBattlefieldScores()
  if numScoresCheck and numScoresCheck > 0 then
    local testInfo = C_PvP.GetScoreInfo(1)
    if testInfo and issecretvalue and testInfo.name ~= nil and issecretvalue(testInfo.name) then
      self.scoreboardFrozen = true
      return
    end
  end

  self:SetAllyFaction(self.AllyFaction or 0) --set fallback value

  local _, _, _, _, numEnemies = GetBattlefieldTeamInfo(self.EnemyFaction)
  local _, _, _, _, numAllies = GetBattlefieldTeamInfo(self.AllyFaction)

  if numEnemies then
    self.Enemies:SetRealPlayerCount(numEnemies)
  end

  if numAllies then
    self.Allies:SetRealPlayerCount(numAllies)
  end

  local battlefieldScores = {}
  local numScores = GetNumBattlefieldScores()
  self:Debug("numScores", numScores)
  for i = 1, numScores do
    local score = parseBattlefieldScore(i)
    if score then
      table.insert(battlefieldScores, score)
    end
  end

  --see if our faciton in BG changed
  for i = 1, #battlefieldScores do
    local score = battlefieldScores[i]
    local name = score.name
    local faction = score.faction

    if name == self.UserDetails.PlayerName and faction == self.EnemyFaction then
      self:SetAllyFaction(self.EnemyFaction)
    end
  end

  -- Count new enemies before committing, to avoid losing enemies we already have
  local newEnemyCount = 0
  for i = 1, #battlefieldScores do
    local score = battlefieldScores[i]
    if score.faction and score.name and score.classToken and score.faction == self.EnemyFaction then
      newEnemyCount = newEnemyCount + 1
    end
  end

  local currentEnemyButtons = 0
  for _ in pairs(self.Enemies.Players or {}) do
    currentEnemyButtons = currentEnemyButtons + 1
  end

  -- Only update enemies if we gained or maintained count (never lose enemies)
  local updateEnemies = newEnemyCount >= currentEnemyButtons

  if updateEnemies then
    BattleGroundEnemies.Enemies:BeforePlayerSourceUpdate(self.consts.PlayerSources.Scoreboard)
  end
  BattleGroundEnemies.Allies:BeforePlayerSourceUpdate(self.consts.PlayerSources.Scoreboard)

  for i = 1, #battlefieldScores do
    local score = battlefieldScores[i]

    local faction = score.faction
    local name = score.name
    local classToken = score.classToken

    if faction and name and classToken then
      local side = (faction == self.EnemyFaction) and "ENEMY" or "ALLY"
      if faction == self.EnemyFaction then
        if updateEnemies then
          BattleGroundEnemies.Enemies:AddPlayerToSource(self.consts.PlayerSources.Scoreboard, score)
        end
      else
        BattleGroundEnemies.Allies:AddPlayerToSource(self.consts.PlayerSources.Scoreboard, score)
      end
    end
  end

  if updateEnemies then
    BattleGroundEnemies.Enemies:AfterPlayerSourceUpdate()
  end
  BattleGroundEnemies.Allies:AfterPlayerSourceUpdate()

  self:UpdateRosterCheck()
end

function BattleGroundEnemies:GROUP_ROSTER_UPDATE()
  self.Allies:BeforePlayerSourceUpdate(self.consts.PlayerSources.GroupMembers)
  self.Allies.groupLeader = nil
  self.Allies.assistants = {}

  --IsInGroup returns true when user is in a Raid and In a 5 man group

  self:RequestEverythingFromGroupmembers()

  -- GetRaidRosterInfo also works when in a party (not raid) but i am not 100% sure how the party unitID maps to the index in GetRaidRosterInfo()

  local numGroupMembers = GetNumGroupMembers()
  self.Allies:SetRealPlayerCount(numGroupMembers)

  local addedCount = 0

  if IsInRaid() then
    for i = 1, numGroupMembers do -- the player itself only shows up here when he is in a raid
      local name, rank, subgroup, level, localizedClass, classToken, zone, online, isDead, role, isML, combatRole =
        GetRaidRosterInfo(i)

      if name and name ~= self.UserDetails.PlayerName and rank and classToken then
        self.Allies:AddGroupMember(name, rank == 2, rank == 1, classToken, "raid" .. i)
        addedCount = addedCount + 1
      end
    end
  else
    -- we are in a party, 5 man group
    for i = 1, numGroupMembers do
      local unitID = "party" .. i
      local name = GetUnitName(unitID, true)

      local classToken = select(2, UnitClass(unitID))

      if name and classToken then
        self.Allies:AddGroupMember(name, UnitIsGroupLeader(unitID), UnitIsGroupAssistant(unitID), classToken, unitID)
        addedCount = addedCount + 1
      end
    end
  end

  self.UserDetails.isGroupLeader = UnitIsGroupLeader("player")
  self.UserDetails.isGroupAssistant = UnitIsGroupAssistant("player")
  self.Allies:AddGroupMember(
    self.UserDetails.PlayerName,
    self.UserDetails.isGroupLeader,
    self.UserDetails.isGroupAssistant,
    self.UserDetails.PlayerClass,
    "player"
  )
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
  -- GetRaidRosterInfo / GetUnitName can return nil for members who haven't loaded yet,
  -- and GROUP_ROSTER_UPDATE does not re-fire when they finish loading.
  local expectedNonSelf = numGroupMembers - 1
  if addedCount < expectedNonSelf and not self.betweenRounds then
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
end

BattleGroundEnemies.PARTY_LEADER_CHANGED = BattleGroundEnemies.GROUP_ROSTER_UPDATE

--Fires when the player logs in, /reloads the UI or zones between map instances. Basically whenever the loading screen appears.
function BattleGroundEnemies:PLAYER_ENTERING_WORLD()
  self:StartTargetScanTicker()
  self:DisableTestOrEditmode()

  -- Reset scoreboard freeze flag
  self.scoreboardFrozen = false

  self:ClearPIDCaches()
  wipe(self.ArenaIDToPlayerButton)
  self.Enemies:RemoveAllPlayersFromAllSources()
  self.Allies:RemoveAllPlayersFromSource(self.consts.PlayerSources.Scoreboard)
  local _, zone = IsInInstance()

  if zone == "pvp" or zone == "arena" then
    if GetBattlefieldArenaFaction then
      self:SetAllyFaction(GetBattlefieldArenaFaction()) -- returns the playered faction 0 for horde, 1 for alliance, doesnt exist in TBC)
    else
      self:SetAllyFaction(1) -- set a dummy value, we get data later from GetBattlefieldScore()
    end

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
      end)
    end
  else
    self.states.real.isInArena = false
    self.states.real.isInBattleground = false
    self.states.real.isSoloRBG = false
    self.states.real.isRatedBG = false
  end

  self:CheckEnableState()
  self:UpdateMapID()
  self:ToggleArenaFrames()
  self:ToggleRaidFrames()
end
