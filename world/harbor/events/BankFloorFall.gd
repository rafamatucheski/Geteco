extends "res://CharacterFallPresentation.gd"
## No banco, a projeção dos atores precisa continuar igual à do piso.
func update(delta: float) -> void:
	super.update(delta)
	if is_instance_valid(camera):
		camera.transform=camera_transform
		camera.size=camera_size
		camera.fov=camera_fov
