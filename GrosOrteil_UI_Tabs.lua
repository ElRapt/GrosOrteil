---@diagnostic disable: undefined-global
-- GrosOrteil/UI_Tabs.lua
-- Per-tab builder functions extracted from UI_Init.
-- Each builder receives a `ctx` table with all needed upvalues and writes results
-- into the ctx or directly into the ns.UI (UI) table.
local _, ns = ...

-- ── Tab 1 (Fiche) ───────────────────────────────────────────────────────────
-- ctx fields used: page (pageHP), C, TEX, Core, mkLabel, mkLabelCenter, mkEdit,
--   mkButton, mkRowAnchor, getNumber, setNumber, CONTENT_W, BLOCK_W,
--   applyResTextColor (unused here), positionMarkers, hideMarkers,
--   setEditBoxEnabled, setButtonEnabled, roundPct, getResProfile, getKeysForIdx
-- ctx fields written: inputs (returned), resRow/Label/Cur/Max (via UI.*),
--   noResHint (via UI), postureButtons (via UI), manaShieldToggleBtn (via UI), etc.
function ns.UI_BuildFicheTab(ctx)
  local UI = ns.UI
  local page        = ctx.page
  local C           = ctx.C
  local TEX         = ctx.TEX
  local Core        = ctx.Core
  local mkLabel     = ctx.mkLabel
  local mkLabelCenter = ctx.mkLabelCenter
  local mkEdit      = ctx.mkEdit
  local mkButton    = ctx.mkButton
  local mkRowAnchor = ctx.mkRowAnchor
  local getNumber   = ctx.getNumber
  local BLOCK_W     = ctx.BLOCK_W

  -- Forward-declared widget refs (returned via ctx.inputs at end).
  local hpCur, hpMax
  local armorEB, trueArmorEB, tempArmorEB, dodgeEB, blockEB
  local msHpEB, msMaxHpEB, msArmorEB
  local mnsArmorEB, mnsToggleBtn, mnsLabel, mnsArmorLabel
  local actValEB
  local attaqueMeleeEB, attaqueDistanceEB, chanceCurEB, chanceMaxEB, perceptionEB

  local function applyAllHP()
    Core.SetHP(ctx.getNumber(hpCur), ctx.getNumber(hpMax))
  end
  local function applyAllArmor()
    local vArmor     = ctx.getNumber(armorEB)
    local vTrueArmor = ctx.getNumber(trueArmorEB)
    local vTempArmor = ctx.getNumber(tempArmorEB)
    local vDodge     = ctx.getNumber(dodgeEB)
    local vBlock     = ctx.getNumber(blockEB)
    Core.SetArmor(vArmor, vTrueArmor)
    Core.SetTempArmor(vTempArmor)
    Core.SetDodge(vDodge)
    Core.SetTempBlock(vBlock)
  end
  local function applyAllAttaque()
    if Core and Core.SetAttaque then
      local vMelee = ctx.getNumber(attaqueMeleeEB)
      local vDist  = ctx.getNumber(attaqueDistanceEB)
      Core.SetAttaque(vMelee, vDist)
    end
  end
  local function applyAllChance()
    if Core and Core.SetChance then
      local vCur = ctx.getNumber(chanceCurEB)
      local vMax = ctx.getNumber(chanceMaxEB)
      Core.SetChance(vCur, vMax)
    end
  end
  local function applyAllPerception()
    if Core and Core.SetPerception then Core.SetPerception(ctx.getNumber(perceptionEB)) end
  end
  local function applyAllMagicShield()
    local vHp    = ctx.getNumber(msHpEB)
    local vMaxHp = ctx.getNumber(msMaxHpEB)
    local vArmor = ctx.getNumber(msArmorEB)
    Core.SetMagicShield(vHp, vMaxHp, vArmor)
  end
  local function applyAllManaShield()
    Core.SetManaShieldArmor(ctx.getNumber(mnsArmorEB))
  end
  local function doDmgArmor() Core.DamageWithArmor(ctx.getNumber(actValEB) or 0) end
  local function doDmgTrue()  Core.DamageTrue(ctx.getNumber(actValEB) or 0) end
  local function doHeal()     Core.Heal(ctx.getNumber(actValEB) or 0) end

  -- Scroll frame
  local paramSF = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
  paramSF:SetPoint("TOPLEFT",     page, "TOPLEFT",     0,   0)
  paramSF:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -20, 0)
  local paramChild = CreateFrame("Frame", nil, paramSF)
  paramChild:SetHeight(680)
  paramSF:SetScrollChild(paramChild)
  local cA = CreateFrame("Frame", nil, paramChild)
  cA:SetSize(BLOCK_W, 1)

  -- Resource rows (merged Tab 2)
  UI.resRow      = UI.resRow      or {}
  UI.resRowLabel = UI.resRowLabel or {}
  UI.resRowCur   = UI.resRowCur   or {}
  UI.resRowMax   = UI.resRowMax   or {}

  local function applyAllRes()
    local snapshots = {}
    for i = 1, 5 do
      local row = UI.resRow[i]
      if row and row:IsShown() then
        snapshots[#snapshots + 1] = {
          idx = row.resIdx or i,
          cur = ctx.getNumber(UI.resRowCur[i]),
          max = ctx.getNumber(UI.resRowMax[i]),
        }
      end
    end
    for _, v in ipairs(snapshots) do
      if Core and Core.SetResIndex then Core.SetResIndex(v.idx, v.cur, v.max) end
    end
  end

  local function mkResRow(idx, y)
    local row = CreateFrame("Frame", nil, cA)
    row:SetSize(354, 24)
    row:SetPoint("TOPLEFT", cA, "TOPLEFT", 43, y)
    row.resIdx = idx
    UI.resRow[idx] = row
    row:Hide()
    local label = mkLabel(row, "Ressource", 0, 0)
    UI.resRowLabel[idx] = label
    mkLabel(row, "/", 196, 0)
    local curEB = mkEdit(row, 70, 20, 120, 2, applyAllRes)
    local maxEB = mkEdit(row, 70, 20, 210, 2, applyAllRes)
    UI.resRowCur[idx] = curEB
    UI.resRowMax[idx] = maxEB
    mkButton(row, "+", 28, 20, 294, 2, function()
      if Core and Core.AddResIndex then Core.AddResIndex(row.resIdx or idx, 1) end
    end)
    mkButton(row, "-", 28, 20, 326, 2, function()
      if Core and Core.AddResIndex then Core.AddResIndex(row.resIdx or idx, -1) end
    end)
    return row
  end

  mkResRow(1, -836); mkResRow(2, -864); mkResRow(3, -892); mkResRow(4, -920); mkResRow(5, -948)
  UI.noResHint = mkLabelCenter(cA, "Aucune ressource pour cette classe.", 0, -862)
  UI.noResHint:Hide()

  -- Main Fiche content
  do
    local INPUT_H = 22
    local BTN_H   = 26
    local LBL_Y   = -2

    local function centerContent()
      local w = paramChild:GetWidth() or 0
      if w <= 0 then return end
      local x = math.max(8, math.floor((w - BLOCK_W) / 2))
      cA:ClearAllPoints()
      cA:SetPoint("TOPLEFT", paramChild, "TOPLEFT", x, 0)
    end
    local function syncParamWidth()
      local w = paramSF:GetWidth() or 0
      if w <= 0 then return end
      paramChild:SetWidth(math.max(200, math.floor(w - 20)))
    end
    paramSF:SetScript("OnSizeChanged", syncParamWidth)
    paramChild:SetScript("OnSizeChanged", centerContent)

    local function mkSectionHeader(text, y)
      local lbl = cA:CreateFontString(nil, "OVERLAY")
      lbl:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
      lbl:SetPoint("TOP", cA, "TOP", 0, y)
      lbl:SetWidth(BLOCK_W)
      lbl:SetJustifyH("CENTER")
      lbl:SetTextColor(C.TEXT_TITLE[1], C.TEXT_TITLE[2], C.TEXT_TITLE[3], 1)
      lbl:SetShadowOffset(1, -1)
      lbl:SetShadowColor(0, 0, 0, 0.60)
      lbl:SetText(text)
      local ul = cA:CreateTexture(nil, "ARTWORK")
      ul:SetTexture(TEX.FLAT)
      ul:SetPoint("TOPLEFT",  cA, "TOPLEFT",  0, y - 18)
      ul:SetPoint("TOPRIGHT", cA, "TOPRIGHT", 0, y - 18)
      ul:SetHeight(1)
      ul:SetColorTexture(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.40)
    end
    local function mkSep(y)
      local sep = paramChild:CreateTexture(nil, "ARTWORK")
      sep:SetTexture(TEX.FLAT)
      sep:SetPoint("TOPLEFT",  paramChild, "TOPLEFT",  16, y)
      sep:SetPoint("TOPRIGHT", paramChild, "TOPRIGHT", -16, y)
      sep:SetHeight(1)
      sep:SetColorTexture(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.16)
    end

    local function lbl(text, x, y)       mkLabel(cA, text, x, y + LBL_Y) end
    local function edt(w, x, y, fn)      return mkEdit(cA, w, INPUT_H, x, y, fn) end
    local function btn(text, w, x, y, fn) return mkButton(cA, text, w, BTN_H, x, y, fn) end
    local function smallBtn(text, w, x, y, fn) return mkButton(cA, text, w, INPUT_H, x, y, fn) end

    -- Points de vie
    mkSectionHeader("Points de vie", -10)
    lbl("PV", 0, -38); lbl("/", 148, -38)
    hpCur = edt(110, 26,  -36, applyAllHP)
    hpMax = edt(110, 166, -36, applyAllHP)
    UI.stabiliseBtn = btn("Stabilisé", 330, 55, -106, function()
      if Core and Core.SetStabilise and Core.state then
        Core.SetStabilise(not Core.state.stabilise)
      end
    end)
    UI.stabiliseBtn:Hide()
    lbl("PC", 0, -72)
    chanceCurEB = edt(48, 26, -70, applyAllChance); lbl("/", 80, -72)
    chanceMaxEB = edt(48, 92, -70, applyAllChance)
    smallBtn("-", 22, 148, -70, function() if Core and Core.AddChance then Core.AddChance(-1) end end)
    smallBtn("+", 22, 174, -70, function() if Core and Core.AddChance then Core.AddChance(1)  end end)
    mkSep(-178)

    -- Armure & Esquive
    mkSectionHeader("Armure & Esquive", -190)
    lbl("Armure", 0, -216); lbl("Armure invul", 190, -216)
    armorEB     = edt(110, 66,  -214, applyAllArmor)
    trueArmorEB = edt(110, 284, -214, applyAllArmor)
    lbl("Esquive", 0, -250); lbl("Armure tempo.", 190, -250)
    dodgeEB     = edt(110, 66,  -248, applyAllArmor)
    tempArmorEB = edt(110, 284, -248, applyAllArmor)
    mkSep(-284)

    -- Attaque & Perception
    mkSectionHeader("Attaque & Perception", -296)
    lbl("CaC", 0, -322); lbl("Distance", 190, -322)
    attaqueMeleeEB    = edt(110, 66,  -320, applyAllAttaque)
    attaqueDistanceEB = edt(110, 284, -320, applyAllAttaque)
    lbl("Perception", 0, -356)
    perceptionEB = edt(110, 66, -354, applyAllPerception)
    mkSep(-390)

    -- Actions
    mkSectionHeader("Actions", -402)
    lbl("Valeur", 0, -430)
    actValEB = edt(120, 60, -428, nil)
    btn("Dégâts (armure)", 210, 0,   -462, doDmgArmor)
    btn("Dégâts (bruts)",  210, 230, -462, doDmgTrue)
    btn("Soins",              210, 0,   -500, doHeal)
    btn("Soins divins (75%)", 210, 230, -500, function() Core.DivineHeal() end)
    btn("Chirurgie (50%)",    210, 0,   -538, function() Core.Surgery() end)
    mkSep(-580)

    -- Blocage
    mkSectionHeader("Blocage", -592)
    lbl("Blocage", 0, -618)
    blockEB = edt(110, 162, -616, applyAllArmor)
    btn("Réinit.", 100, 284, -616, function() Core.ResetTempBlock() end)
    mkSep(-652)

    -- Boucliers magiques
    mkSectionHeader("Boucliers magiques", -664)
    lbl("PV", 0, -690); lbl("/", 148, -690)
    msHpEB    = edt(110, 26,  -688, applyAllMagicShield)
    msMaxHpEB = edt(110, 166, -688, applyAllMagicShield)
    btn("Réinit.", 100, 284, -688, function()
      if Core and Core.ResetMagicShield then Core.ResetMagicShield() end
    end)
    lbl("Armure", 0, -722)
    msArmorEB = edt(110, 162, -720, applyAllMagicShield)
    mnsToggleBtn = btn("Activer bouclier de mana", 240, 0, -756, function()
      if Core and Core.ToggleManaShield then Core.ToggleManaShield() end
    end)
    UI.manaShieldToggleBtn = mnsToggleBtn
    mnsArmorLabel = mkLabel(cA, "Armure", 250, -756 + LBL_Y)
    UI.manaShieldArmorLabel = mnsArmorLabel
    mnsArmorEB = edt(80, 304, -756, applyAllManaShield)
    UI.manaShieldArmorEB = mnsArmorEB
    mnsToggleBtn:Hide(); mnsArmorLabel:Hide()
    if mnsArmorEB._wrap then mnsArmorEB._wrap:Hide() else mnsArmorEB:Hide() end
    mkSep(-792)

    -- Ressources header (rows pre-built above)
    mkSectionHeader("Ressources", -804)

    -- Postures Élémentaires (Shaman uniquement)
    do
      local POSTURE_DEFS = {
        { key = "TERRE", label = "Terre", r = 0.55, g = 0.35, b = 0.15,
          tip = "Posture de Terre",
          desc = "+5 armure\n+20 PV maximum\n+4 points de terre\n\nRequiert : 3 points de terre" },
        { key = "AIR",   label = "Air",   r = 0.60, g = 0.95, b = 0.95,
          tip = "Posture de l'Air",
          desc = "+15 esquive\n+4 points d'air\n\nRequiert : 3 points d'air" },
        { key = "EAU",   label = "Eau",   r = 0.20, g = 0.55, b = 1.00,
          tip = "Posture de l'Eau",
          desc = "+8 points d'eau\n\nRequiert : 3 points d'eau" },
        { key = "FEU",   label = "Feu",   r = 1.00, g = 0.35, b = 0.10,
          tip = "Posture de Feu",
          desc = "Armure réduite à 0\nDégâts reçus +10\n+4 points de feu\n\nRequiert : 3 points de feu" },
      }
      local postureSection = cA:CreateFontString(nil, "OVERLAY")
      postureSection:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
      postureSection:SetPoint("TOP", cA, "TOP", 0, -986)
      postureSection:SetWidth(BLOCK_W)
      postureSection:SetJustifyH("CENTER")
      postureSection:SetTextColor(C.TEXT_TITLE[1], C.TEXT_TITLE[2], C.TEXT_TITLE[3], 1)
      postureSection:SetShadowOffset(1, -1); postureSection:SetShadowColor(0, 0, 0, 0.60)
      postureSection:SetText("Postures Élémentaires")
      UI.postureSectionLabel = postureSection

      local postureSepLine = cA:CreateTexture(nil, "ARTWORK")
      postureSepLine:SetTexture(TEX.FLAT)
      postureSepLine:SetPoint("TOPLEFT",  cA, "TOPLEFT",  0, -1004)
      postureSepLine:SetPoint("TOPRIGHT", cA, "TOPRIGHT", 0, -1004)
      postureSepLine:SetHeight(1)
      postureSepLine:SetColorTexture(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.40)
      UI.postureSepLine = postureSepLine

      UI.postureButtons = {}
      local BTN_W = 98; local BTN_H2 = 26; local GAP = 6
      local totalW = 4 * BTN_W + 3 * GAP
      local startX = math.floor((BLOCK_W - totalW) / 2)
      for i, def in ipairs(POSTURE_DEFS) do
        local bx = startX + (i - 1) * (BTN_W + GAP)
        local b = mkButton(cA, def.label, BTN_W, BTN_H2, bx, -1014)
        b._postureKey = def.key
        b._postureR, b._postureG, b._postureB = def.r, def.g, def.b
        local tipTitle, tipDesc = def.tip, def.desc
        b:SetScript("OnEnter", function(self)
          GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:ClearLines()
          GameTooltip:AddLine(tipTitle, C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3])
          GameTooltip:AddLine(tipDesc, 1, 1, 1, true); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function()
          if Core and Core.SetShamanPosture then Core.SetShamanPosture(def.key) end
        end)
        UI.postureButtons[i] = b
      end
    end

    paramChild:SetHeight(1078)
  end

  -- Write widget refs into ctx.inputs
  ctx.inputs = {
    hpCur = hpCur, hpMax = hpMax,
    armor = armorEB, trueArmor = trueArmorEB, tempArmor = tempArmorEB,
    dodge = dodgeEB, block = blockEB,
    msHp = msHpEB, msMaxHp = msMaxHpEB, msArmor = msArmorEB,
    mnsArmor = mnsArmorEB,
    attaqueMelee = attaqueMeleeEB, attaqueDistance = attaqueDistanceEB,
    chanceCur = chanceCurEB, chanceMax = chanceMaxEB,
    perception = perceptionEB,
  }
