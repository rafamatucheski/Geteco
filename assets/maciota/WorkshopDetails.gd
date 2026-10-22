extends RefCounted
## Architectural finishes remain in the workshop's cached 3D render.
static func build(room: Node3D) -> void:
	for child in room.get_children():
		if child is MeshInstance3D and child.material_override != null and child.position.y < .02:
			if child.material_override.resource_name in ["persian_carpet", "carpet_gold_fringe"]:
				child.position.y += .016
	var concrete := material("596165", 0.92)
	var grout := material("333d41", 0.95)
	var steel := material("263740", 0.4, 0.65)
	var silver := material("aab9bc", 0.28, 0.75)
	var brass := material("b68c48", 0.35, 0.6)
	var wood := material("62432d", 0.62)
	var dark_wood := material("33281f", 0.72)
	var ivory := material("c9c5af", 0.72)
	var teal := material("28524f", 0.68)
	var warm := material("ffd5a0", 0.4)
	warm.emission_enabled = true
	warm.emission = Color("ffd5a0")
	warm.emission_energy_multiplier = 1.1
	var cool := material("d4ebef", 0.4)
	cool.emission_enabled = true
	cool.emission = Color("d4ebef")
	cool.emission_energy_multiplier = 0.7
	# Continuous surrounding structure and driveway anchor the cutaway room.
	box(room, "BuildingFoundation", Vector3(1, -.24, 0), Vector3(50, .32, 40), concrete)
	box(room, "RearBuildingMass", Vector3(1.15, 1.9, -9.3), Vector3(50, 3.8, 10), steel)
	for x in range(-16, 19, 2):
		box(room, "ApronJoint", Vector3(x, -.073, 9), Vector3(.025, .012, 14), grout)
	for z in range(5, 18, 2):
		box(room, "ApronJoint", Vector3(1, -.073, z), Vector3(48, .012, .025), grout)
	# Service floor has slab seams, an inset drain and a robust gate threshold.
	# A oficina vai de X -8.2 a 2.3 desde a ampliação de 21/10/2026 (WorkshopProps.EXTENSION_X).
	for x in [-7.7, -5.5, -3.3, -1.1, 1.1]:
		box(room, "SlabJoint", Vector3(x, .005, .25), Vector3(.018, .01, 8.7), grout)
	for z in [-2.3, .0, 2.3]:
		box(room, "SlabJoint", Vector3(-2.95, .005, z), Vector3(10.5, .01, .018), grout)
	box(room, "GateThreshold", Vector3(0, .018, 4.58), Vector3(4.2, .035, .24), silver)
	box(room, "DrainRecess", Vector3(0, .01, 3.78), Vector3(3.5, .025, .18), steel)
	for i in 48:
		box(room, "DrainGrille", Vector3(-1.7 + i * .072, .03, 3.78), Vector3(.018, .018, .17), silver)
	# Individually laid oak boards, staggered end joints and brass skirting.
	for row in 29:
		var z := -4.08 + row * .303
		var tone := material(Color("634630").lightened(float(row % 4) * .025).to_html(), .64)
		box(room, "OakBoard", Vector3(4.5, .004, z), Vector3(4.12, .012, .286), tone)
		var x := 3.1 + float(row % 3) * 1.1
		box(room, "OakEndJoint", Vector3(x, .012, z), Vector3(.012, .008, .286), dark_wood)
	for x in [2.47, 6.47]:
		box(room, "OfficeSkirting", Vector3(x, .06, -1.7), Vector3(.045, .12, 4.8), brass)
	# Rear wall: ivory service tiles, green office panels and pilasters.
	box(room, "ServiceWallTiles", Vector3(-2.95, .8, -4.075), Vector3(10.5, 1.6, .035), ivory)
	for x in range(21):
		box(room, "TileJoint", Vector3(-8.1 + x * .5, .8, -4.05), Vector3(.012, 1.6, .012), grout)
	for y in [.4, .8, 1.2]:
		box(room, "TileJoint", Vector3(-2.95, y, -4.045), Vector3(10.5, .012, .012), grout)
	box(room, "OfficePanelWall", Vector3(4.5, 1.8, -4.065), Vector3(4.1, 3.5, .06), teal)
	for x in [2.6, 3.55, 4.5, 5.45, 6.4]:
		box(room, "PanelMoulding", Vector3(x, 1.6, -4.015), Vector3(.045, 3.1, .04), brass)
	box(room, "PictureRail", Vector3(4.5, 2.92, -4.005), Vector3(4.12, .055, .055), brass)
	# -4.14 marca onde ficava a parede esquerda antes da ampliação: vira pilar da nova vão.
	for x in [-8.14, -4.14, 2.33, 6.45]:
		box(room, "SteelColumn", Vector3(x, 1.88, -4.02), Vector3(.13, 3.76, .16), steel)
	# High clerestory windows illuminate the workshop without obscuring the bay.
	# A segunda janela fica sobre a estante de peças, à direita da escada da cobertura.
	for window in [[-1.0, 5.2, [-2.65, -1, .65]], [-5.4, 1.8, [-5.4]]]:
		box(room, "WindowFrame", Vector3(window[0], 2.75, -4.045), Vector3(window[1], 1.02, .14), silver)
		box(room, "WindowGlass", Vector3(window[0], 2.75, -3.96), Vector3(window[1] - .2, .84, .025), cool)
		for x in window[2]:
			box(room, "WindowMullion", Vector3(x, 2.75, -3.93), Vector3(.035, .88, .04), steel)
		box(room, "WindowMullion", Vector3(window[0], 2.75, -3.93), Vector3(window[1] - .2, .035, .04), steel)
	# Shelves on the existing office safe wall: books, trophies and record sleeves.
	for y in [1.15, 1.65, 2.15]:
		box(room, "OfficeShelf", Vector3(5.77, y, -3.73), Vector3(1.22, .065, .46), wood)
		for i in 7:
			var book := material(["71483e", "253c45", "b49e68", "4d5c43"][i % 4], .8)
			box(room, "Book", Vector3(5.29 + i * .135, y + .17, -3.7), Vector3(.10, .26 + (i % 3) * .035, .26), book)
	# Tool silhouettes on a pegboard above the existing workbench.
	box(room, "Pegboard", Vector3(-1.0, 1.65, -3.99), Vector3(2.1, .85, .08), dark_wood)
	for i in 8:
		var x := -1.85 + i * .24
		box(room, "HangingTool", Vector3(x, 1.64, -3.91), Vector3(.035, .32, .03), silver)
		box(room, "ToolHead", Vector3(x, 1.8, -3.90), Vector3(.10, .075, .05), silver)
	# Low foreground returns reveal wall thickness without masking feet or the door.
	for x in [-5.2, 4.5]:
		box(room, "CutawayWallCap", Vector3(x, .25, 4.7), Vector3(5.98 if x < 0 else 4.18, .05, .24), silver)
	# Dedicated task lighting, cached with the rest of the furniture.
	for point in [Vector3(-1, 3.0, -1), Vector3(4.5, 2.8, -1.4)]:
		var light := OmniLight3D.new()
		light.position = point
		light.light_color = Color("f6d4a3") if point.x > 2 else Color("d9ebff")
		light.light_energy = 1.25
		light.omni_range = 6
		room.add_child(light)
	for x in [3.0, 6.1]:
		box(room, "OfficeSconce", Vector3(x, 2.5, -3.9), Vector3(.20, .34, .18), warm)
	_used_workshop(room, steel, silver, brass, dark_wood)

