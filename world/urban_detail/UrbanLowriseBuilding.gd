extends "res://world/urban_detail/UrbanSkylineBuilding.gd"
## Exterior-only houses and warehouses using the same static detail batching.
func build() -> void:
	_openings.clear()
	match building_kind:
		"house_gable": _house()
		"house_duplex": _duplex()
		"warehouse_sawtooth": _sawtooth()
		"warehouse_loading": _loading()
	_flush_details()

func _house() -> void:
	var h := height*.72
	var w := building_size.x
	var d := building_size.y
	# Porta no lugar da primeira coluna de janelas; as demais ficam inteiras.
	var column := w/float(maxi(1,floori(w/2.6)))
	_house_door(-w*.5+column*.5,d*.5,minf(1.2,column*.6))
	_block("House",Vector3(0,h*.5,0),Vector3(w,h,d),accent_color)
	_roof(Vector3(0,h,0),w+.35,d+.35,height-h,false)
	_plinth(Vector3.ZERO,Vector3(w,0,d))
	_chimney(Vector3(w*.22,h,-d*.18),height-h)
	_gutters(w,d,h)

func _duplex() -> void:
	var w := building_size.x*.5
	_plinth(Vector3.ZERO,Vector3(building_size.x,0,building_size.y))
	for side in [-1,1]:
		var h := height*(.74 if side == -1 else .67)
		var x: float = side*w*.5
		var depth := building_size.y*(1.0 if side == -1 else .86)
		var z := -(building_size.y-depth)*.5
		_house_door(x,z+depth*.5,1.1)
		_block("Dwelling"+str(side),Vector3(x,h*.5,z),Vector3(w,h,depth),accent_color if side == -1 else accent_color.lightened(.12),"regular",maxi(2,floori(h/2.6)))
		_roof(Vector3(x,h,z),w+.20,depth+.3,height*.26,false)
		_chimney(Vector3(x-side*w*.22,h,z-depth*.2),height*.26)

func _sawtooth() -> void:
	var h := height*.75
	_shutters(1)
	_side_door(h)
	_block("Workshop",Vector3(0,h*.5,0),Vector3(building_size.x,h,building_size.y),accent_color)
	var count := maxi(2,roundi(building_size.y/6.0))
	var span := building_size.y/float(count)
	for index in count:
		var z := -building_size.y*.5+(index+.5)*span
		_roof(Vector3(0,h,z),building_size.x+.25,span,height-h,true)
		_detail(Vector3(0,h+(height-h)*.45,z-span*.5+.035),Vector3(building_size.x-.5,(height-h)*.70,.08),UrbanMaterials.glass_window())
	_plinth(Vector3.ZERO,Vector3(building_size.x,0,building_size.y))
	_gutters(building_size.x,building_size.y,h)

func _loading() -> void:
	var h := height*.79
	var count := maxi(1,floori(building_size.x/7.0))
	_shutters(count)
	_side_door(h)
	_block("Depot",Vector3(0,h*.5,0),Vector3(building_size.x,h,building_size.y),accent_color,"bands")
	_block("Clerestory",Vector3(0,h+(height-h)*.5,0),Vector3(building_size.x*.75,height-h,building_size.y*.35),accent_color.lightened(.1),"glass")
	_plinth(Vector3.ZERO,Vector3(building_size.x,0,building_size.y))
	_gutters(building_size.x,building_size.y,h)
	_rooftop(Vector3(0,h+.03,-building_size.y*.34),Vector3(building_size.x*.8,0,building_size.y*.3),false)
	# Para-choques de borracha da doca, dos dois lados de cada persiana.
	var pitch := building_size.x/float(count)
	for index in count:
		var x := -building_size.x*.5+(index+.5)*pitch
		for edge in [-1,1]:
			_detail(Vector3(x+edge*minf(2.2,pitch*.4),.55,building_size.y*.5+.35),Vector3(.3,.5,.5),UrbanMaterials.trim_dark())

