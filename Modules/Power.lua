---@type string
local AddonName = ...
---@class Data
local Data = select(2, ...)
---@class BattleGroundEnemies
local BattleGroundEnemies = BattleGroundEnemies
local LSM = LibStub("LibSharedMedia-3.0")
local L = Data.L

local PowerBarColor = PowerBarColor --table
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType
local math_random = math.random

-- Resources that passively regenerate to full out of combat
local fullByDefault = {
  MANA = true,
  ENERGY = true,
  FOCUS = true,
}

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

function power:AttachToPlayerButton(playerButton)
  playerButton.Power = CreateFrame("StatusBar", nil, playerButton)
  playerButton.Power:SetMinMaxValues(0, 1)
  playerButton.Power.maxValue = 1

  --playerButton.Power.Background = playerButton.Power:CreateTexture(nil, 'BACKGROUND', nil, 2)
  playerButton.Power.Background = playerButton.Power:CreateTexture(nil, "BACKGROUND", nil, 2)
  playerButton.Power.Background:SetAllPoints()
  playerButton.Power.Background:SetTexture("Interface/Buttons/WHITE8X8")

  function playerButton.Power:UpdateMinMaxValues(max)
    local needsUpdate = true
    -- Try to check if update is needed (optimization)
    local ok = pcall(function()
      if max == self.maxValue then
        needsUpdate = false
      end
    end)

    -- If comparison failed (secret value) OR values are different, update!
    if needsUpdate or not ok then
      self:SetMinMaxValues(0, max)
      self.maxValue = max
    end
  end

  function playerButton.Power:CheckForNewPowerColor(powerToken)
    if not powerToken then return end
    -- If we already have a class-confirmed power token, don't let scan results
    -- override it (PID mismatch can feed us the wrong unit's power type)
    if self.classConfirmedToken then return end

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
      local ok, powerType, powerToken = pcall(UnitPowerType, unitID)
      if not ok then return end -- compound token rejected

      self:CheckForNewPowerColor(powerToken)
      self:UpdatePower(unitID)
    end
  end

  function playerButton.Power:UpdatePower(unitID, powerToken)
    -- Wrap entire logic in pcall to allow "Passthrough" of secret values.
    -- Secret values are "userdata" that crash on math but work on SetValue/SetMinMaxValues
    local ok, err = pcall(function()
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

        -- Secret Value Passthrough:
        -- UnitPower / UnitPowerMax return secret values in Rated PvP.
        -- We must NOT do math (cur / max * 100) or comparisons (if cur > 50).
        -- We just pass them blindly to the status bar.
        local cur = UnitPower(unitID, powerType) or 0
        local max = UnitPowerMax(unitID, powerType) or 1

        self:UpdateMinMaxValues(max)
        self:SetValue(cur)
      else
        if BattleGroundEnemies.states.testmodeActive then
          self:SetValue(math_random(0, 100) / 100)
        else
          -- No unitID: reset to presumptive value based on resource type
          if self.powerToken and fullByDefault[self.powerToken] then
            self:SetMinMaxValues(0, 1)
            self.maxValue = 1
            self:SetValue(1)
          else
            self:SetMinMaxValues(0, 1)
            self.maxValue = 1
            self:SetValue(0)
          end
        end
      end
    end)
  end

  function playerButton.Power:ApplyAllSettings()
    if not self.config then
      return
    end
    self.classConfirmedToken = nil -- reset for fresh class lookup
    -- power
    self:SetHeight(self.config.Height or 0.01)

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

    local powerToken

    local t = Data.Classes[playerDetails.PlayerClass]
    if t then
      if playerDetails.PlayerSpecName then
        t = t[playerDetails.PlayerSpecName]
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
      self.maxValue = 1
      self:SetValue(1)
    else
      self:SetMinMaxValues(0, 1)
      self.maxValue = 1
      self:SetValue(0)
    end
  end
  return playerButton.Power
end
