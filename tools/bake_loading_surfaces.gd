extends SceneTree
## Authoring tool: bake the existing recipe without changing any pixel or mip.
const GROUND := preload("res://assets/regions/source/world/harbor/UrbanGround.gd")
const SET := preload("res://world/shared/SurfaceTextureSet.gd")
const OUT := "res://assets/materials/urban_ground_cache/"
func _initialize() -> void: run.call_deferred()

func run() -> void:
	Engine.set_meta("rebake_loading_surfaces",true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var report := {}
	for kind in ["concrete","stone","brick","gravel","grass"]:
		var bundle := SET.new()
		bundle.albedo = GROUND.texture(kind)
		bundle.normal = GROUND._normals[kind]
		bundle.roughness = GROUND._rough[kind]
		bundle.recipe = "UrbanGround/v1/" + kind
		var error := ResourceSaver.save(bundle,OUT+kind+".res",ResourceSaver.FLAG_COMPRESS)
		if error != OK:
			push_error("Could not bake " + kind)
			quit(1)
			return
		report[kind] = {"albedo":hash_image(bundle.albedo),"normal":hash_image(bundle.normal),"roughness":hash_image(bundle.roughness)}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/loading-fluid-20261021"))
	FileAccess.open("res://evidence/loading-fluid-20261021/surface-hashes.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("LOADING_SURFACE_BAKE ",JSON.stringify(report))
	quit()

func hash_image(texture: Texture2D) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(texture.get_image().get_data())
	return hash.finish().hex_encode()
