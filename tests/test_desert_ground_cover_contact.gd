extends "res://tests/tank_control/test_heavy_impacts.gd"
## Moitas grandes e pedras do chão povoado do deserto são acertadas pelo carro, não atravessadas.
const COVER := preload("res://world/desert/DesertGroundCover.gd")

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	street = Street.new()
	world.add_child(street)
	var chunk := Node3D.new()
	world.add_child(chunk)
	var rect := Rect2(-400, -800, 48, 48)
	var state := COVER.begin(rect)
	COVER.step(chunk, rect, state, func(_p): return 0.0, func(_p, _r): return true, INF)
	var items := FRAGILE.query(Vector3(rect.get_center().x, 0, rect.get_center().y), 40)
	var shrubs := items.filter(func(item): return item.kind == "desert_shrub")
	var stones := items.filter(func(item): return item.kind == "desert_stone")
	check(not shrubs.is_empty(), "large shrubs are registered as car contacts")
	check(not stones.is_empty(), "loose stones are registered as car contacts")
	for item in [shrubs[0] if not shrubs.is_empty() else null, stones[0] if not stones.is_empty() else null]:
		if item == null: continue
		var count: int = item.multimesh.instance_count
		check(item.index < count, "%s index fits its batch" % item.kind)
		var vehicle := car(1.0)
		vehicle.position = item.point + Vector3(0, 0, 6)
		CRUSH.set_planar(vehicle, Vector3.FORWARD * 20)
		var before := street.get_child_count()
		street._hit_props(vehicle, vehicle.horizontal_velocity, Vector3.FORWARD * 10)
		check(item.state == "down", "%s reacts to a passing car" % item.kind)
		check(street.get_child_count() > before, "%s becomes debris" % item.kind)
		var debris: Array = street.get_children().slice(before)
		for body in debris:
			if body is RigidBody3D: check(body.linear_velocity.length() < 4.0, "%s falls near the car instead of flying" % item.kind)
			# Sem o material da instância a moita virava uma pedra branca ao ser atropelada (19/10).
			for mesh in body.find_children("*", "MeshInstance3D", true, false):
				var material: Material = mesh.material_override
				check(material is StandardMaterial3D and not (material as StandardMaterial3D).albedo_color.is_equal_approx(Color.WHITE), "%s debris keeps its colour (%s)" % [item.kind, material])
		vehicle.free()
	print("registrados em 48x48 m: ", items.size())
	print("DESERT_GROUND_COVER_CONTACT checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
