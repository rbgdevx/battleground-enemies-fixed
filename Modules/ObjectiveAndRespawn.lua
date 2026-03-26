---@class BattleGroundEnemies
local BattleGroundEnemies = BattleGroundEnemies

---@type string
local AddonName = ...
---@class Data
local Data = select(2, ...)
local GetTime = GetTime
local GetSpellTexture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture

local IsCataClassic = WOW_PROJECT_ID == WOW_PROJECT_CATACLYSM_CLASSIC

local L = Data.L

local defaultSettings = {
  Enabled = true,
  Parent = "Button",
  ActivePoints = 1,
  Points = {
    {
      Point = "LEFT",
      RelativeFrame = "Button",
      RelativePoint = "RIGHT",
      OffsetX = 0,
    },
  },
  Cooldown = {
    FontSize = 12,
  },
  Text = {
    FontSize = 17,
  },
  UseButtonHeightAsHeight = true,
  UseButtonHeightAsWidth = true,
}

local options = function(location)
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
      order = 2,
      args = Data.AddCooldownSettings(location.Cooldown),
    },
  }
end

-- Orb spell IDs for Temple of Kotmogu based on Enum.PvPUnitClassification
-- (IDs verified from BattlegroundWinConditions)
local orbSpells = {
  [7] = 1119885, -- Blue orb
  [8] = 1119886, -- Green orb
  [9] = 1119887, -- Orange orb
  [10] = 1119888, -- Purple orb
}

-- Helper: Find the correct button for an arena orb carrier
-- Uses full PID matching and handles bidirectional cleanup when orbs change hands
-- Searches both Enemies and Allies since arena tokens cover both factions
local function GetOrbCarrierButton(unitID)
  BattleGroundEnemies:ClearScanCycleCache()
  local matchedButton = BattleGroundEnemies:GetPlayerbuttonByUnitID(unitID, "Enemies", true)
    or BattleGroundEnemies:GetPlayerbuttonByUnitID(unitID, "Allies", true)

  if not matchedButton then
    return nil
  end

  -- Check if this is already the correct mapping
  local currentMapping = BattleGroundEnemies.ArenaIDToPlayerButton[unitID]
  if currentMapping == matchedButton then
    return matchedButton -- Mapping is already correct
  end

  -- Bidirectional cleanup needed

  -- 1. Clear stale mapping FROM the arena token (old button that had this token)
  if currentMapping and currentMapping ~= matchedButton then
    currentMapping:UpdateEnemyUnitID("Arena", false)
    currentMapping:DispatchEvent("ArenaOpponentHidden") -- Reset trinket, etc.
  end

  -- 2. Clear stale mapping FROM the matched button (if it had a different arena token)
  local oldArena = matchedButton.UnitIDs and matchedButton.UnitIDs.Arena
  if oldArena and oldArena ~= unitID then
    BattleGroundEnemies.ArenaIDToPlayerButton[oldArena] = nil
    -- Note: matchedButton will get ArenaOpponentShown below, which handles the transition
  end

  -- 3. Assign fresh mapping
  matchedButton:ArenaOpponentShown(unitID)

  return matchedButton
end

-- Module-level function to check orbs for all arena units
-- In Kotmogu BG, WoW assigns arena tokens (arena1-5) to orb carriers
local isCheckingOrbs = false
local function CheckAllOrbs()
  if isCheckingOrbs then
    return
  end
  isCheckingOrbs = true

  local ok, err = pcall(function()
    -- First: clear stale arena tokens for buttons that no longer have orbs
    for i = 1, 4 do
      local unitID = "arena" .. i
      local button = BattleGroundEnemies.ArenaIDToPlayerButton[unitID]
      if button then
        if not UnitExists(unitID) then
          BattleGroundEnemies.ArenaIDToPlayerButton[unitID] = nil
          button:UpdateEnemyUnitID("Arena", false)
          button:DispatchEvent("ArenaOpponentHidden")
        end
      end
    end

    -- Second: show orbs on players who have them
    for i = 1, 4 do
      local unitID = "arena" .. i
      if UnitExists(unitID) then
        local _, battleGroundDebuffs = BattleGroundEnemies:GetBattlegroundAuras()
        local button = GetOrbCarrierButton(unitID)
        if button and button.ObjectiveAndRespawn and battleGroundDebuffs then
          local spellId = battleGroundDebuffs[i]
          if spellId then
            button.ObjectiveAndRespawn.Icon:SetTexture(GetSpellTexture(spellId))
            button.ObjectiveAndRespawn:Show()
          end
        end
      end
    end
  end)

  isCheckingOrbs = false
  if not ok then
    error(err)
  end
end

