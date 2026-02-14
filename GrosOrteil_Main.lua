local ADDON, ns = ...

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")

f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    GrosOrteilDB = GrosOrteilDB or {}
  elseif event == "PLAYER_LOGIN" then
    ns.Core_Init()
    ns.UI_Init()

    SLASH_GROSORTEIL1 = "/grosorteil"
    SLASH_GROSORTEIL2 = "/go"
    SlashCmdList["GROSORTEIL"] = function(msg)
      msg = (msg or ""):lower()
      if msg == "show" then
        ns.UI_Show(true)
      elseif msg == "hide" then
        ns.UI_Show(false)
      elseif msg == "reset" then
        ns.UI_ResetPosition()
      else
        print("|cFF00FF00GrosOrteil|r commandes : /go show | /go hide | /go reset")
      end
    end
  end
end)
