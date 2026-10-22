@tool
extends RefCounted
## Edits retain original nodes and gameplay references. Meshes and their authored
## physical solids share one permanent identity; NPCs and rewards remain gameplay.
const SHAPES := preload("res://world/editing/WorldPieceShape.gd")
const PROPS := preload("res://world/editing/WorldPropFactory.gd")
const STATE := &"world_interior_editor_state"

static func content(place: Node3D, id: String) -> Node3D:
	if id == "maciota" and place.get("room") is Node3D: return place.get("room")
	if place.get("floor_room") is Node3D: return place.get("floor_room")
	return place

static func floor_of(place: Node3D) -> int:
	if place.get("floor_index") != null: return int(place.get("floor_index"))
	var definition: Variant = place.get("definition")
	return int(definition.get("building_floor_index",0)) if definition is Dictionary else 0

static func _key(root: Node, node: Node) -> String:
	var parts: Array[String] = []
	while node != root and node != null:
		var parent := node.get_parent()
		var label := str(node.name)
		if label.begins_with("@"): label = label.trim_prefix("@").get_slice("@",0)
		parts.push_front(label+"#"+str(node.get_index()))
		node = parent
	return "/".join(parts)

static func _scan(node: Node, place: Node3D, bodies: Array, meshes: Array) -> void:
	if node is CharacterBody3D or node is RigidBody3D or node is Skeleton3D or node is AnimationPlayer or node is AnimationTree: return
	if node.get_meta("invulnerable",false) or node.has_meta("pickup_id") or node.get_meta("world_interior_added",false): return
	if node == place.get("reward_visual") or node == place.get("part_visual") or node == place.get("maciota") or node == place.get("mechanic"): return
	var script: Script = node.get_script()
	if script != null and ("Pickup" in script.resource_path or "Actor" in script.resource_path or "Spectator" in script.resource_path): return
	if node is StaticBody3D: bodies.append(node)
	if node is MeshInstance3D and node.mesh != null: meshes.append(node)
	if node is MultiMeshInstance3D and node.multimesh != null: meshes.append(node)
	for child in node.get_children(): _scan(child,place,bodies,meshes)

static func _shape_box(shape: Shape3D) -> AABB:
	if shape is BoxShape3D: return AABB(-shape.size*.5,shape.size)
	if shape is SphereShape3D: return AABB(Vector3.ONE*-shape.radius,Vector3.ONE*shape.radius*2)
	if shape is CapsuleShape3D or shape is CylinderShape3D:
		return AABB(Vector3(-shape.radius,-shape.height*.5,-shape.radius),Vector3(shape.radius*2,shape.height,shape.radius*2))
	if shape is ConvexPolygonShape3D or shape is ConcavePolygonShape3D:
		var points: PackedVector3Array = shape.points if shape is ConvexPolygonShape3D else shape.get_faces()
		if points.is_empty(): return AABB()
		var bounds := AABB(points[0],Vector3.ZERO)
		for point in points: bounds = bounds.expand(point)
		return bounds
	var mesh := shape.get_debug_mesh()
	return mesh.get_aabb() if mesh != null else AABB()

static func _box(root: Node3D, node: Node3D) -> AABB:
	var inverse := root.global_transform.affine_inverse()
	if node is MeshInstance3D: return inverse*node.global_transform*node.mesh.get_aabb()
	if node is MultiMeshInstance3D: return inverse*node.global_transform*node.get_aabb()
	var result := AABB()
	var found := false
	for shape: CollisionShape3D in node.find_children("*","CollisionShape3D",true,false):
		if shape.shape == null or shape.disabled: continue
		var bounds: AABB = inverse*shape.global_transform*_shape_box(shape.shape)
		result = result.merge(bounds) if found else bounds
		found = true
	return result

