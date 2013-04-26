------------------------------------
--        Initialization          --
------------------------------------

local _G = getfenv(0)
local object = _G.object

object.behaviorLib = object.behaviorLib or {}
local core, eventsLib, behaviorLib, metadata = object.core, object.eventsLib, object.behaviorLib, object.metadata

local print, ipairs, pairs, string, table, next, type, tinsert, tremove, tsort, format, tostring, tonumber, strfind, strsub
	= _G.print, _G.ipairs, _G.pairs, _G.string, _G.table, _G.next, _G.type, _G.table.insert, _G.table.remove, _G.table.sort, _G.string.format, _G.tostring, _G.tonumber, _G.string.find, _G.string.sub
local ceil, floor, pi, tan, atan, atan2, abs, cos, sin, acos, max, random
	= _G.math.ceil, _G.math.floor, _G.math.pi, _G.math.tan, _G.math.atan, _G.math.atan2, _G.math.abs, _G.math.cos, _G.math.sin, _G.math.acos, _G.math.max, _G.math.random

local nSqrtTwo = math.sqrt(2)

behaviorLib.currentBehavior = nil
behaviorLib.lastBeahavior = nil

behaviorLib.tBehaviors = {}
behaviorLib.nNextBehaviorTime = HoN.GetGameTime()
behaviorLib.nBehaviorAssessInterval = 250

local BotEcho, VerboseLog, Clamp = core.BotEcho, core.VerboseLog, core.Clamp

--------------------------------------------
--          Common Complex Logic          --
--------------------------------------------
--
-- PositionSelf:   Determines the best position for the bot to be when they are idle
--                  - Based on creep wave position and proximity to nearby enemy towers
--
-- Port:           Determines if a bot should port to reach a destination
--
-- MoveExecute:    Determines best path to take to reach the desired position
--                  - Calls the port function at extreme distances
--

----------------------------------------
--         PositionSelfLogic          --
----------------------------------------
--
-- Execute:
-- Returns the best position for the bot to be at,
-- Also returns a nearby building to attack if possible
--

-------- Global Constants & Variables --------
behaviorLib.nHeroInfluencePercent = 0.75
behaviorLib.nPositionHeroInfluenceMul = 4.0
behaviorLib.nCreepPushbackMul = 1
behaviorLib.nTargetPositioningMul = 1
behaviorLib.nTargetCriticalPositioningMul = 2
behaviorLib.nLastPositionTime = 0
behaviorLib.vecLastDesiredPosition = Vector3.Create()
behaviorLib.nPositionSelfAllySeparation = 250
behaviorLib.nAllyInfluenceMul = 1.5

-------- Helper Functions --------
function behaviorLib.PositionSelfCreepWave(botBrain, unitCurrentTarget)
	local bDebugLines = false
	local bDebugEchos = false
	local nLineLen = 150

	if bDebugEchos then 
		BotEcho("PositionCreepWave") 
	end

	local unitSelf = core.unitSelf
	
	-- Don't run our calculations if we're basically in the same spot
	if unitSelf.bIsMemoryUnit and unitSelf.storedTime == behaviorLib.nLastPositionTime then
		return behaviorLib.vecLastDesiredPosition
	end
	
	-- Local references for improved performance
	local nHeroInfluencePercent = behaviorLib.nHeroInfluencePercent
	local nPositionHeroInfluenceMul = behaviorLib.nPositionHeroInfluenceMul
	local nCreepPushbackMul = behaviorLib.nCreepPushbackMul
	local vecLaneForward = object.vecLaneForward
	local vecLaneForwardOrtho = object.vecLaneForwardOrtho
	local funcGetThreat  = behaviorLib.GetThreat
	local funcGetDefense = behaviorLib.GetDefense
	local funcLethalityUtility = behaviorLib.LethalityDifferenceUtility
	local funcDistanceThreatUtility = behaviorLib.DistanceThreatUtility
	local funcGetAbsoluteAttackRangeToUnit = core.GetAbsoluteAttackRangeToUnit
	local funcV3Normalize = Vector3.Normalize
	local funcV3Dot = Vector3.Dot
	local funcAngleBetween = core.AngleBetween
	local funcRotateVec2DRad = core.RotateVec2DRad
		
	local vecMyPos = unitSelf:GetPosition()
	local tLocalUnits = core.localUnits
	local nMyThreat =  funcGetThreat(unitSelf)
	local nMyDefense = funcGetDefense(unitSelf)
	local vecBackUp = behaviorLib.PositionSelfBackUp()
	
	
	-- Avoid enemies if we recently drank bottle/health potion/mana potion
	local nExtraThreat = 0.0
	if (unitSelf:HasState("State_HealthPotion") or unitSelf:HasState("State_Bottle")) and unitSelf:GetHealthPercent() < 0.95 then
		nExtraThreat = 10.0
	end
	
	if (unitSelf:HasState("State_ManaPotion") or unitSelf:HasState("State_Bottle")) and unitSelf:GetManaPercent() < 0.95 then
		nExtraThreat = 10.0
	end
	
	
	--Stand appart from enemies
	local vecTotalEnemyInfluence = Vector3.Create()
	local tEnemyUnits = core.CopyTable(tLocalUnits.EnemyUnits)
	core.teamBotBrain:AddMemoryUnitsToTable(tEnemyUnits, core.enemyTeam, vecMyPos)
	
	StartProfile('Loop')
	for _, unitEnemy in pairs(tEnemyUnits) do
		StartProfile('Setup')
		local bIsHero = unitEnemy:IsHero()
		local vecEnemyPos = unitEnemy:GetPosition()
		local vecTheirRange = funcGetAbsoluteAttackRangeToUnit(unitEnemy, unitSelf)
		local vecTowardsMe, nEnemyDist = funcV3Normalize(vecMyPos - vecEnemyPos)
		local nDistanceMul = funcDistanceThreatUtility(nEnemyDist, vecTheirRange, unitEnemy:GetMoveSpeed(), false) / 100
		local vecEnemyInfluence = Vector3.Create()
		StopProfile()

		if not bIsHero then
			StartProfile('Creep')
			-- Stand away from creeps
			if bDebugEchos then 
				BotEcho('  creep unit: ' .. unitEnemy:GetTypeName()) 
			end
			
			vecEnemyInfluence = vecTowardsMe * (nDistanceMul + nExtraThreat)
			StopProfile()
		else
			StartProfile('Hero')
			-- Stand away from enemy heroes
			if bDebugEchos then 
				BotEcho('  hero unit: ' .. unitEnemy:GetTypeName()) 
			end
			
			local vecHeroDir = vecTowardsMe
			local vecBackwards = funcV3Normalize(vecBackUp - vecMyPos)
			vecHeroDir = vecHeroDir * nHeroInfluencePercent + vecBackwards * (1 - nHeroInfluencePercent)

			-- Calculate their lethality utility
			local nThreat = funcGetThreat(unitEnemy)
			local nDefense = funcGetDefense(unitEnemy)
			local nLethalityDifference = (nThreat - nMyDefense) - (nMyThreat - nDefense) 
			local nBaseMul = 1 + (Clamp(funcLethalityUtility(nLethalityDifference), 0, 100) / 50)
			local nLength = nBaseMul * nDistanceMul
			
			vecEnemyInfluence = vecHeroDir * nLength * nPositionHeroInfluenceMul			
			StopProfile()
		end
		
		StartProfile('Common')
		-- Enemies should not push the bot forward, flip it across the orthogonal line
		if vecLaneForward and funcV3Dot(vecEnemyInfluence, vecLaneForward) > 0 then
			local vecX = Vector3.Create(1,0)
			local nLaneOrthoAngle = funcAngleBetween(vecLaneForwardOrtho, vecX)
			local nInfluenceOrthoAngle = funcAngleBetween(vecEnemyInfluence, vecLaneForwardOrtho)
			local vecRelativeInfluence = funcRotateVec2DRad(vecEnemyInfluence, -nLaneOrthoAngle)
			if vecRelativeInfluence.y < 0 then
				nInfluenceOrthoAngle = -nInfluenceOrthoAngle
			end

			vecEnemyInfluence = funcRotateVec2DRad(vecEnemyInfluence, -nInfluenceOrthoAngle*2)
		end
		
		if not bIsHero then
			vecEnemyInfluence = vecEnemyInfluence * nCreepPushbackMul
		end

		vecTotalEnemyInfluence = vecTotalEnemyInfluence + vecEnemyInfluence

		if bDebugLines then 
			core.DrawDebugArrow(vecEnemyPos, vecEnemyPos + vecEnemyInfluence * nLineLen, 'teal') 
		end
		
		if bDebugEchos and unitEnemy then 
			BotEcho(unitEnemy:GetTypeName()..': '..tostring(vecEnemyInfluence)) 
		end
		StopProfile()
	end

	-- Stand appart from allies a bit
	StartProfile('Allies')
	local tAllyHeroes = tLocalUnits.AllyHeroes
	local vecTotalAllyInfluence = Vector3.Create()
	local nAllyInfluenceMul = behaviorLib.nAllyInfluenceMul
	local nPositionSelfAllySeparation = behaviorLib.nPositionSelfAllySeparation
	for _, unitAlly in pairs(tAllyHeroes) do
		local vecAllyPos = unitAlly:GetPosition()
		local vecCurrentAllyInfluence, nDistance = funcV3Normalize(vecMyPos - vecAllyPos)
		if nDistance < nPositionSelfAllySeparation then
			vecCurrentAllyInfluence = vecCurrentAllyInfluence * (1 - nDistance/nPositionSelfAllySeparation) * nAllyInfluenceMul
			vecTotalAllyInfluence = vecTotalAllyInfluence + vecCurrentAllyInfluence
			
			if bDebugLines then 
				core.DrawDebugArrow(vecMyPos, vecMyPos + vecCurrentAllyInfluence * nLineLen, 'white') 
			end
		end
	end
	StopProfile()

	-- Stand near your target
	StartProfile('Target')
	local vecTargetInfluence = Vector3.Create()
	local nTargetMul = behaviorLib.nTargetPositioningMul
	if unitCurrentTarget and botBrain:CanSeeUnit(unitCurrentTarget) then
		local nMyRange = core.GetAbsoluteAttackRangeToUnit(unitSelf, unitCurrentTarget)
		local vecTargetPosition = unitCurrentTarget:GetPosition()
		local vecToTarget, nTargetDist = funcV3Normalize(vecTargetPosition - vecMyPos)
		local nLength = 1
		if not unitCurrentTarget:IsHero() then
			nLength = nTargetDist / nMyRange
			if bDebugEchos then 
				BotEcho('  nLength calc - nTargetDist: '..nTargetDist..'  nMyRange: '..nMyRange) 
			end
		end

		nLength = Clamp(nLength, 0, 25)

		--Hack: Get closer if they are critical health and the bot is out of nRange
		if unitCurrentTarget:GetHealth() < (core.GetFinalAttackDamageAverage(unitSelf) * 3) then --and nTargetDist > nMyRange then
			nTargetMul = behaviorLib.nTargetCriticalPositioningMul
		end
		
		vecTargetInfluence = vecToTarget * nLength * nTargetMul
		if bDebugEchos then 
			BotEcho('  target '..unitCurrentTarget:GetTypeName()..': '..tostring(vecTargetInfluence)..'  nLength: '..nLength) 
		end
	else 
		if bDebugEchos then 
			BotEcho("PositionSelfCreepWave - target is nil")
		end
	end
	StopProfile()

	-- Sum of all influences
	local vecDesiredPos = vecMyPos
	local vecDesired = vecTotalEnemyInfluence + vecTargetInfluence + vecTotalAllyInfluence
	local vecMove = vecDesired * core.moveVecMultiplier

	if bDebugEchos then 
		BotEcho('vecDesiredPos: '..tostring(vecDesiredPos)..'  vCreepInfluence: '..tostring(vecTotalEnemyInfluence)..'  vecTargetInfluence: '..tostring(vecTargetInfluence)) 
	end

	-- Don't return a move if it's too close to the bots current position
	if Vector3.LengthSq(vecMove) >= core.distSqTolerance then
		vecDesiredPos = vecDesiredPos + vecMove
	end
	
	behaviorLib.nLastPositionTime = unitSelf.storedTime
	behaviorLib.vecLastDesiredPosition = vecDesiredPos

	if bDebugLines then
		if vecLaneForward then
			local offset = vecLaneForwardOrtho * (nLineLen * 3)
			core.DrawDebugArrow(vecMyPos + offset, vecMyPos + offset + vecLaneForward * nLineLen, 'white')
			core.DrawDebugArrow(vecMyPos - offset, vecMyPos - offset + vecLaneForward * nLineLen, 'white')
		end

		core.DrawDebugArrow(vecMyPos, vecMyPos + vecTotalEnemyInfluence * nLineLen, 'cyan')
		if unitCurrentTarget ~= nil and botBrain:CanSeeUnit(unitCurrentTarget) then
			local color = 'cyan'
			if nTargetMul ~= behaviorLib.nTargetPositioningMul then
				color = 'orange'
			end
			
			core.DrawDebugArrow(vecMyPos, vecMyPos + vecTargetInfluence * nLineLen, color)
		end

		core.DrawXPosition(vecDesiredPos, 'blue')
		core.DrawDebugArrow(vecMyPos, vecMyPos + vecDesired * nLineLen, 'blue')
	end

	return vecDesiredPos
end

function behaviorLib.PositionSelfTraverseLane(botBrain)
	local bDebugLines = false
	local bDebugEchos = false

	local vecDesiredPos = nil
	
	if bDebugEchos then
		BotEcho("In PositionSelfTraverseLane") 
	end
	
	local tLane = core.tMyLane
	if tLane then
		local vecFurthest = core.GetFurthestCreepWavePos(tLane, core.bTraverseForward)
		if vecFurthest then
			vecDesiredPos = vecFurthest
		else
			if bDebugEchos then 
				BotEcho("PositionSelfTraverseLane - can't fine furthest creep wave pos in lane " .. tLane.sLaneName) 
			end
			
			vecDesiredPos = core.enemyMainBaseStructure:GetPosition()
		end
	else
		BotEcho('PositionSelfTraverseLane - unable to get my lane!')
	end
	
	if bDebugLines then
		local vecMyPos = core.unitSelf:GetPosition()
		core.DrawDebugArrow(vecMyPos, vecDesiredPos, 'white')
	end

	return vecDesiredPos
end

function behaviorLib.ChooseBuildingTarget(tBuildings, vecPosition)
	local tSortedBuildings = core.SortBuildings(tBuildings)
	local unitTarget = nil
	
	-- Throne
	if tSortedBuildings.enemyMainBaseStructure and not tSortedBuildings.enemyMainBaseStructure:IsInvulnerable() then
		unitTarget = tSortedBuildings.enemyMainBaseStructure
	end

	-- Rax
	if not unitTarget then
		local tRax = tSortedBuildings.enemyRax
		if core.NumberElements(tRax) > 0 then
			local unitTargetRax = nil
			for _, unitRax in pairs(tRax) do
				if not unitRax:IsInvulnerable() and (unitTargetRax == nil or not unitTargetRax:IsUnitType("MeleeRax")) then
					unitTargetRax = unitRax
				end
			end

			unitTarget = unitTargetRax
		end
	end

	-- Towers		
	if not unitTarget then
		local tTowers = tSortedBuildings.enemyTowers
		if core.NumberElements(tTowers) > 0 then
			local nClosestSq = 999999999
			for _, unitTower in pairs(tTowers) do
				if not unitTower:IsInvulnerable() then
					local nDistanceSq = Vector3.Distance2DSq(vecPosition, unitTower:GetPosition())
					if nDistanceSq < nClosestSq then
						unitTarget = unitTower
						nClosestSq = nDistanceSq
					end
				end
			end
		end
	end

	-- Other Buildings
	if not unitTarget then
		local tOthers = tSortedBuildings.enemyOtherBuildings
		if core.NumberElements(tOthers) > 0 then
			local nClosestSq = 999999999
			for _, unitBbuilding in pairs(tOthers) do
				if not unitBbuilding:IsInvulnerable() then
					local nDistanceSq = Vector3.Distance2DSq(vecPosition, unitBbuilding:GetPosition())
					if nDistanceSq < nClosestSq then
						unitTarget = unitBbuilding
						nClosestSq = nDistanceSq
					end
				end
			end
		end
	end
		
	return unitTarget
end

function behaviorLib.PositionSelfBuilding(unitBuilding)
	local bDebugLines = false
	
	if unitBuilding == nil then
		return nil
	end

	local vecMyPos = core.unitSelf:GetPosition()
	local vecTargetPosition = unitBuilding:GetPosition()
	local vecTowardsTarget = Vector3.Normalize(vecTargetPosition - vecMyPos)
	local nRange = core.GetAbsoluteAttackRangeToUnit(core.unitSelf, unitBuilding)
	local nDistance = nRange - 50
	local vecDesiredPos = vecTargetPosition + (-vecTowardsTarget) * nDistance
	
	if bDebugLines then
		local lineLen = 150
		local vecTargetPosition = unitBuilding:GetPosition()
		local vecOrtho = Vector3.Create(-vecTowardsTarget.y, vecTowardsTarget.x) --quick 90 rotate z
		core.DrawDebugArrow(vecMyPos, vecMyPos + vecTowardsTarget * nRange, 'orange')
		core.DrawDebugLine((vecMyPos + vecTowardsTarget * nRange) - (vecOrtho * 0.5 * lineLen), (vecMyPos + vecTowardsTarget * nRange) + (vecOrtho * 0.5 * lineLen), 'orange')		
		core.DrawXPosition(vecDesiredPos, 'blue')	
		core.DrawXPosition(vecTargetPosition, 'red')
	end
	
	return vecDesiredPos
