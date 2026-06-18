---@class Data
local Data = select(2, ...)
---@class BattleGroundEnemies
local BattleGroundEnemies = BattleGroundEnemies
local L = Data.L
local CreateFrame = CreateFrame
local GetTime = GetTime
local GetSpellTexture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
local GameTooltip = GameTooltip

local defaultSettings = {
  Enabled = true,
  Parent = "Button",
  ActivePoints = 1,
  Points = {
    {
      Point = "LEFT",
      RelativeFrame = "ObjectiveAndRespawn",
      RelativePoint = "RIGHT",
      OffsetX = 0,
    },
  },
  UseButtonHeightAsHeight = true,
  UseButtonHeightAsWidth = true,
  Cooldown = {
    ShowNumber = true,
    FontSize = 12,
    FontOutline = "OUTLINE",
    EnableShadow = false,
    DrawSwipe = true,
    ShadowColor = { 0, 0, 0, 1 },
  },
}

local options = function(location)
  return {
    CooldownTextSettings = {
      type = "group",
      name = L.Countdowntext,
      inline = true,
      order = 1,
      get = function(option)
        return Data.GetOption(location.Cooldown, option)
      end,
      set = function(option, ...)
        return Data.SetOption(location.Cooldown, option, ...)
      end,
      args = Data.AddCooldownSettings(location.Cooldown),
    },
  }
end

local trinket = BattleGroundEnemies:NewButtonModule({
  moduleName = "Trinket",
  localizedModuleName = L.Trinket,
  defaultSettings = defaultSettings,
  options = options,
  events = { "ArenaOpponentHidden" },
  enabledInThisExpansion = true,
})

function trinket:AttachToPlayerButton(playerButton)
  local frame = CreateFrame("frame", nil, playerButton)

  frame:HookScript("OnEnter", function(self)
    if self.spellId then
      BattleGroundEnemies:ShowTooltip(self, function()
        GameTooltip:SetSpellByID(self.spellId)
      end)
    end
  end)

  frame:HookScript("OnLeave", function(self)
    if GameTooltip:IsOwned(self) then
      GameTooltip:Hide()
    end
  end)

  frame.Icon = frame:CreateTexture()
  frame.Icon:SetAllPoints()
  frame:SetScript("OnSizeChanged", function(self, width, height)
    BattleGroundEnemies.CropImage(self.Icon, width, height)
  end)

  frame.Cooldown = BattleGroundEnemies.MyCreateCooldown(frame)

  function frame:TrinketCheck(spellId)
    if not Data.TrinketData[spellId] then
      return
    end
    self:DisplayTrinket(spellId, Data.TrinketData[spellId].itemID)
    if Data.TrinketData[spellId].cd then
      local trinketCD = Data.TrinketData[spellId].cd or 0
      -- If healer in retail reduce 2 min trinkets to 90 seconds
      if playerButton.PlayerDetails.PlayerRoleNumber == 1 and trinketCD == 120 then
        trinketCD = 90
      end
      self:SetTrinketCooldown(GetTime(), trinketCD)
    end
  end

  function frame:DisplayTrinket(spellId, itemID)
    local texture
    local spellIdSecret = issecretvalue and spellId and issecretvalue(spellId)
    local itemIdSecret = issecretvalue and itemID and issecretvalue(itemID)
    if itemID and itemID ~= 0 and not itemIdSecret then
      texture = GetItemIcon(itemID)
    elseif spellId and not spellIdSecret then
      -- Guard: GetSpellTexture crashes on nil input
      local _, spellTextureNoOverride = GetSpellTexture(spellId)
      texture = spellTextureNoOverride
    end
    -- Fallback: spellId/itemID are secret (arena Midnight restriction) — use generic medallion icon
    if not texture then
      local fallback = GetSpellTexture(208683) -- Gladiator's Medallion
      texture = fallback
    end
    self.spellId = spellId
    self.Icon:SetTexture(texture)
  end

  function frame:SetTrinketCooldown(startTime, duration)
    if startTime ~= 0 and duration ~= 0 then
      self.Cooldown:SetCooldown(startTime, duration)
    else
      self.Cooldown:Clear()
    end
  end

  function frame:StartFakeCooldown(duration)
    if self._fakeCdActive then
      return
    end
    self._fakeCdActive = true
    self.Cooldown:SetCooldown(GetTime(), duration)
    if self._fakeTimer then
      self._fakeTimer:Cancel()
    end
    self._fakeTimer = C_Timer.NewTimer(duration, function()
      self._fakeCdActive = false
    end)
  end

  function frame:ResetFakeCooldown()
    self._fakeCdActive = false
    if self._fakeTimer then
      self._fakeTimer:Cancel()
      self._fakeTimer = nil
    end
  end

  function frame:Reset()
    self.spellId = false
    self:ResetFakeCooldown()
    self.Icon:SetTexture(nil)
    self.Cooldown:Clear()
  end

  function frame:ArenaOpponentHidden()
    -- Reset trinket display when arena token is cleared
    -- (e.g., orb changes hands in Kotmogu, or arena opponent leaves)
    self:Reset()
  end

  function frame:ApplyAllSettings()
    -- Hide in BGs: ARENA_COOLDOWNS_UPDATE never fires there so cooldowns would
    -- never track. Icons would show but timers would never start. Show everywhere else.
    local _, instanceType = IsInInstance()
    if instanceType == "pvp" then
      self:Hide()
      return
    end
    self:Show()
    local moduleSettings = self.config
    self.Cooldown:ApplyCooldownSettings(moduleSettings.Cooldown, false, { 0, 0, 0, 0.5 })
  end

  playerButton.Trinket = frame
  return playerButton.Trinket
end
