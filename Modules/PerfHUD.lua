-- BGE PerfHUD glue: wires BattleGroundEnemies-specific instrumentation into the
-- generic, reusable PerfHUD-1.0 library (libs/PerfHUD-1.0).
--
-- This file is dev-only (package-addon.sh strips it + its SavedVariables from
-- the release). The library itself ships harmlessly but does nothing unless a
-- consumer like this glue instantiates it.
--
-- Behaviour is identical to the old standalone Modules/PerfHUD.lua: /bgehud
-- toggles a floating diagnostic window, same rows, same colours, same logger.
--
-- Hooks four hotspots flagged in the perf review:
--   BattleGroundEnemies:GetPlayerbuttonByUnitID  (matcher)
--   BattleGroundEnemies:ScanTargets              (periodic sweep)
--   playerButton:UpdateAll                       (per-button refresh)
--   playerButton:UNIT_HEALTH                     (also aliased to several events)
--
-- When the HUD is closed the wrappers short-circuit to a single boolean check
-- + tail call, so cost is negligible.

local BattleGroundEnemies = BattleGroundEnemies

local PerfHUD = LibStub and LibStub("PerfHUD-1.0", true)
if not PerfHUD then
  -- Library not present (e.g. stripped in some build). Nothing to do.
  return
end

local debugprofilestop = debugprofilestop
local collectgarbage = collectgarbage
local GetTime = GetTime
local string_format = string.format
local math_floor = math.floor

------------------------------------------------------------------------------
-- BGE-specific counters
------------------------------------------------------------------------------

-- Matcher cache-hit heuristic: count fast vs slow calls.
-- A "fast" call (<0.01ms = 10μs) suggests cache hit or early reject; "slow"
-- (>=10μs) suggests a full resolve walked some/all of the fallback tiers.
local CACHE_FAST_THRESHOLD_MS = 0.01
local matcherFast = 0
local matcherSlow = 0

-- UNIT_HEALTH alias dedup detector: track which buttons fired any UNIT_HEALTH
-- alias on the current frame. seenButtons is wiped each frame (onFrame); a
-- redundant fire (same button hit again before the frame boundary) increments
-- dedupRedundant. Tells us whether a per-frame dedup pass would pay off.
local seenButtons = {}
local dedupTotal = 0
local dedupRedundant = 0

-- Manual fallback BG-start tracker. GetBattlefieldInstanceRunTime() should work
-- in random/epic BGs but returns 0 in arenas / before match start. We capture
-- the start moment via PVP_MATCH_STATE_CHANGED → Engaged.
local _bgStartFallback = nil

------------------------------------------------------------------------------
-- BGE-specific metric sources
------------------------------------------------------------------------------

-- Death state cache. UnitIsDeadOrGhost is cheap but only needs polling at HUD
-- refresh tick (0.5s) — not per-frame.
local function getDeathState()
  if UnitIsGhost("player") then
    return "GHOST"
  end
  if UnitIsDeadOrGhost("player") then
    return "DEAD"
  end
  return "ALIVE"
end

-- Match state — derived from C_PvP. Categorises the BG lifecycle phase.
local function getMatchState()
  local _, instType = IsInInstance()
  if instType ~= "pvp" and instType ~= "arena" then
    return "world"
  end
  if not C_PvP or not C_PvP.GetActiveMatchState then
    return "?"
  end
  local s = C_PvP.GetActiveMatchState()
  if not s or not Enum or not Enum.PvPMatchState then
    return "?"
  end
  -- Enum.PvPMatchState: Inactive=0, Waiting=1, StartUp=2, Engaged=3,
  -- PostRound=4, Complete=5.
  if s == Enum.PvPMatchState.Inactive then
    return "lobby"
  end
  if s == Enum.PvPMatchState.Waiting then
    return "waiting"
  end
  if s == Enum.PvPMatchState.StartUp then
    return "startup"
  end
  if s == Enum.PvPMatchState.Engaged then
    return "engaged"
  end
  if s == Enum.PvPMatchState.PostRound then
    return "post-round"
  end
  if s == Enum.PvPMatchState.Complete then
    return "complete"
  end
  return "?"
