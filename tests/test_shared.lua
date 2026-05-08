---@diagnostic disable: undefined-global
local T = _G.T
local ns = _G.NS
local Shared = ns.Shared

T.describe("Shared.Round", function()
  T.it("rounds halves to nearest integer", function()
    T.assertEq(Shared.Round(0.5),  1)
    T.assertEq(Shared.Round(1.49), 1)
    T.assertEq(Shared.Round(1.5),  2)
    T.assertEq(Shared.Round(-0.5), -1)
    T.assertEq(Shared.Round(-1.5), -2)
  end)
  T.it("returns 0 for non-numeric input", function()
    T.assertEq(Shared.Round(nil),   0)
    T.assertEq(Shared.Round("foo"), 0)
  end)
end)

T.describe("Shared.RoundPct", function()
  T.it("converts fraction to integer percent", function()
    T.assertEq(Shared.RoundPct(0),     0)
    T.assertEq(Shared.RoundPct(0.5),   50)
    T.assertEq(Shared.RoundPct(0.999), 100)
    T.assertEq(Shared.RoundPct(1),     100)
    T.assertEq(Shared.RoundPct(0.123), 12)
  end)
end)

T.describe("Shared.GetKeysForIdx", function()
  T.it("maps indexes 1..5 to known keys", function()
    local r1, m1 = Shared.GetKeysForIdx(1); T.assertEq(r1, "res");  T.assertEq(m1, "maxRes")
    local r2, m2 = Shared.GetKeysForIdx(2); T.assertEq(r2, "res2"); T.assertEq(m2, "maxRes2")
    local r3, m3 = Shared.GetKeysForIdx(3); T.assertEq(r3, "res3"); T.assertEq(m3, "maxRes3")
    local r4, m4 = Shared.GetKeysForIdx(4); T.assertEq(r4, "res4"); T.assertEq(m4, "maxRes4")
    local r5, m5 = Shared.GetKeysForIdx(5); T.assertEq(r5, "auth"); T.assertEq(m5, "maxAuth")
  end)
  T.it("returns nil for out-of-range indexes", function()
    local r, m = Shared.GetKeysForIdx(0); T.assertNil(r); T.assertNil(m)
    r, m = Shared.GetKeysForIdx(99);      T.assertNil(r); T.assertNil(m)
  end)
end)

