extends RefCounted
## Móveis montados em caixas e cilindros dos lotes do andar (mesa, cadeira, cama, cozinha,
## bancada, estante, aquário...), separados do HarborBuildingDressing em 01/11 (Onda 1).
## O estado do andar (_spec, _palette, _rng, _frame, _layout, lotes, sólidos, camas, decoração) continua
## no HarborBuildingDressing e é lido e escrito por `g.`; o dono mantém cada função antiga como
## delegação de uma linha com a mesma assinatura. Os sorteios de `g._rng` saem na mesma ordem de
## antes (test_harbor_interior_variety compara dois populate do mesmo andar).
## `g` fica como RefCounted, e não como o script do dono, para não criar preload cíclico. O dono
## solta os auxiliares no fim de populate: dono e auxiliar se referenciam e, sendo RefCounted, o
## ciclo não se desfaria sozinho.

var g: RefCounted

func _init(host: RefCounted) -> void:
	g = host

func _desk(at: Vector3, id: String, program: String, compact: bool) -> void:
	var width := 1.55 if compact else 2.0
	_table_base(at, id, Vector2(width, .82), .90 if compact else .82)
	var y := .96 if compact else .88
	var screen: bool = program in ["reception", "press", "drafting", "meeting"] or g._rng.randf() < .3
	if screen and g._rng.randf() < .35:
		# Notebook aberto em vez do monitor de mesa.
		g._box(at + Vector3(.3, y + .02, .08), Vector3(.40, .025, .28), "3a3f42", id, "metal")
		g._box(at + Vector3(.3, y + .15, -.06), Vector3(.40, .26, .02), "2c3134", id, "metal")
		g._box(at + Vector3(.3, y + .15, -.048), Vector3(.35, .21, .006), "5d7f8a", id, "glass")
	elif screen:
		g._box(at + Vector3(.3, y + .31, -.1), Vector3(.58, .40, .06), "28383c", id, "metal")
		g._box(at + Vector3(.3, y + .1, -.1), Vector3(.055, .25, .10), "737b79", id, "metal")
		g._box(at + Vector3(.3, y + .015, .22), Vector3(.53, .025, .17), "3d4949", id, "metal")
		g._box(at + Vector3(.3, y + .31, -.063), Vector3(.50, .32, .01), "618386", id, "glass")
	else:
		_surface_items(at + Vector3(.32, y + .05, -.05), id, 1)
	_papers(at + Vector3(-.33, y + .025, .18), id)
	_mug(at + Vector3(.62, y + .09, .14), id)
	if g._rng.randf() < .5: _desk_lamp(at + Vector3(-.58 if compact else -.74, y + .05, -.18), id)
	else: g._box(at + Vector3(-.49, y + .05, -.18), Vector3(.26, .1, .22), g._palette.accent, id)

func _table_base(at: Vector3, id: String, size: Vector2, height := .78) -> void:
	g._box(at + Vector3(0, height, 0), Vector3(size.x, .10, size.y), g._palette.wood, id)
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]: g._box(at + Vector3(side * (size.x * .5 - .11), height * .5, end * (size.y * .5 - .10)), Vector3(.085, height, .085), g._palette.metal, id, "metal")
	g._box(at + Vector3(0, height - .20, 0), Vector3(size.x - .16, .12, .065), "6d5945", id)

func _table(at: Vector3, id: String, papers: bool) -> void:
	_table_base(at, id, Vector2(1.85, .90))
	if papers: _papers(at + Vector3(-.30, .85, .1), id)
	else:
		for level in 3: g._box(at + Vector3(.24, .87 + level * .055, 0), Vector3(.60, .05, .43), g._palette.cloth, id, "cloth")
	_mug(at + Vector3(.54, .91, -.20), id)
	_surface_items(at + Vector3(-.66 if papers else -.42, .88, -.20), id, 1)
	# A cadeira muda de lado e de ângulo, sempre dentro da pegada original.
	var chair_x: float = [-.53, .48, -.30][g._layout % 3]
	_chair_turned(at + Vector3(chair_x, 0, .76), id + "Chair", [0.0, .12, -.10][(g._layout + int(g._spec.floor)) % 3])

func _chair(at: Vector3, id: String) -> void:
	g._box(at + Vector3(0, .47, 0), Vector3(.49, .11, .50), g._palette.cloth, id, "cloth")
	g._box(at + Vector3(0, .79, -.2), Vector3(.50, .56, .10), g._palette.cloth, id, "cloth")
	for x in [-.18, .18]:
		for z in [-.18, .18]: g._box(at + Vector3(x, .23, z), Vector3(.05, .46, .05), g._palette.metal, id, "metal")

## Cadeira girada em torno do próprio centro (compõe com o frame atual).
func _chair_turned(at: Vector3, id: String, yaw: float) -> void:
	var saved: Transform3D = g._frame
	g._frame = saved * Transform3D(Basis(Vector3.UP, yaw), at) * Transform3D(Basis.IDENTITY, -at)
	_chair(at, id)
	g._frame = saved

