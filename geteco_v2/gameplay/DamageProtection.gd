extends RefCounted
## Proteção de alvos que nunca podem sofrer dano (Maciota e o mecânico). O corpo que recebe o
## golpe costuma ser filho do personagem marcado (`ResidentBody`), então vale a marca no próprio
## nó ou em QUALQUER ancestral. Um único critério para todo caminho de dano direto:
## `Gameplay._damage`, `Actor.receive_damage` e a colisão de `Vehicle`.
const META := "invulnerable"

static func is_protected(target: Object) -> bool:
	var node := target as Node
	while is_instance_valid(node):
		if node.get_meta(META, false) == true: return true
		node = node.get_parent()
	return false
