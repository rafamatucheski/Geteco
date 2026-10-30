extends RefCounted
## Experimento opt-in para o export normal, cujo reveal fica desligado durante a sessão.
## Não restaura lotes já publicados: uma futura ativação em produção exige esse contrato antes de usar o gate.
## Diagnósticos são protegidos desde o boot, inclusive os que ligam o efeito só depois do streaming.
const REVEAL_GROUP := &"exterior_reveal_building"
const CENSUS_SCRIPT := "res://tests/measure/census_chunk_draws.gd"
static var enabled := OS.get_environment("GETECO_REVEAL_GUARD") == "1"
static var _contexts: Array[WeakRef] = []
static var _generation := 0
static var _census_owner: WeakRef

static func register_context(context: RefCounted) -> void:
	# Limpa instâncias antigas mesmo com o gate desligado, sem reter câmeras mortas.
	_all_disabled()
	_contexts.append(weakref(context))
	_generation += 1

static func state_changed() -> void:
	_generation += 1

## Exceção estrita para o censo: dono real, script real e argumento explícito.
## O censo ainda precisa criar e reter ExteriorReveal; este registro não inventa seu estado.
static func register_census(owner: SceneTree) -> bool:
	var script := owner.get_script() as Script
	if script == null or script.resource_path != CENSUS_SCRIPT: return false
	if "--reveal-guard-census" not in OS.get_cmdline_user_args(): return false
	if _launch_protected(OS.get_cmdline_args(), OS.get_cmdline_user_args(), true): return false
	_census_owner = weakref(owner)
	_generation += 1
	return true

static func capture() -> int:
	if not enabled: return -1
	var census := _census_owner != null and is_instance_valid(_census_owner.get_ref())
	return _capture(OS.get_cmdline_args(), OS.get_cmdline_user_args(), census)

## Argumentos explícitos permitem testar a política sem abrir outra instância do motor.
static func _capture(engine_args: PackedStringArray, user_args: PackedStringArray, census: bool) -> int:
	if not enabled or Engine.is_editor_hint() or _launch_protected(engine_args, user_args, census): return -1
	if not _all_disabled(): return -1
	return _generation

static func still_allowed(generation: int) -> bool:
	# Setter, registro e NOTIFICATION_PREDELETE invalidam; não varrer contextos por vértice.
	return enabled and generation >= 0 and generation == _generation

static func _all_disabled() -> bool:
	var live: Array[WeakRef] = []
	var disabled := true
	for reference in _contexts:
		var context: Object = reference.get_ref()
		if not is_instance_valid(context): continue
		live.append(reference)
		var value: Variant = context.get("enabled")
		if not value is bool or bool(value): disabled = false
	if live.size() != _contexts.size():
		_contexts = live
		_generation += 1
	return not live.is_empty() and disabled

static func _launch_protected(engine_args: PackedStringArray, user_args: PackedStringArray, census: bool) -> bool:
	# --script inclui testes que alternam reveal sem --reveal-on (measure_exterior_reveal).
	var scripts: Array[String] = []
	var index := 0
	while index < engine_args.size():
		var argument := engine_args[index]
		if argument == "--script" or argument == "-s":
			index += 1
			if index >= engine_args.size(): return true
			scripts.append(engine_args[index])
		elif argument.begins_with("--script="):
			scripts.append(argument.trim_prefix("--script="))
		index += 1
	for argument in engine_args + user_args:
		if argument.begins_with("--reveal-"):
			if not census or argument != "--reveal-guard-census": return true
	if scripts.is_empty(): return census
	if not census or scripts.size() != 1: return true
	return ProjectSettings.localize_path(scripts[0]) != CENSUS_SCRIPT

## Ignorar apenas o marcador de reveal. Qualquer outro dono público/interativo continua excluído.
## Cache pertence a uma única execução de merge/casca; nada global depende de um nó que mudou de chunk.
static func cached_scope(scope: Node, cache: Dictionary) -> bool:
	var id := scope.get_instance_id()
	if not cache.has(id): cache[id] = noninteractive_scope(scope)
	return bool(cache[id])

static func noninteractive_scope(scope: Node) -> bool:
	if not scope.is_in_group(REVEAL_GROUP) or not noninteractive_node(scope): return false
	if scope.get_node_or_null("BuildingAccess") != null: return false
	return scope.find_children("BuildingAccess", "", true, false).is_empty()

## Também protege donos intermediários entre uma caixa e o escopo relaxado da casca.
static func noninteractive_node(node: Node) -> bool:
	for group in node.get_groups():
		if group != REVEAL_GROUP and not String(group).begins_with("_"): return false
	for meta in [&"street_fragile_registered", &"interior_solid_id", &"loot_container", &"door_leaf", &"port_lootable"]:
		if node.has_meta(meta): return false
	if not str(node.get_meta("place_id", "")).is_empty(): return false
	if node is RigidBody3D or node is CharacterBody3D or node is AnimatableBody3D or node is Area3D: return false
	if node is Skeleton3D or node is BoneAttachment3D or node is AnimationPlayer or node is AnimationTree: return false
	if node is PathFollow3D or node is Camera3D: return false
	return not (node.is_processing() or node.is_physics_processing() or node.is_processing_input() or node.is_processing_unhandled_input())
