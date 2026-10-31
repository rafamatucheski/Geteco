extends Camera3D

const SCOPE_SIZE_MULTIPLIER := 0.5
const SMUGGLER_CANYON := preload("res://world/desert/canyon/DesertSmugglerLayout.gd")
const FOLLOW_RATE := 4.2
const AIM_FOLLOW_RATE := 12.0
const ORBIT_FOLLOW_RATE := 16.0
const MOUSE_ORBIT_RADIANS_PER_PIXEL := 0.004
const GAMEPAD_ORBIT_SPEED := deg_to_rad(110.0)
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
# Inclinação de 45°: equilibra a leitura da rua com o volume das fachadas.
# Mantém a distância ao foco (~35,8 m) e a escala aparente calibrada abaixo.
const EXTERIOR_OFFSET := Vector3(0,25.30,25.30)
# Pedido de jogo (2026-10-12): visão "3D por trás do boneco, na diagonal". 36° de inclinação
# na mesma distância ao foco (~35,8 m): mostra mais da rua à frente e as fachadas.
const PREVIEW_OFFSET := Vector3(0, 21.0, 29.0)
const PREVIEW_DRIVE_OFFSET := Vector3(0, 24.0, 26.5)
# Pedido de jogo (2026-10-12): dentro do carro a câmera sobe e inclina mais para baixo para
# mostrar mais da cidade. 58° de inclinação na mesma distância ao foco (~35,8 m, então áudio e
# near/far seguem iguais) e enquadramento 12% mais aberto, só com veículo.
const DRIVE_OFFSET := Vector3(0, 30.4, 19.0)
const DRIVE_VIEW_SIZE_SCALE := 1.12
const DRIVE_VIEW_BLEND_SECONDS := 0.6
const PREVIEW_HEADING := PI / 4.0
const STORE_FOCUS_OFFSET := Vector3(0,12.0,25.3)
# Camera3D.size mede o plano vertical da câmera. O zoom produtivo da V1
# media o chão visível, então compensa o pitch exterior em vez de
# copiar números da Camera2D para metros. Igual a sin(pitch) de EXTERIOR_OFFSET.
const EXTERIOR_GROUND_PROJECTION := 0.7071067811865476 # sin(45°)
# A escala aparente de quem está de pé é proporcional a cot(inclinação)/size.
# As medições V1 abaixo foram calibradas com a câmera antiga (cot = 22/28);
# mudar a inclinação alteraria o tamanho de Dante na tela. Compensar todo o
# enquadramento (andar E dirigir) na mesma proporção preserva o tamanho do
# personagem da V1 e a relação andar/dirigir.
const V1_CALIBRATION_PITCH_COT := 22.0 / 28.0
const PITCH_APPARENT_COMPENSATION := (EXTERIOR_OFFSET.z / EXTERIOR_OFFSET.y) / V1_CALIBRATION_PITCH_COT
# Capturas equivalentes em 1280x720 mediram o rig alpha produtivo do Dante na V1 com
# 34.312 px e o ator nativo de 1.80 m da V2 com 46.886 px, convertendo só pelo
# chão. O enquadramento a pé compensa essa diferença de apresentação enquanto
# o enquadramento de veículo mantém a projeção de rua/veículo da V1 de forma independente.
const V1_WALK_APPARENT_SCALE := 46.8863525390625 / 34.3123196752596
# Pedido de jogo (2026-09-22): a câmera parecia longe demais. Aproxima 25% o
# enquadramento inteiro (andar, dirigir e mira) sem mexer na calibração V1
# acima, para que a relação andar/dirigir continue a mesma.
# Pedido de jogo (2026-10-12): aproximar mais 13% sobre o enquadramento atual.
const FRAMING_ZOOM_SCALE := 0.75 * 0.87
const WALK_SIZE_CLOSE := V1_VIEWPORT_HEIGHT / (V1_WALK_ZOOM_CLOSE * V1_PIXELS_PER_METRE) * EXTERIOR_GROUND_PROJECTION * PITCH_APPARENT_COMPENSATION * V1_WALK_APPARENT_SCALE * FRAMING_ZOOM_SCALE
const TARGET_TELEPORT_DISTANCE := 8.0
# Enquadramento de desenvolvedor só da sessão; o enquadramento normal do jogo volta a valer depois do reset.
var developer_zoom := 1.0
var developer_view := 0
var developer_chase := false
var _developer_camera_state: Dictionary = {}

func set_developer_zoom(multiplier: float, view: int = 0) -> void:
	if not is_finite(multiplier): return
	_release_exterior_depth_range()
	if _developer_camera_state.is_empty():
		_developer_camera_state = {"projection": projection, "size": size, "far": far, "near": near, "fov": fov}
	developer_zoom = clampf(multiplier, 1.0, 1000.0)
	developer_view = clampi(view, 0, 2)

