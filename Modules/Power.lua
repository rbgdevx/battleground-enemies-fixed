---@class Data
local Data = select(2, ...)
---@class BattleGroundEnemies
local BattleGroundEnemies = BattleGroundEnemies
local LSM = LibStub("LibSharedMedia-3.0")
local L = Data.L
local GetArenaOpponentIndex = BattleGroundEnemies.GetArenaOpponentIndex
local GetActiveMatchState = C_PvP.GetActiveMatchState
local PvPMatchState = Enum.PvPMatchState
local IsRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
local ArenaUnitExists = IsRetail and ArenaUtil.UnitExists
local After = C_Timer.After

local PowerBarColor = PowerBarColor --table
local UnitPowerPercent = UnitPowerPercent
local UnitPowerType = UnitPowerType
local math_random = math.random

-- Resources that passively regenerate to full out of combat
local fullByDefault = {
  MANA = true,
  ENERGY = true,
  FOCUS = true,
}

-- Module-level Power update implementation. Lifted out of the per-call
-- pcall(function() ... end) that used to live inside UpdatePower, so it is
-- not allocated as a fresh closure on every UNIT_POWER_FREQUENT event
-- (200-600/s in epic BG combat = that many closures/s of pure garbage).
-- Called via pcall(powerUpdateImpl, self, unitID, powerToken) so secret-
-- value crashes still can't propagate. Reassigning the powerToken param
-- locally is harmless — the old closure did the same to its captured
-- upvalue and never propagated it back either.
local function powerUpdateImpl(self, unitID, powerToken)
  if unitID then
    local powerType
    if not powerToken then
      powerType, powerToken = UnitPowerType(unitID)
    else
      powerType = UnitPowerType(unitID)
    end

    if powerToken then
      self:CheckForNewPowerColor(powerToken)
    end

    -- Keep the fixed 0–1 range; pass the possibly secret fraction directly through.
    local percent = UnitPowerPercent(unitID, powerType)
    if not percent then
      return
    end
    self:SetValue(percent)
  else
    if BattleGroundEnemies.states.testmodeActive then
      self:SetValue(math_random(0, 100) / 100)
    else
      -- No unitID: reset to presumptive value based on resource type
      if self.powerToken and fullByDefault[self.powerToken] then
        self:SetMinMaxValues(0, 1)
        self:SetValue(1)
      else
        self:SetMinMaxValues(0, 1)
        self:SetValue(0)
      end
    end
  end
end

local generalDefaults = {
  Texture = "Solid",
  Background = { 0, 0, 0, 0.66 },
  OnlyShowForHealers = false,
}

local defaultSettings = {
  Enabled = true,
  Parent = "Button",
  Height = 5,
  ActivePoints = 1,
  Points = {
    {
      Point = "TOP",
      RelativeFrame = "healthBar",
      RelativePoint = "BOTTOM",
    },
  },
  UseButtonWidthAsWidth = true,
}

local options = function(location)
  return {}
end

local generalOptions = function(location)
  return {
    Texture = {
      type = "select",
      name = L.BarTexture,
      desc = L.HealthBar_Texture_Desc,
      dialogControl = "LSM30_Statusbar",
      values = AceGUIWidgetLSMlists.statusbar,
      width = "normal",
      order = 1,
    },
    Background = {
      type = "color",
      name = L.BarBackground,
      desc = L.PowerBar_Background_Desc,
      hasAlpha = true,
      width = "normal",
      order = 2,
    },
    OnlyShowForHealers = {
      type = "toggle",
      name = L.OnlyShowForHealers,
      desc = L.PowerBar_OnlyShowForHealers_Desc,
      width = "normal",
      order = 3,
    },
  }
end

local flags = {
  SetZeroHeightWhenDisabled = true,
}

local power = BattleGroundEnemies:NewButtonModule({
  moduleName = "Power",
  localizedModuleName = L.PowerBar,
  flags = flags,
  defaultSettings = defaultSettings,
  generalDefaults = generalDefaults,
  options = options,
  generalOptions = generalOptions,
  events = { "UnitIdUpdate", "UpdatePower" },
  enabledInThisExpansion = true,
  attachSettingsToButton = false,
})

local function refreshArenaPowerVisibility(unitID)
  for _, playerButton in ipairs(BattleGroundEnemies.Enemies.PlayerList) do
    local arenaIndex = GetArenaOpponentIndex(playerButton)
    if arenaIndex and unitID == "arena" .. arenaIndex and playerButton.Power.Enabled then
      playerButton.Power:UpdateArenaVisibility()
    end
  end
