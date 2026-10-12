extends "res://world/places/NativePlace.gd"
## The visual cutaway never removes the enclosure seen by projectiles.
func _ready() -> void:
	super._ready()
	for body in solid_bodies:
		var id := str(body.get_meta("interior_solid_id", ""))
		if not (id.begins_with("BackWall") or id.begins_with("FrontWall") or id.begins_with("SideWall")): continue
		var shape: CollisionShape3D = body.get_child(0)
		shape.shape.size.y = 3.4
		shape.position.y = 1.7
		var bounds: AABB = body.get_meta("bounds")
		bounds.size.y = 3.4
		body.set_meta("bounds", bounds)
	# Not a floor obstacle: actors walk below the slab; grenades hit its underside.
	_box_solid("CulvertCeiling", AABB(Vector3(-20.5, 3.2, -5.5), Vector3(41, .3, 11)), false)
