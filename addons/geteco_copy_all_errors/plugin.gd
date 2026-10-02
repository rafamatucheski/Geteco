@tool
extends EditorPlugin
## Editor only. Never selects, expands, clears or modifies debugger entries.

const OWNER_META := &"geteco_copy_all_errors_owner"

var _base: Control
var _actions: HBoxContainer
var _button: Button
var _feedback: Label
var _watcher: Timer
var _error_tree: Tree
var _candidates: Array[Tree] = []
var _discovery_pending := true
var _owns_ui := false
var _feedback_until := 0


func _enter_tree() -> void:
	_base = EditorInterface.get_base_control()
	if _base.has_meta(OWNER_META):
		var previous: Object = instance_from_id(int(_base.get_meta(OWNER_META)))
		if is_instance_valid(previous):
			return
	_base.set_meta(OWNER_META, get_instance_id())
	_owns_ui = true
	_create_actions()
	_base.get_tree().node_added.connect(_on_node_added)
	_watcher = Timer.new()
	_watcher.wait_time = 1.0
	_watcher.timeout.connect(_refresh)
	add_child(_watcher)
	_watcher.start()
	call_deferred("_refresh")


func _create_actions() -> void:
	_actions = HBoxContainer.new()
	_actions.name = "GetecoCopyAllErrors"
	_button = Button.new()
	_button.text = "Copiar todos"
	_button.tooltip_text = "Copia todas as entradas desta sessão, incluindo detalhes recolhidos."
	_button.pressed.connect(_copy_all)
	_actions.add_child(_button)
	_feedback = Label.new()
	_actions.add_child(_feedback)


func _exit_tree() -> void:
	if not _owns_ui:
		return
	if is_instance_valid(_base):
		if _base.get_tree().node_added.is_connected(_on_node_added):
			_base.get_tree().node_added.disconnect(_on_node_added)
		if _base.get_meta(OWNER_META, 0) == get_instance_id():
			_base.remove_meta(OWNER_META)
	if is_instance_valid(_watcher):
		_watcher.stop()
	if is_instance_valid(_actions):
		if _actions.get_parent() != null:
			_actions.get_parent().remove_child(_actions)
		_actions.free()


func _on_node_added(node: Node) -> void:
	if node is Tree or node.get_class() == "ScriptEditorDebugger":
		_discovery_pending = true


func _refresh() -> void:
	if not _owns_ui or not is_instance_valid(_base):
		return
	# Discover only at startup or when debugger structure changes. No frame loop.
	if _discovery_pending:
		_discovery_pending = false
		_candidates.clear()
		_find_error_trees(_base, _candidates)
	var target: Tree = null
	for candidate in _candidates:
		if not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
			continue
		if target == null:
			target = candidate
		if candidate.is_visible_in_tree():
			target = candidate
			break
	if target == null:
		return
	# A closed debugger session may have freed the toolbar's children.
	if not is_instance_valid(_actions):
		_create_actions()
	_attach(target)
	_button.disabled = _entry_count(target) == 0
	if Time.get_ticks_msec() >= _feedback_until:
		_feedback.text = ""


func _find_error_trees(node: Node, result: Array[Tree]) -> void:
	if node is Tree and _is_error_tree(node):
		result.append(node)
		return
	for child in node.get_children(true):
		_find_error_trees(child, result)


func _is_error_tree(tree: Tree) -> bool:
	if tree.columns != 2 or not tree.hide_root:
		return false
	var panel: Node = tree.get_parent()
	if not panel is VBoxContainer or not panel.get_parent() is TabContainer:
		return false
	if _toolbar(tree) == null:
		return false
	# Independent of translated labels. Inspect callables, never invoke them.
	# Internal UI is not a stable API: fail closed if this structure changes.
	for connection in tree.get_signal_connection_list("item_selected"):
		var callback: Callable = connection["callable"]
		var method_name := str(callback.get_method())
		if method_name == "_error_selected" or method_name.ends_with("::_error_selected"):
			var receiver: Object = callback.get_object()
			if is_instance_valid(receiver) and receiver.get_class() == "ScriptEditorDebugger":
				return true
	return false


