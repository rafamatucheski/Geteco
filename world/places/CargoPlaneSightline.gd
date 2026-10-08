extends RefCounted
## Recorte local da carcaça: não altera a câmera global nem os sólidos do avião.
var plane: Node3D
var revealed := false
var port_open := false
var starboard_open := false
var _camera: Camera3D

func _init(owner_plane: Node3D) -> void:
	plane = owner_plane

func update(camera: Camera3D) -> void:
	var next := false
	var port := false
	var starboard := false
	if camera != null and &"target" in camera and is_instance_valid(camera.get("target")):
		var target: Node3D = camera.get("target")
		var at := plane.to_local(target.global_position)
		# Histerese evita recortes oscilando na borda do acesso. A área cabe no
		# lago original; não mantém o avião aberto em outro ambiente/carro.
		var margin := 1.0 if revealed else 0.0
		var walking := not &"max_forward_speed" in target
		var unlocked: bool = not (&"locked" in camera and camera.get("locked"))
		next = walking and unlocked and target.is_visible_in_tree() and absf(at.x)<4.8+margin and at.z>-16.8-margin and at.z<12.0+margin and at.y>-.7 and at.y<3.0
		if next:
			var eye := plane.to_local(camera.global_position)
			port = eye.x<-.3
			starboard = eye.x>.3
	if next:
		if _camera!=camera:
			release()
			_camera=camera
			_camera.set_meta("cargo_plane_view",plane.get_instance_id())
	else: release()
	if next==revealed and port==port_open and starboard==starboard_open: return
	revealed=next; port_open=port; starboard_open=starboard
	plane.model.set_cutaway(revealed)
	plane.model.set_side_cutaway(-1,port_open)
	plane.model.set_side_cutaway(1,starboard_open)
	for part in plane._roof_parts: part.visible=not revealed

func release() -> void:
	if is_instance_valid(_camera) and _camera.get_meta("cargo_plane_view",0)==plane.get_instance_id():
		_camera.remove_meta("cargo_plane_view")
	_camera=null
