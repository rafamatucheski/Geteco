extends Node
## Local scavenger quest and explicit counter choices. The session supplies
## normal interaction/HUD polling and owns atomic snapshots. Timer processing
## sleeps completely unless the register or resident hostility is cooling down.
const REWARD_ID := "tonico_old_pump"
const REWARD := 450
const TONICO_POINT := Vector3(-353,0,101)
const PUMP_POINT := Vector3(-342,0,101)
const BELT_POINT := Vector3(-397,0,133)
const CRANK_POINT := Vector3(-270,0,135)
const REACH := 2.0
const COOLER_POINT := Vector3(-364,0,85)
const PARKING_POINT := Vector3(-286,0,55)
const COMMERCE := preload("res://gameplay/urban_v1/TruckersVillageCommerce.gd")
var session
var village: Node3D
var commerce = COMMERCE.new()
var residents_manager: Node
var _tick_clock := 0.0
var _hostile_applied := false
var house_guards: Node
var _pending_guards := {"version":1,"health":{}}
var _compact_state: Dictionary = {}
var data := {"version":1,"started":false,"belt":false,"crank":false,"completed":false}

func configure(owner_session, visual: Node3D = null) -> void:
	session = owner_session
	village = visual
	set_process(false)
	set_physics_process(false)
	commerce.configure(self)
	_reconcile()
	_sync_visual()

func bind_residents(manager: Node) -> void:
	residents_manager = manager
	if manager.has_signal("attacked") and not manager.attacked.is_connected(_resident_attacked):
		manager.attacked.connect(_resident_attacked)
	_sync_hostility(true)

func bind_house_guards(guards: Node) -> void:
	house_guards=guards
	house_guards.restore_snapshot(_pending_guards)

func _resident_attacked(_actor, source) -> void:
	if source == session.world.player or source == session.world.gameplay or (is_instance_valid(source) and source.has_method("is_player_damage_source") and source.is_player_damage_source()):
		trigger_conflict(session.world.player)

func trigger_conflict(source: Node3D) -> void:
	if not _local() or session.world.gameplay.health <= 0: return
	commerce.data.hostility = COMMERCE.HOSTILITY_SECONDS
	if session.has_method("close_menu"): session.close_menu()
	_sync_hostility(true,source)
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if session == null or not session.ready_for_play: return
	_tick_clock += delta
	if _tick_clock < .25: return
	commerce.tick(_tick_clock)
	_tick_clock = 0.0
	_sync_hostility()
	set_physics_process(commerce.data.hostility > 0 or commerce.data.register_cooldown > 0)

func _sync_hostility(force := false, source: Node3D = null) -> void:
	var hostile: bool = commerce.data.hostility > 0
	if is_instance_valid(residents_manager) and (force or hostile != _hostile_applied):
		residents_manager.set_hostile(hostile,source if is_instance_valid(source) else session.world.player)
	_hostile_applied = hostile

func counter_available() -> bool:
	return _walking() and _tonico_available() and commerce.data.hostility <= 0 and session.world.player.global_position.distance_to(COOLER_POINT) <= REACH

func save_when_allowed() -> void:
	if session.has_method("save_block_reason") and not session.save_block_reason().is_empty(): return
	session.save_game()

func _local() -> bool:
	return session != null and session.ready_for_play and session.state.region_id == "harbor" and session.state.place_id.is_empty()

func _walking() -> bool:
	return _local() and session.world.gameplay.health > 0 and not session.world.driving.occupied and is_instance_valid(session.world.player)

func nearest_action() -> Dictionary:
	if not _walking(): return {}
	var point: Vector3 = session.world.player.global_position
	if point.distance_to(COOLER_POINT) <= REACH and _tonico_available() and commerce.data.hostility <= 0:
		return _action("counter", "Comprar bebida / assaltar")
	if point.distance_to(TONICO_POINT) <= REACH and _tonico_available() and commerce.data.hostility <= 0:
		return _action("tonico", "Falar com Tonico")
	if data.started and not data.completed:
		if not data.belt and point.distance_to(BELT_POINT) <= REACH:
			return _action("belt", "Pegar correia")
		if not data.crank and point.distance_to(CRANK_POINT) <= REACH:
			return _action("crank", "Pegar manivela")
	if point.distance_to(PUMP_POINT) <= REACH:
		if data.completed and commerce.data.hostility <= 0: return _action("service", "Consertar veículo na entrada · grátis")
		if data.started and data.belt and data.crank: return _action("repair", "Restaurar bomba de ar")
	return {}

func _tonico_available() -> bool:
	if not is_instance_valid(village): return true
	var actor = village.get("tonico")
	if not is_instance_valid(actor): return actor == null
	if actor.get("dead") == true: return false
	var health: Variant = actor.get("health")
	return not (health is float or health is int) or health > 0

