-- PerfHUD: floating, draggable diagnostic window for BGE perf hotspots.
--
-- Toggle in-game with /bgehud. State and position persist via the
-- BattleGroundEnemiesPerfHUD per-character saved variable (declared in the .toc).
--
-- Hooks four hotspots flagged in the perf review:
--   BattleGroundEnemies:GetPlayerbuttonByUnitID  (matcher)
--   BattleGroundEnemies:ScanTargets              (periodic sweep)
--   playerButton:UpdateAll                       (per-button refresh)
--   playerButton:UNIT_HEALTH                     (also aliased to several events)
--
-- When the HUD is closed (M.enabled == false), the wrappers short-circuit
-- to a single boolean check + tail call, so cost is negligible.

local _addonName, Data = ...

local BattleGroundEnemies = BattleGroundEnemies

local M = {}
BattleGroundEnemies.PerfHUD = M

local debugprofilestop = debugprofilestop
local GetFramerate = GetFramerate
local GetTime = GetTime
local collectgarbage = collectgarbage
local GetAddOnCPUUsage = (C_AddOns and C_AddOns.GetAddOnCPUUsage) or GetAddOnCPUUsage
local UpdateAddOnCPUUsage = (C_AddOns and C_AddOns.UpdateAddOnCPUUsage) or UpdateAddOnCPUUsage
local string_format = string.format
local math_max = math.max
local math_floor = math.floor

------------------------------------------------------------------------------
-- Counters
------------------------------------------------------------------------------

-- Per-hotspot accumulators. Reset every refresh tick so the HUD shows
-- "per second" rates over the most recent window.
local PATHS = { "Matcher", "ScanTargets", "UpdateAll", "UNIT_HEALTH" }

local function newBucket()
  return { calls = 0, totalMs = 0, worstMs = 0, allocKB = 0 }
end

local stats = {}
for _, k in ipairs(PATHS) do
  stats[k] = newBucket()
end

-- Matcher cache-hit heuristic: count fast vs slow calls.
-- A "fast" call (<0.01ms = 10μs) suggests cache hit or early reject; "slow"
-- (>=10μs) suggests a full resolve walked some/all of the fallback tiers.
local CACHE_FAST_THRESHOLD_MS = 0.01
local matcherFast = 0
local matcherSlow = 0

-- UNIT_HEALTH alias dedup detector: track which buttons fired any UNIT_HEALTH
-- alias on the current frame. seenButtons is wiped each frame in onUpdate;
-- redundant fires (same button hit again before frame boundary) increment
-- dedupRedundant. Tells us whether a per-frame dedup pass would pay off.
local seenButtons = {}
local dedupTotal = 0
local dedupRedundant = 0

-- Frame-time tracker: worst ms between two consecutive OnUpdate firings
-- over the rolling display window (5s). Driven by the HUD frame's OnUpdate.
local frameWorst = 0
local lastFrameTime = nil

-- Lua memory delta tracker. collectgarbage("count") returns KB.
local lastMemKB = nil

-- Display window for "worst frame" — a 5s sliding window via simple decay.
local worstWindow = { value = 0, expires = 0 }

-- Memory growth rate over the last 30s — smoother signal than the per-tick
-- mem Δ which is jittery (catches GC sweeps as huge negatives, then bounces).
-- Ring buffer of (timestamp, totalMemKB) pairs; rate = (newest - oldest) / span.
local memSamples = {} -- ring buffer
local MEM_SAMPLE_WINDOW = 30 -- seconds

-- Manual fallback BG-start tracker. GetBattlefieldInstanceRunTime() should
-- work in random/epic BGs but returns 0 in arenas / before match starts.
-- We capture the start moment via PVP_MATCH_STATE_CHANGED → Active.
local _bgStartFallback = nil

-- Auto-logger: ring buffer of samples while in a BG.
-- Each sample = a snapshot of the HUD's measured values + context fields.
-- Sampled every LOG_SAMPLE_INTERVAL seconds in onUpdate. Pushed to per-account
-- SavedVariable on PVP_MATCH_COMPLETE / PLAYER_LEAVING_BATTLEGROUND.
local LOG_SAMPLE_INTERVAL = 2
local LOG_RING_SIZE = 1000 -- ~33 minutes at 2s sampling
local logBuffer = {}
local logHead = 0 -- write index
local logCount = 0
local logAccum = 0 -- elapsed since last sample
local logEnabled = true -- can be toggled via /bgehud log on/off

