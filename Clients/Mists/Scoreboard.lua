-- luacheck: read globals GetBattlefieldArenaFaction GetBattlefieldScore WorldStateScoreFrame
local Data = select(2, ...)
local GetBattlefieldArenaFaction = GetBattlefieldArenaFaction
local GetBattlefieldScore = GetBattlefieldScore
local GetNumBattlefieldScores = GetNumBattlefieldScores

local Scoreboard = {}
Data.Scoreboard = Scoreboard

function Scoreboard.IsVisible()
  return WorldStateScoreFrame:IsShown()
end

function Scoreboard.ReadRow(index, row)
  local name, _, _, _, _, faction, _, raceName, className, classToken = GetBattlefieldScore(index)
  if not name then
    return
  end
  row.name = name
  row.faction = faction
  row.raceName = raceName
  row.className = className
  row.classToken = classToken
  return row
end

function Scoreboard.FindAllyFaction(addon)
  local faction = GetBattlefieldArenaFaction()
  local playerName = addon.UserDetails.PlayerName
  for index = 1, GetNumBattlefieldScores() do
    local name, _, _, _, _, rowFaction = GetBattlefieldScore(index)
    if name and addon:CanonicalName(name) == playerName then
      if faction == rowFaction then
        return faction
      end
      return
    end
  end
end

function Scoreboard.HasRosterChanged(rows, enemyFaction)
  local enemyIndex = 0
  for index = 1, GetNumBattlefieldScores() do
    local name, _, _, _, _, faction, _, _, _, classToken = GetBattlefieldScore(index)
    if faction == enemyFaction and name and classToken then
      enemyIndex = enemyIndex + 1
      local row = rows[enemyIndex]
      if not row or row.name ~= name or row.classToken ~= classToken then
        return true
      end
    end
  end
  return enemyIndex ~= #rows
end
