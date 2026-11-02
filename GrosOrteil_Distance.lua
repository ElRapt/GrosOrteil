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
  instance = "Mesure indisponible dans cette instance PvE/PvP ou non reconnue.",
  housing_context = "Identification du quartier ou de la maison en attente. Réessayez dans quelques instants.",
  restricted = "Cette position est masquée par WoW.",
  unavailable = "Position indisponible dans cette zone.",
  target = "Position de la cible inaccessible : essayez un membre du groupe.",
  no_target = "Sélectionnez une cible pour mesurer sa distance.",
  no_origin = "Placez-vous au point de départ puis cliquez sur Mémoriser ici.",
  no_waypoint = "Placez un repère avec Ctrl + clic gauche sur la carte du monde.",
  different_map = "Le point et le personnage sont dans des espaces différents.",
}

local origin, lastHouseRequest
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
  local kind
  ok, value, kind = call(IsInInstance)
  if ok and (isSecret(value) or isSecret(kind)) then return "restricted" end
  if not ok and type(IsInInstance) == "function" then return "restricted" end
  -- Housing is instanced too, but is not dungeon/raid/PvP content. Probe only
  -- ordinary public APIs there; nil/error/secret results still remain unusable.
  local instanced = ok and value
  if instanced and (kind == "party" or kind == "raid" or kind == "pvp"
      or kind == "arena" or kind == "scenario") then return "instance" end
  -- Use housing's public predicates rather than treating every instance as a
  -- combat map. Check indoors first: house interiors need their own identity.
  ok, value = call(C_Housing and C_Housing.IsInsideHouse)
  if not ok and C_Housing and type(C_Housing.IsInsideHouse) == "function" then return "housing_context" end
  if ok and isSecret(value) then return "restricted" end
  if ok and value == true then return nil, "interior" end
  ok, value = call(C_Housing and C_Housing.IsOnNeighborhoodMap)
  if ok and isSecret(value) then return "restricted" end
  if ok and value == true then return nil, "neighborhood" end
  if instanced then return "instance" end
end

function Distance.IsValidScope(scope)
  return not isSecret(scope) and type(scope) == "string" and #scope <= 100
    and scope:match("^[NH]%-[%w%-]+$") ~= nil
end

local function housingScope(kind)
  if not kind then return nil end
  local ok, id
  if kind == "neighborhood" then
    ok, id = call(C_Housing and C_Housing.GetCurrentNeighborhoodGUID)
  else
    local info
    ok, info = call(C_Housing and C_Housing.GetCurrentHouseInfo)
    if ok and isSecret(info) then return nil, "restricted" end
    if ok and type(info) == "table" then id = info.houseGUID end
    if ok and info == nil and C_Housing and type(C_Housing.RequestCurrentHouseInfo) == "function" then
      -- House info is asynchronous and may not have been requested by the
      -- default UI (e.g. a visitor). Poll normally, but bound server requests.
      local now = GetTime()
      if not lastHouseRequest or now - lastHouseRequest >= 10 then
        lastHouseRequest = now
        call(C_Housing.RequestCurrentHouseInfo)
      end
    end
  end
  if isSecret(id) then return nil, "restricted" end
  if not ok or type(id) ~= "string" or #id == 0 or #id > 98 or id:find("[^%w%-]") then
    return nil, "housing_context"
  end
  return (kind == "neighborhood" and "N-" or "H-") .. id
end

-- Map IDs identify layouts, not individual copies of a neighborhood/house.
-- UnitPosition and C_Map also use different coordinate systems.
function Distance.SameSpace(a, b)
  return a and b and a.map == b.map and a.scope == b.scope and a.basis == b.basis
end

function Distance.IsValidPosition(p)
  if isSecret(p) or type(p) ~= "table" then return false end
  if not finite(p.map) or p.map < 0 or p.map > 1e6 or p.map ~= math.floor(p.map)
      or not finite(p.x) or not finite(p.y) or math.abs(p.x) > 1e6 or math.abs(p.y) > 1e6
      or isSecret(p.scope) or isSecret(p.basis) then return false end
  if p.scope ~= nil and not Distance.IsValidScope(p.scope) then return false end
  return p.basis == nil or (p.basis == "M" and p.scope ~= nil)
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

local function between(a, b, source)
  if not Distance.SameSpace(a, b) then return unavailable("different_map") end
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

local function playerMapPosition()
  local ok, map = call(C_Map and C_Map.GetBestMapForUnit, "player")
  if ok and isSecret(map) then return nil, "restricted" end
  if not ok or not finite(map) or map <= 0 then return nil, "unavailable" end
  local position
  ok, position = call(C_Map and C_Map.GetPlayerMapPosition, map, "player")
  if not ok then return nil, "unavailable" end
  return mapPosition(map, position)
end

-- Shared position for origin/proximity features. Never fall back after a secret
-- result. A housing-only map fallback uses public normalized/world map APIs.
function Distance.GetPlayerPosition()
  local reason, kind = blockedReason()
  if reason then return nil, reason end
  local scope
  scope, reason = housingScope(kind)
  if reason then return nil, reason end
  local position
  position, reason = unitPosition("player")
  if not position and kind and reason ~= "restricted" then
    position, reason = playerMapPosition()
    if position then position.basis = "M" end
  end
  if position then position.scope = scope end
  return position, reason
end

local function measureWaypoint()
  local ok, waypoint = call(C_Map and C_Map.GetUserWaypoint)
  if not ok then return unavailable("no_waypoint") end
  if isSecret(waypoint) then return unavailable("restricted") end
  if type(waypoint) ~= "table" then return unavailable("no_waypoint") end
  if isSecret(waypoint.uiMapID) or isSecret(waypoint.position) then return unavailable("restricted") end
  local point, reason = mapPosition(waypoint.uiMapID, waypoint.position)
  if not point then return unavailable(reason) end

  local player
  player, reason = playerMapPosition()
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
    player, reason = Distance.GetPlayerPosition()
    if not player then return unavailable(reason) end
    return between(player, origin, "origin")
  end
  return measureTarget()
end

function Distance.RememberPlayerPosition()
  local position, reason = Distance.GetPlayerPosition()
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

-- A saved point cannot survive a loading-screen phase/instance transition.
local worldEvents = CreateFrame("Frame")
worldEvents:RegisterEvent("PLAYER_LEAVING_WORLD")
worldEvents:SetScript("OnEvent", function()
  lastHouseRequest = nil
  Distance.ClearOrigin()
end)

