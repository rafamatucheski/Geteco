extends SceneTree
## Porta do PaintedFacadeKit: só abre ao alcance do braço, abre e fecha devagar,
## espera antes de fechar, e o vão bate com a posição da porta pintada.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func wait_seconds(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until: await physics_frame

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var collisions := Node3D.new()
	stage.add_child(collisions)
	for style in PaintedFacadeKit.STYLES:
		var rect: Array = PaintedFacadeKit.style_data(style).get("doors", {}).get("front", [])
		check(rect.size() == 4 and rect[2] > rect[0] and rect[3] > rect[1], style + ": style.json has a front doorway")
		check(rect.size() == 4 and rect[3] > 0.8 and rect[1] > 0.4, style + ": doorway sits on the ground floor")
	# Prédio sem interior: nenhuma porta reage (antes abria para um corredor falso).
	var shut := PaintedFacadeKit.build(stage, "tijolo-londrino", Vector3(12, 7, 8), collisions)
	shut.position.x = 40.0
	check(shut.find_children("DoorZone", "", true, false).is_empty(), "building without interior: no door reacts to the player")
	# Prédio com interior: só a entrada de verdade (walk_in_x) abre.
	var entrance_x := PaintedFacadeKit.nearest_door_x("tijolo-vermelho", 6.0, 0.0)
	var built := PaintedFacadeKit.build(stage, "tijolo-vermelho", Vector3(6, 7, 8), collisions, entrance_x)
	check(built.find_children("DoorZone", "", true, false).size() == 1, "only the real entrance opens (front walk-in), back door stays shut")
	var door = built.get_node("Doorway_front/Door")
	var doorway: Node3D = built.get_node("Doorway_front")
	var player := CharacterBody3D.new()
	player.collision_layer = PaintedFacadeKit.PLAYER_LAYER
	player.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.shape.radius = 0.3
	shape.shape.height = 1.8
	player.add_child(shape)
	stage.add_child(player)
	var center: Vector3 = doorway.global_position + doorway.global_basis.x * 0.5
	player.global_position = center + Vector3(0, 0.9, 2.0)
	await wait_seconds(0.5)
	check(is_zero_approx(door.open_amount), "door stays shut with the player 2 m away")
	player.global_position = center + Vector3(0, 0.9, 0.55)
	await wait_seconds(0.4)
	var early: float = door.open_amount
	check(early > 0.05 and early < 0.6, "door starts opening, not snapping open (0.4 s -> %.2f)" % early)
	await wait_seconds(1.8)
	check(door.open_amount > 0.95, "door fully open after ~2 s")
	check(absf(door.hinge.rotation.y - deg_to_rad(80.0)) < 0.05, "door swings 80 degrees inward")
	player.global_position = center + Vector3(0, 0.9, 4.0)
	await wait_seconds(0.8)
	check(door.open_amount > 0.95, "door waits before closing")
	await wait_seconds(1.6)
	var closing: float = door.open_amount
	check(closing > 0.05 and closing < 0.95, "door closes slowly (%.2f midway)" % closing)
	await wait_seconds(2.2)
	check(is_zero_approx(door.open_amount), "door back on the frame")
	print("PAINTED_FACADE_DOOR checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
