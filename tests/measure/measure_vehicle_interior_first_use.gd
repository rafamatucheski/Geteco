extends "res://tests/measure/measure_performance_plan.gd"
## Diagnóstico dirigido de primeiro uso. O Main é renderizado, mas o process mode dele é desligado
## depois do início/assentamento normais. Estas estatísticas de quadro NÃO são FPS de jogo.
## Rode em processos novos com interior-control, interior-trigger ou interior-stages
## e HARBOR_PLAN_WARMUP_IDENTITY=1. Nunca limpa caches de recursos. Todos os braços dirigidos
## usam 120 FPS para manter o observador limitado de 12,000 intervalos abaixo do limite.

const FAMILY := "union_sedan"
const VEHICLE_SOURCE := preload("res://scripts/Vehicle.gd")
const VEHICLE_ID := "diagnostic_union_interior_first_use"
const VEHICLE_POINT := Vector3(117.0, .12, 26.75539)
const FIRST_DELAY_USEC := 15000000
const SECOND_DELAY_USEC := 5000000

var subject: CharacterBody3D
var fixture_phase := "loading"
var fixture_events: Array[Dictionary] = []
var fixture_error := ""
var fixture_started := 0
var first_finished := 0
var first_requested := false
var second_requested := false
var phase_pending := false

func _cache_state() -> Dictionary:
	return {"warmed":WARMUP_SOURCE._warmed.has(FAMILY),
		"warming_owner":int(WARMUP_SOURCE._warming.get(FAMILY, 0)),
		"spec_cached":WARMUP_SOURCE._specs.has(FAMILY),
		"mesh_cached":WARMUP_SOURCE._meshes.has(FAMILY)}

func _record_event(event: String) -> void:
	var row := {"event":event,"engine_usec":Time.get_ticks_usec(),
		"process_frame":Engine.get_process_frames(),"cache":_cache_state(),
		"vehicle_id":VEHICLE_ID,"scenario":scenario}
	if is_instance_valid(subject):
		row["vehicle_instance_id"] = subject.get_instance_id()
		row["vehicle_position"] = str(subject.global_position)
	fixture_events.append(row)
	# Mantém a captura de eventos em memória: saída síncrona de console/arquivo não pode ficar
	# entre o timestamp do gatilho e a operação sendo diagnosticada.
	row["capture_usec"] = Time.get_ticks_usec()-int(row.engine_usec)

func _fail_fixture(reason: String) -> void:
	if not fixture_error.is_empty(): return
	fixture_error = reason
	fixture_phase = "invalid"
	_record_event("invalid:"+reason)
	push_error("INTERIOR_FIRST_USE_INVALID: "+reason)
	# O runner rejeita o erro explícito e também este código de saída.
	quit(7)

func settle_load() -> bool:
	if not await super.settle_load(): return false
	if scenario not in ["interior-control", "interior-trigger", "interior-stages"]:
		_fail_fixture("unknown_scenario")
		return false
	if not warmup_identity_enabled:
		_fail_fixture("identity_observer_required")
		return false
	if WARMUP_SOURCE._warmed.has(FAMILY) or WARMUP_SOURCE._warming.has(FAMILY):
		_fail_fixture("family_already_warmed_or_pending")
		return false
	# Usa a implementação de produção do Vehicle, com identidade e pintura fixadas antes do
	# _ready. ProductionWorld.spawn_vehicle atribui primeiro uma identidade derivada do relógio;
	# mudá-la depois deixaria a variação cosmética original do VehicleUsage.
	subject = VEHICLE_SOURCE.new()
	subject.archetype = FAMILY
	subject.vehicle_id = VEHICLE_ID
	subject.paint_color = Color("dde3e4")
	subject.position = VEHICLE_POINT
	subject.set_meta("region_id", world.session.state.region_id)
	world.add_child(subject)
	if not world.production.vehicle_position_clear(subject, VEHICLE_POINT, 0.0):
		_fail_fixture("fixed_spawn_position_not_clear")
		return false
	world.production.vehicles.append(subject)
	# Nenhum await entre a construção e desligar o Main: o Driving não pode selecionar o
	# alvo primeiro. O ponto fixo também fica fora do raio de seleção de 5 m dele.
	world.process_mode = Node.PROCESS_MODE_DISABLED
	Engine.max_fps = 120
	fixture_phase = "settled_frozen"
	_record_event("prepared")
	return true

