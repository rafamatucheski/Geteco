extends SceneTree
## Regenere com Godot 4.7.2 .NET --headless --script neste arquivo.
## O importer/bake_mesh público do Terrain3D exporta o ladrilho. As regiões de apoio são
## recortadas. Nenhum nó nativo do Terrain3D fica retido pelo jogo rodando.
const ORIGIN := Vector2(704,-448)
func _initialize() -> void: call_deferred("run")

func run() -> void:
	if not ClassDB.can_instantiate("Terrain3D"): push_error("Terrain3D not installed"); quit(1); return
	var definition = preload("res://world/editing/EditableRegion.gd").new()
	definition.region_id = "mountain"
	definition.prepare_data()
	var source = definition.terrain
	var terrain: Node3D = ClassDB.instantiate("Terrain3D")
	root.add_child(terrain)
	terrain.get("collision").set("mode",0)
	terrain.set("region_size",64)
	var heights := Image.create(128,128,false,Image.FORMAT_RF)
	for z in 128:
		for x in 128:
			heights.set_pixel(x,z,Color(source.surface_height_at(ORIGIN+Vector2(x,z)),0,0,1))
	var maps: Array[Image] = [heights,null,null]
	terrain.get("data").call("import_images",maps,Vector3(ORIGIN.x,0,ORIGIN.y),0.0,1.0)
	var baked: Mesh = terrain.call("bake_mesh",0,0)
	if baked == null: push_error("Terrain3D bake failed"); quit(1); return
	var exported := {}
	for v in baked.get_faces():
		if v.x>=704 and v.x<=768 and v.z>=-448 and v.z<=-384:
			exported[Vector2i(roundi(v.x),roundi(v.z))] = v
	# O Terrain3D alterna as diagonais. Combina com a diagonal do colisor existente
	# sem mudar as posições de vértice exportadas nem as amostras de altura.
	var faces := PackedVector3Array()
	for z in range(-448,-384):
		for x in range(704,768):
			for key in [Vector2i(x,z),Vector2i(x+1,z),Vector2i(x,z+1),Vector2i(x+1,z),Vector2i(x+1,z+1),Vector2i(x,z+1)]:
				if not exported.has(key): push_error("Missing Terrain3D export vertex"); quit(1); return
				faces.append(exported[key])
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var triangle_count := faces.size()/3
	for i in range(0,faces.size(),3):
		for j in 3:
			var v: Vector3 = faces[i+j]
			var p := Vector2(v.x,v.z)
			var grid := (p/4.0).floor()*4.0
			var f := (p-grid)/4.0
			var ns: Array[Vector3] = []
			for offset in [Vector2.ZERO,Vector2(4,0),Vector2(0,4),Vector2(4,4)]:
				var at: Vector2 = grid+offset
				ns.append(Vector3(source.height_at(at-Vector2.RIGHT)-source.height_at(at+Vector2.RIGHT),2.0,source.height_at(at-Vector2.DOWN)-source.height_at(at+Vector2.DOWN)).normalized())
			var n: Vector3 = ns[0]+(ns[1]-ns[0])*f.x+(ns[2]-ns[0])*f.y if f.x+f.y<=1 else ns[3]+(ns[2]-ns[3])*(1-f.x)+(ns[1]-ns[3])*(1-f.y)
			builder.set_normal(n)
			var snow := 1.0-smoothstep(-1500.0,-1200.0,v.z*16.0+4960.0)
			builder.set_color(Color("52634a").lerp(Color("72766b"),clampf(v.y/7.5,0,1)).lerp(Color("d2d9d9"),snow))
			builder.add_vertex(v)
	builder.index()
	var mesh := builder.commit()
	var signature := PackedFloat32Array()
	for z in 17:
		for x in 17: signature.append(source.height_at(ORIGIN+Vector2(x,z)*4.0))
	mesh.set_meta("native_grid_heights",signature)
	mesh.set_meta("generator","Terrain3D 1.0.2 / bake_mesh(0, HEIGHT_FILTER_NEAREST)")
	mesh.set_meta("triangle_count",triangle_count)
	var folder := "res://world/regions/terrain3d_pilot"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var err := ResourceSaver.save(mesh,folder.path_join("terminal_mesh.res"))
	print("TERRAIN3D_BAKED triangles=",triangle_count," error=",err)
	terrain.free()
	definition.free()
	quit(0 if err==OK and triangle_count>0 else 1)
