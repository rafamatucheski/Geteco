extends Node
const Actor := preload("res://runtime/RobberyActor.gd")
const Lockpick := preload("res://runtime/BankLockpick.gd")
const Treasure := preload("res://runtime/BankVaultTreasure.gd")
const CASH := [4000,3000,3000]
const LOOT := [Vector3(-3,0,-4.2),Vector3(0,0,-4.2),Vector3(3,0,-4.2)]
const VAULT := Vector3(0,0,-2.5)
var session
var data := defaults()
var lockpick: CanvasLayer
var _room: Node3D
var _actors: Array = []
var _piles: Array[Node3D] = []
var _card: Node3D
var _hold_id := ""
var _hold_time := 0.0
var _intimidation := 0.0
var _fuel_notice := false

var _spawn_retry := 0.0

static func defaults() -> Dictionary:
	return {"version":1,"bank_alarm":false,"bank_shots":false,"bank_dispatched":false,"bank_cycle":0,"bank_cash0":false,"bank_cash1":false,"bank_cash2":false,
		"guards":[50.0,50.0],"clerks":[80.0,80.0],"keycard_available":false,"keycard_taken":false,"keycard_position":[-5.0,0.0,.5],"vault_open":false,"opening_remaining":0.0,
		"aftermath":"","elapsed_days":0.0,"fuel_alarm":false,"fuel_dispatched":false,"fuel_alarm_remaining":30.0,"fuel_register":false,"fuel_health":80.0,"fuel_resists":false,"fuel_initialized":false}

func configure(owner_session) -> void:
	session=owner_session
	process_mode=Node.PROCESS_MODE_PAUSABLE
	lockpick=Lockpick.new()
	add_child(lockpick)
	lockpick.unlocked.connect(_unlocked)
	lockpick.cancelled.connect(_unlock_cancelled)
	if session.world.gameplay.has_signal("weapon_fired"):
		session.world.gameplay.weapon_fired.connect(_weapon_fired)

func inside(place: String) -> bool:
	return session!=null and session.state.place_id==place and is_instance_valid(session.room) and session.world.gameplay.health>0 and not session.world.driving.occupied

func can_enter_bank() -> bool:
	return data.aftermath!="closed" or float(data.elapsed_days)>=4

func bank_unavailable() -> bool:
	return data.bank_alarm or not can_enter_bank() or float(data.clerks[0])<=0

func helena_position() -> Vector3:
	if inside("harbor_bank"): return session.room.to_global(Vector3(-2.65,0,-1.9))
	return preload("res://world/places/PlaceCatalog.gd").get_definition("harbor_bank").entry_position

func _physics_process(delta: float) -> void:
	if session==null or not session.ready_for_play or not is_finite(delta) or delta<=0: return
	var place: String = session.state.place_id
	if data.aftermath=="pending" and place!="harbor_bank":
		data.aftermath="closed"
		session.save_game()
	if data.aftermath=="closed":
		data.elapsed_days+=delta/600.0
		if float(data.elapsed_days)>=4: _reopen_bank()
	if data.fuel_alarm and not data.fuel_dispatched:
		data.fuel_alarm_remaining=maxf(0,float(data.fuel_alarm_remaining)-delta)
		if data.fuel_alarm_remaining<=0: _dispatch(false)
	if place not in ["harbor_bank","harbor_fuel"] or not is_instance_valid(session.room):
		_detach_room()
		return
	if _room!=session.room:
		_detach_room()
		_room=session.room
		_attach_room()
	_spawn_retry-=delta
	if _spawn_retry<=0:
		_spawn_retry=1.0
		_ensure_actors()
	if not inside(place):
		_reset_hold()
		if lockpick.active: lockpick.finish(false)
		return
	if place=="harbor_bank":
		if data.opening_remaining>0:
			data.opening_remaining=maxf(0,float(data.opening_remaining)-delta)
			if _room.has_method("set_vault_open"): _room.set_vault_open(1.0-float(data.opening_remaining)/3.0)
			if data.opening_remaining<=0:
				data.vault_open=true
				session.save_game()
		if not _hold_id.is_empty(): _tick_hold(delta,Input.is_action_pressed("interact"))
	else: _tick_cashier(delta,Input.is_action_pressed("aim"))

func _attach_room() -> void:
	if is_instance_valid(session.room_npc): session.room_npc.hide(); session.room_npc.collision_layer=0
	if session.state.place_id=="harbor_bank":
		_ensure_actors()
		for i in 3:
			var pile := Treasure.build(_room,LOOT[i],i)
			pile.visible=not data["bank_cash%d"%i]
			_piles.append(pile)
		if _room.has_method("set_vault_open"): _room.set_vault_open(1.0 if data.vault_open else (1.0-float(data.opening_remaining)/3.0 if data.opening_remaining>0 else 0.0))
		_refresh_card()
	else:
		if not data.fuel_initialized:
			data.fuel_resists=randf()<.25
			data.fuel_initialized=true
			_session_save()
		_ensure_actors()

