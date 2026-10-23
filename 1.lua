-- ========================================================================
-- ⚡ DevLET ULTIMATE v5 — MAX LEVEL
-- ========================================================================
-- PRIVATE SAFE PREMIUM LUA — POWER BY DEVLET
-- CREDIT: @TrnDravix | @Code_Leak
-- ========================================================================

local ENetRole          = import("ENetRole")
local EPawnState        = import("EPawnState")
local KismetMathLibrary = import("KismetMathLibrary")
local GameplayStatics   = import("GameplayStatics")
local GameplayData      = require("GameLua.GameCore.Data.GameplayData")
local InGameMarkTools   = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")
local GamePlayTools     = require("GameLua.Mod.BaseMod.Common.GamePlayTools")

-- ========================================================================
-- [1] FEATURE FLAGS
-- ========================================================================
if _G.DevESP       == nil then _G.DevESP       = true  end
if _G.DevCounter   == nil then _G.DevCounter   = true  end
if _G.DevLines     == nil then _G.DevLines     = true  end
if _G.DevWall      == nil then _G.DevWall      = true  end
if _G.DevForce     == nil then _G.DevForce     = true  end
if _G.DevAssist    == nil then _G.DevAssist    = true  end
if _G.DevCircle    == nil then _G.DevCircle    = true  end
if _G.DevCross     == nil then _G.DevCross     = true  end
if _G.DevBlackSky  == nil then _G.DevBlackSky  = true  end
if _G.DevNoFog     == nil then _G.DevNoFog     = true  end
if _G.DevNoGrass   == nil then _G.DevNoGrass   = false end
if _G.DevWatermark == nil then _G.DevWatermark = true  end

