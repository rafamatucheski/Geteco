extends Node
## Root forwards input after modal routing. No autonomous input polling.
const AUDIO := preload("res://gameplay/VehicleEquipmentAudio.gd")
const PROFILES := preload("res://gameplay/VehicleLightProfiles.gd")
const SURFACES := preload("res://runtime/VehicleSurfaceRoles.gd")
const ENGINE_PROFILE := preload("res://audio/VehicleEngineProfile.gd")
const LIGHT_BUDGET := preload("res://gameplay/lights/LightBudget.gd")
## Nearby traffic uses real projectors under the shared light budget.
static var npc_beam_budget := 2
## Chave global do acendimento noturno automático (medição A/B e futura opção).
static var night_auto_enabled := true
const NPC_BEAM_RADIUS := 45.0
static var _npc_beams: Dictionary = {}
static var _npc_frame := -1
static var _npc_allowed: Dictionary = {}
static var _glow_texture: ImageTexture
signal changed
var car: CharacterBody3D
var world: Node
var headlights_on := false
var siren_on := false
var broken_left := false
var broken_right := false
var input_enabled := true
var lamps: Array[Dictionary] = []
var glows: Array[Dictionary] = []
var beacon_glows: Array[Dictionary] = []
var lens_materials: Array[Dictionary] = []
var tail_materials: Array[StandardMaterial3D] = []
var _tail_colors: Array[Color] = []
var _previous_speed := 0.0
var _decelerating := false
var _brake_hold := 0.0
var _tail_state := -1
var _lens_state := -1
## Facho único de NPC, centrado entre os faróis (metade das luzes por carro).
var npc_beam: SpotLight3D
var profile: Dictionary = {}
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
## Lanternas de teto da cabine (gabarito âmbar) dos caminhões. Só emissivas: acendem
## junto com o farol e não custam luz dinâmica.
var cab_markers: Array[MeshInstance3D] = []
var _markers_lit := -1
static var _marker_tops: Dictionary = {}
static var _marker_mesh: BoxMesh
static var _marker_on: StandardMaterial3D
static var _marker_off: StandardMaterial3D

func configure(vehicle: CharacterBody3D, scene: Node) -> void:
	car = vehicle
	world = scene

func _ready() -> void:
	if not is_instance_valid(car): return
	if car.archetype == "rescue_pumper": _rig_pumper()
	var mounts: Array[Vector3] = []
	var bar_mounts: Array[Vector3] = []
	var materials := {}
	for part in car.visual.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null or part.has_meta("wheel_center"): continue
		for surface in (1 if part.material_override != null else part.mesh.get_surface_count()):
			_bind_lens(part, surface, materials, mounts, bar_mounts)
	# Authored positions take precedence over centers of merged lens meshes.
	if car.visual.has_meta("headlight_mounts"):
		mounts.clear()
		for mount: Vector3 in car.visual.get_meta("headlight_mounts"):
			mounts.append(car.to_local(car.visual.to_global(mount)))
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
		lamps.append({"lamp": _projector(center / count, float(profile.energy), float(profile.angle)), "side": side})
		if LIGHT_BUDGET.enabled:
			var projector: SpotLight3D = lamps.back().lamp
			glows.append({"sprite": _glow(projector.get_parent(), projector.position, profile.color, .42), "side": side})
	var front := Vector3.ZERO
	for mount in mounts: front += mount
	npc_beam = _projector(front / mounts.size(), float(profile.energy) * (1.0 if profile.single else 1.6), float(profile.angle) + (0.0 if profile.single else 8.0))
	npc_beam.shadow_enabled = true
	for item in lens_materials: item.material.emission = profile.color
	_build_cab_markers()
	if not bar_mounts.is_empty():
		var center := Vector3.ZERO
		for mount in bar_mounts: center += mount
		halo = OmniLight3D.new()
		halo.position = center / bar_mounts.size() + Vector3.UP * .35
		halo.omni_range = 7.0
		halo.light_energy = 2.2
		if LIGHT_BUDGET.enabled: halo.set_meta("budget_energy", 2.2)
		halo.shadow_enabled = false
		halo.hide()
		car.add_child(halo)
		if LIGHT_BUDGET.enabled:
			for side in 2:
				var point := Vector3.ZERO
				var count := 0
				for mount in bar_mounts:
					if (mount.x < 0) == (side == 0):
						point += mount
						count += 1
				if count == 0: continue
				for beacon in beacons:
					if beacon.side == side:
						beacon_glows.append({"sprite": _glow(car, point / count + Vector3.UP * .04, beacon.color, .58), "side": side})
						break
	horn_audio = _audio(43.75, -7)
	siren_audio = _audio(56.25, -10)
	siren_audio.unit_size = 5
	alarm_audio = _audio(62.5, 2)
	alarm_audio.unit_size = 5
	if LIGHT_BUDGET.enabled: LIGHT_BUDGET.register(self)
	_refresh()

