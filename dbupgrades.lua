local _, Data = ...

local ipairs = ipairs
local pairs = pairs
local type = type

local currentDBVersion = 2
local playerTypes = { "Allies", "Enemies" }
local legacyPlayerCounts = { "5", "15", "40" }

local function copyMissingSettings(settings, legacy)
  for key, value in pairs(legacy) do
    if settings[key] == nil then
      settings[key] = value
    elseif type(settings[key]) == "table" and type(value) == "table" then
      copyMissingSettings(settings[key], value)
    end
  end
end

local function upgradePlayerCountConfigs(side)
  local configs = type(side.playerCountConfigs) == "table" and side.playerCountConfigs or {}
  for index, playerCount in ipairs(legacyPlayerCounts) do
    local oldConfig = side[playerCount]
    if type(oldConfig) == "table" then
      local config = type(configs[index]) == "table" and configs[index] or {}
      copyMissingSettings(config, oldConfig)
      configs[index] = config
      side[playerCount] = nil
    end
  end
  side.playerCountConfigs = configs
end

local function setCurrentDbVersion(profile)
  profile.dbVersion = currentDBVersion
end
Data.SetCurrentDbVersion = setCurrentDbVersion

function Data.UpgradeProfile(profile)
  local version = profile.dbVersion
  if type(version) ~= "number" then
    version = 0
  end
  if version >= currentDBVersion then
    return
  end

  if version < 1 then
    for _, playerType in ipairs(playerTypes) do
      if type(profile[playerType]) == "table" then
        upgradePlayerCountConfigs(profile[playerType])
      end
    end
  end
  if type(profile.Font) == "string" then
    local text = type(profile.Text) == "table" and profile.Text or {}
    if type(text.Font) ~= "string" then
      text.Font = profile.Font
    end
    profile.Text = text
    profile.Font = nil
  end
  setCurrentDbVersion(profile)
end
