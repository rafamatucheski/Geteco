extends SceneTree
## Recuo da câmera ortográfica diante de prédio alto (26/10/2026): um prédio do grupo exterior_reveal_building
## que passa do plano de corte próximo empurra a câmera para trás no eixo de visão até ficar na frente dela;
## terreno (fora do grupo) não empurra; sem nada no caminho a distância não muda.
## Uso: "$GODOT" --headless --path . --script res://tests/test_building_camera_clearance.gd
const CLEARANCE := preload("res://scripts/camera/BuildingCameraClearance.gd")
const NOMINAL := Vector3(0, 25.30, 25.30)
const VIEW := Vector2(53.0, 30.0)
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	checks += 1
	print("BUILDING_CLEARANCE ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)

func _initialize() -> void:
	run.call_deferred()

func _box(center: Vector3, size: Vector3, building: bool) -> Node3D:
	var root_node := Node3D.new()
	if building: root_node.add_to_group(&"exterior_reveal_building")
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	root_node.add_child(body)
	root_node.position = center
	root.add_child(root_node)
	return root_node

func run() -> void:
	var focus := Vector3(0, .85, 0)
	var back := NOMINAL.normalized()
	var space := root.world_3d.direct_space_state
	var clearance := CLEARANCE.new()
	for frame in 2: await physics_frame
	check(is_equal_approx(clearance.offset_for(space, focus, NOMINAL, VIEW, .1, .2).length(), NOMINAL.length()), "sem prédio a câmera fica na distância normal")
	# Prédio de 30 m, 30 m ao sul do jogador (no pé da tela): o topo fica além da câmera.
	var tower := _box(Vector3(0, 15, 34), Vector3(14, 30, 8), true)
	for frame in 2: await physics_frame
	var deepest := (Vector3(0, 30, 30) - focus).dot(back)
	check(deepest > NOMINAL.length(), "o prédio de teste passa mesmo do plano da câmera (%.1f m > %.1f m)" % [deepest, NOMINAL.length()])
	clearance = CLEARANCE.new()
	var offset := clearance.offset_for(space, focus, NOMINAL, VIEW, .1, .2)
	check(offset.length() >= deepest + .1 and offset.normalized().is_equal_approx(back), "câmera recua no eixo de visão até a frente do prédio (%.1f m)" % offset.length())
	tower.free()
	# Encosta (fora do grupo) no mesmo lugar: continua cortada, a câmera não sai do lugar.
	var hill := _box(Vector3(0, 15, 34), Vector3(14, 30, 8), false)
	for frame in 2: await physics_frame
	clearance = CLEARANCE.new()
	check(is_equal_approx(clearance.offset_for(space, focus, NOMINAL, VIEW, .1, .2).length(), NOMINAL.length()), "terreno alto não empurra a câmera")
	hill.free()
	print("BUILDING_CLEARANCE checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
