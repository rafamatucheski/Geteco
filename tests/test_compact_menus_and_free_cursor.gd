extends SceneTree
## UI geometry and real input/settings contracts; no render or personal save writes.
var failures: Array[String] = []
var checks := 0
class PreviewWorld extends Node3D:
	var session: Node
	var player: Node3D
class DamageTarget extends CharacterBody3D:
	var dead := false
class Feedback extends Node:
	var camera: Camera3D
	var point := Vector3.ZERO
	var blocked := false
	func aim_feedback_active() -> bool: return true
	func hitmarker_active() -> bool: return false
	func aim_feedback() -> Dictionary: return {"point":point,"blocked":blocked}
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func settle() -> void:
	for frame in 5: await process_frame
func run() -> void:
	var settings := root.get_node("V2Settings")
	var controls := root.get_node("GameInput")
	if settings.default_path().begins_with("user://"):
		push_error("Requires --isolated-save-root"); quit(2); return
	DirAccess.make_dir_recursive_absolute(settings.default_path().get_base_dir())
	controls.reset_bindings()
	check(not settings.controller_aim_assist,"controller assistance defaults to disabled")
	var world := PreviewWorld.new()
	root.add_child(world)
	var pause := preload("res://ui/PauseMenu.tscn").instantiate()
	pause.world = world
	root.add_child(pause)
	pause.visible = true
	var menu: Control = pause.settings
	for dimensions: Vector2i in [Vector2i(800,600),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(3440,1440)]:
		root.content_scale_size = dimensions
		root.size = dimensions
		await settle()
		var panel: Control = pause.get_node("RootControl/CenterPanel")
		check(panel.size.x <= 761 and panel.size.y <= 681,"pause bounded at "+str(dimensions))
		check(panel.get_rect().get_center().distance_to(Vector2(dimensions)*.5)<2,"pause centered at "+str(dimensions))
		pause.open_settings()
		await settle()
		check(menu._panel.size.x <= 1041 and menu._panel.size.y <= 741,"settings bounded at "+str(dimensions))
		check(menu._panel.get_rect().get_center().distance_to(Vector2(dimensions)*.5)<14,"settings centered at "+str(dimensions))
		check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(menu._panel.get_global_rect()),"settings stays inside screen at "+str(dimensions))
		menu._select_tab(2)
		menu._choose_control_mode(0)
		await settle()
		check(menu._widgets.controller_aim_assist.is_visible_in_tree(),"aim assistance discoverable in keyboard mode at "+str(dimensions))
		check(menu._widgets.controller_aim_assist.focus_mode == Control.FOCUS_ALL,"aim assistance accessible by gamepad focus")
		for index in [0,1]:
			menu._choose_control_mode(index)
			await settle()
			for button: Button in menu._controls_list.find_children("*","Button",true,false):
				if not button.is_visible_in_tree(): continue
				var bounds := button.get_global_rect()
				check(bounds.position.x>=menu._panel.position.x and bounds.end.x<=menu._panel.get_global_rect().end.x,"binding columns stay inside compact panel")
		menu.close()
		for name in ["AchievementsModal","CollectiblesModal"]:
			var modal: Control = pause.get_node("RootControl/"+name)
			modal.show()
			await settle()
			check(modal.size.x <= 1041 and modal.size.y <= 741 and Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(modal.get_global_rect()),name+" stays compact at "+str(dimensions))
			modal.hide()
		pause.guide.open()
		await settle()
		var guide_frame: Control = pause.guide.get_node("GuidePanelFrame")
		check(guide_frame.size.x <= 1041 and guide_frame.size.y <= 741 and Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(guide_frame.get_global_rect()),"guide stays compact at "+str(dimensions))
		pause.guide.close()
	menu.show()
	menu.open()
	menu._select_tab(2)
	var assist: CheckButton = menu._widgets.controller_aim_assist
	assist.button_pressed = true
	check(settings.controller_aim_assist,"assist toggle applies immediately")
	menu.close()
	check(not settings.controller_aim_assist,"cancel restores disabled assistance")
	menu.show()
	menu.open()
	assist.button_pressed = true
	menu._save()
	settings.controller_aim_assist = false
	check(settings.load_settings() == OK and settings.controller_aim_assist,"assistance survives save/reload")
	menu.show()
	menu.open()
	menu._select_tab(2)
	menu._restore_tab_defaults()
	check(not settings.controller_aim_assist,"controls defaults disable assistance")
	menu._save()
	pause.free()
	world.free()
	var stage := Node3D.new()
	root.add_child(stage)
	var feedback := Feedback.new()
	stage.add_child(feedback)
	feedback.camera = Camera3D.new()
	stage.add_child(feedback.camera)
	feedback.camera.position = Vector3(0,10,10)
	feedback.camera.look_at(Vector3.ZERO)
	feedback.camera.current = true
	var reticle := preload("res://ui/AimReticle.gd").new()
	reticle.gameplay = feedback
	stage.add_child(reticle)
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(.2,.1)
	controls.using_gamepad = true
	controls.observe_event(mouse)
	check(not controls.using_gamepad,"subpixel mouse movement takes aiming ownership")
	for assisted in [false,true]:
		settings.controller_aim_assist = assisted
		for blocked in [false,true]:
			feedback.blocked = blocked
			feedback.point = Vector3(4,1,1) if blocked else Vector3(-4,1,-4)
			reticle._process(0)
			check(reticle.position.distance_to(root.get_mouse_position())<.01,"mouse reticle follows cursor with assist="+str(assisted)+" blocked="+str(blocked))
	var joy := InputEventJoypadButton.new()
	joy.pressed = true
	joy.device = 0
	joy.button_index = JOY_BUTTON_A
	controls.observe_event(joy)
	reticle._process(0)
	check(controls.using_gamepad and reticle.position.distance_to(feedback.camera.unproject_position(feedback.point))<.01,"gamepad retains projected feedback marker")
	# The same actual input/controller path responds to its persisted opt-in setting.
	var actor := CharacterBody3D.new()
	stage.add_child(actor)
	var target := DamageTarget.new()
	target.collision_layer = 2
	var shape_node := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .3
	capsule.height = 1.7
	shape_node.shape = capsule
	shape_node.position.y = .85
	target.add_child(shape_node)
	target.add_to_group("v2_damageable")
	stage.add_child(target)
	target.position = Vector3(10,0,-.5)
	for frame in 3: await physics_frame
	var axis := InputEventJoypadMotion.new()
	axis.device = 0
	axis.axis = JOY_AXIS_RIGHT_X
	axis.axis_value = 1.0
	controls.observe_event(axis)
	controls.aim_direction = Vector2.RIGHT
	settings.controller_aim_assist = false
	var manual: Vector3 = controls.aim_target_3d(actor,feedback.camera,.1,false)
	controls.aim_direction = Vector2.RIGHT
	settings.controller_aim_assist = true
	var assisted: Vector3 = controls.aim_target_3d(actor,feedback.camera,.1,false)
	check(manual.distance_to(Vector3.RIGHT*25)<.001,"disabled controller assistance keeps exact stick direction near a target")
	check(assisted.distance_to(manual)>.01,"enabled controller assistance makes the optional correction")
	controls.observe_event(mouse)
	reticle._process(0)
	check(not controls.using_gamepad and reticle.position.distance_to(root.get_mouse_position())<.01,"mouse immediately retakes free cursor from assisted controller")
	Input.action_press("aim")
	var camera := preload("res://scripts/CameraRig.gd").new()
	stage.add_child(camera)
	var orbit := InputEventAction.new()
	orbit.action = "camera_drag"
	orbit.pressed = true
	camera._unhandled_input(orbit)
	check(not camera.mouse_orbit_active() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED,"aiming does not capture or freeze mouse for camera orbit")
	Input.action_release("aim")
	stage.free()
	print("COMPACT_FREE_CURSOR checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