func _bookcase(at: Vector3, id: String, folders: bool) -> void:
	g._box(at + Vector3(0, 1.04, -.24), Vector3(1.80, 2.08, .06), g._palette.wood, id)
	for side in [-1.0, 1.0]: g._box(at + Vector3(side * .88, 1.04, 0), Vector3(.08, 2.08, .55), g._palette.wood, id)
	for level in 4:
		var y := .13 + level * .50
		g._box(at + Vector3(0, y, 0), Vector3(1.80, .065, .55), g._palette.wood, id)
		for column in 6:
			var col: String = ["6b7769", "8e6c52", "465e6b", "b5a37c", "76686a", "a28b6c"][(column + level + g._spec.floor) % 6]
			var bx := -.72 + column * .28
			g._box(at + Vector3(bx, y + .21, 0), Vector3(.20 if folders else .15, .34 + (column % 2) * .04, .34), col, id, "paper")
			g._box(at + Vector3(bx, y + .25, .176), Vector3(.10, .06, .01), "d4c9ac", id, "paper")

func _sofa(at: Vector3, id: String) -> void:
	g._box(at + Vector3(0, .25, 0), Vector3(2.1, .38, .88), g._palette.wood, id)
	g._box(at + Vector3(0, .80, .35), Vector3(2.05, .75, .18), g._palette.cloth, id, "cloth")
	for side in [-1.0, 1.0]:
		g._box(at + Vector3(side * .51, .50, 0), Vector3(.93, .23, .70), g._palette.cloth, id, "cloth")
		g._box(at + Vector3(side * 1.02, .59, 0), Vector3(.20, .52, .94), g._palette.cloth, id, "cloth")
	g._box(at + Vector3(.70, .72, .18), Vector3(.34, .36, .18), g._palette.accent, id, "cloth")
	g._box(at + Vector3(-.70, .64, 0), Vector3(.32, .06, .50), "c1b39a", id, "cloth")
	# A folded blanket has a hem and two short hanging folds, within the sofa.
	for z in [-.16, .04, .23]: g._box(at + Vector3(-.7, .681, z), Vector3(.33, .015, .025), "84775e", id, "cloth")

func _bed(at: Vector3, id: String, single := false) -> void:
	# Âncora da cama (centro, cabeceira em -Z) para quem dorme nela.
	# A origem fica na altura do lençol (0,62 m).
	g._beds.append(g._frame * Transform3D(Basis.IDENTITY, at + Vector3(-.26 if single else 0.0, .62, 0)))
	if single:
		# Cama de solteiro com criado-mudo, dentro da pegada da cama de casal.
		var bed := at + Vector3(-.26, 0, 0)
		g._box(bed + Vector3(0, .24, 0), Vector3(1.02, .40, 2.10), g._palette.wood, id)
		g._box(bed + Vector3(0, .51, 0), Vector3(.97, .19, 2.03), g._palette.linen, id, "cloth")
		g._box(bed + Vector3(0, .64, .30), Vector3(.98, .08, 1.38), g._palette.cloth, id, "cloth")
		g._box(bed + Vector3(0, .56, -1.02), Vector3(1.06, 1.0, .10), g._palette.wood, id)
		g._box(bed + Vector3(0, .68, -.70), Vector3(.62, .14, .36), "e0d6bf", id, "cloth")
		var stand := at + Vector3(.56, 0, -.78)
		g._box(stand + Vector3(0, .29, 0), Vector3(.42, .58, .40), g._palette.wood, id)
		g._box(stand + Vector3(0, .36, .205), Vector3(.30, .12, .012), g._palette.metal, id, "metal")
		_desk_lamp(stand + Vector3(-.05, .58, -.05), id)
		return
	g._box(at + Vector3(0, .24, 0), Vector3(1.55, .40, 2.13), g._palette.wood, id)
	g._box(at + Vector3(0, .51, 0), Vector3(1.50, .19, 2.06), g._palette.linen, id, "cloth")
	g._box(at + Vector3(0, .64, .28), Vector3(1.51, .08, 1.44), g._palette.cloth, id, "cloth")
	g._box(at + Vector3(0, .56, -1.03), Vector3(1.61, 1.05, .12), g._palette.wood, id)
	for side in [-1.0, 1.0]: g._box(at + Vector3(side * .35, .68, -.70), Vector3(.59, .14, .39), "e0d6bf", id, "cloth")
	for z in [.12, .23]: g._box(at + Vector3(0, .687, z), Vector3(1.52, .014, .045), "b9aa8d", id, "cloth")