func _action(target: String, label: String) -> Dictionary:
	return {"id":"urban_v1", "target":"truckers_village_" + target, "label":label}

func perform(target: String) -> bool:
	if target == "truckers_village_buy_drink": return commerce.buy_drink()
	if target == "truckers_village_rob_register": return commerce.rob_register()
	# Recheck location, reach and current stage instead of trusting a cached UI.
	var action := nearest_action()
	if action.is_empty() or action.target != target: return false
	target = target.trim_prefix("truckers_village_")
	match target:
		"counter":
			session._menu("Posto do Tonico")
			session._button("Comprar bebida · R$ 20 · +25 vida",_counter_action.bind("buy_drink"))
			session._button("Assaltar caixa",_counter_action.bind("rob_register"))
			session._button("Voltar",session.close_menu)
			_compact_counter_menu()
		"tonico":
			if data.completed:
				session.show_message("Tonico: Estacione na entrada e venha a pé até a bomba. O conserto é por minha conta!")
			elif not data.started:
				data.started = true
				session.show_message("Tonico: Quer levantar essa bomba velha? A correia ficou na sucata atrás das casas do oeste. A manivela está na carroça, no fundo leste.")
			else:
				session.show_message("Tonico: Agora monte as peças na bomba de ar!" if data.belt and data.crank else "Tonico: Correia na sucata do oeste; manivela na carroça do leste. Procure nos fundos das casas.")
		"belt", "crank":
			data[target] = true
			_sync_visual()
			session.show_message("Correia recuperada." if target == "belt" else "Manivela recuperada.")
		"repair":
			if not _paid() and not session.state.economy.grant_reward(REWARD_ID,REWARD):
				session.show_message("Sua carteira está cheia. Volte para concluir o conserto.")
				return false
			data.completed = true
			_sync_visual()
			session.show_message("Bomba restaurada · R$ 450. Tonico liberou consertos grátis aqui no posto!")
			session.save_game()
		"service":
			var car = _service_vehicle()
			if car == null:
				session.show_message("Estacione um veículo danificado na entrada da vila e venha a pé.")
				return false
			car.repair()
			session.show_message("Veículo consertado · cortesia do Tonico.")
			session.save_game()
		_: return false
	return true

func _counter_action(target: String) -> void:
	session.close_menu()
	perform("truckers_village_"+target)

func _compact_counter_menu() -> void:
	# Reuse input/focus/modal ownership, but remove the generic 620x440 panel
	# and its nested 580x400 scroll minimum for this three-choice counter only.
	var panel = session.get("panel")
	if not panel is PanelContainer: return
	if not _compact_state.is_empty(): _restore_counter_menu()
	var scroll: ScrollContainer = session.column.get_parent()
	var margin: MarginContainer = scroll.get_parent()
	_compact_state={"position":panel.position,"size":panel.size,"minimum":panel.custom_minimum_size,"scroll_minimum":scroll.custom_minimum_size,"separation":session.column.get_theme_constant("separation"),"close":session.menu_closed,"margins":[]}
	_compact_state.had_preferred_size=panel.has_meta("modal_preferred_size")
	_compact_state.preferred_size=panel.get_meta("modal_preferred_size") if panel.has_meta("modal_preferred_size") else null
	_compact_state.had_panel_style=panel.has_theme_stylebox_override("panel")
	_compact_state.panel_style=panel.get_theme_stylebox("panel")
	_compact_state.had_preserve_style=panel.has_meta("preserve_panel_style")
	_compact_state.preserve_style=panel.get_meta("preserve_panel_style",false)
	var style:=preload("res://ui/GameStyle.gd").panel()
	for side in ["left","right","top","bottom"]: style.set("content_margin_"+side,8)
	panel.add_theme_stylebox_override("panel",style)
	panel.set_meta("preserve_panel_style",true)
	panel.set_meta("modal_preferred_size",Vector2(350,210))
	for side in ["top","left","right","bottom"]:
		_compact_state.margins.append(margin.get_theme_constant("margin_"+side))
		margin.add_theme_constant_override("margin_"+side,12)
	scroll.custom_minimum_size=Vector2.ZERO
	panel.custom_minimum_size=Vector2(350,210)
	panel.size=Vector2(350,210)
	var viewport: Vector2 = panel.get_viewport_rect().size
	panel.position=Vector2((viewport.x-350)*.5,maxf(24,(viewport.y-210)*.5))
	session.column.add_theme_constant_override("separation",6)
	for child in session.column.get_children():
		if child is Button:
			child.custom_minimum_size.y=32
			child.add_theme_font_size_override("font_size",16)
			if child.text.begins_with("Comprar bebida"): child.text="Bebida · R$ 20 · +25 vida"
		elif child is Label: child.add_theme_font_size_override("font_size",18)
	session.menu_closed=_restore_counter_menu

