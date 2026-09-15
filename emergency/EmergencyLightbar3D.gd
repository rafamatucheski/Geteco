extends RefCounted
## Animate the actual lens materials, including both bars on a fire engine.
var lamps: Array[StandardMaterial3D] = []
var rest_colors: Array[Color] = []
var phase := -2

func bind(model: Node3D) -> void:
	lamps.clear()
	rest_colors.clear()
	for key in ["bar_left", "bar_right"]:
		var material := model.materials.get(key) as StandardMaterial3D
		if material == null: continue
		var color: Color = material.get_meta("beacon_rest_color", material.albedo_color)
		material.set_meta("beacon_rest_color", color)
		lamps.append(material)
		rest_colors.append(color)
	phase = -2
	update(false, 0)

func update(active: bool, clock_msec: int) -> bool:
	var next_phase := int(clock_msec / 160) % 2 if active and not lamps.is_empty() else -1
	if next_phase == phase: return false
	phase = next_phase
	for index in lamps.size():
		var on := index == phase
		lamps[index].albedo_color = rest_colors[index].lerp(Color.WHITE, 0.55) if on else rest_colors[index]
		lamps[index].emission = rest_colors[index]
		lamps[index].emission_enabled = on
		lamps[index].emission_energy_multiplier = 2.8 if on else 0.0
	return true
