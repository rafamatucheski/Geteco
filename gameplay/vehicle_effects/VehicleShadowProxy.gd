extends RefCounted
## Experimento local ao processo, sem rotina por quadro, leitura de malha, colisão ou luz.
## Substitui somente o Body intacto e fechado dos perfis permitidos. Dano e mudanças
## de topologia invalidam imediatamente; só um reparo concluído permite tentar novamente.
const HULL := preload("res://gameplay/vehicle_effects/VehicleShadowHull.gd")
const TRACE := preload("res://runtime/StallWorkTrace.gd")
const GUARDS := preload("res://gameplay/emergency/EffectsPrewarm.gd")
static var enabled := OS.get_environment("GETECO_CAR_SHADOW_PROXY") == "1"
static var prewarmed := false
static var _pending: Array[WeakRef] = []
static var installed_total := 0
static var removed_total := 0
static var original_surfaces_replaced_total := 0
static var _active: Dictionary = {} # ID do helper -> WeakRef; eventos de árvore, sem consulta por quadro.
static var _requests_by_profile: Dictionary = {}
static var _refusals_by_profile: Dictionary = {}
static var _deferred_by_profile: Dictionary = {}
var _vehicle: WeakRef
var _source: WeakRef
var _proxy: WeakRef
var _original_cast := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
var _blocked := false
var _queued := false
var _archetype := ""
var _surface_count := 0
var _refusal_noted: Dictionary = {}

static func supports(archetype: String) -> bool:
	return HULL.supports(archetype)

static func offer(archetype: String) -> bool:
	_requests_by_profile[archetype] = int(_requests_by_profile.get(archetype,0)) + 1
	if supports(archetype): return true
	_note_refusal(archetype, "unsupported_profile")
	return false

func configure(vehicle: Node3D) -> void:
	_vehicle = weakref(vehicle)
	_archetype = str(vehicle.get("archetype"))
	request()

func request() -> void:
	if not enabled or _blocked or active() or _candidate() == null: return
	if not prewarmed:
		if not _queued:
			_pending.append(weakref(self))
			_queued = true
			_deferred_by_profile[_archetype] = int(_deferred_by_profile.get(_archetype,0)) + 1
		return
	_install()

func active() -> bool:
	return _proxy != null and is_instance_valid(_proxy.get_ref())

func invalidate() -> void:
	_blocked = true
	if not active(): return
	var began := TRACE.begin()
	var proxy := _proxy.get_ref() as MeshInstance3D
	# Retira da árvore agora: dano, portas, explosões e limites da carcaça podem
	# percorrer os filhos nesta mesma chamada. Só ocultar/queue_free seria tarde.
	if proxy.get_parent() != null: proxy.get_parent().remove_child(proxy)
	proxy.free()
	_proxy = null
	var source := _source.get_ref() as MeshInstance3D if _source != null else null
	if is_instance_valid(source) and source.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		source.cast_shadow = _original_cast
	_source = null
	removed_total += 1
	TRACE.finish("vehicle.shadow_proxy.remove", began)

func repair_completed() -> void:
	# Portas preparadas e tuning persistem após reparo e _candidate os recusa.
	# Limpar a trava não restaura geometria ausente nem reabre um teto.
	_blocked = false
	request()

func _candidate() -> MeshInstance3D:
	var car := _vehicle.get_ref() as Node3D if _vehicle != null else null
	if not is_instance_valid(car) or not car.is_inside_tree() or car.is_queued_for_deletion(): return _reject("not_live")
	var archetype := str(car.get("archetype"))
	if not supports(archetype): return _reject("unsupported_profile")
	var health := float(car.get("health"))
	var maximum := float(car.get("max_health"))
	if not is_finite(health) or not is_finite(maximum) or maximum <= 0.0 or health < maximum: return _reject("damaged")
	if is_instance_valid(car.get("door_presentation")): return _reject("prepared_doors")
	if is_instance_valid(car.get("breakaway_parts")): return _reject("breakaway")
	if car.has_meta("tuning_appearance") or car.has_meta("interior_view") or car.has_meta("heavy_crush_ratio"): return _reject("modified_body")
	var visual := car.get("visual") as Node3D
	if not is_instance_valid(visual) or visual.get_meta("fleet_redesign_version",0) != 1: return _reject("unsupported_model")
	if visual.get_meta("breakaway_geometry_version",0) != 0 or visual.has_node("Interior"): return _reject("modified_body")
	var dents: Variant = car.get("body_dents")
	if is_instance_valid(dents) and not (dents.get("dents") as Array).is_empty(): return _reject("dents")
	var body := visual.get_node_or_null("Body") as MeshInstance3D
	if body == null or body.mesh == null or not body.visible or body.is_queued_for_deletion(): return _reject("missing_body")
	if not body.transform.is_finite() or not visual.transform.is_finite(): return _reject("invalid_transform")
	if body.basis.determinant() <= 0.0 or visual.basis.determinant() <= 0.0: return _reject("invalid_transform")
	# Um modo de sombra incomum é intencional. Este primeiro experimento conserva
	# esses casos sem alterar o contrato de faces ou visibilidade da fonte.
	if body.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON or body.transparency > 0.0: return _reject("source_shadow_mode")
	if body.has_meta("breakaway_part_id") or body.has_meta("body_dents_rest_mesh"): return _reject("modified_body")
	if body.mesh.get_surface_count() < 2 or not HULL.accepts_bounds(archetype, body.get_aabb()): return _reject("profile_bounds_mismatch")
	return body

