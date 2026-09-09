@tool
class_name StreetLamp
extends StaticBody2D

@export var is_facing_south: bool = true
@export var light_energy := 0.85
@export var light_radius := 300
@export var light_color := Color(1.0,0.90,0.72)
var broken := false
var model: Node3D
var view: SubViewport
var bulb: StandardMaterial3D
var _impact_cooldown := 0.0
var _falling := false
var _near_view := true
var _head_pixel := Vector2.ZERO

var lamp_light: PointLight2D
var light_glow_sprite: Sprite2D
var lamp_sprite: Sprite2D
var is_lit: bool = false
var _has_private_model := false
static var _shared_cache: Dictionary = {}

func _ready() -> void:
	z_index = 8 # Fica acima das calçadas
	add_to_group("obstacle")
	add_to_group("metal_prop")
	add_to_group("street_lamp")
	
	# Solid base until a strong vehicle impact knocks the pole down.
	collision_layer = 1 # Camada de Mundo / Obstáculos sólidos
	collision_mask = 0
	
	_build_lamp_post()
	_setup_collision()
	_setup_light()
	
	# Conecta com o gerenciador de Dia/Noite
	var mgr = get_tree().get_first_node_in_group("day_night_manager")
	if mgr:
		mgr.time_changed.connect(set_lit)
		set_lit(mgr.get("is_dark") == true)
	else:
		set_lit(false)


func _setup_collision() -> void:
	# Colisor cilíndrico sólido de ferro fundido na base
	var col := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5.0
	col.shape = circle
	col.position = Vector2.ZERO
	add_child(col)

static func _get_shared_lamp_data(facing_south: bool, tree: SceneTree, light_col: Color) -> Dictionary:
	var key := "south" if facing_south else "north"
	if _shared_cache.has(key) and is_instance_valid(_shared_cache[key].get("view")):
		return _shared_cache[key]

	var vp := SubViewport.new()
	vp.name = "SharedStreetLampView_" + key
	vp.size = Vector2i(160, 160)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	tree.root.add_child(vp)

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
	for part in [[Vector3(0, 0.08, 0), Vector3(0.36, 0.16, 0.36), steel], [Vector3(0, 3.75, sign_z * 0.45), Vector3(0.09, 0.10, 0.9), steel], [Vector3(0, 3.68, sign_z * 0.95), Vector3(0.42, 0.16, 0.65), steel], [Vector3(0, 3.58, sign_z * 0.95), Vector3(0.32, 0.045, 0.50), b]]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[1]
		mesh.mesh = box
		mesh.position = part[0]
		mesh.material_override = part[2]
		m.add_child(mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -25, 0)
	vp.add_child(sun)
	var camera := Camera3D.new()
	vp.add_child(camera)
	camera.position = Vector3(0, 8, 6)
	camera.look_at(Vector3(0, 1.6, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8
	var sprite_pos := (Vector2(80, 80) - camera.unproject_position(Vector3.ZERO)) * 0.8
	var head_px := (camera.unproject_position(Vector3(0, 3.7, sign_z * 0.95)) - camera.unproject_position(Vector3.ZERO)) * 0.8

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

func _ensure_private_model() -> void:
	if _has_private_model: return
	_has_private_model = true
	view = SubViewport.new()
	view.size = Vector2i(160, 160)
	view.own_world_3d = true
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(view)
	model = Node3D.new()
	view.add_child(model)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("414952")
	steel.metallic = 0.7
	steel.roughness = 0.45
	bulb = StandardMaterial3D.new()
	bulb.albedo_color = Color("ddd5b5")
	bulb.emission = light_color
	bulb.emission_enabled = is_lit and not broken
	var pole := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.06
	cylinder.bottom_radius = 0.10
	cylinder.height = 3.8
	cylinder.radial_segments = 8
	pole.mesh = cylinder
	pole.material_override = steel
	pole.position.y = 1.9
	model.add_child(pole)
	var sign_z := 1.0 if is_facing_south else -1.0
	for part in [[Vector3(0, 0.08, 0), Vector3(0.36, 0.16, 0.36), steel], [Vector3(0, 3.75, sign_z * 0.45), Vector3(0.09, 0.10, 0.9), steel], [Vector3(0, 3.68, sign_z * 0.95), Vector3(0.42, 0.16, 0.65), steel], [Vector3(0, 3.58, sign_z * 0.95), Vector3(0.32, 0.045, 0.50), bulb]]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[1]
		mesh.mesh = box
		mesh.position = part[0]
		mesh.material_override = part[2]
		model.add_child(mesh)
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
	var data := _get_shared_lamp_data(is_facing_south, get_tree(), light_color)
	view = data["view"]
	model = data["model"]
	bulb = data["bulb"]
	_head_pixel = data["head_pixel"]
	lamp_sprite = Sprite2D.new()
	lamp_sprite.texture = data["texture"]
	lamp_sprite.scale = Vector2(0.8, 0.8)
	lamp_sprite.position = data["sprite_pos"]
	add_child(lamp_sprite)
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.rect = Rect2(-180, -180, 360, 360)
	add_child(notifier)
	notifier.screen_entered.connect(func(): _near_view = true; set_lit(is_lit))
	notifier.screen_exited.connect(func(): _near_view = false; set_lit(is_lit))

func _setup_light() -> void:
	var arm_offset = Vector2(0, 24) if is_facing_south else Vector2(0, -24)
	
	# Ponto de Luz Âmbar Suave 2D para calçadas e travessias
	lamp_light = PointLight2D.new()
	lamp_light.name = "LampLight"
	lamp_light.color = light_color
	lamp_light.energy = light_energy
	lamp_light.position = arm_offset
	
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.20, 0.58, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.95, 0.82, 0.65),
		Color(1.0, 0.90, 0.72, 0.40),
		Color(0.95, 0.82, 0.58, 0.14),
		Color(0.90, 0.75, 0.50, 0.0)
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = light_radius
	tex.height = light_radius
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	lamp_light.texture = tex
	lamp_light.visible = false
	add_child(lamp_light)
	light_glow_sprite=Sprite2D.new()
	light_glow_sprite.texture=tex
	light_glow_sprite.scale=Vector2.ONE*(10.0/float(light_radius))
	light_glow_sprite.position=_head_pixel
	var glow_material:=CanvasItemMaterial.new()
	glow_material.light_mode=CanvasItemMaterial.LIGHT_MODE_UNSHADED
	glow_material.blend_mode=CanvasItemMaterial.BLEND_MODE_ADD
	light_glow_sprite.material=glow_material
	add_child(light_glow_sprite)


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

func receive_vehicle_impact(speed: float, direction: Vector2) -> void:
	if broken or _falling or _impact_cooldown > 0 or speed < 35: return
	_impact_cooldown = 0.65
	_ensure_private_model()
	var axis := Vector3(direction.y, 0, -direction.x).normalized()
	if axis.is_zero_approx(): axis=Vector3.FORWARD
	var tween:=create_tween()
	if speed>=170:
		broken=true
		_falling=true
		collision_layer=0
		for child in get_children():
			if child is CollisionShape2D: child.set_deferred("disabled",true)
		set_lit(is_lit)
		tween.tween_method(func(angle): model.quaternion=Quaternion(axis,angle); view.render_target_update_mode=SubViewport.UPDATE_ONCE,0.0,PI*.49,.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
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
