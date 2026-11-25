local Data = select(2, ...)
local C_PvP = C_PvP
local GetInstanceInfo = GetInstanceInfo
local IsRatedBattleground = IsRatedBattleground

local Match = { SupportsArena = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE }
Data.Match = Match

local bgMaxPlayerCorrections = {
  -- Classic/Legacy IDs (may still be used in some contexts)
  [443] = 10, -- Warsong Gulch (Classic)
  [461] = 15, -- Arathi Basin (Classic)
  [401] = 40, -- Alterac Valley (Classic)
  [607] = 15, -- Strand of the Ancients

  -- Epic Battlegrounds (40v40)
  [30] = 40, -- Alterac Valley
  [628] = 40, -- Isle of Conquest
  [2118] = 40, -- Battle for Wintergrasp
  [2197] = 40, -- Korrak's Revenge (Brawl)
  [1280] = 40, -- Tarren Mill vs Southshore (Brawl)
  [1191] = 40, -- Ashran

  -- 15v15 Battlegrounds
  [566] = 15, -- Eye of the Storm
  [968] = 15, -- Eye of the Storm (alternate)
  [2107] = 15, -- Arathi Basin
  [2245] = 15, -- Deepwind Gorge
  [1105] = 15, -- Deepwind Gorge (alternate ID)

  -- 10v10 Battlegrounds
  [726] = 10, -- Twin Peaks
  [761] = 10, -- Battle for Gilneas
  [998] = 10, -- Temple of Kotmogu
  [727] = 10, -- Silvershard Mines
  [1803] = 10, -- Seething Shore
  [2656] = 10, -- Deephaul Ravine
  [2106] = 10, -- Warsong Gulch
}

function Match.GetBattlegroundTeamSize()
  if C_PvP and C_PvP.IsSoloRBG and C_PvP.IsSoloRBG() then
    return 8
  end
  if C_PvP and C_PvP.IsRatedBattleground and C_PvP.IsRatedBattleground() then
    return 10
  end
  local _, _, _, _, maxPlayers, _, _, instanceID = GetInstanceInfo()
  if instanceID and bgMaxPlayerCorrections[instanceID] then
    return bgMaxPlayerCorrections[instanceID]
  end
  return maxPlayers or 0
end

function Match.GetBattlegroundTypes()
  if C_PvP then
    return not not C_PvP.IsRatedBattleground and C_PvP.IsRatedBattleground(),
      not not C_PvP.IsSoloRBG and C_PvP.IsSoloRBG()
  end
  return not not IsRatedBattleground and IsRatedBattleground(), false
end
