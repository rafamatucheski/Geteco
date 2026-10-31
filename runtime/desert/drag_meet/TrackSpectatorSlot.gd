extends Node3D
## A vaga do chunk sobrevive à limpeza de cadáveres para a recuperação restaurar o espectador.
var specification: Dictionary = {}
var actor: CharacterBody3D
var gameplay: Node
var world: Node3D
var reset_pending := false
func _ready() -> void:
	var ancestor := get_parent()
	while ancestor != null:
		var script = ancestor.get_script()
		if script != null and script.resource_path == "res://scripts/World.gd":
			world = ancestor
			break
		ancestor = ancestor.get_parent()
	_bind_gameplay.call_deferred()
	_spawn()
func _bind_gameplay() -> void:
	if is_instance_valid(world): gameplay = world.gameplay
	if is_instance_valid(gameplay): gameplay.changed.connect(_on_changed)
func _spawn() -> void:
	actor = preload("res://runtime/desert/drag_meet/DragStripSpectator.gd").new()
	actor.identity = int(specification.identity)
	actor.specification = specification
	actor.set_meta("region_id","desert")
	add_child(actor)
func _on_changed() -> void:
	if gameplay.health <= 0: reset_pending = true
	elif reset_pending:
		reset_pending = false
		_reset.call_deferred()
func _reset() -> void:
	if is_instance_valid(actor):
		actor.hide()
		actor.collision_layer = 0
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		actor.queue_free()
	_spawn()
