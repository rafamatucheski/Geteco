extends SceneTree
## Saias, lábio, difusor e aerofólios novos precisam caber no carro de verdade: entre as
## rodas, acima do chão, na frente/traseira certa, sem duplicar nem vazar na troca.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const APPEARANCE := preload("res://gameplay/desert_cars/TuningAppearance.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const ROOF := preload("res://gameplay/desert_cars/TuningSunroof.gd")
const HATCHES := ["orbita_micro","station_wagon","nordic_estate","nimbus_minivan","surf_woody_wagon","sport_estate","digo_gol_1993"]
const BOOTS := ["desert_coyote","sedan_classic","union_sedan","cobra_v8","taxi_yellow","muscle_classic","aurora_executive","porto_rosso","vertice_midengine","jessica_jetta_gli"]
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func run() -> void:
	check(TUNING.compatible("skirt_sport","desert_mirage"),"Coupe accepts side skirts")
	check(not TUNING.compatible("skirt_step","desert_mirage"),"Coupe has no utility step")
	check(TUNING.compatible("skirt_step","desert_bison"),"Pickup accepts a side step")
	check(not TUNING.compatible("skirt_sport","desert_bison"),"Pickup refuses low skirts")
	check(not TUNING.compatible("lip_splitter","ranch_pickup") and not TUNING.compatible("diffuser_race","ranch_pickup"),"Utility refuses lip and diffuser")
	check(not TUNING.compatible("skirt_sport","beach_buggy"),"Buggy has no body sides for skirts")
	for slot in ["skirts","front_lip","diffuser"]: check(slot in TUNING.SLOTS and TUNING.SLOT_LABELS.has(slot),slot+" is a workshop slot")
	for slot in TUNING.FACTORY_KIT:
		var part: String = {"spoiler":"spoiler_sport","front_lip":"lip_sport","diffuser":"diffuser_street","skirts":"skirt_sport"}[slot]
		for id in TUNING.FACTORY_KIT[slot]: check(not TUNING.compatible(part,id),id+" factory "+slot+" is not doubled by a workshop part")
	for id in ["desert_faisca","desert_coyote","desert_mirage","desert_siroco","supra_a80","rauhz_focus_mk1","sedan_classic","sport_coupe","metro_hatch","desert_bison","orbita_micro","station_wagon","nordic_estate","nimbus_minivan","cobra_v8","monaliza","taxi_yellow","surf_woody_wagon","sport_estate","digo_gol_1993","desert_coyote_drag","union_sedan","muscle_classic","aurora_executive","porto_rosso","vertice_midengine","jessica_jetta_gli"]:
		_car_cycle(id)
	print("TUNING_AERO_KITS checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _car_cycle(id: String) -> void:
	var car := VEHICLE.new()
	car.archetype = id
	root.add_child(car)
	car.set_physics_process(false)
	var sibling := VEHICLE.new()
	sibling.archetype = id
	root.add_child(sibling)
	sibling.set_physics_process(false)
	var sibling_meshes: Array = []
	for part in sibling.visual.find_children("*","MeshInstance3D",true,false): sibling_meshes.append(part.mesh)
	var utility := TUNING.is_utility(id)
	var looks: Array = [{"skirts":"skirt_step"}] if utility else [
		{"skirts":"skirt_slim","front_lip":"lip_sport","diffuser":"diffuser_street","spoiler":"spoiler_ducktail"},
		{"skirts":"skirt_sport"},
		{"skirts":"skirt_vented","front_lip":"lip_splitter","diffuser":"diffuser_race","spoiler":"spoiler_gt"},
		{"skirts":"skirt_carbon","paint":"paint_royal","wheels":"wheels_gold","wheel_model":"wheel_six_spoke"},
		{"wheel_model":"wheel_multi_spoke","wheels":"wheels_white"}]
	for wanted in looks:
		var parts := {}
		for slot in wanted:
			if id not in TUNING.FACTORY_KIT.get(slot,[]) and not (slot == "spoiler"): check(TUNING.compatible(wanted[slot],id),id+" offers "+wanted[slot])
			if TUNING.compatible(wanted[slot],id): parts[slot] = wanted[slot]
		# Aplica o pedido inteiro: a montagem precisa recusar sozinha o que não cabe neste carro.
		APPEARANCE.apply_vehicle(car,wanted)
		var kits: RefCounted = car.get_meta("tuning_appearance")._kits
		for slot in ["skirts","front_lip","diffuser"]:
			if wanted.has(slot) and not parts.has(slot): check(not is_instance_valid(kits.aero.nodes.get(slot)),id+" incompatible "+slot+" is not mounted")
		var b: Dictionary = kits.aero.body()
		check(not b.is_empty(),id+" body measured for aero kit")
		if b.is_empty(): continue
		var rear := float(b.rear)
		if parts.has("skirts"):
			var node: Node3D = kits.aero.nodes.get("skirts")
			check(is_instance_valid(node),id+" "+parts.skirts+" built")
			if is_instance_valid(node):
				var box := _bounds(node,car.visual)
				var zs := [box.position.z*rear,box.end.z*rear]
				check(minf(zs[0],zs[1]) > float(b.front_axle) and maxf(zs[0],zs[1]) < float(b.rear_axle),id+" "+parts.skirts+" stays between the wheels")
				check(box.position.y > float(b.ground)+.06,id+" "+parts.skirts+" clears the ground")
				check(box.end.x > float(b.sill_hw) and box.end.x < float(b.wheel_hw)+.25,id+" "+parts.skirts+" sits on the sill, not floating wide")
		if parts.has("front_lip"):
			var node: Node3D = kits.aero.nodes.get("front_lip")
			check(is_instance_valid(node),id+" "+parts.front_lip+" built")
			if is_instance_valid(node):
				var box := _bounds(node,car.visual)
				check(minf(box.position.z*rear,box.end.z*rear) < float(b.front_axle),id+" lip is at the real front")
				check(box.position.y > float(b.ground)+.04,id+" lip clears the ground")
		if parts.has("diffuser"):
			var node: Node3D = kits.aero.nodes.get("diffuser")
			check(is_instance_valid(node),id+" "+parts.diffuser+" built")
			if is_instance_valid(node):
				var box := _bounds(node,car.visual)
				check(maxf(box.position.z*rear,box.end.z*rear) > float(b.rear_axle),id+" diffuser is at the real rear")
		if parts.has("spoiler"):
			check(is_instance_valid(kits.spoiler),id+" "+parts.spoiler+" built")
			var mount: Dictionary = kits.aero.spoiler_mount()
			# Hatch, perua e minivan: borda do teto; sedã, cupê e muscle: tampa do porta-malas.
			if id in HATCHES: check(bool(mount.hatch) and float(mount.y) > float(mount.roof_y)-.12,id+" spoiler sits on the rear roof edge")
			if id in BOOTS: check(not bool(mount.hatch) and float(mount.y) < float(mount.roof_y)-.18,id+" spoiler sits on the boot lid")
			if is_instance_valid(kits.spoiler):
				var box := _bounds(kits.spoiler,car.visual)
				check(maxf(box.position.z*rear,box.end.z*rear) > float(b.rear_axle)-.6,id+" spoiler is at the real rear")
		elif wanted.has("spoiler"): check(not is_instance_valid(kits.spoiler),id+" incompatible spoiler is not mounted")
		var count := car.visual.find_children("*","MeshInstance3D",true,false).size()
		for repeat in 2: APPEARANCE.apply_vehicle(car,wanted)
		check(car.visual.find_children("*","MeshInstance3D",true,false).size()==count,id+" repeated preview does not duplicate kits")
	APPEARANCE.apply_vehicle(car,{})
	var kits_after: RefCounted = car.get_meta("tuning_appearance")._kits
	for slot in ["skirts","front_lip","diffuser"]: check(not is_instance_valid(kits_after.aero.nodes.get(slot)),id+" removing "+slot+" frees its geometry")
	var sibling_after: Array = []
	for part in sibling.visual.find_children("*","MeshInstance3D",true,false): sibling_after.append(part.mesh)
	check(sibling_after==sibling_meshes,id+" sibling keeps shared fleet meshes")
	car.free(); sibling.free()

func _bounds(node: Node3D, ancestor: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for part: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		var box: AABB = ROOF.relative_transform(part,ancestor)*part.mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result