func _ensure_actors() -> void:
	if not is_instance_valid(_room): return
	if session.state.place_id=="harbor_bank":
		for i in 2:
			_spawn_actor(Vector3(-5 if i==0 else 5,0,.5),float(data.guards[i]),true,i)
			_spawn_actor(Vector3(-2.65 if i==0 else 2.65,0,-1.9),float(data.clerks[i]),false,i)
	elif session.state.place_id=="harbor_fuel": _spawn_actor(Vector3(4.6,0,-3.8),float(data.fuel_health),false,0)

func _spawn_actor(point: Vector3, health: float, guard: bool, index: int) -> void:
	for existing in _actors:
		if is_instance_valid(existing) and existing.guard==guard and existing.get_meta("heist_index")==index: return
	if not session.position_clear(_room.to_global(point)+Vector3.UP*.04): return
	var actor := Actor.new()
	actor.guard=guard
	actor.shotgun=index==0
	actor.female=index==0
	actor.fuel=session.state.place_id=="harbor_fuel"
	actor.health=health
	actor.heist=self
	actor.position=point
	actor.set_meta("heist_index",index)
	_room.add_child(actor)
	actor.injured.connect(_actor_injured)
	_actors.append(actor)

func _actor_injured(actor, _amount: float) -> void:
	var bank: bool = session.state.place_id=="harbor_bank"
	if bank:
		var index: int = actor.get_meta("heist_index")
		if actor.guard:
			data.guards[index]=actor.health
			if actor.dead and not data.keycard_available:
				data.keycard_available=true
				var point: Vector3 = _room.to_local(actor.global_position)
				data.keycard_position=[point.x,0.0,point.z]
				_refresh_card()
		else: data.clerks[index]=actor.health
		data.bank_shots=true
	else: data.fuel_health=actor.health
	_start_alarm(bank)
	_session_save()

func _weapon_fired(_weapon: String, _origin: Vector3) -> void:
	if inside("harbor_bank"):
		data.bank_shots=true
		_start_alarm(true)
	elif inside("harbor_fuel"): _start_alarm(false)

func _start_alarm(bank: bool) -> void:
	var key := "bank_alarm" if bank else "fuel_alarm"
	if data[key]: return
	data[key]=true
	if bank:
		data.aftermath="pending"
		_dispatch(true)
	_session_save()

func _dispatch(bank: bool) -> void:
	var key := "bank_dispatched" if bank else "fuel_dispatched"
	if data[key]: return
	data[key]=true
	var entrance: Vector3 = preload("res://world/places/PlaceCatalog.gd").get_definition("harbor_bank" if bank else "harbor_fuel").entry_position
	# Existing Wanted owns response. No claim of the V1 vehicle perimeter/blockade.
	session.world.gameplay.register_crime(35 if bank else 15,entrance)
	_session_save()

func nearest_action() -> Dictionary:
	if not inside("harbor_bank") or not data.bank_alarm or lockpick==null or lockpick.active or data.opening_remaining>0: return {}
	var local: Vector3 = _room.to_local(session.world.player.global_position)
	var id := ""
	var target := Vector3.ZERO
	var label := ""
	if not data.keycard_taken and data.keycard_available:
		target=Vector3(data.keycard_position[0],0,data.keycard_position[2])
		if local.distance_to(target)<48.0/16.0: id="bank_card"; label="Segurar para pegar cartão"
	elif data.keycard_taken and not data.vault_open and local.distance_to(VAULT)<42.0/16.0:
		id="bank_vault"; target=VAULT; label="Segurar para abrir cofre"
	if data.vault_open and local.z < -3.45:
		for i in 3:
			if not data["bank_cash%d"%i] and local.distance_to(LOOT[i])<40.0/16.0:
				id="bank_cash%d"%i; target=LOOT[i]; label="Segurar para recolher"
	if id.is_empty(): return {}
	return {"id":"robbery","target":id,"label":label,"position":_room.to_global(target)}

func perform(id: String) -> bool:
	if nearest_action().get("target","")!=id or id.is_empty(): return false
	_hold_id=id
	_hold_time=0
	return true

func _tick_hold(delta: float, holding: bool) -> void:
	if not holding or nearest_action().get("target","")!=_hold_id: _reset_hold(); return
	_hold_time+=delta
	var required := .6 if _hold_id=="bank_vault" else 1.2
	if _hold_time<required: return
	var action := _hold_id
	_reset_hold()
	if action=="bank_card":
		data.keycard_taken=true
		_refresh_card()
		_session_save()
	elif action=="bank_vault":
		session.modal=true
		session.world.player.input_locked=true
		lockpick.begin()
	else:
		var index := int(action.trim_prefix("bank_cash"))
		if index not in range(3): return
		if session.state.economy.grant_reward(action+":%d"%int(data.bank_cycle),CASH[index]):
			data[action]=true
			if index<_piles.size(): _piles[index].hide()
			_session_save()

func _unlocked() -> void:
	session.close_menu()
	if not inside("harbor_bank") or not data.keycard_taken: return
	data.opening_remaining=3.0
	_session_save()
func _unlock_cancelled() -> void:
	if session!=null: session.close_menu()
func _reset_hold() -> void:
	_hold_id=""
	_hold_time=0

