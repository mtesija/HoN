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
function core.GetClosestTeleportUnit(vecDesiredPosition)
	local unitBuilding = core.GetClosestTeleportBuilding(vecDesiredPosition)
	local vecBuildingPosition = unitBuilding:GetPosition()
	local nDistance = Vector3.Distance2D(vecBuildingPosition, vecDesiredPosition)
	local nDistancePositionToTowerSq = nDistance * nDistance

	local unitTarget = nil
	local nBestDistanceSq = nDistancePositionToTowerSq
	local tPortTargets = HoN.GetUnitsInRadius(vecDesiredPosition, nDistance, core.UNIT_MASK_ALIVE + core.UNIT_MASK_UNIT)
	for _, unitCreep in pairs(tPortTargets) do
		if unitCreep:GetTeam() == core.myTeam and string.find(unitCreep:GetTypeName(), "Creep") and unitCreep:GetHealth() > (unitCreep:GetMaxHealth() * .8) then
			local vecCreepPosition = unitCreep:GetPosition()
			if Vector3.Distance2DSq(vecCreepPosition, vecBuildingPosition) < nDistancePositionToTowerSq then
				-- Only consider creeps between the closest building and the desired position
				local nDistanceCreepToPositionSq = Vector3.Distance2DSq(vecCreepPosition, vecDesiredPosition)
				if nDistanceCreepToPositionSq < nBestDistanceSq then
					nBestDistanceSq = nDistanceCreepToPositionSq
					unitTarget = unitCreep
				end
			end
		end
	end

	return unitTarget or unitBuilding
end

