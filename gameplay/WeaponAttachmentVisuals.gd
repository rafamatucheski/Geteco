extends RefCounted
const GEO = preload("res://gameplay/WeaponPresentation3D.gd")
const CUSTOM = preload("res://gameplay/WeaponCustomization.gd")
const FINISHES := {"matte":Color("282d32"), "sand":Color("b9a175"), "olive":Color("596348"), "chrome":Color("b9c9d3"), "wood":Color("73452c"), "gold":Color("d8b048")}
## Extensão do cano longo; peças de bocal vão para a nova boca.
const LONG_BARREL := .075

static func apply(root: Node3D, id: String, entry: Dictionary, muzzle: Vector3) -> void:
	var parts: Dictionary = entry.get("parts",{})
	# Peças de arma branca recolorem só o material que representam (madeira do
	# taco, aço da lâmina, latão da soqueira); o acabamento vem depois e prevalece.
	for slot in ["edge", "handle", "finish"]:
		var part: String = parts.get(slot, "none")
		if CUSTOM.PARTS.has(part) and CUSTOM.PARTS[part].has("recolor"): _recolor(root, CUSTOM.PARTS[part])
	var finish: String = parts.get("finish","none")
	if FINISHES.has(finish): _finish(root,finish)
	var steel := _mat(Color("252b30"), .7, .4)
	if id in CUSTOM.MELEE:
		_melee(root, id, parts, steel)
		return
	# The M4 effect anchor is 1 cm ahead of its authored barrel end. A short
	# mounting sleeve joins attachments to the barrel without moving their mouth.
	if id == "m4a1" and (parts.get("barrel", "") == "barrel_long" or parts.get("muzzle", "") in ["suppressor", "compensator"]):
		GEO._cylinder(root,"MuzzleMount",muzzle+Vector3(0,0,.0045),.015,.013,steel,Vector3(90,0,0))
	var mouth := muzzle
	if parts.get("barrel","") == "barrel_long":
		GEO._cylinder(root,"LongBarrel",muzzle+Vector3(0,0,-LONG_BARREL*.5),.012,LONG_BARREL,steel,Vector3(90,0,0))
		mouth = muzzle + Vector3(0,0,-LONG_BARREL)
	elif parts.get("barrel","") == "barrel_short":
		# Cano curto: guarda-mão vazado mais curto que marca a troca.
		GEO._box(root,"ShortHandguard",muzzle+Vector3(0,-.006,.07),Vector3(.036,.034,.06),steel)
	match str(parts.get("muzzle","")):
		"suppressor": GEO._cylinder(root,"Suppressor",mouth+Vector3(0,0,-.068),.025,.145,steel,Vector3(90,0,0))
		"compensator":
			GEO._box(root,"Compensator",mouth+Vector3(0,0,-.024),Vector3(.03,.03,.048),steel)
			var port := _mat(Color("0d0f10"), .2, .8)
			for z in [-.012,-.028]: GEO._box(root,"CompensatorPort",mouth+Vector3(0,.0155,z),Vector3(.018,.002,.007),port)
		"choke_full": GEO._cylinder(root,"ChokeTube",mouth+Vector3(0,0,-.02),.017,.04,_mat(Color("8c7a4a"), .75, .35),Vector3(90,0,0))
		"duckbill": GEO._box(root,"Duckbill",mouth+Vector3(0,0,-.03),Vector3(.06,.014,.06),steel)
		"flame_focus": _cone(root,"FocusNozzle",mouth+Vector3(0,0,-.05),.028,.008,.10,steel,Vector3(-90,0,0))
		"flame_wide": GEO._box(root,"FanNozzle",mouth+Vector3(0,0,-.035),Vector3(.09,.018,.07),steel)
	if parts.has("laser"):
		var lens := _mat(Color("67ed8b") if parts.laser == "laser_green" else Color("f54d49"), .0, .5)
		GEO._box(root,"LaserModule",Vector3(-.039,muzzle.y-.025,muzzle.z+.085),Vector3(.026,.025,.065),steel)
		GEO._cylinder(root,"LaserLens",Vector3(-.039,muzzle.y-.025,muzzle.z+.051),.006,.002,lens,Vector3(90,0,0))
	match str(parts.get("magazine","")):
		"extended":
			if id == "shotgun":
				GEO._cylinder(root,"ExtendedMagazineTube",Vector3(0,-.015,muzzle.z+.09),.018,.17,steel,Vector3(90,0,0))
			elif id == "ak47":
				GEO._profile(root,"ExtendedMagazine",PackedVector2Array([Vector2(-.065,-.17),Vector2(-.115,-.15),Vector2(-.13,-.19),Vector2(-.095,-.225),Vector2(-.073,-.2)]),.031,steel)
			else:
				GEO._box(root,"ExtendedMagazine",Vector3(0,-.115,.016 if id == "pistol" else -.035),Vector3(.035,.085,.047),steel)
		"drum":
			var z := -.09 if id == "ak47" else -.035
			GEO._cylinder(root,"DrumMagazine",Vector3(0,-.12,z),.065,.05,steel,Vector3(0,0,90))
			GEO._box(root,"DrumFeed",Vector3(0,-.06,z),Vector3(.03,.05,.04),steel)
		"quick_mag":
			GEO._box(root,"MagPull",Vector3(0,-.10 if id == "pistol" else -.16,.016 if id == "pistol" else -.035),Vector3(.02,.012,.03),_mat(Color("c8662b"), .0, .8))
		"speedloader":
			GEO._cylinder(root,"SpeedloaderPouch",Vector3(.035,-.03,.02),.018,.03,_mat(Color("2b2622"), .0, .85),Vector3(90,0,0))
		"big_tank":
			GEO._cylinder(root,"SecondTank",Vector3(.06,-.02,muzzle.z+.3),.035,.2,_mat(Color("8a2a22"), .4, .5),Vector3(90,0,0))
	match str(parts.get("grip","")):
		"vertical_grip": GEO._box(root,"ControlGrip",Vector3(0,-.09,-.14),Vector3(.032,.105,.035),steel)
		"angled_grip":
			var grip := MeshInstance3D.new()
			grip.name = "AngledGrip"
			grip.mesh = BoxMesh.new()
			grip.mesh.size = Vector3(.03,.06,.07)
			grip.material_override = steel
			grip.position = Vector3(0,-.055,-.13)
			grip.rotation_degrees.x = 35
			root.add_child(grip)
	if parts.has("stock"):
		# The authored meshes are material-batched before customization; use their
		# measured attachment coordinates, not names removed by the batching pass.
		var butt_z := .182 if id == "hunting_rifle" else (.29 if id == "ak47" else (.19 if id == "smg" else .25))
		GEO._box(root,"StabilizedButtPad",Vector3(0,.01 if id == "smg" else -.02,butt_z),Vector3(.055,.14 if id == "hunting_rifle" else .095,.025),steel)
	if parts.has("scope"):
		if id == "hunting_rifle":
			# Upgrade the existing optic's objective rather than stacking a second.
			GEO._cylinder(root,"UpgradedObjective",Vector3(0,.097,-.222),.034,.042,steel,Vector3(90,0,0))
			GEO._cylinder(root,"UpgradedObjectiveLens",Vector3(0,.097,-.244),.029,.002,_mat(Color("477d87"), .45, .5),Vector3(90,0,0))
			return
		GEO._box(root,"ScopeMount",Vector3(0,.045,-.045),Vector3(.035,.05,.095),steel)
		GEO._cylinder(root,"ScopeTube",Vector3(0,.086,-.045),.027,.19,steel,Vector3(90,0,0))
		GEO._cylinder(root,"ScopeLens",Vector3(0,.086,-.141),.025,.002,_mat(Color("477d87"), .45, .5),Vector3(90,0,0))

