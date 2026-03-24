---@type string
local AddonName = ...
---@class Data
local Data = select(2, ...)
---@class BattleGroundEnemies
local BattleGroundEnemies = BattleGroundEnemies
local L = Data.L

local CreateFrame = CreateFrame

local defaultSettings = {
  Enabled = true,
  Parent = "healthBar",
  IconWidth = 8,
  IconHeight = 10,
  IconSpacing = 10,
  ActivePoints = 1,
  Points = {
    {
      Point = "TOP",
      RelativeFrame = "healthBar",
      RelativePoint = "TOP",
      OffsetX = 0,
    },
  },
}

local options = function(location)
  return {
    IconWidth = {
      type = "range",
      name = L.Width,
      min = 1,
      max = 20,
      step = 1,
      width = "normal",
      order = 1,
    },
    IconHeight = {
      type = "range",
      name = L.Height,
      min = 1,
      max = 20,
      step = 1,
      width = "normal",
      order = 2,
    },
    IconSpacing = {
      type = "range",
      name = L.HorizontalSpacing,
      min = 1,
      max = 20,
      step = 1,
      width = "normal",
      order = 3,
    },
  }
end

local symbolicTargetIndicator = BattleGroundEnemies:NewButtonModule({
  moduleName = "TargetIndicatorSymbolic",
  localizedModuleName = L.TargetIndicatorSymbolic,
  defaultSettings = defaultSettings,
  options = options,
  events = { "UpdateTargetIndicators", "PlayerButtonSizeChanged" },
  enabledInThisExpansion = true,
  attachSettingsToButton = true,
})

function symbolicTargetIndicator:AttachToPlayerButton(playerButton)
  playerButton.TargetIndicatorSymbolic =
    CreateFrame("frame", nil, playerButton, BackdropTemplateMixin and "BackdropTemplate")
  playerButton.TargetIndicatorSymbolic:SetFrameStrata("TOOLTIP")
  playerButton.TargetIndicatorSymbolic:SetSize(playerButton:GetWidth() > 0 and playerButton:GetWidth() or 200, 20)
  playerButton.TargetIndicatorSymbolic.Symbols = {}

  function playerButton.TargetIndicatorSymbolic:PlayerButtonSizeChanged(width, height)
    self:SetWidth(width)
  end

  playerButton.TargetIndicatorSymbolic.SetSizeAndPosition = function(self, index)
    local config = self.config
    local symbol = self.Symbols[index]
    if not symbol then
      return
    end
    if not (config.IconWidth and config.IconHeight) then
      return
    end
    symbol:SetSize(config.IconWidth, config.IconHeight)
    symbol:SetPoint("TOP", math.floor(index / 2) * (index % 2 == 0 and -config.IconSpacing or config.IconSpacing), 0) --1: 0, 0 2: -10, 0 3: 10, 0 4: -20, 0 > i = even > left, uneven > right
  end

  function playerButton.TargetIndicatorSymbolic:UpdateTargetIndicators()
    self:GetConfig()

    -- Render-time validation: prune stale entries where the source button's
    -- .Target no longer points back to us. This catches phantom indicators
    -- caused by PID oscillation leaving orphaned TargetedByEnemy entries.
    local stale
    for sourceButton in pairs(playerButton.UnitIDs.TargetedByEnemy) do
      if sourceButton.Target ~= playerButton then
        stale = stale or {}
        stale[#stale + 1] = sourceButton
      end
    end
    if stale then
      for _, key in ipairs(stale) do
        playerButton.UnitIDs.TargetedByEnemy[key] = nil
      end
    end

    local i = 1
    for enemyButton in pairs(playerButton.UnitIDs.TargetedByEnemy) do
      local indicator = self.Symbols[i]
      if not indicator then
        indicator =
          CreateFrame("frame", nil, playerButton.TargetIndicatorSymbolic, BackdropTemplateMixin and "BackdropTemplate")
        indicator:SetBackdrop({
          bgFile = "Interface/Buttons/WHITE8X8", --drawlayer "BACKGROUND"
          edgeFile = "Interface/Buttons/WHITE8X8", --drawlayer "BORDER"
          edgeSize = 1,
        })
        indicator:SetBackdropBorderColor(0, 0, 0, 1)
        indicator:SetFrameStrata("TOOLTIP")
        self.Symbols[i] = indicator

        self:SetSizeAndPosition(i)
      end
      local classColor = enemyButton.PlayerDetails.PlayerClassColor
      indicator:SetBackdropColor(classColor.r, classColor.g, classColor.b)
      indicator:Show()

      i = i + 1
    end

    while self.Symbols[i] do --hide no longer used ones
      self.Symbols[i]:Hide()
      i = i + 1
    end
  end

  playerButton.TargetIndicatorSymbolic.ApplyAllSettings = function(self)
    if not self.config then
      return
    end
    for i = 1, #self.Symbols do
      self:SetSizeAndPosition(i)
    end
  end
  return playerButton.TargetIndicatorSymbolic
end
