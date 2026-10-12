extends SceneTree
const SPEC := preload("res://gameplay/jessica/JessicaCarSpec.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const MODEL := preload("res://gameplay/jessica/JessicaModel.gd")
const NEON := preload("res://gameplay/jessica/JessicaNeon.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const FLEET_STATE := preload("res://runtime/FleetState.gd")
const RUNTIME := preload("res://runtime/JessicaRuntime.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func run() -> void:
	check_bank_anchors()
	check(FLEET.spec(SPEC.ID).get("turbo_audio",false),"cold catalogue enables existing turbo audio")
	var car := VEHICLE.new()
	car.archetype = SPEC.ID
	car.vehicle_id = SPEC.ID
	car.paint_color = Color("f1f0ea")
	root.add_child(car)
	car.set_physics_process(false)
	check(car.wheels.size() == 4,"four animated wheel pivots")
	check(car.visual.get_meta("body_doors",0) == 4,"modern four-door GLI body")
	check(car.handling.drivetrain == "fwd" and car.max_forward_speed > 30,"turbo front-wheel-drive specification")
	check(car._paint.materials.size() > 0,"ordinary paint adapter recognizes semantic body panels")
	var all_white := true
	for material in car._paint.materials:
		if material.albedo_color != Color("f1f0ea"): all_white = false
	check(all_white,"white paint reaches body panels without recoloring trim")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0,3,8)
	camera.make_current()
	var neon = NEON.install(car)
	check(NEON.install(car) == neon,"repeated restore attachment keeps a single neon")
	check(neon.find_children("*","OmniLight3D",true,false).size() == 1,"only one real underbody light")
	check(neon.strips.size() == 2 and neon.find_children("*","MeshInstance3D",true,false).size() == 3,"two strips and exactly one ground pool after repeated attachment")
	check(not neon.ground_light.shadow_enabled and neon.ground_light.omni_range < 3,"short shadowless source")
	check(neon.ground_finish.blend_mode == BaseMaterial3D.BLEND_MODE_ADD and neon.ground_finish.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED and not neon.ground_finish.no_depth_test,"ground pool preserves depth testing without writing depth")
	check(is_equal_approx(neon.ground_pool.position.y,.07) and neon.ground_pool.find_children("*","CollisionObject3D",true,false).is_empty(),"low visual pool introduces no physics body")
	check(neon.ground_finish.albedo_texture == NEON._ground_texture() and neon.ground_finish.albedo_texture.get_width() == 64,"small soft texture is shared across installs")
	neon.update(.5,camera,true,1.0)
	check(neon.strength == 0 and not neon.ground_light.visible and not neon.ground_pool.visible and neon.ground_finish.albedo_color.a == 0,"source and ground pool fully off at midday")
	neon.update(0,camera,true,1.0)
	check(neon.strength > .9 and neon.ground_light.visible and neon.ground_pool.visible and neon.ground_finish.albedo_color.a > .5,"red source and soft ground pool at night")
	var night_strength: float = neon.strength
	neon.update(.5,camera,true,.05)
	check(neon.strength > 0 and neon.strength < night_strength and neon.ground_pool.visible,"ground pool follows the existing gradual daylight fade")
	neon.update(0,camera,false,1.0)
	check(neon.strength == 0 and not neon.ground_light.visible and not neon.ground_pool.visible,"hidden region/interior emits no neon or ground pool")
	neon.update(0,camera,true,1.0)
	car.hide()
	neon.update(0,camera,true,1.0)
	check(neon.strength == 0 and not neon.ground_pool.visible,"hidden vehicle emits no ground pool")
	car.show()
	camera.position = Vector3(0,3,100)
	neon.update(0,camera,true,1.0)
	check(neon.strength == 0 and not neon.ground_pool.visible,"distant ground pool uses the source distance fade")
	camera.position = Vector3(0,3,8)
	neon.update(0,camera,true,1.0)
	car.health = 0
	neon.update(0,camera,true,1.0)
	check(neon.strength == 0 and not neon.ground_pool.visible and neon.ground_finish.albedo_color.a == 0,"destroyed car stops source and ground pool")
	car.health = 100
	var saved := FLEET_STATE.capture(car,"harbor")
	check(RUNTIME.validate_vehicle(JSON.parse_string(JSON.stringify(saved))),"saved Jetta retains native identity")
	var wrong := saved.duplicate(true)
	wrong.vehicle_id = "someone_elses_car"
	check(not RUNTIME.validate_vehicle(wrong),"another owner rejected without deleting their vehicle")
	var model := MODEL.new()
	root.add_child(model)
	check(model.wardrobe.female and model.wardrobe.build == 0 and model.wardrobe.hair == 3,"fixed slender female rig with long blonde hair")
	check(model.wardrobe.hair_color == Color("d7b969"),"hair color remains blonde across reload")
	model.set_talking(true)
	check(model.activity == "talk","dialogue uses ordinary articulated conversation pose")
	model.free()
	car.free()
	camera.free()
	await process_frame
	print("JESSICA_CAR_RESULT checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func check_bank_anchors() -> void:
	var had_document := Engine.has_meta("geteco_world_edit_document")
	var saved_document: Variant = Engine.get_meta("geteco_world_edit_document") if had_document else null
	var document := {"regions":{"harbor":{}}}
	Engine.set_meta("geteco_world_edit_document", document)
	var places := preload("res://world/places/PlaceCatalog.gd")
	var original: Dictionary = places.get_definition("harbor_bank")
	var runtime := RUNTIME.new()
	var parking: Vector3 = original.exterior_position + Vector3(0,.12,18.4)
	check(runtime._bank_parking().is_equal_approx(parking), "Jessica parking follows the authored bank position")
	check(runtime._bank_parking().is_equal_approx(parking), "repeated contact queries preserve the bank anchor")
	var origin: Vector3 = original.exterior_position
	var row := {"position":[origin.x+20.0,origin.z-10.0],"rotation":90.0,"size":[14.0,10.0],"height":5.0,
		"service_base":{"position":[origin.x,origin.z],"size":[14.0,10.0],"height":5.0}}
	document.regions.harbor["building/NorthFrontage0"] = row
	var edited: Dictionary = places.get_definition("harbor_bank")
	check(runtime._bank_parking().is_equal_approx(edited.exterior_position+Vector3(0,.12,18.4)), "live bank edit updates Jessica parking")
	runtime.session = {"state":{"campaign":{"active_id":"jessica_bank"},"world_state":{"jessica":{"bank_phase":"accepted"}}}}
	check(runtime.target_position().is_equal_approx(edited.entry_position), "accepted mission targets the edited bank entrance")
	row.position[0] += 7.0
	edited = places.get_definition("harbor_bank")
	check(runtime.target_position().is_equal_approx(edited.entry_position), "in-place editor mutation invalidates the bank anchor")
	document.regions.harbor.clear()
	check(runtime._bank_parking().is_equal_approx(parking), "removing bank override restores authored parking")
	runtime.session = null
	runtime.free()
	if had_document: Engine.set_meta("geteco_world_edit_document",saved_document)
	else: Engine.remove_meta("geteco_world_edit_document")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
