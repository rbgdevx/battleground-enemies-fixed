-- luacheck: read globals ARENA C_CurveUtil SHOW_ENEMY_CAST UnitCastingDuration UnitCastingInfo UnitChannelDuration UnitChannelInfo UnitEmpoweredChannelDuration UnitEmpoweredStagePercentages
---@class Data
local Data = select(2, ...)
---@class BattleGroundEnemies
local BattleGroundEnemies = BattleGroundEnemies
local L = Data.L
local IsTestmodeActive = BattleGroundEnemies.IsTestmodeActive
local DoesTemplateExist = DoesTemplateExist
local OnetimeInformation = BattleGroundEnemies.OnetimeInformation
local CreateFrame = CreateFrame
local CreateCurve = C_CurveUtil.CreateCurve
local GetSpellInfo = C_Spell.GetSpellInfo
local UnitCastingInfo = UnitCastingInfo
local UnitCastingDuration = UnitCastingDuration
local UnitChannelInfo = UnitChannelInfo
local UnitChannelDuration = UnitChannelDuration
local UnitEmpoweredChannelDuration = UnitEmpoweredChannelDuration
local UnitEmpoweredStagePercentages = UnitEmpoweredStagePercentages
local StepCurve = Enum.LuaCurveType.Step
local StatusBarInterpolation = Enum.StatusBarInterpolation
local StatusBarTimerDirection = Enum.StatusBarTimerDirection
local math_min = math.min
local math_random = math.random
local PREVIEW_FALLBACK_ICON = "Interface/Icons/INV_Misc_QuestionMark"
local PREVIEW_CAST_DURATION = 2.5
local PREVIEW_CAST_CYCLE = PREVIEW_CAST_DURATION + 0.5
local previewStageFraction = PREVIEW_CAST_DURATION / (4 * PREVIEW_CAST_CYCLE)
local previewCasts = {
  { spellID = 118, name = "Polymorph", notInterruptible = false },
  { spellID = 118, name = "Polymorph", notInterruptible = true },
  {
    spellID = 357208,
    name = "Fire Breath",
    notInterruptible = false,
    stages = {
      previewStageFraction,
      previewStageFraction,
      previewStageFraction,
      previewStageFraction,
      1 - 4 * previewStageFraction,
    },
  },
}

-- Blizzard's Normal and Small TextBorder extends 12 units under the fill.
local CAST_BAR_LABEL_HEIGHT = 12

local templates = {
  -- Match PlayerCastingBarFrame's XML size for the unsized Normal template.
  Normal = { name = "CastingBarFrameTemplate", width = 208, height = 11 },
  -- TargetSpellBarTemplate sets these dimensions on the shared Small art.
  Small = { name = "SmallCastingBarFrameTemplate", width = 150, height = 10 },
  Arena = DoesTemplateExist("ArenaCastingBarFrameTemplate") and { name = "ArenaCastingBarFrameTemplate" },
}

local styles = {
  Arena = templates.Arena and ARENA or nil,
  Normal = L.NormalCastingBar,
  Small = L.SmallCastingBar,
}

local defaultSettings = {
  Parent = "Button",
  ActivePoints = 1,
  Style = "Small",
  Scale = 1,
}

local options = function()
  return {
    Style = {
      type = "select",
      name = L.Style,
      values = styles,
      order = 1,
    },
    Scale = {
      type = "range",
      name = L.Scale,
      min = 0.1,
      max = 2,
      step = 0.05,
      order = 2,
    },
  }
end

local castBar = BattleGroundEnemies:NewButtonModule({
  moduleName = "CastBar",
  localizedModuleName = SHOW_ENEMY_CAST,
  defaultSettings = defaultSettings,
  options = options,
  flags = {
    Height = "Fixed",
    Width = "Fixed",
  },
  events = { "UnitIdUpdate", "OnTestmodeDisabled" },
  enabledInThisExpansion = true,
})

