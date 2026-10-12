extends Node3D
## Independent equipment: follows Dante's waist, never the weapon or its pose.
const PRICE := 300
var gameplay
var owned := false
var enabled := false
var lamp: SpotLight3D
var housing: Node3D

func _ready() -> void:
	housing = Node3D.new()
	housing.name = "BeltLampHousing"
	add_child(housing)
	var body := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(.095, .13, .075)
	body.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("252b30")
	material.metallic = .65
	body.material_override = material
	housing.add_child(body)
	var lens := MeshInstance3D.new()
	var lens_mesh := CylinderMesh.new()
	lens_mesh.top_radius = .032
	lens_mesh.bottom_radius = .032
	lens_mesh.height = .012
	lens.mesh = lens_mesh
	lens.rotation.x = PI / 2
	lens.position.z = -.043
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color("e1eadc")
	lens.material_override = glass
	housing.add_child(lens)
	lamp = SpotLight3D.new()
	lamp.position.z = -.055
	lamp.rotation.x = -.12
	lamp.spot_range = 18.0
	lamp.spot_angle = 42.0
	lamp.spot_attenuation = .7
	lamp.spot_angle_attenuation = 1.5
	lamp.light_color = Color(1.0, .94, .83)
	lamp.light_energy = 5.0
	lamp.light_specular = .2
	lamp.shadow_enabled = true
	housing.add_child(lamp)
	update_visibility()

func purchase() -> bool:
	if owned or not gameplay.state.spend(PRICE, "belt_flashlight"): return false
	owned = true
	enabled = true
	update_visibility()
	return true

func toggle() -> bool:
	if not owned: return false
	enabled = not enabled
	update_visibility()
	return true

func update_visibility() -> void:
	if not is_instance_valid(housing): return
	housing.visible = owned and is_instance_valid(gameplay.player) and gameplay.player.visible
	var driving = gameplay.world.get("driving") if is_instance_valid(gameplay.world) else null
	lamp.visible = housing.visible and enabled and gameplay.health > 0 and not (is_instance_valid(driving) and driving.occupied)

func _process(_delta: float) -> void:
	if not owned or not is_instance_valid(gameplay.player) or not is_instance_valid(gameplay.player.visual): return
	var actor = gameplay.player
	global_transform = Transform3D(actor.visual.global_basis.orthonormalized(), actor.global_position)
	global_position += global_basis * Vector3(.19, .95, -.14)
	update_visibility()

func snapshot() -> Dictionary:
	return {"owned": owned, "enabled": enabled}

static func valid(data: Variant) -> bool:
	return data is Dictionary and data.get("owned") is bool and data.get("enabled") is bool and (data.owned or not data.enabled)

func restore(data: Dictionary) -> void:
	owned = data.get("owned", false)
	enabled = data.get("enabled", false) and owned
	update_visibility()