## Cinco lanternas na borda dianteira do teto da cabine, como caminhão de verdade.
## O topo da cabine sai dos vértices da própria malha (a frota tem formatos muito
## diferentes: cara-chata, bicudo, guincho) e fica em cache por modelo.
func _build_cab_markers() -> void:
	if not car.has_method("boarding_class") or car.boarding_class() != "truck": return
	var top: Dictionary = _marker_tops.get(car.archetype, {})
	if top.is_empty():
		top = _cab_top()
		_marker_tops[car.archetype] = top
	if top.is_empty(): return
	if _marker_mesh == null:
		_marker_mesh = BoxMesh.new()
		_marker_mesh.size = Vector3(.13, .06, .07)
		_marker_off = StandardMaterial3D.new()
		_marker_off.albedo_color = Color(.55, .30, .06)
		_marker_off.roughness = .35
		_marker_on = StandardMaterial3D.new()
		_marker_on.albedo_color = Color(1.0, .62, .18)
		_marker_on.emission_enabled = true
		_marker_on.emission = Color(1.0, .55, .12)
		_marker_on.emission_energy_multiplier = 3.2
	var half: float = top.half
	for index in 5:
		var marker := MeshInstance3D.new()
		marker.name = "CabMarker%d" % index
		marker.mesh = _marker_mesh
		marker.material_override = _marker_off
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.position = Vector3(lerpf(-half, half, index / 4.0), top.y + .03, top.z + .05)
		car.visual.add_child(marker)
		cab_markers.append(marker)

func _cab_top() -> Dictionary:
	# Resultado idêntico ao laço antigo (todos os vértices, todas as peças), mas só
	# desce a vértices nas poucas peças que a caixa delimitadora não descarta. O laço
	# completo custava 70-150 ms na 1ª viatura de bombeiros da sessão (medido em
	# tests/measure/probe_first_emergency.gd --action=vehicle). A caixa da peça
	# transformada é um limite conservador: nenhum vértice sai dela.
	var to_car := car.global_transform.affine_inverse()
	var parts: Array[Dictionary] = []
	for part: MeshInstance3D in car.visual.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null or part.has_meta("wheel_center"): continue
		var into_car := to_car * part.global_transform
		parts.append({"part": part, "xf": into_car, "box": into_car * part.mesh.get_aabb(), "points": null})
	if parts.is_empty(): return {}
	# Frente exata: só peças cuja caixa ainda pode bater o menor z já visto.
	parts.sort_custom(func(a, b): return a.box.position.z < b.box.position.z)
	var front := INF
	for entry in parts:
		if entry.box.position.z >= front: break
		for point in _car_points(entry): front = minf(front, point.z)
	if not is_finite(front): return {}
	# Cabine: faixa de 2,2 m a partir do para-choque; carroceria alta atrás fica de fora.
	var cab_back := front + 2.2
	var cab: Array[Dictionary] = []
	for entry in parts:
		if entry.box.position.z < cab_back: cab.append(entry)
	# Teto exato: peças por altura decrescente, até nenhuma poder mais alcançar o teto.
	cab.sort_custom(func(a, b): return a.box.end.y > b.box.end.y)
	var roof := -INF
	var scanned: Array[Dictionary] = []
	for entry in cab:
		if entry.box.end.y <= roof - .10: break
		scanned.append(entry)
		for point in _car_points(entry):
			if point.z < cab_back: roof = maxf(roof, point.y)
	var edge := INF
	var width := 0.0
	for entry in scanned:
		for point in _car_points(entry):
			if point.z < cab_back and point.y > roof - .10:
				edge = minf(edge, point.z)
				width = maxf(width, absf(point.x))
	if not is_finite(edge) or width < .3: return {}
	return {"y": roof, "z": edge, "half": minf(width - .12, car.half_width * .8)}

