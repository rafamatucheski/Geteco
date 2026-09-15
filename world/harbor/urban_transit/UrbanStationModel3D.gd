extends Node3D
## Native geometry calibrated to the street's ground projection.
const PPM := 18.0
const FLOOR_Y := 0.76822128
var orientation := 0.0
var materials: Dictionary = {}
var surfaces: Dictionary = {}
var surface_materials: Dictionary = {}
var surface_solids: Dictionary = {}
var active_solid := ""
var service_material: StandardMaterial3D

func build(angle: float, terminal: bool) -> void:
	orientation = angle
	for entry in [["concrete","a7a897"],["edge","dad8bf"],["steel","aec0bd"],["dark","293c43"],["red","b82f39"],["seat","953840"],["yellow","e5ba55"],["window","294c59"]]:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(entry[1])
		material.roughness = 0.75
		if entry[0] == "steel": material.metallic = 0.55
		materials[entry[0]] = material
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.42,0.66,0.70,0.22)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.roughness = 0.18
	materials.glass = glass
	service_material = StandardMaterial3D.new()
	service_material.emission_enabled = true
	materials.service = service_material
	set_service(true)
	_platform()
	_tube()
	_furniture()
	if terminal: _headhouse()
	for key in surfaces:
		var surface: SurfaceTool = surfaces[key]
		surface.generate_normals()
		var mesh := MeshInstance3D.new()
		mesh.name = "Station_"+key
		mesh.mesh = surface.commit()
		mesh.material_override = materials[surface_materials[key]]
		if surface_solids[key] != "": mesh.set_meta("interior_solid_id", StringName(surface_solids[key]))
		if surface_materials[key] == "glass": mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)

func set_service(active: bool) -> void:
	if service_material == null: return
	service_material.albedo_color = Color("78cbac") if active else Color("dd8056")
	service_material.emission = service_material.albedo_color
	service_material.emission_energy_multiplier = 0.5

func floor_point(point: Vector2, height := 0.0) -> Vector3:
	var ground := point.rotated(orientation)
	return Vector3(ground.x/PPM,height,ground.y/(PPM*FLOOR_Y))

func _quad(a: Vector3,b: Vector3,c: Vector3,d: Vector3,key: String) -> void:
	var material_key := key
	key += ":" + active_solid
	surface_materials[key] = material_key
	surface_solids[key] = active_solid
	if not surfaces.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces[key] = surface
	for vertex in [a,b,c,a,c,d]: surfaces[key].add_vertex(vertex)

