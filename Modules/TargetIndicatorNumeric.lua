---@class Data
local Data = select(2, ...)
---@class BattleGroundEnemies
local BattleGroundEnemies = BattleGroundEnemies
local L = Data.L

local generalDefaults = {
  HideWhenZero = true,
}

local defaultSettings = {
  Enabled = false,
  Parent = "healthBar",
  ActivePoints = 1,
  Points = {
    {
      Point = "CENTER",
      RelativeFrame = "healthBar",
      RelativePoint = "CENTER",
      OffsetX = 0,
      OffsetY = 0,
    },
  },
  Text = {
    FontSize = 13,
    JustifyH = "CENTER",
    JustifyV = "MIDDLE",
  },
}

local generalOptions = function(location, playerType)
  return {
    HideWhenZero = {
      type = "toggle",
      name = L.HideWhenZero,
      desc = L.TargetIndicatorNumeric_HideWhenZero_Desc,
      width = "normal",
      order = 1,
    },
  }
end

local options = function(location, playerType)
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

local targetIndicatorNumeric = BattleGroundEnemies:NewButtonModule({
  moduleName = "TargetIndicatorNumeric",
  localizedModuleName = L.TargetIndicatorNumeric,
  defaultSettings = defaultSettings,
  generalDefaults = generalDefaults,
  options = options,
  generalOptions = generalOptions,
  events = { "UpdateTargetIndicators", "OnTestmodeEnabled", "OnTestmodeDisabled", "OnTestmodeTick" },
  enabledInThisExpansion = true,
  attachSettingsToButton = true,
})

function targetIndicatorNumeric:AttachToPlayerButton(playerButton)
  playerButton.TargetIndicatorNumeric = BattleGroundEnemies.MyCreateFontString(playerButton)

  function playerButton.TargetIndicatorNumeric:UpdateTargetIndicators()
    -- Test mode drives the count via OnTestmodeTick (fake players have no real
    -- TargetedByEnemy entries); don't let a live update reset the simulated value
    -- (ApplyAllSettings calls this, so a settings change would otherwise blank it).
    if BattleGroundEnemies:IsTestmodeActive() then
      return
    end

    local enemyTargets = 0

    if playerButton.UnitIDs and playerButton.UnitIDs.TargetedByEnemy then
      -- Render-time validation: prune stale entries where the source button's
      -- .Target no longer points back to us. This catches phantom counts
      -- caused by token churn leaving orphaned TargetedByEnemy entries.
      local stale
      for sourceButton in pairs(playerButton.UnitIDs.TargetedByEnemy) do
        if sourceButton.Target ~= playerButton then
          stale = stale or {}
          stale[#stale + 1] = sourceButton
        else
          enemyTargets = enemyTargets + 1
        end
      end
      if stale then
        for _, key in ipairs(stale) do
          playerButton.UnitIDs.TargetedByEnemy[key] = nil
        end
      end
    end

    if enemyTargets == 0 and self.config.HideWhenZero then
      self:SetText("")
    else
      self:SetText(enemyTargets)
    end
  end

  playerButton.TargetIndicatorNumeric.ApplyAllSettings = function(self)
    if not self.config then
      return
    end
    self:ApplyFontStringSettings(self.config.Text)
    self:UpdateTargetIndicators()
  end

  -- Test mode: simulate a random number of enemies targeting this player so the
  -- numeric indicator is visible/tunable outside a live BG (honors HideWhenZero).
  function playerButton.TargetIndicatorNumeric:OnTestmodeEnabled()
    self.testmodeEnabled = true
  end

  function playerButton.TargetIndicatorNumeric:OnTestmodeDisabled()
    self.testmodeEnabled = false
    self:Reset()
  end

  function playerButton.TargetIndicatorNumeric:OnTestmodeTick()
    local enemyTargets = math.random(0, 5)
    if enemyTargets == 0 and self.config and self.config.HideWhenZero then
      self:SetText("")
    else
      self:SetText(enemyTargets)
    end
  end

  playerButton.TargetIndicatorNumeric.Reset = function(self)
    --dont SetWidth before Hide() otherwise it won't work as aimed
    if not self:GetFont() then
      return
    end
    self:SetText(0) --we do that because the level is anchored right to this and the name is anhored right to the level
  end
  return playerButton.TargetIndicatorNumeric
end
