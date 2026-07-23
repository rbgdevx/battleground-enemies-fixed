---@class BattleGroundEnemies
local BattleGroundEnemies = BattleGroundEnemies
---@class Data
local Data = select(2, ...)
local LibSpellIconSelector = LibStub("LibSpellIconSelector")
local L = Data.L

local CTimerNewTicker = C_Timer.NewTicker

local generalDefaults = {
  Combat = {
    Enabled = true,
    Icon = 132147,
  },
  OutOfCombat = {
    Enabled = true,
    Icon = 132310,
  },
  UpdatePeriod = 5,
}

local defaultSettings = {
  Enabled = false,
  Parent = "SpecClassPriority",
  ActivePoints = 1,
  Width = 21,
  Height = 21,
  Points = {
    {
      Point = "RIGHT",
      RelativeFrame = "SpecClassPriority",
      RelativePoint = "LEFT",
      OffsetX = 0,
      OffsetY = 0,
    },
  },
}

local Icons = { --one of the two (or both) must be enabled, otherwise u won't see an icon
  "Combat",
  "OutOfCombat",
}

local generalOptions = function(location)
  local t = {}
  for i = 1, #Icons do
    t[Icons[i]] = {
      type = "group",
      name = L[Icons[i]],
      inline = true,
      order = 4,
      get = function(option)
        return Data.GetOption(location[Icons[i]], option)
      end,
      set = function(option, ...)
        return Data.SetOption(location[Icons[i]], option, ...)
      end,
      args = {
        Enabled = {
          type = "toggle",
          name = VIDEO_OPTIONS_ENABLED,
          order = 1,
        },
        Icon = {
          type = "execute",
          name = L.Icon,
          image = function()
            return location[Icons[i]].Icon
          end,
          func = function(option)
            local locationn = location[Icons[i]]
            local optiontable = {} --hold a copy of the option table for the OnOkayButtonPressed otherweise the table will be empty
            Mixin(optiontable, option)
            LibSpellIconSelector:Show(locationn, function(spelldata)
              Data.SetOption(locationn, optiontable, spelldata.icon)
              BattleGroundEnemies:NotifyChange()
            end)
          end,
          disabled = function()
            return not location[Icons[i]].Enabled
          end,
          width = "half",
          order = 2,
        },
      },
    }
  end
  t.UpdatePeriod = {
    type = "range",
    name = L.UpdatePeriod,
    desc = L.UpdatePeriod_Desc,
    min = 1.0,
    max = 30,
    step = 0.05,
    order = 3,
    -- Visually clamp old DB values < 1.0 up to the new minimum, without
    -- migrating the saved value. If the user moves the slider, the new
    -- (>= 1.0) value is written back via the standard set path.
    get = function(option)
      local v = Data.GetOption(location, option)
      if type(v) ~= "number" or v < 1.0 then
        return 1.0
      end
      return v
    end,
    set = function(option, value)
      return Data.SetOption(location, option, value)
    end,
  }
  return t
end

local combatIndicator = BattleGroundEnemies:NewButtonModule({
  moduleName = "CombatIndicator",
  localizedModuleName = L.CombatIndicator,
  defaultSettings = defaultSettings,
  generalDefaults = generalDefaults,
  events = { "OnTestmodeEnabled", "OnTestmodeDisabled", "OnTestmodeTick", "UnitIdUpdate" },
  generalOptions = generalOptions,
  enabledInThisExpansion = true,
  attachSettingsToButton = false,
})

local function getState(inCombat)
  if inCombat == nil then
    return 0
  elseif inCombat then
    return 1
  else
    return 2
  end
end

-- Shared ticker: single timer updates all active buttons instead of one ticker per button.
local sharedTicker = nil
-- Last seen UpdatePeriod from a button's config. Cached so StartCombatIndicatorTicker()
-- (called from BattleGroundEnemies:Enable()) can resume the ticker even when no
-- per-button ApplyAllSettings has fired yet.
local lastKnownPeriod = 5

local function UpdateAllCombatIndicators()
  if not BattleGroundEnemies.enabled then
    return
  end
  local containers = { BattleGroundEnemies.Enemies, BattleGroundEnemies.Allies }
  for c = 1, #containers do
    local container = containers[c]
    if container and container.Players then
      for _, playerButton in pairs(container.Players) do
        local ci = playerButton.CombatIndicator
        if ci and ci.Enabled and ci.config and not ci.testmodeEnabled then
          ci:Update()
        end
      end
    end
  end
end

