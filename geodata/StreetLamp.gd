@tool
class_name StreetLamp
extends StaticBody2D

@export var is_facing_south: bool = true
@export var light_energy := 0.67
@export var light_radius := 480
@export var light_color := Color("ffda85")
## Aim the ground wash at the road while leaving the pole safely on the curb.
@export var road_target := Vector2.INF
@export var arm_rotation_quarters := 0
var broken := false
var model: Node3D
var view: SubViewport
var bulb: StandardMaterial3D
var _impact_cooldown := 0.0
var _falling := false
var _near_view := false
var _head_pixel := Vector2.ZERO
var _impact_tween: Tween
var _occlusion: Area2D
var _standing_z := 8
const FALL_SPEED := 35.0

var lamp_light: PointLight2D
var light_glow_sprite: Sprite2D
var lamp_sprite: Sprite2D
var is_lit: bool = false
var _has_private_model := false
const BASE_SIZE := Vector3(.36, .16, .36)
const LAMP_PPM := 16.0
static var _shared_cache: Dictionary = {}
static var _light_textures: Dictionary = {}

func _ready() -> void:
	z_index = 8 # Fica acima das calçadas
	add_to_group("obstacle")
	add_to_group("metal_prop")
	add_to_group("street_lamp")
	add_to_group("fragile_road_post")
	
	# Solid base until a strong vehicle impact knocks the pole down.
	collision_layer = 1 # Camada de Mundo / Obstáculos sólidos
	collision_mask = 0
	
	_build_lamp_post()
	preload("res://systems/ContactShadow.gd").add_2d(self, Vector2(19,13), 0.32)
	_setup_collision()
	_setup_light()
	
	# Conecta com o gerenciador de Dia/Noite
	var mgr = get_tree().get_first_node_in_group("day_night_manager")
	if mgr:
		if mgr.has_signal("time_changed"):
			mgr.time_changed.connect(set_lit)
		set_lit(mgr.get("is_dark") == true)
	else:
		set_lit(false)
	set_process(false)


func _setup_collision() -> void:
	# Same mesh dimensions and orthographic floor projection as the visible plinth.
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(BASE_SIZE.x, BASE_SIZE.z * 6.4 / sqrt(6.4 * 6.4 + 36.0)) * LAMP_PPM
	col.shape = shape
	add_child(col)

