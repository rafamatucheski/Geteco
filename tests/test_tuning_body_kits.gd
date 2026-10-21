extends SceneTree
## New visual parts must fit an actual donor, preserve driving/identity, isolate
## shared fleet resources and survive repeated preview/removal without leaks.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const APPEARANCE := preload("res://gameplay/desert_cars/TuningAppearance.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const WHEEL := preload("res://gameplay/desert_cars/TuningWheelKit.gd")
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func run() -> void:
	check(TUNING.compatible("sunroof_glass","desert_faisca"),"Authored roof accepts real glass aperture")
	check(not TUNING.compatible("sunroof_glass","beach_cabriolet"),"Convertible cannot buy a fabricated sunroof")
	check(not TUNING.compatible("wheel_mesh","army_tank"),"Tank cannot buy car rims")
	check(not TUNING.compatible("spoiler_sport","desert_bison"),"Pickup has no unsupported boot spoiler")
	check(not TUNING.compatible("unknown","desert_faisca"),"Unknown part is refused")
	for design in ["five_spoke","mesh","turbine"]:
		for ratio in [.60,.72,.80]:
			var kit := WHEEL.build(design,.32,Color("a58450"),.22,ratio)
			var bounds: AABB = kit.get_child(0).mesh.get_aabb()
			check(absf(bounds.size.y-.64)<.002 and absf(bounds.size.z-.64)<.002,"Different rim/profile keeps tyre contact radius: "+design+str(ratio))
			kit.free()
	for id in ["desert_faisca","desert_coyote","desert_mirage","supra_a80","sedan_classic","sport_coupe"]:
		var car := VEHICLE.new()
		car.archetype = id
		car.vehicle_id = "kit_contract_"+id
		root.add_child(car)
		car.set_physics_process(false)
		var sibling := VEHICLE.new()
		sibling.archetype = id
		root.add_child(sibling)
		sibling.set_physics_process(false)
		var sibling_meshes: Array = []
		for part in sibling.visual.find_children("*","MeshInstance3D",true,false): sibling_meshes.append(part.mesh)
		var original_pivots: Array = []
		for pivot in car.wheels: original_pivots.append(pivot.transform)
		var initial_speed: float = car.max_forward_speed
		var initial_health: float = car.health
		var parts := {"wheel_model":"wheel_mesh","wheel_size":"wheel_size_large","wheels":"wheels_bronze","spoiler":"spoiler_sport","taillights":"taillights_smoke"}
		if TUNING.compatible("sunroof_glass",id): parts.sunroof = "sunroof_glass"
		# Cover both a saved kit installed before boarding and the live workshop,
		# where the driver/cabin already exist when the glass is previewed.
		if id in ["desert_coyote","supra_a80"]:
			car.controlled = true
			INTERIOR.attach(car)
		APPEARANCE.apply_vehicle(car,parts)
		var appearance: RefCounted = car.get_meta("tuning_appearance")
		var kits: RefCounted = appearance._kits
		check(kits.wheels.size()==4,id+" has four independently animated wheel kits")
		for group in kits.wheels:
			check(is_instance_valid(group.kit) and group.parts.all(func(p): return not p.visible),id+" kit replaces original wheel without doubled geometry")
			check(group.kit.get_meta("alloy_material").albedo_color == Color("a58450"),id+" kit receives purchased alloy colour")
		if id == "desert_coyote":
			# PassengerDesign authors the rotor with #667177. Check those exact
			# referenced triangles: dark hub pixels alone cannot prove rotor safety.
			var rotors_checked := 0
			for group in kits.wheels:
				var rotor_found := false
				var rotor_unchanged := true
				for part in group.parts:
					for surface in part.mesh.get_surface_count():
						var material: StandardMaterial3D = part.get_active_material(surface)
						var arrays: Array = part.mesh.surface_get_arrays(surface)
						if arrays[Mesh.ARRAY_COLOR] == null: continue
						var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
						var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
						if indices.is_empty():
							for index in colors.size(): indices.append(index)
						for index in indices:
							var authored_rotor := Color("667177")
							if absf(colors[index].r-authored_rotor.r)>.012 or absf(colors[index].g-authored_rotor.g)>.012 or absf(colors[index].b-authored_rotor.b)>.012: continue
							rotor_found = true
							var effective: Color = material.albedo_color*colors[index] if material.vertex_color_use_as_albedo else material.albedo_color
							if not effective.is_equal_approx(colors[index]): rotor_unchanged = false
				check(rotor_found and rotor_unchanged,id+" purchased bronze leaves the actual rotor grey unchanged")
				if rotor_found: rotors_checked += 1
			check(rotors_checked==4,id+" authored rotor colour inspected on all four wheels")
		check(not kits.tails.is_empty(),id+" actual rear lens was found")
		check(kits.tails.all(func(row): return row.material.albedo_color==Color("352c37")),id+" lens tint reaches real tail material")
		if parts.has("sunroof"):
			check(kits.roof.cut_triangles>0 and is_instance_valid(kits.roof.glass_node),id+" glass replaces clipped opaque triangles")
			for row in kits.roof.surfaces: check(row.part.mesh != row.original,id+" opaque roof mesh actually replaced")
			# Production's current open_view records the cabin without calling its
			# legacy _open_roof splitter. Exercise real boarding and the low camera,
			# then leave/reboard: an opaque roof skin must never cover the aperture.
			for boarding in 2:
				car.controlled = true
				INTERIOR.attach(car)
				INTERIOR.open_view(car)
				INTERIOR.set_low_camera_roof(car,true)
				check(_opaque_roof_hits(car)==0,id+" actual aperture stays clear after boarding "+str(boarding))
				check(kits.roof.glass_node.visible and kits.roof.glass_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,id+" glass survives seated low-camera view")
				INTERIOR.close_view(car)
				car.controlled = false
				check(_opaque_roof_hits(car)==0,id+" aperture persists after leaving "+str(boarding))
				check(car.visual.find_children("TuningSunroofGlass","MeshInstance3D",true,false).size()==1,id+" occupancy does not duplicate glass")
		var count := car.visual.find_children("*","MeshInstance3D",true,false).size()
		for repeat in 3: APPEARANCE.apply_vehicle(car,parts)
		check(car.visual.find_children("*","MeshInstance3D",true,false).size()==count,id+" repeated identical preview does not duplicate kits")
		for i in car.wheels.size(): check(car.wheels[i].transform==original_pivots[i],id+" steering/spin pivot was preserved")
		check(car.max_forward_speed==initial_speed and car.health==initial_health,id+" preview preserves driving and condition")
		# Boarding can lazily replace lens instances after a saved kit was applied.
		# The next visual edit must follow the live material, not a stale reference.
		for row in kits.tails:
			var replacement: StandardMaterial3D = row.material.duplicate()
			if row.part.material_override != null: row.part.material_override = replacement
			else: row.part.set_surface_override_material(row.surface,replacement)
		APPEARANCE.apply_vehicle(car,{})
		check(not is_instance_valid(kits.spoiler),id+" removing spoiler frees its geometry")
		for group in kits.wheels: check(not is_instance_valid(group.kit) and group.parts.all(func(p): return p.visible),id+" removing kit restores original wheels")
		for row in kits.tails: check(row.material.albedo_color==row.color,id+" removal restores each original lens colour")
		if id == "sport_coupe":
			var tyre_checked := 0
			for group in kits.wheels:
				for part in group.parts:
					for surface in part.mesh.get_surface_count():
						var material: StandardMaterial3D = part.get_active_material(surface)
						if material.resource_name != "wheel_fixed": continue
						check(material.albedo_color == Color.WHITE and material.vertex_color_use_as_albedo,id+" rubber and rotor retain authored vertex colours")
						tyre_checked += 1
			check(tyre_checked==4,id+" four tyres remain independent of alloy finish")
		for row in kits.roof.surfaces: check(row.part.mesh==row.original,id+" removal restores original opaque roof resource")
		var sibling_after: Array = []
		for part in sibling.visual.find_children("*","MeshInstance3D",true,false): sibling_after.append(part.mesh)
		check(sibling_after==sibling_meshes,id+" sibling retains original fleet mesh resources")
		car.free(); sibling.free()
	_dent_roof_cycles()
	_tail_lens_inspection()
	print("TUNING_BODY_KITS checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _dent_roof_cycles() -> void:
	for kit_first in [true,false]:
		var car := VEHICLE.new()
		car.archetype = "desert_faisca"
		root.add_child(car)
		car.set_physics_process(false)
		var parts := {"sunroof":"sunroof_glass"}
		if kit_first: APPEARANCE.apply_vehicle(car,parts)
		car.body_dents.impact(10.0,Vector3(.1,.6,-car.half_length))
		if not kit_first: APPEARANCE.apply_vehicle(car,parts)
		check(_opaque_roof_hits(car)==0,"Sunroof aperture exists with prior dent state "+str(kit_first))
		var records: Array = car.body_dents.snapshot()
		car.body_dents.impact(10.0,Vector3(.1,.6,car.half_length))
		check(_opaque_roof_hits(car)==0,"Next impact cannot restore an opaque sunroof skin "+str(kit_first))
		APPEARANCE.apply_vehicle(car,{})
		check(_opaque_roof_hits(car)>0,"Removing sunroof restores opaque roof on dented car "+str(kit_first))
		car.body_dents.impact(10.0,Vector3(car.half_width,.6,.1))
		check(_opaque_roof_hits(car)>0,"Impact after removal cannot restore a glassless aperture "+str(kit_first))
		check(car.body_dents.snapshot().size()>=records.size(),"Cosmetic swaps preserve dent records "+str(kit_first))
		APPEARANCE.apply_vehicle(car,parts)
		check(_opaque_roof_hits(car)==0,"Dented car can reinstall its glass roof "+str(kit_first))
		car.body_dents.clear()
		check(_opaque_roof_hits(car)==0,"Repair preserves installed sunroof aperture "+str(kit_first))
		car.free()

func _tail_lens_inspection() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var car := VEHICLE.new()
	car.archetype = "desert_coyote"
	world.add_child(car)
	car.set_physics_process(false)
	var equipment: Node = car.ensure_equipment(world)
	equipment.set_process(false)
	car.controlled = true
	car.brake_input = true
	equipment.headlights_on = true
	APPEARANCE.apply_vehicle(car,{"taillights":"taillights_amber"})
	equipment._refresh(false)
	check(not equipment.tail_materials.is_empty(),"Inspection fixture binds real Coyote rear lenses")
	check(equipment.tail_materials.all(func(m): return m.albedo_color==Color(1.0,.055,.025) and m.emission_enabled),"Physical held brake produces red signal before lens inspection")
	var beams: Array = []
	for item in equipment.lamps: beams.append(item.lamp.visible)
	equipment.set_tail_lens_preview(true)
	check(equipment.tail_materials.all(func(m): return m.albedo_color==Color("d57a25") and not m.emission_enabled),"Inspection exposes purchased amber lens without brake emission")
	equipment._refresh(false)
	check(car.brake_input and car.controlled,"Lens inspection keeps physical brake and driver ownership")
	var inspection_beams: Array = []
	for item in equipment.lamps: inspection_beams.append(item.lamp.visible)
	check(inspection_beams==beams and equipment.headlights_on,"Lens inspection does not change headlight state")
	APPEARANCE.apply_vehicle(car,{"taillights":"taillights_ruby"})
	equipment._refresh(false)
	check(equipment.tail_materials.all(func(m): return m.albedo_color==Color("8c1737") and not m.emission_enabled),"Changing lens finish stays visible during inspection")
	equipment.set_tail_lens_preview(false)
	check(equipment.tail_materials.all(func(m): return m.albedo_color==Color(1.0,.055,.025) and m.emission_enabled and is_equal_approx(m.emission_energy_multiplier,2.5)),"Leaving inspection immediately restores functional red brake signal")
	car.brake_input = false
	equipment._refresh(false)
	check(equipment.tail_materials.all(func(m): return m.albedo_color==Color("8c1737")),"Releasing physical brake restores installed lens finish")
	world.free()

## Cast a vertical ray through the middle of the actual opening. Test the
## installed geometry/materials, including any cabin skin created on boarding.
func _opaque_roof_hits(car: Node3D) -> int:
	var cabin: Dictionary = car.visual.get_meta("vehicle_interior_spec",{})
	var z: float = (float(cabin.wz1)+float(cabin.rear_top))*.5
	var min_y: float = float(cabin.roof)-.05
	var hits := 0
	for part: MeshInstance3D in car.visual.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null or not part.visible: continue
		var xf: Transform3D = preload("res://gameplay/desert_cars/TuningSunroof.gd").relative_transform(part,car.visual)
		for surface in part.mesh.get_surface_count():
			var material := part.get_active_material(surface) as StandardMaterial3D
			if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: continue
			var arrays: Array = part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if indices.is_empty():
				for index in vertices.size(): indices.append(index)
			for i in range(0,indices.size(),3):
				var a: Vector3 = xf*vertices[indices[i]]
				var b: Vector3 = xf*vertices[indices[i+1]]
				var c: Vector3 = xf*vertices[indices[i+2]]
				var denominator := (b.z-c.z)*(a.x-c.x)+(c.x-b.x)*(a.z-c.z)
				if absf(denominator)<.000001: continue
				var u := ((b.z-c.z)*(-c.x)+(c.x-b.x)*(z-c.z))/denominator
				var v := ((c.z-a.z)*(-c.x)+(a.x-c.x)*(z-c.z))/denominator
				if u>=0 and v>=0 and u+v<=1 and u*a.y+v*b.y+(1-u-v)*c.y>=min_y: hits += 1
	return hits