-- Cached "last refresh" results for the auto-logger (so log() doesn't have
-- to recompute everything that refresh() already computed). Populated at the
-- end of refresh().
local lastSnapshot = nil

-- Death state cache. UnitIsDeadOrGhost is cheap but only needs polling at
-- HUD refresh tick (0.5s) — not per-frame.
local function getDeathState()
  if UnitIsGhost("player") then
    return "GHOST"
  end
  if UnitIsDeadOrGhost("player") then
    return "DEAD"
  end
  return "ALIVE"
end

-- Match state — derived from C_PvP. Categorises the BG lifecycle phase so
-- screenshots / logs don't need manual captioning.
local function getMatchState()
  if not C_PvP or not C_PvP.GetActiveMatchState then
    return "?"
  end
  local s = C_PvP.GetActiveMatchState()
  if not s or not Enum or not Enum.PvPMatchState then
    return "?"
  end
  if s == Enum.PvPMatchState.Inactive then
    return "lobby"
  end
  if s == Enum.PvPMatchState.StartUp then
    return "startup"
  end
  if s == Enum.PvPMatchState.Engaged then
    return "active"
  end
  if s == Enum.PvPMatchState.PostRound then
    return "post-round"
  end
  if s == Enum.PvPMatchState.Complete then
    return "complete"
  end
  return "?"
end

-- BG elapsed time in milliseconds. GetBattlefieldInstanceRunTime is the
-- authoritative source for random/epic BGs. Returns 0 outside a BG OR
-- before the match has actually begun (lobby phase) — fall back to our
-- manual capture from PVP_MATCH_STATE_CHANGED → Active for those cases.
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

