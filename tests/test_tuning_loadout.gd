extends SceneTree
## Um rascunho completo da oficina é pago e instalado junto, ou fica intocado.
const GARAGE := preload("res://runtime/desert/DesertGarageState.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)

func _run() -> void:
	var wallet := ECONOMY.new()
	wallet.grant_reward("tuning_loadout_fixture",10000)
	var world := {}
	var draft := {"paint":"paint_ocean","wheels":"wheels_bronze"}
	var expected := int(TUNING.PARTS.paint_ocean.cost)+int(TUNING.PARTS.wheels_bronze.cost)
	var result := GARAGE.apply_loadout(world,wallet,"customer_car","sedan_classic",draft,9)
	_check(result.ok and result.cost==expected,"loadout charges the sum once")
	_check(wallet.balance==10000-expected,"wallet debited once for both parts")
	_check(GARAGE.vehicle(world,"customer_car","sedan_classic").parts==draft,"all selected parts installed")
	_check(GARAGE.valid(world.desert_garage,wallet.snapshot()),"each purchase has a valid durable receipt")
	var before := wallet.snapshot()
	result = GARAGE.apply_loadout(world,wallet,"customer_car","sedan_classic",draft,9)
	_check(result.ok and result.cost==0 and wallet.snapshot()==before,"repeated apply is free and idempotent")
	result = GARAGE.apply_loadout(world,wallet,"customer_car","sedan_classic",{},9)
	_check(result.ok and GARAGE.vehicle(world,"customer_car","sedan_classic").parts.is_empty(),"remove all restores factory without refund")
	result = GARAGE.apply_loadout(world,wallet,"customer_car","sedan_classic",draft,0)
	_check(result.ok and wallet.snapshot()==before,"owned parts can be refitted without a second charge")
	var state_before := world.duplicate(true)
	result = GARAGE.apply_loadout(world,wallet,"customer_car","sedan_classic",{"paint":"wheels_bronze"},9)
	_check(not result.ok and world==state_before and wallet.snapshot()==before,"wrong-slot draft changes nothing")
	result = GARAGE.apply_loadout(world,wallet,"customer_car","sport_coupe",draft,9)
	_check(not result.ok and world==state_before and wallet.snapshot()==before,"identity mismatch changes nothing")
	result = GARAGE.apply_loadout(world,wallet,"customer_car","sedan_classic",{"paint":"paint_ocean","ecu":"ecu_3"},0)
	_check(not result.ok and world==state_before and wallet.snapshot()==before,"one locked part rejects the whole draft")
	var poor := ECONOMY.new()
	poor.grant_reward("poor_tuning_fixture",int(TUNING.PARTS.paint_ocean.cost))
	var poor_before := poor.snapshot()
	var empty_world := {}
	result = GARAGE.apply_loadout(empty_world,poor,"poor_car","sedan_classic",draft,9)
	_check(not result.ok and empty_world.is_empty() and poor.snapshot()==poor_before,"combined price rejects before charging any part")
	# Força uma falha tardia de recibo: o primeiro débito também precisa ser revertido.
	before = wallet.snapshot()
	_check(not wallet.spend_batch([{"amount":100,"receipt_id":"batch_first"},{"amount":100,"receipt_id":"x".repeat(111)}]),"invalid later receipt rejected")
	_check(wallet.snapshot()==before,"late failure rolls back all debits and receipts")
	_check(not wallet.spend_batch([{"amount":100,"receipt_id":"duplicate"},{"amount":100,"receipt_id":"duplicate"}]) and wallet.snapshot()==before,"duplicate batch receipt rejects atomically")
	var restored := ECONOMY.new()
	_check(restored.restore_snapshot(wallet.snapshot()),"wallet survives cold snapshot restore")
	_check(GARAGE.valid(world.desert_garage,restored.snapshot()),"loadout survives cold wallet restore")
	var roof_wallet := ECONOMY.new()
	roof_wallet.grant_reward("roof_fixture",10000)
	var roof_world := {}
	result = GARAGE.apply_loadout(roof_world,roof_wallet,"roof_car","desert_coyote",{"sunroof":"sunroof_glass"},9)
	_check(result.ok and GARAGE.valid(roof_world.desert_garage,roof_wallet.snapshot()),"compatible roof and receipt survive save validation")
	roof_world.desert_garage.vehicles.roof_car.archetype = "sedan_classic"
	_check(not GARAGE.valid(roof_world.desert_garage,roof_wallet.snapshot()),"cold save rejects incompatible owned roof even with a valid receipt")
	print("TUNING_LOADOUT ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

