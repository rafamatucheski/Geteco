extends Node2D
## A short pressure flash, rolling fire, lifted smoke and ballistic fragments.
## All dimensions are world pixels; a single bounded node owns the entire burst.
const MAX_BURSTS := 16
var age := 0.0
var radius := 100.0
var vehicle_blast := false
var rocket_direction := Vector2.ZERO
var lobes: Array[Vector3] = []
var fragments: Array[Vector3] = []
static var soft: GradientTexture2D

static func spawn(parent: Node, origin: Vector2, blast_radius: float, vehicle: bool = false, impact_direction: Vector2 = Vector2.ZERO) -> Node2D:
	if not is_instance_valid(parent) or not parent.is_inside_tree(): return null
	if parent.get_tree().get_nodes_in_group("explosion_visuals").size() >= MAX_BURSTS: return null
	var effect := new()
	effect.radius = clampf(blast_radius * 0.68, 40.0, 135.0)
	effect.vehicle_blast = vehicle
	effect.rocket_direction = impact_direction.normalized()
	parent.add_child(effect)
	effect.global_position = origin
	if parent.get_tree().get_nodes_in_group("explosion_scorches").size() < 24:
		var scorch := Polygon2D.new()
		var points := PackedVector2Array()
		for i in 18:
			points.append(Vector2.from_angle(TAU*float(i)/18.0)*effect.radius*randf_range(0.25,0.38))
		scorch.polygon = points
		scorch.color = Color(0.045,0.04,0.035,0.65)
		scorch.z_as_relative = false
		scorch.z_index = 2
		parent.add_child(scorch)
		scorch.global_position = origin
		scorch.add_to_group("explosion_scorches")
		var fade := scorch.create_tween()
		fade.tween_interval(8.0)
		fade.tween_property(scorch,"modulate:a",0.0,4.0)
		fade.tween_callback(scorch.queue_free)
	return effect

func _ready() -> void:
	add_to_group("explosion_visuals")
	z_as_relative = false
	z_index = 25
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if soft == null:
		soft = GradientTexture2D.new()
		soft.width = 64
		soft.height = 64
		soft.fill = GradientTexture2D.FILL_RADIAL
		soft.fill_from = Vector2(0.5, 0.5)
		soft.fill_to = Vector2(1.0, 0.5)
		soft.gradient = Gradient.new()
		soft.gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		soft.gradient.colors = PackedColorArray([Color.WHITE, Color(1,1,1,0.72), Color(1,1,1,0)])
	for i in 11:
		var angle := TAU * float(i) / 11.0 + randf_range(-0.18, 0.18)
		lobes.append(Vector3(cos(angle), sin(angle), randf_range(0.65, 1.15)))
	for i in (30 if vehicle_blast else 22):
		var angle := randf() * TAU
		fragments.append(Vector3(cos(angle), sin(angle), randf_range(0.35, 1.0)))
	if vehicle_blast or not rocket_direction.is_zero_approx():
		var light := PointLight2D.new()
		light.texture = soft
		light.texture_scale = radius / 22.0
		light.color = Color(1.0, 0.57, 0.20)
		light.energy = 0.85
		add_child(light)
		var fade := light.create_tween()
		fade.tween_property(light, "energy", 0.0, 0.26)
		fade.tween_callback(light.queue_free)

func _process(delta: float) -> void:
	age += delta
	if age >= (3.6 if vehicle_blast else 2.4):
		queue_free()
	elif get_viewport().get_visible_rect().grow(radius * 2.0).has_point(get_global_transform_with_canvas().origin):
		queue_redraw()

func puff(center: Vector2, size: float, color: Color) -> void:
	if size > 0.1 and color.a > 0.001:
		draw_texture_rect(soft, Rect2(center - Vector2.ONE * size, Vector2.ONE * size * 2.0), false, color)

