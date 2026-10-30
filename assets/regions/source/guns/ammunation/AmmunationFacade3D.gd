extends Node3D
const ART = preload("res://assets/regions/source/guns/ammunation/AmmunationArt.gd")
var panels: Array[Node3D] = []
var open_amount := 0.0

func set_open_amount(value: float) -> void:
	open_amount = clampf(value,0.0,1.0)
	for i in panels.size():
		panels[i].position.x = (-1.0 if i == 0 else 1.0) * (.45 + .88 * open_amount)

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if name in ["NorthFrontage2","harbor_ammunation"] and PaintedFacadeKit.enabled() and OS.get_environment("GETECO_PAINTED_AMMUNATION_HARBOR") != "0" and not PaintedFacadeKit.style_data("ammunation-harbor").is_empty():
		# O factory conectou finalize antes de _ready: primeiro mantém as mesmas
		# colisões trimesh; depois troca a pele, antes de capturar o cache do trecho.
		ready.connect(_apply_painted_harbor,CONNECT_ONE_SHOT)
	var shell := ART.box(self,Vector3(8.4,2.8,4.4),Vector3(0,1.4,0),ART.INK)
	shell.material_override = preload("res://assets/urban_detail/UrbanMaterials.gd").textured_wall(ART.INK)
	if ready.is_connected(_apply_painted_harbor):
		# Este casco é a única malha que o factory converte em colisão: os demais
		# detalhes são finos, pequenos ou acima de 2,8 m. Não remonta o desenho V1.
		for side in [-1,1]:
			var panel := Node3D.new()
			add_child(panel)
			panel.position = Vector3(side*.45,0,2.32)
			panels.append(panel)
		return
	ART.box(self,Vector3(8.65,.22,4.65),Vector3(0,2.9,0),Color("515957"))
	for side in [-1,1]: ART.box(self,Vector3(.14,.25,4.7),Vector3(side*4.3,3.06,0),ART.INK)
	ART.box(self,Vector3(8.6,.25,.14),Vector3(0,3.06,-2.28),ART.INK)
	var rooftop := Node3D.new()
	add_child(rooftop)
	rooftop.position = Vector3(0,3.025,0)
	rooftop.rotation.x = -PI*.5
	ART.target(rooftop,Vector3(-2.25,0,0),.70)
	ART.text(rooftop,"AMMU\nNATION",Vector3(.55,0,0),.014)
	ART.box(self,Vector3(1.0,.45,.8),Vector3(3,3.18,-1.25),Color("77827b"))
	for i in 6: ART.box(self,Vector3(.8,.015,.03),Vector3(3,3.415,-1.53+i*.10),ART.INK)
	var fascia := ART.box(self,Vector3(8.5,.87,.16),Vector3(0,2.30,2.24),ART.RED)
	fascia.material_override = preload("res://assets/urban_detail/ExteriorFinish.gd").material("paint", ART.RED)
	ART.text(self,"AMMU-NATION",Vector3(0,2.40,2.34),.012)
	for side in [-1,1]:
		ART.target(self,Vector3(side*3.7,2.38,2.35),.24)
		ART.box(self,Vector3(2.35,1.35,.09),Vector3(side*2.5,1.04,2.24),Color("56675d"))
		for i in 8: ART.box(self,Vector3(.032,1.39,.10),Vector3(side*2.5-.97+i*.28,1.04,2.31),ART.INK)
		ART.box(self,Vector3(.22,1.9,.24),Vector3(side*1.0,.95,2.3),ART.RED)
	ART.box(self,Vector3(1.8,1.85,.04),Vector3(0,.94,2.23),Color("080d0d"))
	for side in [-1,1]:
		var panel := Node3D.new()
		add_child(panel)
		panel.position = Vector3(side*.45,0,2.32)
		ART.box(panel,Vector3(.88,1.85,.08),Vector3(0,.94,0),Color("344741"))
		ART.box(panel,Vector3(.035,1.85,.10),Vector3(-side*.43,.94,0),Color("949c8c"))
		ART.box(panel,Vector3(.035,.4,.1),Vector3(-side*.33,.94,.08),ART.CREAM)
		panels.append(panel)
	var canopy := ART.box(self,Vector3(8.7,.10,1.05),Vector3(0,1.9,2.62),ART.RED)
	canopy.material_override = preload("res://assets/urban_detail/ExteriorFinish.gd").material("paint", ART.RED)
	var apron := ART.box(self,Vector3(8.7,.15,1.35),Vector3(0,-.01,2.65),Color("818778"))
	apron.material_override = preload("res://world/urban_detail/PromenadePaving.gd").material(Color("818778"), true)
	ART.box(self,Vector3(1.8,.025,.7),Vector3(0,.08,2.75),ART.INK)
	for side in [-1,1]:
		ART.box(self,Vector3(.15,.68,.15),Vector3(side*3.8,.34,2.9),Color("c8aa54"))
		ART.box(self,Vector3(.17,.16,.17),Vector3(side*3.8,.4,2.9),ART.INK)

func _apply_painted_harbor() -> void:
	# O casco antigo conserva seus corpos. Só a apresentação é substituída.
	for mesh in find_children("*","MeshInstance3D",true,false):
		mesh.hide()
	for label in find_children("*","Label3D",true,false):
		label.hide()
	var scratch := Node3D.new()
	add_child(scratch)
	var painted := PaintedFacadeKit.build(self,"ammunation-harbor",Vector3(8.4,2.8,4.4),scratch,NAN,{"ground_door":false})
	scratch.free()
	var doorway := painted.get_node_or_null("Doorway_front")
	if doorway != null: doorway.free()
	var art := preload("res://runtime/desert/roadside/RoadsideArt.gd")
	for index in panels.size():
		var leaf := art.batch()
		var uv := Rect2(float(index)*.5,0,.5,1)
		leaf.quad(PaintedFacadeKit.material("ammunation-harbor","door_front"),Vector3(0,.94,.055),Vector3(.44,0,0),Vector3(0,.925,0),uv)
		leaf.quad(PaintedFacadeKit.material("ammunation-harbor","door_front_inside"),Vector3(0,.94,-.055),Vector3(-.44,0,0),Vector3(0,.925,0),uv)
		art.instantiate(panels[index],leaf.bake())
	# As mesmas duas folhas continuam deslizando por set_open_amount; sem zona nova.
	set_open_amount(open_amount)
