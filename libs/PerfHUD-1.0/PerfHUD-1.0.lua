--- PerfHUD-1.0
-- A reusable, embeddable performance HUD for World of Warcraft addons.
--
-- A floating, draggable diagnostic window that profiles whatever you point it
-- at (methods, functions, manual timings) and renders live per-hotspot rates
-- plus universal frame/memory/CPU rows. Optionally logs a whole session's
-- timeline into a SavedVariable for after-the-fact inspection.
--
-- Nothing in here is addon-specific: you create an instance per addon, declare
-- the SavedVariable name(s) in your own .toc, register what to profile and what
-- rows to show, then enable it. The consumer owns the slash word, the title,
-- the rows, and the lifecycle.
--
-- ============================================================================
-- QUICK START
-- ============================================================================
--
--   local PerfHUD = LibStub("PerfHUD-1.0")
--
--   -- declare in your .toc:  ## SavedVariablesPerCharacter: MyAddonPerfHUD
--   local hud = PerfHUD:New("MyAddon", {
--     savedVar = "MyAddonPerfHUD",   -- per-char HUD state (enabled + position)
--     slash    = "myhud",            -- /myhud toggles
--     title    = "MyAddon PerfHUD",
--     addonName = "MyAddon",         -- name passed to GetAddOnCPUUsage (CPU row)
--   })
--
--   -- profile a method on a table/object (wrapped in place):
--   hud:Profile(MyAddon, "HeavyUpdate", "Update")
--
--   -- or wrap a bare function and assign the result yourself:
--   parse = hud:Wrap(parse, "Parse")
--
--   -- universal rows (any subset, any order):
--   hud:AddBuiltin("fps")
--   hud:AddBuiltin("frameWorst")
--   hud:AddBuiltin("luaMem")
--   hud:AddBuiltin("addonCpu")
--
--   -- a custom row (return a preformatted, colour-coded string):
--   hud:AddMetric("rows", "Visible rows", function(h)
--     return "Visible rows: " .. #MyAddon.rows
--   end)
--
--   -- show the rows for the profiled hotspots (call order = display order):
--   hud:AddPathRow("Update")
--   hud:AddPathRow("Parse")
--
--   hud:SetEnabled(true)   -- or hud:Toggle()
--
-- ============================================================================
-- ROWS, IN ORDER
-- ============================================================================
--
-- The HUD renders rows top-to-bottom in the order you register them. There are
-- three kinds, all freely interleavable:
--
--   AddBuiltin(key[, label])      universal rows the lib computes for you:
--                                 "fps", "frameWorst", "luaMem", "memRate",
--                                 "addonCpu".
--   AddPathRow(label[, opts])     a row for something you Profile()/Wrap()/
--                                 Record() under `label`. opts: displayLabel,
--                                 and warn/bad thresholds (warnRate/badRate,
--                                 warnMs/badMs, warnAlloc/badAlloc,
--                                 warnWorst/badWorst).
--   AddMetric(key, label, def)    a custom row. `def` is either a render
--                                 function (function(hud) -> string) for a
--                                 display-only row, or a table
--                                 { update = function(hud) -> value,
--                                   render = function(value, hud) -> string }
--                                 when you also want the value logged.
--
-- Register all rows BEFORE the first SetEnabled(true) (rows are baked into the
-- frame when it is first built).
--
-- ============================================================================
-- PROFILING PRIMITIVES
-- ============================================================================
--
--   Record(label, ms[, allocKB])   raw accumulator. Use when you time something
--                                   yourself and want full control of the
--                                   wrapper (e.g. extra per-call bookkeeping).
--   Wrap(fn, label) -> wrappedFn    returns a timing wrapper around `fn`. When
--                                   the HUD is disabled the wrapper is a single
--                                   boolean check + tail call (negligible cost).
--   Profile(obj, methodName, label) wraps obj[methodName] in place via Wrap.
--
-- ============================================================================
-- OPTIONAL AUTO-LOGGER
-- ============================================================================
--
-- If you pass `logSavedVar` (declare it in your .toc as a global, NOT
-- per-character) the HUD samples its rows' values into a ring buffer every
-- `logInterval` seconds while enabled and `logGate(hud)` returns true, and you
-- flush them to the SavedVariable at moments you choose:
--
--   opts.logSavedVar = "MyAddonPerfLog"
--   opts.logGate     = function(h) return InCombatLockdown() end  -- when to sample
--   opts.formatLogLine = function(snap) return ... end            -- /slash log dump line
--   hud:FlushLog("reason")   -- append the ring buffer to the SV as one entry
--   hud:ClearLog()           -- wipe in-memory buffer
--
-- The slash command gains subcommands: `log on|off|clear|flush|dump|status`.
--
-- ============================================================================
-- LIFECYCLE HOOKS (opts)
-- ============================================================================
--
--   onEnable(hud)        called each time the HUD is enabled (install your own
--                        hooks here, e.g. wrap newly created frames).
--   onDisable(hud)       called each time the HUD is disabled.
--   onFrame(hud, dt)     called every render frame while shown (e.g. reset a
--                        per-frame dedup set).
--
-- ============================================================================
-- EMBEDDING IN ANOTHER ADDON
-- ============================================================================
--
-- Copy Libs/PerfHUD-1.0/ into your addon and load it after LibStub, e.g. add to
-- your embeds.xml:  <Include file="Libs\PerfHUD-1.0\PerfHUD-1.0.xml"/>
-- (LibStub must load first.) Then declare your SavedVariable(s) in your .toc.

