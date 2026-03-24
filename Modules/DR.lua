---@type string
local AddonName = ...
---@class Data
local Data = select(2, ...)
---@class BattleGroundEnemies
local BattleGroundEnemies = BattleGroundEnemies
local L = Data.L

local CreateFrame = CreateFrame
local BackdropTemplateMixin = BackdropTemplateMixin
local GameTooltip = GameTooltip
local GetTime = GetTime

-- DR-specific debug prints (always on for now)
local function DRPrint(...)
  print("|cff00ccff[BGE-DR]|r", ...)
end

-- C_SpellDiminish availability (added in Midnight)
local hasSpellDiminishAPI = C_SpellDiminish and C_SpellDiminish.GetSpellDiminishCategoryInfo
local hasSpellDiminishEnums = Enum and Enum.SpellDiminishCategory

-- Map Enum.SpellDiminishCategory values to stable string keys for saved variables / filtering
local categoryEnumToKey = {}
local categoryKeyToEnum = {}
local categoryKeyToInfo = {} -- populated at load time

-- Hardcoded fallback data in case API calls fail at load time
local fallbackCategoryData = {
  { key = "root", name = "Root", enum = 0 },
  { key = "taunt", name = "Taunt", enum = 1 },
  { key = "stun", name = "Stun", enum = 2 },
  { key = "knockback", name = "AoE Knockback", enum = 3 },
  { key = "incap", name = "Incapacitate", enum = 4 },
  { key = "disorient", name = "Disorient", enum = 5 },
  { key = "silence", name = "Silence", enum = 6 },
  { key = "disarm", name = "Disarm", enum = 7 },
}

if hasSpellDiminishEnums then
  local enumTable = {
    { enum = Enum.SpellDiminishCategory.Root, key = "root" },
    { enum = Enum.SpellDiminishCategory.Taunt, key = "taunt" },
    { enum = Enum.SpellDiminishCategory.Stun, key = "stun" },
    { enum = Enum.SpellDiminishCategory.AoEKnockback, key = "knockback" },
    { enum = Enum.SpellDiminishCategory.Incapacitate, key = "incap" },
    { enum = Enum.SpellDiminishCategory.Disorient, key = "disorient" },
    { enum = Enum.SpellDiminishCategory.Silence, key = "silence" },
    { enum = Enum.SpellDiminishCategory.Disarm, key = "disarm" },
  }
  for _, entry in ipairs(enumTable) do
    categoryEnumToKey[entry.enum] = entry.key
    categoryKeyToEnum[entry.key] = entry.enum
    -- Get localized name and icon from Blizzard API
    local info = hasSpellDiminishAPI and C_SpellDiminish.GetSpellDiminishCategoryInfo(entry.enum)
    if info then
      categoryKeyToInfo[entry.key] = {
        name = info.name or entry.key,
        icon = info.icon,
        category = entry.enum,
      }
    end
  end
end

-- Fill in any missing categories with fallback data
for _, fb in ipairs(fallbackCategoryData) do
  if not categoryKeyToInfo[fb.key] then
    categoryEnumToKey[fb.enum] = fb.key
    categoryKeyToEnum[fb.key] = fb.enum
    categoryKeyToInfo[fb.key] = {
      name = fb.name,
      icon = nil, -- no icon available without API
      category = fb.enum,
    }
  end
end

-- LoC API fallback: map locType strings to our DR category keys
-- Note: locType is the CC mechanic type, NOT the DR category — these are separate systems.
-- STUN locType = "breaks on damage" (Sap, Gouge) = Incap DR (not Stun DR)
-- STUN_MECHANIC locType = hard stun (Kidney Shot, etc.) = Stun DR
-- FEAR locType = horror (Mortal Coil) = Incap DR (not Disorient DR)
-- FEAR_MECHANIC locType = actual fear = Disorient DR
-- PACIFYSILENCE locType = Cyclone (cannot attack or cast) = Disorient DR
-- CYCLONE is NOT a valid locType — Cyclone returns PACIFYSILENCE
local locTypeToDRCategory = {
  STUN = "incap",             -- breaks on damage (Sap, Gouge)
  STUN_MECHANIC = "stun",     -- hard stun (Kidney Shot, Cheap Shot)
  FEAR = "incap",             -- horror (Mortal Coil)
  FEAR_MECHANIC = "disorient", -- actual fear (Warlock Fear, Psychic Scream)
  CHARM = "disorient",
  PACIFYSILENCE = "disorient", -- Cyclone, Hex
  CONFUSE = "incap",           -- best-guess: Polymorph=incap, Blind=disorient (ambiguous)
  ROOT = "root",
  SILENCE = "silence",
  DISARM = "disarm",
}

