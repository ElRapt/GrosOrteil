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
local GetTime  = rawget(_G, "GetTime")

local MAX_HEAL = 1000000  -- sanity cap on a single heal

-- No-answer warning: if the target neither accepts nor refuses within this
-- delay, tell the healer (target offline, addon missing, popup ignored...).
Heal.RESPONSE_TIMEOUT = 10
-- Per-sender floor between incoming heal popups, so a misbehaving peer can't
-- spam StaticPopups.
Heal.REQUEST_MIN_INTERVAL = 2

local function now()
  return (GetTime and GetTime()) or 0
end

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

-- Chat line shown to the healer once the target answers. An accepted heal
-- that applied 0 PV (full HP or wound cap) gets its own wording — "accepté
-- votre soin de 0" read like a bug.
function Heal.FormatResponseMessage(targetDisplay, accepted, amount)
  local who = targetDisplay or "Quelqu'un"
  if accepted then
    if (tonumber(amount) or 0) <= 0 then
      return string.format(
        "%s a accepté votre soin, mais il n'a eu aucun effet (PV déjà au plafond).", who)
    end
    return string.format("%s a accepté votre soin de %d.", who, amount or 0)
  end
  return string.format("%s a refusé votre soin de %d.", who, amount or 0)
end

-- ── Pending requests (healer side) & per-sender throttle (target side) ────────

local function nameKey(name)
  local Shared = ns.Shared
  if Shared and Shared.NormalizeNameKey then
    return Shared.NormalizeNameKey(name)
  end
  return type(name) == "string" and name:lower() or nil
end

local pendingByTarget = {}   -- key → { amount, t }
local lastRequestFrom = {}   -- key → time of last accepted incoming popup

function Heal.MarkPending(target, amount, t, toPet)
  local k = nameKey(target)
  if not k then return end
  pendingByTarget[k] = { amount = amount, t = t or now(), pet = toPet and true or nil }
end

-- Was the pending request for this target aimed at their pet? (Read before
-- ClearPending — used by OnResponse for the chat wording.)
function Heal.PendingIsPet(target)
  local k = nameKey(target)
  local entry = k and pendingByTarget[k]
  return (entry and entry.pet) and true or false
end

function Heal.ClearPending(target)
  local k = nameKey(target)
  if k then pendingByTarget[k] = nil end
end

function Heal.HasPending(target)
  local k = nameKey(target)
  if not k then return false end
  return pendingByTarget[k] ~= nil
end

-- Expire a pending request if its timeout elapsed; returns true when it did.
-- Safe against early timers (the offline mock fires C_Timer synchronously):
-- a callback arriving before the deadline is a no-op.
function Heal.ExpirePending(target, t)
  local k = nameKey(target)
  local entry = k and pendingByTarget[k]
  if not entry then return false end
  if ((t or now()) - (entry.t or 0)) < Heal.RESPONSE_TIMEOUT then return false end
  pendingByTarget[k] = nil
  return true
end

-- Target side: accept at most one incoming heal popup per sender per
-- REQUEST_MIN_INTERVAL. Records the accepted time.
function Heal.ShouldAcceptRequest(sender, t)
  local k = nameKey(sender)
  if not k then return false end
  t = t or now()
  local last = lastRequestFrom[k]
  if last and (t - last) < Heal.REQUEST_MIN_INTERVAL then return false end
  lastRequestFrom[k] = t
  return true
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
-- Tracks the request so the healer is warned when no answer ever comes back
-- (target offline, addon missing, popup ignored).
function Heal.SendRequest(targetName, amount, toPet)
  local amt = Heal.SanitizeAmount(amount)
  if not targetName or targetName == "" or not amt then return false end
  if ns.Comm and ns.Comm.SendHealRequest then
    ns.Comm:SendHealRequest(targetName, amt, toPet)
  end
  Heal.MarkPending(targetName, amt, nil, toPet)
  local cTimer = rawget(_G, "C_Timer")
  if cTimer and cTimer.After then
    cTimer.After(Heal.RESPONSE_TIMEOUT + 0.5, function()
      if Heal.ExpirePending(targetName) then
        chat(string.format(
          "Aucune réponse de %s — addon absent, joueur hors ligne ou demande ignorée.",
          rpName(targetName)))
      end
    end)
  end
  return true
end

