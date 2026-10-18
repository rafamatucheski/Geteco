extends "res://gameplay/urban_v1/PortWorker.gd"
## Morador da serra com vida e dano, para ser atropelado, baleado e socorrido como
## qualquer outro civil. A base V1RoutineActor não expõe dano de propósito, e o
## corpo sólido dela virava um bloco de ferro na frente do carro.
##
## 2026-10-17: este arquivo sobrescrevia `_facing_yaw` com atan2(-x, -z), supondo um
## modelo de inverno virado para -Z. Desde a troca para o corpo articulado (RigBodySwap
## com faces_positive_z) o modelo olha para +Z, como o do porto, e os moradores andavam
## de costas. A orientação do PortWorker (atan2(x, z)) é a certa.
