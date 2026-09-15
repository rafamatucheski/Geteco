extends SceneTree
const RELOAD := preload("res://guns/combat/WeaponReload.gd")
var failures: Array[String] = []

class PursuedCar extends CharacterBody2D:
	var is_driven_by_player := true

class DriveByUnit extends CharacterBody2D:
	var target: Node2D
	var is_acting := false
	var is_returning_to_base := false
	var is_broken := false
	var police_variant := "cruiser"
	var _police_available_seats := 2

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var officer := preload("res://police/PoliceOfficer.gd").new()
	world.add_child(officer)
	officer.set_physics_process(false)
	for id in WeaponCatalog.get_order():
		var size := int(WeaponCatalog.get_weapon(id).get("magazine_size", -1))
		if size <= 0:
			check(RELOAD.duration(id) == 0, id + " does not reload melee")
			continue
		var cycle := RELOAD.new()
		cycle.equip(id)
		var fired := 0
		for round_index in size:
			if cycle.consume(): fired += 1
		check(fired == size, id + " fires exactly magazine capacity")
		check(cycle.remaining == RELOAD.duration(id) and cycle.remaining > 0, id + " starts shared reload only after magazine empties")
		check(not cycle.consume(), id + " cannot fire on empty magazine")
		cycle.tick(cycle.remaining - 0.001)
		check(not cycle.consume(), id + " cannot fire before completion")
		cycle.tick(0.002)
		check(cycle.clip == size and cycle.consume(), id + " refills exactly one magazine")
	for id in ["pistol", "smg", "m4a1", "ak47"]:
		officer.dropped_weapon = StringName(id)
		var size := int(WeaponCatalog.get_weapon(id).magazine_size)
		for i in size: officer._shoot_at_target(Vector2(300,0))
		check(officer.is_reloading() and officer.weapon_reload.clip == 0, id + " actual officer drains magazine")
		var count := world.get_child_count()
		officer._shoot_at_target(Vector2(300,0))
		check(world.get_child_count() == count, id + " actual officer cannot spawn projectile during reload")
		check(is_equal_approx(officer.weapon_reload.remaining, RELOAD.duration(id)), id + " actual officer uses player duration")
	var drive_by := preload("res://police/PoliceVehicleCombat.gd").new()
	var unit := DriveByUnit.new()
	var hull := CollisionShape2D.new()
	hull.name = "CollisionShape2D"
	hull.shape = RectangleShape2D.new()
	unit.add_child(hull)
	world.add_child(unit)
	unit.target = PursuedCar.new()
	world.add_child(unit.target)
	unit.target.position = Vector2(180,0)
	root.get_node("WantedManager").current_stars = 2
	for i in 12: drive_by.tick(unit, 3.0)
	check(drive_by.weapon_reload.remaining == RELOAD.duration("pistol"), "passenger uses same pistol magazine and duration")
	var count := world.get_child_count()
	drive_by.tick(unit, 0.5)
	check(world.get_child_count() == count, "passenger cannot shoot during reload")
	drive_by.tick(unit, drive_by.weapon_reload.remaining + 0.001)
	check(world.get_child_count() == count + 1 and drive_by.weapon_reload.clip == 11, "passenger resumes firing only when reload finishes")
	world.queue_free()
	await process_frame
	print("POLICE_RELOAD failures=", failures)
	quit(0 if failures.is_empty() else 1)