func reset_developer_zoom() -> void:
	if _developer_camera_state.is_empty(): return
	projection = _developer_camera_state.projection
	size = _developer_camera_state.size
	far = _developer_camera_state.far
	near = _developer_camera_state.near
	fov = _developer_camera_state.fov
	_developer_camera_state.clear()
	developer_zoom = 1.0
	developer_view = 0
	initialized = false

func developer_ground_rect() -> Rect2:
	# Projeta os quatro cantos da viewport no plano do foco, incluindo perspectiva
	# e órbita. A margem de altura evita que o terreno na borda da tela carregue tarde demais.
	var screen := get_viewport().get_visible_rect().size
	var bounds := Rect2(Vector2(focus.x, focus.z), Vector2.ZERO)
	for corner in [Vector2.ZERO, Vector2(screen.x, 0), screen, Vector2(0, screen.y)]:
		var origin := project_ray_origin(corner)
		var direction := project_ray_normal(corner)
		if direction.y >= -0.001: continue
		var point := origin + direction * ((focus.y - origin.y) / direction.y)
		bounds = bounds.expand(Vector2(point.x, point.z))
	return bounds.grow(96.0)

func _update_developer_camera() -> void:
	if _exterior_reveal.enabled: _exterior_reveal.release()
	_tunnel_safety.restore_environment()
	focus = target.global_position + Vector3.UP
	var span := WALK_SIZE_CLOSE * developer_zoom
	var direction := Vector3(0, 1, 0.001) if developer_view == 1 else EXTERIOR_OFFSET.normalized().rotated(Vector3.UP, heading)
	var distance := maxf(EXTERIOR_OFFSET.length(), span)
	projection = Camera3D.PROJECTION_PERSPECTIVE if developer_view == 2 else Camera3D.PROJECTION_ORTHOGONAL
	size = span
	fov = 60.0
	near = 0.1
	far = maxf(EXTERIOR_FAR, distance * 4.0 + span * 2.0)
	global_position = focus + direction.normalized() * distance
	look_at(focus)

var target: Node3D
var heading := 0.0
var _view_heading := 0.0
var _mouse_orbit := false
var _mouse_orbit_screen := Vector2.ZERO
var _mouse_orbit_previous_mode := Input.MOUSE_MODE_HIDDEN
var target_size := WALK_SIZE_CLOSE
var focus := Vector3.ZERO
var initialized := false
var locked := false:
	set(value):
		locked = value
		if value and _exterior_reveal != null: _exterior_reveal.release()
		if value: _release_exterior_depth_range()
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
# Aproximação/afastamento de portas: o enquadramento também interpola o deslocamento.
var _transition_offsets := false
var _transition_offset_from := Vector3.ZERO
var _transition_offset_to := Vector3.ZERO
var preview_view := false
var _preview_blend := 0.0
var _container_blend := 0.0
var _container_focus := Vector3.ZERO
var _building_approach_blend := 0.0
var _drive_view_blend := 0.0
var _cargo_plane_blend := 0.0
# Túnel do canal: 0 fora, 1 no fundo (cresce com a profundidade do alvo na rampa).
# Perspectiva traseira no túnel, dirigindo ou a pé; visão normal na rua.
var _tunnel_blend := 0.0
var _tunnel_chase_blend := 0.0
var _tunnel_chase_heading := 0.0
var _tunnel_chase_distance := 6.0
var _mountain_chase_active := false
var _tunnel_safety := preload("res://scripts/camera/TunnelChaseSafety.gd").new()
const TUNNEL_CHASE_FOV := 70.0
const TUNNEL_CHASE_HEIGHT := 2.4
const TUNNEL_CHASE_DISTANCE := 6.0
const EXTERIOR_FAR := 180.0
# Túnel do canal (release de 2026-10-13): a câmera em perspectiva desenhava a cidade inteira acima do
# teto até 180 m e os draw calls saltavam de ~500 para 2000-4300 (27-60 fps por ~5 s). Dentro do tubo
# o alcance cai para 75 m e uma neblina, como no túnel da serra, esconde o corte.
const CANAL_TUNNEL_FAR := 75.0
const CANAL_TUNNEL_FOG_END := 65.0
const VEHICLE_INTERIOR := preload("res://gameplay/VehicleInterior.gd")
var _chase_roof_vehicle: Node3D
const CANAL_TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
const MOUNTAIN_CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
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
var _desert_terrain_camera := preload("res://world/desert/DesertTerrainCamera.gd").new()
var _exterior_reveal := preload("res://scripts/camera/ExteriorReveal.gd").new()
var _railway_clearance := preload("res://scripts/camera/RailwayCameraClearance.gd").new()
var _building_clearance := preload("res://scripts/camera/BuildingCameraClearance.gd").new()
var _exterior_depth := preload("res://scripts/camera/ExteriorDepthRange.gd").new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cutaway.min_fades_per_frame = 3
	projection = Camera3D.PROJECTION_ORTHOGONAL
	size = target_size
	near = 0.1
	far = EXTERIOR_FAR
	current = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var settings := get_node_or_null("/root/V2Settings")
	if settings != null:
		settings.applied.connect(_read_camera_settings)
		_read_camera_settings()
	if "--camera-preview" in OS.get_cmdline_user_args(): set_preview_view(true)

