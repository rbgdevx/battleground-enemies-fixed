-- Static analysis for the battle-ground-enemies-fixed WoW addon.  Run from the repo root: luacheck .
--
-- Tailored to the addon: WoW globals seeded from its .luarc.json and completed
-- with a luacheck harvest of APIs the code actually calls (luacheck has no WoW
-- API library of its own, unlike the LSP's WoW addon the .luarc.json leans on).
-- NOTE: luacheck must run under Lua <= 5.4 (it crashes on 5.5). The `luacheck`
-- on PATH is built against lua@5.4; we still lint WoW's 5.1 dialect via std.

std = "lua51"            -- WoW runs Lua 5.1
max_line_length = false  -- WoW addon lines are routinely wide

exclude_files = {
  ".libraries", ".claude", ".vscode",
  -- External embedded libraries (NOT ours). PerfHUD-1.0 is our own lib, so it
  -- is deliberately absent here and stays linted.
  "libs/AceConfig-3.0", "libs/AceDB-3.0", "libs/AceDBOptions-3.0",
  "libs/AceGUI-3.0", "libs/AceGUI-3.0-SharedMediaWidgets",
  "libs/CallbackHandler-1.0", "libs/LibDeflate", "libs/LibRangeCheck-3.0",
  "libs/LibSerialize", "libs/LibSharedMedia-3.0", "libs/LibSpellIconSelector",
  "libs/LibStub", "libs/UTF8",
}

-- WoW idioms that aren't defects, handled at config level (not by churning
-- 200+ signatures, which only risks bugs):
--   unused_args=false — WoW event/callback/option handlers carry positional
--     params (event, unitID, location, option, widget...) that a given handler
--     often doesn't use. These are API-fixed signatures, not dead code.
--   432/self — `something:SetScript("OnX", function(self) ... end)` inside a
--     `Module:Method()` shadows the outer `self`. Idiomatic; the inner self is
--     the widget. (Non-self shadows are still flagged and fixed in source.)
--   _ADDON — the `local _ADDON, NS = ...` addon-load vararg.
unused_args = false
ignore = { "_ADDON", "432/self" }

-- Globals the addon DEFINES/WRITES (saved-vars, slash handlers).
globals = {
  "BattleGroundEnemies", "ClickCastFrames", "ColorPickerFrame", "NineSliceLayouts",
  "SLASH_BattleGroundEnemies1", "SLASH_BattleGroundEnemies2", "SlashCmdList",
}