end

-- ── Tab 6 (Classes) ─────────────────────────────────────────────────────────
-- ctx fields used: page (pageClasses), C, TEX, Core, Shared, mkRowAnchor,
--   mkButton, lastStateRef, setClassIconTexCoords
function ns.UI_BuildClassesTab(ctx)
  local UI     = ns.UI
  local Shared = ns.Shared
  local page          = ctx.page
  local C             = ctx.C
  local TEX           = ctx.TEX
  local Core          = ctx.Core
  local mkRowAnchor   = ctx.mkRowAnchor
  local mkButton      = ctx.mkButton
  local lastStateRef  = ctx.lastStateRef  -- { v = lastState }
  local setClassIconTexCoords = ctx.setClassIconTexCoords

  local CLASS_BTN_SIZE = 60; local CLASS_BTN_GAP_X = 8; local CLASS_BTN_GAP_Y = 8
  local classStrip = CreateFrame("Frame", nil, page)
  classStrip:SetPoint("TOPLEFT",  page, "TOPLEFT",  0, -20)
  classStrip:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -20)
  classStrip:SetHeight((CLASS_BTN_SIZE * 2) + CLASS_BTN_GAP_Y)
  UI.classStrip = classStrip

  UI.classButtons = {}
  local CLASS_KEYS = {
    "WARRIOR","MEDIC","PALADIN","PRIEST","SHADOWPRIEST","MAGE",
    "ROGUE","WARLOCK","DRUID","MONK","SHAMAN",
  }

  local classBtnPerRow = math.ceil(#CLASS_KEYS / 2)
  local classRow2Count = #CLASS_KEYS - classBtnPerRow
  local classRow1W = (classBtnPerRow * CLASS_BTN_SIZE) + ((classBtnPerRow - 1) * CLASS_BTN_GAP_X)
  local classRow2W = (classRow2Count * CLASS_BTN_SIZE) + ((classRow2Count - 1) * CLASS_BTN_GAP_X)
  local aClassRow1 = mkRowAnchor(classStrip, classRow1W, 0)
  local aClassRow2 = mkRowAnchor(classStrip, classRow2W, -(CLASS_BTN_SIZE + CLASS_BTN_GAP_Y))

  local function mkClassButton(idx, classKey)
    local b = CreateFrame("Button", nil, classStrip, "BackdropTemplate")
    b:SetSize(CLASS_BTN_SIZE, CLASS_BTN_SIZE)
    b.classKey = classKey
    b:SetBackdrop({ edgeFile = TEX.FLAT, edgeSize = 2,
                    insets = { left = 0, right = 0, top = 0, bottom = 0 } })
    b:SetBackdropBorderColor(0.08, 0.06, 0.02, 0.90)

    local row = (idx <= classBtnPerRow) and 1 or 2
    local idxInRow = (row == 1) and idx or (idx - classBtnPerRow)
    local anchor = (row == 1) and aClassRow1 or aClassRow2
    local x = (idxInRow - 1) * (CLASS_BTN_SIZE + CLASS_BTN_GAP_X)
    b:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, 0)

    local iconBg = b:CreateTexture(nil, "BACKGROUND")
    iconBg:SetPoint("TOPLEFT", 2, -2); iconBg:SetPoint("BOTTOMRIGHT", -2, 2)
    iconBg:SetTexture(TEX.FLAT); iconBg:SetColorTexture(0.04, 0.03, 0.01, 1)

    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
    tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b.tex = tex
    setClassIconTexCoords(tex, classKey)

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 2, -2); hl:SetPoint("BOTTOMRIGHT", -2, 2)
    hl:SetTexture(TEX.FLAT); hl:SetColorTexture(1, 1, 1, 0.15)

    b:SetScript("OnClick", function()
      if Core and Core.SetClassKey then Core.SetClassKey(classKey) end
    end)
    b:SetScript("OnEnter", function(self)
      b:SetBackdropBorderColor(C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3], 1.0)
      local name = (Shared.CLASS_NAMES_FR and Shared.CLASS_NAMES_FR[classKey]) or classKey
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:ClearLines()
      GameTooltip:AddLine(name, C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3])
      local profile = Shared.RES_PROFILES_BY_CLASS and Shared.RES_PROFILES_BY_CLASS[classKey]
      if not profile then
        local style = Shared.CLASS_STYLES and Shared.CLASS_STYLES[classKey]
        if style and style.label then profile = {{ label = style.label }} end
      end
      if profile and #profile > 0 then
        local parts = {}
        for i = 1, #profile do parts[#parts + 1] = profile[i].label end
        GameTooltip:AddLine(table.concat(parts, ", "), 1, 1, 1, true)
      else
        GameTooltip:AddLine("Aucune ressource", 0.6, 0.6, 0.6, true)
      end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
      local ls = lastStateRef.v
      if ls and b.classKey == ls.classKey then
        b:SetBackdropBorderColor(C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3], 1.0)
      else
        b:SetBackdropBorderColor(0.08, 0.06, 0.02, 0.90)
      end
      GameTooltip:Hide()
    end)

    UI.classButtons[idx] = b
    return b
  end

  for i = 1, #CLASS_KEYS do mkClassButton(i, CLASS_KEYS[i]) end
