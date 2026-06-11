---@diagnostic disable: undefined-global
local T    = _G.T
local ns   = _G.NS
local Heal = ns.Heal
local Comm = ns.Comm
local Core = ns.Core

local function lastSent()
  local s = _G.MOCKS.sentMessages
  return s[#s]
end

-- ── Heal.SanitizeAmount ───────────────────────────────────────────────────────

T.describe("Heal.SanitizeAmount", function()
  T.it("accepts positive integers", function()
    T.assertEq(Heal.SanitizeAmount(25), 25)
    T.assertEq(Heal.SanitizeAmount("30"), 30)
  end)
  T.it("floors fractional values", function()
    T.assertEq(Heal.SanitizeAmount(25.9), 25)
  end)
  T.it("rejects zero and negatives", function()
    T.assertNil(Heal.SanitizeAmount(0))
    T.assertNil(Heal.SanitizeAmount(-5))
  end)
  T.it("rejects non-numbers", function()
    T.assertNil(Heal.SanitizeAmount("abc"))
    T.assertNil(Heal.SanitizeAmount(nil))
    T.assertNil(Heal.SanitizeAmount({}))
  end)
  T.it("clamps absurdly large values to the cap", function()
    T.assertEq(Heal.SanitizeAmount(2e9), 1000000)
  end)
end)

-- ── Heal.FormatResponseMessage ────────────────────────────────────────────────

T.describe("Heal.FormatResponseMessage", function()
  T.it("accepted message mentions the amount and 'accepté'", function()
    local m = Heal.FormatResponseMessage("Bob", true, 40)
    T.assertTrue(m:find("Bob") ~= nil)
    T.assertTrue(m:find("accept") ~= nil)
    T.assertTrue(m:find("40") ~= nil)
  end)
  T.it("refused message says 'refusé'", function()
    local m = Heal.FormatResponseMessage("Bob", false, 40)
    T.assertTrue(m:find("refus") ~= nil)
  end)
  T.it("nil target falls back to a placeholder", function()
    local m = Heal.FormatResponseMessage(nil, true, 5)
    T.assertTrue(m:find("Quelqu") ~= nil)
  end)
end)

-- ── Heal.SendRequest (healer -> target) ───────────────────────────────────────

T.describe("Heal.SendRequest", function()
  T.it("sends HEAL_REQ:<amount> as a whisper to the target", function()
    _G.MOCKS.sentMessages = {}
    local ok = Heal.SendRequest("Bob", 30)
    T.assertTrue(ok)
    local m = lastSent()
    T.assertEq(m.msg, "HEAL_REQ:30")
    T.assertEq(m.channel, "WHISPER")
    T.assertEq(m.target, "Bob")
  end)
  T.it("rejects an invalid amount without sending", function()
    _G.MOCKS.sentMessages = {}
    T.assertFalse(Heal.SendRequest("Bob", 0))
    T.assertEq(#_G.MOCKS.sentMessages, 0)
  end)
  T.it("rejects an empty target without sending", function()
    _G.MOCKS.sentMessages = {}
    T.assertFalse(Heal.SendRequest("", 30))
    T.assertEq(#_G.MOCKS.sentMessages, 0)
  end)
end)

-- ── Heal.Accept (target side) ─────────────────────────────────────────────────

T.describe("Heal.Accept", function()
  T.it("applies the heal to the local state and records it in history", function()
    Core.SetHP(50, 100)
    _G.MOCKS.sentMessages = {}
    Heal.Accept("Healer", 20)
    T.assertTrue(Core.state.hp > 50, "HP should have increased")
    local hist = Core.GetHistory()
    T.assertEq(hist[1].kind, "HEAL")
    T.assertEq(hist[1].healer, "Healer")
  end)

  T.it("sends HEAL_RESP:1:<amount> back to the healer", function()
    Core.SetHP(50, 100)
    _G.MOCKS.sentMessages = {}
    Heal.Accept("Healer", 20)
    local m = lastSent()
    T.assertEq(m.msg, "HEAL_RESP:1:20")
    T.assertEq(m.channel, "WHISPER")
    T.assertEq(m.target, "Healer")
  end)

  T.it("does nothing for an invalid amount", function()
    Core.SetHP(50, 100)
    _G.MOCKS.sentMessages = {}
    Heal.Accept("Healer", 0)
    T.assertEq(Core.state.hp, 50)
    T.assertEq(#_G.MOCKS.sentMessages, 0)
  end)
end)

-- ── Heal.Refuse (target side) ─────────────────────────────────────────────────

T.describe("Heal.Refuse", function()
  T.it("sends HEAL_RESP:0:<amount> and does not heal", function()
    Core.SetHP(50, 100)
    _G.MOCKS.sentMessages = {}
    Heal.Refuse("Healer", 20)
    T.assertEq(Core.state.hp, 50)
    local m = lastSent()
    T.assertEq(m.msg, "HEAL_RESP:0:20")
    T.assertEq(m.target, "Healer")
  end)
end)

-- ── Comm dispatch routes heal messages to the Heal module ─────────────────────

T.describe("Comm dispatch -> Heal", function()
  T.it("HEAL_REQ is routed to Heal:OnRequest(sender, amount)", function()
    local gotSender, gotAmount
    local saved = Heal.OnRequest
    Heal.OnRequest = function(_, sender, amount) gotSender, gotAmount = sender, amount end
    Comm:OnChatMsgAddon(Comm.PREFIX, "HEAL_REQ:40", "WHISPER", "Bob")
    Heal.OnRequest = saved
    T.assertEq(gotSender, "Bob")
    T.assertEq(gotAmount, 40)
  end)

  T.it("HEAL_RESP is routed to Heal:OnResponse with parsed accept flag + amount", function()
    local gotSender, gotAccepted, gotAmount
    local saved = Heal.OnResponse
    Heal.OnResponse = function(_, sender, accepted, amount)
      gotSender, gotAccepted, gotAmount = sender, accepted, amount
    end
    Comm:OnChatMsgAddon(Comm.PREFIX, "HEAL_RESP:1:40", "WHISPER", "Bob")
    T.assertEq(gotSender, "Bob")
    T.assertTrue(gotAccepted)
    T.assertEq(gotAmount, 40)

    Comm:OnChatMsgAddon(Comm.PREFIX, "HEAL_RESP:0:15", "WHISPER", "Bob")
    T.assertFalse(gotAccepted)
    T.assertEq(gotAmount, 15)

    Heal.OnResponse = saved
  end)

  T.it("ignores heal messages with a foreign prefix", function()
    local called = false
    local saved = Heal.OnRequest
    Heal.OnRequest = function() called = true end
    Comm:OnChatMsgAddon("SOME_OTHER_PREFIX", "HEAL_REQ:40", "WHISPER", "Bob")
    Heal.OnRequest = saved
    T.assertFalse(called)
  end)
end)
