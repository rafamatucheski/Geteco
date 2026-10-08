extends Node3D
## Bounded presentation on already defeated, damageable human NPCs. No extra damage,
## no detached rigid bodies, and no effects on protected residents or the player.
const PROTECTION := preload("res://gameplay/DamageProtection.gd")
const MAX_PARTS := 12
const MAX_BLEEDS := 8
const LIFE := 14.0
var effects: Node3D
var _parts: Array[Dictionary] = []
var _bleeds: Array[Dictionary] = []
var _cap_material: StandardMaterial3D

func _ready() -> void:
	_cap_material = StandardMaterial3D.new()
	_cap_material.albedo_color = Color("671421")
	_cap_material.roughness = 0.7
	set_physics_process(false)

func sever_defeated(actor: Node3D, direction: Vector3, combo: int) -> bool:
	if not is_instance_valid(actor) or PROTECTION.is_protected(actor) or actor.get("is_player") == true: return false
	if actor.get("dead") != true or not actor.has_method("receive_damage") or actor.has_meta("katana_severed"): return false
	var limb_names := ["right_upper_arm", "left_upper_leg", "left_upper_arm"]
	var limb := _visible_limb(actor, limb_names[posmod(combo, 3)])
	if limb == null: return false # Skinned/special rigs keep their authored death presentation.
	actor.set_meta("katana_severed", true)
	_detach(actor, limb, direction)
	if combo == 2:
		var second := _visible_limb(actor, "right_lower_leg")
		if second != null: _detach(actor, second, -direction * 0.7)
	set_physics_process(true)
	return true

func _visible_limb(actor: Node3D, limb_name: String) -> MeshInstance3D:
	# Some officers retain a hidden legacy body next to their current civilian rig.
	for candidate in actor.find_children(limb_name, "MeshInstance3D", true, false):
		if (candidate as MeshInstance3D).is_visible_in_tree(): return candidate
	return null

func _detach(actor: Node3D, limb: MeshInstance3D, direction: Vector3) -> void:
	while _parts.size() >= MAX_PARTS:
		var removed: Dictionary = _parts.pop_front()
		if is_instance_valid(removed.node): removed.node.queue_free()
	var part := limb.duplicate(0) as MeshInstance3D
	var transform_now := limb.global_transform
	add_child(part)
	part.global_transform = transform_now
	part.show()
	limb.hide()
	var cap := _cap(0.074 if limb.name.to_lower().contains("leg") else 0.054)
	part.add_child(cap)
	var stump := _cap(0.074 if limb.name.to_lower().contains("leg") else 0.054)
	limb.get_parent().add_child(stump)
	stump.transform = limb.transform
	var flat := Vector3(direction.x, 0.0, direction.z).normalized()
	_parts.append({"node": part, "velocity": flat * 2.2 + Vector3.UP * 2.1, "age": 0.0, "landed": false})
	if _bleeds.size() >= MAX_BLEEDS: _bleeds.pop_front()
	_bleeds.append({"actor": weakref(actor), "stump": weakref(stump), "age": 0.0, "next": 0.0, "direction": flat})
	if is_instance_valid(effects):
		effects.blood(stump.global_position, flat, 75.0)
		effects.stain(actor.global_position, 0.7)

func _cap(radius: float) -> MeshInstance3D:
	var cap := MeshInstance3D.new()
	cap.name = "CutSurface"
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = 0.012
	shape.radial_segments = 8
	cap.mesh = shape
	cap.material_override = _cap_material
	return cap

func _physics_process(delta: float) -> void:
	for index in range(_parts.size() - 1, -1, -1):
		var item: Dictionary = _parts[index]
		var part := item.node as MeshInstance3D
		item.age += delta
		if not is_instance_valid(part) or item.age >= LIFE:
			if is_instance_valid(part): part.queue_free()
			_parts.remove_at(index)
			continue
		if not item.landed:
			var from := part.global_position
			item.velocity += Vector3.DOWN * 9.8 * delta
			var to: Vector3 = from + item.velocity * delta
			var query := PhysicsRayQueryParameters3D.create(from, to, 1)
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty():
				part.global_position = to
				part.rotate_x(delta * 3.0)
				part.rotate_z(delta * 2.0)
			else:
				part.global_position = hit.position + hit.normal * 0.07
				part.rotation.x = PI * 0.5
				item.landed = true
		part.transparency = smoothstep(LIFE - 2.0, LIFE, float(item.age))
	for index in range(_bleeds.size() - 1, -1, -1):
		var bleed: Dictionary = _bleeds[index]
		bleed.age += delta
		var actor: Node3D = bleed.actor.get_ref()
		var stump: Node3D = bleed.stump.get_ref()
		if not is_instance_valid(actor) or not is_instance_valid(stump) or bleed.age > 2.4:
			_bleeds.remove_at(index)
			continue
		if bleed.age >= bleed.next and is_instance_valid(effects):
			bleed.next += 0.4
			effects.blood(stump.global_position, bleed.direction, 18.0 * (1.0 - bleed.age / 2.4))
	if _parts.is_empty() and _bleeds.is_empty(): set_physics_process(false)

func clear() -> void:
	for item in _parts:
		if is_instance_valid(item.node): item.node.queue_free()
	_parts.clear()
	_bleeds.clear()
	set_physics_process(false)

func part_count() -> int:
	return _parts.size()
