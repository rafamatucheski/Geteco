extends RefCounted
## A precisão só muda ao atirar. A recuperação usa o relógio de combate, então a pausa
## a congela e trocar de arma não apaga o bloom de uma rajada contínua.
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
	# Mirar estabiliza o atirador; não consegue estreitar o cone físico de chumbos da espingarda.
	if aimed:
		extra *= 0.60
		if int(data.get("pellets", 1)) == 1: base *= 0.75
	return base + extra * float(data.get("recoil_multiplier", 1.0))

func fired(id: String, data: Dictionary, clock: float) -> void:
	var growth := float(data.get("spread_growth", 0.0))
	if growth <= 0.0: return
	_shots[id] = {"time": clock, "bloom": minf(float(data.get("spread_limit", growth)), bloom(id, data, clock) + growth)}
