extends SceneTree
## Consolidated fleet integration contracts. Headless proves resource behaviour,
## never visual quality/FPS. Existing boarding/physics tests cover the actor flow.
const FLEET=preload("res://runtime/FleetCatalog.gd")
const REGISTRY=preload("res://runtime/RedesignedFleet.gd")
const VEHICLE=preload("res://scripts/Vehicle.gd")
const ROLES=preload("res://runtime/VehicleSurfaceRoles.gd")
const PAINT=preload("res://runtime/VehiclePaint.gd")
var checks:=0
var failures: Array[String]=[]
var report: Dictionary={}
var stage: Node3D
var current_id: String
var legacy:=false
var label:="contracts-after"
var started:=0

func _initialize() -> void: run.call_deferred()

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		var issue:=current_id+": "+message
		failures.append(issue)
		push_error(issue)

func geometry(model: Node3D) -> Dictionary:
	var result:={"meshes":0,"surfaces":0,"triangles":0,"invalid_vertices":0,"roles":{},"centers":[]}
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh==null: continue
		result.meshes+=1
		if part.has_meta("wheel_center") and part.get_meta("wheel_spins",true):
			var center: Vector3=part.get_meta("wheel_center")
			if center not in result.centers: result.centers.append(center)
		for surface in part.mesh.get_surface_count():
			result.surfaces+=1
			var arrays:=part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			result.triangles+=(indices.size() if not indices.is_empty() else vertices.size())/3
			for v in vertices:
				if not v.is_finite(): result.invalid_vertices+=1
			var role:=ROLES.key(part,surface)
			result.roles[role]=int(result.roles.get(role,0))+1
	return result

func spawn(id: String,at: Vector3,tint: Color) -> CharacterBody3D:
	var car:=VEHICLE.new()
	car.archetype=id
	car.paint_color=tint
	car.position=at
	stage.add_child(car)
	car.process_mode=Node.PROCESS_MODE_DISABLED
	return car

func snapshot(model: Node3D,exclude_paint:=false) -> Dictionary:
	var result: Dictionary={}
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh==null: continue
		for surface in part.mesh.get_surface_count():
			var role:=ROLES.key(part,surface)
			if exclude_paint and role in ["paint","roof_paint"]: continue
			var mat:=part.get_active_material(surface) as StandardMaterial3D
			if mat==null: continue
			result[str(model.get_path_to(part))+"/"+str(surface)]={"material":mat.get_instance_id(),"color":mat.albedo_color,"roughness":mat.roughness,"emission":mat.emission_enabled,"detail":mat.detail_enabled,"visible":part.visible}
	return result

func paint_matches(car: CharacterBody3D,tint: Color) -> bool:
	if car._paint.materials.is_empty(): return false
	for mat: StandardMaterial3D in car._paint.materials:
		var expected: Color=preload("res://runtime/VehicleTwoTone.gd").roof_color(tint) if mat in car._paint.roof_materials else tint
		if not mat.albedo_color.is_equal_approx(expected): return false
	return true