static func _inventory(place: Node3D, root: Node3D, id: String) -> Dictionary:
	var bodies: Array = []
	var meshes: Array = []
	_scan(root,place,bodies,meshes)
	var groups := {}
	var body_keys := {}
	for body: StaticBody3D in bodies:
		var key := "floor/%d/solid/" % floor_of(place)+_key(root,body)
		body_keys[body] = key
		groups[key] = {"nodes":[body],"bounds":_box(root,body),"label":str(body.get_meta("interior_solid_id",body.name)),"visual":false}
	for mesh: Node3D in meshes:
		var box := _box(root,mesh)
		var meta := str(mesh.get_meta("interior_solid_id",""))
		var chosen := ""
		var best := INF
		for body: StaticBody3D in bodies:
			var key: String = body_keys[body]
			var group: Dictionary = groups[key]
			var bounds: AABB = group.bounds
			var matching := not meta.is_empty() and meta == str(body.get_meta("interior_solid_id",""))
			if not matching and not bounds.grow(.025).has_point(box.get_center()): continue
			if not matching and (bounds.end.y <= .04 or bounds.position.y > 2.1): continue
			var score := bounds.get_center().distance_squared_to(box.get_center())+(0.0 if matching else 100000.0)
			if score < best: chosen = key; best = score
		if chosen.is_empty():
			chosen = "floor/%d/visual/" % floor_of(place)+_key(root,mesh)
			groups[chosen] = {"nodes":[],"bounds":box,"label":str(mesh.get_meta("interior_solid_id",mesh.name)),"visual":true}
		groups[chosen].nodes.append(mesh)
		groups[chosen].bounds = (groups[chosen].bounds as AABB).merge(box)
		groups[chosen].visual = true
	var rows: Array = []
	var indexed := {}
	for key: String in groups:
		var group: Dictionary = groups[key]
		var row_id := "piece/interior/%s/%s" % [id,key.sha256_text().substr(0,16)]
		var bounds: AABB = group.bounds
		var row := {"id":row_id,"type":"piece","source_record":"interior/"+id+"/"+key,"label":group.label,"position":[bounds.get_center().x,bounds.get_center().z],"rotation":0.0,"size":[maxf(.05,bounds.size.x),maxf(.05,bounds.size.z)],"height":maxf(.05,bounds.size.y),"locked":false,"interior_id":id,"parts":[]}
		row.interior_floor = floor_of(place)
		for node: Node3D in group.nodes:
			node.set_meta("editor_id",row_id)
			node.set_meta("world_snapshot_ground_height",0.0)
			if node is MeshInstance3D or node is MultiMeshInstance3D:
				var visual := _box(root,node)
				(row.parts as Array).append([visual.position.x,visual.position.z,visual.size.x,visual.size.z,visual.end.y,"a3947e"])
		if row.parts.is_empty(): row.parts.append([bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z,bounds.end.y,"627a88"])
		group.row = row
		group.entries = _entries(group.nodes)
		indexed[row_id] = group
		rows.append(row)
	var anchors: Array = []
	var interactions: Variant = root.get("interaction_points")
	if interactions is Dictionary:
		var npc_ids: Array = []
		var definition: Variant = root.get("definition")
		if definition is Dictionary:
			for npc in definition.get("npcs",[]): npc_ids.append(str(npc.get("id","")))
		for name: String in interactions:
			if name in npc_ids or not interactions[name] is Vector3 or not interactions[name].is_finite(): continue
			var local: Vector3 = root.to_local(interactions[name])
			var closest := ""
			var distance := 1.8
			for row_id: String in indexed:
				var group: Dictionary = indexed[row_id]
				var bounds: AABB = group.bounds
				if bounds.end.y <= .06 or bounds.position.y > 1.8 or bounds.size.x*bounds.size.z > 35: continue
				if "wall" in str(group.label).to_lower() or "floor" in str(group.label).to_lower(): continue
				var rect := Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z)
				var point := Vector2(local.x,local.z)
				var nearest := point.clamp(rect.position,rect.end)
				var gap := point.distance_to(nearest)
				if gap < distance: closest = row_id; distance = gap
			if not closest.is_empty(): anchors.append({"name":name,"point":interactions[name],"group":closest})
	var jump: Variant = root.get("jump_point")
	if jump is Vector3:
		for row_id: String in indexed:
			if str(indexed[row_id].label) == "RoofJumpGate":
				anchors.append({"name":"jump_point","property":true,"point":root.to_global(jump),"outward":root.get("jump_outward"),"group":row_id})
				break
	return {"groups":indexed,"rows":rows,"anchors":anchors}

