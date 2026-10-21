extends Node
## Developer-only view residency. Keeps the regular streaming/build budget and actor admission.
var world: Node3D
var _region: Node3D
var _enabled := false
var _elapsed := 0.0
var _instances: Dictionary = {}
var _overlay: CanvasLayer
var _progress: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func start() -> void:
	if _enabled: return
	_enabled = true
	get_tree().node_added.connect(_node_added)
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		_override_range(node)
		stack.append_array(node.get_children())
	set_process(true)
	_elapsed = .25
	if _overlay == null:
		_overlay = CanvasLayer.new()
		_overlay.layer = 105
		add_child(_overlay)
		_progress = Label.new()
		_progress.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_progress.offset_left = -250
		_progress.offset_right = 250
		_progress.offset_top = 48
		_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_progress.add_theme_color_override("font_shadow_color", Color.BLACK)
		_progress.add_theme_constant_override("shadow_offset_x", 2)
		_progress.add_theme_constant_override("shadow_offset_y", 2)
		_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay.add_child(_progress)
	_overlay.show()

func stop() -> void:
	if not _enabled: return
	_enabled = false
	if _overlay != null: _overlay.hide()
	set_process(false)
	if get_tree().node_added.is_connected(_node_added): get_tree().node_added.disconnect(_node_added)
	if is_instance_valid(_region) and _region.is_inside_tree(): _region.set_developer_view(Rect2(), false)
	_region = null
	for reference in _instances.values():
		var node = reference.get_ref()
		if is_instance_valid(node) and node.is_inside_tree():
			RenderingServer.instance_geometry_set_visibility_range(node.get_instance(), node.visibility_range_begin,
				node.visibility_range_end, node.visibility_range_begin_margin, node.visibility_range_end_margin, node.visibility_range_fade_mode)
	_instances.clear()

func _node_added(node: Node) -> void:
	if node is GeometryInstance3D: _override_deferred.call_deferred(weakref(node))

func _override_deferred(reference: WeakRef) -> void:
	var node = reference.get_ref()
	if _enabled and is_instance_valid(node): _override_range(node)

func _override_range(node: Node) -> void:
	if not node is GeometryInstance3D or not world.is_ancestor_of(node): return
	if node.visibility_range_end <= 0: return
	_instances[node.get_instance_id()] = weakref(node)
	# Override the rendering instance, never the authored properties: chunk merging
	# must still copy the real ranges, and restoration must not change shared materials.
	RenderingServer.instance_geometry_set_visibility_range(node.get_instance(), node.visibility_range_begin,
		0.0, node.visibility_range_begin_margin, node.visibility_range_end_margin, node.visibility_range_fade_mode)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < .25: return
	_elapsed = 0.0
	var next: Node3D = world.production.get("region")
	if next != _region:
		if is_instance_valid(_region) and _region.is_inside_tree(): _region.set_developer_view(Rect2(), false)
		_region = next
	if is_instance_valid(_region) and _region.has_method("set_developer_view"):
		_region.set_developer_view(world.camera.developer_ground_rect(), true, true)
		var waiting := {}
		for key in _region.developer_view_cells:
			if not _region.chunks.has(key): waiting[key] = true
		for job in _region.build_jobs:
			if _region.developer_view_cells.has(job.key): waiting[job.key] = true
		var total: int = _region.developer_view_cells.size()
		_progress.text = "Carregando mapa inteiro · %d/%d trechos" % [total-waiting.size(), total]
		_progress.visible = not waiting.is_empty()
		# Do not retain weak-reference entries for chunks that were streamed away.
		for id in _instances.keys():
			if _instances[id].get_ref() == null: _instances.erase(id)

func _exit_tree() -> void: stop()
