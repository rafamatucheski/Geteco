extends RefCounted
const L := preload("res://world/desert/canyon/DesertSmugglerLayout.gd")
const T := preload("res://world/desert/canyon/DesertSmugglerTerrain.gd")
const G := preload("res://world/desert/DesertGeometry.gd")
const SITE := preload("res://world/desert/canyon/DesertSmugglerSite.gd")
const LIFETIME := preload("res://world/desert/DesertPreparationLifetime.gd")
const DECK_FROM := -611.6
const DECK_TO := -516.0
const SEGMENT := 8.0

static func build_visuals() -> Node3D:
	if not L.enabled(): return Node3D.new()
	var root := T.build_visuals()
	root.name="SmugglerCanyon"
	var structure := Node3D.new()
	structure.name="ExposedGorgeBridge"
	root.add_child(structure)
	_bridge(structure,L.BOUNDS.grow(16.0),false)
	G.batch_repeated_meshes(structure)
	root.add_child(preload("res://world/desert/canyon/ScavengerRemains.gd").build())
	return root

## Versão fatiada de build_visuals para o mirante costeiro (carregamento de 16/10).
static func build_visuals_sliced(tree: SceneTree, token: Dictionary = {}) -> Node3D:
	if LIFETIME.cancelled(token): return null
	if not L.enabled(): return Node3D.new()
	var root: Node3D = await T.build_visuals_sliced(tree,12000,token)
	if LIFETIME.cancelled(token): return null
	LIFETIME.track(token,root)
	root.name="SmugglerCanyon"
	await tree.process_frame
	if LIFETIME.cancelled(token): return null
	var structure := Node3D.new()
	structure.name="ExposedGorgeBridge"
	root.add_child(structure)
	_bridge(structure,L.BOUNDS.grow(16.0),false)
	G.batch_repeated_meshes(structure)
	await tree.process_frame
	if LIFETIME.cancelled(token): return null
	root.add_child(preload("res://world/desert/canyon/ScavengerRemains.gd").build())
	LIFETIME.release(token,root)
	return root

static func build_chunk(parent: Node3D,rect: Rect2) -> Node3D:
	if not L.enabled(): return null
	T.build_collision(parent,rect)
	_bridge(parent,rect,true)
	_approach(parent,rect)
	if rect.has_point(Vector2(L.CENTER.x,L.CENTER.z)):
		var site := SITE.build()
		parent.add_child(site)
		return site
	return null

static func _part(parent: Node3D,id: String,at: Vector3,size: Vector3,color: Color,physical: bool,clip := Rect2()) -> void:
	if not physical:
		G.box(parent,id,at,size,color)
		return
	# Recorta a área real do colisor pela célula dona. O centro da ponte
	# fica exatamente numa borda de célula, então a posse pelo ponto médio perde metade do tabuleiro
	# na preparação de colisão de célula única numa consulta de apoio de restauração/veículo.
	var footprint := Rect2(Vector2(at.x-size.x*.5,at.z-size.z*.5),Vector2(size.x,size.z)).intersection(clip)
	if not footprint.has_area(): return
	at.x=footprint.get_center().x
	at.z=footprint.get_center().y
	size.x=footprint.size.x
	size.z=footprint.size.y
	var body := StaticBody3D.new()
	body.name=id+"Collider"
	body.position=at
	body.collision_layer=1
	body.collision_mask=0
	body.set_meta("vehicle_surface","hard")
	var shape := BoxShape3D.new()
	shape.size=size
	var node := CollisionShape3D.new()
	node.shape=shape
	body.add_child(node)
	parent.add_child(body)

