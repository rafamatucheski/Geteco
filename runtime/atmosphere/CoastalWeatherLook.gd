extends RefCounted
## A dry sun, B marine/cloud breaks, C rain. One shared reflection environment;
## no per-car traversal, extra light, screen copy or reflection camera.
const SKY_SHADER := preload("res://runtime/atmosphere/coastal_reflection_sky.gdshader")
var sky: Sky
var material: ShaderMaterial
var previous_sky: Sky
var previous_reflections := Environment.REFLECTION_SOURCE_BG
var installed := false
var _last_colors: Dictionary = {}
var _last_clouds := -1.0
var _last_sun_direction := Vector3.ZERO
var _sun: DirectionalLight3D
var _previous_shadow_opacity := 1.0
var _previous_shadow_blur := 1.0
var current: Dictionary = {}

static func sample(daylight: float, clouds: float, wetness: float) -> Dictionary:
	var day := clampf(daylight,0.0,1.0)
	var closed := smoothstep(.52,.72,clouds)
	var marine := maxf(smoothstep(.05,.52,clouds)*(1.0-closed),wetness*(1.0-closed))
	# A cor pertence à luz, não a uma sobreposição quente na imagem inteira: o
	# mesmo painel branco parece mel no sol direto e azul-ardósia na sombra.
	var sun := Color(1.0,.90,.72).lerp(Color(1.0,.94,.79),marine).lerp(Color(.90,.96,1.0),closed)
	var shadow := Color(1.025,1.025,1.015).lerp(Color(.89,1.065,1.015),marine).lerp(Color(.98,1.015,1.025),closed)
	return {"sun":Color.WHITE.lerp(sun,day),"shadow":Color.WHITE.lerp(shadow,day),
		"saturation":lerpf(1.025,.85,closed),"contrast":lerpf(1.015,.99,closed),
		# A luz nublada é ampla, mas um preenchimento extra forte lavava o concreto
		# e apagava a separação entre a fachada azul e as pilastras.
		"direct_energy":lerpf(.98,.77,closed),"bounce_energy":lerpf(.055,.065,closed)*day,
		"shadow_opacity":lerpf(lerpf(.82,.72,marine),.42,closed),
		# Pegada de PCF modesta: mantém o contato e evita o granulado de kernels largos.
		"shadow_blur":lerpf(lerpf(1.25,1.45,marine),1.65,closed),
		"fog":Color("182432").lerp(Color("b1b8ae").lerp(Color("8eaaa9"),marine).lerp(Color("829199"),closed),day),
		"top":Color("101b2b").lerp(Color("648da4").lerp(Color("6d95a4"),marine).lerp(Color("788790"),closed),day),
		"horizon":Color("142131").lerp(Color("dec49a").lerp(Color("bfd3cf"),marine).lerp(Color("bac2c5"),closed),day),
		"ground":Color("080d15").lerp(Color("424b51"),day),
		"cloud":Color("121b28").lerp(Color("eddfc6").lerp(Color("e3e8df"),marine).lerp(Color("a4b1b7"),closed),day),
		"rain_weight":closed,"marine_weight":marine}

