extends "res://assets/regions/source/world/mountain_pass/SummitSkiLodge3D.gd"

const SHOP_MATERIALS := preload("res://world/places/ShopInteriorMaterials.gd")
const MANNEQUIN := preload("res://world/places/ShopMannequin.gd")
const FACADE_FINISH := preload("res://world/places/FacadeFinish.gd")

func _ready() -> void:
	# A posição é atribuída antes da admissão pela fábrica da região. Resolve também a
	# posição editada do catálogo, sem acrescentar trabalho ao streamer compartilhado.
	var shop_variant := 2
	for definition in preload("res://world/places/PlaceCatalog.gd").definitions():
		if definition.id in ["mountain_outfitters", "mountain_boutique", "mountain_village_outfitters"] and position.distance_to(definition.exterior_position) < .1:
			shop_variant = definition.variant
			break
	var timber := SHOP_MATERIALS.material("wood", [Color("705b45"), Color("b4a18a"), Color("895c48")][shop_variant-1])
	var stone := SHOP_MATERIALS.material("stone",Color("777975"))
	var trim := SHOP_MATERIALS.material("wood",Color("42362e"))
	var iron := _mat("iron",Color("26333c"),.7,.2)
	var snow := GROUND.material_3d("snow")
	var glass := _mat("glass",Color("657e83"),.25,.25)
	# Mapas por papel (tábua, pedra, chapa) no lugar do ladrilho único de 64 px.
	SURFACE_FINISH.apply(timber, "timber", "wood")
	SURFACE_FINISH.apply(trim, "trim", "wood")
	SURFACE_FINISH.apply(stone, "stone", "granite")
	_box("Foundation",Vector3(0,.12,0),Vector3(6.7,.24,4.0),stone)
	_box("BackWall",Vector3(0,1.6,-1.8),Vector3(6.5,3.0,.24),timber).set_meta("interior_solid_id",&"ShopBack")
	for side in [-1,1]:
		_box("SideWall",Vector3(side*3.15,1.6,0),Vector3(.24,3.0,3.6),timber).set_meta("interior_solid_id",StringName("ShopSide%d"%side))
		_box("WindowPlinth",Vector3(side*1.88,.45,1.8),Vector3(2.5,.65,.25),stone).set_meta("interior_solid_id",StringName("ShopWindow%d"%side))
		_box("WindowLintel",Vector3(side*1.88,2.75,1.8),Vector3(2.5,.3,.25),timber)
		_box("WindowBackdrop%d"%side,Vector3(side*1.88,1.65,1.12),Vector3(2.45,1.9,.06),SHOP_MATERIALS.material("cloth",Color("777569") if shop_variant == 2 else Color("566164")))
		for x in [side*.65,side*3.1]:
			_box("WindowFrame",Vector3(x,1.6,1.83),Vector3(.08,2.2,.12),iron)
		var colors: Array = [[Color("aa714c"),Color("426777")],[Color("c1aa88"),Color("889481")],[Color("995344"),Color("586875")]][shop_variant-1]
		var dummy := MANNEQUIN.create("WindowDisplay%d"%side,colors[0 if side<0 else 1],2 if shop_variant == 2 and side > 0 else 0)
		dummy.position = Vector3(side*1.88,.79,1.48)
		add_child(dummy)
		# O pedestal sólido da vitrine envolve a pegada inteira do manequim; evita
		# gerar um corpo físico trimesh por peça do rig estático de roupas.
		for mesh in dummy.find_children("*","MeshInstance3D",true,false): mesh.remove_meta("interior_solid_id")
		_box("DisplayPlinth%d"%side,Vector3(side*1.88,.76,1.48),Vector3(1.0,.06,.62),stone).set_meta("interior_solid_id",StringName("ShopDisplay%d"%side))
		_box("WindowSill",Vector3(side*1.88,.74,1.85),Vector3(2.55,.09,.40),timber)
		_box("CornerPost%d"%side,Vector3(side*3.19,1.62,1.81),Vector3(.15,3.04,.17),trim)
		_box("SidePlinth%d"%side,Vector3(side*3.28,.43,0),Vector3(.08,.6,3.65),stone)
		for y in [1.0,1.35,1.7,2.05,2.4]:
			_box("Cladding",Vector3(side*3.29,y,0),Vector3(.035,.022,3.7),trim)
		FACADE_FINISH.window(self,Vector3(side*3.32,1.85,-.30),side*PI/2,1.25,1.25,trim,glass)
		FACADE_FINISH.window(self,Vector3(side*1.85,1.85,-1.95),PI,1.20,1.25,trim,glass)
		var roof := _box("Roof",Vector3(side*1.7,3.98,0),Vector3(3.8,.20,4.7),iron,Vector3(0,0,-side*23))
		roof.set_meta("exterior_part","roof_slope")
		_box("SnowRoof",roof.position+Vector3(0,.18,0),Vector3(3.8,.10,4.7),snow,Vector3(0,0,-side*23)).set_meta("exterior_part","roof_snow")
	for z in [-1.8,1.8]:
		_box("GableSupport",Vector3(0,3.155,z),Vector3(6.5,.11,.20),timber)
		FACADE_FINISH.gable(self,"ShopGable",3.25,3.21,4.59,z,.20,timber)
	_box("RidgeCap",Vector3(0,4.79,0),Vector3(.22,.12,4.76),iron)
	_box("RidgeSnow",Vector3(0,4.9,0),Vector3(.30,.10,4.76),snow)
	_box("Door",Vector3(0,1.18,1.82),Vector3(1.1,2.2,.14),iron).set_meta("interior_solid_id",&"ShopDoor")
	_box("DoorGlass",Vector3(0,1.4,1.9),Vector3(.84,1.3,.035),glass)
	_box("Handle",Vector3(.38,1.1,1.94),Vector3(.03,.25,.035),stone)
	_box("Threshold",Vector3(0,.035,2.25),Vector3(1.8,.07,.7),stone)
	_box("NameBoard",Vector3(0,3.04,1.98),Vector3(4.3,.40,.13),trim)
	var label := Label3D.new()
	label.text = "BOUTIQUE ALPINA"
	label.font_size = 48
	label.pixel_size = .007
	label.position = Vector3(0,3.04,2.07)
	label.modulate = Color("ddd5be")
	add_child(label)