-- A terminal event's value is its never-secret cast-bar ID argument index.
local spellCastEvents = {
  UNIT_SPELLCAST_START = false,
  UNIT_SPELLCAST_DELAYED = false,
  UNIT_SPELLCAST_STOP = 4,
  UNIT_SPELLCAST_FAILED = 4,
  UNIT_SPELLCAST_INTERRUPTED = 5,
  UNIT_SPELLCAST_CHANNEL_START = false,
  UNIT_SPELLCAST_CHANNEL_UPDATE = false,
  UNIT_SPELLCAST_CHANNEL_STOP = 5,
  UNIT_SPELLCAST_EMPOWER_START = false,
  UNIT_SPELLCAST_EMPOWER_UPDATE = false,
  UNIT_SPELLCAST_EMPOWER_STOP = 6,
  UNIT_SPELLCAST_INTERRUPTIBLE = false,
  UNIT_SPELLCAST_NOT_INTERRUPTIBLE = false,
}

local directUnitTokens = {
  player = true,
  target = true,
  focus = true,
  mouseover = true,
  softenemy = true,
}

local function isCastBarUnit(unit)
  -- Row election also accepts compound targets, which cast queries can reject.
  return unit
    and (
      directUnitTokens[unit]
      or unit:match("^arena%d+$")
      or unit:match("^nameplate%d+$")
      or unit:match("^party%d+$")
      or unit:match("^raid%d+$")
    )
end

local function configureCastBarIcon(bar, style, isEnemy)
  local iconPoint = isEnemy and "RIGHT" or "LEFT"
  local barPoint = isEnemy and "LEFT" or "RIGHT"
  local gap = style == "Small" and 2 or 5
  bar.Icon:ClearAllPoints()
  bar.Icon:SetPoint(iconPoint, bar.TextBorder or bar, barPoint, isEnemy and -gap or gap, 0)
  bar.Icon:Show()
end

local function createCastBarDisplay(parent, style)
  local template = templates[style]
  local bar = CreateFrame("StatusBar", nil, parent, template.name)
  -- The templates initialize their art with no unit. Use that art with the
  -- duration APIs instead of the native scripts that inspect secret values.
  bar:SetScript("OnEvent", nil)
  bar:SetScript("OnUpdate", nil)
  bar:SetScript("OnShow", nil)
  bar:Hide()

  configureCastBarIcon(bar, style, parent.playerButton.PlayerIsEnemy)
  bar.Flash:Hide()
  if bar.CastTimeText then
    bar.CastTimeText:Hide()
  end
  bar:SetStatusBarTexture("ui-castingbar-filling-standard")
  bar.Spark:ClearAllPoints()
  bar.Spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT")
  return bar
end

local function readUnitCast(unit)
  local name, text, texture, _, _, isTradeSkill, _, notInterruptible, _, castBarID = UnitCastingInfo(unit)
  if name then
    if not isTradeSkill then
      return UnitCastingDuration(unit), StatusBarTimerDirection.ElapsedTime, text, texture, notInterruptible, castBarID
    end
    return
  end

  local isEmpowered
  name, text, texture, _, _, isTradeSkill, notInterruptible, _, isEmpowered, _, castBarID = UnitChannelInfo(unit)
  if not name or isTradeSkill then
    return
  end
  if isEmpowered then
    return UnitEmpoweredChannelDuration(unit),
      StatusBarTimerDirection.ElapsedTime,
      text,
      texture,
      notInterruptible,
      castBarID,
      UnitEmpoweredStagePercentages(unit)
  end
  return UnitChannelDuration(unit), StatusBarTimerDirection.RemainingTime, text, texture, notInterruptible, castBarID
end

local function applyCastBarAppearance(bar, direction, text, texture, notInterruptible)
  local fill = bar:GetStatusBarTexture()
  local atlas = direction == StatusBarTimerDirection.RemainingTime and "ui-castingbar-filling-channel"
    or "ui-castingbar-filling-standard"
  fill:SetAtlas(atlas)
  -- A missing flag is allowed. Its type is readable even when its value is secret.
  if type(notInterruptible) ~= "boolean" then
    notInterruptible = false
  end
  fill:SetDesaturated(notInterruptible)
  bar.Text:SetText(text)
  bar.Icon:SetTexture(texture)
end

