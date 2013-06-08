-------------------------------------------------
-- ______              _     ______       _    --
-- |  ___|            | |    | ___ \     | |   --
-- | |_ __ _ _   _  __| | ___| |_/ / ___ | |_  --
-- |  _/ _` | | | |/ _` |/ _ \ ___ \/ _ \| __| --
-- | || (_| | |_| | (_| |  __/ |_/ / (_) | |_  --
-- \_| \__,_|\__, |\__,_|\___\____/ \___/ \__| --
--            __/ |                            --
--           |___/        -By: DarkFire-       --
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

-- Fayde
object.heroName = 'Hero_Fade'

-- Item buy order. internal names  
behaviorLib.StartingItems  = {"Item_RunesOfTheBlight", "Item_HealthPotion", "Item_LoggersHatchet", "Item_GuardianRing"}
behaviorLib.LaneItems  = {"Item_Marchers", "Item_Bottle", "Item_LexTalionis 3", "Item_EnhancedMarchers", "Item_Nuke 1"}
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
object.nLexTalionisUp = 10
object.nCodexUp = 22
object.nHellflowerUp = 14
object.nSheepstickUp = 18

-- Bonus agression points that are applied to the bot upon successfully using a skill/item

object.nCullUse = 16
object.nBurningShadowsUse = 18
object.nDeepShadowsUse = 10
object.nReflectionUse = 35
object.nLexTalionisUse = 12
object.nCodexUse = 20
object.nHellflowerUse = 17
object.nSheepstickUse = 21

-- Thresholds of aggression the bot must reach to use these abilities

object.nCullThreshold = 22
object.nBurningShadowsThreshold = 23
object.nDeepShadowsThreshold = 21
object.nReflectionThreshold = 28
object.nLexTalionisThreshold = 22
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
	
	if core.itemLexTalionis ~= nil and not core.itemLexTalionis:IsValid() then
		core.itemLexTalionis = nil
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
		if core.itemBottle and core.itemLexTalionis and core.itemCodex and  core.itemHellflower and core.itemSheepstick then
			return
		end
	
		local inventory = core.unitSelf:GetInventory(true)
		for slot = 1, 12, 1 do
			local curItem = inventory[slot]
			if curItem then
				if core.itemBottle == nil and curItem:GetName() == "Item_Bottle" then
					core.itemBottle = core.WrapInTable(curItem)
				elseif core.itemLexTalionis == nil and curItem:GetName() == "Item_LexTalionis" then
					core.itemLexTalionis = core.WrapInTable(curItem)
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
		if core.itemLexTalionis ~= nil and EventData.SourceUnit == core.unitSelf:GetUniqueID() and EventData.InflictorName == core.itemLexTalionis:GetName() then
			nAddBonus = nAddBonus + self.nLexTalionisUse
		elseif core.itemCodex ~= nil and EventData.SourceUnit == core.unitSelf:GetUniqueID() and EventData.InflictorName == core.itemCodex:GetName() then
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

	if object.itemLexTalionis and object.itemLexTalionis:CanActivate() then
		nUtility = nUtility + object.nLexTalionisUp
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
		local vecMovementDirection = Vector3.Normalize(unitSelf.storedPosition - unitSelf.lastStoredPosition)
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

	-- Lex Talionis
	if not bActionTaken then
		local itemLexTalionis = core.itemLexTalionis
		if itemLexTalionis and itemLexTalionis:CanActivate() and bCanSeeTarget and nLastHarassUtility > object.nLexTalionisThreshold  then
			local nRange = itemLexTalionis:GetRange()
			if nTargetDistanceSq < (nRange * nRange) then
				bActionTaken = core.OrderItemEntityClamp(botBrain, unitSelf, itemLexTalionis, unitTarget)
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
