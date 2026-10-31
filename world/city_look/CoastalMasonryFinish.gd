extends RefCounted
## Acabamento local e fosco para as caixas de parede autoradas da Polícia. Dois mapas
## compartilhados são montados uma vez; variação de tom fica de fora do campo de relevo de propósito.
const SURFACES := preload("res://assets/urban_detail/UrbanSurfaces.gd")
const MAP_SIZE := 256
const WALL_COLOR := Color("4f6878")
static var _wall_material: StandardMaterial3D

static func decorate(building: UrbanBuildingBase) -> void:
	if building.building_id != "Police" or not is_instance_valid(building.visuals_root): return
	var root := building.visuals_root
	var body := root.get_node_or_null("PrecinctBody") as MeshInstance3D
	var wing := root.get_node_or_null("PrecinctFrontWing") as MeshInstance3D
	var vestibule := root.get_node_or_null("PrecinctVestibuleSide") as MeshInstance3D
	# Só filhos diretos: nunca alcança interiores nem o mobiliário de fachada separado.
	# add_solid_box repete nomes de ala/vestíbulo. O Godot pode dar à segunda caixa
	# um nome anônimo, então identifica também as dimensões autoradas espelhadas exatas.
	for child in root.get_children():
		var wall := child as MeshInstance3D
		if wall == null or not wall.mesh is BoxMesh: continue
		if wall == body or _same_wall_pair(wall, wing) or _same_wall_pair(wall, vestibule):
			wall.material_override = _material()

static func _same_wall_pair(candidate: MeshInstance3D, source: MeshInstance3D) -> bool:
	if source == null or not source.mesh is BoxMesh: return false
	if candidate == source: return true
	var mirrored := Vector3(-source.position.x, source.position.y, source.position.z)
	return candidate.position.is_equal_approx(mirrored) \
		and (candidate.mesh as BoxMesh).size.is_equal_approx((source.mesh as BoxMesh).size)

static func _material() -> StandardMaterial3D:
	if _wall_material != null: return _wall_material
	var albedo := Image.create_empty(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGB8)
	var heights := PackedFloat32Array()
	heights.resize(MAP_SIZE * MAP_SIZE)
	var tint_rng := RandomNumberGenerator.new()
	tint_rng.seed = 73041
	var relief_rng := RandomNumberGenerator.new()
	relief_rng.seed = 91327
	for y in MAP_SIZE:
		for x in MAP_SIZE:
			# Repetição de 4m, painéis de 2m por 1.33m. Distância periódica e
			# perfis suaves evitam emenda dura na borda da textura.
			var dx := float(mini(x % 128, 128 - x % 128))
			var panel_y := fposmod(float(y), float(MAP_SIZE)/3.0)
			var dy := minf(panel_y, float(MAP_SIZE)/3.0-panel_y)
			var joint := 1.0 - smoothstep(0.0, 2.5, minf(dx, dy))
			var panel_index := int(x / 128.0) + int(float(y)*3.0/MAP_SIZE)*2
			var panel_tone: float = [-.025,.02,.035,-.015,-.035,.015][panel_index]
			var u := TAU * float(x) / float(MAP_SIZE)
			var v := TAU * float(y) / float(MAP_SIZE)
			var tone := 1.0 + .014 * sin(u + .7) * cos(v - .4) \
				+ .008 * sin(2.0 * u - v) + tint_rng.randf_range(-.012, .012)
			# Mantém a separação dos painéis legível na escala do jogo; o primeiro teste
			# de 7% sumia depois da minificação. Sem luz direcional embutida.
			var tint := WALL_COLOR * (tone + float(panel_tone) - joint * .22)
			tint.a = 1.0
			albedo.set_pixel(x, y, tint)
			# Só agregado fino e juntas rebaixadas afetam as normais;
			# manchas amplas de cor ficam planas, evitando nódoas em relevo.
			heights[y * MAP_SIZE + x] = .5 - joint * .08 + relief_rng.randf_range(-.006, .006)
	albedo.generate_mipmaps()
	var material := StandardMaterial3D.new()
	material.resource_name = "CoastalPoliceMatteMasonry"
	material.albedo_color = Color.WHITE
	material.albedo_texture = ImageTexture.create_from_image(albedo)
	material.normal_enabled = true
	material.normal_texture = SURFACES.normal_from_height(heights, MAP_SIZE, 2.0)
	material.normal_scale = .75
	material.roughness = .92
	material.metallic = 0.0
	material.metallic_specular = .16
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / 4.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_wall_material = material
	return _wall_material