-- Helper: Find the correct button for a flag carrier
-- Uses full PID matching and handles bidirectional cleanup when flags change hands
-- Searches both Enemies and Allies since arena tokens cover both factions
local function GetFlagCarrierButton(unitID)
  BattleGroundEnemies:ClearScanCycleCache()
  local matchedButton = BattleGroundEnemies:GetPlayerbuttonByUnitID(unitID, "Enemies", true)
    or BattleGroundEnemies:GetPlayerbuttonByUnitID(unitID, "Allies", true)

  if not matchedButton then
    return nil
  end

  -- Check if this is already the correct mapping
  local currentMapping = BattleGroundEnemies.ArenaIDToPlayerButton[unitID]
  if currentMapping == matchedButton then
    return matchedButton -- Mapping is already correct
  end

  -- Bidirectional cleanup needed

  -- 1. Clear stale mapping FROM the arena token (old button that had this token)
  if currentMapping and currentMapping ~= matchedButton then
    currentMapping:UpdateEnemyUnitID("Arena", false)
    currentMapping:DispatchEvent("ArenaOpponentHidden") -- Reset trinket, etc.
  end

  -- 2. Clear stale mapping FROM the matched button (if it had a different arena token)
  local oldArena = matchedButton.UnitIDs and matchedButton.UnitIDs.Arena
  if oldArena and oldArena ~= unitID then
    BattleGroundEnemies.ArenaIDToPlayerButton[oldArena] = nil
  end

  -- 3. Assign fresh mapping
  matchedButton:ArenaOpponentShown(unitID)

  return matchedButton
end

-- Module-level function to check flags for all arena units (WSG, Twin Peaks, Deephaul Ravine)
local isCheckingFlags = false
local function CheckAllFlags()
  if isCheckingFlags then
    return
  end
  isCheckingFlags = true

  local ok, err = pcall(function()
    -- First: clear stale arena tokens for buttons that no longer have flags
    for i = 1, 2 do
      local unitID = "arena" .. i
      local button = BattleGroundEnemies.ArenaIDToPlayerButton[unitID]
      if button then
        if not UnitExists(unitID) then
          -- This arena unit doesn't exist anymore (flag was dropped/captured)
          BattleGroundEnemies.ArenaIDToPlayerButton[unitID] = nil
          button:UpdateEnemyUnitID("Arena", false)
          button:DispatchEvent("ArenaOpponentHidden")
        end
      end
    end

    -- Second: show flags on players who have them
    for i = 1, 2 do
      local unitID = "arena" .. i
      if UnitExists(unitID) then
        local battlegroundBuffs = BattleGroundEnemies:GetBattlegroundAuras()
        local button = GetFlagCarrierButton(unitID)
        if button and button.ObjectiveAndRespawn and battlegroundBuffs then
          local spellId = battlegroundBuffs[i == 1 and 0 or 1]
          if spellId then
            button.ObjectiveAndRespawn.Icon:SetTexture(GetSpellTexture(spellId))
            button.ObjectiveAndRespawn:Show()
          end
        end
      end
    end
  end)

  isCheckingFlags = false
  if not ok then
    error(err)
  end
end

-- Module-level event frame for objective detection triggers
-- Supplements per-button UPDATE_UI_WIDGET handlers with additional event sources
local objectiveEventFrame = CreateFrame("Frame")
objectiveEventFrame:RegisterEvent("UPDATE_UI_WIDGET")
objectiveEventFrame:RegisterEvent("UNIT_CLASSIFICATION_CHANGED")
objectiveEventFrame:RegisterEvent("ARENA_OPPONENT_UPDATE")
objectiveEventFrame:SetScript("OnEvent", function(self, event, ...)
  if event == "UPDATE_UI_WIDGET" then
    local widgetInfo = ...
    if not widgetInfo or not widgetInfo.widgetID then
      return
    end
    local id = widgetInfo.widgetID
    -- 1683: Kotmogu (Orbs), 1640: WSG/Twin Peaks (Flags), 1672: EotS (Flags)
    if id == 1683 then
      CheckAllOrbs()
    elseif id == 1640 or id == 1672 then
      CheckAllFlags()
    end
  elseif event == "UNIT_CLASSIFICATION_CHANGED" then
    -- May fire when a unit picks up or drops an orb/flag
    CheckAllOrbs()
    CheckAllFlags()
  elseif event == "ARENA_OPPONENT_UPDATE" then
    -- Fires when arena units appear/disappear
    CheckAllOrbs()
    CheckAllFlags()
  end
end)

