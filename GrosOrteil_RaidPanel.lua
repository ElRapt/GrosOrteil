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

local PANEL_W      = 360
local PANEL_H      = 580
local EDGE         = 4      -- gold tooltip-border inset around the board
local WOOD         = 20     -- wooden rail thickness (bulletin-board frame)
local PAD          = 8      -- gap between the rails and the cards
local PLAQUE_H     = 30     -- header plaque height
local FOOTER_H     = 14
local CONTENT_X    = EDGE + WOOD + PAD
local SCROLL_W     = PANEL_W - CONTENT_X * 2
local CARD_PAD     = 10
local ACCENT_W     = 3      -- class-colored stripe on the left card edge
local ICON_SIZE    = 16
local BAR_W        = SCROLL_W - CARD_PAD * 2
local ROW_H        = 15
local ROW_GAP      = 3
local NAME_H       = 16
local STATUS_H     = 16
local SECTION_GAP  = 7
local CARD_TOP_PAD = 6
local CARD_BOT_PAD = 7
local MAX_RES_BARS = 5

local HP_COLOR        = { 0.85, 0.16, 0.18 }
local HP_DEAD_COLOR   = { 0.45, 0.08, 0.09 }
local PLACEHOLDER_COL = { 0.30, 0.30, 0.32 }
local NAME_DEFAULT    = { 0.95, 0.82, 0.30 }
local CREAMY_BROWN    = { 0.48, 0.39, 0.32 }   -- TRP3's backdrop border color
local GOLD            = { 1.00, 0.675, 0.125 }
local CARD_BG         = { 0.085, 0.065, 0.045 }
local BORDER_AGONIE   = { 0.78, 0.16, 0.13 }
local BORDER_STAB     = { 0.28, 0.68, 0.30 }

-- TRP3 bulletin-board art, used when TRP3 is installed (this addon already
-- integrates with it); Blizzard's neutral parchment is the fallback.
local TRP3_BG     = "Interface\\AddOns\\totalRP3\\Resources\\UI\\ui-frame-neutral-background"
local TRP3_WOOD_V = "Interface\\AddOns\\totalRP3\\Resources\\UI\\!ui-frame-wooden-border"
local TRP3_WOOD_H = "Interface\\AddOns\\totalRP3\\Resources\\UI\\_ui-frame-wooden-border"
local BLIZZ_BG    = "Interface\\FrameGeneral\\UIFrameNeutralBackground"

-- HP threshold markers (50% / 25% / 10%) — same definitions as the hover popup.
local HP_MARKER_DEFS = {
  { pct = 0.50, r = 1.0, g = 1.0,  b = 1.0,  a = 0.35, w = 2 },
  { pct = 0.25, r = 1.0, g = 0.65, b = 0.10, a = 0.45, w = 2 },
  { pct = 0.10, r = 1.0, g = 0.15, b = 0.15, a = 0.55, w = 2 },
}

