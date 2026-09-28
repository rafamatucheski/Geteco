extends SceneTree
## Onde vai o custo de montar um policial: _ready (geometria antiga) x corpo articulado.
## Renderizado, sem --headless.
const MODEL = preload("res://gameplay/PoliceModel.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	await process_frame
	for pass_index in 4:
		var t0 := Time.get_ticks_usec()
		var m = MODEL.new()
		m.tier = 0
		host.add_child(m)               # dispara _ready
		var t1 := Time.get_ticks_usec()
		m._install_body()               # o mesmo que o call_deferred faria
		var t2 := Time.get_ticks_usec()
		var w0 := Time.get_ticks_usec()
		m.equip("m4a1")
		var w1 := Time.get_ticks_usec()
		var sil = preload("res://gameplay/PoliceOcclusionSilhouette.gd").new()
		m.get_parent().add_child(sil) if false else host.add_child(sil)
		var w2 := Time.get_ticks_usec()
		print("POLICE_COST   equip=%.2f ms  silhouette=%.2f ms" % [(w1-w0)/1000.0, (w2-w1)/1000.0])
		await process_frame
		var t3 := Time.get_ticks_usec()
		print("POLICE_COST pass=%d ready=%.2f ms  install_body=%.2f ms  next_frame=%.2f ms" % [pass_index, (t1-t0)/1000.0, (t2-t1)/1000.0, (t3-t2)/1000.0])
	quit(0)
