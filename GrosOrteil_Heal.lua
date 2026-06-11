---@diagnostic disable: undefined-global
-- Raid-panel heal handshake.
--   Healer:  picks a target, enters an amount  -> SendRequest (HEAL_REQ)
--   Target:  popup Accepter/Refuser
--             accept -> Core.HealFrom (same event as a heal Action) + HEAL_RESP(1)
--             refuse -> HEAL_RESP(0)
--   Healer:  OnResponse -> chat line telling them accepted / refused
local _, ns = ...

local Heal = {}
ns.Heal = Heal

local type     = type
local math     = math
local tonumber = tonumber
local string   = string

local MAX_HEAL = 1000000  -- sanity cap on a single heal

-- ── Pure helpers (testable offline) ───────────────────────────────────────────

-- Returns a positive integer, or nil when x is not a usable heal amount.
function Heal.SanitizeAmount(x)
  local n = tonumber(x)
  if not n then return nil end
  n = math.floor(n)
  if n <= 0 then return nil end
  if n > MAX_HEAL then n = MAX_HEAL end
  return n
end

-- Chat line shown to the healer once the target answers.
function Heal.FormatResponseMessage(targetDisplay, accepted, amount)
  local who = targetDisplay or "Quelqu'un"
  if accepted then
    return string.format("%s a accepté votre soin de %d.", who, amount or 0)
  end
  return string.format("%s a refusé votre soin de %d.", who, amount or 0)
end

-- ── Small guarded utilities ───────────────────────────────────────────────────

local function rpName(name)
  local popup = ns.TargetPopup
  if popup and popup.GetRPDisplayName then
    return popup.GetRPDisplayName(name) or name
  end
  return name
end

local function chat(msg)
  local p = rawget(_G, "print")
  if p then p("|cFF66CC66GrosOrteil|r " .. msg) end
end

-- ── Healer side ───────────────────────────────────────────────────────────────

-- Validate + send a heal request. Returns true if a request went out.
function Heal.SendRequest(targetName, amount)
  local amt = Heal.SanitizeAmount(amount)
  if not targetName or targetName == "" or not amt then return false end
  if ns.Comm and ns.Comm.SendHealRequest then
    ns.Comm:SendHealRequest(targetName, amt)
  end
  return true
end

-- Prompt the healer for an amount, then send. (UI; no-op without StaticPopup.)
function Heal.PromptAndSend(targetName)
  if not targetName or targetName == "" then return end
  local show = rawget(_G, "StaticPopup_Show")
  if not show then return end
  show("GROSORTEIL_HEAL_INPUT", rpName(targetName), nil, { name = targetName })
end

-- A response came back from the target.
function Heal:OnResponse(targetName, accepted, amount)
  local _ = self
  local amt = Heal.SanitizeAmount(amount) or 0
  chat(Heal.FormatResponseMessage(rpName(targetName), accepted, amt))
end

-- ── Target side ───────────────────────────────────────────────────────────────

-- An incoming heal request. (UI; no-op without StaticPopup.)
function Heal:OnRequest(healerName, amount)
  local _ = self
  local amt = Heal.SanitizeAmount(amount)
  if not healerName or healerName == "" or not amt then return end
  local show = rawget(_G, "StaticPopup_Show")
  if not show then return end
  show("GROSORTEIL_HEAL_REQUEST", rpName(healerName), amt,
    { healer = healerName, amount = amt })
end

-- Accept: apply the heal locally (same path as a heal Action) + notify healer.
function Heal.Accept(healerName, amount)
  local amt = Heal.SanitizeAmount(amount)
  if not amt then return end
  if ns.Core and ns.Core.HealFrom then
    ns.Core.HealFrom(amt, rpName(healerName))
  end
  if ns.Comm and ns.Comm.SendHealResponse then
    ns.Comm:SendHealResponse(healerName, true, amt)
  end
end

-- Refuse: notify the healer only.
function Heal.Refuse(healerName, amount)
  local amt = Heal.SanitizeAmount(amount) or 0
  if ns.Comm and ns.Comm.SendHealResponse then
    ns.Comm:SendHealResponse(healerName, false, amt)
  end
end

-- ── StaticPopup registration (WoW-only; called at PLAYER_LOGIN) ────────────────

function ns.Heal_Init()
  local dialogs = rawget(_G, "StaticPopupDialogs")
  if type(dialogs) ~= "table" then return end

  local function editBoxOf(self)
    if self.editBox then return self.editBox end
    if self.GetEditBox then return self:GetEditBox() end
    return nil
  end

  dialogs["GROSORTEIL_HEAL_INPUT"] = {
    text       = "Soigner %s de combien de PV ?",
    button1    = rawget(_G, "ACCEPT") or "Accepter",
    button2    = rawget(_G, "CANCEL") or "Annuler",
    hasEditBox = true,
    maxLetters = 9,
    OnShow = function(self)
      local eb = editBoxOf(self)
      if eb then eb:SetNumeric(true); eb:SetText(""); eb:SetFocus() end
    end,
    OnAccept = function(self)
      local eb = editBoxOf(self)
      Heal.SendRequest(self.data and self.data.name, eb and eb:GetText())
    end,
    EditBoxOnEnterPressed = function(self)
      local parent = self:GetParent()
      Heal.SendRequest(parent.data and parent.data.name, self:GetText())
      parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
  }

  dialogs["GROSORTEIL_HEAL_REQUEST"] = {
    text     = "%s souhaite vous soigner de %d PV.",
    button1  = "Accepter",
    button2  = "Refuser",
    OnAccept = function(self) Heal.Accept(self.data.healer, self.data.amount) end,
    OnCancel = function(self) Heal.Refuse(self.data.healer, self.data.amount) end,
    timeout = 0, whileDead = true, hideOnEscape = true,
  }
end
