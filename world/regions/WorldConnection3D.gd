extends Node3D
## Shared, non-regional structure for the authored Harbor -> Mountain route.
## Regional road chunks own the asphalt. This node owns only the bridge deck,
## margins, barriers, abutment and tunnel shell so neither region duplicates it.

const UNIT := 1.0 / 16.0
const HARBOR_OCEAN := preload("res://world/regions/HarborOcean.gd")
const PIER_FOAM := preload("res://world/regions/bridge_pier_foam.gdshader")
const NORTH_GATEWAY := preload("res://world/north_gateway/NorthGateway.gd")
const NORTH_GATEWAY_POLICY := preload("res://world/north_gateway/NorthGatewayPolicy.gd")
const PIER_FOAM_REACH := 1.3
const LOOK_MESH := preload("res://world/regions/bridge_look/BridgeLookMesh.gd")
const LOOK_CONCRETE := preload("res://world/regions/bridge_look/bridge_concrete.gdshader")
const UNIFIED_BRIDGE := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
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
const MOUNTAIN_BLEND_END_X := TUNNEL_END_X + 20.0
const MOUNTAIN_NORTH_FADE := Vector2(-203.75, -128.75)

static func unified_bridge_enabled() -> bool:
	return UNIFIED_BRIDGE.enabled()

static func tunnel_camera_weight(point: Vector3) -> float:
	if absf(point.z-CENTER_Z) > TUNNEL_CLEAR_HALF_WIDTH or point.y > 4.4: return 0.0
	var approach := maxf(TUNNEL_START_X-point.x,point.x-TUNNEL_END_X)
	# Lower the camera before the portal; keep it low until clear of the roof.
	return 1.0-smoothstep(8.0,24.0,approach)

var _materials: Dictionary = {}
var bridge_lamps: Array[OmniLight3D] = []
## Acabamento da ponte (concreto com textura, pilares com forma, fáscia e guarda-corpo).
## GETECO_BRIDGE_LOOK=0 restaura as caixas lisas de antes; colisão é a mesma nos dois.
static var look_enabled := OS.get_environment("GETECO_BRIDGE_LOOK") != "0"
## Sombra das luzes do teto do túnel da ponte (A/B do pico isolado de 220–250 ms na emenda
## ponte–serra, auditoria Godot 4.7 de 19/10, §5 item 1). GETECO_TUNNEL_LIGHT_SHADOWS=0 desliga.
static var tunnel_light_shadows := OS.get_environment("GETECO_TUNNEL_LIGHT_SHADOWS") != "0"
## Fade por distância da câmera nas luzes do túnel. Dentro dele a câmera é de perseguição (~6 m atrás);
## por fora, a ortográfica fica a ~36 m e o teto esconde as luzes: além do fade nem a luz nem o mapa
## de sombra são processados.
const TUNNEL_LIGHT_FADE_BEGIN := 45.0
const TUNNEL_LIGHT_FADE_LENGTH := 10.0
const TUNNEL_LIGHT_SHADOW_FADE := 25.0
static var _look_materials: Dictionary = {}
static var _unified_geometry: PackedScene
static var _unified_materials: Array[Material] = []
static var unified_geometry_summary: Dictionary = {}

## Chamado sob a cortina. O builder fica fora da arvore: nao executa _ready,
## nao monta o braco norte e nao registra fisica no mundo do jogador.
static func prewarm_unified_geometry() -> void:
	if not UNIFIED_BRIDGE.enabled() or _unified_geometry != null: return
	var began := Time.get_ticks_usec()
	var builder := Node3D.new()
	var builder_script: Script = load("res://world/regions/WorldConnection3D.gd")
	builder.set_script(builder_script)
	builder.call("_build_unified_bridge")
	builder.call("_build_tunnel")
	_unified_materials.clear()
	var meshes := builder.find_children("*","MeshInstance3D",true,false)
	for entry in meshes:
		var mesh := entry as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var finish := mesh.get_active_material(surface)
			if finish != null and not _unified_materials.has(finish): _unified_materials.append(finish)
	var shapes := builder.find_children("*","CollisionShape3D",true,false).size()
	# A raiz do blueprint precisa ser neutra; instanciar nunca pode recursar _ready.
	builder.set_script(null)
	builder.name = "UnifiedBridgeGeometryBlueprint"
	_own_unified_geometry(builder,builder)
	var blueprint := PackedScene.new()
	var error := blueprint.pack(builder)
	if error == OK: _unified_geometry = blueprint
	else: push_error("Falha ao preparar geometria da ponte: %s" % error)
	unified_geometry_summary = {"prepared":error==OK,"meshes":meshes.size(),"shapes":shapes,"materials":_unified_materials.size(),"usec":Time.get_ticks_usec()-began}
	builder.free()

