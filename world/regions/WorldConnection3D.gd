extends Node3D
## Shared, non-regional structure for the authored Harbor -> Mountain route.
## Regional road chunks own the asphalt. This node owns only the bridge deck,
## margins, barriers, abutment and tunnel shell so neither region duplicates it.

const UNIT := 1.0 / 16.0
const HARBOR_OCEAN := preload("res://world/regions/HarborOcean.gd")
const PIER_FOAM := preload("res://world/regions/bridge_pier_foam.gdshader")
const PIER_FOAM_REACH := 1.3
const SEAM := Vector3(7300.0, 0.0, -4560.0) * UNIT
const HARBOR_ABUTMENT_X := 6300.0 * UNIT
const HARBOR_CONNECTOR_X := 6480.0 * UNIT
const BRIDGE_START_X := (4300.0 + 3200.0) * UNIT
const BRIDGE_END_X := (4300.0 + 4650.0) * UNIT
const TUNNEL_START_X := (4300.0 + 4950.0) * UNIT
const TUNNEL_END_X := (4300.0 + 5800.0) * UNIT
const CENTER_Z := -4560.0 * UNIT
const TAPER_START_X := 6500.0 * UNIT
const LOGICAL_NORTH_LIMIT_Z := -2000.0 * UNIT
const BRIDGE_HALF_WIDTH := 7.2
const TUNNEL_CLEAR_HALF_WIDTH := 7.15
const TRAFFIC_MERGE_X := SEAM.x + 12.0

var _materials: Dictionary = {}
var bridge_lamps: Array[OmniLight3D] = []

static func logical_region(point: Vector3) -> String:
	return "mountain" if point.x >= SEAM.x and point.z < LOGICAL_NORTH_LIMIT_Z else "harbor"

static func reserves_approach_for_driving(point: Vector2) -> bool:
	return point.x >= HARBOR_CONNECTOR_X and point.x <= SEAM.x and absf(point.y-CENTER_Z) <= 11.0

static func traffic_connectors() -> Array[Dictionary]:
	# V1 transfers the two separated Harbor lanes to MountainPassRoad at this
	# exact head. In 3D they remain short directed graph edges; no vehicle is
	# removed, reparented or teleported at the join.
	return [
		{"id":"continuous_bridge_outbound","width":3.875,"points":PackedVector3Array([
			Vector3(7300.0,0.0,-4529.0)*UNIT, Vector3(TRAFFIC_MERGE_X,0.0,CENTER_Z)])},
		{"id":"continuous_bridge_inbound","width":3.875,"points":PackedVector3Array([
			Vector3(TRAFFIC_MERGE_X,0.0,CENTER_Z), Vector3(7300.0,0.0,-4591.0)*UNIT])},
	]

func _ready() -> void:
	name = "HarborMountainConnection"
	_build_bridge()
	_build_tunnel()

func set_night_lights(level: float) -> void:
	for lamp in bridge_lamps:
		lamp.light_energy = 1.4*clampf(level,0.0,1.0)

func _material(id: String, color: Color, roughness := 0.86, metallic := 0.0) -> StandardMaterial3D:
	if _materials.has(id): return _materials[id]
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	_materials[id] = result
	return result

func _box(label: String, point: Vector3, size: Vector3, material: StandardMaterial3D, solid := false) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = label
	var geometry := BoxMesh.new()
	geometry.size = size
	result.mesh = geometry
	result.position = point
	result.material_override = material
	add_child(result)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		result.add_child(body)
	return result

func _beam_between(label: String, a: Vector3, b: Vector3, width: float, height: float, material: StandardMaterial3D, solid := false) -> MeshInstance3D:
	var delta := b-a
	var result := _box(label,(a+b)*.5,Vector3(width,height,delta.length()),material,solid)
	result.rotation.y = atan2(delta.x,delta.z)
	return result

