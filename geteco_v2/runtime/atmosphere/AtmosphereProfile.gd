extends Resource
## Art controls are independent of gameplay weather and the shared world clock.
@export var label := ""
@export var shadow_tint := Color.WHITE
@export var sunlight_tint := Color.WHITE
@export var fog_color := Color("b1c4ce")
@export_range(0.0, 0.5) var haze := 0.08
@export_range(0.0, 1.0) var distant_haze := 0.35
@export_range(0.0, 2.0) var saturation := 1.0
@export_range(0.5, 1.5) var contrast := 1.0
@export var wind := Vector2(9, -2)

func sample(hour: float, cloud: float) -> Dictionary:
	var h := fposmod(hour, 1.0)
	var daylight := smoothstep(0.22, 0.36, h) * (1.0 - smoothstep(0.74, 0.88, h))
	var sunset := smoothstep(0.67, 0.76, h) * (1.0 - smoothstep(0.78, 0.88, h))
	var overcast := clampf(cloud, 0, 1)
	var sun := sunlight_tint.lerp(Color.WHITE, overcast * 0.72)
	sun = Color.WHITE.lerp(sun, daylight)
	sun *= Color.WHITE.lerp(Color(1.12, 1.025, 0.88), sunset * (1.0 - overcast))
	var air := Color("172334").lerp(fog_color, daylight)
	air = air.lerp(Color("c59d85"), sunset * (1.0 - overcast) * 0.40)
	return {"shadow_tint": shadow_tint, "sunlight_tint": sun,
		"fog_color": air, "haze": haze * lerpf(0.65, 1.0, daylight) + overcast * 0.045,
		"distant_haze": distant_haze + overcast * 0.12,
		"saturation": saturation * lerpf(1.0, 0.90, overcast),
		"contrast": lerpf(contrast, 0.98, overcast), "wind": wind}
