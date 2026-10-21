extends RigidBody3D
## A detached panel owns its frozen appearance. It never damages people or blocks traffic.
## Timers belong to this body and pause with the scene; no permanent global update loop.
const MAX_ACTIVE := 18
const LIFETIME := 22.0
static var _active: Array[WeakRef] = []
var panel_mesh: MeshInstance3D
var panel_id := ""
var source_vehicle_id := ""
var _retiring := false

func _ready() -> void:
	add_to_group("vehicle_panel_debris")
	_prune()
	while _active.size() >= MAX_ACTIVE:
		var oldest: Variant = _active.pop_front().get_ref()
		if is_instance_valid(oldest): oldest.retire()
	_active.append(weakref(self))
	var expiry := Timer.new()
	expiry.one_shot = true
	expiry.wait_time = LIFETIME
	add_child(expiry)
	expiry.timeout.connect(retire)
	expiry.start()

static func _prune() -> void:
	for index in range(_active.size()-1,-1,-1):
		var body: Variant = _active[index].get_ref()
		if not is_instance_valid(body) or body.is_queued_for_deletion(): _active.remove_at(index)

func retire() -> void:
	if _retiring: return
	_retiring = true
	freeze = true
	collision_layer = 0
	collision_mask = 0
	var fade := create_tween()
	if is_instance_valid(panel_mesh): fade.tween_property(panel_mesh,"transparency",1.0,.45)
	fade.tween_callback(queue_free)

func _exit_tree() -> void:
	# Clear renderer slots before native destruction releases copied material refs.
	if is_instance_valid(panel_mesh):
		panel_mesh.set_base(RID())
	for index in range(_active.size()-1,-1,-1):
		if _active[index].get_ref() == self: _active.remove_at(index)
