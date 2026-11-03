-- GTA-5-spezifisch: Knochen des Peds -> Koerperzone fuer den Bewusstlos-Bildschirm.
-- Zonen: head, torso, leftArm, rightArm, leftLeg, rightLeg. Links und rechts aus Sicht der Figur.
-- Unbekannte Knochen zaehlen als Oberkoerper. Beim Umzug wird nur diese Datei ersetzt.

BodyZoneOfBone = {
    [31086] = 'head',  -- SKEL_Head
    [12844] = 'head',  -- IK_Head
    [39317] = 'head',  -- SKEL_Neck_1

    [0] = 'torso',     -- SKEL_ROOT
    [11816] = 'torso', -- SKEL_Pelvis
    [57597] = 'torso', -- SKEL_Spine_Root
    [23553] = 'torso', -- SKEL_Spine0
    [24816] = 'torso', -- SKEL_Spine1
    [24817] = 'torso', -- SKEL_Spine2
    [24818] = 'torso', -- SKEL_Spine3
    [64729] = 'torso', -- SKEL_L_Clavicle
    [10706] = 'torso', -- SKEL_R_Clavicle

    [45509] = 'leftArm',  -- SKEL_L_UpperArm
    [61163] = 'leftArm',  -- SKEL_L_Forearm
    [18905] = 'leftArm',  -- SKEL_L_Hand
    [22711] = 'leftArm',  -- MH_L_Elbow
    [5232] = 'leftArm',   -- RB_L_ArmRoll
    [61007] = 'leftArm',  -- RB_L_ForeArmRoll

    [40269] = 'rightArm', -- SKEL_R_UpperArm
    [28252] = 'rightArm', -- SKEL_R_Forearm
    [57005] = 'rightArm', -- SKEL_R_Hand
    [2992] = 'rightArm',  -- MH_R_Elbow
    [37119] = 'rightArm', -- RB_R_ArmRoll
    [43810] = 'rightArm', -- RB_R_ForeArmRoll

    [58271] = 'leftLeg',  -- SKEL_L_Thigh
    [63931] = 'leftLeg',  -- SKEL_L_Calf
    [14201] = 'leftLeg',  -- SKEL_L_Foot
    [2108] = 'leftLeg',   -- SKEL_L_Toe0
    [46078] = 'leftLeg',  -- MH_L_Knee
    [23639] = 'leftLeg',  -- RB_L_ThighRoll

    [51826] = 'rightLeg', -- SKEL_R_Thigh
    [36864] = 'rightLeg', -- SKEL_R_Calf
    [52301] = 'rightLeg', -- SKEL_R_Foot
    [20781] = 'rightLeg', -- SKEL_R_Toe0
    [16335] = 'rightLeg', -- MH_R_Knee
    [6442] = 'rightLeg',  -- RB_R_ThighRoll
}

function BodyZone(bone)
    return BodyZoneOfBone[tonumber(bone) or -1] or 'torso'
end
