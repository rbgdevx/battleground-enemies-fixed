---@class BattleGroundEnemies
local BattleGroundEnemies = BattleGroundEnemies
---@class Data
local Data = select(2, ...)

local L = Data.L
local IsForever = Data.IsForever
local LSM = LibStub("LibSharedMedia-3.0")
local UpdateArenaOpponentSpecDisplay = UnitFrameUtil and UnitFrameUtil.UpdateArenaOpponentSpecDisplay
local GetArenaOpponentIndex = BattleGroundEnemies.GetArenaOpponentIndex
local IsRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
local GetPlayerSpecName = IsRetail and PlayerUtil.GetSpecName
local GetInspectSpecialization = IsRetail and C_SpecializationInfo.GetInspectSpecialization
local GetSpecializationNameForSpecID = GetSpecializationNameForSpecID
local CanInspect = CanInspect
local NotifyInspect = NotifyInspect
local UnitGUID = UnitGUID
local UnitSex = UnitSex
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local issecretvalue = issecretvalue
local wipe = wipe
local After = C_Timer.After
local IsTestmodeActive = BattleGroundEnemies.IsTestmodeActive
local QueueForUpdateAfterCombat = BattleGroundEnemies.QueueForUpdateAfterCombat

local defaultSettings = {
  Enabled = true,
  Parent = "healthBar",
  ActivePoints = 1,
  Points = {
    {
      Point = "TOP",
      RelativeFrame = "Name",
      RelativePoint = "CENTER",
      OffsetX = 0,
      OffsetY = -5,
    },
  },
  UseButtonWidthAsWidth = true,
  Height = 9,
  Text = {
    FontSize = 9,
    JustifyH = "LEFT",
    JustifyV = "MIDDLE",
    WordWrap = false,
  },
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
  }
end

local specName = BattleGroundEnemies:NewButtonModule({
  moduleName = "SpecName",
  localizedModuleName = L.SpecName,
  defaultSettings = defaultSettings,
  options = options,
  enabledInThisExpansion = not IsForever,
  attachSettingsToButton = false,
  events = { "ArenaOpponentShown", "ArenaOpponentHidden" },
  flags = {
    SetZeroWidthWhenDisabled = true,
  },
})

-- Friendly arena inspection results belong only to this instance and roster.
local friendlySpecs = {}
local inspectQueue = {}
local pendingInspect
local nextInspectCheck = 0
local layoutRefreshQueued = false

local function isFriendlyArenaRow(playerButton)
  return IsRetail and BattleGroundEnemies.states.real.isInArena
    and not IsTestmodeActive(BattleGroundEnemies) and not playerButton.PlayerIsEnemy
end

local function getFriendlyArenaUnit(playerButton)
  if not BattleGroundEnemies.enabled or not isFriendlyArenaRow(playerButton)
    or not playerButton.SpecName.Enabled then
    return nil
  end
  local details = playerButton.PlayerDetails
  local unit = details and details.unitID
  if not unit or (unit ~= "player" and not unit:match("^party%d+$") and not unit:match("^raid%d+$")) then
    return nil
  end
  local guid = UnitGUID(unit)
  if issecretvalue(guid) or not guid or guid ~= details.GUID then
    return nil
  end
  return unit, guid
end

local function findFriendlyArenaUnit(guid)
  for _, playerButton in ipairs(BattleGroundEnemies.Allies.PlayerList) do
    local unit, currentGUID = getFriendlyArenaUnit(playerButton)
    if currentGUID == guid then
      return unit, playerButton
    end
  end
end

local function refreshFriendlySpecNames()
  for _, playerButton in ipairs(BattleGroundEnemies.Allies.PlayerList) do
    local display = playerButton.SpecName
    if display.Enabled then
      display:SetSpec()
    end
  end
end

function specName:RefreshFriendlyLayout()
  if not BattleGroundEnemies.enabled or not BattleGroundEnemies.states.real.isInArena
    or IsTestmodeActive(BattleGroundEnemies) then
    return
  end
  if InCombatLockdown() then
    QueueForUpdateAfterCombat(BattleGroundEnemies, self, "RefreshFriendlyLayout")
    return
  end
  refreshFriendlySpecNames()
  BattleGroundEnemies.Allies:SortPlayers(true)
