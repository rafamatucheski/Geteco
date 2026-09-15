extends RefCounted
## Shared visual kit: shop displays and product viewer use the same geometry.
const P = preload("res://characters/pedestrians/CitizenDetails.gd")
const ARSENAL = preload("res://scripts/player/ArsenalWeapon3D.gd")
const RED = Color("a3322d")
const INK = Color("222b2d")
const CREAM = Color("eee1bf")
const OLIVE = Color("626b46")

static func box(root: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	return P.piece(root, size, pos, color)

static func text(root: Node3D, words: String, pos: Vector3, pixels := .009, color := CREAM) -> Label3D:
	var label := Label3D.new()
	label.text = words
	label.position = pos
	label.pixel_size = pixels
	label.font_size = 48
	label.modulate = color
	label.outline_size = 0
	root.add_child(label)
	return label

static func target(root: Node3D, pos: Vector3, radius: float) -> void:
	for i in 3:
		var ring := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = radius * (1.0 - i * .29) - .025
		mesh.outer_radius = radius * (1.0 - i * .29)
		mesh.rings = 32
		mesh.ring_segments = 8
		ring.mesh = mesh
		ring.rotation.x = PI * .5
		ring.position = pos
		var mat := StandardMaterial3D.new()
		mat.albedo_color = CREAM
		ring.material_override = mat
		root.add_child(ring)
	box(root, Vector3(radius*2.5,.025,.025), pos, CREAM)
	box(root, Vector3(.025,radius*2.5,.025), pos, CREAM)

static func item(root: Node3D, id: String) -> void:
	if id == "armor":
		box(root,Vector3(.46,.48,.17),Vector3(0,0,0),OLIVE)
		for side in [-1,1]:
			box(root,Vector3(.11,.18,.14),Vector3(side*.17,.28,0),OLIVE)
			box(root,Vector3(.20,.09,.035),Vector3(side*.25,-.06,0),INK)
			for row in 3:
				box(root,Vector3(.16,.07,.055),Vector3(side*.105,.04-row*.10,.105),Color("424b35"))
		box(root,Vector3(.26,.06,.025),Vector3(0,.17,.10),CREAM)
		text(root,"A / N",Vector3(0,.17,.12),.0009,INK)
		return
	ARSENAL.build(root,id)
	if id == "grenade":
		for row in 4:
			for col in 8:
				var angle := col*TAU/8
				var tile := box(root,Vector3(.023,.014,.014),Vector3(sin(angle)*.042,-.03+row*.019,-.10+cos(angle)*.042),OLIVE)
				tile.rotation.y = angle
		box(root,Vector3(.015,.013,.095),Vector3(0,.064,-.075),INK)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = .014
		torus.outer_radius = .019
		ring.mesh = torus
		ring.position = Vector3(.025,.058,-.10)
		ring.rotation.x = PI*.5
		root.add_child(ring)
		return
	if id in ["knife","axe","knuckles","bat","hunting_rifle","rpg"]: return
	# Machined details at display scale: rails, ejection port, screws and trigger guard.
	for side in [-1,1]:
		box(root,Vector3(.006,.023,.055),Vector3(side*.026,.022,-.025),Color("111619"))
		for z in [-.048,.015]:
			P.piece(root,Vector3(.009,.009,.009),Vector3(side*.031,.023,z),Color("969b9b"),true)
	if id in ["ak47","m4a1","smg"]:
		for i in 7:
			box(root,Vector3(.054,.007,.008),Vector3(0,.052,-.11+i*.018),INK)
	box(root,Vector3(.012,.06,.012),Vector3(0,-.063,-.031),INK)
	box(root,Vector3(.012,.012,.07),Vector3(0,-.091,.0),INK)
	if id in ["shotgun","sawed_off"]:
		for i in 7: box(root,Vector3(.056,.055,.005),Vector3(0,-.01,-.21+i*.016),Color("69432b"))
	if id in ["ak47","m4a1","smg"]:
		for i in 5: box(root,Vector3(.031,.006,.056),Vector3(0,-.06-i*.022,-.055),Color("505654"))
	for part in root.get_children():
		if part is MeshInstance3D and part.mesh is BoxMesh:
			part.mesh = bevel_box(part.mesh.size)
	if id=="magnum":
		for i in 6:
			var angle := i*TAU/6
			P.piece(root,Vector3(.015,.015,.004),Vector3(sin(angle)*.020,.01+cos(angle)*.020,-.043),Color("111719"),true)

static func bevel_box(size: Vector3) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profile := [Vector2(-.35,-.5),Vector2(.35,-.5),Vector2(.5,-.35),Vector2(.5,.35),Vector2(.35,.5),Vector2(-.35,.5),Vector2(-.5,.35),Vector2(-.5,-.35)]
	var rings := []
	for level in 4:
		var ring := []
		var width: float = .82 if level in [0,3] else 1.0
		var height: float = [-.5,-.38,.38,.5][level]
		for point in profile: ring.append(Vector3(point.x*size.x*width,height*size.y,point.y*size.z*width))
		rings.append(ring)
	for level in 3:
		for i in 8:
			var j := (i+1)%8
			for vertex in [rings[level][i],rings[level+1][i],rings[level+1][j],rings[level][i],rings[level+1][j],rings[level][j]]: surface.add_vertex(vertex)
	for i in range(1,7):
		for vertex in [rings[0][0],rings[0][i+1],rings[0][i],rings[3][0],rings[3][i],rings[3][i+1]]: surface.add_vertex(vertex)
	surface.generate_normals()
	return surface.commit()

static func gunsmith(root: Node3D) -> Node3D:
	var npc := Node3D.new()
	npc.name = "VanceMilitaryGunsmith"
	root.add_child(npc)
	var skin := Color("b78360")
	for side in [-1,1]:
		box(npc,Vector3(.20,.76,.24),Vector3(side*.14,.51,0),OLIVE)
		box(npc,Vector3(.23,.20,.36),Vector3(side*.14,.10,.07),INK)
		box(npc,Vector3(.23,.22,.035),Vector3(side*.14,.54,.14),Color("48543c"))
		var arm := box(npc,Vector3(.20,.48,.23),Vector3(side*.36,1.24,0),OLIVE)
		arm.rotation.z = side*.10
		box(npc,Vector3(.16,.27,.17),Vector3(side*.38,.94,.04),skin)
		box(npc,Vector3(.17,.12,.20),Vector3(side*.38,.80,.07),INK)
		for row in 3:
			box(npc,Vector3(.13,.055,.025),Vector3(side*.14,.35+row*.15,.128),Color("827b50"))
	box(npc,Vector3(.56,.63,.34),Vector3(0,1.19,0),OLIVE)
	var vest := Node3D.new()
	npc.add_child(vest)
	item(vest,"armor")
	vest.position = Vector3(0,1.19,.13)
	box(npc,Vector3(.53,.08,.37),Vector3(0,.87,0),INK)
	box(npc,Vector3(.10,.065,.025),Vector3(0,.87,.20),CREAM)
	P.piece(npc,Vector3(.36,.36,.31),Vector3(0,1.71,0),skin,true)
	box(npc,Vector3(.17,.12,.17),Vector3(0,1.49,0),skin)
	box(npc,Vector3(.35,.08,.30),Vector3(0,1.87,0),OLIVE)
	box(npc,Vector3(.33,.035,.18),Vector3(0,1.84,.19),OLIVE)
	box(npc,Vector3(.07,.045,.02),Vector3(0,1.87,.16),CREAM)
	for side in [-1,1]:
		P.piece(npc,Vector3(.07,.10,.065),Vector3(side*.18,1.70,0),skin,true)
		box(npc,Vector3(.08,.025,.025),Vector3(side*.075,1.75,.145),INK)
		box(npc,Vector3(.034,.018,.026),Vector3(side*.07,1.71,.155),Color("1a2021"))
	P.piece(npc,Vector3(.06,.08,.065),Vector3(0,1.67,.17),skin.lightened(.1),true)
	box(npc,Vector3(.18,.045,.025),Vector3(0,1.60,.135),Color("56473b"))
	text(npc,"VANCE",Vector3(.12,1.40,.24),.00055)
	return npc

static func room(root: Node3D) -> void:
	box(root,Vector3(14,.16,10),Vector3(0,-.09,0),Color("535954"))
	for x in range(-7,8): box(root,Vector3(.018,.014,10),Vector3(x,0,0),Color("7b8075"))
	for z in range(-5,6): box(root,Vector3(14,.014,.018),Vector3(0,0,z),Color("7b8075"))
	box(root,Vector3(14,3,.22),Vector3(0,1.5,-5),INK)
	for side in [-1,1]:
		box(root,Vector3(.22,2.4,10),Vector3(side*7,1.2,0),INK)
		box(root,Vector3(.25,.14,10),Vector3(side*6.98,1.9,0),RED)
	box(root,Vector3(14,.72,.08),Vector3(0,2.55,-4.83),RED)
	text(root,"AMMU-NATION",Vector3(0,2.62,-4.76),.015)
	text(root,"ARMAS  /  MUNIÇÃO  /  EQUIPAMENTO",Vector3(0,2.21,-4.75),.0043)
	target(root,Vector3(-3.7,2.6,-4.73),.27)
	target(root,Vector3(3.7,2.6,-4.73),.27)
	for side in [-1,1]:
		box(root,Vector3(3.5,1.7,.10),Vector3(side*4.8,1.2,-4.8),Color("384440"))
		for x in 12:
			for y in 5: box(root,Vector3(.024,.024,.018),Vector3(side*4.8-1.55+x*.28,.52+y*.27,-4.73),Color("1b2524"))
		for i in 3:
			var weapon := Node3D.new()
			root.add_child(weapon)
			item(weapon,["shotgun","ak47","m4a1","smg","magnum","hunting_rifle"][i+(0 if side<0 else 3)])
			weapon.position = Vector3(side*4.8,.65+i*.49,-4.51)
			weapon.rotation.y = PI*.5
			weapon.scale = Vector3.ONE*2.25
		box(root,Vector3(3.4,.035,.08),Vector3(side*4.8,2.09,-4.68),CREAM)
	# Counter has transparent upper glazing and visible pistols on a felt shelf.
	box(root,Vector3(5,.64,1.1),Vector3(0,.32,-2.2),RED)
	box(root,Vector3(5.12,.10,1.18),Vector3(0,.67,-2.2),INK)
	var glass := box(root,Vector3(4.92,.32,.025),Vector3(0,.86,-1.64),Color("a5d2ca"))
	glass.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.material_override.albedo_color.a = .18
	for x in [-2.5,0,2.5]: box(root,Vector3(.05,.4,1.12),Vector3(x,.87,-2.2),INK)
	var top := box(root,Vector3(5.16,.04,1.2),Vector3(0,1.08,-2.2),Color("a5d2ca"))
	top.material_override = glass.material_override
	for z in [-2.78,-1.62]: box(root,Vector3(5.16,.07,.05),Vector3(0,1.08,z),Color("a2987a"))
	text(root,"AMMU-NATION",Vector3(0,.39,-1.635),.007)
	for i in 3:
		var gun := Node3D.new()
		root.add_child(gun)
		item(gun,["pistol","magnum","sawed_off"][i])
		gun.position = Vector3(-1.6+i*1.6,.8,-2.02)
		gun.rotation = Vector3(0,PI*.5,PI*.5)
		gun.scale = Vector3.ONE*1.6
	var npc := gunsmith(root)
	npc.position = Vector3(0,0,-3.4)
	box(root,Vector3(.55,.10,.45),Vector3(1.85,1.18,-2.2),INK)
	box(root,Vector3(.45,.32,.08),Vector3(1.85,1.36,-2.35),Color("476b60"))
	# Ammunition shelves and service drawers frame the merchant's station.
	for side in [-1,1]:
		box(root,Vector3(1.25,1.45,.45),Vector3(side*2.25,.73,-4.5),Color("121c1c"))
		for row in 3:
			box(root,Vector3(1.3,.06,.52),Vector3(side*2.25,.18+row*.43,-4.46),OLIVE)
			for col in 3:
				box(root,Vector3(.31,.25,.28),Vector3(side*2.25-.39+col*.39,.34+row*.43,-4.42),Color("b2a073"))
				box(root,Vector3(.19,.07,.015),Vector3(side*2.25-.39+col*.39,.35+row*.43,-4.27),RED)
		text(root,"MUNIÇÃO",Vector3(side*2.25,1.64,-4.25),.003)
	for side in [-1,1]:
		box(root,Vector3(1.55,.85,2.9),Vector3(side*5.5,.425,.5),INK)
		box(root,Vector3(1.65,.08,3),Vector3(side*5.5,.90,.5),Color("9b9377"))
		text(root,"PROTEÇÃO" if side<0 else "EXPLOSIVOS",Vector3(side*5.5,.56,1.97),.0049)
		for i in 3:
			var stock := Node3D.new()
			root.add_child(stock)
			item(stock,"armor" if side<0 else "grenade")
			stock.position = Vector3(side*5.5,1.23 if side<0 else 1.1,-.3+i*.85)
			stock.scale = Vector3.ONE*(1.1 if side<0 else 3.0)
		for i in 3:
			box(root,Vector3(.8,.26,.55),Vector3(side*5.5,.13,2.5+i*.46),OLIVE)
			box(root,Vector3(.48,.08,.015),Vector3(side*5.5,.17,2.78+i*.46),CREAM)
	# Entrance is a cutaway: a threshold, posts and floor markings keep it readable.
	for side in [-1,1]:
		box(root,Vector3(5.8,.42,.22),Vector3(side*4.1,.21,4.9),INK)
		box(root,Vector3(.18,1.4,.26),Vector3(side*1.15,.7,4.82),RED)
	box(root,Vector3(2.15,.025,1.6),Vector3(0,.015,3.8),Color("243d33"))
	var exit_label := text(root,"SAÍDA  ↓",Vector3(0,.042,3.95),.010)
	exit_label.rotation.x = -PI*.5
	for side in [-1,1]: box(root,Vector3(.055,.02,5.4),Vector3(side*1.8,.02,1.35),Color("ad9654"))
