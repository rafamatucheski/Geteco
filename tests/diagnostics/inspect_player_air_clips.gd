extends SceneTree

func _init() -> void:
	var policy := preload("res://runtime/ShopSafety.gd")
	var places: int = policy.IDS.size()
	var interiors: int = policy.IDS.size()
	for definition in preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd").definitions():
		if policy.peaceful(definition.id):
			places += 1
			interiors += int(definition.floor_count)
	print("SHOP_POLICY_INVENTORY places=",places," distinct_authored_interior_floors=",interiors)
	var library: AnimationLibrary = load("res://assets/animation_library/dante_ual.res")
	for clip in library.get_animation_list():
		if "Jump" in clip or "Fall" in clip or "Land" in clip or "Climb" in clip or "Hang" in clip or "Roll" in clip or "Get" in clip:
			print("AIR_CLIP ", clip, " length=", library.get_animation(clip).length)
			if clip.begins_with("Jump"):
				var animation := library.get_animation(clip)
				for track in animation.get_track_count():
					if animation.track_get_type(track) == Animation.TYPE_POSITION_3D:
						for sample in [0.0, .3, .65, 1.1, animation.length]:
							print("AIR_HIP ", clip, " ", sample, " ", animation.position_track_interpolate(track, sample))
	quit()
