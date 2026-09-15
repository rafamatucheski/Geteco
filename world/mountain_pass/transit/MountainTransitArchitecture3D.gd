extends Node3D
## Native snowy village. Geometry and blockers share one ground projection.
const LAYOUT := preload("res://world/mountain_pass/transit/MountainTransitVillageLayout.gd")
const PPM := 18.0
const FLOOR_Y := 0.76822128
const GROUND := preload("res://world/mountain_pass/MountainGroundMaterials.gd")
var materials: Dictionary = {}
var solids: Array[Dictionary] = []

func _ready() -> void:
	for pair in [["snow", "9cabb3"], ["snow_edge", "879ea8"], ["stone", "617078"], ["paving", "7c8c91"], ["wood", "725440"], ["trim", "3d3933"], ["roof", "354b55"], ["glass", "537982"], ["white", "e2dfc7"], ["gold", "c8a159"], ["red", "934d43"], ["green", "4e7470"]]:
		materials[pair[0]] = _material(Color(pair[1]))
	for pair in [["snow","snow"],["snow_edge","packed"],["stone","stone"],["paving","packed"]]:
		materials[pair[0]] = GROUND.material_3d(pair[1])
	materials["warm"] = _material(Color("edba65"), true)
	_ground()
	var station_first_mesh := get_child_count()
	var station_first_solid := solids.size()
	_station()
	_shift_section(station_first_mesh,station_first_solid,LAYOUT.STATION_SHIFT)
	_shop()
	for i in 4:
		_chalet(LAYOUT.CABIN_CENTERS[i], i)
	_amenities()

static func floor_from_local(point: Vector2) -> Vector3:
	return Vector3(point.x / PPM, 0, point.y / (PPM * FLOOR_Y))

func _ground() -> void:
	# The small settlement is plowed around buildings; natural forest resumes
	# outside this irregular snowy clearing. Bus access pavement is service-owned.
	var outline := PackedVector2Array([Vector2(7340,-1720), Vector2(7580,-1733), Vector2(7885,-1720), Vector2(7955,-1600), Vector2(7960,-1370), Vector2(7860,-1325), Vector2(7640,-1345), Vector2(7360,-1385), Vector2(7315,-1510)])
	_polygon(outline, 0.002, "snow_edge")
	for i in outline.size():
		var toward: Vector2 = (Vector2(7630,-1540) - outline[i]).normalized() * 11.0
		outline[i] += toward
	_polygon(outline, 0.014, "snow")
	var paths: Array = [LAYOUT.BUS_TO_PLAZA, LAYOUT.PLAZA_TO_SHOP, LAYOUT.PLAZA_TO_WAIT]
	for i in 4:
		paths.append(LAYOUT.cabin_route(i))
	for point in LAYOUT.BENCH_CENTERS:
		paths.append(LAYOUT.bench_access_route(point))
	for path in paths:
		for i in range(path.size() - 1):
			_ground_line(path[i], path[i+1], 34.0, "paving")
			_ground_line(path[i], path[i+1], 25.0, "stone")
	_slab(Rect2(7592, -1624, 108, 108), 0.035, 0.06, "paving")
	for x in range(7600, 7698, 16):
		_ground_line(Vector2(x, -1618), Vector2(x, -1523), 0.8, "stone")
	for y in range(-1618, -1520, 16):
		_ground_line(Vector2(7597, y), Vector2(7694, y), 0.8, "stone")
	# Exactly one marked coach berth. No parked coach is part of the village art.
	for y in [-1783.0, -1737.0]:
		_ground_line(Vector2(7416, y), Vector2(7584, y), 2.2, "gold")
	for x in [7416.0, 7584.0]:
		_ground_line(Vector2(x, -1783), Vector2(x, -1737), 2.2, "gold")
	var bay := _text("01", Vector2(7569, -1729), 0.042, 62, "gold", Vector2(0.9,0.65))
	bay.rotation.x = -PI / 2.0

