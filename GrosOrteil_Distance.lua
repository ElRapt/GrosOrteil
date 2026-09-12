---@diagnostic disable: undefined-global
-- Read-only range aid. Distances use WoW's display convention (API yards are
-- shown as "m" by the French client), without a physical yard/metre conversion.
-- Blizzard's documented APIs expose unit positions and map waypoints, not a
-- world-space point under an arbitrary click on the 3D terrain.
local _, ns = ...
local Distance = { mode = "target" }
ns.Distance = Distance

Distance.Categories = {
  { key = "contact", label = "Contact", range = "Moins de 1 m" },
  { key = "restricted", label = "Distance restreinte", range = "1 à moins de 5 m" },
  { key = "short", label = "Courte distance", range = "5 à moins de 25 m" },
  { key = "medium", label = "Moyenne distance", range = "25 à 40 m" },
  { key = "long", label = "Longue distance", range = "Plus de 40 m" },
}

local MESSAGES = {
  combat = "Mesure suspendue pendant le combat.",
  instance = "Mesure indisponible dans les instances.",
  restricted = "Cette position est masquée par WoW.",
  unavailable = "Position indisponible dans cette zone.",
  target = "Cible non mesurable : essayez un membre du groupe, hors instance.",
  no_target = "Sélectionnez une cible pour mesurer sa distance.",
  no_origin = "Placez-vous au point de départ puis cliquez sur Mémoriser ici.",
  no_waypoint = "Placez un repère avec Ctrl + clic gauche sur la carte du monde.",
  different_map = "Le point et le personnage sont dans des espaces différents.",
}

local origin
local function isSecret(value)
  return type(issecretvalue) == "function" and issecretvalue(value) or false
end

local function finite(value)
  return not isSecret(value) and type(value) == "number"
    and value == value and value > -math.huge and value < math.huge
end

local function call(fn, ...)
  if type(fn) ~= "function" then return false end
  return pcall(fn, ...)
end

local function unavailable(reason)
  return { reason = reason, message = MESSAGES[reason] or MESSAGES.unavailable }
end

local function blockedReason()
  local ok, value = call(InCombatLockdown)
  if ok and (isSecret(value) or value) then return "combat" end
  ok, value = call(IsInInstance)
  if ok and (isSecret(value) or value) then return "instance" end
end

function Distance.Classify(value)
  if not finite(value) or value < 0 then return nil end
  local index = value < 1 and 1 or value < 5 and 2 or value < 25 and 3 or value <= 40 and 4 or 5
  local category = Distance.Categories[index]
  return category.key, category.label, category.range
end

local function measured(value, source)
  local key, label, range = Distance.Classify(value)
  if not key then return unavailable("unavailable") end
  return { distance = value, category = key, label = label, range = range, source = source }
end

local function unitPosition(unit)
  local ok, x, y, z, map = call(UnitPosition, unit)
  if not ok then return nil, "unavailable" end
  if isSecret(x) or isSecret(y) or isSecret(z) or isSecret(map) then return nil, "restricted" end
  if not finite(x) or not finite(y) or not finite(map) or map < 0 then return nil, "unavailable" end
  return { x = x, y = y, map = map }
end

-- Shared safe world position for proximity features; no position in restricted contexts.
function Distance.GetPlayerPosition()
  if blockedReason() then return nil end
  return unitPosition("player")
end

local function between(a, b, source)
  if a.map ~= b.map then return unavailable("different_map") end
  local dx, dy = a.x - b.x, a.y - b.y
  -- UnitPosition's Z is not reliable. Both positions and map waypoints are
  -- explicitly horizontal estimates, with no line-of-sight/range guarantee.
  return measured(math.sqrt(dx * dx + dy * dy), source)
end