## Coordenadas medidas nos modelos de `assets/.../player/WeaponPresentation3D.gd`
## (frente da arma em −Z).
static func _melee(root: Node3D, id: String, parts: Dictionary, steel: StandardMaterial3D) -> void:
	var edge: String = parts.get("edge", "none")
	var handle: String = parts.get("handle", "none")
	var bright := _mat(Color("aeb8bf"), .9, .25)
	match id:
		"knife":
			if edge == "serrated":
				for i in 6:
					var tooth := MeshInstance3D.new()
					tooth.name = "SerrationTooth"
					tooth.mesh = BoxMesh.new()
					tooth.mesh.size = Vector3(.006,.008,.008)
					tooth.material_override = bright
					tooth.position = Vector3(0,.021,-.06-i*.018)
					tooth.rotation_degrees.x = 45
					root.add_child(tooth)
			elif edge == "tanto":
				GEO._profile(root,"TantoPoint",PackedVector2Array([Vector2(-.17,-.018),Vector2(-.255,-.018),Vector2(-.255,.004),Vector2(-.17,.021)]),.008,bright)
			elif edge == "balanced":
				GEO._box(root,"Fuller",Vector3(0,.003,-.11),Vector3(.0085,.006,.10),_mat(Color("15191c"), .5, .5))
			if handle == "paracord":
				var cord_a := _mat(Color("c8662b"), .0, .9)
				var cord_b := _mat(Color("3d4630"), .0, .9)
				for i in 9: GEO._cylinder(root,"Paracord",Vector3(0,0,-.025+i*.012),.02,.009,cord_a if i % 2 == 0 else cord_b,Vector3(90,0,0))
			elif handle == "knuckle_guard":
				var brass := _mat(Color("b7955b"), .65, .38)
				GEO._box(root,"GuardBow",Vector3(0,-.045,.02),Vector3(.01,.01,.11),brass)
				for z in [-.035,.075]: GEO._box(root,"GuardPost",Vector3(0,-.031,z),Vector3(.01,.03,.01),brass)
		"bat":
			if edge == "nails":
				for z in [-.37,-.42,-.47]:
					for k in 6:
						var angle: float = TAU * k / 6.0 + (.5 if z == -.42 else 0.0)
						GEO._cylinder(root,"Nail",Vector3(cos(angle)*.038,sin(angle)*.038,z),.003,.026,bright,Vector3(0,0,rad_to_deg(angle)-90))
			elif edge == "barbed_wire":
				for z in [-.30,-.35,-.40,-.45]:
					var ring := MeshInstance3D.new()
					ring.name = "BarbedWire"
					var torus := TorusMesh.new()
					torus.inner_radius = .031
					torus.outer_radius = .036
					torus.rings = 16
					torus.ring_segments = 4
					ring.mesh = torus
					ring.material_override = steel
					ring.position = Vector3(0,0,z)
					ring.rotation.x = PI * .5
					root.add_child(ring)
					for k in 3:
						var angle: float = TAU * k / 3.0 + z * 9.0
						GEO._box(root,"Barb",Vector3(cos(angle)*.037,sin(angle)*.037,z),Vector3(.012,.012,.004),steel)
			if handle == "grip_tape": GEO._cylinder(root,"GripTape",Vector3(0,0,.08),.0195,.15,_mat(Color("b3261e"), .0, .9),Vector3(90,0,0))
			elif handle == "long_handle":
				GEO._cylinder(root,"HandleExtension",Vector3(0,0,.215),.018,.07,_mat(Color("252629"), .0, .86),Vector3(90,0,0))
				GEO._cylinder(root,"ExtendedPommel",Vector3(0,0,.255),.025,.02,_mat(Color("714331"), .0, .62),Vector3(90,0,0))
		"axe":
			if edge == "fire_axe":
				# O fio aponta para +X (cabeça girada −90° em Z); o pico vai do lado oposto.
				_cone(root,"FirePick",Vector3(-.10,0,-.445),.02,.0,.10,_mat(Color("222b30"), .62, .42),Vector3(0,0,90))
			if handle == "long_handle":
				GEO._cylinder(root,"HandleExtension",Vector3(0,0,.20),.019,.09,_mat(Color("714331"), .0, .62),Vector3(90,0,0))
		"knuckles":
			if edge == "spikes":
				for i in 4: _cone(root,"KnuckleSpike",Vector3(-.033+i*.022,.008,-.062),.007,.0,.032,bright,Vector3(-90,0,0))
			elif edge == "weighted":
				GEO._box(root,"WeightBar",Vector3(0,.008,-.052),Vector3(.09,.022,.016),_mat(Color("30363b"), .8, .35))
			if handle == "padded_palm":
				GEO._box(root,"PalmPad",Vector3(0,-.015,.03),Vector3(.09,.024,.02),_mat(Color("5a3521"), .0, .8))
			elif handle == "push_blade":
				GEO._profile(root,"PushBlade",PackedVector2Array([Vector2(-.03,-.03),Vector2(-.085,-.022),Vector2(-.03,-.012)]),.004,bright)

