-- Custom-affix authoring, shared by the character and pet Affixes pages.
local _, ns = ...

function ns.UI_BuildCustomAffixes(ctx, page, isPet)
  local Core, Affixes, Theme = ns.Core, ns.Affixes, ns.Theme
  local C, mkButton, mkEdit = ctx.C, ctx.mkButton, ctx.mkEdit
  local refs = { cards = {}, rows = {} }
  local timedTint = { r = .35, g = .65, b = .95 }
  local draft, editingKey, pickerInfo
  local refresh, layoutEditor, openEditor
  local stats = {}
  for _, stat in ipairs(Affixes.STATS) do
    if not isPet or not stat.playerOnly then stats[#stats + 1] = stat end
  end
  local function holder()
    local s = Core.state
    return s and (isPet and s.pet or s)
  end
  local function label(parent, text, x, y, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetWidth(width or 386); fs:SetJustifyH("LEFT")
    Theme.BindColor(fs, "SetTextColor", C.TEXT_DIM, 1)
    fs:SetText(text)
    return fs
  end
  local root = CreateFrame("Frame", nil, page)
  root:SetPoint("TOP", page, "TOP", 0, -334); root:SetSize(410, 150)
  Theme.SectionHeader(root, "Affixes personnalisés", 0, 410)
  refs.newButton = mkButton(root, "+ Nouvel affixe", 190, 30, 0, -30)
  label(root, "Vos créations sont propres à cette fiche. Cliquez sur un affixe pour l'activer ou le désactiver.", 0, -70, 410)
  local empty = label(root, "Aucun affixe personnalisé. Créez votre premier affixe.", 0, -112, 410)
  local editor = CreateFrame("Frame", nil, root, "BackdropTemplate")
  editor:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -110); editor:SetSize(410, 300)
  editor:SetBackdrop({ bgFile = ctx.TEX.FLAT, edgeFile = ctx.TEX.FLAT, edgeSize = 1 })
  Theme.BindColor(editor, "SetBackdropColor", C.BROWN_DEEP, 0.95)
  Theme.BindColor(editor, "SetBackdropBorderColor", C.GOLD_MUTED, 0.7)
  refs.editor = editor
  label(editor, "Nom", 12, -12)
  refs.name = mkEdit(editor, 386, 26, 12, -30)
  refs.name:SetNumeric(false); refs.name:SetMaxLetters(80)
  label(editor, "Statistique", 12, -70, 218)
  label(editor, "Valeur (+ / -)", 238, -70, 100)
  refs.addEffect = mkButton(editor, "+ Statistique", 160, 26, 12, 0)
  refs.timed = mkButton(editor, "Durée : illimitée", 220, 26, 12, 0)
  refs.duration = mkEdit(editor, 80, 26, 242, 0)
  refs.duration:SetMaxLetters(4)
  local turnsLabel = label(editor, "tours", 332, 0, 66)
  refs.color = mkButton(editor, "Couleur…", 150, 26, 12, 0)
  local colorSwatch = editor:CreateTexture(nil, "ARTWORK")
  colorSwatch:SetSize(22, 22)
  colorSwatch:SetPoint("LEFT", refs.color, "RIGHT", 10, 0)
  refs.error = label(editor, "", 12, 0)
  refs.error:SetHeight(40)
  Theme.BindColor(refs.error, "SetTextColor", C.DANGER, 1)
  refs.save = mkButton(editor, "Enregistrer", 180, 28, 12, 0)
  refs.cancel = mkButton(editor, "Annuler", 180, 28, 218, 0)

  local function closePicker()
    if pickerInfo and ColorPickerFrame and ColorPickerFrame:GetExtraInfo() == pickerInfo then
      if ColorPickerFrame:IsShown() then pickerInfo.cancelFunc(); ColorPickerFrame:Hide() end
    end
    pickerInfo = nil
  end
  local function updateColor()
    if draft then colorSwatch:SetColorTexture(draft.color.r, draft.color.g, draft.color.b, 1) end
  end
  refs.color:SetScript("OnClick", function()
    if not draft or not ColorPickerFrame then return end
    closePicker()
    local session = draft
    local original = { r = draft.color.r, g = draft.color.g, b = draft.color.b }
    local info = { r = original.r, g = original.g, b = original.b, hasOpacity = false }
    info.extraInfo = info
    local function owns()
      return pickerInfo == info and draft == session and ColorPickerFrame:GetExtraInfo() == info
    end
    info.swatchFunc = function()
      if not owns() or not ColorPickerFrame:IsShown() then return end
      local r, g, b = ColorPickerFrame:GetColorRGB()
      draft.color = { r = r, g = g, b = b }; updateColor()
    end
    info.cancelFunc = function()
      if owns() then draft.color = original; updateColor(); pickerInfo = nil end
    end
    pickerInfo = info
    ColorPickerFrame:SetupColorPickerAndShow(info)
  end)

  local function setAt(frame, y, x)
    frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", editor, "TOPLEFT", x or 12, -y)
  end
  local function readRows()
    if not draft then return end
    for i, effect in ipairs(draft.effects) do effect.value = refs.rows[i].value:GetText() end
  end
  local function makeRow(i)
    local row = CreateFrame("Frame", nil, editor)
    row:SetSize(386, 26); row:SetPoint("TOPLEFT", editor, "TOPLEFT", 12, -90 - (i - 1) * 34)
    row.stat = mkButton(row, "", 218, 26, 0, 0)
    row.value = mkEdit(row, 102, 26, 226, 0); row.value:SetNumeric(false)
    row.value:SetMaxLetters(24)
    row.remove = mkButton(row, "−", 50, 26, 336, 0)
    row.stat:SetScript("OnClick", function(self)
      if not draft or not draft.effects[i] then return end
      local session, effect = draft, draft.effects[i]
      local function choose(stat)
        if draft ~= session or draft.effects[i] ~= effect then return end
        effect.stat = stat.key; row.stat:SetText(stat.label .. " ▾")
      end
      local menu = rawget(_G, "MenuUtil")
      if menu and type(menu.CreateContextMenu) == "function" then
        menu.CreateContextMenu(self, function(_, rootMenu)
          for _, stat in ipairs(stats) do
            local choice = stat
            rootMenu:CreateButton(choice.label, function() choose(choice) end)
          end
        end)
      else
        -- Same compatibility fallback as the Grimoire resource selector.
        local current = 0
        for index, stat in ipairs(stats) do if stat.key == effect.stat then current = index end end
        choose(stats[current % #stats + 1])
      end
    end)
    row.remove:SetScript("OnClick", function()
      if not draft or #draft.effects <= 1 then return end
      readRows(); table.remove(draft.effects, i); layoutEditor(); refresh()
    end)
    return row
  end
  layoutEditor = function()
    if not draft then return end
    for i, effect in ipairs(draft.effects) do
      local row = refs.rows[i]
      if not row then row = makeRow(i); refs.rows[i] = row end
      row.stat:SetText(Affixes.BY_STAT[effect.stat].label .. " ▾")
      row.value:SetText(tostring(effect.value)); row:Show()
      ctx.setButtonEnabled(row.remove, #draft.effects > 1)
    end
    for i = #draft.effects + 1, #refs.rows do refs.rows[i]:Hide() end
    local y = 90 + #draft.effects * 34
    setAt(refs.addEffect, y); y = y + 38
    setAt(refs.timed, y)
    setAt(refs.duration:GetParent(), y, 242)
    setAt(turnsLabel, y + 7, 332); y = y + 38
    refs.duration:GetParent():SetShown(draft.timed); turnsLabel:SetShown(draft.timed)
    refs.timed:SetText(draft.timed and "Durée : limitée" or "Durée : illimitée")
    Theme.SetButtonSelected(refs.timed, draft.timed and timedTint or false)
    setAt(refs.color, y); y = y + 36
    setAt(refs.error, y); y = y + 46
    setAt(refs.save, y); setAt(refs.cancel, y, 218)
    editor:SetHeight(y + 40)
    ctx.setButtonEnabled(refs.addEffect, #draft.effects < #stats)
    updateColor()
  end
  refs.addEffect:SetScript("OnClick", function()
    if not draft or #draft.effects >= #stats then return end
    readRows()
    local used = {}
    for _, effect in ipairs(draft.effects) do used[effect.stat] = true end
    for _, stat in ipairs(stats) do
      if not used[stat.key] then
        draft.effects[#draft.effects + 1] = { stat = stat.key, value = "1" }; break
      end
    end
    layoutEditor(); refresh()
  end)
  refs.timed:SetScript("OnClick", function()
    if not draft then return end
    readRows(); draft.timed = not draft.timed; layoutEditor(); refresh()
  end)

  local function closeEditor()
    closePicker()
    refs.name:ClearFocus(); refs.duration:ClearFocus()
    for _, row in ipairs(refs.rows) do row.value:ClearFocus() end
    draft, editingKey = nil, nil
    editor:Hide(); refresh()
  end
  openEditor = function(def)
    closePicker()
    editingKey = def and def.id
    draft = { holder = holder(), color = { r = 0.5, g = 0.75, b = 1 },
      timed = def and def.duration ~= nil, effects = {} }
    if def then
      draft.color = { r = def.color.r, g = def.color.g, b = def.color.b }
      for _, effect in ipairs(def.effects) do
        draft.effects[#draft.effects + 1] = { stat = effect.stat, value = tostring(effect.value) }
      end
    else draft.effects[1] = { stat = "maxHp", value = "1" } end
    refs.name:SetText(def and def.name or "")
    refs.duration:SetText(tostring(def and def.duration or 3))
    refs.error:SetText("")
    layoutEditor(); editor:Show(); refresh(); refs.name:SetFocus()
  end
  refs.newButton:SetScript("OnClick", function() openEditor() end)
  refs.cancel:SetScript("OnClick", closeEditor)
  refs.save:SetScript("OnClick", function()
    if not draft then return end
    if holder() ~= draft.holder then closeEditor(); return end
    readRows()
    local input = { name = refs.name:GetText(), color = draft.color, effects = {} }
    if draft.timed then input.duration = tonumber(refs.duration:GetText()) or false end
    for _, effect in ipairs(draft.effects) do
      input.effects[#input.effects + 1] = { stat = effect.stat,
        value = tonumber((effect.value:gsub(",", "."))) }
    end
    local key, err = Core.SaveCustomAffix(input, editingKey, isPet)
    if key then closeEditor() else refs.error:SetText(err) end
  end)
  page:HookScript("OnHide", function()
    closePicker(); refs.name:ClearFocus(); refs.duration:ClearFocus()
    for _, row in ipairs(refs.rows) do row.value:ClearFocus() end
  end)

  local function makeCard()
    local card = CreateFrame("Frame", nil, root)
    card:SetWidth(410)
    card.toggle = mkButton(card, "", 410, 30, 0, 0)
    card.toggle._fs:SetWidth(384)
    card.toggle._fs:SetMaxLines(1)
    card.swatch = card.toggle:CreateTexture(nil, "ARTWORK")
    card.swatch:SetPoint("TOPLEFT", card.toggle, "TOPLEFT", 2, -2)
    card.swatch:SetPoint("BOTTOMLEFT", card.toggle, "BOTTOMLEFT", 2, 2)
    card.swatch:SetWidth(4)
    card.summary = label(card, "", 10, -38, 390)
    card.edit = mkButton(card, "Modifier", 100, 24, 0, 0)
    card.delete = mkButton(card, "Supprimer", 100, 24, 110, 0)
    card.toggle:SetScript("OnClick", function()
      if isPet then Core.TogglePetAffix(card.key) else Core.ToggleAffix(card.key) end
    end)
    card.toggle:SetScript("OnEnter", function(self)
      local def = Affixes.Find(holder(), card.key)
      if not def then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:ClearLines()
      GameTooltip:AddLine(def.name, def.color.r, def.color.g, def.color.b)
      GameTooltip:AddLine(Affixes.Summary(def), 1, 1, 1, true)
      GameTooltip:AddLine(def.duration and ("Durée : " .. def.duration .. " tours") or "Durée illimitée", 1, 1, 1)
      GameTooltip:Show()
    end)
    card.toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    card.edit:SetScript("OnClick", function()
      local def = Affixes.Find(holder(), card.key)
      if def then openEditor(def) end
    end)
    card.delete:SetScript("OnClick", function()
      if editingKey == card.key then closeEditor() end
      Core.DeleteCustomAffix(card.key, isPet)
    end)
    return card
  end
  refresh = function()
    local h = holder() or {}
    local list = h.customAffixes or {}
    local y = draft and 110 + editor:GetHeight() + 16 or 110
    empty:SetShown(#list == 0 and not draft)
    -- Reuse cards; ordinary state updates never repopulate the editor's draft.
    for i, def in ipairs(list) do
      local card = refs.cards[i]
      if not card then card = makeCard(); refs.cards[i] = card end
      card.key = def.id
      card:ClearAllPoints(); card:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
      local turns = h.affixTurns and h.affixTurns[def.id]
      local active = h.affixes and h.affixes[def.id]
      card.toggle:SetText(def.name .. (turns and (" (" .. turns .. " tours)") or (active and " • Actif" or "")))
      Theme.SetButtonSelected(card.toggle, active and def.color or false)
      card.swatch:SetColorTexture(def.color.r, def.color.g, def.color.b, 1)
      ctx.setButtonEnabled(card.toggle, not isPet or h.enabled)
      card.summary:SetText(Affixes.Summary(def) .. "\n" .. (def.duration and (def.duration .. " tours") or "Illimité"))
      local textHeight = card.summary:GetStringHeight()
      card.edit:ClearAllPoints(); card.edit:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -46 - textHeight)
      card.delete:ClearAllPoints(); card.delete:SetPoint("TOPLEFT", card, "TOPLEFT", 110, -46 - textHeight)
      card:SetHeight(80 + textHeight); card:Show()
      y = y + card:GetHeight() + 12
    end
    for i = #list + 1, #refs.cards do refs.cards[i]:Hide() end
    root:SetHeight(y + 40); page:SetHeight(334 + y + 40)
  end
  editor:Hide()
  if isPet then ns.UI.petCustomAffixes = refs else ns.UI.customAffixes = refs end
  refresh()
  return refresh
end
