extends Node3D
## Mecânico da oficina do Maciota: macacão azul, barba e botas pretas. Corpo único importado do Meshy
## (`CivilianModel` com `body_source`); a geometria procedural antiga e a rotina que girava os pivôs dela
## foram removidas. `limbs`, `clock` e `walking` ficam só por compatibilidade com quem lê o contrato dos
## modelos antigos; o corpo novo mede o próprio deslocamento e anda sozinho.
const BODY := preload("res://assets/CivilianModel.gd")
const SOURCE := "res://assets/civilians/meshy/mechanic/mechanic.glb"
var limbs: Array[Node3D] = []
var clock := 0.0
var walking := false
var body: Node3D

func _ready() -> void:
	body = BODY.new()
	body.name = "Body"
	body.body_source = SOURCE
	body.appearance_locked = true
	body.appearance_variant = 8200
	# O GLB do Meshy já olha para +Z, a mesma frente do pedestre articulado.
	add_child(body)
