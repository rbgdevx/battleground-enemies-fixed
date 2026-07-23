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
  events = {
    "UpdateTargetIndicators",
    "PlayerButtonSizeChanged",
    "OnTestmodeEnabled",
    "OnTestmodeDisabled",
    "OnTestmodeTick",
  },
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

  -- Render exactly #colorList class-colored symbols (creating/reusing frames),
  -- then hide any extras. Shared by the live UpdateTargetIndicators path and the
  -- test-mode simulation so both look identical.
  playerButton.TargetIndicatorSymbolic.RenderSymbols = function(self, colorList)
    local i = 1
    for _, classColor in ipairs(colorList) do
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
      indicator:SetBackdropColor(classColor.r, classColor.g, classColor.b)
      indicator:Show()

      i = i + 1
    end

    while self.Symbols[i] do --hide no longer used ones
      self.Symbols[i]:Hide()
      i = i + 1
    end
  end

  function playerButton.TargetIndicatorSymbolic:UpdateTargetIndicators()
    self:GetConfig()

    -- Test mode drives rendering via OnTestmodeTick (fake players have no real
    -- TargetedByEnemy entries); don't let a live update blank the simulation.
    if BattleGroundEnemies:IsTestmodeActive() then
      return
    end

    -- Render-time validation: prune stale entries where the source button's
    -- .Target no longer points back to us (phantom indicators from PID
    -- oscillation leaving orphaned TargetedByEnemy entries), and collect the
    -- class color of each surviving targeter in the same pass.
    local stale
    local colorList = {}
    for sourceButton in pairs(playerButton.UnitIDs.TargetedByEnemy) do
      if sourceButton.Target ~= playerButton then
        stale = stale or {}
        stale[#stale + 1] = sourceButton
      else
        colorList[#colorList + 1] = sourceButton.PlayerDetails.PlayerClassColor
      end
    end
    if stale then
      for _, key in ipairs(stale) do
        playerButton.UnitIDs.TargetedByEnemy[key] = nil
      end
    end

    self:RenderSymbols(colorList)
  end

  -- Test mode: simulate a random number of enemies targeting this player, each
  -- a random class color, so the symbolic indicator is visible/tunable outside a
  -- live BG. Mirrors how the other button modules preview themselves.
  function playerButton.TargetIndicatorSymbolic:OnTestmodeEnabled()
    self.testmodeEnabled = true
  end

  function playerButton.TargetIndicatorSymbolic:OnTestmodeDisabled()
    self.testmodeEnabled = false
    self:RenderSymbols({})
  end

  function playerButton.TargetIndicatorSymbolic:OnTestmodeTick()
    self:GetConfig()
    local classColors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local colorList = {}
    for i = 1, math.random(0, 4) do
      local classToken = CLASS_SORT_ORDER[math.random(1, #CLASS_SORT_ORDER)]
      colorList[i] = classColors[classToken]
    end
    self:RenderSymbols(colorList)
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