local BACKDROP_PANEL = {
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 16,
}
-- Cards are styled as tooltip "notes" pinned on the parchment board.
local BACKDROP_CARD = {
  bgFile   = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 12,
  insets   = { left = 3, right = 3, top = 3, bottom = 3 },
}
local BACKDROP_PLAQUE = {
  bgFile   = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 12,
  insets   = { left = 3, right = 3, top = 3, bottom = 3 },
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

  -- Points de Chance (gold bar, only when the character has a chance pool).
  local chMax   = tonumber(state.maxChance) or 0
  local chance  = nil
  if chMax > 0 then
    local chCur = tonumber(state.chance) or 0
    chance = { cur = math.max(0, math.min(chCur, chMax)), max = chMax }
  end

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
    chance     = chance,
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
    data.unit = m.unit  -- carried for click-to-target (nil for nameless injects)
    list[#list + 1] = data
  end
  return list
end

-- ── Frame layer (WoW-only; lazily built, sections pooled to avoid leaks) ───────

local frame, scrollFrame, content, headerFs, countFs, fadeIn, fadeOut
local sectionPool    = {}
local currentMembers = nil
local pendingRelayout = false  -- a relayout was requested while in combat

local InCombatLockdown = rawget(_G, "InCombatLockdown")
local function inCombat()
  return InCombatLockdown and InCombatLockdown()
end

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

-- Best display name: TRP3/RP name if known, else the character name. Guarded
-- so a missing or erroring RP lib never breaks the layout.
local function resolveDisplayName(name)
  local popup = ns.TargetPopup
  if popup and popup.GetRPDisplayName then
    local ok, rp = pcall(popup.GetRPDisplayName, name)
    if ok and type(rp) == "string" and rp ~= "" then return rp end
  end
  return name
end

-- Right-click context menu: "Soigner" -> heal prompt. Uses MenuUtil when
-- present (modern retail); otherwise falls back straight to the heal prompt.
local function openMemberMenu(sec)
  local name = sec._name
  if not name or name == "" then return end
  local menuUtil = rawget(_G, "MenuUtil")
  if menuUtil and menuUtil.CreateContextMenu then
    menuUtil.CreateContextMenu(sec, function(_, root)
      root:CreateTitle(sec._displayName or name)
      root:CreateButton("Soigner", function()
        if ns.Heal and ns.Heal.PromptAndSend then ns.Heal.PromptAndSend(name) end
      end)
    end)
  elseif ns.Heal and ns.Heal.PromptAndSend then
    ns.Heal.PromptAndSend(name)
  end
end

local function makeBar(parent)
  local bf = Shared.MakeBarFrame(parent, BAR_W, ROW_H)
  -- Top-half sheen for the glass effect used by the main window's bars.
  local sheen = bf.bar:CreateTexture(nil, "OVERLAY", nil, -1)
  sheen:SetTexture("Interface\\Buttons\\WHITE8x8")
  sheen:SetVertexColor(1, 1, 1, 0.06)
  sheen:SetPoint("TOPLEFT",  bf.bar, "TOPLEFT",  1, -1)
  sheen:SetPoint("TOPRIGHT", bf.bar, "TOPRIGHT", -1, -1)
  sheen:SetHeight(math.max(1, math.floor(ROW_H / 2)))
  local label = bf.bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetAllPoints(bf.bar)
  label:SetJustifyH("CENTER")
  label:SetJustifyV("MIDDLE")
  applyBarText(label)
  return { frame = bf.frame, bar = bf.bar, label = label, markers = {} }
end

local function buildSection()
  -- A SecureActionButton so left-click can target the member without tainting
  -- (insecure TargetUnit is blocked by Blizzard). Bars don't enable mouse, so
  -- their clicks fall through to this parent. Right-click opens the action menu.
  local sec = CreateFrame("Button", nil, content, "SecureActionButtonTemplate, BackdropTemplate")
  sec:SetWidth(SCROLL_W)
  if sec.SetBackdrop then
    sec:SetBackdrop(BACKDROP_CARD)
    sec:SetBackdropColor(CARD_BG[1], CARD_BG[2], CARD_BG[3], 0.92)
    sec:SetBackdropBorderColor(CREAMY_BROWN[1], CREAMY_BROWN[2], CREAMY_BROWN[3], 0.90)
  end
  -- Both down and up must be registered: since 10.x, secure action buttons
  -- fire on the edge selected by the ActionButtonUseKeyDown cvar, so an
  -- "AnyUp"-only registration can silently drop the protected target click.
  sec:RegisterForClicks("AnyDown", "AnyUp")
  -- Left-click targets the `unit` attribute. Both plain and wildcard forms are
  -- set so it works with or without held modifiers.
  if sec.SetAttribute then
    sec:SetAttribute("type1", "target")
    sec:SetAttribute("*type1", "target")
  end
  -- Custom right-click menu runs in PostClick — the blessed hook for insecure
  -- work AFTER the secure action. Touching OnClick (HookScript) or any handler
  -- that runs BEFORE it (OnMouseUp) taints the click and Blizzard then blocks
  -- the protected target, which is why earlier attempts silently did nothing.
  -- With both click edges registered, only act on release so it fires once.
  sec:SetScript("PostClick", function(self, button, down)
    if button == "RightButton" and not down then openMemberMenu(self) end
  end)
  sec:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
  local hl = sec.GetHighlightTexture and sec:GetHighlightTexture()
  if hl then hl:SetVertexColor(1.0, 0.95, 0.6, 0.08) end

  -- Class-colored accent stripe along the left card edge.
  local accent = sec:CreateTexture(nil, "BORDER")
  accent:SetTexture("Interface\\Buttons\\WHITE8x8")
  accent:SetPoint("TOPLEFT",    sec, "TOPLEFT",    3, -3)
  accent:SetPoint("BOTTOMLEFT", sec, "BOTTOMLEFT", 3, 3)
  accent:SetWidth(ACCENT_W)
  sec.accent = accent

  -- Class icon in front of the name.
  local icon = sec:CreateTexture(nil, "ARTWORK")
  icon:SetSize(ICON_SIZE, ICON_SIZE)
  icon:SetPoint("TOPLEFT", sec, "TOPLEFT", CARD_PAD, -CARD_TOP_PAD)
  sec.icon = icon

  local nameFs = sec:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  nameFs:SetPoint("TOPLEFT",  icon, "TOPRIGHT", 5, 0)
  nameFs:SetPoint("TOPRIGHT", sec,  "TOPRIGHT", -CARD_PAD, -CARD_TOP_PAD)
  nameFs:SetHeight(NAME_H)
  nameFs:SetJustifyH("LEFT")
  nameFs:SetShadowColor(0, 0, 0, 0.9)
  nameFs:SetShadowOffset(1, -1)
  sec.nameFs = nameFs

  -- Thin class-tinted rule between the name row and the bars.
  local rule = sec:CreateTexture(nil, "ARTWORK")
  rule:SetTexture("Interface\\Buttons\\WHITE8x8")
  rule:SetPoint("TOPLEFT",  sec, "TOPLEFT",  CARD_PAD, -(CARD_TOP_PAD + NAME_H + 1))
  rule:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -CARD_PAD, -(CARD_TOP_PAD + NAME_H + 1))
  rule:SetHeight(1)
  sec.rule = rule

  -- Hover: gold border glow only (no tooltip — the footer carries the hints,
  -- and a tooltip here got in the way of click-to-target).
  sec:SetScript("OnEnter", function(self)
    if self.SetBackdropBorderColor then
      self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
    end
  end)
  sec:SetScript("OnLeave", function(self)
    local c = self._borderColor or CREAMY_BROWN
    if self.SetBackdropBorderColor then
      self:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 0.90)
    end
  end)

  sec.hp  = makeBar(sec)
  sec.res = {}
  for i = 1, MAX_RES_BARS do
    sec.res[i] = makeBar(sec)
  end
  sec.chanceBar = makeBar(sec)

  local statusFs = sec:CreateFontString(nil, "OVERLAY")
  statusFs:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
  statusFs:SetJustifyH("CENTER")
  statusFs:Hide()
  sec.statusFs = statusFs
  -- Soft pulse for the "EN AGONIE" state.
  if statusFs.CreateAnimationGroup then
    local pulse = statusFs:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.7)
    sec.statusPulse = pulse
  end

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
-- Only ever called out of combat (relayout defers otherwise), so the secure
-- SetAttribute is safe.
local function updateSection(sec, data)
  local hasState = data.hp ~= nil
  sec._unit = data.unit
  sec._name = data.name
  local shown = resolveDisplayName(data.name)
  sec._displayName = shown
  if not inCombat() and sec.SetAttribute then
    sec:SetAttribute("unit", data.unit)  -- left-click target
  end

  local col = data.nameColor or NAME_DEFAULT
  sec.nameFs:SetTextColor(col[1], col[2], col[3], 1)
  if data.classLabel and data.classLabel ~= "" then
    sec.nameFs:SetText(string.format("%s  |cffb0a08c— %s|r", shown or "?", data.classLabel))
  else
    sec.nameFs:SetText(shown or "?")
  end

  -- Class crest (question mark while waiting for data).
  if hasState and data.classKey and data.classKey ~= "" then
    Shared.SetClassEmblem(sec.icon, data.classKey)
    if sec.icon.SetDesaturated then sec.icon:SetDesaturated(false) end
  else
    sec.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    sec.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if sec.icon.SetDesaturated then sec.icon:SetDesaturated(true) end
  end

  -- Accent stripe + border follow the member's condition.
  local accentCol, borderCol = col, CREAMY_BROWN
  if not hasState then
    accentCol = PLACEHOLDER_COL
  elseif data.status == "agonie" then
    accentCol, borderCol = BORDER_AGONIE, BORDER_AGONIE
  elseif data.status == "stabilise" then
    accentCol, borderCol = BORDER_STAB, BORDER_STAB
  end
  sec._borderColor = borderCol
  sec.accent:SetVertexColor(accentCol[1], accentCol[2], accentCol[3], 0.90)
  sec.rule:SetVertexColor(col[1], col[2], col[3], hasState and 0.30 or 0.12)
  if sec.SetBackdropBorderColor and not (sec.IsMouseOver and sec:IsMouseOver()) then
    sec:SetBackdropBorderColor(borderCol[1], borderCol[2], borderCol[3], 0.90)
  end
  sec:SetAlpha(hasState and 1 or 0.65)

  local top = CARD_TOP_PAD + NAME_H + 5

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
    sec.hp.label:SetText(string.format("PV : %d / %d  (%d%%)",
      math.floor(data.hp + 0.5), math.floor(maxHp + 0.5), Shared.RoundPct(hp / maxHp)))
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

  -- Points de Chance (gold), shown only when the member has a chance pool.
  if hasState and data.chance then
    local cb = sec.chanceBar
    cb.frame:ClearAllPoints()
    cb.frame:SetPoint("TOPLEFT", sec, "TOPLEFT", CARD_PAD, -top)
    cb.bar:SetMinMaxValues(0, data.chance.max)
    cb.bar:SetValue(data.chance.cur)
    cb.bar:SetStatusBarColor(0.95, 0.78, 0.20, 1)
    cb.label:SetText(string.format("PC : %d / %d",
      math.floor(data.chance.cur + 0.5), math.floor(data.chance.max + 0.5)))
    hideMarkers(cb)
    cb.frame:Show()
    top = top + ROW_H + ROW_GAP
  else
    sec.chanceBar.frame:Hide()
    hideMarkers(sec.chanceBar)
  end

  -- Status line (only at 0 HP); "EN AGONIE" pulses softly.
  if hasState and data.status then
    sec.statusFs:ClearAllPoints()
    sec.statusFs:SetPoint("TOPLEFT",  sec, "TOPLEFT",  CARD_PAD, -top)
    sec.statusFs:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -CARD_PAD, -top)
    sec.statusFs:SetHeight(STATUS_H)
    if data.status == "stabilise" then
      sec.statusFs:SetText("|cff44ee44** STABILISE **|r")
      if sec.statusPulse then sec.statusPulse:Stop() end
    else
      sec.statusFs:SetText("|cffee2222** EN AGONIE **|r")
      if sec.statusPulse and not sec.statusPulse:IsPlaying() then sec.statusPulse:Play() end
    end
    sec.statusFs:Show()
    top = top + STATUS_H + ROW_GAP
  else
    if sec.statusPulse then sec.statusPulse:Stop() end
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
  if countFs then
    countFs:SetText(#dataList == 1 and "1 membre" or (#dataList .. " membres"))
  end
end

local function ensureFrame()
  if frame then return end

  -- TRP3's bulletin-board art when TRP3 is around (this addon already
  -- integrates with it); plain warm rails otherwise.
  local hasTRP3 = rawget(_G, "TRP3_API") ~= nil

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
    frame:SetBackdropBorderColor(CREAMY_BROWN[1], CREAMY_BROWN[2], CREAMY_BROWN[3], 1)
  end

  -- Tiled parchment board behind everything (TRP3 tints it 0.6 grey).
  local board = frame:CreateTexture(nil, "BACKGROUND")
  board:SetTexture(hasTRP3 and TRP3_BG or BLIZZ_BG, "REPEAT", "REPEAT")
  board:SetHorizTile(true)
  board:SetVertTile(true)
  board:SetPoint("TOPLEFT",     frame, "TOPLEFT",     EDGE, -EDGE)
  board:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -EDGE, EDGE)
  board:SetVertexColor(0.60, 0.60, 0.60)

  -- Wooden rails around the board, like TRP3's main frame.
  if hasTRP3 then
    local function woodV(point, xOfs, flip)
      local t = frame:CreateTexture(nil, "BORDER", nil, -3)
      t:SetTexture(TRP3_WOOD_V, "REPEAT", "REPEAT")
      t:SetVertTile(true)
      t:SetWidth(WOOD)
      t:SetPoint("TOP" .. point,    frame, "TOP" .. point,    xOfs, -EDGE)
      t:SetPoint("BOTTOM" .. point, frame, "BOTTOM" .. point, xOfs, EDGE)
      if flip then t:SetTexCoord(0.2265625, 0.0078125, 0, 1)
      else         t:SetTexCoord(0.0078125, 0.2265625, 0, 1) end
      t:SetVertexColor(1, 0.8, 0.8)
    end
    local function woodH(point, yOfs, top, bottom)
      local t = frame:CreateTexture(nil, "BORDER", nil, -2)
      t:SetTexture(TRP3_WOOD_H, "REPEAT", "REPEAT")
      t:SetHorizTile(true)
      t:SetHeight(WOOD)
      t:SetPoint(point .. "LEFT",  frame, point .. "LEFT",  EDGE, yOfs)
      t:SetPoint(point .. "RIGHT", frame, point .. "RIGHT", -EDGE, yOfs)
      t:SetTexCoord(0, 1, top, bottom)
      t:SetVertexColor(1, 0.8, 0.8)
    end
    woodV("LEFT",  EDGE, false)
    woodV("RIGHT", -EDGE, true)
    woodH("TOP",    -EDGE, 0.484375, 0.921875)
    woodH("BOTTOM", EDGE,  0.015625, 0.453125)
  else
    local function plainRail()
      local t = frame:CreateTexture(nil, "BORDER", nil, -2)
      t:SetColorTexture(0.23, 0.16, 0.10, 1)
      return t
    end
    local left, right, topT, botT = plainRail(), plainRail(), plainRail(), plainRail()
    left:SetPoint("TOPLEFT", EDGE, -EDGE);  left:SetPoint("BOTTOMLEFT", EDGE, EDGE);   left:SetWidth(WOOD)
    right:SetPoint("TOPRIGHT", -EDGE, -EDGE); right:SetPoint("BOTTOMRIGHT", -EDGE, EDGE); right:SetWidth(WOOD)
    topT:SetPoint("TOPLEFT", EDGE, -EDGE);  topT:SetPoint("TOPRIGHT", -EDGE, -EDGE);   topT:SetHeight(WOOD)
    botT:SetPoint("BOTTOMLEFT", EDGE, EDGE); botT:SetPoint("BOTTOMRIGHT", -EDGE, EDGE); botT:SetHeight(WOOD)
  end

  -- ESC closes it (standard pattern; taint-safe for a non-protected frame).
  local specials = rawget(_G, "UISpecialFrames")
  if type(specials) == "table" then
    table.insert(specials, "GrosOrteilRaidPanel")
  end

  -- Header plaque: a dark tooltip-style nameplate pinned over the top rail.
  local plaque = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  plaque:SetPoint("TOPLEFT",  frame, "TOPLEFT",  EDGE + 8, -(EDGE + 6))
  plaque:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(EDGE + 8), -(EDGE + 6))
  plaque:SetHeight(PLAQUE_H)
  if plaque.SetBackdrop then
    plaque:SetBackdrop(BACKDROP_PLAQUE)
    plaque:SetBackdropColor(0.10, 0.075, 0.05, 0.97)
    plaque:SetBackdropBorderColor(CREAMY_BROWN[1], CREAMY_BROWN[2], CREAMY_BROWN[3], 1)
  end

  headerFs = plaque:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  headerFs:SetPoint("LEFT",  plaque, "LEFT",  10, 0)
  headerFs:SetJustifyH("LEFT")
  headerFs:SetTextColor(1.00, 0.84, 0.30, 1)
  headerFs:SetShadowColor(0, 0, 0, 0.8)
  headerFs:SetShadowOffset(1, -1)
  headerFs:SetText("Ressources du Groupe")

  local closeBtn = CreateFrame("Button", nil, plaque, "UIPanelCloseButton")
  closeBtn:SetSize(24, 24)
  closeBtn:SetPoint("RIGHT", plaque, "RIGHT", -2, 0)
  closeBtn:SetScript("OnClick", function() RaidPanel.Hide() end)

  countFs = plaque:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  countFs:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
  countFs:SetJustifyH("RIGHT")
  countFs:SetTextColor(0.78, 0.66, 0.46, 1)
  countFs:SetText("")

  -- Footer hint just above the bottom rail.
  local hintFs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hintFs:SetPoint("BOTTOM", frame, "BOTTOM", 0, EDGE + WOOD + 3)
  hintFs:SetHeight(FOOTER_H)
  hintFs:SetTextColor(0.42, 0.34, 0.25, 1)
  hintFs:SetText("Clic gauche : cibler  —  Clic droit : actions")

  local scrollTop = EDGE + 6 + PLAQUE_H + PAD
  local scrollBot = EDGE + WOOD + 3 + FOOTER_H + 4
  local scrollH   = PANEL_H - scrollTop - scrollBot
  scrollFrame = CreateFrame("ScrollFrame", "GrosOrteilRaidPanelScroll", frame)
  scrollFrame:SetSize(SCROLL_W, scrollH)
  scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", CONTENT_X, -scrollTop)

  content = CreateFrame("Frame", nil, scrollFrame)
  content:SetSize(SCROLL_W, 1)
  scrollFrame:SetScrollChild(content)

  -- Slim scroll indicator in the gap between the cards and the right rail.
  local rail = frame:CreateTexture(nil, "ARTWORK")
  rail:SetColorTexture(0, 0, 0, 0.20)
  rail:SetWidth(3)
  rail:SetPoint("TOPRIGHT",    frame, "TOPRIGHT", -(EDGE + WOOD + 2), -scrollTop)
  rail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(EDGE + WOOD + 2), scrollBot)
  rail:Hide()
  local thumb = frame:CreateTexture(nil, "ARTWORK", nil, 1)
  thumb:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.55)
  thumb:SetWidth(3)
  thumb:Hide()

  local function updateScrollThumb()
    local range = scrollFrame:GetVerticalScrollRange() or 0
    if range <= 0 then rail:Hide(); thumb:Hide(); return end
    rail:Show(); thumb:Show()
    local h      = scrollFrame:GetHeight() or 1
    local thumbH = math.max(24, h * h / (h + range))
    local ofs    = (h - thumbH) * ((scrollFrame:GetVerticalScroll() or 0) / range)
    thumb:SetHeight(thumbH)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", rail, "TOPRIGHT", 0, -ofs)
  end

  scrollFrame:EnableMouseWheel(true)
  scrollFrame:SetScript("OnMouseWheel", function(sf, delta)
    local cur   = sf:GetVerticalScroll()
    local range = sf:GetVerticalScrollRange()
    local nv    = cur - delta * 30
    if nv < 0 then nv = 0 elseif nv > range then nv = range end
    sf:SetVerticalScroll(nv)
    updateScrollThumb()
  end)
  scrollFrame:SetScript("OnScrollRangeChanged", updateScrollThumb)
  scrollFrame:SetScript("OnVerticalScroll", updateScrollThumb)

  -- Gentle fade-in when the panel opens, fade-out when it closes.
  if frame.CreateAnimationGroup then
    fadeIn = frame:CreateAnimationGroup()
    local a = fadeIn:CreateAnimation("Alpha")
    a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.18)
  end
  fadeOut = Shared.MakeFadeOut(frame, 0.15)

  -- Secure section buttons can't be moved/shown/re-attributed in combat, so a
  -- relayout requested during combat is deferred until combat ends.
  frame:RegisterEvent("PLAYER_REGEN_ENABLED")
  frame:SetScript("OnEvent", function()
    if pendingRelayout and frame:IsShown() then
      pendingRelayout = false
      layoutSections(collectData(currentMembers))
    end
  end)
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

local function relayout()
  if not frame then return end
  if inCombat() then pendingRelayout = true; return end
  layoutSections(collectData(currentMembers))
end

local function Refresh()
  currentMembers = getRaidMembers()
  -- Fire-and-forget fresh requests; replies refresh rows via OnStateArrived.
  if ns.Comm and ns.Comm.RequestState then
    for _, m in ipairs(currentMembers) do
      ns.Comm:RequestState(m.name)
    end
  end
  relayout()
end

function RaidPanel.Show()
  ensureFrame()
  if fadeOut then fadeOut:Stop() end  -- cancel a pending close fade
  Refresh()
  if scrollFrame then scrollFrame:SetVerticalScroll(0) end
  frame:Show()
  frame:Raise()
  if fadeIn then fadeIn:Play() end
end

function RaidPanel.Hide()
  if not frame then return end
  if fadeOut and frame:IsShown() and not fadeOut:IsPlaying() then
    fadeOut:Play()
  else
    frame:Hide()
  end
end

function RaidPanel.Toggle()
  -- A panel mid-fade-out counts as hidden, so toggling reopens it.
  if frame and frame:IsShown() and not (fadeOut and fadeOut:IsPlaying()) then
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
