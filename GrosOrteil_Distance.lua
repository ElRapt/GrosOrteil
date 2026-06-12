---@diagnostic disable: undefined-global
local _, ns = ...

-- "Aura de distance" — the RP distance calculator and its in-world ground
-- aura: a screen-space ellipse overlay centered on the character, drawn on
-- the WorldFrame and sized live from the camera zoom (and pitch, when the
-- client exposes it) so the colored bands track the real category radii.
--
-- Pure section (offline-testable): the five RP range categories, the
-- meter formatting, and all the overlay geometry/calibration math.
--
-- World units are treated 1:1 as meters (RP convention — Grappin reaches 40).

local Distance = {}
ns.Distance = Distance

local type     = type
local ipairs   = ipairs
local tonumber = tonumber
local math     = math
local string   = string

-- ── Pure: categories ───────────────────────────────────────────────────────────

-- Bands are lower-inclusive: exactly 1 m is "Distance restreinte", exactly
-- 40 m is "Longue distance" (Grappin still reaches its full 40 m).
-- Colors run hot → cold as range opens up.
Distance.CATEGORIES = {
  { key = "contact",    label = "Contact",             min = 0,  max = 1,         r = 0.90, g = 0.22, b = 0.18 },
  { key = "restreinte", label = "Distance restreinte", min = 1,  max = 5,         r = 1.00, g = 0.55, b = 0.10 },
  { key = "courte",     label = "Courte distance",     min = 5,  max = 25,        r = 1.00, g = 0.84, b = 0.25 },
  { key = "moyenne",    label = "Moyenne distance",    min = 25, max = 40,        r = 0.35, g = 0.80, b = 0.30 },
  { key = "longue",     label = "Longue distance",     min = 40, max = math.huge, r = 0.30, g = 0.58, b = 0.95 },
}

