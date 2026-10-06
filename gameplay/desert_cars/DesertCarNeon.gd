extends Node3D
## Exterior underbody kit. Session supplies the clock and the current camera;
## there is no scene search, autonomous process or per-car physics probe.
const ATMOSPHERE := preload("res://runtime/atmosphere/RegionalAtmosphere3D.gd")
const GROUP := "desert_car_neon"
const FADE_BEGIN := 34.0
const FADE_END := 58.0
const FLOOR_LIFT := .045 # Above the road's .026/.030 visual paving layers.
static var _pool_texture: ImageTexture
static var _mesh_cache: Dictionary = {}
static var _housing_finish: StandardMaterial3D

var car: CharacterBody3D
var ground_light: SpotLight3D
var ground_pool: MeshInstance3D
var ground_finish: StandardMaterial3D
var strip_finish: StandardMaterial3D
var strips: Array[MeshInstance3D] = []
var strength := 0.0
var color := Color("73edc3")
var maximum_strength := 1.0
var _spec: Dictionary = {}
var _ground_strength := 0.0
var _last_strength := -1.0
var _last_ground_strength := -1.0

## Call after Vehicle._ready. Passing a stock/legacy spec creates no effect.
## Reapplying tuning/save state reuses the exact same kit and light source.
static func install(owner_car: CharacterBody3D, specification: Dictionary = {}) -> Node3D:
	if not is_instance_valid(owner_car): return null
	var existing := owner_car.get_node_or_null("DesertCarNeon")
	if existing != null: return existing as Node3D
	if float(specification.get("neon_strength",0.0)) <= 0.0: return null
	if not specification.has("size") or not specification.has("neon_color"): return null
	var effect = load("res://gameplay/desert_cars/DesertCarNeon.gd").new()
	effect.car = owner_car
	effect._spec = specification.duplicate(true)
	effect.name = "DesertCarNeon"
	owner_car.add_child(effect)
	return effect

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	add_to_group(GROUP)
	color = Color(str(_spec.get("neon_color","73edc3")))
	maximum_strength = clampf(float(_spec.get("neon_strength",1.0)),0.0,1.0)
	var width := float(_spec["size"][0])
	var length := float(_spec["size"][2])
	var radius := float(_spec.get("wheel_radius",.33))
	var strip_length := length*.47
	var strip_height := radius*.67
	strip_finish = StandardMaterial3D.new()
	strip_finish.resource_name = "desert_neon_tube" # Never classified as paint/headlight.
	strip_finish.albedo_color = color* .06
	strip_finish.roughness = .48
	strip_finish.metallic = .0
	strip_finish.emission_enabled = true
	strip_finish.emission = color
	strip_finish.emission_energy_multiplier = 0.0
	for side in [-1.0,1.0]:
		# The dark mounting rail joins the tube to the sill; the luminous core
		# hangs underneath it, between the tyres, and reads from the drag camera.
		var point := Vector3(side*width*.475,strip_height,.035)
		_mesh("NeonRail",_box_mesh(Vector3(.058,.044,strip_length+.06)),point+Vector3.UP*.023,_housing_material())
		var strip := _mesh("NeonTube",_box_mesh(Vector3(.034,.030,strip_length)),point,strip_finish)
		strips.append(strip)
	_build_ground(width,length)
	_build_light(width)

func _build_ground(width: float, length: float) -> void:
	var key := "pool:%s:%s" % [width,length]
	if not _mesh_cache.has(key):
		var plane := PlaneMesh.new()
		plane.size = Vector2(width+1.20,length*.82)
		_mesh_cache[key] = plane
	ground_finish = StandardMaterial3D.new()
	ground_finish.resource_name = "desert_neon_ground"
	ground_finish.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground_finish.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ground_finish.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ground_finish.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	ground_finish.no_depth_test = false
	ground_finish.cull_mode = BaseMaterial3D.CULL_BACK
	ground_finish.disable_receive_shadows = true
	ground_finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	ground_finish.albedo_texture = _ground_texture()
	ground_finish.albedo_color = Color(color.r,color.g,color.b,0)
	ground_pool = _mesh("NeonGroundPool",_mesh_cache[key],Vector3(0,FLOOR_LIFT,.035),ground_finish)
	ground_pool.hide()