function behaviorLib.ShouldPort(botBrain, vecDesiredPosition)
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
	
	local idefPostHaste = HoN.GetItemDefinition("Item_PostHaste")
	if idefPostHaste then
		local tPostHaste = core.InventoryContains(tInventory, idefPostHaste:GetName(), true)
		if #tPostHaste > 0 then
			itemPort = tPostHaste[1]
			unitTarget = core.GetClosestTeleportUnit(vecDesiredPosition)

			if bDebugEchos then
				BotEcho("  unitTarget: "..(unitTarget and unitTarget:GetTypeName() or "nil")) 
			end

			if unitTarget then
				local nMoveSpeed = unitSelf:GetMoveSpeed()
				local vecMyPos = unitSelf:GetPosition()
				local vecTargetPosition = unitTarget:GetPosition()
				local nNormalWalkingTimeMS = core.TimeToPosition(vecDesiredPosition, vecMyPos, nMoveSpeed, itemGhostMarchers)
				local nCooldownTime = core.GetRemainingCooldownTime(unitSelf, idefPostHaste)
				local nPortWalkTime = core.TimeToPosition(vecDesiredPosition, vecTargetPosition, nMoveSpeed, itemGhostMarchers)
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
					core.DrawXPosition(vecTargetPosition, 'teal')
					core.DrawDebugLine(vecMyPos, vecTargetPosition)
					core.DrawXPosition(vecDesiredPosition, 'red')
				end
			end
		end
	end
		
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
					local vecMyPos = unitSelf:GetPosition()
					local vecTargetPosition = unitTarget:GetPosition()
					local nNormalWalkingTimeMS = core.TimeToPosition(vecDesiredPosition, vecMyPos, nMoveSpeed, itemGhostMarchers)
					local nCooldownTime = core.GetRemainingCooldownTime(unitSelf, idefHomecomingStone)
					local nPortWalkTime = core.TimeToPosition(vecDesiredPosition, vecTargetPosition, nMoveSpeed, itemGhostMarchers)
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
						core.DrawDebugLine(vecMyPos, unitTarget:GetPosition())
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
			local bShouldPort, unitTarget, itemPort = behaviorLib.ShouldPort(botBrain, vecDesiredPosition)
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
	
	if core.itemHatchet then
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
	if nDistSq < nAttackRangeSq and unitSelf:IsAttackReady() then
		--only attack when in nRange, so not to aggro towers/creeps until necessary, and move forward when attack is on cd
		bActionTaken = core.OrderAttackClamp(botBrain, unitSelf, unitTarget)
	end
	
	-- Use Loggers Hatchet
	if not bActionTaken then
		local itemHatchet = core.itemHatchet
		if itemHatchet and itemHatchet:CanActivate() and unitTarget:GetTeam() ~= unitSelf:GetTeam() and string.find(unitTarget:GetTypeName(), "Creep") and core.GetAttackSequenceProgress(unitSelf) ~= "windup" and nDistSq < 600 * 600 then
			bActionTaken = botBrain:OrderItemEntity(itemHatchet.object or itemHatchet, unitTarget.object or unitTarget, false)
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
	local vecSafeDirection = nil
	local unitSelf = core.unitSelf
	local vecSelfPos = unitSelf:GetPosition()
	local nMyID = unitSelf:GetUniqueID()
	local tThreateningUnits = {}
	local tAwayFromThreatValues = {}
	for _, unitEnemy in pairs(core.localUnits["EnemyUnits"]) do
		-- Ignore creeps that are already attacking something
		local unitEnemyTarget = unitEnemy:GetAttackTarget()
		if not (string.find(unitEnemy:GetTypeName(), "Creep") and unitEnemyTarget and unitEnemyTarget:GetUniqueID() ~= nMyID) then
			local nAbsRange = core.GetAbsoluteAttackRangeToUnit(unitEnemy, unitSelf) + 325
			local nAbsRangeSq = nAbsRange * nAbsRange
			local nDistSq = Vector3.Distance2DSq(vecSelfPos, unitEnemy:GetPosition())
			if nDistSq < nAbsRangeSq then
				tinsert(tThreateningUnits, unitEnemy)
				tinsert(tAwayFromThreatValues, nAbsRange)
			end
		end
	end

	local curTimeMS = HoN.GetGameTime()
	local nThreateningUnits = core.NumberElements(tThreateningUnits)
	if nThreateningUnits > 0 or eventsLib.recentDotTime > curTimeMS or #eventsLib.incomingProjectiles["all"] > 0 then
		-- Determine best "away from threat" vector
		local vecAway = Vector3.Create()
		for nIndex, unitEnemy in pairs(tThreateningUnits) do
			local vecAwayFromTarget = Vector3.Normalize(vecSelfPos - unitEnemy:GetPosition())
			vecAway = vecAway + vecAwayFromTarget * tAwayFromThreatValues[nIndex]
		end

		if nThreateningUnits > 0 then
			local vecThreatCenter = core.GetGroupCenter(tThreateningUnits)
			vecAway = vecAway - (vecSelfPos - vecThreatCenter) * nThreateningUnits
			vecAway = Vector3.Normalize(vecAway)
		end

		-- Average vecAway with "retreat" vector
		local vecRetreat = Vector3.Normalize(behaviorLib.PositionSelfBackUp() - vecSelfPos)
		local vecSafeDirection = Vector3.Normalize(vecAway + vecRetreat)
	end

	return vecSafeDirection
end

function behaviorLib.GetBatterySupplyFromInventory(tInventory)
	-- Returns Mana Battery or Power Supply if they are in the bot's inventory
	-- else returns nil

	local tManaBattery = core.InventoryContains(tInventory, "Item_ManaBattery")
	local tPowerSupply = core.InventoryContains(tInventory, "Item_PowerSupply")
	if #tManaBattery > 0 then
		return tManaBattery[1]
	elseif #tPowerSupply > 0 then
		return tPowerSupply[1]
	end
	
	return nil
end

function behaviorLib.BatterySupplyHealthUtilFn(nHealthMissing, nCharges)
	-- With 1 Charge:
	-- Roughly 20+ when we are missing 30 health
	-- Function which crosses 20 at x=30 and 30 at x=140, convex down
	-- With 15 Charges:
	-- Roughly 20+ when we are missing 170 health
	-- Function which crosses 20 at x=170 and 30 at x=330, convex down
	
	local nHealAmount = 10 * nCharges
	local nHealBuffer = 20
	local nUtilityThreshold = 20
		
	local vecPoint = Vector3.Create(nHealAmount + nHealBuffer, nUtilityThreshold)
	local vecOrigin = Vector3.Create(-250, -30)
	return core.ATanFn(nHealthMissing, vecPoint, vecOrigin, 100)