func _build_bridge() -> void:
	var concrete := _material("bridge_concrete",Color("707b7a"))
	var edge := _material("bridge_edge",Color("a7aaa0"))
	var steel := _material("bridge_steel",Color("83999a"),.58,.32)
	var asphalt: StandardMaterial3D = preload("res://world/urban_detail/HarborRoadGeometry3D.gd").new()._material(Color("202932"))
	# HarborMountainConnector: the divided city approach from the north highway
	# to the shared seam, including its wide two-lane deck and tapered rails.
	_box("HarborConnectorAbutment",Vector3((HARBOR_ABUTMENT_X+HARBOR_CONNECTOR_X)*.5,-.28,CENTER_Z),Vector3(HARBOR_CONNECTOR_X-HARBOR_ABUTMENT_X,.56,23.0),edge,true)
	_box("HarborConnectorDeck",Vector3((HARBOR_CONNECTOR_X+SEAM.x)*.5,-.38,CENTER_Z),Vector3(SEAM.x-HARBOR_CONNECTOR_X,.76,22.0),concrete,true)
	# Productive V1 follows the real inner edges of both curved lanes here. A
	# rectangular/tapered concrete deck alone exposes a pale wedge between them.
	# Keep the structural deck below, but close only the true gap with asphalt;
	# the collision polygon stops at the asphalt edges and therefore does not
	# duplicate either road collider.
	_build_inner_gap(asphalt)
	for side in [-1.0,1.0]:
		_beam_between("HarborConnectorRail",Vector3(HARBOR_CONNECTOR_X,.68,CENTER_Z+side*10.5),Vector3(SEAM.x,.68,CENTER_Z+side*7.15),.20,1.18,steel,true)
	for source_x in [6700.0,7040.0]:
		var x: float = float(source_x)*UNIT
		for side in [-1.0,1.0]:
			_box("HarborConnectorPylon",Vector3(x,1.5,CENTER_Z+side*11.2),Vector3(1.75,3.0,1.75),concrete,true)
			_pier_in_water(Vector3(x,0,CENTER_Z+side*11.2),1.75,concrete)
	var length := BRIDGE_END_X-SEAM.x
	# The Mountain road slab ends at y=0. Keep the structural deck just below
	# it so their coplanar faces cannot alternate in the depth buffer.
	_box("ContinuousBridgeDeck",Vector3((SEAM.x+BRIDGE_END_X)*.5,-.40,CENTER_Z),Vector3(length,.74,BRIDGE_HALF_WIDTH*2.0),concrete,true)
	for side in [-1.0,1.0]:
		_box("BridgeMargin",Vector3((SEAM.x+BRIDGE_END_X)*.5,.02,CENTER_Z+side*6.45),Vector3(length,.10,1.5),edge,true)
		_box("BridgeGuardRail",Vector3((SEAM.x+TUNNEL_START_X)*.5,.68,CENTER_Z+side*BRIDGE_HALF_WIDTH),Vector3(TUNNEL_START_X-SEAM.x,1.18,.18),steel,true)
		for x in range(int(SEAM.x*4.0),int(TUNNEL_START_X*4.0)+1,8):
			_box("BridgeRailPost",Vector3(float(x)/4.0,.48,CENTER_Z+side*BRIDGE_HALF_WIDTH),Vector3(.16,.95,.22),steel)
	# Authored pylon positions: local x=3500 and 4060 in MountainPass.
	for source_x in [7800.0,8360.0]:
		var x: float = float(source_x)*UNIT
		for side in [-1.0,1.0]:
			_box("BridgePylon",Vector3(x,2.0,CENTER_Z+side*8.2),Vector3(1.5,4.0,1.5),concrete,true)
			_pier_in_water(Vector3(x,0,CENTER_Z+side*8.2),1.5,concrete)
	_build_bridge_lamps(steel)
	# Vigas sob as bordas do tabuleiro, só visuais: com o mar rebaixado no vão, dão
	# espessura à ponte e a sombra dela cai longe, mostrando a altura.
	for side in [-1.0,1.0]:
		_box("HarborConnectorGirder",Vector3((HARBOR_CONNECTOR_X+SEAM.x)*.5,-1.35,CENTER_Z+side*10.3),Vector3(SEAM.x-HARBOR_CONNECTOR_X,1.2,.9),concrete)
		_box("BridgeGirder",Vector3((SEAM.x+BRIDGE_END_X)*.5,-1.35,CENTER_Z+side*(BRIDGE_HALF_WIDTH-.6)),Vector3(length,1.2,.9),concrete)
	# East shore/access between the authored bridge end and tunnel portal.
	_box("MountainAbutment",Vector3((BRIDGE_END_X+TUNNEL_START_X)*.5,-.30,CENTER_Z),Vector3(TUNNEL_START_X-BRIDGE_END_X,.54,18.0),edge,true)