func _box(rect: Rect2, bottom: float, height: float, key: String) -> void:
	var points := [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
	var low: Array[Vector3] = []
	var high: Array[Vector3] = []
	for point in points:
		low.append(floor_point(point,bottom))
		high.append(floor_point(point,bottom+height))
	_quad(high[0],high[3],high[2],high[1],key)
	_quad(low[0],low[1],low[2],low[3],key)
	for i in 4:
		var j := (i+1)%4
		_quad(low[i],high[i],high[j],low[j],key)

func _beam(a: Vector3,b: Vector3,radius: float,key: String) -> void:
	var axis := (b-a).normalized()
	var side := axis.cross(Vector3.UP)
	if side.length_squared()<0.01: side = axis.cross(Vector3.RIGHT)
	side = side.normalized()*radius
	var normal := axis.cross(side)
	for i in 8:
		var t := TAU*i/8.0
		var next := TAU*(i+1)/8.0
		var first := side*cos(t)+normal*sin(t)
		var last := side*cos(next)+normal*sin(next)
		_quad(a+first,b+first,b+last,a+last,key)

func _platform() -> void:
	_box(Rect2(-157,-32,314,67),0,0.20,"concrete")
	_box(Rect2(-157,29,314,6),0.20,0.04,"edge")
	for x in range(-147,148,6): _box(Rect2(x,24,2,2),0.205,0.025,"yellow")
	_quad(floor_point(Vector2(155,-5),0.20),floor_point(Vector2(155,22),0.20),floor_point(Vector2(193,22)),floor_point(Vector2(193,-5)),"concrete")

	for y in [-7.0,24.0]:
		active_solid = "RampRail%s" % y
		_box(Rect2(155,y-1,39,2),0,0.22,"edge")
		_beam(floor_point(Vector2(156,y),1.02),floor_point(Vector2(190,y),0.82),0.045,"steel")
		for x in [157.0,187.0]: _beam(floor_point(Vector2(x,y)),floor_point(Vector2(x,y),0.85),0.04,"steel")

	active_solid = ""

func _tube() -> void:
	for x in range(-145,146,29):
		for i in 18:
			var a := PI*i/18.0
			var b := PI*(i+1)/18.0
			_beam(floor_point(Vector2(x,cos(a)*27),1.10+sin(a)*1.75),floor_point(Vector2(x,cos(b)*27),1.10+sin(b)*1.75),0.055,"steel")
		for side in [-1.0,1.0]: _beam(floor_point(Vector2(x,side*27),0.2),floor_point(Vector2(x,side*27),1.1),0.055,"steel")
	for i in 18:
		var a := PI*i/18.0
		var b := PI*(i+1)/18.0
		_quad(floor_point(Vector2(-145,cos(a)*27),1.10+sin(a)*1.75),floor_point(Vector2(145,cos(a)*27),1.10+sin(a)*1.75),floor_point(Vector2(145,cos(b)*27),1.10+sin(b)*1.75),floor_point(Vector2(-145,cos(b)*27),1.10+sin(b)*1.75),"glass")
	active_solid = "TubeBackWall"
	_box(Rect2(-146,-28,292,2),0.20,0.30,"dark")
	_box(Rect2(-147,-28,294,1.6),1.05,0.09,"steel")
	_quad(floor_point(Vector2(-145,-27),0.5),floor_point(Vector2(-145,-27),1.1),floor_point(Vector2(145,-27),1.1),floor_point(Vector2(145,-27),0.5),"glass")
	active_solid = ""
	_box(Rect2(-148,-3,296,6),2.84,0.10,"red")
	for x in [-116.0,-58.0,0.0,58.0,116.0]: _box(Rect2(x-10,-1,20,2),2.79,0.04,"edge")

	for wall in [[Rect2(-148,-28,3,57),"TubeWestWall"],[Rect2(-145,27,247,2),"TubeFrontWall"],[Rect2(140,27,15,2),"TubeFrontEnd"],[Rect2(153,-28,2,22),"TubeEastBack"],[Rect2(153,23,2,6),"TubeEastFront"],[Rect2(102,27,38,2),"BoardingGate"]]:
		active_solid = wall[1]
		_box(wall[0],0.20,0.30,"dark")
		_box(wall[0],0.50,1.15,"glass")
		_box(wall[0],1.65,0.06,"steel")
	active_solid = ""

func _furniture() -> void:
	for x in [-113.0,-65.0,-17.0]:
		active_solid = "StationBench%s" % x
		_box(Rect2(x,-20,24,8),0.53,0.12,"seat")
		_box(Rect2(x,-22,24,2),0.6,0.43,"seat")
		for leg in [x+3,x+20]: _box(Rect2(leg,-18,1.8,5),0.2,0.34,"dark")
	active_solid = "StationTotem"
	# Bus pictogram and physical status lamp replace all floating labels.
	_box(Rect2(139,-20,10,4),0.20,2.8,"red")
	_box(Rect2(141,-15.8,6,0.5),1.85,0.50,"edge")
	_box(Rect2(142,-15.1,4,0.2),2.08,0.18,"window")
	for x in [141.5,145.5]: _box(Rect2(x,-15,1,0.3),1.78,0.10,"dark")
	_box(Rect2(141,-15.6,6,0.6),2.58,0.15,"service")
	active_solid = "TicketReader"
	_box(Rect2(153,-16,3,4),0.2,1.05,"dark")
	_box(Rect2(152,-17,5,6),1.2,0.23,"red")
	_box(Rect2(153,-10.8,3,0.3),1.25,0.10,"service")

	active_solid = ""

func _headhouse() -> void:
	_box(Rect2(-153,-106,168,55),-0.02,0.14,"concrete")
	active_solid = "UrbanTicketOffice"
	_box(Rect2(-145,-102,152,44),0.12,2.4,"edge")
	active_solid = ""
	_box(Rect2(-148,-105,158,50),2.52,0.20,"dark")
	for x in range(-145,8,12): _box(Rect2(x,-103,1.2,46),2.72,0.035,"steel")
	_box(Rect2(-120,-91,86,18),2.75,0.22,"window")
	_box(Rect2(-122,-93,90,22),2.97,0.07,"dark")
	# Glazing on the plaza facade remains visible from the game's south camera.
	for x in [-127.0,-91.0,-38.0]:
		_box(Rect2(x,-103.0,25,0.8),0.85,1.20,"window")
		_box(Rect2(x+12,-103.3,0.8,0.4),0.85,1.20,"steel")
	for x in [-127.0,-91.0]:
		_box(Rect2(x,-57.6,29,0.8),0.85,1.20,"window")
		_box(Rect2(x-1,-57,31,4),0.83,0.10,"steel")
		_box(Rect2(x+14,-56.6,0.8,0.4),0.93,1.05,"steel")
	_box(Rect2(-38,-57.6,25,0.8),0.14,2,"window")
	_box(Rect2(-27,-56.6,0.6,0.8),0.90,0.45,"steel")
	_box(Rect2(-153,-61,169,20),2.23,0.12,"red")
	for x in [-147.0,9.0]:
		active_solid = "CanopyColumn%s" % x
		_box(Rect2(x,-46,2.2,2.2),0.12,2.15,"steel")
	active_solid = ""