-- Filter list values for the settings multiselect: key = category key string, value = localized name
local filterListValues = {}
for key, info in pairs(categoryKeyToInfo) do
  filterListValues[key] = info.name
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local generalDefaults = {
  Filtering_Enabled = false,
  Filtering_Filterlist = {},
  DisplayType = "Frame",
}

local defaultSettings = {
  Enabled = true,
  Parent = "Button",
  ActivePoints = 1,
  Points = {
    {
      Point = "RIGHT",
      RelativeFrame = "SpecClassPriority",
      RelativePoint = "LEFT",
      OffsetX = 0,
    },
  },
  IconSize = 20,
  Cooldown = {
    FontSize = 13,
    FontOutline = "OUTLINE",
    ShowDRCount = true,
  },
  Container = {
    UseButtonHeightAsSize = true,
    IconSize = 15,
    IconsPerRow = 10,
    HorizontalGrowDirection = "leftwards",
    HorizontalSpacing = 2,
    VerticalGrowdirection = "downwards",
    VerticalSpacing = 1,
  },
}

local generalOptions = function(location)
  return {
    DisplayType = {
      type = "select",
      name = L.DisplayType,
      desc = L.DrTracking_DisplayType_Desc,
      values = Data.DisplayType,
      order = 1,
    },
    FilteringSettings = {
      type = "group",
      name = FILTER,
      order = 7,
      args = {
        Filtering_Enabled = {
          type = "toggle",
          name = L.Filtering_Enabled,
          desc = L.DrTrackingFiltering_Enabled_Desc,
          width = "normal",
          order = 1,
        },
        Filtering_Filterlist = {
          type = "multiselect",
          name = "",
          desc = L.DrTrackingFiltering_Filterlist_Desc,
          disabled = function()
            return not location.Filtering_Enabled
          end,
          get = function(option, key)
            return location.Filtering_Filterlist[key]
          end,
          set = function(option, key, state)
            location.Filtering_Filterlist[key] = state or nil
          end,
          values = filterListValues,
          order = 2,
        },
      },
    },
  }
end

local options = function(location)
  return {
    ContainerSettings = {
      type = "group",
      name = L.ContainerSettings,
      order = 4,
      get = function(option)
        return Data.GetOption(location.Container, option)
      end,
      set = function(option, ...)
        return Data.SetOption(location.Container, option, ...)
      end,
      args = Data.AddContainerSettings(location.Container),
    },
    CooldownTextSettings = {
      type = "group",
      name = L.Countdowntext,
      get = function(option)
        return Data.GetOption(location.Cooldown, option)
      end,
      set = function(option, ...)
        return Data.SetOption(location.Cooldown, option, ...)
      end,
      order = 5,
      args = (function()
        local args = Data.AddCooldownSettings(location.Cooldown)
        -- Spacer before DR Count toggle
        args.ShowDRCountSpacer = {
          type = "description",
          name = " ",
          order = 4,
          width = "full",
        }
        args.ShowDRCount = {
          type = "toggle",
          name = L.DrTracking_ShowDRCount,
          desc = L.DrTracking_ShowDRCount_Desc,
          width = "full",
          order = 5,
        }
        return args
      end)(),
    },
  }
end

---------------------------------------------------------------------------
-- DR state colors (2-state: Midnight rules — 2 applications then immune)
---------------------------------------------------------------------------

local dRstates = {
  [1] = { 0, 1, 0, 1 }, -- green  (1st CC ended — next will be half duration)
  [2] = { 1, 0, 0, 1 }, -- red    (immune)
}

local function updateStatusCounter(drFrame, status)
  if drFrame.StatusText and drFrame.StatusBG then
    local showCount = drFrame.Container.config.Cooldown.ShowDRCount
    if showCount then
      drFrame.StatusText:SetText(status .. "/2")
      local w = drFrame.StatusText:GetStringWidth() + 2
      local h = drFrame.StatusText:GetStringHeight() + 1
      drFrame.StatusBG:SetSize(w, h)
      drFrame.StatusBG:Show()
      drFrame.StatusText:Show()
    else
      drFrame.StatusBG:Hide()
      drFrame.StatusText:Hide()
    end
  end
