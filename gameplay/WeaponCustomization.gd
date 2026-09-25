extends RefCounted
## Saved per weapon; purchased kits remain owned when removed.
##
## Cada peça declara em quais armas cabe ("for") e o que muda nos dados de
## combate ("mul" multiplica, "add" soma, "set" substitui). Gameplay lê tudo por
## `effective_data`, então dano, cadência, alcance, dispersão, projéteis,
## capacidade, recarga e recuo mudam de verdade — sem ramos por peça no combate.
## Armas brancas têm slots próprios (lâmina/cabeça, cabo, acabamento do material
## certo): pintura de fuzil não vai mais para faca.
const PRICE := 350
const COMPATIBLE := ["pistol", "magnum", "smg", "shotgun", "sawed_off", "ak47", "m4a1", "hunting_rifle", "flamethrower"]
const FIREARMS := ["pistol", "magnum", "smg", "shotgun", "sawed_off", "ak47", "m4a1", "hunting_rifle"]
const MELEE := ["knuckles", "knife", "bat", "axe"]
const CUSTOMIZABLE := ["knuckles", "knife", "bat", "axe", "pistol", "magnum", "smg", "shotgun", "sawed_off", "ak47", "m4a1", "hunting_rifle", "flamethrower"]
## Ordem de aplicação e de exibição das abas.
const SLOTS := {"flashlight":"LANTERNA", "laser":"LASER", "muzzle":"BOCAL", "barrel":"CANO", "magazine":"CARREGADOR", "ammo":"MUNIÇÃO", "trigger":"GATILHO", "grip":"EMPUNHADURA", "stock":"CORONHA", "scope":"MIRA", "edge":"LÂMINA", "handle":"CABO", "finish":"ACABAMENTO"}
const _GUN_FINISH := ["pistol", "magnum", "smg", "shotgun", "sawed_off", "ak47", "m4a1", "hunting_rifle", "flamethrower"]
const PARTS := {
	"flashlight": {"slot":"flashlight", "label":"Lanterna tática", "price":350, "for":COMPATIBLE},

	# Laser: ponto na mira reduz a dispersão do tiro sem mirar.
	"laser_red": {"slot":"laser", "label":"Laser vermelho", "price":450, "for":FIREARMS, "mul":{"spread":0.88, "falloff_start":1.08},
		"note":"Laser ativo ao mirar; o ponto para no primeiro obstáculo."},
	"laser_green": {"slot":"laser", "label":"Laser verde", "price":500, "for":FIREARMS, "mul":{"spread":0.8, "falloff_start":1.1},
		"note":"Laser verde, mais visível de dia; ativo ao mirar e para no primeiro obstáculo."},

	# Bocal.
	"suppressor": {"slot":"muzzle", "label":"Silenciador", "price":650, "for":["pistol", "smg", "ak47", "m4a1", "hunting_rifle"],
		"mul":{"damage":0.92, "max_range":0.9},
		"note":"Silenciador: reduz o barulho; pessoas próximas e na trajetória ainda reagem. Menos polícia por disparo."},
	"compensator": {"slot":"muzzle", "label":"Compensador", "price":550, "for":["pistol", "magnum", "smg", "ak47", "m4a1"],
		"mul":{"recoil_multiplier":0.65, "spread":0.88},
		"note":"Joga o gás para cima: a arma sobe menos a cada tiro. Não reduz barulho."},
	"choke_full": {"slot":"muzzle", "label":"Choke apertado", "price":400, "for":["shotgun", "sawed_off"],
		"mul":{"spread":0.55, "falloff_start":1.45},
		"note":"Fecha o leque de chumbo: acerta mais projéteis de longe."},
	"duckbill": {"slot":"muzzle", "label":"Bico-de-pato", "price":450, "for":["shotgun", "sawed_off"],
		"mul":{"spread":1.45, "max_range":0.85}, "add":{"pellets":3},
		"note":"Abre o tiro na horizontal com mais chumbos: varre um corredor inteiro de perto."},
	"flame_focus": {"slot":"muzzle", "label":"Bico concentrado", "price":600, "for":["flamethrower"],
		"mul":{"max_range":1.35, "spread":0.6, "damage":1.05},
		"note":"Jato fino e longo: alcança quem está do outro lado da rua."},
	"flame_wide": {"slot":"muzzle", "label":"Bico leque", "price":600, "for":["flamethrower"],
		"mul":{"max_range":0.8, "spread":1.6, "damage":1.15},
		"note":"Leque curto e largo: cobre a frente inteira, mas não chega longe."},

	# Cano.
	"barrel_long": {"slot":"barrel", "label":"Cano longo de precisão", "price":700, "for":["pistol", "magnum", "smg", "ak47", "m4a1", "hunting_rifle"],
		"mul":{"damage":1.08, "max_range":1.3, "falloff_start":1.35, "projectile_speed":1.15, "fire_interval":1.06},
		"note":"Mais velocidade de saída: o dano cai bem mais tarde. Um pouco mais lento entre disparos."},
	"barrel_short": {"slot":"barrel", "label":"Cano curto de assalto", "price":550, "for":["smg", "ak47", "m4a1", "shotgun"],
		"mul":{"fire_interval":0.9, "spread":1.2, "max_range":0.8, "falloff_start":0.8},
		"note":"Leve e rápido para combate em ambiente fechado; perde alcance e precisão."},

	# Carregador.
	"extended": {"slot":"magazine", "label":"Capacidade ampliada", "price":500, "for":["pistol", "smg", "shotgun", "ak47", "m4a1", "hunting_rifle"],
		"mul":{"reload_multiplier":1.18}, "special":"extended",
		"note":"Mais tiros antes de recarregar; a troca de carregador demora um pouco mais."},
	"drum": {"slot":"magazine", "label":"Tambor de 75", "price":950, "for":["smg", "ak47"],
		"set":{"magazine_size":75}, "mul":{"reload_multiplier":1.55, "fire_interval":1.03},
		"note":"Tambor enorme: fogo contínuo por muito tempo. Recarregar vira um problema."},
	"quick_mag": {"slot":"magazine", "label":"Engate rápido", "price":450, "for":["pistol", "smg", "m4a1"],
		"mul":{"reload_multiplier":0.65},
		"note":"Alça no carregador: recarga bem mais rápida, mesma capacidade."},
	"speedloader": {"slot":"magazine", "label":"Speedloader", "price":350, "for":["magnum"],
		"mul":{"reload_multiplier":0.5},
		"note":"Carrega as seis câmaras de uma vez."},
	"big_tank": {"slot":"magazine", "label":"Tanque duplo", "price":700, "for":["flamethrower"],
		"mul":{"magazine_size":1.6, "reload_multiplier":1.3},
		"note":"Segundo cilindro de combustível nas costas da arma."},

	# Munição: muda o tracejante e a curva de dano.
	"hollow_point": {"slot":"ammo", "label":"Ponta oca", "price":600, "for":["pistol", "magnum", "smg"],
		"mul":{"damage":1.3, "min_damage_ratio":0.6, "max_range":0.8}, "set":{"tracer_color":Color("ff7a3d")},
		"note":"Expande no alvo: muito dano de perto, perde força rápido com a distância."},
	"armor_piercing": {"slot":"ammo", "label":"Perfurante", "price":750, "for":["pistol", "magnum", "smg", "ak47", "m4a1", "hunting_rifle"],
		"mul":{"damage":1.1, "falloff_start":1.4, "min_damage_ratio":1.6, "projectile_speed":1.25}, "set":{"tracer_color":Color("8fe8ff")},
		"note":"Núcleo de aço: bala mais rápida que mantém o dano de longe."},
	"plus_p": {"slot":"ammo", "label":"Carga +P", "price":500, "for":["magnum"],
		"mul":{"damage":1.22, "recoil_multiplier":1.35, "fire_interval":1.1}, "set":{"tracer_color":Color("ff5b3a")},
		"note":"Pólvora extra: cada tiro derruba, mas o coice é brutal."},
	"slug": {"slot":"ammo", "label":"Balote", "price":650, "for":["shotgun", "sawed_off"], "special":"slug",
		"set":{"tracer_color":Color("ffd36b")},
		"note":"Um projétil maciço no lugar do chumbo: vira um fuzil de curto alcance."},
	"buckshot": {"slot":"ammo", "label":"Chumbo grosso 00", "price":450, "for":["shotgun", "sawed_off"],
		"mul":{"pellets":0.6, "damage":1.9, "spread":0.85},
		"note":"Menos chumbos, bem mais pesados: cada um que acerta pesa."},
	"match_ammo": {"slot":"ammo", "label":"Munição de competição", "price":600, "for":["hunting_rifle"],
		"mul":{"damage":1.12, "spread":0.5, "projectile_speed":1.2},
		"note":"Carga medida à mão: tiro ainda mais reto e forte."},

	# Gatilho / ação.
	"match_trigger": {"slot":"trigger", "label":"Gatilho de competição", "price":650, "for":["pistol", "magnum", "hunting_rifle"],
		"mul":{"fire_interval":0.8, "spread":0.9},
		"note":"Curso curto e limpo: dispara mais rápido sem puxar a mira."},
	"light_bolt": {"slot":"trigger", "label":"Ferrolho aliviado", "price":800, "for":["smg", "ak47", "m4a1"],
		"mul":{"fire_interval":0.85, "recoil_multiplier":1.2, "spread":1.1},
		"note":"Cadência bem mais alta; a arma fica nervosa na mão."},
	"slick_pump": {"slot":"trigger", "label":"Bomba polida", "price":550, "for":["shotgun"],
		"mul":{"fire_interval":0.78},
		"note":"Ação da bomba lisa: o próximo cartucho entra num instante."},

	"vertical_grip": {"slot":"grip", "label":"Empunhadura de controle", "price":400, "for":["smg", "shotgun", "ak47", "m4a1"],
		"mul":{"recoil_multiplier":0.75, "spread":0.75},
		"note":"Segunda mão firme: menos recuo em rajada."},
	"angled_grip": {"slot":"grip", "label":"Empunhadura angular", "price":450, "for":["smg", "ak47", "m4a1"],
		"mul":{"recoil_multiplier":0.85, "reload_multiplier":0.88},
		"note":"Controle intermediário e mão mais perto do carregador: recarga mais ágil."},
	"stabilized_stock": {"slot":"stock", "label":"Coronha estabilizada", "price":450, "for":["smg", "shotgun", "ak47", "m4a1", "hunting_rifle"],
		"mul":{"recoil_multiplier":0.85, "spread":0.85},
		"note":"Apoio firme no ombro."},
	"scope_2x": {"slot":"scope", "label":"Luneta 2×", "price":900, "for":["hunting_rifle"],
		"note":"Ao mirar: ampliação 2× e visão adiantada, fora dos interiores."},

	# Acabamentos de arma de fogo (cosméticos).
	"matte": {"slot":"finish", "label":"Preto fosco", "price":200, "for":_GUN_FINISH, "color":Color("282d32")},
	"sand": {"slot":"finish", "label":"Areia", "price":200, "for":_GUN_FINISH, "color":Color("b9a175")},
	"olive": {"slot":"finish", "label":"Verde militar", "price":200, "for":_GUN_FINISH, "color":Color("596348")},
	"chrome": {"slot":"finish", "label":"Cromado", "price":350, "for":_GUN_FINISH, "color":Color("b9c9d3")},
	"wood": {"slot":"finish", "label":"Madeira escura", "price":250, "for":_GUN_FINISH, "color":Color("73452c")},
	"gold": {"slot":"finish", "label":"Ouro polido", "price":1500, "for":_GUN_FINISH, "color":Color("d8b048"),
		"note":"Só para ser visto."},

	# Faca.
	"serrated": {"slot":"edge", "label":"Serrilha no dorso", "price":300, "for":["knife"],
		"mul":{"damage":1.25, "fire_interval":1.06},
		"note":"Dentes no dorso rasgam mais; o golpe fica um pouco mais pesado."},
	"tanto": {"slot":"edge", "label":"Ponta tanto", "price":350, "for":["knife"],
		"mul":{"damage":1.1, "melee_range":1.15},
		"note":"Ponta reforçada e mais comprida: alcança um pouco mais longe."},
	"balanced": {"slot":"edge", "label":"Lâmina balanceada", "price":400, "for":["knife"],
		"mul":{"fire_interval":0.78, "damage":0.92},
		"note":"Canal de alívio na lâmina: golpes em sequência bem mais rápidos."},
	"paracord": {"slot":"handle", "label":"Cabo de paracord", "price":150, "for":["knife"],
		"mul":{"fire_interval":0.9},
		"note":"Cordão trançado que não escorrega."},
	"knuckle_guard": {"slot":"handle", "label":"Guarda-soqueira", "price":350, "for":["knife"],
		"mul":{"damage":1.12},
		"note":"Arco de metal sobre os dedos: o golpe também soca."},
	"blade_black": {"slot":"finish", "label":"Óxido negro", "price":200, "for":["knife"], "recolor":{"697782":Color("1d2124")}, "metallic":0.45, "roughness":0.6},
	"blade_mirror": {"slot":"finish", "label":"Aço espelhado", "price":300, "for":["knife"], "recolor":{"697782":Color("dfe6ea")}, "metallic":0.98, "roughness":0.08},

	# Taco.
	"nails": {"slot":"edge", "label":"Pregos cravados", "price":250, "for":["bat"],
		"mul":{"damage":1.35, "fire_interval":1.05},
		"note":"Pregos atravessando a ponta. Nada sutil."},
	"barbed_wire": {"slot":"edge", "label":"Arame farpado", "price":300, "for":["bat"],
		"mul":{"damage":1.2, "melee_range":1.08},
		"note":"Arame enrolado na ponta: dano extra em qualquer ângulo."},
	"aluminum": {"slot":"edge", "label":"Taco de alumínio", "price":350, "for":["bat"],
		"mul":{"fire_interval":0.78, "damage":0.9}, "recolor":{"714331":Color("b9c3cb")}, "metallic":0.85, "roughness":0.3,
		"note":"Mais leve: swing muito mais rápido, um pouco menos de impacto."},
	"grip_tape": {"slot":"handle", "label":"Fita de grip", "price":120, "for":["bat"],
		"mul":{"fire_interval":0.9},
		"note":"Pegada firme para girar mais rápido."},
	"long_handle": {"slot":"handle", "label":"Cabo estendido", "price":300, "for":["bat", "axe"],
		"mul":{"melee_range":1.2, "fire_interval":1.08},
		"note":"Alcança mais longe; o giro demora um pouco mais."},
	"bat_varnish": {"slot":"finish", "label":"Verniz claro", "price":150, "for":["bat"], "recolor":{"714331":Color("c8955a")}, "roughness":0.28},
	"bat_team": {"slot":"finish", "label":"Pintura de time", "price":200, "for":["bat"], "recolor":{"714331":Color("a3322d")}, "roughness":0.4},
	"bat_charred": {"slot":"finish", "label":"Queimado", "price":200, "for":["bat"], "recolor":{"714331":Color("2a1d18")}, "roughness":0.92},

	# Machado.
	"fire_axe": {"slot":"edge", "label":"Cabeça de bombeiro", "price":450, "for":["axe"],
		"mul":{"damage":1.2, "melee_range":1.05},
		"note":"Pico no lado oposto ao fio: golpe mais pesado."},
	"sharpened": {"slot":"edge", "label":"Fio amolado", "price":300, "for":["axe"],
		"mul":{"damage":1.12, "fire_interval":0.95}, "recolor":{"697782":Color("e8eef2")}, "metallic":0.95, "roughness":0.12,
		"note":"Fio polido na pedra: corta mais e prende menos."},
	"fiberglass": {"slot":"handle", "label":"Cabo de fibra", "price":400, "for":["axe"],
		"mul":{"fire_interval":0.82}, "recolor":{"714331":Color("e0b421")}, "roughness":0.45,
		"note":"Cabo leve de fibra de vidro: golpes bem mais rápidos."},
	"axe_red": {"slot":"finish", "label":"Vermelho bombeiro", "price":200, "for":["axe"], "recolor":{"222b30":Color("b8261d")}, "roughness":0.45},
	"axe_black": {"slot":"finish", "label":"Aço negro", "price":200, "for":["axe"], "recolor":{"222b30":Color("15181a"), "697782":Color("3a4148")}, "roughness":0.5},

	# Soqueira.
	"spikes": {"slot":"edge", "label":"Espigões", "price":300, "for":["knuckles"],
		"mul":{"damage":1.4, "fire_interval":1.05},
		"note":"Pontas de aço sobre os nós dos dedos."},
	"weighted": {"slot":"edge", "label":"Barra de aço temperado", "price":250, "for":["knuckles"],
		"mul":{"damage":1.18, "melee_range":1.1},
		"note":"Peso extra na frente do punho."},
	"light_alloy": {"slot":"edge", "label":"Liga leve", "price":300, "for":["knuckles"],
		"mul":{"fire_interval":0.8}, "recolor":{"d4ac0d":Color("a9b2b9")}, "metallic":0.8, "roughness":0.3,
		"note":"Metade do peso: sequência de socos bem mais rápida."},
	"padded_palm": {"slot":"handle", "label":"Palma acolchoada", "price":150, "for":["knuckles"],
		"mul":{"fire_interval":0.88},
		"note":"Couro na barra da palma: dá para socar mais rápido sem machucar a mão."},
	"push_blade": {"slot":"handle", "label":"Lâmina de empurrar", "price":400, "for":["knuckles"],
		"mul":{"damage":1.12, "melee_range":1.15},
		"note":"Lâmina curta saindo entre os dedos: soco que corta e alcança um palmo a mais."},
	"knuckle_black": {"slot":"finish", "label":"Cromo negro", "price":200, "for":["knuckles"], "recolor":{"d4ac0d":Color("1c1f22")}, "metallic":0.85, "roughness":0.25},
	"knuckle_silver": {"slot":"finish", "label":"Prata escovada", "price":250, "for":["knuckles"], "recolor":{"d4ac0d":Color("c3c8cc")}, "metallic":0.9, "roughness":0.35},
}
const GEO = preload("res://gameplay/WeaponPresentation3D.gd")
const _INT_STATS := ["magazine_size", "pellets"]
## Tempo-base de recarga do Gameplay (`reload_weapon`), só para exibir segundos.
const _RELOAD_SLOW := ["rpg", "shotgun", "hunting_rifle"]