static func _get_shared_lamp_data(facing_south: bool, tree: SceneTree, light_col: Color, arm_turns: int = 0) -> Dictionary:
	var key := ("south" if facing_south else "north") + light_col.to_html() + str(arm_turns)
	if _shared_cache.has(key) and is_instance_valid(_shared_cache[key].get("view")):
		return _shared_cache[key]

	var vp := SubViewport.new()
	vp.name = "SharedStreetLampView_" + key
	vp.size = Vector2i(160, 160)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var host: Node = tree.root.get_node_or_null("PresentationBudget")
	if host and is_instance_valid(host):
		host.add_child(vp)
	else:
		tree.root.call_deferred("add_child", vp)

	var m := Node3D.new()
	vp.add_child(m)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("414952")
	steel.metallic = 0.7
	steel.roughness = 0.45
	var b := StandardMaterial3D.new()
	b.albedo_color = Color("ddd5b5")
	b.emission = light_col
	var pole := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.06
	cylinder.bottom_radius = 0.10
	cylinder.height = 3.8
	cylinder.radial_segments = 8
	pole.mesh = cylinder
	pole.material_override = steel
	pole.position.y = 1.9
	m.add_child(pole)
	var sign_z := 1.0 if facing_south else -1.0
	for part in [[Vector3(0, 0.08, 0), BASE_SIZE, steel], [Vector3(0, 3.75, sign_z * 0.45), Vector3(0.09, 0.10, 0.9), steel], [Vector3(0, 3.68, sign_z * 0.95), Vector3(0.42, 0.16, 0.65), steel], [Vector3(0, 3.58, sign_z * 0.95), Vector3(0.32, 0.045, 0.50), b]]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[1]
		mesh.mesh = box
		mesh.position = part[0]
		mesh.material_override = part[2]
		m.add_child(mesh)
	# Raised cooling fins distinguish the enclosed LED head from a bare bulb.
	for rib in 4:
		var fin := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(.035,.055,.52)
		fin.mesh = box
		fin.position = Vector3(-.15 + rib*.1,3.79,sign_z*.95)
		fin.material_override = steel
		m.add_child(fin)
	_rotate_arm_geometry(m,arm_turns)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -25, 0)
	vp.add_child(sun)
	var camera := Camera3D.new()
	vp.add_child(camera)
	camera.look_at_from_position(Vector3(0, 8, 6), Vector3(0, 1.6, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.reset_physics_interpolation()
	# Camera is attached deferred; compute the same orthographic foot analytically.
	var sprite_pos := Vector2(0, -1.6 * 6.0 / sqrt(6.4 * 6.4 + 36.0) * LAMP_PPM)
	var head_px := Vector2(0.0, -29.40035 if facing_south else -51.57829)
	if arm_turns != 0: head_px = Vector2(15.2*signf(float(arm_turns)), -40.48932)

	var data := {
		"view": vp,
		"model": m,
		"bulb": b,
		"sprite_pos": sprite_pos,
		"head_pixel": head_px,
		"texture": vp.get_texture()
	}
	_shared_cache[key] = data
	return data

static func _rotate_arm_geometry(root: Node3D, turns: int) -> void:
	var angle := turns*PI*.5
	for part in root.get_children():
		if part is MeshInstance3D:
			part.position = part.position.rotated(Vector3.UP,angle)
			part.rotate_y(angle)

func _ensure_private_model() -> void:
	if _has_private_model: return
	_has_private_model = true
	view = SubViewport.new()
	view.size = Vector2i(160, 160)
	view.own_world_3d = true
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(view)
	# Preserve every authored part (including head fins) when leaving the cache.
	model = model.duplicate() as Node3D
	var shared_bulb := bulb
	bulb = bulb.duplicate() as StandardMaterial3D
	bulb.emission_enabled = is_lit and not broken
	for part in model.get_children():
		if part is MeshInstance3D and part.material_override is StandardMaterial3D:
			if part.material_override == shared_bulb:
				part.material_override = bulb
	view.add_child(model)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -25, 0)
	view.add_child(sun)
	var camera := Camera3D.new()
	view.add_child(camera)
	camera.position = Vector3(0, 8, 6)
	camera.look_at(Vector3(0, 1.6, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8
	if lamp_sprite:
		lamp_sprite.texture = view.get_texture()

func _build_lamp_post() -> void:
	var data := _get_shared_lamp_data(is_facing_south, get_tree(), light_color, arm_rotation_quarters)
	view = data["view"]
	model = data["model"]
	bulb = data["bulb"]
	_head_pixel = data["head_pixel"]
	lamp_sprite = Sprite2D.new()
	lamp_sprite.texture = data["texture"]
	lamp_sprite.scale = Vector2(0.8, 0.8)
	lamp_sprite.position = data["sprite_pos"]
	add_child(lamp_sprite)
	_occlusion = preload("res://systems/interiors/ExteriorOcclusion.gd").attach(lamp_sprite, 0.0)
	var notifier := VisibleOnScreenNotifier2D.new()
	# Keep illumination active while its pool still intersects the screen.
	var visibility_extent := maxf(180.0, float(light_radius) * 0.5 + (road_target.length() if road_target.is_finite() else 24.0))
	notifier.rect = Rect2(Vector2.ONE * -visibility_extent, Vector2.ONE * visibility_extent * 2.0)
	add_child(notifier)
	notifier.screen_entered.connect(func():
		_near_view = true
		if _occlusion and not broken:
			_occlusion.monitoring = true
		set_lit(is_lit)
	)
	notifier.screen_exited.connect(func():
		_near_view = false
		if _occlusion:
			_occlusion.monitoring = false
			_occlusion.bodies.clear()
			_occlusion.set_process(false)
			if _occlusion.overlay:
				_occlusion.overlay.hide()
		set_lit(is_lit)
	)
	_near_view = notifier.is_on_screen()
	if _occlusion and not _near_view:
		_occlusion.monitoring = false

func _setup_light() -> void:
	var arm_offset = Vector2(0, 24) if is_facing_south else Vector2(0, -24)
	if road_target.is_finite(): arm_offset = road_target
	
	# Ponto de Luz Âmbar Suave 2D para calçadas e travessias
	lamp_light = PointLight2D.new()
	lamp_light.name = "LampLight"
	lamp_light.color = light_color
	lamp_light.energy = light_energy
	lamp_light.position = arm_offset
	lamp_light.height = 65
	var tex := _road_wash_texture(light_radius)
	lamp_light.texture = tex
	lamp_light.visible = false
	add_child(lamp_light)
	light_glow_sprite=Sprite2D.new()
	light_glow_sprite.texture=tex
	light_glow_sprite.modulate=Color(light_color.r, light_color.g, light_color.b, 0.8)
	light_glow_sprite.scale=Vector2.ONE*(10.0/float(light_radius))
	light_glow_sprite.position=_head_pixel
	var glow_material:=CanvasItemMaterial.new()
	glow_material.light_mode=CanvasItemMaterial.LIGHT_MODE_UNSHADED
	glow_material.blend_mode=CanvasItemMaterial.BLEND_MODE_ADD
	light_glow_sprite.material=glow_material
	add_child(light_glow_sprite)

static func _road_wash_texture(diameter: int) -> GradientTexture2D:
	if _light_textures.has(diameter): return _light_textures[diameter]
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.58, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 0.90),
		Color(1, 1, 1, 0.74),
		Color(1, 1, 1, 0.32),
		Color(1, 1, 1, 0.0)
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = diameter
	tex.height = diameter
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_light_textures[diameter] = tex
	return tex


func set_lit(lit: bool) -> void:
	is_lit = lit
	if lamp_light:
		lamp_light.visible = is_lit and not broken and _near_view
	if light_glow_sprite:
		light_glow_sprite.visible = is_lit and not broken and _near_view
	if bulb and is_instance_valid(bulb) and is_instance_valid(view):
		if bulb.emission_enabled != (is_lit and not broken):
			bulb.emission_enabled = is_lit and not broken
			view.render_target_update_mode = SubViewport.UPDATE_ONCE

# Bullet damage does not count as a vehicle impulse.
func take_damage(_amount: int, _is_player: bool = false) -> void:
	pass

func _process(delta: float) -> void:
	_impact_cooldown = maxf(0.0, _impact_cooldown - delta)
	if _impact_cooldown <= 0.0:
		set_process(false)

func receive_vehicle_impact(speed: float, direction: Vector2) -> void:
	if not is_finite(speed) or not direction.is_finite(): return
	if broken or _falling or speed < 15 or (_impact_cooldown > 0 and speed < FALL_SPEED): return
	_impact_cooldown = 0.65
	set_process(true)
	_ensure_private_model()
	var axis := Vector3(direction.y, 0, -direction.x).normalized()
	if axis.is_zero_approx(): axis=Vector3.FORWARD
	if _impact_tween: _impact_tween.kill()
	var tween:=create_tween()
	_impact_tween = tween
	if speed>=FALL_SPEED:
		_standing_z = z_index
		broken=true
		_falling=true
		collision_layer=0
		for child in get_children():
			if child is CollisionShape2D: child.set_deferred("disabled",true)
		set_lit(is_lit)
		tween.tween_method(func(angle): model.quaternion=Quaternion(axis,angle); view.render_target_update_mode=SubViewport.UPDATE_ONCE,0.0,PI*.49,.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(_settle_on_ground)
	else:
		tween.tween_method(func(angle): model.quaternion=Quaternion(axis,angle); view.render_target_update_mode=SubViewport.UPDATE_ONCE,0.0,.09,.12)
		tween.tween_method(func(angle): model.quaternion=Quaternion(axis,angle); view.render_target_update_mode=SubViewport.UPDATE_ONCE,.09,0.0,.35)
	var sound:=AudioStreamPlayer2D.new()
	sound.stream=ProceduralAudio.get_bullet_metal_hit_stream()
	sound.bus=&"SFX"
	sound.volume_db=-12
	sound.max_distance=450
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()

func _settle_on_ground() -> void:
	_falling = false
	# The wreck now rests on the road, below the lowest vehicle layer (8).
	# A standing-pole overlay would incorrectly repaint it across cabin roofs.
	z_index = 7
	_occlusion.monitoring = false
	_occlusion.set_process(false)
	_occlusion.bodies.clear()
	_occlusion.overlay.hide()

func restore_world_prop() -> void:
	if _impact_tween: _impact_tween.kill()
	broken = false
	_falling = false
	z_index = _standing_z
	_occlusion.monitoring = true
	_impact_cooldown = 0.0
	model.quaternion = Quaternion.IDENTITY
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	collision_layer = 1
	for child in get_children():
		if child is CollisionShape2D: child.set_deferred("disabled", false)
	set_lit(is_lit)
