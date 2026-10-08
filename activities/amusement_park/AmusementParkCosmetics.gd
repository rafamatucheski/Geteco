extends RefCounted
const STATE := preload("res://activities/amusement_park/AmusementParkCosmeticState.gd")
const ART := preload("res://activities/amusement_park/AmusementParkCosmeticArt.gd")

static func apply(player: Node3D, world: Dictionary) -> void:
	if not is_instance_valid(player): return
	var skeleton := player.get("skeleton") as Skeleton3D
	if not is_instance_valid(skeleton): return
	for child in skeleton.get_children():
		if child.name == &"ParkCosmetics": child.free()
	var saved := STATE.data(world)
	if not STATE.valid(saved): return
	# Suppress only baked glasses, preserving hats and all other outfit pieces.
	var outfit_head := skeleton.get_node_or_null("MeshyOutfitHead")
	if is_instance_valid(outfit_head):
		for space in outfit_head.get_children():
			for piece in space.get_children():
				if piece.get_meta("outfit_accessory_kind", "") in ["shades", "goggles"]:
					piece.visible = saved.glasses.is_empty()
	if saved.glasses.is_empty() and saved.mask.is_empty(): return
	var head := skeleton.find_bone("Head")
	if head < 0: return
	var attachment := BoneAttachment3D.new()
	attachment.name = "ParkCosmetics"
	attachment.bone_name = "Head"
	skeleton.add_child(attachment)
	var space := Node3D.new()
	space.transform = skeleton.get_bone_global_rest(head).affine_inverse()
	attachment.add_child(space)
	for slot in ["glasses", "mask"]:
		var id := str(saved[slot])
		if id.is_empty(): continue
		var item := ART.accessory(id)
		item.set_meta("cosmetic_slot", slot)
		# Eye sockets sit behind the nose tip; a shared nose-depth plane made
		# glasses float and the mask cover them. Fit each to its facial region.
		item.position = Vector3(.004, 1.538, .085) if slot == "glasses" else Vector3(.004, 1.500, .080)
		space.add_child(item)
