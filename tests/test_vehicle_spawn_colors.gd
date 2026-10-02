extends SceneTree

const CATALOG := preload("res://runtime/FleetCatalog.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const STATE := preload("res://runtime/FleetState.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAIL ", label)

func run() -> void:
	seed(9282026)
	for id in CATALOG.all():
		var colors: Array = CATALOG.SPAWN_PALETTES.get(id, CATALOG.spec(id).get("colors", []))
		if id in preload("res://runtime/VehicleTwoTone.gd").MODELS:
			colors = preload("res://runtime/VehicleTwoTone.gd").PALETTES
		var previous := CATALOG.default_paint(id)
		for i in 32:
			var chosen := CATALOG.default_paint(id)
			check(chosen.to_html(true) in colors, id + ": paint belongs to palette")
			if colors.size() > 1: check(chosen != previous, id + ": consecutive spawns vary")
			previous = chosen
	check(CATALOG.default_paint("taxi_yellow") == Color("ffc526"), "taxi remains yellow")
	check(CATALOG.default_paint("police_cruiser") == Color.WHITE, "police retains livery")
	check(CATALOG.default_paint("cobra_boss_ironback") == Color("49252d"), "reward retains signature paint")
	check(CATALOG.default_paint("missing_model", Color.CORAL) == Color.CORAL, "unknown model uses fallback")
	var world := Node3D.new()
	root.add_child(world)
	for id in CATALOG.SPAWN_PALETTES:
		var first := VEHICLE.new()
		first.archetype = id
		world.add_child(first)
		first.set_physics_process(false)
		var original := first.paint_color
		var second := VEHICLE.new()
		second.archetype = id
		world.add_child(second)
		second.set_physics_process(false)
		check(second.paint_color != original, id + ": actual vehicles spawn in different colors")
		check(not first._paint.materials.is_empty(), id + ": body materials bound")
		for material in first._paint.materials:
			check(material.albedo_color.is_equal_approx(original), id + ": visible paint isolated from second car")
		var saved := STATE.capture(first, "harbor")
		var restored := VEHICLE.new()
		restored.archetype = id
		restored.paint_color = Color.html(saved.paint)
		world.add_child(restored)
		restored.set_physics_process(false)
		check(restored.paint_color.is_equal_approx(original), id + ": saved/explicit color bypasses random choice")
		first.free()
		second.free()
		restored.free()
	world.free()
	print("VEHICLE_SPAWN_COLORS ", checks, " checks failures=", failures)
	quit(0 if failures.is_empty() else 1)
