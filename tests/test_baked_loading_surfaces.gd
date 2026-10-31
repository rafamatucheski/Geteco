extends SceneTree
## Compara os pixels assados E todos os níveis de mip com a receita determinística original.
const GROUND := preload("res://assets/regions/source/world/harbor/UrbanGround.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var failures := 0
	for kind in GROUND.BAKED:
		var baked: Resource = GROUND.BAKED[kind]
		var generated: Texture2D = GROUND._generate(kind)
		for pair in [[baked.albedo,generated],[baked.normal,GROUND._normals[kind]],[baked.roughness,GROUND._rough[kind]]]:
			var a: Image = pair[0].get_image()
			var b: Image = pair[1].get_image()
			var same := a.get_size() == b.get_size() and a.get_format() == b.get_format() and a.get_mipmap_count() == b.get_mipmap_count() and a.get_data() == b.get_data()
			if not same: failures += 1
			print(("PASS " if same else "FAIL ") + "pixels e mipmaps: " + kind)
		GROUND._tiles.erase(kind)
		var loaded := GROUND.texture(kind)
		if loaded != baked.albedo or GROUND._normals[kind] != baked.normal or GROUND._rough[kind] != baked.roughness: failures += 1
	print("BAKED_LOADING_SURFACES ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