func _kitchen(at: Vector3, id: String, compact: bool) -> void:
	var width := 1.65 if compact else 2.45
	g._box(at + Vector3(0, .45, 0), Vector3(width, .90, .70), g._palette.cabinet, id)
	g._box(at + Vector3(0, .945, 0), Vector3(width + .06, .09, .76), "c8c0ab", id, "stone")
	for side in [-1.0, 1.0]:
		g._box(at + Vector3(side * width * .25, .50, .362), Vector3(width * .44, .65, .035), g._palette.cabinet if side < 0 else g._palette.wood, id)
		g._box(at + Vector3(side * width * .25, .72, .394), Vector3(.18, .025, .045), "a9aca0", id, "metal")
	g._box(at + Vector3(-width * .22, 1.0, -.03), Vector3(.53, .035, .45), "516b6d", id, "metal")
	g._box(at + Vector3(-width * .22, 1.16, -.26), Vector3(.035, .34, .035), "b3b8b1", id, "metal")
	g._box(at + Vector3(-width * .22, 1.32, -.19), Vector3(.035, .035, .19), "b3b8b1", id, "metal")
	g._box(at + Vector3(width * .23, 1.0, .02), Vector3(.57, .03, .51), "303c3a", id, "metal")
	g._cylinder(at + Vector3(.16, 1.115, .27), .16, .22, "6a7068", id)
	g._cylinder(at + Vector3(.16, 1.233, .27), .135, .015, "9d8654", id, "ceramic")
	_mug(at + Vector3(-width * .42, 1.08, .15), id)
	if not compact: _surface_items(at + Vector3(width * .40, 1.0, -.18), id, 1)
	g._box(at + Vector3(0, 1.36, -.36), Vector3(width, .64, .03), "c2c1aa" if g._layout % 2 == 0 else g._palette.linen, id, "ceramic")
	for row in 2:
		for column in 6: g._box(at + Vector3(-width * .42 + column * width * .168, 1.2 + row * .24, -.335), Vector3(.006, .23, .006), "999d8d", id, "ceramic")

func _workbench(at: Vector3, id: String, compact: bool) -> void:
	_table_base(at, id, Vector2(1.65 if compact else 2.30, .82), .94)
	g._box(at + Vector3(-.45, 1.10, .18), Vector3(.30, .24, .28), "526764", id, "metal")
	g._box(at + Vector3(-.45, 1.245, .18), Vector3(.43, .06, .14), "8e9690", id, "metal")
	g._box(at + Vector3(.29, 1.027, .15), Vector3(.64, .035, .43), "5b665b", id, "cloth")
	for part in 4: g._cylinder(at + Vector3(.05 + part * .15, 1.07, .14), .035, .07, "a6a392", id)
	g._box(at + Vector3(0, 1.60, -.36), Vector3(1.48, .88, .075), "867255", id)
	for tool in 5:
		var x := -.55 + tool * .27
		g._box(at + Vector3(x, 1.57, -.305), Vector3(.055, .35, .045), "90978f", id, "metal")
		g._box(at + Vector3(x, 1.39, -.29), Vector3(.075, .14, .07), "665345", id)

func _packing(at: Vector3, id: String, compact: bool) -> void:
	_table_base(at, id, Vector2(1.65 if compact else 2.3, .82), .93)
	for column in 3:
		g._box(at + Vector3(-.48 + column * .46, 1.12, -.12), Vector3(.38, .28 + column * .06, .40), "a88c61", id, "paper")
		g._box(at + Vector3(-.48 + column * .46, 1.27 + column * .03, -.12), Vector3(.10, .01, .42), "c5b283", id, "paper")
	_papers(at + Vector3(0, .999, .24), id)

func _studio(at: Vector3, id: String, compact: bool) -> void:
	_table_base(at, id, Vector2(1.65 if compact else 2.25, .85), .91)
	g._box(at + Vector3(.18, .979, .04), Vector3(.90, .02, .54), "d9c8a5", id, "paper")
	for stroke in 4: g._box(at + Vector3(-.14 + stroke * .14, .992, .05), Vector3(.045, .008, .32 - stroke * .035), ["798372", "9e7352", "576f79", "ac9c78"][stroke], id, "paper")
	g._cylinder(at + Vector3(-.54, 1.095, -.13), .085, .24, "938466", id, "ceramic")
	for brush in 4: g._box(at + Vector3(-.59 + brush * .035, 1.26, -.13), Vector3(.017, .28, .017), "7d6441", id)
	g._box(at + Vector3(.64, 1.02, -.2), Vector3(.20, .12, .22), g._palette.cloth, id, "cloth")

func _shop_counter(at: Vector3, id: String, compact: bool) -> void:
	g._box(at + Vector3(0, .50, 0), Vector3(1.65 if compact else 2.4, 1.0, .78), g._palette.wood, id)
	g._box(at + Vector3(0, 1.055, 0), Vector3(1.7 if compact else 2.46, .10, .84), "c0b8a4", id, "stone")
	g._box(at + Vector3(.4, 1.24, -.15), Vector3(.45, .30, .31), "445654", id, "metal")
	g._box(at + Vector3(.4, 1.26, .017), Vector3(.28, .17, .015), "688b85", id, "glass")
	_papers(at + Vector3(-.35, 1.12, .20), id)

