extends RefCounted
## Antecipação pela velocidade física, incluindo ré e derrapagem. Carros em
## outra pista/altura ou que já passaram não provocam fuga.
const HORIZON := 2.0
const MIN_SPEED := 0.05 ## Mesmo limiar do impacto físico: manobra lenta também empurra (e derruba quem fica preso).
const MARGIN := 0.9

static func assess(vehicle: CharacterBody3D, position: Vector3, pedestrian_velocity := Vector3.ZERO) -> Dictionary:
	var motion := Vector3(vehicle.velocity.x, 0, vehicle.velocity.z)
	var speed := motion.length()
	if speed < MIN_SPEED or absf(position.y - vehicle.global_position.y) > 2.5: return {}
	var forward := motion / speed
	var side := Vector3.UP.cross(forward)
	var relative := position - vehicle.global_position
	var width := float(vehicle.get("half_width"))
	var length := float(vehicle.get("half_length"))
	# Projeção do casco na trajetória real: funciona também saindo de lado.
	var across := absf(side.dot(vehicle.global_basis.x)) * width + absf(side.dot(vehicle.global_basis.z)) * length
	var along := absf(forward.dot(vehicle.global_basis.x)) * width + absf(forward.dot(vehicle.global_basis.z)) * length
	var ahead := relative.dot(forward)
	var lateral := relative.dot(side)
	# Na retomada, o pedestre pode caminhar de encontro ao carro. Usar apenas a
	# velocidade do veículo detectava essa aproximação tarde demais.
	var closing := speed - pedestrian_velocity.dot(forward)
	if ahead < -along or (closing <= 0 and ahead > along): return {}
	var impact_time := maxf(0, ahead - along) / maxf(0.05, closing)
	if impact_time > HORIZON: return {}
	var predicted_lateral := lateral + pedestrian_velocity.dot(side) * impact_time
	if absf(lateral) > across + MARGIN and absf(predicted_lateral) > across + MARGIN: return {}
	return {"forward": forward, "side": side, "lateral": lateral, "clearance": across + MARGIN + 0.7,
		"impact_time": impact_time}
