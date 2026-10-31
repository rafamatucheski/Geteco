extends Node3D
## Equipamento independente: segue a cintura do Dante, nunca a arma nem a pose dela.
const PRICE := 300
var gameplay
var owned := false
var enabled := false
var lamp: OmniLight3D
var housing: Node3D
var glass: StandardMaterial3D

func _ready() -> void:
	housing = Node3D.new()
	housing.name = "BeltLampHousing"
	add_child(housing)
	var body := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = .055
	mesh.bottom_radius = .055
	mesh.height = .17
	body.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("252b30")
	material.metallic = .65
	body.material_override = material
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	housing.add_child(body)
	var lens := MeshInstance3D.new()
	var lens_mesh := CylinderMesh.new()
	lens_mesh.top_radius = .058
	lens_mesh.bottom_radius = .058
	lens_mesh.height = .10
	lens.mesh = lens_mesh
	glass = StandardMaterial3D.new()
	glass.albedo_color = Color("e7c28a")
	glass.emission = Color(1.0, .77, .46)
	glass.emission_energy_multiplier = 1.2
	lens.material_override = glass
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	housing.add_child(lens)
	# Uma fonte local com sombra: útil atrás e ao lado do Dante, independente da mira.
	# Alcance menor que o da lanterna tática; nunca pinta um cone para a frente.
	lamp = OmniLight3D.new()
	lamp.omni_range = 7.0
	lamp.omni_attenuation = 1.35
	lamp.light_color = Color(1.0, .80, .54)
	lamp.light_energy = 2.8
	lamp.light_specular = .2
	lamp.shadow_enabled = true
	lamp.shadow_caster_mask = preload("res://gameplay/PersonalLightLayers.gd").SHADOW_MASK
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
	if glass.emission_enabled != lamp.visible: glass.emission_enabled = lamp.visible

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