## Os pilares começavam em y=0, fora do tabuleiro: ficavam pendurados 0,94 m acima
## do mar. A base desce até dentro da água e a espuma marca onde ela bate.
func _pier_in_water(top: Vector3, width: float, concrete: StandardMaterial3D) -> void:
	var water_y := HARBOR_OCEAN.surface_y(Vector2(top.x,top.z))
	var bottom := water_y-2.5
	_box("BridgePierFooting",Vector3(top.x,(top.y+bottom)*.5,top.z),Vector3(width+.3,top.y-bottom,width+.3),concrete)
	var foam := MeshInstance3D.new()
	foam.name = "BridgePierFoam"
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE*(width+.3+PIER_FOAM_REACH*3.2)
	foam.mesh = quad
	foam.position = Vector3(top.x,water_y+.02,top.z)
	foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = PIER_FOAM
	material.set_shader_parameter("half_size",Vector2.ONE*(width+.3)*.5)
	material.set_shader_parameter("reach",PIER_FOAM_REACH)
	foam.material_override = material
	add_child(foam)

func _build_bridge_lamps(steel: StandardMaterial3D) -> void:
	var glass := _material("bridge_lamp_glass",Color("dbc391"))
	glass.emission_enabled = true
	glass.emission = Color("d9b776")
	glass.emission_energy_multiplier = 0.55
	for index in 7:
		var x := 460.0+float(index)*19.0
		var side := -1.0 if index%2==0 else 1.0
		var rail_z := CENTER_Z+side*BRIDGE_HALF_WIDTH
		# The pole grows from the guard rail; its head hangs above the outer
		# shoulder, leaving the whole driving lane clear.
		_box("BridgeLampPole",Vector3(x,2.72,rail_z),Vector3(.12,3.0,.12),steel)
		_box("BridgeLampArm",Vector3(x,4.20,rail_z-side*.40),Vector3(.12,.10,.82),steel)
		_box("BridgeLampHead",Vector3(x,4.15,rail_z-side*.82),Vector3(.42,.13,.36),glass)
		var lamp := OmniLight3D.new()
		lamp.name = "BridgeNightLight"
		lamp.position = Vector3(x,4.10,rail_z-side*.82)
		lamp.light_color = Color("ffe4b5")
		lamp.omni_range = 17.0
		lamp.omni_attenuation = 1.45
		lamp.shadow_enabled = false
		lamp.light_energy = 0.0
		add_child(lamp)
		bridge_lamps.append(lamp)

static func _approach_centerlines() -> Array[PackedVector2Array]:
	var outbound := PackedVector2Array()
	for i in range(25):
		outbound.append(Vector2(6400,-4200)+Vector2.from_angle(PI+PI*.5*i/24.0)*280.0)
	for i in range(1,25):
		var t := float(i)/24.0
		outbound.append(Vector2(lerpf(6400,7300,t),lerpf(-4480,-4529,smoothstep(0,1,t))))
	var inbound := PackedVector2Array()
	for i in range(25):
		var t := float(i)/24.0
		inbound.append(Vector2(lerpf(7300,6500,t),lerpf(-4591,-4640,smoothstep(0,1,t))))
	return [outbound,inbound]

static func _interpolate_z_at_x(points: PackedVector2Array, x: float) -> float:
	for index in range(points.size()-1):
		var a := points[index]
		var b := points[index+1]
		if (x>=a.x and x<=b.x) or (x<=a.x and x>=b.x):
			var weight := 0.0 if is_equal_approx(a.x,b.x) else (x-a.x)/(b.x-a.x)
			return lerpf(a.y,b.y,clampf(weight,0.0,1.0))
	return points[0].y if x<=points[0].x else points[-1].y

