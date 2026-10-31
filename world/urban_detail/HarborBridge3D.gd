extends Node3D
class_name HarborBridge3D

## Tradução 3D nativa de world/harbor/HarborBridge.gd. O sistema de ruas é dono do
## asfalto e das marcações; este modelo é dono da estrutura do tabuleiro, guarda-corpos de borda,
## pilones estaiados, luminárias e contenção física.

const SCALE:=1.0/16.0
const SOURCE_CENTER:=Vector2(3790,400)
const TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
static var merge_enabled := OS.get_environment("GETECO_BRIDGE_MERGE") != "0"
var materials:={}
var solid_root: StaticBody3D
var _merge_chunk: WeakRef
var _merge_sources: Array[WeakRef] = []

func _ready()->void:
	name="FoundryBridge3D"
	set_meta("source_id","world/harbor/HarborBridge.gd")
	solid_root=StaticBody3D.new()
	solid_root.name="BridgeStructureSolids"
	solid_root.collision_layer=1
	solid_root.collision_mask=0
	add_child(solid_root)
	_build_deck()
	_build_pylons_and_stays()
	_build_luminaires()
	_build_abutment()
	set_process(false)
	if merge_enabled and not Engine.get_meta("geteco_live_preview_build", false):
		# Fontes nascem na ordem original. WorldUnits ainda pode agrupá-las/movê-las
		# até o trecho terminar; referências fracas acompanham essas mesmas peças.
		for source in find_children("*", "MeshInstance3D", true, false): _merge_sources.append(weakref(source))
		var chunk := get_parent()
		if chunk != null and str(chunk.name).begins_with("Chunk_"):
			_merge_chunk = weakref(chunk)
			set_process(true)

func _process(_delta: float) -> void:
	var chunk: Node = _merge_chunk.get_ref() if _merge_chunk != null else null
	if not is_instance_valid(chunk):
		set_process(false)
		return
	if not chunk.has_meta("vegetation_ready_frame"): return
	set_process(false)
	# EditableRegion finaliza as edições depois do retorno da montagem nativa.
	_finish_static_batch.call_deferred()

func _finish_static_batch() -> void:
	if not merge_enabled or not is_inside_tree() or is_queued_for_deletion(): return
	if Engine.get_meta("geteco_live_preview_build", false) or has_meta("bridge_merge_finished"): return
	set_meta("bridge_merge_finished", true)
	var groups := {}
	for reference in _merge_sources:
		var source := reference.get_ref() as MeshInstance3D
		if not is_instance_valid(source) or not _merge_eligible(source): continue
		var key := "%d|%d|%d|%d|%s" % [source.get_active_material(0).get_instance_id(), source.cast_shadow, source.layers, source.gi_mode, source.extra_cull_margin]
		if not groups.has(key): groups[key] = []
		groups[key].append(source)
	var removed := 0
	var added := 0
	for entries in groups.values():
		if entries.size() < 2: continue
		var bounds: AABB = entries[0].global_transform * entries[0].get_aabb()
		for source: MeshInstance3D in entries: bounds = bounds.merge(source.global_transform * source.get_aabb())
		# Duas peças editadas em lados opostos do canal não podem produzir um lote
		# cuja caixa passe sobre o tubo, mesmo sendo seguras individualmente.
		if not _outside_tunnel_cut(bounds): continue
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for source: MeshInstance3D in entries:
			surface.append_from(source.mesh, 0, global_transform.affine_inverse() * source.global_transform)
		var mesh := surface.commit()
		if mesh == null or mesh.get_surface_count() != 1: continue
		var first: MeshInstance3D = entries[0]
		var batch := MeshInstance3D.new()
		batch.name = "BridgeStaticBatch_%d" % added
		batch.mesh = mesh
		batch.material_override = first.get_active_material(0)
		batch.cast_shadow = first.cast_shadow
		batch.layers = first.layers
		batch.gi_mode = first.gi_mode
		batch.extra_cull_margin = first.extra_cull_margin
		batch.set_meta("world_unit_skip", true)
		add_child(batch)
		for source: MeshInstance3D in entries: source.visible = false
		removed += entries.size()
		added += 1
	_merge_sources.clear()
	set_meta("bridge_merge_counts", {"sources_hidden": removed, "batches": added})

