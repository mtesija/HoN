-------------------------------------------------
-- ______              _     ______       _    --
-- |  ___|            | |    | ___ \     | |   --
-- | |_ __ _ _   _  __| | ___| |_/ / ___ | |_  --
-- |  _/ _` | | | |/ _` |/ _ \ ___ \/ _ \| __| --
-- | || (_| | |_| | (_| |  __/ |_/ / (_) | |_  --
-- \_| \__,_|\__, |\__,_|\___\____/ \___/ \__| --
--            __/ |                            --
--           |___/     -v1.0 By: DarkFire-     --
-------------------------------------------------

------------------------------------------
--          Bot Initialization          --
------------------------------------------

local _G = getfenv(0)
local object = _G.object

object.myName = object:GetName()

object.bRunLogic = true
object.bRunBehaviors = true
object.bUpdates = true
object.bUseShop = true

object.bRunCommands = true 
object.bMoveCommands = true
object.bAttackCommands = true
object.bAbilityCommands = true
object.bOtherCommands = true

object.bReportBehavior = false
object.bDebugUtility = false

object.logger = {}
object.logger.bWriteLog = false
object.logger.bVerboseLog = false

object.core = {}
object.eventsLib = {}
object.metadata = {}
object.behaviorLib = {}
object.skills = {}

runfile "bots/core.lua"
runfile "bots/botbraincore.lua"
runfile "bots/eventsLib.lua"
runfile "bots/metadata.lua"
runfile "bots/behaviorLib.lua"

local core, eventsLib, behaviorLib, metadata, skills = object.core, object.eventsLib, object.behaviorLib, object.metadata, object.skills

local print, ipairs, pairs, string, table, next, type, tinsert, tremove, tsort, format, tostring, tonumber, strfind, strsub
	= _G.print, _G.ipairs, _G.pairs, _G.string, _G.table, _G.next, _G.type, _G.table.insert, _G.table.remove, _G.table.sort, _G.string.format, _G.tostring, _G.tonumber, _G.string.find, _G.string.sub
local ceil, floor, pi, tan, atan, atan2, abs, cos, sin, acos, asin, min, max, random
	= _G.math.ceil, _G.math.floor, _G.math.pi, _G.math.tan, _G.math.atan, _G.math.atan2, _G.math.abs, _G.math.cos, _G.math.sin, _G.math.acos, _G.math.asin, _G.math.min, _G.math.max, _G.math.random

local BotEcho, VerboseLog, BotLog = core.BotEcho, core.VerboseLog, core.BotLog
local Clamp = core.Clamp

BotEcho('loading Fayde_main...')

---------------------------------
--          Constants          --
---------------------------------

-- Wretched Hag
object.heroName = 'Hero_Fade'

-- Item buy order. internal names  
behaviorLib.StartingItems  = {"Item_RunesOfTheBlight", "Item_LoggersHatchet", "Item_IronShield"}
behaviorLib.LaneItems  = {"Item_Marchers", "Item_Bottle", "Item_EnhancedMarchers", "Item_Nuke 1"}
behaviorLib.MidItems  = {"Item_SpellShards 3", "Item_Nuke 5"}
behaviorLib.LateItems  = {"Item_GrimoireOfPower", "Item_Silence", "Item_Morph"}

-- Skillbuild table, 0=q, 1=w, 2=e, 3=r, 4=attri
object.tSkills = {
	1, 0, 1, 0, 1,
	3, 1, 0, 0, 2,
	3, 2, 2, 2, 4,
	3, 4, 4, 4, 4,
	4, 4, 4, 4, 4,
}

-- Bonus agression points if a skill/item is available for use

object.nCullUp = 12
object.nBurningShadowsUp = 15
object.nDeepShadowsUp = 8
object.nReflectionUp = 24
object.nCodexUp = 22
object.nHellflowerUp = 14
object.nSheepstickUp = 18

-- Bonus agression points that are applied to the bot upon successfully using a skill/item

object.nCullUse = 16
object.nBurningShadowsUse = 18
object.nDeepShadowsUse = 10
object.nReflectionUse = 35
object.nCodexUse = 20
object.nHellflowerUse = 17
object.nSheepstickUse = 21

-- Thresholds of aggression the bot must reach to use these abilities

object.nCullThreshold = 22
object.nBurningShadowsThreshold = 23
object.nDeepShadowsThreshold = 21
object.nReflectionThreshold = 28
object.nCodexThreshold = 28
object.nHellflowerThreshold = 25
object.nSheepstickThreshold = 30

-- Other variables

behaviorLib.nCreepPushbackMul = 0.6
behaviorLib.nTargetPositioningMul = 1.2
behaviorLib.nTargetCriticalPositioningMul = 1

object.tIllusions = {}

------------------------------
--          Skills          --
------------------------------

function object:SkillBuild()
	local unitSelf = self.core.unitSelf
	if  skills.abilCull == nil then
		skills.abilCull = unitSelf:GetAbility(0)
		skills.abilBurningShadows = unitSelf:GetAbility(1)
		skills.abilDeepShadows = unitSelf:GetAbility(2)
		skills.abilReflection = unitSelf:GetAbility(3)
		skills.abilAttributeBoost = unitSelf:GetAbility(4)
	end
	
	local nPoints = unitSelf:GetAbilityPointsAvailable()
	if nPoints <= 0 then
		return
	end
	
	local nLevel = unitSelf:GetLevel()
	for i = nLevel, (nLevel + nPoints) do
		unitSelf:GetAbility( self.tSkills[i] ):LevelUp()
	end
end

------------------------------------------
--          FindItems Override          --
------------------------------------------

local function funcFindItemsOverride(botBrain)
	local bUpdated = object.FindItemsOld(botBrain)
	
	if core.itemBottle ~= nil and not core.itemBottle:IsValid() then
		core.itemBottle = nil
	end
	
	if core.itemCodex ~= nil and not core.itemCodex:IsValid() then
		core.itemCodex = nil
	end
 
	if core.itemHellflower ~= nil and not core.itemHellflower:IsValid() then
		core.itemHellflower = nil
	end
	
	if core.itemSheepstick ~= nil and not core.itemSheepstick:IsValid() then
		core.itemSheepstick = nil
	end
	
	if bUpdated then
		--only update if we need to
		if core.itemSteamboots and  core.itemHellflower and core.itemSheepstick then
			return
		end
	
		local inventory = core.unitSelf:GetInventory(true)
		for slot = 1, 12, 1 do
			local curItem = inventory[slot]
			if curItem then
				if core.itemBottle == nil and curItem:GetName() == "Item_Bottle" then
					core.itemBottle = core.WrapInTable(curItem)
				elseif core.itemCodex == nil and curItem:GetName() == "Item_Nuke" then
					core.itemCodex = core.WrapInTable(curItem)
				elseif core.itemHellflower == nil and curItem:GetName() == "Item_Silence" then
					core.itemHellflower = core.WrapInTable(curItem)
				elseif core.itemSheepstick == nil and curItem:GetName() == "Item_Morph" then
					core.itemSheepstick = core.WrapInTable(curItem)
				end
			end
		end
	end
end

object.FindItemsOld = core.FindItems
core.FindItems = funcFindItemsOverride

----------------------------------------------
--          OnCombatEvent Override          --
----------------------------------------------

function object:oncombateventOverride(EventData)
	self:oncombateventOld(EventData)
	
	local nAddBonus = 0
	
	if EventData.Type == "Ability" then
		if EventData.InflictorName == "Ability_Fade1" then
			nAddBonus = nAddBonus + self.nCullUse
		elseif EventData.InflictorName == "Ability_Fade2" then
			nAddBonus = nAddBonus + self.nBurningShadowsUse
		elseif EventData.InflictorName == "Ability_Fade3" then
			nAddBonus = nAddBonus + self.nDeepShadowsUse
		elseif EventData.InflictorName == "Ability_Fade4" then
			nAddBonus = nAddBonus + self.nReflectionUse
		end
	elseif EventData.Type == "Item" then
		if core.itemCodex ~= nil and EventData.SourceUnit == core.unitSelf:GetUniqueID() and EventData.InflictorName == core.itemCodex:GetName() then
			nAddBonus = nAddBonus + self.nCodexUse
		elseif core.itemHellflower ~= nil and EventData.SourceUnit == core.unitSelf:GetUniqueID() and EventData.InflictorName == core.itemHellflower:GetName() then
			nAddBonus = nAddBonus + self.nHellflowerUse
		elseif core.itemSheepstick ~= nil and EventData.SourceUnit == core.unitSelf:GetUniqueID() and EventData.InflictorName == core.itemSheepstick:GetName() then
			nAddBonus = nAddBonus + self.nSheepstickUse
		end
	end
	
	if nAddBonus > 0 then
		core.DecayBonus(self)
		core.nHarassBonus = core.nHarassBonus + nAddBonus
	end
end

object.oncombateventOld = object.oncombatevent
object.oncombatevent = object.oncombateventOverride

----------------------------------------------------
--          CustomHarassUtility Override          --
----------------------------------------------------

local function CustomHarassUtilityFnOverride(hero)
	local nUtility = 0
	
	if skills.abilCull:CanActivate() then
		nUtility = nUtility + object.nCullUp
	end
	
	if skills.abilBurningShadows:CanActivate() then
		nUtility = nUtility + object.nBurningShadowsUp
	end
	
	if skills.abilDeepShadows:CanActivate() then
		nUtility = nUtility + object.nDeepShadowsUp
	end
	
	if skills.abilReflection:CanActivate() then
		nUtility = nUtility + object.nReflectionUp
	end
	
	if object.itemCodex and object.itemCodex:CanActivate() then
		nUtility = nUtility + object.nCodexUp
	end 
	
	if object.itemHellflower and object.itemHellflower:CanActivate() then
		nUtility = nUtility + object.nHellflowerUp
	end
	
	if object.itemSheepstick and object.itemSheepstick:CanActivate() then
		nUtility = nUtility + object.nSheepstickUp
	end
	
	return nUtility
end

behaviorLib.CustomHarassUtility = CustomHarassUtilityFnOverride   

------------------------------------
--          Bottle Logic          --
------------------------------------

-- Returns whether or not to use the powerup
local function useBottlePowerup(itemBottle, nDistanceTargetSq)
	local sPowerup = itemBottle:GetActiveModifierKey()

	if sPowerup == "bottle_damage" then
		return true
	elseif sPowerup == "bottle_illusion" then
		return true
	elseif sPowerup == "bottle_movespeed" then
		return true
	elseif sPowerup == "bottle_regen" then
		return false
	elseif sPowerup == "bottle_stealth" then
		if nDistanceTargetSq > (700 * 700) then
			return true
		end
	end
	
	return false
end

-- Returns the number of charges in the bottle
local function getBottleCharges(itemBottle)
	local sModifierKey = itemBottle:GetActiveModifierKey()

	if sModifierKey == "bottle_empty" then
		return 0
	elseif sModifierKey == "bottle_1" then
		return 1
	elseif sModifierKey == "bottle_2" then
		return 2
	elseif sModifierKey == "" then
		return 3
	-- Bottle has a rune in it
	else
		return 4
	end
end

--------------------------------------
--          Illusion Logic          --
--------------------------------------

-- Returns a table of all Illusions that the bot controls
local function updateIllusions(botBrain)
	local playerSelf = core.unitSelf:GetOwnerPlayer()
	local tAllyHeroes = HoN.GetHeroes(core.myTeam)
	object.tIllusions = {}
	for nUID, unitHero in pairs(tAllyHeroes) do
		if core.teamBotBrain.tAllyHeroes[nUID] == nil then
			if unitHero:GetOwnerPlayer() == playerSelf then
				tinsert(object.tIllusions, unitHero)
			end
		end
	end

	return
end

-- Order all illusions to move to a position
local function moveIllusions(botBrain, vecPosition)
	if #object.tIllusions > 0 then
		for _, unitIllusion in pairs(object.tIllusions) do
			if Vector3.Distance2DSq(unitIllusion:GetPosition(), vecPosition) > (100 * 100) then
				core.OrderMoveToPos(self, unitIllusion, vecPosition)
			end
		end
	end

	return
end

-- Order all illusions to attack the target
local function harassHeroIllusions(botBrain, unitTarget)
	if #object.tIllusions > 0 then
		for _, unitIllusion in pairs(object.tIllusions) do
			core.OrderAttack(botBrain, unitIllusion, unitTarget)
		end
	end

	return
end

----------------------------------
--          Cull Logic          --
----------------------------------

-- Returns the radius of Cull
local function getCullRadius()
	return 300
end

---------------------------------------------
--          Burning Shadows Logic          --
---------------------------------------------

-- Retruns the best direction to cast Burning Shadows at the target from the bots current position
local function getBurningShadowsCastDirection(unitTarget)
	local vecTargetPosition = unitTarget:GetPosition()
	local vecDirection = nil
	
	if unitTarget.bIsMemoryUnit then
		local vecTargetHeading = Vector3.Normalize(unitTarget.storedPosition - unitTarget.lastStoredPosition)
		if vecTargetHeading then
			vecDirection = Vector3.Normalize(vecTargetPosition + vecTargetHeading * 75 - core.unitSelf:GetPosition())
		end
	end
	
	return vecDirection
end

-- Returns the total range of Burning Shadows
local function getBurningShadowsTotalRange()
	return 800
end

------------------------------------------
--          Deep Shadows Logic          --
------------------------------------------

-- Returns the best location to place Deep Shadows when retreating
local function getDeepShadowsRetreatPosition()
	local unitSelf = core.unitSelf
	local vecDeepShadowsPosition = nil
	
	if unitSelf.bIsMemoryUnit then
		local vecMovementDirection = Vector3.Normalize(unitSelf.storredPosition - unitSelf.lastStoredPosition)
		if vecMovementDirection then
			vecDeepShadowsPosition = unitSelf:GetPosition() + vecMovementDirection * 350
		end
	else
		vecDeepShadowsPosition = unitSelf:GetPosition()
	end

	return vecDeepShadowsPosition
end

-- Returns the Radius of Deep Shadows
local function getDeepShadowsRadius()
	return 300
end

----------------------------------------
--          Reflection Logic          --
----------------------------------------

-- Returns the mana needed to perform a Reflection -> Burning Shadows -> Cull combo
local function getComboMana()
	return skills.abilCull:GetManaCost() + skills.abilBurningShadows:GetManaCost() + skills.abilReflection:GetManaCost()
end

local function getReflectionDamage(nSkillLevel)
	if nSkillLevel == 1 then
		return 225
	elseif nSkillLevel == 2 then
		return 375
	elseif  nSkillLevel == 3 then
		return 525
	end

	return nil
end

---------------------------------------
--          Harass Behavior          --
---------------------------------------

local function HarassHeroExecuteOverride(botBrain)
	
	local unitTarget = behaviorLib.heroTarget
	if unitTarget == nil then
		return object.harassExecuteOld(botBrain)
	end
	
	local unitSelf = core.unitSelf
	local vecMyPosition = unitSelf:GetPosition()
	
	local vecTargetPosition = unitTarget:GetPosition()
	local nTargetDistanceSq = Vector3.Distance2DSq(vecMyPosition, vecTargetPosition)
	local bCanSeeTarget = core.CanSeeUnit(botBrain, unitTarget)
	local bTargetDisabled = unitTarget:IsStunned() or unitTarget:IsSilenced()
	
	local nLastHarassUtility = behaviorLib.lastHarassUtil
	local bActionTaken = false
	
	-- Stop the bot from trying to harass heroes while dead
	if not bActionTaken and not unitSelf:IsAlive() then
		bActionTaken = true
	end
	
	-- Illusions
	harassHeroIllusions(botBrain, unitTarget)

	-- Don't cast spells or use items to break stealth from Reflection
	if unitSelf:HasState("State_Fade_Ability4_Stealth") then
		bActionTaken = core.OrderAttackClamp(botBrain, unitSelf, unitTarget)
	end
	
	-- Bottle
	if not bActionTaken then
		local itemBottle = core.itemBottle
		if itemBottle then
			if useBottlePowerup(itemBottle, nTargetDistanceSq) then
				-- Use if the bot has an offensive rune bottled
				bActionTaken = core.OrderItemClamp(botBrain, unitSelf, itemBottle)
			elseif getBottleCharges(itemBottle) > 0 and not unitSelf:HasState("State_Bottle") then
				-- Use if we need mana and it is safe to drink
				local nCurTimeMS = HoN.GetGameTime()
				if unitSelf:GetManaPercent() < .2 and (not (eventsLib.recentDotTime > nCurTimeMS) or not (#eventsLib.incomingProjectiles["all"] > 0)) then
					bActionTaken = core.OrderItemClamp(botBrain, unitSelf, itemBottle)
				end
			end
		end
	end
	
	-- Reflection
	if not bActionTaken then
		local abilReflection = skills.abilReflection
		if abilReflection:CanActivate() and nLastHarassUtility > object.nReflectionThreshold then
			if unitSelf:GetMana() < getComboMana() and bCanSeeTarget then
				-- If the bot does not have combo mana, then check if just Reflection will get the kill
				local nTargetMagicEHP = unitTarget:GetHealth() / (1 - unitTarget:GetMagicResistance())
				if nTargetMagicEHP <= getReflectionDamage(abilReflection:GetLevel()) then
					bActionTaken = core.OrderAbility(botBrain, abilReflection)
				end
			else
				-- If the bot has mana for a combo then use it
				bActionTaken = core.OrderAbility(botBrain, abilReflection)
			end
		end
	end

	-- Hellflower
	if not bActionTaken then
		local itemHellflower = core.itemHellflower
		if itemHellflower and itemHellflower:CanActivate() and not bTargetDisabled and bCanSeeTarget and nLastHarassUtility > object.nHellflowerThreshold then
			local nRange = itemHellflower:GetRange()
			if nTargetDistanceSq < (nRange * nRange) then
				bActionTaken = core.OrderItemEntityClamp(botBrain, unitSelf, itemHellflower, unitTarget)
			end
		end
	end

	-- Burning Shadows
	if not bActionTaken then
		local abilBurningShadows = skills.abilBurningShadows
		if abilBurningShadows:CanActivate() and not unitTarget:IsStunned() and nLastHarassUtility > object.nBurningShadowsThreshold then
			local nTotalRange = getBurningShadowsTotalRange()
			if nTargetDistanceSq < ((nTotalRange - 40) * (nTotalRange - 40)) then
				local nCastRange = abilBurningShadows:GetRange()
				if nTargetDistanceSq > (nCastRange * nCastRange) then
					local vecTargetDirection = getBurningShadowsCastDirection(unitTarget)
					-- If the enemy is out of cast range, then predict their movement and cast there
					if vecTargetDirection then
						bActionTaken = core.OrderAbilityPosition(botBrain, abilBurningShadows, vecMyPosition + vecTargetDirection * 500)
					end
				else
					-- If the target is inside cast range then cast on target
					bActionTaken = core.OrderAbilityEntity(botBrain, abilBurningShadows, unitTarget)
				end
			end
		end
	end
	
	-- Cull
	if not bActionTaken then
		local abilCull = skills.abilCull
		if abilCull:CanActivate() and nLastHarassUtility > object.nCullThreshold then
			local nRadius = getCullRadius() - 20
			if nTargetDistanceSq < (nRadius * nRadius) then
				bActionTaken = core.OrderAbility(botBrain, abilCull)
			end
		end
	end
	
	-- Codex
	if not bActionTaken then
		local itemCodex = core.itemCodex
		if itemCodex and itemCodex:CanActivate() and bCanSeeTarget and nLastHarassUtility > object.nCodexThreshold then
			if nTargetDistanceSq <= (250 * 250) then
				-- If the enemy is in melee range, only use codex if we can't kill them with 2 or less auto attacks
				local nTargetPhysicalEHP = unitTarget:GetHealth() / (1 - unitTarget:GetPhysicalResistance())
				if nTargetPhysicalEHP > (core.GetFinalAttackDamageAverage(unitSelf) * 2) then
					bActionTaken = core.OrderItemEntityClamp(botBrain, unitSelf, itemCodex, unitTarget)
				end
			else
				bActionTaken = core.OrderItemEntityClamp(botBrain, unitSelf, itemCodex, unitTarget)
			end
		end
	end
	
	-- Sheepstick
	if not bActionTaken then
		local itemSheepstick = core.itemSheepstick
		if itemSheepstick and itemSheepstick:CanActivate() and not bTargetDisabled and bCanSeeTarget and nLastHarassUtility > object.nSheepstickThreshold then
			local nRange = itemSheepstick:GetRange()
			if nTargetDistanceSq < (nRange * nRange) then
				bActionTaken = core.OrderItemEntityClamp(botBrain, unitSelf, itemSheepstick, unitTarget)
			end
		end
	end
	
	-- Deep Shadows
	if not bActionTaken then
		local abilDeepShadows = skills.abilDeepShadows
		if abilDeepShadows:CanActivate() and nLastHarassUtility > object.nDeepShadowsThreshold then
			local nRange = abilDeepShadows:GetRange()
			local nRadius = getDeepShadowsRadius() - 30
			local nTotalRange = nRange + nRadius
			if nTargetDistanceSq < (nTotalRange * nTotalRange) then
				local vecTargetDirection = Vector3.Normalize(vecTargetPosition - vecMyPosition)
				if vecTargetDirection then
					-- If the enemy is in range cast behind them, otherwise cast at max range
					nRange = nRange - 80
					if nTargetDistanceSq < (nRange * nRange) then
						bActionTaken = core.OrderAbilityPosition(botBrain, abilDeepShadows, vecTargetPosition + vecTargetDirection * 80)
					else
						bActionTaken = core.OrderAbilityPosition(botBrain, abilDeepShadows, vecMyPosition + vecTargetDirection * (nRange + 80))
					end
				end
			end
		end
	end

	if not bActionTaken then
		return object.harassExecuteOld(botBrain)
	end
end

object.harassExecuteOld = behaviorLib.HarassHeroBehavior["Execute"]
behaviorLib.HarassHeroBehavior["Execute"] = HarassHeroExecuteOverride

--------------------------------------------------
--          RetreatFromThreat Override          --
--------------------------------------------------

local function funcRetreatFromThreatExecuteOverride(botBrain)
	local bActionTaken = false
	local unitSelf = core.unitSelf
	local nNearbyEnemyHeroes = core.NumberElements(core.localUnits["EnemyHeroes"])

	-- Use Deep Shadows to retreat
	if not bActionTaken then
		local abilDeepShadows = skills.abilDeepShadows
		if abilDeepShadows:CanActivate() and not unitSelf:HasState("State_Fade_Ability4_Stealth") and nNearbyEnemyHeroes > 0 and unitSelf:GetHealthPercent() < .70 then
			local vecPosition = getDeepShadowsRetreatPosition()
			if vecPosition then
				bActionTaken = core.OrderAbilityPosition(botBrain, abilDeepShadows, vecPosition)
			end
		end
	end
	
	-- Use Reflection to retreat
	if not bActionTaken then
		local abilReflection = skills.abilReflection
		if abilReflection:CanActivate() and nNearbyEnemyHeroes > 0 and unitSelf:GetHealthPercent() < .55 then
			bActionTaken = core.OrderAbility(botBrain, abilReflection)
		end
	end
	
	if not bActionTaken then
		return object.RetreatFromThreatExecuteOld(botBrain)
	end
end

object.RetreatFromThreatExecuteOld = behaviorLib.RetreatFromThreatExecute
behaviorLib.RetreatFromThreatBehavior["Execute"] = funcRetreatFromThreatExecuteOverride

-------------------------------------------------
--          HealAtWellExecute Overide          --
-------------------------------------------------

local function HealAtWellOveride(botBrain)
	local bActionTaken = false
	local unitSelf = core.unitSelf
	local abilDeepShadows = skills.abilDeepShadows
	
	-- Use Deep Shadows on way to well
	if not bActionTaken then
		local abilDeepShadows = skills.abilDeepShadows
		if abilDeepShadows:CanActivate() and not unitSelf:HasState("State_Fade_Ability4_Stealth") then
			local unitAllyWell = core.allyWell
			if unitAllyWell then
				local nWellDistanceSq = Vector3.Distance2DSq(unitSelf:GetPosition(), unitAllyWell:GetPosition())
				if nWellDistanceSq > (1000 * 1000) then
					local vecPosition = getDeepShadowsRetreatPosition()
					if vecPosition then
						bActionTaken = core.OrderAbilityPosition(botBrain, abilDeepShadows, vecPosition)
					end
				end
			end
		end
	end
 
	-- Use Bottle at well
 	if not bActionTaken then
		local itemBottle = core.itemBottle
		if itemBottle and itemBottle:CanActivate() and not unitSelf:HasState("State_Bottle") then
			local unitAllyWell = core.allyWell
			if unitAllyWell then
				local nWellDistanceSq = Vector3.Distance2DSq(unitSelf:GetPosition(), unitAllyWell:GetPosition())
				if nWellDistanceSq < (400 * 400) then
					bActionTaken = core.OrderItemClamp(botBrain, unitSelf, itemBottle)
				end
			end
		end
	end
 
	if not bActionTaken then
		return object.HealAtWellBehaviorOld(botBrain)
	end
end

object.HealAtWellBehaviorOld = behaviorLib.HealAtWellBehavior["Execute"]
behaviorLib.HealAtWellBehavior["Execute"] = HealAtWellOveride

-------------------------------------------
--          PushExecute Overide          --
-------------------------------------------

-- These are modified from fane_maciuca's Rhapsody Bot
local function AbilityPush(botBrain)
	local bActionTaken = false
	local unitSelf = core.unitSelf
	local nMinimumCreeps = 3
	
	-- Stop the bot from trying to farm creeps if the creeps approach the spot where the bot died
	if not unitSelf:IsAlive() then
		return bActionTaken
	end

	-- Use Cull to farm creeps if the bot has enough mana
	local abilCull = skills.abilCull
	if abilCull:CanActivate() and unitSelf:GetManaPercent() > .45 then
		local tLocalEnemyCreeps = core.localUnits["EnemyCreeps"]
		if core.NumberElements(tLocalEnemyCreeps) > 3 then
			local vecCenter = core.GetGroupCenter(tLocalEnemyCreeps)
			if vecCenter then
				local nDistanceToCenterSq = Vector3.Distance2DSq(unitSelf:GetPosition(), vecCenter)
				-- If the bot is too far away then move closer
				if nDistanceToCenterSq < (75 * 75) then
					bActionTaken = core.OrderAbility(botBrain, abilCull)
				else
					bActionTaken = core.OrderMoveToPosClamp(botBrain, unitSelf, vecCenter)
				end
			end
		end
	end

	return bActionTaken
end

local function PushExecuteOverride(botBrain)
	if not AbilityPush(botBrain) then 
		return object.PushExecuteOld(botBrain)
	end
end

object.PushExecuteOld = behaviorLib.PushBehavior["Execute"]
behaviorLib.PushBehavior["Execute"] = PushExecuteOverride

local function TeamGroupBehaviorOverride(botBrain)
	if not AbilityPush(botBrain) then 
		return object.TeamGroupBehaviorOld(botBrain)
	end
end

object.TeamGroupBehaviorOld = behaviorLib.TeamGroupBehavior["Execute"]
behaviorLib.TeamGroupBehavior["Execute"] = TeamGroupBehaviorOverride


----------------------------------------------------
--          AttackCreepsExecute Override          --
----------------------------------------------------

-- Override to use logger's hatchet
local function attackCreepsExecuteOverride(botBrain)
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
		local itemHatchet = core.itemHatchet
		if itemHatchet and itemHatchet:CanActivate() and unitTarget:GetTeam() ~= unitSelf:GetTeam() and string.find(unitTarget:GetTypeName(), "Creep") and core.GetAttackSequenceProgress(unitSelf) ~= "windup" and nDistSq < 600 * 600 then
			bActionTaken = core.OrderItemEntityClamp(botBrain, unitSelf, itemHatchet, unitTarget)
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

behaviorLib.AttackCreepsBehavior["Execute"] = attackCreepsExecuteOverride

-----------------------------------------------
--          UseHealthRegen Override          --
-----------------------------------------------
--
-- Utility: 0 to 40
-- Based on missing health
--
-- Execute: 
-- Use Runes of the Blight, Health Pot, or Bottle to heal
-- Will only use Health Pot or Bottle if it is safe
--

-------- Global Constants & Variables --------
behaviorLib.nBottleHealthUtility = 0
behaviorLib.bUseBottleForHealth = true

-------- Helper Functions --------
local function getSafeDrinkDirection()
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

local function bottleHealthUtilFn(nHealthMissing)
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
local function useHealthRegenUtilityOverride(botBrain)
	StartProfile("Init")
	local bDebugLines = false

	local nUtility = 0
	local nHealthPotUtility = 0
	local nBlightsUtility = 0
	local nBottleUtility = 0

	local unitSelf = core.unitSelf
	local nHealthMissing = unitSelf:GetMaxHealth() - unitSelf:GetHealth()
	local tInventory = unitSelf:GetInventory()
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
		local itemBottle = core.itemBottle
		if itemBottle and not unitSelf:HasState("State_Bottle") and itemBottle:GetActiveModifierKey() ~= "bottle_empty" then
			nBottleUtility = bottleHealthUtilFn(nHealthMissing)
		end
	end
	StopProfile()

	StartProfile("End")
	nUtility = max(nHealthPotUtility, nBlightsUtility, nBottleUtility)
	nUtility = Clamp(nUtility, 0, 100)

	behaviorLib.nHealthPotUtility = nHealthPotUtility
	behaviorLib.nBlightsUtility = nBlightsUtility
	behaviorLib.nBottleHealthUtility = nBottleUtility

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

local function useHealthRegenExecuteOverride(botBrain)
	local bDebugLines = false
	local bActionTaken = false
	local unitSelf = core.unitSelf
	local vecSelfPos = unitSelf:GetPosition()
	local tInventory = unitSelf:GetInventory()
	local nMaxUtility = max(behaviorLib.nBlightsUtility, behaviorLib.nHealthPotUtility, behaviorLib.nBottleHealthUtility)

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
			local vecRetreatDirection = getSafeDrinkDirection()
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
		local itemBottle = core.itemBottle
		if itemBottle and itemBottle:CanActivate() and not unitSelf:HasState("State_Bottle") and itemBottle:GetActiveModifierKey() ~= "bottle_empty" then
			local vecRetreatDirection = getSafeDrinkDirection()
			-- Check if it is safe to drink
			if vecRetreatDirection then
				bActionTaken = core.OrderMoveToPosClamp(botBrain, unitSelf, vecSelfPos + vecRetreatDirection * core.moveVecMultiplier, false)
			else
				bActionTaken = core.OrderItemClamp(botBrain, unitSelf, itemBottle)
			end
		end
	end

	return bActionTaken
end

behaviorLib.UseHealthRegenBehavior["Utility"] = useHealthRegenUtilityOverride
behaviorLib.UseHealthRegenBehavior["Execute"] = useHealthRegenExecuteOverride

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
behaviorLib.nBottleManaUtility = 0
behaviorLib.bUseBottleForMana = true

-------- Helper Functions --------
local function bottleManaUtilFn(nManaMissing)
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
local function useManaRegenUtility(botBrain)
	StartProfile("Init")
	local nUtility = 0
	local nBottleUtility = 0

	local unitSelf = core.unitSelf
	local nManaMissing = unitSelf:GetMaxMana() - unitSelf:GetMana()
	StopProfile()

	StartProfile("Bottle")
	if behaviorLib.bUseBottleForMana then
		local itemBottle = core.itemBottle
		if itemBottle and not unitSelf:HasState("State_Bottle") and itemBottle:GetActiveModifierKey() ~= "bottle_empty" then
			nBottleUtility = bottleManaUtilFn(nManaMissing)
		end
	end
	StopProfile()

	StartProfile("End")
	nUtility = nBottleUtility
	nUtility = Clamp(nUtility, 0, 100)

	behaviorLib.nBottleManaUtility = nBottleUtility

	if botBrain.bDebugUtility == true and nUtility ~= 0 then
		BotEcho(format("  UseManaRegenUtility: %g", nUtility))
	end
	StopProfile()

	return nUtility
end

local function useManaRegenExecute(botBrain)
	local bActionTaken = false
	local unitSelf = core.unitSelf
	local vecSelfPos = unitSelf:GetPosition()
	local tInventory = unitSelf:GetInventory()

	-- Use Bottle to regen mana
	if not bActionTaken  then
		local itemBottle = core.itemBottle
		if itemBottle and itemBottle:CanActivate() and not unitSelf:HasState("State_Bottle") and itemBottle:GetActiveModifierKey() ~= "bottle_empty" then
			local vecRetreatDirection = getSafeDrinkDirection()
			-- Check if it is safe to drink
			if vecRetreatDirection then
				bActionTaken = core.OrderMoveToPosClamp(botBrain, unitSelf, vecSelfPos + vecRetreatDirection * core.moveVecMultiplier, false)
			else
				bActionTaken = core.OrderItemClamp(botBrain, unitSelf, itemBottle)
			end
		end
	end

	return bActionTaken
end

behaviorLib.UseManaRegenBehavior = {}
behaviorLib.UseManaRegenBehavior["Utility"] = useManaRegenUtility
behaviorLib.UseManaRegenBehavior["Execute"] = useManaRegenExecute
behaviorLib.UseManaRegenBehavior["Name"] = "UseManaRegen"
tinsert(behaviorLib.tBehaviors, behaviorLib.UseManaRegenBehavior)

----------------------------------------
--          OnThink Override          --
----------------------------------------

function object:onthinkOverride(tGameVariables)
	self:onthinkOld(tGameVariables)

	updateIllusions(self)
	if behaviorLib.currentBehavior ~= "HarassHero" then
		-- Don't move illusions if they are attacking something
		moveIllusions(self, core.unitSelf:GetPosition())
	end
end

object.onthinkOld = object.onthink
object.onthink = object.onthinkOverride

BotEcho(object:GetName()..' finished loading Fayde_main')