func _read_camera_settings() -> void:
	var settings := get_node_or_null("/root/V2Settings")
	if settings != null:
		set_preview_view(int(settings.get("camera_view")) == 1)
		if _exterior_depth.enabled(): _exterior_depth.set_shadow_distance(settings.shadow_distance_metres())

func set_preview_view(enabled: bool) -> void:
	preview_view = enabled

func _exterior_view_offset() -> Vector3:
	# Never change authored interior offsets, target, zoom, or heading.
	if locked: return offset
	var exterior := offset.lerp(PREVIEW_OFFSET.rotated(Vector3.UP, PREVIEW_HEADING), _preview_blend)
	# Câmera de direção: aplicada antes das visões especiais (prédio, túnel, carga, contêiner),
	# que continuam mandando no enquadramento quando ativas.
	var drive_offset := DRIVE_OFFSET.lerp(PREVIEW_DRIVE_OFFSET.rotated(Vector3.UP, PREVIEW_HEADING), _preview_blend)
	exterior = exterior.lerp(drive_offset, smoothstep(0.0, 1.0, _drive_view_blend))
	# Duas entradas estreitas de prédio ficam atrás de telhados vizinhos. Eleva
	# só a vista a pé de aproximação, mantendo a direção de órbita do jogador.
	var approach_direction := Vector2(exterior.x,exterior.z).normalized()*5.0
	exterior = exterior.lerp(Vector3(approach_direction.x,35.0,approach_direction.y),_building_approach_blend)
	exterior = exterior.lerp(TUNNEL_OFFSET, smoothstep(0.0, 1.0, _tunnel_blend))
	# A asa alta cruza a visão diagonal do corredor. Elevar apenas esta área
	# conserva o avião sólido e libera a visão de Dante/carga em toda a órbita.
	exterior = exterior.lerp(Vector3(0,33.6,12.2),smoothstep(0.0,1.0,_cargo_plane_blend))
	# Um offset mínimo em Z mantém o vetor up do look_at não colinear na vista de cima.
	return exterior.lerp(Vector3(0,35,.15),_container_blend)

const _SYS_SPAN := preload("res://runtime/StallWorkTrace.gd")
## Span do sistema inteiro (22/10): quadros de 30–60 ms com o tempo em _process sem nenhum span.
func _process(delta: float) -> void:
	var span := _SYS_SPAN.begin()
	_process_traced(delta)
	_SYS_SPAN.finish_slow("sys.camera.process", span, 3000)