local function StartSharedTicker(updatePeriod)
  if sharedTicker then
    sharedTicker:Cancel()
  end
  -- Defensive floor: even if a saved profile has a stale value below 1.0
  -- (older mins were 0.5, then 0.01), enforce 1.0 as the actual ticker
  -- rate so the new performance floor holds for everyone.
  if type(updatePeriod) ~= "number" or updatePeriod < 1.0 then
    updatePeriod = 1.0
  end
  lastKnownPeriod = updatePeriod
  sharedTicker = CTimerNewTicker(updatePeriod, UpdateAllCombatIndicators)
end

-- Explicit start/stop for BattleGroundEnemies:Enable()/Disable(). Disable() must
-- be able to fully stop the ticker so it doesn't keep firing while the user is
-- outside PvP. Enable() must be able to resume it without waiting for the
-- per-button ApplyAllSettings chain to eventually trigger StartSharedTicker.
function BattleGroundEnemies:StartCombatIndicatorTicker()
  StartSharedTicker(lastKnownPeriod)
end

function BattleGroundEnemies:StopCombatIndicatorTicker()
  if sharedTicker then
    sharedTicker:Cancel()
    sharedTicker = nil
  end
end

function combatIndicator:AttachToPlayerButton(playerButton)
  playerButton.CombatIndicator = CreateFrame("Frame", nil, playerButton)
  playerButton.CombatIndicator.currentState = nil

  for i = 1, #Icons do
    local type = Icons[i]

    local iconFrame = CreateFrame("Frame", nil, playerButton.CombatIndicator)
    iconFrame:SetAllPoints()
    iconFrame:Hide()

    iconFrame.type = type
    iconFrame.texture = iconFrame:CreateTexture(nil, "BACKGROUND")
    iconFrame.texture:SetAllPoints()
    --RaiseFrameLevel(frame)
    iconFrame:SetFrameLevel(playerButton:GetFrameLevel() + 1)

    playerButton.CombatIndicator[type] = iconFrame
  end

  function playerButton.CombatIndicator:ShowIconForState(newState)
    local showCombat = false
    local showOutOfCombat = false
    if newState ~= 0 then
      if newState == 1 then
        if self.config.Combat.Enabled then
          showCombat = true
        end
      else
        if self.config.OutOfCombat.Enabled then
          showOutOfCombat = true
        end
      end
    end

    self.Combat:SetShown(showCombat)
    self.OutOfCombat:SetShown(showOutOfCombat)

    self.currentState = newState
  end

  function playerButton.CombatIndicator:Update(forceState, applyConfig)
    local inCombat
    local newState

    --set showCombat and showOutOfCombat to false (this takes effect when the player doesnt have a unitID)

    if forceState ~= nil then
      newState = forceState
    else
      local unitID = playerButton:GetUnitID()
      if unitID then
        inCombat = UnitAffectingCombat(unitID)
      end
      newState = getState(inCombat)
    end

    if applyConfig or self.currentState ~= newState then
      self:ShowIconForState(newState)
    end
  end

  function playerButton.CombatIndicator:CallFuncOnAllIconFrames(func)
    for i = 1, #Icons do
      local type = Icons[i]
      local iconFrame = self[type]
      func(iconFrame)
    end
  end

  function playerButton.CombatIndicator:Disable()
    -- Nothing per-button to clean up; shared ticker handles polling.
  end

  function playerButton.CombatIndicator:OnTestmodeEnabled()
    self.testmodeEnabled = true
  end

  function playerButton.CombatIndicator:OnTestmodeDisabled()
    self.testmodeEnabled = false
    self:Update(0)
  end

  function playerButton.CombatIndicator:OnTestmodeTick()
    if not self.testmodeEnabled then
      self.testmodeEnabled = true
    end
    local newState = math.random(1, 2)
    self:Update(newState)
  end

  function playerButton.CombatIndicator:ApplyAllSettings()
    if not self.config then
      return
    end
    self:CallFuncOnAllIconFrames(function(iconFrame)
      iconFrame.texture:SetTexture(self.config[iconFrame.type].Icon)
    end)

    -- Re-apply the icon textures/config, but DON'T re-derive combat state in test
    -- mode: there's no live unit, so Update(nil,...) would read UnitAffectingCombat
    -- (nil for fake players) and blank the simulated combat icon on every unrelated
    -- settings change. Pass the current simulated state instead so it's preserved.
    if BattleGroundEnemies:IsTestmodeActive() then
      self:Update(self.currentState, true)
    else
      self:Update(nil, true)
    end

    -- Ensure shared ticker is running with the configured period
    if self.config.UpdatePeriod then
      StartSharedTicker(self.config.UpdatePeriod)
    end
  end

  function playerButton.CombatIndicator:UnitIdUpdate()
    self:Update()
  end

  return playerButton.CombatIndicator
end