static func _entries(nodes: Array) -> Array:
	var entries: Array = []
	var seen := {}
	for node: Node3D in nodes: _snapshot(node,entries,seen)
	return entries

static func _snapshot(node: Node, entries: Array, seen: Dictionary) -> void:
	if seen.has(node.get_instance_id()): return
	seen[node.get_instance_id()] = true
	if node is Node3D:
		var entry := {"node":node,"transform":node.global_transform,"visible":node.visible}
		if node is CollisionObject3D: entry.layer = node.collision_layer; entry.mask = node.collision_mask
		if node is CollisionShape3D: entry.shape = node.shape; entry.disabled = node.disabled
		if node is MeshInstance3D: entry.mesh = node.mesh
		entries.append(entry)
	for child in node.get_children(): _snapshot(child,entries,seen)

static func _apply(root: Node3D, group: Dictionary, change: Dictionary) -> void:
	if change.is_empty() and not group.get("applied",false): return
	group["applied"] = not change.is_empty()
	var base: Dictionary = group.row
	var position: Array = change.get("position",base.position)
	var stretch: Array = change.get("stretch",[1.0,1.0])
	var scale := Vector3(float(stretch[0]),float(change.get("height_stretch",1)),float(stretch[1]))
	var rotation := Basis(Vector3.UP,deg_to_rad(float(change.get("rotation",0))))
	var origin := Vector3(base.position[0],0,base.position[1])
	var target := Vector3(position[0],float(change.get("lift",0)),position[1])
	var rigid := root.global_transform*Transform3D(rotation,target)*Transform3D(Basis.IDENTITY,-origin)*root.global_transform.affine_inverse()
	var warp := root.global_transform*Transform3D(rotation*Basis.from_scale(scale),target)*Transform3D(Basis.IDENTITY,-origin)*root.global_transform.affine_inverse()
	var deleted := bool(change.get("deleted",false))
	# Parent transforms precede children; CollisionObject bases remain rigid while
	# each physical shape receives its deformation in its own local coordinates.
	for entry: Dictionary in group.entries:
		var node: Node3D = entry.node
		if not is_instance_valid(node): continue
		var desired: Transform3D = warp*(entry.transform as Transform3D)
		if node is CollisionObject3D:
			desired.basis = (rigid*(entry.transform as Transform3D)).basis.orthonormalized()
			node.collision_layer = 0 if deleted else int(entry.layer)
			node.collision_mask = 0 if deleted else int(entry.mask)
			node.global_transform = desired
		elif node is CollisionShape3D:
			var local: Transform3D = (node.get_parent() as Node3D).global_transform.affine_inverse()*desired
			node.shape = SHAPES._bake_shape(entry.shape,local.basis)
			node.transform = Transform3D(Basis.IDENTITY,local.origin)
			node.disabled = deleted or bool(entry.disabled)
		else: node.global_transform = desired
		node.visible = bool(entry.visible) and not deleted

