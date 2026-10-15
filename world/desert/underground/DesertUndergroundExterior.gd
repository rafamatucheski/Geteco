extends Node3D
## Parte de fora das entradas subterrâneas do deserto. Cada tipo tem uma cara própria, nada de tampa de ferro de rua:
##  - "culvert": boca de concreto de uma galeria sob a rodovia, com grade enferrujada e placa de enchente.
##  - "well": poço de pedra de Santa Lua, tampa de madeira, polia, balde e fitas de oração.
##  - "cellar": alçapão duplo de madeira nos fundos do motel, com sacos de areia e uma lamparina.
##  - "vent": poço de ventilação da mina, chapa de aço, torre do ventilador e listras de aviso.
## `open_amount` abre/desliza a tampa ou as folhas; `descent` é lido pela `SewerHatchDescent`.
var kind := "well"
var site_id := ""
var descent: Dictionary = {}
var _leaf_a: Node3D
var _leaf_b: Node3D
var _lid: Node3D
var _palette: Dictionary = {}
var open_amount := 0.0:
	set(value):
		open_amount = clampf(value, 0.0, 1.0)
		_apply_open()

func setup(site: Dictionary) -> void:
	kind = str(site.kind)
	site_id = str(site.id)
	name = site_id
	descent = site.descent.duplicate(true)

func set_open_amount(value: float) -> void:
	open_amount = value

func _ready() -> void:
	match kind:
		"culvert": _build_culvert()
		"well": _build_well()
		"cellar": _build_cellar()
		"vent": _build_vent()
	_apply_open()

func _apply_open() -> void:
	match kind:
		"well", "vent":
			if is_instance_valid(_lid): _lid.position.x = -1.5 * open_amount
		"cellar":
			if is_instance_valid(_leaf_a): _leaf_a.rotation.z = -open_amount * 1.45
			if is_instance_valid(_leaf_b): _leaf_b.rotation.z = open_amount * 1.45
		"culvert":
			if is_instance_valid(_leaf_a): _leaf_a.rotation.y = open_amount * 1.35

func _mat(color: String, metal := false, glow := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color, metal, glow]
	if not _palette.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(color)
		material.roughness = 0.6 if metal else 0.95
		material.metallic = 0.4 if metal else 0.0
		if glow > 0.0:
			material.emission_enabled = true
			material.emission = Color(color)
			material.emission_energy_multiplier = glow
		_palette[key] = material
	return _palette[key]

