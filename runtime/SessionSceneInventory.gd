extends RefCounted
## Incremental tree inventory, no recursive scans and no per-node records.
## Includes diagnostic nodes. Counts describe tree presence, not visibility/camera influence.
var classes: Dictionary = {}
var scripts: Dictionary = {}
var added := 0
var removed := 0
var callback_usec := 0
var overflow := 0
var tracked: Dictionary = {}
const MAX_CLASSES := 128
const MAX_DYNAMIC := 512
var _tree: SceneTree

func start(tree: SceneTree) -> void:
	_tree = tree
	tree.node_added.connect(_added)
	tree.node_removed.connect(_removed)
	# O autoload vem primeiro; só os poucos nós raiz existentes precisam ser semeados.
	_seed(tree.root)

func _seed(node: Node) -> void:
	_added(node)
	for child in node.get_children(): _seed(child)

func _added(node: Node) -> void:
	var started := Time.get_ticks_usec()
	added += 1
	var kind := node.get_class()
	if classes.has(kind) or classes.size() < MAX_CLASSES:
		classes[kind] = int(classes.get(kind, 0)) + 1
	else: overflow += 1
	var script: Variant = node.get_script()
	if script != null:
		var path := str(script.resource_path)
		if path.is_empty(): path = "<embedded-script>"
		if scripts.has(path) or scripts.size() < 512: scripts[path] = int(scripts.get(path,0)) + 1
		else: overflow += 1
	if node is Light3D or node is Light2D or node is SubViewport or node is AudioStreamPlayer or node is AudioStreamPlayer3D or node is AudioStreamPlayer2D:
		if tracked.size() < MAX_DYNAMIC: tracked[node.get_instance_id()] = weakref(node)
		else: overflow += 1
	callback_usec += Time.get_ticks_usec() - started

func _removed(node: Node) -> void:
	var started := Time.get_ticks_usec()
	removed += 1
	var kind := node.get_class()
	if classes.has(kind): classes[kind] = maxi(0, int(classes[kind]) - 1)
	var script: Variant = node.get_script()
	if script != null:
		var path := str(script.resource_path)
		if path.is_empty(): path = "<embedded-script>"
		if scripts.has(path): scripts[path] = maxi(0, int(scripts[path]) - 1)
	tracked.erase(node.get_instance_id())
	callback_usec += Time.get_ticks_usec() - started

func snapshot() -> Dictionary:
	var dynamic := {"lights_visible_in_tree":0, "lights_with_shadows_visible_in_tree":0, "subviewports_updating":0, "audio_playing":0}
	for reference: WeakRef in tracked.values():
		var node: Node = reference.get_ref()
		if not is_instance_valid(node): continue
		if node is Light3D and node.is_visible_in_tree():
			dynamic.lights_visible_in_tree += 1
			if node.shadow_enabled: dynamic.lights_with_shadows_visible_in_tree += 1
		elif node is Light2D and node.enabled and node.is_visible_in_tree():
			dynamic.lights_visible_in_tree += 1
			if node.shadow_enabled: dynamic.lights_with_shadows_visible_in_tree += 1
		elif node is SubViewport:
			if node.render_target_update_mode != SubViewport.UPDATE_DISABLED: dynamic.subviewports_updating += 1
		elif node is AudioStreamPlayer or node is AudioStreamPlayer3D or node is AudioStreamPlayer2D:
			if node.playing: dynamic.audio_playing += 1
	return {"classes":classes.duplicate(), "scripts":scripts.duplicate(), "added_total":added, "removed_total":removed, "callback_total_usec":callback_usec, "dynamic":dynamic,
		"dynamic_tracked":tracked.size(), "capacity":MAX_DYNAMIC, "omitted_total":overflow,
		"scope":"tree_inventory_not_camera_influence; dynamic_counts_lower_bound_when_omitted"}

func stop() -> void:
	if _tree.node_added.is_connected(_added): _tree.node_added.disconnect(_added)
	if _tree.node_removed.is_connected(_removed): _tree.node_removed.disconnect(_removed)
	tracked.clear()
