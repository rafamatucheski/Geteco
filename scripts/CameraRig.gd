extends Camera3D

const SCOPE_SIZE_MULTIPLIER := 0.5
const FOLLOW_RATE := 4.2
const HEIGHT_FOLLOW_RATE := 10.0
const V1_VIEWPORT_HEIGHT := 720.0
const V1_PIXELS_PER_METRE := 16.0
const V1_WALK_ZOOM_CLOSE := 2.072
const V1_WALK_ZOOM_FAR := 1.96
const V1_DRIVE_ZOOM_CLOSE := 1.55
const V1_DRIVE_ZOOM_FAR := 1.25
const V1_DRIVE_ZOOM_NITRO := 1.15
const V1_CAMERA_SPEED := 600.0 / V1_PIXELS_PER_METRE
const V1_WALK_LEAD := 18.0 / V1_PIXELS_PER_METRE
const V1_DRIVE_LEAD := 52.0 / V1_PIXELS_PER_METRE
const V1_SCOPE_LEAD := 250.0 / V1_PIXELS_PER_METRE
# Inclinação de 45° (antes ~52°, Vector3(0,28,22)). Com a câmera quase de
# cima, a laje dos prédios ocupava ~60% da tela e a fachada virava uma faixa
# fina; a 45° a relação fachada/telhado sobe ~28% (cot 0,79 -> 1,0), leitura
# de "cidade de jogo" à la GTA Chinatown Wars. A distância ao foco (~35.8 m)
# foi mantida para não mudar atenuação de áudio nem o near/far.
const EXTERIOR_OFFSET := Vector3(0,25.3,25.3)
const PREVIEW_OFFSET := Vector3(0, 21.8, 28.4)
const PREVIEW_HEADING := PI / 4.0
const STORE_FOCUS_OFFSET := Vector3(0,12.0,25.3)
# Camera3D.size measures the vertical camera plane. The productive V1 zoom
# measured visible ground, so compensate for the exterior pitch instead of
# copying Camera2D numbers into metres. Equals sin(pitch) of EXTERIOR_OFFSET.
const EXTERIOR_GROUND_PROJECTION := 0.7071068
# A escala aparente de quem está de pé é proporcional a cot(inclinação)/size.
# As medições V1 abaixo foram calibradas com a câmera antiga (cot = 22/28);
# baixar a câmera faria o Dante crescer ~27% na tela. Abrir todo o
# enquadramento (andar E dirigir) na mesma proporção preserva o tamanho do
# personagem da V1 e a relação andar/dirigir; o chão visível fica ~27% maior.
const V1_CALIBRATION_PITCH_COT := 22.0 / 28.0
const PITCH_APPARENT_COMPENSATION := (25.3 / 25.3) / V1_CALIBRATION_PITCH_COT
# Equivalent 1280x720 captures measured the productive V1 Dante alpha rig at
# 34.312 px and the native 1.80 m V2 actor at 46.886 px with ground-only
# conversion. Walking framing compensates that presentation difference while
# vehicle framing keeps the V1 road/vehicle projection independently.
const V1_WALK_APPARENT_SCALE := 46.8863525390625 / 34.3123196752596
# Pedido de jogo (2026-09-22): a câmera parecia longe demais. Aproxima 25% o
# enquadramento inteiro (andar, dirigir e mira) sem mexer na calibração V1
# acima, para que a relação andar/dirigir continue a mesma.
const FRAMING_ZOOM_SCALE := 0.75
const WALK_SIZE_CLOSE := V1_VIEWPORT_HEIGHT / (V1_WALK_ZOOM_CLOSE * V1_PIXELS_PER_METRE) * EXTERIOR_GROUND_PROJECTION * PITCH_APPARENT_COMPENSATION * V1_WALK_APPARENT_SCALE * FRAMING_ZOOM_SCALE
const TARGET_TELEPORT_DISTANCE := 8.0
var target: Node3D
var heading := 0.0
var target_size := WALK_SIZE_CLOSE
var focus := Vector3.ZERO
var initialized := false
var locked := false
var offset := EXTERIOR_OFFSET
var scope_reticle: Control
var _smoothed_lead := Vector3.ZERO
var _tracked_target_id := 0
var _last_auto_size := WALK_SIZE_CLOSE
var _external_size_target_id := 0
var _was_locked := false
var _store_focus_active := false
var _store_focus_from := Vector3.ZERO
var _store_focus_to := Vector3.ZERO
var _store_size_from := 0.0
var _store_size_to := 0.0
var _store_focus_elapsed := 0.0
var _store_focus_duration := 0.55
var _store_focus_reverse := false
var preview_view := false
var _preview_blend := 0.0
var _container_blend := 0.0
var _container_focus := Vector3.ZERO
# Túnel do canal: 0 fora, 1 no fundo (cresce com a profundidade do alvo na rampa).
# Aproxima o zoom, levanta a inclinação e apaga a cidade que tapa o tubo; volta suave ao sair.
var _tunnel_blend := 0.0
const CANAL_TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
const TUNNEL_CUTAWAY := preload("res://world/urban_detail/TunnelCutaway.gd")
const TUNNEL_ZOOM := 0.62
# 70° de inclinação, mesma distância ao foco do EXTERIOR_OFFSET (~35,8 m: áudio e
# near/far intactos). A 45° o chão ao sul da vala tapava o carro assim que o piso
# passava de ~4,3 m de profundidade (a linha de visada só sai do chão 6 m ao sul);
# a 70° o fundo da vala (−6 m) fica visível a partir de 2,2 m da borda sul.
const TUNNEL_OFFSET := Vector3(0, 33.6, 12.2)
const TUNNEL_DEPTH_START := 0.6
const TUNNEL_DEPTH_FULL := 3.2
const TUNNEL_BLEND_RATE := 1.6
# O corte da cidade só começa depois que a câmera já está bem inclinada.
const TUNNEL_CUTAWAY_START := 0.3
var _cutaway := TUNNEL_CUTAWAY.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	projection = Camera3D.PROJECTION_ORTHOGONAL
	size = target_size
	near = 0.1
	far = 180.0
	current = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var settings := get_node_or_null("/root/V2Settings")
	if settings != null:
		settings.applied.connect(_read_camera_settings)
		_read_camera_settings()
	if "--camera-preview" in OS.get_cmdline_user_args(): set_preview_view(true)