func _process_traced(delta: float) -> void:
	if _mouse_orbit and (_camera_input_blocked() or not Input.is_action_pressed("camera_drag")):
		_end_mouse_orbit()
	# O Dante se move em tempo real durante a habilidade da katana. Seguir/orbitar precisa usar
	# esse relógio; o resto do mundo e as câmeras que seguem veículos continuam escalados.
	if not locked and is_instance_valid(target) and target.has_meta("katana_rage_speed"):
		delta *= float(target.get_meta("katana_rage_speed", 1.0))
	if not get_tree().paused:
		_building_approach_blend = move_toward(_building_approach_blend,1.0 if has_meta("harbor_building_approach") and not locked else 0.0,maxf(0,delta)/.45)
		_cargo_plane_blend = move_toward(_cargo_plane_blend,1.0 if has_meta("cargo_plane_view") and not locked else 0.0,maxf(0,delta)/.45)
		_drive_view_blend = move_toward(_drive_view_blend,1.0 if _is_vehicle_target() and not locked else 0.0,maxf(0,delta)/DRIVE_VIEW_BLEND_SECONDS)
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
	if get_tree().paused: return
	if not _developer_camera_state.is_empty() and is_instance_valid(target):
		_update_developer_camera()
		return
	if _store_focus_active:
		if _exterior_reveal.enabled: _exterior_reveal.release()
		_tunnel_safety.restore_environment()
		_store_focus_elapsed = minf(_store_focus_duration, _store_focus_elapsed + maxf(delta, 0.0))
		var t := _store_focus_elapsed / _store_focus_duration
		var eased := t * t * (3.0 - 2.0 * t)
		focus = _store_focus_from.lerp(_store_focus_to, eased)
		size = lerpf(_store_size_from, _store_size_to, eased)
		var start_offset: Vector3 = STORE_FOCUS_OFFSET if _store_focus_reverse else _exterior_view_offset()
		var end_offset: Vector3 = _exterior_view_offset() if _store_focus_reverse else STORE_FOCUS_OFFSET
		if _transition_offsets:
			start_offset = _transition_offset_from
			end_offset = _transition_offset_to
		global_position = focus + start_offset.lerp(end_offset, eased).rotated(Vector3.UP, heading)
		look_at(focus)
		return
	if not is_instance_valid(target):
		_release_exterior_depth_range()
		if _exterior_reveal.enabled: _exterior_reveal.release()
		_tunnel_safety.restore_environment()
		return
	delta = maxf(delta,0.0) if is_finite(delta) else 0.0
	_update_gamepad_rotation(delta)
	var target_changed := _track_target()
	var actual := target.global_position
	var interpolated := target.get_global_transform_interpolated().origin
	var teleported := actual.distance_to(interpolated) > TARGET_TELEPORT_DISTANCE
	var base := actual if teleported or locked else interpolated
	var snap := not initialized or teleported or locked != _was_locked
	_view_heading = heading if snap or _mouse_orbit else lerp_angle(_view_heading, heading, 1.0 - exp(-ORBIT_FOLLOW_RATE * delta))
	# Degraus pequenos de calçamento não podem sacudir a rua inteira na vertical. Mantém
	# o acompanhamento horizontal imediato e preserva snaps/enquadramento travado de interior.
	if not snap and not target_changed and not locked and target is CharacterBody3D and not _is_vehicle_target():
		base.y = lerpf(focus.y - _smoothed_lead.y, base.y, 1.0 - exp(-HEIGHT_FOLLOW_RATE * delta))
	if target_changed:
		if initialized and not snap and focus.distance_to(base) <= TARGET_TELEPORT_DISTANCE:
			# A V1 passava o centro antigo da tela para a câmera do novo ator. Mantém esse
			# centro ao embarcar/sair de um veículo próximo e depois converge para a antecipação.
			_smoothed_lead = focus-base
		else:
			_smoothed_lead = Vector3.ZERO
	var desired_lead := Vector3.ZERO if locked else _desired_lead(base,scoped)
	if snap:
		_smoothed_lead = desired_lead if not locked else Vector3.ZERO
	else:
		var aiming_camera := scoped or _manual_aim_active()
		_smoothed_lead = _smoothed_lead.lerp(desired_lead,1.0-exp(-(AIM_FOLLOW_RATE if aiming_camera else FOLLOW_RATE)*delta))
	# A interpolação de física já suaviza o próprio ator. Só a antecipação é
	# amortecida, como na V1, evitando um segundo rastro do alvo inteiro.
	focus = base+_smoothed_lead
	if not locked and _container_blend > 0:
		focus = focus.lerp(_container_focus,_container_blend)
	initialized = true
	var base_size := _base_size()
	# A revelação local da ponte expõe a borda de rocha e a fenda funda dos dois lados.
	# Preserva enquadramento explícito de revisão/usuário, travas de interior e a proporção normal do escopo.
	if not locked and _external_size_target_id==0:
		base_size=lerpf(base_size,maxf(base_size,SMUGGLER_CANYON.CAMERA_SIZE),SMUGGLER_CANYON.camera_weight(actual))
	var desired_size := base_size*SCOPE_SIZE_MULTIPLIER if scoped else base_size
	if not locked: desired_size *= float(get_meta("port_container_zoom",1.0))
	var tunnel_depth := 0.0
	if not locked and CANAL_TUNNEL.in_roadway(actual):
		tunnel_depth = smoothstep(TUNNEL_DEPTH_START, TUNNEL_DEPTH_FULL, -actual.y)
	_tunnel_blend = move_toward(_tunnel_blend, tunnel_depth, delta * TUNNEL_BLEND_RATE)
	if _tunnel_blend > 0.0: desired_size *= lerpf(1.0, TUNNEL_ZOOM, smoothstep(0.0, 1.0, _tunnel_blend))
	if snap or locked:
		size = desired_size
	else:
		size = lerpf(size,desired_size,1.0-exp(-(AIM_FOLLOW_RATE if scoped else FOLLOW_RATE)*delta))
	var exterior_offset := _exterior_view_offset().rotated(Vector3.UP, _view_heading)
	var falling: bool = target is CharacterBody3D and target.velocity.y < -1.0 and not target.is_on_floor()
	exterior_offset = _desert_terrain_camera.offset_for(focus,exterior_offset,delta,snap,not locked and _tunnel_blend<.001,Vector2(size*get_viewport().get_visible_rect().size.aspect(),size),near,actual,3.4 if _is_vehicle_target() else .8,_flat_velocity(),falling)
	global_position = focus + exterior_offset
	look_at(focus)
	_update_tunnel_chase(actual, delta, snap)
	var exterior_retreat := 0.0
	if not locked and projection==Camera3D.PROJECTION_ORTHOGONAL and _tunnel_chase_blend<=.001:
		var nominal := global_position-focus
		var view := Vector2(size*get_viewport().get_visible_rect().size.aspect(),size)
		var safe := _railway_clearance.offset_for(focus,nominal,view,near,delta)
		safe = _building_clearance.offset_for(get_world_3d().direct_space_state,focus,safe,view,near,delta)
		# Mover no eixo ortográfico muda só a profundidade. Mantém o plano distante
		# original no espaço do mundo enquanto abre espaço para pontes em primeiro plano.
		global_position=focus+safe
		exterior_retreat=maxf(0.0,safe.length()-nominal.length())
		if not _exterior_depth.enabled(): far=EXTERIOR_FAR+exterior_retreat
	# look_at zera esta base a cada quadro; a pequena rolagem nunca acumula.
	var alcohol_roll := float(get_meta("alcohol_intensity",0.0)) * float(get_meta("alcohol_sway",0.0)) * .016
	if not is_zero_approx(alcohol_roll): rotate_object_local(Vector3.FORWARD,alcohol_roll)
	if _exterior_depth.enabled(): _update_exterior_depth_range(exterior_retreat)
	# A transparência exterior é só diagnóstico; o jogo normal mantém a silhueta.
	# A visibilidade escrita de túnel/interior ainda cuida do próprio recorte independente.
	if _exterior_reveal.enabled:
		_exterior_reveal.update(self,target,_is_vehicle_target(),_flat_velocity(),delta,not locked and _tunnel_blend < .001 and _tunnel_chase_blend < .001 and projection == Camera3D.PROJECTION_ORTHOGONAL and not get_tree().paused)
	_update_cutaway()
	_was_locked = locked

