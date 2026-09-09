class_name GaragePropBuilder
extends RefCounted

## Construtor de peças modulares e estações para a oficina mecânica compacta.
## Geometria enriquecida com profundidade, sombras de contato, materiais industriais
## e leitura mecânica imediata sem dependência de rótulos de texto explicativos.

static func build_concrete_floor(size: Vector2) -> Node2D:
	var root := Node2D.new()
	root.name = "FloorModule"

	var half := size * 0.5
	var floor_rect := Polygon2D.new()
	floor_rect.name = "ConcreteSlab"
	floor_rect.color = Color("#181f26") # Concreto industrial escuro
	floor_rect.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y)
	])
	root.add_child(floor_rect)

	# Juntas de dilatação do concreto
	var joints_color := Color(0.09, 0.12, 0.15, 0.65)
	for x in range(int(-half.x + 130), int(half.x), 130):
		var j := Line2D.new()
		j.points = PackedVector2Array([Vector2(x, -half.y), Vector2(x, half.y)])
		j.width = 1.5
		j.default_color = joints_color
		root.add_child(j)
	for y in range(int(-half.y + 110), int(half.y), 110):
		var j := Line2D.new()
		j.points = PackedVector2Array([Vector2(-half.x, y), Vector2(half.x, y)])
		j.width = 1.5
		j.default_color = joints_color
		root.add_child(j)

	# Manchas de óleo e desgaste industrial perto das baias
	var oil_spots = [
		{"pos": Vector2(140, -40), "r": 32.0, "col": Color(0.04, 0.05, 0.07, 0.55)},
		{"pos": Vector2(155, -25), "r": 20.0, "col": Color(0.03, 0.04, 0.05, 0.70)},
		{"pos": Vector2(110, -55), "r": 16.0, "col": Color(0.04, 0.05, 0.07, 0.40)},
		{"pos": Vector2(0, 45), "r": 24.0, "col": Color(0.05, 0.06, 0.08, 0.35)},
		{"pos": Vector2(245, -75), "r": 18.0, "col": Color(0.03, 0.04, 0.05, 0.50)}
	]
	for sp in oil_spots:
		var circle := Polygon2D.new()
		var pts := PackedVector2Array()
		var spos: Vector2 = sp.pos
		var srad: float = float(sp.r)
		for i in 16:
			var ang := float(i) * TAU / 16.0
			var rad: float = srad * (0.85 + sin(ang * 3.0) * 0.15)
			pts.append(spos + Vector2(cos(ang), sin(ang)) * rad)
		circle.polygon = pts
		circle.color = sp.col
		root.add_child(circle)

	# Marcas pretas de borracha de pneu na entrada da baia
	for side in [-1, 1]:
		var tire_skid := Line2D.new()
		tire_skid.points = PackedVector2Array([
			Vector2(float(side) * 55, half.y - 10),
			Vector2(float(side) * 50, 110),
			Vector2(float(side) * 45 + 50, 20),
			Vector2(140 + float(side) * 35, -30)
		])
		tire_skid.width = 11.0
		tire_skid.default_color = Color(0.04, 0.04, 0.05, 0.30)
		root.add_child(tire_skid)

	# Faixas zebradas de segurança (amarelo e preto) no vão sul
	var hazard_p := Line2D.new()
	hazard_p.points = PackedVector2Array([Vector2(-95, half.y - 10), Vector2(95, half.y - 10)])
	hazard_p.width = 18.0
	hazard_p.default_color = Color("#d4ac0d")
	root.add_child(hazard_p)

	for s in range(-90, 95, 20):
		var stripe := Line2D.new()
		stripe.points = PackedVector2Array([Vector2(s - 8, half.y - 19), Vector2(s + 8, half.y - 1)])
		stripe.width = 7.0
		stripe.default_color = Color("#121417")
		root.add_child(stripe)

	return root

