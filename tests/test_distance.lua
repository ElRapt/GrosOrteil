---@diagnostic disable: undefined-global
-- Distance calculator ("Aura de distance"): category bands, formatting,
-- and the ground-aura overlay math (geometry, calibration, auto-tilt).
local T = _G.T
local ns = _G.NS
local Distance = ns.Distance

T.describe("Distance.Categorize", function()
  local function keyAt(m)
    local cat = Distance.Categorize(m)
    return cat and cat.key or nil
  end

  T.it("rejects nil and negative input", function()
    T.assertNil(Distance.Categorize(nil))
    T.assertNil(Distance.Categorize(-0.1))
    T.assertNil(Distance.Categorize("junk"))
  end)

  T.it("maps the five RP bands (lower-inclusive boundaries)", function()
    T.assertEq(keyAt(0),     "contact")
    T.assertEq(keyAt(0.99),  "contact")
    T.assertEq(keyAt(1),     "restreinte")
    T.assertEq(keyAt(4.99),  "restreinte")
    T.assertEq(keyAt(5),     "courte")
    T.assertEq(keyAt(24.9),  "courte")
    T.assertEq(keyAt(25),    "moyenne")
    T.assertEq(keyAt(39.9),  "moyenne")
    T.assertEq(keyAt(40),    "longue")   -- Grappin still reaches 40 m
    T.assertEq(keyAt(500),   "longue")
  end)

  T.it("uses the spec labels and distinct colors", function()
    local labels = {}
    local colors = {}
    for _, cat in ipairs(Distance.CATEGORIES) do
      labels[#labels + 1] = cat.label
      local c = string.format("%.2f/%.2f/%.2f", cat.r, cat.g, cat.b)
      T.assertNil(colors[c])  -- no two categories share a color
      colors[c] = true
    end
    T.assertEq(table.concat(labels, "|"),
      "Contact|Distance restreinte|Courte distance|Moyenne distance|Longue distance")
  end)
end)

T.describe("Distance.RangeLabel / FormatMeters", function()
  T.it("renders legend ranges", function()
    local cats = Distance.CATEGORIES
    T.assertEq(Distance.RangeLabel(cats[1]), "moins de 1 m")
    T.assertEq(Distance.RangeLabel(cats[2]), "1 à 5 m")
    T.assertEq(Distance.RangeLabel(cats[3]), "5 à 25 m")
    T.assertEq(Distance.RangeLabel(cats[4]), "25 à 40 m")
    T.assertEq(Distance.RangeLabel(cats[5]), "plus de 40 m")
    T.assertEq(Distance.RangeLabel(nil), "")
  end)

  T.it("formats meters with a French decimal comma", function()
    T.assertEq(Distance.FormatMeters(0.46),  "0,5 m")
    T.assertEq(Distance.FormatMeters(9.94),  "9,9 m")
    T.assertEq(Distance.FormatMeters(12.6),  "13 m")
    T.assertEq(Distance.FormatMeters(-3),    "0,0 m")
    T.assertEq(Distance.FormatMeters(nil),   "0,0 m")
  end)
end)

T.describe("Distance ground-aura math", function()
  T.it("NormalizeOverlayConfig falls back to defaults and clamps", function()
    local d = Distance.OVERLAY_DEFAULTS
    local cfg = Distance.NormalizeOverlayConfig(nil)
    T.assertEq(cfg.scale, d.scale)
    T.assertEq(cfg.squash, d.squash)
    T.assertEq(cfg.offsetY, d.offsetY)
    cfg = Distance.NormalizeOverlayConfig({ scale = 99, squash = 0, offsetY = "junk" })
    T.assertEq(cfg.scale, 3.0)      -- clamped high
    T.assertEq(cfg.squash, 0.2)     -- clamped low
    T.assertEq(cfg.offsetY, d.offsetY)
    cfg = Distance.NormalizeOverlayConfig({ scale = "1.5" })
    T.assertNear(cfg.scale, 1.5, 1e-9)
  end)

  T.it("NormalizeOverlayConfig defaults auto-tilt on; only explicit false disables", function()
    T.assertTrue(Distance.NormalizeOverlayConfig(nil).auto)
    T.assertTrue(Distance.NormalizeOverlayConfig({}).auto)
    T.assertTrue(Distance.NormalizeOverlayConfig({ auto = "junk" }).auto)
    T.assertTrue(Distance.NormalizeOverlayConfig({ auto = true }).auto)
    T.assertEq(Distance.NormalizeOverlayConfig({ auto = false }).auto, false)
  end)

  T.it("OVERLAY_BANDS colors index real categories and rim sits at the Grappin edge", function()
    local bands = Distance.OVERLAY_BANDS
    -- Drawn biggest-first.
    local prev = math.huge
    for _, band in ipairs(bands) do
      T.assertTrue(band.radius <= prev, "bands not biggest-first")
      prev = band.radius
      local cat = Distance.CATEGORIES[band.color]
      T.assertTrue(cat ~= nil, "band color must index a category")
    end
    -- Outer band is the 40 m Grappin edge (Longue distance, blue, idx 5);
    -- the green disc just inside it leaves a thin rim.
    T.assertEq(bands[1].radius, 40)
    T.assertEq(bands[1].color, 5)
    T.assertTrue(bands[2].radius < bands[1].radius and bands[2].radius >= 39)
    -- Inner bands line up with the category boundaries.
    T.assertEq(bands[3].radius, 25)
    T.assertEq(bands[4].radius, 5)
    T.assertEq(bands[5].radius, 1)
  end)

  T.it("SquashFromPitch follows sin(pitch) with sign/clamp handling", function()
    T.assertNear(Distance.SquashFromPitch(90), 1.0, 1e-9)
    T.assertNear(Distance.SquashFromPitch(30), 0.5, 1e-9)
    T.assertNear(Distance.SquashFromPitch(-30), 0.5, 1e-9)   -- sign ignored
    T.assertNear(Distance.SquashFromPitch(120), 1.0, 1e-9)   -- clamped to 90
    T.assertEq(Distance.SquashFromPitch(0), 0.2)             -- floored
    T.assertEq(Distance.SquashFromPitch(5), 0.2)
    T.assertNil(Distance.SquashFromPitch(nil))
    T.assertNil(Distance.SquashFromPitch("junk"))
  end)

  T.it("OverlayRadiusPx scales with meters and inversely with zoom", function()
    local base = Distance.OverlayRadiusPx(10, 20, 1000, 1)
    T.assertNear(Distance.OverlayRadiusPx(20, 20, 1000, 1), base * 2, 1e-9)
    T.assertNear(Distance.OverlayRadiusPx(10, 40, 1000, 1), base / 2, 1e-9)
    T.assertNear(Distance.OverlayRadiusPx(10, 20, 1000, 2), base * 2, 1e-9)
  end)

  T.it("OverlayRadiusPx floors the zoom and rejects junk", function()
    -- Zoom below 2 behaves like zoom 2 (first person would explode the math).
    T.assertEq(Distance.OverlayRadiusPx(10, 0.1, 1000, 1),
               Distance.OverlayRadiusPx(10, 2, 1000, 1))
    T.assertEq(Distance.OverlayRadiusPx(nil, 20, 1000, 1), 0)
    T.assertEq(Distance.OverlayRadiusPx(-5, 20, 1000, 1), 0)
  end)

  T.it("SetOverlayOption stores clamped values under French keys", function()
    local v = Distance.SetOverlayOption("taille", 1.4)
    T.assertNear(v, 1.4, 1e-9)
    v = Distance.SetOverlayOption("aplat", 5)       -- clamped to 1.0
    T.assertNear(v, 1.0, 1e-9)
    v = Distance.SetOverlayOption("hauteur", -0.1)
    T.assertNear(v, -0.1, 1e-9)
    T.assertNil(Distance.SetOverlayOption("nimporte", 1))
    -- Reset for other tests / a clean saved state.
    Distance.SetOverlayOption("taille", Distance.OVERLAY_DEFAULTS.scale)
    Distance.SetOverlayOption("aplat", Distance.OVERLAY_DEFAULTS.squash)
    Distance.SetOverlayOption("hauteur", Distance.OVERLAY_DEFAULTS.offsetY)
    Distance.SetOverlayAuto(true)
  end)

  T.it("manual aplat disables auto-tilt; SetOverlayAuto restores/toggles it", function()
    Distance.SetOverlayAuto(true)
    T.assertTrue(Distance.IsOverlayAuto())
    Distance.SetOverlayOption("aplat", 0.6)
    T.assertEq(Distance.IsOverlayAuto(), false)
    T.assertTrue(Distance.SetOverlayAuto(true))
    T.assertTrue(Distance.IsOverlayAuto())
    T.assertEq(Distance.SetOverlayAuto(nil), false)  -- nil toggles
    T.assertTrue(Distance.SetOverlayAuto(nil))
    -- Other knobs do not touch auto.
    Distance.SetOverlayOption("taille", 1.2)
    T.assertTrue(Distance.IsOverlayAuto())
    -- Clean saved state.
    Distance.SetOverlayOption("taille", Distance.OVERLAY_DEFAULTS.scale)
    Distance.SetOverlayOption("aplat", Distance.OVERLAY_DEFAULTS.squash)
    Distance.SetOverlayAuto(true)
  end)
end)

