extends "res://tests/test_jessica_crossing_yield.gd"
## Mesma curva do dono, sinal e prazo físico de 15s; só a fixture traseira explícita
## usa a posição de 114.16m observada à parte, com espaço disponível.
func _initialize() -> void:
	rear_fixture_point = Vector3(114.1632,.12,79.83971)
	expect_clear = true
	super._initialize()
