extends RefCounted
## Accuracy changes only when firing. Recovery uses the combat clock, so pause
## freezes it and swapping weapons cannot erase a sustained burst's bloom.
var _shots: Dictionary = {}

func clear() -> void:
	_shots.clear()

func bloom(id: String, data: Dictionary, clock: float) -> float:
	var last: Dictionary = _shots.get(id, {})
	if last.is_empty(): return 0.0
	var elapsed := maxf(0.0, clock - float(last.time))
	return maxf(0.0, float(last.bloom) - elapsed * float(data.get("spread_recovery", 0.0)))

func shot_spread(id: String, data: Dictionary, clock: float, speed: float, aimed: bool) -> float:
	var base := float(data.get("spread", 0.0))
	if not data.has("category"): return base
	var moving := float(data.get("move_spread", 0.0)) * clampf(speed / 4.0, 0.0, 1.0)
	var extra := bloom(id, data, clock) + moving
	# Aiming steadies the shooter; it cannot narrow a shotgun's physical pellet cone.
	if aimed:
		extra *= 0.60
		if int(data.get("pellets", 1)) == 1: base *= 0.75
	return base + extra * float(data.get("recoil_multiplier", 1.0))

func fired(id: String, data: Dictionary, clock: float) -> void:
	var growth := float(data.get("spread_growth", 0.0))
	if growth <= 0.0: return
	_shots[id] = {"time": clock, "bloom": minf(float(data.get("spread_limit", growth)), bloom(id, data, clock) + growth)}