local function createEmpowerStage(bar, index)
  local pipTemplate = bar.StageFlash and "CastingBarFrameStagePipFXTemplate" or "CastingBarFrameStagePipTemplate"
  local pip = CreateFrame("Frame", nil, bar, pipTemplate)
  local tier = CreateFrame("Frame", nil, bar, "CastingBarFrameStageTierTemplate")
  tier.Normal:SetAllPoints(tier)
  tier.Disabled:SetAllPoints(tier)
  tier.Glow:SetAllPoints(tier)
  tier.Disabled:SetDrawLayer("BACKGROUND", 3)
  tier.Normal:SetAtlas(("ui-castingbar-tier%d-empower"):format(index))
  tier.Disabled:SetAtlas(("ui-castingbar-disabled-tier%d-empower"):format(index))
  tier.Glow:SetAtlas(("ui-castingbar-glow-tier%d-empower"):format(index))

  local curve = CreateCurve()
  curve:SetType(StepCurve)
  return { pip = pip, tier = tier, curve = curve }
end

local function positionEmpowerStage(bar, stage, startFraction, endFraction)
  if stage.startFraction == startFraction and stage.endFraction == endFraction then
    return
  end
  stage.startFraction = startFraction
  stage.endFraction = endFraction

  local width = bar:GetWidth()
  local startOffset = width * startFraction
  stage.pip:ClearAllPoints()
  stage.pip:SetPoint("TOP", bar, "TOPLEFT", startOffset, -1)
  stage.pip:SetPoint("BOTTOM", bar, "BOTTOMLEFT", startOffset, 1)
  stage.tier:ClearAllPoints()
  stage.tier:SetPoint("TOPLEFT", stage.pip, "TOP")
  stage.tier:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", width * endFraction, 1)
  stage.tier.Normal:SetTexCoord(startFraction, endFraction, 0, 1)
  stage.tier.Disabled:SetTexCoord(startFraction, endFraction, 0, 1)
  stage.tier.Glow:SetTexCoord(startFraction, endFraction, 0, 1)

  stage.curve:ClearPoints()
  stage.curve:AddPoint(0, 0)
  stage.curve:AddPoint(startFraction, 1)
end

local function hideEmpowerStage(stage)
  stage.charged = false
  stage.tier.Normal:SetAlpha(0)
  stage.tier.FlashAnim:Stop()
  stage.tier.Glow:SetAlpha(0)
  if stage.pip.StageAnim then
    stage.pip.StageAnim:Stop()
  end
  stage.pip:Hide()
  stage.tier:Hide()
end

local function setEmpowerCursor(bar, enabled)
  local fill = bar:GetStatusBarTexture()
  fill:SetAlpha(enabled and 0 or 1)
  bar.Spark:SetAtlas(enabled and "ui-castingbar-empower-cursor" or "ui-castingbar-pip")
  bar.Spark:ClearAllPoints()
  bar.Spark:SetPoint("CENTER", fill, "RIGHT", 0, enabled and 4 or 0)
end

local function clearEmpowerStages(bar)
  if not bar.empowerStageCount then
    return
  end
  for i = 1, bar.empowerStageCount do
    hideEmpowerStage(bar.empowerStages[i])
  end
  if bar.StageFlash then
    bar.StageFlash:Stop()
    bar.StageFinish:Stop()
    bar.ChargeFlash:SetAlpha(0)
  end
  if bar.empowerDuration then
    bar:SetScript("OnUpdate", nil)
    bar.empowerDuration = nil
  end
  bar.empowerStageCount = nil
  setEmpowerCursor(bar, false)
end

local function layoutEmpowerStages(bar, percentages)
  if not percentages or #percentages < 2 then
    clearEmpowerStages(bar)
    return
  end
  if not bar.empowerStages then
    bar.empowerStages = {}
  end
  local previousCount = bar.empowerStageCount or 0
  if previousCount == 0 then
    setEmpowerCursor(bar, true)
  end
  local count = #percentages - 1
  local fraction = 0
  for i = 1, count do
    local stage = bar.empowerStages[i]
    if not stage then
      stage = createEmpowerStage(bar, i)
      bar.empowerStages[i] = stage
    end
    fraction = fraction + percentages[i]
    local endFraction = i == count and 1 or fraction + percentages[i + 1]
    positionEmpowerStage(bar, stage, fraction, endFraction)
    stage.pip:Show()
    stage.tier:Show()
  end
  for i = count + 1, previousCount do
    hideEmpowerStage(bar.empowerStages[i])
  end
  bar.empowerStageCount = count