local function measureTarget()
  local ok, exists = call(UnitExists, "target")
  if ok and isSecret(exists) then return unavailable("restricted") end
  if ok and not exists then return unavailable("no_target") end

  local squared, checked
  ok, squared, checked = call(UnitDistanceSquared, "target")
  if ok and (isSecret(squared) or isSecret(checked)) then return unavailable("restricted") end
  -- An unchecked zero does not mean that the target is in contact range.
  if ok and checked == true and finite(squared) and squared >= 0 then
    return measured(math.sqrt(squared), "target")
  end
  local player, reason = unitPosition("player")
  if not player then return unavailable(reason) end
  local target
  target, reason = unitPosition("target")
  if not target then return unavailable(reason == "restricted" and reason or "target") end
  return between(player, target, "target")
end

local function vectorXY(vector)
  if isSecret(vector) then return nil, nil, "restricted" end
  if type(vector) ~= "table" and type(vector) ~= "userdata" then return nil, nil, "unavailable" end
  local ok, x, y = pcall(function() return vector.x, vector.y end)
  if not ok then return nil, nil, "unavailable" end
  if isSecret(x) or isSecret(y) then return nil, nil, "restricted" end
  if not finite(x) or not finite(y) then return nil, nil, "unavailable" end
  return x, y
end

local function mapPosition(map, pos)
  local x, y, reason = vectorXY(pos)
  if not x then return nil, reason end
  if not finite(map) or map <= 0 or x < 0 or x > 1 or y < 0 or y > 1 then
    return nil, "unavailable"
  end
  local ok, continent, world = call(C_Map and C_Map.GetWorldPosFromMapPos, map, pos)
  if not ok then return nil, "unavailable" end
  if isSecret(continent) then return nil, "restricted" end
  if not finite(continent) or continent < 0 then return nil, "unavailable" end
  x, y, reason = vectorXY(world)
  if not x then return nil, reason end
  return { x = x, y = y, map = continent }
end

local function measureWaypoint()
  local ok, waypoint = call(C_Map and C_Map.GetUserWaypoint)
  if not ok then return unavailable("no_waypoint") end
  if isSecret(waypoint) then return unavailable("restricted") end
  if type(waypoint) ~= "table" then return unavailable("no_waypoint") end
  if isSecret(waypoint.uiMapID) or isSecret(waypoint.position) then return unavailable("restricted") end
  local point, reason = mapPosition(waypoint.uiMapID, waypoint.position)
  if not point then return unavailable(reason) end

  local playerMap, playerPos
  ok, playerMap = call(C_Map and C_Map.GetBestMapForUnit, "player")
  if ok and isSecret(playerMap) then return unavailable("restricted") end
  if not ok or not finite(playerMap) or playerMap <= 0 then return unavailable("unavailable") end
  ok, playerPos = call(C_Map and C_Map.GetPlayerMapPosition, playerMap, "player")
  if not ok then return unavailable("unavailable") end
  local player
  player, reason = mapPosition(playerMap, playerPos)
  if not player then return unavailable(reason) end
  -- Convert both through C_Map: never mix its axes with UnitPosition's axes.
  return between(player, point, "waypoint")
end

function Distance.Measure(mode)
  local reason = blockedReason()
  if reason then return unavailable(reason) end
  mode = mode or Distance.mode
  if mode == "waypoint" then return measureWaypoint() end
  if mode == "origin" then
    if not origin then return unavailable("no_origin") end
    local player
    player, reason = unitPosition("player")
    if not player then return unavailable(reason) end
    return between(player, origin, "origin")
  end
  return measureTarget()
end

function Distance.RememberPlayerPosition()
  local reason = blockedReason()
  if reason then return false, MESSAGES[reason] end
  local position
  position, reason = unitPosition("player")
  if not position then return false, MESSAGES[reason] end
  origin = position
  Distance.SetMode("origin")
  return true
end

function Distance.ClearOrigin()
  origin = nil
  if Distance.Refresh then Distance.Refresh() end
end

function Distance.SetMode(mode)
  if mode ~= "target" and mode ~= "origin" and mode ~= "waypoint" then return false end
  local changed = Distance.mode ~= mode
  Distance.mode = mode
  if Distance.Refresh then Distance.Refresh(changed) end
  return true
end
