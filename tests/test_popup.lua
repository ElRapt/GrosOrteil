---@diagnostic disable: undefined-global
local T = _G.T
local ns = _G.NS
local Popup = ns.TargetPopup
local h = Popup._test  -- helpers exposed for tests; see GrosOrteil_TargetPopup.lua

T.describe("TargetPopup name normalization", function()
  T.it("normalizeName lowercases and strips whitespace", function()
    T.assertEq(h.normalizeName("  Foo Bar "), "foobar")
    T.assertEq(h.normalizeName("FOO"), "foo")
    T.assertNil(h.normalizeName(""))
    T.assertNil(h.normalizeName("   "))
    T.assertNil(h.normalizeName(nil))
    T.assertNil(h.normalizeName(42))
  end)
  T.it("splitNameRealm splits on hyphen", function()
    local short, realm = h.splitNameRealm("Foo-Realm")
    T.assertEq(short, "foo")
    T.assertEq(realm, "realm")
    short, realm = h.splitNameRealm("Foo")
    T.assertEq(short, "foo")
    T.assertNil(realm)
  end)
  T.it("toCacheKey strips realm so Foo and Foo-Realm share cache", function()
    T.assertEq(h.toCacheKey("Foo"), "foo")
    T.assertEq(h.toCacheKey("Foo-Realm"), "foo")
    T.assertEq(h.toCacheKey("Foo-OtherRealm"), "foo")
  end)
  T.it("namesMatch treats missing realm as wildcard", function()
    T.assertTrue(h.namesMatch("Foo", "Foo-Realm"))
    T.assertTrue(h.namesMatch("Foo-Realm", "Foo"))
    T.assertTrue(h.namesMatch("Foo-Realm", "Foo-Realm"))
    T.assertFalse(h.namesMatch("Foo-RealmA", "Foo-RealmB"))
    T.assertFalse(h.namesMatch("Foo", "Bar"))
    T.assertFalse(h.namesMatch(nil, "Foo"))
  end)
  T.it("baseCharacterName returns short name without realm", function()
    T.assertEq(h.baseCharacterName("Foo-Realm"), "Foo")
    T.assertEq(h.baseCharacterName("Foo"), "Foo")
    T.assertEq(h.baseCharacterName(""), "Inconnu")
    T.assertEq(h.baseCharacterName(nil), "Inconnu")
  end)
end)

T.describe("TargetPopup color stripping", function()
  T.it("stripColorCodes removes |cFFRRGGBB and |r escapes", function()
    T.assertEq(h.stripColorCodes("|cFF00FF00Hello|r"), "Hello")
    T.assertEq(h.stripColorCodes("plain"), "plain")
    T.assertEq(h.stripColorCodes("  spaced  "), "spaced")
    T.assertNil(h.stripColorCodes(""))
    T.assertNil(h.stripColorCodes(nil))
  end)
end)

T.describe("TargetPopup owner-tooltip parser", function()
  T.it("matches English '<X's Pet>'", function()
    T.assertEq(h.extractOwnerNameFromTooltipText("<Lucas's Pet>"), "Lucas")
  end)
  T.it("matches French '<Pet de X>'", function()
    T.assertEq(h.extractOwnerNameFromTooltipText("<Pet de Lucas>"), "Lucas")
  end)
  T.it("matches French 'Familier de X'", function()
    T.assertEq(h.extractOwnerNameFromTooltipText("Familier de Lucas"), "Lucas")
  end)
  T.it("matches French 'Compagnon de X'", function()
    T.assertEq(h.extractOwnerNameFromTooltipText("Compagnon de Lucas"), "Lucas")
  end)
  T.it("strips color codes before matching", function()
    T.assertEq(h.extractOwnerNameFromTooltipText("|cFFFFFFFF<Pet de Lucas>|r"), "Lucas")
  end)
  T.it("returns nil for unrecognized text", function()
    T.assertNil(h.extractOwnerNameFromTooltipText("just some random text"))
    T.assertNil(h.extractOwnerNameFromTooltipText(""))
    T.assertNil(h.extractOwnerNameFromTooltipText(nil))
  end)
end)

T.describe("TargetPopup state cache", function()
  local function clearCache()
    for k in pairs(h.cache) do h.cache[k] = nil end
  end

  T.it("setCached + getCached round-trip", function()
    clearCache()
    h.setCached("foo", { hp = 10 })
    local got = h.getCached("foo")
    T.assertNotNil(got)
    T.assertEq(got.hp, 10)
    clearCache()
  end)
  T.it("getCached returns nil for missing key", function()
    clearCache()
    T.assertNil(h.getCached("never-set-this-key"))
  end)
  T.it("getCached evicts and returns nil for entries older than TTL", function()
    clearCache()
    _G.MOCKS.fakeNow = 1000
    h.setCached("aging", { hp = 1 })
    T.assertNotNil(h.getCached("aging"))
    -- Advance past TTL.
    _G.MOCKS.fakeNow = _G.MOCKS.fakeNow + h.CACHE_TTL + 1
    T.assertNil(h.getCached("aging"))
    -- Entry should also be removed from the underlying map.
    T.assertNil(h.cache["aging"])
    _G.MOCKS.fakeNow = nil
    clearCache()
  end)
  T.it("setCached evicts oldest entry when cache exceeds CACHE_MAX", function()
    clearCache()
    _G.MOCKS.fakeNow = 1000
    -- Fill above CACHE_MAX. Older entries get older fakeNow timestamps.
    for i = 1, h.CACHE_MAX do
      _G.MOCKS.fakeNow = 1000 + i
      h.setCached("k" .. i, { hp = i })
    end
    T.assertNotNil(h.cache["k1"])
    -- Insert one more; the soft cap should drop the oldest (k1, ts=1001).
    _G.MOCKS.fakeNow = 2000
    h.setCached("kNew", { hp = 0 })
    T.assertNil(h.cache["k1"], "oldest entry should be evicted")
    T.assertNotNil(h.cache["kNew"])
    _G.MOCKS.fakeNow = nil
    clearCache()
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- senderToUnitID
-- ────────────────────────────────────────────────────────────────────

T.describe("TargetPopup senderToUnitID", function()
  T.it("passes through names that already include a realm", function()
    T.assertEq(h.senderToUnitID("Foo-Realm"), "Foo-Realm")
  end)
  T.it("appends TRP3's player_realm_id when available", function()
    rawset(_G, "TRP3_API", { globals = { player_realm_id = "MyRealm" } })
    T.assertEq(h.senderToUnitID("Foo"), "Foo-MyRealm")
    rawset(_G, "TRP3_API", nil)
  end)
  T.it("returns bare name when TRP3 is absent", function()
    rawset(_G, "TRP3_API", nil)
    T.assertEq(h.senderToUnitID("Foo"), "Foo")
  end)
end)
