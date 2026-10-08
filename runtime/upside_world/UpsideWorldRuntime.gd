extends Node
## A transient first-person illusion; FullSession still owns admission and return.
const STATE := preload("res://runtime/upside_world/UpsideWorldState.gd")
const RETURNS := preload("res://runtime/upside_world/UpsideReturnPoints.gd")
const VEIL := preload("res://runtime/upside_world/UpsideVeil.gd")
const HOUSE := preload("res://world/places/amusement_park/AmusementParkLayout.gd")
const ARENA_ORIGIN := Vector3(0,0,-3400)
const OWNER_META := &"upside_world_owner"
var session
var world
var state=STATE.new()
var active := false
var arena: Node3D
var view: Camera3D
var veil: CanvasLayer
var yaw := 0.0
var pitch := 0.0
var _saved: Dictionary={}
var _entry_room: Node3D
var _token := 0
var _admitting := false
var _returning := false
var _released := false
var _finishing := false
var _return_attempts := 0
var _retry := 0.0
var _return_generation := 0
var _handoff_generation := 0
var _safe_return_pending := false
var _safe_retry := 0.0
var _safe_reason := ""
var _safe_notice: Label
var _rng := RandomNumberGenerator.new()

func configure(owner_session) -> void:
	name="UpsideWorldRuntime"
	session=owner_session
	world=session.world
	_rng.randomize()

func busy() -> bool: return active or _admitting or _returning
func exploring() -> bool: return active and state.active and not _admitting and not _returning and not _released and not _safe_return_pending
func token() -> int: return _token
func owns(expected: int) -> bool:
	if expected<=0 or expected!=_token or not busy() or not is_instance_valid(session): return false
	if not _released: return session._owns_transition(expected)
	# The illusion token hands off to one registered departure at a time.
	# It must never act as an unconditional permit after another owner arrives.
	var generation: int = session.transition_generation
	var kind: String = session.transition_kind
	if generation == _handoff_generation and kind.is_empty(): return true
	return generation == _return_generation and kind in ["leave_place", ""]

func arm_entry(place_id: String, restored := false) -> bool:
	if session==null or busy() or not is_instance_valid(session.room) or session.wine==null: return false
	var alcohol: float=session.wine.model.data.alcohol
	if not state.arm_entry(session.room.get_instance_id(),place_id,alcohol,restored): return false
	_entry_room=session.room
	try_start.call_deferred()
	return true

func _can_start() -> bool:
	return session!=null and session.ready_for_play and not get_tree().paused and not session.modal and not session.is_transition_blocked() and session.state.region_id=="harbor" and session.state.place_id==STATE.PLACE and session.room==_entry_room and is_instance_valid(_entry_room) and world.gameplay.health>0 and not session.rescue_pending and not session.arrest_pending and not world.driving.occupied and not world.player.input_locked

func try_start() -> bool:
	if busy() or state.pending_entry==0 or not _can_start(): return false
	_admitting=true
	_return_attempts=0
	_retry=0.0
	_released=false
	_return_generation=0
	_handoff_generation=0
	_safe_return_pending=false
	set_meta("end_reason","")
	# The house camera must relinquish ownership before our snapshot is taken.
	if session.amusement_park!=null: session.amusement_park._end_house_view()
	_saved={"point":world.player.global_position,"locked":world.player.input_locked,
		"visual_visible":world.player.visual.visible,"hud_visible":world.hud.visible,
		"player_camera":world.player.camera,"camera":get_viewport().get_camera_3d(),
		"gameplay_enabled":world.gameplay.enabled,"mouse":Input.mouse_mode,
		"automatic":world.player.controlled_automatically,"automatic_direction":world.player.automatic_direction,
		"physics":world.player.is_physics_processing(),"layer":world.player.collision_layer,"mask":world.player.collision_mask,
		"weapon":session.state.equipped_weapon,"health":world.gameplay.health}
	_token=session._begin_transition("upside_world")
	if _token<0:
		_admitting=false; _saved.clear(); return false
	active=true
	world.player.set_meta(OWNER_META,_token)
	world.hud.set_meta(OWNER_META,_token)
	world.gameplay.set_meta(OWNER_META,_token)
	world.gameplay.enabled=false
	world.player.input_locked=true
	world.player.velocity=Vector3.ZERO
	veil=VEIL.new()
	add_child(veil)
	if not await _fade_to(1.0,.28,_token): return false
	var script: Script=load("res://world/places/upside_world/UpsideWorld.gd")
	if script==null: cancel("arena_unavailable"); return false
	arena=script.new()
	arena.position=ARENA_ORIGIN
	world.add_child(arena)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not _still_owns_scene(): cancel("admission_interrupted",false); return false
	var spawn: Vector3=arena.to_global(arena.get("spawn_local"))
	if not session.position_clear(spawn): cancel("spawn_blocked"); return false
	view=Camera3D.new()
	view.name="UpsideWorldCamera"
	view.near=.06
	view.far=180.0
	view.fov=72.0
	view.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(view)
	var source: Environment=world.production.environment.environment
	view.environment=arena.make_environment(source)
	view.make_current()
	world.player.teleport(spawn)
	world.player.camera=view
	world.player.visual.hide()
	world.hud.hide()
	world.player.controlled_automatically=false
	world.player.automatic_direction=Vector3.ZERO
	world.player.set_physics_process(true)
	yaw=0.0; pitch=0.0
	_tick_view(0.0)
	if not state.start(state.pending_entry,_rng.randf_range(STATE.MIN_DURATION,STATE.MAX_DURATION)):
		cancel("state_refused"); return false
	if not await _fade_to(0.0,.35,_token): return false
	_admitting=false
	world.player.input_locked=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if _touch_interface() else Input.MOUSE_MODE_CAPTURED
	return true