## Elevador Automotivo Hidráulico 2 Colunas detalhado com profundidade,
## sapatas com parafusos de ancoragem, cremalheira, pistões cromados e botoeira industrial
static func build_automotive_lift(pos: Vector2) -> Node2D:
	var lift := Node2D.new()
	lift.name = "AutomotiveLift"
	lift.position = pos

	# 1. Sombra de contato (Ambient Occlusion) projetada no concreto
	var shadow := Polygon2D.new()
	shadow.color = Color(0.04, 0.05, 0.07, 0.70)
	shadow.polygon = PackedVector2Array([
		Vector2(-96, -65), Vector2(96, -65),
		Vector2(100, 65), Vector2(-100, 65)
	])
	lift.add_child(shadow)

	# 2. Demarcação amarela de segurança no piso com cantos chanfrados
	var bay_border := Line2D.new()
	bay_border.points = PackedVector2Array([
		Vector2(-92, -58), Vector2(92, -58),
		Vector2(92, 58), Vector2(-92, 58), Vector2(-92, -58)
	])
	bay_border.width = 3.5
	bay_border.default_color = Color("#d4ac0d")
	lift.add_child(bay_border)

	# Travessa metálica embutida no piso com chapa xadrez
	var cross := Polygon2D.new()
	cross.color = Color("#242e38")
	cross.polygon = PackedVector2Array([
		Vector2(-6, -58), Vector2(6, -58),
		Vector2(6, 58), Vector2(-6, 58)
	])
	lift.add_child(cross)

	var cross_center := Line2D.new()
	cross_center.points = PackedVector2Array([Vector2(0, -58), Vector2(0, 58)])
	cross_center.width = 2.0
	cross_center.default_color = Color("#34495e")
	lift.add_child(cross_center)

	# 3. Colunas de Aço Estrutural (Esquerda em X = -72, Direita em X = 72)
	for side in [-1, 1]:
		var col_x: float = float(side) * 72.0

		# Placa de base reforçada ancorada no piso
		var base_plate := Polygon2D.new()
		base_plate.color = Color("#1e272e")
		base_plate.polygon = PackedVector2Array([
			Vector2(col_x - 16, -26), Vector2(col_x + 16, -26),
			Vector2(col_x + 16, 26), Vector2(col_x - 16, 26)
		])
		lift.add_child(base_plate)

		# 4 Parafusos de ancoragem sextavados em latão/aço
		for bx in [-12, 12]:
			for by in [-22, 22]:
				var bolt := Polygon2D.new()
				bolt.color = Color("#bdc3c7")
				bolt.polygon = PackedVector2Array([
					Vector2(col_x + bx - 2, by - 2), Vector2(col_x + bx + 2, by - 2),
					Vector2(col_x + bx + 2, by + 2), Vector2(col_x + bx - 2, by + 2)
				])
				lift.add_child(bolt)

		# Corpo principal da coluna em perfil H de aço amarelo/laranja industrial
		var col_body := Polygon2D.new()
		col_body.color = Color("#e59866") # Amarelo/laranja de segurança industrial
		col_body.polygon = PackedVector2Array([
			Vector2(col_x - 12, -22), Vector2(col_x + 12, -22),
			Vector2(col_x + 12, 22), Vector2(col_x - 12, 22)
		])
		lift.add_child(col_body)

		# Borda e friso escuro de chapa dobrada
		var col_trim := Line2D.new()
		col_trim.points = col_body.polygon
		col_trim.width = 2.0
		col_trim.default_color = Color("#a04000")
		lift.add_child(col_trim)

		# Canaleta interna da viga com o pistão cromado brilhante
		var channel := Polygon2D.new()
		channel.color = Color("#1a252f")
		channel.polygon = PackedVector2Array([
			Vector2(col_x - 5, -18), Vector2(col_x + 5, -18),
			Vector2(col_x + 5, 18), Vector2(col_x - 5, 18)
		])
		lift.add_child(channel)

		# Haste do pistão hidráulico cromada polida
		var piston := Line2D.new()
		piston.points = PackedVector2Array([Vector2(col_x, -16), Vector2(col_x, 16)])
		piston.width = 4.0
		piston.default_color = Color("#ecf0f1")
		lift.add_child(piston)

		# Dentes da cremalheira de trava mecânica de segurança
		for ty in range(-14, 16, 5):
			var tooth := Line2D.new()
			tooth.points = PackedVector2Array([Vector2(col_x + float(side) * 5, ty), Vector2(col_x + float(side) * 9, ty)])
			tooth.width = 2.0
			tooth.default_color = Color("#7f8c8d")
			lift.add_child(tooth)

	# 4. Unidade Eletro-Hidráulica de Força e Botoeira Industrial na coluna esquerda
	var pump_box := Polygon2D.new()
	pump_box.color = Color("#2c3e50")
	pump_box.polygon = PackedVector2Array([
		Vector2(-95, -14), Vector2(-84, -14),
		Vector2(-84, 14), Vector2(-95, 14)
	])
	lift.add_child(pump_box)

	var pump_box_trim := Line2D.new()
	pump_box_trim.points = pump_box.polygon
	pump_box_trim.width = 1.5
	pump_box_trim.default_color = Color("#1a252f")
	lift.add_child(pump_box_trim)

	# Botão cogumelo de emergência vermelho
	var btn_stop := Polygon2D.new()
	btn_stop.color = Color("#c0392b")
	btn_stop.polygon = PackedVector2Array([
		Vector2(-93, -10), Vector2(-86, -10),
		Vector2(-86, -5), Vector2(-93, -5)
	])
	lift.add_child(btn_stop)

	# Botão de subida verde
	var btn_up := Polygon2D.new()
	btn_up.color = Color("#27ae60")
	btn_up.polygon = PackedVector2Array([
		Vector2(-93, -2), Vector2(-86, -2),
		Vector2(-86, 3), Vector2(-93, 3)
	])
	lift.add_child(btn_up)

	# Alavanca de descida manual
	var lever := Line2D.new()
	lever.points = PackedVector2Array([Vector2(-86, 8), Vector2(-80, 10)])
	lever.width = 2.5
	lever.default_color = Color("#bdc3c7")
	lift.add_child(lever)

	# 5. Quatro Braços Pantográficos Articulados de Elevação com Sapatas
	var arm_definitions = [
		{"from": Vector2(-68, -10), "to": Vector2(-32, -42)},
		{"from": Vector2(-68, 10), "to": Vector2(-32, 42)},
		{"from": Vector2(68, -10), "to": Vector2(32, -42)},
		{"from": Vector2(68, 10), "to": Vector2(32, 42)}
	]
	for ad in arm_definitions:
		# Braço primário grosso
		var arm_main := Line2D.new()
		arm_main.points = PackedVector2Array([ad.from, ad.to])
		arm_main.width = 7.0
		arm_main.default_color = Color("#34495e")
		lift.add_child(arm_main)

		# Braço telescópico secundário interno
		var arm_inner := Line2D.new()
		arm_inner.points = PackedVector2Array([ad.from.lerp(ad.to, 0.45), ad.to])
		arm_inner.width = 4.5
		arm_inner.default_color = Color("#2c3e50")
		lift.add_child(arm_inner)

		# Pino de articulação circular na junta
		var pin := Polygon2D.new()
		pin.color = Color("#7f8c8d")
		var p_pts := PackedVector2Array()
		for i in 12:
			var ang := float(i) * TAU / 12.0
			p_pts.append(ad.from + Vector2(cos(ang), sin(ang)) * 4.5)
		pin.polygon = p_pts
		lift.add_child(pin)

		# Sapata de borracha estriada com borda metálica
		var pad := Polygon2D.new()
		pad.color = Color("#111317")
		pad.polygon = PackedVector2Array([
			ad.to + Vector2(-7, -7), ad.to + Vector2(7, -7),
			ad.to + Vector2(7, 7), ad.to + Vector2(-7, 7)
		])
		lift.add_child(pad)

		var pad_rim := Line2D.new()
		pad_rim.points = pad.polygon
		pad_rim.width = 1.5
		pad_rim.default_color = Color("#566573")
		lift.add_child(pad_rim)

	return lift

