-- luacheck: read globals ArenaUtil PlayerUtil
local Data = select(2, ...)
local IsRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
local GetActiveMatchState = C_PvP.GetActiveMatchState
local PvPMatchState = Enum.PvPMatchState
local ArenaUnitExists = IsRetail and ArenaUtil.UnitExists

local Arena = {
  RefreshPowerOnOpponentUpdate = IsRetail,
  GetPlayerSpecName = IsRetail and PlayerUtil.GetSpecName,
  GetInspectSpecialization = IsRetail and C_SpecializationInfo.GetInspectSpecialization,
}
Data.Arena = Arena

function Arena.CanShowPower(index)
  return GetActiveMatchState() == PvPMatchState.Engaged and (not IsRetail or ArenaUnitExists("arena" .. index))
end
