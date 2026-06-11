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
        tt:AddLine("Clic gauche: afficher/masquer la fenetre", 0.8, 0.8, 0.8)
        tt:AddLine("Clic droit: panel de raid", 0.8, 0.8, 0.8)
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
    initMinimapIcon()

    f:UnregisterEvent("ADDON_LOADED")
    f:UnregisterEvent("PLAYER_LOGIN")

    _G.SLASH_GROSORTEIL1 = "/grosorteil"
    _G.SLASH_GROSORTEIL2 = "/go"
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
      elseif cmd == "raidtest" then
        local SIM = {
          { name="Archimonde",  classKey="MAGE",        hp=80,  maxHp=100, res=70, maxRes=100 },
          { name="Illidan",     classKey="WARLOCK",      hp=45,  maxHp=120, res=50, maxRes=100, res2=30, maxRes2=60, res3=2, maxRes3=5 },
          { name="Sylvanas",    classKey="SHADOWPRIEST", hp=0,   maxHp=90,  res=15, maxRes=100, res2=20, maxRes2=25, stabilise=true },
          { name="Thrall",      classKey="SHAMAN",       hp=95,  maxHp=110, res=88, maxRes=100, res3=1,  maxRes3=3,  res4=2,  maxRes4=3 },
          { name="Jaina",       classKey="MAGE",         hp=60,  maxHp=100, res=40, maxRes=100 },
          { name="Anduin",      classKey="PALADIN",      hp=100, maxHp=100, res=70, maxRes=100 },
          { name="Garrosh",     classKey="ROGUE",        hp=55,  maxHp=130, res=90, maxRes=100 },
          { name="Malfurion",   classKey="DRUID",        hp=0,   maxHp=120, stabilise=false },
          { name="Khadgar",     classKey="MONK",         hp=70,  maxHp=100, res=60, maxRes=100, res2=4, maxRes2=8 },
          { name="Tyrande",     classKey="MEDIC",        hp=85,  maxHp=100, res=55, maxRes=100 },
        }
        local names = {}
        if ns.TargetPopup then
          for _, s in ipairs(SIM) do
            ns.TargetPopup.InjectState(s.name, s)
            names[#names + 1] = { name = s.name }
          end
        end
        if ns.RaidPanel then
          ns.RaidPanel.Show({ members = names, skipRequest = true })
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
      else
        print("|cFF00FF00GrosOrteil|r commandes : /go (toggle) | /go show | /go hide | /go reset | /go clearhistory | /go class <CLASS> | /go pet | /go minimap [show|hide] | /go raid | /go raidtest")
      end
    end
  end
end)