static func _added(root: Node3D, changes: Dictionary, floor_index: int) -> String:
	var existing := root.get_node_or_null("WorldInteriorAdded")
	if existing != null: existing.free()
	var holder := Node3D.new()
	holder.name = "WorldInteriorAdded"
	holder.set_meta("world_interior_added",true)
	root.add_child(holder)
	for id: String in changes:
		var row: Dictionary = changes[id]
		if int(row.get("interior_floor",0)) != floor_index: continue
		if not id.begins_with("new/") or row.get("deleted",false): continue
		var node: Node3D
		match str(row.type):
			"prop": node = PROPS.create(row)
			"tree":
				node = preload("res://world/regions/NativePine.gd").create(int(row.variant),bool(row.snow))
				node.scale = Vector3.ONE*float(row.scale)
				node.rotation.y = deg_to_rad(float(row.rotation))
				var body := StaticBody3D.new()
				var collider := CollisionShape3D.new()
				var shape := BoxShape3D.new()
				shape.size = Vector3(.4,2.8,.4)
				collider.shape = shape
				collider.position.y = 1.4
				body.add_child(collider)
				node.add_child(body)
			"building":
				node = preload("res://world/urban_detail/UrbanBuildingFactory.gd").build_building({"id":id,"position":Vector3.ZERO,"size":Vector2(row.size[0],row.size[1]),"kind":row.model,"height_override":row.height,"color":row.color})
				if node != null: node.rotation.y = deg_to_rad(float(row.rotation))
			"ground": node = preload("res://world/editing/WorldGroundFactory.gd").create(row,preload("res://world/editing/WorldGroundFactory.gd").bounds(row))
			"light":
				node = Node3D.new()
				var light := OmniLight3D.new()
				light.light_color = Color(str(row.color))
				light.light_energy = float(row.energy)
				light.omni_range = float(row.range)
				light.position.y = float(row.height)
				node.add_child(light)
			_:
				return "Tipo de objeto indisponível no interior: "+str(row.type)
		if node == null: return "Não foi possível reconstruir o objeto do interior: "+id
		node.set_meta("editor_id",id)
		node.set_meta("world_snapshot_ground_height",0.0)
		if row.type != "ground": node.position = Vector3(row.position[0],float(row.get("interior_lift",0)),row.position[1])
		holder.add_child(node)
	return ""

static func manifest(place: Node3D, id: String) -> Array:
	var root := content(place,id)
	if not root.has_meta(STATE): root.set_meta(STATE,_inventory(place,root,id))
	return root.get_meta(STATE).rows.duplicate(true)

static func prepare(place: Node3D, id: String, document: Dictionary) -> Dictionary:
	var root := content(place,id)
	var changes: Dictionary = document.get("interiors",{}).get(id,{})
	if changes.is_empty() and not Engine.get_meta("geteco_live_preview_build",false) and not root.has_meta(STATE):
		return {"rows":[],"bounds":[],"spawn":[],"error":""}
	if not root.has_meta(STATE): root.set_meta(STATE,_inventory(place,root,id))
	var state: Dictionary = root.get_meta(STATE)
	for row_id: String in state.groups:
		_apply(root,state.groups[row_id],changes.get(row_id,{}))
	var interactions: Variant = root.get("interaction_points")
	for anchor: Dictionary in state.get("anchors",[]):
		var change: Dictionary = changes.get(anchor.group,{})
		var base: Dictionary = state.groups[anchor.group].row
		var position: Array = change.get("position",base.position)
		var stretch: Array = change.get("stretch",[1.0,1.0])
		var basis := Basis(Vector3.UP,deg_to_rad(float(change.get("rotation",0))))*Basis.from_scale(Vector3(stretch[0],float(change.get("height_stretch",1)),stretch[1]))
		var point: Vector3 = root.to_local(anchor.point)-Vector3(base.position[0],0,base.position[1])
		point = basis*point+Vector3(position[0],float(change.get("lift",0)),position[1])
		if anchor.get("property",false):
			root.set(anchor.name,Vector3.INF if change.get("deleted",false) else point)
			if anchor.get("outward") is Vector3: root.set("jump_outward",Basis(Vector3.UP,deg_to_rad(float(change.get("rotation",0))))*anchor.outward)
		elif interactions is Dictionary:
			interactions[anchor.name] = Vector3.INF if change.get("deleted",false) else root.to_global(point)
	var error := _added(root,changes,floor_of(place))
	var bounds := Rect2(-8,-6,16,12)
	var definition: Variant = place.get("definition")
	var spawn := Vector2.ZERO
	if definition is Dictionary and definition.get("size") is Vector2:
		bounds = Rect2(-definition.size*.5,definition.size)
		if definition.get("spawn") is Vector3: spawn = Vector2(definition.spawn.x,definition.spawn.z)
	elif id == "maciota": bounds = Rect2(-4.4,-4.3,11.2,9.2); spawn = Vector2(0,3.2)
	_refresh_solids(place,root)
	if error.is_empty(): error = validate_layout(place,id,document)
	return {"rows":state.rows.duplicate(true),"bounds":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y],"spawn":[spawn.x,spawn.y],"error":error}

