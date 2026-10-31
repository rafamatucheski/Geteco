extends "res://scripts/Vehicle.gd"
## Usa a física compartilhada de Vehicle, incluindo engine_disabled, frenagem e dano.
## Colisões de serviço nunca acusam o Dante; controlado significa um veículo ocupado.
func _init() -> void:
	player_damage_attribution = false

func _wreck_expires() -> bool:
	# O comboio aposenta a frota finita fora de vista, incluindo carros destruídos.
	if get_meta("armored_transport", false): return false
	return super._wreck_expires()