func _process(delta: float) -> void:
	if session==null or not session.ready_for_play: return
	if not busy():
		if state.pending_entry!=0:
			if not is_instance_valid(_entry_room) or session.room!=_entry_room or session.state.place_id!=STATE.PLACE: state.cancel()
			elif _can_start(): try_start()
		return
	if _released:
		if not owns(_token) or world.gameplay.health<=0 or session.rescue_pending or session.arrest_pending or session.state.region_id!="harbor": cancel("handoff_interrupted",false)
		return
	if not _still_owns_scene(): cancel("interrupted",false); return
	if get_tree().paused or _admitting: return
	if _safe_return_pending:
		_tick_view(delta)
		_safe_retry=maxf(0.0,_safe_retry-delta)
		if _safe_retry<=0.0: cancel(_safe_reason)
		return
	if _returning: return
	_tick_view(delta)
	if is_instance_valid(arena): arena.set_visitor(arena.to_local(world.player.global_position))
	if _retry>0.0:
		_retry=maxf(0.0,_retry-delta)
		if _retry<=0.0: _request_return()
	elif state.tick(delta):
		_request_return()

func _still_owns_scene() -> bool:
	return is_instance_valid(session) and is_instance_valid(world) and session._owns_transition(_token) and session.room==_entry_room and session.state.place_id==STATE.PLACE and session.state.region_id=="harbor" and world.gameplay.health>0 and not session.rescue_pending and not session.arrest_pending and not world.driving.occupied

func _tick_view(delta: float) -> void:
	if not is_instance_valid(view): return
	_gamepad_look(delta)
	view.global_position=world.player.global_position+Vector3.UP*1.65
	view.rotation=Vector3(pitch,yaw,0)
	if not session.modal and not get_tree().paused:
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if _touch_interface() else Input.MOUSE_MODE_CAPTURED

func look_delta(motion: Vector2) -> void:
	if not motion.is_finite(): return
	yaw=wrapf(yaw-motion.x,-PI,PI)
	pitch=clampf(pitch-motion.y,-1.15,.95)

func _gamepad_look(delta: float) -> void:
	if not exploring() or session.modal or get_tree().paused: return
	var controls:=get_node_or_null("/root/GameInput")
	if controls==null: return
	var stick: Vector2=controls.touch_aim
	if stick.is_zero_approx() and controls.using_gamepad:
		stick=controls._read_aim_stick()
		var strength:=minf(stick.length(),1.0)
		var deadzone: float=controls.AIM_STICK_DEADZONE
		if strength<=deadzone: return
		stick=stick.normalized()*(strength-deadzone)/(1.0-deadzone)
	if not stick.is_zero_approx(): look_delta(stick.limit_length()*delta*1.8)

func handle_input(event: InputEvent) -> bool:
	if not busy(): return false
	if event.is_action_pressed("pause_game"):
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		return false
	if get_tree().paused: return false
	if session.modal or not exploring(): return not (event is InputEventScreenTouch)
	if event is InputEventMouse and event.device==InputEvent.DEVICE_ID_EMULATION: return false
	if event is InputEventMouseMotion:
		look_delta(event.relative*.002)
		return true
	if event is InputEventScreenDrag:
		var touch: Node=world.find_child("AndroidControls",true,false)
		if is_instance_valid(touch) and touch.fingers.has(event.index): return false
		look_delta(event.relative*.003)
		return true
	# Movement actions still reach the normal real capsule controller.
	for action in ["move_left","move_right","move_up","move_down","sprint"]:
		if event.is_action(action): return false
	return not (event is InputEventScreenTouch)

