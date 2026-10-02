extends SceneTree

const CATALOG = preload("res://gameplay/WeaponCatalog.gd")
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var gameplay := preload("res://gameplay/Gameplay.gd").new()
	var car := preload("res://scripts/Vehicle.gd").new()
	var shooter := Node.new()
	car.set_meta("gameplay_role", "vehicle")
	for id in ["pistol", "magnum", "smg", "ak47", "m4a1", "hunting_rifle", "shotgun", "sawed_off"]:
		var data := CATALOG.get_weapon(id)
		car.health = 180.0
		var shots := 0
		while car.health > 0.0 and shots < 100:
			for pellet in int(data.get("pellets", 1)):
				gameplay._damage_bullet(car, float(data.damage), shooter)
			shots += 1
			if shots == 3:
				check(car.health > 90.0, id + ": three shots preserve over half the hull")
		check(shots >= 7 and shots < 100, id + ": resists sustained fire but remains destructible")
		print("VEHICLE_BULLETS ", id, " shots=", shots)
	car.health = 180.0
	gameplay._damage(car, 70.0, shooter)
	check(is_equal_approx(car.health, 110.0), "non-ballistic damage remains unchanged")
	car.health = 180.0
	car.damage_resistance = 0.4
	gameplay._damage_bullet(car, 100.0, shooter)
	check(is_equal_approx(car.health, 174.0), "tank armor stacks with hull resistance")
	car.set_meta("invulnerable", true)
	gameplay._damage_bullet(car, 10000.0, shooter)
	check(is_equal_approx(car.health, 174.0), "protected vehicle remains invulnerable")
	car.free()
	shooter.free()
	gameplay.free()
	print("VEHICLE_BULLET_RESISTANCE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