end

if IsRetail then
  power:RegisterEvent("ARENA_OPPONENT_UPDATE")
  power:SetScript("OnEvent", function(_, _, unitID)
    -- Let Blizzard's ArenaUtil process its unseen override before reading it.
    After(0, function()
      refreshArenaPowerVisibility(unitID)
    end)
  end)
end

function power:AttachToPlayerButton(playerButton)
  playerButton.Power = CreateFrame("StatusBar", nil, playerButton)
  playerButton.Power:SetMinMaxValues(0, 1)

  --playerButton.Power.Background = playerButton.Power:CreateTexture(nil, 'BACKGROUND', nil, 2)
  playerButton.Power.Background = playerButton.Power:CreateTexture(nil, "BACKGROUND", nil, 2)
  playerButton.Power.Background:SetAllPoints()
  playerButton.Power.Background:SetTexture("Interface/Buttons/WHITE8X8")

  function playerButton.Power:CheckForNewPowerColor(powerToken)
    if not powerToken then
      return
    end
    -- If we already have a class-confirmed power token, don't let scan results
    -- override it (a stale unit token can feed us the wrong unit's power type)
    if self.classConfirmedToken then
      return
    end

    if self.powerToken ~= powerToken then
      local color = PowerBarColor[powerToken]
      if color then
        self:SetStatusBarColor(color.r, color.g, color.b)
        self.powerToken = powerToken
      end
    end
  end

  function playerButton.Power:UnitIdUpdate(unitID)
    if unitID then
      -- 12.0.7: UnitPowerType no longer errors on restricted/compound tokens (it
      -- returns nil), so the old `pcall ... if not ok then return` error-gate is
      -- now dead. Gate on a missing power type instead — preserving the original
      -- "skip compound tokens" behavior. powerToken (powerTypeToken) carries no
      -- secret flag, so `not powerToken` is taint-safe.
      local _, powerToken = UnitPowerType(unitID)
      if not powerToken then
        return
      end

      self:CheckForNewPowerColor(powerToken)
      self:UpdatePower(unitID)
    end
  end

  function playerButton.Power:UpdatePower(unitID, powerToken)
    -- pcall the module-level impl so secret-value crashes don't propagate.
    -- Secret values are "userdata" that crash on math but work on
    -- SetValue/SetMinMaxValues — the impl only passes them through.
    pcall(powerUpdateImpl, self, unitID, powerToken)
  end

  function playerButton.Power:ShouldShowInArena()
    local arenaIndex = GetArenaOpponentIndex(playerButton)
    return not arenaIndex or (GetActiveMatchState() == PvPMatchState.Engaged
      and (not IsRetail or ArenaUnitExists("arena" .. arenaIndex)))
  end

  function playerButton.Power:UpdateArenaVisibility()
    self:SetShown(self:ShouldShowInArena())
    playerButton:UpdateHealthBarLayout()
  end

  function playerButton.Power:ApplyAllSettings()
    if not self.config then
      return
    end
    self.classConfirmedToken = nil -- reset for fresh class lookup
    -- power
    self:SetHeight(self.config.Height or 0.01)
    self:UpdateArenaVisibility()

    self:SetStatusBarTexture(LSM:Fetch("statusbar", self.config.Texture)) --self.healthBar:SetStatusBarTexture(137012)
    self.Background:SetVertexColor(unpack(self.config.Background))
    local playerDetails = playerButton.PlayerDetails
    if not playerDetails then
      return
    end
    if not playerDetails.PlayerClass then
      return
    end
    if not playerDetails.PlayerRole then
      return
    end

    if playerDetails.PlayerRole == "HEALER" or not self.config.OnlyShowForHealers then
      self:SetHeight(self.config.Height or 0.01)
    else
      self:SetHeight(0.01)
    end
    playerButton:UpdateHealthBarLayout()

    local powerToken

    local t = Data.Classes[playerDetails.PlayerClass]
    if t then
      local spec = playerDetails.PlayerSpecName
      if spec and not (issecretvalue and issecretvalue(spec)) then
        t = t[spec]
      end
    end
    if t then
      powerToken = t.Ressource
    end

    self:CheckForNewPowerColor(powerToken)
    if powerToken then
      self.classConfirmedToken = true
    end

    -- Set presumptive fill: resources that regen passively start full, others start empty
    if powerToken and fullByDefault[powerToken] then
      self:SetMinMaxValues(0, 1)
      self:SetValue(1)
    else
      self:SetMinMaxValues(0, 1)
      self:SetValue(0)
    end
  end

  return playerButton.Power
end