end

-- ── Tab 7 (Historique) ───────────────────────────────────────────────────────
-- ctx fields used: page (pageHistory), C, TEX, Core, mkButton, CONTENT_W
function ns.UI_BuildHistoryTab(ctx)
  local UI = ns.UI
  local page      = ctx.page
  local C         = ctx.C
  local TEX       = ctx.TEX
  local Core      = ctx.Core
  local mkButton  = ctx.mkButton
  local CONTENT_W = ctx.CONTENT_W

  local histHeader = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  histHeader:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -2)
  histHeader:SetTextColor(C.GOLD_DIM[1], C.GOLD_DIM[2], C.GOLD_DIM[3], 1)
  histHeader:SetText("Historique des évènements")
  local histHeaderLine = page:CreateTexture(nil, "ARTWORK")
  histHeaderLine:SetTexture(TEX.FLAT)
  histHeaderLine:SetPoint("TOPLEFT", histHeader, "BOTTOMLEFT", 0, -2)
  histHeaderLine:SetPoint("RIGHT",   page,       "RIGHT",      -4, 0)
  histHeaderLine:SetHeight(1)
  histHeaderLine:SetColorTexture(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.30)

  local sf = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT",     histHeaderLine, "BOTTOMLEFT",  0, -4)
  sf:SetPoint("BOTTOMRIGHT", page,           "BOTTOMRIGHT", -20, 44)
  UI.historyScroll = sf

  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(CONTENT_W - 64, 10)
  sf:SetScrollChild(child)
  UI.historyChild = child

  local txt = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  txt:SetPoint("TOPLEFT", 0, 0)
  txt:SetJustifyH("LEFT"); txt:SetJustifyV("TOP")
  txt:SetWidth(CONTENT_W - 72)
  txt:SetTextColor(C.TEXT_NORMAL[1], C.TEXT_NORMAL[2], C.TEXT_NORMAL[3], 1)
  txt:SetText("")
  UI.historyText = txt

  local function syncHistoryWidth()
    if not UI.historyScroll or not UI.historyChild or not UI.historyText then return end
    local w = UI.historyScroll:GetWidth() or 0
    if w <= 0 then return end
    local textW = math.max(80, w - 14)
    UI.historyChild:SetWidth(textW)
    UI.historyText:SetWidth(textW)
  end
  UI.syncHistoryWidth = syncHistoryWidth
  sf:SetScript("OnSizeChanged", syncHistoryWidth)
  syncHistoryWidth()

  local clearBtn = mkButton(page, "Effacer", 90, 20, 0, 0)
  clearBtn:ClearAllPoints()
  clearBtn:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 14, 12)
  clearBtn:SetScript("OnClick", function()
    if Core and Core.ClearHistory then Core.ClearHistory() end
  end)
  UI.historyClear = clearBtn
