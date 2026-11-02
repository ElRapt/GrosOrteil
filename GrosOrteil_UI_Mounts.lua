local _, ns = ...

function ns.UI_BuildMountsTab(ctx)
  local UI, Mounts, Core = ns.UI, ns.Mounts, ns.Core
  local page = ctx.page
  local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -20, 0)
  local pane = CreateFrame("Frame", nil, scroll)
  pane:SetSize(400, 410)
  scroll:SetScrollChild(pane)
  scroll:SetScript("OnSizeChanged", function() pane:SetWidth(math.max(380, scroll:GetWidth() - 20)) end)
  local function row(y) return ctx.mkRowAnchor(pane, 380, y) end
  local inputs = {}
  local nav = row(-10)
  UI.mountPrevious = ctx.mkButton(nav, "Précédente", 120, 22, 0, 0, function() Mounts.SelectNext(-1) end)
  UI.mountCurrent = ctx.mkButton(nav, "Actuelle", 120, 22, 130, 0, function()
    Mounts.Sync()
    if Core.state.activeMountID then Mounts.Select(Core.state.activeMountID) end
  end)
  UI.mountNext = ctx.mkButton(nav, "Suivante", 120, 22, 260, 0, function() Mounts.SelectNext(1) end)
  local status = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  status:SetPoint("TOP", pane, "TOP", 0, -44)
  status:SetWidth(380)
  status:SetJustifyH("CENTER")
  ns.Theme.BindColor(status, "SetTextColor", ctx.C.TEXT_DIM, 1)
  UI.mountStatus = status

  local link = row(-84)
  UI.mountPetToggle = ctx.mkButton(link, "Utiliser mon familier", 380, 24, 0, 0, function()
    local _, config = Mounts.GetSelected()
    Mounts.SetPetLink(not config.isPet)
  end)
  local nameRow = row(-124)
  ctx.mkLabel(nameRow, "Nom", 0, -2)
  inputs.name = ctx.mkEdit(nameRow, 300, 20, 80, 0, function() Mounts.SetField("name", inputs.name:GetText(), inputs.name._mountID) end)
  inputs.name:SetNumeric(false)
  local hpRow = row(-156)
  ctx.mkLabel(hpRow, "PV", 0, -2)
  inputs.hp = ctx.mkEdit(hpRow, 110, 20, 80, 0, function() Mounts.SetField("hp", ctx.getNumber(inputs.hp), inputs.hp._mountID) end)
  ctx.mkLabel(hpRow, "/", 204, -2)
  inputs.maxHp = ctx.mkEdit(hpRow, 110, 20, 230, 0, function() Mounts.SetField("maxHp", ctx.getNumber(inputs.maxHp), inputs.maxHp._mountID) end)
  local defense = row(-188)
  ctx.mkLabel(defense, "Armure", 0, -2)
  inputs.armor = ctx.mkEdit(defense, 110, 20, 80, 0, function() Mounts.SetField("armor", ctx.getNumber(inputs.armor), inputs.armor._mountID) end)
  ctx.mkLabel(defense, "Esquive", 200, -2)
  inputs.dodge = ctx.mkEdit(defense, 110, 20, 270, 0, function() Mounts.SetField("dodge", ctx.getNumber(inputs.dodge), inputs.dodge._mountID) end)
  local value = row(-232)
  ctx.mkLabel(value, "Valeur", 0, -2)
  inputs.value = ctx.mkEdit(value, 110, 20, 80, 0)
  local buttons = {}
  for i, def in ipairs({
    { "Dégâts (armure)", "DAMAGE_ARMOR" }, { "Dégâts (bruts)", "DAMAGE_TRUE" },
    { "Dégâts directs", "DAMAGE_DIRECT" }, { "Soins", "HEAL" },
  }) do
    local anchor = row(-266 - math.floor((i - 1) / 2) * 32)
    buttons[i] = ctx.mkButton(anchor, def[1], 180, 24, ((i - 1) % 2) * 200, 0, function()
      Core.MountAction(def[2], ctx.getNumber(inputs.value) or 0)
    end)
  end
  UI.mountActionButtons = buttons
  local hint = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hint:SetPoint("TOP", pane, "TOP", 0, -342)
  hint:SetWidth(380)
  hint:SetJustifyH("CENTER")
  hint:SetText("Invoquez une monture pour créer sa fiche. Chaque monture conserve ses valeurs.\n"
    .. "En selle, le personnage ne peut pas esquiver.\n"
    .. "Avec « Utiliser mon familier », les PV et statistiques sont partagés.")
  ns.Theme.BindColor(hint, "SetTextColor", ctx.C.TEXT_DIM, 1)
  UI.mountInputs = inputs
  local lastID
  for _, key in ipairs({ "name", "hp", "maxHp", "armor", "dodge" }) do
    inputs[key]:HookScript("OnEditFocusGained", function(self) self._mountID = Mounts.GetSelectedID() end)
  end
  UI.refreshMounts = function(s)
    local id = Mounts.GetSelectedID()
    if id ~= lastID then
      lastID = id
      -- A mount change commits a focused draft to the sheet where it began.
      for _, key in ipairs({ "name", "hp", "maxHp", "armor", "dodge" }) do inputs[key]:ClearFocus() end
    end
    local m, config = Mounts.GetSelected()
    if not m then return end
    if not inputs.name:HasFocus() then inputs.name:SetText(m.name) end
    for _, key in ipairs({ "hp", "maxHp", "armor", "dodge" }) do ctx.setNumber(inputs[key], m[key]) end
    UI.mountPetToggle:SetText(config.isPet and "Familier partagé : oui" or "Utiliser mon familier")
    ns.Theme.SetButtonSelected(UI.mountPetToggle, config.isPet and { r = 0.95, g = 0.62, b = 0.18 } or false)
    ctx.setButtonEnabled(UI.mountCurrent, s.mounted)
    local active = s.mounted and s.activeMountID == Mounts.GetSelectedID()
    status:SetText(active and "Monture sortie — esquive du cavalier : 0"
      or s.mounted and "Fiche d'une autre monture — cavalier en selle"
      or "À pied — esquive du personnage disponible")
  end
end