func _laundry(at: Vector3, id: String, compact: bool) -> void:
	for column in (1 if compact else 2):
		var point := at + Vector3(column * .9 - (0.0 if compact else .45), 0, 0)
		var machine_id := id + str(column)
		g._box(point + Vector3(0, .48, 0), Vector3(.80, .96, .72), "b5beb3", machine_id, "metal")
		g._box(point + Vector3(0, .49, .368), Vector3(.56, .57, .04), "657e7c", machine_id, "metal")
		g._box(point + Vector3(0, .49, .396), Vector3(.40, .40, .025), "364f54", machine_id, "glass")
		for knob in [-.2, .2]: g._box(point + Vector3(knob, .84, .388), Vector3(.08, .08, .04), "566664", machine_id, "metal")
		for fold in 3: g._box(point + Vector3(0, 1.015 + fold * .055, 0), Vector3(.52, .05, .36), g._palette.cloth, machine_id, "cloth")

func _rack(at: Vector3, id: String) -> void:
	for side in [-1.0, 1.0]: g._box(at + Vector3(side * .84, 1.12, 0), Vector3(.06, 2.24, .60), "59695f", id, "metal")
	for level in 3:
		var y := .18 + level * .66
		g._box(at + Vector3(0, y, 0), Vector3(1.78, .06, .62), "778271", id, "metal")
		for side in [-1.0, 1.0]:
			g._box(at + Vector3(side * .43, y + .24, 0), Vector3(.68, .39, .48), "9e8962", id, "paper")
			g._box(at + Vector3(side * .43, y + .29, .247), Vector3(.24, .10, .012), "d0c6a5", id, "paper")

func _pallet(at: Vector3, id: String) -> void:
	for strip in 5: g._box(at + Vector3(-.64 + strip * .32, .12, 0), Vector3(.26, .10, 1.00), "91774f", id)
	for side in [-1.0, 1.0]: g._box(at + Vector3(0, .06, side * .36), Vector3(1.55, .10, .12), "6e5a41", id)
	for side in [-1.0, 1.0]:
		g._box(at + Vector3(side * .36, .44, 0), Vector3(.64, .56, .82), "ac946c", id, "paper")
		g._box(at + Vector3(side * .36, .731, 0), Vector3(.12, .014, .83), "c9b587", id, "paper")
	g._box(at + Vector3(.2, .92, 0), Vector3(.57, .38, .58), "8c9c8e", id, "metal")

func _easel(at: Vector3, id: String) -> void:
	for side in [-1.0, 1.0]: g._box(at + Vector3(side * .40, .9, 0), Vector3(.065, 1.80, .065), "8d7049", id)
	g._box(at + Vector3(0, .47, -.3), Vector3(.10, .94, .1), "80603e", id)
	g._box(at + Vector3(0, .95, .10), Vector3(1.0, .055, .17), "927345", id)
	g._box(at + Vector3(0, 1.44, .03), Vector3(.91, .93, .07), "c7bfa0", id, "paper")
	for stripe in 6: g._box(at + Vector3(-.35 + stripe * .14, 1.42 + sin(stripe * 2.0) * .10, .074), Vector3(.12, .50 + stripe * .035, .012), ["526c76", "8a987f", "b6a47e"][stripe % 3], id, "paper")

func _display(at: Vector3, id: String) -> void:
	_table_base(at, id, Vector2(1.8, .74), .80)
	for column in 4:
		for level in 2: g._box(at + Vector3(-.64 + column * .42, .92 + level * .13, 0), Vector3(.34, .12, .45), ["91775f", "687a70", "687c89", "a19378"][column], id, "cloth")