end

function behaviorLib.BatterySupplyManaUtilFn(nManaMissing, nCharges)
	-- With 1 Charge:
	-- Roughly 20+ when we are missing 40 mana
	-- Function which crosses 20 at x=40 and 30 at x=100, convex down
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

function behaviorLib.RunesOfTheBlightUtilFn(nHealthMissing, nHealthRegen)
	-- Roughly 20+ when we are missing 115 hp
	-- Function which crosses 20 at x=115 and is 30 at roughly x=600, convex down

	local nHealAmount = 115
	local nHealBuffer = nHealthRegen * 16
	local nUtilityThreshold = 20
		
	local vecPoint = Vector3.Create(nHealAmount + nHealBuffer, nUtilityThreshold)
	local vecOrigin = Vector3.Create(-1000, -20)
	return core.ATanFn(nHealthMissing, vecPoint, vecOrigin, 100)
end

function behaviorLib.HealthPotUtilFn(nHealthMissing, nHealthRegen)
	-- Roughly 20+ when we are missing 400 hp
	-- Function which crosses 20 at x=400 and 40 at x=650, convex down

	local nHealAmount = 400
	local nHealBuffer = nHealthRegen * 10
	local nUtilityThreshold = 20
	
	local vecPoint = Vector3.Create(nHealAmount, nUtilityThreshold)
	local vecOrigin = Vector3.Create(200, -40)
	return core.ATanFn(nHealthMissing, vecPoint, vecOrigin, 100)
end

function behaviorLib.BottleHealthUtilFn(nHealthMissing, nHealthRegen)
	-- Roughly 20+ when we are missing 135 hp
	-- Function which crosses 20 at x=135 and 30 at x=220, convex down
	
	local nHealAmount = 135
	local nHealBuffer = nHealthRegen * 3
	local nUtilityThreshold = 20

	local vecPoint = Vector3.Create(nHealAmount + nHealBuffer, nUtilityThreshold)
	local vecOrigin = Vector3.Create(-100, -30)
	return core.ATanFn(nHealthMissing, vecPoint, vecOrigin, 100)
end

function behaviorLib.BottleManaUtilFn(nManaMissing, nManaRegen)
	-- Roughly 20+ when we are missing 70 mana
	-- Function which crosses 20 at x=70 and 30 at x=140, convex down

	local nManaRegenAmount = 70
	local nManaBuffer = nManaRegen * 3
	local nUtilityThreshold = 20
	
	local vecPoint = Vector3.Create(nManaRegenAmount + nManaBuffer, nUtilityThreshold)
	local vecOrigin = Vector3.Create(-125, -30)
	return core.ATanFn(nManaMissing, vecPoint, vecOrigin, 100)
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
	local nHealthRegen = unitSelf:GetHealthRegen()
	local nManaMissing = unitSelf:GetMaxMana() - unitSelf:GetMana()
	local nManaRegen = unitSelf:GetManaRegen()
	local tInventory = unitSelf:GetInventory()
	StopProfile()

	StartProfile("Mana Battery/Power Supply")
	if behaviorLib.bUseBatterySupplyForHealth then
		local itemBatterySupply = behaviorLib.GetBatterySupplyFromInventory(tInventory)
		if itemBatterySupply and itemBatterySupply:CanActivate() then
			local nCharges = itemBatterySupply:GetCharges()
			if nCharges > 0 then
				nBatterySupplyUtility = behaviorLib.BatterySupplyHealthUtilFn(nHealthMissing, nCharges) * .8 + behaviorLib.BatterySupplyManaUtilFn(nManaMissing, nCharges) * .2
			end
		end
	end
	StopProfile()
	
	StartProfile("Health pot")
	local tHealthPots = core.InventoryContains(tInventory, "Item_HealthPotion")
	if #tHealthPots > 0 and not unitSelf:HasState("State_HealthPotion") then
		nHealthPotUtility = behaviorLib.HealthPotUtilFn(nHealthMissing, nHealthRegen)
	end
	StopProfile()

	StartProfile("Runes")
	local tBlights = core.InventoryContains(tInventory, "Item_RunesOfTheBlight")
	if #tBlights > 0 and not unitSelf:HasState("State_RunesOfTheBlight") then
		nBlightsUtility = behaviorLib.RunesOfTheBlightUtilFn(nHealthMissing, nHealthRegen)
	end
	StopProfile()

	StartProfile("Bottle")
	if behaviorLib.bUseBottleForHealth then
		local tItemBottle = core.InventoryContains(tInventory, "Item_Bottle")
		if #tItemBottle > 0 and not unitSelf:HasState("State_Bottle") and tItemBottle[1]:GetActiveModifierKey() ~= "bottle_empty" then
			nBottleUtility = behaviorLib.BottleHealthUtilFn(nHealthMissing, nHealthRegen) * .7 + behaviorLib.BottleManaUtilFn(nManaMissing, nManaRegen) * .3
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
	if behaviorLib.nBlightsUtility == nMaxUtility then
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
		local itemBatterySupply = behaviorLib.GetBatterySupplyFromInventory(tInventory)
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