## Bancada Mecânica Pesada de Oficina com gaveteiros, morsa em ferro fundido,
## motoesmeril com protetores e pegboard perfurado com ferramentas realistas
static func build_mechanic_workbench(pos: Vector2) -> Node2D:
	var bench := Node2D.new()
	bench.name = "MechanicWorkbench"
	bench.position = pos

	# 1. Sombra de contato projetada no piso sob a bancada
	var shadow := Polygon2D.new()
	shadow.color = Color(0.04, 0.05, 0.07, 0.70)
	shadow.polygon = PackedVector2Array([
		Vector2(-86, -26), Vector2(86, -26),
		Vector2(88, 28), Vector2(-88, 28)
	])
	bench.add_child(shadow)

	# 2. Tampo robusto de carvalho nobre oleado (largura 170, profundidade 46)
	var top := Polygon2D.new()
	top.color = Color("#935116") # Madeira pesada envelhecida com impregnação de óleo
	top.polygon = PackedVector2Array([
		Vector2(-84, -22), Vector2(84, -22),
		Vector2(84, 22), Vector2(-84, 22)
	])
	bench.add_child(top)

	# Placa de aço de impacto no centro do tampo
	var steel_plate := Polygon2D.new()
	steel_plate.color = Color("#566573")
	steel_plate.polygon = PackedVector2Array([
		Vector2(-25, -18), Vector2(25, -18),
		Vector2(25, 18), Vector2(-25, 18)
	])
	bench.add_child(steel_plate)

	# Cantoneira metálica de borda de bancada
	var edge := Line2D.new()
	edge.points = top.polygon
	edge.width = 2.5
	edge.default_color = Color("#2c3e50")
	bench.add_child(edge)

	# 3. Gaveteiros duplos modulares vermelhos industriais (#922b21)
	for gx in [-52, 52]:
		var cab := Polygon2D.new()
		cab.color = Color("#922b21")
		cab.polygon = PackedVector2Array([
			Vector2(gx - 26, -18), Vector2(gx + 26, -18),
			Vector2(gx + 26, 18), Vector2(gx - 26, 18)
		])
		bench.add_child(cab)

		# Frestas e puxadores de aço escovado
		for dy in [-11, 0, 11]:
			var slot := Line2D.new()
			slot.points = PackedVector2Array([Vector2(gx - 24, dy), Vector2(gx + 24, dy)])
			slot.width = 1.5
			slot.default_color = Color("#641e16")
			bench.add_child(slot)

			var handle := Line2D.new()
			handle.points = PackedVector2Array([Vector2(gx - 14, dy - 2), Vector2(gx + 14, dy - 2)])
			handle.width = 2.5
			handle.default_color = Color("#ecf0f1")
			bench.add_child(handle)

	# 4. Morsa de bancada em ferro fundido (canto superior esquerdo)
	var vise_base := Polygon2D.new()
	vise_base.color = Color("#1e272c")
	vise_base.polygon = PackedVector2Array([
		Vector2(-78, -20), Vector2(-62, -20),
		Vector2(-62, -8), Vector2(-78, -8)
	])
	bench.add_child(vise_base)

	# Fuso roscado e manípulo com esferas nas pontas
	var vise_screw := Line2D.new()
	vise_screw.points = PackedVector2Array([Vector2(-70, -25), Vector2(-70, -3)])
	vise_screw.width = 3.5
	vise_screw.default_color = Color("#bdc3c7")
	bench.add_child(vise_screw)

	var vise_handle := Line2D.new()
	vise_handle.points = PackedVector2Array([Vector2(-76, -24), Vector2(-64, -24)])
	vise_handle.width = 2.0
	vise_handle.default_color = Color("#ecf0f1")
	bench.add_child(vise_handle)

	# 5. Motoesmeril duplo (centro da bancada)
	var grinder_body := Polygon2D.new()
	grinder_body.color = Color("#1b2631")
	grinder_body.polygon = PackedVector2Array([
		Vector2(-9, -16), Vector2(9, -16),
		Vector2(9, -6), Vector2(-9, -6)
	])
	bench.add_child(grinder_body)

	# Rebolo esquerdo (grão grosso cinza escuro)
	var wheel_l := Polygon2D.new()
	wheel_l.color = Color("#5d6d7e")
	wheel_l.polygon = PackedVector2Array([
		Vector2(-16, -18), Vector2(-10, -18),
		Vector2(-10, -4), Vector2(-16, -4)
	])
	bench.add_child(wheel_l)

	# Rebolo direito (grão fino cinza claro)
	var wheel_r := Polygon2D.new()
	wheel_r.color = Color("#d5dbdb")
	wheel_r.polygon = PackedVector2Array([
		Vector2(10, -18), Vector2(16, -18),
		Vector2(16, -4), Vector2(10, -4)
	])
	bench.add_child(wheel_r)

	# Protetores de fagulhas inclinados
	for s in [-1, 1]:
		var shield := Line2D.new()
		shield.points = PackedVector2Array([Vector2(s * 13 - 4, -20), Vector2(s * 13 + 4, -17)])
		shield.width = 1.5
		shield.default_color = Color(0.8, 0.9, 1.0, 0.75)
		bench.add_child(shield)

	# 6. Painel Perfurado (Pegboard) na parede acima da bancada
	var pegboard := Polygon2D.new()
	pegboard.color = Color("#2c3e50")
	pegboard.polygon = PackedVector2Array([
		Vector2(-80, -56), Vector2(80, -56),
		Vector2(80, -25), Vector2(-80, -25)
	])
	bench.add_child(pegboard)

	var peg_border := Line2D.new()
	peg_border.points = pegboard.polygon
	peg_border.width = 2.0
	peg_border.default_color = Color("#7f8c8d")
	bench.add_child(peg_border)

	# Furos perfurados regulares do painel
	for px in range(-74, 76, 12):
		for py in range(-52, -26, 10):
			var hole := Polygon2D.new()
			hole.color = Color("#1a252f")
			hole.polygon = PackedVector2Array([
				Vector2(px - 1, py - 1), Vector2(px + 1, py - 1),
				Vector2(px + 1, py + 1), Vector2(px - 1, py + 1)
			])
			bench.add_child(hole)

	# Ferramentas detalhadas penduradas no painel:
	# Jogo de 6 chaves combinadas cromadas em ordem crescente
	for i in 6:
		var wx: float = -70.0 + float(i) * 11.0
		var wrench := Line2D.new()
		wrench.points = PackedVector2Array([Vector2(wx, -50), Vector2(wx, -32 - float(i) * 2.0)])
		wrench.width = 2.5
		wrench.default_color = Color("#ecf0f1")
		bench.add_child(wrench)

		# Boca da chave
		var jaw_w := Line2D.new()
		jaw_w.points = PackedVector2Array([Vector2(wx - 2.5, -51), Vector2(wx + 2.5, -51)])
		jaw_w.width = 2.0
		jaw_w.default_color = Color("#bdc3c7")
		bench.add_child(jaw_w)

	# Martelo de pena com cabo de madeira e cabeça de aço
	var hammer_head := Polygon2D.new()
	hammer_head.color = Color("#7f8c8d")
	hammer_head.polygon = PackedVector2Array([
		Vector2(10, -52), Vector2(22, -52),
		Vector2(22, -47), Vector2(10, -47)
	])
	bench.add_child(hammer_head)

	var hammer_handle := Line2D.new()
	hammer_handle.points = PackedVector2Array([Vector2(16, -47), Vector2(16, -30)])
	hammer_handle.width = 2.5
	hammer_handle.default_color = Color("#d35400") # Madeira envernizada
	bench.add_child(hammer_handle)

	# Alicate universal com punhos emborrachados vermelhos
	var pliers_head := Line2D.new()
	pliers_head.points = PackedVector2Array([Vector2(40, -52), Vector2(40, -44)])
	pliers_head.width = 4.0
	pliers_head.default_color = Color("#95a5a6")
	bench.add_child(pliers_head)

	for ps in [-1, 1]:
		var pliers_grip := Line2D.new()
		pliers_grip.points = PackedVector2Array([Vector2(40, -44), Vector2(40 + ps * 4, -32)])
		pliers_grip.width = 2.5
		pliers_grip.default_color = Color("#c0392b") # Borracha vermelha
		bench.add_child(pliers_grip)

	# Estojo de soquetes aberto sobre a bancada (canto direito)
	var socket_case := Polygon2D.new()
	socket_case.color = Color("#2980b9") # Maleta plástica azul
	socket_case.polygon = PackedVector2Array([
		Vector2(48, -12), Vector2(74, -12),
		Vector2(74, 4), Vector2(48, 4)
	])
	bench.add_child(socket_case)

	for sx in range(52, 72, 5):
		var socket := Polygon2D.new()
		socket.color = Color("#ecf0f1")
		socket.polygon = PackedVector2Array([
			Vector2(sx - 1.5, -8), Vector2(sx + 1.5, -8),
			Vector2(sx + 1.5, -4), Vector2(sx - 1.5, -4)
		])
		bench.add_child(socket)

	return bench

