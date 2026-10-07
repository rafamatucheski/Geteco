extends Node3D
## Normal player car physics, input, camera and collision remain authoritative.
const COURSE := preload("res://activities/desert_wash/DesertWashCourse.gd")
const STATE := preload("res://activities/desert_wash/DesertWashState.gd")
const MARKERS := preload("res://activities/desert_wash/DesertWashMarkers.gd")
signal race_completed(result: Dictionary)
var session
var active := false
var phase := ""
var countdown := 0.0
var elapsed := 0.0
var next_gate := 1
var last_result: Dictionary={}
var player_car
var markers: Node3D
var _previous := Vector3.ZERO
var _countdown_origin := Vector3.ZERO
var _was_locked := false
var _player_was_locked := false
var _ui_clock := 0.0
var _proximity_clock := 0.0
var _layer: CanvasLayer
var _label: Label

func configure(owner_session) -> void:
	session=owner_session
	name="DesertWash"
	set_physics_process(false)
	process_physics_priority=5

func _process(delta: float) -> void:
	if is_instance_valid(_label): _label.visible=not session.modal and not get_tree().paused
	_proximity_clock-=delta
	if _proximity_clock>0 or session==null: return
	_proximity_clock=.5
	var near: bool=session.ready_for_play and session.state.region_id=="desert" and session.state.place_id.is_empty() and session.world.player.global_position.distance_to(COURSE.gate(6))<360
	if OS.is_debug_build() and Engine.get_meta("desert_wash_benchmark_disabled",false): near=false
	if near and not is_instance_valid(markers):
		markers=MARKERS.new()
		add_child(markers)
		markers.build(_surface_height)
		markers.show_gate(next_gate if active else -1)
	elif not near and is_instance_valid(markers):
		markers.queue_free()
		markers=null

func _surface_height(point: Vector2) -> float:
	return COURSE.LANDFORMS.surface_height(point,session.world.production.region._ground_height)

func nearest_action() -> Dictionary:
	if session==null or not session.ready_for_play or session.controller.save_invalid or session.state.region_id!="desert" or not session.state.place_id.is_empty(): return {}
	if active: return {"id":"desert_wash","target":"cancel","label":"Abandonar prova do leito seco"}
	var driving=session.world.driving
	var p: Vector3=driving.car.global_position if driving.occupied and is_instance_valid(driving.car) else session.world.player.global_position
	if p.distance_to(COURSE.gate(0))>7.0: return {}
	var saved:=STATE.data(session.state.world_state)
	var label:="Prova do leito seco · 45 s · R$ 1.800"
	if STATE.valid(saved) and saved.finishes>0: label="Prova do leito seco · Recorde %.2f s · Meta 45 s"%float(saved.best)
	return {"id":"desert_wash","target":"start","label":label}

func start_block_reason() -> String:
	if active: return "A prova já começou."
	if session.controller.save_invalid: return "Save inválido preservado; atividade indisponível."
	if not session.ready_for_play or session.modal or get_tree().paused or session.is_transition_blocked(): return "Encerre a atividade atual."
	if session.state.intro.stage!="complete" or not session.state.campaign.active_id.is_empty(): return "Conclua a missão atual."
	if session.desert.busy() or (session.activities!=null and not session.activities.can_rest()): return "Encerre a atividade atual."
	if session.world.gameplay.health<=0 or session.rescue_pending or session.arrest_pending: return "Aguarde a recuperação."
	if session.world.gameplay.stars>0: return "Despiste a polícia antes de correr."
	if nearest_action().get("target","")!="start": return "Vá à entrada do leito seco."
	var driving=session.world.driving
	if not driving.occupied or not is_instance_valid(driving.car) or driving.is_body_transition_active(): return "Entre em um carro para correr."
	var car=driving.car
	if car.health<=0 or car.engine_disabled or car.half_width>1.45 or car.half_length>3.1: return "Use um carro em condições de correr."
	if car.input_locked or car.external_input or absf(car.speed)>.5: return "Pare o carro entre os cones da largada."
	var offset: Vector3=car.global_position-COURSE.gate(0)
	if absf(offset.dot(COURSE.direction(0).cross(Vector3.UP)))>2.0 or absf(offset.dot(COURSE.direction(0)))>4.0: return "Alinhe o carro entre os cones da largada."
	if (-car.global_basis.z).dot(COURSE.direction(0))<.75: return "Vire o carro para o próximo par de cones."
	return ""

