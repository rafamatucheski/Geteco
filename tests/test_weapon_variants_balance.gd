extends SceneTree
## Product contracts: distinct choices, bounded burst accuracy, native suppression,
## authored reload timing and no draw/ammo loophole in protected garages.
const CATALOG := preload("res://gameplay/WeaponCatalog.gd")
const CUSTOM := preload("res://gameplay/WeaponCustomization.gd")
const HANDLING := preload("res://gameplay/WeaponHandling.gd")
const STATE := preload("res://runtime/GameState.gd")
const GROUPS := {
	"pistol": ["pistol", "magnum", "pistol_suppressed"],
	"smg": ["smg", "smg_compact", "smg_tactical"],
	"shotgun": ["shotgun", "sawed_off", "shotgun_auto"]
}

class ReloadState extends RefCounted:
	var equipped_weapon := "pistol_suppressed"
	func get_ammo(_id: String) -> Dictionary: return {"magazine": 0, "reserve": 12}
class ReloadHarness extends "res://gameplay/Gameplay.gd":
	func _ready() -> void: set_process(false); set_physics_process(false)
	func attack_allowed() -> bool: return true
	func _play_reload_audio(_id: String, _multiplier: float) -> void: pass

var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void: run.call_deferred()

func run() -> void:
	for category: String in GROUPS:
		var actual: Array = CATALOG.ORDER.filter(func(id): return CATALOG.get_weapon(id).get("category", "") == category)
		check(actual == GROUPS[category], category + " has exactly its three ordered choices")
		for id: String in actual:
			var data := CUSTOM.effective_data(id, {})
			check(data.damage > 0 and data.magazine_size > 0 and data.reload_duration > 0.5, id + " has usable damage, capacity and reload")
			check(float(data.max_range) > float(data.falloff_start), id + " retains meaningful damage falloff")
			check(CATALOG.distance_damage(int(data.damage), float(data.max_range)+1, float(data.falloff_start), float(data.max_range), float(data.min_damage_ratio)) == 0, id + " respects its maximum reach")
			var base := String(data.get("model_base", id))
			check(CATALOG.WEAPONS.has(base), id + " resolves its presentation base")
	var pistol := CUSTOM.effective_data("pistol", {})
	var quiet := CUSTOM.effective_data("pistol_suppressed", {})
	var magnum := CUSTOM.effective_data("magnum", {})
	check(ceili(100.0 / float(pistol.damage)) == 3 and ceili(100.0 / float(quiet.damage)) == 4 and ceili(100.0 / float(magnum.damage)) == 2, "pistols differ in close-range hits to stop a 100-health target")
	check(quiet.suppressed and quiet.hearing_radius > 0 and quiet.hearing_radius < pistol.hearing_radius, "integral suppressor reduces hearing but is never silent")
	check(quiet.max_range < pistol.max_range and quiet.fire_interval > pistol.fire_interval, "quiet pistol pays range and cadence for discretion")
	check(quiet.magazine_size > pistol.magazine_size and quiet.reload_duration < pistol.reload_duration, "integral quiet pistol keeps capacity and reload advantages over a basic pistol with suppressor")
	check(magnum.magazine_size < pistol.magazine_size and magnum.fire_interval > pistol.fire_interval, "Magnum trades capacity and follow-up speed for impact")
	check(not CUSTOM.supports("pistol_suppressed", "suppressor") and not CUSTOM.supports("pistol_suppressed", "barrel_long"), "integral barrel cannot stack a second suppressor or replacement barrel")
	check(CUSTOM.supports("pistol_suppressed", "quick_mag") and CUSTOM.supports("smg_compact", "extended") and CUSTOM.supports("shotgun_auto", "choke_full"), "compatible upgrades remain available on new variants")
	var smg := CUSTOM.effective_data("smg", {})
	var compact := CUSTOM.effective_data("smg_compact", {})
	var tactical := CUSTOM.effective_data("smg_tactical", {})
	check(compact.fire_interval < smg.fire_interval and compact.damage < smg.damage and compact.max_range < smg.max_range, "compact SMG gains cadence at the cost of damage and reach")
	check(tactical.spread < smg.spread and tactical.fire_interval > smg.fire_interval and tactical.reload_duration > smg.reload_duration, "tactical SMG gains control with slower follow-ups and reload")
	check(tactical.magazine_size < smg.magazine_size and compact.magazine_size < smg.magazine_size, "MP5 keeps its capacity advantage")
	var pump := CUSTOM.effective_data("shotgun", {})
	var sawed := CUSTOM.effective_data("sawed_off", {})
	var semi := CUSTOM.effective_data("shotgun_auto", {})
	check(semi.damage * semi.pellets < 100 and pump.damage * pump.pellets >= 100, "semi shotgun needs a follow-up where a full pump volley can stop a target")
	check(semi.fire_interval < pump.fire_interval and semi.reload_duration > pump.reload_duration and not semi.automatic, "semi shotgun is rapid click fire with a longer reload, never automatic")
	check(sawed.spread > pump.spread and sawed.max_range < pump.max_range and sawed.magazine_size == 2, "sawed-off retains its wide short-range two-shot role")
	var handling := HANDLING.new()
	var first := handling.shot_spread("smg_compact", compact, 0.0, 0.0, false)
	for i in 24: handling.fired("smg_compact", compact, i * float(compact.fire_interval))
	var last_time := 23 * float(compact.fire_interval)
	var burst := handling.shot_spread("smg_compact", compact, last_time, 0.0, false)
	check(burst > first * 2.0, "holding compact SMG fire loses precision")
	check(handling.bloom("smg_compact", compact, last_time) <= compact.spread_limit, "burst bloom is bounded")
	handling.fired("smg_tactical", tactical, last_time)
	check(is_equal_approx(handling.shot_spread("smg_compact", compact, last_time, 0.0, false), burst), "switching weapons cannot reset compact bloom")
	check(is_equal_approx(handling.shot_spread("smg_compact", compact, last_time+3.0, 0.0, false), first), "ceasing fire fully restores accuracy")
	check(handling.shot_spread("smg_tactical", tactical, 10.0, 4.0, true) < handling.shot_spread("smg_tactical", tactical, 10.0, 4.0, false), "aiming controls movement error")
	check(is_equal_approx(handling.shot_spread("shotgun", pump, 10.0, 0.0, true), float(pump.spread)), "aiming does not artificially narrow the shotgun pellet cone")
	var customized := CUSTOM.effective_data("smg_tactical", {"smg_tactical": {"owned_parts": ["compensator"], "parts": {"muzzle": "compensator"}}})
	check(customized.recoil_multiplier < tactical.recoil_multiplier, "attachments multiply native handling rather than erasing it")
	var reload_test := ReloadHarness.new()
	reload_test.state = ReloadState.new()
	root.add_child(reload_test)
	check(reload_test.reload_weapon() and is_equal_approx(reload_test.reload_timer, 1.5), "Gameplay uses authored variant reload duration")
	reload_test.reload_timer = 0
	reload_test.customization = {"pistol_suppressed": {"owned_parts": ["quick_mag"], "parts": {"magazine": "quick_mag"}}}
	check(reload_test.reload_weapon() and is_equal_approx(reload_test.reload_timer, 1.5 * .65), "Gameplay applies quick magazine to variant duration")
	reload_test.free()
	var state := STATE.new()
	state.economy.activate_arsenal_cheat()
	for garage: String in ["maciota", "harbor_garage"]:
		state.set_location("harbor", garage)
		for id: String in ["pistol_suppressed", "smg_compact", "smg_tactical", "shotgun_auto"]:
			check(not state.equip_weapon(id) and not state.consume_ammo(id) and not state.reload_weapon(id), garage + " blocks variant draw, shot and reload: " + id)
	state.set_location("harbor")
	check(state.equip_weapon("smg_compact"), "exiting garage restores variant use")
	print("WEAPON_VARIANTS_BALANCE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
