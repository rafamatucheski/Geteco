extends Node
## Player-operated line: the service owns passenger identities; Driving owns Dante.
var service: Node3D
var world
var active_bus: CharacterBody3D
var panel: PanelContainer
var text: Label
var offer: Label
var notice := ""
var notice_age := 0.0
var _hud_clock := 0.0
var _initial_passengers: Array = []
var _exchange_age := 0.0
var _exchange_done := false

func configure(owner_service: Node3D) -> void:
	service=owner_service; world=service.controller.world

func _ready() -> void:
	panel=PanelContainer.new(); panel.position=Vector2(380,76)
	panel.custom_minimum_size=Vector2(530,76); panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	text=Label.new(); text.add_theme_font_size_override("font_size",18)
	text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(text); world.hud.add_child(panel); panel.hide()
	offer=Label.new(); offer.position=Vector2(380,575); offer.size=Vector2(540,35)
	offer.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; offer.add_theme_font_size_override("font_size",20)
	offer.mouse_filter=Control.MOUSE_FILTER_IGNORE; world.hud.add_child(offer); offer.hide()

func hint(action: String) -> String:
	var controls=get_node_or_null("/root/GameInput")
	return controls.hint(action) if controls!=null else str({"bus_driver_shift":"B","bus_doors":"O","exit_vehicle":"F"}.get(action,"—"))

func nearby_bus():
	if world.session==null or not world.session.ready_for_play or world.session.modal: return null
	if world.player.input_locked or world.driving.occupied or world.driving.is_body_transition_active(): return null
	if service.controller.state.region_id!="harbor" or not service.controller.state.place_id.is_empty(): return null
	var option: Dictionary=world.driving._entry_option()
	var bus=option.get("car")
	if not is_instance_valid(bus) or not service.fleet.has(bus) or bus.stolen or absf(bus.speed)>.1: return null
	return bus if bus.driver_shift or bus.service_state=="exchange" else null

func start(bus: CharacterBody3D) -> bool:
	if nearby_bus()!=bus: return false
	var was_duty: bool=bus.driver_shift
	var was_traffic: bool=bus.traffic
	bus.driver_shift=true; bus.traffic=false; bus.stop_boarding_motion(); bus._release_tokens()
	bus.set_meta("duty_entry",true)
	var entered: bool=world.driving._begin_entry(bus,1)
	bus.remove_meta("duty_entry")
	if not entered:
		bus.driver_shift=was_duty; bus.traffic=was_traffic; return false
	if bus.work_state.is_empty(): bus.work_state={"next_stop":maxi(0,bus.service_stop),"stops":0,"earned":0,"laps":0}
	bus.work_state.next_stop=int(bus.work_state.next_stop)%service.stops.size()
	bus.set_doors(0); bus.service_state="player_line"
	active_bus=bus; _exchange_done=false; _exchange_age=0; _initial_passengers.clear()
	notice="Linha 510 iniciada"; notice_age=3
	return true

func target_position() -> Vector3:
	if not is_instance_valid(active_bus) or active_bus.work_state.is_empty(): return Vector3.INF
	return service.path_poses.front(float(service.stops[int(active_bus.work_state.next_stop)].offset)).origin

func docked(bus: CharacterBody3D) -> bool:
	if absf(bus.speed)>.15 or bus.work_state.is_empty(): return false
	var index: int=int(bus.work_state.next_stop)%service.stops.size()
	var expected: Array[Transform3D]=service.path_poses.at(float(service.stops[index].offset))
	for part in 3:
		var gap: Vector3=bus.sections[part].global_position-expected[part].origin; gap.y=0
		if gap.length()>1.75 or absf(angle_difference(bus.sections[part].rotation.y,expected[part].basis.get_euler().y))>deg_to_rad(12): return false
	return true

func toggle_doors() -> bool:
	if not is_instance_valid(active_bus) or not world.driving.occupied or world.driving.car!=active_bus or world.driving.is_body_transition_active(): return false
	var bus=active_bus
	if bus.door_amount>.5:
		if not _exchange_done or _exchange_age<2 or service.doorway_occupied(bus):
			notice="Aguarde o embarque e libere as portas"; notice_age=3; return false
		bus.set_doors(0); service.gate(bus.service_stop,false)
		complete_stop(bus); return true
	if not docked(bus): notice="Pare e alinhe o ônibus na parada indicada"; notice_age=3; return false
	bus.service_stop=int(bus.work_state.next_stop)%service.stops.size()
	_initial_passengers.clear()
	for person in bus.passengers: _initial_passengers.append(person.id)
	_exchange_age=0; _exchange_done=false
	bus.set_doors(1); service.gate(bus.service_stop,true)
	return true