func state() -> Dictionary:
	var row := super.state()
	row["interior_first_use"] = {"phase":fixture_phase,"error":fixture_error,
		"shared_materials_prepared":preload("res://gameplay/VehicleInteriorMaterialPrewarm.gd")._drawn,
		"world_process_disabled":world.process_mode == Node.PROCESS_MODE_DISABLED,
		"events":fixture_events.duplicate(true),"cache":_cache_state(),
		"scope":"Directed rendered first-use diagnostic with Main callbacks disabled and the same 120 FPS cap in all arms; not gameplay FPS. SceneTree frames and rendering remain active."}
	return row

func apply_load(now: int) -> void:
	if not fixture_error.is_empty(): return
	if identity_dropped_intervals > 0 or identity_dropped_warmups > 0:
		_fail_fixture("identity_capture_overflow")
		return
	if fixture_started == 0: fixture_started = now
	if now-fixture_started >= 29000000 and fixture_phase != "complete":
		_fail_fixture("directed_phases_incomplete")
		return
	if phase_pending: return
	if not first_requested and now-fixture_started >= FIRST_DELAY_USEC:
		first_requested = true
		_exercise_phase("first")
	elif first_finished != 0 and not second_requested and now-first_finished >= SECOND_DELAY_USEC:
		second_requested = true
		_exercise_phase("repeat")

func _exercise_phase(which: String) -> void:
	phase_pending = true
	fixture_phase = which
	if not is_instance_valid(subject) or not subject.is_inside_tree():
		_fail_fixture("subject_removed")
		return
	if which == "first" and (WARMUP_SOURCE._warmed.has(FAMILY) or WARMUP_SOURCE._warming.has(FAMILY)):
		_fail_fixture("family_changed_before_trigger")
		return
	if scenario == "interior-stages":
		if which == "first" and (WARMUP_SOURCE._specs.has(FAMILY) or WARMUP_SOURCE._meshes.has(FAMILY)):
			_fail_fixture("stage_first_spec_or_mesh_already_cached")
			return
		if which == "repeat" and (not WARMUP_SOURCE._specs.has(FAMILY) or not WARMUP_SOURCE._meshes.has(FAMILY) or WARMUP_SOURCE._warmed.has(FAMILY) or WARMUP_SOURCE._warming.has(FAMILY)):
			_fail_fixture("stage_repeat_requires_cached_geometry_and_unwarmed_family")
			return
	_record_event(which+"_begin")
	if scenario == "interior-stages" and which == "first":
		var cabin: Dictionary = WARMUP_SOURCE.spec(subject)
		if cabin.is_empty():
			_fail_fixture("stage_first_empty_spec")
			return
		var interior_mesh: ArrayMesh = WARMUP_SOURCE.mesh_for(FAMILY, cabin)
		if interior_mesh == null:
			_fail_fixture("stage_first_missing_mesh")
			return
		_record_event(which+"_sync_end")
		# Sem vidro temporário nem interior anexado: observa o trabalho adiado causado pela
		# construção normal de spec/malha nos três quadros seguintes.
		for frame in 3: await process_frame
	elif scenario == "interior-trigger" or scenario == "interior-stages":
		await WARMUP_SOURCE.prewarm(subject)
	else:
		for frame in 3: await process_frame
	_record_event(which+"_end")
	var expected_warmed := scenario == "interior-trigger" or (scenario == "interior-stages" and which == "repeat")
	if WARMUP_SOURCE._warmed.has(FAMILY) != expected_warmed or WARMUP_SOURCE._warming.has(FAMILY):
		_fail_fixture("unexpected_cache_state_after_"+which)
		return
	phase_pending = false
	if which == "first":
		first_finished = Time.get_ticks_usec()
		fixture_phase = "awaiting_repeat"
	else:
		fixture_phase = "complete"
