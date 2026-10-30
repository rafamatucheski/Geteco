extends SceneTree
## Contratos da espada e escudo da Cabana do Cavaleiro e da academia Ferro Velho (30/10): catálogo,
## prêmio da cabana pelo caminho real de coleta (economia + save), progressão e save da academia e as
## bibliotecas de clipes do Mixamo. Não carrega o mundo nem mede pose/terreno (ver as sondas).
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const WEAPONS := preload("res://gameplay/WeaponCatalog.gd")
const GYM := preload("res://activities/gym/GymState.gd")
const GYM_PLACE := preload("res://world/places/gym/GymPlace.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	_catalog()
	_cabin_reward()
	_gym_progress()
	_libraries()
	print("SWORD_SHIELD_GYM ", JSON.stringify({"checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)

func _catalog() -> void:
	var weapon: Dictionary = WEAPONS.get_weapon("sword_shield")
	check(not weapon.is_empty() and weapon.get("is_melee", false), "espada e escudo é arma corpo a corpo do catálogo")
	check("sword_shield" in WEAPONS.ORDER, "espada e escudo está na ordem das armas")
	var cabin: Dictionary = CATALOG.get_definition("mountain_cabin_secret")
	check(cabin.get("region", "") == "mountain", "a Cabana do Cavaleiro fica na serra")
	var rewards: Array = cabin.get("rewards", [])
	check(rewards.size() == 1 and rewards[0].get("item", "") == "sword_shield" and rewards[0].get("kind", "") == "weapon", "a cabana guarda só a espada e escudo")
	if not rewards.is_empty():
		check(str(rewards[0].id) == str(weapon.get("discovery_pickup", "")), "o id do prêmio é a descoberta que libera a arma")
	check(CATALOG.walkup_family("mountain_cabin_secret") == "cabin", "a cabana usa a porta das cabanas da serra")
	var gym: Dictionary = CATALOG.get_definition(GYM_PLACE.ID)
	check(gym.get("region", "") == "harbor" and gym.get("service", "") == "gym", "a academia está no catálogo do Harbor")
	check(preload("res://runtime/ShopSafety.gd").peaceful(GYM_PLACE.ID), "a academia é lugar pacífico")
	for station in GYM_PLACE.STATIONS:
		check(GYM.STATIONS.has(station), "aparelho %s tem atributo" % station)

func _cabin_reward() -> void:
	var cabin: Dictionary = CATALOG.get_definition("mountain_cabin_secret")
	if cabin.get("rewards", []).is_empty(): return
	var reward: Dictionary = cabin.rewards[0]
	var state: STATE = STATE.new()
	state.economy.enable_grid_inventory()
	check(not state.economy.owns_weapon("sword_shield"), "começa sem a espada e escudo")
	var granted: Dictionary = state.economy.grant_world_reward(reward)
	check(granted.ok and state.economy.owns_weapon("sword_shield"), "pegar na cabana dá a espada e escudo")
	state.world_state.rewards.append(reward.id)
	var store: STORE = STORE.new()
	store.path = "res://evidence/sword-shield-gym/save-%d.json" % Time.get_ticks_usec()
	check(store.save(state) == OK, "save com a espada salva em disco isolado")
	var loaded: STATE = STATE.new()
	check(store.load_into(loaded).ok, "save com a espada carrega")
	check(loaded.economy.owns_weapon("sword_shield"), "a espada e escudo continua com o jogador depois de carregar")
	var retry: Dictionary = loaded.economy.grant_world_reward(reward)
	check(retry.ok and not retry.get("changed", true), "o prêmio não sai duas vezes")

func _gym_progress() -> void:
	var world := {}
	check(GYM.validate_world(world), "mundo sem academia é válido")
	check(is_equal_approx(GYM.melee_damage_scale(world), 1.0) and is_equal_approx(GYM.sprint_scale(world), 1.0), "sem treino não muda nada")
	var first: Dictionary = GYM.complete_set(world, "punching_bag")
	check(first.ok and first.attribute == "strength" and first.level == 1 and first.raised, "uma série no saco sobe a força")
	check(GYM.complete_set(world, "treadmill").attribute == "stamina", "a esteira treina fôlego")
	check(not GYM.complete_set(world, "sofa").get("ok", false), "aparelho desconhecido não conta")
	for i in GYM.MAX_LEVEL + 5: GYM.complete_set(world, "push_up")
	var saved: Dictionary = GYM.data(world)
	check(int(saved.strength) == GYM.MAX_LEVEL and GYM.valid(saved), "a força para no nível máximo")
	check(is_equal_approx(GYM.melee_damage_scale(world), 1.0 + GYM.STRENGTH_DAMAGE), "força máxima dá o bônus inteiro de dano")
	check(GYM.sprint_scale(world) > 1.0 and GYM.sprint_scale(world) < 1.0 + GYM.STAMINA_SPRINT, "um nível de fôlego dá parte do bônus de corrida")
	var forged := world.duplicate(true)
	forged[GYM.KEY].strength = 15
	forged[GYM.KEY].sets = 3
	check(not GYM.validate_world(forged), "save com mais nível que séries é recusado")
	var state: STATE = STATE.new()
	GYM.complete_set(state.world_state, "speedbag")
	var store: STORE = STORE.new()
	store.path = "res://evidence/sword-shield-gym/gym-%d.json" % Time.get_ticks_usec()
	check(store.save(state) == OK, "save com treino salva")
	var loaded: STATE = STATE.new()
	check(store.load_into(loaded).ok and int(GYM.data(loaded.world_state).strength) == 1, "o treino volta do save")

func _libraries() -> void:
	var sword: AnimationLibrary = load("res://assets/dante/mixamo/dante_mixamo_sword.res")
	for clip in ["ss_idle", "ss_walk", "ss_run", "ss_block_idle", "ss_slash_downward", "ss_slash_cross", "ss_slash_power", "gs_idle", "gs_walk", "gs_run"]:
		check(sword != null and sword.has_animation(clip), "biblioteca da espada tem " + clip)
	var gym: AnimationLibrary = load("res://assets/dante/mixamo/dante_mixamo_gym.res")
	for station in GYM_PLACE.STATIONS:
		check(gym != null and gym.has_animation(station), "biblioteca da academia tem " + station)