end

-- ── Tab 8 (Familier — Fiche) ─────────────────────────────────────────────────
-- ctx fields used: page (pagePetHP), C, TEX, Core, mkLabel, mkEdit, mkButton,
--   mkRowAnchor, getNumber, rowAnchors
function ns.UI_BuildPetFicheTab(ctx)
  local UI = ns.UI
  local page        = ctx.page
  local C           = ctx.C
  local TEX         = ctx.TEX
  local Core        = ctx.Core
  local mkLabel     = ctx.mkLabel
  local mkEdit      = ctx.mkEdit
  local mkButton    = ctx.mkButton
  local mkRowAnchor = ctx.mkRowAnchor
  local rowAnchors  = ctx.rowAnchors

  local petToggleBtn
  local petNameEB, petHpCurEB, petHpMaxEB
  local petArmorEB, petTrueArmorEB, petDodgeEB
  local petAttaqueMeleeEB, petAttaqueDistanceEB, petTempArmorEB
  local petMsHpEB, petMsMaxHpEB, petMsArmorEB
  local petActionValEB
  local petDmgArmorBtn, petDmgTrueBtn, petHealBtn, petDivineBtn, petSurgeryBtn

  local function applyAllPet()
    if not Core then return end
    local petNameVal   = petNameEB and petNameEB:GetText() or nil
    local petHpCurVal  = ctx.getNumber(petHpCurEB)
    local petHpMaxVal  = ctx.getNumber(petHpMaxEB)
    local armorVal     = ctx.getNumber(petArmorEB)
    local trueArmorVal = ctx.getNumber(petTrueArmorEB)
    local dodgeVal     = ctx.getNumber(petDodgeEB)
    local meleeVal     = ctx.getNumber(petAttaqueMeleeEB)
    local distVal      = ctx.getNumber(petAttaqueDistanceEB)
    local tempArmorVal = ctx.getNumber(petTempArmorEB)
    local msHpVal      = ctx.getNumber(petMsHpEB)
    local msMaxHpVal   = ctx.getNumber(petMsMaxHpEB)
    local msArmorVal   = ctx.getNumber(petMsArmorEB)
    if Core.SetPetName  and petNameVal then Core.SetPetName(petNameVal) end
    if Core.SetPetHP    then Core.SetPetHP(petHpCurVal, petHpMaxVal) end
    if Core.SetPetArmor then Core.SetPetArmor(armorVal, trueArmorVal) end
    if Core.SetPetDodge then Core.SetPetDodge(dodgeVal) end
    if Core.SetPetAttaque   then Core.SetPetAttaque(meleeVal, distVal) end
    if Core.SetPetTempArmor then Core.SetPetTempArmor(tempArmorVal) end
    if Core.SetPetMagicShield then Core.SetPetMagicShield(msHpVal, msMaxHpVal, msArmorVal) end
  end

  local petSF = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
  petSF:SetPoint("TOPLEFT",     page, "TOPLEFT",     0,   0)
  petSF:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -20, 0)
  local petPane = CreateFrame("Frame", nil, petSF)
  petPane:SetHeight(420)
  petSF:SetScrollChild(petPane)

  local function syncPetPaneWidth()
    local w = petSF:GetWidth() or 0
    if w <= 0 then return end
    petPane:SetWidth(math.max(200, w - 20))
  end
  petSF:SetScript("OnSizeChanged", syncPetPaneWidth)
  petPane:SetScript("OnSizeChanged", function()
    for i = 1, #rowAnchors do
      local f = rowAnchors[i]
      if f._reposition then f._reposition() end
    end
  end)

  local function mkPetHeader(text, y)
    local lbl = petPane:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    lbl:SetPoint("TOPLEFT",  petPane, "TOPLEFT",  0, y)
    lbl:SetPoint("TOPRIGHT", petPane, "TOPRIGHT", 0, y)
    lbl:SetJustifyH("CENTER")
    lbl:SetTextColor(C.TEXT_TITLE[1], C.TEXT_TITLE[2], C.TEXT_TITLE[3], 1)
    lbl:SetShadowOffset(1, -1); lbl:SetShadowColor(0, 0, 0, 0.60)
    lbl:SetText(text)
  end
  local function mkPetSep(y)
    local sep = petPane:CreateTexture(nil, "ARTWORK")
    sep:SetTexture(TEX.FLAT)
    sep:SetPoint("LEFT",  petPane, "LEFT",  20, 0)
    sep:SetPoint("RIGHT", petPane, "RIGHT", -20, 0)
    sep:SetPoint("TOP",   petPane, "TOP",   0, y)
    sep:SetHeight(1)
    sep:SetColorTexture(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.20)
  end

  -- Identité
  mkPetHeader("Identité", -6)
  local aPetToggle = mkRowAnchor(petPane, 380, -26)
  petToggleBtn = mkButton(aPetToggle, "Activer le familier", 180, 22, 0, 0, function()
    if not Core or not Core.SetPetEnabled then return end
    local p = Core.GetPet and Core.GetPet() or nil
    Core.SetPetEnabled(not (p and p.enabled))
  end)
  UI.petAuthorityToggleBtn = mkButton(aPetToggle, "Autorité", 180, 22, 200, 0, function()
    if not Core or not Core.SetPetAuthorityEnabled then return end
    local p = Core.GetPet and Core.GetPet() or nil
    Core.SetPetAuthorityEnabled(not (p and p.authorityEnabled))
  end)
  local aPetNom = mkRowAnchor(petPane, 230, -54)
  mkLabel(aPetNom, "Nom", 0, -2)
  petNameEB = mkEdit(aPetNom, 180, 20, 46, 0, applyAllPet)
  petNameEB:SetNumeric(false)
  local aPetHP = mkRowAnchor(petPane, 230, -80)
  mkLabel(aPetHP, "PV", 0, -2)
  petHpCurEB = mkEdit(aPetHP, 70, 20, 30,  0, applyAllPet)
  mkLabel(aPetHP, "/", 106, -2)
  petHpMaxEB = mkEdit(aPetHP, 70, 20, 120, 0, applyAllPet)

  -- Armure & Esquive (inclut Armure temporaire)
  mkPetSep(-106); mkPetHeader("Armure & Esquive", -114)
  local aPetDef1 = mkRowAnchor(petPane, 320, -132)
  mkLabel(aPetDef1, "Armure", 0, -2)
  petArmorEB     = mkEdit(aPetDef1, 70, 20, 60,  0, applyAllPet)
  mkLabel(aPetDef1, "Armure invul", 150, -2)
  petTrueArmorEB = mkEdit(aPetDef1, 70, 20, 244, 0, applyAllPet)
  local aPetDef2 = mkRowAnchor(petPane, 160, -160)
  mkLabel(aPetDef2, "Esquive", 0, -2)
  petDodgeEB = mkEdit(aPetDef2, 70, 20, 60, 0, applyAllPet)
  local aPetTempArmor = mkRowAnchor(petPane, 310, -188)
  mkLabel(aPetTempArmor, "Arm. tempo.", 0, -2)
  petTempArmorEB = mkEdit(aPetTempArmor, 70, 20, 110, 0, applyAllPet)
  mkButton(aPetTempArmor, "Réinit.", 70, 20, 200, 0, function()
    if Core and Core.ResetPetTempArmor then Core.ResetPetTempArmor() end
  end)

  -- Attaque
  mkPetSep(-216); mkPetHeader("Attaque", -224)
  local aPetAtt = mkRowAnchor(petPane, 320, -242)
  mkLabel(aPetAtt, "CaC", 0, -2)
  petAttaqueMeleeEB    = mkEdit(aPetAtt, 70, 20, 30,  0, applyAllPet)
  mkLabel(aPetAtt, "Distance", 120, -2)
  petAttaqueDistanceEB = mkEdit(aPetAtt, 70, 20, 210, 0, applyAllPet)

  -- Actions
  mkPetSep(-270); mkPetHeader("Actions", -278)
  local aPetVal = mkRowAnchor(petPane, 180, -296)
  mkLabel(aPetVal, "Valeur", 0, -2)
  petActionValEB = mkEdit(aPetVal, 80, 20, 56, 0)
  local aPetBtns1 = mkRowAnchor(petPane, 392, -322)
  petDmgArmorBtn = mkButton(aPetBtns1, "Dégâts (armure)", 190, 22, 0,   0, function()
    if Core and Core.PetDamageWithArmor then Core.PetDamageWithArmor(ctx.getNumber(petActionValEB) or 0) end
  end)
  petDmgTrueBtn = mkButton(aPetBtns1, "Dégâts (bruts)", 190, 22, 202, 0, function()
    if Core and Core.PetDamageTrue then Core.PetDamageTrue(ctx.getNumber(petActionValEB) or 0) end
  end)
  local aPetBtns2 = mkRowAnchor(petPane, 392, -350)
  petHealBtn = mkButton(aPetBtns2, "Soins", 190, 22, 0, 0, function()
    if Core and Core.PetHeal then Core.PetHeal(ctx.getNumber(petActionValEB) or 0) end
  end)
  petDivineBtn = mkButton(aPetBtns2, "Soins divins (75%)", 190, 22, 202, 0, function()
    if Core and Core.PetDivineHeal then Core.PetDivineHeal() end
  end)
  local aPetBtns3 = mkRowAnchor(petPane, 392, -388)
  petSurgeryBtn = mkButton(aPetBtns3, "Chirurgie (50%)", 190, 22, 0, 0, function()
    if Core and Core.PetSurgery then Core.PetSurgery() end
  end)

  -- Bouclier magique
  mkPetSep(-416); mkPetHeader("Bouclier magique", -424)
  local aPetMs1 = mkRowAnchor(petPane, 310, -442)
  mkLabel(aPetMs1, "PV", 0, -2)
  petMsHpEB    = mkEdit(aPetMs1, 70, 20, 26,  0, applyAllPet)
  mkLabel(aPetMs1, "/", 100, -2)
  petMsMaxHpEB = mkEdit(aPetMs1, 70, 20, 114, 0, applyAllPet)
  mkButton(aPetMs1, "Réinit.", 70, 20, 210, 0, function()
    if Core and Core.ResetPetMagicShield then Core.ResetPetMagicShield() end
  end)
  local aPetMs2 = mkRowAnchor(petPane, 230, -470)
  mkLabel(aPetMs2, "Armure", 0, -2)
  petMsArmorEB = mkEdit(aPetMs2, 70, 20, 70, 0, applyAllPet)

  petPane:SetHeight(510)

  -- Write refs
  UI.petToggleBtn = petToggleBtn
  UI.petControls = { petNameEB, petHpCurEB, petHpMaxEB,
                     petArmorEB, petTrueArmorEB, petDodgeEB,
                     petAttaqueMeleeEB, petAttaqueDistanceEB, petTempArmorEB,
                     petMsHpEB, petMsMaxHpEB, petMsArmorEB, petActionValEB }
  UI.petButtons  = { petDmgArmorBtn, petDmgTrueBtn, petHealBtn, petDivineBtn, petSurgeryBtn }
  ctx.petInputs  = {
    petName = petNameEB, petHpCur = petHpCurEB, petHpMax = petHpMaxEB,
    petArmor = petArmorEB, petTrueArmor = petTrueArmorEB,
    petDodge = petDodgeEB,
    petAttaqueMelee = petAttaqueMeleeEB, petAttaqueDistance = petAttaqueDistanceEB,
    petTempArmor = petTempArmorEB,
    petMsHp = petMsHpEB, petMsMaxHp = petMsMaxHpEB, petMsArmor = petMsArmorEB,
    petActionVal = petActionValEB,
  }
