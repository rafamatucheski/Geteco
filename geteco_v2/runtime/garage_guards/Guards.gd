extends Node3D
const POINTS := [Vector3(7.3,.04,5.7),Vector3(-8,.04,1)]
var garage
var actors: Array[CharacterBody3D]=[]
var records: Array=[]
func configure(owner_garage) -> void:
	garage=owner_garage
func active() -> bool:
	return garage!=null and garage.session.ready_for_play and garage.session.state.place_id=="port_boss_garage" and is_instance_valid(garage.session.room)
func alerted() -> bool:
	return garage.data.police_called or garage.data.alarm_remaining>=0
func gameplay(): return garage.session.world.gameplay
func target() -> Node3D:
	return garage.session.world.driving.car if garage.session.world.driving.occupied else garage.session.world.player
func sync() -> void:
	if not active():
		capture()
		for actor in actors:
			if is_instance_valid(actor): actor.queue_free()
		actors.clear()
		return
	if records.is_empty():
		for point in POINTS: records.append({"health":50.0,"position":[point.x,point.y,point.z],"clip":12,"reload":0.0})
	if actors.size()==2: return
	for index in range(actors.size(),2):
		var record: Dictionary=records[index]
		var point: Vector3=garage.session.room.global_position+Vector3(record.position[0],record.position[1],record.position[2])
		if record.health>0 and not garage.session.position_clear(point): break
		var actor=preload("res://runtime/garage_guards/Guard.gd").new()
		actor.manager=self
		actor.health=record.health
		actor.clip=int(record.clip)
		actor.reload_remaining=record.reload
		actor.position=point
		actor.set_meta("room_origin",garage.session.room.global_position)
		add_child(actor)
		actors.append(actor)
func injured(source: Node) -> void:
	if is_instance_valid(source) and (source==garage.session.world.player or source==garage.session.world.driving.car): garage.raise_alarm()
	capture()
	garage.session.save_game()
func capture() -> void:
	for index in actors.size():
		var actor=actors[index]
		if not is_instance_valid(actor): continue
		var point: Vector3=actor.global_position-actor.get_meta("room_origin",Vector3.ZERO)
		records[index]={"health":actor.health,"position":[point.x,point.y,point.z],"clip":actor.clip,"reload":actor.reload_remaining}
func snapshot() -> Array:
	capture()
	return records.duplicate(true)
func restore(saved: Array) -> bool:
	if not validate(saved): return false
	for actor in actors:
		if is_instance_valid(actor): actor.queue_free()
	actors.clear()
	records=saved.duplicate(true)
	return true
static func validate(saved: Variant) -> bool:
	if not saved is Array or saved.size() not in [0,2]: return false
	for record in saved:
		if not record is Dictionary: return false
		for key in ["health","clip","reload"]:
			if typeof(record.get(key)) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(record[key])): return false
		if record.health<0 or record.health>50 or record.clip<0 or record.clip>12 or record.clip!=floorf(record.clip) or record.reload<0 or record.reload>1.691875: return false
		if not record.get("position") is Array or record.position.size()!=3: return false
		for value in record.position:
			if typeof(value) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(value)) or absf(float(value))>100: return false
	return true
