extends Node
## Carros molhados pela chuva: a pintura fica mais escura e brilhante e ganha gotas
## (normal triplanar). Cada carro tem a própria umidade: molha com a chuva, seca devagar
## e não molha sob teto (túnel, garagem, marquise). Só toca nos materiais de pintura que
## VehiclePaint já copiou por carro; o vidro e os materiais compartilhados ficam intactos.
##
## Custo: um passo a 4 Hz sobre o grupo "drivable"; só carros perto do foco recebem
## material novo e só quando a umidade muda de degrau. Seco, nada é tocado.
## As flags do StandardMaterial3D que surgem aqui (normal_enabled + uv1_triplanar) geram
## variantes de shader: VehicleMaterialVariantPrewarm as compila sob a cortina.
const ATMOSPHERE := preload("res://runtime/atmosphere/RegionalAtmosphere3D.gd")
const STEP := .25
const NEAR := 160.0             # além disso o carro não aparece: só a umidade é atualizada
const RAY_NEAR := 90.0          # teto só é medido perto do foco
const WET_RISE_SECONDS := 14.0  # chuva forte molha a lataria inteira nesse tempo
const DRY_SECONDS := 120.0      # parado ao sol, leva ~2 min para secar
const LEVELS := 20.0            # degraus de umidade que viram material novo
const BEAD_SCALE := 1.5
static var _beads: Texture2D
var weather: Node
var _clock := 0.0
var _query := PhysicsRayQueryParameters3D.new()

## Controle A/B de medição: HARBOR_VEHICLE_RAIN=0 desliga o efeito.
static func enabled() -> bool:
	return OS.get_environment("HARBOR_VEHICLE_RAIN") != "0" and "--no-vehicle-rain" not in OS.get_cmdline_user_args()

func _physics_process(delta: float) -> void:
	# Relógio primeiro: enabled() lê o ambiente e copia os argumentos da linha de comando,
	# e isso não precisa acontecer a cada passo de física, só a 4 Hz.
	_clock += delta
	if _clock < STEP: return
	var dt := _clock
	_clock = 0.0
	if not enabled() or weather == null or DisplayServer.get_name() == "headless": return
	var controller = weather.get("controller")
	if controller == null: return
	var focus: Vector3 = ATMOSPHERE.focus_position(controller)
	for vehicle in get_tree().get_nodes_in_group("drivable"):
		if vehicle is Node3D and is_instance_valid(vehicle) and vehicle.is_inside_tree(): _step(vehicle, focus, dt)

func _step(vehicle: Node3D, focus: Vector3, dt: float) -> void:
	var wet := float(vehicle.get_meta("rain_wet", 0.0))
	var point := vehicle.global_position
	var near := point.distance_squared_to(focus) < NEAR * NEAR
	var rain: float = weather.rain_strength_at(point)
	var exposed: bool = rain > .05 and not weather.atmosphere.SHELTER.sheltered(point)
	if exposed and point.distance_squared_to(focus) < RAY_NEAR * RAY_NEAR: exposed = not _covered(vehicle, point)
	if exposed: wet = minf(1.0, wet + dt / WET_RISE_SECONDS * (.35 + .65 * rain))
	elif wet > 0.0: wet = maxf(0.0, wet - dt / DRY_SECONDS)
	vehicle.set_meta("rain_wet", wet)
	if not near: return
	var level := roundf(wet * LEVELS)
	var applied: float = float(vehicle.get_meta("rain_level", 0.0))
	if level == applied and not (level > 0.0 and _lost_beads(vehicle)): return
	vehicle.set_meta("rain_level", level)
	apply(vehicle, level / LEVELS)

## Um raio para cima: só construção/estrutura estática conta como teto (carro, pessoa
## e chão não). Fica de fora com a chuva parada, então seco o custo é zero.
func _covered(vehicle: Node3D, point: Vector3) -> bool:
	var space := vehicle.get_world_3d().direct_space_state
	_query.from = point + Vector3.UP * 1.4
	_query.to = point + Vector3.UP * 14.0
	_query.collision_mask = 7
	_query.exclude = [vehicle.get_rid()] if vehicle is CollisionObject3D else []
	var hit := space.intersect_ray(_query)
	return not hit.is_empty() and hit.collider is StaticBody3D and not (hit.collider as Node).is_in_group("drivable")

static func apply(vehicle: Node3D, wet: float) -> void:
	var paint = vehicle.get("_paint")
	if paint == null: return
	var visual = vehicle.get("visual")
	var dirt := 0
	if is_instance_valid(visual): dirt = (visual.get_meta("usage_profile", Vector2i.ZERO) as Vector2i).x
	# Sujeira cobre o verniz: carro empoeirado molha mais fosco e com menos gota.
	var gloss := wet * (1.0 - .3 * dirt)
	for material: StandardMaterial3D in paint.materials:
		_apply_material(material, wet, gloss, 1.0 - .25 * dirt)

