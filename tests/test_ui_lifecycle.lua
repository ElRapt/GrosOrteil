-- Deferred secure-panel intent and distance-window polling/cleanup.
return function(T, ns, frames)
  local Raid, Distance = ns.RaidPanel, ns.Distance
  local function combat(active)
    frames.combat = active
    frames.fire(active and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
  end
  local function find(predicate)
    for _, f in ipairs(frames.frames) do if predicate(f) then return f end end
    error("frame missing")
  end
  local function tab(view) find(function(f) return f._view == view end):RunScript("OnClick") end
  local function showGroup()
    Raid.Show(); frames.finishAnimations(); tab("group")
    return GrosOrteilRaidPanel, GrosOrteilRaidPanelScroll
  end
  T.describe("Raid lifecycle ownership", function()
    T.it("lays out queued show once, skips queued hide, and consumes pending work", function()
      local panel, scroll = showGroup()
      local group = scroll._scrollChild
      tab("meter"); local meter = scroll._scrollChild; tab("group")
      local layouts, originals = 0, {}
      for _, child in ipairs({group, meter}) do
        originals[child] = child.SetHeight
        child.SetHeight = function(self, h) layouts = layouts + 1; originals[self](self, h) end
      end
      combat(true)
      ns.Core.SetHP(50,100); frames.fire("GROUP_ROSTER_UPDATE")
      tab("meter"); Raid.Show(); layouts = 0
      combat(false); frames.finishAnimations()
      T.assertEq(layouts,1); T.assertEq(scroll._scrollChild,meter); T.assertTrue(panel:IsShown())
      tab("group"); combat(true)
      frames.fire("GROUP_ROSTER_UPDATE"); tab("meter"); Raid.Hide(); layouts = 0
      combat(false); frames.finishAnimations()
      T.assertEq(layouts,0); T.assertFalse(panel:IsShown())
      Raid.Show(); frames.finishAnimations()
      T.assertEq(layouts,1); T.assertEq(scroll._scrollChild,meter)
      layouts = 0; combat(true); combat(false)
      T.assertEq(layouts,0)
      combat(true); tab("group"); combat(false)
      T.assertEq(layouts,1); T.assertEq(scroll._scrollChild,group)
      layouts = 0; combat(true); frames.fire("GROUP_ROSTER_UPDATE"); combat(false)
      T.assertEq(layouts,1)
      for child, original in pairs(originals) do child.SetHeight = original end
      Raid.Hide(); frames.finishAnimations()
    end)
    T.it("keeps the latest view and visibility intent, including cancellation", function()
      local panel, scroll = showGroup()
      local group = scroll._scrollChild
      combat(true)
      tab("meter"); tab("group")
      Raid.Hide(); Raid.Toggle(); Raid.Toggle(); Raid.Show()
      T.assertEq(scroll._scrollChild,group); T.assertTrue(panel:IsShown())
      combat(false); frames.finishAnimations()
      T.assertEq(scroll._scrollChild,group); T.assertTrue(panel:IsShown())
      combat(true); Raid.Show(); Raid.Toggle(); combat(false); frames.finishAnimations()
      T.assertFalse(panel:IsShown())
      combat(true); Raid.Toggle(); Raid.Toggle(); combat(false); frames.finishAnimations()
      T.assertFalse(panel:IsShown())
      combat(true); Raid.Toggle(); combat(false); frames.finishAnimations()
      T.assertTrue(panel:IsShown())
      Raid.Hide(); frames.finishAnimations()
    end)
    T.it("refreshes secure roster targets after combat and after hidden roster changes", function()
      local mocks = require("mocks")
      local oldUnits, oldGroup = mocks.units, IsInGroup
      mocks.units = {player={name="Player"}}
      _G.IsInGroup = function() return true end
      local panel = showGroup()
      combat(true); mocks.units.party1 = {name="Visitor"}
      frames.fire("GROUP_ROSTER_UPDATE"); Raid.Show(); combat(false)
      local row = find(function(f) return f:IsVisible() and f._attrs.unit == "party1" end)
      T.assertEq(row:GetAttribute("type1"),"target")
      T.assertEq(row:GetAttribute("*type1"),"target")
      T.assertNil(row:GetScript("OnClick")); T.assertNotNil(row:GetScript("PostClick"))
      Raid.Hide(); frames.finishAnimations(); T.assertFalse(panel:IsShown())
      mocks.units.party1 = nil; frames.fire("GROUP_ROSTER_UPDATE")
      Raid.Show(); frames.finishAnimations()
      for _, f in ipairs(frames.frames) do
        if f:IsVisible() and f._attrs.type1 == "target" then T.assertNeq(f._attrs.unit,"party1") end
      end
      mocks.units, _G.IsInGroup = oldUnits, oldGroup
      Raid.Hide(); frames.finishAnimations()
    end)
    T.it("restores Escape exactly once and cancels combat-interrupted card and window drags", function()
      local panel = showGroup()
      local row = find(function(f) return f:IsVisible() and f._attrs.type1 == "target" and f._displayIndex end)
      row:RunScript("OnDragStart"); panel:RunScript("OnDragStart")
      T.assertNotNil(panel:GetScript("OnUpdate")); T.assertTrue(panel._moving)
      for i=1,3 do
        combat(true)
        T.assertNil(panel:GetScript("OnUpdate")); T.assertFalse(panel._moving)
        for _, name in ipairs(UISpecialFrames) do T.assertNeq(name,"GrosOrteilRaidPanel") end
        combat(false)
        local registrations = 0
        for _, name in ipairs(UISpecialFrames) do if name == "GrosOrteilRaidPanel" then registrations=registrations+1 end end
        T.assertEq(registrations,1)
      end
      T.assertEq(row:GetAlpha(),1)
      row:RunScript("OnDragStart"); Raid.Hide(); frames.finishAnimations()
      T.assertNil(panel:GetScript("OnUpdate")); T.assertEq(row:GetAlpha(),1)
      Raid.Show(); frames.finishAnimations()
      local grip = find(function(f)
        return f._parent == panel and f._NormalTexture and tostring(f._NormalTexture:GetTexture()):find("SizeGrabber",1,true)
      end)
      grip:RunScript("OnMouseDown","LeftButton"); T.assertNotNil(grip:GetScript("OnUpdate"))
      Raid.Hide(); frames.finishAnimations(); T.assertNil(grip:GetScript("OnUpdate"))
    end)
  end)
  T.describe("Distance presentation and polling", function()
    T.it("continues measurements without repainting unchanged mode controls", function()
      Distance.Show("target")
      local panel, measure = Distance.frame, Distance.Measure
      local measurements, hintWrites, borderWrites = 0, 0, 0
      local hintText, borders = panel.hint.SetText, {}
      panel.hint.SetText = function(self,text) hintWrites=hintWrites+1; hintText(self,text) end
      for _, b in pairs(panel.modeButtons) do
        borders[b] = b.SetBackdropBorderColor
        b.SetBackdropBorderColor = function(self,...) borderWrites=borderWrites+1; borders[self](self,...) end
      end
      Distance.Measure = function()
        measurements=measurements+1
        if measurements == 1 then
          return {distance=4.5,category=Distance.Categories[1].key,label="Near",range="0-5"}
        end
        return {message="Position unavailable"}
      end
      panel:RunScript("OnUpdate",0.24); T.assertEq(measurements,0)
      panel:RunScript("OnUpdate",0.01)
      T.assertEq(panel.value:GetText(),"~ 4.5 m")
      T.assertEq(panel.categoryRows[1].text._textColor[1],ns.Theme.Colors.TEXT_TITLE[1])
      panel:RunScript("OnUpdate",0.25)
      T.assertEq(panel.status:GetText(),"Position unavailable"); T.assertEq(panel.category:GetText(),"")
      T.assertEq(panel.categoryRows[1].text._textColor[1],ns.Theme.Colors.TEXT_DIM[1])
      T.assertEq(hintWrites,0); T.assertEq(borderWrites,0); T.assertEq(measurements,2)
      Distance.SetMode("target"); T.assertEq(hintWrites,0); T.assertEq(borderWrites,0)
      Distance.SetMode("origin"); T.assertEq(hintWrites,1); T.assertEq(borderWrites,3)
      local originHint = panel.hint:GetText()
      T.assertFalse(Distance.SetMode("invalid")); T.assertEq(Distance.mode,"origin")
      panel:RunScript("OnDragStart"); T.assertTrue(panel._moving)
      panel:Hide(); T.assertFalse(panel._moving); T.assertNil(panel:GetScript("OnUpdate"))
      local before = measurements
      Distance.SetMode("waypoint"); panel:RunScript("OnUpdate",1)
      T.assertEq(measurements,before); T.assertEq(hintWrites,1)
      Distance.Show()
      T.assertNeq(panel.hint:GetText(),originHint); T.assertEq(hintWrites,2); T.assertEq(borderWrites,6)
      Distance.Measure, panel.hint.SetText = measure, hintText
      for b, original in pairs(borders) do b.SetBackdropBorderColor = original end
      panel:Hide(); frames.finishAnimations()
      for _, f in ipairs(frames.frames) do T.assertNil(f:GetScript("OnUpdate"), f._name or f._kind) end
      T.assertEq(#require("mocks").errorHandlerCalls,0)
    end)
  end)
end
