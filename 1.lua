local BRPlayerCharacterBase = {
  ServerRPC = {},
  ClientRPC = {},
  MulticastRPC = {},
  LuaEventContainer = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue = {
  Reliable = true,
  Params = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Object
  }
}
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Bool
  }
}
local ENetRole = import("ENetRole")
local EPawnState = import("EPawnState")
local ESpecialMovementType = import("ESpecialMovementType")
local ESpiderSwingMoveState = import("ESpiderSwingMoveState")
local ESurviveWeaponPropSlot = import("ESurviveWeaponPropSlot")
local EParachuteState = import("EParachuteState")
local EMovementMode = import("EMovementMode")
local EStateType = import("EStateType")
local ESTEPoseState = import("ESTEPoseState")
local EGameModeType = import("EGameModeType")
local STExtraGameStateBase = import("STExtraGameStateBase")
local UKismetSystemLibrary = import("KismetSystemLibrary")
local USTExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")
local GameplayData = require("GameLua.GameCore.Data.GameplayData")
local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
local MatchModeIds = require("GameLua.Mod.BaseMod.GamePlay.Config.MatchModeIdsConfig")
-- MODIFIED BY EXORTOP 
-- VIP MOD: ESP, CHAMS, WEAPON GLOW HDR, 165 FPS, IPAD VIEW, WHITE BODY, AIMBOT

-- VIP skin popup disabled: no modal is shown on load or match transitions.
-- Keep the existing per-controller load guard intact.
do
    -- Only skip a duplicate load after a previous load reached the module's
    -- final return. A nil controller during startup must not lock out loading.
    local pc = nil
    pcall(function()
        if slua_GameFrontendHUD and slua_GameFrontendHUD.GetPlayerController then
            pc = slua_GameFrontendHUD:GetPlayerController()
        end
    end)
    if _G._MOD_INIT_COMPLETE and pc ~= nil and _G._MOD_PC == pc then
        return
    end
    -- Do not mark initialization complete here: later imports/hooks can fail.
end

-- Initialize feature toggles with defaults
if not _G.Mod_ESP_Enabled then _G.Mod_ESP_Enabled = false end
if not _G.Mod_Chams_Enabled then _G.Mod_Chams_Enabled = false end
if not _G.Mod_WeaponGlow_Enabled then _G.Mod_WeaponGlow_Enabled = false end
_G.WeaponGlowColor = _G.WeaponGlowColor or 5
_G.WeaponGlowThickness = _G.WeaponGlowThickness or 3
if not _G.Mod_UnlockFPS_Enabled then _G.Mod_UnlockFPS_Enabled = false end
if not _G.Mod_IpadView_Enabled then _G.Mod_IpadView_Enabled = false end
if not _G.Mod_WhiteBody_Enabled then _G.Mod_WhiteBody_Enabled = false end
_G.IpadViewFOV = _G.IpadViewFOV or 120
_G.GraphicsUnlocked = false
_G.PrevWhiteBody = false
if not _G.Mod_CircleArrow_Enabled then _G.Mod_CircleArrow_Enabled = false end

-- ESP V2 sub-feature toggles
if not _G.Mod_ESP_ShowPlayerCount then _G.Mod_ESP_ShowPlayerCount = true end
if not _G.Mod_ESP_ShowName then _G.Mod_ESP_ShowName = true end
if not _G.Mod_ESP_ShowDistance then _G.Mod_ESP_ShowDistance = true end
if not _G.Mod_ESP_ShowHealthBar then _G.Mod_ESP_ShowHealthBar = true end
if not _G.Mod_ESP_ShowTeamColor then _G.Mod_ESP_ShowTeamColor = true end
if not _G.Mod_ESP_ShowWeaponIcon then _G.Mod_ESP_ShowWeaponIcon = true end
if not _G.Mod_ESP_ShowSnapline then _G.Mod_ESP_ShowSnapline = false end





-- Slider values for fine-tuning

local require = require
local import  = import
local isValid = slua.isValid
local pcall = pcall
local type = type
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local math = math
local string = string

local function nop() return true end
local function retFalse() return false end
local function retZero() return 0 end
local function retEmpty() return {} end
_G.CheatsEnabled = true

local function safe_require(path)
    local ok, mod = pcall(require, path)
    return ok and mod or nil
end

local ok_gd, GameplayData = pcall(require, "GameLua.GameCore.Data.GameplayData")
if not ok_gd then GameplayData = nil end

local SecurityCommonUtils = require("GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils")
local ASTExtraPlayerController = import("/Script/ShadowTrackerExtra.STExtraPlayerController")

-- ============================================================
-- CHAMS & AIMBOT VARIABLES
-- ============================================================
local FLinearColor = import("LinearColor")
local chamsTimer = nil
local processedPawns = {}
local tickCount = 0
local chamsReady = false
local colors = nil
local lastWeapon = nil

if FLinearColor then
    colors = {
        vis = FLinearColor(0, 500, 500, 1),       -- Ultra Bright Cyan
        occ = FLinearColor(500, 0, 500, 1),       -- Ultra Bright Purple
        bVis = FLinearColor(500, 500, 0, 1),      -- Ultra Bright Gold
        bOcc = FLinearColor(0, 250, 500, 1)       -- Ultra Bright Blue
    }
end

-- ============================================================
-- CHAMS FUNCTIONS
-- ============================================================
local function EnableChamsConsole()
    if chamsReady then return end
    pcall(function()
        local KSL = import("KismetSystemLibrary")
        local world = slua.getWorld()
        if not KSL or not world then return end
        
        KSL.ExecuteConsoleCommand(world, "r.EnableDrawDyeingColor 1")
        KSL.ExecuteConsoleCommand(world, "r.CustomDepth 3")
        KSL.ExecuteConsoleCommand(world, "r.IdeaOutline.Enable 1")
        KSL.ExecuteConsoleCommand(world, "r.Highlight.Enable 1")
        KSL.ExecuteConsoleCommand(world, "r.BloomQuality 5")
        KSL.ExecuteConsoleCommand(world, "r.DefaultFeature.Bloom 1")
        KSL.ExecuteConsoleCommand(world, "r.Bloom.Intensity 2.0")
        
        chamsReady = true
    end)
end

-- Disable chams: reset all processed meshes to normal
local function DisableChamsToMesh(mesh)
    if not mesh or not slua.isValid(mesh) then return end
    pcall(function()
        if mesh.SetDrawDyeing then mesh:SetDrawDyeing(false) end
        if mesh.SetDrawHighlight then mesh:SetDrawHighlight(false) end
        if mesh.SetDrawIdeaOutline then mesh:SetDrawIdeaOutline(false) end
        if mesh.SetIdeaOutlineNew then mesh:SetIdeaOutlineNew(false) end
        if mesh.SetIdeaOutlineOcclusionHighlight then mesh:SetIdeaOutlineOcclusionHighlight(false) end
        if mesh.SetIdeaOverrideOutlineAndOcclusion then mesh:SetIdeaOverrideOutlineAndOcclusion(false) end
        if mesh.SetRenderCustomDepth then mesh:SetRenderCustomDepth(false) end
    end)
end

local function DisableChams()
    pcall(function()
        -- Disable console commands
        local KSL = import("KismetSystemLibrary")
        local world = slua.getWorld()
        if KSL and world then
            KSL.ExecuteConsoleCommand(world, "r.EnableDrawDyeingColor 0")
            KSL.ExecuteConsoleCommand(world, "r.IdeaOutline.Enable 0")
            KSL.ExecuteConsoleCommand(world, "r.Highlight.Enable 0")
        end
        -- Reset all processed pawns
        local allChars = Game:GetAllPlayerPawns() or {}
        for _, pawn in pairs(allChars) do
            if slua.isValid(pawn) then
                if pawn.Mesh and slua.isValid(pawn.Mesh) then DisableChamsToMesh(pawn.Mesh) end
                local avatarComp = pawn.CharacterAvatarComp2_BP or (pawn.getAvatarComponent2 and pawn:getAvatarComponent2())
                if avatarComp and slua.isValid(avatarComp) and avatarComp.GetMeshCompBySlot then
                    for _, slot in ipairs({0,1,2,3,4,5,6,7}) do
                        local meshComp = avatarComp:GetMeshCompBySlot(slot)
                        if meshComp and slua.isValid(meshComp) then DisableChamsToMesh(meshComp) end
                    end
                end
                local weapon = pawn.GetCurrentWeapon and pawn:GetCurrentWeapon()
                if weapon and slua.isValid(weapon) and weapon.Mesh then DisableChamsToMesh(weapon.Mesh) end
            end
        end
        processedPawns = {}
        chamsReady = false
    end)
end

local function ApplyChamsToMesh(mesh, visColor, occColor)
    if not mesh or not slua.isValid(mesh) then return end
    pcall(function()
        mesh:SetDrawDyeing(true)
        mesh:SetDrawDyeingMode(1)
        mesh:SetVisibleDyeingColor(visColor)
        mesh:SetOccludedDyeingColor(occColor)
        
        mesh:SetDrawIdeaOutline(true)
        mesh:SetIdeaOutlineNew(true)
        mesh:SetIdeaOutlineOcclusionHighlight(true)
        mesh:OverrideIdeaOutlineColor(visColor)
        mesh:SetIdeaOutlineOcclusionColor(occColor)
        mesh:OverrideIdeaOutlineThickness(8.0)
        mesh:SetIdeaOverrideOutlineAndOcclusion(true)
    end)
end

local function IsAlive_Chams(pawn) -- Renamed to avoid conflict with ESP's IsPawnAlive
    if not slua.isValid(pawn) then return false end
    local hp = pawn.Health
    if hp and hp > 0 then return true end
    local status = pawn.HealthStatus
    if status then return SecurityCommonUtils.IsHealthStatusAlive(status) end
    return false
end

local function ProcessEnemy_Chams(pawn, myTeamID)
    if not slua.isValid(pawn) or not IsAlive_Chams(pawn) then return false end
    local teamID = pawn.TeamID
    if not teamID or teamID <= 0 or teamID == myTeamID then return false end
    
    local isBot = false
    pcall(function() isBot = Game:IsAI(pawn) end)
    local visColor = isBot and colors.bVis or colors.vis
    local occColor = isBot and colors.bOcc or colors.occ
    
    if pawn.Mesh and slua.isValid(pawn.Mesh) then ApplyChamsToMesh(pawn.Mesh, visColor, occColor) end
    
    local avatarComp = pawn.CharacterAvatarComp2_BP or pawn:getAvatarComponent2()
    if avatarComp and slua.isValid(avatarComp) and avatarComp.GetMeshCompBySlot then
        for _, slot in ipairs({0, 1, 2, 3, 4, 5, 6, 7}) do
            local meshComp = avatarComp:GetMeshCompBySlot(slot)
            if meshComp and slua.isValid(meshComp) then ApplyChamsToMesh(meshComp, visColor, occColor) end
        end
    end
    
    local weapon = pawn:GetCurrentWeapon()
    if weapon and slua.isValid(weapon) and weapon.Mesh then ApplyChamsToMesh(weapon.Mesh, visColor, occColor) end
    
    local playerKey = pawn.PlayerKey
    if playerKey then processedPawns[playerKey] = true end
    return true
end

-- ========================================================================
-- âš¡ ESP V2 SYSTEM (RedBoxOverlay + PlayerMapMarker) - FIXED
-- ========================================================================
local PlayerMapMarker = {}
local RedBoxOverlay = {
    bActive = false,
    MainContainer = nil,
    WidgetSlot = nil,
    TextBlock = nil,
    Width = 430,
    Height = 62,
    OffsetY = 46,
    PlayerCount = 0,
    BotCount = 0,
    Layers = {},
    FontSize = 22,
    TextScaleValue = 1.0,
    _CachedText = "",
    _CachedPosVec = nil
}

