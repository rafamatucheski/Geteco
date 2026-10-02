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
var revision := 0

func remember(origin: Vector3, end: Vector3) -> void:
	origin.y = 0.0
	end.y = 0.0
	for threat in threats:
		# Rajada automática repete a mesma origem a cada disparo: renova em vez de empilhar.
		if threat.origin.distance_to(origin) < DEDUPE_DISTANCE:
			# Mudar a mira da mesma rajada não reinicia uma busca pendente.
			# A próxima busca/camada de candidatos já usa a linha de tiro renovada.
			threat.end = end
			threat.age = 0.0
			return
	threats.append({"origin": origin, "end": end, "age": 0.0})
	revision += 1
	while threats.size() > MAX_THREATS: threats.pop_front()

func tick(delta: float) -> void:
	for index in range(threats.size() - 1, -1, -1):
		threats[index].age += delta
		if threats[index].age > THREAT_LIFE:
			threats.remove_at(index)
			revision += 1

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

## Compatibilidade síncrona; o diretor usa begin_escape/step_escape com orçamento
## compartilhado. A ordem por score permite parar no primeiro raio livre sem
## mudar a preferência pelo maior comprimento nem o desempate original.
func choose_escape(body: Node3D, blocked: Array[Vector3] = []) -> Vector3:
	var search := begin_escape(body, blocked)
	while not search.done: step_escape(body, search)
	return search.target

func begin_escape(body: Node3D, blocked: Array[Vector3] = []) -> Dictionary:
	return {"origin": body.global_position, "away": away_from_threats(body.global_position),
		"blocked": blocked.duplicate(), "revision": revision, "length_index": 0,
		"candidates": [], "candidate_index": 0, "done": false, "target": Vector3.ZERO,
		"query": PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 1 | 4, [body.get_rid()])}

## Um passo faz NO MÁXIMO um raycast. Rejeições antigas não sobrevivem a uma
## mudança de ameaça ou deslocamento relevante; o raio aceito sempre parte da
## posição atual, mesmo quando a busca atravessa vários frames.
func step_escape(body: Node3D, search: Dictionary) -> int:
	if search.done: return 0
	if search.revision != revision or body.global_position.distance_squared_to(search.origin) > 1.0:
		var restarted := begin_escape(body, search.blocked)
		search.clear()
		search.merge(restarted)
	if search.away == Vector3.ZERO:
		search.done = true
		return 0
	if search.candidates.is_empty(): _rank_candidates(search)
	var candidate: Dictionary = search.candidates[search.candidate_index]
	var point: Vector3 = candidate.point
	var query: PhysicsRayQueryParameters3D = search.query
	query.from = body.global_position + Vector3.UP * 0.9
	query.to = Vector3(point.x, query.from.y, point.z)
	if body.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		search.target = Vector3(point.x, body.global_position.y, point.z)
		search.done = true
		return 1
	search.candidate_index += 1
	if search.candidate_index >= search.candidates.size():
		search.length_index += 1
		search.candidate_index = 0
		search.candidates.clear()
		if search.length_index >= LENGTHS.size(): search.done = true
	return 1

func _rank_candidates(search: Dictionary) -> void:
	var length: float = LENGTHS[search.length_index]
	for index in ANGLES.size():
		var direction: Vector3 = search.away.rotated(Vector3.UP, deg_to_rad(ANGLES[index]))
		var point: Vector3 = search.origin + direction * length
		var score := danger_at(point) - length * 0.5
		for bad in search.blocked:
			if direction.dot(bad) > 0.8: score += 40.0
		search.candidates.append({"point": point, "score": score, "order": index})
	search.candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.order < b.order if a.score == b.score else a.score < b.score)

static func _lane_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var segment := b - a
	var length_squared := segment.length_squared()
	if length_squared < 0.0001: return point.distance_to(a)
	var t := clampf((point - a).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(a + segment * t)
