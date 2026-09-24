extends "res://assets/regions/source/world/mountain_pass/MountainCabin3D.gd"

var variant := 1

func _ready() -> void:
	super._ready()
	match variant:
		1: # Encosta: sleeping area east, writing desk west.
			_move(["Bed", "BedsideTable", "Chest"], Vector3(9.6, 0, 0))
			_move(["RangerDesk"], Vector3(-9.6, 0, 0))
			_remove(["AmmoCrates"])
			_move_lamp(Vector3(-3.2, 0.9, 0.8), Vector3(9.6, 0, 0))
			_move_lamp(Vector3(5, 1.15, 0.8), Vector3(-9.6, 0, 0))
		2: # Forest station: operational map table and archive in place of bedroom.
			_remove(["Bed", "BedsideTable", "Chest", "Sofa"])
			_table("ForestMapTable", Vector3(-4.7, 0, 1.7), Vector2(2.7, 1.5))
			_solid_id = &"ForestMapTable"
			_box(Vector3(-4.7, 0.97, 1.7), Vector3(2.0, 0.015, 1.1), _mat("survey_map", Color("d7d0ac")))
			for i in 7:
				_box(Vector3(-5.5 + i * .26, 1.0, 1.3 + sin(i) * .2), Vector3(.12, .06, .12), _mat("map_marker", Color("9e412c")))
			_crates("ForestArchive", Vector3(-5.5, 0, 3.5), 3)
		3: # Fishing cabin: rod repair bench, tackle and drying rack.
			_remove(["RangerDesk", "AmmoCrates", "Armchair"])
			_move(["Sofa"], Vector3(0, 0, .5))
			_table("FishingBench", Vector3(4.8, 0, -.8), Vector2(1.4, 3.0))
			_solid_id = &"FishingBench"
			for i in 4:
				_cyl(Vector3(4.45 + i * .2, 1.1, -.8), .025, 2.5, _mat("rod", Color("694a2b")), Vector3(90, 0, 0))
			_crates("TackleBoxes", Vector3(5.0, 0, 2.4), 2)
		4: # Tailor: sewing island, fabric bolts and east bedroom.
			_remove(["RangerDesk", "AmmoCrates"])
			_move(["Bed", "BedsideTable", "Chest"], Vector3(9.6, 0, 0))
			_move_lamp(Vector3(-3.2, .9, .8), Vector3(9.6, 0, 0))
			_table("SewingTable", Vector3(-4.8, 0, .5), Vector2(2.0, 1.5))
			_solid_id = &"SewingTable"
			var iron := _mat("sewing_iron", Color("243a39"), .7, .3)
			_box(Vector3(-4.8, 1.02, .5), Vector3(.8, .08, .4), iron)
			_box(Vector3(-4.55, 1.22, .5), Vector3(.14, .4, .28), iron)
			_box(Vector3(-4.85, 1.4, .5), Vector3(.65, .15, .26), iron)
			_solid_id = &"FabricRack"
			for i in 5:
				_cyl(Vector3(-5.6 + i * .4, .6, 3.0), .18, 1.2, _mat("cloth_%d" % i, [Color("a0493b"), Color("55766e"), Color("bd9c68")][i % 3]))
		5: # Musician: upright piano and stool, open rehearsal space.
			_remove(["RangerDesk", "AmmoCrates", "Armchair", "CoffeeTable"])
			_solid_id = &"UprightPiano"
			var ebony := _mat("piano_ebony", Color("211b1a"), .15, .25)
			_box(Vector3(4.9, .75, -1.0), Vector3(2.4, 1.5, .75), ebony)
			_box(Vector3(4.9, .77, -.43), Vector3(2.3, .1, .5), ebony)
			for i in 24:
				_box(Vector3(3.85 + i * .088, .84, -.4), Vector3(.08, .025, .34), _mat("ivory", Color("e4dac2")))
				if i % 7 not in [2, 6]: _box(Vector3(3.88 + i * .088, .87, -.49), Vector3(.042, .03, .16), ebony)
			_solid_id = &"PianoStool"
			_box(Vector3(4.9, .3, .55), Vector3(1.1, .6, .55), _mat("piano_velvet", Color("633c42")))
		6: # Photographer: tripod, print table and a darkroom in the old bedroom.
			_remove(["Bed", "BedsideTable", "Chest", "Armchair"])
			_table("PrintTable", Vector3(-4.8, 0, 1.8), Vector2(2.4, 1.3))
			_solid_id = &"PrintTable"
			for i in 4:
				_box(Vector3(-5.6 + i * .5, .97, 1.8), Vector3(.36, .012, .45), _mat("photo_paper", Color("ddd5c3")))
			_solid_id = &"CameraTripod"
			var steel := _mat("tripod", Color("424a4c"), .75, .4)
			for i in 3:
				var angle := i * TAU / 3.0
				_cyl(Vector3(3.8 + cos(angle) * .25, .65, 2.3 + sin(angle) * .25), .035, 1.35, steel, Vector3(sin(angle) * 20, 0, cos(angle) * 20))
			_box(Vector3(3.8, 1.45, 2.3), Vector3(.5, .32, .35), steel)
			_cyl(Vector3(3.8, 1.45, 2.03), .14, .25, steel, Vector3(90, 0, 0))
	_solid_id = &""

func _move(ids: Array, offset: Vector3) -> void:
	for part in find_children("*", "MeshInstance3D", true, false):
		if String(part.get_meta("interior_solid_id", "")) in ids: part.position += offset

func _remove(ids: Array) -> void:
	for light in find_children("*", "OmniLight3D", true, false):
		if ("BedsideTable" in ids and light.position.distance_to(Vector3(-3.2, .9, .8)) < .05) or ("RangerDesk" in ids and light.position.distance_to(Vector3(5, 1.15, .8)) < .05):
			light.get_parent().remove_child(light)
			light.free()
	for part in find_children("*", "MeshInstance3D", true, false):
		if String(part.get_meta("interior_solid_id", "")) in ids:
			part.get_parent().remove_child(part)
			part.free()

func _move_lamp(point: Vector3, offset: Vector3) -> void:
	for light in find_children("*", "OmniLight3D", true, false):
		if light.position.distance_to(point) < .05: light.position += offset

func _table(id: StringName, point: Vector3, size: Vector2) -> void:
	_solid_id = id
	var wood := _mat("variant_oak", Color("61432d"), 0, .6)
	_box(point + Vector3(0, .91, 0), Vector3(size.x, .1, size.y), wood)
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			_box(point + Vector3(x * (size.x / 2 - .14), .44, z * (size.y / 2 - .14)), Vector3(.12, .88, .12), wood)

func _crates(id: StringName, point: Vector3, count: int) -> void:
	_solid_id = id
	for i in count:
		_box(point + Vector3(i * .55, .3, 0), Vector3(.5, .6, .6), _mat("archive_wood", Color("6b5838")))
		_box(point + Vector3(i * .55, .32, -.31), Vector3(.07, .5, .02), _mat("crate_iron", Color("252e2b"), .6))
