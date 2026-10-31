extends SceneTree
## Autoria determinística de candidatos. A produção nunca é sobrescrita por este
## script: o coordenador instala os candidatos revisados depois da captura de referência.
const MESH=preload("res://tools/fleet_fixups/FleetBatchMesh.gd")
const ROLES=preload("res://runtime/VehicleSurfaceRoles.gd")
const OUT="res://artifacts/car-fleet-implementation-20261019/candidates"
const ORIGINALS="res://artifacts/car-fleet-implementation-20261019/originals-current"
const FAMILIES={"sedan_classic":"popular","union_sedan":"traditional","aurora_executive":"executive","metro_hatch":"popular","station_wagon":"traditional","desert_faisca":"sport","desert_faisca_rally":"sport","ranch_single":"work","ranch_pickup":"work"}

func _initialize() -> void: run.call_deferred()

func warp(p: Vector3,id: String) -> Vector3:
	var q:=p
	if id=="sedan_classic":
		# Balanços curtos e uma cabine popular mais alta e vertical. Os eixos e a
		# abertura completa da porta mantêm as posições X/Z.
		if absf(q.z)>1.75: q.z=signf(q.z)*(1.75+(absf(q.z)-1.75)*.68)
		if q.y>.78: q.y=.78+(q.y-.78)*1.14
	elif id=="union_sedan":
		# Perfil tradicional forte de três volumes: deque traseiro horizontal marcado
		# e ombros largos, com a porta dianteira original mantida intacta.
		if q.y>.80 and q.z>.28:
			q.z+=.12*clampf((q.y-.80)/.58,0,1)*clampf((q.z-.28)/.50,0,1)
	elif id=="aurora_executive":
		# Teto formal baixo e cabine traseira superior mais longa. Nenhuma mudança física
		# de entre-eixos ou de direção acompanha o alongamento ótico.
		if q.y>.82:
			var h:=clampf((q.y-.82)/.62,0,1)
			q.y=.82+(q.y-.82)*.86
			if q.z>.30: q.z+=.15*h*clampf((q.z-.30)/.5,0,1)
	elif id=="metro_hatch":
		# Traseira utilitária vertical, longe do vidro traseiro inclinado do hatch esportivo.
		if q.z>.55 and q.y>.86:
			q.z+=.13*clampf((q.y-.86)/.5,0,1)*clampf((q.z-.55)/.4,0,1)
	elif id in ["desert_faisca","desert_faisca_rally"]:
		if q.y>.82:
			var h:=clampf((q.y-.82)/.70,0,1)
			q.y=.82+(q.y-.82)*.89
			if q.z>.4: q.z-=.24*h*clampf((q.z-.4)/.65,0,1)
	return q

func component_root(parents: PackedInt32Array,index: int) -> int:
	while parents[index]!=index: index=parents[index]
	return index

func lamp_mask(part: MeshInstance3D,arrays: Array,role: String,id: String) -> PackedByteArray:
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var mask:=PackedByteArray()
	mask.resize(vertices.size())
	if id!="aurora_executive" or role in ["paint","glass","roof_paint"]: return mask
	# Identifica carcaças de lanterna fechadas e desconectadas dentro do acabamento consolidado.
	# Só as lentes semânticas não bastam: as molduras pretas delas compartilham grandes
	# superfícies da carroceria com detalhes sem relação. A conectividade mantém esses intactos.
	var parents:=PackedInt32Array()
	parents.resize(vertices.size())
	var points:={}
	for i in vertices.size():
		parents[i]=i
		var p:=part.transform*vertices[i]
		var key:=Vector3i(roundi(p.x*10000),roundi(p.y*10000),roundi(p.z*10000))
		if points.has(key): parents[i]=points[key]
		else: points[key]=i
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	var count:=indices.size() if not indices.is_empty() else vertices.size()
	for first in range(0,count,3):
		var a:=indices[first] if not indices.is_empty() else first
		for offset in [1,2]:
			var b: int=indices[first+offset] if not indices.is_empty() else first+offset
			parents[component_root(parents,b)]=component_root(parents,a)
	var components:={}
	for i in vertices.size():
		var key:=component_root(parents,i)
		var p:=part.transform*vertices[i]
		components[key]=(components[key] as AABB).expand(p) if components.has(key) else AABB(p,Vector3.ZERO)
	var selected:={}
	for key in components:
		var box: AABB=components[key]
		var c:=box.get_center()
		if absf(c.z)<2.4 or absf(c.x)<.15 or c.y<.58 or box.size.x>.85 or box.size.y>.35 or box.size.z>.18: continue
		selected[key]=true
		print("AURORA_LAMP_COMPONENT ",role," ",box)
	for i in vertices.size():
		if selected.has(component_root(parents,i)): mask[i]=1
	return mask