end

local function playEmpowerStageEffects(bar, index)
  local stage = bar.empowerStages[index]
  stage.tier.FlashAnim:Play()
  if stage.pip.StageAnim then
    stage.pip.StageAnim:Play()
  end
  if bar.StageFlash then
    if index == bar.empowerStageCount then
      bar.StageFinish:Play()
    else
      bar.StageFlash:Play()
    end
  end
end

local function updateEmpowerStages(bar, progress, animate)
  local stageReached
  for i = 1, bar.empowerStageCount do
    local stage = bar.empowerStages[i]
    local charged = progress >= stage.startFraction
    if charged ~= stage.charged then
      stage.charged = charged
      stage.tier.Normal:SetAlpha(charged and 1 or 0)
      if charged then
        stageReached = i
      end
    end
  end
  if animate and stageReached then
    playEmpowerStageEffects(bar, stageReached)
  end
end

local function updateSecretEmpowerStages(bar)
  local duration = bar.empowerDuration
  for i = 1, bar.empowerStageCount do
    local stage = bar.empowerStages[i]
    stage.charged = nil
    stage.tier.Normal:SetAlpha(duration:EvaluateElapsedPercent(stage.curve))
  end
end

local function updateLiveEmpowerStages(bar)
  updateEmpowerStages(bar, bar.empowerDuration:GetElapsedPercent(), true)
end

local function showCastBar(bar, duration, direction, text, texture, notInterruptible, stages)
  applyCastBarAppearance(bar, direction, text, texture, notInterruptible)
  bar:SetTimerDuration(duration, StatusBarInterpolation.Immediate, direction)
  layoutEmpowerStages(bar, stages)
  if bar.empowerStageCount then
    bar.empowerDuration = duration
    local update = duration:HasSecretValues() and updateSecretEmpowerStages or updateLiveEmpowerStages
    bar:SetScript("OnUpdate", update)
    update(bar)
  end
  bar:Show()
end

local function clearCastBar(self)
  self.castBarID = nil
  local bar = self.CastBar
  if bar then
    clearEmpowerStages(bar)
    bar:Hide()
  end
end

local function refreshCastBar(self)
  local duration, direction, text, texture, notInterruptible, castBarID, stages = readUnitCast(self.unit)
  if not duration then
    clearCastBar(self)
    return
  end
  if castBarID ~= self.castBarID then
    clearEmpowerStages(self.CastBar)
  end
  self.castBarID = castBarID
  showCastBar(self.CastBar, duration, direction, text, texture, notInterruptible, stages)
end

local function onSpellCastEvent(self, event, ...)
  local stopIDIndex = spellCastEvents[event]
  if not stopIDIndex then
    refreshCastBar(self)
    return
  end

  local castBarID = select(stopIDIndex, ...)
  if not castBarID or not self.castBarID or castBarID == self.castBarID then
    clearCastBar(self)
  end
end

local function resetCastBar(self)
  self.unit = nil
  self:UnregisterAllEvents()
  local bar = self.CastBar
  if bar and bar.previewElapsed then
    bar:SetScript("OnUpdate", nil)
    bar.previewElapsed = nil
    bar.previewCast = nil
  end
  clearCastBar(self)
end

local function updatePreviewCastProgress(bar, animate)
  if bar.empowerStageCount then
    bar:SetValue(bar.previewElapsed)
    updateEmpowerStages(bar, bar.previewElapsed / PREVIEW_CAST_CYCLE, animate)
  else
    bar:SetValue(math_min(bar.previewElapsed, PREVIEW_CAST_DURATION))
  end
end

