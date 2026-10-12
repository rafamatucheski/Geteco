extends Node
## Event-only mesh deformation. Pristine meshes stay shared until the first dent.
## Records use vehicle-local metres; rebuilding from rest makes save/load exact.
const ROLES := preload("res://runtime/VehicleSurfaceRoles.gd")
const MAX_DENTS := 12
const MAX_DEPTH := .34
const MAX_VERTICES := 60000
const REST_MESH_META := "body_dents_rest_mesh"
var vehicle: CharacterBody3D
var dents: Array = []
var parts: Array[Dictionary] = []
var prepared := false
var rebuild_usec := 0
var _remaining := 0.0
var _kick := Vector3.ZERO
var _last_rotation := Vector3.ZERO
var _last_position := Vector3.ZERO

func configure(car: CharacterBody3D) -> void:
	vehicle=car
	set_process(false)
	set_physics_process(false)

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

static func valid_records(value: Variant) -> bool:
	if not value is Array or value.size()>MAX_DENTS: return false
	for row in value:
		if not row is Dictionary: return false
		for field in ["point","direction"]:
			if not row.get(field) is Array or row[field].size()!=3: return false
			for number in row[field]:
				if typeof(number) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(number)) or absf(float(number))>20: return false
		var direction:=Vector3(row.direction[0],row.direction[1],row.direction[2])
		if absf(direction.length()-1)>.01 or absf(direction.y)>.01: return false
		for field in ["radius","depth"]:
			if typeof(row.get(field)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(row[field])): return false
		if row.radius<.3 or row.radius>1.6 or row.depth<=0 or row.depth>MAX_DEPTH: return false
	return true

func snapshot() -> Array:
	return dents.duplicate(true)

func restore_records(records: Array) -> void:
	if not valid_records(records): return
	clear()
	dents=records.duplicate(true)
	if not dents.is_empty(): _prepare(); _rebuild()

func impact(amount: float, point: Vector3) -> void:
	if amount<2 or not is_finite(amount) or not point.is_finite(): return
	if vehicle.archetype.begins_with("bike_") or vehicle.archetype in ["army_tank","biarticulated_510"]: return
	var frontal:=absf(point.z)/maxf(vehicle.half_length,.1)>=absf(point.x)/maxf(vehicle.half_width,.1)
	var direction:=Vector3(0,0,-signf(point.z)) if frontal else Vector3(-signf(point.x),0,0)
	if direction.length_squared()<.5: return
	point.x=clampf(point.x,-vehicle.half_width,vehicle.half_width)
	point.z=clampf(point.z,-vehicle.half_length,vehicle.half_length)
	point.y=clampf(point.y,.35,minf(.8,vehicle.body_height*.5))
	var depth:=clampf(amount*.009,.025,.20)
	var row: Dictionary={}
	for existing in dents:
		var old:=Vector3(existing.point[0],existing.point[1],existing.point[2])
		var inward:=Vector3(existing.direction[0],existing.direction[1],existing.direction[2])
		if old.distance_to(point)<.65 and inward.dot(direction)>.9: row=existing; break
	if row.is_empty():
		if dents.size()>=MAX_DENTS: return
		row={"point":[point.x,point.y,point.z],"direction":[direction.x,direction.y,direction.z],"radius":1.25 if frontal else 1.0,"depth":0.0}
		dents.append(row)
	var prior:=float(row.depth)
	row.depth=minf(MAX_DEPTH,prior+depth)
	if row.depth>prior:
		_prepare()
		_rebuild()
	# Short damped body recoil. No permanent processing on damaged vehicles.
	if vehicle.controlled and vehicle.health>0:
		_kick=Vector3(direction.z,0,-direction.x)*clampf(amount*.002,.012,.045)
		_remaining=.38
		set_process(true)