func _read_camera_settings() -> void:
	var settings := get_node_or_null("/root/V2Settings")
	if settings != null: set_preview_view(int(settings.get("camera_view")) == 1)

func set_preview_view(enabled: bool) -> void:
	preview_view = enabled

func _exterior_view_offset() -> Vector3:
	# Never change authored interior offsets, target, zoom, or heading.
	if locked: return offset
	var exterior := offset.lerp(PREVIEW_OFFSET.rotated(Vector3.UP, PREVIEW_HEADING), _preview_blend)
	exterior = exterior.lerp(TUNNEL_OFFSET, smoothstep(0.0, 1.0, _tunnel_blend))
	# Tiny Z offset keeps look_at's up vector non-collinear at the overhead view.
	return exterior.lerp(Vector3(0,35,.15),_container_blend)

func _process(delta: float) -> void:
	var container_view := has_meta("port_container_focus") and not locked
	if container_view: _container_focus = get_meta("port_container_focus")
	if not get_tree().paused:
		_container_blend = move_toward(_container_blend,1.0 if container_view else 0.0,maxf(0,delta)/.6)
	if not locked and not get_tree().paused:
		_preview_blend = move_toward(_preview_blend, 1.0 if preview_view else 0.0, maxf(0.0, delta) * 2.0)
	_ensure_scope_reticle()
	var scoped := _scope_active()
	if is_instance_valid(scope_reticle):
		var combat := _gameplay()
		# Production sights follow the shot; do not overlay a second cross at screen centre.
		scope_reticle.visible = scoped and not (combat != null and combat.has_method("aim_feedback_active"))
	if _store_focus_active:
		_store_focus_elapsed = minf(_store_focus_duration, _store_focus_elapsed + maxf(delta, 0.0))
		var t := _store_focus_elapsed / _store_focus_duration
		var eased := t * t * (3.0 - 2.0 * t)
		focus = _store_focus_from.lerp(_store_focus_to, eased)
		size = lerpf(_store_size_from, _store_size_to, eased)
		var start_offset: Vector3 = STORE_FOCUS_OFFSET if _store_focus_reverse else _exterior_view_offset()
		var end_offset: Vector3 = _exterior_view_offset() if _store_focus_reverse else STORE_FOCUS_OFFSET
		global_position = focus + start_offset.lerp(end_offset, eased).rotated(Vector3.UP, heading)
		look_at(focus)
		return
	if not is_instance_valid(target): return
	delta = maxf(delta,0.0) if is_finite(delta) else 0.0
	var target_changed := _track_target()
	var actual := target.global_position
	var interpolated := target.get_global_transform_interpolated().origin
	var teleported := actual.distance_to(interpolated) > TARGET_TELEPORT_DISTANCE
	var base := actual if teleported or locked else interpolated
	var snap := not initialized or teleported or locked != _was_locked
	# Small paving steps must not kick the entire street vertically. Keep
	# horizontal tracking immediate and preserve snaps/locked interior framing.
	if not snap and not target_changed and not locked and target is CharacterBody3D and not _is_vehicle_target():
		base.y = lerpf(focus.y - _smoothed_lead.y, base.y, 1.0 - exp(-HEIGHT_FOLLOW_RATE * delta))
	if target_changed:
		if initialized and not snap and focus.distance_to(base) <= TARGET_TELEPORT_DISTANCE:
			# V1 handed the old screen centre to the new actor camera. Retain that
			# centre when boarding/leaving a nearby vehicle, then converge to lead.
			_smoothed_lead = focus-base
		else:
			_smoothed_lead = Vector3.ZERO
	var desired_lead := Vector3.ZERO if locked else _desired_lead(base,scoped)
	if snap:
		_smoothed_lead = desired_lead if not locked else Vector3.ZERO
	else:
		_smoothed_lead = _smoothed_lead.lerp(desired_lead,1.0-exp(-FOLLOW_RATE*delta))
	# Physics interpolation already smooths the actor itself. Only lead is
	# damped, matching V1 and avoiding a second full-target trail.
	focus = base+_smoothed_lead
	if not locked and _container_blend > 0:
		focus = focus.lerp(_container_focus,_container_blend)
	initialized = true
	var base_size := _base_size()
	var desired_size := base_size*SCOPE_SIZE_MULTIPLIER if scoped else base_size
	if not locked: desired_size *= float(get_meta("port_container_zoom",1.0))
	var tunnel_depth := 0.0
	if not locked and CANAL_TUNNEL.in_roadway(actual):
		tunnel_depth = smoothstep(TUNNEL_DEPTH_START, TUNNEL_DEPTH_FULL, -actual.y)
	_tunnel_blend = move_toward(_tunnel_blend, tunnel_depth, delta * TUNNEL_BLEND_RATE)
	if _tunnel_blend > 0.0: desired_size *= lerpf(1.0, TUNNEL_ZOOM, smoothstep(0.0, 1.0, _tunnel_blend))
	_update_cutaway()
	if snap or locked:
		size = desired_size
	else:
		size = lerpf(size,desired_size,1.0-exp(-FOLLOW_RATE*delta))
	global_position = focus + _exterior_view_offset().rotated(Vector3.UP, heading)
	look_at(focus)
	_was_locked = locked

