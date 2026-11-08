class_name ProgressionRules
extends RefCounted
## Pure progression math (level curve, reward calculation). Kept free of side effects so
## the host can compute rewards authoritatively and tests can verify them.

const MAX_LEVEL := 50


## XP required to go from `level` to `level + 1`.
static func xp_to_next(level: int) -> int:
	return 400 + (level - 1) * 175


static func level_for_total_xp(total_xp: int) -> Dictionary:
	var level := 1
	var remaining := total_xp
	while level < MAX_LEVEL and remaining >= xp_to_next(level):
		remaining -= xp_to_next(level)
		level += 1
	return {"level": level, "into_level": remaining, "needed": xp_to_next(level)}


## result (per player) keys: success, extracted, survived, objectives_xp, objectives_currency,
## optional_xp, revives, carried_objective
static func compute_rewards(rewards: RewardData, result: Dictionary) -> Dictionary:
	if rewards == null:
		rewards = RewardData.new()
	var xp := rewards.base_xp + int(result.get("objectives_xp", 0))
	var currency := rewards.base_currency + int(result.get("objectives_currency", 0))
	xp += int(float(result.get("optional_xp", 0)) * rewards.optional_multiplier)
	xp += int(result.get("revives", 0)) * rewards.revive_xp
	if result.get("extracted", false):
		xp += rewards.extraction_xp
		currency += rewards.extraction_currency
	if result.get("survived", false):
		xp += rewards.survival_xp
	if result.get("carried_objective", false):
		xp += rewards.carried_objective_bonus_xp
	if not result.get("success", false):
		xp = int(xp * rewards.failure_multiplier)
		currency = int(currency * rewards.failure_multiplier)
	return {"xp": maxi(0, xp), "currency": maxi(0, currency)}
