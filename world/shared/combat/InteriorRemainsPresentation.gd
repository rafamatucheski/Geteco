extends Node
## Interior fragments share the room's depth buffer and original mesh/material
## resources. Their existing 2D bodies still resolve all movement against solids.
var presentation: Node
var models := {}

func configure(actor: Node2D, remains: Node2D) -> void:
	presentation = actor.get_meta("interior_actor_presentation") if actor.has_meta("interior_actor_presentation") else null
	if not is_instance_valid(presentation): return
	for i in remains.pieces.size():
		var piece: Node2D = remains.pieces[i]
		var model: Node3D = piece.fragment_model
		presentation.room_camera.get_parent().add_child(model)
		model.scale = presentation.anchor.scale
		piece.self_modulate.a = 0
		models[piece] = model
	_process(0)

func _process(_delta: float) -> void:
	if not is_instance_valid(presentation) or not is_instance_valid(presentation.room_camera):
		queue_free()
		return
	for piece in models.keys():
		var model: Node3D = models[piece]
		if not is_instance_valid(piece):
			if is_instance_valid(model): model.queue_free()
			models.erase(piece)
			continue
		if not is_instance_valid(model): continue
		model.global_position = presentation.floor_position(piece.global_position)
		var pixels: float = presentation.pixels_per_rig_unit(Vector2.UP)
		model.rotation = piece.tumble
		model.position.y = preload("res://world/shared/combat/BodyFragmentMesh.gd").floor_offset(model) + piece.height / maxf(pixels, 1) * presentation.anchor.scale.x
		model.visible = piece.is_visible_in_tree()
		for mesh in model.get_children():
			if mesh is GeometryInstance3D: mesh.transparency = 1.0-get_parent().modulate.a

func _exit_tree() -> void:
	for model in models.values():
		if is_instance_valid(model): model.queue_free()
	models.clear()