static func _used_workshop(room: Node3D, steel: Material, silver: Material, brass: Material, wood: Material) -> void:
	for part in room.get_children():
		if not part is MeshInstance3D or not part.mesh is BoxMesh or part.material_override == null: continue
		var identity: String = part.material_override.resource_name
		if identity in ["boss_leather","visitor_leather","executive_mahogany"]:
			part.mesh = preload("res://world/desert/village/DesertHomeCraft.gd").rounded_box(part.mesh.size,.035)
			var finish := preload("res://world/places/ShopInteriorMaterials.gd").material("wood" if identity == "executive_mahogany" else "cloth",part.material_override.albedo_color)
			part.material_override = finish
	# Flat, opaque stains: no lights, particles, physics or frame updates.
	var oil := material("3a403b", .32)
	for i in 12:
		var stain := MeshInstance3D.new()
		stain.name = "OldOilStain"
		var disc := SurfaceTool.new()
		disc.begin(Mesh.PRIMITIVE_TRIANGLES)
		var radius := .12 + float(i % 4) * .065
		for edge in 13:
			var a := float(edge)*TAU/13
			var b := float(edge+1)*TAU/13
			var ra := radius*(.78+.18*sin(edge*2.1+i))
			var rb := radius*(.78+.18*sin((edge+1)*2.1+i))
			disc.set_normal(Vector3.UP)
			for vertex in [Vector3.ZERO,Vector3(cos(a)*ra,0,sin(a)*ra),Vector3(cos(b)*rb,0,sin(b)*rb)]: disc.add_vertex(vertex)
		stain.mesh = disc.commit()
		stain.material_override = oil
		stain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stain.position = Vector3(-.65 + sin(i * 2.4) * .6, .018 + float(i) * .0002, -.6 + cos(i * 1.7) * .85)
		stain.scale.z = .55 + float(i % 3) * .16
		room.add_child(stain)
	# Hand tools and oily rag stay within the existing tool chest footprint.
	box(room,"GreasyRag",Vector3(-3.46,1.103,-2.02),Vector3(.31,.018,.23),material("716b54",.98))
	for i in 4:
		var x := -3.72 + i * .15
		box(room,"SocketRail",Vector3(x,1.12,-2.22),Vector3(.07,.065,.07),silver)
	# A small radio on the rear workbench gives the mechanic a lived-in station.
	box(room,"WorkshopRadio",Vector3(-1.65,1.08,-3.75),Vector3(.33,.26,.17),steel)
	box(room,"RadioGrille",Vector3(-1.69,1.08,-3.656),Vector3(.2,.17,.014),wood)
	box(room,"RadioDial",Vector3(-1.52,1.08,-3.65),Vector3(.035,.06,.022),brass)
	# Personal desk props, inside its existing solid; no new floor obstacles.
	box(room,"LeatherLedger",Vector3(4.67,.79,-1.65),Vector3(.27,.045,.35),material("633848",.8))
	box(room,"LedgerPages",Vector3(4.67,.795,-1.65),Vector3(.25,.021,.32),material("d4c5a2",.95))
	box(room,"DeskPen",Vector3(4.83,.785,-1.62),Vector3(.014,.014,.19),brass)
	box(room,"TelephoneBase",Vector3(4.9,.81,-2.06),Vector3(.24,.09,.17),steel)
	box(room,"TelephoneReceiver",Vector3(4.9,.883,-2.06),Vector3(.29,.045,.06),wood)
	var carpet := material("b39155",.95)
	for side in [-1,1]:
		for index in 7:
			var motif := box(room,"WovenRugMotif",Vector3(3.42+index*.35,.035,-1.8+side*.72),Vector3(.12,.003,.12),carpet)
			motif.rotation.y = PI*.25
	for side in [-1,1]:
		for index in 10:
			box(room,"TyreWear",Vector3(side*.8,.012,.7+index*.22),Vector3(.17,.002,.035),material("4c5353",.98))
	# Stitched leather and brass studs enrich the existing chair back.
	for x in [4.31,4.5,4.69]:
		for y in [.72,.91,1.1]:
			box(room,"LeatherButton",Vector3(x,y,-2.875),Vector3(.022,.022,.012),brass)

static func material(hex: String, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = Color(hex)
	result.roughness = roughness
	result.metallic = metallic
	return result

static func box(parent: Node3D, label: String, point: Vector3, size: Vector3, surface: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.set_meta("detail_id", label)
	# SceneTree renames duplicate node names; classify by authored identity.
	if label == "ApronJoint": node.hide()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	if label in ["RearBuildingMass", "OfficeShelf", "SteelColumn", "ServiceWallTiles", "OfficePanelWall", "CutawayWallCap"]:
		node.set_meta("interior_solid_id", StringName("Detail%d" % node.get_instance_id()))
	node.position = point
	node.material_override = surface
	parent.add_child(node)
	return node
