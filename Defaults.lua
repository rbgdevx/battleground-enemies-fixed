---@type string
local AddonName = ...
---@class Data
local Data = select(2, ...)

local allieDefaults15man = {
  Enabled = false,
  minPlayerCount = 6,
  maxPlayerCount = 15,

  Position_X = 300,
  Position_Y = 600,
  BarWidth = 185,
  BarHeight = 35,
  BarVerticalGrowdirection = "downwards",
  BarVerticalSpacing = 2,
  BarColumns = 1,
  BarHorizontalGrowdirection = "rightwards",
  BarHorizontalSpacing = 2,

  PlayerCount = {
    Enabled = true,
  },

  ButtonModules = {
    DRTracking = {
      Enabled = true,
      Parent = "Button",
      ActivePoints = 1,
      Points = {
        {
          Point = "LEFT",
          RelativeFrame = "SpecClassPriority",
          RelativePoint = "RIGHT",
          OffsetX = 0,
        },
      },
      IconSize = 20,
      Cooldown = {
        FontSize = 13,
        FontOutline = "OUTLINE",
        ShowDRCount = true,
      },
      Container = {
        UseButtonHeightAsSize = true,
        IconSize = 15,
        IconsPerRow = 10,
        HorizontalGrowDirection = "rightwards",
        HorizontalSpacing = 2,
        VerticalGrowdirection = "downwards",
        VerticalSpacing = 1,
      },
    },
    CombatIndicator = {
      Enabled = true,
      Points = {
        {
          Point = "LEFT",
          RelativeFrame = "SpecClassPriority",
          RelativePoint = "RIGHT",
          OffsetX = 0,
          OffsetY = 0,
        },
      },
    },
    RaidTargetIcon = {
      UseButtonHeightAsWidth = true,
      UseButtonHeightAsHeight = true,
      ActivePoints = 1,
      Points = {
        {
          Point = "CENTER",
          RelativeFrame = "healthBar",
          RelativePoint = "CENTER",
        },
      },
    },
    SpecClassPriority = {
      Cooldown = {
        FontSize = 20,
      },
      Points = {
        {
          Point = "LEFT",
          RelativeFrame = "Button",
          RelativePoint = "RIGHT",
        },
      },
      UseButtonHeightAsHeight = true,
      UseButtonHeightAsWidth = true,
    },
    Trinket = {
      Points = {
        {
          Point = "RIGHT",
          RelativeFrame = "ObjectiveAndRespawn",
          RelativePoint = "LEFT",
        },
      },
      UseButtonHeightAsHeight = true,
      UseButtonHeightAsWidth = true,
    },
    healthBar = {
      Enabled = true,
      Height = 30,
      UseButtonWidthAsWidth = true,
      Points = {
        {
          Point = "TOP",
          RelativeFrame = "Button",
          RelativePoint = "TOP",
          OffsetX = 0,
          OffsetY = 0,
        },
      },
    },
    healthBarText = {
      FontSize = 17,
      JustifyH = "RIGHT",
      JustifyV = "MIDDLE",
      Points = {
        {
          Point = "RIGHT",
          RelativeFrame = "healthBar",
          RelativePoint = "RIGHT",
          OffsetX = -4,
        },
      },
    },
    Power = {
      Enabled = true,
      Height = 5,
      UseButtonWidthAsWidth = true,
      Points = {
        {
          Point = "TOP",
          RelativeFrame = "healthBar",
          RelativePoint = "BOTTOM",
          OffsetX = 0,
          OffsetY = 0,
        },
      },
    },
    Level = {
      Enabled = false,
      Points = {
        {
          Point = "RIGHT",
          RelativeFrame = "healthBar",
          RelativePoint = "RIGHT",
          OffsetX = -4,
        },
      },
      Text = {
        FontSize = 18,
        JustifyH = "CENTER",
        JustifyV = "MIDDLE",
      },
    },
    Name = {
      Enabled = true,
      UseButtonWidthAsWidth = true,
      UseButtonHeightAsHeight = true,
      Points = {
        {
          Point = "LEFT",
          RelativeFrame = "Role",
          RelativePoint = "RIGHT",
          OffsetX = 4,
        },
      },
      Text = {
        FontSize = 12,
        JustifyH = "LEFT",
        JustifyV = "MIDDLE",
      },
    },
    Role = {
      Enabled = true,
      Width = 12,
      Height = 12,
      Points = {
        {
          Point = "LEFT",
          RelativeFrame = "healthBar",
          RelativePoint = "LEFT",
          OffsetX = 4,
        },
      },
    },
    ObjectiveAndRespawn = {
      Enabled = true,
      Points = {
        {
          Point = "RIGHT",
          RelativeFrame = "Button",
          RelativePoint = "LEFT",
        },
      },
      UseButtonHeightAsWidth = true,
      UseButtonHeightAsHeight = true,
      Cooldown = {
        FontSize = 12,
      },
      Text = {
        FontSize = 17,
        JustifyH = "CENTER",
        JustifyV = "MIDDLE",
      },
    },
  },

  Framescale = 1,

  -- PositiveSound = [[Interface\AddOns\WeakAuras\Media\Sounds\BatmanPunch.ogg]],
  -- NegativeSound = [[Sound\Interface\UI_BattlegroundCountdown_Timer.ogg]],
}

