extends SceneTree
## Reproduce the Nord-only optimized asset without altering the legacy source.
## godot --headless --path . --script res://tools/fleet_fixups/bake_nord240.gd
const SOURCE := "res://assets/fleet/nordic_estate.scn"
const OUTPUT := "res://assets/fleet/nordic_estate_detail.scn"

func _initialize() -> void:
	var model := (load(SOURCE) as PackedScene).instantiate() as Node3D
	preload("res://runtime/VehicleFinish.gd").decorate("nordic_estate",model)
	preload("res://runtime/Nord240Detail.gd").decorate(model)
	for child: Node in model.find_children("*","",true,false): child.owner = model
	var packed := PackedScene.new()
	var result := packed.pack(model)
	if result == OK:
		result = ResourceSaver.save(packed,OUTPUT,ResourceSaver.FLAG_COMPRESS)
	var triangles := 0
	var meshes := 0
	var surfaces := 0
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		meshes += 1
		triangles += part.mesh.get_faces().size()/3
		surfaces += part.mesh.get_surface_count()
	print("NORD_BAKE ",JSON.stringify({"error":result,"triangles":triangles,
		"meshes":meshes,"surfaces":surfaces,"output":OUTPUT}))
	model.free()
	quit(0 if result == OK else 1)