func _build_light(width: float) -> void:
	ground_light = SpotLight3D.new()
	ground_light.name = "NeonDownlight"
	# One downward, shadowless source: it cannot illuminate the roof or distant
	# facades. The depth-tested side wash supplies the elongated footprint.
	ground_light.position = Vector3(0,.42,.035)
	ground_light.rotation.x = -PI*.5
	ground_light.light_color = color
	ground_light.light_energy = 0.0
	ground_light.light_specular = .08
	ground_light.light_indirect_energy = 0.0
	ground_light.light_volumetric_fog_energy = 0.0
	ground_light.light_bake_mode = Light3D.BAKE_DISABLED
	ground_light.spot_range = minf(1.8,width*.90)
	ground_light.spot_angle = 76.0
	ground_light.spot_angle_attenuation = .45
	ground_light.spot_attenuation = .65
	ground_light.shadow_enabled = false
	ground_light.hide()
	add_child(ground_light)

static func night_weight(time_of_day: float) -> float:
	if not is_finite(time_of_day): return 0.0
	return 1.0-smoothstep(.16,.57,ATMOSPHERE.daylight_at(fposmod(time_of_day,1.0)))

static func distance_weight(distance: float) -> float:
	if not is_finite(distance): return 0.0
	return 1.0-smoothstep(FADE_BEGIN,FADE_END,maxf(0.0,distance))

func update(time_of_day: float, camera: Camera3D, exterior: bool, delta: float) -> void:
	if not is_instance_valid(car) or not is_instance_valid(ground_light): return
	if not is_finite(delta) or delta <= 0.0: return
	var target := 0.0
	if exterior and is_instance_valid(camera) and car.is_visible_in_tree() and float(car.get("health")) > 0.0 and not car.has_meta("awaiting_ground"):
		target = maximum_strength*night_weight(time_of_day)*distance_weight(camera.global_position.distance_to(car.global_position))
	strength = move_toward(strength,target,delta*1.8)
	# Use the body's actual floor contact. A jump keeps the installed tubes lit
	# while the floor wash immediately vanishes, instead of floating with it.
	var supported := car.is_on_floor()
	var ground_target := strength if supported else 0.0
	_ground_strength = move_toward(_ground_strength,ground_target,delta*4.0) if supported else 0.0
	if strength > .001 and supported:
		var normal := (car.global_basis.inverse()*car.get_floor_normal()).normalized()
		if normal.is_finite() and normal.dot(Vector3.UP) > .55:
			var along := Vector3.BACK.slide(normal).normalized()
			var across := normal.cross(along).normalized()
			ground_pool.basis = Basis(across,normal,along)
			ground_pool.position = normal*FLOOR_LIFT+along*.035
	if not is_equal_approx(strength,_last_strength):
		_last_strength = strength
		strip_finish.albedo_color = Color(color.r,color.g,color.b)*lerpf(.06,.65,strength)
		strip_finish.emission_energy_multiplier = strength*1.65
	if not is_equal_approx(_ground_strength,_last_ground_strength):
		_last_ground_strength = _ground_strength
		ground_finish.albedo_color = Color(color.r,color.g,color.b,_ground_strength*.74)
		ground_pool.visible = _ground_strength > .001
		ground_light.light_energy = _ground_strength*.85
		ground_light.visible = _ground_strength > .001

static func _ground_texture() -> ImageTexture:
	if _pool_texture != null: return _pool_texture
	var image := Image.create(96,128,false,Image.FORMAT_RGBA8)
	for y in 128:
		var along := absf(float(y)/127.0*2.0-1.0)
		var end_fade := 1.0-smoothstep(.53,1.0,along)
		for x in 96:
			var across := absf(float(x)/95.0*2.0-1.0)
			# Two soft ribbons under the sills, rather than one giant oval.
			var ribbon := exp(-pow((across-.57)/.26,2.0)*2.0)
			var spill := .12*(1.0-smoothstep(.18,.95,across))
			var value := (ribbon+spill)*end_fade*(1.0-smoothstep(.82,1.0,across))
			image.set_pixel(x,y,Color(value,value,value,1.0))
	image.generate_mipmaps()
	_pool_texture = ImageTexture.create_from_image(image)
	return _pool_texture

static func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "box:%s" % size
	if not _mesh_cache.has(key):
		var mesh := BoxMesh.new()
		mesh.size = size
		_mesh_cache[key] = mesh
	return _mesh_cache[key] as BoxMesh

static func _housing_material() -> StandardMaterial3D:
	if _housing_finish == null:
		_housing_finish = StandardMaterial3D.new()
		_housing_finish.albedo_color = Color("141a21")
		_housing_finish.roughness = .66
	return _housing_finish

func _mesh(label: String, mesh: Mesh, point: Vector3, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = mesh
	part.position = point
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	return part