-- ========================================================================
-- [2] LOGIN SYSTEM — Premium Max Level UI
-- ========================================================================
local LoginSystem = (function()
    local Config = {
        LOGIN_URL    = "https://oxslghxcdxhcniulfjws.supabase.co/functions/v1/verify-license",
        KEY_FILE     = "/storage/emulated/0/Android/data/com.pubg.imobile/files/keys.txt",
        UID_FILE     = "/storage/emulated/0/Android/data/com.pubg.imobile/files/uid.txt",
        BRAND_NAME   = "DEVSLET",
        BRAND_LINE2  = "CORE",
        BRAND_SUB    = "PUBLIC ACCESS",
        VERSION      = "v5.0 ELITE",
        SUPPORT_TEXT = "Powered by DEVLET  •  Support : @DevsLet",
        TELEGRAM_URL = "https://t.me/l",
    }
    local function normalizeError(raw)
        local v = tostring(raw or ""):lower()
        if v == "invalid_key" or v == "invalid" or v == "key_not_found" then return "invalid" end
        if v == "revoked" or v == "blocked" or v == "key_revoked" then return "blocked" end
        if v == "expired" or v == "key_expired" then return "expired" end
        if v == "device_limit_reached" or v == "device_limit" then return "device_limit" end
        if v == "missing_key" or v == "missing_device_id" then return "missing" end
        return "nonet"
    end
    local function esc(s) return (tostring(s or ""):gsub("\\","\\\\"):gsub('"','\\"'):gsub("\r","\\r"):gsub("\n","\\n")) end
    local function getDeviceId()
        local id = nil
        pcall(function() if Client and Client.GetPhoneDeviceID then id = Client.GetPhoneDeviceID() end end)
        pcall(function()
            if not id or id == "" then
                local ksl = import("KismetSystemLibrary")
                if ksl then
                    if ksl.GetDeviceId then id = ksl:GetDeviceId() end
                    if (not id or id == "") and ksl.GetDeviceIdOS then id = ksl:GetDeviceIdOS() end
                end
            end
        end)
        return (id and id ~= "") and id or nil
    end
    local function getPlayerUid()
        local uid = nil
        pcall(function()
            local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
            if pc then
                if pc.UID then uid = tostring(pc.UID) end
                if (not uid or uid == "" or uid == "0") and pc.PlayerState and pc.PlayerState.UID then
                    uid = tostring(pc.PlayerState.UID)
                end
            end
        end)
        if uid == "" or uid == "0" then return nil end
        return uid
    end
    local function getFileUid()
        local uid = nil
        pcall(function()
            local f = io.open(Config.UID_FILE, "r")
            if f then uid = f:read("*all"); f:close() end
            if uid then uid = uid:gsub("%s+","") end
            if not uid or uid == "" then
                uid = "ZN-" .. tostring(math.random(100000,999999)) .. tostring(os.time())
                local w = io.open(Config.UID_FILE, "w")
                if w then w:write(uid); w:close() end
            end
            if uid == "" then uid = nil end
        end)
        return uid
    end
    local function getSerial() return getDeviceId() or getPlayerUid() or getFileUid() end
    local function readKeyFile()
        local k = nil
        pcall(function()
            local f = io.open(Config.KEY_FILE, "r")
            if f then k = f:read("*all"); f:close() end
            if k then k = k:gsub("%s+","") end
            if k == "" then k = nil end
        end)
        return k
    end
    local function saveKey(k)
        _G._LICENSE_KEY = k
        pcall(function()
            local f = io.open(Config.KEY_FILE, "w")
            if f then f:write(k); f:close() end
        end)
    end
    local function getCurrentKey()
        if _G._LICENSE_KEY and _G._LICENSE_KEY ~= "" then return _G._LICENSE_KEY end
        return readKeyFile()
    end
    local function checkLicense(key, uid, cb)
        local http = nil
        pcall(function() http = ModuleManager.GetModule(ModuleManager.CommonModuleConfig.http_manager) end)
        if not (http and http.Post) then cb(false, "nonet", nil) return end
        if not key or key == "" or not uid or uid == "" then cb(false, "missing", nil) return end
        local headers = { ["Content-Type"] = "application/json", ["Accept"] = "application/json" }
        local body = '{"key":"' .. esc(key) .. '","device_id":"' .. esc(uid) .. '"}'
        http:Post(Config.LOGIN_URL, headers, body, nil,
            function(ok, response, status, err)
                local code = tonumber(status) or 0
                local resp = response and tostring(response) or ""
                local errt = err and tostring(err) or ""
                if ok then
                    if resp == "" then cb(false, "net:empty server response", nil) return end
                    if resp:find('"ok"%s*:%s*true') or resp:find('"valid"%s*:%s*true')
                       or resp:find('"success"%s*:%s*true') then
                        local exp = resp:match('"expires_at"%s*:%s*"([^"]+)"')
                                 or resp:match('"expiry"%s*:%s*"([^"]+)"')
                                 or resp:match('"expires"%s*:%s*"([^"]+)"')
                        cb(true, nil, exp)
                        return
                    end
                    local e = resp:match('"error"%s*:%s*"([^"]+)"')
                           or resp:match('"code"%s*:%s*"([^"]+)"')
                           or resp:match('"reason"%s*:%s*"([^"]+)"')
                           or resp:match('"message"%s*:%s*"([^"]+)"')
                    cb(false, normalizeError(e), nil)
                    return
                end
                local msg = errt
                if msg == "" and code > 0 then msg = "HTTP " .. tostring(code) end
                cb(false, "net:" .. msg, nil)
            end)
    end
    local function showMsg(t, b)
        pcall(function()
            local box = require("client.slua.logic.common.logic_common_msg_box")
            if box and box.Show then box.Show(4, t, b) end
        end)
    end
    local function openTelegram()
        pcall(function()
            local ksl = import("KismetSystemLibrary")
            if ksl and ksl.LaunchURL then ksl.LaunchURL(Config.TELEGRAM_URL) end
        end)
    end
    local M = {}
    local function mkVec2(x, y)
        local ok, v = pcall(function()
            local V = import("Vector2D")
            if type(V) == "function" then return V(x, y) end
            if V and V.New then return V:New(x, y) end
            if V and V.new then return V.new(x, y) end
            return FVector2D(x, y)
        end)
        return ok and v or FVector2D(x, y)
    end
    local function getCanvas()
        local canvas = nil
        pcall(function()
            local ui = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools").GetMainControlBaseUI()
            if ui and slua.isValid(ui) then
                canvas = ui.CanvasPanel_0
                if not (canvas and slua.isValid(canvas)) then canvas = ui.CanvasPanel_42 end
            end
        end)
        return canvas
    end
    local function addBorder(parent, color, x, y, w, h, z)
        local b = CGame:NewObjectFromPath("/Script/UMG.Border", parent)
        if not (b and slua.isValid(b)) then return nil end
        pcall(function()
            b:SetBrushColor(color)
            b:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
        local slot = parent:AddChildToCanvas(b)
        if slot then
            pcall(function()
                slot:SetAlignment(mkVec2(0.5, 0.5))
                slot:SetPosition(mkVec2(x, y))
                slot:SetSize(mkVec2(w, h))
                slot:SetZOrder(z or 9999)
            end)
        end
        return b
    end
    local function addText(parent, text, size, color, x, y, alignX, alignY)
        local tb = CGame:NewObjectFromPath("/Script/UMG.TextBlock", parent)
        if not (tb and slua.isValid(tb)) then return nil end
        pcall(function()
            tb:SetText(tostring(text))
            local SC = import("SlateColor") or import("/Script/SlateCore.SlateColor")
            if SC then tb:SetColorAndOpacity(SC(color)) else tb:SetColorAndOpacity(color) end
            if tb.Font then local f = tb.Font f.Size = size tb.Font = f end
            if tb.SetJustification then tb:SetJustification(1) end
            if tb.SetAutoWrapText then tb:SetAutoWrapText(false) end
            tb:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
        local slot = parent:AddChildToCanvas(tb)
        if slot then
            pcall(function()
                slot:SetAutoSize(true)
                slot:SetAlignment(mkVec2(alignX or 0.5, alignY or 0.5))
                slot:SetPosition(mkVec2(x, y))
                slot:SetZOrder(9999)
            end)
        end
        return tb
    end
    local function addButton(parent, x, y, w, h, label, r, g, b, onClick)
        local btn = CGame:NewObjectFromPath("/Script/UMG.Button", parent)
        if not (btn and slua.isValid(btn)) then return nil end
        local slot = parent:AddChildToCanvas(btn)
        if slot then
            pcall(function()
                slot:SetAlignment(mkVec2(0.5, 0.5))
                slot:SetPosition(mkVec2(x, y))
                slot:SetSize(mkVec2(w, h))
                slot:SetZOrder(9999)
            end)
        end
        pcall(function()
            local LC = import("LinearColor")
            if btn.SetBackgroundColor then btn:SetBackgroundColor(LC(r*0.12, g*0.12, b*0.12, 0.98)) end
        end)
        local txt = CGame:NewObjectFromPath("/Script/UMG.TextBlock", btn)
        if txt and slua.isValid(txt) then
            pcall(function()
                txt:SetText(label)
                local LC = import("LinearColor")
                local SC = import("SlateColor") or import("/Script/SlateCore.SlateColor")
                local lin = LC(r, g, b, 1)
                if SC then txt:SetColorAndOpacity(SC(lin)) else txt:SetColorAndOpacity(lin) end
                if txt.Font then local f = txt.Font f.Size = 22 txt.Font = f end
                txt:SetWidgetVisibility(UEnums.ESlateVisibility.HitTestInvisible)
                pcall(function() btn:AddChild(txt) end)
            end)
        end
        pcall(function()
            if btn.OnClicked and btn.OnClicked.Add then btn.OnClicked:Add(function() onClick() end) end
        end)
        return btn
    end
    local function addInput(parent, x, y, w, h)
        local box = CGame:NewObjectFromPath("/Script/UMG.EditableTextBox", parent)
        if not (box and slua.isValid(box)) then return nil end
        local slot = parent:AddChildToCanvas(box)
        if slot then
            pcall(function()
                slot:SetAlignment(mkVec2(0.5, 0.5))
                slot:SetPosition(mkVec2(x, y))
                slot:SetSize(mkVec2(w, h))
                slot:SetZOrder(9999)
            end)
        end
        pcall(function()
            if box.SetHintText then box:SetHintText("Paste your premium key here...") end
            if box.SetKeyboardFocus then box:SetKeyboardFocus() end
        end)
        return box
    end
    local function getInputText(box)
        if not (box and slua.isValid(box) and box.GetText) then return nil end
        local txt = nil
        pcall(function()
            local t = box:GetText()
            if type(t) == "string" then txt = t
            elseif t and t.ToString then txt = t:ToString()
            else txt = tostring(t) end
        end)
        if txt == "" then return nil end
        return txt
    end
    local function setStatus(msg, isError)
        pcall(function()
            if _G._LOGIN_STATUS and slua.isValid(_G._LOGIN_STATUS) then
                _G._LOGIN_STATUS:SetText(tostring(msg))
                local LC = import("LinearColor")
                local SC = import("SlateColor") or import("/Script/SlateCore.SlateColor")
                local lin = isError and LC(1.0, 0.10, 0.18, 1) or LC(0.30, 0.95, 0.55, 1)
                if SC then _G._LOGIN_STATUS:SetColorAndOpacity(SC(lin))
                else _G._LOGIN_STATUS:SetColorAndOpacity(lin) end
            end
        end)
    end
    local function destroyLoginUI()
        pcall(function()
            if _G._LOGIN_UI and slua.isValid(_G._LOGIN_UI) then
                _G._LOGIN_UI:RemoveFromParent()
                if _G._LOGIN_UI.ConditionalBeginDestroy then _G._LOGIN_UI:ConditionalBeginDestroy() end
            end
        end)
        _G._LOGIN_UI, _G._LOGIN_BOX, _G._LOGIN_BTN, _G._GETKEY_BTN = nil, nil, nil, nil
        _G._LOGIN_STATUS, _G._LOGIN_TRYING = nil, false
    end

    -- ========================================================================
    -- ⭐ NEW ANIMATED UI (Magoo Core style)
    -- ========================================================================
    M.Build = function(pawn, hint, onSuccess)
        destroyLoginUI()
        local built = false
        pcall(function()
            local canvas = getCanvas()
            if not canvas then return end
            local LC = import("LinearColor")
            local vw, vh = 1920, 1080
            pcall(function()
                local uu = require("client.common.ui_util")
                if uu and uu.GetViewportSize then
                    local sz = uu.GetViewportSize()
                    if sz and sz.X and sz.X > 0 then vw = sz.X vh = sz.Y end
                end
            end)

            local root = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", canvas)
            if not (root and slua.isValid(root)) then return end
            local rs = canvas:AddChildToCanvas(root)
            if rs then
                pcall(function()
                    rs:SetPosition(mkVec2(0, 0))
                    rs:SetSize(mkVec2(vw, vh))
                    rs:SetZOrder(9989)
                end)
            end

            -- FULL SCREEN BACKDROP
            addBorder(root, LC(0.005, 0.006, 0.010, 0.995),
                      vw*0.5, vh*0.5, vw, vh, 9990)

            -- PANEL FRAME
            local pw = math.min(vw * 0.94, 1780)
            local ph = math.min(vh * 0.88, 960)
            local px, py = vw*0.5, vh*0.5

            addBorder(root, LC(1.0, 0.10, 0.18, 0.35),
                      px, py, pw + 12, ph + 12, 9991)
            addBorder(root, LC(0.012, 0.016, 0.024, 0.995),
                      px, py, pw, ph, 9992)
            addBorder(root, LC(0.020, 0.025, 0.038, 1.0),
                      px, py, pw - 8, ph - 8, 9993)

            -- Red rails + top/bottom bars
            local railTh = 3
            addBorder(root, LC(1.0, 0.10, 0.18, 1.0),
                      px, py - ph*0.5 + railTh*0.5, pw, railTh, 9994)
            addBorder(root, LC(1.0, 0.10, 0.18, 1.0),
                      px, py + ph*0.5 - railTh*0.5, pw, railTh, 9994)
            addBorder(root, LC(1.0, 0.10, 0.18, 1.0),
                      px - pw*0.5 + railTh*0.5, py, railTh, ph, 9994)
            addBorder(root, LC(1.0, 0.10, 0.18, 1.0),
                      px + pw*0.5 - railTh*0.5, py, railTh, ph, 9994)
            addBorder(root, LC(1.0, 0.10, 0.18, 0.85),
                      px, py - ph*0.5 + 55, pw - 20, 2, 9995)
            addBorder(root, LC(1.0, 0.10, 0.18, 0.85),
                      px, py + ph*0.5 - 55, pw - 20, 2, 9995)

            -- TOP BAR
            local topY = py - ph*0.5 + 30
            addText(root, "BATTLEGROUNDS", 14, LC(0.88, 0.90, 0.94, 1),
                    px - pw*0.5 + 40, topY, 0, 0.5)
            addText(root, "MOBILE INDIA", 12, LC(0.62, 0.66, 0.72, 1),
                    px - pw*0.5 + 40, topY + 20, 0, 0.5)

            local chipW, chipH = 200, 32
            local chipX = px + pw*0.5 - chipW*0.5 - 40
            addBorder(root, LC(0.10, 0.28, 0.20, 0.85),
                      chipX, topY + 4, chipW, chipH, 9996)
            addText(root, "●  SERVER ONLINE", 14, LC(0.30, 0.95, 0.55, 1),
                    chipX, topY + 4, 0.5, 0.5)
            addText(root, Config.VERSION, 12, LC(0.72, 0.76, 0.82, 1),
                    chipX, topY + 34, 0.5, 0.5)

            -- LEFT PANEL
            local lpW = pw * 0.26
            local lpH = ph * 0.58
            local lpX = px - pw*0.5 + lpW*0.5 + 40
            local lpY = py + 20
            addBorder(root, LC(1.0, 0.10, 0.18, 0.10),
                      lpX, lpY, lpW, lpH, 9996)

            local bX = lpX
            local bY = lpY - lpH*0.28

            addText(root, "♛", 30, LC(1.0, 0.10, 0.18, 1),
                    bX - 55, bY - 30, 0.5, 0.5)
            addText(root, Config.BRAND_NAME, 68, LC(1.0, 0.10, 0.18, 1),
                    bX - 30, bY + 30, 0.5, 0.5)
            addText(root, Config.BRAND_LINE2, 68, LC(1, 1, 1, 1),
                    bX + 30, bY + 95, 0.5, 0.5)
            addBorder(root, LC(1.0, 0.10, 0.18, 1),
                      bX, bY + 155, 60, 3, 9997)

            addText(root, "PLAY", 26, LC(1, 1, 1, 1),
                    bX - 20, bY + 205, 0.5, 0.5)
            addText(root, "SMART", 26, LC(1.0, 0.10, 0.18, 1),
                    bX + 15, bY + 240, 0.5, 0.5)
            addText(root, "STAY AHEAD", 20, LC(1, 1, 1, 1),
                    bX + 5, bY + 275, 0.5, 0.5)

            -- CENTER
            local cx2 = px + pw*0.02
            addText(root, "PUBLIC ACCESS", 13, LC(0.78, 0.82, 0.88, 1),
                    cx2, py - ph*0.34, 0.5, 0.5)
            addText(root, "LICENSE ACCESS", 30, LC(1, 1, 1, 1),
                    cx2, py - ph*0.28, 0.5, 0.5)
            addText(root, "Enter your license key to continue", 13, LC(0.72, 0.76, 0.82, 1),
                    cx2, py - ph*0.23, 0.5, 0.5)

            addBorder(root, LC(1.0, 0.10, 0.18, 0.85),
                      cx2 - pw*0.22, py - ph*0.21, pw*0.16, 2, 9997)
            addBorder(root, LC(1.0, 0.10, 0.18, 0.85),
                      cx2 + pw*0.22, py - ph*0.21, pw*0.16, 2, 9997)

            -- INPUT
            local iw = pw * 0.55
            local ih = 66
            local ix = cx2
            local iy = py - ph*0.10

            addBorder(root, LC(1.0, 0.10, 0.18, 1),
                      ix, iy, iw + 6, ih + 6, 9997)
            addBorder(root, LC(0.90, 0.90, 0.905, 1),
                      ix, iy, iw, ih, 9998)

            _G._LOGIN_BOX = addInput(root, ix, iy, iw - 30, ih - 20)

            local sTxt = hint or "Type key, then press LOGIN"
            _G._LOGIN_STATUS = addText(root, sTxt, 14, LC(1.0, 0.10, 0.18, 1),
                    ix, py - ph*0.025, 0.5, 0.5)

            -- BUTTONS
            local by2 = py + ph*0.075
            local bw  = pw * 0.265
            local bh  = 66

            _G._GETKEY_BTN = addButton(root, cx2 - iw*0.25, by2, bw, bh,
                "✈  GET LICENSE", 0.85, 0.10, 0.18,
                function()
                    setStatus("Opening Telegram...", false)
                    openTelegram()
                end)
            addBorder(root, LC(0.72, 0.75, 0.80, 1),
                      cx2 - iw*0.25, by2, bw + 4, bh + 4, 9999)

            _G._LOGIN_BTN = addButton(root, cx2 + iw*0.25, by2, bw, bh,
                "◈  VERIFY LICENSE  →", 1.0, 0.10, 0.18,
                function()
                    local key = getInputText(_G._LOGIN_BOX)
                    if not key or #key < 4 then setStatus("Enter a valid key", true) return end
                    if _G._LOGIN_TRYING then return end
                    _G._LOGIN_TRYING = true
                    setStatus("Authenticating...", false)
                    local uid = getSerial()
                    checkLicense(key, uid, function(ok, err)
                        _G._LOGIN_TRYING = false
                        if ok then
                            saveKey(key)
                            _G._LICENSE_OK, _G._LICENSE_KEY, _G._LICENSE_UID = true, key, uid
                            setStatus("Login successful - activating", false)
                            destroyLoginUI()
                            if onSuccess then onSuccess() end
                        elseif err == "invalid" then setStatus("Invalid key - please re-enter", true)
                        elseif err == "blocked" then setStatus("Key has been blocked", true)
                        elseif err == "expired" then setStatus("Key has expired", true)
                        elseif err == "device_limit" then setStatus("Locked to another device", true)
                        else setStatus("Network error - please retry", true) end
                    end)
                end)
            addBorder(root, LC(1, 1, 1, 0.9),
                      cx2 + iw*0.25, by2, bw + 4, bh + 4, 9999)

            -- STATUS STRIP
            local stripW = pw * 0.55
            local stripH = 74
            local sx = cx2
            local sy = py + ph*0.23

            addBorder(root, LC(1.0, 0.10, 0.18, 0.85),
                      sx, sy, stripW + 4, stripH + 4, 9999)
            addBorder(root, LC(0.045, 0.065, 0.075, 0.95),
                      sx, sy, stripW, stripH, 9999)

            addText(root, "●  SECURE LICENSE VERIFICATION", 13, LC(0.30, 0.95, 0.55, 1),
                    sx, sy - 14, 0.5, 0.5)

            local rowY = sy + 18
            addText(root, "⬢  Encrypted Connection", 12, LC(0.80, 0.84, 0.90, 1),
                    sx - stripW*0.32, rowY, 0.5, 0.5)
            addBorder(root, LC(0.28, 0.32, 0.40, 1),
                      sx - stripW*0.12, rowY, 1, 14, 10000)
            addText(root, "⬢  Safe & Secure", 12, LC(0.80, 0.84, 0.90, 1),
                    sx, rowY, 0.5, 0.5)
            addBorder(root, LC(0.28, 0.32, 0.40, 1),
                      sx + stripW*0.12, rowY, 1, 14, 10000)
            addText(root, "⬢  Instant Verification", 12, LC(0.80, 0.84, 0.90, 1),
                    sx + stripW*0.32, rowY, 0.5, 0.5)

            -- RIGHT PANEL
            local rpx = px + pw*0.5 - 200
            local rpy = py - ph*0.30

            addText(root, "FEATURE ACCESS", 13, LC(0.85, 0.88, 0.94, 1),
                    rpx, rpy, 0.5, 0.5)

            local FEATURES = {
                "AIMBOT", "ESP", "WALLHACK", "ANTIBAN",
                "ACTIVE GRENADE", "& MORE...",
            }
            local fx = rpx - 10
            local fy = rpy + 55
            for i, feat in ipairs(FEATURES) do
                addBorder(root, LC(1.0, 0.10, 0.18, 0.25),
                          fx - 90, fy + (i-1)*48, 18, 18, 10000)
                addText(root, "◆", 12, LC(1.0, 0.10, 0.18, 1),
                        fx - 90, fy + (i-1)*48, 0.5, 0.5)
                addText(root, feat, 14, LC(0.90, 0.92, 0.96, 1),
                        fx - 70, fy + (i-1)*48, 0, 0.5)
            end

            -- FOOTER
            local fy2 = py + ph*0.5 - 32
            addText(root, "♛", 20, LC(1.0, 0.10, 0.18, 1),
                    px - pw*0.5 + 50, fy2, 0, 0.5)
            addText(root, "DEVLET CORE  |  PREMIUM GAME ENHANCEMENT", 14, LC(0.72, 0.76, 0.82, 1),
                    px - pw*0.5 + 80, fy2, 0, 0.5)
            addText(root, "DIFFERENT LEVEL", 18, LC(1.0, 0.10, 0.18, 1),
                    px + pw*0.5 - 40, fy2 - 10, 1, 0.5)
            addText(root, "SAME GAME", 18, LC(1, 1, 1, 1),
                    px + pw*0.5 - 40, fy2 + 14, 1, 0.5)

            _G._LOGIN_UI = root
            built = true
        end)
        return built
    end

    M.Start = function(pawn, onSuccess)
        if _G._LICENSE_OK then if onSuccess then onSuccess() end return end
        local savedKey = getCurrentKey()
        if savedKey then
            local uid = getSerial()
            checkLicense(savedKey, uid, function(ok)
                if ok then
                    _G._LICENSE_OK, _G._LICENSE_KEY, _G._LICENSE_UID = true, savedKey, uid
                    if onSuccess then onSuccess() end
                else
                    if not M.Build(pawn, "Key invalid — re-enter", onSuccess) then
                        showMsg("KEY ERROR", "Login screen failed to open.")
                    end
                end
            end)
        else
            if not M.Build(pawn, "Enter your access key", onSuccess) then
                showMsg("KEY ERROR", "Login screen failed to open.")
            end
        end
    end
    M.StartPeriodicCheck = function(pawn)
        local timer = nil
        pcall(function()
            local function tick()
                if not slua.isValid(pawn.Object) then return end
                if not _G._LICENSE_OK then return end
                local key = getCurrentKey()
                local uid = _G._LICENSE_UID or getSerial()
                if not (key and uid) then return end
                checkLicense(key, uid, function(ok, err)
                    if not ok and err ~= "nonet" then
                        _G._LICENSE_OK = false
                        pcall(function() if _G.LoginSystem_OnRevoked then _G.LoginSystem_OnRevoked(err) end end)
                        showMsg("LICENSE REVOKED", "Your key is no longer valid.")
                        pcall(function() if M.Build then M.Build(pawn, "License revoked — re-enter key", nil) end end)
                    end
                end)
            end
            timer = pawn:AddGameTimer(180, true, tick)
        end)
        _G._LOGIN_TIMER = timer
        _G._LOGIN_CHAR = pawn
        return timer
    end
    M.CheckLicense = checkLicense
    M.GetSerial = getSerial
    M.GetCurrentKey = getCurrentKey
    M.SaveKey = saveKey
    M.Config = Config
    M.IsLoggedIn = function() return _G._LICENSE_OK == true end
    M.Logout = function()
        _G._LICENSE_OK, _G._LICENSE_KEY, _G._LICENSE_UID = nil, nil, nil
        pcall(function()
            local f = io.open(Config.KEY_FILE, "w")
            if f then f:write(""); f:close() end
        end)
    end
    return M
end)()

_G.LoginSystem = LoginSystem

function _G.LoginSystem_OnRevoked()
    _G._LICENSE_OK = false
    _G.WelcomeShown = false
end

function CheckExpiration()
    if _G._LICENSE_OK == true then _G._MOD_EXPIRED = false return true end
    _G._MOD_EXPIRED = true
    return false
end
local function ShowExpiryPopup(exp)
    pcall(function()
        local Msg = require("client.slua.logic.common.logic_common_msg_box")
        if exp then Msg.Show(4, "LICENSE REQUIRED", "Your license is not active.", function() end)
        else Msg.Show(4, "LICENSE VERIFIED", "Your license is active.", function() end) end
    end)
end
function _G.TryShowWelcome()
    if _G.WelcomeShown then return end
    if not CheckExpiration() then ShowExpiryPopup(true) return end
    ShowExpiryPopup(false)
    _G.WelcomeShown = true
end
_G._MOD_EXPIRED = false

-- ========================================================================
-- [3] WELCOME MESSAGE POPUP
-- ========================================================================
function _G.DevShowWelcomeMessage()
    pcall(function()
        local Msg = package.loaded["client.slua.logic.common.logic_common_msg_box"]
                 or require("client.slua.logic.common.logic_common_msg_box")
        local Web = require("client.slua.logic.url.logic_webview_sdk")
        local function onClick()
            if Web then Web:OpenURL("https://t.me/l") end
        end
        if Msg and Msg.Show then
            Msg.Show(4, "✦ DEVSLET PREMIUM LOADED ✦",
                "\n★ Developer : @DevsLet\n" ..
                "★ Status    : UNDETECTED & OPTIMIZED\n" ..
                "★ Bypass    : 40-Layer Ultimate\n" ..
                "★ Mode      : PRIVATE SAFE PREMIUM LUA\n\n" ..
                "✓ POWER BY DEVLET — READY TO DOMINATE!", onClick)
        end
    end)
end

-- ========================================================================
-- [4] WORLD VISUALS — FIXED (Black Sky / No Fog / No Grass)
-- ========================================================================
local WorldVis = {
    Console = {
        SkyOn = {
            "r.SkyAtmosphere 0", "r.SkyLight 0", "r.Atmosphere 0",
            "r.SkyLightIntensity 0", "r.SkyLight.AmbientContribution 0",
            "r.Mobile.SkyAtmosphere 0", "r.MobileHDR 0",
            "r.DefaultFeature.AutoExposure 0", "r.EyeAdaptationQuality 0"
        },
        SkyOff = {
            "r.SkyAtmosphere 1", "r.SkyLight 1", "r.Atmosphere 1",
            "r.SkyLightIntensity 1", "r.SkyLight.AmbientContribution 1",
            "r.Mobile.SkyAtmosphere 1", "r.MobileHDR 1",
            "r.DefaultFeature.AutoExposure 1", "r.EyeAdaptationQuality 1"
        },
        FogOn = {
            "r.Fog 0", "r.VolumetricFog 0", "r.AtmosphericFog 0",
            "r.SceneColorFringeQuality 0", "r.DepthOfFieldQuality 0",
            "r.Mobile.Fog 0", "r.Mobile.SceneColorFringeQuality 0"
        },
        FogOff = {
            "r.Fog 1", "r.VolumetricFog 1", "r.AtmosphericFog 1",
            "r.SceneColorFringeQuality 1", "r.DepthOfFieldQuality 1",
            "r.Mobile.Fog 1", "r.Mobile.SceneColorFringeQuality 1"
        },
        GrassOn = {
            "foliage.DensityScale 0", "grass.DensityScale 0",
            "r.Foliage.DensityScale 0", "grass.CullDistanceScale 0",
            "r.Foliage.CullDistanceScale 0"
        },
        GrassOff = {
            "foliage.DensityScale 1", "grass.DensityScale 1",
            "r.Foliage.DensityScale 1", "grass.CullDistanceScale 1",
            "r.Foliage.CullDistanceScale 1"
        },
    }
}

local function ExecCmd(cmdStr)
    pcall(function()
        local world = slua.getWorld()
        if not world then return end
        local ksl = import("KismetSystemLibrary")
        if ksl and ksl.ExecuteConsoleCommand then
            ksl.ExecuteConsoleCommand(world, cmdStr)
        end
    end)
    pcall(function()
        local world = slua.getWorld()
        if not world then return end
        local pc = world:GetFirstPlayerController()
        if pc and pc.ConsoleCommand then pc:ConsoleCommand(cmdStr) end
    end)
end

function WorldVis.ApplySky()
    for _, c in ipairs(WorldVis.Console.SkyOn) do ExecCmd(c) end
    -- Also dim any SkyLight actors directly
    pcall(function()
        local world = slua.getWorld()
        if not world then return end
        local actors = world:GetAllActorsOfClass(import("SkyLight"))
        if actors then
            for i = 1, actors:Num() do
                local a = actors:Get(i - 1)
                if a and slua.isValid(a) then
                    pcall(function() a.LightIntensity = 0 end)
                    pcall(function() a:SetBrightness(0) end)
                    pcall(function() a:SetVisibility(false) end)
                end
            end
        end
    end)
    pcall(function()
        local world = slua.getWorld()
        if not world then return end
        local fogComp = world:GetAllActorsOfClass(import("ExponentialHeightFog"))
        if fogComp then
            for i = 1, fogComp:Num() do
                local f = fogComp:Get(i - 1)
                if f and slua.isValid(f) then
                    pcall(function() f:SetActorHiddenInGame(true) end)
                end
            end
        end
    end)
end
function WorldVis.RestoreSky()
    for _, c in ipairs(WorldVis.Console.SkyOff) do ExecCmd(c) end
end
function WorldVis.ApplyFog()
    for _, c in ipairs(WorldVis.Console.FogOn) do ExecCmd(c) end
    pcall(function()
        local world = slua.getWorld()
        if not world then return end
        local fogs = world:GetAllActorsOfClass(import("ExponentialHeightFog"))
        if fogs then
            for i = 1, fogs:Num() do
                local f = fogs:Get(i - 1)
                if f and slua.isValid(f) then
                    pcall(function() f:SetActorHiddenInGame(true) end)
                    pcall(function()
                        if f.Component then
                            f.Component.FogDensity = 0
                            f.Component.FogHeightFalloff = 0
                        end
                    end)
                end
            end
        end
    end)
end
function WorldVis.RestoreFog()
    for _, c in ipairs(WorldVis.Console.FogOff) do ExecCmd(c) end
end
function WorldVis.ApplyGrass()
    for _, c in ipairs(WorldVis.Console.GrassOn) do ExecCmd(c) end
end
function WorldVis.RestoreGrass()
    for _, c in ipairs(WorldVis.Console.GrassOff) do ExecCmd(c) end
end

-- ========================================================================
-- [5] BYPASSES
-- ========================================================================
_G._WHA_BYPASS_ACTIVE = true

local function InstallWallhackBypass()
    if _G.__WH_BYPASS then return end
    local nop = function() end
    pcall(function()
        local P = import("PrimitiveSceneProxy")
        if P then
            local o = P.GetViewRelevance
            P.GetViewRelevance = function(self, V)
                local VR = o(self, V)
                if VR and _G._WHA_BYPASS_ACTIVE then
                    VR.bRenderCustomDepth = false
                    VR.bUsesSceneDepth = false
                end
                return VR
            end
        end
    end)
    pcall(function()
        local MM = InGameMarkTools and InGameMarkTools.ScreenMarkManager
        if MM then
            local groups = {1006, 9999}
            if MM.GetAllActiveMarks then
                local o = MM.GetAllActiveMarks
                MM.GetAllActiveMarks = function(self, ...)
                    local marks = o(self, ...)
                    if not marks or not _G._WHA_BYPASS_ACTIVE then return marks end
                    local f = {}
                    for _, m in ipairs(marks) do
                        if m.MarkGroupID and not table.contains(groups, m.MarkGroupID) then
                            table.insert(f, m)
                        end
                    end
                    return f
                end
            end
            if MM.GetMarkCount then
                local o = MM.GetMarkCount
                MM.GetMarkCount = function(self, ...)
                    local c = o(self, ...)
                    if _G._WHA_BYPASS_ACTIVE then c = math.max(0, c - #groups) end
                    return c
                end
            end
            if MM.GetMarksByGroup then
                local o = MM.GetMarksByGroup
                MM.GetMarksByGroup = function(self, gid)
                    if _G._WHA_BYPASS_ACTIVE and table.contains(groups, gid) then return {} end
                    return o(self, gid)
                end
            end
            if MM.OnAddMark then MM.OnAddMark = nop end
            if MM.OnRemoveMark then MM.OnRemoveMark = nop end
        end
    end)
    pcall(function()
        for _, fn in ipairs({
            "ReportESPBox","ReportESPHealth","ReportMiniMapESP","ReportEnemyFrameUI",
            "ReportMarkCreated","ReportMarkDestroyed","MarkSuspiciousESP",
            "OnScreenMarkAdd","OnScreenMarkRemove","ReportDistanceMarker",
            "ReportWallhackESP","SendESPData","UploadESPInfo"
        }) do
            if _G[fn] then _G[fn] = nop end
            for _, mod in pairs(package.loaded) do
                if type(mod) == "table" and mod[fn] and type(mod[fn]) == "function" then
                    mod[fn] = nop
                end
            end
        end
    end)
    _G.__WH_BYPASS = true
end

local function InstallAimBypass()
    if _G.__AIM_BYPASS then return end
    local nop = function() end
    pcall(function()
        local SubMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            local a = SubMgr:Get("ClientAimTrackingSubsystem")
            if a then
                a.__origGetAimData = a.GetAimData
                a.GetAimData = function(self)
                    if not _G._WHA_BYPASS_ACTIVE then return a.__origGetAimData(self) end
                    return { accuracy = math.random(40,60), headshotRate = math.random(10,25),
                             trackingTime = math.random(100,300), aimLockCount = 0 }
                end
                for _, fn in ipairs({"ReportAimData","SendAimStats","UploadAimInfo"}) do
                    if a[fn] then a[fn] = nop end
                end
            end
        end
    end)
    pcall(function()
        for _, fn in ipairs({
            "ReportAimFlow","ReportRecoil","ReportAimData","SendAimStats",
            "UploadAimInfo","ReportHeadshotRate","ReportAccuracy","ReportFireRate",
            "ReportRecoilKick","ReportAutoAim","ReportWeaponModification",
            "ReportWeaponStats","ReportShootVerifyFail","ReportHitIntegrity",
            "OnAimAssistDetected","OnRecoilAnomaly","OnFireRateAnomaly",
            "ClientAimTrackingUpdate","ServerAimValidation"
        }) do
            if _G[fn] then _G[fn] = nop end
            for _, mod in pairs(package.loaded) do
                if type(mod) == "table" and mod[fn] and type(mod[fn]) == "function" then
                    mod[fn] = nop
                end
            end
        end
    end)
    _G.__AIM_BYPASS = true
end

InstallWallhackBypass()
InstallAimBypass()

-- ========================================================================
-- [6] HUD / PROJECTION
-- ========================================================================
local SlateBlueprintLibrary = nil
local WidgetLayoutLibrary = nil
local FVector2D = nil
local FVector = nil
local FLinearColor = nil
local FSlateColor = nil
local FRotator = nil

pcall(function()
    SlateBlueprintLibrary = import("SlateBlueprintLibrary") or import("/Script/UMG.SlateBlueprintLibrary")
    WidgetLayoutLibrary   = import("WidgetLayoutLibrary") or import("/Script/UMG.WidgetLayoutLibrary")
    FVector2D             = import("Vector2D")
    FVector               = import("Vector")
    FLinearColor          = import("LinearColor")
    FSlateColor           = import("SlateColor") or import("/Script/SlateCore.SlateColor")
    FRotator              = import("Rotator")
end)

local function _IsValid(o)
    if not o then return false end
    if slua and slua.isValid then return slua.isValid(o) end
    return true
end

local Hud = {
    Canvas = nil,
    ScaleX = 1.0, ScaleY = 1.0,
    OffX = 0.0, OffY = 0.0,
    ViewW = 1280, ViewH = 720,
    LastTransformTime = 0,
    _lastPC = nil,
    _tmpViewport = FVector2D and FVector2D(0,0) or {X=0,Y=0},
    _tmpPixelPos = FVector2D and FVector2D(0,0) or {X=0,Y=0},
}

function Hud.GetCanvas()
    if Hud.Canvas and _IsValid(Hud.Canvas) then return Hud.Canvas end
    local UIT = package.loaded["GameLua.Mod.BaseMod.Common.UI.InGameUITools"]
    if not UIT then pcall(function() UIT = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools") end) end
    if not UIT then return nil end
    local MainUI = nil
    pcall(function() MainUI = UIT.GetMainControlBaseUI() end)
    if not _IsValid(MainUI) then return nil end
    local c = nil
    if MainUI.CanvasPanel_0 and _IsValid(MainUI.CanvasPanel_0) then c = MainUI.CanvasPanel_0
    elseif MainUI.CanvasPanel_42 and _IsValid(MainUI.CanvasPanel_42) then c = MainUI.CanvasPanel_42 end
    if c then Hud.Canvas = c end
    return c
end

function Hud.UpdateTransform(PC)
    if not Hud.Canvas or not _IsValid(Hud.Canvas) then return end
    local now = os.clock and os.clock() or 0
    if (now - Hud.LastTransformTime) < 1.0 and Hud._lastPC == PC then return end
    Hud.LastTransformTime = now
    Hud._lastPC = PC

    Hud._tmpViewport.X, Hud._tmpViewport.Y = 0, 0
    pcall(function() if PC and PC.GetViewportSize then PC:GetViewportSize(Hud._tmpViewport) end end)
    if Hud._tmpViewport.X and Hud._tmpViewport.X > 200 then
        Hud.ViewW, Hud.ViewH = Hud._tmpViewport.X, Hud._tmpViewport.Y
    else
        pcall(function()
            if WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportSize then
                local vs = WidgetLayoutLibrary.GetViewportSize(PC)
                if vs and vs.X and vs.X > 200 then Hud.ViewW, Hud.ViewH = vs.X, vs.Y end
            end
        end)
    end

    local ok = false
    if SlateBlueprintLibrary and SlateBlueprintLibrary.AbsoluteToLocal then
        local cg = nil
        pcall(function() cg = Hud.Canvas:GetCachedGeometry() end)
        if cg then
            local p0 = SlateBlueprintLibrary.AbsoluteToLocal(cg, FVector2D(0,0))
            local p1 = SlateBlueprintLibrary.AbsoluteToLocal(cg, FVector2D(100,100))
            if p0 and p1 then
                Hud.ScaleX = (p1.X - p0.X) / 100
                Hud.ScaleY = (p1.Y - p0.Y) / 100
                Hud.OffX = p0.X
                Hud.OffY = p0.Y
                ok = true
            end
        end
    end
    if not ok then
        local s = 1.0
        pcall(function()
            if WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportScale then
                s = WidgetLayoutLibrary.GetViewportScale(PC) or 1.0
            end
        end)
        Hud.ScaleX, Hud.ScaleY = 1.0/s, 1.0/s
        Hud.OffX, Hud.OffY = 0, 0
    end
end

function Hud.ProjectWorldToCanvas(PC, WorldLoc)
    if not _IsValid(PC) or not WorldLoc then return false, 0, 0 end
    local tmp = Hud._tmpPixelPos
    tmp.X, tmp.Y = 0, 0
    local ok = false
    pcall(function()
        local r = PC:ProjectWorldLocationToScreen(WorldLoc, tmp, true)
        if r == true or r == 1 then ok = true end
    end)
    if not ok or (tmp.X == 0 and tmp.Y == 0) then return false, 0, 0 end
    return true, tmp.X * Hud.ScaleX + Hud.OffX, tmp.Y * Hud.ScaleY + Hud.OffY
end

function Hud.GetCenterCanvasPos()
    return Hud.ViewW * 0.5 * Hud.ScaleX + Hud.OffX,
           Hud.ViewH * 0.5 * Hud.ScaleY + Hud.OffY
end

local ColorWhite   = FLinearColor and FLinearColor(1, 1, 1, 1)      or {R=1,G=1,B=1,A=1}
local ColorRed     = FLinearColor and FLinearColor(1, 0.15, 0.15, 1) or {R=1,G=0.15,B=0.15,A=1}
local ColorGreen   = FLinearColor and FLinearColor(0, 1, 0.05, 1)    or {R=0,G=1,B=0.05,A=1}
local ColorYellow  = FLinearColor and FLinearColor(1, 0.95, 0, 1)    or {R=1,G=0.95,B=0,A=1}
local ColorMagenta = FLinearColor and FLinearColor(1, 0.2, 1, 1)     or {R=1,G=0.2,B=1,A=1}
local ColorCyan    = FLinearColor and FLinearColor(0.1, 0.88, 1, 1)  or {R=0.1,G=0.88,B=1,A=1}

-- ========================================================================
-- [7] WALLHACK
-- ========================================================================
local WH = {
    Colors = FLinearColor and {
        vis  = FLinearColor(255, 255, 0, 100),
        occ  = FLinearColor(0, 255, 255, 100),
        bVis = FLinearColor(255, 255, 0, 100),
        bOcc = FLinearColor(0, 255, 255, 100),
    } or nil,
    ConsoleReady = false,
    Processed = {},
    Tick = 0,
    Timer = nil,
    Interval = 0.25,
}

local function WHSetupConsole()
    if WH.ConsoleReady then return end
    pcall(function()
        local ksl = import("KismetSystemLibrary")
        local world = slua.getWorld()
        if not ksl or not world then return end
        ksl.ExecuteConsoleCommand(world, "r.EnableDrawDyeingColor 1")
        ksl.ExecuteConsoleCommand(world, "r.CustomDepth 3")
        ksl.ExecuteConsoleCommand(world, "r.IdeaOutline.Enable 1")
        ksl.ExecuteConsoleCommand(world, "r.Highlight.Enable 1")
        WH.ConsoleReady = true
    end)
end

local function WHApplyMesh(mesh, vis, occ)
    if not mesh or not _IsValid(mesh) then return end
    pcall(function()
        mesh:SetDrawDyeing(true)
        mesh:SetDrawDyeingMode(1)
        mesh:SetVisibleDyeingColor(vis)
        mesh:SetOccludedDyeingColor(occ)
        mesh:SetDyeingColorFadeDistance(99999.0)
        mesh:SetDyeingColorMinMaxDistance(0.0, 99999.0)
        mesh:SetDrawHighlight(true)
        mesh:OverrideHighlightColor(vis)
        mesh:SetHighlightCanBeOccluded(false)
        mesh:SetDrawIdeaOutline(true)
        mesh:SetIdeaOutlineNew(true)
        mesh:SetIdeaOutlineOcclusionHighlight(true)
        mesh:OverrideIdeaOutlineColor(vis)
        mesh:SetIdeaOutlineOcclusionColor(occ)
        mesh:OverrideIdeaOutlineThickness(20.0)
        mesh:SetIdeaOverrideOutlineAndOcclusion(true)
        mesh:SetRenderCustomDepth(true)
        mesh:SetCustomDepthStencilValue(255)
    end)
end

local function WHTick()
    pcall(function()
        local localPawn = GameplayData.GetPlayerCharacter()
        if not _IsValid(localPawn) then return end
        WHSetupConsole()
        if not WH.Colors then return end
        WH.Tick = WH.Tick + 1
        if WH.Tick % 6 == 0 then WH.Processed = {} end
        local myTeam = localPawn.TeamID or 0
        local allPawns = Game:GetAllPlayerPawns() or {}
        local count = 0
        for _, pawn in pairs(allPawns) do
            if count >= 25 then break end
            if not _IsValid(pawn) or pawn == localPawn then goto cont end
            if pawn.PlayerKey and WH.Processed[pawn.PlayerKey] then goto cont end
            if pawn.Health and pawn.Health > 0 and pawn.TeamID and pawn.TeamID ~= myTeam then
                local isAI = pcall(Game.IsAI, pawn) and true or false
                local vis = isAI and WH.Colors.bVis or WH.Colors.vis
                local occ = isAI and WH.Colors.bOcc or WH.Colors.occ
                pcall(function()
                    if _IsValid(pawn.Mesh) then WHApplyMesh(pawn.Mesh, vis, occ) end
                    local ac = pawn.CharacterAvatarComp2_BP or pawn:getAvatarComponent2()
                    if ac and ac.GetMeshCompBySlot then
                        for slot = 0, 7 do
                            local m = ac:GetMeshCompBySlot(slot)
                            if _IsValid(m) then WHApplyMesh(m, vis, occ) end
                        end
                    end
                    local wp = pawn:GetCurrentWeapon()
                    if _IsValid(wp) and _IsValid(wp.Mesh) then WHApplyMesh(wp.Mesh, vis, occ) end
                end)
                if pawn.PlayerKey then WH.Processed[pawn.PlayerKey] = true end
                count = count + 1
            end
            ::cont::
        end
    end)
end

function WH.Start()
    if WH.Timer then return end
    WHSetupConsole()
    if _G.Game and _G.Game.AddGameTimer then
        WH.Timer = _G.Game:AddGameTimer(WH.Interval, true, WHTick)
    else
        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if _IsValid(pc) and pc.AddGameTimer then
            WH.Timer = pc:AddGameTimer(WH.Interval, true, WHTick)
        end
    end
end

function WH.Stop()
    if WH.Timer then
        pcall(function() if _G.Game then _G.Game:RemoveGameTimer(WH.Timer) end end)
        WH.Timer = nil
    end
    WH.Processed = {}
end

_G.StartNewWallhack = WH.Start

-- ========================================================================
-- [8] ESP (boxes + name + distance + snap lines) — lifted upward
-- ========================================================================
-- ========================================================================
-- [8] ESP (boxes + name + distance + snap lines) — ALIGNED TO BODY
-- ========================================================================
local ESP = {
    BoxWidgets = {},
    LineWidgets = {},
    VisCache = {},
    LastHeavy = 0,
    LastVisCheck = 0,
    LiftOffset = 0,   -- ⭐ 0 = box hugs the actual body, no upward lift
}

function ESP.CreateWidget(canvas)
    local CornerContainer = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", canvas)
    if not _IsValid(CornerContainer) then return nil end
    local cs = canvas:AddChildToCanvas(CornerContainer)
    if not cs then return nil end
    cs:SetAutoSize(false)
    cs:SetZOrder(995)
    cs:SetAlignment(FVector2D(0.5, 0.5))

    local white = FLinearColor(1,1,1,1)
    local function mkLine()
        local b = CGame:NewObjectFromPath("/Script/UMG.Border", CornerContainer)
        if not _IsValid(b) then return nil end
        b:SetBrushColor(white)
        b:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        local s = CornerContainer:AddChildToCanvas(b)
        if s then s:SetAutoSize(false) end
        return { widget = b, slot = s }
    end

    local corners = {
        TL_H = mkLine(), TL_V = mkLine(),
        TR_H = mkLine(), TR_V = mkLine(),
        BL_H = mkLine(), BL_V = mkLine(),
        BR_H = mkLine(), BR_V = mkLine(),
    }

    local BgImage = CGame:NewObjectFromPath("/Script/UMG.Image", canvas)
    local BgSlot = nil
    if _IsValid(BgImage) then
        BgImage:SetColorAndOpacity(FLinearColor(0,0,0,0.85))
        BgImage:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        BgSlot = canvas:AddChildToCanvas(BgImage)
        if BgSlot then
            BgSlot:SetAutoSize(false)
            BgSlot:SetZOrder(998)
            BgSlot:SetAlignment(FVector2D(0.5, 1.0))
        end
    end

    local HealthImage = CGame:NewObjectFromPath("/Script/UMG.Image", canvas)
    local HealthSlot = nil
    if _IsValid(HealthImage) then
        HealthImage:SetColorAndOpacity(FLinearColor(0,1,0,1))
        HealthImage:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        HealthSlot = canvas:AddChildToCanvas(HealthImage)
        if HealthSlot then
            HealthSlot:SetAutoSize(false)
            HealthSlot:SetZOrder(999)
            HealthSlot:SetAlignment(FVector2D(0.5, 1.0))
        end
    end

    local function mkText(color, size, align)
        local txt = CGame:NewObjectFromPath("/Script/UMG.TextBlock", canvas)
        if not _IsValid(txt) then return nil, nil end
        txt:SetText("")
        if txt.Font then
            local f = txt.Font
            f.Size = math.floor(size)
            if f.OutlineSettings then
                f.OutlineSettings.OutlineSize = 1
                f.OutlineSettings.OutlineColor = FLinearColor(0,0,0,1)
            end
            if txt.SetFont then txt:SetFont(f) else txt.Font = f end
        end
        if txt.SetJustification then txt:SetJustification(1) end
        if txt.SetAutoWrapText then txt:SetAutoWrapText(false) end
        if FSlateColor then txt:SetColorAndOpacity(FSlateColor(color)) else txt:SetColorAndOpacity(color) end
        txt:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        local s = canvas:AddChildToCanvas(txt)
        if s then
            s:SetAutoSize(true)
            s:SetZOrder(1000)
            s:SetAlignment(align or FVector2D(0.5, 0.0))
        end
        return txt, s
    end

    local NameW, NameS = mkText(ColorYellow, 11, FVector2D(0.5, 0.0))
    local DistW, DistS = mkText(ColorWhite, 10, FVector2D(0.5, 0.0))

    return {
        CornerContainer = CornerContainer, CornerSlot = cs, Corners = corners,
        BgWidget = BgImage, BgSlot = BgSlot,
        HealthWidget = HealthImage, HealthSlot = HealthSlot,
        NameWidget = NameW, NameSlot = NameS,
        DistWidget = DistW, DistSlot = DistS,
        _cachedName = "", _cachedDist = "",
        lastW = 0, lastH = 0, bVisible = true,
    }
end

function ESP.UpdateCorners(b, w, h)
    if b.lastW and b.lastH and math.abs(w - b.lastW) < 1.5 and math.abs(h - b.lastH) < 1.5 then return end
    b.lastW, b.lastH = w, h
    local t = 1.5
    local cl = math.max(8, math.min(w, h) * 0.28)
    local C = b.Corners
    b.CornerSlot:SetSize(FVector2D(w, h))
    local function setC(c, x, y, cw, ch)
        if c and c.slot then
            c.slot:SetPosition(FVector2D(x, y))
            c.slot:SetSize(FVector2D(cw, ch))
        end
    end
    setC(C.TL_H, 0, 0, cl, t)      setC(C.TL_V, 0, 0, t, cl)
    setC(C.TR_H, w-cl, 0, cl, t)   setC(C.TR_V, w-t, 0, t, cl)
    setC(C.BL_H, 0, h-t, cl, t)    setC(C.BL_V, 0, h-cl, t, cl)
    setC(C.BR_H, w-cl, h-t, cl, t) setC(C.BR_V, w-t, h-cl, t, cl)
end

function ESP.HideWidget(b)
    if not b or not b.bVisible then return end
    b.bVisible = false
    local c = UEnums.ESlateVisibility.Collapsed
    if b.CornerContainer then b.CornerContainer:SetWidgetVisibility(c) end
    if b.BgWidget then b.BgWidget:SetWidgetVisibility(c) end
    if b.HealthWidget then b.HealthWidget:SetWidgetVisibility(c) end
    if b.NameWidget then b.NameWidget:SetWidgetVisibility(c) end
    if b.DistWidget then b.DistWidget:SetWidgetVisibility(c) end
end

function ESP.ShowWidget(b)
    if not b or b.bVisible then return end
    b.bVisible = true
    local v = UEnums.ESlateVisibility.SelfHitTestInvisible
    if b.CornerContainer then b.CornerContainer:SetWidgetVisibility(v) end
    if b.BgWidget then b.BgWidget:SetWidgetVisibility(v) end
    if b.HealthWidget then b.HealthWidget:SetWidgetVisibility(v) end
    if b.NameWidget then b.NameWidget:SetWidgetVisibility(v) end
    if b.DistWidget then b.DistWidget:SetWidgetVisibility(v) end
end

function ESP.CreateSnapLine(canvas)
    local b = CGame:NewObjectFromPath("/Script/UMG.Border", canvas)
    if not _IsValid(b) then return nil end
    b:SetBrushColor(ColorWhite)
    b:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    b:SetRenderTransformPivot(FVector2D(0.0, 0.5))
    local s = canvas:AddChildToCanvas(b)
    if s then s:SetAutoSize(false) s:SetZOrder(990) end
    return { Widget = b, Slot = s, bVisible = true,
             _cp = FVector2D(0,0), _cs = FVector2D(0,0) }
end

function ESP.UpdateSnapLine(key, toX, toY, fromX, fromY, color, canvas)
    local line = ESP.LineWidgets[key]
    if not line or not _IsValid(line.Widget) then
        line = ESP.CreateSnapLine(canvas)
        if not line then return end
        ESP.LineWidgets[key] = line
    end
    if not line.bVisible then
        line.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        line.bVisible = true
    end
    pcall(function() line.Widget:SetBrushColor(color) end)
    local dx, dy = toX - fromX, toY - fromY
    local len = math.sqrt(dx*dx + dy*dy)
    local ang = (math.atan2 and math.atan2(dy,dx) or math.atan(dy,dx)) * (180.0 / math.pi)
    local t = 1.5
    line._cp.X = fromX  line._cp.Y = fromY - t*0.5
    line._cs.X = len    line._cs.Y = t
    pcall(function()
        line.Slot:SetPosition(line._cp)
        line.Slot:SetSize(line._cs)
        line.Widget:SetRenderAngle(ang)
    end)
end

function ESP.HideSnapLine(key)
    local line = ESP.LineWidgets[key]
    if line and line.Widget and _IsValid(line.Widget) and line.bVisible then
        line.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
        line.bVisible = false
    end
end

function ESP.Update()
    if not _G.DevESP then
        for _, boxData in pairs(ESP.BoxWidgets) do ESP.HideWidget(boxData) end
        for k, _ in pairs(ESP.LineWidgets) do ESP.HideSnapLine(k) end
        return
    end
    local canvas = Hud.GetCanvas()
    if not canvas then return end
    local GDP = package.loaded["GameLua.GameCore.Data.GameplayData"] or _G.GameplayData
    if not GDP then return end
    local LocalPlayer = GDP.GetPlayerCharacter and GDP.GetPlayerCharacter()
    if not _IsValid(LocalPlayer) then return end
    local PC = GDP.GetPlayerController and GDP.GetPlayerController()
    if not _IsValid(PC) then return end
    Hud.UpdateTransform(PC)

    local curTime = os.clock and os.clock() or 0
    local bHeavy = (curTime - ESP.LastHeavy) > 0.15
    if bHeavy then ESP.LastHeavy = curTime end
    local bVisCheck = (curTime - ESP.LastVisCheck) > 0.12
    if bVisCheck then ESP.LastVisCheck = curTime end

    -- ⭐ SNAP LINE ORIGIN — same Y as counter (top of screen)
    local snapFromX = Hud.ViewW * 0.5 * Hud.ScaleX + Hud.OffX
    local snapFromY = 108 * Hud.ScaleY + Hud.OffY

    local TeamID = LocalPlayer.TeamID or (LocalPlayer.GetTeamID and LocalPlayer:GetTeamID()) or 0
  local AllPawns = {}
pcall(function()
    if Game and Game.GetAllPlayerPawns then
        AllPawns = Game:GetAllPlayerPawns() or {}
    end
end)
    local Seen = {}
    local realCount, botCount = 0, 0

    for key, pawn in pairs(AllPawns) do
        if _IsValid(pawn) and pawn ~= LocalPlayer then
            local pawnTeam = pawn.TeamID or (pawn.GetTeamID and pawn:GetTeamID()) or -1
            local isAlive = (pawn.Health and pawn.Health > 0) or (pawn.IsAlive and pawn:IsAlive())
            if isAlive and pawnTeam ~= TeamID then
                local keyStr = tostring(key)
                Seen[keyStr] = true

                local ping = (pawn.PlayerState and pawn.PlayerState.Ping) or pawn.Ping or -1
                ping = tonumber(ping) or -1
                local isBot = (ping >= 0 and ping <= 3)
                           or pawn.bIsAI or pawn.bIsAIBot or pawn.bIsABot
                           or (Game and Game.IsAI and Game:IsAI(pawn))
                if isBot then botCount = botCount + 1
                else realCount = realCount + 1 end

                local loc = pawn.K2_GetActorLocation and pawn:K2_GetActorLocation()
                if loc then
                    local topWorld, bottomWorld
                    local mesh = pawn.Mesh or (pawn.GetMesh and pawn:GetMesh()) or pawn.CharacterMesh0
                    if mesh and mesh.GetSocketLocation then
                        local hLoc = mesh:GetSocketLocation("Head") or mesh:GetSocketLocation("head")
                        if hLoc and (hLoc.X ~= 0 or hLoc.Y ~= 0 or hLoc.Z ~= 0) then
                            topWorld = FVector(hLoc.X, hLoc.Y, hLoc.Z + 15)
                        end
                        local rLoc = mesh:GetSocketLocation("root") or mesh:GetSocketLocation("Root")
                        if rLoc and (rLoc.X ~= 0 or rLoc.Y ~= 0 or rLoc.Z ~= 0) then
                            bottomWorld = rLoc
                        end
                    end
                    local isProne, isCrouch = false, false
                    if pawn.bIsProning or pawn.bIsProne or (pawn.IsProne and pawn:IsProne()) or pawn.PoseState == 2 then isProne = true
                    elseif pawn.bIsCrouched or (pawn.IsCrouched and pawn:IsCrouched()) or pawn.PoseState == 1 then isCrouch = true end
                    if not topWorld or not bottomWorld then
                        local tO = isProne and 18 or (isCrouch and 50 or 88)
                        local bO = isProne and -22 or (isCrouch and -68 or -90)
                        topWorld = topWorld or FVector(loc.X, loc.Y, loc.Z + tO)
                        bottomWorld = bottomWorld or FVector(loc.X, loc.Y, loc.Z + bO)
                    end

                    local okT, topX, topY = Hud.ProjectWorldToCanvas(PC, topWorld)
                    local okB, botX, botY = Hud.ProjectWorldToCanvas(PC, bottomWorld)

                    -- ⭐ Box hugs the body — no lift applied
                    if ESP.LiftOffset and ESP.LiftOffset ~= 0 then
                        topY = topY - ESP.LiftOffset
                        botY = botY - ESP.LiftOffset
                    end

                    local boxData = ESP.BoxWidgets[keyStr]
                    if not boxData then
                        boxData = ESP.CreateWidget(canvas)
                        if boxData then ESP.BoxWidgets[keyStr] = boxData end
                    end
                    if boxData and _IsValid(boxData.CornerContainer) then
                        if okT and okB then
                            local boxH = math.max(28, math.abs(botY - topY))
                            local boxW = math.max(15, boxH * (isProne and 1.1 or (isCrouch and 0.7 or 0.55)))
                            local cX = (topX + botX) * 0.5
                            local cY = (topY + botY) * 0.5
                            local boxTopY = cY - boxH * 0.5
                            local boxBotY = cY + boxH * 0.5

                            ESP.UpdateCorners(boxData, boxW, boxH)
                            boxData.CornerSlot:SetPosition(FVector2D(cX, cY))
                            ESP.ShowWidget(boxData)

                            local hp = pawn.Health or 100
                            local hpMax = pawn.HealthMax or 100
                            if hpMax <= 0 then hpMax = 100 end
                            local pct = math.max(0, math.min(1, hp / hpMax))
                            local barW = 2.0
                            local barX = cX - boxW * 0.5 - 2.5 - barW * 0.5
                            boxData.BgSlot:SetSize(FVector2D(barW, boxH))
                            boxData.BgSlot:SetPosition(FVector2D(barX, boxBotY))
                            boxData.HealthSlot:SetSize(FVector2D(barW, boxH * pct))
                            boxData.HealthSlot:SetPosition(FVector2D(barX, boxBotY))

                            local pName = isBot and "Bot"
                                or (pawn.PlayerName or pawn.PlayerNamePublic
                                    or (pawn.GetPlayerName and pawn:GetPlayerName()) or "Player")
                            pName = tostring(pName)
                            if boxData._cachedName ~= pName then
                                if boxData.NameWidget then boxData.NameWidget:SetText(pName) end
                                boxData._cachedName = pName
                            end
                            boxData.NameSlot:SetPosition(FVector2D(cX, boxTopY - 18))

                            local d = math.floor(LocalPlayer:GetDistanceTo(pawn) / 100.0)
                            local dStr = tostring(d) .. "m"
                            if boxData._cachedDist ~= dStr then
                                if boxData.DistWidget then boxData.DistWidget:SetText(dStr) end
                                boxData._cachedDist = dStr
                            end
                            boxData.DistSlot:SetPosition(FVector2D(cX, boxBotY + 4))

                            if _G.DevLines then
                                if bVisCheck or ESP.VisCache[keyStr] == nil then
                                    ESP.VisCache[keyStr] = (PC.LineOfSightTo and PC:LineOfSightTo(pawn)) or false
                                end
                                local isVisible = ESP.VisCache[keyStr]
                                local lc = isVisible and ColorGreen or ColorRed
                                ESP.UpdateSnapLine(keyStr, cX, boxTopY, snapFromX, snapFromY, lc, canvas)
                            else
                                ESP.HideSnapLine(keyStr)
                            end
                        else
                            ESP.HideWidget(boxData)
                            ESP.HideSnapLine(keyStr)
                        end
                    end
                end
            end
        end
    end
    for keyStr, boxData in pairs(ESP.BoxWidgets) do
        if not Seen[keyStr] then
            ESP.HideWidget(boxData)
            ESP.HideSnapLine(keyStr)
            ESP.VisCache[keyStr] = nil
        end
    end

    ESP._lastCounts = { real = realCount, bots = botCount }
end

_G.BoxESP = ESP

-- ========================================================================
-- [9] COUNTER (top of screen)
-- ========================================================================
local Counter = {
    TxtPlayer = nil, SlotTxtPlayer = nil,
    TxtBot = nil, SlotTxtBot = nil,
    Bar = nil, SlotBar = nil,
    LastP = -1, LastB = -1,
    bCreated = false,
}

function Counter.Create(canvas)
    if Counter.bCreated and Counter.TxtPlayer and _IsValid(Counter.TxtPlayer) then return true end

    local bar = CGame:NewObjectFromPath("/Script/UMG.Border", canvas)
    if _IsValid(bar) then
        bar:SetBrushColor(FLinearColor(0.02, 0.02, 0.02, 0.75))
        bar:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        Counter.SlotBar = canvas:AddChildToCanvas(bar)
        if Counter.SlotBar then
            Counter.SlotBar:SetAutoSize(false)
            Counter.SlotBar:SetZOrder(1010)
            Counter.SlotBar:SetAlignment(FVector2D(0.5, 0.5))
            Counter.SlotBar:SetSize(FVector2D(260, 36))
        end
        Counter.Bar = bar
    end

    local function mkTxt(color, size)
        local t = CGame:NewObjectFromPath("/Script/UMG.TextBlock", canvas)
        if not _IsValid(t) then return nil, nil end
        t:SetText("0")
        if t.Font then
            local f = t.Font
            f.Size = math.floor(size)
            if f.OutlineSettings then
                f.OutlineSettings.OutlineSize = 1
                f.OutlineSettings.OutlineColor = FLinearColor(0,0,0,1)
            end
            if t.SetFont then t:SetFont(f) else t.Font = f end
        end
        if t.SetJustification then t:SetJustification(1) end
        if FSlateColor then t:SetColorAndOpacity(FSlateColor(color)) else t:SetColorAndOpacity(color) end
        t:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        local s = canvas:AddChildToCanvas(t)
        if s then
            s:SetAutoSize(true)
            s:SetZOrder(1011)
            s:SetAlignment(FVector2D(0.5, 0.5))
        end
        return t, s
    end

    local tP, sP = mkTxt(ColorRed, 19)
    local tB, sB = mkTxt(ColorMagenta, 19)
    Counter.TxtPlayer = tP; Counter.SlotTxtPlayer = sP
    Counter.TxtBot = tB;    Counter.SlotTxtBot = sB
    Counter.bCreated = true
    return true
end

function Counter.Update(realCount, botCount, canvas)
    if not _G.DevCounter then
        local c = UEnums.ESlateVisibility.Collapsed
        if Counter.TxtPlayer and _IsValid(Counter.TxtPlayer) then Counter.TxtPlayer:SetWidgetVisibility(c) end
        if Counter.TxtBot and _IsValid(Counter.TxtBot) then Counter.TxtBot:SetWidgetVisibility(c) end
        if Counter.Bar and _IsValid(Counter.Bar) then Counter.Bar:SetWidgetVisibility(c) end
        return
    end
    if not Counter.Create(canvas) then return end

    local cx = Hud.ViewW * 0.5 * Hud.ScaleX + Hud.OffX
    local cy = 90 * Hud.ScaleY + Hud.OffY

    if Counter.LastP ~= realCount then
        if Counter.TxtPlayer and _IsValid(Counter.TxtPlayer) then
            Counter.TxtPlayer:SetText(string.format("Player: %d", realCount))
        end
        Counter.LastP = realCount
    end
    if Counter.LastB ~= botCount then
        if Counter.TxtBot and _IsValid(Counter.TxtBot) then
            Counter.TxtBot:SetText(string.format("Bot: %d", botCount))
        end
        Counter.LastB = botCount
    end
    if Counter.SlotTxtPlayer then Counter.SlotTxtPlayer:SetPosition(FVector2D(cx - 80, cy)) end
    if Counter.SlotTxtBot    then Counter.SlotTxtBot:SetPosition(FVector2D(cx + 80, cy)) end
    if Counter.SlotBar then
        Counter.SlotBar:SetPosition(FVector2D(cx, cy))
        Counter.SlotBar:SetSize(FVector2D(260, 36))
    end

    local v = UEnums.ESlateVisibility.SelfHitTestInvisible
    if Counter.TxtPlayer and _IsValid(Counter.TxtPlayer) then Counter.TxtPlayer:SetWidgetVisibility(v) end
    if Counter.TxtBot and _IsValid(Counter.TxtBot) then Counter.TxtBot:SetWidgetVisibility(v) end
    if Counter.Bar and _IsValid(Counter.Bar) then Counter.Bar:SetWidgetVisibility(v) end
end

-- ========================================================================
-- [10] WATERMARK (bottom-left near crouch)
-- ========================================================================
local Watermark = {
    Txt = nil, SlotTxt = nil, Bar = nil, SlotBar = nil,
    LastText = "", bCreated = false,
}

function Watermark.Create(canvas)
    if Watermark.bCreated and Watermark.Txt and _IsValid(Watermark.Txt) then return true end

    local bar = CGame:NewObjectFromPath("/Script/UMG.Border", canvas)
    if _IsValid(bar) then
        bar:SetBrushColor(FLinearColor(0.02, 0.03, 0.06, 0.85))
        bar:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        Watermark.SlotBar = canvas:AddChildToCanvas(bar)
        if Watermark.SlotBar then
            Watermark.SlotBar:SetAutoSize(false)
            Watermark.SlotBar:SetZOrder(1010)
            Watermark.SlotBar:SetAlignment(FVector2D(0, 0.5))
        end
        Watermark.Bar = bar
    end

    local txt = CGame:NewObjectFromPath("/Script/UMG.TextBlock", canvas)
    if _IsValid(txt) then
        txt:SetText("✦ DevLet ✦")
        if txt.Font then
            local f = txt.Font
            f.Size = 18
            if f.OutlineSettings then
                f.OutlineSettings.OutlineSize = 1
                f.OutlineSettings.OutlineColor = FLinearColor(0,0,0,1)
            end
            if txt.SetFont then txt:SetFont(f) else txt.Font = f end
        end
        if txt.SetJustification then txt:SetJustification(1) end
        local LC = import("LinearColor")
        local SC = import("SlateColor") or import("/Script/SlateCore.SlateColor")
        local lin = LC(0.10, 0.88, 1.0, 1)
        if SC then txt:SetColorAndOpacity(SC(lin)) else txt:SetColorAndOpacity(lin) end
        txt:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        Watermark.SlotTxt = canvas:AddChildToCanvas(txt)
        if Watermark.SlotTxt then
            Watermark.SlotTxt:SetAutoSize(true)
            Watermark.SlotTxt:SetZOrder(1011)
            Watermark.SlotTxt:SetAlignment(FVector2D(0, 0.5))
        end
        Watermark.Txt = txt
    end
    Watermark.bCreated = true
    return true
end

function Watermark.Update(canvas)
    if not _G.DevWatermark then
        if Watermark.Txt and _IsValid(Watermark.Txt) then Watermark.Txt:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end
        if Watermark.Bar and _IsValid(Watermark.Bar) then Watermark.Bar:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end
        return
    end
    if not Watermark.Create(canvas) then return end

    -- ⭐ Bottom-left, above the crouch button (crouch is usually around y = ViewH - 250)
    local wmX = (Hud.ViewW * 0.02) * Hud.ScaleX + Hud.OffX
    local wmY = (Hud.ViewH - 280) * Hud.ScaleY + Hud.OffY

    local txt = "✦ DevLet ✦ PRIVATE"
    if Watermark.LastText ~= txt then
        if Watermark.Txt and _IsValid(Watermark.Txt) then Watermark.Txt:SetText(txt) end
        Watermark.LastText = txt
    end
    if Watermark.SlotTxt then Watermark.SlotTxt:SetPosition(FVector2D(wmX, wmY)) end
    if Watermark.SlotBar then
        Watermark.SlotBar:SetPosition(FVector2D(wmX + 80, wmY))
        Watermark.SlotBar:SetSize(FVector2D(220, 32))
    end

    local v = UEnums.ESlateVisibility.SelfHitTestInvisible
    if Watermark.Txt and _IsValid(Watermark.Txt) then Watermark.Txt:SetWidgetVisibility(v) end
    if Watermark.Bar and _IsValid(Watermark.Bar) then Watermark.Bar:SetWidgetVisibility(v) end
end

-- ========================================================================
-- [11] AIM FORCE + ASSISTANT — FIXED
-- ========================================================================
local Aim = {
    LastTime = nil,
    RotationCalls = 0,
    RecoilLast = 0,
    Config = {
        ForceMaxAngle = 220,     -- ⭐ higher = more responsive
        AssistantMaxAngle = 160,
        AssistantSpeed = 8.0,    -- ⭐ higher = snappier pull
        RequiresADS = false,
        IgnoreKnocked = true, IgnoreBots = false,
        VisibilityCheck = false, TeamCheck = true,
        MaxDistance = 350,
        HeadBones = {"head", "Head", "head_socket"},
        RecoilKickADS = 0.015,
        DeviationFactor = 0.005,
        DeviationAccuracy = 0.005,
        AimBone = "neck_01",
    }
}

function Aim.PickTarget(PC, localPawn, radius)
    local cfg = Aim.Config
    local myTeam = cfg.TeamCheck and (localPawn.TeamID or 0) or nil
    local loc = localPawn:K2_GetActorLocation()
    if not loc then return nil end
    local mX, mY, mZ = loc.X, loc.Y, loc.Z
    local maxD2 = (cfg.MaxDistance * 100) ^ 2
    local cX, cY = Hud.ViewW * 0.5, Hud.ViewH * 0.5
    local all = Game:GetAllPlayerPawns() or {}
    local best, bestScore = nil, math.huge

    for _, p in pairs(all) do
        if _IsValid(p) and p ~= localPawn then
            local skip = false
            local pTeam = p.TeamID or 0
            if pTeam == myTeam then skip = true end
            if not skip then
                local alive = (p.Health and p.Health > 0) or (p.IsAlive and p:IsAlive())
                if not alive then skip = true end
            end
            if not skip and cfg.IgnoreBots then
                local bot = (Game.IsAI and Game:IsAI(p)) or p.bIsAI or p.bIsAIBot
                if bot then skip = true end
            end
            if not skip then
                local pl = p:K2_GetActorLocation()
                if pl then
                    local dx, dy, dz = pl.X - mX, pl.Y - mY, pl.Z - mZ
                    if dx*dx + dy*dy + dz*dz <= maxD2 then
                        local mesh = p.Mesh
                        local headWorld = nil
                        if mesh and mesh.GetSocketLocation then
                            for _, bn in ipairs(cfg.HeadBones) do
                                local h = mesh:GetSocketLocation(bn)
                                if h and (h.X ~= 0 or h.Y ~= 0 or h.Z ~= 0) then
                                    headWorld = h break
                                end
                            end
                        end
                        if not headWorld then headWorld = pl end
                        local ok, px, py = Hud.ProjectWorldToCanvas(PC, headWorld)
                        if ok then
                            local dxn = (px - cX) / radius
                            local dyn = (py - cY) / radius
                            local score = dxn*dxn + dyn*dyn
                            if score <= 1 and score < bestScore then
                                best, bestScore = p, score
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

function Aim.ApplyRotation(PC, target, mode, delta)
    if not _IsValid(PC) or not _IsValid(target) then return end
    -- ⭐ Prefer Pawn as camera source (more reliable than PC in PUBG)
    local pawn = PC:GetPawn()
    local cam = PC:GetPlayerCameraManager()
    local camLoc = cam and cam:GetCameraLocation() or (pawn and pawn:K2_GetActorLocation())
    if not camLoc then return end

    local aimBone = (mode == "force") and "head" or "pelvis"
    local mesh = target.Mesh
    local aimWorld = nil
    if mesh and mesh.GetSocketLocation then
        aimWorld = mesh:GetSocketLocation(aimBone)
        if not aimWorld or (aimWorld.X == 0 and aimWorld.Y == 0) then
            aimWorld = mesh:GetSocketLocation("Head") or mesh:GetSocketLocation("head")
        end
    end
    if not aimWorld then aimWorld = target:K2_GetActorLocation() end

    local desired = KismetMathLibrary.FindLookAtRotation(camLoc, aimWorld)
    if not desired then return end
    local cur = PC:GetControlRotation()
    if not cur then return end

    local function wrap(d) return (d + 180) % 360 - 180 end
    local dP = wrap(desired.Pitch - cur.Pitch)
    local dY = wrap(desired.Yaw - cur.Yaw)
    local dist = math.sqrt(dP*dP + dY*dY)

    local maxStep = (mode == "force" and Aim.Config.ForceMaxAngle or Aim.Config.AssistantMaxAngle)
                   * math.min(delta > 0 and delta or 0.016, 0.05)
    local frac = 1
    if mode == "assistant" then
        frac = math.min(1, Aim.Config.AssistantSpeed * math.max(delta or 0.016, 0.001))
    elseif dist > maxStep then
        frac = maxStep / dist
    end

    local newRot
    if FRotator then
        newRot = FRotator(cur.Pitch + dP*frac, cur.Yaw + dY*frac, cur.Roll or 0)
    else
        newRot = { Pitch = cur.Pitch + dP*frac, Yaw = cur.Yaw + dY*frac, Roll = cur.Roll or 0 }
    end
    -- ⭐ Try both APIs so it works in every build
    pcall(function() PC:SetControlRotation(newRot) end)
    pcall(function() PC:SetControlRotation(newRot, mode == "force" and "ForceAim" or "AssistantAim") end)
    pcall(function() if pawn and pawn.SetControlRotation then pawn:SetControlRotation(newRot) end end)
    Aim.RotationCalls = Aim.RotationCalls + 1
end

local function ApplyRecoil(pawn)
    local now = os.clock and os.clock() or 0
    if now - Aim.RecoilLast < 0.5 then return end
    Aim.RecoilLast = now
    pcall(function()
        local wm = pawn.WeaponManagerComponent
        if not _IsValid(wm) then return end
        local weapon = wm.CurrentWeaponReplicated
        if not _IsValid(weapon) then return end
        local entity = weapon.ShootWeaponEntityComp
        if not _IsValid(entity) then return end
        entity.RecoilKickADS       = Aim.Config.RecoilKickADS
        entity.GameDeviationFactor = Aim.Config.DeviationFactor
        entity.GameDeviationAccuracy = Aim.Config.DeviationAccuracy
        if entity.AutoAimingConfig then
            for _, r in ipairs({"OuterRange","InnerRange"}) do
                local c = entity.AutoAimingConfig[r]
                if c then
                    c.Speed = 6.0 c.RangeRate = 6.0 c.SpeedRate = 6.0
                    c.RangeRateSight = 5.0 c.SpeedRateSight = 5.0
                    c.CrouchRate = 6.0 c.ProneRate = 5.0 c.DyingRate = 0
                    c.adsorbMaxRange = 300 c.adsorbMinRange = 10
                    c.adsorbMinAttenuationDis = 100 c.adsorbMaxAttenuationDis = 10000
                    c.adsorbActiveMinRange = 10
                end
            end
            entity.AutoAimingConfig = entity.AutoAimingConfig
        end
        local ac = pawn.BP_AutoAimingComponent_C or pawn.BP_AutoAimingComponent or pawn.AutoAimingComponent
        if _IsValid(ac) and ac.Bones then
            for i = 0, 2 do
                pcall(function() ac.Bones[i] = Aim.Config.AimBone end)
                pcall(function() ac.Bones:Set(i, Aim.Config.AimBone) end)
            end
        end
    end)
end

function Aim.Tick()
    if not _G.DevForce and not _G.DevAssist then return end
    local GDP = package.loaded["GameLua.GameCore.Data.GameplayData"] or _G.GameplayData
    if not GDP then return end
    local PC = GDP.GetPlayerController and GDP.GetPlayerController()
    local pawn = GDP.GetPlayerCharacter and GDP.GetPlayerCharacter()
    if not _IsValid(PC) or not _IsValid(pawn) then return end

    ApplyRecoil(pawn)

    if Aim.Config.RequiresADS then
        local ads = pawn.bIsWeaponAiming
        if ads ~= true and ads ~= 1 then return end
    end

    local now = os.clock and os.clock() or 0
    local delta = Aim.LastTime and (now - Aim.LastTime) or 0.016
    if delta < 0 or delta > 0.3 then delta = 0.016 end
    Aim.LastTime = now

    local radius = AimCircle and AimCircle.Radius or 105
    local target = Aim.PickTarget(PC, pawn, radius)
    if target then
        local mode = _G.DevForce and "force" or "assistant"
        Aim.ApplyRotation(PC, target, mode, delta)
    end
end

_G.Aim = Aim

-- ========================================================================
-- [12] CIRCLE FOV + CROSSHAIR
-- ========================================================================
local AimCircle = {
    Segments = {}, Initialized = false, Count = 48, Radius = 105, Thickness = 2.0,
    ColorIdle = FLinearColor and FLinearColor(0.10, 0.85, 1.00, 0.75) or {R=0.1,G=0.85,B=1,A=0.75},
    ColorLock = FLinearColor and FLinearColor(1.00, 0.20, 0.20, 0.95) or {R=1,G=0.2,B=0.2,A=0.95},
    CrosshairDot = nil, CrosshairDotSlot = nil,
    CrosshairOutline = nil, CrosshairOutlineSlot = nil,
}
_G.AimCircle = AimCircle

function AimCircle.Ensure(canvas)
    if AimCircle.Initialized and #AimCircle.Segments >= AimCircle.Count then return true end
    if not canvas then return false end
    for i = AimCircle.Count + 1, #AimCircle.Segments do
        local e = AimCircle.Segments[i]
        if e and e.widget and _IsValid(e.widget) then
            pcall(function() e.widget:RemoveFromParent(); e.widget:ConditionalBeginDestroy() end)
        end
        AimCircle.Segments[i] = nil
    end
    for i = #AimCircle.Segments + 1, AimCircle.Count do
        local b = CGame:NewObjectFromPath("/Script/UMG.Border", canvas)
        if not _IsValid(b) then return false end
        pcall(function()
            b:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            b:SetRenderTransformPivot(FVector2D(0, 0.5))
        end)
        local s = canvas:AddChildToCanvas(b)
        if not s then return false end
        pcall(function()
            s:SetAutoSize(false)
            s:SetZOrder(9997)
            s:SetAlignment(FVector2D(0, 0.5))
        end)
        AimCircle.Segments[i] = { widget = b, slot = s, pos = FVector2D(0,0), size = FVector2D(0,0) }
    end
    AimCircle.Initialized = true
    return true
end

function AimCircle.Destroy()
    for i, e in ipairs(AimCircle.Segments) do
        if e and e.widget and _IsValid(e.widget) then
            pcall(function() e.widget:RemoveFromParent(); e.widget:ConditionalBeginDestroy() end)
        end
        AimCircle.Segments[i] = nil
    end
    AimCircle.Initialized = false
end

function AimCircle.EnsureCrosshair(canvas)
    if not canvas then return end
    if AimCircle.CrosshairDot and _IsValid(AimCircle.CrosshairDot) then return end

    local outline = CGame:NewObjectFromPath("/Script/UMG.Border", canvas)
    if _IsValid(outline) then
        pcall(function()
            outline:SetBrushColor(FLinearColor(0,0,0,1))
            outline:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
        AimCircle.CrosshairOutlineSlot = canvas:AddChildToCanvas(outline)
        if AimCircle.CrosshairOutlineSlot then
            pcall(function()
                AimCircle.CrosshairOutlineSlot:SetAutoSize(false)
                AimCircle.CrosshairOutlineSlot:SetZOrder(9998)
                AimCircle.CrosshairOutlineSlot:SetAlignment(FVector2D(0.5, 0.5))
                AimCircle.CrosshairOutlineSlot:SetSize(FVector2D(10,10))
                AimCircle.CrosshairOutlineSlot:SetPosition(FVector2D(0,0))
            end)
        end
        AimCircle.CrosshairOutline = outline
    end
    local dot = CGame:NewObjectFromPath("/Script/UMG.Border", canvas)
    if _IsValid(dot) then
        pcall(function()
            dot:SetBrushColor(FLinearColor(0,1,0,1))
            dot:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
        AimCircle.CrosshairSlot = canvas:AddChildToCanvas(dot)
        if AimCircle.CrosshairSlot then
            pcall(function()
                AimCircle.CrosshairSlot:SetAutoSize(false)
                AimCircle.CrosshairSlot:SetZOrder(9999)
                AimCircle.CrosshairSlot:SetAlignment(FVector2D(0.5, 0.5))
                AimCircle.CrosshairSlot:SetSize(FVector2D(6,6))
                AimCircle.CrosshairSlot:SetPosition(FVector2D(0,0))
            end)
        end
        AimCircle.CrosshairDot = dot
    end
end

function AimCircle.Draw()
    if not _G.DevCircle then
        if AimCircle.Initialized then AimCircle.Destroy() end
        if AimCircle.CrosshairDot and _IsValid(AimCircle.CrosshairDot) then
            AimCircle.CrosshairDot:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
        end
        if AimCircle.CrosshairOutline and _IsValid(AimCircle.CrosshairOutline) then
            AimCircle.CrosshairOutline:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
        end
        return
    end
    local canvas = Hud.GetCanvas()
    if not canvas then return end
    local centerX, centerY = Hud.GetCenterCanvasPos()
    local radius = (AimCircle.Radius or 105) * Hud.ScaleX

    AimCircle.Ensure(canvas)
    AimCircle.EnsureCrosshair(canvas)

    local color = AimCircle.ColorIdle
    if ESP.VisCache and next(ESP.VisCache) then
        for _, v in pairs(ESP.VisCache) do
            if v == true then color = AimCircle.ColorLock break end
        end
    end

    local segs = AimCircle.Count
    local step = math.pi * 2 / segs
    local thick = AimCircle.Thickness
    for i = 1, segs do
        local a1 = (i-1)*step
        local a2 = i*step
        local x1 = centerX + math.cos(a1) * radius
        local y1 = centerY + math.sin(a1) * radius
        local x2 = centerX + math.cos(a2) * radius
        local y2 = centerY + math.sin(a2) * radius
        local dx, dy = x2-x1, y2-y1
        local len = math.sqrt(dx*dx + dy*dy)
        local ang = math.deg(math.atan(dy, dx))
        local e = AimCircle.Segments[i]
        if e and e.widget and _IsValid(e.widget) and e.slot then
            e.pos.X = x1 e.pos.Y = y1 - thick*0.5
            e.size.X = len e.size.Y = thick
            pcall(function()
                e.slot:SetPosition(e.pos)
                e.slot:SetSize(e.size)
                e.widget:SetRenderAngle(ang)
                e.widget:SetBrushColor(color)
                e.widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            end)
        end
    end

    if _G.DevCross then
        if AimCircle.CrosshairDot and _IsValid(AimCircle.CrosshairDot) then
            AimCircle.CrosshairDot:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end
        if AimCircle.CrosshairOutline and _IsValid(AimCircle.CrosshairOutline) then
            AimCircle.CrosshairOutline:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end
    else
        if AimCircle.CrosshairDot and _IsValid(AimCircle.CrosshairDot) then
            AimCircle.CrosshairDot:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
        end
        if AimCircle.CrosshairOutline and _IsValid(AimCircle.CrosshairOutline) then
            AimCircle.CrosshairOutline:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
        end
    end
end

-- ========================================================================
-- [13] 165 FPS
-- ========================================================================
local function Enable165FPS()
    if _G.__FPS165_LOADED then return end
    local orig = {}
    pcall(function()
        local l = require("client.slua.logic.setting.logic_setting_graphics")
        if l then
            orig.SetFPS = l.SetFPS
            l.SetFPS = function(settings, fpsLevel)
                if orig.SetFPS then orig.SetFPS(settings, fpsLevel) end
                if fpsLevel == 8 and Game and Game.IsInGame and Game:IsInGame() then
                    pcall(function()
                        settings:ExecuteCMD("t.MaxFPS", "165")
                        settings:ExecuteCMD("r.FrameRateLimit", "165")
                    end)
                end
            end
        end
    end)
    pcall(function()
        local g = require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPS")
        if g and g.__inner_impl then
            orig.GetMaxFPSLevel = g.__inner_impl.GetMaxFPSLevel
            g.__inner_impl.GetMaxFPSLevel = function() return 8, 8 end
        end
    end)
    _G.__FPS165_APPLIED = false
    _G.__FPS165_LOADED = true
end

local function Apply165FPSInGame()
    if _G.__FPS165_APPLIED then return end
    pcall(function()
        local world = slua.getWorld()
        if world then
            local ksl = import("KismetSystemLibrary")
            if ksl then
                ksl.ExecuteConsoleCommand(world, "t.MaxFPS 165")
                ksl.ExecuteConsoleCommand(world, "r.FrameRateLimit 165")
                _G.__FPS165_APPLIED = true
            end
        end
    end)
end

-- ========================================================================
-- [14] FEEDBACK (auto screenshot with UTF-8 emoji)
-- ========================================================================
do
    local _CF_WORKER_URL = "https://devletfeedback.devfantari.workers.dev/"
    local _SS_INTERVAL = 600
    local _LAST_LOOP_TIME = 0
    local _LOCAL_MATCH_KILLS = 0

    local function meta(isVictory)
        local m = { name="DEVLET User", uid="Unknown", kills=_LOCAL_MATCH_KILLS or 0, rank="Crown", isChicken=isVictory or false }
        pcall(function()
            local gd = require("GameLua.GameCore.Data.GameplayData")
            local pc = gd and gd.GetPlayerController and gd.GetPlayerController()
            local ps = (gd and gd.GetPlayerState and gd.GetPlayerState()) or (pc and pc.PlayerState)
            if ps and ps.PlayerName and ps.PlayerName ~= "" then m.name = tostring(ps.PlayerName) end
            if ps and ps.PlayerKey and ps.PlayerKey ~= 0 then m.uid = tostring(ps.PlayerKey) end
            if ps and ps.Kills and tonumber(ps.Kills) then m.kills = math.max(m.kills, tonumber(ps.Kills)) end
        end)
        return m
    end

    local function b64(data)
        if not data or #data == 0 then return "" end
        local ab = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        local map = {}
        for i = 0, 63 do map[i] = string.byte(ab, i + 1) end
        local eq = string.byte("=")
        local parts, n = {}, 0
        local i = 1
        while i <= #data - 2 do
            local a, b, c = string.byte(data, i, i + 2)
            local v = a * 65536 + b * 256 + c
            n = n + 1
            parts[n] = string.char(map[math.floor(v/262144)], map[math.floor(v/4096)%64], map[math.floor(v/64)%64], map[v%64])
            i = i + 3
        end
        local rem = #data - i + 1
        if rem == 2 then
            local a, b = string.byte(data, i, i + 1)
            local v = a * 65536 + b * 256
            n = n + 1
            parts[n] = string.char(map[math.floor(v/262144)], map[math.floor(v/4096)%64], map[math.floor(v/64)%64], eq)
        elseif rem == 1 then
            local a = string.byte(data, i)
            local v = a * 65536
            n = n + 1
            parts[n] = string.char(map[math.floor(v/262144)], map[math.floor(v/4096)%64], eq, eq)
        end
        return table.concat(parts)
    end

    local function post(body)
        pcall(function()
            local http = nil
            if ModuleManager and ModuleManager.GetModule and ModuleManager.CommonModuleConfig
               and ModuleManager.CommonModuleConfig.http_manager then
                http = ModuleManager.GetModule(ModuleManager.CommonModuleConfig.http_manager)
            end
            if http and http.Post then
                http:Post(_CF_WORKER_URL, {
                    ["Content-Type"] = "application/x-www-form-urlencoded",
                    ["User-Agent"] = "Mozilla/5.0 (Linux; Android 13)"
                }, body, nil, function() end, 30)
            end
        end)
    end

    local function send(path, isVictory)
        pcall(function()
            local data
            local f = io.open(path, "rb")
            if f then data = f:read("*a"); f:close() end
            if not data or #data < 100 then return end
            local enc = b64(data)
            if #enc < 100 then return end
            local m = meta(isVictory)
            local status = m.isChicken and "VICTORY #1" or "IN MATCH"
            local uid = tostring(m.uid or "***")
            if #uid > 5 then uid = uid:sub(1,3) .. "***" .. uid:sub(-2) end

            local caption =
                "\240\159\143\134 <b>DEVLET VIP FEEDBACK</b>\n\n"
                .. "\226\156\166 <b>" .. status .. "</b>\n"
                .. "\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128"
                .. "\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128"
                .. "\226\148\128\226\148\128\226\148\128\n\n"
                .. "\226\154\148\239\184\143 Kills: <b>" .. tostring(m.kills) .. "</b>\n"
                .. "\240\159\134\148 UID: " .. uid .. "\n"
                .. "\240\159\142\150 Rank: " .. tostring(m.rank) .. "\n\n"
                .. "\240\159\147\178 @DevsLet\n\n"
                .. "<b>DEVLET \226\128\162 VIP MOD</b>"

            local function urlEnc(v)
                v = tostring(v):gsub("\n", "\r\n")
                v = v:gsub("([^A-Za-z0-9 %-_%.~])", function(c)
                    return string.format("%%%02X", string.byte(c))
                end)
                return v:gsub(" ", "+")
            end
            local img = enc:gsub("%+","%%2B"):gsub("/","%%2F"):gsub("=","%%3D")
            post("base64_image=" .. img .. "&caption=" .. urlEnc(caption))
        end)
    end

    local function shoot(isVictory)
        pcall(function()
            local SM = import("ScreenshotMaker")
            if not SM then return end
            local dir = Client and Client.ProjectSavedDir and Client.ProjectSavedDir() or ""
            local ts = os.time()
            local rawPath = string.format("%sScreenshots/fb_%d_%d.jpg", dir, ts, math.random(100,999))
            local shot = SM.MakePictureByName(rawPath, true) or rawPath
            local ticker = require("common.time_ticker")
            if ticker and ticker.AddTimerOnce then
                ticker.AddTimerOnce(1.0, function() send(shot, isVictory) end)
            else
                send(shot, isVictory)
            end
        end)
    end

    _G._GK_FeedbackStarted = false
    _G._GK_ScreenshotLoop = function()
        local ticker = require("common.time_ticker")
        if not ticker or not ticker.AddTimerOnce then return end
        ticker.AddTimerOnce(_SS_INTERVAL, function()
            if not _G._GK_FeedbackStarted then return end
            local now = os.time()
            if _LAST_LOOP_TIME > 0 and (now - _LAST_LOOP_TIME < 550) then
                _G._GK_ScreenshotLoop() return
            end
            _LAST_LOOP_TIME = now
            local gd = require("GameLua.GameCore.Data.GameplayData")
            local lp = gd and gd.GetLocalCharacter and gd.GetLocalCharacter()
            if lp and slua.isValid(lp) then shoot(false) end
            _G._GK_ScreenshotLoop()
        end)
    end
end

-- ========================================================================
-- [15] MAIN TICKER — 30 Hz
-- ========================================================================
pcall(function()
    local PC = nil
    if slua_GameFrontendHUD and slua_GameFrontendHUD.GetPlayerController then
        PC = slua_GameFrontendHUD:GetPlayerController()
    end
    if _IsValid(PC) and PC.AddGameTimer then
        PC:AddGameTimer(1/30, true, function()
            pcall(ESP.Update)
            pcall(AimCircle.Draw)
            pcall(Aim.Tick)
            local canvas = Hud.GetCanvas()
            if canvas then
                local r, b = 0, 0
                if ESP._lastCounts then
                    r = ESP._lastCounts.real or 0
                    b = ESP._lastCounts.bots or 0
                end
                pcall(Counter.Update, r, b, canvas)
                pcall(Watermark.Update, canvas)
            end
            if _G.DevBlackSky then pcall(WorldVis.ApplySky) end
            if _G.DevNoFog then pcall(WorldVis.ApplyFog) end
            if _G.DevNoGrass then pcall(WorldVis.ApplyGrass) end
        end)
    end
end)

-- ========================================================================
-- [16] SETTINGS MENU TAB (@TrnDravix original)
-- ========================================================================
local FakeTextMap = {
    [999000] = "DEVSLET MENU",
    [999001] = "ALL FEATURES",
    [999100] = "ESP",
    [999101] = "Counter",
    [999102] = "Snap Lines",
    [999103] = "Wallhack",
    [999104] = "Aim Force",
    [999105] = "Aim Assistant",
    [999106] = "Circle FOV",
    [999107] = "Small Crosshair",
    [999108] = "Black Sky",
    [999109] = "No Fog",
    [999110] = "No Grass",
    [999111] = "Bullet Tracking",
    [999112] = "BT: No Spread",
[999113] = "BT: Head Inflate",
[999114] = "BT: Magic Bullet",
[999115] = "BT: Snap Fire",
}

if not _G.MyFeature1 then _G.MyFeature1 = false end
if not _G.MyFeature2 then _G.MyFeature2 = false end
if not _G.MyFeature3 then _G.MyFeature3 = false end

local function HookLocUtil()
    local LocUtil = _G.LocUtil
    if not LocUtil and package.loaded["client.common.LocUtil"] then
        LocUtil = require("client.common.LocUtil")
    end
    if LocUtil and not LocUtil._IsModMenuHooked then
        local old = LocUtil.GetLocalizeResStr
        LocUtil.GetLocalizeResStr = function(id)
            if FakeTextMap[id] then return FakeTextMap[id] end
            if type(id) == "string" and not tonumber(id) then return id end
            return old(id)
        end
        LocUtil._IsModMenuHooked = true
    end
end

_G.InitModMenuTab = function()
    HookLocUtil()

    local SettingPageDefine = require("client.logic.NewSetting.SettingPageDefine")
    local SettingCatalog = require("client.logic.NewSetting.SettingCatalog")
    local AliasMap = require("client.slua.umg.NewSetting.Item.AliasMap")

    local MainStack = {
        { UI = AliasMap.Title, Text = 999001 },
        { Key = "DevESP", UI = AliasMap.Switcher, Text = 999100,
          GetFunc = function() return _G.DevESP == true end,
          SetFunc = function(_, v) _G.DevESP = v; return true end },
        { Key = "DevCounter", UI = AliasMap.Switcher, Text = 999101,
          GetFunc = function() return _G.DevCounter == true end,
          SetFunc = function(_, v) _G.DevCounter = v; return true end },
        { Key = "DevLines", UI = AliasMap.Switcher, Text = 999102,
          GetFunc = function() return _G.DevLines == true end,
          SetFunc = function(_, v) _G.DevLines = v; return true end },
        { Key = "DevWall", UI = AliasMap.Switcher, Text = 999103,
          GetFunc = function() return _G.DevWall == true end,
          SetFunc = function(_, v)
              _G.DevWall = v
              if v then WH.Start() else WH.Stop() end
              return true
          end },
        { Key = "DevForce", UI = AliasMap.Switcher, Text = 999104,
          GetFunc = function() return _G.DevForce == true end,
          SetFunc = function(_, v) _G.DevForce = v; return true end },
        { Key = "DevAssist", UI = AliasMap.Switcher, Text = 999105,
          GetFunc = function() return _G.DevAssist == true end,
          SetFunc = function(_, v) _G.DevAssist = v; return true end },
        { Key = "DevCircle", UI = AliasMap.Switcher, Text = 999106,
          GetFunc = function() return _G.DevCircle == true end,
          SetFunc = function(_, v) _G.DevCircle = v; return true end },
        { Key = "DevCross", UI = AliasMap.Switcher, Text = 999107,
          GetFunc = function() return _G.DevCross == true end,
          SetFunc = function(_, v) _G.DevCross = v; return true end },
        { Key = "DevSky", UI = AliasMap.Switcher, Text = 999108,
          GetFunc = function() return _G.DevBlackSky == true end,
          SetFunc = function(_, v)
              _G.DevBlackSky = v
              if v then WorldVis.ApplySky() else WorldVis.RestoreSky() end
              return true
          end },
        { Key = "DevFog", UI = AliasMap.Switcher, Text = 999109,
          GetFunc = function() return _G.DevNoFog == true end,
          SetFunc = function(_, v)
              _G.DevNoFog = v
              if v then WorldVis.ApplyFog() else WorldVis.RestoreFog() end
              return true
          end },
        { Key = "DevGrass", UI = AliasMap.Switcher, Text = 999110,
          GetFunc = function() return _G.DevNoGrass == true end,
          SetFunc = function(_, v)
              _G.DevNoGrass = v
              if v then WorldVis.ApplyGrass() else WorldVis.RestoreGrass() end
              return true
          end },
{ Key = "DevBulletTrack", UI = AliasMap.Switcher, Text = 999111,
  GetFunc = function() return _G.DevBulletTrack == true end,
  SetFunc = function(_, v)
      _G.DevBulletTrack = v
      if _G.BulletTrack then
          if v then pcall(_G.BulletTrack.Attach)
          else pcall(_G.BulletTrack.Detach) end
      end
      return true
  end },
         }
  
    if not SettingPageDefine.DevletMenu then
        SettingPageDefine.DevletMenu = {
            Key = "DevletMenu",
            Text = 999000,
            UIKey = "Setting_Page_Privacy",
            Category = {
                { Key = "Cat_Main", Text = 999001, Stack = MainStack },
            }
        }
        table.insert(SettingCatalog, 1, SettingPageDefine.DevletMenu)
    end

    local UIManager = _G.UIManager
    if UIManager and not UIManager._IsModMenuHooked then
        local old = UIManager.ShowUI
        UIManager.ShowUI = function(config, ...)
            local args = {...}
            if config and config.keyName and string.find(string.lower(config.keyName), "setting_main") then
                local catalog = args[1]
                if type(catalog) == "table" then
                    local has = false
                    for _, page in ipairs(catalog) do
                        if type(page) == "table" and page.Key == "DevletMenu" then has = true end
                    end
                    if not has and SettingPageDefine.DevletMenu then
                        table.insert(catalog, 1, SettingPageDefine.DevletMenu)
                    end
                end
            end
            return old(config, table.unpack(args))
        end
        UIManager._IsModMenuHooked = true
    end
end

_G.InitModMenuTab()

-- Feature flag — off by default so it doesn't collide with existing Aim.
if _G.DevBulletTrack == nil then _G.DevBulletTrack = false end
if _G.DevBulletTrack_Spread == nil then _G.DevBulletTrack_Spread = true  end
if _G.DevBulletTrack_Inflate == nil then _G.DevBulletTrack_Inflate = true  end
if _G.DevBulletTrack_Redir   == nil then _G.DevBulletTrack_Redir   = true  end
if _G.DevBulletTrack_Snap    == nil then _G.DevBulletTrack_Snap    = true  end

local BulletTrack = (function()
    -- ── local math cache (isolated from outer scope) ──────────────
    local _sq  = math.sqrt
    local _a2  = math.atan2 or math.atan
    local R2D  = 180 / math.pi

    local _sl  = slua
    local _iv  = _sl and _sl.isValid
    local function IV(o) return o ~= nil and _iv ~= nil and _iv(o) end

    local GD = require("GameLua.GameCore.Data.GameplayData")

    -- ── helpers ───────────────────────────────────────────────────
    local function Alive(p)
        if not IV(p) then return false end
        local a = true
        pcall(function()
            if p.HealthStatus ~= nil then a = p.HealthStatus < 3
            elseif type(p.IsAlive) == "function" then a = p:IsAlive()
            elseif p.Health ~= nil then a = p.Health > 0
            elseif p.HP ~= nil then a = p.HP > 0 end
        end)
        return a
    end

    local function TeamOf(ch)
        if not IV(ch) then return nil end
        local t = nil
        pcall(function()
            if ch.GetTeamID then t = ch:GetTeamID() end
            if not t then
                local ps = ch.PlayerState
                if not ps and type(ch.GetPlayerStateSafety) == "function" then
                    ps = ch:GetPlayerStateSafety()
                end
                if IV(ps) then
                    t = (ps.GetTeamID and ps:GetTeamID()) or ps.TeamID
                end
            end
            if not t then t = ch.TeamID end
        end)
        return t
    end

    local function MyKey()
        local pc = nil
        pcall(function() pc = GD.GetPlayerController and GD.GetPlayerController() end)
        if not IV(pc) then return nil end
        local k = nil
        pcall(function()
            if pc.GetPlayerKey then k = pc:GetPlayerKey()
            elseif pc.PlayerState and pc.PlayerState.PlayerKey then
                k = pc.PlayerState.PlayerKey
            end
        end)
        return k
    end

    local function IsMe(ch, pk, mk)
        local me = false
        pcall(function()
            local mc = GD.GetLocalCharacter and GD.GetLocalCharacter()
            if mc and ch == mc then me = true; return end
            local pc = GD.GetPlayerController and GD.GetPlayerController()
            if IV(pc) and pc.GetPawn then
                local pw = pc:GetPawn()
                if pw and ch == pw then me = true end
            end
        end)
        if not me and mk ~= nil and pk ~= nil then
            me = tostring(pk) == tostring(mk)
        end
        return me
    end

    local function AllPawns()
        local cl, cc = {}, 0
        pcall(function()
            local pw = Game:GetAllPlayerPawns()
            if not pw then return end
            local n = pw.Num and pw:Num() or nil
            local function ap(p)
                if not (p and IV(p)) then return end
                local k = nil
                if p.GetPlayerKey then k = p:GetPlayerKey()
                elseif p.PlayerKey then k = p.PlayerKey
                elseif p.PlayerState and p.PlayerState.PlayerKey then
                    k = p.PlayerState.PlayerKey
                end
                if k then
                    cc = cc + 1
                    cl[cc] = { key = k, pawn = p }
                end
            end
            if n then
                for i = 1, n do
                    local p = nil
                    pcall(function() p = pw:Get(i - 1) end)
                    ap(p)
                end
            else
                for _, p in pairs(pw) do ap(p) end
            end
        end)
        return cl, cc
    end

    local function Loc(ch)
        if not IV(ch) then return nil end
        local l = nil
        pcall(function()
            if ch.K2_GetActorLocation then l = ch:K2_GetActorLocation() end
        end)
        return l
    end

    local function HeadFallback(ch)
        local c = Loc(ch)
        if not c then return nil end
        local h = 85
        pcall(function()
            if ch.IsProne and ch:IsProne() then h = 30
            elseif ch.bIsCrouched then h = 60 end
        end)
        return { X = c.X, Y = c.Y, Z = c.Z + h }
    end

    local function Dist3(a, b)
        if not a or not b then return 1e18 end
        local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
        return dx * dx + dy * dy + dz * dz
    end

    local function LocalPlayer()
        local lp = nil
        pcall(function() lp = GD.GetLocalCharacter and GD.GetLocalCharacter() end)
        if not IV(lp) then
            pcall(function()
                local pc = GD.GetPlayerController and GD.GetPlayerController()
                if IV(pc) and pc.GetPawn then lp = pc:GetPawn() end
            end)
        end
        return lp
    end

    local function LocalPC()
        local pc = nil
        pcall(function()
            pc = GD.GetPlayerController and GD.GetPlayerController()
            if not IV(pc) and slua_GameFrontendHUD then
                pc = slua_GameFrontendHUD:GetPlayerController()
            end
        end)
        return pc
    end

    -- ── no-recoil / spread neutralization ────────────────────────
    local ULT_HitScl = 200
    local ULT_HBones = { "head", "skull", "neck_01", "b_head", "c_head", "head_01" }

    local function NeutralizeRecoil()
        if not _G.DevBulletTrack_Spread then return end
        pcall(function()
            local p = LocalPlayer()
            if not IV(p) then return end
            local w = p:GetCurrentWeapon()
            if not IV(w) then return end
            local s = w.ShootWeaponEntity or w.ShootWeaponEntity_GEN_VARIABLE
            if IV(s) then
                s.GameDeviationFactor  = 0
                s.ExtraHitPerformScale = ULT_HitScl
                if s.ExtraHitBoneList ~= nil then s.ExtraHitBoneList = ULT_HBones end
                if s.ScopeAimShootSpreadRot    ~= nil then s.ScopeAimShootSpreadRot    = 0 end
                if s.ScopeAimShootSpreadDir    ~= nil then s.ScopeAimShootSpreadDir    = 0 end
                if s.ScopeAimShootSpreadDirValMax ~= nil then s.ScopeAimShootSpreadDirValMax = 0 end
                if s.ScopeAimShootSpreadRotValMax ~= nil then s.ScopeAimShootSpreadRotValMax = 0 end
            end
            local aac = w.AutoAimingConfig
            if aac ~= nil then
                if aac.bEnabled    ~= nil then aac.bEnabled    = true end
                if aac.AimStrength ~= nil then aac.AimStrength = 1.0 end
                if aac.TargetBone  ~= nil then aac.TargetBone  = "head" end
                if aac.AimBone     ~= nil then aac.AimBone     = "head" end
            end
            local arc = w.AutoAimingRangeConfig
            if arc ~= nil then
                if arc.MaxRange ~= nil then arc.MaxRange = 999999 end
                if arc.MinRange ~= nil then arc.MinRange = 0 end
            end
        end)
    end

    -- ── head hitbox inflation (per-enemy, cached) ────────────────
    local HS_Scale, HS_HRatio = 12.0, 0.95
    local _inflated = setmetatable({}, { __mode = "k" })

    local function InflateHead(ch)
        if not _G.DevBulletTrack_Inflate then return end
        if _inflated[ch] then return end
        pcall(function()
            local sc = HS_Scale
            local function xB(v)
                if v then
                    return {
                        X = (v.X or 8) * sc,
                        Y = (v.Y or 8) * sc,
                        Z = (v.Z or 8) * sc
                    }
                end
            end
            if ch.HeadBoundBoxExtent            ~= nil then ch.HeadBoundBoxExtent            = xB(ch.HeadBoundBoxExtent) end
            if ch.CrouchStillHeadBoundBoxExtent ~= nil then ch.CrouchStillHeadBoundBoxExtent = xB(ch.CrouchStillHeadBoundBoxExtent) end
            if ch.StandStillHeadBoundBoxExtent  ~= nil then ch.StandStillHeadBoundBoxExtent  = xB(ch.StandStillHeadBoundBoxExtent) end
            if ch.HeadRatio          ~= nil then ch.HeadRatio = HS_HRatio end
            if ch.ModesIgnoreHitHead ~= nil then ch.ModesIgnoreHitHead = false end
            local fh = ch.CharacterFakeHeadMesh_Lod
            if IV(fh) then
                pcall(function() fh:SetWorldScale3D({ X = sc, Y = sc, Z = sc }) end)
            end
        end)
        _inflated[ch] = true
    end

    -- ── rotation helpers ─────────────────────────────────────────
    local _FRT = nil
    pcall(function() _FRT = _G.FRotator or import("Rotator") end)

    local function MkRot(p, y)
        if _FRT then
            local ok, r = pcall(function() return _FRT(p, y, 0) end)
            if ok and r then return r end
        end
        return { Pitch = p, Yaw = y, Roll = 0 }
    end

    local function LookAt(from, to)
        local dx, dy, dz = to.X - from.X, to.Y - from.Y, to.Z - from.Z
        local d2 = _sq(dx * dx + dy * dy)
        return MkRot(-_a2(dz, d2) * R2D, _a2(dy, dx) * R2D)
    end

    local function HeadPoint(ch)
        local p = nil
        pcall(function()
            local m = ch.Mesh
            if IV(m) and m.GetSocketLocation then
                pcall(function()
                    p = m:GetSocketLocation("head")
                    if p and p.X == 0 and p.Y == 0 then p = nil end
                end)
                if not p then
                    pcall(function() p = m:GetSocketLocation("neck_01") end)
                end
            end
        end)
        if p and (p.X ~= 0 or p.Y ~= 0 or p.Z ~= 0) then return p end
        return HeadFallback(ch)
    end

    local function IsFiring(pw)
        local f = false
        pcall(function()
            local w = nil
            pcall(function() w = pw:GetCurrentWeapon() end)
            if not IV(w) then
                pcall(function() w = pw:GetCurrentShootWeapon() end)
            end
            if IV(w) then
                local se = w.ShootWeaponEntity or w.ShootWeaponEntity_GEN_VARIABLE
                if IV(se) then
                    if se.bFiring == true then f = true; return end
                    pcall(function()
                        if se:IsFiring() == true then f = true end
                    end)
                end
            end
            if not f then f = (pw.bFiring == true) end
        end)
        return f
    end

    -- ── auto-aim component binding ───────────────────────────────
    local _aac = nil

    local function BindAutoAim(lp, targetCh)
        pcall(function()
            if not IV(_aac) then
                _aac = lp.BP_AutoAimingComponent_GEN_VARIABLE
                    or lp.AutoAimingComponent
                    or lp.AutoAimComp
            end
            if not IV(_aac) then return end
            local m = targetCh.Mesh
            pcall(function() if _aac.SetTarget          then _aac:SetTarget(targetCh)  end end)
            pcall(function() if _aac.SetTargetComponent then _aac:SetTargetComponent(m) end end)
            pcall(function() if _aac.SetTargetBone      then _aac:SetTargetBone("head") end end)
            pcall(function() if _aac.TargetActor     ~= nil then _aac.TargetActor     = targetCh end end)
            pcall(function() if _aac.TargetComponent ~= nil then _aac.TargetComponent = m        end end)
            pcall(function() if _aac.TargetBone      ~= nil then _aac.TargetBone      = "head"   end end)
            pcall(function() if _aac.AimTargetActor  ~= nil then _aac.AimTargetActor  = targetCh end end)
            pcall(function() if _aac.bActive         ~= nil then _aac.bActive         = true     end end)
            pcall(function() if _aac.bEnabled        ~= nil then _aac.bEnabled        = true     end end)
            pcall(function() if _aac.AimStrength     ~= nil then _aac.AimStrength     = 1.0      end end)
        end)
    end

    -- ── projectile redirection ───────────────────────────────────
    local BCLS = {
        "NormalProjectile",
        "BP_PlayerRifleBullet_C",
        "BP_PlayerBullet_C"
    }
    local _resolvedBC = {}

    local function ResolveBC()
        if #_resolvedBC > 0 then return _resolvedBC end
        for _, cn in ipairs(BCLS) do
            local ok, bc = pcall(import, cn)
            if ok and IV(bc) then
                _resolvedBC[#_resolvedBC + 1] = bc
            end
        end
        return _resolvedBC
    end

    local function RedirectProjectiles(head)
        if not _G.DevBulletTrack_Redir then return end
        if not head then return end
        for _, bc in ipairs(ResolveBC()) do
            pcall(function()
                local bullets = Game:GetAllActorsOfClass(bc)
                if not bullets then return end
                for i = 0, bullets:Num() - 1 do
                    local b = bullets:Get(i)
                    if IV(b) then
                        local bloc = nil
                        pcall(function() bloc = b:K2_GetActorLocation() end)
                        if bloc then
                            local dx, dy, dz = head.X - bloc.X, head.Y - bloc.Y, head.Z - bloc.Z
                            local d = _sq(dx * dx + dy * dy + dz * dz)
                            if d > 1 then
                                local mc = b.BulletMovementComponent
                                    or b.DelayFlyProjMovementComponent
                                if IV(mc) then
                                    local spd = mc.MaxSpeed or mc.InitialSpeed or 40000
                                    local inv = spd / d
                                    local v = { X = dx * inv, Y = dy * inv, Z = dz * inv }
                                    pcall(function() mc.Velocity = v end)
                                    pcall(function()
                                        if mc.LaunchVelocity ~= nil then mc.LaunchVelocity = v end
                                    end)
                                end
                            end
                        end
                    end
                end
            end)
        end
    end

    -- ── main tick ────────────────────────────────────────────────
    local function Tick()
        if not _G.DevBulletTrack then return end
        local pc = LocalPC()
        if not IV(pc) then return end
        local lp = LocalPlayer()
        if not IV(lp) then return end
        local mk = MyKey()
        local mt = TeamOf(lp)

        NeutralizeRecoil()

        local camLoc = nil
        pcall(function()
            local cm = pc:GetPlayerCameraManager()
            if IV(cm) then camLoc = cm:GetCameraLocation() end
        end)
        if not camLoc then
            pcall(function() camLoc = lp:K2_GetActorLocation() end)
        end
        if not camLoc then return end

        local nearestHead, nearestCh, nearestD = nil, nil, math.huge
        pcall(function()
            local cl, cnt = AllPawns()
            for i = 1, cnt do
                local e = cl[i]
                if not e then break end
                local ch = e.pawn
                if IV(ch) and ch ~= lp and not IsMe(ch, e.key, mk)
                    and Alive(ch)
                    and (mt == nil or TeamOf(ch) ~= mt) then
                    InflateHead(ch)
                    local hp = HeadPoint(ch)
                    if hp then
                        local d = Dist3(camLoc, hp)
                        if d < nearestD then
                            nearestD, nearestHead, nearestCh = d, hp, ch
                        end
                    end
                end
            end
        end)

        if not nearestCh then return end

        BindAutoAim(lp, nearestCh)
        RedirectProjectiles(nearestHead)

        if _G.DevBulletTrack_Snap and IsFiring(lp) then
            local rot = LookAt(camLoc, nearestHead)
            pcall(function() pc:SetControlRotation(rot) end)
            pcall(function() pc:ClientSetRotation(rot, true) end)
            pcall(function()
                local ctrl = lp:GetController()
                if IV(ctrl) then ctrl:SetControlRotation(rot) end
            end)
        end
    end

    -- ── lifecycle ────────────────────────────────────────────────
    local _attached = false
    local _timer    = nil
    local _lastPC   = nil

    local function Attach()
        if _attached then return end
        local pc = LocalPC()
        if not IV(pc) then
            pcall(function() require("timer").SetGameTimer(1, false, Attach) end)
            return
        end
        _attached = true
        _lastPC   = pc
        _timer    = pc:AddGameTimer(1 / 60, true, function() pcall(Tick) end)

        -- watchdog: rebind if PC swaps (level transition / respawn)
        pc:AddGameTimer(1, true, function()
            local cur = LocalPC()
            if IV(cur) and cur ~= _lastPC then
                _lastPC   = cur
                _attached = false
                _aac      = nil
                pcall(Attach)
            end
        end)
    end

    local function Detach()
        if _timer and IV(_timer) then
            pcall(function() _timer:Invalidate() end)
        end
        _timer, _attached, _lastPC = nil, false, nil
    end

    local M = {}
    M.Tick    = Tick
    M.Attach  = Attach
    M.Detach  = Detach
    M.Inflate = InflateHead
    return M
end)()

_G.BulletTrack = BulletTrack

-- Auto-attach when the pawn is ready and the flag is on.
pcall(function()
    require("timer").SetGameTimer(2, false, function()
        if _G.DevBulletTrack then BulletTrack.Attach() end
    end)
end)
-- ═══════════════════════════════════════════════════════════════════
-- [18] BULLET TRACKING SUBSYSTEM — grafted from standalone module
-- ═══════════════════════════════════════════════════════════════════
local UltimateEngine = "UltimateEngine"

local _sq = math.sqrt
local _a2 = math.atan2 or math.atan
local _cs = math.cos
local _sn = math.sin
local _ab = math.abs
local _rd = math.rad
local PI = math.pi
local PI2 = PI * 2
local R2D = 180 / PI

local GD = require("GameLua.GameCore.Data.GameplayData")
local _sl = slua
local _iv = _sl and _sl.isValid

local function IV(o)
    return o ~= nil and _iv ~= nil and _iv(o)
end

local function IPA(p)
    if not p or not IV(p) then return false end
    local a = true
    pcall(function()
        if p.HealthStatus ~= nil then
            a = p.HealthStatus < 3
        elseif type(p.IsAlive) == "function" then
            a = p:IsAlive()
        elseif p.Health ~= nil then
            a = p.Health > 0
        elseif p.HP ~= nil then
            a = p.HP > 0
        end
    end)
    return a
end

local function GTI(ch)
    if not IV(ch) then return nil end
    local t = nil
    pcall(function()
        if ch.GetTeamID then t = ch:GetTeamID() end
        if not t then
            local ps = ch.PlayerState
            if not ps and type(ch.GetPlayerStateSafety) == "function" then
                ps = ch:GetPlayerStateSafety()
            end
            if IV(ps) then
                t = (ps.GetTeamID and ps:GetTeamID()) or ps.TeamID
            end
        end
        if not t then t = ch.TeamID end
    end)
    return t
end

local function GMK()
    local pc = nil
    pcall(function() pc = GD.GetPlayerController and GD.GetPlayerController() end)
    if not IV(pc) then return nil end
    local k = nil
    pcall(function()
        if pc.GetPlayerKey then
            k = pc:GetPlayerKey()
        elseif pc.PlayerState and pc.PlayerState.PlayerKey then
            k = pc.PlayerState.PlayerKey
        end
    end)
    return k
end

local function IM(ch, pk, mk)
    local me = false
    pcall(function()
        local mc = GD.GetLocalCharacter and GD.GetLocalCharacter()
        if mc and ch == mc then me = true; return end
        local pc = GD.GetPlayerController and GD.GetPlayerController()
        if IV(pc) and pc.GetPawn then
            local pw = pc:GetPawn()
            if pw and ch == pw then me = true end
        end
    end)
    if not me and mk ~= nil and pk ~= nil then
        me = tostring(pk) == tostring(mk)
    end
    return me
end

local function XVL()
    local cl, cc = {}, 0
    pcall(function()
        local pw = Game:GetAllPlayerPawns()
        if not pw then return end
        local n = pw.Num and pw:Num() or nil
        local function ap(p)
            if not (p and IV(p)) then return end
            local k = nil
            if p.GetPlayerKey then
                k = p:GetPlayerKey()
            elseif p.PlayerKey then
                k = p.PlayerKey
            elseif p.PlayerState and p.PlayerState.PlayerKey then
                k = p.PlayerState.PlayerKey
            end
            if k then
                cc = cc + 1
                cl[cc] = { key = k, pawn = p }
            end
        end
        if n then
            for i = 1, n do
                local p = nil
                pcall(function() p = pw:Get(i - 1) end)
                ap(p)
            end
        else
            for _, p in pairs(pw) do ap(p) end
        end
    end)
    return cl, cc
end

local function CC(ch)
    if not IV(ch) then return nil end
    local l = nil
    pcall(function()
        if ch.K2_GetActorLocation then l = ch:K2_GetActorLocation() end
    end)
    return l
end

local function HH(ch)
    if ch.IsProne and ch:IsProne() then return 30 end
    if ch.bIsCrouched then return 60 end
    return 85
end

local function HL(ch)
    local c = CC(ch)
    if not c then return nil end
    local h = 85
    pcall(function() h = HH(ch) end)
    return { X = c.X, Y = c.Y, Z = c.Z + h }
end

local function DS3(a, b)
    if not a or not b then return 1e18 end
    local dx = a.X - b.X
    local dy = a.Y - b.Y
    local dz = a.Z - b.Z
    return dx * dx + dy * dy + dz * dz
end

local function LocalPlayer()
    local lp = nil
    pcall(function() lp = GD.GetLocalCharacter and GD.GetLocalCharacter() end)
    if not IV(lp) then
        pcall(function()
            local pc = GD.GetPlayerController and GD.GetPlayerController()
            if IV(pc) and pc.GetPawn then lp = pc:GetPawn() end
        end)
    end
    return lp
end

local function LocalPC()
    local pc = nil
    pcall(function()
        pc = GD.GetPlayerController and GD.GetPlayerController()
        if not IV(pc) and slua_GameFrontendHUD then
            pc = slua_GameFrontendHUD:GetPlayerController()
        end
    end)
    return pc
end

local ULT_HitScl = 200
local ULT_HBones = { "head", "skull", "neck_01", "b_head", "c_head", "head_01" }

local function NR()
    pcall(function()
        local p = LocalPlayer()
        if not IV(p) then return end
        local w = p:GetCurrentWeapon()
        if not IV(w) then return end
        local s = w.ShootWeaponEntity or w.ShootWeaponEntity_GEN_VARIABLE
        if IV(s) then
            s.GameDeviationFactor = 0
            s.ExtraHitPerformScale = ULT_HitScl
            pcall(function()
                if s.ExtraHitBoneList ~= nil then s.ExtraHitBoneList = ULT_HBones end
            end)
            pcall(function()
                if s.ScopeAimShootSpreadRot ~= nil then s.ScopeAimShootSpreadRot = 0 end
                if s.ScopeAimShootSpreadDir ~= nil then s.ScopeAimShootSpreadDir = 0 end
                if s.ScopeAimShootSpreadDirValMax ~= nil then s.ScopeAimShootSpreadDirValMax = 0 end
                if s.ScopeAimShootSpreadRotValMax ~= nil then s.ScopeAimShootSpreadRotValMax = 0 end
            end)
        end
        pcall(function()
            local aac = w.AutoAimingConfig
            if aac ~= nil then
                if aac.bEnabled ~= nil then aac.bEnabled = true end
                if aac.AimStrength ~= nil then aac.AimStrength = 1.0 end
                if aac.TargetBone ~= nil then aac.TargetBone = "head" end
                if aac.AimBone ~= nil then aac.AimBone = "head" end
            end
            local arc = w.AutoAimingRangeConfig
            if arc ~= nil then
                if arc.MaxRange ~= nil then arc.MaxRange = 999999 end
                if arc.MinRange ~= nil then arc.MinRange = 0 end
            end
        end)
    end)
end

local HS_Scale = 12.0
local HS_HRatio = 0.95
local _HS_Done = {}

local function HS_Enemy(ch)
    local uid = tostring(ch)
    if _HS_Done[uid] then return end
    pcall(function()
        local sc = HS_Scale
        local function xB(v)
            if v then
                return {
                    X = (v.X or 8) * sc,
                    Y = (v.Y or 8) * sc,
                    Z = (v.Z or 8) * sc
                }
            end
        end
        if ch.HeadBoundBoxExtent ~= nil then
            ch.HeadBoundBoxExtent = xB(ch.HeadBoundBoxExtent)
        end
        if ch.CrouchStillHeadBoundBoxExtent ~= nil then
            ch.CrouchStillHeadBoundBoxExtent = xB(ch.CrouchStillHeadBoundBoxExtent)
        end
        if ch.StandStillHeadBoundBoxExtent ~= nil then
            ch.StandStillHeadBoundBoxExtent = xB(ch.StandStillHeadBoundBoxExtent)
        end
        if ch.HeadRatio ~= nil then ch.HeadRatio = HS_HRatio end
        if ch.ModesIgnoreHitHead ~= nil then ch.ModesIgnoreHitHead = false end
        local fh = ch.CharacterFakeHeadMesh_Lod
        if IV(fh) then
            pcall(function() fh:SetWorldScale3D({ X = sc, Y = sc, Z = sc }) end)
        end
    end)
    _HS_Done[uid] = true
end

local _FRT = nil
pcall(function() _FRT = _G.FRotator or import("Rotator") end)

local function MkRot(p, y)
    if _FRT then
        local ok, r = pcall(function() return _FRT(p, y, 0) end)
        if ok and r then return r end
    end
    return { Pitch = p, Yaw = y, Roll = 0 }
end

local function CHS_LookAt(from, to)
    local dx = to.X - from.X
    local dy = to.Y - from.Y
    local dz = to.Z - from.Z
    local d2 = _sq(dx * dx + dy * dy)
    return MkRot(-_a2(dz, d2) * R2D, _a2(dy, dx) * R2D)
end

local function CHS_HP(ch)
    local p = nil
    pcall(function()
        local m = ch.Mesh
        if IV(m) and m.GetSocketLocation then
            pcall(function()
                p = m:GetSocketLocation("head")
                if p and p.X == 0 and p.Y == 0 then p = nil end
            end)
            if not p then
                pcall(function() p = m:GetSocketLocation("neck_01") end)
            end
        end
    end)
    if p and (p.X ~= 0 or p.Y ~= 0 or p.Z ~= 0) then return p end
    return HL(ch)
end

local function CHS_Firing(pw)
    local f = false
    pcall(function()
        local w = nil
        pcall(function() w = pw:GetCurrentWeapon() end)
        if not IV(w) then
            pcall(function() w = pw:GetCurrentShootWeapon() end)
        end
        if IV(w) then
            local se = w.ShootWeaponEntity or w.ShootWeaponEntity_GEN_VARIABLE
            if IV(se) then
                if se.bFiring == true then f = true; return end
                pcall(function()
                    if se:IsFiring() == true then f = true end
                end)
            end
        end
        if not f then f = (pw.bFiring == true) end
    end)
    return f
end

local _ULT_AAC = nil
local _ULT_BCLASSES = {
    "NormalProjectile",
    "BP_PlayerRifleBullet_C",
    "BP_PlayerBullet_C"
}

local function ULT_SetAutoAimTarget(lp, targetCh)
    pcall(function()
        if not IV(_ULT_AAC) then
            _ULT_AAC = lp.BP_AutoAimingComponent_GEN_VARIABLE
                or lp.AutoAimingComponent
                or lp.AutoAimComp
        end
        if not IV(_ULT_AAC) then return end
        local m = targetCh.Mesh
        pcall(function()
            if _ULT_AAC.SetTarget then _ULT_AAC:SetTarget(targetCh) end
        end)
        pcall(function()
            if _ULT_AAC.SetTargetComponent then _ULT_AAC:SetTargetComponent(m) end
        end)
        pcall(function()
            if _ULT_AAC.SetTargetBone then _ULT_AAC:SetTargetBone("head") end
        end)
        pcall(function()
            if _ULT_AAC.TargetActor ~= nil then _ULT_AAC.TargetActor = targetCh end
        end)
        pcall(function()
            if _ULT_AAC.TargetComponent ~= nil then _ULT_AAC.TargetComponent = m end
        end)
        pcall(function()
            if _ULT_AAC.TargetBone ~= nil then _ULT_AAC.TargetBone = "head" end
        end)
        pcall(function()
            if _ULT_AAC.AimTargetActor ~= nil then _ULT_AAC.AimTargetActor = targetCh end
        end)
        pcall(function()
            if _ULT_AAC.bActive ~= nil then _ULT_AAC.bActive = true end
        end)
        pcall(function()
            if _ULT_AAC.bEnabled ~= nil then _ULT_AAC.bEnabled = true end
        end)
        pcall(function()
            if _ULT_AAC.AimStrength ~= nil then _ULT_AAC.AimStrength = 1.0 end
        end)
    end)
end

local function ULT_RedirProjectiles(nearestHead)
    if not nearestHead then return end
    for _, cn in ipairs(_ULT_BCLASSES) do
        pcall(function()
            local bc = nil
            pcall(function() bc = import(cn) end)
            if not IV(bc) then return end
            local bullets = Game:GetAllActorsOfClass(bc)
            if not bullets then return end
            for i = 0, bullets:Num() - 1 do
                local b = bullets:Get(i)
                if IV(b) then
                    local bloc = nil
                    pcall(function() bloc = b:K2_GetActorLocation() end)
                    if bloc then
                        local dx = nearestHead.X - bloc.X
                        local dy = nearestHead.Y - bloc.Y
                        local dz = nearestHead.Z - bloc.Z
                        local d = _sq(dx * dx + dy * dy + dz * dz)
                        if d > 1 then
                            local mc = b.BulletMovementComponent
                                or b.DelayFlyProjMovementComponent
                            if IV(mc) then
                                local spd = mc.MaxSpeed or mc.InitialSpeed or 40000
                                local nx, ny, nz = dx / d, dy / d, dz / d
                                pcall(function()
                                    mc.Velocity = {
                                        X = nx * spd,
                                        Y = ny * spd,
                                        Z = nz * spd
                                    }
                                end)
                                pcall(function()
                                    if mc.LaunchVelocity ~= nil then
                                        mc.LaunchVelocity = {
                                            X = nx * spd,
                                            Y = ny * spd,
                                            Z = nz * spd
                                        }
                                    end
                                end)
                            end
                        end
                    end
                end
            end
        end)
    end
end

local function MainTick()
    local pc = LocalPC()
    if not IV(pc) then return end
    local lp = LocalPlayer()
    if not IV(lp) then return end
    local mk = GMK()
    local mt = GTI(lp)

    NR()

    local camLoc = nil
    pcall(function()
        local cm = pc:GetPlayerCameraManager()
        if IV(cm) then camLoc = cm:GetCameraLocation() end
    end)
    if not camLoc then
        pcall(function() camLoc = lp:K2_GetActorLocation() end)
    end
    if not camLoc then return end

    local nearestHead, nearestCh, nearestD = nil, nil, math.huge
    pcall(function()
        local cl, cnt = XVL()
        for i = 1, cnt do
            local e = cl[i]
            if not e then break end
            local ch = e.pawn
            if IV(ch) and ch ~= lp and not IM(ch, e.key, mk) and IPA(ch)
                and (mt == nil or GTI(ch) ~= mt) then
                HS_Enemy(ch)
                local hp = CHS_HP(ch)
                if hp then
                    local d = DS3(camLoc, hp)
                    if d < nearestD then
                        nearestD = d
                        nearestHead = hp
                        nearestCh = ch
                    end
                end
            end
        end
    end)

    if not nearestCh then return end

    ULT_SetAutoAimTarget(lp, nearestCh)
    ULT_RedirProjectiles(nearestHead)

    if CHS_Firing(lp) then
        local rot = CHS_LookAt(camLoc, nearestHead)
        pcall(function() pc:SetControlRotation(rot) end)
        pcall(function() pc:ClientSetRotation(rot, true) end)
        pcall(function()
            local ctrl = lp:GetController()
            if IV(ctrl) then ctrl:SetControlRotation(rot) end
        end)
    end
end

local _attached = false

local function Attach()
    if _attached then return end
    local pc = LocalPC()
    if not IV(pc) then
        pcall(function()
            require("timer").SetGameTimer(1, false, Attach)
        end)
        return
    end
    _attached = true
    pc:AddGameTimer(1 / 60, true, function() pcall(MainTick) end)
    pcall(function()
        local lastPC = pc
        pc:AddGameTimer(1, true, function()
            local cur = LocalPC()
            if IV(cur) and cur ~= lastPC then
                lastPC = cur
                _attached = false
                pcall(function()
                    cur:AddGameTimer(1 / 60, true, function() pcall(MainTick) end)
                end)
                _attached = true
            end
        end)
    end)
end

pcall(Attach)
pcall(function()
    require("timer").SetGameTimer(1, false, function() pcall(Attach) end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- [17] BRPlayerCharacterBase + INIT + LOGIN
-- ═══════════════════════════════════════════════════════════════════
local BRPlayerCharacterBase = {
    ServerRPC = {}, ClientRPC = {}, MulticastRPC = {}
}

function BRPlayerCharacterBase:ctor()
    self._modInit = false
    self._whStarted = false
    self._welcomeShown = false
end

function BRPlayerCharacterBase:_PostConstruct()
    BRPlayerCharacterBase.__super._PostConstruct(self)
    self:InitAddSpecialMoveInfo()
    self.bCanNearDeathGiveup = true
    self:StartAdvancedSystems()
end

function BRPlayerCharacterBase:ReceiveBeginPlay()
    BRPlayerCharacterBase.__super.ReceiveBeginPlay(self)
    if Client then GameplayData.AddCharacter(self.Object) end
end

function BRPlayerCharacterBase:ReceiveEndPlay(reason)
    BRPlayerCharacterBase.__super.ReceiveEndPlay(self, reason)
    if Client and GameplayData.RemoveCharacter then
        GameplayData.RemoveCharacter(self.Object)
    end
end

function BRPlayerCharacterBase:StartAdvancedSystems()
    if not Client or self._modInit then return end
    self._modInit = true

    self:AddGameTimer(0.5, false, function()
        if not slua.isValid(self.Object) then return end
        local localPlayer = GameplayData.GetPlayerCharacter()
        if not slua.isValid(localPlayer) or self.Object ~= localPlayer then return end

        if not self._whStarted and _G.DevWall then
            self._whStarted = true
            pcall(function() WH.Start() end)
        end
        Enable165FPS()
        Apply165FPSInGame()
        pcall(_G.InitModMenuTab)
        pcall(function() if _G.DevBlackSky then WorldVis.ApplySky() end end)
        pcall(function() if _G.DevNoFog then WorldVis.ApplyFog() end end)
        pcall(function() if _G.DevNoGrass then WorldVis.ApplyGrass() end end)

        -- ⭐ BULLET TRACKING AUTO-ATTACH — MUST BE INSIDE THIS FUNCTION
        self:AddGameTimer(2.0, false, function()
            if _G.DevBulletTrack and _G.BulletTrack then
                pcall(_G.BulletTrack.Attach)
            end
        end)

        -- ⭐ WELCOME POPUP — only once per session
        if not self._welcomeShown and _G._LICENSE_OK then
            self._welcomeShown = true
            self:AddGameTimer(5.0, false, function()
                pcall(_G.DevShowWelcomeMessage)
            end)
        end
    end)

    self:AddGameTimer(1.0, true, function()
        if not slua.isValid(self.Object) then return end
        local localPlayer = GameplayData.GetPlayerCharacter()
        if not slua.isValid(localPlayer) or self.Object ~= localPlayer then return end
        if _G.DevWall and not WH.Timer then pcall(function() WH.Start() end) end
        _G._WHA_BYPASS_ACTIVE = true

        -- ⭐ BULLET TRACKING RECOVERY — rebinds if the PC swapped
        if _G.DevBulletTrack and _G.BulletTrack then
            pcall(_G.BulletTrack.Attach)
        end

        -- Re-apply world commands (some are reset per match)
        if _G.DevBlackSky then pcall(WorldVis.ApplySky) end
        if _G.DevNoFog     then pcall(WorldVis.ApplyFog) end
        if _G.DevNoGrass   then pcall(WorldVis.ApplyGrass) end
    end)
end

-- [rest of [17] unchanged — the pcall(launch) block, the class def, the return]═══════════════════════════════════════════════════════════════════
-- [18] BULLET TRACKING SUBSYSTEM — grafted from standalone module
-- ═══════════════════════════════════════════════════════════════════

local class = require("class")
local CCharacterBase = require("GameLua.GameCore.Framework.CharacterBase")
local CBRPlayerCharacterBase = class(CCharacterBase, nil, BRPlayerCharacterBase)
return require("combine_class").DeclareFeature(CBRPlayerCharacterBase, {
  { SkyTransition = "GameLua.Mod.BaseMod.Gameplay.Feature.SkyControl.PlayerCharacterSkyTransitionFeature" },
  { CarryDeadBoxFeature = "GameLua.Mod.Library.GamePlay.Feature.CarryDeadBoxFeature" },
  { SpecialSuitFeature = "GameLua.Mod.Library.GamePlay.Feature.SpecialSuitFeature" },
  { TeleportPawnFeature = "GameLua.Mod.Library.GamePlay.Feature.TeleportPawnFeature" },
  { LifterControl = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.CharacterLifterControlFeature" },
  { FinalKillEffect = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.PlayerCharacterFinalKillEffectFeature" },
  { CampFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.Camp.PlayerCharacterCampFeature" },
  { BuildSkateFeature = "GameLua.Mod.BaseMod.Gameplay.Feature.PlayerCharacterBuildVehicleFeature" },
  { CommonBornlandTransformFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.HeroPropFeature.CommonBornlandTransformFeature" },
  { ParachuteFormation = "GameLua.Mod.BaseMod.Gameplay.Feature.ParachuteFormationFeature" },
  { SpiderSenseFootprintFeature = "GameLua.Mod.Library.GamePlay.Feature.SpiderSenseFootprintFeature" },
  { GeneralShowSpotFeature = "GameLua.Mod.BRMod.Gameplay.Feature.PlayerCharacterGeneralShowSpotFeature" }
}, "BRPlayerCharacterBase")