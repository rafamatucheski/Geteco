extends "res://runtime/CashierBaseModel.gd"

func _ready() -> void:
	appearance_locked = true
	appearance_variant = 11
	coat_color = Color("485b70")
	super._ready()
	set_meta("standing_rig_height", 1.8)
	scale = Vector3(.82,.95,.90)

func part(parent: Node3D, point: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var piece := super.part(parent,point,size,color)
	if size.y > .35 or size.z > size.y * 1.5:
		piece.mesh = preload("res://assets/regions/source/guns/ammunation/AmmunationArt.gd").bevel_box(size)
		# The old sphere used node scale for dimensions; the tailored mesh
		# already carries them, so retaining that scale shrinks each part twice.
		piece.scale = Vector3.ONE
	return piece