## Apaga a cidade entre a câmera e o tubo enquanto o alvo está fundo no túnel.
func _update_cutaway() -> void:
	var strength := clampf((_tunnel_blend - TUNNEL_CUTAWAY_START) / (1.0 - TUNNEL_CUTAWAY_START), 0.0, 1.0)
	CANAL_TUNNEL.set_camera_reveal(smoothstep(0.0, 1.0, strength))
	var aspect := get_viewport().get_visible_rect().size.aspect() if is_inside_tree() else 1.78
	# Meia largura visível + folga: quem entra na janela já está apagado antes de aparecer.
	var half_width := size * aspect * 0.5 + 16.0
	var chunks: Array = []
	if strength > 0.0:
		var world := get_parent()
		var production: Variant = world.get("production") if world != null else null
		var regions: Variant = production.get("regions") if production is Node else null
		var harbor: Variant = regions.get("harbor") if regions is Dictionary else null
		if harbor is Node and is_instance_valid(harbor):
			# Só os chunks sob a janela do túnel (e a faixa ao sul que a varredura alcança).
			var reach := Rect2(focus.x - half_width, CANAL_TUNNEL.outer_north() - 4.0, half_width * 2.0, CANAL_TUNNEL.outer_south() - CANAL_TUNNEL.outer_north() + 40.0)
			for key in harbor.chunks:
				if Rect2(Vector2(key) * harbor.CELL, Vector2.ONE * harbor.CELL).intersects(reach): chunks.append(harbor.chunks[key])
	_cutaway.update(chunks, focus, global_position - focus, half_width, smoothstep(0.0, 1.0, strength), get_process_delta_time())