static func validate_layout(place: Node3D, id: String, document: Dictionary) -> String:
	var root := content(place,id)
	var changes: Dictionary = document.get("interiors",{}).get(id,{})
	if changes.is_empty(): return ""
	var points: Array = []
	var definition: Variant = root.get("definition")
	if definition is Dictionary:
		if floor_of(place) > 0 and definition.get("size") is Vector2:
			points.append({"label":"entrada da escada","point":Vector3(-definition.size.x*.5+2.8,0,1.45)})
			points.append({"label":"saída da escada","point":Vector3(-definition.size.x*.5+1.45,0,1.45)})
		else:
			for field in ["spawn","exit"]:
				if definition.get(field) is Vector3: points.append({"label":"entrada" if field == "spawn" else "saída","point":definition[field]})
		for npc in definition.get("npcs",[]):
			if npc.get("local_position") is Vector3: points.append({"label":"posição de "+str(npc.get("id","NPC")),"point":npc.local_position})
		for reward in definition.get("rewards",[]):
			if reward.get("local_position") is Vector3: points.append({"label":"recompensa","point":reward.local_position})
		if definition.has("floor_count"):
			var specification: Dictionary = preload("res://world/places/harbor_buildings/HarborBuildingContent.gd").floor_spec(definition,floor_of(place))
			for resident in specification.get("occupants",[]):
				if resident.get("position") is Vector3: points.append({"label":"posição de "+str(resident.get("id","morador")),"point":resident.position})
			for reward in specification.get("rewards",[]):
				if reward.get("local_position") is Vector3: points.append({"label":"recompensa","point":reward.local_position})
	elif id == "maciota":
		points = [{"label":"entrada","point":Vector3(0,0,3.2)},{"label":"saída","point":Vector3(0,0,4.3)},{"label":"recompensa","point":Vector3(.75,0,-2.65)}]
	# Protect actual residents/rewards as well as authored catalog coordinates.
	# These actors remain gameplay objects and never become editor scenery.
	for node: Node in root.find_children("*","",true,false):
		if node is Node3D and (node is CharacterBody3D or node.get_meta("invulnerable",false) or node.has_meta("pickup_id") or node == place.get("reward_visual")):
			points.append({"label":"posição de "+str(node.name),"point":root.to_local(node.global_position)})
	var floor_validation := {}
	var support_error := _validate_changed_floor_support(root,changes,points,floor_validation)
	if not support_error.is_empty(): return support_error
	for body: StaticBody3D in root.find_children("*","StaticBody3D",true,false):
		if body.collision_layer == 0: continue
		var changed := false
		var replacement_floor := false
		var current: Node = body
		while current != root and current != null:
			var key := str(current.get_meta("editor_id",""))
			if changes.has(key) and not changes[key].get("deleted",false):
				changed = true
				replacement_floor = changes[key].get("type","") == "ground" and floor_validation.get("edited",false)
				break
			current = current.get_parent()
		if not changed: continue
		var bounds := _box(root,body)
		if bounds.end.y <= .06 or bounds.position.y > 1.8 or (replacement_floor and bounds.end.y<=.12): continue
		for point in points:
			var p: Vector3 = point.point
			if Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z).grow(.32).has_point(Vector2(p.x,p.z)):
				return "O objeto bloqueia a %s do interior. Mova-o antes de salvar." % point.label
	return ""

