extends SceneTree

const FINISH := preload("res://world/mountain_detail/MountainShadowFinish.gd")
const TERRAIN := preload("res://world/regions/MountainTerrain3D.gd")
const VILLAGE := preload("res://world/mountain_detail/OriginalVillageArchitecture.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func _run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("Mountain shadow contract requires --no-save")
		quit(2)
		return
	var fixture := Node3D.new()
	root.add_child(fixture)
	FINISH.attach(fixture, Vector2(3.6, 4.2))
	var contacts := fixture.find_children("Mountain*Contact*", "MeshInstance3D", true, false)
	_check(contacts.size() == 3, "contact, tight contact and wall base are present")
	for contact in contacts:
		_check(contact.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "contact does not create another shadow caster")
		_check(contact.find_children("*", "CollisionShape3D", true, false).is_empty(), "contact has no collision")
	var terrain := TERRAIN.new()
	terrain.configure([], [], [])
	var ground := terrain.build_chunk(fixture, Rect2(0, 0, 64, 64))
	_check(ground != null, "mountain terrain builds")
	if ground != null:
		var arrays := ground.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		_check(vertices.size() == normals.size() and normals[0].y > 0.5, "snow terrain exposes upward normals")
		_check(not ground.find_children("*", "CollisionShape3D", true, false).is_empty(), "terrain retains physical floor")
	var village := VILLAGE.new()
	fixture.add_child(village)
	_check(village.find_children("Mountain*Contact*", "MeshInstance3D", true, false).size() == 3, "village terminal receives the same contact finish")
	for failure in failures: push_error(failure)
	print("MOUNTAIN_SHADOW_FINISH ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