## Carrinho móvel de ferramentas com 3 bandejas e tambor 200L com bomba rotativa
static func build_tool_cart_and_oil(pos: Vector2) -> Node2D:
	var group := Node2D.new()
	group.name = "ToolCartAndOil"
	group.position = pos

	# Sombra de contato do carrinho
	var cart_shadow := Polygon2D.new()
	cart_shadow.color = Color(0.04, 0.05, 0.07, 0.60)
	cart_shadow.polygon = PackedVector2Array([
		Vector2(-24, -17), Vector2(24, -17),
		Vector2(24, 17), Vector2(-24, 17)
	])
	group.add_child(cart_shadow)

	# Carrinho de ferramentas vermelho industrial
	var cart := Polygon2D.new()
	cart.color = Color("#c0392b")
	cart.polygon = PackedVector2Array([
		Vector2(-20, -15), Vector2(20, -15),
		Vector2(20, 15), Vector2(-20, 15)
	])
	group.add_child(cart)

	var cart_trim := Line2D.new()
	cart_trim.points = cart.polygon
	cart_trim.width = 1.5
	cart_trim.default_color = Color("#922b21")
	group.add_child(cart_trim)

	# Bandeja superior com divisória
	var divider := Line2D.new()
	divider.points = PackedVector2Array([Vector2(0, -15), Vector2(0, 15)])
	divider.width = 1.5
	divider.default_color = Color("#922b21")
	group.add_child(divider)

	# Alça tubular de empurrar
	var handle := Line2D.new()
	handle.points = PackedVector2Array([Vector2(-20, -11), Vector2(-26, -11), Vector2(-26, 11), Vector2(-20, 11)])
	handle.width = 2.5
	handle.default_color = Color("#ecf0f1")
	group.add_child(handle)

	# 4 Rodízios de poliuretano preto
	for rx in [-18, 18]:
		for ry in [-14, 14]:
			var wheel := Polygon2D.new()
			wheel.color = Color("#17202a")
			wheel.polygon = PackedVector2Array([
				Vector2(rx - 2, ry - 2), Vector2(rx + 2, ry - 2),
				Vector2(rx + 2, ry + 2), Vector2(rx - 2, ry + 2)
			])
			group.add_child(wheel)

	# Tambor de óleo 200L azul com anéis frisados
	var drum_pos := Vector2(40, 0)
	var drum_shadow := Polygon2D.new()
	drum_shadow.color = Color(0.04, 0.05, 0.07, 0.65)
	var ds_pts := PackedVector2Array()
	for i in 16:
		var ang := float(i) * TAU / 16.0
		ds_pts.append(drum_pos + Vector2(cos(ang), sin(ang)) * 18.0)
	drum_shadow.polygon = ds_pts
	group.add_child(drum_shadow)

	var drum := Polygon2D.new()
	drum.color = Color("#2471a3")
	var d_pts := PackedVector2Array()
	for i in 20:
		var ang := float(i) * TAU / 20.0
		d_pts.append(drum_pos + Vector2(cos(ang), sin(ang)) * 16.0)
	drum.polygon = d_pts
	group.add_child(drum)

	var drum_ring := Line2D.new()
	drum_ring.points = d_pts
	drum_ring.width = 2.0
	drum_ring.default_color = Color("#1a5276")
	group.add_child(drum_ring)

	# Bomba rotativa manual com bico e manivela vermelha
	var pump_hub := Polygon2D.new()
	pump_hub.color = Color("#2c3e50")
	var ph_pts := PackedVector2Array()
	for i in 12:
		var ang := float(i) * TAU / 12.0
		ph_pts.append(drum_pos + Vector2(cos(ang), sin(ang)) * 5.0)
	pump_hub.polygon = ph_pts
	group.add_child(pump_hub)

	var crank := Line2D.new()
	crank.points = PackedVector2Array([drum_pos, drum_pos + Vector2(12, -9)])
	crank.width = 3.0
	crank.default_color = Color("#e74c3c")
	group.add_child(crank)

	return group

