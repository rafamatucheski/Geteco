extends Node
## Polled by the park runtime at 0.15 s; pickups have no physics/process callback.
const STATE := preload("res://activities/amusement_park/AmusementParkCosmeticState.gd")
const ART := preload("res://activities/amusement_park/AmusementParkCosmeticArt.gd")
const COSMETICS := preload("res://activities/amusement_park/AmusementParkCosmetics.gd")
const AUDIO := preload("res://gameplay/RewardAudio.gd")
const POINTS := {
	"lume_jacket":Vector3(-31,.12,27),
	"midnight_coat":Vector3(28,.12,27),
	"star_glasses":Vector3(-2,.20,-28),
	"amber_glasses":Vector3(31,.20,-3),
	"ghost_mask":Vector3(-6.4,.20,-5.2),
	"fox_mask":Vector3(6.4,.20,-5.2),
}
var session
var site: Node3D
var haunted: Node3D
var pickups: Dictionary = {}

func configure(owner_session) -> void:
	session = owner_session
	set_process(false)

func set_location(park_site: Node3D, haunted_room: Node3D) -> void:
	site = park_site
	haunted = haunted_room
	refresh()

func refresh() -> void:
	if session == null: return
	var found: Array = STATE.data(session.state.world_state).get("found", [])
	for id in STATE.ENTRIES:
		var parent: Variant = haunted if STATE.ENTRIES[id].location == "haunted" else site
		var existing: Variant = pickups.get(id)
		if is_instance_valid(existing):
			if existing.get_parent() == parent and not found.has(id): continue
			existing.free()
		pickups.erase(id)
		if not is_instance_valid(parent) or found.has(id): continue
		var item := ART.pickup(id)
		item.name = "ParkSecret_" + id
		item.position = POINTS[id]
		item.set_meta("park_secret_id", id)
		parent.add_child(item)
		pickups[id] = item

func collect_nearby() -> int:
	if not _can_collect(): return 0
	var count := 0
	for id in pickups.keys():
		var item: Variant = pickups[id]
		if not is_instance_valid(item) or not item.is_visible_in_tree(): continue
		var location: String = STATE.ENTRIES[id].location
		if location == "haunted" and session.state.place_id != "harbor_haunted_house": continue
		if location == "park" and not session.state.place_id.is_empty(): continue
		var player: Node3D = session.world.player
		if player.global_position.distance_to(item.global_position) > 1.1: continue
		# Prevent collecting through a wall or shelf from the next corridor.
		var from := player.global_position + Vector3.UP*.65
		var to: Vector3 = item.global_position + Vector3.UP*.35
		var query := PhysicsRayQueryParameters3D.create(from, to, 1, [player.get_rid()])
		if not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): continue
		if not STATE.collect(session.state.world_state, session.state.economy, id): continue
		count += 1
		item.free()
		pickups.erase(id)
		session.show_message(String(TranslationServer.translate("Encontrado: %s · disponível no guarda-roupa.")) % STATE.ENTRIES[id].label)
	if count > 0:
		AUDIO.play(self, "collectible")
		_save()
	return count

func _can_collect() -> bool:
	return session != null and session.state.region_id == "harbor" and not session.modal \
		and not session.is_transition_blocked() and session.world.gameplay.health > 0 \
		and not session.world.driving.occupied and not session.world.player.input_locked

func open_wardrobe() -> void:
	if not _can_collect(): return
	_show_wardrobe()

func _show_wardrobe() -> void:
	var saved := STATE.data(session.state.world_state)
	session._menu(String(TranslationServer.translate("GUARDA-ROUPA LUME · %d/6")) % saved.found.size())
	for id in saved.found:
		var entry: Dictionary = STATE.ENTRIES[id]
		var selected: bool = session.state.economy.outfit == entry.get("outfit", "") if entry.slot == "outfit" else saved[entry.slot] == id
		session._button(str(entry.label) + (" · equipado" if selected else " · vestir"), _equip.bind(id))
	if session.state.economy.outfit in ["dante_lume", "dante_midnight"]:
		session._button("Vestir roupa original", _classic)
	if not saved.glasses.is_empty(): session._button("Retirar óculos", _remove.bind("glasses"))
	if not saved.mask.is_empty(): session._button("Retirar máscara", _remove.bind("mask"))
	session._button("Voltar", session.close_menu)

func _equip(id: String) -> void:
	if not _wardrobe_alive(): return
	if not STATE.equip(session.state.world_state, session.state.economy, id): return
	# Óculos ou máscara do parque tiram o da Union do mesmo lugar do rosto.
	if STATE.ENTRIES[id].slot != "outfit":
		preload("res://systems/wardrobe/AccessoryState.gd").yield_to_park(session.state.world_state, STATE.ENTRIES[id].slot)
	session.apply_outfit()
	_save()
	_show_wardrobe()

func _classic() -> void:
	if not _wardrobe_alive(): return
	if session.state.economy.equip_outfit("dante_classic"):
		session.apply_outfit()
		_save()
	_show_wardrobe()

func _remove(slot: String) -> void:
	if not _wardrobe_alive(): return
	if STATE.remove(session.state.world_state, slot):
		# Remonta a roupa inteira: os óculos da roupa e os da Union dependem dessa ordem.
		session.apply_outfit()
		_save()
	_show_wardrobe()

func _wardrobe_alive() -> bool:
	return session != null and session.modal and session.world.gameplay.health > 0 \
		and not session.is_transition_blocked() and not session.world.driving.occupied

func _save() -> void:
	# FullSession already queues an automatic checkpoint when saving is blocked.
	session.save_game()

func _exit_tree() -> void:
	for item in pickups.values():
		if is_instance_valid(item): item.queue_free()
	pickups.clear()