## Vértices da peça no espaço do carro (transformação nativa do array inteiro), em cache.
func _car_points(entry: Dictionary) -> PackedVector3Array:
	if entry.points != null: return entry.points
	var result := PackedVector3Array()
	var mesh: Mesh = (entry.part as MeshInstance3D).mesh
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null: continue
		result.append_array((entry.xf as Transform3D) * (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array))
	entry.points = result
	return result

func _bind_lens(part: MeshInstance3D, surface: int, materials: Dictionary, mounts: Array[Vector3], bar_mounts: Array[Vector3]) -> void:
	var key := SURFACES.key(part, surface)
	var original := part.get_active_material(surface) as StandardMaterial3D
	if original == null: return
	# Older procedural exports retain their exact lens material, but no key tag.
	if key == "" and is_equal_approx(original.roughness, .1):
		if original.albedo_color.is_equal_approx(Color("f5f6fa")) and original.emission_enabled: key = "headlight"
		# A SUV da PM usa as mesmas lentes do cruiser; sem ela aqui a viatura
		# roubada do pátio não tinha giroflex nem sirene.
		var police: bool = car.archetype in ["police_cruiser", "police_suv", "police_transport", "bike_police"]
		if (police or car.archetype == "rescue_pumper") and original.emission_enabled:
			var left := Color("e83c42") if police else Color("e74c3c")
			var right := Color("3689ef") if police else Color("f39c12")
			if original.albedo_color.is_equal_approx(left): key = "bar_left"
			if original.albedo_color.is_equal_approx(right): key = "bar_right"
	if key in ["bar_left", "bar_right"] and car.archetype not in ["police_cruiser", "police_suv", "police_transport", "bike_police", "medic_box", "rescue_pumper"]: return
	if key not in ["bar_left","bar_right"] and not SURFACES.is_headlight_lens(key) and not SURFACES.is_tail_lens(key):
		if key != "" or not original.emission_enabled: return
	# Flattened ArrayMeshes keep vertices away from their node origin.
	var local: Vector3 = car.to_local(part.to_global(SURFACES.center(part, surface)))
	if key not in ["bar_left", "bar_right"]: key = _lens_role(key, original, local)
	if key == "": return
	# Uma cópia por lente original: modelos com cores de lente diferentes mantêm a sua.
	var side_id := -1 if local.x < 0 else (1 if local.x > 0 else 0)
	var material_id := key + ":" + str(original.get_instance_id()) + (":" + str(side_id) if key == "headlight" else "")
	if not materials.has(material_id):
		materials[material_id] = original.duplicate()
		if key == "headlight": lens_materials.append({"material": materials[material_id], "side": side_id})
		elif key == "tail":
			tail_materials.append(materials[material_id])
			_tail_colors.append(original.albedo_color)
			materials[material_id].emission = Color(1.0, .025, .012)
		else: beacons.append({"material": materials[material_id], "color": original.albedo_color, "side": 0 if key == "bar_left" else 1})
	if part.material_override != null: part.material_override = materials[material_id]
	else: part.set_surface_override_material(surface, materials[material_id])
	if key == "tail" and car.tail_material == original: car.tail_material = materials[material_id]
	if key == "headlight": mounts.append(local)
	elif key != "tail": bar_mounts.append(local)

