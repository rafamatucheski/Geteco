extends RefCounted
## Local race-meet sky, driven by the existing world clock. Adds no light/shadow.
const SHADER := preload("res://runtime/atmosphere/drag_strip_sky.gdshader")
const COMPACT := preload("res://world/desert/DesertCompactLayout.gd")
const STRIP := Rect2(Vector2(-1060+COMPACT.DRAG.x,-1380+COMPACT.DRAG.z),Vector2(1200,200))
var sky: Sky
var material: ShaderMaterial
var previous_sky: Sky
var previous_mode := Environment.BG_COLOR
var previous_reflections := Environment.REFLECTION_SOURCE_BG
var installed := false
var _flash_strength := 0.0
var _flash_id := -1

func update_lightning(strength: float, strike_id: int) -> void:
	if material == null: return
	var value := clampf(strength,0.0,1.0) if installed else 0.0
	if value > 0.0 and strike_id != _flash_id:
		_flash_id = strike_id
		material.set_shader_parameter("strike_offset",sin(float(strike_id)*2.39996)*.27)
		material.set_shader_parameter("strike_seed",fposmod(float(strike_id)*.618034,1.0))
	if not is_equal_approx(value,_flash_strength):
		_flash_strength = value
		material.set_shader_parameter("lightning_strength",value)

func apply(env: Environment, point: Vector3, hour: float, cloud_cover: float, moon_phase: float, inside: bool) -> void:
	var strip := STRIP
	var flat := Vector2(point.x,point.z)
	var nearest := flat.clamp(strip.position,strip.end)
	var weight := 1.0-smoothstep(80.0,280.0,flat.distance_to(nearest)) if not inside else 0.0
	if weight <= .001:
		if installed:
			env.sky = previous_sky
			env.background_mode = previous_mode
			env.reflected_light_source = previous_reflections
			installed = false
		return
	if material == null:
		material = ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("cloud_texture",preload("res://runtime/atmosphere/drag_cloud_noise.tres"))
		sky = Sky.new()
		sky.sky_material = material
		sky.radiance_size = Sky.RADIANCE_SIZE_32
		sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	if not installed:
		previous_sky = env.sky
		previous_mode = env.background_mode
		previous_reflections = env.reflected_light_source
		installed = true
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# The cubemap branch retains the old flat background for reflections.
	# Visible clouds and disks do not change existing car reflection lighting.
	material.set_shader_parameter("base_color",env.background_color)
	material.set_shader_parameter("region_weight",weight)
	material.set_shader_parameter("hour",fposmod(hour,1.0))
	material.set_shader_parameter("cloud_cover",cloud_cover)
	material.set_shader_parameter("moon_phase",moon_phase)