local objectiveAndRespawn = BattleGroundEnemies:NewButtonModule({
  moduleName = "ObjectiveAndRespawn",
  localizedModuleName = L.ObjectiveAndRespawnTimer,
  defaultSettings = defaultSettings,
  options = options,
  events = {
    "UnitDied",
    "UnitRevived",
    "ArenaOpponentShown",
    "ArenaOpponentHidden",
    "UPDATE_UI_WIDGET",
    "PLAYER_ENTERING_WORLD",
    "OnTestmodeEnabled",
    "OnTestmodeDisabled",
    "OnTestmodeTick",
  },
  enabledInThisExpansion = true,
  attachSettingsToButton = false,
  flags = {
    SetZeroWidthWhenDisabled = true,
  },
})

function objectiveAndRespawn:AttachToPlayerButton(playerButton)
  local frame = CreateFrame("frame", nil, playerButton)
  frame:SetFrameLevel(playerButton:GetFrameLevel() + 5)

  frame.Icon = frame:CreateTexture(nil, "BORDER")
  frame.Icon:SetAllPoints()

  frame:SetScript("OnSizeChanged", function(self, width, height)
    BattleGroundEnemies.CropImage(self.Icon, width, height)
  end)
  frame:Hide()

  -- Explicitly register the event and set the script handler
  frame:RegisterEvent("UPDATE_UI_WIDGET")
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")

  frame:SetScript("OnEvent", function(self, event, ...)
    if self[event] then
      self[event](self, ...)
    end
  end)

  frame.AuraText = BattleGroundEnemies.MyCreateFontString(frame)
  frame.AuraText:SetAllPoints()
  frame.AuraText:SetJustifyH("CENTER")

  frame.Cooldown = BattleGroundEnemies.MyCreateCooldown(frame)
  frame.Cooldown:Hide()

  frame.Cooldown:SetScript("OnCooldownDone", function()
    -- Respawn timer expired, mark the player as alive
    if playerButton.isDead then
      playerButton:PlayerIsAlive()
      -- No unitID available so push a full-health update directly;
      -- spirit healer always resurrects at 100% health
      playerButton:UpdateHealth(nil, 1, 0, 100, 1)
    end
  end)

  function frame:Reset()
    if BattleGroundEnemies.states.editmodeActive and self.Enabled then
      self:Show()
      self.Icon:SetTexture(GetSpellTexture(8326))
    else
      self:Hide()
      self.Icon:SetTexture()
      if self.AuraText:GetFont() then
        self:HideText()
      end
    end
    self.ActiveRespawnTimer = false
    self.Cooldown:Clear() -- this doesn't seem to trigger OnCooldownDone for some reason, i am sure it used to in the past
  end

  function frame:HideText()
    self.AuraText:SetText("")
    self.shownValue = false
  end

  function frame:ApplyAllSettings()
    if not self.config then
      return
    end
    local conf = self.config
    self.AuraText:ApplyFontStringSettings(conf.Text)
    self.Cooldown:ApplyCooldownSettings(conf.Cooldown, true, { 0, 0, 0, 0.75 })

    -- if not playerButton.isDead then
    --   self:UnitRevived()
    -- end

    -- -- In Kotmogu, don't reset if this player has an orb (avoids hiding orb on nameplate update)
    -- local states = BattleGroundEnemies:GetActiveStates()
    -- if states.currentMapId == 417 then
    --   local arenaID = playerButton.UnitIDs and playerButton.UnitIDs.Arena
    --   if arenaID and UnitExists(arenaID) then
    --     local classification = UnitPvpClassification(arenaID)
    --     if classification and orbSpells[classification] then
    --       -- Player has orb, don't reset - just re-apply the orb display
    --       self.Icon:SetTexture(orbSpells[classification])
    --       self:Show()
    --       return
    --     end
    --   end
    -- end

    -- self:Reset()
  end

  function frame:UnitRevived()
    frame:Reset()
  end

  function frame:UnitDied()
    local states = BattleGroundEnemies:GetActiveStates()

    -- Force show death visual for all battlegrounds
    self:Show()
    self:SetFrameLevel(playerButton:GetFrameLevel() + 10) -- Ensure on top
    self.Icon:SetTexture(GetSpellTexture(8326)) -- Ghost/death icon
    self:HideText()
    self.ActiveRespawnTimer = true

    -- Set respawn timer based on BG type (from original BGE)
    local respawnTime = 26 -- Default RBG respawn time
    if IsCataClassic then
      respawnTime = 45 -- Cata Classic has longer respawn
    else
      if states.isSoloRBG then
        if states.currentMapId ~= 2656 then -- Not Deephaul Ravine
          respawnTime = 16 -- Blitz has faster respawn
        end
      end
    end
    self.Cooldown:SetCooldown(GetTime(), respawnTime)
  end

  function frame:ArenaOpponentShown()
    -- local battlegroundBuffs = BattleGroundEnemies:GetBattlegroundAuras()
    -- if battlegroundBuffs then
    --   local spellId =
    --     battlegroundBuffs[playerButton.PlayerIsEnemy and BattleGroundEnemies.EnemyFaction or BattleGroundEnemies.AllyFaction]
    --   if spellId then
    --     self.Icon:SetTexture(GetSpellTexture(spellId))
    --     self:Show()
    --   end
    -- end

    self:HideText()

    local states = BattleGroundEnemies:GetActiveStates()

    -- Check for objectives when arena opponents are shown
    if states.currentMapId == 417 then
      CheckAllOrbs()
    elseif
      states.currentMapId == 206
      or states.currentMapId == 1339
      or states.currentMapId == 112
      or states.currentMapId == 397
      or states.currentMapId == 2345
    then
      -- WSG (2106), Twin Peaks (726), Deephaul Ravine (2656), Eye of the Storm (566 normal, 968 rated) - check flags
      CheckAllFlags()
    end
  end

  function frame:ArenaOpponentHidden()
    -- -- In Kotmogu, don't reset orbs when arena opponent "hides" (goes out of range)
    -- -- The orb classification persists even when out of nameplate range
    -- -- Kotmogu: check if this player still has an orb via their arena token
    -- local arenaID = playerButton.UnitIDs and playerButton.UnitIDs.Arena
    -- if arenaID and UnitExists(arenaID) then
    --   local classification = UnitPvpClassification(arenaID)
    --   if classification and orbSpells[classification] then
    --     -- Still has orb, don't hide
    --     return
    --   end
    -- end

    self:Reset()
  end

  function frame:PLAYER_ENTERING_WORLD()
    -- Just check everything on load (map checks handle if it runs or not)
    local states = BattleGroundEnemies:GetActiveStates()
    -- 2106=WSG, 726=Twin Peaks, 2656=Deephaul Ravine, 566=EOTS, 968=EOTS Rated
    if
      states.currentMapId == 206
      or states.currentMapId == 1339
      or states.currentMapId == 112
      or states.currentMapId == 397
      or states.currentMapId == 2345
    then
      CheckAllFlags()

      -- Start ticker for frequent updates (widget events unreliable)
      if not self.FlagTicker then
        self.FlagTicker = C_Timer.NewTicker(1, function()
          CheckAllFlags()
        end)
      end
    elseif states.currentMapId == 417 then
      -- Temple of Kotmogu (417)
      CheckAllOrbs()

      -- Start ticker for frequent updates if not already running
      if not self.OrbTicker then
        self.OrbTicker = C_Timer.NewTicker(1, function()
          CheckAllOrbs()
        end)
      end
    else
      -- Cancel tickers if we leave objective BGs
      if self.OrbTicker then
        self.OrbTicker:Cancel()
        self.OrbTicker = nil
      end
      if self.FlagTicker then
        self.FlagTicker:Cancel()
        self.FlagTicker = nil
      end
    end
  end

  function frame:UPDATE_UI_WIDGET(widgetInfo)
    if not widgetInfo or not widgetInfo.widgetID then
      return
    end

    local widgetID = widgetInfo.widgetID

    -- 1640: WSG/Twin Peaks (Flags)
    -- 1672: Eye of the Storm (Flags)
    -- 1683: Kotmogu (Orbs)
    if widgetID == 1640 or widgetID == 1672 then
      CheckAllFlags()
    elseif widgetID == 1683 then
      CheckAllOrbs()
    end
  end

  -- Test mode: simulate flag/orb carrying and death/respawn
  local testObjectiveSpells = { 156618, 156621, 8326 } -- Horde flag, Alliance flag, Ghost

  function frame:OnTestmodeEnabled()
    self.testmodeEnabled = true
  end

  function frame:OnTestmodeDisabled()
    self.testmodeEnabled = false
    self:Reset()
  end

  function frame:OnTestmodeTick()
    if not self.testmodeEnabled then
      self.testmodeEnabled = true
    end
    -- Randomly show an objective or respawn, or hide
    local roll = math.random(1, 5)
    if roll <= 2 then
      -- Show a flag/objective icon
      local spellId = testObjectiveSpells[math.random(1, #testObjectiveSpells)]
      self.Icon:SetTexture(GetSpellTexture(spellId))
      self:Show()
      self.ActiveRespawnTimer = false
      self.Cooldown:Clear()
    elseif roll == 3 then
      -- Simulate death with respawn timer
      self.Icon:SetTexture(GetSpellTexture(8326))
      self:Show()
      self.ActiveRespawnTimer = true
      self.Cooldown:SetCooldown(GetTime(), 16)
    else
      -- Hide (no objective)
      self:Reset()
    end
  end

  playerButton.ObjectiveAndRespawn = frame
  return playerButton.ObjectiveAndRespawn
end
