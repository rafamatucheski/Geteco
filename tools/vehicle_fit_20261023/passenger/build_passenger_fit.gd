extends SceneTree
## Correções offline de vãos reais de produção. Nenhum nó ou laço em runtime.
const FLEET := preload("res://runtime/FleetCatalog.gd")
const ROLES := preload("res://runtime/VehicleSurfaceRoles.gd")
const BATCH := preload("res://tools/fleet_fixups/FleetBatchMesh.gd")
const ROOT := "res://artifacts/vehicle-fit-20261023/passenger"
const IDS := ["porto_rosso","beach_cabriolet","orbita_micro","vale_crossover"]
var tool: SurfaceTool
var added := 0
var repaired := 0

func _initialize() -> void: run.call_deferred()

func tri(a: Vector3,b: Vector3,c: Vector3,n: Vector3,tint:=Color.WHITE) -> void:
	var points: Array[Vector3]=[a,b,c]
	if (b-a).cross(c-a).dot(n)>0: points=[a,c,b]
	for p: Vector3 in points:
		tool.set_normal(n.normalized())
		tool.set_color(tint)
		tool.set_uv(Vector2(p.x,p.z))
		tool.add_vertex(p)
	added+=1

func quad(a: Vector3,b: Vector3,c: Vector3,d: Vector3,n: Vector3,tint:=Color.WHITE) -> void:
	tri(a,b,c,n,tint)
	tri(a,c,d,n,tint)

func roof_caps(id: String) -> void:
	if id=="vale_crossover":
		# A tampa vertical antiga do nariz parava no ombro do capô. Preenche a
		# coroa real de .065 m acima da grade, usando os dez vãos originais.
		for i in 10:
			var x0:=lerpf(-.60,.60,i/10.0)
			var x1:=lerpf(-.60,.60,(i+1)/10.0)
			var h0:=.68+.065*(1.0-pow(x0/.60,2.0))
			var h1:=.68+.065*(1.0-pow(x1/.60,2.0))
			quad(Vector3(x0,.678,-2.181),Vector3(x1,.678,-2.181),Vector3(x1,h1,-2.181),Vector3(x0,h0,-2.181),Vector3.FORWARD)
	if id not in ["orbita_micro","vale_crossover"]: return
	var hw:=.64 if id=="orbita_micro" else .73
	var belt:=1.48 if id=="orbita_micro" else 1.70
	var front:=-.56 if id=="orbita_micro" else -.66
	var rear:=1.04 if id=="orbita_micro" else 1.36
	var rise:=.09 if id=="orbita_micro" else .085
	# Combina com a coroa parabólica autoral do teto e com a borda superior exata do vidro.
	# Cada ponta antes aberta agora une a borda inteira, não só as colunas.
	for z: float in [front,rear]:
		var n:=Vector3.FORWARD if z==front else Vector3.BACK
		for i in 10:
			var x0:=lerpf(-hw,hw,i/10.0)
			var x1:=lerpf(-hw,hw,(i+1)/10.0)
			var h0:=belt+rise*(1.0-pow(x0/hw,2.0))
			var h1:=belt+rise*(1.0-pow(x1/hw,2.0))
			quad(Vector3(x0,belt-.003,z),Vector3(x1,belt-.003,z),Vector3(x1,h1,z),Vector3(x0,h0,z),n)

func liners(model: Node3D,id: String) -> void:
	var wheels:={}
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh==null or not part.has_meta("wheel_center") or not part.get_meta("wheel_spins",true): continue
		var center: Vector3=part.get_meta("wheel_center")
		var box: AABB=part.transform*part.mesh.get_aabb()
		wheels[center]=box if not wheels.has(center) else (wheels[center] as AABB).merge(box)
	for center: Vector3 in wheels:
		var box: AABB=wheels[center]
		var radius:=maxf(box.size.y,box.size.z)*.5+.078
		var side:=signf(center.x)
		# Esta parede traseira fica bem dentro do envelope de esterçamento total, e o
		# revestimento curvo fica fora do raio de varredura diagonal do pneu.
		var inner_x:=side*maxf(.25,absf(center.x)-box.size.x*.5-.30)
		# Fica logo atrás da pele afunilada da carroceria. A caixa precisa chegar à
		# abertura para bloquear a luz oblíqua, sem virar um alargador externo.
		var outer_x:=center.x+side*.002 if id=="beach_cabriolet" else center.x-side*.045
		var tint:=Color("171c20")
		for i in 16:
			var a:=PI*i/16.0
			var b:=PI*(i+1)/16.0
			var pa:=Vector3(0,sin(a)*radius,cos(a)*radius)
			var pb:=Vector3(0,sin(b)*radius,cos(b)*radius)
			var ci:=Vector3(inner_x,center.y,center.z)
			var co:=Vector3(outer_x,center.y,center.z)
			quad(ci+pa,ci+pb,co+pb,co+pa,-(pa+pb).normalized(),tint)
			tri(ci,ci+pb,ci+pa,Vector3(side,0,0),tint)
			# A face traseira impede que a abertura apareça pela caixa oposta.
			tri(ci,ci+pa,ci+pb,Vector3(-side,0,0),tint)

