extends SceneTree
## Catálogo de peças da bancada: cada peça cabe só nas armas que declara, muda
## de fato os números lidos pelo combate e monta o visual sem erro. Não precisa
## de sessão; roda em headless (não aprova aparência).

const CUSTOM := preload("res://gameplay/WeaponCustomization.gd")
const ART := preload("res://assets/regions/source/guns/ammunation/AmmunationArt.gd")

var failures: Array[String] = []
var checks := 0

func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("ARSENAL_PARTS FAIL " + label + ((" | " + detail) if not detail.is_empty() else ""))

func state_with(id: String, part: String) -> Dictionary:
	return {id: {"owned":false, "installed":false, "owned_parts":[part], "parts":{CUSTOM.PARTS[part].slot: part}}}

func _initialize() -> void:
	# Armas brancas não herdam acabamento, laser ou bocal de arma de fogo.
	for id in CUSTOM.MELEE:
		for part in ["matte", "chrome", "laser_red", "suppressor", "extended"]:
			check(not CUSTOM.supports(id, part), "%s recusa %s" % [id, part])
		var slots := {}
		for part in CUSTOM.PARTS:
			if CUSTOM.supports(id, part): slots[CUSTOM.PARTS[part].slot] = true
		check(slots.has("edge") and slots.has("finish"), "%s tem slot próprio e acabamento próprio" % id, str(slots.keys()))
	# Cada arma personalizável tem pelo menos três abas com opções.
	for id in CUSTOM.CUSTOMIZABLE:
		var slots := {}
		for part in CUSTOM.PARTS:
			if part != "flashlight" and CUSTOM.supports(id, part): slots[CUSTOM.PARTS[part].slot] = true
		check(slots.size() >= 3, "%s oferece variedade" % id, str(slots.keys()))
	# Toda peça com modificador muda os dados efetivos do combate e monta visual.
	var root := Node3D.new()
	get_root().add_child(root)
	var tested := 0
	for part in CUSTOM.PARTS:
		if part == "flashlight": continue
		var info: Dictionary = CUSTOM.PARTS[part]
		for id in info.get("for", []):
			var state := state_with(id, part)
			var normalized := CUSTOM.normalize(state)
			check(CUSTOM.selected(normalized, id, info.slot) == part, "save preserva %s em %s" % [part, id])
			var base := CUSTOM.effective_data(id, {})
			var after := CUSTOM.effective_data(id, state)
			var changed := false
			for key in ["damage", "fire_interval", "max_range", "melee_range", "falloff_start", "spread", "pellets", "magazine_size", "reload_multiplier", "recoil_multiplier", "tracer_color", "suppressed", "projectile_speed", "min_damage_ratio"]:
				if base.get(key) != after.get(key): changed = true
			var functional: bool = info.has("mul") or info.has("add") or info.has("special") or info.has("set") or part == "suppressor"
			if functional: check(changed, "%s altera o combate de %s" % [part, id])
			check(float(after.get("fire_interval", 1.0)) >= 0.05 and int(after.get("damage", 1)) >= 1, "%s mantém números válidos em %s" % [part, id])
			if functional and info.slot != "finish": check(not CUSTOM.effect_summary(part).is_empty(), "%s tem resumo de efeito" % part)
			var model := Node3D.new()
			root.add_child(model)
			ART.item(model, id)
			var before_children := _count(model)
			CUSTOM.fit(model, id, state, model.get_meta("weapon_muzzle", Vector3.ZERO))
			var visual: bool = _count(model) > before_children or info.has("recolor") or info.slot in ["ammo", "trigger", "finish"]
			check(visual, "%s tem representação visual em %s" % [part, id])
			model.free()
			tested += 1
	# Números específicos que a bancada promete.
	var knife := CUSTOM.effective_data("knife", state_with("knife", "serrated"))
	check(int(knife.damage) == roundi(25 * 1.25), "serrilha: faca 25 → 31", str(knife.damage))
	var slug := CUSTOM.effective_data("shotgun", state_with("shotgun", "slug"))
	check(int(slug.pellets) == 1 and int(slug.damage) == roundi(18 * 8 * 0.72) and float(slug.spread) < 0.05, "balote vira projétil único", "%s×%s" % [slug.damage, slug.pellets])
	var drum := CUSTOM.effective_data("smg", state_with("smg", "drum"))
	check(int(drum.magazine_size) == 75 and float(drum.reload_multiplier) > 1.5, "tambor 75 com recarga lenta")
	var legacy := CUSTOM.effective_data("pistol", state_with("pistol", "extended"))
	check(int(legacy.magazine_size) == 18, "carregador ampliado antigo preserva 12 → 18", str(legacy.magazine_size))
	var dropped := CUSTOM.normalize({"knife":{"owned_parts":["matte"], "parts":{"finish":"matte"}}})
	check(not dropped.has("knife"), "save antigo com pintura de fuzil na faca é descartado sem erro")
	root.free()
	print("ARSENAL_PARTS RESULT %s combinações=%d checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", tested, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _count(node: Node) -> int:
	var total := 1
	for child in node.get_children(): total += _count(child)
	return total