-- meters → category table, or nil for nil/negative input.
function Distance.Categorize(meters)
  local m = tonumber(meters)
  if not m or m < 0 then return nil end
  for _, cat in ipairs(Distance.CATEGORIES) do
    if m < cat.max then return cat end
  end
  return Distance.CATEGORIES[#Distance.CATEGORIES]
end

-- Human-readable range for the legend ("moins de 1 m", "1 à 5 m", ...).
function Distance.RangeLabel(cat)
  if not cat then return "" end
  if cat.min <= 0 then return string.format("moins de %d m", cat.max) end
  if cat.max == math.huge then return string.format("plus de %d m", cat.min) end
  return string.format("%d à %d m", cat.min, cat.max)
end

-- "12,3 m" under 10 m (the close bands deserve the precision), "23 m" above.
function Distance.FormatMeters(meters)
  local m = tonumber(meters) or 0
  if m < 0 then m = 0 end
  local s
  if m < 10 then s = string.format("%.1f m", m)
  else           s = string.format("%d m", math.floor(m + 0.5)) end
  return (s:gsub("%.", ","))
end

-- ── Pure: in-world ground aura math ────────────────────────────────────────────
-- WoW removed world-projection APIs long ago (no camera matrices since 3.3.5),
-- so a true ground decal is impossible. The aura is the honest best fit: a
-- screen-space ellipse centered on the character, sized from the camera zoom.

-- User calibration, persisted in db.distance.overlay.
--   scale   : global size multiplier
--   squash  : ellipse height/width ratio, used when auto is off (or pitch
--             is unreadable on this client)
--   offsetY : vertical center offset as a fraction of screen height
--   auto    : squash follows the live camera pitch instead of `squash`
Distance.OVERLAY_DEFAULTS = { scale = 1.0, squash = 0.55, offsetY = -0.05, auto = true }

function Distance.NormalizeOverlayConfig(cfg)
  cfg = type(cfg) == "table" and cfg or {}
  local d = Distance.OVERLAY_DEFAULTS
  local function clamp(v, lo, hi, def)
    v = tonumber(v)
    if not v then return def end
    if v < lo then return lo elseif v > hi then return hi end
    return v
  end
  return {
    scale   = clamp(cfg.scale,   0.3, 3.0, d.scale),
    squash  = clamp(cfg.squash,  0.2, 1.0, d.squash),
    offsetY = clamp(cfg.offsetY, -0.3, 0.3, d.offsetY),
    auto    = cfg.auto ~= false,  -- default on; only an explicit false disables
  }
end

-- A camera pitched `deg` below the horizon sees a ground circle squashed by
-- sin(pitch): top-down (90°) shows a true circle, horizontal (0°) a line.
-- Sign is ignored (some pitch sources point "down" negative). Floored at the
-- manual-squash minimum so a near-horizontal camera still draws something.
-- nil for unreadable input — the caller then falls back to manual squash.
function Distance.SquashFromPitch(pitchDeg)
  local p = tonumber(pitchDeg)
  if not p then return nil end
  if p < 0 then p = -p end
  if p > 90 then p = 90 end
  local s = math.sin(math.rad(p))
  if s < 0.2 then s = 0.2 end
  return s
end

-- Approximate on-screen pixel radius of a ground circle of `meters` around
-- the player. With WoW's ~53° vertical FOV, half the screen height spans
-- about half the camera distance on the focal plane, so px ≈ m·H/zoom.
-- Zoom is floored at 2 (first person would explode the math).
function Distance.OverlayRadiusPx(meters, zoom, screenH, scale)
  local m = tonumber(meters) or 0
  if m < 0 then m = 0 end
  local z = tonumber(zoom) or 0
  if z < 2 then z = 2 end
  return m * (tonumber(screenH) or 0) * (tonumber(scale) or 1) / z
end

-- ── Frame layer (WoW-only) ─────────────────────────────────────────────────────

local CreateFrame = rawget(_G, "CreateFrame")
local UIParent    = rawget(_G, "UIParent")

local DISC_TEX = "Interface\\CharacterFrame\\TempPortraitAlphaMask"  -- soft white disc

local overlay, overlayBands, overlayCfg
local updateOverlay  -- forward declaration

local function notifyToggleChanged()
  if ns.UI and ns.UI.refreshAuraToggleBtn then ns.UI.refreshAuraToggleBtn() end
end

-- ── In-world ground aura ───────────────────────────────────────────────────────
-- A click-through, full-screen frame on the WorldFrame: translucent ellipse
-- bands centered on the character, resized live from the camera zoom so they
-- track the real category radii. Beyond 40 m the world is untinted ("Longue
-- distance"); a brighter blue rim marks the Grappin edge itself.

local function overlayDb()
  local db = ns.GetDB and ns.GetDB()
  if type(db) ~= "table" then return nil end
  db.distance = db.distance or {}
  return db.distance
end

local function loadOverlayCfg()
  local d = overlayDb()
  overlayCfg = Distance.NormalizeOverlayConfig(d and d.overlay)
  return overlayCfg
end

-- Drawn biggest-first; `color` indexes Distance.CATEGORIES. The 39.2 m green
-- disc sits on the 40 m blue one, leaving a thin bright rim at the edge.
-- Exposed so the tests can pin the radii to the category boundaries.
Distance.OVERLAY_BANDS = {
  { radius = 40,   color = 5, alpha = 0.45 },
  { radius = 39.2, color = 4, alpha = 0.07 },
  { radius = 25,   color = 3, alpha = 0.10 },
  { radius = 5,    color = 2, alpha = 0.13 },
  { radius = 1,    color = 1, alpha = 0.16 },
}
local OVERLAY_BANDS = Distance.OVERLAY_BANDS

-- Live camera pitch in degrees, or nil when no source on this client works.
-- Tried in order: the active-camera object (modern clients expose its
-- orientation in radians), then the cameraSavedPitch CVar the client keeps
-- up to date so the camera survives a /reload (already in degrees).
local function readCameraPitchDeg()
  local CI = rawget(_G, "C_CameraInfo")
  if type(CI) == "table" and CI.GetActiveCameraID and CI.GetCameraInfo then
    local ok, id = pcall(CI.GetActiveCameraID)
    if ok and id then
      local okInfo, info = pcall(CI.GetCameraInfo, id)
      local pitch = okInfo and type(info) == "table" and tonumber(info.pitch)
      if pitch then return math.deg(pitch) end
    end
  end
  local getCVar = rawget(_G, "GetCVar")
  if getCVar then
    local ok, v = pcall(getCVar, "cameraSavedPitch")
    if ok then return tonumber(v) end
  end
  return nil
end

updateOverlay = function()
  if not overlay then return end
  local getZoom = rawget(_G, "GetCameraZoom")
  local zoom = (getZoom and getZoom()) or 0
  local h = overlay:GetHeight() or 0
  local cfg = overlayCfg or loadOverlayCfg()
  if zoom < 1.5 or h <= 0 then
    -- First person (or unsized frame): an aura around yourself has no
    -- meaningful shape; hide quietly until the camera zooms out.
    for i = 1, #overlayBands do overlayBands[i]:Hide() end
    return
  end
  local squash = cfg.squash
  if cfg.auto then
    squash = Distance.SquashFromPitch(readCameraPitchDeg()) or squash
  end
  local cy = cfg.offsetY * h
  for i, band in ipairs(OVERLAY_BANDS) do
    local px = Distance.OverlayRadiusPx(band.radius, zoom, h, cfg.scale)
    local t = overlayBands[i]
    t:SetSize(px * 2, px * 2 * squash)
    t:ClearAllPoints()
    t:SetPoint("CENTER", overlay, "CENTER", 0, cy)
    t:Show()
  end
end

local function ensureOverlay()
  if overlay then return end
  local worldFrame = rawget(_G, "WorldFrame") or UIParent
  overlay = CreateFrame("Frame", "GrosOrteilDistanceOverlay", worldFrame)
  overlay:SetAllPoints(worldFrame)
  overlay:SetFrameStrata("BACKGROUND")
  overlay:EnableMouse(false)
  overlayBands = {}
  for i, band in ipairs(OVERLAY_BANDS) do
    local cat = Distance.CATEGORIES[band.color]
    local t = overlay:CreateTexture(nil, "BACKGROUND", nil, -8 + i)
    t:SetTexture(DISC_TEX)
    t:SetVertexColor(cat.r, cat.g, cat.b, band.alpha)
    t:Hide()
    overlayBands[i] = t
  end
  loadOverlayCfg()
  local acc = 0
  overlay:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc < 0.05 then return end
    acc = 0
    updateOverlay()
  end)
  overlay:Hide()
end

-- ── Public API ─────────────────────────────────────────────────────────────────

function Distance.ShowOverlay()
  ensureOverlay()
  loadOverlayCfg()
  overlay:Show()
  updateOverlay()
  local d = overlayDb()
  if d then d.overlayShown = true end
  notifyToggleChanged()
end

function Distance.HideOverlay()
  if overlay then overlay:Hide() end
  local d = overlayDb()
  if d then d.overlayShown = false end
  notifyToggleChanged()
end

function Distance.IsOverlayShown()
  return overlay ~= nil and overlay:IsShown()
end

function Distance.ToggleOverlay()
  if Distance.IsOverlayShown() then Distance.HideOverlay() else Distance.ShowOverlay() end
end

-- Calibration via slash: /go aura taille|aplat|hauteur <valeur>.
-- Returns the clamped value actually stored, or nil for unknown keys.
-- Setting `aplat` by hand is an explicit override: it switches auto-tilt off
-- (/go aura auto re-enables it).
local OVERLAY_OPTION_KEYS = { taille = "scale", aplat = "squash", hauteur = "offsetY" }
function Distance.SetOverlayOption(key, value)
  local field = OVERLAY_OPTION_KEYS[key] or key
  if field ~= "scale" and field ~= "squash" and field ~= "offsetY" then return nil end
  local d = overlayDb()
  if not d then return nil end
  d.overlay = type(d.overlay) == "table" and d.overlay or {}
  d.overlay[field] = value
  if field == "squash" then d.overlay.auto = false end
  d.overlay = Distance.NormalizeOverlayConfig(d.overlay)
  overlayCfg = d.overlay
  if overlay and overlay:IsShown() then updateOverlay() end
  return overlayCfg[field]
end

-- Auto-tilt: the ellipse squash follows the live camera pitch.
-- nil toggles; returns the new state (or nil when no DB is available).
function Distance.SetOverlayAuto(enabled)
  local d = overlayDb()
  if not d then return nil end
  d.overlay = Distance.NormalizeOverlayConfig(d.overlay)
  if enabled == nil then enabled = not d.overlay.auto end
  d.overlay.auto = not not enabled
  overlayCfg = d.overlay
  if overlay and overlay:IsShown() then updateOverlay() end
  return d.overlay.auto
end

function Distance.IsOverlayAuto()
  local d = overlayDb()
  local cfg = Distance.NormalizeOverlayConfig(d and d.overlay)
  return cfg.auto
end

-- Login hook (Main.lua): restore a ground aura the player left enabled.
function ns.Distance_Init()
  local d = overlayDb()
  if d and d.overlayShown then Distance.ShowOverlay() end
end

