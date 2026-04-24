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

    -- 12.0.5: Ambiguate is Blizzard's official realm-stripping helper,
    -- added specifically for the new PvP-secrecy regime. Works on both
    -- normal strings and secret strings without tainting (that's its
    -- whole purpose — previously strsplit/utf8/gsub would taint on
    -- secret names, forcing a passthrough-as-Name-Realm fallback).
    --   "short" → "Name"          (realm stripped)
    --   "none"  → "Name-Realm"    (realm preserved when present)
    -- pcall-guarded just in case, with legacy strsplit fallback for
    -- older clients that don't expose Ambiguate.
    local context = self.config.ShowRealmnames and "none" or "short"
    local ok, resolvedName
    if Ambiguate then
      ok, resolvedName = pcall(Ambiguate, playerName, context)
    end
    if not ok or type(resolvedName) ~= "string" then
      -- Ambiguate unavailable or returned unexpected type — fall back to
      -- the pre-12.0.5 path. Secret names passthrough without string ops.
      if issecretvalue and issecretvalue(playerName) then
        self.fs:SetText(playerName)
        self.fs.DisplayedName = nil
        return
      end
      local bareName, realm = strsplit("-", playerName, 2)
      resolvedName = (realm and self.config.ShowRealmnames) and (bareName .. "-" .. realm) or bareName
    end

    -- Cyrillic → Roman transliteration requires string iteration which
    -- would taint on a secret-tagged result. Skip the conversion in that
    -- case; the displayed name is still correct (just not transliterated).
    local resolvedIsSecret = issecretvalue and issecretvalue(resolvedName)
    if BattleGroundEnemies.db.profile.ConvertCyrillic and not resolvedIsSecret then
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
    -- DisplayedName is read elsewhere for comparisons; storing a secret
    -- value would taint those callers. Stash nil when secret.
    self.fs.DisplayedName = resolvedIsSecret and nil or resolvedName
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