func perform(target: String) -> bool:
	if target=="cancel" and active:
		cancel_attempt()
		return true
	if target!="start": return false
	var reason:=start_block_reason()
	if not reason.is_empty(): session.show_message(reason); return false
	STATE.claim(session.state.world_state,session.state.economy)
	player_car=session.world.driving.car
	_was_locked=player_car.input_locked
	_player_was_locked=session.world.player.input_locked
	player_car.input_locked=true
	session.world.player.input_locked=true
	_previous=player_car.global_position
	_countdown_origin=_previous
	active=true; phase="countdown"; countdown=3.0; elapsed=0.0; next_gate=1
	last_result={}
	_layer=CanvasLayer.new()
	_layer.layer=22
	add_child(_layer)
	_label=Label.new()
	_label.position=Vector2(24,112)
	_label.add_theme_font_size_override("font_size",23)
	_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x",2)
	_label.add_theme_constant_override("shadow_offset_y",2)
	_layer.add_child(_label)
	_update_hud()
	if is_instance_valid(markers): markers.show_gate(next_gate)
	set_physics_process(true)
	return true

func _physics_process(delta: float) -> void:
	if not active: return
	if not is_instance_valid(player_car) or session.state.region_id!="desert" or not session.state.place_id.is_empty() or not session.world.driving.occupied or session.world.driving.car!=player_car:
		cancel_attempt("leave"); return
	if session.world.gameplay.health<=0 or session.world.player.dead or player_car.health<=0 or player_car.engine_disabled or session.rescue_pending or session.arrest_pending:
		cancel_attempt("recovery"); return
	if session.world.gameplay.stars>0: cancel_attempt("police"); return
	if session.modal or get_tree().paused: return
	var p: Vector3=player_car.global_position
	if phase=="countdown":
		if p.distance_to(_countdown_origin)>.8: cancel_attempt("false_start"); return
		countdown-=delta
		_previous=p
		if countdown<=0:
			phase="running"
			player_car.input_locked=_was_locked
		_update_hud()
		return
	# Check displacement before any checkpoint, preventing teleport completion.
	if not p.is_finite() or p.distance_to(_previous)>maxf(2.0,delta*90.0): cancel_attempt("discontinuity"); return
	if COURSE.distance_to_course(p)>16.0: cancel_attempt("off_course"); return
	var fraction:=COURSE.crossing(_previous,p,next_gate)
	if fraction>=0:
		if next_gate==COURSE.GATES-1:
			elapsed+=delta*fraction
			_finish()
			return
		next_gate+=1
		if is_instance_valid(markers): markers.show_gate(next_gate)
	elapsed+=delta
	_previous=p
	if elapsed>COURSE.TIME_LIMIT: cancel_attempt("timeout"); return
	_ui_clock-=delta
	if _ui_clock<=0: _ui_clock=.1; _update_hud()

func _update_hud() -> void:
	if not is_instance_valid(_label): return
	_label.text="Leito seco · %d"%maxi(1,ceili(countdown)) if phase=="countdown" else "Leito seco · %.1f s / 45 s · %d/%d"%[elapsed,next_gate,COURSE.GATES-1]
	_label.text+="\n"+get_node("/root/GameInput").hint("interact")+" · Abandonar prova"

func _finish() -> void:
	if not STATE.record(session.state.world_state,elapsed): cancel_attempt("invalid"); return
	var paid:=STATE.claim(session.state.world_state,session.state.economy)
	last_result={"finished":true,"seconds":elapsed,"won":elapsed<=COURSE.PRIZE_TIME,"paid":paid}
	_release()
	var best: float=STATE.data(session.state.world_state).best
	session.show_message("Leito seco: %.2f s · Recorde: %.2f s%s"%[elapsed,best," · R$ 1.800" if paid else ""])
	session.save_game()
	race_completed.emit(last_result)

func cancel_attempt(reason: String = "cancelled") -> void:
	if not active: return
	last_result={"finished":false,"reason":reason}
	_release()
	if is_instance_valid(session): session.show_message("Prova encerrada. Volte à largada para tentar novamente.")

func _release() -> void:
	if not active: return
	var keep_locked: bool=is_instance_valid(session) and (session.modal or session.is_transition_blocked() or session.world.gameplay.health<=0)
	if is_instance_valid(player_car) and phase=="countdown": player_car.input_locked=_was_locked or keep_locked
	if is_instance_valid(session) and is_instance_valid(session.world.player): session.world.player.input_locked=_player_was_locked or keep_locked
	active=false; phase=""
	set_physics_process(false)
	if is_instance_valid(_layer): _layer.queue_free()
	_layer=null; _label=null
	if is_instance_valid(markers): markers.show_gate(-1)
	player_car=null

func _exit_tree() -> void:
	_release()

func save_block_reason() -> String:
	return "Encerre a prova do leito seco para salvar." if active else ""

func controls_locked() -> bool:
	return active and phase=="countdown"

func objective() -> String:
	# The shared HUD announces changes as a new objective; a ticking clock here
	# would repeatedly restart that notification. The local race HUD owns time.
	return "Leito seco · Atravesse os portões na ordem · Meta 45 s" if active else ""

func target_position() -> Vector3:
	return COURSE.gate(next_gate if active else 0)
