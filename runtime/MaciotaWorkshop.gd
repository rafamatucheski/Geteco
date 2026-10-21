extends Node
## Oficina da Maciota: o mecânico prepara o carro do jogador com o mesmo sistema do
## Digo (peças, vitórias, vitrine 3D). O estado é o mesmo `desert_garage` do save, por
## identidade do carro, então as peças valem nos dois mapas. Fica separado de
## DesertRuntime para não misturar com a oficina móvel do deserto.
const PANEL := preload("res://gameplay/desert_cars/DesertTuningPanel.gd")
const GARAGE := preload("res://runtime/desert/DesertGarageState.gd")
const ADAPTER := preload("res://gameplay/desert_cars/DesertCarAdapter.gd")
const PERF := preload("res://data/catalogs/VehiclePerformance.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const RACE_WINS := preload("res://systems/campaign/RaceWins.gd")
const PLACE := "maciota"
const YARD_RADIUS := 45.0
const PRESETS := ["rua","drag","terra"]
var session
var panel: CanvasLayer
var tuning_car: CharacterBody3D

func configure(owner_session) -> void:
	session = owner_session
	name = "MaciotaWorkshop"
	panel = PANEL.new()
	panel.mechanic_name = "Mecânico"
	add_child(panel)
	panel.purchase_requested.connect(_buy_part)
	panel.remove_requested.connect(_remove_part)
	panel.loadout_requested.connect(_apply_loadout)
	panel.closed.connect(_close_tuning)

func _process(_delta: float) -> void:
	if is_instance_valid(tuning_car) and (session.world.gameplay.health <= 0 or not _at_garage()):
		panel.discard_and_close()

func _at_garage() -> bool:
	return session != null and session.state.place_id == PLACE and session.state.region_id == "harbor"

## O carro do jogador que dá para preparar: parado perto da garagem (do lado de fora) ou
## dentro dela, inteiro e de um modelo que tem perfil mecânico. Veículo de serviço fica fora.
func candidate_car() -> CharacterBody3D:
	if not _at_garage() or session.world.driving.occupied: return null
	var car: CharacterBody3D = session.world.driving.car
	if not is_instance_valid(car) or car.health <= 0 or car.engine_disabled: return null
	if not PERF.eligible(str(car.archetype)): return null
	var inside := str(car.get_meta("garage_place","")) == PLACE
	var near: bool = car.global_position.distance_to(session.world.maciota_place.entry_position) <= YARD_RADIUS
	return car if inside or near else null

## `-- --no-maciota-workshop` devolve o mecânico ao comportamento antigo, para comparar
## antes/depois sem trocar arquivos de lugar (medições A/B).
static var _disabled := OS.get_cmdline_user_args().has("--no-maciota-workshop")

## Conversa com o mecânico (depois da introdução). Sempre abre o menu.
func open_menu() -> bool:
	if _disabled: return false
	tuning_car = candidate_car()
	session._menu("Mecânico")
	if is_instance_valid(tuning_car):
		session._button("Preparar "+str(FLEET.spec(tuning_car.archetype).get("label","carro")),_open_tuning)
		for preset in PRESETS:
			session._button("Salvar ajuste: "+preset,_preset.bind(preset,true))
			session._button("Aplicar ajuste: "+preset,_preset.bind(preset,false))
	else:
		session._button("Deixe seu carro perto da garagem para preparar",session.close_menu)
	session._button("Cuidar da Monaliza",func():
		session.close_menu()
		session.show_services("garage"))
	session._button("Fechar",session.close_menu)
	return true

func _race_wins() -> int:
	return RACE_WINS.count(session.state.world_state,session.state.campaign.snapshot())

func _open_tuning() -> void:
	if not is_instance_valid(tuning_car) or tuning_car != candidate_car(): session.close_menu(); return
	session.panel.hide()
	session.menu_closed = _dismiss_tuning
	var record := GARAGE.vehicle(session.state.world_state,tuning_car.vehicle_id,tuning_car.archetype)
	panel.show_vehicle(ADAPTER.profile_of(tuning_car),record.parts,record.owned,_race_wins(),session.state.economy.balance,{"archetype":tuning_car.archetype,"paint":tuning_car.paint_color})

func _close_tuning() -> void:
	if session == null: return
	_dismiss_tuning()
	session.menu_closed = Callable()
	session.close_menu()

func _dismiss_tuning() -> void:
	if is_instance_valid(panel): panel.hide()
	tuning_car = null

func _buy_part(part: String) -> void:
	if not is_instance_valid(tuning_car) or tuning_car != candidate_car(): return
	var result := GARAGE.buy(session.state.world_state,session.state.economy,tuning_car.vehicle_id,tuning_car.archetype,part,_race_wins())
	if not result.ok: panel.set_message(str(result.reason)); return
	ADAPTER.attach(tuning_car,result.parts)
	panel.confirm_application()
	session.save_game()
	_open_tuning()

func _apply_loadout(parts: Dictionary) -> void:
	if not is_instance_valid(tuning_car) or tuning_car != candidate_car(): return
	var result := GARAGE.apply_loadout(session.state.world_state,session.state.economy,tuning_car.vehicle_id,tuning_car.archetype,parts,_race_wins())
	if not result.ok: panel.set_message(str(result.reason)); return
	ADAPTER.attach(tuning_car,result.parts)
	panel.confirm_application()
	session.save_game()
	_open_tuning()

func _remove_part(slot: String) -> void:
	if not is_instance_valid(tuning_car) or tuning_car != candidate_car(): return
	var saved := GARAGE.data(session.state.world_state)
	var record := GARAGE.vehicle(session.state.world_state,tuning_car.vehicle_id,tuning_car.archetype)
	record.parts.erase(slot)
	saved.vehicles[tuning_car.vehicle_id] = record
	session.state.world_state.desert_garage = saved
	ADAPTER.attach(tuning_car,record.parts)
	session.save_game()
	_open_tuning()

func _preset(id: String, save_current: bool) -> void:
	if not is_instance_valid(tuning_car) or tuning_car != candidate_car(): session.close_menu(); return
	var saved := GARAGE.data(session.state.world_state)
	var record := GARAGE.vehicle(session.state.world_state,tuning_car.vehicle_id,tuning_car.archetype)
	if save_current: record.presets[id] = record.parts.duplicate(true)
	elif record.presets.has(id): record.parts = record.presets[id].duplicate(true)
	else: session.show_message("Nenhum ajuste salvo nesse espaço."); return
	saved.vehicles[tuning_car.vehicle_id] = record
	session.state.world_state.desert_garage = saved
	ADAPTER.attach(tuning_car,record.parts)
	session.close_menu()
	session.save_game()
