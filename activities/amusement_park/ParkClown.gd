extends "res://gameplay/urban_v1/PortWorker.gd"
const MODEL := preload("res://world/places/amusement_park/ParkClownModel.gd")
var patrol := PackedVector3Array()
var patrol_index := 0
var travelled := 0.0
var _last_point := Vector3.ZERO

func _build_model() -> void:
	model = MODEL.new()
	model.clown_index = int(definition.get("worker_index",0))
	add_child(model)

func _ready() -> void:
	super._ready()
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("park_clown")
	_last_point = global_position
	if gameplay != null:
		var reaction = preload("res://gameplay/civilian_reactions/WorkplaceThreatReaction.gd").install(self,model,gameplay)
		if reaction != null: reaction.react_to_aim = true

func _tick_mountain_routine(_delta: float) -> void:
	travelled += Vector2(global_position.x-_last_point.x,global_position.z-_last_point.z).length()
	_last_point = global_position
	velocity.x = 0
	velocity.z = 0
	if patrol.is_empty(): return
	var offset := patrol[patrol_index]-global_position
	offset.y = 0
	if offset.length() < .22:
		patrol_index = (patrol_index+1)%patrol.size()
		return
	var direction := offset.normalized()*(1.15+.08*int(definition.get("worker_index",0)))
	velocity.x = direction.x
	velocity.z = direction.z
	activity = "walk"
