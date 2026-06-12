local ADDON, ns = ...

local MINIMAP_ICON_NAME = "GrosOrteil"
local MINIMAP_ICON_TEXTURE = "Interface\\Icons\\inv_misc_herb_goldclover"

local LDB
local Icon
local minimapLauncher

local function deepCopy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for k, v in pairs(value) do
    out[deepCopy(k, seen)] = deepCopy(v, seen)
  end
  return out
end

local function ensureCharacterDB()
  GrosOrteilDB = GrosOrteilDB or {}
  if type(GrosOrteilDBPC) ~= "table" then
    GrosOrteilDBPC = {}
  end

  -- First login after introducing per-character DB: clone existing account-wide data.
  if not GrosOrteilDBPC._pcInitialized then
    if next(GrosOrteilDBPC) == nil and type(GrosOrteilDB) == "table" and next(GrosOrteilDB) ~= nil then
      GrosOrteilDBPC = deepCopy(GrosOrteilDB)
      GrosOrteilDBPC._migratedFromAccountWide = true
    end
    GrosOrteilDBPC._pcInitialized = true
  end

  ns.db = GrosOrteilDBPC
  return ns.db
end

function ns.GetDB()
  if type(ns.db) ~= "table" then
    ensureCharacterDB()
  end
  return ns.db
end

local function applyMinimapVisibility()
  local db = ns.GetDB()
  db.minimap = db.minimap or {}
  if not Icon then return end
  if db.minimap.hide then
    Icon:Hide(MINIMAP_ICON_NAME)
  else
    Icon:Show(MINIMAP_ICON_NAME)
  end
end

local function setMinimapHidden(hidden)
  local db = ns.GetDB()
  db.minimap = db.minimap or {}
  db.minimap.hide = not not hidden
  applyMinimapVisibility()
end

local function initMinimapIcon()
  if not LDB and type(LibStub) == "table" and LibStub.GetLibrary then
    LDB = LibStub("LibDataBroker-1.1", true)
  end
  if not Icon and type(LibStub) == "table" and LibStub.GetLibrary then
    Icon = LibStub("LibDBIcon-1.0", true)
  end
  if not LDB or not Icon then
    print("|cFFFF7F00GrosOrteil|r: LibDataBroker/LibDBIcon indisponibles, icone minimap desactivee.")
    return
  end

  local db = ns.GetDB()
  db.minimap = db.minimap or { minimapPos = 225, hide = false }

  if minimapLauncher == nil then
    minimapLauncher = LDB:NewDataObject(MINIMAP_ICON_NAME, {
      type = "launcher",
      text = "GrosOrteil",
      icon = MINIMAP_ICON_TEXTURE,
      OnClick = function(_, button)
        if button == "RightButton" then
          if ns.RaidPanel then ns.RaidPanel.Toggle() end
        else
          local shown = ns.UI and ns.UI.frame and ns.UI.frame:IsShown()
          ns.UI_Show(not shown)
        end
      end,
      OnTooltipShow = function(tt)
        tt:AddLine("GrosOrteil")
        tt:AddLine("Clic gauche : afficher/masquer la fenêtre", 0.8, 0.8, 0.8)
        tt:AddLine("Clic droit : panel de groupe", 0.8, 0.8, 0.8)
        tt:AddLine("/go help : liste des commandes", 0.6, 0.52, 0.36)
      end,
    })
  end

  if not Icon:IsRegistered(MINIMAP_ICON_NAME) then
    Icon:Register(MINIMAP_ICON_NAME, minimapLauncher, db.minimap)
  end

  Icon:Refresh(MINIMAP_ICON_NAME, db.minimap)
  applyMinimapVisibility()
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")

