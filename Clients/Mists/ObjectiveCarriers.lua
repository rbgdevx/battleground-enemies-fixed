local _, Data = ...
local BattleGroundEnemies = BattleGroundEnemies
local ObjectiveIcon = Data.ObjectiveIcon
local GetSpellTexture = C_Spell.GetSpellTexture
local GetUnitAuraBySpellID = C_UnitAuras.GetUnitAuraBySpellID
local MyCreateFontString = BattleGroundEnemies.MyCreateFontString
local L = Data.L

local unitTokens = { "arena1", "arena2" }
local factionFlags = { 301091, 301089 }
local netherstormFlags = { 34976, 34976 }

-- Instance IDs, including the rated Eye of the Storm variant.
local carrierSpellsByInstance = {
  [489] = factionFlags, -- Warsong Gulch
  [566] = netherstormFlags, -- Eye of the Storm
  [726] = factionFlags, -- Twin Peaks
  [968] = netherstormFlags, -- Rated Eye of the Storm
}

local module = BattleGroundEnemies:NewButtonModule({
  moduleName = "ObjectiveAndRespawn",
  localizedModuleName = L.ObjectiveAndRespawn_ObjectiveEnabled,
  defaultSettings = ObjectiveIcon.DefaultSettings(),
  options = function(location)
    return { TextSettings = ObjectiveIcon.TextOptions(location.Text) }
  end,
  enabledInThisExpansion = true,
  attachSettingsToButton = false,
  flags = { SetZeroWidthWhenDisabled = true },
})

local function createStackText(frame)
  local text = MyCreateFontString(frame)
  text:SetPoint("CENTER", frame, "CENTER")
  return text
end

function module:AttachToPlayerButton(playerButton)
  local frame = ObjectiveIcon.Create(playerButton)
  frame.StackText = createStackText(frame)

  function frame:Reset()
    self.carrierUnit = nil
    self:Hide()
  end

  function frame:SetCarrier(unit, spellID, stackText)
    self.carrierUnit = unit
    self.Icon:SetTexture(GetSpellTexture(spellID))
    self.StackText:SetText(stackText or "")
    self:SetShown(self.Enabled == true)
  end

  function frame:ApplyAllSettings()
    self.StackText:ApplyFontStringSettings(self.config.Text)
    self:SetShown(self.Enabled == true and self.carrierUnit ~= nil)
  end

  playerButton.ObjectiveAndRespawn = frame
  return frame
end

local activeSpells
local displayedByUnit = {}
local clearedUnits = {}

local function clearCarrier(unit)
  local frame = displayedByUnit[unit]
  if frame and frame.carrierUnit == unit then
    frame:Reset()
  end
  displayedByUnit[unit] = nil
end

local function getCarrierStackText(unit)
  local aura = GetUnitAuraBySpellID(unit, 46393) or GetUnitAuraBySpellID(unit, 46392)
  local stacks = aura and aura.applications
  return stacks and stacks > 0 and tostring(stacks) or nil
end

local function refreshCarrier(unit, spellID)
  if clearedUnits[unit] then
    return
  end
  local name = BattleGroundEnemies:GetCanonicalUnitName(unit)
  if not name then
    return
  end

  local button = BattleGroundEnemies.Allies.Players[name] or BattleGroundEnemies.Enemies.Players[name]
  local frame = button and button.ObjectiveAndRespawn
  if displayedByUnit[unit] ~= frame then
    clearCarrier(unit)
  end
  if frame then
    displayedByUnit[unit] = frame
    frame:SetCarrier(unit, spellID, getCarrierStackText(unit))
  end
end

local function refreshCarriers()
  if not activeSpells or not BattleGroundEnemies.enabled or BattleGroundEnemies:IsTestmodeActive() then
    return
  end
  for index, spellID in ipairs(activeSpells) do
    refreshCarrier(unitTokens[index], spellID)
  end
end

local function enterWorld()
  for _, unit in ipairs(unitTokens) do
    clearCarrier(unit)
  end
  wipe(clearedUnits)
  local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
  activeSpells = instanceType == "pvp" and carrierSpellsByInstance[instanceID] or nil
  refreshCarriers()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ARENA_OPPONENT_UPDATE")
frame:RegisterUnitEvent("UNIT_AURA", unpack(unitTokens))
frame:RegisterUnitEvent("UNIT_NAME_UPDATE", unpack(unitTokens))
frame:SetScript("OnEvent", function(_, event, unit, reason)
  if event == "PLAYER_ENTERING_WORLD" then
    enterWorld()
  elseif activeSpells and BattleGroundEnemies.enabled and not BattleGroundEnemies:IsTestmodeActive() then
    local index = unit:match("^arena([12])$")
    local spellID = index and activeSpells[tonumber(index)]
    if not spellID then
      return
    end
    if event == "ARENA_OPPONENT_UPDATE" then
      if reason == "cleared" then
        clearedUnits[unit] = true
        clearCarrier(unit)
        return
      elseif reason == "seen" then
        clearedUnits[unit] = nil
      end
    end
    refreshCarrier(unit, spellID)
  end
end)

-- Reconcile again after the roster has built or recycled its player buttons.
hooksecurefunc(BattleGroundEnemies.Enemies, "CreateOrRemovePlayerButtons", refreshCarriers)
hooksecurefunc(BattleGroundEnemies.Allies, "CreateOrRemovePlayerButtons", refreshCarriers)