func _station() -> void:
	_slab(Rect2(7387,-1713,141,93), 0.09, 0.18, "stone")
	var mesh_start := get_child_count()
	var office_bounds := Rect2(LAYOUT.STATION_BOUNDS.position-LAYOUT.STATION_SHIFT,LAYOUT.STATION_BOUNDS.size)
	_slab(office_bounds, 1.32, 2.64, "wood")
	_solid(office_bounds, "MiniTerminalOffice")
	var solid_index := solids.size()-1
	for row in 11:
		_box(Vector2(7457.5,-1649), 0.32 + row * 0.21, Vector3(6.93,0.045,0.075), "trim")
	for x in [7419.0,7497.0]:
		_box(Vector2(x,-1647),1.48,Vector3(1.72,1.24,0.11),"trim")
		_box(Vector2(x,-1645),1.49,Vector3(1.48,1.01,0.08),"warm")
		_box(Vector2(x,-1643),1.49,Vector3(0.045,1.04,0.07),"trim")
	_box(Vector2(7460,-1647),1.2,Vector3(1.02,2.27,0.12),"trim")
	_box(Vector2(7460,-1645),1.47,Vector3(0.80,1.36,0.07),"glass")
	_roof(Vector2(7457.5,-1677),7.4,5.4,2.95,0.27)
	_record_volume(solid_index,mesh_start)
	var canopy := _box(Vector2(7457.5,-1635),2.70,Vector3(7.6,0.14,2.30),"roof")
	canopy.rotation.x = 0.08
	var cap := _box(Vector2(7457.5,-1635),2.81,Vector3(7.62,0.07,2.32),"snow")
	cap.rotation.x = 0.08
	for x in [7396.0,7519.0]:
		_box(Vector2(x,-1624),1.3,Vector3(0.16,2.6,0.16),"wood")
		_solid(Rect2(x-3,-1627,6,6),"TerminalPorchPost")
	_sign("TERMINAL DA SERRA",Vector2(7457,-1617),2.49,Vector2(7.35,0.64),64)
	_sign("HARBOR  ·  PLATAFORMA 01",Vector2(7457,-1712),2.86,Vector2(7.15,0.47),48)
	_bench(Vector2(7418,-1631),1.7)
	_bench(Vector2(7498,-1631),1.5)
	_box(Vector2(7380,-1725),1.36,Vector3(0.10,2.72,0.1),"trim")
	_sign("ÔNIBUS",Vector2(7380,-1725),2.53,Vector2(1.38,0.60),36)
	_box(Vector2(7524,-1668),1.3,Vector3(0.15,1.53,0.9),"green")
	_box(Vector2(7526,-1668),1.42,Vector3(0.07,1.2,0.69),"white")

func _shop() -> void:
	_slab(Rect2(7703,-1682,174,105),0.10,0.20,"stone")
	var mesh_start := get_child_count()
	_slab(LAYOUT.SHOP_BOUNDS,1.51,3.02,"wood")
	_solid(LAYOUT.SHOP_BOUNDS,"WinterClothingShop")
	var solid_index := solids.size()-1
	for row in 12:
		_box(Vector2(7790,-1609),0.31+row*0.22,Vector3(9.02,0.045,0.075),"trim")
	for x in [7741.0,7839.0]:
		_box(Vector2(x,-1608),1.6,Vector3(3.17,1.81,0.14),"trim")
		_box(Vector2(x,-1606),1.6,Vector3(2.91,1.56,0.07),"warm")
		_box(Vector2(x,-1604),1.6,Vector3(0.055,1.56,0.07),"trim")
	_box(Vector2(7790,-1608),1.3,Vector3(1.25,2.49,0.14),"trim")
	_box(Vector2(7790,-1606),1.61,Vector3(1.01,1.55,0.07),"glass")
	_roof(LAYOUT.SHOP_CENTER,10.15,5.85,3.34,0.29)
	_record_volume(solid_index,mesh_start)
	var awning := _box(Vector2(7790,-1595),2.91,Vector3(9.7,0.16,2.2),"red")
	awning.rotation.x = 0.08
	_box(Vector2(7790,-1595),3.02,Vector3(9.7,0.06,2.2),"snow")
	_sign("ROUPAS DE INVERNO",Vector2(7790,-1579),2.68,Vector2(9.55,0.73),70)
	for x in [7712.0,7868.0]:
		# Wall-mounted cantilever brackets leave the public shopping sidewalk open.
		_box(Vector2(x,-1597),2.73,Vector3(0.15,0.19,2.15),"wood")
	for i in 4:
		var x := 7725.0 + i * 17.0 if i < 2 else 7822.0 + (i-2) * 17.0
		_coat(Vector2(x,-1564),["red","green","gold","glass"][i])
		_solid(Rect2(x-7,-1568,14,8),"WinterCoatDisplay")
	_sign("CASACOS  •  LUVAS  •  BOTAS",Vector2(7790,-1577),2.08,Vector2(6.9,0.38),39)

