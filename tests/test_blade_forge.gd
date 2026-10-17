extends SceneTree
## Regras da Forja da Serra sem sessão: preços, efeito no combate, normalização do save
## (inclusive números que voltam do JSON como float), recibos obrigatórios, lendária só
## depois da pista, save antigo com ingresso do zoológico e o visual da lâmina lendária.
const FORGE := preload("res://gameplay/forge/BladeForge.gd")
const CUSTOM := preload("res://gameplay/WeaponCustomization.gd")
const CATALOG := preload("res://gameplay/WeaponCatalog.gd")
const STATE := preload("res://runtime/GameState.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const VISUALS := preload("res://gameplay/WeaponAttachmentVisuals.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func run() -> void:
	_rules()
	_save()
	_visuals()
	print("BLADE_FORGE ", checks, " checks ", "PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)

func _rules() -> void:
	var custom := {}
	var base: Dictionary = CATALOG.get_weapon("axe")
	check(FORGE.offer(custom, "met", "axe", "edge").price == 600, "Axe edge level 1 price")
	check(not FORGE.offer(custom, "met", "axe", "legendary").ok, "Legendary locked before the trail")
	check(not FORGE.offer(custom, "done", "axe", "legendary").ok, "Legendary needs both tracks at max")
	for track in FORGE.TRACKS:
		for i in FORGE.MAX_LEVEL: FORGE.install(custom, "axe", track)
	check(FORGE.level(custom, "axe", "edge") == 2 and FORGE.level(custom, "axe", "temper") == 2, "Levels install in order")
	check(not FORGE.offer(custom, "done", "axe", "edge").ok, "No level past the maximum")
	var two: Dictionary = CUSTOM.effective_data("axe", custom)
	check(int(two.damage) == roundi(float(base.damage)*1.24), "Edge 2 adds 24%% damage: %s" % two.damage)
	check(is_equal_approx(float(two.fire_interval), float(base.fire_interval)*.84), "Temper 2 shortens the swing 16%")
	check(FORGE.offer(custom, "done", "axe", "legendary").ok, "Legendary offered after the trail at max levels")
	FORGE.install(custom, "axe", "legendary")
	var legend: Dictionary = CUSTOM.effective_data("axe", custom)
	check(int(legend.damage) == roundi(float(base.damage)*1.24*1.25), "Legendary multiplies damage again")
	check(is_equal_approx(float(legend.melee_range), float(base.melee_range)*1.1), "Legendary adds reach")
	# Katana não tem peças de bancada, mas a forja grava na mesma estrutura e sobrevive à normalização.
	FORGE.install(custom, "katana", "edge")
	var normalized := CUSTOM.normalize(custom)
	check(normalized == custom, "Normalization keeps forge entries, katana included")
	var from_json: Variant = JSON.parse_string(JSON.stringify(custom))
	check(CUSTOM.normalize(from_json) == from_json, "Normalization is idempotent after JSON (floats)")
	check(int(CUSTOM.effective_data("katana", from_json).damage) == roundi(float(CATALOG.get_weapon("katana").damage)*1.12), "Katana edge applies from saved floats")
	check(CUSTOM.effective_data("pistol", custom) == CUSTOM.effective_data("pistol", {}), "Firearms untouched")
	var forged := {"knife":{"owned":false, "installed":false, "owned_parts":[], "parts":{}, "forge":{"edge":7}}}
	check(not CUSTOM.normalize(forged).has("knife"), "Out-of-range level dropped by normalization")

func _wallet_with(receipts: Array) -> Dictionary:
	var state = STATE.new()
	state.economy.grant_reward("forge_test_cash", 50000)
	for item in receipts: check(state.spend(int(item[1]), str(item[0])), "Spend " + str(item[0]))
	return state.economy.snapshot()

func _save() -> void:
	var data: Dictionary = FIXTURE.full_snapshot(Vector3(80,0,80), true)
	check(not data.is_empty(), "Fixture save")
	if data.is_empty(): return
	var knife := {"knife":{"owned":false, "installed":false, "owned_parts":[], "parts":{}, "forge":{"edge":1}}}
	data.combat = {"health":100, "armor":0, "crime_points":0, "hidden_time":0, "customization":knife}
	check(not STATE.new().restore_snapshot(data), "Unpaid forge level rejected")
	data.economy = _wallet_with([[FORGE.receipt("knife", "edge", 1), FORGE.price("knife", "edge", 1)]])
	check(STATE.new().restore_snapshot(data), "Paid forge level accepted")
	var json_round: Dictionary = JSON.parse_string(JSON.stringify(data))
	check(STATE.new().restore_snapshot(json_round), "Paid forge level accepted after JSON round trip")
	var legend: Dictionary = data.duplicate(true)
	legend.combat.customization.knife.forge = {"edge":2, "temper":2, "legendary":true}
	legend.economy = _wallet_with([
		[FORGE.receipt("knife", "edge", 1), 400], [FORGE.receipt("knife", "edge", 2), 1200],
		[FORGE.receipt("knife", "temper", 1), 400], [FORGE.receipt("knife", "temper", 2), 1200],
		[FORGE.receipt("knife", "legendary"), 3500]])
	legend.world.blade_forge = {"version":1, "stage":"has_ore"}
	check(not STATE.new().restore_snapshot(legend), "Legendary rejected before the trail is done")
	legend.world.blade_forge.stage = "done"
	check(STATE.new().restore_snapshot(legend), "Legendary accepted with receipts and finished trail")
	legend.world.blade_forge.stage = "anywhere"
	check(not STATE.new().restore_snapshot(legend), "Unknown trail stage rejected")
	# Save de antes da troca: o ingresso do zoológico é descartado sem invalidar o save.
	var legacy: Dictionary = FIXTURE.full_snapshot(Vector3(80,0,80), true)
	legacy.world.mountain_zoo = {"version":1, "active":true, "inside":false, "serial":3, "receipt":"mountain_zoo_3"}
	var restored = STATE.new()
	check(restored.restore_snapshot(legacy), "Legacy save with zoo ticket still loads")
	check(not restored.world_state.has("mountain_zoo"), "Zoo ticket dropped on load")

func _visuals() -> void:
	for id in ["knife", "axe", "katana"]:
		var root := Node3D.new()
		if id == "katana": preload("res://gameplay/KatanaModel.gd").build(root, false)
		else: preload("res://gameplay/ArsenalWeapon3D.gd").build(root, id)
		VISUALS.apply(root, id, {"forge":{"edge":2, "temper":2, "legendary":true}}, Vector3.ZERO)
		var glowing := 0
		var dark := 0
		for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			var used: Array = [mesh.material_override]
			for surface in mesh.mesh.get_surface_count(): used.append(mesh.get_surface_override_material(surface))
			if VISUALS.legendary_glow() in used: glowing += 1
			if VISUALS.legendary_steel() in used: dark += 1
		check(glowing >= 1 and dark >= 1, "%s legendary: dark steel and glowing edge (%d/%d)" % [id, dark, glowing])
		var plain := Node3D.new()
		if id == "katana": preload("res://gameplay/KatanaModel.gd").build(plain, false)
		else: preload("res://gameplay/ArsenalWeapon3D.gd").build(plain, id)
		VISUALS.apply(plain, id, {"forge":{"edge":2}}, Vector3.ZERO)
		check(not plain.find_children("*", "MeshInstance3D", true, false).any(func(m): return m.material_override == VISUALS.legendary_glow()), id + " without legendary keeps its steel")
		root.free()
		plain.free()
