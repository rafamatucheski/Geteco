extends Node3D
## Optional armed hideout. Carried money becomes a reward only after a live exit.
const STATE := preload("res://gameplay/mining/MiningRaidState.gd")
const GUARD := preload("res://runtime/desert/DesertBanditEncounter.gd").Bandit
const PLACE_ID := "remote_coal_mine"
var session
var room: Node3D
var actors: Dictionary={}
var pending_cash := false
var engaged := false
var _clock := 0.0
var _retry := 0.0
var _hud: CanvasLayer
var _label: Label
var _cancelled_room_id := 0
var _owned_loot: Array[Node3D]=[]
var _known_loot: Dictionary={}

func configure(owner_session) -> void:
	session=owner_session
	name="MiningRaid"
	if not session.state.world_state.has(STATE.KEY): session.state.world_state[STATE.KEY]=STATE.defaults()

func completed() -> bool:
	return session.state.economy.has_reward_receipt(STATE.RECEIPT)

func enter_room(next_room: Node3D) -> void:
	if next_room.get_instance_id()==_cancelled_room_id: return
	if room==next_room: return
	_cancelled_room_id=0
	_release()
	room=next_room
	pending_cash=false
	engaged=false
	_retry=.25
	_known_loot.clear()
	for pickup in session.world.gameplay._loot:
		if is_instance_valid(pickup): _known_loot[pickup.get_instance_id()]=true
	room.set_raid_loot_available(not completed())

func operational() -> bool:
	return is_instance_valid(session) and session.ready_for_play and session.state.place_id==PLACE_ID and is_instance_valid(room) and session.room==room and session.world.gameplay.health>0 and not session.modal and not session.is_transition_blocked() and not session.world.player.input_locked

func live_count() -> int:
	var count:=0
	for actor in actors.values():
		if is_instance_valid(actor) and not actor.dead: count+=1
	return count

func _process(delta: float) -> void:
	if not is_instance_valid(session) or not session.ready_for_play: return
	_clock+=delta
	if _clock<.2: return
	var elapsed:=_clock
	_clock=0
	_retry=maxf(0,_retry-elapsed)
	if session.state.place_id!=PLACE_ID or not is_instance_valid(session.room):
		if is_instance_valid(room) or not actors.is_empty(): cancel()
		_cancelled_room_id=0
		return
	if session.room.get_instance_id()==_cancelled_room_id: return
	if room!=session.room: enter_room(session.room)
	if session.world.gameplay.health<=0: cancel(); return
	var active:=operational()
	for actor in actors.values():
		if is_instance_valid(actor): actor.set_physics_process(active and not actor.dead)
	if not active or completed(): return
	var positions: Array=room.raid_guard_positions()
	for index in positions.size():
		if actors.has(index) or _retry>0: continue
		if _admit(index,positions[index]): _retry=.25
		break
	if room.raid_contains(session.world.player.global_position): engaged=true
	for actor in actors.values():
		if is_instance_valid(actor) and not actor.dead: actor.engaged=engaged
	if is_instance_valid(_label):
		_label.visible=pending_cash
		_label.text="R$ 12.000 na bolsa  ·  Saia vivo da mina"

func _admit(index: int,point: Vector3) -> bool:
	if not session.position_clear(point+Vector3.UP*.05): return false
	var guard:=GUARD.new()
	guard.encounter=self
	guard.slot=index%3
	guard.configure(session.world.gameplay,index%3)
	guard.weapon_id="pistol"
	guard.position=point+Vector3.UP*.05
	guard.died.connect(_guard_died.bind(index))
	add_child(guard)
	guard.remove_from_group("desert_bandits")
	guard.add_to_group("mining_bandits")
	guard.set_meta("character_name",["Nilo","Rato","Brasa","Tito"][index])
	guard.set_meta("mining_bandit",true)
	guard.set_meta("place_id",PLACE_ID)
	# The shared line-of-sight query keys interior ownership by this field.
	guard.set_meta("police_place_id",PLACE_ID)
	guard.health=85
	guard.max_health=85
	actors[index]=guard
	return true

func provoke(source: Node) -> void:
	if operational() and source==session.world.player: engaged=true

func _guard_died(_index: int) -> void:
	# Keep the dead slot owned until departure; no replacement during this attempt.
	# Production death drops happen immediately before this signal. Remember
	# only this visit's new pickups so they cannot leak into another interior
	# that uses the same world-space room origin.
	for pickup in session.world.gameplay._loot:
		if not is_instance_valid(pickup) or _known_loot.has(pickup.get_instance_id()): continue
		_known_loot[pickup.get_instance_id()]=true
		if is_instance_valid(room) and room.raid_contains(pickup.global_position):
			pickup.set_meta("mining_raid_loot",true)
			_owned_loot.append(pickup)

func nearest_action() -> Dictionary:
	if not operational() or pending_cash or completed() or session.world.driving.occupied: return {}
	return room.nearest_raid_action(session.world.player.global_position,true)

func perform(action: Dictionary) -> bool:
	if nearest_action().get("target","")!=action.get("target","") or action.get("target","")!="raid_loot": return false
	pending_cash=true
	engaged=true
	room.set_raid_loot_available(false)
	if not is_instance_valid(_hud):
		_hud=CanvasLayer.new(); _hud.layer=10; add_child(_hud)
		_label=Label.new()
		_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		_label.offset_top=105
		_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		_label.add_theme_font_size_override("font_size",18)
		_label.add_theme_color_override("font_color",Color("f7d27c"))
		_label.add_theme_color_override("font_outline_color",Color("171714"))
		_label.add_theme_constant_override("outline_size",4)
		_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
		_hud.add_child(_label)
	session.show_message("Dinheiro na bolsa. Saia vivo da mina.")
	return true

func save_block_reason() -> String:
	if pending_cash: return "Saia vivo da mina para guardar o dinheiro e salvar."
	if engaged and live_count()>0: return "Saia da mina ou encerre o confronto antes de salvar."
	return ""

func departed() -> void:
	# Called only after FullSession validates the live actor and exterior return.
	if session.state.place_id!=PLACE_ID or session.world.gameplay.health<=0: cancel(); return
	if pending_cash and not completed():
		if session.state.economy.grant_reward(STATE.RECEIPT,STATE.CASH):
			session.state.world_state[STATE.KEY]={"version":1,"escaped":true}
			preload("res://gameplay/RewardAudio.gd").play(self,"cash")
			session.show_message("Saque guardado: R$ 12.000.")
	cancel()

func cancel() -> void:
	if is_instance_valid(room): _cancelled_room_id=room.get_instance_id()
	pending_cash=false
	engaged=false
	_release()
	room=null
	if is_instance_valid(_label): _label.hide()

func _release() -> void:
	for pickup in _owned_loot:
		if is_instance_valid(pickup): pickup.queue_free()
	_owned_loot.clear()
	_known_loot.clear()
	for actor in actors.values():
		if is_instance_valid(actor):
			actor.set_physics_process(false)
			actor.collision_layer=0
			actor.queue_free()
	actors.clear()

func _exit_tree() -> void: _release()
