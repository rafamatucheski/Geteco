@tool
extends RefCounted
## Immutable scenery assets. Capturing stages a draft; only explicit Save promotes it.
const STAGING := "res://.godot/world_editor_snapshots/"
const PUBLISHED := "res://world/editing/snapshots/"

static func valid_id(value: Variant) -> bool:
	if not value is String or value.length() != 64: return false
	for letter in value:
		if letter not in "0123456789abcdef": return false
	return true

static func path_for(id: String) -> String:
	if not valid_id(id): return ""
	var published := PUBLISHED+id+".scn"
	return published if FileAccess.file_exists(published) else STAGING+id+".scn"

static func capture(nodes: Array, pivot: Vector3) -> Dictionary:
	var holder := Node3D.new()
	holder.name = "StaticScenery"
	for node in nodes:
		if not is_instance_valid(node) or not node is Node3D: continue
		var nested := false
		for other in nodes:
			if is_instance_valid(other) and other != node and other.is_ancestor_of(node): nested = true; break
		if nested: continue
		var copy := node.duplicate(0) as Node3D
		copy.transform = Transform3D(Basis.IDENTITY,-pivot)*node.global_transform
		holder.add_child(copy)
		_sanitize(copy,holder)
	var bounds := {"box":AABB(),"has":false}
	_bounds(holder,Transform3D.IDENTITY,bounds)
	if not bounds.has:
		holder.free()
		return {"error":"A seleção não contém geometria estática para copiar."}
	# The destination click is the footprint's center, including authored objects
	# whose original construction pivot sits at a corner or outside their mesh.
	var footprint_center: Vector3 = (bounds.box as AABB).get_center()
	footprint_center.y = 0
	for child in holder.get_children():
		if child is Node3D: child.position -= footprint_center
	var packed := PackedScene.new()
	var error := packed.pack(holder)
	holder.free()
	if error != OK: return {"error":"Não foi possível preparar a cópia estática: "+error_string(error)}
	error = DirAccess.make_dir_recursive_absolute(STAGING)
	if error != OK: return {"error":"Não foi possível criar a pasta de rascunhos: "+error_string(error)}
	var temporary := STAGING+"capture_%d_%d.scn" % [OS.get_process_id(),Time.get_ticks_usec()]
	# Bundle dependencies so a staged preview file can be removed without breaking
	# a later save, game launch, or transfer of this object to another map.
	error = ResourceSaver.save(packed,temporary,ResourceSaver.FLAG_BUNDLE_RESOURCES)
	if error != OK: return {"error":"Não foi possível guardar a geometria no rascunho: "+error_string(error)}
	var id := FileAccess.get_sha256(temporary)
	var target := STAGING+id+".scn"
	if FileAccess.file_exists(target): DirAccess.remove_absolute(temporary)
	else:
		error = DirAccess.rename_absolute(temporary,target)
		if error != OK: return {"error":"Não foi possível finalizar a cópia: "+error_string(error)}
	var box: AABB = bounds.box
	return {"error":"","snapshot_id":id,"size":[maxf(.05,box.size.x),maxf(.05,box.size.z)],"height":maxf(.05,box.size.y)}

static func _sanitize(node: Node, owner: Node) -> void:
	# Copies never create characters, triggers, cameras, gameplay or sound emitters.
	if node is CharacterBody3D or node is RigidBody3D or node is Area3D or node is Camera3D or node is AudioStreamPlayer3D or node is AnimationPlayer or node is AnimationTree or node is Timer:
		node.free()
		return
	var layer := int(node.get_meta("world_snapshot_collision_layer",node.get_meta("preview_collision_layer",node.collision_layer if node is CollisionObject3D else 0)))
	var mask := int(node.get_meta("world_snapshot_collision_mask",node.get_meta("preview_collision_mask",node.collision_mask if node is CollisionObject3D else 0)))
	var visual_layers := int(node.get_meta("world_snapshot_visual_layers",node.layers if node is VisualInstance3D else 1))
	if node.get_script() != null: node.set_script(null)
	for group in node.get_groups(): node.remove_from_group(group)
	for key in node.get_meta_list(): node.remove_meta(key)
	if node is VisualInstance3D: node.layers = visual_layers
	if node is StaticBody3D:
		node.collision_layer = layer
		node.collision_mask = mask
	# Disabling a CollisionObject3D removes it from the physics world by default.
	# Scripts and active entities were stripped above; keep static physics alive.
	node.process_mode = Node.PROCESS_MODE_INHERIT
	node.set_process(false)
	node.set_physics_process(false)
	node.owner = owner
	for child in node.get_children(): _sanitize(child,owner)

static func _bounds(node: Node, parent: Transform3D, result: Dictionary) -> void:
	var transform: Transform3D = parent*node.transform if node is Node3D else parent
	if node is MeshInstance3D and node.mesh != null:
		var box: AABB = transform*node.mesh.get_aabb()
		result.box = (result.box as AABB).merge(box) if result.has else box
		result.has = true
	elif node is MultiMeshInstance3D and node.multimesh != null:
		var box: AABB = transform*node.get_aabb()
		result.box = (result.box as AABB).merge(box) if result.has else box
		result.has = true
	for child in node.get_children(): _bounds(child,transform,result)

static func instantiate(row: Dictionary) -> Node3D:
	var path := path_for(str(row.get("snapshot_id","")))
	if path.is_empty() or not FileAccess.file_exists(path):
		push_error("Cópia estática ausente: "+str(row.get("snapshot_id","")))
		return null
	var packed := ResourceLoader.load(path,"PackedScene") as PackedScene
	if packed == null: return null
	var instance := packed.instantiate() as Node3D
	if instance == null: return null
	instance.name = "WorldStaticSnapshot"
	instance.set_meta("editor_id",str(row.id))
	instance.scale = Vector3.ONE*float(row.get("scale",1.0))
	instance.rotation.y = deg_to_rad(float(row.get("rotation",0.0)))
	return instance

static func promote_document(document: Dictionary) -> String:
	var ids := {}
	var areas: Array = document.get("regions",{}).values()+document.get("interiors",{}).values()
	for area in areas:
		for row in area.values():
			if row.get("model","") == "static_snapshot" and not row.get("deleted",false):
				var id: Variant = row.get("snapshot_id","")
				if not valid_id(id): return "Identidade da cópia estática inválida."
				ids[id] = true
	# Check all draft assets before publishing any, including integrity after recovery.
	for id in ids:
		var source := path_for(id)
		if not FileAccess.file_exists(source): return "Geometria da cópia estática ausente: "+id
		if FileAccess.get_sha256(source) != id: return "A geometria da cópia foi alterada fora do editor: "+id
	if ids.is_empty(): return ""
	var error := DirAccess.make_dir_recursive_absolute(PUBLISHED)
	if error != OK: return "Não foi possível criar a pasta de cópias: "+error_string(error)
	for id in ids:
		var target: String = PUBLISHED+id+".scn"
		if FileAccess.file_exists(target): continue
		var temporary := target+".tmp_%d" % OS.get_process_id()
		error = DirAccess.copy_absolute(STAGING+id+".scn",temporary)
		if error != OK: return "Não foi possível salvar a geometria da cópia: "+error_string(error)
		error = DirAccess.rename_absolute(temporary,target)
		if error != OK: return "Não foi possível finalizar a geometria salva: "+error_string(error)
	return ""