func _update_exterior_depth_range(extra_retreat: float) -> void:
	# A perspectiva mantém seu próprio far/névoa; sua luz precisa recuperar as frações originais.
	if locked or projection != Camera3D.PROJECTION_ORTHOGONAL or _tunnel_chase_blend > .001:
		_exterior_depth.release()
		return
	var world := get_parent()
	var production: Variant = world.get("production") if world != null and "production" in world else null
	var region: Variant = production.get("region") if is_instance_valid(production) and "region" in production else null
	var sun: DirectionalLight3D = production.get("sun") as DirectionalLight3D if is_instance_valid(production) and "sun" in production else null
	var next_far := EXTERIOR_FAR + extra_retreat
	if current and is_instance_valid(region) and "region_id" in region and region.get("region_id") == "harbor":
		next_far = _exterior_depth.apply(self, focus, extra_retreat, sun)
	else:
		_exterior_depth.release()
	if not is_equal_approx(far, next_far): far = next_far

func _release_exterior_depth_range() -> void:
	if _exterior_depth == null or not _exterior_depth.active: return
	var previous_far: float = _exterior_depth.legacy_far
	_exterior_depth.release()
	if not is_equal_approx(far, previous_far): far = previous_far

func reflection_far() -> float:
	return _exterior_depth.reflection_far(far)

func exterior_depth_snapshot() -> Dictionary:
	return _exterior_depth.snapshot(self)

