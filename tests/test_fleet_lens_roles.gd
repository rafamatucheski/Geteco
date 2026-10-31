extends SceneTree
## Regressão: acabamento autoral nunca pode virar lanterna traseira por casamento de substring.
## Usa fábrica/Vehicle/equipamento reais para os 59; sem afirmações de direção nem visuais/FPS.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const EQUIPMENT := preload("res://gameplay/VehicleEquipment.gd")
const REGISTRY := preload("res://runtime/RedesignedFleet.gd")
const ROLES := preload("res://runtime/VehicleSurfaceRoles.gd")
const NONLENS := ["detail","service_detail","brake_metal","trim","rubber","tire","wheel","paint","roof_paint","glass","steel","interior","case","stripe","amber","amber_turn","indicator"]
var failures: Array[String] = []
var checks := 0
var models: Dictionary = {}
var stage: Node3D

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func material_state(material: StandardMaterial3D) -> Array:
	return [material.get_instance_id(),material.albedo_color,material.emission_enabled,material.emission,material.emission_energy_multiplier,material.roughness,material.metallic,material.vertex_color_use_as_albedo]

func nonlens_snapshot(car: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for part: MeshInstance3D in car.visual.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null: continue
		for surface in part.mesh.get_surface_count():
			var role := ROLES.key(part,surface)
			var material := part.get_active_material(surface) as StandardMaterial3D
			if role not in NONLENS or material == null: continue
			result.append({"part":part,"surface":surface,"role":role,"state":material_state(material)})
	return result

func verify_nonlens(rows: Array[Dictionary], label: String) -> void:
	var altered: Array[String] = []
	for row in rows:
		var material := row.part.get_active_material(row.surface) as StandardMaterial3D
		if material == null or material_state(material) != row.state:
			altered.append(str(row.part.name)+"/"+str(row.surface)+":"+row.role)
	check(altered.is_empty(),label+" nonlens materials unchanged: "+str(altered))

func aliases() -> void:
	var car := VEHICLE.new()
	var equipment := EQUIPMENT.new()
	equipment.configure(car,stage)
	var material := StandardMaterial3D.new()
	for role in ["tail","tail#fixed","tail_light","taillight","taillight_vert","rear_lens","brake_light","brake"]:
		check(equipment._lens_role(role,material,Vector3(0,1,2)) == "tail","legacy rear alias "+role)
		check(equipment._lens_role(role,material,Vector3(0,1,-2)) == "","rear alias cannot mount in front: "+role)
	for role in ["headlight","headlight#fixed","headlight#-1_0","headlight#1_0","headlight_left","headlight_right"]:
		check(equipment._lens_role(role,material,Vector3(0,1,-2)) == "headlight","front alias "+role)
	for role in ["detail","service_detail","detail#fixed","brake_metal","headlight_trim","tailpipe","retail","taillight_housing"]:
		for z in [-2.0,2.0]:
			check(equipment._lens_role(role,material,Vector3(0,1,z)) == "","nonlens role rejected "+role+" at "+str(z))
	# Older motorcycles/vehicles may have untagged emissive lenses.
	material.emission_enabled = true
	material.albedo_color = Color("f5f6fa")
	check(equipment._lens_role("",material,Vector3(0,1,-4)) == "headlight","untagged legacy white front lens")
	material.albedo_color = Color("c0392b")
	check(equipment._lens_role("",material,Vector3(0,1,4)) == "tail","untagged legacy red rear lens")
	equipment.free()
	car.free()

func inspect(id: String) -> void:
	var began_checks := checks
	var began_failures := failures.size()
	var car := VEHICLE.new()
	car.archetype = id
	stage.add_child(car)
	car.process_mode = Node.PROCESS_MODE_DISABLED
	var rows := nonlens_snapshot(car)
	var details := 0
	for row in rows:
		if row.role in ["detail","service_detail"]: details += 1
	# Motos têm um único farol redondo e não passam pelo acabamento de carro: só os carros exigem superfícies de detalhe.
	check(details > 0 or id.begins_with("bike_"),id+" includes actual authored detail surfaces")
	var equipment: Node = car.ensure_equipment(stage)
	verify_nonlens(rows,id+" after binding")
	check(equipment.lamps.size() == (1 if id.begins_with("bike_") else 2) and not equipment.tail_materials.is_empty(),id+" retains paired projectors and rear lenses")
	car.controlled = true
	check(equipment.toggle_headlights(),id+" headlight action accepted")
	verify_nonlens(rows,id+" headlights on")
	var lit := true
	for material: StandardMaterial3D in equipment.tail_materials:
		lit = lit and material.emission_enabled and is_equal_approx(material.emission_energy_multiplier,.9)
	check(lit,id+" rear lenses enter night state")
	car.brake_input = true
	equipment._refresh()
	verify_nonlens(rows,id+" brakes on")
	var braking := true
	for material: StandardMaterial3D in equipment.tail_materials:
		braking = braking and material.emission_enabled and is_equal_approx(material.emission_energy_multiplier,2.5)
	check(braking,id+" rear lenses brighten under braking")
	var emergency := id in ["police_cruiser","police_suv","police_transport","medic_box","rescue_pumper"]
	check(equipment.toggle_siren() == emergency,id+" emergency availability preserved")
	verify_nonlens(rows,id+" siren action")
	if emergency:
		var beacon_lit := false
		for beacon: Dictionary in equipment.beacons: beacon_lit = beacon_lit or beacon.material.emission_enabled
		check(beacon_lit and equipment.siren_audio.playing,id+" beacon and siren operate")
		check(equipment.toggle_siren(),id+" siren stops normally")
	car.brake_input = false
	check(equipment.toggle_headlights(),id+" headlight off action accepted")
	equipment._refresh()
	verify_nonlens(rows,id+" lights and brakes off")
	var dark := true
	for material: StandardMaterial3D in equipment.tail_materials: dark = dark and not material.emission_enabled
	check(dark,id+" rear lenses return to off state")
	models[id] = {"checks":checks-began_checks,"failures":failures.slice(began_failures),"nonlens_surfaces":rows.size(),"detail_surfaces":details,"real_projectors":equipment.lamps.size(),"tail_materials":equipment.tail_materials.size(),"beacons":equipment.beacons.size()}
	print("FLEET_LENS_ROLE ",id," ",JSON.stringify(models[id]))
	car.free()
	await process_frame

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	aliases()
	var ids: Array = REGISTRY.MESH_COUNTS.keys()
	for id: String in ids: await inspect(id)
	stage.free()
	var path := "res://evidence/fleet-redesign-20261011/validation/lens-role-fix/contracts.json"
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"vehicles":models,"scope":"material-role binding and light/brake/siren state; no temporal or FPS approval"},"\t"))
	print("FLEET_LENS_ROLES ","PASS" if failures.is_empty() else "FAIL"," vehicles=",models.size()," checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