## Estante tubular de parede com pneus radiais montados em rodas esportivas
static func build_tire_racks(pos: Vector2) -> Node2D:
	var racks := Node2D.new()
	racks.name = "TireRacks"
	racks.position = pos

	var frame := Line2D.new()
	frame.points = PackedVector2Array([
		Vector2(-60, -15), Vector2(60, -15), Vector2(60, 15), Vector2(-60, 15), Vector2(-60, -15)
	])
	frame.width = 2.5
	frame.default_color = Color("#7f8c8d")
	racks.add_child(frame)

	for i in 4:
		var tx := -45 + i * 30
		var tire := Polygon2D.new()
		tire.color = Color("#1c2833")
		var t_pts := PackedVector2Array()
		for j in 16:
			var ang := float(j) * TAU / 16.0
			t_pts.append(Vector2(tx, 0) + Vector2(cos(ang), sin(ang)) * 13.0)
		tire.polygon = t_pts
		racks.add_child(tire)

		var rim := Polygon2D.new()
		rim.color = Color("#bdc3c7")
		var r_pts := PackedVector2Array()
		for j in 12:
			var ang := float(j) * TAU / 12.0
			r_pts.append(Vector2(tx, 0) + Vector2(cos(ang), sin(ang)) * 6.0)
		rim.polygon = r_pts
		racks.add_child(rim)

	return racks