func _chalet(center: Vector2, index: int) -> void:
	var wood_key := "chalet%d" % index
	materials[wood_key] = _material([Color("775a43"),Color("684645"),Color("465e69"),Color("626747")][index])
	_slab(Rect2(center-Vector2(58,35),Vector2(116,78)),0.11,0.22,"stone")
	var mesh_start := get_child_count()
	_slab(Rect2(center-Vector2(52,31),Vector2(104,62)),1.30,2.60,wood_key)
	_solid(Rect2(center-Vector2(52,31),Vector2(104,62)),"Chalet%02d"%(index+1))
	var solid_index := solids.size()-1
	for row in 11:
		_box(center+Vector2(0,32),0.33+row*0.21,Vector3(5.79,0.055,0.07),"trim")
	for side in [-1.0,1.0]:
		_box(center+Vector2(side*31,33),1.43,Vector3(1.47,1.20,0.12),"trim")
		_box(center+Vector2(side*31,35),1.43,Vector3(1.22,0.96,0.07),"warm")
		_box(center+Vector2(side*31,36),1.43,Vector3(0.055,0.98,0.06),"trim")
		_box(center+Vector2(side*31,36),1.43,Vector3(1.24,0.06,0.06),"trim")
		for shutter in [-1.0,1.0]:
			_box(center+Vector2(side*31+shutter*15,34),1.43,Vector3(0.32,1.1,0.10),wood_key)
	_box(center+Vector2(0,33),1.15,Vector3(0.97,2.14,0.14),"trim")
	_box(center+Vector2(0,35),1.31,Vector3(0.77,1.46,0.07),wood_key)
	_box(center+Vector2(5.4,36),1.08,Vector3(0.075,0.13,0.08),"gold")
	_slab(Rect2(center+Vector2(-14,33),Vector2(28,10)),0.11,0.22,"wood")
	_roof(center,6.6,5.46,2.94,0.48)
	# Raised dormer and snowy ridge make every small chalet read as a home.
	_box(center+Vector2(0,8),3.42,Vector3(1.08,0.81,1.0),wood_key)
	_box(center+Vector2(0,16),3.42,Vector3(0.68,0.55,0.07),"warm")
	_box(center+Vector2(0,8),3.89,Vector3(1.29,0.12,1.26),"snow")
	_box(center+Vector2(34,-16),3.63,Vector3(0.47,1.56,0.52),"stone")
	_box(center+Vector2(34,-16),4.42,Vector3(0.64,0.13,0.69),"snow")
	_record_volume(solid_index,mesh_start)
	for i in 3:
		_box(center+Vector2(-40+i*9,38),0.27,Vector3(0.43,0.42,0.45),"wood")

func _amenities() -> void:
	for point in [Vector2(7384,-1570),Vector2(7578,-1532),Vector2(7908,-1565),Vector2(7650,-1364)]:
		_box(point,1.7,Vector3(0.09,3.4,0.09),"trim")
		_box(point,3.36,Vector3(0.42,0.47,0.42),"warm")
		_box(point,3.67,Vector3(0.58,0.15,0.58),"snow")
		_solid(Rect2(point-Vector2(3,3),Vector2(6,6)),"VillageLamp")
	_bench(LAYOUT.BENCH_CENTERS[2],1.75)
	_bench(LAYOUT.BENCH_CENTERS[3],1.75)
	_box(Vector2(7630,-1666),1.1,Vector3(0.10,2.2,0.1),"wood")
	_sign("CHALÉS  ↓",Vector2(7630,-1666),2.09,Vector2(2.8,0.42),39)
	_sign("ROUPAS  →",Vector2(7630,-1666),1.62,Vector2(2.8,0.42),39)
	for point in [Vector2(7334,-1502),Vector2(7932,-1358),Vector2(7613,-1390)]:
		_box(point,0.57,Vector3(1.55,1.14,0.69),"wood")
		_box(point,1.18,Vector3(1.75,0.14,0.87),"snow")
		_solid(Rect2(point-Vector2(15,7),Vector2(30,14)),"VillageWoodStore")

func _coat(point: Vector2, material: String) -> void:
	_box(point,0.76,Vector3(0.55,0.81,0.27),material)
	for side in [-1.0,1.0]:
		var sleeve := _box(point+Vector2(side*6.1,0),0.77,Vector3(0.21,0.68,0.26),material)
		sleeve.rotation.z = side*0.16
	for row in 4:
		_box(point+Vector2(0,2.1),0.50+row*0.15,Vector3(0.51,0.023,0.02),"trim")
	_box(point,1.29,Vector3(0.23,0.25,0.21),"white")
	_box(point,0.22,Vector3(0.17,0.33,0.18),"trim")
	_box(point,0.07,Vector3(0.67,0.08,0.52),"trim")

func _roof(point: Vector2, width: float, depth: float, height: float, pitch: float) -> void:
	var panel_width := width * 0.54
	for side in [-1.0,1.0]:
		var offset := Vector2(side * width * 0.245 * PPM,0)
		var panel := _box(point+offset,height,Vector3(panel_width,0.13,depth),"roof")
		panel.rotation.z = -side*pitch
		var snow := _box(point+offset,height+0.12,Vector3(panel_width+0.03,0.12,depth+0.035),"snow")
		snow.rotation.z = -side*pitch
		for rib in 6:
			var seam := _box(point+offset+Vector2(0,(rib-2.5)*depth*PPM*FLOOR_Y/6.0),height+0.19,Vector3(panel_width,0.035,0.025),"snow_edge")
			seam.rotation.z = -side*pitch
	_box(point,height+width*0.245*sin(pitch)+0.13,Vector3(0.16,0.15,depth+0.08),"snow")