static func _cone(root: Node3D, label: String, p: Vector3, bottom: float, top: float, length: float, mat: Material, angles: Vector3) -> void:
	var part := MeshInstance3D.new()
	part.name = label
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = length
	mesh.radial_segments = 10
	part.mesh = mesh
	part.material_override = mat
	part.position = p
	part.rotation_degrees = angles
	root.add_child(part)

static func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material

## Troca só as superfícies cuja cor de origem é a do material alvo. Por
## superfície: o modelo pode ter sido agrupado por material em uma malha só.
static func _recolor(node: Node, info: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var mesh_node := node as MeshInstance3D
		for surface in mesh_node.mesh.get_surface_count():
			var source: Material = mesh_node.material_override if mesh_node.material_override != null else mesh_node.get_active_material(surface)
			if not source is StandardMaterial3D: continue
			var target: Variant = _target(info.recolor, source.albedo_color)
			if target == null: continue
			var material: StandardMaterial3D = source.duplicate()
			material.albedo_color = target
			if info.has("metallic"): material.metallic = info.metallic
			if info.has("roughness"): material.roughness = info.roughness
			if mesh_node.material_override != null:
				mesh_node.material_override = material
				break
			mesh_node.set_surface_override_material(surface, material)
	for child in node.get_children(): _recolor(child, info)

static func _target(recolor: Dictionary, color: Color) -> Variant:
	for key in recolor:
		var wanted := Color(str(key))
		if absf(wanted.r - color.r) + absf(wanted.g - color.g) + absf(wanted.b - color.b) < .03: return recolor[key]
	return null

static func _finish(node: Node, finish: String) -> void:
	if node is MeshInstance3D:
		var source: Material = node.material_override
		if source == null and node.mesh != null and node.mesh.get_surface_count() > 0: source = node.get_active_material(0)
		if source is StandardMaterial3D and not source.emission_enabled and source.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			# Duplicate per mesh: never recolor another weapon or a shared material.
			var material: StandardMaterial3D = source.duplicate()
			material.albedo_color = FINISHES[finish].lerp(source.albedo_color,.18)
			material.metallic = .93 if finish in ["chrome", "gold"] else (.0 if finish == "wood" else .32)
			material.roughness = .2 if finish in ["chrome", "gold"] else .68
			node.material_override = material
	for child in node.get_children(): _finish(child,finish)
