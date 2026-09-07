---@diagnostic disable: undefined-global
local T, Distance = _G.T, _G.NS.Distance

local function withAPI(overrides, fn)
  local previous = {}
  for name, value in pairs(overrides) do previous[name] = _G[name]; _G[name] = value end
  local ok, err = pcall(fn)
  for name in pairs(overrides) do _G[name] = previous[name] end
  if not ok then error(err, 0) end
end

local function outside(extra, fn)
  local api = {
    InCombatLockdown = function() return false end,
    IsInInstance = function() return false end,
    UnitExists = function() return true end,
    UnitPosition = false, UnitDistanceSquared = false, C_Map = false,
    issecretvalue = function() return false end,
  }
  for k, v in pairs(extra) do api[k] = v end
  withAPI(api, fn)
end

T.describe("Distance categories", function()
  T.it("assigns every shared boundary once and retains 40 in medium range", function()
    for _, row in ipairs({
      { 0, "contact" }, { 0.999, "contact" }, { 1, "restricted" },
      { 4.999, "restricted" }, { 5, "short" }, { 24.999, "short" },
      { 25, "medium" }, { 40, "medium" }, { 40.001, "long" },
    }) do T.assertEq(Distance.Classify(row[1]), row[2]) end
  end)
  T.it("rejects invalid and non-finite distances", function()
    T.assertNil(Distance.Classify(nil)); T.assertNil(Distance.Classify("40"))
    T.assertNil(Distance.Classify(-1)); T.assertNil(Distance.Classify(0 / 0))
    T.assertNil(Distance.Classify(math.huge)); T.assertNil(Distance.Classify(-math.huge))
  end)
end)

T.describe("Distance measurements", function()
  T.it("uses checked unit distances with the same numeric convention as spell range", function()
    outside({ UnitDistanceSquared = function(unit)
      T.assertEq(unit, "target"); return 1600, true
    end }, function()
      local result = Distance.Measure("target")
      T.assertEq(result.distance, 40); T.assertEq(result.category, "medium")
    end)
  end)
  T.it("accepts a checked zero but never reports unchecked zero as contact", function()
    outside({ UnitDistanceSquared = function() return 0, true end }, function()
      T.assertEq(Distance.Measure("target").category, "contact")
    end)
    outside({ UnitDistanceSquared = function() return 0, false end }, function()
      T.assertNil(Distance.Measure("target").distance)
    end)
  end)
  T.it("requires an actual target before reading its range", function()
    outside({ UnitExists = function() return false end,
      UnitDistanceSquared = function() error("must not query missing target") end }, function()
      T.assertEq(Distance.Measure("target").reason, "no_target")
    end)
  end)
  T.it("falls back to accessible horizontal unit positions", function()
    outside({ UnitDistanceSquared = function() return 0, false end,
      UnitPosition = function(unit)
        if unit == "player" then return 10, 20, 0, 1 end
        return 13, 24, 100, 1
      end }, function()
      T.assertEq(Distance.Measure("target").distance, 5)
    end)
  end)
  T.it("rejects positions on different world maps", function()
    outside({ UnitPosition = function(unit)
      return 10, 20, 0, unit == "player" and 1 or 2
    end }, function()
      T.assertEq(Distance.Measure("target").reason, "different_map")
    end)
  end)
  T.it("does not query positions in combat or instanced content", function()
    local queried = false
    for _, reason in ipairs({ "combat", "instance" }) do
      outside({ InCombatLockdown = function() return reason == "combat" end,
        IsInInstance = function() return reason == "instance" end,
        UnitDistanceSquared = function() queried = true; return 0, true end,
        UnitPosition = function() queried = true; return 0, 0, 0, 1 end }, function()
        T.assertEq(Distance.Measure("target").reason, reason)
        T.assertFalse(Distance.RememberPlayerPosition())
      end)
    end
    T.assertFalse(queried)
  end)
  T.it("returns unavailable if WoW refuses a coordinate API call", function()
    outside({ UnitDistanceSquared = function() error("restricted API") end,
      UnitPosition = function() error("restricted API") end }, function()
      T.assertNil(Distance.Measure("target").distance)
    end)
  end)
  T.it("never compares, computes or falls back from secret values", function()
    local secret = setmetatable({}, {
      __eq = function() error("secret comparison") end,
      __lt = function() error("secret comparison") end,
      __le = function() error("secret comparison") end,
      __tostring = function() error("secret formatting") end,
    })
    local positionCalls = 0
    outside({ issecretvalue = function(value) return rawequal(value, secret) end,
      UnitDistanceSquared = function() return secret, true end,
      UnitPosition = function() positionCalls = positionCalls + 1; return 0, 0, 0, 1 end }, function()
      T.assertEq(Distance.Measure("target").reason, "restricted")
      T.assertEq(positionCalls, 0); T.assertNil(Distance.Classify(secret))
      _G.UnitDistanceSquared = function() return 0, secret end
      T.assertEq(Distance.Measure("target").reason, "restricted")
      _G.UnitDistanceSquared = false
      _G.UnitPosition = function() return 0, secret, 0, 1 end
      T.assertEq(Distance.Measure("target").reason, "restricted")
    end)
  end)
  T.it("ignores malformed and non-finite coordinate results", function()
    for _, invalid in ipairs({ math.huge, -math.huge, 0 / 0, "12" }) do
      outside({ UnitPosition = function() return invalid, 0, 0, 1 end }, function()
        T.assertNil(Distance.Measure("target").distance)
      end)
    end
  end)
end)