func _restore_counter_menu() -> void:
	if _compact_state.is_empty(): return
	var old := _compact_state
	_compact_state={}
	var panel = session.panel
	if old.had_preferred_size: panel.set_meta("modal_preferred_size",old.preferred_size)
	else: panel.remove_meta("modal_preferred_size")
	if old.had_panel_style: panel.add_theme_stylebox_override("panel",old.panel_style)
	else: panel.remove_theme_stylebox_override("panel")
	if old.had_preserve_style: panel.set_meta("preserve_panel_style",old.preserve_style)
	else: panel.remove_meta("preserve_panel_style")
	var scroll: ScrollContainer = session.column.get_parent()
	var margin: MarginContainer = scroll.get_parent()
	scroll.custom_minimum_size=old.scroll_minimum
	panel.custom_minimum_size=old.minimum
	panel.size=old.size
	panel.position=old.position
	session.column.add_theme_constant_override("separation",old.separation)
	var sides := ["top","left","right","bottom"]
	for index in sides.size(): margin.add_theme_constant_override("margin_"+sides[index],old.margins[index])
	var previous: Callable = old.close
	if previous.is_valid(): previous.call()

func _service_vehicle():
	# The last driven car is the one captured by ProductionWorld.save_game.
	# Never service a traffic/mission vehicle merely passing through the yard.
	var car = session.world.driving.car
	if not is_instance_valid(car) or car.is_queued_for_deletion() or not car.has_method("repair"): return null
	if not session.controller.vehicles.has(car): return null
	if car.get_meta("region_id", "harbor") != "harbor" or car.get_meta("garage_suspended",false) or car.has_meta("awaiting_ground"): return null
	if not car.is_visible_in_tree() or car.controlled or car.traffic or car.health <= 0 or car.health >= car.max_health or absf(car.speed) > .15: return null
	return car if car.global_position.distance_to(PARKING_POINT) < 8.0 else null

func objective() -> String:
	if _local() and commerce.data.hostility > 0: return "Moradores armados · Afaste-se da vila!"
	if not _local() or not data.started or data.completed: return ""
	if data.belt and data.crank: return "Tonico · Volte ao posto e restaure a bomba de ar."
	if data.belt: return "Tonico · Encontre a manivela na carroça, no fundo leste da vila (1/2)."
	if data.crank: return "Tonico · Encontre a correia na sucata atrás das casas do oeste (1/2)."
	return "Tonico · Procure a correia na sucata oeste e a manivela na carroça leste (0/2)."

func snapshot() -> Dictionary:
	var saved := data.duplicate(true)
	saved.commerce = commerce.snapshot()
	saved.house_guards = house_guards.snapshot() if is_instance_valid(house_guards) else _pending_guards.duplicate(true)
	return saved

func restore_snapshot(saved: Dictionary) -> bool:
	if not validate_snapshot(saved): return false
	data = saved.duplicate(true)
	data.erase("commerce")
	data.erase("house_guards")
	_pending_guards=saved.get("house_guards",{"version":1,"health":{}}).duplicate(true)
	if is_instance_valid(house_guards): house_guards.restore_snapshot(_pending_guards)
	commerce.restore_snapshot(saved.get("commerce",{"version":1,"drink_serial":0,"robbery_serial":0,"register_cooldown":0.0,"hostility":0.0}))
	_sync_hostility(true)
	set_physics_process(commerce.data.hostility > 0 or commerce.data.register_cooldown > 0)
	_reconcile()
	_sync_visual()
	return true

static func validate_snapshot(saved: Dictionary) -> bool:
	if saved.get("version") != 1: return false
	if saved.has("commerce") and (not saved.commerce is Dictionary or not COMMERCE.validate_snapshot(saved.commerce)): return false
	if saved.has("house_guards") and (not saved.house_guards is Dictionary or not preload("res://gameplay/urban_v1/TruckersVillageHouseGuards.gd").validate_snapshot(saved.house_guards)): return false
	for key in ["started","belt","crank","completed"]:
		if typeof(saved.get(key)) != TYPE_BOOL: return false
	if (saved.belt or saved.crank or saved.completed) and not saved.started: return false
	if saved.completed and not (saved.belt and saved.crank): return false
	return true

func _paid() -> bool:
	return session != null and session.state.economy.snapshot().transactions.has("reward:" + REWARD_ID)

func _reconcile() -> void:
	# Wallet receipt is authoritative when an older quest marker is replayed.
	if _paid():
		for key in ["started","belt","crank","completed"]: data[key] = true

func _sync_visual() -> void:
	if not is_instance_valid(village): return
	village.set_part_collected("belt",data.belt)
	village.set_part_collected("crank",data.crank)
	village.set_repaired(data.completed)