-- Blizzard client API the addon READS.
read_globals = {
  "ACCEPT", "ACTION_BUTTON_USE_KEY_DOWN", "ARENA", "AbbreviateNumbers",
  "AceGUIEditBoxInsertLink", "AceGUIMultiLineEditBoxInsertLink", "AceGUIWidgetLSMlists",
  "Ambiguate", "AnchorUtil", "ArenaEnemyFrames", "ArenaEnemyFramesContainer",
  "ArenaEnemyFrames_CheckEffectiveEnableState", "ArenaEnemyFrames_Disable", "BATTLEFIELDS",
  "BOOKTYPE_SPELL", "BackdropTemplateMixin", "BetterDate", "BigDebuffs",
  "ButtonFrameTemplate_HidePortrait", "CANCEL", "CLASS_ICON_TCOORDS", "CLASS_SORT_ORDER",
  "CLOSE", "COMPACT_UNIT_FRAME_PROFILE_DISPLAYHEALPREDICTION",
  "COMPACT_UNIT_FRAME_PROFILE_HEALTHTEXT_HEALTH",
  "COMPACT_UNIT_FRAME_PROFILE_HEALTHTEXT_LOSTHEALTH",
  "COMPACT_UNIT_FRAME_PROFILE_HEALTHTEXT_PERC", "CUSTOM_CLASS_COLORS", "C_AddOns",
  "C_CVar", "C_CreatureInfo", "C_EventUtils", "C_Item", "C_LossOfControl", "C_Map", "C_MountJournal",
  "C_PetJournal", "C_PvP", "C_SpecializationInfo", "C_Spell", "C_SpellBook", "C_SpellDiminish",
  "C_Timer", "C_UIWidgetManager", "C_UnitAuras", "CalculateDistanceSq", "ChatEdit_InsertLink", "ChatFontNormal",
  "ChatFrameUtil", "CheckInteractDistance", "ClearCursor", "CloseSpecialWindows",
  "CompactArenaFrame", "CompactUnitFrame_UpdateHealPrediction", "CopyTable", "CreateFont",
  "CreateFrame", "CreateFromMixins", "CreateIndexRangeDataProvider", "CreateObjectPool",
  "CreateScrollBoxListGridView", "CreateUnitHealPredictionCalculator", "CurveConstants",
  "DEFAULT_CHAT_FRAME", "DELETE", "DebuffTypeColor", "DoesTemplateExist", "ENABLE",
  "ENTER_MACRO_LABEL", "ERRORS", "Enum", "EventRegistry", "FILTER", "FONT_COLOR_CODE_CLOSE",
  "FOREIGN_SERVER_LABEL", "GENERAL", "GameFontDisableSmall", "GameFontHighlight",
  "GameFontHighlightLarge", "GameFontHighlightSmall", "GameFontNormal", "GameFontNormalSmall",
  "GameFontWhite", "GameTooltip", "GenerateClosure", "GetAddOnMetadata",
  "GetAppropriateTooltip", "GetArenaOpponentSpec", "GetBattlefieldInstanceRunTime",
  "GetBattlefieldTeamInfo", "GetBuildInfo", "GetCVar", "GetCVarBool", "GetCachedPlayerInfo",
  "GetClassAtlas", "GetClassInfo", "GetCurrentRegion", "GetCurrentRegionName", "GetCursorInfo",
  "GetCursorPosition", "GetGuildInfo", "GetInstanceInfo", "GetInventoryItemLink",
  "GetInventorySlotInfo", "GetItemIcon", "GetItemInfo", "GetLocale", "GetMacroInfo",
  "GetMaxPlayerLevel", "GetNormalizedRealmName", "GetNumArenaOpponentSpecs",
  "GetNumArenaOpponents", "GetNumBattlefieldScores", "GetNumClasses", "GetNumGroupMembers",
  "GetNumSpecializationsForClassID", "GetNumSpellTabs", "GetPlayerInfoByGUID",
  "GetRaidRosterInfo", "GetRaidTargetIndex", "GetRealmName", "GetSpecialization",
  "GetSpecializationInfoByID", "GetSpecializationInfoForClassID", "GetSpecializationRole",
  "GetSpellBookItemName", "GetSpellInfo", "GetSpellName", "GetSpellTabInfo", "GetSpellTexture",
  "GetTexCoordsForRoleSmallCircle", "GetTime", "GetUnitName", "ICON_SELECTION_CLICK",
  "ICON_SELECTION_DRAG", "ICON_SELECTION_NOTINLIST", "ICON_SELECTION_TITLE_CURRENT",
  "ICON_SELECTION_TITLE_CUSTOM", "IconSelectorPopupFrameTemplateMixin", "InCombatLockdown",
  "InterfaceOptionsFramePanelContainer", "InterfaceOptions_AddCategory", "IsAltKeyDown",
  "IsControlKeyDown", "IsInGroup", "IsInInstance", "IsInRaid", "IsRatedBattleground",
  "IsShiftKeyDown", "Item", "KEY_BINDINGS", "KEY_BUTTON1", "KEY_BUTTON2", "KEY_BUTTON3",
  "LEVEL", "LE_PARTY_CATEGORY_INSTANCE", "LE_REALM_RELATION_VIRTUAL", "LOCALE_deDE",
  "LOCALE_esES", "LOCALE_esMX", "LOCALE_frFR", "LOCALE_itIT", "LOCALE_koKR", "LOCALE_ptBR",
  "LOCALE_ptPT", "LOCALE_ruRU", "LOCALE_zhCN", "LOCALE_zhTW", "LibStub",
  "MACRO_POPUP_CHOOSE_ICON", "MISCELLANEOUS", "MainMenuBar", "MainMenuBarVehicleLeaveButton",
  "MergeTable", "Mixin", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft",
  "MultiBarRight", "NORMAL_FONT_COLOR", "NORMAL_FONT_COLOR_CODE", "NOT_BOUND", "NineSliceUtil",
  "OKAY", "OPTION_TOOLTIP_ACTION_BUTTON_USE_KEY_DOWN", "ObjectiveTrackerFrame",
  "OpacitySliderFrame", "OverrideActionBar", "PLAYER_COUNT_ALLIANCE", "PLAYER_COUNT_HORDE",
  "PVPMatchResults", "PVPMatchScoreboard", "PetActionBar", "PixelUtil", "PlaySound",
  "PlaySoundFile", "PossessActionBar", "PowerBarColor", "RAID_CLASS_COLORS", "ROLE",
  "ReloadUI", "RequestBattlefieldScoreData", "SELECTED_CHAT_FRAME", "SETTINGS_DEFAULTS",
  "SET_FOCUS", "SOUNDKIT", "STANDARD_TEXT_FONT", "ScrollBoxConstants", "ScrollUtil",
  "SecureHandlerWrapScript", "SelectionFrameCancelButton_OnClick",
  "SelectionFrameOkayButton_OnClick", "SetBattlefieldScoreFaction", "SetCVar",
  "SetDesaturation", "SetRaidTargetIconTexture", "Settings", "StanceBar", "TARGET", "UIParent",
  "UNKNOWN", "UnitAffectingCombat", "UnitCanAssist", "UnitCanAttack", "UnitClass",
  "UnitClassBase", "UnitExists", "UnitFactionGroup", "UnitGUID",
  "UnitGetDetailedHealPrediction", "UnitGroupRolesAssigned", "UnitHealth", "UnitHealthMax",
  "UnitHealthMissing", "UnitHealthPercent", "UnitHonorLevel", "UnitInRange",
  "UnitIsDeadOrGhost", "UnitIsFriend", "UnitIsGhost", "UnitIsGroupAssistant",
  "UnitIsGroupLeader", "UnitIsPlayer", "UnitIsUnit", "UnitIsVisible", "UnitLevel", "UnitName",
  "UnitPower", "UnitPowerMax", "UnitPowerType", "UnitRace", "UnitRealmRelationship", "UnitSex",
  "UnitSexBase", "VIDEO_OPTIONS_ENABLED", "WOW_PROJECT_BURNING_CRUSADE_CLASSIC",
  "WOW_PROJECT_CATACLYSM_CLASSIC", "WOW_PROJECT_CLASSIC", "WOW_PROJECT_ID",
  "WOW_PROJECT_MAINLINE", "WOW_PROJECT_WRATH_CLASSIC", "date", "debugprofilestop", "format",
  "geterrorhandler", "hooksecurefunc", "issecretvalue", "securecallfunction", "sort",
  "strfind", "strsplit", "strtrim", "tAppendAll", "tContains", "time", "tinsert", "tremove",
  "utf8_lc_uc", "utf8_uc_lc", "wipe",
  -- PerfHUD-1.0 (our lib):
  "GetAddOnCPUUsage",
  "GetFrameCPUUsage",
  "GetFramerate",
  "UpdateAddOnCPUUsage",
}