func inspect(id: String) -> void:
	current_id=id
	var before_failures:=failures.size()
	var before_checks:=checks
	var source:=FLEET.create(id)
	check(is_instance_valid(source),"factory creates a model")
	if source==null: return
	var raw:=geometry(source)
	check(raw.meshes>0 and raw.triangles>0 and raw.invalid_vertices==0,"nonempty geometry contains only finite vertices")
	check(raw.centers.size()>=4,"at least four independent rolling wheel centers")
	var left:=0
	var right:=0
	var front:=0
	var rear:=0
	for center: Vector3 in raw.centers:
		if center.x<0: left+=1
		else: right+=1
		if center.z<0: front+=1
		else: rear+=1
	check(left>=2 and right>=2 and front>=2 and rear>=2,"wheel anchors occupy both sides and both axles")
	if not legacy:
		for part: MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):
			if part.mesh==null: continue
			for key in part.get_meta_list():
				if str(key).ends_with("surface_material_keys"):
					check(part.get_meta(key).size()==part.mesh.get_surface_count(),"material-role array follows every surface: "+str(part.name))
			if part.has_meta("wheel_center"):
				check(part.get_parent()==source,"rolling part remains reachable by Vehicle pivot binding: "+str(part.name))
	var centers: Array=raw.centers.duplicate()
	source.free()
	var a:=spawn(id,Vector3(0,.05,0),Color("b63b32"))
	var b:=spawn(id,Vector3(15,.05,0),Color("31577a"))
	var equipment: Node=a.ensure_equipment(stage)
	b.ensure_equipment(stage)
	var lens_sides: Array=[]
	for item: Dictionary in equipment.lens_materials:
		if item.side not in lens_sides: lens_sides.append(item.side)
	check(lens_sides.has(-1) and lens_sides.has(1),"front lens surfaces retain independent left/right bindings")
	check(not equipment.tail_materials.is_empty(),"rear lens surfaces remain bound to brake/tail behaviour")
	check(equipment.lamps.size()==2,"headlight binding creates both projectors")
	a.controlled=true
	equipment.toggle_headlights()
	var lenses_lit: bool=not equipment.lens_materials.is_empty()
	for item: Dictionary in equipment.lens_materials: lenses_lit=lenses_lit and item.material.emission_enabled
	check(lenses_lit,"headlight control reaches the actual lens materials")
	if id in ["digo_gol_1993","jessica_jetta_gli"]:
		equipment.broken_left=true
		equipment._refresh()
		var damage_isolated:=true
		for item: Dictionary in equipment.lens_materials:
			damage_isolated=damage_isolated and item.material.emission_enabled==(item.side>0)
		check(damage_isolated and lens_sides.has(-1) and lens_sides.has(1),"breaking one lens preserves the opposite headlight")
		equipment.broken_left=false
		equipment._refresh()
	a.controlled=false
	equipment._refresh()
	check(a.wheels.size()==centers.size(),"Vehicle binds every independent wheel")
	for pivot: Node3D in a.wheels:
		check(pivot.position in centers and pivot.get_child_count()>0,"bound wheel keeps its authored pivot and visible children")
	var untouched_b:=snapshot(b.visual)
	var untouched_trim:=snapshot(a.visual,true)
	check(not a._paint.materials.is_empty() and not b._paint.materials.is_empty(),"both instances expose paintable body materials")
	a.paint_color=Color("d5a544")
	check(paint_matches(a,Color("d5a544")),"repainting reaches all paint surfaces")
	check(snapshot(b.visual)==untouched_b,"repainting leaves the other instance unchanged")
	check(snapshot(a.visual,true)==untouched_trim,"repainting preserves glass, tires, lenses and trim")
	var door_count:=0
	if a.boarding_class() not in ["open","bus"]:
		a.finish_doors()
		check(is_instance_valid(a.door_presentation) and a.door_presentation.ready_for_boarding,"door preparation reaches boarding-ready state")
		if is_instance_valid(a.door_presentation):
			var finished:=geometry(a.visual)
			a.finish_doors()
			check(geometry(a.visual)==finished,"repeated door preparation adds no duplicate geometry")
			for side in a.boarding_sides():
				check(a.door_presentation.hinges.has(side),"door hinge exists on side "+str(side))
				if not a.door_presentation.hinges.has(side): continue
				var hinge: Node3D=a.door_presentation.hinges[side]
				var leaf:=hinge.get_node_or_null("Skin") as MeshInstance3D
				check(leaf!=null and leaf.mesh!=null and leaf.mesh.get_faces().size()>0,"real body/glass skin moves with door on side "+str(side))
				if leaf==null: continue
				var closed:=leaf.global_transform
				var wheel_poses: Array=[]
				for pivot: Node3D in a.wheels: wheel_poses.append(pivot.global_transform)
				a.animate_driver_door(side,true,0.0)
				check(absf(hinge.rotation.y)>.5 and not leaf.global_transform.is_equal_approx(closed),"opening rotates actual skin on side "+str(side))
				var wheel_unchanged:=true
				for index in a.wheels.size(): wheel_unchanged=wheel_unchanged and a.wheels[index].global_transform.is_equal_approx(wheel_poses[index])
				check(wheel_unchanged,"opening the door never moves the wheels")
				a.animate_driver_door(side,false,0.0)
				check(leaf.global_transform.is_equal_approx(closed),"closing restores the exact door pose")
				door_count+=1
	check(snapshot(b.visual)==untouched_b,"door cutting never edits the shared second model")
	a.paint_color=Color("6a963b")
	check(paint_matches(a,Color("6a963b")),"repainting remains complete after door cutting")
	var healthy:=snapshot(a.visual)
	a.receive_damage(a.max_health*.55/maxf(a.damage_resistance,.05))
	check(is_equal_approx(a.health,a.max_health*.45),"damage reaches expected health through resistance")
	var worn:=false
	for mat: StandardMaterial3D in a._paint.materials: worn=worn or mat.detail_enabled
	check(worn and paint_matches(a,Color("6a963b")),"wear adds surface damage while retaining paint hue")
	a.repair()
	check(a.health==a.max_health and snapshot(a.visual)==healthy,"repair restores all materials and finishes after wear")
	a.restore_health(0.0)
	check(a.damage_look.wrecked,"terminal damage enters the wreck presentation")
	check(snapshot(b.visual)==untouched_b,"damage/wreck cannot modify another instance's shared resources")
	a.repair()
	check(a.health==a.max_health and not a.damage_look.wrecked and snapshot(a.visual)==healthy,"repair restores every batched/door surface after wreck")
	check(a.wheels.size()==centers.size(),"repair keeps the independent wheel pivots")
	check(snapshot(b.visual)==untouched_b,"repair leaves the second vehicle unchanged")
	report[id]={"checks":checks-before_checks,"failures":failures.slice(before_failures),"geometry":raw,"doors":door_count}
	print("FLEET_RED_SIGN ",id," checks=",checks-before_checks," failures=",failures.size()-before_failures)
	a.free()
	b.free()
	await process_frame

func run() -> void:
	started=Time.get_ticks_msec()
	var ids: Array=REGISTRY.MESH_COUNTS.keys()
	for arg in OS.get_cmdline_user_args():
		if arg=="--legacy": legacy=true
		elif arg.begins_with("--ids="): ids=Array(arg.trim_prefix("--ids=").split(","))
		elif arg.begins_with("--label="): label=arg.trim_prefix("--label=").validate_filename()
	REGISTRY.enabled=not legacy
	FLEET._data.clear()
	stage=Node3D.new()
	root.add_child(stage)
	var watchdog:=Timer.new()
	watchdog.wait_time=180
	watchdog.one_shot=true
	root.add_child(watchdog)
	watchdog.timeout.connect(func(): check(false,"180-second watchdog interrupted incomplete suite"); finish())
	watchdog.start()
	for id: String in ids: await inspect(id)
	stage.free()
	watchdog.stop()
	finish()

func finish() -> void:
	var folder:="res://evidence/fleet-redesign-20261011/validation"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file:=FileAccess.open(folder+"/"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"legacy":legacy,"checks":checks,"vehicles":report,"failures":failures,"elapsed_ms":Time.get_ticks_msec()-started,"scope":"resource/Vehicle integration contracts; headless is not visual/FPS certification"},"\t"))
	print("FLEET_REDESIGN ","PASS" if failures.is_empty() else "FAIL"," vehicles=",report.size()," checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
