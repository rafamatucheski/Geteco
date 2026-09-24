extends Node
## Root forwards input after modal routing. No autonomous input polling.
const AUDIO := preload("res://gameplay/VehicleEquipmentAudio.gd")
const PROFILES := preload("res://gameplay/VehicleLightProfiles.gd")
## Fachos reais (SpotLight) de NPC ao mesmo tempo, só nos carros mais próximos
## do jogador: iluminam pedestres e lataria em volta. O que se vê de cima é a
## mancha no chão (`ground_pool`), que custa quase nada. Medido em 22/09/2026
## (RTX 4060, mobile, VSync off, não isolado): 5 fachos somaram 0,8–2,3 ms ao p95;
## as manchas ficaram dentro do ruído. O limite do renderizador "mobile" também
## é de 8 SpotLights por malha, e o asfalto é malha grande.
static var npc_beam_budget := 2
## Chave global do acendimento noturno automático (medição A/B e futura opção).
static var night_auto_enabled := true
const NPC_BEAM_RADIUS := 45.0
static var _npc_beams: Dictionary = {}
static var _npc_frame := -1
static var _npc_allowed: Dictionary = {}
static var _pool_texture: ImageTexture
static var _pool_materials: Dictionary = {}
signal changed
var car: CharacterBody3D
var world: Node
var headlights_on := false
var siren_on := false
var input_enabled := true
var lamps: Array[SpotLight3D] = []
var lens_materials: Array[StandardMaterial3D] = []
var tail_materials: Array[StandardMaterial3D] = []
## Facho único de NPC, centrado entre os faróis (metade das luzes por carro).
var npc_beam: SpotLight3D
var profile: Dictionary = {}
## Mancha de luz no chão à frente do carro, como a dos postes (CityLookMaterials
## `light_pool`) e o cone da V1 (`HeadlightTextureGenerator`). Com a câmera alta,
## uma SpotLight comum quase não aparece no asfalto; é esta mancha que mostra o
## farol — e o formato, a cor e o brilho dela seguem o perfil do modelo.
var ground_pool: MeshInstance3D
## Acendimento automático de quem dirige sozinho (trânsito, ônibus, viaturas).
var auto_lit := false
var beacons: Array[Dictionary] = []
## V1 `SirenHalo`: luz alternando azul/vermelho em volta do giroflex aceso.
var halo: OmniLight3D
var horn_audio: AudioStreamPlayer3D
var siren_audio: AudioStreamPlayer3D
var alarm_audio: AudioStreamPlayer3D
## Segundos restantes do alarme antifurto (V1 `TrafficVehicle.start_theft_alarm`).
var alarm_remaining := 0.0
var _phase := -2

func configure(vehicle: CharacterBody3D, scene: Node) -> void:
	car = vehicle
	world = scene