local function showPreviewCast(bar, cast)
  clearEmpowerStages(bar)
  local spell = GetSpellInfo(cast.spellID)
  applyCastBarAppearance(
    bar,
    StatusBarTimerDirection.ElapsedTime,
    spell and spell.name or cast.name,
    spell and spell.iconID or PREVIEW_FALLBACK_ICON,
    cast.notInterruptible
  )
  layoutEmpowerStages(bar, cast.stages)
  bar:SetMinMaxValues(0, cast.stages and PREVIEW_CAST_CYCLE or PREVIEW_CAST_DURATION)
  updatePreviewCastProgress(bar, false)
end

local function updateCastBarPreview(bar, elapsed)
  if not BattleGroundEnemies.states.testmodeAnimationEnabled then
    return
  end

  bar.previewElapsed = bar.previewElapsed + elapsed
  if bar.previewElapsed >= PREVIEW_CAST_CYCLE then
    bar.previewElapsed = bar.previewElapsed % PREVIEW_CAST_CYCLE
    local cast = math_random(#previewCasts - 1)
    if cast >= bar.previewCast then
      cast = cast + 1
    end
    bar.previewCast = cast
    showPreviewCast(bar, previewCasts[cast])
  else
    updatePreviewCastProgress(bar, true)
  end
end

local function startCastBarPreview(self)
  local bar = self.CastBar
  if bar.previewElapsed then
    return
  end

  resetCastBar(self)
  bar.previewCast = math_random(#previewCasts)
  bar.previewElapsed = math_random() * PREVIEW_CAST_DURATION
  showPreviewCast(bar, previewCasts[bar.previewCast])
  bar:SetScript("OnUpdate", updateCastBarPreview)
  bar:Show()
end

local function endCastBarPreview(self)
  if self.CastBar and self.CastBar.previewElapsed then
    resetCastBar(self)
  end
end

local function bindCastBarUnit(self, unit)
  if not self.CastBar or self.CastBar.previewElapsed or self.unit == unit then
    return
  end
  resetCastBar(self)
  if not isCastBarUnit(unit) then
    return
  end
  for event in pairs(spellCastEvents) do
    if not self:RegisterUnitEvent(event, unit) then
      self:UnregisterAllEvents()
      return
    end
  end
  self.unit = unit
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  refreshCastBar(self)
end

local function applyCastBarStyle(self, style)
  if not templates[style] then
    style = defaultSettings.Style
    OnetimeInformation(
      BattleGroundEnemies,
      "The Castbar style/template doesnt exist on this client. Automatically set castbar style to: " .. style
    )
  end
  if style == self.style then
    return
  end

  resetCastBar(self)
  local template = templates[style]
  local bar = createCastBarDisplay(self, style)
  local width, height = template.width, template.height
  if not width then
    width, height = bar:GetSize()
  end
  local labelHeight = bar.TextBorder and CAST_BAR_LABEL_HEIGHT or 0
  self:SetSize(width, height + labelHeight)
  bar:SetPoint("TOPLEFT", self, "TOPLEFT")
  bar:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, labelHeight)
  self.CastBar = bar
  self.style = style
end

local function applyCastBarSettings(self)
  if not self.config then
    return
  end
  applyCastBarStyle(self, self.config.Style)
  self:SetScale(self.config.Scale)
  local playerButton = self.playerButton
  if
    IsTestmodeActive(BattleGroundEnemies)
    and playerButton.PlayerDetails
    and playerButton.PlayerDetails.isFakePlayer
  then
    startCastBarPreview(self)
  else
    endCastBarPreview(self)
    bindCastBarUnit(self, playerButton:GetUnitID())
  end
end

function castBar:AttachToPlayerButton(playerButton)
  local frame = CreateFrame("Frame", nil, playerButton)
  frame.playerButton = playerButton
  frame:SetScript("OnEvent", onSpellCastEvent)
  frame.UnitIdUpdate = bindCastBarUnit
  frame.OnTestmodeDisabled = endCastBarPreview
  frame.Reset = resetCastBar
  frame.Disable = resetCastBar
  frame.ApplyAllSettings = applyCastBarSettings
  playerButton.CastBar = frame
  return frame
end