local MAJOR, MINOR = "PerfHUD-1.0", 1

assert(LibStub, MAJOR .. " requires LibStub")
local PerfHUD = LibStub:NewLibrary(MAJOR, MINOR)
if not PerfHUD then
  return -- a newer or equal version is already loaded
end

------------------------------------------------------------------------------
-- Upvalues
------------------------------------------------------------------------------

local debugprofilestop = debugprofilestop
local GetFramerate = GetFramerate
local GetTime = GetTime
local collectgarbage = collectgarbage
local GetAddOnCPUUsage = (C_AddOns and C_AddOns.GetAddOnCPUUsage) or GetAddOnCPUUsage
local UpdateAddOnCPUUsage = (C_AddOns and C_AddOns.UpdateAddOnCPUUsage) or UpdateAddOnCPUUsage
local GetCVarBool = (C_CVar and C_CVar.GetCVarBool) or GetCVarBool
-- CPU profiling (GetAddOnCPUUsage/GetFrameCPUUsage) only returns real data when
-- the scriptProfile CVar was set the PRIOR session + reloaded; otherwise it reads
-- 0. Cheap check so CPU rows can show "off" instead of a misleading 0 ms.
local function cpuProfilingEnabled()
  return (GetCVarBool and GetCVarBool("scriptProfile")) and true or false
end
PerfHUD.CpuProfilingEnabled = cpuProfilingEnabled
local CreateFrame = CreateFrame
local string_format = string.format
local math_max = math.max
local math_min = math.min
local math_floor = math.floor
local tinsert = table.insert
local tremove = table.remove
local ipairs = ipairs
local pairs = pairs
local type = type

------------------------------------------------------------------------------
-- Colour helpers (exposed so consumers can colour their own custom rows the
-- same way the built-in/path rows do).
------------------------------------------------------------------------------

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

