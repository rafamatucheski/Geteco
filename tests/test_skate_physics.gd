extends SceneTree
const BOARD := preload("res://activities/skate/SkateBody.gd")
const PARK := preload("res://activities/skate/SkatePark.gd")
const LAYOUT := preload("res://activities/skate/SkateParkLayout.gd")
const POSE := preload("res://activities/skate/SkatePose.gd")
const CONTROLLER := preload("res://activities/skate/Skate.gd")
var checks := 0
var failed := 0
var landed := 0
var damage := 0.0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failed += 1
	print("SKATE ", "PASS " if ok else "FAIL ", title)
func frames(count: int) -> void:
	for i in count: await physics_frame
func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, .2, 60)
	floor_shape.shape = box
	floor_shape.position.y = -.1
	floor_body.add_child(floor_shape)
	scene.add_child(floor_body)
	var park := PARK.new()
	scene.add_child(park)
	var board := BOARD.new()
	board.position = Vector3(0, .02, 0)
	scene.add_child(board)
	board.bailed.connect(func(amount): damage += amount)
	board.trick_landed.connect(func(points, _title): landed += points)
	await frames(20)
	check(board.is_on_floor(), "quatro rodas apoiadas no piso real")
	check(board.deck.wheels.size() == 4, "shape tem quatro rodas e trucks")
	var deck_art = board.deck.get_node("DeckTrucksAndHubs")
	var colors: PackedColorArray = deck_art.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	check(Color("bca17d") in colors and deck_art.material_override.vertex_color_is_srgb and board.deck.get_node("GripTape").material_override.albedo_texture != null, "lixa granulada e madeira mantêm acabamento próprio")
	var bounds: AABB = board.deck.get_node("GripTape").mesh.get_aabb()
	check(bounds.size.x > .20 and bounds.size.x < .22 and absf(bounds.size.z - .8128) < .002, "shape tem proporções street de 8,5 por 32 polegadas")
	var wheel_bounds: AABB = board.deck.wheels[0].get_child(0).mesh.get_aabb()
	check(absf(wheel_bounds.size.y - .054) < .002, "rodas têm 54 mm de diâmetro")
	board.riding = true
	board.drive(1, 0, false)
	await frames(100)
	check(board.speed > 2 and board.position.z < -2, "remadas aceleram e deslocam com colisão")
	board.pushing = true
	board.push_phase = .42
	var targets := POSE.feet(board)
	check(is_equal_approx(targets[0].y, .10) and is_zero_approx(targets[1].y) and targets[1].x > .2, "um pé permanece no shape e outro empurra o chão")
	board.drive(0, 0, true)
	await frames(90)
	check(board.speed < .2, "freio para o skate")
	check(not board.start_trick("flip"), "flip não gira atravessando o chão")
	check(board.ollie(), "ollie lança do piso")
	await frames(8)
	check(board.position.y > .4 and board.airborne, "salto tem altura e gravidade reais")
	check(board.start_trick("flip"), "kickflip começa no ar")
	await frames(60)
	check(board.riding and landed == 100, "flip completado antes do pouso pontua")
	check(board.ollie(), "segundo salto após pouso")
	await frames(26)
	check(board.start_trick("flip"), "flip tardio permitido com risco")
	await frames(40)
	check(not board.riding and damage > 0, "manobra incompleta derruba e aplica dano")
	var query := PhysicsRayQueryParameters3D.create(LAYOUT.CENTER + Vector3.UP * 3, LAYOUT.CENTER - Vector3.UP * 4, 1)
	var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
	print("SKATE_BOWL_DIAGNOSTIC ", hit)
	check(not hit.is_empty() and hit.position.y < -1.5, "bowl é fisicamente rebaixado")
	for obstacle in [{"at": Vector2(64, 87), "height": .60, "name": "bank"}, {"at": Vector2(72.6, 99.3), "height": .515, "name": "ledge"}, {"at": Vector2(72.65, 91), "height": .5325, "name": "corrimão"}, {"at": Vector2(62, 101.5), "height": .50, "name": "banco"}]:
		query.from = Vector3(obstacle.at.x, 2, obstacle.at.y)
		query.to = Vector3(obstacle.at.x, -4, obstacle.at.y)
		hit = scene.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and absf(hit.position.y - obstacle.height) < .01, "%s ocupa espaço físico" % obstacle.name)
	for i in 12:
		var angle := TAU * i / 12.0
		var point := Vector2(LAYOUT.CENTER.x, LAYOUT.CENTER.z) + Vector2(cos(angle), sin(angle)) * LAYOUT.RADII * .8
		query.from = Vector3(point.x, 2, point.y)
		query.to = Vector3(point.x, -4, point.y)
		hit = scene.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and absf(hit.position.y - LAYOUT.height_at(point)) < .04, "curva visual e colisão concordam %d" % i)
	check(CONTROLLER.validate_snapshot({"owned": true, "best": 175.0}), "save JSON preserva posse e recorde")
	check(not CONTROLLER.validate_snapshot({"owned": 1, "best": -1}), "save inválido rejeitado")
	var state = preload("res://runtime/GameState.gd").new()
	state.world_state.skate = {"owned": true, "best": 175}
	var store = preload("res://runtime/SaveStore.gd").new()
	store.path = "res://evidence/skate-save-test-%d.json" % Time.get_ticks_usec()
	check(store.save(state) == OK, "save real isolado grava posse e recorde")
	var restored = preload("res://runtime/GameState.gd").new()
	check(store.load_into(restored).get("ok", false) and restored.world_state.get("skate", {}).get("best") == 175 and restored.world_state.get("skate", {}).get("owned") == true, "save real recarrega posse e recorde")
	print("SKATE_RESULT checks=", checks, " failures=", failed)
	scene.free()
	quit(1 if failed else 0)
