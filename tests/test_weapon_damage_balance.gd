extends SceneTree
## Combat pacing targets against a full-health civilian, independent of catalog values.
const CATALOG := preload("res://gameplay/WeaponCatalog.gd")
const CUSTOM := preload("res://gameplay/WeaponCustomization.gd")
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func damage_at(id: String, distance: float) -> int:
	var data := CATALOG.get_weapon(id)
	return CATALOG.distance_damage(int(data.damage), distance, float(data.falloff_start), float(data.max_range), float(data.min_damage_ratio))

func _initialize() -> void:
	for target in [["pistol", 3], ["magnum", 2], ["smg", 4], ["ak47", 3], ["m4a1", 3], ["hunting_rifle", 1]]:
		var amount := damage_at(target[0], 96.0)
		check(ceili(100.0 / amount) == target[1], "%s close-range hit count" % target[0])
	for target in [["pistol", 320.0, 4], ["smg", 256.0, 5], ["ak47", 480.0, 3], ["m4a1", 480.0, 4]]:
		check(ceili(100.0 / damage_at(target[0], target[1])) <= target[2], "%s remains effective at medium range" % target[0])
	for id in ["pistol", "magnum", "smg", "shotgun", "sawed_off", "ak47", "m4a1", "hunting_rifle"]:
		var data := CATALOG.get_weapon(id)
		var previous := damage_at(id, 0.0)
		for step in range(1, 21):
			var current := damage_at(id, float(data.max_range) * step / 20.0)
			check(current > 0 and current <= previous, "%s falloff is bounded and monotonic" % id)
			previous = current
		check(damage_at(id, float(data.falloff_start)) == int(data.damage), "%s full damage through effective range" % id)
		check(damage_at(id, float(data.max_range) + 1.0) == 0, "%s cannot damage beyond range" % id)
	for id in ["shotgun", "sawed_off"]:
		var data := CATALOG.get_weapon(id)
		check(int(data.damage) * 6 >= 100, "%s six close pellets can drop a civilian" % id)
		check(damage_at(id, float(data.max_range)) * int(data.pellets) < 100, "%s loses lethality at long range" % id)
	var improved := CUSTOM.effective_data("pistol", {"pistol": {"owned_parts": ["hollow_point"], "parts": {"ammo": "hollow_point"}}})
	check(int(improved.damage) > damage_at("pistol", 0.0), "existing ammunition upgrade still improves close damage")
	check(ceili(130.0 / damage_at("pistol", 96.0)) > ceili(100.0 / damage_at("pistol", 96.0)), "heavy police still resist more hits than civilians")
	print("WEAPON_DAMAGE_BALANCE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
