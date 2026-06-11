---@diagnostic disable: undefined-global
local _, ns = ...

local RaidPanel = {}
ns.RaidPanel = RaidPanel

local Shared = ns.Shared

local type   = type
local math   = math
local string = string
local table  = table
local ipairs = ipairs

-- Stable WoW APIs: captured once at load (taint-neutral reads). Roster APIs are
-- looked up lazily inside getRaidMembers so the offline tests can swap them.
local CreateFrame = rawget(_G, "CreateFrame")
local UIParent    = rawget(_G, "UIParent")

-- ── Layout constants ──────────────────────────────────────────────────────────

local PANEL_W      = 320
local PANEL_H      = 560
local PAD          = 10
local HEADER_H     = 24
local SCROLL_W     = PANEL_W - PAD * 2
local CARD_PAD     = 6
local BAR_W        = SCROLL_W - CARD_PAD * 2
local ROW_H        = 15
local ROW_GAP      = 3
local NAME_H       = 15
local STATUS_H     = 16
local SECTION_GAP  = 6
local CARD_TOP_PAD = 5
local CARD_BOT_PAD = 6
local MAX_RES_BARS = 5

local HP_COLOR        = { 0.85, 0.16, 0.18 }
local HP_DEAD_COLOR   = { 0.45, 0.08, 0.09 }
local PLACEHOLDER_COL = { 0.30, 0.30, 0.32 }
local NAME_DEFAULT    = { 0.95, 0.82, 0.30 }

-- HP threshold markers (50% / 25% / 10%) — same definitions as the hover popup.
local HP_MARKER_DEFS = {
  { pct = 0.50, r = 1.0, g = 1.0,  b = 1.0,  a = 0.35, w = 2 },
  { pct = 0.25, r = 1.0, g = 0.65, b = 0.10, a = 0.45, w = 2 },
  { pct = 0.10, r = 1.0, g = 0.15, b = 0.15, a = 0.55, w = 2 },
}