function RedBoxOverlay.Create()
    if RedBoxOverlay.MainContainer and slua.isValid(RedBoxOverlay.MainContainer) then return true end

    local ParentCanvas = PlayerMapMarker.ESPCanvas
    if not ParentCanvas or not slua.isValid(ParentCanvas) then 
        if not PlayerMapMarker.InitESPCanvas() then return false end
        ParentCanvas = PlayerMapMarker.ESPCanvas
    end
    if not ParentCanvas or not slua.isValid(ParentCanvas) then return false end

    local FLinearColor = import("LinearColor") or FLinearColor
    local FVector2D = import("Vector2D") or FVector2D
    local FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")

    local Container = nil
    pcall(function() Container = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", ParentCanvas) end)
    if not Container or not slua.isValid(Container) then return false end

    -- ===== NAYI DIMENSIONS (CENTER FIX KE SATH) =====
    local PANEL_W      = 230  -- Pura width
    local PANEL_H      = 30
    local CENTER_X     = 115  -- Exact Center of the Panel (PANEL_W / 2)
    local OFFSET_SIDE  = 76   -- Red/Green box center se kitni door hain
    local SIDE_W       = 84
    local OFFSET_BLACK = 15   -- Center shield overlapping ke liye

    -- Colors
    local GREEN_DARK   = FLinearColor(0.0, 0.45, 0.20, 1.0)
    local GREEN_BRIGHT = FLinearColor(0.0, 0.65, 0.30, 1.0)
    local GREEN_EDGE   = FLinearColor(0.0, 0.85, 0.45, 1.0)

    local RED_DARK     = FLinearColor(0.55, 0.0, 0.0, 1.0)
    local RED_BRIGHT   = FLinearColor(0.85, 0.05, 0.05, 1.0)
    local RED_EDGE     = FLinearColor(1.0, 0.15, 0.15, 1.0)

    local BLACK_DARK   = FLinearColor(0.02, 0.02, 0.02, 1.0)
    local BLACK_EDGE   = FLinearColor(0.15, 0.15, 0.15, 1.0)

    local WHITE_TEXT   = FLinearColor(1.0, 1.0, 1.0, 1.0)

    RedBoxOverlay.Layers = {}

    local function MakeSkewed(parent, offsetX, width, height, color, zOrder, shearX)
        local border = nil
        pcall(function() border = CGame:NewObjectFromPath("/Script/UMG.Border", parent) end)
        if not border or not slua.isValid(border) then return nil end
        pcall(function()
            border:SetBrushColor(color)
            border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            border:SetRenderTransformPivot(FVector2D(0.5, 0.5))
            pcall(function() border:SetRenderShear(FVector2D(shearX or 0.0, 0.0)) end)
            pcall(function() border:SetRenderShear({X=shearX or 0.0, Y=0.0}) end)
        end)
        local slot = nil
        pcall(function()
            slot = parent:AddChildToCanvas(border)
            if slot then
                slot:SetAutoSize(false)
                slot:SetAlignment(FVector2D(0.5, 0.5))
                slot:SetPosition(FVector2D(offsetX, 0))
                slot:SetSize(FVector2D(width, height))
                slot:SetZOrder(zOrder or 0)
            end
        end)
        table.insert(RedBoxOverlay.Layers, {Widget = border, Slot = slot})
        return border
    end

    local LEFT_SHEAR = 25.0
    local RIGHT_SHEAR = -25.0

    -- 1. LEFT RED PANEL (PLAYER)
    MakeSkewed(Container, CENTER_X - OFFSET_SIDE, SIDE_W + 4, PANEL_H + 4, RED_EDGE, 0, LEFT_SHEAR)
    MakeSkewed(Container, CENTER_X - OFFSET_SIDE, SIDE_W, PANEL_H, RED_BRIGHT, 1, LEFT_SHEAR)
    MakeSkewed(Container, CENTER_X - OFFSET_SIDE, SIDE_W - 2, PANEL_H - 2, RED_DARK, 2, LEFT_SHEAR)

    -- 2. RIGHT GREEN/BLUE PANEL (BOT)
    MakeSkewed(Container, CENTER_X + OFFSET_SIDE, SIDE_W + 4, PANEL_H + 4, GREEN_EDGE, 0, RIGHT_SHEAR)
    MakeSkewed(Container, CENTER_X + OFFSET_SIDE, SIDE_W, PANEL_H, GREEN_BRIGHT, 1, RIGHT_SHEAR)
    MakeSkewed(Container, CENTER_X + OFFSET_SIDE, SIDE_W - 2, PANEL_H - 2, GREEN_DARK, 2, RIGHT_SHEAR)

    -- 3. CENTER BLACK SHIELD (Red & Green ke upar overlap karke V shape banayega)
    -- Left half of the black shield (slants \)
    MakeSkewed(Container, CENTER_X - OFFSET_BLACK, 40, PANEL_H + 8, BLACK_EDGE, 3, LEFT_SHEAR)
    MakeSkewed(Container, CENTER_X - OFFSET_BLACK, 36, PANEL_H + 4, BLACK_DARK, 4, LEFT_SHEAR)
    -- Right half of the black shield (slants /)
    MakeSkewed(Container, CENTER_X + OFFSET_BLACK, 40, PANEL_H + 8, BLACK_EDGE, 3, RIGHT_SHEAR)
    MakeSkewed(Container, CENTER_X + OFFSET_BLACK, 36, PANEL_H + 4, BLACK_DARK, 4, RIGHT_SHEAR)

    -- REAL text (LEFT) - Centered correctly
    local playerText = nil
    pcall(function() playerText = CGame:NewObjectFromPath("/Script/UMG.TextBlock", Container) end)
    if playerText and slua.isValid(playerText) then
        pcall(function()
            playerText:SetText("REAL: 0")
            if FSlateColor then playerText:SetColorAndOpacity(FSlateColor(WHITE_TEXT)) else playerText:SetColorAndOpacity(WHITE_TEXT) end
            if playerText.Font then
                local f = playerText.Font
                f.Size = 13
                f.TypefaceFontName = "Bold"
                playerText.Font = f
            end
            playerText:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
        local slot = Container:AddChildToCanvas(playerText)
        if slot then
            pcall(function()
                slot:SetAutoSize(true)
                slot:SetAlignment(FVector2D(0.5, 0.5))
                slot:SetPosition(FVector2D(CENTER_X - OFFSET_SIDE, 0))
                slot:SetZOrder(100)
            end)
        end
        RedBoxOverlay.PlayerText = playerText
    end

    -- V SYMBOL (CENTER) - Perfectly aligned at true center!
    local crownText = nil
    pcall(function() crownText = CGame:NewObjectFromPath("/Script/UMG.TextBlock", Container) end)
    if crownText and slua.isValid(crownText) then
        pcall(function()
            crownText:SetText("▼")
            if FSlateColor then crownText:SetColorAndOpacity(FSlateColor(WHITE_TEXT)) else crownText:SetColorAndOpacity(WHITE_TEXT) end
            if crownText.Font then
                local f = crownText.Font
                f.Size = 16
                f.TypefaceFontName = "Bold"
                crownText.Font = f
            end
            crownText:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
        local slot = Container:AddChildToCanvas(crownText)
        if slot then
            pcall(function()
                slot:SetAutoSize(true)
                slot:SetAlignment(FVector2D(0.5, 0.5))
                slot:SetPosition(FVector2D(CENTER_X, -2)) -- Exact Center
                slot:SetZOrder(101)
            end)
        end
        RedBoxOverlay.CrownText = crownText
    end

    -- BOT text (RIGHT) - Centered correctly
    local botText = nil
    pcall(function() botText = CGame:NewObjectFromPath("/Script/UMG.TextBlock", Container) end)
    if botText and slua.isValid(botText) then
        pcall(function()
            botText:SetText("BOT: 0")
            if FSlateColor then botText:SetColorAndOpacity(FSlateColor(WHITE_TEXT)) else botText:SetColorAndOpacity(WHITE_TEXT) end
            if botText.Font then
                local f = botText.Font
                f.Size = 13
                f.TypefaceFontName = "Bold"
                botText.Font = f
            end
            botText:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
        local slot = Container:AddChildToCanvas(botText)
        if slot then
            pcall(function()
                slot:SetAutoSize(true)
                slot:SetAlignment(FVector2D(0.5, 0.5))
                slot:SetPosition(FVector2D(CENTER_X + OFFSET_SIDE, 0))
                slot:SetZOrder(100)
            end)
        end
        RedBoxOverlay.BotText = botText
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
        MainSlot:SetSize(FVector2D(PANEL_W, PANEL_H))
    end)

    RedBoxOverlay.UpdatePosition()
    return true
end

function RedBoxOverlay.SetCounts(players, bots)
    players = tonumber(players) or 0
    bots = tonumber(bots) or 0
    if RedBoxOverlay.PlayerCount == players and RedBoxOverlay.BotCount == bots then return end
    RedBoxOverlay.PlayerCount = players
    RedBoxOverlay.BotCount = bots

    if RedBoxOverlay.PlayerText and slua.isValid(RedBoxOverlay.PlayerText) then
        pcall(function()
            RedBoxOverlay.PlayerText:SetText(string.format("REAL: %d", players))
        end)
    end
    if RedBoxOverlay.BotText and slua.isValid(RedBoxOverlay.BotText) then
        pcall(function()
            RedBoxOverlay.BotText:SetText(string.format("BOT: %d", bots))
        end)
    end
end

function RedBoxOverlay.UpdatePosition()
    local Slot = RedBoxOverlay.WidgetSlot
    if not Slot or not slua.isValid(Slot) then return end
    local PC = PlayerMapMarker.GetMyPlayerController()
    if not slua.isValid(PC) then return end

    local fromX, fromY = PlayerMapMarker.GetSnapLineStartPos(PC)
    local FVector2D = import("Vector2D") or FVector2D
    pcall(function()
        if not RedBoxOverlay._CachedPosVec then
            RedBoxOverlay._CachedPosVec = FVector2D(fromX, fromY + 28)
        else
            RedBoxOverlay._CachedPosVec.X = fromX
            RedBoxOverlay._CachedPosVec.Y = fromY + 28
        end
        Slot:SetPosition(RedBoxOverlay._CachedPosVec)
        pcall(function()
            Slot:SetAlignment(FVector2D(0.5, 1.0))
            Slot:SetSize(FVector2D(230, 30))
        end)
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
    RedBoxOverlay.TextBlock = nil
    RedBoxOverlay.PlayerText = nil
    RedBoxOverlay.BotText = nil
    RedBoxOverlay.CrownText = nil
    RedBoxOverlay.Layers = {}
    RedBoxOverlay._CachedPosVec = nil
end

_G.RedBoxOverlay = RedBoxOverlay


-- ========================================================================
-- âš¡ ESP V2 SYSTEM (Continued) - FIXED
-- ========================================================================
local SlateBlueprintLibrary = nil
local WidgetLayoutLibrary = nil
local KismetMathLibrary_ESP9 = nil
local KismetSystemLibrary_ESP9 = nil

pcall(function() SlateBlueprintLibrary = import("SlateBlueprintLibrary") or import("/Script/UMG.SlateBlueprintLibrary") end)
pcall(function() WidgetLayoutLibrary = import("WidgetLayoutLibrary") or import("/Script/UMG.WidgetLayoutLibrary") end)
pcall(function() KismetMathLibrary_ESP9 = import("KismetMathLibrary") end)
pcall(function() KismetSystemLibrary_ESP9 = import("KismetSystemLibrary") end)

local FVector2D_ESP9 = _G.FVector2D or import("Vector2D")
local FLinearColor_ESP9 = _G.FLinearColor or import("LinearColor")
local FVector_ESP9 = _G.FVector or import("Vector")

PlayerMapMarker.MarkTypeID = 1007
PlayerMapMarker.bUseScreenESP = true
PlayerMapMarker.bUseScreenMark = false
PlayerMapMarker.bUseQuickSign = false
PlayerMapMarker.bUseNavigator = false
PlayerMapMarker.bUseWidgetComponent = false
PlayerMapMarker.ESPBoneName = "head"
PlayerMapMarker.ESPWorldOffsetZ = 0
PlayerMapMarker.ESPAnchorOffsetX = 35
PlayerMapMarker.ESPAnchorOffsetY = 0
PlayerMapMarker.ESPTextOffsetX = 0
PlayerMapMarker.ESPTextOffsetY = 0
PlayerMapMarker.ESPWidgetAlignment = FVector2D_ESP9 and FVector2D_ESP9(0.5, 1.0) or {X=0.5, Y=1.0}
PlayerMapMarker.ESPWidgetSize = FVector2D_ESP9 and FVector2D_ESP9(70, 21) or {X=70, Y=21}
PlayerMapMarker.ESPWidgetAutoSize = true
PlayerMapMarker.ESPWidgetZOrder = 2
PlayerMapMarker.bShowDistance = true
PlayerMapMarker.DistanceUnit = "m"
PlayerMapMarker.WeaponIconBrushW = 96
PlayerMapMarker.WeaponIconBrushH = 48
PlayerMapMarker.HPWidgetSwitcherTypeIndex = 0
PlayerMapMarker.HPWidgetSwitcherType2Index = 0
PlayerMapMarker.bForceSwitcherIndexEveryUpdate = true
PlayerMapMarker.bUseSnapLines = false
PlayerMapMarker.SnapLineThickness = 1.4
PlayerMapMarker.SnapLineOriginY = 70  -- (Value badhane se counter aur niche aayega)
PlayerMapMarker.SnapLineOriginOffsetX = 0
PlayerMapMarker.SnapLineHeadOffsetX = 0
PlayerMapMarker.SnapLineHeadOffsetY = -14
PlayerMapMarker.SnapLineColor = FLinearColor_ESP9 and FLinearColor_ESP9(1.0, 0.85, 0.0, 1.0) or {R=255, G=217, B=0, A=255}
PlayerMapMarker.SnapLineOpacity = 0.9

PlayerMapMarker.SkeletonThickness = 0.8
PlayerMapMarker.SkeletonColor = nil
PlayerMapMarker.SkeletonOpacity = 0.8
PlayerMapMarker.SkeletonMaxDistance = 100000
PlayerMapMarker.bUseVisibilityColor = true
PlayerMapMarker.SkeletonVisibleColor = FLinearColor_ESP9 and FLinearColor_ESP9(1.0, 0.85, 0.0, 0.8) or {R=255,G=217,B=0,A=200}
PlayerMapMarker.SkeletonCoverColor = FLinearColor_ESP9 and FLinearColor_ESP9(0.9, 0.0, 0.0, 0.6) or {R=230,G=0,B=0,A=150}
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
PlayerMapMarker._LightUpdateInterval = 0.02
PlayerMapMarker._bDistanceUpdateScheduled = false
PlayerMapMarker._DistanceUpdateInterval = 0.1
PlayerMapMarker._bScreenMarkConfigSetup = false

local function IsValid_ESP9(obj)
    if obj == nil then return false end
    if slua and slua.isValid then return slua.isValid(obj) end
    return obj ~= nil
end

function PlayerMapMarker.GetGameplayData()
    if PlayerMapMarker._CachedGameplayData then return PlayerMapMarker._CachedGameplayData end
    local ok, GDP = pcall(function() return require("GameLua.GameCore.Data.GameplayData") end)
    if ok and GDP then PlayerMapMarker._CachedGameplayData = GDP return GDP end
    return nil
end

function PlayerMapMarker.GetMyPlayerController()
    local PC = PlayerMapMarker._CachedPC
    if PC and IsValid_ESP9(PC) then return PC end
    local GDP = PlayerMapMarker.GetGameplayData()
    if not GDP then return nil end
    pcall(function() PC = GDP.GetPlayerController and GDP.GetPlayerController() end)
    if PC and IsValid_ESP9(PC) then PlayerMapMarker._CachedPC = PC return PC end
    return nil
end

function PlayerMapMarker.GetCGameState()
    if CGameState and IsValid_ESP9(CGameState) then return CGameState end
    if PlayerMapMarker._CachedCGameState and IsValid_ESP9(PlayerMapMarker._CachedCGameState) then return PlayerMapMarker._CachedCGameState end
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
    if not IsValid_ESP9(PC) then return nil end
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
    if not IsValid_ESP9(Character) then return nil end
    local Loc = nil
    pcall(function() if Character.K2_GetActorLocation then Loc = Character:K2_GetActorLocation() end end)
    if not Loc then pcall(function() if Game and Game.GetActorLocation then Loc = Game:GetActorLocation(Character) end end) end
    return Loc
end

function PlayerMapMarker.CalcDistance(Loc1, Loc2)
    if not Loc1 or not Loc2 then return nil end
    local Dist = nil
    pcall(function() if FVector_ESP9 and FVector_ESP9.Dist2D then Dist = FVector_ESP9.Dist2D(Loc1, Loc2) end end)
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
    if not IsValid_ESP9(MyChar) then return nil end
    return PlayerMapMarker.GetCharacterLocation(MyChar)
end

function PlayerMapMarker.GetPlayerName(Character)
    if not IsValid_ESP9(Character) then return "Unknown" end
    local Name = nil
    pcall(function() if Character.GetPlayerNameSafety then Name = Character:GetPlayerNameSafety() end end)
    if not Name then
        pcall(function()
            local PS = nil
            if Character.GetPlayerStateSafety then PS = Character:GetPlayerStateSafety()
            elseif Character.GetPlayerState then PS = Character:GetPlayerState() end
            if IsValid_ESP9(PS) and PS.GetPlayerName then Name = PS:GetPlayerName() end
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

function PlayerMapMarker.GetTeamID(Character)
    if not IsValid_ESP9(Character) then return nil end
    local TeamID = nil
    pcall(function() if Character.GetTeamID then TeamID = Character:GetTeamID() end end)
    if not TeamID then
        pcall(function()
            local PS = nil
            if Character.GetPlayerStateSafety then PS = Character:GetPlayerStateSafety()
            elseif Character.GetPlayerState then PS = Character:GetPlayerState() end
            if IsValid_ESP9(PS) and PS.GetTeamID then TeamID = PS:GetTeamID()
            elseif IsValid_ESP9(PS) and PS.TeamID then TeamID = PS.TeamID end
        end)
    end
    if not TeamID then pcall(function() if Character.TeamID then TeamID = Character.TeamID end end) end
    return TeamID
end

function PlayerMapMarker.GetTeamColor(TeamID)
    if TeamID == nil or TeamID == 0 then
        return FLinearColor_ESP9 and FLinearColor_ESP9(0.2, 0.4, 1.0, 1.0) or {R=50,G=100,B=255,A=255}
    end
    local TeamColors = {
        [1]={R=255,G=50,B=50,A=255,fR=1.0,fG=0.2,fB=0.2},
        [2]={R=50,G=255,B=50,A=255,fR=0.2,fG=1.0,fB=0.2},
        [3]={R=50,G=100,B=255,A=255,fR=0.2,fG=0.4,fB=1.0},
        [4]={R=255,G=255,B=50,A=255,fR=1.0,fG=1.0,fB=0.2},
        [5]={R=255,G=50,B=255,A=255,fR=1.0,fG=0.2,fB=1.0},
        [6]={R=50,G=255,B=255,A=255,fR=0.2,fG=1.0,fB=1.0},
        [7]={R=255,G=150,B=50,A=255,fR=1.0,fG=0.6,fB=0.2},
        [8]={R=150,G=50,B=255,A=255,fR=0.6,fG=0.2,fB=1.0},
        [9]={R=200,G=255,B=50,A=255,fR=0.8,fG=1.0,fB=0.2},
        [10]={R=50,G=150,B=255,A=255,fR=0.2,fG=0.6,fB=1.0},
        [11]={R=255,G=100,B=150,A=255,fR=1.0,fG=0.4,fB=0.6},
        [12]={R=100,G=255,B=150,A=255,fR=0.4,fG=1.0,fB=0.6},
        [13]={R=150,G=150,B=50,A=255,fR=0.6,fG=0.6,fB=0.2},
        [14]={R=50,G=200,B=150,A=255,fR=0.2,fG=0.8,fB=0.6},
        [15]={R=255,G=200,B=50,A=255,fR=1.0,fG=0.8,fB=0.2}
    }
    local colorIndex = (TeamID % 15)
    if colorIndex == 0 then colorIndex = 15 end
    local c = TeamColors[colorIndex]
    return FLinearColor_ESP9 and FLinearColor_ESP9(c.fR, c.fG, c.fB, 1.0) or {R=c.R, G=c.G, B=c.B, A=c.A}
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
    return true
end

function PlayerMapMarker.GetESPLocation(Character)
    if not IsValid_ESP9(Character) then return nil end
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
    if not IsValid_ESP9(Character) then return nil end
    local WeaponID, WeaponName, WeaponIconPath, WeaponIconTexture, CurrentWeapon = nil, nil, nil, nil, nil
    pcall(function() if Character.GetCurrentWeapon then CurrentWeapon = Character:GetCurrentWeapon() end end)
    if not CurrentWeapon then pcall(function() CurrentWeapon = Character.CurrentWeapon end) end
    if not CurrentWeapon then pcall(function() if Character.GetWeaponManager then local WM = Character:GetWeaponManager() if WM and WM.GetCurrentWeapon then CurrentWeapon = WM:GetCurrentWeapon() end end end) end
    if CurrentWeapon and IsValid_ESP9(CurrentWeapon) then
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
            if PS and IsValid_ESP9(PS) then
                if PS.GetCurrentWeaponID then WeaponID = PS:GetCurrentWeaponID() end
                if not WeaponID and PS.CurWeaponID then WeaponID = PS.CurWeaponID end
            end
        end)
    end
    return { WeaponID = WeaponID, WeaponName = WeaponName, WeaponIconPath = WeaponIconPath, WeaponIconTexture = WeaponIconTexture, CurrentWeapon = CurrentWeapon }
end

PlayerMapMarker._OBHeadWidgetClass = nil
PlayerMapMarker._OBHeadWidgetLoadFailed = false

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
    end

    local Widget = nil
    pcall(function()
        local STExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")
        local PC = PlayerMapMarker.GetMyPlayerController()
        local OuterObj = IsValid_ESP9(PC) and PC.Object or PlayerMapMarker.ESPCanvas
        Widget = STExtraBlueprintFunctionLibrary.CreateWidgetByClass(PlayerMapMarker._OBHeadWidgetClass, OuterObj)
    end)
    if not Widget then return nil end

    pcall(function() Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
    pcall(function() Widget:SetRenderOpacity(1.0) end)

    -- Premium styling: apply yellow & red theme to the ESP widget
    local FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")
    local premiumYellow = FLinearColor_ESP9 and FLinearColor_ESP9(1.0, 0.85, 0.0, 1.0) or {R=1,G=0.85,B=0,A=1}
    local premiumRedGlow = FLinearColor_ESP9 and FLinearColor_ESP9(1.0, 1.0, 1.0, 0.6) or {R=1,G=1,B=1,A=0.6}

    -- Try to style the widget background and border with premium red glow
    pcall(function()
        if Widget.SetBrushColor then Widget:SetBrushColor(FLinearColor_ESP9 and FLinearColor_ESP9(0.05, 0.02, 0.0, 0.85) or {R=0.05,G=0.02,B=0,A=0.85}) end
        if Widget.SetBrushColor then Widget:SetBrushColor(premiumRedGlow) end
    end)

    -- Try to apply render opacity and render scale for a premium look
    pcall(function() Widget:SetRenderOpacity(1.0) end)

    local NameText = nil
    local HealthFill = nil
    pcall(function()
        NameText = Widget.TextBlock_TeamName
        if NameText and slua.isValid(NameText) then pcall(function() NameText:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end) end
        if Widget.TextBlock_PlayerName and slua.isValid(Widget.TextBlock_PlayerName) then pcall(function() Widget.TextBlock_PlayerName:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end) end
        local SizeBox_HP = Widget.SizeBox_HP
        if SizeBox_HP and slua.isValid(SizeBox_HP) then
            pcall(function() SizeBox_HP:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
            local ExistingChild = nil
            pcall(function() if SizeBox_HP.GetContent then ExistingChild = SizeBox_HP:GetContent() end end)
            if ExistingChild and slua.isValid(ExistingChild) then
                local FoundPB = PlayerMapMarker.FindProgressBarInWidget(ExistingChild, 0, 5)
                if FoundPB and slua.isValid(FoundPB) then HealthFill = FoundPB end
            end
        end
    end)

    local WidgetData = {
        Container = Widget,
        NameText = NameText,
        HealthFill = HealthFill,
        IsGameWidget = true,
        HasChildren = (NameText ~= nil)
    }
    return WidgetData
end

function PlayerMapMarker.FindProgressBarInWidget(WidgetObj, Depth, MaxDepth)
    if not WidgetObj or not slua.isValid(WidgetObj) then return nil end
    Depth = Depth or 0
    MaxDepth = MaxDepth or 5
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

function PlayerMapMarker.ApplyTeamColor(Widget, TeamID)
    if not Widget or not Widget.Container then return end
    if not _G.Mod_ESP_ShowTeamColor then return end
    local color = PlayerMapMarker.GetTeamColor(TeamID)
    if not color then return end
    pcall(function()
        local W = Widget.Container
        if not W or not slua.isValid(W) then return end
        if W.SetTeamColor then pcall(function() W:SetTeamColor(TeamID) end) end
    end)
end

function PlayerMapMarker.UpdateESPText(Widget, Text)
    if not Widget then return end
    if Widget._LastESPText == Text then return end
    Widget._LastESPText = Text

    -- Premium yellow text color for ESP names
    local FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")
    local premiumYellow = FLinearColor_ESP9 and FLinearColor_ESP9(1.0, 0.0, 0.0, 1.0) or {R=255,G=0,B=0,A=255}


    local function applyText(w, txt)
        if not w or not slua.isValid(w) then return end
        if txt == "" then
            pcall(function() w:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
            return
        else
            pcall(function() w:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
        end
        pcall(function() w:SetText(txt) end)
        -- Apply premium yellow text color
        pcall(function()
            if FSlateColor then w:SetColorAndOpacity(FSlateColor(premiumYellow))
            else w:SetColorAndOpacity(premiumYellow) end
        end)
    end

    if Widget.NameText and slua.isValid(Widget.NameText) then applyText(Widget.NameText, Text) end
    if Widget.IsGameWidget and Widget.Container then
        pcall(function()
            local W = Widget.Container
            if W and slua.isValid(W) then
                applyText(W.TextBlock_TeamName, Text)
                applyText(W.TextBlock_PlayerName, Text)
            end
        end)
    end
end

function PlayerMapMarker.UpdateESPHealth(Widget, pct)
    if not Widget then return end
    Widget.LastPct = pct
    local bShowHP = _G.Mod_ESP_ShowHealthBar
    if not bShowHP then return end

    if PlayerMapMarker.bForceSwitcherIndexEveryUpdate and Widget.Container then
        pcall(function()
            local W = Widget.Container
            if W and slua.isValid(W) then
                if W.WidgetSwitcher_Type and slua.isValid(W.WidgetSwitcher_Type) then pcall(function() if W.WidgetSwitcher_Type.SetActiveWidgetIndex then W.WidgetSwitcher_Type:SetActiveWidgetIndex(PlayerMapMarker.HPWidgetSwitcherTypeIndex) end end) end
                if W.WidgetSwitcher_Type2 and slua.isValid(W.WidgetSwitcher_Type2) then pcall(function() if W.WidgetSwitcher_Type2.SetActiveWidgetIndex then W.WidgetSwitcher_Type2:SetActiveWidgetIndex(PlayerMapMarker.HPWidgetSwitcherType2Index) end end) end
            end
        end)
    end

    if Widget.HealthFill then
        local bValid = false
        pcall(function() bValid = slua.isValid(Widget.HealthFill) end)
        if bValid then
            pcall(function()
                if Widget.HealthFill.SetPercent then
                    Widget.HealthFill:SetPercent(pct)
                    local color
                    color = FLinearColor_ESP9 and FLinearColor_ESP9(0.0, 1.0, 0.0, 1.0) or {R=0,G=255,B=0,A=255}
if Widget.HealthFill.SetFillColorAndOpacity then Widget.HealthFill:SetFillColorAndOpacity(color) end

                    if Widget.HealthFill.SetFillColorAndOpacity then Widget.HealthFill:SetFillColorAndOpacity(color) end
                end
            end)
        end
    end
end

function PlayerMapMarker.UpdateESPPositionWithPC(Widget, WorldLoc, PC, CanvasPos)
    if not Widget or not IsValid_ESP9(PC) then return false end

    local Container = Widget.Container or Widget
    local bOnScreen = true

    if not CanvasPos then
        if not WorldLoc then return false end
        bOnScreen, CanvasPos = PlayerMapMarker.ProjectWorldToCanvasLocal(PC, WorldLoc)
    end

    if not bOnScreen then pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end) return false end

    pcall(function()
        local bShowAnyUI = _G.Mod_ESP_ShowName or _G.Mod_ESP_ShowDistance or _G.Mod_ESP_ShowHealthBar or _G.Mod_ESP_ShowTeamColor or _G.Mod_ESP_ShowWeaponIcon
        if bShowAnyUI then Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        else Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end

        if PlayerMapMarker.ESPCanvas and Game:IsValid(PlayerMapMarker.ESPCanvas) then
            local ptr = tostring(Container)
            local Slot = PlayerMapMarker.ESPWidgetPtrs[ptr]
            if not Slot or not slua.isValid(Slot) then
                local addedSlot = PlayerMapMarker.ESPCanvas:AddChildToCanvas(Container)
                if addedSlot and slua.isValid(addedSlot) then
                    Slot = addedSlot
                    PlayerMapMarker.ESPWidgetPtrs[ptr] = addedSlot
                    pcall(function() Slot:SetAutoSize(true) end)
                    pcall(function() Slot:SetAlignment(FVector2D_ESP9 and FVector2D_ESP9(0.5, 1.0) or {X=0.5, Y=1.0}) end)
                    pcall(function() Slot:SetZOrder(PlayerMapMarker.ESPWidgetZOrder or 20) end)
                end
            end
            if Slot and slua.isValid(Slot) then
                local finalX = CanvasPos.X + (PlayerMapMarker.ESPAnchorOffsetX or 0)
                local finalY = CanvasPos.Y + (PlayerMapMarker.ESPAnchorOffsetY or 0)
                if not Widget._CachedPosVec then Widget._CachedPosVec = FVector2D_ESP9 and FVector2D_ESP9(finalX, finalY) or {X=finalX, Y=finalY}
                else Widget._CachedPosVec.X = finalX; Widget._CachedPosVec.Y = finalY end
                pcall(function() Slot:SetPosition(Widget._CachedPosVec) end)
            end
        end
    end)
    return true
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
                local pt0 = SBL.AbsoluteToLocal(cg, FVector2D_ESP9 and FVector2D_ESP9(0, 0) or {X=0, Y=0})
                local pt1 = SBL.AbsoluteToLocal(cg, FVector2D_ESP9 and FVector2D_ESP9(100, 100) or {X=100, Y=100})
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
        local scale = 1.0
        if WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportScale then scale = WidgetLayoutLibrary.GetViewportScale(PC) or 1.0 end
        PlayerMapMarker._CanvasScaleX = 1.0 / scale
        PlayerMapMarker._CanvasScaleY = 1.0 / scale
        PlayerMapMarker._CanvasOffsetX = 0
        PlayerMapMarker._CanvasOffsetY = 0
    end
end

function PlayerMapMarker.ScreenPixelToCanvasLocal(PC, ScreenPixelPos)
    if not ScreenPixelPos then return FVector2D_ESP9 and FVector2D_ESP9(0, 0) or {X=0, Y=0} end
    local scaleX = PlayerMapMarker._CanvasScaleX or 1.0
    local scaleY = PlayerMapMarker._CanvasScaleY or 1.0
    local offsetX = PlayerMapMarker._CanvasOffsetX or 0
    local offsetY = PlayerMapMarker._CanvasOffsetY or 0
    return (FVector2D_ESP9 and FVector2D_ESP9(ScreenPixelPos.X * scaleX + offsetX, ScreenPixelPos.Y * scaleY + offsetY)) or {X = ScreenPixelPos.X * scaleX + offsetX, Y = ScreenPixelPos.Y * scaleY + offsetY}
end

function PlayerMapMarker.ProjectWorldToCanvasLocal(PC, WorldLoc)
    if not IsValid_ESP9(PC) or not WorldLoc then return false, (FVector2D_ESP9 and FVector2D_ESP9(0, 0) or {X=0, Y=0}) end

    local ScreenPixelPos = FVector2D_ESP9 and FVector2D_ESP9(0, 0) or {X=0, Y=0}
    local bOK = false
    pcall(function()
        local res = PC:ProjectWorldLocationToScreen(WorldLoc, ScreenPixelPos, true)
        if res == true or res == 1 or (ScreenPixelPos and (ScreenPixelPos.X ~= 0 or ScreenPixelPos.Y ~= 0)) then bOK = true end
    end)

    if not bOK or not ScreenPixelPos or (ScreenPixelPos.X == 0 and ScreenPixelPos.Y == 0) then return false, (FVector2D_ESP9 and FVector2D_ESP9(0, 0) or {X=0, Y=0}) end

    local CanvasLocalPos = PlayerMapMarker.ScreenPixelToCanvasLocal(PC, ScreenPixelPos)
    return true, CanvasLocalPos
end

function PlayerMapMarker.GetSnapLineStartPos(PC)
    local screenPixelW, screenPixelH = 0, 0
    local scale = 1.0

    pcall(function()
        if PC and PC.GetViewportSize then
            local vs = FVector2D_ESP9 and FVector2D_ESP9(0, 0) or {X=0,Y=0}
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

    if not PlayerMapMarker._CachedTopCenterPixel then PlayerMapMarker._CachedTopCenterPixel = FVector2D_ESP9 and FVector2D_ESP9(0, 0) or {X=0,Y=0} end
    PlayerMapMarker._CachedTopCenterPixel.X = screenPixelW / 2.0
    PlayerMapMarker._CachedTopCenterPixel.Y = (PlayerMapMarker.SnapLineOriginY or 50) * scale

    local fromCanvasPos = PlayerMapMarker.ScreenPixelToCanvasLocal(PC, PlayerMapMarker._CachedTopCenterPixel)
    return fromCanvasPos.X + (PlayerMapMarker.SnapLineOriginOffsetX or 0), fromCanvasPos.Y
end

function PlayerMapMarker.GetSnapLineStartPos(PC)
    local screenPixelW, screenPixelH = 0, 0
    local scale = 1.0

    pcall(function()
        if PC and PC.GetViewportSize then
            local vs = FVector2D_ESP9 and FVector2D_ESP9(0, 0) or {X=0,Y=0}
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

    if not PlayerMapMarker._CachedTopCenterPixel then PlayerMapMarker._CachedTopCenterPixel = FVector2D_ESP9 and FVector2D_ESP9(0, 0) or {X=0,Y=0} end
    PlayerMapMarker._CachedTopCenterPixel.X = screenPixelW / 2.0
    PlayerMapMarker._CachedTopCenterPixel.Y = (PlayerMapMarker.SnapLineOriginY or 50) * scale

    local fromCanvasPos = PlayerMapMarker.ScreenPixelToCanvasLocal(PC, PlayerMapMarker._CachedTopCenterPixel)
    return fromCanvasPos.X + (PlayerMapMarker.SnapLineOriginOffsetX or 0), fromCanvasPos.Y
end

-- ============================================================
-- SNAPLINE CREATE — With Color Sync from Chams Visible Color
-- ============================================================
function PlayerMapMarker.CreateSnapLine()
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return nil end

    -- Premium 2-layer snapline: glow + core
    local layerDefs = {
        -- Layer 1: Glow (wider, behind)
        {r = 0.9, g = 0.05, b = 0.0, a = 0.35, thick = 2.5, z = 0},
        -- Layer 2: Bright core (sharp, front)
        {r = 1.0, g = 0.85, b = 0.0, a = 0.9, thick = 1.0, z = 1},
    }

    -- ===== Snapline color sync with Chams visible color =====
    if _G.SnapLineCustomColor then
        layerDefs[1].r = _G.SnapLineCustomColor.R
        layerDefs[1].g = _G.SnapLineCustomColor.G
        layerDefs[1].b = _G.SnapLineCustomColor.B
        layerDefs[1].a = 0.4
        layerDefs[2].r = _G.SnapLineCustomColor.R
        layerDefs[2].g = _G.SnapLineCustomColor.G
        layerDefs[2].b = _G.SnapLineCustomColor.B
        layerDefs[2].a = 1.0
    end

    local Layers = {}
    for _, ld in ipairs(layerDefs) do
        local Border = nil
        pcall(function() Border = CGame:NewObjectFromPath("/Script/UMG.Border", PlayerMapMarker.ESPCanvas) end)
        if Border and slua.isValid(Border) then
            local lc = FLinearColor_ESP9 and FLinearColor_ESP9(ld.r, ld.g, ld.b, ld.a) or {R=ld.r,G=ld.g,B=ld.b,A=ld.a}
            pcall(function() Border:SetBrushColor(lc) end)
            pcall(function() Border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
            pcall(function() Border.RenderTransformPivot = FVector2D_ESP9 and FVector2D_ESP9(0.0, 0.5) or {X=0,Y=0.5} end)
            pcall(function() Border:SetRenderTransformPivot(FVector2D_ESP9 and FVector2D_ESP9(0.0, 0.5) or {X=0,Y=0.5}) end)

            local Slot = nil
            pcall(function()
                Slot = PlayerMapMarker.ESPCanvas:AddChildToCanvas(Border)
                if Slot then Slot:SetAutoSize(false) Slot:SetZOrder(ld.z) end
            end)
            if Slot then
                table.insert(Layers, { Widget = Border, Slot = Slot, Thick = ld.thick })
            end
        end
    end

    if #Layers == 0 then return nil end

    -- Return composite structure; .Widget and .Slot point to the core (front) layer for compatibility
    local coreLayer = Layers[2] or Layers[1]
    return {
        Widget = coreLayer.Widget,
        Slot = coreLayer.Slot,
        Layers = Layers,
        _CachedPosVec = nil,
        _CachedSizeVec = nil,
    }
end

function PlayerMapMarker.UpdateSnapLine(KeyStr, CanvasPos, bOnScreen, fromX, fromY)
    if not PlayerMapMarker.bUseSnapLines then return end
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return end

    local LineData = PlayerMapMarker.SnapLineWidgets[KeyStr]
    -- Validate: if multi-layer, check all layers; if single, check the one
    local function IsLineDataValid(ld)
        if not ld or not ld.Widget or not slua.isValid(ld.Widget) or not ld.Slot then return false end
        if ld.Layers then
            for _, layer in ipairs(ld.Layers) do
                if not layer.Widget or not slua.isValid(layer.Widget) or not layer.Slot then return false end
            end
        end
        return true
    end
    
    if LineData and not IsLineDataValid(LineData) then
        PlayerMapMarker.RemoveSnapLine(KeyStr)
        LineData = nil
    end
    
    if not bOnScreen or not CanvasPos then
        if LineData then
            if LineData.Layers then
                for _, layer in ipairs(LineData.Layers) do
                    if layer.Widget and slua.isValid(layer.Widget) then
                        pcall(function() layer.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                    end
                end
            elseif LineData.Widget and slua.isValid(LineData.Widget) then
                pcall(function() LineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
            end
        end
        return
    end

    if not LineData then
        LineData = PlayerMapMarker.CreateSnapLine()
        if not LineData or not LineData.Widget or not LineData.Slot then return end
        PlayerMapMarker.SnapLineWidgets[KeyStr] = LineData
    end

    local toX = CanvasPos.X + (PlayerMapMarker.SnapLineHeadOffsetX or 0)
    local toY = CanvasPos.Y + (PlayerMapMarker.SnapLineHeadOffsetY or 0)

    local dx = toX - fromX
    local dy = toY - fromY
    local length = math.sqrt(dx * dx + dy * dy)
    local baseThick = PlayerMapMarker.SnapLineThickness or 3.0
    local angle_rad = 0
    if math.atan2 then angle_rad = math.atan2(dy, dx) else angle_rad = math.atan(dy, dx) end
    local angle = angle_rad * (180.0 / math.pi)

    local FLinearColor_ESP9 = _G.FLinearColor or import("LinearColor")

    -- Update all layers with their respective thickness multipliers and INSTANT COLOR
    if LineData.Layers then
        for i, layer in ipairs(LineData.Layers) do
            local lt = baseThick * (layer.Thick or 1.0)
            local lY = fromY - lt / 2.0
            pcall(function() layer.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)

            -- ========================================================
            -- INSTANT COLOR SYNC: Color change hote hi instantly apply
            -- ========================================================
            if _G.SnapLineCustomColor then
                local alpha = (i == 1) and 0.35 or 0.9 -- Layer 1 is Glow, Layer 2 is Core
                local lc = FLinearColor_ESP9 and FLinearColor_ESP9(_G.SnapLineCustomColor.R, _G.SnapLineCustomColor.G, _G.SnapLineCustomColor.B, alpha) or {R=_G.SnapLineCustomColor.R, G=_G.SnapLineCustomColor.G, B=_G.SnapLineCustomColor.B, A=alpha}
                pcall(function() layer.Widget:SetBrushColor(lc) end)
            end
            -- ========================================================

            if not layer._posVec then
                layer._posVec = FVector2D_ESP9 and FVector2D_ESP9(fromX, lY) or {X=fromX, Y=lY}
                layer._sizeVec = FVector2D_ESP9 and FVector2D_ESP9(length, lt) or {X=length, Y=lt}
            else
                layer._posVec.X = fromX; layer._posVec.Y = lY
                layer._sizeVec.X = length; layer._sizeVec.Y = lt
            end
            pcall(function()
                layer.Slot:SetPosition(layer._posVec)
                layer.Slot:SetSize(layer._sizeVec)
            end)
            pcall(function() layer.Widget:SetRenderAngle(angle) end)
        end
    else
        -- Fallback: single-layer (legacy path)
        local Widget = LineData.Widget
        local Slot = LineData.Slot
        pcall(function() Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)

        -- ========================================================
        -- INSTANT COLOR SYNC (For Single Layer)
        -- ========================================================
        if _G.SnapLineCustomColor then
            pcall(function() Widget:SetBrushColor(_G.SnapLineCustomColor) end)
        end
        -- ========================================================

        if not LineData._CachedPosVec then
            LineData._CachedPosVec = FVector2D_ESP9 and FVector2D_ESP9(fromX, fromY - baseThick / 2.0) or {X=fromX, Y=fromY - baseThick / 2.0}
            LineData._CachedSizeVec = FVector2D_ESP9 and FVector2D_ESP9(length, baseThick) or {X=length, Y=baseThick}
        else
            LineData._CachedPosVec.X = fromX; LineData._CachedPosVec.Y = fromY - baseThick / 2.0
            LineData._CachedSizeVec.X = length; LineData._CachedSizeVec.Y = baseThick
        end
        pcall(function()
            Slot:SetPosition(LineData._CachedPosVec)
            Slot:SetSize(LineData._CachedSizeVec)
        end)
        pcall(function() Widget:SetRenderAngle(angle) end)
    end
end


function PlayerMapMarker.RemoveSnapLine(KeyStr)
    local LineData = PlayerMapMarker.SnapLineWidgets[KeyStr]
    if LineData then
        -- Multi-layer: destroy all layer widgets
        if LineData.Layers then
            for _, layer in ipairs(LineData.Layers) do
                if layer.Widget and slua.isValid(layer.Widget) then
                    pcall(function() layer.Widget:RemoveFromParent() layer.Widget:ConditionalBeginDestroy() end)
                end
            end
        elseif LineData.Widget and slua.isValid(LineData.Widget) then
            pcall(function() LineData.Widget:RemoveFromParent() LineData.Widget:ConditionalBeginDestroy() end)
        end
    end
    -- Always clear the record, including invalid/stale widget handles.
    PlayerMapMarker.SnapLineWidgets[KeyStr] = nil
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

function PlayerMapMarker.ClearAllSnapLines()
    for KeyStr, LineData in pairs(PlayerMapMarker.SnapLineWidgets) do
        if LineData then
            if LineData.Layers then
                for _, layer in ipairs(LineData.Layers) do
                    if layer.Widget and slua.isValid(layer.Widget) then
                        pcall(function() layer.Widget:RemoveFromParent() layer.Widget:ConditionalBeginDestroy() end)
                    end
                end
            elseif LineData.Widget and slua.isValid(LineData.Widget) then
                pcall(function() LineData.Widget:RemoveFromParent() LineData.Widget:ConditionalBeginDestroy() end)
            end
        end
    end
    PlayerMapMarker.SnapLineWidgets = {}
end

-- ============================================================
function PlayerMapMarker.ScreenPixelToCanvasLocalRaw(PC, screenX, screenY)
    local scaleX = PlayerMapMarker._CanvasScaleX or 1.0
    local scaleY = PlayerMapMarker._CanvasScaleY or 1.0
    local offsetX = PlayerMapMarker._CanvasOffsetX or 0
    local offsetY = PlayerMapMarker._CanvasOffsetY or 0
    return screenX * scaleX + offsetX, screenY * scaleY + offsetY
end

function PlayerMapMarker.ProjectWorldToCanvasLocalRaw(PC, WorldLoc)
    if not IsValid_ESP9(PC) or not WorldLoc then return false, 0, 0 end

    if not PlayerMapMarker._tempScreenPixelPos then
        PlayerMapMarker._tempScreenPixelPos = FVector2D_ESP9 and FVector2D_ESP9(0, 0) or {X=0, Y=0}
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
    if not IsValid_ESP9(Character) or not PrimaryBoneName then return nil end

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

function PlayerMapMarker.GetCharacterMesh(Character)
    if not IsValid_ESP9(Character) then return nil end
    local Mesh = nil
    pcall(function() if Character.Mesh and Game:IsValid(Character.Mesh) then Mesh = Character.Mesh end end)
    if not Mesh then pcall(function() local SkeletalMeshCompClass = import("/Script/Engine.SkeletalMeshComponent") Mesh = Character:GetComponentByClass(SkeletalMeshCompClass) end) end
    return Mesh
end

function PlayerMapMarker.IsPlayerVisible(PC, Character)
    if not IsValid_ESP9(PC) or not IsValid_ESP9(Character) then return false end
    local now = os.clock()
    if Character._lastVisTime and (now - Character._lastVisTime) < 0.15 then
        return Character._cachedIsVisible or false
    end
    Character._lastVisTime = now

    local bVis = false
    pcall(function()
        if PC.LineOfSightTo then
            if not PlayerMapMarker._ZeroVector then
                local VT = FVector_ESP9 or import("/Script/CoreUObject.Vector")
                if VT then PlayerMapMarker._ZeroVector = VT(0, 0, 0) end
            end
            bVis = PC:LineOfSightTo(Character, PlayerMapMarker._ZeroVector, false)
        end
    end)
    Character._cachedIsVisible = bVis
    return bVis
end

function PlayerMapMarker.CreateSkeletonLineWidget()
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return nil end

    local Border = nil
    pcall(function() Border = CGame:NewObjectFromPath("/Script/UMG.Border", PlayerMapMarker.ESPCanvas) end)
    if not Border or not slua.isValid(Border) then return nil end

    pcall(function() Border.RenderTransformPivot = FVector2D_ESP9 and FVector2D_ESP9(0.0, 0.5) or {X=0, Y=0.5} end)
    pcall(function() Border:SetRenderTransformPivot(FVector2D_ESP9 and FVector2D_ESP9(0.0, 0.5) or {X=0, Y=0.5}) end)

    local Slot = nil
    pcall(function()
        Slot = PlayerMapMarker.ESPCanvas:AddChildToCanvas(Border)
        if Slot then Slot:SetAutoSize(false) Slot:SetZOrder(5) end
    end)

    return {
        Widget = Border, Slot = Slot,
        posVec = FVector2D_ESP9 and FVector2D_ESP9(0, 0) or {X=0, Y=0},
        sizeVec = FVector2D_ESP9 and FVector2D_ESP9(0, 0) or {X=0, Y=0},
        lastFromX = -99999, lastFromY = -99999,
        lastToX = -99999, lastToY = -99999
    }
end

function PlayerMapMarker.UpdateSkeletonLines(KeyStr, Character, PC, bVisible, TeamColor, bPlayerOnScreen, charLoc)
    if not PlayerMapMarker.bUseSkeleton then return end
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return end

    local PlayerBones = PlayerMapMarker.SkeletonWidgets[KeyStr]

    if not bVisible or not IsValid_ESP9(Character) or not IsValid_ESP9(PC) then
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
        if bTargetVisible then lineColor = PlayerMapMarker.SkeletonVisibleColor or FLinearColor_ESP9(1.0, 0.85, 0.0, 0.8)
        else lineColor = PlayerMapMarker.SkeletonCoverColor or FLinearColor_ESP9(0.9, 0.0, 0.0, 0.6) end
    else
        lineColor = PlayerMapMarker.SkeletonColor or TeamColor or FLinearColor_ESP9(1.0, 1.0, 1.0, PlayerMapMarker.SkeletonOpacity or 0.8)
    end

    local cache = PlayerMapMarker._StaticBoneLocCache
    for k in pairs(cache) do cache[k] = nil end

    local lineIndex = 0
    local thickness = PlayerMapMarker.SkeletonThickness or 1.2

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
                        pVec.X = fromX; pVec.Y = fromY - thickness / 2.0
                        Slot:SetPosition(pVec)

                        local sVec = LineData.sizeVec
                        sVec.X = length; sVec.Y = thickness
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

function PlayerMapMarker.ClearAllESP()
    RedBoxOverlay.Stop()
    for KeyStr, Data in pairs(PlayerMapMarker.ESPWidgets) do
        PlayerMapMarker.RemoveESPWidget(Data.Widget, KeyStr)
    end
    PlayerMapMarker.ESPWidgets = {}
    PlayerMapMarker.ESPWidgetPtrs = {}
    PlayerMapMarker.ClearAllSnapLines()
    PlayerMapMarker.ClearAllSkeletonLines()
    PlayerMapMarker.ESPCanvas = nil
    PlayerMapMarker._OBHeadWidgetClass = nil
    PlayerMapMarker._OBHeadWidgetLoadFailed = false
    PlayerMapMarker._cachedViewportW = 1920
    PlayerMapMarker._cachedViewportH = 1080
end

function PlayerMapMarker.UpdateESP(AllPlayers, MyLoc)
    if not PlayerMapMarker.bUseScreenESP then return end

    PlayerMapMarker.bUseSnapLines = _G.Mod_ESP_ShowSnapline
    PlayerMapMarker.bUseSkeleton = false

    if not PlayerMapMarker.InitESPCanvas() then return end
    if PlayerMapMarker._OBHeadWidgetLoadFailed then return end

    local PC = PlayerMapMarker.GetMyPlayerController()
    if IsValid_ESP9(PC) then PlayerMapMarker.UpdateCanvasTransform(PC) end

    local fromX, fromY = 0, 0
    if PlayerMapMarker.bUseSnapLines and IsValid_ESP9(PC) then
        fromX, fromY = PlayerMapMarker.GetSnapLineStartPos(PC)
    end

    local MyKey = PlayerMapMarker.GetMyPlayerKey()
    local SeenKeys = {}
    local MyChar = nil
    pcall(function()
        local GDP = PlayerMapMarker.GetGameplayData()
        if GDP and GDP.GetLocalCharacter then MyChar = GDP.GetLocalCharacter()
        else if PC and PC.GetPawn then MyChar = PC:GetPawn() end end
    end)

    local MyTeamID = PlayerMapMarker.GetTeamID(MyChar)

    for PlayerKey, Character in pairs(AllPlayers) do
        if IsValid_ESP9(Character) then
            local bIsMe = PlayerMapMarker.IsMe(Character, PlayerKey, MyKey)
            local bIsAI = PlayerMapMarker.IsAI(Character)
            local KeyStr = tostring(PlayerKey)
            local Name = PlayerMapMarker.GetPlayerName(Character)
            local Loc = PlayerMapMarker.GetESPLocation(Character)
            local DistStr = ""
            if MyLoc and Loc then DistStr = PlayerMapMarker.GetDistanceString(MyLoc, Loc) end

            local bSkip = false
            if bIsMe and not PlayerMapMarker.bIncludeMe then bSkip = true end
            if bIsAI and not PlayerMapMarker.bIncludeAI then bSkip = true end

            local TeamID = PlayerMapMarker.GetTeamID(Character)
            if MyTeamID ~= nil and TeamID == MyTeamID and not bIsMe then bSkip = true end

            local bIsAlive = PlayerMapMarker.IsAlive(Character)

            if not bSkip and Loc then
                SeenKeys[KeyStr] = true
                local ESPData = PlayerMapMarker.ESPWidgets[KeyStr]

                local Text = ""
                if _G.Mod_ESP_ShowName then Text = Name end
                if _G.Mod_ESP_ShowDistance and DistStr ~= "" then
                    if Text ~= "" then Text = string.format("%s [%s]", Text, DistStr) else Text = string.format("[%s]", DistStr) end
                end

                local bOnScreen, CanvasPos = PlayerMapMarker.ProjectWorldToCanvasLocal(PC, Loc)

                if not ESPData then
                    local Widget = PlayerMapMarker.CreateESPWidget()
                    if Widget then
                        PlayerMapMarker.ESPWidgets[KeyStr] = { Widget = Widget, Character = Character, Name = Name, LastDistStr = DistStr, TeamID = TeamID }
                        PlayerMapMarker.UpdateESPText(Widget, Text)
                        if bIsAlive then
                            PlayerMapMarker.UpdateESPPositionWithPC(Widget, Loc, PC, CanvasPos)
                            PlayerMapMarker.ApplyTeamColor(Widget, TeamID)
                            local HP = Character.Health or 0
                            local MaxHP = Character.MaxHealth or 120
                            local pct = 0
                            if HP > 0 and MaxHP > 0 then pct = HP / MaxHP; if pct > 1 then pct = 1 end; if pct < 0 then pct = 0 end end
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
                    ESPData.TeamID = TeamID
                    PlayerMapMarker.ApplyTeamColor(ESPData.Widget, TeamID)
                    ESPData.Widget._LastESPText = nil
                    PlayerMapMarker.UpdateESPText(ESPData.Widget, Text)
                    PlayerMapMarker.UpdateESPPositionWithPC(ESPData.Widget, Loc, PC, CanvasPos)

                    local HP = Character.Health or 0
                    local MaxHP = Character.MaxHealth or 120
                    local pct = 0
                    if HP > 0 and MaxHP > 0 then pct = HP / MaxHP; if pct > 1 then pct = 1 end; if pct < 0 then pct = 0 end end
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
    -- Remove any line whose target record no longer exists; this prevents stale left-side flicker.
    for KeyStr in pairs(PlayerMapMarker.SnapLineWidgets) do
        if not PlayerMapMarker.ESPWidgets[KeyStr] then PlayerMapMarker.RemoveSnapLine(KeyStr) end
    end
end

function PlayerMapMarker.UpdateESPLight()
    if RedBoxOverlay and RedBoxOverlay.bActive then RedBoxOverlay.UpdatePosition() end
    if not PlayerMapMarker.bUseScreenESP then return end

    PlayerMapMarker.bUseSnapLines = _G.Mod_ESP_ShowSnapline
    PlayerMapMarker.bUseSkeleton = false

    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return end

    local PC = PlayerMapMarker.GetMyPlayerController()
    if not IsValid_ESP9(PC) then return end

    PlayerMapMarker.UpdateCanvasTransform(PC)

    local fromX, fromY = 0, 0
    if PlayerMapMarker.bUseSnapLines then fromX, fromY = PlayerMapMarker.GetSnapLineStartPos(PC) end

    for KeyStr, ESPData in pairs(PlayerMapMarker.ESPWidgets) do
        local Widget = ESPData.Widget
        local Character = ESPData.Character
        local Container = Widget and (Widget.Container or Widget)
        local bWidgetValid = false
        pcall(function() bWidgetValid = Container and slua.isValid(Container) end)

        if Widget and bWidgetValid and Character and IsValid_ESP9(Character) then
            local bIsAlive = PlayerMapMarker.IsAlive(Character)
            if not bIsAlive then
                pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                PlayerMapMarker.RemoveSnapLine(KeyStr)
                PlayerMapMarker.RemoveSkeletonLines(KeyStr)
                    else
                local bShowAnyUI = _G.Mod_ESP_ShowName or _G.Mod_ESP_ShowDistance or _G.Mod_ESP_ShowHealthBar or _G.Mod_ESP_ShowTeamColor or _G.Mod_ESP_ShowWeaponIcon
                if bShowAnyUI then
                    pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                else
                    pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
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
    if not IsValid_ESP9(PC) then return end

    PlayerMapMarker.UpdateCanvasTransform(PC)

    for KeyStr, ESPData in pairs(PlayerMapMarker.ESPWidgets) do
        local Character = ESPData.Character
        local Widget = ESPData.Widget
        local Container = Widget and (Widget.Container or Widget)
        local bWidgetValid = false
        pcall(function() bWidgetValid = Container and slua.isValid(Container) end)

        if Character and IsValid_ESP9(Character) and Widget and bWidgetValid then
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
                    if _G.Mod_ESP_ShowName then Text = Name end
                    if _G.Mod_ESP_ShowDistance and DistStr ~= "" then
                        if Text ~= "" then Text = string.format("%s [%s]", Text, DistStr) else Text = string.format("[%s]", DistStr) end
                    end

                    ESPData.LastDistStr = DistStr
                    Widget._LastESPText = nil
                    PlayerMapMarker.UpdateESPText(Widget, Text)
                end
            end
        end
    end
end

function PlayerMapMarker.AddWeaponIconToESP(WidgetData, Character)
    if not WidgetData or not WidgetData.Container then return end
    if not _G.Mod_ESP_ShowWeaponIcon then return end

    pcall(function()
        local Container = WidgetData.Container
        if not Container or not slua.isValid(Container) then return end

        local winfo = Character and PlayerMapMarker.GetCharacterWeaponInfo(Character) or nil
        if not winfo or not winfo.WeaponID or winfo.WeaponID == 0 then return end

        if WidgetData._LastWeaponID == winfo.WeaponID and WidgetData._WeaponIconApplied then return end
        WidgetData._LastWeaponID = winfo.WeaponID
        WidgetData._WeaponIconApplied = true
    end)
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
        if IsValid_ESP9(Character) then
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

    if _G.Mod_ESP_ShowPlayerCount then
        if RedBoxOverlay.bActive then RedBoxOverlay.SetCounts(realPlayers, botPlayers)
        else RedBoxOverlay.Start() end
    else
        if RedBoxOverlay.bActive then RedBoxOverlay.Stop() end
    end

    if PlayerMapMarker.bUseScreenESP then
        PlayerMapMarker.UpdateESP(AllChars, MyLoc)
    end

    return 0
end

function PlayerMapMarker.AttachTimers()
    pcall(function()
        local pc = PlayerMapMarker.GetMyPlayerController()
        if not slua.isValid(pc) or not pc.AddGameTimer then return end

        pcall(function() pc:AddGameTimer(PlayerMapMarker.nUpdateInterval or 0.5, true, function() if PlayerMapMarker.bActive then pcall(function() PlayerMapMarker.ScanAndUpdate() end) end end) end)
        pcall(function() pc:AddGameTimer(PlayerMapMarker._LightUpdateInterval or 0.02, true, function() if PlayerMapMarker.bActive then pcall(function() PlayerMapMarker.UpdateESPLight() end) end end) end)
        pcall(function() pc:AddGameTimer(PlayerMapMarker._DistanceUpdateInterval or 0.1, true, function() if PlayerMapMarker.bActive and PlayerMapMarker.bUseScreenESP and PlayerMapMarker.bShowDistance then pcall(function() PlayerMapMarker.UpdateESPDistances() end) end end) end)
    end)
end

function PlayerMapMarker.Start()
    if PlayerMapMarker.bActive then return end
    PlayerMapMarker.bActive = true
    PlayerMapMarker._FrameCount = 0
    PlayerMapMarker.ScanAndUpdate()
    PlayerMapMarker.AttachTimers()
end

function PlayerMapMarker.Stop()
    PlayerMapMarker.bActive = false
    PlayerMapMarker._FrameCount = 0
    PlayerMapMarker.ClearAllESP()
end

_G.PlayerMapMarker = PlayerMapMarker


-- ============================================================
-- ANIME CORNER BOX ESP (Clean - Only Corners)
-- ============================================================
local FVector2D = _G.FVector2D or import("Vector2D")
local FLinearColor = _G.FLinearColor or import("LinearColor")
local SlateBlueprintLibrary = nil
local WidgetLayoutLibrary = nil
pcall(function() SlateBlueprintLibrary = import("SlateBlueprintLibrary") end)
pcall(function() WidgetLayoutLibrary = import("WidgetLayoutLibrary") end)

local function ESPValid(obj)
  if obj == nil then return false end
  local ok, v = pcall(function() return slua.isValid(obj) end)
  return ok and v == true
end

local function ESPV2(x, y)
  if FVector2D then return FVector2D(x, y) end
  return { X = x, Y = y }
end

local function ESPMKC(r, g, b, a)
  if FLinearColor then return FLinearColor(r, g, b, a) end
  return { R = r, G = g, B = b, A = a }
end

local CFG = {
  MaxDistance = 40000,
  MaxTracked = 16,
  ScreenMargin = 220,
  CornerThickness = 1.0,
  CornerLen = 0.28,
  CornerMin = 6,
  CornerMax = 28,
  BoxMinWidth = 22,
  BoxMaxWidth = 320,
  BoxMinHeight = 14,
  BoxWidthFactor = 0.62,
  HeadExtra = 0.06,
  FootExtra = 0.02,
  DeadZone = 0.5,
  SizeHyst = 2.0,
}

local C_WHITE = ESPMKC(0.0, 1.0, 0.0, 1.0)

local function RND(v)
  if v ~= v then return 0 end
  return math.floor(v + 0.5)
end

local ESP = {}
ESP.Canvas = nil
ESP.Corners = {}
ESP.EnemyCache = {}
ESP.ScaleX = 1.0
ESP.ScaleY = 1.0
ESP.OffsetX = 0.0
ESP.OffsetY = 0.0
ESP.ViewW = 1920
ESP.ViewH = 1080
ESP.ScanInterval = 0.35
ESP.LightInterval = 0.033
ESP.TransformInterval = 0.50
ESP.LastScan = -999.0
ESP.LastTransform = -999.0
ESP.LastWorld = nil
ESP.bActive = false

function ESP.GetGameplayData()
  if ESP._GDP then return ESP._GDP end
  local ok, GDP = pcall(function() return require("GameLua.GameCore.Data.GameplayData") end)
  if ok and GDP then ESP._GDP = GDP return GDP end
  return nil
end

function ESP.GetController()
  local pc = nil
  pcall(function()
    local GDP = ESP.GetGameplayData()
    if GDP and GDP.GetPlayerController then pc = GDP.GetPlayerController() end
  end)
  if not ESPValid(pc) then
    pcall(function()
      if slua_GameFrontendHUD then pc = slua_GameFrontendHUD:GetPlayerController() end
    end)
  end
  return ESPValid(pc) and pc or nil
end

function ESP.GetLocalCharacter()
  local c = nil
  pcall(function()
    local GDP = ESP.GetGameplayData()
    if GDP then
      if GDP.GetPlayerCharacter then c = GDP.GetPlayerCharacter() end
      if not ESPValid(c) and GDP.GetLocalCharacter then c = GDP.GetLocalCharacter() end
    end
  end)
  if not ESPValid(c) then
    local pc = ESP.GetController()
    pcall(function() if pc and pc.GetPawn then c = pc:GetPawn() end end)
  end
  return ESPValid(c) and c or nil
end

function ESP.GetTeamID(Character)
  if not ESPValid(Character) then return nil end
  local id = nil
  pcall(function() if Character.GetTeamID then id = Character:GetTeamID() end end)
  if id == nil then pcall(function() id = Character.TeamID end) end
  if id == nil then
    local ps = nil
    pcall(function()
      if Character.GetPlayerStateSafety then ps = Character:GetPlayerStateSafety()
      elseif Character.GetPlayerState then ps = Character:GetPlayerState() end
    end)
    if not ESPValid(ps) then pcall(function() ps = Character.PlayerState end) end
    if ESPValid(ps) then
      pcall(function() if ps.GetTeamID then id = ps:GetTeamID() end end)
      if id == nil then pcall(function() id = ps.TeamID end) end
    end
  end
  return id
end

function ESP.IsAlive(Character)
  if not ESPValid(Character) then return false end
  local alive = nil
  pcall(function() if Character.IsAlive then alive = Character:IsAlive() end end)
  if type(alive) == "boolean" then return alive end
  local hp = nil
  pcall(function() hp = Character.Health end)
  if type(hp) ~= "number" then pcall(function() hp = Character.HP end) end
  if type(hp) == "number" then return hp > 0 end
  return true
end

function ESP.GetPlayerKey(Character)
  local key = nil
  pcall(function() if Character.GetPlayerKey then key = Character:GetPlayerKey() end end)
  if key == nil then pcall(function() key = Character.PlayerKey end) end
  return tostring(key or Character)
end

function ESP.ActorLocation(Character)
  local loc = nil
  if not ESPValid(Character) then return nil end
  pcall(function()
    if Character.K2_GetActorLocation then loc = Character:K2_GetActorLocation()
    elseif Game and Game.GetActorLocation then loc = Game:GetActorLocation(Character) end
  end)
  return loc
end

function ESP.DistMeters(a, b)
  if not a or not b then return math.huge end
  local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
  return math.sqrt(dx * dx + dy * dy + dz * dz) / 100.0
end

function ESP.GetVerticalBounds(Character)
  if not ESPValid(Character) then return nil, nil end
  local center, halfHeight = nil, nil
  local capsule = nil
  pcall(function()
    if Character.GetCapsuleComponent then capsule = Character:GetCapsuleComponent()
    elseif Character.CapsuleComponent then capsule = Character.CapsuleComponent end
  end)
  if capsule and ESPValid(capsule) then
    pcall(function()
      if capsule.K2_GetComponentLocation then center = capsule:K2_GetComponentLocation()
      elseif capsule.GetComponentLocation then center = capsule:GetComponentLocation() end
      if capsule.GetScaledCapsuleHalfHeight then halfHeight = capsule:GetScaledCapsuleHalfHeight()
      elseif capsule.GetUnscaledCapsuleHalfHeight then halfHeight = capsule:GetUnscaledCapsuleHalfHeight()
      elseif capsule.CapsuleHalfHeight then halfHeight = capsule.CapsuleHalfHeight end
    end)
  end
  if not center then
    pcall(function() if Character.K2_GetActorLocation then center = Character:K2_GetActorLocation() end end)
  end
  if not center then
    pcall(function() if Game and Game.GetActorLocation then center = Game:GetActorLocation(Character) end end)
  end
  if not center then return nil, nil end
  if not halfHeight or halfHeight < 10 or halfHeight > 200 then
    halfHeight = 85
    pcall(function()
      if Character.bIsCrouched then halfHeight = 60 end
      if Character.IsProne and Character:IsProne() then halfHeight = 25 end
    end)
  end
  return center, halfHeight
end

function ESP.GetHeadFeet(Character)
  local center, half = ESP.GetVerticalBounds(Character)
  if not center or not half then return nil, nil end
  local head = { X = center.X, Y = center.Y, Z = center.Z + half }
  local feet = { X = center.X, Y = center.Y, Z = center.Z - half }
  return head, feet
end

function ESP.Now()
  local t = nil
  pcall(function()
    local w = (slua and slua.getWorld and slua.getWorld()) or nil
    if GameplayStaticsESP and w and GameplayStaticsESP.GetRealTimeSeconds then
      t = GameplayStaticsESP.GetRealTimeSeconds(w)
    end
  end)
  if tonumber(t) then return tonumber(t) end
  pcall(function() if os and os.clock then t = os.clock() end end)
  return tonumber(t) or 0.0
end

function ESP.World()
  local w = nil
  pcall(function() if slua and slua.getWorld then w = slua.getWorld() end end)
  return w
end

function ESP.GetCanvas()
  if ESPValid(ESP.Canvas) then return ESP.Canvas end
  local root = nil
  pcall(function()
    local InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
    if InGameUITools and InGameUITools.GetMainControlBaseUI then root = InGameUITools.GetMainControlBaseUI() end
  end)
  if not ESPValid(root) then return nil end
  local canvas = nil
  pcall(function()
    if ESPValid(root.CanvasPanel_0) then canvas = root.CanvasPanel_0
    elseif ESPValid(root.CanvasPanel_42) then canvas = root.CanvasPanel_42 end
  end)
  if ESPValid(canvas) then ESP.Canvas = canvas return canvas end
  return nil
end

function ESP.UpdateCanvasTransform(pc)
  local canvas = ESP.GetCanvas()
  if not ESPValid(canvas) then return false end
  local calibrated = false
  pcall(function()
    if SlateBlueprintLibrary and SlateBlueprintLibrary.AbsoluteToLocal then
      local geo = canvas:GetCachedGeometry()
      if geo then
        local p0 = SlateBlueprintLibrary.AbsoluteToLocal(geo, ESPV2(0, 0))
        local p1 = SlateBlueprintLibrary.AbsoluteToLocal(geo, ESPV2(100, 100))
        if p0 and p1 and tonumber(p0.X) and tonumber(p1.X) and p1.X ~= p0.X and p1.Y ~= p0.Y then
          ESP.ScaleX = (p1.X - p0.X) / 100.0
          ESP.ScaleY = (p1.Y - p0.Y) / 100.0
          ESP.OffsetX = p0.X
          ESP.OffsetY = p0.Y
          calibrated = true
        end
      end
    end
  end)
  if not calibrated then
    local scale = 1.0
    pcall(function()
      if WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportScale then
        local s = WidgetLayoutLibrary.GetViewportScale(pc)
        if tonumber(s) and s > 0 then scale = s end
      end
    end)
    ESP.ScaleX = 1.0 / scale
    ESP.ScaleY = 1.0 / scale
    ESP.OffsetX = 0.0
    ESP.OffsetY = 0.0
  end
  return true
end

function ESP.Viewport(pc)
  local w, h = 1920.0, 1080.0
  pcall(function()
    if pc and pc.GetViewportSize then
      local v = ESPV2(0, 0)
      pc:GetViewportSize(v)
      if v and tonumber(v.X) and v.X > 200 then w, h = v.X, v.Y end
    end
  end)
  return w, h
end

function ESP.Project(pc, worldLoc)
  if not pc or not worldLoc then return nil end
  local pix = ESPV2(0, 0)
  local ok = false
  pcall(function()
    local res = pc:ProjectWorldLocationToScreen(worldLoc, pix, true)
    ok = (res == true or res == 1 or (pix and (pix.X ~= 0 or pix.Y ~= 0)))
  end)
  if not ok then return nil end
  return ESPV2(pix.X * (ESP.ScaleX or 1.0) + (ESP.OffsetX or 0.0),
               pix.Y * (ESP.ScaleY or 1.0) + (ESP.OffsetY or 0.0)), pix
end

function ESP.NewLine(color, z)
  local canvas = ESP.GetCanvas()
  if not ESPValid(canvas) then return nil end
  local border = nil
  pcall(function() border = CGame:NewObjectFromPath("/Script/UMG.Border", canvas) end)
  if not ESPValid(border) then return nil end
  pcall(function()
    border:SetBrushColor(color)
    border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    border:SetRenderTransformPivot(ESPV2(0.0, 0.5))
  end)
  local slot = nil
  pcall(function() slot = canvas:AddChildToCanvas(border) end)
  if not slot then
    pcall(function() border:RemoveFromParent() end)
    return nil
  end
  pcall(function() slot:SetAutoSize(false) slot:SetZOrder(z or 30) end)
  return { Widget = border, Slot = slot }
end

function ESP.DrawLine(data, x1, y1, x2, y2, thickness)
  if not data or not ESPValid(data.Widget) or not data.Slot then return false end
  if x1 ~= x1 or y1 ~= y1 or x2 ~= x2 or y2 ~= y2 then return false end
  x1, y1, x2, y2 = RND(x1), RND(y1), RND(x2), RND(y2)
  local dz = CFG.DeadZone or 0.5
  if data.lx1 and data.th == thickness then
    if math.abs((data.lx1 or 0) - x1) < dz and math.abs((data.ly1 or 0) - y1) < dz
    and math.abs((data.lx2 or 0) - x2) < dz and math.abs((data.ly2 or 0) - y2) < dz then
      if data.hidden ~= true then return true end
    end
  end
  local dx, dy = x2 - x1, y2 - y1
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1 then
    ESP.Hide(data)
    return false
  end
  local angle = ((math.atan2 and math.atan2(dy, dx)) or math.atan(dy, dx)) * 180.0 / math.pi
  angle = math.floor(angle * 10 + 0.5) / 10
  len = RND(len)
  if data.lx1 == x1 and data.ly1 == y1 and data.lx2 == x2 and data.ly2 == y2 and data.th == thickness then
    if data.hidden == true then
      pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
      data.hidden = false
    end
    return true
  end
  local ok = pcall(function()
    data.Slot:SetPosition(ESPV2(x1, y1 - thickness * 0.5))
    data.Slot:SetSize(ESPV2(len, thickness))
    data.Widget:SetRenderAngle(angle)
    data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
  end)
  if ok then
    data.lx1, data.ly1, data.lx2, data.ly2, data.th = x1, y1, x2, y2, thickness
    data.hidden = false
  end
  return true
end

function ESP.Hide(data)
  if data and ESPValid(data.Widget) and data.hidden ~= true then
    pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
    data.hidden = true
    data.lx1, data.ly1, data.lx2, data.ly2, data.th = nil, nil, nil, nil, nil
  end
end

function ESP.Destroy(data)
  if not data then return end
  local w = data.Widget or data.Container
  if ESPValid(w) then
    pcall(function() w:RemoveFromParent() end)
    pcall(function() w:ConditionalBeginDestroy() end)
  end
end

function ESP.EnsureCorner(key, idx, color)
  local t = ESP.Corners[key]
  if not t then t = {} ESP.Corners[key] = t end
  local d = t[idx]
  if d and ESPValid(d.Widget) then return d end
  d = ESP.NewLine(color or C_WHITE, 32)
  t[idx] = d
  return d
end

function ESP.HideTarget(key)
  local c = ESP.Corners[key]
  if c then for i = 1, 8 do ESP.Hide(c[i]) end end
end

function ESP.ReleaseTarget(key)
  local c = ESP.Corners[key]
  if c then for i = 1, 8 do ESP.Destroy(c[i]) end end
  ESP.Corners[key] = nil
end

function ESP.ResetWidgets()
  for _, t in pairs(ESP.Corners) do for _, d in pairs(t) do ESP.Destroy(d) end end
  ESP.Corners = {}
  ESP.Canvas = nil
  ESP.EnemyCache = {}
end

function ESP.Scan()
  local pc = ESP.GetController()
  local me = ESP.GetLocalCharacter()
  if not pc or not me then ESP.EnemyCache = {} return pc end
  local myLoc = ESP.ActorLocation(me)
  if not myLoc then ESP.EnemyCache = {} return pc end
  local myTeam = ESP.GetTeamID(me)
  local list = {}
  local pawns = nil
  pcall(function() if Game and Game.GetAllPlayerPawns then pawns = Game:GetAllPlayerPawns() end end)
  if pawns then
    for _, ch in pairs(pawns) do
      if ESPValid(ch) and ch ~= me and ESP.IsAlive(ch) then
        local team = ESP.GetTeamID(ch)
        if myTeam == nil or team == nil or tostring(team) ~= tostring(myTeam) then
          local loc = ESP.ActorLocation(ch)
          local dm = ESP.DistMeters(myLoc, loc)
          if dm * 100.0 <= (CFG.MaxDistance or 40000) then
            list[#list + 1] = { Character = ch, Key = ESP.GetPlayerKey(ch), Distance = dm }
          end
        end
      end
    end
  end
  table.sort(list, function(a, b) return (a.Distance or 99999) < (b.Distance or 99999) end)
  local trimmed = {}
  local maxR = CFG.MaxTracked or 16
  for i, it in ipairs(list) do
    if i > maxR then break end
    trimmed[#trimmed + 1] = it
  end
  ESP.EnemyCache = trimmed
  return pc
end

function ESP.Update()
  if not _G.Mod_ESP_ShowTeamColor then ESP.ResetWidgets() return end
  local world = ESP.World()
  if world ~= ESP.LastWorld then
    ESP.ResetWidgets()
    ESP.LastWorld = world
    ESP.LastScan = -999.0
    ESP.LastTransform = -999.0
  end
  local canvas = ESP.GetCanvas()
  if not canvas then return end
  local now = ESP.Now()
  local pc = ESP.GetController()
  if (now - ESP.LastScan) >= (ESP.ScanInterval or 0.35) then
    pc = ESP.Scan()
    ESP.LastScan = now
  end
  pc = pc or ESP.GetController()
  if not pc then return end
  if (now - (ESP.LastTransform or -999.0)) >= (ESP.TransformInterval or 0.50) then
    ESP.UpdateCanvasTransform(pc)
    ESP.LastTransform = now
  end
  local vw, vh = ESP.Viewport(pc)
  local hyst = CFG.SizeHyst or 2.0
  if math.abs(vw - (ESP.ViewW or 0)) > hyst or math.abs(vh - (ESP.ViewH or 0)) > hyst then
    ESP.ViewW, ESP.ViewH = vw, vh
  else
    vw, vh = ESP.ViewW, ESP.ViewH
  end

  local active = {}
  for _, item in ipairs(ESP.EnemyCache) do
    local c = item.Character
    local key = item.Key
    if ESPValid(c) and ESP.IsAlive(c) then
      local head, feet = ESP.GetHeadFeet(c)
      if head and feet then
        local headS, headPix = ESP.Project(pc, head)
        local feetS, feetPix = ESP.Project(pc, feet)
        if headS and feetS and headPix and feetPix then
          local m = CFG.ScreenMargin or 220
          local on = headPix.X > -m and headPix.X < vw + m
            and headPix.Y > -m and headPix.Y < vh + m
            and feetPix.X > -m and feetPix.X < vw + m
            and feetPix.Y > -m and feetPix.Y < vh + m
          if on then
            local H = feetS.Y - headS.Y
            if H >= (CFG.BoxMinHeight or 14) and H <= vh * 1.5 then
              active[key] = true
              local W = H * (CFG.BoxWidthFactor or 0.62)
              W = math.max(CFG.BoxMinWidth or 22, math.min(CFG.BoxMaxWidth or 320, W))
              local padT = H * (CFG.HeadExtra or 0)
              local padB = H * (CFG.FootExtra or 0)
              local cx = (headS.X + feetS.X) * 0.5
              local L = cx - W * 0.5
              local R = cx + W * 0.5
              local T = headS.Y - padT
              local B = feetS.Y + padB

              local arm = math.min(R - L, B - T) * (CFG.CornerLen or 0.28)
              arm = math.max(CFG.CornerMin or 6, math.min(CFG.CornerMax or 28, arm))
              local th = CFG.CornerThickness or 2.2
              ESP.DrawLine(ESP.EnsureCorner(key, 1, C_WHITE), L, T, L + arm, T, th)
              ESP.DrawLine(ESP.EnsureCorner(key, 2, C_WHITE), L, T, L, T + arm, th)
              ESP.DrawLine(ESP.EnsureCorner(key, 3, C_WHITE), R, T, R - arm, T, th)
              ESP.DrawLine(ESP.EnsureCorner(key, 4, C_WHITE), R, T, R, T + arm, th)
              ESP.DrawLine(ESP.EnsureCorner(key, 5, C_WHITE), L, B, L + arm, B, th)
              ESP.DrawLine(ESP.EnsureCorner(key, 6, C_WHITE), L, B, L, B - arm, th)
              ESP.DrawLine(ESP.EnsureCorner(key, 7, C_WHITE), R, B, R - arm, B, th)
              ESP.DrawLine(ESP.EnsureCorner(key, 8, C_WHITE), R, B, R, B - arm, th)
            else
              ESP.HideTarget(key)
            end
          else
            ESP.HideTarget(key)
          end
        else
          ESP.HideTarget(key)
        end
      else
        ESP.HideTarget(key)
      end
    end
  end
  local seenCache = {}
  for _, it in ipairs(ESP.EnemyCache) do seenCache[it.Key] = true end
  local function stillActive(k) return active[k] == true end
  for k, _ in pairs(ESP.Corners) do
    if not stillActive(k) then ESP.HideTarget(k) end
  end
  for k, _ in pairs(ESP.Corners) do
    if not stillActive(k) and not seenCache[k] then ESP.ReleaseTarget(k) end
  end
end

function ESP.Tick()
  pcall(ESP.Update)
end

function ESP.AttachTimers()
  pcall(function()
    local pc = ESP.GetController()
    if ESPValid(pc) and pc.AddGameTimer then
      if ESP._TimerPC == pc and ESP._TimerHooked then return end
      ESP._TimerPC = pc
      ESP._TimerHooked = true
      pc:AddGameTimer(ESP.LightInterval or 0.033, true, function()
        if ESP.bActive then pcall(ESP.Tick) end
      end)
    else
      pcall(function()
        require("timer").SetGameTimer(1.0, false, function()
          ESP._TimerHooked = false
          ESP.AttachTimers()
        end)
      end)
    end
    pcall(function() require("timer").SetGameTimer(5.0, false, function() ESP.AttachTimers() end) end)
  end)
end

function ESP.Start()
  if ESP.bActive then return end
  ESP.bActive = true
  pcall(ESP.Update)
  ESP.AttachTimers()
end

_G.ESP = ESP
-- ============================================================
-- END ANIME CORNER BOX ESP
-- =======================================================
-- ========================================================================
-- NewFreshRuntimeTick - applies ESP toggle settings and start/stop
-- ========================================================================
function _G.NewFreshRuntimeTick()
    -- Aim features, iPad view, credit (from BRPlayerCharacterBase.lua)
    -- These functions may not exist in this context, so pcall them safely
    pcall(function() if _G.NewFreshApplyV1AimFeatures then _G.NewFreshApplyV1AimFeatures() end end)
    pcall(function() if _G.NewFreshApplyIpadView then _G.NewFreshApplyIpadView() end end)
    pcall(function() if _G.NewFreshCredit then _G.NewFreshCredit() end end)

    -- Weapon Glow
    if _G.Mod_WeaponGlow_Enabled and _G.ApplyWeaponGlow then
        pcall(function() _G.ApplyWeaponGlow(GameplayData.GetPlayerCharacter()) end)
    end

    -- ESP V2 toggle settings and start/stop
    if _G.PlayerMapMarker then
        _G.PlayerMapMarker.bUseSnapLines = _G.Mod_ESP_ShowSnapline or false
        _G.PlayerMapMarker.bShowDistance = _G.Mod_ESP_ShowDistance or false
        if _G.Mod_ESP_Enabled then
            if not _G.PlayerMapMarker.bActive then pcall(_G.PlayerMapMarker.Start) end
        elseif _G.PlayerMapMarker.bActive then
            pcall(_G.PlayerMapMarker.Stop)
        end
    end

    -- RedBoxOverlay (player count) start/stop
    if _G.RedBoxOverlay then
        if _G.Mod_ESP_Enabled and _G.Mod_ESP_ShowPlayerCount then
            if not _G.RedBoxOverlay.bActive then pcall(_G.RedBoxOverlay.Start) end
        else
            if _G.RedBoxOverlay.bActive then pcall(_G.RedBoxOverlay.Stop) end
        end
    end
end


-- ============================================================
-- WEAPON GLOW (HDR) FUNCTION
-- ============================================================
-- WEAPON GLOW (HDR) FUNCTION - GLITCH FIXED
-- ============================================================
_G.ApplyWeaponGlow = function(PlayerCharacter)
    pcall(function()
        if not slua.isValid(PlayerCharacter) then return end
        local WeaponManager = PlayerCharacter.WeaponManagerComponent
        if not slua.isValid(WeaponManager) then return end

        local meshComponentClass = import("/Script/Engine.MeshComponent")

        -- PEHLE SABHI GUNS SE GLOW HATAO (Taki peeth wali gun glitch na kare)
        for slot = 1, 3 do
            local Weapon = WeaponManager:GetInventoryWeaponByPropSlot(slot)
            if slua.isValid(Weapon) then
                pcall(function()
                    local components = Weapon:GetComponentsByClass(meshComponentClass)
                    local count = type(components.Num) == "function" and components:Num() or #components
                    for i = 1, count do
                        local comp = type(components.Get) == "function" and components:Get(i-1) or components[i]
                        if slua.isValid(comp) and comp.SetDrawIdeaOutline then
                            comp:SetDrawIdeaOutline(false)
                        end
                    end
                end)
            end
        end

        -- Agar Glow Toggle OFF hai toh yahi ruk jao
        if not _G.Mod_WeaponGlow_Enabled then return end

        local LinearColorClass = import("LinearColor") or FLinearColor
        local glowIntensity = 80.0
        local thickness = _G.WeaponGlowThickness or 3
        local colorMode = _G.WeaponGlowColor or 5

        local r, g, b = 1.0, 1.0, 0.0
        if colorMode == 1 then r, g, b = 1.0, 0.0, 0.0
        elseif colorMode == 2 then r, g, b = 1.0, 0.85, 0.0
        elseif colorMode == 3 then r, g, b = 0.0, 0.0, 1.0
        elseif colorMode == 4 then r, g, b = 1.0, 1.0, 0.0
        elseif colorMode == 5 then
            local time = os.clock() * 2.0
            r = (math.sin(time) + 1) / 2
            g = (math.sin(time + 2) + 1) / 2
            b = (math.sin(time + 4) + 1) / 2
        end

        local finalColor = LinearColorClass and LinearColorClass(r * glowIntensity, g * glowIntensity, b * glowIntensity, 1.0) or { R = r * 255 * glowIntensity, G = g * 255 * glowIntensity, B = b * 255 * glowIntensity, A = 255 }

        -- AB SIRF HAATH MEIN PAKDI HUI GUN PAR GLOW LAGAO
        local CurrentWeapon = PlayerCharacter:GetCurrentWeapon()
        if slua.isValid(CurrentWeapon) then
            pcall(function()
                local components = CurrentWeapon:GetComponentsByClass(meshComponentClass)
                local count = type(components.Num) == "function" and components:Num() or #components
                for i = 1, count do
                    local comp = type(components.Get) == "function" and components:Get(i-1) or components[i]
                    if slua.isValid(comp) then
                        comp.UseScopeDistanceCulling = false
                        if comp.SetDrawIdeaOutline then
                            comp:SetDrawIdeaOutline(true)
                            if comp.OverrideIdeaOutlineColor then comp:OverrideIdeaOutlineColor(true, finalColor) end
                            if comp.OverrideIdeaOutlineThickness then comp:OverrideIdeaOutlineThickness(true, thickness) end
                        end
                    end
                end
            end)
        end
    end)
end





-- ============================================================
-- UNLOCK 165 FPS FUNCTION (Full hook version)
-- ============================================================
local function InitializeGraphicsUnlock()
    if _G.GraphicsUnlocked then return end

    pcall(function()
        local SettingCfg = safe_require("client.logic.setting.setting_config")
        local GraphicSettingDB = safe_require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")
        if SettingCfg then
            if SettingCfg.TpViewValue then SettingCfg.TpViewValue.max = 160 end
            if SettingCfg.FpViewValue then SettingCfg.FpViewValue.max = 160 end
        end
        if GraphicSettingDB then
            if GraphicSettingDB.TpViewValue then GraphicSettingDB.TpViewValue.max = 160 end
        end
    end)

    pcall(function()
        local logic_setting_graphics = safe_require("client.slua.logic.setting.logic_setting_graphics")
        local GSC_FPS = safe_require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPS")
        local GSC_FPSFT = safe_require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPSFT")
        local GraphicSettingDB = safe_require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")

        local KismetMathLibrary = import("KismetMathLibrary") or _G.KismetMathLibrary
        local FLinearColor2 = import("LinearColor") or FLinearColor

        -- Hook SetFPS to force 165 when level 8
        if logic_setting_graphics then
            local old_SetFPS = logic_setting_graphics.SetFPS
            function logic_setting_graphics.SetFPS(gameInstance, FPSLevel)
                if old_SetFPS then old_SetFPS(gameInstance, FPSLevel) end
                if FPSLevel == 8 then
                    gameInstance:ExecuteCMD("t.MaxFPS", "165")
                    gameInstance:ExecuteCMD("r.FrameRateLimit", "165")
                end
            end
        end

        -- Hook GSC_FPS to unlock all FPS levels
        if GSC_FPS and GSC_FPS.__inner_impl then
            local fps_impl = GSC_FPS.__inner_impl
            function fps_impl:GetMaxFPSLevel() return 8, 8 end
            function fps_impl:InitRealSupportFPS()
                local RealSupportFPS = {}
                for i = 1, 8 do RealSupportFPS[i] = {true, true} end
                if GraphicSettingDB then GraphicSettingDB:UpdateUIData(GraphicSettingDB.RealSupportFPS, RealSupportFPS, false) end
                return RealSupportFPS
            end
            function fps_impl:UpdateSelectedFPSState(selectedLevel)
                if not slua.isValid(self.UIRoot) then return end
                for level = 2, 8 do
                    local name = "NodeFps" .. (({[2]=20,[3]=25,[4]=30,[5]=40,[6]=60,[7]=90,[8]=120})[level] or 120)
                    local widget = self.UIRoot[name]
                    if slua.isValid(widget) then
                        widget:SetIsEnabled(true)
                        pcall(function() widget:SetRenderOpacity(1.0) end)
                        local switcher = self.UIRoot["WidgetSwitcher_" .. level]
                        if slua.isValid(switcher) then
                            switcher:SetActiveWidgetIndex(level == selectedLevel and 0 or 1)
                        end
                    end
                end
            end
        end

        -- Hook GSC_FPSFT to allow 90-165 fine tune slider
        if GSC_FPSFT and GSC_FPSFT.__inner_impl then
            local ft_impl = GSC_FPSFT.__inner_impl
            local NMinFPS, NStep = 90, 5
            local function clamp(value, min, max)
                if value < min then return min end
                if max < value then return max end
                return value
            end
            local function lerp(a, b, t) return a + (b - a) * t end
            local function _getColorByPercent(start, finish, percent)
                if not FLinearColor2 then return nil end
                return FLinearColor2(lerp(start.R, finish.R, percent), lerp(start.G, finish.G, percent), lerp(start.B, finish.B, percent), lerp(start.A, finish.A, percent))
            end

            ft_impl.ShowOrHide = function(self)
                self:SelfHitTestInvisible()
                if self.InitFPSFTSwitch then self:InitFPSFTSwitch() end
            end

            ft_impl.InitFPSFTSwitch = function(self)
                local FPSFineTuneSwitch = GraphicSettingDB:GetUIData(GraphicSettingDB.FPSFineTuneSwitch)
                if self.UIRoot.Setting_Switch then self.UIRoot.Setting_Switch:SetSwitcherEnable2(FPSFineTuneSwitch, true) end
                if self.UIRoot.CanvasPanel_8 then self:SetWidgetVisible(self.UIRoot.CanvasPanel_8, FPSFineTuneSwitch) end
                if self.UIRoot.WidgetSwitcher_0 then self.UIRoot.WidgetSwitcher_0:SetActiveWidgetIndex(2) end
                if self.InitFPSFTValue165 then self:InitFPSFTValue165() end
            end

            ft_impl.InitFPSFTValue165 = function(self)
                local itemRoot = self.UIRoot
                local FPSFineTuneSwitch = GraphicSettingDB:GetUIData(GraphicSettingDB.FPSFineTuneSwitch)
                local FPSFineTuneNum = 165
                if FPSFineTuneSwitch then
                    FPSFineTuneNum = GraphicSettingDB:GetUIData(GraphicSettingDB.FPSFineTuneNum) or 165
                    itemRoot.Slider_screen3:SetLocked(false)
                    if FLinearColor2 then
                        itemRoot.ProgressBar_screen3:SetFillColorAndOpacity(FLinearColor2(1.0, 1.0, 1.0, 1.0))
                        itemRoot.Slider_screen3:SetSliderHandleColor(FLinearColor2(1.0, 1.0, 1.0, 1.0))
                    end
                else
                    itemRoot.Slider_screen3:SetLocked(true)
                    if FLinearColor2 then
                        itemRoot.ProgressBar_screen3:SetFillColorAndOpacity(FLinearColor2(1.0, 0.625, 0.6, 1))
                        itemRoot.Slider_screen3:SetSliderHandleColor(FLinearColor2(1.0, 0.625, 0.6, 1.0))
                    end
                end
                local FPSFineTunePer = (FPSFineTuneNum - NMinFPS) / (165 - NMinFPS)

                itemRoot.Veihclescreen3:SetText(tostring(FPSFineTuneNum))
                itemRoot.Slider_screen3:SetValue(FPSFineTunePer)
                itemRoot.ProgressBar_screen3:SetPercent(FPSFineTunePer)

                if FLinearColor2 then
                    local startColor = FLinearColor2(1.0, 1.0, 1.0, 1.0)
                    local midColor = FLinearColor2(1.0, 0.54, 0.11, 1.0)
                    local endColor = FLinearColor2(1.0, 0.23, 0.15, 1.0)
                    local sliderColor = FPSFineTunePer < 0.4 and startColor or _getColorByPercent(midColor, endColor, (FPSFineTunePer - 0.4) / 0.6)
                    itemRoot.Slider_screen3:SetSliderHandleColor(sliderColor)
                end
            end

            ft_impl.OnFPSFTValueChange3 = function(self, FPSFineTuneNum)
                GraphicSettingDB:UpdateUIData(GraphicSettingDB.FPSFineTuneNum, FPSFineTuneNum)
                if self.InitFPSFTValue165 then self:InitFPSFTValue165() end
                if self:GetParentUI() then self:GetParentUI():SetDirty(true) end
                local gameInstance = GraphicSettingDB.GetGameInstance and GraphicSettingDB.GetGameInstance()
                if gameInstance then
                    gameInstance:ExecuteCMD("t.MaxFPS", tostring(FPSFineTuneNum))
                    gameInstance:ExecuteCMD("r.FrameRateLimit", tostring(FPSFineTuneNum))
                end
            end

            ft_impl.OnFPSFTSliderValueChange3 = function(self, value)
                if GraphicSettingDB:GetUIData(GraphicSettingDB.FPSFineTuneSwitch) and KismetMathLibrary then
                    local FPSFineTuneNum = KismetMathLibrary.FCeil(value * (165 - NMinFPS) / NStep) * NStep + NMinFPS
                    self:OnFPSFTValueChange3(clamp(FPSFineTuneNum, NMinFPS, 165))
                end
            end

            ft_impl.OnFPSFTAdd = ft_impl.OnFPSFTAdd3
            ft_impl.OnFPSFTMinus = ft_impl.OnFPSFTMinus3
            ft_impl.OnFPSFTAdd2 = ft_impl.OnFPSFTAdd3
            ft_impl.OnFPSFTMinus2 = ft_impl.OnFPSFTMinus3
            ft_impl.OnFPSFTSliderValueChange = ft_impl.OnFPSFTSliderValueChange3
            ft_impl.OnFPSFTSliderValueChange2 = ft_impl.OnFPSFTSliderValueChange3
        end
    end)

    -- Also run console commands directly
    pcall(function()
        local KSL = import("KismetSystemLibrary")
        local world = slua.getWorld()
        if KSL and world then
            KSL.ExecuteConsoleCommand(world, "t.MaxFPS 165")
            KSL.ExecuteConsoleCommand(world, "r.FrameRateLimit 165")
        end
    end)

    _G.GraphicsUnlocked = true
end

-- ============================================================
-- IPAD VIEW FUNCTION
-- ============================================================
local function UpdateIpadView(localPlayer, pc)
    pcall(function()
        if not isValid(localPlayer) then return end
        
        local currentVehicle = localPlayer.CurrentVehicle or (type(localPlayer.GetVehicle) == "function" and localPlayer:GetVehicle())
        local isInVehicle = isValid(currentVehicle) or localPlayer.bIsInVehicle
        local uTPPCam = localPlayer.ThirdPersonCameraComponent
        local uVehCam = localPlayer.VehicleCameraComponent
        local camMgr = pc.PlayerCameraManager
        
        -- Not aiming (walking or driving)
        if type(pc.FOV) == "function" then pc:FOV(0) end
        if isValid(camMgr) and type(camMgr.UnlockFOV) == "function" then camMgr:UnlockFOV() end
        
        -- Walk
        if not isInVehicle then
            if _G.Mod_IpadView_Enabled then
                local targetTPP = _G.IpadViewFOV or 120
                if isValid(uTPPCam) and uTPPCam.FieldOfView ~= targetTPP then
                    uTPPCam.FieldOfView = targetTPP
                end
            else
                if isValid(uTPPCam) and uTPPCam.FieldOfView ~= 90 then
                    uTPPCam.FieldOfView = 90
                end
            end
        end
        
        -- Drive (reset vehicle cam to default)
        if isInVehicle then
            if isValid(uVehCam) and uVehCam.FieldOfView ~= 90 then
                uVehCam.FieldOfView = 90
            end
        end
    end)
end

-- ============================================================
-- WHITE BODY FUNCTION
-- ============================================================
local function InitCircleArrowESP()
    if _G.CircleArrowESP then return end
    local CAIsValid = function(obj) return obj ~= nil and slua ~= nil and slua.isValid ~= nil and slua.isValid(obj) end
    local CAFVector2D = _G.FVector2D or import("Vector2D")
    local CAFLinearColor = _G.FLinearColor or import("LinearColor")
    local CASlateBlueprintLibrary = nil
    local CAWidgetLayoutLibrary = nil
    pcall(function() CASlateBlueprintLibrary = import("SlateBlueprintLibrary") end)
    pcall(function() CAWidgetLayoutLibrary = import("WidgetLayoutLibrary") end)

    local ESP = {}
    ESP.FOVCircleLines = {}
    ESP.ESPCanvas = nil
    ESP.bActive = false
    ESP._cachedViewportW = 1920
    ESP._cachedViewportH = 1080
    ESP._CanvasScaleX = 1.0
    ESP._CanvasScaleY = 1.0
    ESP._CanvasOffsetX = 0.0
    ESP._CanvasOffsetY = 0.0
    
    -- [ SETTINGS FOR SIMPLE SOLID GREEN CIRCLE ]
    ESP.FOVCircleRadius = 250.0
    ESP.FOVCircleSegments = 72
    ESP.FOVCircleThickness = 4.0
    ESP.FOVCircleColor = CAFLinearColor and CAFLinearColor(0.0, 1.0, 0.0, 1.0) or {R=0,G=1,B=0,A=1}
    
    ESP.nUpdateInterval = 0.5
    ESP._LightUpdateInterval = 0.05

    function ESP.GetGameplayData()
        if ESP._CachedGameplayData then return ESP._CachedGameplayData end
        local ok, GDP = pcall(function() return require("GameLua.GameCore.Data.GameplayData") end)
        if ok and GDP then ESP._CachedGameplayData = GDP; return GDP end
        return nil
    end

    function ESP.GetMyPlayerController()
        local PC = ESP._CachedPC
        if PC and CAIsValid(PC) then return PC end
        local GDP = ESP.GetGameplayData()
        if GDP then pcall(function() PC = GDP.GetPlayerController and GDP.GetPlayerController() end) end
        if not (PC and CAIsValid(PC)) then pcall(function() if slua_GameFrontendHUD then PC = slua_GameFrontendHUD:GetPlayerController() end end) end
        if PC and CAIsValid(PC) then ESP._CachedPC = PC end
        return PC
    end

    function ESP.InitESPCanvas()
        if ESP.ESPCanvas and Game:IsValid(ESP.ESPCanvas) then return true end
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
        ESP.ESPCanvas = ParentCanvas
        return true
    end

    function ESP.UpdateCanvasTransform(PC)
        if not ESP.ESPCanvas or not Game:IsValid(ESP.ESPCanvas) then return end
        local success = false
        pcall(function()
            local SBL = CASlateBlueprintLibrary
            if SBL and SBL.AbsoluteToLocal then
                local cg = ESP.ESPCanvas:GetCachedGeometry()
                if cg then
                    local pt0 = SBL.AbsoluteToLocal(cg, CAFVector2D and CAFVector2D(0,0) or {X=0,Y=0})
                    local pt1 = SBL.AbsoluteToLocal(cg, CAFVector2D and CAFVector2D(100,100) or {X=100,Y=100})
                    if pt0 and pt1 then
                        ESP._CanvasScaleX = (pt1.X - pt0.X) / 100
                        ESP._CanvasScaleY = (pt1.Y - pt0.Y) / 100
                        ESP._CanvasOffsetX = pt0.X
                        ESP._CanvasOffsetY = pt0.Y
                        success = true
                    end
                end
            end
        end)
        if not success then
            local scale = 1.0
            local WLL = CAWidgetLayoutLibrary
            if WLL and WLL.GetViewportScale then scale = WLL.GetViewportScale(PC) or 1.0 end
            ESP._CanvasScaleX = 1.0 / scale
            ESP._CanvasScaleY = 1.0 / scale
            ESP._CanvasOffsetX = 0
            ESP._CanvasOffsetY = 0
        end
    end

    function ESP.ScreenPixelToCanvasLocal(PC, ScreenPixelPos)
        if not ScreenPixelPos then return CAFVector2D and CAFVector2D(0,0) or {X=0,Y=0} end
        local scaleX = ESP._CanvasScaleX or 1.0
        local scaleY = ESP._CanvasScaleY or 1.0
        local offsetX = ESP._CanvasOffsetX or 0
        local offsetY = ESP._CanvasOffsetY or 0
        return (CAFVector2D and CAFVector2D(ScreenPixelPos.X * scaleX + offsetX, ScreenPixelPos.Y * scaleY + offsetY)) or {X = ScreenPixelPos.X * scaleX + offsetX, Y = ScreenPixelPos.Y * scaleY + offsetY}
    end

    function ESP.GetScreenCenter(PC)
        local screenPixelW, screenPixelH = 0, 0
        local scale = 1.0
        pcall(function()
            if PC and PC.GetViewportSize then
                local vs = CAFVector2D and CAFVector2D(0,0) or {X=0,Y=0}
                PC:GetViewportSize(vs)
                if vs and vs.X and vs.X > 200 then screenPixelW, screenPixelH = vs.X, vs.Y end
            end
        end)
        if screenPixelW <= 200 then
            pcall(function()
                local WLL = CAWidgetLayoutLibrary
                if WLL and WLL.GetViewportSize then
                    local vs = WLL.GetViewportSize(PC)
                    if vs and vs.X and vs.X > 200 then screenPixelW, screenPixelH = vs.X, vs.Y end
                end
            end)
        end
        if screenPixelW <= 200 then
            screenPixelW = (ESP._cachedViewportW or 1920) * scale
            screenPixelH = (ESP._cachedViewportH or 1080) * scale
        end
        local centerPixel = CAFVector2D and CAFVector2D(screenPixelW / 2.0, screenPixelH / 2.0) or {X = screenPixelW / 2.0, Y = screenPixelH / 2.0}
        return ESP.ScreenPixelToCanvasLocal(PC, centerPixel)
    end

    function ESP.UpdateCenterCircle(CenterCanvas)
        if not ESP.ESPCanvas or not Game:IsValid(ESP.ESPCanvas) then ESP.RemoveCenterCircle() return end
        local cx = CenterCanvas.X
        local cy = CenterCanvas.Y
        if not ESP.FOVCircleLines then ESP.FOVCircleLines = {} end

        local function DrawRing(linesTable, radius, segments, thickness, color, zorder)
            for i = 1, segments do
                local angle1 = ((i-1) / segments) * (2 * math.pi)
                local angle2 = (i / segments) * (2 * math.pi)
                local x1 = cx + math.cos(angle1) * radius
                local y1 = cy + math.sin(angle1) * radius
                local x2 = cx + math.cos(angle2) * radius
                local y2 = cy + math.sin(angle2) * radius
                local dx = x2 - x1
                local dy = y2 - y1
                local len = math.sqrt(dx*dx + dy*dy)
                local ang = (math.atan2 and math.atan2(dy,dx) or math.atan(dy,dx)) * (180.0 / math.pi)
                local lineData = linesTable[i]
                if not lineData then
                    local Border = nil
                    pcall(function() Border = CGame:NewObjectFromPath("/Script/UMG.Border", ESP.ESPCanvas) end)
                    if Border and slua.isValid(Border) then
                        pcall(function() Border:SetBrushColor(color) end)
                        pcall(function() Border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                        pcall(function() Border:SetRenderTransformPivot(CAFVector2D and CAFVector2D(0.0, 0.5) or {X=0,Y=0.5}) end)
                        local Slot = ESP.ESPCanvas:AddChildToCanvas(Border)
                        if Slot then Slot:SetAutoSize(false); Slot:SetZOrder(zorder) end
                        lineData = { Widget = Border, Slot = Slot }
                        linesTable[i] = lineData
                    end
                end
                if lineData and lineData.Slot then
                    pcall(function()
                        lineData.Slot:SetPosition(CAFVector2D and CAFVector2D(x1, y1 - thickness/2.0) or {X=x1, Y=y1 - thickness/2.0})
                        lineData.Slot:SetSize(CAFVector2D and CAFVector2D(len + 0.5, thickness) or {X=len+0.5, Y=thickness})
                        lineData.Widget:SetRenderAngle(ang)
                        lineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                    end)
                end
            end
        end

        DrawRing(ESP.FOVCircleLines, ESP.FOVCircleRadius or 250.0, ESP.FOVCircleSegments or 72, ESP.FOVCircleThickness or 4.0, ESP.FOVCircleColor, 1)
    end

    function ESP.RemoveCenterCircle()
        if ESP.FOVCircleLines then
            for _, lineData in pairs(ESP.FOVCircleLines) do
                if lineData and lineData.Widget and slua.isValid(lineData.Widget) then
                    pcall(function() lineData.Widget:RemoveFromParent() lineData.Widget:ConditionalBeginDestroy() end)
                end
            end
        end
        ESP.FOVCircleLines = {}
    end

    function ESP.ScanAndUpdate()
        if not ESP.InitESPCanvas() then return end
        local PC = ESP.GetMyPlayerController()
        if not CAIsValid(PC) then return end
        ESP.UpdateCanvasTransform(PC)
        local centerCanvas = ESP.GetScreenCenter(PC)
        ESP.UpdateCenterCircle(centerCanvas)
    end

    function ESP.UpdateLight()
        if not ESP.ESPCanvas or not Game:IsValid(ESP.ESPCanvas) then return end
        local PC = ESP.GetMyPlayerController()
        if not CAIsValid(PC) then return end
        ESP.UpdateCanvasTransform(PC)
        local centerCanvas = ESP.GetScreenCenter(PC)
        ESP.UpdateCenterCircle(centerCanvas)
    end

    function ESP.AttachTimers()
        pcall(function()
            local pc = ESP.GetMyPlayerController()
            if not slua.isValid(pc) or not pc.AddGameTimer then return end
            local now = os.time()
            local lastPC = ESP._ActiveTimerPC
            if lastPC and slua.isValid(lastPC) and lastPC == pc then
                if ESP._ActiveTimerTick and (now - ESP._ActiveTimerTick) < 5 then return end
            end
            ESP._ActiveTimerPC = pc
            ESP._ActiveTimerTick = now
            pcall(function()
                pc:AddGameTimer(ESP.nUpdateInterval or 0.5, true, function()
                    ESP._ActiveTimerTick = os.time()
                    if ESP.bActive then pcall(function() ESP.ScanAndUpdate() end) end
                end)
            end)
            pcall(function()
                pc:AddGameTimer(ESP._LightUpdateInterval or 0.05, true, function()
                    ESP._ActiveTimerTick = os.time()
                    if ESP.bActive then pcall(function() ESP.UpdateLight() end) end
                end)
            end)
        end)
    end

    function ESP.Start()
        if ESP.bActive then return end
        ESP.bActive = true
        ESP.ScanAndUpdate()
        ESP.AttachTimers()
    end

    function ESP.Stop()
        ESP.bActive = false
        ESP.RemoveCenterCircle()
        ESP.ESPCanvas = nil
    end

    _G.CircleArrowESP = ESP
end

-- ============================================================
-- MAIN UPDATE LOOP (CHAMS + ESP V2 + WEAPON GLOW + IPAD + WHITE BODY + FPS + CIRCLE ARROW)
-- ============================================================
local function MainUpdate()
    pcall(function()
        local localPlayer = GameplayData and GameplayData.GetPlayerCharacter()
        if not slua.isValid(localPlayer) then return end

        -- ===== CHAMS COLOR SYNC =====
        if colors and _G.ChamsColors then
            if _G.ChamsColors.vis then colors.vis = _G.ChamsColors.vis end
            if _G.ChamsColors.occ then colors.occ = _G.ChamsColors.occ end
            if _G.ChamsColors.bVis then colors.bVis = _G.ChamsColors.bVis end
            if _G.ChamsColors.bOcc then colors.bOcc = _G.ChamsColors.bOcc end
        end

        -- ===== IPAD FOV SYNC =====
        if _G.Mod_IpadView_Enabled and _G.IpadViewFOV then
            local targetFov = tonumber(_G.IpadViewFOV) or 120
            if targetFov < 90 then targetFov = 90 end
            if targetFov > 190 then targetFov = 190 end
            _G.IpadViewFOV = targetFov
            
            pcall(function()
                if localPlayer.ThirdPersonCameraComponent and slua.isValid(localPlayer.ThirdPersonCameraComponent) then
                    if localPlayer.ThirdPersonCameraComponent.FieldOfView ~= targetFov then
                        localPlayer.ThirdPersonCameraComponent.FieldOfView = targetFov
                    end
                end
            end)
        end

        -- Update Chams
        if _G.Mod_Chams_Enabled then
            EnableChamsConsole()
            if colors then
                tickCount = tickCount + 1
                if tickCount % 6 == 0 then processedPawns = {} end
                local myTeamID = localPlayer.TeamID
                local allChars = Game:GetAllPlayerPawns() or {}
                local count = 0
                for _, target in pairs(allChars) do
                    if count >= 20 then break end
                    local playerKey = target.PlayerKey
                    if not (playerKey and processedPawns[playerKey]) then
                        if ProcessEnemy_Chams(target, myTeamID) then count = count + 1 end
                    end
                end
            end
        else
            if chamsReady then
                DisableChams()
            end
        end

        -- Update Anime Box ESP (FIXED - Mod_ESP_ShowTeamColor)
        if _G.Mod_ESP_ShowTeamColor then
            if _G.ESP and not _G.ESP.bActive then
                pcall(_G.ESP.Start)
            end
        else
            if _G.ESP and _G.ESP.bActive then
                pcall(function() 
                    _G.ESP.bActive = false
                    _G.ESP.ResetWidgets()
                end)
            end
        end

        -- Call NewFreshRuntimeTick
        pcall(_G.NewFreshRuntimeTick)

        -- Update Weapon Glow
        if not _G.LastGlowTime or (os.clock() - _G.LastGlowTime) > 0.5 then
            _G.LastGlowTime = os.clock()
            if _G.Mod_WeaponGlow_Enabled then
                if _G.ApplyWeaponGlow then _G.ApplyWeaponGlow(localPlayer) end
            else
                if _G.DisableWeaponGlow then _G.DisableWeaponGlow(localPlayer) end
            end
        end

        -- Update Unlock 165 FPS
        if _G.Mod_UnlockFPS_Enabled and not _G.GraphicsUnlocked then
            InitializeGraphicsUnlock()
        end

        -- Update iPad View
        local uCon = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if isValid(uCon) then
            UpdateIpadView(localPlayer, uCon)
        end

        -- Update White Body
        UpdateWhiteBody()

        -- Update Circle & Arrow ESP
        if _G.Mod_CircleArrow_Enabled then
            if not _G.CircleArrowESP then InitCircleArrowESP() end
            if _G.CircleArrowESP and not _G.CircleArrowESP.bActive then
                pcall(_G.CircleArrowESP.Start)
            end
        else
            if _G.CircleArrowESP and _G.CircleArrowESP.bActive then
                pcall(_G.CircleArrowESP.Stop)
            end
        end

    end)
end



-- ============================================================
-- START MODULES
-- ============================================================
pcall(function()
    if _G._ESPWatchdogHandle then pcall(function() Game:ClearTimer(_G._ESPWatchdogHandle) end); _G._ESPWatchdogHandle = nil end

    local function StartESP_Watchdog(targetActor)
        if not isValid(targetActor) then return end
        _G._ESPTimerChar = targetActor
        _G._ESPTimerHandle = targetActor:AddGameTimer(0.2, true, function()
            pcall(MainUpdate)
        end)
    end

    local function Watchdog()
        pcall(function()
            local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
            local curPawn = pc and pc:GetCurPawn()
            if isValid(curPawn) and _G._ESPTimerChar ~= curPawn then
                if _G._ESPTimerHandle and isValid(_G._ESPTimerChar) then
                    pcall(function() _G._ESPTimerChar:RemoveGameTimer(_G._ESPTimerHandle) end)
                end
                _G._ESPTimerHandle = nil
                StartESP_Watchdog(curPawn)
            elseif not _G._ESPTimerHandle then
                StartESP_Watchdog(curPawn)
            end
        end)
    end

    _G._ESPWatchdogHandle = Game:SetTimer(1.0, true, Watchdog)
    Watchdog()
end)



-- ============================================================
-- LUXURY MENU UI - FROM 1.lua (old game menu removed)
-- ============================================================

-- ============================================================
-- ============================================================
-- ============================================================
-- ============================================================
-- ============================================================
-- ============================================================
-- VIP MENU UI - 2 MENU + PNG BANNER + Snapline Sync
-- MOD DEVELOPER EXORTOP
-- ============================================================

-- ============================================================
-- VIP MENU UI - 2 MENU + PNG BANNER + Snapline Sync
-- ============================================================
-- VIP MENU UI - 2 MENU + PNG BANNER + Snapline Sync
-- MOD DEVELOPER EXORTOP
-- ============================================================

do
    local IsValid = function(obj) return obj and slua and slua.isValid and slua.isValid(obj) end
    local FLinearColor = import("LinearColor")
    local FVector2D = import("Vector2D")
    local FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")

    -- ===== PREMIUM GLASS PALETTE =====
    local C = {
        bg_panel        = FLinearColor(0.96, 0.96, 0.96, 0.75),
        bg_header       = FLinearColor(0.88, 0.88, 0.88, 0.80),
        bg_tab_active   = FLinearColor(0.35, 0.65, 1.0, 1.0),
        bg_tab_inactive = FLinearColor(0.85, 0.85, 0.85, 0.60),
        bg_row          = FLinearColor(0.85, 0.85, 0.85, 0.55),
        bg_row_alt      = FLinearColor(0.78, 0.78, 0.78, 0.50),
        bg_slider_row   = FLinearColor(0.75, 0.85, 1.0, 0.55),

        text_black      = FLinearColor(0.0, 0.0, 0.0, 1.0),
        text_blue       = FLinearColor(0.0, 0.35, 0.85, 1.0),
        text_light      = FLinearColor(1.0, 1.0, 1.0, 1.0),

        toggle_on       = FLinearColor(0.20, 0.85, 0.30, 1.0),
        toggle_off      = FLinearColor(0.60, 0.60, 0.60, 1.0),
        toggle_knob     = FLinearColor(1.0, 1.0, 1.0, 1.0),
        close_btn       = FLinearColor(0.9, 0.2, 0.2, 1.0),
        transparent     = FLinearColor(0, 0, 0, 0.01),
        border_blue     = FLinearColor(0.0, 0.35, 0.85, 0.6),

        btn_minus       = FLinearColor(0.9, 0.3, 0.3, 1.0),
        btn_plus        = FLinearColor(0.2, 0.8, 0.3, 1.0),
    }

    local M_W = 520
    local M_H = 620
    local ROW_H = 48
    local SLIDER_ROW_H = 56
    local HEADER_H = 80
    local TAB_H = 50

    _G.VIPConfig = _G.VIPConfig or {
        ESP_Enabled = true, ESP_HealthBar = true, ESP_Distance = true, ESP_WeaponIcon = false, ESP_Name = false,
        ESP_Line = false, ESP_Radar = false, ESP_TotalCount = false,
        AIM_Enabled = false, AIM_Bot = false, AIM_Silent = false,
        AIM_FOV = false, AIM_Smooth = false, AIM_Visible = false,
    }

    -- ===== CHAMS COLOR PRESETS =====
    local CHAMS_VIS_COLORS = {
        {name = "Cyan",     r = 0,   g = 5,   b = 5},
        {name = "Purple",   r = 5,   g = 0,   b = 5},
        {name = "Gold",     r = 5,   g = 5,   b = 0},
        {name = "Blue",     r = 0,   g = 2.5, b = 5},
        {name = "Red",      r = 5,   g = 0,   b = 0},
        {name = "Green",    r = 0,   g = 5,   b = 0},
        {name = "Pink",     r = 5,   g = 0,   b = 3},
        {name = "White",    r = 5,   g = 5,   b = 5},
        {name = "Orange",   r = 5,   g = 2.5, b = 0},
        {name = "Yellow",   r = 5,   g = 5,   b = 0},
    }
    local CHAMS_OCC_COLORS = {
        {name = "Purple",   r = 5,   g = 0,   b = 5},
        {name = "Cyan",     r = 0,   g = 5,   b = 5},
        {name = "Blue",     r = 0,   g = 2.5, b = 5},
        {name = "Red",      r = 5,   g = 0,   b = 0},
        {name = "Gold",     r = 5,   g = 5,   b = 0},
        {name = "Green",    r = 0,   g = 5,   b = 0},
        {name = "Pink",     r = 5,   g = 0,   b = 3},
        {name = "White",    r = 5,   g = 5,   b = 5},
        {name = "Orange",   r = 5,   g = 2.5, b = 0},
        {name = "Yellow",   r = 5,   g = 5,   b = 0},
    }

    _G.ChamsVisColorIndex = _G.ChamsVisColorIndex or 1
    _G.ChamsOccColorIndex = _G.ChamsOccColorIndex or 1

    -- ===== FEATURE MAP =====
    local FeatureMap = {
        ESP_Enabled = "_G.Mod_ESP_Enabled",
        ESP_Line = "_G.Mod_ESP_ShowSnapline",
        ESP_Distance = "_G.Mod_ESP_ShowDistance",
        ESP_Name = "_G.Mod_ESP_ShowName",
        ESP_HealthBar = "_G.Mod_ESP_ShowHealthBar",
        ESP_TotalCount = "_G.Mod_ESP_ShowPlayerCount",
        ESP_Radar = "_G.Mod_ESP_ShowTeamColor",
        ESP_WeaponIcon = "_G.Mod_ESP_ShowWeaponIcon",
        AIM_Enabled = "_G.Mod_Chams_Enabled",
        AIM_Bot = "_G.Mod_WeaponGlow_Enabled",
        AIM_Silent = "_G.Mod_UnlockFPS_Enabled",
        AIM_FOV = "_G.Mod_IpadView_Enabled",
        AIM_Smooth = "_G.Mod_WhiteBody_Enabled",
        AIM_Visible = "_G.Mod_CircleArrow_Enabled",
    }

    local function SyncFeature(key, value)
        local gVar = FeatureMap[key]
        if gVar then pcall(function() load(gVar .. " = " .. tostring(value))() end) end
    end

    local function GetFeatureState(key)
        local gVar = FeatureMap[key]
        if not gVar then return _G.VIPConfig[key] or false end
        local val = false
        pcall(function() val = load("return " .. gVar)() end)
        return val
    end

    -- ===== APPLY CHAMS COLOR =====
    local function ApplyChamsColor()
        pcall(function()
            local visCfg = CHAMS_VIS_COLORS[_G.ChamsVisColorIndex] or CHAMS_VIS_COLORS[1]
            local occCfg = CHAMS_OCC_COLORS[_G.ChamsOccColorIndex] or CHAMS_OCC_COLORS[1]

            local FLC = import("LinearColor")
            if not FLC then return end

            _G.ChamsColors = _G.ChamsColors or {}
            _G.ChamsColors.vis = FLC(visCfg.r, visCfg.g, visCfg.b, 1.0)
            _G.ChamsColors.occ = FLC(occCfg.r, occCfg.g, occCfg.b, 1.0)
            _G.ChamsColors.bVis = _G.ChamsColors.vis
            _G.ChamsColors.bOcc = _G.ChamsColors.occ

            local normR = visCfg.r / 5
            local normG = visCfg.g / 5
            local normB = visCfg.b / 5
            _G.SnapLineCustomColor = FLC(normR, normG, normB, 1.0)

            if _G.PlayerMapMarker then
                pcall(function()
                    _G.PlayerMapMarker.SnapLineColor = _G.SnapLineCustomColor
                end)
            end
        end)
    end

    -- ===== APPLY IPAD FOV =====
    local function ApplyIpadFov()
        pcall(function()
            local fov = tonumber(_G.IpadViewFOV) or 120
            if fov < 90 then fov = 90 end
            if fov > 190 then fov = 190 end
            _G.IpadViewFOV = fov

            local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
            if not slua.isValid(pc) then return end
            local char = pc:GetPlayerCharacterSafety()
            if not slua.isValid(char) then return end

            if char.ThirdPersonCameraComponent and slua.isValid(char.ThirdPersonCameraComponent) then
                char.ThirdPersonCameraComponent.FieldOfView = fov
            end

            local camMgr = pc.PlayerCameraManager
            if slua.isValid(camMgr) then
                if camMgr.UnlockFOV then camMgr:UnlockFOV() end
                if camMgr.SetFOV then camMgr:SetFOV(fov) end
            end
        end)
    end

    -- ===== HELPER: ESP SUB-FEATURES SYNC (sab yahi se chalega) =====
    local function _SyncESPState()
        local anyESP = _G.Mod_ESP_ShowSnapline
            or _G.Mod_ESP_ShowName
            or _G.Mod_ESP_ShowDistance
            or _G.Mod_ESP_ShowHealthBar
            or _G.Mod_ESP_ShowWeaponIcon
            or _G.Mod_ESP_ShowTeamColor

        _G.Mod_ESP_Enabled = anyESP

        if _G.PlayerMapMarker then
            if anyESP then
                if not _G.PlayerMapMarker.bActive then
                    pcall(_G.PlayerMapMarker.Start)
                end
            else
                if _G.PlayerMapMarker.bActive then
                    pcall(_G.PlayerMapMarker.Stop)
                end
            end
        end

        if _G.RedBoxOverlay then
            if anyESP and _G.Mod_ESP_ShowPlayerCount then
                if not _G.RedBoxOverlay.bActive then pcall(_G.RedBoxOverlay.Start) end
            else
                if _G.RedBoxOverlay.bActive then pcall(_G.RedBoxOverlay.Stop) end
            end
        end
    end

    -- ===== DIRECT FUNCTION TRIGGER =====
    local function ApplyFeature(key, state)
        SyncFeature(key, state)
        pcall(function()
            if key == "ESP_Enabled" then
                _G.Mod_ESP_Enabled = state
                _SyncESPState()
            elseif key == "ESP_Line" then
                _G.Mod_ESP_ShowSnapline = state
                _SyncESPState()
            elseif key == "ESP_HealthBar" then
                _G.Mod_ESP_ShowHealthBar = state
                _SyncESPState()
            elseif key == "ESP_Name" then
                _G.Mod_ESP_ShowName = state
                _SyncESPState()
            elseif key == "ESP_Distance" then
                _G.Mod_ESP_ShowDistance = state
                _SyncESPState()
            elseif key == "ESP_WeaponIcon" then
                _G.Mod_ESP_ShowWeaponIcon = state
                _SyncESPState()
            elseif key == "ESP_TotalCount" then
                _G.Mod_ESP_ShowPlayerCount = state
                if _G.RedBoxOverlay then
                    if state then
                        if not _G.RedBoxOverlay.bActive then pcall(_G.RedBoxOverlay.Start) end
                    else
                        if _G.RedBoxOverlay.bActive then pcall(_G.RedBoxOverlay.Stop) end
                    end
                end
            elseif key == "ESP_Radar" then
                _G.Mod_ESP_ShowTeamColor = state
                if state then
                    if _G.ESP and not _G.ESP.bActive then
                        pcall(_G.ESP.Start)
                    end
                else
                    if _G.ESP and _G.ESP.bActive then
                        pcall(function()
                            _G.ESP.bActive = false
                            _G.ESP.ResetWidgets()
                        end)
                    end
                end
            elseif key == "AIM_Enabled" then
                _G.Mod_Chams_Enabled = state
            elseif key == "AIM_Bot" then
                _G.Mod_WeaponGlow_Enabled = state
            elseif key == "AIM_Silent" then
                _G.Mod_UnlockFPS_Enabled = state
                if state then
                    pcall(function()
                        local KSL = import("KismetSystemLibrary")
                        local world = slua.getWorld()
                        if KSL and world then
                            KSL.ExecuteConsoleCommand(world, "t.MaxFPS 165")
                            KSL.ExecuteConsoleCommand(world, "r.FrameRateLimit 165")
                        end
                    end)
                end
            elseif key == "AIM_FOV" then
                _G.Mod_IpadView_Enabled = state
                if state then ApplyIpadFov() end
            elseif key == "AIM_Smooth" then
                _G.Mod_WhiteBody_Enabled = state
            elseif key == "AIM_Visible" then
                _G.Mod_CircleArrow_Enabled = state
                if state then
                    if not _G.CircleArrowESP then InitCircleArrowESP() end
                    if _G.CircleArrowESP and not _G.CircleArrowESP.bActive then
                        pcall(_G.CircleArrowESP.Start)
                    end
                else
                    if _G.CircleArrowESP and _G.CircleArrowESP.bActive then
                        pcall(_G.CircleArrowESP.Stop)
                    end
                end
            end
        end)
    end


    for cfgKey, _ in pairs(FeatureMap) do
        local state = GetFeatureState(cfgKey)
        _G.VIPConfig[cfgKey] = state
    end

    pcall(ApplyChamsColor)

    local parentCanvas = nil
    local bgPanel = nil
    local allWidgets = {}
    local toggleRows = {}
    local floatItem = nil
    local isMenuOpen = false
    local menuBuilt = false

    local function GetCanvas()
        if parentCanvas and Game:IsValid(parentCanvas) then return parentCanvas end
        parentCanvas = nil
        pcall(function()
            local InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
            local MainUI = InGameUITools.GetMainControlBaseUI()
            if not MainUI or not Game:IsValid(MainUI) then return end
            if MainUI.CanvasPanel_0 and Game:IsValid(MainUI.CanvasPanel_0) then parentCanvas = MainUI.CanvasPanel_0
            elseif MainUI.CanvasPanel_42 and Game:IsValid(MainUI.CanvasPanel_42) then parentCanvas = MainUI.CanvasPanel_42 end
        end)
        return parentCanvas
    end

    local function MakeBtn(parent, x, y, w, h, z, onClick)
        local btn = nil
        pcall(function()
            btn = CGame:NewObjectFromPath("/Script/UMG.Button", parent)
            if btn and slua.isValid(btn) then
                pcall(function() btn:SetColorAndOpacity(C.transparent) end)
                pcall(function() btn:SetBackgroundColor(C.transparent) end)
                pcall(function() btn:SetWidgetVisibility(UEnums.ESlateVisibility.Visible) end)
                local slot = parent:AddChildToCanvas(btn)
                if slot then
                    slot:SetAutoSize(false)
                    slot:SetPosition(FVector2D(x, y))
                    slot:SetSize(FVector2D(w, h))
                    slot:SetZOrder(z or 900)
                end
                if onClick then
                    pcall(function() if btn.OnClicked then btn.OnClicked:Add(function() pcall(onClick) end) end end)
                end
            end
        end)
        table.insert(allWidgets, btn)
        return btn
    end

    local function Layer(parent, x, y, w, h, color, z)
        local b = nil
        pcall(function()
            b = CGame:NewObjectFromPath("/Script/UMG.Border", parent)
            if b and slua.isValid(b) then
                b:SetBrushColor(color)
                b:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                local slot = parent:AddChildToCanvas(b)
                if slot then
                    slot:SetAutoSize(false)
                    slot:SetPosition(FVector2D(x, y))
                    slot:SetSize(FVector2D(w, h))
                    slot:SetZOrder(z or 0)
                end
            end
        end)
        table.insert(allWidgets, b)
        return b
    end

    local function Text(parent, txt, x, y, size, color, z, alignX, alignY)
        local t = nil
        pcall(function()
            t = CGame:NewObjectFromPath("/Script/UMG.TextBlock", parent)
            if t and slua.isValid(t) then
                t:SetText(txt)
                if FSlateColor then t:SetColorAndOpacity(FSlateColor(color))
                else t:SetColorAndOpacity(color) end
                if t.Font then local f = t.Font f.Size = size t.Font = f end
                t:SetRenderTransformPivot(FVector2D(alignX or 0.5, alignY or 0.5))
                t:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                local slot = parent:AddChildToCanvas(t)
                if slot then
                    slot:SetAutoSize(true)
                    slot:SetAlignment(FVector2D(alignX or 0.5, alignY or 0.5))
                    slot:SetPosition(FVector2D(x, y))
                    slot:SetZOrder(z or 100)
                end
            end
        end)
        table.insert(allWidgets, t)
        return t
    end

    local function UpdateToggleRow(rowData)
        if not rowData then return end
        local state = GetFeatureState(rowData.key)
        _G.VIPConfig[rowData.key] = state
        if rowData.track and IsValid(rowData.track) then
            pcall(function() rowData.track:SetBrushColor(state and C.toggle_on or C.toggle_off) end)
        end
        if rowData.knobSlot then
            pcall(function()
                local knobX = state and (rowData.toggleX + rowData.toggleW - rowData.knobSize - 2) or (rowData.toggleX + 2)
                rowData.knobSlot:SetPosition(FVector2D(knobX, rowData.toggleY + 2))
            end)
        end
    end

    local function MakeToggleRow(parent, label, x, y, w, h, toggleKey, isZebra)
        local state = GetFeatureState(toggleKey)
        _G.VIPConfig[toggleKey] = state
        local rowBg = isZebra and C.bg_row_alt or C.bg_row
        local rowData = { key = toggleKey }

        rowData.bg = Layer(parent, x, y, w, h, rowBg, 200)
        rowData.label = Text(parent, label, x + 16, y + h * 0.5, 16, C.text_black, 300, 0, 0.5)

        local toggleW = 48
        local toggleH = 24
        local toggleX = x + w - toggleW - 16
        local toggleY = y + h * 0.5 - toggleH * 0.5
        local knobSize = toggleH - 4

        rowData.toggleX = toggleX
        rowData.toggleY = toggleY
        rowData.toggleW = toggleW
        rowData.toggleH = toggleH
        rowData.knobSize = knobSize

        rowData.track = Layer(parent, toggleX, toggleY, toggleW, toggleH, state and C.toggle_on or C.toggle_off, 300)
        local knobX = state and (toggleX + toggleW - knobSize - 2) or (toggleX + 2)
        local knobY = toggleY + 2

        pcall(function()
            local k = CGame:NewObjectFromPath("/Script/UMG.Border", parent)
            if k and slua.isValid(k) then
                k:SetBrushColor(C.toggle_knob)
                k:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                local slot = parent:AddChildToCanvas(k)
                if slot then
                    slot:SetAutoSize(false)
                    slot:SetPosition(FVector2D(knobX, knobY))
                    slot:SetSize(FVector2D(knobSize, knobSize))
                    slot:SetZOrder(301)
                end
                rowData.knob = k
                rowData.knobSlot = slot
            end
        end)

        rowData.btn = MakeBtn(parent, x, y, w, h, 900, function()
            local newState = not _G.VIPConfig[toggleKey]
            _G.VIPConfig[toggleKey] = newState
            ApplyFeature(toggleKey, newState)
            UpdateToggleRow(rowData)
        end)

        table.insert(toggleRows, rowData)
        return rowData
    end

    -- ============================================================
    -- SIMPLE SLIDER ROW (1 Click = 1 Change)
    -- ============================================================
    local function MakeSliderRow(parent, label, x, y, w, h, getDisplayText, onMinus, onPlus, isZebra)
        local rowBg = isZebra and C.bg_row_alt or C.bg_slider_row
        local rowData = { key = label, isSlider = true }

        rowData.bg = Layer(parent, x, y, w, h, rowBg, 200)
        rowData.label = Text(parent, label, x + 16, y + h * 0.5 - 8, 15, C.text_black, 300, 0, 0.5)

        local valText = getDisplayText()
        rowData.valueText = Text(parent, valText, x + 16, y + h * 0.5 + 10, 13, C.text_blue, 300, 0, 0.5)

        local function RefreshText()
            if rowData.valueText and IsValid(rowData.valueText) then
                pcall(function() rowData.valueText:SetText(getDisplayText()) end)
            end
        end

        local btnW = 40
        local btnH = 36
        local btnY = y + h * 0.5 - btnH * 0.5
        local minusX = x + w - 100
        local plusX = x + w - 52

        Layer(parent, minusX, btnY, btnW, btnH, C.btn_minus, 299)
        Text(parent, "-", minusX + btnW * 0.5, btnY + btnH * 0.5, 26, C.text_light, 400, 0.5, 0.5)
        MakeBtn(parent, minusX, btnY, btnW, btnH, 900, function()
            onMinus()
            RefreshText()
        end)

        Layer(parent, plusX, btnY, btnW, btnH, C.btn_plus, 299)
        Text(parent, "+", plusX + btnW * 0.5, btnY + btnH * 0.5, 24, C.text_light, 400, 0.5, 0.5)
        MakeBtn(parent, plusX, btnY, btnW, btnH, 900, function()
            onPlus()
            RefreshText()
        end)

        table.insert(toggleRows, rowData)
        return rowData
    end

        local function BuildMenu()
        if menuBuilt and bgPanel and IsValid(bgPanel) then
            pcall(function() bgPanel:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
            return
        end

        local canvas = GetCanvas()
        if not canvas then return end

        pcall(function()
            bgPanel = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", canvas)
            if bgPanel and slua.isValid(bgPanel) then
                local slot = canvas:AddChildToCanvas(bgPanel)
                if slot then
                    slot:SetAutoSize(false)
                    slot:SetZOrder(10000)
                    slot:SetAnchors(FAnchors(1, 0, 1, 0))
                    slot:SetAlignment(FVector2D(1, 0))
                    slot:SetPosition(FVector2D(-10, 20))
                    slot:SetSize(FVector2D(M_W, M_H))
                end
            end
        end)
        if not bgPanel or not slua.isValid(bgPanel) then return end

        Layer(bgPanel, 0, 0, M_W, M_H, C.bg_panel, 1)
        Layer(bgPanel, 0, 0, M_W, 2, C.border_blue, 2)
        Layer(bgPanel, 0, M_H - 2, M_W, 2, C.border_blue, 2)
        Layer(bgPanel, 0, 0, 2, M_H, C.border_blue, 2)
        Layer(bgPanel, M_W - 2, 0, 2, M_H, C.border_blue, 2)

        Layer(bgPanel, 2, 2, M_W - 4, HEADER_H - 4, C.bg_header, 3)
        Text(bgPanel, "REDMAGIX-OFFICIAL", M_W * 0.5, HEADER_H * 0.5, 26, C.text_black, 400, 0.5, 0.5)
        Layer(bgPanel, 20, 20, 12, 12, FLinearColor(1, 0.4, 0.4), 5)
        Layer(bgPanel, 40, 20, 12, 12, FLinearColor(1, 0.8, 0.2), 5)
        Layer(bgPanel, 60, 20, 12, 12, FLinearColor(0.2, 0.9, 0.2), 5)

        MakeBtn(bgPanel, M_W - 40, 20, 30, 30, 900, function()
            isMenuOpen = false
            pcall(function() bgPanel:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
        end)
        Text(bgPanel, "X", M_W - 25, 35, 20, C.close_btn, 400, 0.5, 0.5)

        local tabY = HEADER_H
        local tabNames = {"ESP", "WALL HACK"}
        local tabW = M_W / #tabNames
        Layer(bgPanel, 0, tabY, M_W, TAB_H, C.bg_panel, 1)

        local tabWidgets = {}
        local contentPanels = {}

        local function SwitchTab(tabIndex)
            for i = 1, #tabWidgets do
                local tw = tabWidgets[i]
                if tw then
                    local isActive = (i == tabIndex)
                    if tw.bg and IsValid(tw.bg) then
                        tw.bg:SetBrushColor(isActive and C.bg_tab_active or C.bg_tab_inactive)
                    end
                    if tw.txt and IsValid(tw.txt) then
                        local color = isActive and C.text_light or C.text_black
                        if FSlateColor then tw.txt:SetColorAndOpacity(FSlateColor(color))
                        else tw.txt:SetColorAndOpacity(color) end
                    end
                end
            end
            for i = 1, #contentPanels do
                if contentPanels[i] and IsValid(contentPanels[i]) then
                    contentPanels[i]:SetWidgetVisibility(i == tabIndex and UEnums.ESlateVisibility.SelfHitTestInvisible or UEnums.ESlateVisibility.Collapsed)
                end
            end
        end

        for i, tabName in ipairs(tabNames) do
            local tx = (i - 1) * tabW
            local isActive = (i == 1)
            local tabBg = Layer(bgPanel, tx + 4, tabY + 4, tabW - 8, TAB_H - 8, isActive and C.bg_tab_active or C.bg_tab_inactive, 3)
            local tabTxt = Text(bgPanel, tabName, tx + tabW * 0.5, tabY + TAB_H * 0.5, 16, isActive and C.text_light or C.text_black, 400, 0.5, 0.5)
            local tabIdx = i
            MakeBtn(bgPanel, tx, tabY, tabW, TAB_H, 900, function() SwitchTab(tabIdx) end)
            tabWidgets[i] = { bg = tabBg, txt = tabTxt }
        end

        local contentStartY = tabY + TAB_H + 10
        local contentX = 12
        local contentW = M_W - 24

        -- ESP TAB — SAB FEATURES
        local espPanel = nil
        pcall(function()
            espPanel = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", bgPanel)
            if espPanel and slua.isValid(espPanel) then
                local slot = bgPanel:AddChildToCanvas(espPanel)
                if slot then
                    slot:SetAutoSize(false)
                    slot:SetPosition(FVector2D(0, contentStartY))
                    slot:SetSize(FVector2D(M_W, M_H - contentStartY - 40))
                    slot:SetZOrder(10)
                end
                espPanel:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            end
        end)
        contentPanels[1] = espPanel
        if not espPanel or not slua.isValid(espPanel) then espPanel = bgPanel end

        local espY = 10
        Text(espPanel, "ESP OPTIONS", contentX + contentW * 0.5, espY, 17, C.text_blue, 400, 0.5, 0.5)
        espY = espY + 32

        local espOptions = {
            {label = "ANIME BOX ESP",  key = "ESP_Radar"},
            {label = "ESP LINE",       key = "ESP_Line"},
            {label = "ESP HEALTH",     key = "ESP_HealthBar"},
            {label = "ESP NAME",       key = "ESP_Name"},
            {label = "ESP DISTANCE",   key = "ESP_Distance"},
            {label = "ESP WEAPON",     key = "ESP_WeaponIcon"},
            {label = "PLAYER COUNT",   key = "ESP_TotalCount"},
        }

        for i, opt in ipairs(espOptions) do
            MakeToggleRow(espPanel, opt.label, contentX, espY, contentW, ROW_H, opt.key, i % 2 == 0)
            espY = espY + ROW_H + 4
        end

        -- MOD TAB (NOW NAMED WALL HACK)
        local modPanel = nil
        pcall(function()
            modPanel = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", bgPanel)
            if modPanel and slua.isValid(modPanel) then
                local slot = bgPanel:AddChildToCanvas(modPanel)
                if slot then
                    slot:SetAutoSize(false)
                    slot:SetPosition(FVector2D(0, contentStartY))
                    slot:SetSize(FVector2D(M_W, M_H - contentStartY - 40))
                    slot:SetZOrder(10)
                end
                modPanel:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            end
        end)
        contentPanels[2] = modPanel
        if not modPanel or not slua.isValid(modPanel) then modPanel = bgPanel end

        local modY = 10
        Text(modPanel, "WALL HACK", contentX + contentW * 0.5, modY, 17, C.text_blue, 400, 0.5, 0.5)
        modY = modY + 32

        MakeToggleRow(modPanel, "WALL ESP (CHAMS)", contentX, modY, contentW, ROW_H, "AIM_Enabled", false)
        modY = modY + ROW_H + 4

        MakeSliderRow(modPanel, "CHAMS VISIBLE COLOR", contentX, modY, contentW, SLIDER_ROW_H,
            function()
                local cfg = CHAMS_VIS_COLORS[_G.ChamsVisColorIndex] or CHAMS_VIS_COLORS[1]
                return "Color: " .. cfg.name .. "  (" .. _G.ChamsVisColorIndex .. "/" .. #CHAMS_VIS_COLORS .. ")"
            end,
            function()
                _G.ChamsVisColorIndex = _G.ChamsVisColorIndex - 1
                if _G.ChamsVisColorIndex < 1 then _G.ChamsVisColorIndex = #CHAMS_VIS_COLORS end
                ApplyChamsColor()
            end,
            function()
                _G.ChamsVisColorIndex = _G.ChamsVisColorIndex + 1
                if _G.ChamsVisColorIndex > #CHAMS_VIS_COLORS then _G.ChamsVisColorIndex = 1 end
                ApplyChamsColor()
            end,
            true)
        modY = modY + SLIDER_ROW_H + 4

        MakeSliderRow(modPanel, "CHAMS WALL COLOR", contentX, modY, contentW, SLIDER_ROW_H,
            function()
                local cfg = CHAMS_OCC_COLORS[_G.ChamsOccColorIndex] or CHAMS_OCC_COLORS[1]
                return "Color: " .. cfg.name .. "  (" .. _G.ChamsOccColorIndex .. "/" .. #CHAMS_OCC_COLORS .. ")"
            end,
            function()
                _G.ChamsOccColorIndex = _G.ChamsOccColorIndex - 1
                if _G.ChamsOccColorIndex < 1 then _G.ChamsOccColorIndex = #CHAMS_OCC_COLORS end
                ApplyChamsColor()
            end,
            function()
                _G.ChamsOccColorIndex = _G.ChamsOccColorIndex + 1
                if _G.ChamsOccColorIndex > #CHAMS_OCC_COLORS then _G.ChamsOccColorIndex = 1 end
                ApplyChamsColor()
            end,
            false)
        modY = modY + SLIDER_ROW_H + 4

        MakeToggleRow(modPanel, "IPAD VIEW", contentX, modY, contentW, ROW_H, "AIM_FOV", true)
        modY = modY + ROW_H + 4

        MakeSliderRow(modPanel, "IPAD VIEW FOV", contentX, modY, contentW, SLIDER_ROW_H,
            function() return "FOV: " .. tostring(_G.IpadViewFOV or 120) end,
            function()
                _G.IpadViewFOV = (_G.IpadViewFOV or 120) - 1
                if _G.IpadViewFOV < 90 then _G.IpadViewFOV = 90 end
                ApplyIpadFov()
            end,
            function()
                _G.IpadViewFOV = (_G.IpadViewFOV or 120) + 1
                if _G.IpadViewFOV > 190 then _G.IpadViewFOV = 190 end
                ApplyIpadFov()
            end,
            false)
        modY = modY + SLIDER_ROW_H + 4

        local modOptions = {
            {label = "WEAPON GLOW",        key = "AIM_Bot"},
            {label = "ROUND GREEN CIRCLE", key = "AIM_Visible"},
        }
        for i, opt in ipairs(modOptions) do
            MakeToggleRow(modPanel, opt.label, contentX, modY, contentW, ROW_H, opt.key, i % 2 == 0)
            modY = modY + ROW_H + 4
        end

        Layer(bgPanel, 2, M_H - 32, M_W - 4, 30, C.bg_header, 5)
        Text(bgPanel, "DEVELOPER- DevLet", M_W * 0.5, M_H - 15, 12, C.text_blue, 400, 0.5, 0.5)

        pcall(ApplyChamsColor)

        menuBuilt = true
        isMenuOpen = true
    end


    local function CreateFloat()
        if floatItem and floatItem.btn and IsValid(floatItem.btn) then return end
        floatItem = nil
        pcall(function()
            local canvas = GetCanvas()
            if not canvas then return end

            floatItem = {}
            local fX = 20
            local fY = 15
            local fW = 110
            local fH = 45

            floatItem.s8 = Layer(canvas, fX, fY, fW, fH, FLinearColor(0.96, 0.96, 0.96, 0.75), 11902)
            Layer(canvas, fX, fY, fW, 4, C.bg_tab_active, 11903)
            Layer(canvas, fX, fY, fW, 2, C.border_blue, 11904)
            Layer(canvas, fX, fY + fH - 2, fW, 2, C.border_blue, 11904)

            pcall(function()
                floatItem.text = CGame:NewObjectFromPath("/Script/UMG.TextBlock", canvas)
                if floatItem.text and slua.isValid(floatItem.text) then
                    floatItem.text:SetText("MENU")
                    if FSlateColor then floatItem.text:SetColorAndOpacity(FSlateColor(C.text_black))
                    else floatItem.text:SetColorAndOpacity(C.text_black) end
                    if floatItem.text.Font then local f = floatItem.text.Font f.Size = 20 floatItem.text.Font = f end
                    floatItem.text:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                    local slot = canvas:AddChildToCanvas(floatItem.text)
                    if slot then
                        slot:SetAutoSize(true)
                        slot:SetAlignment(FVector2D(0.5, 0.5))
                        slot:SetPosition(FVector2D(fX + fW * 0.5, fY + fH * 0.5))
                        slot:SetZOrder(12001)
                    end
                end
            end)

            pcall(function()
                floatItem.btn = CGame:NewObjectFromPath("/Script/UMG.Button", canvas)
                if floatItem.btn and slua.isValid(floatItem.btn) then
                    pcall(function() floatItem.btn:SetColorAndOpacity(C.transparent) end)
                    pcall(function() floatItem.btn:SetBackgroundColor(C.transparent) end)
                    pcall(function() floatItem.btn:SetWidgetVisibility(UEnums.ESlateVisibility.Visible) end)
                    local slot = canvas:AddChildToCanvas(floatItem.btn)
                    if slot then
                        slot:SetAutoSize(false)
                        slot:SetPosition(FVector2D(fX, fY))
                        slot:SetSize(FVector2D(fW, fH))
                        slot:SetZOrder(12002)
                    end
                    pcall(function()
                        if floatItem.btn.OnClicked then
                            floatItem.btn.OnClicked:Add(function()
                                pcall(function()
                                    isMenuOpen = not isMenuOpen
                                    if isMenuOpen then
                                        if menuBuilt and bgPanel and IsValid(bgPanel) then
                                            bgPanel:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                                        else
                                            BuildMenu()
                                        end
                                    else
                                        if bgPanel and IsValid(bgPanel) then
                                            bgPanel:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                                        end
                                    end
                                end)
                            end)
                        end
                    end)
                end
            end)
        end)
    end

    pcall(function()
        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if pc and IsValid(pc) then
            CreateFloat()
            pc:AddGameTimer(3, true, function()
                if not floatItem or not floatItem.btn or not IsValid(floatItem.btn) then
                    floatItem = nil
                    CreateFloat()
                end
            end)
        end
    end)
end
-- ==============================================================================

-- ============================ END SKIN MOD SYSTEM ============================

function BRPlayerCharacterBase:ctor()
end

function BRPlayerCharacterBase:_PostConstruct()
  BRPlayerCharacterBase.__super._PostConstruct(self)
  self:InitAddSpecialMoveInfo()
  self.bCanNearDeathGiveup = true
  print(bWriteLog and "BRPlayerCharacterBase:_PostConstruct bCanNearDeathGiveup true")
end

function BRPlayerCharacterBase:ReceiveBeginPlay()
  BRPlayerCharacterBase.__super.ReceiveBeginPlay(self)
  self:AddControlEvent(self, "MovementModeChangedDelegate", self.HandleOnMovementModeChangedNew, self)
  if self:HasAuthority() and self:CheckAddCheckFallingDistanceComponent() then
    local CheckFallingDistanceComponent_C = import("CheckFallingDistanceComponent")
    if slua.isValid(CheckFallingDistanceComponent_C) and not slua.isValid(self:GetComponentByClass(CheckFallingDistanceComponent_C)) then
      print(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay Add CheckFallingDistanceComponent")
      Game:AddComponent(CheckFallingDistanceComponent_C, self, "CheckFallingDistanceComponent")
    end
  end
  if slua.isValid(self.STCharacterMovement) then
    self.STCharacterMovement.bPositiveBlowUp = true
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy then
    self:AddControlEvent(self, "OnPawnStateDisabled", self.OnPawnStateChange, self)
    self:AddControlEvent(self, "OnPawnStateEnabled", self.OnPawnStateChange, self)
    self:AddControlEventConditionOnly(self, "OnAttrChangeEventDelegate", {
      AttrName = {
        "bCanSelfRescue"
      }
    }, self.CharacterAttrChangeEvent, self)
  end
  if Client then
    printf(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay, PlayerKey:%u ", self.PlayerKey)
    GameplayData.AddCharacter(self.Object)
  else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, {
      [1] = "FinishedState"
    }, self.HandleFinishedState, self)
  end
end

function BRPlayerCharacterBase:CharacterAttrChangeEvent(uPawn, AttrName, AttrVal)
  BRPlayerCharacterBase.__super.CharacterAttrChangeEvent(self, uPawn, AttrName, AttrVal)
  if self.Object ~= uPawn then
    return
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and AttrName == "bCanSelfRescue" then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_CanSelfRescue", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:OnPawnStateChange(PawnState)
  print("BRPlayerCharacterBase:OnPawnStateChange:", PawnState)
  if PawnState == EPawnState.SwitchPP then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_FPPModeChange", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:HandleFinishedState()
  print(bWriteLog and "BRPlayerCharacterBase:HandleFinishedState", self.STCharacterMovement)
  if slua.isValid(self.STCharacterMovement) and self.STCharacterMovement.SetDynamicSimpleQueryConfigDisable then
    local EDynamicSimpleQueryConfigDisableMask = import("EDynamicSimpleQueryConfigDisableMask")
    self.STCharacterMovement:SetDynamicSimpleQueryConfigDisable(EDynamicSimpleQueryConfigDisableMask.Bit0, true)
  end
end

function BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent()
  if CGameMode and CGameMode.GameModeType and CGameState and CGameState.GameModeID then
    local GameModeType = CGameMode.GameModeType
    local GameModeID = tonumber(CGameState.GameModeID)
    local bModeTypeSatisfy = GameModeType == EGameModeType.ETypicalGameMode or GameModeType == EGameModeType.EFourInOneGameMode or GameModeType == EGameModeType.EHeavyWeaponGameMode
    local bModeIDSatisfy = not MatchModeIds[GameModeID]
    print(bWriteLog and bWriteLog and "BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent:", GameModeType, GameModeID, bModeTypeSatisfy, bModeIDSatisfy)
    return bModeTypeSatisfy and bModeIDSatisfy
  end
  return false
end

function BRPlayerCharacterBase:LuaHandleParachuteStateChanged(LastParachuteState, NewParachuteState)
  BRPlayerCharacterBase.__super.LuaHandleParachuteStateChanged(self, LastParachuteState, NewParachuteState)
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if slua.isValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if NewParachuteState == EParachuteState.PS_Opening then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.SatrtCheckShowParachuteCloseUI then
          uCurrentPlayerControl.CheckParachuteOpenFeature:SatrtCheckShowParachuteCloseUI()
        end
      elseif NewParachuteState == EParachuteState.PS_None then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.RecoverParachuteOpenParam then
          uCurrentPlayerControl.CheckParachuteOpenFeature:RecoverParachuteOpenParam()
        end
        if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then
          uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState()
        end
      end
    end
  end
end

function BRPlayerCharacterBase:OnLanded()
  printf("BRPlayerCharacterBase:OnLanded PlayerKey:%d", self.PlayerKey)
  if self.HandleOnLanded then
    self:HandleOnLanded(-1)
  end
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if slua.isValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then
        uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState()
      end
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ResetCheckShowUI then
        uCurrentPlayerControl.CheckParachuteOpenFeature:ResetCheckShowUI()
      end
    end
  end
end

function BRPlayerCharacterBase:ReceiveEndPlay(EndPlayReason)
  BRPlayerCharacterBase.__super.ReceiveEndPlay(self, EndPlayReason)
  if Client then
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:IsWarGameMode()
  local uGameState = GameplayData:GetGameState()
  if slua.isValid(uGameState) and Game:IsClassOf(uGameState, STExtraGameStateBase) then
    return uGameState.GameModeType == EGameModeType.EWarGameMode
  else
    return false
  end
end

function BRPlayerCharacterBase:BPOnRecycled()
  print(bWriteLog and string.format("%s BPOnRecycled()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
  end
end

function BRPlayerCharacterBase:BPOnRespawned()
  print(bWriteLog and string.format("%s BPOnRespawned()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
  end
end

function BRPlayerCharacterBase:ReceiveOnRecycle()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnRecycle()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ReceiveOnSpawn()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnSpawn()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.AddCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ResetMeshRelativeLocationAndRotation()
  if Game:IsValid(self.Object) and Game:IsValid(self.Mesh) then
    local uDefaultMeshRot = FRotator(0, -90, 0)
    local uDefaultMeshRelativeLoc = FVector(0, 0, 0)
    if self.Mesh.K2_SetRelativeRotation then
      self.Mesh:K2_SetRelativeRotation(uDefaultMeshRot, false, nil, false)
    end
    self:CacheInitialMeshOffset(uDefaultMeshRelativeLoc, uDefaultMeshRot)
    local vRelativeRot = self.Mesh.RelativeRotation
    local vBaseRotationOffset = self.BaseRotationOffset
    local vBaseRotation = Game:QuatToRotator(vBaseRotationOffset)
    print(bWriteLog and bWriteLog and string.format("%s ResetMeshRelativeLocationAndRotation() Mesh.RelativeRotation: %s %s %s   Pawn.BaseRotationOffset:%s %s %s ", Game:GetPlainName(self.Object), tostring(vRelativeRot.Pitch), tostring(vRelativeRot.Yaw), tostring(vRelativeRot.Roll), tostring(vBaseRotation.Pitch), tostring(vBaseRotation.Yaw), tostring(vBaseRotation.Roll)))
  end
end

function BRPlayerCharacterBase:HandleOnMovementModeChangedNew()
  print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged11")
  if Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Swimming and self:CheckBaseIsMoveable() then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged22")
    self.CharacterMovement:SetBase(nil, "", true)
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Walking and UIManager.UI_Config_InGame.ParachuteOpenUI then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChangedNew CloseUI")
    UIManager.CloseUI(UIManager.UI_Config_InGame.ParachuteOpenUI)
  end
end

function BRPlayerCharacterBase:BPOnMissPlayerDamageRecord()
end

function BRPlayerCharacterBase:PreAttachedToVehicle()
  local IsDS = UKismetSystemLibrary.IsDedicatedServer(self)
  if not IsDS then
    return
  end
  local MainPlayerController = self:GetPlayerControllerSafety()
  if not slua.isValid(MainPlayerController) then
    return
  end
  local CharacterAvatarComp2_BP = self.CharacterAvatarComp2_BP
  if not slua.isValid(CharacterAvatarComp2_BP) then
    return
  end
  local CommerAvatarDataUtil = require("GameLua.Activity.Commercialize.GamePlay.CommerAvatarDataUtil")
  local changedVehicleId = CommerAvatarDataUtil:ChangeVehicleSkinByClothes(MainPlayerController, CharacterAvatarComp2_BP)
  local ESTExtraVehicleShapeType = import("ESTExtraVehicleShapeType")
  if changedVehicleId then
    local UAvatarUtils = import("AvatarUtils")
    if UAvatarUtils.GetVehicleShapeBySkinID(changedVehicleId) == ESTExtraVehicleShapeType.VST_Horse then
      local uCurPlayerState = self:GetPlayerStateSafety()
      if slua.isValid(uCurPlayerState) then
        print(bWriteLog and "  BRPlayerCharacterBase:PreAttachedToVehicle. changedVehicleId: " .. tostring(changedVehicleId))
        uCurPlayerState:AddGeneralCount(468, 1, false)
      end
    end
  end
end

function BRPlayerCharacterBase:ParachuteJump()
  local uPlayerController = self:GetControllerSafety()
  if slua.isValid(uPlayerController) then
    if not self:GetEnsure() then
      if uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteJump and uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteOpen then
        self:SwitchPoseState(ESTEPoseState.Stand, true, true, true, false)
        uPlayerController:ReInitParachuteItem()
        uPlayerController:ServerChangeStatePC(EStateType.State_ParachuteJump)
      end
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump over")
    else
      EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_AI_CALL_PARACHUTE_JUMP, self.Object)
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump AI JUMP over, Loc=", tostring(self:K2_GetActorLocation():ToString()))
    end
  end
end

function BRPlayerCharacterBase:OnMovementBaseChangedEvent(uCharacter, uNewMovementBase, uOldMovementBase)
  if uCharacter ~= self.Object then
    return
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase:OnMovementBaseChangedEvent %s, Base: %s -> %s", uCharacter, uOldMovementBase, uNewMovementBase))
  local MedievalCrane = self:GetMedievalCraneFromBase(uNewMovementBase)
  if MedievalCrane and MedievalCrane.AddCharacter then
    MedievalCrane:AddCharacter(self.Object)
  else
    MedievalCrane = self:GetMedievalCraneFromBase(uOldMovementBase)
    if MedievalCrane and MedievalCrane.RemoveCharacter then
      MedievalCrane:RemoveCharacter(self.Object)
    end
  end
end

function BRPlayerCharacterBase:GetMedievalCraneFromBase(Base)
  if not slua.isValid(Base) or not Base.GetOwner then
    return
  end
  local Lifter = Base:GetOwner()
  if not slua.isValid(Lifter) then
    return
  end
  if not Lifter.AddCharacter then
    return
  end
  return Lifter
end

function BRPlayerCharacterBase:CheckForbidFlaregun()
  local uPlayerState = self:GetPlayerStateSafety()
  if not slua.isValid(uPlayerState) then
    return false
  end
  if uPlayerState.CanUseFlaregun == false and self:IsLocallyControlled() then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:DisplayGameTipWithMsgID(48532)
    end
  end
  return not uPlayerState.CanUseFlaregun
end

function BRPlayerCharacterBase:ServerRPC_NearDeathGiveupRescue()
  self:HandleNearDeathGiveupRescue()
end

function BRPlayerCharacterBase:HandleNearDeathGiveupRescue()
  local uNearDeathComp = self.NearDeatchComponent
  if self:IsNearDeath() and slua.isValid(uNearDeathComp) and self.bCanNearDeathGiveup == true then
    local uPlayerState = self:GetPlayerStateSafety()
    if slua.isValid(uPlayerState) then
      uPlayerState:AddGeneralCount(1613, 1, false)
    end
    uNearDeathComp:TriggerGotoDieExplictly(self.Object)
  end
end

function BRPlayerCharacterBase:RPC_Server_GmPlayAction(actionId)
  log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction.  actionId: " .. tostring(actionId))
  if USTExtraBlueprintFunctionLibrary.IsDevelopment() then
    log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction. IsDevelopment actionId: " .. tostring(actionId))
    self:MulticastRPC_GmPlayAction(actionId)
  end
end

function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(actionId)
  if not Client then
    return
  end
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction.  actionId: " .. tostring(actionId))
  local uPlayEmoteComp = self:GetPlayEmoteComponent()
  if not slua.isValid(uPlayEmoteComp) then
    return
  end
  local LogFilter = require("common.log_filter")
  LogFilter.SetLogTreeEnable(true)
  local animCfg = CDataTable.GetTableData("EmoteBPTable", actionId)
  if not animCfg then
    return
  end
  local handlePath = animCfg.Path
  local EmoteHandleAsset = slua.loadObject(handlePath)
  local assetsArray = slua.Array(UEnums.EPropertyClass.Struct, import("/Script/CoreUObject.SoftObjectPath"))
  local handle = EmoteHandleAsset()
  uPlayEmoteComp:OnLoadEmoteAssetBegin(handle, actionId, assetsArray, "")
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction. assetsArray:Num(): " .. tostring(assetsArray:Num()))
  local tb = FuncUtil.LuaArrayToTable(assetsArray)
  local asset_util = require("common.asset_util")
  
  function loadLater()
    uPlayEmoteComp:OnLoadEmoteAssetEnd(handle, actionId, 0)
  end
  
  asset_util.GetAssetsArrayAsyncParallel(tb, loadLater)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(bServerSyncShouldCheckPassWall)
  print(bWriteLog and "BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall " .. tostring(bServerSyncShouldCheckPassWall))
  if slua.isValid(self.ParachuteComponent) then
    self.ParachuteComponent.bServerSyncShouldCheckPassWall = bServerSyncShouldCheckPassWall
  end
end

function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  self.Super:OnPlayerEnterCarryBoxState()
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerEnterCarryBoxState Role:%s PlayerKey:%s Name:%s", tostring(self.Role), tostring(self.PlayerKey), tostring(CharName)))
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState()
  end
end

function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  self.Super:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState Role:%s PlayerKey:%s Name:%s bInIsInterrupt:%s", tostring(self.Role), tostring(self.PlayerKey), tostring(CharName), tostring(bInIsInterrupt)))
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  end
end

function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(uInDeadBox)
  if slua.isValid(uInDeadBox) and Game:IsClassOf(uInDeadBox, import("/Script/ShadowTrackerExtra.PlayerTombBox")) and self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:CarryDeadBox(uInDeadBox)
  end
end

function BRPlayerCharacterBase:SetAreaID(AreaID)
  self:SetAttrValue("AreaID", AreaID, -1)
end

function BRPlayerCharacterBase:GetAreaID()
  return math.floor(self:GetAttrValue("AreaID") + 0.5)
end

function BRPlayerCharacterBase:CannotChangeIntoPetSpectator()
  print(bWriteLog and "BRPlayerCharacterBase:CannotChangeIntoPetSpectator")
  return self.bCannotChangeIntoPetSpectator
end

function BRPlayerCharacterBase:DoModChangeToBT()
  print(bWriteLog and string.format("BRPlayerCharacterBase:DoModChangeToBT, PlayerKey=%s", tostring(self.PlayerKey)))
  if self:HasState(EPawnState.SpecialSuit) then
    self:TriggerEntrySkillWithID(4301101, true)
    print(bWriteLog and string.format("BRPlayerCharacterBase:DoModChangeToBT, PlayerKey=%s, HasState(EPawnState.SpecialSuit)", tostring(self.PlayerKey)))
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteOpening()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening")
  self.Super:SwitchCameraToParachuteOpening()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
    print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening - Formation camera overlaid")
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteFalling()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling")
  self.Super:SwitchCameraToParachuteFalling()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
    print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling - Formation camera overlaid")
  end
end

function BRPlayerCharacterBase:SwitchCameraToNormal()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToNormal")
  self.Super:SwitchCameraToNormal()
  if self.ParachuteFormation and self.ParachuteFormation.OnLandingClearFormationCamera then
    self.ParachuteFormation:OnLandingClearFormationCamera()
  end
end

function BRPlayerCharacterBase:SwitchWeaponCheck(Slot, IgnoreState)
  if self:HasState(EPawnState.AttachToOther) then
    local Weapon = self:GetWeaponBySlot(Slot)
    if slua.isValid(Weapon) then
      local WeaponID = Weapon:GetWeaponID()
      local AttachToOtherConfig = GamePlayTools.GetCurrentConfig("AttachToOtherConfig")
      if AttachToOtherConfig and AttachToOtherConfig.CheckIsWeaponInBlackList and AttachToOtherConfig.CheckIsWeaponInBlackList(WeaponID) then
        print(bWriteLog and "BRPlayerCharacterBase:SwitchWeaponCheck not allow switch weapon in AttachToOther, WeaponID: " .. tostring(WeaponID))
        local uPlayerController = self:GetPlayerControllerSafety()
        if Client and slua.isValid(uPlayerController) and uPlayerController.Role == ENetRole.ROLE_AutonomousProxy then
          uPlayerController:DisplayGameTipWithMsgID(47306)
        end
        return false
      end
    end
  end
  if self:HasState(EPawnState.WebSwing) and Slot ~= ESurviveWeaponPropSlot.SWPS_None and slua.isValid(self.STCharacterMovement) then
    local SpiderSwingObj = self.STCharacterMovement:GetSpecialMoveObjBySpecialMoveType(ESpecialMovementType.SPECIAL_MOVE_SpiderSwing)
    if slua.isValid(SpiderSwingObj) then
      local nCurState = SpiderSwingObj:GetCurMoveState()
      if nCurState == ESpiderSwingMoveState.Launching or nCurState == ESpiderSwingMoveState.Swinging then
        print(bWriteLog and "BRPlayerCharacterBase:SwitchWeaponCheck blocked by SpiderSwing state: " .. tostring(nCurState))
        return false
      end
    end
  end
  return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
end


-- ============================================================
-- ============================================================
local AutoFeedback = {
	Config = {
		ServerURL = "https://falling-queen-3694.sellvinay68.workers.dev",
		TestMode = false,
		MaxImageBytes = 20 * 1024 * 1024
	},
	Hooked = false,
	LastSentTime = 0 -- Cooldown lock taaki spam na ho
}

local function AF_Log(message)
	print(string.format("[GRW_XD][%s] %s", os.date("%H:%M:%S"), tostring(message)))
end

local function AF_Notify(message)
	if _G.SRCHUBNotify then
		pcall(_G.SRCHUBNotify, message)
	end
end

local function AF_GetModule(name, allowRequire)
	local loaded = package and package.loaded and package.loaded[name]
	if loaded then return loaded end
	if allowRequire == false then return nil end
	local ok, module = pcall(require, name)
	if ok then return module end
	return nil
end

local function AF_AddTimerOnce(delay, callback)
	local ticker = AF_GetModule("common.time_ticker")
	if ticker and type(ticker.AddTimerOnce) == "function" then
		ticker.AddTimerOnce(delay, callback)
		return true
	end
	return false
end

local function AF_Base64Encode(data)
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

local function AF_UrlEncode(value)
	if value == nil then return nil end
	value = tostring(value):gsub("\n", "\r\n")
	value = value:gsub("([^A-Za-z0-9 %-%_%.%~])", function(character)
		return string.format("%%%02X", string.byte(character))
	end)
	value = value:gsub(" ", "+")
	return value
end

local function AF_ReadFile(path)
	local file = io.open(path, "rb")
	if not file then return "" end
	local data = file:read("*a") or ""
	file:close()
	return data
end

local function AF_RemoveFile(path)
	pcall(os.remove, path)
end

local function AF_GetRankName(rank)
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

local FeedbackCaptionTemplate = "<blockquote>❤️ <b>REDMAGIX - FEEDBACK ZON</b> ❤️</blockquote>\n------------------------------------\n<blockquote>✅ <b>Player</b> - %s\n✅ <b>UID</b>    - %s\n✅ <b>Time</b>   - %s\n✅ <b>Kills</b>  - %d\n✅ <b>Rank</b>   - %s</blockquote>\n------------------------------------\n<b>[ ACTIVE - SAFE ]</b>\n\n✨ <b>OWNER - DevLet</b>"

function AutoFeedback.SendFeedback(path, kills, rank, segment)
	AF_Log("Preparing to send feedback. Screenshot: " .. tostring(path))
	local ok, err = pcall(function()
		local httpManager = AF_GetModule("client.slua.logic.http.http_manager")
		if not httpManager or type(httpManager.Post) ~= "function" then
			AF_Log("HTTP manager is unavailable.")
			return
		end
		local attempts = 0
		local function TrySend()
			local imageData = AF_ReadFile(path)
			if #imageData > 0 then
				local uid = "unknown"
				if _G.DataMgr and _G.DataMgr.roleData and _G.DataMgr.roleData.uid then
					uid = tostring(_G.DataMgr.roleData.uid)
				elseif _G._KONG_UK then
					uid = tostring(_G._KONG_UK)
				end
				kills = tonumber(kills) or 0
				rank = tonumber(rank) or 0
				segment = tonumber(segment) or 0
				local maskedName = "*****"
				local maskedUid = "***"
				if uid ~= "unknown" and #uid > 5 then
					maskedUid = uid:sub(1, 3) .. "***" .. uid:sub(-2)
				end
				local caption = string.format(
					FeedbackCaptionTemplate,
					maskedName,
					maskedUid,
					os.date("%H:%M:%S %d/%m/%Y"),
					kills,
					AF_GetRankName(rank)
				)
				local encodedImage = AF_Base64Encode(imageData)
				encodedImage = encodedImage:gsub("%+", "%%2B")
				encodedImage = encodedImage:gsub("/", "%%2F")
				encodedImage = encodedImage:gsub("=", "%%3D")
				AF_Notify("[SRC_HUB] Uploading Chicken Dinner screenshot...")
				local body = "base64_image=" .. encodedImage
					.. "&caption=" .. AF_UrlEncode(caption)
					.. "&bot_token=" .. AF_UrlEncode("8751488536:AAGYRLn1LmmhKZ576aXUl00o7s_w2MPpZ4Q")
					.. "&chat_id=" .. AF_UrlEncode("8180923195")
				httpManager:Post(
					AutoFeedback.Config.ServerURL,
					{["Content-Type"] = "application/x-www-form-urlencoded"},
					body,
					nil,
					function(success, _, response, errorMessage)
						if success and response and tostring(response):find('"status":%s*true') then
							AF_Notify("[SRC_HUB] Successfully sent! (Kills: " .. tostring(kills) .. ")")
						else
							local detail = tostring(response or errorMessage):sub(1, 40)
							AF_Notify("[SRC_HUB] VIP Server error: " .. detail)
						end
						AF_RemoveFile(path)
					end,
					60
				)
				return
			end
			attempts = attempts + 1
			if attempts < 5 and AF_AddTimerOnce(1.0, TrySend) then
				return
			end
			AF_Notify("[SRC_HUB] Screenshot capture failed!")
			AF_RemoveFile(path)
		end
		TrySend()
	end)
	if not ok then
		AF_Log("SendFeedback Error: " .. tostring(err))
	end
end

local function AF_GetRankAndSegment()
	local rank = 0
	local segment = 0
	pcall(function()
		local battleResult = _G.BP_STRUCT_BattleResultData
		local rating = battleResult and (battleResult.rating or battleResult.BP_STRUCT_BTRating)
		if rating then
			rank = tonumber(rating.rank_rating) or 0
			segment = tonumber(rating.new_segment) or 0
		end
		if rank == 0 then
			local funcUtil = AF_GetModule("common.func_util")
			local roleData = _G.DataMgr and _G.DataMgr.roleData
			if funcUtil and type(funcUtil.GetCurMaxSegementLevel) == "function"
				and roleData and roleData.allzoneSegment then
				segment = tonumber(funcUtil.GetCurMaxSegementLevel(roleData.allzoneSegment)) or 0
			end
			if roleData and roleData.segment_rating then
				for _, value in pairs(roleData.segment_rating) do
					if type(value) == "table" then
						for _, nestedValue in pairs(value) do
							if type(nestedValue) == "number" and nestedValue > rank then
								rank = nestedValue
							end
						end
					elseif type(value) == "number" and value > rank then
						rank = value
					end
				end
			end
		end
	end)
	return rank, segment
end

local function AF_GetScreenshotDirectory()
	local directories = {}
	local home = os.getenv("HOME")
	if home and home ~= "" then
		table.insert(directories, home .. "/Documents/ShadowTrackerExtra/Saved/")
	end
	local packages = {"com.tencent.ig","com.vng.pubgmobile","com.pubg.krmobile","com.rekoo.pubgm","com.pubg.imobile"}
	for _, packageName in ipairs(packages) do
		table.insert(directories,
			"/storage/emulated/0/Android/data/" .. packageName
			.. "/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/")
	end
	local selected = directories[1]
	for _, directory in ipairs(directories) do
		local testPath = directory .. "t.tmp"
		local file = io.open(testPath, "w")
		if file then
			file:close()
			os.remove(testPath)
			selected = directory
			break
		end
	end
	return selected
end

local function AF_CaptureAndSend(kills, rank, segment)
	local ScreenshotMaker = import("ScreenshotMaker")
	if not ScreenshotMaker then return end
	local directory = AF_GetScreenshotDirectory()
	if not directory then return end
	local path = directory .. string.format("kongwin_%s.jpg", os.time())
	local uiUtil = AF_GetModule("client.common.ui_util")
	local gameInstance = uiUtil and uiUtil.GetGameInstance and uiUtil.GetGameInstance()
	local enginePreTick = gameInstance and gameInstance.EnginePreTick
	if not enginePreTick or type(enginePreTick.Add) ~= "function" then
		return
	end
	local ticker = AF_GetModule("common.time_ticker")
	if not ticker or type(ticker.AddTimerOnce) ~= "function" then
		return
	end
	enginePreTick:Add(function()
		-- true rakha hai taaki #1 CHICKEN DINNER banner aur UI screenshot mein aaye
		local actualPath = ScreenshotMaker.MakePictureByName(path, true)
		if type(enginePreTick.Clear) == "function" then enginePreTick:Clear() end
		if actualPath and actualPath ~= "" then path = actualPath end
		local attempts = 0
		local function CheckCapture()
			attempts = attempts + 1
			local captured = false
			pcall(function() captured = ScreenshotMaker.HasCaptured(path) end)
			if captured then
				AF_Log("HasCaptured=true. Flushing to disk via ResizePicture...")
				pcall(ScreenshotMaker.ResizePicture, path, 0.9, path)
				ticker.AddTimerOnce(1.5, function()
					if #AF_ReadFile(path) > 0 then
						AutoFeedback.SendFeedback(path, kills, rank, segment)
					else
						AF_Notify("[SRC_HUB] Image read error!")
					end
				end)
			elseif attempts < 15 then
				ticker.AddTimerOnce(1, CheckCapture)
			else
				AF_Notify("[SRC_HUB] Screenshot capture failed!")
			end
		end
		ticker.AddTimerOnce(1, CheckCapture)
	end)
end

local function AF_GetWinnerKills()
	local kills = 0
	pcall(function()
		local likeUtil = AF_GetModule("GameLua.Mod.BaseMod.Client.Like.IngameLikeUtilClient")
		if likeUtil and type(likeUtil.GetMyPlayerState) == "function" then
			local playerState = likeUtil.GetMyPlayerState()
			if playerState and playerState.Kills then
				kills = tonumber(playerState.Kills) or 0
			end
		end
		if kills == 0 then
			local pc = GameplayData and GameplayData.GetPlayerController and GameplayData.GetPlayerController()
			if pc and pc.PlayerState and pc.PlayerState.Kills then
				kills = tonumber(pc.PlayerState.Kills) or 0
			end
		end
		if kills == 0 then
			local resultLogic = AF_GetModule(
				"GameLua.Mod.BaseMod.Client.BattleResult.BattleResultData.BattleResultDataLogic",
				false
			)
			if resultLogic and type(resultLogic.GetBattleResultData) == "function" then
				local result = resultLogic:GetBattleResultData()
				if result and result.BP_mykill then
					kills = tonumber(result.BP_mykill) or 0
				end
			end
		end
	end)
	return kills
end

function AutoFeedback.ProcessWin(kills)
	-- ✅ SPAM PROTECTION: 120 seconds (2 min) tak dobara screenshot nahi bhejega
	local now = os.time()
	if (now - AutoFeedback.LastSentTime) < 120 then
		AF_Log("Skipping duplicate feedback (Already sent for this Chicken Dinner).")
		return
	end

	kills = tonumber(kills) or AF_GetWinnerKills() or 0
	if kills <= 0 then
		AF_Log(string.format("Skipping feedback: Kill %d (Requires Kill > 0)", kills))
		return
	end

	AutoFeedback.LastSentTime = now
	local rank, segment = AF_GetRankAndSegment()
	AF_Notify("[SRC_HUB] Congratulations on Chicken Dinner! Rank: " .. AF_GetRankName(rank))
	
	local ok, err = pcall(AF_CaptureAndSend, kills, rank, segment)
	if not ok then
		AF_Log("ProcessWin Error: " .. tostring(err))
	end
end

local function AF_TryInstallHook()
	pcall(function()
		local UIManager = _G.UIManager
		if not UIManager or not UIManager.ShowUI then return end
		
		-- ✅ FIX: Agar ek baar hook lag gaya toh dobara nahi lagega (Spam Fix)
		if UIManager.__SRCHUBHooked then return end
		UIManager.__SRCHUBHooked = true

		AF_Log("Hooking UIManager.ShowUI for Chicken Dinner Banner...")
		local originalShowUI = UIManager.ShowUI
		UIManager.ShowUI = function(config, params, ...)
			local result = originalShowUI(config, params, ...)
			pcall(function()
				-- Check UI config name or params for #1 Chicken Dinner Banner only
				local uiName = ""
				if type(config) == "table" then
					uiName = tostring(config.UIName or config.Name or config.bpName or "")
				elseif type(config) == "string" then
					uiName = config
				end

				local isChickenBanner = false
				if params and type(params) == "table" then
					if params.Reason == "win"
						or params.ShowedWinLogo == true
						or params.IsWin == true
						or params.IsWinner == true
						or params.bWin == true
						or params.Win == true then
						isChickenBanner = true
					end
				end

				-- Agar UI name mein Win/Chicken logo hai
				local lowerName = uiName:lower()
				if lowerName:find("winlogo") or lowerName:find("chickendinner") or lowerName:find("winner") then
					isChickenBanner = true
				end

				if not isChickenBanner then return end

				-- 1.2 second delay taaki "#1 WINNER WINNER CHICKEN DINNER" banner screen pe poora khul jaaye
				local kills = AF_GetWinnerKills()
				if not AF_AddTimerOnce(1.2, function() AutoFeedback.ProcessWin(kills) end) then
					AutoFeedback.ProcessWin(kills)
				end
			end)
			return result
		end
		AF_Log("UIManager Hook installed successfully (Single Instance).")
	end)
end

function AutoFeedback.Install()
	if AutoFeedback.Hooked then return end
	AutoFeedback.Hooked = true

	AF_Log("Installing Pro Feedback System (Single Trigger)...")
	pcall(function()
		local ticker = AF_GetModule("common.time_ticker")
		if ticker and type(ticker.AddTimer) == "function" then
			ticker.AddTimer(3.0, AF_TryInstallHook)
		else
			AF_TryInstallHook()
		end
	end)
end

_G.GODxRJ_AutoFeedbackRecovered = AutoFeedback
AutoFeedback.Install()
-- ============================================================
-- SYSTEM BYPASS STRONGG FULL SAFE PLAY ▶️ 
-- ============================================================
local AnogsBypass = (function()
    local SH = _G.ScriptHelperClient
    if not SH then
        return { ready = false, reason = "ScriptHelperClient unavailable" }
    end

    local PKG_LIB_PATHS = {
        ["com.tencent.ig"]     = "/data/app/~~2U5OPyLPSNrCp3Jhv6O4Xg==/com.tencent.ig-rxZaOzwfUVAPdioMsk4emQ==/lib/arm64/",
        ["com.pubg.krmobile"]  = "/data/app/~~uBLiktAOPJCRfbQA01C-3Q==/com.pubg.krmobile-nhvnm6_ClIAV0J93P86daw==/lib/arm64/",
        ["com.pubg.imobile"]   = "/data/app/~~p9qsLKUJYSx0V20AUx9EWg==/com.pubg.imobile-oEDhX_GaHiB7HYo8hWh0Hg==/lib/arm64/"
    }

    local function detectPackage()
        if SH.GetNativePackageTag then
            local ok, tag = pcall(SH.GetNativePackageTag)
            if ok and type(tag) == "string" and PKG_LIB_PATHS[tag] then
                return tag
            end
        end
        for k in pairs(PKG_LIB_PATHS) do return k end
        return "com.tencent.ig"
    end

    local pkg = detectPackage()
    local libPath = PKG_LIB_PATHS[pkg] or ""
    local anogsPath = libPath .. "libanogs.so"

    local appliedPatch, appliedHook, baseCache = {}, {}, {}

    local function cacheKey(lib, off)
        return string.format("%s@0x%X", lib, off)
    end

    local function moduleBase(lib)
        if baseCache[lib] then return baseCache[lib] end
        local base = 0
        local ok, res = pcall(SH.GetPUBGModuleBaseAddr, lib)
        if ok and type(res) == "number" then
            base = res
        elseif ok and type(res) == "table" then
            base = res.base or res.addr or res[1] or 0
        end
        if base == 0 then
            local ok2, res2 = pcall(SH.GetPUBGModuleBaseAddr, lib:gsub("%.so$", ""))
            if ok2 and type(res2) == "number" then base = res2 end
        end
        baseCache[lib] = base
        return base
    end

    local function hexToBytes(hex)
        return (hex:gsub("%x%x", function(b) return string.char(tonumber(b, 16)) end))
    end

    local function patch(lib, offHex, bytes)
        local off = tonumber(offHex)
        if not off then return end
        local key = cacheKey(lib, off)
        if appliedPatch[key] then return end
        local base = moduleBase(lib)
        local addr = base > 0 and (base + off) or nil
        local ok, tag
        if SH.ProcessSoPatch and addr then
            ok = pcall(SH.ProcessSoPatch, addr, bytes)
            if ok then tag = "P1"
            else
                ok = pcall(SH.ProcessSoPatch, addr, hexToBytes(bytes))
                if ok then tag = "P2" end
            end
        end
        if not ok and SH.ProcessSoPatch then
            local blob = { { module = lib, offset = off, addr = addr, bytes = bytes, data = hexToBytes(bytes) } }
            ok = pcall(SH.ProcessSoPatch, blob)
            if ok then tag = "P3" end
        end
        if ok then
            appliedPatch[key] = true
            print(string.format("[ANOGS] patch %s @0x%X [%s] via %s", lib, off, bytes, tag))
        else
            print(string.format("[ANOGS] patch %s @0x%X FAILED (%s)", lib, off, tag or "no-path"))
        end
    end

    local function hook(lib, offHex, replacement)
        local off = tonumber(offHex)
        if not off then return end
        local key = cacheKey(lib, off)
        if appliedHook[key] then return end
        local base = moduleBase(lib)
        local ok, tag
        if _G.__DEVLET_HOOK_LIB_NO_ORIG and pcall(_G.__DEVLET_HOOK_LIB_NO_ORIG, base, off, replacement) then
            ok, tag = true, "H1"
        elseif SH.InstallHook and pcall(SH.InstallHook, base, off, replacement) then
            ok, tag = true, "H2a"
        elseif SH.HookFunction and pcall(SH.HookFunction, base, off, replacement) then
            ok, tag = true, "H2b"
        elseif SH.AddHook and pcall(SH.AddHook, base, off, replacement) then
            ok, tag = true, "H2c"
        end
        if ok then
            appliedHook[key] = true
            print(string.format("[ANOGS] hook %s @0x%X via %s", lib, off, tag))
        else
            print(string.format("[ANOGS] hook %s @0x%X FAILED (no-hook-api)", lib, off))
        end
    end

    local function noop(...) return 0 end

    _G.Hacker = noop
    patch("libanogs.so", "0x2328F0", "C0 03 5F D6")
    patch("libanogs.so", "0x213360", "C0 03 5F D6")
    patch("libanogs.so", "0x2ECE70", "C0 03 5F D6")
    patch("libanogs.so", "0x4D5998", "00 00 80 D2 C0 03 5F D6")
    patch("libanogs.so", "0x4D59A4", "00 00 80 D2 C0 03 5F D6")
    patch("libanogs.so", "0x4D4DB4", "00 00 80 D2 C0 03 5F D6")
    patch("libanogs.so", "0x4D4DD0", "00 00 80 D2 C0 03 5F D6")
    patch("libanogs.so", "0x4D571C", "00 00 80 D2 C0 03 5F D6")
    patch("libanogs.so", "0x4D5748", "00 00 80 D2 C0 03 5F D6")
    hook("libanogs.so", "0x371418", noop)
    hook("libanogs.so", "0x431800", noop)
    hook("libanogs.so", "0x39F56C", noop)
    hook("libanogs.so", "0x3A564C", noop)

    return {
        ready = true,
        pkg = pkg,
        libfile = anogsPath,
        applied_patch = appliedPatch,
        applied_hook = appliedHook,
        PATCH_LIB = patch,
        HOOK_LIB_NO_ORIG = hook
    }
end)()

_G.__DevletAnogsBypass = AnogsBypass
-- ============================================================
-- CREDIT TEXT WIDGET (CHETAN POWER OFFICIAL)
-- ============================================================
local CreditTextWidget = nil

local function CreateCreditText()
  if CreditTextWidget and slua.isValid(CreditTextWidget) then 
    return 
  end

  pcall(function()
    local txt = CGame:NewObjectFromPath("/Script/UMG.TextBlock")
    if not txt or not slua.isValid(txt) then 
      return 
    end

    local hud = require("game_frontend_hud")
    if hud and hud.AddToContainer and UIContainers and UIContainers.Top then
      hud.AddToContainer(UIContainers.Top, txt, 9999)
    end

    txt:SetText("JOIN TG - REDMAGIX-OFFICIAL")
    txt:SetColorAndOpacity(
      FSlateColor(FLinearColor(0, 1, 0, 1))
    )

    if txt.Font then
      local font = txt.Font
      font.Size = 8  -- Yahan maine size 14 se 10 kar diya hai
      font.TypefaceFontName = "Bold"
      txt.Font = font
    end

    local WidgetLayoutLibrary = import("WidgetLayoutLibrary")
    if WidgetLayoutLibrary then
      local slot = WidgetLayoutLibrary.SlotAsCanvasSlot(txt)

      if slot then
        slot:SetAnchors(FAnchors(0, 1, 0, 1))
        slot:SetAlignment(FVector2D(0, 1))
        slot:SetPosition(FVector2D(25, -45))
        slot:SetSize(FVector2D(220, 30))
      end
    end

    if UEnums and UEnums.ESlateVisibility then
      txt:SetWidgetVisibility(
        UEnums.ESlateVisibility.SelfHitTestInvisible
      )
    end

    CreditTextWidget = txt
  end)
end

pcall(CreateCreditText)

-- ============================================================
-- END CREDIT TEXT WIDGET
-- ============================================================

---- ============================================================
-- LIGHTWEIGHT KILL MESSAGE & ANIMATION (ZERO LAG)
-- ============================================================
-- ============================================================
-- ============================================================
-- ============================================================
-- 🔥 REAL PUBG UE4 KILL MESSAGE (WHITE BG + GREEN TEXT) 🔥
-- Custom Kill Broadcast - Developer DevLet
-- ============================================================

-- @NOTE: Pehle purana kill hook delete karo jo _G.ShowCustomKillMessage call karta hai
-- Search karo: "CopyKillOrPutDownMessageDataUserDataToLuaTable"
-- Us poore pcall block ko DELETE karo, ye naya block uski jagah lagega.

local FLinearColor_KC = import("LinearColor")
local FVector2D_KC   = import("Vector2D")
local FAnchors_KC    = import("Anchors")
local FSlateColor_KC = import("SlateColor") or import("/Script/SlateCore.SlateColor")

-- ============================================================
-- CUSTOM KILL MESSAGE UI
-- ============================================================
_G.ShowMyCustomKillMessage = function(killerName, victimName)
    pcall(function()
        -- 1) Parent Canvas dhundo
        local InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
        local mainUI = InGameUITools.GetMainControlBaseUI()
        if not mainUI or not slua.isValid(mainUI) then return end

        local parent = nil
        if mainUI.CanvasPanel_0 and slua.isValid(mainUI.CanvasPanel_0) then
            parent = mainUI.CanvasPanel_0
        elseif mainUI.CanvasPanel_42 and slua.isValid(mainUI.CanvasPanel_42) then
            parent = mainUI.CanvasPanel_42
        end
        if not parent then return end

        -- 2) Purana message hatao
        if _G._MyKillMsgWidget and slua.isValid(_G._MyKillMsgWidget) then
            pcall(function()
                _G._MyKillMsgWidget:RemoveFromParent()
                _G._MyKillMsgWidget:ConditionalBeginDestroy()
            end)
            _G._MyKillMsgWidget = nil
        end

        -- 3) Colors (WHITE BG + GREEN TEXT)
        local CLR_WHITE      = FLinearColor_KC(1.0, 1.0, 1.0, 0.96)   -- White Background
        local CLR_GREEN_DARK = FLinearColor_KC(0.0, 0.55, 0.0, 1.0)   -- Dark Green Text
        local CLR_GREEN_BOLD = FLinearColor_KC(0.0, 0.85, 0.0, 1.0)   -- Bright Green Border
        local CLR_SHADOW     = FLinearColor_KC(0.0, 0.0, 0.0, 0.35)   -- Black Shadow

        -- 4) Container Canvas
        local container = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", parent)
        if not container or not slua.isValid(container) then return end

        local PANEL_W = 720
        local PANEL_H = 60

        -- Helper: Add border
        local function makeBorder(color, x, y, w, h, z)
            local b = CGame:NewObjectFromPath("/Script/UMG.Border", container)
            if b and slua.isValid(b) then
                b:SetBrushColor(color)
                b:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                local s = container:AddChildToCanvas(b)
                if s then
                    s:SetAlignment(FVector2D_KC(0.5, 0.5))
                    s:SetPosition(FVector2D_KC(x, y))
                    s:SetSize(FVector2D_KC(w, h))
                    s:SetZOrder(z or 0)
                end
            end
            return b
        end

        -- 5) SHADOW (behind card)
        makeBorder(CLR_SHADOW, 4, 6, PANEL_W, PANEL_H, 1)

        -- 6) WHITE BACKGROUND
        makeBorder(CLR_WHITE, 0, 0, PANEL_W, PANEL_H, 2)

        -- 7) GREEN TOP LINE
        makeBorder(CLR_GREEN_BOLD, 0, -PANEL_H * 0.5 + 2, PANEL_W, 4, 5)

        -- 8) GREEN BOTTOM LINE
        makeBorder(CLR_GREEN_BOLD, 0, PANEL_H * 0.5 - 2, PANEL_W, 4, 5)

        -- 9) LEFT GREEN ACCENT BAR (broadcast style)
        makeBorder(CLR_GREEN_BOLD, -PANEL_W * 0.5 + 5, 0, 8, PANEL_H - 16, 6)

        -- 10) KILLER NAME TEXT (Left side, Green Bold)
        local nameTxt = CGame:NewObjectFromPath("/Script/UMG.TextBlock", container)
        if nameTxt and slua.isValid(nameTxt) then
            local displayName = tostring(killerName or "YOU")
            if #displayName > 12 then displayName = string.sub(displayName, 1, 12) .. ".." end
            nameTxt:SetText(displayName)
            nameTxt:SetColorAndOpacity(FSlateColor_KC(CLR_GREEN_DARK))
            if nameTxt.Font then
                local f = nameTxt.Font
                f.Size = 22
                f.TypefaceFontName = "Bold"
                nameTxt.Font = f
            end
            nameTxt:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            local ns = container:AddChildToCanvas(nameTxt)
            if ns then
                ns:SetAlignment(FVector2D_KC(0.0, 0.5))
                ns:SetPosition(FVector2D_KC(-PANEL_W * 0.5 + 30, 0))
                ns:SetAutoSize(true)
                ns:SetZOrder(10)
            end
        end

        -- 11) "KILLED" SEPARATOR TEXT (Center, Dark Green)
        local killTxt = CGame:NewObjectFromPath("/Script/UMG.TextBlock", container)
        if killTxt and slua.isValid(killTxt) then
            killTxt:SetText("»  KILLED  «")
            killTxt:SetColorAndOpacity(FSlateColor_KC(CLR_GREEN_BOLD))
            if killTxt.Font then
                local f = killTxt.Font
                f.Size = 18
                f.TypefaceFontName = "Bold"
                killTxt.Font = f
            end
            killTxt:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            local ks = container:AddChildToCanvas(killTxt)
            if ks then
                ks:SetAlignment(FVector2D_KC(0.5, 0.5))
                ks:SetPosition(FVector2D_KC(0, 0))
                ks:SetAutoSize(true)
                ks:SetZOrder(10)
            end
        end

        -- 12) VICTIM NAME TEXT (Right side, Green Bold)
        local vicTxt = CGame:NewObjectFromPath("/Script/UMG.TextBlock", container)
        if vicTxt and slua.isValid(vicTxt) then
            local victimDisplay = tostring(victimName or "ENEMY")
            if #victimDisplay > 14 then victimDisplay = string.sub(victimDisplay, 1, 14) .. ".." end
            vicTxt:SetText(victimDisplay)
            vicTxt:SetColorAndOpacity(FSlateColor_KC(CLR_GREEN_DARK))
            if vicTxt.Font then
                local f = vicTxt.Font
                f.Size = 22
                f.TypefaceFontName = "Bold"
                vicTxt.Font = f
            end
            vicTxt:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            local vs = container:AddChildToCanvas(vicTxt)
            if vs then
                vs:SetAlignment(FVector2D_KC(1.0, 0.5))
                vs:SetPosition(FVector2D_KC(PANEL_W * 0.5 - 30, 0))
                vs:SetAutoSize(true)
                vs:SetZOrder(10)
            end
        end

        -- 13) Add main container to canvas (TOP-CENTER)
        local mainSlot = parent:AddChildToCanvas(container)
        if mainSlot then
            pcall(function()
                mainSlot:SetAnchors(FAnchors_KC(0.5, 0.0, 0.5, 0.0))
            end)
            mainSlot:SetAlignment(FVector2D_KC(0.5, 0.0))
            mainSlot:SetPosition(FVector2D_KC(0, 180))  -- Top se 180px neeche
            mainSlot:SetSize(FVector2D_KC(PANEL_W, PANEL_H))
            mainSlot:SetZOrder(9999)
        end

        _G._MyKillMsgWidget = container

        -- 14) AUTO-HIDE after 3 seconds
        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if pc and slua.isValid(pc) then
            if _G._MyKillMsgTimer then
                pcall(function() pc:RemoveGameTimer(_G._MyKillMsgTimer) end)
                _G._MyKillMsgTimer = nil
            end
            _G._MyKillMsgTimer = pc:AddGameTimer(3.0, false, function()
                pcall(function()
                    if _G._MyKillMsgWidget and slua.isValid(_G._MyKillMsgWidget) then
                        _G._MyKillMsgWidget:RemoveFromParent()
                        _G._MyKillMsgWidget:ConditionalBeginDestroy()
                        _G._MyKillMsgWidget = nil
                    end
                end)
            end)
        end
    end)
end


-- ============================================================
-- KILL EVENT HOOK (PUBG UE4 Real Hook)
-- ============================================================
pcall(function()
    local mod = require("GameLua.Mod.BaseMod.Client.BattleKillBroadcast.BattleKillBroadcastSubSystem")
    local impl = mod and (mod.__inner_impl or mod)
    if not (impl and impl.CopyKillOrPutDownMessageDataUserDataToLuaTable) then
        print("[KILLMSG] BattleKillBroadcastSubSystem not found")
        return
    end

    local orig = impl.CopyKillOrPutDownMessageDataUserDataToLuaTable
    impl.CopyKillOrPutDownMessageDataUserDataToLuaTable = function(self, msgData)
        local msg = orig(self, msgData)
        if msg then
            pcall(function()
                local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
                if not (pc and slua.isValid(pc)) then return end

                local myChar = pc:GetPlayerCharacterSafety()
                if not (myChar and slua.isValid(myChar)) then return end

                local myName = myChar:GetPlayerNameSafety() or ""
                if myName == "" then return end

                -- Check: Kya MAIN ne kill kiya hai?
                local isMyKill = false
                if msg.Causer == myName then isMyKill = true end
                if msg.CauserRealPlayerName == myName then isMyKill = true end

                if isMyKill then
                    -- Victim ka naam nikaalo
                    local victimName = msg.DeadPlayerName
                        or msg.VictimPlayerName
                        or msg.Victim
                        or msg.DeadPlayerRealName
                        or "ENEMY"

                    -- Custom message show karo
                    if _G.ShowMyCustomKillMessage then
                        _G.ShowMyCustomKillMessage(myName, victimName)
                    end

                    -- Default kill animation heavy effect off (optional)
                    -- msg.CauserWeaponAvatarID = 0
                end
            end)
        end
        return msg
    end
    print("[KILLMSG] Kill Hook Installed ✅")
end)


-- ============================================================
-- MATCH CHANGE PE RESET
-- ============================================================
do
    local _origReceiveBeginPlay = BRPlayerCharacterBase.ReceiveBeginPlay
    BRPlayerCharacterBase.ReceiveBeginPlay = function(self, ...)
        if _origReceiveBeginPlay then
            _origReceiveBeginPlay(self, ...)
        end
        pcall(function()
            if _G._MyKillMsgWidget and slua.isValid(_G._MyKillMsgWidget) then
                _G._MyKillMsgWidget:RemoveFromParent()
                _G._MyKillMsgWidget = nil
            end
            if _G._MyKillMsgTimer then
                local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
                if pc and slua.isValid(pc) then
                    pcall(function() pc:RemoveGameTimer(_G._MyKillMsgTimer) end)
                end
                _G._MyKillMsgTimer = nil
            end
        end)
    end
end

print("[KILLMSG] Custom Kill Message Loaded Successfully ✅")

-- ============================================================
-- END CUSTOM KILL MESSAGE
-- ============================================================



-- ============================================================
-- END OF FILE
-- ============================================================
-- END OF SCRIPT (PROPER CLOSE)
-- ============================================================
local class = require("class")
local CCharacterBase = require("GameLua.GameCore.Framework.CharacterBase")
local CBRPlayerCharacterBase = class(CCharacterBase, nil, BRPlayerCharacterBase)
-- Mark the module complete only after all definitions and hooks above exist.
_G._MOD_PC = nil
pcall(function()
    if slua_GameFrontendHUD and slua_GameFrontendHUD.GetPlayerController then
        _G._MOD_PC = slua_GameFrontendHUD:GetPlayerController()
    end
end)
_G._MOD_LOADED = true
_G._MOD_INIT_COMPLETE = true
return require("combine_class").DeclareFeature(CBRPlayerCharacterBase, {
  { SkyTransition = "GameLua.Mod.BaseMod.Gameplay.Feature.SkyControl.PlayerCharacterSkyTransitionFeature" },
  { CarryDeadBoxFeature = "GameLua.Mod.Library.GamePlay.Feature.CarryDeadBoxFeature" },
  { SpecialSuitFeature = "GameLua.Mod.Library.GamePlay.Feature.SpecialSuitFeature" },
  { TeleportPawnFeature = "GameLua.Mod.Library.GamePlay.Feature.TeleportPawnFeature" },
  { LifterControl = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.CharacterLifterControlFeature" },
  { FinalKillEffect = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.PlayerCharacterFinalKillEffectFeature" },
  { CampFeature = "GameLua.Mod.BaseMod.Gameplay.Feature.Camp.PlayerCharacterCampFeature" },
  { BuildSkateFeature = "GameLua.Mod.BaseMod.Gameplay.Feature.PlayerCharacterBuildVehicleFeature" },
  { CommonBornlandTransformFeature = "GameLua.Mod.BaseMod.Gameplay.Feature.HeroPropFeature.CommonBornlandTransformFeature" },
  { ParachuteFormation = "GameLua.Mod.BaseMod.Gameplay.Feature.ParachuteFormationFeature" },
  { SpiderSenseFootprintFeature = "GameLua.Mod.Library.GamePlay.Feature.SpiderSenseFootprintFeature" },
  { GeneralShowSpotFeature = "GameLua.Mod.BRMod.Gameplay.Feature.PlayerCharacterGeneralShowSpotFeature" }
}, "BRPlayerCharacterBase")
