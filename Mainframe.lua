---@class Data
---@class BattleGroundEnemies

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
-- Secret-safe GetUnitName (mirrors Main.lua). Enemy name/realm are SECRET in
-- instanced PvP and Blizzard's stock GetUnitName does an unguarded `server ~= ""`
-- on them, emitting taint that pcall cannot suppress. Guard with issecretvalue:
-- when name/realm is secret, return the bare name (callers issecretvalue-check
-- before using it as a key, and SetText accepts secrets).
local GetUnitName = function(unit, showServerName)
  local name, server = UnitName(unit)
  if not name then
    return nil
  end
  if issecretvalue and (issecretvalue(name) or issecretvalue(server)) then
    return name
  end
  if server and server ~= "" then
    if showServerName then
      return name .. "-" .. server
    else
      local relationship = UnitRealmRelationship(unit)
      if relationship == LE_REALM_RELATION_VIRTUAL then
        return name
      else
        return name .. FOREIGN_SERVER_LABEL
      end
    end
  else
    return name
  end
end
local InCombatLockdown = InCombatLockdown
local UnitGUID = UnitGUID
local UnitRace = UnitRace

--lua
local math_huge = math.huge
local math_max = math.max
local math_random = math.random
local table_insert = table.insert
local table_remove = table.remove

