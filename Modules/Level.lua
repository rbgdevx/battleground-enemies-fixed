---@type string
local AddonName = ...
---@class Data
local Data = select(2, ...)
---@class BattleGroundEnemies
local BattleGroundEnemies = BattleGroundEnemies
local L = Data.L
local MaxLevel = GetMaxPlayerLevel()

local generalDefaults = {
  OnlyShowIfNotMaxLevel = true,
}

local defaultSettings = {
  Enabled = false,
  Parent = "healthBar",
  ActivePoints = 1,
  Points = {
    {
      Point = "RIGHT",
      RelativeFrame = "healthBar",
      RelativePoint = "RIGHT",
      OffsetX = -4,
      OffsetY = 0,
    },
  },
  Text = {
    FontSize = 18,
    JustifyH = "RIGHT",
  },
  UseButtonHeightAsHeight = true,
  UseButtonHeightAsWidth = true,
}

local generalOptions = function(location)
  return {
    OnlyShowIfNotMaxLevel = {
      type = "toggle",
      name = L.LevelText_OnlyShowIfNotMaxLevel,
      order = 2,
      width = "full",
    },
  }
end

local options = function(location)
  return {
    LevelTextTextSettings = {
      type = "group",
      name = L.Text,
      get = function(option)
        return Data.GetOption(location.Text, option)
      end,
      set = function(option, ...)
        return Data.SetOption(location.Text, option, ...)
      end,
      inline = true,
      order = 3,
      args = Data.AddNormalTextSettings(location.Text),
    },
  }
end

local level = BattleGroundEnemies:NewButtonModule({
  moduleName = "Level",
  localizedModuleName = LEVEL,
  defaultSettings = defaultSettings,
  generalDefaults = generalDefaults,
  options = options,
  generalOptions = generalOptions,
  events = { "UnitIdUpdate" },
  enabledInThisExpansion = true,
  attachSettingsToButton = false,
  flags = {
    SetZeroWidthWhenDisabled = true,
  },
})

function level:AttachToPlayerButton(playerButton)
  local container = CreateFrame("Frame", nil, playerButton)
  container.fs = BattleGroundEnemies.MyCreateFontString(container)
  container.fs:SetAllPoints()

  container.DisplayLevel = function(self)
    if not self.config.OnlyShowIfNotMaxLevel or (playerButton.PlayerLevel and playerButton.PlayerLevel < MaxLevel) then
      self.fs:SetText(MaxLevel - 1) -- to set the width of the frame (the name shoudl have the same space from the role icon/spec icon regardless of level shown)
      self.fs:SetWidth(0)
      self.fs:SetText(playerButton.PlayerLevel)
    else
      self.fs:SetText("")
    end
  end

  -- Level
  container.UnitIdUpdate = function(self, unitID)
    if unitID then
      self:SetLevel(UnitLevel(unitID))
    end
  end

  container.SetLevel = function(self, level)
    if not playerButton.PlayerLevel or level ~= playerButton.PlayerLevel then
      playerButton.PlayerLevel = level
    end
    self:DisplayLevel()
  end

  container.ApplyAllSettings = function(self)
    if not self.config then
      return
    end
    if not self.Enabled then
      return
    end
    self.fs:ApplyFontStringSettings(self.config.Text)
    local playerDetails = playerButton.PlayerDetails
    if not playerDetails then
      return
    end
    if playerDetails.PlayerLevel then
      self:SetLevel(playerDetails.PlayerLevel)
    end --for testmode
    self:DisplayLevel()
  end

  playerButton.Level = container
  return playerButton.Level
end