func _aquarium(at: Vector3, id: String, compact: bool) -> void:
	var width := 1.60 if compact else 2.16
	g._box(at + Vector3(0, .41, 0), Vector3(width, .82, .68), "536a64", id, "wood")
	g._box(at + Vector3(0, .86, 0), Vector3(width + .04, .08, .73), "394e4b", id, "metal")
	g._box(at + Vector3(0, .94, 0), Vector3(width - .12, .12, .59), "b3ad85", id, "stone")
	g._box(at + Vector3(0, 1.42, -.315), Vector3(width - .06, .95, .035), "557d87", id, "glass")
	g._box(at + Vector3(0, 1.93, 0), Vector3(width + .03, .10, .73), "445c58", id, "metal")
	for side in [-1.0, 1.0]:
		g._box(at + Vector3(side * (width * .5 - .03), 1.43, 0), Vector3(.065, 1.04, .70), "78999b", id, "tank_glass")
		g._box(at + Vector3(side * (width * .5 - .04), 1.43, .33), Vector3(.05, 1.04, .04), "546d67", id, "metal")
	g._box(at + Vector3(0, 1.43, .33), Vector3(width - .10, .96, .022), "82b1b0", id, "tank_glass")
	for plant in 6:
		var px := -width * .39 + plant * width * .15
		g._box(at + Vector3(px, 1.12 + (plant % 3) * .05, -.11), Vector3(.085, .36 + (plant % 3) * .10, .12), ["5a816a", "728b66", "436d61"][plant % 3], id, "cloth")
	for fish in 6:
		var fx := -width * .34 + fish * width * .125
		var fy := 1.38 + sin(fish * 1.2) * .20
		var color: String = ["c1a16b", "8cb0ab", "b08c6a"][fish % 3]
		g._box(at + Vector3(fx, fy, .13), Vector3(.15, .075, .06), color, id, "ceramic")
		g._box(at + Vector3(fx - .09, fy, .13), Vector3(.04, .11, .035), color, id, "ceramic")

func _ship_exhibit(at: Vector3, id: String) -> void:
	g._box(at + Vector3(0, .40, 0), Vector3(1.80, .80, .77), "86755b", id, "wood")
	g._box(at + Vector3(0, .85, 0), Vector3(1.84, .10, .82), "c0b69b", id, "stone")
	g._box(at + Vector3(0, 1.01, 0), Vector3(1.38, .18, .37), "655b47", id, "wood")
	g._box(at + Vector3(.68, 1.055, 0), Vector3(.20, .12, .24), "655b47", id, "wood")
	g._box(at + Vector3(-.67, 1.10, 0), Vector3(.20, .18, .33), "816a4a", id, "wood")
	g._box(at + Vector3(0, 1.12, 0), Vector3(1.36, .06, .36), "ac956a", id, "wood")
	for mast in [-.30, .30]:
		g._box(at + Vector3(mast, 1.49, 0), Vector3(.028, .82, .028), "6d634c", id, "wood")
		g._box(at + Vector3(mast + .12, 1.58, .028), Vector3(.28, .46, .018), "d0c6a6", id, "cloth")
		g._box(at + Vector3(mast, 1.83, 0), Vector3(.42, .023, .025), "6d634c", id, "wood")
	for rail in [-.17, .17]: g._box(at + Vector3(0, 1.22, rail), Vector3(1.3, .03, .024), "968563", id, "wood")

func _papers(at: Vector3, id: String) -> void:
	g._box(at, Vector3(.36, .035, .28), "d9d1b8", id, "paper")
	for line in 4: g._box(at + Vector3(0, .020, -.09 + line * .046), Vector3(.25, .003, .007), "858577", id, "paper")
	g._box(at + Vector3(.21, .009, .06), Vector3(.016, .016, .23), "354f55", id, "metal")

func _mug(at: Vector3, id: String) -> void:
	g._cylinder(at, .072, .15, "b8bca7", id, "ceramic")
	g._cylinder(at + Vector3(0, .077, 0), .056, .007, "504939", id, "ceramic")
	g._box(at + Vector3(.086, .015, 0), Vector3(.041, .067, .045), "b8bca7", id, "ceramic")

func _surface_items(at: Vector3, id: String, count: int, spread := .30) -> void:
	# Objetos de tampo (só visuais, já dentro do envelope do móvel que os apoia).
	for index in count:
		var point := at + Vector3((float(index) - (count - 1) * .5) * spread, 0, 0)
		match g._rng.randi() % 7:
			0: _desk_lamp(point, id)
			1:
				for book in 2 + g._rng.randi() % 3:
					g._box(point + Vector3(0, .025 + book * .045, 0), Vector3(.24 - book * .02, .04, .17), [g._palette.accent, g._palette.cloth, "b5a37c", "6b7769"][book % 4], id, "paper")
			2:
				g._cylinder(point + Vector3(0, .07, 0), .08, .14, "8a7655", id, "ceramic")
				for leaf in 4: g._box(point + Vector3(sin(leaf * 1.7) * .06, .20 + leaf * .03, cos(leaf * 1.7) * .06), Vector3(.10, .12, .08), "5a7655", id, "cloth")
			3:
				g._cylinder(point + Vector3(0, .12, 0), .045, .24, ["5f7a5c", "7a5240", "6b7f8c"][g._layout % 3], id, "glass")
				g._cylinder(point + Vector3(0, .27, 0), .018, .06, "3d3a33", id, "metal")
			4:
				g._cylinder(point + Vector3(0, .04, 0), .15, .07, g._palette.linen, id, "ceramic")
				for fruit in 3: g._cylinder(point + Vector3(-.06 + fruit * .06, .10, .02 * fruit), .045, .07, ["c0904a", "a5502f", "8fa04a"][fruit], id, "ceramic")
			5:
				g._box(point + Vector3(0, .09, 0), Vector3(.30, .18, .14), "4c4a45", id, "metal")
				g._cylinder(point + Vector3(-.07, .09, .072), .045, .01, "8e9690", id, "metal")
			_:
				g._box(point + Vector3(0, .09, 0), Vector3(.17, .17, .025), g._palette.wood, id)
				g._box(point + Vector3(0, .09, .014), Vector3(.13, .13, .006), g._palette.cloth, id, "paper")