static func supports(id: String, part: String) -> bool:
	if id not in CUSTOMIZABLE or not PARTS.has(part): return false
	return id in PARTS[part].get("for", [])

static func slot_label(id: String, slot: String) -> String:
	if slot == "edge": return {"bat":"CABEÇA", "knuckles":"PUNHO"}.get(id, "LÂMINA")
	if slot == "handle" and id == "knuckles": return "PALMA"
	if id == "flamethrower": return {"muzzle":"BICO", "magazine":"TANQUE"}.get(slot, SLOTS.get(slot, slot))
	return SLOTS.get(slot, slot)

static func selected(state: Dictionary, id: String, slot: String) -> String:
	if slot == "flashlight": return "flashlight" if installed(state,id) else "none"
	return str(state.get(id,{}).get("parts",{}).get(slot,"none"))

static func owns(state: Dictionary, id: String, part: String) -> bool:
	if part == "none": return true
	if part == "flashlight": return state.get(id,{}).get("owned",false) == true
	return part in state.get(id,{}).get("owned_parts",[])

static func effective_data(id: String, state: Dictionary) -> Dictionary:
	var data: Dictionary = preload("res://gameplay/WeaponCatalog.gd").get_weapon(id).duplicate(true)
	var base_magazine := int(data.get("magazine_size", 0))
	data["reload_multiplier"] = 1.0
	data["recoil_multiplier"] = 1.0
	for slot in SLOTS:
		var part := selected(state, id, slot)
		if part == "none" or part == "flashlight" or not supports(id, part): continue
		_apply(data, id, PARTS[part], base_magazine)
	if data.has("fire_interval"): data["fire_interval"] = maxf(0.05, float(data.fire_interval))
	if data.has("min_damage_ratio"): data["min_damage_ratio"] = minf(0.95, float(data.min_damage_ratio))
	if data.has("damage"): data["damage"] = maxi(1, roundi(float(data.damage)))
	data["suppressed"] = selected(state,id,"muzzle") == "suppressor"
	data["hearing_radius"] = 80.0 if data.suppressed else 240.0
	return data

