extends RefCounted

## Keeps the street resident for a seamless return, but runs the sewer in its
## own World2D. No scene-wide audio bus is muted: Dante/UI remain audible.
var viewport: SubViewport
var layer: CanvasLayer
var street: Node2D
var actor_parent: Node
var process_states: Dictionary = {}
var timers: Dictionary = {}
var sounds: Dictionary = {}
var sound_volumes: Dictionary = {}
var canvases: Dictionary = {}
var active := false
var street_visible := true
var actor: Node2D
var controller: Node
var player_camera_enabled := true

func build(owner: Node, room: Node2D) -> void:
	controller = owner
	layer = CanvasLayer.new()
	layer.name = "SewerInstanceView"
	layer.layer = 40
	layer.hide()
	owner.add_child(layer)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_PASS
	layer.add_child(container)
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport = SubViewport.new()
	viewport.name = "IsolatedSewerWorld"
	viewport.world_2d = World2D.new()
	viewport.disable_3d = false # Dante still owns his small 3D character view.
	viewport.audio_listener_enable_2d = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	container.add_child(viewport)
	room.reparent(viewport, true)
	var camera := Camera2D.new()
	camera.name = "SewerCamera"
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	room.add_child(camera)
	camera.position = Vector2(100, 17)
	camera.zoom = Vector2.ONE * 2.072
	camera.make_current()
	var listener := AudioListener2D.new()
	listener.name = "SewerListener"
	room.add_child(listener)
	listener.make_current()

func enter(player: Node2D, room: Node2D) -> void:
	if active: return
	active = true
	actor = player
	street = controller.get_tree().current_scene as Node2D
	actor_parent = player.get_parent()
	player.reparent(room, true)
	player.set_meta("combat_scene_root", room)
	player.set_meta("isolated_interior", true)
	player.set_meta("interior_return_position", controller.global_position)
	player.set_meta("police_exterior_position", controller.global_position)
	var camera := player.get_node_or_null("Camera") as Camera2D
	if camera:
		player_camera_enabled = camera.enabled
		camera.enabled = false
	room.get_node("SewerCamera").make_current()
	controller.process_mode = Node.PROCESS_MODE_PAUSABLE
	_freeze(street)
	for singleton in ["PresentationBudget", "WantedManager", "EmergencyPool", "CityAudioManager", "TrafficLightManager", "NPCMedicalCare", "WorldRenewal", "DistrictRestriction", "RegionTravel"]:
		var service := controller.get_node_or_null("/root/" + singleton)
		if service != null: _freeze(service)
	_apply_suspension()
	street_visible = street.visible
	# The opaque sewer viewport covers the street. Do not toggle visibility on
	# the whole district: hundreds of cached prop views rebuild on visibility
	# notifications, causing a multi-second first frame on return.
	viewport.audio_listener_enable_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	layer.show()
	controller.get_tree().node_added.connect(_on_node_added)

func _freeze(node: Node) -> void:
	if node == controller or node == actor: return
	if node.name in ["HUD", "PauseMenu"]:
		return
	# Suspend script work/input, not the engine's physics-space membership or
	# render visibility. Restoring a district-wide disabled subtree caused a
	# broadphase/view rebuild. The two World2D instances already isolate bodies.
	if not process_states.has(node):
		var flags := [node.is_processing(), node.is_physics_processing(), node.is_processing_input(), node.is_processing_unhandled_input()]
		if true in flags: process_states[node] = flags
	if node is Timer and not timers.has(node): timers[node] = node.paused
	if node is CanvasLayer:
		if not canvases.has(node): canvases[node] = node.visible
		node.hide()
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		if not sounds.has(node): sounds[node] = node.stream_paused
		if not sound_volumes.has(node): sound_volumes[node] = node.volume_db
	for child in node.get_children(): _freeze(child)

func _apply_suspension() -> void:
	for node in process_states:
		if is_instance_valid(node):
			node.set_process(false)
			node.set_physics_process(false)
			node.set_process_input(false)
			node.set_process_unhandled_input(false)
	for timer in timers:
		if is_instance_valid(timer): timer.paused = true
	for node in sounds:
		if is_instance_valid(node):
			node.stream_paused = true
			node.volume_db = -80.0

func _on_node_added(node: Node) -> void:
	# A pending surface timer can finish while the room is active.
	if active and street.is_ancestor_of(node) and not controller.is_ancestor_of(node) and node != actor:
		_suspend_added.call_deferred(node.get_instance_id())

func _suspend_added(instance_id: int) -> void:
	var node := instance_from_id(instance_id) as Node
	if active and is_instance_valid(node):
		_freeze(node)
		_apply_suspension()

func leave() -> void:
	if not active: return
	active = false
	if controller.get_tree().node_added.is_connected(_on_node_added):
		controller.get_tree().node_added.disconnect(_on_node_added)
	if is_instance_valid(actor) and is_instance_valid(actor_parent):
		actor.reparent(actor_parent, true)
		for key in ["combat_scene_root", "isolated_interior", "interior_return_position", "police_exterior_position"]:
			actor.remove_meta(key)
		var camera := actor.get_node_or_null("Camera") as Camera2D
		if camera:
			camera.enabled = player_camera_enabled
			if camera.enabled: camera.make_current()
			camera.reset_smoothing()
	for node in process_states:
		if is_instance_valid(node):
			var flags: Array = process_states[node]
			node.set_process(flags[0])
			node.set_physics_process(flags[1])
			node.set_process_input(flags[2])
			node.set_process_unhandled_input(flags[3])
	for timer in timers:
		if is_instance_valid(timer): timer.paused = timers[timer]
	for node in sounds:
		if is_instance_valid(node):
			node.stream_paused = sounds[node]
			node.volume_db = sound_volumes[node]
	for node in canvases:
		if is_instance_valid(node): node.visible = canvases[node]
	process_states.clear()
	timers.clear()
	sounds.clear()
	sound_volumes.clear()
	canvases.clear()
	viewport.audio_listener_enable_2d = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	layer.hide()

func dispose() -> void:
	leave()
	if is_instance_valid(layer): layer.queue_free()
