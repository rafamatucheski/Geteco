extends RefCounted
## O recibo da carteira também é a unidade de estoque: débito, entrega e estoque se efetivam juntos.
const ECONOMY := preload("res://systems/economy/Economy.gd")
const GRID := preload("res://systems/inventory/GridInventory.gd")
const MACHINES := {
	"drinks":{"name":"Aurora", "position":Vector3(34,0,6), "approach":Vector3(34,.08,7.4), "items":{"water":24,"juice":16}},
	"snacks":{"name":"Pingo", "position":Vector3(23,0,30), "approach":Vector3(23,.08,28.6), "items":{"cereal_bar":16,"sandwich":12}},
}
var session
var site: Node3D
var opened := ""

func configure(owner_session) -> void: session = owner_session

func set_site(value: Node3D) -> void:
	site = value
	if not is_instance_valid(site) and not opened.is_empty(): session.close_menu()

func _available(machine: String, allow_menu := false) -> bool:
	if not MACHINES.has(machine) or not is_instance_valid(site) or not site.is_inside_tree(): return false
	if site.get_tree().paused or not session.ready_for_play or session.is_transition_blocked(): return false
	if session.state.region_id != "harbor" or not session.state.place_id.is_empty(): return false
	if session.world.gameplay.health <= 0 or session.world.driving.occupied: return false
	if session.modal and (not allow_menu or opened != machine): return false
	if session.world.player.input_locked and (not allow_menu or opened != machine): return false
	var player: Node3D = session.world.player
	var approach: Vector3 = site.to_global(MACHINES[machine].approach)
	if player.global_position.distance_to(approach) > 1.65: return false
	var ray := PhysicsRayQueryParameters3D.create(player.global_position+Vector3.UP*.8,approach+Vector3.UP*.8,1)
	return player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func nearest_action() -> Dictionary:
	for id: String in MACHINES:
		if _available(id): return {"id":"amusement_park", "target":"vending:"+id, "label":"Comprar em "+str(MACHINES[id].name)}
	return {}

func _receipt(machine: String, item: String, unit: int) -> String:
	return "park_vending_%s_%s_%d" % [machine,item,unit]

func offer_token(machine: String, item: String) -> String:
	if not MACHINES.has(machine) or not MACHINES[machine].items.has(item): return ""
	var receipts: Dictionary = session.state.economy.snapshot().transactions
	for unit in range(1,int(MACHINES[machine].items[item])+1):
		var token := _receipt(machine,item,unit)
		if not receipts.has("purchase:"+token): return token
	return ""

func remaining(machine: String, item: String) -> int:
	if not MACHINES.has(machine) or not MACHINES[machine].items.has(item): return 0
	var receipts: Dictionary = session.state.economy.snapshot().transactions
	var available := 0
	for unit in range(1,int(MACHINES[machine].items[item])+1):
		if not receipts.has("purchase:"+_receipt(machine,item,unit)): available += 1
	return available

func open(machine: String) -> bool:
	if not _available(machine,opened == machine): return false
	opened = machine
	session._menu("%s · R$ %d" % [MACHINES[machine].name,session.state.economy.balance])
	session.menu_closed = func(): opened = ""
	for item: String in MACHINES[machine].items:
		var amount := remaining(machine,item)
		var token := offer_token(machine,item)
		var label: String = GRID.spec(item).label
		var text := String(TranslationServer.translate("%s · R$ %d · %d disponíveis")) % [label,ECONOMY.SUPPLIES[item].price,amount] if amount > 0 else label+" · Esgotado"
		session._button(text,func(): buy(machine,item,token))
	session._button("Fechar",session.close_menu)
	return true

func buy(machine: String, item: String, token: String) -> Dictionary:
	if not _available(machine,true):
		if not opened.is_empty(): session.close_menu()
		return {"ok":false,"reason":"unavailable"}
	if not MACHINES[machine].items.has(item): return {"ok":false,"reason":"unknown_item"}
	var valid_token := false
	for unit in range(1,int(MACHINES[machine].items[item])+1):
		if token == _receipt(machine,item,unit): valid_token = true; break
	if not valid_token:
		session.show_message("Produto esgotado." if token.is_empty() else "Compra indisponível.")
		return {"ok":false,"reason":"out_of_stock" if token.is_empty() else "invalid_transaction"}
	# Um botão pendente pode ser entregue duas vezes; a Economy repete o recibo.
	var result: Dictionary = session.state.economy.purchase("supply",item,token)
	if result.ok and result.reason == "purchased":
		session.save_game()
		session.show_message("Guardado no inventário.")
	elif not result.ok:
		session.show_message({"inventory_full":"Inventário cheio.","insufficient_funds":"Dinheiro insuficiente."}.get(result.reason,"Compra indisponível."))
	open(machine)
	return result