end

-------- Logic Function --------
function behaviorLib.PositionSelfLogic(botBrain)
	StartProfile("PositionSelfLogic")
	local bDebugEchos = false
	
	local vecMyPos = core.unitSelf:GetPosition()
	local vecDesiredPos = nil
	
	local unitTarget = nil
	local tLocalUnits = core.localUnits
	
	local vecLanePosition = behaviorLib.PositionSelfTraverseLane(botBrain)
	local nLaneDistanceSq =  Vector3.Distance2DSq(vecLanePosition, vecMyPos)
	-- If we are massivly out of position, ignore the other positioning logic and just go
	if nLaneDistanceSq < core.nOutOfPositionRangeSq then
		if not vecDesiredPos and core.NumberElements(tLocalUnits["EnemyUnits"]) > 0 then
			if bDebugEchos then 
				BotEcho("PositionSelfCreepWave") 
			end
			
			StartProfile("PositionSelfCreepWave")
			unitTarget = core.unitCreepTarget
			vecDesiredPos = behaviorLib.PositionSelfCreepWave(botBrain, unitTarget, tLocalUnits)
			StopProfile()
		end	
		
		if not vecDesiredPos and core.HasBuildingTargets(tLocalUnits["EnemyBuildings"]) and core.NumberElements(tLocalUnits["AllyCreeps"]) > 0 then
			--This ignores misc. buildings
			if bDebugEchos then 
				BotEcho("PositionSelfBuilding") 
			end
			
			StartProfile("Get building unitTarget")
			unitTarget = behaviorLib.ChooseBuildingTarget(tLocalUnits["EnemyBuildings"], vecMyPos)
			StopProfile()
			
			StartProfile("PositionSelfBuilding")
			vecDesiredPos = behaviorLib.PositionSelfBuilding(unitTarget)
			StopProfile()
		end
	end
	
	if not vecDesiredPos then
		if bDebugEchos then 
			BotEcho("PositionSelfTraverseLane") 
		end
		
		StartProfile("PositionSelfTraverseLane")
		vecDesiredPos = vecLanePosition
		StopProfile()
	end
		
	if vecDesiredPos then
		if bDebugEchos then 
			BotEcho("Adjusting PositionSelf for Towers") 
		end
		
		local bCanEnterTowerRange = true
		if core.NumberElements(tLocalUnits["EnemyHeroes"]) > 0 then
			bCanEnterTowerRange = false
		end		
					
		StartProfile("AdjustMovementForTowerLogic")
		vecDesiredPos = core.AdjustMovementForTowerLogic(vecDesiredPos, bCanEnterTowerRange)
		StopProfile()
	end
	StopProfile()
	
	return vecDesiredPos, unitTarget
end

---------------------------------
--          PortLogic          --
---------------------------------
--
-- Execute:
-- Checks if porting will be faster then walking to get to the desired location
-- Will use Homecoming Stone or Post Haste
--

-------- Global Constants & Variables --------
behaviorLib.nPortThresholdMS = 9000
behaviorLib.bCheckPorting = true
behaviorLib.bLastPortResult = false

-------- Helper Functions --------
function behaviorLib.ShouldPort(vecDesiredPosition)
	local bDebugEchos = false
	local bDebugLines = false
	
	if not vecDesiredPosition then
		BotEcho("ShouldPort recieved a nil position")
		return nil
	end

	local bShouldPort = false
	local unitTarget = nil
	local itemPort = nil

	local unitSelf = core.unitSelf
	local nChannelTime = 3000
	local tInventory = unitSelf:GetInventory()
	local itemGhostMarchers = core.itemGhostMarchers
	
	if not itemPort then
		local idefHomecomingStone = HoN.GetItemDefinition("Item_HomecomingStone")
		if idefHomecomingStone then
			local tHomecomingStones = core.InventoryContains(tInventory, idefHomecomingStone:GetName(), true)
			if #tHomecomingStones > 0 then
				itemPort = tHomecomingStones[1]
				unitTarget = core.GetClosestTeleportBuilding(vecDesiredPosition)

				if bDebugEchos then
					BotEcho("  unitTarget: "..(unitTarget and unitTarget:GetTypeName() or "nil")) 
				end

				if unitTarget then
					local nMoveSpeed = unitSelf:GetMoveSpeed()
					local myPos = unitSelf:GetPosition()
					local nNormalWalkingTimeMS = core.TimeToPosition(vecDesiredPosition, myPos, nMoveSpeed, itemGhostMarchers)
					local nCooldownTime = core.GetRemainingCooldownTime(unitSelf, idefHomecomingStone)
					local nPortWalkTime = core.TimeToPosition(vecDesiredPosition, unitTarget:GetPosition(), nMoveSpeed, itemGhostMarchers)
					local nPortingTimeMS = nCooldownTime + nPortWalkTime + nChannelTime
					local nPortDifference = nNormalWalkingTimeMS - nPortingTimeMS

					if nPortDifference > behaviorLib.nPortThresholdMS then
						bShouldPort = true
					end
					
					if bDebugEchos then 
						BotEcho(format("  walkingTime: %d  -  portTime: %d (cd: %d, walk: %d)  =  diff: %d  v  threshold: %d", 
							nNormalWalkingTimeMS, nPortingTimeMS, nCooldownTime, nPortWalkTime, nPortDifference, behaviorLib.nPortThresholdMS)) 
						BotEcho("Traversing forward... port: "..tostring(bShouldPort)) 
					end

					if bDebugLines then
						core.DrawXPosition(unitTarget:GetPosition(), 'teal')
						core.DrawDebugLine(myPos, unitTarget:GetPosition())
						core.DrawXPosition(vecDesiredPosition, 'red')
					end
				end
			end
		end
	end
		
	if not itemPort then
		local idefPostHaste = HoN.GetItemDefinition("Item_PostHaste")
		if idefPostHaste then
			local tPostHaste = core.InventoryContains(tInventory, idefPostHaste:GetName(), true)
			if #tPostHaste > 0 then
				itemPort = tPostHaste[1]
				unitTarget = core.GetClosestTeleportBuilding(vecDesiredPosition)

				if bDebugEchos then
					BotEcho("  unitTarget: "..(unitTarget and unitTarget:GetTypeName() or "nil")) 
				end

				if unitTarget then
					local nMoveSpeed = unitSelf:GetMoveSpeed()
					local myPos = unitSelf:GetPosition()
					local nNormalWalkingTimeMS = core.TimeToPosition(vecDesiredPosition, myPos, nMoveSpeed, itemGhostMarchers)
					local nCooldownTime = core.GetRemainingCooldownTime(unitSelf, idefPostHaste)
					local nPortWalkTime = core.TimeToPosition(vecDesiredPosition, unitTarget:GetPosition(), nMoveSpeed, itemGhostMarchers)
					local nPortingTimeMS = nCooldownTime + nPortWalkTime + nChannelTime
					local nPortDifference = nNormalWalkingTimeMS - nPortingTimeMS

					if nPortDifference > behaviorLib.nPortThresholdMS then
						bShouldPort = true
					end
					
					if bDebugEchos then 
						BotEcho(format("  walkingTime: %d  -  portTime: %d (cd: %d, walk: %d)  =  diff: %d  v  threshold: %d", 
							nNormalWalkingTimeMS, nPortingTimeMS, nCooldownTime, nPortWalkTime, nPortDifference, behaviorLib.nPortThresholdMS)) 
						BotEcho("Traversing forward... port: "..tostring(bShouldPort)) 
					end

					if bDebugLines then
						core.DrawXPosition(unitTarget:GetPosition(), 'teal')
						core.DrawDebugLine(myPos, unitTarget:GetPosition())
						core.DrawXPosition(vecDesiredPosition, 'red')
					end
				end
			end
		end
	end

	return bShouldPort, unitTarget, itemPort
end

-------- Logic Functions --------
function behaviorLib.PortLogic(botBrain, vecDesiredPosition)
	local bDebugEchos = false

	local unitSelf = core.unitSelf
	if behaviorLib.bLastPortResult and not unitSelf:IsChanneling() then
		-- Port didn't go off, try again
		behaviorLib.bCheckPorting = true
	end
		
	if behaviorLib.bCheckPorting then
		behaviorLib.bCheckPorting = false
		local nDesiredDistanceSq = Vector3.Distance2DSq(vecDesiredPosition, unitSelf:GetPosition())
		local bSuccess = false
		if nDesiredDistanceSq > (2000 * 2000) then
			local bShouldPort, unitTarget, itemPort = behaviorLib.ShouldPort(vecDesiredPosition)
			if bShouldPort and unitTarget and itemPort then
				if itemPort:GetTypeName() == "Item_HomecomingStone" then
					-- Add noise to the position to prevent clustering on mass ports
					local nX = core.RandomReal(-1, 1)
					local nY = core.RandomReal(-1, 1)
					local vecDirection = Vector3.Normalize(Vector3.Create(nX, nY))
					local nDistance = random(100, 400)
					local vecTarget = unitTarget:GetPosition() + vecDirection * nDistance
					
					bSuccess = core.OrderItemPosition(botBrain, unitSelf, itemPort, vecTarget)
				elseif itemPort:GetTypeName() == "Item_PostHaste" then
					bSuccess = core.OrderItemEntityClamp(botBrain, unitSelf, itemPort, unitTarget)
				end
				
				if bSuccess then
					core.nextOrderTime = HoN.GetGameTime() + core.timeBetweenOrders --seed some extra time in there
				end
			end
		end
		
		if bDebugEchos then 
			BotEcho("PortLogic, ran logic. Ported: "..tostring(bSuccess)) 
		end
		
		behaviorLib.bLastPortResult = bSuccess
	end
	
	return behaviorLib.bLastPortResult
end

-----------------------------------
--          MoveExecute          --
-----------------------------------
--
-- Execute:
-- Decides how to get to the desired position
-- Will port if it saves enough time, otherwise uses pathing
--

-------- Global Constants & Variables --------
behaviorLib.nPathEnemyTerritoryMul = 1.5
behaviorLib.nPathBaseMul = 1.75
behaviorLib.nPathTowerMul = 3.0
behaviorLib.tPath = nil
behaviorLib.nPathNode = 1
behaviorLib.vecGoal = Vector3.Create()
behaviorLib.nGoalToleranceSq = 750*750
behaviorLib.nPathDistanceToleranceSq = 300*300