-- Prompt the healer for an amount, then send. (UI; no-op without StaticPopup.)
-- With toPet, the request targets the member's pet: the prompt shows the pet
-- name and the heal is applied to the pet on acceptance.
function Heal.PromptAndSend(targetName, toPet, petName)
  if not targetName or targetName == "" then return end
  local show = rawget(_G, "StaticPopup_Show")
  if not show then return end
  local display = rpName(targetName)
  if toPet then
    display = string.format("%s (familier de %s)", petName or "Familier", display)
  end
  show("GROSORTEIL_HEAL_INPUT", display, nil,
    { name = targetName, pet = toPet and true or nil })
end

-- A response came back from the target. On acceptance the response carries
-- the amount actually applied (post wound-cap); credit it to our "Soins"
-- group-meter counter — that counter only tracks heals given to others.
function Heal:OnResponse(targetName, accepted, amount)
  local _ = self
  local wasPet = Heal.PendingIsPet(targetName)
  Heal.ClearPending(targetName)
  local amt = Heal.SanitizeAmount(amount) or 0
  if accepted and amt > 0 and ns.Core and ns.Core.CreditHealGiven then
    ns.Core.CreditHealGiven(amt)
  end
  local who = rpName(targetName)
  if wasPet then
    who = string.format("Le familier de %s", who)
  end
  chat(Heal.FormatResponseMessage(who, accepted, amt))
end

-- ── Target side ───────────────────────────────────────────────────────────────

-- An incoming heal request. (UI; no-op without StaticPopup.)
-- Per-sender throttled so a misbehaving peer can't spam popups.
-- A pet-targeted request with no enabled pet is auto-refused: there is
-- nothing to heal and the healer deserves an answer instead of a timeout.
function Heal:OnRequest(healerName, amount, toPet)
  local _ = self
  local amt = Heal.SanitizeAmount(amount)
  if not healerName or healerName == "" or not amt then return end
  if not Heal.ShouldAcceptRequest(healerName) then return end
  if toPet then
    local pet = ns.Core and ns.Core.state and ns.Core.state.pet
    if type(pet) ~= "table" or not pet.enabled then
      Heal.Refuse(healerName, amt)
      return
    end
  end
  local show = rawget(_G, "StaticPopup_Show")
  if not show then return end
  show(toPet and "GROSORTEIL_HEAL_REQUEST_PET" or "GROSORTEIL_HEAL_REQUEST",
    rpName(healerName), amt,
    { healer = healerName, amount = amt, pet = toPet and true or nil })
end

-- Accept: apply the heal locally (same path as a heal Action) + notify healer.
-- The response reports the HP actually gained (the wound cap may shave the
-- requested amount) so the healer's meter is credited with real healing.
function Heal.Accept(healerName, amount, toPet)
  local amt = Heal.SanitizeAmount(amount)
  if not amt then return end
  local applied = amt
  if toPet and ns.Core and ns.Core.PetHealFrom then
    local pet = ns.Core.state and ns.Core.state.pet
    local before = type(pet) == "table" and (pet.hp or 0) or nil
    ns.Core.PetHealFrom(amt, rpName(healerName))
    if before and type(pet) == "table" then
      applied = math.max(0, (pet.hp or 0) - before)
    end
  elseif ns.Core and ns.Core.HealFrom then
    local s = ns.Core.state
    local before = s and (s.hp or 0)
    ns.Core.HealFrom(amt, rpName(healerName))
    if before and s then
      applied = math.max(0, (s.hp or 0) - before)
    end
  end
  if ns.Comm and ns.Comm.SendHealResponse then
    ns.Comm:SendHealResponse(healerName, true, applied)
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
      Heal.SendRequest(self.data and self.data.name, eb and eb:GetText(),
        self.data and self.data.pet)
    end,
    EditBoxOnEnterPressed = function(self)
      local parent = self:GetParent()
      Heal.SendRequest(parent.data and parent.data.name, self:GetText(),
        parent.data and parent.data.pet)
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

  dialogs["GROSORTEIL_HEAL_REQUEST_PET"] = {
    text     = "%s souhaite soigner votre familier de %d PV.",
    button1  = "Accepter",
    button2  = "Refuser",
    OnAccept = function(self) Heal.Accept(self.data.healer, self.data.amount, true) end,
    OnCancel = function(self) Heal.Refuse(self.data.healer, self.data.amount) end,
    timeout = 0, whileDead = true, hideOnEscape = true,
  }
end