end

-- BG elapsed time in milliseconds. GetBattlefieldInstanceRunTime is authoritative
-- for random/epic BGs; returns 0 outside a BG OR before the match begins — fall
-- back to our manual capture from PVP_MATCH_STATE_CHANGED → Engaged.
local function getBGElapsedMs()
  if GetBattlefieldInstanceRunTime then
    local t = GetBattlefieldInstanceRunTime()
    if t and t > 0 then
      return t
    end
  end
  if _bgStartFallback then
    return (GetTime() - _bgStartFallback) * 1000
  end
  return 0
end

-- Format milliseconds as "MM:SS" (or "H:MM:SS"). "—" for <=0. (Mirrors the
-- library helper; kept local so formatLogLine doesn't depend on instance state.)
local function formatElapsed(ms)
  if not ms or ms <= 0 then
    return "—"
  end
  local total = math_floor(ms / 1000)
  local h = math_floor(total / 3600)
  local m = math_floor((total % 3600) / 60)
  local s = total % 60
  if h > 0 then
    return string_format("%d:%02d:%02d", h, m, s)
  end
  return string_format("%d:%02d", m, s)
end

-- Count nameplates currently visible, split into enemy (attackable) and
-- friendly (non-attackable, excluding the player's own personal nameplate).
local function countNameplates()
  local enemy, friendly = 0, 0
  for i = 1, 40 do
    local token = "nameplate" .. i
    if UnitExists(token) then
      local ok, can = pcall(UnitCanAttack, "player", token)
      if ok and can then
        enemy = enemy + 1
      elseif not UnitIsUnit(token, "player") then
        friendly = friendly + 1
      end
    end
  end
  return enemy, friendly
end

-- Read the ON/OFF state (size-aware), active player-button count, and active
-- player-count bracket of one of BGE's containers ("Enemies" / "Allies").
local function getFrameState(side)
  local mf = BattleGroundEnemies[side]
  if not mf then
    return false, 0, "—"
  end
  local on = mf.enabled and true or false
  local count = (mf.PlayerList and #mf.PlayerList) or 0
  local pcc = mf.playerCountConfig
  local bracket
  if type(pcc) == "table" then
    bracket = string_format("%d-%d", pcc.minPlayerCount or 0, pcc.maxPlayerCount or 0)
  else
    bracket = "no profile"
  end
  return on, count, bracket
end

------------------------------------------------------------------------------
-- Build the HUD instance
------------------------------------------------------------------------------

-- Forward declarations: installHooks is referenced by onEnable below and
-- assigned in the Hooks section further down.
local installHooks, wrapButton, sweepExisting
local hooksInstalled = false

local hud = PerfHUD:New("BattleGroundEnemies", {
  savedVar = "BattleGroundEnemiesPerfHUD", -- per-char HUD state (declared in .toc)
  logSavedVar = "BattleGroundEnemiesPerfHUDLog", -- per-account logger (declared in .toc)
  slash = "bgehud",
  title = "BGE PerfHUD",
  tag = "|cffffd100[BGE PerfHUD]|r",
  addonName = "BattleGroundEnemiesFixed", -- for GetAddOnCPUUsage
  defaultEnabled = true,
  -- Only sample the logger while actually inside a BG/arena instance.
  logGate = function()
    local _, instType = IsInInstance()
    return instType == "pvp" or instType == "arena"
  end,
  -- Reproduce the original /bgehud "log dump" line format.
  formatLogLine = function(s)
    local ctx = s.context or {}
    return string_format(
      "%s %s bg %s fps=%d frame=%.0fms np=%d mem=%+.0fK/s",
      formatElapsed(ctx.bgElapsedMs),
      ctx.deathState or "?",
      ctx.matchState or "?",
      s.fps or 0,
      s.frameWorst or 0,
      s.nameplates or 0,
      s.luaMem or 0
    )
  end,
  -- Wipe the per-frame "seen UNIT_HEALTH alias" set once per render frame, which
  -- defines the dedup window as one frame.
  onFrame = function()
    for k in pairs(seenButtons) do
      seenButtons[k] = nil
    end
  end,
  -- Install BGE's hooks when the HUD is first enabled.
  onEnable = function(h)
    installHooks(h)
  end,
})

------------------------------------------------------------------------------
-- Rows (registered in display order — must match the original layout)
------------------------------------------------------------------------------

-- Combined match state / death state / BG time.
hud:AddMetric("context", "Context", {
  update = function()
    return {
      matchState = getMatchState(),
      deathState = getDeathState(),
      bgElapsedMs = getBGElapsedMs(),
    }
  end,
  render = function(v, h)
    local deathColor = (v.deathState == "ALIVE" and "|cff66dd66")
      or (v.deathState == "DEAD" and "|cffff5555")
      or "|cffffcc44"
    local stateColor = (v.matchState == "engaged" and "|cff66dd66")
      or (v.matchState == "lobby" and "|cffffcc44")
      or "|cff8888aa"
    return string_format(
      "%s%s|r  %s%s|r  bg %s",
      stateColor,
      v.matchState,
      deathColor,
      v.deathState,
      h:FormatElapsed(v.bgElapsedMs)
    )
  end,
})

-- Nameplate counts. The "nameplates" row computes both enemy and friendly in
-- one pass and stashes the friendly count for the next row (which renders right
-- after it, in registration order).
hud:AddMetric("nameplates", "Enemy nameplates", {
  update = function(h)
    local enemy, friendly = countNameplates()
    h._bgeFriendlyNameplates = friendly
    return enemy
  end,
  render = function(v)
    local color = (v >= 20 and "|cffff5555") or (v >= 10 and "|cffffcc44") or "|cff66dd66"
    return string_format("Enemy nameplates: %s%d|r visible", color, v)
  end,
})

hud:AddMetric("friendlyNameplates", "Friendly nameplates", {
  update = function(h)
    return h._bgeFriendlyNameplates or 0
  end,
  render = function(v)
    local color = (v >= 20 and "|cffff5555") or (v >= 10 and "|cffffcc44") or "|cff66dd66"
    return string_format("Friendly nameplates: %s%d|r visible", color, v)
  end,
})

hud:AddMetric("enemyFrames", "Enemy frames", {
  update = function()
    local on, count, bracket = getFrameState("Enemies")
    return { on = on, count = count, bracket = bracket }
  end,
  render = function(v)
    local onStr, offStr = "|cff66dd66ON|r", "|cff888888OFF|r"
    return string_format(
      "Enemy frames: %s  %d buttons  |cff8888aa[%s]|r",
      v.on and onStr or offStr,
      v.count,
      v.bracket
    )
  end,
})

hud:AddMetric("allyFrames", "Ally frames", {
  update = function()
    local on, count, bracket = getFrameState("Allies")
    return { on = on, count = count, bracket = bracket }
  end,
  render = function(v)
    local onStr, offStr = "|cff66dd66ON|r", "|cff888888OFF|r"
    return string_format(
      "Ally frames: %s  %d buttons  |cff8888aa[%s]|r",
      v.on and onStr or offStr,
      v.count,
      v.bracket
    )
  end,
})

-- Universal rows.
hud:AddBuiltin("fps")
hud:AddBuiltin("frameWorst")
hud:AddBuiltin("addonCpu")
hud:AddBuiltin("luaMem")
hud:AddBuiltin("memRate")

-- Per-button frame CPU (12.0.7 re-enabled GetFrameCPUUsage). Sums the real CPU
-- time spent in every enemy/ally button frame + child regions per refresh tick.
-- This is strictly richer than the UpdateAll/UNIT_HEALTH debugprofilestop
-- wrappers below, which only time the two methods we explicitly wrap — this row
-- captures ALL scripts on the button + its child regions (healthbar/power/etc).
-- Requires scriptProfile=1 (set the prior session + /reload); GetFrameCPUUsage
-- returns 0 otherwise, so the row self-gates on the same CVar as the addon-CPU row.
local GetFrameCPUUsage = GetFrameCPUUsage
local cpuProfilingEnabled = PerfHUD.CpuProfilingEnabled or function()
  return false
end
-- Weak keys: pooled buttons may be GC'd; don't pin them. Stores the previous
-- cumulative (call_time, call_count) per button so we can report a per-tick delta
-- without ResetCPUUsage() (which is global and would clobber other addons).
local prevBtnCpu = setmetatable({}, { __mode = "k" })
local SIDES = { "Enemies", "Allies" }

-- Per-button CPU delta since the last tick (call_time ms, call_count). Module-level
-- (not a per-call closure) so the refresh loop allocates nothing beyond the one-time
-- baseline table per newly-seen button.
local function btnCpuDelta(btn)
  -- includeChildren = true: count the button's child regions too.
  local ms, calls = GetFrameCPUUsage(btn, true)
  ms = ms or 0
  calls = calls or 0
  local rec = prevBtnCpu[btn]
  if not rec then
    -- First sight: seed the baseline, contribute 0 (avoid a spike from counting
    -- the button's entire pre-existing cumulative).
    prevBtnCpu[btn] = { ms = ms, calls = calls }
    return 0, 0
  end
  -- Cumulative since login; a decrease means the engine reset the counter — skip
  -- that tick rather than report a negative.
  local dMs, dCalls = 0, 0
  if ms >= rec.ms then
    dMs = ms - rec.ms
    dCalls = calls - rec.calls
  end
  rec.ms = ms
  rec.calls = calls
  return dMs, dCalls
end

local function sumButtonCpuDelta()
  local totalMs, totalCalls = 0, 0
  for _, side in ipairs(SIDES) do
    local mf = BattleGroundEnemies[side]
    if mf then
      if mf.Players then
        for _, btn in pairs(mf.Players) do
          local dMs, dCalls = btnCpuDelta(btn)
          totalMs = totalMs + dMs
          totalCalls = totalCalls + dCalls
        end
      end
      if mf.InactivePlayerButtons then
        for _, btn in pairs(mf.InactivePlayerButtons) do
          local dMs, dCalls = btnCpuDelta(btn)
          totalMs = totalMs + dMs
          totalCalls = totalCalls + dCalls
        end
      end
    end
  end
  return totalMs, totalCalls
end

hud:AddMetric("buttonCpu", "Button frame CPU", {
  update = function(h)
    if not GetFrameCPUUsage or not cpuProfilingEnabled() then
      return nil
    end
    local ms, calls = sumButtonCpuDelta()
    return { msPerSec = ms / h.refreshInterval, calls = calls }
  end,
  render = function(v)
    if not v then
      return "Button frame CPU: |cff888888off (scriptProfile 0)|r"
    end
    local color = (v.msPerSec >= 8 and "|cffff5555") or (v.msPerSec >= 2 and "|cffffcc44") or "|cff66dd66"
    return string_format("Button frame CPU: %s%.1f ms/s|r  (%d calls)", color, v.msPerSec, v.calls)
  end,
})

-- Matcher cache-hit heuristic: % of calls under the fast threshold.
hud:AddMetric("cacheHit", "Matcher fast lookups", {
  update = function()
    local v = { fast = matcherFast, slow = matcherSlow }
    matcherFast = 0
    matcherSlow = 0
    return v
  end,
  render = function(v)
    local total = v.fast + v.slow
    if total <= 0 then
      return "Matcher fast lookups: —"
    end
    local pct = (v.fast / total) * 100
    local color = (pct >= 85 and "|cff66dd66") or (pct >= 60 and "|cffffcc44") or "|cffff5555"
    return string_format("Matcher fast lookups: %s%.0f%%|r  (%d fast / %d slow)", color, pct, v.fast, v.slow)
  end,
})

-- UNIT_HEALTH redundant fires: % of fires hitting a button already seen this frame.
hud:AddMetric("uhDedup", "UH redundant fires", {
  update = function()
    local v = { total = dedupTotal, redundant = dedupRedundant }
    dedupTotal = 0
    dedupRedundant = 0
    return v
  end,
  render = function(v)
    if v.total <= 0 then
      return "UH redundant fires: —"
    end
    local pct = (v.redundant / v.total) * 100
    -- Inverted thresholds — high redundancy is bad.
    local color = (pct >= 50 and "|cffff5555") or (pct >= 25 and "|cffffcc44") or "|cff66dd66"
    return string_format("UH redundant fires: %s%.0f%%|r  (%d of %d)", color, pct, v.redundant, v.total)
  end,
})

-- Per-hotspot rows. Matcher uses higher calls/s thresholds (it's a hot matcher).
hud:AddPathRow("Matcher", { warnRate = 200, badRate = 800 })
hud:AddPathRow("ScanTargets")
hud:AddPathRow("UpdateAll")
hud:AddPathRow("UNIT_HEALTH", { displayLabel = "UNIT_HEALTH*" })

------------------------------------------------------------------------------
-- Hooks
------------------------------------------------------------------------------

installHooks = function(h)
  if hooksInstalled then
    return
  end
  hooksInstalled = true

  -- Matcher (singleton method). Custom wrapper so we can also count fast/slow.
  local origMatcher = BattleGroundEnemies.GetPlayerbuttonByUnitID
  if origMatcher then
    BattleGroundEnemies.GetPlayerbuttonByUnitID = function(self, ...)
      if not h.enabled then
        return origMatcher(self, ...)
      end
      local m0 = collectgarbage("count")
      local t0 = debugprofilestop()
      local a, b, c, d = origMatcher(self, ...)
      local dt = debugprofilestop() - t0
      h:Record("Matcher", dt, collectgarbage("count") - m0)
      if dt < CACHE_FAST_THRESHOLD_MS then
        matcherFast = matcherFast + 1
      else
        matcherSlow = matcherSlow + 1
      end
      return a, b, c, d
    end
  end

  -- ScanTargets (singleton method) — plain timing wrap.
  h:Profile(BattleGroundEnemies, "ScanTargets", "ScanTargets")

  -- Per-button methods (UpdateAll, UNIT_HEALTH). Set as closures inside
  -- CreatePlayerButton, so wrap each button after construction. hooksecurefunc
  -- catches new ones; sweepExisting() catches buttons already created when the
  -- HUD turns on.
  if BattleGroundEnemies.CreatePlayerButton then
    hooksecurefunc(BattleGroundEnemies, "CreatePlayerButton", function(self, mainframe, num)
      if not mainframe or not mainframe.PlayerType or not num then
        return
      end
      local btnName = "BattleGroundEnemies" .. mainframe.PlayerType .. "frame" .. num
      wrapButton(_G[btnName])
    end)
  end
  sweepExisting()
end

-- Wrap an individual button's hot methods. Idempotent via _perfWrapped flag.
wrapButton = function(btn)
  if not btn or btn._perfWrapped then
    return
  end
  btn._perfWrapped = true

  local origUpdateAll = btn.UpdateAll
  if origUpdateAll then
    btn.UpdateAll = hud:Wrap(origUpdateAll, "UpdateAll")
  end

  local origUH = btn.UNIT_HEALTH
  if origUH then
    -- Custom wrapper so we can also detect per-frame redundant fires.
    local wrapped = function(self_, ...)
      if not hud.enabled then
        return origUH(self_, ...)
      end
      dedupTotal = dedupTotal + 1
      if seenButtons[self_] then
        dedupRedundant = dedupRedundant + 1
      else
        seenButtons[self_] = true
      end
      local m0 = collectgarbage("count")
      local t0 = debugprofilestop()
      local a, b, c, d = origUH(self_, ...)
      hud:Record("UNIT_HEALTH", debugprofilestop() - t0, collectgarbage("count") - m0)
      return a, b, c, d
    end
    btn.UNIT_HEALTH = wrapped
    -- Aliases set in PlayerButton.lua right after UNIT_HEALTH is defined still
    -- point at the original closure. Re-point so they're counted too.
    -- UNIT_MAXHEALTH is deliberately NOT re-pointed: it's a REAL handler now
    -- (flags the health bar's range dirty), not an alias — re-pointing would
    -- silently clobber that behavior while profiling. It delegates to
    -- self:UNIT_HEALTH, which resolves to `wrapped` at call time, so its
    -- work is still counted.
    btn.UNIT_HEALTH_FREQUENT = wrapped
    btn.UNIT_HEAL_PREDICTION = wrapped
    btn.UNIT_ABSORB_AMOUNT_CHANGED = wrapped
    btn.UNIT_HEAL_ABSORB_AMOUNT_CHANGED = wrapped
  end
end

-- Walk both mainframes and wrap every active + pooled button.
sweepExisting = function()
  for _, side in ipairs(SIDES) do
    local mf = BattleGroundEnemies[side]
    if mf then
      if mf.Players then
        for _, btn in pairs(mf.Players) do
          wrapButton(btn)
        end
      end
      if mf.InactivePlayerButtons then
        for _, btn in pairs(mf.InactivePlayerButtons) do
          wrapButton(btn)
        end
      end
    end
  end
end

------------------------------------------------------------------------------
-- Lifecycle: restore HUD state on login + drive the auto-logger flush events
------------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PVP_MATCH_STATE_CHANGED")
loader:RegisterEvent("PVP_MATCH_COMPLETE")
loader:RegisterEvent("PVP_MATCH_INACTIVE")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("PLAYER_LOGOUT") -- fires on /reload too — final safety flush
loader:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then
    -- PerfHUD is dev-only (stripped from the release), so for the maintainer it
    -- should ALWAYS be on — never silently off. Force-enable on every
    -- login/reload regardless of the saved toggle. /bgehud (or the window's X)
    -- still hides it for the session; the next reload restores it.
    hud:SetEnabled(true)
    return
  end
  if event == "PVP_MATCH_STATE_CHANGED" then
    -- Capture the BG start moment for the fallback timer. DO NOT flush here —
    -- we want the full lifecycle in a single SV entry (flushed on zone-leave).
    if C_PvP and C_PvP.GetActiveMatchState and Enum and Enum.PvPMatchState then
      if C_PvP.GetActiveMatchState() == Enum.PvPMatchState.Engaged then
        _bgStartFallback = GetTime()
      end
    end
    return
  end
  if event == "PVP_MATCH_COMPLETE" then
    return -- no-op; wait for zone-leave to flush the whole lifecycle
  end
  if event == "PVP_MATCH_INACTIVE" then
    _bgStartFallback = nil
    return
  end
  if event == "PLAYER_ENTERING_WORLD" then
    -- Leaving an instance back to the world is the primary flush trigger.
    local _, instType = IsInInstance()
    if instType ~= "pvp" and instType ~= "arena" and hud:GetLogCount() > 0 then
      hud:FlushLog("PLAYER_ENTERING_WORLD-out")
    end
    return
  end
  if event == "PLAYER_LOGOUT" and hud:GetLogCount() > 0 then
    -- /reload or full exit while still in-zone. Capture whatever we have.
    hud:FlushLog("PLAYER_LOGOUT")
    return
  end
end)

-- Expose the instance for inspection / reuse from other BGE code.
BattleGroundEnemies.PerfHUD = hud
