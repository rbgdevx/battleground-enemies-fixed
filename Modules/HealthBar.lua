---@type string
local AddonName = ...
---@class Data
local Data = select(2, ...)
---@class BattleGroundEnemies
local BattleGroundEnemies = BattleGroundEnemies
local LSM = LibStub("LibSharedMedia-3.0")
local L = Data.L

local CompactUnitFrame_UpdateHealPrediction = CompactUnitFrame_UpdateHealPrediction

local HealthTextTypes = {
  health = COMPACT_UNIT_FRAME_PROFILE_HEALTHTEXT_HEALTH,
  losthealth = COMPACT_UNIT_FRAME_PROFILE_HEALTHTEXT_LOSTHEALTH,
  perc = COMPACT_UNIT_FRAME_PROFILE_HEALTHTEXT_PERC,
}

local generalDefaults = {
  Texture = "Solid",
  Background = { 0, 0, 0, 0.66 },
  HealthPrediction_Enabled = true,
}

local defaultSettings = {
  Parent = "Button",
  Enabled = true,
  ActivePoints = 1,
  Height = 30,
  Points = {
    {
      Point = "TOP",
      RelativeFrame = "Button",
      RelativePoint = "TOP",
    },
  },
  UseButtonWidthAsWidth = true,
}

local healthTextDefaultSettings = {
  Parent = "Button",
  Enabled = true,
  HealthTextType = "health",
  FontSize = 17,
  JustifyH = "RIGHT",
  JustifyV = "MIDDLE",
  ActivePoints = 1,
  Points = {
    {
      Point = "RIGHT",
      RelativeFrame = "healthBar",
      RelativePoint = "RIGHT",
      OffsetX = -4,
    },
  },
  Width = 500,
  UseButtonWidthAsWidth = true,
  UseButtonHeightAsHeight = true,
}

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
      desc = L.HealthBar_Background_Desc,
      hasAlpha = true,
      width = "normal",
      order = 2,
    },
    HealthPrediction_Enabled = {
      type = "toggle",
      name = COMPACT_UNIT_FRAME_PROFILE_DISPLAYHEALPREDICTION,
      width = "full",
      order = 3,
    },
  }
end

local options = function(location)
  return {}
end

local healthTextOptions = function(location)
  return {
    General = {
      type = "group",
      name = L.General,
      order = 1,
      args = {
        HealthTextType = {
          type = "select",
          name = L.HealthTextType,
          width = "normal",
          values = HealthTextTypes,
          order = 1,
        },
        TextSettings = {
          type = "group",
          name = L.HealthTextSettings,
          get = function(option)
            return Data.GetOption(location, option)
          end,
          set = function(option, ...)
            return Data.SetOption(location, option, ...)
          end,
          inline = true,
          order = 2,
          args = Data.AddNormalTextSettings(location),
        },
      },
    },
    HealthTextPosition = {
      type = "group",
      name = L.Position .. " " .. L.AND .. " " .. L.Size,
      get = function(option)
        return Data.GetOption(location, option)
      end,
      set = function(option, ...)
        return Data.SetOption(location, option, ...)
      end,
      order = 2,
      args = Data.AddPositionSetting(
        location,
        "healthBarText",
        BattleGroundEnemies.ButtonModules.healthBarText,
        "Enemies"
      ),
    },
  }
end

local healthBar = BattleGroundEnemies:NewButtonModule({
  moduleName = "healthBar",
  localizedModuleName = L.HealthBar,
  defaultSettings = defaultSettings,
  generalDefaults = generalDefaults,
  options = options,
  generalOptions = generalOptions,
  events = { "UpdateHealth" },
  flags = {},
  enabledInThisExpansion = true,
  attachSettingsToButton = false,
  order = 1,
})

local healthBarText = BattleGroundEnemies:NewButtonModule({
  moduleName = "healthBarText",
  localizedModuleName = L.HealthTextSettings,
  defaultSettings = healthTextDefaultSettings,
  options = healthTextOptions,
  events = { "UpdateHealth" },
  enabledInThisExpansion = true,
  attachSettingsToButton = false,
  order = 1.1, -- This will sort it right after Healthbar
})