func _ready() -> void:
	if not is_instance_valid(car): return
	var mounts: Array[Vector3] = []
	var bar_mounts: Array[Vector3] = []
	var materials := {}
	for part in car.visual.find_children("*", "MeshInstance3D", true, false):
		var key := ""
		for metadata in part.get_meta_list():
			if str(metadata).ends_with("material_key"): key = str(part.get_meta(metadata))
		var original := part.material_override as StandardMaterial3D
		if original == null: continue
		if key == "": key = original.resource_name
		# Older procedural exports retain their exact lens material, but no key tag.
		if key == "" and is_equal_approx(original.roughness, .1):
			if original.albedo_color.is_equal_approx(Color("f5f6fa")) and original.emission_enabled: key = "headlight"
			# A SUV da PM usa as mesmas lentes do cruiser; sem ela aqui a viatura
			# roubada do pátio não tinha giroflex nem sirene.
			var police: bool = car.archetype in ["police_cruiser", "police_suv"]
			if (police or car.archetype == "rescue_pumper") and original.emission_enabled:
				var left := Color("e83c42") if police else Color("e74c3c")
				var right := Color("3689ef") if police else Color("f39c12")
				if original.albedo_color.is_equal_approx(left): key = "bar_left"
				if original.albedo_color.is_equal_approx(right): key = "bar_right"
		if key in ["bar_left", "bar_right"] and car.archetype not in ["police_cruiser", "police_suv", "medic_box", "rescue_pumper"]: continue
		var local := car.to_local(part.global_position)
		if key not in ["bar_left", "bar_right"]: key = _lens_role(key, original, local)
		if key == "": continue
		# O cupê original já anima a própria lanterna de freio (Vehicle.tail_material).
		if key == "tail" and car.tail_material != null: continue
		# Uma cópia por lente original: modelos com cores de lente diferentes mantêm a sua.
		var material_id := key + ":" + str(original.get_instance_id())
		if not materials.has(material_id):
			materials[material_id] = original.duplicate()
			if key == "headlight": lens_materials.append(materials[material_id])
			elif key == "tail": tail_materials.append(materials[material_id])
			else: beacons.append({"material": materials[material_id], "color": original.albedo_color, "side": 0 if key == "bar_left" else 1})
		part.material_override = materials[material_id]
		if key == "headlight": mounts.append(local)
		elif key != "tail": bar_mounts.append(local)
	# Some original procedural meshes have no material tags: derive mount from hull.
	if mounts.is_empty():
		mounts.assign([Vector3(-car.half_width * .7, .8, -car.half_length), Vector3(car.half_width * .7, .8, -car.half_length)])
	profile = PROFILES.for_archetype(car.archetype)
	# One projector per side even when the original lens consists of several meshes.
	# Moto: um projetor só, no centro.
	for side in ([0] if profile.single else [-1, 1]):
		var center := Vector3.ZERO
		var count := 0
		for mount in mounts:
			if side == 0 or (mount.x < 0) == (side < 0):
				center += mount
				count += 1
		if count == 0: continue
		lamps.append(_projector(center / count, float(profile.energy), float(profile.angle)))
	var front := Vector3.ZERO
	for mount in mounts: front += mount
	# Facho central do NPC: uma luz com a soma aproximada das duas.
	npc_beam = _projector(front / mounts.size(), float(profile.energy) * (1.0 if profile.single else 1.6), float(profile.angle) + (0.0 if profile.single else 8.0))
	for material in lens_materials: material.emission = profile.color
	ground_pool = _ground_pool(front / mounts.size())
	if not bar_mounts.is_empty():
		var center := Vector3.ZERO
		for mount in bar_mounts: center += mount
		halo = OmniLight3D.new()
		halo.position = center / bar_mounts.size() + Vector3.UP * .35
		halo.omni_range = 7.0
		halo.light_energy = 2.2
		halo.shadow_enabled = false
		halo.hide()
		car.add_child(halo)
	horn_audio = _audio(43.75, -7)
	siren_audio = _audio(56.25, -10)
	siren_audio.unit_size = 5
	# V1 ouvia o alarme a 1000 px (62,5 m) e 2 dB acima da sirene.
	alarm_audio = _audio(62.5, 2)
	alarm_audio.unit_size = 5
	_refresh()

func _projector(mount: Vector3, energy: float, angle: float) -> SpotLight3D:
	var light := SpotLight3D.new()
	light.position = mount + Vector3(0, 0, -.06)
	light.rotation.x = deg_to_rad(-4)
	light.light_color = profile.color
	light.light_energy = energy
	light.spot_range = float(profile.range)
	light.spot_angle = angle
	light.shadow_enabled = false
	light.hide()
	car.add_child(light)
	return light

func _ground_pool(front: Vector3) -> MeshInstance3D:
	var length := float(profile.range) * .42
	var width := minf(2.0 * tan(deg_to_rad(float(profile.angle))) * length * .55, length * 1.1)
	if profile.single: width *= .7
	var plane := PlaneMesh.new()
	plane.size = Vector2(width, length)
	var instance := MeshInstance3D.new()
	instance.mesh = plane
	instance.material_override = _pool_material(str(profile.family), profile.color, float(profile.energy))
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Rente ao chão, logo à frente do para-choque; o teste de profundidade deixa
	# a calçada e os carros da frente taparem a mancha como tapam a dos postes.
	instance.position = Vector3(front.x * .2, .07, front.z - length * .5 + .2)
	instance.hide()
	car.add_child(instance)
	return instance

static func _pool_material(family: String, color: Color, energy: float) -> StandardMaterial3D:
	if _pool_materials.has(family): return _pool_materials[family]
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	material.albedo_texture = _cone_texture()
	material.albedo_color = Color(color.r, color.g, color.b) * clampf(energy * .42, .3, .9)
	_pool_materials[family] = material
	return material