end

local function queueFriendlyLayoutRefresh()
  if InCombatLockdown() then
    QueueForUpdateAfterCombat(BattleGroundEnemies, specName, "RefreshFriendlyLayout")
  elseif not layoutRefreshQueued then
    layoutRefreshQueued = true
    After(0, function()
      layoutRefreshQueued = false
      specName:RefreshFriendlyLayout()
    end)
  end
end

local function resetFriendlyInspections()
  wipe(friendlySpecs)
  wipe(inspectQueue)
  pendingInspect = nil
  nextInspectCheck = 0
  specName:SetScript("OnUpdate", nil)
end

local function findNextFriendlyInspection(now)
  local candidateGUID, candidateUnit, candidateState
  local waiting = false
  for guid, state in pairs(inspectQueue) do
    local unit = findFriendlyArenaUnit(guid)
    if not unit then
      inspectQueue[guid] = nil
    elseif state.attempts < 3 then
      waiting = true
      if now >= state.nextAttempt and CanInspect(unit)
        and (not candidateState or state.attempts < candidateState.attempts) then
        candidateGUID, candidateUnit, candidateState = guid, unit, state
      end
    end
  end
  return candidateGUID, candidateUnit, candidateState, waiting
end

local function processFriendlyInspections(self)
  if not BattleGroundEnemies.enabled or not BattleGroundEnemies.states.real.isInArena
    or IsTestmodeActive(BattleGroundEnemies) then
    resetFriendlyInspections()
    return
  end
  local now = GetTime()
  if now < nextInspectCheck then
    return
  end
  nextInspectCheck = now + 1.5
  if pendingInspect and not findFriendlyArenaUnit(pendingInspect.guid) then
    inspectQueue[pendingInspect.guid] = nil
    pendingInspect = nil
  end
  if pendingInspect then
    if now - pendingInspect.started < 10 then
      return
    end
    pendingInspect = nil
  end
  if InCombatLockdown() or (InspectFrame and InspectFrame.unit)
    or (PlayerSpellsFrame and PlayerSpellsFrame:IsInspecting()) then
    return
  end
  local candidateGUID, candidateUnit, candidateState, waiting = findNextFriendlyInspection(now)
  if candidateUnit then
    candidateState.attempts = candidateState.attempts + 1
    candidateState.nextAttempt = now + 13
    pendingInspect = { guid = candidateGUID, started = now }
    NotifyInspect(candidateUnit)
  elseif not waiting then
    self:SetScript("OnUpdate", nil)
  end
end

local function applyFriendlySpec(display, spec, hasLine)
  if display.hasSpecNameLine ~= hasLine then
    if InCombatLockdown() then
      if not hasLine then
        display.fs:SetText("")
      end
      queueFriendlyLayoutRefresh()
      return
    end
    display.hasSpecNameLine = hasLine
    queueFriendlyLayoutRefresh()
  end
  if hasLine then
    display.fs:SetText(spec)
  else
    display.fs:SetText("")
  end
end

local function setFriendlyArenaSpec(display, playerButton)
  if not isFriendlyArenaRow(playerButton) then
    return false
  end
  local unit, guid = getFriendlyArenaUnit(playerButton)
  local spec
  if unit == "player" then
    spec = GetPlayerSpecName()
  elseif unit then
    spec = friendlySpecs[guid]
  end
  if spec and spec ~= "" then
    applyFriendlySpec(display, spec, true)
  else
    local scoreboardSpec = playerButton.PlayerDetails.PlayerSpecNameScoreboard
    local kind = type(scoreboardSpec)
    local hasScoreboardSpec = kind ~= "nil" and kind ~= "boolean"
    if hasScoreboardSpec and not issecretvalue(scoreboardSpec) and scoreboardSpec == "" then
      hasScoreboardSpec = false
    end
    if hasScoreboardSpec then
      applyFriendlySpec(display, scoreboardSpec, true)
    else
      applyFriendlySpec(display, nil, false)
    end
    if unit and unit ~= "player" and not hasScoreboardSpec then
      local state = inspectQueue[guid]
      if not state then
        state = { attempts = 0, nextAttempt = 0 }
        inspectQueue[guid] = state
      end
      if state.attempts < 3 then
        specName:SetScript("OnUpdate", processFriendlyInspections)
      end
    end
  end
  return true
