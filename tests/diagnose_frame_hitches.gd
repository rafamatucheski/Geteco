extends SceneTree

## Atribui os HITCHES de frame (picos de 40-110ms) a uma causa, em vez de so
## reportar percentis. Roda o checkpoint real do HarborGame dirigindo, com vsync
## ligado, e separa o tempo do frame em render CPU, render GPU e o resto.
##
## O que esta medicao estabeleceu nesta base:
##  - A GPU esta ociosa: 1.4ms de render_gpu tanto nos frames rapidos quanto nos
##    hitches. O render CPU tambem e identico nos dois (6.5ms). Em um frame de
##    80ms, ~73ms nao estao nem no render nem na GPU -- estao na thread principal.
##  - Os hitches sao frames que CRIAM COISA: |delta nos| 20.7x maior que nos
##    frames rapidos, |delta objetos| 15.0x, memoria de video +1.48MB contra
##    +0.25MB, recursos carregados 588x. Instanciacao de cena com upload de
##    textura/mesh, nao custo de desenho.
##  - Desligar o PresentationBudget (`-- nopb`) reduziu os hitches de 32 para 27,
##    dentro da variancia entre execucoes (27 a 37): ele participa mas nao e a
##    causa principal. Existem outros caminhos de spawn furando o orcamento.
##  - Consequencia para a direcao de otimizacao: o desenho custa ~1.4ms de um
##    orcamento de 16.7ms. Culling de luzes, batching e SubViewports mexem na parte
##    que NAO e o gargalo. Esta base e limitada por CPU, nao por GPU.
##  - A fila do PresentationBudget fica parada em ~100 atores pendentes durante
##    toda a amostragem: com max_builds_per_frame=1 e budget_usec=2000 ela nunca
##    esvazia.
##  - As razoes de 15x a 606x foram reproduzidas em quatro execucoes seguidas. Ja a
##    contagem absoluta de hitches NAO e estavel (27 a 37 entre execucoes), porque
##    a rota diverge com colisoes e trafego -- comparacoes de antes/depois tem que
##    usar as razoes, nunca a contagem.
##  - Descartados por medicao: fisica (7-10ms, igual nos rapidos e nos lentos),
##    navegacao (0.0ms), draw calls (1690 vs 1740) e os ciclos de 0.2s de
##    ContinuousWorld e HarborLife (16.3ms nos frames do ciclo contra 16.1ms nos
##    outros).
##
## Uso: --script res://tests/diagnose_frame_hitches.gd -- [nopb]
const GAME := preload("res://world/harbor/HarborGame.tscn")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	root.size = Vector2i(1920,1080); root.content_scale_size = Vector2i(1920,1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED); Engine.max_fps = 0
	root.get_node("SaveManager").clear_pending_save()
	var c := root.get_node("CampaignState"); c.reset_campaign()
	for f in ["harbor_arrival_seen","harbor_arrival_call_complete","harbor_maciota_met","harbor_delivery_complete"]:
		c.set_campaign_flag(StringName(f), true)
	var world := GAME.instantiate(); root.add_child(world); current_scene = world
	for i in 90: await process_frame
	var player: Node2D = world.get_node("Player")
	var car: CharacterBody2D = world.get_node("PlayerCar")
	car.global_position = Vector2(700,425); car.rotation = 0.0
	player.global_position = car.global_position
	car.enter_vehicle(player)
	for i in 150: await process_frame
	Input.action_press("ui_up")
	for i in 120: await process_frame
	var off := OS.get_cmdline_user_args().has("nopb")
	var pb := root.get_node_or_null("PresentationBudget")
	if off and pb != null:
		pb.set_process(false)
	print("HITCH presentation_budget_desligado=%s" % str(off and pb != null))
	var vp := root.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in 20: await process_frame
	var rows: Array = []
	for i in 600:
		var t := Time.get_ticks_usec()
		await process_frame
		rows.append({
			"ms": float(Time.get_ticks_usec()-t)/1000.0,
			"rcpu": RenderingServer.viewport_get_measured_render_time_cpu(vp),
			"rgpu": RenderingServer.viewport_get_measured_render_time_gpu(vp),
			"setup": 0.0,
			"objs": Performance.get_monitor(Performance.OBJECT_COUNT),
			"vram": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0,
			"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			"res": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
			"pend": float(pb.pending.size()) if pb != null else 0.0,
		})
	Input.action_release("ui_up")
	var slow: Array = []; var fast: Array = []
	for r in rows:
		if r.ms > 25.0:
			slow.append(r)
		else:
			fast.append(r)
	for lbl in [["RAPIDOS", fast], ["HITCHES>25ms", slow]]:
		var set: Array = lbl[1]
		if set.is_empty(): continue
		var s := {"ms":0.0,"rcpu":0.0,"rgpu":0.0,"setup":0.0,"objs":0.0,"pend":0.0}
		for r in set:
			for k in s: s[k] += float(r[k])
		print("HITCH %-12s n=%3d  frame=%6.2f  render_cpu=%5.2f  render_gpu=%5.2f  |  nao_explicado=%6.2f  objetos=%.0f  fila_apresentacao=%.1f" % [
			lbl[0], set.size(), s.ms/set.size(), s.rcpu/set.size(), s.rgpu/set.size(),
			(s.ms - s.rcpu)/set.size(), s.objs/set.size(), s.pend/set.size()])
	# Correlaciona cada hitch com o que MUDOU naquele frame.
	for key in ["objs", "vram", "nodes", "res"]:
		var d: Array[float] = []
		var m: Array[float] = []
		for i in range(1, rows.size()):
			d.append(absf(float(rows[i][key]) - float(rows[i-1][key])))
			m.append(float(rows[i].ms))
		var n := float(d.size())
		var mx := 0.0
		var my := 0.0
		for i in d.size():
			mx += d[i]
			my += m[i]
		mx /= n
		my /= n
		var cov := 0.0
		var vx := 0.0
		var vy := 0.0
		for i in d.size():
			var a := d[i]-mx
			var b := m[i]-my
			cov += a*b
			vx += a*a
			vy += b*b
		# media da mudanca nos frames de hitch contra a media nos frames rapidos
		var ds := 0.0
		var ns := 0
		var df := 0.0
		var nf := 0
		for i in d.size():
			if m[i] > 25.0:
				ds += d[i]
				ns += 1
			else:
				df += d[i]
				nf += 1
		print("HITCH delta[%-5s] correl_com_ms=%+.3f  media_nos_hitches=%8.2f  media_nos_rapidos=%8.2f  razao=%.1fx" % [
			key, cov/maxf(sqrt(vx*vy),0.0001), ds/maxf(float(ns),1.0), df/maxf(float(nf),1.0),
			(ds/maxf(float(ns),1.0))/maxf(df/maxf(float(nf),1.0),0.0001)])
	var w := rows.duplicate(); w.sort_custom(func(a,b): return a.ms > b.ms)
	for i in 6:
		print("HITCH pior#%d frame=%6.2f render_cpu=%5.2f render_gpu=%5.2f setup=%5.2f" % [i, w[i].ms, w[i].rcpu, w[i].rgpu, w[i].setup])
	quit(0)
