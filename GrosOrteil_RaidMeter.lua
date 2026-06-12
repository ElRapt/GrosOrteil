---@diagnostic disable: undefined-global
local _, ns = ...

-- Group damage/heal meter: pure aggregation over the raid panel's cached
-- member states. Core produces the running counters (state.meter, rolled back
-- by undo/redo) and the comm layer ships them in the state payload; this
-- module only reads, filters and sorts. No frames — fully testable offline.
--
-- "Reset" is local-only: baselines remember each member's counters at reset
-- time and the displayed value is the delta since then. Each viewer can zero
-- their own meter without touching anyone's state.

local RaidMeter = {}
ns.RaidMeter = RaidMeter

local type     = type
local tonumber = tonumber
local ipairs   = ipairs
local table    = table

-- Mode → counter field. Damage = effective damage taken (character + pet);
-- heal = healing GIVEN to others via the heal-others handshake (credited on
-- acceptance with the amount actually applied). Peers running an older
-- version send no counters and simply don't appear (value 0 is filtered).
local MODE_FIELDS = { damage = "dmg", heal = "heal" }
RaidMeter.MODES = MODE_FIELDS

local normalizeKey = ns.Shared.NormalizeNameKey
RaidMeter.NormalizeKey = normalizeKey

-- Tolerant read of a state's counters; always returns two numbers.
function RaidMeter.GetTotals(state)
  local m = type(state) == "table" and type(state.meter) == "table" and state.meter
  if not m then return 0, 0 end
  return tonumber(m.dmg) or 0, tonumber(m.heal) or 0
end

-- members:   { {name=...}, ... } (duplicate names collapse on normalized key)
-- getState:  function(name) -> state|nil  (the panel's cache lookup)
-- baselines: { [key] = {dmg=n, heal=n} } from RaidMeter.Reset; may be nil
-- mode:      "damage" | "heal"
-- Returns { rows, total, maxValue }. Each row is { name, key, classKey,
-- value, share } with rows sorted by value desc (key asc on ties) and
-- zero/negative values excluded — members with nothing to show don't appear.
function RaidMeter.BuildRows(members, getState, baselines, mode)
  local field = MODE_FIELDS[mode] or "dmg"
  baselines = baselines or {}
  local rows, total, maxValue, seen = {}, 0, 0, {}
  for _, m in ipairs(members or {}) do
    local key = normalizeKey(m.name)
    if key and not seen[key] then
      seen[key] = true
      local state = getState and getState(m.name) or nil
      if state then
        local dmg, heal = RaidMeter.GetTotals(state)
        local raw  = (field == "heal") and heal or dmg
        local base = baselines[key]
        local value = raw - (base and (tonumber(base[field]) or 0) or 0)
        if value > 0 then
          rows[#rows + 1] = {
            name     = m.name,
            key      = key,
            classKey = type(state.classKey) == "string" and state.classKey or "",
            value    = value,
          }
          total = total + value
          if value > maxValue then maxValue = value end
        end
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.value ~= b.value then return a.value > b.value end
    return (a.key or "") < (b.key or "")
  end)
  for _, r in ipairs(rows) do
    r.share = (total > 0) and (r.value / total) or 0
  end
  return { rows = rows, total = total, maxValue = maxValue }
end

-- Local reset: snapshot every reachable member's counters as the new zero.
-- Mutates and returns `baselines` (creates it when nil). Members whose state
-- is unknown keep their old baseline and zero out when their state arrives
-- with smaller counters than recorded — BuildRows clamps below zero anyway.
function RaidMeter.Reset(members, getState, baselines)
  baselines = baselines or {}
  for _, m in ipairs(members or {}) do
    local key = normalizeKey(m.name)
    if key then
      local state = getState and getState(m.name) or nil
      if state then
        local dmg, heal = RaidMeter.GetTotals(state)
        baselines[key] = { dmg = dmg, heal = heal }
      end
    end
  end
  return baselines
end
