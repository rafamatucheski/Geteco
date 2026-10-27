
extends RefCounted

# Catálogo definitivo de armas, estatísticas, munições e atributos de combate
const ORDER = [
	"fists",
	"knuckles",
	"knife",
	"bat",
	"axe",
	"katana",
	"pistol",
	"magnum",
	"pistol_suppressed",
	"smg",
	"smg_compact",
	"smg_tactical",
	"shotgun",
	"sawed_off",
	"shotgun_auto",
	"ak47",
	"m4a1",
	"rpg",
	"flamethrower",
	"grenade",
	"hunting_rifle"
]

const WEAPONS = {
	"katana": {
		"label":"KATANA DA FAMÍLIA", "short_label":"KATANA", "price":300000,
		"damage":45, "fire_interval":0.78, "melee_range":48.0,
		"falloff_start":48.0, "max_range":48.0, "min_damage_ratio":1.0,
		"magazine_size":-1, "starting_reserve":-1, "is_melee":true,
		"is_knife":true, "automatic":false, "stance":"katana",
		"sound_type":"knife", "audio_volume_db":-1.0, "pitch_variance":0.06,
		"discovery_pickup":"takeshi_honor", "discovery_hint":"Vença o desafio de Takeshi nas drag races."
	},
	"fists": {
		"falloff_start": 30.0, "max_range": 46.0, "min_damage_ratio": 0.65,
		# Sempre disponivel, sem preco, sem municao (arma corpo a corpo:
		# magazine_size/starting_reserve = -1 e' o sentinela lido por
		# buy_weapon()/_reload_active_weapon() como "nao usa municao").
		"label": "PUNHOS", "short_label": "PUNHO", "price": 0,
		"damage": 9, "fire_interval": 0.40, "melee_range": 46.0,
		"magazine_size": -1, "starting_reserve": -1,
		"is_melee": true, "automatic": false, "stance": "unarmed",
		"sound_type": "fists", "audio_volume_db": -4.0, "pitch_variance": 0.10
	},
	"knuckles": {
		"falloff_start": 32.0, "max_range": 48.0, "min_damage_ratio": 0.65,
		"label": "SOQUEIRA DE BRONZE", "short_label": "SOQUEIRA", "price": 150,
		"damage": 18, "fire_interval": 0.34, "melee_range": 48.0,
		"magazine_size": -1, "starting_reserve": -1,
		"is_melee": true, "is_knife": false, "automatic": false, "stance": "knuckles",
		"sound_type": "fists", "audio_volume_db": -2.5, "pitch_variance": 0.08
	},
	"knife": {
		"falloff_start": 28.0, "max_range": 40.0, "min_damage_ratio": 0.65,
		"label": "FACA DE COMBATE", "short_label": "FACA", "price": 350,
		"damage": 25, "fire_interval": 0.44, "melee_range": 40.0,
		"magazine_size": -1, "starting_reserve": -1,
		"is_melee": true, "is_knife": true, "automatic": false, "stance": "knife",
		"sound_type": "knife", "audio_volume_db": -2.0, "pitch_variance": 0.07
	},
	"bat": {
		"falloff_start": 42.0, "max_range": 62.0, "min_damage_ratio": 0.65,
		"label": "TACO DE BEISEBOL", "short_label": "TACO", "price": 250,
		"damage": 35, "fire_interval": 0.65, "melee_range": 62.0,
		"magazine_size": -1, "starting_reserve": -1,
		"is_melee": true, "is_knife": false, "automatic": false, "stance": "bat",
		"sound_type": "fists", "audio_volume_db": -1.0, "pitch_variance": 0.06
	},
	"axe": {
		"falloff_start": 44.0, "max_range": 66.0, "min_damage_ratio": 0.65,
		"label": "MACHADO DE LENHADOR", "short_label": "MACHADO", "price": 650,
		"damage": 52, "fire_interval": 0.85, "melee_range": 66.0,
		"magazine_size": -1, "starting_reserve": -1,
		"is_melee": true, "is_knife": true, "automatic": false, "stance": "axe",
		"sound_type": "knife", "audio_volume_db": -1.0, "pitch_variance": 0.05
	},
	"pistol": {
		"category": "pistol", "ammo_family": "9mm", "role": "Equilibrada", "role_en": "Balanced",
		"reload_duration": 1.691875, "move_spread": 0.018,
		"falloff_start": 145.0, "max_range": 300.0, "min_damage_ratio": 0.5,
		"label": "PISTOLA 9MM", "short_label": "9MM", "price": 0,
		"damage": 34, "fire_interval": 0.26, "projectile_speed": 620.0,
		"pellets": 1, "spread": 0.0, "magazine_size": 12, "starting_reserve": 60,
		"automatic": false, "tracer_color": Color("ffe36b"), "stance": "pistol",
		"sound_type": "pistol", "audio_volume_db": 6, "pitch_variance": 0.06
	},
	"magnum": {
		"category": "pistol", "ammo_family": "44", "role": "Impacto", "role_en": "Stopping power",
		"reload_duration": 2.52590625, "move_spread": 0.040,
		"falloff_start": 180.0, "max_range": 380.0, "min_damage_ratio": 0.6,
		"label": "REVÓLVER .44 MAGNUM", "short_label": "MAGNUM", "price": 800,
		"damage": 70, "fire_interval": 0.58, "projectile_speed": 720.0,
		"pellets": 1, "spread": 0.0, "magazine_size": 6, "starting_reserve": 36,
		"automatic": false, "tracer_color": Color("ffb940"), "stance": "pistol",
		"sound_type": "magnum", "audio_volume_db": 7, "pitch_variance": 0.04
	},
	"pistol_suppressed": {
		"category": "pistol", "model_base": "pistol", "ammo_family": "9mm",
		"role": "Discreta", "role_en": "Quiet", "suppressed": true,
		"label": "PISTOLA 9MM SILENCIADA", "short_label": "SILENCIADA", "price": 2200,
		"damage": 28, "fire_interval": 0.30, "projectile_speed": 560.0,
		"falloff_start": 120.0, "max_range": 250.0, "min_damage_ratio": 0.45,
		"pellets": 1, "spread": 0.008, "magazine_size": 15, "starting_reserve": 48,
		"reload_duration": 1.5, "recoil_multiplier": 0.70, "camera_kick": 0.012, "move_spread": 0.020,
		"automatic": false, "tracer_color": Color("c7d6c2"), "stance": "pistol",
		"sound_type": "pistol_suppressed", "audio_volume_db": 4.0, "pitch_variance": 0.04
	},
	"smg": {
		"category": "smg", "ammo_family": "9mm", "role": "Versátil", "role_en": "Versatile",
		"reload_duration": 1.48096875, "move_spread": 0.024,
		"spread_growth": 0.010, "spread_limit": 0.070, "spread_recovery": 0.060,
		"falloff_start": 120.0, "max_range": 260.0, "min_damage_ratio": 0.45,
		"discovery_pickup": "mountain_cargo_plane_smg_01", "discovery_hint": "Encontre a SMG dentro do avião no lago.",
		"label": "SUBMETRALHADORA MP5", "short_label": "SMG", "price": 1200,
		"damage": 25, "fire_interval": 0.11, "projectile_speed": 650.0,
		"pellets": 1, "spread": 0.035, "magazine_size": 30, "starting_reserve": 150,
		"automatic": true, "tracer_color": Color("78dcff"), "stance": "rifle",
		"sound_type": "smg", "audio_volume_db": 4, "pitch_variance": 0.08
	},
	"smg_compact": {
		"category": "smg", "model_base": "smg", "ammo_family": "9mm",
		"role": "Rajada curta", "role_en": "Short bursts",
		"label": "SUBMETRALHADORA COMPACTA", "short_label": "COMPACTA", "price": 1400,
		"damage": 19, "fire_interval": 0.075, "projectile_speed": 600.0,
		"falloff_start": 85.0, "max_range": 210.0, "min_damage_ratio": 0.35,
		"pellets": 1, "spread": 0.050, "magazine_size": 24, "starting_reserve": 96,
		"reload_duration": 1.3, "recoil_multiplier": 1.30, "camera_kick": 0.025, "move_spread": 0.015,
		"spread_growth": 0.018, "spread_limit": 0.120, "spread_recovery": 0.100,
		"automatic": true, "tracer_color": Color("e8cf81"), "stance": "rifle",
		"sound_type": "smg_compact", "audio_volume_db": 3.0, "pitch_variance": 0.08
	},
	"smg_tactical": {
		"category": "smg", "model_base": "smg", "ammo_family": "9mm",
		"role": "Controle", "role_en": "Control",
		"label": "SUBMETRALHADORA TÁTICA", "short_label": "TÁTICA", "price": 2600,
		"damage": 29, "fire_interval": 0.135, "projectile_speed": 690.0,
		"falloff_start": 155.0, "max_range": 310.0, "min_damage_ratio": 0.50,
		"pellets": 1, "spread": 0.018, "magazine_size": 24, "starting_reserve": 96,
		"reload_duration": 2.0, "recoil_multiplier": 0.65, "camera_kick": 0.015, "move_spread": 0.030,
		"spread_growth": 0.006, "spread_limit": 0.035, "spread_recovery": 0.035,
		"automatic": true, "tracer_color": Color("a6d9d6"), "stance": "rifle",
		"sound_type": "smg_tactical", "audio_volume_db": 4.5, "pitch_variance": 0.05
	},
	"shotgun": {
		"category": "shotgun", "ammo_family": "12g", "role": "Potência", "role_en": "Power",
		"reload_duration": 2.83028125, "move_spread": 0.030,
		"falloff_start": 50.0, "max_range": 145.0, "min_damage_ratio": 0.15,
		"label": "ESCOPETA 12G PUMP", "short_label": "12G", "price": 1800,
		"damage": 18, "fire_interval": 0.78, "projectile_speed": 480.0,
		"pellets": 8, "spread": 0.20, "magazine_size": 6, "starting_reserve": 36,
		"automatic": false, "tracer_color": Color("ff9b63"), "stance": "rifle",
		"sound_type": "shotgun", "audio_volume_db": 6, "pitch_variance": 0.05
	},
	"sawed_off": {
		"category": "shotgun", "ammo_family": "12g", "role": "Curto alcance", "role_en": "Close range",
		"reload_duration": 2.62565625, "move_spread": 0.020,
		"falloff_start": 35.0, "max_range": 110.0, "min_damage_ratio": 0.1,
		"label": "CANO SERRADO DUPLO", "short_label": "SERRADA", "price": 1600,
		"damage": 18, "fire_interval": 0.44, "projectile_speed": 480.0,
		"pellets": 10, "spread": 0.34, "magazine_size": 2, "starting_reserve": 24,
		"automatic": false, "tracer_color": Color("ff793f"), "stance": "pistol",
		"sound_type": "sawed_off", "audio_volume_db": 6.5, "pitch_variance": 0.05
	},
	"shotgun_auto": {
		"category": "shotgun", "model_base": "shotgun", "ammo_family": "12g",
		"role": "Disparos rápidos", "role_en": "Rapid follow-up",
		"label": "ESCOPETA 12G SEMIAUTOMÁTICA", "short_label": "12G SEMI", "price": 2800,
		"damage": 13, "fire_interval": 0.38, "projectile_speed": 510.0,
		"falloff_start": 45.0, "max_range": 135.0, "min_damage_ratio": 0.12,
		"pellets": 7, "spread": 0.22, "magazine_size": 8, "starting_reserve": 32,
		"reload_duration": 3.3, "recoil_multiplier": 0.78, "camera_kick": 0.055, "move_spread": 0.040,
		"automatic": false, "tracer_color": Color("efbd79"), "stance": "rifle",
		"sound_type": "shotgun_auto", "audio_volume_db": 5.5, "pitch_variance": 0.05
	},
	"ak47": {
		"falloff_start": 250.0, "max_range": 440.0, "min_damage_ratio": 0.6,
		"label": "FUZIL AK-47 7.62MM", "short_label": "AK-47", "price": 3200,
		"damage": 42, "fire_interval": 0.15, "projectile_speed": 760.0,
		"pellets": 1, "spread": 0.040, "magazine_size": 30, "starting_reserve": 180,
		"automatic": true, "tracer_color": Color("ff6348"), "stance": "rifle",
		"sound_type": "ak47", "audio_volume_db": 6.5, "pitch_variance": 0.06
	},
	"m4a1": {
		"falloff_start": 275.0, "max_range": 470.0, "min_damage_ratio": 0.65,
		"label": "CARABINA M4A1 5.56MM", "short_label": "M4A1", "price": 3800,
		"damage": 35, "fire_interval": 0.12, "projectile_speed": 800.0,
		"pellets": 1, "spread": 0.020, "magazine_size": 30, "starting_reserve": 180,
		"automatic": true, "tracer_color": Color("70a1ff"), "stance": "rifle",
		"sound_type": "m4a1", "audio_volume_db": 5.5, "pitch_variance": 0.06
	},
	"rpg": {
		"blast_radius": 112.0,
		"falloff_start": 460.0, "max_range": 460.0, "min_damage_ratio": 1,
		"label": "LANÇA-FOGUETES RPG-7", "short_label": "RPG", "price": 8500,
		"damage": 95, "fire_interval": 1.65, "projectile_speed": 420.0,
		"pellets": 1, "spread": 0.0, "magazine_size": 1, "starting_reserve": 8,
		"automatic": false, "tracer_color": Color("ff4757"), "is_explosive": true, "stance": "shoulder_rpg",
		"sound_type": "rpg", "audio_volume_db": 5.5, "pitch_variance": 0.03
	},
	"flamethrower": {
		"falloff_start": 38.0, "max_range": 90.0, "min_damage_ratio": 0.25,
		"label": "LANÇA-CHAMAS INCENDIÁRIO", "short_label": "CHAMAS", "price": 5500,
		"damage": 3, "fire_interval": 0.05, "projectile_speed": 350.0,
		"pellets": 1, "spread": 0.20, "magazine_size": 100, "starting_reserve": 300,
		"automatic": true, "tracer_color": Color("ffa502"), "is_flame": true, "stance": "hip_heavy",
		"sound_type": "flamethrower", "audio_volume_db": -2.0, "pitch_variance": 0.08
	},
	"grenade": {
		"throw_range": 320.0, "blast_radius": 120.0,
		"label": "GRANADAS DE FRAGMENTAÇÃO", "short_label": "GRANADA", "price": 600,
		"damage": 80, "fire_interval": 0.90, "projectile_speed": 650.0,
		"pellets": 1, "spread": 0.0, "magazine_size": 1, "starting_reserve": 10,
		"automatic": false, "tracer_color": Color("2ed573"), "is_grenade": true, "stance": "grenade",
		"sound_type": "grenade", "audio_volume_db": 0.5, "pitch_variance": 0.05
	},
	"hunting_rifle": {
		"falloff_start": 360.0, "max_range": 560.0, "min_damage_ratio": 0.5,
		"discovery_pickup": "mountain_cabin_hunting_rifle", "discovery_hint": "Encontre o rifle na cabana dos caçadores.",
		"label": "FUZIL DE CAÇA LENDÁRIO", "short_label": "PRESA DO INVERNO", "price": 4800,
		"damage": 120, "fire_interval": 0.95, "projectile_speed": 1000.0,
		"pellets": 1, "spread": 0.004, "magazine_size": 5, "starting_reserve": 35,
		"automatic": false, "tracer_color": Color("f1c40f"), "stance": "rifle",
		"sound_type": "hunting_rifle", "audio_volume_db": 6, "pitch_variance": 0.03
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

static func get_audio_volume_db(weapon_id: String) -> float:
	var data := get_weapon(weapon_id)
	return float(data.get("audio_volume_db", -2.0))

static func get_random_pitch_scale(weapon_id: String) -> float:
	var data := get_weapon(weapon_id)
	var variance := float(data.get("pitch_variance", 0.06))
	return randf_range(1.0 - variance, 1.0 + variance)

# Distances are world units, independent of projectile speed and camera zoom.
static func distance_damage(base_damage: int, distance: float, full_range: float, max_range: float, minimum: float) -> int:
	if distance > max_range or base_damage <= 0: return 0
	var weight := clampf((distance - full_range) / maxf(max_range - full_range, 0.001), 0.0, 1.0)
	return maxi(1, roundi(base_damage * lerpf(1.0, clampf(minimum, 0.0, 1.0), weight)))
