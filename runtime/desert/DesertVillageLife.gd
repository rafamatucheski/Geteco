extends Node
## Só a casa ocupada de Santa Lua tem um morador ativo. Salas vazias não
## retêm rigs, física nem animação; o relógio salvo do mundo é dono da ocupação.
const HOMES := preload("res://world/desert/village/DesertVillageHomes.gd")
const RESIDENT := preload("res://runtime/desert/DesertVillageResident.gd")
var session
var resident: CharacterBody3D
var active_room: Node3D
var active_home := ""
var admission_failure := ""
var _clock := 0.0
var _suppressed_room: WeakRef
var _suppressed_home := ""

func configure(owner_session) -> void:
	session=owner_session
	name="DesertVillageLife"

static func night_at(hour: float) -> bool:
	var wrapped := fposmod(hour,1.0)
	return wrapped<.25 or wrapped>=.75

func _process(delta: float) -> void:
	_clock+=delta
	if _clock<.25: return
	_clock=0
	reconcile()

func reconcile() -> void:
	if session==null or not session.ready_for_play or not is_instance_valid(session.weather):
		_clear(); return
	var id: String=str(session.state.place_id)
	var room: Node3D=session.room
	if id not in HOMES.IDS or session.state.region_id!="desert" or not night_at(float(session.weather.time_of_day)) or not is_instance_valid(room) or not room.is_visible_in_tree() or not bool(room.get("active")):
		_clear(); return
	if session.is_transition_blocked():
		_clear(); return
	# A limpeza de cadáveres não pode virar ressurreição na sala ocupada.
	# Sair ou amanhecer encerra esta visita; nenhum esquema de save compartilhado está envolvido.
	if _suppressed_home==id and _suppressed_room!=null and _suppressed_room.get_ref()==room: return
	if active_room==room and active_home==id and is_instance_valid(resident): return
	_clear()
	var data: Dictionary=HOMES.home_data(id)
	var spec: Dictionary=data.get("resident_data",{})
	if spec.is_empty(): admission_failure="missing_resident_data"; return
	var placement := _placement(room,spec)
	if placement.is_empty(): return
	active_room=room
	active_home=id
	resident=RESIDENT.new()
	resident.specification=spec
	resident.position=placement.position
	resident.rotation.y=placement.yaw
	room.add_child(resident)
	resident.home_resident_died.connect(_resident_died.bind(resident))
	resident.set_meta("home_id",id)
	resident.set_meta("sleep_support_height",placement.get("support_height",0.0))
	admission_failure=""

func _resident_died(body: CharacterBody3D) -> void:
	if body!=resident or not is_instance_valid(active_room): return
	_suppressed_room=weakref(active_room)
	_suppressed_home=active_home

func _placement(room: Node3D,spec: Dictionary) -> Dictionary:
	var activity := str(spec.get("activity","read"))
	var point: Vector3=spec.get("cooking_point",Vector3.ZERO) if activity=="cook" else spec.get("floor_point",Vector3.ZERO)
	var yaw := float(spec.get("cooking_yaw",PI)) if activity=="cook" else float(spec.get("floor_yaw",0.0))
	if activity=="sleep":
		point=spec.get("sleep_point",Vector3.ZERO)
		yaw=float(spec.get("sleep_yaw",0.0))
		var sleep_global_point := room.to_global(point)
		var sleep_ray := PhysicsRayQueryParameters3D.create(sleep_global_point+Vector3.UP*.25,sleep_global_point-Vector3.UP*.25,1)
		var sleep_hit := room.get_world_3d().direct_space_state.intersect_ray(sleep_ray)
		if sleep_hit.is_empty() or absf(float(sleep_hit.position.y)-sleep_global_point.y)>.08 or float(sleep_hit.normal.y)<.9:
			admission_failure="sleep_support_missing"; return {}
		var bed: Vector3=room.to_local(sleep_hit.position)
		var basis := Basis(Vector3.UP,yaw)
		for row in [[Vector3(0,.17,.13),Vector3(.58,.28,1.35)],
			[Vector3(0,.30,-.67),Vector3(.30,.26,.35)]]:
			var shape := BoxShape3D.new()
			shape.size=row[1]
			if not _clear_shape(room,shape,Transform3D(basis,bed+basis*row[0])):
				admission_failure="sleep_body_obstructed"; return {}
		return {"position":bed+basis*Vector3(0,.15,.87),"yaw":yaw,"support_height":bed.y}
	if not room.is_floor_clear(point,.32): admission_failure="floor_anchor_overlaps_furniture"; return {}
	var capsule := CapsuleShape3D.new()
	capsule.radius=.30
	capsule.height=1.72
	if not _clear_shape(room,capsule,Transform3D(Basis.IDENTITY,point+Vector3.UP*.90)):
		admission_failure="floor_anchor_occupied"; return {}
	var global_point := room.to_global(point)
	var ray := PhysicsRayQueryParameters3D.create(global_point+Vector3.UP*.25,global_point-Vector3.UP*.3,1)
	var hit := room.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or float(hit.normal.y)<.9:
		admission_failure="floor_support_missing"; return {}
	return {"position":room.to_local(hit.position)+Vector3.UP*.035,"yaw":yaw}

func _clear_shape(room: Node3D,shape: Shape3D,local_transform: Transform3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=shape
	query.transform=room.global_transform*local_transform
	query.collision_mask=7
	return room.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _clear() -> void:
	if is_instance_valid(resident):
		resident.hide()
		resident.collision_layer=0
		resident.collision_mask=0
		resident.process_mode=Node.PROCESS_MODE_DISABLED
		resident.queue_free()
	resident=null
	active_room=null
	active_home=""
	_suppressed_room=null
	_suppressed_home=""

func _exit_tree() -> void: _clear()

func diagnostics() -> Dictionary:
	return {"home":active_home,"active_id":active_home,"count":1 if is_instance_valid(resident) else 0,"resident_count":1 if is_instance_valid(resident) else 0,
		"activity":str(resident.home_activity) if is_instance_valid(resident) else "",
		"death_suppressed":not _suppressed_home.is_empty(),
		"admission_failure":admission_failure,"night":night_at(float(session.weather.time_of_day)) if session!=null and is_instance_valid(session.weather) else false}
