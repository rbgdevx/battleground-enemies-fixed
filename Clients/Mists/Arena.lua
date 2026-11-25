-- luacheck: read globals ArenaPrepFrames ArenaUtil GetInspectSpecialization
local Data = select(2, ...)
local ArenaUnitExists = ArenaUtil.UnitExists
local GetArenaOpponentSpec = GetArenaOpponentSpec
local GetNumArenaOpponents = GetNumArenaOpponents
local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo
local GetSpecializationInfoByID = GetSpecializationInfoByID

local Arena = {
  RefreshPowerOnOpponentUpdate = true,
  GetInspectSpecialization = GetInspectSpecialization,
  ReadTrinket = C_PvP.GetArenaCrowdControlInfo,
}
Data.Arena = Arena

function Arena.CanShowPower(index)
  return ArenaUnitExists("arena" .. index)
end

function Arena.GetPlayerSpecName()
  local index = GetSpecialization()
  if index then
    local _, name = GetSpecializationInfo(index)
    return name
  end
end

function Arena.GetOpponentSpec(index)
  local specID, gender = GetArenaOpponentSpec(index)
  if specID and specID > 0 then
    local _, name, _, _, _, class = GetSpecializationInfoByID(specID, gender)
    return name, class and string.upper(class)
  end
end

function Arena.Initialize(addon)
  if GetNumArenaOpponents() > 0 then
    addon:CheckForArenaEnemies()
  end
end

function Arena.GetPrepFrames()
  return ArenaPrepFrames
end
