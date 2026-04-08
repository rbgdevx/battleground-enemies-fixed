---@class Data
---@class BattleGroundEnemies

---@type string
local AddonName = ...
---@class Data
local Data = select(2, ...)

---@class BattleGroundEnemies
local BattleGroundEnemies = BattleGroundEnemies
local L = Data.L

--WoW API
local pairs = pairs
local type = type

local CreateFrame = CreateFrame
local GetArenaOpponentSpec = GetArenaOpponentSpec
local GetSpecializationInfoByID = GetSpecializationInfoByID
local GetUnitName = GetUnitName
local InCombatLockdown = InCombatLockdown
local UnitGUID = UnitGUID
local UnitRace = UnitRace

--lua
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_random = math.random
local table_insert = table.insert
local table_remove = table.remove

local HasSpeccs = not not GetSpecialization

--Libs
local LibRaces = LibStub("LibRaces-1.0")

local IsRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
local IsClassic = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
local IsTBCC = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC
local IsWrath = WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC

--[[  from wowpedia
1	IconSmall RaidStar.png 		Yellow 4-point Star
2	IconSmall RaidCircle.png 	Orange Circle
3	IconSmall RaidDiamond.png 	Purple Diamond
4	IconSmall RaidTriangle.png 	Green Triangle
5	IconSmall RaidMoon.png 		White Crescent Moon
6	IconSmall RaidSquare.png 	Blue Square
7	IconSmall RaidCross.png 	Red "X" Cross
8	IconSmall RaidSkull.png 	White Skull
 ]]