func return_candidates() -> Array[Vector3]:
	var result:=RETURNS.candidates()
	for index in range(result.size()-1,0,-1):
		var other:=_rng.randi_range(0,index)
		var temporary: Vector3=result[index]
		result[index]=result[other]; result[other]=temporary
	return result

func _request_return() -> void:
	if _returning or not _still_owns_scene(): return
	var expected := _token
	_returning=true
	_return_attempts+=1
	world.player.input_locked=true
	world.player.velocity=Vector3.ZERO
	if not await _fade_to(1.0,.32,expected): return
	if not session.has_method("complete_upside_return"):
		cancel("return_adapter_missing"); return
	var completed: bool=await session.complete_upside_return(self,expected)
	if completed or not active or _token!=expected: return
	if _released or _return_attempts>=3:
		cancel("return_unavailable"); return
	_returning=false
	_retry=.4
	# Keep the curtain opaque while the finite safe-return retry runs.

func release_for_return(expected: int) -> bool:
	if not owns(expected) or not _returning or _released or not _still_owns_scene(): return false
	var point := _safe_room_point()
	if not point.is_finite(): return false
	world.player.teleport(point)
	_saved.point=point
	_restore_presentation(true,false)
	world.player.input_locked=true
	_released=true
	_handoff_generation=session.transition_generation
	_return_generation=_handoff_generation+1
	session._finish_transition(expected)
	return true

func prepare_departure_retry(expected: int) -> bool:
	# A blocked ordinary departure may choose another curated street point.
	# Renew only our own completed handoff; never adopt a foreign transition.
	if not owns(expected) or not _released or not session.transition_kind.is_empty(): return false
	if not is_instance_valid(_entry_room) or session.room!=_entry_room or session.state.place_id!=STATE.PLACE or session.state.region_id!="harbor": return false
	if world.gameplay.health<=0 or session.rescue_pending or session.arrest_pending or world.driving.occupied: return false
	_handoff_generation=session.transition_generation
	_return_generation=_handoff_generation+1
	return true

func finish_return(expected: int) -> bool:
	if not owns(expected) or not _released or world.gameplay.health<=0 or session.rescue_pending or session.arrest_pending: return false
	if session.transition_generation!=_return_generation or not session.transition_kind.is_empty(): return false
	if session.state.region_id!="harbor" or not session.state.place_id.is_empty() or is_instance_valid(session.room) or world.driving.occupied: return false
	if not session.position_clear(world.player.global_position): return false
	_finishing=true
	set_meta("end_reason","returned")
	active=false; _admitting=false; _returning=false
	state.cancel()
	if session.wine!=null: session.wine.recover()
	_clear_owned_assets()
	_saved.clear(); _entry_room=null; _token=0; _released=false; _return_generation=0; _handoff_generation=0; _safe_return_pending=false
	_finishing=false
	return true

func cancel(reason := "", restore_player := true) -> void:
	if _finishing: return
	_finishing=true
	var ours: bool=is_instance_valid(session) and _token>0 and session._owns_transition(_token)
	var living: bool=is_instance_valid(world) and world.gameplay.health>0 and not session.rescue_pending and not session.arrest_pending
	if ours and living and restore_player and _saved.has("point"):
		var point := _safe_room_point()
		if point.is_finite():
			world.player.teleport(point)
		elif is_instance_valid(arena):
			# Never remove the only floor under a living visitor. Keep ownership,
			# camera and physical arena until a validated room point becomes free.
			_wait_for_safe_room(reason)
			_finishing=false
			return
	if busy() or state.pending_entry!=0: set_meta("end_reason",reason)
	_restore_presentation(ours,ours and living)
	if ours: session._finish_transition(_token)
	active=false; _admitting=false; _returning=false; _released=false
	state.cancel()
	_clear_owned_assets()
	_saved.clear(); _entry_room=null; _token=0; _retry=0.0; _return_generation=0; _handoff_generation=0; _safe_return_pending=false
	_finishing=false

