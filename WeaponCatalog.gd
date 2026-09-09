class_name WeaponCatalog
extends RefCounted

# Catálogo definitivo de armas, estatísticas, munições e atributos de combate
const ORDER = [
	"fists",
	"knife",
	"pistol",
	"magnum",
	"smg",
	"shotgun",
	"sawed_off",
	"ak47",
	"m4a1",
	"rpg",
	"flamethrower",
	"grenade",
	"hunting_rifle"
]

const WEAPONS = {
	"fists": {
		# Sempre disponivel, sem preco, sem municao (arma corpo a corpo:
		# magazine_size/starting_reserve = -1 e' o sentinela lido por
		# buy_weapon()/_reload_active_weapon() como "nao usa municao").
		"label": "PUNHOS", "short_label": "PUNHO", "price": 0,
		"damage": 9, "fire_interval": 0.42, "melee_range": 46.0,
		"magazine_size": -1, "starting_reserve": -1,
		"is_melee": true, "automatic": false, "stance": "unarmed",
		"sound_type": "fists", "audio_volume_db": -4.0, "pitch_variance": 0.10
	},
	"knife": {
		"label": "FACA DE COMBATE", "short_label": "FACA", "price": 350,
		"damage": 22, "fire_interval": 0.50, "melee_range": 54.0,
		"magazine_size": -1, "starting_reserve": -1,
		"is_melee": true, "is_knife": true, "automatic": false, "stance": "knife",
		"sound_type": "knife", "audio_volume_db": -2.0, "pitch_variance": 0.07
	},
	"pistol": {
		"label": "PISTOLA 9MM", "short_label": "9MM", "price": 0,
		"damage": 12, "fire_interval": 0.26, "projectile_speed": 920.0,
		"pellets": 1, "spread": 0.0, "magazine_size": 12, "starting_reserve": 60,
		"automatic": false, "tracer_color": Color("ffe36b"), "stance": "pistol",
		"sound_type": "pistol", "audio_volume_db": -2.0, "pitch_variance": 0.06
	},
	"magnum": {
		"label": "REVÓLVER .44 MAGNUM", "short_label": "MAGNUM", "price": 800,
		"damage": 30, "fire_interval": 0.58, "projectile_speed": 1080.0,
		"pellets": 1, "spread": 0.0, "magazine_size": 6, "starting_reserve": 36,
		"automatic": false, "tracer_color": Color("ffb940"), "stance": "pistol",
		"sound_type": "magnum", "audio_volume_db": 2.0, "pitch_variance": 0.04
	},
	"smg": {
		"discovery_pickup": "mountain_cargo_plane_smg_01", "discovery_hint": "Encontre a SMG dentro do avião no lago.",
		"label": "SUBMETRALHADORA MP5", "short_label": "SMG", "price": 1200,
		"damage": 8, "fire_interval": 0.11, "projectile_speed": 960.0,
		"pellets": 1, "spread": 0.035, "magazine_size": 30, "starting_reserve": 150,
		"automatic": true, "tracer_color": Color("78dcff"), "stance": "rifle",
		"sound_type": "smg", "audio_volume_db": -3.0, "pitch_variance": 0.08
	},
	"shotgun": {
		"label": "ESCOPETA 12G PUMP", "short_label": "12G", "price": 1800,
		"damage": 6, "fire_interval": 0.78, "projectile_speed": 840.0,
		"pellets": 8, "spread": 0.20, "magazine_size": 6, "starting_reserve": 36,
		"automatic": false, "tracer_color": Color("ff9b63"), "stance": "rifle",
		"sound_type": "shotgun", "audio_volume_db": 1.0, "pitch_variance": 0.05
	},
	"sawed_off": {
		"label": "CANO SERRADO DUPLO", "short_label": "SERRADA", "price": 1600,
		"damage": 6, "fire_interval": 0.44, "projectile_speed": 780.0,
		"pellets": 10, "spread": 0.34, "magazine_size": 2, "starting_reserve": 24,
		"automatic": false, "tracer_color": Color("ff793f"), "stance": "pistol",
		"sound_type": "sawed_off", "audio_volume_db": 1.5, "pitch_variance": 0.05
	},
	"ak47": {
		"label": "FUZIL AK-47 7.62MM", "short_label": "AK-47", "price": 3200,
		"damage": 15, "fire_interval": 0.15, "projectile_speed": 1120.0,
		"pellets": 1, "spread": 0.040, "magazine_size": 30, "starting_reserve": 180,
		"automatic": true, "tracer_color": Color("ff6348"), "stance": "rifle",
		"sound_type": "ak47", "audio_volume_db": 0.5, "pitch_variance": 0.06
	},
	"m4a1": {
		"label": "CARABINA M4A1 5.56MM", "short_label": "M4A1", "price": 3800,
		"damage": 13, "fire_interval": 0.12, "projectile_speed": 1180.0,
		"pellets": 1, "spread": 0.020, "magazine_size": 30, "starting_reserve": 180,
		"automatic": true, "tracer_color": Color("70a1ff"), "stance": "rifle",
		"sound_type": "m4a1", "audio_volume_db": -0.5, "pitch_variance": 0.06
	},
	"rpg": {
		"label": "LANÇA-FOGUETES RPG-7", "short_label": "RPG", "price": 8500,
		"damage": 95, "fire_interval": 1.65, "projectile_speed": 520.0,
		"pellets": 1, "spread": 0.0, "magazine_size": 1, "starting_reserve": 8,
		"automatic": false, "tracer_color": Color("ff4757"), "is_explosive": true, "stance": "shoulder_rpg",
		"sound_type": "rpg", "audio_volume_db": 2.5, "pitch_variance": 0.03
	},
	"flamethrower": {
		"label": "LANÇA-CHAMAS INCENDIÁRIO", "short_label": "CHAMAS", "price": 5500,
		"damage": 3, "fire_interval": 0.05, "projectile_speed": 450.0,
		"pellets": 1, "spread": 0.20, "magazine_size": 100, "starting_reserve": 300,
		"automatic": true, "tracer_color": Color("ffa502"), "is_flame": true, "stance": "hip_heavy",
		"sound_type": "flamethrower", "audio_volume_db": -2.0, "pitch_variance": 0.08
	},
	"grenade": {
		"label": "GRANADAS DE FRAGMENTAÇÃO", "short_label": "GRANADA", "price": 600,
		"damage": 80, "fire_interval": 0.90, "projectile_speed": 650.0,
		"pellets": 1, "spread": 0.0, "magazine_size": 1, "starting_reserve": 10,
		"automatic": false, "tracer_color": Color("2ed573"), "is_grenade": true, "stance": "grenade",
		"sound_type": "grenade", "audio_volume_db": 0.5, "pitch_variance": 0.05
	},
	"hunting_rifle": {
		"discovery_pickup": "mountain_cabin_hunting_rifle", "discovery_hint": "Encontre o rifle na cabana dos caçadores.",
		"label": "FUZIL DE CAÇA LENDÁRIO", "short_label": "PRESA DO INVERNO", "price": 4800,
		"damage": 120, "fire_interval": 0.95, "projectile_speed": 1600.0,
		"pellets": 1, "spread": 0.004, "magazine_size": 5, "starting_reserve": 35,
		"automatic": false, "tracer_color": Color("f1c40f"), "stance": "rifle",
		"sound_type": "magnum", "audio_volume_db": 2.8, "pitch_variance": 0.03
	}
}

static func get_order() -> Array:
	return ORDER.duplicate()

static func get_weapon(id: String) -> Dictionary:
	return WEAPONS.get(id, {})

static func is_shop_unlocked(id: String, collected_pickups: Array) -> bool:
	var required := String(get_weapon(id).get("discovery_pickup", ""))
	return required.is_empty() or collected_pickups.has(required)

static func get_weapon_id_at(index: int) -> String:
	return ORDER[posmod(index, ORDER.size())]

static func get_audio_stream(weapon_id: String) -> AudioStream:
	return ProceduralAudio.get_gunshot_stream(weapon_id)

static func get_audio_volume_db(weapon_id: String) -> float:
	var data := get_weapon(weapon_id)
	return float(data.get("audio_volume_db", -2.0))

static func get_random_pitch_scale(weapon_id: String) -> float:
	var data := get_weapon(weapon_id)
	var variance := float(data.get("pitch_variance", 0.06))
	return randf_range(1.0 - variance, 1.0 + variance)
