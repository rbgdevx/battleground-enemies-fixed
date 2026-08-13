---@class Data
local Data = select(2, ...)
---@class BattleGroundEnemies
local BattleGroundEnemies = BattleGroundEnemies
local L = Data.L
local CreateFrame = CreateFrame
local GetSpellTexture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
local GetClassAtlas = GetClassAtlas

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
  -- Real CC is rendered by the secure AuraContainer below. This ordinary
  -- cooldown remains for fake test-mode CC.

  frame:SetScript("OnSizeChanged", function(self, width, height)
    self:CropImage()
  end)

  frame:Hide()

  function frame:EnsureLiveCCContainer()
    if self.LiveCCContainer or (playerButton.PlayerDetails and playerButton.PlayerDetails.isFakePlayer) then
      return
    end
    -- Blizzard_AuraContainer is a game-loaded 12.1 foundation whose public
    -- templates are explicitly exposed for external addons. If those globals
    -- do not exist, keep the addon loadable and omit only live CC display.
    if not AuraContainerSortMethod or not AuraContainerSortDirection then
      return
    end

    local container = CreateFrame("AuraContainer", nil, self, "CustomAuraContainerTemplate")
    container:SetAllPoints()
    container:SetEnabled(false)
    container:SetUnit("none")

    local width, height = self:GetSize()
    local cooldownSettings = self.config.Cooldown
    container:AddAuraSlot("CC", "HARMFUL|CROWD_CONTROL", {
      sortMethod = AuraContainerSortMethod.AuraInstanceIDOnly,
      sortDirection = AuraContainerSortDirection.Normal,
      initializeFrame = function(auraButton)
        auraButton:SetAllPoints()
        auraButton:SetMouseClickEnabled(false)
        auraButton:SetMouseMotionEnabled(false)

        local icon = auraButton:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        if width > 0 and height > 0 then
          BattleGroundEnemies.CropImage(icon, width, height)
        end
        auraButton:SetIcon(icon)

        -- This cooldown belongs exclusively to the restricted aura button.
        -- Do not add it to AllCooldowns or touch it after this initializer.
        local cooldown = CreateFrame("Cooldown", nil, auraButton)
        cooldown:SetAllPoints()
        cooldown:SetSwipeTexture("Interface/Buttons/WHITE8X8")
        if cooldown.SetUseAuraDisplayTime then
          cooldown:SetUseAuraDisplayTime(true)
        end
        BattleGroundEnemies.AttachCooldownSettings(cooldown)
        cooldown:ApplyCooldownSettings(cooldownSettings, true, { 0, 0, 0, 0.5 })
        auraButton:SetDurationCooldown(cooldown)
      end,
    })

    self.LiveCCContainer = container
  end

  function frame:IsCompoundLiveCCUnit(unitID)
    return playerButton.PlayerIsEnemy
      and type(unitID) == "string"
      and unitID ~= "target"
      and unitID ~= "focus"
      and unitID ~= "mouseover"
      and unitID ~= "softenemy"
      and not unitID:match("^arena%d+$")
      and not unitID:match("^nameplate%d+$")
  end

  function frame:SetLiveCCUnit(unitID, forceRefresh)
    local container = self.LiveCCContainer
    if not container then
      return
    end

    local isFakePlayer = playerButton.PlayerDetails and playerButton.PlayerDetails.isFakePlayer
    local shouldEnable = self.Enabled
      and self.config
      and self.config.showHighestPriority
      and not isFakePlayer
      and not BattleGroundEnemies.betweenRounds
      and type(unitID) == "string"
      and unitID ~= ""
    local nextUnit = shouldEnable and unitID or "none"

    if nextUnit == "none" then
      self.LiveCCVerifiedUnit = nil
    end

    if self.LiveCCUnit ~= nextUnit or self.LiveCCEnabled ~= shouldEnable then
      -- Clear the previous slot before changing tokens so a recycled row never
      -- flashes its former player's aura while the new unit is parsed.
      container:SetEnabled(false)
      container:SetUnit(nextUnit)
      self.LiveCCUnit = nextUnit
      self.LiveCCEnabled = shouldEnable
      if shouldEnable then
        container:SetEnabled(true)
      end
    elseif shouldEnable and forceRefresh then
      -- Unit-token text can stay constant while its arena/target occupant
      -- changes. Force the secure container to re-read that token in place.
      container:UpdateAllAuras()
    end
  end

  -- Revalidate the elected token against this row's exact canonical name
  -- before allowing the secure container to read it.
  function frame:SyncLiveCCUnit(unitID, forceRefresh)
    local isFakePlayer = playerButton.PlayerDetails and playerButton.PlayerDetails.isFakePlayer
    if
      not self.LiveCCContainer
      or not self.Enabled
      or not self.config
      or not self.config.showHighestPriority
      or isFakePlayer
      or BattleGroundEnemies.betweenRounds
    then
      self:SetLiveCCUnit(nil)
      return false
    end

    -- Compound target chains can change occupants after this exact-name check
    -- but before Blizzard's AuraContainer reads them on its next OnUpdate.
    -- Never bind live CC to those volatile aliases.
    if self:IsCompoundLiveCCUnit(unitID) then
      self:SetLiveCCUnit(nil)
      return false
    end

    local expectedName = playerButton.PlayerDetails and playerButton.PlayerDetails.PlayerName
    local exactName = BattleGroundEnemies:GetCanonicalUnitName(unitID)
    local expectedNameIsUsable = type(expectedName) == "string"
      and expectedName ~= ""
      and not (issecretvalue and issecretvalue(expectedName))

    if exactName and expectedNameIsUsable then
      if exactName == expectedName then
        self.LiveCCVerifiedUnit = unitID
      else
        self.LiveCCVerifiedUnit = nil
      end
    else
      self.LiveCCVerifiedUnit = nil
    end

    if self.LiveCCVerifiedUnit == unitID then
      self:SetLiveCCUnit(unitID, forceRefresh)
      return true
    end

    self:SetLiveCCUnit(nil)
    return false
  end

  function frame:Disable()
    self:SetLiveCCUnit(nil)
  end

  function frame:MakeSureWeAreOnTop()
    if true then
      return
    end
    -- intentionally unreachable: soft-disabled by the if-true-then-return above
    -- luacheck: ignore 511
    local numPoints = self:GetNumPoints()
    local highestLevel = 0
    for i = 1, numPoints do
      local _, relativeTo, _, _, _ = self:GetPoint(i)
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

    -- PriorityAuras is retained for fake test-mode CC. Real aura state is
    -- rendered by LiveCCContainer without being exposed to addon code.
    local priorityAuras = self.PriorityAuras
    for i = 1, #priorityAuras do
      local priorityAura = priorityAuras[i]
      if not highestPrioritySpell or (priorityAura.Priority > highestPrioritySpell.Priority) then
        highestPrioritySpell = priorityAura
      end
    end
    if highestPrioritySpell then
      frame.SpecClassIcon:Hide()
      frame.DisplayedAura = highestPrioritySpell
      frame.PriorityIcon:Show()
      local iconToShow = highestPrioritySpell.icon or GetSpellTexture(118)
      frame.PriorityIcon:SetTexture(iconToShow)
      frame.Cooldown:SetCooldown(
        highestPrioritySpell.expirationTime - highestPrioritySpell.duration,
        highestPrioritySpell.duration
      )
    else
      frame.SpecClassIcon:Show()
      frame.DisplayedAura = false
      frame.PriorityIcon:Hide()
      frame.Cooldown:Clear()
    end
  end

  function frame:Reset()
    self:SetLiveCCUnit(nil)
    self:ResetPriorityData()
  end

  function frame:ResetPriorityData()
    wipe(self.PriorityAuras)
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
    self:EnsureLiveCCContainer()
    if self:IsCompoundLiveCCUnit(playerButton.unitID) then
      self:SetLiveCCUnit(nil)
    else
      self:SyncLiveCCUnit(playerButton.unitID, false)
    end
    self:MakeSureWeAreOnTop()
  end
  return frame
end

function SpecClassPriority:AttachToPlayerButton(playerButton)
  playerButton.SpecClassPriority = attachToPlayerButton(playerButton)
  return playerButton.SpecClassPriority
end
