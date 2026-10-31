extends SceneTree
## Contrato focado de posse/interrupção. Acesso real, horizonte e FPS são medidos
## à parte na sessão de produção renderizada, não certificados por esta fixture.
const BINOCULARS := preload("res://runtime/coastal_lookout/CoastalBinoculars.gd")

class TestPlayer extends CharacterBody3D:
	var input_locked := false
	var ski_controller: Node
	var visual: Node3D

class TestCamera extends Camera3D:
	var locked := false

class TestSession extends Node:
	var ready_for_play := true
	var modal := false
	var rebinding_action := ""
	var transition_generation := 0
	var state := {"region_id":"harbor", "place_id":""}
	var transition_blocked := false
	func is_transition_blocked() -> bool: return transition_blocked
	func blocks_driving_change() -> bool: return transition_blocked

class TestGameplay extends Node:
	var health := 100.0

class TestDriving extends Node:
	var occupied := false

class TestWorld extends Node3D:
	var player: TestPlayer
	var camera: TestCamera
	var session: TestSession
	var driving: TestDriving
	var gameplay: TestGameplay
	var hud: CanvasLayer

class TestLookout extends Node3D:
	func binocular_interaction_position() -> Vector3: return Vector3(1, 10, 1)
	func binocular_eye_position() -> Vector3: return Vector3(1, 11.5, 0)
	func binocular_target_position() -> Vector3: return Vector3(-180, 38, -900)

var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	print(("PASS " if value else "FAIL ") + message)
	if not value: failures.append(message)

func event(action: String) -> InputEventAction:
	var result := InputEventAction.new()
	result.action = action
	result.pressed = true
	return result

