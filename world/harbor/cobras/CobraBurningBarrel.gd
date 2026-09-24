@tool
class_name CobraBurningBarrel
extends StaticBody2D
## Tambor de fogo do território hostil dos Iron Cobras. Mesmo padrão de
## StreetLamp.gd (raiz do projeto): corpo 3D renderizado uma vez num
## SubViewport compartilhado entre instâncias intactas, modelo privado só ao
## tombar. O fogo por cima é CPUParticles2D, não CPUParticles3D dentro do
## viewport: uma partícula animada exigiria render_target_update_mode =
## UPDATE_ALWAYS, contra a filosofia de performance do projeto (ver
## docs/ARCHITECTURE.md — SubViewport majoritariamente UPDATE_ONCE). A
## paleta de chama é a mesma de world/shared/combat/PersonBurning.gd, pro
## fogo parecer o mesmo fogo em qualquer lugar do jogo.

const FALL_SPEED := 35.0
const DRUM_R := 0.24
const DRUM_H := 0.55

var broken := false
var model: Node3D
var view: SubViewport
var flames: CPUParticles2D
var glow_light: PointLight2D
var _occlusion: Area2D
var _impact_cooldown := 0.0
var _falling := false
var _has_private_model := false
var _impact_tween: Tween

static var _shared_cache: Dictionary = {}
static var flame_texture: GradientTexture2D
static var flame_colors: Gradient

func _ready() -> void:
	add_to_group("obstacle")
	add_to_group("metal_prop")
	add_to_group("fragile_road_post")
	collision_layer = 1
	collision_mask = 0
	_build_drum()
	preload("res://systems/ContactShadow.gd").add_2d(self, Vector2(15, 11), 0.35)
	var col := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 9.0
	col.shape = circle
	add_child(col)
	_build_fire()

static func _get_shared_drum_data(tree: SceneTree) -> Dictionary:
	if _shared_cache.has("drum") and is_instance_valid(_shared_cache["drum"].get("view")):
		return _shared_cache["drum"]
	var vp := SubViewport.new()
	vp.name = "SharedBurningBarrelView"
	vp.size = Vector2i(96, 96)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	tree.root.call_deferred("add_child", vp)
	var m := Node3D.new()
	vp.add_child(m)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("2f3542")
	steel.metallic = 0.55
	steel.roughness = 0.5
	var rim := StandardMaterial3D.new()
	rim.albedo_color = Color("57606f")
	rim.metallic = 0.6
	rim.roughness = 0.4
	var body := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = DRUM_R
	cylinder.bottom_radius = DRUM_R
	cylinder.height = DRUM_H
	cylinder.radial_segments = 12
	body.mesh = cylinder
	body.material_override = steel
	body.position.y = DRUM_H * 0.5
	m.add_child(body)
	var top_rim := MeshInstance3D.new()
	var ring := CylinderMesh.new()
	ring.top_radius = DRUM_R * 1.04
	ring.bottom_radius = DRUM_R * 1.04
	ring.height = 0.03
	ring.radial_segments = 12
	top_rim.mesh = ring
	top_rim.material_override = rim
	top_rim.position.y = DRUM_H - 0.02
	m.add_child(top_rim)
	var bung := MeshInstance3D.new()
	var bung_mesh := CylinderMesh.new()
	bung_mesh.top_radius = 0.03
	bung_mesh.bottom_radius = 0.03
	bung_mesh.height = 0.02
	bung.mesh = bung_mesh
	bung.material_override = rim
	bung.position = Vector3(DRUM_R * 0.5, DRUM_H - 0.02, 0)
	m.add_child(bung)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -25, 0)
	vp.add_child(sun)
	var camera := Camera3D.new()
	vp.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.3
	camera.look_at_from_position(Vector3(0, DRUM_H * 0.7, 1.4), Vector3(0, DRUM_H * 0.5, 0))
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.reset_physics_interpolation()
	var data := {"view": vp, "model": m, "texture": vp.get_texture()}
	_shared_cache["drum"] = data
	return data

func _build_drum() -> void:
	var data := _get_shared_drum_data(get_tree())
	view = data["view"]
	model = data["model"]
	var sprite := Sprite2D.new()
	sprite.name = "DrumSprite"
	sprite.texture = data["texture"]
	sprite.position = Vector2(0, -22)
	add_child(sprite)
	_occlusion = preload("res://systems/interiors/ExteriorOcclusion.gd").attach(sprite, DRUM_H * 0.5)