func apply(env: Environment, sun: DirectionalLight3D, daylight: float, clouds: float, wetness: float, region_weight: float, inside: bool, hour: float = .5) -> void:
	var weight := clampf(region_weight,0.0,1.0) if not inside else 0.0
	if weight <= .001:
		release(env)
		current.clear()
		return
	if not installed:
		_sun = sun
		_previous_shadow_opacity = sun.shadow_opacity
		_previous_shadow_blur = sun.shadow_blur
	current = sample(daylight,clouds,wetness)
	# A é um fim de tarde dourado, enquanto B mantém um sol marfim sobre o reflexo
	# do mar. Limita o calor extra à luz solar e ao horizonte de reflexão;
	# a rua na sombra e as paredes pintadas de azul mantêm as próprias cores.
	var local_hour := fposmod(hour,1.0)
	var afternoon := smoothstep(.60,.72,local_hour)*(1.0-smoothstep(.77,.85,local_hour))
	var golden: float = afternoon*daylight*(1.0-current.rain_weight)*(1.0-current.marine_weight*.82)
	current.sun = current.sun.lerp(Color(1.0,.79,.52),golden*.68)
	current.direct_energy *= 1.0+golden*.12
	current.horizon = current.horizon.lerp(Color("edc38a"),golden*.45)
	current.cloud = current.cloud.lerp(Color("f3dbb4"),golden*.35)
	sun.light_color *= Color.WHITE.lerp(current.sun,weight)
	sun.light_energy *= lerpf(1.0,current.direct_energy,weight*daylight)
	sun.shadow_opacity = lerpf(_previous_shadow_opacity,current.shadow_opacity,weight*daylight)
	sun.shadow_blur = lerpf(_previous_shadow_blur,current.shadow_blur*_shadow_texel_scale(sun),weight*daylight)
	# A luz da tarde corta as formas de lado como nos estudos A/B escritos.
	# Mantém o ângulo lunar alto existente à noite: uma lua baixa cria cunhas
	# de sombra enormes sobre bairros inteiros na câmera elevada do jogo.
	var solar_elevation := maxf(35.0,70.0*maxf(0.0,sin((fposmod(hour,1.0)-.25)*TAU)))
	sun.rotation_degrees.x = lerpf(sun.rotation_degrees.x,-solar_elevation,weight*smoothstep(.15,.55,daylight))
	env.ambient_light_color *= Color.WHITE.lerp(current.shadow,weight)
	env.ambient_light_energy += current.bounce_energy*weight
	env.adjustment_saturation *= lerpf(1.0,current.saturation,weight)
	env.adjustment_contrast *= lerpf(1.0,current.contrast,weight)
	env.fog_light_color = env.fog_light_color.lerp(current.fog,weight*.45)
	if material == null:
		material = ShaderMaterial.new()
		material.shader = SKY_SHADER
		sky = Sky.new()
		sky.sky_material = material
		sky.radiance_size = Sky.RADIANCE_SIZE_64
		sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	if not installed:
		previous_sky = env.sky
		previous_reflections = env.reflected_light_source
		installed = true
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# Só atualiza a radiância quando o gradiente lento do clima muda visivelmente.
	# No TIME/LIGHT uniforms: moving headlights do not rebuild the cubemap.
	for key in ["top","horizon","ground","cloud"]:
		var color: Color = env.background_color.lerp(current[key],weight)
		if not _last_colors.has(key) or _color_distance(color,_last_colors[key])>.008:
			material.set_shader_parameter(key+"_color",color)
			_last_colors[key] = color
	# Aberturas largas nas nuvens fazem vidros/pintura curva parecerem objetos reflexivos,
	# sem cópias em espaço de tela nem reflexos artificiais da geometria próxima.
	var reflection_clouds := clampf(clouds,0.0,1.0)
	if absf(reflection_clouds-_last_clouds)>.015:
		material.set_shader_parameter("cloud_cover",reflection_clouds)
		_last_clouds = reflection_clouds
	# Scene-independent basis also supports the isolated contract test.
	var direction := sun.basis.z.normalized()
	if direction.distance_to(_last_sun_direction)>.025:
		material.set_shader_parameter("sun_direction",direction)
		_last_sun_direction = direction

static func _shadow_texel_scale(sun: DirectionalLight3D) -> float:
	# Os offsets de PCF são medidos em texels do atlas. Mantém a pegada escrita
	# comparável quando a qualidade do jogador usa um atlas maior; não
	# muda essa configuração nem liga filtragem nos níveis duros de propósito.
	if not sun.is_inside_tree(): return 1.0
	var settings := sun.get_node_or_null("/root/V2Settings")
	if settings == null: return 1.0
	return clampf(float(settings.SHADOW_ATLAS[settings.shadow_quality])/2048.0,1.0,4.0)

static func _color_distance(a: Color, b: Color) -> float:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))

func release(env: Environment) -> void:
	if installed and is_instance_valid(_sun):
		_sun.shadow_opacity = _previous_shadow_opacity
		_sun.shadow_blur = _previous_shadow_blur
	if installed and env.sky == sky:
		env.sky = previous_sky
		env.reflected_light_source = previous_reflections
	installed = false

static func advance_wetness(value: float, raining: bool, delta: float) -> float:
	return clampf(value+(1.0/45.0 if raining else -1.0/120.0)*maxf(delta,0.0),0.0,1.0)
