local _, Data = ...
local BattleGroundEnemies = BattleGroundEnemies

local L = Data.L
local ObjectiveIcon = {}
Data.ObjectiveIcon = ObjectiveIcon

function ObjectiveIcon.DefaultSettings()
  return {
    Enabled = true,
    Parent = "Button",
    ActivePoints = 1,
    Points = {
      {
        Point = "LEFT",
        RelativeFrame = "Button",
        RelativePoint = "RIGHT",
        OffsetX = 0,
      },
    },
    Text = {
      FontSize = 15,
      FontOutline = "OUTLINE", -- Normal (overrides the global Text default of None)
      EnableShadow = true,
      ShadowColor = { 0, 0, 0, 0.8 },
      ShadowOffsetX = 1,
      ShadowOffsetY = -1,
    },
    UseButtonHeightAsHeight = true,
    UseButtonHeightAsWidth = true,
  }
end

function ObjectiveIcon.TextOptions(settings)
  return {
    type = "group",
    name = L.Text,
    inline = true,
    order = 4,
    get = function(option)
      return Data.GetOption(settings, option)
    end,
    set = function(option, ...)
      return Data.SetOption(settings, option, ...)
    end,
    args = Data.AddNormalTextSettings(settings, nil, true, true),
  }
end

function ObjectiveIcon.Create(playerButton)
  local frame = CreateFrame("frame", nil, playerButton)
  frame:SetFrameLevel(playerButton:GetFrameLevel() + 5)

  frame.Icon = frame:CreateTexture(nil, "BORDER")
  frame.Icon:SetAllPoints()

  frame:SetScript("OnSizeChanged", function(self, width, height)
    BattleGroundEnemies.CropImage(self.Icon, width, height)
  end)
  frame:Hide()

  return frame
end