## Perspectiva atrás do veículo ou personagem; a rua conserva seu enquadramento.
func _update_tunnel_chase(actual: Vector3, delta: float, snap: bool) -> void:
	var vehicle := _is_vehicle_target() and not locked and _container_blend < 0.001
	var actor_visual: Node3D = target.get("visual") if not _is_vehicle_target() and &"visual" in target else null
	var pedestrian := is_instance_valid(actor_visual) and not locked and _container_blend < 0.001
	var mountain_weight := MOUNTAIN_CONNECTION.tunnel_camera_weight(actual)
	var desired := maxf(_tunnel_blend,mountain_weight) if vehicle or pedestrian else 0.0
	if developer_chase and (vehicle or pedestrian): desired = 1.0
	_tunnel_chase_blend = move_toward(_tunnel_chase_blend, desired, delta * 2.4)
	if snap: _tunnel_chase_blend = desired
	# A solid roof cannot tolerate an overhead camera after a fast entry.
	if mountain_weight >= 1.0 and desired > 0.0: _tunnel_chase_blend = 1.0
	if locked:
		_tunnel_chase_blend = 0.0
	# Mantém a atmosfera local durante a mescla de saída, mas nunca a leva
	# para outro túnel ou um interior escrito depois de uma troca de alvo.
	var mountain_exit := actual.x >= MOUNTAIN_CONNECTION.TUNNEL_START_X-48.0 and actual.x <= MOUNTAIN_CONNECTION.TUNNEL_END_X+48.0 and absf(actual.z-MOUNTAIN_CONNECTION.CENTER_Z) < 30.0
	_mountain_chase_active = mountain_weight > 0.0 or (_mountain_chase_active and mountain_exit and desired <= .001 and _tunnel_chase_blend > .001)
	var blend := smoothstep(0.0, 1.0, _tunnel_chase_blend)
	# Ao desembarcar, conservar o carro fechado enquanto a câmera continua baixa.
	if is_instance_valid(_chase_roof_vehicle) and (locked or _container_blend > 0.001 or _tunnel_chase_blend < 0.65 or (vehicle and _chase_roof_vehicle != target)):
		VEHICLE_INTERIOR.set_low_camera_roof(_chase_roof_vehicle, false)
		_chase_roof_vehicle = null
	if vehicle and _tunnel_chase_blend > 0.8:
		VEHICLE_INTERIOR.set_low_camera_roof(target, true)
		_chase_roof_vehicle = target
	if vehicle or pedestrian:
		var facing: Node3D = target if vehicle else actor_visual
		var facing_heading := facing.get_global_transform_interpolated().basis.get_euler().y
		_tunnel_chase_heading = facing_heading if snap or blend <= 0.001 else lerp_angle(_tunnel_chase_heading, facing_heading, 1.0 - exp(-6.0 * delta))
	var distance := TUNNEL_CHASE_DISTANCE + _target_number(&"half_length", 2.3) - 2.3 if vehicle else 4.0
	_tunnel_chase_distance = distance if snap or blend <= 0.001 else lerpf(_tunnel_chase_distance, distance, 1.0 - exp(-4.2 * delta))
	if blend <= 0.001:
		projection = Camera3D.PROJECTION_ORTHOGONAL
		if not _exterior_depth.enabled() or locked: far = EXTERIOR_FAR
		_tunnel_safety.restore_environment()
		return
	var rear := Vector3.BACK.rotated(Vector3.UP, _tunnel_chase_heading)
	var base := target.get_global_transform_interpolated().origin
	if snap: base = actual
	var chase := base + rear * _tunnel_chase_distance + Vector3.UP * (TUNNEL_CHASE_HEIGHT if vehicle else 2.2)
	# A rampa sobe atrás do carro. Não deixar a lente abaixo do piso nem no teto.
	if not developer_chase or CANAL_TUNNEL.in_roadway(actual):
		chase.y = maxf(chase.y, CANAL_TUNNEL.floor_y(chase.x) + 1.6)
		var ceiling := CANAL_TUNNEL.ceiling_y(chase.x)
		if is_finite(ceiling): chase.y = minf(chase.y, ceiling - 0.4)
	var eye := base + Vector3.UP * 1.3
	var street_position := global_position
	var street_fov := rad_to_deg(2.0 * atan(size * 0.5 / maxf(0.1, street_position.distance_to(focus))))
	projection = Camera3D.PROJECTION_PERSPECTIVE
	fov = lerpf(street_fov, TUNNEL_CHASE_FOV, blend)
	var candidate := street_position.lerp(chase, blend)
	if _mountain_chase_active:
		# Uma lança pode passar acima do trilho baixo e ainda pô-lo na frente do Dante e
		# da moto dele. Mantém a vista baixa do lado do pedestre.
		var limit := MOUNTAIN_CONNECTION.TUNNEL_CLEAR_HALF_WIDTH - .4
		var corridor_z := clampf(candidate.z, MOUNTAIN_CONNECTION.CENTER_Z-limit, MOUNTAIN_CONNECTION.CENTER_Z+limit)
		candidate.z = lerpf(candidate.z, corridor_z, smoothstep(.2, .65, blend))
	# Protege a pose FINAL interpolada, incluindo o volume da lente: checar
	# só o ponto final da perseguição deixava a mescla rua-túnel atravessar sólidos.
	global_position = _tunnel_safety.solve(self, target, eye, candidate)
	var boom_fraction := clampf((global_position-base).dot(rear)/maxf(_tunnel_chase_distance,.1),0.0,1.0)
	look_at(focus.lerp(eye - rear * (3.0 if vehicle else 1.4) * boom_fraction, blend))
	if _mountain_chase_active:
		far = EXTERIOR_FAR
		_tunnel_safety.update_environment(self, _tunnel_chase_blend, delta, actual)
	else:
		# Só o túnel do canal: `_tunnel_blend` sobe com a profundidade do alvo na vala dele.
		var canal := minf(_tunnel_chase_blend, _tunnel_blend)
		far = lerpf(EXTERIOR_FAR, CANAL_TUNNEL_FAR, smoothstep(.5, 1.0, canal))
		_tunnel_safety.update_environment(self, canal, delta, actual, CANAL_TUNNEL_FOG_END)

