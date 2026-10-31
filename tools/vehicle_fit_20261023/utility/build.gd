extends SceneTree
## Passe de encaixe offline. Não altera produção, rodas, portas nem materiais.
const OUT="res://artifacts/vehicle-fit-20261023/utility"
const IDS=["ranch_pickup","ranch_single","boxrunner","toco_minitruck"]
const METRICS=preload("res://tools/fleet_fixups/FleetBatchMesh.gd")
var extra:Dictionary={}
var removed:=0
func _initialize()->void:run.call_deferred()

func quad(surface:int,a:Vector3,b:Vector3,c:Vector3,d:Vector3,normal:Vector3)->void:
	if not extra.has(surface):extra[surface]=[]
	var points:Array=[a,b,c,a,c,d]
	if (b-a).cross(c-a).dot(normal)>0:points=[a,c,b,a,d,c]
	for p:Vector3 in points:extra[surface].append({"p":p,"n":normal.normalized()})

func frame(surface:int,corners:Array,normal:Vector3)->void:
	# As quatro faixas compartilham vértices exatos com o vidro embutido.
	for rect:Vector4 in [Vector4(0,1,0,.07),Vector4(0,1,.94,1),Vector4(0,.045,.07,.94),Vector4(.955,1,.07,.94)]:
		var pts:Array=[]
		for uv:Vector2 in [Vector2(rect.x,rect.z),Vector2(rect.y,rect.z),Vector2(rect.y,rect.w),Vector2(rect.x,rect.w)]:
			pts.append((corners[0] as Vector3).lerp(corners[1],uv.x).lerp((corners[3] as Vector3).lerp(corners[2],uv.x),uv.y))
		quad(surface,pts[0],pts[1],pts[2],pts[3],normal)

func pane(corners:Array,normal:Vector3)->void:
	var points:Array=[]
	for uv:Vector2 in [Vector2(.045,.07),Vector2(.955,.07),Vector2(.955,.94),Vector2(.045,.94)]:
		points.append((corners[0] as Vector3).lerp(corners[1],uv.x).lerp((corners[3] as Vector3).lerp(corners[2],uv.x),uv.y))
	quad(1,points[0],points[1],points[2],points[3],normal)

func ranch()->void:
	# Fecha a antepara aberta da cabine sob o vidro traseiro. A caçamba fica aberta.
	quad(0,Vector3(-.895,.44,.29),Vector3(.895,.44,.29),Vector3(.895,1.,.29),Vector3(-.895,1.,.29),Vector3.BACK)
	quad(0,Vector3(-.895,.44,.278),Vector3(-.895,1.,.278),Vector3(.895,1.,.278),Vector3(.895,.44,.278),Vector3.FORWARD)
	quad(0,Vector3(-.895,1.,.29),Vector3(.895,1.,.29),Vector3(.85,.97,.39),Vector3(-.85,.97,.39),Vector3.UP)
	# O ombro externo termina 10 mm antes da faixa da janela. Encaixa-o exatamente.
	for side:float in [-1.,1.]:
		quad(0,Vector3(side*.905,1.,-1.07),Vector3(side*.905,1.,.29),Vector3(side*.895,1.,.29),Vector3(side*.895,1.,-1.07),Vector3.UP)

func toco()->void:
	for side:float in [-1.,1.]:
		# Preenche o para-lama superior triangular onde o capô afunilado encontra a cabine.
		quad(0,Vector3(side*.8,1.,-2.09),Vector3(side*.8,1.,-1.89),Vector3(side*.775,1.,-1.89),Vector3(side*.8,1.,-2.09),Vector3.UP)
	# A cabine traseira não tem parede de fundo baixa no export; fecha-a acima do chassi.
	quad(0,Vector3(-.775,.35,-.52),Vector3(.775,.35,-.52),Vector3(.775,1.,-.52),Vector3(-.775,1.,-.52),Vector3.BACK)
	quad(0,Vector3(-.775,.35,-.53),Vector3(-.775,1.,-.53),Vector3(.775,1.,-.53),Vector3(.775,.35,-.53),Vector3.FORWARD)

