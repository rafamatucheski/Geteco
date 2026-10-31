extends "res://tests/tank_control/test_heavy_impacts.gd"
## Consultas reais de casco de veículo e de parede. O coletor agregado existente conta
## os lançamentos de obstrução sem sobrescrever um método nativo não virtual de física.
const WORK := preload("res://runtime/StallWorkTrace.gd")
const CAST_LABEL := "street.pre.props.cast"
const MOTION := Vector3(0, 0, -0.5)

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	street = Street.new()
	world.add_child(street)
	await distant_prop_same_cell()
	await prop_in_path()
	await prop_on_another_level()
	await wall_before_prop()
	FRAGILE.cells.clear()
	world.free()
	print("STREET_PROP_QUERY_BUDGET checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func registered_prop(point: Vector3) -> Dictionary:
	var prop := Node3D.new()
	world.add_child(prop)
	prop.global_position = point
	FRAGILE.register_node("lamp", prop, world)
	return FRAGILE.query(point, 0.01)[0]

func query_cast_count(vehicle: Car, motion: Vector3) -> int:
	WORK.start_aggregate()
	street._hit_props(vehicle, Vector3.FORWARD * 12.0, motion)
	var report := WORK.stop_aggregate()
	check(report.dropped_calls == 0, "prop query counters retain every call")
	return int(report.labels.get(CAST_LABEL, {}).get("calls", 0))

func distant_prop_same_cell() -> void:
	FRAGILE.cells.clear()
	var vehicle := car(30.0, Vector3(2.0, 1.4, 4.0), Vector3(4.0, 0.05, 4.0))
	var item := registered_prop(Vector3(7.6, 0.0, 3.0))
	await physics_frame
	check(FRAGILE._key(vehicle.global_position) == FRAGILE._key(item.point),
		"distant decoration and vehicle occupy the same coarse cell")
	check(FRAGILE.query(vehicle.global_position + MOTION * 0.5,
		MOTION.length() * 0.5 + vehicle.half_length + 2.0).has(item),
		"coarse query includes the distant decoration")
	check(query_cast_count(vehicle, MOTION) == 0,
		"decoration outside the actual car path does not request a native obstruction cast")
	check(item.state == "standing", "distant decoration remains intact")
	item.root.get_ref().free()
	vehicle.free()

func prop_in_path() -> void:
	FRAGILE.cells.clear()
	var vehicle := car(30.0, Vector3(2.0, 1.4, 4.0), Vector3(4.0, 0.05, 4.0))
	var item := registered_prop(Vector3(4.0, 0.0, 1.7))
	await physics_frame
	check(query_cast_count(vehicle, MOTION) == 1,
		"decoration in the car path retains its native obstruction cast")
	check(item.state == "down", "a real bumper contact still topples the decoration")
	check(vehicle.health == vehicle.max_health, "heavy vehicle impact behavior is preserved")
	item.root.get_ref().free()
	vehicle.free()

func prop_on_another_level() -> void:
	FRAGILE.cells.clear()
	var vehicle := car(30.0, Vector3(2.0, 1.4, 4.0), Vector3(4.0, 0.05, 4.0))
	var item := registered_prop(Vector3(4.0, 5.0, 1.7))
	await physics_frame
	check(query_cast_count(vehicle, MOTION) == 0,
		"decoration on another level does not request a native obstruction cast")
	check(item.state == "standing", "overpass decoration remains intact")
	item.root.get_ref().free()
	vehicle.free()

func wall_before_prop() -> void:
	FRAGILE.cells.clear()
	var vehicle := car(30.0, Vector3(2.0, 1.4, 4.0), Vector3(4.0, 0.05, 4.0))
	var item := registered_prop(Vector3(4.0, 0.0, -1.0))
	var barrier := solid(Vector3(8.0, 3.0, 0.2), Vector3(4.0, 1.5, 0.0))
	var motion := Vector3.FORWARD * 4.0
	await physics_frame
	var contact := KinematicCollision3D.new()
	check(vehicle.test_move(vehicle.global_transform, motion, contact)
		and contact.get_collider() == barrier, "the native vehicle hull reaches the wall first")
	check(query_cast_count(vehicle, motion) == 1,
		"potential contact behind a wall retains the authoritative obstruction cast")
	check(item.state == "standing", "the wall prevents breaking decoration behind it")
	check(vehicle.global_position.is_equal_approx(Vector3(4.0, 0.05, 4.0)),
		"prop checks do not move the physical vehicle")
	barrier.free()
	item.root.get_ref().free()
	vehicle.free()