func _box(parent: Node3D, at: Vector3, size: Vector3, color: String, solid := false, metal := false, glow := 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _mat(color, metal, glow)
	instance.position = at
	parent.add_child(instance)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		body.position = at
		parent.add_child(body)
	return instance

func _cyl(parent: Node3D, at: Vector3, radius: float, height: float, color: String, solid := false, metal := false, glow := 0.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 14
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _mat(color, metal, glow)
	instance.position = at
	parent.add_child(instance)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = radius
		cylinder.height = height
		shape.shape = cylinder
		body.add_child(shape)
		body.position = at
		parent.add_child(body)
	return instance

func _lantern(at: Vector3, color := "#ffb25a", energy := 1.4) -> void:
	_box(self, at, Vector3(0.14, 0.2, 0.14), "#2a2622", false, true)
	_box(self, at + Vector3(0, 0.0, 0), Vector3(0.09, 0.12, 0.09), color, false, false, 2.0)
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = Color(color)
	light.light_energy = energy
	light.omni_range = 4.5
	light.shadow_enabled = false
	add_child(light)

# --- Galeria da rodovia: boca de concreto no talude, voltada para o sul, e o leito seco à frente. ---
func _build_culvert() -> void:
	var concrete := "#a69d88"
	var dark := "#3a342b"
	# Talude de terra batida atrás da boca e cabeceira de concreto com a abertura de 2,6 x 2,1 m.
	# Recessed throat: the old solid embankment filled the doorway itself.
	_box(self, Vector3(0, 1.5, -4.4), Vector3(14.0, 3.0, 2.0), "#8c7653", true)
	for side in [-1.0, 1.0]:
		_box(self, Vector3(side*2.5, 1.5, -2.0), Vector3(2.4, 3.0, 2.8), "#8c7653", true)
		_box(self, Vector3(side*1.42, 1.2, -1.8), Vector3(.24, 2.4, 3.0), concrete, true)
	_box(self, Vector3(0, 2.5, -1.8), Vector3(2.6, .3, 3.0), concrete, true)
	_box(self, Vector3(0, .025, -1.6), Vector3(2.6, .05, 3.6), "#71644f")
	_box(self, Vector3(-2.4, 1.4, -0.4), Vector3(2.2, 2.8, 0.7), concrete, true)
	_box(self, Vector3(2.4, 1.4, -0.4), Vector3(2.2, 2.8, 0.7), concrete, true)
	_box(self, Vector3(0, 2.45, -0.4), Vector3(2.8, 0.7, 0.7), concrete, true)
	_box(self, Vector3(0, 0.03, -0.4), Vector3(2.6, 0.06, 0.8), dark)
	for side in [-1.0, 1.0]:
		var wing := _box(self, Vector3(side * 4.4, 0.9, 0.9), Vector3(0.6, 1.8, 3.4), concrete, true)
		wing.rotation.y = side * -0.5
		# Mesh and collider must share the authored wing rotation.
		get_child(get_child_count()-1).rotation.y = wing.rotation.y
	# Marca d'água das enchentes na cabeceira, rachaduras e lama seca na frente.
	for side in [-1.0, 1.0]:
		_box(self, Vector3(side*2.35, 1.2, -.03), Vector3(2.05, .12, .02), "#6e5a3c")
		for seam in 4:
			_box(self, Vector3(side*2.35, .45+seam*.55, -.035), Vector3(2.05, .022, .025), "#837964")
		for bolt_y in [.35, 1.8]:
			_cyl(self, Vector3(side*1.4, bolt_y, .07), .06, .06, "#413b32", false, true).rotation.x = PI*.5
	_box(self, Vector3(0, 0.02, 3.0), Vector3(9.0, 0.02, 7.0), "#9a8460")
	for index in 9:
		var crack := _box(self, Vector3(-3.6 + index * 0.9, 0.04, 1.2 + (index % 3) * 1.2), Vector3(0.9, 0.01, 0.05), "#5e4c33")
		crack.rotation.y = index * 0.7
	# Grade de ferro enferrujada, que gira para abrir.
	_leaf_a = Node3D.new()
	_leaf_a.position = Vector3(-1.3, 0, 0.1)
	add_child(_leaf_a)
	for bar in 7: _box(_leaf_a, Vector3(0.2 + bar * 0.38, 1.05, 0.0), Vector3(0.06, 2.1, 0.06), "#6a3d22", false, true)
	_box(_leaf_a, Vector3(1.3, 0.1, 0.0), Vector3(2.6, 0.08, 0.08), "#6a3d22", false, true)
	_box(_leaf_a, Vector3(1.3, 2.0, 0.0), Vector3(2.6, 0.08, 0.08), "#6a3d22", false, true)
	_box(_leaf_a, Vector3(1.3, .85, 0), Vector3(2.6, .07, .09), "#493c30", false, true)
	_box(_leaf_a, Vector3(2.25, 1.1, .08), Vector3(.12, .3, .12), "#322e28", false, true)
	var gate_body := StaticBody3D.new()
	gate_body.name = "CulvertGate"
	gate_body.collision_layer = 1
	gate_body.collision_mask = 0
	var gate_shape := CollisionShape3D.new()
	var gate_box := BoxShape3D.new()
	gate_box.size = Vector3(2.6, 2.1, .1)
	gate_shape.shape = gate_box
	gate_shape.position = Vector3(1.3, 1.05, 0)
	gate_body.add_child(gate_shape)
	_leaf_a.add_child(gate_body)
	# Placa de perigo e pedras soltas.
	_box(self, Vector3(5.6, 1.1, 2.4), Vector3(0.1, 2.2, 0.1), "#4a3a28")
	_box(self, Vector3(5.6, 2.0, 2.4), Vector3(1.2, 0.8, 0.06), "#c9a12a")
	_box(self, Vector3(5.6, 2.0, 2.43), Vector3(1.0, 0.6, 0.03), "#2a1f10")
	for index in 7:
		var rock := _box(self, Vector3(-4.0 + index * 1.4, 0.2, 2.8 + (index % 2) * 1.0), Vector3(0.5 + (index % 3) * 0.2, 0.4, 0.5), "#7a6a52")
		rock.rotation = Vector3(0.2, index * 1.1, 0.1)
	_box(self, Vector3(3.6, 0.35, 0.8), Vector3(2.0, 0.7, 1.3), "#b9a079")

# --- Poço de Santa Lua: poço de pedra seca com tampa de tábuas, polia e fitas de oração. ---
func _build_well() -> void:
	var stone := "#9a8a6e"
	_cyl(self, Vector3(0, 0.025, 0), 1.12, 0.05, "#050403")
	for index in 14:
		var angle := TAU * float(index) / 14.0
		var block := _box(self, Vector3(cos(angle) * 1.15, 0.2, sin(angle) * 1.15), Vector3(0.5, 0.4, 0.34), stone if index % 3 else "#8a7a5e")
		block.rotation.y = -angle
	# Tampa de tábuas que desliza, com argola de ferro.
	_lid = Node3D.new()
	add_child(_lid)
	_cyl(_lid, Vector3(0, 0.1, 0), 0.98, 0.1, "#6b4d30")
	for plank in 5: _box(_lid, Vector3(-0.8 + plank * 0.4, 0.17, 0), Vector3(0.05, 0.02, 1.8), "#4a3320")
	_cyl(_lid, Vector3(0, 0.2, 0), 0.12, 0.04, "#2a2622", false, true).rotation.x = PI * 0.5
	var lid_body := StaticBody3D.new()
	lid_body.collision_layer = 1
	lid_body.collision_mask = 0
	var lid_shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	# Menor que a tampa desenhada (0,98 m): a descida leva o Dante até a borda a
	# 0,95 m do centro com move_and_collide, e com o raio cheio a tampa o barrava a
	# 1,25 m; a entrada "Entrar" abortava sem descer (auditoria de portas, 15/10).
	cylinder.radius = 0.6
	cylinder.height = 0.1
	lid_shape.shape = cylinder
	lid_body.add_child(lid_shape)
	lid_body.position = Vector3(0, 0.1, 0)
	_lid.add_child(lid_body)
	# Armação de madeira com polia e balde, sem colisão no centro.
	for side in [-1.0, 1.0]: _box(self, Vector3(side * 1.55, 1.1, -0.9), Vector3(0.14, 2.2, 0.14), "#5a4128", true)
	_box(self, Vector3(0, 2.15, -0.9), Vector3(3.3, 0.14, 0.14), "#5a4128")
	_cyl(self, Vector3(0, 1.95, -0.9), 0.2, 0.1, "#2a2622", false, true).rotation.x = PI * 0.5
	_box(self, Vector3(0.9, 1.0, -0.9), Vector3(0.02, 1.9, 0.02), "#cfc2a0")
	_cyl(self, Vector3(0.9, 0.2, -0.9), 0.17, 0.3, "#6a6a5e", false, true)
	# Fitas de oração e uma lua entalhada na pedra.
	for index in 5:
		var ribbon := _box(self, Vector3(-1.4 + index * 0.7, 1.85 - (index % 2) * 0.1, -0.9), Vector3(0.1, 0.5, 0.01), ["#a8362a", "#e0b43a", "#3a6aa8", "#e8e1cf", "#7a3a8a"][index])
		ribbon.rotation.z = (index - 2) * 0.05
	_cyl(self, Vector3(1.4, 0.45, 0.7), 0.3, 0.05, "#d8cfae", false, false, 0.6).rotation.x = PI * 0.5
	_lantern(Vector3(-1.25, 0.55, 0.9))

# --- Adega do Horizonte: alçapão duplo de madeira nos fundos do motel (as folhas giram para abrir). ---
func _build_cellar() -> void:
	_box(self, Vector3(0, 0.02, 0), Vector3(2.0, 0.04, 2.8), "#060504")
	for side in [-1.0, 1.0]:
		_box(self, Vector3(side * 1.1, 0.12, 0), Vector3(0.2, 0.24, 3.0), "#7a6a52", true)
	_box(self, Vector3(0, 0.12, 1.5), Vector3(2.4, 0.24, 0.2), "#7a6a52")
	_leaf_a = Node3D.new()
	_leaf_a.position = Vector3(-1.0, 0.2, 0)
	add_child(_leaf_a)
	_leaf_b = Node3D.new()
	_leaf_b.position = Vector3(1.0, 0.2, 0)
	add_child(_leaf_b)
	for leaf in [_leaf_a, _leaf_b]:
		var direction := 1.0 if leaf == _leaf_a else -1.0
		_box(leaf, Vector3(direction * 0.5, 0.0, 0), Vector3(1.0, 0.08, 2.8), "#5a4128")
		for slat in 4: _box(leaf, Vector3(direction * 0.5, 0.05, -1.05 + slat * 0.7), Vector3(0.96, 0.02, 0.06), "#3a2a18")
		_box(leaf, Vector3(direction * 0.9, 0.06, 0), Vector3(0.1, 0.06, 0.12), "#2a2622", false, true)
	# Sacos de areia, caixas de garrafas e uma lamparina ao lado da porta.
	for index in 4:
		_box(self, Vector3(-2.2 + index * 0.45, 0.12 + (index % 2) * 0.2, 1.9), Vector3(0.5, 0.22, 0.28), "#b9a079", index % 2 == 0)
	_box(self, Vector3(2.5, 0.3, 0.6), Vector3(0.9, 0.6, 0.7), "#6e5236", true)
	for index in 3: _cyl(self, Vector3(2.3 + index * 0.18, 0.7, 0.6), 0.05, 0.22, ["#3a5a3e", "#6a5020", "#41596a"][index])
	_lantern(Vector3(-2.0, 0.55, 0.3), "#ff8f3a", 1.2)

# --- Poço 3 da Serra Bruta: chapa de aço sobre o poço, torre do ventilador e fitas de aviso. ---
func _build_vent() -> void:
	_box(self, Vector3(0, 0.03, 0), Vector3(1.5, 0.06, 1.5), "#050403")
	_box(self, Vector3(0, 0.05, 0), Vector3(1.8, 0.1, 1.8), "#3a362f", false, true)
	for side in [-1.0, 1.0]:
		_box(self, Vector3(side * 0.95, 0.1, 0), Vector3(0.12, 0.2, 1.9), "#8a7a2a")
	_lid = Node3D.new()
	add_child(_lid)
	_box(_lid, Vector3(0, 0.12, 0), Vector3(1.5, 0.08, 1.5), "#5a564a", false, true)
	for stripe in 6: _box(_lid, Vector3(-0.6 + stripe * 0.24, 0.17, 0), Vector3(0.1, 0.01, 1.5), "#c9a12a" if stripe % 2 == 0 else "#2a2622")
	var lid_body := StaticBody3D.new()
	lid_body.collision_layer = 1
	lid_body.collision_mask = 0
	var lid_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 0.08, 1.5)
	lid_shape.shape = box
	lid_body.add_child(lid_shape)
	lid_body.position = Vector3(0, 0.12, 0)
	_lid.add_child(lid_body)
	# Torre do ventilador (de lado, sólida), duto torto e caixa de ferramentas.
	_box(self, Vector3(3.0, 2.2, -1.4), Vector3(2.0, 4.4, 2.0), "#6e665a", true, true)
	_cyl(self, Vector3(3.0, 4.6, -1.4), 1.2, 0.5, "#4a463e", false, true)
	for blade in 4:
		var fan := _box(self, Vector3(3.0, 4.9, -1.4), Vector3(2.0, 0.04, 0.22), "#2a2622", false, true)
		fan.rotation.y = blade * PI * 0.25
	for index in 4: _box(self, Vector3(1.6 + index * 0.5, 1.0 - index * 0.15, -1.4), Vector3(0.5, 0.18, 0.18), "#5a564a", false, true)
	_box(self, Vector3(-2.0, 0.3, 0.8), Vector3(0.9, 0.6, 0.5), "#8a2a1f", true)
	for post in [Vector2(-2.6, -1.2), Vector2(-2.6, 1.6), Vector2(2.2, 1.6)]: _box(self, Vector3(post.x, 0.5, post.y), Vector3(0.1, 1.0, 0.1), "#8a7a2a")
	_box(self, Vector3(-2.6, 0.95, 0.2), Vector3(0.03, 0.12, 2.8), "#c9a12a")
	_lantern(Vector3(1.6, 0.5, 1.4), "#9fd6ff", 1.0)
