extends "res://tools/fleet_fixups/PassengerDesign.gd"
## Model-specific editions retain their original cabins, liveries and wheelbase.
var target_id := ""

func split_front_lenses(target: Node3D) -> void:
	# Estes dois exports legados põem os dois faróis numa só superfície. O equipamento
	# define o lado pelos limites da superfície, então um centro compartilhado produzia um facho só.
	# Separa os triângulos reais offline sem mudar topologia nem materiais.
	var roles:=preload("res://runtime/VehicleSurfaceRoles.gd")
	for part: MeshInstance3D in target.find_children("*","MeshInstance3D",true,false):
		if part.mesh==null or part.has_meta("wheel_center"): continue
		var changed:=false
		var retained:=ArrayMesh.new()
		var retained_roles: Array[String]=[]
		for surface in part.mesh.get_surface_count():
			var key: String=roles.key(part,surface)
			var arrays:=part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var bounds:=AABB(part.transform*vertices[0],Vector3.ZERO)
			for vertex: Vector3 in vertices: bounds=bounds.expand(part.transform*vertex)
			var material:=part.get_active_material(surface)
			if "headlight" not in key or bounds.position.x>=-.05 or bounds.end.x<=.05:
				retained.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
				retained.surface_set_material(retained.get_surface_count()-1,material)
				retained_roles.append(key)
				continue
			var tools_by_side:={}
			for side in [-1,1]:
				var st:=SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				st.set_material(material)
				tools_by_side[side]=st
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
			var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
			var total:=indices.size() if not indices.is_empty() else vertices.size()
			for start in range(0,total,3):
				var triangle_indices: Array[int]=[]
				var x:=0.0
				for offset in 3:
					var index:=indices[start+offset] if not indices.is_empty() else start+offset
					triangle_indices.append(index)
					x+=(part.transform*vertices[index]).x
				var st: SurfaceTool=tools_by_side[-1 if x<0 else 1]
				for index in triangle_indices:
					st.set_normal(normals[index])
					if not uvs.is_empty(): st.set_uv(uvs[index])
					if not colors.is_empty(): st.set_color(colors[index])
					st.add_vertex(vertices[index])
			for side in [-1,1]:
				var st: SurfaceTool=tools_by_side[side]
				st.index()
				var lens:=MeshInstance3D.new()
				lens.name=str(part.name)+("_HeadlightL" if side<0 else "_HeadlightR")
				lens.transform=part.transform
				lens.mesh=st.commit()
				lens.set_meta("batch_surface_material_keys",[key])
				lens.set_meta("batch_ratio",1.0)
				part.get_parent().add_child(lens)
			changed=true
		if not changed: continue
		if retained.get_surface_count()==0: part.free()
		else:
			for surface in part.get_surface_override_material_count(): part.set_surface_override_material(surface,null)
			part.material_override=null
			part.mesh=retained
			for key in part.get_meta_list():
				if str(key).ends_with("surface_material_keys") or str(key).ends_with("surface_material_roles"): part.remove_meta(key)
			part.set_meta("batch_surface_material_keys",retained_roles)
	print("SPECIAL_HEADLIGHT_SURFACES_SPLIT ",target_id)

func details(id: String,half: Vector3,bc: Vector3,wheels: Dictionary) -> void:
	var saved_profile := profile
	profile=profile.duplicate()
	# Um sedã não herda as barras de teto de uma perua. Mantém o novo detalhamento
	# dentro dos para-choques existentes em vez de pendurar entradas de ar além de uma traseira arredondada.
	if profile.style in ["touring","touring_sport","cross"]: profile.style="gt"
	if target_id=="supra_a80": profile.style="supercar"
	super.details("cobra_v8",half,bc,wheels)
	profile=saved_profile
	active="PassengerDetails"
	var front := bc.z-half.z+.05
	var rear := bc.z+half.z-.06
	var trim := Color(profile.accent)
	var sportive := target_id in ["desert_mirage","desert_mirage_gt","supra_a80","jessica_jetta_gli","rauhz_focus_mk1","desert_faisca_rally"]
	if sportive:
		# Aerodinâmica inferior apoiada, dutos de freio e um difusor definem o conjunto esportivo.
		for side in [-1.0,1.0]:
			box("detail",Vector3(side*half.x*.79,.24,front+.09),Vector3(.13,.045,.25),DARK)
			box("detail",Vector3(side*half.x*.79,.268,front+.08),Vector3(.11,.014,.22),trim)
	if target_id in ["desert_coyote","desert_coyote_drag","cobra_boss_ironback"]:
		# Vintage muscle identity: paired deep lower intakes and satin bumpers.
		for side in [-1.0,1.0]:
			var at := Vector3(side*half.x*.67,.47,front-.01)
			ring("detail",at,Vector3.RIGHT,Vector3.UP,.078,.060,Vector3.FORWARD,trim,14)
			ring("detail",at+Vector3(0,0,.007),Vector3.RIGHT,Vector3.UP,.060,0,Vector3.FORWARD,DARK,14)
	if target_id in ["desert_bison","digo_amarok_2014"]:
		# Protetor de cárter embutido e estribos integrados, longe das portas.
		box("detail",Vector3(0,.29,front+.055),Vector3(half.x*1.12,.15,.04),METAL)
		for x in [-.3,0.0,.3]: box("detail",Vector3(x,.30,front+.031),Vector3(.1,.026,.01),DARK)
		for side in [-1.0,1.0]:
			box("detail",Vector3(side*(half.x-.15),.27,0),Vector3(.16,.06,1.55),METAL)
			for j in 7: box("detail",Vector3(side*(half.x-.15),.305,-.6+j*.2),Vector3(.13,.007,.04),DARK)
	if target_id in ["desert_faisca","desert_siroco","digo_gol_1993"]:
		# Detalhamento urbano modesto com uma faixa clara abaixo dos vidros.
		for side in [-1.0,1.0]:
			box("detail",Vector3(side*half.x*.87,.40,.0),Vector3(.025,.026,half.z*.75),trim)
	if target_id=="desert_faisca_rally":
		# Pequenos olhais de reboque de metal em vez de nós extras ou luzes dinâmicas.
		for z in [front,rear]:
			ring("detail",Vector3(-half.x*.34,.32,z),Vector3.RIGHT,Vector3.UP,.063,.040,Vector3.FORWARD if z==front else Vector3.BACK,Color("cd5e36"),12)
