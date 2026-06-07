---@class Data
local Data = select(2, ...)
---@class BattleGroundEnemies
local BattleGroundEnemies = BattleGroundEnemies
local L = Data.L
local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local GetSpellTexture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
local GetClassAtlas = GetClassAtlas

-- Early-out filter for UNIT_AURA: checks whether the aura update contains
-- any crowd-control-related changes worth rebuilding for. Skips irrelevant
-- aura churn (food buffs, procs, HoTs, etc.) to avoid unnecessary work.
-- Returns true to proceed with UpdateLossOfControl, false to skip.
local function IsInterestedInUpdate(unitID, updateInfo, existingPriorityAuras)
  if not updateInfo or updateInfo.isFullUpdate then
    return true
  end

  -- Added auras: pass the CC filter?
  -- IsAuraFilteredOutByInstanceID may return secret booleans, so pcall it.
  -- On any failure, assume we're interested (safe fallback).
  if updateInfo.addedAuras then
    for _, aura in pairs(updateInfo.addedAuras) do
      local id = aura.auraInstanceID
      if id then
        if not C_UnitAuras.IsAuraFilteredOutByInstanceID then
          return true
        end
        local ok, filtered = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unitID, id, "HARMFUL|CROWD_CONTROL")
        if not ok or not filtered then
          return true
        end
      end
    end
  end

  -- Updated auras: pass the CC filter?
  if updateInfo.updatedAuraInstanceIDs then
    for _, id in pairs(updateInfo.updatedAuraInstanceIDs) do
      if id then
        if not C_UnitAuras.IsAuraFilteredOutByInstanceID then
          return true
        end
        local ok, filtered = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unitID, id, "HARMFUL|CROWD_CONTROL")
        if not ok or not filtered then
          return true
        end
      end
    end
  end

  -- Removed auras: was any of them a CC we were tracking?
  -- We CANNOT match by ID here: auraInstanceID is SecretWhenUnitAuraRestricted,
  -- so for enemies in instanced PvP both `entry.auraInstanceID` (stored from a
  -- prior GetUnitAuras) and `id` (from the UNIT_AURA payload) can be secret
  -- values. The old `entry.auraInstanceID == id` compared secret == secret with
  -- no guard, which TAINTS execution — and because UNIT_AURA + CC churn fire
  -- constantly, that taint re-emitted thousands of times per match, accumulated
  -- across a no-reload session, and eventually detonated the score-parse path.
  -- The filter API can't help either (removed auras are already gone).
  --
  -- We don't actually need the exact match: this branch only decides whether to
  -- rebuild the CC display. So if we're tracking any CC and ANYTHING was removed,
  -- conservatively rebuild. The rebuild re-scans live auras via GetUnitAuras and
  -- is idempotent — identical display result, just an occasional extra rescan
  -- (when a non-CC aura drops off a unit we're tracking CC on). No UX change, and
  -- the secret comparison is gone entirely.
  if updateInfo.removedAuraInstanceIDs and next(updateInfo.removedAuraInstanceIDs) ~= nil then
    if #existingPriorityAuras > 0 then
      return true
    end
  end

  return false
end

local generalDefaults = {
  showSpecIfExists = true,
  showHighestPriority = true,
}

local defaultSettings = {
  Enabled = true,
  Parent = "Button",
  Cooldown = {
    ShowNumber = true,
    FontSize = 12,
    FontOutline = "OUTLINE",
    EnableShadow = false,
    DrawSwipe = true,
    ShadowColor = { 0, 0, 0, 1 },
  },
  Width = 36,
  ActivePoints = 1,
  Points = {
    {
      Point = "TOPRIGHT",
      RelativeFrame = "Button",
      RelativePoint = "TOPLEFT",
    },
  },
  UseButtonHeightAsHeight = true,
}

local generalOptions = function(location)
  return {
    showSpecIfExists = {
      type = "toggle",
      name = L.ShowSpecIfExists,
      desc = L.ShowSpecIfExists_Desc,
      width = "full",
      order = 1,
    },
    showHighestPriority = {
      type = "toggle",
      name = L.ShowHighestPriority,
      desc = L.ShowHighestPriority_Desc,
      width = "full",
      order = 2,
    },
  }
end

local options = function(location)
  return {
    CooldownTextSettings = {
      type = "group",
      name = L.Countdowntext,
      inline = true,
      get = function(option)
        return Data.GetOption(location.Cooldown, option)
      end,
      set = function(option, ...)
        return Data.SetOption(location.Cooldown, option, ...)
      end,
      order = 3,
      args = Data.AddCooldownSettings(location.Cooldown),
    },
  }
end

local SpecClassPriority = BattleGroundEnemies:NewButtonModule({
  moduleName = "SpecClassPriority",
  localizedModuleName = L.SpecClassPriority,
  defaultSettings = defaultSettings,
  generalDefaults = generalDefaults,
  options = options,
  generalOptions = generalOptions,
  events = {
    "GotInterrupted",
    "UnitDied",
  },
  enabledInThisExpansion = true,
  flags = {
    SetZeroWidthWhenDisabled = true,
  },
})

local function attachToPlayerButton(playerButton)
  local frame = CreateFrame("frame", nil, playerButton)
  frame.Background = frame:CreateTexture(nil, "BACKGROUND")
  frame.Background:SetAllPoints()
  frame.Background:SetColorTexture(0, 0, 0, 0.8)
  frame.PriorityAuras = {}
  frame.ActiveInterrupt = false
  frame.ShowsSpec = false
  frame.SpecClassIcon = frame:CreateTexture(nil, "BORDER", nil, 2)
  frame.SpecClassIcon:SetAllPoints()
  frame.PriorityIcon = frame:CreateTexture(nil, "BORDER", nil, 3)
  frame.PriorityIcon:SetAllPoints()
  frame.Cooldown = BattleGroundEnemies.MyCreateCooldown(frame)
  -- Aura display timing adjusts the countdown to be appropriate for buff/debuff
  -- durations rather than ability cooldowns (matches Blizzard's arena CC debuff display).
  if frame.Cooldown.SetUseAuraDisplayTime then
    frame.Cooldown:SetUseAuraDisplayTime(true)
  end
  -- No OnCooldownDone handler — matches MiniCC's approach. CC cleanup is
  -- driven by UNIT_AURA events (which fire when the aura is removed) and
  -- the polling ticker as a safety net. OnCooldownDone can fire prematurely
  -- with DurationObjects and race with SetCooldownFromDurationObject.

  frame:HookScript("OnLeave", function(self)
    if GameTooltip:IsOwned(self) then
      GameTooltip:Hide()
    end
  end)

  frame:HookScript("OnEnter", function(self)
    BattleGroundEnemies:ShowTooltip(self, function()
      if frame.DisplayedAura and frame.DisplayedAura.spellId then
        GameTooltip:SetSpellByID(frame.DisplayedAura.spellId)
      elseif not frame.DisplayedAura then
        local playerDetails = playerButton.PlayerDetails
        if not playerDetails.PlayerClass then
          return
        end
        local numClasses = GetNumClasses()
        local localizedClass
        for i = 1, numClasses do -- we could also just save the localized class name it into the button itself, but since its only used for this tooltip no need for that
          local className, classFile, classID = GetClassInfo(i)
          if classFile and classFile == playerDetails.PlayerClass then
            localizedClass = className
          end
        end
        if not localizedClass then
          return
        end

        if playerDetails.PlayerSpecName then
          GameTooltip:SetText(localizedClass .. " " .. playerDetails.PlayerSpecName)
        else
          return GameTooltip:SetText(localizedClass)
        end
      end
    end)
  end)

  frame:SetScript("OnSizeChanged", function(self, width, height)
    self:CropImage()
  end)

  frame:Hide()

  function frame:MakeSureWeAreOnTop()
    if true then
      return
    end
    local numPoints = self:GetNumPoints()
    local highestLevel = 0
    for i = 1, numPoints do
      local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint(i)
      if relativeTo then
        local level = relativeTo:GetFrameLevel()
        if level and level > highestLevel then
          highestLevel = level
        end
      end
    end
    self:SetFrameLevel(highestLevel + 1)
  end

  function frame:Update()
    self:MakeSureWeAreOnTop()
    local highestPrioritySpell
    local currentTime = GetTime()

    -- PriorityAuras are rebuilt from C_UnitAuras.GetUnitAuras each time
    -- UpdateLossOfControl runs, so any entry in the list is currently active.
    local priorityAuras = self.PriorityAuras
    for i = 1, #priorityAuras do
      local priorityAura = priorityAuras[i]
      if not highestPrioritySpell or (priorityAura.Priority > highestPrioritySpell.Priority) then
        highestPrioritySpell = priorityAura
      end
    end
    if frame.ActiveInterrupt then
      if frame.ActiveInterrupt.expirationTime < currentTime then
        frame.ActiveInterrupt = false
      else
        if not highestPrioritySpell or (frame.ActiveInterrupt.Priority > highestPrioritySpell.Priority) then
          highestPrioritySpell = frame.ActiveInterrupt
        end
      end
    end

    if highestPrioritySpell then
      frame.SpecClassIcon:Hide()
      frame.DisplayedAura = highestPrioritySpell
      frame.PriorityIcon:Show()
      local iconToShow = highestPrioritySpell.icon or GetSpellTexture(118)
      frame.PriorityIcon:SetTexture(iconToShow)
      if highestPrioritySpell.durationObject and frame.Cooldown.SetCooldownFromDurationObject then
        frame.Cooldown:SetCooldownFromDurationObject(highestPrioritySpell.durationObject)
      else
        -- Fallback for interrupts which still use expirationTime/duration
        frame.Cooldown:SetCooldown(
          highestPrioritySpell.expirationTime - highestPrioritySpell.duration,
          highestPrioritySpell.duration
        )
      end
    else
      frame.SpecClassIcon:Show()
      frame.DisplayedAura = false
      frame.PriorityIcon:Hide()
      frame.Cooldown:Clear()
    end
  end

  function frame:Reset()
    self:ResetPriorityData()
  end

  function frame:ResetPriorityData()
    self.ActiveInterrupt = false
    wipe(self.PriorityAuras)
    if self._locExpiryTimer then
      self._locExpiryTimer:Cancel()
      self._locExpiryTimer = nil
    end
    self:Update()
  end

  function frame:GotInterrupted(spellId, interruptDuration)
    self.ActiveInterrupt = {
      spellId = spellId,
      icon = GetSpellTexture(spellId),
      expirationTime = GetTime() + interruptDuration,
      duration = interruptDuration,
      Priority = BattleGroundEnemies:GetSpellPriority(spellId) or 4,
    }
    self:Update()
  end

  function frame:UpdateLossOfControl(unitID, updateInfo)
    if not self.config or not self.config.showHighestPriority then
      return
    end
    -- Dead units can't be CC'd — clear immediately so icons don't linger after death.
    if UnitIsDeadOrGhost(unitID) then
      if self._locExpiryTimer then
        self._locExpiryTimer:Cancel()
        self._locExpiryTimer = nil
      end
      wipe(self.PriorityAuras)
      self:Update()
      return
    end

    -- No dead-player guard — MiniCC doesn't have one either. Let C_UnitAuras
    -- try to detect CC on living allies even when the local player is dead.
    -- If it returns empty, PriorityAuras will simply be empty (same as before).

    -- Skip full rebuild if updateInfo tells us nothing CC-related changed.
    -- Critical in BGs: UNIT_AURA fires constantly for food buffs, procs, heals, etc.
    if not IsInterestedInUpdate(unitID, updateInfo, self.PriorityAuras) then
      return
    end

    wipe(self.PriorityAuras)

    -- C_UnitAuras for detection (works for allies and enemies):
    -- 1. GetAuraDuration first (skip aura if no duration object)
    -- 2. IsSpellCrowdControl to verify, with simple issecretvalue(x) or x
    -- NOTE: Do NOT pass sort params — SecretArguments="AllowedWhenUntainted"
    -- means they fail silently from tainted addon code.
    local auras = C_UnitAuras.GetUnitAuras(unitID, "HARMFUL|CROWD_CONTROL")
    for _, aura in ipairs(auras) do
      local durationObj = C_UnitAuras.GetAuraDuration(unitID, aura.auraInstanceID)
      if durationObj then
        local isCC = C_Spell.IsSpellCrowdControl(aura.spellId)
        if issecretvalue(isCC) or isCC then
          self.PriorityAuras[#self.PriorityAuras + 1] = {
            icon = aura.icon,
            Priority = 5,
            durationObject = durationObj,
            auraInstanceID = aura.auraInstanceID,
          }
        end
      end
    end

    -- Cancel any pending expiry timer before possibly starting a new one.
    if self._locExpiryTimer then
      self._locExpiryTimer:Cancel()
      self._locExpiryTimer = nil
    end

    if #self.PriorityAuras > 0 then
      -- Poll every second as a safety net in case UNIT_AURA misses the expiry.
      self._locExpiryTimer = C_Timer.NewTicker(1, function(ticker)
        if UnitIsDeadOrGhost(unitID) then
          ticker:Cancel()
          self._locExpiryTimer = nil
          wipe(self.PriorityAuras)
          self:Update()
          return
        end
        local checkAuras = C_UnitAuras.GetUnitAuras(unitID, "HARMFUL|CROWD_CONTROL")
        if #checkAuras == 0 then
          -- If the local player is a ghost, GetUnitAuras returns empty for living
          -- units due to phase separation — use C_LossOfControl as backup check.
          if UnitIsDeadOrGhost("player") then
            local locCount = C_LossOfControl
                and C_LossOfControl.GetActiveLossOfControlDataCountByUnit
                and C_LossOfControl.GetActiveLossOfControlDataCountByUnit(unitID)
                or 0
            if locCount > 0 then
              return -- still CC'd per LoC, don't clear
            end
          end
          ticker:Cancel()
          self._locExpiryTimer = nil
          wipe(self.PriorityAuras)
          self:Update()
        end
      end)
    end

    self:Update()
  end

  function frame:UnitDied()
    self:ResetPriorityData()
  end

  frame.CropImage = function(self)
    local width = self:GetWidth()
    local height = self:GetHeight()
    if width and height and width > 0 and height > 0 then
      if self.ShowsSpec then
        BattleGroundEnemies.CropImage(self.SpecClassIcon, width, height)
      end
      BattleGroundEnemies.CropImage(self.PriorityIcon, width, height)
    end
  end

  frame.ApplyAllSettings = function(self)
    if not self.config then
      return
    end
    local moduleSettings = self.config
    self:Show()
    local playerDetails = playerButton.PlayerDetails
    if not playerDetails then
      return
    end
    self.ShowsSpec = false

    local specData = playerButton:GetSpecData()
    if specData and self.config.showSpecIfExists then
      self.SpecClassIcon:SetTexture(specData.specIcon)
      self.ShowsSpec = true
    else
      local classIconAtlas = GetClassAtlas and GetClassAtlas(playerDetails.PlayerClass)
      if classIconAtlas then
        self.SpecClassIcon:SetAtlas(classIconAtlas)
      else
        local coords = CLASS_ICON_TCOORDS[playerDetails.PlayerClass]
        if playerDetails.PlayerClass and coords then
          self.SpecClassIcon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
          self.SpecClassIcon:SetTexCoord(unpack(coords))
        else
          self.SpecClassIcon:SetTexture(nil)
        end
      end
    end
    self:CropImage()
    self.Cooldown:ApplyCooldownSettings(moduleSettings.Cooldown, true, { 0, 0, 0, 0.5 })
    if not moduleSettings.showHighestPriority then
      self:ResetPriorityData()
    end
    self:MakeSureWeAreOnTop()
  end
  return frame
end

function SpecClassPriority:AttachToPlayerButton(playerButton)
  playerButton.SpecClassPriority = attachToPlayerButton(playerButton)
  return playerButton.SpecClassPriority
end
