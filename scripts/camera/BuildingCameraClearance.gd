extends RefCounted
## Prédio alto entre a câmera e o jogador entra no plano de corte próximo da câmera ortográfica e aparece
## fatiado: telhado cortado em diagonal, paredes de dentro escuras e janelas acesas soltas (vídeo de
## 26/10/2026). Como em RailwayCameraClearance, a câmera recua no eixo de visão até o prédio ficar na
## frente dela; na ortográfica o enquadramento não muda. Só prédios (grupo exterior_reveal_building):
## terreno alto atrás da câmera continua cortado, senão uma encosta da serra taparia o jogador.
## Raios de trás para frente numa grade sobre a tela, a cada INTERVAL; o primeiro prédio que cada raio
## encontra é o ponto mais recuado dele naquela linha.
const GROUP := &"exterior_reveal_building"
const MARGIN := 3.0
const MAX_EXTRA := 70.0
const INTERVAL := .1
const COLUMNS := 6
const ROWS := 4
## Sobe na hora (nada cortado nem por um quadro) e volta devagar, sem a câmera pulsar entre dois prédios.
const RELEASE_RATE := 20.0
const MAX_SKIPS := 4
## GETECO_BUILDING_CLEARANCE=0 desliga (A/B no mesmo export).
static var enabled := OS.get_environment("GETECO_BUILDING_CLEARANCE") != "0"
var _required := 0.0
var _target := 0.0
var _clock := INTERVAL

func offset_for(space: PhysicsDirectSpaceState3D, focus: Vector3, nominal: Vector3, view: Vector2, near_clip: float, delta := .1) -> Vector3:
	if not enabled or nominal.length_squared() < .01 or space == null: return nominal
	var back := nominal.normalized()
	var distance := nominal.length()
	_clock += maxf(delta, 0.0)
	if _clock >= INTERVAL:
		_clock = 0.0
		_target = _probe(space, focus, back, distance, view, near_clip)
	_required = _target if _target > _required else move_toward(_required, _target, RELEASE_RATE * maxf(delta, 0.0))
	return back * maxf(distance, _required)

func _probe(space: PhysicsDirectSpaceState3D, focus: Vector3, back: Vector3, distance: float, view: Vector2, near_clip: float) -> float:
	var right := Vector3.UP.cross(back).normalized()
	var up := back.cross(right).normalized()
	var need := 0.0
	for column in COLUMNS:
		for row in ROWS:
			var across := right * ((column + .5) / COLUMNS - .5) * view.x + up * ((row + .5) / ROWS - .5) * view.y
			var from := focus + across + back * (distance + MAX_EXTRA)
			var to := focus + across + back * maxf(0.0, distance - near_clip - MARGIN)
			var exclude: Array[RID] = []
			for skip in MAX_SKIPS:
				var query := PhysicsRayQueryParameters3D.create(from, to, 1, exclude)
				var hit := space.intersect_ray(query)
				if hit.is_empty(): break
				if _is_building(hit.collider):
					need = maxf(need, (hit.position - focus).dot(back) + near_clip + MARGIN)
					break
				exclude.append(hit.rid)
	return minf(need, distance + MAX_EXTRA)

static func _is_building(collider: Object) -> bool:
	var node := collider as Node
	for level in 8:
		if node == null: return false
		if node.is_in_group(GROUP): return true
		node = node.get_parent()
	return false