func _ensure_private_model() -> void:
	if _has_private_model:
		return
	_has_private_model = true
	view = SubViewport.new()
	view.size = Vector2i(96, 96)
	view.own_world_3d = true
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(view)
	model = model.duplicate() as Node3D
	view.add_child(model)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -25, 0)
	view.add_child(sun)
	var camera := Camera3D.new()
	view.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.3
	camera.position = Vector3(0, DRUM_H * 0.7, 1.4)
	camera.look_at(Vector3(0, DRUM_H * 0.5, 0))
	var sprite := get_node_or_null("DrumSprite") as Sprite2D
	if sprite:
		sprite.texture = view.get_texture()

static func _make_fire_resources() -> void:
	if flame_texture != null:
		return
	flame_texture = GradientTexture2D.new()
	flame_texture.width = 32
	flame_texture.height = 40
	flame_texture.fill = GradientTexture2D.FILL_RADIAL
	flame_texture.fill_from = Vector2(0.5, 0.5)
	flame_texture.fill_to = Vector2(0.5, 0.0)
	flame_texture.gradient = Gradient.new()
	flame_texture.gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	flame_colors = Gradient.new()
	flame_colors.offsets = PackedFloat32Array([0, 0.2, 0.6, 1])
	flame_colors.colors = PackedColorArray([Color(1, 0.95, 0.5, 0.9), Color(1, 0.65, 0.05, 1), Color(1, 0.19, 0.015, 0.8), Color(0.4, 0.06, 0.01, 0)])

func _build_fire() -> void:
	_make_fire_resources()
	flames = CPUParticles2D.new()
	flames.amount = 14
	flames.lifetime = 0.4
	flames.texture = flame_texture
	flames.color_ramp = flame_colors
	flames.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	flames.emission_rect_extents = Vector2(4, 2)
	flames.direction = Vector2.UP
	flames.spread = 16
	flames.gravity = Vector2(0, -22)
	flames.initial_velocity_min = 10
	flames.initial_velocity_max = 22
	flames.scale_amount_min = 0.2
	flames.scale_amount_max = 0.4
	flames.position = Vector2(0, -34)
	add_child(flames)
	glow_light = PointLight2D.new()
	glow_light.color = Color("ff8a3d")
	glow_light.energy = 0.75
	glow_light.texture = flame_texture
	glow_light.texture_scale = 1.4
	glow_light.position = Vector2(0, -32)
	glow_light.shadow_enabled = false
	add_child(glow_light)

# Bullet damage does not topple a sealed steel drum — same call as StreetLamp.gd.
func take_damage(_amount: int, _is_player: bool = false) -> void:
	pass

func _process(delta: float) -> void:
	_impact_cooldown = maxf(0.0, _impact_cooldown - delta)
	if _impact_cooldown <= 0.0:
		set_process(false)

func receive_vehicle_impact(speed: float, direction: Vector2) -> void:
	if not is_finite(speed) or not direction.is_finite():
		return
	if broken or _falling or speed < 15:
		return
	_impact_cooldown = 0.65
	set_process(true)
	_ensure_private_model()
	var axis := Vector3(direction.y, 0, -direction.x).normalized()
	if axis.is_zero_approx():
		axis = Vector3.FORWARD
	if _impact_tween:
		_impact_tween.kill()
	var tween := create_tween()
	_impact_tween = tween
	if speed >= FALL_SPEED:
		broken = true
		_falling = true
		collision_layer = 0
		for child in get_children():
			if child is CollisionShape2D:
				child.set_deferred("disabled", true)
		# A tombado tomba, derrama o conteúdo em chamas: apaga fogo e luz.
		flames.emitting = false
		glow_light.visible = false
		tween.tween_method(func(angle): model.quaternion = Quaternion(axis, angle); view.render_target_update_mode = SubViewport.UPDATE_ONCE, 0.0, PI * .49, .7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(func(): _falling = false)
	else:
		tween.tween_method(func(angle): model.quaternion = Quaternion(axis, angle); view.render_target_update_mode = SubViewport.UPDATE_ONCE, 0.0, .09, .12)
		tween.tween_method(func(angle): model.quaternion = Quaternion(axis, angle); view.render_target_update_mode = SubViewport.UPDATE_ONCE, .09, 0.0, .35)
	var sound := AudioStreamPlayer2D.new()
	sound.stream = ProceduralAudio.get_bullet_metal_hit_stream()
	sound.bus = &"SFX"
	sound.volume_db = -12
	sound.max_distance = 450
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()

func restore_world_prop() -> void:
	if _impact_tween:
		_impact_tween.kill()
	broken = false
	_falling = false
	_impact_cooldown = 0.0
	if is_instance_valid(model):
		model.quaternion = Quaternion.IDENTITY
	if is_instance_valid(view):
		view.render_target_update_mode = SubViewport.UPDATE_ONCE
	collision_layer = 1
	for child in get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", false)
	flames.emitting = true
	glow_light.visible = true