static func _apply(data: Dictionary, id: String, part: Dictionary, base_magazine: int) -> void:
	# Arma sem munição (-1) não ganha capacidade nem projéteis.
	var mul: Dictionary = part.get("mul", {})
	for key in mul:
		if not data.has(key) and key not in ["reload_multiplier", "recoil_multiplier"]: continue
		if key == "magazine_size" and int(data.get(key, 0)) <= 0: continue
		data[key] = float(data.get(key, 1.0)) * float(mul[key])
		if key in _INT_STATS: data[key] = maxi(1, roundi(data[key]))
	var add: Dictionary = part.get("add", {})
	for key in add:
		if data.has(key): data[key] = data[key] + add[key]
	var values: Dictionary = part.get("set", {})
	for key in values:
		if key == "magazine_size" and base_magazine <= 0: continue
		data[key] = values[key]
	match str(part.get("special", "")):
		"extended":
			data["magazine_size"] = int(data.get("magazine_size",0)) + (2 if id == "shotgun" else (3 if id == "hunting_rifle" else base_magazine/2))
		"slug":
			# Um projétil com ~72% do dano somado do leque, reto e de alcance longo.
			data["damage"] = float(data.damage) * int(data.get("pellets", 1)) * 0.72
			data["pellets"] = 1
			data["spread"] = 0.012
			data["falloff_start"] = float(data.get("falloff_start", 85.0)) * 2.2
			data["max_range"] = float(data.get("max_range", 280.0)) * 1.5

