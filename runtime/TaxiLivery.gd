extends Node3D
## Shared taxi body; per-car sign state and registration, with no extra light source.
var sign_material: StandardMaterial3D
var plates: Array[Label3D] = []
var available := true

static func decorate(model: Node3D) -> void:
	if model.has_node("TaxiLivery"): return
	var art = load("res://runtime/TaxiLivery.gd").new()
	art.name = "TaxiLivery"
	model.add_child(art)
	art.build(model)

func build(model: Node3D) -> void:
	sign_material = StandardMaterial3D.new()
	sign_material.albedo_color = Color("fff0b0")
	sign_material.emission_enabled = true
	sign_material.emission = Color("ffe49b")
	sign_material.emission_energy_multiplier = .65
	for part in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null: continue
		var bounds: AABB = part.transform*part.get_aabb()
		if bounds.position.y > 1.41 and bounds.size.y > .2 and bounds.size.x < 1.1:
			part.material_override = sign_material
	for back in [false,true]:
		var label := _label("TAXI",Vector3(0,1.57,.277 if back else -.077),.005,Color("181b1d"))
		label.rotation.y = 0.0 if back else PI
		var plate := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(.48,.15,.016)
		plate.mesh = box
		plate.position = Vector3(0,.39,2.37 if back else -2.37)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("edece7")
		material.roughness = .35
		plate.material_override = material
		add_child(plate)
		var local_registration := _label("HBR-0000",plate.position+Vector3(0,-.016,.012 if back else -.012),.0015,Color("17212a"))
		local_registration.rotation.y = 0.0 if back else PI
		plates.append(local_registration)
		var band := MeshInstance3D.new()
		var strip := BoxMesh.new(); strip.size = Vector3(.48,.025,.02)
		band.mesh = strip; band.position = plate.position+Vector3.UP*.056
		var blue := StandardMaterial3D.new(); blue.albedo_color = Color("2151a1")
		band.material_override = blue; add_child(band)

func _label(text: String, point: Vector3, pixel: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text; label.position = point; label.pixel_size = pixel
	label.font_size = 48; label.outline_size = 0; label.modulate = color
	label.no_depth_test = false
	add_child(label)
	return label

func _ready() -> void:
	var vehicle = get_parent().get_parent()
	if vehicle != null and "vehicle_id" in vehicle: registration(vehicle.vehicle_id)

func registration(id: String) -> void:
	var text := "HBR-%04d" % (absi(id.hash())%10000)
	for plate in plates: plate.text = text

func set_available(value: bool) -> void:
	available = value
	sign_material.emission_energy_multiplier = .65 if value else 0.0
	sign_material.albedo_color = Color("fff0b0") if value else Color("575249")
