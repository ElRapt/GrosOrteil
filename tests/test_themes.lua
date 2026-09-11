return function(T, ns, frames)
  local unpack = table.unpack or unpack
  local Theme, UI = ns.Theme, ns.UI
  local original = Theme.GetName()
  local function reset(name)
    frames.combat = false
    Theme.SetName(name or original); Theme.ResetOptions()
    ns.UI_Show(true); UI.setSidebarSection(1); UI.setTab(UI.TAB_IDS.THEMES)
    frames.layout()
  end
  local function edit(key, value)
    local input = UI.themeControls[key].edit
    input:SetFocus(); input:SetText(value); input:RunScript("OnEnterPressed")
  end
  local function preview(key, hex)
    UI.themeControls[key].button:RunScript("OnClick")
    ColorPickerFrame.Content.ColorPicker:SetColorRGB(Theme.ColorRGB(hex))
  end
  local function choose(key, hex)
    preview(key, hex)
    ColorPickerFrame.Footer.OkayButton:RunScript("OnClick")
  end
  T.describe("Custom themes", function()
    T.it("applies border, background, opacity and bar choices to existing windows", function()
      reset("slate"); ns.Distance.Show(); ns.RaidPanel.Show()
      local windows = {UI.frame, ns.Distance.frame, _G.GrosOrteilRaidPanel, _G.GrosOrteilTargetPopup}
      T.assertNotNil(windows[4])
      local bars = {}
      for _, frame in ipairs(frames.frames) do
        if frame._kind == "StatusBar" and frame:GetStatusBarTexture()
          and frame:GetStatusBarTexture():GetTexture() == Theme.Textures.STATUSBAR then bars[#bars+1] = frame end
      end
      UI.themeControls.border.buttons[2]:RunScript("OnClick")
      edit("borderSize", "6")
      UI.themeControls.background.buttons[1]:RunScript("OnClick")
      edit("opacity", "35")
      choose("backgroundColor", "336699"); choose("borderColor", "aa3355")
      for _, frame in ipairs(windows) do
        T.assertEq(frame._backdrop.edgeSize, 6)
        T.assertEq(frame._backdrop.edgeFile, "Interface/Tooltips/UI-Tooltip-Border")
        T.assertNear(frame._goBoard._vertexColor[1], 0x33/255)
        T.assertNear(frame._goBoard._vertexColor[4], .35)
        T.assertNear(frame._borderColor[1], 0xaa/255)
        T.assertFalse(frame._goWash:IsShown())
      end
      T.assertEq(UI.sidebar._backdrop.edgeSize, 6)
      T.assertEq(UI.sidebar._backdrop.edgeFile, "Interface/Tooltips/UI-Tooltip-Border")
      Theme.SetOption("opacity", 0)
      for _, frame in ipairs(windows) do T.assertEq(frame._goBoard._vertexColor[4], 0) end
      UI.themeControls.border.buttons[3]:RunScript("OnClick")
      for _, frame in ipairs(windows) do T.assertNil(frame._backdrop) end
      T.assertNil(UI.sidebar._backdrop.edgeFile)
      UI.themeControls.bars.buttons[2]:RunScript("OnClick")
      T.assertTrue(#bars > 1)
      for _, bar in ipairs(bars) do
        T.assertEq(bar:GetStatusBarTexture():GetTexture(), "Interface/TargetingFrame/UI-StatusBar")
      end
      UI.themeControls.decorations:RunScript("OnClick")
      T.assertFalse(Theme.GetOption("decorations"))
      for _, rail in ipairs(UI.frame._goSlateRails) do T.assertFalse(rail:IsShown()) end
      ns.Distance.frame:Hide(); reset()
    end)
    T.it("updates hidden and future windows and restores textured tint when switching backgrounds", function()
      reset("legacy")
      local future = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
      future:Hide(); Theme.ApplyBoardSkin(future)
      Theme.SetOption("backgroundColor", "224466"); Theme.SetOption("opacity", 40)
      T.assertNear(future._goBoard._vertexColor[1], 0x22/255)
      T.assertNear(future._goBoard._vertexColor[4], .4)
      Theme.SetOption("background", "flat")
      T.assertEq(future._goBoard:GetTexture(), Theme.Textures.FLAT)
      T.assertNear(future._goBoard._vertexColor[1], 0x22/255)
      T.assertNear(future._goBoard._vertexColor[4], .4)
      Theme.SetOption("background", "gradient")
      T.assertTrue(future._goWash:IsShown())
      local later = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
      Theme.ApplyBoardSkin(later)
      T.assertNear(later._goBoard._vertexColor[1], 0x22/255)
      T.assertFalse(future:IsShown())
      later:Hide(); reset()
    end)
    T.it("preserves each preset's customizations and resets only the selected appearance", function()
      reset("slate"); choose("accentColor", "33AAFF")
      local color = Theme.Colors.TEXT_TITLE
      T.assertEq(UI.title._textColor[1], color[1])
      Theme.SetName("legacy"); Theme.ResetOptions(); Theme.SetOption("opacity", 55)
      Theme.SetName("slate")
      T.assertEq(Theme.GetOption("accentColor"), "33AAFF")
      T.assertEq(Theme.Colors.TEXT_TITLE, color)
      T.assertNear(Theme.Colors.GOLD[1], .2)
      local state, revision = ns.Core.state, ns.Core.state.rev
      UI.themeResetButton:RunScript("OnClick")
      T.assertEq(Theme.GetOption("accentColor"), "C7A363")
      T.assertEq(ns.Core.state, state); T.assertEq(state.rev, revision)
      Theme.SetName("legacy"); T.assertEq(Theme.GetOption("opacity"), 55)
      Theme.ResetOptions(); reset()
    end)
    T.it("defers all presentation until combat ends and applies the latest saved choices", function()
      reset("slate"); ns.RaidPanel.Show(); frames.finishAnimations()
      local raid, title = _G.GrosOrteilRaidPanel, UI.title._textColor[1]
      local unitButton
      for _, frame in ipairs(frames.frames) do if frame._attrs.type1 == "target" then unitButton = frame; break end end
      T.assertNotNil(unitButton)
      local unit, click = unitButton:GetAttribute("unit"), unitButton:GetScript("OnClick")
      local writes, backdrop = 0, raid.SetBackdrop
      raid.SetBackdrop = function(self, ...) writes = writes + 1; return backdrop(self, ...) end
      frames.combat = true; frames.fire("PLAYER_REGEN_DISABLED")
      Theme.SetName("legacy"); Theme.SetOption("borderSize", 8); Theme.SetOption("borderSize", 4)
      choose("accentColor", "5599CC")
      T.assertTrue(Theme.IsPending()); T.assertEq(Theme.GetName(), "slate")
      T.assertEq(writes, 0); T.assertEq(UI.title._textColor[1], title)
      Theme.Initialize(); T.assertEq(Theme.GetName(), "slate")
      frames.combat = false; frames.fire("PLAYER_REGEN_ENABLED")
      T.assertFalse(Theme.IsPending()); T.assertEq(Theme.GetName(), "legacy")
      T.assertEq(writes, 1); T.assertEq(raid._backdrop.edgeSize, 4)
      T.assertEq(unitButton:GetAttribute("unit"), unit)
      T.assertEq(unitButton:GetScript("OnClick"), click)
      T.assertEq(UI.title._textColor[1], Theme.Colors.TEXT_TITLE[1])
      raid.SetBackdrop = backdrop
      Theme.ResetOptions(); reset()
    end)
    T.it("preserves focused drafts, selected affixes and disabled button colors", function()
      reset("slate")
      ns.Core.ResetToDefaults()
      ns.Core.SetPetEnabled(true)
      ns.Core.TogglePetAffix("CAMBUSE_ATTAQUE")
      local affix = UI.petAffixButtons[1]
      T.assertNear(affix._borderColor[1], 1)
      T.assertNear(affix._borderColor[2], .35)
      local border = {unpack(affix._borderColor)}
      UI.setTab(1)
      local input = UI.inputs.hpCur
      input:SetFocus(); input:SetText("17")
      local state, revision, hp = ns.Core.state, ns.Core.state.rev, ns.Core.state.hp
      local button = CreateFrame("Button", nil, UI.frame, "BackdropTemplate")
      button._fs = button:CreateFontString(nil, "OVERLAY")
      Theme.StyleButton(button, "danger"); button:Disable()
      Theme.SetOption("accentColor", "44BB99")
      Theme.SetName("legacy")
      T.assertTrue(input:HasFocus()); T.assertEq(input:GetText(), "17")
      T.assertEq(ns.Core.state, state); T.assertEq(state.rev, revision); T.assertEq(state.hp, hp)
      T.assertEq(button._fs._textColor[1], Theme.Colors.TEXT_DISABLED[1])
      T.assertEq(input._wrap._borderColor[1], Theme.Colors.GOLD_BRIGHT[1])
      for i = 1, 4 do T.assertNear(affix._borderColor[i], border[i]) end
      input:SetText(tostring(hp)); input:ClearFocus(); button:Hide(); reset()
    end)
    T.it("keeps class selection, resource colors and health status feedback after restyling", function()
      reset("slate"); ns.Core.SetClassKey(""); ns.Core.SetClassKey("MAGE"); UI.setTab(6)
      local resource
      for _, frame in ipairs(frames.frames) do
        if frame._kind == "FontString" and frame:IsVisible() and frame:GetText():find("^•") then
          resource = frame; break
        end
      end
      T.assertNotNil(resource)
      local rgb = {unpack(resource._textColor)}
      local inactive
      for _, button in ipairs(UI.classButtons) do if button.classKey ~= "MAGE" then inactive = button; break end end
      inactive:RunScript("OnEnter"); inactive:RunScript("OnLeave")
      Theme.SetName("legacy")
      T.assertEq(inactive._borderColor[1], Theme.Colors.BROWN_DEEP[1])
      for i = 1, 4 do T.assertNear(resource._textColor[i], rgb[i]) end
      ns.Core.SetHP(0); ns.Core.SetStabilise(false)
      Theme.SetOption("accentColor", "5588AA")
      T.assertNear(UI.stabiliseBtn._borderColor[1], .85)
      ns.Core.SetStabilise(true); Theme.SetName("slate")
      T.assertNear(UI.stabiliseBtn._borderColor[2], .8)
      ns.Core.ResetToDefaults(); Theme.SetName("legacy"); Theme.ResetOptions(); reset()
    end)
    T.it("rejects invalid input and skips restyling unchanged settings", function()
      reset("slate")
      for _, pair in ipairs({{"opacity", -1}, {"opacity", 101}, {"opacity", 0/0}, {"borderSize", 17},
        {"borderSize", 2.5}, {"border", "unknown"}, {"background", {}}, {"accentColor", "oops"},
        {"decorations", "false"}, {"unknown", 5}}) do
        T.assertFalse(Theme.SetOption(pair[1], pair[2]))
      end
      edit("opacity", "101"); T.assertEq(UI.themeControls.opacity.edit:GetText(), "98")
      Theme.SetOption("opacity", 45)
      edit("opacity", ""); T.assertEq(Theme.GetOption("opacity"), 45)
      T.assertFalse(Theme.SetOption("opacity", nil))
      Theme.ResetOptions()
      local writes, backdrop = 0, UI.frame.SetBackdrop
      UI.frame.SetBackdrop = function(self, ...) writes = writes+1; return backdrop(self, ...) end
      Theme.SetOption("opacity", 98); Theme.SetName("slate")
      choose("accentColor", Theme.GetOption("accentColor"))
      T.assertEq(writes, 0)
      UI.frame.SetBackdrop = backdrop
      reset()
    end)
    T.it("previews native color choices and cancels back to the exact preset or custom color", function()
      reset("slate")
      local r = Theme.Colors.GOLD[1]
      preview("accentColor", "33AAFF")
      T.assertTrue(ColorPickerFrame:IsShown())
      T.assertFalse(ColorPickerFrame.hasOpacity)
      T.assertNear(Theme.Colors.GOLD[1], .2)
      T.assertNear(UI.themeControls.accentColor.swatch._color[3], 1)
      ColorPickerFrame.Footer.CancelButton:RunScript("OnClick")
      T.assertFalse(ColorPickerFrame:IsShown())
      T.assertEq(Theme.Colors.GOLD[1], r)
      T.assertNil(ns.GetDB().settings.themeOptions.slate.accentColor)
      choose("accentColor", "123456")
      for _, cancel in ipairs({function() ColorPickerFrame:RunScript("OnKeyDown", "ESCAPE") end,
          function() frames.fire("GLOBAL_MOUSE_DOWN", "LeftButton") end}) do
        preview("accentColor", "ABCDEF"); cancel()
        T.assertEq(Theme.GetOption("accentColor"), "123456")
        T.assertFalse(ColorPickerFrame:IsShown())
      end
      reset()
    end)
    T.it("cancels unfinished previews when changing colors, presets, tabs or resetting", function()
      reset("slate")
      local original = Theme.GetOption("accentColor")
      preview("accentColor", "33AAFF")
      preview("borderColor", "445566")
      T.assertEq(Theme.GetOption("accentColor"), original)
      UI.themeControls.preset.buttons[2]:RunScript("OnClick")
      T.assertFalse(ColorPickerFrame:IsShown())
      Theme.SetName("slate")
      T.assertEq(Theme.GetOption("accentColor"), original)
      T.assertNil(ns.GetDB().settings.themeOptions.slate.borderColor)
      preview("accentColor", "33AAFF")
      UI.setTab(1)
      T.assertEq(Theme.GetOption("accentColor"), original)
      T.assertFalse(ColorPickerFrame:IsShown())
      UI.setTab(UI.TAB_IDS.THEMES)
      preview("accentColor", "33AAFF")
      UI.themeResetButton:RunScript("OnClick")
      T.assertEq(Theme.GetOption("accentColor"), original)
      T.assertFalse(ColorPickerFrame:IsShown())
      reset()
    end)
    T.it("ignores stale picker callbacks without closing another addon's picker", function()
      reset("slate")
      UI.themeControls.accentColor.button:RunScript("OnClick")
      local stale = ColorPickerFrame:GetExtraInfo()
      local other = {}
      ColorPickerFrame:SetupColorPickerAndShow({r=1, g=0, b=0, extraInfo=other})
      stale.swatchFunc(); stale.cancelFunc()
      T.assertEq(Theme.GetOption("accentColor"), "C7A363")
      UI.setTab(1)
      T.assertTrue(ColorPickerFrame:IsShown())
      T.assertEq(ColorPickerFrame:GetExtraInfo(), other)
      ColorPickerFrame:Hide(); reset()
      UI.themeControls.accentColor.button:RunScript("OnClick")
      stale = ColorPickerFrame:GetExtraInfo()
      Theme.SetName("legacy"); Theme.ResetOptions()
      local original = Theme.GetOption("accentColor")
      ColorPickerFrame.Content.ColorPicker:SetColorRGB(1, 0, 0)
      stale.cancelFunc()
      T.assertEq(Theme.GetOption("accentColor"), original)
      ColorPickerFrame:Hide(); reset()
    end)
    T.it("cancels a combat preview before applying the final saved appearance", function()
      reset("slate")
      local original = Theme.Colors.GOLD[1]
      frames.combat = true
      preview("accentColor", "33AAFF")
      T.assertEq(Theme.Colors.GOLD[1], original)
      T.assertTrue(Theme.IsPending())
      ColorPickerFrame.Footer.CancelButton:RunScript("OnClick")
      frames.combat = false; frames.fire("PLAYER_REGEN_ENABLED")
      T.assertEq(Theme.Colors.GOLD[1], original)
      T.assertNil(ns.GetDB().settings.themeOptions.slate.accentColor)
      reset()
    end)
    T.it("loads saved overrides before building windows and tolerates malformed saved values", function()
      local db = {settings = {theme = "legacy", themeOptions = {legacy = {accentColor = "123456", opacity = 30,
        border = "flat", borderSize = 3, decorations = false, background = "flat"}}}}
      local fresh = {GetDB = function() return db end}
      assert(loadfile("GrosOrteil_Theme.lua"))("GrosOrteil", fresh)
      fresh.Theme.Initialize()
      local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
      fresh.Theme.ApplyBoardSkin(frame); fresh.Theme.ApplyBoardRails(frame)
      T.assertNear(fresh.Theme.Colors.GOLD[1], 0x12/255)
      T.assertNear(frame._goBoard._vertexColor[4], .3)
      T.assertEq(frame._backdrop.edgeSize, 3)
      for _, rail in ipairs(frame._goLegacyRails) do T.assertFalse(rail:IsShown()) end
      db.settings.themeOptions.slate = {borderSize = 0/0, opacity = math.huge, accentColor = {}, background = false}
      fresh.Theme.SetName("slate")
      T.assertEq(fresh.Theme.GetOption("borderSize"), 1)
      T.assertEq(fresh.Theme.GetOption("opacity"), 98)
      T.assertEq(fresh.Theme.GetOption("background"), "gradient")
      frame:Hide()
    end)
    T.it("applies each color palette once while preserving the rest of the selected theme", function()
      reset("slate")
      Theme.SetOptions({border="tooltip", borderSize=5, background="flat", opacity=70, decorations=false})
      local writes, backdrop = 0, UI.frame.SetBackdrop
      UI.frame.SetBackdrop = function(self, ...) writes = writes+1; return backdrop(self, ...) end
      for i, preset in ipairs(Theme.ColorPresets) do
        writes = 0
        UI.themeControls.palette.buttons[i]:RunScript("OnClick")
        T.assertEq(writes, 1)
        for key, value in pairs(preset.colors) do T.assertEq(Theme.GetOption(key), value) end
        for j, button in ipairs(UI.themeControls.palette.buttons) do
          T.assertEq(not not button._goSelection, i == j)
        end
        T.assertEq(Theme.GetSelectedName(), "slate")
        T.assertEq(Theme.GetOption("border"), "tooltip")
        T.assertEq(Theme.GetOption("borderSize"), 5)
        T.assertEq(Theme.GetOption("background"), "flat")
        T.assertEq(Theme.GetOption("opacity"), 70)
        T.assertFalse(Theme.GetOption("decorations"))
        UI.themeControls.palette.buttons[i]:RunScript("OnClick")
        T.assertEq(writes, 1, "reselecting the same palette must not repaint")
      end
      UI.frame.SetBackdrop = backdrop
      reset()
    end)
    T.it("keeps palette colors editable, restores picker cancellation, and isolates base themes", function()
      reset("slate")
      UI.themeControls.palette.buttons[1]:RunScript("OnClick")
      local monochrome = Theme.ColorPresets[1].colors
      preview("accentColor", "ABCDEF")
      ColorPickerFrame.Footer.CancelButton:RunScript("OnClick")
      T.assertEq(Theme.GetOption("accentColor"), monochrome.accentColor)
      preview("accentColor", "ABCDEF")
      UI.themeControls.palette.buttons[2]:RunScript("OnClick")
      T.assertFalse(ColorPickerFrame:IsShown())
      choose("accentColor", "123456")
      for _, button in ipairs(UI.themeControls.palette.buttons) do T.assertFalse(button._goSelection) end
      Theme.SetName("legacy"); Theme.ResetOptions()
      UI.themeControls.palette.buttons[3]:RunScript("OnClick")
      Theme.SetName("slate")
      T.assertEq(Theme.GetOption("accentColor"), "123456")
      T.assertEq(Theme.GetOption("backgroundColor"), Theme.ColorPresets[2].colors.backgroundColor)
      Theme.SetName("legacy")
      T.assertEq(Theme.GetOption("accentColor"), Theme.ColorPresets[3].colors.accentColor)
      UI.themeResetButton:RunScript("OnClick")
      T.assertNil(ns.GetDB().settings.themeOptions.legacy)
      reset()
    end)
    T.it("validates a palette atomically and defers its complete appearance in combat", function()
      reset("slate")
      local original = Theme.GetOption("accentColor")
      T.assertFalse(Theme.SetOptions({accentColor="ABCDEF", backgroundColor="invalid"}))
      T.assertEq(Theme.GetOption("accentColor"), original)
      local rgb = Theme.Colors.GOLD[1]
      frames.combat = true
      UI.themeControls.palette.buttons[5]:RunScript("OnClick")
      T.assertEq(Theme.Colors.GOLD[1], rgb)
      T.assertTrue(Theme.IsPending())
      frames.combat = false; frames.fire("PLAYER_REGEN_ENABLED")
      for key, value in pairs(Theme.ColorPresets[5].colors) do T.assertEq(Theme.GetOption(key), value) end
      local r = Theme.ColorRGB(Theme.ColorPresets[5].colors.accentColor)
      T.assertNear(Theme.Colors.GOLD[1], r)
      reset()
    end)
    T.it("repeatedly switches without adding regions, animations, reloads or idle callbacks", function()
      reset("slate")
      local regions, animations, reloads = #frames.frames, #frames.animations, frames.reloads
      for i = 1, 6 do
        Theme.SetName(i % 2 == 1 and "legacy" or "slate")
        choose("accentColor", i % 2 == 1 and "AA8866" or "6688AA")
      end
      T.assertEq(#frames.frames, regions); T.assertEq(#frames.animations, animations)
      T.assertEq(frames.reloads, reloads)
      reset(); ns.Distance.frame:Hide(); frames.finishAnimations()
      for _, frame in ipairs(frames.frames) do T.assertNil(frame:GetScript("OnUpdate"), frame._name or frame._kind) end
    end)
  end)
end
