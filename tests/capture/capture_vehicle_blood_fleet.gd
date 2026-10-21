extends SceneTree
const FLEET := preload("res://runtime/FleetCatalog.gd")
const BLOOD := preload("res://gameplay/vehicle_effects/VehicleBlood.gd")
var stage: Node3D
var camera: Camera3D
var folder := "res://artifacts/vehicle-blood-fleet/before"
var only_bikes := false
func _initialize() -> void: run.call_deferred()
static func roster() -> Array:
	var ids: Array = FLEET.all().keys()
	ids.append_array(preload("res://gameplay/desert_cars/DesertCarCatalog.gd").IDS)
	ids.append_array(preload("res://gameplay/mining/MiningFleet.gd").IDS)
	ids.append_array(["cobra_boss_ironback","desert_cargo_truck","biarticulated_510","armored_truck","jessica_jetta_gli","digo_amarok_2014","digo_gol_1993"])
	var unique: Array = []
	for id in ids:
		if id not in unique: unique.append(id)
	unique.sort()
	return unique
func shot(path: String) -> void:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): folder="res://artifacts/vehicle-blood-fleet/"+arg.trim_prefix("--label=").validate_filename()
		if arg == "--bikes": only_bikes=true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(800,600))
	root.content_scale_size=Vector2i(800,600)
	OS.low_processor_usage_mode=false
	stage=Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color(.18,.20,.22)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE
	env.environment.ambient_light_energy=.65
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-45,-35,0)
	stage.add_child(sun)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	var reports: Array = []
	for id in roster():
		if only_bikes and not id.begins_with("bike_"): continue
		var car = preload("res://gameplay/dispatch/DispatchVehicle.gd").new() if id.begins_with("police_") or id=="bike_police" else preload("res://scripts/Vehicle.gd").new()
		car.archetype=id
		car.vehicle_id="blood_review_"+id
		car.traffic=true
		stage.add_child(car)
		car.set_physics_process(false)
		car.set_process(false)
		var spec := FLEET.spec(id)
		var size: Array = spec.bounds_size
		var length := float(size[2])
		camera.size=maxf(3.2,length*1.1)
		var focus := Vector3(0,float(size[1])*.42,0)
		var row := {"id":id,"bounds":size,"meshes":0,"overlays":0,"rider_overlays":0}
		for view in [{"tag":"front","mask":1,"offset":Vector3(-1,.65,-1)},{"tag":"rear","mask":2,"offset":Vector3(1,.65,1)},{"tag":"left","mask":4,"offset":Vector3(-1,.65,-.25)},{"tag":"right","mask":8,"offset":Vector3(1,.65,.25)}]:
			camera.position=focus+view.offset*length
			camera.look_at(focus)
			var tag: String = view.tag
			car.restore_blood_stains(0)
			await shot(folder+"/"+id+"_"+tag+"_clean.png")
			car.restore_blood_stains(int(view.mask))
			await shot(folder+"/"+id+"_"+tag+"_blood.png")
		for part in car.visual.find_children("*","MeshInstance3D",true,false):
			row.meshes+=1
			if part.material_overlay is ShaderMaterial and part.material_overlay.shader==BLOOD.SHADER:
				row.overlays+=1
				if part.get_meta("motorcycle_rider",false) or part.skin != null: row.rider_overlays+=1
		reports.append(row)
		print("BLOOD_FLEET ",id," ",row.overlays,"/",row.meshes)
		car.free()
		await process_frame
	FileAccess.open(folder+"/inventory.json",FileAccess.WRITE).store_string(JSON.stringify(reports,"\t"))
	stage.free()
	quit()

