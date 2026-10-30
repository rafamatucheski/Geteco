extends RefCounted
## Experimento de 29/10: o Godot 4.7.2 ignora shadow_max_distance em câmera ortográfica
## (renderer_scene_cull.cpp:1965). 0 conserva os 180 m; 120 é o primeiro candidato A/B,
## ainda sem medição. O plano distante também corta geometria, por isso o chão manda.
## "settings" usa os 40/55/80 m do jogador como reserva depois do foco, só no Harbor.
const LEGACY_FAR := 180.0
const HARBOR_MIN_Y := -12.0 # Pilares da ponte chegam a -8,94 m; não estender à serra/deserto.
const DEPTH_MARGIN := 4.0
const MIN_DOWNWARD_AXIS := .05

var mode := "off"
var requested_far := 0.0
var settings_distance := 55.0
var active := false
var legacy_far := LEGACY_FAR
var floor_far := 0.0
var retreat := 0.0
var _sun: DirectionalLight3D
var _original_shadow := Vector4.ZERO

func _init() -> void:
	configure_request(OS.get_environment("GETECO_CAMERA_FAR"))

func configure_request(value: String) -> void:
	release()
	mode = "off"
	requested_far = 0.0
	var text := value.strip_edges().to_lower()
	if text == "settings":
		mode = "settings"
	elif text.is_valid_float():
		var metres := text.to_float()
		if is_finite(metres) and metres > 0.0:
			mode = "fixed"
			requested_far = minf(metres, LEGACY_FAR)

func enabled() -> bool:
	return mode != "off"

func set_shadow_distance(metres: float) -> void:
	if is_finite(metres) and metres > 0.0: settings_distance = metres

## Câmera FINAL: inclui recuo ferroviário/prédio e o roll. Não somar o recuo outra vez.
## O suporte vertical dos quatro cantos protege todo o plano em y_min, sem raycasts.
static func minimum_far(pose: Transform3D, view: Vector2, y_min := HARBOR_MIN_Y) -> float:
	if not pose.is_finite() or not view.is_finite() or not is_finite(y_min): return INF
	if view.x <= 0.0 or view.y <= 0.0 or pose.basis.z.y <= MIN_DOWNWARD_AXIS: return INF
	var vertical_extent := (absf(pose.basis.x.y) * view.x + absf(pose.basis.y.y) * view.y) * .5
	return maxf(0.0, (pose.origin.y - y_min + vertical_extent) / pose.basis.z.y) + DEPTH_MARGIN

static func choose_far(request: float, extra_retreat: float, protected_far: float) -> float:
	var extra := maxf(0.0, extra_retreat) if is_finite(extra_retreat) else 0.0
	var previous := LEGACY_FAR + extra
	if not is_finite(request) or request <= 0.0 or not is_finite(protected_far): return previous
	# Se o piso pede mais que o alcance antigo, recusar a redução; não ampliar a cena no A/B.
	return minf(previous, maxf(request + extra, protected_far))

## Frações antigas expressas na faixa curta, com a mesma profundidade útil depois do recuo.
static func shadow_fraction(value: float, near_clip: float, far_clip: float, extra_retreat: float, maximum: float) -> float:
	return clampf((value * (LEGACY_FAR - near_clip) + extra_retreat) / maxf(.001, far_clip - near_clip), .001, maximum)

func apply(camera: Camera3D, focus: Vector3, extra_retreat: float, sun: DirectionalLight3D) -> float:
	retreat = maxf(0.0, extra_retreat) if is_finite(extra_retreat) else 0.0
	legacy_far = LEGACY_FAR + retreat
	if not enabled() or not is_instance_valid(camera) or not is_instance_valid(sun):
		release()
		return legacy_far
	if camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
		release()
		return legacy_far
	var half_extents := camera.get_camera_projection().get_viewport_half_extents()
	floor_far = minimum_far(camera.global_transform, half_extents * 2.0)
	var request := requested_far
	if mode == "settings":
		# A preferência permanece 40/55/80 na perspectiva; na ortográfica reserva mundo após o foco.
		request = maxf(0.0, camera.global_position.distance_to(focus) - retreat) + settings_distance
	var result := choose_far(request, retreat, floor_far)
	if result >= legacy_far - .001:
		release()
		return legacy_far
	if sun != _sun:
		release()
		_sun = sun
		_original_shadow = Vector4(sun.directional_shadow_split_1, sun.directional_shadow_split_2,
			sun.directional_shadow_split_3, sun.directional_shadow_fade_start)
	active = true
	# O fade .4 começaria a 48 m com far120. Conservar o começo a ~72 m evita apagar a rua.
	_write_shadow(Vector4(
		shadow_fraction(_original_shadow.x, camera.near, result, retreat, .97),
		shadow_fraction(_original_shadow.y, camera.near, result, retreat, .98),
		shadow_fraction(_original_shadow.z, camera.near, result, retreat, .99),
		clampf((_original_shadow.w * LEGACY_FAR + retreat) / result, .001, .99)))
	return result

func release() -> void:
	if active and is_instance_valid(_sun): _write_shadow(_original_shadow)
	active = false
	_sun = null

func reflection_far(current_far: float) -> float:
	# O volume espelhado olha para outra altura; o piso do enquadramento principal não o protege.
	return legacy_far if active else current_far

func _write_shadow(values: Vector4) -> void:
	if not is_equal_approx(_sun.directional_shadow_split_1, values.x): _sun.directional_shadow_split_1 = values.x
	if not is_equal_approx(_sun.directional_shadow_split_2, values.y): _sun.directional_shadow_split_2 = values.y
	if not is_equal_approx(_sun.directional_shadow_split_3, values.z): _sun.directional_shadow_split_3 = values.z
	if not is_equal_approx(_sun.directional_shadow_fade_start, values.w): _sun.directional_shadow_fade_start = values.w

func snapshot(camera: Camera3D) -> Dictionary:
	# Só diagnóstico sob demanda; nenhum Dictionary é criado no laço de atualização.
	return {"mode": mode, "requested_m": requested_far, "settings_m": settings_distance,
		"active": active, "far_m": camera.far, "legacy_far_m": legacy_far,
		"floor_m": floor_far, "minimum_world_y": HARBOR_MIN_Y, "retreat_m": retreat,
		"near_m": camera.near, "projection": camera.projection, "size_m": camera.size}
