extends Node3D
## V1 WeaponPickup: spin 1.6 rad/s, bob 3.2 rad/s, pulsing halo,
## and a quarter-second absorption. Only art moves; the ground anchor stays put.
var art: Node3D
var ring: MeshInstance3D
var material: StandardMaterial3D
var consumed := false
var age := 0.0
var phase := 0.0

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
	if consumed or art == null: return
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.global_position.distance_squared_to(global_position) > 6400: return
	age += delta
	art.rotation.y = age * 1.6
	art.position.y = .09 + sin(age * 3.2 + phase) * .045
	var pulse := 1.0 + sin(age * 2.5 + phase) * .12
	ring.scale = Vector3(pulse,.08,pulse)
	material.albedo_color.a = .25 + sin(age * 3.2 + phase) * .08

func collect() -> void:
	if consumed: return
	consumed = true
	set_process(false)
	var body := get_node_or_null("PickupBody") as StaticBody3D
	if body != null: body.collision_layer = 0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(art,"scale",Vector3.ONE * .2,.25)
	tween.tween_property(art,"position:y",art.position.y + .5,.25)
	tween.tween_property(material,"albedo_color:a",0.0,.25)
	for mesh in art.find_children("*","GeometryInstance3D",true,false):
		tween.tween_property(mesh,"transparency",1.0,.25)
	tween.chain().tween_callback(queue_free)
