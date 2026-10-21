@tool
extends Node
## Free a large passive hierarchy in bounded slices instead of one editor frame.
var pending: Array = []
var keep_alive := true

static func install(reference: WeakRef, tree: SceneTree) -> void:
	var collector: Node = reference.get_ref()
	if not is_instance_valid(collector): return
	if tree == null or tree.root == null:
		collector.free()
		return
	tree.root.add_child(collector)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func take(node: Node) -> void:
	if not is_instance_valid(node): return
	if node is Node3D: node.hide()
	if node.get_parent() != self:
		if node.get_parent() != null: node.reparent(self,false)
		else: add_child(node)
	pending.append([node,false])
	set_process(true)

func _process(_delta: float) -> void:
	var began := Time.get_ticks_usec()
	while not pending.is_empty() and Time.get_ticks_usec()-began < 2500:
		var entry: Array = pending.pop_back()
		var node: Node = entry[0]
		if not is_instance_valid(node): continue
		if not entry[1]:
			pending.append([node,true])
			for child in node.get_children(): pending.append([child,false])
		else: node.free()
	if pending.is_empty():
		if not keep_alive and get_child_count() == 0: queue_free()
		elif not keep_alive: pass # A child may still be collecting a threaded read.
		else: set_process(false)
