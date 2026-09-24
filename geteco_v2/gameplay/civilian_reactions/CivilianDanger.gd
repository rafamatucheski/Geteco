extends RefCounted
## Memória de perigo e escolha de fuga de UM civil (porte 3D de `characters/PedestrianDanger.gd` do V1).
## Só decide: não move ninguém. Percepção entra por `remember`; a decisão sai de `choose_escape`.
## V1: até 4 ameaças, vida de 12 s, candidatos com raio conferido, pontuação por distância da ameaça e penalidade por
## ficar na linha de tiro. Aqui os candidatos são ângulos em torno do "para longe da ameaça" e três comprimentos.

const MAX_THREATS := 4
const THREAT_LIFE := 12.0
const FIRING_LANE := 4.0            ## m; V1: 42 px
const LENGTHS := [12.0, 6.0, 3.0]   ## m; V1: 150/72/36 px
const ANGLES := [0.0, 35.0, -35.0, 70.0, -70.0, 110.0, -110.0, 150.0, -150.0, 180.0]
const DEDUPE_DISTANCE := 1.0

var threats: Array[Dictionary] = []

func remember(origin: Vector3, end: Vector3) -> void:
	origin.y = 0.0
	end.y = 0.0
	for threat in threats:
		# Rajada automática repete a mesma origem a cada disparo: renova em vez de empilhar.
		if threat.origin.distance_to(origin) < DEDUPE_DISTANCE:
			threat.end = end
			threat.age = 0.0
			return
	threats.append({"origin": origin, "end": end, "age": 0.0})
	while threats.size() > MAX_THREATS: threats.pop_front()

func tick(delta: float) -> void:
	for index in range(threats.size() - 1, -1, -1):
		threats[index].age += delta
		if threats[index].age > THREAT_LIFE: threats.remove_at(index)

func is_empty() -> bool: return threats.is_empty()

func danger_at(point: Vector3) -> float:
	var score := 0.0
	for threat in threats:
		var flat: Vector3 = point
		flat.y = 0.0
		score += maxf(0.0, 30.0 - flat.distance_to(threat.origin))
		if _lane_distance(flat, threat.origin, threat.end) < FIRING_LANE: score += 25.0
	return score

func away_from_threats(position: Vector3) -> Vector3:
	var away := Vector3.ZERO
	for threat in threats:
		var offset: Vector3 = position - threat.origin
		offset.y = 0.0
		if offset.length_squared() < 0.01: offset = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
		away += offset.normalized() / maxf(1.0, offset.length() * 0.1)
	if away.length_squared() < 0.0001: return Vector3.ZERO
	return away.normalized()

## Melhor ponto livre (raio de mundo+veículos limpo) ou ZERO. `avoid` exclui a direção que já travou.
func choose_escape(body: Node3D, blocked: Array[Vector3] = []) -> Vector3:
	var away := away_from_threats(body.global_position)
	if away == Vector3.ZERO: return Vector3.ZERO
	var space := body.get_world_3d().direct_space_state
	var from := body.global_position + Vector3.UP * 0.9
	var best := Vector3.ZERO
	var best_score := INF
	for length in LENGTHS:
		for angle in ANGLES:
			var direction := away.rotated(Vector3.UP, deg_to_rad(angle))
			var to: Vector3 = from + direction * length
			var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 4)
			query.exclude = [body.get_rid()]
			if not space.intersect_ray(query).is_empty(): continue
			var point: Vector3 = body.global_position + direction * length
			var score: float = danger_at(point) - length * 0.5
			for bad in blocked:
				if direction.dot(bad) > 0.8: score += 40.0
			if score < best_score:
				best_score = score
				best = point
		if best != Vector3.ZERO: break # comprimento maior livre vence; só encurta se nada coube (V1)
	return best

static func _lane_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var segment := b - a
	var length_squared := segment.length_squared()
	if length_squared < 0.0001: return point.distance_to(a)
	var t := clampf((point - a).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(a + segment * t)
