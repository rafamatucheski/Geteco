extends RefCounted
## Reuses the authored motorcycle cabin, grips and rider rig with winter running gear.
static func create() -> Node3D:
	var model := (load("res://assets/fleet/bike_urban.scn") as PackedScene).instantiate() as Node3D
	for part in model.get_children():
		if part.has_meta("wheel_center"): part.hide()
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color("20242a")
	rubber.roughness = .95
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("727d84")
	metal.roughness = .55
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color("245cab")
	shell.roughness = .65
	_box(model, "RearTrack", Vector3(0,.25,.48), Vector3(.57,.46,1.18), rubber)
	for row in 10:
		_box(model, "TrackTread", Vector3(0,.485,.0+row*.11), Vector3(.61,.045,.045), rubber)
	for side in [-1.0,1.0]:
		_box(model, "Ski", Vector3(side*.46,.07,-.75), Vector3(.19,.10,.96), rubber)
		var nose := _box(model, "SkiRaisedNose", Vector3(side*.46,.145,-1.21), Vector3(.19,.09,.24), rubber)
		nose.rotation.x = .4
		_box(model, "SkiStrut", Vector3(side*.46,.28,-.66), Vector3(.06,.34,.07), metal)
	_box(model, "WinterCowling", Vector3(0,.65,-.53), Vector3(.75,.45,.74), shell)
	return model

static func _box(parent: Node3D, label: String, point: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.material_override = material
	part.position = point
	parent.add_child(part)
	return part
