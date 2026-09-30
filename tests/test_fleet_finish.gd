extends SceneTree
const FLEET := preload("res://runtime/FleetCatalog.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const FINISH := preload("res://runtime/VehicleFinish.gd")
const ROLES := preload("res://runtime/VehicleSurfaceRoles.gd")
const GEOMETRY := preload("res://tools/fleet_fixups/FleetGeometry.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAIL ",label)
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	for id in FLEET.all():
		# Industrial lifting equipment is covered by its own contract, not road lamps.
		if id == "port_forklift": continue
		var car := VEHICLE.new()
		car.archetype = id
		world.add_child(car)
		car.set_physics_process(false)
		car.ensure_equipment(world)
		var equipment = car.equipment
		check(not equipment.lens_materials.is_empty(),id+": headlight lenses bound")
		# The forklift has no road brake lamps; all road vehicles do.
		# O blindado do Exército não tem lanternas de freio; a empilhadeira também não.
		if id not in ["port_forklift","army_tank"]: check(not equipment.tail_materials.is_empty(),id+": rear brake lenses bound")
		for item in equipment.lamps:
			check(item.lamp.position.z < -.2,id+": projectors ahead of cabin")
			check(item.lamp.transform.basis.z.z > .9,id+": beam faces driving direction (-Z)")
		car.controlled = true
		car.brake_input = true
		equipment._refresh()
		for material in equipment.tail_materials:
			check(material.emission_enabled and material.emission_energy_multiplier > 2 and material.emission.r > material.emission.g*3,id+": braking lights red in daylight")
		car.brake_input = false
		equipment._refresh()
		for material in equipment.tail_materials: check(not material.emission_enabled,id+": release extinguishes daytime brake lights")
		car.controlled = false
		car.brake_input = true
		equipment._refresh()
		for material in equipment.tail_materials: check(not material.emission_enabled,id+": parked car does not brake")
		car.controlled = true
		car.health = 0
		equipment._refresh()
		for material in equipment.tail_materials: check(not material.emission_enabled,id+": wreck lamps off")
		# Moto da polícia tem libré fixa (sem material "paint"); não é repintável na garagem.
		if id != "bike_police": check(not car._paint.materials.is_empty(),id+": paint remains customizable")
		if id in FINISH.CABINS:
			var cabin := car.visual.get_node("SculptedCabin") as MeshInstance3D
			var glass := cabin.get_active_material(0) as StandardMaterial3D
			check(glass != null and glass.roughness <= .15,id+": separate polished glazing")
			var original := glass.albedo_color
			car.paint_color = Color.MAGENTA
			check(glass.albedo_color == original,id+": repaint does not paint over windows")
			var count := car.visual.get_child_count()
			FINISH.decorate(id,car.visual)
			check(count == car.visual.get_child_count(),id+": generation is idempotent")
			var geo = GEOMETRY.new(car.visual)
			var arrays := cabin.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for first in range(0,vertices.size(),6):
				var center := Vector3.ZERO
				for i in 6: center += vertices[first+i]/6.0
				# Tactical van bars intentionally cross the windshield; the body must not.
				# Sample the clear pane between its three narrow protective bars.
				if id == "police_transport" and normals[first].z < -.5: center.x += .12
				var hit: Dictionary = geo.ray(center+normals[first]*.22,-normals[first])
				check(not hit.is_empty() and hit.part == cabin,id+": window exposed outside body at "+str(center)+" hit="+(str(hit.part.name) if not hit.is_empty() else "none"))
			for part: MeshInstance3D in geo.parts():
				if part.mesh.get_surface_count() != 1 or not GEOMETRY.is_tail_lamp(part): continue
				var center: Vector3 = geo.bounds(part).get_center()
				if center.z < 0: continue
				var hit: Dictionary = geo.ray(center+Vector3.BACK*.25,Vector3.FORWARD)
				check(not hit.is_empty() and hit.part == part,id+": brake lens exposed outside body")
		print("AUDIT ",id," fronts=",equipment.lens_materials.size()," tails=",equipment.tail_materials.size()," paint=",car._paint.materials.size())
		car.free()
	var first_car := VEHICLE.new()
	first_car.archetype = "arctic_jeep"
	world.add_child(first_car)
	first_car.set_physics_process(false)
	first_car.ensure_equipment(world)
	var second_car := VEHICLE.new()
	second_car.archetype = "arctic_jeep"
	world.add_child(second_car)
	second_car.set_physics_process(false)
	second_car.ensure_equipment(world)
	first_car.controlled = true
	first_car.brake_input = true
	first_car.equipment._refresh()
	second_car.equipment._refresh()
	check(first_car.equipment.tail_materials[0] != second_car.equipment.tail_materials[0] and not second_car.equipment.tail_materials[0].emission_enabled,"braking one car does not light a shared model")
	first_car.traffic = true
	first_car.brake_input = false
	first_car.equipment._previous_speed = 8.0
	first_car.speed = 7.5
	first_car.equipment._process(.1)
	check(first_car.equipment.tail_materials[0].emission_energy_multiplier > 2,"traffic deceleration lights brake lamps")
	first_car.equipment._process(.01)
	check(first_car.equipment.tail_materials[0].emission_energy_multiplier > 2,"brake lamps stay steady between physics ticks")
	first_car.equipment._process(.2)
	check(not first_car.equipment.tail_materials[0].emission_enabled,"traffic brakes release after deceleration")
	world.free()
	print("FLEET_FINISH ",checks," checks failures=",failures)
	quit(0 if failures.is_empty() else 1)