func boxrunner()->void:
	# Os vidros herdados eram caixas grossas rotacionadas, sobrepostas à cabine
	# aberta autoral. Uma chapa ajustada por abertura remove as placas azuis salientes.
	var wind:Array=[Vector3(-1.02,1.115,-3.247),Vector3(1.02,1.115,-3.247),Vector3(1.02,1.94,-3.075),Vector3(-1.02,1.94,-3.075)]
	frame(12,wind,Vector3(0,.2,-1))
	pane(wind,Vector3(0,.2,-1))
	for side:float in [-1.,1.]:
		var corners:Array=[Vector3(side*1.078,1.14,-3.235),Vector3(side*1.078,1.14,-1.71),Vector3(side*1.078,1.925,-1.71),Vector3(side*1.078,1.925,-3.075)]
		frame(12,corners,Vector3(side,0,0))
		pane(corners,Vector3(side,0,0))

func omit_face(id:String,surface:int,a:Vector3,b:Vector3,c:Vector3)->bool:
	if id=="boxrunner" and surface==1:return true
	# Drop degenerate export faces. These occupy no area and cannot close a gap.
	return (b-a).cross(c-a).length_squared()<.00000000001

func patch(part:MeshInstance3D,id:String)->void:
	var result:=ArrayMesh.new()
	for s in part.mesh.get_surface_count():
		var arrays:Array=part.mesh.surface_get_arrays(s)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if indices.is_empty():
			for i in vertices.size():indices.append(i)
		var keep:=PackedInt32Array()
		for i in range(0,indices.size(),3):
			if omit_face(id,s,vertices[indices[i]],vertices[indices[i+1]],vertices[indices[i+2]]):removed+=1;continue
			keep.append_array(PackedInt32Array([indices[i],indices[i+1],indices[i+2]]))
		var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL]!=null else PackedVector3Array()
		var colors:PackedColorArray=arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
		var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
		var tangents:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT]!=null else PackedFloat32Array()
		for entry:Dictionary in extra.get(s,[]):
			keep.append(vertices.size())
			vertices.append(part.transform.affine_inverse()*entry.p)
			if not normals.is_empty():normals.append((part.basis.transposed()*(entry.n as Vector3)).normalized())
			if not colors.is_empty():colors.append(Color.WHITE)
			if not uv.is_empty():uv.append(Vector2(entry.p.x,entry.p.z))
			if not tangents.is_empty():
				var n:Vector3=entry.n
				var tangent:=Vector3.RIGHT-n*n.dot(Vector3.RIGHT)
				if tangent.length_squared()<.001:tangent=Vector3.UP-n*n.dot(Vector3.UP)
				tangent=tangent.normalized()
				tangents.append_array(PackedFloat32Array([tangent.x,tangent.y,tangent.z,1.]))
		arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_INDEX]=keep
		arrays[Mesh.ARRAY_NORMAL]=normals if not normals.is_empty() else null
		arrays[Mesh.ARRAY_COLOR]=colors if not colors.is_empty() else null
		arrays[Mesh.ARRAY_TEX_UV]=uv if not uv.is_empty() else null
		arrays[Mesh.ARRAY_TANGENT]=tangents if not tangents.is_empty() else null
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		assert(result.get_surface_count()==s+1,"Utility fit must preserve every source surface")
		result.surface_set_material(s,part.get_active_material(s))
	part.mesh=result
	part.material_override=null
	for s in part.get_surface_override_material_count():part.set_surface_override_material(s,null)

func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT+"/candidates"))
	var report:Dictionary={}
	for id:String in IDS:
		var source:=OUT+"/originals/"+id+".scn"
		var model:Node3D=(load(source) as PackedScene).instantiate()
		var before:Dictionary=METRICS.counts(model)
		extra={};removed=0
		match id:
			"ranch_pickup","ranch_single":ranch()
			"toco_minitruck":toco()
			"boxrunner":boxrunner()
		patch(model.get_node("Body"),id)
		model.set_meta("utility_fit_revision",20261023)
		var path:=OUT+"/candidates/"+id+".scn"
		var status:int=METRICS.save_model(model,path)
		report[id]={"before":before,"after":METRICS.counts(model),"path":path,"source":source,"save_status":status,"degenerate_or_replaced_triangles":removed}
		print("UTILITY_FIT ",id," ",JSON.stringify(report[id]))
		model.free()
	FileAccess.open(OUT+"/manifest.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	quit()
