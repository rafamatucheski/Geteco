extends SceneTree
## Custo de ligar o motor completo a um carro (roda a cada carro que nasce no trânsito).
const ADAPTER := preload("res://gameplay/desert_cars/DesertCarAdapter.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var car := VEHICLE.new()
	car.archetype = "sedan_classic"
	car.vehicle_id = "attach_cost"
	root.add_child(car)
	car.set_physics_process(false)
	var samples: Array[float] = []
	for i in 400:
		var began := Time.get_ticks_usec()
		ADAPTER.attach(car)
		samples.append((Time.get_ticks_usec()-began)/1000.0)
	samples.sort()
	print("STREET_ATTACH_COST n=%d mediana=%.3f ms p95=%.3f ms max=%.3f ms" % [samples.size(),samples[samples.size()/2],samples[int(samples.size()*.95)],samples[-1]])
	quit(0)
