extends RefCounted
## Desert moonlight reuses Weather's one directional source and shadow map.
## The caller supplies the existing lunar phase after cloud attenuation, so
## save restoration, the eight-day cycle and storms keep one source of truth.

static func apply(sun: DirectionalLight3D, env: Environment, daylight: float, clouds: float, moon: float, desert: float) -> void:
	var night := clampf(desert,0.0,1.0)*(1.0-smoothstep(0.0,0.32,daylight))
	if night<=0.0: return
	var lunar := clampf(moon,0.0,1.0)
	var overcast := clampf(clouds,0.0,1.0)
	var clear := 1.0-overcast*.70
	# Pale silver highlights retain the warm mineral colours of sand and rock.
	# Directional contrast makes the relief legible without washing out night.
	sun.light_color=sun.light_color.lerp(Color("c9d8ec").lerp(Color("b7c2d0"),overcast),night)
	sun.light_energy*=1.0+night*lunar*clear*.42
	env.ambient_light_energy*=1.0-night*lunar*clear*.08
	env.ambient_light_color=env.ambient_light_color.lerp(Color("8f9eb8"),night*.55)
	# Keep the existing elevated moon and shadow-map settings: changing its
	# direction by player position would make shadows slide on the region seam.
	# Distant silhouettes stay cool and darker than moonlit nearby terrain.
	# Overcast retains Weather's authored sky; StormPresentation applies later.
	var air_weight := night*(1.0-overcast)
	env.background_color=env.background_color.lerp(Color("151c2a").lerp(Color("28364e"),lunar),air_weight)
	env.fog_light_color=env.fog_light_color.lerp(Color("161e2b").lerp(Color("293447"),lunar),air_weight)
	env.adjustment_contrast=lerpf(env.adjustment_contrast,1.045,night)
