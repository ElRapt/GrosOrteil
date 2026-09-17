-- Focused lifecycle/transport/UI tests; no game client required.
package.path = "tests/?.lua;" .. package.path
local mocks = require("mocks")
mocks.install()
local frames = require("ui_mocks")
frames.install()
_G.Enum = { SendAddonMessageResult = { Success=0, AddonMessageThrottle=3, NotInGroup=5, GeneralError=9 } }
if arg and arg[1] == "ctl" then
  -- Exercise the bundled transport too, including its completion callbacks.
  _G.GetFramerate = function() return 60 end
  _G.securecallfunction = function(fn, ...) return fn(...) end
  _G.unpack = table.unpack or unpack
  table.wipe = function(t) for k in pairs(t) do t[k]=nil end; return t end
  local hook = hooksecurefunc
  _G.hooksecurefunc = function() end -- Traffic hooks are unrelated to queued sends.
  if _VERSION == "Lua 5.1" then
    local original = xpcall
    _G.xpcall = function(fn, handler, ...)
      local args, count = {...}, select("#", ...)
      return original(function() return fn(unpack(args, 1, count)) end, handler)
    end
  end
  dofile("Libs/ChatThrottleLib/ChatThrottleLib.lua")
  _G.hooksecurefunc = hook
end
local ns = require("load").load()
assert(loadfile("GrosOrteil_Typing.lua"))("GrosOrteil", ns)
local T = require("framework")
local active, timer, raid, party, instance
local nameplates = {}
local playerX, playerY, playerMap = 0, 0, 1
_G.UnitPosition = function() return playerX, playerY, 0, playerMap end
_G.IsInInstance = function() return false end
_G.GetNormalizedRealmName = function() return "TestRealm" end
_G.LE_PARTY_CATEGORY_HOME, _G.LE_PARTY_CATEGORY_INSTANCE = 1, 2
_G.IsInGroup = function(category) return category == 2 and instance or category ~= 2 and party end
_G.IsInRaid = function() return raid end
_G.ChatFrameUtil = { GetActiveWindow = function() return active end }
_G.ChatTypeInfo = { SAY={r=1,g=1,b=1}, PARTY={r=.5,g=.5,b=1}, RAID={r=1,g=.5,b=0},
  INSTANCE_CHAT={r=1,g=.5,b=0}, WHISPER={r=1,g=.5,b=1} }
