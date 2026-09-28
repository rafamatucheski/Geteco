extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var region = preload("res://world/editing/EditableRegion.gd").build_region("harbor")
	region.prepare_data()
	var catalog = preload("res://world/editing/WorldEditData.gd").catalog(region)
	DirAccess.make_dir_recursive_absolute("res://evidence/biarticulated")
	FileAccess.open("res://evidence/biarticulated/catalog-before.json",FileAccess.WRITE).store_string(JSON.stringify(catalog))
	region.free()
	quit()
