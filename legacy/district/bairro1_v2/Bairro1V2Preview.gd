class_name Bairro1V2Preview
extends Node2D

## Cena de avaliação isolada. Nunca é carregada por Main.tscn; serve para
## caminhar pelo bairro novo e aprovar escala, leitura e rota inicial antes da
## troca definitiva do distrito legado.

@onready var district := $Bairro1V2 as Node2D
@onready var player := $Player as CharacterBody2D


func _ready() -> void:
	call_deferred("_place_player_at_spawn")


func _place_player_at_spawn() -> void:
	if district == null or player == null:
		return
	var spawn := district.call("get_marker", &"PlayerSpawn") as Marker2D
	if spawn == null:
		push_error("Bairro1V2Preview: PlayerSpawn is missing")
		return
	player.global_position = spawn.global_position
