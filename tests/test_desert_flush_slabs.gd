extends SceneTree
## Lajes "rentes" do deserto não podem ter quina que segure o carro. O casco do Vehicle é uma caixa apoiada
## em y=0 sem subida de degrau: uma laje sólida com o tampo 1,5 cm acima do chão (pátio do ponto Cobre)
## parava o carro como parede invisível (achado com tests/probe_desert_invisible_walls.gd, 27/10).
## Monta a região do deserto real e arrasta uma caixa do tamanho de um carro, rente ao chão, por cima da laje.
## Uso: "$GODOT" --headless --path . --script res://tests/test_desert_flush_slabs.gd
const REGION := preload("res://world/desert/DesertRegion.gd")
const STOP := preload("res://world/desert/DesertCoachStop.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(120).timeout.connect(func(): push_error("FLUSH_SLABS timeout"); quit(3))
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("FLUSH_SLABS ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func _run() -> void:
	var region: Node3D = REGION.build_region("desert", STOP.POSITION)
	root.add_child(region)
	for frame in 900:
		await physics_frame
		if region.is_streaming_idle(): break
	for frame in 3: await physics_frame
	check(is_instance_valid(region.find_child("CobreCoachStop", true, false)), "ponto Cobre montado pelo streaming do deserto")
	var space := region.get_world_3d().direct_space_state
	var hull := BoxShape3D.new()
	# Só a faixa baixa do casco (até 30 cm): o banco e os postes do abrigo ficam acima ou fora da faixa varrida.
	hull.size = Vector3(4.8, .3, 2.1)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = hull
	query.collision_mask = 7
	# Frente do pátio (z local 2..4, além dos postes em ±1,25), atravessando a laje de ponta a ponta.
	var from := STOP.POSITION + Vector3(-12, .15 + .002, 3)
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.motion = Vector3(24, 0, 0)
	var result := space.cast_motion(query)
	check(result.size() == 2 and result[0] >= 1.0, "casco do carro atravessa o pátio do ponto sem bater em quina (fração livre %.3f)" % (result[0] if result.size() > 0 else -1.0))
	# O jogador e o carro continuam apoiados: o chão do deserto existe sob a laje.
	var ray := PhysicsRayQueryParameters3D.create(STOP.POSITION + Vector3(0, 5, 3), STOP.POSITION + Vector3(0, -5, 3), 7)
	var floor_hit := space.intersect_ray(ray)
	check(not floor_hit.is_empty() and absf(float(floor_hit.position.y)) < .03, "chão físico sob o pátio, rente a y=0")
	region.free()
	print("FLUSH_SLABS_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
