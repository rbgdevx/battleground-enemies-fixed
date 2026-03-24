---@class BattleGroundEnemies
local BattleGroundEnemies = BattleGroundEnemies
---@type string
local AddonName = ...
---@class Data
local Data = select(2, ...)

local L = Data.L

local generalDefaults = {
  ShowRealmnames = false,
}

local defaultSettings = {
  Enabled = true,
  Parent = "healthBar",
  ActivePoints = 1,
  Points = {
    {
      Point = "LEFT",
      RelativeFrame = "Role",
      RelativePoint = "RIGHT",
      OffsetX = 4,
      OffsetY = 0,
    },
  },
  Text = {
    FontSize = 13,
    JustifyH = "LEFT",
    JustifyV = "MIDDLE",
    WordWrap = false,
  },
}

local generalOptions = function(location)
  return {
    ShowRealmnames = {
      type = "toggle",
      name = L.ShowRealmnames,
      desc = L.ShowRealmnames_Desc,
      width = "normal",
      order = 2,
    },
  }
end

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

local name = BattleGroundEnemies:NewButtonModule({
  moduleName = "Name",
  localizedModuleName = L.Name,
  generalDefaults = generalDefaults,
  defaultSettings = defaultSettings,
  generalOptions = generalOptions,
  options = options,
  enabledInThisExpansion = true,
  attachSettingsToButton = false,
  flags = {
    SetZeroWidthWhenDisabled = true,
  },
})

function name:AttachToPlayerButton(playerButton)
  local container = CreateFrame("Frame", nil, playerButton)
  container.fs = BattleGroundEnemies.MyCreateFontString(container)
  container.fs:SetAllPoints()

  container.SetName = function(self)
    if not playerButton.PlayerDetails then
      return
    end

    -- 12.0.0: Arena opponent names are secret values. Can't manipulate them
    -- but CAN pass directly to :SetText() (InsecureSecretArguments).
    local secretName = playerButton.PlayerDetails.SecretDisplayName
    if type(secretName) ~= "nil" then
      self.fs:SetText(secretName)
      self.fs.DisplayedName = nil
      return
    end

    local playerName = playerButton.PlayerDetails.PlayerName
    if not playerName then
      return
    end

    local name, realm = strsplit("-", playerName, 2)

    if BattleGroundEnemies.db.profile.ConvertCyrillic then
      playerName = ""
      for i = 1, name:utf8len() do
        local c = name:utf8sub(i, i)

        if Data.CyrillicToRomanian[c] then
          playerName = playerName .. Data.CyrillicToRomanian[c]
          if i == 1 then
            playerName = playerName:gsub("^.", string.upper) --uppercase the first character
          end
        else
          playerName = playerName .. c
        end
      end
      --self.DisplayedName = self.DisplayedName:gsub("-.",string.upper) --uppercase the realm name
      name = playerName
    end

    if realm and self.config.ShowRealmnames then
      name = name .. "-" .. realm
    end

    self.fs:SetText(name)
    self.fs.DisplayedName = name
  end

  container.ApplyAllSettings = function(self)
    if not self.config then
      return
    end
    local config = self.config
    -- name
    self.fs:ApplyFontStringSettings(config.Text)
    self:SetName()
  end

  -- Forward FontString methods if needed elsewhere, but mostly BGE calls ApplyAllSettings
  container.SetTextColor = function(self, ...)
    self.fs:SetTextColor(...)
  end

  playerButton.Name = container
  return playerButton.Name
end