## Apaga a cidade entre a câmera e o tubo enquanto o alvo está fundo no túnel.
func _update_cutaway() -> void:
	var strength := clampf((_tunnel_blend - TUNNEL_CUTAWAY_START) / (1.0 - TUNNEL_CUTAWAY_START), 0.0, 1.0)
	# No interior do tubo a lente já está sob o teto: restaurar sua profundidade.
	strength *= 1.0 - smoothstep(0.65, 1.0, _tunnel_chase_blend)
	CANAL_TUNNEL.set_camera_reveal(smoothstep(0.0, 1.0, strength))
	var aspect := get_viewport().get_visible_rect().size.aspect() if is_inside_tree() else 1.78
	# Meia largura visível + folga: quem entra na janela já está apagado antes de aparecer.
	var half_width := size * aspect * 0.5 + 16.0
	var chunks: Array = []
	# Já na rampa (antes de o corte começar) os chunks entram só para aquecer o cache de caixas.
	if strength > 0.0 or _tunnel_blend > 0.0:
		var world := get_parent()
		var production: Variant = world.get("production") if world != null else null
		var regions: Variant = production.get("regions") if production is Node else null
		var harbor: Variant = regions.get("harbor") if regions is Dictionary else null
		if harbor is Node and is_instance_valid(harbor):
			# Só os chunks sob a janela do túnel (e a faixa ao sul que a varredura alcança).
			var reach := Rect2(focus.x - half_width, CANAL_TUNNEL.outer_north() - 4.0, half_width * 2.0, CANAL_TUNNEL.outer_south() - CANAL_TUNNEL.outer_north() + 40.0)
			for key in harbor.chunks:
				if Rect2(Vector2(key) * harbor.CELL, Vector2.ONE * harbor.CELL).intersects(reach): chunks.append(harbor.chunks[key])
	if strength <= 0.0 and not chunks.is_empty(): _cutaway.prewarm(chunks)
	_cutaway.update(chunks, focus, global_position - focus, half_width, smoothstep(0.0, 1.0, strength), get_process_delta_time())

func focus_on_store(point: Vector3, final_size: float, duration: float) -> void:
	_release_exterior_depth_range()
	_store_focus_reverse = false
	_transition_offsets = false
	_store_focus_from = focus if initialized else (target.global_position if is_instance_valid(target) else point)
	_store_focus_to = point
	_store_size_from = size
	_store_size_to = maxf(1.0, final_size)
	_store_focus_elapsed = 0.0
	_store_focus_duration = maxf(0.01, duration)
	_store_focus_active = true

## Aproxima a câmera de `point` indo também para `final_offset` (porta de um lugar).
func focus_on_transition(point: Vector3, final_size: float, final_offset: Vector3, duration: float) -> void:
	var from_offset := (global_position - focus).rotated(Vector3.UP, -heading)
	focus_on_store(point, final_size, duration)
	_transition_offsets = true
	_transition_offset_from = from_offset
	_transition_offset_to = final_offset

## Começa fechado em `point` e abre até o enquadramento externo `final_size`.
func reveal_exterior(point: Vector3, close_size: float, final_size: float, duration: float) -> void:
	focus = point
	size = maxf(1.0, close_size)
	var exterior := _exterior_view_offset()
	global_position = focus + exterior.rotated(Vector3.UP, heading)
	look_at(focus)
	initialized = true
	focus_on_transition(point, final_size, exterior, duration)

func zoom_out_from_store(point: Vector3, close_size: float, duration: float) -> void:
	_transition_offsets = false
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
	# Ferramentas de captura/revisão definem target_size direto. Respeita esse valor explícito
	# para o alvo atual sem desligar o enquadramento automático produtivo.
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
	# A câmera de veículo da V1 abre a partir da vista de pedestre. O ator nativo
	# precisa de uma adaptação de escala aparente, então uma troca parada pode manter o
	# quadro atual, mas nunca apertá-lo.
	return maxf(WALK_SIZE_CLOSE,size_for_v1_zoom(zoom)) * DRIVE_VIEW_SIZE_SCALE

func _desired_lead(base: Vector3,scoped: bool) -> Vector3:
	if not _is_vehicle_target() and (scoped or _manual_aim_active()):
		var controls := get_node_or_null("/root/GameInput")
		if controls != null and not controls.using_gamepad and not controls.get_meta("touch_controls_active", false) and controls.touch_aim.is_zero_approx():
			return mouse_aim_lead(base, scoped, aim_screen_position())
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

func _manual_aim_active() -> bool:
	var combat := _gameplay()
	return combat != null and combat.has_method("aim_feedback_active") and combat.aim_feedback_active()

