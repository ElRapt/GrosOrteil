---@diagnostic disable: undefined-global
-- GrosOrteil/UI_Grimoire.lua
-- First-class Player page for ordered, local-only Technique authoring.
local _, ns = ...

function ns.UI_BuildGrimoireTab(ctx)
  local UI = ns.UI
  local page = ctx.page
  local C = ctx.C
  local TEX = ctx.TEX
  local Core = ctx.Core
  local Grimoire = ctx.Grimoire or ns.Grimoire
  local IconCatalog = ctx.GrimoireIcons or ns.GrimoireIcons or {}
  local mkButton = ctx.mkButton
  local mkEdit = ctx.mkEdit
  local setButtonEnabled = ctx.setButtonEnabled
  local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
  local CARD_H, CARD_GAP = 150, 8

  if not Grimoire then return end

  local function applyIcon(texture, icon)
    if not texture then return end
    if texture.SetTexCoord then texture:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    if type(icon) == "table" and icon.type == "atlas"
        and type(icon.atlas) == "string" and icon.atlas ~= ""
        and texture.SetAtlas then
      local ok = pcall(texture.SetAtlas, texture, icon.atlas, false)
      local resolved = ok and (not texture.GetAtlas or texture:GetAtlas())
      if resolved then return end
    end
    if type(icon) == "table" and icon.type == "file"
        and (type(icon.file) == "number" or type(icon.file) == "string") then
      local ok = pcall(texture.SetTexture, texture, icon.file)
      local resolved = ok and (not texture.GetTexture or texture:GetTexture())
      if resolved then return end
    end
    texture:SetTexture(FALLBACK_ICON)
  end

  -- Resolve spell-backed catalogue entries at runtime. This keeps newer class
  -- icons current without shipping an icon database or depending on TRP.
  local function resolveCatalogFile(iconInfo)
    if type(iconInfo) ~= "table" then return FALLBACK_ICON end
    local spellId = iconInfo.spellId
    if type(spellId) == "number" then
      local spellAPI = rawget(_G, "C_Spell")
      if type(spellAPI) == "table" and type(spellAPI.GetSpellTexture) == "function" then
        local ok, file = pcall(spellAPI.GetSpellTexture, spellId)
        if ok and (type(file) == "number" or (type(file) == "string" and file ~= "")) then
          return file
        end
      end
      if type(spellAPI) == "table" and type(spellAPI.GetSpellInfo) == "function" then
        local ok, info = pcall(spellAPI.GetSpellInfo, spellId)
        local file = ok and type(info) == "table" and info.iconID or nil
        if type(file) == "number" or (type(file) == "string" and file ~= "") then
          return file
        end
      end
      local legacyGetSpellTexture = rawget(_G, "GetSpellTexture")
      if type(legacyGetSpellTexture) == "function" then
        local ok, file = pcall(legacyGetSpellTexture, spellId)
        if ok and (type(file) == "number" or (type(file) == "string" and file ~= "")) then
          return file
        end
      end
    end
    if type(iconInfo.file) == "number" or (type(iconInfo.file) == "string" and iconInfo.file ~= "") then
      return iconInfo.file
    end
    return FALLBACK_ICON
  end

  local function showMessage(message)
    local errors = rawget(_G, "UIErrorsFrame")
    if errors and type(errors.AddMessage) == "function" then
      errors:AddMessage(message, 1.0, 0.45, 0.20, 1.0)
    elseif type(print) == "function" then
      print("GrosOrteil : " .. message)
    end
  end

  -- Text input using the existing palette. Multiline inputs get a real scroll
  -- child so long descriptions remain editable at minimum window height.
  local function makeTextEdit(parent, multiline)
    local wrap = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    wrap:SetBackdrop({
      bgFile = TEX.FLAT, edgeFile = TEX.FLAT, edgeSize = 2,
      insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    wrap:SetBackdropColor(C.BROWN_DEEP[1], C.BROWN_DEEP[2], C.BROWN_DEEP[3], 0.92)
    wrap:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.70)

    local edit
    if multiline then
      local scroll = CreateFrame("ScrollFrame", nil, wrap, "UIPanelScrollFrameTemplate")
      scroll:SetPoint("TOPLEFT", wrap, "TOPLEFT", 6, -5)
      scroll:SetPoint("BOTTOMRIGHT", wrap, "BOTTOMRIGHT", -24, 5)
      edit = CreateFrame("EditBox", nil, scroll)
      edit:SetMultiLine(true)
      edit:SetAutoFocus(false)
      edit:SetHeight(40)
      scroll:SetScrollChild(edit)
      edit._scroll = scroll

      local function syncMultilineWidth()
        local width = scroll:GetWidth() or 0
        edit:SetWidth(math.max(40, width - 4))
      end
      wrap:SetScript("OnSizeChanged", syncMultilineWidth)
      edit:SetScript("OnTextChanged", function(self)
        local stringHeight = self.GetStringHeight and self:GetStringHeight() or 0
        local visibleHeight = scroll:GetHeight() or 40
        self:SetHeight(math.max(40, visibleHeight, stringHeight + 12))
      end)
      syncMultilineWidth()
    else
      edit = CreateFrame("EditBox", nil, wrap)
      edit:SetPoint("TOPLEFT", 6, -4)
      edit:SetPoint("BOTTOMRIGHT", -6, 4)
      edit:SetMultiLine(false)
      edit:SetAutoFocus(false)
    end

    edit:SetFontObject("GameFontHighlight")
    edit:SetTextColor(C.TEXT_BRIGHT[1], C.TEXT_BRIGHT[2], C.TEXT_BRIGHT[3], 1)
    edit:SetJustifyH("LEFT")
    if multiline then edit:SetJustifyV("TOP") end
    edit:SetScript("OnEditFocusGained", function()
      wrap:SetBackdropBorderColor(C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3], 0.90)
    end)
    edit:SetScript("OnEditFocusLost", function()
      wrap:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.70)
    end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit._wrap = wrap
    return edit, wrap
  end

  -- One reusable, addon-safe manual copy dialog.
  local function ensureCopyDialog()
    if UI.grimoireCopyDialog then return UI.grimoireCopyDialog end
    local dialog = CreateFrame("Frame", "GrosOrteilGrimoireCopyDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(520, 150)
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetClampedToScreen(true)
    dialog:EnableMouse(true)
    dialog:SetBackdrop({
      bgFile = TEX.BG_DARK, edgeFile = TEX.FLAT, edgeSize = 2,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    dialog:SetBackdropColor(C.BROWN_DEEP[1], C.BROWN_DEEP[2], C.BROWN_DEEP[3], 0.98)
    dialog:SetBackdropBorderColor(C.GOLD[1], C.GOLD[2], C.GOLD[3], 0.85)

    local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", dialog, "TOP", 0, -12)
    title:SetTextColor(C.TEXT_TITLE[1], C.TEXT_TITLE[2], C.TEXT_TITLE[3], 1)
    title:SetText("Copier la technique")

    local edit, wrap = makeTextEdit(dialog, true)
    wrap:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -40)
    wrap:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -16, -40)
    wrap:SetHeight(54)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); dialog:Hide() end)
    edit:HookScript("OnTextChanged", function(self)
      if self._restoringCopy then return end
      local expected = self._copyText or ""
      if self:GetText() ~= expected then
        self._restoringCopy = true
        self:SetText(expected)
        self:HighlightText(0, -1)
        self._restoringCopy = false
      end
    end)

    local hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOP", wrap, "BOTTOM", 0, -7)
    hint:SetTextColor(C.TEXT_DIM[1], C.TEXT_DIM[2], C.TEXT_DIM[3], 1)
    hint:SetText("Le texte est sélectionné — appuyez sur Ctrl+C / Cmd+C.")

    local close = mkButton(dialog, "Fermer", 84, 22, 0, 0)
    close:ClearAllPoints()
    close:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 10)
    close:SetScript("OnClick", function() edit:ClearFocus(); dialog:Hide() end)
    dialog:SetScript("OnHide", function() edit:ClearFocus() end)
    dialog.editBox = edit
    dialog:Hide()
    UI.grimoireCopyDialog = dialog
    return dialog
  end

  local function openCopyDialog(technique)
    local dialog = ensureCopyDialog()
    local text = Grimoire.FormatTechniqueForCopy(technique)
    dialog.editBox._copyText = text
    dialog.editBox._restoringCopy = true
    dialog.editBox:SetText(text)
    dialog.editBox._restoringCopy = false
    dialog:Show()
    dialog:Raise()
    dialog.editBox:SetFocus()
    dialog.editBox:HighlightText(0, -1)
    if C_Timer and C_Timer.After then
      C_Timer.After(0, function()
        if dialog:IsShown() then
          dialog.editBox:SetFocus()
          dialog.editBox:HighlightText(0, -1)
        end
      end)
    end
  end

  -- One reusable native icon picker. The curated catalogue stays grouped and
  -- scrollable without introducing an external addon dependency.
  local function ensureIconPicker()
    if UI.grimoireIconPicker then return UI.grimoireIconPicker end

    local dialog = CreateFrame("Frame", "GrosOrteilGrimoireIconPicker", UIParent, "BackdropTemplate")
    dialog:SetSize(520, 430)
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetClampedToScreen(true)
    dialog:EnableMouse(true)
    dialog:SetBackdrop({
      bgFile = TEX.BG_DARK, edgeFile = TEX.FLAT, edgeSize = 2,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    dialog:SetBackdropColor(C.BROWN_DEEP[1], C.BROWN_DEEP[2], C.BROWN_DEEP[3], 0.98)
    dialog:SetBackdropBorderColor(C.GOLD[1], C.GOLD[2], C.GOLD[3], 0.85)

    local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", dialog, "TOP", 0, -11)
    title:SetTextColor(C.TEXT_TITLE[1], C.TEXT_TITLE[2], C.TEXT_TITLE[3], 1)
    title:SetText("Choisir une icône")

    local iconCount = 0
    for i = 1, #IconCatalog do iconCount = iconCount + #(IconCatalog[i].icons or {}) end
    local subtitle = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -2)
    subtitle:SetTextColor(C.TEXT_DIM[1], C.TEXT_DIM[2], C.TEXT_DIM[3], 1)
    subtitle:SetText(tostring(iconCount) .. " icônes intégrées, classées par thème")

    local scroll = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", dialog, "TOPLEFT", 13, -48)
    scroll:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -31, 48)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(466)
    scroll:SetScrollChild(child)

    local buttons = {}
    local columns, buttonSize, gap = 8, 42, 10
    local startX = 12
    local y = -4
    for categoryIndex = 1, #IconCatalog do
      local category = IconCatalog[categoryIndex]
      local categoryName = category.category or "Icônes"
      local icons = category.icons or {}

      local categoryTitle = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      categoryTitle:SetPoint("TOPLEFT", child, "TOPLEFT", startX, y)
      categoryTitle:SetTextColor(C.GOLD_DIM[1], C.GOLD_DIM[2], C.GOLD_DIM[3], 1)
      categoryTitle:SetText(categoryName)
      y = y - 22

      for iconIndex = 1, #icons do
        local iconInfo = icons[iconIndex]
        local col = (iconIndex - 1) % columns
        local row = math.floor((iconIndex - 1) / columns)
        local button = CreateFrame("Button", nil, child, "BackdropTemplate")
        button:SetSize(buttonSize, buttonSize)
        button:SetPoint("TOPLEFT", child, "TOPLEFT",
          startX + col * (buttonSize + gap), y - row * (buttonSize + gap))
        button:SetBackdrop({
          bgFile = TEX.FLAT, edgeFile = TEX.FLAT, edgeSize = 2,
          insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        button:SetBackdropColor(C.BROWN_DARK[1], C.BROWN_DARK[2], C.BROWN_DARK[3], 0.88)
        button:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.55)

        local texture = button:CreateTexture(nil, "ARTWORK")
        texture:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -4)
        texture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 4)
        local resolvedFile = resolveCatalogFile(iconInfo)
        texture:SetTexture(resolvedFile)
        if texture.GetTexture and not texture:GetTexture() then texture:SetTexture(FALLBACK_ICON) end
        texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints(button)
        highlight:SetTexture(TEX.FLAT)
        highlight:SetColorTexture(C.GOLD[1], C.GOLD[2], C.GOLD[3], 0.14)

        button._iconInfo = iconInfo
        button._categoryName = categoryName
        button._texture = texture
        button._resolvedFile = resolvedFile
        button:SetScript("OnClick", function(self)
          if dialog._onSelect then
            local selected = self._iconInfo
            dialog._onSelect({
              name = selected.name,
              type = "file",
              file = self._resolvedFile or selected.file,
            })
          end
          dialog:Hide()
        end)
        button:SetScript("OnEnter", function(self)
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:ClearLines()
          GameTooltip:AddLine(self._iconInfo.label or self._iconInfo.name,
            C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3])
          local detail = self._categoryName
          if self._iconInfo.classLabel then
            detail = self._iconInfo.classLabel .. " — " .. detail
          end
          GameTooltip:AddLine(detail, C.TEXT_DIM[1], C.TEXT_DIM[2], C.TEXT_DIM[3])
          GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        buttons[#buttons + 1] = button
      end

      local rowCount = math.max(1, math.ceil(#icons / columns))
      y = y - rowCount * (buttonSize + gap) - 10
    end
    child:SetHeight(math.max(1, -y + 4))

    local noIcon = mkButton(dialog, "Aucune icône", 112, 22, 0, 0)
    noIcon:ClearAllPoints(); noIcon:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 15, 13)
    noIcon:SetScript("OnClick", function()
      if dialog._onSelect then dialog._onSelect(nil) end
      dialog:Hide()
    end)
    local close = mkButton(dialog, "Annuler", 88, 22, 0, 0)
    close:ClearAllPoints(); close:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -15, 13)
    close:SetScript("OnClick", function() dialog:Hide() end)

    function dialog:Open(selectedIcon, onSelect)
      self._onSelect = onSelect
      local selectedName = type(selectedIcon) == "table" and selectedIcon.name or nil
      for i = 1, #buttons do
        local button = buttons[i]
        if button._iconInfo.spellId then
          button._resolvedFile = resolveCatalogFile(button._iconInfo)
          button._texture:SetTexture(button._resolvedFile)
        end
        if selectedName and button._iconInfo.name == selectedName then
          button:SetBackdropBorderColor(C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3], 1)
        else
          button:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.55)
        end
      end
      self:Show()
      self:Raise()
    end
    dialog:SetScript("OnHide", function(self)
      self._onSelect = nil
      GameTooltip:Hide()
    end)
    dialog.buttons = buttons
    dialog:Hide()
    UI.grimoireIconPicker = dialog
    return dialog
  end

  local function openIconPicker(selectedIcon, onSelect)
    ensureIconPicker():Open(selectedIcon, onSelect)
  end
  UI.openGrimoireIconPicker = openIconPicker

  if _G.StaticPopupDialogs and not _G.StaticPopupDialogs.GROSORTEIL_DELETE_TECHNIQUE then
    _G.StaticPopupDialogs.GROSORTEIL_DELETE_TECHNIQUE = {
      text = "Supprimer définitivement la technique « %s » ?",
      button1 = "Supprimer",
      button2 = "Annuler",
      OnAccept = function(_, data)
        if data and data.id then Grimoire.DeleteTechnique(data.id) end
      end,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    }
  end

  -- List view ---------------------------------------------------------
  local listView = CreateFrame("Frame", nil, page)
  listView:SetAllPoints(page)

  local header = listView:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  header:SetPoint("TOP", listView, "TOP", 0, -4)
  header:SetTextColor(C.TEXT_TITLE[1], C.TEXT_TITLE[2], C.TEXT_TITLE[3], 1)
  header:SetText("Grimoire")

  local addBtn = mkButton(listView, "Ajouter une technique", 168, 24, 0, 0)
  addBtn:ClearAllPoints()
  addBtn:SetPoint("TOP", header, "BOTTOM", 0, -6)

  local hint = listView:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hint:SetPoint("TOPLEFT", listView, "TOPLEFT", 12, -62)
  hint:SetPoint("TOPRIGHT", listView, "TOPRIGHT", -12, -62)
  hint:SetJustifyH("CENTER")
  hint:SetTextColor(C.TEXT_DIM[1], C.TEXT_DIM[2], C.TEXT_DIM[3], 1)
  hint:SetText("Les coûts, dégâts / soins et utilisations sont purement informatifs ; rien n’est appliqué automatiquement.")

  local listScroll = CreateFrame("ScrollFrame", nil, listView, "UIPanelScrollFrameTemplate")
  listScroll:SetPoint("TOPLEFT", listView, "TOPLEFT", 4, -88)
  listScroll:SetPoint("BOTTOMRIGHT", listView, "BOTTOMRIGHT", -22, 2)
  local listChild = CreateFrame("Frame", nil, listScroll)
  listChild:SetHeight(1)
  listScroll:SetScrollChild(listChild)

  local emptyText = listChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  emptyText:SetPoint("TOP", listChild, "TOP", 0, -34)
  emptyText:SetTextColor(C.TEXT_DIM[1], C.TEXT_DIM[2], C.TEXT_DIM[3], 1)
  emptyText:SetText("Aucune technique. Commencez par en ajouter une.")

  local cards = {}
  local openEditor

  local function costTextFor(state, cost)
    if type(cost) ~= "table" then return "Aucun" end
    local resource = Grimoire.GetCostResource(cost.classKey, cost.resourceIdx)
    local label = resource and resource.label or "Ressource indisponible"
    local stale = not state or cost.classKey ~= state.classKey or not resource
    local text = tostring(cost.amount or 0) .. " " .. label
    if stale then text = text .. " |cffff8844(ancienne classe — à rechoisir)|r" end
    return text, stale
  end

  local function createCard(index)
    local card = CreateFrame("Frame", nil, listChild, "BackdropTemplate")
    card:SetHeight(CARD_H)
    card:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((index - 1) * (CARD_H + CARD_GAP)))
    card:SetBackdrop({
      bgFile = TEX.FLAT, edgeFile = TEX.FLAT, edgeSize = 1,
      insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    card:SetBackdropColor(C.BROWN_DARK[1], C.BROWN_DARK[2], C.BROWN_DARK[3], 0.72)
    card:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.45)
    if card.SetClipsChildren then card:SetClipsChildren(true) end

    local iconBg = CreateFrame("Frame", nil, card, "BackdropTemplate")
    iconBg:SetSize(42, 42)
    iconBg:SetPoint("TOPLEFT", card, "TOPLEFT", 9, -9)
    iconBg:SetBackdrop({ edgeFile = TEX.FLAT, edgeSize = 1 })
    iconBg:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.70)
    local icon = iconBg:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", iconBg, "TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", iconBg, "BOTTOMRIGHT", -3, 3)

    local actionCol = CreateFrame("Frame", nil, card)
    actionCol:SetPoint("TOPRIGHT", card, "TOPRIGHT", -7, -7)
    actionCol:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -7, 7)
    actionCol:SetWidth(68)

    local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", iconBg, "TOPRIGHT", 8, -1)
    title:SetPoint("RIGHT", actionCol, "LEFT", -8, 0)
    title:SetHeight(20)
    title:SetJustifyH("LEFT")
    title:SetJustifyV("TOP")
    title:SetTextColor(C.TEXT_BRIGHT[1], C.TEXT_BRIGHT[2], C.TEXT_BRIGHT[3], 1)
    if title.SetMaxLines then title:SetMaxLines(1) end

    local desc = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", iconBg, "TOPRIGHT", 8, -27)
    desc:SetPoint("RIGHT", actionCol, "LEFT", -8, 0)
    desc:SetHeight(51)
    desc:SetJustifyH("LEFT")
    desc:SetJustifyV("TOP")
    desc:SetWordWrap(true)
    desc:SetNonSpaceWrap(true)
    desc:SetTextColor(C.TEXT_NORMAL[1], C.TEXT_NORMAL[2], C.TEXT_NORMAL[3], 1)
    if desc.SetMaxLines then desc:SetMaxLines(3) end

    local meta = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    meta:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 59, 9)
    meta:SetPoint("RIGHT", actionCol, "LEFT", -8, 0)
    meta:SetHeight(48)
    meta:SetJustifyH("LEFT")
    meta:SetJustifyV("BOTTOM")
    meta:SetTextColor(C.TEXT_LABEL[1], C.TEXT_LABEL[2], C.TEXT_LABEL[3], 1)

    local copyBtn = mkButton(actionCol, "Copier", 68, 20, 0, 0)
    copyBtn:ClearAllPoints(); copyBtn:SetPoint("TOP", actionCol, "TOP", 0, 0)
    local editBtn = mkButton(actionCol, "Modifier", 68, 20, 0, 0)
    editBtn:ClearAllPoints(); editBtn:SetPoint("TOP", copyBtn, "BOTTOM", 0, -4)
    local deleteBtn = mkButton(actionCol, "Supprimer", 68, 20, 0, 0)
    deleteBtn:ClearAllPoints(); deleteBtn:SetPoint("TOP", editBtn, "BOTTOM", 0, -4)
    if deleteBtn._fs then deleteBtn._fs:SetTextColor(1.0, 0.55, 0.42, 1) end

    local upBtn = mkButton(actionCol, "Haut", 32, 20, 0, 0)
    upBtn:ClearAllPoints(); upBtn:SetPoint("BOTTOMLEFT", actionCol, "BOTTOMLEFT", 0, 0)
    local downBtn = mkButton(actionCol, "Bas", 32, 20, 0, 0)
    downBtn:ClearAllPoints(); downBtn:SetPoint("BOTTOMRIGHT", actionCol, "BOTTOMRIGHT", 0, 0)

    copyBtn:SetScript("OnClick", function()
      local technique = Grimoire.GetTechniqueById(card._techniqueId)
      if technique then openCopyDialog(technique) end
    end)
    editBtn:SetScript("OnClick", function()
      if card._techniqueId then openEditor(card._techniqueId) end
    end)
    deleteBtn:SetScript("OnClick", function()
      local technique = Grimoire.GetTechniqueById(card._techniqueId)
      if not technique then return end
      if StaticPopup_Show then
        StaticPopup_Show("GROSORTEIL_DELETE_TECHNIQUE", technique.title, nil, { id = technique.id })
      else
        showMessage("La confirmation de suppression est indisponible.")
      end
    end)
    upBtn:SetScript("OnClick", function()
      if card._techniqueId then Grimoire.MoveTechnique(card._techniqueId, -1) end
    end)
    downBtn:SetScript("OnClick", function()
      if card._techniqueId then Grimoire.MoveTechnique(card._techniqueId, 1) end
    end)

    card.icon = icon
    card.title = title
    card.desc = desc
    card.meta = meta
    card.upBtn = upBtn
    card.downBtn = downBtn
    cards[index] = card
    return card
  end

  local function layoutCards()
    local width = listScroll:GetWidth() or 0
    if width <= 0 then width = math.max(280, (ctx.CONTENT_W or 500) - 40) end
    width = math.max(260, width - 8)
    listChild:SetWidth(width)
    emptyText:SetWidth(math.max(180, width - 24))
    for i = 1, #cards do cards[i]:SetWidth(width) end
  end
  listScroll:SetScript("OnSizeChanged", layoutCards)

  -- Editor view -------------------------------------------------------
  local editor = CreateFrame("Frame", nil, page)
  editor:SetAllPoints(page)
  editor:Hide()

  local editorTitle = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  editorTitle:SetPoint("TOP", editor, "TOP", 0, -5)
  editorTitle:SetTextColor(C.TEXT_TITLE[1], C.TEXT_TITLE[2], C.TEXT_TITLE[3], 1)

  local formScroll = CreateFrame("ScrollFrame", nil, editor, "UIPanelScrollFrameTemplate")
  formScroll:SetPoint("TOPLEFT", editor, "TOPLEFT", 4, -34)
  formScroll:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", -22, 42)
  local formChild = CreateFrame("Frame", nil, formScroll)
  formChild:SetHeight(480)
  formScroll:SetScrollChild(formChild)

  local draft
  local editingId

  local iconLabel = formChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  iconLabel:SetPoint("TOPLEFT", formChild, "TOPLEFT", 10, -7)
  iconLabel:SetTextColor(C.TEXT_LABEL[1], C.TEXT_LABEL[2], C.TEXT_LABEL[3], 1)
  iconLabel:SetText("Icône")

  local iconBtn = CreateFrame("Button", nil, formChild, "BackdropTemplate")
  iconBtn:SetSize(48, 48)
  iconBtn:SetPoint("TOPLEFT", iconLabel, "BOTTOMLEFT", 0, -4)
  iconBtn:SetBackdrop({ edgeFile = TEX.FLAT, edgeSize = 2 })
  iconBtn:SetBackdropBorderColor(C.GOLD_MUTED[1], C.GOLD_MUTED[2], C.GOLD_MUTED[3], 0.80)
  local iconPreview = iconBtn:CreateTexture(nil, "ARTWORK")
  iconPreview:SetPoint("TOPLEFT", iconBtn, "TOPLEFT", 4, -4)
  iconPreview:SetPoint("BOTTOMRIGHT", iconBtn, "BOTTOMRIGHT", -4, 4)
  local chooseIconText = formChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  chooseIconText:SetPoint("LEFT", iconBtn, "RIGHT", 9, 7)
  chooseIconText:SetTextColor(C.TEXT_NORMAL[1], C.TEXT_NORMAL[2], C.TEXT_NORMAL[3], 1)
  chooseIconText:SetText("Choisir une icône classique")
  local clearIconBtn = mkButton(formChild, "Retirer l’icône", 120, 20, 0, 0)
  clearIconBtn:ClearAllPoints(); clearIconBtn:SetPoint("TOPLEFT", iconBtn, "TOPRIGHT", 9, -25)

  local titleLabel = formChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  titleLabel:SetPoint("TOPLEFT", formChild, "TOPLEFT", 10, -82)
  titleLabel:SetTextColor(C.TEXT_LABEL[1], C.TEXT_LABEL[2], C.TEXT_LABEL[3], 1)
  titleLabel:SetText("Titre *")
  local titleEdit, titleWrap = makeTextEdit(formChild, false)
  titleWrap:SetPoint("TOPLEFT", formChild, "TOPLEFT", 10, -103)
  titleWrap:SetPoint("TOPRIGHT", formChild, "TOPRIGHT", -10, -103)
  titleWrap:SetHeight(26)
  titleEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

  local descLabel = formChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  descLabel:SetPoint("TOPLEFT", formChild, "TOPLEFT", 10, -139)
  descLabel:SetTextColor(C.TEXT_LABEL[1], C.TEXT_LABEL[2], C.TEXT_LABEL[3], 1)
  descLabel:SetText("Description")
  local descEdit, descWrap = makeTextEdit(formChild, true)
  descWrap:SetPoint("TOPLEFT", formChild, "TOPLEFT", 10, -160)
  descWrap:SetPoint("TOPRIGHT", formChild, "TOPRIGHT", -10, -160)
  descWrap:SetHeight(106)

  local costLabel = formChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  costLabel:SetPoint("TOPLEFT", formChild, "TOPLEFT", 10, -279)
  costLabel:SetTextColor(C.TEXT_LABEL[1], C.TEXT_LABEL[2], C.TEXT_LABEL[3], 1)
  costLabel:SetText("Coût informatif")
  local costSelect = mkButton(formChild, "Aucun", 214, 24, 0, 0)
  costSelect:ClearAllPoints(); costSelect:SetPoint("TOPLEFT", costLabel, "BOTTOMLEFT", 0, -4)
  local amountLabel = formChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  amountLabel:SetPoint("LEFT", costSelect, "RIGHT", 12, 0)
  amountLabel:SetTextColor(C.TEXT_LABEL[1], C.TEXT_LABEL[2], C.TEXT_LABEL[3], 1)
  amountLabel:SetText("Montant")
  local amountEdit = mkEdit(formChild, 68, 24, 0, 0)
  amountEdit._wrap:ClearAllPoints()
  amountEdit._wrap:SetPoint("LEFT", amountLabel, "RIGHT", 7, 0)

  local damageHealingLabel = formChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  damageHealingLabel:SetPoint("TOPLEFT", formChild, "TOPLEFT", 10, -341)
  damageHealingLabel:SetTextColor(C.TEXT_LABEL[1], C.TEXT_LABEL[2], C.TEXT_LABEL[3], 1)
  damageHealingLabel:SetText("Dégâts / Soins (informatif)")
  local damageHealingEdit = mkEdit(formChild, 104, 24, 0, 0)
  damageHealingEdit._wrap:ClearAllPoints()
  damageHealingEdit._wrap:SetPoint("TOPLEFT", formChild, "TOPLEFT", 190, -335)
  damageHealingEdit:SetNumeric(false)
  damageHealingEdit:SetMaxLetters(19)
  local damageHealingHint = formChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  damageHealingHint:SetPoint("LEFT", damageHealingEdit._wrap, "RIGHT", 8, 0)
  damageHealingHint:SetTextColor(C.TEXT_DIM[1], C.TEXT_DIM[2], C.TEXT_DIM[3], 1)
  damageHealingHint:SetText("ex. 120 ou 30-50")

  local usesLabel = formChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  usesLabel:SetPoint("TOPLEFT", formChild, "TOPLEFT", 10, -381)
  usesLabel:SetTextColor(C.TEXT_LABEL[1], C.TEXT_LABEL[2], C.TEXT_LABEL[3], 1)
  usesLabel:SetText("Utilisations par mission")
  local usesMode = mkButton(formChild, "Illimité", 120, 24, 0, 0)
  usesMode:ClearAllPoints(); usesMode:SetPoint("TOPLEFT", usesLabel, "BOTTOMLEFT", 0, -4)
  local usesEdit = mkEdit(formChild, 68, 24, 0, 0)
  usesEdit._wrap:ClearAllPoints(); usesEdit._wrap:SetPoint("LEFT", usesMode, "RIGHT", 10, 0)

  local errorText = formChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  errorText:SetPoint("TOPLEFT", formChild, "TOPLEFT", 10, -449)
  errorText:SetPoint("RIGHT", formChild, "RIGHT", -10, 0)
  errorText:SetJustifyH("LEFT")
  errorText:SetTextColor(1.0, 0.38, 0.25, 1)
  errorText:SetText("")

  local saveBtn = mkButton(editor, "Enregistrer", 112, 24, 0, 0)
  saveBtn:ClearAllPoints(); saveBtn:SetPoint("BOTTOMRIGHT", editor, "BOTTOM", -5, 7)
  local cancelBtn = mkButton(editor, "Annuler", 92, 24, 0, 0)
  cancelBtn:ClearAllPoints(); cancelBtn:SetPoint("BOTTOMLEFT", editor, "BOTTOM", 5, 7)

  local function syncFormWidth()
    local width = formScroll:GetWidth() or 0
    if width <= 0 then width = math.max(300, (ctx.CONTENT_W or 500) - 40) end
    formChild:SetWidth(math.max(300, width - 8))
  end
  formScroll:SetScript("OnSizeChanged", syncFormWidth)

  local function refreshEditorSelectors()
    if not draft then return end
    applyIcon(iconPreview, draft.icon)
    if draft.cost then
      local costLabelText, stale = costTextFor(Core and Core.state, draft.cost)
      costSelect:SetText(costLabelText)
      if stale and costSelect._fs then
        costSelect._fs:SetTextColor(1.0, 0.55, 0.30, 1)
      elseif costSelect._fs then
        costSelect._fs:SetTextColor(C.GOLD_LIGHT[1], C.GOLD_LIGHT[2], C.GOLD_LIGHT[3], 1)
      end
      amountEdit._wrap:Show(); amountLabel:Show()
      if not amountEdit:HasFocus() then amountEdit:SetText(tostring(draft.cost.amount or 1)) end
    else
      costSelect:SetText("Aucun")
      if costSelect._fs then costSelect._fs:SetTextColor(C.GOLD_LIGHT[1], C.GOLD_LIGHT[2], C.GOLD_LIGHT[3], 1) end
      amountEdit._wrap:Hide(); amountLabel:Hide(); amountEdit:SetText("")
    end
    if draft.usesPerMission then
      usesMode:SetText("Limité")
      usesEdit._wrap:Show()
      if not usesEdit:HasFocus() then usesEdit:SetText(tostring(draft.usesPerMission)) end
    else
      usesMode:SetText("Illimité")
      usesEdit._wrap:Hide(); usesEdit:SetText("")
    end
    if not damageHealingEdit:HasFocus() then
      local damageHealingInput = draft.damageHealing and tostring(draft.damageHealing) or ""
      if draft.damageHealing and draft.damageHealingMax then
        damageHealingInput = damageHealingInput .. "-" .. tostring(draft.damageHealingMax)
      end
      damageHealingEdit:SetText(damageHealingInput)
    end
  end

  local function selectCost(resource)
    if not resource then
      draft.cost = nil
    else
      local amount = tonumber(amountEdit:GetText()) or (draft.cost and draft.cost.amount) or 1
      draft.cost = { classKey = Core.state.classKey, resourceIdx = resource.idx, amount = amount }
    end
    errorText:SetText("")
    refreshEditorSelectors()
  end

  costSelect:SetScript("OnClick", function(self)
    if not draft then return end
    local resources = Grimoire.GetAvailableCostResources(Core.state)
    local menuUtil = rawget(_G, "MenuUtil")
    if menuUtil and type(menuUtil.CreateContextMenu) == "function" then
      menuUtil.CreateContextMenu(self, function(_, root)
        root:CreateButton("Aucun", function() selectCost(nil) end)
        for i = 1, #resources do
          local resource = resources[i]
          root:CreateButton(resource.label, function() selectCost(resource) end)
        end
      end)
      return
    end

    -- Compatibility fallback: cycle choices when the modern menu API is absent.
    local current = 0
    if draft.cost and draft.cost.classKey == Core.state.classKey then
      for i = 1, #resources do
        if resources[i].idx == draft.cost.resourceIdx then current = i; break end
      end
    end
    current = current + 1
    if current > #resources then selectCost(nil) else selectCost(resources[current]) end
  end)

  usesMode:SetScript("OnClick", function()
    if not draft then return end
    if draft.usesPerMission then draft.usesPerMission = nil
    else draft.usesPerMission = tonumber(usesEdit:GetText()) or 1 end
    errorText:SetText("")
    refreshEditorSelectors()
  end)

  clearIconBtn:SetScript("OnClick", function()
    if not draft then return end
    draft.icon = nil
    applyIcon(iconPreview, nil)
  end)

  iconBtn:SetScript("OnClick", function()
    if not draft then return end
    openIconPicker(draft.icon, function(iconInfo)
      draft.icon = iconInfo
      applyIcon(iconPreview, draft.icon)
    end)
  end)
  iconBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Icône de la technique", C.GOLD_BRIGHT[1], C.GOLD_BRIGHT[2], C.GOLD_BRIGHT[3])
    GameTooltip:AddLine("Cliquez pour ouvrir la sélection d’icônes classiques de GrosOrteil.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local function closeEditor()
    titleEdit:ClearFocus(); descEdit:ClearFocus(); amountEdit:ClearFocus()
    usesEdit:ClearFocus(); damageHealingEdit:ClearFocus()
    if UI.grimoireIconPicker then UI.grimoireIconPicker:Hide() end
    draft, editingId = nil, nil
    editor:Hide()
    listView:Show()
    UI.grimoireEditorOpen = false
  end

  openEditor = function(id)
    local technique = id and Grimoire.GetTechniqueById(id) or nil
    editingId = technique and technique.id or nil
    if technique then
      draft = Grimoire.CopyTechnique(technique)
      editorTitle:SetText("Modifier la technique")
    else
      draft = {
        title = "", description = "", icon = nil, cost = nil,
        usesPerMission = nil, damageHealing = nil, damageHealingMax = nil,
      }
      editorTitle:SetText("Nouvelle technique")
    end
    titleEdit:SetText(draft.title or "")
    descEdit:SetText(draft.description or "")
    errorText:SetText("")
    refreshEditorSelectors()
    listView:Hide()
    editor:Show()
    UI.grimoireEditorOpen = true
    titleEdit:SetFocus()
  end

  addBtn:SetScript("OnClick", function() openEditor(nil) end)
  cancelBtn:SetScript("OnClick", closeEditor)
  saveBtn:SetScript("OnClick", function()
    if not draft then return end
    draft.title = titleEdit:GetText() or ""
    draft.description = descEdit:GetText() or ""
    local damageHealingText = damageHealingEdit:GetText() or ""
    local damageHealing, damageHealingMax, damageHealingError =
      Grimoire.ParseDamageHealingInput(damageHealingText)
    if damageHealingError then errorText:SetText(damageHealingError); return end
    draft.damageHealing = damageHealing
    draft.damageHealingMax = damageHealingMax
    if draft.cost then
      local amount = tonumber(amountEdit:GetText())
      if not amount or amount < 1 or amount ~= math.floor(amount) then
        errorText:SetText("Le montant du coût doit être un entier positif.")
        return
      end
      draft.cost.amount = amount
    end
    if draft.usesPerMission then
      local uses = tonumber(usesEdit:GetText())
      if not uses or uses < 1 or uses ~= math.floor(uses) then
        errorText:SetText("Le nombre d’utilisations doit être un entier positif.")
        return
      end
      draft.usesPerMission = uses
    end
    local fields = {
      title = draft.title,
      description = draft.description,
      icon = draft.icon or false,
      cost = draft.cost or false,
      usesPerMission = draft.usesPerMission or false,
      damageHealing = draft.damageHealing or false,
      damageHealingMax = draft.damageHealingMax or false,
    }
    local result, err
    if editingId then result, err = Grimoire.UpdateTechnique(editingId, fields)
    else result, err = Grimoire.CreateTechnique(fields) end
    if not result then errorText:SetText(err or "Impossible d’enregistrer la technique."); return end
    closeEditor()
  end)

  local function refresh(state)
    local techniques = Grimoire.GetTechniques(state)
    emptyText:SetShown(#techniques == 0)
    for i = 1, #techniques do
      local technique = techniques[i]
      local card = cards[i] or createCard(i)
      card._techniqueId = technique.id
      card.title:SetText(technique.title ~= "" and technique.title or "Technique sans titre")
      card.desc:SetText(technique.description ~= "" and technique.description or "Aucune description.")
      local costText = costTextFor(state, technique.cost)
      local usesText = technique.usesPerMission and (tostring(technique.usesPerMission) .. " / mission") or "Illimité"
      local damageHealingText = Grimoire.FormatDamageHealing(technique) or "Aucun"
      card.meta:SetText("Coût : " .. costText
        .. "\nDégâts / Soins : " .. damageHealingText
        .. "\nUtilisations : " .. usesText)
      applyIcon(card.icon, technique.icon)
      setButtonEnabled(card.upBtn, i > 1)
      setButtonEnabled(card.downBtn, i < #techniques)
      card:Show()
    end
    for i = #techniques + 1, #cards do
      cards[i]._techniqueId = nil
      cards[i]:Hide()
    end
    local totalHeight = #techniques > 0 and (#techniques * CARD_H + (#techniques - 1) * CARD_GAP) or 90
    listChild:SetHeight(totalHeight)
    layoutCards()
    if draft and editor:IsShown() then refreshEditorSelectors() end
  end

  UI.grimoireRows = cards
  UI.grimoireDamageHealingEdit = damageHealingEdit
  UI.refreshGrimoire = refresh
  UI.openGrimoireEditor = openEditor
  page:HookScript("OnHide", function()
    if UI.grimoireIconPicker then UI.grimoireIconPicker:Hide() end
  end)
  layoutCards()
  syncFormWidth()
end
