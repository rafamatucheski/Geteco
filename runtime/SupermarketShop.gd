extends RefCounted
## Physical access belongs to this adapter; atomic receipts/capacity to Economy.
const STOCK := ["apple", "water", "juice", "yogurt", "bread", "cereal_bar", "sandwich", "first_aid"]
const GRID := preload("res://systems/inventory/GridInventory.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")

static func available(session) -> bool:
	return session.ready_for_play and session.state.place_id == "harbor_supermarket" \
		and is_instance_valid(session.room) and session.world.gameplay.health > 0 \
		and not session.world.driving.occupied and not session.is_transition_blocked() \
		and session.world.player.global_position.distance_to(session.room.interaction_points.service) < 1.6 \
		and not session.room.threatened()

static func open(session) -> void:
	if not available(session): return
	var existing: Node = session.world.hud.get_node_or_null("SupermarketPanel")
	if is_instance_valid(existing) and not existing.is_queued_for_deletion():
		existing.refresh()
		return
	if is_instance_valid(existing): existing.get_parent().remove_child(existing)
	session._menu("")
	session.panel.hide()
	var panel := preload("res://ui/SupermarketPanel.gd").new()
	panel.session = session
	panel.name = "SupermarketPanel"
	session.world.hud.add_child(panel)
	session.menu_closed = panel.queue_free
	session._service_menu_open = true
	if session.world.hud.has_method("_sync_channels"): session.world.hud._sync_channels()

static func buy(session, id: String) -> Dictionary:
	if not available(session):
		session.close_menu()
		return {"ok":false,"reason":"unavailable"}
	if id not in STOCK and id != "armor": return {"ok":false,"reason":"unknown_item"}
	var result: Dictionary
	if id == "armor":
		result = session.state.economy.purchase_body_armor(session.world.gameplay.armor,100,session._transaction())
		if result.ok: session.world.gameplay.armor = int(result.armor)
	else:
		result = session.state.economy.purchase("supply",id,session._transaction())
	var message := "Colete equipado." if id == "armor" else "Guardado no inventário."
	if not result.ok:
		message = {"inventory_full":"Inventário cheio.","insufficient_funds":"Dinheiro insuficiente.","protection_full":"O colete já está completo."}.get(result.reason,"Compra indisponível.")
	if result.ok: session.save_game()
	open(session)
	var panel: Node = session.world.hud.get_node_or_null("SupermarketPanel")
	if is_instance_valid(panel): panel.feedback(message,result.ok)
	return result
