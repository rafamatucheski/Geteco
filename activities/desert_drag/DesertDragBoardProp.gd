extends RefCounted
const G := preload("res://world/desert/DesertGeometry.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")

static func position() -> Vector3:
	# Outside the driving/staging lane and parked-car bays; reached from the south.
	return LAYOUT.drag_staging_point()+Vector3(8,0,5)

static func build_chunk(parent: Node3D, rect: Rect2) -> void:
	var at := position()
	if not rect.has_point(Vector2(at.x,at.z)): return
	var board := Node3D.new()
	board.name="DragRivalsBoard"
	board.position=at
	parent.add_child(board)
	board.add_to_group("desert_drag_boards")
	G.box(board,"WoodenFrame",Vector3(0,1.65,0),Vector3(2.3,1.7,.16),Color("624936"),true)
	G.box(board,"ChalkFace",Vector3(0,1.65,.087),Vector3(2.14,1.54,.02),Color("243a33"))
	for x in [-.85,.85]: G.box(board,"Leg",Vector3(x,.45,0),Vector3(.10,.9,.14),Color("624936"),true)
	var font: Font
	if ResourceLoader.exists("res://assets/fonts/caveat/Caveat.ttf"): font=load("res://assets/fonts/caveat/Caveat.ttf")
	else:
		font=FontFile.new()
		font.load_dynamic_font("res://assets/fonts/caveat/Caveat.ttf")
	var text := Label3D.new()
	text.name="Names"
	text.text="Digo\nLívia\nRaul\nJessica\nNadir"
	text.font=font
	text.font_size=38
	text.pixel_size=.006
	text.outline_size=0
	text.modulate=Color("ede8d3")
	text.position=Vector3(0,1.65,.104)
	board.add_child(text)
