extends SceneTree
## Muscle cars e lowriders (runtime/MuscleFleet.gd): registrados no catálogo, cena assada, motor
## completo RWD, folhas de porta prontas sem recorte, cabine declarada, desenho dentro do envelope
## de colisão, emblema da gangue medido no capô e hidráulica só nos lowriders.
const CATALOG = preload("res://runtime/MuscleFleet.gd")
const FLEET = preload("res://runtime/FleetCatalog.gd")
const STREET = preload("res://gameplay/desert_cars/StreetPowertrainCatalog.gd")
const REDESIGNED = preload("res://runtime/RedesignedFleet.gd")
const VEHICLE = preload("res://scripts/Vehicle.gd")
const DOORS = preload("res://gameplay/VehicleDoorPresentation.gd")
const DOOR_SPECS = preload("res://data/catalogs/VehicleDoorSpecs.gd")
const ROLES = preload("res://runtime/VehicleSurfaceRoles.gd")
const ENGINES = preload("res://audio/FleetEngineDesign.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	check(CATALOG.IDS.size() == CATALOG.MUSCLE_IDS.size() + CATALOG.LOWRIDER_IDS.size(), "IDS = muscle + lowrider")
	var picks := {}
	for i in 400: picks[CATALOG.cobra_pick(float(i) / 400.0)] = true
	check(picks.size() == CATALOG.IDS.size(), "a garagem dos Cobras sorteia todos os modelos (%d)" % picks.size())
	for id: String in CATALOG.IDS:
		var spec: Dictionary = FLEET.spec(id)
		check(not spec.is_empty(), id + ": registrado no FleetCatalog")
		check(REDESIGNED.contains(id), id + ": cena assada registrada")
		check(STREET.has(id), id + ": motor completo (StreetPowertrainCatalog)")
		check(str(spec.get("drivetrain", "")) == "rwd", id + ": tração traseira")
		check(float(STREET.spec(id).get("traction", 0.0)) >= clampf(float(spec.acceleration) / 160.0, 2.0, 10.0) / 9.81, id + ": aderência segura a aceleração")
		check(ENGINES.VEHICLE_PROFILES.has(id), id + ": perfil de som de motor")
		check(not DOOR_SPECS.row(id).is_empty(), id + ": porta na tabela")
		check(bool(spec.get("lowrider", false)) == (id in CATALOG.LOWRIDER_IDS), id + ": marca de lowrider na ficha")
	var stage := Node3D.new()
	root.add_child(stage)
	for id: String in CATALOG.IDS:
		var car := VEHICLE.new()
		car.archetype = id
		stage.add_child(car)
		car.process_mode = Node.PROCESS_MODE_DISABLED
		check(car.wheels.size() == 4, id + ": quatro rodas com pivô")
		check((car.hydraulics != null) == CATALOG.is_lowrider(id), id + ": hidráulica só no lowrider")
		check(car.visual.has_meta("hood_badge") and (car.visual.get_meta("hood_badge") as Vector3).z < 0.0, id + ": ponto do emblema no capô")
		var lights := {"headlight":0, "tail":0}
		var cabin: Dictionary = car.visual.get_meta("vehicle_interior_spec", {})
		var d := CATALOG.door_spec(id)
		check(not cabin.is_empty(), id + ": cabine declarada")
		check(float(cabin.get("sz", 999)) >= float(d.zf) and float(cabin.get("sz", 999)) <= float(d.zr), id + ": banco dentro do vão da porta")
		var leaves := {}
		var bounds := AABB()
		var first := true
		for part: MeshInstance3D in car.visual.find_children("*", "MeshInstance3D", true, false):
			if part.mesh == null: continue
			var box := (car.visual.global_transform.affine_inverse() * part.global_transform) * part.mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
			for surface in part.mesh.get_surface_count():
				var role := ROLES.key(part, surface)
				if ROLES.is_headlight_lens(role): lights.headlight += 1
				if ROLES.is_tail_lens(role): lights.tail += 1
			if part.has_meta("new_civilian_door_side"): leaves[int(part.get_meta("new_civilian_door_side"))] = part
		check(lights.headlight >= 2 and lights.tail >= 1, id + ": lentes de farol e lanterna " + str(lights))
		check(bounds.position.y >= -.0001, id + ": nada abaixo do chão (" + str(bounds.position.y) + ")")
		var size: Array = CATALOG.spec(id).bounds_size
		check(bounds.size.x <= float(size[0]) + .05 and bounds.size.y <= float(size[1]) + .05 and bounds.size.z <= float(size[2]) + .05, id + ": envelope de colisão real=" + str(bounds.size) + " ficha=" + str(size))
		check(bounds.size.z >= float(size[2]) - .15, id + ": ficha não é maior que o desenho")
		check(leaves.size() == 2, id + ": duas folhas de porta")
		var doors := DOORS.new()
		car.visual.add_child(doors)
		doors.configure(car)
		check(doors.ready_for_boarding, id + ": porta pronta sem recorte")
		for side in leaves:
			var leaf: MeshInstance3D = leaves[side]
			check(leaf.get_parent() == doors.hinges.get(side), id + ": dobradiça certa")
		car.free()
	stage.free()
	print("MUSCLE_FLEET_MODELS ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