end

local function receiveFriendlyInspection(guid)
  local unit, playerButton = findFriendlyArenaUnit(guid)
  local resolved = false
  if unit then
    local specID = GetInspectSpecialization(unit)
    if not issecretvalue(specID) and specID > 0 then
      local name = GetSpecializationNameForSpecID(specID, UnitSex(unit))
      if name and name ~= "" then
        friendlySpecs[guid] = name
        resolved = true
      end
    end
  end
  if resolved then
    inspectQueue[guid] = nil
    playerButton.SpecName:SetSpec()
  elseif inspectQueue[guid] then
    inspectQueue[guid].nextAttempt = GetTime() + 3
  end
  if pendingInspect and pendingInspect.guid == guid then
    pendingInspect = nil
  end
end

local function pruneFriendlyInspections()
  for guid in pairs(friendlySpecs) do
    if not findFriendlyArenaUnit(guid) then
      friendlySpecs[guid] = nil
    end
  end
  for guid in pairs(inspectQueue) do
    if not findFriendlyArenaUnit(guid) then
      inspectQueue[guid] = nil
    end
  end
end

if IsRetail then
  specName:RegisterEvent("INSPECT_READY")
  specName:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
  specName:RegisterEvent("PLAYER_ENTERING_WORLD")
  specName:RegisterEvent("GROUP_ROSTER_UPDATE")
  specName:SetScript("OnEvent", function(_, event, unitOrGUID)
    if event == "PLAYER_ENTERING_WORLD" then
      resetFriendlyInspections()
      if BattleGroundEnemies.states.real.isInArena then
        refreshFriendlySpecNames()
      end
    elseif not BattleGroundEnemies.enabled or not BattleGroundEnemies.states.real.isInArena
      or IsTestmodeActive(BattleGroundEnemies) then
      return
    elseif event == "GROUP_ROSTER_UPDATE" then
      pruneFriendlyInspections()
      refreshFriendlySpecNames()
    elseif event == "INSPECT_READY" then
      receiveFriendlyInspection(unitOrGUID)
    else
      local guid = UnitGUID(unitOrGUID)
      if not issecretvalue(guid) and guid then
        friendlySpecs[guid] = nil
        inspectQueue[guid] = nil
        refreshFriendlySpecNames()
      end
    end
  end)
end

-- Extra button height to reserve for the spec-name line when the module is
-- enabled, so the spec name has dedicated vertical room without forcing every
-- user to raise their BarHeight. Real spec names are SecretInActivePvPMatch, so
-- their own fontstring's height can't be measured without tainting. Instead we
-- measure a HIDDEN, NON-SECRET sample ("Ag", spanning a full ascender+descender)
-- set to the SAME font / size / outline the module renders with — a single
-- line's height is glyph-independent, so the sample equals the real spec's line
-- height. Returns 0 when the module is disabled. Deterministic for a given
-- config, so the button layout (row spacing) and ApplyButtonSettings (button
-- height) both call it and stay in lockstep — otherwise taller buttons overlap.
local measureFontString
function BattleGroundEnemies:GetSpecNameReservedHeight(playerCountConfig, playerButton)
  if not playerCountConfig then
    return 0
  end
  local moduleConfig = playerCountConfig.ButtonModules and playerCountConfig.ButtonModules.SpecName
  if not (moduleConfig and moduleConfig.Enabled) then
    return 0
  end
  if not self:IsModuleEnabledOnThisExpansion("SpecName") then
    return 0
  end
  if playerButton and isFriendlyArenaRow(playerButton) and not playerButton.SpecName.hasSpecNameLine then
    return 0
  end

  local textConfig = moduleConfig.Text or {}
  local globalText = (self.db and self.db.profile and self.db.profile.Text) or {}
  local fontPath = LSM:Fetch("font", textConfig.Font or globalText.Font)
  local fontSize = textConfig.FontSize or globalText.FontSize or 9
  local outline = textConfig.FontOutline
  if outline == nil then
    outline = globalText.FontOutline
  end

  if not fontPath then
    return fontSize -- LSM miss: point size is a reasonable height estimate
  end

  if not measureFontString then
    measureFontString = UIParent:CreateFontString(nil, "OVERLAY")
    measureFontString:Hide()
  end
  measureFontString:SetFont(fontPath, fontSize, outline)
  measureFontString:SetText("Ag")
  local height = measureFontString:GetStringHeight()
  if not height or height <= 0 then
    return fontSize
  end
  return height
