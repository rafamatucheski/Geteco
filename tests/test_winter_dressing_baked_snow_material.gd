extends SceneTree

const MATERIAL := preload("res://world/mountain_pass/transit/WinterDressingSnowMaterial.res")

func _initialize() -> void:
	var albedo := MATERIAL.albedo_texture.get_image()
	var normal := MATERIAL.normal_texture.get_image()
	var valid := (
		albedo.get_size() == Vector2i(256, 256)
		and normal.get_size() == Vector2i(256, 256)
		and albedo.has_mipmaps()
		and normal.has_mipmaps()
		and MATERIAL.uv1_triplanar
		and MATERIAL.uv1_world_triplanar
		and is_equal_approx(MATERIAL.normal_scale, 0.65)
	)
	print("WINTER_DRESSING_BAKED_SNOW albedo_size=", albedo.get_size(),
		" normal_size=", normal.get_size(),
		" albedo_mipmaps=", albedo.has_mipmaps(),
		" normal_mipmaps=", normal.has_mipmaps(),
		" triplanar=", MATERIAL.uv1_triplanar,
		" world_triplanar=", MATERIAL.uv1_world_triplanar,
		" normal_scale=", MATERIAL.normal_scale,
		" valid=", valid)
	quit(0 if valid else 1)