func focus_on_store(point: Vector3, final_size: float, duration: float) -> void:
	_store_focus_reverse = false
	_store_focus_from = focus if initialized else (target.global_position if is_instance_valid(target) else point)
	_store_focus_to = point
	_store_size_from = size
	_store_size_to = maxf(1.0, final_size)
	_store_focus_elapsed = 0.0
	_store_focus_duration = maxf(0.01, duration)
	_store_focus_active = true

func zoom_out_from_store(point: Vector3, close_size: float, duration: float) -> void:
	_store_focus_from = point
	_store_focus_to = target.global_position if is_instance_valid(target) else point
	_store_size_from = maxf(1.0, close_size)
	_store_size_to = maxf(1.0, target_size)
	_store_focus_elapsed = 0.0
	_store_focus_duration = maxf(0.01, duration)
	_store_focus_reverse = true
	_store_focus_active = true

func clear_store_focus() -> void:
	_store_focus_active = false

static func size_for_v1_zoom(zoom: float) -> float:
	if not is_finite(zoom) or zoom <= 0.0: return WALK_SIZE_CLOSE
	return V1_VIEWPORT_HEIGHT/(zoom*V1_PIXELS_PER_METRE)*EXTERIOR_GROUND_PROJECTION*PITCH_APPARENT_COMPENSATION*FRAMING_ZOOM_SCALE

static func walking_size_for_v1_zoom(zoom: float) -> float:
	return size_for_v1_zoom(zoom)*V1_WALK_APPARENT_SCALE

func _track_target() -> bool:
	var id := target.get_instance_id()
	if id == _tracked_target_id: return false
	_tracked_target_id = id
	_external_size_target_id = 0
	return true

func _base_size() -> float:
	if locked: return clampf(target_size,1.0,200.0)
	# Capture/review tools set target_size directly. Honour that explicit value
	# for the current target without disabling productive automatic framing.
	if not is_equal_approx(target_size,_last_auto_size) and _external_size_target_id == 0:
		_external_size_target_id = _tracked_target_id
	if _external_size_target_id == _tracked_target_id:
		return clampf(target_size,14.0,52.0)
	var automatic := _vehicle_size() if _is_vehicle_target() else _walking_size()
	target_size = clampf(automatic,14.0,52.0)
	_last_auto_size = target_size
	return target_size

func _walking_size() -> float:
	var speed := _flat_velocity().length()
	var factor := clampf(speed/V1_CAMERA_SPEED,0.0,1.0)
	return walking_size_for_v1_zoom(lerpf(V1_WALK_ZOOM_CLOSE,V1_WALK_ZOOM_FAR,factor))

func _vehicle_size() -> float:
	var speed := absf(_target_number(&"speed",_flat_velocity().length()))
	var maximum := maxf(.1,_target_number(&"max_forward_speed",V1_CAMERA_SPEED))
	var zoom := lerpf(V1_DRIVE_ZOOM_CLOSE,V1_DRIVE_ZOOM_FAR,clampf(speed/maximum,0.0,1.0))
	if _target_bool(&"is_boosting"): zoom = V1_DRIVE_ZOOM_NITRO
	# The V1 vehicle camera opens from the pedestrian view. The native actor
	# needs an apparent-scale adaptation, so a stationary handoff may retain the
	# current frame but must never tighten it.
	return maxf(WALK_SIZE_CLOSE,size_for_v1_zoom(zoom))