func _desk_lamp(at: Vector3, id: String) -> void:
	g._cylinder(at + Vector3(0, .015, 0), .08, .03, g._palette.metal, id, "metal")
	g._box(at + Vector3(0, .20, -.02), Vector3(.025, .36, .025), g._palette.metal, id, "metal")
	g._cylinder(at + Vector3(0, .40, .03), .09, .12, g._palette.accent, id, "cloth")

func _bunk_bed(at: Vector3, id: String) -> void:
	# Beliche: dorme-se na cama de baixo (âncora com a altura do colchão).
	g._beds.append(g._frame * Transform3D(Basis.IDENTITY, at + Vector3(-.18, .55, 0)))
	var bed := at + Vector3(-.18, 0, 0)
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]: g._box(bed + Vector3(side * .52, .92, end * 1.0), Vector3(.07, 1.84, .07), g._palette.wood, id)
	for level in [.36, 1.36]:
		g._box(bed + Vector3(0, level, 0), Vector3(1.0, .12, 2.0), g._palette.wood, id)
		g._box(bed + Vector3(0, level + .12, 0), Vector3(.94, .14, 1.94), g._palette.linen, id, "cloth")
		g._box(bed + Vector3(0, level + .21, .25), Vector3(.95, .05, 1.30), [g._palette.cloth, g._palette.accent][int(level > 1.0)], id, "cloth")
		g._box(bed + Vector3(0, level + .25, -.72), Vector3(.55, .12, .32), "e0d6bf", id, "cloth")
	g._box(bed + Vector3(.30, 1.58, 0), Vector3(.05, .22, 2.0), g._palette.wood, id)
	for rung in 4: g._box(bed + Vector3(.60, .30 + rung * .36, .62), Vector3(.05, .04, .36), g._palette.wood, id)
	g._box(at + Vector3(.62, .9, .44), Vector3(.05, 1.8, .05), g._palette.wood, id)
	g._box(at + Vector3(.62, .9, .80), Vector3(.05, 1.8, .05), g._palette.wood, id)
	# Caixa de brinquedos ao pé do beliche.
	g._box(at + Vector3(.45, .20, -.70), Vector3(.40, .40, .50), g._palette.accent, id)
	for toy in 3: g._box(at + Vector3(.36 + toy * .09, .45, -.70 + toy * .1), Vector3(.08, .10, .08), ["c0904a", "5b7fa0", "a5502f"][toy], id, "ceramic")

func _tv_wall(at: Vector3, id: String) -> void:
	g._box(at + Vector3(0, .25, -.02), Vector3(1.80, .50, .45), g._palette.cabinet, id)
	for door in 3: g._box(at + Vector3(-.58 + door * .58, .25, .21), Vector3(.52, .40, .012), g._palette.wood, id)
	g._box(at + Vector3(0, .53, -.08), Vector3(.30, .06, .20), "2d3133", id, "metal")
	g._box(at + Vector3(0, .93, -.10), Vector3(1.20, .70, .06), "202426", id, "metal")
	g._box(at + Vector3(0, .93, -.068), Vector3(1.12, .63, .006), "3b4d55", id, "glass")
	for side in [-1.0, 1.0]:
		g._box(at + Vector3(side * .78, .95, -.08), Vector3(.24, 1.40, .30), g._palette.wood, id)
		for item in 3: g._box(at + Vector3(side * .78, .70 + item * .32, -.06), Vector3(.16, .18, .18), [g._palette.accent, "b8bca7", g._palette.cloth][item], id, "ceramic")

func _tv_lounge(at: Vector3, id: String) -> void:
	# Rack baixo com TV voltada para a sala e um pufe à frente.
	g._box(at + Vector3(0, .25, .28), Vector3(1.60, .50, .42), g._palette.cabinet, id)
	g._box(at + Vector3(0, .54, .30), Vector3(.30, .06, .18), "2d3133", id, "metal")
	g._box(at + Vector3(0, .92, .32), Vector3(1.15, .68, .06), "202426", id, "metal")
	g._box(at + Vector3(0, .92, .288), Vector3(1.07, .61, .006), "3b4d55", id, "glass")
	g._cylinder(at + Vector3(-.40, .20, -.25), .22, .40, g._palette.cloth, id, "cloth")
	g._box(at + Vector3(.55, .56, .30), Vector3(.22, .08, .14), g._palette.accent, id, "ceramic")

