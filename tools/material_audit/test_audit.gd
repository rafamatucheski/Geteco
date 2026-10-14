extends "res://tools/material_audit/audit.gd"
## Contratos de leitura: distinguir equivalência visual de identidade mutável.
var failures := 0
var checks := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		push_error("Teste exige --no-save.")
		quit(1)
		return
	var first := StandardMaterial3D.new()
	first.albedo_color = Color(.2, .3, .4)
	var copy := first.duplicate() as StandardMaterial3D
	expect(first != copy and signatures(first).exact == signatures(copy).exact, "Duplicatas exatas têm IDs distintos e assinatura igual.")
	copy.albedo_color = Color(.4, .3, .2)
	expect(signatures(first).exact != signatures(copy).exact and signatures(first).color == signatures(copy).color, "Variação de cor mantém apenas grupo de cor.")
	expect(signatures(first).roughness != signatures(copy).roughness, "Cor diferente não entra em grupo de rugosidade.")
	copy.albedo_color = first.albedo_color
	copy.roughness = .3
	expect(signatures(first).roughness == signatures(copy).roughness and signatures(first).exact != signatures(copy).exact, "Rugosidade não é duplicata exata.")
	copy.roughness = first.roughness
	copy.metallic = .2
	expect(signatures(first).scalar == signatures(copy).scalar and signatures(first).roughness != signatures(copy).roughness, "Escalar metálico é agrupado sem confundir rugosidade.")
	copy.metallic = first.metallic
	copy.cull_mode = BaseMaterial3D.CULL_DISABLED
	expect(signatures(first).scalar != signatures(copy).scalar, "Culling não pode ser ignorado como escalar.")
	copy.cull_mode = first.cull_mode
	copy.uv1_scale = Vector3(2, 1, 1)
	expect(signatures(first).scalar != signatures(copy).scalar, "UV distinto permanece separado.")
	copy.uv1_scale = first.uv1_scale
	copy.set_meta("city_window", true)
	expect(signatures(first).exact != signatures(copy).exact, "Metadados de papel fazem parte da assinatura.")
	copy.remove_meta("city_window")
	copy.next_pass = StandardMaterial3D.new()
	expect(signatures(first).exact != signatures(copy).exact, "Next pass faz parte da assinatura.")
	copy.next_pass = null
	var pixels := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.RED)
	first.albedo_texture = ImageTexture.create_from_image(pixels)
	copy.albedo_texture = ImageTexture.create_from_image(pixels)
	expect(signatures(first).exact == signatures(copy).exact, "Texturas com IDs distintos e pixels iguais são reconhecidas.")
	pixels.set_pixel(0, 0, Color.BLUE)
	copy.albedo_texture = ImageTexture.create_from_image(pixels)
	expect(signatures(first).color != signatures(copy).color, "Textura diferente não é variação apenas de cor.")
	var shader := Shader.new()
	shader.code = "shader_type spatial; uniform float tint = 1.0; void fragment(){ ALBEDO = vec3(tint); }"
	var shader_a := ShaderMaterial.new()
	shader_a.shader = shader
	shader_a.set_shader_parameter("tint", .2)
	var shader_b := shader_a.duplicate() as ShaderMaterial
	shader_b.set_shader_parameter("tint", .7)
	expect(signatures(shader_a).exact != signatures(shader_b).exact and signatures(shader_a).scalar == signatures(shader_b).scalar, "Uniforme escalar difere apenas no grupo escalar.")
	CITY.set_night(0.0)
	var daylight: String = signatures(CITY.window_lit(0)).exact
	CITY.set_night(1.0)
	expect(daylight != signatures(CITY.window_lit(0)).exact, "Material de janela registra alteração noturna sem perder identidade.")
	var chunk := Node3D.new()
	root.add_child(chunk)
	var source := StandardMaterial3D.new()
	source.albedo_color = Color(.1, .2, .3)
	var duplicate := source.duplicate() as StandardMaterial3D
	var overlay := StandardMaterial3D.new()
	overlay.albedo_color = Color.GREEN
	var pass_material := StandardMaterial3D.new()
	pass_material.albedo_color = Color.BLUE
	overlay.next_pass = pass_material
	var visual := MeshInstance3D.new()
	visual.mesh = BoxMesh.new()
	visual.material_override = source
	visual.material_overlay = overlay
	chunk.add_child(visual)
	var instanced := MultiMeshInstance3D.new()
	instanced.multimesh = MultiMesh.new()
	instanced.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	instanced.multimesh.mesh = BoxMesh.new()
	instanced.multimesh.mesh.surface_set_material(0, duplicate)
	instanced.multimesh.instance_count = 1
	chunk.add_child(instanced)
	var before: String = signatures(source).exact
	var snapshot := inspect_chunk(chunk)
	expect(snapshot.distinct_materials == 4, "Malha, MultiMesh, overlay e next_pass contam quatro instâncias.")
	expect(snapshot.exact_extra_instances == 1 and snapshot.exact_top20.size() == 1, "Top de duplicados exatos reconhece só o par idêntico.")
	expect(snapshot.color_top20.size() == 1 and snapshot.color_top20[0].exact_variants == 2 and snapshot.color_top20[0].instances == 3, "Grupo de cor exclui o overlay com next_pass próprio.")
	expect(visual.material_override == source and instanced.multimesh.mesh.surface_get_material(0) == duplicate and signatures(source).exact == before, "Auditoria não modifica materiais nem referências.")
	chunk.free()
	print("AUDITORIA_TESTE verificações=%d falhas=%d" % [checks, failures])
	quit(1 if failures else 0)