func complete_stop(bus: CharacterBody3D) -> void:
	var boarded := 0
	for person in bus.passengers:
		if not _initial_passengers.has(person.id): boarded+=1
	bus.work_state.stops=int(bus.work_state.stops)+1
	bus.work_state.next_stop=(int(bus.work_state.next_stop)+1)%service.stops.size()
	var amount := 12+boarded*2
	if int(bus.work_state.stops)%service.stops.size()==0:
		bus.work_state.laps=int(bus.work_state.laps)+1; amount+=60
	if world.session.state.economy.collect_loose_cash(amount,"Linha 510"):
		bus.work_state.earned=int(bus.work_state.earned)+amount
		notice="Parada atendida"
	else: notice="Parada atendida · carteira cheia"
	notice_age=4; _exchange_done=false; _exchange_age=0

func tick(bus: CharacterBody3D, delta: float) -> void:
	if active_bus!=bus:
		if world.driving.occupied and world.driving.car==bus and bus.driver_shift:
			active_bus=bus; _exchange_done=false; _exchange_age=0
		else: return
	if not bus.controlled or world.driving.is_body_transition_active(): return
	if bus.health<=0 or bus.stolen or service.controller.state.region_id!="harbor": finish(); return
	if bus.door_amount>.5:
		bus.stop_boarding_motion(); _exchange_age+=delta
		_exchange_done=service.exchange(bus)

func finish() -> void:
	if is_instance_valid(active_bus):
		if active_bus.door_amount>0 and active_bus.service_stop>=0: service.gate(active_bus.service_stop,false)
		active_bus.set_doors(0)
		for person in service.people:
			if person.stop==active_bus.service_stop and person.phase in ["boarding","to_door"]:
				person.phase="waiting"
				if is_instance_valid(person.actor): person.actor.automatic_direction=Vector3.ZERO
	active_bus=null; _exchange_done=false
	if is_instance_valid(panel): panel.hide()

func _input(event: InputEvent) -> void:
	if event.is_echo() or world.session==null or world.session.modal or world.driving._external_transition_blocked(): return
	if event.is_action_pressed("bus_driver_shift"):
		var bus=nearby_bus()
		if bus!=null and start(bus): get_viewport().set_input_as_handled()
	elif event.is_action_pressed("bus_doors") and is_instance_valid(active_bus):
		toggle_doors(); get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not is_instance_valid(world) or world.session==null or not world.session.ready_for_play: return
	if is_instance_valid(active_bus) and (not world.driving.occupied or world.driving.car!=active_bus or active_bus.stolen): finish()
	_hud_clock+=delta; notice_age=maxf(0,notice_age-delta)
	if _hud_clock<.15: return
	_hud_clock=0
	var driving: bool=is_instance_valid(active_bus) and world.driving.occupied and not world.session.modal
	panel.visible=driving; offer.visible=not driving and nearby_bus()!=null
	if offer.visible: offer.text=String(TranslationServer.translate("%s  Jogar de motorista · linha 510")) % hint("bus_driver_shift")
	if not driving: return
	var bus=active_bus
	var index: int=int(bus.work_state.next_stop)%service.stops.size()
	var distance := roundi(bus.global_position.distance_to(target_position()))
	var action := "Fechar portas" if bus.door_amount>.5 else "Abrir portas"
	text.text=String(TranslationServer.translate("Linha 510 · %s · %d m\n%s  %s   |   %d passageiros   |   %d paradas   |   R$ %d\n%s")) % [str(service.stops[index].definition.name),distance,hint("bus_doors"),action,bus.passengers.size(),bus.work_state.stops,bus.work_state.earned,notice if notice_age>0 else hint("exit_vehicle")+"  Sair do ônibus"]

func _exit_tree() -> void:
	if is_instance_valid(panel): panel.queue_free()
	if is_instance_valid(offer): offer.queue_free()
