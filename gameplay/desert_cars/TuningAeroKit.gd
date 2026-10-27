extends RefCounted
## Saias laterais, lábio dianteiro e difusor medidos na carroceria real de cada carro.
## Geometria por instância, montada só quando a peça muda; nada roda por quadro.
## As medidas usam um referencial com a traseira em +Z: se as lanternas do modelo
## estiverem em −Z, o kit inteiro gira 180° (as peças são simétricas em X).
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
const WHEEL := preload("res://gameplay/desert_cars/TuningWheelKit.gd")
const ROOF := preload("res://gameplay/desert_cars/TuningSunroof.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
## Mesmas propriedades do aerofólio (cor, aspereza, metal): não cria variante nova de shader.
const CARBON := Color("1b1e22")
const TRIM := Color("262b30")
const ALLOY := Color("a9b1b6")
## Vidro, luzes e forro ficam fora das medidas da carroceria.
const NOT_BODY := ["glass","headlight","tail","indicator","optic_projector","trunk_liner","race_livery"]
const PROFILE_STEP := .025
## Trecho plano mínimo para contar como tampa de porta-malas: a tampa do sedã passa de 1 m;
## o degrau do para-choque atrás da porta de uma perua tem ~25 cm.
const DECK_MIN := .35
var model: Node3D
var wheels: Array = []
var tails: Array = []
var body_materials: Array = []
var nodes := {}
var _styles := {}
var _paint_materials := {}
var _body := {}

func bind(source: Node3D, wheel_groups: Array, tail_rows: Array, painter: RefCounted) -> void:
	model = source
	wheels = wheel_groups
	tails = tail_rows
	if painter != null and painter.get("materials") != null: body_materials = painter.materials

func apply(slot: String, style: String, paint: Color) -> void:
	if style == str(_styles.get(slot,"")):
		for material in _paint_materials.get(slot,[]): material.albedo_color = paint
		return
	_styles[slot] = style
	if is_instance_valid(nodes.get(slot)): nodes[slot].free()
	nodes.erase(slot)
	_paint_materials.erase(slot)
	if style.is_empty(): return
	var measured := body()
	if measured.is_empty(): return
	var began := STALL_WORK.begin()
	var root := Node3D.new()
	root.name = "Tuning"+slot.capitalize().replace(" ","")
	# Referencial com a traseira em +Z; um carro modelado ao contrário gira o kit.
	if float(measured.rear) < 0.0: root.rotation.y = PI
	model.add_child(root)
	nodes[slot] = root
	var paint_material := WHEEL.material(paint,.30,.42)
	_paint_materials[slot] = [paint_material]
	match slot:
		"skirts": _build_skirts(root,style,measured,paint_material)
		"front_lip": _build_lip(root,style,measured,paint_material)
		"diffuser": _build_diffuser(root,style,measured)
	STALL_WORK.finish_slow("tuning_aero_"+slot,began,4000)

## Medidas da carroceria no referencial com traseira em +Z, calculadas uma vez por carro
## (a malha compartilhada da frota não muda com dano: só a cópia local amassa).
## A soleira e o teto vêm da lata pintada; frente e traseira vêm de toda peça opaca,
## porque o para-choque de muitos carros é cinza ou preto e fica abaixo da lata.
func body() -> Dictionary:
	if not _body.is_empty(): return _body
	if wheels.size() < 4: return {}
	var began := STALL_WORK.begin()
	var rear := _rear_sign()
	var front_axle := INF
	var rear_axle := -INF
	var radius := 0.0
	var centre_y := 0.0
	var wheel_hw := 0.0
	for group in wheels:
		var c: Vector3 = group.center
		front_axle = minf(front_axle,c.z*rear)
		rear_axle = maxf(rear_axle,c.z*rear)
		radius += float(group.radius)/wheels.size()
		centre_y += c.y/wheels.size()
		wheel_hw = maxf(wheel_hw,absf(c.x)+float(group.width)*.5)
	var points := PackedVector3Array()
	var solid := PackedVector3Array()
	var profile := {}
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null or part.has_meta("wheel_center") or not part.visible: continue
		if part.name.begins_with("Tuning") or part.name in ["Interior","InteriorAlpha"]: continue
		var xf := ROOF.relative_transform(part,model)
		var original: Mesh = part.get_meta("body_dents_rest_mesh",part.mesh)
		for surface in original.get_surface_count():
			var material := part.get_active_material(surface) as StandardMaterial3D
			if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: continue
			if material.resource_name in NOT_BODY: continue
			var painted: bool = material in body_materials or material.resource_name in ["paint","roof_paint"]
			var arrays := MESH_ARRAYS.arrays_of(original,surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in vertices:
				var p: Vector3 = xf*v
				var q := Vector3(absf(p.x),p.y,p.z*rear)
				solid.append(q)
				if painted: points.append(q)
			if painted: _centreline(profile,vertices,arrays[Mesh.ARRAY_INDEX],xf,rear)
	if points.is_empty(): return {}
	var ground := centre_y-radius
	var sill_hw := 0.0
	var sill_y := INF
	var top := -INF
	for p in points:
		top = maxf(top,p.y)
		if p.z > front_axle+radius*1.15 and p.z < rear_axle-radius*1.15 and p.y < centre_y+radius*.9:
			sill_hw = maxf(sill_hw,p.x)
	for p in points:
		if p.z > front_axle+radius*1.15 and p.z < rear_axle-radius*1.15 and p.x > sill_hw-.12:
			sill_y = minf(sill_y,p.y)
	var nose := INF
	var tail := -INF
	for p in solid:
		# Só a carroceria acima do chão: escapamento e peças de baixo não contam.
		if p.y < ground+.08: continue
		nose = minf(nose,p.z)
		tail = maxf(tail,p.z)
	var nose_y := INF
	var tail_y := INF
	for p in solid:
		if p.y < ground+.08: continue
		if p.z < nose+.30: nose_y = minf(nose_y,p.y)
		if p.z > tail-.30: tail_y = minf(tail_y,p.y)
	var nose_hw := 0.0
	var tail_hw := 0.0
	for p in solid:
		if p.z < nose+.30 and p.y < nose_y+.22: nose_hw = maxf(nose_hw,p.x)
		if p.z > tail-.30 and p.y < tail_y+.22: tail_hw = maxf(tail_hw,p.x)
	if sill_hw <= 0.0 or sill_y == INF: return {}
	_body = {"rear":rear,"front_axle":front_axle,"rear_axle":rear_axle,"radius":radius,"ground":ground,
		"wheel_hw":wheel_hw,"sill_hw":sill_hw,"sill_y":sill_y,"nose":nose,"nose_y":nose_y,"nose_hw":nose_hw,
		"tail":tail,"tail_y":tail_y,"tail_hw":tail_hw,"top":top,"profile":profile,"points":points}
	STALL_WORK.finish_slow("tuning_aero_measure",began,4000)
	return _body

## Perfil do topo da lata na linha de centro (x = 0): faixa de 2,5 cm em Z → maior altura.
func _centreline(profile: Dictionary, vertices: PackedVector3Array, indices: Variant, xf: Transform3D, rear: float) -> void:
	var index: PackedInt32Array = indices if indices != null else PackedInt32Array()
	var count := index.size() if not index.is_empty() else vertices.size()
	for i in range(0,count,3):
		var tri: Array[Vector3] = []
		for j in 3: tri.append(xf*vertices[index[i+j] if not index.is_empty() else i+j])
		var cut: Array[Vector3] = []
		for j in 3:
			var a: Vector3 = tri[j]
			var b: Vector3 = tri[(j+1)%3]
			if (a.x < 0.0) == (b.x < 0.0) or absf(a.x-b.x) < 1e-6: continue
			cut.append(a.lerp(b,-a.x/(b.x-a.x)))
		if cut.size() < 2: continue
		var steps := maxi(1,int(absf(cut[1].z-cut[0].z)/PROFILE_STEP)+1)
		for k in steps+1:
			var p: Vector3 = cut[0].lerp(cut[1],float(k)/steps)
			var bin := int(floor(p.z*rear/PROFILE_STEP))
			profile[bin] = maxf(float(profile.get(bin,-INF)),p.y)

## Onde o aerofólio assenta, no referencial com traseira em +Z. Com tampa de porta-malas
## (um trecho plano de lata abaixo do teto, atrás dele) vai na ponta da tampa; sem tampa
## (hatch, perua, minivan) vai na borda traseira do teto. Não usa a ficha do interior:
## a frota base não tem uma e, no deserto, ela não separava hatch de sedã (auditoria 27/10).
func spoiler_mount() -> Dictionary:
	var b := body()
	if b.is_empty(): return {}
	var profile: Dictionary = b.profile
	var bins: Array = profile.keys()
	bins.sort()
	if bins.is_empty(): return {}
	var roof_y := -INF
	for bin in bins:
		var z: float = (bin+.5)*PROFILE_STEP
		if z > float(b.front_axle) and z < float(b.rear_axle): roof_y = maxf(roof_y,float(profile[bin]))
	var roof_end := -INF
	for bin in bins:
		if float(profile[bin]) >= roof_y-.07: roof_end = maxf(roof_end,(bin+1)*PROFILE_STEP)
	var deck_end := -INF
	var run_start := INF
	var previous := -1000
	for bin in bins:
		var z: float = bin*PROFILE_STEP
		var y := float(profile[bin])
		# Acima da metade da altura do teto: o topo do para-choque de um hatch não é tampa.
		var deck_height: bool = z > roof_end+.05 and y < roof_y-.18 and y > lerpf(float(b.ground),roof_y,.55)
		if deck_height and run_start != INF and bin == previous+1 and absf(y-float(profile[previous])) < .02:
			if (bin+1)*PROFILE_STEP-run_start >= DECK_MIN: deck_end = (bin+1)*PROFILE_STEP
		elif deck_height: run_start = z
		else: run_start = INF
		previous = bin
	var hatch := deck_end == -INF
	var z := roof_end-.05 if hatch else deck_end-.07
	var y := float(profile.get(int(floor(z/PROFILE_STEP)),roof_y if hatch else float(b.top)))
	# Largura da lata na altura de montagem: as hastes e as placas ficam por dentro.
	var half := 0.0
	for p: Vector3 in b.points:
		if absf(p.z-z) < .12 and absf(p.y-y) < .08: half = maxf(half,p.x)
	if half <= .3: half = float(b.sill_hw)*.85
	return {"z":z,"y":y,"half_width":half,"hatch":hatch,"rear":float(b.rear),"roof_y":roof_y}

## Traseira pelas lanternas reais: média de Z das superfícies "tail". Sem lanterna, +Z
## (a frente do Vehicle é −Z).
func _rear_sign() -> float:
	var total := 0.0
	var count := 0
	for row in tails:
		if not is_instance_valid(row.part) or row.part.mesh == null: continue
		var xf := ROOF.relative_transform(row.part,model)
		var vertices: PackedVector3Array = MESH_ARRAYS.arrays_of(row.part.mesh,int(row.surface))[Mesh.ARRAY_VERTEX]
		for v in vertices:
			total += (xf*v).z
			count += 1
	if count == 0: return 1.0
	return -1.0 if total/count < 0.0 else 1.0

func _build_skirts(root: Node3D, style: String, b: Dictionary, paint_material: StandardMaterial3D) -> void:
	var r := float(b.radius)
	var z0 := float(b.front_axle)+r*1.10
	var z1 := float(b.rear_axle)-r*1.10
	if z1-z0 < .45: return
	var floor_y := float(b.ground)+.085
	var x0 := float(b.sill_hw)-.012
	var sill := float(b.sill_y)
	if style == "step":
		# Estribo de utilitário: prancha afastada da soleira, presa por suportes.
		var trim := WHEEL.material(TRIM,.72,.30)
		var tread := WHEEL.material(ALLOY,.36,.78)
		var y := maxf(sill-.10,float(b.ground)+.17)
		for side in [-1.0,1.0]:
			_box(root,Vector3(side*(x0+.10),y,(z0+z1)*.5),Vector3(.17,.04,z1-z0-.10),trim)
			_box(root,Vector3(side*(x0+.10),y+.023,(z0+z1)*.5),Vector3(.13,.008,z1-z0-.18),tread)
			for t in [.18,.5,.82]:
				_box(root,Vector3(side*(x0+.035),(y+sill+.03)*.5,lerpf(z0,z1,t)),Vector3(.05,maxf(.04,sill+.03-y),.05),trim)
		return
	var material := paint_material
	if style == "carbon":
		material = WHEEL.material(CARBON,.30,.42)
		_paint_materials.erase("skirts")
	var top := sill+.05
	var bottom := maxf(sill-(.035 if style == "slim" else .07),floor_y)
	var h := top-bottom
	# Perfil convexo em (para fora, altura); o ponto (0,015, meio) fica dentro dele.
	var profile: Array
	if style == "slim":
		profile = [Vector2(0,top),Vector2(.028,top-.01),Vector2(.034,bottom+.008),Vector2(.026,bottom),Vector2(0,bottom)]
	else:
		profile = [Vector2(0,top),Vector2(.035,top-.012),Vector2(.045,bottom+h*.45),Vector2(.072,bottom+.014),Vector2(.068,bottom),Vector2(0,bottom)]
	var stations := [[z0,.25],[z0+.09,1.0],[z1-.09,1.0],[z1,.25]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0,1.0]: _extrude_side(st,profile,stations,x0,side,Vector3(side*(x0+.015),(top+bottom)*.5,(z0+z1)*.5))
	_commit(root,st,material)
	if style == "vented":
		# Entradas de ar escuras antes da roda traseira.
		var dark := WHEEL.material(TRIM,.62,.30)
		for side in [-1.0,1.0]:
			for i in 3:
				var vent := _box(root,Vector3(side*(x0+.047),bottom+h*.55,z1-.22-i*.075),Vector3(.006,h*.55,.035),dark)
				vent.rotation.x = .35

func _build_lip(root: Node3D, style: String, b: Dictionary, paint_material: StandardMaterial3D) -> void:
	var hw := float(b.nose_hw)*(.90 if style == "sport" else .95)
	if hw < .3: return
	var out := .035 if style == "sport" else .075
	var depth := .20
	var thick := .022 if style == "sport" else .018
	var y := maxf(float(b.nose_y)-.004,float(b.ground)+.07)
	var nose := float(b.nose)
	var material := paint_material
	if style == "splitter":
		material = WHEEL.material(CARBON,.30,.42)
		_paint_materials.erase("front_lip")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A borda dianteira acompanha um nariz arredondado; as pontas recuam.
	var rows: Array = []
	for i in 13:
		var t := float(i)/12.0*2.0-1.0
		var x := t*hw
		var front := nose-out+.12*t*t
		rows.append([x,front])
	for i in rows.size()-1:
		var a: Array = rows[i]
		var c: Array = rows[i+1]
		var corners := [Vector3(a[0],y,a[1]),Vector3(c[0],y,c[1]),Vector3(c[0],y,c[1]+depth),Vector3(a[0],y,a[1]+depth)]
		var lifted := corners.map(func(p: Vector3): return p+Vector3(0,-thick,0))
		var inside := Vector3((a[0]+c[0])*.5,y-thick*.5,(a[1]+c[1])*.5+depth*.5)
		_quad(st,corners[0],corners[1],corners[2],corners[3],inside,0)
		_quad(st,lifted[0],lifted[1],lifted[2],lifted[3],inside,0)
		_quad(st,corners[0],corners[1],lifted[1],lifted[0],inside,0)
		_quad(st,corners[3],corners[2],lifted[2],lifted[3],inside,0)
		if i == 0: _quad(st,corners[0],corners[3],lifted[3],lifted[0],inside)
		if i == rows.size()-2: _quad(st,corners[1],corners[2],lifted[2],lifted[1],inside)
	_commit(root,st,material)
	if style == "splitter":
		for side in [-1.0,1.0]:
			var front := nose-out+.12
			_box(root,Vector3(side*hw,y+.03-thick,front+.08),Vector3(.012,.07,.16),material)

func _build_diffuser(root: Node3D, style: String, b: Dictionary) -> void:
	var hw := float(b.tail_hw)*.78
	if hw < .3: return
	var tail := float(b.tail)
	var y := maxf(float(b.tail_y)+.004,float(b.ground)+.10)
	var material := WHEEL.material(CARBON if style == "race" else TRIM,.32 if style == "race" else .60,.42 if style == "race" else .30)
	var length := .30
	# Placa inclinada: sobe em direção à traseira, como o difusor de verdade.
	var plate := _box(root,Vector3(0,y-.01,tail-length*.5+.015),Vector3(hw*2.0,.018,length),material)
	plate.rotation.x = .16
	var fins := 4 if style == "street" else 6
	var fin_h := .055 if style == "street" else .085
	for i in fins:
		var x := lerpf(-hw*.85,hw*.85,float(i)/float(fins-1))
		var fin := _box(root,Vector3(x,y-.01-fin_h*.5,tail-length*.42),Vector3(.012,fin_h,length*.8),material)
		fin.rotation.x = .16
	if style == "race":
		_box(root,Vector3(0,y-.03,tail-.012),Vector3(.10,.05,.02),WHEEL.material(Color("b3241f"),.40,.20))

## Extruda o perfil (x para fora, y) ao longo de Z; a escala de cada estação afina as pontas.
func _extrude_side(st: SurfaceTool, profile: Array, stations: Array, x0: float, side: float, inside: Vector3) -> void:
	var rings: Array = []
	for station in stations:
		var ring: Array = []
		for p: Vector2 in profile: ring.append(Vector3(side*(x0+p.x*float(station[1])),p.y,float(station[0])))
		rings.append(ring)
	for s in rings.size()-1:
		for i in profile.size()-1:
			_quad(st,rings[s][i],rings[s][i+1],rings[s+1][i+1],rings[s+1][i],inside,2)
	for ring in [rings[0],rings[rings.size()-1]]:
		for i in range(1,ring.size()-1): _triangle(st,ring[0],ring[i],ring[i+1],inside)

## Godot desenha a face da frente em sentido horário: a normal sai do lado oposto a `inside`.
## Numa extrusão, `axis` é o eixo do comprimento: o ponto interno acompanha a face nele,
## senão uma ponta afinada longe do meio poderia virar para dentro.
static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, inside: Vector3, axis := -1) -> void:
	var normal := (b-a).cross(c-a)
	if normal.length_squared() < 1e-12: return
	var centre := (a+b+c)/3.0
	if axis >= 0: inside[axis] = centre[axis]
	if normal.dot(centre-inside) > 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	normal = -normal.normalized()
	for p in [a,b,c]:
		st.set_normal(normal)
		st.add_vertex(p)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3, axis := -1) -> void:
	_triangle(st,a,b,c,inside,axis)
	_triangle(st,a,c,d,inside,axis)

static func _commit(root: Node3D, st: SurfaceTool, material: Material) -> void:
	st.set_material(material)
	var part := MeshInstance3D.new()
	part.mesh = st.commit()
	root.add_child(part)

static func _box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = at
	part.material_override = material
	parent.add_child(part)
	return part
