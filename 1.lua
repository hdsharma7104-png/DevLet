-- ====================================================================
-- BRPlayerCharacterBase.lua V6100 (RJ Universal FIX) - VERSION 3500
-- UNIVERSAL: Works on Global / KR / VN / TW / BGMI / any version
-- FIXED: Bat/Transformation revert works (exclusion list applied)
-- ====================================================================

-- ====================================================================
-- UNIVERSAL PACKAGE DETECTION
-- ====================================================================
local SUPPORTED_PACKAGES = {
    ["com.tencent.ig"]        = "Global",
    ["com.pubg.krmobile"]     = "Korea",
    ["com.vng.pubgmobile"]    = "Vietnam",
    ["com.rekoo.pubgm"]       = "Taiwan",
    ["com.pubg.imobile"]      = "BGMI",
    ["com.pubg.krmobile.ig"]  = "Korea-Alt",
    ["com.tencent.tmgp.pubgmhd"] = "CN",
    ["com.tencent.tmgp.pubgm"] = "CN-Alt",
}

local packageName = nil
local gameRegion = "Unknown"

pcall(function()
    local KSL = import("KismetSystemLibrary")
    if KSL and KSL.GetGameBundleId then
        packageName = KSL:GetGameBundleId()
    end
end)

if not packageName then
    local probes = {
        "com.tencent.ig", "com.pubg.krmobile", "com.vng.pubgmobile",
        "com.rekoo.pubgm", "com.pubg.imobile", "com.tencent.tmgp.pubgmhd",
        "com.tencent.tmgp.pubgm"
    }
    for _, pkg in ipairs(probes) do
        local f = io.open("//storage/emulated/0/Android/data/" .. pkg .. "/", "r")
        if f then f:close() packageName = pkg break end
    end
end

if not packageName then
    packageName = "com.tencent.ig"
end

gameRegion = SUPPORTED_PACKAGES[packageName] or "Unknown"
print("[RJ MOD] Package: " .. packageName .. " (" .. gameRegion .. ")")

-- ====================================================================
-- UNIVERSAL PATHS
-- ====================================================================
local PATHS = {
    PubgData     = "//storage/emulated/0/Android/data/" .. packageName .. "/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/",
    Paks         = nil,
    SaveGames    = nil,
    Cache        = nil,
    DataCache    = nil,  -- [CACHE-PATH] game's own Android/data/<pkg>/cache/ folder
}
PATHS.Paks      = PATHS.PubgData .. "Paks/"
PATHS.SaveGames = PATHS.PubgData .. "SaveGames/"
PATHS.Cache     = PATHS.PubgData .. "image_download_mgr/temporary/Daliy/imgdownload_20713/"
-- [CACHE-PATH] Direct Android cache folder — auto-correct per game version
-- Global  → /Android/data/com.tencent.ig/cache/
-- BGMI    → /Android/data/com.pubg.imobile/cache/
-- KR      → /Android/data/com.pubg.krmobile/cache/
-- VN      → /Android/data/com.vng.pubgmobile/cache/
-- TW      → /Android/data/com.rekoo.pubgm/cache/
-- CN      → /Android/data/com.tencent.tmgp.pubgmhd/cache/
PATHS.DataCache = "//storage/emulated/0/Android/data/" .. packageName .. "/cache/"

-- ====================================================================
-- BRPlayerCharacterBase declaration
-- ====================================================================
local BRPlayerCharacterBase = { ServerRPC = {}, ClientRPC = {}, MulticastRPC = {} }
BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue = { Reliable = true, Params = {} }
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox = { Reliable = true, Params = { UEnums.EPropertyClass.Object } }
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall = { Reliable = true, Params = { UEnums.EPropertyClass.Bool } }
BRPlayerCharacterBase.ClientRPC.ClientRPC_TriggerHighlightMoment = { Reliable = true, Params = { UEnums.EPropertyClass.UInt32, UEnums.EPropertyClass.UInt32 } }

local ENetRole = import("ENetRole")
local EPawnState = import("EPawnState")

local GameplayData = nil
pcall(function() GameplayData = require("GameLua.GameCore.Data.GameplayData") end)

local GamePlayTools = nil
pcall(function() GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools") end)

-- ====================================================================
-- UNIVERSAL SAFE HELPERS
-- ====================================================================
local function safeRequire(...)
    local ok, result = pcall(require, ...)
    if ok and result then return result end
    return nil
end

local function safeImport(name)
    local ok, result = pcall(import, name)
    if ok and result then return result end
    return nil
end

-- ====================================================================
-- [32BIT-FIX]
-- ====================================================================
local IS_32BIT = false
pcall(function()
    if jit and jit.arch then
        IS_32BIT = (jit.arch == "x86" or jit.arch == "arm")
    else
        local probe = collectgarbage("count")
        IS_32BIT = (probe > 0 and tostring(2^31) ~= "2147483648")
    end
end)

-- [LAG FIX] Cache time_ticker so every tick loop doesn't pcall(require) each fire
local _ticker_cache = nil
local function GetTicker()
    if _ticker_cache then return _ticker_cache end
    local ok, tk = pcall(require, "common.time_ticker")
    if ok and tk then _ticker_cache = tk end
    return _ticker_cache
end

local LIMITS = {
    MAX_BOT_CACHE       = IS_32BIT and 200 or 800,
    MAX_VIS_CACHE       = IS_32BIT and 60  or 200,
    MAX_MID_CACHE       = IS_32BIT and 120 or 500,
    MAX_ENEMY_MARKS     = IS_32BIT and 40  or 100,
    MAX_TRACKED_MARKS   = IS_32BIT and 80  or 250,
    ESP_MAX_DISTANCE    = IS_32BIT and 250 or 400,
    BONE_ESP_MAX_DIST   = IS_32BIT and 100 or 250,
    AIMBOT_TICK         = IS_32BIT and 0.055 or 0.040,
    MAIN_TICK           = IS_32BIT and 1.00  or 0.85,  -- [LAG FIX] less main-loop pressure mid-match
    CONFIG_SAVE_INTERVAL= IS_32BIT and 20    or 15,
    AUTO_HEAD_DEFAULT   = not IS_32BIT,
    ESP6_DEFAULT        = not IS_32BIT,
    ESPVIPPRO_DEFAULT   = not IS_32BIT,
    MAX_ESP_LINES       = IS_32BIT and 12  or 28,
    ESP_LINE_UPDATE     = IS_32BIT and 0.08  or 0.06,  -- [LAG FIX] reduce line redraw hitch
    ESP_LINE_THICKNESS  = 0.8,
    ESP_LINE_MAX_DIST   = IS_32BIT and 300 or 600,
    ESP_LINE_SMOOTH     = 0.35,
    VIS_CACHE_TIME      = 0.15,
}

-- ====================================================================
-- ONLINE LICENSE AUTHENTICATION
-- Uses the existing LOGIN.lua / Supabase verification flow.
-- The previous local device/key/master/banned-file authentication is removed.
-- ====================================================================
local isExpired = true
_G._LICENSE_OK = _G._LICENSE_OK == true and true or false
if _G._LICENSE_OK then isExpired = false end

-- Single gate used by every ticker / feature apply path.
-- After online login succeeds, _LICENSE_OK stays true and features stay unlocked.
local function IsFeatureLocked()
    if _G._LICENSE_OK == true then
        isExpired = false
        _G._MOD_EXPIRED = false
        return false
    end
    return isExpired == true
end
_G.IsFeatureLocked = IsFeatureLocked

local LoginSystem = (function()

    local Config = {
          LICENSE_URL  = "https://oxslghxcdxhcniulfjws.supabase.co/functions/v1/verify-license",
        LOGIN_URL    = "https://oxslghxcdxhcniulfjws.supabase.co/functions/v1/verify-license",
        GAME_NAME    = "pubg",
        KEY_FILE     = "//storage/emulated/0/Android/data/" .. tostring(packageName or "com.tencent.ig") .. "/files/keys.txt",
        UID_FILE     = "//storage/emulated/0/Android/data/" .. tostring(packageName or "com.tencent.ig") .. "/files/uid.txt",
        BRAND_NAME   = "MAGOO",
        BRAND_SUB    = "PUBLIC ACCESS",
        SUPPORT_TEXT = "Get Key / Support : MAGOO",
        TELEGRAM_URL = "YOUR_TELEGRAM_SUPPORT_URL_HERE",
        DEBUG        = false,
    }

    local function getDeviceId()
        local id = nil
        pcall(function()
            if Client and Client.GetPhoneDeviceID then
                id = Client.GetPhoneDeviceID()
            end
        end)
        pcall(function()
            if not id or id == "" then
                local ksl = import("KismetSystemLibrary")
                if ksl then
                    if ksl.GetDeviceId then id = ksl.GetDeviceId() end
                    if (not id or id == "") and ksl.GetDeviceIdOS then
                        id = ksl.GetDeviceIdOS()
                    end
                end
            end
        end)
        if not id or id == "" then return nil end
        return id
    end

    local function getPlayerUid()
        local uid = nil
        pcall(function()
            local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
            if pc then
                if pc.UID then uid = tostring(pc.UID) end
                if (not uid or uid == "" or uid == "0")
                   and pc.PlayerState and pc.PlayerState.UID then
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
            if uid then uid = uid:gsub("%s+", "") end
            if not uid or uid == "" then
                uid = "ZN-" .. tostring(math.random(100000, 999999)) .. tostring(os.time())
                local w = io.open(Config.UID_FILE, "w")
                if w then w:write(uid); w:close() end
            end
            if uid == "" then uid = nil end
        end)
        return uid
    end

    local function getSerial()
        return getDeviceId() or getPlayerUid() or getFileUid()
    end

    local function readKeyFile()
        local key = nil
        pcall(function()
            local f = io.open(Config.KEY_FILE, "r")
            if f then
                local raw = f:read("*all") or ""
                f:close()
                -- support multi-line: line1=key, line2=expiry
                local first = raw:match("^([^\r\n]+)") or raw
                key = first and first:gsub("%s+", "") or nil
                local exp = raw:match("\n([^\r\n]+)")
                if exp and exp:gsub("%s+", "") ~= "" then
                    _G._LICENSE_EXPIRY = exp:gsub("%s+", "")
                end
            end
            if key == "" then key = nil end
        end)
        if not _G._LICENSE_EXPIRY then
            pcall(function()
                local ef = io.open("//storage/emulated/0/Android/data/" .. tostring(packageName or "com.tencent.ig") .. "/files/key_expiry.txt", "r")
                if ef then
                    local e = ef:read("*all"); ef:close()
                    if e then _G._LICENSE_EXPIRY = e:gsub("%s+", "") end
                end
            end)
        end
        return key
    end

    local function saveKey(key, expiry)
        _G._LICENSE_KEY = key
        if expiry and expiry ~= "" then
            _G._LICENSE_EXPIRY = tostring(expiry)
        end
        pcall(function()
            local f = io.open(Config.KEY_FILE, "w")
            if f then
                local line = tostring(key or "")
                if _G._LICENSE_EXPIRY and _G._LICENSE_EXPIRY ~= "" then
                    line = line .. "\n" .. tostring(_G._LICENSE_EXPIRY)
                end
                f:write(line)
                f:close()
            end
        end)
        -- also keep a dedicated expiry file for robustness
        pcall(function()
            if _G._LICENSE_EXPIRY and _G._LICENSE_EXPIRY ~= "" then
                local ef = io.open("//storage/emulated/0/Android/data/" .. tostring(packageName or "com.tencent.ig") .. "/files/key_expiry.txt", "w")
                if ef then ef:write(tostring(_G._LICENSE_EXPIRY)); ef:close() end
            end
        end)
    end

    local function getCurrentKey()
        if _G._LICENSE_KEY and _G._LICENSE_KEY ~= "" then
            return _G._LICENSE_KEY
        end
        return readKeyFile()
    end

    local function normalizeError(raw)
        local v = tostring(raw or ""):lower()
        if v == "invalid_key" or v == "invalid" or v == "key_not_found" then return "invalid" end
        if v == "revoked" or v == "blocked" or v == "key_revoked" then return "blocked" end
        if v == "expired" or v == "key_expired" then return "expired" end
        if v == "device_limit_reached" or v == "device_limit" then return "device_limit" end
        if v == "missing_key" or v == "missing_device_id" then return "missing" end
        return "nonet"
    end

    local function esc(s)
        return (tostring(s or "")
            :gsub("\\", "\\\\")
            :gsub('"', '\\"')
            :gsub("\r", "\\r")
            :gsub("\n", "\\n"))
    end

    local function checkLicense(key, uid, callback)
        local http = nil
        pcall(function()
            http = ModuleManager.GetModule(ModuleManager.CommonModuleConfig.http_manager)
        end)

        if not (http and http.Post) then
            callback(false, "nonet", nil)
            return
        end

        if not key or key == "" or not uid or uid == "" then
            callback(false, "missing", nil)
            return
        end

        local headers = {
            ["Content-Type"] = "application/json",
            ["Accept"]       = "application/json",
        }

        local body = '{"key":"' .. esc(key) .. '","device_id":"' .. esc(uid) .. '"}'

        http:Post(Config.LOGIN_URL, headers, body, nil,
            function(ok, response, status, err)
                local code = tonumber(status) or 0
                local resp = response and tostring(response) or ""
                local errt = err and tostring(err) or ""

                if ok then
                    if resp == "" then
                        callback(false, "net:empty server response", nil)
                        return
                    end

                    if resp:find('"ok"%s*:%s*true')
                    or resp:find('"valid"%s*:%s*true')
                    or resp:find('"success"%s*:%s*true') then

                        local exp = resp:match('"expires_at"%s*:%s*"([^"]+)"')
                                 or resp:match('"expiry"%s*:%s*"([^"]+)"')
                                 or resp:match('"expires"%s*:%s*"([^"]+)"')

                        callback(true, nil, exp)
                        return
                    end

                    local e = resp:match('"error"%s*:%s*"([^"]+)"')
                           or resp:match('"code"%s*:%s*"([^"]+)"')
                           or resp:match('"reason"%s*:%s*"([^"]+)"')
                           or resp:match('"message"%s*:%s*"([^"]+)"')

                    callback(false, normalizeError(e), nil)
                    return
                end

                local msg = errt
                if msg == "" and code > 0 then
                    msg = "HTTP " .. tostring(code)
                end
                callback(false, "net:" .. msg, nil)
            end)
    end

    local function showMsg(title, body)
        pcall(function()
            local box = require("client.slua.logic.common.logic_common_msg_box")
            if box and box.Show then box.Show(4, title, body) end
        end)
    end

    local function explainError(code, expiry)
        if code == "invalid" then
            showMsg("INVALID KEY", "Your key is not valid.")
        elseif code == "blocked" then
            showMsg("KEY BLOCKED", "This key has been blocked.")
        elseif code == "expired" then
            local e = expiry and ("\n\nExpiry: " .. expiry) or ""
            showMsg("KEY EXPIRED", "This key has expired." .. e)
        elseif code == "device_limit" then
            showMsg("DEVICE LIMIT", "This key is locked to another device.")
        elseif code == "missing" then
            showMsg("KEY ERROR", "Key or device ID missing.")
        else
            showMsg("CONNECTION ERROR", "Could not reach the license server.")
        end
    end

    local function openTelegram()
        pcall(function()
            local ksl = import("KismetSystemLibrary")
            if ksl and ksl.LaunchURL then ksl.LaunchURL(Config.TELEGRAM_URL) end
        end)
    end

    local M = {}

    -- =====================================================
-- UI HELPERS
-- =====================================================
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
            if not (canvas and slua.isValid(canvas)) then
                canvas = ui.CanvasPanel_42
            end
        end
    end)
    return canvas
end

local function addText(parent, text, size, color, x, y)
    local tb = CGame:NewObjectFromPath("/Script/UMG.TextBlock", parent)
    if not (tb and slua.isValid(tb)) then return nil end
    pcall(function()
        tb:SetText(tostring(text))
        local SlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")
        if SlateColor then
            tb:SetColorAndOpacity(SlateColor(color))
        else
            tb:SetColorAndOpacity(color)
        end
        if tb.Font then
            local f = tb.Font
            f.Size = size
            -- Prefer a bold typeface when the runtime exposes Typeface.
            -- Falls back silently to the existing font if unsupported.
            pcall(function() f.Typeface = "Bold" end)
            tb.Font = f
        end
        tb:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    end)
    local slot = parent:AddChildToCanvas(tb)
    if slot then
        pcall(function()
            slot:SetAutoSize(true)
            slot:SetAlignment(mkVec2(0.5, 0.5))
            slot:SetPosition(mkVec2(x, y))
            slot:SetZOrder(9999)
        end)
    end
    return tb
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

    local txt = CGame:NewObjectFromPath("/Script/UMG.TextBlock", btn)
    if txt and slua.isValid(txt) then
        pcall(function()
            txt:SetText(label)
            local LC = import("LinearColor")
            local SC = import("SlateColor") or import("/Script/SlateCore.SlateColor")
            local lin = LC(r, g, b, 1)
            if SC then
                txt:SetColorAndOpacity(SC(lin))
            else
                txt:SetColorAndOpacity(lin)
            end
            if txt.Font then
                local f = txt.Font
                f.Size = 24
                txt.Font = f
            end
            txt:SetWidgetVisibility(UEnums.ESlateVisibility.HitTestInvisible)
            pcall(function() btn:AddChild(txt) end)
        end)
    end

    pcall(function()
        if btn.OnClicked and btn.OnClicked.Add then
            btn.OnClicked:Add(function() onClick() end)
        end
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
        if box.SetHintText then box:SetHintText("Enter your key here") end
        if box.SetKeyboardFocus then box:SetKeyboardFocus() end
    end)
    return box
end

local function getInputText(box)
    if not (box and slua.isValid(box) and box.GetText) then return nil end
    local txt = nil
    pcall(function()
        local t = box:GetText()
        if type(t) == "string" then
            txt = t
        elseif t and t.ToString then
            txt = t:ToString()
        else
            txt = tostring(t)
        end
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
            local lin
            if isError then
                lin = LC(1.0, 0.28, 0.28, 1.0)
            else
                lin = LC(0.10, 0.45, 0.20, 1.0) -- dark phosphor
            end
            if SC then
                _G._LOGIN_STATUS:SetColorAndOpacity(SC(lin))
            else
                _G._LOGIN_STATUS:SetColorAndOpacity(lin)
            end
        end
    end)
end

local function openTelegram()
    pcall(function()
        local ksl = import("KismetSystemLibrary")
        if ksl and ksl.LaunchURL then
            ksl.LaunchURL(Config.TELEGRAM_URL)
        end
    end)
end

local function destroyLoginUI()
    pcall(function()
        if _G._LOGIN_UI and slua.isValid(_G._LOGIN_UI) then
            _G._LOGIN_UI:RemoveFromParent()
            if _G._LOGIN_UI.ConditionalBeginDestroy then
                _G._LOGIN_UI:ConditionalBeginDestroy()
            end
        end
    end)
    _G._LOGIN_UI = nil
    _G._LOGIN_BOX = nil
    _G._LOGIN_BTN = nil
    _G._GETKEY_BTN = nil
    _G._LOGIN_STATUS = nil
    _G._LOGIN_TRYING = false
end

-- =====================================================
-- BUILD LOGIN UI — GHOST TERMINAL
-- Void black / phosphor green / white · classified access
-- =====================================================
M.Build = function(pawn, hint, onSuccess)
    destroyLoginUI()
    local built = false

    pcall(function()
        local canvas = getCanvas()
        if not canvas then return end

        local LC = import("LinearColor")
        local SC = import("SlateColor") or import("/Script/SlateCore.SlateColor")
        local vw, vh = 1920, 1080

        pcall(function()
            local uu = require("client.common.ui_util")
            if uu and uu.GetViewportSize then
                local sz = uu.GetViewportSize()
                if sz and sz.X and sz.X > 0 then
                    vw = sz.X
                    vh = sz.Y
                end
            end
        end)

        -- Shifted slightly left + up so it reads true center; larger card
        local cx, cy = vw * 0.47, vh * 0.42
        local panelW = math.min(vw * 0.50, 620)
        local panelH = math.min(vh * 0.56, 460)
        panelW = math.max(panelW, 500)
        panelH = math.max(panelH, 380)
        local scale = math.max(0.85, math.min(panelW / 560, panelH / 400))

        -- Extremely dark terminal palette (deep green + muted white)
        local VOID       = LC(0.01, 0.01, 0.012, 0.94)
        local PANEL      = LC(0.025, 0.03, 0.035, 0.99)
        local PANEL_IN   = LC(0.035, 0.04, 0.045, 1.00)
        local EDGE       = LC(0.04, 0.14, 0.07, 0.90)   -- very dark green rim
        local GREEN      = LC(0.08, 0.42, 0.18, 1.00)   -- dark phosphor
        local GREEN_DIM  = LC(0.05, 0.22, 0.10, 1.00)
        local GREEN_BTN  = LC(0.04, 0.28, 0.12, 1.00)
        local WHITE      = LC(0.72, 0.74, 0.76, 1.00)   -- muted / dark white
        local WHITE_DIM  = LC(0.48, 0.50, 0.52, 1.00)
        local GREY       = LC(0.28, 0.30, 0.32, 1.00)
        local ERR        = LC(0.75, 0.18, 0.18, 1.00)
        local CLEAR      = LC(0, 0, 0, 0)

        local root = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", canvas)
        if not (root and slua.isValid(root)) then return end
        local rootSlot = canvas:AddChildToCanvas(root)
        if rootSlot then
            pcall(function()
                rootSlot:SetPosition(mkVec2(0, 0))
                rootSlot:SetSize(mkVec2(vw, vh))
                rootSlot:SetZOrder(9989)
            end)
        end

        -- Soft full-screen dim (not pure black block)
        addBorder(root, VOID, cx, cy, vw, vh, 9989)

        -- Outer hairline rim
        addBorder(root, EDGE, cx, cy, panelW + 2, panelH + 2, 9990)
        -- Main panel
        addBorder(root, PANEL, cx, cy, panelW, panelH, 9991)

        -- Corner ticks (terminal bezel, not fat glow stacks)
        local tw, th = 18 * scale, 2 * scale
        local hw, hh = panelW * 0.5, panelH * 0.5
        local corners = {
            {cx - hw + 10, cy - hh + 2}, {cx + hw - 10, cy - hh + 2},
            {cx - hw + 10, cy + hh - 2}, {cx + hw - 10, cy + hh - 2},
        }
        for _, p in ipairs(corners) do
            addBorder(root, GREEN_DIM, p[1], p[2], tw, th, 9998)
        end
        local ticksV = {
            {cx - hw + 2, cy - hh + 12}, {cx + hw - 2, cy - hh + 12},
            {cx - hw + 2, cy + hh - 12}, {cx + hw - 2, cy + hh - 12},
        }
        for _, p in ipairs(ticksV) do
            addBorder(root, GREEN_DIM, p[1], p[2], th, tw, 9998)
        end

        -- Header
        addText(root, "MAGOO CORE", math.floor(11 * scale), GREY, cx, cy - panelH * 0.40)
        addText(root, "SECURE ACCESS", math.floor(20 * scale), WHITE, cx, cy - panelH * 0.30)
        addBorder(root, GREEN_DIM, cx, cy - panelH * 0.22, panelW * 0.22, 2 * scale, 9997)

        -- Prompt line
        local prompt = "ACCESS KEY"
        if hint and tostring(hint):find("EXPIRED") then
            prompt = "KEY EXPIRED — ENTER NEW KEY"
        elseif hint and tostring(hint):find("Invalid") then
            prompt = "INVALID KEY — TRY AGAIN"
        elseif hint and tostring(hint):find("blocked") then
            prompt = "KEY BLOCKED — ENTER NEW KEY"
        end
        addText(root, prompt, math.floor(12 * scale), GREEN, cx, cy - panelH * 0.12)

        -- Input well
        local inputW = panelW * 0.78
        local inputH = 48 * scale
        local inputY = cy + panelH * 0.02
        addBorder(root, EDGE, cx, inputY, inputW + 2, inputH + 2, 9996)
        addBorder(root, PANEL_IN, cx, inputY, inputW, inputH, 9997)

        _G._LOGIN_BOX = addInput(root, cx, inputY, inputW - 16 * scale, inputH - 8 * scale)
        pcall(function()
            if _G._LOGIN_BOX and _G._LOGIN_BOX.SetHintText then
                _G._LOGIN_BOX:SetHintText("Enter license key")
            end
            if _G._LOGIN_BOX and _G._LOGIN_BOX.SetKeyboardFocus then
                _G._LOGIN_BOX:SetKeyboardFocus()
            end
        end)

        -- Status / log line
        local statusSeed = "> awaiting key input_"
        if hint and hint ~= "" and not tostring(hint):find("Enter your key") then
            statusSeed = "> " .. tostring(hint)
        end
        _G._LOGIN_STATUS = addText(root, statusSeed, math.floor(12 * scale), GREEN_DIM,
            cx, cy + panelH * 0.16)

        -- Buttons
        local btnW = inputW * 0.48
        local btnH = 44 * scale
        local btnY = cy + panelH * 0.30

        -- GET KEY (outline style)
        addBorder(root, EDGE, cx - inputW * 0.26, btnY, btnW + 2, btnH + 2, 9996)
        addBorder(root, PANEL_IN, cx - inputW * 0.26, btnY, btnW, btnH, 9997)

        -- AUTHENTICATE (phosphor fill)
        addBorder(root, GREEN, cx + inputW * 0.26, btnY, btnW + 2, btnH + 2, 9996)
        addBorder(root, GREEN_BTN, cx + inputW * 0.26, btnY, btnW, btnH, 9997)

        local function closeWithAuthAnim(exp, key, uid, onSuccess)
            -- Closing sequence: status → brief hold → destroy → verified popup → runtime
            setStatus("> AUTH OK · SESSION LIVE", false)
            pcall(function()
                if _G._LOGIN_STATUS and slua.isValid(_G._LOGIN_STATUS) then
                    -- flash white then green for success beat
                    local LC2 = import("LinearColor")
                    local SC2 = import("SlateColor") or import("/Script/SlateCore.SlateColor")
                    local white = LC2(0.95, 0.97, 1.0, 1.0)
                    if SC2 then
                        _G._LOGIN_STATUS:SetColorAndOpacity(SC2(white))
                    end
                end
            end)

            local function finish()
                destroyLoginUI()
                pcall(function()
                    local body = "Your key is valid."
                    local e = exp or _G._LICENSE_EXPIRY
                    if e and e ~= "" then
                        body = "Your key is valid.\nExpires: " .. tostring(e)
                    end
                    showMsg("KEY VERIFIED", body)
                end)
                pcall(function()
                    if type(_G.StartAuthenticatedRuntime) == "function" then
                        _G.StartAuthenticatedRuntime()
                    end
                end)
                if onSuccess then onSuccess() end
            end

            local delayed = false
            pcall(function()
                local tk = GetTicker and GetTicker() or nil
                if not tk then
                    local ok, t = pcall(require, "common.time_ticker")
                    if ok then tk = t end
                end
                if tk and tk.AddTimerOnce then
                    delayed = true
                    tk.AddTimerOnce(0.20, function()
                        setStatus("> AUTH OK · SESSION LIVE", false)
                    end)
                    -- close fade on root
                    local fades = {0.75, 0.50, 0.28, 0.10, 0.0}
                    for i, op in ipairs(fades) do
                        local o = op
                        tk.AddTimerOnce(0.35 + 0.08 * i, function()
                            pcall(function()
                                local r = _G._LOGIN_UI
                                if r and slua.isValid(r) and r.SetRenderOpacity then
                                    r:SetRenderOpacity(o)
                                end
                            end)
                        end)
                    end
                    tk.AddTimerOnce(0.95, finish)
                end
            end)
            if not delayed then finish() end
        end

        local function doLogin()
            local key = getInputText(_G._LOGIN_BOX)
            if not key or #key < 4 then
                setStatus("> error: enter a valid key", true)
                return
            end
            if _G._LOGIN_TRYING then return end
            _G._LOGIN_TRYING = true

            setStatus("> verifying credentials...", false)
            local uid = getSerial()

            checkLicense(key, uid, function(ok, err, exp)
                _G._LOGIN_TRYING = false
                if ok then
                    saveKey(key, exp)
                    _G._LICENSE_OK  = true
                    _G._LICENSE_KEY = key
                    _G._LICENSE_UID = uid
                    isExpired = false
                    _G._MOD_EXPIRED = false
                    if exp and exp ~= "" then _G._LICENSE_EXPIRY = tostring(exp) end
                    closeWithAuthAnim(exp, key, uid, onSuccess)
                elseif err == "invalid" then
                    setStatus("> error: invalid key", true)
                elseif err == "blocked" then
                    setStatus("> error: key blocked", true)
                elseif err == "expired" then
                    setStatus("> error: key expired — enter new key", true)
                elseif err == "device_limit" then
                    setStatus("> error: device limit reached", true)
                elseif type(err) == "string" and err:sub(1, 4) == "net:" then
                    local detail = err:sub(5)
                    if #detail > 40 then detail = detail:sub(1, 40) .. "..." end
                    setStatus("> error: " .. detail, true)
                else
                    setStatus("> error: connection failed — retry", true)
                end
            end)
        end

        _G._GETKEY_BTN = addButton(
            root,
            cx - inputW * 0.26,
            btnY,
            btnW,
            btnH,
            "GET KEY",
            0.75, 0.90, 0.80,
            function()
                setStatus("> opening support channel...", false)
                openTelegram()
            end
        )

        _G._LOGIN_BTN = addButton(
            root,
            cx + inputW * 0.26,
            btnY,
            btnW,
            btnH,
            "AUTHENTICATE",
            0.95, 1.00, 0.95,
            doLogin
        )

        -- Footer
        addText(root, "ENCRYPTED SESSION  ·  " .. tostring(Config.BRAND_NAME or "MAGOO"),
            math.floor(10 * scale), GREY, cx, cy + panelH * 0.42)

        _G._LOGIN_UI = root
        -- Open fade: start invisible, ramp opacity on root
        pcall(function()
            if root.SetRenderOpacity then root:SetRenderOpacity(0.0) end
            local tk = nil
            pcall(function()
                if GetTicker then tk = GetTicker() end
                if not tk then
                    local ok, t = pcall(require, "common.time_ticker")
                    if ok then tk = t end
                end
            end)
            if tk and tk.AddTimerOnce then
                local steps = {0.25, 0.45, 0.65, 0.85, 1.0}
                for i, op in ipairs(steps) do
                    local o = op
                    tk.AddTimerOnce(0.05 * i, function()
                        pcall(function()
                            if root and slua.isValid(root) and root.SetRenderOpacity then
                                root:SetRenderOpacity(o)
                            end
                        end)
                    end)
                end
            else
                if root.SetRenderOpacity then root:SetRenderOpacity(1.0) end
            end
        end)
        built = true
    end)

    return built
end

M.Start = function(pawn, onSuccess)
    -- Already licensed this process → never re-prompt
    if _G._LICENSE_OK == true then
        pcall(function()
            if type(_G.StartAuthenticatedRuntime) == "function" then
                _G.StartAuthenticatedRuntime()
            end
        end)
        if onSuccess then onSuccess() end
        return
    end

    local function unlockWithKey(key, exp)
        saveKey(key, exp)
        _G._LICENSE_OK  = true
        _G._LICENSE_KEY = key
        _G._LICENSE_UID = getSerial()
        isExpired = false
        _G._MOD_EXPIRED = false
        if exp and exp ~= "" then _G._LICENSE_EXPIRY = tostring(exp) end
        pcall(function()
            if type(_G.StartAuthenticatedRuntime) == "function" then
                _G.StartAuthenticatedRuntime()
            end
        end)
        if onSuccess then onSuccess() end
    end

    local function showLogin(hint)
        if not M.Build(pawn, hint or "Enter your key", onSuccess) then
            -- last-resort: still try to unlock runtime so menu/features are not dead
            showMsg("KEY ERROR", "Login screen failed to open.")
        end
    end

    local savedKey = getCurrentKey()

    if savedKey and savedKey ~= "" then
        local uid = getSerial() or "unknown"
        local answered = false

        -- Timeout: if server never replies, unlock offline with saved key so
        -- menu + features still appear (never leave user on a blank screen).
        pcall(function()
            local tk = GetTicker and GetTicker() or nil
            if not tk then
                local ok, t = pcall(require, "common.time_ticker")
                if ok then tk = t end
            end
            if tk and tk.AddTimerOnce then
                tk.AddTimerOnce(3.5, function()
                    if answered then return end
                    if _G._LICENSE_OK == true then return end
                    answered = true
                    unlockWithKey(savedKey, _G._LICENSE_EXPIRY)
                end)
            end
        end)

        checkLicense(savedKey, uid, function(ok, err, exp)
            if answered or _G._LICENSE_OK == true then return end
            answered = true
            if ok then
                unlockWithKey(savedKey, exp)
                return
            end
            -- soft network failure → offline unlock, no popup spam
            if type(err) == "string" and (err == "nonet" or err:sub(1,4) == "net:" or err == "missing") then
                unlockWithKey(savedKey, _G._LICENSE_EXPIRY)
                return
            end
            -- hard fail → show login with clear reason
            local hint = "Enter your key"
            if err == "expired" then
                hint = "KEY EXPIRED - enter new key"
            elseif err == "invalid" then
                hint = "Invalid key - enter a valid key"
            elseif err == "blocked" then
                hint = "Key blocked - enter a new key"
            elseif err == "device_limit" then
                hint = "Device limit - enter key for this device"
            else
                hint = "Key check failed - enter key"
            end
            showLogin(hint)
        end)
    else
        -- No saved key → always show login UI
        showLogin("Enter your key")
    end
end

    M.StartPeriodicCheck = function(pawn)
    if _G._LOGIN_TIMER then return _G._LOGIN_TIMER end
    local timer = nil
    pcall(function()
        local function tick()
            if not slua.isValid(pawn.Object) then return end
            if not _G._LICENSE_OK then return end

            local key = getCurrentKey()
            local uid = _G._LICENSE_UID or getSerial()
            if not (key and uid) then return end

            checkLicense(key, uid, function(ok, err)
                if ok then return end
                -- ignore pure network failures — do not kick or re-prompt
                if err == "nonet" or (type(err) == "string" and err:sub(1,4) == "net:") then
                    return
                end
                _G._LICENSE_OK = false
                pcall(function()
                    if _G.LoginSystem_OnRevoked then
                        _G.LoginSystem_OnRevoked(err)
                    end
                end)
                local title = "LICENSE REVOKED"
                local hint = "License revoked - re-enter key"
                if err == "expired" then
                    title = "KEY EXPIRED"
                    hint = "KEY EXPIRED - enter new key"
                elseif err == "invalid" then
                    title = "INVALID KEY"
                    hint = "Invalid key - enter a valid key"
                end
                showMsg(title, "Your key is no longer valid.")
                pcall(function()
                    if M.Build then
                        M.Build(pawn, hint, nil)
                    end
                end)
            end)
        end
        timer = pawn:AddGameTimer(180, true, tick)
    end)
    _G._LOGIN_TIMER = timer
    _G._LOGIN_CHAR  = pawn
    return timer
end

    M.CheckLicense  = checkLicense
    M.GetSerial     = getSerial
    M.GetCurrentKey = getCurrentKey
    M.SaveKey       = saveKey
    M.Config        = Config
    M.IsLoggedIn    = function() return _G._LICENSE_OK == true end

    return M
end)()

_G.LoginSystem = LoginSystem

function _G.LoginSystem_OnRevoked(errCode)
    _G._LICENSE_OK  = false
    _G._MOD_EXPIRED = true
    isExpired = true
    _G._MAGOO_RUNTIME_STARTED = false
    pcall(function()
        if _G._LOGIN_TIMER and _G._LOGIN_CHAR and slua.isValid(_G._LOGIN_CHAR) and _G._LOGIN_CHAR.RemoveGameTimer then
            _G._LOGIN_CHAR:RemoveGameTimer(_G._LOGIN_TIMER)
        end
    end)
    _G._LOGIN_TIMER = nil
    _G._LOGIN_CHAR = nil
    pcall(function()
        if _G.PlayerMapMarker and _G.PlayerMapMarker.bActive then
            _G.PlayerMapMarker.Stop()
        end
    end)
    pcall(function() if _G.StopEnemyCounter then _G.StopEnemyCounter() end end)
    pcall(function() if _G._GK_FeedbackStarted then _G._GK_FeedbackStarted = false end end)
end


-- ====================================================================
-- POST-LOGIN POPUPS
-- 1) Rules — large body, ONE-TIME (persisted to magoo_rules_ack.txt)
-- 2) Key verified — once per game process/session (not every match)
-- Features never wait on these popups.
-- ====================================================================
local function ShowMagooVerifiedPopup()
    if _G._MAGOO_VERIFIED_SHOWN then return end
    _G._MAGOO_VERIFIED_SHOWN = true
    pcall(function()
        local Msg = require("client.slua.logic.common.logic_common_msg_box")
        if not Msg or not Msg.Show then return end
        local body = table.concat({
            "",
            "══════════════════════════════════════",
            "     KEY VERIFIED — ACCESS GRANTED",
            "══════════════════════════════════════",
            "",
            "  Everything is ready. Play safely.",
            "  Follow the rules at all times.",
            "",
            "  Original owner :  @THE_MAGOO",
            "",
            "  Stay natural. Stay undetected.",
            "  Enjoy the game.",
            "",
            "══════════════════════════════════════",
            "",
        }, "\n")
        -- type 4 = standard large dialog in this client
        Msg.Show(4, "MAGOO CORE — VERIFIED", body, function() end, nil, "  PLAY  ")
    end)
end

local function ShowRulesOnce(onDone)
    -- Never block runtime
    if onDone then pcall(onDone) end

    local function afterRules()
        -- session popup after rules (or immediately if rules already acked)
        pcall(ShowMagooVerifiedPopup)
    end

    if _G._MAGOO_RULES_SHOWN then
        afterRules()
        return
    end

    local rulesAckPath = PATHS and PATHS.PubgData and (PATHS.PubgData .. "magoo_rules_ack.txt")
        or ("//storage/emulated/0/Android/data/" .. tostring(packageName or "com.tencent.ig") .. "/files/magoo_rules_ack.txt")
    local alreadyAcked = false
    pcall(function()
        local f = io.open(rulesAckPath, "r")
        if f then
            local v = f:read("*a") or ""
            f:close()
            alreadyAcked = v:match("^%s*1%s*$") ~= nil
        end
    end)
    if alreadyAcked then
        _G._MAGOO_RULES_SHOWN = true
        afterRules()
        return
    end

    pcall(function()
        local Msg = require("client.slua.logic.common.logic_common_msg_box")
        if not Msg or not Msg.Show then
            _G._MAGOO_RULES_SHOWN = true
            afterRules()
            return
        end
        -- Large body = large popup. Extra blank lines force a taller dialog.
        local body = table.concat({
            "",
            "════════════════════════════════════════════",
            "          MAGOO CORE — RULES",
            "════════════════════════════════════════════",
            "",
            "  READ CAREFULLY BEFORE YOU PLAY",
            "",
            "────────────────────────────────────────────",
            "  PLAY STYLE",
            "────────────────────────────────────────────",
            "",
            "  • Play SOLO vs SQUAD when possible.",
            "  • Use LESS skills — do not over-aim.",
            "  • Play NATURALLY, like a real pro.",
            "  • Do NOT play like a hacker.",
            "  • Hide your statistics when you can.",
            "  • Avoid obvious tracking / snapping.",
            "  • Take fights fair. Rotate smart.",
            "",
            "────────────────────────────────────────────",
            "  ACCOUNT & SAFETY",
            "────────────────────────────────────────────",
            "",
            "  • Do not share your license key.",
            "  • Keep device / account info private.",
            "  • If key expires or is revoked, re-login.",
            "",
            "────────────────────────────────────────────",
            "  VERSION SAFETY",
            "────────────────────────────────────────────",
            "",
            "  • ALL VERSIONS SAFE",
            "  • GLOBAL SAFE",
            "  • BGMI SAFE",
            "  • KR / VN / TW SAFE",
            "",
            "════════════════════════════════════════════",
            "  By continuing you accept these rules.",
            "  Original owner : @THE_MAGOO",
            "════════════════════════════════════════════",
            "",
            "",
            "",
        }, "\n")
        Msg.Show(4, "MAGOO CORE — RULES & SAFETY", body, function()
            _G._MAGOO_RULES_SHOWN = true
            pcall(function()
                local f = io.open(rulesAckPath, "w")
                if f then f:write("1\n"); f:close() end
            end)
            afterRules()
        end, nil, "  I UNDERSTAND  ")
    end)
end

_G.ShowRulesOnce = ShowRulesOnce
_G.ShowMagooVerifiedPopup = ShowMagooVerifiedPopup

-- ====================================================================
-- PRIVATE MOD MENU: SMALL CROSSHAIR (HackerWeaponFeatures)
-- Ported exactly from private_modmenue.lua — manages RecoilKickADS,
-- GameDeviationFactor, GameDeviationAccuracy on the active weapon entity.
-- Cleans up correctly when toggled off WITHOUT requiring drop/re-equip.
-- ====================================================================
local HackerWeaponFeatures = (function()
local Weapon = {}
Weapon.__index = Weapon
local FIELDS = { 'RecoilKickADS', 'GameDeviationFactor', 'GameDeviationAccuracy' }
local VALUE, INTERVAL = .01, .2
local FIREARMS = {
    m416=true,akm=true,['scar-l']=true,m762=true,aug=true,groza=true,
    qbz=true,mk47=true,g36c=true,['honey badger']=true,famas=true,['asm abakan']=true,
    ace32=true,uzi=true,ump45=true,vector=true,thompson=true,['thompson smg']=true,
    bizon=true,['pp-19 bizon']=true,['pp-19']=true,mp5k=true,p90=true,
    kar98=true,kar98k=true,m24=true,awm=true,sks=true,vss=true,slr=true,mini14=true,
    mk14=true,amr=true,mk12=true,dsr=true,['m1 garand']=true,s686=true,s1897=true,
    s12k=true,dbs=true,ns2000=true,m249=true,dp28=true,['dp-28']=true,mg3=true
}
local function wfinite(v) return type(v)=='number' and v==v and v>-math.huge and v<math.huge end
local function wsame(a,b) return wfinite(a) and wfinite(b) and math.abs(a-b)<.000001 end
local function wread(o,k) if o==nil then return nil end local ok,v=pcall(function() return o[k] end) if ok then return v end end
local function wcall(o,k,...) local fn=wread(o,k) if type(fn)~='function' then return nil end local ok,v=pcall(fn,o,...) if ok then return v end end
function Weapon.new(env)
    return setmetatable({env=env or _G,enabled=false,active=false,disposed=false,
        nextCheck=0,lastTime=nil,pawn=nil,weapon=nil,entry=nil,blockedEntity=nil,
        restoring=false,smallCrosshairAvailable=nil,lastStatus='inactive'},Weapon)
end
function Weapon:_valid(o)
    if o==nil then return false end
    local fn=wread(wread(self.env,'slua'),'isValid')
    if type(fn)=='function' then local ok,v=pcall(fn,o) if ok and v==true then return true end end
    return wcall(wread(self.env,'Game'),'IsValid',o)==true
end
function Weapon:_currentWeapon(pawn)
    for _,key in ipairs({'GetCurrentWeapon','GetCurrentShootWeapon'}) do
        local fn=wread(pawn,key)
        if type(fn)=='function' then local ok,cur=pcall(fn,pawn) if ok then if self:_valid(cur) then return cur end end end
    end
    local mgr=wread(pawn,'WeaponManagerComponent')
    if self:_valid(mgr) then
        local cur=wread(mgr,'CurrentWeapon') if self:_valid(cur) then return cur end
        local rep=wread(mgr,'CurrentWeaponReplicated') if self:_valid(rep) then return rep end
    end
end
function Weapon:_firearm(weapon)
    local name=wcall(weapon,'GetWeaponName')
    if type(name)~='string' then return false end
    return FIREARMS[name:lower():match('^%s*(.-)%s*$')]==true
end
function Weapon:_ownedCount()
    local count=0
    if self.entry then for i=1,3 do if self.entry.owned[FIELDS[i]] then count=count+1 end end end
    return count
end
function Weapon:_restore()
    local entry=self.entry self.active=false
    if not entry then self.restoring=false return true end
    if not self:_valid(entry.entity) then self.entry=nil self.restoring=false return true end
    for i=1,3 do
        local key=FIELDS[i]
        if entry.owned[key] then
            local value=wread(entry.entity,key)
            if wsame(value,VALUE) then
                pcall(function() entry.entity[key]=entry.original[key] end)
                if wsame(wread(entry.entity,key),entry.original[key]) then entry.owned[key]=nil end
            elseif wfinite(value) then entry.owned[key]=nil end
        end
    end
    if self:_ownedCount()==0 then self.entry=nil self.restoring=false return true end
    self.restoring=true return false
end
function Weapon:_stop(reason)
    local restored=self:_restore()
    self.lastStatus=restored and reason or 'restore_pending' return false
end
function Weapon:_block(entity,reason)
    self.blockedEntity,self.blockedReason=entity,reason
    self.smallCrosshairAvailable=false return self:_stop(reason)
end
function Weapon:_isCurrent(pawn,weapon,entity,settings)
    return settings.smallCrosshair==true and self:_valid(pawn) and self:_valid(weapon)
        and self:_valid(entity) and self:_currentWeapon(pawn)==weapon
        and wread(weapon,'ShootWeaponEntityComp')==entity and self:_firearm(weapon)
end
function Weapon:_apply(pawn,weapon,entity,settings)
    local entry={entity=entity,original={},owned={}}
    for i=1,3 do
        local key=FIELDS[i] local value=wread(entity,key)
        if not wfinite(value) then self.smallCrosshairAvailable=false self.lastStatus='source_field_unavailable' return false end
        entry.original[key]=value
    end
    self.entry=entry
    for i=1,3 do
        local key=FIELDS[i]
        if not self:_isCurrent(pawn,weapon,entity,settings) then self.smallCrosshairAvailable=false return self:_stop('context_changed') end
        if not wsame(wread(entity,key),entry.original[key]) then return self:_block(entity,'external_value_changed') end
        if not wsame(entry.original[key],VALUE) then
            entry.owned[key]=true
            local ok=pcall(function() entity[key]=VALUE end)
            if not ok or not wsame(wread(entity,key),VALUE) then return self:_block(entity,'source_write_failed') end
        end
    end
    for i=1,3 do if not wsame(wread(entity,FIELDS[i]),VALUE) then return self:_block(entity,'external_value_changed') end end
    if not self:_isCurrent(pawn,weapon,entity,settings) then self.smallCrosshairAvailable=false return self:_stop('context_changed') end
    self.active=true self.smallCrosshairAvailable=true self.lastStatus='source_values_verified' return true
end
function Weapon:update(pawn,settings,now)
    if self.disposed then return false end
    settings=type(settings)=='table' and settings or {}
    if settings.smallCrosshair~=true then
        self.enabled=false self.blockedEntity=nil self.lastTime=nil self.nextCheck=0 self.pawn,self.weapon=nil,nil
        return self:_stop('inactive')
    end
    if not wfinite(now) or now<0 then self.lastTime=nil self.nextCheck=0 self.weapon=nil return self:_stop('clock_unavailable') end
    if self.lastTime and now<self.lastTime then self.lastTime=now self.nextCheck=0 self.weapon=nil self.blockedEntity=nil return self:_stop('clock_changed') end
    self.lastTime=now
    if pawn~=self.pawn then
        self.pawn=pawn self.weapon=nil self.blockedEntity=nil self.nextCheck=0
        if not self:_restore() then self.nextCheck=now+INTERVAL self.lastStatus='restore_pending' return false end
    end
    if self.enabled and now<self.nextCheck then return self.active end
    self.enabled=true self.nextCheck=now+INTERVAL
    if not self:_valid(pawn) then self.weapon=nil return self:_stop('player_unavailable') end
    local weapon=self:_currentWeapon(pawn)
    if not self:_valid(weapon) or not self:_firearm(weapon) then
        self.weapon=nil self.smallCrosshairAvailable=false return self:_stop('firearm_unavailable')
    end
    local entity=wread(weapon,'ShootWeaponEntityComp')
    if not self:_valid(entity) then self.weapon=nil self.smallCrosshairAvailable=false return self:_stop('shoot_entity_unavailable') end
    if weapon~=self.weapon then self.blockedEntity=nil end
    if self.restoring or (self.entry and self.entry.entity~=entity) then
        if not self:_restore() then self.lastStatus='restore_pending' return false end
    end
    self.weapon=weapon
    if self.blockedEntity==entity then self.active=false self.lastStatus=self.blockedReason return false end
    if self.entry then
        for i=1,3 do
            local value=wread(entity,FIELDS[i])
            if not wsame(value,VALUE) then return self:_block(entity,wfinite(value) and 'external_value_changed' or 'source_field_unavailable') end
        end
        self.active=true self.smallCrosshairAvailable=true self.lastStatus='source_values_verified' return true
    end
    return self:_apply(pawn,weapon,entity,settings)
end
function Weapon:dispose()
    self.disposed=true self.enabled=false self.blockedEntity=nil self.pawn,self.weapon,self.lastTime=nil,nil,nil
    return self:_stop('disposed')
end
return Weapon
end)()

-- Global instances for private mod menu features
_G.PrivWeaponInstance = nil  -- HackerWeaponFeatures instance for small crosshair
_G.PrivAimInstance   = nil   -- HackerAimFeatures instance for force aimbot

-- ====================================================================
-- UTILITIES (defined here so PrivAimbotTick closure can capture them)
-- ====================================================================
local _slua = rawget(_G, "slua")
local function Valid(obj)
    if not obj then return false end
    if _slua and _slua.isValid then
        local ok, v = pcall(_slua.isValid, obj)
        if not ok or not v then return false end
    end
    return true
end

-- [LAG FIX] Cache per-frame imports once so 60fps loops don't safeImport every tick
-- IMPORTANT: These must be defined BEFORE PrivAimbotTick so the closure captures them correctly
local _cached_FV2 = nil
local _cached_KML = nil
local _cached_UGS = nil
local _cached_ui_util = nil
local function GetFV2()     if not _cached_FV2     then _cached_FV2     = safeImport("Vector2D")          end; return _cached_FV2     end
local function GetKML()     if not _cached_KML     then _cached_KML     = safeImport("KismetMathLibrary")  end; return _cached_KML     end
local function GetUGS()     if not _cached_UGS     then _cached_UGS     = safeImport("GameplayStatics")    end; return _cached_UGS     end
local function GetUIUtil()
    if not _cached_ui_util then
        local ok, m = pcall(require, "client.common.ui_util")
        if ok and m then _cached_ui_util = m end
    end
    return _cached_ui_util
end

-- ====================================================================
-- PRIVATE MOD MENU: FORCE AIMBOT ENGINE (fire-only, neck/chest target)
-- Replaces old AimTouch for ForceAimbot feature.
-- Key changes vs private menu: aim locks ON FIRE only, target is
-- spine_03 (neck/chest), force+assistant both active via one toggle.
-- ====================================================================
-- [FIXED] Aimbot kill counter / auto-off system REMOVED.
-- Aimbot now stays ON as long as the user toggle is ON.
-- No auto-disable, no kill limit, no match tracking.

-- Human-like aim variance helpers — makes aimbot look like natural human movement
local _humanAimJitter = { lastApply = 0, phase = 0 }
local function HumanAimDelta(dx, dy, fraction)
    -- Micro-jitter: small random offset that mimics hand tremor
    local now = os.clock()
    local dt = now - _humanAimJitter.lastApply
    _humanAimJitter.lastApply = now
    _humanAimJitter.phase = _humanAimJitter.phase + dt * 7.3 -- ~7Hz tremor

    local jitterAmp = 0.35 -- degrees, mimics hand tremor
    local jx = math.sin(_humanAimJitter.phase * 1.7) * jitterAmp * (0.5 + math.random() * 0.5)
    local jy = math.cos(_humanAimJitter.phase * 2.1) * jitterAmp * (0.5 + math.random() * 0.5)

    -- Slight overshoot-then-correct pattern on large moves (human behavior)
    local dist = math.sqrt(dx*dx + dy*dy)
    local overshoot = 1.0
    if dist > 30 then
        -- Large angle: humans tend to overshoot slightly then correct
        overshoot = 1.0 + (math.random() - 0.5) * 0.12
    end

    return dx * fraction * overshoot + jx,
           dy * fraction * overshoot + jy
end

local function PrivAimbotTick()
    local cfg = _G.GTLMODConfig or {}
    local hipOn = cfg.ForceAimbot == true
    if not hipOn then return end

    local player = nil
    pcall(function() player = GameplayData.GetPlayerCharacter() end)
    if not (player and slua.isValid(player)) then return end

    local pc = nil
    pcall(function() pc = player:GetPlayerControllerSafety() end)
    if not (pc and slua.isValid(pc)) then return end

    -- FORCE AIM (HIP): works in both hipfire and scoped/ADS — no mode split
    -- FIRE-ONLY: aim locks only when actively firing
    local isFiring = false
    pcall(function()
        isFiring = player.bIsWeaponFiring == true
        if not isFiring then
            local wepMgr = player.WeaponManagerComponent
            if slua.isValid(wepMgr) then isFiring = wepMgr.bIsWeaponFiring == true end
        end
    end)
    if not isFiring then return end

    -- Get weapon
    local weapon = nil
    pcall(function()
        local mgr = player.WeaponManagerComponent
        if mgr and slua.isValid(mgr) then weapon = mgr.CurrentWeaponReplicated or mgr.CurrentWeapon end
        if not (weapon and slua.isValid(weapon)) then
            if type(player.GetCurrentShootWeapon) == 'function' then weapon = player:GetCurrentShootWeapon() end
        end
        if not (weapon and slua.isValid(weapon)) then
            if type(player.GetCurrentWeapon) == 'function' then weapon = player:GetCurrentWeapon() end
        end
    end)
    if not (weapon and slua.isValid(weapon)) then return end

    -- Collect enemies (multi-source — match transitions often empty one path)
    local myTeam = -1
    pcall(function() myTeam = player:GetTeamID() or player.TeamID or -1 end)

    local allChars = {}
    local seen = {}
    local function addChar(c)
        if not c or not slua.isValid(c) then return end
        local id = tostring(c)
        if seen[id] then return end
        seen[id] = true
        allChars[#allChars + 1] = c
    end
    pcall(function()
        if GameplayData and GameplayData.GetAllPlayerCharacters then
            local list = GameplayData.GetAllPlayerCharacters()
            if list then
                for _, c in pairs(list) do addChar(c) end
            end
        end
    end)
    pcall(function()
        if GameplayData and GameplayData.GameCharacters then
            for _, c in pairs(GameplayData.GameCharacters) do addChar(c) end
        end
    end)
    pcall(function()
        if Game and Game.GetAllPlayerPawns then
            local list = Game:GetAllPlayerPawns()
            if list then
                for _, c in pairs(list) do addChar(c) end
            end
        end
    end)
    pcall(function()
        if _G.Game and _G.Game.GetAllPlayerPawns then
            local list = _G.Game:GetAllPlayerPawns()
            if list then
                for _, c in pairs(list) do addChar(c) end
            end
        end
    end)

    local KismetMathLibrary = GetKML()
    local UGameplayStatics = GetUGS()
    if not KismetMathLibrary or not UGameplayStatics then return end

    local camManager = UGameplayStatics.GetPlayerCameraManager(pc, 0)
    if not (camManager and slua.isValid(camManager)) then return end
    local camLoc = camManager:GetCameraLocation()
    if not camLoc then return end

    -- [LAG FIX] Use cached ui_util (GetUIUtil already caches it) — stop require() every 16ms
    local ui_util = GetUIUtil and GetUIUtil()
    if not ui_util then
        pcall(function() ui_util = require("client.common.ui_util") end)
    end
    if not ui_util then return end
    local viewportSize = ui_util.GetViewportSize()
    if not viewportSize then return end

    local centerX = viewportSize.X * 0.5
    local centerY = viewportSize.Y * 0.5
    -- FOV radius: 30% of half-width — comfortable aim circle
    local FOV_RADIUS = 0.30 * (viewportSize.X / 2.0)

    -- TARGET BONE: spine_03 = neck/upper chest area (safer than head)
    local TARGET_BONE = "spine_03"

    local bestTarget = nil
    local bestScore  = 99999999
    local now = os.clock()

    -- Visibility / bot / knocked caches — flush periodically to prevent memory bloat / lag
    _G.PrivAimVisCache = _G.PrivAimVisCache or {}
    _G.PrivAimBotCache = _G.PrivAimBotCache or {}
    _G._PrivAimCacheLastFlush = _G._PrivAimCacheLastFlush or 0
    local _cacheNow = os.clock()
    if _cacheNow - _G._PrivAimCacheLastFlush > 30.0 then
        -- Flush every 30s: stale actors should not accumulate
        _G.PrivAimVisCache = {}
        _G.PrivAimBotCache = {}
        _G._PrivAimCacheLastFlush = _cacheNow
    end

    -- [LAG FIX] Cap how many pawns aimbot evaluates per tick near crowded fights
    local maxAimScan = (LIMITS and LIMITS.MAX_ENEMY_MARKS) or 40
    if maxAimScan > 24 then maxAimScan = 24 end
    local scanned = 0

    for _, actor in pairs(allChars) do
        scanned = scanned + 1
        if scanned > maxAimScan then break end
        if slua.isValid(actor) and actor ~= player then
            -- alive check
            local alive = true
            pcall(function()
                if type(actor.IsAlive) == 'function' then alive = actor:IsAlive()
                elseif actor.HealthStatus ~= nil then alive = (actor.HealthStatus ~= 2)
                elseif actor.bIsDead ~= nil then alive = not actor.bIsDead end
            end)
            if not alive then goto priv_continue end

            -- team check
            local teamId = -2
            pcall(function()
                if type(actor.GetTeamID) == 'function' then teamId = actor:GetTeamID()
                elseif actor.TeamID ~= nil then teamId = actor.TeamID end
            end)
            if teamId == myTeam then goto priv_continue end

            -- knocked check (ignore knocked)
            if actor.HealthStatus == 1 then goto priv_continue end

            -- bot check (ignore bots)
            local actorKey = type(actor.GetUniqueID)=='function' and tostring(actor:GetUniqueID()) or tostring(actor)
            local isBot = _G.PrivAimBotCache[actorKey]
            if isBot == nil then
                isBot = false
                pcall(function()
                    if actor.bIsAI==true or actor.IsAI==true or actor.bIsAIActor==true then isBot=true end
                    if not isBot then
                        local ps = actor.PlayerState
                        if slua.isValid(ps) and (ps.bIsABot==true or ps.bIsBot==true or ps.bIsAI==true) then isBot=true end
                    end
                    if not isBot and type(actor.IsBot)=='function' then
                        local ok,r = pcall(actor.IsBot, actor) if ok and r then isBot=true end
                    end
                end)
                _G.PrivAimBotCache[actorKey] = isBot
            end
            if isBot then goto priv_continue end

            -- visibility check (fail-open: if LOS call fails, treat as visible so aim
            -- does not die after match transitions when PC LOS is not ready yet)
            local vcache = _G.PrivAimVisCache[actorKey]
            if not vcache or (now - vcache.t) > 0.12 then
                local hidden = false
                local losOk = false
                pcall(function()
                    if type(pc.LineOfSightTo) == "function" then
                        hidden = not pc:LineOfSightTo(actor)
                        losOk = true
                    end
                end)
                if not losOk then hidden = false end
                _G.PrivAimVisCache[actorKey] = { hidden = hidden, t = now }
                vcache = _G.PrivAimVisCache[actorKey]
            end
            if vcache.hidden then goto priv_continue end

            -- project to screen
            local tPos = nil
            pcall(function()
                -- Try spine_03 first (neck/chest), fall back to head, then actor location
                local mesh = actor.Mesh
                if slua.isValid(mesh) and type(mesh.GetSocketLocation)=='function' then
                    tPos = mesh:GetSocketLocation(TARGET_BONE)
                    if tPos and tPos.X==0 and tPos.Y==0 and tPos.Z==0 then tPos=nil end
                end
                if not tPos and type(actor.GetBonePos)=='function' then
                    tPos = actor:GetBonePos(TARGET_BONE, {X=0,Y=0,Z=0})
                    if tPos and tPos.X==0 and tPos.Y==0 and tPos.Z==0 then tPos=nil end
                end
                if not tPos then
                    -- fallback: actor location + offset for neck/chest height
                    local loc = actor:K2_GetActorLocation()
                    if loc then tPos = {X=loc.X, Y=loc.Y, Z=loc.Z+45} end
                end
            end)
            if not tPos then goto priv_continue end

            local FV2 = GetFV2()
            local screen = FV2 and FV2(0,0) or {X=0,Y=0}
            local onScreen = false
            pcall(function() onScreen = pc:ProjectWorldLocationToScreen(tPos, screen, false) end)
            if not onScreen then goto priv_continue end

            local dx = screen.X - centerX
            local dy = screen.Y - centerY
            local dist2 = dx*dx + dy*dy
            if dist2 <= FOV_RADIUS*FOV_RADIUS and dist2 < bestScore then
                bestScore  = dist2
                bestTarget = actor
            end

            ::priv_continue::
        end
    end

    if not (bestTarget and slua.isValid(bestTarget)) then return end

    -- Get final bone position for rotation
    local finalPos = nil
    pcall(function()
        local mesh = bestTarget.Mesh
        if slua.isValid(mesh) and type(mesh.GetSocketLocation)=='function' then
            finalPos = mesh:GetSocketLocation(TARGET_BONE)
            if finalPos and finalPos.X==0 and finalPos.Y==0 and finalPos.Z==0 then finalPos=nil end
        end
        if not finalPos and type(bestTarget.GetBonePos)=='function' then
            finalPos = bestTarget:GetBonePos(TARGET_BONE, {X=0,Y=0,Z=0})
            if finalPos and finalPos.X==0 and finalPos.Y==0 and finalPos.Z==0 then finalPos=nil end
        end
        if not finalPos then
            local loc = bestTarget:K2_GetActorLocation()
            if loc then finalPos={X=loc.X,Y=loc.Y,Z=loc.Z+45} end
        end
    end)
    if not finalPos then return end

    local rot = KismetMathLibrary.FindLookAtRotation(camLoc, finalPos)
    if not rot then return end

    local currentRot = pc:GetControlRotation()
    if not currentRot then return end

    local deltaYaw   = rot.Yaw   - currentRot.Yaw
    local deltaPitch = rot.Pitch - currentRot.Pitch

    if deltaYaw   >  180 then deltaYaw   = deltaYaw   - 360 end
    if deltaYaw   < -180 then deltaYaw   = deltaYaw   + 360 end
    if deltaPitch >  180 then deltaPitch = deltaPitch - 360 end
    if deltaPitch < -180 then deltaPitch = deltaPitch + 360 end

    -- [FIXED] P3-identical rotation math — works at ALL ranges including long range + scope
    -- Smoothness is user-controlled: 1 (very slow) to 100 (near-instant, P3 default = 50)
    local _smoothVal = tonumber(_G.GTLMODConfig.AimbotSmoothness) or 50
    local _smoothClamped = math.max(1, math.min(100, _smoothVal))
    -- Map 1-100 → maximum deg/frame: value 50 = 85deg (P3's exact default)
    local maximum = ((_smoothClamped - 1) / 99.0) * (200 - 5) + 5
    local _delta = 0.016
    maximum = maximum * math.min(_delta, 0.05)

    local distance = math.sqrt(deltaYaw*deltaYaw + deltaPitch*deltaPitch)
    local fraction = (distance > maximum) and (maximum/distance) or 1.0

    local humanDY, humanDP = HumanAimDelta(deltaYaw, deltaPitch, fraction)

    local finalRot = {
        Pitch = currentRot.Pitch + humanDP,
        Yaw   = currentRot.Yaw   + humanDY,
        Roll  = 0
    }

    pcall(function()
        local ok = pcall(function() pc:SetControlRotation(finalRot, "CircleAim") end)
        if not ok then pcall(function() pc:SetControlRotation(finalRot) end) end
    end)
end

-- [UTILITIES already defined above PrivAimbotTick — no duplicate needed]

local C_GREEN = {R=0, G=255, B=0, A=255}
local C_RED = {R=255, G=0, B=0, A=255}
local C_CYAN = {R=0, G=255, B=255, A=255}
local C_YELLOW = {R=255, G=255, B=0, A=255}
local C_WHITE = {R=255, G=255, B=255, A=255}
local C_BLUE = {R=0, G=0, B=255, A=255}

-- ====================================================================
-- CONFIG
-- ====================================================================
_G.GTLMODConfig = _G.GTLMODConfig or {
    AutoHead = false,
    EspVip = false,
    EspDistance = false,
    EspVipPro = false,
    EspRadar = false,
    Esp5 = false,
    Esp6 = false,
    Esp7 = false,
    Esp8 = false,
    EspAntenna = false,
    EspName = false,
    EspOutline = false,
    OutlineThickness = 10,
    UnlockFPS = false,
    TargetFPS = 90,
    FPSStabilizer = true,
    PotatoGraphics = false,
    CleaningSpace = false,
    IpadView = false,
    CustomAimbot = false,
    CustomAimbotClose = false,
    CustomHRecoil = false,
    CustomVRecoil = false,
    LessShake = false,
    RemoveGrass = false,
    RemoveFog = false,
    WhiteBody = false,
    ColorBodyV2 = false,
    Crosshair = false,
    Accuracy = false,
    GodMode = false,
    BlackSky = false,
    AimTouchEnable = false,
    AimTouchIgKnock = true,
    AimTouchIgBot = true,
    AimTouchVisCheck = true,
    ForceAimbot = false,
    PrivSmallCrosshair = false,
    CounterEnabled = false,         -- [DEFAULT OFF] user must enable manually
    EspLine = false,
    AimDebug = false,
    WallhackSmart = false,
    EspLineThickness = 2,
    EspItem_Master = false,
    EspItem_AR = true,
    EspItem_Sniper = true,
    EspItem_SMG = true,
    EspItem_Shotgun = true,
    EspItem_LMG = true,
    EspItem_Pistol = true,
    EspItem_Scope = true,
    EspItem_Special = false,
    EspItem_Grenade = true,
    EspItem_Med = true,
    EspItem_Melee = false,
    EspModelName = false,           -- [DEFAULT OFF] user must enable
    EspShowDistance = false,        -- sub of Player Name
    EspShowHealthBar = false,       -- sub of Player Name
    EspTeamColorBox = false,        -- sub of Player Name
    EspWeaponIcon = false,          -- Weapon Icon
    EspActiveBom = false,           -- Active Grenade Warning DEFAULT OFF (toggle in menu)
    ForceAimbotScope = false,       -- force aim only while scoped/ADS
    AimbotSmoothness = 50,          -- 1 (slowest) to 100 (fastest), default 50 = P3 feel
    LagFreeMode = false,
    WallhackThickness = 2.5,
    -- Independent wallhack colors (Goku-style)
    -- indices: 0 Red, 1 Cyan, 2 Yellow, 3 Green, 4 Purple, 5 White, 6 Pink, 7 Lime
    ColorEnemyWHVis = 3,   -- Green visible
    ColorEnemyWHOcc = 0,   -- Red hidden
    ColorBotWHVis   = 1,   -- Cyan visible
    ColorBotWHOcc   = 2,   -- Yellow hidden
    GlowIntensity   = 60,  -- 10-100
}


-- [FIXED] Pre-guard init block removed.
-- All first-load defaults and safe resets are now ONLY inside the
-- "if not _G.ModConfigLoaded" block below, so user settings are
-- NEVER wiped on match-to-match transitions.
-- Only EspActiveBom (Grenade Warning) is forced ON at first load.

_G.GTLMODState = _G.GTLMODState or {
    LoopToken = 0,
    NativeESPReady = false,
    GraphicsUnlocked = false,
    MenuStep = 0,
    TrackedMarks = {},
    EnemyMarks = {},
    CustomTextData = nil,
    PrevGraphicsState = {},
    MidCacheCount = 0,
    AimLastFail = "",
}

-- ====================================================================
-- CONFIG SAVE/LOAD
-- ====================================================================
local function GetConfigPaths(fileName)
    -- [CACHE-PATH] Primary: Android/data/<pkg>/cache/ — same folder as key/hwid
    return {
        -- PRIMARY: game's own cache folder (version-auto-detected)
        PATHS.DataCache .. fileName,
        -- SECONDARY: deep image cache fallback
        PATHS.Cache .. fileName,
        -- LEGACY fallbacks — kept so old installs still read settings
        PATHS.Paks .. "MAGOO/" .. fileName,
        "ShadowTrackerExtra/Saved/Paks/MAGOO/" .. fileName,
        "../../ShadowTrackerExtra/Saved/Paks/MAGOO/" .. fileName,
        PATHS.SaveGames .. fileName,
        PATHS.Paks .. fileName,
        fileName
    }
end
local ConfigFileName = "RJ_settings.txt"
_G.LastConfigSaveStr = ""
_G.LastConfigSaveTime = 0

_G.SaveModSettings = function()
    local now = os.time()
    if now - (_G.LastConfigSaveTime or 0) < LIMITS.CONFIG_SAVE_INTERVAL then return end
    _G.LastConfigSaveTime = now
    pcall(function()
        local buf = { "return {\nGTLConfig = {\n" }
        for k, v in pairs(_G.GTLMODConfig or {}) do
            buf[#buf+1] = "  [\"" .. tostring(k) .. "\"] = " .. tostring(v) .. ",\n"
        end
        buf[#buf+1] = "}\n}"
        local data = table.concat(buf)
        if data == _G.LastConfigSaveStr then return end
        _G.LastConfigSaveStr = data
        for _, path in ipairs(GetConfigPaths(ConfigFileName)) do
            local file = io.open(path, "w")
            if file then file:write(data); file:close(); break end
        end
    end)
end

_G.LoadModSettings = function()
    local loaded = false
    pcall(function()
        local content = nil
        for _, path in ipairs(GetConfigPaths(ConfigFileName)) do
            local file = io.open(path, "r")
            if file then content = file:read("*a"); file:close(); break end
        end
        if content and content ~= "" then
            local func = load(content)
            if func then
                local savedData = func()
                if savedData and type(savedData) == "table" and savedData.GTLConfig then
                    for k, v in pairs(savedData.GTLConfig) do
                        _G.GTLMODConfig[k] = v
                    end
                    loaded = true
                end
            end
        end
        _G.SaveModSettings()
    end)
    return loaded
end

local function AutoSaveLoop()
    -- SaveModSettings itself skips write when content unchanged
    pcall(function() if _G.SaveModSettings then _G.SaveModSettings() end end)
    pcall(function()
        local ticker = GetTicker()
        if ticker and ticker.AddTimerOnce then
            ticker.AddTimerOnce(LIMITS.CONFIG_SAVE_INTERVAL, AutoSaveLoop)
        end
    end)
end

if not _G.ModConfigLoaded then
    local hadSaved = _G.LoadModSettings()
    -- Only wipe to defaults when there is NO saved config.
    -- Previously this always forced ForceAimbot/etc OFF after load, killing
    -- aimbot across matches / restarts even when the user left it ON.
    if not hadSaved then
        local c = _G.GTLMODConfig
        if c then
            c.WallhackSmart      = false
            c.BlackSky           = false
            c.Crosshair          = false
            c.AimTouchEnable     = false
            c.ForceAimbot        = false
            c.PrivSmallCrosshair = false
            c.EspVip             = false
            c.EspVipPro          = false
            c.EspRadar           = false
            c.Esp5               = false
            c.Esp6               = false
            c.Esp7               = false
            c.Esp8               = false
            c.EspAntenna         = false
            c.EspName            = false
            c.EspDistance        = false
            c.AutoHead           = false
            c.UnlockFPS          = false
            c.TargetFPS          = 90
            c.FPSStabilizer      = true
            c.PotatoGraphics     = false
            c.CleaningSpace      = false
            c.IpadView           = false
            c.LagFreeMode        = false
            c.LessShake          = false
            c.Accuracy           = false
            c.CustomHRecoil      = false
            c.CustomVRecoil      = false
            c.GodMode            = false
            c.EspItem_Master     = false
            c.EspOutline         = false
            c.WhiteBody          = false
            c.ColorBodyV2        = false
            c.RemoveGrass        = false
            c.RemoveFog          = false
            c.AimDebug           = false
            c.ForceAimbotScope   = false
            c.EspShowDistance    = false
            c.EspShowHealthBar   = false
            c.EspTeamColorBox    = false
            c.EspLine            = false
            c.CounterEnabled     = false
            c.EspModelName       = false
            c.EspWeaponIcon      = false
        end
    end
    -- Grenade warning: keep saved value; default ON only if never set
    if _G.GTLMODConfig and _G.GTLMODConfig.EspActiveBom == nil then
        _G.GTLMODConfig.EspActiveBom = false
    end
    -- Restore ForceAimbot wanted flag from saved config
    if _G.GTLMODConfig and _G.GTLMODConfig.ForceAimbot == true then
        _G._ForceAimbotWanted = true
    end
    AutoSaveLoop()
    _G.ModConfigLoaded = true
end

-- ====================================================================
-- NEW WALLHACK
-- ====================================================================
local NewWallhack = {
    Active = false,
    WH_TIMER = nil,
    PROCESSED_PAWNS = {},
    TICK_COUNT = 0,
    CONSOLE_READY = false,
    TICK_INTERVAL = 2.6,           -- lag fix: fewer full mesh walks (was 1.8)
    MAX_PAWNS_PER_TICK = 8,         -- lag fix: was 12
    RESET_PROCESSED_EVERY = 8,      -- lag fix: re-dye less often
    AVATAR_SLOTS = {0,1,2,3,4,5,6,7},
    colors = { vis = nil, occ = nil, bVis = nil, bOcc = nil }
}

pcall(function()
    local LC = safeImport("LinearColor")
    if LC then
        NewWallhack.colors.vis = LC(0.0, 1.0, 0.0, 0.4)
        NewWallhack.colors.occ = LC(1.0, 0.0, 0.0, 0.4)
        NewWallhack.colors.bVis = LC(0.0, 0.8, 0.0, 0.4)
        NewWallhack.colors.bOcc = LC(0.8, 0.0, 0.0, 0.4)
    end
end)

local function SetupConsole()
    if NewWallhack.CONSOLE_READY then return end
    pcall(function()
        local KSL = safeImport("KismetSystemLibrary")
        local world = slua.getWorld()
        if not KSL or not world then return end
        KSL.ExecuteConsoleCommand(world, "r.EnableDrawDyeingColor 1")
        KSL.ExecuteConsoleCommand(world, "r.CustomDepth 3")
        KSL.ExecuteConsoleCommand(world, "r.IdeaOutline.Enable 1")
        KSL.ExecuteConsoleCommand(world, "r.Highlight.Enable 1")
        NewWallhack.CONSOLE_READY = true
    end)
end

local function ApplyToMesh(mesh, visColor, occColor)
    if not mesh or not slua.isValid(mesh) then return end
    pcall(function()
        if mesh.SetDrawDyeing then mesh:SetDrawDyeing(true) end
        if mesh.SetDrawDyeingMode then mesh:SetDrawDyeingMode(1) end
        if mesh.SetVisibleDyeingColor then mesh:SetVisibleDyeingColor(visColor) end
        if mesh.SetOccludedDyeingColor then mesh:SetOccludedDyeingColor(occColor) end
        if mesh.SetDyeingColorFadeDistance then mesh:SetDyeingColorFadeDistance(99999.0) end
        if mesh.SetDyeingColorMinMaxDistance then mesh:SetDyeingColorMinMaxDistance(0.0, 99999.0) end
        if mesh.SetDrawHighlight then mesh:SetDrawHighlight(true) end
        if mesh.OverrideHighlightColor then mesh:OverrideHighlightColor(visColor) end
        if mesh.SetHighlightCanBeOccluded then mesh:SetHighlightCanBeOccluded(false) end
        if mesh.SetDrawIdeaOutline then mesh:SetDrawIdeaOutline(true) end
        if mesh.SetIdeaOutlineNew then mesh:SetIdeaOutlineNew(true) end
        if mesh.SetIdeaOutlineOcclusionHighlight then mesh:SetIdeaOutlineOcclusionHighlight(true) end
        if mesh.OverrideIdeaOutlineColor then mesh:OverrideIdeaOutlineColor(visColor) end
        if mesh.SetIdeaOutlineOcclusionColor then mesh:SetIdeaOutlineOcclusionColor(occColor) end
        if mesh.OverrideIdeaOutlineThickness then mesh:OverrideIdeaOutlineThickness(20.0) end
        if mesh.SetIdeaOverrideOutlineAndOcclusion then mesh:SetIdeaOverrideOutlineAndOcclusion(true) end
        if mesh.SetRenderCustomDepth then mesh:SetRenderCustomDepth(true) end
        if mesh.SetCustomDepthStencilValue then mesh:SetCustomDepthStencilValue(255) end
    end)
end

local function IsPawnAlive(pawn)
    if not slua.isValid(pawn) then return false end
    if pawn.Health and pawn.Health > 0 then return true end
    return false
end

local function NewWallhackTick()
    pcall(function()
        local localPawn = GameplayData and GameplayData.GetPlayerCharacter and GameplayData.GetPlayerCharacter()
        if not slua.isValid(localPawn) then return end
        -- console cmds only once (calling every tick causes hitch)
        if not NewWallhack.CONSOLE_READY then SetupConsole() end
        if not NewWallhack.colors.vis then return end
        NewWallhack.TICK_COUNT = NewWallhack.TICK_COUNT + 1
        if NewWallhack.TICK_COUNT % NewWallhack.RESET_PROCESSED_EVERY == 0 then
            NewWallhack.PROCESSED_PAWNS = {}
        end
        local myTeamId = localPawn.TeamID or 0
        local allPawns = Game:GetAllPlayerPawns() or {}
        local processedCount = 0
        for _, pawn in pairs(allPawns) do
            if processedCount >= NewWallhack.MAX_PAWNS_PER_TICK then break end
            if not slua.isValid(pawn) or pawn == localPawn then goto continue end
            if pawn.PlayerKey and NewWallhack.PROCESSED_PAWNS[pawn.PlayerKey] then goto continue end
            -- [FIXED] Verify pawn is still valid before accessing properties
            if not slua.isValid(pawn) then goto continue end
            if IsPawnAlive(pawn) and pawn.TeamID and pawn.TeamID ~= myTeamId then
                local isAI = pcall(Game.IsAI, pawn) and true or false
                local vis = isAI and NewWallhack.colors.bVis or NewWallhack.colors.vis
                local occ = isAI and NewWallhack.colors.bOcc or NewWallhack.colors.occ
                pcall(function()
                    if slua.isValid(pawn.Mesh) then ApplyToMesh(pawn.Mesh, vis, occ) end
                    local avatarComp = pawn.CharacterAvatarComp2_BP or (pawn.getAvatarComponent2 and pawn:getAvatarComponent2())
                    if avatarComp and avatarComp.GetMeshCompBySlot then
                        for _, slot in ipairs(NewWallhack.AVATAR_SLOTS) do
                            local mesh = avatarComp:GetMeshCompBySlot(slot)
                            if slua.isValid(mesh) then ApplyToMesh(mesh, vis, occ) end
                        end
                    end
                    -- skeletal only, cap components (static mesh scan caused mid-match hitch)
                    pcall(function()
                        local SkeletalMeshComponent = safeImport("SkeletalMeshComponent")
                        if SkeletalMeshComponent and pawn.GetComponentsByClass then
                            local skComps = pawn:GetComponentsByClass(SkeletalMeshComponent)
                            if skComps then
                                local n = skComps:Num() or 0
                                if n > 6 then n = 6 end
                                for i = 0, n - 1 do
                                    local comp = skComps:Get(i)
                                    if slua.isValid(comp) and comp ~= pawn.Mesh then
                                        ApplyToMesh(comp, vis, occ)
                                    end
                                end
                            end
                        end
                    end)
                    if pawn.GetCurrentWeapon then
                        local weapon = pawn:GetCurrentWeapon()
                        if slua.isValid(weapon) and slua.isValid(weapon.Mesh) then
                            ApplyToMesh(weapon.Mesh, vis, occ)
                        end
                    end
                end)
                if pawn.PlayerKey then NewWallhack.PROCESSED_PAWNS[pawn.PlayerKey] = true end
                processedCount = processedCount + 1
            end
            ::continue::
        end
    end)
end

function _G.StartNewWallhack()
    -- Always re-prime console (match transition resets dyeing flags)
    NewWallhack.CONSOLE_READY = false
    NewWallhack.PROCESSED_PAWNS = {}
    NewWallhack.TICK_COUNT = 0
    pcall(function() if _G.RefreshWallhackColors then _G.RefreshWallhackColors() end end)
    if NewWallhack.WH_TIMER then
        pcall(function()
            if _G.Game then _G.Game:RemoveGameTimer(NewWallhack.WH_TIMER) end
        end)
        pcall(function()
            local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
            if slua.isValid(pc) and pc.RemoveGameTimer then
                pc:RemoveGameTimer(NewWallhack.WH_TIMER)
            end
        end)
        NewWallhack.WH_TIMER = nil
    end
    NewWallhack.Active = false
    SetupConsole()
    if not NewWallhack.colors.vis then
        pcall(function() if _G.RefreshWallhackColors then _G.RefreshWallhackColors() end end)
        if not NewWallhack.colors.vis then return false end
    end
    if _G.Game and _G.Game.AddGameTimer then
        NewWallhack.WH_TIMER = _G.Game:AddGameTimer(NewWallhack.TICK_INTERVAL, true, NewWallhackTick)
        NewWallhack.Active = true
        NewWallhack.PROCESSED_PAWNS = {}
        return true
    end
    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if slua.isValid(pc) and pc.AddGameTimer then
        NewWallhack.WH_TIMER = pc:AddGameTimer(NewWallhack.TICK_INTERVAL, true, NewWallhackTick)
        NewWallhack.Active = true
        NewWallhack.PROCESSED_PAWNS = {}
        return true
    end
    return false
end

function _G.StopNewWallhack()
    if NewWallhack.WH_TIMER then
        pcall(function()
            if _G.Game then _G.Game:RemoveGameTimer(NewWallhack.WH_TIMER) end
        end)
        -- also try player controller timer remove
        pcall(function()
            local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
            if slua.isValid(pc) and pc.RemoveGameTimer then
                pc:RemoveGameTimer(NewWallhack.WH_TIMER)
            end
        end)
        NewWallhack.WH_TIMER = nil
    end
    -- Clear dyeing/outline from tracked pawns
    pcall(function()
        local GD = GameplayData or package.loaded["GameLua.GameCore.Data.GameplayData"]
        local chars = GD and GD.GetAllPlayerCharacters and GD.GetAllPlayerCharacters()
        if chars then
            for _, pawn in pairs(chars) do
                if slua.isValid(pawn) then
                    pcall(function()
                        local function ClearMesh(mesh)
                            if not mesh or not slua.isValid(mesh) then return end
                            pcall(function()
                                if mesh.SetDrawDyeing then mesh:SetDrawDyeing(false) end
                                if mesh.SetDrawHighlight then mesh:SetDrawHighlight(false) end
                                if mesh.SetDrawIdeaOutline then mesh:SetDrawIdeaOutline(false) end
                                if mesh.SetIdeaOutlineNew then mesh:SetIdeaOutlineNew(false) end
                                if mesh.SetRenderCustomDepth then mesh:SetRenderCustomDepth(false) end
                            end)
                        end
                        if pawn.Mesh then ClearMesh(pawn.Mesh) end
                        if pawn.getAvatarComponent2 then
                            local av = pawn:getAvatarComponent2()
                            if slua.isValid(av) then
                                for _, slot in ipairs(NewWallhack.AVATAR_SLOTS or {0,1,2,3,4,5,6,7}) do
                                    pcall(function()
                                        local m = nil
                                        if av.GetMeshCompBySlot then m = av:GetMeshCompBySlot(slot)
                                        elseif av.GetMeshBySlot then m = av:GetMeshBySlot(slot) end
                                        ClearMesh(m)
                                    end)
                                end
                            end
                        end
                        -- also clear all skeletal mesh components
                        pcall(function()
                            local SkeletalMeshComponent = safeImport("SkeletalMeshComponent")
                            if SkeletalMeshComponent and pawn.GetComponentsByClass then
                                local skComps = pawn:GetComponentsByClass(SkeletalMeshComponent)
                                if skComps then
                                    for i = 0, skComps:Num() - 1 do
                                        local comp = skComps:Get(i)
                                        ClearMesh(comp)
                                    end
                                end
                            end
                        end)
                    end)
                end
            end
        end
    end)
    NewWallhack.PROCESSED_PAWNS = {}
    NewWallhack.Active = false
end

-- Independent wallhack color palette (visible / hidden / bot)
_G.WH_COLOR_PALETTE = {
    [0]  = {0.95, 0.05, 0.05},  -- Red
    [1]  = {0.05, 0.95, 0.95},  -- Cyan
    [2]  = {0.95, 0.95, 0.08},  -- Yellow
    [3]  = {0.08, 0.95, 0.15},  -- Green
    [4]  = {0.55, 0.10, 0.95},  -- Purple
    [5]  = {0.95, 0.95, 0.95},  -- White
    [6]  = {1.00, 0.20, 0.55},  -- Pink
    [7]  = {0.30, 1.00, 0.15},  -- Lime
    [8]  = {1.00, 0.45, 0.05},  -- Orange
    [9]  = {0.15, 0.35, 1.00},  -- Blue
    [10] = {1.00, 0.05, 0.85},  -- Magenta
    [11] = {0.05, 0.85, 0.70},  -- Teal
    [12] = {1.00, 0.80, 0.15},  -- Gold
}

local function _WH_MakeLC(idx, alpha)
    local LC = safeImport("LinearColor")
    if not LC then return nil end
    local c = _G.WH_COLOR_PALETTE[tonumber(idx) or 0] or _G.WH_COLOR_PALETTE[0]
    local intensity = tonumber((_G.GTLMODConfig and _G.GTLMODConfig.GlowIntensity) or 60) or 60
    if intensity < 10 then intensity = 10 end
    if intensity > 100 then intensity = 100 end
    local mult = 0.55 + (intensity / 100.0) * 0.70
    local a = alpha or 0.50
    return LC(c[1] * mult, c[2] * mult, c[3] * mult, a)
end

function _G.RefreshWallhackColors()
    local cfg = _G.GTLMODConfig or {}
    NewWallhack.colors.vis  = _WH_MakeLC(cfg.ColorEnemyWHVis or 3, 0.50)
    NewWallhack.colors.occ  = _WH_MakeLC(cfg.ColorEnemyWHOcc or 0, 0.50)
    NewWallhack.colors.bVis = _WH_MakeLC(cfg.ColorBotWHVis or 1, 0.45)
    NewWallhack.colors.bOcc = _WH_MakeLC(cfg.ColorBotWHOcc or 2, 0.45)
    NewWallhack.PROCESSED_PAWNS = {}
end

pcall(function()
    local ticker = package.loaded["common.time_ticker"] or require("common.time_ticker")
    if ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(4.0, function()
            if _G.GTLMODConfig and _G.GTLMODConfig.WallhackSmart and _G.StartNewWallhack then
                _G.StartNewWallhack()
            end
        end)
    end
end)

-- ====================================================================
-- MENU
-- ====================================================================
function _G.InitModMenuTab()
    if _G.ModMenuInitialized then return end
    _G.ModMenuInitialized = true

    _G.GTLMODState.CustomTextData = _G.GTLMODState.CustomTextData or {
        OuterSpeed = 10, InnerSpeed = 10, OuterRecoil = 0,
        HRecoil = 0.3, VRecoil = 0.3, IpadViewFOV = 120,
    }
    -- Always keep OuterRecoil at 0 to prevent scope drift upward
    _G.GTLMODState.CustomTextData.OuterRecoil = 0

    local LocUtil = _G.LocUtil
    if not LocUtil and package.loaded["client.common.LocUtil"] then
        LocUtil = require("client.common.LocUtil")
    end
    if LocUtil and not LocUtil._IsModMenuHooked then
        local old_get = LocUtil.GetLocalizeResStr
        LocUtil.GetLocalizeResStr = function(id)
            if type(id) == "string" and not tonumber(id) then return id end
            return old_get(id)
        end
        LocUtil._IsModMenuHooked = true
    end

    local SettingPageDefine = require("client.logic.NewSetting.SettingPageDefine")
    local SettingCatalog = require("client.logic.NewSetting.SettingCatalog")

    if not SettingPageDefine.ModMenu then
        local AliasMap = require("client.slua.umg.NewSetting.Item.AliasMap")

        -- ==================== SUPERVISION ====================
        local StackSupervision = {
            { Key = "ModMenu_ESP4", UI = AliasMap.Switcher, Text = "ESP MARK · 360 RADAR", GetFunc = function() return _G.GTLMODConfig.EspRadar end, SetFunc = function(c,v) _G.GTLMODConfig.EspRadar = v return true end },
            { Key = "ModMenu_ESP5", UI = AliasMap.Switcher, Text = "BOX ESP", GetFunc = function() return _G.GTLMODConfig.Esp5 end, SetFunc = function(c,v) _G.GTLMODConfig.Esp5 = v return true end },
            { Key = "ModMenu_ESPLine_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ ESP LINE", ExpandIndex = 0, GetFunc = function() return _G.GTLMODConfig.EspLine end, SetFunc = function(c,v)
                _G.GTLMODConfig.EspLine = v
                -- ESP LINE uses PlayerMapMarker only (old green ESPLine removed)
                if _G.LexusConfig then
                    _G.LexusConfig.Esp9_Line = v and true or false
                    _G.LexusConfig.EspLoai9 = true
                end
                if _G.PlayerMapMarker then
                    if v then
                        -- [FIX] Use EnsureRunning (not Start) so canvas is NOT wiped.
                        -- Start() resets ESPCanvas=nil which kills RedBoxOverlay counter widgets.
                        -- EnsureRunning() only rebuilds what's actually broken.
                        if _G.PlayerMapMarker.EnsureRunning then
                            pcall(_G.PlayerMapMarker.EnsureRunning)
                        elseif _G.PlayerMapMarker.Start then
                            pcall(_G.PlayerMapMarker.Start)
                        end
                    else
                        if _G.PlayerMapMarker.ClearAllSnapLines then pcall(_G.PlayerMapMarker.ClearAllSnapLines) end
                    end
                end
                return true
            end },
            { Key = "ModMenu_Counter", UI = AliasMap.Switcher, Text = "PLAYER / BOT COUNTER", GetFunc = function() return _G.GTLMODConfig.CounterEnabled end, SetFunc = function(c,v)
                _G.GTLMODConfig.CounterEnabled = v
                -- Star RedBoxOverlay is the only counter
                if _G.LexusConfig then
                    _G.LexusConfig.Esp9_Count = v and true or false
                    _G.LexusConfig.EspLoai9 = true
                end
                if v then
                    if _G.PlayerMapMarker and _G.PlayerMapMarker.Start then pcall(_G.PlayerMapMarker.Start) end
                    if _G.RedBoxOverlay and _G.RedBoxOverlay.Start then pcall(_G.RedBoxOverlay.Start) end
                else
                    if _G.RedBoxOverlay and _G.RedBoxOverlay.Stop then pcall(_G.RedBoxOverlay.Stop) end
                end
                return true
            end },
            { Key = "ModMenu_PlayerName_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ PLAYER NAME", ExpandIndex = 0, GetFunc = function() return _G.GTLMODConfig.EspModelName end, SetFunc = function(c,v)
                _G.GTLMODConfig.EspModelName = v
                -- [FIXED] Master toggle: all three sub-options mirror the parent state
                _G.GTLMODConfig.EspShowDistance  = v
                _G.GTLMODConfig.EspShowHealthBar = v
                _G.GTLMODConfig.EspTeamColorBox  = v
                if _G.LexusConfig then
                    _G.LexusConfig.Esp9_Name     = v and true or false
                    _G.LexusConfig.Esp9_Distance  = v and true or false
                    _G.LexusConfig.Esp9_HP        = v and true or false
                    _G.LexusConfig.Esp9_Team      = v and true or false
                    _G.LexusConfig.EspLoai9 = true
                end
                if v and _G.PlayerMapMarker and _G.PlayerMapMarker.Start then pcall(_G.PlayerMapMarker.Start) end
                return true
            end },
            { Key = "ModMenu_ShowDistance", UI = AliasMap.Switcher, Text = "   Show Distance", ExpandHandle = "ModMenu_PlayerName_Ex", GetFunc = function() return _G.GTLMODConfig.EspShowDistance end, SetFunc = function(c,v) _G.GTLMODConfig.EspShowDistance = v return true end },
            { Key = "ModMenu_ShowHealthBar", UI = AliasMap.Switcher, Text = "   Show Health Bar", ExpandHandle = "ModMenu_PlayerName_Ex", GetFunc = function() return _G.GTLMODConfig.EspShowHealthBar end, SetFunc = function(c,v) _G.GTLMODConfig.EspShowHealthBar = v return true end },
            { Key = "ModMenu_TeamColorBox", UI = AliasMap.Switcher, Text = "   Team Color Box", ExpandHandle = "ModMenu_PlayerName_Ex", GetFunc = function() return _G.GTLMODConfig.EspTeamColorBox end, SetFunc = function(c,v) _G.GTLMODConfig.EspTeamColorBox = v return true end },
            { Key = "ModMenu_WeaponIcon", UI = AliasMap.Switcher, Text = "WEAPON ICON", GetFunc = function() return _G.GTLMODConfig.EspWeaponIcon end, SetFunc = function(c,v)
                _G.GTLMODConfig.EspWeaponIcon = v
                if _G.LexusConfig then _G.LexusConfig.Esp9_Weapon = v and true or false; _G.LexusConfig.EspLoai9 = true end
                if v and _G.PlayerMapMarker and _G.PlayerMapMarker.Start then pcall(_G.PlayerMapMarker.Start) end
                return true
            end },
            { Key = "ModMenu_EspItem_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ ITEM ESP", ExpandIndex = 0, GetFunc = function() return _G.GTLMODConfig.EspItem_Master end, SetFunc = function(c,v)
                _G.GTLMODConfig.EspItem_Master = v
                if not v then
                    pcall(function() if _G.ClearAllItemESPGlow then _G.ClearAllItemESPGlow() end end)
                end
                return true
            end },
            { Key = "ModMenu_EspItem_AR", UI = AliasMap.Switcher, Text = "   AR Weapons", ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.GTLMODConfig.EspItem_AR end, SetFunc = function(c,v) _G.GTLMODConfig.EspItem_AR = v return true end },
            { Key = "ModMenu_EspItem_Sniper", UI = AliasMap.Switcher, Text = "   Sniper Rifles", ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.GTLMODConfig.EspItem_Sniper end, SetFunc = function(c,v) _G.GTLMODConfig.EspItem_Sniper = v return true end },
            { Key = "ModMenu_EspItem_SMG", UI = AliasMap.Switcher, Text = "   SMGs", ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.GTLMODConfig.EspItem_SMG end, SetFunc = function(c,v) _G.GTLMODConfig.EspItem_SMG = v return true end },
            { Key = "ModMenu_EspItem_Scope", UI = AliasMap.Switcher, Text = "   Scopes", ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.GTLMODConfig.EspItem_Scope end, SetFunc = function(c,v) _G.GTLMODConfig.EspItem_Scope = v return true end },
            { Key = "ModMenu_EspItem_Med", UI = AliasMap.Switcher, Text = "   Meds", ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.GTLMODConfig.EspItem_Med end, SetFunc = function(c,v) _G.GTLMODConfig.EspItem_Med = v return true end },
            { Key = "ModMenu_EspActiveBom", UI = AliasMap.Switcher, Text = "ACTIVE GRENADE WARNING",
              GetFunc = function() return _G.GTLMODConfig.EspActiveBom == true end,
              SetFunc = function(c,v)
                _G.GTLMODConfig.EspActiveBom = v and true or false
                _G.LexusConfig = _G.LexusConfig or {}
                _G.LexusConfig.EspActiveBom = _G.GTLMODConfig.EspActiveBom
                _G.LexusConfig.EspBomMaster = _G.GTLMODConfig.EspActiveBom
                return true
              end },
        }

        -- ==================== AIM FOCUS ====================
        -- Force Aimbot = single toggle that enables both force+assistant modes.
        -- Locks aim ON FIRE only (not always). Target: neck/chest (spine_03).
        -- Visibility check, ignore knocked, ignore bots are always active internally.
        -- Small Crosshair uses HackerWeaponFeatures (private mod menu method).
        local StackAimFocus = {
            { Key = "ModMenu_ForceAimbot", UI = AliasMap.Switcher, Text = "FORCE AIM (HIP)", GetFunc = function() return _G.GTLMODConfig.ForceAimbot end, SetFunc = function(c,v)
                _G.GTLMODConfig.ForceAimbot = v and true or false
                _G._ForceAimbotWanted = _G.GTLMODConfig.ForceAimbot
                -- clear stale aim caches so it engages immediately
                _G.PrivAimVisCache = {}
                _G.PrivAimBotCache = {}
                if _G.SaveModSettings then pcall(_G.SaveModSettings) end
                if _G.PrivAimInstance then pcall(function() _G.PrivAimInstance:dispose() end); _G.PrivAimInstance = nil end
                return true
            end },
            { Key = "ModMenu_AimbotSmooth", UI = AliasMap.Slider, Text = "   Aim Smoothness (1-100)", ExpandHandle = "ModMenu_ForceAimbot", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return tonumber(_G.GTLMODConfig.AimbotSmoothness) or 50 end, SetFunc = function(c,v)
                _G.GTLMODConfig.AimbotSmoothness = math.max(1, math.min(100, tonumber(v) or 50))
                return true
            end },
            { Key = "ModMenu_PrivSmallCrosshair", UI = AliasMap.Switcher, Text = "SMALL CROSSHAIR", GetFunc = function() return _G.GTLMODConfig.PrivSmallCrosshair end, SetFunc = function(c,v)
                _G.GTLMODConfig.PrivSmallCrosshair = v
                if not v then
                    if _G.PrivWeaponInstance then
                        pcall(_G.PrivWeaponInstance.dispose, _G.PrivWeaponInstance)
                        _G.PrivWeaponInstance = nil
                    end
                end
                return true
            end },
            { Key = "ModMenu_LessShake", UI = AliasMap.Switcher, Text = "LESS SCOPE SHAKE", GetFunc = function() return _G.GTLMODConfig.LessShake end, SetFunc = function(c,v) _G.GTLMODConfig.LessShake = v return true end },
            { Key = "ModMenu_NoRecoil", UI = AliasMap.Switcher, Text = "LESS RECOIL (Drop/Pick weapon)", GetFunc = function() return _G.GTLMODConfig.CustomHRecoil end, SetFunc = function(c,v)
                _G.GTLMODConfig.CustomHRecoil = v
                _G.GTLMODConfig.CustomVRecoil = v
                _G.GTLMODState.CustomTextData = _G.GTLMODState.CustomTextData or {}
                if v then
                    _G.GTLMODState.CustomTextData.HRecoil = 0.05
                    _G.GTLMODState.CustomTextData.VRecoil = 0.05
                else
                    _G.GTLMODState.CustomTextData.HRecoil = 0.3
                    _G.GTLMODState.CustomTextData.VRecoil = 0.3
                end
                return true
            end },
        }

        -- ==================== WORLD VISION ====================
        local StackWorldVision = {
            { Key = "ModMenu_NewWallhack", UI = AliasMap.TitleSwitcher, Text = "▶ NEW WALLHACK", ExpandIndex = 0,
              GetFunc = function() return _G.GTLMODConfig.WallhackSmart end, SetFunc = function(c,v)
                _G.GTLMODConfig.WallhackSmart = v
                if v then
                    if _G.RefreshWallhackColors then _G.RefreshWallhackColors() end
                    if _G.StartNewWallhack then _G.StartNewWallhack() end
                else
                    if _G.StopNewWallhack then _G.StopNewWallhack() end
                end
                return true
            end },
            { Key = "ModMenu_WH_Glow", UI = AliasMap.Slider, Text = "   Glow Intensity",
              ExpandHandle = "ModMenu_NewWallhack",
              MinValue = 10, MaxValue = 100, min = 10, max = 100,
              GetFunc = function() return _G.GTLMODConfig.GlowIntensity or 60 end,
              SetFunc = function(_, v)
                _G.GTLMODConfig.GlowIntensity = math.floor(tonumber(v) or 60)
                if _G.RefreshWallhackColors then _G.RefreshWallhackColors() end
                return true
              end },
            { Key = "ModMenu_WH_EV_1", UI = AliasMap.Switcher, Text = "   Enemy Visible · 1",
              ExpandHandle = "ModMenu_NewWallhack",
              SwitcherText = {"Red","Cyan","Yellow","Green"}, SwitcherValue = {0,1,2,3},
              GetFunc = function() return _G.GTLMODConfig.ColorEnemyWHVis or 3 end,
              SetFunc = function(_, v)
                _G.GTLMODConfig.ColorEnemyWHVis = math.floor(tonumber(v) or 3)
                if _G.RefreshWallhackColors then _G.RefreshWallhackColors() end
                return true
              end },
            { Key = "ModMenu_WH_EV_2", UI = AliasMap.Switcher, Text = "   Enemy Visible · 2",
              ExpandHandle = "ModMenu_NewWallhack",
              SwitcherText = {"Purple","White","Pink","Lime"}, SwitcherValue = {4,5,6,7},
              GetFunc = function() return _G.GTLMODConfig.ColorEnemyWHVis or 3 end,
              SetFunc = function(_, v)
                _G.GTLMODConfig.ColorEnemyWHVis = math.floor(tonumber(v) or 3)
                if _G.RefreshWallhackColors then _G.RefreshWallhackColors() end
                return true
              end },
            { Key = "ModMenu_WH_EV_3", UI = AliasMap.Switcher, Text = "   Enemy Visible · 3",
              ExpandHandle = "ModMenu_NewWallhack",
              SwitcherText = {"Orange","Blue","Magenta","Teal"}, SwitcherValue = {8,9,10,11},
              GetFunc = function() return _G.GTLMODConfig.ColorEnemyWHVis or 3 end,
              SetFunc = function(_, v)
                _G.GTLMODConfig.ColorEnemyWHVis = math.floor(tonumber(v) or 3)
                if _G.RefreshWallhackColors then _G.RefreshWallhackColors() end
                return true
              end },
            { Key = "ModMenu_WH_EV_4", UI = AliasMap.Switcher, Text = "   Enemy Visible · 4",
              ExpandHandle = "ModMenu_NewWallhack",
              SwitcherText = {"Gold"}, SwitcherValue = {12},
              GetFunc = function() return _G.GTLMODConfig.ColorEnemyWHVis or 3 end,
              SetFunc = function(_, v)
                _G.GTLMODConfig.ColorEnemyWHVis = math.floor(tonumber(v) or 3)
                if _G.RefreshWallhackColors then _G.RefreshWallhackColors() end
                return true
              end },
            { Key = "ModMenu_WH_EH_1", UI = AliasMap.Switcher, Text = "   Enemy Hidden · 1",
              ExpandHandle = "ModMenu_NewWallhack",
              SwitcherText = {"Red","Cyan","Yellow","Green"}, SwitcherValue = {0,1,2,3},
              GetFunc = function() return _G.GTLMODConfig.ColorEnemyWHOcc or 0 end,
              SetFunc = function(_, v)
                _G.GTLMODConfig.ColorEnemyWHOcc = math.floor(tonumber(v) or 0)
                if _G.RefreshWallhackColors then _G.RefreshWallhackColors() end
                return true
              end },
            { Key = "ModMenu_WH_EH_2", UI = AliasMap.Switcher, Text = "   Enemy Hidden · 2",
              ExpandHandle = "ModMenu_NewWallhack",
              SwitcherText = {"Purple","White","Pink","Lime"}, SwitcherValue = {4,5,6,7},
              GetFunc = function() return _G.GTLMODConfig.ColorEnemyWHOcc or 0 end,
              SetFunc = function(_, v)
                _G.GTLMODConfig.ColorEnemyWHOcc = math.floor(tonumber(v) or 0)
                if _G.RefreshWallhackColors then _G.RefreshWallhackColors() end
                return true
              end },
            { Key = "ModMenu_WH_EH_3", UI = AliasMap.Switcher, Text = "   Enemy Hidden · 3",
              ExpandHandle = "ModMenu_NewWallhack",
              SwitcherText = {"Orange","Blue","Magenta","Teal"}, SwitcherValue = {8,9,10,11},
              GetFunc = function() return _G.GTLMODConfig.ColorEnemyWHOcc or 0 end,
              SetFunc = function(_, v)
                _G.GTLMODConfig.ColorEnemyWHOcc = math.floor(tonumber(v) or 0)
                if _G.RefreshWallhackColors then _G.RefreshWallhackColors() end
                return true
              end },
            { Key = "ModMenu_WH_EH_4", UI = AliasMap.Switcher, Text = "   Enemy Hidden · 4",
              ExpandHandle = "ModMenu_NewWallhack",
              SwitcherText = {"Gold"}, SwitcherValue = {12},
              GetFunc = function() return _G.GTLMODConfig.ColorEnemyWHOcc or 0 end,
              SetFunc = function(_, v)
                _G.GTLMODConfig.ColorEnemyWHOcc = math.floor(tonumber(v) or 0)
                if _G.RefreshWallhackColors then _G.RefreshWallhackColors() end
                return true
              end },
            { Key = "ModMenu_WH_BV_1", UI = AliasMap.Switcher, Text = "   Bot Visible · 1",
              ExpandHandle = "ModMenu_NewWallhack",
              SwitcherText = {"Red","Cyan","Yellow","Green"}, SwitcherValue = {0,1,2,3},
              GetFunc = function() return _G.GTLMODConfig.ColorBotWHVis or 1 end,
              SetFunc = function(_, v)
                _G.GTLMODConfig.ColorBotWHVis = math.floor(tonumber(v) or 1)
                if _G.RefreshWallhackColors then _G.RefreshWallhackColors() end
                return true
              end },
            { Key = "ModMenu_WH_BV_2", UI = AliasMap.Switcher, Text = "   Bot Visible · 2",
              ExpandHandle = "ModMenu_NewWallhack",
              SwitcherText = {"Purple","White","Pink","Lime"}, SwitcherValue = {4,5,6,7},
              GetFunc = function() return _G.GTLMODConfig.ColorBotWHVis or 1 end,
              SetFunc = function(_, v)
                _G.GTLMODConfig.ColorBotWHVis = math.floor(tonumber(v) or 1)
                if _G.RefreshWallhackColors then _G.RefreshWallhackColors() end
                return true
              end },
            { Key = "ModMenu_WH_BV_3", UI = AliasMap.Switcher, Text = "   Bot Visible · 3",
              ExpandHandle = "ModMenu_NewWallhack",
              SwitcherText = {"Orange","Blue","Magenta","Teal"}, SwitcherValue = {8,9,10,11},
              GetFunc = function() return _G.GTLMODConfig.ColorBotWHVis or 1 end,
              SetFunc = function(_, v)
                _G.GTLMODConfig.ColorBotWHVis = math.floor(tonumber(v) or 1)
                if _G.RefreshWallhackColors then _G.RefreshWallhackColors() end
                return true
              end },
            { Key = "ModMenu_WH_BV_4", UI = AliasMap.Switcher, Text = "   Bot Visible · 4",
              ExpandHandle = "ModMenu_NewWallhack",
              SwitcherText = {"Gold"}, SwitcherValue = {12},
              GetFunc = function() return _G.GTLMODConfig.ColorBotWHVis or 1 end,
              SetFunc = function(_, v)
                _G.GTLMODConfig.ColorBotWHVis = math.floor(tonumber(v) or 1)
                if _G.RefreshWallhackColors then _G.RefreshWallhackColors() end
                return true
              end },
            { Key = "ModMenu_WH_BH_1", UI = AliasMap.Switcher, Text = "   Bot Hidden · 1",
              ExpandHandle = "ModMenu_NewWallhack",
              SwitcherText = {"Red","Cyan","Yellow","Green"}, SwitcherValue = {0,1,2,3},
              GetFunc = function() return _G.GTLMODConfig.ColorBotWHOcc or 2 end,
              SetFunc = function(_, v)
                _G.GTLMODConfig.ColorBotWHOcc = math.floor(tonumber(v) or 2)
                if _G.RefreshWallhackColors then _G.RefreshWallhackColors() end
                return true
              end },
            { Key = "ModMenu_WH_BH_2", UI = AliasMap.Switcher, Text = "   Bot Hidden · 2",
              ExpandHandle = "ModMenu_NewWallhack",
              SwitcherText = {"Purple","White","Pink","Lime"}, SwitcherValue = {4,5,6,7},
              GetFunc = function() return _G.GTLMODConfig.ColorBotWHOcc or 2 end,
              SetFunc = function(_, v)
                _G.GTLMODConfig.ColorBotWHOcc = math.floor(tonumber(v) or 2)
                if _G.RefreshWallhackColors then _G.RefreshWallhackColors() end
                return true
              end },
            { Key = "ModMenu_WH_BH_3", UI = AliasMap.Switcher, Text = "   Bot Hidden · 3",
              ExpandHandle = "ModMenu_NewWallhack",
              SwitcherText = {"Orange","Blue","Magenta","Teal"}, SwitcherValue = {8,9,10,11},
              GetFunc = function() return _G.GTLMODConfig.ColorBotWHOcc or 2 end,
              SetFunc = function(_, v)
                _G.GTLMODConfig.ColorBotWHOcc = math.floor(tonumber(v) or 2)
                if _G.RefreshWallhackColors then _G.RefreshWallhackColors() end
                return true
              end },
            { Key = "ModMenu_WH_BH_4", UI = AliasMap.Switcher, Text = "   Bot Hidden · 4",
              ExpandHandle = "ModMenu_NewWallhack",
              SwitcherText = {"Gold"}, SwitcherValue = {12},
              GetFunc = function() return _G.GTLMODConfig.ColorBotWHOcc or 2 end,
              SetFunc = function(_, v)
                _G.GTLMODConfig.ColorBotWHOcc = math.floor(tonumber(v) or 2)
                if _G.RefreshWallhackColors then _G.RefreshWallhackColors() end
                return true
              end },
            { Key = "ModMenu_BlackSky", UI = AliasMap.Switcher, Text = "NIGHT SKY", GetFunc = function() return _G.GTLMODConfig.BlackSky end, SetFunc = function(c,v)
                _G.GTLMODConfig.BlackSky = v
                pcall(function()
                    if _G.UniversalSkyController then
                        if v then
                            _G.UniversalSkyController.SetEnabled(true)
                            -- deep blue-purple night (slight black)
                            _G.UniversalSkyController.SetRGB(12, 8, 48)
                        else
                            _G.UniversalSkyController.SetEnabled(false)
                        end
                    end
                end)
                return true
              end },
        }

        -- ==================== PERFORMANCE ====================
        local StackPerformance = {
            -- ========== VIEW ==========
            { UI = AliasMap.Title, Text = "── VIEW ──" },
            { Key = "ModMenu_Ipad_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ iPad View", ExpandIndex = 0, GetFunc = function() return _G.GTLMODConfig.IpadView end, SetFunc = function(c,v) _G.GTLMODConfig.IpadView = v return true end },
            { Key = "ModMenu_Ipad_FOV", UI = AliasMap.Slider, Text = "   FOV Angle", ExpandHandle = "ModMenu_Ipad_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return (_G.GTLMODState.CustomTextData.IpadViewFOV or 120) - 80 end, SetFunc = function(c,v) _G.GTLMODState.CustomTextData.IpadViewFOV = 80 + v return true end },

            -- ========== LAG FIX ==========
            { UI = AliasMap.Title, Text = "── LAG FIX ──" },
            { Key = "ModMenu_TargetFPS", UI = AliasMap.Switcher, Text = "Target Frame Rate (FPS)",
              SwitcherText = {"60 FPS","90 FPS","120 FPS","144 FPS","165 FPS"},
              SwitcherValue = {60, 90, 120, 144, 165},
              GetFunc = function() return tonumber(_G.GTLMODConfig.TargetFPS) or 90 end,
              SetFunc = function(c, v)
                local val = tonumber(v) or 90
                if val < 60 then val = 60 end
                _G.GTLMODConfig.TargetFPS = val
                if _G.ApplyTargetFPS then pcall(_G.ApplyTargetFPS, val) end
                return true
              end },
            { Key = "ModMenu_FPSStabilizer", UI = AliasMap.Switcher, Text = "FPS Stabilizer",
              GetFunc = function() return _G.GTLMODConfig.FPSStabilizer ~= false end,
              SetFunc = function(c, v)
                _G.GTLMODConfig.FPSStabilizer = (v == true)
                if _G.ApplyFPSStabilizer then pcall(_G.ApplyFPSStabilizer, v == true) end
                return true
              end },
            { Key = "ModMenu_PotatoGraphics", UI = AliasMap.Switcher, Text = "Potato Graphics",
              GetFunc = function() return _G.GTLMODConfig.PotatoGraphics == true end,
              SetFunc = function(c, v)
                _G.GTLMODConfig.PotatoGraphics = (v == true)
                if _G.ApplyPotatoGraphics then pcall(_G.ApplyPotatoGraphics, v == true) end
                return true
              end },
            { Key = "ModMenu_CleaningSpace", UI = AliasMap.Switcher, Text = "Cleaning Space (Remove Grass)",
              GetFunc = function() return _G.GTLMODConfig.CleaningSpace == true end,
              SetFunc = function(c, v)
                _G.GTLMODConfig.CleaningSpace = (v == true)
                _G.GTLMODConfig.RemoveGrass = (v == true)
                if _G.ApplyCleaningSpace then pcall(_G.ApplyCleaningSpace, v == true) end
                return true
              end },
        }

        SettingPageDefine.ModMenu = {
            Key = "ModMenu",
            Text = "MAGOO CORE",
            UIKey = "Setting_Page_Privacy",
            Category = {
                { Key = "Cat_Supervision", Text = "SUPERVISION", Stack = StackSupervision },
                { Key = "Cat_Aim_Focus", Text = "AIM FOCUS", Stack = StackAimFocus },
                { Key = "Cat_World_Vision", Text = "WORLD VISION", Stack = StackWorldVision },
                { Key = "Cat_Performance", Text = "PERFORMANCE", Stack = StackPerformance },
            }
        }
        table.insert(SettingCatalog, SettingPageDefine.ModMenu)
    end

    local UIManager = _G.UIManager
    if UIManager and not UIManager._IsModMenuHooked then
        local old_ShowUI = UIManager.ShowUI
        UIManager.ShowUI = function(config, ...)
            local args = {...}
            local n = select('#', ...)
            if config and config.keyName and (string.find(string.lower(config.keyName), "setting_main") or string.find(string.lower(config.keyName), "setting")) then
                local catalog = args[1]
                if type(catalog) == "table" then
                    local hasModMenu = false
                    for _, page in ipairs(catalog) do
                        if type(page) == "table" and page.Key == "ModMenu" then hasModMenu = true; break end
                    end
                    if not hasModMenu then table.insert(catalog, SettingPageDefine.ModMenu) end
                end
            end
            local table_unpack = table.unpack or unpack
            return old_ShowUI(config, table_unpack(args, 1, n))
        end
        UIManager._IsModMenuHooked = true
    end
end

local function Notify(msg)
    local s = "[RJ MOD] " .. tostring(msg)
    pcall(function()
        local sh = safeImport("ScriptHelperClient")
        if sh and sh.AddOnScreenDebugMessage then
            sh.AddOnScreenDebugMessage(s, -1, 3.0, {R=1,G=1,B=0,A=1}, {X=1.2, Y=1.2})
        end
    end)
end

-- ====================================================================
-- GRAPHICS UNLOCK
-- ====================================================================
-- ====================================================================
-- GRAPHICS UNLOCK (CharacterBase-style full 165fps implementation)
-- ====================================================================
-- ====================================================================
-- GRAPHICS / LAG FIX (Target FPS, Stabilizer, Potato, Cleaning Space)
-- ====================================================================
local function _GfxGetGI()
    local gi = nil
    pcall(function()
        if slua_GameFrontendHUD and slua_GameFrontendHUD.GetGameInstance then
            gi = slua_GameFrontendHUD:GetGameInstance()
        end
    end)
    if not gi then
        pcall(function()
            local ui_util = require("client.common.ui_util")
            if ui_util and ui_util.GetGameInstance then gi = ui_util.GetGameInstance() end
        end)
    end
    return gi
end

local function _GfxExec(cmd, arg)
    pcall(function()
        local gi = _GfxGetGI()
        if gi and gi.ExecuteCMD then
            if arg ~= nil then gi:ExecuteCMD(cmd, tostring(arg))
            else gi:ExecuteCMD(cmd) end
        end
    end)
    pcall(function()
        local KSL = safeImport("KismetSystemLibrary")
        local world = (slua and slua.getWorld and slua.getWorld()) or nil
        if KSL and KSL.ExecuteConsoleCommand and world then
            if arg ~= nil then
                KSL.ExecuteConsoleCommand(world, cmd .. " " .. tostring(arg))
            else
                KSL.ExecuteConsoleCommand(world, cmd)
            end
        end
    end)
end

function _G.ApplyTargetFPS(fps)
    fps = tonumber(fps) or (_G.GTLMODConfig and _G.GTLMODConfig.TargetFPS) or 90
    if fps < 30 then fps = 30 end
    if fps > 165 then fps = 165 end
    if _G.GTLMODConfig then _G.GTLMODConfig.TargetFPS = fps end

    -- Hard engine cap (always)
    pcall(function()
        _GfxExec("t.MaxFPS", tostring(fps))
        _GfxExec("r.FrameRateLimit", tostring(fps))
        _GfxExec("r.VSync", "0")
    end)

    -- Map fps -> game FPS level (matches BGMI/Global UI levels)
    -- 2=20 3=25 4=30 5=40 6=60 7=90 8=120+ / ultra
    local level = 6
    if fps >= 165 then level = 8
    elseif fps >= 144 then level = 8
    elseif fps >= 120 then level = 8
    elseif fps >= 90 then level = 7
    elseif fps >= 60 then level = 6
    else level = 5 end

    -- Unlock high FPS in native graphics UI + force selected level
    pcall(function()
        local SettingCfg = require("client.logic.setting.setting_config")
        local GraphicSettingDB = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")
        if SettingCfg then
            if SettingCfg.TpViewValue then SettingCfg.TpViewValue.max = 160 end
            if SettingCfg.FpViewValue then SettingCfg.FpViewValue.max = 160 end
        end
        if GraphicSettingDB and GraphicSettingDB.TpViewValue then
            GraphicSettingDB.TpViewValue.max = 160
        end
    end)

    pcall(function()
        local logic_setting_graphics = require("client.slua.logic.setting.logic_setting_graphics")
        local GSC_FPS  = require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPS")
        local GSC_FPSFT = require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPSFT")
        local GraphicSettingDB = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")

        if logic_setting_graphics then
            local old_SetFPS = logic_setting_graphics.SetFPS
            function logic_setting_graphics.SetFPS(gameInstance, FPSLevel)
                if old_SetFPS then old_SetFPS(gameInstance, FPSLevel) end
                local t = (_G.GTLMODConfig and _G.GTLMODConfig.TargetFPS) or 90
                if gameInstance and gameInstance.ExecuteCMD then
                    gameInstance:ExecuteCMD("t.MaxFPS", tostring(t))
                    gameInstance:ExecuteCMD("r.FrameRateLimit", tostring(t))
                end
            end
            -- Force game to apply high FPS level now
            pcall(function()
                local gi = _GfxGetGI and _GfxGetGI() or nil
                if gi and logic_setting_graphics.SetFPS then
                    logic_setting_graphics.SetFPS(gi, level)
                end
            end)
        end

        if GSC_FPS and GSC_FPS.__inner_impl then
            local fps_impl = GSC_FPS.__inner_impl
            function fps_impl:GetMaxFPSLevel() return 8, 8 end
            function fps_impl:InitRealSupportFPS()
                local RealSupportFPS = {}
                for i = 1, 8 do RealSupportFPS[i] = {true, true} end
                if GraphicSettingDB then
                    pcall(function()
                        GraphicSettingDB:UpdateUIData(GraphicSettingDB.RealSupportFPS, RealSupportFPS, false)
                    end)
                end
                return RealSupportFPS
            end
            pcall(function()
                if type(fps_impl.InitRealSupportFPS) == "function" then
                    -- try call on any live instance is optional; patch is enough for next open
                end
            end)
        end

        if GSC_FPSFT and GSC_FPSFT.__inner_impl then
            local ft = GSC_FPSFT.__inner_impl
            pcall(function()
                if type(ft.GetMaxFPSLevel) == "function" or true then
                    function ft:GetMaxFPSLevel() return 8, 8 end
                end
            end)
        end
    end)

    -- Second pass hard set (some builds reset after SetFPS)
    pcall(function()
        _GfxExec("t.MaxFPS", tostring(fps))
        _GfxExec("r.FrameRateLimit", tostring(fps))
    end)
    return true
end

function _G.ApplyFPSStabilizer(enable)
    local on = (enable ~= false)
    if _G.GTLMODConfig then _G.GTLMODConfig.FPSStabilizer = on end
    pcall(function()
        if slua and slua.setGCParam then
            if on then slua.setGCParam(5.0E-4, 500, 50)
            else slua.setGCParam(0.001, 1000, 0) end
        end
    end)
    if on then
        _GfxExec("a.ParallelAnimEvaluation", "1")
        _GfxExec("r.GTSyncType", "1")
        _GfxExec("r.OneFrameThreadLag", "1")
        _GfxExec("r.FinishCurrentFrame", "0")
        _GfxExec("r.EnableWeaponCompTickOptimise", "1")
        _GfxExec("r.EnableWeaponGameStallIssueFix", "1")
        _GfxExec("slate.SuperFrameMiniMapUpdateRate", "3")
        _GfxExec("r.Streaming.PoolSize", "400")
        _GfxExec("r.Streaming.LimitPoolSizeToVRAM", "1")
        _GfxExec("fx.ParticlePerfStats", "0")
        _GfxExec("r.VSync", "0")
        _GfxExec("r.Touch.EnableVibration", "0")
        local fps = (_G.GTLMODConfig and _G.GTLMODConfig.TargetFPS) or 90
        _GfxExec("t.MaxFPS", tostring(fps))
        _GfxExec("r.FrameRateLimit", tostring(fps))
    end
    return true
end

function _G.ApplyPotatoGraphics(enable)
    local on = (enable == true)
    if _G.GTLMODConfig then _G.GTLMODConfig.PotatoGraphics = on end
    pcall(function()
        local ClientObj = _G.Client
        pcall(function() if not ClientObj and import then ClientObj = import("Client") end end)
        local TG = _G.TextureGroup
        pcall(function() if not TG and import then TG = import("TextureGroup") end end)

        _GfxExec("r.StaticMeshLODDistanceScale", "1.0")
        _GfxExec("r.DetailMode", on and "1" or "2")
        _GfxExec("s.EnableOverrideVerySmoothMaterial", "0")

        if on then
            _GfxExec("r.MipLODBiasFromQuality", "2")
            _GfxExec("r.EnableBiasWhenTexStreamingOff", "1")
            _GfxExec("r.MipLODBiasLowClampSize", "256")
            _GfxExec("r.Streaming.DropMips", "2")
            _GfxExec("r.Streaming.MipBias", "2")
            _GfxExec("r.MipMapLODBias", "2")
            _GfxExec("r.MaxAnisotropy", "0")
            _GfxExec("r.Streaming.PoolSize", "300")
            _GfxExec("foliage.LODDistanceScale", "0.7")
            _GfxExec("r.SkeletalMeshLODBias", "0")
            _GfxExec("r.SkeletalMeshLODDistanceScale", "1.0")
            _GfxExec("r.ShadowQuality", "0")
            _GfxExec("r.Shadow.CSM.MaxCascades", "0")
            if ClientObj and ClientObj.SetTextureGroupLODBias and TG then
                for _, name in ipairs({
                    "TEXTUREGROUP_World", "TEXTUREGROUP_WorldHD", "TEXTUREGROUP_WorldNormalMap",
                    "TEXTUREGROUP_WorldSpecular", "TEXTUREGROUP_TerrainAlbedo",
                    "TEXTUREGROUP_ProcBuilding_Face", "TEXTUREGROUP_MobileFlattened"
                }) do
                    if TG[name] ~= nil then pcall(ClientObj.SetTextureGroupLODBias, TG[name], 2) end
                end
                if TG.TEXTUREGROUP_Character then pcall(ClientObj.SetTextureGroupLODBias, TG.TEXTUREGROUP_Character, 0) end
                if TG.TEXTUREGROUP_CharacterHD then pcall(ClientObj.SetTextureGroupLODBias, TG.TEXTUREGROUP_CharacterHD, 0) end
                if TG.TEXTUREGROUP_Weapon then pcall(ClientObj.SetTextureGroupLODBias, TG.TEXTUREGROUP_Weapon, 0) end
            end
        else
            _GfxExec("r.MipLODBiasFromQuality", "0")
            _GfxExec("r.EnableBiasWhenTexStreamingOff", "0")
            _GfxExec("r.MipLODBiasLowClampSize", "0")
            _GfxExec("r.Streaming.DropMips", "0")
            _GfxExec("r.Streaming.MipBias", "0")
            _GfxExec("r.MipMapLODBias", "0")
            _GfxExec("r.MaxAnisotropy", "1")
            _GfxExec("r.Streaming.PoolSize", "400")
            _GfxExec("foliage.LODDistanceScale", "1.0")
            if ClientObj and ClientObj.SetTextureGroupLODBias and TG then
                for _, name in ipairs({
                    "TEXTUREGROUP_World", "TEXTUREGROUP_WorldHD", "TEXTUREGROUP_WorldNormalMap",
                    "TEXTUREGROUP_WorldSpecular", "TEXTUREGROUP_TerrainAlbedo",
                    "TEXTUREGROUP_ProcBuilding_Face", "TEXTUREGROUP_MobileFlattened"
                }) do
                    if TG[name] ~= nil then pcall(ClientObj.SetTextureGroupLODBias, TG[name], 0) end
                end
            end
        end
    end)
    return true
end

function _G.ApplyCleaningSpace(enable)
    local on = (enable == true)
    if _G.GTLMODConfig then
        _G.GTLMODConfig.CleaningSpace = on
        _G.GTLMODConfig.RemoveGrass = on
    end
    if on then
        _GfxExec("grass.DensityScale", "0")
        _GfxExec("foliage.DensityScale", "0")
        _GfxExec("grass.DiscardDataOnLoad", "0")
        _GfxExec("r.Fog", "0")
        _GfxExec("r.VolumetricFog", "0")
        _GfxExec("grass.flush", "1")
    else
        _GfxExec("grass.DensityScale", "1")
        _GfxExec("foliage.DensityScale", "1")
        _GfxExec("r.Fog", "1")
        _GfxExec("r.VolumetricFog", "1")
        _GfxExec("grass.flush", "1")
    end
    return true
end

local function InitializeGraphicsUnlock()
    if isExpired then return end
    local fps = (_G.GTLMODConfig and _G.GTLMODConfig.TargetFPS) or 90
    pcall(function() _G.ApplyTargetFPS(fps) end)
    if not _G.GTLMODConfig or _G.GTLMODConfig.FPSStabilizer ~= false then
        pcall(function() _G.ApplyFPSStabilizer(true) end)
    end
    if _G.GTLMODConfig and _G.GTLMODConfig.PotatoGraphics then
        pcall(function() _G.ApplyPotatoGraphics(true) end)
    end
    if _G.GTLMODConfig and _G.GTLMODConfig.CleaningSpace then
        pcall(function() _G.ApplyCleaningSpace(true) end)
    end
    if _G.GTLMODState then _G.GTLMODState.GraphicsUnlocked = true end
end


local function SafeAddMark(id, pos, z, str, size, actor)
    if not _G.GTLMODState.TrackedMarks then _G.GTLMODState.TrackedMarks = {} end
    local count = 0
    for _ in pairs(_G.GTLMODState.TrackedMarks) do count = count + 1 end
    if count >= LIMITS.MAX_TRACKED_MARKS then return nil end
    local mark = nil
    pcall(function()
        local InGameMarkTools = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")
        if InGameMarkTools and InGameMarkTools.ClientAddMapMark then
            mark = InGameMarkTools.ClientAddMapMark(id, pos, z, str, size, actor)
            if mark then _G.GTLMODState.TrackedMarks[mark] = true end
        end
    end)
    return mark
end

local function SafeRemoveMark(mark)
    if not mark then return end
    pcall(function()
        local InGameMarkTools = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")
        if InGameMarkTools and InGameMarkTools.HideMapMark then InGameMarkTools.HideMapMark(mark) end
        if InGameMarkTools and InGameMarkTools.RemoveMapMark then InGameMarkTools.RemoveMapMark(mark) end
    end)
    if _G.GTLMODState.TrackedMarks then _G.GTLMODState.TrackedMarks[mark] = nil end
end

local function GetSafeEnemyKey(enemy)
    if Valid(enemy) then
        if enemy.PlayerKey then return tostring(enemy.PlayerKey) end
        if type(enemy.GetUniqueID) == "function" then return tostring(enemy:GetUniqueID()) end
    end
    return tostring(enemy)
end

-- ====================================================================
-- COUNTER
-- ====================================================================

-- ====================================================================
-- MAGOO REDBOX COUNTER (animated red/white — CharacterBase style)
-- ====================================================================
local RJCounter = {
    Canvas = nil, RealFrame = nil, RealBg = nil, RealDot = nil, RealLabel = nil, RealText = nil,
    BotFrame = nil, BotBg = nil, BotDot = nil, BotLabel = nil, BotText = nil,
    LastRealText = "", LastBotText = "", Created = false, BotCache = {}, Enabled = true,
}
_G.RJCounter = RJCounter

function RJCounter.SetEnabled(on)
    -- disabled — Star RedBoxOverlay is the only Player/Bot counter
    RJCounter.Enabled = false
    if RJCounter.Created then
        local Items = { RJCounter.RealFrame, RJCounter.RealBg, RJCounter.RealDot, RJCounter.RealLabel, RJCounter.RealText,
                        RJCounter.BotFrame, RJCounter.BotBg, RJCounter.BotDot, RJCounter.BotLabel, RJCounter.BotText }
        for _, w in ipairs(Items) do
            if w and Valid(w) then pcall(function() w:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end) end
        end
    end
    -- MagooRedBox removed; Star RedBoxOverlay only
end

local function CounterRainbowColor(t, phase)
    phase = phase or 0
    local r = math.sin(t * 1.8 + phase) * 0.5 + 0.5
    local g = math.sin(t * 1.8 + phase + 2.094) * 0.5 + 0.5
    local b = math.sin(t * 1.8 + phase + 4.188) * 0.5 + 0.5
    local FC = safeImport("LinearColor")
    if not FC then return {R=255, G=255, B=255, A=255} end
    return FC(0.25 + r * 0.75, 0.25 + g * 0.75, 0.25 + b * 0.75, 1.0)
end

local function CounterGetCanvas()
    local canvas = nil
    pcall(function()
        local T = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
        local M = T.GetMainControlBaseUI()
        if M then
            if M.CanvasPanel_0 and Game:IsValid(M.CanvasPanel_0) then canvas = M.CanvasPanel_0
            elseif M.CanvasPanel_42 and Game:IsValid(M.CanvasPanel_42) then canvas = M.CanvasPanel_42 end
        end
    end)
    return canvas
end

local function CounterDetectBot(Character)
    if not Valid(Character) then return nil end
    local CacheKey = nil
    pcall(function()
        if Character.PlayerKey then CacheKey = tostring(Character.PlayerKey)
        elseif type(Character.GetUniqueID) == "function" then CacheKey = tostring(Character:GetUniqueID()) end
    end)
    if not CacheKey then CacheKey = tostring(Character) end
    if RJCounter.BotCache[CacheKey] ~= nil then return RJCounter.BotCache[CacheKey] end

    local IsBot = false
    local Checked = false
    pcall(function()
        if Game and type(Game.IsAI) == "function" then
            local NativeAI = Game:IsAI(Character)
            if NativeAI ~= nil then Checked = true; if NativeAI == true then IsBot = true end end
        end
        if Character.bIsAI ~= nil then Checked = true; if Character.bIsAI == true then IsBot = true end end
        if Character.IsAI ~= nil then Checked = true; if Character.IsAI == true then IsBot = true end end
        if type(Character.IsBot) == "function" then
            Checked = true
            local Result = Character:IsBot()
            if Result == true then IsBot = true end
        end
        local PS = Character.PlayerState or (type(Character.GetPlayerState) == "function" and Character:GetPlayerState())
        if Valid(PS) then
            Checked = true
            if PS.bIsABot == true or PS.bIsBot == true then IsBot = true end
            if type(PS.IsBot) == "function" and PS:IsBot() then IsBot = true end
        end
        if not IsBot then
            local Name = Character.PlayerName or (type(Character.GetPlayerName) == "function" and Character:GetPlayerName()) or ""
            if Name ~= "" and (Name:find("Cobra") or Name:find("Target") or Name:find("bot_") or Name:find("b_")) then
                IsBot = true; Checked = true
            end
        end
    end)
    if IsBot then RJCounter.BotCache[CacheKey] = true; return true end
    if Checked then RJCounter.BotCache[CacheKey] = false; return false end
    return nil
end

local function CounterCreateUI()
    if RJCounter.RealText and Valid(RJCounter.RealText) then return true end
    local canvas = CounterGetCanvas()
    if not canvas or not Game:IsValid(canvas) then return false end
    RJCounter.Canvas = canvas

    local boxW, boxH, gap = 145, 36, 8
    local framePad = 2
    -- [FIXED] Position: horizontally centered, vertically 9% from top (below ESP line start).
    -- ESP lines go from player (screen center-bottom) up to enemies; counter sits in the
    -- upper-center zone where the ESP line tips cluster.
    local vpW, vpH = 1920, 1080  -- safe defaults
    local centerX, topY = vpW * 0.5 - (boxW * 2 + gap) * 0.5, math.floor(vpH * 0.09)
    pcall(function()
        local GS = safeImport("GameplayStatics")
        local pc2 = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if false then
            vpW = 1920
            vpH = 1080
            centerX = vpW * 0.5 - (boxW * 2 + gap) * 0.5
            topY = math.max(55, math.floor(vpH * 0.09))
        elseif GS and pc2 and GS.GetViewportSize then
            local sx, sy = GS.GetViewportSize(pc2)
            if type(sx) == "number" and sx > 10 then
                centerX = sx * 0.5 - (boxW * 2 + gap) * 0.5
                topY = math.max(55, math.floor((sy or 1080) * 0.09))
            elseif type(sx) == "table" and sx.X and sx.X > 10 then
                centerX = sx.X * 0.5 - (boxW * 2 + gap) * 0.5
                topY = math.max(55, math.floor((sx.Y or 1080) * 0.09))
            end
        elseif pc2 and pc2.GetViewportSize then
            local FVec2 = _G.FVector2D or safeImport("Vector2D")
            local vs = FVec2 and FVec2(0,0) or {X=0,Y=0}
            pc2:GetViewportSize(vs)
            if vs and vs.X and vs.X > 10 then
                centerX = vs.X * 0.5 - (boxW * 2 + gap) * 0.5
                topY = math.max(55, math.floor(vs.Y * 0.09))
            end
        end
    end)
    local FLC = safeImport("LinearColor")
    local FSlate = safeImport("SlateColor") or safeImport("/Script/SlateCore.SlateColor")

    if not FLC then return false end

    pcall(function()
        RJCounter.RealFrame = CGame:NewObjectFromPath("/Script/UMG.Border", canvas)
        if Valid(RJCounter.RealFrame) then
            RJCounter.RealFrame:SetBrushColor(FLC(1.0, 0.2, 0.2, 1.0))
            local s = canvas:AddChildToCanvas(RJCounter.RealFrame)
            if s then s:SetAutoSize(false); s:SetPosition(FVector2D(centerX - framePad, topY - framePad)); s:SetSize(FVector2D(boxW + framePad*2, boxH + framePad*2)); s:SetAlignment(FVector2D(0,0)); s:SetZOrder(4999) end
        end
        RJCounter.RealBg = CGame:NewObjectFromPath("/Script/UMG.Border", canvas)
        if Valid(RJCounter.RealBg) then
            RJCounter.RealBg:SetBrushColor(FLC(0.05, 0.02, 0.02, 0.92))
            local s = canvas:AddChildToCanvas(RJCounter.RealBg)
            if s then s:SetAutoSize(false); s:SetPosition(FVector2D(centerX, topY)); s:SetSize(FVector2D(boxW, boxH)); s:SetAlignment(FVector2D(0,0)); s:SetZOrder(5000) end
        end
        RJCounter.RealDot = CGame:NewObjectFromPath("/Script/UMG.Border", canvas)
        if Valid(RJCounter.RealDot) then
            RJCounter.RealDot:SetBrushColor(FLC(1.0, 0.2, 0.2, 1.0))
            local s = canvas:AddChildToCanvas(RJCounter.RealDot)
            if s then s:SetAutoSize(false); s:SetPosition(FVector2D(centerX + 10, topY + 13)); s:SetSize(FVector2D(10, 10)); s:SetAlignment(FVector2D(0,0)); s:SetZOrder(5001) end
        end
        RJCounter.RealLabel = CGame:NewObjectFromPath("/Script/UMG.TextBlock", canvas)
        if Valid(RJCounter.RealLabel) then
            RJCounter.RealLabel:SetText("REAL")
            if FSlate then RJCounter.RealLabel:SetColorAndOpacity(FSlate(FLC(0.85, 0.85, 0.9, 1.0))) else RJCounter.RealLabel:SetColorAndOpacity(FLC(0.85, 0.85, 0.9, 1.0)) end
            local f = RJCounter.RealLabel.Font
            if f then f.Size = 13; RJCounter.RealLabel:SetFont(f) end
            RJCounter.RealLabel:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            local s = canvas:AddChildToCanvas(RJCounter.RealLabel)
            if s then s:SetAutoSize(false); s:SetAlignment(FVector2D(0, 0.5)); s:SetPosition(FVector2D(centerX + 28, topY + boxH/2)); s:SetSize(FVector2D(60, boxH)); s:SetZOrder(5002) end
        end
        RJCounter.RealText = CGame:NewObjectFromPath("/Script/UMG.TextBlock", canvas)
        if Valid(RJCounter.RealText) then
            RJCounter.RealText:SetText("0")
            if FSlate then RJCounter.RealText:SetColorAndOpacity(FSlate(FLC(1,1,1,1))) else RJCounter.RealText:SetColorAndOpacity(FLC(1,1,1,1)) end
            local f = RJCounter.RealText.Font
            if f then f.Size = 20; RJCounter.RealText:SetFont(f) end
            RJCounter.RealText:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            local s = canvas:AddChildToCanvas(RJCounter.RealText)
            if s then s:SetAutoSize(false); s:SetAlignment(FVector2D(1, 0.5)); s:SetPosition(FVector2D(centerX + boxW - 12, topY + boxH/2)); s:SetSize(FVector2D(60, boxH)); s:SetZOrder(5002) end
        end
        RJCounter.BotFrame = CGame:NewObjectFromPath("/Script/UMG.Border", canvas)
        if Valid(RJCounter.BotFrame) then
            RJCounter.BotFrame:SetBrushColor(FLC(0.2, 1.0, 0.2, 1.0))
            local s = canvas:AddChildToCanvas(RJCounter.BotFrame)
            if s then s:SetAutoSize(false); s:SetPosition(FVector2D(centerX + boxW + gap - framePad, topY - framePad)); s:SetSize(FVector2D(boxW + framePad*2, boxH + framePad*2)); s:SetAlignment(FVector2D(0,0)); s:SetZOrder(4999) end
        end
        RJCounter.BotBg = CGame:NewObjectFromPath("/Script/UMG.Border", canvas)
        if Valid(RJCounter.BotBg) then
            RJCounter.BotBg:SetBrushColor(FLC(0.02, 0.05, 0.02, 0.92))
            local s = canvas:AddChildToCanvas(RJCounter.BotBg)
            if s then s:SetAutoSize(false); s:SetPosition(FVector2D(centerX + boxW + gap, topY)); s:SetSize(FVector2D(boxW, boxH)); s:SetAlignment(FVector2D(0,0)); s:SetZOrder(5000) end
        end
        RJCounter.BotDot = CGame:NewObjectFromPath("/Script/UMG.Border", canvas)
        if Valid(RJCounter.BotDot) then
            RJCounter.BotDot:SetBrushColor(FLC(0.2, 1.0, 0.2, 1.0))
            local s = canvas:AddChildToCanvas(RJCounter.BotDot)
            if s then s:SetAutoSize(false); s:SetPosition(FVector2D(centerX + boxW + gap + 10, topY + 13)); s:SetSize(FVector2D(10, 10)); s:SetAlignment(FVector2D(0,0)); s:SetZOrder(5001) end
        end
        RJCounter.BotLabel = CGame:NewObjectFromPath("/Script/UMG.TextBlock", canvas)
        if Valid(RJCounter.BotLabel) then
            RJCounter.BotLabel:SetText("BOT")
            if FSlate then RJCounter.BotLabel:SetColorAndOpacity(FSlate(FLC(0.85, 0.85, 0.9, 1.0))) else RJCounter.BotLabel:SetColorAndOpacity(FLC(0.85, 0.85, 0.9, 1.0)) end
            local f = RJCounter.BotLabel.Font
            if f then f.Size = 13; RJCounter.BotLabel:SetFont(f) end
            RJCounter.BotLabel:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            local s = canvas:AddChildToCanvas(RJCounter.BotLabel)
            if s then s:SetAutoSize(false); s:SetAlignment(FVector2D(0, 0.5)); s:SetPosition(FVector2D(centerX + boxW + gap + 28, topY + boxH/2)); s:SetSize(FVector2D(60, boxH)); s:SetZOrder(5002) end
        end
        RJCounter.BotText = CGame:NewObjectFromPath("/Script/UMG.TextBlock", canvas)
        if Valid(RJCounter.BotText) then
            RJCounter.BotText:SetText("0")
            if FSlate then RJCounter.BotText:SetColorAndOpacity(FSlate(FLC(1,1,1,1))) else RJCounter.BotText:SetColorAndOpacity(FLC(1,1,1,1)) end
            local f = RJCounter.BotText.Font
            if f then f.Size = 20; RJCounter.BotText:SetFont(f) end
            RJCounter.BotText:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            local s = canvas:AddChildToCanvas(RJCounter.BotText)
            if s then s:SetAutoSize(false); s:SetAlignment(FVector2D(1, 0.5)); s:SetPosition(FVector2D(centerX + boxW + gap + boxW - 12, topY + boxH/2)); s:SetSize(FVector2D(60, boxH)); s:SetZOrder(5002) end
        end
    end)
    RJCounter.Created = true
    return RJCounter.RealText ~= nil
end

local function GetPlayerCharacterLocal()
    local p = nil
    pcall(function() p = GameplayData.GetPlayerCharacter() end)
    return p
end

local function RJCounterTick()
    pcall(function()
        if not _G.GTLMODConfig.CounterEnabled then return end
        if not CounterCreateUI() then return end
        local Now = os.clock()
        if Valid(RJCounter.RealFrame) then pcall(function() RJCounter.RealFrame:SetBrushColor(CounterRainbowColor(Now, 0)) end) end
        if Valid(RJCounter.BotFrame) then pcall(function() RJCounter.BotFrame:SetBrushColor(CounterRainbowColor(Now, 1.5)) end) end

        local localPlayer = GetPlayerCharacterLocal()
        if not slua.isValid(localPlayer) then return end
        local myTeam = 0
        pcall(function() myTeam = localPlayer.TeamID or localPlayer:GetTeamID() or 0 end)

        local allCharacters = {}
        if GameplayData.GetAllPlayerCharacters then
            allCharacters = GameplayData.GetAllPlayerCharacters()
        elseif GameplayData.GameCharacters then
            for _, c in pairs(GameplayData.GameCharacters) do table.insert(allCharacters, c) end
        end

        local RealCount = 0
        local BotCount = 0
        for _, c in pairs(allCharacters) do
            if Valid(c) and c ~= localPlayer then
                local alive = false
                pcall(function()
                    if c.Health and c.Health > 0 then alive = true
                    elseif type(c.IsAlive) == "function" and c:IsAlive() then alive = true end
                end)
                local tTeam = 0
                pcall(function() tTeam = c.TeamID or (type(c.GetTeamID) == "function" and c:GetTeamID()) or 0 end)
                if alive and tTeam ~= myTeam then
                    local isBot = CounterDetectBot(c)
                    if isBot == true then BotCount = BotCount + 1
                    elseif isBot == false then RealCount = RealCount + 1 end
                end
            end
        end
        local NewRealText = tostring(RealCount)
        local NewBotText = tostring(BotCount)
        if NewRealText ~= RJCounter.LastRealText then
            RJCounter.LastRealText = NewRealText
            if Valid(RJCounter.RealText) then RJCounter.RealText:SetText(NewRealText) end
        end
        if NewBotText ~= RJCounter.LastBotText then
            RJCounter.LastBotText = NewBotText
            if Valid(RJCounter.BotText) then RJCounter.BotText:SetText(NewBotText) end
        end
    end)
end

-- ====================================================================
-- AIMBOT
-- ====================================================================
_G.GetEnemyTargetsFromActors = function(radius)
    local result = {}
    local player = GameplayData.GetPlayerCharacter()
    if not slua.isValid(player) then return result end

    local allCharacters = {}
    if GameplayData.GetAllPlayerCharacters then
        allCharacters = GameplayData.GetAllPlayerCharacters()
    elseif GameplayData.GameCharacters then
        for _, char in pairs(GameplayData.GameCharacters) do table.insert(allCharacters, char) end
    end

    local myTeam = 0
    pcall(function() myTeam = player:GetTeamID() or player.TeamID or 0 end)

    for _, actor in pairs(allCharacters) do
        if slua.isValid(actor) and actor ~= player then
            local isAlive = true
            pcall(function()
                if type(actor.IsAlive) == "function" then
                    isAlive = actor:IsAlive()
                elseif actor.HealthStatus ~= nil then
                    isAlive = (actor.HealthStatus ~= 2)
                elseif actor.bIsDead ~= nil then
                    isAlive = not actor.bIsDead
                end
            end)
            if isAlive then
                local teamId = -1
                pcall(function()
                    if type(actor.GetTeamID) == "function" then teamId = actor:GetTeamID()
                    elseif actor.TeamID ~= nil then teamId = actor.TeamID end
                end)
                if teamId ~= myTeam then
                    local dist = 999999
                    pcall(function() dist = player:GetDistanceTo(actor) end)
                    if dist <= radius then table.insert(result, actor) end
                end
            end
        end
    end
    return result
end

local function GetTargetBonePos(target, boneName, fallbackZ)
    local pos = nil
    if type(target.GetBonePos) == "function" then
        pcall(function() pos = target:GetBonePos(boneName, {X=0, Y=0, Z=0}) end)
    end
    if not pos or (pos.X == 0 and pos.Y == 0 and pos.Z == 0) then
        pcall(function()
            if slua.isValid(target.Mesh) and type(target.Mesh.GetSocketLocation) == "function" then
                pos = target.Mesh:GetSocketLocation(boneName)
            end
        end)
    end
    if not pos or (pos.X == 0 and pos.Y == 0 and pos.Z == 0) then
        pcall(function()
            if type(target.GetSocketLocation) == "function" then
                pos = target:GetSocketLocation(boneName)
            end
        end)
    end
    if not pos or (pos.X == 0 and pos.Y == 0 and pos.Z == 0) then
        pcall(function()
            if type(target.K2_GetActorLocation) == "function" then
                pos = target:K2_GetActorLocation()
                if pos then pos.Z = pos.Z + (fallbackZ or 70) end
            end
        end)
    end
    return pos
end

local function TrimCache(cache, maxSize, now)
    if not cache then return end
    local count = 0
    for _ in pairs(cache) do count = count + 1 end
    if count <= maxSize then return end
    local toRemove = {}
    for k, v in pairs(cache) do
        if type(v) == "table" and v.time and (now - v.time) > 30 then
            table.insert(toRemove, k)
        end
    end
    for _, k in ipairs(toRemove) do cache[k] = nil end
    count = 0
    for _ in pairs(cache) do count = count + 1 end
    if count > maxSize then
        for k in pairs(cache) do cache[k] = nil end
    end
end

_G.AimTouch = function()
    if not _G.GTLMODConfig.AimTouchEnable then return end
    if not _G.GTLMODState.AimDebugErr then _G.GTLMODState.AimDebugErr = "starting" end

    local player = GameplayData.GetPlayerCharacter()
    if not slua.isValid(player) then _G.GTLMODState.AimLastFail = "no player"; return end

    local pc = player:GetPlayerControllerSafety()
    if not slua.isValid(pc) then _G.GTLMODState.AimLastFail = "no pc"; return end

    local isFiring = player.bIsWeaponFiring
    local isADS = player.bIsGunADS

    local weapon = player.WeaponManagerComponent and player.WeaponManagerComponent.CurrentWeaponReplicated
    if not weapon and type(player.GetCurrentShootWeapon) == "function" then
        weapon = player:GetCurrentShootWeapon()
    end

    local isShotgun = false
    local isSniper = false
    local currentAmmo = 1

    if slua.isValid(weapon) then
        local wID = type(weapon.GetWeaponID) == "function" and weapon:GetWeaponID() or 0
        local wName = type(weapon.GetWeaponName) == "function" and weapon:GetWeaponName() or ""
        if (wID >= 1030000 and wID < 1040000) or wName:find("S686") or wName:find("S1897") or wName:find("S12") or wName:find("DBS") or wName:find("M1014") then
            isShotgun = true
        end
        if wName:find("Kar98") or wName:find("M24") or wName:find("AWM") or wName:find("Mosin") or wName:find("Win94") or wName:find("AMR") or wName:find("SKS") or wName:find("SLR") or wName:find("Mini") or wName:find("Mk14") or wName:find("QBU") or wName:find("Mk12") or wName:find("VSS") then
            isSniper = true
        end
        if type(weapon.GetCurrentAmmo) == "function" then
            currentAmmo = weapon:GetCurrentAmmo()
        elseif weapon.CurrentAmmo ~= nil then
            currentAmmo = weapon.CurrentAmmo
        end
    end

    if _G.GTLMODState.IsAutoFiring then
        pcall(function()
            player.bIsWeaponFiring = false
            if type(player.SetIsWeaponFiring) == "function" then player:SetIsWeaponFiring(false) end
            if slua.isValid(pc) and type(pc.SetIsWeaponFiring) == "function" then pc:SetIsWeaponFiring(false) end
            local wepMgr = player.WeaponManagerComponent
            if slua.isValid(wepMgr) then wepMgr.bIsWeaponFiring = false end
        end)
        _G.GTLMODState.IsAutoFiring = false
    end

    if isShotgun and currentAmmo <= 0 then _G.GTLMODState.AimLastFail = "shotgun no ammo"; return end

    local cond = 2
    local boneIdx = 1
    local speedVal = 50
    local fovVal = 30
    local maxDistMeters = 50
    local useVisCheck = _G.GTLMODConfig.AimTouchVisCheck
    local igKnock = _G.GTLMODConfig.AimTouchIgKnock
    local igBot = _G.GTLMODConfig.AimTouchIgBot

    if isShotgun then
        cond = 2; boneIdx = 2; speedVal = 90; fovVal = 32; maxDistMeters = 30
    elseif isADS then
        if isSniper then
            cond = 2; boneIdx = 1; speedVal = 85; fovVal = 28; maxDistMeters = 400
        else
            cond = 1; boneIdx = 2; speedVal = 85; fovVal = 28; maxDistMeters = 300
        end
    else
        cond = 1; boneIdx = 1; speedVal = 85; fovVal = 28; maxDistMeters = 250
    end

    if cond == 1 and not isFiring then _G.GTLMODState.AimLastFail = "not firing"; return end

    local currentMaxDist = maxDistMeters * 100
    local enemies = _G.GetEnemyTargetsFromActors(currentMaxDist)
    if not enemies or #enemies == 0 then _G.GTLMODState.AimLastFail = "no enemies"; return end

    local FVector2D = GetFV2()
    local UGameplayStatics = GetUGS()
    local KismetMathLibrary = GetKML()
    if not FVector2D or not UGameplayStatics or not KismetMathLibrary then return end

    local camManager = UGameplayStatics.GetPlayerCameraManager(pc, 0)
    if not slua.isValid(camManager) then _G.GTLMODState.AimLastFail = "no camManager"; return end
    local camLoc = camManager:GetCameraLocation()
    if not camLoc then _G.GTLMODState.AimLastFail = "no camLoc"; return end

    local ui_util = GetUIUtil()
    if not ui_util then _G.GTLMODState.AimLastFail = "no ui_util"; return end
    local viewportSize = ui_util.GetViewportSize()
    if not viewportSize then _G.GTLMODState.AimLastFail = "no viewport"; return end

    local centerX = viewportSize.X * 0.5
    local centerY = viewportSize.Y * 0.5
    local FOV_RADIUS = (fovVal / 100.0) * (viewportSize.X / 2.0)

    local bestTarget = nil
    local bestScore = 99999999
    local selBoneName = "head"
    if boneIdx == 2 then selBoneName = "spine_03"
    elseif boneIdx == 3 then selBoneName = "spine_01"
    elseif boneIdx == 4 then selBoneName = "pelvis" end

    local now = os.clock()
    _G.BotStatusCache = _G.BotStatusCache or {}
    _G.AimTouchVisCache = _G.AimTouchVisCache or {}
    if not _G.LastCacheTrim or (now - _G.LastCacheTrim) > 15 then
        _G.LastCacheTrim = now
        TrimCache(_G.BotStatusCache, LIMITS.MAX_BOT_CACHE, now)
        TrimCache(_G.AimTouchVisCache, LIMITS.MAX_VIS_CACHE, now)
    end

    for i, target in ipairs(enemies) do
        if slua.isValid(target) then
            pcall(function()
                if slua.isValid(target.Mesh) then target.Mesh.MeshComponentUpdateFlag = 0 end
            end)

            local skip = false
            if igKnock and target.HealthStatus == 1 then skip = true end

            if not skip and igBot then
                local tId = type(target.GetUniqueID) == "function" and target:GetUniqueID() or tostring(target)
                local cachedBot = _G.BotStatusCache[tId]
                if cachedBot == nil then
                    cachedBot = false
                    if target.bIsAI == true or target.IsAI == true or target.bIsAi == true then cachedBot = true end
                    if not cachedBot then
                        if target.AIData ~= nil or target.AIController ~= nil or target.bIsAIActor == true then cachedBot = true end
                        if not cachedBot and target.PlayerAIType ~= nil and target.PlayerAIType ~= 0 then cachedBot = true end
                    end
                    if not cachedBot then
                        local pState = target.PlayerState
                        if slua.isValid(pState) then
                            if pState.bIsABot or pState.bIsBot or pState.IsBot or pState.bIsAI then cachedBot = true end
                            if not cachedBot then
                                local uid = pState.Uid or pState.UID or pState.PlayerId or pState.PlayerID
                                if uid ~= nil and (uid == 0 or uid == "0") then cachedBot = true end
                            end
                        end
                    end
                    if not cachedBot and type(target.IsBot) == "function" then
                        local ok, r = pcall(function() return target:IsBot() end)
                        if ok and r then cachedBot = true end
                    end
                    _G.BotStatusCache[tId] = cachedBot
                end
                if cachedBot then skip = true end
            end

            if not skip and useVisCheck then
                local tId = type(target.GetUniqueID) == "function" and target:GetUniqueID() or tostring(target)
                local cacheEntry = _G.AimTouchVisCache[tId]
                if not cacheEntry or (now - cacheEntry.time) > 0.2 then
                    local isHidden = true
                    pcall(function() if pc:LineOfSightTo(target) then isHidden = false end end)
                    _G.AimTouchVisCache[tId] = { hidden = isHidden, time = now }
                    cacheEntry = _G.AimTouchVisCache[tId]
                end
                if cacheEntry.hidden then skip = true end
            end

            if not skip then
                local fallbackZ = (boneIdx == 1) and 70 or (boneIdx == 2) and 40 or (boneIdx == 3) and 20 or 0
                local tPos = GetTargetBonePos(target, selBoneName, fallbackZ)
                if tPos and (tPos.X ~= 0 or tPos.Y ~= 0) then
                    local screen = FVector2D()
                    local success = pc:ProjectWorldLocationToScreen(tPos, screen, false)
                    if success and screen.X > 0 and screen.Y > 0 then
                        local dx = screen.X - centerX
                        local dy = screen.Y - centerY
                        local distScreen = math.sqrt(dx*dx + dy*dy)
                        if distScreen <= FOV_RADIUS then
                            if distScreen < bestScore then
                                bestScore = distScreen
                                bestTarget = target
                            end
                        end
                    end
                end
            end
        end
    end

    if not slua.isValid(bestTarget) then _G.GTLMODState.AimLastFail = "no best target in FOV"; return end

    local fallbackZ2 = (boneIdx == 1) and 70 or (boneIdx == 2) and 40 or (boneIdx == 3) and 20 or 0
    local finalBonePos = GetTargetBonePos(bestTarget, selBoneName, fallbackZ2)
    if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0) then _G.GTLMODState.AimLastFail = "no final bone pos"; return end

    local rot = KismetMathLibrary.FindLookAtRotation(camLoc, finalBonePos)
    if not rot then _G.GTLMODState.AimLastFail = "no rot"; return end

    local currentRot = pc:GetControlRotation()
    if not currentRot then _G.GTLMODState.AimLastFail = "no currentRot"; return end

    local deltaYaw = rot.Yaw - currentRot.Yaw
    local deltaPitch = rot.Pitch - currentRot.Pitch

    if isADS then
        local camRot = nil
        if type(camManager.GetCameraRotation) == "function" then camRot = camManager:GetCameraRotation() end
        if camRot then
            deltaYaw = deltaYaw - (camRot.Yaw - currentRot.Yaw)
            deltaPitch = deltaPitch - (camRot.Pitch - currentRot.Pitch)
        end
    end

    if deltaYaw > 180 then deltaYaw = deltaYaw - 360 end
    if deltaYaw < -180 then deltaYaw = deltaYaw + 360 end
    if deltaPitch > 180 then deltaPitch = deltaPitch - 360 end
    if deltaPitch < -180 then deltaPitch = deltaPitch + 360 end

    -- Smooth factor: natural-feeling movement speed with proper scaling
    -- Base: speedVal/100 * 0.40 gives a smooth, responsive feel.
    -- Minimum 0.03 prevents micro-jitter that looks laggy.
    local smoothFactor = (speedVal >= 100) and 1.0 or math.max(0.03, (speedVal / 100.0) * 0.40)

    -- Adaptive smooth: when very close to target (fine-tune zone < 5°), slow down
    -- so the aim rests naturally on target without oscillating.
    local dist2d = math.sqrt(deltaYaw*deltaYaw + deltaPitch*deltaPitch)
    if dist2d < 5.0 then
        -- Fine-tune zone: reduce factor proportionally so we glide in, not snap
        local fineTuneFactor = dist2d / 5.0  -- 0..1
        smoothFactor = smoothFactor * (0.35 + fineTuneFactor * 0.65)
    elseif dist2d > 40.0 then
        -- Large correction zone: boost slightly so we reach target within 2-3 frames
        smoothFactor = math.min(1.0, smoothFactor * 1.4)
    end

    -- Pitch correction: counteract RecoilKick upward drift when scoped.
    -- Without small crosshair, RecoilKickADS is active and pushes barrel up each frame.
    -- We apply a stronger pitch pull to stay on target despite recoil.
    local pitchFactor = smoothFactor
    if isADS then
        local absDeltaPitch = math.abs(deltaPitch)
        if absDeltaPitch < 20 then
            -- Close to target pitch: use strong correction to hold on target
            pitchFactor = math.min(1.0, smoothFactor * 2.5)
        elseif absDeltaPitch < 45 then
            -- Medium distance: moderate boost
            pitchFactor = math.min(1.0, smoothFactor * 1.6)
        else
            -- Far off: normal smooth (avoid jarring snap)
            pitchFactor = smoothFactor
        end
    else
        -- Hipfire: slight pitch boost for snappier vertical tracking
        pitchFactor = math.min(1.0, smoothFactor * 1.2)
    end

    local finalPitch = currentRot.Pitch + (deltaPitch * pitchFactor)
    local finalYaw   = currentRot.Yaw   + (deltaYaw   * smoothFactor)
    local finalRot = { Pitch = finalPitch, Yaw = finalYaw, Roll = 0 }

    -- SetControlRotation: only push toward target, player touch still wins.
    local okRot = pcall(function() pc:SetControlRotation(finalRot, "AimTouch") end)
    if not okRot then
        pcall(function() pc:SetControlRotation(finalRot) end)
    end

    _G.GTLMODState.AimLastFail = "OK"

    if isShotgun then
        pcall(function()
            local distToTarget = player:GetDistanceTo(bestTarget) / 100
            if distToTarget <= maxDistMeters then
                player.bIsWeaponFiring = true
                if type(player.SetIsWeaponFiring) == "function" then player:SetIsWeaponFiring(true) end
                if slua.isValid(pc) and type(pc.SetIsWeaponFiring) == "function" then pc:SetIsWeaponFiring(true) end
                local wepMgr = player.WeaponManagerComponent
                if slua.isValid(wepMgr) then wepMgr.bIsWeaponFiring = true end
                local currentWep = player:GetCurrentWeapon()
                if slua.isValid(currentWep) and type(currentWep.StartFire) == "function" then currentWep:StartFire() end
                _G.GTLMODState.IsAutoFiring = true
            end
        end)
    end
end

-- ====================================================================
-- MAIN LOOP
-- ====================================================================


-- ====================================================================
-- ITEM ESP (CharacterBase-style, optimized scan)
-- ====================================================================
_G.AppliedItemESP = _G.AppliedItemESP or {}
_G.CachedItems = _G.CachedItems or {}
_G.LastScanItemTime = 0
-- Weak set of actors we dyed so we can clear glow when Item ESP is turned off
_G._ItemDyedActors = _G._ItemDyedActors or setmetatable({}, { __mode = "k" })
_G._ItemESP_ConsoleReady = false

local ITEM_NAME_MAP = {
    -- ===== Classic short TypeSpecificIDs =====
    -- AR
    [101001] = {"AKM", {R=255,G=80,B=80}},
    [101002] = {"M16A4", {R=255,G=200,B=80}},
    [101003] = {"SCAR-L", {R=80,G=255,B=120}},
    [101004] = {"M416", {R=80,G=180,B=255}},
    [101005] = {"Groza", {R=255,G=50,B=50}},
    [101006] = {"AUG", {R=100,G=200,B=255}},
    [101007] = {"QBZ", {R=200,G=200,B=80}},
    [101008] = {"M762", {R=255,G=120,B=60}},
    [101009] = {"Mk47", {R=255,G=150,B=50}},
    [101010] = {"G36C", {R=150,G=255,B=150}},
    [101011] = {"Mk47 Mutant", {R=255,G=140,B=40}},
    [101012] = {"ACE32", {R=255,G=100,B=100}},
    -- 9-digit config AR IDs (from data files)
    [101001002] = {"M416", {R=80,G=180,B=255}},
    [101001003] = {"SCAR-L", {R=80,G=255,B=120}},
    [101001004] = {"AKM", {R=255,G=80,B=80}},
    [101001005] = {"M16A4", {R=255,G=200,B=80}},
    [101001007] = {"Groza", {R=255,G=50,B=50}},
    [101001008] = {"AUG", {R=100,G=200,B=255}},
    [101001009] = {"QBZ", {R=200,G=200,B=80}},
    [101001021] = {"M762", {R=255,G=120,B=60}},
    [101001023] = {"Mk47 Mutant", {R=255,G=140,B=40}},
    [101001024] = {"G36C", {R=150,G=255,B=150}},
    [101001027] = {"FAMAS", {R=180,G=220,B=100}},
    [101001031] = {"ACE32", {R=255,G=100,B=100}},
    [101001032] = {"Honey Badger", {R=200,G=160,B=80}},
    -- alt client block AR
    [907000010] = {"M416", {R=80,G=180,B=255}},
    -- SMG short
    [102001] = {"UZI", {R=180,G=255,B=80}},
    [102002] = {"UMP45", {R=180,G=200,B=255}},
    [102003] = {"Vector", {R=255,G=80,B=200}},
    [102004] = {"Thompson", {R=200,G=150,B=80}},
    [102005] = {"Bizon", {R=150,G=200,B=150}},
    [102007] = {"MP5K", {R=100,G=255,B=200}},
    [102105] = {"P90", {R=255,G=100,B=255}},
    -- Sniper short
    [103001] = {"Kar98k", {R=255,G=60,B=60}},
    [103002] = {"M24", {R=255,G=40,B=40}},
    [103003] = {"AWM", {R=255,G=20,B=20}},
    [103004] = {"SKS", {R=255,G=120,B=80}},
    [103005] = {"VSS", {R=180,G=180,B=255}},
    [103006] = {"Mini14", {R=200,G=200,B=100}},
    [103007] = {"Mk14", {R=255,G=80,B=40}},
    [103008] = {"Win94", {R=200,G=160,B=80}},
    [103009] = {"SLR", {R=255,G=100,B=60}},
    [103010] = {"QBU", {R=180,G=220,B=100}},
    [103011] = {"Mosin", {R=255,G=50,B=50}},
    [103012] = {"AMR", {R=255,G=0,B=0}},
    -- Shotgun short
    [104001] = {"S686", {R=200,G=200,B=80}},
    [104002] = {"S1897", {R=180,G=180,B=60}},
    [104003] = {"S12K", {R=160,G=200,B=100}},
    [104004] = {"DBS", {R=255,G=180,B=40}},
    -- LMG / Pistol short
    [105001] = {"M249", {R=255,G=140,B=40}},
    [105002] = {"DP-28", {R=255,G=160,B=60}},
    [106001] = {"P92", {R=200,G=200,B=200}},
    [106002] = {"P1911", {R=200,G=200,B=200}},
    [106003] = {"R1895", {R=200,G=180,B=100}},
    [106004] = {"P18C", {R=180,G=180,B=220}},
    [106005] = {"R45", {R=200,G=160,B=80}},
    [106006] = {"SawedOff", {R=180,G=140,B=60}},
    [106007] = {"Flare", {R=255,G=255,B=0}},
    [106008] = {"Skorpion", {R=180,G=220,B=180}},
    -- Scopes classic 203xxx
    [203001] = {"Red Dot", {R=100,G=255,B=100}},
    [203002] = {"Holo", {R=100,G=255,B=150}},
    [203003] = {"2x", {R=80,G=200,B=255}},
    [203004] = {"4x", {R=80,G=150,B=255}},
    [203005] = {"8x", {R=255,G=80,B=80}},
    [203014] = {"3x", {R=80,G=180,B=255}},
    [203015] = {"6x", {R=255,G=120,B=80}},
    [203018] = {"Canted", {R=150,G=150,B=255}},
    -- Scopes 9-digit config (103001xxx)
    [103001004] = {"4x", {R=80,G=150,B=255}},
    [103001005] = {"8x", {R=255,G=80,B=80}},
    [103001006] = {"3x", {R=80,G=180,B=255}},
    [103001007] = {"6x", {R=255,G=120,B=80}},
    -- Scopes alt block 907000xxx
    [907000021] = {"3x", {R=80,G=180,B=255}},
    [907000022] = {"4x", {R=80,G=150,B=255}},
    [907000023] = {"6x", {R=255,G=120,B=80}},
    [907000024] = {"8x", {R=255,G=80,B=80}},
    -- Meds classic 301xxx
    [301001] = {"Bandage", {R=255,G=200,B=200}},
    [301002] = {"FirstAid", {R=255,G=100,B=100}},
    [301003] = {"MedKit", {R=255,G=40,B=40}},
    [301004] = {"EnergyDrink", {R=100,G=255,B=255}},
    [301005] = {"Painkiller", {R=255,G=200,B=50}},
    [301006] = {"Adrenaline", {R=255,G=50,B=255}},
    -- Meds 9-digit 104001xxx
    [104001001] = {"MedKit", {R=255,G=40,B=40}},
    [104001002] = {"FirstAid", {R=255,G=100,B=100}},
    [104001003] = {"Bandage", {R=255,G=200,B=200}},
    [104001004] = {"Adrenaline", {R=255,G=50,B=255}},
    [104001005] = {"Painkiller", {R=255,G=200,B=50}},
    [104001006] = {"EnergyDrink", {R=100,G=255,B=255}},
    -- Grenades
    [602001] = {"Frag", {R=255,G=80,B=40}},
    [602002] = {"Smoke", {R=180,G=180,B=180}},
    [602003] = {"Molotov", {R=255,G=120,B=0}},
    [602004] = {"Stun", {R=255,G=255,B=100}},
}

local CATEGORY_DEFAULT_COLOR = {
    AR = {R=80,G=180,B=255}, SMG = {R=180,G=255,B=120}, Sniper = {R=255,G=60,B=60},
    Shotgun = {R=255,G=180,B=40}, LMG = {R=255,G=140,B=40}, Pistol = {R=200,G=200,B=200},
    Scope = {R=80,G=200,B=255}, Med = {R=255,G=100,B=100}, Grenade = {R=255,G=80,B=40},
    Other = {R=200,G=200,B=200},
}

-- Supports classic short IDs + 9-digit config IDs + name fallback
local function ItemCategory(id)
    id = tonumber(id) or 0
    if id <= 0 then return "Other" end

    if id >= 1000000 then
        if id >= 101001000 and id < 101002000 then return "AR" end
        if id >= 102001000 and id < 102002000 then return "SMG" end
        if id >= 103001000 and id < 103002000 then return "Scope" end
        if id >= 104001000 and id < 104002000 then return "Med" end
        if id >= 907000000 and id < 907000020 then return "AR" end
        if id >= 907000020 and id < 907000030 then return "Scope" end
        local top = math.floor(id / 1000000)
        if top == 101 then return "AR" end
        if top == 102 then return "SMG" end
        if top == 103 then return "Scope" end
        if top == 104 then return "Med" end
        if top == 203 then return "Scope" end
        if top == 301 then return "Med" end
        return "Other"
    end

    -- classic short TypeSpecificID (wide ranges so variants still match)
    if id >= 101000 and id < 102000 then return "AR" end
    if id >= 102000 and id < 103000 then return "SMG" end
    if id >= 103000 and id < 104000 then return "Sniper" end
    if id >= 104000 and id < 105000 then return "Shotgun" end
    if id >= 105000 and id < 106000 then return "LMG" end
    if id >= 106000 and id < 107000 then return "Pistol" end
    if id >= 201000 and id < 205000 then return "Scope" end   -- all sight/scope blocks
    if id >= 301000 and id < 303000 then return "Med" end
    if id >= 601000 and id < 604000 then return "Grenade" end
    return "Other"
end

local function ItemCategoryFromName(item)
    local n = ""
    pcall(function()
        if item.GetName then n = tostring(item:GetName() or "") end
        if (n == "" or n == "None") and item.GetClass then
            local c = item:GetClass()
            if c and c.GetName then n = tostring(c:GetName() or "") end
        end
    end)
    n = string.lower(n)
    if n == "" then return "Other" end
    -- scopes / sights
    if n:find("scope", 1, true) or n:find("sight", 1, true) or n:find("reddot", 1, true)
        or n:find("holo", 1, true) or n:find("2x", 1, true) or n:find("3x", 1, true)
        or n:find("4x", 1, true) or n:find("6x", 1, true) or n:find("8x", 1, true)
        or n:find("canted", 1, true) or n:find("optics", 1, true) then
        return "Scope"
    end
    -- AR names
    if n:find("m416", 1, true) or n:find("scar", 1, true) or n:find("akm", 1, true)
        or n:find("m16", 1, true) or n:find("groza", 1, true) or n:find("aug", 1, true)
        or n:find("qbz", 1, true) or n:find("m762", 1, true) or n:find("mk47", 1, true)
        or n:find("g36", 1, true) or n:find("famas", 1, true) or n:find("ace32", 1, true)
        or n:find("honey", 1, true) or n:find("assault", 1, true) or n:find("rifle_ar", 1, true)
        or n:find("bp_rifle", 1, true) or n:find("ar_", 1, true) then
        return "AR"
    end
    if n:find("uzi", 1, true) or n:find("ump", 1, true) or n:find("vector", 1, true)
        or n:find("bizon", 1, true) or n:find("mp5", 1, true) or n:find("p90", 1, true)
        or n:find("thompson", 1, true) or n:find("smg", 1, true) then
        return "SMG"
    end
    if n:find("kar98", 1, true) or n:find("m24", 1, true) or n:find("awm", 1, true)
        or n:find("sks", 1, true) or n:find("mini14", 1, true) or n:find("slr", 1, true)
        or n:find("mosin", 1, true) or n:find("sniper", 1, true) or n:find("dmr", 1, true) then
        return "Sniper"
    end
    if n:find("medkit", 1, true) or n:find("firstaid", 1, true) or n:find("bandage", 1, true)
        or n:find("painkiller", 1, true) or n:find("adrenaline", 1, true)
        or n:find("energydrink", 1, true) or n:find("drink", 1, true) or n:find("pill", 1, true) then
        return "Med"
    end
    if n:find("grenade", 1, true) or n:find("frag", 1, true) or n:find("molotov", 1, true)
        or n:find("smoke", 1, true) or n:find("stun", 1, true) then
        return "Grenade"
    end
    return "Other"
end

local function ItemShouldShow(id, item)
    local cfg = _G.GTLMODConfig
    if not cfg or not cfg.EspItem_Master then return false end
    id = tonumber(id) or 0
    local cat = "Other"
    if id > 0 then cat = ItemCategory(id) end
    if cat == "Other" and item then
        cat = ItemCategoryFromName(item)
    end
    if cat == "AR" then return cfg.EspItem_AR == true end
    if cat == "SMG" then return cfg.EspItem_SMG == true end
    if cat == "Sniper" then return cfg.EspItem_Sniper == true end
    if cat == "Shotgun" then return cfg.EspItem_Shotgun == true end
    if cat == "LMG" then return cfg.EspItem_LMG == true end
    if cat == "Pistol" then return cfg.EspItem_Pistol == true end
    if cat == "Scope" then return cfg.EspItem_Scope == true end
    if cat == "Med" then return cfg.EspItem_Med == true end
    if cat == "Grenade" then return cfg.EspItem_Grenade == true end
    if cfg.EspItem_Special == true then return true end
    return false
end

local function UnDyeItemMesh(mesh)
    if not mesh or not slua.isValid(mesh) then return end
    pcall(function()
        if mesh.SetDrawDyeing then mesh:SetDrawDyeing(false) end
        if mesh.SetDrawHighlight then mesh:SetDrawHighlight(false) end
        if mesh.SetDrawIdeaOutline then mesh:SetDrawIdeaOutline(false) end
        if mesh.SetIdeaOutlineNew then mesh:SetIdeaOutlineNew(false) end
        if mesh.OverrideIdeaOutlineThickness then mesh:OverrideIdeaOutlineThickness(0.0) end
    end)
end

local function ClearItemGlowOnActor(actor)
    if not actor or not slua.isValid(actor) then return end
    pcall(function()
        if actor.Mesh then UnDyeItemMesh(actor.Mesh) end
        if actor.StaticMesh then UnDyeItemMesh(actor.StaticMesh) end
        if actor.SkeletalMesh then UnDyeItemMesh(actor.SkeletalMesh) end
        local SkeletalMeshComponent = safeImport("SkeletalMeshComponent")
        local StaticMeshComponent = safeImport("StaticMeshComponent")
        if SkeletalMeshComponent and actor.GetComponentsByClass then
            local sk = actor:GetComponentsByClass(SkeletalMeshComponent)
            if sk then
                local n = (type(sk.Num) == "function" and sk:Num()) or 0
                for i = 0, math.min(n, 8) - 1 do
                    local c = sk:Get(i)
                    if slua.isValid(c) then UnDyeItemMesh(c) end
                end
            end
        end
        if StaticMeshComponent and actor.GetComponentsByClass then
            local st = actor:GetComponentsByClass(StaticMeshComponent)
            if st then
                local n = (type(st.Num) == "function" and st:Num()) or 0
                for i = 0, math.min(n, 8) - 1 do
                    local c = st:Get(i)
                    if slua.isValid(c) then UnDyeItemMesh(c) end
                end
            end
        end
    end)
end

function _G.ClearAllItemESPGlow()
    local dyed = _G._ItemDyedActors
    if dyed then
        for actor, _ in pairs(dyed) do
            pcall(ClearItemGlowOnActor, actor)
        end
    end
    _G._ItemDyedActors = setmetatable({}, { __mode = "k" })
    _G.CachedItems = {}
end

local function EnsureItemESPConsole()
    if _G._ItemESP_ConsoleReady then return end
    pcall(function()
        local KSL = safeImport("KismetSystemLibrary")
        local world = slua.getWorld and slua.getWorld()
        if not KSL or not world then return end
        KSL.ExecuteConsoleCommand(world, "r.EnableDrawDyeingColor 1")
        KSL.ExecuteConsoleCommand(world, "r.CustomDepth 3")
        KSL.ExecuteConsoleCommand(world, "r.IdeaOutline.Enable 1")
        KSL.ExecuteConsoleCommand(world, "r.Highlight.Enable 1")
        _G._ItemESP_ConsoleReady = true
    end)
end

local function DyeItemMesh(mesh, col)
    if not mesh or not slua.isValid(mesh) then return end
    pcall(function()
        if mesh.SetDrawDyeing then mesh:SetDrawDyeing(true) end
        if mesh.SetDrawDyeingMode then mesh:SetDrawDyeingMode(1) end
        if mesh.SetVisibleDyeingColor then mesh:SetVisibleDyeingColor(col) end
        if mesh.SetOccludedDyeingColor then mesh:SetOccludedDyeingColor(col) end
        if mesh.SetDyeingColorFadeDistance then mesh:SetDyeingColorFadeDistance(99999.0) end
        if mesh.SetDyeingColorMinMaxDistance then mesh:SetDyeingColorMinMaxDistance(0.0, 99999.0) end
        if mesh.SetDrawHighlight then mesh:SetDrawHighlight(true) end
        if mesh.OverrideHighlightColor then mesh:OverrideHighlightColor(col) end
        if mesh.SetHighlightCanBeOccluded then mesh:SetHighlightCanBeOccluded(false) end
        if mesh.SetDrawIdeaOutline then mesh:SetDrawIdeaOutline(true) end
        if mesh.SetIdeaOutlineNew then mesh:SetIdeaOutlineNew(true) end
        if mesh.SetIdeaOutlineOcclusionHighlight then mesh:SetIdeaOutlineOcclusionHighlight(true) end
        if mesh.OverrideIdeaOutlineColor then mesh:OverrideIdeaOutlineColor(col) end
        if mesh.SetIdeaOutlineOcclusionColor then mesh:SetIdeaOutlineOcclusionColor(col) end
        if mesh.OverrideIdeaOutlineThickness then mesh:OverrideIdeaOutlineThickness(12.0) end
    end)
end

local function ApplyGlowToItemActor(item, col)
    if not item or not slua.isValid(item) then return end
    pcall(function()
        if item.Mesh and slua.isValid(item.Mesh) then DyeItemMesh(item.Mesh, col) end
        if item.StaticMesh and slua.isValid(item.StaticMesh) then DyeItemMesh(item.StaticMesh, col) end
        if item.SkeletalMesh and slua.isValid(item.SkeletalMesh) then DyeItemMesh(item.SkeletalMesh, col) end
        if item.RootComponent and slua.isValid(item.RootComponent) then
            local rc = item.RootComponent
            if rc.SetDrawDyeing or rc.SetDrawIdeaOutline then DyeItemMesh(rc, col) end
        end
        local SkeletalMeshComponent = safeImport("SkeletalMeshComponent")
        local StaticMeshComponent = safeImport("StaticMeshComponent")
        if SkeletalMeshComponent and item.GetComponentsByClass then
            local sk = item:GetComponentsByClass(SkeletalMeshComponent)
            if sk then
                local n = (type(sk.Num) == "function" and sk:Num()) or 0
                for i = 0, math.min(n, 8) - 1 do
                    local c = sk:Get(i)
                    if slua.isValid(c) then DyeItemMesh(c, col) end
                end
            end
        end
        if StaticMeshComponent and item.GetComponentsByClass then
            local st = item:GetComponentsByClass(StaticMeshComponent)
            if st then
                local n = (type(st.Num) == "function" and st:Num()) or 0
                for i = 0, math.min(n, 8) - 1 do
                    local c = st:Get(i)
                    if slua.isValid(c) then DyeItemMesh(c, col) end
                end
            end
        end
    end)
    _G._ItemDyedActors[item] = true
end

local function ReadItemId(item)
    local itemId = nil
    pcall(function()
        if item.DefineID then
            local d = item.DefineID
            itemId = d.TypeSpecificID or d.TypeSpecificId or d.TypeID
            -- some builds pack full 9-digit into defineID fields
            if (not itemId or itemId == 0) and d.ID then itemId = d.ID end
        end
        if (not itemId or itemId == 0) and item.ItemID then itemId = item.ItemID end
        if (not itemId or itemId == 0) and item.GetItemID then itemId = item:GetItemID() end
        if (not itemId or itemId == 0) and item.GetDefineID then
            local d = item:GetDefineID()
            if d then
                itemId = d.TypeSpecificID or d.TypeSpecificId or d.TypeID or d.ID
            end
        end
        if (not itemId or itemId == 0) and item.PickupData then
            local pd = item.PickupData
            if type(pd) == "table" or type(pd) == "userdata" then
                itemId = pd.TypeSpecificID or pd.ItemID or pd.ID or pd.TypeID
            end
        end
        -- last resort: name digits
        if (not itemId or itemId == 0) and item.GetName then
            local n = tostring(item:GetName() or "")
            local m = n:match("(%d%d%d%d%d%d%d%d%d)") or n:match("(%d%d%d%d%d%d)")
            if m then itemId = tonumber(m) end
        end
    end)
    return tonumber(itemId) or 0
end

_G.RunOptimizedItemAndVehicleESP = function(pc)
    local cfg = _G.GTLMODConfig
    if not cfg or not cfg.EspItem_Master then
        -- Master OFF → strip every glow we applied
        if _G.ClearAllItemESPGlow then _G.ClearAllItemESPGlow() end
        return
    end

    EnsureItemESPConsole()

    local curTime = os.clock()
    local player = nil
    pcall(function()
        local GD = GameplayData or package.loaded["GameLua.GameCore.Data.GameplayData"]
        if GD and GD.GetPlayerCharacter then player = GD.GetPlayerCharacter() end
        if not slua.isValid(player) then
            local ctrl = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
            if slua.isValid(ctrl) and ctrl.GetPlayerCharacterSafety then
                player = ctrl:GetPlayerCharacterSafety()
            end
        end
    end)
    if not slua.isValid(player) then return end

    -- Rescan every 1.6s (balanced visibility vs lag)
    if curTime - (_G.LastScanItemTime or 0) > 1.4 then
        _G.LastScanItemTime = curTime
        local newItems = {}
        local seen = {}

        local function consider(item)
            if not item or not slua.isValid(item) or item.bHidden then return end
            if seen[item] then return end
            seen[item] = true
            local dist = 0
            pcall(function()
                if player.GetDistanceTo then dist = player:GetDistanceTo(item) end
            end)
            if dist <= 0 or dist > 15000 then return end -- 150m
            local itemId = ReadItemId(item)
            if not ItemShouldShow(itemId, item) then return end
            local meta = ITEM_NAME_MAP[itemId]
            local cat = ItemCategory(itemId)
            local name = meta and meta[1] or (cat .. "#" .. tostring(itemId))
            local color = (meta and meta[2]) or CATEGORY_DEFAULT_COLOR[cat] or CATEGORY_DEFAULT_COLOR.Other
            newItems[#newItems + 1] = { act = item, data = { name = name, color = color, id = itemId, cat = cat } }
        end

        pcall(function()
            local classNames = {
                "PickUpWrapperActor",
                "STExtraPickUpWrapperActor",
                "STPickupWrapperActor",
                "PickUpListWrapperActor",
                "STExtraLobbyWeapon",
            }
            local GS = safeImport("GameplayStatics")
            local world = slua.getWorld and slua.getWorld()
            local maxScan = IS_32BIT and 220 or 500
            local scanned = 0

            for _, cn in ipairs(classNames) do
                if scanned >= maxScan then break end
                local APickUp = safeImport(cn)
                if APickUp then
                    local actors = nil
                    pcall(function()
                        if Game and Game.GetActorsByClass then
                            actors = Game:GetActorsByClass(APickUp)
                        end
                    end)
                    if not actors and GS and world then
                        pcall(function()
                            actors = GS.GetAllActorsOfClass(world, APickUp, nil)
                        end)
                    end
                    if actors then
                        local count = 0
                        pcall(function()
                            count = (type(actors.Num) == "function" and actors:Num()) or 0
                        end)
                        for i = 0, count - 1 do
                            scanned = scanned + 1
                            if scanned > maxScan then break end
                            local item = nil
                            pcall(function() item = actors:Get(i) end)
                            consider(item)
                        end
                    end
                end
            end
        end)

        -- Clear glow on actors that are no longer in the active set
        local stillActive = {}
        for _, entry in ipairs(newItems) do
            stillActive[entry.act] = true
        end
        if _G._ItemDyedActors then
            for actor, _ in pairs(_G._ItemDyedActors) do
                if not stillActive[actor] then
                    pcall(ClearItemGlowOnActor, actor)
                    _G._ItemDyedActors[actor] = nil
                end
            end
        end

        _G.CachedItems = newItems
    end

    -- Apply animated glow every run
    local LC = safeImport("LinearColor")
    if not LC or not _G.CachedItems then return end
    local now = os.clock()

    for _, entry in ipairs(_G.CachedItems) do
        local item = entry.act
        local itemData = entry.data
        if item and itemData and slua.isValid(item) and not item.bHidden then
            -- category may have been toggled off since scan
            if not ItemShouldShow(itemData.id, itemData.actor) then
                pcall(ClearItemGlowOnActor, item)
                if _G._ItemDyedActors then _G._ItemDyedActors[item] = nil end
            else
                local dist = 0
                pcall(function()
                    if player.GetDistanceTo then dist = player:GetDistanceTo(item) / 100 end
                end)
                if dist > 0 and dist <= 150 then
                    local phase = (now * 2.6 + (itemData.id or 0) * 0.17) % 6.28318
                    local shimmer = (math.sin(phase) + 1) * 0.5
                    local baseR = (itemData.color.R or 255) / 255
                    local baseG = (itemData.color.G or 255) / 255
                    local baseB = (itemData.color.B or 255) / 255
                    local r = baseR * (0.50 + 0.50 * shimmer)
                    local g = baseG * (0.50 + 0.50 * shimmer)
                    local b = baseB * (0.50 + 0.50 * shimmer)
                    local col = LC(r, g, b, 0.90)
                    ApplyGlowToItemActor(item, col)
                end
            end
        end
    end
end

local _RunItemESP_LastRun = 0
local _RunItemESP_WasOn = false
local function RunItemESPLite()
    local on = (_G.GTLMODConfig and _G.GTLMODConfig.EspItem_Master) == true
    if not on then
        -- edge: just turned off → clear all glows once
        if _RunItemESP_WasOn then
            pcall(function() if _G.ClearAllItemESPGlow then _G.ClearAllItemESPGlow() end end)
        end
        _RunItemESP_WasOn = false
        return
    end
    _RunItemESP_WasOn = true
    local _now = os.clock()
    -- apply loop a bit faster than scan so animation stays smooth
    if _now - _RunItemESP_LastRun < 0.50 then return end
    _RunItemESP_LastRun = _now
    local pc = nil
    pcall(function()
        pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    end)
    _G.RunOptimizedItemAndVehicleESP(pc)
end

-- ====================================================================
-- [iPad FOV / SCOPE TRANSITION FIX]
-- Keep iPad FOV state transitions independent from the slow MainLoop.
-- On scope-open, remove the custom FOV as soon as ADS is detected so the
-- native scope owns the camera immediately. On scope-close, restore the
-- configured iPad FOV in the same tick instead of waiting for MainLoop.
-- ====================================================================
-- ====================================================================
-- [iPad FOV / SCOPE TRANSITION FIX]
-- Exact same logic as original fixed.lua (word-for-word behaviour).
-- Keep iPad FOV state transitions independent from the slow MainLoop.
-- On scope-open, remove the custom FOV as soon as ADS is detected so the
-- native scope owns the camera immediately. On scope-close, restore the
-- configured iPad FOV in the same tick instead of waiting for MainLoop.
-- ====================================================================
local function ApplyIpadFOVState(pc, localPlayer)
    if not Valid(pc) or not Valid(localPlayer) then return end

    if not _G.GTLMODState.CachedIpadFOV then
        _G.GTLMODState.CachedIpadFOV = {}
    end

    local state = _G.GTLMODState.CachedIpadFOV
    local isAiming = false

    pcall(function()
        isAiming =
            localPlayer.bIsWeaponAiming == true or
            localPlayer.bIsGunADS == true
    end)

    local wasAiming = state.prevAiming == true

    -- Scope just opened: release the custom iPad FOV immediately.
    -- Do not re-apply iPad FOV while ADS is active; native scope camera
    -- handling remains fully in control.
    if isAiming then
        if not wasAiming then
            if type(pc.FOV) == "function" and state.lastAppliedFOV ~= nil then
                pcall(function() pc:FOV(0) end)
            end
            state.lastAppliedFOV = nil
        end
        state.prevAiming = true
        return
    end

    -- Scope just closed (or we are in normal view).
    state.prevAiming = false

    local targetFOV = nil
    local currentVehicle = nil

    pcall(function()
        currentVehicle = localPlayer.CurrentVehicle
        if not currentVehicle and type(localPlayer.GetVehicle) == "function" then
            currentVehicle = localPlayer:GetVehicle()
        end
    end)

    local isInVehicle =
        Valid(currentVehicle) or localPlayer.bIsInVehicle == true

    local custom = _G.GTLMODState and _G.GTLMODState.CustomTextData
    if _G.GTLMODConfig and _G.GTLMODConfig.IpadView and custom then
        targetFOV = tonumber(custom.IpadViewFOV) or 120
    end

    if type(pc.FOV) ~= "function" then return end

    if targetFOV and targetFOV > 0 then
        targetFOV = math.max(40, math.min(160, targetFOV))

        -- Force the value on the exact close transition. This overwrites
        -- the native scope-close FOV instead of allowing a default-FOV gap.
        if wasAiming or state.lastAppliedFOV ~= targetFOV then
            pcall(function() pc:FOV(targetFOV) end)
            state.lastAppliedFOV = targetFOV
        end
    elseif state.lastAppliedFOV ~= nil then
        pcall(function() pc:FOV(0) end)
        state.lastAppliedFOV = nil
    end
end

local function MainLoop()
    if isExpired then return end

    if _G.GTLMODState.CustomTextData == nil then
        _G.GTLMODState.CustomTextData = { OuterSpeed = 10, InnerSpeed = 10, HRecoil = 0.3, VRecoil = 0.3, IpadViewFOV = 120 }
    end

    local pc = GameplayData.GetPlayerController()
    local localPlayer = nil
    if Valid(pc) then localPlayer = pc:GetPlayerCharacterSafety() end

    if not Valid(localPlayer) then
        -- Player not in game — clean up marks and mark session as inactive
        if _G.GTLMODState.TrackedMarks then
            for markId, _ in pairs(_G.GTLMODState.TrackedMarks) do SafeRemoveMark(markId) end
        end
        _G.GTLMODState.TrackedMarks = {}
        for key, data in pairs(_G.GTLMODState.EnemyMarks) do
            if data and data.MIDs then
                for meshStr, midTable in pairs(data.MIDs) do
                    for k in pairs(midTable) do midTable[k] = nil end
                end
                data.MIDs = nil
            end
        end
        _G.GTLMODState.EnemyMarks = {}
        _G.GTLMODState.PrevGraphicsState = {}
        _G.BotStatusCache = {}
        _G.AimTouchVisCache = {}
        _G.GTLMODState.MidCacheCount = 0
        -- [LAG FIX] Clear per-enemy distance and LOS caches on session end
        _G._GTL_DistCache = {}
        _G._GTL_LOSCache  = {}
        _G.GTLMODState._LastHadPlayer = false  -- track session gap
        -- Soft-invalidate match-bound runtime only. Config flags stay ON.
        pcall(function()
            if _G.PlayerMapMarker then
                _G.PlayerMapMarker._ActiveTimerPC = nil
                _G.PlayerMapMarker._ActiveTimerTick = 0
                _G.PlayerMapMarker.ESPCanvas = nil
                _G.PlayerMapMarker.bActive = false
            end
            if NewWallhack then
                NewWallhack.WH_TIMER = nil
                NewWallhack.Active = false
                NewWallhack.PROCESSED_PAWNS = {}
            end
            -- Always invalidate counter widgets so they rebuild on next game
            if _G.RedBoxOverlay then
                _G.RedBoxOverlay.bActive = false
                _G.RedBoxOverlay.MainContainer = nil
                _G.RedBoxOverlay.WidgetSlot = nil
                _G.RedBoxOverlay.TextBlockPlayer = nil
                _G.RedBoxOverlay.TextBlockBot = nil
                pcall(function() _G.RedBoxOverlay._CachedPosVec = nil end)
            end
            -- old ESPLine removed (no canvas to invalidate)
            -- Invalidate iPad FOV state so it re-applies cleanly
            -- prevAiming is also reset so scope-open/close transitions detect correctly
            if _G.GTLMODState.CachedIpadFOV then
                _G.GTLMODState.CachedIpadFOV = {}
            end
        end)
        return
    end

    -- [FIX] New game start detected: player became valid after a session gap.
    -- Force re-initialization of all enabled UI features so they work immediately.
    if not _G.GTLMODState._LastHadPlayer then
        _G.GTLMODState._LastHadPlayer = true
        pcall(function()
            local c = _G.GTLMODConfig or {}
            -- Force-rebuild LexusConfig sync so PlayerMapMarker restarts correctly
            if _G.LexusConfig then
                _G.LexusConfig.EspLoai9 = (c.EspLine or c.CounterEnabled or c.EspModelName or c.EspWeaponIcon) and true or false
            end
            -- Re-prime graphics unlock so 165fps applies in new match
            if c.TargetFPS or c.FPSStabilizer then _G.GTLMODState.GraphicsUnlocked = false end
            -- Reset wallhack timer (it dies across session boundaries)
            if c.WallhackSmart and NewWallhack then
                NewWallhack.WH_TIMER = nil
                NewWallhack.Active = false
            end
            -- Clear OrigAutoAimCompCached so AutoHead re-caches per-match
            _G.GTLMODState.OrigAutoAimCompCached = nil
            -- Clear aim caches so ForceAimbot / AimTouch work immediately in new match
            _G.PrivAimVisCache = {}
            _G.PrivAimBotCache = {}
            _G.AimTouchVisCache = {}
            _G._PrivAimCacheLastFlush = 0
        end)
    end

    local Cached_MyHUD = pc and pc.MyHUD or nil

    -- [LAG FIX] Feature Activation Sync — LexusConfig rebuild only when flags changed.
    pcall(function()
        local c = _G.GTLMODConfig or {}
        -- Fingerprint: only rebuild when something actually changed (saves ~0.3ms/tick)
        local _syncFP = tostring(c.EspLine) .. tostring(c.CounterEnabled) .. tostring(c.EspModelName)
                     .. tostring(c.EspWeaponIcon) .. tostring(c.EspShowHealthBar) .. tostring(c.EspTeamColorBox)
                     .. tostring(c.EspShowDistance) .. tostring(c.EspActiveBom)
        if _syncFP ~= _G._LexusSyncFP then
            _G._LexusSyncFP = _syncFP
            local L = _G.LexusConfig or {}
            _G.LexusConfig = L
            local any = c.EspLine or c.CounterEnabled or c.EspModelName or c.EspWeaponIcon
            L.EspLoai9 = any and true or false
            L.Esp9_Count = c.CounterEnabled == true
            L.Esp9_Name = c.EspModelName == true
            L.Esp9_HP = (c.EspModelName == true) and (c.EspShowHealthBar ~= false)
            L.Esp9_Team = (c.EspModelName == true) and (c.EspTeamColorBox ~= false)
            L.Esp9_Weapon = c.EspWeaponIcon == true
            L.Esp9_Distance = (c.EspModelName == true) and (c.EspShowDistance ~= false)
            L.Esp9_Line = c.EspLine == true
            L.EspActiveBom = c.EspActiveBom == true
            L.EspBomMaster = c.EspActiveBom == true
            -- Restart PlayerMapMarker on config change if needed
            if _G.PlayerMapMarker and not _G.PlayerMapMarker.bActive and L.EspLoai9 then
                if _G.PlayerMapMarker.Start then pcall(_G.PlayerMapMarker.Start) end
            end
        end

        -- These checks are cheap — run every tick regardless of fingerprint
        if c.CounterEnabled then
            if _G.RedBoxOverlay and _G.RedBoxOverlay.Start then pcall(_G.RedBoxOverlay.Start) end
        elseif _G.RedBoxOverlay and _G.RedBoxOverlay.bActive and _G.RedBoxOverlay.Stop then
            pcall(_G.RedBoxOverlay.Stop)
        end

        -- old ESPLine removed

        if c.WallhackSmart then
            if not NewWallhack.Active or not NewWallhack.WH_TIMER then
                NewWallhack.WH_TIMER = nil
                NewWallhack.Active = false
                pcall(_G.StartNewWallhack)
            end
        elseif NewWallhack.Active then
            pcall(_G.StopNewWallhack)
        end

        -- Force aimbot: config stays ON across matches; clear stale aim state if needed
        if c.ForceAimbot then
            -- mark that aim should stay active (PrivFeaturesTick reads config every tick)
            _G._ForceAimbotWanted = true
        else
            _G._ForceAimbotWanted = false
        end

        if c.IpadView and not _G.GTLMODState.CustomTextData then
            _G.GTLMODState.CustomTextData = { OuterSpeed = 10, InnerSpeed = 10, HRecoil = 0.3, VRecoil = 0.3, IpadViewFOV = 120 }
        end

        if _G.RJCounter and _G.RJCounter.SetEnabled then
            pcall(function() _G.RJCounter.SetEnabled(false) end)
        end
    end)

    -- Ping / crash safety: clean up any lingering report timers
    pcall(function()
        local SubMgr = package.loaded["GameLua.GameCore.Module.Subsystem.SubsystemMgr"]
        if SubMgr then
            for _, subName in ipairs({"AFKReportorSubsystem","SpeedCheckSubsystem","WallCheckSubsystem","ShootVerifySubSystemClient"}) do
                pcall(function()
                    local sub = SubMgr:Get(subName)
                    if sub and sub.ReportPingDelayTimer then
                        sub:RemoveGameTimer(sub.ReportPingDelayTimer)
                        sub.ReportPingDelayTimer = nil
                    end
                end)
            end
        end
    end)

    if _G.GTLMODConfig then InitializeGraphicsUnlock() end
    InitializeNativeESP()

    -- Snap lines: PlayerMapMarker only
    if _G.GTLMODConfig.EspLine and _G.PlayerMapMarker then
        if not _G.PlayerMapMarker.bActive then
            if _G.PlayerMapMarker.EnsureRunning then
                pcall(_G.PlayerMapMarker.EnsureRunning)
            elseif _G.PlayerMapMarker.Start then
                pcall(_G.PlayerMapMarker.Start)
            end
        end
    end

    -- [FIXED v3] iPad View FOV is handled by the dedicated high-frequency
    -- IpadFOVTick below. Keeping this out of the 0.50s MainLoop prevents the
    -- scope-open/close state from waiting on the general feature loop.
    pcall(function()
        ApplyIpadFOVState(pc, localPlayer)
    end)

    pcall(function()
        if Valid(pc) then
            if pc.HiggsBoson then pc.HiggsBoson.bMHActive = false; pc.HiggsBoson.bCallPreReplication = false end
            if pc.HiggsBosonComponent then pc.HiggsBosonComponent.bMHActive = false; pc.HiggsBosonComponent.bCallPreReplication = false end
        end
    end)

    pcall(function()
        local autoComp = localPlayer.AutoAimComp
        if Valid(autoComp) then
            if not _G.GTLMODState.OrigAutoAimCompCached then
                _G.GTLMODState.OrigAutoAimCompCached = {
                    bOnlyHitHead = autoComp.bOnlyHitHead,
                    HeadBoneName = autoComp.HeadBoneName,
                    Bones = autoComp.Bones,
                    ChestBoneName = autoComp.ChestBoneName,
                    PelvisBoneName = autoComp.PelvisBoneName,
                    HeadPriority = autoComp.AimAssistConfig and autoComp.AimAssistConfig.HeadPriority,
                    ChestPriority = autoComp.AimAssistConfig and autoComp.AimAssistConfig.ChestPriority,
                    PelvisPriority = autoComp.AimAssistConfig and autoComp.AimAssistConfig.PelvisPriority
                }
            end
            if _G.GTLMODConfig.AutoHead then
                autoComp.bOnlyHitHead = true
                autoComp.HeadBoneName = "Head"
                pcall(function() autoComp.Bones = {"Head"} end)
                autoComp.ChestBoneName = "Head"
                autoComp.PelvisBoneName = "Head"
                if autoComp.AimAssistConfig then
                    autoComp.AimAssistConfig.HeadPriority = 100
                    autoComp.AimAssistConfig.ChestPriority = 100
                    autoComp.AimAssistConfig.PelvisPriority = 100
                end
            else
                local orig = _G.GTLMODState.OrigAutoAimCompCached
                autoComp.bOnlyHitHead = orig.bOnlyHitHead
                autoComp.HeadBoneName = orig.HeadBoneName
                pcall(function() autoComp.Bones = orig.Bones or {"Spine_01", "Pelvis", "Head"} end)
                autoComp.ChestBoneName = orig.ChestBoneName
                autoComp.PelvisBoneName = orig.PelvisBoneName
                if autoComp.AimAssistConfig then
                    autoComp.AimAssistConfig.HeadPriority = orig.HeadPriority or 1
                    autoComp.AimAssistConfig.ChestPriority = orig.ChestPriority or 1
                    autoComp.AimAssistConfig.PelvisPriority = orig.PelvisPriority or 1
                end
            end
        end
    end)

    -- [LAG FIX] Cache graphics module — was require()d raw every MainLoop tick
    if not _G._GTL_lsg_cache then
        pcall(function() _G._GTL_lsg_cache = require("client.slua.logic.setting.logic_setting_graphics") end)
    end
    pcall(function()
        local lsg = _G._GTL_lsg_cache
        if not lsg then return end
        local gi = lsg.GetGameInstance()
        if gi then
            local cleanOn = (_G.GTLMODConfig.CleaningSpace == true) or (_G.GTLMODConfig.RemoveGrass == true)
            if cleanOn and not _G.GTLMODState.PrevGraphicsState.RemoveGrass then
                if _G.ApplyCleaningSpace then pcall(_G.ApplyCleaningSpace, true)
                else
                    gi:ExecuteCMD("grass.DensityScale", "0"); gi:ExecuteCMD("foliage.DensityScale", "0")
                    gi:ExecuteCMD("r.Fog", "0")
                end
                _G.GTLMODState.PrevGraphicsState.RemoveGrass = true
            elseif not cleanOn and _G.GTLMODState.PrevGraphicsState.RemoveGrass then
                if _G.ApplyCleaningSpace then pcall(_G.ApplyCleaningSpace, false)
                else
                    gi:ExecuteCMD("grass.DensityScale", "1"); gi:ExecuteCMD("foliage.DensityScale", "1")
                    gi:ExecuteCMD("r.Fog", "1")
                end
                _G.GTLMODState.PrevGraphicsState.RemoveGrass = false
            end

            if _G.GTLMODConfig.ColorBodyV2 and not _G.GTLMODState.PrevGraphicsState.ColorBodyV2 then
                gi:ExecuteCMD("r.CharacterMinShadowFactor", "4")
                gi:ExecuteCMD("r.CharacterDiffuseOffset", "200")
                gi:ExecuteCMD("r.CharacterDiffusePower", "200")
                _G.GTLMODState.PrevGraphicsState.ColorBodyV2 = true
            elseif not _G.GTLMODConfig.ColorBodyV2 and _G.GTLMODState.PrevGraphicsState.ColorBodyV2 then
                gi:ExecuteCMD("r.CharacterMinShadowFactor", "1")
                gi:ExecuteCMD("r.CharacterDiffuseOffset", "0")
                gi:ExecuteCMD("r.CharacterDiffusePower", "1")
                _G.GTLMODState.PrevGraphicsState.ColorBodyV2 = false
            end
            if _G.GTLMODConfig.BlackSky and not _G.GTLMODState.PrevGraphicsState.BlackSky then
                _G.GTLMODState.PrevGraphicsState.BlackSky = true
                pcall(function()
                    if _G.UniversalSkyController then
                        _G.UniversalSkyController.SetEnabled(true)
                        _G.UniversalSkyController.SetRGB(12, 8, 48)
                    end
                end)
            elseif not _G.GTLMODConfig.BlackSky and _G.GTLMODState.PrevGraphicsState.BlackSky then
                _G.GTLMODState.PrevGraphicsState.BlackSky = false
                pcall(function()
                    if _G.UniversalSkyController then
                        _G.UniversalSkyController.SetEnabled(false)
                    end
                end)
            elseif _G.GTLMODConfig.BlackSky and _G.UniversalSkyController then
                -- keep night tint refreshed while on
                pcall(function() _G.UniversalSkyController.Apply() end)
            end
        end
    end)

    pcall(function()
        local weapon = nil
        pcall(function()
            local weaponManager = localPlayer.WeaponManagerComponent
            if Valid(weaponManager) and type(weaponManager.GetCurrentWeapon) == "function" then weapon = weaponManager:GetCurrentWeapon() end
        end)
        if not Valid(weapon) then
            if type(localPlayer.GetCurrentShootWeapon) == "function" then weapon = localPlayer:GetCurrentShootWeapon()
            elseif type(localPlayer.GetCurrentWeapon) == "function" then weapon = localPlayer:GetCurrentWeapon() end
        end
        if Valid(weapon) then
            local entities = {}
            if Valid(weapon.ShootWeaponEntity_GEN_VARIABLE) then table.insert(entities, weapon.ShootWeaponEntity_GEN_VARIABLE) end
            if Valid(weapon.ShootWeaponEntity) then table.insert(entities, weapon.ShootWeaponEntity) end
            if Valid(weapon.ShootWeaponComponent) and Valid(weapon.ShootWeaponComponent.ShootWeaponEntityComponent) then
                table.insert(entities, weapon.ShootWeaponComponent.ShootWeaponEntityComponent)
            end
            for _, entity in ipairs(entities) do
                -- NOTE: GodMode intentionally excluded to prevent fake damage / ban
                local anyModOn = _G.GTLMODConfig.CustomHRecoil or _G.GTLMODConfig.CustomVRecoil
                    or _G.GTLMODConfig.LessShake or _G.GTLMODConfig.Accuracy
                    or _G.GTLMODConfig.Crosshair

                if anyModOn then
                    if not entity.OriginalStatsCached then
                        entity.OriginalStatsCached = {
                            GameDeviationFactor      = entity.GameDeviationFactor,
                            GameDeviationAccuracy    = entity.GameDeviationAccuracy,
                            BulletFireSpeed          = entity.BulletFireSpeed,
                            ShootInterval            = entity.ShootInterval,
                            BaseDamage               = entity.BaseDamage,
                            AccessoriesHRecoilFactor = entity.AccessoriesHRecoilFactor,
                            AccessoriesVRecoilFactor = entity.AccessoriesVRecoilFactor,
                            RecoilKick               = entity.RecoilKick,
                            RecoilKickADS            = entity.RecoilKickADS,
                            AnimationKick            = entity.AnimationKick,
                        }
                    end

                    -- Apply/restore crosshair deviation
                    if _G.GTLMODConfig.Crosshair then
                        entity.GameDeviationFactor = 0.0
                    else
                        entity.GameDeviationFactor = entity.OriginalStatsCached.GameDeviationFactor
                    end

                    -- Apply/restore accuracy deviation
                    if _G.GTLMODConfig.Accuracy then
                        entity.GameDeviationAccuracy = 0.0
                    else
                        entity.GameDeviationAccuracy = entity.OriginalStatsCached.GameDeviationAccuracy
                    end

                    -- No-recoil (CharacterBase method: set factors to near-zero, not zero)
                    if _G.GTLMODConfig.CustomHRecoil then
                        entity.AccessoriesHRecoilFactor = _G.GTLMODState.CustomTextData.HRecoil or 0.05
                    else
                        entity.AccessoriesHRecoilFactor = entity.OriginalStatsCached.AccessoriesHRecoilFactor
                    end

                    if _G.GTLMODConfig.CustomVRecoil then
                        entity.AccessoriesVRecoilFactor = _G.GTLMODState.CustomTextData.VRecoil or 0.05
                    else
                        entity.AccessoriesVRecoilFactor = entity.OriginalStatsCached.AccessoriesVRecoilFactor
                    end

                    if _G.GTLMODConfig.LessShake then
                        entity.RecoilKickADS  = 0.0
                        entity.RecoilKick     = 0.0
                        entity.AnimationKick  = 0.0
                    else
                        entity.RecoilKickADS  = entity.OriginalStatsCached.RecoilKickADS
                        entity.RecoilKick     = entity.OriginalStatsCached.RecoilKick
                        entity.AnimationKick  = entity.OriginalStatsCached.AnimationKick
                    end

                    entity.GTLMODWeaponModsActive = true

                elseif entity.GTLMODWeaponModsActive then
                    if entity.OriginalStatsCached then
                        local orig = entity.OriginalStatsCached
                        entity.GameDeviationFactor      = orig.GameDeviationFactor
                        entity.GameDeviationAccuracy    = orig.GameDeviationAccuracy
                        entity.BulletFireSpeed          = orig.BulletFireSpeed
                        entity.ShootInterval            = orig.ShootInterval
                        entity.BaseDamage               = orig.BaseDamage
                        entity.AccessoriesHRecoilFactor = orig.AccessoriesHRecoilFactor
                        entity.AccessoriesVRecoilFactor = orig.AccessoriesVRecoilFactor
                        entity.RecoilKick               = orig.RecoilKick
                        entity.RecoilKickADS            = orig.RecoilKickADS
                        entity.AnimationKick            = orig.AnimationKick
                    end
                    entity.GTLMODWeaponModsActive = false
                end
            end
        end
    end)

    pcall(function()
        local allCharacters = {}
        if GameplayData.GetAllPlayerCharacters then
            allCharacters = GameplayData.GetAllPlayerCharacters()
        elseif GameplayData.GameCharacters then
            for _, char in pairs(GameplayData.GameCharacters) do table.insert(allCharacters, char) end
        end

        local currentValidKeys = {}
        for _, enemy in pairs(allCharacters) do
            if Valid(enemy) and enemy ~= localPlayer then
                currentValidKeys[GetSafeEnemyKey(enemy)] = true
            end
        end
        for key, data in pairs(_G.GTLMODState.EnemyMarks) do
            if not currentValidKeys[key] then
                SafeRemoveMark(data.radarMark)
                SafeRemoveMark(data.hpMark)
                SafeRemoveMark(data.distMark)
                SafeRemoveMark(data.hpMark8)
                if _G.AimTouchVisCache and _G.AimTouchVisCache[key] then _G.AimTouchVisCache[key] = nil end
                if _G.BotStatusCache and _G.BotStatusCache[key] then _G.BotStatusCache[key] = nil end
                if data.MIDs then
                    for meshStr, midTable in pairs(data.MIDs) do
                        for k in pairs(midTable) do midTable[k] = nil end
                    end
                    data.MIDs = nil
                end
                data.enemy = nil
                data.CachedMeshes = nil
                _G.GTLMODState.EnemyMarks[key] = nil
            end
        end

        local localTeamID = -1
        pcall(function()
            localTeamID = localPlayer.TeamID
                or (type(localPlayer.GetTeamID) == "function" and localPlayer:GetTeamID())
                or -1
        end)
        for _, enemy in pairs(allCharacters) do
            -- [FIXED] Verify enemy is valid before accessing any properties
            if not Valid(enemy) then goto enemyContinue end
            local enemyTeamID = -2
            pcall(function()
                enemyTeamID = enemy.TeamID
                    or (type(enemy.GetTeamID) == "function" and enemy:GetTeamID())
                    or -2
            end)
            if Valid(enemy) and enemy ~= localPlayer and enemyTeamID ~= localTeamID then
                local eKey = GetSafeEnemyKey(enemy)
                _G.GTLMODState.EnemyMarks[eKey] = _G.GTLMODState.EnemyMarks[eKey] or { enemy = enemy }
                local markData = _G.GTLMODState.EnemyMarks[eKey]
                markData.enemy = enemy

                local bIsReallyDead = false
                pcall(function()
                    if type(enemy.IsDead) == "function" then bIsReallyDead = enemy:IsDead()
                    elseif enemy.bIsDead ~= nil then bIsReallyDead = enemy.bIsDead
                    elseif enemy.bIsDeadFlag ~= nil then bIsReallyDead = enemy.bIsDeadFlag end
                    if enemy.HealthStatus ~= nil and enemy.HealthStatus == 2 then bIsReallyDead = true end
                end)

                if not bIsReallyDead then
                    local eMesh = nil
                    pcall(function() eMesh = enemy.Mesh end)
                    local aLoc = nil
                    pcall(function() if type(enemy.K2_GetActorLocation) == "function" then aLoc = enemy:K2_GetActorLocation() end end)

                    -- [LAG FIX] Cache GetDistanceTo per enemy — raw call was firing every tick per enemy
                    local eKey2 = GetSafeEnemyKey(enemy)
                    local _now_ml = os.clock()
                    if not _G._GTL_DistCache then _G._GTL_DistCache = {} end
                    local _dc = _G._GTL_DistCache[eKey2]
                    local distM = 0
                    if _dc and (_now_ml - _dc.t) < 0.35 then
                        distM = _dc.v
                    else
                        pcall(function() distM = localPlayer:GetDistanceTo(enemy) / 100 end)
                        _G._GTL_DistCache[eKey2] = { v = distM, t = _now_ml }
                    end

                    local MyHUD = Cached_MyHUD
                    if Valid(MyHUD) then
                        if _G.GTLMODConfig.EspAntenna and distM <= 400 then
                            pcall(function()
                                local loopCount = IS_32BIT and 4 or 8
                                local zStep = 1000
                                for i = 1, loopCount do
                                    local zOffset = 105 + (i * zStep)
                                    MyHUD:AddDebugText("|", enemy, 0.65, {X=0,Y=0,Z=zOffset}, {X=0,Y=0,Z=zOffset}, C_GREEN, true, false, true, nil, 1.2, true)
                                end
                            end)
                        end
                        if _G.GTLMODConfig.EspDistance and distM <= LIMITS.ESP_MAX_DISTANCE then
                            pcall(function()
                                MyHUD:AddDebugText(string.format("%.0fm", math.floor(distM+0.5)), enemy, 0.65, {X=15,Y=15,Z=-15}, {X=15,Y=15,Z=-15}, C_WHITE, true, false, true, nil, 0.9, true)
                            end)
                        end
                        if _G.GTLMODConfig.EspName and distM <= LIMITS.ESP_MAX_DISTANCE then
                            pcall(function()
                                local pName = enemy.PlayerName or "Enemy"
                                local isKnock = (enemy.Health or 100) <= 0 or enemy.HealthStatus == 1
                                -- [LAG FIX] Cache LineOfSightTo per enemy — raw raycast was firing every tick per enemy
                                if not _G._GTL_LOSCache then _G._GTL_LOSCache = {} end
                                local _lc = _G._GTL_LOSCache[eKey2]
                                local bVis = true
                                if _lc and (_now_ml - _lc.t) < 0.25 then
                                    bVis = _lc.v
                                else
                                    pcall(function() if pc and type(pc.LineOfSightTo) == "function" then bVis = pc:LineOfSightTo(enemy) end end)
                                    _G._GTL_LOSCache[eKey2] = { v = bVis, t = _now_ml }
                                end
                                local color = isKnock and C_BLUE or (bVis and C_GREEN or C_RED)
                                MyHUD:AddDebugText(pName, enemy, 0.65, {X=0,Y=0,Z=120}, {X=0,Y=0,Z=120}, color, true, false, true, nil, 1.0, true)
                            end)
                        end
                        -- REMOVED: EspModelName yellow name rendering (unwanted duplicate player name)
                        -- The correct red/team-colored name is rendered at line 4230 above
                        -- This yellow model name render was causing visual duplication - now fully disabled
                    end

                    if _G.GTLMODConfig.EspVip then
                        if markData.hpMark == nil then markData.hpMark = SafeAddMark(1006, FVector(0,0,0), 0, "", 4, enemy) end
                        if markData.distMark == nil then markData.distMark = SafeAddMark(9999, FVector(0,0,0), 0, "", 4, enemy) end
                    else
                        if markData.hpMark then SafeRemoveMark(markData.hpMark); markData.hpMark = nil end
                        if markData.distMark then SafeRemoveMark(markData.distMark); markData.distMark = nil end
                    end
                    if _G.GTLMODConfig.EspRadar then
                        if not markData.radarMark or markData.radarMark == 0 then
                            markData.radarMark = SafeAddMark(8888, FVector(0,0,0), 0, "", 4, enemy)
                        end
                    else
                        if markData.radarMark and markData.radarMark ~= 0 then
                            SafeRemoveMark(markData.radarMark); markData.radarMark = nil
                        end
                    end

                    -- BOX ESP (CharacterBase-style frame UI)
                    pcall(function()
                        if _G.GTLMODConfig.Esp5 then
                            local hp = enemy.Health or 100
                            local maxHp = enemy.HealthMax or enemy.MaxHealth or 100
                            if maxHp <= 0 then maxHp = 100 end
                            local hpRatio = math.max(0, math.min(1, hp / maxHp))
                            if enemy.Replay_IsEnemyFrameUIExisted and not enemy:Replay_IsEnemyFrameUIExisted() then
                                pcall(function() enemy:Replay_CreateEnemyFrameUI(true, true) end)
                            end
                            if enemy.Replay_SetVisiableOfFrameUI then enemy:Replay_SetVisiableOfFrameUI(true) end
                            if enemy.Replay_UpdateEnemyFrameUI then enemy:Replay_UpdateEnemyFrameUI(hpRatio) end
                            local uiComp = enemy.EnemyFrameUI or (type(enemy.GetEnemyFrameUI) == "function" and enemy:GetEnemyFrameUI())
                            if Valid(uiComp) then
                                if type(uiComp.SetVisibility) == "function" then uiComp:SetVisibility(0) end
                                if type(uiComp.SetHiddenInGame) == "function" then uiComp:SetHiddenInGame(false) end
                            end
                        else
                            if enemy.Replay_SetVisiableOfFrameUI then enemy:Replay_SetVisiableOfFrameUI(false) end
                            local uiComp = enemy.EnemyFrameUI or (type(enemy.GetEnemyFrameUI) == "function" and enemy:GetEnemyFrameUI())
                            if Valid(uiComp) then
                                if type(uiComp.SetVisibility) == "function" then uiComp:SetVisibility(2) end
                                if type(uiComp.SetHiddenInGame) == "function" then uiComp:SetHiddenInGame(true) end
                            end
                        end
                    end)
                end
            end
            ::enemyContinue::
        end
    end)

    if _G.GTLMODConfig.AimDebug and Valid(Cached_MyHUD) then
        pcall(function()
            local status = _G.GTLMODState.AimLastFail or "?"
            local enemies = _G.GetEnemyTargetsFromActors(25000)
            local cnt = enemies and #enemies or 0
            local txt = string.format("[AIM] %s | Enemies: %d", status, cnt)
            Cached_MyHUD:AddDebugText(txt, localPlayer, 0.1, {X=0,Y=0,Z=200}, {X=0,Y=0,Z=200}, C_YELLOW, true, false, true, nil, 1.0, true)
        end)
    end
end

-- ====================================================================
-- LOOPS
-- ====================================================================
-- [FIXED] LoopToken prevents duplicate initialization within a match.
-- It does NOT reset user feature state (GTLMODConfig).
-- Match transitions increment LoopToken but preserve GTLMODConfig settings.
_G.GTLMODState.LoopToken = (_G.GTLMODState.LoopToken or 0) + 1
local myToken = _G.GTLMODState.LoopToken


-- Clear any leftover ESP marks on load (name/radar must not stay from old session)
pcall(function()
    if _G.GTLMODState and _G.GTLMODState.EnemyMarks then
        for k, data in pairs(_G.GTLMODState.EnemyMarks) do
            if type(data) == "table" then
                if data.radarMark then pcall(function() SafeRemoveMark(data.radarMark) end); data.radarMark = nil end
                if data.hpMark then pcall(function() SafeRemoveMark(data.hpMark) end); data.hpMark = nil end
                if data.distMark then pcall(function() SafeRemoveMark(data.distMark) end); data.distMark = nil end
            end
        end
        _G.GTLMODState.EnemyMarks = {}
    end
end)

local function MainTick()
    if isExpired then
        if not _G.GTLMODNotifiedExpire then
            _G.GTLMODNotifiedExpire = true
            -- Hard stop all running systems
                                    pcall(function() if _G.StopNewWallhack then _G.StopNewWallhack() end end)
            -- Zero out all boolean config flags
            pcall(function()
                if _G.GTLMODConfig then
                    for k, v in pairs(_G.GTLMODConfig) do
                        if type(v) == "boolean" then _G.GTLMODConfig[k] = false end
                    end
                end
            end)
            -- Show expiry message on screen (persistent)
            pcall(function()
                local sh = safeImport("ScriptHelperClient")
                if sh and sh.AddOnScreenDebugMessage then
                    sh.AddOnScreenDebugMessage("[MAGOO CORE] ⛔ EXPIRED — ALL FEATURES DISABLED", -1, 8.0, {R=1,G=0,B=0,A=1}, {X=1.5,Y=1.5})
                end
            end)
            Notify("MAGOO CORE EXPIRED — ALL FEATURES DISABLED")
        end
        return
    end
    if myToken ~= _G.GTLMODState.LoopToken then return end
    pcall(MainLoop)
    pcall(RunItemESPLite)
    local ticker = GetTicker()
    if ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(LIMITS.MAIN_TICK, MainTick)
    end
end

-- Dedicated FOV transition loop. MainLoop is intentionally much slower
-- because it handles heavier features; scope/FOV transitions need frame-rate
-- timing so they cannot produce a visible 0.5s state gap.
local function IpadFOVTick()
    if isExpired then return end
    if myToken ~= _G.GTLMODState.LoopToken then return end

    local ipadOn = _G.GTLMODConfig and _G.GTLMODConfig.IpadView == true
    if ipadOn then
        pcall(function()
            local pc = GameplayData.GetPlayerController()
            if not Valid(pc) then return end
            local localPlayer = pc:GetPlayerCharacterSafety()
            if not Valid(localPlayer) then return end
            ApplyIpadFOVState(pc, localPlayer)
        end)
    end

    local ticker = GetTicker()
    if ticker and ticker.AddTimerOnce then
        -- fast only while iPad is on; slow poll when off (prevents 60Hz empty work)
        ticker.AddTimerOnce(ipadOn and 0.033 or 0.40, IpadFOVTick)
    end
end

local function AimbotTick()
    if isExpired then return end
    if myToken ~= _G.GTLMODState.LoopToken then return end
    local on = _G.GTLMODConfig and _G.GTLMODConfig.AimTouchEnable == true
    if on then
        pcall(_G.AimTouch)
    end
    local ticker = GetTicker()
    if ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(on and LIMITS.AIMBOT_TICK or 0.35, AimbotTick)
    end
end

local function CounterTickLoop()
    if isExpired then return end
    if myToken ~= _G.GTLMODState.LoopToken then return end
    -- [FIXED] Flush BotCache every 60s to prevent unbounded memory growth / lag
    _G._CounterCacheFlushAt = _G._CounterCacheFlushAt or 0
    local _cNow = os.clock()
    if _cNow - _G._CounterCacheFlushAt > 60.0 then
        if RJCounter then RJCounter.BotCache = {} end
        -- [LAG FIX] Also flush distance and LOS caches — stale dead-actor entries accumulate
        _G._GTL_DistCache = {}
        _G._GTL_LOSCache  = {}
        _G._CounterCacheFlushAt = _cNow
    end
    -- CharacterBase-style MagooRedBox counter -- [LAG FIX] EnsureRunning moved out of 1s loop
    if _G.GTLMODConfig.CounterEnabled then
        -- MagooRedBox removed
        pcall(function()
            local players, bots = 0, 0
            local GD = GameplayData or package.loaded["GameLua.GameCore.Data.GameplayData"]
            local chars = GD and GD.GetAllPlayerCharacters and GD.GetAllPlayerCharacters()
            local localPlayer = nil
            local myTeam = -1
            pcall(function()
                if GD and GD.GetPlayerCharacter then
                    localPlayer = GD.GetPlayerCharacter()
                    if slua.isValid(localPlayer) then
                        myTeam = localPlayer.TeamID
                            or (type(localPlayer.GetTeamID) == "function" and localPlayer:GetTeamID())
                            or -1
                    end
                end
            end)
            if chars then
                for _, ch in pairs(chars) do
                    if slua.isValid(ch) and ch ~= localPlayer then
                        -- Check alive
                        local hp = 0
                        pcall(function()
                            hp = ch.Health or 0
                            if hp <= 0 and type(ch.IsAlive) == "function" then
                                hp = ch:IsAlive() and 1 or 0
                            end
                        end)
                        if hp > 0 then
                            -- CRITICAL: skip teammates
                            local chTeam = -2
                            pcall(function()
                                chTeam = ch.TeamID
                                    or (type(ch.GetTeamID) == "function" and ch:GetTeamID())
                                    or -2
                            end)
                            if chTeam ~= myTeam then
                                local isBot = false
                                pcall(function()
                                    if Game and Game.IsAI and Game:IsAI(ch) then isBot = true end
                                    if ch.bIsAI == true or ch.IsAI == true or ch.bIsAi == true then isBot = true end
                                    if not isBot then
                                        local PS = ch.PlayerState
                                        if slua.isValid(PS) then
                                            if PS.bIsABot == true or PS.bIsBot == true or PS.bIsAI == true then
                                                isBot = true
                                            end
                                        end
                                    end
                                    if not isBot and type(ch.IsBot) == "function" then
                                        local ok2, r2 = pcall(function() return ch:IsBot() end)
                                        if ok2 and r2 then isBot = true end
                                    end
                                end)
                                if isBot then bots = bots + 1 else players = players + 1 end
                            end
                        end
                    end
                end
            end
            if _G.RedBoxOverlay then
                if _G.GTLMODConfig and _G.GTLMODConfig.CounterEnabled then
                    -- [FIX] Validate container: if PlayerMapMarker rebuilt its canvas,
                    -- RedBoxOverlay.MainContainer becomes an orphaned widget. Detect and
                    -- clear it so the next Start() call re-creates it on the fresh canvas.
                    pcall(function()
                        local RBO = _G.RedBoxOverlay
                        if RBO.MainContainer then
                            local ok = slua and slua.isValid and slua.isValid(RBO.MainContainer)
                            if not ok then
                                RBO.bActive = false; RBO.MainContainer = nil
                                RBO.WidgetSlot = nil; RBO.TextBlockPlayer = nil
                                RBO.TextBlockBot = nil; RBO._CachedPosVec = nil
                            end
                        end
                    end)
                    if not _G.RedBoxOverlay.bActive then pcall(_G.RedBoxOverlay.Start) end
                    pcall(function() _G.RedBoxOverlay.SetCounts(players, bots) end)
                    -- [LAG FIX] UpdatePosition removed from hot loop (set at Create time)
                end
            end
        end)
    else
        -- MagooRedBox removed
    end
    -- keep old RJCounter off to avoid double HUD
    if _G.RJCounter and _G.RJCounter.SetEnabled then
        pcall(function() _G.RJCounter.SetEnabled(false) end)
    end
    local ticker = GetTicker()
    if ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(1.15, CounterTickLoop)
    end
end

local function ESPLineTickLoop()
    -- PlayerMapMarker owns ESP lines (old green ESPLine removed)
    if isExpired then return end
    if myToken ~= _G.GTLMODState.LoopToken then return end
    if _G.GTLMODConfig and _G.GTLMODConfig.EspLine and _G.PlayerMapMarker then
        if not _G.PlayerMapMarker.bActive then
            if _G.PlayerMapMarker.EnsureRunning then
                pcall(_G.PlayerMapMarker.EnsureRunning)
            elseif _G.PlayerMapMarker.Start then
                pcall(_G.PlayerMapMarker.Start)
            end
        end
    end
    local ticker = GetTicker()
    local lineOn = _G.GTLMODConfig and _G.GTLMODConfig.EspLine == true
    if ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(lineOn and LIMITS.ESP_LINE_UPDATE or 0.50, ESPLineTickLoop)
    end
end

-- Private mod menu features tick: small crosshair + force aimbot
local function PrivFeaturesTick()
    if isExpired then return end
    if myToken ~= _G.GTLMODState.LoopToken then return end

    local now = os.clock()

    -- Small crosshair via HackerWeaponFeatures
    pcall(function()
        local pawn = GameplayData and GameplayData.GetPlayerCharacter and GameplayData.GetPlayerCharacter()
        if not (pawn and slua.isValid(pawn)) then return end
        if _G.GTLMODConfig.PrivSmallCrosshair then
            if not _G.PrivWeaponInstance then
                _G.PrivWeaponInstance = HackerWeaponFeatures.new(_G)
            end
            _G.PrivWeaponInstance:update(pawn, { smallCrosshair = true }, now)
        else
            if _G.PrivWeaponInstance then
                _G.PrivWeaponInstance:update(pawn, { smallCrosshair = false }, now)
                -- Dispose when fully restored
                if not _G.PrivWeaponInstance.restoring then
                    pcall(_G.PrivWeaponInstance.dispose, _G.PrivWeaponInstance)
                    _G.PrivWeaponInstance = nil
                end
            end
        end
    end)

    -- Force aimbot HIP (fire-only, neck/chest) — works hip + scope
    -- Always respect saved toggle; never auto-off across matches
    local forceOn = (_G.GTLMODConfig and _G.GTLMODConfig.ForceAimbot == true)
        or (_G._ForceAimbotWanted == true)
    if forceOn then
        if _G.GTLMODConfig then _G.GTLMODConfig.ForceAimbot = true end
        pcall(PrivAimbotTick)
    end

    local anyPriv = (_G.GTLMODConfig and (_G.GTLMODConfig.PrivSmallCrosshair or _G.GTLMODConfig.ForceAimbot))
        or (_G._ForceAimbotWanted == true)
    local ticker = GetTicker()
    if ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(anyPriv and LIMITS.AIMBOT_TICK or 0.40, PrivFeaturesTick)
    end
end

if not isExpired then
    local ticker = GetTicker()
    if ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(0.2, MainTick)
        ticker.AddTimerOnce(0.2, AimbotTick)
        ticker.AddTimerOnce(0.2, PrivFeaturesTick)
        ticker.AddTimerOnce(0.016, IpadFOVTick)
        ticker.AddTimerOnce(1.15, CounterTickLoop)
        ticker.AddTimerOnce(LIMITS.ESP_LINE_UPDATE, ESPLineTickLoop)
    end
    Notify("MAGOO CORE loaded | " .. gameRegion .. " (" .. packageName .. ")")
else
    local ticker = GetTicker()
    if ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(0.2, MainTick)
    end
end

-- ====================================================================
-- AUTO-HEAD HOOKS
-- ====================================================================
_G.InitializeAutoHeadHooks = function()
    pcall(function()
        local EAvatarDamagePosition = safeImport("EAvatarDamagePosition")
        if not EAvatarDamagePosition then return end
        for _, path in ipairs({"GameLua.Mod.BaseMod.Common.Weapon.ShootWeaponEntity", "GameLua.Logic.Weapon.ShootWeaponEntity"}) do
            local hitLogic = package.loaded[path]
            if hitLogic then
                local orig1 = hitLogic.GetHitBodyType
                hitLogic.GetHitBodyType = function(self, ImpactResult, InImpactVec)
                    if _G.GTLMODConfig.AutoHead then return EAvatarDamagePosition.BigHead end
                    if orig1 then return orig1(self, ImpactResult, InImpactVec) end
                end
                local orig2 = hitLogic.GetHitBodyTypeByHitPos
                hitLogic.GetHitBodyTypeByHitPos = function(self, InImpactVec)
                    if _G.GTLMODConfig.AutoHead then return EAvatarDamagePosition.BigHead end
                    if orig2 then return orig2(self, InImpactVec) end
                end
            end
        end
    end)
end
pcall(_G.InitializeAutoHeadHooks)

-- ====================================================================
-- INIT ALL
-- ====================================================================
_G.EnsureModFeaturesRunning = function()
    if isExpired then return end
    pcall(function()
        local c = _G.GTLMODConfig or {}
        local L = _G.LexusConfig or {}
        _G.LexusConfig = L
        local any = c.EspLine or c.CounterEnabled or c.EspModelName or c.EspWeaponIcon
        L.EspLoai9 = any and true or false
        L.Esp9_Count = c.CounterEnabled == true
        L.Esp9_Name = c.EspModelName == true
        L.Esp9_HP = (c.EspModelName == true) and (c.EspShowHealthBar ~= false)
        L.Esp9_Team = (c.EspModelName == true) and (c.EspTeamColorBox ~= false)
        L.Esp9_Weapon = c.EspWeaponIcon == true
        L.Esp9_Distance = (c.EspModelName == true) and (c.EspShowDistance ~= false)
        L.Esp9_Line = c.EspLine == true
        L.EspActiveBom = c.EspActiveBom == true
        L.EspBomMaster = c.EspActiveBom == true

        -- [LAG FIX] Use lightweight Start check (EnsureRunning is expensive, called by syncBridge)
        if _G.PlayerMapMarker and not _G.PlayerMapMarker.bActive and L.EspLoai9 then
            if _G.PlayerMapMarker.Start then pcall(_G.PlayerMapMarker.Start) end
        end

        if c.CounterEnabled then
            if _G.RedBoxOverlay and _G.RedBoxOverlay.Start then pcall(_G.RedBoxOverlay.Start) end
        elseif _G.RedBoxOverlay and _G.RedBoxOverlay.bActive and _G.RedBoxOverlay.Stop then
            pcall(_G.RedBoxOverlay.Stop)
        end

        if c.WallhackSmart then
            if NewWallhack then
                NewWallhack.WH_TIMER = nil
                NewWallhack.Active = false
            end
            if _G.StartNewWallhack then pcall(_G.StartNewWallhack) end
        elseif NewWallhack and NewWallhack.Active and _G.StopNewWallhack then
            pcall(_G.StopNewWallhack)
        end

        if c.IpadView and _G.GTLMODState and not _G.GTLMODState.CustomTextData then
            _G.GTLMODState.CustomTextData = { OuterSpeed = 10, InnerSpeed = 10, HRecoil = 0.3, VRecoil = 0.3, IpadViewFOV = 120 }
        end
        if (c.TargetFPS or c.FPSStabilizer) and _G.GTLMODState then
            _G.GTLMODState.GraphicsUnlocked = false
        end

    end)
end

local function InitAllModSystems()
    if isExpired then return end
    pcall(function()
        if _G.InitializeAutoHeadHooks then _G.InitializeAutoHeadHooks() end
        if _G.InitModMenuTab then _G.InitModMenuTab() end
        pcall(_G.EnsureModFeaturesRunning)
    end)
end
_G.InitAllModSystems = InitAllModSystems
-- Tickers + InitAll start after online login via StartAuthenticatedRuntime


-- ====================================================================
-- PUBLIC ESP API
-- ====================================================================
function BRPlayerCharacterBase:ESP_Start()
    if _G.PlayerMapMarker and _G.PlayerMapMarker.Start then
        pcall(_G.PlayerMapMarker.Start)
    end
end

function BRPlayerCharacterBase:ESP_Stop()
    if _G.PlayerMapMarker and _G.PlayerMapMarker.Stop then
        pcall(_G.PlayerMapMarker.Stop)
    end
end

function BRPlayerCharacterBase:ESP_Toggle()
    local c = _G.GTLMODConfig
    if not c then return false end
    c.EspLine = not c.EspLine
    if c.EspLine then
        self:ESP_Start()
    else
        self:ESP_Stop()
    end
    return c.EspLine
end

function BRPlayerCharacterBase:ESP_IsEnabled()
    return _G.GTLMODConfig and _G.GTLMODConfig.EspLine or false
end

function BRPlayerCharacterBase:ESP_IsRunning()
    return _G.PlayerMapMarker and _G.PlayerMapMarker.bActive or false
end

-- ====================================================================
-- CLASS METHODS
-- ====================================================================
function BRPlayerCharacterBase:ctor() end

function BRPlayerCharacterBase:_PostConstruct()
  BRPlayerCharacterBase.__super._PostConstruct(self)
  self:InitAddSpecialMoveInfo()
  self.bCanNearDeathGiveup = true
end

function BRPlayerCharacterBase:ReceiveBeginPlay()
  BRPlayerCharacterBase.__super.ReceiveBeginPlay(self)
  self:AddControlEvent(self, "MovementModeChangedDelegate", self.HandleOnMovementModeChangedNew, self)
  if self:HasAuthority() and self:CheckAddCheckFallingDistanceComponent() then
    local CheckFallingDistanceComponent_C = safeImport("CheckFallingDistanceComponent")
    if slua.isValid(CheckFallingDistanceComponent_C) and not slua.isValid(self:GetComponentByClass(CheckFallingDistanceComponent_C)) then
      Game:AddComponent(CheckFallingDistanceComponent_C, self, "CheckFallingDistanceComponent")
    end
  end
  if slua.isValid(self.STCharacterMovement) then self.STCharacterMovement.bPositiveBlowUp = true end
  if self.Role == ENetRole.ROLE_AutonomousProxy then
    self:AddControlEvent(self, "OnPawnStateDisabled", self.OnPawnStateChange, self)
    self:AddControlEvent(self, "OnPawnStateEnabled", self.OnPawnStateChange, self)
    self:AddControlEventConditionOnly(self, "OnAttrChangeEventDelegate", { AttrName = { "bCanSelfRescue" } }, self.CharacterAttrChangeEvent, self)
  end
  if Client then
    GameplayData.AddCharacter(self.Object)
    self:AddControlEvent(self, "OnAttachedToVehicle", self.HandleOnAttachedToVehicle, self)
    self:AddControlEvent(self, "OnDetachedFromVehicle", self.HandleOnDetachedFromVehicle, self)
    if not isExpired and self.Role == ENetRole.ROLE_AutonomousProxy then
      pcall(function()
        if type(_G.EnsureModFeaturesRunning) == "function" then
          _G.EnsureModFeaturesRunning()
        end
        local tk = package.loaded["common.time_ticker"] or require("common.time_ticker")
        if tk and tk.AddTimerOnce then
          tk.AddTimerOnce(0.8, function()
            pcall(function()
              if type(_G.EnsureModFeaturesRunning) == "function" then _G.EnsureModFeaturesRunning() end
            end)
          end)
          tk.AddTimerOnce(2.5, function()
            pcall(function()
              if type(_G.EnsureModFeaturesRunning) == "function" then _G.EnsureModFeaturesRunning() end
            end)
          end)
        end
      end)
    end
  else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, { [1] = "FinishedState" }, self.HandleFinishedState, self)
  end
end

function BRPlayerCharacterBase:HandleOnAttachedToVehicle(uVehicle) if slua.isValid(uVehicle) then self:ClearAttachToVehicleTimer() end end
function BRPlayerCharacterBase:HandleOnDetachedFromVehicle(uLastVehicle) if slua.isValid(uLastVehicle) then self:ClearAttachToVehicleTimer() end end
function BRPlayerCharacterBase:UpdatePlayerAttachToVehicle() end
function BRPlayerCharacterBase:FixMeshContainerOffsetIfNeeded() end
function BRPlayerCharacterBase:ClearAttachToVehicleTimer()
  if self.nUpdatePlayerAttachToVehicleTimer then
    self:RemoveGameTimer(self.nUpdatePlayerAttachToVehicleTimer)
    self.nUpdatePlayerAttachToVehicleTimer = nil  end
  if self.nFixMeshContainerTimer then
    self:RemoveGameTimer(self.nFixMeshContainerTimer)
    self.nFixMeshContainerTimer = nil
  end
end

function BRPlayerCharacterBase:CharacterAttrChangeEvent(uPawn, AttrName, AttrVal)
  BRPlayerCharacterBase.__super.CharacterAttrChangeEvent(self, uPawn, AttrName, AttrVal)
  if self.Object ~= uPawn then return end
  if self.Role == ENetRole.ROLE_AutonomousProxy and AttrName == "bCanSelfRescue" then
    local pc = self:GetPlayerControllerSafety()
    if slua.isValid(pc) then pc:BroadcastUIMessage("UIMsg_CanSelfRescue", 0, "", "") end
  end
end

function BRPlayerCharacterBase:OnPawnStateChange(PawnState)
  local EPS = import("EPawnState")
  if PawnState == EPS.SwitchPP then
    local pc = self:GetPlayerControllerSafety()
    if slua.isValid(pc) then pc:BroadcastUIMessage("UIMsg_FPPModeChange", 0, "", "") end
  end
end

function BRPlayerCharacterBase:HandleFinishedState()
  if slua.isValid(self.STCharacterMovement) and self.STCharacterMovement.SetDynamicSimpleQueryConfig then
    self.STCharacterMovement:SetDynamicSimpleQueryConfig(false)
  end
end

function BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent() return false end
function BRPlayerCharacterBase:LuaHandleParachuteStateChanged(LastParachuteState, NewParachuteState)
  BRPlayerCharacterBase.__super.LuaHandleParachuteStateChanged(self, LastParachuteState, NewParachuteState)
end
function BRPlayerCharacterBase:OnLanded()
  if self.HandleOnLanded then self:HandleOnLanded(-1) end
end
function BRPlayerCharacterBase:ReceiveEndPlay(EndPlayReason)
  BRPlayerCharacterBase.__super.ReceiveEndPlay(self, EndPlayReason)
  if Client then GameplayData.RemoveCharacter(self.Object) end
end
function BRPlayerCharacterBase:IsWarGameMode() return false end
function BRPlayerCharacterBase:BPOnRecycled() if Client then self:ResetMeshRelativeLocationAndRotation() end end
function BRPlayerCharacterBase:BPOnRespawned() if Client then self:ResetMeshRelativeLocationAndRotation() end end
function BRPlayerCharacterBase:ReceiveOnRecycle() if Client then self:ResetMeshRelativeLocationAndRotation(); GameplayData.RemoveCharacter(self.Object) end end
function BRPlayerCharacterBase:ReceiveOnSpawn() if Client then self:ResetMeshRelativeLocationAndRotation(); GameplayData.AddCharacter(self.Object) end end
function BRPlayerCharacterBase:ResetMeshRelativeLocationAndRotation()
  if Game:IsValid(self.Object) and Game:IsValid(self.Mesh) then
    local rot = FRotator(0, -90, 0)
    if self.Mesh.K2_SetRelativeRotation then self.Mesh:K2_SetRelativeRotation(rot, false, nil, false) end
    self:CacheInitialMeshOffset(FVector(0, 0, 0), rot)
  end
end

function BRPlayerCharacterBase:HandleOnMovementModeChangedNew()
  local EMovementMode = import("EMovementMode")
  if Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Swimming and self:CheckBaseIsMoveable() then
    self.CharacterMovement:SetBase(nil, "", true)
  end
end

function BRPlayerCharacterBase:BPOnMissPlayerDamageRecord() end
function BRPlayerCharacterBase:ClientRPC_TriggerHighlightMoment(Type, Param)
  EventSystem:postEvent(EVENTTYPE_INGAME, EVENTID_INGAME_TRIGGER_HIGHLIGHT_MOMENT, Type, Param)
end
function BRPlayerCharacterBase:ParachuteJump()
  local pc = self:GetControllerSafety()
  if slua.isValid(pc) and not self:GetEnsure() then
    local EStateType = import("EStateType")
    if pc:GetCurrentStateType() ~= EStateType.State_ParachuteJump and pc:GetCurrentStateType() ~= EStateType.State_ParachuteOpen then
      local EPS = import("ESTEPoseState")
      self:SwitchPoseState(EPS.Stand, true, true, true, false)
      pc:ReInitParachuteItem()
      pc:ServerChangeStatePC(EStateType.State_ParachuteJump)
    end
  end
end
function BRPlayerCharacterBase:CheckForbidFlaregun()
  local ps = self:GetPlayerStateSafety()
  if not slua.isValid(ps) then return false end
  return not ps.CanUseFlaregun
end
function BRPlayerCharacterBase:ServerRPC_NearDeathGiveupRescue() self:HandleNearDeathGiveupRescue() end
function BRPlayerCharacterBase:HandleNearDeathGiveupRescue() end
function BRPlayerCharacterBase:RPC_Server_GmPlayAction(actionId) end
function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(actionId) end
function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(b) if slua.isValid(self.ParachuteComponent) then self.ParachuteComponent.bServerSyncShouldCheckPassWall = b end end
function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState() self.Super:OnPlayerEnterCarryBoxState(); if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState() end end
function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(b) self.Super:OnPlayerLeaveCarryBoxState(b); if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(b) end end
function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(u)
  if slua.isValid(u) and Game:IsClassOf(u, import("/Script/ShadowTrackerExtra.PlayerTombBox")) and self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:CarryDeadBox(u)
  end
end
function BRPlayerCharacterBase:SetAreaID(a) self:SetAttrValue("AreaID", a, -1) end
function BRPlayerCharacterBase:GetAreaID() return math.floor(self:GetAttrValue("AreaID") + 0.5) end
function BRPlayerCharacterBase:CannotChangeIntoPetSpectator() return self.bCannotChangeIntoPetSpectator end
function BRPlayerCharacterBase:DoModChangeToBT() if self:HasState(EPawnState.SpecialSuit) then self:TriggerEntrySkillWithID(4301101, true) end end
function BRPlayerCharacterBase:SwitchCameraToParachuteOpening() self.Super:SwitchCameraToParachuteOpening() end
function BRPlayerCharacterBase:SwitchCameraToParachuteFalling() self.Super:SwitchCameraToParachuteFalling() end
function BRPlayerCharacterBase:SwitchCameraToNormal() self.Super:SwitchCameraToNormal() end
function BRPlayerCharacterBase:SwitchWeaponCheck(Slot, IgnoreState) return self.Super:SwitchWeaponCheck(Slot, IgnoreState) end

-- [FIXED] Aimbot kill hook removed — no longer needed.

-- ====================================================================
-- AUTO FEEDBACK — ported from CharacterBase.lua
-- Sends Top-1 win screenshot to Telegram via Cloudflare worker.
-- Same bot_token + chat_id as original.
-- Only fires on real wins (kills > 5 AND rank >= Silver if rank readable).
-- ====================================================================
if not isExpired then
pcall(function()

local AutoFeedback = {
    Config = {
        ServerURL = "YOUR_FEEDBACK_WORKER_URL_HERE",
        TestMode = false
    },
    Hooked = false
}

local function AFLog(message)
    local IST_OFFSET = 19800
    print(string.format("[MAGOO_FB] [%s IST] %s", os.date("!%H:%M:%S", os.time() + IST_OFFSET), tostring(message)))
end

local function AFNotify(message)
    if _G.SRCHUBNotify then pcall(_G.SRCHUBNotify, message)
    elseif _G.Notify then pcall(_G.Notify, message) end
end

local function AFGetModule(name, allowRequire)
    local loaded = package and package.loaded and package.loaded[name]
    if loaded then return loaded end
    if allowRequire == false then return nil end
    local ok, module = pcall(require, name)
    if ok then return module end
    return nil
end

local function AFAddTimerOnce(delay, callback)
    local ticker = AFGetModule("common.time_ticker")
    if ticker and type(ticker.AddTimerOnce) == "function" then
        ticker.AddTimerOnce(delay, callback)
        return true
    end
    return false
end

local function AFBase64Encode(data)
    if type(data) ~= "string" or #data == 0 then return "" end
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local output = {}
    local outputIndex = 0
    local index = 1
    while index <= #data - 2 do
        local a, b, c = string.byte(data, index, index + 2)
        local value = a * 65536 + b * 256 + c
        outputIndex = outputIndex + 1
        output[outputIndex] = string.char(
            string.byte(alphabet, math.floor(value / 262144) + 1),
            string.byte(alphabet, math.floor(value / 4096) % 64 + 1),
            string.byte(alphabet, math.floor(value / 64) % 64 + 1),
            string.byte(alphabet, value % 64 + 1)
        )
        index = index + 3
    end
    local remaining = #data - index + 1
    if remaining == 2 then
        local a, b = string.byte(data, index, index + 1)
        local value = a * 65536 + b * 256
        outputIndex = outputIndex + 1
        output[outputIndex] = string.char(
            string.byte(alphabet, math.floor(value / 262144) + 1),
            string.byte(alphabet, math.floor(value / 4096) % 64 + 1),
            string.byte(alphabet, math.floor(value / 64) % 64 + 1),
            string.byte("=")
        )
    elseif remaining == 1 then
        local value = string.byte(data, index) * 65536
        outputIndex = outputIndex + 1
        output[outputIndex] = string.char(
            string.byte(alphabet, math.floor(value / 262144) + 1),
            string.byte(alphabet, math.floor(value / 4096) % 64 + 1),
            string.byte("="),
            string.byte("=")
        )
    end
    return table.concat(output)
end

local function AFUrlEncode(value)
    if value == nil then return nil end
    value = tostring(value):gsub("\n", "\r\n")
    value = value:gsub("([^A-Za-z0-9 %-%_%.%~])", function(character)
        return string.format("%%%02X", string.byte(character))
    end)
    value = value:gsub(" ", "+")
    return value
end

local function AFReadFile(path)
    local file = io.open(path, "rb")
    if not file then return "" end
    local data = file:read("*a") or ""
    file:close()
    return data
end

local function AFRemoveFile(path)
    pcall(os.remove, path)
end

local function AFGetRankName(rank)
    if rank < 1700 then return "Bronze"
    elseif rank < 2200 then return "Silver"
    elseif rank < 2700 then return "Gold"
    elseif rank < 3200 then return "Platinum"
    elseif rank < 3700 then return "Diamond"
    elseif rank < 4200 then return "Crown"
    elseif rank < 4700 then return "Ace"
    elseif rank < 5200 then return "Ace Master"
    elseif rank < 5600 then return "Ace Dominator"
    end
    return "Conqueror"
end

local AFCaptionTemplate = "<b>THE_MAGOO AUTO FEEDBACK</b>\n<pre>\nPlayer - %s\nUID    - %s\nTime   - %s\nKills  - %d\nRank   - %s\n</pre>\n[ ACTIVE - SAFE ]\n<b>Owner: @THE_MAGOO</b>"

function AutoFeedback.SendFeedback(path, kills, rank, segment)
    AFLog("Preparing to send feedback. Screenshot: " .. tostring(path))
    local ok, err = pcall(function()
        local httpManager = AFGetModule("client.slua.logic.http.http_manager")
        if not httpManager or type(httpManager.Post) ~= "function" then
            AFLog("HTTP manager unavailable.")
            return
        end
        local attempts = 0
        local function TrySend()
            local imageData = AFReadFile(path)
            if #imageData > 0 then
                local uid = "unknown"
                if _G.DataMgr and _G.DataMgr.roleData and _G.DataMgr.roleData.uid then
                    uid = tostring(_G.DataMgr.roleData.uid)
                elseif _G._KONG_UK then
                    uid = tostring(_G._KONG_UK)
                end
                kills = tonumber(kills) or 0
                rank  = tonumber(rank)  or 0
                segment = tonumber(segment) or 0
                local maskedUid = "***"
                if uid ~= "unknown" and #uid > 5 then
                    maskedUid = uid:sub(1,3) .. "***" .. uid:sub(-2)
                end
                local IST_OFFSET = 19800
                local caption = string.format(
                    AFCaptionTemplate,
                    "*****",
                    maskedUid,
                    os.date("!%H:%M:%S %d/%m/%Y IST", os.time() + IST_OFFSET),
                    kills,
                    AFGetRankName(rank)
                )
                local encodedImage = AFBase64Encode(imageData)
                encodedImage = encodedImage:gsub("%+", "%%2B")
                encodedImage = encodedImage:gsub("/", "%%2F")
                encodedImage = encodedImage:gsub("=", "%%3D")
                AFNotify("[MAGOO] Uploading Top 1 screenshot to VIP Server...")
                local body = "base64_image=" .. encodedImage
                    .. "&caption=" .. AFUrlEncode(caption)
                    .. "&bot_token=" .. AFUrlEncode("YOUR_BOT_TOKEN_HERE")
                    .. "&chat_id=" .. AFUrlEncode("YOUR_CHAT_ID_HERE")
                httpManager:Post(
                    AutoFeedback.Config.ServerURL,
                    {["Content-Type"] = "application/x-www-form-urlencoded"},
                    body,
                    nil,
                    function(success, _, response, errorMessage)
                        if success and response and tostring(response):find('"status":%s*true') then
                            AFNotify("[MAGOO] Feedback sent! (Kills: " .. tostring(kills) .. ")")
                        else
                            local detail = tostring(response or errorMessage):sub(1,40)
                            AFNotify("[MAGOO] VIP Server error: " .. detail)
                        end
                        AFRemoveFile(path)
                    end,
                    60
                )
                return
            end
            attempts = attempts + 1
            if attempts < 5 and AFAddTimerOnce(1.0, TrySend) then return end
            AFNotify("[MAGOO] Screenshot capture failed!")
            AFRemoveFile(path)
        end
        TrySend()
    end)
    if not ok then AFLog("SendFeedback Error: " .. tostring(err)) end
end

local AFHudNames = {
    "BattleChat_UIBP","Chat_UIBP","ChatMsg_UIBP","TeamAvatar_UIBP","Team_UIBP",
    "VoiceChat_UIBP","MiniMap_UIBP","Bag_UIBP","PickUp_UIBP","PickUpList_UIBP",
    "SystemChat_UIBP","InGameChat_UIBP","InGameChatPanel_UIBP","KillFeed_UIBP",
    "Elimination_UIBP","ChatHUD_UIBP","ChatPanel_UIBP","MainHUD_UIBP","BattleHUD_UIBP"
}

local function AFCreateHudController()
    local hidden = {}
    local function SetHidden(hide)
        local UIManager = _G.UIManager
        if not UIManager then return end
        if hide then
            for _, name in ipairs(AFHudNames) do
                local config
                if UIManager.UI_Config_InGame and UIManager.UI_Config_InGame[name] then
                    config = UIManager.UI_Config_InGame[name]
                elseif UIManager.UI_Config and UIManager.UI_Config[name] then
                    config = UIManager.UI_Config[name]
                end
                if config then
                    local view = type(UIManager.GetUI) == "function" and UIManager.GetUI(config) or nil
                    if view then
                        pcall(function()
                            if type(view.SetVisibility) == "function" then
                                view:SetVisibility(2)
                            elseif view.UIRoot and type(view.UIRoot.SetVisibility) == "function" then
                                view.UIRoot:SetVisibility(2)
                            elseif type(UIManager.HideUI) == "function" then
                                UIManager.HideUI(config)
                            end
                        end)
                        table.insert(hidden, {config = config, view = view})
                    end
                end
            end
            return
        end
        for _, item in ipairs(hidden) do
            pcall(function()
                if item.view and type(item.view.SetVisibility) == "function" then
                    item.view:SetVisibility(0)
                elseif item.view and item.view.UIRoot and type(item.view.UIRoot.SetVisibility) == "function" then
                    item.view.UIRoot:SetVisibility(0)
                elseif type(UIManager.ShowUI) == "function" then
                    UIManager.ShowUI(item.config)
                end
            end)
        end
        hidden = {}
    end
    return SetHidden
end

local function AFGetScreenshotDir()
    local dirs = {}
    local home = os.getenv("HOME")
    if home and home ~= "" then
        table.insert(dirs, home .. "/Documents/ShadowTrackerExtra/Saved/")
    end
    local pkgs = {"com.tencent.ig","com.vng.pubgmobile","com.pubg.krmobile","com.rekoo.pubgm","com.pubg.imobile"}
    for _, pkg in ipairs(pkgs) do
        table.insert(dirs, "/storage/emulated/0/Android/data/" .. pkg .. "/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/")
    end
    local selected = dirs[1]
    for _, dir in ipairs(dirs) do
        local tp = dir .. "t.tmp"
        local f = io.open(tp, "w")
        if f then f:close(); os.remove(tp); selected = dir; break end
    end
    return selected
end

local function AFCaptureAndSend(kills, rank, segment, restoreHud)
    local restored = false
    local function RestoreOnce()
        if not restored then restored = true; restoreHud(false) end
    end
    local SM = import("ScreenshotMaker")
    if not SM then RestoreOnce(); return end
    local dir = AFGetScreenshotDir()
    if not dir then RestoreOnce(); return end
    local path = dir .. string.format("kongwin_%s.jpg", os.time())
    local uiUtil = AFGetModule("client.common.ui_util")
    local gameInstance = uiUtil and uiUtil.GetGameInstance and uiUtil.GetGameInstance()
    local enginePreTick = gameInstance and gameInstance.EnginePreTick
    if not enginePreTick or type(enginePreTick.Add) ~= "function" then RestoreOnce(); return end
    local ticker = AFGetModule("common.time_ticker")
    if not ticker or type(ticker.AddTimerOnce) ~= "function" then RestoreOnce(); return end
    enginePreTick:Add(function()
        local actualPath = SM.MakePictureByName(path, true)
        if type(enginePreTick.Clear) == "function" then enginePreTick:Clear() end
        if actualPath and actualPath ~= "" then path = actualPath end
        local attempts = 0
        local function CheckCapture()
            attempts = attempts + 1
            local captured = false
            pcall(function() captured = SM.HasCaptured(path) end)
            if captured then
                RestoreOnce()
                AFLog("HasCaptured=true. Flushing...")
                pcall(SM.ResizePicture, path, 0.9, path)
                ticker.AddTimerOnce(2.0, function()
                    if #AFReadFile(path) > 0 then
                        AutoFeedback.SendFeedback(path, kills, rank, segment)
                    else
                        AFNotify("[MAGOO] iOS image read error!")
                    end
                end)
            elseif attempts < 15 then
                ticker.AddTimerOnce(1, CheckCapture)
            else
                RestoreOnce()
                AFNotify("[MAGOO] Screenshot capture failed!")
            end
        end
        ticker.AddTimerOnce(1, CheckCapture)
    end)
end

function AutoFeedback.ProcessWin(kills)
    kills = tonumber(kills) or 0
    local rank, segment = 0, 0
    pcall(function()
        local battleResult = _G.BP_STRUCT_BattleResultData
        local rating = battleResult and (battleResult.rating or battleResult.BP_STRUCT_BTRating)
        if rating then
            rank = tonumber(rating.rank_rating) or 0
            segment = tonumber(rating.new_segment) or 0
        end
        if rank == 0 then
            local roleData = _G.DataMgr and _G.DataMgr.roleData
            if roleData and roleData.segment_rating then
                for _, value in pairs(roleData.segment_rating) do
                    if type(value) == "table" then
                        for _, nv in pairs(value) do
                            if type(nv) == "number" and nv > rank then rank = nv end
                        end
                    elseif type(value) == "number" and value > rank then
                        rank = value
                    end
                end
            end
        end
    end)

    local now = os.clock()
    if _G._MAGOO_FeedbackSentAt and (now - _G._MAGOO_FeedbackSentAt) < 120.0 then
        AFLog(string.format("Skipping feedback: sent %.1fs ago", now - _G._MAGOO_FeedbackSentAt))
        return
    end
    if _G._MAGOO_FeedbackInFlight then
        AFLog("Skipping feedback: in progress")
        return
    end
    if kills <= 5 then
        AFLog(string.format("Skipping feedback: Kill %d (need > 5)", kills))
        return
    end
    if rank > 0 and rank < 2200 then
        AFLog(string.format("Skipping feedback: Rank %d (need >= 2200)", rank))
        return
    end
    _G._MAGOO_FeedbackSentAt = now
    _G._MAGOO_FeedbackInFlight = true
    AFNotify("[MAGOO] Congratulations! TOP 1!")
    local setHudHidden = AFCreateHudController()
    setHudHidden(true)
    local ok, err = pcall(AFCaptureAndSend, kills, rank, segment, setHudHidden)
    if not ok then
        setHudHidden(false)
        _G._MAGOO_FeedbackInFlight = false
        AFLog("ProcessWin Error: " .. tostring(err))
    else
        AFAddTimerOnce(25.0, function() _G._MAGOO_FeedbackInFlight = false end)
    end
end

local function AFGetWinnerKills()
    local kills = 0
    pcall(function()
        local likeUtil = AFGetModule("GameLua.Mod.BaseMod.Client.Like.IngameLikeUtilClient")
        if likeUtil and type(likeUtil.GetMyPlayerState) == "function" then
            local ps = likeUtil.GetMyPlayerState()
            if ps and ps.Kills then kills = tonumber(ps.Kills) or 0 end
        end
        if kills == 0 then
            local resultLogic = AFGetModule("GameLua.Mod.BaseMod.Client.BattleResult.BattleResultData.BattleResultDataLogic", false)
            if resultLogic and type(resultLogic.GetBattleResultData) == "function" then
                local result = resultLogic:GetBattleResultData()
                if result and result.BP_mykill then kills = tonumber(result.BP_mykill) or 0 end
            end
        end
    end)
    return kills
end

local function AFTryInstallHook()
    pcall(function()
        local UIManager = _G.UIManager
        if not UIManager or not UIManager.ShowUI then return end
        if UIManager.__MAGOOHooked then AutoFeedback.Hooked = true; return end
        AFLog("Hooking UIManager.ShowUI for Winner UI...")
        local originalShowUI = UIManager.ShowUI
        UIManager.ShowUI = function(config, params, ...)
            local result = originalShowUI(config, params, ...)
            pcall(function()
                local now = os.clock()
                if _G._MAGOO_FeedbackSentAt and (now - _G._MAGOO_FeedbackSentAt) < 120.0 then return end
                if _G._MAGOO_FeedbackInFlight then return end
                local inGameConfig = UIManager.UI_Config_InGame or {}
                local winnerConfigs = {
                    inGameConfig.GameOverCountDown_UIBP,
                    inGameConfig.GameOver_UIBP,
                    inGameConfig.BattleResult_UIBP,
                    inGameConfig.Result_UIBP,
                }
                local isWinnerUI = false
                for _, wc in ipairs(winnerConfigs) do
                    if wc and config == wc then isWinnerUI = true; break end
                end
                local keyName = ""
                pcall(function()
                    keyName = tostring((config and (config.keyName or config.KeyName or config.UIKey)) or "")
                end)
                if keyName ~= "" then
                    local kl = string.lower(keyName)
                    if kl:find("gameover") or kl:find("battleresult") or kl:find("battle_result")
                        or kl == "result_uibp" or kl:find("winlogo") or kl:find("winner") then
                        isWinnerUI = true
                    end
                end
                local isWinner = params and (
                    params.Reason == "win" or params.Reason == "Win" or params.Reason == "WIN"
                    or params.ShowedWinLogo == true or params.bWin == true or params.IsWin == true
                    or params.Winner == true or tostring(params.Reason or ""):lower() == "win"
                )
                if not isWinnerUI or not isWinner then return end
                if _G._MAGOO_FeedbackScheduled then return end
                _G._MAGOO_FeedbackScheduled = true
                local kills = AFGetWinnerKills()
                if not AFAddTimerOnce(2, function()
                    _G._MAGOO_FeedbackScheduled = false
                    AutoFeedback.ProcessWin(kills)
                end) then
                    _G._MAGOO_FeedbackScheduled = false
                    AutoFeedback.ProcessWin(kills)
                end
            end)
            return result
        end
        UIManager.__MAGOOHooked = true
        AutoFeedback.Hooked = true
        AFLog("UIManager Hook installed.")
    end)
end

function AutoFeedback.Install()
    AFLog("Installing AutoFeedback (Cloudflare+Telegram)...")
    local ticker = AFGetModule("common.time_ticker")
    AFTryInstallHook()
    if ticker and type(ticker.AddTimerOnce) == "function" then
        ticker.AddTimerOnce(2.0, AFTryInstallHook)
        ticker.AddTimerOnce(5.0, AFTryInstallHook)
        ticker.AddTimerOnce(12.0, AFTryInstallHook)
    end
end

_G.THE_MAGOO_AutoFeedback_BR = AutoFeedback
AutoFeedback.Install()

end) -- end pcall for AutoFeedback
end  -- end if not isExpired



-- ============================================================
-- EXACT STAR LUA ESP LOẠI 9 (PlayerMapMarker + RedBox + SnapLine + Name/HP/Team/Weapon)
-- Config bridge: GTLMODConfig (BR menu) -> Esp9_* (Star logic)
-- ============================================================
pcall(function()
if _G._StarExactESP9 then return end
_G._StarExactESP9 = true

-- Bridge so exact Star code keeps using _G.LexusConfig.Esp9_*
_G.LexusConfig = _G.LexusConfig or {}
local function syncBridge()
    local c = _G.GTLMODConfig or {}
    local L = _G.LexusConfig
    -- master on if any feature requested
    local any = c.EspLine or c.CounterEnabled or c.EspModelName or c.EspWeaponIcon
    L.EspLoai9 = any and true or false
    L.Esp9_Count = c.CounterEnabled == true
    L.Esp9_Name = c.EspModelName == true
    L.Esp9_HP = (c.EspModelName == true) and (c.EspShowHealthBar ~= false)
    L.Esp9_Team = (c.EspModelName == true) and (c.EspTeamColorBox ~= false)
    L.Esp9_Weapon = c.EspWeaponIcon == true
    L.Esp9_Distance = (c.EspModelName == true) and (c.EspShowDistance ~= false)
    L.Esp9_Line = c.EspLine == true
    L.Esp9_Skeleton = false  -- not requested
    L.EspActiveBom = c.EspActiveBom == true
    L.EspBomMaster = c.EspActiveBom == true
    L.EspItemBom = false  -- do not import ground grenade ESP
end
syncBridge()
-- keep bridge fresh
do
    local tk = nil
    pcall(function() tk = require("common.time_ticker") end)
    if tk and tk.AddTimerOnce then
        local function loop()
            pcall(syncBridge)
            pcall(function()
                if _G.PlayerMapMarker and _G.PlayerMapMarker.EnsureRunning then
                    _G.PlayerMapMarker.EnsureRunning()
                elseif _G.PlayerMapMarker and _G.PlayerMapMarker.Start then
                    local L = _G.LexusConfig
                    if L and L.EspLoai9 then
                        if not _G.PlayerMapMarker.bActive then _G.PlayerMapMarker.Start() end
                    elseif _G.PlayerMapMarker.bActive then
                        _G.PlayerMapMarker.Stop()
                    end
                end
            end)
            tk.AddTimerOnce(2.0, loop) -- [LAG FIX] was 0.5s, 2s is enough for config sync
        end
        tk.AddTimerOnce(2.0, loop)
    end
end


local PlayerMapMarker = {}

local RedBoxOverlay = {
    bActive = false,
    MainContainer = nil,
    WidgetSlot = nil,
    TextBlockPlayer = nil,
    TextBlockBot = nil,
    Width = 280,
    Height = 30,
    OffsetY = 12,
    PlayerCount = 0,
    BotCount = 0,
    FontSize = 14,
    TextScaleValue = 1.0,
    NumLayers = 50,
    Red = 0.32,
    Green = 0.06,
    Blue = 0.48,
    LayerAlpha = 0.038,
    _CachedTextPlayer = "",
    _CachedTextBot = "",
    _CachedPosVec = nil,
    _Layers = nil
}

function RedBoxOverlay.Create()
    if RedBoxOverlay.MainContainer and slua.isValid(RedBoxOverlay.MainContainer) then return true end

    local ParentCanvas = PlayerMapMarker.ESPCanvas
    if not ParentCanvas or not slua.isValid(ParentCanvas) then
        if not PlayerMapMarker.InitESPCanvas then return false end
        if not PlayerMapMarker.InitESPCanvas() then return false end
        ParentCanvas = PlayerMapMarker.ESPCanvas
    end
    if not ParentCanvas or not slua.isValid(ParentCanvas) then return false end

    local Container = nil
    pcall(function() Container = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", ParentCanvas) end)
    if not Container or not slua.isValid(Container) then return false end

    local FLinearColor = import("LinearColor")
    local FVector2D = import("Vector2D")
    local FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")

    -- ===== Same layered taper. Colour is a dark-purple / green wash. =====
    local numLayers = RedBoxOverlay.NumLayers
    local totalWidth = RedBoxOverlay.Width
    RedBoxOverlay._Layers = {}

    for i = 1, numLayers do
        local progress = (i / numLayers) ^ 1.15
        local layerWidth = progress * totalWidth
        local layerX = (totalWidth - layerWidth) / 2.0

        local border = nil
        pcall(function() border = CGame:NewObjectFromPath("/Script/UMG.Border", Container) end)
        if border and slua.isValid(border) then
            pcall(function()
                border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            end)
            local slot = Container:AddChildToCanvas(border)
            if slot then
                slot:SetPosition(FVector2D(layerX, 0))
                slot:SetSize(FVector2D(layerWidth, RedBoxOverlay.Height))
            end
            RedBoxOverlay._Layers[#RedBoxOverlay._Layers + 1] = border
        end
    end
    RedBoxOverlay.ApplySweep()

    -- ===== Center divider (thin white line) =====
    local divider = nil
    pcall(function() divider = CGame:NewObjectFromPath("/Script/UMG.Border", Container) end)
    if divider and slua.isValid(divider) then
        pcall(function()
            divider:SetBrushColor(FLinearColor(1.0, 1.0, 1.0, 0.35))
            divider:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
        local dSlot = Container:AddChildToCanvas(divider)
        if dSlot then
            dSlot:SetPosition(FVector2D(totalWidth * 0.5 - 0.5, 5))
            dSlot:SetSize(FVector2D(1, RedBoxOverlay.Height - 10))
            dSlot:SetZOrder(999)
        end
    end

    local whiteColor = FLinearColor(1.0, 1.0, 1.0, 1.0)

    -- ===== LEFT: Player count =====
    local txtPlayer = nil
    pcall(function() txtPlayer = CGame:NewObjectFromPath("/Script/UMG.TextBlock", Container) end)
    if txtPlayer and slua.isValid(txtPlayer) then
        pcall(function()
            local strText = string.format("PLAYER  %d", RedBoxOverlay.PlayerCount)
            txtPlayer:SetText(strText)
            RedBoxOverlay._CachedTextPlayer = strText
            if FSlateColor then txtPlayer:SetColorAndOpacity(FSlateColor(whiteColor))
            else txtPlayer:SetColorAndOpacity(whiteColor) end
            if txtPlayer.Font then
                local font = txtPlayer.Font
                font.Size = RedBoxOverlay.FontSize
                txtPlayer.Font = font
            end
            txtPlayer:SetRenderScale(FVector2D(RedBoxOverlay.TextScaleValue, RedBoxOverlay.TextScaleValue))
            txtPlayer:SetRenderTransformPivot(FVector2D(0.5, 0.5))
            txtPlayer:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
        local txtSlot1 = Container:AddChildToCanvas(txtPlayer)
        if txtSlot1 then
            pcall(function()
                txtSlot1:SetAutoSize(true)
                txtSlot1:SetAlignment(FVector2D(0.5, 0.5))
                txtSlot1:SetPosition(FVector2D(totalWidth * 0.28, RedBoxOverlay.Height * 0.5))
                txtSlot1:SetZOrder(1000)
            end)
        end
        RedBoxOverlay.TextBlockPlayer = txtPlayer
    end

    -- ===== RIGHT: Bot count =====
    local txtBot = nil
    pcall(function() txtBot = CGame:NewObjectFromPath("/Script/UMG.TextBlock", Container) end)
    if txtBot and slua.isValid(txtBot) then
        pcall(function()
            local strText = string.format("BOT  %d", RedBoxOverlay.BotCount)
            txtBot:SetText(strText)
            RedBoxOverlay._CachedTextBot = strText
            if FSlateColor then txtBot:SetColorAndOpacity(FSlateColor(whiteColor))
            else txtBot:SetColorAndOpacity(whiteColor) end
            if txtBot.Font then
                local font = txtBot.Font
                font.Size = RedBoxOverlay.FontSize
                txtBot.Font = font
            end
            txtBot:SetRenderScale(FVector2D(RedBoxOverlay.TextScaleValue, RedBoxOverlay.TextScaleValue))
            txtBot:SetRenderTransformPivot(FVector2D(0.5, 0.5))
            txtBot:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
        local txtSlot2 = Container:AddChildToCanvas(txtBot)
        if txtSlot2 then
            pcall(function()
                txtSlot2:SetAutoSize(true)
                txtSlot2:SetAlignment(FVector2D(0.5, 0.5))
                txtSlot2:SetPosition(FVector2D(totalWidth * 0.72, RedBoxOverlay.Height * 0.5))
                txtSlot2:SetZOrder(1000)
            end)
        end
        RedBoxOverlay.TextBlockBot = txtBot
    end

    local MainSlot = nil
    pcall(function() MainSlot = ParentCanvas:AddChildToCanvas(Container) end)
    if not MainSlot then return false end

    RedBoxOverlay.MainContainer = Container
    RedBoxOverlay.WidgetSlot = MainSlot

    pcall(function()
        MainSlot:SetAutoSize(false)
        MainSlot:SetZOrder(999)
        MainSlot:SetAlignment(FVector2D(0.5, 0.0))
        MainSlot:SetSize(FVector2D(RedBoxOverlay.Width, RedBoxOverlay.Height))
    end)

    RedBoxOverlay.UpdatePosition()
    return true
end

function RedBoxOverlay.SetCounts(players, bots)
    if RedBoxOverlay.PlayerCount == players and RedBoxOverlay.BotCount == bots then return end
    RedBoxOverlay.PlayerCount = players or 0
    RedBoxOverlay.BotCount = bots or 0

    if RedBoxOverlay.TextBlockPlayer and slua.isValid(RedBoxOverlay.TextBlockPlayer) then
        pcall(function()
            local strP = string.format("PLAYER  %d", RedBoxOverlay.PlayerCount)
            if RedBoxOverlay._CachedTextPlayer ~= strP then
                RedBoxOverlay.TextBlockPlayer:SetText(strP)
                RedBoxOverlay._CachedTextPlayer = strP
            end
        end)
    end
    if RedBoxOverlay.TextBlockBot and slua.isValid(RedBoxOverlay.TextBlockBot) then
        pcall(function()
            local strB = string.format("BOT  %d", RedBoxOverlay.BotCount)
            if RedBoxOverlay._CachedTextBot ~= strB then
                RedBoxOverlay.TextBlockBot:SetText(strB)
                RedBoxOverlay._CachedTextBot = strB
            end
        end)
    end
end

function RedBoxOverlay.ApplySweep()
    local layers = RedBoxOverlay._Layers
    if not layers or #layers == 0 then return end
    local LC = import("LinearColor")
    if not LC then return end
    -- slow wash, not a blink. one full cycle ~ 7s
    local wave = (math.sin(os.clock() * 0.9) + 1) * 0.5
    local n = #layers
    local a = RedBoxOverlay.LayerAlpha
    for i = 1, n do
        local border = layers[i]
        if border and slua.isValid(border) then
            local along = i / n
            local mix = along * 0.62 + wave * 0.38
            if mix < 0 then mix = 0 elseif mix > 1 then mix = 1 end
            -- dark purple -> deep green, blended across the same layers
            local r = 0.34 + (0.04 - 0.34) * mix
            local g = 0.05 + (0.42 - 0.05) * mix
            local b = 0.52 + (0.16 - 0.52) * mix
            pcall(function() border:SetBrushColor(LC(r, g, b, a)) end)
        end
    end
end

function RedBoxOverlay.UpdatePosition()
    pcall(RedBoxOverlay.ApplySweep)
    local Slot = RedBoxOverlay.WidgetSlot
    if not Slot or not slua.isValid(Slot) then return end
    if not PlayerMapMarker.GetMyPlayerController then return end
    local PC = PlayerMapMarker.GetMyPlayerController()
    if not slua.isValid(PC) then return end
    if not PlayerMapMarker.GetSnapLineStartPos then return end

    local fromX, fromY = PlayerMapMarker.GetSnapLineStartPos(PC)
    local FVector2D = import("Vector2D")
    pcall(function()
        if not RedBoxOverlay._CachedPosVec then
            RedBoxOverlay._CachedPosVec = FVector2D(fromX, fromY)
        else
            RedBoxOverlay._CachedPosVec.X = fromX
            RedBoxOverlay._CachedPosVec.Y = fromY
        end
        Slot:SetPosition(RedBoxOverlay._CachedPosVec)
    end)
end

function RedBoxOverlay.Start()
    if RedBoxOverlay.bActive and RedBoxOverlay.MainContainer and slua.isValid(RedBoxOverlay.MainContainer) then return end
    if RedBoxOverlay.Create() then
        RedBoxOverlay.bActive = true
        pcall(function() RedBoxOverlay.MainContainer:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
    end
end

function RedBoxOverlay.Stop()
    RedBoxOverlay.bActive = false
    if RedBoxOverlay.MainContainer and slua.isValid(RedBoxOverlay.MainContainer) then
        pcall(function()
            RedBoxOverlay.MainContainer:RemoveFromParent()
            RedBoxOverlay.MainContainer:ConditionalBeginDestroy()
        end)
    end
    RedBoxOverlay.MainContainer = nil
    RedBoxOverlay.WidgetSlot = nil
    RedBoxOverlay.TextBlockPlayer = nil
    RedBoxOverlay.TextBlockBot = nil
    RedBoxOverlay._CachedPosVec = nil
    RedBoxOverlay._Layers = nil
end

_G.RedBoxOverlay = RedBoxOverlay

local InGameMarkTools = nil
pcall(function() InGameMarkTools = require("GameLua.Mod.BaseMod.Common.InGameMarkTools") end)

local SlateBlueprintLibrary = nil
local WidgetLayoutLibrary = nil
local KismetMathLibrary = nil
local KismetSystemLibrary = nil

pcall(function() SlateBlueprintLibrary = import("SlateBlueprintLibrary") or import("/Script/UMG.SlateBlueprintLibrary") end)
pcall(function() WidgetLayoutLibrary = import("WidgetLayoutLibrary") or import("/Script/UMG.WidgetLayoutLibrary") end)
pcall(function() KismetMathLibrary = import("KismetMathLibrary") end)
pcall(function() KismetSystemLibrary = import("KismetSystemLibrary") end)

local FVector2D = _G.FVector2D or import("Vector2D")
local FLinearColor = _G.FLinearColor or import("LinearColor")
local FVector = _G.FVector or import("Vector")

PlayerMapMarker.MarkTypeID = 1007
PlayerMapMarker.bUseScreenESP = true
PlayerMapMarker.bUseScreenMark = false
PlayerMapMarker.bUseQuickSign = false
PlayerMapMarker.bUseNavigator = false
PlayerMapMarker.bUseWidgetComponent = false
PlayerMapMarker.QuickSignConfigKey = "C_MarkPos"

PlayerMapMarker.WidgetCompUIPath = "/Game/BluePrints/ControlInput/NewbieItem/NewbieTips_ConsumeTips.NewbieTips_ConsumeTips"
PlayerMapMarker.WidgetCompBoneName = "head"
PlayerMapMarker.WidgetCompOffset = FVector and FVector(0, 0, 80) or {X=0, Y=0, Z=80}
PlayerMapMarker.WidgetCompDrawSize = FVector2D and FVector2D(210, 35) or {X=210, Y=35} -- [SIZE 70%]

PlayerMapMarker.ESPBoneName = "head"
PlayerMapMarker.ESPWorldOffsetZ = 0
PlayerMapMarker.ESPScreenOffsetY = 0
PlayerMapMarker.ESPAnchorOffsetX = 35 -- [SIZE 70%]
PlayerMapMarker.ESPAnchorOffsetY = 0
PlayerMapMarker.ESPTextOffsetX = 0
PlayerMapMarker.ESPTextOffsetY = 0

PlayerMapMarker.ESPWidgetAlignment = FVector2D and FVector2D(0.5, 1.0) or {X=0.5, Y=1.0}
PlayerMapMarker.ESPWidgetSize = FVector2D and FVector2D(70, 21) or {X=70, Y=21} -- [SIZE 70%]
PlayerMapMarker.ESPWidgetAutoSize = true
PlayerMapMarker.ESPWidgetZOrder = 2

PlayerMapMarker.bShowDistance = true
PlayerMapMarker.DistanceUnit = "m"
PlayerMapMarker.WeaponIconBrushW = 96 -- [SIZE 70%] Gốc 138
PlayerMapMarker.WeaponIconBrushH = 48 -- [SIZE 70%] Gốc 69
PlayerMapMarker.HPWidgetSwitcherTypeIndex = 0
PlayerMapMarker.HPWidgetSwitcherType2Index = 0
PlayerMapMarker.bForceSwitcherIndexEveryUpdate = true

PlayerMapMarker.bUseSnapLines = true
PlayerMapMarker.SnapLineThickness = 1.0 -- [SIZE 70%] Gốc 1.5
PlayerMapMarker.SnapLineOriginY = 50
PlayerMapMarker.SnapLineOriginOffsetX = 0
PlayerMapMarker.SnapLineHeadOffsetX = 0
PlayerMapMarker.SnapLineHeadOffsetY = -14 -- [SIZE 70%] Gốc -20
PlayerMapMarker.SnapLineColor = FLinearColor and FLinearColor(0.0, 0.4, 1.0, 1.0) or {R=0, G=100, B=255, A=255} -- Blue
PlayerMapMarker.SnapLineOpacity = 0.7

-- ====== BẮT ĐẦU: CẤU HÌNH SKELETON (TỪ CODE MẪU) ======
PlayerMapMarker.bUseSkeleton = true                      -- Tùy chọn bật Skeleton
PlayerMapMarker.SkeletonThickness = 0.8                  -- [SIZE 70%] Gốc 1.2                  
PlayerMapMarker.SkeletonColor = nil                      
PlayerMapMarker.SkeletonOpacity = 0.8                    
PlayerMapMarker.SkeletonMaxDistance = 100000             
PlayerMapMarker.bUseVisibilityColor = true              
PlayerMapMarker.SkeletonVisibleColor = FLinearColor and FLinearColor(0.0, 1.0, 0.0, 0.8) or {R=0,G=255,B=0,A=200}
PlayerMapMarker.SkeletonCoverColor = FLinearColor and FLinearColor(0.9, 0.0, 0.0, 0.6) or {R=230,G=0,B=0,A=150}

PlayerMapMarker.SkeletonWidgets = {}
PlayerMapMarker._StaticBoneLocCache = {}

PlayerMapMarker.SkeletonChains = {
    {"neck_01", "lowerarm_r", "hand_r"},
    {"neck_01", "lowerarm_l", "hand_l"},
    {"head", "neck_01", "pelvis"},
    {"pelvis", "calf_r", "foot_r"},
    {"pelvis", "calf_l", "foot_l"}
}

PlayerMapMarker.BoneNameFallbacks = {
    ["head"] = {"head", "Head", "head_socket"},
    ["neck_01"] = {"neck_01", "Neck_01", "neck", "Neck"},
    ["clavicle_r"] = {"clavicle_r", "Clavicle_R", "clavicle_R"},
    ["upperarm_r"] = {"upperarm_r", "UpperArm_R", "arm_r", "arm_r_01"},
    ["lowerarm_r"] = {"lowerarm_r", "LowerArm_R", "forearm_r"},
    ["hand_r"] = {"hand_r", "Hand_R", "hand_r_socket"},
    ["clavicle_l"] = {"clavicle_l", "Clavicle_L", "clavicle_L"},
    ["upperarm_l"] = {"upperarm_l", "UpperArm_L", "arm_l", "arm_l_01"},
    ["lowerarm_l"] = {"lowerarm_l", "LowerArm_L", "forearm_l"},
    ["hand_l"] = {"hand_l", "Hand_L", "hand_l_socket"},
    ["spine_03"] = {"spine_03", "Spine_03", "spine_02", "spine"},
    ["spine_02"] = {"spine_02", "Spine_02", "spine_01"},
    ["pelvis"] = {"pelvis", "Pelvis", "hip"},
    ["thigh_r"] = {"thigh_r", "Thigh_R", "leg_r"},
    ["calf_r"] = {"calf_r", "Calf_R", "shin_r"},
    ["foot_r"] = {"foot_r", "Foot_R", "foot_r_socket"},
    ["thigh_l"] = {"thigh_l", "Thigh_L", "leg_l"},
    ["calf_l"] = {"calf_l", "Calf_L", "shin_l"},
    ["foot_l"] = {"foot_l", "Foot_L", "foot_l_socket"},
}
-- ====== KẾT THÚC: CẤU HÌNH SKELETON ======

PlayerMapMarker.MapAddedFlag = 4
PlayerMapMarker.nUpdateInterval = 0.5
PlayerMapMarker.bUseFrameTick = false
PlayerMapMarker.nHeavyScanFrameInterval = 15
PlayerMapMarker.nDistanceUpdateFrameInterval = 5
PlayerMapMarker.bIncludeMe = false
PlayerMapMarker.bIncludeAI = true
PlayerMapMarker.bUseServerMarks = false

PlayerMapMarker.bActive = false
PlayerMapMarker.MarkMap = {}
PlayerMapMarker.PlayerInfo = {}
PlayerMapMarker.ESPCanvas = nil
PlayerMapMarker.ESPWidgets = {}
PlayerMapMarker.ESPWidgetPtrs = {}
PlayerMapMarker.SnapLineWidgets = {}

PlayerMapMarker._cachedViewportW = 1920
PlayerMapMarker._cachedViewportH = 1080
PlayerMapMarker._FrameCount = 0
PlayerMapMarker._bTickRegistered = false
PlayerMapMarker._CachedAllChars = nil
PlayerMapMarker._CachedMyLoc = nil
PlayerMapMarker._CachedMyKey = nil
PlayerMapMarker.WidgetComps = {}
PlayerMapMarker._bAllPathsFailed = false
PlayerMapMarker._bLightUpdateScheduled = false
PlayerMapMarker._LightUpdateInterval = 0.05 -- [LAG FIX] 20Hz light pass; keeps ESP responsive without a 50Hz render loop
PlayerMapMarker._bDistanceUpdateScheduled = false
PlayerMapMarker._DistanceUpdateInterval = 0.1
PlayerMapMarker._bScreenMarkConfigSetup = false
-- [STABILITY] Own every repeating timer so match transitions cannot accumulate callbacks.
PlayerMapMarker._TimerHandles = {}
PlayerMapMarker._TimerGeneration = 0

local function IsValid(obj)
    if obj == nil then return false end
    if slua and slua.isValid then return slua.isValid(obj) end
    return obj ~= nil
end

function PlayerMapMarker.SetupScreenMarkConfig()
    if PlayerMapMarker._bScreenMarkConfigSetup then return true end
    local bOK = false
    pcall(function()
        local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
        local ScreenMarkConfig = GamePlayTools.GetCurrentConfig("ScreenMarkConfig")
        if ScreenMarkConfig then
            ScreenMarkConfig[1007] = {
                UIPathName = "/Game/BluePrints/UI/OBUI/Item/OB_PlayerHeadHPItem_UIBP.OB_PlayerHeadHPItem_UIBP_C",
                MaxWidgetNum = 100,
                MaxShowDistance = 6000000,
                bBindOutScreen = false,
                bBindBlocked = true,
                bNeedPreLoad = true,
                bIsBindingActor = true,
                BindSocketName = "HelmetSocket",
                WorldPositionOffset = FVector and FVector(0, 0, 80) or {X=0,Y=0,Z=80}
            }
            PlayerMapMarker._bScreenMarkConfigSetup = true
            bOK = true
        end
    end)
    return bOK
end

function PlayerMapMarker.GetGameplayData()
    if PlayerMapMarker._CachedGameplayData then return PlayerMapMarker._CachedGameplayData end
    local ok, GDP = pcall(function() return require("GameLua.GameCore.Data.GameplayData") end)
    if ok and GDP then PlayerMapMarker._CachedGameplayData = GDP return GDP end
    return nil
end

function PlayerMapMarker.GetMyPlayerController()
    local PC = PlayerMapMarker._CachedPC
    if PC and IsValid(PC) then return PC end
    local GDP = PlayerMapMarker.GetGameplayData()
    if not GDP then return nil end
    pcall(function() PC = GDP.GetPlayerController and GDP.GetPlayerController() end)
    if PC and IsValid(PC) then PlayerMapMarker._CachedPC = PC return PC end
    return nil
end

function PlayerMapMarker.GetCGameState()
    if CGameState and IsValid(CGameState) then return CGameState end
    if PlayerMapMarker._CachedCGameState and IsValid(PlayerMapMarker._CachedCGameState) then return PlayerMapMarker._CachedCGameState end
    local ok, GS = pcall(function() return require("GameLua.GameCore.Data.CGameState") end)
    if ok and GS then PlayerMapMarker._CachedCGameState = GS return GS end
    return nil
end

function PlayerMapMarker.GetAllCharacters()
    local AllChars = {}
    pcall(function()
        local Pawns = Game:GetAllPlayerPawns()
        if Pawns then
            for _, Pawn in pairs(Pawns) do
                if Pawn and slua.isValid(Pawn) then
                    local pKey = nil
                    if Pawn.GetPlayerKey then pKey = Pawn:GetPlayerKey() end
                    if not pKey and Pawn.PlayerKey then pKey = Pawn.PlayerKey end
                    if not pKey and Pawn.PlayerState and Pawn.PlayerState.PlayerKey then pKey = Pawn.PlayerState.PlayerKey end
                    if pKey then AllChars[pKey] = Pawn end
                end
            end
        end
    end)
    if not next(AllChars) then
        local GS = PlayerMapMarker.GetCGameState()
        if GS and GS.GetAllCharacters then pcall(function() AllChars = GS:GetAllCharacters() end) end
    end
    return AllChars
end

function PlayerMapMarker.GetMyPlayerKey()
    local PC = PlayerMapMarker.GetMyPlayerController()
    if not IsValid(PC) then return nil end
    local MyKey = nil
    pcall(function()
        if PC.GetPlayerKey then MyKey = PC:GetPlayerKey()
        elseif PC.PlayerState and PC.PlayerState.PlayerKey then MyKey = PC.PlayerState.PlayerKey end
    end)
    return MyKey
end

function PlayerMapMarker.IsMe(Character, PlayerKey, MyKey)
    local bIsMe = false
    pcall(function()
        local GDP = PlayerMapMarker.GetGameplayData()
        if GDP and GDP.GetLocalCharacter then
            local MyChar = GDP.GetLocalCharacter()
            if MyChar and Character == MyChar then bIsMe = true return end
        end
        local PC = PlayerMapMarker.GetMyPlayerController()
        if PC and PC.GetPawn then
            local Pawn = PC:GetPawn()
            if Pawn and Character == Pawn then bIsMe = true return end
        end
    end)
    if not bIsMe and MyKey ~= nil and PlayerKey ~= nil then bIsMe = (tostring(PlayerKey) == tostring(MyKey)) end
    return bIsMe
end

function PlayerMapMarker.GetCharacterLocation(Character)
    if not IsValid(Character) then return nil end
    local Loc = nil
    pcall(function() if Character.K2_GetActorLocation then Loc = Character:K2_GetActorLocation() end end)
    if not Loc then pcall(function() if Game and Game.GetActorLocation then Loc = Game:GetActorLocation(Character) end end) end
    return Loc
end

function PlayerMapMarker.CalcDistance(Loc1, Loc2)
    if not Loc1 or not Loc2 then return nil end
    local Dist = nil
    pcall(function() if FVector and FVector.Dist2D then Dist = FVector.Dist2D(Loc1, Loc2) end end)
    if not Dist then
        pcall(function()
            local DX = (Loc1.X or 0) - (Loc2.X or 0)
            local DY = (Loc1.Y or 0) - (Loc2.Y or 0)
            Dist = math.sqrt(DX * DX + DY * DY)
        end)
    end
    return Dist
end

function PlayerMapMarker.GetDistanceString(MyLoc, TargetLoc)
    if not PlayerMapMarker.bShowDistance then return "" end
    if not MyLoc or not TargetLoc then return "" end
    local Dist = PlayerMapMarker.CalcDistance(MyLoc, TargetLoc)
    if not Dist then return "" end
    local Meters = Dist / 100
    if Meters < 1000 then return string.format("%dm", math.floor(Meters))
    else return string.format("%.1fkm", Meters / 1000) end
end

function PlayerMapMarker.GetMyLocation()
    local GDP = PlayerMapMarker.GetGameplayData()
    if not GDP then return nil end
    local MyChar = nil
    pcall(function() MyChar = GDP.GetLocalCharacter and GDP.GetLocalCharacter() end)
    if not IsValid(MyChar) then
        local PC = PlayerMapMarker.GetMyPlayerController()
        if IsValid(PC) then
            pcall(function()
                if PC.GetPawn then
                    local Pawn = PC:GetPawn()
                    if IsValid(Pawn) and Pawn.K2_GetActorLocation then return Pawn:K2_GetActorLocation() end
                end
            end)
        end
        return nil
    end
    return PlayerMapMarker.GetCharacterLocation(MyChar)
end

function PlayerMapMarker.GetPlayerName(Character)
    if not IsValid(Character) then return "Unknown" end
    local Name = nil
    pcall(function() if Character.GetPlayerNameSafety then Name = Character:GetPlayerNameSafety() end end)
    if not Name then
        pcall(function()
            local PS = nil
            if Character.GetPlayerStateSafety then PS = Character:GetPlayerStateSafety()
            elseif Character.GetPlayerState then PS = Character:GetPlayerState() end
            if IsValid(PS) and PS.GetPlayerName then Name = PS:GetPlayerName() end
        end)
    end
    return Name or "Unknown"
end

function PlayerMapMarker.IsAI(Character)
    local bAI = false
    pcall(function() if Game and Game.IsAI then bAI = Game:IsAI(Character) end end)
    return bAI
end

function PlayerMapMarker.IsAlive(Character)
    local bAlive = true
    pcall(function() if Character.IsAlive then bAlive = Character:IsAlive() end end)
    return bAlive
end

function PlayerMapMarker.IsOurESPWidget(w)
    if not w or not slua.isValid(w) then return false end
    local bIsOurs = false
    pcall(function()
        local wstr = tostring(w)
        for KeyStr, ESPData in pairs(PlayerMapMarker.ESPWidgets) do
            if ESPData and ESPData.Widget and ESPData.Widget.Container then
                local cstr = tostring(ESPData.Widget.Container)
                if cstr == wstr then bIsOurs = true return end
            end
        end
    end)
    if bIsOurs then return true end
    pcall(function()
        if w.GetChildrenCount then
            local n = w:GetChildrenCount()
            for i = 0, n - 1 do
                local child = w:GetChildAt(i)
                if child and slua.isValid(child) then
                    local cstr = tostring(child)
                    if string.find(cstr, "Border") then bIsOurs = true break end
                end
            end
        end
    end)
    if not bIsOurs then
        pcall(function()
            local slot = w.Slot
            if slot and slot.GetPosition then
                local pos = slot:GetPosition()
                if pos and (math.abs(pos.X or 0) > 1 or math.abs(pos.Y or 0) > 1) then bIsOurs = true end
            end
        end)
    end
    return bIsOurs
end

function PlayerMapMarker.ApplyAnchorBasedPosition(Slot, ScreenPos, Canvas)
    if not Slot or not ScreenPos then return false end
    local sx = ScreenPos.X or 0
    local sy = ScreenPos.Y or 0
    local sz = PlayerMapMarker.ESPWidgetSize or (FVector2D and FVector2D(100, 30) or {X=100, Y=30})
    local align = PlayerMapMarker.ESPWidgetAlignment or (FVector2D and FVector2D(0.5, 1.0) or {X=0.5, Y=1.0})

    local canvasW, canvasH = 0, 0
    if PlayerMapMarker._cachedViewportW and PlayerMapMarker._cachedViewportW > 200 then
        canvasW = PlayerMapMarker._cachedViewportW
        canvasH = PlayerMapMarker._cachedViewportH
    end

    if canvasW < 200 then
        pcall(function()
            local PC = PlayerMapMarker.GetMyPlayerController()
            if IsValid(PC) and PC.GetViewportSize then
                local VS = FVector2D and FVector2D(0, 0) or {X=0, Y=0}
                PC:GetViewportSize(VS)
                if VS and VS.X and VS.X > 200 then
                    canvasW = VS.X ; canvasH = VS.Y
                    PlayerMapMarker._cachedViewportW = canvasW ; PlayerMapMarker._cachedViewportH = canvasH
                end
            end
        end)
    end

    if canvasW > 200 and canvasH > 200 then
        local anchorX = (sx + (PlayerMapMarker.ESPAnchorOffsetX or 0)) / canvasW
        local anchorY = (sy + (PlayerMapMarker.ESPAnchorOffsetY or 0)) / canvasH
        anchorX = math.max(0, math.min(1, anchorX))
        anchorY = math.max(0, math.min(1, anchorY))

        local bSuccess = false
        pcall(function()
            local FAnchors = import("Anchors") or import("/Script/SlateCore.Anchors")
            if Slot.SetAnchors and FAnchors then
                local anchors = FAnchors(anchorX, anchorY, anchorX, anchorY)
                if anchors then Slot:SetAnchors(anchors) Slot:SetPosition(FVector2D and FVector2D(0, 0) or {X=0, Y=0}) bSuccess = true end
            end
        end)
        if not bSuccess then
            pcall(function()
                if Slot.SetAnchors then Slot:SetAnchors(anchorX, anchorY, anchorX, anchorY) Slot:SetPosition(FVector2D and FVector2D(0, 0) or {X=0, Y=0}) bSuccess = true end
            end)
        end
        if bSuccess then
            pcall(function() if Slot.SetOffsets and import("Margin") then Slot:SetOffsets(import("Margin")(0, 0, sz.X, sz.Y)) end end)
            pcall(function() Slot:SetSize(sz) end)
            pcall(function() Slot:SetAlignment(align) end)
            pcall(function() if Slot.SetAutoSize then Slot:SetAutoSize(PlayerMapMarker.ESPWidgetAutoSize or true) end end)
            pcall(function() if Slot.SetZOrder then Slot:SetZOrder(PlayerMapMarker.ESPWidgetZOrder or 2) end end)
            return true
        end
    end

    pcall(function()
        Slot:SetPosition(FVector2D and FVector2D(sx, sy) or {X=sx, Y=sy})
        pcall(function() Slot:SetSize(sz) end)
        pcall(function() Slot:SetAlignment(align) end)
        pcall(function() if Slot.SetAutoSize then Slot:SetAutoSize(PlayerMapMarker.ESPWidgetAutoSize or true) end end)
        pcall(function() if Slot.SetZOrder then Slot:SetZOrder(PlayerMapMarker.ESPWidgetZOrder or 2) end end)
    end)
    return false
end

function PlayerMapMarker.InitESPCanvas()
    if PlayerMapMarker.ESPCanvas and Game:IsValid(PlayerMapMarker.ESPCanvas) then return true end
    local InGameUITools = nil
    pcall(function() InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools") end)
    if not InGameUITools then return false end
    local MainControlBaseUI = nil
    pcall(function() MainControlBaseUI = InGameUITools.GetMainControlBaseUI() end)
    if not MainControlBaseUI or not Game:IsValid(MainControlBaseUI) then return false end

    local ParentCanvas = nil
    pcall(function()
        if MainControlBaseUI.CanvasPanel_0 and Game:IsValid(MainControlBaseUI.CanvasPanel_0) then ParentCanvas = MainControlBaseUI.CanvasPanel_0
        elseif MainControlBaseUI.CanvasPanel_42 and Game:IsValid(MainControlBaseUI.CanvasPanel_42) then ParentCanvas = MainControlBaseUI.CanvasPanel_42 end
    end)

    if not ParentCanvas then return false end
    PlayerMapMarker.ESPCanvas = ParentCanvas

    pcall(function()
        local nChildren = ParentCanvas:GetChildrenCount()
        for i = nChildren - 1, 0, -1 do
            local child = ParentCanvas:GetChildAt(i)
            if child and slua.isValid(child) then
                if PlayerMapMarker.IsOurESPWidget(child) then pcall(function() ParentCanvas:RemoveChild(child) end) end
            end
        end
    end)
    return true
end

function PlayerMapMarker.FindProgressBarInWidget(WidgetObj, Depth, MaxDepth)
    if not WidgetObj or not slua.isValid(WidgetObj) then return nil end
    Depth = Depth or 0 ; MaxDepth = MaxDepth or 5
    if Depth > MaxDepth then return nil end

    local bIsPB = false
    pcall(function() if WidgetObj.SetPercent and WidgetObj.SetFillColorAndOpacity then bIsPB = true end end)
    if bIsPB then return WidgetObj end

    local nChildren = 0
    pcall(function() if WidgetObj.GetChildrenCount then nChildren = WidgetObj:GetChildrenCount() end end)

    for i = 0, math.max(nChildren - 1, 0) do
        local child = nil
        pcall(function() child = WidgetObj:GetChildAt(i) end)
        if child and slua.isValid(child) then
            local result = PlayerMapMarker.FindProgressBarInWidget(child, Depth + 1, MaxDepth)
            if result then return result end
        end
    end
    return nil
end

function PlayerMapMarker.GetTeamID(Character)
    if not IsValid(Character) then return nil end
    local TeamID = nil
    pcall(function() if Character.GetTeamID then TeamID = Character:GetTeamID() end end)
    if not TeamID then
        pcall(function()
            local PS = nil
            if Character.GetPlayerStateSafety then PS = Character:GetPlayerStateSafety()
            elseif Character.GetPlayerState then PS = Character:GetPlayerState() end
            if IsValid(PS) and PS.GetTeamID then TeamID = PS:GetTeamID()
            elseif IsValid(PS) and PS.TeamID then TeamID = PS.TeamID end
        end)
    end
    if not TeamID then pcall(function() if Character.TeamID then TeamID = Character.TeamID end end) end
    return TeamID
end

function PlayerMapMarker.GetTeamColor(TeamID)
    if TeamID == nil or TeamID == 0 then 
        return FLinearColor and FLinearColor(0.2, 0.4, 1.0, 1.0) or {R=50,G=100,B=255,A=255} 
    end
    
    -- Khởi tạo bảng 15 màu sắc rực rỡ và dễ phân biệt
    local TeamColors = {
        [1]  = {R=255, G=50,  B=50,  A=255, fR=1.0, fG=0.2, fB=0.2}, -- Đỏ
        [2]  = {R=50,  G=255, B=50,  A=255, fR=0.2, fG=1.0, fB=0.2}, -- Lục (Xanh lá)
        [3]  = {R=50,  G=100, B=255, A=255, fR=0.2, fG=0.4, fB=1.0}, -- Lam (Xanh dương)
        [4]  = {R=255, G=255, B=50,  A=255, fR=1.0, fG=1.0, fB=0.2}, -- Vàng
        [5]  = {R=255, G=50,  B=255, A=255, fR=1.0, fG=0.2, fB=1.0}, -- Tím / Hồng Đậm
        [6]  = {R=50,  G=255, B=255, A=255, fR=0.2, fG=1.0, fB=1.0}, -- Xanh Ngọc Bích (Cyan)
        [7]  = {R=255, G=150, B=50,  A=255, fR=1.0, fG=0.6, fB=0.2}, -- Cam
        [8]  = {R=150, G=50,  B=255, A=255, fR=0.6, fG=0.2, fB=1.0}, -- Tím Đậm
        [9]  = {R=200, G=255, B=50,  A=255, fR=0.8, fG=1.0, fB=0.2}, -- Vàng Chanh
        [10] = {R=50,  G=150, B=255, A=255, fR=0.2, fG=0.6, fB=1.0}, -- Xanh Nước Biển
        [11] = {R=255, G=100, B=150, A=255, fR=1.0, fG=0.4, fB=0.6}, -- Hồng Nhạt
        [12] = {R=100, G=255, B=150, A=255, fR=0.4, fG=1.0, fB=0.6}, -- Xanh Trà
        [13] = {R=150, G=150, B=50,  A=255, fR=0.6, fG=0.6, fB=0.2}, -- Màu Olive
        [14] = {R=50,  G=200, B=150, A=255, fR=0.2, fG=0.8, fB=0.6}, -- Xanh Rêu
        [15] = {R=255, G=200, B=50,  A=255, fR=1.0, fG=0.8, fB=0.2}  -- Vàng Kim
    }
    
    -- Dùng thuật toán Modulo để xoay vòng màu. 
    -- Ví dụ: Team 16 chia 15 dư 1 sẽ dùng lại màu số 1.
    -- Đảm bảo 100 người (25 team) trong trận đều được tự động gắn màu, chung team = chung màu.
    local colorIndex = (TeamID % 15)
    if colorIndex == 0 then colorIndex = 15 end 
    
    local c = TeamColors[colorIndex]
    return FLinearColor and FLinearColor(c.fR, c.fG, c.fB, 1.0) or {R=c.R, G=c.G, B=c.B, A=c.A}
end

local _WhiteTexture = nil
local _bWhiteTextureFailed = false
local function GetWhiteTexture()
    if _WhiteTexture then return _WhiteTexture end
    if _bWhiteTextureFailed then return nil end
    pcall(function()
        local paths = { "/Game/BluePrints/UI/Textures/White.White", "/Game/BluePrints/UI/Textures/Common/White.White", "/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture" }
        for _, path in ipairs(paths) do
            pcall(function() local tex = import(path); if tex and slua.isValid(tex) then _WhiteTexture = tex return end end)
            if _WhiteTexture then break end
        end
    end)
    if not _WhiteTexture then _bWhiteTextureFailed = true end
    return _WhiteTexture
end

local function SetImageColor(Image, color)
    if not Image or not slua.isValid(Image) then return false end
    local bOK = false
    pcall(function() if Image.SetBrushTintColor then Image:SetBrushTintColor(color); bOK = true end end)
    pcall(function() if Image.SetColorAndOpacity then Image:SetColorAndOpacity(color); bOK = true end end)
    pcall(function()
        if Image.SetBrushFromTexture then
            local whiteTex = GetWhiteTexture()
            if whiteTex then
                Image:SetBrushFromTexture(whiteTex, false)
                if Image.SetColorAndOpacity then Image:SetColorAndOpacity(color) end
                bOK = true
            end
        end
    end)
    pcall(function() Image:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible); Image:SetRenderOpacity(1.0) end)
    return bOK
end

function PlayerMapMarker._GetWidgetRoot(WidgetObj)
    if not WidgetObj or not slua.isValid(WidgetObj) then return nil end
    local Root = nil
    pcall(function() if WidgetObj.GetRootWidget then Root = WidgetObj:GetRootWidget() end end)
    if Root and slua.isValid(Root) then return Root end
    pcall(function() if WidgetObj.WidgetTree and WidgetObj.WidgetTree.RootWidget then Root = WidgetObj.WidgetTree.RootWidget end end)
    if Root and slua.isValid(Root) then return Root end
    pcall(function() if WidgetObj.RootWidget and slua.isValid(WidgetObj.RootWidget) then Root = WidgetObj.RootWidget end end)
    return Root
end

function PlayerMapMarker._FindNamedWidgetInTree(WidgetObj, TargetName, MaxDepth)
    if not WidgetObj or not slua.isValid(WidgetObj) then return nil end
    MaxDepth = MaxDepth or 8
    local wname = nil
    pcall(function() if WidgetObj.GetName then wname = WidgetObj:GetName() end end)
    if wname and wname == TargetName then return WidgetObj end

    local wstr = tostring(WidgetObj)
    if wstr and string.find(wstr, TargetName, 1, true) then
        if wname and wname == TargetName then return WidgetObj
        elseif not wname or wname == "" then
            local _, endPos = string.find(wstr, TargetName, 1, true)
            if endPos then
                local nextChar = string.sub(wstr, endPos + 1, endPos + 1)
                if nextChar ~= "_" and nextChar ~= "" then return WidgetObj end
            end
        end
    end

    local nChildren = 0
    pcall(function() if WidgetObj.GetChildrenCount then nChildren = WidgetObj:GetChildrenCount() end end)

    if nChildren > 0 then
        for i = 0, nChildren - 1 do
            local child = nil
            pcall(function() child = WidgetObj:GetChildAt(i) end)
            if child and slua.isValid(child) then
                local found = PlayerMapMarker._FindNamedWidgetInTree(child, TargetName, MaxDepth - 1)
                if found then return found end
            end
        end
    else
        local Root = PlayerMapMarker._GetWidgetRoot(WidgetObj)
        if Root and slua.isValid(Root) and Root ~= WidgetObj then
            local found = PlayerMapMarker._FindNamedWidgetInTree(Root, TargetName, MaxDepth - 1)
            if found then return found end
        end
    end
    return nil
end

function PlayerMapMarker.ApplyTeamColor(Widget, TeamID)
    if not Widget or not Widget.Container then return end
    
    -- [THÊM MỚI] Check công tắc tắt Ô màu team
    if not _G.LexusConfig.Esp9_Team then
        pcall(function()
            local W = Widget.Container
            if W and slua.isValid(W) then
                local img1 = PlayerMapMarker._FindNamedWidgetInTree(W, "Image_TeamBG", 8)
                if img1 and slua.isValid(img1) then img1:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end
                local img2 = PlayerMapMarker._FindNamedWidgetInTree(W, "Image_TeamLogoBG", 8)
                if img2 and slua.isValid(img2) then img2:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end
                if Widget.TeamBgBorder and slua.isValid(Widget.TeamBgBorder) then Widget.TeamBgBorder:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end
            end
        end)
        return
    end

    local color = PlayerMapMarker.GetTeamColor(TeamID)
    if not color then return end

    pcall(function()
        local W = Widget.Container
        if not W or not slua.isValid(W) then return end

        local bBG = false
        local Image_TeamBG = PlayerMapMarker._FindNamedWidgetInTree(W, "Image_TeamBG", 8)
        if Image_TeamBG and slua.isValid(Image_TeamBG) then bBG = SetImageColor(Image_TeamBG, color) end

        local Image_TeamLogoBG = PlayerMapMarker._FindNamedWidgetInTree(W, "Image_TeamLogoBG", 8)
        if Image_TeamLogoBG and slua.isValid(Image_TeamLogoBG) then SetImageColor(Image_TeamLogoBG, color) end

        if W.SetTeamColor then pcall(function() W:SetTeamColor(TeamID) end) end
        
        if not Widget.TeamBgBorder or not slua.isValid(Widget.TeamBgBorder) then
            pcall(function()
                local Border = CGame:NewObjectFromPath("/Script/UMG.Border", W)
                if Border and slua.isValid(Border) then
                    pcall(function() Border:SetBrushColor(color) end)
                    pcall(function() Border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                    pcall(function() Border:SetRenderOpacity(0.7) end)
                    pcall(function() Border:SetDesiredSizeOverride(FVector2D and FVector2D(120, 20) or {X=120, Y=20}) end)
                    pcall(function() if W.AddChild then W:AddChild(Border) end end)
                    pcall(function() if Border.SetZOrder then Border:SetZOrder(-1) end end)
                    Widget.TeamBgBorder = Border
                end
            end)
        else
            pcall(function()
                Widget.TeamBgBorder:SetBrushColor(color)
                Widget.TeamBgBorder:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                Widget.TeamBgBorder:SetRenderOpacity(0.7)
            end)
        end
    end)
end

function PlayerMapMarker.GetCharacterMesh(Character)
    if not IsValid(Character) then return nil end
    local Mesh = nil
    pcall(function() if Character.Mesh and Game:IsValid(Character.Mesh) then Mesh = Character.Mesh end end)
    if not Mesh then pcall(function() local SkeletalMeshCompClass = import("/Script/Engine.SkeletalMeshComponent") Mesh = Character:GetComponentByClass(SkeletalMeshCompClass) end) end
    return Mesh
end

function PlayerMapMarker.GetESPLocation(Character)
    if not IsValid(Character) then return nil end
    local BoneLoc = PlayerMapMarker.GetCharacterLocation(Character)
    if BoneLoc then
        local heightOffset = 85
        pcall(function()
            if Character.bIsCrouched then heightOffset = 60 end
            if Character.IsProne and Character:IsProne() then heightOffset = 30 end
        end)
        pcall(function() BoneLoc.Z = BoneLoc.Z + heightOffset + (PlayerMapMarker.ESPWorldOffsetZ or 0) end)
    end
    return BoneLoc
end

function PlayerMapMarker.GetCharacterWeaponInfo(Character)
    if not IsValid(Character) then return nil end
    local WeaponID, WeaponName, WeaponIconPath, WeaponIconTexture, CurrentWeapon = nil, nil, nil, nil, nil

    pcall(function() if Character.GetCurrentWeapon then CurrentWeapon = Character:GetCurrentWeapon() end end)
    if not CurrentWeapon then pcall(function() CurrentWeapon = Character.CurrentWeapon end) end
    if not CurrentWeapon then pcall(function() if Character.GetWeaponManager then local WM = Character:GetWeaponManager() if WM and WM.GetCurrentWeapon then CurrentWeapon = WM:GetCurrentWeapon() end end end) end

    if CurrentWeapon and IsValid(CurrentWeapon) then
        pcall(function() if CurrentWeapon.GetWeaponID then WeaponID = CurrentWeapon:GetWeaponID() end end)
        if not WeaponID then pcall(function() WeaponID = CurrentWeapon.WeaponID end) end
        if not WeaponID then pcall(function() if CurrentWeapon.GetItemID then WeaponID = CurrentWeapon:GetItemID() end end) end
        pcall(function() if CurrentWeapon.GetWeaponName then WeaponName = CurrentWeapon:GetWeaponName() end end)
        pcall(function() if CurrentWeapon.GetWeaponIconPath then WeaponIconPath = CurrentWeapon:GetWeaponIconPath() end end)
        pcall(function() if CurrentWeapon.GetWeaponIcon then WeaponIconTexture = CurrentWeapon:GetWeaponIcon() end end)
    end

    if not WeaponID then
        pcall(function()
            local PS = nil
            if Character.GetPlayerStateSafety then PS = Character:GetPlayerStateSafety() elseif Character.GetPlayerState then PS = Character:GetPlayerState() end
            if PS and IsValid(PS) then
                if PS.GetCurrentWeaponID then WeaponID = PS:GetCurrentWeaponID() end
                if not WeaponID and PS.CurWeaponID then WeaponID = PS.CurWeaponID end
            end
        end)
    end
    return { WeaponID = WeaponID, WeaponName = WeaponName, WeaponIconPath = WeaponIconPath, WeaponIconTexture = WeaponIconTexture, CurrentWeapon = CurrentWeapon }
end

function PlayerMapMarker.FindWeaponIconInWidget(WidgetObj, Depth, MaxDepth)
    if not WidgetObj or not slua.isValid(WidgetObj) then return nil end
    Depth = Depth or 0 ; MaxDepth = MaxDepth or 8
    local propNames = { "Image_Weapon", "Image_WeaponIcon", "Image_Gun", "Image_Icon", "WeaponIcon", "WeaponImage", "Image_Equip" }
    for _, pname in ipairs(propNames) do
        pcall(function()
            local prop = WidgetObj[pname]
            if prop and slua.isValid(prop) then
                local hasBrush = false
                pcall(function() if prop.Brush then hasBrush = true end end)
                if hasBrush then return prop end
            end
        end)
    end
    if Depth >= MaxDepth then return nil end
    local nChildren = 0
    pcall(function() if WidgetObj.GetChildrenCount then nChildren = WidgetObj:GetChildrenCount() end end)
    for i = 0, math.max(nChildren - 1, 0) do
        local child = nil
        pcall(function() child = WidgetObj:GetChildAt(i) end)
        if child and slua.isValid(child) then
            local result = PlayerMapMarker.FindWeaponIconInWidget(child, Depth + 1, MaxDepth)
            if result then return result end
        end
    end
    if nChildren == 0 then
        local Root = PlayerMapMarker._GetWidgetRoot(WidgetObj)
        if Root and slua.isValid(Root) and Root ~= WidgetObj then
            local result = PlayerMapMarker.FindWeaponIconInWidget(Root, Depth + 1, MaxDepth)
            if result then return result end
        end
    end
    return nil
end

function PlayerMapMarker.FixWeaponIconBrushSize(ImageWidget, DefaultW, DefaultH)
    if not ImageWidget or not slua.isValid(ImageWidget) then return end
    DefaultW = DefaultW or 138 ; DefaultH = DefaultH or 69
    pcall(function()
        local brush = ImageWidget.Brush
        if brush then
            brush.ImageSize = FVector2D and FVector2D(DefaultW, DefaultH) or {X=DefaultW, Y=DefaultH}
            brush.DrawAs = 3
            brush.TintColor = FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {R=1,G=1,B=1,A=1}
            if ImageWidget.SetBrush then ImageWidget:SetBrush(brush) end
        end
        if ImageWidget.SetDesiredSizeOverride then ImageWidget:SetDesiredSizeOverride(FVector2D and FVector2D(DefaultW, DefaultH) or {X=DefaultW, Y=DefaultH}) end
        local slot = ImageWidget.Slot
        if slot and slot.SetSize then slot:SetSize(FVector2D and FVector2D(DefaultW, DefaultH) or {X=DefaultW, Y=DefaultH}) end
        ImageWidget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        ImageWidget:SetRenderOpacity(1.0)
        ImageWidget:SetColorAndOpacity(FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {R=1,G=1,B=1,A=1})
    end)
end

function PlayerMapMarker.ApplyWeaponIconFullOpacity(Container, ourWeaponIcon)
    local fullIcon = FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {R=1,G=1,B=1,A=1}
    if not ourWeaponIcon or not slua.isValid(ourWeaponIcon) then return end
    pcall(function() if ourWeaponIcon.SetRenderOpacity then ourWeaponIcon:SetRenderOpacity(1.0) end end)
    pcall(function() if ourWeaponIcon.SetColorAndOpacity then ourWeaponIcon:SetColorAndOpacity(fullIcon) end end)
    pcall(function()
        local brush = ourWeaponIcon.Brush
        if brush then pcall(function() brush.TintColor = fullIcon end) if ourWeaponIcon.SetBrush then ourWeaponIcon:SetBrush(brush) end end
    end)
    local chainNames = {"Border_WeaponColor", "Border_Weapon", "Border_WeaponIcon", "SizeBox_Weapon", "ScaleBox_Weapon", "Switcher_WeaponIcon"}
    for _, pname in ipairs(chainNames) do
        pcall(function()
            local node = Container and Container[pname]
            if node and slua.isValid(node) and node.SetRenderOpacity then node:SetRenderOpacity(1.0) end
            if node and slua.isValid(node) and node.SetColorAndOpacity then node:SetColorAndOpacity(fullIcon) end
        end)
    end
end

function PlayerMapMarker.ApplyWeaponIconToImage(ImageWidget, winfo)
    if not ImageWidget or not slua.isValid(ImageWidget) then return false, "no_widget" end
    if not winfo or not winfo.WeaponID then return false, "no_weapon_id" end

    local iconPath = nil
    local method = "none"
    local bHasAddKnownMissing = false
    local defaultW = 138
    local defaultH = 69

    pcall(function()
        local itemRecord = CDataTable.GetTableData("Item", winfo.WeaponID)
        if itemRecord and itemRecord.KillWhiteIcon and itemRecord.KillWhiteIcon ~= "" then iconPath = itemRecord.KillWhiteIcon method = "KillWhiteIcon" end
        if (not iconPath or iconPath == "") and winfo.WeaponIconPath and winfo.WeaponIconPath ~= "" then iconPath = winfo.WeaponIconPath method = "WeaponIconPath" end
        if (not iconPath or iconPath == "") and winfo.WeaponIconTexture and slua.isValid(winfo.WeaponIconTexture) then
            if ImageWidget.SetBrushFromTexture then ImageWidget:SetBrushFromTexture(winfo.WeaponIconTexture, true) method = "WeaponIconTexture" return end
        end
        if not iconPath or iconPath == "" then
            local UIUtil = require("client.common.ui_util")
            iconPath, bHasAddKnownMissing = UIUtil.GetItemBigIcon(winfo.WeaponID, ImageWidget)
            if iconPath and iconPath ~= "" then method = "GetItemBigIcon" end
        end
        if not iconPath or iconPath == "" then
            local UIUtil = require("client.common.ui_util")
            iconPath = UIUtil.GetItemSmallIcon(winfo.WeaponID, ImageWidget, bHasAddKnownMissing)
            if iconPath and iconPath ~= "" then method = "GetItemSmallIcon" end
        end
    end)

    if method == "WeaponIconTexture" then PlayerMapMarker.FixWeaponIconBrushSize(ImageWidget, defaultW, defaultH) return true, method end
    if not iconPath or iconPath == "" then return false, "no_path" end

    local bOK = false
    pcall(function()
        if ImageWidget.SetBrushResourceFromPathSync then ImageWidget:SetBrushResourceFromPathSync(iconPath, true) bOK = true end
        if not bOK then
            local util = require("client.slua_ui_framework.util")
            local result = util.SetTexture(ImageWidget, iconPath, { sync = true, bMatchSize = true, bIsInCombatState = true, bHasAddKnownMissing = bHasAddKnownMissing })
            bOK = result ~= nil
        end
        if not bOK then
            local tex = import(iconPath)
            if tex and slua.isValid(tex) and ImageWidget.SetBrushFromTexture then ImageWidget:SetBrushFromTexture(tex, true) bOK = true end
        end
        if not bOK then
            local LoadObject = import("LoadObject")
            if LoadObject then
                local tex = LoadObject(iconPath)
                if tex and slua.isValid(tex) and ImageWidget.SetBrushFromTexture then ImageWidget:SetBrushFromTexture(tex, true) bOK = true end
            end
        end
    end)

    if bOK then PlayerMapMarker.FixWeaponIconBrushSize(ImageWidget, defaultW, defaultH) end
    return bOK, method .. ":" .. tostring(iconPath)
end

function PlayerMapMarker.CopyWeaponIconBrushFromNative(ourWeaponIcon, nativeWeaponIcon)
    if not ourWeaponIcon or not slua.isValid(ourWeaponIcon) then return false end
    if not nativeWeaponIcon or not slua.isValid(nativeWeaponIcon) then return false end

    local bCopied = false
    pcall(function()
        local nBrush = nativeWeaponIcon.Brush
        if nBrush then
            local resObj = nil
            pcall(function() resObj = nBrush.ResourceObject end)
            if resObj and slua.isValid(resObj) and ourWeaponIcon.SetBrushFromTexture then
                ourWeaponIcon:SetBrushFromTexture(resObj, true)
                bCopied = true
            end
            if bCopied then
                local imgSize = nil
                pcall(function() imgSize = nBrush.ImageSize end)
                if imgSize then
                    local oBrush = ourWeaponIcon.Brush
                    if oBrush then oBrush.ImageSize = imgSize if ourWeaponIcon.SetBrush then ourWeaponIcon:SetBrush(oBrush) end end
                end
            end
        end
    end)
    return bCopied
end

function PlayerMapMarker.AddWeaponIconToESP(WidgetData, Character)
    if not WidgetData or not WidgetData.Container then return end
    local Container = WidgetData.Container
    if not slua.isValid(Container) then return end

    -- [THÊM MỚI] Check công tắc Tắt Icon Súng
    if not _G.LexusConfig.Esp9_Weapon then
        pcall(function()
            local chainNames = {"Border_WeaponColor", "Border_Weapon", "Border_WeaponIcon", "SizeBox_Weapon", "ScaleBox_Weapon", "Switcher_WeaponIcon"}
            for _, pname in ipairs(chainNames) do
                local node = Container[pname]
                if node and slua.isValid(node) and node.SetWidgetVisibility then node:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end
            end
            local ourWeaponIcon = Container.WeaponIcon or PlayerMapMarker.FindWeaponIconInWidget(Container, 0, 8)
            if ourWeaponIcon and slua.isValid(ourWeaponIcon) then ourWeaponIcon:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end
        end)
        WidgetData._LastWeaponID = 0
        WidgetData._WeaponIconApplied = false
        return
    end

    pcall(function()
        local ourWeaponIcon = Container.WeaponIcon
        if not ourWeaponIcon or not slua.isValid(ourWeaponIcon) then ourWeaponIcon = PlayerMapMarker.FindWeaponIconInWidget(Container, 0, 8) end
        if not ourWeaponIcon or not slua.isValid(ourWeaponIcon) then return end

        local winfo = Character and PlayerMapMarker.GetCharacterWeaponInfo(Character) or nil

        if not winfo or not winfo.WeaponID or winfo.WeaponID == 0 then
            pcall(function() ourWeaponIcon:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
            local chainNames = {"Border_WeaponColor", "Border_Weapon", "Border_WeaponIcon", "SizeBox_Weapon", "ScaleBox_Weapon", "Switcher_WeaponIcon"}
            for _, pname in ipairs(chainNames) do
                pcall(function()
                    local node = Container and Container[pname]
                    if node and slua.isValid(node) and node.SetWidgetVisibility then node:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end
                end)
            end
            WidgetData._LastWeaponID = 0
            WidgetData._WeaponIconApplied = false
            return
        end

        if WidgetData._LastWeaponID == winfo.WeaponID and WidgetData._WeaponIconApplied then
            pcall(function() ourWeaponIcon:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
            pcall(function() ourWeaponIcon:SetRenderOpacity(1.0) end)
            local chainNames = {"Border_WeaponColor", "Border_Weapon", "Border_WeaponIcon", "SizeBox_Weapon", "ScaleBox_Weapon", "Switcher_WeaponIcon"}
            for _, pname in ipairs(chainNames) do
                pcall(function()
                    local node = Container and Container[pname]
                    if node and slua.isValid(node) and node.SetWidgetVisibility then
                        node:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                        pcall(function() if node.SetRenderOpacity then node:SetRenderOpacity(1.0) end end)
                    end
                end)
            end
            if WidgetData._CachedSwitcherIndexes then
                for sName, idx in pairs(WidgetData._CachedSwitcherIndexes) do
                    pcall(function()
                        local ws = Container[sName]
                        if ws and slua.isValid(ws) and ws.SetActiveWidgetIndex then ws:SetActiveWidgetIndex(idx) end
                    end)
                end
            end
            if WidgetData._CachedParentSwitchers then
                for _, data in pairs(WidgetData._CachedParentSwitchers) do
                    pcall(function() if data.w and slua.isValid(data.w) and data.w.SetActiveWidgetIndex then data.w:SetActiveWidgetIndex(data.idx) end end)
                end
            end
            return
        end

        local chainNames = {"Border_WeaponColor", "Border_Weapon", "Border_WeaponIcon", "SizeBox_Weapon", "ScaleBox_Weapon", "Switcher_WeaponIcon"}
        for _, pname in ipairs(chainNames) do
            pcall(function()
                local node = Container and Container[pname]
                if node and slua.isValid(node) and node.SetWidgetVisibility then node:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end
            end)
        end

        local bCopied = false
        if winfo and winfo.WeaponID then
            local ok, method = PlayerMapMarker.ApplyWeaponIconToImage(ourWeaponIcon, winfo)
            if ok then bCopied = true end
        end

        local bWeaponIconSet = false
        if Character and winfo then
            if winfo and winfo.WeaponID then
                pcall(function() if Container.SetWeaponIcon then Container:SetWeaponIcon(winfo.WeaponID) bWeaponIconSet = true end end)
                if not bWeaponIconSet then pcall(function() if Container.SetWeaponIconByID then Container:SetWeaponIconByID(winfo.WeaponID) bWeaponIconSet = true end end) end
                if not bWeaponIconSet then pcall(function() if Container.UpdateWeaponIcon then Container:UpdateWeaponIcon(winfo.WeaponID) bWeaponIconSet = true end end) end
                if not bWeaponIconSet then pcall(function() if Container.SetWeaponID then Container:SetWeaponID(winfo.WeaponID) bWeaponIconSet = true end end) end
                pcall(function() if Container.SetData then Container:SetData(Character) end end)
                pcall(function() if Container.SetPlayerInfo then Container:SetPlayerInfo(Character) end end)
                if winfo.CurrentWeapon then pcall(function() if Container.SetCurrentWeapon then Container:SetCurrentWeapon(winfo.CurrentWeapon) end end) end
            end
        end

        if bWeaponIconSet then
            pcall(function()
                local innerIcon = Container.Image_Icon
                if not innerIcon or not slua.isValid(innerIcon) then if Container.CanvasPanel_Type1 then innerIcon = Container.CanvasPanel_Type1.Image_Icon end end
                if not innerIcon or not slua.isValid(innerIcon) then
                    local function findImageIcon(w, depth)
                        if not w or not slua.isValid(w) or depth > 8 then return nil end
                        local prop = w.Image_Icon
                        if prop and slua.isValid(prop) then return prop end
                        local n = 0
                        pcall(function() if w.GetChildrenCount then n = w:GetChildrenCount() end end)
                        for i = 0, math.max(n - 1, 0) do
                            local c = nil
                            pcall(function() c = w:GetChildAt(i) end)
                            if c then local r = findImageIcon(c, depth + 1) if r then return r end end
                        end
                        return nil
                    end
                    innerIcon = findImageIcon(Container, 0)
                end
                if innerIcon and slua.isValid(innerIcon) and innerIcon ~= ourWeaponIcon then
                    pcall(function()
                        local ibrush = innerIcon.Brush
                        if ibrush then
                            local iresObj = nil
                            pcall(function() iresObj = ibrush.ResourceObject end)
                            if iresObj and slua.isValid(iresObj) then
                                if ourWeaponIcon.SetBrushFromAsset then ourWeaponIcon:SetBrushFromAsset(iresObj) bCopied = true end
                                if not bCopied and ourWeaponIcon.SetBrushFromTexture then ourWeaponIcon:SetBrushFromTexture(iresObj) bCopied = true end
                            end
                        end
                    end)
                    if not bCopied then
                        pcall(function()
                            local brush = innerIcon.Brush
                            if brush then
                                local iresObj = nil
                                pcall(function() iresObj = brush.ResourceObject end)
                                if iresObj and slua.isValid(iresObj) and ourWeaponIcon.SetBrushFromTexture then
                                    ourWeaponIcon:SetBrushFromTexture(iresObj, false)
                                    PlayerMapMarker.FixWeaponIconBrushSize(ourWeaponIcon)
                                    bCopied = true
                                end
                            end
                        end)
                    end
                end
            end)
        end

        if not bCopied then
            local nativeWeaponIcon = nil
            if PlayerMapMarker.ESPCanvas and Game:IsValid(PlayerMapMarker.ESPCanvas) then
                local nChildren = 0
                pcall(function() nChildren = PlayerMapMarker.ESPCanvas:GetChildrenCount() end)
                for i = 0, math.max(nChildren - 1, 0) do
                    local child = nil
                    pcall(function() child = PlayerMapMarker.ESPCanvas:GetChildAt(i) end)
                    if child and slua.isValid(child) then
                        local cstr = tostring(child)
                        if string.find(cstr, "OB_PlayerHeadHPItem") then
                            if not PlayerMapMarker.IsOurESPWidget(child) then
                                local nativeIcon = child.WeaponIcon
                                if nativeIcon and slua.isValid(nativeIcon) then nativeWeaponIcon = nativeIcon break end
                            end
                        end
                    end
                end
            end

            if nativeWeaponIcon and slua.isValid(nativeWeaponIcon) then
                local okNative, nativeMethod = PlayerMapMarker.CopyWeaponIconBrushFromNative(ourWeaponIcon, nativeWeaponIcon)
                if okNative then bCopied = true end
            end
        end

        if not bCopied then
            pcall(function()
                local brush = ourWeaponIcon.Brush
                if brush then
                    local resObj = nil
                    pcall(function() resObj = brush.ResourceObject end)
                    if resObj and slua.isValid(resObj) and ourWeaponIcon.SetBrushFromTexture then
                        ourWeaponIcon:SetBrushFromTexture(resObj)
                        bCopied = true
                    end
                end
            end)
        end

        if not bCopied then
            pcall(function()
                local brush = ourWeaponIcon.Brush
                if brush then
                    local imgSize = nil
                    pcall(function() imgSize = brush.ImageSize end)
                    local bZeroSize = false
                    if imgSize then
                        local sx, sy = nil, nil
                        pcall(function() sx = imgSize.X end)
                        pcall(function() sy = imgSize.Y end)
                        if (not sx or sx == 0) and (not sy or sy == 0) then bZeroSize = true end
                    end
                    if bZeroSize then
                        pcall(function() brush.ImageSize = FVector2D and FVector2D(PlayerMapMarker.WeaponIconBrushW or 138, PlayerMapMarker.WeaponIconBrushH or 69) or {X=138, Y=69} end)
                    end
                    pcall(function() brush.DrawAs = 3 end)
                    if ourWeaponIcon.SetBrush then ourWeaponIcon:SetBrush(brush) end
                end
            end)
        end

        pcall(function() ourWeaponIcon:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
        PlayerMapMarker.ApplyWeaponIconFullOpacity(Container, ourWeaponIcon)
        PlayerMapMarker.FixWeaponIconBrushSize(ourWeaponIcon)

        pcall(function()
            local function findWidgetInSwitcher(switcher, targetWidget)
                if not switcher or not slua.isValid(switcher) then return nil end
                if not switcher.GetChildrenCount or not switcher.GetChildAt then return nil end
                local nChildren = switcher:GetChildrenCount()
                for i = 0, math.max(nChildren - 1, 0) do
                    local child = switcher:GetChildAt(i)
                    if child and slua.isValid(child) then
                        if child == targetWidget then return i end
                        local function searchDescendant(w, target, depth)
                            if depth > 5 then return false end
                            if w == target then return true end
                            if not w.GetChildrenCount or not w.GetChildAt then return false end
                            local nc = w:GetChildrenCount()
                            for j = 0, math.max(nc - 1, 0) do
                                local c = w:GetChildAt(j)
                                if c and slua.isValid(c) and searchDescendant(c, target, depth + 1) then return true end
                            end
                            return false
                        end
                        if searchDescendant(child, targetWidget, 0) then return i end
                    end
                end
                return nil
            end

            for _, switcherName in ipairs({"Switcher_WeaponIcon", "WidgetSwitcher_Type", "WidgetSwitcher_Type2"}) do
                local ws = Container[switcherName]
                if ws and slua.isValid(ws) and ws.GetChildrenCount and ws.GetChildAt then
                    local foundIdx = findWidgetInSwitcher(ws, ourWeaponIcon)
                    if foundIdx then
                        if ws.SetActiveWidgetIndex then
                            ws:SetActiveWidgetIndex(foundIdx)
                            WidgetData._CachedSwitcherIndexes = WidgetData._CachedSwitcherIndexes or {}
                            WidgetData._CachedSwitcherIndexes[switcherName] = foundIdx
                        end
                    end
                end
            end
        end)

        pcall(function()
            local parent = ourWeaponIcon
            for depth = 0, 8 do
                if not parent or not slua.isValid(parent) then break end
                if parent.GetParent then
                    local p = parent:GetParent()
                    if p and slua.isValid(p) then
                        local pStr = tostring(p)
                        if string.find(pStr, "WidgetSwitcher") then
                            if p.GetChildrenCount and p.GetChildAt then
                                local nCh = p:GetChildrenCount()
                                for i = 0, math.max(nCh - 1, 0) do
                                    local child = p:GetChildAt(i)
                                    if child and slua.isValid(child) then
                                        local function isDescendant(w, target, d)
                                            if d > 5 then return false end
                                            if w == target then return true end
                                            if not w.GetChildrenCount or not w.GetChildAt then return false end
                                            local nc = w:GetChildrenCount()
                                            for j = 0, math.max(nc - 1, 0) do
                                                local c = w:GetChildAt(j)
                                                if c and slua.isValid(c) and isDescendant(c, target, d + 1) then return true end
                                            end
                                            return false
                                        end
                                        if isDescendant(child, ourWeaponIcon, 0) then
                                            if p.SetActiveWidgetIndex then
                                                p:SetActiveWidgetIndex(i)
                                                WidgetData._CachedParentSwitchers = WidgetData._CachedParentSwitchers or {}
                                                WidgetData._CachedParentSwitchers[tostring(p)] = {w = p, idx = i}
                                            end
                                            break
                                        end
                                    end
                                end
                            end
                        end
                        parent = p
                    else
                        break
                    end
                else
                    break
                end
            end
        end)

        pcall(function()
            local parent = ourWeaponIcon
            for depth = 0, 8 do
                pcall(function()
                    if parent.GetParent then
                        local p = parent:GetParent()
                        if p and slua.isValid(p) then
                            if p.SetWidgetVisibility then p:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end
                            pcall(function() if p.SetRenderOpacity then p:SetRenderOpacity(1.0) end end)
                            pcall(function() if p.SetContentColorAndOpacity then p:SetContentColorAndOpacity(FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {R=1,G=1,B=1,A=1}) end end)
                            pcall(function() if p.SetColorAndOpacity then p:SetColorAndOpacity(FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {R=1,G=1,B=1,A=1}) end end)
                            pcall(function() if p.SetBrushTintColor then p:SetBrushTintColor(FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {R=1,G=1,B=1,A=1}) end end)
                            pcall(function()
                                local pBrush = p.Brush
                                if pBrush and pBrush.TintColor then
                                    pBrush.TintColor = FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {R=1,G=1,B=1,A=1}
                                    if p.SetBrush then p:SetBrush(pBrush) end
                                end
                            end)
                            pcall(function() if p.InvalidateLayout then p:InvalidateLayout() end end)
                            parent = p
                        end
                    end
                end)
            end
        end)
        pcall(function() if ourWeaponIcon.InvalidateLayout then ourWeaponIcon:InvalidateLayout() end end)

        pcall(function() if Container.UpdateWeapon then Container:UpdateWeapon() end end)
        pcall(function() if Container.RefreshWeapon then Container:RefreshWeapon() end end)
        
        WidgetData._LastWeaponID = winfo.WeaponID
        WidgetData._WeaponIconApplied = true
    end)
end

PlayerMapMarker._OBHeadWidgetClass = nil
PlayerMapMarker._OBHeadWidgetLoadFailed = false
PlayerMapMarker._bDumpedWidgetChildren = false

function PlayerMapMarker.CreateESPWidget()
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return nil end
    if PlayerMapMarker._OBHeadWidgetLoadFailed then return nil end

    if not PlayerMapMarker._OBHeadWidgetClass then
        pcall(function()
            local Path = "/Game/BluePrints/UI/OBUI/Item/OB_PlayerHeadHPItem_UIBP.OB_PlayerHeadHPItem_UIBP"
            local uClass = slua.loadClass(Path)
            if uClass then PlayerMapMarker._OBHeadWidgetClass = uClass end
        end)
        if not PlayerMapMarker._OBHeadWidgetClass then
            PlayerMapMarker._OBHeadWidgetLoadFailed = true
            return nil
        end
    else
        local bValid = false
        pcall(function() bValid = slua.isValid(PlayerMapMarker._OBHeadWidgetClass) end)
        if not bValid then
            PlayerMapMarker._OBHeadWidgetLoadFailed = true
            PlayerMapMarker._OBHeadWidgetClass = nil
            return nil
        end
    end

    local Widget = nil
    pcall(function()
        local STExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")
        local PC = PlayerMapMarker.GetMyPlayerController()
        local OuterObj = IsValid(PC) and PC.Object or PlayerMapMarker.ESPCanvas
        Widget = STExtraBlueprintFunctionLibrary.CreateWidgetByClass(PlayerMapMarker._OBHeadWidgetClass, OuterObj)
    end)

    if not Widget then return nil end

    pcall(function() Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
    pcall(function() Widget:SetRenderOpacity(1.0) end)

    local NameText = nil
    local HealthFill = nil
    local bIsOriginalProgressBar = false

    pcall(function()
        NameText = Widget.TextBlock_TeamName
        if NameText and slua.isValid(NameText) then pcall(function() NameText:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end) end
        if Widget.TextBlock_PlayerName and slua.isValid(Widget.TextBlock_PlayerName) then pcall(function() Widget.TextBlock_PlayerName:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end) end

        local WS_Type = Widget.WidgetSwitcher_Type
        local WS_Type2 = Widget.WidgetSwitcher_Type2
        if WS_Type and slua.isValid(WS_Type) then pcall(function() if WS_Type.SetActiveWidgetIndex then WS_Type:SetActiveWidgetIndex(PlayerMapMarker.HPWidgetSwitcherTypeIndex) end end) end
        if WS_Type2 and slua.isValid(WS_Type2) then pcall(function() if WS_Type2.SetActiveWidgetIndex then WS_Type2:SetActiveWidgetIndex(PlayerMapMarker.HPWidgetSwitcherType2Index) end end) end

        local SizeBox_HP = Widget.SizeBox_HP
        if SizeBox_HP and slua.isValid(SizeBox_HP) then
            pcall(function() SizeBox_HP:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
            pcall(function() SizeBox_HP:SetHeightOverride(6) end)
            pcall(function() SizeBox_HP:SetWidthOverride(100) end)

            local ExistingChild = nil
            pcall(function() if SizeBox_HP.GetContent then ExistingChild = SizeBox_HP:GetContent() end end)
            if not ExistingChild then pcall(function() if SizeBox_HP.GetChildAt then ExistingChild = SizeBox_HP:GetChildAt(0) end end) end

            if ExistingChild and slua.isValid(ExistingChild) then
                pcall(function() ExistingChild:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                pcall(function() ExistingChild:SetRenderOpacity(1.0) end)

                local FoundPB = PlayerMapMarker.FindProgressBarInWidget(ExistingChild, 0, 5)
                if FoundPB and slua.isValid(FoundPB) then
                    HealthFill = FoundPB
                    bIsOriginalProgressBar = true
                    pcall(function() FoundPB:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                    pcall(function() FoundPB:SetRenderOpacity(1.0) end)
                else
                    local PB = CGame:NewObjectFromPath("/Script/UMG.ProgressBar", ExistingChild)
                    if PB then
                        pcall(function() PB:SetFillColorAndOpacity(FLinearColor and FLinearColor(0, 1, 0, 1) or {R=0,G=1,B=0,A=1}) end)
                        pcall(function() PB:SetPercent(1.0) end)
                        pcall(function() PB:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                        pcall(function() PB:SetRenderOpacity(1.0) end)
                        pcall(function() PB:SetDesiredSizeOverride(FVector2D and FVector2D(100, 6) or {X=100, Y=6}) end)
                        pcall(function() ExistingChild:AddChild(PB) end)
                        HealthFill = PB
                    end
                end
            else
                local PB = CGame:NewObjectFromPath("/Script/UMG.ProgressBar", SizeBox_HP)
                if PB then
                    pcall(function() PB:SetFillColorAndOpacity(FLinearColor and FLinearColor(0, 1, 0, 1) or {R=0,G=1,B=0,A=1}) end)
                    pcall(function() PB:SetPercent(1.0) end)
                    pcall(function() PB:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                    pcall(function() PB:SetRenderOpacity(1.0) end)
                    pcall(function() PB:SetDesiredSizeOverride(FVector2D and FVector2D(100, 6) or {X=100, Y=6}) end)

                    local bUsedSetContent = false
                    pcall(function() if SizeBox_HP.SetContent then SizeBox_HP:SetContent(PB) bUsedSetContent = true end end)
                    if not bUsedSetContent then pcall(function() SizeBox_HP:AddChild(PB) end) end
                    HealthFill = PB
                end
            end
        end
    end)

    local WidgetData = {
        Container = Widget,
        NameText = NameText,
        HealthFill = HealthFill,
        IsGameWidget = true,
        IsOriginalProgressBar = bIsOriginalProgressBar,
        HasChildren = (NameText ~= nil)
    }
    return WidgetData
end

PlayerMapMarker._CanvasScaleX = 1.0
PlayerMapMarker._CanvasScaleY = 1.0
PlayerMapMarker._CanvasOffsetX = 0.0
PlayerMapMarker._CanvasOffsetY = 0.0

function PlayerMapMarker.UpdateCanvasTransform(PC)
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return end
    local success = false
    pcall(function()
        local SBL = SlateBlueprintLibrary
        if SBL and SBL.AbsoluteToLocal then
            local cg = PlayerMapMarker.ESPCanvas:GetCachedGeometry()
            if cg then
                local pt0 = SBL.AbsoluteToLocal(cg, FVector2D and FVector2D(0, 0) or {X=0, Y=0})
                local pt1 = SBL.AbsoluteToLocal(cg, FVector2D and FVector2D(100, 100) or {X=100, Y=100})
                if pt0 and pt1 then
                    PlayerMapMarker._CanvasScaleX = (pt1.X - pt0.X) / 100
                    PlayerMapMarker._CanvasScaleY = (pt1.Y - pt0.Y) / 100
                    PlayerMapMarker._CanvasOffsetX = pt0.X
                    PlayerMapMarker._CanvasOffsetY = pt0.Y
                    success = true
                end
            end
        end
    end)

    if not success then
        pcall(function()
            local WLL = WidgetLayoutLibrary
            if WLL and WLL.ScreenToWidgetLocal then
                local cg = PlayerMapMarker.ESPCanvas:GetCachedGeometry()
                if cg then
                    local pt0 = FVector2D and FVector2D(0, 0) or {X=0, Y=0}
                    local pt1 = FVector2D and FVector2D(0, 0) or {X=0, Y=0}
                    WLL.ScreenToWidgetLocal(PC, cg, FVector2D and FVector2D(0, 0) or {X=0, Y=0}, pt0)
                    WLL.ScreenToWidgetLocal(PC, cg, FVector2D and FVector2D(100, 100) or {X=100, Y=100}, pt1)
                    PlayerMapMarker._CanvasScaleX = (pt1.X - pt0.X) / 100
                    PlayerMapMarker._CanvasScaleY = (pt1.Y - pt0.Y) / 100
                    PlayerMapMarker._CanvasOffsetX = pt0.X
                    PlayerMapMarker._CanvasOffsetY = pt0.Y
                    success = true
                end
            end
        end)
    end

    if not success then
        local scale = 1.0
        local WLL = WidgetLayoutLibrary
        if WLL and WLL.GetViewportScale then scale = WLL.GetViewportScale(PC) or 1.0 end
        PlayerMapMarker._CanvasScaleX = 1.0 / scale
        PlayerMapMarker._CanvasScaleY = 1.0 / scale
        PlayerMapMarker._CanvasOffsetX = 0
        PlayerMapMarker._CanvasOffsetY = 0
    end
end

function PlayerMapMarker.ScreenPixelToCanvasLocal(PC, ScreenPixelPos)
    if not ScreenPixelPos then return FVector2D and FVector2D(0, 0) or {X=0, Y=0} end
    local scaleX = PlayerMapMarker._CanvasScaleX or 1.0
    local scaleY = PlayerMapMarker._CanvasScaleY or 1.0
    local offsetX = PlayerMapMarker._CanvasOffsetX or 0
    local offsetY = PlayerMapMarker._CanvasOffsetY or 0
    return (FVector2D and FVector2D(ScreenPixelPos.X * scaleX + offsetX, ScreenPixelPos.Y * scaleY + offsetY)) or {X = ScreenPixelPos.X * scaleX + offsetX, Y = ScreenPixelPos.Y * scaleY + offsetY}
end

function PlayerMapMarker.ProjectWorldToCanvasLocal(PC, WorldLoc)
    if not IsValid(PC) or not WorldLoc then return false, (FVector2D and FVector2D(0, 0) or {X=0, Y=0}) end
    local ScreenPixelPos = FVector2D and FVector2D(0, 0) or {X=0, Y=0}
    local bOK = false
    pcall(function()
        local res = PC:ProjectWorldLocationToScreen(WorldLoc, ScreenPixelPos, true)
        if res == true or res == 1 or (ScreenPixelPos and (ScreenPixelPos.X ~= 0 or ScreenPixelPos.Y ~= 0)) then bOK = true end
    end)
    if not bOK or not ScreenPixelPos or (ScreenPixelPos.X == 0 and ScreenPixelPos.Y == 0) then return false, (FVector2D and FVector2D(0, 0) or {X=0, Y=0}) end
    local CanvasLocalPos = PlayerMapMarker.ScreenPixelToCanvasLocal(PC, ScreenPixelPos)
    return true, CanvasLocalPos
end

function PlayerMapMarker.GetDynamicViewportSize(PC)
    local width, height = 0, 0
    if PlayerMapMarker.ESPCanvas and Game:IsValid(PlayerMapMarker.ESPCanvas) then
        pcall(function()
            local cg = PlayerMapMarker.ESPCanvas:GetCachedGeometry()
            if cg and cg.GetLocalSize then
                local sz = cg:GetLocalSize()
                if sz and sz.X and sz.X > 200 then width = sz.X height = sz.Y end
            end
        end)
    end
    if width > 200 then return width, height end
    pcall(function()
        local WLL = WidgetLayoutLibrary
        if WLL and WLL.GetViewportSize then
            local sz = WLL.GetViewportSize(PC or PlayerMapMarker.GetMyPlayerController())
            if sz and sz.X and sz.X > 200 then width = sz.X height = sz.Y end
        end
    end)
    if width > 200 then
        pcall(function()
            local WLL = WidgetLayoutLibrary
            if WLL and WLL.GetViewportScale then
                local scale = WLL.GetViewportScale(PC or PlayerMapMarker.GetMyPlayerController())
                if scale and type(scale) == "number" and scale > 0 and scale ~= 1.0 then width = width / scale height = height / scale end
            end
        end)
        return width, height
    end
    return PlayerMapMarker._cachedViewportW or 1920, PlayerMapMarker._cachedViewportH or 1080
end

function PlayerMapMarker.UpdateESPPositionWithPC(Widget, WorldLoc, PC, CanvasPos)
    if not Widget or not IsValid(PC) then return false end
    local Container = Widget.Container or Widget
    local bOnScreen = true
    if not CanvasPos then
        if not WorldLoc then return false end
        bOnScreen, CanvasPos = PlayerMapMarker.ProjectWorldToCanvasLocal(PC, WorldLoc)
    end

    if not bOnScreen then pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end) return false end

    pcall(function()
        if PlayerMapMarker.ESPCanvas and Game:IsValid(PlayerMapMarker.ESPCanvas) then
            local ptr = tostring(Container)
            local Slot = PlayerMapMarker.ESPWidgetPtrs[ptr]

            if not Slot or not slua.isValid(Slot) or type(Slot) == "boolean" then
                local addedSlot = PlayerMapMarker.ESPCanvas:AddChildToCanvas(Container)
                if addedSlot and slua.isValid(addedSlot) then
                    Slot = addedSlot
                    PlayerMapMarker.ESPWidgetPtrs[ptr] = addedSlot
                    if type(Widget) == "table" then Widget.Slot = addedSlot end
                    pcall(function() Slot:SetAutoSize(true) end)
                    pcall(function() Slot.bAutoSize = true end)
                    local align = FVector2D and FVector2D(0.5, 1.0) or {X=0.5, Y=1.0}
                    pcall(function() Slot.Alignment = align end)
                    pcall(function() Slot:SetAlignment(align) end)
                    pcall(function() Slot:SetAlignment(0.5, 1.0) end)
                    pcall(function() Slot:SetZOrder(PlayerMapMarker.ESPWidgetZOrder or 20) end)
                end
            end

            -- [FIX VIP] Xóa vệt đen trên đầu khi tắt hết UI
            local bShowAnyUI = _G.LexusConfig.Esp9_Name or _G.LexusConfig.Esp9_Distance or _G.LexusConfig.Esp9_HP or _G.LexusConfig.Esp9_Team or _G.LexusConfig.Esp9_Weapon
            if bShowAnyUI then
                Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            else
                Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            end
            
            if not Widget._OffsetResetDone then
                pcall(function() Container:SetRenderTranslation(FVector2D and FVector2D(0.0, 0.0) or {X=0, Y=0}) end)
                
                -- [SIZE 85% UI UE4] Tăng size to hơn một chút cho dễ nhìn (Gốc là 1.0, cũ là 0.7)
                pcall(function() Container:SetRenderScale(FVector2D and FVector2D(0.90, 0.90) or {X=0.90, Y=0.90}) end)
                
                if Widget and type(Widget) == "table" then
                    if Widget.NameText and slua.isValid(Widget.NameText) then pcall(function() Widget.NameText:SetRenderTranslation(FVector2D and FVector2D(0.0, 0.0) or {X=0, Y=0}) end) end
                    if Widget.HealthFill and slua.isValid(Widget.HealthFill) then pcall(function() Widget.HealthFill:SetRenderTranslation(FVector2D and FVector2D(0.0, 0.0) or {X=0, Y=0}) end) end
                end
                pcall(function() Container.RenderTransformPivot = FVector2D and FVector2D(0.5, 1.0) or {X=0.5, Y=1.0} end)
                pcall(function() Container:SetRenderTransformPivot(FVector2D and FVector2D(0.5, 1.0) or {X=0.5, Y=1.0}) end)
                Widget._OffsetResetDone = true
            end

            if not Slot or not slua.isValid(Slot) or Slot == PlayerMapMarker.ESPCanvas then
                if Widget and type(Widget) == "table" and Widget.Slot and slua.isValid(Widget.Slot) then Slot = Widget.Slot
                elseif Container.Slot and slua.isValid(Container.Slot) then Slot = Container.Slot end
            end

            if Slot and slua.isValid(Slot) and Slot ~= PlayerMapMarker.ESPCanvas then
                local finalX = CanvasPos.X + (PlayerMapMarker.ESPAnchorOffsetX or 0)
                local finalY = CanvasPos.Y + (PlayerMapMarker.ESPAnchorOffsetY or 0)
                if Widget and type(Widget) == "table" then
                    local cached = Widget._CachedPosVec
                    if not cached or cached.X ~= finalX or cached.Y ~= finalY then
                        if not cached then
                            Widget._CachedPosVec = FVector2D and FVector2D(finalX, finalY) or {X=finalX, Y=finalY}
                        else
                            cached.X = finalX
                            cached.Y = finalY
                        end
                        pcall(function() Slot:SetPosition(Widget._CachedPosVec) end)
                    end
                else
                    pcall(function() Slot:SetPosition(FVector2D and FVector2D(finalX, finalY) or {X=finalX, Y=finalY}) end)
                end
            end
        end
    end)
    return true
end

function PlayerMapMarker.UpdateESPText(Widget, Text)
    if not Widget then return end
    if Widget._LastESPText == Text then return end
    Widget._LastESPText = Text

    local function applyTextAndCenter(w, txt)
        if not w or not slua.isValid(w) then return end
        
        -- Nếu chữ rỗng (do người chơi đã tắt Tên & Khoảng cách) thì ẨN Widget đi
        if txt == "" then
            pcall(function() w:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
            return
        else
            pcall(function() w:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
        end

        pcall(function() w:SetText(txt) end)
        -- ÉP MÀU CAM CHO CHỮ & SỐ MÉT 
        pcall(function()
            local FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")
            local orangeColor = FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {R=255, G=255, B=255, A=255}
            if w.SetColorAndOpacity then
                if FSlateColor then w:SetColorAndOpacity(FSlateColor(orangeColor)) else w:SetColorAndOpacity(orangeColor) end
            end
        end)
        pcall(function() if w.SetJustification then w:SetJustification(1) end end)
        pcall(function() local slot = w.Slot if slot and slot.SetHorizontalAlignment then slot:SetHorizontalAlignment(1) end end)
        pcall(function() w:SetRenderTranslation(FVector2D and FVector2D(PlayerMapMarker.ESPTextOffsetX or 0, PlayerMapMarker.ESPTextOffsetY or 0) or {X=PlayerMapMarker.ESPTextOffsetX or 0, Y=PlayerMapMarker.ESPTextOffsetY or 0}) end)
    end

    if Widget.NameText and slua.isValid(Widget.NameText) then applyTextAndCenter(Widget.NameText, Text) end
    if Widget.IsGameWidget and Widget.Container then
        pcall(function()
            local W = Widget.Container
            if W and slua.isValid(W) then
                if W.SetPlayerName then
                    local Name = Text
                    local idx = string.find(Text, " %[")
                    if idx then Name = string.sub(Text, 1, idx - 1) end
                    W:SetPlayerName(Name)
                end
                applyTextAndCenter(W.TextBlock_TeamName, Text)
                applyTextAndCenter(W.TextBlock_PlayerName, Text)

                pcall(function()
                    if not Widget._CachedVBChildren then
                        local list = {}
                        local VB = PlayerMapMarker._FindNamedWidgetInTree(W, "VerticalBox_0", 8)
                        if VB and slua.isValid(VB) and VB.GetChildrenCount then
                            local nChildren = VB:GetChildrenCount()
                            for i = 0, nChildren - 1 do
                                local child = VB:GetChildAt(i)
                                if child and slua.isValid(child) and child.SetText then table.insert(list, child) end
                            end
                        end
                        Widget._CachedVBChildren = list
                    end
                    for _, child in ipairs(Widget._CachedVBChildren) do applyTextAndCenter(child, Text) end
                end)

                pcall(function()
                    if not Widget._CachedHBChildren then
                        local list = {}
                        local HB = PlayerMapMarker._FindNamedWidgetInTree(W, "HorizontalBox_TeamName", 8)
                        if HB and slua.isValid(HB) and HB.GetChildrenCount then
                            local nChildren = HB:GetChildrenCount()
                            for i = 0, nChildren - 1 do
                                local child = HB:GetChildAt(i)
                                if child and slua.isValid(child) and child.SetText then table.insert(list, child) end
                            end
                        end
                        Widget._CachedHBChildren = list
                    end
                    for _, child in ipairs(Widget._CachedHBChildren) do applyTextAndCenter(child, Text) end
                end)
            end
        end)
    end
end

function PlayerMapMarker.UpdateESPHealth(Widget, pct)
    if not Widget then return end

    local bShowHP = _G.LexusConfig.Esp9_HP == true
    local hpVisibilityChanged = Widget._LastHPVisibility ~= bShowHP
    local pctChanged = Widget.LastPct ~= pct
    Widget.LastPct = pct

    -- Keep the switcher/visibility writes only for actual toggle changes.
    -- The percentage itself is still updated whenever its value changes.
    if not hpVisibilityChanged and not pctChanged and not PlayerMapMarker.bForceSwitcherIndexEveryUpdate then return end

    if PlayerMapMarker.bForceSwitcherIndexEveryUpdate and Widget.Container then
        pcall(function()
            local W = Widget.Container
            if W and slua.isValid(W) then
                if W.WidgetSwitcher_Type and slua.isValid(W.WidgetSwitcher_Type) then pcall(function() if W.WidgetSwitcher_Type.SetActiveWidgetIndex then W.WidgetSwitcher_Type:SetActiveWidgetIndex(PlayerMapMarker.HPWidgetSwitcherTypeIndex) end end) end
                if W.WidgetSwitcher_Type2 and slua.isValid(W.WidgetSwitcher_Type2) then pcall(function() if W.WidgetSwitcher_Type2.SetActiveWidgetIndex then W.WidgetSwitcher_Type2:SetActiveWidgetIndex(PlayerMapMarker.HPWidgetSwitcherType2Index) end end) end
                
                -- Cập nhật ẩn/hiện Box chứa thanh máu
                if W.SizeBox_HP and slua.isValid(W.SizeBox_HP) then 
                    if bShowHP then
                        W.SizeBox_HP:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                    else
                        W.SizeBox_HP:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                    end
                end
            end
        end)
    end

    -- Chặn đoạn code cập nhật màu bên dưới nếu công tắc tắt
    Widget._LastHPVisibility = bShowHP
    if not bShowHP then return end

    if Widget.HealthFill then
        local bValid = false
        pcall(function() bValid = slua.isValid(Widget.HealthFill) end)
        if bValid then
            local bHasSetPercent = false
            pcall(function() bHasSetPercent = (Widget.HealthFill.SetPercent ~= nil) end)
            if not bHasSetPercent then
                local PB = PlayerMapMarker.FindProgressBarInWidget(Widget.HealthFill, 0, 5)
                if PB and slua.isValid(PB) then Widget.HealthFill = PB else return end
            end

            pcall(function()
                if Widget.HealthFill.SetWidgetVisibility then Widget.HealthFill:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end
                if Widget.HealthFill.SetRenderOpacity then Widget.HealthFill:SetRenderOpacity(1.0) end
                if Widget.HealthFill.SetPercent then
                    Widget.HealthFill:SetPercent(pct)
                    
                    -- [FIX VIP] Xóa bỏ rào cản IsOriginalProgressBar để ÉP MÀU mọi lúc
                    local color
                    if pct > 0.5 then 
                        -- Máu nhiều: Xanh Lá Cây
                        color = FLinearColor and FLinearColor(0.0, 1.0, 0.0, 1.0) or {R=0,G=255,B=0,A=255}
                    elseif pct > 0.25 then 
                        -- Nửa máu: Cam/Vàng
                        color = FLinearColor and FLinearColor(1.0, 0.5, 0.0, 1.0) or {R=255,G=128,B=0,A=255}
                    else 
                        -- Yếu máu: Đỏ
                        color = FLinearColor and FLinearColor(1.0, 0.0, 0.0, 1.0) or {R=255,G=0,B=0,A=255} 
                    end
                    
                    -- 1. Ép màu bằng hàm chuẩn
                    if Widget.HealthFill.SetFillColorAndOpacity then 
                        Widget.HealthFill:SetFillColorAndOpacity(color) 
                    end
                    
                    -- 2. Ép màu sâu vào Style (Khắc phục triệt để lỗi màu trắng xám của UI gốc UE4)
                    pcall(function()
                        if Widget.IsOriginalProgressBar then
                            local style = Widget.HealthFill.WidgetStyle
                            if style and style.FillImage then
                                style.FillImage.TintColor = color
                                Widget.HealthFill:SetWidgetStyle(style)
                            end
                        end
                    end)
                end
            end)
        end
        return
    end
end

function PlayerMapMarker.RemoveESPWidget(Widget, KeyStr)
    if not Widget then return end
    local Container = Widget.Container or Widget
    pcall(function()
        local ptr = tostring(Container)
        PlayerMapMarker.ESPWidgetPtrs[ptr] = nil
        Container:RemoveFromParent()
        Container:ConditionalBeginDestroy()
    end)
    if KeyStr then
        PlayerMapMarker.RemoveSnapLine(KeyStr)
        if PlayerMapMarker.RemoveSkeletonLines then
            PlayerMapMarker.RemoveSkeletonLines(KeyStr)
        end
    end
end

function PlayerMapMarker.CreateSnapLine()
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return nil end
    local Border = nil
    pcall(function() Border = CGame:NewObjectFromPath("/Script/UMG.Border", PlayerMapMarker.ESPCanvas) end)
    if not Border or not slua.isValid(Border) then return nil end

    local color = PlayerMapMarker.SnapLineColor or (FLinearColor and FLinearColor(1.0, 1.0, 1.0, PlayerMapMarker.SnapLineOpacity or 0.7) or {R=1,G=1,B=1,A=PlayerMapMarker.SnapLineOpacity or 0.7})
    pcall(function() Border:SetBrushColor(color) end)
    pcall(function() Border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
    pcall(function() Border.RenderTransformPivot = FVector2D and FVector2D(0.0, 0.5) or {X=0,Y=0.5} end)
    pcall(function() Border:SetRenderTransformPivot(FVector2D and FVector2D(0.0, 0.5) or {X=0,Y=0.5}) end)

    local Slot = nil
    pcall(function()
        Slot = PlayerMapMarker.ESPCanvas:AddChildToCanvas(Border)
        if Slot then Slot:SetAutoSize(false) Slot:SetZOrder(1) end
    end)
    return { Widget = Border, Slot = Slot }
end

function PlayerMapMarker.GetSnapLineStartPos(PC)
    local screenPixelW, screenPixelH = 0, 0
    local scale = 1.0

    pcall(function()
        if PC and PC.GetViewportSize then
            local vs = FVector2D and FVector2D(0, 0) or {X=0,Y=0}
            PC:GetViewportSize(vs)
            if vs and vs.X and vs.X > 200 then screenPixelW = vs.X screenPixelH = vs.Y end
        end
    end)
    if screenPixelW <= 200 then
        pcall(function()
            local WLL = WidgetLayoutLibrary
            if WLL and WLL.GetViewportSize then
                local vs = WLL.GetViewportSize(PC)
                if vs and vs.X and vs.X > 200 then screenPixelW = vs.X screenPixelH = vs.Y end
            end
        end)
    end
    pcall(function()
        local WLL = WidgetLayoutLibrary
        if WLL and WLL.GetViewportScale then
            local s = WLL.GetViewportScale(PC)
            if s and type(s) == "number" and s > 0 then scale = s end
        end
    end)
    if screenPixelW <= 200 then
        screenPixelW = (PlayerMapMarker._cachedViewportW or 1920) * scale
        screenPixelH = (PlayerMapMarker._cachedViewportH or 1080) * scale
    end

    if not PlayerMapMarker._CachedTopCenterPixel then PlayerMapMarker._CachedTopCenterPixel = FVector2D and FVector2D(0, 0) or {X=0,Y=0} end
    PlayerMapMarker._CachedTopCenterPixel.X = screenPixelW / 2.0
    PlayerMapMarker._CachedTopCenterPixel.Y = (PlayerMapMarker.SnapLineOriginY or 50) * scale

    local fromCanvasPos = PlayerMapMarker.ScreenPixelToCanvasLocal(PC, PlayerMapMarker._CachedTopCenterPixel)
    local fromX = fromCanvasPos.X + (PlayerMapMarker.SnapLineOriginOffsetX or 0)
    local fromY = fromCanvasPos.Y

    return fromX, fromY
end

function PlayerMapMarker.UpdateSnapLine(KeyStr, CanvasPos, bOnScreen, fromX, fromY)
    if not PlayerMapMarker.bUseSnapLines then return end
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return end

    local LineData = PlayerMapMarker.SnapLineWidgets[KeyStr]

    if not bOnScreen or not CanvasPos then
        if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
            pcall(function() LineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
        end
        return
    end

    local bIsNew = false
    if not LineData then
        LineData = PlayerMapMarker.CreateSnapLine()
        if not LineData or not LineData.Widget or not LineData.Slot then return end
        PlayerMapMarker.SnapLineWidgets[KeyStr] = LineData
        bIsNew = true
    end

    local Widget = LineData.Widget
    local Slot = LineData.Slot

    pcall(function() Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
    
    if not LineData._PivotSet then
        pcall(function() Widget.RenderTransformPivot = FVector2D and FVector2D(0.0, 0.5) or {X=0,Y=0.5} end)
        pcall(function() Widget:SetRenderTransformPivot(FVector2D and FVector2D(0.0, 0.5) or {X=0,Y=0.5}) end)
        LineData._PivotSet = true
    end

    local toX = CanvasPos.X + (PlayerMapMarker.SnapLineHeadOffsetX or 0)
    local toY = CanvasPos.Y + (PlayerMapMarker.SnapLineHeadOffsetY or 0)
    local dx = toX - fromX
    local dy = toY - fromY
    local length = math.sqrt(dx * dx + dy * dy)
    local thickness = PlayerMapMarker.SnapLineThickness or 1.5

    local angle_rad = 0
    if math.atan2 then angle_rad = math.atan2(dy, dx) else angle_rad = math.atan(dy, dx) end
    local angle = angle_rad * (180.0 / math.pi)

    if not LineData._CachedPosVec then
        LineData._CachedPosVec = FVector2D and FVector2D(fromX, fromY - thickness / 2.0) or {X=fromX, Y=fromY - thickness / 2.0}
        LineData._CachedSizeVec = FVector2D and FVector2D(length, thickness) or {X=length, Y=thickness}
    else
        LineData._CachedPosVec.X = fromX ; LineData._CachedPosVec.Y = fromY - thickness / 2.0
        LineData._CachedSizeVec.X = length ; LineData._CachedSizeVec.Y = thickness
    end

    pcall(function() 
        Slot:SetPosition(LineData._CachedPosVec) 
        Slot:SetSize(LineData._CachedSizeVec)
        if bIsNew then Slot:SetZOrder(1) end
    end)
    pcall(function() Widget:SetRenderAngle(angle) end)
end

function PlayerMapMarker.RemoveSnapLine(KeyStr)
    local LineData = PlayerMapMarker.SnapLineWidgets[KeyStr]
    if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
        pcall(function() LineData.Widget:RemoveFromParent() LineData.Widget:ConditionalBeginDestroy() end)
        PlayerMapMarker.SnapLineWidgets[KeyStr] = nil
    end
end

function PlayerMapMarker.ClearAllSnapLines()
    for KeyStr, LineData in pairs(PlayerMapMarker.SnapLineWidgets) do
        if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
            pcall(function() LineData.Widget:RemoveFromParent() LineData.Widget:ConditionalBeginDestroy() end)
        end
    end
    PlayerMapMarker.SnapLineWidgets = {}
end

-- ====== BẮT ĐẦU: LOGIC SKELETON TỪ CODE MẪU ======
function PlayerMapMarker.ScreenPixelToCanvasLocalRaw(PC, screenX, screenY)
    local scaleX = PlayerMapMarker._CanvasScaleX or 1.0
    local scaleY = PlayerMapMarker._CanvasScaleY or 1.0
    local offsetX = PlayerMapMarker._CanvasOffsetX or 0
    local offsetY = PlayerMapMarker._CanvasOffsetY or 0
    return screenX * scaleX + offsetX, screenY * scaleY + offsetY
end

function PlayerMapMarker.ProjectWorldToCanvasLocalRaw(PC, WorldLoc)
    if not IsValid(PC) or not WorldLoc then return false, 0, 0 end
    if not PlayerMapMarker._tempScreenPixelPos then
        PlayerMapMarker._tempScreenPixelPos = FVector2D and FVector2D(0, 0) or {X=0, Y=0}
    end
    local tempPos = PlayerMapMarker._tempScreenPixelPos
    local bOK = false
    pcall(function()
        local res = PC:ProjectWorldLocationToScreen(WorldLoc, tempPos, true)
        if res == true or res == 1 then bOK = true end
    end)
    if not bOK or (tempPos.X == 0 and tempPos.Y == 0) then return false, 0, 0 end
    local canvasX, canvasY = PlayerMapMarker.ScreenPixelToCanvasLocalRaw(PC, tempPos.X, tempPos.Y)
    return true, canvasX, canvasY
end

function PlayerMapMarker.GetBoneLocationWithFallback(Character, PrimaryBoneName)
    if not IsValid(Character) or not PrimaryBoneName then return nil end
    if Character._cachedBoneNames and Character._cachedBoneNames[PrimaryBoneName] then
        local cachedName = Character._cachedBoneNames[PrimaryBoneName]
        local loc = nil
        pcall(function()
            local Mesh = PlayerMapMarker.GetCharacterMesh(Character)
            if Mesh and Game:IsValid(Mesh) then
                if Mesh.GetSocketLocation then loc = Mesh:GetSocketLocation(cachedName)
                elseif Mesh.GetBoneLocation then loc = Mesh:GetBoneLocation(cachedName) end
            end
        end)
        if loc then return loc end
    end
    local fallbacks = PlayerMapMarker.BoneNameFallbacks[PrimaryBoneName] or {PrimaryBoneName}
    for _, bname in ipairs(fallbacks) do
        local loc = nil
        pcall(function()
            local Mesh = PlayerMapMarker.GetCharacterMesh(Character)
            if Mesh and Game:IsValid(Mesh) then
                if Mesh.GetSocketLocation then loc = Mesh:GetSocketLocation(bname)
                elseif Mesh.GetBoneLocation then loc = Mesh:GetBoneLocation(bname) end
            end
        end)
        if loc then
            if not Character._cachedBoneNames then Character._cachedBoneNames = {} end
            Character._cachedBoneNames[PrimaryBoneName] = bname
            return loc
        end
    end
    return nil
end

function PlayerMapMarker.IsPlayerVisible(PC, Character)
    if not IsValid(PC) or not IsValid(Character) then return false end
    local now = os.clock()
    if Character._lastVisTime and (now - Character._lastVisTime) < 0.15 then
        return Character._cachedIsVisible or false
    end
    Character._lastVisTime = now
    local bVis = false
    pcall(function()
        if PC.LineOfSightTo then
            if not PlayerMapMarker._ZeroVector then
                local VT = FVector or import("/Script/CoreUObject.Vector")
                if VT then PlayerMapMarker._ZeroVector = VT(0, 0, 0) end
            end
            bVis = PC:LineOfSightTo(Character, PlayerMapMarker._ZeroVector, false)
        end
    end)
    if not bVis then
        local KismetSystemLibrary = import("KismetSystemLibrary")
        if KismetSystemLibrary and KismetSystemLibrary.LineTraceSingle then
            pcall(function()
                local camMgr = nil
                local GameplayStatics = import("GameplayStatics")
                if GameplayStatics and GameplayStatics.GetPlayerCameraManager then
                    camMgr = GameplayStatics.GetPlayerCameraManager(PC, 0)
                end
                local startLoc = camMgr and camMgr:GetCameraLocation() or PlayerMapMarker.GetMyLocation()
                local headLoc = PlayerMapMarker.GetBoneLocationWithFallback(Character, "head")
                if startLoc and headLoc then
                    if not PlayerMapMarker._CachedHitResult then
                        local HitResultClass = import("HitResult") or import("/Script/Engine.HitResult")
                        PlayerMapMarker._CachedHitResult = HitResultClass and HitResultClass() or {}
                    end
                    local bHit = KismetSystemLibrary.LineTraceSingle(PC, startLoc, headLoc, 0, false, nil, 0, PlayerMapMarker._CachedHitResult, true)
                    if bHit then
                        local hitActor = nil
                        if type(PlayerMapMarker._CachedHitResult.GetActor) == "function" then hitActor = PlayerMapMarker._CachedHitResult:GetActor()
                        elseif PlayerMapMarker._CachedHitResult.Actor then hitActor = PlayerMapMarker._CachedHitResult.Actor end
                        if hitActor and (hitActor == Character or (type(hitActor.IsChildOf) == "function" and hitActor:IsChildOf(Character))) then
                            bVis = true
                        end
                    else
                        bVis = true
                    end
                end
            end)
        end
    end
    Character._cachedIsVisible = bVis
    return bVis
end

function PlayerMapMarker.CreateSkeletonLineWidget()
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return nil end
    local Border = nil
    pcall(function() Border = CGame:NewObjectFromPath("/Script/UMG.Border", PlayerMapMarker.ESPCanvas) end)
    if not Border or not slua.isValid(Border) then return nil end
    pcall(function() Border.RenderTransformPivot = FVector2D and FVector2D(0.0, 0.5) or {X=0, Y=0.5} end)
    pcall(function() Border:SetRenderTransformPivot(FVector2D and FVector2D(0.0, 0.5) or {X=0, Y=0.5}) end)
    local Slot = nil
    pcall(function()
        Slot = PlayerMapMarker.ESPCanvas:AddChildToCanvas(Border)
        if Slot then Slot:SetAutoSize(false) Slot:SetZOrder(5) end
    end)
    return { 
        Widget = Border, Slot = Slot,
        posVec = FVector2D and FVector2D(0, 0) or {X=0, Y=0},
        sizeVec = FVector2D and FVector2D(0, 0) or {X=0, Y=0},
        lastFromX = -99999, lastFromY = -99999,
        lastToX = -99999, lastToY = -99999
    }
end

function PlayerMapMarker.UpdateSkeletonLines(KeyStr, Character, PC, bVisible, TeamColor, bPlayerOnScreen, charLoc)
    if not PlayerMapMarker.bUseSkeleton then return end
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return end
    local PlayerBones = PlayerMapMarker.SkeletonWidgets[KeyStr]
    if not bVisible or not IsValid(Character) or not IsValid(PC) then
        if PlayerBones then
            for _, LineData in ipairs(PlayerBones) do
                if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
                    LineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                    LineData.Widget._isSelfHitTestVisible = false
                end
            end
        end
        return
    end

    if not charLoc then charLoc = PlayerMapMarker.GetESPLocation(Character) end
    if not charLoc then return end

    if bPlayerOnScreen == nil then
        local bOnScreen, _, _ = PlayerMapMarker.ProjectWorldToCanvasLocalRaw(PC, charLoc)
        bPlayerOnScreen = bOnScreen
    end
    if not bPlayerOnScreen then
        if PlayerBones then
            for _, LineData in ipairs(PlayerBones) do
                if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
                    LineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                    LineData.Widget._isSelfHitTestVisible = false
                end
            end
        end
        return
    end

    local dist = 0
    local myLoc = PlayerMapMarker._CachedMyLoc or PlayerMapMarker.GetMyLocation()
    if myLoc and charLoc then
        local dx = (charLoc.X or 0) - (myLoc.X or 0)
        local dy = (charLoc.Y or 0) - (myLoc.Y or 0)
        local dz = (charLoc.Z or 0) - (myLoc.Z or 0)
        dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    end

    if PlayerMapMarker.SkeletonMaxDistance and PlayerMapMarker.SkeletonMaxDistance > 0 then
        if dist > PlayerMapMarker.SkeletonMaxDistance then
            if PlayerBones then
                for _, LineData in ipairs(PlayerBones) do
                    if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
                        LineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                        LineData.Widget._isSelfHitTestVisible = false
                    end
                end
            end
            return
        end
    end

    if not PlayerBones then
        PlayerBones = {}
        PlayerMapMarker.SkeletonWidgets[KeyStr] = PlayerBones
    end

    local lineColor = nil
    if PlayerMapMarker.bUseVisibilityColor then
        local bTargetVisible = PlayerMapMarker.IsPlayerVisible(PC, Character)
        if bTargetVisible then lineColor = PlayerMapMarker.SkeletonVisibleColor or FLinearColor(0.0, 1.0, 0.0, 0.8)
        else lineColor = PlayerMapMarker.SkeletonCoverColor or FLinearColor(0.9, 0.0, 0.0, 0.6) end
    else
        lineColor = PlayerMapMarker.SkeletonColor or TeamColor or FLinearColor(1.0, 1.0, 1.0, PlayerMapMarker.SkeletonOpacity or 0.8)
    end

    local cache = PlayerMapMarker._StaticBoneLocCache
    for k in pairs(cache) do cache[k] = nil end
    local lineIndex = 0
    local thickness = PlayerMapMarker.SkeletonThickness or 1.2
    if not Character._cachedBones3D then Character._cachedBones3D = {} end

    for _, chain in ipairs(PlayerMapMarker.SkeletonChains) do
        local lastCanvasX, lastCanvasY = nil, nil
        for _, boneName in ipairs(chain) do
            local boneWorldLoc = cache[boneName]
            if boneWorldLoc == nil then
                boneWorldLoc = PlayerMapMarker.GetBoneLocationWithFallback(Character, boneName) or false
                cache[boneName] = boneWorldLoc
            end
            if boneWorldLoc == false then boneWorldLoc = nil end

            local currentCanvasX, currentCanvasY = nil, nil
            if boneWorldLoc then
                local bOnScreen, cX, cY = PlayerMapMarker.ProjectWorldToCanvasLocalRaw(PC, boneWorldLoc)
                if bOnScreen then
                    currentCanvasX = cX
                    currentCanvasY = cY
                end
            end

            if lastCanvasX and currentCanvasX then
                lineIndex = lineIndex + 1
                local LineData = PlayerBones[lineIndex]
                if not LineData or not LineData.Widget or not slua.isValid(LineData.Widget) then
                    LineData = PlayerMapMarker.CreateSkeletonLineWidget()
                    if LineData then PlayerBones[lineIndex] = LineData end
                end

                if LineData and LineData.Widget and LineData.Slot then
                    local Widget = LineData.Widget
                    local Slot = LineData.Slot

                    if Widget._cachedColor ~= lineColor then
                        Widget:SetBrushColor(lineColor)
                        Widget._cachedColor = lineColor
                    end
                    if not Widget._isSelfHitTestVisible then
                        Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                        Widget._isSelfHitTestVisible = true
                    end

                    local fromX = lastCanvasX
                    local fromY = lastCanvasY
                    local toX = currentCanvasX
                    local toY = currentCanvasY

                    local threshold = 0.15
                    if dist > 8000 then threshold = 0.8 elseif dist > 4000 then threshold = 0.4 end

                    if math.abs(fromX - LineData.lastFromX) > threshold or
                       math.abs(fromY - LineData.lastFromY) > threshold or
                       math.abs(toX - LineData.lastToX) > threshold or
                       math.abs(toY - LineData.lastToY) > threshold then

                        LineData.lastFromX = fromX
                        LineData.lastFromY = fromY
                        LineData.lastToX = toX
                        LineData.lastToY = toY

                        local dx = toX - fromX
                        local dy = toY - fromY
                        local length = math.sqrt(dx * dx + dy * dy)
                        local angle_rad = (math.atan2 and math.atan2(dy, dx)) or math.atan(dy, dx)
                        local angle = angle_rad * 57.29577951308232

                        local pVec = LineData.posVec
                        pVec.X = fromX ; pVec.Y = fromY - thickness / 2.0
                        Slot:SetPosition(pVec)

                        local sVec = LineData.sizeVec
                        sVec.X = length ; sVec.Y = thickness
                        Slot:SetSize(sVec)
                        Widget:SetRenderAngle(angle)
                    end
                end
            end
            lastCanvasX = currentCanvasX
            lastCanvasY = currentCanvasY
        end
    end

    for i = lineIndex + 1, #PlayerBones do
        local LineData = PlayerBones[i]
        if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
            LineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            LineData.Widget._isSelfHitTestVisible = false
        end
    end
end

function PlayerMapMarker.RemoveSkeletonLines(KeyStr)
    local PlayerBones = PlayerMapMarker.SkeletonWidgets[KeyStr]
    if PlayerBones then
        for _, LineData in ipairs(PlayerBones) do
            if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
                pcall(function()
                    LineData.Widget:RemoveFromParent()
                    LineData.Widget:ConditionalBeginDestroy()
                end)
            end
        end
        PlayerMapMarker.SkeletonWidgets[KeyStr] = nil
    end
end

function PlayerMapMarker.ClearAllSkeletonLines()
    for KeyStr, PlayerBones in pairs(PlayerMapMarker.SkeletonWidgets) do
        for _, LineData in ipairs(PlayerBones) do
            if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
                pcall(function()
                    LineData.Widget:RemoveFromParent()
                    LineData.Widget:ConditionalBeginDestroy()
                end)
            end
        end
    end
    PlayerMapMarker.SkeletonWidgets = {}
end
-- ====== KẾT THÚC: LOGIC SKELETON ======

function PlayerMapMarker.ClearAllESP()
    RedBoxOverlay.Stop()
    for KeyStr, Data in pairs(PlayerMapMarker.ESPWidgets) do
        PlayerMapMarker.RemoveESPWidget(Data.Widget, KeyStr)
    end
    PlayerMapMarker.ESPWidgets = {}
    PlayerMapMarker.ESPWidgetPtrs = {}
    PlayerMapMarker.ClearAllSnapLines()
    PlayerMapMarker.ClearAllSkeletonLines()
    if PlayerMapMarker.ESPCanvas and Game:IsValid(PlayerMapMarker.ESPCanvas) then
        pcall(function()
            local n = PlayerMapMarker.ESPCanvas:GetChildrenCount()
            for i = n - 1, 0, -1 do
                local child = PlayerMapMarker.ESPCanvas:GetChildAt(i)
                if child and slua.isValid(child) then
                    if PlayerMapMarker.IsOurESPWidget(child) then PlayerMapMarker.ESPCanvas:RemoveChild(child) end
                end
            end
        end)
    end
    PlayerMapMarker.ESPCanvas = nil
    PlayerMapMarker._OBHeadWidgetClass = nil
    PlayerMapMarker._OBHeadWidgetLoadFailed = false
    PlayerMapMarker._bDumpedWidgetChildren = false
    PlayerMapMarker._cachedViewportW = 1920
    PlayerMapMarker._cachedViewportH = 1080
end

function PlayerMapMarker.UpdateESP(AllPlayers, MyLoc)
    if not PlayerMapMarker.bUseScreenESP then return end
    
    -- Đồng bộ Config Dây và Xương
    PlayerMapMarker.bUseSnapLines = _G.LexusConfig.Esp9_Line
    PlayerMapMarker.bUseSkeleton = _G.LexusConfig.Esp9_Skeleton

    if not PlayerMapMarker.InitESPCanvas() then
        return
    end

    if PlayerMapMarker._OBHeadWidgetLoadFailed then return end

    local PC = PlayerMapMarker.GetMyPlayerController()
    if IsValid(PC) then
        PlayerMapMarker.UpdateCanvasTransform(PC)
    end

    local fromX, fromY = 0, 0
    if PlayerMapMarker.bUseSnapLines and IsValid(PC) then
        fromX, fromY = PlayerMapMarker.GetSnapLineStartPos(PC)
    end

    local MyKey = PlayerMapMarker.GetMyPlayerKey()
    local SeenKeys = {}
    
    local MyChar = nil
    pcall(function()
        local GDP = PlayerMapMarker.GetGameplayData()
        if GDP and GDP.GetLocalCharacter then
            MyChar = GDP.GetLocalCharacter()
        else
            if PC and PC.GetPawn then MyChar = PC:GetPawn() end
        end
    end)
    local MyTeamID = PlayerMapMarker.GetTeamID(MyChar)

    for PlayerKey, Character in pairs(AllPlayers) do
        if IsValid(Character) then
            local bIsMe = PlayerMapMarker.IsMe(Character, PlayerKey, MyKey)
            local bIsAI = PlayerMapMarker.IsAI(Character)
            local KeyStr = tostring(PlayerKey)
            local Name = PlayerMapMarker.GetPlayerName(Character)

            local Loc = PlayerMapMarker.GetESPLocation(Character)

            local DistStr = ""
            if MyLoc and Loc then
                DistStr = PlayerMapMarker.GetDistanceString(MyLoc, Loc)
            end

            local bSkip = false
            if bIsMe and not PlayerMapMarker.bIncludeMe then bSkip = true end
            if bIsAI and not PlayerMapMarker.bIncludeAI then bSkip = true end
            
            local TeamID = PlayerMapMarker.GetTeamID(Character)
            if MyTeamID ~= nil and TeamID == MyTeamID and not bIsMe then
                bSkip = true
            end

            local bIsAlive = PlayerMapMarker.IsAlive(Character)

            if not bSkip and Loc then
                SeenKeys[KeyStr] = true
                local ESPData = PlayerMapMarker.ESPWidgets[KeyStr]

                -- [THÊM MỚI] Check Bật Tắt Tên và Khoảng Cách
                local Text = ""
                if _G.LexusConfig.Esp9_Name then Text = Name end
                if _G.LexusConfig.Esp9_Distance and DistStr and DistStr ~= "" then
                    if Text ~= "" then Text = string.format("%s [%s]", Text, DistStr) else Text = string.format("[%s]", DistStr) end
                end

                local bOnScreen, CanvasPos = PlayerMapMarker.ProjectWorldToCanvasLocal(PC, Loc)

                if not ESPData then
                    local Widget = PlayerMapMarker.CreateESPWidget()
                    if Widget then
                        PlayerMapMarker.ESPWidgets[KeyStr] = {
                            Widget = Widget,
                            Character = Character,
                            Name = Name,
                            LastDistStr = DistStr,
                            TeamID = TeamID,
                        }
                        PlayerMapMarker.UpdateESPText(Widget, Text)
                        if bIsAlive then
                            PlayerMapMarker.UpdateESPPositionWithPC(Widget, Loc, PC, CanvasPos)
                            PlayerMapMarker.ApplyTeamColor(Widget, TeamID)
                            local HP = Character.Health or 0
                            local MaxHP = Character.MaxHealth or 120
                            local pct = 0
                            if HP > 0 and MaxHP > 0 then
                                pct = HP / MaxHP
                                if pct > 1 then pct = 1 end
                                if pct < 0 then pct = 0 end
                            end
                            PlayerMapMarker.UpdateESPHealth(Widget, pct)
                            PlayerMapMarker.AddWeaponIconToESP(Widget, Character)
                            
                            if PlayerMapMarker.bUseSnapLines then
                                PlayerMapMarker.UpdateSnapLine(KeyStr, CanvasPos, bOnScreen, fromX, fromY)
                            else
                                PlayerMapMarker.RemoveSnapLine(KeyStr)
                            end

                            if PlayerMapMarker.bUseSkeleton then
                                PlayerMapMarker.UpdateSkeletonLines(KeyStr, Character, PC, true, PlayerMapMarker.GetTeamColor(TeamID), bOnScreen, Loc)
                            else
                                PlayerMapMarker.RemoveSkeletonLines(KeyStr)
                            end
                        else
                            local Container = Widget.Container or Widget
                            pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                            PlayerMapMarker.UpdateESPHealth(Widget, 0)
                            PlayerMapMarker.RemoveSnapLine(KeyStr)
                            PlayerMapMarker.RemoveSkeletonLines(KeyStr)
                        end
                    end
                else
                    ESPData.Character = Character
                    ESPData.Name = Name
                    ESPData.LastDistStr = DistStr
                    if bIsAlive then
                        -- Xóa chữ "if TeamID ~= ESPData.TeamID" để nó quét màu Team liên tục, ăn công tắc lập tức
                        ESPData.TeamID = TeamID
                        PlayerMapMarker.ApplyTeamColor(ESPData.Widget, TeamID)
                        
                        -- UpdateESPText already skips identical strings.
                        PlayerMapMarker.UpdateESPText(ESPData.Widget, Text)
                        PlayerMapMarker.UpdateESPPositionWithPC(ESPData.Widget, Loc, PC, CanvasPos)
                        local HP = Character.Health or 0
                        local MaxHP = Character.MaxHealth or 120
                        local pct = 0
                        if HP > 0 and MaxHP > 0 then
                            pct = HP / MaxHP
                            if pct > 1 then pct = 1 end
                            if pct < 0 then pct = 0 end
                        end
                        PlayerMapMarker.UpdateESPHealth(ESPData.Widget, pct)
                        PlayerMapMarker.AddWeaponIconToESP(ESPData.Widget, Character)
                        
                        if PlayerMapMarker.bUseSnapLines then
                            PlayerMapMarker.UpdateSnapLine(KeyStr, CanvasPos, bOnScreen, fromX, fromY)
                        else
                            PlayerMapMarker.RemoveSnapLine(KeyStr)
                        end

                        if PlayerMapMarker.bUseSkeleton then
                            PlayerMapMarker.UpdateSkeletonLines(KeyStr, Character, PC, true, PlayerMapMarker.GetTeamColor(TeamID), bOnScreen, Loc)
                        else
                            PlayerMapMarker.RemoveSkeletonLines(KeyStr)
                        end
                    else
                        local Container = ESPData.Widget.Container or ESPData.Widget
                        pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                        PlayerMapMarker.UpdateESPHealth(ESPData.Widget, 0)
                        PlayerMapMarker.RemoveSnapLine(KeyStr)
                        PlayerMapMarker.RemoveSkeletonLines(KeyStr)
                    end
                end
            end
        end
    end

    for KeyStr, Data in pairs(PlayerMapMarker.ESPWidgets) do
        if not SeenKeys[KeyStr] then
            PlayerMapMarker.RemoveESPWidget(Data.Widget, KeyStr)
            PlayerMapMarker.ESPWidgets[KeyStr] = nil
        end
    end
end

function PlayerMapMarker.UpdateESPLight()
    if RedBoxOverlay and RedBoxOverlay.bActive then RedBoxOverlay.UpdatePosition() end
    if not PlayerMapMarker.bUseScreenESP then return end
    
    -- Đồng bộ Config Dây và Xương
    PlayerMapMarker.bUseSnapLines = _G.LexusConfig.Esp9_Line
    PlayerMapMarker.bUseSkeleton = _G.LexusConfig.Esp9_Skeleton
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return end
    local PC = PlayerMapMarker.GetMyPlayerController()
    if not IsValid(PC) then return end

    PlayerMapMarker.UpdateCanvasTransform(PC)

    local fromX, fromY = 0, 0
    if PlayerMapMarker.bUseSnapLines then fromX, fromY = PlayerMapMarker.GetSnapLineStartPos(PC) end

    for KeyStr, ESPData in pairs(PlayerMapMarker.ESPWidgets) do
        local Widget = ESPData.Widget
        local Character = ESPData.Character
        local Container = Widget and (Widget.Container or Widget)
        local bWidgetValid = false
        pcall(function() bWidgetValid = Container and slua.isValid(Container) end)

        if Widget and bWidgetValid and Character and IsValid(Character) then
            local bIsAlive = PlayerMapMarker.IsAlive(Character)
            if not bIsAlive then
                if ESPData._LastContainerVisibility ~= UEnums.ESlateVisibility.Collapsed then
                    ESPData._LastContainerVisibility = UEnums.ESlateVisibility.Collapsed
                    pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                end
                PlayerMapMarker.RemoveSnapLine(KeyStr)
                PlayerMapMarker.RemoveSkeletonLines(KeyStr)
            else
                -- [FIX VIP] Xóa vệt đen trên vòng lặp Light
                local bShowAnyUI = _G.LexusConfig.Esp9_Name or _G.LexusConfig.Esp9_Distance or _G.LexusConfig.Esp9_HP or _G.LexusConfig.Esp9_Team or _G.LexusConfig.Esp9_Weapon
                local desiredVisibility = bShowAnyUI and UEnums.ESlateVisibility.SelfHitTestInvisible or UEnums.ESlateVisibility.Collapsed
                if ESPData._LastContainerVisibility ~= desiredVisibility then
                    ESPData._LastContainerVisibility = desiredVisibility
                    pcall(function() Container:SetWidgetVisibility(desiredVisibility) end)
                end
                if ESPData._LastRenderOpacity ~= 1.0 then
                    ESPData._LastRenderOpacity = 1.0
                    pcall(function() Container:SetRenderOpacity(1.0) end)
                end

                local Loc = PlayerMapMarker.GetESPLocation(Character)
                if Loc then
                    local bOnScreen, CanvasPos = PlayerMapMarker.ProjectWorldToCanvasLocal(PC, Loc)
                    PlayerMapMarker.UpdateESPPositionWithPC(Widget, Loc, PC, CanvasPos)
                    if PlayerMapMarker.bUseSnapLines then PlayerMapMarker.UpdateSnapLine(KeyStr, CanvasPos, bOnScreen, fromX, fromY)
                    else PlayerMapMarker.RemoveSnapLine(KeyStr) end

                    if PlayerMapMarker.bUseSkeleton then
                        PlayerMapMarker.UpdateSkeletonLines(KeyStr, Character, PC, true, PlayerMapMarker.GetTeamColor(ESPData.TeamID), bOnScreen, Loc)
                    else
                        PlayerMapMarker.RemoveSkeletonLines(KeyStr)
                    end
                else 
                    PlayerMapMarker.RemoveSnapLine(KeyStr)
                    PlayerMapMarker.RemoveSkeletonLines(KeyStr)
                end
            end
        end
    end
end

function PlayerMapMarker.UpdateESPDistances()
    if not PlayerMapMarker.bUseScreenESP then return end
    local MyLoc = PlayerMapMarker.GetMyLocation()
    if not MyLoc then return end
    local PC = PlayerMapMarker.GetMyPlayerController()
    if not IsValid(PC) then return end
    PlayerMapMarker.UpdateCanvasTransform(PC)

    for KeyStr, ESPData in pairs(PlayerMapMarker.ESPWidgets) do
        local Character = ESPData.Character
        local Widget = ESPData.Widget
        local Container = Widget and (Widget.Container or Widget)
        local bWidgetValid = false
        pcall(function() bWidgetValid = Container and slua.isValid(Container) end)
        if Character and IsValid(Character) and Widget and bWidgetValid then
            local Loc = PlayerMapMarker.GetESPLocation(Character)
            if Loc then
                local Dist = PlayerMapMarker.CalcDistance(MyLoc, Loc)
                ESPData.LastDistance = Dist

                if PlayerMapMarker.bShowDistance then
                    local DistStr = ""
                    local Meters = 0
                    if Dist then
                        Meters = Dist / 100
                        if Meters < 1000 then DistStr = string.format("%dm", math.floor(Meters))
                        else DistStr = string.format("%.1fkm", Meters / 1000) end
                    end

                    local Name = ESPData.Name or "Unknown"
                    local Text = ""
                    
                    -- Đồng bộ với công tắc ESP 9
                    if _G.LexusConfig.Esp9_Name then Text = Name end
                    if _G.LexusConfig.Esp9_Distance and DistStr and DistStr ~= "" then
                        if Text ~= "" then Text = string.format("%s [%s]", Text, DistStr) else Text = string.format("[%s]", DistStr) end
                    end
                    
                    ESPData.LastDistStr = DistStr
                    -- UpdateESPText already skips identical strings; do not force a UE widget rewrite.
                    PlayerMapMarker.UpdateESPText(Widget, Text)
                end
            end
        end
    end
end

function PlayerMapMarker.ScanAndUpdate()
    local AllChars = PlayerMapMarker.GetAllCharacters()
    if not AllChars then RedBoxOverlay.SetCounts(0, 0) return 0 end

    local MyKey = PlayerMapMarker.GetMyPlayerKey()
    local MyLoc = PlayerMapMarker.GetMyLocation()

    local MyChar = nil
    pcall(function()
        local GDP = PlayerMapMarker.GetGameplayData()
        if GDP and GDP.GetLocalCharacter then MyChar = GDP.GetLocalCharacter()
        else local PC = PlayerMapMarker.GetMyPlayerController() if PC and PC.GetPawn then MyChar = PC:GetPawn() end end
    end)
    local MyTeamID = PlayerMapMarker.GetTeamID(MyChar)

    local realPlayers = 0
    local botPlayers = 0

    for PlayerKey, Character in pairs(AllChars) do
        if IsValid(Character) then
            local bIsMe = PlayerMapMarker.IsMe(Character, PlayerKey, MyKey)
            local bIsAI = PlayerMapMarker.IsAI(Character)
            local bIsAlive = PlayerMapMarker.IsAlive(Character)

            if bIsAlive and not bIsMe then
                local bIsMyTeam = false
                if MyTeamID ~= nil then
                    local targetTeamID = PlayerMapMarker.GetTeamID(Character)
                    if targetTeamID == MyTeamID then bIsMyTeam = true end
                end
                
                if not bIsMyTeam then
                    if bIsAI then botPlayers = botPlayers + 1
                    else realPlayers = realPlayers + 1 end
                end
            end
        end
    end

    -- [THÊM MỚI] Bật Tắt Bảng Đếm Người
    if _G.LexusConfig.Esp9_Count then
        if RedBoxOverlay.bActive then RedBoxOverlay.SetCounts(realPlayers, botPlayers)
        else RedBoxOverlay.Start() end
    else
        if RedBoxOverlay.bActive then RedBoxOverlay.Stop() end
    end

    if PlayerMapMarker.bUseScreenESP then
        PlayerMapMarker.UpdateESP(AllChars, MyLoc)
        return 0
    end
    return 0
end

function PlayerMapMarker._CancelTimers()
    -- Invalidate callbacks first. This protects us even on builds where a timer
    -- handle cannot be removed through the exposed API.
    PlayerMapMarker._TimerGeneration = (PlayerMapMarker._TimerGeneration or 0) + 1

    local handles = PlayerMapMarker._TimerHandles or {}
    local pc = PlayerMapMarker._ActiveTimerPC

    for i = 1, #handles do
        local h = handles[i]
        if h then
            pcall(function()
                if pc and slua and slua.isValid and slua.isValid(pc) and pc.RemoveGameTimer then
                    pc:RemoveGameTimer(h)
                end
            end)
            pcall(function()
                if _G.Game and _G.Game.RemoveGameTimer then
                    _G.Game:RemoveGameTimer(h)
                end
            end)
        end
    end

    PlayerMapMarker._TimerHandles = {}
    PlayerMapMarker._ActiveTimerPC = nil
    PlayerMapMarker._ActiveTimerTick = 0
    PlayerMapMarker._AttachPending = nil
    PlayerMapMarker._AttachPendingTime = nil
end

function PlayerMapMarker.AttachTimers()
    pcall(function()
        local pc = PlayerMapMarker.GetMyPlayerController()
        if not (pc and slua and slua.isValid and slua.isValid(pc) and pc.AddGameTimer) then
            local now = os.clock()
            if PlayerMapMarker._AttachPending
                and PlayerMapMarker._AttachPendingTime
                and (now - PlayerMapMarker._AttachPendingTime) < 2.0 then
                return
            end

            PlayerMapMarker._AttachPending = true
            PlayerMapMarker._AttachPendingTime = now
            pcall(function()
                require("timer").SetGameTimer(1.0, false, function()
                    PlayerMapMarker._AttachPending = nil
                    PlayerMapMarker._AttachPendingTime = nil
                    PlayerMapMarker.AttachTimers()
                end)
            end)
            return
        end

        PlayerMapMarker._AttachPending = nil
        PlayerMapMarker._AttachPendingTime = nil

        local now = os.clock()
        local lastPC = PlayerMapMarker._ActiveTimerPC
        local lastTick = PlayerMapMarker._ActiveTimerTick
        if lastPC and slua.isValid(lastPC) and lastPC == pc then
            if lastTick > 0 and (now - lastTick) < 5.0 then return end
        end

        -- If a previous generation survived unexpectedly, invalidate/cancel it
        -- before creating a new set for this controller.
        PlayerMapMarker._CancelTimers()
        PlayerMapMarker._ActiveTimerPC = pc
        PlayerMapMarker._ActiveTimerTick = now

        local generation = PlayerMapMarker._TimerGeneration or 0
        local handles = PlayerMapMarker._TimerHandles

        local h1 = nil
        local h2 = nil
        local h3 = nil

        pcall(function()
            h1 = pc:AddGameTimer(PlayerMapMarker.nUpdateInterval or 0.5, true, function()
                if generation ~= PlayerMapMarker._TimerGeneration then return end
                PlayerMapMarker._ActiveTimerTick = os.clock()
                if PlayerMapMarker.bActive then
                    pcall(PlayerMapMarker.ScanAndUpdate)
                end
            end)
        end)

        pcall(function()
            h2 = pc:AddGameTimer(PlayerMapMarker._LightUpdateInterval or 0.05, true, function()
                if generation ~= PlayerMapMarker._TimerGeneration then return end
                PlayerMapMarker._ActiveTimerTick = os.clock()
                if PlayerMapMarker.bActive then
                    pcall(PlayerMapMarker.UpdateESPLight)
                end
            end)
        end)

        pcall(function()
            h3 = pc:AddGameTimer(PlayerMapMarker._DistanceUpdateInterval or 0.1, true, function()
                if generation ~= PlayerMapMarker._TimerGeneration then return end
                PlayerMapMarker._ActiveTimerTick = os.clock()
                if PlayerMapMarker.bActive and PlayerMapMarker.bUseScreenESP and PlayerMapMarker.bShowDistance then
                    pcall(PlayerMapMarker.UpdateESPDistances)
                end
            end)
        end)

        if h1 then handles[#handles + 1] = h1 end
        if h2 then handles[#handles + 1] = h2 end
        if h3 then handles[#handles + 1] = h3 end

        pcall(function() require("timer").SetGameTimer(5.0, false, PlayerMapMarker.AttachTimers) end)
    end)
end

-- EnsureRunning: if config is ON, rebind timers/canvas after every match change.
-- Settings stay ON; runtime is forced back in sync without a manual toggle.
function PlayerMapMarker.EnsureRunning()
    local L = _G.LexusConfig or {}
    local c = _G.GTLMODConfig or {}
    local want = (L.EspLoai9 == true)
        or (L.Esp9_Line == true) or (L.Esp9_Count == true) or (L.Esp9_Name == true)
        or (L.Esp9_Weapon == true) or (L.Esp9_Distance == true) or (L.Esp9_HP == true)
        or (L.Esp9_Team == true) or (L.Esp9_Skeleton == true)
        or (c.EspLine == true) or (c.CounterEnabled == true) or (c.EspModelName == true)
        or (c.EspWeaponIcon == true)
    if not want then
        if PlayerMapMarker.bActive then PlayerMapMarker.Stop() end
        return false
    end

    local pc = nil
    pcall(function() pc = PlayerMapMarker.GetMyPlayerController() end)
    local lastPC = PlayerMapMarker._ActiveTimerPC
    local pcChanged = (not lastPC)
        or (slua and slua.isValid and not slua.isValid(lastPC))
        or (pc ~= nil and lastPC ~= pc)
    local canvasOk = false
    pcall(function()
        canvasOk = PlayerMapMarker.ESPCanvas and Game and Game.IsValid and Game:IsValid(PlayerMapMarker.ESPCanvas)
    end)
    local now = os.clock()
    local lastTick = PlayerMapMarker._ActiveTimerTick or 0
    local stale = (lastTick > 0) and ((now - lastTick) > 6.0)
    local lastEnsure = PlayerMapMarker._LastEnsureAt or 0
    local tooSoon = (os.clock() - lastEnsure) < 0.35

    local needsRebind = (not PlayerMapMarker.bActive) or pcChanged or (not canvasOk) or stale
    if not needsRebind then
        return true
    end
    if tooSoon and PlayerMapMarker.bActive and not pcChanged then
        return true
    end
    PlayerMapMarker._LastEnsureAt = os.clock()

    if pcChanged or not canvasOk or stale then
        -- [STABILITY] Do not leave callbacks from the previous match alive while
        -- the canvas/controller is being rebuilt.
        pcall(PlayerMapMarker._CancelTimers)
    end

    if not canvasOk then
        PlayerMapMarker.ESPWidgets = {}
        PlayerMapMarker.ESPWidgetPtrs = {}
        PlayerMapMarker.SnapLineWidgets = {}
        PlayerMapMarker.SkeletonWidgets = {}
        PlayerMapMarker.ESPCanvas = nil
        PlayerMapMarker._OBHeadWidgetClass = nil
        PlayerMapMarker._OBHeadWidgetLoadFailed = false
    end

    PlayerMapMarker.bActive = true
    PlayerMapMarker._FrameCount = 0
    PlayerMapMarker._ActiveTimerPC = nil
    PlayerMapMarker._ActiveTimerTick = 0
    PlayerMapMarker._AttachPending = nil
    pcall(function() PlayerMapMarker.AttachTimers() end)
    pcall(function() PlayerMapMarker.ScanAndUpdate() end)
    return true
end

function PlayerMapMarker.Start()
    -- Never early-return on stale bActive from a previous match.
    pcall(PlayerMapMarker._CancelTimers)
    PlayerMapMarker.bActive = false
    PlayerMapMarker.ESPCanvas = nil
    -- [FIX] Canvas wipe kills RedBoxOverlay counter. Reset it so CounterTickLoop
    -- will re-create it on the fresh canvas from the next EnsureRunning() call.
    pcall(function()
        local RBO = _G.RedBoxOverlay
        if RBO and (RBO.bActive or RBO.MainContainer) then
            RBO.bActive = false
            RBO.MainContainer = nil
            RBO.WidgetSlot = nil
            RBO.TextBlockPlayer = nil
            RBO.TextBlockBot = nil
            RBO._CachedPosVec = nil
            RBO._CachedTextPlayer = ""
            RBO._CachedTextBot = ""
        end
    end)
    return PlayerMapMarker.EnsureRunning()
end

function PlayerMapMarker.Stop()
    PlayerMapMarker.bActive = false
    PlayerMapMarker._FrameCount = 0
    pcall(PlayerMapMarker._CancelTimers)
    PlayerMapMarker.ClearAllESP()
end

_G.PlayerMapMarker = PlayerMapMarker
-- ============================================================
-- KẾT THÚC: LÕI ESP LOẠI 9 (TỪ CODE MẪU GỐC FULL LOGIC)


print("[StarExact] ESP9 PlayerMapMarker + RedBox (black) loaded")
end) -- end pcall StarExactESP9



-- ============================================================
-- STAR Active Grenade Warning — toggle (default OFF), original detection when ON
-- Gold/white animated "BOOM" for thrown/cooked frag grenades
-- ============================================================
pcall(function()
if _G._StarGrenadePortComplete then return end
_G._StarGrenadePortComplete = true

_G.LexusConfig = _G.LexusConfig or {}
if _G.LexusConfig.EspItemBom == nil then _G.LexusConfig.EspItemBom = false end
_G.GTLMODConfig = _G.GTLMODConfig or {}
if _G.GTLMODConfig.EspActiveBom == nil then _G.GTLMODConfig.EspActiveBom = false end
_G.LexusConfig.EspActiveBom = (_G.GTLMODConfig.EspActiveBom == true)
_G.LexusConfig.EspBomMaster = _G.LexusConfig.EspActiveBom

local function GValid(obj)
    if not obj then return false end
    local ok, v = pcall(function() return slua.isValid(obj) end)
    return ok and v == true
end

local Cached_MyHUD = nil
local function RefreshHUD()
    pcall(function()
        local PC = nil
        if GameplayData and GameplayData.GetPlayerController then
            PC = GameplayData.GetPlayerController()
        end
        if not GValid(PC) then
            local GS = import("GameplayStatics")
            if GS and GS.GetPlayerController then
                PC = GS.GetPlayerController(slua.getWorld and slua.getWorld() or nil, 0)
            end
        end
        if not GValid(PC) and slua_GameFrontendHUD and slua_GameFrontendHUD.GetPlayerController then
            PC = slua_GameFrontendHUD:GetPlayerController()
        end
        if GValid(PC) then Cached_MyHUD = PC.MyHUD end
    end)
    return Cached_MyHUD
end

local function GetLocalPlayer()
    local lp = nil
    pcall(function()
        if GameplayData and GameplayData.GetPlayerCharacter then
            lp = GameplayData.GetPlayerCharacter()
        end
        if not GValid(lp) then
            local PC = nil
            if GameplayData and GameplayData.GetPlayerController then
                PC = GameplayData.GetPlayerController()
            end
            if GValid(PC) and PC.GetPlayerCharacterSafety then
                lp = PC:GetPlayerCharacterSafety()
            end
        end
    end)
    return lp
end

-- Gold <-> white continuous shimmer
local function GrenadeSweepColor(now, phase)
    local t = (now * 2.8 + phase) % (math.pi * 2)
    local sweep = (math.sin(t) + 1) * 0.5
    local gold = { R = 255, G = 210, B = 40, A = 255 }
    local white = { R = 255, G = 255, B = 255, A = 255 }
    return {
        R = math.floor(gold.R + (white.R - gold.R) * sweep + 0.5),
        G = math.floor(gold.G + (white.G - gold.G) * sweep + 0.5),
        B = math.floor(gold.B + (white.B - gold.B) * sweep + 0.5),
        A = 255
    }
end

local function ClassifyBomb(actor)
    local nameLower = ""
    pcall(function()
        if type(actor.GetName) == "function" then
            nameLower = string.lower(tostring(actor:GetName() or ""))
        else
            nameLower = string.lower(tostring(actor))
        end
        if (nameLower == "" or nameLower == "nil") and actor.GetClass then
            local c = actor:GetClass()
            if c and c.GetName then nameLower = string.lower(tostring(c:GetName() or "")) end
        end
    end)
    if nameLower == "" then return 0, false end

    local bType = 0
    if string.find(nameLower, "smoke", 1, true) then
        bType = 2
    elseif string.find(nameLower, "molotov", 1, true) or string.find(nameLower, "burn", 1, true)
        or string.find(nameLower, "incendiary", 1, true) then
        bType = 3
    elseif string.find(nameLower, "flash", 1, true) or string.find(nameLower, "stun", 1, true) then
        bType = 4
    elseif string.find(nameLower, "m79", 1, true) or string.find(nameLower, "launcher", 1, true) then
        bType = 5
    elseif string.find(nameLower, "grenade", 1, true) or string.find(nameLower, "frag", 1, true)
        or string.find(nameLower, "boom", 1, true) or string.find(nameLower, "projectile_grenade", 1, true)
        or string.find(nameLower, "bp_grenade", 1, true) or string.find(nameLower, "thrown", 1, true) then
        bType = 1
    end
    if bType == 0 then return 0, false end

    -- active (thrown/cooked) vs ground item
    local isItem = true
    if string.find(nameLower, "projectile", 1, true)
        or string.find(nameLower, "thrown", 1, true)
        or string.find(nameLower, "cook", 1, true)
        or string.find(nameLower, "predict", 1, true)
        or string.find(nameLower, "flying", 1, true) then
        isItem = false
    end
    -- pin pulled / cooking = treat as active
    pcall(function()
        if actor.bIsPinPulled or actor.bPinPulled then isItem = false end
        if type(actor.IsPinPulled) == "function" and actor:IsPinPulled() then isItem = false end
        if actor.ExplosionTime or actor.ExplodeTime then isItem = false end
    end)
    return bType, isItem
end

local function StarGrenadeTick()
    -- Toggle (default OFF). Original detection path when ON.
    _G.LexusConfig = _G.LexusConfig or {}
    if not (_G.GTLMODConfig and _G.GTLMODConfig.EspActiveBom == true) then
        _G.LexusConfig.EspActiveBom = false
        _G.LexusConfig.EspBomMaster = false
        return
    end
    _G.LexusConfig.EspBomMaster = true
    _G.LexusConfig.EspActiveBom = true

    local localPlayer = GetLocalPlayer()
    Cached_MyHUD = Cached_MyHUD or RefreshHUD()
    local MyHUD = Cached_MyHUD
    if not GValid(MyHUD) then
        RefreshHUD()
        MyHUD = Cached_MyHUD
    end
    if not GValid(MyHUD) or not MyHUD.AddDebugText then return end

    pcall(function()
        if not _G.CachedGameplayStatics then
            _G.CachedGameplayStatics = import("GameplayStatics")
        end
        local GS = _G.CachedGameplayStatics
        if not GS then return end

        if not _G.CachedActorClass_ForBomb then
            _G.CachedActorClass_ForBomb = import("Actor")
        end

        local world = nil
        pcall(function()
            if slua.getWorld then world = slua.getWorld() end
        end)

        local gameInstance = nil
        pcall(function()
            local ui_util = require("client.common.ui_util")
            if ui_util and ui_util.GetGameInstance then
                gameInstance = ui_util.GetGameInstance()
            end
        end)

        local ctx = gameInstance or world
        if not ctx then return end

        local curTime = os.clock()

        -- Scan every 0.2s (tighter so cook/throw is not missed)
        if not _G.LastBombScanTime or (curTime - _G.LastBombScanTime) > 0.30 then
            _G.LastBombScanTime = curTime

            -- soft-clear non-bomb cache every 3s so misclassifications can recover
            if not _G.LastBombCacheWipe or (curTime - _G.LastBombCacheWipe) > 3.0 then
                _G.LastBombCacheWipe = curTime
                _G.NonBombCache = setmetatable({}, { __mode = "k" })
            end
            if not _G.BombCache then
                _G.BombCache = setmetatable({}, { __mode = "k" })
            end
            if not _G.NonBombCache then
                _G.NonBombCache = setmetatable({}, { __mode = "k" })
            end

            local activeBombs = {}
            local itemBombs = {}
            local arr = nil
            pcall(function()
                if slua.Array and UEnums then
                    arr = slua.Array(UEnums.EPropertyClass.Object, _G.CachedActorClass_ForBomb)
                end
            end)

            local allActors = nil
            pcall(function()
                if arr then
                    allActors = GS.GetAllActorsOfClass(ctx, _G.CachedActorClass_ForBomb, arr)
                else
                    allActors = GS.GetAllActorsOfClass(ctx, _G.CachedActorClass_ForBomb)
                end
            end)

            if allActors then
                local function consider(actor)
                    if not GValid(actor) then return end
                    if actor.bHidden or actor.bTearOff then return end
                    if _G.NonBombCache[actor] then return end

                    local bType, isItem = 0, false
                    local known = _G.BombCache[actor]
                    if known then
                        bType = known.type
                        isItem = known.isItem
                    else
                        bType, isItem = ClassifyBomb(actor)
                        if bType > 0 then
                            _G.BombCache[actor] = { type = bType, isItem = isItem }
                        else
                            _G.NonBombCache[actor] = true
                            return
                        end
                    end

                    local pending = false
                    pcall(function()
                        if type(actor.IsPendingKill) == "function" then
                            pending = actor:IsPendingKill()
                        end
                    end)
                    if pending then
                        _G.BombCache[actor] = nil
                        return
                    end

                    if isItem then
                        itemBombs[#itemBombs + 1] = { act = actor, type = bType }
                    else
                        activeBombs[#activeBombs + 1] = { act = actor, type = bType }
                    end
                end

                if type(allActors) == "table" then
                    for _, actor in pairs(allActors) do
                        consider(actor)
                    end
                else
                    pcall(function()
                        local n = allActors.Num and allActors:Num() or 0
                        for i = 0, n - 1 do
                            local actor = allActors:Get(i)
                            consider(actor)
                        end
                    end)
                end
            end

            _G.CachedActiveBombs = activeBombs
            _G.CachedItemBombs = itemBombs
        end

        local curGameTime = 0
        pcall(function()
            if GS.GetTimeSeconds then
                curGameTime = GS.GetTimeSeconds(ctx) or 0
            end
        end)

        local function DrawBombs(bombList, isItem, maxDist)
            if not bombList then return end
            for _, item in ipairs(bombList) do
                local bomb = item.act
                local bType = item.type
                if not GValid(bomb) or bomb.bHidden then goto cont end

                local distM = 0
                pcall(function()
                    if GValid(localPlayer) and localPlayer.GetDistanceTo then
                        distM = localPlayer:GetDistanceTo(bomb) / 100
                    end
                end)
                if distM <= 0 or distM > maxDist then goto cont end

                local displayName = "BOOM"
                local bombColor = GrenadeSweepColor(curTime, isItem and 0.7 or 0.0)
                local zOffset = isItem and 15 or 30

                if bType == 1 then
                    displayName = "BOOM"
                    bombColor = GrenadeSweepColor(curTime, 0.0)
                elseif bType == 2 then
                    displayName = "SMOKE"
                    bombColor = { R = 220, G = 220, B = 220, A = 255 }
                elseif bType == 3 then
                    displayName = "FIRE"
                    bombColor = { R = 255, G = 120, B = 20, A = 255 }
                elseif bType == 4 then
                    displayName = "FLASH"
                    bombColor = { R = 100, G = 255, B = 255, A = 255 }
                elseif bType == 5 then
                    displayName = "SMOKE SHELL"
                    bombColor = { R = 120, G = 255, B = 120, A = 255 }
                end

                local text = string.format("%s [%dm]", displayName, math.floor(distM))
                local shouldTimer = not isItem
                if isItem then
                    pcall(function()
                        if bomb.bIsPinPulled or bomb.bPinPulled
                            or (type(bomb.IsPinPulled) == "function" and bomb:IsPinPulled()) then
                            shouldTimer = true
                        end
                    end)
                end

                if shouldTimer and curGameTime > 0 then
                    local timeLeft = -1
                    pcall(function()
                        if bomb.ExplosionTime then
                            timeLeft = bomb.ExplosionTime - curGameTime
                        elseif bomb.ExplodeTime then
                            timeLeft = bomb.ExplodeTime - curGameTime
                        end
                    end)
                    if timeLeft < 0 or timeLeft > 100 then
                        _G.ActiveBombTimers = _G.ActiveBombTimers or {}
                        local bombId = tostring(bomb)
                        if not _G.ActiveBombTimers[bombId] then
                            _G.ActiveBombTimers[bombId] = curGameTime
                        end
                        local elapsed = curGameTime - _G.ActiveBombTimers[bombId]
                        local maxTime = (bType == 1 and 7.0) or (bType == 2 and 45.0)
                            or (bType == 3 and 12.0) or (bType == 4 and 5.0) or 45.0
                        timeLeft = maxTime - elapsed
                    end
                    if timeLeft < 0 then timeLeft = 0 end
                    if timeLeft > 0.05 then
                        text = string.format("%s (%.1fs)", text, timeLeft)
                    end
                end

                local dynamicScale = math.max(0.75, 1.25 - (distM / maxDist) * 0.4)
                pcall(function()
                    MyHUD:AddDebugText(
                        text, bomb, 0.28,
                        { X = 0, Y = 0, Z = zOffset },
                        { X = 0, Y = 0, Z = zOffset },
                        bombColor, true, false, true, nil, dynamicScale, true
                    )
                end)
                ::cont::
            end
        end

        -- Always draw active (thrown/cooked). Ground items only if enabled.
        DrawBombs(_G.CachedActiveBombs, false, 180)
        if _G.LexusConfig.EspItemBom then
            DrawBombs(_G.CachedItemBombs, true, 50)
        end
    end)
end

-- Fast loop — starts immediately, always on
do
    local tk = nil
    pcall(function() tk = require("common.time_ticker") end)
    if tk and tk.AddTimerOnce then
        local function loop()
            pcall(StarGrenadeTick)
            tk.AddTimerOnce(0.08, loop)
        end
        tk.AddTimerOnce(1.0, loop)
    end
end
-- Loop: fast only when toggle ON (no lag when OFF)
do
    local tk = nil
    pcall(function() tk = require("common.time_ticker") end)
    if tk and tk.AddTimerOnce then
        local function loop()
            pcall(StarGrenadeTick)
            local on = _G.GTLMODConfig and _G.GTLMODConfig.EspActiveBom == true
            tk.AddTimerOnce(on and 0.12 or 1.0, loop)
        end
        tk.AddTimerOnce(1.5, loop)
    end
end
print("[StarExact] Active Grenade Warning — restored + toggle READY")
end)
















-- ====================================================================
-- START AUTHENTICATED RUNTIME (called after online login success)
-- ====================================================================
function _G.StartAuthenticatedRuntime()
    if _G._MAGOO_RUNTIME_STARTED then return end
    local licensed = (_G._LICENSE_OK == true)
        or (_G.LoginSystem and _G.LoginSystem.IsLoggedIn and _G.LoginSystem.IsLoggedIn())
    if not licensed then return end
    isExpired = false
    _G._MOD_EXPIRED = false
    _G._LICENSE_OK = true
    _G._MAGOO_RUNTIME_STARTED = true

    pcall(function()
        local ticker = GetTicker and GetTicker() or nil
        if not ticker then
            local ok, tk = pcall(require, "common.time_ticker")
            if ok then ticker = tk end
        end
        if ticker and ticker.AddTimerOnce then
            if not _G._MAGOO_FEATURE_TICKERS_STARTED then
                _G._MAGOO_FEATURE_TICKERS_STARTED = true
                ticker.AddTimerOnce(0.2, MainTick)
                ticker.AddTimerOnce(0.2, AimbotTick)
                ticker.AddTimerOnce(0.2, PrivFeaturesTick)
                ticker.AddTimerOnce(0.016, IpadFOVTick)
                ticker.AddTimerOnce(1.15, CounterTickLoop)
                ticker.AddTimerOnce(LIMITS.ESP_LINE_UPDATE, ESPLineTickLoop)
            end
            ticker.AddTimerOnce(0.5, function()
                if _G.InitAllModSystems then pcall(_G.InitAllModSystems) end
                if _G.EnsureModFeaturesRunning then pcall(_G.EnsureModFeaturesRunning) end
            end)
            -- Post-login popups: rules (one-time) then verified (once per game session)
            ticker.AddTimerOnce(1.2, function()
                if type(ShowRulesOnce) == "function" then
                    pcall(ShowRulesOnce, nil)
                elseif type(_G.ShowRulesOnce) == "function" then
                    pcall(_G.ShowRulesOnce, nil)
                end
            end)
        end
    end)
    print("[MAGOO] Authenticated runtime started")
end


-- ONLINE LOGIN BOOTSTRAP
-- ====================================================================
pcall(function()
    if _G._MAGOO_LOGIN_BOOTSTRAPPED then return end
    _G._MAGOO_LOGIN_BOOTSTRAPPED = true
    local tk = GetTicker()
    local function boot()
        if not _G.LoginSystem or not _G.LoginSystem.Start then return end
        _G.LoginSystem.Start(nil, function()
            isExpired = false
            _G._LICENSE_OK = true
            if type(StartAuthenticatedRuntime) == "function" then
                StartAuthenticatedRuntime()
            elseif type(_G.StartAuthenticatedRuntime) == "function" then
                _G.StartAuthenticatedRuntime()
            end
        end)
        -- If already licensed from a previous session in this process
        if _G._LICENSE_OK == true then
            isExpired = false
            pcall(function()
                if type(_G.StartAuthenticatedRuntime) == "function" then
                    _G.StartAuthenticatedRuntime()
                end
            end)
        end
        -- Failsafe: after a few seconds, if still locked but a key file exists,
        -- unlock offline so the mod menu never stays completely dead.
        pcall(function()
            local tk = GetTicker and GetTicker() or nil
            if not tk then
                local ok, t = pcall(require, "common.time_ticker")
                if ok then tk = t end
            end
            if tk and tk.AddTimerOnce then
                tk.AddTimerOnce(5.0, function()
                    if _G._LICENSE_OK == true then return end
                    local key = nil
                    pcall(function()
                        if _G.LoginSystem and _G.LoginSystem.GetCurrentKey then
                            key = _G.LoginSystem.GetCurrentKey()
                        end
                    end)
                    if key and key ~= "" then
                        _G._LICENSE_OK = true
                        _G._LICENSE_KEY = key
                        isExpired = false
                        _G._MOD_EXPIRED = false
                        pcall(function()
                            if type(_G.StartAuthenticatedRuntime) == "function" then
                                _G.StartAuthenticatedRuntime()
                            end
                        end)
                    end
                end)
            end
        end)
    end
    if tk and tk.AddTimerOnce then
        tk.AddTimerOnce(0.4, boot)
        tk.AddTimerOnce(2.0, function()
            if _G._LICENSE_OK and not _G._MAGOO_FEATURE_TICKERS_STARTED then
                pcall(function() _G.StartAuthenticatedRuntime() end)
            end
        end)
        tk.AddTimerOnce(5.0, function()
            if _G._LICENSE_OK and not _G._MAGOO_FEATURE_TICKERS_STARTED then
                pcall(function() _G.StartAuthenticatedRuntime() end)
            end
        end)
    else
        boot()
    end
end)


-- ====================================================================
-- UNIVERSAL SKY CONTROLLER — deep blue-purple night (slight black)
-- Menu: NIGHT SKY (uses GTLMODConfig.BlackSky as toggle)
-- ====================================================================
pcall(function()
if _G.UniversalSkyController then return end

local UniversalSkyController = {}

local SKY_CONFIG = {
    Enabled = false,
    Preset = "CUSTOM",
    CustomRGB = { R = 12, G = 8, B = 48 },
    Alpha = 1.0,
    MaterialOverride = nil,
    Apply = {
        SkyMaterial      = true,
        SkyLight         = false,
        DirectionalLight = false,
        Fog              = false,
    },
    AutoRefresh = true,
    RefreshSeconds = 2.5,
}

local COLOR_PRESETS = {
    NIGHT_SKY      = { R = 5,  G = 10, B = 35 },
    DEEP_SPACE     = { R = 8,  G = 0,  B = 25 },
    DEEP_BLUE_PURPLE = { R = 12, G = 8,  B = 48 },
    DARK_PURPLE    = { R = 40, G = 5,  B = 70 },
    BLACK          = { R = 0,  G = 0,  B = 0 },
}

local SKY_VECTOR_PARAMETERS = {
    "SkyColor", "Sky_Color", "SkyTint", "Sky_Tint",
    "TintColor", "Tint_Color", "Color", "BaseColor",
    "ZenithColor", "Zenith Color", "HorizonColor", "Horizon Color",
    "CloudColor", "Cloud Color", "Sky Color", "Sky Tint",
}

local function skySafe(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

local function skyValid(obj)
    if obj == nil then return false end
    if slua and slua.isValid then
        local ok, result = pcall(slua.isValid, obj)
        if ok then return result end
    end
    return true
end

local function clamp255(v)
    v = tonumber(v) or 0
    if v < 0 then return 0 end
    if v > 255 then return 255 end
    return v
end

local function selectedRGB()
    if SKY_CONFIG.Preset == "CUSTOM" then
        return SKY_CONFIG.CustomRGB
    end
    return COLOR_PRESETS[SKY_CONFIG.Preset] or COLOR_PRESETS.DEEP_BLUE_PURPLE
end

local function normalizedRGB()
    local c = selectedRGB()
    return {
        R = clamp255(c.R) / 255.0,
        G = clamp255(c.G) / 255.0,
        B = clamp255(c.B) / 255.0,
        A = SKY_CONFIG.Alpha or 1.0
    }
end

local function makeLinearColor(c)
    local LC = _G.LinearColor
    if not LC then
        local ok, m = pcall(import, "LinearColor")
        if ok then LC = m end
    end
    if LC then
        local value = skySafe(function() return LC(c.R, c.G, c.B, c.A) end)
        if value then return value end
    end
    return { R = c.R, G = c.G, B = c.B, A = c.A }
end

local function getSkyWorld()
    local world = nil
    if slua_GameFrontendHUD and slua_GameFrontendHUD.GetPlayerController then
        local pc = skySafe(function() return slua_GameFrontendHUD:GetPlayerController() end)
        if skyValid(pc) then
            world = skySafe(function() return pc:GetWorld() end)
            if skyValid(world) then return world end
        end
    end
    local GDP = skySafe(function() return require("GameLua.GameCore.Data.GameplayData") end)
    if GDP then
        local pc2 = skySafe(function() return GDP.GetPlayerController() end)
        if skyValid(pc2) then
            world = skySafe(function() return pc2:GetWorld() end)
            if skyValid(world) then return world end
        end
    end
    if slua and slua.getWorld then
        world = skySafe(function() return slua.getWorld() end)
        if skyValid(world) then return world end
    end
    return nil
end

local function getActorsByClass(classPath)
    local world = getSkyWorld()
    if not skyValid(world) then return {} end
    local cls = skySafe(import, classPath)
    if not cls then return {} end
    local results = {}
    pcall(function()
        local UGameplayStatics = import("GameplayStatics")
        if not UGameplayStatics or not UGameplayStatics.GetAllActorsOfClass then return end
        local AActor = import("/Script/Engine.Actor")
        local OutList = slua.Array(UEnums.EPropertyClass.Object, AActor)
        UGameplayStatics.GetAllActorsOfClass(world, cls, OutList)
        if OutList and OutList.Num then
            local n = OutList:Num()
            for i = 1, n do
                local actor = OutList:Get(i - 1)
                if skyValid(actor) then results[#results + 1] = actor end
            end
        end
    end)
    return results
end

local function eachSkyActor(list, callback)
    if type(list) ~= "table" then return end
    for _, actor in pairs(list) do
        if skyValid(actor) then skySafe(callback, actor) end
    end
end

local function applyMaterial(material, color)
    if not skyValid(material) then return false end
    local changed = false
    for _, param in ipairs(SKY_VECTOR_PARAMETERS) do
        if material.SetVectorParameterValue then
            local ok = pcall(function() material:SetVectorParameterValue(param, color) end)
            if ok then changed = true end
        end
    end
    return changed
end

local function applyToMesh(mesh, color)
    if not skyValid(mesh) then return false end
    local changed = false
    local num = 1
    if mesh.GetNumMaterials then
        num = skySafe(function() return mesh:GetNumMaterials() end) or 1
    end
    for index = 0, math.max(0, num - 1) do
        local mat = nil
        if mesh.CreateDynamicMaterialInstance then
            mat = skySafe(function() return mesh:CreateDynamicMaterialInstance(index) end)
        end
        if not skyValid(mat) and mesh.GetMaterial then
            mat = skySafe(function() return mesh:GetMaterial(index) end)
        end
        if skyValid(mat) and applyMaterial(mat, color) then changed = true end
    end
    return changed
end

local function applySkyMaterials(color)
    local skySphereClasses = {
        "/Game/Arts_Scenes/Meshs/Sky/BP_Sky_Sphere_Base.BP_Sky_Sphere_Base_C",
        "/Script/Engine.StaticMeshActor",
    }
    for _, classPath in ipairs(skySphereClasses) do
        eachSkyActor(getActorsByClass(classPath), function(actor)
            local name = tostring(skySafe(function() return actor:GetName() end) or "")
            local lower = string.lower(name)
            local isSkySphere = string.find(classPath, "BP_Sky_Sphere", 1, true) ~= nil
            local looksLikeSky = string.find(lower, "sky", 1, true) ~= nil
                or string.find(lower, "dome", 1, true) ~= nil
                or string.find(lower, "sphere", 1, true) ~= nil
                or string.find(lower, "cloud", 1, true) ~= nil
                or string.find(lower, "atmos", 1, true) ~= nil
            if isSkySphere or looksLikeSky then
                local mesh = actor.StaticMeshComponent
                    or actor.StaticMesh
                    or actor.SkyMesh
                    or actor.Mesh
                if skyValid(mesh) then applyToMesh(mesh, color) end
            end
        end)
    end
end

function UniversalSkyController.Apply()
    if not SKY_CONFIG.Enabled then return false end
    local n = normalizedRGB()
    local color = makeLinearColor(n)
    if SKY_CONFIG.Apply.SkyMaterial then
        skySafe(applySkyMaterials, color)
    end
    return true
end

function UniversalSkyController.SetPreset(name)
    name = tostring(name or "")
    if name ~= "CUSTOM" and not COLOR_PRESETS[name] then return false end
    SKY_CONFIG.Preset = name
    return UniversalSkyController.Apply()
end

function UniversalSkyController.SetRGB(r, g, b)
    SKY_CONFIG.CustomRGB.R = clamp255(r)
    SKY_CONFIG.CustomRGB.G = clamp255(g)
    SKY_CONFIG.CustomRGB.B = clamp255(b)
    SKY_CONFIG.Preset = "CUSTOM"
    return UniversalSkyController.Apply()
end

function UniversalSkyController.SetEnabled(v)
    SKY_CONFIG.Enabled = (v == true)
    if SKY_CONFIG.Enabled then
        return UniversalSkyController.Apply()
    end
    return true
end

function UniversalSkyController.GetConfig()
    return SKY_CONFIG
end

local function skyLoop()
    if SKY_CONFIG.Enabled then
        pcall(UniversalSkyController.Apply)
    end
    local tk = skySafe(require, "common.time_ticker")
    if tk and tk.AddTimerOnce then
        skySafe(function()
            tk.AddTimerOnce(SKY_CONFIG.RefreshSeconds, skyLoop)
        end)
    end
end

local function startSkyAutoRefresh()
    if not SKY_CONFIG.AutoRefresh then return end
    local tk = skySafe(require, "common.time_ticker")
    if not tk or not tk.AddTimerOnce then return end
    skySafe(function()
        tk.AddTimerOnce(SKY_CONFIG.RefreshSeconds, skyLoop)
    end)
end

_G.UniversalSkyController = UniversalSkyController
skySafe(startSkyAutoRefresh)
print("[MAGOO] Night Sky controller ready (deep blue-purple)")
end)


-- RETURN SECTION
-- ====================================================================
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

  -- Keep the original BRPlayerCharacterBase feature chain intact.
  -- In particular, do not replace the original vehicle/formation/UI lifecycle features.
  { BuildAircraftVehicleFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.PlayerCharacterBuildVehicleFeature" },
  { UnifiedBuildVehicleFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.UnifiedBuildVehicleFeature" },

  -- Transformation feature: keep the original implementation available.
  { CommonBornlandTransformFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.HeroPropFeature.CommonBornlandTransformFeature" },

  { ParachuteFormation = "GameLua.Mod.BaseMod.GamePlay.Feature.ParachuteFormationFeature" },
  { ParachuteSprint = "GameLua.Mod.BaseMod.GamePlay.Feature.Parachute.ParachuteSprintFeature" },
  { GeneralShowSpotFeature = "GameLua.Mod.BRMod.Gameplay.Feature.PlayerCharacterGeneralShowSpotFeature" },
  { FPPAnimMonitor = "GameLua.Mod.BaseMod.GamePlay.Feature.Player.FPPAnimMonitorFeature" }
}, "BRPlayerCharacterBase")