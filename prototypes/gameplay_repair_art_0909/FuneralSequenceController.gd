extends Node3D

## Controlador de demonstração de funeral completo com separação espacial,
## transição de estados de sepultura, sem clones repetidos e com corredor livre.
## Sinais e comandos expostos para integração limpa.

const CASKET_SCRIPT := preload("res://prototypes/gameplay_repair_art_0909/Casket3D.gd")
const GRAVE_SITE_SCRIPT := preload("res://prototypes/gameplay_repair_art_0909/GraveSiteVisual.gd")
const MOURNER_SCRIPT := preload("res://prototypes/gameplay_repair_art_0909/MournerCharacterModel.gd")

signal sequence_started()
signal procession_arrived()
signal ceremony_started()
signal lowering_started()
signal lowering_completed()
signal filling_started()
signal filling_completed()
signal dispersal_started()
signal sequence_completed()
signal sequence_cancelled()

enum Phase {
	IDLE,
	PROCESSION,
	CEREMONY_WAIT,
	LOWERING,
	FILLING,
	DISPERSAL,
	FINISHED
}

@export var ceremony_wait_time: float = 4.0
@export var walk_speed: float = 1.2
@export var speed_multiplier: float = 1.0

var current_phase: Phase = Phase.IDLE
var phase_timer: float = 0.0

# Componentes da cena
var casket: Node3D
var grave_site: Node3D
var pallbearers: Array[Node3D] = []
var visitors: Array[Node3D] = []
var gravedigger: Node3D
var active_tween: Tween

# Posições relativas de atuação (no espaço 3D da demonstração)
var plot_pos := Vector3(3.4, 0.0, 0.0)
var gate_pos := Vector3(0.0, 0.0, -8.5)
var procession_start_pos := Vector3(0.0, 0.0, -6.5)

var pallbearer_offsets := [
	Vector3(-0.62, 0.0, -0.55),
	Vector3(-0.62, 0.0,  0.55),
	Vector3( 0.62, 0.0, -0.55),
	Vector3( 0.62, 0.0,  0.55)
]

var pallbearer_standby_pos := [
	Vector3(1.9, 0.0, -1.2),
	Vector3(1.9, 0.0,  1.2),
	Vector3(4.9, 0.0, -1.2),
	Vector3(4.9, 0.0,  1.2)
]

var visitor_standby_pos := [
	Vector3(2.3, 0.0, -2.4),
	Vector3(3.4, 0.0, -2.7),
	Vector3(4.5, 0.0, -2.4),
	Vector3(5.4, 0.0, -1.5)
]

var gravedigger_standby_pos := Vector3(5.2, 0.0, 1.8)
var gravedigger_work_pos := Vector3(4.3, 0.0, 0.0)

func set_grave_site(site: Node3D) -> void:
	grave_site = site
	if is_instance_valid(grave_site):
		plot_pos = grave_site.position

func _ready() -> void:
	_setup_environment()

func _setup_environment() -> void:
	if grave_site == null:
		grave_site = GRAVE_SITE_SCRIPT.new()
		grave_site.name = "GraveSite"
		grave_site.position = plot_pos
		add_child(grave_site)

func _process(delta: float) -> void:
	if current_phase == Phase.IDLE or current_phase == Phase.FINISHED:
		return

	var is_moving := (current_phase == Phase.PROCESSION or current_phase == Phase.DISPERSAL)
	for p in pallbearers:
		if is_instance_valid(p) and p.has_method("update_animation"):
			p.update_animation(delta, is_moving)
	for v in visitors:
		if is_instance_valid(v) and v.has_method("update_animation"):
			v.update_animation(delta, is_moving)
	if is_instance_valid(gravedigger) and gravedigger.has_method("update_animation"):
		gravedigger.update_animation(delta, is_moving)

func start_sequence() -> void:
	cancel_sequence()

	current_phase = Phase.PROCESSION
	phase_timer = 0.0
	sequence_started.emit()

	grave_site.set_state(0) # State.OPEN

	casket = CASKET_SCRIPT.new()
	casket.name = "FuneralCasket"
	casket.position = procession_start_pos + Vector3(0.0, 0.70, 0.0)
	add_child(casket)

	for i in 4:
		var p: Node3D = MOURNER_SCRIPT.new(0, i) # Role.PALLBEARER
		p.name = "Pallbearer_" + str(i)
		p.position = casket.position + pallbearer_offsets[i]
		p.position.y = 0.0
		var side := -1.0 if pallbearer_offsets[i].x < 0 else 1.0
		p.set_carrying(true, side)
		add_child(p)
		pallbearers.append(p)

	for i in 4:
		var v: Node3D = MOURNER_SCRIPT.new(1, i + 4) # Role.GUEST
		v.name = "Visitor_" + str(i)
		v.position = gate_pos + Vector3((i % 2) * 1.4 - 0.7, 0.0, -float(i) * 1.1)
		v.set_respect_pose()
		add_child(v)
		visitors.append(v)

	_run_procession_tween()

