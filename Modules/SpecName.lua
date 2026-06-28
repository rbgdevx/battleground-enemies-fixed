---@class BattleGroundEnemies
local BattleGroundEnemies = BattleGroundEnemies
---@class Data
local Data = select(2, ...)

local L = Data.L
local LSM = LibStub("LibSharedMedia-3.0")

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
      OffsetY = -4,
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
  enabledInThisExpansion = true,
  attachSettingsToButton = false,
  flags = {
    SetZeroWidthWhenDisabled = true,
  },
})

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
function BattleGroundEnemies:GetSpecNameReservedHeight(playerCountConfig)
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
function BattleGroundEnemies:GetNameSpecNameYAdjust(playerCountConfig)
  local reserved = self:GetSpecNameReservedHeight(playerCountConfig)
  if reserved == 0 then
    return 0
  end
  local specConfig = playerCountConfig
      and playerCountConfig.ButtonModules
      and playerCountConfig.ButtonModules.SpecName
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

    -- PlayerSpecName is the scoreboard talentSpec (C_PvP.GetScoreInfo), already
    -- mapped to this button by the identity matcher. Mid-match it is a
    -- SecretInActivePvPMatch value, so render it 100% as-is: only type() (safe
    -- on a secret) decides empty-vs-present, and SetText (InsecureSecretArguments)
    -- draws it. No comparison / slicing / formatting — any of those would taint.
    -- nil or false (no spec known) just clears the text.
    local spec = playerButton.PlayerDetails.PlayerSpecName
    local specType = type(spec)
    if specType == "nil" or specType == "boolean" then
      self.fs:SetText("")
      return
    end
    self.fs:SetText(spec)
  end

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
