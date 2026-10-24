extends Node
## Event-only, instance-local glazing damage. Body/paint surfaces are never hidden or edited.
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
const NODE_NAME := "GlassDamage"
const MAX_RECORDS := 32
var vehicle: Node3D
var records: Array = []
var _parts: Dictionary = {}
var _applying := false
static var _missing: StandardMaterial3D

static func owner_for(car: Node3D, create := false) -> Node:
	var owner := car.get_node_or_null(NODE_NAME)
	if owner == null and create:
		owner = load("res://gameplay/vehicle_effects/VehicleGlassDamage.gd").new()
		owner.name = NODE_NAME
		owner.vehicle = car
		car.add_child(owner)
	return owner

static func valid_records(value: Variant) -> bool:
	if not value is Array or value.size() > MAX_RECORDS: return false
	for row in value:
		if not row is Dictionary: return false
		for key in ["point","direction"]:
			if not row.get(key) is Array or row[key].size() != 3: return false
			for number in row[key]:
				if typeof(number) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(number)) or absf(float(number)) > 64.0: return false
		if absf(Vector3(row.direction[0],row.direction[1],row.direction[2]).length()-1.0) > .01: return false
	return true

static func pristine_part(car: Node3D, part: MeshInstance3D) -> Mesh:
	var owner := owner_for(car)
	if owner != null and owner._parts.has(part) and part.mesh == owner._parts[part].applied:
		return owner._parts[part].base
	return part.mesh

static func geometry_changed(car: Node3D) -> void:
	var owner := owner_for(car)
	if owner != null: owner.reapply()

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

func snapshot() -> Array: return records.duplicate(true)

func restore_records(value: Array) -> void:
	if not valid_records(value): return
	clear()
	if value.is_empty(): return
	_prepare_topology()
	records = value.duplicate(true)
	reapply()

func _prepare_topology() -> void:
	# Freeze cabin dimensions before removing a window; finish a pending door cut before
	# making holes, so later boarding cannot rebuild pristine glazing over those holes.
	INTERIOR.spec(vehicle)
	if vehicle.has_method("finish_doors"): vehicle.finish_doors()