func deform(part: MeshInstance3D,id: String) -> void:
	if part.mesh==null or part.has_meta("wheel_center"): return
	var fresh:=ArrayMesh.new()
	for surface in part.mesh.get_surface_count():
		var arrays:=part.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var role: String=ROLES.key(part,surface)
		var lamps:=lamp_mask(part,arrays,role,id)
		var tail_bounds: Dictionary={}
		if ROLES.is_tail_lens(role):
			for p: Vector3 in vertices:
				var v:=part.transform*p
				var side:=signf(v.x)
				tail_bounds[side]=(tail_bounds[side] as AABB).expand(v) if tail_bounds.has(side) else AABB(v,Vector3.ZERO)
		for i in vertices.size():
			var p: Vector3=part.transform*vertices[i]
			var q:=warp(p,id)
			# Mudanças na geometria da lente mantêm o material semântico, o estado
			# e a contagem de superfícies existentes; acabamento sem relação não pode virar emissivo.
			if ROLES.is_tail_lens(role) and id in ["sedan_classic","union_sedan","aurora_executive"]:
				var box: AABB=tail_bounds[signf(p.x)]
				var c:=box.get_center()
				var desired:=Vector2(.14,.23) if id=="sedan_classic" else (Vector2(.43,.12) if id=="union_sedan" else Vector2(.48,.065))
				q.x=c.x+(p.x-c.x)*desired.x/maxf(box.size.x,.001)
				q.y=c.y+(p.y-c.y)*desired.y/maxf(box.size.y,.001)
			if lamps[i]==1:
				var lens:=ROLES.is_tail_lens(role) or ROLES.is_headlight_lens(role) or role in ["lens","indicator"]
				# Mantém a área útil da lente, enquanto assenta a moldura preta alta
				# demais abaixo da borda do deque. As contagens de material/estado/fonte sobrevivem.
				q.y-=.15 if p.z>0 else .14
				if not lens: q.y=(.51 if p.z>0 else .525)+(warp(p,id).y-.66)*.52
				# As lanternas traseiras antigas ficavam acima do deque e à frente da tampa
				# da ponta. Abaixá-las também exige assentar o Z delas na face
				# externa. As lentes ficam 1 cm saltadas do acabamento, livres de cintilação coplanar.
				q.z+=(.075 if lens else .065) if p.z>0 else -.04
			vertices[i]=part.transform.affine_inverse()*q
			if i<normals.size():
				# A diferencial da mesma deformação mantém as normais presas aos
				# painéis transformados sem mudar índices nem suavizar emendas.
				var eps:=.001
				var jac:=Basis((warp(p+Vector3.RIGHT*eps,id)-warp(p-Vector3.RIGHT*eps,id))/(eps*2),(warp(p+Vector3.UP*eps,id)-warp(p-Vector3.UP*eps,id))/(eps*2),(warp(p+Vector3.BACK*eps,id)-warp(p-Vector3.BACK*eps,id))/(eps*2))
				normals[i]=(part.basis.transposed()*jac.inverse().transposed()*part.basis.inverse().transposed()*normals[i]).normalized()
				if lamps[i]==1 and not (ROLES.is_tail_lens(role) or ROLES.is_headlight_lens(role) or role in ["lens","indicator"]):
					normals[i]=(normals[i]/Vector3(1,.52,1)).normalized()
		arrays[Mesh.ARRAY_VERTEX]=vertices
		arrays[Mesh.ARRAY_NORMAL]=normals
		fresh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		fresh.surface_set_material(surface,part.get_active_material(surface))
	part.material_override=null
	for surface in part.get_surface_override_material_count(): part.set_surface_override_material(surface,null)
	part.mesh=fresh
	part.set_meta("batch_ratio",1.0)