func _merge_eligible(source: MeshInstance3D) -> bool:
	if not source.is_visible_in_tree() or source.is_queued_for_deletion(): return false
	if not source.mesh is BoxMesh or source.mesh.get_surface_count() != 1: return false
	if source.get_script() != null or source.get_child_count() > 0 or source.skin != null: return false
	if source.material_overlay != null or source.transparency != 0.0: return false
	if source.visibility_range_begin != 0.0 or source.visibility_range_end != 0.0: return false
	# SurfaceTool não carrega o sinal de escala do nó para o culling do lote.
	if (global_transform.affine_inverse() * source.global_transform).basis.determinant() <= 0.0: return false
	var material := source.get_active_material(0) as StandardMaterial3D
	if material == null or material.emission_enabled or material.next_pass != null: return false
	if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: return false
	var chunk: Node = _merge_chunk.get_ref() if _merge_chunk != null else null
	if not is_instance_valid(chunk): return false
	var current: Node = source
	while current != null and current != chunk:
		if current is CharacterBody3D or current is RigidBody3D or current is AnimatableBody3D: return false
		if current != self and current.get_script() != null: return false
		if current.has_meta("street_fragile_registered") or not str(current.get_meta("place_id", "")).is_empty(): return false
		for group in ["exterior_reveal_building", "v2_walkin_facade", "harbor_building_facade", "canal_tunnel"]:
			if current.is_in_group(group): return false
		var label := str(current.name).to_lower()
		for protected in ["door", "glass", "sign", "neon", "lamp", "light", "beacon", "loot", "fragile"]:
			if label.contains(protected): return false
		current = current.get_parent()
	return current == chunk and _outside_tunnel_cut(source.global_transform * source.get_aabb())

static func _outside_tunnel_cut(bounds: AABB) -> bool:
	# TunnelCutaway trata topo < 0,5 como piso: nunca entra no sweep da câmera.
	# Nesse ramo só a interseção com o corredor fechado pode apagar a peça.
	if bounds.end.y >= 0.5: return false
	var closed := Rect2(TUNNEL.W_PORTAL, TUNNEL.outer_north(), TUNNEL.E_PORTAL - TUNNEL.W_PORTAL, TUNNEL.outer_south() - TUNNEL.outer_north()).grow(-0.05)
	return not Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z).intersects(closed)

func _build_deck()->void:
	# Tabuleiro da V1 3200..4380 x 298..502, centrado neste nó.
	# Mantém a laje abaixo do asfalto do HarborRoadGeometry3D; só as margens e a
	# face de baixo ficam visíveis, como na ordem de camadas da V1 de produção.
	_box("BridgeUnderside",Vector3(0,-.38,0),Vector3(1180*SCALE,.64,204*SCALE),"626e6e",true)
	_box("BridgeDeckEdge",Vector3(0,-.13,0),Vector3(1180*SCALE,.12,220*SCALE),"a7aaa0")
	for north in [true,false]:
		var z:=(-112.0 if north else 112.0)*SCALE
		_box("NorthRail" if north else "SouthRail",Vector3(0,.72,z),Vector3(1180*SCALE,1.44,.26),"5e7479",true)
		_box("RailTop",Vector3(0,1.48,z),Vector3(1180*SCALE,.10,.34),"c6d3cc")
		for source_x in range(3220,4381,40):
			var x:=(float(source_x)-SOURCE_CENTER.x)*SCALE
			_box("RailPost",Vector3(x,.74,z),Vector3(.10,1.42,.10),"3d4b4f")
	_build_structure_detail()
	for source_x in [3208.0,3495.0,4055.0,4372.0]:
		var x:float=(float(source_x)-SOURCE_CENTER.x)*SCALE
		for z in [-6.35,6.35]: _box("ExpansionJoint",Vector3(x,.10,z),Vector3(.20,.04,.45),"445459")

## Volume que a ponte não tinha: da câmera alta só se via uma laje lisa. Vigas e pilares
## sob o tabuleiro, meio-fio e corrimão intermediário. Tudo decorativo (sem colisão).
func _build_structure_detail()->void:
	var length:=1180.0*SCALE
	for z in [-4.2,4.2]:
		_box("UndersideGirder",Vector3(0,-.92,z),Vector3(length,.62,.5),"57625f")
	for x in range(-34,35,4):
		_box("CrossGirder",Vector3(float(x),-.86,0),Vector3(.34,.46,12.2),"4d5857")
	for z in [-6.62,6.62]:
		_box("DeckCurb",Vector3(0,.1,z),Vector3(length,.22,.55),"b2b5aa")
	for z in [-7.0,7.0]:
		_box("RailMidBar",Vector3(0,.98,z),Vector3(length,.08,.14),"3d4b4f")
		_box("RailKick",Vector3(0,.18,z),Vector3(length,.16,.34),"8d9a96")
	for source_x in [3350.0,3500.0,3780.0,4060.0,4220.0]:
		var x:float=(float(source_x)-SOURCE_CENTER.x)*SCALE
		for z in [-4.2,4.2]:
			_box("PierColumn",Vector3(x,-5.3,z),Vector3(1.5,8.8,1.5),"8a948d")
			_box("PierCap",Vector3(x,-1.3,z),Vector3(2.1,.5,2.1),"9aa39b")

