---@diagnostic disable: undefined-global
local _, ns = ...
local Distance, Theme = ns.Distance, ns.Theme
local C = Theme.Colors
local frame
local MODE_HINTS = {
  target = "Sélectionnez un membre du groupe. La mesure dépend des positions que WoW rend accessibles.",
  origin = "Mémorisez votre position, puis déplacez-vous : la distance au point de départ s'actualise.",
  waypoint = "Sur la carte du monde, posez un repère avec Ctrl + clic gauche. Mesure approximative sur le plan.",
}

local function label(parent, text, x, y, width, font, rgb)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetWidth(width); fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
  fs:SetWordWrap(true)
  rgb = rgb or C.TEXT_NORMAL
  fs:SetTextColor(rgb[1], rgb[2], rgb[3], 1)
  fs:SetText(text)
  return fs
end

local function button(parent, text, x, y, width, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); b:SetSize(width, 28)
  b._fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b._fs:SetPoint("CENTER"); b._fs:SetText(text)
  Theme.StyleButton(b)
  b:SetScript("OnClick", onClick)
  return b
end

function Distance.Refresh(modeChanged)
  if not frame or not frame:IsShown() then return end
  local result = Distance.Measure()
  frame.result = result
  if result.distance then
    frame.value:SetText(string.format("~ %.1f m", result.distance))
    frame.category:SetText(result.label .. "  ·  " .. result.range)
    frame.status:SetText("Estimation horizontale ; relief et obstacles non pris en compte.")
  else
    frame.value:SetText("Indisponible")
    frame.category:SetText("")
    frame.status:SetText(result.message)
  end
  if modeChanged then
    frame.hint:SetText(MODE_HINTS[Distance.mode])
    for mode, b in pairs(frame.modeButtons) do
      local rgb = mode == Distance.mode and C.GOLD or C.GOLD_MUTED
      b:SetBackdropBorderColor(rgb[1], rgb[2], rgb[3], 1)
      local text = mode == Distance.mode and C.TEXT_TITLE or C.TEXT_NORMAL
      b._fs:SetTextColor(text[1], text[2], text[3], 1)
    end
  end
  for _, row in ipairs(frame.categoryRows) do
    local rgb = result.category == row.key and C.TEXT_TITLE or C.TEXT_DIM
    row.text:SetTextColor(rgb[1], rgb[2], rgb[3], 1)
  end
end

local function create()
  if frame then return end
  frame = CreateFrame("Frame", "GrosOrteilDistanceFrame", UIParent, "BackdropTemplate")
  Distance.frame = frame
  frame:SetSize(432, 468); frame:SetPoint("CENTER", UIParent, "CENTER", 180, 40)
  frame:SetFrameStrata("DIALOG"); frame:SetClampedToScreen(true)
  frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
  Theme.ApplyNoteSkin(frame, 1)
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  label(frame, "Calculateur de distance", 18, -18, 354, "GameFontNormalLarge", C.TEXT_TITLE)
  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetSize(26, 26); close:SetPoint("TOPRIGHT", -12, -12)
  Theme.StyleClose(close); close:SetScript("OnClick", function() frame:Hide() end)
  frame.modeButtons = {
    target = button(frame, "Cible", 18, -53, 112, function() Distance.SetMode("target") end),
    origin = button(frame, "Point mémorisé", 137, -53, 150, function() Distance.SetMode("origin") end),
    waypoint = button(frame, "Repère carte", 294, -53, 120, function() Distance.SetMode("waypoint") end),
  }
  frame.value = label(frame, "", 18, -98, 396, "GameFontNormalLarge", C.TEXT_BRIGHT)
  frame.category = label(frame, "", 18, -126, 396, "GameFontHighlight", C.TEXT_TITLE)
  frame.status = label(frame, "", 18, -151, 396, nil, C.TEXT_LABEL)
  frame.status:SetHeight(38)
  frame.rememberButton = button(frame, "Mémoriser ici", 18, -195, 150, function()
    local ok, message = Distance.RememberPlayerPosition()
    if not ok then frame.status:SetText(message) end
  end)
  frame.hint = label(frame, "", 18, -234, 396)
  frame.hint:SetHeight(43)
  frame.categoryRows = {}
  for i, category in ipairs(Distance.Categories) do
    frame.categoryRows[i] = { key = category.key,
      text = label(frame, category.label .. " : " .. category.range, 18, -287 - (i - 1) * 21, 396, nil, C.TEXT_DIM) }
  end
  label(frame, "Le clic direct sur le sol 3D n'est pas disponible. Utilisez la carte ou un point mémorisé. Les m suivent la portée affichée par WoW ; ils ne garantissent pas la portée d'un sort.",
    18, -404, 396, nil, C.TEXT_DIM):SetHeight(52)
  local elapsed = 0
  local fade = Theme.MakeFadeIn(frame)
  frame:SetScript("OnShow", function()
    elapsed = 0
    Distance.Refresh(true); fade:Play()
    frame:SetScript("OnUpdate", function(_, delta)
      elapsed = elapsed + delta
      if elapsed >= 0.25 then elapsed = 0; Distance.Refresh() end
    end)
  end)
  frame:SetScript("OnHide", function(self)
    self:SetScript("OnUpdate", nil); self:StopMovingOrSizing()
  end)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "GrosOrteilDistanceFrame") end
  frame:Hide()
end

function Distance.Show(mode)
  if mode then Distance.SetMode(mode) end
  create()
  frame:Show(); frame:Raise(); Distance.Refresh()
end

function Distance.Toggle()
  if frame and frame:IsShown() then frame:Hide() else Distance.Show() end
end