local HasSpeccs = not not GetSpecialization

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
    -- DR and Trinket only work in arena (<=5 players); skip for larger team sizes
    if (BattleGroundEnemies.Testmode.PlayerCountTestmode or 5) > 5 then
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

		-- 12.0.5: secret-named players have their playerName attribute set to nil,
		-- so skip any index whose name is nil and walk until we find one or
		-- loop back to start. If none of the slots have a usable name, bail
		-- (no-op click) rather than concatenating nil and erroring.
		local nextTargetName = self:GetAttribute("playerName"..nextPlayerIndex)
		if not nextTargetName then
			local scanned = 0
			while scanned < maxUnits do
				nextPlayerIndex = nextPlayerIndex + 1
				if nextPlayerIndex > maxUnits then nextPlayerIndex = 1 end
				nextTargetName = self:GetAttribute("playerName"..nextPlayerIndex)
				if nextTargetName then break end
				scanned = scanned + 1
			end
		end

		if nextTargetName then
			self:SetAttribute("macrotext",'/cleartarget\n' ..
					'/targetexact ' ..
					nextTargetName)
			self:SetAttribute("playerIndex", nextPlayerIndex)
		end
	]]
  )

  mainframe.Players = {} --index = name, value = button(table), contains enemyButtons
  mainframe.PlayerList = {} --index = number, value = button(table). Parallel to Players, safe under secret names (pairs() on a secret-keyed table can taint).
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
    -- PvE hard gate: Enemies/Allies frames register UNIT_DIED, UNIT_TARGET, etc.
    -- at file load and keep firing in raids. Drop every event outside PvP.
    if not BattleGroundEnemies:IsInPvPInstance() then
      return
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
    -- DIAGNOSTIC (commented out — re-enable if the "enemies disappear in
    -- lobby" bug returns. Prints when this path is called so we can see
    -- if PEW or some other path is wiping all sources unexpectedly):
    -- print(
    --   string.format(
    --     "BGE Diag: %s:RemoveAllPlayersFromAllSources called (PlayerList=%d)",
    --     self.PlayerType,
    --     #self.PlayerList
    --   )
    -- )
    self:InitializeAllPlayerSources()
    self.RealPlayerCount = nil
    self:AfterPlayerSourceUpdate()
  end

  function mainframe:RemoveAllPlayersFromSource(source)
    self:BeforePlayerSourceUpdate(source)
    self:AfterPlayerSourceUpdate()
  end

  function mainframe:BeforePlayerSourceUpdate(source)
    self.PlayerSources[source] = {}
  end

  function mainframe:AddPlayerToSource(source, playerT)
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

    if not playerT.classToken or playerT.classToken == "" then
      return
    end

    table_insert(self.PlayerSources[source], playerT)
  end

  function mainframe:FindPlayerInSource(source, playerT)
    local playerSource = self.PlayerSources[source]
    local targetName = playerT.name
    if not targetName then
      return
    end
    for i = 1, #playerSource do
      local playerData = playerSource[i]
      if playerData.name == targetName then
        return playerData
      end
    end
  end

  local function matchBattleFieldScoreToArenaEnemyPlayer(scoreTables, arenaPlayerInfo)
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
        -- talentSpec has no NeverSecret flag in PVPScoreInfo, so it can be
        -- a secret string in active matches. Direct == compare on a secret
        -- string taints the call stack — fold the secrecy check into a
        -- pre-computed specMatches bool. Legacy expansions return
        -- talentSpec=nil, which still needs to match arenaPlayerInfo.specName=nil.
        local scoreSpec = scoreInfo.talentSpec
        local specMatches
        if scoreSpec == nil then
          specMatches = (arenaPlayerInfo.specName == nil)
        elseif issecretvalue and issecretvalue(scoreSpec) then
          -- Secret spec can't be safely disambiguated. Skip this candidate.
          specMatches = false
        else
          specMatches = (scoreSpec == arenaPlayerInfo.specName)
        end

        if
          scoreInfo.faction == BattleGroundEnemies.EnemyFaction
          and scoreInfo.classToken == arenaPlayerInfo.classToken
          and specMatches
        then
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
    -- if BattleGroundEnemies.LogButtonEvent then
    --   BattleGroundEnemies:LogButtonEvent(
    --     "TICK_START",
    --     self.PlayerType,
    --     nil,
    --     "list=" .. #self.PlayerList .. " combat=" .. tostring(InCombatLockdown())
    --   )
    -- end

    local newPlayers = {} --contains combined data from PlayerSources
    if self.PlayerType == BattleGroundEnemies.consts.PlayerTypes.Enemies then
      if BattleGroundEnemies:IsTestmodeActive() then
        newPlayers = self.PlayerSources[BattleGroundEnemies.consts.PlayerSources.FakePlayers]
      else
        local scoreboardEnemies = self.PlayerSources[BattleGroundEnemies.consts.PlayerSources.Scoreboard]
        local numScoreboardEnemies = #scoreboardEnemies
        local addScoreBoardPlayers = false
        if BattleGroundEnemies:GetActiveStates().isInArena then
          --use arenaPlayers is primary source to preserve same order arena1 to arena3, scoreboard doesn't offer this
          local arenaEnemies = self.PlayerSources[BattleGroundEnemies.consts.PlayerSources.ArenaPlayers]
          local numArenaEnemies = #arenaEnemies

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
                  playerName = match.name
                else
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
      if BattleGroundEnemies:IsTestmodeActive() then
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
            local match = self:FindPlayerInSource(BattleGroundEnemies.consts.PlayerSources.Scoreboard, groupMember)
            if match then
              groupMember.specName = match.talentSpec
            end
          end
          table.insert(newPlayers, groupMember)
        end
      end
    end
    self:BeforePlayerUpdate()
    -- DIAGNOSTIC (commented out — re-enable if the "enemies disappear in
    -- lobby" bug returns. Logs when AfterPlayerSourceUpdate shrinks the
    -- PlayerList, with which source emptied out):
    -- if BattleGroundEnemies.LogButtonEvent and #newPlayers < #self.PlayerList then
    --   local scoreboardSrc = self.PlayerSources
    --     and self.PlayerSources[BattleGroundEnemies.consts.PlayerSources.Scoreboard]
    --   local groupSrc = self.PlayerSources
    --     and self.PlayerSources[BattleGroundEnemies.consts.PlayerSources.GroupMembers]
    --   local arenaSrc = self.PlayerSources
    --     and self.PlayerSources[BattleGroundEnemies.consts.PlayerSources.ArenaPlayers]
    --   print(
    --     string.format(
    --       "BGE Diag: %s:AfterPlayerSourceUpdate SHRINKING PlayerList %d → %d (Scoreboard=%d Group=%d Arena=%d)",
    --       self.PlayerType,
    --       #self.PlayerList,
    --       #newPlayers,
    --       scoreboardSrc and #scoreboardSrc or -1,
    --       groupSrc and #groupSrc or -1,
    --       arenaSrc and #arenaSrc or -1
    --     )
    --   )
    -- end
    for i = 1, #newPlayers do
      local newPlayer = newPlayers[i]
      local name = newPlayer.name
      local raceName = newPlayer.raceName
      local classToken = newPlayer.classToken
      local specName = newPlayer.specName
      local additionalData = newPlayer.additionalData
      local realmName = newPlayer.realmName
      self:CreateOrUpdatePlayerDetails(name, raceName, classToken, specName, realmName, additionalData)
    end

    self:SetPlayerCount(#newPlayers)
    self:CreateOrRemovePlayerButtons()

    -- if BattleGroundEnemies.LogButtonEvent then
    --   BattleGroundEnemies:LogButtonEvent(
    --     "TICK_END",
    --     self.PlayerType,
    --     nil,
    --     "list=" .. #self.PlayerList .. " num=" .. (self.NumPlayers or -1)
    --   )
    -- end

    -- Hide mainframe when no players to show, to prevent empty frame blocking clicks
    if not BattleGroundEnemies:IsTestmodeActive() then
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
  end

  function mainframe:OnTestmodeDisabled()
    for playerName, playerButton in pairs(self.Players) do
      playerButton:DispatchEvent("OnTestmodeDisabled")
    end
    self:RemoveAllPlayersFromSource(BattleGroundEnemies.consts.PlayerSources.FakePlayers)
    self.ActiveProfile:Hide()
  end

  function mainframe:Enable()
    if InCombatLockdown() then
      return BattleGroundEnemies:QueueForUpdateAfterCombat(mainframe, "CheckEnableState")
    end

    if BattleGroundEnemies:IsTestmodeActive() then
    else
      if self.PlayerType == BattleGroundEnemies.consts.PlayerTypes.Enemies then
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

    -- In test mode, always use NumPlayers, not instance info
    if BattleGroundEnemies:IsTestmodeActive() then
      maxNumPlayers = self.NumPlayers or 10
    elseif BattleGroundEnemies.states.real.isInArena then
      -- Arena: same map can host different brackets (2v2, 3v3), so GetInstanceInfo()
      -- returns the map capacity, not the bracket size. Use actual player count instead.
      maxNumPlayers = math_max(self.RealPlayerCount or 0, self.NumPlayers or 0)
    elseif BattleGroundEnemies.states.real.isInBattleground then
      -- BG: use instance max players for profile selection so the frame stays
      -- visible when enemies are still loading (e.g., Training Grounds).
      -- GetCorrectedMaxPlayers fixes GetInstanceInfo's mis-reports (epics report
      -- the TOTAL 80 instead of the 40-per-team bracket size, Solo Blitz, etc.)
      -- so we don't trip the ">40 -> no profile" guard below. It returns 0 when
      -- nothing is known yet (instanceID nil during load) -> fall back to the
      -- live player counts.
      local instanceMaxPlayers = BattleGroundEnemies:GetCorrectedMaxPlayers()
      if instanceMaxPlayers and instanceMaxPlayers > 0 then
        if instanceMaxPlayers > 40 then
          -- >40 = GetInstanceInfo reported the epic TOTAL (a single team is never
          -- >40, user-confirmed), so this IS an epic regardless of the map -- and
          -- every epic is 16-40 per team. Default to the top bracket: clamp to 40,
          -- which matches the 16-40 profile (or whatever custom bracket covers 40).
          -- This is never a wrong bracket (it really is an epic) and never blanks.
          -- Curated epics never reach here (the corrections table pins them to 40);
          -- this only covers an unlisted/future epic map.
          maxNumPlayers = 40
        else
          maxNumPlayers = instanceMaxPlayers
        end
      else
        -- 0 = GetInstanceInfo hasn't settled yet (the brief load window). We have
        -- NO trustworthy bracket, and we will NOT guess from the live count -- a
        -- partially-loaded roster would pick a wrong SMALL bracket (e.g. 1-5/6-15
        -- for a true 40v40) on entry. Per "never show the wrong profile; prefer no
        -- enemies", show "no profile" until GetInstanceInfo resolves; self-heals
        -- via UBS every combat tick + the +5s SelectPlayerCountProfile(true) /
        -- GROUP_ROSTER_UPDATE (Main.lua ~5532). NOTE: the map's per-team cap (not
        -- the live joined-count) drives the bracket once settled, so enemies show
        -- as they JOIN under the correct bracket -- nothing waits for a full lobby.
        return self:NoActivePlayercountProfile()
      end
    else
      -- Not in any PvP instance (open world / city). No player-count bracket
      -- applies, so force "no profile" rather than reading GetInstanceInfo --
      -- which out in the world returns a meaningless small maxPlayers (~5) that
      -- otherwise shows up as a phantom "1-5" bracket. The container is Disabled
      -- here regardless; this just keeps the bracket reading consistently as
      -- "no profile" out of an instance (and lets the enemy bracket, which UBS
      -- can't re-settle in the city, reset cleanly on leaving a match).
      return self:NoActivePlayercountProfile()
    end
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
      -- Custom-profile gap hint. When this side has CUSTOM player-count profiles
      -- enabled (the 1-5 / 6-15 / 16-40 defaults are off) and NONE of them cover
      -- the current size, frames silently don't show -- which is confusing. Tell
      -- the user why and how to fix it. Conditions:
      --   * self.playerTypeConfig.Enabled -- only warn for a side the user
      --     actually wants shown (a disabled Allies/Enemies side stays silent
      --     even if it has custom profiles configured).
      --   * CustomPlayerCountConfigsEnabled -- the defaults cover every size
      --     1-40, so a gap is only possible in custom mode.
      --   * not self._warnedNoCustomProfile -- throttle to once per game (the
      --     flag is reset on entering a BG/arena in PLAYER_ENTERING_WORLD; a
      --     /reload clears it too, so it re-fires).
      if
        self.playerTypeConfig.Enabled
        and self.playerTypeConfig.CustomPlayerCountConfigsEnabled
        and not self._warnedNoCustomProfile
      then
        self._warnedNoCustomProfile = true
        BattleGroundEnemies:Information(
          "Custom "
            .. self.PlayerType
            .. " profiles are on, but none cover the current size of "
            .. maxNumPlayers
            .. " players. Add or widen a custom "
            .. self.PlayerType
            .. " profile in the options to show frames at this size."
        )
      end
      return
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

  -- Config-derived "should this container be shown for the current bracket".
  -- Timing-safe, unlike self.enabled: it reads only playerTypeConfig /
  -- playerCountConfig (set synchronously by SelectPlayerCountProfile, which is
  -- NOT combat-deferred) plus the main-addon enabled flag (set synchronously by
  -- BattleGroundEnemies:Enable). self.enabled, by contrast, LAGS in combat --
  -- mainframe:Enable and ApplyPlayerCountProfileSettings both early-return via
  -- QueueForUpdateAfterCombat BEFORE updating self.enabled / calling
  -- CheckEnableState while InCombatLockdown() is true. The ghost-frame BUILD
  -- gates (GROUP_ROSTER_UPDATE / UBS / CreateArenaEnemies) use THIS, so an
  -- in-combat instance entry or mid-match /reload still builds the right
  -- rosters instead of reading a stale/nil enabled flag and building nothing.
  function mainframe:ShouldBeEnabled()
    return (
      BattleGroundEnemies.enabled
      and self.playerTypeConfig
      and self.playerTypeConfig.Enabled
      and self.playerCountConfig
      and self.playerCountConfig.Enabled
    ) and true
      or false
  end

  function mainframe:CheckEnableState()
    if self:ShouldBeEnabled() then
      self:Enable()
    else
      self:Disable()
    end
  end

  function mainframe:SetRealPlayerCount(realCount)
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

    if not self.playerCountConfig or not self.playerCountConfig.PlayerCount.Enabled then
      self.PlayerCount:Hide()
      return
    end

    -- Wait for faction to be authoritatively set by UBS / PEW (via the
    -- user's own scoreboard-row GUID lookup). No defensive guess here —
    -- "Alliance" / "Horde" labels would be wrong for mercs and for users
    -- whose home faction differs from their assigned team. Better to
    -- briefly show nothing than the wrong label. UBS will trigger another
    -- UpdatePlayerCountText via SetAllyFaction's change-callback when it
    -- gets a value.
    if BattleGroundEnemies.EnemyFaction == nil then
      self.PlayerCount:Hide()
      return
    end

    self.PlayerCount:Show()
    self.PlayerCount:SetText(
      format(
        isEnemy == (BattleGroundEnemies.EnemyFaction == 0) and PLAYER_COUNT_HORDE or PLAYER_COUNT_ALLIANCE,
        maxNumPlayers
      )
    )
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
    -- 0.2s = 5 Hz per button (halved from 0.1s / 10 Hz). Shared by both the
    -- enemy and ally OnUpdate handlers below. UpdateAll's health/power data
    -- is already driven by UNIT_HEALTH / UNIT_POWER_FREQUENT push events;
    -- this ticker is a safety-net poll (mainly for range-indicator state and
    -- compound tokens). Halving it cuts the UpdateAll call volume ~50%
    -- (the single biggest CPU line in epic BG combat, up to 124-378 ms/s)
    -- at the cost of ~100ms extra range-indicator latency (imperceptible).
    local UpdatePeriod = 0.2 --update every 0.2 seconds

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
          if TimeSinceLastOnUpdate > UpdatePeriod then
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
          if TimeSinceLastOnUpdate > UpdatePeriod then
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

    local pname = playerButton.PlayerDetails and playerButton.PlayerDetails.PlayerName
    if pname then
      self.Players[pname] = playerButton
    end
    table_insert(self.PlayerList, playerButton)

    -- if BattleGroundEnemies.LogButtonEvent then
    --   BattleGroundEnemies:LogButtonEvent(
    --     "CREATE",
    --     self.PlayerType,
    --     playerButton,
    --     "list=" .. #self.PlayerList
    --   )
    -- end

    return playerButton
  end

  function mainframe:RemovePlayer(playerButton)
    if playerButton == BattleGroundEnemies.UserButton then
      -- Keep the player's own button stable across roster churn WHILE the ally
      -- container is enabled (the original "don't remove the player itself"
      -- intent -- avoids flicker when a teammate join/leave rebuilds the list).
      -- But RemovePlayer is the ONLY teardown path, so an unconditional skip
      -- made the self-button impossible to remove: with allies DISABLED for the
      -- bracket (or the addon disabled while leaving to the city), the #1/#5
      -- teardown calls RemovePlayer on it and this guard bailed, so it persisted
      -- as a lone ghost ally frame across BG -> city -> BG. Gate the skip on
      -- ShouldBeEnabled (config-derived, combat-safe) so the self-button is kept
      -- only while allies should be shown, and torn down otherwise. Clear the
      -- now-stale UserButton ref so target/focus logic doesn't touch a recycled
      -- button (re-tagged by UpdateAllUnitIDs on the next enabled build).
      if self:ShouldBeEnabled() then
        return
      end
      BattleGroundEnemies.UserButton = false
    end -- dont remove the Player itself (only while allies are enabled)

    -- if BattleGroundEnemies.LogButtonEvent then
    --   BattleGroundEnemies:LogButtonEvent(
    --     "REMOVE",
    --     self.PlayerType,
    --     playerButton,
    --     "combat=" .. tostring(InCombatLockdown())
    --   )
    -- end

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
    local pname = playerButton.PlayerDetails and playerButton.PlayerDetails.PlayerName
    if pname then
      self.Players[pname] = nil
    end
    for i = #self.PlayerList, 1, -1 do
      if self.PlayerList[i] == playerButton then
        table_remove(self.PlayerList, i)
        break
      end
    end
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
    local maxPlayers = #self.CurrentPlayerOrder
    self:SetAttribute("maxUnits", maxPlayers)
    for j = 1, #self.CurrentPlayerOrder do
      local pname = self.CurrentPlayerOrder[j].PlayerDetails.PlayerName
      self:SetAttribute("playerName" .. j, pname or nil)
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
    -- Reset all buttons' "claimed-this-tick" status to 2 (carried-over /
    -- unclaimed). The CreateOrRemovePlayerButtons combat-deferred path
    -- early-returns mid-loop and does NOT reset claimed buttons (status=1)
    -- back to 2 in that case. Without this, on the next tick's Stage 3
    -- those stuck-at-1 buttons are excluded from match candidacy
    -- (`btn.status ~= 1` filter), so source rows fall through to
    -- PENDING_NEW and we create duplicate buttons on top of stuck ones.
    -- Doing the reset here, at the start of every AfterPlayerSourceUpdate,
    -- means each tick begins with a clean slate regardless of whether the
    -- previous tick fully completed its cleanup.
    for i = 1, #self.PlayerList do
      self.PlayerList[i].status = 2
    end
  end

  function mainframe:CreateOrUpdatePlayerDetails(name, race, classToken, specName, realmName, additionalData)
    local spec = false
    if specName then
      -- 12.0.5: specName may be a secret string; comparing ~= "" taints.
      -- Secret values are real strings (never empty), so treat as non-empty.
      if (issecretvalue and issecretvalue(specName)) or specName ~= "" then
        spec = specName
      end
    end
    local specData
    if classToken and spec and not (issecretvalue and issecretvalue(spec)) then
      local t = Data.Classes[classToken]
      if t then
        specData = t[spec]
      end
    end

    local playerDetails = {
      -- Canonicalize PlayerName to "Name-Realm" form. PVPScoreInfo.name and
      -- GetRaidRosterInfo return short "Name" for same-realm players; chat
      -- messages always emit "Name-Realm". Storing under canonical form
      -- means Players[] lookups work uniformly. See BattleGroundEnemies:CanonicalName
      -- in Main.lua for rationale.
      PlayerName = BattleGroundEnemies:CanonicalName(name),
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

    -- GUIDs are effectively always secret in 12.0.5 PvP now, so the old
    -- PlayerGUIDs fast-path can never be populated with a usable key —
    -- removed. Ditto for the GUID-match stage in identity lookup below.

    -- Find existing button for this scoreboard entry. Each button can be
    -- claimed (status=1) at most once per tick — all matching paths honor
    -- the status check so name-lookup and fingerprint-fallback can't both
    -- collide on the same button and cause data swaps / duplicates.
    --
    -- Stage 1: non-secret name lookup. Stable identity for non-secret names.
    -- Stage 2: consume-first-unclaimed by class (fallback for secret names).
    --
    -- GUIDs are effectively always secret in 12.0.5 PvP now, so the GUID
    -- stage that used to sit between these two has been removed — it was
    -- silently dead code.
    local playerButton
    local strongMatch = false
    -- local matchStage = "new" -- diagnostic: tracks which stage produced the match
    if name then
      -- Canonicalize lookup key: Players[] stores under "Name-Realm" form
      -- (CanonicalName at storage above). PVPScoreInfo.name is short for
      -- same-realm — must canonicalize before lookup or we silently miss
      -- and fall through to class-fallback, mis-claiming buttons.
      local btn = self.Players[BattleGroundEnemies:CanonicalName(name)]
      -- Must check status so the SAME button doesn't get claimed twice in
      -- one tick (once via name, once via class fallback). Without this,
      -- two rows that resolve to the same button mutate each other's data
      -- and the "loser" row's player never materializes anywhere.
      if btn and btn.status ~= 1 then
        playerButton = btn
        strongMatch = true
        -- matchStage = "stage1-name"
      end
    end
    if not playerButton and classToken and self.PlayerList then
      local upperClass = string.upper(classToken)
      local raceKey = race or ""
      -- Consume-first-unclaimed. Same-class-same-race rows are processed
      -- in order; each row claims the first unclaimed button that matches
      -- (greedy). Identity of individual buttons among same-class peers
      -- can drift across ticks if row order shifts, but the total count
      -- stays correct — no duplicates, no hijacking, no ghost buttons.
      for i = 1, #self.PlayerList do
        local btn = self.PlayerList[i]
        if
          btn.status ~= 1
          and btn.PlayerDetails
          and btn.PlayerDetails.PlayerClass == upperClass
          and (btn.PlayerDetails.PlayerRace or "") == raceKey
        then
          playerButton = btn
          -- matchStage = "stage2-fingerprint"
          -- Not a strong match — live-captured attrs (gender, honor,
          -- guild) should not be preserved across this swap since we're
          -- attaching a potentially different player's scoreboard row
          -- onto this button.
          break
        end
      end
    end

    -- Preserve fields we set on the button after its initial creation —
    -- these are NOT provided by the scoreboard, so a wholesale PlayerDetails
    -- swap would wipe them. Specifically this was the "click works once"
    -- bug: PlayerArenaUnitID gets set by ArenaOpponentShown when the flag
    -- carrier's arena token arrives, then the next UPDATE_BATTLEFIELD_SCORE
    -- rebuilds PlayerDetails from scoreboard, nukes PlayerArenaUnitID, and
    -- SetBindings clears the secure unit/type1/type2 attributes.
    if playerButton and playerButton.PlayerDetails then
      local pd = playerButton.PlayerDetails
      -- Arena-token-mirror / scoreboard-can't-provide fields: preserve
      -- unconditionally. They were written by us onto this exact button
      -- (ArenaOpponentShown), not inferred via ambiguous fingerprint.
      if pd.PlayerArenaUnitID and not playerDetails.PlayerArenaUnitID then
        playerDetails.PlayerArenaUnitID = pd.PlayerArenaUnitID
      end
      if pd.SecretDisplayName ~= nil and playerDetails.SecretDisplayName == nil then
        playerDetails.SecretDisplayName = pd.SecretDisplayName
      end
    end

    -- Preserve live-captured non-secret attrs across the details swap —
    -- ONLY on strong identity match. Weak (ambiguous fingerprint) matches
    -- might be carrying another player's data forward.
    -- Source tags travel with the value so captureLiveAttrs in
    -- GetPlayerbuttonByUnitID can still distinguish "harvest seed" vs
    -- "live captured" after a CreateOrUpdatePlayerDetails swap.
    if strongMatch and playerButton and playerButton.PlayerDetails then
      local pd = playerButton.PlayerDetails
      if pd.gender and not (issecretvalue and issecretvalue(pd.gender)) and not playerDetails.gender then
        playerDetails.gender = pd.gender
        playerDetails._genderSource = pd._genderSource
      end
      if
        pd.honorLevel
        and not (issecretvalue and issecretvalue(pd.honorLevel))
        and (not playerDetails.honorLevel or (issecretvalue and issecretvalue(playerDetails.honorLevel)))
      then
        playerDetails.honorLevel = pd.honorLevel
        playerDetails._honorLevelSource = pd._honorLevelSource
      end
      -- GuildName: `false` (confirmed guildless) is a real value, not
      -- "no value". Use explicit `~= nil` instead of truthy check so we
      -- correctly preserve a captured-guildless state across the swap.
      if
        pd.GuildName ~= nil
        and not (issecretvalue and issecretvalue(pd.GuildName))
        and playerDetails.GuildName == nil
      then
        playerDetails.GuildName = pd.GuildName
        playerDetails._GuildNameSource = pd._GuildNameSource
      end
      if pd.lastPowerType and not playerDetails.lastPowerType then
        playerDetails.lastPowerType = pd.lastPowerType
        playerDetails._lastPowerTypeSource = pd._lastPowerTypeSource
      end
    end

    -- Harvest seed: fill any field still nil/false/secret from
    -- db.global.PlayerHistory. Runs AFTER live-captured preservation so
    -- live values take priority over harvest. Source-tag with
    -- _<field>Source = "harvest" so captureLiveAttrs in GetPlayerbuttonByUnitID
    -- can promote to "live" on the first non-fallback unit-token resolve.
    -- For PlayerSpecName / PlayerRole this is the ONLY mid-match source —
    -- talentSpec/roleAssigned are SecretInActivePvPMatch on the scoreboard.
    do
      local history = BattleGroundEnemies.db
        and BattleGroundEnemies.db.global
        and BattleGroundEnemies.db.global.PlayerHistory
        and BattleGroundEnemies.db.global.PlayerHistory[playerDetails.PlayerName]
      if history then
        -- Normal seed: empty = nil OR false (placeholder) OR secret.
        local function seed(field, value, sourceField)
          if value == nil then
            return
          end
          local cur = playerDetails[field]
          if cur == nil or cur == false or (issecretvalue and issecretvalue(cur)) then
            playerDetails[field] = value
            playerDetails[sourceField] = "harvest"
          end
        end
        -- GuildName seed: `false` means CONFIRMED GUILDLESS (real value),
        -- NOT a placeholder. Empty = ONLY nil OR secret. Don't overwrite
        -- a live-captured `false` with potentially-stale harvest data.
        local function seedGuild(value)
          if value == nil then
            return
          end
          local cur = playerDetails.GuildName
          if cur == nil or (issecretvalue and issecretvalue(cur)) then
            playerDetails.GuildName = value
            playerDetails._GuildNameSource = "harvest"
          end
        end
        seed("gender", history.gender, "_genderSource")
        seed("honorLevel", history.honorLevel, "_honorLevelSource")
        seedGuild(history.GuildName)
        seed("lastPowerType", history.lastPowerType, "_lastPowerTypeSource")

        -- Spec seeding also recomputes PlayerRole via spec→roleID, since
        -- the original PlayerRole calculation above ran with spec=secret.
        local specStillEmpty = playerDetails.PlayerSpecName == nil
          or playerDetails.PlayerSpecName == false
          or (issecretvalue and issecretvalue(playerDetails.PlayerSpecName))
        if history.lastSpec and specStillEmpty then
          playerDetails.PlayerSpecName = history.lastSpec
          playerDetails._PlayerSpecNameSource = "harvest"
          if classToken then
            local t = Data.Classes[classToken]
            local sd = t and t[history.lastSpec]
            local roleStillEmpty = playerDetails.PlayerRole == nil
              or (issecretvalue and issecretvalue(playerDetails.PlayerRole))
            if sd and sd.roleID and roleStillEmpty then
              playerDetails.PlayerRole = sd.roleID
              playerDetails._PlayerRoleSource = "harvest"
            end
          end
        end
      end
    end

    if playerButton then --already existing
      local currentDetails = playerButton.PlayerDetails
      local detailsChanged = false

      -- Both sides of the compare must be non-secret — post-12.0.5 many
      -- fields (name, guid, talentSpec, honorLevel, roleAssigned) can be
      -- secret on either side depending on whether we're comparing a
      -- lobby-parsed PlayerDetails against a mid-match-parsed one.
      for k, v in pairs(playerDetails) do
        local cv = currentDetails[k]
        if not (issecretvalue and (issecretvalue(v) or issecretvalue(cv))) then
          if v ~= cv then
            detailsChanged = true
            break
          end
        end
      end

      if not detailsChanged then
        for k, v in pairs(currentDetails) do
          local pv = playerDetails[k]
          if not (issecretvalue and (issecretvalue(v) or issecretvalue(pv))) then
            if v ~= pv then
              detailsChanged = true
              break
            end
          end
        end
      end
      -- Re-key self.Players when this button's name changes. Without this,
      -- the dict accumulates stale keys (pointing to buttons that no longer
      -- have that name) and fresh rows for other players can't find their
      -- real button via Stage 1 name lookup.
      local oldName = currentDetails and currentDetails.PlayerName
      local newName = playerDetails.PlayerName
      if oldName and self.Players[oldName] == playerButton and oldName ~= newName then
        self.Players[oldName] = nil
      end
      if newName then
        self.Players[newName] = playerButton
      end

      playerButton.PlayerDetails = playerDetails

      if detailsChanged then
        playerButton:PlayerDetailsChanged()
      end

      playerButton.status = 1 --1 means found, already existing
      playerDetails = playerButton.PlayerDetails

      -- if BattleGroundEnemies.LogButtonEvent then
      --   BattleGroundEnemies:LogButtonEvent("MATCH", self.PlayerType, playerButton, matchStage)
      -- end
    else
      table.insert(self.NewPlayersDetails, playerDetails)

      -- if BattleGroundEnemies.LogButtonEvent then
      --   -- Build a temporary button-shaped object so the logger gets the
      --   -- name/class/race fields. Reuse the same playerDetails we just
      --   -- inserted into NewPlayersDetails.
      --   BattleGroundEnemies:LogButtonEvent(
      --     "PENDING_NEW",
      --     self.PlayerType,
      --     { PlayerDetails = playerDetails },
      --     "pending_count=" .. #self.NewPlayersDetails
      --   )
      -- end
    end
  end

  function mainframe:CreateOrRemovePlayerButtons()
    local inCombat = InCombatLockdown()
    local existingPlayersCount = 0
    -- Iterate a snapshot of PlayerList since RemovePlayer mutates it.
    local snapshot = {}
    for i = 1, #self.PlayerList do
      snapshot[i] = self.PlayerList[i]
    end
    for i = 1, #snapshot do
      local playerButton = snapshot[i]
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

    -- Build the 6-tier role ordering from the user's 3-role setting.
    -- The UI dropdown only exposes TANK / HEALER / DAMAGER. Internally
    -- we expand the "TANK" slot into three sub-tiers in Blizzard's order
    -- (MAINTANK → MAINASSIST → TANK) and always append NONE as the last
    -- tier (not user-exposed). This matches Blizzard's CRFSort_Role priority.
    --
    -- Example: RoleSortingOrder = "HEALER_TANK_DAMAGER" →
    --   HEALER=1, MAINTANK=2, MAINASSIST=3, TANK=4, DAMAGER=5, NONE=6
    -- Example: "TANK_HEALER_DAMAGER" →
    --   MAINTANK=1, MAINASSIST=2, TANK=3, HEALER=4, DAMAGER=5, NONE=6
    local function buildRoleTiers()
      local parts = { strsplit("_", BattleGroundEnemies.db.profile.RoleSortingOrder or "HEALER_TANK_DAMAGER") }
      local tiers = {}
      local t = 0
      for i = 1, #parts do
        local role = parts[i]
        if role == "TANK" then
          t = t + 1
          tiers.MAINTANK = t
          t = t + 1
          tiers.MAINASSIST = t
          t = t + 1
          tiers.TANK = t
        elseif role == "HEALER" then
          t = t + 1
          tiers.HEALER = t
        elseif role == "DAMAGER" then
          t = t + 1
          tiers.DAMAGER = t
        end
      end
      -- NONE always last, whether or not it appeared in the user setting.
      t = t + 1
      tiers.NONE = t
      return tiers
    end

    -- Blizzard's chain for picking a player's effective role (CRFSort_Role):
    --   1) Raid-assigned role (GetRaidRosterInfo 10th return: "MAINTANK" or
    --      "MAINASSIST") — wins if present. Ally-only, non-secret.
    --   2) UnitGroupRolesAssigned result stored in PlayerRole (TANK / HEALER /
    --      DAMAGER / NONE), derived upstream from specData or groupRole. For
    --      enemies this can fall back to PVPScoreInfo.roleAssigned, which is
    --      still secret in active match — keep the issecretvalue guard.
    --   3) Otherwise NONE.
    local function effectiveRole(details)
      local raid = details.raidRole
      if raid == "MAINTANK" or raid == "MAINASSIST" then
        return raid
      end
      local role = details.PlayerRole
      if role and not (issecretvalue and issecretvalue(role)) then
        return role
      end
      return "NONE"
    end

    local function PlayerSortingByRoleClassName(playerA, playerB) -- a and b are playerButtons
      local tiers = buildRoleTiers()
      local detailsA = playerA.PlayerDetails
      local detailsB = playerB.PlayerDetails

      local roleA = effectiveRole(detailsA)
      local roleB = effectiveRole(detailsB)
      local tierA = tiers[roleA] or tiers.NONE
      local tierB = tiers[roleB] or tiers.NONE
      if tierA ~= tierB then
        return tierA < tierB
      end

      -- Class tier (Blizzard's standard CLASS_SORT_ORDER). PlayerClass is the
      -- uppercased classToken — non-secret on the ally side (raid roster /
      -- party UnitClass), safe to compare directly.
      local classA = BlizzardsSortOrder[detailsA.PlayerClass] or math_huge
      local classB = BlizzardsSortOrder[detailsB.PlayerClass] or math_huge
      if classA ~= classB then
        return classA < classB
      end

      -- Alphabetical tiebreak (matches Blizzard's CRFSort_Alphabetical).
      local nameA = detailsA.PlayerName
      local nameB = detailsB.PlayerName
      if nameA and nameB and nameA ~= nameB then
        return nameA < nameB
      elseif nameA and not nameB then
        return true
      elseif nameB and not nameA then
        return false
      end

      -- Full tie. Stable fallback by button identity keeps strict weak ordering.
      return tostring(playerA) < tostring(playerB)
    end

    local function PlayerSortingByClassName(playerA, playerB)
      local detailsA = playerA.PlayerDetails
      local detailsB = playerB.PlayerDetails

      -- Class tier in Blizzard's standard order. PlayerClass is already
      -- string.upper(classToken). PVPScoreInfo.classToken is NeverSecret,
      -- and UnitClass / GetSpecializationInfoByID returns are non-secret,
      -- so direct compare is safe across every source path.
      local classA = BlizzardsSortOrder[detailsA.PlayerClass] or math_huge
      local classB = BlizzardsSortOrder[detailsB.PlayerClass] or math_huge
      if classA ~= classB then
        return classA < classB
      end

      -- Alphabetical name tiebreak. PVPScoreInfo.name is NeverSecret in
      -- every match state (lobby, active, post-match), so the compare
      -- can't taint.
      local nameA = detailsA.PlayerName
      local nameB = detailsB.PlayerName
      if nameA and nameB and nameA ~= nameB then
        return nameA < nameB
      elseif nameA and not nameB then
        return true
      elseif nameB and not nameA then
        return false
      end

      -- Full tie. Stable fallback by button identity keeps strict weak ordering.
      return tostring(playerA) < tostring(playerB)
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
      local newPlayerOrder = {}
      for i = 1, #self.PlayerList do
        table.insert(newPlayerOrder, self.PlayerList[i])
      end

      -- Allies sort by role tier → name (UnitGroupRolesAssigned, raid/party
      -- UnitClass, and ally names are all non-secret). BG enemies sort by
      -- class tier → name — both PVPScoreInfo.classToken and .name are
      -- NeverSecret per Blizzard's API docs. Enemy role is NOT used in the
      -- comparator: talentSpec / roleAssigned remain secret in active match,
      -- which would taint role-based compares.
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
            -- Arena unit IDs are numeric tokens, safe to sort by.
            table.sort(newPlayerOrder, PlayerSortingByArenaUnitID)
          end
        else
          -- Arena allies: prefer role-based sort (user-configured priority
          -- via RoleSortingOrder). Fall back to CRFSort_Group_ (unitID order)
          -- when role data isn't yet populated for everyone.
          local allHaveRoles = true
          for i = 1, #newPlayerOrder do
            if not newPlayerOrder[i].PlayerDetails.PlayerRole then
              allHaveRoles = false
              break
            end
          end
          if allHaveRoles then
            table.sort(newPlayerOrder, PlayerSortingByRoleClassName)
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
            end
          end
        end
      else
        -- BG. Allies by role (RoleSortingOrder setting). Enemies by class+name.
        if self.PlayerType == BattleGroundEnemies.consts.PlayerTypes.Allies then
          table.sort(newPlayerOrder, PlayerSortingByRoleClassName)
        else
          table.sort(newPlayerOrder, PlayerSortingByClassName)
        end
      end

      local orderChanged = false
      for i = 1, math_max(#newPlayerOrder, #self.CurrentPlayerOrder) do --players can leave or join so #self.CurrentPlayerOrder can be unequal to #newPlayerOrder
        if newPlayerOrder[i] ~= self.CurrentPlayerOrder[i] then
          orderChanged = true
          break
        end
      end

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

-- Direct unit-token → ally button map. Rebuilt by UpdateAllUnitIDs after
-- GROUP_ROSTER_UPDATE. Allies are driven exclusively by stable raidN/partyN/
-- player tokens — no PID matching, no scoreboard, no cross-side contamination.
BattleGroundEnemies.Allies.tokenToButton = {}

-- Resolve any incoming unitID to an ally button, or nil if not one of ours.
-- Fast path: direct token lookup (covers party/raid/player event tokens).
-- Fallback A: UnitIsUnit iteration for arbitrary tokens (target, focus,
-- nameplateN, mouseover, etc). Bounded at ≤40 iterations in a BG, ≤5 in
-- arena. UnitIsUnit is SecretWhenUnitComparisonRestricted — in 12.0.5 PvP
-- it returns a SECRET BOOLEAN for compound tokens like raid1target (testing
-- it in a boolean context would taint, crashing the addon). We pre-filter
-- via issecretvalue and silently skip such pairs.
-- Fallback B: name match via GetUnitName (also pcall + secret-guarded).
-- No PID, no fingerprinting. Never touches the enemy matcher.
function BattleGroundEnemies.Allies:GetAllyButtonByUnitID(unitID)
  if not unitID then
    return nil
  end
  -- Same non-player rejection as the enemy matcher: pets / NPCs / totems
  -- must never resolve to a player button. Without this, a pet whose name
  -- collides with an ally would false-match via the name fallback below.
  -- UnitIsPlayer isn't in the SecretWhenUnitComparisonRestricted family,
  -- but pcall anyway for compound-token safety. Only reject on EXPLICIT
  -- false; nil/secret falls through so we don't accidentally drop a
  -- confirmed ally.
  local okPlayer, isPlayer = pcall(UnitIsPlayer, unitID)
  if okPlayer and isPlayer == false then
    return nil
  end
  local direct = self.tokenToButton[unitID]
  if direct then
    return direct
  end
  for token, btn in pairs(self.tokenToButton) do
    local ok, same = pcall(UnitIsUnit, unitID, token)
    -- MUST check issecretvalue(same) BEFORE any boolean test on `same`.
    -- Touching a secret boolean in a truthy check taints the entire call
    -- stack. issecretvalue is designed to accept secret values without
    -- tainting — it's the only safe probe we have.
    if ok and not (issecretvalue and issecretvalue(same)) and same then
      return btn
    end
  end
  -- Name fallback — ally names may be non-secret (GetUnitName guarded).
  -- Canonicalize: GetUnitName returns short "Name" for same-realm, but
  -- Players[] is keyed by full "Name-Realm" since the canonicalization
  -- refactor (Main.lua CanonicalName helper). Without this canonicalize,
  -- same-realm allies would silently miss the name fallback and fall
  -- through to the no-match return.
  local ok, name = pcall(GetUnitName, unitID, true)
  if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
    local btn = self.Players[BattleGroundEnemies:CanonicalName(name)]
    if btn then
      return btn
    end
  end
  return nil
end

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

function BattleGroundEnemies.Allies:AddGroupMember(name, isLeader, isAssistant, classToken, unitID, raidRole)
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
        -- Raid-assigned role ("MAINTANK" / "MAINASSIST"); empty string / nil
        -- for regular members and for non-raid groups (parties). Used as a
        -- higher-priority signal than UnitGroupRolesAssigned in the sort
        -- comparator so MT/MA tiers can come before plain TANK.
        raidRole = raidRole,
      },
    })
  end

  if isLeader then
    self.groupLeader = name
  end
  if isAssistant then
    table_insert(self.assistants, name)
  end
