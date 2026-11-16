local _, Data = ...

local _G = _G
local ipairs = ipairs
local pairs = pairs
local select = select
local type = type
local tostring = tostring
local strlenutf8 = _G.strlenutf8
local wipe = wipe
local CopyTable = CopyTable
local Mixin = Mixin

local GetRealmName = GetRealmName
local RegionalUniqueNamesEnabled = RegionalUniqueNamesEnabled
local UnitNameUnmodified = _G.UnitNameUnmodified
local C_GameRules = _G.C_GameRules
local UnitClass = UnitClass
local defaultSettings = Data.defaultSettings
local legacyProfileDefaults = Data.legacyProfileDefaults
local newInstallProfileDefaults = Data.newInstallProfileDefaults
local UpgradeProfile = Data.UpgradeProfile
local SetCurrentDbVersion = Data.SetCurrentDbVersion

local Database = {}
Data.Database = Database

local function copyDefaults(defaults, db)
  if type(db) ~= "table" then
    db = {}
  end

  for key, value in pairs(defaults) do
    if type(value) == "table" then
      db[key] = copyDefaults(value, db[key])
    elseif type(db[key]) ~= type(value) then
      db[key] = value
    end
  end

  return db
end

local function splitProfileDefaults(defaults)
  local profile = CopyTable(defaults, true)
  local customBrackets = {}
  for _, playerType in ipairs({ "Allies", "Enemies" }) do
    local side = CopyTable(defaults[playerType], true)
    customBrackets[playerType] = side.customPlayerCountConfigs["**"]
    side.customPlayerCountConfigs = {}
    profile[playerType] = side
  end
  return { profile = profile, customBrackets = customBrackets }
end

local function applyProfileDefaults(profile, defaults)
  copyDefaults(defaults.profile, profile)
  for playerType, template in pairs(defaults.customBrackets) do
    local brackets = profile[playerType].customPlayerCountConfigs
    brackets["**"] = nil
    for _, bracket in pairs(brackets) do
      if type(bracket) == "table" then
        copyDefaults(template, bracket)
      end
    end
  end
end

local function getProfileKeys()
  local name, surname = UnitNameUnmodified("player")
  local realm, character

  -- Match the character keys already stored by the previous database.
  if RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
    character = surname and name .. " " .. tostring(surname) or name
    if C_GameRules.IsGameRuleActive(Enum.GameRule.HardcoreRuleset) then
      realm = "Hardcore"
    elseif C_GameRules.IsGameRuleActive(Enum.GameRule.RPRuleset) then
      realm = "RP"
    elseif C_GameRules.IsGameRuleActive(Enum.GameRule.PvPRuleset) then
      realm = "PvP"
    else
      realm = "PvE"
    end
  else
    realm = GetRealmName()
    character = name .. " - " .. realm
  end

  return { char = character, realm = realm, class = select(2, UnitClass("player")) }
end

local function validProfileName(name)
  if type(name) ~= "string" then
    return false
  end

  local length = strlenutf8(name)
  return length > 0 and length <= 50 and not name:find("^ +$")
end

local function restoreStoredProfiles(profiles, defaults)
  local aceDefaults = splitProfileDefaults(legacyProfileDefaults)
  for _, profile in pairs(profiles) do
    if type(profile) == "table" then
      UpgradeProfile(profile)
      -- Infer missing AceDB values from the .7 rollback defaults.
      applyProfileDefaults(profile, aceDefaults)
      applyProfileDefaults(profile, defaults)
    end
  end
end

local function activateProfile(database, name)
  local profile = database.sv.profiles[name]
  if type(profile) ~= "table" then
    profile = {}
    applyProfileDefaults(profile, database.profileDefaults)
    SetCurrentDbVersion(profile)
    database.sv.profiles[name] = profile
  end

  database.keys.profile = name
  database.sv.profileKeys[database.keys.char] = name
  database.profile = profile
end

function Database:Initialize(addon)
  local saved = _G.BattleGroundEnemiesDB
  local existingInstall = type(saved) == "table"
  if not existingInstall then
    saved = {}
  end

  copyDefaults({ profiles = {}, profileKeys = {}, global = {} }, saved)
  -- Keep the install's starting defaults for new profiles and explicit resets.
  if type(saved.profileDefaults) ~= "table" then
    saved.profileDefaults = CopyTable(existingInstall and legacyProfileDefaults or newInstallProfileDefaults)
  end
  saved.profileDefaults = copyDefaults(defaultSettings.profile, saved.profileDefaults)
  _G.BattleGroundEnemiesDB = saved

  self.addon = addon
  self.sv = saved
  self.defaults = { profile = saved.profileDefaults, global = defaultSettings.global }
  self.profileDefaults = splitProfileDefaults(saved.profileDefaults)
  self.global = saved.global
  self.keys = getProfileKeys()

  restoreStoredProfiles(saved.profiles, self.profileDefaults)
  copyDefaults(defaultSettings.global, self.global)

  local selected = saved.profileKeys[self.keys.char]
  activateProfile(self, validProfileName(selected) and selected or "Default")
  return self
end

function Database:GetCurrentProfile()
  return self.keys.profile
end

function Database:GetProfiles(names)
  names = names and wipe(names) or {}
  for name in pairs(self.sv.profiles) do
    names[#names + 1] = name
  end
  return names
end

function Database:SetProfile(name)
  if validProfileName(name) and name ~= self.keys.profile then
    activateProfile(self, name)
    self.addon:ProfileChanged()
  end
end

function Database:CopyProfile(name)
  local source = self.sv.profiles[name]
  if type(source) == "table" and name ~= self.keys.profile then
    local copied = CopyTable(source)
    Mixin(wipe(self.profile), copied)
    self.addon:ProfileChanged()
  end
end

function Database:ResetProfile()
  wipe(self.profile)
  applyProfileDefaults(self.profile, self.profileDefaults)
  SetCurrentDbVersion(self.profile)
  self.addon:ProfileReset()
end

function Database:DeleteProfile(name)
  if name ~= self.keys.profile and self.sv.profiles[name] then
    self.sv.profiles[name] = nil
    for character, selected in pairs(self.sv.profileKeys) do
      if selected == name then
        self.sv.profileKeys[character] = nil
      end
    end
  end
end