## Resumo curto do efeito de uma peça, para a lista da bancada.
static func effect_summary(part: String) -> String:
	if not PARTS.has(part): return ""
	var info: Dictionary = PARTS[part]
	var bits: Array[String] = []
	var mul: Dictionary = info.get("mul", {})
	match str(info.get("special", "")):
		"extended": bits.append("+capacidade")
		"slug": bits.append("projétil único")
	if info.get("set", {}).has("magazine_size"): bits.append("%d tiros" % int(info.set.magazine_size))
	if mul.has("damage"): bits.append(_signed(float(mul.damage) - 1.0) + " dano")
	if mul.has("fire_interval"): bits.append(_signed(1.0 / float(mul.fire_interval) - 1.0) + " cadência")
	for key in ["max_range", "melee_range"]:
		if mul.has(key): bits.append(_signed(float(mul[key]) - 1.0) + " alcance")
	if mul.has("falloff_start") and not mul.has("max_range"): bits.append(_signed(float(mul.falloff_start) - 1.0) + " dano à distância")
	if mul.has("spread"): bits.append(_signed(float(mul.spread) - 1.0) + " dispersão")
	if mul.has("recoil_multiplier"): bits.append(_signed(float(mul.recoil_multiplier) - 1.0) + " recuo")
	if mul.has("reload_multiplier"): bits.append(_signed(float(mul.reload_multiplier) - 1.0) + " tempo de recarga")
	if mul.has("magazine_size"): bits.append(_signed(float(mul.magazine_size) - 1.0) + " capacidade")
	if info.get("add", {}).has("pellets"): bits.append("+%d chumbos" % int(info.add.pellets))
	if part == "suppressor": bits.append("silencioso")
	if bits.is_empty(): return "visual" if info.slot == "finish" else ""
	return ", ".join(bits.slice(0, 3))

