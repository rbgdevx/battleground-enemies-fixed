-- ============================================================================
-- BGE_TokenRig.lua — THROWAWAY DIAGNOSTIC (2026-07-15).
-- Delete this file + its line in the .toc to remove completely; nothing else
-- references it. It only READS BattleGroundEnemies state (currentTarget +
-- that button's UnitIDs); it never writes any addon state.
--
-- Purpose: the health-jumping hunt. The real enemy frame is painted by MANY
-- writers through many tokens. This rig renders ONE thin bar PER TOKEN that
-- BGE currently believes is your target, each bar fed ONLY by its own token,
-- stacked ABOVE the Blizzard target frame (which shows the same unit as
-- ground truth right below). All bars should march in lockstep:
--   * one bar diverges            -> that token family delivers wrong data
--   * bars steady, BGE frame jumps -> multi-writer interleaving on the frame
--   * all bars jump               -> per-read/per-write behavior, not tokens
--
-- Secret-safety: UnitHealth/UnitHealthMax returns go STRAIGHT into
-- SetValue/SetMinMaxValues (SecretArgumentsAddAspect BarValue — allowed).
-- Presence checks are truthiness only (same battle-tested pattern as
-- HealthBar.lua). Labels are token key strings — never player data.
-- ============================================================================

local ROW_HEIGHT = 10
local ROW_WIDTH = 220
local ROW_GAP = 1
local UPDATE_PERIOD = 0.1

-- Explicit key list (mirrors UpdateEnemyUnitID's priority chain order).
-- Iterated explicitly so bookkeeping keys (TargetedByEnemy, HasAllyUnitID)
-- never render.
local UNIT_ID_KEYS = {
  "Arena",
  "Target",
  "Focus",
  "SoftEnemy",
  "Mouseover",
  "Nameplate",
  "PetTarget",
  "TargetTarget",
  "FocusTarget",
  "GroupTarget",
  "GroupPetTarget",
  "NameplateTarget",
  "ArenaTarget",
}

local rig = CreateFrame("Frame", "BGETokenRig", UIParent)
rig:SetSize(ROW_WIDTH, ROW_HEIGHT)
rig:SetFrameStrata("HIGH")
rig:SetPoint("BOTTOM", TargetFrame, "TOP", 0, 30)
rig:Hide()

local rows = {}

local function AcquireRow(i)
  local row = rows[i]
  if not row then
    row = CreateFrame("StatusBar", nil, rig)
    row:SetSize(ROW_WIDTH, ROW_HEIGHT)
    row:SetPoint("BOTTOMLEFT", rig, "BOTTOMLEFT", 0, (i - 1) * (ROW_HEIGHT + ROW_GAP))
    row:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    row:GetStatusBarTexture():SetVertexColor(0.1, 0.9, 0.2, 0.9)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    row.bg:SetVertexColor(0, 0, 0, 0.6)
    -- FontObject (not SetFont) — avoids the 12.0.7 inline-font/shadow issue.
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.label:SetJustifyH("LEFT")
    rows[i] = row
  end
  row:Show()
  return row
end

local shownCount = 0

local function ShowRow(index, label, tok, classColor)
  local row = AcquireRow(index)
  row.label:SetText(label .. "  " .. tostring(tok))
  if classColor then
    row:GetStatusBarTexture():SetVertexColor(classColor.r, classColor.g, classColor.b, 0.9)
  end
  if UnitExists(tok) then
    -- Same read flavor as the enemy path in PlayerButton:UNIT_HEALTH
    -- (default usePredicted, matching the real frames).
    local maxv = UnitHealthMax(tok)
    local h = UnitHealth(tok, true)
    if maxv and h then
      row:SetMinMaxValues(0, maxv)
      row:SetValue(h)
    end
    -- reads returned nothing: keep prior fill (mimics the real bar)
  end
end

local elapsedAcc = 0
rig:SetScript("OnUpdate", function(_, elapsed)
  elapsedAcc = elapsedAcc + elapsed
  if elapsedAcc < UPDATE_PERIOD then
    return
  end
  elapsedAcc = 0

  local BGE = BattleGroundEnemies
  local btn = BGE and BGE.currentTarget
  if not (btn and btn.PlayerIsEnemy and btn.UnitIDs) then
    for i = 1, #rows do
      rows[i]:Hide()
    end
    return
  end

  local classColor = btn.PlayerDetails and btn.PlayerDetails.PlayerClassColor

  local n = 0
  -- Row 1: the token the REAL frame's priority chain picked (its writer basis)
  if btn.unitID then
    n = n + 1
    ShowRow(n, "ACTIVE", btn.unitID, classColor)
  end
  for _, key in ipairs(UNIT_ID_KEYS) do
    local tok = btn.UnitIDs[key]
    if type(tok) == "string" then
      n = n + 1
      ShowRow(n, key, tok, classColor)
    end
  end
  for i = n + 1, #rows do
    rows[i]:Hide()
  end
end)

-- Only tick inside PvP instances: cheap visibility driver.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function()
  local _, instanceType = IsInInstance()
  if instanceType == "pvp" or instanceType == "arena" then
    rig:Show()
  else
    rig:Hide()
  end
end)
