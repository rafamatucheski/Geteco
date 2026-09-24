extends Node3D
## Item largado no chão (arma com munição ou colete), coletado só de passar por
## cima. Port de `legacy/city_demo/scenes/pickups/WeaponPickup.gd` e
## `BodyArmorPickup.gd` da V1: halo colorido por arma, ícone flutuando e girando,
## coleta imediata sem aviso na tela e sumiço suave depois de 35 s.
## A V1 desenhava uma silhueta 2D; aqui o ícone é o próprio modelo 3D da arma
## (`ArsenalWeapon3D`) ampliado para ser legível da câmera ortográfica alta,
## com um brilho aditivo que pisca.

const ARSENAL = preload("res://gameplay/ArsenalWeapon3D.gd")
## Tempo no chão antes de começar a sumir, e duração do sumiço (V1: 28 s + 7 s).
const LIFETIME := 28.0
const FADE_TIME := 7.0
## Raio horizontal de coleta. A V1 usava 22–42 px, o pé do Dante dentro do halo.
const PICKUP_RADIUS := 1.05
const ICON_HEIGHT := 0.85
## Comprimento visível do ícone (m): a pistola e o fuzil ficam do mesmo porte,
## como as silhuetas compactas da V1, em vez da pistola sumir ao lado do fuzil.
const ICON_LENGTH := 1.05

var kind := "weapon"
var weapon_id := "pistol"
var ammo_amount := 12
var armor_amount := 50
var consumed := false
var _age := 0.0
var _icon_scale := 2.4
var _phase := 0.0
var _icon: Node3D
var _halo: MeshInstance3D
var _halo_material: StandardMaterial3D
var _glow_material: StandardMaterial3D

func setup(p_kind: String, p_weapon: String = "", p_amount: int = 0) -> void:
	kind = p_kind
	if p_weapon != "": weapon_id = p_weapon
	if kind == "armor": armor_amount = p_amount if p_amount > 0 else armor_amount
	else: ammo_amount = p_amount if p_amount > 0 else ammo_amount

func _ready() -> void:
	_phase = randf() * TAU
	var tint := halo_color()
	var disc_material := StandardMaterial3D.new()
	disc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	disc_material.albedo_color = Color(tint.r, tint.g, tint.b, tint.a * 0.45)
	_halo_material = StandardMaterial3D.new()
	_halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_halo_material.albedo_color = tint
	_halo = MeshInstance3D.new()
	_halo.name = "Halo"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.42
	ring.outer_radius = 0.58
	ring.rings = 24
	ring.ring_segments = 6
	_halo.mesh = ring
	_halo.scale = Vector3(1.0, 0.08, 1.0)
	_halo.position.y = 0.04
	_halo.material_override = _halo_material
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_halo)
	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 0.30
	disc_mesh.bottom_radius = 0.30
	disc_mesh.height = 0.01
	disc_mesh.radial_segments = 24
	disc.mesh = disc_mesh
	disc.position.y = 0.03
	disc.material_override = disc_material
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	_icon = Node3D.new()
	_icon.name = "Icon"
	_icon.position.y = ICON_HEIGHT
	add_child(_icon)
	var model := Node3D.new()
	_icon.add_child(model)
	if kind == "armor": _build_vest(model)
	else:
		ARSENAL.build(model, weapon_id)
		# Deitada de lado e centrada no giro, como a silhueta da V1.
		model.rotation = Vector3(0, 0, PI * 0.5)
		model.position = -_model_center(model).rotated(Vector3.BACK, PI * 0.5)
	var extent := _model_size(model)
	_icon_scale = clampf(ICON_LENGTH / maxf(maxf(extent.x, extent.y), maxf(extent.z, 0.05)), 1.4, 4.0)
	_icon.scale = Vector3.ONE * _icon_scale
	_glow_material = StandardMaterial3D.new()
	_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_material.albedo_color = Color(tint.r, tint.g, tint.b, 0.0)
	for mesh in _icon.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).material_overlay = _glow_material
		(mesh as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Anda e pisca. Não há física: a coleta é por distância, feita por Gameplay.
func advance(delta: float) -> bool:
	if consumed: return false
	_age += delta
	var t := _age * 3.2 + _phase
	_icon.position.y = ICON_HEIGHT + sin(t) * 0.09
	_icon.rotation.y = _age * 1.6
	# Piscar: o brilho aditivo sobe e desce; no fim da vida pisca mais rápido
	# e some, avisando que o item vai desaparecer.
	var fading := clampf((_age - LIFETIME) / FADE_TIME, 0.0, 1.0)
	var rate := lerpf(5.0, 14.0, fading)
	var pulse := 0.5 + 0.5 * sin(_age * rate + _phase)
	var alive := 1.0 - fading
	_glow_material.albedo_color.a = (0.10 + 0.45 * pulse) * alive
	_halo_material.albedo_color.a = halo_color().a * (0.65 + 0.9 * pulse) * alive
	_halo.scale = Vector3(1.0 + sin(_age * 2.5) * 0.12, 0.08, 1.0 + sin(_age * 2.5) * 0.12)
	_icon.visible = alive > 0.02 and (fading < 0.35 or pulse > 0.25)
	return _age < LIFETIME + FADE_TIME

func can_collect(point: Vector3) -> bool:
	if consumed: return false
	var offset := point - global_position
	return Vector2(offset.x, offset.z).length() < PICKUP_RADIUS and absf(offset.y) < 1.6

## Encolhe e some (V1: escala 0,2 e alfa 0 em 0,25 s).
func collect() -> void:
	consumed = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_icon, "scale", Vector3.ONE * _icon_scale * 0.2, 0.25)
	tween.tween_property(_icon, "position:y", ICON_HEIGHT + 0.5, 0.25)
	tween.tween_property(_halo_material, "albedo_color:a", 0.0, 0.25)
	tween.tween_property(_glow_material, "albedo_color:a", 0.0, 0.25)
	tween.chain().tween_callback(queue_free)

