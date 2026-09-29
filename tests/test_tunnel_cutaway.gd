extends SceneTree
## Corte da cidade sobre o Túnel do canal (`TunnelCutaway`), em cena sintética: o que tapa
## o tubo (laje, prédio entre a câmera e o túnel, Northstar sobre o canal, letreiros) vira
## quase transparente; o resto não é tocado; ao sair tudo volta ao material, sombra e cor
## originais. Não mede aparência: ver `tests/canal_tunnel/capture_canal_tunnel.gd`.
## Uso: "$GODOT" --path . --script res://tests/test_tunnel_cutaway.gd
const CUTAWAY := preload("res://world/urban_detail/TunnelCutaway.gd")
const TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func box(parent: Node, id: String, center: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = id
	instance.mesh = mesh
	instance.material_override = material
	instance.position = center
	parent.add_child(instance)
	return instance

func paint(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material

func run() -> void:
	var chunk := Node3D.new()
	root.add_child(chunk)
	var opaque := paint(Color(0.5, 0.5, 0.5))
	var glassy := paint(Color(0.6, 0.9, 0.95, 0.4))
	var shader_material := ShaderMaterial.new()
	var building := box(chunk, "Predio", Vector3(190, 6, 75), Vector3(10, 12, 10), opaque)
	var far_building := box(chunk, "Longe", Vector3(190, 6, 140), Vector3(10, 12, 10), opaque)
	var deck := box(chunk, "Laje", Vector3(190, 0.0, 63), Vector3(20, 0.1, 40), opaque)
	var road_far := box(chunk, "RuaRampa", Vector3(160, 0.0, 63), Vector3(10, 0.1, 40), opaque)
	var tinted := box(chunk, "Vidraca", Vector3(185, 6, 70), Vector3(4, 10, 4), glassy)
	var shaded := box(chunk, "Agua", Vector3(195, 6, 70), Vector3(4, 10, 4), shader_material)
	var label := Label3D.new()
	label.name = "Letreiro"
	label.position = Vector3(200, 6, 70)
	label.modulate = Color(1, 0.9, 0.5, 1)
	chunk.add_child(label)
	var tunnel := Node3D.new()
	tunnel.name = "CanalTunnel"
	tunnel.add_to_group("canal_tunnel")
	chunk.add_child(tunnel)
	var ceiling := box(tunnel, "CanalTunnelBatch_ceiling", Vector3(190, -0.17, 63), Vector3(20, 0.35, 8.4), opaque)
	var steel := box(tunnel, "CanalTunnelBatch_steel", Vector3(190, -3.0, 63), Vector3(20, 5, 0.3), opaque)
	# Uma malha com dois materiais: cada superfície ganha a sua cópia.
	var two := ArrayMesh.new()
	for surface in 2:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)])
		two.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		two.surface_set_material(surface, paint(Color(0.2 + surface * 0.4, 0.3, 0.3)))
	var pair := MeshInstance3D.new()
	pair.name = "DuasFaces"
	pair.mesh = two
	pair.position = Vector3(205, 3, 70)
	pair.scale = Vector3(4, 4, 4)
	chunk.add_child(pair)
	var pair_originals: Array[Material] = [two.surface_get_material(0), two.surface_get_material(1)]
	await process_frame

	var cutaway := CUTAWAY.new()
	var focus := Vector3(190, -5.5, 63)
	var to_camera := Vector3(0, 33.6, 12.2)
	var chunks: Array = [chunk]

	# Fora do túnel: nada muda.
	cutaway.update(chunks, focus, to_camera, 30.0, 0.0, 0.1)
	check(cutaway.faded_count() == 0, "Fora do túnel nenhum nó é apagado")
	check(building.material_override == opaque, "Fora do túnel o material é o original")

	cutaway.update(chunks, focus, to_camera, 30.0, 1.0, 0.1)
	check(building.material_override != opaque and building.material_override is StandardMaterial3D, "Prédio entre a câmera e o túnel recebe cópia com alfa")
	check(absf((building.material_override as StandardMaterial3D).albedo_color.a - CUTAWAY.MIN_ALPHA) < 0.001, "Alfa cheio do corte é MIN_ALPHA")
	check((building.material_override as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "Cópia usa mistura por alfa")
	check(building.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Apagado não projeta sombra no tubo")
	check(opaque.albedo_color.a == 1.0 and opaque.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "O material original não é alterado")
	check(deck.material_override != opaque, "Laje sobre o trecho coberto é apagada")
	check(ceiling.material_override != opaque, "Teto do trecho coberto é apagado")
	check(steel.material_override == opaque, "Outras peças do túnel não são apagadas")
	check(far_building.material_override == opaque, "Prédio fora da linha de visada fica opaco")
	check(road_far.material_override == opaque, "Chão da rampa aberta fica opaco (revelaria o vazio)")
	check(shaded.material_override == shader_material, "ShaderMaterial não é tocado")
	check((tinted.material_override as StandardMaterial3D).albedo_color.a < 0.4 * CUTAWAY.MIN_ALPHA + 0.001, "Vidro já translúcido multiplica o alfa")
	check(deck.material_override == building.material_override, "Nós de mesmo material dividem uma cópia")
	check(label.modulate.a < 0.2 and label.modulate.r == 1.0, "Letreiro perde alfa e mantém a cor")
	check(pair.get_surface_override_material(0) != null and pair.get_surface_override_material(1) != null and pair.get_surface_override_material(0) != pair.get_surface_override_material(1), "Cada superfície ganha a sua cópia")

	# Meio caminho: alfa intermediário.
	cutaway.update(chunks, focus, to_camera, 30.0, 0.5, 0.1)
	var middle := (building.material_override as StandardMaterial3D).albedo_color.a
	check(middle > CUTAWAY.MIN_ALPHA + 0.1 and middle < 0.9, "Força 0,5 dá alfa intermediário (%.2f)" % middle)

	# Foco longe do trecho: a laje sai da janela e volta ao normal, sem esperar a saída total.
	cutaway.update(chunks, Vector3(400, -5.5, 63), to_camera, 30.0, 1.0, 1.0)
	check(deck.material_override == opaque and building.material_override == opaque, "Fora da janela em X os nós voltam ao normal")

	cutaway.update(chunks, focus, to_camera, 30.0, 1.0, 1.0)
	check(deck.material_override != opaque, "Volta ao entrar na janela")
	cutaway.update(chunks, focus, to_camera, 30.0, 0.0, 0.1)
	check(cutaway.faded_count() == 0, "Ao sair tudo é solto")
	check(building.material_override == opaque and deck.material_override == opaque and ceiling.material_override == opaque, "Materiais originais restaurados")
	check(building.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "Sombra restaurada")
	check(label.modulate == Color(1, 0.9, 0.5, 1), "Cor do letreiro restaurada")
	check(pair.get_surface_override_material(0) == null and pair.get_surface_override_material(1) == null, "Sem sobreposição de superfície depois de restaurar")
	check(two.surface_get_material(0) == pair_originals[0] and two.surface_get_material(1) == pair_originals[1], "Materiais da malha intactos")

	# Nó liberado durante o corte não quebra a restauração.
	cutaway.update(chunks, focus, to_camera, 30.0, 1.0, 1.0)
	building.free()
	cutaway.release()
	check(cutaway.faded_count() == 0, "Liberar com nó já destruído não falha")

	chunk.queue_free()
	await process_frame
	if failures.is_empty():
		print("TUNNEL_CUTAWAY_OK")
		quit(0)
	else:
		print("TUNNEL_CUTAWAY_FALHOU ", failures.size())
		quit(1)
