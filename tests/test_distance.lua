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
    UnitPosition = false, UnitDistanceSquared = false, C_Map = false, C_Housing = false,
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

T.describe("Housing proximity capabilities", function()
  local function housing(kind, extra, fn)
    local api = {
      IsInInstance = function() return true, kind end,
      C_Housing = {
        IsInsideHouse = function() return kind == "interior" end,
        IsOnNeighborhoodMap = function() return kind == "neighborhood" end,
        GetCurrentNeighborhoodGUID = function() return "Neighborhood-A" end,
        GetCurrentHouseInfo = function() return {houseGUID="House-A"} end,
      },
      UnitPosition = function(unit) return unit == "player" and 0 or 3, unit == "player" and 0 or 4, 0, 100 end,
    }
    for k,v in pairs(extra or {}) do api[k]=v end
    outside(api,fn)
  end
  local function maps(x,y)
    return {
      GetBestMapForUnit=function() return 10 end,
      GetPlayerMapPosition=function() return {x=x or .5,y=y or .5} end,
      GetWorldPosFromMapPos=function(_,p) return 100,{x=p.x*100,y=p.y*100} end,
      GetUserWaypoint=function() return {uiMapID=10,position={x=.53,y=.54}} end,
    }
  end
  T.it("measures accessible targets and self positions in neighborhoods and house interiors",function()
    for _,kind in ipairs({"neighborhood","interior"}) do
      housing(kind,{},function()
        T.assertEq(Distance.Measure("target").distance,5)
        local p=Distance.GetPlayerPosition()
        T.assertEq(p.scope,kind=="interior" and "H-House-A" or "N-Neighborhood-A")
        T.assertTrue(Distance.IsValidPosition(p))
        _G.UnitDistanceSquared=function() return 900,true end
        T.assertEq(Distance.Measure("target").distance,30)
        T.assertTrue(Distance.RememberPlayerPosition())
        T.assertEq(Distance.Measure("origin").distance,0)
        Distance.ClearOrigin()
      end)
    end
  end)
  T.it("recognizes housing even when the instance flag is false",function()
    housing("neighborhood",{IsInInstance=function() return false,"none" end},function()
      T.assertEq(Distance.GetPlayerPosition().scope,"N-Neighborhood-A")
    end)
  end)
  T.it("continues to block PvE, PvP, scenarios and unknown instances before coordinate access",function()
    for _,kind in ipairs({"party","raid","pvp","arena","scenario","unknown"}) do
      housing(kind,{UnitPosition=function() error("must not query") end,
        C_Map=maps()},function()
        T.assertEq(Distance.Measure("target").reason,"instance")
        T.assertEq(Distance.Measure("waypoint").reason,"instance")
        T.assertNil(Distance.GetPlayerPosition()); T.assertFalse(Distance.RememberPlayerPosition())
      end)
    end
    housing("neighborhood",{InCombatLockdown=function() return true end},function()
      T.assertEq(Distance.Measure("target").reason,"combat")
      T.assertNil(Distance.GetPlayerPosition())
    end)
  end)
  T.it("uses public map conversion only as a housing fallback and never mixes coordinate bases",function()
    housing("neighborhood",{UnitPosition=function() return nil end,C_Map=maps()},function()
      local p=Distance.GetPlayerPosition()
      T.assertEq(p.x,50); T.assertEq(p.basis,"M"); T.assertEq(p.scope,"N-Neighborhood-A")
      T.assertNear(Distance.Measure("waypoint").distance,5)
      T.assertTrue(Distance.RememberPlayerPosition())
      _G.C_Map=maps(.53,.54); T.assertNear(Distance.Measure("origin").distance,5)
      _G.UnitPosition=function() return 53,54,0,100 end
      T.assertEq(Distance.Measure("origin").reason,"different_map")
      Distance.ClearOrigin()
    end)
    outside({C_Map=maps()},function() T.assertNil(Distance.GetPlayerPosition()) end)
  end)
  T.it("does not compare a saved origin across different houses or neighborhoods",function()
    for _,kind in ipairs({"interior","neighborhood"}) do
      housing(kind,{},function()
        T.assertTrue(Distance.RememberPlayerPosition())
        _G.C_Housing.GetCurrentNeighborhoodGUID=function() return "Neighborhood-B" end
        _G.C_Housing.GetCurrentHouseInfo=function() return {houseGUID="House-B"} end
        T.assertEq(Distance.Measure("origin").reason,"different_map")
        Distance.ClearOrigin()
      end)
    end
  end)
  T.it("requires a resolved housing identity for broadcast positions but not target measurements",function()
    housing("interior",{},function()
      _G.C_Housing.GetCurrentHouseInfo=function() return nil end
      local p,reason=Distance.GetPlayerPosition()
      T.assertNil(p); T.assertEq(reason,"housing_context")
      T.assertEq(Distance.Measure("target").distance,5)
      T.assertFalse(Distance.RememberPlayerPosition())
      _G.C_Housing.GetCurrentHouseInfo=function() return {houseGUID="bad:id"} end
      T.assertNil(Distance.GetPlayerPosition())
    end)
  end)
  T.it("never falls back after a secret housing position or identity",function()
    local secret=setmetatable({}, {__tostring=function() error("secret formatting") end})
    housing("interior",{issecretvalue=function(v) return rawequal(v,secret) end,
      UnitPosition=function() return secret,0,0,100 end,
      C_Map={GetBestMapForUnit=function() error("must not fall back") end}},function()
      local p,reason=Distance.GetPlayerPosition()
      T.assertNil(p); T.assertEq(reason,"restricted")
      _G.C_Housing.GetCurrentHouseInfo=function() return {houseGUID=secret} end
      p,reason=Distance.GetPlayerPosition(); T.assertNil(p); T.assertEq(reason,"restricted")
      _G.C_Housing.GetCurrentHouseInfo=function() return secret end
      p,reason=Distance.GetPlayerPosition(); T.assertNil(p); T.assertEq(reason,"restricted")
      _G.IsInInstance=function() return true,secret end
      T.assertEq(Distance.Measure().reason,"restricted")
    end)
  end)
  T.it("requests initially missing house information without spamming the server",function()
    housing("interior",{},function()
      local now,requests,loaded=MOCKS.fakeNow,0,false
      MOCKS.fakeNow=10000
      _G.C_Housing.GetCurrentHouseInfo=function() return loaded and {houseGUID="House-Visitor"} or nil end
      _G.C_Housing.RequestCurrentHouseInfo=function() requests=requests+1 end
      for _=1,20 do T.assertNil(Distance.GetPlayerPosition()) end
      T.assertEq(requests,1)
      MOCKS.fakeNow=10010; T.assertNil(Distance.GetPlayerPosition()); T.assertEq(requests,2)
      loaded=true; T.assertEq(Distance.GetPlayerPosition().scope,"H-House-Visitor")
      T.assertEq(requests,2); MOCKS.fakeNow=now
    end)
  end)
  T.it("stays unavailable when both housing coordinate paths are missing or restricted",function()
    housing("neighborhood",{UnitPosition=function() error("unavailable") end,C_Map=maps()},function()
      _G.C_Map.GetPlayerMapPosition=function() return nil end
      local p,reason=Distance.GetPlayerPosition()
      T.assertNil(p); T.assertEq(reason,"unavailable")
      local secret={}; _G.issecretvalue=function(v) return rawequal(v,secret) end
      _G.C_Map.GetPlayerMapPosition=function() return {x=secret,y=.5} end
      p,reason=Distance.GetPlayerPosition(); T.assertNil(p); T.assertEq(reason,"restricted")
    end)
  end)
  T.it("rejects unsafe outbound positions before serialization",function()
    for _,p in ipairs({{map=1,x=0/0,y=0},{map=1,x=math.huge,y=0},
      {map=1.5,x=0,y=0},{map=1,x=0,y=0,scope="bad:scope"},
      {map=1,x=0,y=0,scope="N-"..string.rep("a",100)},
      {map=1,x=0,y=0,basis="M"},{map=1,x=0,y=0,basis="unknown"}}) do
      T.assertFalse(Distance.IsValidPosition(p))
      T.assertFalse(NS.Comm:SendTyping("SAY",nil,true,p))
    end
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

