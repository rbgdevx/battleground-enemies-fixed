local _, Data = ...
local DRList = LibStub("DRList-1.0")
local GetSpellTexture = C_Spell.GetSpellTexture
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo

local DiminishingReturns = {
  Categories = {},
  Preview = {},
  MaxApplications = 3,
}
Data.ClassicDiminishingReturns = DiminishingReturns

local function getCategoryKey(category)
  return category == "incapacitate" and "incap" or category
end

for category, name in pairs(DRList:GetCategories()) do
  if category ~= "taunt" and category ~= "knockback" then
    DiminishingReturns.Categories[getCategoryKey(category)] = name
  end
end

for _, spellID in ipairs({ 118, 408, 5782, 339 }) do
  local category = DRList:GetCategoryBySpellID(spellID)
  DiminishingReturns.Preview[getCategoryKey(category)] = GetSpellTexture(spellID)
end

local function findPlayerButton(addon, guid, name)
  if not name or not guid or not guid:find("^Player%-") then
    return
  end
  local canonicalName = addon:CanonicalName(name)
  local button = addon.Enemies.Players[canonicalName] or addon.Allies.Players[canonicalName]
  local details = button and button.PlayerDetails
  if details and (not details.guid or details.guid == guid) then
    return button
  end
end

local function dispatchCategory(button, category, spellID)
  local key = getCategoryKey(category)
  if DiminishingReturns.Categories[key] then
    button:DispatchEvent("ClassicDiminishingReturnsUpdated", key, DRList:GetResetTime(category), spellID)
  end
end

local function dispatchCombatLog(addon)
  if not addon.enabled or addon:IsTestmodeActive() then
    return
  end
  local _, event, _, _, _, sourceFlags, _, guid, name, _, _, spellID, _, _, auraType = CombatLogGetCurrentEventInfo()
  if (event ~= "SPELL_AURA_REMOVED" and event ~= "SPELL_AURA_REFRESH") or auraType ~= "DEBUFF" then
    return
  end
  if bit.band(sourceFlags, COMBATLOG_OBJECT_CONTROL_PLAYER) == 0 then
    return
  end
  local category, categories = DRList:GetCategoryBySpellID(spellID)
  if not category then
    return
  end
  local button = findPlayerButton(addon, guid, name)
  if not button then
    return
  end

  if categories then
    for _, sharedCategory in ipairs(categories) do
      dispatchCategory(button, sharedCategory, spellID)
    end
  else
    dispatchCategory(button, category, spellID)
  end
end

function DiminishingReturns.Install(addon)
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")
  frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
      local _, instanceType = IsInInstance()
      if instanceType == "pvp" or instanceType == "arena" then
        self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
      else
        self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
      end
    else
      dispatchCombatLog(addon)
    end
  end)
end