-- Format milliseconds as "MM:SS" (or "H:MM:SS" if it's been hours). "—" for <=0.
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

-- Static helpers on the library table.
function PerfHUD.ColorForMs(_, ms, warn, bad)
  return colorForMs(ms, warn, bad)
end
function PerfHUD.ColorForRate(_, rate, warn, bad)
  return colorForRate(rate, warn, bad)
end
function PerfHUD.FormatElapsed(_, ms)
  return formatElapsed(ms)
end

------------------------------------------------------------------------------
-- Built-in row definitions. Each reads the per-refresh frame stats the
-- instance computes (see HUD._refresh) and returns (loggable value) from
-- update + (display string) from render.
------------------------------------------------------------------------------

local BUILTINS = {
  fps = {
    label = "FPS",
    update = function(h)
      return h._frameStats.fps
    end,
    render = function(v)
      local color = (v < 30 and "|cffff5555") or (v < 60 and "|cffffcc44") or "|cff66dd66"
      return string_format("FPS: %s%.0f|r", color, v)
    end,
  },
  frameWorst = {
    label = "Frame worst (5s)",
    update = function(h)
      return h._frameStats.frameWorstMs
    end,
    render = function(v)
      return string_format("Frame worst (5s): %s%.1f ms|r", colorForMs(v, 33, 50), v)
    end,
  },
  luaMem = {
    label = "Lua mem Δ",
    update = function(h)
      return h._frameStats.luaMemDeltaPerSec
    end,
    render = function(v, h)
      return string_format(
        "Lua mem Δ: %s%+.1f KB/s|r  (total %.0f KB)",
        colorForRate(v, 50, 200),
        v,
        h._frameStats.luaMemKB
      )
    end,
  },
  memRate = {
    label = "Mem growth (30s)",
    update = function(h)
      return h._frameStats.memRate -- may be nil until enough samples
    end,
    render = function(v, h)
      if not v then
        return "Mem growth (30s): —"
      end
      return string_format(
        "Mem growth (%ds): %s%+.1f KB/s|r",
        math_floor((h._frameStats.memRateSpan or 0) + 0.5),
        colorForRate(v, 100, 500),
        v
      )
    end,
  },
  addonCpu = {
    label = "Addon CPU",
    update = function(h)
      return h._frameStats.cpuMs -- nil when profiling APIs unavailable
    end,
    render = function(v)
      if not v then
        return "Addon CPU: n/a"
      end
      if not cpuProfilingEnabled() then
        return "Addon CPU: |cff888888off (/console scriptProfile 1 + reload)|r"
      end
      return string_format("Addon CPU: %s%.0f ms|r (since login)", colorForMs(v, 5000, 20000), v)
    end,
  },
}

------------------------------------------------------------------------------
-- Instance prototype
------------------------------------------------------------------------------

local HUD = {}
local HUD_mt = { __index = HUD }

-- Convenience: colour helpers also available on instances.
HUD.ColorForMs = PerfHUD.ColorForMs
HUD.ColorForRate = PerfHUD.ColorForRate
HUD.FormatElapsed = PerfHUD.FormatElapsed

local function newBucket()
  return { calls = 0, totalMs = 0, worstMs = 0, allocKB = 0 }
end

--- Create a new HUD instance.
-- @param name string  identifier (used for frame/slash key defaults).
-- @param opts table   see header docs. Recognised keys: savedVar, logSavedVar,
--   slash, title, tag, addonName, width, height, defaultEnabled, refreshInterval,
--   logInterval, logRingSize, maxGamesRetained, memSampleWindow, logGate,
--   formatLogLine, onEnable, onDisable, onFrame.
function PerfHUD:New(name, opts)
  assert(type(name) == "string", "PerfHUD:New requires a name string")
  opts = opts or {}

  local hud = setmetatable({}, HUD_mt)
  hud.name = name
  hud.savedVar = opts.savedVar
  hud.logSavedVar = opts.logSavedVar
  hud.slash = opts.slash or name:lower():gsub("[^%w]", "") .. "hud"
  hud.title = opts.title or (name .. " PerfHUD")
  hud.tag = opts.tag or ("|cffffd100[" .. (opts.title or name) .. "]|r")
  hud.addonName = opts.addonName or name
  hud.width = opts.width or 380
  hud.height = opts.height or 460
  hud.defaultEnabled = opts.defaultEnabled and true or false

  -- Tunables.
  hud.refreshInterval = opts.refreshInterval or 0.5
  hud.logInterval = opts.logInterval or 2
  hud.logRingSize = opts.logRingSize or 1000
  hud.maxGamesRetained = opts.maxGamesRetained or 5
  hud.memSampleWindow = opts.memSampleWindow or 30

  -- Callbacks.
  hud.logGate = opts.logGate
  hud.formatLogLine = opts.formatLogLine
  hud.onEnable = opts.onEnable
  hud.onDisable = opts.onDisable
  hud.onFrame = opts.onFrame

  -- State.
  hud.enabled = false
  hud._stats = {} -- label -> bucket
  hud._rows = {} -- ordered list of row descriptors
  hud._rowByKey = {}
  hud._lines = {} -- key -> FontString (built on first enable)
  hud._refreshAccum = 0
  hud._frameWorst = 0
  hud._worstWindow = 0
  hud._worstExpires = 0
  hud._lastMemKB = nil
  hud._memSamples = {}
  hud._frameStats = {}
  hud._lastSnapshot = nil

  -- Logger.
  hud.logEnabled = true
  hud._logBuffer = {}
  hud._logHead = 0
  hud._logCount = 0
  hud._logAccum = 0
  hud.logSV = nil

  hud:_registerSlash()
  return hud
end

------------------------------------------------------------------------------
-- SavedVariables
------------------------------------------------------------------------------

function HUD:_ensureSV()
  if self.savedVar then
    local sv = _G[self.savedVar]
    if not sv then
      sv = {}
      _G[self.savedVar] = sv
    end
    self._sv = sv
  else
    self._sv = self._sv or {}
  end
  local sv = self._sv
  if sv.enabled == nil then
    sv.enabled = self.defaultEnabled
  end
  sv.point = sv.point or "CENTER"
  sv.x = sv.x or 0
  sv.y = sv.y or 0
  return sv
end

function HUD:_ensureLogSV()
  if not self.logSavedVar then
    return nil
  end
  local sv = _G[self.logSavedVar]
  if not sv then
    sv = { games = {} }
    _G[self.logSavedVar] = sv
  end
  if not sv.games then
    sv.games = {}
  end
  self.logSV = sv
  return sv
end

------------------------------------------------------------------------------
-- Profiling primitives
------------------------------------------------------------------------------

function HUD:Record(label, ms, allocKB)
  local b = self._stats[label]
  if not b then
    b = newBucket()
    self._stats[label] = b
  end
  b.calls = b.calls + 1
  b.totalMs = b.totalMs + ms
  if ms > b.worstMs then
    b.worstMs = ms
  end
  if allocKB and allocKB > 0 then
    b.allocKB = b.allocKB + allocKB
  end
end

-- Wrap a function in a timing closure. When the HUD is disabled this short-
-- circuits to a single boolean check + tail call.
function HUD:Wrap(fn, label)
  if not self._stats[label] then
    self._stats[label] = newBucket()
  end
  local hud = self
  return function(...)
    if not hud.enabled then
      return fn(...)
    end
    local m0 = collectgarbage("count")
    local t0 = debugprofilestop()
    local a, b, c, d = fn(...)
    hud:Record(label, debugprofilestop() - t0, collectgarbage("count") - m0)
    return a, b, c, d
  end
end

-- Wrap obj[methodName] in place. No-op if the method doesn't exist.
function HUD:Profile(obj, methodName, label)
  local orig = obj and obj[methodName]
  if not orig then
    return self
  end
  obj[methodName] = self:Wrap(orig, label)
  return self
end

------------------------------------------------------------------------------
-- Row registration
------------------------------------------------------------------------------

function HUD:_addRow(row)
  self._rows[#self._rows + 1] = row
  self._rowByKey[row.key] = row
  return self
end

-- Universal row computed by the lib. key ∈ fps|frameWorst|luaMem|memRate|addonCpu
function HUD:AddBuiltin(key, label)
  local b = BUILTINS[key]
  assert(b, "PerfHUD: unknown built-in row '" .. tostring(key) .. "'")
  return self:_addRow({ key = key, label = label or b.label, update = b.update, render = b.render })
end

-- Custom row. `def` is a render function (display-only) or a table with
-- { update = function(hud)->value, render = function(value, hud)->string }.
function HUD:AddMetric(key, label, def)
  local row = { key = key, label = label }
  if type(def) == "function" then
    -- Display-only: value is not captured into the log snapshot.
    row.render = function(_, hud)
      return def(hud)
    end
  else
    assert(type(def) == "table", "PerfHUD:AddMetric def must be a function or table")
    row.update = def.update
    row.render = def.render
  end
  return self:_addRow(row)
end

-- Row for a profiled/recorded label. opts: displayLabel + warn/bad thresholds.
function HUD:AddPathRow(label, opts)
  opts = opts or {}
  if not self._stats[label] then
    self._stats[label] = newBucket()
  end
  local displayLabel = opts.displayLabel or label
  local warnRate, badRate = opts.warnRate or 50, opts.badRate or 200
  local warnMs, badMs = opts.warnMs or 2, opts.badMs or 8
  local warnAlloc, badAlloc = opts.warnAlloc or 50, opts.badAlloc or 200
  local warnWorst, badWorst = opts.warnWorst or 1, opts.badWorst or 5

  local row = {
    key = label,
    label = displayLabel,
    update = function(hud)
      local b = hud._stats[label]
      local interval = hud.refreshInterval
      local v = {
        callsPerSec = b.calls / interval,
        msPerSec = b.totalMs / interval,
        allocPerSec = b.allocKB / interval,
        worstMs = b.worstMs,
      }
      b.calls = 0
      b.totalMs = 0
      b.worstMs = 0
      b.allocKB = 0
      return v
    end,
    render = function(v)
      return string_format(
        "%-12s %s%4.0f/s|r %s%5.1f ms|r %s%+4.0fK|r w%s%4.2f|r",
        displayLabel,
        colorForRate(v.callsPerSec, warnRate, badRate),
        v.callsPerSec,
        colorForMs(v.msPerSec, warnMs, badMs),
        v.msPerSec,
        colorForRate(v.allocPerSec, warnAlloc, badAlloc),
        v.allocPerSec,
        colorForMs(v.worstMs, warnWorst, badWorst),
        v.worstMs
      )
    end,
  }
  return self:_addRow(row)
end

------------------------------------------------------------------------------
-- Refresh + frame stats
------------------------------------------------------------------------------

function HUD:_refresh()
  local now = GetTime()

  -- Worst frame: decay the 5s window.
  if now > self._worstExpires then
    self._worstWindow = self._frameWorst
    self._worstExpires = now + 5
  else
    self._worstWindow = math_max(self._worstWindow, self._frameWorst)
  end
  local frameWorstMs = self._worstWindow * 1000
  self._frameWorst = 0

  local fps = GetFramerate()

  -- Lua memory delta.
  local mem = collectgarbage("count")
  local delta = self._lastMemKB and (mem - self._lastMemKB) or 0
  self._lastMemKB = mem
  local memDeltaPerSec = delta / self.refreshInterval

  -- Smoothed memory growth over the sample window (ring buffer of time/mem).
  self._memSamples[#self._memSamples + 1] = { t = now, mem = mem }
  while #self._memSamples > 0 and (now - self._memSamples[1].t) > self.memSampleWindow do
    tremove(self._memSamples, 1)
  end
  local memRate, memRateSpan
  if #self._memSamples >= 2 then
    local oldest = self._memSamples[1]
    local span = now - oldest.t
    if span > 0 then
      memRate = (mem - oldest.mem) / span
      memRateSpan = span
    end
  end

  -- Addon CPU (only meaningful with /console scriptProfile 1).
  local cpuMs
  if GetAddOnCPUUsage and UpdateAddOnCPUUsage and self.addonName then
    UpdateAddOnCPUUsage()
    cpuMs = GetAddOnCPUUsage(self.addonName) or 0
  end

  self._frameStats = {
    fps = fps,
    frameWorstMs = frameWorstMs,
    luaMemKB = mem,
    luaMemDeltaPerSec = memDeltaPerSec,
    memRate = memRate,
    memRateSpan = memRateSpan,
    cpuMs = cpuMs,
  }

  -- Run each row: update (collect + reset its accumulators) then render.
  -- The value returned by update is captured into the log snapshot.
  local snap = { t = now }
  for _, row in ipairs(self._rows) do
    local value
    if row.update then
      value = row.update(self)
    end
    if row.render then
      local fs = self._lines[row.key]
      if fs then
        fs:SetText(row.render(value, self))
      end
    end
    if value ~= nil then
      snap[row.key] = value
    end
  end

  self._lastSnapshot = snap
end

function HUD:_onUpdate(elapsed)
  if elapsed and elapsed > self._frameWorst then
    self._frameWorst = elapsed
  end
  if self.onFrame then
    self.onFrame(self, elapsed)
  end
  self._refreshAccum = self._refreshAccum + (elapsed or 0)
  if self._refreshAccum >= self.refreshInterval then
    self._refreshAccum = 0
    self:_refresh()
  end
  -- Auto-logger sampling. Separate accumulator so it can differ from refresh.
  self._logAccum = self._logAccum + (elapsed or 0)
  if self._logAccum >= self.logInterval then
    self._logAccum = 0
    self:_pushLogSample()
  end
end

------------------------------------------------------------------------------
-- Auto-logger
------------------------------------------------------------------------------

function HUD:_pushLogSample()
  if not self._lastSnapshot then
    return
  end
  if not self.logEnabled then
    return
  end
  if not self.logSavedVar then
    return
  end
  if self.logGate and not self.logGate(self) then
    return
  end
  if not self.logSV then
    self:_ensureLogSV()
  end
  -- Ring buffer: overwrite oldest entry when full.
  self._logHead = (self._logHead % self.logRingSize) + 1
  self._logBuffer[self._logHead] = self._lastSnapshot
  if self._logCount < self.logRingSize then
    self._logCount = self._logCount + 1
  end
end

function HUD:ClearLog()
  for i = 1, #self._logBuffer do
    self._logBuffer[i] = nil
  end
  self._logHead = 0
  self._logCount = 0
end

function HUD:SetLogEnabled(on)
  self.logEnabled = on and true or false
end

-- Flush the in-memory ring buffer to the SavedVariable as one game entry.
function HUD:FlushLog(reason)
  if self._logCount == 0 then
    return
  end
  if not self.logSavedVar then
    return
  end
  local sv = self:_ensureLogSV()
  -- Walk the ring buffer in chronological order (oldest first).
  local samples = {}
  local start = (self._logCount == self.logRingSize) and ((self._logHead % self.logRingSize) + 1) or 1
  local idx = start
  for _ = 1, self._logCount do
    samples[#samples + 1] = self._logBuffer[idx]
    idx = (idx % self.logRingSize) + 1
  end
  local entry = {
    finishedAt = time(),
    reason = reason,
    samples = samples,
    sampleCount = #samples,
  }
  tinsert(sv.games, 1, entry)
  while #sv.games > self.maxGamesRetained do
    tremove(sv.games, #sv.games)
  end
  print(
    string_format(
      "%s logged %d samples to SV (reason: %s). %d games retained.",
      self.tag,
      #samples,
      reason or "?",
      #sv.games
    )
  )
  -- Clear after a successful flush so repeated flush events for the same
  -- session no-op, and the next session starts fresh.
  self:ClearLog()
end

function HUD:GetLogCount()
  return self._logCount, self.logRingSize
end

------------------------------------------------------------------------------
-- HUD frame
------------------------------------------------------------------------------

function HUD:_buildHUD()
  if self._frame then
    return self._frame
  end
  local sv = self:_ensureSV()
  self:_ensureLogSV()

  local frame = CreateFrame("Frame", self.name .. "PerfHUDFrame", UIParent, "BackdropTemplate")
  self._frame = frame
  frame:SetSize(self.width, self.height)
  frame:SetFrameStrata("HIGH")
  frame:ClearAllPoints()
  frame:SetPoint(sv.point, UIParent, sv.point, sv.x, sv.y)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(f)
    f:StopMovingOrSizing()
    local point, _, _, x, y = f:GetPoint(1)
    sv.point = point
    sv.x = x
    sv.y = y
  end)
  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.78)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  end

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetFont("Fonts\\ARIALN.TTF", 16, "OUTLINE")
  title:SetPoint("TOPLEFT", 10, -8)
  title:SetText("|cffffd100" .. self.title .. "|r  (drag to move, /" .. self.slash .. " to toggle)")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetSize(20, 20)
  close:SetPoint("TOPRIGHT", 0, 0)
  close:SetScript("OnClick", function()
    self:SetEnabled(false)
  end)

  -- Stack the rows.
  local prev = title
  for _, row in ipairs(self._rows) do
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetFont("Fonts\\ARIALN.TTF", 15, "OUTLINE")
    fs:SetJustifyH("LEFT")
    fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -4)
    fs:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
    fs:SetText((row.label or row.key) .. ": —")
    self._lines[row.key] = fs
    prev = fs
  end

  frame:SetScript("OnUpdate", function(_, elapsed)
    self:_onUpdate(elapsed)
  end)
  frame:Hide()
  return frame
end

------------------------------------------------------------------------------
-- Enable / disable
------------------------------------------------------------------------------

function HUD:SetEnabled(on)
  local sv = self:_ensureSV()
  sv.enabled = on and true or false
  self.enabled = sv.enabled

  if self.enabled then
    if self.onEnable then
      self.onEnable(self)
    end
    self:_buildHUD()
    self._frame:Show()
    -- Reset baselines so the first tick isn't garbage.
    self._lastMemKB = collectgarbage("count")
    self._frameWorst = 0
    self._worstWindow = 0
    self._worstExpires = GetTime() + 5
    print(self.tag .. " enabled. Drag to move. /" .. self.slash .. " to toggle.")
  else
    if self._frame then
      self._frame:Hide()
    end
    if self.onDisable then
      self.onDisable(self)
    end
    print(self.tag .. " disabled.")
  end
end

function HUD:Toggle()
  local sv = self:_ensureSV()
  self:SetEnabled(not sv.enabled)
end

function HUD:IsEnabled()
  return self.enabled
end

-- Apply the saved enabled state (call from PLAYER_LOGIN if you want to restore
-- the last session's on/off rather than forcing a state).
function HUD:RestoreState()
  local sv = self:_ensureSV()
  self:SetEnabled(sv.enabled)
end

------------------------------------------------------------------------------
-- Slash command
------------------------------------------------------------------------------

function HUD:_registerSlash()
  local key = ("PERFHUD_" .. self.slash):upper():gsub("[^%w]", "")
  _G["SLASH_" .. key .. "1"] = "/" .. self.slash
  SlashCmdList[key] = function(msg)
    self:_handleSlash(msg)
  end
end

function HUD:_handleSlash(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "" then
    self:Toggle()
    return
  end
  if not self.logSavedVar then
    print(self.tag .. " unknown subcommand (logging not enabled for this HUD).")
    return
  end
  if msg == "log on" then
    self.logEnabled = true
    print(self.tag .. " log: on")
    return
  end
  if msg == "log off" then
    self.logEnabled = false
    print(self.tag .. " log: off")
    return
  end
  if msg == "log clear" then
    self:ClearLog()
    if self.logSV then
      self.logSV.games = {}
    end
    print(self.tag .. " log: in-memory + SV cleared")
    return
  end
  if msg == "log flush" then
    self:FlushLog("manual")
    return
  end
  if msg == "log dump" then
    local n = math_min(10, self._logCount)
    if n == 0 then
      print(self.tag .. " log buffer empty")
      return
    end
    print(string_format("%s last %d samples:", self.tag, n))
    for i = 0, n - 1 do
      local idx = ((self._logHead - 1 - i) % self.logRingSize) + 1
      local s = self._logBuffer[idx]
      if s then
        if self.formatLogLine then
          print("  " .. self.formatLogLine(s))
        else
          -- Generic fallback: list numeric top-level snapshot fields.
          local parts = {}
          for k, v in pairs(s) do
            if type(v) == "number" and k ~= "t" then
              parts[#parts + 1] = string_format("%s=%.1f", k, v)
            end
          end
          print("  " .. table.concat(parts, " "))
        end
      end
    end
    return
  end
  if msg == "log status" then
    local svGames = (self.logSV and self.logSV.games) or {}
    print(
      string_format(
        "%s log: %s, in-memory %d/%d samples, SV %d games retained",
        self.tag,
        self.logEnabled and "on" or "off",
        self._logCount,
        self.logRingSize,
        #svGames
      )
    )
    return
  end
  print(self.tag .. " unknown subcommand. Try: log on/off/clear/flush/dump/status")
end

return PerfHUD
