extends SceneTree
## Prévia renderizada isolada de sala nativa: sala de produção, Coyote, painel e
## câmera de serviço. Não sobe o Main, não exercita admissão nem mede FPS.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const ADAPTER := preload("res://gameplay/desert_cars/DesertCarAdapter.gd")
const APPEARANCE := preload("res://gameplay/desert_cars/TuningAppearance.gd")
const PANEL := preload("res://gameplay/desert_cars/DesertTuningPanel.gd")
const DRIVE := preload("res://runtime/desert/DigoWorkshopDrive.gd")
const TUNED := {"paint":"paint_ocean","finish":"finish_satin","spoiler":"spoiler_sport","sunroof":"sunroof_glass","taillights":"taillights_amber","wheel_model":"wheel_mesh","wheel_size":"wheel_size_sport","wheels":"wheels_bronze","neon":"neon_cyan"}
var destination := "res://artifacts/digo-workshop-refresh-20261019/native-preview"
var failures: Array[String] = []
var captures: Array = []
var stage: Node3D
var panel: CanvasLayer
var helper: Node3D
var car: CharacterBody3D

class ServiceSession extends RefCounted:
	var room: Node3D
	var state := {"place_id":"desert_digo","region_id":"desert"}
	var ready_for_play := false
	var message := ""
	func show_message(value: String) -> void: message = value

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> bool:
	print("DIGO_NATIVE_PREVIEW ","PASS " if ok else "FAIL ",message)
	if not ok: failures.append(message)
	return ok

func _frames(count: int) -> void:
	for frame in count: await process_frame

func _capture(name: String) -> void:
	await _frames(12)
	await RenderingServer.frame_post_draw
	var path := destination.path_join(name+".png")
	var result := root.get_texture().get_image().save_png(path)
	_check(result==OK,"native-room preview saved: "+name)
	captures.append({"name":name,"path":path,"scope":"isolated native-room fixture; not Main; no FPS claim"})

func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Native preview requires a rendered viewport; headless cannot produce visual evidence")
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out-dir="): destination = argument.trim_prefix("--out-dir=")
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination)) != OK:
		push_error("Native preview output directory unavailable")
		quit(2)
		return
	create_timer(120).timeout.connect(func(): push_error("Native preview finite 120s deadline exceeded"); quit(3))
	root.size = Vector2i(1280,720)
	DisplayServer.window_set_size(Vector2i(1280,720))
	var watermark := root.get_node_or_null("BuildWatermark")
	if watermark is CanvasLayer: watermark.hide()
	var settings := root.get_node_or_null("V2Settings")
	if settings != null and is_instance_valid(settings.get("_fps_layer")): settings.get("_fps_layer").visible = false
	stage = Node3D.new()
	stage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	var look := Environment.new()
	look.background_mode = Environment.BG_COLOR
	look.background_color = Color("9da9ad")
	look.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	look.ambient_light_color = Color("d9dce0")
	look.ambient_light_energy = .55
	environment.environment = look
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-25,0)
	sun.light_color = Color("fff1dc")
	sun.light_energy = .8
	stage.add_child(sun)
	var session := ServiceSession.new()
	session.room = PLACES.create_place("desert_digo")
	if not _check(session.room!=null,"PlaceCatalog creates the actual refreshed desert_digo room"):
		stage.free(); quit(1); return
	session.room.position = Vector3(0,0,-2400)
	stage.add_child(session.room)
	var normal_camera := Camera3D.new()
	normal_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	normal_camera.size = session.room.camera_size
	normal_camera.near = .05
	normal_camera.far = 100.0
	stage.add_child(normal_camera)
	normal_camera.global_position = session.room.camera_target+Vector3(0,18,15)
	normal_camera.look_at(session.room.camera_target)
	normal_camera.make_current()
	car = VEHICLE.new()
	car.archetype = "desert_coyote"
	car.vehicle_id = "native_refresh_preview_coyote"
	car.paint_color = Color("284d79")
	stage.add_child(car)
	car.set_physics_process(false)
	car.set_process(false)
	car.place(session.room.to_global(Vector3(0,.12,0)),PI)
	car.ensure_equipment(stage).set_process(false)
	ADAPTER.attach(car,TUNED)
	panel = PANEL.new()
	root.add_child(panel)
	helper = DRIVE.new()
	stage.add_child(helper)
	helper.configure(session)
	helper.set_physics_process(false)
	for frame in 3: await physics_frame
	if not _check(helper.open_service_view(car),"Production service camera and physical shutter admit the actual centred Coyote"):
		panel.free(); stage.free(); quit(1); return
	helper.set_process(false)
	panel.view_requested.connect(helper.focus_slot)
	panel.camera_action.connect(helper.camera_action)
	panel.orbit_requested.connect(helper.orbit_by)
	panel.preview_requested.connect(func(parts: Dictionary): APPEARANCE.preview_vehicle(car,parts))
	panel.set_live_vehicle(car)
	panel.show_vehicle(ADAPTER.profile_of(car),TUNED,TUNED.values(),9,100000,{"archetype":car.archetype,"paint":car.paint_color})
	panel.show_visual_menu()
	helper.camera_action("reset",0.0)
	await _capture("day-service")
	panel._select_slot("sunroof")
	await _capture("roof-options")
	panel._select_slot("taillights")
	await _capture("rear-taillights")
	panel.hide()
	helper.close_service_view()
	normal_camera.make_current()
	await _frames(3)
	await _capture("room-normal")
	_check(helper._camera==null and helper._service_shutter==null and helper._service_walls.is_empty(),"Fixture cleanup restores the native room and releases the service camera/shutter")
	var file := FileAccess.open(destination.path_join("manifest.json"),FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"scope":"Isolated native desert_digo room, actual Vehicle/DesertTuningPanel and DigoWorkshopDrive service view. This is not Main gameplay, admission validation, temporal lighting validation or an FPS benchmark.","engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"resolution":[1280,720],"ambient":.55,"sun":.8,"vehicle":"desert_coyote","yaw":PI,"parts":TUNED,"session_fixture":"ServiceSession RefCounted; ready_for_play=false; production transitions disabled","driver":"No actor fixture: these images show the room, vehicle and UI only.","captures":captures,"failures":failures},"\t"))
	panel.free()
	stage.free()
	await _frames(3)
	print("DIGO_NATIVE_PREVIEW failures=",failures," output=",destination)
	quit(0 if failures.is_empty() else 1)
