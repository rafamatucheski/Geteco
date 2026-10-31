extends SceneTree
## Directed runtime ownership fixtures. Main covers physical admission/return;
## these fixtures isolate interruptions without waiting for unrelated services.
const RUNTIME := preload("res://runtime/upside_world/UpsideWorldRuntime.gd")
const OWNER := &"upside_world_owner"
var checks := 0
var failures: Array[String] = []

class CameraFixture extends Camera3D:
	var initialized := true

class PlayerFixture extends CharacterBody3D:
	var visual := Node3D.new()
	var camera: Camera3D
	var input_locked := false
	var controlled_automatically := true
	var automatic_direction := Vector3.ZERO
	func teleport(point: Vector3) -> void: global_position = point

class GameplayFixture extends Node:
	var health := 83.0
	var enabled := true

class DrivingFixture extends Node:
	var occupied := false

class WineFixture extends Node:
	var recoveries := 0
	func recover() -> void: recoveries += 1

class WorldFixture extends Node3D:
	var player: PlayerFixture
	var camera: CameraFixture
	var gameplay: GameplayFixture
	var driving: DrivingFixture
	var hud: Control

class SessionFixture extends Node:
	var world: WorldFixture
	var ready_for_play := false
	var rescue_pending := false
	var arrest_pending := false
	var owner_token := 41
	var transition_generation := 41
	var transition_kind := "upside_world"
	var finishes := 0
	var clear_point := true
	var permitted_point := Vector3.INF
	var modal := false
	var state := {"place_id":"harbor_haunted_house","region_id":"harbor"}
	var room: Node3D
	var wine: WineFixture
	func _owns_transition(expected: int) -> bool: return expected == owner_token and expected > 0
	func _finish_transition(expected: int) -> void:
		if _owns_transition(expected): owner_token = 0; transition_kind = ""; finishes += 1
	func position_clear(point: Vector3) -> bool: return clear_point and (not permitted_point.is_finite() or point.distance_to(permitted_point)<.01)

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("UPSIDE_CLEANUP ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func fixture() -> Dictionary:
	var scene := WorldFixture.new()
	root.add_child(scene)
	scene.player = PlayerFixture.new()
	scene.add_child(scene.player)
	scene.player.add_child(scene.player.visual)
	scene.camera = CameraFixture.new()
	scene.camera.environment = Environment.new()
	scene.add_child(scene.camera)
	scene.gameplay = GameplayFixture.new()
	scene.add_child(scene.gameplay)
	scene.driving = DrivingFixture.new()
	scene.add_child(scene.driving)
	scene.hud = Control.new()
	scene.add_child(scene.hud)
	var session := SessionFixture.new()
	session.world = scene
	session.wine = WineFixture.new()
	scene.add_child(session.wine)
	session.room = Node3D.new()
	scene.add_child(session.room)
	scene.add_child(session)
	var runtime = RUNTIME.new()
	runtime.configure(session)
	session.add_child(runtime)
	runtime.set_process(false)
	runtime._token = 41
	runtime._entry_room = session.room
	runtime.active = true
	runtime.state.active = true
	runtime.state.duration = 12.0
	runtime.state.elapsed = 5.0
	runtime.view = Camera3D.new()
	runtime.add_child(runtime.view)
	runtime.view.make_current()
	runtime.arena = Node3D.new()
	scene.add_child(runtime.arena)
	runtime.veil = CanvasLayer.new()
	runtime.add_child(runtime.veil)
	runtime._saved = {"point":Vector3(3,.08,4),"locked":false,"visual_visible":true,"hud_visible":true,"player_camera":scene.camera,"camera":scene.camera,"gameplay_enabled":true,"mouse":Input.MOUSE_MODE_VISIBLE,"automatic":true,"automatic_direction":Vector3.FORWARD,"physics":true,"layer":2,"mask":7,"weapon":"pistol","health":83.0}
	scene.player.camera = runtime.view
	scene.player.global_position = Vector3(0,.08,-3400)
	scene.player.input_locked = true
	scene.player.controlled_automatically = false
	scene.player.visual.hide()
	scene.player.set_physics_process(false)
	scene.hud.hide()
	scene.gameplay.enabled = false
	for owner in [scene.player,scene.hud,scene.gameplay]: owner.set_meta(OWNER,41)
	return {"scene":scene,"session":session,"runtime":runtime}

func assert_cleared(data: Dictionary,label: String) -> void:
	check(not data.runtime.busy() and not data.runtime.state.active and data.runtime.state.pending_entry == 0,label + " clears active and pending state")
	check(not is_instance_valid(data.runtime.arena) and not is_instance_valid(data.runtime.view) and not is_instance_valid(data.runtime.veil),label + " releases only owned nodes")
	check(not data.scene.player.has_meta(OWNER) and not data.scene.hud.has_meta(OWNER) and not data.scene.gameplay.has_meta(OWNER),label + " clears stale ownership metadata")

func run() -> void:
	var data := fixture()
	var environment: Environment = data.scene.camera.environment
	data.runtime.cancel("load")
	assert_cleared(data,"ordinary cancellation")
	check(data.scene.player.global_position == Vector3(3,.08,4) and not data.scene.player.input_locked,"owner cancellation returns the living actor and releases its own lock")
	check(data.scene.player.visual.visible and data.scene.hud.visible and data.scene.gameplay.enabled,"owner cancellation restores its prior presentation")
	check(data.scene.player.controlled_automatically and data.scene.player.is_physics_processing() and data.scene.player.collision_layer == 2 and data.scene.player.collision_mask == 7,"owner cancellation restores control mode and physics flags")
	check(root.get_camera_3d() == data.scene.camera and data.scene.player.camera == data.scene.camera and data.scene.camera.environment == environment,"owner cancellation restores camera without mutating the source environment")
	check(data.session.owner_token == 0 and data.session.finishes == 1,"owner cancellation finishes exactly its own transition")
	check(data.runtime.get_meta("end_reason","") == "load","cancellation records its actual end reason")
	data.runtime.cancel("duplicate")
	check(data.session.finishes == 1 and data.runtime.get_meta("end_reason","") == "load","duplicate cleanup cannot finish another transition or erase its reason")
	data.scene.queue_free()
	await process_frame

	data = fixture()
	data.session.owner_token = 42
	var new_camera := CameraFixture.new()
	data.scene.add_child(new_camera)
	new_camera.make_current()
	data.scene.player.camera = new_camera
	data.scene.player.global_position = Vector3(8,.08,9)
	data.scene.player.collision_layer = 4
	data.scene.player.collision_mask = 13
	data.runtime.cancel("new_owner",false)
	assert_cleared(data,"foreign-owner interruption")
	check(data.session.owner_token == 42 and data.session.finishes == 0,"cleanup cannot release the next transition owner's token")
	check(data.scene.player.input_locked and not data.scene.player.is_physics_processing() and not data.scene.player.controlled_automatically,"cleanup preserves the next owner's input and physics locks")
	check(not data.scene.player.visual.visible and not data.scene.hud.visible and not data.scene.gameplay.enabled,"cleanup does not clobber the next owner's visibility or gameplay state")
	check(data.scene.player.global_position == Vector3(8,.08,9) and data.scene.player.collision_layer == 4 and data.scene.player.collision_mask == 13,"cleanup does not teleport or replace collision flags owned by a new transition")
	check(root.get_camera_3d() == new_camera and data.scene.player.camera == new_camera,"cleanup cannot steal an already replaced camera")
	data.scene.queue_free()
	await process_frame

	for cause in ["death","arrest"]:
		data = fixture()
		if cause == "death":
			data.scene.gameplay.health = 0.0
			data.session.rescue_pending = true
		else: data.session.arrest_pending = true
		var before: Vector3 = data.scene.player.global_position
		var health: float = data.scene.gameplay.health
		data.runtime.cancel(cause,false)
		assert_cleared(data,cause)
		check(data.scene.player.global_position == before and data.scene.player.input_locked,cause + " does not move or unlock the actor owned by recovery")
		check(data.scene.gameplay.health == health and data.session.owner_token == 0,cause + " leaves health authority to the real recovery flow")
		data.scene.queue_free()
		await process_frame

	data = fixture()
	data.runtime._returning = true
	data.session.clear_point = false
	var blocked_point: Vector3 = data.scene.player.global_position
	check(not data.runtime.release_for_return(41) and data.session.owner_token == 41 and data.scene.player.global_position == blocked_point,"blocked original room refuses return release without moving the player or clearing the token")
	# Foreign token rejection happens before reading live-room geometry.
	check(not data.runtime.release_for_return(40) and data.session.owner_token == 41 and data.runtime.busy(),"stale return callback cannot release or alter an active illusion")
	data.session.owner_token = 42
	check(not data.runtime.release_for_return(41) and data.session.owner_token == 42,"return callback that lost ownership cannot release the next transition")
	data.runtime.cancel("return_interrupted",false)
	assert_cleared(data,"interrupted return")
	data.scene.queue_free()
	await process_frame

	data = fixture()
	data.session.clear_point = false
	data.scene.player.set_physics_process(true)
	var held_arena: Node3D = data.runtime.arena
	var held_point: Vector3 = data.scene.player.global_position
	data.runtime.cancel("all_room_points_occupied")
	check(data.runtime.busy() and data.runtime._safe_return_pending and data.session.owner_token == 41,"fully blocked cancellation retains the original transition authority")
	check(data.runtime.arena == held_arena and not held_arena.is_queued_for_deletion() and data.scene.player.global_position == held_point,"fully blocked cancellation keeps physical arena under the visitor")
	check(data.scene.player.input_locked and data.scene.player.is_physics_processing() and not data.scene.gameplay.enabled,"blocked retry preserves physical support and combat exclusion")
	check(is_instance_valid(data.runtime._safe_notice) and data.runtime._safe_notice.visible,"blocked return presents a visible functional waiting notice")
	data.session.clear_point = true
	data.session.ready_for_play = true
	data.runtime._process(1.1)
	assert_cleared(data,"safe-room retry")
	check(data.scene.player.global_position == Vector3(3,.08,4) and data.session.owner_token == 0 and not data.scene.player.input_locked,"next safe retry relocates before freeing floor and releasing controls")
	data.scene.queue_free()
	await process_frame

	data = fixture()
	data.runtime._returning = true
	data.session.permitted_point = data.session.room.to_global(Vector3(0,.08,5.4))
	check(data.runtime.release_for_return(41) and data.scene.player.global_position == data.session.permitted_point,"blocked original point falls back to a validated authored house route point")
	check(data.runtime._return_generation == 42 and data.runtime.owns(41),"release predicts precisely one subsequent departure generation")
	check(not data.runtime.finish_return(41),"finish cannot run before ordinary departure actually occurs")
	data.session.transition_generation = 42
	data.session.transition_kind = "leave_place"
	check(data.runtime.owns(41) and not data.runtime.finish_return(41),"held departure generation is recognized but cannot finish mid-transition")
	data.session.transition_kind = ""
	check(not data.runtime.finish_return(41),"a completed token alone cannot finish while room and interior location remain")
	for next_generation in [43,44]:
		check(data.runtime.prepare_departure_retry(41) and data.runtime._handoff_generation == next_generation - 1 and data.runtime._return_generation == next_generation,"blocked departure renews only its owned generation for attempt " + str(next_generation - 41))
		check(not data.runtime.prepare_departure_retry(40) and data.runtime._return_generation == next_generation,"foreign callback cannot renew the pending departure")
		data.session.transition_generation = next_generation
		data.session.transition_kind = "leave_place"
		check(data.runtime.owns(41) and not data.runtime.prepare_departure_retry(41),"in-flight retry holds its new generation and cannot renew again")
		data.session.transition_kind = ""
	check(data.runtime.busy() and data.session.wine.recoveries == 0 and is_instance_valid(data.runtime.veil),"two refused departures keep one live illusion, its veil and intoxication until actual exterior success")
	data.session.state.place_id = ""
	data.session.room = null
	data.session.permitted_point = Vector3.INF
	data.scene.player.global_position = Vector3(20,.08,18)
	check(data.runtime.finish_return(41) and data.session.wine.recoveries == 1,"exact completed exterior departure finishes and sobers once")
	check(data.runtime.get_meta("end_reason","") == "returned","successful final departure records returned after retries")
	assert_cleared(data,"generation-matched departure")
	data.scene.queue_free()
	await process_frame

	data = fixture()
	data.runtime._returning = true
	check(data.runtime.release_for_return(41),"released-owner fixture begins a real handoff")
	data.session.transition_generation = 43
	data.session.owner_token = 43
	data.session.transition_kind = "rescue"
	data.scene.player.input_locked = true
	check(not data.runtime.owns(41) and not data.runtime.prepare_departure_retry(41) and not data.runtime.finish_return(41) and data.session.wine.recoveries == 0,"released illusion cannot retry, approve or recover over a later owner generation")
	data.session.transition_kind = ""
	check(not data.runtime.prepare_departure_retry(41),"a finished foreign generation also cannot be adopted as our retry")
	data.session.transition_kind = "rescue"
	data.session.ready_for_play = true
	data.runtime._process(.1)
	assert_cleared(data,"released foreign owner")
	check(data.session.owner_token == 43 and data.scene.player.input_locked,"handoff interruption keeps the next owner's token and lock")
	data.scene.queue_free()
	await process_frame

	# Amostragem semeada fixa e finita testa a política de seleção sem exigir
	# que voltas dependentes do trânsito vivo continuem tentando até os destinos diferirem.
	var selection = RUNTIME.new()
	selection._rng.seed = 20261007
	var first: Array[Vector3] = selection.return_candidates()
	selection._rng.seed = 20261007
	check(first == selection.return_candidates(),"return shuffling is reproducible with an explicitly seeded generator")
	var observed := {}
	var original: Array[Vector3] = preload("res://runtime/upside_world/UpsideReturnPoints.gd").candidates()
	for sample in 8:
		var candidates: Array[Vector3] = selection.return_candidates()
		check(candidates.size() == original.size() and candidates.all(func(point): return point in original),"shuffle preserves the authored candidate set " + str(sample))
		if not candidates.is_empty(): observed[str(candidates[0])] = true
	check(observed.size() > 1,"fixed eight-draw sequence offers varying authored destinations")
	selection.free()
	print("UPSIDE_CLEANUP_RESULT checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
