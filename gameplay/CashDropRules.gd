extends RefCounted
## One roll per civilian death. Probabilities include the chance of no drop.
static func roll(rng: RandomNumberGenerator) -> int:
	var chance := rng.randi_range(0, 99)
	if chance < 50: return 0
	if chance < 85: return rng.randi_range(5, 30)
	if chance < 95: return rng.randi_range(31, 80)
	if chance < 99: return rng.randi_range(81, 180)
	return rng.randi_range(181, 300)