static func _signed(value: float) -> String:
	return ("+" if value >= 0 else "−") + "%d%%" % absi(roundi(value * 100.0))

## Números que o jogador compara na bancada. Mesmas fórmulas do combate.
static func stats(id: String, state: Dictionary) -> Array:
	var data := effective_data(id, state)
	var rows := []
	var pellets := int(data.get("pellets", 1))
	var damage := int(data.get("damage", 0))
	rows.append(["Dano", float(damage * pellets), ("%d×%d" % [damage, pellets]) if pellets > 1 else str(damage), true])
	rows.append(["Golpes/s" if data.get("is_melee", false) else "Tiros/s", 1.0 / float(data.fire_interval), "%.1f" % (1.0 / float(data.fire_interval)), true])
	var reach := float(data.get("melee_range", data.get("max_range", 0.0))) / 16.0
	rows.append(["Alcance", reach, "%.1f m" % reach if reach < 10.0 else "%d m" % roundi(reach), true])
	if data.get("is_melee", false): return rows
	if data.has("falloff_start"):
		var falloff := float(data.falloff_start) / 16.0
		rows.append(["Dano cheio até", falloff, "%d m" % roundi(falloff), true])
	var magazine := int(data.get("magazine_size", -1))
	if magazine > 0:
		rows.append(["Capacidade", float(magazine), str(magazine), true])
		var reload := (2.2 if id in _RELOAD_SLOW else 1.35) * float(data.reload_multiplier)
		rows.append(["Recarga", reload, "%.1f s" % reload, false])
	rows.append(["Recuo", float(data.recoil_multiplier), "%d%%" % roundi(float(data.recoil_multiplier) * 100.0), false])
	if float(data.get("spread", 0.0)) > 0.0:
		rows.append(["Dispersão", float(data.spread), "%.3f" % float(data.spread), false])
	return rows

