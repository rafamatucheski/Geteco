extends SceneTree
## Acessórios avulsos da Union e roupas de 28/10: catálogo, compra, save e peças no Dante.
const GAME_STATE := preload("res://runtime/GameState.gd")
const CATALOG := preload("res://data/catalogs/AccessoryCatalog.gd")
const STATE := preload("res://systems/wardrobe/AccessoryState.gd")
const LOOK := preload("res://assets/outfits/DanteAccessories.gd")
const PARK := preload("res://activities/amusement_park/AmusementParkCosmeticState.gd")
const PARK_LOOK := preload("res://activities/amusement_park/AmusementParkCosmetics.gd")
const OUTFITS := preload("res://data/catalogs/OutfitCatalog.gd")
const APPEARANCE := preload("res://assets/outfits/MeshyDanteAppearance.gd")
const THERMAL := preload("res://runtime/cold/ThermalState.gd")
const ACTOR := preload("res://scripts/Actor.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("WARDROBE ", "PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	# Catálogo: tudo na vitrine existe, tem preço e um encaixe conhecido.
	var listed := {}
	var catalog_ok := CATALOG.ORDER.size() == CATALOG.ITEMS.size()
	for id in CATALOG.ORDER:
		listed[id] = true
		var spec: Dictionary = CATALOG.ITEMS.get(id, {})
		if spec.is_empty() or spec.slot not in CATALOG.SLOTS or int(spec.price) <= 0 or str(spec.name).is_empty(): catalog_ok = false
	check(catalog_ok and listed.size() == CATALOG.ITEMS.size(), "catálogo de acessórios coerente (%d itens)" % CATALOG.ITEMS.size())
	var outfits_ok := true
	for id in OUTFITS.ORDER:
		if not OUTFITS.OUTFITS.has(id) or not APPEARANCE.OUTFITS.has(id): outfits_ok = false; print("  roupa sem aparência: ", id)
	check(outfits_ok and OUTFITS.ORDER.size() >= 18, "toda roupa da loja tem aparência no Dante (%d)" % OUTFITS.ORDER.size())
	check(THERMAL.PROTECTION.has("dante_puffer") and THERMAL.PROTECTION.dante_puffer > .5, "puffer protege do frio")

	# Compra, uso e save.
	var state = GAME_STATE.new()
	var world: Dictionary = state.world_state
	check(STATE.purchase(world, state.economy, "aviator_gold") == "insufficient_funds" and not STATE.owns(world, "aviator_gold"), "sem dinheiro não compra")
	state.economy.grant_reward("test:wardrobe", 5000)
	var before: int = state.economy.balance
	check(STATE.purchase(world, state.economy, "aviator_gold") == "purchased" and state.economy.balance == before - 550, "compra cobra o preço do aviador")
	check(STATE.purchase(world, state.economy, "aviator_gold") == "already_owned" and state.economy.balance == before - 550, "segunda compra não cobra de novo")
	check(not STATE.equip(world, "fedora_black"), "não usa o que não comprou")
	check(STATE.equip(world, "aviator_gold") and STATE.equipped(world).get("eyes") == "aviator_gold", "aviador vai para os olhos")
	STATE.purchase(world, state.economy, "fedora_black")
	STATE.purchase(world, state.economy, "hockey")
	STATE.purchase(world, state.economy, "chain_gold")
	check(STATE.equip(world, "fedora_black") and STATE.equip(world, "chain_gold"), "chapéu e corrente juntos")
	var snapshot: Dictionary = state.snapshot()
	var restored = GAME_STATE.new()
	check(restored.restore_snapshot(snapshot) and STATE.equipped(restored.world_state) == {"head":"fedora_black", "eyes":"aviator_gold", "neck":"chain_gold"}, "acessórios voltam do save")
	var corrupt: Dictionary = state.snapshot()
	corrupt.world[STATE.KEY].face = "hockey"
	corrupt.world[STATE.KEY].owned.erase("hockey")
	check(not GAME_STATE.new().restore_snapshot(corrupt), "save com máscara não comprada é recusado")
	corrupt = state.snapshot()
	corrupt.world[STATE.KEY].head = "aviator_gold"
	check(not GAME_STATE.new().restore_snapshot(corrupt), "save com óculos no encaixe da cabeça é recusado")
	var legacy: Dictionary = state.snapshot()
	legacy.world.erase(STATE.KEY)
	check(GAME_STATE.new().restore_snapshot(legacy), "save antigo sem acessórios continua válido")

	# Parque e Union não somam óculos no mesmo rosto.
	world[PARK.KEY] = {"version":1, "found":["star_glasses"], "glasses":"star_glasses", "mask":""}
	check(STATE.equip(world, "aviator_gold") and PARK.data(world).glasses == "", "óculos da Union tiram os do parque")
	STATE.yield_to_park(world, "glasses")
	check(not STATE.equipped(world).has("eyes") and STATE.equipped(world).get("head") == "fedora_black", "óculos do parque tiram só os da Union")

	# Peças no Dante: roupa com boné e óculos próprios cede o lugar.
	var stage := Node3D.new()
	root.add_child(stage)
	var player = ACTOR.new()
	player.is_player = true
	stage.add_child(player)
	player.set_physics_process(false)
	check(player.set_outfit("dante_badboy"), "regata com boné e óculos vestida")
	LOOK.apply(player, {"head":"fedora_black", "eyes":"aviator_gold", "neck":"chain_gold"})
	var skeleton: Skeleton3D = player.skeleton
	check(pieces(skeleton, "fedora_black") > 0 and pieces(skeleton, "aviator_gold") > 0 and pieces(skeleton, "chain_gold") > 0, "fedora, aviador e corrente montados")
	check(not baked_visible(skeleton, ["cap_backwards", "shades"]), "boné e óculos da roupa somem sob os da Union")
	LOOK.apply(player, {"face":"hockey", "eyes":"aviator_gold"})
	check(pieces(skeleton, "hockey") > 0 and pieces(skeleton, "aviator_gold") == 0 and pieces(skeleton, "fedora_black") == 0, "máscara de hóquei tapa os óculos e remontar tira o chapéu")
	player.set_outfit("dante_badboy")
	LOOK.apply(player, {})
	check(baked_visible(skeleton, ["cap_backwards", "shades"]) and not has_wardrobe_nodes(skeleton), "sem acessórios a roupa volta inteira")
	# Óculos do parque com máscara de hóquei por cima também somem.
	var park_world := {PARK.KEY:{"version":1, "found":["amber_glasses"], "glasses":"amber_glasses", "mask":""}}
	PARK_LOOK.apply(player, park_world)
	LOOK.apply(player, {"face":"hockey"})
	check(not park_glasses_visible(skeleton), "máscara de hóquei esconde os óculos do parque")
	# Cada acessório e cada roupa nova monta sem erro.
	var every_ok := true
	for id in CATALOG.ORDER:
		LOOK.apply(player, {CATALOG.ITEMS[id].slot: id})
		if pieces(skeleton, id) == 0: every_ok = false; print("  sem peça: ", id)
	check(every_ok, "todos os acessórios montam peças")
	var outfit_ok := true
	for id in ["dante_biker", "dante_hoodie", "dante_tracksuit", "dante_varsity", "dante_mechanic", "dante_urban_camo", "dante_tuxedo", "dante_puffer"]:
		if not player.set_outfit(id): outfit_ok = false; print("  roupa falhou: ", id)
	check(outfit_ok, "roupas novas vestem no Dante")
	stage.free()
	print("%s wardrobe accessories: %d checks" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func pieces(skeleton: Skeleton3D, id: String) -> int:
	var count := 0
	for mount in skeleton.get_children():
		if not String(mount.name).begins_with(LOOK.PREFIX): continue
		for space in mount.get_children():
			for piece in space.get_children():
				if piece.get_meta("wardrobe_accessory", "") == id: count += 1
	return count

func has_wardrobe_nodes(skeleton: Skeleton3D) -> bool:
	for mount in skeleton.get_children():
		if String(mount.name).begins_with(LOOK.PREFIX): return true
	return false

func baked_visible(skeleton: Skeleton3D, kinds: Array) -> bool:
	var found := 0
	for mount in skeleton.get_children():
		if not String(mount.name).begins_with("MeshyOutfit"): continue
		for space in mount.get_children():
			for piece in space.get_children():
				if piece.get_meta("outfit_accessory_kind", "") in kinds:
					if not piece.visible: return false
					found += 1
	return found > 0

func park_glasses_visible(skeleton: Skeleton3D) -> bool:
	var mount := skeleton.get_node_or_null("ParkCosmetics")
	if mount == null: return false
	for space in mount.get_children():
		for piece in space.get_children():
			if piece.get_meta("cosmetic_slot", "") == "glasses" and piece.visible: return true
	return false