local enemyDefault15man = {
  Enabled = true,
  minPlayerCount = 6,
  maxPlayerCount = 15,

  Position_X = 900,
  Position_Y = 600,
  BarWidth = 185,
  BarHeight = 35,
  BarVerticalGrowdirection = "downwards",
  BarVerticalSpacing = 2,
  BarColumns = 1,
  BarHorizontalGrowdirection = "rightwards",
  BarHorizontalSpacing = 2,

  PlayerCount = {
    Enabled = true,
  },

  ButtonModules = {
    DRTracking = {
      Enabled = true,
      Parent = "Button",
      ActivePoints = 1,
      Points = {
        {
          Point = "RIGHT",
          RelativeFrame = "SpecClassPriority",
          RelativePoint = "LEFT",
          OffsetX = 0,
        },
      },
      IconSize = 20,
      Cooldown = {
        FontSize = 13,
        FontOutline = "OUTLINE",
        ShowDRCount = true,
      },
      Container = {
        UseButtonHeightAsSize = true,
        IconSize = 15,
        IconsPerRow = 10,
        HorizontalGrowDirection = "leftwards",
        HorizontalSpacing = 2,
        VerticalGrowdirection = "downwards",
        VerticalSpacing = 1,
      },
    },
    CombatIndicator = {
      Enabled = true,
      Points = {
        {
          Point = "RIGHT",
          RelativeFrame = "SpecClassPriority",
          RelativePoint = "LEFT",
          OffsetX = 0,
          OffsetY = 0,
        },
      },
    },
    RaidTargetIcon = {
      UseButtonHeightAsWidth = true,
      UseButtonHeightAsHeight = true,
      ActivePoints = 1,
      Points = {
        {
          Point = "CENTER",
          RelativeFrame = "healthBar",
          RelativePoint = "CENTER",
        },
      },
    },
    SpecClassPriority = {
      Cooldown = {
        FontSize = 20,
      },
      Points = {
        {
          Point = "RIGHT",
          RelativeFrame = "Button",
          RelativePoint = "LEFT",
        },
      },
      UseButtonHeightAsHeight = true,
      UseButtonHeightAsWidth = true,
    },
    Trinket = {
      Points = {
        {
          Point = "LEFT",
          RelativeFrame = "ObjectiveAndRespawn",
          RelativePoint = "RIGHT",
        },
      },
      UseButtonHeightAsHeight = true,
      UseButtonHeightAsWidth = true,
    },
    healthBar = {
      Enabled = true,
      Height = 30,
      UseButtonWidthAsWidth = true,
      Points = {
        {
          Point = "TOP",
          RelativeFrame = "Button",
          RelativePoint = "TOP",
          OffsetX = 0,
          OffsetY = 0,
        },
      },
    },
    healthBarText = {
      FontSize = 17,
      JustifyH = "RIGHT",
      JustifyV = "MIDDLE",
      Points = {
        {
          Point = "RIGHT",
          RelativeFrame = "healthBar",
          RelativePoint = "RIGHT",
          OffsetX = -4,
        },
      },
    },
    Power = {
      Enabled = true,
      Height = 5,
      UseButtonWidthAsWidth = true,
      Points = {
        {
          Point = "TOP",
          RelativeFrame = "healthBar",
          RelativePoint = "BOTTOM",
          OffsetX = 0,
          OffsetY = 0,
        },
      },
    },
    Level = {
      Enabled = false,
      Points = {
        {
          Point = "RIGHT",
          RelativeFrame = "healthBar",
          RelativePoint = "RIGHT",
          OffsetX = -4,
        },
      },
      Text = {
        FontSize = 18,
        JustifyH = "CENTER",
        JustifyV = "MIDDLE",
      },
    },
    Name = {
      Enabled = true,
      UseButtonWidthAsWidth = true,
      UseButtonHeightAsHeight = true,
      Points = {
        {
          Point = "LEFT",
          RelativeFrame = "Role",
          RelativePoint = "RIGHT",
          OffsetX = 4,
        },
      },
      Text = {
        FontSize = 12,
        JustifyH = "LEFT",
        JustifyV = "MIDDLE",
      },
    },
    Role = {
      Enabled = true,
      Width = 12,
      Height = 12,
      Points = {
        {
          Point = "LEFT",
          RelativeFrame = "healthBar",
          RelativePoint = "LEFT",
          OffsetX = 4,
        },
      },
    },
    ObjectiveAndRespawn = {
      Enabled = true,
      Points = {
        {
          Point = "LEFT",
          RelativeFrame = "Button",
          RelativePoint = "RIGHT",
        },
      },
      UseButtonHeightAsWidth = true,
      UseButtonHeightAsHeight = true,
      Cooldown = {
        FontSize = 12,
      },
      Text = {
        FontSize = 17,
        JustifyH = "CENTER",
        JustifyV = "MIDDLE",
      },
    },
  },

  Framescale = 1,
}
-- PositiveSound = [[Interface\AddOns\WeakAuras\Media\Sounds\BatmanPunch.ogg]],
-- NegativeSound = [[Sound\Interface\UI_BattlegroundCountdown_Timer.ogg]],

