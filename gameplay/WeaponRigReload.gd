extends RefCounted
## Recarga do WeaponRigPose: linha do tempo de cada arma (`reload_targets`, normalizada pelo áudio)
## e as curvas de ferrolho, tranco e acentos de carregador. Separado em 01/11 (Onda 3 de
## docs/plano-divisao-arquivos-grandes-20261101.md) só para o rig caber na leitura; o dono mantém
## `reload_targets` e `_rack` como delegações de uma linha (testes e o update chamam por lá).
## Estático e sem estado: o rig é RefCounted e um auxiliar com `var g` faria ciclo de referência;
## `reload_targets` recebe o rig em `g` só para o ombro esquerdo do lança-foguetes.

const DATA = preload("res://gameplay/WeaponPoseData.gd")
const SAWED = preload("res://gameplay/SawedOffPresentation.gd")

## V1 `PlayerCombatPose.reload_targets`: uma linha de tempo normalizada pelo
## áudio — ergue, manipula e volta à prontidão antes da gravação terminar.
static func reload_targets(g: RefCounted, id: String, progress: float) -> Dictionary:
	if id == "sawed_off": return SAWED.reload_targets(progress, DATA.GRIPS.sawed_off)
	var t := clampf(progress, 0.0, 1.0)
	var weight := smoothstep(0.0, 0.10, t) * (1.0 - smoothstep(0.88, 1.0, t))
	var hand := Vector3(0.14, 0.91, -0.18)
	var tilt := Vector3(0.22, -0.16, -0.38)
	var insert := Vector3(0.02, 0.79, -0.18)
	var belt := Vector3(-0.19, 0.65, 0.03)
	var left := insert
	var pump := 0.0
	var accents := {"roll": 0.0, "pitch": 0.0, "kick": Vector3.ZERO, "left": Vector3.ZERO}
	match id:
		"pistol", "pistol_suppressed":
			var magazine_well := Vector3(-0.01, 0.89, -0.22)
			var waist_magazine := Vector3(-0.16, 0.78, -0.02)
			var fetch := smoothstep(0.09, 0.22, t) * (1.0 - smoothstep(0.30, 0.47, t))
			left = magazine_well.lerp(waist_magazine, fetch)
			var rack := smoothstep(0.56, 0.65, t) * (1.0 - smoothstep(0.80, 0.89, t))
			left = left.lerp(Vector3(0.06, 0.98, -0.25 + _rack(t, 0.66, 0.81) * 0.07), rack)
			accents = _magazine_accents(t, 0.09, 0.45, 0.66 + 0.15 * DATA.RACK_PULL)
		"smg", "smg_compact", "smg_tactical", "ak47", "m4a1":
			var fetch := smoothstep(0.09, 0.22, t) * (1.0 - smoothstep(0.30, 0.47, t))
			left = insert.lerp(belt, fetch)
			var rack := smoothstep(0.56, 0.65, t) * (1.0 - smoothstep(0.80, 0.89, t))
			left = left.lerp(Vector3(0.07, 0.96, -0.20 + _rack(t, 0.66, 0.81) * 0.09), rack)
			accents = _magazine_accents(t, 0.09, 0.45, 0.66 + 0.15 * DATA.RACK_PULL)
			if id in ["ak47", "m4a1"]:
				hand.x = 0.09
				tilt.z = -0.52
			if id in ["smg", "smg_compact", "smg_tactical"]: tilt.z = DATA.SMG_RELOAD_ROLL
		"magnum":
			# Revólver, não escopeta: antes caía no caso da 12 e ia duas vezes ao cinto
			# como quem enfia cartucho no tubo. Aqui: tambor para a esquerda, cano para
			# cima para ejetar, UMA ida ao cinto pelo carregador rápido, cano para baixo
			# para encaixar, fecha. A abertura do tambor é de `Gameplay.update_weapon_parts`.
			var eject := smoothstep(0.08, 0.20, t) * (1.0 - smoothstep(0.30, 0.40, t))
			var engine_load_value := smoothstep(0.52, 0.62, t) * (1.0 - smoothstep(0.78, 0.88, t))
			# No encaixe o revólver vem para junto do peito, quase na horizontal: cano
			# para baixo e à frente com as duas mãos lia como arma longa.
			hand = Vector3(0.06, 0.92, -0.17).lerp(Vector3(0.02, 0.97, -0.08), engine_load_value)
			tilt = Vector3(0.85 * eject - 0.12 * engine_load_value, -0.10, -0.80 * smoothstep(0.04, 0.14, t) * (1.0 - smoothstep(0.80, 0.92, t)))
			# Palma no tambor aberto (lado esquerdo do receptor), em espaço da arma.
			var cylinder := hand + Basis.from_euler(tilt) * Vector3(-0.075, 0.06, -0.03)
			var fetch := smoothstep(0.32, 0.44, t) * (1.0 - smoothstep(0.46, 0.58, t))
			left = cylinder.lerp(belt, fetch)
			# Fecha o tambor com um golpe de pulso (o "flick" de cinema), no mesmo
			# instante em que `Gameplay.update_weapon_parts` recolhe o tambor.
			var flick := _pulse(t, 0.80, 0.08)
			accents = {"roll": 0.30 * flick, "pitch": 0.06 * flick, "kick": Vector3(0.012, 0.01, 0) * flick, "left": Vector3.ZERO}
		"shotgun", "shotgun_auto", "hunting_rifle":
			hand = Vector3(0.10, 0.87, -0.15)
			tilt = Vector3(0.05, -0.12, -0.62)
			insert = Vector3(-0.035, 0.84, -0.20)
			var load_motion := maxf(_stroke(t, 0.12, 0.35), _stroke(t, 0.39, 0.66))
			left = insert.lerp(belt, load_motion)
			if id == "shotgun":
				pump = _rack(t, 0.77, 0.94) * 0.09
				# Telha volta à frente com estalo: a arma pula para a frente.
				var slam := _pulse(t, 0.77 + 0.17 * DATA.RACK_PULL, 0.06)
				accents = {"roll": 0.0, "pitch": 0.07 * slam, "kick": Vector3(0, 0.008, -0.018) * slam, "left": Vector3.ZERO}
				var grab := smoothstep(0.68, 0.77, t)
				var basis := Basis.from_euler(tilt)
				left = left.lerp(hand + basis * (DATA.SUPPORT_GRIPS.shotgun - DATA.GRIPS.shotgun + Vector3(0, 0, pump)), grab)
			elif id == "hunting_rifle":
				hand = Vector3(0.15, 0.87, -0.30)
				left = left.lerp(Vector3(0.06, 0.94, -0.13), smoothstep(0.68, 0.79, t))
		"rpg":
			# Tubo atravessado à frente do peito, boca subindo para a esquerda (ao alcance
			# da mão esquerda, que traz o foguete do cinto e o assenta na boca por cima) e
			# mão direita na empunhadura à altura da cintura. Pose achada por busca com o
			# alcance real dos braços (~0,41 m): inclinado contra o peito (versão
			# anterior) o tubo entrava 5 cm no tronco, e em pé à frente do corpo a mão
			# ficaria a 0,76 m do ombro.
			var stand := Basis(Vector3.UP, 0.9) * Basis(Vector3.RIGHT, 0.7) * Basis(Vector3.BACK, -0.3)
			var rpg_hand := Vector3(0.08, 0.88, -0.14)
			var mouth := rpg_hand + stand * (DATA.RPG_MUZZLE - DATA.GRIPS.rpg)
			var axis := stand * Vector3.FORWARD
			var tube := rpg_hand + stand * (DATA.SUPPORT_GRIPS.rpg - DATA.GRIPS.rpg)
			# Linha do tempo do foguete (Gameplay o põe na palma esquerda entre a pega no
			# cinto e o encaixe): solta o tubo, busca no cinto, traz à frente da boca,
			# empurra para dentro e volta ao tubo.
			left = tube.lerp(belt, smoothstep(0.08, 0.24, t))
			left = left.lerp(mouth + axis * 0.22, smoothstep(0.30, 0.48, t))
			var seat := mouth + axis * DATA.RPG_ROCKET_CENTER
			var toward: Vector3 = g._shoulder("Left", -0.60) - seat
			left = left.lerp(seat + (toward - axis * toward.dot(axis)).normalized() * DATA.RPG_ROCKET_SIDE, smoothstep(DATA.RPG_ROCKET_SEAT.x, DATA.RPG_ROCKET_SEAT.y, t))
			left = left.lerp(tube, smoothstep(0.66, 0.80, t))
			# Volta ao ombro mais longa que a das outras armas (0,80–1,0): em 0,12 da
			# recarga o tubo subia varrendo o antebraço direito.
			weight = smoothstep(0.0, 0.10, t) * (1.0 - smoothstep(0.80, 1.0, t))
			return {"hand": rpg_hand, "left": left, "basis": stand, "weight": weight, "pump": 0.0, "kick": Vector3.ZERO}
		"flamethrower":
			tilt = Vector3(-0.18, 0.0, -0.43)
			left = Vector3(-0.06, 0.83, -0.17) + Vector3(sin(t * TAU * 2.0) * 0.035, cos(t * TAU * 2.0) * 0.025, 0)
		"grenade":
			hand = belt.lerp(Vector3(0.18, 0.92, -0.13), smoothstep(0.2, 0.82, t))
			left = Vector3(-0.17, 0.76, -0.05)
	# Manipula a arma à frente da jaqueta; a mão livre mantém o alcance do cinto
	# enquanto os alvos de inserção acompanham o receptor.
	tilt.y = 0.55
	if id in DATA.LONG_GUNS:
		# Coronha no ombro (`update`): cano para a frente e um pouco para baixo, girado
		# sobre o próprio eixo para mostrar o encaixe. Virado para dentro (0,55) a
		# arma deitava sobre o peito a partir do ombro.
		tilt.y = 0.06
		tilt.x -= 0.12
	tilt.x += float(accents.pitch)
	tilt.z += float(accents.roll)
	left += accents.left
	var clearance_offset := Vector3(0.10, 0, -0.14)
	hand += clearance_offset
	left += clearance_offset * clampf(left.distance_to(belt) / 0.15, 0.0, 1.0)
	if id == "grenade":
		hand = Vector3(0.25, lerpf(0.72, 0.94, smoothstep(0.2, 0.82, t)), -0.16)
	return {"hand": hand, "left": left, "basis": Basis.from_euler(tilt), "weight": weight, "pump": pump, "kick": (accents.kick as Vector3) * weight}