function healthBar:AttachToPlayerButton(playerButton)
  playerButton.healthBar = CreateFrame("StatusBar", nil, playerButton)
  playerButton.healthBar:SetMinMaxValues(0, 1)
  playerButton.healthBar:SetValue(1)
  playerButton.healthBar:SetClipsChildren(true)

  -- Mix in Blizzard's SmoothStatusBarMixin for lerped health transitions.
  playerButton.powerBarUsedHeight = 0

  if CreateUnitHealPredictionCalculator then
    playerButton.healPredCalc = CreateUnitHealPredictionCalculator()
    playerButton.healPredCalc:SetIncomingHealOverflowPercent(1.05)
  end

  local hbLevel = playerButton.healthBar:GetFrameLevel()
  local function CreatePredictionBar(level, r, g, b, a)
    local bar = CreateFrame("StatusBar", nil, playerButton.healthBar)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar:GetStatusBarTexture():SetVertexColor(r, g, b, a or 1)
    bar:SetFrameLevel(hbLevel + (level or 1))
    bar:Hide()
    return bar
  end

  playerButton.myHealPrediction = CreatePredictionBar(1, 8 / 255, 93 / 255, 72 / 255)
  playerButton.otherHealPrediction = CreatePredictionBar(1, 11 / 255, 53 / 255, 43 / 255)
  playerButton.totalAbsorb = CreatePredictionBar(2, 1, 1, 1)
  playerButton.totalAbsorb:SetStatusBarTexture("Interface\\RaidFrame\\Shield-Fill")

  playerButton.totalAbsorbOverlay = playerButton.healthBar:CreateTexture(nil, "ARTWORK", nil, 4)
  playerButton.totalAbsorbOverlay:SetTexture("Interface\\RaidFrame\\Shield-Overlay", true, true)
  playerButton.totalAbsorbOverlay.tileSize = 20
  playerButton.totalAbsorbOverlay:SetAllPoints(playerButton.totalAbsorb:GetStatusBarTexture())

  playerButton.myHealAbsorb = CreatePredictionBar(2, 0.7, 0.0, 0.0, 0.7)
  playerButton.myHealAbsorb:SetStatusBarTexture("Interface\\RaidFrame\\Absorb-Fill")
  playerButton.myHealAbsorb:SetReverseFill(true)

  playerButton.overAbsorbGlow = playerButton.healthBar:CreateTexture(nil, "ARTWORK", nil, 2)
  playerButton.overAbsorbGlow:SetTexture("Interface\\RaidFrame\\Shield-Overshield")
  playerButton.overAbsorbGlow:SetBlendMode("ADD")
  playerButton.overAbsorbGlow:SetPoint("BOTTOMLEFT", playerButton.healthBar, "BOTTOMRIGHT", -7, 0)
  playerButton.overAbsorbGlow:SetPoint("TOPLEFT", playerButton.healthBar, "TOPRIGHT", -7, 0)
  playerButton.overAbsorbGlow:SetWidth(16)
  playerButton.overAbsorbGlow:Hide()

  playerButton.overHealAbsorbGlow = playerButton.healthBar:CreateTexture(nil, "ARTWORK", nil, 2)
  playerButton.overHealAbsorbGlow:SetTexture("Interface\\RaidFrame\\Absorb-Overabsorb")
  playerButton.overHealAbsorbGlow:SetBlendMode("ADD")
  playerButton.overHealAbsorbGlow:SetPoint("BOTTOMRIGHT", playerButton.healthBar, "BOTTOMLEFT", 7, 0)
  playerButton.overHealAbsorbGlow:SetPoint("TOPRIGHT", playerButton.healthBar, "TOPLEFT", 7, 0)
  playerButton.overHealAbsorbGlow:SetWidth(16)
  playerButton.overHealAbsorbGlow:Hide()

  playerButton.myHealAbsorbLeftShadow = playerButton.healthBar:CreateTexture(nil, "ARTWORK", nil, 3)
  playerButton.myHealAbsorbLeftShadow:ClearAllPoints()
  playerButton.myHealAbsorbRightShadow = playerButton.healthBar:CreateTexture(nil, "ARTWORK", nil, 3)
  playerButton.myHealAbsorbRightShadow:ClearAllPoints()

  playerButton.healthBar.Background = playerButton.healthBar:CreateTexture(nil, "BACKGROUND", nil, 2)
  playerButton.healthBar.Background:SetAllPoints()
  playerButton.healthBar.Background:SetTexture("Interface/Buttons/WHITE8X8")

  function playerButton.healthBar:UpdateHealth(unitID, health, healthMissing, healthPercent, maxHealth)
    -- Fetch live health if arguments are missing
    if not health and unitID then
      local ok, h = pcall(UnitHealth, unitID)
      health = (ok and h) or nil
    end
    if not maxHealth and unitID then
      local ok3, hMax = pcall(UnitHealthMax, unitID)
      maxHealth = (ok3 and hMax) or nil
    end

    -- Dead: force health to 0, hide prediction
    if playerButton.isDead then
      self:SetMinMaxValues(0, maxHealth or 1)
      self:SetValue(0)
      playerButton.myHealPrediction:Hide()
      playerButton.otherHealPrediction:Hide()
      playerButton.totalAbsorb:Hide()
      playerButton.totalAbsorbOverlay:Hide()
      playerButton.overAbsorbGlow:Hide()
      playerButton.myHealAbsorb:Hide()
      playerButton.overHealAbsorbGlow:Hide()
      return
    end

    -- If pcall fell back to nil, don't clobber the bar — keep prior values.
    -- SetMinMaxValues/SetValue require numbers and will error on nil.
    if not health or not maxHealth then
      return
    end

    self:SetMinMaxValues(0, maxHealth)
    self:SetValue(health)

    local calc = playerButton.healPredCalc
    if unitID and calc and UnitGetDetailedHealPrediction then
      UnitGetDetailedHealPrediction(unitID, "player", calc)

      local max = calc:GetMaximumHealth()
      local mainTex = self:GetStatusBarTexture()
      local barWidth = self:GetWidth()

      local allHeal, playerHeal, otherHeal, healClamped = calc:GetIncomingHeals()
      playerButton.myHealPrediction:ClearAllPoints()
      playerButton.myHealPrediction:SetPoint("TOPLEFT", mainTex, "TOPRIGHT", 0, 0)
      playerButton.myHealPrediction:SetPoint("BOTTOMLEFT", mainTex, "BOTTOMRIGHT", 0, 0)
      playerButton.myHealPrediction:SetWidth(barWidth)
      playerButton.myHealPrediction:SetMinMaxValues(0, max)
      playerButton.myHealPrediction:SetValue(playerHeal)
      playerButton.myHealPrediction:Show()

      local prevTex = playerButton.myHealPrediction:GetStatusBarTexture()
      playerButton.otherHealPrediction:ClearAllPoints()
      playerButton.otherHealPrediction:SetPoint("TOPLEFT", prevTex, "TOPRIGHT", 0, 0)
      playerButton.otherHealPrediction:SetPoint("BOTTOMLEFT", prevTex, "BOTTOMRIGHT", 0, 0)
      playerButton.otherHealPrediction:SetWidth(barWidth)
      playerButton.otherHealPrediction:SetMinMaxValues(0, max)
      playerButton.otherHealPrediction:SetValue(otherHeal)
      playerButton.otherHealPrediction:Show()

      local damageAbsorbAmount, damageAbsorbClamped = calc:GetDamageAbsorbs()
      local prevAbsorbTex = playerButton.otherHealPrediction:GetStatusBarTexture()
      playerButton.totalAbsorb:ClearAllPoints()
      playerButton.totalAbsorb:SetPoint("TOPLEFT", prevAbsorbTex, "TOPRIGHT", 0, 0)
      playerButton.totalAbsorb:SetPoint("BOTTOMLEFT", prevAbsorbTex, "BOTTOMRIGHT", 0, 0)
      playerButton.totalAbsorb:SetWidth(barWidth)
      playerButton.totalAbsorb:SetMinMaxValues(0, max)
      playerButton.totalAbsorb:SetValue(damageAbsorbAmount)
      playerButton.totalAbsorb:Show()
      playerButton.totalAbsorbOverlay:Show()

      playerButton.overAbsorbGlow:SetAlphaFromBoolean(damageAbsorbClamped, 1, 0)

      local healAbsorbAmount, healAbsorbClamped = calc:GetHealAbsorbs()
      playerButton.myHealAbsorb:ClearAllPoints()
      playerButton.myHealAbsorb:SetPoint("TOPRIGHT", mainTex, "TOPRIGHT", 0, 0)
      playerButton.myHealAbsorb:SetPoint("BOTTOMRIGHT", mainTex, "BOTTOMRIGHT", 0, 0)
      playerButton.myHealAbsorb:SetWidth(barWidth)
      playerButton.myHealAbsorb:SetMinMaxValues(0, max)
      playerButton.myHealAbsorb:SetValue(healAbsorbAmount)
      playerButton.myHealAbsorb:Show()

      playerButton.overHealAbsorbGlow:SetAlphaFromBoolean(healAbsorbClamped, 1, 0)
    else
      playerButton.myHealPrediction:Hide()
      playerButton.otherHealPrediction:Hide()
      playerButton.totalAbsorb:Hide()
      playerButton.totalAbsorbOverlay:Hide()
      playerButton.overAbsorbGlow:Hide()
      playerButton.myHealAbsorb:Hide()
      playerButton.overHealAbsorbGlow:Hide()
    end
  end

  function playerButton.healthBar:ApplyAllSettings()
    if not self.config then
      return
    end
    local config = self.config
    self:SetStatusBarTexture(LSM:Fetch("statusbar", config.Texture))
    self.Background:SetVertexColor(unpack(config.Background))

    local playerDetails = playerButton.PlayerDetails
    if not playerDetails then
      return
    end
    local color = playerDetails.PlayerClassColor
    self:SetStatusBarColor(color.r, color.g, color.b)
  end
  return playerButton.healthBar
