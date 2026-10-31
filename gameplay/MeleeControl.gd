extends RefCounted
## Geometria/tempo de ataque compartilhados. Valores são ajuste inicial de playtest, não FPS medido.
const BUFFER_SECONDS := 0.16
const PROFILES := {
	"knife": {"rate": 1.20, "width": 0.72, "arc": 8.0, "window": 0.065, "move": 0.94},
	"bat": {"rate": 1.25, "width": 1.35, "arc": 24.0, "window": 0.12, "move": 0.72},
	"axe": {"rate": 1.12, "width": 1.05, "arc": 18.0, "window": 0.10, "move": 0.62},
	"katana": {"rate": 1.40, "width": 1.15, "arc": 22.0, "window": 0.10, "move": 0.88},
	"sword_shield": {"rate": 1.40, "width": 1.05, "arc": 18.0, "window": 0.10, "move": 0.90},
}

static func profile(id: String) -> Dictionary:
	return PROFILES.get(id, {"rate": 1.0, "width": 1.3, "arc": 0.0, "window": 0.04, "move": 0.90})

static func rate(id: String, base_interval: float, interval: float) -> float:
	return float(profile(id).rate) * clampf(base_interval / maxf(interval, 0.05), 0.5, 3.0)

static func movement(id: String, age: float, contact: float) -> float:
	var p := profile(id)
	var end := contact + float(p.window)
	# Só a parte comprometida do golpe custa movimento; a recuperação é livre.
	var weight := smoothstep(maxf(0.0, contact - 0.12), contact, age)
	weight *= 1.0 - smoothstep(contact, end, age)
	return lerpf(1.0, float(p.move), weight)

static func target_score(origin: Vector3, direction: Vector3, point: Vector3) -> float:
	var offset := point - origin
	offset.y = 0.0
	return (1.0 - direction.dot(offset.normalized())) * 12.0 + offset.length() * 0.08