static func _stroke(t: float, start: float, finish: float) -> float:
	return sin(clampf((t - start) / maxf(finish - start, 0.001), 0.0, 1.0) * PI)

## Ferrolho/telha: puxa com a mão (curva suave até RACK_PULL do trecho) e a mola
## devolve de uma vez. O seno simétrico de `_stroke` lia como empurrar devagar.
static func _rack(t: float, start: float, finish: float) -> float:
	var x := clampf((t - start) / maxf(finish - start, 0.001), 0.0, 1.0)
	if x <= DATA.RACK_PULL: return sin(x / DATA.RACK_PULL * PI * 0.5)
	return 1.0 - smoothstep(DATA.RACK_PULL, 1.0, x)

## Impulso curto: sobe em 20% da janela e decai em quadrático (tranco, não onda).
static func _pulse(t: float, at: float, width: float) -> float:
	var x := (t - at) / maxf(width, 0.001)
	if x < 0.0 or x > 1.0: return 0.0
	return x / 0.2 if x < 0.2 else pow((1.0 - x) / 0.8, 2.0)

## Acentos de recarga com carregador, sobre os MESMOS instantes do áudio:
## soltar o vazio (a arma tomba para o lado para o carregador cair), encaixar o
## novo com um tapa da palma (a arma pula) e o retorno do ferrolho.
static func _magazine_accents(t: float, release: float, seat: float, slam: float) -> Dictionary:
	var flick := _pulse(t, release, 0.10)
	var slap := _pulse(t, seat, 0.07)
	var snap := _pulse(t, slam, 0.06)
	return {
		"roll": -0.28 * flick,
		"pitch": 0.10 * flick + 0.12 * slap + 0.05 * snap,
		"kick": Vector3(0, 0.014, 0) * slap + Vector3(0, 0.006, -0.012) * snap + Vector3(-0.01, 0.012, 0) * flick,
		"left": Vector3(0, 0.035, 0) * slap,
	}