T.describe("Shared.GetResProfile", function()
  T.it("returns Warlock 3-resource profile", function()
    local p = Shared.GetResProfile({ classKey = "WARLOCK" })
    T.assertEq(#p, 3)
    T.assertEq(p[1].label, "Énergie gangrénée")
    T.assertEq(p[2].label, "Corruption")
    T.assertEq(p[3].label, "Fragments d'âme")
  end)
  T.it("returns single fallback for class without explicit profile", function()
    local p = Shared.GetResProfile({ classKey = "ROGUE" })
    T.assertEq(#p, 1)
    T.assertEq(p[1].label, "Énergie")
  end)
  T.it("returns generic Ressource for unknown class", function()
    local p = Shared.GetResProfile({ classKey = "UNKNOWN" })
    T.assertEq(#p, 1)
    T.assertEq(p[1].label, "Ressource")
  end)
  T.it("appends auth slot when pet authority is enabled", function()
    local s = { classKey = "MAGE", pet = { enabled = true, authorityEnabled = true } }
    local p = Shared.GetResProfile(s)
    -- Mage profile has 2 entries + auth.
    T.assertEq(#p, 3)
    T.assertEq(p[#p].idx, 5)
  end)
  T.it("does not append auth when pet disabled", function()
    local s = { classKey = "MAGE", pet = { enabled = false, authorityEnabled = true } }
    local p = Shared.GetResProfile(s)
    T.assertEq(#p, 2)
  end)
end)

T.describe("Shared.GetClassNameFr", function()
  T.it("returns localized name for known classes", function()
    T.assertEq(Shared.GetClassNameFr("MAGE"),    "Mage")
    T.assertEq(Shared.GetClassNameFr("WARLOCK"), "Démoniste")
    T.assertEq(Shared.GetClassNameFr("MEDIC"),   "Médecin")
  end)
  T.it("falls back gracefully for unknown / nil input", function()
    T.assertEq(Shared.GetClassNameFr(nil), "Inconnue")
    T.assertEq(Shared.GetClassNameFr(""),  "Inconnue")
    T.assertEq(Shared.GetClassNameFr("MADE_UP"), "MADE_UP")
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- Texture-coord helpers + overlay math (smoke against mock frames)
-- ────────────────────────────────────────────────────────────────────

-- Recording texture mock so we can assert show/hide/width side effects.
local function makeRecordingTex()
  local t = {
    _shown = false,
    _alpha = 1,
    _width = 0,
    _texture = nil,
    _coord = nil,
    _points = {},
  }
  function t:Show()             self._shown = true  end
  function t:Hide()             self._shown = false end
  function t:SetAlpha(a)        self._alpha = a end
  function t:SetWidth(w)        self._width = w end
  function t:GetWidth()         return self._width end
  function t:SetTexture(s)      self._texture = s end
  function t:SetTexCoord(...)   self._coord = { ... } end
  function t:SetColorTexture(r, g, b, a) self._color = { r, g, b, a } end
  function t:SetHeight(h)       self._height = h end
  function t:ClearAllPoints()   self._points = {} end
  function t:SetPoint(...)      self._points[#self._points + 1] = { ... } end
  return t
end

local function makeBar(width)
  return {
    _w = width,
    GetWidth = function(self) return self._w end,
    GetHeight = function() return 14 end,
    CreateTexture = function() return makeRecordingTex() end,
  }
end

T.describe("Shared.SetClassIconTexCoords", function()
  T.it("applies the texture+coords defined in CLASS_ICONS", function()
    local tex = makeRecordingTex()
    local def = Shared.CLASS_ICONS["MAGE"]
    T.assertNotNil(def)
    Shared.SetClassIconTexCoords(tex, "MAGE")
    T.assertEq(tex._texture, def.texture)
    T.assertEq(tex._coord[1], def.coords[1])
    T.assertEq(tex._coord[2], def.coords[2])
    T.assertEq(tex._coord[3], def.coords[3])
    T.assertEq(tex._coord[4], def.coords[4])
  end)
  T.it("MEDIC uses its custom icon entry", function()
    local tex = makeRecordingTex()
    Shared.SetClassIconTexCoords(tex, "MEDIC")
    T.assertEq(tex._texture, Shared.CLASS_ICONS["MEDIC"].texture)
  end)
  T.it("SHADOWPRIEST uses its custom icon entry", function()
    local tex = makeRecordingTex()
    Shared.SetClassIconTexCoords(tex, "SHADOWPRIEST")
    T.assertEq(tex._texture, Shared.CLASS_ICONS["SHADOWPRIEST"].texture)
  end)
  T.it("falls back to full coords for unknown class", function()
    local tex = makeRecordingTex()
    Shared.SetClassIconTexCoords(tex, "UNKNOWN")
    T.assertNotNil(tex._coord)
    T.assertEq(tex._coord[1], 0); T.assertEq(tex._coord[2], 1)
  end)
  T.it("no-op when texture has no SetTexCoord", function()
    Shared.SetClassIconTexCoords({}, "MAGE")
    Shared.SetClassIconTexCoords(nil, "MAGE")
    T.assertTrue(true)
  end)
end)

T.describe("Shared.HideOverlay", function()
  T.it("hides + collapses width", function()
    local tex = makeRecordingTex(); tex._shown = true; tex._width = 50
    Shared.HideOverlay(tex)
    T.assertFalse(tex._shown)
    T.assertEq(tex._alpha, 0)
    T.assertTrue(tex._width <= 0.001 + 1e-9)
  end)
  T.it("nil texture is a no-op", function()
    Shared.HideOverlay(nil); T.assertTrue(true)
  end)
end)

T.describe("Shared.UpdateHpShieldOverlays", function()
  T.it("hides both overlays when no shields", function()
    local block, magic = makeRecordingTex(), makeRecordingTex()
    block._shown = true; magic._shown = true
    Shared.UpdateHpShieldOverlays(block, magic, makeBar(100), 50, 100, 0, 0, 100)
    T.assertFalse(block._shown); T.assertFalse(magic._shown)
  end)
  T.it("shows magic overlay when magic > 0", function()
    local block, magic = makeRecordingTex(), makeRecordingTex()
    Shared.UpdateHpShieldOverlays(block, magic, makeBar(100), 50, 100, 0, 10, 100)
    T.assertTrue(magic._shown)
    T.assertTrue(magic._width > 0)
  end)
  T.it("shows block overlay when block > 0", function()
    local block, magic = makeRecordingTex(), makeRecordingTex()
    Shared.UpdateHpShieldOverlays(block, magic, makeBar(100), 50, 100, 10, 0, 100)
    T.assertTrue(block._shown)
  end)
  T.it("hides both when bar width is zero", function()
    local block, magic = makeRecordingTex(), makeRecordingTex()
    block._shown = true; magic._shown = true
    Shared.UpdateHpShieldOverlays(block, magic, makeBar(0), 50, 100, 10, 10, 0)
    T.assertFalse(block._shown); T.assertFalse(magic._shown)
  end)
  T.it("hides both when hp = 0", function()
    local block, magic = makeRecordingTex(), makeRecordingTex()
    block._shown = true; magic._shown = true
    Shared.UpdateHpShieldOverlays(block, magic, makeBar(100), 0, 100, 10, 10, 100)
    T.assertFalse(block._shown); T.assertFalse(magic._shown)
  end)
end)

T.describe("Shared marker helpers", function()
  T.it("MakeMarker returns hidden texture with stored pct", function()
    local m = Shared.MakeMarker(makeBar(100), 0.5, 1, 1, 1, 0.5, 2)
    T.assertEq(m.pct, 0.5)
    T.assertFalse(m._shown)
  end)
  T.it("HideMarkers hides all entries", function()
    local list = { makeRecordingTex(), makeRecordingTex(), nil, makeRecordingTex() }
    list[1]._shown = true; list[2]._shown = true; list[4]._shown = true
    Shared.HideMarkers(list)
    T.assertFalse(list[1]._shown); T.assertFalse(list[2]._shown); T.assertFalse(list[4]._shown)
  end)
  T.it("PositionMarkers no-ops when bar width is 0", function()
    local m = makeRecordingTex(); m.pct = 0.5
    Shared.PositionMarkers({ m }, makeBar(0))
    T.assertFalse(m._shown)
  end)
  T.it("PositionMarkers shows + clamps marker pct", function()
    local m = makeRecordingTex(); m.pct = 1.5  -- overshoot, must clamp to bar width
    Shared.PositionMarkers({ m }, makeBar(100))
    T.assertTrue(m._shown)
  end)
end)

-- ────────────────────────────────────────────────────────────────────
-- HP threshold marker factory (smoke)
-- ────────────────────────────────────────────────────────────────────

T.describe("Shared.MakeHpThresholdMarkers", function()
  T.it("creates 3 threshold markers and 1 cap marker", function()
    local markers, cap = Shared.MakeHpThresholdMarkers(makeBar(100))
    T.assertEq(#markers, 3)
    T.assertNotNil(cap)
    T.assertEq(markers[1].pct, 0.50)
    T.assertEq(markers[2].pct, 0.25)
    T.assertEq(markers[3].pct, 0.10)
  end)
end)