## Cor do halo por família, a mesma da V1.
func halo_color() -> Color:
	if kind == "armor": return Color(0.2, 0.85, 1.0, 0.30)
	match weapon_id:
		"magnum", "pistol": return Color(1.0, 0.8, 0.2, 0.28)
		"smg", "m4a1": return Color(0.2, 0.8, 1.0, 0.28)
		"shotgun", "sawed_off", "hunting_rifle": return Color(1.0, 0.55, 0.15, 0.28)
		"ak47", "rpg", "flamethrower": return Color(1.0, 0.25, 0.25, 0.30)
		"grenade": return Color(0.2, 0.9, 0.4, 0.28)
		"knuckles": return Color(0.95, 0.75, 0.15, 0.35)
		"knife": return Color(0.65, 0.85, 0.95, 0.30)
		"axe": return Color(0.95, 0.40, 0.15, 0.32)
		"bat": return Color(0.90, 0.65, 0.25, 0.30)
	return Color(0.5, 0.9, 0.5, 0.28)

func _model_size(model: Node3D) -> Vector3:
	return _model_bounds(model).size

func _model_center(model: Node3D) -> Vector3:
	return _model_bounds(model).get_center()

func _model_bounds(model: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh as MeshInstance3D
		if instance.mesh == null: continue
		var local := model.global_transform.affine_inverse() * instance.global_transform if model.is_inside_tree() else _relative_transform(model, instance)
		var box := local * instance.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds

func _relative_transform(ancestor: Node3D, node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D: result = (current as Node3D).transform * result
		current = current.get_parent()
	return result

## Colete balístico: silhueta da V1 (alças, gola aberta, cintura afunilada e
## placas) em volume, em metros reais.
func _build_vest(root: Node3D) -> void:
	var shell := _vest_material(Color("182b38"), 0.7)
	var plate := _vest_material(Color("46677d"), 0.55)
	var light := _vest_material(Color("7798ac"), 0.45)
	var pouch := _vest_material(Color("263e50"), 0.7)
	var strap := _vest_material(Color("a8c3ce"), 0.5)
	_box(root, Vector3(0.40, 0.46, 0.10), Vector3(0, 0, 0), shell)
	_box(root, Vector3(0.11, 0.12, 0.10), Vector3(-0.145, 0.29, 0), shell)
	_box(root, Vector3(0.11, 0.12, 0.10), Vector3(0.145, 0.29, 0), shell)
	_box(root, Vector3(0.30, 0.30, 0.03), Vector3(0, 0.0, 0.055), plate)
	_box(root, Vector3(0.24, 0.10, 0.02), Vector3(0, 0.07, 0.075), light)
	_box(root, Vector3(0.09, 0.10, 0.04), Vector3(-0.06, -0.14, 0.08), pouch)
	_box(root, Vector3(0.09, 0.10, 0.04), Vector3(0.06, -0.14, 0.08), pouch)
	_box(root, Vector3(0.06, 0.04, 0.02), Vector3(-0.145, 0.30, 0.06), strap)
	_box(root, Vector3(0.06, 0.04, 0.02), Vector3(0.145, 0.30, 0.06), strap)
	root.scale = Vector3.ONE * 0.62
	root.rotation.x = -0.35

func _box(root: Node3D, size: Vector3, offset: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = offset
	mesh.material_override = material
	root.add_child(mesh)

func _vest_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