end

-- Vertical nudge (offsetY units, positive = up) to add to the Name module's
-- anchor so the Name + Spec Name PAIR stays centered on whatever Name lines up
-- with (e.g. the Role icon) once Spec Name is tucked underneath it.
--
-- Geometry: Name sits at its anchor line; Spec Name's center drops below Name's
-- center by (reservedHeight - specOffsetY) — reservedHeight is how far Spec Name
-- extends down, specOffsetY (negative = down) is the gap the user set. The pair's
-- midpoint is therefore half that drop below the line, so shifting Name UP by half
-- the drop puts the midpoint back on the line: reservedHeight/4 - specOffsetY/2.
-- Returns 0 when Spec Name is disabled, so Name is left exactly as configured.
function BattleGroundEnemies:GetNameSpecNameYAdjust(playerCountConfig, playerButton)
  local reserved = self:GetSpecNameReservedHeight(playerCountConfig, playerButton)
  if reserved == 0 then
    return 0
  end
  local specConfig = playerCountConfig and playerCountConfig.ButtonModules and playerCountConfig.ButtonModules.SpecName
  local points = specConfig and specConfig.Points
  local specOffsetY = (points and points[1] and points[1].OffsetY) or 0
  -- -1 empirical correction: the "Ag" sample includes descender space most spec
  -- names lack, so the geometric calc lands the pair slightly high; nudge it down.
  return reserved / 4 - specOffsetY / 2 - 1
end

function specName:AttachToPlayerButton(playerButton)
  local container = CreateFrame("Frame", nil, playerButton)
  container.fs = BattleGroundEnemies.MyCreateFontString(container)
  container.fs:SetAllPoints()

  container.SetSpec = function(self)
    if not playerButton.PlayerDetails then
      return
    end

    if setFriendlyArenaSpec(self, playerButton) then
      return
    end

    -- PlayerSpecNameScoreboard is the LIVE scoreboard talentSpec
    -- (C_PvP.GetScoreInfo) exactly as delivered THIS match, already mapped to
    -- this button by the identity matcher. NOT PlayerSpecName — that field gets
    -- overwritten by the harvest seeder with the player's last-seen spec from a
    -- PREVIOUS game (needed for role/icon logic, which can't use a secret), and
    -- rendering it here showed stale specs. Pass current scoreboard text
    -- directly to SetText; type() safely selects the missing-value path.
    -- When absent, real arena rows use the native text helper; other rows clear.
    local spec = playerButton.PlayerDetails.PlayerSpecNameScoreboard
    local specType = type(spec)
    if specType == "nil" or specType == "boolean" then
      local arenaIndex = GetArenaOpponentIndex(playerButton)
      if arenaIndex and UpdateArenaOpponentSpecDisplay then
        UpdateArenaOpponentSpecDisplay({ specNameText = self.fs }, arenaIndex)
      else
        self.fs:SetText("")
      end
      return
    end
    self.fs:SetText(spec)
  end

  container.ArenaOpponentShown = container.SetSpec
  container.ArenaOpponentHidden = container.SetSpec

  container.ApplyAllSettings = function(self)
    if not self.config then
      return
    end
    self.fs:ApplyFontStringSettings(self.config.Text)
    self:SetSpec()
  end

  container.SetTextColor = function(self, ...)
    self.fs:SetTextColor(...)
  end

  playerButton.SpecName = container
  return playerButton.SpecName
end
