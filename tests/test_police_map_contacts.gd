extends SceneTree

const POLICE_MAP_CONTACTS := preload("res://ui/PoliceMapContacts.gd")

var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		failures.append(label)

func _initialize() -> void:
	var interval: int = POLICE_MAP_CONTACTS.BLINK_INTERVAL_MS
	check(POLICE_MAP_CONTACTS.marker_color(0) == POLICE_MAP_CONTACTS.POLICE_RED, "police marker starts red")
	check(POLICE_MAP_CONTACTS.marker_color(interval - 1) == POLICE_MAP_CONTACTS.POLICE_RED, "police marker remains red for one blink interval")
	check(POLICE_MAP_CONTACTS.marker_color(interval) == POLICE_MAP_CONTACTS.POLICE_BLUE, "police marker alternates to blue")
	check(POLICE_MAP_CONTACTS.marker_color(interval * 2) == POLICE_MAP_CONTACTS.POLICE_RED, "police marker keeps alternating red and blue")

	var source := (POLICE_MAP_CONTACTS as GDScript).source_code
	check(not source.contains("unit.global_rotation"), "police marker does not rotate with the vehicle")
	check(not source.contains("draw_colored_polygon"), "police marker no longer draws a car silhouette")
	check(source.contains("draw_circle(point, 4.0, light_color)"), "police contact is represented by a flashing dot")

	print("POLICE_MAP_CONTACTS_TEST failures=", failures)
	quit(0 if failures.is_empty() else 1)
