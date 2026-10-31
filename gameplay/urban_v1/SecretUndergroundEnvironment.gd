extends RefCounted
## Uma atmosfera local da câmera impede que o clima/neblina externos desbotem as
## salas enterradas. As câmeras da superfície continuam usando o ambiente vivo do mundo.

static func apply_to(camera: Camera3D) -> void:
	camera.set_meta("uses_interior_depth",true)
	var atmosphere := Environment.new()
	atmosphere.background_mode = Environment.BG_COLOR
	atmosphere.background_color = Color("0b1110")
	atmosphere.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	atmosphere.ambient_light_color = Color("9baba1")
	atmosphere.ambient_light_energy = .62
	atmosphere.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	atmosphere.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	atmosphere.fog_enabled = false
	atmosphere.volumetric_fog_enabled = false
	camera.environment = atmosphere
