class_name WeaponCombatHandler
extends Node

## Exemplo de componente para controlar o tiro baseado no inventário
## Adicione no seu Jogador e chame `shoot()`

@export var inventory_manager: InventoryManager

@export_category("Weapon Stats Base")
@export var base_damage: float = 25.0
@export var base_recoil: float = 1.0

func try_shoot() -> void:
	# 1. Checa qual arma está na mão. (Neste exemplo, digamos que ele está com a Primária/Fuzil)
	var primary_weapon = inventory_manager.equipment.slots[0].item_data
	var secondary_weapon = inventory_manager.equipment.slots[1].item_data
	
	# Simulação simples: ele tenta atirar com o que tem na mão.
	# Vamos assumir que a lógica de "qual está na mão" é sua, mas vamos aplicar o Recuo:
	
	var final_recoil = base_recoil
	var can_shoot_heavy = true
	
	# VERIFICA A MALA DE MÃO
	if inventory_manager.has_combat_penalty():
		print("VOCÊ ESTÁ SEGURANDO UMA MALA! Atirando com uma mão só...")
		final_recoil *= 3.0 # Triplica o recuo!
		
		if primary_weapon != null:
			# Impede atirar com Fuzil/Doze segurando a mala
			print("Não é possível usar Fuzil/Escopeta segurando a Mala de Mão! Drope a mala (Q).")
			can_shoot_heavy = false
			return
			
	# Lógica do Tiro Real
	print("POW! Tiro disparado com recuo de: ", final_recoil)
	# ... spawnar bullet, tocar som, etc ...