Data.defaultSettings = {
  profile = {
    Locked = false,
    Debug = false,
    DebugBlizzEvents = false,
    DebugToSV = false,
    DebugToSV_ResetOnPlayerLogin = false,
    DebugToChat = false,
    DebugToChat_AddTimestamp = false,

    shareActiveProfile = false,

    DisableArenaFramesInArena = false,
    DisableArenaFramesInBattleground = false,

    DisableRaidFramesInArena = false,
    DisableRaidFramesInBattleground = false,

    ShowBGEInArena = false,
    ShowBGEInBattleground = true,

    MyTarget_Color = { 1, 1, 1, 1 },
    MyTarget_BorderSize = 2,
    MyFocus_Color = { 0, 0.988235294117647, 0.729411764705882, 1 },
    MyFocus_BorderSize = 2,
    ShowTooltips = false,
    EnableMouseWheelPlayerTargeting = false,
    ConvertCyrillic = true,
    DisableRoleCheckWarning = false,

    PlayerCount = {
      Text = {
        FontSize = 14,
        JustifyV = "MIDDLE",
        JustifyH = "LEFT",
      },
    },

    RoleSortingOrder = "HEALER_TANK_DAMAGER",

    Cooldown = {
      ShowNumber = true,
      DrawSwipe = true,
    },

    Text = {
      Font = "Friz Quadrata TT",
      FontColor = { 241 / 255, 241 / 255, 241 / 255, 1 },
      FontOutline = "",
      EnableShadow = true,
      ShadowColor = { 0, 0, 0, 0.8 },
    },

    RBG = {
      TargetCalling_SetMark = false,
      TargetCalling_NotificationEnable = false,
      EnemiesTargetingMe_Enabled = false,
      EnemiesTargetingMe_Amount = 5,
      EnemiesTargetingAllies_Enabled = false,
      EnemiesTargetingAllies_Amount = 5,
    },

    Enemies = {
      Enabled = true,

      CustomPlayerCountConfigsEnabled = false,

      RangeIndicator_Enabled = true,
      RangeIndicator_Range = 40, --not used anymore, but kept for compatibility
      RangeIndicator_Range_InCombat = 30,
      RangeIndicator_Range_OutOfCombat = 40,
      RangeIndicator_Alpha = 0.35,
      RangeIndicator_Everything = true,
      RangeIndicator_Frames = {},

      ActionButtonUseKeyDown = false,
      UseClique = false,

      LeftButtonType = "Target",
      LeftButtonValue = "",
      RightButtonType = "Focus",
      RightButtonValue = "",
      MiddleButtonType = "Custom",
      MiddleButtonValue = "",

      playerCountConfigs = {
        {
          Enabled = false,
          minPlayerCount = 1,
          maxPlayerCount = 5,

          Position_X = 900,
          Position_Y = 600,
          BarWidth = 185,
          BarHeight = 50,
          BarVerticalGrowdirection = "downwards",
          BarVerticalSpacing = 10,
          BarColumns = 1,
          BarHorizontalGrowdirection = "rightwards",
          BarHorizontalSpacing = 5,

          PlayerCount = {
            Enabled = true,
          },

          ButtonModules = {
            DRTracking = {
              Enabled = true,
              Parent = "Button",
              ActivePoints = 1,
              Points = {
                {
                  Point = "RIGHT",
                  RelativeFrame = "SpecClassPriority",
                  RelativePoint = "LEFT",
                  OffsetX = 0,
                },
              },
              IconSize = 20,
              Cooldown = {
                FontSize = 13,
                FontOutline = "OUTLINE",
                ShowDRCount = true,
              },
              Container = {
                UseButtonHeightAsSize = true,
                IconSize = 15,
                IconsPerRow = 10,
                HorizontalGrowDirection = "leftwards",
                HorizontalSpacing = 2,
                VerticalGrowdirection = "downwards",
                VerticalSpacing = 1,
              },
            },
            CombatIndicator = {
              Enabled = true,
              Points = {
                {
                  Point = "RIGHT",
                  RelativeFrame = "SpecClassPriority",
                  RelativePoint = "LEFT",
                  OffsetX = 0,
                  OffsetY = 0,
                },
              },
            },
            RaidTargetIcon = {
              UseButtonHeightAsWidth = true,
              UseButtonHeightAsHeight = true,
              ActivePoints = 1,
              Points = {
                {
                  Point = "CENTER",
                  RelativeFrame = "healthBar",
                  RelativePoint = "CENTER",
                },
              },
            },
            SpecClassPriority = {
              Cooldown = {
                FontSize = 20,
              },
              Points = {
                {
                  Point = "RIGHT",
                  RelativeFrame = "Button",
                  RelativePoint = "LEFT",
                },
              },
              UseButtonHeightAsHeight = true,
              UseButtonHeightAsWidth = true,
            },
            Trinket = {
              Points = {
                {
                  Point = "LEFT",
                  RelativeFrame = "ObjectiveAndRespawn",
                  RelativePoint = "RIGHT",
                },
              },
              UseButtonHeightAsHeight = true,
              UseButtonHeightAsWidth = true,
            },
            healthBar = {
              Enabled = true,
              Height = 42,
              UseButtonWidthAsWidth = true,
              Points = {
                {
                  Point = "TOP",
                  RelativeFrame = "Button",
                  RelativePoint = "TOP",
                  OffsetX = 0,
                  OffsetY = 0,
                },
              },
            },
            healthBarText = {
              FontSize = 17,
              JustifyH = "RIGHT",
              JustifyV = "MIDDLE",
              Points = {
                {
                  Point = "RIGHT",
                  RelativeFrame = "healthBar",
                  RelativePoint = "RIGHT",
                  OffsetX = -4,
                },
              },
            },
            Power = {
              Enabled = true,
              Height = 8,
              UseButtonWidthAsWidth = true,
              Points = {
                {
                  Point = "TOP",
                  RelativeFrame = "healthBar",
                  RelativePoint = "BOTTOM",
                  OffsetX = 0,
                  OffsetY = 0,
                },
              },
            },
            Level = {
              Enabled = false,
              Points = {
                {
                  Point = "RIGHT",
                  RelativeFrame = "healthBar",
                  RelativePoint = "RIGHT",
                  OffsetX = -4,
                },
              },
              Text = {
                FontSize = 18,
                JustifyH = "CENTER",
                JustifyV = "MIDDLE",
              },
            },
            Name = {
              Enabled = true,
              UseButtonWidthAsWidth = true,
              UseButtonHeightAsHeight = true,
              Points = {
                {
                  Point = "LEFT",
                  RelativeFrame = "Role",
                  RelativePoint = "RIGHT",
                  OffsetX = 4,
                },
              },
              Text = {
                FontSize = 12,
                JustifyH = "LEFT",
                JustifyV = "MIDDLE",
              },
            },
            Role = {
              Enabled = true,
              Width = 12,
              Height = 12,
              Points = {
                {
                  Point = "LEFT",
                  RelativeFrame = "healthBar",
                  RelativePoint = "LEFT",
                  OffsetX = 4,
                },
              },
            },
            ObjectiveAndRespawn = {
              Enabled = false,
              Points = {
                {
                  Point = "LEFT",
                  RelativeFrame = "Button",
                  RelativePoint = "RIGHT",
                },
              },
              UseButtonHeightAsWidth = true,
              UseButtonHeightAsHeight = true,
              Cooldown = {
                FontSize = 12,
              },
              Text = {
                FontSize = 17,
                JustifyH = "CENTER",
                JustifyV = "MIDDLE",
              },
            },
          },

          Framescale = 1,

          -- PositiveSound = [[Interface\AddOns\WeakAuras\Media\Sounds\BatmanPunch.ogg]],
          -- NegativeSound = [[Sound\Interface\UI_BattlegroundCountdown_Timer.ogg]],
        },
        enemyDefault15man,
        {
          Enabled = true,
          minPlayerCount = 16,
          maxPlayerCount = 40,

          Position_X = 800,
          Position_Y = 600,
          BarWidth = 160,
          BarHeight = 30,
          BarVerticalGrowdirection = "downwards",
          BarVerticalSpacing = 2,
          BarColumns = 3,
          BarHorizontalGrowdirection = "rightwards",
          BarHorizontalSpacing = 2,

          PlayerCount = {
            Enabled = true,
          },

          ButtonModules = {
            DRTracking = {
              Enabled = false,
              Parent = "Button",
              ActivePoints = 1,
              Points = {
                {
                  Point = "RIGHT",
                  RelativeFrame = "SpecClassPriority",
                  RelativePoint = "LEFT",
                  OffsetX = 0,
                },
              },
              IconSize = 20,
              Cooldown = {
                FontSize = 13,
                FontOutline = "OUTLINE",
                ShowDRCount = true,
              },
              Container = {
                UseButtonHeightAsSize = true,
                IconSize = 15,
                IconsPerRow = 10,
                HorizontalGrowDirection = "leftwards",
                HorizontalSpacing = 2,
                VerticalGrowdirection = "downwards",
                VerticalSpacing = 1,
              },
            },
            CombatIndicator = {
              Enabled = false,
              Points = {
                {
                  Point = "RIGHT",
                  RelativeFrame = "SpecClassPriority",
                  RelativePoint = "LEFT",
                  OffsetX = 0,
                  OffsetY = 0,
                },
              },
            },
            RaidTargetIcon = {
              Enabled = true,
              UseButtonHeightAsWidth = true,
              UseButtonHeightAsHeight = true,
              ActivePoints = 1,
              Points = {
                {
                  Point = "CENTER",
                  RelativeFrame = "healthBar",
                  RelativePoint = "CENTER",
                },
              },
            },
            SpecClassPriority = {
              Enabled = false,
              Cooldown = {
                FontSize = 20,
              },
              Points = {
                {
                  Point = "RIGHT",
                  RelativeFrame = "Button",
                  RelativePoint = "LEFT",
                },
              },
              UseButtonHeightAsHeight = true,
              UseButtonHeightAsWidth = true,
            },
            Trinket = {
              Enabled = false,
              Points = {
                {
                  Point = "LEFT",
                  RelativeFrame = "ObjectiveAndRespawn",
                  RelativePoint = "RIGHT",
                },
              },
              UseButtonHeightAsHeight = true,
              UseButtonHeightAsWidth = true,
            },
            healthBar = {
              Enabled = true,
              Height = 26,
              UseButtonWidthAsWidth = true,
              Points = {
                {
                  Point = "TOP",
                  RelativeFrame = "Button",
                  RelativePoint = "TOP",
                  OffsetX = 0,
                  OffsetY = 0,
                },
              },
            },
            healthBarText = {
              HealthTextType = "perc",
              FontSize = 17,
              JustifyH = "RIGHT",
              JustifyV = "MIDDLE",
              Points = {
                {
                  Point = "RIGHT",
                  RelativeFrame = "healthBar",
                  RelativePoint = "RIGHT",
                  OffsetX = -4,
                },
              },
            },
            Power = {
              Enabled = true,
              Height = 4,
              UseButtonWidthAsWidth = true,
              Points = {
                {
                  Point = "TOP",
                  RelativeFrame = "healthBar",
                  RelativePoint = "BOTTOM",
                  OffsetX = 0,
                  OffsetY = 0,
                },
              },
            },
            Level = {
              Enabled = false,
              Points = {
                {
                  Point = "RIGHT",
                  RelativeFrame = "healthBar",
                  RelativePoint = "RIGHT",
                  OffsetX = -4,
                },
              },
              Text = {
                FontSize = 18,
                JustifyH = "CENTER",
                JustifyV = "MIDDLE",
              },
            },
            Name = {
              Enabled = true,
              UseButtonWidthAsWidth = true,
              UseButtonHeightAsHeight = true,
              Points = {
                {
                  Point = "LEFT",
                  RelativeFrame = "Role",
                  RelativePoint = "RIGHT",
                  OffsetX = 4,
                },
              },
              Text = {
                FontSize = 12,
                JustifyH = "LEFT",
                JustifyV = "MIDDLE",
              },
            },
            Role = {
              Enabled = true,
              Width = 12,
              Height = 12,
              Points = {
                {
                  Point = "LEFT",
                  RelativeFrame = "healthBar",
                  RelativePoint = "LEFT",
                  OffsetX = 4,
                },
              },
            },
            ObjectiveAndRespawn = {
              Enabled = false,
              Points = {
                {
                  Point = "LEFT",
                  RelativeFrame = "Button",
                  RelativePoint = "RIGHT",
                },
              },
              UseButtonHeightAsWidth = true,
              UseButtonHeightAsHeight = true,
              Cooldown = {
                FontSize = 12,
              },
              Text = {
                FontSize = 17,
                JustifyH = "CENTER",
                JustifyV = "MIDDLE",
              },
            },
          },

          Framescale = 0.8,
        },
      },

      customPlayerCountConfigs = {
        ["**"] = enemyDefault15man,
        -- PositiveSound = [[Interface\AddOns\WeakAuras\Media\Sounds\BatmanPunch.ogg]],
        -- NegativeSound = [[Sound\Interface\UI_BattlegroundCountdown_Timer.ogg]],
      },
    },

    Allies = {
      Enabled = true,

      CustomPlayerCountConfigsEnabled = false,

      RangeIndicator_Enabled = true,
      RangeIndicator_Range = 40, --not used anymore, but kept for compatibility
      RangeIndicator_Range_InCombat = 40,
      RangeIndicator_Range_OutOfCombat = 40,
      RangeIndicator_Alpha = 0.55,
      RangeIndicator_Everything = true,
      RangeIndicator_Frames = {},

      ActionButtonUseKeyDown = false,
      UseClique = false,

      LeftButtonType = "Target",
      LeftButtonValue = "",
      RightButtonType = "Focus",
      RightButtonValue = "",
      MiddleButtonType = "Custom",
      MiddleButtonValue = "",

      playerCountConfigs = {
        {
          Enabled = false,
          minPlayerCount = 1,
          maxPlayerCount = 5,

          Position_X = 200,
          Position_Y = 600,
          BarWidth = 185,
          BarHeight = 50,
          BarVerticalGrowdirection = "downwards",
          BarVerticalSpacing = 10,
          BarColumns = 1,
          BarHorizontalGrowdirection = "rightwards",
          BarHorizontalSpacing = 5,

          PlayerCount = {
            Enabled = true,
          },

          ButtonModules = {
            DRTracking = {
              Enabled = true,
              Parent = "Button",
              ActivePoints = 1,
              Points = {
                {
                  Point = "LEFT",
                  RelativeFrame = "SpecClassPriority",
                  RelativePoint = "RIGHT",
                  OffsetX = 0,
                },
              },
              IconSize = 20,
              Cooldown = {
                FontSize = 13,
                FontOutline = "OUTLINE",
                ShowDRCount = true,
              },
              Container = {
                UseButtonHeightAsSize = true,
                IconSize = 15,
                IconsPerRow = 10,
                HorizontalGrowDirection = "righttwards",
                HorizontalSpacing = 2,
                VerticalGrowdirection = "downwards",
                VerticalSpacing = 1,
              },
            },
            CombatIndicator = {
              Enabled = true,
              Points = {
                {
                  Point = "LEFT",
                  RelativeFrame = "SpecClassPriority",
                  RelativePoint = "RIGHT",
                  OffsetX = 0,
                  OffsetY = 0,
                },
              },
            },
            RaidTargetIcon = {
              UseButtonHeightAsWidth = true,
              UseButtonHeightAsHeight = true,
              ActivePoints = 1,
              Points = {
                {
                  Point = "CENTER",
                  RelativeFrame = "healthBar",
                  RelativePoint = "CENTER",
                },
              },
            },
            SpecClassPriority = {
              Cooldown = {
                FontSize = 20,
              },
              Points = {
                {
                  Point = "LEFT",
                  RelativeFrame = "Button",
                  RelativePoint = "RIGHT",
                },
              },
              UseButtonHeightAsHeight = true,
              UseButtonHeightAsWidth = true,
            },
            Trinket = {
              Points = {
                {
                  Point = "RIGHT",
                  RelativeFrame = "ObjectiveAndRespawn",
                  RelativePoint = "LEFT",
                },
              },
              UseButtonHeightAsHeight = true,
              UseButtonHeightAsWidth = true,
            },
            healthBar = {
              Enabled = true,
              Height = 42,
              UseButtonWidthAsWidth = true,
              Points = {
                {
                  Point = "TOP",
                  RelativeFrame = "Button",
                  RelativePoint = "TOP",
                  OffsetX = 0,
                  OffsetY = 0,
                },
              },
            },
            healthBarText = {
              FontSize = 17,
              JustifyH = "RIGHT",
              JustifyV = "MIDDLE",
              Points = {
                {
                  Point = "RIGHT",
                  RelativeFrame = "healthBar",
                  RelativePoint = "RIGHT",
                  OffsetX = -4,
                },
              },
            },
            Power = {
              Enabled = true,
              Height = 8,
              UseButtonWidthAsWidth = true,
              Points = {
                {
                  Point = "TOP",
                  RelativeFrame = "healthBar",
                  RelativePoint = "BOTTOM",
                  OffsetX = 0,
                  OffsetY = 0,
                },
              },
            },
            Level = {
              Enabled = false,
              Points = {
                {
                  Point = "RIGHT",
                  RelativeFrame = "healthBar",
                  RelativePoint = "RIGHT",
                  OffsetX = -4,
                },
              },
              Text = {
                FontSize = 18,
                JustifyH = "CENTER",
                JustifyV = "MIDDLE",
              },
            },
            Name = {
              Enabled = true,
              UseButtonWidthAsWidth = true,
              UseButtonHeightAsHeight = true,
              Points = {
                {
                  Point = "LEFT",
                  RelativeFrame = "Role",
                  RelativePoint = "RIGHT",
                  OffsetX = 4,
                },
              },
              Text = {
                FontSize = 12,
                JustifyH = "LEFT",
                JustifyV = "MIDDLE",
              },
            },
            Role = {
              Enabled = true,
              Width = 12,
              Height = 12,
              Points = {
                {
                  Point = "LEFT",
                  RelativeFrame = "healthBar",
                  RelativePoint = "LEFT",
                  OffsetX = 4,
                },
              },
            },
            ObjectiveAndRespawn = {
              Enabled = false,
              Points = {
                {
                  Point = "RIGHT",
                  RelativeFrame = "Button",
                  RelativePoint = "LEFT",
                },
              },
              UseButtonHeightAsWidth = true,
              UseButtonHeightAsHeight = true,
              Cooldown = {
                FontSize = 12,
              },
              Text = {
                FontSize = 17,
                JustifyH = "CENTER",
                JustifyV = "MIDDLE",
              },
            },
          },

          Framescale = 1,

          -- PositiveSound = [[Interface\AddOns\WeakAuras\Media\Sounds\BatmanPunch.ogg]],
          -- NegativeSound = [[Sound\Interface\UI_BattlegroundCountdown_Timer.ogg]],
        },
        allieDefaults15man,
        {
          Enabled = false,
          minPlayerCount = 16,
          maxPlayerCount = 40,

          Position_X = 200,
          Position_Y = 600,
          BarWidth = 160,
          BarHeight = 30,
          BarVerticalGrowdirection = "downwards",
          BarVerticalSpacing = 2,
          BarColumns = 3,
          BarHorizontalGrowdirection = "rightwards",
          BarHorizontalSpacing = 2,

          PlayerCount = {
            Enabled = true,
          },

          ButtonModules = {
            DRTracking = {
              Enabled = false,
              Parent = "Button",
              ActivePoints = 1,
              Points = {
                {
                  Point = "LEFT",
                  RelativeFrame = "SpecClassPriority",
                  RelativePoint = "RIGHT",
                  OffsetX = 0,
                },
              },
              IconSize = 20,
              Cooldown = {
                FontSize = 13,
                FontOutline = "OUTLINE",
                ShowDRCount = true,
              },
              Container = {
                UseButtonHeightAsSize = true,
                IconSize = 15,
                IconsPerRow = 10,
                HorizontalGrowDirection = "rightwards",
                HorizontalSpacing = 2,
                VerticalGrowdirection = "downwards",
                VerticalSpacing = 1,
              },
            },
            CombatIndicator = {
              Enabled = false,
              Points = {
                {
                  Point = "LEFT",
                  RelativeFrame = "SpecClassPriority",
                  RelativePoint = "RIGHT",
                  OffsetX = 0,
                  OffsetY = 0,
                },
              },
            },
            RaidTargetIcon = {
              Enabled = true,
              UseButtonHeightAsWidth = true,
              UseButtonHeightAsHeight = true,
              ActivePoints = 1,
              Points = {
                {
                  Point = "CENTER",
                  RelativeFrame = "healthBar",
                  RelativePoint = "CENTER",
                },
              },
            },
            SpecClassPriority = {
              Enabled = false,
              Cooldown = {
                FontSize = 20,
              },
              Points = {
                {
                  Point = "LEFT",
                  RelativeFrame = "Button",
                  RelativePoint = "RIGHT",
                },
              },
            },
            Trinket = {
              Enabled = false,
              Points = {
                {
                  Point = "RIGHT",
                  RelativeFrame = "ObjectiveAndRespawn",
                  RelativePoint = "LEFT",
                },
              },
              UseButtonHeightAsHeight = true,
              UseButtonHeightAsWidth = true,
            },
            healthBar = {
              Enabled = true,
              Height = 26,
              UseButtonWidthAsWidth = true,
              Points = {
                {
                  Point = "TOP",
                  RelativeFrame = "Button",
                  RelativePoint = "TOP",
                  OffsetX = 0,
                  OffsetY = 0,
                },
              },
            },
            healthBarText = {
              HealthTextType = "perc",
              FontSize = 17,
              JustifyH = "RIGHT",
              JustifyV = "MIDDLE",
              Points = {
                {
                  Point = "RIGHT",
                  RelativeFrame = "healthBar",
                  RelativePoint = "RIGHT",
                  OffsetX = -4,
                },
              },
            },
            Power = {
              Enabled = true,
              Height = 4,
              UseButtonWidthAsWidth = true,
              Points = {
                {
                  Point = "TOP",
                  RelativeFrame = "healthBar",
                  RelativePoint = "BOTTOM",
                  OffsetX = 0,
                  OffsetY = 0,
                },
              },
            },
            Level = {
              Enabled = false,
              Points = {
                {
                  Point = "RIGHT",
                  RelativeFrame = "healthBar",
                  RelativePoint = "RIGHT",
                  OffsetX = -4,
                },
              },
              Text = {
                FontSize = 18,
                JustifyH = "CENTER",
                JustifyV = "MIDDLE",
              },
            },
            Name = {
              Enabled = true,
              UseButtonWidthAsWidth = true,
              UseButtonHeightAsHeight = true,
              Points = {
                {
                  Point = "LEFT",
                  RelativeFrame = "Role",
                  RelativePoint = "RIGHT",
                  OffsetX = 4,
                },
              },
              Text = {
                FontSize = 12,
                JustifyH = "LEFT",
                JustifyV = "MIDDLE",
              },
            },
            Role = {
              Enabled = true,
              Width = 12,
              Height = 12,
              Points = {
                {
                  Point = "LEFT",
                  RelativeFrame = "healthBar",
                  RelativePoint = "LEFT",
                  OffsetX = 4,
                },
              },
            },
            ObjectiveAndRespawn = {
              Enabled = false,
              Points = {
                {
                  Point = "RIGHT",
                  RelativeFrame = "Button",
                  RelativePoint = "LEFT",
                },
              },
              UseButtonHeightAsWidth = true,
              UseButtonHeightAsHeight = true,
              Cooldown = {
                FontSize = 12,
              },
              Text = {
                FontSize = 17,
                JustifyH = "CENTER",
                JustifyV = "MIDDLE",
              },
            },
          },

          Framescale = 0.8,
        },
      },
      customPlayerCountConfigs = {
        ["**"] = allieDefaults15man, --**means it will be used by all other keys in here, for example customPlayerCountConfigs.xyx will be allieDefaults15man
      },
    },

    ButtonModules = {},
  },
}
