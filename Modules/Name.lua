---@class BattleGroundEnemies
local BattleGroundEnemies = BattleGroundEnemies
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

    -- Arena-prep buttons may carry a SecretDisplayName from UnitName("arenaN")
    -- when the unit identity is still secret. Pass it directly to :SetText()
    -- (InsecureSecretArguments) and bail — no realm strip / Cyrillic conversion.
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

    -- Ambiguate is Blizzard's official realm-stripping helper.
    --   "short" → "Name"          (realm stripped)
    --   "none"  → "Name-Realm"    (realm preserved when present)
    -- pcall-guarded with a legacy strsplit fallback for older clients.
    local context = self.config.ShowRealmnames and "none" or "short"
    local ok, resolvedName
    if Ambiguate then
      ok, resolvedName = pcall(Ambiguate, playerName, context)
    end
    if not ok or type(resolvedName) ~= "string" then
      local bareName, realm = strsplit("-", playerName, 2)
      resolvedName = (realm and self.config.ShowRealmnames) and (bareName .. "-" .. realm) or bareName
    end

    if BattleGroundEnemies.db.profile.ConvertCyrillic then
      local converted = ""
      for i = 1, resolvedName:utf8len() do
        local c = resolvedName:utf8sub(i, i)
        if Data.CyrillicToRomanian[c] then
          converted = converted .. Data.CyrillicToRomanian[c]
          if i == 1 then
            converted = converted:gsub("^.", string.upper) --uppercase the first character
          end
        else
          converted = converted .. c
        end
      end
      resolvedName = converted
    end

    self.fs:SetText(resolvedName)
    self.fs.DisplayedName = resolvedName
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
