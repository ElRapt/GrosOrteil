-- Focused production-route synchronization regressions: lua tests/run_raid_sync.lua
package.path = "tests/?.lua;" .. package.path
local mocks = require("mocks")
mocks.install()
local frames = require("ui_mocks")
frames.install()
local loader = require("load")
local ns = loader.load(true)
frames.fire("ADDON_LOADED", "GrosOrteil")
frames.fire("PLAYER_LOGIN")
local T = require("framework")

-- Controlled timer order, including timers scheduled by timer callbacks.
local timers = {}
mocks.fakeNow = 100
C_Timer.After = function(delay, fn)
  timers[#timers + 1] = { at = mocks.fakeNow + delay, fn = fn }
end
local function advance(seconds)
  local deadline = mocks.fakeNow + seconds
  while true do
    local index
    for i, timer in ipairs(timers) do
      if timer.at <= deadline and (not index or timer.at < timers[index].at) then index = i end
    end
    if not index then break end
    local timer = table.remove(timers, index)
    mocks.fakeNow = timer.at
    timer.fn()
  end
  mocks.fakeNow = deadline
end
local function roster(units)
  mocks.units = units
  IsInRaid = function() return true end
  IsInGroup = function() return true end
end
local function requestsFor(name)
  local count = 0
  for _, m in ipairs(mocks.sentMessages) do
    if m.msg == "REQUEST_STATE" and m.target == name then count = count + 1 end
  end
  return count
end
local function stateMessages(channel)
  local messages = {}
  for _, m in ipairs(mocks.sentMessages) do
    if m.msg:match("^STATE_DATA") and (not channel or m.channel == channel) then
      messages[#messages + 1] = m
    end
  end
  return messages
end
local function receive(client, messages, sender)
  for _, m in ipairs(messages) do
    client.Comm:OnChatMsgAddon(m.prefix, m.msg, m.channel, sender)
  end
end

T.describe("Raid synchronization through shipped modules", function()
  T.it("preserves every member when a legacy saved order names cross-realm twins", function()
    local members = {{name = "Twin-One"}, {name = "Twin-Two"}, {name = "Other"}}
    local ordered = ns.RaidPanel._applySavedOrder(members, {"twin"})
    T.assertEq(#ordered, 3)
    T.assertEq(ordered[1], members[1]); T.assertEq(ordered[2], members[2])
  end)

  T.it("leaves an unknown realm profile empty instead of borrowing its namesake", function()
    ns.TargetPopup:OnStateReceived("Namesake-One", {hp = 12, maxHp = 100})
    ns.MeterSync.Store("Namesake-One", 30, 40)
    T.assertNil(ns.TargetPopup.GetCachedState("Namesake-Two"))
    T.assertNil(ns.MeterSync.Get("Namesake-Two"))
    T.assertEq(ns.TargetPopup.GetCachedState("Namesake-One").hp, 12)
  end)

  T.it("keeps realm-qualified roster profiles distinct through rendering and requests", function()
    roster({ player = { name = "Viewer", realm = "Home" },
      raid1 = { name = "Twin", realm = "One" }, raid2 = { name = "Twin", realm = "Two" } })
    ns.TargetPopup:OnStateReceived("Twin-One", { hp = 30, maxHp = 100 })
    ns.TargetPopup:OnStateReceived("Twin-Two", { hp = 80, maxHp = 100 })
    mocks.sentMessages = {}
    ns.RaidPanel.Show()
    local members = ns.RaidPanel._getRaidMembers()
    T.assertEq(members[1].name, "Twin-One")
    T.assertEq(members[2].name, "Twin-Two")
    local rows = ns.RaidPanel._collectData(members)
    T.assertEq(rows[1].hp, 30); T.assertEq(rows[2].hp, 80)
    T.assertEq(requestsFor("Twin-One"), 1); T.assertEq(requestsFor("Twin-Two"), 1)
  end)

  T.it("eventually requests the latest roster when refreshes arrive inside the cooldown", function()
    advance(10)
    roster({ player = { name = "Viewer", realm = "Home" }, raid1 = { name = "Early", realm = "One" } })
    ns.RaidPanel.Show()
    mocks.sentMessages = {}
    mocks.units.raid2 = { name = "Late", realm = "Two" }
    frames.fire("GROUP_ROSTER_UPDATE")
    frames.fire("GROUP_ROSTER_UPDATE")
    advance(3)
    T.assertEq(requestsFor("Late-Two") + requestsFor("Late"), 1,
      "a suppressed roster refresh must run after cooldown")
  end)

  T.it("answers a cooldown-blocked request with the latest state once", function()
    advance(10)
    ns.Comm.lastRequestServed = {}
    ns.Comm:OnChatMsgAddon(ns.Comm.PREFIX, "REQUEST_STATE", "WHISPER", "Reader-Realm")
    mocks.sentMessages = {}
    ns.Core.SetHP(67, 100)
    ns.Comm:OnChatMsgAddon(ns.Comm.PREFIX, "REQUEST_STATE", "WHISPER", "Reader-Realm")
    ns.Comm:OnChatMsgAddon(ns.Comm.PREFIX, "REQUEST_STATE", "WHISPER", "Reader-Realm")
    T.assertEq(#stateMessages("WHISPER"), 0)
    advance(ns.Comm.RESPONSE_COOLDOWN)
    local messages = stateMessages("WHISPER")
    T.assertTrue(#messages > 0, "the throttled refresh was dropped")
    receive(ns, messages, "Respondent-Realm")
    T.assertEq(ns.TargetPopup.GetCachedState("Respondent-Realm").hp, 67)
  end)

  T.it("pushes full state changes to two viewers even with the owner's panel closed", function()
    local peer = loader.load()
    assert(loadfile("GrosOrteil_Guard.lua"))("GrosOrteil", peer)
    peer.Core.ResetToDefaults()
    roster({player = {name = "Viewer", realm = "Home"}, raid1 = {name = "Owner", realm = "Realm"}})
    ns.RaidPanel.Show()
    advance(1)
    mocks.sentMessages = {}
    peer.Core.SetHP(77, 100)
    peer.Core.SetResIndex(1, 19, 100)
    peer.Core.SetPetEnabled(true)
    peer.Core.SetPetHP(23, 40)
    advance(0)
    local messages = stateMessages("RAID")
    T.assertTrue(#messages > 0, "Core mutations must publish full profiles")
    local arrivals = 0
    local unsubscribe = ns.TargetPopup.OnStateArrived(function(sender)
      if sender == "Owner-Realm" then arrivals = arrivals + 1 end
    end)
    receive(ns, messages, "Owner-Realm")
    unsubscribe()
    T.assertEq(arrivals, 1, "same-frame mutations should send one complete snapshot")
    receive(peer, messages, "Owner-Realm")
    for _, viewer in ipairs({ns, peer}) do
      local rows = viewer.RaidPanel._collectData({{name = "Owner-Realm"}})
      T.assertEq(rows[1].hp, 77)
      T.assertEq(rows[1].resources[1].cur, 19)
      T.assertEq(rows[1].pet.hp, 23)
    end
    local card
    for _, f in ipairs(frames.frames) do
      if f._name == "Owner-Realm" and f._unit == "raid1" and f.hp and f:IsShown() then card = f end
    end
    T.assertNotNil(card, "incoming state must render the visible raid card")
    T.assertEq(card.hp.bar:GetValue(), 77)
  end)

  T.it("assembles interleaved raid and whisper snapshots independently", function()
    local seen = {}
    local unsubscribe = ns.TargetPopup.OnStateArrived(function(sender, state)
      if sender == "Stream-Realm" then seen[#seen + 1] = state.hp end
    end)
    local raid = ns.Comm.SerializeState({hp = 21, maxHp = 100})
    local whisper = ns.Comm.SerializeState({hp = 87, maxHp = 100})
    local count = math.ceil(#raid / 200)
    T.assertEq(math.ceil(#whisper / 200), count)
    for i = 1, count do
      for _, stream in ipairs({{raid, "RAID"}, {whisper, "WHISPER"}}) do
        ns.Comm:OnChatMsgAddon(ns.Comm.PREFIX,
          string.format("STATE_DATA_PART:%d:%d:%s", count, i, stream[1]:sub((i-1)*200+1, i*200)),
          stream[2], "Stream-Realm")
      end
    end
    unsubscribe()
    T.assertDeepEq(seen, {21, 87})
  end)

  T.it("announces a full snapshot on world entry without a stat mutation", function()
    advance(10)
    mocks.sentMessages = {}
    ns.Comm.eventFrame:RunScript("OnEvent", "PLAYER_ENTERING_WORLD")
    advance(0)
    T.assertTrue(#stateMessages("RAID") > 0)
  end)

  T.it("uses party and instance channels and cancels a queued broadcast after leaving", function()
    advance(10)
    IsInRaid = function() return false end
    IsInGroup = function(category) return category == nil end
    for _, channel in ipairs({"PARTY", "INSTANCE_CHAT"}) do
      if channel == "INSTANCE_CHAT" then
        LE_PARTY_CATEGORY_INSTANCE = 2
        IsInGroup = function() return true end
      end
      mocks.sentMessages = {}
      ns.Comm.eventFrame:RunScript("OnEvent", "GROUP_ROSTER_UPDATE")
      advance(0)
      T.assertTrue(#stateMessages(channel) > 0, channel)
    end
    mocks.sentMessages = {}
    ns.Core.SetHP(56, 100)
    IsInGroup = function() return false end
    advance(0)
    T.assertEq(#stateMessages(), 0)
  end)

  T.it("retains direct whisper state replies while solo", function()
    IsInRaid = function() return false end
    IsInGroup = function() return false end
    advance(10)
    mocks.sentMessages = {}
    ns.Core.SetHP(55, 100)
    advance(0)
    T.assertEq(#stateMessages(), 0)
    ns.Comm:SendStateData("SoloReader-Realm")
    local messages = stateMessages()
    T.assertTrue(#messages > 0)
    for _, m in ipairs(messages) do
      T.assertEq(m.channel, "WHISPER"); T.assertEq(m.target, "SoloReader-Realm")
    end
    T.assertEq(#mocks.errorHandlerCalls, 0, table.concat(mocks.errorHandlerCalls, "\n"))
  end)
end)
os.exit(T.run({verbose = true}) and 0 or 1)
