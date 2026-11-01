extends RefCounted
## Montagem do anexo da Casa 1, da escada, do porão (alvenaria, estante, caixas, rádio, estante
## secreta, teclado) e da câmera do porão, com o lote de malhas por cor e os materiais. Separado de
## TruckersVillageSecretPassage.gd em 01/11 só para o dono caber na leitura. Os nós montados
## (cellar_root, surface_door, shelf_pivot, tunnel_door, solids...) e os caches (_materials, _batches)
## continuam no dono, porque testes e o próprio dono os leem lá; o dono mantém cada função antiga como
## delegação de uma linha. `g` fica como Node3D, e não como o script do dono, para não criar preload
## cíclico; até as chamadas entre funções deste arquivo passam por `g.`. A ordem das chamadas (e,
## portanto, a dos filhos e dos lotes) é a mesma de antes. Roda uma vez, em configure().

const UNDERGROUND_ENVIRONMENT := preload("res://gameplay/urban_v1/SecretUndergroundEnvironment.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

func _build_annex() -> void:
	var annex := Node3D.new()
	annex.name = "Casa1CellarAnnex"
	g.home.add_child(annex)
	# A extensão parece uma despensa comum vista de fora. Não tem placa, slogan
	# nem interação externa; o único acesso utilizável é de dentro da Casa 1.
	# O centro é o vão real da escada; só ficam duas saliências estreitas nas bordas.
	for side in [-1.0,1.0]:
		g._box(annex,g.ANNEX_CENTER_LOCAL+Vector3(side*1.46,.03,0),Vector3(.23,.06,g.ANNEX_SIZE.z),"75694e")
	for side in [-1.0,1.0]:
		g._solid_box(annex,"AnnexSide",g.ANNEX_CENTER_LOCAL+Vector3(side*g.ANNEX_SIZE.x*.5,1.35,0),Vector3(.18,2.7,g.ANNEX_SIZE.z),"7c735f")
	g._solid_box(annex,"AnnexRear",g.ANNEX_CENTER_LOCAL+Vector3(0,1.35,-g.ANNEX_SIZE.z*.5),Vector3(g.ANNEX_SIZE.x,2.7,.18),"746b59")
	# O madeiramento simples faz o pequeno acréscimo parecer uma despensa antiga e ao
	# mesmo tempo visualmente mais discreto que a fachada da casa.
	for side in [-1.0,1.0]:
		g._batch_box(annex,g.ANNEX_CENTER_LOCAL+Vector3(side*1.47,1.35,-2.54),Vector3(.14,2.55,.12),"544a3d")
		g._batch_box(annex,g.ANNEX_CENTER_LOCAL+Vector3(side*1.47,1.35,2.54),Vector3(.14,2.55,.12),"544a3d")
	for x in [-.95,-.47,0.0,.47,.95]:
		g._batch_box(annex,g.ANNEX_CENTER_LOCAL+Vector3(x,1.35,-2.70),Vector3(.035,2.42,.035),"625746")
	g._box(g.homes.homes[g.HOME_INDEX].roof,g.ANNEX_CENTER_LOCAL+Vector3(0,2.82,0),Vector3(g.ANNEX_SIZE.x+.35,.18,g.ANNEX_SIZE.z+.35),"635c4c",Vector3(.03,0,0))
	g.surface_door = Node3D.new()
	g.surface_door.name = "CellarDoorPivot"
	g.surface_door.position = Vector3(-.08,0,-4.31)
	g.home.add_child(g.surface_door)
	g._box(g.surface_door,Vector3(.73,1.14,.04),Vector3(1.46,2.28,.13),"665845")
	for y in [.38,.76,1.14,1.52,1.90]: g._batch_box(g.surface_door,Vector3(.73,y,.12),Vector3(1.35,.055,.055),"897457")
	for x in [.08,1.38]: g._batch_box(g.surface_door,Vector3(x,1.14,.13),Vector3(.07,2.14,.06),"493d31")
	g._batch_cylinder(g.surface_door,Vector3(1.18,1.10,.18),.055,.055,"aa8952",Vector3(PI*.5,0,0))
	g.surface_door_body = g._solid_box(g.surface_door,"CellarDoor",Vector3(.73,1.14,.04),Vector3(1.46,2.28,.16),"",Vector3.ZERO,false)
	g._build_stair(annex)

func _build_stair(parent: Node3D) -> void:
	var run: float = g.STAIR_BOTTOM_LOCAL.z-g.STAIR_TOP_LOCAL.z
	var drop: float = g.STAIR_TOP_LOCAL.y-g.STAIR_BOTTOM_LOCAL.y
	# O corte do terreno termina logo atrás da porta enquanto a rampa inclinada começa
	# mais para trás. Esta soleira nivelada liga as duas superfícies para que a cápsula do jogador
	# chegue ao topo da rampa em vez de cair contra a tampa frontal íngreme dela.
	# O patamar começa onde a rampa termina (z=-4,75). Começando antes (-4,825), a quina
	# ficava ~5 cm acima da rampa de 41° e prendia a cápsula na subida de volta à casa.
	g._solid_box(parent,"EntryLanding",Vector3(.65,-.08,-4.325),Vector3(1.40,.14,.85),"4a5049")
	for index in 15:
		var weight := float(index)/14.0
		var point: Vector3 = g.STAIR_TOP_LOCAL.lerp(g.STAIR_BOTTOM_LOCAL,weight)
		g._batch_box(parent,point,Vector3(2.55,.18,.46),"4a5049" if index%3 else "545b53")
	var angle := atan2(drop,absf(run))
	var middle: Vector3 = (g.STAIR_TOP_LOCAL+g.STAIR_BOTTOM_LOCAL)*.5+Vector3(0,-.12,0)
	var buried_toe := .30
	var ramp_center := middle-Vector3(0,sin(angle),cos(angle))*buried_toe*.5
	g._solid_box(parent,"CellarStairRamp",ramp_center,Vector3(2.42,.16,Vector2(absf(run),drop).length()+buried_toe),"",Vector3(-angle,0,0),false)
	for side in [-1.0,1.0]:
		g._solid_box(parent,"CellarStairWall",middle+Vector3(side*1.48,1.15,0),Vector3(.18,3.1,5.25),"615d50")

func _build_cellar() -> void:
	g.cellar_root = Node3D.new()
	g.cellar_root.name = "Casa1Cellar"
	g.cellar_root.position = g.CELLAR_ORIGIN_LOCAL
	g.home.add_child(g.cellar_root)
	g._solid_box(g.cellar_root,"CellarFloor",Vector3(0,-.12,0),Vector3(8.9,.22,8.5),"4b5049")
	# Manchas finas de umidade trianguladas seguem a laje sem mudar a altura
	# de caminhada. Contornos irregulares evitam a aparência de tapetes retangulares.
	g._batch_floor_puddle(g.cellar_root,Vector3(-2.75,.002,-2.55),PackedVector2Array([
		Vector2(-.74,-.10),Vector2(-.48,-.27),Vector2(.03,-.23),Vector2(.61,-.13),
		Vector2(.70,.08),Vector2(.28,.24),Vector2(-.22,.20),Vector2(-.66,.10),
	]),"263a38")
	g._batch_floor_puddle(g.cellar_root,Vector3(.10,.002,1.55),PackedVector2Array([
		Vector2(-.92,-.08),Vector2(-.64,-.22),Vector2(-.08,-.18),Vector2(.40,-.25),
		Vector2(.91,-.05),Vector2(.72,.16),Vector2(.18,.21),Vector2(-.34,.14),
		Vector2(-.80,.19),
	]),"263a38")
	g._batch_floor_puddle(g.cellar_root,Vector3(2.85,.002,-.15),PackedVector2Array([
		Vector2(-.53,-.06),Vector2(-.25,-.17),Vector2(.18,-.13),Vector2(.56,.02),
		Vector2(.35,.15),Vector2(-.10,.17),Vector2(-.47,.10),
	]),"263a38")
	for wall in [
		[Vector3(-4.45,1.45,-2.535),Vector3(.30,3.0,3.43)],
		[Vector3(-4.45,1.45,2.685),Vector3(.30,3.0,3.13)],
		[Vector3(-4.45,2.68,.15),Vector3(.30,.54,1.94)],
		[Vector3(4.45,1.45,0),Vector3(.30,3.0,8.5)],
		[Vector3(0,1.45,-4.25),Vector3(8.9,3.0,.30)],
	]:
		g._solid_box(g.cellar_root,"CellarWall",wall[0],wall[1],"",Vector3.ZERO,false)
		# Rebaixa a argamassa atrás das pedras individuais mantendo o
		# envelope físico completo. A argamassa rente antes escondia as faces frontais delas.
		var backing: Vector3 = wall[1]
		if backing.x < .5: backing.x = .20
		elif backing.z < .5: backing.z = .20
		g._box(g.cellar_root,wall[0],backing,"555a51")
	# Colisão frontal completa, recortada só na camada de apresentação.
	g._solid_box(g.cellar_root,"CellarFrontWall",Vector3(0,1.45,4.25),Vector3(8.9,3.0,.30),"",Vector3.ZERO,false)
	g._build_cellar_masonry()
	g.cellar_ceiling = Node3D.new()
	g.cellar_ceiling.name = "CellarCeilingCutaway"
	g.cellar_root.add_child(g.cellar_ceiling)
	g._box(g.cellar_ceiling,Vector3(0,3.06,0),Vector3(9.0,.24,8.6),"393f3b")
	for x in [-3.55,-1.78,0.0,1.78,3.55]:
		g._batch_box(g.cellar_ceiling,Vector3(x,2.88,0),Vector3(.20,.22,8.35),"443e34")
	# Armazenamento esparso e comum faz a sala valer a leitura antes que a estante
	# incomum seja notada. Todo objeto de volume cheio recebe colisão correspondente.
	g._solid_box(g.cellar_root,"StorageRack",Vector3(3.45,.85,-1.7),Vector3(1.35,1.7,3.0),"",Vector3.ZERO,false)
	g._build_storage_rack()
	g._solid_box(g.cellar_root,"CellarCrates",Vector3(2.7,.48,2.75),Vector3(2.1,.96,1.45),"",Vector3.ZERO,false)
	g._build_crate_stack()
	g._solid_box(g.cellar_root,"CellarWorkbench",Vector3(-1.2,.55,3.45),Vector3(2.7,1.1,.9),"",Vector3.ZERO,false)
	g._build_radio_workbench()
	# Uma lâmpada utilitária de curto alcance e sem sombra mantém a escada e a estante legíveis
	# sem acrescentar fontes de luz sobrepostas ao exterior em streaming.
	g._box(g.cellar_root,Vector3(.35,2.88,.25),Vector3(.70,.12,.24),"8a7757")
	var utility_light := OmniLight3D.new()
	utility_light.name = "CellarUtilityLight"
	utility_light.position = Vector3(.35,2.70,.25)
	utility_light.light_color = Color("c7a36d")
	utility_light.light_energy = 2.15
	utility_light.omni_range = 6.2
	utility_light.shadow_enabled = false
	g.cellar_root.add_child(utility_light)
	g._build_cellar_shelf()

func _build_cellar_masonry() -> void:
	# Os colisores de apoio continuam planos; blocos rasos ficam inteiramente dentro
	# do volume deles, então a pedra velha e irregular aparece sem mudar a circulação.
	var stone_colors := ["5d6259","4b514b","66675d","535a52"]
	for row in 5:
		var y := .27+float(row)*.55
		var offset := .48 if row%2 else 0.0
		for column in 9:
			var x := -3.92+float(column)*.98+offset
			if x > 4.05: continue
			var width := .88 if (column+row)%3 else .78
			g._batch_box(g.cellar_root,Vector3(x,y,-4.115),Vector3(width,.46,.025),stone_colors[(column+row*2)%stone_colors.size()])
	for side in [-1.0,1.0]:
		for row in 5:
			var y := .27+float(row)*.55
			for column in 8:
				var z := -3.72+float(column)*1.04+(.50 if row%2 else 0.0)
				if z > 3.85: continue
				if side < 0.0 and z > -.86 and z < 1.16: continue
				g._batch_box(g.cellar_root,Vector3(side*4.305,y,z),Vector3(.025,.46,.92),stone_colors[(column+row+int(side>0.0))%stone_colors.size()])

func _build_storage_rack() -> void:
	var center := Vector3(3.45,0,-1.70)
	for x in [-.54,.54]:
		for z in [-1.32,1.32]:
			g._batch_box(g.cellar_root,center+Vector3(x,.85,z),Vector3(.10,1.70,.10),"53564e")
	for y in [.18,.70,1.22,1.62]:
		g._batch_box(g.cellar_root,center+Vector3(0,y,0),Vector3(1.18,.09,2.82),"81765e")
	for point in [
		Vector3(3.45,.39,-2.55),Vector3(3.45,.91,-1.70),Vector3(3.45,1.43,-.87),
	]:
		g._batch_box(g.cellar_root,point,Vector3(.82,.32,.62),"6d624d")
		g._batch_box(g.cellar_root,point+Vector3(0,.01,.321),Vector3(.70,.06,.025),"9a835c")
	for z in [-2.55,-2.20,-.98,-.63]:
		g._batch_cylinder(g.cellar_root,Vector3(3.45,1.37,z),.105,.28,"657269")

func _build_crate_stack() -> void:
	g._build_crate(Vector3(2.26,.31,2.62),Vector3(.90,.62,1.12),"756047")
	g._build_crate(Vector3(3.20,.28,2.82),Vector3(.82,.56,.94),"68533f")
	g._build_crate(Vector3(2.72,.73,2.72),Vector3(.92,.40,.84),"80694d")

func _build_crate(at: Vector3,size: Vector3,color: String) -> void:
	g._batch_box(g.cellar_root,at,size,color)
	for y in [-.38,.38]:
		g._batch_box(g.cellar_root,at+Vector3(0,y*size.y, size.z*.505),Vector3(size.x*.94,.055,.035),"4c4034")
	for x in [-.42,.42]:
		g._batch_box(g.cellar_root,at+Vector3(x*size.x,0,size.z*.505),Vector3(.055,size.y*.86,.035),"4c4034")

func _build_radio_workbench() -> void:
	var center := Vector3(-1.20,0,3.45)
	g._batch_box(g.cellar_root,center+Vector3(0,.86,0),Vector3(2.70,.16,.90),"806b4e")
	for x in [-1.12,1.12]:
		for z in [-.32,.32]:
			g._batch_box(g.cellar_root,center+Vector3(x,.42,z),Vector3(.13,.84,.13),"564637")
	g._batch_box(g.cellar_root,center+Vector3(0,.62,-.37),Vector3(2.48,.16,.12),"5d4d3b")
	# Box, tuning glass, grille, knobs and aerial form one readable field radio.
	var radio := center+Vector3(-.34,1.13,0)
	g._batch_box(g.cellar_root,radio,Vector3(1.12,.46,.42),"303735")
	g._batch_box(g.cellar_root,radio+Vector3(-.24,.06,.222),Vector3(.44,.22,.025),"404b46")
	for x in [-.40,-.30,-.20,-.10]:
		g._batch_box(g.cellar_root,radio+Vector3(x,.06,.239),Vector3(.022,.18,.018),"788077")
	g._batch_box(g.cellar_root,radio+Vector3(.28,.10,.239),Vector3(.34,.10,.018),"b49457")
	for x in [.18,.38]: g._batch_cylinder(g.cellar_root,radio+Vector3(x,-.10,.244),.055,.035,"aa8952",Vector3(PI*.5,0,0))
	g._batch_cylinder(g.cellar_root,radio+Vector3(.43,.57,-.10),.018,.78,"777b70",Vector3(0,0,-.15))
	g._batch_box(g.cellar_root,center+Vector3(.78,.98,.06),Vector3(.56,.025,.42),"b5aa8b",Vector3(0,-.10,0))

func _build_cellar_shelf() -> void:
	# A estante fica na parede oeste do porão, longe do patamar da escada. O
	# conteúdo dela é só geometria; não há rótulos explicativos.
	g.shelf_pivot = Node3D.new()
	g.shelf_pivot.name = "SecretShelfPivot"
	# Dobradiças opostas deixam o caminho livre quando os dois painéis estão abertos.
	g.shelf_pivot.position = Vector3(-4.12,0,1.12)
	g.cellar_root.add_child(g.shelf_pivot)
	g._batch_box(g.shelf_pivot,Vector3(.11,1.18,-.97),Vector3(.28,2.36,1.94),"514536")
	for z in [.055,1.885]: g._batch_box(g.shelf_pivot,Vector3(.31,1.18,-z),Vector3(.34,2.36,.11),"756047")
	for y in [.06,2.30]: g._batch_box(g.shelf_pivot,Vector3(.31,y,-.97),Vector3(.38,.14,2.08),"806a4b")
	for y in [.32,.78,1.24,1.70,2.16]: g._batch_box(g.shelf_pivot,Vector3(.34,y,-.97),Vector3(.38,.08,1.82),"8d7653")
	var book_colors := ["704b3e","53665c","887252","4a5961","755d68","9a8259"]
	var book_widths := [.11,.14,.09,.16,.12,.10,.15,.08,.13,.11]
	for row in 4:
		var base_y := .36+float(row)*.46
		var z := .14
		for index in book_widths.size():
			var width: float = book_widths[(index+row*2)%book_widths.size()]
			var height := .27+float((index+row)%4)*.025
			var tilt := -.045 if index%5==0 else (.035 if index%4==0 else 0.0)
			g._batch_box(g.shelf_pivot,Vector3(.50,base_y+height*.5,-z-width*.5),Vector3(.24,height,width),book_colors[(index+row)%book_colors.size()],Vector3(-tilt,0,0))
			z += width+.026
			if z > 1.78: break
	g.shelf_body = g._solid_box(g.shelf_pivot,"SecretBookshelf",Vector3(.18,1.18,-.97),Vector3(.46,2.36,1.94),"",Vector3.ZERO,false)
	g.tunnel_door = Node3D.new()
	g.tunnel_door.name = "TunnelDoorPivot"
	g.tunnel_door.position = Vector3(-4.27,0,-.82)
	g.cellar_root.add_child(g.tunnel_door)
	g._batch_box(g.tunnel_door,Vector3(.06,1.18,.97),Vector3(.16,2.36,1.94),"343c3a")
	for y in [.28,.78,1.28,1.78,2.22]: g._batch_box(g.tunnel_door,Vector3(.15,y,.97),Vector3(.08,.07,1.78),"6f746b")
	for z in [.14,1.80]: g._batch_box(g.tunnel_door,Vector3(.15,1.18,z),Vector3(.08,2.18,.08),"6f746b")
	for y in [.30,2.05]:
		for z in [.18,1.76]: g._batch_cylinder(g.tunnel_door,Vector3(.205,y,z),.035,.025,"9b8254",Vector3(0,0,PI*.5))
	g.tunnel_door_body = g._solid_box(g.tunnel_door,"TunnelDoor",Vector3(.06,1.18,.97),Vector3(.18,2.36,1.94),"",Vector3.ZERO,false)
	# Teclado numérico funcional: dez teclas pequenas e dois controles, sem texto decorativo.
	g._box(g.cellar_root,g.KEYPAD_CENTER,Vector3(.18,.78,.56),"303937")
	g._batch_box(g.cellar_root,g.KEYPAD_CENTER+Vector3(.105,.31,0),Vector3(.025,.11,.40),"607d66")
	for row in 4:
		for column in 3:
			g._batch_box(g.cellar_root,g.KEYPAD_CENTER+Vector3(.105,.17-float(row)*.125,-.17+float(column)*.17),Vector3(.025,.075,.075),"8b8f7f")

func _build_camera() -> void:
	g.cellar_camera = Camera3D.new()
	g.cellar_camera.name = "Casa1CellarCamera"
	g.cellar_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	g.cellar_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	g.cellar_camera.size = 10.8
	g.cellar_camera.near = .12
	g.cellar_camera.far = 45.0
	g.cellar_camera.cull_mask = g.UNDERGROUND_LAYER
	UNDERGROUND_ENVIRONMENT.apply_to(g.cellar_camera)
	g.cellar_root.add_child(g.cellar_camera)
	g._update_cellar_camera(g._cellar_global(Vector3.ZERO))

func _batch_floor_puddle(parent: Node3D,center: Vector3,outline: PackedVector2Array,color: String) -> void:
	if outline.size() < 3: return
	var key := "%s/%s"%[parent.get_instance_id(),color]
	if not g._batches.has(key):
		var created := SurfaceTool.new()
		created.begin(Mesh.PRIMITIVE_TRIANGLES)
		g._batches[key] = {"surface":created,"parent":parent,"color":color}
	var surface: SurfaceTool = g._batches[key].surface
	for index in outline.size():
		var current := outline[index]
		var next := outline[(index+1)%outline.size()]
		for vertex in [
			center,
			center+Vector3(current.x,0,current.y),
			center+Vector3(next.x,0,next.y),
		]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(vertex)

func _batch_box(parent: Node3D,at: Vector3,size: Vector3,color: String,angles := Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	g._batch_mesh(parent,mesh,at,color,angles)

func _batch_cylinder(parent: Node3D,at: Vector3,radius: float,height: float,color: String,angles := Vector3.ZERO) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	g._batch_mesh(parent,mesh,at,color,angles)

func _batch_mesh(parent: Node3D,mesh: Mesh,at: Vector3,color: String,angles: Vector3) -> void:
	var key := "%s/%s"%[parent.get_instance_id(),color]
	if not g._batches.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		g._batches[key] = {"surface":surface,"parent":parent,"color":color}
	g._batches[key].surface.append_from(mesh,0,Transform3D(Basis.from_euler(angles),at))

func _flush_batches() -> void:
	for batch in g._batches.values():
		var node := MeshInstance3D.new()
		node.name = "CellarDetailBatch"
		node.mesh = batch.surface.commit()
		node.material_override = g._material(batch.color)
		batch.parent.add_child(node)
	g._batches.clear()

func _solid_box(parent: Node3D,id: String,at: Vector3,size: Vector3,color: String,angles := Vector3.ZERO,with_visual := true) -> StaticBody3D:
	if with_visual and not color.is_empty(): g._box(parent,at,size,color,angles)
	var body := StaticBody3D.new()
	body.name = id
	body.position = at
	body.rotation = angles
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("interior_solid_id","truckers_home_1_secret/"+id)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	g.solids.append(body)
	return body

func _box(parent: Node3D,at: Vector3,size: Vector3,color: String,angles := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.rotation = angles
	node.material_override = g._material(color)
	parent.add_child(node)
	return node

func _material(color: String) -> StandardMaterial3D:
	if not g._materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(color)
		material.roughness = .91
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		if color in ["303735","303937","343c3a","53564e","6f746b","777b70","788077","8b8f7f"]:
			material.metallic = .62
			material.roughness = .54
		elif color in ["aa8952","9b8254","b49457"]:
			material.metallic = .78
			material.roughness = .38
		elif color in ["5d6259","4b514b","66675d","535a52","555a51","4b5049"]:
			material.roughness = .98
		elif color == "263a38":
			material.roughness = .24
			material.metallic = .05
		elif color == "607d66":
			material.emission_enabled = true
			material.emission = Color("395a44")
			material.emission_energy_multiplier = .55
		g._materials[color] = material
	return g._materials[color]

func _apply_underground_layer(root: Node) -> void:
	for node in root.find_children("*","GeometryInstance3D",true,false):
		node.layers = g.UNDERGROUND_LAYER
	for light in root.find_children("*","Light3D",true,false):
		light.layers = g.UNDERGROUND_LAYER
		light.light_cull_mask = g.UNDERGROUND_LAYER

func _enable_player_underground_layer() -> void:
	if g.session == null or not is_instance_valid(g.session.world.player): return
	for node in g.session.world.player.find_children("*","GeometryInstance3D",true,false):
		node.layers |= g.UNDERGROUND_LAYER
