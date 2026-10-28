extends SceneTree
## Presentation fixture only: real Sede facade at the two exterior CameraRig
## angles. This does not certify streaming, navigation or performance.
const RIG := preload("res://scripts/CameraRig.gd")
const DEST := "res://artifacts/bars-20261027/facade"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEST))
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1280,720)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	stage.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color("c4ac84")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("f2e3c7")
	settings.ambient_light_energy=.6
	environment.environment=settings
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-48,-30,0)
	sun.light_energy=1.0
	sun.shadow_enabled=true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size=Vector2(100,100)
	ground.mesh=plane
	ground.position.y=-.01
	var sand := StandardMaterial3D.new()
	sand.albedo_color=Color("c6a570")
	sand.roughness=1.0
	ground.material_override=sand
	stage.add_child(ground)
	stage.add_child(preload("res://world/places/bars/DesertBarFacade.gd").new())
	var actor := preload("res://scripts/Actor.gd").new()
	actor.is_player=true
	actor.controlled_automatically=true
	actor.position=Vector3(0,.04,9.8)
	stage.add_child(actor)
	actor.set_physics_process(false)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=24
	camera.far=140
	stage.add_child(camera)
	camera.current=true
	var focus := actor.position+Vector3.UP
	var records := []
	for preview in [false,true]:
		var offset: Vector3=RIG.PREVIEW_OFFSET.rotated(Vector3.UP,RIG.PREVIEW_HEADING) if preview else RIG.EXTERIOR_OFFSET
		camera.position=focus+offset
		camera.look_at(focus)
		for frame in 12: await process_frame
		await RenderingServer.frame_post_draw
		var name := "sede-preview-final.png" if preview else "sede-exterior-final.png"
		viewport.get_texture().get_image().save_png(DEST.path_join(name))
		records.append({"file":name,"camera_offset":str(offset),"focus":str(focus),"size":camera.size})
	FileAccess.open(DEST.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"purpose":"Facade name legibility only","renderer":RenderingServer.get_current_rendering_method(),"viewport":"1280x720","records":records},"\t"))
	print("BAR_FACADE_CAPTURE saved two real facade views")
	stage.free()
	viewport.free()
	await process_frame
	quit(0)