func _shutters(count: int) -> void:
	var pitch := building_size.x/float(count)
	var width := minf(4.0,pitch*.70)
	var h := height*.48
	var z := building_size.y*.5+.13
	for index in count:
		var x := -building_size.x*.5+(index+.5)*pitch
		_reserve(false,z,x,width+.8,h+.5)
		_detail(Vector3(x,h*.5,z),Vector3(width+.25,h+.12,.25),UrbanMaterials.trim_dark())
		_detail(Vector3(x,h*.5,z+.14),Vector3(width,h,.08),UrbanMaterials.metal_steel())
		for slat in range(1,maxi(2,floori(h/.28))):
			_detail(Vector3(x,slat*.28,z+.19),Vector3(width,.035,.03),UrbanMaterials.trim_dark())
		_detail(Vector3(x,h+.26,z+.15),Vector3(width+.5,.18,1.0),UrbanMaterials.roof_tin_rusty())

func _house_door(x: float, face_z: float, width: float) -> void:
	var door_h := minf(2.2,height*.45)
	_reserve(false,face_z+.09,x,width+.4,door_h)
	_detail(Vector3(x,door_h*.5,face_z+.06),Vector3(width+.24,door_h+.12,.16),UrbanMaterials.trim_stone())
	_detail(Vector3(x,door_h*.5,face_z+.12),Vector3(width,door_h,.10),UrbanMaterials.wood_door_brown())
	_detail(Vector3(x+width*.32,door_h*.48,face_z+.19),Vector3(.06,.06,.06),UrbanMaterials.trim_dark())
	_detail(Vector3(x,door_h+.20,face_z+.32),Vector3(width+.8,.14,.7),UrbanMaterials.trim_stone())
	_detail(Vector3(x,.08,face_z+.40),Vector3(width+.6,.16,.7),UrbanMaterials.trim_stone())

func _side_door(wall_h: float) -> void:
	# Porta de serviço na lateral direita, longe das persianas.
	var x := building_size.x*.5+.06
	var z := -building_size.y*.25
	_reserve(true,x,z,1.6,2.3)
	_detail(Vector3(x,1.1,z),Vector3(.12,2.3,1.2),UrbanMaterials.trim_dark())
	_detail(Vector3(x+.05,1.05,z),Vector3(.06,2.1,1.0),UrbanMaterials.metal_steel())
	_detail(Vector3(x+.35,minf(2.6,wall_h-.3),z),Vector3(.7,.10,1.6),UrbanMaterials.roof_tin_rusty())

func _chimney(base: Vector3, rise: float) -> void:
	_detail(base+Vector3(0,rise*.55,0),Vector3(.6,rise*1.1,.6),UrbanMaterials.roof_tar())
	_detail(base+Vector3(0,rise*1.1+.05,0),Vector3(.75,.10,.75),UrbanMaterials.trim_stone())

func _gutters(w: float, d: float, wall_h: float) -> void:
	for sx in [-1,1]:
		for sz in [-1,1]:
			_detail(Vector3(sx*(w*.5+.08),wall_h*.5,sz*(d*.5+.08)),Vector3(.09,wall_h,.09),UrbanMaterials.trim_dark())

func _roof(origin: Vector3, width: float, depth: float, rise: float, shed: bool) -> void:
	var vertices: PackedVector3Array
	if shed:
		# Sawtooth prism: vertical glazed north face and long sloping south roof.
		vertices = PackedVector3Array([Vector3(-width*.5,0,-depth*.5),Vector3(-width*.5,0,depth*.5),Vector3(-width*.5,rise,-depth*.5),Vector3(width*.5,0,-depth*.5),Vector3(width*.5,0,depth*.5),Vector3(width*.5,rise,-depth*.5)])
	else:
		vertices = PackedVector3Array([Vector3(-width*.5,0,-depth*.5),Vector3(width*.5,0,-depth*.5),Vector3(0,rise,-depth*.5),Vector3(-width*.5,0,depth*.5),Vector3(width*.5,0,depth*.5),Vector3(0,rise,depth*.5)])
	var indices := [0,2,1,3,4,5,0,1,4,0,4,3,1,2,5,1,5,4,2,0,3,2,3,5]
	# Godot's front faces use clockwise winding; swapping extrusion axes
	# for the shed reverses the prism orientation.
	if not shed: indices.reverse()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	for index in indices: surface.add_vertex(vertices[index])
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "ShedRoof" if shed else "GableRoof"
	mesh.mesh = surface.commit()
	mesh.position = origin
	mesh.material_override = UrbanMaterials.roof_tin_rusty() if shed else UrbanMaterials.material_for_color(Color("735044"))
	visuals_root.add_child(mesh)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = vertices
	collision.shape = shape
	collision.position = origin
	body.add_child(collision)
	collision_root.add_child(body)