f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    ensureCharacterDB()
    initMinimapIcon()
  elseif event == "PLAYER_LOGIN" then
    ns.Core_Init()
    ns.UI_Init()
    if ns.Comm_Init then
      ns.Comm_Init()
    end
    if ns.TargetPopup_Init then
      ns.TargetPopup_Init()
    end
    if ns.Bonus_Init then
      ns.Bonus_Init()
    end
    if ns.RaidPanel_Init then
      ns.RaidPanel_Init()
    end
    if ns.Heal_Init then
      ns.Heal_Init()
    end
    if ns.Distance_Init then
      ns.Distance_Init()  -- restore the ground aura if it was left enabled
    end
    initMinimapIcon()

    f:UnregisterEvent("ADDON_LOADED")
    f:UnregisterEvent("PLAYER_LOGIN")

    _G.SLASH_GROSORTEIL1 = "/grosorteil"
    _G.SLASH_GROSORTEIL2 = "/go"

    local function printHelp()
      local G, D = "|cFF00FF00", "|cFFB0A08C"
      print(G .. "GrosOrteil|r — commandes :")
      print(G .. "/go|r " .. D .. "— affiche/masque la fenêtre principale|r")
      print(G .. "/go raid|r " .. D .. "— panel de groupe (fiches + compteur)|r")
      print(G .. "/go aura|r " .. D .. "— aura de distance au sol|r")
      print(G .. "/go aura auto [on|off]|r " .. D .. "— l'aura suit l'inclinaison de la caméra|r")
      print(G .. "/go aura taille|aplat|hauteur <valeur>|r " .. D .. "— calibration de l'aura|r")
      print(G .. "/go pet [on|off|name <NOM>]|r " .. D .. "— familier|r")
      print(G .. "/go class <CLASSE>|r " .. D .. "— change la classe de la fiche|r")
      print(G .. "/go clearhistory|r " .. D .. "— vide le journal des évènements|r")
      print(G .. "/go minimap [show|hide]|r " .. D .. "— icône minimap|r")
      print(G .. "/go reset|r " .. D .. "— recentre la fenêtre|r")
    end

    _G.SlashCmdList["GROSORTEIL"] = function(msg)
      local raw = (msg or "")
      local cmd, rest = raw:match("^(%S+)%s*(.-)$")
      cmd = (cmd or ""):lower()
      rest = rest or ""

      if cmd == "show" then
        ns.UI_Show(true)
      elseif cmd == "hide" then
        ns.UI_Show(false)
      elseif cmd == "toggle" or cmd == "" then
        local shown = ns.UI and ns.UI.frame and ns.UI.frame:IsShown()
        ns.UI_Show(not shown)
      elseif cmd == "reset" then
        ns.UI_ResetPosition()
      elseif cmd == "clear" or cmd == "clearhistory" then
        if ns.Core and ns.Core.ClearHistory then
          ns.Core.ClearHistory()
        end
      elseif cmd == "class" then
        local classKey = rest:upper()
        if ns.Core and ns.Core.SetClassKey and classKey ~= "" then
          ns.Core.SetClassKey(classKey)
        else
          print("|cFF00FF00GrosOrteil|r usage: /go class <CLASS>")
        end
      elseif cmd == "pet" then
        if rest == "" then
          if ns.Core and ns.Core.GetPet and ns.Core.SetPetEnabled then
            local pet = ns.Core.GetPet()
            ns.Core.SetPetEnabled(not (pet and pet.enabled))
          end
        else
          local sub, value = rest:match("^(%S+)%s*(.-)$")
          sub = (sub or ""):lower()
          value = value or ""
          if sub == "on" and ns.Core and ns.Core.SetPetEnabled then
            ns.Core.SetPetEnabled(true)
          elseif sub == "off" and ns.Core and ns.Core.SetPetEnabled then
            ns.Core.SetPetEnabled(false)
          elseif sub == "name" and ns.Core and ns.Core.SetPetName and value ~= "" then
            ns.Core.SetPetName(value)
          else
            print("|cFF00FF00GrosOrteil|r usage: /go pet | /go pet on | /go pet off | /go pet name <NOM>")
          end
        end
      elseif cmd == "raid" then
        if ns.RaidPanel then ns.RaidPanel.Toggle() end
      elseif cmd == "aura" or cmd == "distance" then
        local sub, val = rest:match("^(%S*)%s*(.-)$")
        sub = (sub or ""):lower()
        if sub == "" then
          if ns.Distance then ns.Distance.ToggleOverlay() end
        elseif sub == "taille" or sub == "aplat" or sub == "hauteur" then
          local out = ns.Distance and ns.Distance.SetOverlayOption(sub, tonumber(val))
          if out then
            print(string.format("|cFF00FF00GrosOrteil|r aura %s = %.2f", sub, out))
            if sub == "aplat" then
              print("|cFF00FF00GrosOrteil|r inclinaison auto desactivee (/go aura auto pour la retablir).")
            end
          else
            print("|cFF00FF00GrosOrteil|r usage: /go aura " .. sub .. " <valeur>")
          end
        elseif sub == "auto" then
          local v = val:lower()
          local want  -- nil = toggle
          if v == "on" or v == "oui" then want = true
          elseif v == "off" or v == "non" then want = false end
          local state = ns.Distance and ns.Distance.SetOverlayAuto(want)
          if state ~= nil then
            print("|cFF00FF00GrosOrteil|r inclinaison auto " .. (state and "activee" or "desactivee")
              .. (state and " : l'aura suit la camera." or " : reglage manuel via /go aura aplat."))
          end
        else
          print("|cFF00FF00GrosOrteil|r usage: /go aura | /go aura auto [on|off] | /go aura taille|aplat|hauteur <valeur>")
        end
      elseif cmd == "minimap" then
        local sub = (rest or ""):match("^(%S*)"):lower()
        if sub == "hide" then
          setMinimapHidden(true)
          print("|cFF00FF00GrosOrteil|r icone minimap masquee.")
        elseif sub == "show" then
          setMinimapHidden(false)
          print("|cFF00FF00GrosOrteil|r icone minimap affichee.")
        else
          local db = ns.GetDB()
          db.minimap = db.minimap or {}
          setMinimapHidden(not db.minimap.hide)
          print("|cFF00FF00GrosOrteil|r icone minimap " .. (db.minimap.hide and "masquee" or "affichee") .. ".")
        end
      elseif cmd == "help" or cmd == "aide" then
        printHelp()
      else
        print("|cFF00FF00GrosOrteil|r commande inconnue : « " .. cmd .. " ». Tapez /go help pour la liste.")
      end
    end
  end
end)
