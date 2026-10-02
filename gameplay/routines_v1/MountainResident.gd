extends "res://gameplay/urban_v1/PortWorker.gd"
## Morador da serra com vida e dano, para ser atropelado, baleado e socorrido como
## qualquer outro civil. A base V1RoutineActor não expõe dano de propósito, e o
## corpo sólido dela virava um bloco de ferro na frente do carro. O modelo de
## inverno olha para -Z (o do porto olha para +Z), então a orientação volta ao padrão.

func _facing_yaw(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)