end

-- ── Tab 9 (Historique Familier) ──────────────────────────────────────────────
-- ctx fields used: page (pagePetArmor), C, TEX, Core, mkButton, CONTENT_W
function ns.UI_BuildPetHistoryTab(ctx)
  local UI = ns.UI
  local page      = ctx.page
  local C         = ctx.C
  local TEX       = ctx.TEX
  local Core      = ctx.Core
  local mkButton  = ctx.mkButton
  local CONTENT_W = ctx.CONTENT_W

  local petHistHeader = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  petHistHeader:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -2)
  petHistHeader:SetTextColor(C.GOLD_DIM[1], C.GOLD_DIM[2], C.GOLD_DIM[3], 1)
  petHistHeader:SetText("Historique du familier")
  local petHistHeaderLine = page:CreateTexture(nil, "ARTWORK")
  petHistHeaderLine:SetTexture(TEX.FLAT)
  petHistHeaderLine:SetPoint("TOPLEFT", petHistHeader,     "BOTTOMLEFT",  0, -2)
  petHistHeaderLine:SetPoint("RIGHT",   page,              "RIGHT",       -4, 0)
  petHistHeaderLine:SetHeight(1)
  petHistHeaderLine:SetColorTexture(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.30)

  local petSF = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
  petSF:SetPoint("TOPLEFT",     petHistHeaderLine, "BOTTOMLEFT",  0, -4)
  petSF:SetPoint("BOTTOMRIGHT", page,              "BOTTOMRIGHT", -20, 44)
  UI.petHistoryScroll = petSF

  local petChild = CreateFrame("Frame", nil, petSF)
  petChild:SetSize(CONTENT_W - 64, 10)
  petSF:SetScrollChild(petChild)
  UI.petHistoryChild = petChild

  local petTxt = petChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  petTxt:SetPoint("TOPLEFT", 0, 0)
  petTxt:SetJustifyH("LEFT"); petTxt:SetJustifyV("TOP")
  petTxt:SetWidth(CONTENT_W - 72)
  petTxt:SetTextColor(C.TEXT_NORMAL[1], C.TEXT_NORMAL[2], C.TEXT_NORMAL[3], 1)
  petTxt:SetText("")
  UI.petHistoryText = petTxt

  local function syncPetHistoryWidth()
    if not UI.petHistoryScroll or not UI.petHistoryChild or not UI.petHistoryText then return end
    local w = UI.petHistoryScroll:GetWidth() or 0
    if w <= 0 then return end
    local textW = math.max(80, w - 14)
    UI.petHistoryChild:SetWidth(textW)
    UI.petHistoryText:SetWidth(textW)
  end
  UI.syncPetHistoryWidth = syncPetHistoryWidth
  petSF:SetScript("OnSizeChanged", syncPetHistoryWidth)
  syncPetHistoryWidth()

  local petClearBtn = mkButton(page, "Effacer", 90, 20, 0, 0)
  petClearBtn:ClearAllPoints()
  petClearBtn:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 14, 12)
  petClearBtn:SetScript("OnClick", function()
    if Core and Core.ClearHistory then Core.ClearHistory() end
  end)