func repair_porto(mesh: Mesh,surface: int) -> Mesh:
	var source:=SurfaceTool.new()
	source.create_from(mesh,surface)
	source.deindex()
	var arrays:=source.commit_to_arrays()
	var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	for cursor in range(0,points.size(),3):
		var a:=points[cursor]
		var b:=points[cursor+1]
		var c:=points[cursor+2]
		var p:=(a+b+c)/3.0
		var cross:=(b-a).cross(c-a)
		# A lateral traseira tem uma única pele externa; os lados dela foram autorados
		# virados para o eixo. Preserva o deque superior, o túnel da roda, as portas e os retrovisores.
		if p.z<.79 or p.y>.86 or absf(p.x)<.70 or absf(cross.x)<cross.length()*.70 or cross.x*p.x<=0: continue
		for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2,Mesh.ARRAY_COLOR]:
			if arrays[channel]==null or arrays[channel].size()!=points.size(): continue
			var old=arrays[channel][cursor+1]
			arrays[channel][cursor+1]=arrays[channel][cursor+2]
			arrays[channel][cursor+2]=old
		for offset in 3:
			var normal: Vector3=arrays[Mesh.ARRAY_NORMAL][cursor+offset]
			if normal.dot(cross)<0: arrays[Mesh.ARRAY_NORMAL][cursor+offset]=-normal
		repaired+=1
	var fixed:=ArrayMesh.new()
	fixed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	fixed.surface_set_material(0,mesh.surface_get_material(surface))
	return fixed

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT+"/candidates"))
	var report:={}
	for id: String in IDS:
		var baseline:="res://artifacts/vehicle-fit-20261023/baseline/assets/"+id+".scn"
		# Lê só snapshots imutáveis depois que o coordenador os criou.
		var packed:=load(baseline if ResourceLoader.exists(baseline) else FLEET.spec(id).scene) as PackedScene
		var model:=packed.instantiate() as Node3D
		var before:=BATCH.counts(model)
		added=0
		repaired=0
		var body:=model.get_node("Body") as MeshInstance3D
		var fresh:=ArrayMesh.new()
		var liner_surface:=-1
		for surface in body.mesh.get_surface_count():
			var mat:=body.get_active_material(surface) as StandardMaterial3D
			if ROLES.key(body,surface)=="trim" and mat!=null and mat.vertex_color_use_as_albedo:
				liner_surface=surface
				break
		assert(liner_surface>=0,"Existing vertex-colour trim surface required")
		for surface in body.mesh.get_surface_count():
			var role:=ROLES.key(body,surface)
			tool=SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			if role=="paint" and id=="porto_rosso": tool.append_from(repair_porto(body.mesh,surface),0,Transform3D.IDENTITY)
			else: tool.append_from(body.mesh,surface,Transform3D.IDENTITY)
			# append_from mantém o buffer de índices da fonte; expande-o antes de
			# acrescentar cantos novos para que o index() final inclua os fechamentos.
			tool.deindex()
			if role=="paint": roof_caps(id)
			if surface==liner_surface: liners(model,id)
			tool.index()
			tool.set_material(body.get_active_material(surface))
			tool.commit(fresh)
		body.material_override=null
		for s in body.get_surface_override_material_count(): body.set_surface_override_material(s,null)
		body.mesh=fresh
		model.set_meta("passenger_fit_revision",20261023)
		var after:=BATCH.counts(model)
		var path:=ROOT+"/candidates/"+id+".scn"
		var status:=BATCH.save_model(model,path)
		report[id]={"candidate":path,"production":"res://assets/fleet/redesigned/"+id+".scn","before":before,"after":after,"triangles_added":added,"triangles_winding_repaired":repaired,"save_error":status,"notes":"Existing mesh/surface count preserved; no light, collision, wheel pivot, catalog or per-frame processing changed. Rendered Main performance is coordinator-owned."}
		print("PASSENGER_FIT ",id," ",JSON.stringify(report[id]))
		model.free()
	FileAccess.open(ROOT+"/manifest.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	quit(0)