local testEvents = {
  ---@param mainFrame MainFrame
  function(mainFrame, playerButton)
    if playerButton.isDead then
      return
    end

    -- hide old flag carrier
    local oldFlagholder = mainFrame.Testmode.holdsFlag
    if oldFlagholder then
      oldFlagholder:DispatchEvent("ArenaOpponentHidden")
    end

    playerButton:ArenaOpponentShown()

    mainFrame.Testmode.holdsFlag = playerButton
    mainFrame.Testmode.hasFlag = true
  end,
  ---@param mainFrame MainFrame
  function(mainFrame, playerButton)
    if playerButton.isDead then
      return
    end
    -- Trinket testmode: simulate a trinket use via the Trinket module if it exists
    if playerButton.Trinket and playerButton.Trinket.TrinketCheck and BattleGroundEnemies.Testmode.RandomTrinkets then
      local randomTrinket =
        BattleGroundEnemies.Testmode.RandomTrinkets[math_random(1, #BattleGroundEnemies.Testmode.RandomTrinkets)]
      playerButton.Trinket:TrinketCheck(randomTrinket)
    end
  end,
  ---@param mainFrame MainFrame
  function(mainFrame, playerButton)
    if playerButton.isDead then
      return
    end
    -- CC testmode: simulate a CC effect on SpecClassPriority if it exists
    local scp = playerButton.SpecClassPriority
    if scp and scp.config and scp.config.showHighestPriority then
      -- Random CC spells: Polymorph, HoJ, Fear, Kidney Shot, Psychic Scream
      local testCCSpells = {
        { spellId = 118, duration = 8, priority = 7 }, -- Polymorph (disorient)
        { spellId = 853, duration = 6, priority = 8 }, -- Hammer of Justice (stun)
        { spellId = 5782, duration = 8, priority = 7 }, -- Fear (fear)
        { spellId = 408, duration = 6, priority = 8 }, -- Kidney Shot (stun)
        { spellId = 8122, duration = 8, priority = 7 }, -- Psychic Scream (fear)
        { spellId = 15487, duration = 4, priority = 5 }, -- Silence
      }
      local cc = testCCSpells[math_random(1, #testCCSpells)]
      local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(cc.spellId)
        or GetSpellTexture and GetSpellTexture(cc.spellId)
      if icon then
        local currentTime = GetTime()
        wipe(scp.PriorityAuras)
        scp.PriorityAuras[1] = {
          spellId = cc.spellId,
          icon = icon,
          expirationTime = currentTime + cc.duration,
          duration = cc.duration,
          Priority = cc.priority,
        }
        scp:Update()
      end
    end
  end,
  ---@param mainFrame MainFrame
  function(mainFrame, playerButton)
    playerButton:UNIT_POWER_FREQUENT()
    if playerButton.isDead then
      return
    end
  end,
  ---@param mainFrame MainFrame
  function(mainFrame, playerButton)
    playerButton:UNIT_HEALTH()
  end,
  ---@param mainFrame MainFrame
  function(mainFrame, playerButton)
    if playerButton.Target then
      playerButton:IsNoLongerTarging(playerButton.Target)
    end

    local oppositeMainFrame = playerButton:GetOppositeMainFrame()
    if oppositeMainFrame then --this really should never be nil
      local randomPlayer = oppositeMainFrame:GetRandomPlayer()

      if randomPlayer then
        playerButton:IsNowTargeting(randomPlayer)
      end
    end
  end,
  ---@param mainFrame MainFrame
  function(mainFrame, playerButton)
    playerButton:UpdateRaidTargetIcon(math_random(1, 8))
  end,
  function(mainFrame, playerButton)
    playerButton:UpdateRange(not playerButton.wasInRange)
  end,
}

---@class MainFrame : Button
---@field Players table<string, PlayerButton>
---@field CurrentPlayerOrder table<number, PlayerButton>
---@field InactivePlayerButtons table<number, PlayerButton>
---@field NewPlayersDetails table<number, table>
---@field PlayerType string
---@field PlayerSources table<string, table>
---@field NumPlayers number
---@field Counter table<string, number>
---@field PlayerCount MyFontString
---@field ActiveProfile MyFontString
---@return MainFrame
local function CreateMainFrame(playerType)
  --binding voodoo
  -- how it works:
  -- SecureHandlerEnterLeaveTemplate is necessary to add the secure onenter and onleave event handlers
  -- the handler then sets the wheeldown and wheelup binding to execute a button click using the global button names
  -- when mouswheel is scrolled up or down it triggers a button click and runs the onclick kook from SecureHandlerWrapScript gets execute, which then sets the macrotext

  ---@class MainFrame
  local mainframe =
    CreateFrame("Button", "BGE" .. playerType, UIParent, "SecureActionButtonTemplate, SecureHandlerEnterLeaveTemplate")

  mainframe:SetAttribute("type4", "macro")
  mainframe:SetAttribute("type5", "macro")
  mainframe:RegisterForClicks(GetCVarBool("ActionButtonUseKeyDown") and "AnyDown" or "AnyUp")

  SecureHandlerWrapScript(
    mainframe,
    "OnClick",
    mainframe,
    [[

		local maxUnits = self:GetAttribute("maxUnits")
		local playerIndex = self:GetAttribute("playerIndex")
		local nextPlayerIndex

		if button == "Button4" then
			nextPlayerIndex = playerIndex -1
			if nextPlayerIndex <1 then
				nextPlayerIndex = maxUnits
			end
		else
			nextPlayerIndex = playerIndex + 1
			if nextPlayerIndex >maxUnits then
				nextPlayerIndex = 1
			end
		end

		local nextTargetName = self:GetAttribute("playerName"..nextPlayerIndex)

		self:SetAttribute("macrotext",'/cleartarget\n' ..
				'/targetexact ' ..
				nextTargetName)
		self:SetAttribute("playerIndex", nextPlayerIndex)
	]]
  )

  mainframe.Players = {} --index = name, value = button(table), contains enemyButtons
  mainframe.CurrentPlayerOrder = {} --index = number, value = playerButton(table)
  mainframe.InactivePlayerButtons = {} --index = number, value = button(table)
  mainframe.NewPlayersDetails = {} -- index = numeric, value = playerdetails, used for creation of new buttons, use (temporary) table to not create an unnecessary new button if another player left
  mainframe.PlayerType = playerType
  mainframe.PlayerSources = {}
  mainframe.NumPlayers = 0
  mainframe.Counter = {}
  mainframe.Testmode = {
    holdsFlag = false,
    hasFlag = false,
  }

  mainframe:SetScript("OnEvent", function(self, event, ...)
    if self.db and self.db.profile and self.db.profile.DebugBlizzEvents then
      self:Debug("OnEvent", event, ...)
    end
    self[event](self, ...)
  end)

  function mainframe:InitializeAllPlayerSources()
    for sourceName in pairs(BattleGroundEnemies.consts.PlayerSources) do
      mainframe.PlayerSources[sourceName] = {}
    end
  end

  mainframe:InitializeAllPlayerSources()

  function mainframe:RemoveAllPlayersFromAllSources()
    self:InitializeAllPlayerSources()
    self.RealPlayerCount = nil
    self:AfterPlayerSourceUpdate()
  end

  function mainframe:Debug(...)
    BattleGroundEnemies:Debug(self.PlayerType, ...)
  end

  function mainframe:RemoveAllPlayersFromSource(source)
    self:BeforePlayerSourceUpdate(source)
    self:AfterPlayerSourceUpdate()
  end

  function mainframe:BeforePlayerSourceUpdate(source)
    self.PlayerSources[source] = {}
  end

  function mainframe:AddPlayerToSource(source, playerT)
    self:Debug("AddPlayerToSource", source, playerT)
    if playerT.name then
      if playerT.name == "" then
        return
      end
    else
      --only allow no name if its a arena prep enemy
      if not playerT.additionalData then
        return
      end
      if not playerT.additionalData.PlayerArenaUnitID then
        return
      end
    end

    if not playerT.classToken then
      return
    end
    if playerT.classToken == "" then
      return
    end

    table_insert(self.PlayerSources[source], playerT)
  end

  function mainframe:FindPlayerInSource(source, playerT)
    local playerSource = self.PlayerSources[source]
    for i = 1, #playerSource do
      local playerData = playerSource[i]
      if playerData.name == playerT.name then
        return playerData
      end
    end
  end

  local function matchBattleFieldScoreToArenaEnemyPlayer(scoreTables, arenaPlayerInfo)
    BattleGroundEnemies:Debug("matchBattleFieldScoreToArenaEnemyPlayer", scoreTables, arenaPlayerInfo)
    local foundPlayer = false
    local foundMatchIndex
    for i = 1, #scoreTables do
      local scoreInfo = scoreTables[i]

      -- local faction = scoreInfo.faction
      -- local name = scoreInfo.name
      -- local classToken = scoreInfo.classToken
      -- local specName = scoreInfo.talentSpec
      -- local raceName = scoreInfo.raceName

      if scoreInfo.classToken and arenaPlayerInfo.classToken then
        if
          scoreInfo.faction == BattleGroundEnemies.EnemyFaction
          and scoreInfo.classToken == arenaPlayerInfo.classToken
          and scoreInfo.talentSpec == arenaPlayerInfo.specName
        then --specname/talentSpec can be nil for old expansions
          if foundPlayer then
            return false -- we already had a match but found a second player that matches, unlucky
          end
          foundPlayer = true --we found a match, make sure its the only one
          foundMatchIndex = i
        end
      end
    end
    if foundPlayer then
      return scoreTables[foundMatchIndex]
    end
  end

  function mainframe:AfterPlayerSourceUpdate()
    self:Debug("AfterPlayerSourceUpdate")
    local newPlayers = {} --contains combined data from PlayerSources
    if self.PlayerType == BattleGroundEnemies.consts.PlayerTypes.Enemies then
      if BattleGroundEnemies:IsTestmodeOrEditmodeActive() then
        newPlayers = self.PlayerSources[BattleGroundEnemies.consts.PlayerSources.FakePlayers]
      else
        local scoreboardEnemies = self.PlayerSources[BattleGroundEnemies.consts.PlayerSources.Scoreboard]
        local numScoreboardEnemies = #scoreboardEnemies
        local addScoreBoardPlayers = false
        if BattleGroundEnemies:GetActiveStates().isInArena then
          self:Debug("AfterPlayerSourceUpdate", "inArena")
          --use arenaPlayers is primary source to preserve same order arena1 to arena3, scoreboard doesn't offer this
          local arenaEnemies = self.PlayerSources[BattleGroundEnemies.consts.PlayerSources.ArenaPlayers]
          local numArenaEnemies = #arenaEnemies
          self:Debug("AfterPlayerSourceUpdate", numArenaEnemies)

          if numArenaEnemies > 0 then
            for i = 1, numArenaEnemies do
              local playerName
              local arenaEnemy = arenaEnemies[i]
              if arenaEnemy.name then
                playerName = arenaEnemy.name
              else
                --useful in solo shuffle in first round, then we can show a playername via data from scoreboard
                local match = matchBattleFieldScoreToArenaEnemyPlayer(scoreboardEnemies, arenaEnemy)
                if match then
                  self:Debug("found a name match")
                  playerName = match.name
                else
                  self:Debug("didnt find a match", arenaEnemy.additionalData.PlayerArenaUnitID)
                  -- use the unitID
                  playerName = arenaEnemy.additionalData.PlayerArenaUnitID
                end
              end
              local t = Mixin({}, arenaEnemy)
              t.name = playerName
              table.insert(newPlayers, t)
            end
          else
            addScoreBoardPlayers = true
            --maybe we got some in scoreboard
          end
        else --in BattleGround
          if numScoreboardEnemies > 0 then
            addScoreBoardPlayers = true
          end
        end
        if addScoreBoardPlayers then
          for i = 1, numScoreboardEnemies do
            local scoreboardEnemy = scoreboardEnemies[i]
            table.insert(newPlayers, {
              name = scoreboardEnemy.name,
              raceName = scoreboardEnemy.raceName,
              classToken = scoreboardEnemy.classToken,
              specName = scoreboardEnemy.talentSpec,
              realmName = scoreboardEnemy.realmName, -- Explicitly at top level as user requested
              additionalData = {
                className = scoreboardEnemy.className, -- Added
                roleAssigned = scoreboardEnemy.roleAssigned, -- Added
                faction = scoreboardEnemy.faction, -- Added
                honorLevel = scoreboardEnemy.honorLevel,
                -- Scoreboard generally doesn't have level/sex for enemies, but we stash what we can
                level = scoreboardEnemy.level or 0,
                sex = scoreboardEnemy.sex,
                guid = scoreboardEnemy.guid,
                englishRace = scoreboardEnemy.englishRace,
                realmName = scoreboardEnemy.realmName, -- Added realmName (kept for Mixin safety)
              },
            })
          end
        end
      end
    else --"Allies"
      local groupMembers = self.PlayerSources[BattleGroundEnemies.consts.PlayerSources.GroupMembers]
      local numGroupMembers = #groupMembers
      local addWholeGroup = false
      if BattleGroundEnemies:IsTestmodeOrEditmodeActive() then
        if BattleGroundEnemies.db.profile.Testmode_UseTeammates then
          addWholeGroup = true
        else
          --just addMyself and fill up the rest with fakeplayers
          if type(BattleGroundEnemies.UserButton) == "table" and BattleGroundEnemies.UserButton.PlayerDetails then
            table.insert(newPlayers, groupMembers[numGroupMembers]) --i am always last in here
            local fakeAllies = self.PlayerSources[BattleGroundEnemies.consts.PlayerSources.FakePlayers]
            local numFakeAllies = #fakeAllies
            for i = 1, numFakeAllies do
              local fakeAlly = fakeAllies[i]
              table.insert(newPlayers, fakeAlly)
            end
          end
        end
      else
        addWholeGroup = true
      end
      if addWholeGroup then
        for i = 1, numGroupMembers do
          local groupMember = groupMembers[i]
          local specName = groupMember.specName
          if not specName or specName == "" then
            local name = groupMember.name
            --self:Debug("player", name, "doesnt have a spec from group member")
            local match = self:FindPlayerInSource(BattleGroundEnemies.consts.PlayerSources.Scoreboard, groupMember)
            if match then
              --self:Debug("player", name, "we found a spec from the scoreboard")
              groupMember.specName = match.talentSpec
            end
          end
          table.insert(newPlayers, groupMember)
        end
      end
    end
    self:BeforePlayerUpdate()
    for i = 1, #newPlayers do
      local newPlayer = newPlayers[i]
      local name = newPlayer.name
      local raceName = newPlayer.raceName
      local classToken = newPlayer.classToken
      local specName = newPlayer.specName
      local additionalData = newPlayer.additionalData
      local realmName = newPlayer.realmName
      self:Debug("AfterPlayer", name, raceName, classToken, specName, additionalData)
      self:CreateOrUpdatePlayerDetails(name, raceName, classToken, specName, realmName, additionalData)
    end
    self:SetPlayerCount(#newPlayers)
    self:CreateOrRemovePlayerButtons()

    -- Hide mainframe when no players to show, to prevent empty frame blocking clicks
    if not BattleGroundEnemies:IsTestmodeOrEditmodeActive() then
      if #newPlayers == 0 then
        if not InCombatLockdown() then
          self:Hide()
        end
      elseif self.enabled and not self:IsShown() then
        if not InCombatLockdown() then
          self:Show()
        end
      end
    end
  end

  function mainframe:OnTestOrEditmodeEnabled()
    self.ActiveProfile:Show()
  end

  function mainframe:OnTestOrEditmodeDisabled()
    self:RemoveAllPlayersFromSource(BattleGroundEnemies.consts.PlayerSources.FakePlayers)
    self.ActiveProfile:Hide()
  end

  function mainframe:OnTestmodeTick()
    for name, playerButton in pairs(self.Players) do
      if playerButton.PlayerDetails.isFakePlayer then
        local numEvents = #testEvents
        local randomEvent = testEvents[math_random(1, numEvents)]
        randomEvent(self, playerButton)
        playerButton:UNIT_HEALTH()

        playerButton:DispatchEvent("OnTestmodeTick")
      end
    end
  end

  function mainframe:OnEditmodeEnabled()
    for name, playerButton in pairs(self.Players) do
      if playerButton.PlayerDetails.isFakePlayer then
        local numEvents = #testEvents
        for i = 1, numEvents do
          local event = testEvents[i]
          event(self, playerButton)
        end
        playerButton:UNIT_HEALTH()
      end
    end
    self:OnTestOrEditmodeEnabled()
  end

  function mainframe:OnEditmodeDisabled()
    self:OnTestOrEditmodeDisabled()
  end

  function mainframe:OnTestmodeEnabled()
    for playerName, playerButton in pairs(self.Players) do
      playerButton:DispatchEvent("OnTestmodeEnabled")
    end
    self.ActiveProfile:Show()

    if self.CurrentPlayerOrder[1] then
      BattleGroundEnemies:HandleTargetChanged(self.CurrentPlayerOrder[1])
    end
    if self.CurrentPlayerOrder[2] then
      BattleGroundEnemies:HandleFocusChanged(self.CurrentPlayerOrder[2])
    end
    self:OnTestOrEditmodeEnabled()
  end

  function mainframe:OnTestmodeDisabled()
    for playerName, playerButton in pairs(self.Players) do
      playerButton:DispatchEvent("OnTestmodeDisabled")
    end
    self:OnTestOrEditmodeDisabled()
  end

  function mainframe:Enable()
    self:Debug("Enable called")
    if InCombatLockdown() then
      return BattleGroundEnemies:QueueForUpdateAfterCombat(mainframe, "CheckEnableState")
    end

    if BattleGroundEnemies:IsTestmodeOrEditmodeActive() then
    else
      if self.PlayerType == BattleGroundEnemies.consts.PlayerTypes.Enemies then
        self:Debug("Registered enemy events")
        self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        self:RegisterEvent("UNIT_NAME_UPDATE")
        if HasSpeccs then
          self:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS")
        end
      end

      BattleGroundEnemies:CheckForArenaEnemies()
    end
    self.enabled = true
    -- Don't show an empty frame (e.g. after /reload mid-game with no scoreboard data)
    if (self.NumPlayers or 0) > 0 then
      self:Show()
    end
  end

  function mainframe:Disable()
    self:Debug("Disable called")

    if InCombatLockdown() then
      return BattleGroundEnemies:QueueForUpdateAfterCombat(mainframe, "CheckEnableState")
    end
    self:UnregisterAllEvents()

    self.enabled = false
    self:Hide()
  end

  function mainframe:NoActivePlayercountProfile()
    self.playerCountConfig = false
    self:Disable()
  end

  function mainframe:ApplyPlayerCountProfileSettings()
    if InCombatLockdown() then
      return BattleGroundEnemies:QueueForUpdateAfterCombat(self, "ApplyPlayerCountProfileSettings")
    end

    local conf = self.playerCountConfig
    if not conf then
      return
    end

    self:SetPlayerCountJustifyV(conf.BarVerticalGrowdirection)

    self.ActiveProfile:ApplyFontStringSettings(BattleGroundEnemies.db.profile.PlayerCount.Text)

    self.ActiveProfile:SetText(
      L[self.PlayerType]
        .. ": "
        .. BattleGroundEnemies:GetPlayerCountConfigNameLocalized(
          self.playerCountConfig,
          self.playerTypeConfig.CustomPlayerCountConfigsEnabled
        )
    )

    self:SortPlayers(true) --force repositioning

    self:UpdatePlayerCountText()
    self:CheckEnableState()
  end

  function mainframe:SelectPlayerCountProfile(forceUpdate)
    self.playerTypeConfig = BattleGroundEnemies.db.profile[self.PlayerType]
    local maxNumPlayers

    -- In test/edit mode, always use NumPlayers, not instance info
    if BattleGroundEnemies:IsTestmodeOrEditmodeActive() then
      maxNumPlayers = self.NumPlayers or 10
    elseif BattleGroundEnemies.states.real.isInArena then
      -- Arena: same map can host different brackets (2v2, 3v3), so GetInstanceInfo()
      -- returns the map capacity, not the bracket size. Use actual player count instead.
      maxNumPlayers = math_max(self.RealPlayerCount or 0, self.NumPlayers or 0)
    else
      -- BG: use instance max players for profile selection so the frame stays visible
      -- when enemies are still loading (e.g., Training Grounds).
      local _, _, _, _, instanceMaxPlayers = GetInstanceInfo()
      if instanceMaxPlayers and instanceMaxPlayers > 0 then
        maxNumPlayers = instanceMaxPlayers
      else
        maxNumPlayers = math_max(self.RealPlayerCount or 0, self.NumPlayers or 0)
      end
    end
    self:Debug("SelectPlayerCountProfile", maxNumPlayers)
    if not maxNumPlayers then
      return
    end
    if maxNumPlayers == 0 then
      return self:NoActivePlayercountProfile()
    end

    if maxNumPlayers > 40 then
      return self:NoActivePlayercountProfile()
    end

    local playerCountConfigs
    if self.playerTypeConfig.CustomPlayerCountConfigsEnabled then
      playerCountConfigs = self.playerTypeConfig.customPlayerCountConfigs
    else
      playerCountConfigs = self.playerTypeConfig.playerCountConfigs
    end

    local foundProfilesForPlayerCount = {}
    for i = 1, #playerCountConfigs do
      local playerCountProfile = playerCountConfigs[i]
      local minPlayerCount = playerCountProfile.minPlayerCount
      local maxPlayerCount = playerCountProfile.maxPlayerCount

      if maxNumPlayers <= maxPlayerCount and maxNumPlayers >= minPlayerCount then
        table.insert(foundProfilesForPlayerCount, playerCountProfile)
      end
    end

    if #foundProfilesForPlayerCount == 0 then
      self:NoActivePlayercountProfile()
      return
      --return BattleGroundEnemies:Information("Can't find a profile for the current player count of " .. self.NumPlayers .." players for "..self.PlayerType.." please check the settings")
    end

    if #foundProfilesForPlayerCount > 1 then
      local overlappingProfilesString = ""
      for i = 1, #foundProfilesForPlayerCount do
        local overlappingIndexShownName =
          BattleGroundEnemies:GetPlayerCountConfigNameLocalized(foundProfilesForPlayerCount[i])
        overlappingProfilesString = overlappingProfilesString .. "and " .. overlappingIndexShownName
      end
      self:NoActivePlayercountProfile()
      BattleGroundEnemies:Information(
        "Found multiple player count profiles fitting the current player count for "
          .. self.PlayerType
          .. " please check your settings and make sure they don't overlap"
      )
      BattleGroundEnemies:Information("The following profiles are overlapping: " .. overlappingProfilesString)

      return
    end

    if forceUpdate or foundProfilesForPlayerCount[1] ~= self.playerCountConfig then
      self.playerCountConfig = foundProfilesForPlayerCount[1]
      self:ApplyPlayerCountProfileSettings()
    end
  end

  function mainframe:CheckEnableState()
    self:Debug("CheckEnableState")
    if not BattleGroundEnemies.enabled then
      return self:Disable()
    end
    if self.playerTypeConfig.Enabled and self.playerCountConfig and self.playerCountConfig.Enabled then
      self:Enable()
    else
      self:Disable()
    end
  end

  function mainframe:SetRealPlayerCount(realCount)
    self:Debug("SetRealPlayerCount", realCount)
    local oldCount = self.RealPlayerCount
    self.RealPlayerCount = realCount
    if not oldCount or oldCount ~= realCount then
      self:SelectPlayerCountProfile()
    end
    self:UpdatePlayerCountText()
  end

  function mainframe:SetPlayerCount(count)
    local oldCount = self.NumPlayers
    self.NumPlayers = count
    if not oldCount or oldCount ~= count then
      self:SelectPlayerCountProfile()
    end
    self:UpdatePlayerCountText()
  end

  function mainframe:UpdatePlayerCountText()
    self.PlayerCount:ApplyFontStringSettings(BattleGroundEnemies.db.profile.PlayerCount.Text)
    local maxNumPlayers = math_max(self.RealPlayerCount or 0, self.NumPlayers or 0)

    local isEnemy = self.PlayerType == BattleGroundEnemies.consts.PlayerTypes.Enemies
    self:Debug("UpdatePlayerCountText", maxNumPlayers, isEnemy)

    BattleGroundEnemies:SetAllyFaction(
      BattleGroundEnemies.AllyFaction or (BattleGroundEnemies.UserFaction == "Horde" and 1 or 0)
    )

    if self.playerCountConfig and self.playerCountConfig.PlayerCount.Enabled then
      self.PlayerCount:Show()
      self.PlayerCount:SetText(
        format(
          isEnemy == (BattleGroundEnemies.EnemyFaction == 0) and PLAYER_COUNT_HORDE or PLAYER_COUNT_ALLIANCE,
          maxNumPlayers
        )
      )
    else
      self.PlayerCount:Hide()
    end
  end

  function mainframe:GetPlayerbuttonByUnitID(unitID, playerType)
    -- Delegate to the robust GUID/PID matcher in Main.lua
    return BattleGroundEnemies:GetPlayerbuttonByUnitID(unitID, playerType)
  end

  function mainframe:GetRandomPlayer()
    local t = {}
    for playerName, playerButton in pairs(self.Players) do
      table.insert(t, playerButton)
    end
    local numPlayers = #t
    if numPlayers > 0 then
      return t[math_random(1, numPlayers)]
    end
  end

  function mainframe:SetPlayerCountJustifyV(direction)
    if direction == "downwards" then
      self.PlayerCount:SetJustifyV("BOTTOM")
    else
      self.PlayerCount:SetJustifyV("TOP")
    end
  end

  function mainframe:SetupButtonForNewPlayer(playerDetails)
    local playerButton = self.InactivePlayerButtons[#self.InactivePlayerButtons]
    if playerButton then --recycle a previous used button
      table_remove(self.InactivePlayerButtons, #self.InactivePlayerButtons)
      --Cleanup previous shown stuff of another player
      playerButton.MyTarget:Hide() --reset possible shown target indicator frame
      playerButton.MyFocus:Hide() --reset possible shown target indicator frame

      for moduleName, moduleFrameOnButton in pairs(BattleGroundEnemies.ButtonModules) do
        if playerButton[moduleName] and playerButton[moduleName].Reset then
          playerButton[moduleName]:Reset()
        end
      end

      -- Reset isDead before DeleteActiveUnitID so the health bar resets to
      -- full (value 1) instead of empty (value 0) for the new player.
      playerButton.isDead = false

      if playerButton.UnitIDs then
        wipe(playerButton.UnitIDs.TargetedByEnemy)
        playerButton:UpdateTargetIndicators()
        playerButton:DeleteActiveUnitID()
      end
    else --no recycleable buttons remaining => create a new one
      self.buttonCounter = (self.buttonCounter or 0) + 1
      playerButton = BattleGroundEnemies:CreatePlayerButton(self, self.buttonCounter)
    end

    playerButton.UnitIDs = { TargetedByEnemy = {}, HasAllyUnitID = false }
    playerButton.unitID = nil
    playerButton.unit = nil
    playerButton.RaidTargetIconIndex = nil

    playerButton.powerBarUsedHeight = 0

    playerButton.PlayerDetails = playerDetails
    playerButton:PlayerDetailsChanged()

    self.Target = nil

    local TimeSinceLastOnUpdate = 0
    local UpdatePeroid = 0.1 --update every 0.1 seconds

    -- Initial range state: enemies start out-of-range, allies start in-range.
    -- Note: UpdateRange may no-op if self.config is nil (not yet set by ApplyButtonSettings).
    -- SetAlpha(0.55) is a safety net so enemies don't appear full-brightness before config loads.
    if playerButton.PlayerIsEnemy then
      playerButton:SetAlpha(0.55)
      playerButton:UpdateRange(false)
      if playerButton.PlayerDetails.isFakePlayer then
        playerButton:SetScript("OnUpdate", nil)
      else
        playerButton:SetScript("OnUpdate", function(self, elapsed)
          TimeSinceLastOnUpdate = TimeSinceLastOnUpdate + elapsed
          if TimeSinceLastOnUpdate > UpdatePeroid then
            if BattleGroundEnemies.states.userIsAlive and not BattleGroundEnemies.betweenRounds then
              playerButton:UpdateAll()
            end
            TimeSinceLastOnUpdate = 0
          end
        end)
      end
    else
      playerButton:UpdateRange(true)
      if playerButton.PlayerDetails.isFakePlayer then
        playerButton:SetScript("OnUpdate", nil)
      else
        playerButton:SetScript("OnUpdate", function(self, elapsed)
          TimeSinceLastOnUpdate = TimeSinceLastOnUpdate + elapsed
          if TimeSinceLastOnUpdate > UpdatePeroid then
            if BattleGroundEnemies.states.userIsAlive and not BattleGroundEnemies.betweenRounds then
              -- Call UpdateAll() for allies to ensure UNIT_HEALTH gets called
              -- (UpdateAll handles health, power, range, guild, target updates)
              playerButton:UpdateAll()
            end
            TimeSinceLastOnUpdate = 0
          end
        end)
      end
    end

    playerButton:Show()

    self.Players[playerButton.PlayerDetails.PlayerName] = playerButton

    return playerButton
  end

  function mainframe:RemovePlayer(playerButton)
    if playerButton == BattleGroundEnemies.UserButton then
      return
    end -- dont remove the Player itself

    local targetEnemyButton = playerButton.Target
    if targetEnemyButton then -- if that no longer exiting ally targeted something update the button of its target
      playerButton:IsNoLongerTarging(targetEnemyButton)
    end

    if InCombatLockdown() then
      playerButton.pendingHide = true
      BattleGroundEnemies:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
      playerButton:Hide()
    end

    table_insert(self.InactivePlayerButtons, playerButton)
    self.Players[playerButton.PlayerDetails.PlayerName] = nil
  end

  function mainframe:RemoveAllPlayers()
    for playerName, playerButton in pairs(self.Players) do
      self:RemovePlayer(playerButton)
    end
    self:SortPlayers()
  end

  function mainframe:GetPrevioiusPlayer()
    local currentTarget = BattleGroundEnemies.currentTarget

    local currentTargetIndex
    for i = 1, #self.CurrentPlayerOrder do
      local player = self.CurrentPlayerOrder[i]
      if player == currentTarget then
        currentTargetIndex = i
        break
      end
    end
    local newTargetIndex = (currentTargetIndex or 0) - 1
    if newTargetIndex < 1 then
      newTargetIndex = #self.CurrentPlayerOrder
    end
    return newTargetIndex, self.CurrentPlayerOrder[newTargetIndex]
  end

  function mainframe:GetNextPlayer()
    local currentTarget = BattleGroundEnemies.currentTarget

    local currentTargetIndex
    for i = 1, #self.CurrentPlayerOrder do
      local player = self.CurrentPlayerOrder[i]
      if player == currentTarget then
        currentTargetIndex = i
        break
      end
    end
    local newTargetIndex = (currentTargetIndex or 0) + 1
    if newTargetIndex > #self.CurrentPlayerOrder then
      newTargetIndex = 0
    end
    return newTargetIndex, self.CurrentPlayerOrder[newTargetIndex]
  end

  function mainframe:SetUpBindings()
    --self:Debug("SetUpBindings", self.PlayerType)
    local maxPlayers = #self.CurrentPlayerOrder
    self:SetAttribute("maxUnits", maxPlayers)
    for j = 1, #self.CurrentPlayerOrder do
      self:SetAttribute("playerName" .. j, self.CurrentPlayerOrder[j].PlayerDetails.PlayerName)
    end

    self:SetAttribute("playerIndex", 1)

    if BattleGroundEnemies.db.profile.EnableMouseWheelPlayerTargeting then
      --SecureHandlerEnterLeaveTemplate ads _onenter and _onleave functionality
      mainframe:EnableMouseWheel(true)
      mainframe:SetAttribute(
        "_onenter",
        [[
				self:SetBindingClick(true, "MOUSEWHEELUP",self:GetName(), "Button4")
				self:SetBindingClick(true, "MOUSEWHEELDOWN",self:GetName(), "Button5")
			]]
      )
      -- onleave, clear override binding
      mainframe:SetAttribute(
        "_onleave",
        [[
				self:ClearBindings()
			]]
      )
    else
      mainframe:EnableMouseWheel(false)
      mainframe:SetAttribute("_onenter", nil)
      -- onleave, clear override binding
      mainframe:SetAttribute("_onleave", nil)
    end

    --button:SetAttribute("type1", "macro")
  end

  function mainframe:ButtonPositioning()
    self:Debug("ButtonPositioning")
    local orderedPlayers = self.CurrentPlayerOrder

    local config = self.playerCountConfig
    if not config then
      return
    end
    local columns = config.BarColumns

    local barHeight = config.BarHeight
    local barWidth = config.BarWidth

    local verticalSpacing = config.BarVerticalSpacing
    local horizontalSpacing = config.BarHorizontalSpacing

    local growDownwards = (config.BarVerticalGrowdirection == "downwards")
    local growRightwards = (config.BarHorizontalGrowdirection == "rightwards")

    local playerCount = #orderedPlayers

    local rowsPerColumn = math.ceil(playerCount / columns)

    local offsetX, offsetY

    local point, offsetDirectionX, offsetDirectionY =
      Data.Helpers.getContainerAnchorPointForConfig(growRightwards, growDownwards)

    self:SetScale(config.Framescale)
    self:ClearAllPoints()

    local scale = self:GetEffectiveScale()

    self:SetPoint(point, UIParent, "BOTTOMLEFT", config.Position_X / scale, config.Position_Y / scale)

    local column = 1
    local row = 1

    for i = 1, playerCount do
      local playerButton = orderedPlayers[i]
      if playerButton then --should never be nil
        playerButton.position = i
        if column > 1 then
          offsetX = (column - 1) * (barWidth + horizontalSpacing) * offsetDirectionX
        else
          offsetX = 0
        end

        if row > 1 then
          offsetY = (row - 1) * (barHeight + verticalSpacing) * offsetDirectionY
        else
          offsetY = 0
        end

        playerButton:ClearAllPoints()
        playerButton:SetPoint(point, self, point, offsetX, offsetY)

        playerButton:ApplyButtonSettings()

        if row < rowsPerColumn then
          row = row + 1
        else
          column = column + 1
          row = 1
        end
      end
    end
    if playerCount > 0 then
      local lastButton = orderedPlayers[playerCount]
      local firstButton = orderedPlayers[1]

      local topButton
      local bottomButton

      if growDownwards then
        topButton = firstButton
        bottomButton = lastButton
      else
        topButton = lastButton
        bottomButton = firstButton
      end
      self:SetSize(barWidth, topButton:GetTop() - bottomButton:GetBottom())
    end
  end

  function mainframe:BeforePlayerUpdate()
    wipe(self.NewPlayersDetails)
  end

  function mainframe:CreateOrUpdatePlayerDetails(name, race, classToken, specName, realmName, additionalData)
    local spec = false
    if specName and specName ~= "" then
      spec = specName
    end
    local specData
    if classToken and spec then
      local t = Data.Classes[classToken]
      if t then
        specData = t[spec]
      end
    end

    local playerDetails = {
      PlayerName = name,
      PlayerClass = string.upper(classToken), --apparently it can happen that we get a lowercase "druid" from GetBattlefieldScore() in TBCC, IsTBCC
      PlayerClassColor = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classToken],
      PlayerRace = race or "Unknown", -- store localized race name directly (merc-mode safe)
      PlayerSpecName = spec, --set to false since we use Mixin() and Mixin doesnt mixin nil values and therefore we dont overwrite values with nil
      PlayerRole = (specData and specData.roleID) -- 1st priority: spec-based role
        or (additionalData and additionalData.groupRole) -- 2nd priority: group role (allies only)
        or (additionalData and additionalData.roleAssigned), -- 3rd priority: scoreboard role
      PlayerLevel = false,
      isFakePlayer = false, --to set a base value, might be overwritten by mixin
      PlayerArenaUnitID = nil, --to set a base value, might be overwritten by mixin
      GuildName = nil, -- cached from unit info
      GuildRealm = nil, -- cached from unit info
      realmName = realmName, -- from scoreboard
    }
    if additionalData then
      Mixin(playerDetails, additionalData)
    end

    -- Resolve gender from GUID (available in lobby, tainted in combat, lost on reload)
    if playerDetails.guid then
      local _, _, _, _, genderID = GetPlayerInfoByGUID(playerDetails.guid)
      if genderID then
        playerDetails.gender = genderID
      end
    end
    -- Preserve gender from previous details if we couldn't resolve it this time
    local existingButton = self.Players[name]
    if
      not playerDetails.gender
      and existingButton
      and existingButton.PlayerDetails
      and existingButton.PlayerDetails.gender
    then
      playerDetails.gender = existingButton.PlayerDetails.gender
    end

    -- Populate PlayerGUIDs for GUID fast-path lookup
    if playerDetails.guid then
      BattleGroundEnemies.PlayerGUIDs = BattleGroundEnemies.PlayerGUIDs or {}
      BattleGroundEnemies.PlayerGUIDs[playerDetails.guid] = { name = name }
    end

    -- self:Debug("CreateOrUpdatePlayerDetails", name, race, classToken, specName, realmName, additionalData)
    local playerButton = self.Players[name]
    if playerButton then --already existing
      local currentDetails = playerButton.PlayerDetails
      local detailsChanged = false

      for k, v in pairs(playerDetails) do
        if not (issecretvalue and issecretvalue(v)) then
          if v ~= currentDetails[k] then
            detailsChanged = true
            break
          end
        end
      end

      if not detailsChanged then
        for k, v in pairs(currentDetails) do
          if not (issecretvalue and issecretvalue(v)) then
            if v ~= playerDetails[k] then
              detailsChanged = true
              break
            end
          end
        end
      end
      playerButton.PlayerDetails = playerDetails

      if detailsChanged then
        playerButton:PlayerDetailsChanged()
      end

      playerButton.status = 1 --1 means found, already existing
      playerDetails = playerButton.PlayerDetails
    else
      table.insert(self.NewPlayersDetails, playerDetails)
    end
  end

  function mainframe:CreateOrRemovePlayerButtons()
    local inCombat = InCombatLockdown()
    local existingPlayersCount = 0
    for playerName, playerButton in pairs(self.Players) do
      if playerButton.status == 2 then --no longer existing
        if inCombat then
          return BattleGroundEnemies:QueueForUpdateAfterCombat(self, "AfterPlayerSourceUpdate")
        else
          self:RemovePlayer(playerButton)
        end
      else -- == 1 -- set to 2 for the next comparison
        playerButton.status = 2
        existingPlayersCount = existingPlayersCount + 1
      end
    end

    for i = 1, #self.NewPlayersDetails do
      local playerDetails = self.NewPlayersDetails[i]
      if inCombat then
        return BattleGroundEnemies:QueueForUpdateAfterCombat(self, "AfterPlayerSourceUpdate")
      else
        local playerButton = self:SetupButtonForNewPlayer(playerDetails)
        playerButton.status = 2
      end
    end
    self:SortPlayers(false)
  end

  do
    local BlizzardsSortOrder = {}
    for i = 1, #CLASS_SORT_ORDER do -- Constants.lua
      BlizzardsSortOrder[CLASS_SORT_ORDER[i]] = i --key = ENGLISH CLASS NAME, value = number
    end

    local function PlayerSortingByRoleClassName(playerA, playerB) -- a and b are playerButtons
      local detailsPlayerA = playerA.PlayerDetails
      local detailsPlayerB = playerB.PlayerDetails

      --BattleGroundEnemies.db.profile.RoleSortingOrder is somethng like "HEALER_TANK_DAMAGER"

      local roleT = { strsplit("_", BattleGroundEnemies.db.profile.RoleSortingOrder) }
      local reverseRoleT = {}

      for k, v in pairs(roleT) do
        reverseRoleT[v] = k
      end

      local roleSortingNumerPlayerA = reverseRoleT[detailsPlayerA.PlayerRole]
      local roleSortingNumerPlayerB = reverseRoleT[detailsPlayerB.PlayerRole]

      if roleSortingNumerPlayerA and roleSortingNumerPlayerB then
        if roleSortingNumerPlayerA == roleSortingNumerPlayerB then
          if BlizzardsSortOrder[detailsPlayerA.PlayerClass] == BlizzardsSortOrder[detailsPlayerB.PlayerClass] then
            if detailsPlayerA.PlayerName < detailsPlayerB.PlayerName then
              return true
            end
          elseif BlizzardsSortOrder[detailsPlayerA.PlayerClass] < BlizzardsSortOrder[detailsPlayerB.PlayerClass] then
            return true
          end
        elseif roleSortingNumerPlayerA < roleSortingNumerPlayerB then
          return true
        end
      else
        if BlizzardsSortOrder[detailsPlayerA.PlayerClass] == BlizzardsSortOrder[detailsPlayerB.PlayerClass] then
          if detailsPlayerA.PlayerName < detailsPlayerB.PlayerName then
            return true
          end
        elseif BlizzardsSortOrder[detailsPlayerA.PlayerClass] < BlizzardsSortOrder[detailsPlayerB.PlayerClass] then
          return true
        end
      end
    end

    local function PlayerSortingByArenaUnitID(playerA, playerB) -- a and b are playerButtons
      if not (playerA and playerB) then
        return
      end
      local detailsPlayerA = playerA.PlayerDetails
      local detailsPlayerB = playerB.PlayerDetails
      if not (detailsPlayerA.PlayerArenaUnitID and detailsPlayerB.PlayerArenaUnitID) then
        return
      end
      if detailsPlayerA.PlayerArenaUnitID <= detailsPlayerB.PlayerArenaUnitID then
        return true
      end
    end

    local function CRFSort_Group_(playerA, playerB) -- this is basically a adapted CRFSort_Group to make the sorting in arena
      if not (playerA and playerB) then
        return
      end
      local detailsPlayerA = playerA.PlayerDetails
      local detailsPlayerB = playerB.PlayerDetails
      if not (detailsPlayerA.unitID and detailsPlayerB.unitID) then
        if detailsPlayerA.PlayerName < detailsPlayerB.PlayerName then
          return true
        end --for enabling testmode in arena since fake players don't have unitid
      end
      if detailsPlayerA.unitID == "player" then
        return true
      elseif detailsPlayerB.unitID == "player" then
        return false
      else
        return detailsPlayerA.unitID < detailsPlayerB.unitID --String compare is OK since we don't go above 1 digit for party.
      end
    end

    function mainframe:SortPlayers(forceRepositioning)
      --self:Debug("SortPlayers", self.PlayerType)
      local newPlayerOrder = {}
      for playerName, playerButton in pairs(self.Players) do
        -- self:Debug(playerName)
        table.insert(newPlayerOrder, playerButton)
      end
      --[[
			self:Debug("before sorting")
			for i = 1, #newPlayerOrder do
				self:Debug(i, newPlayerOrder[i].PlayerDetails.PlayerName)
			end

 ]]

      if BattleGroundEnemies.states.real.isInArena then
        if self.PlayerType == BattleGroundEnemies.consts.PlayerTypes.Enemies then
          local usePlayerSortingByArenaUnitID = true
          for i = 1, #newPlayerOrder do
            if not newPlayerOrder[i].PlayerDetails.PlayerArenaUnitID then
              usePlayerSortingByArenaUnitID = false
              break
            end
          end
          if usePlayerSortingByArenaUnitID then
            -- self:Debug("usePlayerSortingByArenaUnitID", self.PlayerType)
            table.sort(newPlayerOrder, PlayerSortingByArenaUnitID)
          else
            -- self:Debug("dont usePlayerSortingByArenaUnitID", self.PlayerType)
            table.sort(newPlayerOrder, PlayerSortingByRoleClassName)
          end
        else
          local usePlayerSortingByUnitID = true -- fake players don't have unitid
          for i = 1, #newPlayerOrder do
            if not newPlayerOrder[i].PlayerDetails.unitID then
              usePlayerSortingByUnitID = false
              break
            end
          end
          if usePlayerSortingByUnitID then
            table.sort(newPlayerOrder, CRFSort_Group_)
          else
            table.sort(newPlayerOrder, PlayerSortingByRoleClassName)
          end
        end
      else
        table.sort(newPlayerOrder, PlayerSortingByRoleClassName)
      end

      local orderChanged = false
      for i = 1, math_max(#newPlayerOrder, #self.CurrentPlayerOrder) do --players can leave or join so #self.CurrentPlayerOrder can be unequal to #newPlayerOrder
        if newPlayerOrder[i] ~= self.CurrentPlayerOrder[i] then
          orderChanged = true
          break
        end
      end

      --[[ 			self:Debug("after sorting")
			for i = 1, #newPlayerOrder do
				self:Debug(i, newPlayerOrder[i].PlayerDetails.PlayerName)
			end ]]

      if orderChanged or forceRepositioning then
        local inCombat = InCombatLockdown()
        if inCombat then
          return BattleGroundEnemies:QueueForUpdateAfterCombat(self, "AfterPlayerSourceUpdate")
        end
        self.CurrentPlayerOrder = newPlayerOrder
        self:ButtonPositioning()
        self:SetUpBindings()
      end
    end
  end

  mainframe:SetClampedToScreen(true)
  mainframe:SetMovable(true)
  mainframe:SetUserPlaced(true)
  mainframe:SetResizable(true)
  mainframe:SetToplevel(true)

  mainframe.PlayerCount = BattleGroundEnemies.MyCreateFontString(mainframe)
  mainframe.PlayerCount:SetPoint("BOTTOMLEFT", mainframe, "TOPLEFT")
  mainframe.PlayerCount:SetPoint("BOTTOMRIGHT", mainframe, "TOPRIGHT")
  mainframe.PlayerCount:SetHeight(30)
  mainframe.PlayerCount:SetJustifyH("LEFT")
  mainframe.PlayerCount:SetJustifyV("MIDDLE")

  mainframe.ActiveProfile = BattleGroundEnemies.MyCreateFontString(mainframe)
  mainframe.ActiveProfile:SetPoint("BOTTOMLEFT", mainframe.PlayerCount, "TOPLEFT")
  mainframe.ActiveProfile:SetPoint("BOTTOMRIGHT", mainframe.PlayerCount, "TOPRIGHT")
  mainframe.ActiveProfile:SetHeight(30)
  mainframe.ActiveProfile:SetJustifyH("LEFT")
  mainframe.ActiveProfile:SetJustifyV("MIDDLE")
  mainframe.ActiveProfile:Hide()

  return mainframe
end

---@class BattleGroundEnemies.Allies: MainFrame
BattleGroundEnemies.Allies = CreateMainFrame(BattleGroundEnemies.consts.PlayerTypes.Allies)
BattleGroundEnemies.Allies.GUIDToAllyname = {}

-- Track when enemies (nameplates/arena) target allies for ally target indicators
function BattleGroundEnemies.Allies:AddNameplateTarget(allyButton, enemyButton)
  if not allyButton or not allyButton.UnitIDs or not enemyButton then
    return
  end

  self.NameplateTargetMap = self.NameplateTargetMap or {}
  self.NameplateTargetMap[allyButton] = self.NameplateTargetMap[allyButton] or {}
  self.NameplateTargetMap[allyButton][enemyButton] = true

  -- Add to TargetedByEnemy using enemy button as key (same as enemy→enemy targeting)
  allyButton.UnitIDs.TargetedByEnemy[enemyButton] = true
  allyButton:DispatchEvent("UpdateTargetIndicators")
end

function BattleGroundEnemies.Allies:RemoveNameplateTarget(allyButton, enemyButton)
  if not self.NameplateTargetMap or not self.NameplateTargetMap[allyButton] or not enemyButton then
    return
  end

  self.NameplateTargetMap[allyButton][enemyButton] = nil

  if allyButton.UnitIDs and allyButton.UnitIDs.TargetedByEnemy then
    allyButton.UnitIDs.TargetedByEnemy[enemyButton] = nil
    allyButton:DispatchEvent("UpdateTargetIndicators")
  end
end

function BattleGroundEnemies.Allies:AddArenaTarget(allyButton, enemyButton)
  if not allyButton or not allyButton.UnitIDs or not enemyButton then
    return
  end

  self.ArenaTargetMap = self.ArenaTargetMap or {}
  self.ArenaTargetMap[allyButton] = self.ArenaTargetMap[allyButton] or {}
  self.ArenaTargetMap[allyButton][enemyButton] = true

  allyButton.UnitIDs.TargetedByEnemy[enemyButton] = true
  allyButton:DispatchEvent("UpdateTargetIndicators")
end

function BattleGroundEnemies.Allies:RemoveArenaTarget(allyButton, enemyButton)
  if not self.ArenaTargetMap or not self.ArenaTargetMap[allyButton] or not enemyButton then
    return
  end

  self.ArenaTargetMap[allyButton][enemyButton] = nil

  if allyButton.UnitIDs and allyButton.UnitIDs.TargetedByEnemy then
    allyButton.UnitIDs.TargetedByEnemy[enemyButton] = nil
    allyButton:DispatchEvent("UpdateTargetIndicators")
  end
end

---@class BattleGroundEnemies.Enemies: MainFrame
BattleGroundEnemies.Enemies = CreateMainFrame(BattleGroundEnemies.consts.PlayerTypes.Enemies)
BattleGroundEnemies.Enemies.Counter = {}

function BattleGroundEnemies.Allies:GroupInSpecT_Update(event, GUID, unitID, info)
  if not GUID or type(GUID) ~= "string" or not info.class then
    return
  end

  BattleGroundEnemies.specCache[GUID] = info.spec_name_localized

  BattleGroundEnemies:GROUP_ROSTER_UPDATE()
end

function BattleGroundEnemies.Allies:AddGroupMember(name, isLeader, isAssistant, classToken, unitID)
  local raceName, raceFile, raceID = UnitRace(unitID)
  local GUID = UnitGUID(unitID)

  if not GUID or type(GUID) ~= "string" or (issecretvalue and issecretvalue(GUID)) then
    return
  end

  if name and raceName and classToken then
    local ok, specName = pcall(function()
      return BattleGroundEnemies.specCache[GUID]
    end)
    if not ok then
      specName = nil
    end
    local groupRole = UnitGroupRolesAssigned(unitID) -- Get assigned role from group

    self:AddPlayerToSource(BattleGroundEnemies.consts.PlayerSources.GroupMembers, {
      name = name,
      raceName = raceName,
      classToken = classToken,
      specName = specName,
      additionalData = {
        isGroupLeader = isLeader,
        isGroupAssistant = isAssistant,
        GUID = GUID,
        unitID = unitID,
        groupRole = groupRole, -- Store group role for fallback
      },
    })
  end

  self.GUIDToAllyname[GUID] = name

  if isLeader then
    self.groupLeader = name
  end
  if isAssistant then
    table_insert(self.assistants, name)
  end
end

function BattleGroundEnemies.Allies:UpdateAllUnitIDs()
  --it happens that numGroupMembers is higher than the value of the maximal players for that battleground, for example 15 in a 10 man bg, thats why we wipe AllyUnitIDToAllyDetails
  for allyName, allyButton in pairs(self.Players) do
    if allyButton then
      local unitID
      local targetUnitID
      if allyButton.PlayerDetails.PlayerName ~= BattleGroundEnemies.UserDetails.PlayerName then
        local unit = allyButton.PlayerDetails.unitID
        -- Only process if unit exists - skip this ally if unitID is missing
        if unit then
          unitID = unit
          targetUnitID = unitID .. "target"

          --self.unitID already gets assigned for allies before, info from GROUP_ROSTER_UPDATE

          if allyButton.unit ~= unitID then
            --ally has a new unitID now
            --self:Debug("player", groupMember.PlayerName, "has a new unit and targeted something")

            local targetButton = allyButton.Target
            if targetButton then
              --reset the TargetedByEnemy
              targetButton:IsNoLongerTarging(targetButton)
              targetButton:IsNowTargeting(targetButton)
            end

            if InCombatLockdown() then --if we are in combat we go get to set the stuff below later since GROUP_ROSTER_UPDATE also has a combat check and will get called after combat
              -- Queue the SetAttribute for after combat, but don't return - continue processing remaining allies
              BattleGroundEnemies:QueueForUpdateAfterCombat(
                BattleGroundEnemies[allyButton.PlayerType],
                "UpdateAllUnitIDs"
              )
            else
              allyButton.unit = unitID
              allyButton:SetAttribute("unit", unitID)
              BattleGroundEnemies.Allies:SortPlayers()
            end
          end

          allyButton:UpdateUnitID(unitID, targetUnitID)
          -- Request the trinket/CC-break spell so ARENA_CROWD_CONTROL_SPELL_UPDATE fires.
          if C_PvP.RequestCrowdControlSpell and unitID then
            C_PvP.RequestCrowdControlSpell(unitID)
          end
          -- Also check the cache: ARENA_CROWD_CONTROL_SPELL_UPDATE may have already fired
          -- for this unit before the button was ready (race condition, common for "player").
          local cached = BattleGroundEnemies._ccSpellCache and BattleGroundEnemies._ccSpellCache[unitID]
          if cached and allyButton.Trinket then
            allyButton.Trinket:DisplayTrinket(cached.spellId, cached.itemID)
          end
        end
        -- If unit is nil, we simply skip to the next iteration
      else
        unitID = "player"
        targetUnitID = "target"
        BattleGroundEnemies.UserButton = allyButton

        --self.unitID already gets assigned for allies before, info from GROUP_ROSTER_UPDATE

        if allyButton.unit ~= unitID then
          --ally has a new unitID now
          --self:Debug("player", groupMember.PlayerName, "has a new unit and targeted something")

          local targetButton = allyButton.Target
          if targetButton then
            --reset the TargetedByEnemy
            targetButton:IsNoLongerTarging(targetButton)
            targetButton:IsNowTargeting(targetButton)
          end

          if InCombatLockdown() then --if we are in combat we go get to set the stuff below later since GROUP_ROSTER_UPDATE also has a combat check and will get called after combat
            -- Queue the SetAttribute for after combat, but don't return - continue processing remaining allies
            BattleGroundEnemies:QueueForUpdateAfterCombat(
              BattleGroundEnemies[allyButton.PlayerType],
              "UpdateAllUnitIDs"
            )
          else
            allyButton.unit = unitID
            allyButton:SetAttribute("unit", unitID)
            BattleGroundEnemies.Allies:SortPlayers()
          end
        end

        allyButton:UpdateUnitID(unitID, targetUnitID)
        if C_PvP.RequestCrowdControlSpell and unitID then
          C_PvP.RequestCrowdControlSpell(unitID)
        end
        local cached = BattleGroundEnemies._ccSpellCache and BattleGroundEnemies._ccSpellCache[unitID]
        if cached and allyButton.Trinket then
          allyButton.Trinket:DisplayTrinket(cached.spellId, cached.itemID)
        end
      end
    end
  end
end

function BattleGroundEnemies.Enemies:ChangeName(oldName, newName) --only used in arena when players switch from "arenaX" to a real name
  local playerButton = self.Players[oldName]

  if playerButton then
    playerButton.PlayerDetails.PlayerName = newName
    self:Debug("name changed", oldName, newName)
    playerButton:PlayerDetailsChanged()

    self.Players[newName] = playerButton
    self.Players[oldName] = nil
  end
end

function BattleGroundEnemies.Enemies:CreateArenaEnemies()
  self:Debug("CreateArenaEnemies")
  if not BattleGroundEnemies.states.real.isInArena then
    return
  end

  self:BeforePlayerSourceUpdate(BattleGroundEnemies.consts.PlayerSources.ArenaPlayers)
  for i = 1, 15 do --we can have 15 enemies in the Arena Brawl Packed House
    local unitID = "arena" .. i

    local _, classToken, specName
    if GetArenaOpponentSpec and GetSpecializationInfoByID then --HasSpeccs
      local specID, gender = GetArenaOpponentSpec(i)

      if specID and specID > 0 then
        _, specName, _, _, _, classToken, _ = GetSpecializationInfoByID(specID, gender)
      end
    else
      classToken = select(2, UnitClass(unitID))
    end
    self:Debug("classToken", classToken)
    self:Debug("specName", specName)

    if classToken then
      local playerName
      -- 12.0.0: Arena opponent names are secret values.
      -- We can't use them as table keys, but we CAN pass them to :SetText() (InsecureSecretArguments).
      local secretDisplayName
      local ok, name = pcall(GetUnitName, unitID, true)
      if not ok then
        ok, name = pcall(GetUnitName, unitID, false)
      end
      if not ok then
        -- Both calls failed — name is an error string, not a player name
        name = nil
      elseif type(name) ~= "nil" and issecretvalue and issecretvalue(name) then
        -- Store secret name for display only — can't use as table key
        secretDisplayName = name
        name = nil
      end
      if name and name ~= UNKNOWN then
        -- player has a real name, check if he is already shown as arenaX
        self:ChangeName(unitID, name)
        playerName = name
      end

      local raceName = UnitRace(unitID)
      self:AddPlayerToSource(BattleGroundEnemies.consts.PlayerSources.ArenaPlayers, {
        name = playerName,
        raceName = raceName,
        classToken = classToken,
        specName = specName,
        additionalData = { PlayerArenaUnitID = unitID, SecretDisplayName = secretDisplayName },
      })
    end
  end

  self:AfterPlayerSourceUpdate()

  for playerName, playerButton in pairs(self.Players) do
    local playerDetails = playerButton.PlayerDetails
    if playerDetails.PlayerArenaUnitID then
      playerButton:UpdateAll(playerDetails.PlayerArenaUnitID)
    end
  end
end

BattleGroundEnemies.Enemies.ARENA_PREP_OPPONENT_SPECIALIZATIONS = BattleGroundEnemies.Enemies.CreateArenaEnemies -- for Prepframe, not available in TBC

function BattleGroundEnemies.Enemies:UNIT_NAME_UPDATE(unitID)
  self:Debug("UNIT_NAME_UPDATE", unitID)
  BattleGroundEnemies:CheckForArenaEnemies()
end

function BattleGroundEnemies.Enemies:NAME_PLATE_UNIT_ADDED(unitID)
  -- Only process enemy nameplates — friendly nameplates must be ignored
  -- or they can PID-match to enemy buttons and cause false in-range.
  if not BattleGroundEnemies.IsEnemyUnit(unitID) then
    return
  end
  -- Clear stale sticky cache for this nameplate (may have been recycled from a different enemy)
  BattleGroundEnemies:InvalidateStickyPID(unitID)
  BattleGroundEnemies:InvalidateStickyPID(unitID .. "target")

  -- Track highest nameplate index for ScanTargets optimization
  local idx = unitID and tonumber(unitID:match("nameplate(%d+)"))
  if idx then
    BattleGroundEnemies.maxNameplateIndex = math.max(BattleGroundEnemies.maxNameplateIndex or 0, idx)
  end
  local enemyButton = self:GetPlayerbuttonByUnitID(unitID, "Enemies")
  if enemyButton then
    enemyButton:UpdateEnemyUnitID("Nameplate", unitID)
  else
    -- Match failed (unit data may not be ready yet, or PID failed in combat).
    -- Retry after a short delay — ScanTargets will also catch it at 0.25s,
    -- but this gets us there faster.
    local enemies = self
    C_Timer.After(0.1, function()
      if UnitExists(unitID) and BattleGroundEnemies.IsEnemyUnit(unitID) then
        BattleGroundEnemies:ClearScanCycleCache()
        local btn = enemies:GetPlayerbuttonByUnitID(unitID, "Enemies")
        if btn then
          btn:UpdateEnemyUnitID("Nameplate", unitID)
        end
      end
    end)
  end
end

function BattleGroundEnemies.Enemies:NAME_PLATE_UNIT_REMOVED(unitID)
  -- Invalidate sticky PID cache for this nameplate token (and its compound tokens).
  -- Without this, recycled nameplates would incorrectly map to the old enemy's button.
  BattleGroundEnemies:InvalidateStickyPID(unitID)
  BattleGroundEnemies:InvalidateStickyPID(unitID .. "target")

  -- Can't use GetPlayerbuttonByUnitID here because the unit may already be invalid
  -- (UnitExists returns false after nameplate removal). Instead, scan buttons directly
  -- to find which one has this nameplate stored.
  if self.Players then
    for _, btn in pairs(self.Players) do
      if btn.UnitIDs and btn.UnitIDs.Nameplate == unitID then
        btn:UpdateEnemyUnitID("Nameplate", false)
        return
      end
    end
  end
end

-- Focus, Mouseover, TargetTarget Support
local function UpdateUnitIDForToken(self, tokenKey, unitID)
  if not self.Players then
    return
  end

  local button = self:GetPlayerbuttonByUnitID(unitID, "Enemies")

  -- local name = GetUnitName(unitID, true) or "nil"
  -- local found = button and button.PlayerDetails.PlayerName or "nil"

  local previousButtonKey = tokenKey .. "Button" -- e.g. FocusButton

  if self[previousButtonKey] and self[previousButtonKey] ~= button then
    self[previousButtonKey]:UpdateEnemyUnitID(tokenKey, nil)
    self[previousButtonKey] = nil
  end

  if button then
    button:UpdateEnemyUnitID(tokenKey, unitID)
    self[previousButtonKey] = button
  end
end

function BattleGroundEnemies.Enemies:PLAYER_FOCUS_CHANGED()
  UpdateUnitIDForToken(self, "Focus", "focus")
  UpdateUnitIDForToken(self, "FocusTarget", "focustarget")
end

function BattleGroundEnemies.Enemies:UPDATE_MOUSEOVER_UNIT()
  UpdateUnitIDForToken(self, "Mouseover", "mouseover")
end

function BattleGroundEnemies.Enemies:PLAYER_SOFT_INTERACT_CHANGED()
  UpdateUnitIDForToken(self, "SoftEnemy", "softinteract")
end

function BattleGroundEnemies.Enemies:PLAYER_TARGET_CHANGED()
  UpdateUnitIDForToken(self, "TargetTarget", "targettarget")
end

function BattleGroundEnemies.Enemies:AddGroupTarget(button, sourceUnit, targetUnitID)
  self.GroupTargetMap = self.GroupTargetMap or {}
  self.GroupTargetMap[button] = self.GroupTargetMap[button] or {}
  self.GroupTargetMap[button][sourceUnit] = targetUnitID

  button:UpdateEnemyUnitID("GroupTarget", targetUnitID)
end

function BattleGroundEnemies.Enemies:RemoveGroupTarget(button, sourceUnit)
  if not self.GroupTargetMap or not self.GroupTargetMap[button] then
    return
  end
  self.GroupTargetMap[button][sourceUnit] = nil

  local nextUnitID = next(self.GroupTargetMap[button]) and select(2, next(self.GroupTargetMap[button]))
  button:UpdateEnemyUnitID("GroupTarget", nextUnitID)
end

function BattleGroundEnemies.Enemies:AddNameplateTarget(button, sourceUnit, targetUnitID)
  self.NameplateTargetMap = self.NameplateTargetMap or {}
  self.NameplateTargetMap[button] = self.NameplateTargetMap[button] or {}
  self.NameplateTargetMap[button][sourceUnit] = targetUnitID

  button:UpdateEnemyUnitID("NameplateTarget", targetUnitID)
end

function BattleGroundEnemies.Enemies:RemoveNameplateTarget(button, sourceUnit)
  if not self.NameplateTargetMap or not self.NameplateTargetMap[button] then
    return
  end
  self.NameplateTargetMap[button][sourceUnit] = nil

  local nextUnitID = next(self.NameplateTargetMap[button]) and select(2, next(self.NameplateTargetMap[button]))
  button:UpdateEnemyUnitID("NameplateTarget", nextUnitID)
end

function BattleGroundEnemies.Enemies:AddArenaTarget(button, sourceUnit, targetUnitID)
  self.ArenaTargetMap = self.ArenaTargetMap or {}
  self.ArenaTargetMap[button] = self.ArenaTargetMap[button] or {}
  self.ArenaTargetMap[button][sourceUnit] = targetUnitID

  button:UpdateEnemyUnitID("ArenaTarget", targetUnitID)
end

function BattleGroundEnemies.Enemies:RemoveArenaTarget(button, sourceUnit)
  if not self.ArenaTargetMap or not self.ArenaTargetMap[button] then
    return
  end
  self.ArenaTargetMap[button][sourceUnit] = nil

  local nextUnitID = next(self.ArenaTargetMap[button]) and select(2, next(self.ArenaTargetMap[button]))
  button:UpdateEnemyUnitID("ArenaTarget", nextUnitID)
end

function BattleGroundEnemies.Enemies:AddGroupPetTarget(button, sourceUnit, targetUnitID)
  self.GroupPetTargetMap = self.GroupPetTargetMap or {}
  self.GroupPetTargetMap[button] = self.GroupPetTargetMap[button] or {}
  self.GroupPetTargetMap[button][sourceUnit] = targetUnitID

  button:UpdateEnemyUnitID("GroupPetTarget", targetUnitID)
end

function BattleGroundEnemies.Enemies:RemoveGroupPetTarget(button, sourceUnit)
  if not self.GroupPetTargetMap or not self.GroupPetTargetMap[button] then
    return
  end
  self.GroupPetTargetMap[button][sourceUnit] = nil

  local nextUnitID = next(self.GroupPetTargetMap[button]) and select(2, next(self.GroupPetTargetMap[button]))
  button:UpdateEnemyUnitID("GroupPetTarget", nextUnitID)
end

function BattleGroundEnemies.Enemies:UNIT_TARGET(unitID)
  -- Invalidate sticky PID cache for the compound token that just changed.
  -- e.g. raid3 fires UNIT_TARGET → "raid3target" now points to someone else.
  BattleGroundEnemies:InvalidateStickyPID(unitID .. "target")

  -- Single-token handlers (your own unit changed target)
  if unitID == "target" then
    UpdateUnitIDForToken(self, "TargetTarget", "targettarget")
    return
  end

  if unitID == "pet" then
    UpdateUnitIDForToken(self, "PetTarget", "pettarget")
    return
  end

  if unitID == "focus" then
    UpdateUnitIDForToken(self, "FocusTarget", "focustarget")
    return
  end

  -- Multi-source handlers (group members / arena / nameplates changed target)
  local targetUnitID = unitID .. "target"

  if string.find(unitID, "^arena%d") then
    local button = self:GetPlayerbuttonByUnitID(targetUnitID, "Enemies")
    self.ArenaTargets = self.ArenaTargets or {}
    local oldButton = self.ArenaTargets[unitID]
    if oldButton and oldButton ~= button then
      self:RemoveArenaTarget(oldButton, unitID)
    end
    if button then
      self:AddArenaTarget(button, unitID, targetUnitID)
      self.ArenaTargets[unitID] = button
    else
      self.ArenaTargets[unitID] = nil
    end
    return
  end

  if string.find(unitID, "^nameplate%d") then
    local button = self:GetPlayerbuttonByUnitID(targetUnitID, "Enemies")
    self.NameplateTargets = self.NameplateTargets or {}
    local oldButton = self.NameplateTargets[unitID]
    if oldButton and oldButton ~= button then
      self:RemoveNameplateTarget(oldButton, unitID)
    end
    if button then
      self:AddNameplateTarget(button, unitID, targetUnitID)
      self.NameplateTargets[unitID] = button
    else
      self.NameplateTargets[unitID] = nil
    end
    return
  end

  if not (string.find(unitID, "^raid") or string.find(unitID, "^party")) then
    return
  end

  -- GroupTarget: raidNtarget / partyNtarget
  local button = self:GetPlayerbuttonByUnitID(targetUnitID, "Enemies")

  self.UnitTargets = self.UnitTargets or {}
  local oldButton = self.UnitTargets[unitID]

  if oldButton and oldButton ~= button then
    self:RemoveGroupTarget(oldButton, unitID)
  end

  if button then
    self:AddGroupTarget(button, unitID, targetUnitID)
    self.UnitTargets[unitID] = button
  else
    self.UnitTargets[unitID] = nil
  end
end

BattleGroundEnemies.Enemies:RegisterEvent("PLAYER_FOCUS_CHANGED")
BattleGroundEnemies.Enemies:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
if BattleGroundEnemies.Enemies.RegisterEvent then
  pcall(function()
    BattleGroundEnemies.Enemies:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
  end)
end
BattleGroundEnemies.Enemies:RegisterEvent("PLAYER_TARGET_CHANGED")
BattleGroundEnemies.Enemies:RegisterEvent("UNIT_TARGET")