func _armchairs(at: Vector3, id: String) -> void:
	for side in [-1.0, 1.0]:
		var seat := at + Vector3(side * .73, 0, 0)
		g._box(seat + Vector3(0, .22, 0), Vector3(.78, .36, .76), g._palette.wood, id)
		g._box(seat + Vector3(0, .44, -.03), Vector3(.62, .14, .62), g._palette.cloth, id, "cloth")
		# Encosto alto (poltrona de orelhas) voltado para a parede da frente.
		g._box(seat + Vector3(0, .78, .30), Vector3(.76, .82, .16), g._palette.cloth, id, "cloth")
		for arm in [-1.0, 1.0]: g._box(seat + Vector3(arm * .35, .56, 0), Vector3(.10, .32, .72), g._palette.cloth, id, "cloth")
	g._cylinder(at + Vector3(0, .28, -.05), .21, .56, g._palette.wood, id, "wood")
	_surface_items(at + Vector3(0, .56, -.05), id, 1)

func _dining(at: Vector3, id: String) -> void:
	_table_base(at + Vector3(0, 0, -.05), id, Vector2(1.40, .82), .76)
	g._box(at + Vector3(0, .82, -.05), Vector3(.90, .01, .30), g._palette.linen, id, "cloth")
	for plate in [-.35, .35]: g._cylinder(at + Vector3(plate, .825, .12), .11, .012, "e3ddcc", id, "ceramic")
	_surface_items(at + Vector3(0, .82, -.20), id, 1)
	for side in [-1.0, 1.0]: _chair_turned(at + Vector3(side * .36, 0, .58), id + "Chair", PI)

func _piano(at: Vector3, id: String) -> void:
	g._box(at + Vector3(0, .63, -.12), Vector3(1.50, 1.26, .55), "2b2523", id)
	g._box(at + Vector3(0, .74, .22), Vector3(1.42, .08, .26), "2b2523", id)
	g._box(at + Vector3(0, .79, .22), Vector3(1.30, .02, .22), "e4ddcc", id, "ceramic")
	for key in 12: g._box(at + Vector3(-.60 + key * .11, .81, .18), Vector3(.035, .02, .12), "1c1a19", id, "ceramic")
	for leg in [-.65, .65]: g._box(at + Vector3(leg, .35, .26), Vector3(.06, .70, .06), "2b2523", id)
	g._box(at + Vector3(0, .46, .66), Vector3(.82, .08, .34), "2b2523", id)
	for leg in [-.35, .35]: g._box(at + Vector3(leg, .22, .66), Vector3(.06, .44, .28), "2b2523", id)
	g._box(at + Vector3(.35, 1.30, -.18), Vector3(.30, .06, .22), "d4c9ac", id, "paper")

func _canvas_stack(at: Vector3, id: String) -> void:
	for canvas in 4:
		var x := -.62 + canvas * .40
		g._box(at + Vector3(x, .55 + (canvas % 2) * .08, -.12 + canvas * .03), Vector3(.36 + (canvas % 2) * .1, 1.0 + (canvas % 2) * .16, .04), "c7bfa0", id, "paper")
		g._box(at + Vector3(x, .60, -.095 + canvas * .03), Vector3(.30, .55, .006), [g._palette.accent, "526c76", g._palette.cloth, "8a987f"][canvas], id, "paper")
	g._box(at + Vector3(.55, .34, .15), Vector3(.50, .68, .40), g._palette.wood, id)
	for jar in 3: g._cylinder(at + Vector3(.40 + jar * .14, .74, .15), .045, .12, ["798372", "9e7352", "576f79"][jar], id, "ceramic")

func _filing(at: Vector3, id: String) -> void:
	for cabinet in 3:
		var point := at + Vector3(-.61 + cabinet * .61, 0, -.05)
		g._box(point + Vector3(0, .66, 0), Vector3(.58, 1.32, .60), g._palette.metal if cabinet != 1 else g._palette.cabinet, id, "metal")
		for drawer in 4:
			g._box(point + Vector3(0, .20 + drawer * .31, .305), Vector3(.50, .27, .012), "8e9181", id, "metal")
			g._box(point + Vector3(0, .28 + drawer * .31, .318), Vector3(.16, .03, .02), "c9c7bc", id, "metal")
	_papers(at + Vector3(-.40, 1.34, -.05), id)
	_surface_items(at + Vector3(.45, 1.32, -.05), id, 1)

func _tool_cabinet(at: Vector3, id: String) -> void:
	g._box(at + Vector3(-.30, .50, 0), Vector3(1.10, 1.0, .55), "8c3b32", id, "metal")
	for drawer in 5: g._box(at + Vector3(-.30, .12 + drawer * .18, .28), Vector3(1.02, .14, .012), "a9483d", id, "metal")
	g._box(at + Vector3(-.30, 1.08, 0), Vector3(.40, .16, .22), "4c4a45", id, "metal")
	g._box(at + Vector3(.58, .95, 0), Vector3(.58, 1.90, .52), g._palette.metal, id, "metal")
	g._box(at + Vector3(.58, .95, .265), Vector3(.012, 1.70, .02), "2d3133", id, "metal")

