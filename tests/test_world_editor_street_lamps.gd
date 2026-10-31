extends SceneTree
const DATA = preload("res://world/editing/WorldEditData.gd")
const RUNTIME = preload("res://world/editing/WorldEditRuntime.gd")
const REGION = preload("res://world/regions/NativeRegion.gd")
const LIBRARY = preload("res://addons/geteco_world_editor/WorldAssetLibrary.gd")
const EDITOR = preload("res://addons/geteco_world_editor/WorldEditor.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func run() -> void:
	var region := REGION.new()
	var stage := Node3D.new()
	root.add_child(stage)
	var templates := LIBRARY.build({})
	check(templates.any(func(entry): return entry.type == "light" and "braço lateral" in entry.label), "Editor library offers the street lamp")
	var saved: Dictionary = DATA.read_document().document
	var rows: Array[Dictionary] = []
	for row in saved.regions.get("harbor",{}).values():
		if row.get("type", "") == "light" and not row.get("deleted",false): rows.append(row)
	check(not rows.is_empty(), "Existing saved editor lamps are covered")
	for height in [1.0,4.0,12.0]:
		var row := DATA.new_entity("light",Vector2.ZERO)
		row.height = height
		row.rotation = 90.0
		rows.append(row)
	for row in rows:
		# Exercise saved JSON too, including the old schema without a model field.
		row = JSON.parse_string(JSON.stringify(row))
		RUNTIME.build_light(region,stage,{"data":row,"position":Vector3.ZERO})
		var lamp := stage.get_child(stage.get_child_count()-1) as Node3D
		var lights := lamp.find_children("*","OmniLight3D",true,false)
		check(lights.size()==1, "One light source per editor lamp")
		var light := lights[0] as OmniLight3D
		check(is_equal_approx(light.light_energy,float(row.energy)) and is_equal_approx(light.omni_range,float(row.range)), "Saved light settings preserved")
		check(is_equal_approx(lamp.rotation.y,deg_to_rad(float(row.rotation))), "Editor rotation reaches the whole lamp")
		var lens := lamp.get_node("Lamp") as MeshInstance3D
		var center := lens.to_global(lens.mesh.get_aabb().get_center())
		check(center.distance_to(light.global_position)<.01, "Light follows the lateral lens after rotation")
		check(Vector2(light.position.x,light.position.z).length()>1.0, "Head extends laterally beyond the shaft")
		var probe := CharacterBody3D.new()
		probe.collision_layer = 2
		probe.collision_mask = 1
		var collider := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = .3
		capsule.height = 1.7
		collider.shape = capsule
		collider.position.y = .85
		probe.add_child(collider)
		stage.add_child(probe)
		await physics_frame
		probe.position = Vector3(-2,0,0)
		check(probe.move_and_collide(Vector3(4,0,0),true)!=null, "Pole blocks pedestrian sweep")
		# Varre sob o braço no referencial local girado do poste.
		probe.position = lamp.to_global(Vector3(-2,0,1))
		var hit := probe.move_and_collide(lamp.basis * Vector3(4,0,0),true)
		check((hit==null) == (float(row.height)>1.8), "Walk under a raised arm; a lowered arm stays solid")
		probe.free()
		lamp.free()
	stage.free()
	region.free()
	print("WORLD_EDITOR_STREET_LAMPS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