func _build_pylons_and_stays()->void:
	for source_x in [3500.0,4060.0]:
		var x:float=(float(source_x)-SOURCE_CENTER.x)*SCALE
		for north in [true,false]:
			var side:float=-1.0 if north else 1.0
			var foot_z:=side*150.0*SCALE
			var rail_z:=side*114.0*SCALE
			_box("PylonFoot",Vector3(x,1.0,foot_z),Vector3(3.25,2.0,3.75),"d5ccb0",true)
			_box("PylonInset",Vector3(x,2.2,foot_z),Vector3(1.88,3.6,2.4),"829391",true)
			_box("PylonMast",Vector3(x,5.9,foot_z),Vector3(.72,7.6,.72),"d7d8c1",true)
			var top:=Vector3(x,9.7,foot_z)
			_sphere("PylonBeacon",top,.32,"e7bd78")
			for offset in [-245.0,-185.0,-125.0,-65.0,65.0,125.0,185.0,245.0]:
				var anchor_x:=clampf(source_x+offset,3208.0,4372.0)
				var anchor:=Vector3((anchor_x-SOURCE_CENTER.x)*SCALE,.9,rail_z)
				_cable("StayCable",top,anchor,.045,"b7c8c6")

func _build_luminaires()->void:
	for source_x in range(3280,4380,210):
		var x:=(float(source_x)-SOURCE_CENTER.x)*SCALE
		for north in [true,false]:
			var z:=(-112.0 if north else 112.0)*SCALE
			_box("BridgeLampPost",Vector3(x,2.15,z),Vector3(.10,2.8,.10),"465357")
			_box("BridgeLampHead",Vector3(x,3.58,z+(.28 if north else -.28)),Vector3(.46,.16,.72),"d8c994")

func _build_abutment()->void:
	var x:=(4380.0-SOURCE_CENTER.x)*SCALE
	# A antiga caixa de altura total cruzava o tabuleiro inteiro e agia como parede
	# invisível na junção leste.  A tampa estrutural fica abaixo do nível da estrada; só
	# as duas asas laterais podem subir ao lado da superfície transitável.
	_box("EastAbutment",Vector3(x+1.05,-.28,0),Vector3(2.25,.56,15.6),"879496",true)
	for z in [-7.1,7.1]:
		_box("AbutmentWing",Vector3(x+.7,.9,z),Vector3(2.9,1.8,1.25),"c5cdbe",true)
	_box("AbutmentJoint",Vector3(x,.12,0),Vector3(.22,.08,15.1),"242d30")

func _box(label:String,at:Vector3,size:Vector3,hex:String,solid:=false)->MeshInstance3D:
	var item:=MeshInstance3D.new()
	item.name=label
	var mesh:=BoxMesh.new()
	mesh.size=size
	item.mesh=mesh
	item.position=at
	item.material_override=_material(hex)
	add_child(item,true)
	if solid:
		var shape:=CollisionShape3D.new()
		var box_shape:=BoxShape3D.new()
		box_shape.size=size
		shape.shape=box_shape
		shape.position=at
		solid_root.add_child(shape)
	return item

func _sphere(label:String,at:Vector3,radius:float,hex:String)->void:
	var item:=MeshInstance3D.new()
	item.name=label
	var mesh:=SphereMesh.new()
	mesh.radius=radius
	mesh.height=radius*2.0
	mesh.radial_segments=12
	mesh.rings=6
	item.mesh=mesh
	item.position=at
	item.material_override=_material(hex)
	add_child(item,true)

func _cable(label:String,a:Vector3,b:Vector3,radius:float,hex:String)->void:
	var delta:=b-a
	var item:=MeshInstance3D.new()
	item.name=label
	var mesh:=CylinderMesh.new()
	mesh.top_radius=radius
	mesh.bottom_radius=radius
	mesh.height=delta.length()
	mesh.radial_segments=8
	item.mesh=mesh
	item.position=(a+b)*.5
	item.quaternion=Quaternion(Vector3.UP,delta.normalized())
	item.material_override=_material(hex)
	add_child(item,true)

func _material(hex:String)->StandardMaterial3D:
	if materials.has(hex): return materials[hex]
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color(hex)
	material.roughness=.72
	material.metallic=.18 if hex in ["5e7479","c6d3cc","3d4b4f","b7c8c6"] else 0.0
	# Cor lisa lia como plano chapado: relevo e rugosidade em espaço de mundo, mesmo tom.
	if Color(hex).a >= 1.0 and not material.emission_enabled:
		preload("res://assets/urban_detail/UrbanSurfaces.gd").detail(material, "metal" if material.metallic > 0.1 else "concrete", 1.5, 1.0)
		material.albedo_color = Color(minf(Color(hex).r * material.albedo_color.r, 1.0), minf(Color(hex).g * material.albedo_color.g, 1.0), minf(Color(hex).b * material.albedo_color.b, 1.0))
		material.roughness = 1.0
	materials[hex]=material
	return material