end

local function drFrameUpdateStatusBorder(drFrame)
  local status = drFrame.input and drFrame.input.status or 1
  status = math.min(status, 2)
  local color = dRstates[status]
  if color then
    drFrame:SetBackdropBorderColor(unpack(color))
  end
  updateStatusCounter(drFrame, status)
end

local function drFrameUpdateStatusText(drFrame)
  local status = drFrame.input and drFrame.input.status or 1
  status = math.min(status, 2)
  local color = dRstates[status]
  if color then
    drFrame.Cooldown.Text:SetTextColor(unpack(color))
  end
  updateStatusCounter(drFrame, status)
end

---------------------------------------------------------------------------
-- Module registration
---------------------------------------------------------------------------

local flags = {
  HasDynamicSize = true,
}

local dRTracking = BattleGroundEnemies:NewButtonModule({
  moduleName = "DRTracking",
  localizedModuleName = L.DRTracking,
  flags = flags,
  defaultSettings = defaultSettings,
  generalDefaults = generalDefaults,
  options = options,
  generalOptions = generalOptions,
  events = {
    "DiminishStateUpdated",
    "UnitDied",
    "PeriodicUpdate",
    "OnTestmodeEnabled",
    "OnTestmodeDisabled",
    "OnTestmodeTick",
  },
  enabledInThisExpansion = true,
  attachSettingsToButton = false,
})

---------------------------------------------------------------------------
-- Frame creation & setup (ported from OG DR.lua, adapted for C_SpellDiminish)
---------------------------------------------------------------------------

local function createNewDrFrame(playerButton, container)
  local drFrame = CreateFrame("Frame", nil, container, BackdropTemplateMixin and "BackdropTemplate")
  drFrame.Cooldown = BattleGroundEnemies.MyCreateCooldown(drFrame)

  drFrame.Cooldown:SetScript("OnCooldownDone", function()
    drFrame:Remove()
  end)

  drFrame:HookScript("OnEnter", function(self)
    BattleGroundEnemies:ShowTooltip(self, function()
      local catKey = self.input and self.input.drCat
      local info = catKey and categoryKeyToInfo[catKey]
      if info then
        GameTooltip:AddLine(info.name, 1, 1, 1)
        GameTooltip:Show()
      end
    end)
  end)

  drFrame:HookScript("OnLeave", function(self)
    if GameTooltip:IsOwned(self) then
      GameTooltip:Hide()
    end
  end)

  drFrame.Container = container

  drFrame.ApplyChildFrameSettings = function(self)
    self.Cooldown:ApplyCooldownSettings(container.config.Cooldown, true, { 0, 0, 0, 0.5 })
    self:SetDisplayType()
    -- Update status counter visibility based on setting
    if self.input and self.input.status then
      updateStatusCounter(self, self.input.status)
    end
  end

  drFrame.SetDisplayType = function(self)
    if container.config.DisplayType == "Frame" then
      self.SetStatus = drFrameUpdateStatusBorder
    else
      self.SetStatus = drFrameUpdateStatusText
    end

    self.Cooldown.Text:SetTextColor(1, 1, 1, 1)
    self:SetBackdropBorderColor(0, 0, 0, 0)
    if self.input and self.input.status and self.input.status > 0 then
      self:SetStatus()
    end
  end

  drFrame:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 1,
  })

  drFrame:SetBackdropColor(0, 0, 0, 0)
  drFrame:SetBackdropBorderColor(0, 0, 0, 0)

  drFrame.Icon = drFrame:CreateTexture(nil, "BORDER", nil, -1)
  drFrame.Icon:SetAllPoints()

  -- Status counter text (e.g. "1/2", "2/2") at the top of the icon
  drFrame.StatusBG = CreateFrame("Frame", nil, drFrame, BackdropTemplateMixin and "BackdropTemplate")
  drFrame.StatusBG:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
  drFrame.StatusBG:SetBackdropColor(0, 0, 0, 0.8)
  drFrame.StatusBG:SetFrameLevel(drFrame:GetFrameLevel() + 2)
  drFrame.StatusBG:SetPoint("TOP", drFrame, "TOP", 0, 6)

  drFrame.StatusText = drFrame.StatusBG:CreateFontString(nil, "OVERLAY")
  drFrame.StatusText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
  drFrame.StatusText:SetPoint("CENTER", drFrame.StatusBG, "CENTER", 0, 0)

  drFrame:ApplyChildFrameSettings()
  drFrame:Hide()

  return drFrame
