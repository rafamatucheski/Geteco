extends Node3D
## One short-range source, two strips and a depth-tested soft ground pool.
## Smooth daylight and distance weights avoid flashing at activation edges.
const ATMOSPHERE := preload("res://runtime/atmosphere/RegionalAtmosphere3D.gd")
var car: CharacterBody3D
var ground_light: OmniLight3D
var finish: StandardMaterial3D
var ground_pool: MeshInstance3D
var ground_finish: StandardMaterial3D
var strips: Array[MeshInstance3D] = []
var strength := 0.0
static var _pool_texture: ImageTexture

static func install(owner_car: CharacterBody3D) -> Node3D:
	if owner_car.has_node("JessicaNeon"): return owner_car.get_node("JessicaNeon")
	var effect = load("res://gameplay/jessica/JessicaNeon.gd").new()
	effect.car = owner_car
	effect.name = "JessicaNeon"
	owner_car.add_child(effect)
	return effect

func _ready() -> void:
	finish = StandardMaterial3D.new()
	finish.albedo_color = Color("ce1027")
	finish.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	finish.emission_enabled = true
	finish.emission = Color("ef1027")
	finish.emission_energy_multiplier = 0.0
	for side in [-1.0,1.0]:
		var strip := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(.018,.018,1.86)
		strip.mesh = mesh
		strip.material_override = finish
		strip.position = Vector3(side*.856,.252,.13)
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		strip.hide()
		add_child(strip)
		strips.append(strip)
	ground_light = OmniLight3D.new()
	ground_light.name = "RedUnderglow"
	ground_light.position = Vector3(0,.24,.08)
	ground_light.light_color = Color("ef1027")
	ground_light.light_energy = 0.0
	ground_light.light_specular = .05
	ground_light.omni_range = 2.9
	ground_light.omni_attenuation = 1.35
	ground_light.shadow_enabled = false
	ground_light.distance_fade_enabled = true
	ground_light.distance_fade_begin = 35.0
	ground_light.distance_fade_length = 20.0
	ground_light.hide()
	add_child(ground_light)
	ground_pool = MeshInstance3D.new()
	ground_pool.name = "RedGroundPool"
	var plane := PlaneMesh.new()
	plane.size = Vector2(3.65,4.1)
	ground_pool.mesh = plane
	ground_finish = StandardMaterial3D.new()
	ground_finish.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground_finish.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ground_finish.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ground_finish.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	ground_finish.no_depth_test = false
	ground_finish.cull_mode = BaseMaterial3D.CULL_DISABLED
	ground_finish.disable_receive_shadows = true
	ground_finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	ground_finish.albedo_texture = _ground_texture()
	ground_finish.albedo_color = Color(.92,.022,.048,0)
	ground_pool.material_override = ground_finish
	ground_pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The production headlights use the same low plane/depth contract: the
	# actual car, pavement edges and other solids occlude this short pool.
	ground_pool.position = Vector3(0,.07,.08)
	ground_pool.hide()
	add_child(ground_pool)

static func _ground_texture() -> ImageTexture:
	if _pool_texture != null: return _pool_texture
	var image := Image.create_empty(64,64,false,Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var across: float = float(x)/63.0*2.0-1.0
			var along: float = float(y)/63.0*2.0-1.0
			var radius: float = Vector2(across,along).length()
			var value: float = 1.0-smoothstep(.20,1.0,radius)
			image.set_pixel(x,y,Color(value,value,value,1.0))
	image.generate_mipmaps()
	_pool_texture = ImageTexture.create_from_image(image)
	return _pool_texture

static func night_weight(time_of_day: float) -> float:
	if not is_finite(time_of_day): return 0.0
	return 1.0-smoothstep(.15,.48,ATMOSPHERE.daylight_at(clampf(time_of_day,0,1)))

func update(time_of_day: float, camera: Camera3D, exterior: bool, delta: float) -> void:
	if not is_instance_valid(car) or not is_instance_valid(ground_light): return
	var target := night_weight(time_of_day) if exterior and car.health > 0 and car.is_visible_in_tree() else 0.0
	if camera == null: target = 0.0
	else: target *= 1.0-smoothstep(35.0,60.0,camera.global_position.distance_to(car.global_position))
	strength = move_toward(strength,target,maxf(0.0,delta)*2.0)
	finish.emission_energy_multiplier = strength*1.35
	ground_light.light_energy = strength*1.2
	ground_light.visible = strength > .001
	ground_finish.albedo_color = Color(.92,.022,.048,strength*.58)
	ground_pool.visible = strength > .001
	for strip in strips: strip.visible = strength > .001