func _projector(mount: Vector3, energy: float, angle: float) -> SpotLight3D:
	var light := SpotLight3D.new()
	# Na moto a carroceria apresentada empina (Vehicle._tick_motorcycle_wheelie) e tomba com
	# amassados; filho do CharacterBody3D, o projetor ficava parado no ar à frente da lente
	# (13/10: "farol voando"). Pendurado no visual ele acompanha a lente. Carros seguem no corpo.
	# `mount` sai da lente já na pose atual do visual, então a conversão usa o transform atual.
	var on_visual: bool = car.archetype.begins_with("bike_") and is_instance_valid(car.visual) and car.visual.get_parent() == car
	var placement := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-7)), mount + Vector3(0, 0, -.06))
	light.transform = car.visual.transform.affine_inverse() * placement if on_visual else placement
	light.light_color = profile.color
	# Let the actual beam reveal road texture and vertical surfaces. The old
	# emissive pool flattened the road while the physical source was barely visible.
	light.light_energy = energy * 2.2
	if LIGHT_BUDGET.enabled: light.set_meta("budget_energy", light.light_energy)
	light.spot_range = float(profile.range)
	light.spot_angle = angle
	light.spot_attenuation = .7
	light.spot_angle_attenuation = 1.5
	light.light_specular = .35
	# Every enabled projector must stop at opaque bodywork, including race
	# opponents and parked theft alarms. Hidden projectors do not render shadows.
	light.shadow_enabled = true
	light.distance_fade_enabled = true
	light.distance_fade_begin = 35.0
	light.distance_fade_length = 15.0
	light.hide()
	(car.visual if on_visual else car).add_child(light)
	return light

func _glow(parent: Node3D, point: Vector3, color: Color, size: float) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name = "VehicleLensGlow"
	sprite.texture = _lens_glow_texture()
	sprite.pixel_size = size / 64.0
	sprite.modulate = color
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.position = point
	sprite.hide()
	parent.add_child(sprite)
	return sprite