## Cone com o vértice no para-choque (v = 1) abrindo para longe (v = 0):
## mais forte perto do carro e esmaecendo nas bordas e no fim do alcance.
static func _cone_texture() -> ImageTexture:
	if _pool_texture != null: return _pool_texture
	var image := Image.create(64, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		var along := 1.0 - float(y) / 127.0
		var spread := lerpf(.18, 1.0, sqrt(along))
		var reach := (1.0 - smoothstep(.55, 1.0, along)) * smoothstep(0.0, .08, along)
		for x in 64:
			var across := absf(float(x) / 63.0 * 2.0 - 1.0) / spread
			var value := reach * (1.0 - smoothstep(.55, 1.0, across)) * lerpf(1.0, .55, along)
			image.set_pixel(x, y, Color(value, value, value, 1.0))
	_pool_texture = ImageTexture.create_from_image(image)
	return _pool_texture

## Papel de uma lente do modelo original. Exportações mais novas marcam a
## chave; as antigas não, e aí vale cor emissiva + posição: branco-creme na
## frente é farol, vermelho atrás é lanterna. A posição exclui o luminoso do
## táxi e o giroflex, que ficam no teto, perto do centro.
func _lens_role(key: String, material: StandardMaterial3D, local: Vector3) -> String:
	if "headlight" in key: return "headlight"
	if "tail" in key: return "tail"
	if key != "" or not material.emission_enabled: return ""
	var color := material.albedo_color
	if local.z < -car.half_length * .35 and color.s < .35 and color.v > .8: return "headlight"
	if local.z > car.half_length * .35 and (color.h < .04 or color.h > .95) and color.s > .55 and color.r > .6: return "tail"
	return ""

## V1 `DayNightWeatherManager`: escuro com hora > 0,79 ou < 0,30, ou na tempestade.
func is_dark() -> bool:
	var production = world.get("production") if is_instance_valid(world) else null
	if production == null or production.get("state") == null: return false
	var world_state: Dictionary = production.state.world_state
	var hour := float(world_state.get("time", .32))
	return hour > .79 or hour < .30 or int(world_state.get("weather", 0)) == 2

func npc_driven() -> bool:
	return is_instance_valid(car) and (car.traffic or (car.controlled and car.external_input))

func _npc_beam_allowed() -> bool:
	var frame := Engine.get_process_frames()
	if frame != _npc_frame:
		_npc_frame = frame
		_npc_allowed.clear()
		var player = world.get("player") if is_instance_valid(world) else null
		var ranked: Array = []
		for id in _npc_beams.keys():
			var other = instance_from_id(id)
			if not is_instance_valid(other) or not other.auto_lit or not is_instance_valid(other.car):
				_npc_beams.erase(id)
				continue
			var distance: float = other.car.global_position.distance_to(player.global_position) if is_instance_valid(player) else 0.0
			if distance <= NPC_BEAM_RADIUS: ranked.append([distance, id])
		ranked.sort_custom(func(a, b): return a[0] < b[0])
		for index in mini(npc_beam_budget, ranked.size()): _npc_allowed[ranked[index][1]] = true
	return _npc_allowed.has(get_instance_id())

func _audio(distance: float, volume: float) -> AudioStreamPlayer3D:
	var emitter := AudioStreamPlayer3D.new()
	emitter.max_distance = distance
	emitter.volume_db = volume
	if AudioServer.get_bus_index("SFX") >= 0: emitter.bus = "SFX"
	car.add_child(emitter)
	return emitter

func can_operate() -> bool:
	return is_instance_valid(car) and car.controlled and car.health > 0 and input_enabled and is_inside_tree() and not get_tree().paused

func set_input_enabled(value: bool) -> void:
	input_enabled = value
	if not value and is_instance_valid(horn_audio): horn_audio.stop()

func handle_input(event: InputEvent, allowed: bool = true) -> bool:
	if not allowed or not can_operate(): return false
	if event.is_action_pressed("headlights", false): return toggle_headlights()
	# Shared R3 binds siren on emergency vehicles and horn on ordinary vehicles.
	if not beacons.is_empty() and event.is_action_pressed("siren_toggle", false): return toggle_siren()
	if event.is_action_pressed("horn", false): return honk()
	return false

func toggle_headlights() -> bool:
	if not can_operate(): return false
	headlights_on = not headlights_on
	_refresh()
	changed.emit()
	return true

func toggle_siren() -> bool:
	if not can_operate() or beacons.is_empty(): return false
	siren_on = not siren_on
	_refresh()
	changed.emit()
	return true

func honk() -> bool:
	if not can_operate() or horn_audio.playing: return false
	horn_audio.stream = AUDIO.horn_stream()
	horn_audio.play()
	return true

## Repetir o disparo não prolonga um alarme que já está tocando (V1).
func start_alarm(seconds: float = -1.0) -> bool:
	if not is_instance_valid(car) or car.health <= 0 or alarm_remaining > 0: return false
	alarm_remaining = seconds if seconds > 0 else randf_range(10.0, 15.0)
	_refresh()
	changed.emit()
	return true

func stop_alarm() -> void:
	if alarm_remaining <= 0: return
	alarm_remaining = 0
	_refresh()
	changed.emit()

func _process(delta: float) -> void:
	if alarm_remaining > 0:
		alarm_remaining = maxf(0, alarm_remaining - delta)
		if alarm_remaining <= 0: changed.emit()
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(car): return
	var occupied: bool = car.controlled and car.health > 0
	# V1 piscava os faróis junto com o alarme, a cada ~1/6 s.
	var alarm_blink: bool = alarm_remaining > 0 and car.health > 0 and int(Time.get_ticks_msec() / 167) % 2 == 0
	var was_auto := auto_lit
	auto_lit = night_auto_enabled and car.health > 0 and npc_driven() and is_dark()
	if auto_lit: _npc_beams[get_instance_id()] = true
	# Quem toma um carro aceso à noite continua com o farol ligado.
	if was_auto and not auto_lit and occupied and not car.external_input: headlights_on = true
	var driver_lit: bool = (headlights_on and occupied and not npc_driven()) or alarm_blink
	var lit: bool = driver_lit or auto_lit
	for lamp in lamps: lamp.visible = driver_lit
	if is_instance_valid(npc_beam): npc_beam.visible = auto_lit and not driver_lit and _npc_beam_allowed()
	if is_instance_valid(ground_pool): ground_pool.visible = lit and car.health > 0
	for material in lens_materials:
		material.emission_enabled = lit
		material.emission_energy_multiplier = 1.35 if lit else 0
	# Lanterna traseira: acesa fraca à noite, forte na frenagem, apagada de dia.
	# Carro estacionado sem motorista não "freia", mesmo com brake_input preso.
	var braking: bool = car.health > 0 and (car.controlled or car.traffic) and (car.brake_input or car.blocked or (car.throttle_input < -.05 and car.speed > .5))
	for material in tail_materials:
		material.emission_enabled = lit or braking
		material.emission_energy_multiplier = 2.5 if braking else (.9 if lit else 0.0)
	var sounding := siren_on and occupied and not beacons.is_empty()
	if is_instance_valid(siren_audio):
		if sounding and not siren_audio.playing:
			siren_audio.stream = AUDIO.siren_stream()
			siren_audio.play()
		elif not sounding: siren_audio.stop()
	if not occupied and is_instance_valid(horn_audio): horn_audio.stop()
	# O alarme vale com o carro vazio: é justamente o estado de quem falhou o lockpick.
	var alarming: bool = alarm_remaining > 0 and car.health > 0
	if is_instance_valid(alarm_audio):
		if alarming and not alarm_audio.playing:
			alarm_audio.stream = AUDIO.alarm_stream()
			alarm_audio.play()
		elif not alarming: alarm_audio.stop()
	var flashing: bool = (sounding or alarming) and not beacons.is_empty()
	var phase := int(Time.get_ticks_msec() / 160) % 2 if flashing else -1
	if phase == _phase: return
	_phase = phase
	if is_instance_valid(halo):
		halo.visible = phase >= 0
		for beacon in beacons:
			if beacon.side == phase: halo.light_color = beacon.color
	for beacon in beacons:
		var active: bool = beacon.side == phase
		beacon.material.albedo_color = beacon.color.lerp(Color.WHITE, .55) if active else beacon.color
		beacon.material.emission = beacon.color
		beacon.material.emission_enabled = active
		beacon.material.emission_energy_multiplier = 2.8 if active else 0

func snapshot() -> Dictionary: return {"headlights": headlights_on, "siren": siren_on}

func restore_state(data: Dictionary) -> bool:
	if not data.get("headlights") is bool or not data.get("siren") is bool: return false
	if data.siren and beacons.is_empty(): return false
	headlights_on = data.headlights
	siren_on = data.siren
	_refresh()
	return true

func _exit_tree() -> void:
	for emitter in [horn_audio, siren_audio, alarm_audio]:
		if is_instance_valid(emitter):
			emitter.stop()
			emitter.stream = null
			emitter.queue_free()
	for lamp in lamps:
		if is_instance_valid(lamp): lamp.queue_free()
	if is_instance_valid(halo): halo.queue_free()
	if is_instance_valid(npc_beam): npc_beam.queue_free()
	if is_instance_valid(ground_pool): ground_pool.queue_free()
	_npc_beams.erase(get_instance_id())