static func _canonical(part: Node3D, car: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var cursor := part
	while cursor != null and cursor != car:
		var pose := cursor.transform
		if str(cursor.name) in ["DriverDoorL","DriverDoorR"]: pose.basis = Basis.IDENTITY
		result = pose * result
		cursor = cursor.get_parent() as Node3D
	return result

static func _hidden(part: MeshInstance3D, surface: int) -> bool:
	if not part.is_visible_in_tree(): return true
	var material := part.get_active_material(surface) as BaseMaterial3D
	return material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and material.albedo_color.a < .01

static func _indices(arrays: Array) -> PackedInt32Array:
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if not indices.is_empty(): return indices
	indices.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	for i in indices.size(): indices[i] = i
	return indices

## Return nearest rendered surface, including paint, wheels and lamps which block the shot.
func contact(from: Vector3, to: Vector3) -> Dictionary:
	var nearest := INF
	var result: Dictionary = {}
	for part: MeshInstance3D in vehicle.visual.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null or not part.is_visible_in_tree() or part.skeleton != NodePath(""): continue
		if part.name in ["RoofCut","WarmUp"] or "Interior" in str(part.get_path()) or "/WindshieldRain/" in str(part.get_path()): continue
		var inverse := part.global_transform.affine_inverse()
		var start := inverse * from
		var end := inverse * to
		if part.mesh.get_aabb().grow(.002).intersects_segment(start,end) == null: continue
		for surface in part.mesh.get_surface_count():
			if _hidden(part,surface) or part.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
			var arrays := INTERIOR.contact_arrays(part.mesh,surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := _indices(arrays)
			for i in range(0,indices.size()-2,3):
				var point: Variant = Geometry3D.segment_intersects_triangle(start,end,vertices[indices[i]],vertices[indices[i+1]],vertices[indices[i+2]])
				if point == null: continue
				var world_point := part.to_global(point)
				var distance := from.distance_squared_to(world_point)
				if distance >= nearest: continue
				nearest = distance
				result = {"part":part,"surface":surface,"triangle":i,"point":world_point,
					"glass":INTERIOR._is_glass(part,surface,part.get_active_material(surface))}
	return result

func shoot(from: Vector3, to: Vector3) -> Dictionary:
	if records.size() >= MAX_RECORDS or not from.is_finite() or not to.is_finite() or from.distance_squared_to(to) < .0001: return {}
	_prepare_topology()
	var hit := contact(from,to)
	if hit.is_empty() or not hit.glass: return {}
	var part: MeshInstance3D = hit.part
	var canonical := _canonical(part,vehicle)
	var point := canonical * part.to_local(hit.point)
	var direction := (canonical.basis * (part.global_basis.inverse() * from.direction_to(to))).normalized()
	var row := {"point":[point.x,point.y,point.z],"direction":[direction.x,direction.y,direction.z]}
	# Repeated bullets through an existing hole cannot break the opposite window in
	# the same call; the next physical shot may hit that second pane normally.
	records.append(row)
	_remove_panel(part,int(hit.surface),int(hit.triangle))
	_refresh_rain()
	return {"point":hit.point,"normal":-from.direction_to(to),"material":"glass"}

## Connected triangles, welded by position, identify one pane even on combined surfaces.
func _remove_panel(part: MeshInstance3D, surface: int, triangle: int) -> void:
	var original := part.mesh
	var arrays := INTERIOR.contact_arrays(original,surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices := _indices(arrays)
	var triangles: Dictionary = {}
	for i in range(0,indices.size()-2,3):
		for j in 3:
			var point := vertices[indices[i+j]]
			var key := Vector3i(roundi(point.x*1000.0),roundi(point.y*1000.0),roundi(point.z*1000.0))
			if not triangles.has(key): triangles[key] = []
			triangles[key].append(i)
	var removed: Dictionary = {triangle:true}
	var queue: Array[int] = [triangle]
	while not queue.is_empty():
		var i: int = queue.pop_back()
		for j in 3:
			var point := vertices[indices[i+j]]
			var key := Vector3i(roundi(point.x*1000.0),roundi(point.y*1000.0),roundi(point.z*1000.0))
			for neighbor in triangles[key]:
				if removed.has(neighbor): continue
				removed[neighbor] = true
				queue.append(neighbor)
	var kept := PackedInt32Array()
	for i in range(0,indices.size()-2,3):
		if not removed.has(i):
			kept.append(indices[i]); kept.append(indices[i+1]); kept.append(indices[i+2])
	var entry: Dictionary = _parts.get(part,{"base":original,"applied":original,"overrides":{}})
	if part.mesh != entry.applied: entry.base = original
	if not entry.overrides.has(surface): entry.overrides[surface] = part.get_surface_override_material(surface)
	if kept.is_empty():
		if _missing == null:
			_missing = StandardMaterial3D.new()
			_missing.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_missing.albedo_color = Color(0,0,0,0)
		part.set_surface_override_material(surface,_missing)
	else:
		var replacement := ArrayMesh.new()
		for other in original.get_surface_count():
			var changed := INTERIOR.contact_arrays(original,other).duplicate()
			if other == surface: changed[Mesh.ARRAY_INDEX] = kept
			replacement.add_surface_from_arrays(original.surface_get_primitive_type(other),changed)
			replacement.surface_set_material(other,original.surface_get_material(other))
			INTERIOR.inherit_glass(original,replacement,other,changed)
		part.mesh = replacement
	entry.applied = part.mesh
	_parts[part] = entry

func reapply() -> void:
	if _applying or records.is_empty() or not is_instance_valid(vehicle): return
	_applying = true
	for part: MeshInstance3D in vehicle.visual.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null or not part.is_visible_in_tree(): continue
		if _parts.has(part) and part.mesh == _parts[part].applied: continue
		if batch_reapply: _reapply_part(part)
		else: _reapply_part_per_record(part)
	_applying = false
	_refresh_rain()

## GETECO_GLASS_BATCH_REAPPLY=0 volta ao caminho antigo, um _remove_panel por registro (A/B).
static var batch_reapply := OS.get_environment("GETECO_GLASS_BATCH_REAPPLY") != "0"

func _reapply_part_per_record(part: MeshInstance3D) -> void:
	var inverse := _canonical(part,vehicle).affine_inverse()
	for row in records:
		var point := Vector3(row.point[0],row.point[1],row.point[2])
		var direction := Vector3(row.direction[0],row.direction[1],row.direction[2])
		var start := inverse * (point-direction*.08)
		var end := inverse * (point+direction*.08)
		for surface in part.mesh.get_surface_count():
			if _hidden(part,surface) or not INTERIOR._is_glass(part,surface,part.get_active_material(surface)): continue
			var arrays := INTERIOR.contact_arrays(part.mesh,surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := _indices(arrays)
			for i in range(0,indices.size()-2,3):
				if Geometry3D.segment_intersects_triangle(start,end,vertices[indices[i]],vertices[indices[i+1]],vertices[indices[i+2]]) != null:
					_remove_panel(part,surface,i)
					break

## Todos os registros de uma vez numa peça (24/10). Antes cada registro que acertava vidro chamava
## _remove_panel, que remontava o mapa de vizinhança do vidro e a malha INTEIRA da peça: depois de um
## amassado (malha nova, geometry_changed) um carro com 10 tiros remontava a lataria 10 vezes no mesmo
## quadro (vehicle.dents.apply 8–20 ms no estresse a quente, 6ª rodada). Mesmo resultado: cada registro, em
## ordem, tira o painel do 1º triângulo ainda presente que ele cruza em cada superfície de vidro; o mapa de
## vizinhança sai uma vez por superfície e a malha é remontada uma vez no fim.
func _reapply_part(part: MeshInstance3D) -> void:
	var original := part.mesh
	var inverse := _canonical(part,vehicle).affine_inverse()
	var segments: Array = []
	for row in records:
		var point := Vector3(row.point[0],row.point[1],row.point[2])
		var direction := Vector3(row.direction[0],row.direction[1],row.direction[2])
		segments.append([inverse * (point-direction*.08), inverse * (point+direction*.08)])
	var removed_by_surface: Dictionary = {}
	for surface in original.get_surface_count():
		if _hidden(part,surface) or not INTERIOR._is_glass(part,surface,part.get_active_material(surface)): continue
		var arrays := INTERIOR.contact_arrays(original,surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty(): continue
		var indices := _indices(arrays)
		var bounds := AABB(vertices[0],Vector3.ZERO)
		for vertex in vertices: bounds = bounds.expand(vertex)
		bounds = bounds.grow(.002)
		var removed: Dictionary = {}
		var welded: Dictionary = {}
		for segment in segments:
			if bounds.intersects_segment(segment[0],segment[1]) == null: continue
			for i in range(0,indices.size()-2,3):
				if removed.has(i): continue
				if Geometry3D.segment_intersects_triangle(segment[0],segment[1],vertices[indices[i]],vertices[indices[i+1]],vertices[indices[i+2]]) == null: continue
				if welded.is_empty(): welded = _welded(vertices,indices)
				_flood(i,vertices,indices,welded,removed)
				break
		if not removed.is_empty(): removed_by_surface[surface] = removed
	if removed_by_surface.is_empty(): return
	var entry: Dictionary = _parts.get(part,{"base":original,"applied":original,"overrides":{}})
	if part.mesh != entry.applied: entry.base = original
	var kept_by_surface: Dictionary = {}
	for surface in removed_by_surface:
		if not entry.overrides.has(surface): entry.overrides[surface] = part.get_surface_override_material(surface)
		var indices := _indices(INTERIOR.contact_arrays(original,surface))
		var removed: Dictionary = removed_by_surface[surface]
		var kept := PackedInt32Array()
		for i in range(0,indices.size()-2,3):
			if not removed.has(i):
				kept.append(indices[i]); kept.append(indices[i+1]); kept.append(indices[i+2])
		if kept.is_empty():
			if _missing == null:
				_missing = StandardMaterial3D.new()
				_missing.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_missing.albedo_color = Color(0,0,0,0)
			part.set_surface_override_material(surface,_missing)
		else: kept_by_surface[surface] = kept
	if not kept_by_surface.is_empty():
		var replacement := ArrayMesh.new()
		for other in original.get_surface_count():
			var changed := INTERIOR.contact_arrays(original,other).duplicate()
			if kept_by_surface.has(other): changed[Mesh.ARRAY_INDEX] = kept_by_surface[other]
			replacement.add_surface_from_arrays(original.surface_get_primitive_type(other),changed)
			replacement.surface_set_material(other,original.surface_get_material(other))
			INTERIOR.inherit_glass(original,replacement,other,changed)
		part.mesh = replacement
	entry.applied = part.mesh
	_parts[part] = entry

static func _weld_key(point: Vector3) -> Vector3i:
	return Vector3i(roundi(point.x*1000.0),roundi(point.y*1000.0),roundi(point.z*1000.0))

static func _welded(vertices: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	var triangles: Dictionary = {}
	for i in range(0,indices.size()-2,3):
		for j in 3:
			var key := _weld_key(vertices[indices[i+j]])
			if not triangles.has(key): triangles[key] = []
			triangles[key].append(i)
	return triangles

## Painel = triângulos ligados por vértice soldado, a partir de `seed`, somados a `removed`.
static func _flood(seed: int, vertices: PackedVector3Array, indices: PackedInt32Array, welded: Dictionary, removed: Dictionary) -> void:
	removed[seed] = true
	var queue: Array[int] = [seed]
	while not queue.is_empty():
		var i: int = queue.pop_back()
		for j in 3:
			for neighbor in welded[_weld_key(vertices[indices[i+j]])]:
				if removed.has(neighbor): continue
				removed[neighbor] = true
				queue.append(neighbor)

func clear() -> void:
	records.clear()
	for part: MeshInstance3D in _parts:
		if not is_instance_valid(part): continue
		var entry: Dictionary = _parts[part]
		if part.mesh == entry.applied: part.mesh = entry.base
		for surface in entry.overrides:
			if int(surface) < part.mesh.get_surface_count(): part.set_surface_override_material(surface,entry.overrides[surface])
	_parts.clear()
	_refresh_rain()

func _refresh_rain() -> void:
	var effects: Node = vehicle.get("effects")
	if is_instance_valid(effects) and effects.get("windshield_rain") != null:
		effects.windshield_rain.dispose()