-------- Helper Functions --------
function behaviorLib.PathLogic(botBrain, vecDesiredPosition)
	local bDebugLines = false
	local bDebugEchos = false
	local bMarkProperties = false
	local bRepath = false
	
	-- If the new destination is too far from the old destination then repath
	if Vector3.Distance2DSq(vecDesiredPosition, behaviorLib.vecGoal) > behaviorLib.nGoalToleranceSq then
		bRepath = true
	end
	
	local unitSelf = core.unitSelf
	local vecMyPosition = unitSelf:GetPosition()
	
	if bRepath then
		if bDebugEchos then 
			BotEcho("Repathing!") 
		end
		
		local sEnemyZone = "hellbourne"
		if core.myTeam == HoN.GetHellbourneTeam() then
			sEnemyZone = "legion"
		end
		
		if bDebugEchos then 
			BotEcho("enemy zone: "..sEnemyZone) 
		end
		
		local nEnemyTerritoryMul = behaviorLib.nPathEnemyTerritoryMul
		local nTowerMul = behaviorLib.nPathTowerMul
		local nBaseMul = behaviorLib.nPathBaseMul
		
		local function funcNodeCost(nodeParent, nodeCurrent, link, nOriginalCost)
			--TODO: local nDistance = link:GetLength()
			local nDistance = Vector3.Distance(nodeParent:GetPosition(), nodeCurrent:GetPosition())
			local nCostToParent = nOriginalCost - nDistance
			local sZoneProperty  = nodeCurrent:GetProperty("zone")
			local bTowerProperty = nodeCurrent:GetProperty("tower")
			local bBaseProperty  = nodeCurrent:GetProperty("base")
			
			local nMultiplier = 1.0
			local bEnemyZone = false
			if sZoneProperty and sZoneProperty == sEnemyZone then
				bEnemyZone = true
			end
			
			if bEnemyZone then
				nMultiplier = nMultiplier + nEnemyTerritoryMul
				if bBaseProperty then
					nMultiplier = nMultiplier + nBaseMul
				end
				
				if bTowerProperty then
					-- Check if the tower is alive
					local tBuildings = HoN.GetUnitsInRadius(nodeCurrent:GetPosition(), 800, core.UNIT_MASK_ALIVE + core.UNIT_MASK_BUILDING)
					for _, unitBuilding in pairs(tBuildings) do
						if unitBuilding:IsTower() then
							nMultiplier = nMultiplier + nTowerMul
							break
						end
					end
				end				
			end
			
			return nCostToParent + nDistance * nMultiplier
		end
	
		behaviorLib.tPath = BotMetaData.FindPath(vecMyPosition, vecDesiredPosition, funcNodeCost)
		behaviorLib.vecGoal = vecDesiredPosition
		behaviorLib.nPathNode = 1
		
		-- Double check that the first node is on the way to the destination (So we don't backtrack)
		local tPath = behaviorLib.tPath
		if #tPath > 1 then
			local vecMeToFirst = tPath[1]:GetPosition() - vecMyPosition
			local vecFirstToSecond = tPath[2]:GetPosition() - tPath[1]:GetPosition()
			-- If the first node would cause the bot to go backwards then skip to the second node
			if Vector3.Dot(vecMeToFirst, vecFirstToSecond) < 0 then
				behaviorLib.nPathNode = 2
			end
		end
	end
	
	-- Follow path logic
	local vecReturn = nil
	local tPath = behaviorLib.tPath
	local nPathNode = behaviorLib.nPathNode
	if tPath then
		local vecCurrentNode = tPath[nPathNode]
		if vecCurrentNode then
			-- If the bot is too close to the current node then use the next one
			if Vector3.Distance2DSq(vecCurrentNode:GetPosition(), vecMyPosition) < behaviorLib.nPathDistanceToleranceSq then
				nPathNode = nPathNode + 1
				behaviorLib.nPathNode = nPathNode				
			end
			
			local nodeWaypoint = tPath[behaviorLib.nPathNode]
			if nodeWaypoint then
				vecReturn = nodeWaypoint:GetPosition()
			end
		end
	end
	
	if bDebugLines then
		if tPath then
			local nLineLen = 300
			local vecLastNodePosition = nil
			for _, node in ipairs(tPath) do
				local vecNodePosition = node:GetPosition()
				if bMarkProperties then
					local sZoneProperty  = node:GetProperty("zone")
					local bTowerProperty = node:GetProperty("tower")
					local bBaseProperty  = node:GetProperty("base")
					
					local bEnemyZone = false
					local sEnemyZone = "hellbourne"
					if core.myTeam == HoN.GetHellbourneTeam() then
						sEnemyZone = "legion"
					end
					if sZoneProperty and sZoneProperty == sEnemyZone then
						bEnemyZone = true
					end				
					if bEnemyZone then
						core.DrawDebugLine(vecNodePosition, vecNodePosition + Vector3.Create(0, 1) * nLineLen, "red")
						if bBaseProperty then
							core.DrawDebugLine(vecNodePosition, vecNodePosition + Vector3.Create(1, 0) * nLineLen, "orange")
						end
						if bTowerProperty then
							--check if the tower is there
							local tBuildings = HoN.GetUnitsInRadius(node:GetPosition(), 800, core.UNIT_MASK_ALIVE + core.UNIT_MASK_BUILDING)
							for _, unitBuilding in pairs(tBuildings) do
								if unitBuilding:IsTower() then
									core.DrawDebugLine(vecNodePosition, vecNodePosition + Vector3.Create(-1, 0) * nLineLen, "yellow")
									break
								end
							end
						end
					end
				end
			
				if vecLastNodePosition then
					--node to node
					if bDebugLines then
						core.DrawDebugArrow(vecLastNodePosition, vecNodePosition, 'blue')
					end
				end
				vecLastNodePosition = vecNodePosition
			end
			core.DrawXPosition(vecReturn, 'yellow')
			core.DrawXPosition(behaviorLib.vecGoal, "orange")
			core.DrawXPosition(vecDesiredPosition, "teal")
		end
	end	
	
	return vecReturn				
end

-------- Logic Function --------
function behaviorLib.MoveExecute(botBrain, vecDesiredPosition)
	local bDebugEchos = false
	local bActionTaken = false
	local unitSelf = core.unitSelf
	local vecMyPosition = unitSelf:GetPosition()
	local vecMovePosition = vecDesiredPosition
	
	if Vector3.Distance2DSq(vecDesiredPosition, vecMyPosition) > core.nOutOfPositionRangeSq then
		-- Check if porting would save time
		if not bActionTaken then
			StartProfile("PortLogic")
			bActionTaken  = behaviorLib.PortLogic(botBrain, vecDesiredPosition)
			StopProfile()
		end
		
		-- Use Pathing to find a way
		if not bActionTaken then
			if bDebugEchos then 
				BotEcho("Pathin'") 
			end

			StartProfile("PathLogic")
			local vecWaypoint = behaviorLib.PathLogic(botBrain, vecDesiredPosition)
			StopProfile()
			
			if vecWaypoint then
				vecMovePosition = vecWaypoint
			end
		end
	end
	
	-- If everything else fails, just move to location
	if not bActionTaken then
		if bDebugEchos then 
			BotEcho("Move 'n' hold order") 
		end
		
		bActionTaken = core.OrderMoveToPosAndHoldClamp(botBrain, unitSelf, vecMovePosition)
	end
	
	return bActionTaken
end

---------------------------------
--          Behaviors          --
---------------------------------
--
-- HarassHero:          0 to 100    Based on:
--                                   - Distance
--                                   - Relative Health Percent
--                                   - Range
--                                   - Attack Advantage
--                                   - Proximity to Towers
--                                   - Momentum
--
-- RetreatFromThreat:   0 to 100    Based on :
--                                   - Potential damage from aggro'd creeps
--                                   - Potential damage from aggro'd towers
--                                   - Number of incoming tower projectiles
--                                   - Local units
--
-- HealAtWell:          0 to 100    Based on:
--                                   - Missing Health
--                                   - Proximity to well
--
-- DontBreakChannel:    100 or 0    If channeling
--
-- Shop:                99          If just got into shop and not done buying
--
-- PreGame:             98 or 0     If before the 0:00 mark
--
-- HitBulding:          40          If throne
--                      36          If rax
--                      25          If tower
--                      23          If other building
--                                   - Only if target is not invulnerable, in range, and will not draw aggro
--
-- TeamGroup:           35 or 0     If teambrain tells us
--
-- AttackCreeps:        24          If last hit. 
--                      21          If deny. 
--                                   - Only if they are within 1 hit (no prediction)
--
-- TeamDefend:          23 or 0     If the teambrain tells us
--
-- Push:                0 to 22     Based on:
--                                   - Number of enemy heroes that are dead
--                                   - Pushing power
--
-- UseHealthRegen:      20 to 30    When we want to use Runes of the Blight
--                      20 to 40    When we want to use Health Potions
--                      20 to 40    When we want to use Bottle
--                                   - Will retreat to drink Health Potion/Use Bottle if not safe
--
-- UseManaRegen:        20 to 40    When we want to use Mana Potions
--                      20 to 40    When we want to use Bottle
--                                   - Will retreat to drink Mana Potion/Use Bottle if not safe
--
-- PositionSelf:        20          Always 20
--                                   - If there are enemy creeps, positions self based on the creep wave location
--                                   - If there are enemy buildings, positions self based on the building locations
--                                   - Otherwise walk the lane
--                                   - Use homecoming Stone if it saves more than 9000ms
--                                   - Activates Ghost Marchers if able
--

-------- Shared Behavior Functions --------
function behaviorLib.RelativeHealthUtility(nRelativePercentHP)
	local nUtility = 0
	local vecOrigin = Vector3.Create(0, 0)
	local vecMax = Vector3.Create(0.8, 100)
	local vecMin = Vector3.Create(-0.45, -100)

	nUtility = core.UnbalancedSRootFn(nRelativePercentHP, vecMax, vecMin, vecOrigin, 1.5)

	nUtility = Clamp(nUtility, -100, 100)

	return nUtility
end

function behaviorLib.DistanceThreatUtility(nDist, nRange, nMoveSpeed, bAttackReady)
	local nUtility = 0

	if nDist < nRange and bAttackReady then
		nUtility = 100
	else
		local nXShift = nRange
		local nX = max(nDist - nXShift, 0)

		nUtility = core.ExpDecay(nX, 100, nMoveSpeed, 0.5)
	end

	nUtility = Clamp(nUtility, 0, 100)

	return nUtility
end

function behaviorLib.RelativeRangeUtility(nRelativeRange)
	local nUtility = 0

	local nMultiplier = 100/(625-128)

	nUtility = nMultiplier * nRelativeRange

	nUtility = Clamp(nUtility, -100, 100)

	return nUtility
end

-------------------------------
--          PreGame          --
-------------------------------
--
-- Utility: 0 or 98
-- If Match Time is less then one returns 98, otherwise 0
--
-- Execute: 
-- Hold in the fountain
-- Move to lanes before game starts
--

-------- Behavior Functions --------
function behaviorLib.PreGameUtility(botBrain)
	local nUtility = 0

	if HoN:GetMatchTime() <= 0 then
		nUtility = 98
	end

	if botBrain.bDebugUtility == true and nUtility ~= 0 then
		BotEcho(format("  PreGameUtility: %g", nUtility))
	end

	return nUtility
end

function behaviorLib.PreGameExecute(botBrain)
	local bActionTaken = false

	if not bActionTaken then
		-- Wait in well while Human players pick lanes
		if HoN.GetRemainingPreMatchTime() > core.teamBotBrain.nInitialBotMove then        
			bActionTaken = core.OrderHoldClamp(botBrain, core.unitSelf)
		else
			local vecTargetPos = behaviorLib.PositionSelfTraverseLane(botBrain)
			bActionTaken = core.OrderMoveToPosClamp(botBrain, core.unitSelf, vecTargetPos, false)
		end
	end
	
	return bActionTaken
end

behaviorLib.PreGameBehavior = {}
behaviorLib.PreGameBehavior["Utility"] = behaviorLib.PreGameUtility
behaviorLib.PreGameBehavior["Execute"] = behaviorLib.PreGameExecute
behaviorLib.PreGameBehavior["Name"] = "PreGame"
tinsert(behaviorLib.tBehaviors, behaviorLib.PreGameBehavior)

------------------------------------
--          AttackCreeps          --
------------------------------------
--
-- Utility: 21 or 24
-- If last hit 24, If deny 21
--
-- Execute: 
-- Attack target creep
--

-------- Helper Functions --------
function behaviorLib.GetCreepAttackTarget(botBrain, unitEnemyCreep, unitAllyCreep)
	local bDebugEchos = false
	local unitSelf = core.unitSelf
	local nDamageAverage = core.GetFinalAttackDamageAverage(unitSelf)
	
	local tItemHatchet = core.InventoryContains(unitSelf:GetInventory(), "Item_LoggersHatchet")
	if #tItemHatchet > 0 then
		nDamageAverage = nDamageAverage * core.itemHatchet.creepDamageMul
	end	
	
	-- [Difficulty: Easy] Make bots worse at last hitting
	if core.nDifficulty == core.nEASY_DIFFICULTY then
		nDamageAverage = nDamageAverage + 120
	end

	if unitEnemyCreep and core.CanSeeUnit(botBrain, unitEnemyCreep) then
		local nTargetHealth = unitEnemyCreep:GetHealth()
		if nDamageAverage >= nTargetHealth then
			local bActuallyLH = true
			
			-- [Tutorial] Make DS not mess with your last hitting before shit gets real
			if core.bIsTutorial and core.bTutorialBehaviorReset == false and core.unitSelf:GetTypeName() == "Hero_Shaman" then
				bActuallyLH = false
			end
			
			if bActuallyLH then
				if bDebugEchos then 
					BotEcho("Returning an enemy") 
				end

				return unitEnemyCreep
			end
		end
	end

	if unitAllyCreep then
		local nTargetHealth = unitAllyCreep:GetHealth()
		if nDamageAverage >= nTargetHealth then
			local bActuallyDeny = true
			
			--[Difficulty: Easy] Don't deny
			if core.nDifficulty == core.nEASY_DIFFICULTY then
				bActuallyDeny = false
			end			
			
			-- [Tutorial] Hellbourne *will* deny creeps after shit gets real
			if core.bIsTutorial and core.bTutorialBehaviorReset == true and core.myTeam == HoN.GetHellbourneTeam() then
				bActuallyDeny = true
			end
			
			if bActuallyDeny then
				if bDebugEchos then 
					BotEcho("Returning an ally") 
				end
				
				return unitAllyCreep
			end
		end
	end

	return nil
end

-------- Behavior Functions --------
function behaviorLib.AttackCreepsUtility(botBrain)	
	local nDenyVal = 21
	local nLastHitVal = 24
	local nUtility = 0

	-- Don't deny while pushing
	local unitDenyTarget = core.unitAllyCreepTarget
	if core.GetCurrentBehaviorName(botBrain) == "Push" then
		unitDenyTarget = nil
	end
	
	local unitTarget = behaviorLib.GetCreepAttackTarget(botBrain, core.unitEnemyCreepTarget, unitDenyTarget)
	
	if unitTarget and core.unitSelf:IsAttackReady() then
		if unitTarget:GetTeam() == core.myTeam then
			nUtility = nDenyVal
		else
			nUtility = nLastHitVal
		end
		
		core.unitCreepTarget = unitTarget
	end

	if botBrain.bDebugUtility == true and nUtility ~= 0 then
		BotEcho(format("  AttackCreepsUtility: %g", nUtility))
	end

	return nUtility
end

function behaviorLib.AttackCreepsExecute(botBrain)
	local bActionTaken = false
	local unitSelf = core.unitSelf
	local unitTarget = core.unitCreepTarget

	-- The bot has no target/can not see the target
	if not unitTarget or not core.CanSeeUnit(botBrain, unitTarget) then
		return bActionTaken
	end
	
	local vecTargetPos = unitTarget:GetPosition()
	local nDistSq = Vector3.Distance2DSq(unitSelf:GetPosition(), vecTargetPos)
	local nAttackRangeSq = core.GetAbsoluteAttackRangeToUnit(unitSelf, unitTarget, true)
	
	-- Attack creeps if they are in range
	if not bActionTaken and nDistSq < nAttackRangeSq and unitSelf:IsAttackReady() then
		--only attack when in nRange, so not to aggro towers/creeps until necessary, and move forward when attack is on cd
		bActionTaken = core.OrderAttackClamp(botBrain, unitSelf, unitTarget)
	end
	
	-- Use Loggers Hatchet
	if not bActionTaken then
		local tItemHatchet = core.InventoryContains(unitSelf:GetInventory(), "Item_LoggersHatchet")
		if #tItemHatchet > 0 then
			local itemHatchet = tItemHatchet[1]
			if itemHatchet:CanActivate() and unitTarget:GetTeam() ~= unitSelf:GetTeam() and string.find(unitTarget:GetTypeName(), "Creep") and core.GetAttackSequenceProgress(unitSelf) ~= "windup" and nDistSq < 600 * 600 then
				bActionTaken = core.OrderItemEntityClamp(botBrain, unitSelf, itemHatchet, unitTarget)
			end
		end
	end
	
	-- Move towards creeps if out of range
	if not bAtionTaken then
		local vecDesiredPos = core.AdjustMovementForTowerLogic(vecTargetPos)
		if vecDesiredPos then
			bActionTaken = core.OrderMoveToPosClamp(botBrain, unitSelf, vecDesiredPos, false)
		end
	end
	
	return bActionTaken
end

behaviorLib.AttackCreepsBehavior = {}
behaviorLib.AttackCreepsBehavior["Utility"] = behaviorLib.AttackCreepsUtility
behaviorLib.AttackCreepsBehavior["Execute"] = behaviorLib.AttackCreepsExecute
behaviorLib.AttackCreepsBehavior["Name"] = "AttackCreeps"
tinsert(behaviorLib.tBehaviors, behaviorLib.AttackCreepsBehavior)

----------------------------------
--          HarassHero          --
----------------------------------
--
-- Utility: 0 to 100 
-- Based on relative lethalities, calculated per team
--
-- Execute: 
-- Moves to and attacks target when in nRange
--
-- Tutorial: 
-- Hellbourne bots harass much less frequently
--

-------- Global Constants & Variables --------
behaviorLib.heroTarget = nil
behaviorLib.lastHarassUtil = 0
behaviorLib.diveThreshold = 75
behaviorLib.harassUtilityWeight = 1.0
behaviorLib.rangedHarassBuffer = 300
behaviorLib.tThreatMultipliers = {}
behaviorLib.nThreatAdjustment = 0.075

-------- Helper Functions --------
function behaviorLib.GetThreat(unit)
	local nThreat = core.teamBotBrain:GetThreat(unit)
	return nThreat * (behaviorLib.tThreatMultipliers[unit:GetUniqueID()] or 1)
end

function behaviorLib.GetDefense(unit)
	return core.teamBotBrain:GetDefense(unit)
end

function behaviorLib.CustomHarassUtility(unit)
-- This function should be overwritten in each bots main file
	return 0
end

function behaviorLib.LethalityDifferenceUtility(nLethalityDifference)
	return Clamp(nLethalityDifference * 0.035, -100, 100)
end

function behaviorLib.ProxToEnemyTowerUtility(unit, unitClosestEnemyTower)
	local bDebugEchos = false
	local nUtility = 0

	if unitClosestEnemyTower then
		local nDist = Vector3.Distance2D(unitClosestEnemyTower:GetPosition(), unit:GetPosition())
		local nTowerRange = core.GetAbsoluteAttackRangeToUnit(unitClosestEnemyTower, unit)
		local nBuffers = unit:GetBoundsRadius() + unitClosestEnemyTower:GetBoundsRadius()

		nUtility = -1 * core.ExpDecay((nDist - nBuffers), 100, nTowerRange, 2)
		
		nUtility = nUtility * 0.32
		
		if bDebugEchos then 
			BotEcho(format("util: %d  nDistance: %d  nTowerRange: %d", nUtility, (nDist - nBuffers), nTowerRange))
		end
	end
	
	nUtility = Clamp(nUtility, -100, 0)

	return nUtility
end

function behaviorLib.AttackAdvantageUtility(unitSelf, unitTarget)
	local nUtility = 0

	local bAttackingMe = false
	local unitAttackTarget = unitTarget:GetAttackTarget()
	if unitAttackTarget and unitAttackTarget:GetUniqueID() == unitSelf:GetUniqueID() then
		bAttackingMe = true
	end
	
	if not unitTarget:IsAttackReady() and not bAttackingMe then
		nUtility = 5
	end

	return nUtility
end

function behaviorLib.InRangeUtility(unitSelf, unitTarget)
	local nUtility = 0

	if unitSelf:IsAttackReady() then
		local nDistanceSq = Vector3.Distance2DSq(unitSelf:GetPosition(), unitTarget:GetPosition())
		local nRange = core.GetAbsoluteAttackRangeToUnit(unitSelf, unitTarget)
		
		if core.unitSelf:GetAttackType() == "melee" then
			-- Override melee to give the bonus if they are "close enough"
			nRange = 250
		end
		
		if nDistanceSq <= nRange * nRange then
			nUtility = 15
		end
	end

	return nUtility
end


function behaviorLib.ProcessKill(unit)
	local bDebugEchos = false
	
	local nID = unit:GetUniqueID()
	local tThreatMultipliers = behaviorLib.tThreatMultipliers
	
	if tThreatMultipliers[nID] == nil then
		BotEcho("I got a kill on some unknown hero!? "..unit:GetTypeName().." on team "..unit:GetTeam())
		return
	end
	
	--[Difficulty: Easy] Bots don't become more bold
	if core.nDifficulty == core.nEASY_DIFFICULTY and tThreatMultipliers[nID] <= 1 then
		return
	end
	
	if bDebugEchos then 
		BotEcho(format("I got a kill! Changing %s's threat multiplier from %g to %g", unit:GetTypeName(), tThreatMultipliers[nID], tThreatMultipliers[nID] - behaviorLib.nThreatAdjustment)) 
	end
	
	tThreatMultipliers[nID] = tThreatMultipliers[nID] - behaviorLib.nThreatAdjustment
	
	return
end

function behaviorLib.ProcessDeath(unit)
	local bDebugEchos = false
	
	if unit then
		local nID = unit:GetUniqueID()	
		local tThreatMultipliers = behaviorLib.tThreatMultipliers
		
		if tThreatMultipliers[nID] == nil then
			--TODO: figure out how to get the hero who got credit for my death (if any)
			return
		end
		
		if bDebugEchos then 
			BotEcho(format("I died! Changing %s's threat multiplier from %g to %g", unit:GetTypeName(), tThreatMultipliers[nID], tThreatMultipliers[nID] + behaviorLib.nThreatAdjustment)) 
		end
		
		tThreatMultipliers[nID] = tThreatMultipliers[nID] + behaviorLib.nThreatAdjustment
	end
end

-------- Behavior Functions --------
function behaviorLib.HarassHeroUtility(botBrain)
	local bDebugEchos = false
	local nUtility = 0
	local unitSelf = core.unitSelf
	local vecMyPosition = unitSelf:GetPosition()
	local unitTarget = nil
	
	local function fnIsHero(unit)
		return unit:IsHero()
	end
	
	local tLocalEnemies = core.CopyTable(core.localUnits["EnemyHeroes"])
	core.teamBotBrain:AddMemoryUnitsToTable(tLocalEnemies, core.enemyTeam, vecMyPosition, nil, fnIsHero)

	if not core.IsTableEmpty(tLocalEnemies) then
		local unitClosestEnemyTower = core.GetClosestEnemyTower(vecMyPosition)
		local nTotalEnemyThreat = 0
		local nLowestEnemyDefense = 999999
		local unitWeakestEnemy = nil
		local nHighestEnemyThreat = 0

		--local references to loop functions, to increase performance
		local funcGetThreat = behaviorLib.GetThreat
		local funcGetDefense = behaviorLib.GetDefense
		local nHarassUtilityWeight = behaviorLib.harassUtilityWeight
		local funcProxToEnemyTowerUtility =  behaviorLib.ProxToEnemyTowerUtility
		local funcLethalityDifferenceUtility = behaviorLib.LethalityDifferenceUtility
		local funcCustomHarassUtility = behaviorLib.CustomHarassUtility
		local funcAttackAdvantageUtility = behaviorLib.AttackAdvantageUtility
		local funcInRangeUtility = behaviorLib.InRangeUtility		
		
		
		if bDebugEchos then 
			BotEcho("HarassHeroNew") 
		end
		
		--Enemies
		for nID, unitEnemy in pairs(tLocalEnemies) do
			local nThreat = funcGetThreat(unitEnemy)
			nTotalEnemyThreat = nTotalEnemyThreat + nThreat
			if nThreat > nHighestEnemyThreat then
				nHighestEnemyThreat = nThreat
			end
			
			local nDefense = funcGetDefense(unitEnemy)
			if nDefense < nLowestEnemyDefense then
				nLowestEnemyDefense = nDefense
				unitWeakestEnemy = unitEnemy
			end
			
			if bDebugEchos then 
				BotEcho(nID..": "..unitEnemy:GetTypeName().."  threat: "..Round(nThreat).."  defense: "..Round(nDefense)) 
			end
		end
		
		--Aquire a target
		--TODO: based on mix of priority target (high threat) v weak (low defense)
		unitTarget = unitWeakestEnemy
		
		local nMyThreat = 0
		local nTotalAllyThreat = 0
		local tLocalAllies = core.CopyTable(core.localUnits["AllyHeroes"])
		tLocalAllies[unitSelf:GetUniqueID()] = unitSelf --include myself in the threat calculations
		local nAllyThreatRange = 1200
		local nHalfAllyThreatRange = nAllyThreatRange * 0.5
		
		--Allies
		local vecTowardsTarget = (unitTarget:GetPosition() - vecMyPosition)
		for nID, unitAlly in pairs(tLocalAllies) do
			local vecTowardsAlly, nDistance = Vector3.Normalize(unitAlly:GetPosition() - vecMyPosition)
			
			if nDistance <= nAllyThreatRange then
				local nThreat = funcGetThreat(unitAlly)
				local nMyID = unitSelf:GetUniqueID()
				
				if unitAlly:GetUniqueID() ~= nMyID then
					local nThreatMul = 1
					if nDistance > nHalfAllyThreatRange and Vector3.Dot(vecTowardsAlly, vecTowardsTarget) < 0 then
						-- Lower ally threat if they are too far away
						nThreatMul = 1 - (nDistance - nHalfAllyThreatRange) / nHalfAllyThreatRange						
					end
					
					if bDebugEchos then 
						BotEcho(format("%s  dot: %g  nThreatMul: %g  nDistance: %d  nRange: %d",
						unitAlly:GetTypeName(), Vector3.Dot(vecTowardsAlly, vecTowardsTarget), nThreatMul, nDistance, nAllyThreatRange))
					end
					
					nThreat = nThreat * nThreatMul				
				else
					nMyThreat = nThreat
				end
				
				nTotalAllyThreat = nTotalAllyThreat + nThreat
				
				if bDebugEchos then
					BotEcho(nID..": "..unitAlly:GetTypeName().."  threat: "..Round(nThreat))
				end
			end			
		end
		
		local nMyDefense = 0
		nMyDefense = funcGetDefense(unitSelf)
		
		if bDebugEchos then 
			BotEcho("myDefense: "..Round(nMyDefense)) 
		end
		
		local nAllyLethality = 0
		local nEnemyLethality = 0
		local nLethalityDifference = 0
		if unitTarget then
			nAllyLethality = nTotalAllyThreat - nLowestEnemyDefense
			nEnemyLethality = nTotalEnemyThreat - nMyDefense
			nLethalityDifference = nAllyLethality - nEnemyLethality
		end
		
		if bDebugEchos then
			BotEcho("AllyLethality: "..nAllyLethality.."  EnemyLethality "..nEnemyLethality) 
		end

		local nLethalityUtility = funcLethalityDifferenceUtility(nLethalityDifference)
		
		--Apply aggression conditional bonuses
		local nMomentumUtility = core.nHarassBonus
		local nCustomUtility = funcCustomHarassUtility(unitTarget)
		local nProxToEnemyTowerUtility = funcProxToEnemyTowerUtility(unitTarget, unitClosestEnemyTower)
		local nMyProxToEnemyTowerUtility = funcProxToEnemyTowerUtility(unitSelf, unitClosestEnemyTower)
		local nAttackAdvantageUtility = funcAttackAdvantageUtility(unitSelf, unitTarget)
		local nInRangeUtility = funcInRangeUtility(unitSelf, unitTarget)
		
		nUtility = nLethalityUtility + nProxToEnemyTowerUtility + nMyProxToEnemyTowerUtility + nInRangeUtility + nCustomUtility + nMomentumUtility
		nUtility = nUtility * nHarassUtilityWeight
		
		--[Difficulty: Easy] Randomly, bots are more aggressive for an interval
		if core.bEasyRandomAggression then
			nUtility = nUtility + core.nEasyAggroHarassBonus
		end
		
		if bDebugEchos then 
			BotEcho(format("util: %d  lethality: %d  custom: %d  momentum: %d  prox: %d  attkAdv: %d  inRange: %d  %%harass: %g",
				nUtility, nLethalityUtility, nCustomUtility, nMomentumUtility, nProxToEnemyTowerUtility, 
				nAttackAdvantageUtility, nInRangeUtility, nHarassUtilityWeight)
			)
		end
	end
	
	behaviorLib.lastHarassUtil = nUtility
	behaviorLib.heroTarget = unitTarget
	
	if bDebugEchos or botBrain.bDebugUtility and nUtility ~= 0 then
		BotEcho("RandomAggression: "..tostring(core.bEasyRandomAggression))
		BotEcho(format("  HarassHeroNewUtility: %g", nUtility))
	end

	return nUtility
end

function behaviorLib.HarassHeroExecute(botBrain)
	local bDebugEchos = false
	local bActionTaken = false
	local unitSelf = core.unitSelf
	local unitTarget = behaviorLib.heroTarget
	local vecTargetPos = (unitTarget and unitTarget:GetPosition()) or nil

	if bDebugEchos then 
		BotEcho("Harassing "..((unitTarget~=nil and unitTarget:GetTypeName()) or "nil")) 
	end
	
	if unitTarget and vecTargetPos then
		local nDistSq = Vector3.Distance2DSq(unitSelf:GetPosition(), vecTargetPos)
		local nAttackRangeSq = core.GetAbsoluteAttackRangeToUnit(unitSelf, unitTarget, true)
		-- Only attack when in nRange, so not to aggro towers/creeps until necessary, and move forward when attack is on cd
		if nDistSq < nAttackRangeSq and unitSelf:IsAttackReady() and core.CanSeeUnit(botBrain, unitTarget) then
			local bInTowerRange = core.NumberElements(core.GetTowersThreateningUnit(unitSelf)) > 0
			local bShouldDive = behaviorLib.lastHarassUtil >= behaviorLib.diveThreshold
			
			if bDebugEchos then 
				BotEcho(format("inTowerRange: %s  bShouldDive: %s", tostring(bInTowerRange), tostring(bShouldDive))) 
			end
			
			if not bInTowerRange or bShouldDive then
				if bDebugEchos then 
					BotEcho("ATTAKIN NOOBS! divin: "..tostring(bShouldDive)) 
				end

				bActionTaken = core.OrderAttackClamp(botBrain, unitSelf, unitTarget)
			end
		else
			if bDebugEchos then 
				BotEcho("MOVIN OUT") 
			end
			
			local vecDesiredPos = vecTargetPos
			local bUseTargetPosition = true

			--leave some space if we are ranged
			if unitSelf:GetAttackRange() > 200 then
				vecDesiredPos = vecTargetPos + Vector3.Normalize(unitSelf:GetPosition() - vecTargetPos) * behaviorLib.rangedHarassBuffer
				bUseTargetPosition = false
			end

			local itemGhostMarchers = core.itemGhostMarchers
			if itemGhostMarchers and itemGhostMarchers:CanActivate() then
				bActionTaken = core.OrderItemClamp(botBrain, unitSelf, itemGhostMarchers)
			else
				local bChanged = false
				local bWellDiving = false
				vecDesiredPos, bChanged, bWellDiving = core.AdjustMovementForTowerLogic(vecDesiredPos)
				
				if bDebugEchos then 
					BotEcho("Move - bChanged: "..tostring(bChanged).."  bWellDiving: "..tostring(bWellDiving)) 
				end
				
				if not bWellDiving then
					if behaviorLib.lastHarassUtil < behaviorLib.diveThreshold then
						if bDebugEchos then 
							BotEcho("DON'T DIVE!") 
						end
										
						if bUseTargetPosition and not bChanged then
							bActionTaken = core.OrderMoveToUnitClamp(botBrain, unitSelf, unitTarget, false)
						else
							bActionTaken = core.OrderMoveToPosAndHoldClamp(botBrain, unitSelf, vecDesiredPos, false)
						end
					else
						if bDebugEchos then 
							BotEcho("DIVIN Tower! util: "..behaviorLib.lastHarassUtil.." > "..behaviorLib.diveThreshold) 
						end
						
						bActionTaken = core.OrderMoveToPosClamp(botBrain, unitSelf, vecDesiredPos, false)
					end
				end
			end
		end
	end
	
	return bActionTaken
end

behaviorLib.HarassHeroBehavior = {}
behaviorLib.HarassHeroBehavior["Utility"] = behaviorLib.HarassHeroUtility
behaviorLib.HarassHeroBehavior["Execute"] = behaviorLib.HarassHeroExecute
behaviorLib.HarassHeroBehavior["Name"] = "HarassHero"
tinsert(behaviorLib.tBehaviors, behaviorLib.HarassHeroBehavior)

-----------------------------------
--          HitBuilding          --
-----------------------------------
--
-- Utility: {40, 36, 25, 23}
-- If a {Throne, Rax, Tower, Other Building} 
-- is in range, not invulnerable, and will not draw aggro
--
-- Execute: 
-- Attacks the building
--

-------- Global Constants & Variables --------
behaviorLib.hitBuildingTarget = nil

-------- Behavior Functions --------
function behaviorLib.HitBuildingUtility(botBrain)
	local bDebugLines = false
	local bDebugEchos = false

	local nThroneUtil = 40
	local nRaxUtil = 36
	local nTowerUtil = 25
	local nOtherBuildingUtil = 23

	local nUtility = 0
	local unitSelf = core.unitSelf
	
	local nRange = core.GetAbsoluteAttackRange(unitSelf)
	-- Override melee so they don't stand *just* out of range
	if core.unitSelf:GetAttackType() == "melee" then
		nRange = 250
	end

	local tBuildings = core.localUnits["EnemyBuildings"]
	if unitSelf:IsAttackReady() then
		local unitTarget = nil

		local tSortedBuildings = {}
		core.SortBuildings(tBuildings, tSortedBuildings)

		-- Throne
		local unitBase = tSortedBuildings.enemyMainBaseStructure
		if unitBase and not unitBase:IsInvulnerable() then
			local nExtraRange = core.GetExtraRange(unitBase)
			if core.IsUnitInRange(unitSelf, unitBase, nRange + nExtraRange) and core.CanSeeUnit(botBrain, unitBase) then
				unitTarget = unitBase
				nUtility = nThroneUtil
			end
		end
		
		-- Rax
		if unitTarget == nil and core.NumberElements(tSortedBuildings.enemyRax) > 0 then
			local unitTargetRax = nil
			local tRax = tSortedBuildings.enemyRax
			for _, unitRax in pairs(tRax) do
				local nExtraRange = core.GetExtraRange(unitRax)
				if not unitRax:IsInvulnerable() and core.IsUnitInRange(unitSelf, unitRax, nRange + nExtraRange) and core.CanSeeUnit(botBrain, unitRax) then
					-- Prefer melee rax
					if unitTargetRax == nil or not unitTargetRax:IsUnitType("MeleeRax") then
						unitTargetRax = unitRax
					end
				end
			end
			
			if unitTargetRax then
				unitTarget = unitTargetRax
				nUtility = nRaxUtil
			end
		end
		
		-- Tower
		if unitTarget == nil and core.NumberElements(tSortedBuildings.enemyTowers) > 0 and core.NumberElements(core.localUnits["EnemyUnits"]) <= 0 then
			local tTowers = tSortedBuildings.enemyTowers
			for _, unitTower in pairs(tTowers) do
				local nExtraRange = core.GetExtraRange(unitTower)
				if not unitTower:IsInvulnerable() and core.IsUnitInRange(unitSelf, unitTower, nRange + nExtraRange) and core.CanSeeUnit(botBrain, unitTower) and core.IsTowerSafe(unitTower, unitSelf) then
					unitTarget = unitTower
					nUtility = nTowerUtil
					break
				end
			end
		end
				
		-- Other buildings
		if unitTarget == nil and core.NumberElements(tSortedBuildings.enemyOtherBuildings) > 0 then
			local tOtherBuildings = tSortedBuildings.enemyOtherBuildings
			for _, unitBuilding in pairs(tOtherBuildings) do
				local nExtraRange = core.GetExtraRange(unitBuilding)
				if not unitBuilding:IsInvulnerable() and core.IsUnitInRange(unitSelf, unitBuilding, nRange + nExtraRange) and core.CanSeeUnit(botBrain, unitBuilding) then
					unitTarget = unitBuilding
					nUtility = nOtherBuildingUtil
					break
				end
			end
		end
		
		behaviorLib.hitBuildingTarget = unitTarget
	end

	if bDebugLines then
		local nLineLen = 150
		local vecMyPos = unitSelf:GetPosition()
		local nMyRange = unitSelf:GetAttackRange()
		local nMyExtraRange = core.GetExtraRange(unitSelf)

		for _, unitBuilding in pairs(tBuildings) do
			if unitBuilding:GetTeam() ~= core.myTeam then
				local vecBuildingPos = unitBuilding:GetPosition()
				local nBuildingExtraRange = core.GetExtraRange(unitBuilding)
				local vTowards = Vector3.Normalize(vecBuildingPos - vecMyPos)
				local vecOrtho = Vector3.Create(-vTowards.y, vTowards.x) * 0.5 * nLineLen --quick 90 rotate z
				core.DrawDebugLine(vecMyPos, vecMyPos + vTowards * (nMyRange + nMyExtraRange), 'orange')
				core.DrawDebugLine((vecMyPos + vTowards * nMyRange) - (vecOrtho / 2), (vecMyPos + vTowards * nMyRange) + (vecOrtho / 2), 'orange')
				core.DrawDebugLine((vecMyPos + vTowards * (nMyRange + nMyExtraRange)) - vecOrtho, (vecMyPos + vTowards * (nMyRange + nMyExtraRange)) + vecOrtho, 'orange')
				core.DrawDebugLine((vecBuildingPos - vTowards * nBuildingExtraRange) - vecOrtho, (vecBuildingPos - vTowards * nBuildingExtraRange) + vecOrtho, 'yellow')
			end
		end
	end
	
	if bDebugEchos then
		core.printGetTypeNameTable(tBuildings)
	end

	if botBrain.bDebugUtility == true and nUtility ~= 0 then
		BotEcho(format("  HitBuildingUtility: %g", nUtility))
	end

	return nUtility
end

function behaviorLib.HitBuildingExecute(botBrain)
	local bActionTaken = false

	if not bActionTaken then
		local unitTarget = behaviorLib.hitBuildingTarget
		if unitTarget then
			local unitSelf = core.unitSelf
			bActionTaken = core.OrderAttackClamp(botBrain, unitSelf, unitTarget)
		end
	end
	
	return bActionTaken
end

behaviorLib.HitBuildingBehavior = {}
behaviorLib.HitBuildingBehavior["Utility"] = behaviorLib.HitBuildingUtility
behaviorLib.HitBuildingBehavior["Execute"] = behaviorLib.HitBuildingExecute
behaviorLib.HitBuildingBehavior["Name"] = "HitBuilding"
tinsert(behaviorLib.tBehaviors, behaviorLib.HitBuildingBehavior)

----------------------------
--          Push          --
----------------------------
--
-- Utility: 0 to 22
-- Based on whether or not the enemy heroes are dead,
-- and how strong your pushing power is
--
-- Execute: 
-- Moves to and attacks creeps when in range,
-- retreat when there are no creeps
--

-------- Global Constants & Variables --------
behaviorLib.enemiesDeadUtilMul = 0.5
behaviorLib.pushingStrUtilMul = 0.3
behaviorLib.nTeamPushUtilityMul = 0.3
behaviorLib.nDPSPushWeight = 0.8
behaviorLib.pushingCap = 22

-------- Helper Functions --------
function behaviorLib.EnemiesDeadPushUtility(nEnemyTeam)
	local bDebugEchos = false
	local tEnemyHeroes = HoN.GetHeroes(nEnemyTeam)
	local nTotalEnemyHeroes = 0
	local nDeadEnemyHeroes = 0
	for _, unitHero in pairs(tEnemyHeroes) do
		nTotalEnemyHeroes = nTotalEnemyHeroes + 1
		if not unitHero:IsAlive() then
			nDeadEnemyHeroes = nDeadEnemyHeroes + 1
		end
	end

	local nUtility = 0

	if nDeadEnemyHeroes > 0 then
		nUtility = 100 * nDeadEnemyHeroes / (nTotalEnemyHeroes + 1)
	end

	if bDebugEchos then
		BotEcho("Utility: "..nUtility.."enemiesDead: "..nDeadEnemyHeroes.."  totalEnemies: "..nTotalEnemyHeroes)
	end

	return nUtility
end

function behaviorLib.DPSPushingUtility(unitMyHero)
	local bDebugEchos = false
	
	local nMyDamage = core.GetFinalAttackDamageAverage(unitMyHero)
	local nMyAttackDuration = unitMyHero:GetAdjustedAttackDuration()
	local nMyDPS = nMyDamage * 1000 / (nMyAttackDuration) --ms to s
	
	local vecTop = Vector3.Create(300, 100)
	local vecBot = Vector3.Create(100, 0)
	local nSlope = ((vecTop.y - vecBot.y) / (vecTop.x - vecBot.x))
	local nIntercept = vecBot.y - nSlope * vecBot.x 
	
	local nUtility = nSlope * nMyDPS + nIntercept
	nUtility = Clamp(nUtility, 0, 100)
	
	if bDebugEchos then
		BotEcho(format("MyDPS: %g  Utility: %g  myMin: %g  myMax: %g  myAttackAverageL %g", 
			nMyDPS, nUtility, unitMyHero:GetFinalAttackDamageMin(), unitMyHero:GetFinalAttackDamageMax(), nMyDamage))
	end
	
	return nUtility
end

function behaviorLib.PushingStrengthUtility(myHero)
	local nUtility = 0
	
	nUtility = behaviorLib.DPSPushingUtility(myHero) * behaviorLib.nDPSPushWeight
	nUtility = Clamp(nUtility, 0, 100)
	
	return nUtility
end

function behaviorLib.TeamPushUtility()
	return core.teamBotBrain:PushUtility()
end

-------- Behavior Functions --------
function behaviorLib.PushUtility(botBrain)
	--TODO: factor in:
		--how strong are we here? (allies close, pushing ability, hp/mana)
		--what defenses can they mount (potential enemies close, threat, anti-push, time until response)
		--how effective/how much can we hope to acomplish (time cost, weakness of target)

		--For now: push when they have dudes down and as I grow stronger

	local bDebugEchos = false
	local nUtility = 0
	local nEnemiesDeadUtil = behaviorLib.EnemiesDeadPushUtility(core.enemyTeam) * behaviorLib.enemiesDeadUtilMul
	local nPushingStrengthUtil = behaviorLib.PushingStrengthUtility(core.unitSelf) * behaviorLib.pushingStrUtilMul
	local nTeamPushUtility = behaviorLib.TeamPushUtility() * behaviorLib.nTeamPushUtilityMul

	nUtility = nEnemiesDeadUtil + nPushingStrengthUtil + nTeamPushUtility
	nUtility = Clamp(nUtility, 0, behaviorLib.pushingCap)

	if bDebugEchos then
		BotEcho(format("PushUtil: %g  enemyDeadUtil: %g  pushingStrUtil: %g", nUtility, nEnemiesDeadUtil, nPushingStrengthUtil))
	end
	
	if botBrain.bDebugUtility == true and nUtility ~= 0 then
		BotEcho(format("  PushUtility: %g", nUtility))
	end

	return nUtility
end

function behaviorLib.PushExecute(botBrain)
	local bDebugLines = false
	local bActionTaken = false
	local unitSelf = core.unitSelf

	--Attack creeps if the bot is in range
	if not bActionTaken then
		local unitTarget = core.unitEnemyCreepTarget
		if unitTarget then
			local nRange = core.GetAbsoluteAttackRangeToUnit(unitSelf, unitTarget)
			-- Override melee so they don't stand *just* out of range
			if unitSelf:GetAttackType() == "melee" then
				nRange = 250
			end
			
			if unitSelf:IsAttackReady() and core.IsUnitInRange(unitSelf, unitTarget, nRange) then
				bActionTaken = core.OrderAttackClamp(botBrain, unitSelf, unitTarget)
			end
			
			if bDebugLines then 
				core.DrawXPosition(unitTarget:GetPosition(), 'red', 125) 
			end
		end
	end
	
	-- Move to the target 
	if not bActionTaken then
		local vecDesiredPos = behaviorLib.PositionSelfLogic(botBrain)
		if vecDesiredPos then
			bActionTaken = behaviorLib.MoveExecute(botBrain, vecDesiredPos)
			
			if bDebugLines then 
				core.DrawXPosition(vecDesiredPos, 'blue') 
			end
		end
	end
	
	return bActionTaken
end

behaviorLib.PushBehavior = {}
behaviorLib.PushBehavior["Utility"] = behaviorLib.PushUtility
behaviorLib.PushBehavior["Execute"] = behaviorLib.PushExecute
behaviorLib.PushBehavior["Name"] = "Push"
tinsert(behaviorLib.tBehaviors, behaviorLib.PushBehavior)

---------------------------------
--          TeamGroup          --
---------------------------------
--
-- Utility: 0 or 35
-- If the teamBotBrain wants us to group up returns 35, otherwise 0
--
-- Execute: 
-- Move to the rally point
--

-------- Global Constants & Variables --------
behaviorLib.nTeamGroupUtilityMul = 0.35
behaviorLib.nNextGroupMessage = 0

-------- Behavior Functions --------
function behaviorLib.TeamGroupUtility(botBrain)
	local nUtility = 0

	if core.teamBotBrain then
		nUtility = core.teamBotBrain:GroupUtility()
	end

	nUtility = nUtility * behaviorLib.nTeamGroupUtilityMul

	if botBrain.bDebugUtility == true and nUtility ~= 0 then
		BotEcho(format("  TeamGroupUtility: %g", nUtility))
	end

	return nUtility
end

function behaviorLib.TeamGroupExecute(botBrain)
	local bActionTaken = false
	local unitSelf = core.unitSelf
	local teamBotBrain = core.teamBotBrain
	
	if not bActionTaken then
		local vecRallyPoint = teamBotBrain:GetGroupRallyPoint()
		if vecRallyPoint then
			local nCurrentTime = HoN.GetGameTime()
			-- Send Team Chat message
			if behaviorLib.nNextGroupMessage < nCurrentTime then
				if behaviorLib.nNextGroupMessage == 0 then
					behaviorLib.nNextGroupMessage = nCurrentTime
				end

				local nDelay = random(core.nChatDelayMin, core.nChatDelayMax)
				local tLane = teamBotBrain:GetDesiredLane(unitSelf)
				local sLane = tLane and tLane.sLaneName or "nil"
				core.TeamChatLocalizedMessage("group_up", {lane=sLane}, nDelay)
				behaviorLib.nNextGroupMessage = nCurrentTime + core.MinToMS(1)
			end
			
			-- Execute the Order
			local nDistanceSq = Vector3.Distance2DSq(unitSelf:GetPosition(), vecRallyPoint)
			local nCloseEnough = teamBotBrain.nGroupUpRadius - 100
			if nDistanceSq < nCloseEnough * nCloseEnough then
				bActionTaken = core.OrderAttackPositionClamp(botBrain, unitSelf, vecRallyPoint, false)
			else
				bActionTaken = behaviorLib.MoveExecute(botBrain, vecRallyPoint)
			end
		end
	end
	
	if not bActionTaken then
		BotEcho("nil rally point!")
	end

	return bActionTaken
end

behaviorLib.TeamGroupBehavior = {}
behaviorLib.TeamGroupBehavior["Utility"] = behaviorLib.TeamGroupUtility
behaviorLib.TeamGroupBehavior["Execute"] = behaviorLib.TeamGroupExecute
behaviorLib.TeamGroupBehavior["Name"] = "TeamGroup"
tinsert(behaviorLib.tBehaviors, behaviorLib.TeamGroupBehavior)

----------------------------------
--          TeamDefend          --
----------------------------------
--
-- Utility: 0 or 23
-- If the teamBotBrain wants us to defend a building returns 23, otherwise 0
--
-- Execute: 
-- Move to the designated building
-- Attack creeps around the building
--

-------- Global Constants & Variables --------
behaviorLib.nTeamDefendUtilityVal = 23
behaviorLib.unitDefendTarget = nil

-------- Behavior Functions --------
function behaviorLib.TeamDefendUtility(botBrain)
	local nUtility = 0

	if core.teamBotBrain then
		behaviorLib.unitDefendTarget = core.teamBotBrain:GetDefenseTarget(core.unitSelf)
		
		if behaviorLib.unitDefendTarget then
			nUtility = behaviorLib.nTeamDefendUtilityVal
		end
	end

	if (botBrain.bDebugUtility == true) and nUtility ~= 0 then
		BotEcho(format("  TeamDefendUtility: %g", nUtility))
	end

	return nUtility
end

function behaviorLib.TeamDefendExecute(botBrain)
	local bActionTaken = false
	local unitSelf = core.unitSelf
	local teamBotBrain = core.teamBotBrain
	
	if not bActionTaken then
		local unitDefendTarget = behaviorLib.unitDefendTarget
		if unitDefendTarget then
			local nCurrentTime = HoN.GetGameTime()
			-- Send Team Chat message
			if behaviorLib.nNextGroupMessage < nCurrentTime then
				if behaviorLib.nNextGroupMessage == 0 then
					behaviorLib.nNextGroupMessage = nCurrentTime
				end

				local nDelay = random(core.nChatDelayMin, core.nChatDelayMax)
				local tLane = teamBotBrain:GetDesiredLane(unitSelf)
				local sLane = tLane and tLane.sLaneName or "nil"
				core.TeamChatLocalizedMessage("defend", {lane = sLane}, nDelay)
				behaviorLib.nNextGroupMessage = nCurrentTime + core.MinToMS(1)
			end
			
			-- Execute the Order
			local vecTargetPosition = unitDefendTarget:GetPosition()
			local nDistanceSq = Vector3.Distance2DSq(unitSelf:GetPosition(), vecTargetPosition)
			local nCloseEnough = core.teamBotBrain.nDefenseInRangeRadius
			if nDistanceSq < nCloseEnough * nCloseEnough then
				bActionTaken = core.OrderAttackPositionClamp(botBrain, unitSelf, vecTargetPosition, false)
			else
				bActionTaken = behaviorLib.MoveExecute(botBrain, vecTargetPosition)
			end
		end
	end
	
	if not bActionTaken then
		BotEcho("nil defense target!")
	end

	return bActionTaken
end

behaviorLib.TeamDefendBehavior = {}
behaviorLib.TeamDefendBehavior["Utility"] = behaviorLib.TeamDefendUtility
behaviorLib.TeamDefendBehavior["Execute"] = behaviorLib.TeamDefendExecute
behaviorLib.TeamDefendBehavior["Name"] = "TeamDefend"
tinsert(behaviorLib.tBehaviors, behaviorLib.TeamDefendBehavior)

----------------------------------------
--          DontBreakChannel          --
----------------------------------------
--
-- Utility: 0 or 100
-- Returns 100 if you are channeling, 0 otherwise
--
-- Execute: 
-- Do nothing while channeling
--

-------- Behavior Functions --------
function behaviorLib.DontBreakChannelUtility(botBrain)
	local nUtility = 0

	if core.unitSelf:IsChanneling() then
		nUtility = 100
	end

	if botBrain.bDebugUtility == true and nUtility ~= 0 then
		BotEcho(format("  DontBreakChannelUtility: %g", nUtility))
	end

	return nUtility
end

function behaviorLib.DontBreakChannelExecute(botBrain)
	return true
end

behaviorLib.DontBreakChannelBehavior = {}
behaviorLib.DontBreakChannelBehavior["Utility"] = behaviorLib.DontBreakChannelUtility
behaviorLib.DontBreakChannelBehavior["Execute"] = behaviorLib.DontBreakChannelExecute
behaviorLib.DontBreakChannelBehavior["Name"] = "DontBreakChannel"
tinsert(behaviorLib.tBehaviors, behaviorLib.DontBreakChannelBehavior)

--------------------------------------
--          UseHealthRegen          --
--------------------------------------
--
-- Utility: 0 to 40
-- Based on missing health
--
-- Execute: 
-- Use a Rune of the Blight, Health Pot, or Bottle to heal
-- Will only use Health Pot or Bottle if it is safe
--

-------- Global Constants & Variables --------
behaviorLib.nBlightsUtility = 0
behaviorLib.nHealthPotUtility = 0
behaviorLib.nBatterySupplyHealthUtility = 0
behaviorLib.nBottleHealthUtility = 0

behaviorLib.bUseBatterySupplyForHealth = true
behaviorLib.bUseBottleForHealth = true

behaviorLib.safeTreeAngle = 120

-------- Helper Functions --------
function behaviorLib.GetSafeDrinkDirection()
	-- Returns vector to a safe direciton to retreat to drink if the bot is threatened
	-- Returns nil if safe
	local bDebugLines = true
	local vecSafeDirection = nil
	local vecSelfPos = core.unitSelf:GetPosition()
	local tThreateningUnits = {}
	for _, unitEnemy in pairs(core.localUnits["EnemyUnits"]) do
		local nAbsRange = core.GetAbsoluteAttackRangeToUnit(unitEnemy, unitSelf)
		local nDist = Vector3.Distance2D(vecSelfPos, unitEnemy:GetPosition())
		if nDist < nAbsRange * 1.15 then
			local unitPair = {}
			unitPair[1] = unitEnemy
			unitPair[2] = (nAbsRange * 1.15 - nDist)
			tinsert(tThreateningUnits, unitPair)
		end
	end

	local curTimeMS = HoN.GetGameTime()
	if core.NumberElements(tThreateningUnits) > 0 or eventsLib.recentDotTime > curTimeMS or #eventsLib.incomingProjectiles["all"] > 0 then
		-- Determine best "away from threat" vector
		local vecAway = Vector3.Create()
		for _, unitPair in pairs(tThreateningUnits) do
			local unitAwayVec = Vector3.Normalize(vecSelfPos - unitPair[1]:GetPosition())
			vecAway = vecAway + unitAwayVec * unitPair[2]

			if bDebugLines then
				core.DrawDebugArrow(unitPair[1]:GetPosition(), unitPair[1]:GetPosition() + unitAwayVec * unitPair[2], 'teal')
			end
		end

		if core.NumberElements(tThreateningUnits) > 0 then
			vecAway = Vector3.Normalize(vecAway)
		end

		-- Average vecAway with "retreat" vector
		local vecRetreat = Vector3.Normalize(behaviorLib.PositionSelfBackUp() - vecSelfPos)
		local vecSafeDirection = Vector3.Normalize(vecAway + vecRetreat)

		if bDebugLines then
			local nLineLen = 150
			core.DrawDebugArrow(vecSelfPos, vecSelfPos + vecRetreat * nLineLen, 'blue')
			core.DrawDebugArrow(vecSelfPos, vecSelfPos + vecAway * nLineLen, 'teal')
			core.DrawDebugArrow(vecSelfPos, vecSelfPos + vecSafeDirection * nLineLen, 'white')
			core.DrawXPosition(vecSelfPos + vecSafeDirection * core.moveVecMultiplier, 'blue')
		end
	end

	return vecSafeDirection
end

function behaviorLib.BatterySupplyHealthUtilFn(nHealthMissing, nCharges)
	-- With 1 Charge:
	-- Roughly 20+ when we are missing 28 health
	-- Function which crosses 20 at x=28 and 40 at x=300, convex down
	-- With 15 Charges:
	-- Roughly 20+ when we are missing 168 health
	-- Function which crosses 20 at x=168 and 30 at x=320, convex down
	
	local nHealAmount = 10 * nCharges
	local nHealBuffer = 18
	local nUtilityThreshold = 20
		
	local vecPoint = Vector3.Create(nHealAmount + nHealBuffer, nUtilityThreshold)
	local vecOrigin = Vector3.Create(-250, -30)
	return core.ATanFn(nHealthMissing, vecPoint, vecOrigin, 100)
end

function behaviorLib.RunesOfTheBlightUtilFn(nHealthMissing)
	-- Roughly 20+ when we are missing 138 hp
	-- Function which crosses 20 at x=138 and is 30 at roughly x=600, convex down

	local nHealAmount = 115
	local nHealBuffer = 18
	local nUtilityThreshold = 20
		
	local vecPoint = Vector3.Create(nHealAmount + nHealBuffer, nUtilityThreshold)
	local vecOrigin = Vector3.Create(-1000, -20)
	return core.ATanFn(nHealthMissing, vecPoint, vecOrigin, 100)
end

function behaviorLib.HealthPotUtilFn(nHealthMissing)
	-- Roughly 20+ when we are missing 400 hp
	-- Function which crosses 20 at x=400 and 40 at x=650, convex down
	
	local nHealAmount = 400
	local nUtilityThreshold = 20
	
	local vecPoint = Vector3.Create(nHealAmount, nUtilityThreshold)
	local vecOrigin = Vector3.Create(200, -40)
	return core.ATanFn(nHealthMissing, vecPoint, vecOrigin, 100)
end

function behaviorLib.BottleHealthUtilFn(nHealthMissing)
	-- Roughly 20+ when we are missing 195 hp
	-- Function which crosses 20 at x=195 and 30 at x=230, convex down

	local nHealAmount = 135
	local nHealBuffer = 60
	local nUtilityThreshold = 20

	local vecPoint = Vector3.Create(nHealAmount + nHealBuffer, nUtilityThreshold)
	local vecOrigin = Vector3.Create(100, -30)
	return core.ATanFn(nHealthMissing, vecPoint, vecOrigin, 100)
end

-------- Behavior Functions --------
function behaviorLib.UseHealthRegenUtility(botBrain)
	StartProfile("Init")
	local bDebugEchos = false
	local bDebugLines = false

	local nUtility = 0
	local nBatterySupplyUtility = 0
	local nHealthPotUtility = 0
	local nBlightsUtility = 0
	local nBottleUtility = 0
	
	local unitSelf = core.unitSelf
	local nHealthMissing = unitSelf:GetMaxHealth() - unitSelf:GetHealth()
	local tInventory = unitSelf:GetInventory()
	StopProfile()

	StartProfile("Mana Battery/Power Supply")
	if behaviorLib.bUseBatterySupplyForHealth then
		local tManaBattery = core.InventoryContains(tInventory, "Item_ManaBattery")
		local tPowerSupply = core.InventoryContains(tInventory, "Item_PowerSupply")
		local itemBatterySupply = nil
		if #tManaBattery > 0 then
			itemBatterySupply = tManaBattery[1]
		elseif #tPowerSupply > 0 then
			itemBatterySupply = tPowerSupply[1]
		end
		
		if itemBatterySupply and itemBatterySupply:CanActivate() then
			local nCharges = itemBatterySupply:GetCharges()
			if nCharges > 0 then
				nBatterySupplyUtility = behaviorLib.BatterySupplyHealthUtilFn(nHealthMissing, nCharges)
			end
		end
	end
	StopProfile()
	
	StartProfile("Health pot")
	local tHealthPots = core.InventoryContains(tInventory, "Item_HealthPotion")
	if #tHealthPots > 0 and not unitSelf:HasState("State_HealthPotion") then
		nHealthPotUtility = behaviorLib.HealthPotUtilFn(nHealthMissing)
	end
	StopProfile()

	StartProfile("Runes")
	local tBlights = core.InventoryContains(tInventory, "Item_RunesOfTheBlight")
	if #tBlights > 0 and not unitSelf:HasState("State_RunesOfTheBlight") then
		nBlightsUtility = behaviorLib.RunesOfTheBlightUtilFn(nHealthMissing)
	end
	StopProfile()

	StartProfile("Bottle")
	if behaviorLib.bUseBottleForHealth then
		local tItemBottle = core.InventoryContains(tInventory, "Item_Bottle")
		if #tItemBottle > 0 and not unitSelf:HasState("State_Bottle") and tItemBottle[1]:GetActiveModifierKey() ~= "bottle_empty" then
			nBottleUtility = behaviorLib.BottleHealthUtilFn(nHealthMissing)
		end
	end
	StopProfile()

	StartProfile("End")
	nUtility = max(nBatterySupplyUtility, nHealthPotUtility, nBlightsUtility, nBottleUtility)
	nUtility = Clamp(nUtility, 0, 100)

	behaviorLib.nBatterySupplyHealthUtility = nBatterySupplyUtility
	behaviorLib.nHealthPotUtility = nHealthPotUtility
	behaviorLib.nBlightsUtility = nBlightsUtility
	behaviorLib.nBottleHealthUtility = nBottleUtility

	if bDebugEchos then 
		BotEcho(format("UseHealthRegen util: %g  nHealthMissing: %d  tBlights(%d): %g  pots(%d): %g", 
			nUtility, nHealthMissing, #tBlights, nBlightsUtility, #tHealthPots, nHealthPotUtility)) 
	end
	
	if bDebugLines then
		local vecLaneForward = object.vecLaneForward
		if vecLaneForward then
			local vecPos = unitSelf:GetPosition()
			local nHalfSafeTreeAngle = behaviorLib.safeTreeAngle / 2
			local vec1 = core.RotateVec2D(-vecLaneForward, nHalfSafeTreeAngle)
			local vec2 = core.RotateVec2D(-vecLaneForward, -nHalfSafeTreeAngle)
			core.DrawDebugLine(vecPos, vecPos + vec1 * 2000, 'white')
			core.DrawDebugLine(vecPos, vecPos + vec2 * 2000, 'white')
			core.DrawDebugArrow(vecPos, vecPos + -vecLaneForward * 150, 'white')
		end
	end

	if botBrain.bDebugUtility == true and nUtility ~= 0 then
		BotEcho(format("  UseHealthRegenUtility: %g", nUtility))
	end
	StopProfile()

	return nUtility
end

function behaviorLib.UseHealthRegenExecute(botBrain)
	local bDebugLines = false
	local bActionTaken = false
	local unitSelf = core.unitSelf
	local vecSelfPos = unitSelf:GetPosition()
	local tInventory = unitSelf:GetInventory()
	local nMaxUtility = max(behaviorLib.nBatterySupplyHealthUtility, behaviorLib.nBlightsUtility, behaviorLib.nHealthPotUtility, behaviorLib.nBottleHealthUtility)
	
	-- Use Runes to heal
	if not bActionTaken and behaviorLib.nBlightsUtility == nMaxUtility then
		local tBlights = core.InventoryContains(tInventory, "Item_RunesOfTheBlight")
		if #tBlights > 0 and not unitSelf:HasState("State_RunesOfTheBlight") then
			-- Get closest tree
			local unitClosestTree = nil
			local nClosestTreeDistSq = 9999 * 9999
			local vecLaneForward = object.vecLaneForward
			local vecLaneForwardNeg = -vecLaneForward
			local funcRadToDeg = core.RadToDeg
			local funcAngleBetween = core.AngleBetween
			local nHalfSafeTreeAngle = behaviorLib.safeTreeAngle / 2

			core.UpdateLocalTrees()
			local tTrees = core.localTrees
			for _, unitTree in pairs(tTrees) do
				vecTreePosition = unitTree:GetPosition()
				-- "Safe" trees are backwards
				if not vecLaneForward or abs(funcRadToDeg(funcAngleBetween(vecTreePosition - vecSelfPos, vecLaneForwardNeg)) ) < nHalfSafeTreeAngle then
					local nDistSq = Vector3.Distance2DSq(vecTreePosition, vecSelfPos)
					if nDistSq < nClosestTreeDistSq then
						unitClosestTree = unitTree
						nClosestTreeDistSq = nDistSq
						if bDebugLines then
							core.DrawXPosition(vecTreePosition, 'yellow')
						end
					end
				end
			end

			if unitClosestTree then
				bActionTaken = core.OrderItemEntityClamp(botBrain, unitSelf, tBlights[1], unitClosestTree)
			end
		end
	end
	
	-- Use Health Potion to heal
	if not bActionTaken and behaviorLib.nHealthPotUtility == nMaxUtility then
		local tHealthPots = core.InventoryContains(tInventory, "Item_HealthPotion")
		if #tHealthPots > 0 and not unitSelf:HasState("State_HealthPotion") then
			local vecRetreatDirection = behaviorLib.GetSafeDrinkDirection()
			-- Check if it is safe to drink
			if vecRetreatDirection then
				bActionTaken = core.OrderMoveToPosClamp(botBrain, unitSelf, vecSelfPos + vecRetreatDirection * core.moveVecMultiplier, false)
			else
				bActionTaken = core.OrderItemEntityClamp(botBrain, unitSelf, tHealthPots[1], unitSelf)
			end
		end
	end
	
	-- Use Bottle to heal
	if not bActionTaken and behaviorLib.nBottleHealthUtility == nMaxUtility then
		local tItemBottle = core.InventoryContains(tInventory, "Item_Bottle")
		if #tItemBottle > 0 and not unitSelf:HasState("State_Bottle") and tItemBottle[1]:GetActiveModifierKey() ~= "bottle_empty" then
			local vecRetreatDirection = behaviorLib.GetSafeDrinkDirection()
			-- Check if it is safe to drink
			if vecRetreatDirection then
				bActionTaken = core.OrderMoveToPosClamp(botBrain, unitSelf, vecSelfPos + vecRetreatDirection * core.moveVecMultiplier, false)
			else
				bActionTaken = core.OrderItemClamp(botBrain, unitSelf, tItemBottle[1])
			end
		end
	end
	
	-- Use Mana Battery/Power Supply to heal
	if not bActionTaken and behaviorLib.nBatterySupplyHealthUtility == nMaxUtility then
		local tManaBattery = core.InventoryContains(tInventory, "Item_ManaBattery")
		local tPowerSupply = core.InventoryContains(tInventory, "Item_PowerSupply")
		local itemBatterySupply = nil
		if #tManaBattery > 0 then
			itemBatterySupply = tManaBattery[1]
		elseif #tPowerSupply > 0 then
			itemBatterySupply = tPowerSupply[1]
		end
	
		if itemBatterySupply and itemBatterySupply:CanActivate() and itemBatterySupply:GetCharges() > 0 then
			bActionTaken = core.OrderItemClamp(botBrain, unitSelf, itemBatterySupply)
		end
	end
	
	return bActionTaken
end

behaviorLib.UseHealthRegenBehavior = {}
behaviorLib.UseHealthRegenBehavior["Utility"] = behaviorLib.UseHealthRegenUtility
behaviorLib.UseHealthRegenBehavior["Execute"] = behaviorLib.UseHealthRegenExecute
behaviorLib.UseHealthRegenBehavior["Name"] = "UseHealthRegen"
tinsert(behaviorLib.tBehaviors, behaviorLib.UseHealthRegenBehavior)

------------------------------------
--          UseManaRegen          --
------------------------------------
--
-- Utility: 0 to 40
-- Based on missing mana
--
-- Execute:
-- Use Mana Pot or Bottle to restore mana
-- Will only use them if it is safe
--

-------- Global Constants & Variables --------
behaviorLib.nManaPotUtility = 0
behaviorLib.nBottleManaUtility = 0
behaviorLib.nBatterySupplyManaUtility = 0

behaviorLib.bUseBottleForMana = false
behaviorLib.bUseBatterySupplyForMana = true

-------- Helper Functions --------
function behaviorLib.BatterySupplyManaUtilFn(nManaMissing, nCharges)
	-- With 1 Charge:
	-- Roughly 20+ when we are missing 40 mana
	-- Function which crosses 20 at x=40 and 40 at x=260, convex down
	-- With 15 Charges:
	-- Roughly 20+ when we are missing 280 mana
	-- Function which crosses 20 at x=280 and 30 at x=470, convex down

	local nManaRegenAmount = 15 * nCharges
	local nManaBuffer = 25
	local nUtilityThreshold = 20
	
	local vecPoint = Vector3.Create(nManaRegenAmount + nManaBuffer, nUtilityThreshold)
	local vecOrigin = Vector3.Create(-60, -50)
	return core.ATanFn(nManaMissing, vecPoint, vecOrigin, 100)
end

function behaviorLib.ManaPotUtilFn(nManaMissing)
	-- Roughly 20+ when we are missing 100 mana
	-- Function which crosses 20 at x=100 and 30 at x=600, convex down

	local nManaRegenAmount = 100
	local nUtilityThreshold = 20
	
	local vecPoint = Vector3.Create(nManaRegenAmount, nUtilityThreshold)
	local vecOrigin = Vector3.Create(-1000, -15)
	return core.ATanFn(nManaMissing, vecPoint, vecOrigin, 100)
end

function behaviorLib.BottleManaUtilFn(nManaMissing)
	-- Roughly 20+ when we are missing 145 mana
	-- Function which crosses 20 at x=145 and 30 at x=170, convex down

	local nManaRegenAmount = 70
	local nManaBuffer = 75
	local nUtilityThreshold = 20
	
	local vecPoint = Vector3.Create(nManaRegenAmount + nManaBuffer, nUtilityThreshold)
	local vecOrigin = Vector3.Create(75, -30)
	return core.ATanFn(nManaMissing, vecPoint, vecOrigin, 100)
end

-------- Behavior Functions --------
function behaviorLib.UseManaRegenUtility(botBrain)
	StartProfile("Init")
	local bDebugEchos = false

	local nUtility = 0
	local nManaPotUtility = 0
	local nBottleUtility = 0
	local nBatterySupplyUtility = 0
	
	local unitSelf = core.unitSelf
	local nManaMissing = unitSelf:GetMaxMana() - unitSelf:GetMana()
	local tInventory = unitSelf:GetInventory()
	StopProfile()

	StartProfile("Mana Battery/Power Supply")
	if behaviorLib.bUseBatterySupplyForMana then
		local tManaBattery = core.InventoryContains(tInventory, "Item_ManaBattery")
		local tPowerSupply = core.InventoryContains(tInventory, "Item_PowerSupply")
		local itemBatterySupply = nil
		if #tManaBattery > 0 then
			itemBatterySupply = tManaBattery[1]
		elseif #tPowerSupply > 0 then
			itemBatterySupply = tPowerSupply[1]
		end
		
		if itemBatterySupply and itemBatterySupply:CanActivate() then
			local nCharges = itemBatterySupply:GetCharges()
			if nCharges > 0 then
				nBatterySupplyUtility = behaviorLib.BatterySupplyManaUtilFn(nManaMissing, nCharges)
			end
		end
	end
	StopProfile()
	
	StartProfile("Mana pot")
	local tManaPots = core.InventoryContains(tInventory, "Item_ManaPotion")
	if #tManaPots > 0 and not unitSelf:HasState("State_ManaPotion") then
		nManaPotUtility = behaviorLib.ManaPotUtilFn(nManaMissing)
	end
	StopProfile()

	StartProfile("Bottle")
	if behaviorLib.bUseBottleForMana then
		local tItemBottle = core.InventoryContains(tInventory, "Item_Bottle")
		if #tItemBottle > 0 and not unitSelf:HasState("State_Bottle") and tItemBottle[1]:GetActiveModifierKey() ~= "bottle_empty" then
			nBottleUtility = behaviorLib.BottleManaUtilFn(nManaMissing)
		end
	end
	StopProfile()
	
	StartProfile("End")
	nUtility = max(nManaPotUtility, nBottleUtility, nBatterySupplyUtility)
	nUtility = Clamp(nUtility, 0, 100)

	behaviorLib.nManaPotUtility = nManaPotUtility
	behaviorLib.nBottleManaUtility = nBottleUtility
	behaviorLib.nBatterySupplyManaUtility = nBatterySupplyUtility
	
	if bDebugEchos then 
		BotEcho(format("UseManaRegen util: %g  nManaMissing: %d  pots(%d): %g  bottle(%d): %g", 
			nUtility, nManaMissing, #tManaPots, nManaPotUtility, #tItemBottle, nBottleUtility)) 
	end

	if botBrain.bDebugUtility == true and nUtility ~= 0 then
		BotEcho(format("  UseManaRegenUtility: %g", nUtility))
	end
	StopProfile()

	return nUtility
end

function behaviorLib.UseManaRegenExecute(botBrain)
	local bActionTaken = false
	local unitSelf = core.unitSelf
	local vecSelfPos = unitSelf:GetPosition()
	local tInventory = unitSelf:GetInventory()
	local nMaxUtility = max(behaviorLib.nManaPotUtility, behaviorLib.nBottleManaUtility, behaviorLib.nBatterySupplyManaUtility)

	-- Use Mana Potion to regen mana
	if not bActionTaken and behaviorLib.nManaPotUtility == nMaxUtility then
		local tManaPots = core.InventoryContains(tInventory, "Item_ManaPotion")
		if #tManaPots > 0 and not unitSelf:HasState("State_ManaPotion") then
			local vecRetreatDirection = behaviorLib.GetSafeDrinkDirection()
			-- Check if it is safe to drink
			if vecRetreatDirection then
				bActionTaken = core.OrderMoveToPosClamp(botBrain, unitSelf, vecSelfPos + vecRetreatDirection * core.moveVecMultiplier, false)
			else
				bActionTaken = core.OrderItemEntityClamp(botBrain, unitSelf, tManaPots[1], unitSelf)
			end
		end
	end
	
	-- Use Bottle to regen mana
	if not bActionTaken and behaviorLib.nBottleManaUtility == nMaxUtility then
		local tItemBottle = core.InventoryContains(tInventory, "Item_Bottle")
		if #tItemBottle > 0 and not unitSelf:HasState("State_Bottle") and tItemBottle[1]:GetActiveModifierKey() ~= "bottle_empty" then
			local vecRetreatDirection = behaviorLib.GetSafeDrinkDirection()
			-- Check if it is safe to drink
			if vecRetreatDirection then
				bActionTaken = core.OrderMoveToPosClamp(botBrain, unitSelf, vecSelfPos + vecRetreatDirection * core.moveVecMultiplier, false)
			else
				bActionTaken = core.OrderItemClamp(botBrain, unitSelf, tItemBottle[1])
			end
		end
	end
	
	-- Use Mana Battery/Power Supply to regen mana
	if not bActionTaken and behaviorLib.nBatterySupplyManaUtility == nMaxUtility then
		local tManaBattery = core.InventoryContains(tInventory, "Item_ManaBattery")
		local tPowerSupply = core.InventoryContains(tInventory, "Item_PowerSupply")
		local itemBatterySupply = nil
		if #tManaBattery > 0 then
			itemBatterySupply = tManaBattery[1]
		elseif #tPowerSupply > 0 then
			itemBatterySupply = tPowerSupply[1]
		end
	
		if itemBatterySupply and itemBatterySupply:CanActivate() and itemBatterySupply:GetCharges() > 0 then
			bActionTaken = core.OrderItemClamp(botBrain, unitSelf, itemBatterySupply)
		end
	end
	
	return bActionTaken
end

behaviorLib.UseManaRegenBehavior = {}
behaviorLib.UseManaRegenBehavior["Utility"] = behaviorLib.UseManaRegenUtility
behaviorLib.UseManaRegenBehavior["Execute"] = behaviorLib.UseManaRegenExecute
behaviorLib.UseManaRegenBehavior["Name"] = "UseManaRegen"
tinsert(behaviorLib.tBehaviors, behaviorLib.UseManaRegenBehavior)

------------------------------------
--          PositionSelf          --
------------------------------------
--
-- Utility: 20 
-- Always returns 20
--
-- Execute:
-- Move forward in lane to the farthest friendly creep wave
-- Stay away from towers that are aggro'd to the bot
-- Stay near target
-- Stand slightly appart from allied heroes
-- Stand away from enemy heroes and enemy creeps
--

-------- Behavior Functions --------
function behaviorLib.PositionSelfUtility(botBrain)
	local nUtility = 20

	if botBrain.bDebugUtility == true and nUtility ~= 0 then
		BotEcho(format("  PositionSelfUtility: %g", nUtility))
	end

	return nUtility
end

function behaviorLib.PositionSelfExecute(botBrain)
	local bDebugLines = false
	local bActionTaken = false
	
	if not bActionTaken then
		local vecDesiredPos, unitTarget = behaviorLib.PositionSelfLogic(botBrain)
		if vecDesiredPos then
			bActionTaken = behaviorLib.MoveExecute(botBrain, vecDesiredPos)
			
			if bDebugLines then
				if unitTarget ~= nil then
					core.DrawXPosition(unitTarget:GetPosition(), 'orange', 125)
				end

				if vecDesiredPos then
					core.DrawXPosition(vecDesiredPos, 'blue')
				end
			end
		end
	end

	if not bActionTaken then
		BotEcho("PositionSelfExecute - nil desired position")
	end
	
	return bActionTaken
end

behaviorLib.PositionSelfBehavior = {}
behaviorLib.PositionSelfBehavior["Utility"] = behaviorLib.PositionSelfUtility
behaviorLib.PositionSelfBehavior["Execute"] = behaviorLib.PositionSelfExecute
behaviorLib.PositionSelfBehavior["Name"] = "PositionSelf"
tinsert(behaviorLib.tBehaviors, behaviorLib.PositionSelfBehavior)

-----------------------------------------
--          RetreatFromThreat          --
-----------------------------------------
--
-- Utility: 0 to 100
-- Based on creep aggro/damage, tower aggro/damage,
-- recent damage taken, and units in the area
--
-- Execute:
-- Use Ghost Marchers if possible.
-- If the bot is in lane, will use lane nodes to retreat.
-- Otherwise the bot will use pathing.
--

-------- Global Constants & Variables --------
behaviorLib.nCreepAggroUtility = 25
behaviorLib.nRecentDamageMul = 0.35
behaviorLib.nTowerProjectileUtility = 33
behaviorLib.nTowerAggroUtility = 25

behaviorLib.retreatGhostMarchersThreshold = 28
behaviorLib.lastRetreatUtil = 0
 
-------- Helper Functions --------
function behaviorLib.PositionSelfBackUp()
	StartProfile('PositionSelfBackUp')
	
	local vecMyPos = core.unitSelf:GetPosition()
	local vecDesiredPos = nil
	
	if not vecDesiredPos then
		-- Use Lane nodes to path backwards
		local tLaneSet = core.tMyLane
		if tLaneSet then
			local nodePrev = nil
			local nPrevNode = nil
			local nLaneSetSize = #tLaneSet
			nodePrev,nPrevNode = core.GetPrevWaypoint(tLaneSet, vecMyPos, core.bTraverseForward)
			if nodePrev then
				local vecNodePrevPos = nodePrev:GetPosition()
				vecDesiredPos = vecNodePrevPos
				local nodePrevPrev = nil
				if core.bTraverseForward and nPrevNode > 1 then
					nodePrevPrev = tLaneSet[nPrevNode - 1]
				elseif not core.bTraverseForward and nPrevNode < nLaneSetSize then
					nodePrevPrev = tLaneSet[nPrevNode + 1]
				end
				
				-- If possible path back to the second closest node
				if nodePrevPrev then
					local vecNodePrevPrevPos = nodePrevPrev:GetPosition()
					local vecForward = Vector3.Normalize(vecNodePrevPos - vecNodePrevPrevPos)
					if core.RadToDeg(core.AngleBetween(vecNodePrevPos - vecMyPos, vecForward)) < 135 then
						vecDesiredPos = vecNodePrevPrevPos
					end
				end
			end
		end
	end
 
	if not vecDesiredPos then
		-- If all else fails then just head to well
		vecDesiredPos = core.allyWell:GetPosition()
	end
	
	StopProfile()
	return vecDesiredPos
end

-------- Behavior Functions --------
function behaviorLib.RetreatFromThreatUtility(botBrain)
	local bDebugEchos = false
	local unitSelf = core.unitSelf

	--Creep aggro
	local nCreepAggroUtility = 0
	local tEnemyCreeps = core.localUnits["EnemyCreeps"]
	for _, unitEnemyCreep in pairs(tEnemyCreeps) do
		local unitAggroTarget = unitEnemyCreep:GetAttackTarget()
		if unitAggroTarget and unitAggroTarget:GetUniqueID() == unitSelf:GetUniqueID() then
			nCreepAggroUtility = behaviorLib.nCreepAggroUtility
			break
		end
	end

	--RecentDamage	
	local nRecentDamage = (eventsLib.recentDamageTwoSec + eventsLib.recentDamageSec) / 2.0
	local nRecentDamageUtility = nRecentDamage * behaviorLib.nRecentDamageMul

	--Tower Aggro
	local nTowerAggroUtility = 0
	local tEnemyTowers = core.localUnits["EnemyTowers"]
	for _, unitTower in pairs(tEnemyTowers) do
		local unitAggroTarget = unitTower:GetAttackTarget()
		if bDebugEchos then BotEcho(tower:GetTypeName().." target: "..(unitAggroTarget and unitAggroTarget:GetTypeName() or 'nil')) end
		if unitAggroTarget ~= nil and unitAggroTarget == core.unitSelf then
			nTowerAggroUtility = behaivorLib.nTowerAggroUtility
			break
		end
	end
	
	local nNumTowerProj = #eventsLib.incomingProjectiles["towers"]
	local nTowerProjectilesUtility = nNumTowerProj * behaviorLib.nTowerProjectileUtility
	
	local nTowerUtility = max(nTowerProjectilesUtility, nTowerAggroUtility)
	
	--Total
	local nUtility = nCreepAggroUtility + nRecentDamageUtility + nTowerUtility
	nUtility = Clamp(nUtility, 0, 100)
	behaviorLib.lastRetreatUtil = nUtility
	
	if bDebugEchos then
		BotEcho(format("nRecentDmgUtil: %d  nRecentDamage: %g", nRecentDamageUtility, nRecentDamage))
		BotEcho(format("nTowerUtil: %d  max( nTowerProjectilesUtil: %d, nTowerAggroUtil: %d )", nTowerUtility, nTowerProjectilesUtility, nTowerAggroUtility))
		BotEcho(format("util: %d  recentDmg: %d  tower: %d  creeps: %d", nUtility, nRecentDamageUtility, nTowerUtility, nCreepAggroUtility))		
	end

	if botBrain.bDebugUtility == true and nUtility ~= 0 then
		BotEcho(format("  RetreatFromThreatUtility: %g", nUtility))
	end

	return nUtility
end

function behaviorLib.RetreatFromThreatExecute(botBrain)
	local bActionTaken = false
	
	if not bActionTaken then
		-- Activate ghost marchers if we can
		local itemGhostMarchers = core.itemGhostMarchers
		if itemGhostMarchers and itemGhostMarchers:CanActivate() and behaviorLib.lastRetreatUtil >= behaviorLib.retreatGhostMarchersThreshold then
			bActionTaken = core.OrderItemClamp(botBrain, core.unitSelf, itemGhostMarchers)
		end
	end
	
	if not bActionTaken then
		-- Retreat to the desired position
		local vecPos = behaviorLib.PositionSelfBackUp()
		bActionTaken = core.OrderMoveToPosClamp(botBrain, core.unitSelf, vecPos, false)
	end
	
	return bActionTaken
end

behaviorLib.RetreatFromThreatBehavior = {}
behaviorLib.RetreatFromThreatBehavior["Utility"] = behaviorLib.RetreatFromThreatUtility
behaviorLib.RetreatFromThreatBehavior["Execute"] = behaviorLib.RetreatFromThreatExecute
behaviorLib.RetreatFromThreatBehavior["Name"] = "RetreatFromThreat"
tinsert(behaviorLib.tBehaviors, behaviorLib.RetreatFromThreatBehavior)

----------------------------------
--          HealAtWell          --
----------------------------------
--
-- Utility: 0 to 100
-- Based on proximity to well and current health
--
-- Execute:
-- Path to well and hold position at well,
-- or use lane nodes to retreat
--

-------- Helper Functions --------
function behaviorLib.WellProximityUtility(nDist)
	local nMaxVal = 15
	local nFarX = 5000

	local nUtility = 0
	nUtility = nUtility + core.ParabolicDecayFn(nDist, nMaxVal, nFarX)

	if nDist <= 600 then
		nUtility = nUtility + 20
	end

	nUtility = Clamp(nUtility, 0, 100)
	
	return nUtility
end

function behaviorLib.WellHealthUtility(nHealthPercent)
	local nHeight = 100
	local vecCriticalPoint = Vector3.Create(0.25, 20)

	local nUtility = nHeight / ((nHeight/vecCriticalPoint.y) ^ (nHealthPercent/vecCriticalPoint.x))
	
	return nUtility
end

-------- Behavior Functions --------
function behaviorLib.HealAtWellUtility(botBrain)
	local nUtility = 0
	local nHealthPercent = core.unitSelf:GetHealthPercent()

	if nHealthPercent < 0.95 then
		local vecWellPos = core.allyWell and core.allyWell:GetPosition() or Vector3.Create()
		local nDist = Vector3.Distance2D(vecWellPos, core.unitSelf:GetPosition())

		nUtility = behaviorLib.WellHealthUtility(nHealthPercent) + behaviorLib.WellProximityUtility(nDist)
	end

	if botBrain.bDebugUtility == true and nUtility ~= 0 then
		BotEcho(format("  HealAtWellUtility: %g", nUtility))
	end
	
	return nUtility
end

function behaviorLib.HealAtWellExecute(botBrain)
	local bActionTaken = false
	
	if not bActionTaken then
		local wellPos = core.allyWell and core.allyWell:GetPosition() or behaviorLib.PositionSelfBackUp()
		bActionTaken = core.OrderMoveToPosAndHoldClamp(botBrain, core.unitSelf, wellPos, false)
	end
	
	return bActionTaken
end

behaviorLib.HealAtWellBehavior = {}
behaviorLib.HealAtWellBehavior["Utility"] = behaviorLib.HealAtWellUtility
behaviorLib.HealAtWellBehavior["Execute"] = behaviorLib.HealAtWellExecute
behaviorLib.HealAtWellBehavior["Name"] = "HealAtWell"
tinsert(behaviorLib.tBehaviors, behaviorLib.HealAtWellBehavior)

----------------------------
--          Shop          --
----------------------------
--
-- Utility: 99 or 0
-- 99 if just entered well and not finished buying, 0 otherwise
--
-- Execute:
-- Buy the next item in the list
--

--TODO: separate "sort inventory and stash" into a second behavior so we can do so after using a TP in the well
--TODO: dynamic item builds
--TODO: dynamic regen purchases
--TODO: Courier use
--TODO: Use "CanAccessWellShop" instead of CanAccessStash

-------- Global Constants & Variables --------
behaviorLib.printShopDebug = false

behaviorLib.nextBuyTime = HoN.GetGameTime()
behaviorLib.buyInterval = 1000
behaviorLib.finishedBuying = false
behaviorLib.canAccessShopLast = false

behaviorLib.BuyStateUnknown = 0
behaviorLib.BuyStateStartingItems = 1
behaviorLib.BuyStateLaneItems = 2
behaviorLib.BuyStateMidItems = 3
behaviorLib.BuyStateLateItems = 4
behaviorLib.buyState = behaviorLib.BuyStateUnknown

-- list code:
--   "# Item" is "get # of this item"
--   "Item #" is "get # level of this item"
behaviorLib.StartingItems = {}
behaviorLib.LaneItems = {}
behaviorLib.MidItems = {} 
behaviorLib.LateItems = {} 

behaviorLib.curItemList = {}

behaviorLib.BootsList = {"Item_PostHaste", "Item_EnhancedMarchers", "Item_PlatedGreaves", "Item_Steamboots", "Item_Striders", "Item_Marchers"}
behaviorLib.MagicDefList = {"Item_Immunity", "Item_BarrierIdol", "Item_MagicArmor2", "Item_MysticVestments"}
behaviorLib.sPortalKeyName = "Item_PortalKey"

-------- Helper Functions --------
function behaviorLib.ProcessItemCode(sItemCode)
	local nNum = 1
	local nLevel = 1
	local sItemName = sItemCode
	local nPos = strfind(sItemCode, " ")
	if nPos then
		local nTemp = strsub(sItemCode, 1, nPos - 1)
		if tonumber(nTemp) ~= nil then
			nNum = tonumber(nTemp)
			sItemName = strsub(sItemCode, nPos + 1)
		end
	end

	nPos = strfind(sItemName, " ")
	if nPos then
		local nLevelTemp = strsub(sItemName, nPos + 1)
		if tonumber(nLevelTemp) ~= nil then
			nLevel = tonumber(nLevelTemp)
			sItemName = strsub(sItemName, 1, nPos - 1)
		end
	end

	return sItemName, nNum, nLevel
end

function behaviorLib.DetermineBuyState(botBrain)
	--This is for determining where in our buy pattern we are.  We need this for when we dynamically reload the script.
	local tInventory = core.unitSelf:GetInventory(true)
	local tLists = {behaviorLib.LateItems, behaviorLib.MidItems, behaviorLib.LaneItems, behaviorLib.StartingItems}
	for i, tItemList in ipairs(tLists) do
		for j = #tItemList, 1, -1 do
			local sItemName = tItemList[j]
			local sName, nNum, nLevel = behaviorLib.ProcessItemCode(sItemName)
			local tItems = core.InventoryContains(tInventory, sName, true, true)
			local nNumValid = #tItems
			if behaviorLib.printShopDebug then 
				BotEcho("DetermineBuyState - Checking for "..nNum.."x "..sName.." lvl "..nLevel.." in Inventory") 
			end

			if tItems then
				for nArrayPos, itemCurrent in ipairs(tItems) do
					if itemCurrent:GetLevel() < nLevel or itemCurrent:IsRecipe() then
						tremove(tItems, nArrayPos)
						nNumValid = nNumValid - 1
					end
				end
			end

			--if we have this, set the currentItem list to everything "past" this
			if nNumValid >= nNum then
				if j ~= #tItemList then
					if i == 1 then
						behaviorLib.curItemList = core.CopyTable(behaviorLib.LateItems)
						behaviorLib.buyState = behaviorLib.BuyStateLateItems
					elseif i == 2 then
						behaviorLib.curItemList = core.CopyTable(behaviorLib.MidItems)
						behaviorLib.buyState = behaviorLib.BuyStateMidItems
					elseif i == 3 then
						behaviorLib.curItemList = core.CopyTable(behaviorLib.LaneItems)
						behaviorLib.buyState = behaviorLib.BuyStateLaneItems
					else
						behaviorLib.curItemList = core.CopyTable(behaviorLib.StartingItems)
						behaviorLib.buyState = behaviorLib.BuyStateStartingItems
					end

					-- Remove the items we already have
					local nNumToRemove = j - 1
					for k = 0, nNumToRemove, 1 do
						tremove(behaviorLib.curItemList, 1)
					end
				else
					-- Special case for last item in list
					if i == 1 or i == 2 then
						behaviorLib.curItemList = core.CopyTable(behaviorLib.LateItems)
						behaviorLib.buyState = behaviorLib.BuyStateLateItems
					elseif i == 3 then
						behaviorLib.curItemList = core.CopyTable(behaviorLib.MidItems)
						behaviorLib.buyState = behaviorLib.BuyStateMidItems
					elseif i == 4 then
						behaviorLib.curItemList = core.CopyTable(behaviorLib.LaneItems)
						behaviorLib.buyState = behaviorLib.BuyStateLaneItems
					end
				end

                --an item was found, we are all done here
				if behaviorLib.printShopDebug then
					BotEcho("   DetermineBuyState - Found Item!")
				end

                return
			end
		end
	end

	-- We have found no items, start at the beginning
	behaviorLib.curItemList = core.CopyTable(behaviorLib.StartingItems)
	behaviorLib.buyState = behaviorLib.BuyStateStartingItems

	if behaviorLib.printShopDebug then
		BotEcho("   DetermineBuyState - No item found! Starting at the beginning of the buy list")
	end
	
	return
end

function behaviorLib.ShuffleCombine(botBrain, itemNextDef, unitSelf)
	local tInventory = unitSelf:GetInventory(true)

	if behaviorLib.printShopDebug then
		BotEcho("ShuffleCombine for "..itemNextDef:GetName())
	end

	--locate all my components
	local tComponentDefs = itemNextDef:GetComponents()
	local nNumComponents = #tComponentDefs
	local tSlotsToMove = {}
	if tComponentDefs and #tComponentDefs > 1 then
		for nSlot = 1, 12, 1 do
			local itemCurrent = tInventory[nSlot]
			if itemCurrent then
				--if itemCurrent IS the same type, check if it is our recipe and not another (completed) instance
				local bRecipeCheck = (itemCurrent:GetTypeID() ~= itemNextDef:GetTypeID()) or itemCurrent:IsRecipe()

				if behaviorLib.printShopDebug then
					BotEcho("  Checking if "..tostring(nSlot)..", "..itemCurrent:GetName().." is a component")
					BotEcho("    NextItem Type check: "..tostring(itemCurrent:GetTypeID()).." ~= "..tostring(itemNextDef:GetTypeID()).." is "..tostring(itemCurrent:GetTypeID() ~= itemNextDef:GetTypeID()))
					BotEcho("    IsRecipe chieck: "..tostring(itemCurrent:IsRecipe()))
				end

				for nComponentSlot, idefComponent in ipairs(tComponentDefs) do
					if idefComponent then
						if behaviorLib.printShopDebug then
							BotEcho("    Component Type check: "..tostring(itemCurrent:GetTypeID()).." == "..tostring(idefComponent:GetTypeID()).." is "..tostring(itemCurrent:GetTypeID() == idefComponent:GetTypeID()))
						end

						if itemCurrent:GetTypeID() == idefComponent:GetTypeID() and bRecipeCheck then
							tinsert(tSlotsToMove, nSlot)
							tremove(tComponentDefs, nComponentSlot) --remove this out so we don't mark wrong duplicates

							if behaviorLib.printShopDebug then
								BotEcho("    Component found!")
							end
							break
						end
					end
				end
			elseif behaviorLib.printShopDebug then
				BotEcho("  Checking if "..tostring(nSlot)..", EMPTY_SLOT is a component")
			end
		end

		if behaviorLib.printShopDebug then
			BotEcho("ShuffleCombine - nNumComponents "..nNumComponents.."  #tSlotsToMove "..#tSlotsToMove)
			BotEcho("tSlotsToMove:")
			core.printTable(tSlotsToMove)
		end

		if nNumComponents == #tSlotsToMove then
			if behaviorLib.printShopDebug then
				BotEcho("Finding Slots to swap into")
			end

			--swap all components into your stash to combine them, avoiding any components in your stash already
			local nDestSlot = 7
			for _, nSlot in ipairs(tSlotsToMove) do
				if nSlot < 7 then
					--Make sure we don't swap with another component
					local nNum = core.tableContains(tSlotsToMove, nDestSlot)
					while nNum > 0 do
						nDestSlot = nDestSlot + 1
						nNum = core.tableContains(tSlotsToMove, nDestSlot)
					end

					if behaviorLib.printShopDebug then
						BotEcho("Swapping: "..nSlot.." to "..nDestSlot)
					end

					unitSelf:SwapItems(nSlot, nDestSlot)
					nDestSlot = nDestSlot + 1
				end
			end
		end
	end
end

function behaviorLib.SortInventoryAndStash(botBrain)
    --[[
	C) Swap items to fill inventory
       1. Boots / +ms
       2. Magic Armor
       3. Homecoming Stone
       4. PortalKey
       5. Most Expensive Item(s) (price decending)
    --]]
	local unitSelf = core.unitSelf
	local tInventory = core.unitSelf:GetInventory(true)
	local tInventoryBefore = tInventory
	local tSlotsAvailable = {true, true, true, true, true, true} --represents slots 1-6 (backpack)
	local nSlotsLeft = 6
	local bFound = false

	--TODO: optimize via 1 iteration and storing item refs in tables for each category, then filling 1-6
	--  because this is hella bad and inefficent.

	-- Boots
	for nSlot = 1, 12, 1 do
		local itemCurrent = tInventory[nSlot]

		if behaviorLib.printShopDebug then
			local sName = "EMPTY_SLOT"
			if itemCurrent then
				sName = itemCurrent:GetName()
			end
			BotEcho("  Checking if "..tostring(nSlot)..", "..sName.." is a boot")
		end

		if itemCurrent and (nSlot > 6 or tSlotsAvailable[nSlot] ~= false) then
			for _, sBootName in ipairs(behaviorLib.BootsList) do
				if itemCurrent:GetName() == sBootName then

					if behaviorLib.printShopDebug then
						BotEcho("    Boots found")
					end

					for i = 1, #tSlotsAvailable, 1 do
						if tSlotsAvailable[i] then
							if behaviorLib.printShopDebug then 
								BotEcho("    Swapping "..tInventory[nSlot]:GetName().." into slot "..i) 
							end

							unitSelf:SwapItems(nSlot, i)
							tSlotsAvailable[i] = false
							nSlotsLeft = nSlotsLeft - 1
							tInventory[nSlot], tInventory[i] = tInventory[i], tInventory[nSlot]
							break
						end
					end
					bFound = true
				end

				if bFound then
					break
				end
			end
		end

		if bFound then
			break
		end
	end

	--magic armor
	bFound = false
	for nSlot = 1, 12, 1 do
		local itemCurrent = tInventory[nSlot]
		if nSlotsLeft < 1 then
			break
		end

		if behaviorLib.printShopDebug then
			local sName = "EMPTY_SLOT"
			if itemCurrent then
				sName = itemCurrent:GetName()
			end
			BotEcho("  Checking if "..tostring(nSlot)..", "..sName.." has magic defense")
		end

		if itemCurrent and (nSlot > 4 or tSlotsAvailable[nSlot] ~= false) then
			for _, sMagicArmorItemName in ipairs(behaviorLib.MagicDefList) do
				if itemCurrent:GetName() == sMagicArmorItemName then
					for i = 1, #tSlotsAvailable, 1 do
						if tSlotsAvailable[i] then
							unitSelf:SwapItems(nSlot, i)
							tSlotsAvailable[i] = false
							nSlotsLeft = nSlotsLeft - 1
							tInventory[nSlot], tInventory[i] = tInventory[i], tInventory[nSlot]
							break
						end
					end
					bFound = true
				end

				if bFound then
					break
				end
			end
		end

		if bFound then
			break
		end
	end

	-- Homecoming stone
	bFound = false
	local sTPName = core.idefHomecomingStone:GetName()
	for nSlot = 1, 12, 1 do
		local itemCurrent = tInventory[nSlot]
		if nSlotsLeft < 1 then
			break
		end

		if behaviorLib.printShopDebug then
			local sName = "EMPTY_SLOT"
			if itemCurrent then
				sName = itemCurrent:GetName()
			end
			BotEcho("  Checking if "..tostring(nSlot)..", "..sName.." is a homecoming stone")
		end

		if itemCurrent and (nSlot > 6 or tSlotsAvailable[nSlot] ~= false) then
			if itemCurrent:GetName() == sTPName then
				for i = 1, #tSlotsAvailable, 1 do
					if tSlotsAvailable[i] then
						unitSelf:SwapItems(nSlot, i)
						tSlotsAvailable[i] = false
						nSlotsLeft = nSlotsLeft - 1
						tInventory[nSlot], tInventory[i] = tInventory[i], tInventory[nSlot]
						break
					end
				end
				bFound = true
			end
		end

		if bFound then
			break
		end
	end

	-- Portal key
	bFound = false
	local sPortalKeyName = behaviorLib.sPortalKeyName
	for nSlot = 1, 12, 1 do
		local itemCurrent = tInventory[nSlot]
		if nSlotsLeft < 1 then
			break
		end

		if behaviorLib.printShopDebug then
			local sName = "EMPTY_SLOT"
			if itemCurrent then
				sName = itemCurrent:GetName()
			end
			BotEcho("  Checking if "..tostring(nSlot)..", "..sName.." is a homecoming stone")
		end

		if itemCurrent and (nSlot > 6 or tSlotsAvailable[nSlot] ~= false) then
			if itemCurrent:GetName() == sPortalKeyName then
				for i = 1, #tSlotsAvailable, 1 do
					if tSlotsAvailable[i] then
						unitSelf:SwapItems(nSlot, i)
						tSlotsAvailable[i] = false
						nSlotsLeft = nSlotsLeft - 1
						tInventory[nSlot], tInventory[i] = tInventory[i], tInventory[nSlot]
						break
					end
				end
				bFound = true
			end
		end

		if bFound then
			break
		end
	end

	if botBrain.printShopDebug then
		BotEcho("Inv:")
		printInventory(tInventory)
	end

	-- Most expensive
	while nSlotsLeft > 0 do
		--selection sort
		local nHighestValue = 0
		local nHighestSlot = -1
		for nSlot = 1, 12, 1 do
			local itemCurrent = tInventory[nSlot]
			if itemCurrent and (nSlot > 6 or tSlotsAvailable[nSlot] ~= false) then
				local nCost = 0
				if not itemCurrent:IsRecipe() then
					nCost = itemCurrent:GetTotalCost()
				end

				if nCost > nHighestValue then
					nHighestValue = nCost
					nHighestSlot = nSlot
				end
			end
		end

		if nHighestSlot ~= -1 then

			if botBrain.printShopDebug then
				BotEcho("Highest Cost: "..nHighestValue.."  slots available:")
				core.printTable(tSlotsAvailable)
			end

			for i = 1, #tSlotsAvailable, 1 do
				if tSlotsAvailable[i] then
					if behaviorLib.printShopDebug then 
						BotEcho("  Swapping "..tInventory[nHighestSlot]:GetName().." into slot "..i) 
					end

					unitSelf:SwapItems(nHighestSlot, i)
					tSlotsAvailable[i] = false
					tInventory[nHighestSlot], tInventory[i] = tInventory[i], tInventory[nHighestSlot]
					nSlotsLeft = nSlotsLeft - 1
					break
				end
			end
		else
			break
		end
	end

	-- Compare backpack before and after to check for changes
	local bChanged = false
	for nSlot = 1, 6, 1 do
		if tInventory[nSlot] ~= tInventoryBefore[nSlot] then
			bChanged = true
			break
		end
	end

	return bChanged
end

function behaviorLib.SellLowestItems(botBrain, nNumToSell)
	if nNumToSell > 12 then --sanity checking
		return
	end

	local tInventory = core.unitSelf:GetInventory(true)
	local nLowestValue
	local nLowestSlot
	local itemLowestValue = nil
	while nNumToSell > 0 do
		nLowestValue = 99999
		for nSlot = 1, 12, 1 do
			local itemCurrent = tInventory[nSlot]
			if itemCurrent then
				local nCost = itemCurrent:GetTotalCost()
				if nCost < nLowestValue then
					nLowestValue = nCost
					itemLowestValue = itemCurrent
				end
			end
		end

		if itemLowestValue then
			if bDebugEchoes then
				BotEcho("Selling "..itemLowestValue:GetName().." in slot "..itemLowestValue:GetSlot())
			end
			
			core.unitSelf:Sell(itemLowestValue)
			tInventory[itemLowestValue:GetSlot()] = ""
			nNumToSell = nNumToSell - 1
		else
			return
		end
	end
end

function behaviorLib.NumberSlotsOpen(tInventory)
	local nOpenSlots = 0
	for nSlot = 1, 12, 1 do
		itemCurrent = tInventory[nSlot]
		if not itemCurrent then
			nOpenSlots = nOpenSlots + 1
		end
	end
	
	return nOpenSlots
end

function behaviorLib.DetermineNextItemDef(botBrain)
	local inventory = core.unitSelf:GetInventory(true)
	
	--check if our last suggested buy was purchased
	local sName, num, level = behaviorLib.ProcessItemCode(behaviorLib.curItemList[1])
	local tableItems = core.InventoryContains(inventory, sName, true, true)

	if behaviorLib.printShopDebug then
		BotEcho("DetermineNextItemDef - behaviorLib.curItemList")
		core.printTable(behaviorLib.curItemList)
		BotEcho("DetermineNextItemDef - Checking for "..num.."x "..sName.." lvl "..level.." in Inventory")
	end

	local idefCurrent = HoN.GetItemDefinition(sName)
	local bStackable = idefCurrent:GetRechargeable() --"rechargeable" items are items that stack

	local numValid = 0
	if not bStackable then
		if tableItems then
			numValid = #tableItems
			for arrayPos, curItem in ipairs(tableItems) do
				if curItem:GetLevel() < level or curItem:IsRecipe() then
					tremove(tableItems, arrayPos)
					numValid = numValid - 1
					if behaviorLib.printShopDebug then 
						BotEcho('One of the '..sName..' is not valid level or is a recipe...') 
					end
				end
			end
		end
	else
		num = num * idefCurrent:GetInitialCharges()
		for arrayPos, curItem in ipairs(tableItems) do
			numValid = numValid + curItem:GetCharges()
		end
	end

	--if we have this, remove it from our active list
	if numValid >= num then
		if behaviorLib.printShopDebug then 
			BotEcho('Found it! Removing it from the list') 
		end
		
		if #behaviorLib.curItemList > 1 then
			tremove(behaviorLib.curItemList, 1)
		else
			if behaviorLib.printShopDebug then 
				BotEcho('End of this list, switching lists') 
			end
			
			-- special case for last item in list
			if behaviorLib.buyState == behaviorLib.BuyStateStartingItems then
				behaviorLib.curItemList = core.CopyTable(behaviorLib.LaneItems)
				behaviorLib.buyState = behaviorLib.BuyStateLaneItems
			elseif behaviorLib.buyState == behaviorLib.BuyStateLaneItems then
				behaviorLib.curItemList = core.CopyTable(behaviorLib.MidItems)
				behaviorLib.buyState = behaviorLib.BuyStateMidItems
			elseif behaviorLib.buyState == behaviorLib.BuyStateMidItems then
				behaviorLib.curItemList = core.CopyTable(behaviorLib.LateItems)
				behaviorLib.buyState = behaviorLib.BuyStateLateItems
			else
				--keep repeating our last item
			end
		end
	end

	local itemName = behaviorLib.ProcessItemCode(behaviorLib.curItemList[1])
	local retItemDef = HoN.GetItemDefinition(itemName)

	if behaviorLib.printShopDebug then
		BotEcho("DetermineNextItemDef - behaviorLib.curItemList")
		core.printTable(behaviorLib.curItemList)
		if behaviorLib.curItemList[1] then
			BotEcho("DetermineNextItemDef - itemName: "..itemName)
		else
			BotEcho("DetermineNextItemDef - No item in list! Check your code!")
		end
	end

	return retItemDef
end

-------- Behavior Functions --------
function behaviorLib.ShopUtility(botBrain)
	local bCanAccessShop = core.unitSelf:CanAccessStash()

	--just got into shop access, try buying
	if bCanAccessShop and not behaviorLib.canAccessShopLast then
		behaviorLib.finishedBuying = false
	end

	behaviorLib.canAccessShopLast = bCanAccessShop

	local nUtility = 0
	if bCanAccessShop and not behaviorLib.finishedBuying then
		if not core.teamBotBrain.bPurchasedThisFrame then
			nUtility = 99
		end
	end

	if botBrain.bDebugUtility == true and nUtility ~= 0 then
		BotEcho(format("  ShopUtility: %g", nUtility))
	end

	return nUtility
end

function behaviorLib.ShopExecute(botBrain)
--[[
Current algorithm:
    A) Buy items from the list
    B) Swap items to complete recipes
    C) Swap items to fill inventory, prioritizing...
       1. Boots / +ms
       2. Magic Armor
       3. Homecoming Stone
       4. Most Expensive Item(s) (price decending)
--]]
	if object.bUseShop == false then
		return
	end

	-- Space out your buys
	if behaviorLib.nextBuyTime > HoN.GetGameTime() then
		return
	end

	behaviorLib.nextBuyTime = HoN.GetGameTime() + behaviorLib.buyInterval

	--Determine where in the pattern we are (mostly for reloads)
	if behaviorLib.buyState == behaviorLib.BuyStateUnknown then
		behaviorLib.DetermineBuyState(botBrain)
	end
	
	local unitSelf = core.unitSelf
	local bChanged = false
	local bShuffled = false
	local bGoldReduced = false
	local tInventory = core.unitSelf:GetInventory(true)
	local nextItemDef = behaviorLib.DetermineNextItemDef(botBrain)

	--For our first frame of this execute
	if core.GetLastBehaviorName(botBrain) ~= core.GetCurrentBehaviorName(botBrain) then
		if nextItemDef:GetName() ~= core.idefHomecomingStone:GetName() then		
			--Seed a TP stone into the buy items after 1 min, Don't buy TP stones if we have Post Haste
			local sName = "Item_HomecomingStone"
			local nTime = HoN.GetMatchTime()
			local itemPostHaste = core.InventoryContains(tInventory, "Item_PostHaste", true)
			if nTime > core.MinToMS(1) and itemPostHaste == 0 then
				tinsert(behaviorLib.curItemList, 1, sName)
			end
			
			nextItemDef = behaviorLib.DetermineNextItemDef(botBrain)
		end
	end
	
	if behaviorLib.printShopDebug then
		BotEcho("============ BuyItems ============")
		if nextItemDef then
			BotEcho("BuyItems - nextItemDef: "..nextItemDef:GetName())
		else
			BotEcho("ERROR: BuyItems - Invalid ItemDefinition returned from DetermineNextItemDef")
		end
	end

	if nextItemDef then
		core.teamBotBrain.bPurchasedThisFrame = true
		
		--open up slots if we don't have enough room in the stash + inventory
		local componentDefs = unitSelf:GetItemComponentsRemaining(nextItemDef)
		local slotsOpen = behaviorLib.NumberSlotsOpen(tInventory)

		if behaviorLib.printShopDebug then
			BotEcho("Component defs for "..nextItemDef:GetName()..":")
			core.printGetNameTable(componentDefs)
			BotEcho("Checking if we need to sell items...")
			BotEcho("  #components: "..#componentDefs.."  slotsOpen: "..slotsOpen)
		end

		if #componentDefs > slotsOpen + 1 then --1 for provisional slot
			behaviorLib.SellLowestItems(botBrain, #componentDefs - slotsOpen - 1)
		elseif #componentDefs == 0 then
			behaviorLib.ShuffleCombine(botBrain, nextItemDef, unitSelf)
		end

		local nGoldAmtBefore = botBrain:GetGold()
		unitSelf:PurchaseRemaining(nextItemDef)

		local nGoldAmtAfter = botBrain:GetGold()
		bGoldReduced = (nGoldAmtAfter < nGoldAmtBefore)
		bChanged = bChanged or bGoldReduced

		--Check to see if this purchased item has uncombined parts
		componentDefs = unitSelf:GetItemComponentsRemaining(nextItemDef)
		if #componentDefs == 0 then
			behaviorLib.ShuffleCombine(botBrain, nextItemDef, unitSelf)
		end
	end

	bShuffled = behaviorLib.SortInventoryAndStash(botBrain)
	bChanged = bChanged or bShuffled

	if not bChanged then
		if behaviorLib.printShopDebug then
			BotEcho("Finished Buying!")
		end
		
		behaviorLib.finishedBuying = true
	end
end

behaviorLib.ShopBehavior = {}
behaviorLib.ShopBehavior["Utility"] = behaviorLib.ShopUtility
behaviorLib.ShopBehavior["Execute"] = behaviorLib.ShopExecute
behaviorLib.ShopBehavior["Name"] = "Shop"
tinsert(behaviorLib.tBehaviors, behaviorLib.ShopBehavior)