static func inner_gap_polygon(marking_clearance := 3.0) -> PackedVector2Array:
	var roads := _approach_centerlines()
	var outbound: PackedVector2Array = roads[0]
	var inbound: PackedVector2Array = roads[1]
	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	for index in 13:
		var x := lerpf(TAPER_START_X/UNIT,SEAM.x/UNIT,float(index)/12.0)
		upper.append(Vector2(x,_interpolate_z_at_x(inbound,x)+31.0-marking_clearance)*UNIT)
		lower.append(Vector2(x,_interpolate_z_at_x(outbound,x)-31.0+marking_clearance)*UNIT)
	var polygon := upper
	for index in range(lower.size()-1,-1,-1): polygon.append(lower[index])
	return polygon

func _build_inner_gap(asphalt: StandardMaterial3D) -> void:
	var visual_polygon := inner_gap_polygon()
	var collision_polygon := inner_gap_polygon(0.0)
	var visual := _polygon_mesh("HarborConnectorGapAsphalt",visual_polygon,.028,asphalt)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var collision_mesh := _polygon_mesh("HarborConnectorGapCollision",collision_polygon,.027,asphalt)
	collision_mesh.visible = false
	collision_mesh.create_trimesh_collision()
	for child in collision_mesh.get_children():
		if child is StaticBody3D:
			child.name = "HarborConnectorGapBody"
			child.collision_layer = 1
			child.collision_mask = 0

func _polygon_mesh(label: String, polygon: PackedVector2Array, y: float, material: StandardMaterial3D) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in Geometry2D.triangulate_polygon(polygon):
		var point := polygon[index]
		surface.set_normal(Vector3.UP)
		surface.set_uv(point/4.0)
		surface.add_vertex(Vector3(point.x,y,point.y))
	var result := MeshInstance3D.new()
	result.name = label
	result.mesh = surface.commit()
	result.material_override = material
	add_child(result)
	return result

func _build_tunnel() -> void:
	var rock := _material("tunnel_rock",Color("454b47"))
	var lining := _material("tunnel_lining",Color("777b72"))
	var steel := _material("tunnel_steel",Color("a4afa8"),.62,.18)
	var length := TUNNEL_END_X-TUNNEL_START_X
	for side in [-1.0,1.0]:
		_box("TunnelWall",Vector3((TUNNEL_START_X+TUNNEL_END_X)*.5,2.0,CENTER_Z+side*(TUNNEL_CLEAR_HALF_WIDTH+.55)),Vector3(length,4.0,1.1),rock,true)
		_box("TunnelCurb",Vector3((TUNNEL_START_X+TUNNEL_END_X)*.5,.22,CENTER_Z+side*TUNNEL_CLEAR_HALF_WIDTH),Vector3(length,.44,.45),lining,true)
	# Sparse overhead ribs make the enclosure readable without an opaque slab
	# hiding the road from the production camera.
	var rib_count := ceili(length/5.5)
	for index in rib_count+1:
		var x := lerpf(TUNNEL_START_X,TUNNEL_END_X,float(index)/rib_count)
		_box("TunnelRoofRib",Vector3(x,4.25,CENTER_Z),Vector3(.34,.42,TUNNEL_CLEAR_HALF_WIDTH*2.0+1.1),steel,true)
	for x in [TUNNEL_START_X,TUNNEL_END_X]:
		for side in [-1.0,1.0]:
			_box("TunnelPortalPier",Vector3(x,2.35,CENTER_Z+side*(TUNNEL_CLEAR_HALF_WIDTH+.25)),Vector3(1.15,4.7,1.45),lining,true)
		_box("TunnelPortalHeader",Vector3(x,4.65,CENTER_Z),Vector3(1.15,.8,TUNNEL_CLEAR_HALF_WIDTH*2.0+2.0),lining,true)