## This gate is deliberately conditional: old rooms/fixtures without an edited
## physical floor keep their previous validation contract.
static func _validate_changed_floor_support(root: Node3D, changes: Dictionary, points: Array, validation: Dictionary) -> String:
	if not root.has_meta(STATE): return ""
	var state: Dictionary = root.get_meta(STATE)
	var baseline: Array = []
	var floor_changed := false
	var inverse := root.global_transform.affine_inverse()
	for id: String in state.groups:
		var group: Dictionary = state.groups[id]
		var bounds: AABB = group.bounds
		if bounds.end.y > .06: continue
		var physical := false
		for entry: Dictionary in group.entries:
			if not entry.node is CollisionShape3D or entry.get("disabled",false) or entry.get("shape")==null: continue
			var body := entry.node.get_parent() as CollisionObject3D
			if body==null: continue
			var original_layer := 0
			for owner: Dictionary in group.entries:
				if owner.node==body: original_layer = int(owner.get("layer",0)); break
			if (original_layer&1)==0: continue
			physical = true
			baseline.append(_support_shape(entry.shape,inverse*(entry.transform as Transform3D)))
		if not physical or not changes.has(id): continue
		var row: Dictionary = changes[id]
		if row.get("deleted",false) or row.get("position",group.row.position)!=group.row.position or not is_zero_approx(float(row.get("rotation",0))) or row.get("stretch",[1.0,1.0])!=[1.0,1.0] or not is_equal_approx(float(row.get("height_stretch",1)),1) or not is_zero_approx(float(row.get("lift",0))) or row.has("outline"):
			floor_changed = true
	validation["edited"] = floor_changed
	if not floor_changed: return ""
	var current: Array = []
	for body: StaticBody3D in root.find_children("*","StaticBody3D",true,false):
		if (body.collision_layer&1)==0: continue
		for shape: CollisionShape3D in body.find_children("*","CollisionShape3D",true,false):
			if shape.shape!=null and not shape.disabled: current.append(_support_shape(shape.shape,inverse*shape.global_transform))
	for anchor: Dictionary in points:
		var point: Vector3 = anchor.point
		for record: Dictionary in baseline:
			if record.shape is BoxShape3D or record.shape is ConcavePolygonShape3D or record.shape is ConvexPolygonShape3D: continue
			var box: AABB = record.bounds
			if Rect2(box.position.x,box.position.z,box.size.x,box.size.z).has_point(Vector2(point.x,point.z)):
				return "Não foi possível validar o apoio da %s após editar este formato de piso. Restaure o piso antes de salvar." % anchor.label
		var original: Variant = _support_height(baseline,point,.2,-.5)
		# Do not introduce unrelated baseline failures where no original floor exists.
		if original==null: continue
		var supported := true
		# The character's contact area must be supported, not just its centre over a hole.
		for offset in [Vector2.ZERO,Vector2(.24,0),Vector2(-.24,0),Vector2(0,.24),Vector2(0,-.24)]:
			var sample := point+Vector3(offset.x,0,offset.y)
			var previous: Variant = _support_height(baseline,sample,.2,-.5)
			if previous==null: continue
			var height: Variant = _support_height(current,sample,float(previous)+.12,float(previous)-.18)
			if height==null: supported = false; break
		if not supported:
			return "O piso editado deixou a %s do interior sem apoio físico. Restaure ou coloque outro piso antes de salvar." % anchor.label
	return ""