end

function BattleGroundEnemies.Allies:UpdateAllUnitIDs()
  --it happens that numGroupMembers is higher than the value of the maximal players for that battleground, for example 15 in a 10 man bg, thats why we wipe AllyUnitIDToAllyDetails
  wipe(self.tokenToButton)
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

    -- Rebuild the token → ally button map so GetAllyButtonByUnitID and
    -- all ally-side event handlers see current assignments. Must run
    -- every pass since raid indices shift when members leave mid-match.
    if allyButton and allyButton.unit then
      self.tokenToButton[allyButton.unit] = allyButton
    end
  end
end

function BattleGroundEnemies.Enemies:ChangeName(oldName, newName) --only used in arena when players switch from "arenaX" to a real name
  -- oldName is always a unitID literal ("arenaN"); newName is filtered to
  -- non-secret upstream in CreateArenaEnemies before reaching here.
  --
  -- Canonicalize both ends — Players[] is keyed by CanonicalName output
  -- (Main.lua:CanonicalName). The arena-prep flow stored under key
  -- "arenaN-Realm" because CanonicalName appended the user's realm to the
  -- token literal. Lookups must canonicalize the same way or they miss.
  -- newName is normally already in "Name-Realm" form (chat / arena reveal),
  -- but pass it through CanonicalName for idempotency in case a same-realm
  -- short form ever reaches here.
  local oldKey = BattleGroundEnemies:CanonicalName(oldName)
  local newKey = BattleGroundEnemies:CanonicalName(newName)
  local playerButton = self.Players[oldKey]

  if playerButton then
    playerButton.PlayerDetails.PlayerName = newKey
    playerButton:PlayerDetailsChanged()

    self.Players[newKey] = playerButton
    self.Players[oldKey] = nil
  end
