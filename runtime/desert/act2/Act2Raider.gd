extends "res://gameplay/CobraAgent.gd"
## Cobras do ataque final: mesmos agentes dos foras-da-lei (DesertWilds.Outlaw), sempre engajados.
## Era a classe interna VicenteReunion.Raider até 01/11; a VicenteReunion reexporta com o mesmo nome.

func _ready() -> void:
	super._ready()
	add_to_group("act2_raiders")
	set_meta("region_id", "desert")
	set_meta("character_name", "Cobra")