static func _support_shape(shape: Shape3D, transform: Transform3D) -> Dictionary:
	var result := {"shape":shape,"transform":transform,"bounds":transform*_shape_box(shape),"points":PackedVector3Array()}
	var points := PackedVector3Array()
	if shape is ConcavePolygonShape3D: points = shape.get_faces()
	elif shape is ConvexPolygonShape3D: points = shape.points
	for i in points.size(): points[i] = transform*points[i]
	result.points = points
	return result

static func _triangle_floor(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Variant:
	var first := Vector2(b.x-a.x,b.z-a.z)
	var second := Vector2(c.x-a.x,c.z-a.z)
	var delta := Vector2(point.x-a.x,point.z-a.z)
	var divisor := first.cross(second)
	if absf(divisor)<1e-10: return null
	var u := delta.cross(second)/divisor
	var v := first.cross(delta)/divisor
	if u < -.00001 or v < -.00001 or u+v > 1.00001: return null
	return a.y+(b.y-a.y)*u+(c.y-a.y)*v

static func _support_height(shapes: Array, point: Vector3, ceiling: float, bottom: float) -> Variant:
	var highest: Variant = null
	for record: Dictionary in shapes:
		var bounds: AABB = record.bounds
		if not Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z).grow(.00001).has_point(Vector2(point.x,point.z)) or bounds.position.y>ceiling or bounds.end.y<bottom: continue
		var shape: Shape3D = record.shape
		var height: Variant = null
		if shape is BoxShape3D:
			var inverse: Transform3D = record.transform.affine_inverse()
			var hit: Variant = _shape_box(shape).intersects_segment(inverse*Vector3(point.x,ceiling,point.z),inverse*Vector3(point.x,bottom,point.z))
			if hit is Vector3: height = (record.transform*hit).y
		elif shape is ConcavePolygonShape3D:
			var vertices: PackedVector3Array = record.points
			for i in range(0,vertices.size()-2,3):
				if not shape.backface_collision and (vertices[i+2]-vertices[i]).cross(vertices[i+1]-vertices[i]).y<=0: continue
				var candidate: Variant = _triangle_floor(point,vertices[i],vertices[i+1],vertices[i+2])
				if candidate!=null and float(candidate)<=ceiling and float(candidate)>=bottom and (height==null or float(candidate)>float(height)): height = candidate
		elif shape is ConvexPolygonShape3D:
			# A vertical slice's upper convex envelope is the maximum interpolated
			# height among projected triples. This respects rotated/deformed slabs.
			var vertices: PackedVector3Array = record.points
			var top: Variant = null
			for a in vertices.size()-2:
				for b in range(a+1,vertices.size()-1):
					for c in range(b+1,vertices.size()):
						var candidate: Variant = _triangle_floor(point,vertices[a],vertices[b],vertices[c])
						if candidate!=null and (top==null or float(candidate)>float(top)): top = candidate
			if top!=null and float(top)<=ceiling and float(top)>=bottom: height = top
		if height!=null and (highest==null or float(height)>float(highest)): highest = height
	return highest

static func apply_saved(place: Node3D, id: String) -> void:
	var document: Dictionary
	if Engine.has_meta("geteco_world_edit_document"): document = Engine.get_meta("geteco_world_edit_document")
	else:
		var data = load("res://world/editing/WorldEditData.gd")
		var loaded: Dictionary = data.read_document()
		if not str(loaded.error).is_empty(): push_error(loaded.error); return
		document = loaded.document
	if not document.get("interiors",{}).has(id): return
	var result := prepare(place,id,document)
	if not str(result.error).is_empty(): push_warning("Editor de interiores: "+str(result.error))

static func _refresh_solids(place: Node3D, root: Node3D) -> void:
	var cached: Variant = place.get("solid_bounds")
	if not cached is Array: return
	cached.clear()
	for body: StaticBody3D in root.find_children("*","StaticBody3D",true,false):
		if body.collision_layer == 0: continue
		var bounds := _box(root,body)
		if bounds.end.y > .06 and bounds.position.y < 2.1: cached.append(bounds)
