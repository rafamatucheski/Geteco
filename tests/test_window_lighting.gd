extends SceneTree
## Fachadas reais: cobertura noturna, ciclo diário e reconstrução estável.
const DRESSING := preload("res://world/city_look/CityChunkDressing.gd")
const MATERIALS := preload("res://world/city_look/CityLookMaterials.gd")
const FACTORY := preload("res://world/urban_detail/UrbanBuildingFactory.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func facade(source: Dictionary) -> Node3D:
	var chunk := Node3D.new()
	root.add_child(chunk)
	FACTORY.populate_chunk(chunk,source)
	DRESSING._night_pass(chunk,{"lamps":[]})
	return chunk

func panes(chunk: Node) -> Array:
	var result := []
	for node in chunk.find_children("*","GeometryInstance3D",true,false):
		if not (node is MeshInstance3D or node is MultiMeshInstance3D): continue
		var mat: Material = node.material_override
		if mat in [MATERIALS.window_lit(0),MATERIALS.window_lit(1),MATERIALS.window_lit(2),MATERIALS.window_tv()]:
			result.append(node)
	return result

func snapshot(chunk: Node) -> Array:
	var result := []
	# Godot assigns fresh automatic node names on rebuild; compare actual panes.
	for pane in panes(chunk): result.append([pane.material_override,str(pane.transform)])
	return result

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var cases := [
		{"id":"cemetery_keeper","kind":"cemetery","position":Vector3(-30,0,70),"size":Vector2(9,6)},
		{"id":"Clinic","kind":"hospital","position":Vector3(112.5,0,95.6),"size":Vector2(14,11)},
		{"id":"CanalHomesWest","kind":"brownstone","position":Vector3(307.2,0,-53.8),"size":Vector2(9,6)},
		{"id":"NorthbankHomes1","kind":"brownstone","position":Vector3(320,0,94.4),"size":Vector2(12,10)},
		{"id":"window_test_tower","kind":"urban_setback","position":Vector3(220,0,130),"size":Vector2(18,16),"height_override":32},
		{"id":"window_test_house","kind":"house_duplex","position":Vector3(250,0,130),"size":Vector2(12,10),"height_override":7}]
	MATERIALS.set_night(0)
	for source in cases:
		var chunk := facade(source)
		var windows := panes(chunk)
		check(not windows.is_empty(),source.id+": real facade has lit-window coverage")
		if source.id in ["CanalHomesWest","cemetery_keeper"]:
			var tagged := 0
			var known: Array = [MATERIALS.window_tv(),MATERIALS.flat(Color(.20,.29,.34),.18)]
			for index in MATERIALS.WINDOW_TONES.size(): known.append(MATERIALS.window_lit(index))
			for index in MATERIALS.UNLIT_VARIANTS: known.append(MATERIALS.window_unlit(index))
			for mesh in chunk.find_children("*","MeshInstance3D",true,false):
				if mesh.get_meta("city_window",false):
					tagged += 1
					check(mesh.material_override in known,source.id+": every authored pane follows night treatment")
			check(tagged==(4 if source.id=="CanalHomesWest" else 2),source.id+": all panes identified despite automatic node names")
		for pane in windows:
			check(is_zero_approx(pane.material_override.emission_energy_multiplier),source.id+": lights off during day")
		MATERIALS.set_night(.5)
		for pane in windows:
			if pane.material_override != MATERIALS.window_tv(): check(is_equal_approx(pane.material_override.emission_energy_multiplier,.9),source.id+": dusk fades gradually")
		MATERIALS.set_night(1)
		for pane in windows:
			if pane.material_override != MATERIALS.window_tv(): check(pane.material_override.emission_energy_multiplier > 1,source.id+": night emission reaches facade")
		check(chunk.find_children("*","Light3D",true,false).is_empty(),source.id+": windows add no dynamic lights")
		var original := snapshot(chunk)
		chunk.free()
		var rebuilt := facade(source)
		check(snapshot(rebuilt)==original,source.id+": same panes/materials after streaming reconstruction")
		rebuilt.free()
		MATERIALS.set_night(0)
	# Skylights and opaque frames must keep their authored material.
	var stage := Node3D.new()
	root.add_child(stage)
	for row in [["WindowGlass",Vector3(3,.08,3)],["WindowFrame",Vector3(1.5,1.4,.16)]]:
		var mesh := MeshInstance3D.new()
		mesh.name = row[0]
		mesh.mesh = BoxMesh.new()
		mesh.mesh.size = row[1]
		mesh.material_override = StandardMaterial3D.new()
		stage.add_child(mesh)
		var authored := mesh.material_override
		DRESSING._treat_window(mesh)
		check(mesh.material_override==authored,str(row[0])+": skylight/frame remains authored")
	stage.free()
	await process_frame
	print("WINDOW_LIGHTING_CONTRACT checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