func run() -> void:
	var stage := TestWorld.new()
	root.add_child(stage)
	stage.player = TestPlayer.new()
	stage.camera = TestCamera.new()
	stage.session = TestSession.new()
	stage.gameplay = TestGameplay.new()
	stage.driving = TestDriving.new()
	stage.hud = CanvasLayer.new()
	for child in [stage.player, stage.camera, stage.session, stage.gameplay, stage.driving, stage.hud]: stage.add_child(child)
	stage.player.visual = Node3D.new()
	stage.player.add_child(stage.player.visual)
	stage.camera.make_current()
	stage.camera.environment = Environment.new()
	stage.camera.environment.fog_enabled = true
	stage.camera.environment.fog_depth_begin = 18.0
	stage.camera.environment.fog_depth_end = 75.0
	var lookout := TestLookout.new()
	stage.add_child(lookout)
	var viewer = BINOCULARS.new()
	stage.add_child(viewer)
	viewer.configure(stage, lookout)
	stage.player.position = lookout.binocular_interaction_position() - Vector3(0, 10, 0)
	check(viewer.nearest_action().is_empty() and not viewer.enter(), "Binocular cannot be used through the terrace from below")
	stage.player.position = lookout.binocular_interaction_position()
	stage.driving.occupied = true
	check(not viewer.enter(), "A driver cannot use the pedestrian optic")
	stage.driving.occupied = false
	stage.player.input_locked = true
	check(not viewer.enter(), "Another owner of player input is respected")
	stage.player.input_locked = false
	check(viewer.nearest_action().get("id") == "coastal_binoculars", "Walking up exposes functional interaction")
	var previous_transform: Transform3D = stage.camera.transform
	var previous_mouse: int = Input.mouse_mode
	check(viewer.enter(), "Eligible interaction opens binoculars")
	check(stage.player.input_locked and stage.player.has_meta("coastal_binoculars_active"), "Movement and combat ownership are marked")
	check(viewer.optical_camera.current and not stage.camera.current, "Dedicated optical camera becomes current")
	check(viewer.optical_camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "Horizon is viewed with a perspective optic")
	check(viewer.optical_camera.environment.fog_depth_end >= 1400.0, "Panoramic depth fog allows distant coast visibility")
	check(is_equal_approx(stage.camera.environment.fog_depth_end,75.0), "Optical fog range never alters street atmosphere")
	check(stage.player.position.is_equal_approx(lookout.binocular_interaction_position()), "Using the optic does not teleport the player")
	var desired: Vector3 = (lookout.binocular_target_position() - lookout.binocular_eye_position()).normalized()
	check((-viewer.optical_camera.global_basis.z).dot(desired) > 0.999, "Initial direction faces the authored desert target")
	viewer.look_delta(Vector2(99, -99))
	check(absf(viewer.yaw) <= BINOCULARS.MAX_YAW and viewer.pitch <= BINOCULARS.MAX_PITCH, "Optical head clamps yaw and elevation")
	viewer.adjust_zoom(-999)
	check(is_equal_approx(viewer.optical_camera.fov, BINOCULARS.FOV_CLOSE), "Zoom cannot exceed optical limit")
	viewer.adjust_zoom(999)
	check(is_equal_approx(viewer.optical_camera.fov, BINOCULARS.FOV_WIDE), "Zoom returns to its wide limit")
	check(viewer.handle_input(event("fire")), "Combat input is consumed by optical mode")
	var emulated := InputEventMouseButton.new()
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	emulated.button_index = MOUSE_BUTTON_LEFT
	emulated.pressed = true
	check(not viewer.handle_input(emulated) and viewer.active,"Touch-emulated button clicks reach the optical GUI")
	var held_interaction := InputEventKey.new()
	held_interaction.physical_keycode = KEY_E
	held_interaction.pressed = true
	held_interaction.echo = true
	check(viewer.handle_input(held_interaction) and viewer.active,"Holding the interaction key does not close observation on repeat")
	check(viewer.handle_input(event("interact")) and not viewer.active, "Interact closes the optic")
	check(not stage.player.input_locked and not stage.player.has_meta("coastal_binoculars_active"), "Normal exit releases owned movement and combat guards")
	check(stage.camera.current and stage.camera.transform == previous_transform and not stage.camera.locked, "Normal exit restores the original camera without changing its transform")
	check(stage.hud.visible and stage.player.visual.visible and Input.mouse_mode == previous_mouse, "Normal exit restores HUD, model and pointer mode")
	check(viewer.enter(), "Optic can be entered again")
	check(not viewer.handle_input(event("pause_game")) and not viewer.active, "Pause closes optic and remains available to PauseInput")
	check(viewer.enter(), "Optic reenters after pause cancellation")
	paused = true
	viewer._process(0.02)
	check(not viewer.active and not stage.player.input_locked and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "External pause releases input and keeps menu pointer visible")
	paused = false
	check(viewer.enter(), "Optic reenters after external pause")
	stage.gameplay.health = 90
	viewer._process(0.02)
	check(not viewer.active and not stage.player.input_locked, "Incoming damage cancels viewing and restores control")
	check(viewer.enter(), "Optic reenters after damage")
	stage.session.modal = true
	viewer._process(0.02)
	check(not viewer.active and stage.player.input_locked, "A newly opened modal retains its input lock")
	stage.session.modal = false
	stage.player.input_locked = false
	check(viewer.enter(), "Optic reenters after modal")
	stage.player.position.x += 3.0
	viewer._process(0.02)
	check(not viewer.active and not stage.player.input_locked, "External displacement safely cancels viewing")
	stage.player.position = lookout.binocular_interaction_position()
	check(viewer.enter(), "Optic reenters after displacement")
	stage.session.transition_generation += 1
	viewer._process(0.02)
	check(not viewer.active, "A new transition generation invalidates observation")
	check(viewer.enter(), "Optic reenters before death interruption")
	stage.gameplay.health = 0
	viewer._process(0.02)
	check(not viewer.active and stage.player.input_locked and not stage.player.has_meta("coastal_binoculars_active"), "Death preserves recovery lock and removes observation ownership")
	stage.queue_free()
	await process_frame
	print("COASTAL BINOCULARS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