end

function healthBarText:AttachToPlayerButton(playerButton)
  local container = CreateFrame("Frame", nil, playerButton)
  container:SetSize(60, 20)
  container:SetFrameLevel(playerButton:GetFrameLevel() + 20) -- Ensure it's clickable

  container.fs = BattleGroundEnemies.MyCreateFontString(container)
  container.fs:SetWordWrap(false)
  container.fs:SetAllPoints()

  container.GetOptionsPath = function(self)
    local optionsPath = CopyTable(playerButton.basePath)
    table.insert(optionsPath, "ModuleSettings")
    table.insert(optionsPath, "healthBarText")
    return optionsPath
  end

  container.GetConfig = function(self)
    local modules = playerButton.playerCountConfig.ButtonModules
    if not modules.healthBarText then
      modules.healthBarText = CopyTable(healthTextDefaultSettings)
    end
    return modules.healthBarText
  end

  function container:UpdateHealthText(unitID, health, healthMissing, healthPercent, maxHealth)
    local config = self.config
    if not config or not config.Enabled then
      self.fs:Hide()
      return
    end

    local ok, err = pcall(function()
      -- Test mode: Use fake health values (old math-based approach works here)
      if BattleGroundEnemies:IsTestmodeOrEditmodeActive() then
        if not health or not maxHealth then
          health = 50000
          healthPercent = 50
          healthMissing = 50000
          maxHealth = 100000
        end
      end

      if health and maxHealth then
        if config.HealthTextType == "health" then
          health = AbbreviateNumbers(health)
          self.fs:SetText(health)
          self.fs:Show()
        elseif config.HealthTextType == "losthealth" then
          healthMissing = AbbreviateNumbers(healthMissing)
          self.fs:SetText(healthMissing)
          self.fs:Show()
        elseif config.HealthTextType == "perc" then
          self.fs:SetFormattedText("%d%%", healthPercent)
          self.fs:Show()
        else
          self.fs:Hide()
        end
      else
        self.fs:Hide()
      end
    end)

    if not ok then
      -- Verification failed (likely secret value math), hide text
      self.fs:Hide()
    end
  end

  function container:UpdateHealth(unitID, health, healthMissing, healthPercent, maxHealth)
    self:UpdateHealthText(unitID, health, healthMissing, healthPercent, maxHealth)
  end

  function container:ApplyAllSettings()
    if not self.config then
      return
    end
    local config = self.config

    -- Force default for existing profiles
    if config.UseButtonWidthAsWidth == nil then
      config.UseButtonWidthAsWidth = true
    end

    -- Migration Logic: If this is a new setup, try to copy from the old healthBar.HealthText sub-table
    local oldBarConfig = playerButton.healthBar and playerButton.healthBar.config
    if oldBarConfig and oldBarConfig.HealthText and not self.hasMigrated then
      -- Only migrate if the new config matches defaults (meaning it hasn't been touched yet)
      if config.FontSize == healthTextDefaultSettings.FontSize then
        Mixin(config, oldBarConfig.HealthText)
        self.hasMigrated = true
      end
    end

    if config.Enabled then
      self.fs:Show()
    else
      self.fs:Hide()
    end

    self.fs:ApplyFontStringSettings(config)

    self:ClearAllPoints()
    for j = 1, config.ActivePoints or 1 do
      local pointConfig = config.Points[j]
      if pointConfig and pointConfig.RelativeFrame then
        local relativeFrame = playerButton:GetAnchor(pointConfig.RelativeFrame)
        if relativeFrame then
          local effectiveScale = self:GetEffectiveScale()
          self:SetPoint(
            pointConfig.Point,
            relativeFrame,
            pointConfig.RelativePoint,
            (pointConfig.OffsetX or 0) / effectiveScale,
            (pointConfig.OffsetY or 0) / effectiveScale
          )
        end
      end
    end

    if config.Parent then
      self:SetParent(playerButton:GetAnchor(config.Parent))
    end

    local width = config.Width or 500
    if config.UseButtonHeightAsWidth then
      width = playerButton:GetHeight()
    elseif config.UseButtonWidthAsWidth then
      width = (playerButton.playerCountConfig and playerButton.playerCountConfig.BarWidth) or playerButton:GetWidth()
    end

    local height = config.Height or 20
    if config.UseButtonHeightAsHeight then
      height = playerButton:GetHeight()
    end

    self:SetSize(width, height)

    if self.AnchorSelectionFrame then
      self:AnchorSelectionFrame()
    end

    self:UpdateHealthText(nil, nil, nil, nil, nil)
  end

  playerButton.healthBarText = container
  return playerButton.healthBarText
end
