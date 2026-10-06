extends SceneTree
## Imprime o catálogo de performance medido. Matemática pura, sem render, então
## --headless é válido aqui (não mede tempo de quadro).
const PERF := preload("res://data/catalogs/VehiclePerformance.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var rows: Array = []
	for id in PERF.tunable_ids(): rows.append(PERF.measure(id))
	rows.sort_custom(func(a,b): return a.score < b.score)
	for r in rows:
		print("%-3s %5.1f %-22s %-6s 0-100:%5.2fs 400m:%5.2fs top:%4.0f acc%3.0f spd%3.0f hnd%3.0f brk%3.0f" % [
			r["class"],r.score,r.id,r.model,r.zero_to_100,r.quarter,r.top_kmh,r.rate_accel,r.rate_speed,r.rate_handling,r.rate_braking])
	print("TOTAL ",rows.size())
	quit(0)
