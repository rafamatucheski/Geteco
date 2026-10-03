extends Node
## Two instances bracket the normal main-thread callbacks; they never invoke them.
var recorder: SceneTree
var first := false

func _physics_process(_delta: float) -> void:
	if first: recorder.boundary_physics_begin()
	else: recorder.boundary_physics_end()

func _process(_delta: float) -> void:
	if not first: recorder.boundary_process_end()
