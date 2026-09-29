extends Node3D
## V1 WeaponPickup: spin 1.6 rad/s, bob 3.2 rad/s, pulsing halo,
## and a quarter-second absorption. Only art moves; the ground anchor stays put.
var art: Node3D
var ring: MeshInstance3D
var material: StandardMaterial3D
var consumed := false
var age := 0.0
var phase := 0.0
var _tween: Tween
## Ajustes para peças grandes (baú): sem giro/flutuação, halo maior. Padrões = V1.
var spin_speed := 1.6
var bob_height := .045
var lift := .09
var halo_scale := 1.0

func configure(model: Node3D, item: String) -> void:
	art = model
	art.name = "Visual"
	add_child(art)
	phase = float(hash(item) % 1000) / 1000.0 * TAU
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(.3,.85,1,.3) if item == "water" else Color(.95,.75,.25,.3)
	if item in ["apple","sandwich"]: material.albedo_color = Color(.3,.9,.45,.3)
	ring = MeshInstance3D.new()
	ring.name = "PickupHalo"
	var mesh := TorusMesh.new()
	mesh.inner_radius = .29
	mesh.outer_radius = .35
	mesh.rings = 24
	mesh.ring_segments = 6
	ring.mesh = mesh
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = .015
	ring.scale.y = .08
	add_child(ring)

func _process(delta: float) -> void:
	if consumed or art == null or not is_visible_in_tree(): return
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.global_position.distance_squared_to(global_position) > 6400: return
	age += delta
	art.rotation.y = age * spin_speed
	art.position.y = lift + sin(age * 3.2 + phase) * bob_height
	var pulse := 1.0 + sin(age * 2.5 + phase) * .12
	ring.scale = Vector3(pulse * halo_scale,.08,pulse * halo_scale)
	material.albedo_color.a = .25 + sin(age * 3.2 + phase) * .08

## `keep` deixa o nó vivo e escondido no fim da absorção: recompensas fixas do mundo
## voltam com `set_available(true)` (novo jogo, recibo removido) sem recriar o visual.
func collect(keep := false) -> void:
	if consumed: return
	consumed = true
	set_process(false)
	var body := get_node_or_null("PickupBody") as StaticBody3D
	if body != null: body.collision_layer = 0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(art,"scale",Vector3.ONE * .2,.25)
	_tween.tween_property(art,"position:y",art.position.y + .5,.25)
	_tween.tween_property(material,"albedo_color:a",0.0,.25)
	for mesh in art.find_children("*","GeometryInstance3D",true,false):
		_tween.tween_property(mesh,"transparency",1.0,.25)
	_tween.chain().tween_callback(_finish_collect.bind(keep))

func _finish_collect(keep: bool) -> void:
	if keep: visible = false
	else: queue_free()

## Interface das recompensas de mundo (`set_reward_available`): some com a animação
## de absorção quando `animate`, aparece de volta restaurando o estado do visual.
func set_available(available: bool, animate := false) -> void:
	if available:
		if consumed:
			if _tween != null and _tween.is_valid(): _tween.kill()
			consumed = false
			art.scale = Vector3.ONE
			material.albedo_color.a = .25
			for mesh in art.find_children("*","GeometryInstance3D",true,false):
				mesh.transparency = 0.0
			set_process(true)
		visible = true
	elif _tween != null and _tween.is_running():
		return
	elif animate and visible and not consumed:
		collect(true)
	else:
		visible = false
