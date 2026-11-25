local Data = select(2, ...)
local GetScoreInfo = C_PvP.GetScoreInfo
local GetScoreInfoByPlayerGuid = C_PvP.GetScoreInfoByPlayerGuid
local GetNumBattlefieldScores = GetNumBattlefieldScores
local GetNumGroupMembers = GetNumGroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local GetPlayerInfoByGUID = GetPlayerInfoByGUID
local IsInRaid = IsInRaid
local SetBattlefieldScoreFaction = SetBattlefieldScoreFaction
local UnitGUID = UnitGUID

local Scoreboard = {
  AllTeams = -1,
  ReadWhileFiltered = true,
  GetScoreInfo = GetScoreInfo,
  HasTalentSpecs = true,
}
Data.Scoreboard = Scoreboard

function Scoreboard.IsVisible()
  return (PVPMatchScoreboard and PVPMatchScoreboard:IsShown()) or (PVPMatchResults and PVPMatchResults:IsShown())
end

local function PVPMatchScoreboard_OnHide()
  if PVPMatchScoreboard.selectedTab ~= 1 then
    -- user was looking at another tab than all players
    SetBattlefieldScoreFaction() -- request a UPDATE_BATTLEFIELD_SCORE
  end
end

function Scoreboard.OnLogin()
  if PVPMatchScoreboard then
    PVPMatchScoreboard:HookScript("OnHide", PVPMatchScoreboard_OnHide)
  end
end

local SCORE_ROW_FIELDS = {
  "name",
  "guid",
  "killingBlows",
  "honorableKills",
  "deaths",
  "honorGained",
  "faction",
  "raceName",
  "className",
  "classToken",
  "damageDone",
  "healingDone",
  "rating",
  "ratingChange",
  "prematchMMR",
  "mmrChange",
  "postmatchMMR",
  "talentSpec",
  "honorLevel",
  "roleAssigned",
  "stats",
  -- GetPlayerInfoByGUID-derived (only written when guid resolves):
  "localizedClass",
  "englishClass",
  "localizedRace",
  "englishRace",
  "sex",
  "realmName",
}

function Scoreboard.ReadRow(index, result)
  local scoreInfo = GetScoreInfo(index)
  if not scoreInfo then
    return
  end

  -- Explicit field copy instead of Mixin({}, scoreInfo).
  -- Mixin does `for k, v in pairs(scoreInfo)` — but in 12.0.5 PvP the table
  -- returned by C_PvP.GetScoreInfo is a protected/secret table that CANNOT
  -- be iterated while our execution is tainted ("attempted to iterate a
  -- table that cannot be accessed while tainted (execution tainted by
  -- BattleGroundEnemiesFixed)"). Field ACCESS is still allowed (the rest of
  -- this function and UBS already read scoreInfo.guid / row.name directly),
  -- so copy each documented PVPScoreInfo field by name. Every assignment is a
  -- pure pass-through, so possibly-secret fields (talentSpec, rating,
  -- honorGained, damageDone, etc.) carry over EXACTLY as Mixin did — no
  -- comparison, no arithmetic, no use as a table key. Behaviorally identical
  -- to the old Mixin, minus the taint crash. Also eliminates the per-row
  -- Mixin pairs-copy allocation (improvement #10), which in a 40-row epic
  -- lobby ran for every row on every UBS tick.
  -- Field list mirrors PVPScoreInfo in
  -- Blizzard_APIDocumentationGenerated/PvpInfoDocumentation.lua.
  -- #10a: `result` is a pooled, reused table. Clear EVERY field before writing
  -- so a prior occupant's data can't survive — especially the conditional
  -- GetPlayerInfoByGUID fields below, which are skipped when guid is nil. The
  -- clear + writes are pure assignments (no compare / arith / table-key), so
  -- possibly-secret fields stay taint-safe exactly as the old fresh-literal did.
  for fi = 1, #SCORE_ROW_FIELDS do
    result[SCORE_ROW_FIELDS[fi]] = nil
  end
  result.name = scoreInfo.name
  result.guid = scoreInfo.guid
  result.killingBlows = scoreInfo.killingBlows
  result.honorableKills = scoreInfo.honorableKills
  result.deaths = scoreInfo.deaths
  result.honorGained = scoreInfo.honorGained
  result.faction = scoreInfo.faction
  result.raceName = scoreInfo.raceName
  result.className = scoreInfo.className
  result.classToken = scoreInfo.classToken
  result.damageDone = scoreInfo.damageDone
  result.healingDone = scoreInfo.healingDone
  result.rating = scoreInfo.rating
  result.ratingChange = scoreInfo.ratingChange
  result.prematchMMR = scoreInfo.prematchMMR
  result.mmrChange = scoreInfo.mmrChange
  result.postmatchMMR = scoreInfo.postmatchMMR
  result.talentSpec = scoreInfo.talentSpec
  result.honorLevel = scoreInfo.honorLevel
  result.roleAssigned = scoreInfo.roleAssigned
  result.stats = scoreInfo.stats

  if not scoreInfo.guid then
    return result
  end

  local ok, localizedClass, englishClass, localizedRace, englishRace, sex, _, realmName =
    pcall(GetPlayerInfoByGUID, scoreInfo.guid)

  if ok then
    result.localizedClass = localizedClass
    result.englishClass = englishClass
    result.localizedRace = localizedRace
    result.englishRace = englishRace
    result.sex = sex
    result.realmName = realmName
  end

  return result
end

local function getPeerNames(addon, ownName, usesSurnames, isArenaParty)
  local names = {}
  if isArenaParty then
    for index = 1, GetNumGroupMembers() - 1 do
      local name = addon:GetCanonicalUnitName("party" .. index)
      if name then
        names[name] = true
      end
    end
  elseif IsInRaid() then
    for index = 1, GetNumGroupMembers() or 0 do
      local name
      if usesSurnames then
        name = addon:GetCanonicalUnitName("raid" .. index)
      else
        name = GetRaidRosterInfo(index)
      end
      if type(name) == "string" and not (issecretvalue and issecretvalue(name)) and name ~= ownName then
        names[name] = true
      end
    end
  end
  return names
end

local function confirmTeamWithPeers(addon, names, faction, isArenaParty, requiredPeers)
  local agreed = 0
  for index = 1, GetNumBattlefieldScores() do
    local row = GetScoreInfo(index)
    local name = row and row.name
    if isArenaParty and type(name) == "string" then
      name = addon:CanonicalName(name)
    end
    if row and type(name) == "string" and row.faction ~= nil and names[name] then
      if row.faction ~= faction then
        return
      end
      agreed = agreed + 1
      if agreed >= requiredPeers then
        return faction
      end
    end
  end
end

function Scoreboard.FindAllyFaction(addon, usesSurnames)
  local ok, row = pcall(GetScoreInfoByPlayerGuid, UnitGUID("player"))
  -- A tainted execution path can flag the scoreboard name as secret.
  if
    not ok
    or not row
    or row.faction == nil
    or type(row.name) ~= "string"
    or (issecretvalue and issecretvalue(row.name))
  then
    return
  end

  local isArena = addon.states.real.isInArena
  local isArenaParty = isArena and not IsInRaid()
  local names = getPeerNames(addon, row.name, usesSurnames, isArenaParty)
  if not next(names) then
    return
  end

  local requiredPeers = isArena and GetNumGroupMembers() == 2 and 1 or 2
  return confirmTeamWithPeers(addon, names, row.faction, isArenaParty, requiredPeers)
end