static func _bridge(parent: Node3D,rect: Rect2,physical: bool) -> void:
	for i in ceili((DECK_TO-DECK_FROM)/SEGMENT):
		var from := DECK_FROM+float(i)*SEGMENT
		var to := minf(from+SEGMENT,DECK_TO)
		var middle := (from+to)*.5
		if not rect.intersects(Rect2(L.CENTER.x-2.2,from,4.4,to-from)): continue
		if i==0 or is_equal_approx(to,DECK_TO):
			_deck_ramp(parent,rect,from,to,0.0 if i==0 else L.BRIDGE_DECK,L.BRIDGE_DECK if i==0 else 0.0,physical)
		else:
			_part(parent,"BridgeDeck",Vector3(L.CENTER.x,L.BRIDGE_DECK-.13,middle),Vector3(L.BRIDGE_WIDTH,.26,to-from),Color("736856"),physical,rect)
		for side in [-1.0,1.0]:
			var x := L.CENTER.x+float(side)*(L.BRIDGE_WIDTH*.5+.08)
			# Continuous full-height physical barrier follows the visible steel truss.
			if physical:
				_part(parent,"BridgeEdge",Vector3(x,.7,middle),Vector3(.16,1.4,to-from),Color("61584b"),true,rect)
			else:
				for y in [.22,1.25,-.9]: _part(parent,"RustRail",Vector3(x,float(y),middle),Vector3(.16,.14,to-from),Color("685549"),false)
				for z in [from,to]: _part(parent,"SteelPost",Vector3(x,.35,float(z)),Vector3(.18,2.0,.18),Color("655348"),false)
				var brace := G.box(parent,"BridgeDiagonal",Vector3(x,.58,middle),Vector3(.12,.12,sqrt(pow(to-from,2)+1.0)),Color("544b43"))
				brace.rotation.x=atan2(1.0,to-from)
		if not physical:
			for z in range(ceili(from),ceili(to),2):
				var top := L.BRIDGE_DECK
				if i==0: top=lerpf(0,L.BRIDGE_DECK,(float(z)-from)/(to-from))
				elif is_equal_approx(to,DECK_TO): top=lerpf(L.BRIDGE_DECK,0,(float(z)-from)/(to-from))
				G.box(parent,"DeckJoint",Vector3(L.CENTER.x,top+.002,float(z)),Vector3(L.BRIDGE_WIDTH,.006,.035),Color("423e36"))
	# Aberturas reais de pedestre de .72 m: a cápsula de .60 m do Dante cabe, e todas
	# as carcaças de moto atuais (mínimo de .819 m no FleetCatalog) e carros não.
	for z in [L.GATE_Z,L.GATE_Z+3.0]:
		if not rect.intersects(Rect2(L.CENTER.x-2,float(z)-.225,4,.45)): continue
		for x in [-1.45,0,1.45]:
			_part(parent,"PedestrianBollard",Vector3(L.CENTER.x+float(x),.92,float(z)),Vector3(.73,1.6,.45),Color("b7a378"),physical,rect)
	# Cross-ties below deck articulate scale without adding lights or per-frame work.
	if not physical:
		for i in ceili((L.BRIDGE_END.z-L.BRIDGE_START.z)/24.0):
			var z := L.BRIDGE_START.z+8.0+float(i)*24.0
			if z<L.BRIDGE_END.z: G.box(parent,"BridgeCrossbeam",Vector3(L.CENTER.x,-.8,z),Vector3(4.4,.3,.3),Color("594c40"))

static func _deck_ramp(parent: Node3D,rect: Rect2,from: float,to: float,h0: float,h1: float,physical: bool) -> void:
	var footprint := Rect2(L.CENTER.x-L.BRIDGE_WIDTH*.5,from,L.BRIDGE_WIDTH,to-from).intersection(rect)
	if not footprint.has_area(): return
	var low := lerpf(h0,h1,(footprint.position.y-from)/(to-from))
	var high := lerpf(h0,h1,(footprint.end.y-from)/(to-from))
	var points := PackedVector3Array([Vector3(footprint.position.x,low,footprint.position.y),Vector3(footprint.end.x,low,footprint.position.y),Vector3(footprint.end.x,high,footprint.end.y),Vector3(footprint.position.x,high,footprint.end.y)])
	if not physical:
		G.quad(parent,"BridgeLandingRamp",points,G.material(Color("736856")))
		return
	var body := StaticBody3D.new()
	body.name="BridgeLandingRampCollider"
	body.collision_layer=1
	body.collision_mask=0
	body.set_meta("vehicle_surface","hard")
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(PackedVector3Array([points[0],points[1],points[2],points[0],points[2],points[3]]))
	var node := CollisionShape3D.new()
	node.shape=shape
	body.add_child(node)
	parent.add_child(body)

static func _approach(parent: Node3D,rect: Rect2) -> void:
	var path := L.approach_path()
	for i in range(1,path.size()):
		var a := path[i-1]
		var b := path[i]
		var direction := (b-a).normalized()
		var side := Vector3(-direction.z,0,direction.x)
		var count := ceili(a.distance_to(b)/4.0)
		for j in count:
			var p := a.lerp(b,(float(j)+.5)/float(count))
			if not rect.has_point(Vector2(p.x,p.z)) or p.z>DECK_FROM: continue
			for offset in [-.85,.85]:
				var rut := G.box(parent,"CanyonApproachRut",p+side*float(offset)+Vector3(0,.006,0),Vector3(.38,.01,a.distance_to(b)/float(count)+.03),Color("9b8464"))
				rut.rotation.y=atan2(direction.x,direction.z)
	G.batch_repeated_meshes(parent)
