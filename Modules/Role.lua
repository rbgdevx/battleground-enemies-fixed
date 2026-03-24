---@type string
local AddonName = ...
---@class Data
local Data = select(2, ...)
---@class BattleGroundEnemies
local BattleGroundEnemies = BattleGroundEnemies
local L = Data.L
local GetTexCoordsForRoleSmallCircle = GetTexCoordsForRoleSmallCircle
  or function(role)
    if role == "TANK" then
      return 0, 19 / 64, 22 / 64, 41 / 64
    elseif role == "HEALER" then
      return 20 / 64, 39 / 64, 1 / 64, 20 / 64
    elseif role == "DAMAGER" then
      return 20 / 64, 39 / 64, 22 / 64, 41 / 64
    else
      error("Unknown role: " .. tostring(role))
    end
  end

local defaultSettings = {
  Enabled = true,
  Parent = "healthBar",
  Width = 12,
  Height = 12,
  ActivePoints = 1,
  Points = {
    {
      Point = "LEFT",
      RelativeFrame = "healthBar",
      RelativePoint = "LEFT",
      OffsetX = 4,
      OffsetY = 0,
    },
  },
}

local role = BattleGroundEnemies:NewButtonModule({
  moduleName = "Role",
  localizedModuleName = ROLE,
  defaultSettings = defaultSettings,
  options = nil,
  enabledInThisExpansion = not not GetSpecializationRole,
  attachSettingsToButton = false,
  flags = {
    SetZeroWidthWhenDisabled = true,
  },
})

function role:AttachToPlayerButton(playerButton)
  playerButton.Role = CreateFrame("Frame", nil, playerButton)
  playerButton.Role.Icon = playerButton.Role:CreateTexture(nil, "OVERLAY")
  playerButton.Role.Icon:SetAllPoints()

  playerButton.Role.ApplyAllSettings = function(self)
    if not self.config then
      return
    end
    local playerDetails = playerButton.PlayerDetails
    if not playerDetails then
      return
    end
    local specData = playerButton:GetSpecData()
    -- Use spec-based role first, then fall back to PlayerRole (which includes group role fallback)
    local roleID = (specData and specData.roleID) or playerDetails.PlayerRole
    -- Only show icon if roleID is a valid string role (not "NONE", nil, or numeric)
    if roleID and (roleID == "TANK" or roleID == "HEALER" or roleID == "DAMAGER") then
      self.Icon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
      self.Icon:SetTexCoord(GetTexCoordsForRoleSmallCircle(roleID))
    end
  end
  return playerButton.Role
end
