-- luacheck: read globals GetBattlefieldWinner
local Data = select(2, ...)
local BattlegroundTeamSizes = Data.BattlegroundTeamSizes
local GetBattlefieldWinner = GetBattlefieldWinner
local GetInstanceInfo = GetInstanceInfo
local IsRatedMap = C_PvP.IsRatedMap

local Match = { SupportsArena = true }
Data.Match = Match

function Match.GetBattlegroundTypes()
  return IsRatedMap(), false
end

function Match.GetBattlegroundTeamSize()
  local _, _, _, _, maxPlayers, _, _, instanceID = GetInstanceInfo()
  return BattlegroundTeamSizes[instanceID] or maxPlayers or 0
end

function Match.UpdateFromScoreboard(addon)
  local state = addon.states.real
  if not addon.enabled or not (state.isInBattleground or state.isInArena) then
    return false
  end
  if GetBattlefieldWinner() ~= nil then
    addon:Disable()
    return false
  end
  return true
end