end

function BattleGroundEnemies.Enemies:CreateArenaEnemies()
  if not BattleGroundEnemies.states.real.isInArena then
    return
  end

  -- #1 ghost-frame gate (arena enemy path). Arena enemies come from the
  -- ArenaPlayers source -- the enemy build path that the UBS gate does NOT
  -- cover -- so without this, disabling enemies in an arena bracket would still
  -- build hidden enemy frames. We derive the decision from a reliable opponent
  -- count: SetRealPlayerCount runs SelectPlayerCountProfile (sets
  -- playerType/playerCountConfig synchronously), then ShouldBeEnabled reads
  -- those config fields -- which is correct even mid-combat, unlike self.enabled
  -- (which lags past InCombatLockdown). Live count first, falling back to the
  -- prep-phase spec count so disabled enemies are suppressed during arena prep
  -- too. When the count is 0 we don't yet have a fresh profile, so we fall
  -- through to the normal build below -- which produces 0 buttons anyway (the
  -- loop finds no opponents), so the enabled case is never broken.
  local opponentCount = (GetNumArenaOpponents and GetNumArenaOpponents()) or 0
  if opponentCount == 0 and GetNumArenaOpponentSpecs then
    opponentCount = GetNumArenaOpponentSpecs() or 0
  end
  if opponentCount > 0 then
    self:SetRealPlayerCount(opponentCount)
    if not self:ShouldBeEnabled() then
      -- Enemy frames off for this bracket: tear down ALL enemy buttons. Must use
      -- RemoveAllPlayersFromAllSources, NOT just wipe the ArenaPlayers source:
      -- the enemy AfterPlayerSourceUpdate falls back to the Scoreboard source
      -- when ArenaPlayers is empty (Mainframe.lua ~429-438), and Scoreboard IS
      -- populated in solo shuffle / arenas with a scoreboard -- so wiping only
      -- ArenaPlayers would rebuild enemies from scoreboard and defeat the gate.
      -- Wiping every source yields 0 buttons. Mirrors the UBS enemy gate.
      self:RemoveAllPlayersFromAllSources()
      return
    end
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
      elseif type(name) ~= "nil" then
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
  -- 12.0.5: iterate PlayerList (not pairs(self.Players)) so secret-named
  -- buttons are visible — self.Players only holds non-secret-named entries.
  if self.PlayerList then
    for i = 1, #self.PlayerList do
      local btn = self.PlayerList[i]
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
  -- Focus token attachment removed — was duplicating the work of
  -- BattleGroundEnemies:PLAYER_FOCUS_CHANGED in Main.lua, which uses the
  -- click stash to map "focus" to the correct button. This handler used
  -- the matcher (no stash), so on same-class twins it could attach the
  -- Focus token to the wrong button before the stash-based handler
  -- corrected it — same wrong-frame flash bug we just fixed for target.
  -- FocusTarget (your focus's target — a different token) is unique to
  -- this handler, so it stays.
  UpdateUnitIDForToken(self, "FocusTarget", "focustarget")
end

function BattleGroundEnemies.Enemies:UPDATE_MOUSEOVER_UNIT()
  -- Persistently attach the Mouseover UnitID to the matched button (and
  -- detach it from any prior button). Sibling handler at
  -- BattleGroundEnemies:UPDATE_MOUSEOVER_UNIT in Main.lua does a one-shot
  -- snapshot read of health/power via UpdateAll. Both run on the same
  -- event; the matcher call here hits scanCycleCache (already populated
  -- by the sibling). Don't consolidate — different abstractions.
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

-- UNIT_DIED: fires for any unit death, payload is unitGUID (secret under
-- PvP identity restrictions per SecretWhenUnitIdentityRestricted flag in
-- the Blizzard API docs). We ignore the GUID entirely and instead sweep
-- every button with a live unit token, calling UnitIsDeadOrGhost on each.
-- Catches deaths where the nameplate despawned before UNIT_HEALTH fired
-- with dead status, which was the old reliable detection path.
function BattleGroundEnemies.Enemies:UNIT_DIED()
  if not self.PlayerList then
    return
  end
  for i = 1, #self.PlayerList do
    local btn = self.PlayerList[i]
    local uid = btn.unitID
    if uid and UnitExists(uid) and UnitIsDeadOrGhost(uid) then
      btn:PlayerIsDead()
    end
  end
end

BattleGroundEnemies.Enemies:RegisterEvent("UNIT_DIED")