func _reject(reason: String) -> MeshInstance3D:
	if not _refusal_noted.has(reason):
		_refusal_noted[reason] = true
		_note_refusal(_archetype, reason)
	return null

static func _note_refusal(archetype: String, reason: String) -> void:
	if not _refusals_by_profile.has(archetype): _refusals_by_profile[archetype] = {}
	var reasons: Dictionary = _refusals_by_profile[archetype]
	reasons[reason] = int(reasons.get(reason,0)) + 1

func _install() -> void:
	var began := TRACE.begin()
	var source := _candidate()
	if source == null:
		TRACE.finish("vehicle.shadow_proxy.install", began)
		return
	var car := _vehicle.get_ref() as Node3D
	var mesh := HULL.mesh_for(str(car.get("archetype")))
	if mesh == null:
		TRACE.finish("vehicle.shadow_proxy.install", began)
		return
	var proxy := _new_caster(mesh)
	proxy.layers = source.layers
	proxy.set_meta("vehicle_shadow_proxy_profile", _archetype)
	proxy.tree_entered.connect(_proxy_entered)
	proxy.tree_exiting.connect(_proxy_exiting)
	# Filho do Body: herda visibilidade e transformações de recuo/retirada sem
	# copiar poses a cada quadro.
	source.add_child(proxy)
	_original_cast = source.cast_shadow
	_source = weakref(source)
	_proxy = weakref(proxy)
	_surface_count = source.mesh.get_surface_count()
	original_surfaces_replaced_total += _surface_count
	source.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	installed_total += 1
	TRACE.finish("vehicle.shadow_proxy.install", began)

func _proxy_entered() -> void:
	_active[get_instance_id()] = weakref(self)

func _proxy_exiting() -> void:
	_active.erase(get_instance_id())

static func _new_caster(mesh: ArrayMesh) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = "VehicleShadowProxy"
	part.mesh = mesh
	part.material_override = HULL.material()
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	part.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	part.set_meta("vehicle_shadow_proxy", true)
	part.set_meta("door_cut_exempt", true)
	return part

## Reutiliza as três células/luzes de LocalLightShadowPrewarm. A mesma malha,
## material e formato de vértices ficam retidos em HULL após liberar a peça temporária.
static func add_prewarm_caster(cell: Node3D, index: int) -> bool:
	if not enabled: return false
	var archetype: String = HULL.PROFILE_IDS[index % HULL.PROFILE_IDS.size()]
	var caster := _new_caster(HULL.mesh_for(archetype))
	# Célula existente: receptor z=0 e luz z=1,4. O casco inteiro cabe entre eles.
	caster.scale = Vector3.ONE * .10
	caster.position = Vector3(0, -.08, .55)
	cell.add_child(caster)
	return true

static func finish_prewarm(host: Node3D, curtain: CanvasLayer, completed: bool) -> void:
	if not enabled or not completed or not GUARDS._covered_loading(host, curtain): return
	prewarmed = true
	var tree := host.get_tree()
	var slice_start := Time.get_ticks_usec()
	# Sem consultas por quadro depois da carga. Referências fracas deixam passar
	# carros removidos/helpers invalidados. A instalação é fatiada a cada 2 ms.
	while not _pending.is_empty():
		if not GUARDS._covered_loading(host, curtain): break
		var pending := _pending.pop_back() as WeakRef
		var state = pending.get_ref()
		if is_instance_valid(state):
			state._queued = false
			state.request()
		if Time.get_ticks_usec() - slice_start >= 2000:
			await tree.process_frame
			slice_start = Time.get_ticks_usec()
	# Se a cortina saiu antes da hora, mantém essas fontes originais. Um reparo
	# pode pedir novamente; a fila pendente não é instalada durante a partida.
	for pending in _pending:
		var state = pending.get_ref()
		if is_instance_valid(state): state._queued = false
	_pending.clear()

static func summary() -> Dictionary:
	return snapshot()

## Só diagnóstico: visita helpers registrados, sem percorrer a frota/árvore de cena.
## Totais por processo; ativos acompanham a árvore e toleram carros já liberados.
static func snapshot() -> Dictionary:
	var active_by_profile := {}
	var originals := 0
	var active_count := 0
	for key in _active.keys():
		var state = (_active[key] as WeakRef).get_ref()
		if not is_instance_valid(state) or not state.active():
			_active.erase(key)
			continue
		active_count += 1
		originals += int(state._surface_count)
		active_by_profile[state._archetype] = int(active_by_profile.get(state._archetype,0)) + 1
	var waiting := {}
	for reference in _pending:
		var state = reference.get_ref()
		if not is_instance_valid(state) or state._blocked or state.active(): continue
		waiting[state._archetype] = int(waiting.get(state._archetype,0)) + 1
	return {"enabled":enabled, "prewarmed":prewarmed, "active_proxies":active_count,
		"installed_total":installed_total, "removed_total":removed_total,
		"original_meshes_replaced_total":installed_total, "original_surfaces_replaced_total":original_surfaces_replaced_total,
		"active_original_surfaces":originals, "active_proxy_surfaces":active_count,
		"active_by_profile":active_by_profile, "requests_by_profile":_requests_by_profile.duplicate(true),
		"refusals_by_profile":_refusals_by_profile.duplicate(true),
		"deferred_until_prewarm_by_profile":_deferred_by_profile.duplicate(true), "waiting_for_prewarm_by_profile":waiting}