end

-- ── onChangeCallback builder ─────────────────────────────────────────────────
-- Returns the fully-formed onChangeCallback closure.
-- ctx fields used: C, Core, hpBar, applyContentHostLayout, activeSectionRef,
--   lastStateRef, getResProfile, getKeysForIdx, positionMarkers, hideMarkers,
--   setTab, setEditBoxEnabled, setButtonEnabled, applyResTextColor,
--   formatHistoryText, roundPct
function ns.UI_BuildOnChangeCallback(ctx)
  local UI = ns.UI
  local C                    = ctx.C
  local hpBar                = ctx.hpBar
  local applyContentHostLayout = ctx.applyContentHostLayout
  local activeSectionRef     = ctx.activeSectionRef  -- { v = 1 }
  local lastStateRef         = ctx.lastStateRef       -- { v = nil }
  local getResProfile        = ctx.getResProfile
  local getKeysForIdx        = ctx.getKeysForIdx
  local positionMarkers      = ctx.positionMarkers
  local hideMarkers          = ctx.hideMarkers
  local setTab               = ctx.setTab
  local setEditBoxEnabled    = ctx.setEditBoxEnabled
  local setButtonEnabled     = ctx.setButtonEnabled
  local applyResTextColor    = ctx.applyResTextColor
  local formatHistoryText    = ctx.formatHistoryText
  local roundPct             = ctx.roundPct

  return function(s)
    lastStateRef.v = s
    if ctx.refreshHpDisplay then ctx.refreshHpDisplay(s) end

    -- Resources (character section only)
    if activeSectionRef.v == 1 then
      local profile  = getResProfile(s)
      local rowCount = #profile
      local barCount
      if s.classKey == "SHAMAN" then
        local hasAuthority = false
        for i = 1, rowCount do
          if profile[i] and profile[i].idx == 5 then hasAuthority = true; break end
        end
        barCount = (rowCount > 0) and (hasAuthority and 5 or 1) or 0
      else
        barCount = rowCount
      end

      if UI.noResHint then
        if rowCount == 0 then UI.noResHint:Show() else UI.noResHint:Hide() end
      end
      if UI.tabDisabled then
        UI.tabDisabled[2] = (rowCount == 0)
        setTab(UI.activeTab or 1)
      end

      hideMarkers(UI.corruptionMarkers)
      hideMarkers(UI.insanityMarkers)
      hideMarkers(UI.arcaneChargeMarkers)

      do
        local n = math.max(0, math.min(5, barCount))
        local anchor = hpBar
        if n >= 1 and UI.resBars and UI.resBars[n] then anchor = UI.resBars[n] end
        UI.resAnchor = anchor
        applyContentHostLayout(anchor, 0)
      end

      if UI.syncHistoryWidth then UI.syncHistoryWidth() end

      for i = 1, 5 do
        local bar      = UI.resBars    and UI.resBars[i]
        local txt      = UI.resTexts   and UI.resTexts[i]
        local row      = UI.resRow     and UI.resRow[i]
        local rowLabel = UI.resRowLabel and UI.resRowLabel[i]
        local curEB    = UI.resRowCur  and UI.resRowCur[i]
        local maxEB    = UI.resRowMax  and UI.resRowMax[i]
        local p        = profile[i]

        if s.classKey == "SHAMAN" and (not p or p.idx <= 4) then
          if i ~= 1 then
            if bar then bar:Hide() end
            if txt then txt:SetText("") end
          end
          if not p then
            if row then row.resIdx = nil; row:Hide() end
          else
            local resKey, maxKey = getKeysForIdx(p.idx)
            local cur = s[resKey] or 0; local maxv = s[maxKey] or 0
            if row then row.resIdx = p.idx; row:Show() end
            if rowLabel and rowLabel.SetText then rowLabel:SetText(p.label or "Ressource") end
            if curEB then ctx.setNumber(curEB, cur) end
            if maxEB then ctx.setNumber(maxEB, maxv) end
            setEditBoxEnabled(maxEB, true)
          end
          if i == 1 and bar and bar._stackSegs then
            bar:Show(); UI.refreshShamanBar()
          end
        else
          if not p then
            if bar then bar:Hide() end
            if row then row.resIdx = nil; row:Hide() end
          else
            if bar and bar._stackSegs then
              for j = 1, #bar._stackSegs do bar._stackSegs[j]:Hide() end
            end
            local resKey, maxKey = getKeysForIdx(p.idx)
            local cur = s[resKey] or 0; local maxv = s[maxKey] or 0
            local isWarlockCorruption = (s.classKey == "WARLOCK"      and p.idx == 2)
            local isShadowInsanity    = (s.classKey == "SHADOWPRIEST" and p.idx == 2)
            local isMageArcaneCharge  = (s.classKey == "MAGE"         and p.idx == 2)
            local displayMax = maxv
            if isWarlockCorruption then
              maxv = 60; cur = math.max(0, math.min(cur, 60)); displayMax = 60
            elseif isShadowInsanity then
              displayMax = 25; cur = math.max(0, cur)
            elseif isMageArcaneCharge then
              maxv = 8; cur = math.max(0, math.min(cur, 8)); displayMax = 8
            end
            local pct = (displayMax and displayMax > 0) and (math.min(cur, displayMax) / displayMax) or 0
            if bar then
              bar:Show(); bar:SetStatusBarColor(p.r, p.g, p.b, 1)
              bar:SetValue(math.max(0, math.min(1, pct)))
            end
            if txt then
              applyResTextColor(txt)
              if isWarlockCorruption then
                local tier = cur < 10 and "Nulle" or cur < 25 and "Passive" or cur < 45 and "Moyenne" or "Forte"
                txt:SetText(string.format("%s : %d / %d (%d%%) — %s", p.label or "Corruption", cur, maxv, roundPct(pct), tier))
              elseif isShadowInsanity then
                local tier = cur < 4 and "Nulle" or cur < 12 and "Légère" or cur < 20 and "Forte" or cur < 25 and "Intense" or "Folie latente"
                txt:SetText(string.format("%s : %d (%d%%) — %s", p.label or "Insanité", cur, roundPct(pct), tier))
              elseif isMageArcaneCharge then
                local tier = cur >= 8 and "T5 disponible" or cur >= 4 and "T4 disponible" or nil
                if tier then
                  txt:SetText(string.format("%s : %d / %d — %s", p.label or "Charge arcanique", cur, maxv, tier))
                else
                  txt:SetText(string.format("%s : %d / %d", p.label or "Charge arcanique", cur, maxv))
                end
              else
                txt:SetText(string.format("%s : %d / %d (%d%%)", p.label or "Ressource", cur, maxv, roundPct(pct)))
              end
            end
            if isWarlockCorruption then positionMarkers(UI.corruptionMarkers, bar)
            elseif isShadowInsanity then positionMarkers(UI.insanityMarkers, bar)
            elseif isMageArcaneCharge then positionMarkers(UI.arcaneChargeMarkers, bar) end
            if row then row.resIdx = p.idx; row:Show() end
            if rowLabel and rowLabel.SetText then rowLabel:SetText(p.label or "Ressource") end
            if curEB then ctx.setNumber(curEB, cur) end
            if maxEB then
              if isShadowInsanity then ctx.setNumber(maxEB, 25)
              elseif isMageArcaneCharge then ctx.setNumber(maxEB, 8)
              else ctx.setNumber(maxEB, maxv) end
            end
            local fixedMax = isWarlockCorruption or isShadowInsanity or isMageArcaneCharge
            setEditBoxEnabled(maxEB, not fixedMax)
          end
        end
      end

    else
      -- Familiar section: collapse resource bars
      for i = 1, 5 do
        if UI.resBars  and UI.resBars[i]  then UI.resBars[i]:Hide() end
        if UI.resTexts and UI.resTexts[i] then UI.resTexts[i]:SetText("") end
        if UI.resRow   and UI.resRow[i]   then UI.resRow[i]:Hide() end
      end
      hideMarkers(UI.corruptionMarkers)
      hideMarkers(UI.insanityMarkers)
      UI.resAnchor = hpBar
      applyContentHostLayout(hpBar, 0)
      if UI.syncHistoryWidth then UI.syncHistoryWidth() end
    end

    -- Class buttons highlight
    if UI.classButtons then
      for i = 1, #UI.classButtons do
        local b = UI.classButtons[i]
        if b and b.classKey then
          if b.classKey == s.classKey then
            b:SetAlpha(1)
            b:SetBackdropBorderColor(C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3], 1.0)
          else
            b:SetAlpha(0.70)
            b:SetBackdropBorderColor(0.08, 0.06, 0.02, 0.90)
          end
        end
      end
    end

    -- Postures Élémentaires
    do
      local isSham = (s.classKey == "SHAMAN") and (activeSectionRef.v == 1)
      if UI.postureSectionLabel then
        if isSham then UI.postureSectionLabel:Show() else UI.postureSectionLabel:Hide() end
      end
      if UI.postureSepLine then
        if isSham then UI.postureSepLine:Show() else UI.postureSepLine:Hide() end
      end
      local reqKeys = { TERRE = "res", AIR = "res2", EAU = "res3", FEU = "res4" }
      if UI.postureButtons then
        for _, b in ipairs(UI.postureButtons) do
          if isSham then
            b:Show()
            local pk = b._postureKey; local rk = reqKeys[pk]
            local pts = rk and (s[rk] or 0) or 0
            setButtonEnabled(b, pts >= 3)
            if s.shamanPosture == pk then
              b:SetBackdropColor(b._postureR * 0.35, b._postureG * 0.35, b._postureB * 0.35, 0.95)
              b:SetBackdropBorderColor(b._postureR, b._postureG, b._postureB, 1.0)
            else
              b:SetBackdropColor(C.BROWN_DARK[1], C.BROWN_DARK[2], C.BROWN_DARK[3], 0.90)
              b:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.80)
            end
          else
            b:Hide()
          end
        end
      end
    end

    -- Scalar inputs
    ctx.setNumber(UI.inputs.hpCur, s.hp)
    ctx.setNumber(UI.inputs.hpMax, s.maxHp)
    if UI.stabiliseBtn then
      local isDead = (s.hp or 0) == 0
      UI.stabiliseBtn:SetShown(isDead)
      if isDead then
        if s.stabilise then
          UI.stabiliseBtn:SetText("Stabilisé")
          UI.stabiliseBtn:SetBackdropColor(0.05, 0.25, 0.05, 0.95)
          UI.stabiliseBtn:SetBackdropBorderColor(0.20, 0.80, 0.20, 1.0)
        else
          UI.stabiliseBtn:SetText("En agonie")
          UI.stabiliseBtn:SetBackdropColor(0.25, 0.03, 0.03, 0.95)
          UI.stabiliseBtn:SetBackdropBorderColor(0.85, 0.12, 0.12, 1.0)
        end
      end
    end
    ctx.setNumber(UI.inputs.armor,          s.armor)
    ctx.setNumber(UI.inputs.trueArmor,      s.trueArmor)
    ctx.setNumber(UI.inputs.tempArmor,      s.tempArmor)
    ctx.setNumber(UI.inputs.dodge,          s.dodge)
    ctx.setNumber(UI.inputs.block,          s.tempBlock)
    ctx.setNumber(UI.inputs.attaqueMelee,   s.attaqueMelee)
    ctx.setNumber(UI.inputs.attaqueDistance,s.attaqueDistance)
    ctx.setNumber(UI.inputs.chanceCur,      s.chance)
    ctx.setNumber(UI.inputs.chanceMax,      s.maxChance)
    ctx.setNumber(UI.inputs.perception,     s.perception)
    local ms = s.magicShield or {}
    ctx.setNumber(UI.inputs.msHp,    ms.hp)
    ctx.setNumber(UI.inputs.msMaxHp, ms.maxHp)
    ctx.setNumber(UI.inputs.msArmor, ms.armor)
    local mns = s.manaShield or {}
    ctx.setNumber(UI.inputs.mnsArmor, mns.armor)
    if UI.manaShieldToggleBtn then
      local isMage = (s.classKey == "MAGE")
      UI.manaShieldToggleBtn:SetShown(isMage)
      if UI.manaShieldArmorLabel then UI.manaShieldArmorLabel:SetShown(isMage) end
      if UI.manaShieldArmorEB then
        local w = UI.manaShieldArmorEB._wrap
        if w then w:SetShown(isMage) else UI.manaShieldArmorEB:SetShown(isMage) end
      end
      if isMage then
        UI.manaShieldToggleBtn:SetText(mns.active and "Désactiver bouclier de mana" or "Activer bouclier de mana")
      end
    end

    -- Pet controls
    local p = s.pet or {}
    local petEnabled = not not p.enabled
    if UI.petToggleBtn and UI.petToggleBtn.SetText then
      UI.petToggleBtn:SetText(petEnabled and "Désactiver le familier" or "Activer le familier")
    end
    if UI.petAuthorityToggleBtn and UI.petAuthorityToggleBtn.SetText then
      UI.petAuthorityToggleBtn:SetText(
        p.authorityEnabled and "Désactiver points d'autorité" or "Activer points d'autorité"
      )
    end
    if UI.refreshPopupToggleBtn then UI.refreshPopupToggleBtn() end
    if UI.inputs.petName then
      if not (UI.inputs.petName.HasFocus and UI.inputs.petName:HasFocus()) then
        UI.inputs.petName:SetText(p.name or "Familier")
      end
      setEditBoxEnabled(UI.inputs.petName, true)
    end
    ctx.setNumber(UI.inputs.petHpCur,           p.hp)
    ctx.setNumber(UI.inputs.petHpMax,           p.maxHp)
    ctx.setNumber(UI.inputs.petArmor,           p.armor)
    ctx.setNumber(UI.inputs.petTrueArmor,       p.trueArmor)
    ctx.setNumber(UI.inputs.petDodge,           p.dodge)
    ctx.setNumber(UI.inputs.petAttaqueMelee,    p.attaqueMelee)
    ctx.setNumber(UI.inputs.petAttaqueDistance, p.attaqueDistance)
    ctx.setNumber(UI.inputs.petTempArmor,       p.tempArmor)
    local pms = type(p.magicShield) == "table" and p.magicShield or {}
    ctx.setNumber(UI.inputs.petMsHp,    pms.hp)
    ctx.setNumber(UI.inputs.petMsMaxHp, pms.maxHp)
    ctx.setNumber(UI.inputs.petMsArmor, pms.armor)
    if UI.petControls then
      for i = 1, #UI.petControls do setEditBoxEnabled(UI.petControls[i], true) end
    end
    if UI.petButtons then
      for i = 1, #UI.petButtons do setButtonEnabled(UI.petButtons[i], petEnabled) end
    end

    -- History tabs
    if UI.historyText and UI.historyChild then
      local text = formatHistoryText(s.history, "CHAR")
      if not text then
        UI.historyText:SetText("Aucun évènement récent.")
        UI.historyChild:SetHeight(20)
      else
        UI.historyText:SetText(text)
        local h = (UI.historyText.GetStringHeight and UI.historyText:GetStringHeight()) or 0
        UI.historyChild:SetHeight(math.max(20, h + 10))
      end
    end
    if UI.petHistoryText and UI.petHistoryChild then
      local text = formatHistoryText(s.history, "PET")
      if not text then
        UI.petHistoryText:SetText("Aucun évènement récent.")
        UI.petHistoryChild:SetHeight(20)
      else
        UI.petHistoryText:SetText(text)
        local h = (UI.petHistoryText.GetStringHeight and UI.petHistoryText:GetStringHeight()) or 0
        UI.petHistoryChild:SetHeight(math.max(20, h + 10))
      end
    end
  end
end