-- Format milliseconds as "MM:SS" (or "H:MM:SS" if it's been hours).
local function formatElapsed(ms)
  if not ms or ms <= 0 then
    return "—"
  end
  local total = math.floor(ms / 1000)
  local h = math.floor(total / 3600)
  local m = math.floor((total % 3600) / 60)
  local s = total % 60
  if h > 0 then
    return string_format("%d:%02d:%02d", h, m, s)
  end
  return string_format("%d:%02d", m, s)
end

-- Count nameplates currently visible on screen, split into enemy (attackable)
-- and friendly (non-attackable, excluding the player's own personal nameplate).
-- Cheap: ~40 UnitExists/UnitCanAttack calls per refresh tick (0.5s). Same
-- pattern ScanTargets uses internally.
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

-- Read the ON/OFF state, active player-button count, and the active
-- player-count bracket of one of BGE's own containers ("Enemies" or "Allies").
--
-- `enabled` is the flag set in mainframe:Enable()/Disable(). It is ALREADY
-- size-aware: CheckEnableState gates it on `playerCountConfig.Enabled`, the
-- per-bracket toggle (1-5 / 6-15 / 16-40 / …), so turning a bracket off makes
-- `enabled` false while that bracket is the active one. We surface the active
-- bracket range too, so an OFF isn't ambiguous between "this size is toggled
-- off" and "no profile matches this size" (playerCountConfig == false).
--
-- PlayerList is the index→button array of active buttons (parallel to Players,
-- safe to # under secret names — pairs() on the secret-keyed Players map can
-- taint, PlayerList can't). Returns (on, count, bracketLabel).
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
    -- playerCountConfig is false: no bracket matched this size (or >40).
    bracket = "no profile"
  end
  return on, count, bracket
end

------------------------------------------------------------------------------
-- Recording
------------------------------------------------------------------------------

local function record(path, ms)
  local b = stats[path]
  if not b then
    return
  end
  b.calls = b.calls + 1
  b.totalMs = b.totalMs + ms
  if ms > b.worstMs then
    b.worstMs = ms
  end
end

M.Record = record

------------------------------------------------------------------------------
-- Hooks
------------------------------------------------------------------------------

local hooksInstalled = false
local wrapButton, sweepExisting

local function installHooks()
  if hooksInstalled then
    return
  end
  hooksInstalled = true

  -- Matcher (singleton method).
  local origMatcher = BattleGroundEnemies.GetPlayerbuttonByUnitID
  if origMatcher then
    BattleGroundEnemies.GetPlayerbuttonByUnitID = function(self, ...)
      if not M.enabled then
        return origMatcher(self, ...)
      end
      local m0 = collectgarbage("count")
      local t0 = debugprofilestop()
      local a, b, c, d = origMatcher(self, ...)
      local dt = debugprofilestop() - t0
      record("Matcher", dt)
      local dm = collectgarbage("count") - m0
      if dm > 0 then
        stats.Matcher.allocKB = stats.Matcher.allocKB + dm
      end
      if dt < CACHE_FAST_THRESHOLD_MS then
        matcherFast = matcherFast + 1
      else
        matcherSlow = matcherSlow + 1
      end
      return a, b, c, d
    end
  end

  -- ScanTargets (singleton method).
  local origScan = BattleGroundEnemies.ScanTargets
  if origScan then
    BattleGroundEnemies.ScanTargets = function(self, ...)
      if not M.enabled then
        return origScan(self, ...)
      end
      local m0 = collectgarbage("count")
      local t0 = debugprofilestop()
      local a, b, c, d = origScan(self, ...)
      record("ScanTargets", debugprofilestop() - t0)
      local dm = collectgarbage("count") - m0
      if dm > 0 then
        stats.ScanTargets.allocKB = stats.ScanTargets.allocKB + dm
      end
      return a, b, c, d
    end
  end

  -- Per-button methods (UpdateAll, UNIT_HEALTH). These are set as
  -- closures inside CreatePlayerButton, so we must wrap each button after
  -- it's constructed. hooksecurefunc catches new ones; sweepExisting()
  -- catches buttons that already exist when the HUD turns on.
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
    btn.UpdateAll = function(self_, ...)
      if not M.enabled then
        return origUpdateAll(self_, ...)
      end
      local m0 = collectgarbage("count")
      local t0 = debugprofilestop()
      local a, b, c, d = origUpdateAll(self_, ...)
      record("UpdateAll", debugprofilestop() - t0)
      local dm = collectgarbage("count") - m0
      if dm > 0 then
        stats.UpdateAll.allocKB = stats.UpdateAll.allocKB + dm
      end
      return a, b, c, d
    end
  end

  local origUH = btn.UNIT_HEALTH
  if origUH then
    local wrapped = function(self_, ...)
      if not M.enabled then
        return origUH(self_, ...)
      end
      -- Per-frame dedup detection: track if this button has fired any UH
      -- alias on this frame already. Increments redundant counter when so.
      dedupTotal = dedupTotal + 1
      if seenButtons[self_] then
        dedupRedundant = dedupRedundant + 1
      else
        seenButtons[self_] = true
      end
      local m0 = collectgarbage("count")
      local t0 = debugprofilestop()
      local a, b, c, d = origUH(self_, ...)
      record("UNIT_HEALTH", debugprofilestop() - t0)
      local dm = collectgarbage("count") - m0
      if dm > 0 then
        stats.UNIT_HEALTH.allocKB = stats.UNIT_HEALTH.allocKB + dm
      end
      return a, b, c, d
    end
    btn.UNIT_HEALTH = wrapped
    -- Aliases set in PlayerButton.lua right after UNIT_HEALTH is defined
    -- still point at the original closure. Re-point so they're counted too.
    btn.UNIT_HEALTH_FREQUENT = wrapped
    btn.UNIT_MAXHEALTH = wrapped
    btn.UNIT_HEAL_PREDICTION = wrapped
    btn.UNIT_ABSORB_AMOUNT_CHANGED = wrapped
    btn.UNIT_HEAL_ABSORB_AMOUNT_CHANGED = wrapped
  end
end

-- Walk both mainframes and wrap every active + pooled button.
sweepExisting = function()
  for _, side in ipairs({ "Enemies", "Allies" }) do
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
-- HUD frame
------------------------------------------------------------------------------

local hud
local lines = {}
local refreshAccum = 0
local REFRESH_INTERVAL = 0.5

local LABELS = {
  { key = "context", label = "Context" }, -- combined match state / death state / BG time
  { key = "nameplates", label = "Enemy nameplates" },
  { key = "friendlyNameplates", label = "Friendly nameplates" },
  { key = "enemyFrames", label = "Enemy frames" },
  { key = "allyFrames", label = "Ally frames" },
  { key = "fps", label = "FPS" },
  { key = "frame", label = "Frame worst (5s)" },
  { key = "cpu", label = "Addon CPU" },
  { key = "mem", label = "Lua mem Δ" },
  { key = "memRate", label = "Mem growth (30s)" },
  { key = "cacheHit", label = "Matcher fast lookups" },
  { key = "uhDedup", label = "UH redundant fires" },
  { key = "Matcher", label = "Matcher" },
  { key = "ScanTargets", label = "ScanTargets" },
  { key = "UpdateAll", label = "UpdateAll" },
  { key = "UNIT_HEALTH", label = "UNIT_HEALTH*" },
}

local function colorForMs(ms, warn, bad)
  if ms >= bad then
    return "|cffff5555"
  end
  if ms >= warn then
    return "|cffffcc44"
  end
  return "|cff66dd66"
end

local function colorForRate(rate, warn, bad)
  if rate >= bad then
    return "|cffff5555"
  end
  if rate >= warn then
    return "|cffffcc44"
  end
  return "|cff66dd66"
end

local function refresh()
  -- Capture counters that get reset later in this function. These need to
  -- be snapshotted BEFORE the cacheHit / uhDedup / per-path blocks zero them.
  local _snapCacheFast = matcherFast
  local _snapCacheSlow = matcherSlow
  local _snapDedupTotal = dedupTotal
  local _snapDedupRedundant = dedupRedundant

  -- Context line: match state, death state, BG elapsed time. Combined into
  -- one line to save vertical space.
  local matchState = getMatchState()
  local deathState = getDeathState()
  local bgElapsed = getBGElapsedMs()
  local deathColor = (deathState == "ALIVE" and "|cff66dd66") or (deathState == "DEAD" and "|cffff5555") or "|cffffcc44"
  local stateColor = (matchState == "active" and "|cff66dd66")
    or (matchState == "lobby" and "|cffffcc44")
    or "|cff8888aa"
  lines.context:SetText(
    string_format("%s%s|r  %s%s|r  bg %s", stateColor, matchState, deathColor, deathState, formatElapsed(bgElapsed))
  )

  -- Nameplate counts (enemy = attackable, friendly = non-attackable).
  local nameplateCount, friendlyNameplateCount = countNameplates()
  local npColor = (nameplateCount >= 20 and "|cffff5555") or (nameplateCount >= 10 and "|cffffcc44") or "|cff66dd66"
  lines.nameplates:SetText(string_format("Enemy nameplates: %s%d|r visible", npColor, nameplateCount))
  local fnpColor = (friendlyNameplateCount >= 20 and "|cffff5555")
    or (friendlyNameplateCount >= 10 and "|cffffcc44")
    or "|cff66dd66"
  lines.friendlyNameplates:SetText(
    string_format("Friendly nameplates: %s%d|r visible", fnpColor, friendlyNameplateCount)
  )

  -- BGE's own container state: ON/OFF (size-aware) + active player-button
  -- count + the active player-count bracket.
  local enemyOn, enemyCount, enemyBracket = getFrameState("Enemies")
  local allyOn, allyCount, allyBracket = getFrameState("Allies")
  local onStr, offStr = "|cff66dd66ON|r", "|cff888888OFF|r"
  lines.enemyFrames:SetText(
    string_format("Enemy frames: %s  %d buttons  |cff8888aa[%s]|r", enemyOn and onStr or offStr, enemyCount, enemyBracket)
  )
  lines.allyFrames:SetText(
    string_format("Ally frames: %s  %d buttons  |cff8888aa[%s]|r", allyOn and onStr or offStr, allyCount, allyBracket)
  )

  local fps = GetFramerate()
  local fpsColor = (fps < 30 and "|cffff5555") or (fps < 60 and "|cffffcc44") or "|cff66dd66"
  lines.fps:SetText(string_format("FPS: %s%.0f|r", fpsColor, fps))

  -- Worst frame: decay the 5s window.
  local now = GetTime()
  if now > worstWindow.expires then
    worstWindow.value = frameWorst
    worstWindow.expires = now + 5
  else
    worstWindow.value = math_max(worstWindow.value, frameWorst)
  end
  local fw = worstWindow.value * 1000
  lines.frame:SetText(string_format("Frame worst (5s): %s%.1f ms|r", colorForMs(fw, 33, 50), fw))
  frameWorst = 0

  -- Addon CPU (only meaningful with /console scriptProfile 1).
  if GetAddOnCPUUsage and UpdateAddOnCPUUsage then
    UpdateAddOnCPUUsage()
    local ms = GetAddOnCPUUsage("BattleGroundEnemiesFixed") or 0
    lines.cpu:SetText(string_format("Addon CPU: %s%.0f ms|r (since login)", colorForMs(ms, 5000, 20000), ms))
  else
    lines.cpu:SetText("Addon CPU: n/a")
  end

  -- Lua memory delta.
  local mem = collectgarbage("count")
  local delta = lastMemKB and (mem - lastMemKB) or 0
  lastMemKB = mem
  local perSec = delta / REFRESH_INTERVAL
  lines.mem:SetText(
    string_format("Lua mem Δ: %s%+.1f KB/s|r  (total %.0f KB)", colorForRate(perSec, 50, 200), perSec, mem)
  )

  -- Smoothed memory growth over the last 30s. Ring buffer of (time, mem)
  -- samples; rate = (newest mem - oldest mem) / time span. Subtracting
  -- positive deltas from negative GC sweeps gives the *net* allocation
  -- pressure — a much more honest signal than the per-tick mem Δ.
  local nowT = GetTime()
  memSamples[#memSamples + 1] = { t = nowT, mem = mem }
  -- Drop samples older than the window.
  while #memSamples > 0 and (nowT - memSamples[1].t) > MEM_SAMPLE_WINDOW do
    table.remove(memSamples, 1)
  end
  if #memSamples >= 2 then
    local oldest = memSamples[1]
    local span = nowT - oldest.t
    if span > 0 then
      local rate = (mem - oldest.mem) / span
      lines.memRate:SetText(
        string_format("Mem growth (%ds): %s%+.1f KB/s|r", math.floor(span + 0.5), colorForRate(rate, 100, 500), rate)
      )
    else
      lines.memRate:SetText("Mem growth (30s): —")
    end
  else
    lines.memRate:SetText("Mem growth (30s): —")
  end

  -- Matcher cache-hit heuristic: % of calls under the fast threshold.
  -- High % = mostly cache hits / early rejects (good).
  -- Low % = lots of full resolves (bad — fix the cache).
  local mTotal = matcherFast + matcherSlow
  if mTotal > 0 then
    local pct = (matcherFast / mTotal) * 100
    local color = (pct >= 85 and "|cff66dd66") or (pct >= 60 and "|cffffcc44") or "|cffff5555"
    lines.cacheHit:SetText(
      string_format("Matcher fast lookups: %s%.0f%%|r  (%d fast / %d slow)", color, pct, matcherFast, matcherSlow)
    )
  else
    lines.cacheHit:SetText("Matcher fast lookups: —")
  end
  matcherFast = 0
  matcherSlow = 0

  -- UNIT_HEALTH redundant fires: % of fires that hit a button already seen
  -- earlier in the same frame. High % = dedup would be a big win.
  if dedupTotal > 0 then
    local pct = (dedupRedundant / dedupTotal) * 100
    -- Inverted thresholds — high redundancy is bad.
    local color = (pct >= 50 and "|cffff5555") or (pct >= 25 and "|cffffcc44") or "|cff66dd66"
    lines.uhDedup:SetText(
      string_format("UH redundant fires: %s%.0f%%|r  (%d of %d)", color, pct, dedupRedundant, dedupTotal)
    )
  else
    lines.uhDedup:SetText("UH redundant fires: —")
  end
  dedupTotal = 0
  dedupRedundant = 0

  -- Per-path stats. Express as calls/sec, ms/sec, alloc KB/sec, worst ms.
  -- Capture into snapshot for the auto-logger before resetting buckets.
  local snap = {
    t = GetTime(),
    matchState = matchState,
    deathState = deathState,
    bgElapsedMs = bgElapsed,
    nameplates = nameplateCount,
    friendlyNameplates = friendlyNameplateCount,
    enemyFramesOn = enemyOn,
    enemyFrameCount = enemyCount,
    enemyBracket = enemyBracket,
    allyFramesOn = allyOn,
    allyFrameCount = allyCount,
    allyBracket = allyBracket,
    fps = fps,
    frameWorstMs = fw,
    luaMemKB = mem,
    luaMemDeltaPerSec = perSec,
    cacheFast = _snapCacheFast,
    cacheSlow = _snapCacheSlow,
    dedupTotal = _snapDedupTotal,
    dedupRedundant = _snapDedupRedundant,
    paths = {},
  }
  for _, key in ipairs(PATHS) do
    local b = stats[key]
    local callsPerSec = b.calls / REFRESH_INTERVAL
    local msPerSec = b.totalMs / REFRESH_INTERVAL
    local allocPerSec = b.allocKB / REFRESH_INTERVAL
    local label = (key == "UNIT_HEALTH") and "UNIT_HEALTH*" or key
    lines[key]:SetText(
      string_format(
        "%-12s %s%4.0f/s|r %s%5.1f ms|r %s%+4.0fK|r w%s%4.2f|r",
        label,
        colorForRate(callsPerSec, key == "Matcher" and 200 or 50, key == "Matcher" and 800 or 200),
        callsPerSec,
        colorForMs(msPerSec, 2, 8),
        msPerSec,
        colorForRate(allocPerSec, 50, 200),
        allocPerSec,
        colorForMs(b.worstMs, 1, 5),
        b.worstMs
      )
    )
    -- Stash per-path numbers into the snapshot for logging.
    snap.paths[key] = {
      callsPerSec = callsPerSec,
      msPerSec = msPerSec,
      allocPerSec = allocPerSec,
      worstMs = b.worstMs,
    }
    -- Reset bucket for next window.
    b.calls = 0
    b.totalMs = 0
    b.worstMs = 0
    b.allocKB = 0
  end

  lastSnapshot = snap
end

------------------------------------------------------------------------------
-- Auto-logger
------------------------------------------------------------------------------
--
-- Samples the most recent refresh snapshot into a ring buffer every
-- LOG_SAMPLE_INTERVAL seconds while in a BG. On match-end events the
-- buffer is flushed to a per-account SavedVariable. Lets the user examine
-- a whole game's perf timeline without taking dozens of screenshots.

local function pushLogSample()
  if not lastSnapshot then
    return
  end
  if not logEnabled then
    return
  end
  -- Don't log when outside a BG. C_PvP.GetActiveMatchState() returns
  -- Inactive (= "lobby") even in the city, so checking matchState alone
  -- is insufficient. Also gate on IsInInstance() == "pvp"/"arena".
  local s = lastSnapshot.matchState
  if s == "?" or s == nil then
    return
  end
  local _, instType = IsInInstance()
  if instType ~= "pvp" and instType ~= "arena" then
    return
  end
  -- Ring buffer: overwrite oldest entry when full.
  logHead = (logHead % LOG_RING_SIZE) + 1
  logBuffer[logHead] = lastSnapshot
  if logCount < LOG_RING_SIZE then
    logCount = logCount + 1
  end
end

local function clearLogBuffer()
  for i = 1, #logBuffer do
    logBuffer[i] = nil
  end
  logHead = 0
  logCount = 0
end

local function ensureLogSV()
  if not BattleGroundEnemiesPerfHUDLog then
    BattleGroundEnemiesPerfHUDLog = { games = {} }
  end
  if not BattleGroundEnemiesPerfHUDLog.games then
    BattleGroundEnemiesPerfHUDLog.games = {}
  end
  return BattleGroundEnemiesPerfHUDLog
end

-- Flush the in-memory ring buffer to the per-account SavedVariable.
-- Keeps only the last MAX_GAMES_RETAINED games to avoid unbounded SV growth.
local MAX_GAMES_RETAINED = 5
local function flushLogToSV(reason)
  if logCount == 0 then
    return
  end
  local sv = ensureLogSV()
  -- Walk the ring buffer in chronological order (oldest first).
  local samples = {}
  local start = (logCount == LOG_RING_SIZE) and ((logHead % LOG_RING_SIZE) + 1) or 1
  local idx = start
  for _ = 1, logCount do
    samples[#samples + 1] = logBuffer[idx]
    idx = (idx % LOG_RING_SIZE) + 1
  end
  local entry = {
    finishedAt = time(),
    reason = reason,
    samples = samples,
    sampleCount = #samples,
  }
  table.insert(sv.games, 1, entry)
  while #sv.games > MAX_GAMES_RETAINED do
    table.remove(sv.games, #sv.games)
  end
  print(
    string_format(
      "|cffffd100[BGE PerfHUD]|r logged %d samples to SV (reason: %s). %d games retained.",
      #samples,
      reason or "?",
      #sv.games
    )
  )
  -- Clear the in-memory buffer after a successful flush so:
  --   1. Subsequent flush events for the SAME game (e.g. PVP_MATCH_COMPLETE
  --      fires first, then PLAYER_ENTERING_WORLD-out) no-op via the empty
  --      check at the top of this function — no SV duplicates.
  --   2. The next match's lobby samples start fresh, not contaminated by
  --      the previous game's tail.
  clearLogBuffer()
end

local function onUpdate(self, elapsed)
  -- Track inter-frame time for "worst frame" display, regardless of refresh tick.
  if elapsed and elapsed > frameWorst then
    frameWorst = elapsed
  end
  -- Wipe the per-frame "seen UNIT_HEALTH alias" set. OnUpdate fires once per
  -- render frame, so wiping here defines the dedup window as one frame.
  for k in pairs(seenButtons) do
    seenButtons[k] = nil
  end
  refreshAccum = refreshAccum + (elapsed or 0)
  if refreshAccum >= REFRESH_INTERVAL then
    refreshAccum = 0
    refresh()
  end
  -- Auto-logger sampling. Separate accumulator from refreshAccum so the
  -- log interval can differ from the display interval.
  logAccum = logAccum + (elapsed or 0)
  if logAccum >= LOG_SAMPLE_INTERVAL then
    logAccum = 0
    pushLogSample()
  end
end

local function ensureSV()
  if not BattleGroundEnemiesPerfHUD then
    BattleGroundEnemiesPerfHUD = {}
  end
  local sv = BattleGroundEnemiesPerfHUD
  if sv.enabled == nil then
    sv.enabled = false
  end
  sv.point = sv.point or "CENTER"
  sv.x = sv.x or 0
  sv.y = sv.y or 0
  return sv
end

local function buildHUD()
  if hud then
    return hud
  end
  local sv = ensureSV()

  hud = CreateFrame("Frame", "BattleGroundEnemiesPerfHUDFrame", UIParent, "BackdropTemplate")
  hud:SetSize(380, 460)
  hud:SetFrameStrata("HIGH")
  hud:ClearAllPoints()
  hud:SetPoint(sv.point, UIParent, sv.point, sv.x, sv.y)
  hud:SetMovable(true)
  hud:EnableMouse(true)
  hud:RegisterForDrag("LeftButton")
  hud:SetScript("OnDragStart", hud.StartMoving)
  hud:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint(1)
    sv.point = point
    sv.x = x
    sv.y = y
  end)
  if hud.SetBackdrop then
    hud:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    hud:SetBackdropColor(0, 0, 0, 0.78)
    hud:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  end

  local title = hud:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetFont("Fonts\\ARIALN.TTF", 16, "OUTLINE")
  title:SetPoint("TOPLEFT", 10, -8)
  title:SetText("|cffffd100BGE PerfHUD|r  (drag to move, /bgehud to toggle)")

  local close = CreateFrame("Button", nil, hud, "UIPanelCloseButton")
  close:SetSize(20, 20)
  close:SetPoint("TOPRIGHT", 0, 0)
  close:SetScript("OnClick", function()
    M:SetEnabled(false)
  end)

  -- Stack the lines.
  local prev = title
  for _, entry in ipairs(LABELS) do
    local fs = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetFont("Fonts\\ARIALN.TTF", 15, "OUTLINE")
    fs:SetJustifyH("LEFT")
    fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -4)
    fs:SetPoint("RIGHT", hud, "RIGHT", -10, 0)
    fs:SetText(entry.label .. ": —")
    lines[entry.key] = fs
    prev = fs
  end

  hud:SetScript("OnUpdate", onUpdate)
  hud:Hide()
  return hud
end

------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------

function M:SetEnabled(on)
  local sv = ensureSV()
  sv.enabled = on and true or false
  M.enabled = sv.enabled

  if sv.enabled then
    installHooks()
    buildHUD()
    hud:Show()
    -- Reset baselines so the first tick isn't garbage.
    lastMemKB = collectgarbage("count")
    frameWorst = 0
    worstWindow.value = 0
    worstWindow.expires = GetTime() + 5
    print("|cffffd100[BGE PerfHUD]|r enabled. Drag to move. /bgehud to toggle.")
  else
    if hud then
      hud:Hide()
    end
    print("|cffffd100[BGE PerfHUD]|r disabled.")
  end
end

function M:Toggle()
  local sv = ensureSV()
  M:SetEnabled(not sv.enabled)
end

------------------------------------------------------------------------------
-- Slash command + auto-spawn
------------------------------------------------------------------------------

SLASH_BGEPERFHUD1 = "/bgehud"
SlashCmdList["BGEPERFHUD"] = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "" then
    M:Toggle()
    return
  end
  -- Subcommands for the auto-logger.
  if msg == "log on" then
    logEnabled = true
    print("|cffffd100[BGE PerfHUD]|r log: on")
    return
  end
  if msg == "log off" then
    logEnabled = false
    print("|cffffd100[BGE PerfHUD]|r log: off")
    return
  end
  if msg == "log clear" then
    clearLogBuffer()
    if BattleGroundEnemiesPerfHUDLog then
      BattleGroundEnemiesPerfHUDLog.games = {}
    end
    print("|cffffd100[BGE PerfHUD]|r log: in-memory + SV cleared")
    return
  end
  if msg == "log flush" then
    flushLogToSV("manual")
    return
  end
  if msg == "log dump" then
    local n = math.min(10, logCount)
    if n == 0 then
      print("|cffffd100[BGE PerfHUD]|r log buffer empty")
      return
    end
    print(string_format("|cffffd100[BGE PerfHUD]|r last %d samples:", n))
    -- Print newest N samples.
    for i = 0, n - 1 do
      local idx = ((logHead - 1 - i) % LOG_RING_SIZE) + 1
      local s = logBuffer[idx]
      if s then
        print(
          string_format(
            "  %s %s bg %s fps=%d frame=%.0fms np=%d mem=%+.0fK/s match=%s",
            formatElapsed(s.bgElapsedMs),
            s.deathState,
            s.matchState,
            s.fps or 0,
            s.frameWorstMs or 0,
            s.nameplates or 0,
            s.luaMemDeltaPerSec or 0,
            s.matchState
          )
        )
      end
    end
    return
  end
  if msg == "log status" then
    local svGames = (BattleGroundEnemiesPerfHUDLog and BattleGroundEnemiesPerfHUDLog.games) or {}
    print(
      string_format(
        "|cffffd100[BGE PerfHUD]|r log: %s, in-memory %d/%d samples, SV %d games retained",
        logEnabled and "on" or "off",
        logCount,
        LOG_RING_SIZE,
        #svGames
      )
    )
    return
  end
  print("|cffffd100[BGE PerfHUD]|r unknown subcommand. Try: log on/off/clear/flush/dump/status")
end

-- Event loader. Restores HUD state on login + wires BG lifecycle events.
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PVP_MATCH_STATE_CHANGED")
loader:RegisterEvent("PVP_MATCH_COMPLETE")
loader:RegisterEvent("PVP_MATCH_INACTIVE")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("PLAYER_LOGOUT") -- fires on /reload too — final safety flush
loader:SetScript("OnEvent", function(self, event, ...)
  if event == "PLAYER_LOGIN" then
    local sv = ensureSV()
    ensureLogSV()
    if sv.enabled then
      -- Defer one frame so all per-button hooks run on subsequent button
      -- creation; existing buttons get wrapped via hooksecurefunc on the
      -- next CreatePlayerButton call, so first BG entry is when wrapping
      -- fully takes effect.
      M:SetEnabled(true)
    else
      -- Even when disabled, install the hook plumbing so /bgehud works
      -- without /reload.
      installHooks()
    end
    return
  end
  if event == "PVP_MATCH_STATE_CHANGED" then
    -- Capture the BG start moment for the fallback timer (used when
    -- GetBattlefieldInstanceRunTime returns 0). DO NOT flush here — we
    -- want the full lifecycle (lobby + active + post-match in-zone)
    -- in a single SV entry. The flush happens once on zone-leave below.
    if C_PvP and C_PvP.GetActiveMatchState and Enum and Enum.PvPMatchState then
      local s = C_PvP.GetActiveMatchState()
      if s == Enum.PvPMatchState.Engaged then
        _bgStartFallback = GetTime()
      end
    end
    return
  end
  if event == "PVP_MATCH_COMPLETE" then
    -- No-op. Wait for zone-leave to flush the whole lifecycle.
    return
  end
  if event == "PVP_MATCH_INACTIVE" then
    -- New match cycle begins. Reset fallback timer; clear log buffer was
    -- already done on Engaged transition above (this is belt-and-braces).
    _bgStartFallback = nil
    return
  end
  if event == "PLAYER_ENTERING_WORLD" then
    -- Leaving an instance back to the world is the primary flush trigger.
    -- Captures the full game lifecycle (lobby + active + complete +
    -- post-match in-zone) in one SV entry.
    local _, instType = IsInInstance()
    if instType ~= "pvp" and instType ~= "arena" and logCount > 0 then
      flushLogToSV("PLAYER_ENTERING_WORLD-out")
    end
    return
  end
  if event == "PLAYER_LOGOUT" and logCount > 0 then
    -- /reload or full exit while still in-zone. Capture whatever we have so
    -- it isn't lost when the addon unloads.
    flushLogToSV("PLAYER_LOGOUT")
    return
  end
end)
