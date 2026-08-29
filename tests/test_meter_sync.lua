---@diagnostic disable: undefined-global
local T = _G.T
local ns = _G.NS
local Comm = ns.Comm
local Core = ns.Core
local Popup = ns.TargetPopup
local MeterSync = ns.MeterSync

T.describe("MeterSync live counter synchronization", function()
  T.it("overlays live totals onto cached peer state", function()
    Popup.InjectState("Alice-Realm", {
      hp = 50, maxHp = 100, classKey = "MAGE",
      meter = { dmg = 10, heal = 20 },
    })

    MeterSync.Store("Alice-Realm", 123, 456)
    local state = Popup.GetCachedState("Alice")

    T.assertNotNil(state)
    T.assertEq(state.hp, 50)
    T.assertEq(state.classKey, "MAGE")
    T.assertEq(state.meter.dmg, 123)
    T.assertEq(state.meter.heal, 456)
  end)

  T.it("does not mutate the underlying cached state table", function()
    local original = {
      hp = 77, maxHp = 100, classKey = "PRIEST",
      meter = { dmg = 5, heal = 6 },
    }
    Popup.InjectState("Bob", original)
    MeterSync.Store("Bob", 900, 901)

    local merged = Popup.GetCachedState("Bob")
    T.assertEq(merged.meter.dmg, 900)
    T.assertEq(merged.meter.heal, 901)
    T.assertEq(original.meter.dmg, 5)
    T.assertEq(original.meter.heal, 6)
  end)

  T.it("parses METER_STATE messages through Comm dispatcher", function()
    Comm:OnChatMsgAddon(Comm.PREFIX, "METER_STATE:42:84", "PARTY", "Charlie-Realm")
    local totals = MeterSync.Get("Charlie")
    T.assertNotNil(totals)
    T.assertEq(totals.dmg, 42)
    T.assertEq(totals.heal, 84)
  end)

  T.it("answers METER_REQUEST with authoritative local totals", function()
    Core.ResetToDefaults()
    Core.state.meter.dmg = 321
    Core.state.meter.heal = 654
    _G.MOCKS.sentMessages = {}

    Comm:OnChatMsgAddon(Comm.PREFIX, "METER_REQUEST", "WHISPER", "Requester")

    T.assertEq(#_G.MOCKS.sentMessages, 1)
    local msg = _G.MOCKS.sentMessages[1]
    T.assertEq(msg.channel, "WHISPER")
    T.assertEq(msg.target, "Requester")
    T.assertEq(msg.msg, "METER_STATE:321:654")
  end)

  T.it("pairs every normal state request with a meter refresh request", function()
    _G.MOCKS.sentMessages = {}
    Comm:RequestState("Peer")

    local sawState, sawMeter = false, false
    for _, msg in ipairs(_G.MOCKS.sentMessages) do
      if msg.target == "Peer" and msg.msg == "REQUEST_STATE" then sawState = true end
      if msg.target == "Peer" and msg.msg == "METER_REQUEST" then sawMeter = true end
    end
    T.assertTrue(sawState, "normal state request should still be sent")
    T.assertTrue(sawMeter, "meter refresh request should accompany it")
  end)

  T.it("broadcasts changed local counters to the group", function()
    local oldIsInGroup, oldIsInRaid = _G.IsInGroup, _G.IsInRaid
    _G.IsInRaid = function() return false end
    _G.IsInGroup = function() return true end

    Core.ResetToDefaults()
    Core.state.meter.dmg = 11
    Core.state.meter.heal = 22
    _G.MOCKS.sentMessages = {}

    local sent = MeterSync.BroadcastIfChanged(true)
    T.assertTrue(sent)
    T.assertEq(#_G.MOCKS.sentMessages, 1)
    T.assertEq(_G.MOCKS.sentMessages[1].channel, "PARTY")
    T.assertEq(_G.MOCKS.sentMessages[1].msg, "METER_STATE:11:22")

    _G.IsInGroup, _G.IsInRaid = oldIsInGroup, oldIsInRaid
  end)

  T.it("does not rebroadcast unchanged counters without force", function()
    local oldIsInGroup, oldIsInRaid = _G.IsInGroup, _G.IsInRaid
    _G.IsInRaid = function() return false end
    _G.IsInGroup = function() return true end

    Core.state.meter.dmg = 101
    Core.state.meter.heal = 202
    MeterSync.BroadcastIfChanged(true)
    _G.MOCKS.sentMessages = {}

    T.assertFalse(MeterSync.BroadcastIfChanged(false))
    T.assertEq(#_G.MOCKS.sentMessages, 0)

    _G.IsInGroup, _G.IsInRaid = oldIsInGroup, oldIsInRaid
  end)
end)