func _toolbar(tree: Tree) -> HBoxContainer:
	for sibling in tree.get_parent().get_children():
		if sibling is HBoxContainer:
			var buttons := 0
			for child in sibling.get_children():
				if child is Button:
					buttons += 1
			if buttons >= 3:
				return sibling
	return null


func _attach(tree: Tree) -> void:
	var toolbar: HBoxContainer = _toolbar(tree)
	if toolbar == null:
		return
	if _actions.get_parent() != toolbar:
		if _actions.get_parent() != null:
			_actions.get_parent().remove_child(_actions)
		toolbar.add_child(_actions)
		toolbar.move_child(_actions, 2)
	_error_tree = tree
	if _base.has_theme_icon("ActionCopy", "EditorIcons"):
		_button.icon = _base.get_theme_icon("ActionCopy", "EditorIcons")


func _entry_count(tree: Tree) -> int:
	var root: TreeItem = tree.get_root()
	if root == null:
		return 0
	var count := 0
	var entry: TreeItem = root.get_first_child()
	while entry != null:
		count += 1
		entry = entry.get_next()
	return count


## Read-only serialization: no clipboard access, count only root-level entries.
func serialize_errors(tree: Tree) -> Dictionary:
	var blocks := PackedStringArray()
	var root: TreeItem = tree.get_root()
	if root == null:
		return {"count": 0, "text": ""}
	var entry: TreeItem = root.get_first_child()
	while entry != null:
		var lines := PackedStringArray()
		var kind := "Entrada"
		if entry.has_meta("_is_warning"):
			kind = "Aviso"
		elif entry.has_meta("_is_error"):
			kind = "Erro"
		lines.append("[%d] %s" % [blocks.size() + 1, kind])
		_append_rows(entry, tree.columns, 0, lines)
		blocks.append("\n".join(lines))
		entry = entry.get_next()
	if blocks.is_empty():
		return {"count": 0, "text": ""}
	var heading := "GETECO — Depurador — %d entradas\n\n" % blocks.size()
	return {"count": blocks.size(), "text": heading + "\n\n".join(blocks)}


func _append_rows(item: TreeItem, columns: int, depth: int, lines: PackedStringArray) -> void:
	var cells := PackedStringArray()
	var locations := PackedStringArray()
	for column in range(columns):
		var text: String = item.get_text(column)
		if not text.is_empty():
			cells.append(text)
		# Godot stores full script paths and line numbers as [file, line].
		var metadata: Variant = item.get_metadata(column)
		if metadata is Array and metadata.size() >= 2:
			if metadata[0] is String and (metadata[1] is int or metadata[1] is float):
				var location := "%s:%s" % [metadata[0], metadata[1]]
				if not locations.has(location):
					locations.append(location)
	var indent := "  ".repeat(depth)
	if not cells.is_empty():
		lines.append(indent + " | ".join(cells))
	for location in locations:
		if not " | ".join(cells).contains(location):
			lines.append(indent + "  Arquivo/linha: " + location)
	# 4.7.2 tooltips repeat the complete subtree in both columns. Export the
	# canonical rows once regardless of collapsed state, without tooltips.
	var child: TreeItem = item.get_first_child()
	while child != null:
		_append_rows(child, columns, depth + 1, lines)
		child = child.get_next()


func _copy_all() -> void:
	if not is_instance_valid(_error_tree):
		_show_feedback("Painel indisponível")
		return
	var report: Dictionary = serialize_errors(_error_tree)
	if int(report["count"]) == 0:
		_show_feedback("Nenhuma entrada")
		return
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		_show_feedback("Clipboard indisponível")
		return
	DisplayServer.clipboard_set(str(report["text"]))
	_show_feedback("%d entradas copiadas" % int(report["count"]))


func _show_feedback(message: String) -> void:
	_feedback.text = message
	_feedback_until = Time.get_ticks_msec() + 5000