## Subtrair o raio central cancela a translação. Seguir o próprio aim_point
## dava ao escopo ganho de realimentação unitário: um cursor parado o empurrava para longe.
func mouse_aim_lead(base: Vector3, scoped: bool, screen: Vector2) -> Vector3:
	var rect := get_viewport().get_visible_rect()
	var cursor := screen.clamp(rect.position, rect.end)
	var plane := Plane(Vector3.UP, base.y + 1.0)
	var centre: Variant = plane.intersects_ray(project_ray_origin(rect.get_center()), project_ray_normal(rect.get_center()))
	var point: Variant = plane.intersects_ray(project_ray_origin(cursor), project_ray_normal(cursor))
	if not centre is Vector3 or not point is Vector3: return Vector3.ZERO
	var lead: Vector3 = point - centre
	lead.y = 0.0
	return (lead * (0.75 if scoped else 0.3)).limit_length(V1_SCOPE_LEAD if scoped else 3.5)

func aim_screen_position() -> Vector2:
	return _mouse_orbit_screen if _mouse_orbit else get_viewport().get_mouse_position()

func mouse_orbit_active() -> bool:
	return _mouse_orbit

func _end_mouse_orbit(restore_pointer := true) -> void:
	if not _mouse_orbit: return
	_mouse_orbit = false
	# Um menu ou outra câmera pode já ser dono do cursor. Nunca o sobrescreve.
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = _mouse_orbit_previous_mode
		if restore_pointer: get_viewport().warp_mouse(_mouse_orbit_screen)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_end_mouse_orbit(false)

func _input(event: InputEvent) -> void:
	# Soltar precisa funcionar mesmo quando controles de GUI consomem o evento correspondente.
	if _mouse_orbit and (event.is_action_pressed("aim") or event.is_action_pressed("fire")):
		_end_mouse_orbit()
	if _mouse_orbit and event.is_action_released("camera_drag"):
		_end_mouse_orbit()

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
	if _camera_input_blocked(): return false
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
	_release_exterior_depth_range()
	_end_mouse_orbit(false)
	_exterior_reveal.release()
	_tunnel_safety.restore_environment()
	if is_instance_valid(_chase_roof_vehicle): VEHICLE_INTERIOR.set_low_camera_roof(_chase_roof_vehicle, false)
	_cutaway.release()
	CANAL_TUNNEL.set_camera_reveal(0.0)
	if is_instance_valid(scope_reticle):
		scope_reticle.hide()
		scope_reticle.queue_free()

func release_exterior_reveal() -> void:
	_exterior_reveal.release()

func _camera_input_blocked() -> bool:
	if locked or _store_focus_active or get_tree().paused: return true
	var controls := get_node_or_null("/root/GameInput")
	if controls != null and controls.get("remapping") == true: return true
	var world := get_parent()
	var session: Variant = world.get("session") if world != null and &"session" in world else null
	if session != null:
		if session.get("modal") == true or session.get("ready_for_play") == false: return true
		var wheel: Variant = session.get("equipment_wheel")
		if is_instance_valid(wheel) and wheel.active: return true
		if session.has_method("is_transition_blocked") and session.is_transition_blocked(): return true
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit

func _update_gamepad_rotation(delta: float) -> void:
	var controls := get_node_or_null("/root/GameInput")
	if controls == null or not controls.has_method("camera_rotation"): return
	# Lê só ligações analógicas. Botões, teclado e ações de toque mantêm o
	# passo escrito de 45 graus em _unhandled_input, sem uma segunda atualização de quadro.
	var turn: float = controls.camera_rotation()
	if is_zero_approx(turn) or _camera_input_blocked(): return
	if _is_vehicle_target() and &"archetype" in target and target.get("archetype") == "army_tank": return
	var combat := _gameplay()
	# Esqui/skate e direção comum desligam ataques; os gatilhos continuam
	# disponíveis para olhar em volta. Mirar/atirar a pé é dono do analógico direito.
	if combat != null and combat.has_method("attack_allowed") and combat.attack_allowed():
		if Input.is_action_pressed("aim") or Input.is_action_pressed("fire"): return
	heading -= turn * GAMEPAD_ORBIT_SPEED * delta

func _unhandled_input(event: InputEvent) -> void:
	if _camera_input_blocked(): return
	if event.is_action_pressed("camera_drag") and not event.is_echo() and not Input.is_action_pressed("aim") and not Input.is_action_pressed("fire"):
		if not _mouse_orbit:
			_mouse_orbit_screen = get_viewport().get_mouse_position()
			_mouse_orbit_previous_mode = Input.mouse_mode
			_mouse_orbit = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _mouse_orbit:
		heading -= event.screen_relative.x * MOUSE_ORBIT_RADIANS_PER_PIXEL
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadMotion or not event.is_pressed() or event.is_echo(): return
	# A V1 (DynamicCamera) não tinha zoom manual: o enquadramento vem só da
	# velocidade, nitro e luneta. A roda do mouse é da troca de arma a pé e da
	# sintonia de rádio no carro, então a câmera não a consome.
	if event.is_action_pressed("camera_left"):
		heading += PI / 4
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_right"):
		heading -= PI / 4
		get_viewport().set_input_as_handled()