behaviorLib.bUseBottleForMana = true
behaviorLib.bUseBatterySupplyForMana = true

-------- Helper Functions --------
function behaviorLib.ManaPotUtilFn(nManaMissing, nManaRegen)
	-- Roughly 20+ when we are missing 100 mana
	-- Function which crosses 20 at x=100 and 30 at x=200, convex down

	local nManaRegenAmount = 100
	local nManaBuffer = nManaRegen * 20
	local nUtilityThreshold = 20
	
	local vecPoint = Vector3.Create(nManaRegenAmount, nUtilityThreshold)
	local vecOrigin = Vector3.Create(-100, -45)
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
	local nHealthMissing = unitSelf:GetMaxHealth() - unitSelf:GetHealth()
	local nHealthRegen = unitSelf:GetHealthRegen()
	local nManaMissing = unitSelf:GetMaxMana() - unitSelf:GetMana()
	local nManaRegen = unitSelf:GetManaRegen()
	local tInventory = unitSelf:GetInventory()
	StopProfile()

	StartProfile("Mana Battery/Power Supply")
	if behaviorLib.bUseBatterySupplyForMana then
		local itemBatterySupply = behaviorLib.GetBatterySupplyFromInventory(tInventory)
		if itemBatterySupply and itemBatterySupply:CanActivate() then
			local nCharges = itemBatterySupply:GetCharges()
			if nCharges > 0 then
				nBatterySupplyUtility = behaviorLib.BatterySupplyManaUtilFn(nManaMissing, nCharges) * .8 + behaviorLib.BatterySupplyHealthUtilFn(nHealthMissing, nCharges) * .2
			end
		end
	end
	StopProfile()
	
	StartProfile("Mana pot")
	local tManaPots = core.InventoryContains(tInventory, "Item_ManaPotion")
	if #tManaPots > 0 and not unitSelf:HasState("State_ManaPotion") then
		nManaPotUtility = behaviorLib.ManaPotUtilFn(nManaMissing, nManaRegen)
	end
	StopProfile()

	StartProfile("Bottle")
	if behaviorLib.bUseBottleForMana then
		local tItemBottle = core.InventoryContains(tInventory, "Item_Bottle")
		if #tItemBottle > 0 and not unitSelf:HasState("State_Bottle") and tItemBottle[1]:GetActiveModifierKey() ~= "bottle_empty" then
			nBottleUtility = behaviorLib.BottleManaUtilFn(nManaMissing, nManaRegen) * .7 + behaviorLib.BottleHealthUtilFn(nHealthMissing, nHealthRegen) * .3
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
	if behaviorLib.nManaPotUtility == nMaxUtility then
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
		local itemBatterySupply = behaviorLib.GetBatterySupplyFromInventory(tInventory)
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
--          Shop Execute          --
------------------------------------

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
			local tItemPostHaste = core.InventoryContains(tInventory, "Item_PostHaste", true)
			if nTime > core.MinToMS(1) and #tItemPostHaste then
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