static func _lens_glow_texture() -> ImageTexture:
	if _glow_texture != null: return _glow_texture
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var radius := Vector2(float(x) / 63.0 * 2.0 - 1.0, float(y) / 63.0 * 2.0 - 1.0).length()
			var alpha := pow(1.0 - smoothstep(0.0, 1.0, radius), 2.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	image.generate_mipmaps()
	_glow_texture = ImageTexture.create_from_image(image)
	return _glow_texture

## Papel de uma lente do modelo original. Exportações mais novas marcam a
## chave; as antigas não, e aí vale cor emissiva + posição: branco-creme na
## frente é farol, vermelho atrás é lanterna. A posição exclui o luminoso do
## táxi e o giroflex, que ficam no teto, perto do centro.
func _lens_role(key: String, material: StandardMaterial3D, local: Vector3) -> String:
	if SURFACES.is_headlight_lens(key): return "headlight" if local.z < 0 else ""
	if SURFACES.is_tail_lens(key): return "tail" if local.z > 0 else ""
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
	# Dentro do carro a tecla da lanterna da arma (G) não serve para nada: buzina também.
	if event.is_action_pressed("horn", false) or event.is_action_pressed("weapon_flashlight", false): return honk()
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
	var archetype := str(car.archetype)
	var family: String = ENGINE_PROFILE.family(archetype)
	horn_audio.stream = AUDIO.horn_stream(family,archetype)
	# Buzina de ar (caminhão, ônibus, bombeiro, blindado) é mais alta e se ouve de mais longe.
	var heavy: bool = AUDIO.is_heavy_horn(family)
	horn_audio.volume_db = -3.0 if heavy else -7.0
	horn_audio.max_distance = 70.0 if heavy else 43.75
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
	if is_instance_valid(car):
		_brake_hold = maxf(0.0,_brake_hold-delta)
		if car.traffic and car.speed > .3 and (_previous_speed-car.speed) / maxf(delta,.001) > 1.0: _brake_hold = .15
		_decelerating = _brake_hold > 0
		_previous_speed = car.speed
	if alarm_remaining > 0:
		alarm_remaining = maxf(0, alarm_remaining - delta)
		if alarm_remaining <= 0: changed.emit()
	_refresh(false)

func _refresh(force_budget: bool = true) -> void:
	if not is_instance_valid(car): return
	var occupied: bool = car.controlled and car.health > 0
	# V1 piscava os faróis junto com o alarme, a cada ~1/6 s.
	# Whole clock buckets; preserve integer precision and cadence.
	@warning_ignore("integer_division")
	var alarm_blink: bool = alarm_remaining > 0 and car.health > 0 and int(Time.get_ticks_msec() / 167) % 2 == 0
	var was_auto := auto_lit
	auto_lit = night_auto_enabled and car.health > 0 and npc_driven() and is_dark()
	if auto_lit and not LIGHT_BUDGET.enabled: _npc_beams[get_instance_id()] = true
	# Quem toma um carro aceso à noite continua com o farol ligado.
	if was_auto and not auto_lit and occupied and not car.external_input: headlights_on = true
	# Drag owns two physical cars without assigning the rival to player controls.
	# Its scoped marker is removed by race cleanup; normal traffic keeps its budget.
	var race_lit: bool = car.has_meta("desert_drag_physics") and car.health>0
	var driver_lit: bool = (headlights_on and (occupied or race_lit) and (not npc_driven() or race_lit)) or alarm_blink
	var lit: bool = driver_lit or auto_lit
	if LIGHT_BUDGET.enabled:
		for item in glows:
			var broken: bool = _side_broken(item.side)
			item.sprite.visible = lit and car.health > 0 and not broken
	else:
		for item in lamps:
			var broken: bool = (item.side < 0 and broken_left) or (item.side > 0 and broken_right)
			item.lamp.visible = driver_lit and not broken
		if is_instance_valid(npc_beam): npc_beam.visible = auto_lit and not driver_lit and _npc_beam_allowed() and not (broken_left and broken_right)
	# Lenses change only with power/damage. Avoid resending the same material
	# parameters for every parked/traffic car on every rendered frame.
	var lens_state := int(lit) | (int(broken_left) << 1) | (int(broken_right) << 2)
	if lens_state != _lens_state:
		_lens_state = lens_state
		for item in lens_materials:
			var broken: bool = _side_broken(item.side) if LIGHT_BUDGET.enabled else ((item.side < 0 and broken_left) or (item.side > 0 and broken_right))
			item.material.emission_enabled = lit and not broken
			item.material.emission_energy_multiplier = 1.35 if (lit and not broken) else 0.0
	var markers_lit := 1 if lit and car.health > 0 else 0
	if markers_lit != _markers_lit:
		_markers_lit = markers_lit
		for marker in cab_markers: marker.material_override = _marker_on if markers_lit else _marker_off
	# Lanterna traseira: acesa fraca à noite, forte na frenagem, apagada de dia.
	# Carro estacionado sem motorista não "freia", mesmo com brake_input preso.
	var braking: bool = car.health > 0 and (car.controlled or car.traffic) and (car.brake_input or car.blocked or _decelerating or (car.throttle_input < -.05 and car.speed > .5))
	var tail_state := 2 if braking else (1 if lit else 0)
	if tail_state != _tail_state:
		_tail_state = tail_state
		for index in tail_materials.size():
			var material := tail_materials[index]
			material.emission_enabled = lit or braking
			material.emission_energy_multiplier = 2.5 if braking else (.9 if lit else 0.0)
			material.albedo_color = Color(1.0,.055,.025) if braking else _tail_colors[index]
	var sounding := siren_on and occupied and not beacons.is_empty()
	if is_instance_valid(siren_audio):
		if sounding and not siren_audio.playing:
			siren_audio.stream = AUDIO.siren_stream()
			siren_audio.play()
		elif not sounding and siren_audio.playing: siren_audio.stop()
	if not occupied and is_instance_valid(horn_audio) and horn_audio.playing: horn_audio.stop()
	# O alarme vale com o carro vazio: é justamente o estado de quem falhou o lockpick.
	var alarming: bool = alarm_remaining > 0 and car.health > 0
	if is_instance_valid(alarm_audio):
		if alarming and not alarm_audio.playing:
			alarm_audio.stream = AUDIO.alarm_stream()
			alarm_audio.play()
		elif not alarming and alarm_audio.playing: alarm_audio.stop()
	var flashing: bool = (sounding or alarming) and not beacons.is_empty()
	# Whole clock buckets; preserve integer precision and cadence.
	@warning_ignore("integer_division")
	var phase := int(Time.get_ticks_msec() / 160) % 2 if flashing else -1
	# O orçamento precisa acompanhar a câmera mesmo quando a sirene conserva a fase.
	if LIGHT_BUDGET.enabled: LIGHT_BUDGET.refresh(force_budget)
	if phase == _phase: return
	_phase = phase
	if is_instance_valid(halo):
		if not LIGHT_BUDGET.enabled: halo.visible = phase >= 0
		for beacon in beacons:
			if beacon.side == phase: halo.light_color = beacon.color
	for beacon in beacons:
		var active: bool = beacon.side == phase
		beacon.material.albedo_color = beacon.color.lerp(Color.WHITE, .55) if active else beacon.color
		beacon.material.emission = beacon.color
		beacon.material.emission_enabled = active
		beacon.material.emission_energy_multiplier = 2.8 if active else 0.0
	for item in beacon_glows: item.sprite.visible = item.side == phase

func _side_broken(side: int) -> bool:
	# Um farol central de moto quebra quando qualquer lado da lente é atingido.
	if profile.get("single", false): return broken_left or broken_right
	# Lentes fundidas dos carros podem ter centro x=0: ainda representam o par.
	if side == 0: return broken_left and broken_right
	return (side < 0 and broken_left) or (side > 0 and broken_right)

## Estado desejado, separado da visibilidade que o orçamento controla. A leitura
## de todos os donos evita usar o estado atrasado de outro carro no mesmo quadro.
func _budget_request() -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	var point := camera.global_position if is_instance_valid(camera) else Vector3.ZERO
	if is_instance_valid(world):
		var player = world.get("player")
		if is_instance_valid(player): point = player.global_position
	var lights: Array[Light3D] = []
	var wanted: Array[Dictionary] = []
	for item in lamps:
		if is_instance_valid(item.lamp): lights.append(item.lamp)
	if is_instance_valid(npc_beam): lights.append(npc_beam)
	if is_instance_valid(halo): lights.append(halo)
	var player_driven: bool = is_instance_valid(car) and car.controlled and not car.external_input and not car.traffic
	var result := {"lights": lights, "wanted": wanted, "player": player_driven, "camera": point, "decal": null, "pool": false}
	if not is_instance_valid(car) or not car.is_inside_tree() or car.is_queued_for_deletion() or not car.is_visible_in_tree() or car.health <= 0: return result
	var occupied: bool = car.controlled
	var automatic := night_auto_enabled and npc_driven() and is_dark()
	@warning_ignore("integer_division")
	var alarm_blink: bool = alarm_remaining > 0 and int(Time.get_ticks_msec() / 167) % 2 == 0
	var race: bool = car.has_meta("desert_drag_physics")
	var driver: bool = ((headlights_on or (auto_lit and player_driven)) and (occupied or race) and (not npc_driven() or race)) or alarm_blink
	if driver:
		for item in lamps:
			if not _side_broken(item.side): wanted.append({"light": item.lamp, "headlight": true})
	elif automatic and not (broken_left and broken_right) and not (profile.single and (broken_left or broken_right)):
		wanted.append({"light": npc_beam, "headlight": true})
	if is_instance_valid(halo) and ((siren_on and occupied) or alarm_remaining > 0):
		wanted.append({"light": halo, "headlight": false})
	return result

func receive_impact(local_point: Vector3, severity: float) -> void:
	if severity < 3.0: return
	var changed_now := false
	if local_point.z < -car.half_length * 0.4:
		if local_point.x < 0.2 and not broken_left:
			broken_left = true
			changed_now = true
		if local_point.x > -0.2 and not broken_right:
			broken_right = true
			changed_now = true
	if changed_now:
		_refresh()
		changed.emit()

func snapshot() -> Dictionary: return {"headlights": headlights_on, "siren": siren_on}

func restore_state(data: Dictionary) -> bool:
	if not data.get("headlights") is bool or not data.get("siren") is bool: return false
	if data.siren and beacons.is_empty(): return false
	headlights_on = data.headlights
	siren_on = data.siren
	_refresh()
	return true

func _exit_tree() -> void:
	if LIGHT_BUDGET.enabled:
		# As fontes são irmãs do equipamento; queue_free só as remove no fim
		# do quadro. Ocultá-las agora devolve vagas sem sobreposição na reentrada.
		for item in lamps:
			if is_instance_valid(item.lamp): item.lamp.hide()
		for source in [npc_beam, halo]:
			if is_instance_valid(source): source.hide()
		for item in glows:
			if is_instance_valid(item.sprite): item.sprite.hide()
		for item in beacon_glows:
			if is_instance_valid(item.sprite): item.sprite.hide()
		LIGHT_BUDGET.unregister(self)
	for emitter in [horn_audio, siren_audio, alarm_audio]:
		if is_instance_valid(emitter):
			emitter.stop()
			emitter.stream = null
			emitter.queue_free()
	for item in lamps:
		if is_instance_valid(item.lamp): item.lamp.queue_free()
	if is_instance_valid(halo): halo.queue_free()
	for marker in cab_markers:
		if is_instance_valid(marker): marker.queue_free()
	if is_instance_valid(npc_beam): npc_beam.queue_free()
	for item in glows:
		if is_instance_valid(item.sprite): item.sprite.queue_free()
	for item in beacon_glows:
		if is_instance_valid(item.sprite): item.sprite.queue_free()
	_npc_beams.erase(get_instance_id())

## Caminhão de bombeiro (rescue_pumper.scn):
## - As faixas amarelas em V da traseira ficavam no mesmo plano da porta (z 3,32)
##   e brigavam no buffer de profundidade: pareciam riscos picotados. Saem 2 cm.
## - O canhão do teto (base vermelha, cano, bico) era peça fixa. Cano e bico vão
##   para um pivô sobre a base, que o bombeiro gira para mirar no fogo; a água sai
##   do bico (meta "fire_monitor" / "fire_monitor_tip" no carro).
func _rig_pumper() -> void:
	var pivot := Node3D.new()
	pivot.name = "FireMonitorPivot"
	var parts: Array[MeshInstance3D] = []
	var tip: MeshInstance3D
	for part: MeshInstance3D in car.visual.find_children("*", "MeshInstance3D", true, false):
		var material := part.get_active_material(0) as StandardMaterial3D
		if material == null: continue
		var box: AABB = car.global_transform.affine_inverse() * part.global_transform * part.get_aabb()
		var color := material.albedo_color
		if color.is_equal_approx(Color("f1c40f")) and box.position.z > 3.2:
			part.global_position += car.global_basis.z * 0.02
		# Cano e bico: finos, no teto, à frente da base (z < -1.4).
		elif box.position.y > 2.3 and box.end.z < -1.4 and box.size.x < 0.3:
			if color.is_equal_approx(Color("a82020")): continue
			parts.append(part)
			if box.position.z < -2.3: tip = part
		elif color.is_equal_approx(Color("a82020")) and box.position.y > 2.1 and box.end.z < -1.3:
			pivot.position = car.to_local(part.global_position) if pivot.position == Vector3.ZERO else pivot.position
			var center := box.get_center()
			pivot.set_meta("base_local", Vector3(center.x, box.end.y, center.z))
	if parts.is_empty() or tip == null:
		pivot.free()
		return
	car.add_child(pivot)
	pivot.position = pivot.get_meta("base_local", pivot.position)
	for part in parts:
		var keep := part.global_transform
		part.get_parent().remove_child(part)
		pivot.add_child(part)
		part.global_transform = keep
	car.set_meta("fire_monitor", pivot)
	car.set_meta("fire_monitor_tip", tip)
