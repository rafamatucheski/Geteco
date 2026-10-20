@tool
extends EditorScenePostImport
## Pós-importação dos adereços da cidade feitos no Blender (assets/city_props/*.glb).
## Roda só na importação (editor ou --import), nunca durante o jogo, por isso pode ler
## malha de volta com surface_get_arrays.
## - Junta "<Nome>__<ordem>_<camada>" numa malha "<Nome>" com uma superfície por camada,
##   na ordem do nome (a de CityPropKit.LAYERED). Uma malha com dois materiais saía do
##   exportador glTF do Blender 5.2 com a cor da segunda camada toda branca.
## - Tira o material padrão que o importador põe em superfície sem material: quem desenha
##   (kit ou MultiMesh) põe o seu, e assim nenhum material a mais vem junto no pacote.


func _post_import(scene: Node) -> Object:
	var layers := {}
	for node: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		for index in node.mesh.get_surface_count(): node.mesh.surface_set_material(index, null)
		var parts := String(node.name).split("__")
		if parts.size() == 2: layers.get_or_add(parts[0], []).append(node)
	for base: String in layers:
		var nodes: Array = layers[base]
		nodes.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
		var merged := ArrayMesh.new()
		merged.resource_name = base
		for node: MeshInstance3D in nodes:
			# O Blender exporta cada camada na origem, sem transformação de nó.
			merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, node.mesh.surface_get_arrays(0))
		var instance := MeshInstance3D.new()
		instance.name = base
		instance.mesh = merged
		var parent: Node = nodes[0].get_parent()
		parent.add_child(instance)
		instance.owner = scene
		for node: Node in nodes:
			parent.remove_child(node)
			node.free()
	return scene
