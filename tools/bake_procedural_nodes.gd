extends SceneTree

## Congela conteúdo desenhado por código (@tool _ready()) em nós de verdade,
## salvos no .tscn e arrastáveis no editor 2D -- sem reescrever à mão as
## centenas de coordenadas que hoje vivem em Vector2 literais dentro dos
## scripts. Uso:
##
##   godot --path . --script res://tools/bake_procedural_nodes.gd -- \
##       scene=res://world/harbor/HarborPreview.tscn nodes=District,Waterfront
##
## Para cada nó em "nodes" (caminho relativo à raiz da cena):
##   1. Espera a cena assentar (alguns sistemas usam call_deferred).
##   2. Marca owner=raiz nos filhos DIRETOS que ainda não têm dono (conteúdo
##      criado em _ready() nunca ganha owner sozinho, por isso não é salvo
##      por padrão) -- de propósito RASO, só um nível. Ver comentário de
##      _claim_ownership() abaixo para o porquê.
##   3. Se o nó tiver a propriedade "baked_from_editor", liga ela -- é o sinal
##      que os scripts (HarborDistrict.gd etc.) usam para não recriar o
##      conteúdo por cima na próxima vez que a cena abrir.
## Repacota a cena inteira e sobrescreve o mesmo .tscn.
##
## Não é reversível por si só: rode com um checkpoint de git limpo.

var _target_paths: Array[String] = []
var _scene_path := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("scene="):
			_scene_path = arg.substr("scene=".length())
		elif arg.begins_with("nodes="):
			for piece in arg.substr("nodes=".length()).split(","):
				if not piece.is_empty():
					_target_paths.append(piece)
	if _scene_path.is_empty() or _target_paths.is_empty():
		push_error("BAKE: uso: -- scene=res://... nodes=Caminho1,Caminho2")
		quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(_scene_path)
	if packed == null:
		push_error("BAKE: não consegui carregar %s" % _scene_path)
		quit(1)
		return
	var root := packed.instantiate()
	get_root().add_child(root)
	# Vários sistemas do Harbor usam call_deferred/await process_frame em
	# _ready() (StreetLamp<->weather, ligações de trilho, etc.). Dar folga
	# real garante que a árvore esteja no estado final antes de congelar.
	for _frame in 8:
		await process_frame

	var total_newly_owned := 0
	var flagged_baked: Array[String] = []
	for rel_path in _target_paths:
		var target := root.get_node_or_null(NodePath(rel_path))
		if target == null:
			push_error("BAKE: nó não encontrado: %s" % rel_path)
			continue
		total_newly_owned += _claim_ownership(target, root)
		if "baked_from_editor" in target:
			target.set("baked_from_editor", true)
			flagged_baked.append(rel_path)
		else:
			push_warning("BAKE: %s não tem baked_from_editor -- pode recriar conteúdo por cima no próximo load" % rel_path)

	var new_packed := PackedScene.new()
	var pack_error := new_packed.pack(root)
	if pack_error != OK:
		push_error("BAKE: pack() falhou com erro %d" % pack_error)
		quit(1)
		return
	var save_error := ResourceSaver.save(new_packed, _scene_path)
	if save_error != OK:
		push_error("BAKE: ResourceSaver.save() falhou com erro %d" % save_error)
		quit(1)
		return

	print("BAKE_RESULT scene=%s nodes=%s newly_owned=%d flagged_baked=%s" % [
		_scene_path, ",".join(_target_paths), total_newly_owned, ",".join(flagged_baked)
	])
	quit(0)


## Grupos que ficam de fora inteiramente: sinaliza conteúdo cujo _ready()
## depende de entrar na árvore "ao vivo", um nó de cada vez (ex.:
## MountainPine3D compartilha um SubViewport 3D via get_parent().add_child()
## síncrono, que o Godot recusa quando o nó já nasce dentro de uma subárvore
## pré-montada em bloco). Ver comentário de _build_memorial_trees() em
## HarborDistrict.gd.
const SKIP_GROUPS := ["memorial_verge_tree"]


## Congela até o primeiro nó com script PRÓPRIO, e para aí -- nunca desce
## dentro dele. A regra: um nó com script é responsável por reconstruir os
## PRÓPRIOS filhos (solid de colisão, sprite 3D renderizado, zona de oclusão)
## do zero em todo _ready(), congelado ou não -- é assim que já funciona hoje
## (ver ProceduralBuilding._build_geodata(), StreetLamp._build_lamp_post()).
## Descer nele salvaria uma cópia obsoleta que ninguém recria (SubViewport,
## referência não-exportada em ExteriorOcclusion.gd e caminho de
## ViewportTexture não sobrevivem a save/load fora da árvore onde nasceram --
## foi o que quebrou numa versão anterior desta ferramenta).
## Um nó SEM script (StaticBody2D+CollisionShape2D de uma colisão, um
## Node2D container puro) é só estrutura morta -- ninguém mais vai recriá-lo,
## então precisa descer e congelar a subárvore inteira, ou a forma "oca"
## (corpo sem colisão) fica salva.
## Retorna quantos nós ganharam dono agora (métrica de conferência -- se vier
## 0, o alvo já estava congelado ou está vazio).
func _claim_ownership(node: Node, root: Node) -> int:
	var claimed := 0
	for child in node.get_children():
		var skip := false
		for skip_group in SKIP_GROUPS:
			if child.is_in_group(skip_group):
				skip = true
				break
		if skip:
			continue
		if child.owner == null:
			child.owner = root
			claimed += 1
		if child.get_script() == null:
			claimed += _claim_ownership(child, root)
	return claimed