func _bench(point: Vector2, width: float) -> void:
	var mesh_start := get_child_count()
	_box(point,0.55,Vector3(width,0.12,0.46),"wood")
	_box(point+Vector2(0,-3),0.88,Vector3(width,0.47,0.1),"wood")
	for side in [-1.0,1.0]:
		_box(point+Vector2(side*width*PPM*0.38,0),0.27,Vector3(0.12,0.53,0.4),"trim")
	_solid(Rect2(point-Vector2(width*PPM*0.5,5),Vector2(width*PPM,10)),"VillageBench")
	_record_volume(solids.size()-1,mesh_start)
	solids[-1]["seats"] = [point+Vector2(-8,0),point+Vector2(8,0)]
	solids[-1]["seat_height"] = 0.55

func _slab(rect: Rect2, height: float, thickness: float, material: String) -> MeshInstance3D:
	return _box(rect.get_center(),height,Vector3(rect.size.x/PPM,thickness,rect.size.y/(PPM*FLOOR_Y)),material)

func _box(point: Vector2,height: float,size: Vector3,material: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = materials[material]
	instance.position = floor_from_local(point-LAYOUT.ORIGIN)+Vector3.UP*height
	add_child(instance)
	return instance

func _ground_line(start: Vector2,end: Vector2,width: float,material: String) -> void:
	var delta := floor_from_local(end-start)
	var height := 0.052 if material == "stone" else 0.033
	var line := _box((start+end)*0.5,height,Vector3(width/PPM,0.016,delta.length()),material)
	line.rotation.y = atan2(delta.x,delta.z)

func _solid(rect: Rect2,label: String) -> void:
	var polygon := PackedVector3Array()
	for point in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
		polygon.append(floor_from_local(point-LAYOUT.ORIGIN))
	solids.append({"name":label,"polygon":polygon,"mountain_rect":rect})

func _record_volume(index: int, first_mesh: int) -> void:
	# Preserve floor occupancy and add the actual rotated structural mesh bounds.
	# Low steps and suspended porch canopies remain available to pedestrians.
	var vertices: PackedVector3Array = solids[index].polygon.duplicate()
	for child_index in range(first_mesh,get_child_count()):
		var child := get_child(child_index)
		if not child is MeshInstance3D: continue
		var bounds: AABB = child.mesh.get_aabb()
		if child.position.y + bounds.size.y*0.5 <= 0.30: continue
		for endpoint in 8:
			vertices.append(child.transform*bounds.get_endpoint(endpoint))
	solids[index]["polygon"] = vertices
	solids[index]["projected_volume"] = true

func _shift_section(first_mesh: int, first_solid: int, offset: Vector2) -> void:
	var displacement := floor_from_local(offset)
	for index in range(first_mesh,get_child_count()):
		get_child(index).position += displacement
	for index in range(first_solid,solids.size()):
		var polygon: PackedVector3Array = solids[index].polygon
		for vertex in polygon.size(): polygon[vertex] += displacement
		solids[index].polygon = polygon
		solids[index].mountain_rect.position += offset
		if solids[index].has("seats"):
			for seat_index in solids[index].seats.size():
				solids[index].seats[seat_index] += offset

func _polygon(points: PackedVector2Array,height: float,material: String) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for point in points:
		vertices.append(floor_from_local(point-LAYOUT.ORIGIN)+Vector3.UP*height)
		normals.append(Vector3.UP)
	var array := []
	array.resize(Mesh.ARRAY_MAX)
	array[Mesh.ARRAY_VERTEX] = vertices
	array[Mesh.ARRAY_NORMAL] = normals
	array[Mesh.ARRAY_INDEX] = Geometry2D.triangulate_polygon(points)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,array)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var mat: StandardMaterial3D = materials[material].duplicate()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = mat
	add_child(instance)

func _material(color: Color,glow := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.83
	material.emission_enabled = glow
	material.emission = color
	material.emission_energy_multiplier = 0.32
	return material

func _text(value: String,point: Vector2,height: float,font_size: int,material: String,size: Vector2) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.font_size = font_size
	var text_width := ThemeDB.fallback_font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	label.pixel_size = minf(size.x*0.91/maxf(text_width,1),size.y*0.80/(font_size*0.72))
	label.modulate = materials[material].albedo_color
	label.outline_size = 0
	label.position = floor_from_local(point-LAYOUT.ORIGIN)+Vector3.UP*height
	add_child(label)
	return label

func _sign(value: String,point: Vector2,height: float,size: Vector2,font_size: int) -> void:
	_box(point,height,Vector3(size.x,size.y,0.1),"trim")
	_text(value,point+Vector2(0,1),height,font_size,"white",size)