func _tick_cashier(delta: float, aiming: bool) -> void:
	if data.fuel_register or data.fuel_health<=0 or session.state.equipped_weapon in ["","fists"] or not aiming or _actors.is_empty(): _intimidation=0; return
	var clerk = _actors[0]
	if not is_instance_valid(clerk) or clerk.dead: _intimidation=0; return
	var player: CharacterBody3D = session.world.player
	var direction: Vector3 = clerk.global_position-player.global_position
	direction.y=0
	var aim: Vector3 = session.world.gameplay.aim_point-player.global_position
	aim.y=0
	if direction.length()>=220.0/16.0 or direction.normalized().dot(aim.normalized())<=.94: _intimidation=0; return
	var ray := PhysicsRayQueryParameters3D.create(player.global_position+Vector3.UP*1.65,clerk.global_position+Vector3.UP*1.65,1,[player.get_rid()])
	if not _room.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): _intimidation=0; return
	_start_alarm(false)
	_intimidation+=delta
	if not _fuel_notice:
		session.show_message("Não vou abrir o caixa! Estou chamando a polícia!" if data.fuel_resists else "Calma! Vou abrir o caixa...")
		_fuel_notice=true
	if not data.fuel_resists and _intimidation>=3:
		if session.state.economy.grant_reward("fuel_register",180):
			data.fuel_register=true
			session.show_message("Leva e vai embora!")
			_session_save()

func _refresh_card() -> void:
	if not is_instance_valid(_room): return
	if is_instance_valid(_card): _card.queue_free(); _card=null
	if not data.keycard_available or data.keycard_taken: return
	_card=Node3D.new()
	_card.position=Vector3(data.keycard_position[0],.05,data.keycard_position[2])
	_room.add_child(_card)
	var part = preload("res://assets/regions/source/characters/pedestrians/CitizenDetails.gd")
	part.piece(_card,Vector3(.24,.018,.15),Vector3.ZERO,Color("ddd9c7"))
	part.piece(_card,Vector3(.23,.004,.035),Vector3(0,.011,-.04),Color("273b48"))

func _detach_room() -> void:
	if lockpick!=null and lockpick.active: lockpick.finish(false)
	for actor in _actors:
		if is_instance_valid(actor): actor.queue_free()
	for pile in _piles:
		if is_instance_valid(pile): pile.queue_free()
	if is_instance_valid(_card): _card.queue_free()
	_actors.clear()
	_piles.clear()
	_card=null
	_room=null
	_reset_hold()
	_intimidation=0
	_fuel_notice=false

func _reopen_bank() -> void:
	var source := defaults()
	for key in ["bank_alarm","bank_shots","bank_dispatched","guards","clerks","keycard_available","keycard_taken","keycard_position","vault_open","opening_remaining","aftermath","elapsed_days","bank_cash0","bank_cash1","bank_cash2"]: data[key]=source[key]
	data.bank_cycle+=1
	_session_save()

func _session_save() -> void:
	if session!=null: session.save_game()
func snapshot() -> Dictionary: return data.duplicate(true)
func restore_snapshot(saved: Dictionary) -> bool:
	if not validate_snapshot(saved): return false
	data=saved.duplicate(true)
	data.bank_cycle=int(data.bank_cycle)
	_reset_hold()
	_intimidation=0
	return true
static func validate_snapshot(saved: Dictionary) -> bool:
	var source := defaults()
	for key in source:
		if not saved.has(key): return false
		if source[key] is bool and not saved[key] is bool: return false
	if saved.version!=1 or saved.aftermath not in ["","pending","closed"]: return false
	for key in ["bank_cycle","opening_remaining","elapsed_days","fuel_alarm_remaining","fuel_health"]:
		if typeof(saved[key]) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(saved[key])) or float(saved[key])<0: return false
	if saved.bank_cycle!=floorf(float(saved.bank_cycle)) or saved.bank_cycle>10000000 or saved.opening_remaining>3 or saved.elapsed_days>4 or saved.fuel_alarm_remaining>30 or saved.fuel_health>80: return false
	for key in ["guards","clerks","keycard_position"]:
		if not saved[key] is Array or saved[key].size()!=(3 if key=="keycard_position" else 2): return false
		for value in saved[key]:
			if typeof(value) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(value)): return false
			if key=="keycard_position":
				if absf(float(value))>20: return false
			elif float(value)<0 or float(value)>(50 if key=="guards" else 80): return false
	if saved.keycard_taken and not saved.keycard_available: return false
	if saved.keycard_available and float(saved.guards[0])>0 and float(saved.guards[1])>0: return false
	if (saved.bank_cash0 or saved.bank_cash1 or saved.bank_cash2) and not saved.vault_open: return false
	if (saved.vault_open or saved.opening_remaining>0) and (not saved.keycard_taken or not saved.bank_alarm): return false
	if saved.vault_open and saved.opening_remaining>0: return false
	if (saved.bank_dispatched or saved.bank_shots or saved.aftermath!="") and not saved.bank_alarm: return false
	if saved.fuel_dispatched and not saved.fuel_alarm: return false
	if (saved.fuel_alarm or saved.fuel_register) and not saved.fuel_initialized: return false
	return true
