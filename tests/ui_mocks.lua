-- Stateful, deliberately finite WoW UI test double. Missing methods fail instead
-- of silently succeeding. It models hooks, visibility, focus, animation finish
-- and protected ancestors, not the game renderer or Blizzard's taint engine.
local M = { frames = {}, animations = {}, combat = false, cursorX = 800, cursorY = 500 }
local methods = {}
local unpack = table.unpack or unpack
local factors = {TOPLEFT={0,1}, TOP={.5,1}, TOPRIGHT={1,1}, LEFT={0,.5}, CENTER={.5,.5}, RIGHT={1,.5}, BOTTOMLEFT={0,0}, BOTTOM={.5,0}, BOTTOMRIGHT={1,0}}
local function guard(self, operation)
  if M.combat and self._protected then error("Protected mutation in combat: " .. operation, 3) end
end
local function textHeight(self, width)
  local inset = self._callSetTextInsets or {0, 0, 0, 0}
  local size, lines = self._fontSize or 12, 0
  width = math.max(1, width - inset[1] - inset[2])
  for line in (self:GetText() .. "\n"):gmatch("(.-)\n") do
    lines = lines + math.max(1, math.ceil(#line * size * .5 / width))
  end
  return lines * size + inset[3] + inset[4]
end
function methods:RunScript(name, ...)
  if self._scripts[name] then self._scripts[name](self, ...) end
  for _, hook in ipairs(self._hooks[name] or {}) do hook(self, ...) end
end
function methods:SetScript(name, fn) self._scripts[name] = fn end
function methods:GetScript(name) return self._scripts[name] end
function methods:IsForbidden() return self._forbidden == true end
function methods:IsOwned(owner) return self._callSetOwner and self._callSetOwner[1] == owner or false end
function methods:HookScript(name, fn)
  self._hooks[name] = self._hooks[name] or {}
  table.insert(self._hooks[name], fn)
end
function methods:GetRect(seen)
  if self == _G.UIParent then return 0, 0, self._w, self._h end
  seen = seen or {}
  if type(seen[self]) == "table" then return unpack(seen[self]) end
  if seen[self] then return 0, 0, self._w or 0, self._h or 0 end
  seen[self] = true
  if self._scrollOwner and #self._points == 0 then
    local l,b,w,h = self._scrollOwner:GetRect(seen)
    local width = self._w or w
    local height = self._h or (self._multiline and textHeight(self, width)) or 0
    seen[self] = {l, b+h-height+self._scrollOwner:GetVerticalScroll(), width, height}
    return unpack(seen[self])
  end
  local axes = {{}, {}}
  for _, p in ipairs(self._points) do
    local rel = p[2] or self._parent or _G.UIParent
    local l,b,w,h = rel:GetRect(seen)
    local rf, sf = factors[p[3]], factors[p[1]]
    axes[1][#axes[1]+1] = {sf[1], l+rf[1]*w+p[4]}
    axes[2][#axes[2]+1] = {sf[2], b+rf[2]*h+p[5]}
  end
  local function solve(points, size)
    local fixed = size ~= nil
    size = size or 0
    for i=2,#points do
      local span = math.abs(points[i][1]-points[1][1])
      if span > 0 and (not fixed or span == 1) then
        size = (points[i][2]-points[1][2])/(points[i][1]-points[1][1]); break
      end
    end
    return points[1] and points[1][2]-points[1][1]*size or 0, size
  end
  local text = tostring(self._text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local l,w = solve(axes[1], self._w or (#text * (self._fontSize or 12) * .5))
  local b,h = solve(axes[2], self._h or (self._kind == "FontString" and (self._fontSize or 12) or 0))
  seen[self] = {l,b,math.max(0,w),math.max(0,h)}
  return unpack(seen[self])
end
function methods:SetPoint(point, relative, relativePoint, x, y)
  guard(self, "SetPoint")
  assert(factors[point], "invalid anchor " .. tostring(point))
  if type(relative) == "number" then x,y,relative,relativePoint = relative,relativePoint,self._parent,point end
  relative = relative or self._parent or _G.UIParent
  relativePoint = relativePoint or point
  assert(factors[relativePoint], "invalid relative anchor")
  local entry = {point,relative,relativePoint,x or 0,y or 0}
  for i,p in ipairs(self._points) do if p[1] == point then self._points[i]=entry; return end end
  self._points[#self._points+1] = entry
end
function methods:GetPoint(i) return unpack(self._points[i or 1] or {}) end
function methods:ClearAllPoints() guard(self,"ClearAllPoints"); self._points={} end
function methods:SetAllPoints(other)
  self:ClearAllPoints(); self:SetPoint("TOPLEFT",other); self:SetPoint("BOTTOMRIGHT",other)
end
function methods:SetSize(w,h) guard(self,"SetSize"); self._w,self._h=w,h end
function methods:SetWidth(w) guard(self,"SetWidth"); self._w=w end
function methods:SetHeight(h) guard(self,"SetHeight"); self._h=h end
function methods:GetWidth() local _,_,w=self:GetRect(); return w end
function methods:GetHeight() local _,_,_,h=self:GetRect(); return h end
function methods:GetLeft() return self:GetRect() end
function methods:GetBottom() local _,b=self:GetRect(); return b end
function methods:GetTop() local _,b,_,h=self:GetRect(); return b+h end
function methods:GetRight() local l,_,w=self:GetRect(); return l+w end
function methods:GetCenter() local l,b,w,h=self:GetRect(); return l+w/2,b+h/2 end
function methods:GetParent() return self._parent end
function methods:GetName() return self._name end
function methods:GetObjectType() return self._kind end
function methods:IsShown() return self._shown end
function methods:IsVisible() return self._shown and (not self._parent or self._parent:IsVisible()) end
local function visibility(self, show)
  guard(self,show and "Show" or "Hide")
  local before={}
  for _,f in ipairs(M.frames) do before[f]=f:IsVisible() end
  self._shown=show
  for _,f in ipairs(M.frames) do
    local visible=f:IsVisible()
    if visible ~= before[f] then
      if not visible and f:HasFocus() then f:ClearFocus() end
      f:RunScript(visible and "OnShow" or "OnHide")
    end
  end
end
function methods:Show() if not self._shown then visibility(self,true) end end
function methods:Hide() if self._shown then visibility(self,false) end end
function methods:SetShown(show) if show then self:Show() else self:Hide() end end
function methods:Enable() self._enabled=true end
function methods:Disable() self._enabled=false end
function methods:IsEnabled() return self._enabled end
function methods:SetText(text)
  text=tostring(text or "")
  if text ~= self._text then
    self._text=text; self._cursor=#text; self._selection=nil
    self:RunScript("OnTextChanged",false)
  end
end
function methods:GetText() return self._text or "" end
function methods:GetNumber() return tonumber(self:GetText()) or 0 end
function methods:SetCursorPosition(position)
  self._cursor=math.max(0,math.min(#self:GetText(),position))
  self._selection=nil
end
function methods:GetCursorPosition() return self._cursor or 0 end
function methods:HighlightText(first,last)
  self._callHighlightText={first,last}
  first,last=first or 0,last or -1
  if last<0 then last=#self:GetText() end
  self._selection={math.max(0,first),math.min(#self:GetText(),last)}
end
function methods:Insert(text)
  local first,last=self:GetCursorPosition(),self:GetCursorPosition()
  if self._selection then first,last=self._selection[1],self._selection[2] end
  first,last=math.min(first,last),math.max(first,last)
  self._text=self:GetText():sub(1,first)..text..self:GetText():sub(last+1)
  self._cursor=first+#text; self._selection=nil
  self:RunScript("OnTextChanged",true)
end
function methods:SetFocus()
  if M.focus == self then return end
  if M.focus then M.focus:ClearFocus() end
  M.focus=self; self:RunScript("OnEditFocusGained")
end
function methods:ClearFocus()
  if M.focus == self then M.focus=nil; self:RunScript("OnEditFocusLost") end
end
function methods:HasFocus() return M.focus == self end
function methods:SetMultiLine(value) self._multiline=value end
function methods:GetStringHeight()
  assert(self._kind == "FontString", "GetStringHeight belongs to FontString, not EditBox")
  return textHeight(self, self:GetWidth())
end
function methods:GetFrameLevel() return self._level or (self._parent and self._parent:GetFrameLevel()+1) or 0 end
function methods:SetFrameLevel(n) self._level=n end
function methods:GetScale() return self._scale or 1 end
function methods:SetScale(n) guard(self,"SetScale"); self._scale=n end
function methods:GetEffectiveScale() return self:GetScale()*(self._parent and self._parent:GetEffectiveScale() or 1) end
function methods:SetAttribute(k,v) guard(self,"SetAttribute"); self._attrs[k]=v end
function methods:GetAttribute(k) return self._attrs[k] end
function methods:SetScrollChild(child)
  guard(self,"SetScrollChild"); self._scrollChild=child; child._scrollOwner=self
end
function methods:GetVerticalScroll() return self._scroll or 0 end
function methods:GetVerticalScrollRange() return math.max(0,(self._scrollChild and self._scrollChild:GetHeight() or 0)-self:GetHeight()) end
function methods:SetVerticalScroll(n) self._scroll=n; self:RunScript("OnVerticalScroll",n) end
function methods:RegisterEvent(event) self._events[event]=true end
function methods:UnregisterEvent(event) self._events[event]=nil end
function methods:UnregisterAllEvents() self._events={} end
function methods:SetTexture(t) self._texture=t; return true end
function methods:SetHorizTile(value) self._horizTile=value end
function methods:SetVertTile(value) self._vertTile=value end
function methods:GetTexture() return self._texture end
function methods:SetAtlas(a) self._atlas=a; return true end
function methods:GetAtlas() return self._atlas end
function methods:SetColorTexture(...) self._color={...} end
function methods:SetVertexColor(...) self._vertexColor={...} end
function methods:SetTextColor(...) self._textColor={...} end
function methods:SetBackdrop(b)
  guard(self,"SetBackdrop")
  if b and self._backdropInfo == b then return end
  if b and not b.bgFile and not b.edgeFile then b = nil end
  self._backdropInfo = b
  self._backdrop = nil
  if b then
    self._backdrop = {}
    for key, value in pairs(b) do self._backdrop[key] = value end
  end
end
function methods:SetBackdropColor(...) self._backdropColor={...} end
function methods:SetBackdropBorderColor(...) self._borderColor={...} end
function methods:SetFont(path,size,flags) self._fontSize=size; self._font=path end
function methods:SetAlpha(a) self._alpha=a end
function methods:GetAlpha() return self._alpha or 1 end
function methods:IsMouseOver() return M.mouseOver == self end
function methods:SetPropagateKeyboardInput(value) self._propagate=value end
function methods:SetValue(value)
  if self._value ~= value then self._value=value; self:RunScript("OnValueChanged",value) end
end
function methods:GetValue() return self._value or 0 end
function methods:SetMinMaxValues(a,b) self._min,self._max=a,b end
function methods:CreateAnimationGroup()
  local g={playing=false, scripts={}, region=self, animations={}}
  function g:CreateAnimation(kind)
    local a={kind=kind}
    for _,key in ipairs({"FromAlpha","ToAlpha","Duration","Smoothing","Offset","StartDelay","Order","Degrees","Scale"}) do
      a["Set"..key]=function(obj,...) obj[key]={...} end
    end
    self.animations[#self.animations+1]=a; return a
  end
  function g:Play() self.playing=true; self.plays=(self.plays or 0)+1 end
  function g:Stop() self.playing=false end
  function g:IsPlaying() return self.playing end
  function g:SetLooping(v) self.looping=v end
  function g:SetScript(k,v) self.scripts[k]=v end
  function g:Finish()
    if not self.playing then return end
    self.playing=false
    if self.scripts.OnFinished then self.scripts.OnFinished(self) end
  end
  M.animations[#M.animations+1]=g
  return g
end
function M.new(kind,name,parent,template)
  local f=setmetatable({_kind=kind,_name=name,_parent=parent,_shown=true,_enabled=true,_scripts={},_hooks={},_points={},_events={},_attrs={},_template=template}, {__index=methods})
  M.frames[#M.frames+1]=f
  if name then assert(not _G[name],"duplicate frame name: "..name); _G[name]=f end
  if template and template:find("SecureActionButtonTemplate",1,true) then
    local p=f; while p do p._protected=true; p=p._parent end
  end
  return f
end
function methods:CreateTexture(name,layer,template,sublevel)
  local t=M.new("Texture",name,self,template); t._layer=layer; t._sublevel=sublevel; return t
end
function methods:CreateFontString(name,layer,font)
  local f=M.new("FontString",name,self); f._layer=layer; f._fontSize=font and (font:find("Large") and 16 or font:find("Small") and 10 or 12) or 12; return f
end
for _,kind in ipairs({"Normal","Pushed","Highlight","Disabled","StatusBar"}) do
  methods["Set"..kind.."Texture"]=function(self,texture)
    local key="_"..kind.."Texture"
    if texture == nil then self[key]=nil; return end
    self[key]=self[key] or self:CreateTexture(nil,kind=="Highlight" and "HIGHLIGHT" or "ARTWORK")
    self[key]:SetTexture(texture)
  end
  methods["Get"..kind.."Texture"]=function(self) return self["_"..kind.."Texture"] end
end
-- Explicit visual/interaction methods outside this harness's simulation scope.
for _,name in ipairs({"SetJustifyH","SetJustifyV","SetShadowColor","SetShadowOffset","SetFontObject","SetAutoFocus","SetNumeric","SetBlinkSpeed","SetTextInsets","SetMaxLetters","SetMaxLines","SetWordWrap","SetNonSpaceWrap","SetHitRectInsets","SetPropagateMouseClicks","SetBlendMode","SetGradient","SetRotation","SetDesaturated","SetTexCoord","SetStatusBarColor","SetClampedToScreen","SetClipsChildren","SetMovable","EnableMouse","EnableMouseWheel","EnableKeyboard","SetToplevel","SetFrameStrata","SetMotionScriptsWhileDisabled","RegisterForDrag","RegisterForClicks","Raise","AddLine","AddMessage","SetOwner","ClearLines","SetUnit"}) do
  methods[name]=function(self,...) self["_call"..name]={...} end
end
function methods:StartMoving() guard(self,"StartMoving"); self._moving=true end
function methods:StopMovingOrSizing() self._moving=false end
function M.fire(event,...)
  local count=#M.frames
  for i=1,count do local f=M.frames[i]; if f._events[event] then f:RunScript("OnEvent",event,...) end end
end
function M.finishAnimations() for _,g in ipairs(M.animations) do if not g.looping then g:Finish() end end end
function M.layout()
  for pass=1,6 do
    local changed=false
    for _,f in ipairs(M.frames) do
      local w,h=f:GetWidth(),f:GetHeight()
      if w~=f._lastW or h~=f._lastH then
        f._lastW,f._lastH=w,h; changed=true; f:RunScript("OnSizeChanged",w,h)
      end
    end
    if not changed then return end
  end
end
function M.install()
  _G.CreateFrame=M.new
  _G.UIParent=M.new("Frame"); UIParent._w,UIParent._h=1920,1080
  _G.GameTooltip=M.new("GameTooltip",nil,UIParent); GameTooltip:Hide()
  local picker = M.new("Frame", "ColorPickerFrame", UIParent)
  picker:Hide()
  picker.Content = {ColorPicker = M.new("ColorSelect", nil, picker)}
  picker.Footer = {OkayButton = M.new("Button", nil, picker), CancelButton = M.new("Button", nil, picker)}
  function picker:GetColorRGB() return unpack(self._rgb) end
  function picker:GetExtraInfo() return self.extraInfo end
  function picker.Content.ColorPicker:SetColorRGB(r,g,b)
    picker._rgb = {r,g,b}
    if picker.swatchFunc then picker.swatchFunc() end
  end
  function picker:SetupColorPickerAndShow(info)
    self.swatchFunc, self.cancelFunc, self.extraInfo = info.swatchFunc, info.cancelFunc, info.extraInfo
    self.previousValues = {r=info.r, g=info.g, b=info.b, a=info.opacity}
    self.hasOpacity = info.hasOpacity
    self.Content.ColorPicker:SetColorRGB(info.r, info.g, info.b)
    self:Show()
  end
  picker.Footer.OkayButton:SetScript("OnClick", function()
    if picker.swatchFunc then picker.swatchFunc() end
    picker:Hide()
  end)
  local function cancelColor()
    if picker.cancelFunc then picker.cancelFunc(picker.previousValues) end
    picker:Hide()
  end
  picker.Footer.CancelButton:SetScript("OnClick", cancelColor)
  picker:SetScript("OnKeyDown", function(_, key) if key == "ESCAPE" then cancelColor() end end)
  picker:RegisterEvent("GLOBAL_MOUSE_DOWN")
  picker:SetScript("OnEvent", function()
    if picker:IsShown() and not picker:IsMouseOver() then cancelColor() end
  end)
  _G.StaticPopupDialogs={}; _G.SlashCmdList={}
  _G.StaticPopup_Show=function(name,_,_,data) M.popup={name=name,data=data} end
  M.reloads=0
  _G.ReloadUI=function()
    assert(not M.combat, "ReloadUI in combat")
    M.reloads=M.reloads+1
  end
  _G.GetCurrentKeyBoardFocus=function() return M.focus end
  _G.IsControlKeyDown=function() return M.ctrl end
  _G.GetCursorPosition=function() return M.cursorX,M.cursorY end
  _G.InCombatLockdown=function() return M.combat end
  _G.hooksecurefunc=function(object,key,hook)
    local original=object[key]
    object[key]=function(self,...) original(self,...); hook(self,...) end
  end
  _G.C_Timer.After=function(_,fn) M.timers=M.timers or {}; table.insert(M.timers,fn) end
  _G.C_AddOns={GetAddOnMetadata=function(_,key) return key=="Version" and "2.2.0" end}
end
return M