func synchronize_role_maps(target: Node3D) -> Dictionary:
	var result:={}
	for part: MeshInstance3D in target.find_children("*","MeshInstance3D",true,false):
		if part.mesh==null: continue
		# bake() grava aqui a ordem final de materiais, mas copia outros aliases de
		# metadados dos nós Body preservados. Os originais utilitários carregam um segundo
		# array utility_surface_material_keys. Reconstrói todo alias a partir da ordem
		# semântica final para que a ordem de busca não escolha um mapa de superfícies obsoleto.
		var canonical: Array=part.get_meta("batch_surface_material_keys",[])
		assert(canonical.size()==part.mesh.get_surface_count())
		for key in part.get_meta_list():
			if str(key).ends_with("surface_material_keys") or str(key).ends_with("surface_material_roles"):
				part.set_meta(key,canonical.duplicate())
		var rows:=[]
		for index in canonical.size():
			var mat:=part.get_active_material(index) as StandardMaterial3D
			rows.append({"surface":index,"role":canonical[index],"material_name":mat.resource_name if mat!=null else "","albedo":mat.albedo_color.to_html() if mat!=null else "","emissive":mat.emission_enabled if mat!=null else false})
		result[str(part.name)]=rows
	return result

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ORIGINALS))
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/current-manifest.json")) if FileAccess.file_exists(OUT+"/current-manifest.json") else {}
	var only:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--id="): only=arg.trim_prefix("--id=")
		if arg.begins_with("--ids="): only=arg.trim_prefix("--ids=")
	for id: String in FAMILIES:
		if not only.is_empty() and id not in only.split(","): continue
		var original_path:=ORIGINALS+"/"+id+".scn"
		# Refaz a autoria a partir da referência imutável mesmo depois da instalação em produção.
		# Rodar de novo nunca pode acumular a deformação de teto/balanço.
		var source_path:=original_path if FileAccess.file_exists(original_path) else "res://assets/fleet/redesigned/"+id+".scn"
		var model: Node3D=(load(source_path) as PackedScene).instantiate()
		if not FileAccess.file_exists(original_path): MESH.save_model(model,original_path)
		var before: Dictionary=MESH.counts(model)
		for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false): deform(part,id)
		var cabin: Dictionary=model.get_meta("vehicle_interior_spec",{}).duplicate(true)
		if not cabin.is_empty():
			var original_roof:=float(cabin.get("roof",1.4))
			var original_belt:=float(cabin.get("belt",.82))
			for key in ["roof","belt","roof_trim_y"]:
				if cabin.has(key): cabin[key]=warp(Vector3(0,float(cabin[key]),0),id).y
			for key in ["rear","rear_top","roof_rear"]:
				if cabin.has(key): cabin[key]=warp(Vector3(0,original_belt if key=="rear" else original_roof,float(cabin[key])),id).z
			model.set_meta("vehicle_interior_spec",cabin)
		if id=="aurora_executive":
			# O chassi vai de Y=.205..275. O carpete da cabine tem .03 de altura e
			# centro em floor-.01. Um calço de 1 cm acima desse deque também mantém a
			# sola real do sapato skinned livre (floor=.30 a deixava em Y=.2699).
			# Herdar o piso genérico de .12 punha o sapato do Dante abaixo do casco.
			cabin["floor"]=.31
			cabin["seat_floor"]=.31
			model.set_meta("vehicle_interior_spec",cabin)
		preload("res://tools/fleet_refresh_20261019/CurrentFleetCraft.gd").new().replace_wheels(model,FAMILIES[id])
		model.set_meta("fleet_refresh_20261019",true)
		model.set_meta("fleet_wheel_family",FAMILIES[id])
		var baked: Node3D=MESH.bake(model,1.0,id)
		var surface_map:=synchronize_role_maps(baked)
		var after: Dictionary=MESH.counts(baked)
		var destination:=OUT+"/"+id+".scn"
		var error:=MESH.save_model(baked,destination)
		report[id]={"before":before,"after":after,"path":destination,"save_error":error,"wheel_family":FAMILIES[id],"surface_map":surface_map}
		print("FLEET_REFRESH ",id," ",JSON.stringify(report[id]))
		baked.free()
		model.free()
	var file:=FileAccess.open(OUT+"/current-manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	quit()
