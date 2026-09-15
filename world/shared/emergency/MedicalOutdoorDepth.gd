extends Node
## Local 2.5D post compositing, independent of physical collision. One masked
## foreground sprite reuses each actor's texture; no rig copies or SubViewports.
## The support line follows the cot's floor projection rather than its sprite top.
const MASK := preload("res://world/shared/emergency/MedicalPostForeground.gdshader")
var sequence: Node
var layers := {}
var posts: Array = []
var refresh := 0.0

func _process(delta: float) -> void:
	if not is_instance_valid(sequence): return
	if sequence.phase in ["transport", "parked"]:
		for entry in layers.values():
			if is_instance_valid(entry.overlay): entry.overlay.queue_free()
		layers.clear()
		return
	refresh -= delta
	if refresh <= 0:
		refresh = .5
		posts = get_tree().get_nodes_in_group("fixed_traffic_signal")
	for entry in layers.values():
		if is_instance_valid(entry.overlay): entry.overlay.hide()
	var actors: Array = sequence.crew.duplicate()
	if is_instance_valid(sequence.stretcher): actors.append(sequence.stretcher)
	if sequence.carrying and is_instance_valid(sequence.patient): actors.append(sequence.patient)
	for actor in actors:
		if not is_instance_valid(actor) or not actor.is_visible_in_tree(): continue
		var sprite: Sprite2D
		if actor == sequence.stretcher: sprite = actor.display
		elif actor == sequence.patient: sprite = sequence.stretcher.patient_display
		else: sprite = actor.sprite_3d_display
		if not is_instance_valid(sprite) or not sprite.visible: continue
		var a: Vector2 = actor.global_position
		var b := a
		if actor == sequence.stretcher or actor == sequence.patient:
			var cot: Node2D = sequence.stretcher
			var axis := Vector2.from_angle(cot.heading)*15
			a = cot.global_position-axis
			b = cot.global_position+axis
		for post in posts:
			if not is_instance_valid(post) or not is_instance_valid(post.sprite) or post.sprite.texture == null: continue
			if post.global_position.distance_squared_to(actor.global_position) > 10000: continue
			if maxf(a.y,b.y) <= post.global_position.y: continue
			var key := "%d:%d"%[actor.get_instance_id(),post.get_instance_id()]
			if not layers.has(key):
				var overlay := Sprite2D.new()
				overlay.name = "MedicalPostForeground"
				overlay.material = ShaderMaterial.new()
				overlay.material.shader = MASK
				overlay.z_as_relative = false
				overlay.z_index = _depth(post)+1
				sprite.add_child(overlay)
				layers[key] = {"overlay":overlay}
			var overlay: Sprite2D = layers[key].overlay
			overlay.texture = sprite.texture
			overlay.centered = sprite.centered
			overlay.offset = sprite.offset
			overlay.modulate = Color.WHITE
			var inverse: Transform2D = post.sprite.global_transform.affine_inverse()
			var size: Vector2 = post.sprite.texture.get_size()
			var material: ShaderMaterial = overlay.material
			material.set_shader_parameter("post_texture",post.sprite.texture)
			material.set_shader_parameter("post_u",Vector3(inverse.x.x/size.x,inverse.y.x/size.x,inverse.origin.x/size.x+.5))
			material.set_shader_parameter("post_v",Vector3(inverse.x.y/size.y,inverse.y.y/size.y,inverse.origin.y/size.y+.5))
			material.set_shader_parameter("post_y",post.global_position.y)
			material.set_shader_parameter("support_a",a)
			material.set_shader_parameter("support_b",b)
			overlay.show()
	# Layers are temporary and bounded by proximity, even on a long response.
	for key in layers.keys():
		var overlay: Sprite2D = layers[key].overlay
		if not is_instance_valid(overlay) or not overlay.visible:
			if is_instance_valid(overlay): overlay.queue_free()
			layers.erase(key)

func _depth(item: CanvasItem) -> int:
	var result := item.z_index
	var parent := item.get_parent() as CanvasItem
	if item.z_as_relative and parent: result += _depth(parent)
	return result

func _exit_tree() -> void:
	for entry in layers.values():
		if is_instance_valid(entry.overlay): entry.overlay.queue_free()