static func apply_material_for_test(material: StandardMaterial3D, wet: float, gloss: float, bead: float) -> void:
	_apply_material(material, wet, gloss, bead)

static func _apply_material(material: StandardMaterial3D, wet: float, gloss: float, bead: float) -> void:
	var record: Dictionary = material.get_meta("rain_base", {})
	# Outro sistema repintou/gastou o material: o que está nele agora é a nova base.
	if not record.is_empty() and not _matches(material, record): record = {}
	if record.is_empty():
		if wet <= 0.0: return
		record = {"base": [material.roughness, material.clearcoat, material.albedo_color], "beaded": false}
	var base: Array = record.base
	if wet <= 0.0:
		_restore(material, base, record)
		material.remove_meta("rain_base")
		return
	material.roughness = maxf(.05, float(base[0]) * (1.0 - .6 * gloss))
	if material.clearcoat_enabled: material.clearcoat = lerpf(float(base[1]), 1.0, gloss * .75)
	var albedo: Color = base[2]
	material.albedo_color = Color(albedo.r * (1.0 - .24 * wet), albedo.g * (1.0 - .24 * wet), albedo.b * (1.0 - .24 * wet), albedo.a)
	var beads_ok := material.albedo_texture == null and (material.normal_texture == null or material.normal_texture == beads())
	if beads_ok and wet > .04:
		if not record.beaded:
			material.normal_enabled = true
			material.normal_texture = beads()
			material.uv1_triplanar = true
			material.uv1_scale = Vector3.ONE * BEAD_SCALE
			record.beaded = true
		material.normal_scale = clampf(wet * bead, 0.0, 1.0) * .9
	elif record.beaded:
		_strip_beads(material)
		record.beaded = false
	record["out"] = [material.roughness, material.clearcoat, material.albedo_color]
	material.set_meta("rain_base", record)

static func _matches(material: StandardMaterial3D, record: Dictionary) -> bool:
	if not record.has("out"): return true
	var out: Array = record.out
	return is_equal_approx(material.roughness, float(out[0])) and is_equal_approx(material.clearcoat, float(out[1])) \
		and material.albedo_color.is_equal_approx(out[2])

static func _restore(material: StandardMaterial3D, base: Array, record: Dictionary) -> void:
	material.roughness = float(base[0])
	material.clearcoat = float(base[1])
	material.albedo_color = base[2]
	if record.get("beaded", false): _strip_beads(material)

static func _strip_beads(material: StandardMaterial3D) -> void:
	# Se o amassado assumiu a normal no meio da chuva, ele fica como está.
	if material.normal_texture != beads(): return
	material.normal_enabled = false
	material.normal_texture = null
	material.normal_scale = 1.0
	material.uv1_triplanar = false
	material.uv1_scale = Vector3.ONE

## A carcaça trocou a normal (amassado/estágio de dano) e levou as gotas junto.
static func _lost_beads(vehicle: Node3D) -> bool:
	var paint = vehicle.get("_paint")
	if paint == null or paint.materials.is_empty(): return false
	var material: StandardMaterial3D = paint.materials[0]
	return material.albedo_texture == null and material.normal_texture == null

## Gotas redondas e pequenas, tileáveis: altura = calota esférica; normal por diferença finita.
static func beads() -> Texture2D:
	if _beads != null: return _beads
	const SIZE := 128
	var height := PackedFloat32Array()
	height.resize(SIZE * SIZE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4417
	for drop in 70:
		var cx := rng.randf() * SIZE
		var cy := rng.randf() * SIZE
		var radius := rng.randf_range(2.0, 6.5)
		var stretch := rng.randf_range(1.0, 1.5) # gota que escorre fica um pouco mais longa em y
		var reach := int(ceil(radius * stretch)) + 1
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var u := float(dx) / radius
				var v := float(dy) / (radius * stretch)
				var r2 := u * u + v * v
				if r2 >= 1.0: continue
				var index := posmod(int(cy) + dy, SIZE) * SIZE + posmod(int(cx) + dx, SIZE)
				height[index] = maxf(height[index], sqrt(1.0 - r2) * radius * .5)
	var image := Image.create(SIZE, SIZE, true, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			var dx := height[y * SIZE + posmod(x + 1, SIZE)] - height[y * SIZE + posmod(x - 1, SIZE)]
			var dy := height[posmod(y + 1, SIZE) * SIZE + x] - height[posmod(y - 1, SIZE) * SIZE + x]
			var normal := Vector3(-dx, -dy, 1.0).normalized()
			image.set_pixel(x, y, Color(normal.x * .5 + .5, normal.y * .5 + .5, normal.z * .5 + .5))
	image.generate_mipmaps()
	_beads = ImageTexture.create_from_image(image)
	return _beads