end

local function setupDrFrame(container, drFrame, drDetails)
  drFrame:SetStatus()

  -- Icon: prefer Blizzard's category icon, fall back to LoC-provided icon
  local icon
  local catInfo = categoryKeyToInfo[drDetails.drCat]
  if catInfo and catInfo.icon then
    icon = catInfo.icon
  elseif drDetails.iconTexture then
    icon = drDetails.iconTexture
  end
  drFrame.Icon:SetTexture(icon)

  -- Cooldown: startTime/duration may be secret values from arena opponents.
  -- SetCooldown accepts secrets via InsecureSecretArguments.
  if drDetails.startTime and drDetails.duration then
    if issecretvalue and (issecretvalue(drDetails.duration) or issecretvalue(drDetails.startTime)) then
      drFrame.Cooldown:SetCooldown(drDetails.startTime, drDetails.duration)
    elseif drDetails.duration > 0 then
      drFrame.Cooldown:SetCooldown(drDetails.startTime, drDetails.duration)
    end
  end
end

---------------------------------------------------------------------------
-- LoC polling fallback (used only if C_SpellDiminish doesn't fire for BG units)
---------------------------------------------------------------------------

local function pollLoCForUnit(container, unitToken)
  if not C_LossOfControl or not C_LossOfControl.GetActiveLossOfControlDataByUnit then
    return
  end

  -- Track which categories are active THIS poll
  container.locActiveCategories = container.locActiveCategories or {}
  local seenThisPoll = {}
  local index = 1

  while true do
    local ok, data = pcall(C_LossOfControl.GetActiveLossOfControlDataByUnit, unitToken, index)
    if not ok then
      break
    end
    if not data then
      break
    end

    -- Skip generic entries with no spell info
    -- 12.0: spellID can be a secret value in PvP — truthiness works, comparison does not
    if data.spellID then
      local catKey = data.locType and not issecretvalue(data.locType) and locTypeToDRCategory[data.locType]
      if catKey and not seenThisPoll[catKey] then
        seenThisPoll[catKey] = true

        -- Check filtering
        local config = container.config
        if config and (not config.Filtering_Enabled or config.Filtering_Filterlist[catKey]) then
          local input = container:FindInputByAttribute("drCat", catKey)

          if not container.locActiveCategories[catKey] then
            -- Category just appeared (was not active last poll)
            if not input then
              -- First CC in this category
              -- DRPrint("DR 1/2:", unitToken, catKey, "spellID=" .. data.spellID)
              container:NewInput({
                drCat = catKey,
                status = 1,
                startTime = GetTime(),
                duration = 16,
                iconTexture = data.iconTexture,
              })
              container:Display()
            else
              -- Re-CC: same category, already tracked → increment status
              if input.status < 2 then
                input.status = input.status + 1
                input.startTime = GetTime()
                input.duration = 16
                -- DRPrint("DR " .. input.status .. "/2:", unitToken, catKey, "spellID=" .. data.spellID)
                container:Display()
              end
            end
          end
          -- else: category was already active last poll, CC is still ongoing — do nothing
        end
      end
    end
    index = index + 1
  end

  -- Mark categories that ended (were active last poll, not seen this poll)
  for catKey, _ in pairs(container.locActiveCategories) do
    if not seenThisPoll[catKey] then
      -- DRPrint("CC ENDED:", unitToken, catKey)
    end
  end

  -- Update active categories for next poll
  container.locActiveCategories = seenThisPoll
end

---------------------------------------------------------------------------
-- AttachToPlayerButton
---------------------------------------------------------------------------

function dRTracking:AttachToPlayerButton(playerButton)
  local container = BattleGroundEnemies:NewContainer(playerButton, createNewDrFrame, setupDrFrame)

  -- Whether C_SpellDiminish events have ever fired for this button (to decide fallback)
  container.diminishEventReceived = false
  container.locFallbackActive = false
  container.locPollElapsed = 0

  ---------------------------------------------------------------------------
  -- Primary: C_SpellDiminish event handler
  -- Dispatched from Main.lua when UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED fires
  ---------------------------------------------------------------------------
  function container:DiminishStateUpdated(_, stateInfo)
    if not self.config then
      return
    end

    -- 12.0.0: stateInfo fields are secret values for arena opponents (SecretPayloads = true).
    -- Addon code is tainted, so SecretArguments APIs reject secret values from us.
    -- Bail out when category is secret — LoC polling fallback handles arena DR instead.
    local category = stateInfo.category
    if issecretvalue and issecretvalue(category) then
      return
    end

    local catKey = categoryEnumToKey[category]
    if not catKey then
      return
    end

    self.diminishEventReceived = true

    -- Category filtering
    if self.config.Filtering_Enabled and not self.config.Filtering_Filterlist[catKey] then
      return
    end

    local input, inputIdx = self:FindInputByAttribute("drCat", catKey)

    -- Resolve boolean fields: may be secret for arena opponents.
    -- When secret, default isImmune=false, showCountdown=true (show the DR timer).
    local isImmune = stateInfo.isImmune
    local showCountdown = stateInfo.showCountdown
    if issecretvalue then
      if issecretvalue(isImmune) then isImmune = false end
      if issecretvalue(showCountdown) then showCountdown = true end
    end

    if isImmune then
      -- Target is immune
      if not input then
        input = self:NewInput({ drCat = catKey })
      end
      input.status = 2
      input.startTime = stateInfo.startTime
      input.duration = stateInfo.duration
    elseif showCountdown then
      -- DR active but not immune (half duration next)
      if not input then
        input = self:NewInput({ drCat = catKey })
      end
      input.status = 1
      input.startTime = stateInfo.startTime
      input.duration = stateInfo.duration
    else
      -- DR reset / no longer active
      if input and inputIdx then
        self:RemoveFromInput(inputIdx)
        self:Display()
        return
      end
    end

    self:Display()
  end

  ---------------------------------------------------------------------------
  -- LoC polling fallback — dispatched from UpdateAll() every 0.1s via PeriodicUpdate event
  ---------------------------------------------------------------------------
  function container:PeriodicUpdate(unitID)
    if self.diminishEventReceived then
      return
    end

    pollLoCForUnit(self, unitID)
  end

  ---------------------------------------------------------------------------
  -- UnitDied — clear all DR icons
  ---------------------------------------------------------------------------
  function container:UnitDied()
    self:Reset()
  end

  ---------------------------------------------------------------------------
  -- Test mode
  ---------------------------------------------------------------------------
  -- Only use categories that have icons (PvP-relevant ones)
  local testCategories = {}
  for key, info in pairs(categoryKeyToInfo) do
    if info.icon then
      testCategories[#testCategories + 1] = key
    end
  end

  local TEST_MAX_ICONS = 3 -- realistic max simultaneous DRs per enemy

  function container:OnTestmodeEnabled()
    self.testmodeEnabled = true
  end

  function container:OnTestmodeDisabled()
    self.testmodeEnabled = false
    self:Reset()
  end

  function container:OnTestmodeTick()
    if not self.testmodeEnabled then
      self.testmodeEnabled = true
    end
    if #testCategories == 0 then
      return
    end

    -- Pick a random category, simulate a DR state update
    local catKey = testCategories[math.random(1, #testCategories)]
    local input, inputIdx = self:FindInputByAttribute("drCat", catKey)
    if input then
      -- Cycle: 1 -> 2, 2 -> remove (expired)
      if input.status >= 2 then
        if inputIdx then
          self:RemoveFromInput(inputIdx)
        end
      else
        input.status = input.status + 1
        input.startTime = GetTime()
        input.duration = 16
      end
    else
      -- Cap simultaneous icons to keep test mode realistic
      if #self.inputs < TEST_MAX_ICONS then
        self:NewInput({
          drCat = catKey,
          status = 1,
          startTime = GetTime(),
          duration = 16,
        })
      end
    end
    self:Display()
  end

  ---------------------------------------------------------------------------
  -- ApplyAllSettings
  ---------------------------------------------------------------------------
  function container:ApplyAllSettings()
    if not self.config then
      return
    end
    self:Display()
    for i = 1, #self.childFrames do
      local childFrame = self.childFrames[i]
      if childFrame.ApplyChildFrameSettings then
        childFrame:ApplyChildFrameSettings()
      end
    end
  end

  playerButton.DRTracking = container
  return playerButton.DRTracking
end