func _draw() -> void:
	var rocket := not rocket_direction.is_zero_approx()
	# Dust rolls close to the road; smoke rises after the hot core has faded.
	var dust_t := clampf(age / 0.75, 0.0, 1.0)
	if dust_t < 1.0:
		for lobe in lobes:
			var radial := Vector2(lobe.x, lobe.y)
			var center := radial * radius * (1.0 - exp(-age * 4.0)) * lobe.z
			puff(center * Vector2(1,0.5), radius * 0.22, Color(0.43,0.37,0.29,(1.0-dust_t)*0.4))
	var smoke_t := clampf((age - 0.14) / (3.46 if vehicle_blast else 2.26), 0.0, 1.0)
	var smoke_alpha := sin(smoke_t * PI) * 0.58
	for lobe in lobes:
		var center := Vector2(lobe.x,lobe.y) * radius * (0.16 + smoke_t * 0.4) * lobe.z
		center += Vector2(smoke_t * 18.0, -smoke_t * radius * 0.8)
		puff(center, radius * (0.19 + smoke_t * 0.32) * lobe.z, Color(0.12,0.13,0.14,smoke_alpha))
	var fire_t := clampf(age / 0.65, 0.0, 1.0)
	var fire_alpha := pow(1.0 - fire_t, 1.1)
	if fire_t < 1.0:
		puff(Vector2(0,-age*20.0), radius * (0.30 + fire_t*0.18), Color(1.0,0.29,0.035,fire_alpha))
		puff(Vector2(0,-age*20.0), radius * 0.22, Color(1.0,0.76,0.24,fire_alpha))
		for lobe in lobes:
			var center := Vector2(lobe.x,lobe.y) * radius * (1.0-exp(-age*8.0)) * 0.45 * lobe.z
			center.y -= age * 23.0
			var size := radius * (0.20 + sin(fire_t * PI) * 0.18) * lobe.z
			puff(center, size, Color(1.0,0.22,0.025,fire_alpha))
			puff(center, size * 0.62, Color(1.0,0.67,0.12,fire_alpha))
			puff(center, size * 0.28, Color(1.0,0.95,0.68,fire_alpha))
	# Fuel ignites in uneven pockets after the first pressure flash.
	if vehicle_blast:
		for i in 5:
			var local_age := age - float(i) * 0.055
			if local_age < 0 or local_age > 0.85: continue
			var t := local_age / 0.85
			var center := Vector2(sin(i * 2.4) * radius * 0.35, -18.0 - t * 52.0)
			var size := radius * (0.10 + sin(t * PI) * 0.19)
			puff(center, size, Color(0.95, 0.20 + t * 0.12, 0.025, (1.0 - t) * 0.75))
			puff(center, size * 0.5, Color(1, 0.75, 0.25, (1.0 - t) * 0.70))
	var flash := maxf(0.0, 1.0 - age / 0.12)
	puff(Vector2.ZERO, radius * 0.72, Color(1.0,0.91,0.7,flash * 0.7))
	if rocket and age<.22:
		var impact_fade := 1.0-age/.22
		var sideways := rocket_direction.orthogonal()
		for i in 7:
			var angle := (float(i)-3.0)*.32
			var spray := (-rocket_direction).rotated(angle)
			var tip := spray*radius*(.18+age*3.4)
			draw_line(tip-spray*8.0*impact_fade,tip,Color(1,.77,.35,impact_fade),1.4,true)
		puff(sideways*radius*.15, radius*.32,Color(1,.51,.11,impact_fade*.6))
		puff(-sideways*radius*.15, radius*.25,Color(1,.75,.3,impact_fade*.6))
	if age < 0.38 and not rocket:
		draw_arc(Vector2.ZERO, maxf(1.0,radius * age / 0.3), 0, TAU, 48, Color(0.9,0.76,0.52,(1.0-age/0.38)*0.35), 1.5, true)
	if age >= 2.0: return
	for i in fragments.size():
		var fragment := fragments[i]
		var travel := minf(age, 0.85)
		var direction := Vector2(fragment.x, fragment.y)
		var ground := direction * radius * fragment.z * (1.0-exp(-travel*3.0)) * 1.45
		var height := maxf(0.0, (100.0 + fragment.z * 90.0) * travel - 250.0 * travel * travel)
		var pos := ground + Vector2(0,-height)
		var fade := clampf((2.0-age)*1.4,0.0,1.0)
		var axis := Vector2.from_angle(float(i)*1.7+travel*9.0) * (1.4+fragment.z*1.8)
		draw_line(ground-axis*0.7,ground+axis*0.7,Color(0,0,0,fade*0.2),1.5,true)
		var hot := maxf(0.0,1.0-age/0.6)
		var color := Color(0.22,0.24,0.25).lerp(Color(1,0.72,0.18),hot)
		color.a = fade
		draw_line(pos-axis,pos+axis,color,2.0 if vehicle_blast else 1.2,true)
		if vehicle_blast and i < 5:
			var cross := axis.orthogonal() * 1.3
			var panel := PackedVector2Array([pos-axis*2-cross, pos+axis*2-cross*0.6, pos+axis*1.6+cross, pos-axis*1.8+cross*0.8])
			draw_colored_polygon(panel, color.darkened(0.25))
		if hot > 0:
			draw_line(pos-direction*9.0*hot,pos,Color(1,0.45,0.06,hot*0.65),1.0,true)
