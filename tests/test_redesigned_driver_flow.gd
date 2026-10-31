extends "res://tests/test_seated_driver_flow.gd"
## Mesmo fluxo de produção de embarque/direção/saída, com A/B de modelo local ao processo.
## --baseline seleciona os modelos legados sem mudar a frota salva nem arquivos.
func _initialize() -> void:
	preload("res://runtime/RedesignedFleet.gd").enabled = not "--baseline" in OS.get_cmdline_user_args()
	print("REDESIGNED_FLOW baseline=", not preload("res://runtime/RedesignedFleet.gd").enabled)
	super._initialize()