func _desired_lead(base: Vector3,scoped: bool) -> Vector3:
	if scoped:
		var gameplay := _gameplay()
		if gameplay != null:
			var aim: Variant = gameplay.get("aim_point")
			if aim is Vector3:
				var scoped_lead: Vector3 = aim-base
				scoped_lead.y = 0.0
				return scoped_lead.limit_length(V1_SCOPE_LEAD)
	var combat := _gameplay()
	if not _is_vehicle_target() and combat != null and combat.has_method("aim_feedback_active") and combat.aim_feedback_active():
		var lead: Vector3 = combat.aim_point - base
		lead.y = 0.0
		return (lead * 0.3).limit_length(3.5)
	var velocity := _flat_velocity()
	if velocity.length_squared() <= .0001: return Vector3.ZERO
	var limit := V1_DRIVE_LEAD if _is_vehicle_target() else V1_WALK_LEAD
	var multiplier := 1.35 if _is_vehicle_target() and _target_bool(&"is_boosting") else 1.0
	return velocity.normalized()*minf(limit*multiplier,velocity.length()*.1*multiplier)

func _flat_velocity() -> Vector3:
	if target is CharacterBody3D:
		var result: Vector3 = target.velocity
		result.y = 0.0
		return result
	return Vector3.ZERO

func _is_vehicle_target() -> bool:
	return is_instance_valid(target) and &"max_forward_speed" in target

func _target_number(property: StringName,fallback: float) -> float:
	if not property in target: return fallback
	var value: Variant = target.get(property)
	return float(value) if typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) else fallback

func _target_bool(property: StringName) -> bool:
	return property in target and target.get(property) == true

func _gameplay() -> Node:
	var world := get_parent()
	if world == null: return null
	var gameplay: Variant = world.get("gameplay")
	return gameplay if gameplay is Node and is_instance_valid(gameplay) else null

func _scope_active() -> bool:
	if locked: return false
	var gameplay := _gameplay()
	return gameplay != null and is_instance_valid(gameplay) and gameplay.has_method("scope_active") and gameplay.scope_active()

func _ensure_scope_reticle() -> void:
	if is_instance_valid(scope_reticle): return
	var world := get_parent()
	if world == null: return
	var hud: Variant = world.get("hud")
	if hud == null or not is_instance_valid(hud): return
	scope_reticle = Control.new()
	scope_reticle.name = "ScopeReticle"
	scope_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope_reticle.process_mode = Node.PROCESS_MODE_ALWAYS
	hud.add_child(scope_reticle)
	scope_reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for spec in [
		[Vector2(-20,-1),Vector2(14,2)], [Vector2(6,-1),Vector2(14,2)],
		[Vector2(-1,-20),Vector2(2,14)], [Vector2(-1,6),Vector2(2,14)],
	]:
		var bar := ColorRect.new()
		bar.color = Color(0.92,0.96,0.90,0.92)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scope_reticle.add_child(bar)
		bar.set_anchors_preset(Control.PRESET_CENTER)
		bar.position = spec[0]
		bar.size = spec[1]
	scope_reticle.hide()

func _exit_tree() -> void:
	_cutaway.release()
	CANAL_TUNNEL.set_camera_reveal(0.0)
	if is_instance_valid(scope_reticle):
		scope_reticle.hide()
		scope_reticle.queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if locked or get_tree().paused: return
	# A V1 (DynamicCamera) não tinha zoom manual: o enquadramento vem só da
	# velocidade, nitro e luneta. A roda do mouse é da troca de arma a pé e da
	# sintonia de rádio no carro, então a câmera não a consome.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("camera_left"): heading += PI / 4
		if event.is_action_pressed("camera_right"): heading -= PI / 4
