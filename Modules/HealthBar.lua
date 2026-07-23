---@class Data
local Data = select(2, ...)
---@class BattleGroundEnemies
local BattleGroundEnemies = BattleGroundEnemies
local LSM = LibStub("LibSharedMedia-3.0")
local L = Data.L

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
  flags = {
    -- Healthbar is auto-managed by SetModulePositions: full button width,
    -- height = button height minus the power bar. Don't expose per-player-count UI for it.
    HiddenFromPerPlayerCountUI = true,
  },
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
    -- Fetch live health if arguments are missing. 12.0.7: UnitHealth/UnitHealthMax
    -- (UnitTokenPvPRestrictedForAddOns) return nil instead of erroring on
    -- compound/restricted tokens, so the old pcall is redundant — a nil falls
    -- through to the keep-prior guard below.
    if not health and unitID then
      health = UnitHealth(unitID)
    end
    if not maxHealth and unitID then
      maxHealth = UnitHealthMax(unitID)
    end

    -- Dead: force health to 0, hide prediction. Range only needs to exist
    -- (any range shows an empty bar at 0) — don't re-hammer it per write.
    if playerButton.isDead then
      if not self._rangeSetAt then
        self:SetMinMaxValues(0, maxHealth or 1)
        self._rangeSetAt = GetTime()
        self._rangeBasisTok = unitID
      end
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

    -- Blizzard-shaped range handling (CompactUnitFrame model): the range is
    -- NOT re-set on every health write — Blizzard sets it in a separate
    -- function on UNIT_MAXHEALTH and SetValue()s health alone. Post-12.0.7
    -- maxHealth is a FRESH SECRET object per read, so the old per-write
    -- SetMinMaxValues re-based the bar's range against a new secret up to
    -- ~60x/s while SetValue raced it. Refresh the range only when:
    --   * _rangeDirty — the UNIT_MAXHEALTH event fired for this button
    --     (playerButton:UNIT_MAXHEALTH), i.e. the max ACTUALLY changed;
    --   * the writing token CHANGES (plain string compare — never secrets):
    --     a new read basis deserves a matching new range;
    --   * it was never set (fresh/reset bar).
    if self._rangeDirty or self._rangeBasisTok ~= unitID or not self._rangeSetAt then
      self:SetMinMaxValues(0, maxHealth)
      self._rangeDirty = nil
      self._rangeBasisTok = unitID
      self._rangeSetAt = GetTime()
    end
    self:SetValue(health)

    local calc = playerButton.healPredCalc
    if unitID and calc and UnitGetDetailedHealPrediction then
      UnitGetDetailedHealPrediction(unitID, "player", calc)

      local max = calc:GetMaximumHealth()
      local mainTex = self:GetStatusBarTexture()
      local barWidth = self:GetWidth()

      -- #4-S1: the anchor relationships for the 4 heal-prediction sub-bars are
      -- INVARIANT across calls — each pins to the moving right/left edge of the
      -- previous bar's StatusBar texture with offset 0, and the engine re-follows
      -- that edge as SetValue resizes the texture. So set the anchors ONCE (lazy,
      -- behind predictionAnchorsSet) instead of ClearAllPoints + 2x SetPoint per
      -- bar on every UNIT_HEALTH (~300-410/s). The flag is cleared on a texture
      -- swap (ApplyAllSettings) so we re-anchor to the new mainTex; width is
      -- cached and re-applied on resize (SetModulePositions). The main healthBar
      -- has no StatusBar texture until ApplyAllSettings runs, so this must be lazy
      -- here, not in AttachToPlayerButton.
      local _, playerHeal, otherHeal, _ = calc:GetIncomingHeals()
      if not self.predictionAnchorsSet then
        playerButton.myHealPrediction:SetPoint("TOPLEFT", mainTex, "TOPRIGHT", 0, 0)
        playerButton.myHealPrediction:SetPoint("BOTTOMLEFT", mainTex, "BOTTOMRIGHT", 0, 0)
        local prevTex = playerButton.myHealPrediction:GetStatusBarTexture()
        playerButton.otherHealPrediction:SetPoint("TOPLEFT", prevTex, "TOPRIGHT", 0, 0)
        playerButton.otherHealPrediction:SetPoint("BOTTOMLEFT", prevTex, "BOTTOMRIGHT", 0, 0)
        local prevAbsorbTex = playerButton.otherHealPrediction:GetStatusBarTexture()
        playerButton.totalAbsorb:SetPoint("TOPLEFT", prevAbsorbTex, "TOPRIGHT", 0, 0)
        playerButton.totalAbsorb:SetPoint("BOTTOMLEFT", prevAbsorbTex, "BOTTOMRIGHT", 0, 0)
        playerButton.myHealAbsorb:SetPoint("TOPRIGHT", mainTex, "TOPRIGHT", 0, 0)
        playerButton.myHealAbsorb:SetPoint("BOTTOMRIGHT", mainTex, "BOTTOMRIGHT", 0, 0)
        self.predictionAnchorsSet = true
      end

      -- barWidth (= healthBar width) only changes on a button resize. Cache it so
      -- we skip 4 SetWidth + layout-dirty per fire in steady state. Invalidated in
      -- playerButton:SetModulePositions (the sole place the bar width changes).
      if self.cachedBarWidth ~= barWidth then
        playerButton.myHealPrediction:SetWidth(barWidth)
        playerButton.otherHealPrediction:SetWidth(barWidth)
        playerButton.totalAbsorb:SetWidth(barWidth)
        playerButton.myHealAbsorb:SetWidth(barWidth)
        self.cachedBarWidth = barWidth
      end

      playerButton.myHealPrediction:SetMinMaxValues(0, max)
      playerButton.myHealPrediction:SetValue(playerHeal)
      playerButton.myHealPrediction:Show()

      local damageAbsorbAmount, damageAbsorbClamped = calc:GetDamageAbsorbs()
      playerButton.otherHealPrediction:SetMinMaxValues(0, max)
      playerButton.otherHealPrediction:SetValue(otherHeal)
      playerButton.otherHealPrediction:Show()

      playerButton.totalAbsorb:SetMinMaxValues(0, max)
      playerButton.totalAbsorb:SetValue(damageAbsorbAmount)
      playerButton.totalAbsorb:Show()
      playerButton.totalAbsorbOverlay:Show()

      playerButton.overAbsorbGlow:SetAlphaFromBoolean(damageAbsorbClamped, 1, 0)

      local healAbsorbAmount, healAbsorbClamped = calc:GetHealAbsorbs()
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

  -- Reset is called from SetupButtonForNewPlayer when this button gets
  -- recycled to represent a different player (new BG, new opponent in
  -- this slot, etc.). Restore the bar to its initial 100% state and hide
  -- all overlays so stale values from the previous player don't bleed
  -- through. Distinct from the "token lost mid-match" path, which keeps
  -- the last value (DeleteActiveUnitID no longer touches the bar).
  function playerButton.healthBar:Reset()
    self:SetMinMaxValues(0, 1)
    self:SetValue(1)
    -- New occupant = new range basis (see the Blizzard-shaped range handling
    -- in UpdateHealth): force the first write to establish a fresh range.
    self._rangeBasisTok = nil
    self._rangeSetAt = nil
    self._rangeDirty = nil
    if playerButton.myHealPrediction then
      playerButton.myHealPrediction:Hide()
    end
    if playerButton.otherHealPrediction then
      playerButton.otherHealPrediction:Hide()
    end
    if playerButton.totalAbsorb then
      playerButton.totalAbsorb:Hide()
    end
    if playerButton.totalAbsorbOverlay then
      playerButton.totalAbsorbOverlay:Hide()
    end
    if playerButton.overAbsorbGlow then
      playerButton.overAbsorbGlow:Hide()
    end
    if playerButton.myHealAbsorb then
      playerButton.myHealAbsorb:Hide()
    end
    if playerButton.overHealAbsorbGlow then
      playerButton.overHealAbsorbGlow:Hide()
    end
  end

  function playerButton.healthBar:ApplyAllSettings()
    if not self.config then
      return
    end
    local config = self.config
    self:SetStatusBarTexture(LSM:Fetch("statusbar", config.Texture))
    -- #4-S1: SetStatusBarTexture can swap the underlying texture object, which
    -- invalidates the one-shot heal-prediction anchors (they pin to it). Clear the
    -- flag so the next UpdateHealth re-anchors to the current texture. Placed before
    -- the playerDetails early-return below so it fires whenever the texture swaps.
    self.predictionAnchorsSet = nil
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

    -- Test mode override: synthetic values when the test harness is active.
    -- Skip FAKE players: their health is always computed via FakeUnitHealth(), so
    -- a nil here means a settings re-apply churn (ApplyAllSettings ->
    -- UpdateHealthText(nil,...)), NOT missing data. Forcing 50% on them blanked
    -- the simulated value on every unrelated settings change. Falling through
    -- instead hits the keep-last-value guard below, preserving the sim. Real
    -- players that genuinely lack health data still get the 50% fallback.
    if
      BattleGroundEnemies:IsTestmodeActive()
      and not (playerButton.PlayerDetails and playerButton.PlayerDetails.isFakePlayer)
    then
      if not health or not maxHealth then
        health = 50000
        healthPercent = 50
        healthMissing = 50000
        maxHealth = 100000
      end
    end

    -- Missing live values: don't clobber the text — return early and leave
    -- the last shown value in place. This matches the healthBar:UpdateHealth
    -- behavior up at line ~254 ("If pcall fell back to nil, don't clobber
    -- the bar — keep prior values"). Without this guard we Hide() on every
    -- nil-yielding update path (raidNtarget that resolved to a non-existent
    -- unit, ScanTargets sweeps that pre-empt a real read, etc.) and Show()
    -- on the next real update — that's the rapid flash.
    -- Secret values are NOT excluded: AbbreviateNumbers / SetFormattedText
    -- both have SecretArguments="AllowedWhenTainted" per Blizzard's API
    -- docs, so they accept and display secret values without tainting.
    if not health or not maxHealth then
      -- Missing values: keep the last shown text. Diagnostic print kept
      -- below as a commented block — re-enable to debug a future flash.
      -- local diagBtn = playerButton.PlayerIsEnemy
      --     and playerButton.PlayerDetails
      --     and playerButton.PlayerDetails.PlayerName
      --     or nil
      -- if diagBtn then
      --   local issecret = issecretvalue or function() return false end
      --   local function tag(v)
      --     if v == nil then return "nil" end
      --     if issecret(v) then return "secret" end
      --     return tostring(v)
      --   end
      --   print(string.format(
      --     "|cffaa66ff[BGEF text]|r %s SKIP-keep-last u=%s h=%s hM=%s hp=%s mh=%s",
      --     diagBtn, tostring(unitID), tag(health), tag(healthMissing),
      --     tag(healthPercent), tag(maxHealth)
      --   ))
      -- end
      return
    end

    -- Defense-in-depth pcall around the format/set calls. AbbreviateNumbers
    -- and the SetText / SetFormattedText methods all accept secret args
    -- per API docs, so this should rarely fire — but if any unexpected
    -- error occurs, treat it the same as nil values: keep the last shown
    -- text rather than hiding (which would cause flash).
    local _, _ = pcall(function()
      if config.HealthTextType == "health" then
        self.fs:SetText(AbbreviateNumbers(health))
        self.fs:Show()
      elseif config.HealthTextType == "losthealth" then
        self.fs:SetText(AbbreviateNumbers(healthMissing or 0))
        self.fs:Show()
      elseif config.HealthTextType == "perc" then
        self.fs:SetFormattedText("%d%%", healthPercent)
        self.fs:Show()
      else
        self.fs:Hide()
      end
    end)

    -- if not ok then
    --   -- pcall failed (unexpected). Keep last shown value rather than
    --   -- hiding (matches the nil-values branch above). Re-enable the
    --   -- print block here to surface the error if a flash recurs.
    --   local diagBtn = playerButton.PlayerIsEnemy
    --       and playerButton.PlayerDetails
    --       and playerButton.PlayerDetails.PlayerName
    --       or nil
    --   if diagBtn then
    --     print(string.format(
    --       "|cffaa66ff[BGEF text]|r %s SKIP-pcall-err u=%s err=%s",
    --       diagBtn, tostring(unitID), tostring(err)
    --     ))
    --   end
    -- end
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

  -- Reset is called when the button gets recycled for a new player AND
  -- when the module is disabled via config. Hide the FontString and clear
  -- its string so a recycled button never re-shows the PREVIOUS occupant's
  -- "X%" between BGs (UpdateHealthText's keep-last-on-nil guard and
  -- ApplyAllSettings's unconditional Show would otherwise re-expose it).
  -- The SetText("") MUST be guarded by GetFont(): ApplyModuleSettings can
  -- call Reset on the disable path before the font has been set on the
  -- FontString, and SetText errors with "Font not set" when no font is set.
  -- GetFont() returns nil until SetFont has run (same idiom as Blizzard's
  -- SecureUtil and this addon's ObjectiveAndRespawn/TargetIndicatorNumeric
  -- Resets). The "" literal carries no secret value, so this is secret-safe.
  function container:Reset()
    self.fs:Hide()
    if self.fs:GetFont() then
      self.fs:SetText("")
    end
  end

  playerButton.healthBarText = container
  return playerButton.healthBarText
end