func _safe_room_point() -> Vector3:
	if not is_instance_valid(_entry_room) or session.room!=_entry_room or session.state.place_id!=STATE.PLACE: return Vector3.INF
	var candidates: Array[Vector3]=[]
	if _saved.has("point"): candidates.append(_saved.point)
	# This authored walk route was validated against Umbra's real furnishings;
	# every live point still needs capsule clearance and floor support now.
	for local: Vector3 in HOUSE.house_route(): candidates.append(_entry_room.to_global(local)+Vector3.UP*.04)
	if _saved.has("point"):
		for offset: Vector3 in [Vector3(.65,0,0),Vector3(-.65,0,0),Vector3(0,0,.65),Vector3(0,0,-.65)]: candidates.append(_saved.point+offset)
	for candidate: Vector3 in candidates:
		if candidate.is_finite() and session.position_clear(candidate): return candidate
	return Vector3.INF

func _wait_for_safe_room(reason: String) -> void:
	_safe_return_pending=true
	_safe_reason=reason
	_safe_retry=1.0
	_returning=false
	_admitting=false
	world.player.input_locked=true
	world.player.velocity=Vector3.ZERO
	# Freeze the bounded play timer while an exceptional blocked return
	# waits. No extra arena, tween or async retry is created per attempt.
	if is_instance_valid(veil) and veil.has_method("set_amount"): veil.set_amount(.20)
	if not is_instance_valid(_safe_notice):
		_safe_notice=Label.new()
		_safe_notice.name="UpsideSafeReturnNotice"
		_safe_notice.text="Passagem ocupada. Aguardando um local seguro…"
		_safe_notice.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		_safe_notice.vertical_alignment=VERTICAL_ALIGNMENT_BOTTOM
		_safe_notice.add_theme_font_size_override("font_size",22)
		_safe_notice.add_theme_color_override("font_outline_color",Color("100d19"))
		_safe_notice.add_theme_constant_override("outline_size",5)
		_safe_notice.mouse_filter=Control.MOUSE_FILTER_IGNORE
		veil.add_child(_safe_notice)
		_safe_notice.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_safe_notice.offset_bottom=-52
	_safe_notice.show()

func _restore_presentation(owns_session: bool, restore_input: bool) -> void:
	if not is_instance_valid(world) or _saved.is_empty(): return
	var player=world.player
	if is_instance_valid(player) and player.get_meta(OWNER_META,0)==_token:
		if player.camera==view: player.camera=_saved.get("player_camera",world.camera)
		if owns_session:
			player.visual.visible=bool(_saved.visual_visible)
			player.controlled_automatically=bool(_saved.automatic)
			player.automatic_direction=_saved.automatic_direction
			player.set_physics_process(bool(_saved.physics))
			player.collision_layer=int(_saved.layer)
			player.collision_mask=int(_saved.mask)
			player.velocity=Vector3.ZERO
		if restore_input: player.input_locked=bool(_saved.locked)
		player.remove_meta(OWNER_META)
	if is_instance_valid(world.hud) and world.hud.get_meta(OWNER_META,0)==_token:
		if owns_session: world.hud.visible=bool(_saved.hud_visible)
		world.hud.remove_meta(OWNER_META)
	if is_instance_valid(world.gameplay) and world.gameplay.get_meta(OWNER_META,0)==_token:
		if owns_session: world.gameplay.enabled=bool(_saved.gameplay_enabled)
		world.gameplay.remove_meta(OWNER_META)
	if is_instance_valid(view) and get_viewport().get_camera_3d()==view:
		var camera: Variant=_saved.get("camera")
		if is_instance_valid(camera): camera.make_current()
		else: world.camera.make_current()
		world.camera.initialized=false
		Input.mouse_mode=int(_saved.mouse) as Input.MouseMode
	if is_instance_valid(view): view.queue_free()
	view=null

func _fade_to(alpha: float, seconds: float, expected: int) -> bool:
	if not is_instance_valid(veil): return false
	var start: float=veil.amount
	var elapsed:=0.0
	while elapsed<seconds:
		await get_tree().process_frame
		if not is_inside_tree() or not owns(expected) or not is_instance_valid(veil): return false
		if get_tree().paused: continue
		elapsed=minf(seconds,elapsed+get_process_delta_time())
		veil.set_amount(lerpf(start,alpha,smoothstep(0.0,1.0,elapsed/seconds)))
	return true

func _clear_owned_assets() -> void:
	if is_instance_valid(view): view.queue_free()
	if is_instance_valid(arena): arena.queue_free()
	if is_instance_valid(veil): veil.queue_free()
	_safe_notice=null
	view=null; arena=null; veil=null

func _touch_interface() -> bool:
	var controls:=get_node_or_null("/root/GameInput")
	return OS.has_feature("android") or (controls!=null and controls.get_meta("touch_controls_active",false))

func _exit_tree() -> void: cancel("unloaded",false)