_G.C_NamePlate = {
  GetNamePlateForUnit = function(unit) return nameplates[unit] end,
  GetNamePlates = function() local out={}; for _,p in pairs(nameplates) do out[#out+1]=p end; return out end,
}
_G.C_Timer.NewTicker = function(interval, callback)
  T.assertEq(interval, .2)
  timer = { callback=callback, Cancel=function(self) self.cancelled=true end }
  return timer
end
local typing = ns.Typing
typing.Initialize()
local summary = _G.GrosOrteilTypingSummary
local function reset()
  typing.SetEnabled(false)
  for unit in pairs(nameplates) do frames.fire("NAME_PLATE_UNIT_REMOVED",unit) end
  nameplates = {}
  mocks.units = { player={name="TestPlayer",realm="TestRealm",isPlayer=true} }
  mocks.fakeNow = (mocks.fakeNow or 0) + 100
  active, raid, party, instance = nil, false, false, false
  playerX, playerY, playerMap = 0, 0, 1
  typing.SetEnabled(true)
  mocks.sentMessages = {}
end
local function tick(dt)
  mocks.fakeNow = mocks.fakeNow + (dt or .2)
  assert(not timer.cancelled)
  timer.callback()
end
local function edit(channel, text, target)
  active = CreateFrame("EditBox",nil,UIParent)
  active:SetAttribute("chatType",channel)
  active:SetAttribute("tellTarget",target)
  active:SetText(text or "Bonjour")
  active:SetFocus()
  return active
end
local function receive(name, channel, activeFlag)
  channel = channel or "SAY"
  local payload = activeFlag == false and "0" or "1"
  if channel == "SAY" then
    payload = activeFlag == false and "SAY:0" or "SAY:1:1:0:0"
    channel = "CHANNEL"
  end
  ns.Comm:OnChatMsgAddon("GO_STATE", "TYPING:1:"..payload, channel, name)
end
local function plate(unit, name, realm)
  mocks.units[unit]={name=name,realm=realm or "TestRealm",isPlayer=true}
  local p=CreateFrame("Frame",nil,UIParent)
  p.namePlateUnitToken=unit
  nameplates[unit]=p
  frames.fire("NAME_PLATE_UNIT_ADDED",unit)
  return p
end
local function withDiagnostics(fn)
  local original,lines=print,{}
  _G.print=function(line) lines[#lines+1]=line end
  local ok,err=pcall(fn,lines)
  _G.print=original
  if not ok then error(err,0) end
end
T.describe("Typing indicators",function()
  T.it("previews a local whisper indicator through the receiver without network traffic",function()
    reset()
    withDiagnostics(function()
      typing.Debug("test")
      T.assertTrue(summary:IsShown())
      T.assertEq(summary.text:GetText(),"Test de saisie (local) écrit…")
      T.assertEq(summary.text._textColor[2],ChatTypeInfo.WHISPER.g)
      T.assertEq(#mocks.sentMessages,0)
      tick(7); T.assertFalse(summary:IsShown())
      typing.SetEnabled(false)
      typing.Debug("test"); T.assertFalse(summary:IsShown())
      T.assertEq(#mocks.sentMessages,0)
    end)
  end)
  T.it("checks an unpatched peer with the existing state request and reply protocol",function()
    reset()
    withDiagnostics(function(lines)
      typing.Debug("probe Sierafin-TestRealm")
      T.assertEq(#mocks.sentMessages,1)
      T.assertEq(mocks.sentMessages[1].msg,"REQUEST_STATE")
      T.assertEq(mocks.sentMessages[1].target,"Sierafin-TestRealm")
      local timeout=frames.timers[#frames.timers]
      local count=#lines
      ns.Comm:OnChatMsgAddon("GO_STATE","STATE_DATA:invalid","WHISPER","Other-TestRealm")
      ns.Comm:OnChatMsgAddon("GO_STATE","STATE_DATA:invalid","PARTY","Sierafin-TestRealm")
      T.assertEq(#lines,count)
      -- An existing peer handles REQUEST_STATE with its ordinary state sender.
      ns.Comm:SendStateData("TestPlayer-TestRealm")
      for i=2,#mocks.sentMessages do
        local msg=mocks.sentMessages[i]
        ns.Comm:OnChatMsgAddon(msg.prefix,msg.msg,msg.channel,"Sierafin-TestRealm")
      end
      T.assertEq(#lines,count+1)
      T.assertTrue(lines[#lines]:find("State reply received",1,true)~=nil)
      timeout(); T.assertEq(#lines,count+1)
    end)
  end)
  T.it("bounds peer checks and reports timeouts without claiming a delivery cause",function()
    reset()
    withDiagnostics(function(lines)
      typing.Debug("probe"); typing.Debug("probe TestPlayer-TestRealm")
      T.assertEq(#mocks.sentMessages,0)
      typing.Debug("probe Sierafin")
      local timeout=frames.timers[#frames.timers]
      typing.Debug("probe AnotherPlayer")
      T.assertEq(#mocks.sentMessages,1)
      timeout()
      T.assertTrue(lines[#lines]:find("No state reply",1,true)~=nil)
      typing.Debug("probe Sierafin")
      local cancelled=frames.timers[#frames.timers]
      typing.Debug("off")
      local count=#lines
      cancelled(); T.assertEq(#lines,count)
    end)
  end)
  T.it("reports a rejected peer check without a misleading timeout",function()
    reset()
    local send=C_ChatInfo.SendAddonMessage
    C_ChatInfo.SendAddonMessage=function() return Enum.SendAddonMessageResult.GeneralError end
    withDiagnostics(function(lines)
      typing.Debug("probe Sierafin")
      T.assertTrue(lines[#lines]:find("Network check send failed",1,true)~=nil)
      local count=#lines
      frames.timers[#frames.timers](); T.assertEq(#lines,count)
    end)
    C_ChatInfo.SendAddonMessage=send
  end)
  T.it("sends say status with no draft text and stops on send/close",function()
    reset(); edit("SAY","a private draft"); tick()
    T.assertEq(#mocks.sentMessages,1)
    T.assertEq(mocks.sentMessages[1].channel,"CHANNEL")
    T.assertEq(mocks.sentMessages[1].msg,"TYPING:1:SAY:1:1:0.00:0.00")
    active:SetText(""); tick()
    T.assertEq(mocks.sentMessages[2].msg,"TYPING:1:SAY:0")
    active=nil; tick(); T.assertEq(#mocks.sentMessages,2)
  end)
  T.it("routes party, raid and instance typing without a distance lookup",function()
    reset(); party=true; edit("PARTY"); tick()
    T.assertEq(mocks.sentMessages[1].channel,"PARTY")
    raid=true; active:SetAttribute("chatType","RAID"); tick(1)
    T.assertEq(mocks.sentMessages[2].channel,"PARTY")
    T.assertEq(mocks.sentMessages[2].msg,"TYPING:1:0")
    T.assertEq(mocks.sentMessages[3].channel,"RAID")
    instance=true; active:SetAttribute("chatType","INSTANCE_CHAT"); tick(1)
    T.assertEq(mocks.sentMessages[5].channel,"INSTANCE_CHAT")
  end)
  T.it("finds the focused normal chat box when the active pointer is absent or stale",function()
    reset(); local box=edit("WHISPER","private draft","Alice-TestRealm")
    local chats,default=CHAT_FRAMES,DEFAULT_CHAT_FRAME
    _G.CHAT_FRAMES={"TypingTestChat"}
    _G.TypingTestChat={editBox=box}
    active=nil; tick()
    T.assertEq(mocks.sentMessages[1].channel,"WHISPER")
    active=CreateFrame("EditBox",nil,UIParent)
    box:SetText("still typing"); tick(3)
    T.assertEq(mocks.sentMessages[2].msg,"TYPING:1:1")
    _G.CHAT_FRAMES=nil; _G.DEFAULT_CHAT_FRAME={editBox=box}
    tick(3); T.assertEq(mocks.sentMessages[3].msg,"TYPING:1:1")
    box:ClearFocus(); tick()
    T.assertEq(mocks.sentMessages[4].msg,"TYPING:1:0")
    _G.CHAT_FRAMES,_G.DEFAULT_CHAT_FRAME=chats,default
    _G.TypingTestChat=nil
  end)
  T.it("reports rejected sends and bounds retries instead of announcing success",function()
    reset(); edit("WHISPER","private draft","Alice-TestRealm")
    local send,attempts=C_ChatInfo.SendAddonMessage,0
    C_ChatInfo.SendAddonMessage=function() attempts=attempts+1; return Enum.SendAddonMessageResult.GeneralError end
    local sent,result
    T.assertFalse(ns.Comm:SendTyping("WHISPER","Alice-TestRealm",true,nil,function(ok,code) sent,result=ok,code end))
    T.assertFalse(sent); T.assertEq(result,Enum.SendAddonMessageResult.GeneralError)
    tick(); tick(.2); tick(.2)
    T.assertEq(attempts,2)
    C_ChatInfo.SendAddonMessage=send
    tick(1)
    T.assertEq(mocks.sentMessages[1].msg,"TYPING:1:1")
    active=nil; tick()
    T.assertEq(mocks.sentMessages[2].msg,"TYPING:1:0")
  end)
  T.it("traces input, transport and receive without exposing draft text",function()
    reset()
    local original,lines=print,{}
    _G.print=function(line) lines[#lines+1]=line end
    typing.Debug(""); edit("WHISPER","DO_NOT_LOG_THIS","Alice-TestRealm"); tick()
    receive("Alice-TestRealm","WHISPER"); tick()
    typing.Debug("off")
    local count=#lines
    tick(3); receive("Alice-TestRealm","WHISPER")
    _G.print=original
    local output=table.concat(lines,"\n")
    T.assertTrue(output:find("typing WHISPER",1,true)~=nil)
    T.assertTrue(output:find("Transport: accepted",1,true)~=nil)
    T.assertTrue(output:find("Receive: Alice-TestRealm",1,true)~=nil)
    T.assertNil(output:find("DO_NOT_LOG_THIS",1,true))
    T.assertEq(#lines,count)
  end)
  if ChatThrottleLib then
    T.it("waits for the queued transport result and reports a delayed rejection",function()
      reset()
      local ctl=ChatThrottleLib
      local send=C_ChatInfo.SendAddonMessage
      C_ChatInfo.SendAddonMessage=function() return Enum.SendAddonMessageResult.GeneralError end
      ctl.avail,ctl.LastAvailUpdate=0,GetTime()
      local completed,result=false,nil
      T.assertTrue(ns.Comm:SendTyping("WHISPER","Alice-TestRealm",true,nil,function(sent,code)
        completed,result=true,code
        T.assertFalse(sent)
      end))
      T.assertFalse(completed)
      mocks.fakeNow=mocks.fakeNow+3
      ctl.OnUpdate(ctl.Frame,.5)
      T.assertTrue(completed); T.assertEq(result,Enum.SendAddonMessageResult.GeneralError)
      C_ChatInfo.SendAddonMessage=send
      ctl.OnUpdate(ctl.Frame,.5)
    end)
  end
  T.it("whispers only to the recipient and stops the old recipient on change",function()
    reset(); edit("WHISPER","secret","Alice-TestRealm"); tick()
    T.assertEq(mocks.sentMessages[1].target,"Alice-TestRealm")
    active:SetAttribute("tellTarget","Bob-OtherRealm"); tick(1)
    T.assertEq(mocks.sentMessages[2].target,"Alice-TestRealm")
    T.assertEq(mocks.sentMessages[2].msg,"TYPING:1:0")
    T.assertEq(mocks.sentMessages[3].target,"Bob-OtherRealm")
    for _,msg in ipairs(mocks.sentMessages) do T.assertEq(msg.channel,"WHISPER") end
  end)
  T.it("ignores unsupported channels, commands, blank drafts and invalid whisper targets",function()
    reset()
    for _,channel in ipairs({"GUILD","OFFICER","CHANNEL","BN_WHISPER","PARTY"}) do edit(channel); tick(1) end
    edit("SAY","/run print('secret')"); tick()
    edit("SAY","   "); tick()
    edit("WHISPER","hello"); tick()
    T.assertEq(#mocks.sentMessages,0)
  end)
  T.it("expires idle drafts and resumes after editing without sending each keystroke",function()
    reset(); edit("SAY"); tick(); tick(3)
    T.assertEq(#mocks.sentMessages,2)
    tick(5); T.assertEq(mocks.sentMessages[3].msg,"TYPING:1:SAY:0")
    active:SetText("new words"); tick()
    T.assertEq(mocks.sentMessages[4].msg,"TYPING:1:SAY:1:1:0.00:0.00")
    for i=1,10 do active:SetText("new words "..i); tick(.05) end
    T.assertEq(#mocks.sentMessages,4)
  end)
  T.it("bounds starts during rapid recipient switches",function()
    reset(); edit("WHISPER","hello","Alice"); tick()
    for i=1,20 do active:SetAttribute("tellTarget","Player"..i); tick(.2) end
    local starts=0
    for _,msg in ipairs(mocks.sentMessages) do if msg.msg=="TYPING:1:1" then starts=starts+1 end end
    T.assertTrue(starts<=5)
  end)
  T.it("matches realm identities and keeps heartbeat rendering allocation-free",function()
    reset(); local a=plate("nameplate1","Alice"); local b=plate("nameplate2","Alice","OtherRealm")
    receive("Alice-TestRealm"); tick()
    T.assertTrue(a.grosOrteilTypingIcon:IsShown()); T.assertNil(b.grosOrteilTypingIcon)
    local count=#frames.frames
    receive("Alice-TestRealm"); tick()
    T.assertEq(#frames.frames,count)
    receive("Alice-OtherRealm","WHISPER"); tick()
    T.assertTrue(b.grosOrteilTypingIcon:IsShown())
    T.assertEq(summary.text:GetText(),"2 personnes écrivent…")
  end)
  T.it("cleans up on chat, expiry and recycled nameplates",function()
    reset(); local p=plate("nameplate1","Alice")
    receive("Alice-TestRealm"); tick()
    frames.fire("CHAT_MSG_SAY","Bonjour","Alice-TestRealm")
    T.assertFalse(p.grosOrteilTypingIcon:IsShown())
    receive("Alice-TestRealm"); tick(); tick(7)
    T.assertFalse(p.grosOrteilTypingIcon:IsShown()); T.assertFalse(summary:IsShown())
    receive("Alice-TestRealm"); tick()
    frames.fire("NAME_PLATE_UNIT_REMOVED","nameplate1")
    T.assertFalse(p.grosOrteilTypingIcon:IsShown())
    mocks.units.nameplate1.name="Bob"
    frames.fire("NAME_PLATE_UNIT_ADDED","nameplate1")
    T.assertFalse(p.grosOrteilTypingIcon:IsShown())
  end)
  T.it("retains distant group and whisper status without a nameplate",function()
    reset(); party=true
    receive("FarAway-OtherRealm","PARTY"); receive("Friend-TestRealm","WHISPER"); tick()
    T.assertEq(summary.text:GetText(),"2 personnes écrivent…")
    summary:RunScript("OnEnter")
    T.assertTrue(GameTooltip:IsShown())
    frames.fire("GROUP_ROSTER_UPDATE")
    T.assertEq(summary.text:GetText(),"2 personnes écrivent…")
    party=false
    frames.fire("GROUP_ROSTER_UPDATE")
    T.assertEq(summary.text:GetText(),"Friend écrit…")
    receive("Friend-TestRealm","SAY",false); tick()
    T.assertTrue(summary:IsShown(),"a stop for another channel must not clear a whisper")
  end)
  T.it("shows nearby say in the summary without friendly nameplates",function()
    reset(); edit("SAY"); tick()
    local packet=mocks.sentMessages[1]
    ns.Comm:OnChatMsgAddon(packet.prefix,packet.msg,packet.channel,"Alice-TestRealm")
    active=nil; tick()
    T.assertTrue(summary:IsShown())
    T.assertEq(summary.text:GetText(),"Alice écrit…")
    T.assertEq(summary.text._textColor[2],ChatTypeInfo.SAY.g)
    receive("Alice-TestRealm","SAY",false); tick()
    T.assertFalse(summary:IsShown())
    receive("Alice-TestRealm"); tick(); tick(7)
    T.assertFalse(summary:IsShown())
    receive("Alice-TestRealm"); tick()
    frames.fire("CHAT_MSG_SAY","Bonjour","Alice-TestRealm")
    T.assertFalse(summary:IsShown())
  end)
  T.it("keeps nearby say when a nameplate appears, disappears or is forbidden",function()
    reset(); receive("Alice-TestRealm"); tick()
    local p=plate("nameplate1","Alice")
    T.assertTrue(p.grosOrteilTypingIcon and p.grosOrteilTypingIcon:IsShown())
    frames.fire("NAME_PLATE_UNIT_REMOVED","nameplate1")
    T.assertFalse(p.grosOrteilTypingIcon:IsShown())
    receive("Alice-TestRealm"); tick(3)
    T.assertTrue(summary:IsShown())
    p._forbidden=true
    frames.fire("NAME_PLATE_UNIT_ADDED","nameplate1")
    receive("Alice-TestRealm"); tick(3)
    T.assertTrue(summary:IsShown())
    T.assertFalse(p.grosOrteilTypingIcon:IsShown())
    playerX=61; tick()
    T.assertFalse(summary:IsShown())
  end)
  T.it("disable cancels polling, clears icons and stops both send and receive",function()
    reset(); local p=plate("nameplate1","Alice")
    edit("SAY"); receive("Alice-TestRealm"); tick()
    local old=timer
    typing.SetEnabled(false)
    T.assertTrue(old.cancelled); T.assertFalse(summary:IsShown())
    T.assertFalse(p.grosOrteilTypingIcon:IsShown())
    T.assertEq(mocks.sentMessages[#mocks.sentMessages].msg,"TYPING:1:SAY:0")
    receive("Bob-TestRealm"); T.assertFalse(summary:IsShown())
    typing.SetEnabled(true); tick(1)
    T.assertEq(mocks.sentMessages[#mocks.sentMessages].msg,"TYPING:1:SAY:1:1:0.00:0.00")
  end)
  T.it("world transitions clear stale state and restart polling only when enabled",function()
    reset(); receive("Alice-TestRealm"); tick()
    frames.fire("PLAYER_LEAVING_WORLD")
    T.assertTrue(timer.cancelled); T.assertFalse(summary:IsShown())
    frames.fire("PLAYER_ENTERING_WORLD")
    T.assertFalse(timer.cancelled); tick()
    typing.SetEnabled(false); frames.fire("PLAYER_ENTERING_WORLD")
    T.assertTrue(timer.cancelled)
  end)
  T.it("ignores self, malformed packets, unsupported transport and forbidden plates",function()
    reset(); receive("TestPlayer-TestRealm"); receive("Alice-TestRealm","GUILD")
    ns.Comm:OnChatMsgAddon("OTHER","TYPING:1:1","SAY","Alice-TestRealm")
    ns.Comm:OnChatMsgAddon("GO_STATE","TYPING:9:1","SAY","Alice-TestRealm")
    tick(); T.assertFalse(summary:IsShown())
    local p=plate("nameplate1","Alice"); p._forbidden=true
    receive("Alice-TestRealm"); tick(); T.assertNil(p.grosOrteilTypingIcon)
  end)
  T.it("handles 40 simultaneous typists with fixed summary and reusable icons",function()
    reset(); party=true
    for i=1,40 do plate("nameplate"..i,"Player"..i); receive("Player"..i.."-TestRealm","PARTY") end
    tick(); T.assertEq(summary.text:GetText(),"40 personnes écrivent…")
    local count=#frames.frames
    for round=1,10 do
      for i=1,40 do receive("Player"..i.."-TestRealm","PARTY") end
      tick(3)
    end
    T.assertEq(#frames.frames,count)
    tick(7); T.assertFalse(summary:IsShown())
  end)
  T.it("filters say by range and world space independently of nameplates",function()
    reset(); local p=plate("nameplate1","Alice")
    local function at(map,x,y)
      ns.Comm:OnChatMsgAddon("GO_STATE","TYPING:1:SAY:1:"..map..":"..x..":"..y,"CHANNEL","Alice-TestRealm")
      tick()
    end
    at(1,60,0); T.assertTrue(p.grosOrteilTypingIcon:IsShown())
    at(1,60.01,0); T.assertFalse(p.grosOrteilTypingIcon:IsShown())
    at(2,0,0); T.assertFalse(p.grosOrteilTypingIcon:IsShown())
    at(1,0,0); playerX=100; tick()
    T.assertFalse(p.grosOrteilTypingIcon:IsShown())
    playerX=0; receive("NoNameplate-TestRealm"); tick()
    T.assertTrue(summary:IsShown())
    receive("NoNameplate-TestRealm","SAY",false); tick()
    T.assertFalse(summary:IsShown())
    for _,payload in ipairs({"1:SAY:1:1:nan:0","1:SAY:1:1:1e999:0","1:SAY:1:-1:0:0","1:SAY:1:1:1000001:0","1:SAY:1:1:0:0:extra"}) do
      ns.Comm:OnChatMsgAddon("GO_STATE","TYPING:"..payload,"CHANNEL","Alice-TestRealm")
    end
    tick(); T.assertFalse(summary:IsShown())
  end)
  T.it("fails closed for unavailable positions without breaking group/whisper",function()
    reset(); plate("nameplate1","Alice"); playerMap=nil
    edit("SAY"); tick(); receive("Alice-TestRealm"); tick()
    T.assertEq(#mocks.sentMessages,0); T.assertFalse(summary:IsShown())
    edit("WHISPER","hello","Friend"); tick()
    T.assertEq(mocks.sentMessages[1].channel,"WHISPER")
    receive("Friend-TestRealm","WHISPER"); tick(); T.assertTrue(summary:IsShown())
  end)
  T.it("joins the temporary channel with bounded retries and leaves when disabled",function()
    reset()
    local get,join,leave=GetChannelName,JoinTemporaryChannel,LeaveChannelByName
    local joins,left=0,false
    _G.GetChannelName=function() return 0 end
    _G.JoinTemporaryChannel=function(name) T.assertEq(name,ns.Comm.TYPING_CHANNEL); joins=joins+1 end
    _G.LeaveChannelByName=function(name) T.assertEq(name,ns.Comm.TYPING_CHANNEL); left=true end
    edit("SAY"); tick()
    for i=1,20 do tick(.2) end
    T.assertEq(joins,1); T.assertEq(#mocks.sentMessages,0)
    tick(10); T.assertEq(joins,2)
    typing.SetEnabled(false); T.assertTrue(left)
    _G.GetChannelName,_G.JoinTemporaryChannel,_G.LeaveChannelByName=get,join,leave
  end)
  T.it("uses TRP names in the summary and tooltip while retaining network identities",function()
    reset(); local p=plate("nameplate1","Alice")
    local original=LibRPNames
    local rpName="|cffff0000Alicia de la Lune|r"
    _G.LibRPNames={Get=function(sender)
      T.assertEq(sender,"Alice-TestRealm")
      return rpName
    end}
    receive("Alice-TestRealm","WHISPER"); tick()
    T.assertEq(summary.text:GetText(),"Alicia de la Lune écrit…")
    T.assertTrue(p.grosOrteilTypingIcon:IsShown())
    summary:RunScript("OnEnter")
    T.assertEq(GameTooltip._callAddLine[1],"Alicia de la Lune — WHISPER")
    T.assertEq(GameTooltip._callAddLine[3],ChatTypeInfo.WHISPER.g)
    rpName="Alicia Soleil"
    receive("Alice-TestRealm","WHISPER"); tick(3)
    T.assertEq(summary.text:GetText(),"Alicia Soleil écrit…")
    T.assertEq(GameTooltip._callAddLine[1],"Alicia Soleil — WHISPER")
    frames.fire("CHAT_MSG_WHISPER","Bonjour","Alice-TestRealm")
    T.assertFalse(summary:IsShown()); T.assertFalse(p.grosOrteilTypingIcon:IsShown())
    _G.LibRPNames=original
  end)
  T.it("uses channel colors for text and nameplate bubbles and handles mixed crowds",function()
    reset(); party,raid,instance=true,true,true
    local p=plate("nameplate1","Alice")
    for _,channel in ipairs({"SAY","PARTY","RAID","INSTANCE_CHAT","WHISPER"}) do
      receive("Alice-TestRealm",channel); tick()
      local color=ChatTypeInfo[channel]
      for index,component in ipairs({color.r,color.g,color.b}) do
        T.assertEq(summary.text._textColor[index],component)
        T.assertEq(p.grosOrteilTypingIcon._vertexColor[index],component)
      end
      T.assertTrue(p.grosOrteilTypingIcon:IsShown())
    end
    receive("Bob-TestRealm","WHISPER"); tick()
    T.assertEq(summary.text._textColor[2],ChatTypeInfo.WHISPER.g)
    receive("Bob-TestRealm","PARTY"); tick()
    for i=1,3 do T.assertEq(summary.text._textColor[i],1) end
    receive("Bob-TestRealm","PARTY",false); tick()
    T.assertEq(summary.text._textColor[2],ChatTypeInfo.WHISPER.g)
    receive("Alice-TestRealm","WHISPER",false); tick()
    T.assertFalse(summary:IsShown()); T.assertFalse(p.grosOrteilTypingIcon:IsShown())
  end)
  T.it("falls back when RP data is unavailable or its lookup fails",function()
    reset(); receive("Alice-TestRealm","WHISPER"); tick()
    T.assertEq(summary.text:GetText(),"Alice écrit…")
    local original=LibRPNames
    _G.LibRPNames={Get=function() error("RP data unavailable") end}
    receive("Alice-TestRealm","WHISPER"); tick(3)
    T.assertEq(summary.text:GetText(),"Alice-TestRealm écrit…")
    T.assertTrue(summary:IsShown())
    _G.LibRPNames=original
  end)
end)
local ok=T.run({verbose=true})
-- Relevant hot-path baseline: 10,000 samples, with idle and 40 visible typists.
reset()
local before=os.clock()
for i=1,10000 do timer.callback() end
print(string.format("Typing idle: %.2f us/sample",(os.clock()-before)*100))
party=true
for i=1,40 do plate("nameplate"..i,"Player"..i); receive("Player"..i.."-TestRealm","PARTY") end
tick()
local count=#frames.frames
before=os.clock()
for i=1,10000 do timer.callback() end
print(string.format("Typing 40 peers: %.2f us/sample; %d new regions",(os.clock()-before)*100,#frames.frames-count))
for i=1,40 do receive("Player"..i.."-TestRealm","SAY") end
tick()
before=os.clock()
for i=1,10000 do timer.callback() end
print(string.format("Typing 40 nearby say peers: %.2f us/sample; %d new regions",(os.clock()-before)*100,#frames.frames-count))
os.exit(ok and 0 or 1)
