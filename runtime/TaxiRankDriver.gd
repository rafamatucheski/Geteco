extends "res://gameplay/urban_v1/UrbanRoutineActor.gd"
## Native damage/collision contract, with a short sidewalk escape on threats.
func notice_threat(origin: Vector3, radius: float) -> void:
	super.notice_threat(origin,radius)
	if frightened and not dead: flee(origin)

func flee(origin: Vector3) -> void:
	if dead: return
	frightened = true
	var direction := 1.0 if position.x >= origin.x else -1.0
	set_route(PackedVector3Array([position+Vector3(direction*8,0,0)]))