## Lounge do Maciota preservado como placeholder com mobiliário clássico
static func build_maciota_vip_lounge(pos: Vector2) -> Node2D:
	var lounge := Node2D.new()
	lounge.name = "MaciotaVIPLounge"
	lounge.position = pos

	var partition := Line2D.new()
	partition.points = PackedVector2Array([
		Vector2(-105, -70), Vector2(105, -70), Vector2(105, 50), Vector2(20, 50)
	])
	partition.width = 4.0
	partition.default_color = Color("#5d6d7e")
	lounge.add_child(partition)

	var carpet := Polygon2D.new()
	carpet.color = Color("#4a154b")
	carpet.polygon = PackedVector2Array([
		Vector2(-95, -60), Vector2(95, -60), Vector2(95, 40), Vector2(-95, 40)
	])
	lounge.add_child(carpet)

	var carpet_border := Line2D.new()
	carpet_border.points = carpet.polygon
	carpet_border.width = 2.5
	carpet_border.default_color = Color("#f1c40f")
	lounge.add_child(carpet_border)

	var desk_pos := Vector2(25, -10)
	var desk := Polygon2D.new()
	desk.color = Color("#3e2723")
	desk.polygon = PackedVector2Array([
		desk_pos + Vector2(-35, -16), desk_pos + Vector2(35, -16),
		desk_pos + Vector2(35, 16), desk_pos + Vector2(-35, 16)
	])
	lounge.add_child(desk)

	var desk_trim := Line2D.new()
	desk_trim.points = desk.polygon
	desk_trim.width = 1.5
	desk_trim.default_color = Color("#d4ac0d")
	lounge.add_child(desk_trim)

	var lamp := Polygon2D.new()
	lamp.color = Color("#1e8449")
	lamp.polygon = PackedVector2Array([
		desk_pos + Vector2(-24, -10), desk_pos + Vector2(-16, -10),
		desk_pos + Vector2(-16, -4), desk_pos + Vector2(-24, -4)
	])
	lounge.add_child(lamp)

	var chair := Polygon2D.new()
	chair.color = Color("#5d4037")
	chair.polygon = PackedVector2Array([
		desk_pos + Vector2(-14, 18), desk_pos + Vector2(14, 18),
		desk_pos + Vector2(16, 32), desk_pos + Vector2(-16, 32)
	])
	lounge.add_child(chair)

	return lounge