func _prepare() -> void:
	if prepared: return
	prepared=true
	var inverse:=vehicle.global_transform.affine_inverse()
	var total:=0
	for part: MeshInstance3D in vehicle.visual.find_children("*","MeshInstance3D",true,false):
		if part.mesh==null or part.skeleton!=NodePath("") or part.is_queued_for_deletion() or not part.visible: continue
		var path:=str(vehicle.visual.get_path_to(part)).to_lower()
		if "wheel" in path or "interior" in path or "rider" in path: continue
		var arrays: Array = []
		var eligible: Array[bool] = []
		var count:=0
		var painted:=false
		for surface in part.mesh.get_surface_count():
			var data:=part.mesh.surface_get_arrays(surface)
			arrays.append(data)
			var material:=part.get_active_material(surface)
			var role:=ROLES.key(part,surface).get_slice("#",0)
			var is_paint: bool=role=="paint" or (vehicle._paint!=null and material in vehicle._paint.materials and role!="roof_paint")
			eligible.append(is_paint)
			painted=painted or is_paint
			count+=(data[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if not painted or total+count>MAX_VERTICES: continue
		total+=count
		parts.append({"node":part,"mesh":part.mesh,"arrays":arrays,"eligible":eligible,"transform":inverse*part.global_transform})
		part.set_meta(REST_MESH_META,part.mesh)

func _rebuild() -> void:
	var started:=Time.get_ticks_usec()
	for entry in parts:
		var part: MeshInstance3D=entry.node
		if not is_instance_valid(part): continue
		var mesh:=ArrayMesh.new()
		var transform: Transform3D=entry.transform
		var inverse:=transform.affine_inverse()
		for surface in entry.arrays.size():
			var arrays: Array=entry.arrays[surface].duplicate()
			if entry.eligible[surface]:
				var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX].duplicate()
				for index in vertices.size():
					var rest:=transform*vertices[index]
					# Beltline/roof and cabin remain stable, including upper door frames.
					var belt:=1.0-smoothstep(vehicle.body_height*.58,vehicle.body_height*.82,rest.y)
					var displacement:=Vector3.ZERO
					for row in dents:
						var point:=Vector3(row.point[0],row.point[1],row.point[2])
						var direction:=Vector3(row.direction[0],row.direction[1],row.direction[2])
						var distance:=rest.distance_to(point)/float(row.radius)
						if distance>=1: continue
						var weight:=pow(1.0-distance*distance,2)*belt
						displacement+=direction*float(row.depth)*weight
					if displacement.length()>MAX_DEPTH: displacement=displacement.normalized()*MAX_DEPTH
					vertices[index]=inverse*(rest+displacement)
				arrays[Mesh.ARRAY_VERTEX]=vertices
				# Keep the authored topology, UVs and split seams. SurfaceTool reindexes
				# exported meshes, which can merge vertices at hard panel boundaries.
				_update_normals(arrays)
				mesh.add_surface_from_arrays(entry.mesh.surface_get_primitive_type(surface),arrays)
			else: mesh.add_surface_from_arrays(entry.mesh.surface_get_primitive_type(surface),arrays)
			mesh.surface_set_material(surface,entry.mesh.surface_get_material(surface))
		part.mesh=mesh
		entry["applied_mesh"]=mesh
	rebuild_usec=Time.get_ticks_usec()-started

func _update_normals(arrays: Array) -> void:
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	var normals:=PackedVector3Array()
	normals.resize(vertices.size())
	var count:=indices.size() if not indices.is_empty() else vertices.size()
	for triangle in range(0,count-2,3):
		var a:=indices[triangle] if not indices.is_empty() else triangle
		var b:=indices[triangle+1] if not indices.is_empty() else triangle+1
		var c:=indices[triangle+2] if not indices.is_empty() else triangle+2
		var normal:=(vertices[b]-vertices[a]).cross(vertices[c]-vertices[a])
		# Godot's front faces use clockwise winding.
		normals[a]-=normal; normals[b]-=normal; normals[c]-=normal
	for index in normals.size(): normals[index]=normals[index].normalized()
	arrays[Mesh.ARRAY_NORMAL]=normals
	if arrays[Mesh.ARRAY_TANGENT]!=null:
		var tangents: PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT].duplicate()
		for index in normals.size():
			var offset:=index*4
			var tangent:=Vector3(tangents[offset],tangents[offset+1],tangents[offset+2])
			tangent=(tangent-normals[index]*tangent.dot(normals[index])).normalized()
			tangents[offset]=tangent.x; tangents[offset+1]=tangent.y; tangents[offset+2]=tangent.z
		arrays[Mesh.ARRAY_TANGENT]=tangents

func clear() -> void:
	_stop_recoil()
	for entry in parts:
		if is_instance_valid(entry.node):
			entry.node.mesh=entry.mesh
			if entry.node.has_meta(REST_MESH_META): entry.node.remove_meta(REST_MESH_META)
	dents.clear()
	parts.clear()
	prepared=false

## Door/roof builders read pristine geometry through REST_MESH_META. After their
## atomic swap, adopt that new topology and reapply the same damage records.
## This prevents repair or another impact from resurrecting a closed door panel.
func geometry_changed() -> void:
	if dents.is_empty(): return
	_stop_recoil()
	for entry in parts:
		var part: MeshInstance3D=entry.node
		if not is_instance_valid(part): continue
		if part.mesh==entry.get("applied_mesh"): part.mesh=entry.mesh
		if part.has_meta(REST_MESH_META): part.remove_meta(REST_MESH_META)
	parts.clear()
	prepared=false
	_prepare()
	_rebuild()

func _process(delta: float) -> void:
	if not is_instance_valid(vehicle.visual) or vehicle.health<=0: _stop_recoil(); return
	vehicle.visual.rotation-=_last_rotation
	vehicle.visual.position-=_last_position
	_remaining=maxf(0,_remaining-delta)
	var elapsed:=.38-_remaining
	var decay:=exp(-elapsed*10)*sin(elapsed*26)
	_last_rotation=_kick*decay
	_last_position=Vector3(0,absf(decay)*.025,0)
	vehicle.visual.rotation+=_last_rotation
	vehicle.visual.position+=_last_position
	if _remaining<=0: _stop_recoil()

func _stop_recoil() -> void:
	if is_instance_valid(vehicle) and is_instance_valid(vehicle.visual):
		vehicle.visual.rotation-=_last_rotation
		vehicle.visual.position-=_last_position
	_last_rotation=Vector3.ZERO
	_last_position=Vector3.ZERO
	_remaining=0
	set_process(false)