static func normalize(value: Variant) -> Dictionary:
	var result := {}
	if not value is Dictionary: return result
	for id in CUSTOMIZABLE:
		var entry: Variant = value.get(id, {})
		if not entry is Dictionary: continue
		var clean := {"owned": id in COMPATIBLE and entry.get("owned",false) == true, "installed":false,
			"owned_parts":[], "parts":{}}
		clean.installed = clean.owned and entry.get("installed",false) == true
		if entry.get("owned_parts",[]) is Array:
			for part in entry.get("owned_parts",[]):
				if part is String and supports(id,part) and part != "flashlight" and part not in clean.owned_parts: clean.owned_parts.append(part)
		if entry.get("parts",{}) is Dictionary:
			for slot in entry.get("parts",{}):
				var part: Variant = entry.parts[slot]
				if part in clean.owned_parts and PARTS[part].slot == slot: clean.parts[slot] = part
		if clean.owned or not clean.owned_parts.is_empty(): result[id] = clean
	return result

static func installed(state: Dictionary, id: String) -> bool:
	return id in COMPATIBLE and state.get(id, {}).get("installed", false) == true

static func fit(root: Node3D, id: String, state: Dictionary, muzzle: Vector3) -> void:
	preload("res://gameplay/WeaponAttachmentVisuals.gd").apply(root,id,state.get(id,{}),muzzle)
	if not installed(state, id): return
	var mount := Node3D.new()
	mount.name = "TacticalFlashlight"
	root.add_child(mount)
	# Side clamp clears shotgun pumps and the supporting hand.
	mount.position = Vector3(0.049, muzzle.y - 0.018, muzzle.z + 0.09)
	if id == "pistol": mount.position = Vector3(0.0, 0.006, muzzle.z + 0.04)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("242b30")
	metal.metallic = 0.65
	metal.roughness = 0.4
	GEO._box(mount, "Clamp", Vector3(0,0.019,0.018) if id == "pistol" else Vector3(-0.024,0,0.018), Vector3(0.04,0.025,0.028), metal)
	GEO._cylinder(mount, "Body", Vector3.ZERO, 0.019, 0.085, metal, Vector3(90,0,0))
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color("d9e6df")
	lens.metallic = 0.3
	lens.roughness = 0.15
	GEO._cylinder(mount, "Lens", Vector3(0,0,-0.043), 0.015, 0.002, lens, Vector3(90,0,0))