static func _own_unified_geometry(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_own_unified_geometry(child,root)

static func unified_geometry_materials() -> Array:
	prewarm_unified_geometry()
	return _unified_materials.duplicate()

func _mount_unified_geometry() -> bool:
	if _unified_geometry == null: return false
	var geometry := _unified_geometry.instantiate() as Node3D
	for child in geometry.get_children():
		# Ownership serve apenas ao pack; a raiz temporaria deixa de ser ancestral
		# ao transferir os filhos. Limpar antes evita referencias inconsistentes.
		child.owner = null
		_own_unified_geometry(child,null)
		geometry.remove_child(child)
		add_child(child)
	geometry.free()
	bridge_lamps.clear()
	# Uma varredura por montagem, sem descoberta de luzes em loops por quadro.
	for lamp in find_children("*","OmniLight3D",true,false):
		if lamp.get_meta("bridge_night_lamp",false): bridge_lamps.append(lamp as OmniLight3D)
	set_meta("unified_bridge",true)
	set_meta("bridge_surface_owner","UnifiedBridgeKit")
	set_meta("unified_geometry_cached",true)
	return true

static func logical_region(point: Vector3) -> String:
	if preload("res://world/desert/DesertLayout.gd").contains(point): return "desert"
	return "mountain" if point.x >= SEAM.x and point.z < LOGICAL_NORTH_LIMIT_Z else "harbor"

static func mountain_weight(point: Vector3) -> float:
	# Streaming starts over the sea; the climate starts on the eastern shore.
	var climate_start := TUNNEL_END_X+12.0 if UNIFIED_BRIDGE.enabled() else BRIDGE_END_X
	var climate_end := TUNNEL_END_X+60.0 if UNIFIED_BRIDGE.enabled() else MOUNTAIN_BLEND_END_X
	return smoothstep(climate_start, climate_end, point.x) * (1.0 - smoothstep(MOUNTAIN_NORTH_FADE.x, MOUNTAIN_NORTH_FADE.y, point.z))

static func configure_ground_material(material: ShaderMaterial) -> void:
	material.set_shader_parameter("mountain_entry_x", Vector2(TUNNEL_END_X+12.0,TUNNEL_END_X+60.0) if UNIFIED_BRIDGE.enabled() else Vector2(BRIDGE_END_X, MOUNTAIN_BLEND_END_X))
	material.set_shader_parameter("mountain_north_fade", MOUNTAIN_NORTH_FADE)

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
	if UNIFIED_BRIDGE.enabled():
		# Fixtures sem primer mantem o mesmo caminho construtivo. A producao ja
		# recebeu esse cache da cortina e apenas instancia recursos compartilhados.
		prewarm_unified_geometry()
		if not _mount_unified_geometry():
			_build_unified_bridge()
			_build_tunnel()
	else:
		if look_enabled: _build_bridge_look()
		else: _build_bridge()
		_build_tunnel()
	# The northern worksite shares this connection's streaming owner. It never
	# contributes an edge to the eastern mountain traffic connectors above.
	var owner_world := get_parent() as Node3D
	if is_instance_valid(owner_world) and is_instance_valid(owner_world.get("production")) and not NORTH_GATEWAY_POLICY.baseline_disabled():
		var gateway := NORTH_GATEWAY.new()
		gateway.configure(owner_world)
		add_child(gateway)

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

const PAVEMENT_LOWER := -0.03 # bridge deck and mountain abutment
const PAVEMENT_UPPER := 0.07
const PAVEMENT_EDGE_RUN := 0.40
const PAVEMENT_END_RUN := 0.60

## [low, top, base] of the bevelled pavement; shared by the visual, the convex
## body and the bridge finish so all three keep the exact same vertices.
static func _pavement_shape(x0: float, x1: float, inner_z: float, outer_z: float, bottom: float, start_run := PAVEMENT_END_RUN, end_run := PAVEMENT_END_RUN) -> Array[PackedVector3Array]:
	var side := signf(outer_z-inner_z)
	var low := PackedVector3Array([
		Vector3(x0,PAVEMENT_LOWER,inner_z),Vector3(x1,PAVEMENT_LOWER,inner_z),
		Vector3(x1,PAVEMENT_LOWER,outer_z),Vector3(x0,PAVEMENT_LOWER,outer_z)])
	var top := PackedVector3Array([
		Vector3(x0+start_run,PAVEMENT_UPPER,inner_z+side*PAVEMENT_EDGE_RUN),Vector3(x1-end_run,PAVEMENT_UPPER,inner_z+side*PAVEMENT_EDGE_RUN),
		Vector3(x1-end_run,PAVEMENT_UPPER,outer_z),Vector3(x0+start_run,PAVEMENT_UPPER,outer_z)])
	var base := PackedVector3Array()
	for point in low: base.append(Vector3(point.x,bottom,point.z))
	return [low,top,base]

static func _pavement_body(low: PackedVector3Array, top: PackedVector3Array, base: PackedVector3Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	var points := base.duplicate()
	points.append_array(low)
	points.append_array(top)
	shape.points = points
	collision.shape = shape
	body.add_child(collision)
	return body

## A square vehicle hull catches even a 7 cm vertical paving lip. Keep the
## original footprint and level, but bevel its road edge and both ends. One
## convex body and the visible faces share the exact same vertices.
func _pavement(label: String, x0: float, x1: float, inner_z: float, outer_z: float, material: StandardMaterial3D, bottom := -0.10) -> void:
	var side := signf(outer_z-inner_z)
	var lower := PAVEMENT_LOWER
	var upper := PAVEMENT_UPPER
	var edge_run := PAVEMENT_EDGE_RUN
	var end_run := PAVEMENT_END_RUN
	var shape_points := _pavement_shape(x0,x1,inner_z,outer_z,bottom)
	var low: PackedVector3Array = shape_points[0]
	var top: PackedVector3Array = shape_points[1]
	var base: PackedVector3Array = shape_points[2]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_pavement_face(surface,top,Vector3.UP)
	_pavement_face(surface,PackedVector3Array([low[0],low[1],top[1],top[0]]),Vector3(0,edge_run,-side*(upper-lower)).normalized())
	_pavement_face(surface,PackedVector3Array([low[0],top[0],top[3],low[3]]),Vector3(lower-upper,end_run,0).normalized())
	_pavement_face(surface,PackedVector3Array([low[1],low[2],top[2],top[1]]),Vector3(upper-lower,end_run,0).normalized())
	_pavement_face(surface,PackedVector3Array([base[3],base[2],low[2],top[2],top[3],low[3]]),Vector3(0,0,side))
	_pavement_face(surface,PackedVector3Array([base[0],base[1],low[1],low[0]]),Vector3(0,0,-side))
	_pavement_face(surface,PackedVector3Array([base[0],low[0],low[3],base[3]]),Vector3.LEFT)
	_pavement_face(surface,PackedVector3Array([base[1],base[2],low[2],low[1]]),Vector3.RIGHT)
	_pavement_face(surface,base,Vector3.DOWN)
	var result := MeshInstance3D.new()
	result.name = label
	result.mesh = surface.commit()
	result.material_override = material
	add_child(result)
	result.add_child(_pavement_body(low,top,base))

func _pavement_face(surface: SurfaceTool, points: PackedVector3Array, normal: Vector3) -> void:
	for index in range(1,points.size()-1):
		var triangle := PackedVector3Array([points[0],points[index],points[index+1]])
		var cross := (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0])
		if cross.length_squared()<0.000000000001: continue
		# Godot's visible front is clockwise when viewed from the outward normal.
		if cross.dot(normal)>0.0:
			triangle.reverse()
		for point in triangle:
			surface.set_normal(normal)
			surface.set_uv(Vector2(point.x,point.z)*.5)
			surface.add_vertex(point)

func _build_unified_bridge() -> void:
	# O perfil inteiro nasce da mesma linha e possui o próprio piso físico. Não
	# existe mais um asfalto de remendo entre duas pistas regionais sobrepostas.
	var kit := UNIFIED_BRIDGE.new()
	var sections := UNIFIED_BRIDGE.east_sections()
	var mouth := UNIFIED_BRIDGE.east_mouth_limits()
	for i in range(sections.size()-1):
		var first: Dictionary = sections[i]
		var last: Dictionary = sections[i+1]
		var a: Vector3 = first.point
		var b: Vector3 = last.point
		var midpoint := (a+b)*.5
		var city_junction := is_equal_approx(midpoint.x,375.0) and midpoint.z > -136.0
		var west_open := is_equal_approx(midpoint.x,375.0) and midpoint.z>=mouth.x and midpoint.z<=mouth.y
		var walk_a := UNIFIED_BRIDGE.WALK_HEIGHT
		var walk_b := UNIFIED_BRIDGE.WALK_HEIGHT
		if is_equal_approx(a.x,375.0): walk_a *= smoothstep(133.0,135.0,-a.z)
		if is_equal_approx(b.x,375.0): walk_b *= smoothstep(133.0,135.0,-b.z)
		if i==sections.size()-2: walk_b = 0.0
		var west_a := walk_a
		var west_b := walk_b
		if is_equal_approx(a.x,375.0): west_a *= smoothstep(0.0,2.0,maxf(a.z-mouth.y,mouth.x-a.z))
		if is_equal_approx(b.x,375.0): west_b *= smoothstep(0.0,2.0,maxf(b.z-mouth.y,mouth.x-b.z))
		var walk_exclusions: Array[PackedVector2Array] = []
		var white_exclusions: Array[PackedVector2Array] = []
		if is_equal_approx(midpoint.x,375.0) and midpoint.z>=mouth.x-2.0 and midpoint.z<=mouth.y+2.0:
			# O asfalto do braco norte atravessa esta faixa. A esquina restante
			# continua sendo passeio deste corpo, sem duas superficies empilhadas.
			walk_exclusions.append(UNIFIED_BRIDGE.north_asphalt_footprint())
			white_exclusions.append(UNIFIED_BRIDGE.north_entry_paint_footprint())
		kit.add_segment(a,b,first.side,last.side,first.road,last.road,first.deck,last.deck,
			not city_junction and midpoint.x<TUNNEL_START_X,{
				"guard_negative":not west_open,
				"start_cap":i==0,"end_cap":i==sections.size()-2,
				"walk_height_a":walk_a,"walk_height_b":walk_b,
				"walk_exclusions":walk_exclusions,
				"white_negative_exclusions":white_exclusions,
				"walk_negative_a":west_a,"walk_negative_b":west_b})
	# Apoios com cabeça larga e fuste estreito repetem a mesma modulação. Nenhum
	# volume fica sobre a pista ou passa a vedar o braço norte independente.
	for z in [-151.0,-180.0,-209.0,-238.0,-261.0]:
		_add_unified_support(kit,Vector3(375,0,z),Vector3.RIGHT,13.125,absf(z+125.0))
	for x in [418.75,440.0,487.5,522.5,559.375]:
		var best_distance := INF
		var section_distance := 0.0
		for row in sections:
			var delta: float = row.point.distance_squared_to(Vector3(x,0,CENTER_Z))
			if delta < best_distance:
				best_distance = delta
				section_distance = row.distance
		_add_unified_support(kit,Vector3(x,0,CENTER_Z),Vector3.BACK,UNIFIED_BRIDGE.east_deck_half_width(x),section_distance)
	kit.commit(self,"UnifiedEastBridge")
	set_meta("unified_bridge",true)
	set_meta("bridge_surface_owner","UnifiedBridgeKit")
	_build_bridge_lamps(UNIFIED_BRIDGE.material("steel") as StandardMaterial3D)

func _add_unified_support(kit: UNIFIED_BRIDGE, point: Vector3, side: Vector3, half_width: float, distance: float) -> void:
	kit.section_at(distance)
	var cap_size := Vector3(half_width*2.0-.5,.6,1.4) if absf(side.x)>.9 else Vector3(1.4,.6,half_width*2.0-.5)
	kit.add_box("concrete",point+Vector3.DOWN*1.05,cap_size)
	for sign_value in [-1.0,1.0]:
		var center: Vector3 = point+side*float(sign_value)*(half_width-1.1)
		var bottom := HARBOR_OCEAN.surface_y(Vector2(center.x,center.z))-2.5
		var height := -.75-bottom
		kit.add_box("concrete",Vector3(center.x,bottom+height*.5,center.z),Vector3(1.35,height,1.35),true)
		kit.add_box("concrete",Vector3(center.x,bottom+.3,center.z),Vector3(2.1,.6,2.1))

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
		_beam_between("HarborConnectorRail",Vector3(HARBOR_CONNECTOR_X,.68,CENTER_Z+side*10.5),Vector3(SEAM.x,.68,CENTER_Z+side*6.5),.20,1.18,steel,true)
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
		# Continue Harbor's sidewalk edges before settling onto the wider bridge.
		var shoulder := PackedVector2Array([
			Vector2(SEAM.x,CENTER_Z+side*4.5), Vector2(TRAFFIC_MERGE_X,CENTER_Z+side*5.0),
			Vector2(TRAFFIC_MERGE_X,CENTER_Z+side*BRIDGE_HALF_WIDTH), Vector2(SEAM.x,CENTER_Z+side*6.5)])
		_polygon_mesh("BridgeMarginJoin",shoulder,.07,edge)
		# The underside meets the deck without duplicating its exterior face.
		_pavement("BridgeMargin",TRAFFIC_MERGE_X,BRIDGE_END_X,CENTER_Z+side*5.0,CENTER_Z+side*BRIDGE_HALF_WIDTH,edge,-.03)
		_beam_between("BridgeRailJoin",Vector3(SEAM.x,.68,CENTER_Z+side*6.5),Vector3(TRAFFIC_MERGE_X,.68,CENTER_Z+side*BRIDGE_HALF_WIDTH),.20,1.18,steel,true)
		_box("BridgeGuardRail",Vector3((TRAFFIC_MERGE_X+TUNNEL_START_X)*.5,.68,CENTER_Z+side*BRIDGE_HALF_WIDTH),Vector3(TUNNEL_START_X-TRAFFIC_MERGE_X,1.18,.18),steel,true)
		for x in range(int(SEAM.x*4.0),int(TUNNEL_START_X*4.0)+1,8):
			var post_x := float(x)/4.0
			var rail_width := lerpf(6.5,BRIDGE_HALF_WIDTH,clampf((post_x-SEAM.x)/(TRAFFIC_MERGE_X-SEAM.x),0.0,1.0))
			_box("BridgeRailPost",Vector3(post_x,.48,CENTER_Z+side*rail_width),Vector3(.16,.95,.22),steel)
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
		var rail_width := lerpf(6.5,BRIDGE_HALF_WIDTH,clampf((x-SEAM.x)/(TRAFFIC_MERGE_X-SEAM.x),0.0,1.0))
		if UNIFIED_BRIDGE.enabled(): rail_width = UNIFIED_BRIDGE.east_deck_half_width(x)-.18
		var rail_z := CENTER_Z+side*rail_width
		# The pole grows from the guard rail; its head hangs above the outer
		# shoulder, leaving the whole driving lane clear.
		var pole_bottom := UNIFIED_BRIDGE.WALK_HEIGHT if UNIFIED_BRIDGE.enabled() else 1.22
		_box("BridgeLampPole",Vector3(x,(4.22+pole_bottom)*.5,rail_z),Vector3(.12,4.22-pole_bottom,.12),steel)
		_box("BridgeLampArm",Vector3(x,4.20,rail_z-side*.40),Vector3(.12,.10,.82),steel)
		_box("BridgeLampHead",Vector3(x,4.15,rail_z-side*.82),Vector3(.42,.13,.36),glass)
		var lamp := OmniLight3D.new()
		lamp.name = "BridgeNightLight"
		lamp.set_meta("bridge_night_lamp",true)
		lamp.position = Vector3(x,4.10,rail_z-side*.82)
		lamp.light_color = Color("ffe4b5")
		lamp.omni_range = 17.0
		lamp.omni_attenuation = 1.45
		lamp.shadow_enabled = false
		lamp.light_energy = 0.0
		add_child(lamp)
		bridge_lamps.append(lamp)

# --- Acabamento da ponte (GETECO_BRIDGE_LOOK, padrão ligado) ---
# Só aparência. Cada corpo sólido abaixo repete a caixa/convexo de _build_bridge com o mesmo
# transform global; a malha visível é agrupada por material em BridgeLookMesh.

## Corte dos trechos de malha (ver BridgeLookMesh): conector | primeiro vão | segundo vão.
const LOOK_SEGMENT_CUT_X := 508.0
# Tons ~12% mais escuros e puxados para o cinza frio da ponte antiga: ao meio-dia os bege claros estouravam.
const LOOK_DECK := Color("7d8380")
const LOOK_FASCIA := Color("929690")
const LOOK_PIER := Color("818784")
const LOOK_CAP := Color("71766f")
const LOOK_CURB := Color("9c9e97")
const LOOK_MARGIN := Color("959892")
const LOOK_ABUTMENT := Color("8f938d")
const LOOK_RAIL := Color("4f7378")
const LOOK_POLE := Color("3d4a4f")
const LOOK_HOUSING := Color("2c3134")
const LOOK_NO_WATER := Vector2(-100.0, 0.0)
const LOOK_JOINTS := Vector2(-100.0, 1.0)
const LOOK_SLABS := Vector2(-100.0, 2.0)

## Chuva no concreto da ponte. Chamado pelo CityLook junto com a cidade, sem depender da região: a ponte é
## vista do porto e da serra.
static func set_look_wetness(value: float) -> void:
	if _look_materials.has("concrete"): _look_materials.concrete.set_shader_parameter("rain_wetness", clampf(value, 0.0, 1.0))
	if UNIFIED_BRIDGE.enabled(): UNIFIED_BRIDGE.set_wetness(value)

static func _look_concrete() -> ShaderMaterial:
	if _look_materials.has("concrete"): return _look_materials.concrete
	var material := ShaderMaterial.new()
	material.shader = LOOK_CONCRETE
	var origin := Vector3(500.0,0.0,CENTER_Z)
	material.set_shader_parameter("origin",origin)
	# Juntas de dilatação sobre os apoios: costura, os dois pilares e o encontro da serra.
	material.set_shader_parameter("expansion_joints_x",Vector4(SEAM.x,7800.0*UNIT,8360.0*UNIT,BRIDGE_END_X)-Vector4.ONE*origin.x)
	_look_materials.concrete = material
	return material

static func _look_steel() -> StandardMaterial3D:
	if _look_materials.has("steel"): return _look_materials.steel
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = .5
	material.metallic = .35
	_look_materials.steel = material
	return material

func _solid_box(label: String, point: Vector3, size: Vector3, rotation_y := 0.0) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = point
	body.rotation.y = rotation_y
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

## Mesmo transform de _beam_between: caixa no meio, comprimento em z local, giro atan2.
func _solid_beam(label: String, a: Vector3, b: Vector3, width: float, height: float) -> void:
	var delta := b-a
	_solid_box(label,(a+b)*.5,Vector3(width,height,delta.length()),atan2(delta.x,delta.z))

func _build_bridge_look() -> void:
	var asphalt: StandardMaterial3D = preload("res://world/urban_detail/HarborRoadGeometry3D.gd").new()._material(Color("202932"))
	_build_inner_gap(asphalt)
	# Colisão idêntica à de _build_bridge (mesmas caixas, rótulos e convexos).
	_solid_box("HarborConnectorAbutmentBody",Vector3((HARBOR_ABUTMENT_X+HARBOR_CONNECTOR_X)*.5,-.28,CENTER_Z),Vector3(HARBOR_CONNECTOR_X-HARBOR_ABUTMENT_X,.56,23.0))
	_solid_box("HarborConnectorDeckBody",Vector3((HARBOR_CONNECTOR_X+SEAM.x)*.5,-.38,CENTER_Z),Vector3(SEAM.x-HARBOR_CONNECTOR_X,.76,22.0))
	var length := BRIDGE_END_X-SEAM.x
	_solid_box("ContinuousBridgeDeckBody",Vector3((SEAM.x+BRIDGE_END_X)*.5,-.40,CENTER_Z),Vector3(length,.74,BRIDGE_HALF_WIDTH*2.0))
	_solid_box("MountainAbutmentBody",Vector3((BRIDGE_END_X+TUNNEL_START_X)*.5,-.30,CENTER_Z),Vector3(TUNNEL_START_X-BRIDGE_END_X,.54,18.0))
	for side in [-1.0,1.0]:
		_solid_beam("HarborConnectorRailBody",Vector3(HARBOR_CONNECTOR_X,.68,CENTER_Z+side*10.5),Vector3(SEAM.x,.68,CENTER_Z+side*6.5),.20,1.18)
		_solid_beam("BridgeRailJoinBody",Vector3(SEAM.x,.68,CENTER_Z+side*6.5),Vector3(TRAFFIC_MERGE_X,.68,CENTER_Z+side*BRIDGE_HALF_WIDTH),.20,1.18)
		_solid_box("BridgeGuardRailBody",Vector3((TRAFFIC_MERGE_X+TUNNEL_START_X)*.5,.68,CENTER_Z+side*BRIDGE_HALF_WIDTH),Vector3(TUNNEL_START_X-TRAFFIC_MERGE_X,1.18,.18))
		var margin := _pavement_shape(TRAFFIC_MERGE_X,BRIDGE_END_X,CENTER_Z+side*5.0,CENTER_Z+side*BRIDGE_HALF_WIDTH,-.03)
		var margin_body := _pavement_body(margin[0],margin[1],margin[2])
		margin_body.name = "BridgeMarginBody"
		add_child(margin_body)
	var piers: Array[Array] = []
	for source_x in [6700.0,7040.0]:
		for side in [-1.0,1.0]: piers.append([Vector3(float(source_x)*UNIT,0,CENTER_Z+side*11.2),1.75,3.0])
	for source_x in [7800.0,8360.0]:
		for side in [-1.0,1.0]: piers.append([Vector3(float(source_x)*UNIT,0,CENTER_Z+side*8.2),1.5,4.0])
	for pier in piers:
		_solid_box("BridgePylonBody",pier[0]+Vector3.UP*float(pier[2])*.5,Vector3(pier[1],pier[2],pier[1]))
	var look := LOOK_MESH.new(PackedFloat32Array([SEAM.x,LOOK_SEGMENT_CUT_X]))
	# Só o que fica abaixo do asfalto da serra: o teste de costura exige isso deste nó.
	var deck := LOOK_MESH.new(PackedFloat32Array())
	deck.forced_segment = 0
	_look_structure(look,deck,length)
	for pier in piers: _look_pier(look,pier[0],pier[1],pier[2])
	_look_rails(look)
	_look_lamps(look)
	var concrete := _look_concrete()
	var settings := {
		LOOK_MESH.CONCRETE: [concrete,true],
		LOOK_MESH.STEEL: [_look_steel(),false],
		LOOK_MESH.GLASS: [_lamp_glass(),false],
	}
	look.commit(self,"BridgeLook",settings)
	var deck_meshes := deck.commit(self,"BridgeLookDeck",settings)
	deck_meshes[0].name = "ContinuousBridgeDeck"

func _look_structure(look: LOOK_MESH, deck: LOOK_MESH, length: float) -> void:
	var c := LOOK_MESH.CONCRETE
	# Encontros e tabuleiro do conector: mesmas caixas de antes, agora com o concreto.
	look.box(c,Vector3((HARBOR_ABUTMENT_X+HARBOR_CONNECTOR_X)*.5,-.28,CENTER_Z),Vector3(HARBOR_CONNECTOR_X-HARBOR_ABUTMENT_X,.56,23.0),LOOK_ABUTMENT)
	look.box(c,Vector3((HARBOR_CONNECTOR_X+SEAM.x)*.5,-.38,CENTER_Z),Vector3(SEAM.x-HARBOR_CONNECTOR_X,.76,22.0),LOOK_DECK)
	look.box(c,Vector3((BRIDGE_END_X+TUNNEL_START_X)*.5,-.30,CENTER_Z),Vector3(TUNNEL_START_X-BRIDGE_END_X,.54,18.0),LOOK_ABUTMENT)
	deck.box(c,Vector3((SEAM.x+BRIDGE_END_X)*.5,-.40,CENTER_Z),Vector3(length,.74,BRIDGE_HALF_WIDTH*2.0),LOOK_DECK)
	for side in [-1.0,1.0]:
		# Vigas longarinas: as duas de borda de antes e duas internas, que só a vista
		# lateral mostra. Ficam todas sob o tabuleiro.
		for offset in [BRIDGE_HALF_WIDTH-.6,2.2]:
			deck.box(c,Vector3((SEAM.x+BRIDGE_END_X)*.5,-1.35,CENTER_Z+side*offset),Vector3(length,1.2,.9),LOOK_CAP)
		for offset in [10.3,3.6]:
			look.box(c,Vector3((HARBOR_CONNECTOR_X+SEAM.x)*.5,-1.35,CENTER_Z+side*offset),Vector3(SEAM.x-HARBOR_CONNECTOR_X,1.2,.9),LOOK_CAP)
		# Fáscia: faixa clara na borda do tabuleiro, rente à calçada, com pingadeira (o
		# dente embaixo) que corta a água e desenha a linha de sombra vista de longe.
		var band := PackedVector2Array([Vector2(side*7.2,-.95),Vector2(side*7.42,-.95),Vector2(side*7.42,.07),Vector2(side*7.2,.07)])
		var drip := PackedVector2Array([Vector2(side*7.32,-1.07),Vector2(side*7.42,-1.07),Vector2(side*7.42,-.95),Vector2(side*7.32,-.95)])
		for profile in [band,drip]:
			look.extrude(c,Vector3(SEAM.x,0,CENTER_Z),Vector3(BRIDGE_END_X,0,CENTER_Z),profile,LOOK_FASCIA,LOOK_JOINTS)
		var connector_band := PackedVector2Array([Vector2(side*11.0,-.95),Vector2(side*11.2,-.95),Vector2(side*11.2,0),Vector2(side*11.0,0)])
		var connector_drip := PackedVector2Array([Vector2(side*11.1,-1.07),Vector2(side*11.2,-1.07),Vector2(side*11.2,-.95),Vector2(side*11.1,-.95)])
		for profile in [connector_band,connector_drip]:
			look.extrude(c,Vector3(HARBOR_CONNECTOR_X,0,CENTER_Z),Vector3(SEAM.x,0,CENTER_Z),profile,LOOK_FASCIA,LOOK_JOINTS)
		# Calçadas: a mesma forma chanfrada do corpo convexo, cortada no limite do trecho.
		var inner: float = CENTER_Z+side*5.0
		var outer: float = CENTER_Z+side*BRIDGE_HALF_WIDTH
		_look_pavement(look,TRAFFIC_MERGE_X,LOOK_SEGMENT_CUT_X,inner,outer,true,false)
		_look_pavement(look,LOOK_SEGMENT_CUT_X,BRIDGE_END_X,inner,outer,false,true)
		look.polygon(c,PackedVector3Array([
			Vector3(SEAM.x,.07,CENTER_Z+side*4.5),Vector3(TRAFFIC_MERGE_X,.07,CENTER_Z+side*5.0),
			Vector3(TRAFFIC_MERGE_X,.07,CENTER_Z+side*BRIDGE_HALF_WIDTH),Vector3(SEAM.x,.07,CENTER_Z+side*6.5)]),Vector3.UP,LOOK_MARGIN,LOOK_SLABS)
	# Travessas sob o tabuleiro ligando cada par de pilares: o vão passa a ter apoio visível.
	for source_x in [7800.0,8360.0]:
		deck.box(c,Vector3(source_x*UNIT,-2.25,CENTER_Z),Vector3(1.4,.6,16.4),LOOK_CAP)
	for source_x in [6700.0,7040.0]:
		look.box(c,Vector3(source_x*UNIT,-2.25,CENTER_Z),Vector3(1.4,.6,22.4),LOOK_CAP)

## Faces visíveis da calçada; `bevel_start/end` = ponta de verdade (chanfrada), senão corte
## interno entre trechos, sem face. A face externa fica atrás da fáscia e o fundo no tabuleiro.
func _look_pavement(look: LOOK_MESH, x0: float, x1: float, inner_z: float, outer_z: float, bevel_start: bool, bevel_end: bool) -> void:
	var c := LOOK_MESH.CONCRETE
	var side := signf(outer_z-inner_z)
	var shape := _pavement_shape(x0,x1,inner_z,outer_z,-.03,PAVEMENT_END_RUN if bevel_start else 0.0,PAVEMENT_END_RUN if bevel_end else 0.0)
	var low: PackedVector3Array = shape[0]
	var top: PackedVector3Array = shape[1]
	var rise := PAVEMENT_UPPER-PAVEMENT_LOWER
	look.forced_segment = look._segment((x0+x1)*.5)
	look.polygon(c,top,Vector3.UP,LOOK_MARGIN,LOOK_SLABS)
	look.polygon(c,PackedVector3Array([low[0],low[1],top[1],top[0]]),Vector3(0,PAVEMENT_EDGE_RUN,-side*rise).normalized(),LOOK_CURB,LOOK_JOINTS)
	if bevel_start: look.polygon(c,PackedVector3Array([low[0],top[0],top[3],low[3]]),Vector3(-rise,PAVEMENT_END_RUN,0).normalized(),LOOK_MARGIN,LOOK_SLABS)
	if bevel_end: look.polygon(c,PackedVector3Array([low[1],low[2],top[2],top[1]]),Vector3(rise,PAVEMENT_END_RUN,0).normalized(),LOOK_MARGIN,LOOK_SLABS)
	look.forced_segment = -1

## Pilar com forma: bloco de fundação largo na linha d'água, fuste chanfrado que afina até o
## tabuleiro, fuste superior (a caixa de colisão de antes) e capitel com remate.
func _look_pier(look: LOOK_MESH, top: Vector3, width: float, top_y: float) -> void:
	var c := LOOK_MESH.CONCRETE
	var water_y := HARBOR_OCEAN.surface_y(Vector2(top.x,top.z))
	var water := Vector2(water_y,0.0)
	var base := width+1.1
	look.shaft(c,top,water_y-2.5,_oct(base,.28),water_y+.45,_oct(base,.28),LOOK_CAP,water,false,false)
	look.shaft(c,top,water_y+.45,_oct(base,.28),water_y+.72,_oct(width+.45,.24),LOOK_CAP,water)
	look.shaft(c,top,water_y+.72,_oct(width+.45,.24),-.03,_oct(width,.2),LOOK_PIER,water,false,false)
	look.shaft(c,top,-.03,_oct(width,.2),top_y-.5,_oct(width-.14,.2),LOOK_PIER,water,false,false)
	look.shaft(c,top,top_y-.5,_oct(width-.14,.2),top_y-.42,_oct(width+.2,.16),LOOK_CURB,water,false,false)
	look.shaft(c,top,top_y-.42,_oct(width+.2,.16),top_y-.22,_oct(width+.2,.16),LOOK_CURB,water,false,false)
	look.shaft(c,top,top_y-.22,_oct(width+.2,.16),top_y,_oct(width*.42,.16),LOOK_FASCIA,water)
	_pier_foam(Vector3(top.x,water_y,top.z),base)

static func _oct(size: float, chamfer: float) -> PackedVector2Array:
	return LOOK_MESH.octagon(Vector2.ONE*size*.5,chamfer)

func _pier_foam(water_point: Vector3, footing: float) -> void:
	var foam := MeshInstance3D.new()
	foam.name = "BridgePierFoam"
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE*(footing+PIER_FOAM_REACH*3.2)
	foam.mesh = quad
	foam.position = water_point+Vector3.UP*.02
	foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var key := "foam_%.2f" % footing
	if not _look_materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = PIER_FOAM
		material.set_shader_parameter("half_size",Vector2.ONE*footing*.5)
		material.set_shader_parameter("reach",PIER_FOAM_REACH)
		_look_materials[key] = material
	foam.material_override = _look_materials[key]
	add_child(foam)

## Linhas dos guarda-corpos (mesmas linhas das caixas de colisão), com a meia-espessura
## da colisão: a face interna da mureta coincide com a face interna do corpo sólido.
func _rail_lines() -> Array[Array]:
	var lines: Array[Array] = []
	for side in [-1.0,1.0]:
		lines.append([Vector3(HARBOR_CONNECTOR_X,0,CENTER_Z+side*10.5),Vector3(SEAM.x,0,CENTER_Z+side*6.5),.10,side,0.0])
		lines.append([Vector3(SEAM.x,0,CENTER_Z+side*6.5),Vector3(TRAFFIC_MERGE_X,0,CENTER_Z+side*BRIDGE_HALF_WIDTH),.10,side,PAVEMENT_LOWER])
		lines.append([Vector3(TRAFFIC_MERGE_X,0,CENTER_Z+side*BRIDGE_HALF_WIDTH),Vector3(TUNNEL_START_X,0,CENTER_Z+side*BRIDGE_HALF_WIDTH),.09,side,PAVEMENT_LOWER])
	return lines

## Mureta de concreto com topo chanfrado, montantes a cada 2 m, dois tubos intermediários e
## corrimão sextavado. Tudo dentro do volume da colisão de antes (0,09–1,27 m de altura).
func _look_rails(look: LOOK_MESH) -> void:
	for line in _rail_lines():
		var a: Vector3 = line[0]
		var b: Vector3 = line[1]
		var inner: float = line[2]
		var side: float = line[3]
		var foot: float = line[4]
		# Lateral do caminho é +z para +x; a face de dentro (pista) é -side.
		var s := side
		var curb := PackedVector2Array([Vector2(-s*inner,foot),Vector2(s*.2,foot),Vector2(s*.2,.45),Vector2(-s*(inner-.06),.45),Vector2(-s*inner,.39)])
		look.extrude(LOOK_MESH.CONCRETE,a,b,curb,LOOK_CURB,LOOK_JOINTS)
		var handrail := PackedVector2Array([Vector2(-.075,1.165),Vector2(-.035,1.27),Vector2(.035,1.27),Vector2(.075,1.165),Vector2(.035,1.13),Vector2(-.035,1.13)])
		look.extrude(LOOK_MESH.STEEL,a,b,handrail,LOOK_RAIL)
		for height in [.68,.92]:
			look.extrude(LOOK_MESH.STEEL,a,b,PackedVector2Array([Vector2(-.03,height-.03),Vector2(.03,height-.03),Vector2(.03,height+.03),Vector2(-.03,height+.03)]),LOOK_RAIL)
		var run := Vector2(b.x-a.x,b.z-a.z)
		var count := maxi(1,roundi(run.length()/2.0))
		for index in count+1:
			var point := a.lerp(b,float(index)/count)
			look.box(LOOK_MESH.STEEL,Vector3(point.x,.80,point.z),Vector3(.10,.70,.12),LOOK_POLE,-atan2(run.y,run.x))

## Postes nas mesmas posições (a luz e o alcance de antes); só o desenho muda: base na mureta,
## fuste, braço inclinado, luminária escura com o vidro aceso por baixo.
func _look_lamps(look: LOOK_MESH) -> void:
	for index in 7:
		var x := 460.0+float(index)*19.0
		var side := -1.0 if index%2==0 else 1.0
		var rail_width := lerpf(6.5,BRIDGE_HALF_WIDTH,clampf((x-SEAM.x)/(TRAFFIC_MERGE_X-SEAM.x),0.0,1.0))
		var rail_z := CENTER_Z+side*rail_width
		look.box(LOOK_MESH.STEEL,Vector3(x,.49,rail_z),Vector3(.30,.08,.30),LOOK_POLE)
		look.shaft(LOOK_MESH.STEEL,Vector3(x,0,rail_z),.45,LOOK_MESH.octagon(Vector2.ONE*.09,.3),4.22,LOOK_MESH.octagon(Vector2.ONE*.06,.3),LOOK_POLE)
		look.extrude(LOOK_MESH.STEEL,Vector3(x,0,rail_z),Vector3(x,0,rail_z-side*.70),
			PackedVector2Array([Vector2(-.04,4.16),Vector2(.04,4.16),Vector2(.04,4.24),Vector2(-.04,4.24)]),LOOK_POLE)
		# A câmera do jogo vê o poste de cima: a borda acesa do vidro sai da carcaça, senão
		# a luminária some à noite (a caixa clara de antes era o que marcava o poste).
		look.box(LOOK_MESH.STEEL,Vector3(x,4.235,rail_z-side*.82),Vector3(.36,.07,.24),LOOK_HOUSING)
		look.box(LOOK_MESH.GLASS,Vector3(x,4.165,rail_z-side*.82),Vector3(.46,.07,.34),Color.WHITE)
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

func _lamp_glass() -> StandardMaterial3D:
	var glass := _material("bridge_lamp_glass",Color("dbc391"))
	glass.emission_enabled = true
	glass.emission = Color("d9b776")
	glass.emission_energy_multiplier = 0.55
	return glass

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
	var collision_mesh := _polygon_mesh("HarborConnectorGapCollision",collision_polygon,0.0,asphalt)
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
	var rock := UNIFIED_BRIDGE.material("concrete") as StandardMaterial3D if UNIFIED_BRIDGE.enabled() else _material("tunnel_rock",Color("454b47"))
	var lining := UNIFIED_BRIDGE.material("concrete") as StandardMaterial3D if UNIFIED_BRIDGE.enabled() else _material("tunnel_lining",Color("777b72"))
	var steel := UNIFIED_BRIDGE.material("steel") as StandardMaterial3D if UNIFIED_BRIDGE.enabled() else _material("tunnel_steel",Color("a4afa8"),.62,.18)
	var paving: StandardMaterial3D
	if not UNIFIED_BRIDGE.enabled():
		var road_geometry := preload("res://world/urban_detail/HarborRoadGeometry3D.gd").new()
		paving = road_geometry._material(road_geometry.SIDEWALK_COLOR).duplicate() as StandardMaterial3D
		paving.uv1_triplanar = true
		paving.uv1_world_triplanar = true
		paving.uv1_scale = Vector3.ONE * .5
	var length := TUNNEL_END_X-TUNNEL_START_X
	var road_half_width := 140.0 * UNIT * .5
	for side in [-1.0,1.0]:
		# The rural shoulder continues underneath this structure. Cover it up to
		# the lining with a supported, walkable pavement, flush with bridge margins.
		if not UNIFIED_BRIDGE.enabled():
			_pavement("TunnelSidewalk",TUNNEL_START_X-.575,TUNNEL_END_X+.575,CENTER_Z+side*road_half_width,CENTER_Z+side*TUNNEL_CLEAR_HALF_WIDTH,paving)
		_box("TunnelWall",Vector3((TUNNEL_START_X+TUNNEL_END_X)*.5,2.2,CENTER_Z+side*(TUNNEL_CLEAR_HALF_WIDTH+.55)),Vector3(length,4.4,1.1),rock,true)
		_box("TunnelCurb",Vector3((TUNNEL_START_X+TUNNEL_END_X)*.5,.22,CENTER_Z+side*TUNNEL_CLEAR_HALF_WIDTH),Vector3(length,.44,.45),lining,true)
	_box("TunnelRoof",Vector3((TUNNEL_START_X+TUNNEL_END_X)*.5,4.65,CENTER_Z),Vector3(length,.5,TUNNEL_CLEAR_HALF_WIDTH*2.0+2.2),lining,true)
	# Continuous enclosure; the gameplay camera follows the actor inside it.
	var rib_count := ceili(length/11.0)
	for index in rib_count+1:
		var x := lerpf(TUNNEL_START_X,TUNNEL_END_X,float(index)/rib_count)
		var rib := _box("TunnelRoofRib",Vector3(x,4.25,CENTER_Z),Vector3(.20,.30,TUNNEL_CLEAR_HALF_WIDTH*2.0+1.1),steel,true)
		rib.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if index > 0 and index < rib_count:
			for side in [-1.0,1.0]:
				# Crossbeams bear on the curb through their vertical supports.
				_box("TunnelRibSupport",Vector3(x,2.42,CENTER_Z+side*TUNNEL_CLEAR_HALF_WIDTH),Vector3(.20,3.96,.30),steel,true)
	var glass := _material("tunnel_lamp",Color("e8dec4"))
	glass.emission_enabled = true
	glass.emission = Color("ffe5b3")
	glass.emission_energy_multiplier = 1.0
	for index in rib_count:
		var x := lerpf(TUNNEL_START_X,TUNNEL_END_X,(float(index)+.5)/rib_count)
		_box("TunnelCeilingLamp",Vector3(x,4.30,CENTER_Z),Vector3(1.2,.12,.45),glass)
		var lamp := OmniLight3D.new()
		lamp.name = "TunnelInteriorLight"
		lamp.position = Vector3(x,3.95,CENTER_Z)
		lamp.light_color = Color("ffe9c5")
		lamp.light_energy = 1.3
		lamp.omni_range = 10.0
		# Eram 5 omni com sombra cúbica (6 passadas cada), fora de qualquer pré-aquecimento: a primeira
		# ativação de "omni shadow cubemap" é suspeita do pico da emenda ponte–serra. Paraboloide duplo
		# custa 2 passadas e é a variante aquecida em LocalLightShadowPrewarm. A costura do paraboloide
		# fica no plano perpendicular ao Z local: girada para o Z apontar para baixo, ela cai na altura
		# da lâmpada (teto), e não cortando o piso abaixo de cada luz.
		lamp.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		lamp.shadow_enabled = tunnel_light_shadows
		lamp.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
		lamp.distance_fade_enabled = true
		lamp.distance_fade_begin = TUNNEL_LIGHT_FADE_BEGIN
		lamp.distance_fade_length = TUNNEL_LIGHT_FADE_LENGTH
		lamp.distance_fade_shadow = TUNNEL_LIGHT_SHADOW_FADE
		add_child(lamp)
	for x in [TUNNEL_START_X,TUNNEL_END_X]:
		for side in [-1.0,1.0]:
			_box("TunnelPortalPier",Vector3(x,2.35,CENTER_Z+side*(TUNNEL_CLEAR_HALF_WIDTH+.25)),Vector3(1.15,4.7,1.45),lining,true)
		_box("TunnelPortalHeader",Vector3(x,4.65,CENTER_Z),Vector3(1.15,.8,TUNNEL_CLEAR_HALF_WIDTH*2.0+2.0),lining,true)
