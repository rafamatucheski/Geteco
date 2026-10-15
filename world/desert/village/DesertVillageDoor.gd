extends "res://world/places/WalkupFacadeDoor.gd"
## Streamed with its facade; the shared access controller owns push and timing.
## Casa pintada (PaintedFacadeKit) passa o tamanho do vão em "door_size" e o plano
## da parede em "door_z" para a folha ocupar o vão pintado em vez do da casa 3D.
func _ready() -> void:
	add_to_group("v2_walkin_facade")
	var size: Vector2 = get_meta("door_size", Vector2(1.16, 2.26))
	var w := size.x
	var h := size.y
	hinge = Node3D.new()
	hinge.position = Vector3(-w * .5, 0, float(get_meta("door_z", 4.24)))
	add_child(hinge)
	var geometry := preload("res://world/desert/DesertGeometry.gd")
	geometry.box(hinge,"Door",Vector3(w * .5,.06 + h * .5,0),Vector3(w,h,.08),Color("796047"),true)
	var style := str(get_meta("door_style", ""))
	if style.is_empty():
		geometry.box(hinge,"Panel",Vector3(w * .5,.78,.05),Vector3(w * .74,.78,.025),Color("896d50"))
		geometry.box(hinge,"Handle",Vector3(w * .84,1.13,.07),Vector3(.065,.16,.07),Color("737778"))
	else:
		# Folha com a mesma pintura da porta do estilo, por fora e por dentro.
		for part in ["door_front", "door_front_inside"]:
			var face := MeshInstance3D.new()
			face.name = "Painted_" + part
			var quad := QuadMesh.new()
			quad.size = Vector2(w, h)
			face.mesh = quad
			var inside: bool = part.ends_with("inside")
			face.position = Vector3(w * .5, .06 + h * .5, -.045 if inside else .045)
			if inside: face.rotation.y = PI
			face.material_override = PaintedFacadeKit.material(style, part)
			hinge.add_child(face)
	set_open_amount(0.0)