local BACKDROP_PANEL = {
  bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
  tile = true, tileSize = 24, edgeSize = 16,
  insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
local BACKDROP_CARD = {
  bgFile   = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Buttons\\WHITE8x8",
  edgeSize = 1,
}

-- ── Pure data extraction (testable offline, no WoW frames) ─────────────────────

local function normalizeKey(name)
  if type(name) ~= "string" then return nil end
  local base = name:match("^([^%-]+)") or name
  return base:lower():gsub("%s+", "")
end

-- Resource threshold markers per class/idx — mirrors the hover popup exactly.
local function resMarkerDefs(classKey, idx)
  if classKey == "WARLOCK" and idx == 2 then        -- Corruption (cap 60)
    return {
      { pct = 10/60, r = 0.65, g = 0.95, b = 0.65, a = 0.55, w = 2 },
      { pct = 25/60, r = 1.00, g = 0.82, b = 0.22, a = 0.55, w = 2 },
      { pct = 45/60, r = 1.00, g = 0.25, b = 0.25, a = 0.65, w = 3 },
    }
  elseif classKey == "SHADOWPRIEST" and idx == 2 then  -- Insanité (cap 25)
    return {
      { pct = 4/25,  r = 0.65, g = 0.95, b = 0.65, a = 0.45, w = 2 },
      { pct = 12/25, r = 1.00, g = 0.82, b = 0.22, a = 0.55, w = 2 },
      { pct = 20/25, r = 1.00, g = 0.55, b = 0.10, a = 0.60, w = 2 },
      { pct = 25/25, r = 1.00, g = 0.25, b = 0.25, a = 0.70, w = 3 },
    }
  elseif classKey == "MAGE" and idx == 2 then          -- Charge arcanique (cap 8)
    return {
      { pct = 4/8, r = 1.00, g = 0.82, b = 0.22, a = 0.65, w = 2 },
      { pct = 8/8, r = 0.75, g = 0.30, b = 1.00, a = 0.80, w = 3 },
    }
  end
  return {}
end

local function getDisplayData(name, state)
  if not state then return nil end
  local effMaxHp  = math.max(1, tonumber(state.maxHp) or 0)
  local hp        = tonumber(state.hp) or 0
  local classKey  = type(state.classKey) == "string" and state.classKey or ""
  local resources = {}
  local profile   = Shared.GetResProfile(state)
  for _, p in ipairs(profile) do
    local rk, mk  = Shared.GetKeysForIdx(p.idx)
    local cur     = tonumber(state[rk]) or 0
    local maxv    = tonumber(state[mk]) or 0
    local dispMax = maxv
    if     classKey == "WARLOCK"      and p.idx == 2 then dispMax = 60
    elseif classKey == "SHADOWPRIEST" and p.idx == 2 then dispMax = 25
    elseif classKey == "MAGE"         and p.idx == 2 then dispMax = 8 end
    if dispMax <= 0 then dispMax = 1 end
    resources[#resources + 1] = {
      label   = p.label or "Ressource",
      cur     = math.max(0, math.min(cur, dispMax)),
      max     = dispMax,
      r = p.r, g = p.g, b = p.b,
      markers = resMarkerDefs(classKey, p.idx),
    }
  end

  local style = Shared.CLASS_STYLES and Shared.CLASS_STYLES[classKey]
  local nameColor = style and { style.r, style.g, style.b } or NAME_DEFAULT

  local status = nil
  if hp == 0 then
    status = state.stabilise and "stabilise" or "agonie"
  end

  return {
    name       = name,
    classKey   = classKey,
    classLabel = Shared.GetClassNameFr(classKey),
    nameColor  = nameColor,
    hp         = hp,
    maxHp      = effMaxHp,
    resources  = resources,
    status     = status,
  }
end

local function getRaidMembers()
  -- Read-only lazy lookups (taint-neutral) so test overrides are visible.
  local isInRaid_   = rawget(_G, "IsInRaid")
  local isInGroup_  = rawget(_G, "IsInGroup")
  local unitExists_ = rawget(_G, "UnitExists")
  local unitName_   = rawget(_G, "UnitName")

  local out       = {}
  local isInRaid  = isInRaid_  and isInRaid_()
  local isInGroup = isInGroup_ and isInGroup_()
  if isInRaid then
    for i = 1, 40 do
      local u = "raid" .. i
      if unitExists_ and unitExists_(u) then
        local n = unitName_ and unitName_(u)
        if n then out[#out + 1] = { name = n, unit = u } end
      end
    end
  elseif isInGroup then
    local pn = unitName_ and unitName_("player")
    if pn then out[1] = { name = pn, unit = "player" } end
    for i = 1, 40 do
      local u = "party" .. i
      if unitExists_ and unitExists_(u) then
        local n = unitName_ and unitName_(u)
        if n then out[#out + 1] = { name = n, unit = u } end
      end
    end
  else
    local pn = unitName_ and unitName_("player")
    if pn then out[1] = { name = pn, unit = "player" } end
  end
  return out
end

-- Map an ordered member list to display-data, pulling each state from the cache.
-- Members without a cached state become a { name } placeholder row.
local function collectData(members)
  local list = {}
  for _, m in ipairs(members or {}) do
    local st   = ns.TargetPopup and ns.TargetPopup.GetCachedState(m.name)
    local data = (st and getDisplayData(m.name, st)) or { name = m.name }
    list[#list + 1] = data
  end
  return list
end

-- ── Frame layer (WoW-only; lazily built, sections pooled to avoid leaks) ───────

local frame, scrollFrame, content, headerFs
local sectionPool   = {}
local currentMembers = nil

local function applyBarText(fs)
  fs:SetTextColor(1, 1, 1, 1)
  fs:SetShadowColor(0, 0, 0, 0.95)
  fs:SetShadowOffset(1, -1)
end

-- Reuse marker textures across relayouts (textures can't be destroyed, only hidden).
local function applyMarkers(barObj, defs)
  barObj.markers = barObj.markers or {}
  local m = barObj.markers
  local h = barObj.bar:GetHeight()
  if not h or h <= 0 then h = ROW_H end
  for i, d in ipairs(defs) do
    local t = m[i]
    if not t then
      t = Shared.MakeMarker(barObj.bar, d.pct, d.r, d.g, d.b, d.a, d.w)
      m[i] = t
    else
      t:SetColorTexture(d.r, d.g, d.b, d.a or 0.5)
      t:SetWidth(d.w or 2)
      t.pct = d.pct
    end
    local x = BAR_W * (d.pct or 0)
    if x < 0 then x = 0 elseif x > BAR_W then x = BAR_W end
    t:SetHeight(h)
    t:ClearAllPoints()
    t:SetPoint("LEFT", barObj.bar, "LEFT", x, 0)
    t:Show()
  end
  for i = #defs + 1, #m do m[i]:Hide() end
end

local function hideMarkers(barObj)
  if barObj.markers then
    for i = 1, #barObj.markers do barObj.markers[i]:Hide() end
  end
end

local function makeBar(parent)
  local bf = Shared.MakeBarFrame(parent, BAR_W, ROW_H)
  local label = bf.bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetAllPoints(bf.bar)
  label:SetJustifyH("CENTER")
  label:SetJustifyV("MIDDLE")
  applyBarText(label)
  return { frame = bf.frame, bar = bf.bar, label = label, markers = {} }
end

local function buildSection()
  local sec = CreateFrame("Frame", nil, content, "BackdropTemplate")
  sec:SetWidth(SCROLL_W)
  if sec.SetBackdrop then
    sec:SetBackdrop(BACKDROP_CARD)
    sec:SetBackdropColor(0.10, 0.09, 0.08, 0.85)
    sec:SetBackdropBorderColor(0.45, 0.36, 0.18, 0.80)
  end

  local nameFs = sec:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  nameFs:SetPoint("TOPLEFT",  sec, "TOPLEFT",  CARD_PAD, -CARD_TOP_PAD)
  nameFs:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -CARD_PAD, -CARD_TOP_PAD)
  nameFs:SetHeight(NAME_H)
  nameFs:SetJustifyH("LEFT")
  nameFs:SetShadowColor(0, 0, 0, 0.9)
  nameFs:SetShadowOffset(1, -1)
  sec.nameFs = nameFs

  sec.hp  = makeBar(sec)
  sec.res = {}
  for i = 1, MAX_RES_BARS do
    sec.res[i] = makeBar(sec)
  end

  local statusFs = sec:CreateFontString(nil, "OVERLAY")
  statusFs:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
  statusFs:SetJustifyH("CENTER")
  statusFs:Hide()
  sec.statusFs = statusFs

  return sec
end

local function getSection(i)
  local sec = sectionPool[i]
  if sec then return sec end
  sec = buildSection()
  sectionPool[i] = sec
  return sec
end

-- Fill a pooled section with one member's data; returns its total height.
local function updateSection(sec, data)
  local hasState = data.hp ~= nil
  local col = data.nameColor or NAME_DEFAULT
  sec.nameFs:SetTextColor(col[1], col[2], col[3], 1)
  if data.classLabel and data.classLabel ~= "" then
    sec.nameFs:SetText(string.format("%s  |cffb0a08c— %s|r", data.name or "?", data.classLabel))
  else
    sec.nameFs:SetText(data.name or "?")
  end

  local top = CARD_TOP_PAD + NAME_H + 2

  -- HP bar
  sec.hp.frame:ClearAllPoints()
  sec.hp.frame:SetPoint("TOPLEFT", sec, "TOPLEFT", CARD_PAD, -top)
  if hasState then
    local maxHp = math.max(1, data.maxHp or 1)
    local hp    = math.max(0, math.min(data.hp, maxHp))
    sec.hp.bar:SetMinMaxValues(0, maxHp)
    sec.hp.bar:SetValue(hp)
    local c = (data.hp == 0) and HP_DEAD_COLOR or HP_COLOR
    sec.hp.bar:SetStatusBarColor(c[1], c[2], c[3], 1)
    sec.hp.label:SetText(string.format("PV : %d / %d",
      math.floor(data.hp + 0.5), math.floor(maxHp + 0.5)))
    applyMarkers(sec.hp, HP_MARKER_DEFS)
  else
    sec.hp.bar:SetMinMaxValues(0, 1)
    sec.hp.bar:SetValue(0)
    sec.hp.bar:SetStatusBarColor(PLACEHOLDER_COL[1], PLACEHOLDER_COL[2], PLACEHOLDER_COL[3], 1)
    sec.hp.label:SetText("En attente...")
    hideMarkers(sec.hp)
  end
  sec.hp.frame:Show()
  top = top + ROW_H + ROW_GAP

  -- Resource bars
  local res = data.resources or {}
  for i = 1, MAX_RES_BARS do
    local rb = sec.res[i]
    local r  = hasState and res[i]
    if r then
      rb.frame:ClearAllPoints()
      rb.frame:SetPoint("TOPLEFT", sec, "TOPLEFT", CARD_PAD, -top)
      rb.bar:SetMinMaxValues(0, r.max)
      rb.bar:SetValue(r.cur)
      rb.bar:SetStatusBarColor(r.r, r.g, r.b, 1)
      rb.label:SetText(string.format("%s : %d / %d",
        r.label, math.floor(r.cur + 0.5), math.floor(r.max + 0.5)))
      applyMarkers(rb, r.markers or {})
      rb.frame:Show()
      top = top + ROW_H + ROW_GAP
    else
      rb.frame:Hide()
      hideMarkers(rb)
    end
  end

  -- Status line (only at 0 HP)
  if hasState and data.status then
    sec.statusFs:ClearAllPoints()
    sec.statusFs:SetPoint("TOPLEFT",  sec, "TOPLEFT",  CARD_PAD, -top)
    sec.statusFs:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -CARD_PAD, -top)
    sec.statusFs:SetHeight(STATUS_H)
    if data.status == "stabilise" then
      sec.statusFs:SetText("|cff44ee44** STABILISE **|r")
    else
      sec.statusFs:SetText("|cffee2222** EN AGONIE **|r")
    end
    sec.statusFs:Show()
    top = top + STATUS_H + ROW_GAP
  else
    sec.statusFs:Hide()
  end

  local totalH = top + CARD_BOT_PAD
  sec:SetHeight(totalH)
  return totalH
end

local function layoutSections(dataList)
  if not content then return end
  local y = 0
  for i, data in ipairs(dataList) do
    local sec = getSection(i)
    local h   = updateSection(sec, data)
    sec:ClearAllPoints()
    sec:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    sec:Show()
    y = y + h + SECTION_GAP
  end
  for i = #dataList + 1, #sectionPool do
    sectionPool[i]:Hide()
  end
  content:SetHeight(math.max(y, 1))
  if headerFs then
    headerFs:SetText(string.format("Ressources du Groupe  (%d)", #dataList))
  end
end

local function ensureFrame()
  if frame then return end

  frame = CreateFrame("Frame", "GrosOrteilRaidPanel", UIParent, "BackdropTemplate")
  frame:SetSize(PANEL_W, PANEL_H)
  frame:SetPoint("CENTER")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:SetToplevel(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
  frame:SetScript("OnDragStop",  function(f) f:StopMovingOrSizing() end)
  if frame.SetBackdrop then
    frame:SetBackdrop(BACKDROP_PANEL)
    frame:SetBackdropColor(0.04, 0.04, 0.05, 0.95)
  end
  -- ESC closes it (standard pattern; taint-safe for a non-protected frame).
  local specials = rawget(_G, "UISpecialFrames")
  if type(specials) == "table" then
    table.insert(specials, "GrosOrteilRaidPanel")
  end

  headerFs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  headerFs:SetPoint("TOPLEFT",  frame, "TOPLEFT",  PAD + 2, -PAD)
  headerFs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(PAD + 22), -PAD)
  headerFs:SetHeight(HEADER_H)
  headerFs:SetJustifyH("LEFT")
  headerFs:SetTextColor(0.98, 0.86, 0.36, 1)
  headerFs:SetText("Ressources du Groupe")

  local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  closeBtn:SetSize(28, 28)
  closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(PAD - 4), -(PAD - 4))
  closeBtn:SetScript("OnClick", function() RaidPanel.Hide() end)

  -- Divider under the header
  local divider = frame:CreateTexture(nil, "ARTWORK")
  divider:SetColorTexture(0.55, 0.44, 0.18, 0.55)
  divider:SetHeight(1)
  divider:SetPoint("TOPLEFT",  frame, "TOPLEFT",  PAD, -(PAD + HEADER_H))
  divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(PAD + HEADER_H))

  local scrollH = PANEL_H - PAD - HEADER_H - 6 - PAD
  scrollFrame = CreateFrame("ScrollFrame", "GrosOrteilRaidPanelScroll", frame)
  scrollFrame:SetSize(SCROLL_W, scrollH)
  scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(PAD + HEADER_H + 6))

  content = CreateFrame("Frame", nil, scrollFrame)
  content:SetSize(SCROLL_W, 1)
  scrollFrame:SetScrollChild(content)

  scrollFrame:EnableMouseWheel(true)
  scrollFrame:SetScript("OnMouseWheel", function(sf, delta)
    local cur   = sf:GetVerticalScroll()
    local range = sf:GetVerticalScrollRange()
    local nv    = cur - delta * 30
    if nv < 0 then nv = 0 elseif nv > range then nv = range end
    sf:SetVerticalScroll(nv)
  end)
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

local function relayout()
  if not frame then return end
  layoutSections(collectData(currentMembers))
end

local function Refresh(membersOverride, skipRequest)
  currentMembers = membersOverride or getRaidMembers()
  if not skipRequest and ns.Comm and ns.Comm.RequestState then
    for _, m in ipairs(currentMembers) do
      ns.Comm:RequestState(m.name)
    end
  end
  relayout()
end

-- opts = { members = {...}, skipRequest = bool } | nil
function RaidPanel.Show(opts)
  ensureFrame()
  Refresh(opts and opts.members, opts and opts.skipRequest)
  if scrollFrame then scrollFrame:SetVerticalScroll(0) end
  frame:Show()
  frame:Raise()
end

function RaidPanel.Hide()
  if frame then frame:Hide() end
end

function RaidPanel.Toggle()
  if frame and frame:IsShown() then
    RaidPanel.Hide()
  else
    RaidPanel.Show()
  end
end

function RaidPanel.Init()
  if not ns.TargetPopup or not ns.TargetPopup.OnStateArrived then return end
  ns.TargetPopup.OnStateArrived(function(sender, _)
    if not frame or not frame:IsShown() then return end
    local key = normalizeKey(sender)
    if not key then return end
    for _, m in ipairs(currentMembers or {}) do
      if normalizeKey(m.name) == key then
        relayout()
        return
      end
    end
  end)
end

-- Test handles (pure functions, no WoW frames required)
RaidPanel._getDisplayData = getDisplayData
RaidPanel._getRaidMembers = getRaidMembers
RaidPanel._collectData    = collectData
RaidPanel._resMarkerDefs  = resMarkerDefs
RaidPanel._normalizeKey   = normalizeKey

function ns.RaidPanel_Init()
  RaidPanel.Init()
end