## Espaço reservado para o Quadro de Missões (placeholder para Claude Code)
static func build_mission_board_zone(pos: Vector2) -> Node2D:
	var board_zone := Node2D.new()
	board_zone.name = "MissionBoardZone"
	board_zone.position = pos

	var frame := Polygon2D.new()
	frame.color = Color("#4a3525")
	frame.polygon = PackedVector2Array([
		Vector2(-45, -30), Vector2(45, -30), Vector2(45, 30), Vector2(-45, 30)
	])
	board_zone.add_child(frame)

	var cork := Polygon2D.new()
	cork.color = Color("#8d6e63")
	cork.polygon = PackedVector2Array([
		Vector2(-40, -25), Vector2(40, -25), Vector2(40, 25), Vector2(-40, 25)
	])
	board_zone.add_child(cork)

	var papers = [
		{"pos": Vector2(-25, -12), "sz": Vector2(16, 18), "col": Color("#fdfefe")},
		{"pos": Vector2(-5, -15), "sz": Vector2(18, 22), "col": Color("#fcf3cf")},
		{"pos": Vector2(16, -10), "sz": Vector2(16, 16), "col": Color("#d5f5e3")},
		{"pos": Vector2(-18, 6), "sz": Vector2(22, 14), "col": Color("#fadbd8")}
	]
	for p in papers:
		var p_pos: Vector2 = p.pos
		var sz: Vector2 = p.sz
		var sheet := Polygon2D.new()
		sheet.color = p.col
		sheet.polygon = PackedVector2Array([
			p_pos, p_pos + Vector2(sz.x, 0),
			p_pos + sz, p_pos + Vector2(0, sz.y)
		])
		board_zone.add_child(sheet)

		var pin := Polygon2D.new()
		pin.color = Color("#e74c3c")
		pin.polygon = PackedVector2Array([
			p_pos + Vector2(sz.x * 0.5 - 2, 1), p_pos + Vector2(sz.x * 0.5 + 2, 1),
			p_pos + Vector2(sz.x * 0.5 + 2, 4), p_pos + Vector2(sz.x * 0.5 - 2, 4)
		])
		board_zone.add_child(pin)

	var lamp := Line2D.new()
	lamp.points = PackedVector2Array([Vector2(-35, -34), Vector2(35, -34)])
	lamp.width = 4.0
	lamp.default_color = Color("#d4ac0d")
	board_zone.add_child(lamp)

	return board_zone