func _run_procession_tween() -> void:
	if active_tween != null: active_tween.kill()
	var spd: float = maxf(0.1, speed_multiplier)
	active_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	var waypoint_corridor := Vector3(0.0, 0.70, 0.0)
	var final_casket_pos := plot_pos + Vector3(0.0, 0.06, 0.0)

	active_tween.tween_property(casket, "position", waypoint_corridor, 3.5 / spd)
	for i in pallbearers.size():
		var p := pallbearers[i]
		active_tween.parallel().tween_property(p, "position", waypoint_corridor + pallbearer_offsets[i], 3.5 / spd)

	for i in visitors.size():
		var v := visitors[i]
		var follow_pos := Vector3((i % 2) * 1.6 - 0.8, 0.0, -1.8 - float(i) * 0.9)
		active_tween.parallel().tween_property(v, "position", follow_pos, 3.5 / spd)

	active_tween.tween_property(casket, "position", final_casket_pos, 2.8 / spd)
	for i in pallbearers.size():
		var p := pallbearers[i]
		active_tween.parallel().tween_property(p, "position", pallbearer_standby_pos[i], 2.8 / spd)

	for i in visitors.size():
		var v := visitors[i]
		active_tween.parallel().tween_property(v, "position", visitor_standby_pos[i], 3.0 / spd)

	active_tween.tween_callback(func():
		for p in pallbearers:
			if is_instance_valid(p): p.set_respect_pose()
		grave_site.attach_casket(casket)
		procession_arrived.emit()
		_start_ceremony()
	)

func _start_ceremony() -> void:
	current_phase = Phase.CEREMONY_WAIT
	ceremony_started.emit()

	for p in pallbearers:
		if is_instance_valid(p): p.look_at(plot_pos, Vector3.UP)
	for v in visitors:
		if is_instance_valid(v): v.look_at(plot_pos, Vector3.UP)

	if active_tween != null: active_tween.kill()
	var spd: float = maxf(0.1, speed_multiplier)
	active_tween = create_tween()
	active_tween.tween_interval(ceremony_wait_time / spd)
	active_tween.tween_callback(_start_lowering)

func _start_lowering() -> void:
	current_phase = Phase.LOWERING
	lowering_started.emit()

	var spd: float = maxf(0.1, speed_multiplier)
	var lower_tween: Tween = grave_site.animate_lowering(3.2 / spd)
	lower_tween.tween_callback(func():
		lowering_completed.emit()
		_start_filling()
	)

func _start_filling() -> void:
	current_phase = Phase.FILLING
	filling_started.emit()

	var spd: float = maxf(0.1, speed_multiplier)
	if is_instance_valid(gravedigger):
		var dig_tween := create_tween()
		dig_tween.tween_property(gravedigger, "position", gravedigger_work_pos, 1.2 / spd)
		if gravedigger.has_method("set_dig_pose"):
			gravedigger.call("set_dig_pose", true)

	var fill_tween: Tween = grave_site.animate_filling(4.0 / spd)
	fill_tween.tween_callback(func():
		filling_completed.emit()
		if is_instance_valid(gravedigger) and gravedigger.has_method("set_dig_pose"):
			gravedigger.call("set_dig_pose", false)
		_start_dispersal()
	)

func _start_dispersal() -> void:
	current_phase = Phase.DISPERSAL
	dispersal_started.emit()

	if active_tween != null: active_tween.kill()
	var spd: float = maxf(0.1, speed_multiplier)
	active_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	var exit_y := gate_pos.z - 4.0
	for i in pallbearers.size():
		var p := pallbearers[i]
		if is_instance_valid(p):
			var exit_target := Vector3((i % 2) * 1.0 - 0.5, 0.0, exit_y - float(i) * 1.2)
			p.look_at(p.position + Vector3(0, 0, -1), Vector3.UP)
			active_tween.parallel().tween_property(p, "position", exit_target, 4.5 / spd)

	for i in visitors.size():
		var v := visitors[i]
		if is_instance_valid(v):
			var exit_target := Vector3((i % 2) * 1.2 - 0.6, 0.0, exit_y - 2.0 - float(i) * 1.2)
			v.look_at(v.position + Vector3(0, 0, -1), Vector3.UP)
			active_tween.parallel().tween_property(v, "position", exit_target, 5.0 / spd)

	if is_instance_valid(gravedigger):
		active_tween.parallel().tween_property(gravedigger, "position", gravedigger_standby_pos, 2.0 / spd)

	active_tween.tween_callback(_finish_cycle)

func _finish_cycle() -> void:
	current_phase = Phase.FINISHED
	_cleanup_actors()
	sequence_completed.emit()

func cancel_sequence() -> void:
	if active_tween != null and active_tween.is_running():
		active_tween.kill()
	_cleanup_actors()
	if is_instance_valid(casket):
		casket.queue_free()
		casket = null
	if is_instance_valid(grave_site):
		grave_site.set_state(0) # State.OPEN
	current_phase = Phase.IDLE
	sequence_cancelled.emit()

func _cleanup_actors() -> void:
	for p in pallbearers:
		if is_instance_valid(p):
			p.queue_free()
	pallbearers.clear()

	for v in visitors:
		if is_instance_valid(v):
			v.queue_free()
	visitors.clear()

func set_gravedigger(worker: Node3D) -> void:
	gravedigger = worker
	gravedigger.position = gravedigger_standby_pos
