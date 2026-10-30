extends RefCounted
## Espada de uma mão e escudo redondo do cavaleiro da cabana escondida da serra. Modelo provisório,
## por primitivas, até chegar o do Meshy. Usa só o material da katana (`KatanaModel._material`): mesma
## variante de shader, já aquecida, então a primeira vez que a arma aparece não compila nada.
## Espada: cabo na origem, lâmina em −Z, fio em ±X (como a katana). Escudo: centro na origem, face
## para −Z, alça no +Z (é o lado do antebraço).
const KATANA := preload("res://gameplay/KatanaModel.gd")
const TIP := Vector3(0.0, 0.0, -0.92)
const SHIELD_RADIUS := 0.34

static func build_sword(root: Node3D) -> Vector3:
	var steel := KATANA._material(Color("c4ced6"), 0.92, 0.22)
	var dark := KATANA._material(Color("2a2420"), 0.05, 0.82)
	var silver := KATANA._material(Color("9fb3c4"), 0.88, 0.30)
	KATANA._oval(root, "Grip", 0.017, 0.16, 0.85, Vector3(0, 0, 0.05), dark)
	KATANA._oval(root, "Pommel", 0.026, 0.035, 1.0, Vector3(0, 0, 0.145), silver)
	KATANA._box(root, "Guard", Vector3(0.20, 0.03, 0.035), Vector3(0, 0, -0.04), silver)
	KATANA._box(root, "Blade", Vector3(0.052, 0.009, 0.78), Vector3(0, 0, -0.44), steel)
	KATANA._box(root, "Fuller", Vector3(0.012, 0.012, 0.6), Vector3(0, 0, -0.38), silver)
	var point := KATANA._box(root, "Point", Vector3(0.037, 0.009, 0.037), Vector3(0, 0, -0.84), steel)
	point.rotation.y = PI * .25
	return TIP

static func build_shield(root: Node3D) -> void:
	var wood := KATANA._material(Color("5a3b22"), 0.0, 0.78)
	var iron := KATANA._material(Color("8c96a0"), 0.85, 0.35)
	var frost := KATANA._material(Color("bfe4f2"), 0.65, 0.25)
	var face := CylinderMesh.new()
	face.top_radius = SHIELD_RADIUS
	face.bottom_radius = SHIELD_RADIUS
	face.height = 0.035
	face.radial_segments = 24
	face.rings = 1
	var board := MeshInstance3D.new()
	board.name = "Board"
	board.mesh = face
	board.material_override = wood
	board.rotation.x = PI * .5
	root.add_child(board)
	var rim := TorusMesh.new()
	rim.inner_radius = SHIELD_RADIUS - 0.02
	rim.outer_radius = SHIELD_RADIUS + 0.012
	rim.rings = 24
	rim.ring_segments = 6
	var rim_mesh := MeshInstance3D.new()
	rim_mesh.name = "Rim"
	rim_mesh.mesh = rim
	rim_mesh.material_override = iron
	rim_mesh.rotation.x = PI * .5
	root.add_child(rim_mesh)
	KATANA._oval(root, "Boss", 0.075, 0.05, 1.0, Vector3(0, 0, -0.035), frost)
	# Cruz de ferro na face: o desenho que separa o escudo "do gelo" de uma tampa de barril.
	KATANA._box(root, "BandV", Vector3(0.05, SHIELD_RADIUS * 1.9, 0.012), Vector3(0, 0, -0.022), iron)
	KATANA._box(root, "BandH", Vector3(SHIELD_RADIUS * 1.9, 0.05, 0.012), Vector3(0, 0, -0.022), iron)
	KATANA._box(root, "Strap", Vector3(0.05, 0.16, 0.03), Vector3(0, 0, 0.035), wood)
