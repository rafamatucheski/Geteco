extends SceneTree
## Esportivos 2.0 (runtime/SportFleet.gd): cada tração tem pelo menos dois carros, todos com
## motor completo, cena assada registrada, folhas de porta prontas sem recorte, cabine
## declarada e desenho dentro do envelope de colisão.
const CATALOG = preload("res://runtime/SportFleet.gd")
const FLEET = preload("res://runtime/FleetCatalog.gd")
const STREET = preload("res://gameplay/desert_cars/StreetPowertrainCatalog.gd")
const REDESIGNED = preload("res://runtime/RedesignedFleet.gd")
const VEHICLE = preload("res://scripts/Vehicle.gd")
const DOORS = preload("res://gameplay/VehicleDoorPresentation.gd")
const ROLES = preload("res://runtime/VehicleSurfaceRoles.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	var drivetrains := {}
	for id: String in CATALOG.IDS:
		var spec: Dictionary = FLEET.spec(id)
		check(not spec.is_empty(), id+": registrado no FleetCatalog")
		check(REDESIGNED.contains(id), id+": cena assada registrada")
		check(STREET.has(id), id+": motor completo (StreetPowertrainCatalog)")
		check(float(STREET.spec(id).get("traction",0.0)) >= clampf(float(spec.acceleration)/160.0,2.0,10.0)/9.81, id+": aderência segura a aceleração")
		var kind := str(spec.get("drivetrain",""))
		drivetrains[kind] = int(drivetrains.get(kind,0))+1
	for kind in ["awd","fwd","rwd","4x4"]:
		check(int(drivetrains.get(kind,0)) >= 2, "tração "+kind+": pelo menos dois esportivos ("+str(drivetrains)+")")
	var stage := Node3D.new()
	root.add_child(stage)
	for id: String in CATALOG.IDS:
		var car := VEHICLE.new()
		car.archetype = id
		stage.add_child(car)
		car.process_mode = Node.PROCESS_MODE_DISABLED
		check(car.wheels.size() == 4, id+": quatro rodas com pivô")
		var lights := {"headlight":0, "tail":0}
		var cabin: Dictionary = car.visual.get_meta("vehicle_interior_spec", {})
		var d := CATALOG.door_spec(id)
		check(not cabin.is_empty(), id+": cabine declarada")
		check(float(cabin.get("sz",999))>=float(d.zf) and float(cabin.get("sz",999))<=float(d.zr), id+": banco dentro do vão da porta")
		var leaves := {}
		var bounds := AABB()
		var first := true
		for part: MeshInstance3D in car.visual.find_children("*", "MeshInstance3D", true, false):
			if part.mesh == null: continue
			var box := (car.visual.global_transform.affine_inverse()*part.global_transform)*part.mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
			for surface in part.mesh.get_surface_count():
				var role := ROLES.key(part,surface)
				if ROLES.is_headlight_lens(role): lights.headlight += 1
				if ROLES.is_tail_lens(role): lights.tail += 1
			if not part.has_meta("new_civilian_door_side"): continue
			var side := int(part.get_meta("new_civilian_door_side"))
			leaves[side] = {"part":part, "mesh":part.mesh}
			var outside := 0.0
			var inside := 0.0
			for surface in part.mesh.get_surface_count():
				var role := ROLES.key(part,surface)
				if role not in ["paint", "detail"]: continue
				var arrays := part.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				for j in range(0, indices.size(), 3):
					var a := vertices[indices[j]]
					var b := vertices[indices[j+1]]
					var c := vertices[indices[j+2]]
					if maxf(a.y,maxf(b.y,c.y))>float(d.belt)+.001: continue
					var n := (b-a).cross(c-a)
					if absf(n.normalized().x)<.8: continue
					if role=="paint": outside += n.length()*.5
					elif n.normalized().x*side>0: inside += n.length()*.5
			check(outside>.15, id+": lataria externa da porta "+str(side))
			check(inside>.15, id+": cartão interno da porta "+str(side))
		check(lights.headlight >= 2 and lights.tail >= 1, id+": lentes de farol e lanterna "+str(lights))
		check(bounds.position.y>=-.0001, id+": nada abaixo do chão ("+str(bounds.position.y)+")")
		var size: Array = CATALOG.spec(id).bounds_size
		check(bounds.size.x<=float(size[0])+.05 and bounds.size.y<=float(size[1])+.05 and bounds.size.z<=float(size[2])+.05, id+": envelope de colisão real="+str(bounds.size)+" ficha="+str(size))
		check(bounds.size.z>=float(size[2])-.15, id+": ficha não é maior que o desenho ("+str(bounds.size.z)+" × "+str(size[2])+")")
		check(leaves.size()==2, id+": duas folhas de porta")
		var doors := DOORS.new()
		car.visual.add_child(doors)
		doors.configure(car)
		check(doors.ready_for_boarding, id+": porta pronta sem recorte")
		for side in leaves:
			var leaf: MeshInstance3D = leaves[side].part
			check(leaf.mesh==leaves[side].mesh, id+": porta reusa a malha assada")
			check(leaf.get_parent()==doors.hinges.get(side), id+": dobradiça certa")
			var closed := leaf.global_transform
			var hinge: Node3D = doors.hinges[side]
			hinge.rotation.y = float(side)*1.05
			check(not leaf.global_transform.is_equal_approx(closed), id+": folha abre")
			hinge.rotation.y = 0
			check(leaf.global_transform.is_equal_approx(closed), id+": fecha na mesma pose")
		car.free()
	stage.free()
	print("SPORT_FLEET_MODELS ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