T.describe("Distance point selection", function()
  T.it("memorizes a ground position and updates its distance while moving", function()
    local x, y = 0, 0
    Distance.ClearOrigin()
    outside({ UnitPosition = function() return x, y, 0, 1 end }, function()
      T.assertEq(Distance.Measure("origin").reason, "no_origin")
      T.assertTrue(Distance.RememberPlayerPosition())
      T.assertEq(Distance.mode, "origin")
      x, y = 15, 20
      local result = Distance.Measure()
      T.assertEq(result.distance, 25); T.assertEq(result.category, "medium")
      Distance.ClearOrigin(); T.assertEq(Distance.Measure().reason, "no_origin")
    end)
  end)
  T.it("measures the native map waypoint without mixing map and unit axes", function()
    outside({ C_Map = {
      GetUserWaypoint = function() return { uiMapID = 2, position = { x = 0.53, y = 0.54 } } end,
      GetBestMapForUnit = function() return 1 end,
      GetPlayerMapPosition = function() return { x = 0.5, y = 0.5 } end,
      GetWorldPosFromMapPos = function(_, pos) return 7, { x = pos.x * 100, y = pos.y * 100 } end,
    }, UnitPosition = function() error("map positions must use the same coordinate system") end }, function()
      local result = Distance.Measure("waypoint")
      T.assertNear(result.distance, 5); T.assertEq(result.source, "waypoint")
    end)
  end)
  T.it("does not fabricate map positions when no waypoint exists", function()
    outside({ C_Map = { GetUserWaypoint = function() return nil end } }, function()
      T.assertEq(Distance.Measure("waypoint").reason, "no_waypoint")
    end)
  end)
  T.it("rejects map waypoints in another continent", function()
    outside({ C_Map = {
      GetUserWaypoint = function() return { uiMapID = 2, position = { x = 0.5, y = 0.5 } } end,
      GetBestMapForUnit = function() return 1 end,
      GetPlayerMapPosition = function() return { x = 0.5, y = 0.5 } end,
      GetWorldPosFromMapPos = function(map) return map, { x = 10, y = 10 } end,
    } }, function()
      T.assertEq(Distance.Measure("waypoint").reason, "different_map")
    end)
  end)
  T.it("rejects secret map coordinates before sending them to another API", function()
    local secret, conversions = {}, 0
    outside({ issecretvalue = function(value) return rawequal(value, secret) end,
      C_Map = {
        GetUserWaypoint = function() return { uiMapID = 2, position = { x = secret, y = 0.5 } } end,
        GetWorldPosFromMapPos = function() conversions = conversions + 1 end,
      } }, function()
      T.assertEq(Distance.Measure("waypoint").reason, "restricted")
      T.assertEq(conversions, 0)
    end)
  end)
  T.it("keeps the active mode when an unknown mode is requested", function()
    Distance.SetMode("target")
    T.assertFalse(Distance.SetMode("ground")); T.assertEq(Distance.mode, "target")
  end)
end)