func _barrels(at: Vector3, id: String) -> void:
	for barrel in 3:
		var color: String = ["3f5d7a", "8c4a32", g._palette.metal][(barrel + g._layout) % 3]
		g._cylinder(at + Vector3(-.60 + barrel * .60, .46, 0), .28, .92, color, id, "metal")
		for ring in [.18, .74]: g._cylinder(at + Vector3(-.60 + barrel * .60, ring, 0), .285, .03, "2d3133", id, "metal")

func _crate_stack(at: Vector3, id: String) -> void:
	for crate in 2:
		var point := at + Vector3(-.42 + crate * .84, 0, 0)
		g._box(point + Vector3(0, .30, 0), Vector3(.76, .60, .74), "8b7653", id)
		for slat in 3: g._box(point + Vector3(0, .12 + slat * .19, .375), Vector3(.76, .07, .012), "a68a5f", id)
	g._box(at + Vector3(-.20, .85, 0), Vector3(.70, .50, .64), "a68a5f", id)
	g._box(at + Vector3(-.20, 1.105, 0), Vector3(.10, .012, .66), "c5b283", id, "paper")

func _engine_stand(at: Vector3, id: String) -> void:
	for leg in [-.35, .35]: g._box(at + Vector3(leg - .20, .25, 0), Vector3(.06, .50, .55), g._palette.metal, id, "metal")
	g._box(at + Vector3(-.20, .74, 0), Vector3(.72, .46, .52), "4f5755", id, "metal")
	for cylinder in 4: g._cylinder(at + Vector3(-.47 + cylinder * .18, 1.0, 0), .06, .08, "8e9690", id, "metal")
	for tire in 3: g._cylinder(at + Vector3(.72, .11 + tire * .21, 0), .32, .20, "2a2c2b", id, "rubber")

func _clothes_rack(at: Vector3, id: String) -> void:
	for side in [-1.0, 1.0]:
		g._box(at + Vector3(side * .84, .80, 0), Vector3(.05, 1.60, .05), g._palette.metal, id, "metal")
		g._box(at + Vector3(side * .84, .03, 0), Vector3(.10, .05, .50), g._palette.metal, id, "metal")
	g._box(at + Vector3(0, 1.58, 0), Vector3(1.72, .03, .03), g._palette.metal, id, "metal")
	for garment in 9:
		var color: String = [g._palette.cloth, g._palette.accent, "3f4a5a", "a3734e", "d8d2c0", "6b5878"][(garment + g._layout) % 6]
		g._box(at + Vector3(-.72 + garment * .18, 1.17, 0), Vector3(.06, .74 + (garment % 3) * .10, .44), color, id, "cloth")

func _laundry_carts(at: Vector3, id: String) -> void:
	for side in [-1.0, 1.0]:
		var cart := at + Vector3(side * .50, 0, 0)
		g._box(cart + Vector3(0, .45, 0), Vector3(.72, .56, .50), g._palette.metal, id, "metal")
		for wheel in [-.28, .28]: g._cylinder(cart + Vector3(wheel, .06, .18), .05, .06, "2a2c2b", id, "rubber")
		for fold in 3: g._box(cart + Vector3(0, .76 + fold * .06, 0), Vector3(.56, .05, .38), [g._palette.linen, g._palette.cloth, "d8d2c0"][fold], id, "cloth")

func _whiteboard_table(at: Vector3, id: String) -> void:
	_table(at, id, true)
	g._box(at + Vector3(0, 1.28, -.62), Vector3(1.60, .90, .04), "e8e9e2", id + "Board", "ceramic")
	g._box(at + Vector3(0, 1.28, -.645), Vector3(1.68, .98, .03), g._palette.metal, id + "Board", "metal")
	for leg in [-.80, .80]: g._box(at + Vector3(leg, .62, -.64), Vector3(.05, 1.24, .30), g._palette.metal, id + "Board", "metal")
	for mark in 3: g._box(at + Vector3(-.45 + mark * .35, 1.40 - mark * .1, -.598), Vector3(.30, .015, .004), ["3f5d7a", "8c3b32", "2d3133"][mark], id + "Board", "paper")

func _coat_corner(at: Vector3, id: String) -> void:
	g._life_object("coat_rack", at + Vector3(-.62, 0, 0), id)
	g._life_object("tall_plant", at + Vector3(.62, 0, 0), id)
	g._box(at + Vector3(0, .24, .05), Vector3(.62, .48, .38), g._palette.wood, id)
	g._box(at + Vector3(0, .50, .05), Vector3(.56, .05, .34), g._palette.cloth, id, "cloth")
