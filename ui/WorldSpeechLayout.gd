extends CanvasLayer
## One screen-space layout for moving speakers; crowded reactions share space.
const MAX_VISIBLE := 4
var entries: Array[Dictionary] = []

static func show_for(actor: Node2D, panel: PanelContainer, duration: float) -> void:
	var scene := actor.get_tree().current_scene
	if scene == null: scene = actor.get_tree().root
	var layout := scene.get_node_or_null("WorldSpeechLayout")
	if layout == null:
		layout = new()
		layout.name = "WorldSpeechLayout"
		scene.add_child(layout)
	layout.present(actor, panel, duration)

func _ready() -> void:
	layer = 24
	process_priority = 100

func present(actor: Node2D, panel: PanelContainer, duration: float) -> void:
	for entry in entries:
		if entry.panel == panel:
			entry.remaining = duration
			return
	if panel.get_parent() != self:
		panel.reparent(self, false)
		if not actor.tree_exiting.is_connected(panel.queue_free):
			actor.tree_exiting.connect(panel.queue_free, CONNECT_ONE_SHOT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.rotation = 0.0
	panel.scale = Vector2.ONE
	for child in panel.get_children():
		if child is Label:
			child.add_theme_font_size_override("font_size", 12)
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entries.append({"actor": weakref(actor), "panel": panel, "remaining": duration})
	if entries.size() > 12:
		var oldest: Dictionary = entries.pop_front()
		if is_instance_valid(oldest.panel): oldest.panel.hide()
	_process(0.0)

func _process(delta: float) -> void:
	var occupied: Array[Rect2] = []
	var speakers: Array[Vector2] = []
	var bounds := get_viewport().get_visible_rect().grow(-12.0)
	for index in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[index]
		var actor: Node2D = entry.actor.get_ref()
		var panel = entry.panel
		entry.remaining -= delta
		if not is_instance_valid(panel) or not is_instance_valid(actor):
			if is_instance_valid(panel): panel.queue_free()
			entries.remove_at(index)
			continue
		panel.hide()
		if entry.remaining <= 0.0:
			entries.remove_at(index)
			continue
		if not actor.is_visible_in_tree() or actor.get("is_dead") == true or actor.get("is_incapacitated") == true: continue
		var anchor := actor.get_global_transform_with_canvas().origin
		if not bounds.has_point(anchor) or occupied.size() >= MAX_VISIBLE: continue
		# A crowd shouting at once gets one readable reaction in its vicinity.
		var crowded := false
		for speaker in speakers:
			if speaker.distance_to(anchor) < 105.0: crowded = true
		if crowded: continue
		panel.rotation = 0.0
		panel.scale = Vector2.ONE
		panel.reset_size()
		var extent: Vector2 = panel.get_combined_minimum_size()
		var placed := false
		for offset in [Vector2(0,-42), Vector2(0,-78), Vector2(-65,-42), Vector2(65,-42)]:
			var position: Vector2 = anchor + offset - Vector2(extent.x * 0.5, extent.y)
			position.x = clampf(position.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - extent.x))
			position.y = clampf(position.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - extent.y))
			var rect := Rect2(position, extent).grow(6.0)
			var overlaps := false
			for used in occupied:
				if rect.intersects(used): overlaps = true
			if overlaps: continue
			panel.position = position
			panel.show()
			occupied.append(rect)
			speakers.append(anchor)
			placed = true
			break
		if not placed: panel.hide()
