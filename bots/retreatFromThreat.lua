
function behaviorLib.RetreatFromThreatUtility(botBrain)
	local unitSelf = core.unitSelf
	local nMaxHealth = unitSelf:GetMaxHealth()
	local nMissingHealthPercent = 1 - unitSelf:GetHealthPercent()
	local nPhysicalResistance = unitSelf:GetPhysicalResistance()

	-- Creep aggro
	local nCreepAggroUtility = 0
	local tEnemyCreeps = core.localUnits["EnemyCreeps"]
	if core.NumberElements(tEnemyCreeps) > 0 then
		local nTotalCreepDamage = 0
		-- Sum of all the damage the creeps that are aggroed to the bot can do
		for _, unitEnemyCreep in pairs(tEnemyCreeps) do
			local unitAggroTarget = unitEnemyCreep:GetAttackTarget()
			if unitAggroTarget and unitAggroTarget:GetUniqueID() == unitSelf:GetUniqueID() then
				nTotalCreepDamage = nTotalCreepDamage + unitEnemyCreep:GetAttackDamageMax()
			end
		end

		if nTotalCreepDamage > 0 then
			-- Percent damage the creeps would do if they hit the bot
			local nCreepDamagePercent = nTotalCreepDamage * (1 - nPhysicalResistance) / nMaxHealth
			nCreepAggroUtility = 35 * (nMissingHealthPercent + nCreepDamagePercent)
		end
	end

	-- Enemy Tower Aggro
	local nTowerAggroUtility = 0
	local tEnemyTowers = core.localUnits["EnemyTowers"]
	if core.NumberElements(tEnemyTowers) > 0 then
		local nTotalTowerDamage = 0
		-- Sum of all the damage the towers that are aggroed to the bot can do
		for _, unitTower in pairs(tEnemyTowers) do
			if unitTower:GetAttackTarget() == core.unitSelf then
				nTotalTowerDamage = nTotalTowerDamage + unitTower:GetAttackDamageMax()
			end
		end

		if nTotalTowerDamage > 0 then
			-- Percent damage the towers would do if they hit the bot
			local nTowerDamagePercent = nTotalTowerDamage * (1 - nPhysicalResistance) / nMaxHealth
			nTowerAggroUtility = 40 * (nMissingHealthPercent + nTowerDamagePercent)
		end
	end

	-- RecentDamage    
	local nRecentDamageUtility = 0
	local nRecentDamage = (eventsLib.recentDamageTwoSec + eventsLib.recentDamageSec) / 2.0
	if nRecentDamage > 0 then
		-- Percentage of health lost in the past two seconds
		local nRecentDamagePercent = (nRecentDamage / nMaxHealth)
		nRecentDamageUtility = Clamp(((100 * nMissingHealthPercent) + (100 * nRecentDamagePercent)), 0, 100)
	end

	-- Local Units Multiplier
	-- Causes the bot to be more likely to retreat the more enemies are present,
	-- and less likely the more allies are present. Bias towards enemy units.
	local nLocalUnitsMultiplier = 1

	for _, unitEnemyTower in pairs(tEnemyTowers) do
		nLocalUnitsMultiplier = nLocalUnitsMultiplier * 1.05
	end

	local tEnemyHeroes = core.localUnits["EnemyHeroes"]
	for _, unitEnemyHero in pairs(tEnemyHeroes) do
		nLocalUnitsMultiplier = nLocalUnitsMultiplier * 1.025
	end

	local tAllyTowers = core.localUnits["AllyTowers"]
	for _, unitAllyTower in pairs(tAllyTowers) do
		nLocalUnitsMultiplier = nLocalUnitsMultiplier * .945
	end

	local tAllyHeroes = core.localUnits["AllyHeroes"]
	for _, unitAllyHero in pairs(tAllyHeroes) do
		nLocalUnitsMultiplier = nLocalUnitsMultiplier * .985
	end

	-- Total
	local nUtility = (nCreepAggroUtility + nTowerAggroUtility + nRecentDamageUtility) * nLocalUnitsMultiplier
	
	behaviorLib.lastRetreatUtil = nUtility

	return nUtility
end