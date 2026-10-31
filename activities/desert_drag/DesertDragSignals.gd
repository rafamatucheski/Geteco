extends Node3D
## One multimesh finish stripe and a physical starting tree. No dynamic lights.
var lenses: Array[StandardMaterial3D] = []
var _phase := -2

func configure(start: Vector3, forward: Vector3, distance: float) -> void:
	var right := forward.cross(Vector3.UP).normalized()
	var tree := Node3D.new()
	tree.position = start+right*6.2
	add_child(tree)
	var pole := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = .07
	cylinder.bottom_radius = .07
	cylinder.height = 2.8
	pole.mesh = cylinder
	pole.position.y = 1.4
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("383b39")
	pole.material_override = metal
	tree.add_child(pole)
	for i in 3:
		var lamp := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = .18
		sphere.height = .36
		lamp.mesh = sphere
		lamp.position.y = 2.65-float(i)*.46
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("252a25")
		material.emission_enabled = true
		material.emission = Color.BLACK
		lamp.material_override = material
		lenses.append(material)
		tree.add_child(lamp)
	# A chegada escrita de 800 m já pertence ao deserto em streaming. Evita
	# uma segunda faixa quase coplanar que piscaria sob a câmera lateral.
	if is_equal_approx(distance,800.0):
		set_countdown(3)
		return
	var stripe := MultiMeshInstance3D.new()
	var cells := MultiMesh.new()
	cells.transform_format = MultiMesh.TRANSFORM_3D
	cells.use_colors = true
	var block := BoxMesh.new()
	block.size = Vector3(.55,.012,.5)
	cells.mesh = block
	cells.instance_count = 36
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.roughness = .95
	stripe.material_override = paint
	stripe.multimesh = cells
	stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var orientation := Basis.looking_at(forward,Vector3.UP)
	# No referencial da pista, o X local cruza as faixas e o -Z local aponta para frente.
	block.size = Vector3(.5,.012,.55)
	for row in 2:
		for column in 18:
			var i := row*18+column
			var point := start+forward*(distance+float(row)*.55)+right*(-4.25+float(column)*.5)
			point.y = start.y-.047
			cells.set_instance_transform(i,Transform3D(orientation,point))
			cells.set_instance_color(i,Color("e6deca") if (row+column)%2==0 else Color("272a2a"))
	add_child(stripe)
	set_countdown(3)

func set_countdown(seconds: float) -> void:
	var phase := 2 if seconds<=0 else (1 if seconds<=1 else 0)
	if phase==_phase: return
	_phase = phase
	for i in lenses.size():
		var color: Color = [Color("eb6145"),Color("f5bd47"),Color("70ec86")][i]
		lenses[i].albedo_color = color if i==phase else Color("252a25")
		lenses[i].emission = color*1.2 if i==phase else Color.BLACK
