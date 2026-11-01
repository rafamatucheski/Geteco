extends RefCounted
## Procura policial do Gameplay: crime registrado e estrelas (register_crime, update_stars), contato e
## última posição conhecida (report_contact, report_civilian_call), quem a polícia vê e persegue
## (police_can_see, pursuit_target), prisão e aviso (arrest_player, police_arrest_warning, police_can_arrest),
## área de busca e fuga (police_search_radius, evasion_rate, police_evasion_*), o tique da procura
## (_update_police), o policial a pé (spawn_officer), clear_wanted e a denúncia de policial ferido ou morto
## (_report_police_assault/_report_police_killed, que vieram do GameplayDamage). Separado em 01/11 (Onda 3 de
## docs/plano-divisao-arquivos-grandes-20261101.md). O estado (stars, crime_points, last_known,
## last_known_valid, contact_age, hidden_time, dispatch_timer, deployed, police, police_case...) e os sinais
## (changed, crime_reported, player_arrested, police_warning_issued, message) continuam no Gameplay: stars e
## last_known são lidos em 163 arquivos. Cada função antiga virou delegação de uma linha com a mesma
## assinatura e os mesmos padrões.
## Ficam no Gameplay, sobrescritas em subclasses de teste: report_observed_crime, police_surrendering e
## police_force_authorized. Até as chamadas entre funções deste arquivo passam por `g.` para o despacho
## numa subclasse continuar igual.
## `g` fica como Node3D, e não como o script do Gameplay, para não criar preload cíclico.

const OFFICER = preload("res://gameplay/PoliceAgent.gd")
const PURSUIT := preload("res://gameplay/dispatch/PursuitRules.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

func arrest_player() -> bool:
	if not g.police_can_arrest() or g.health <= 0 or g.state == null or not g.state.weapons_allowed() or g.player.input_locked: return false
	g._clear_chain_explosions()
	g.player.input_locked = true
	g.player_arrested.emit()
	return true

func police_arrest_warning(actor: Node3D = null) -> void:
	var now := Time.get_ticks_msec()
	if now-g._last_arrest_warning_msec < 2500: return
	g._last_arrest_warning_msec = now
	g.last_warning_actor = weakref(actor) if is_instance_valid(actor) else null
	g.police_warning_issued.emit()

func register_crime(points: int, point: Vector3, kind: String = "reported", testimony: Dictionary = {}) -> void:
	# A completed testimony describes an earlier crime. Entering a safe garage
	# cannot retroactively erase it; safe areas still reject new local offenses.
	if points < 0 or (points == 0 and kind != "police_assault") or (not g.state.weapons_allowed() and testimony.is_empty()): return
	if g.police_case != null:
		g.police_case.confirmed(points, point, kind, testimony)
		points = g.police_case.escalation.accept(points, g.crime_points, kind)
	var old_stars: int = g.stars
	g.crime_points = mini(g.MAX_CRIME_POINTS, g.crime_points + points)
	g.update_stars()
	g.last_known = testimony.get("exterior", point)
	g.last_known_valid = true
	g.set_meta("police_contact_place_id", "" if not testimony.is_empty() else (String(g.state.place_id) if "place_id" in g.state else ""))
	g.hidden_time = 0
	if old_stars == 0 and g.stars > 0:
		g.dispatch_timer = [0.0, 6.0, 3.0, 1.0, 1.0, 1.0, 1.0][g.stars]
	g.crime_reported.emit(points)
	g.changed.emit()

func update_stars() -> void:
	g.stars = 0
	for level in range(1, g.STAR_THRESHOLDS.size()):
		if g.crime_points >= g.STAR_THRESHOLDS[level]: g.stars = level

func report_contact(point: Vector3) -> void:
	g.set_meta("police_contact_place_id", String(g.state.place_id) if "place_id" in g.state else "")
	g.last_known = point
	g.last_known_valid = true
	g.contact_age = 0
	g.hidden_time = 0
	if g.police_case != null: g.police_case.descending = false

func police_can_arrest() -> bool:
	return g.stars > 0 and (g.police_surrendering() or (g.stars == 1 and not g.police_force_authorized()) or g._vehicle_bust_allowed())

## Perseguição estilo GTA: com 1-2 estrelas sem força autorizada, quem está num carro parado e
## cercado é preso pelo policial que chega à porta (PoliceAgent exige carro parado e o policial ao lado).
func _vehicle_bust_allowed() -> bool:
	if not PURSUIT.enabled or g.stars > PURSUIT.BUST_MAX_STARS or g.police_force_authorized(): return false
	return is_instance_valid(g.world) and g.world.get("driving") != null and bool(g.world.driving.occupied)

## Área de busca (PursuitRules): raio por estrela em volta da última posição conhecida.
func police_search_radius() -> float:
	return PURSUIT.search_radius(g.stars) if PURSUIT.enabled else 0.0

## Fora da área de busca a fuga anda normal; dentro, a PursuitRules.EVASION_INSIDE_RATE. Sair do
## círculo é o que despista (GTA IV); esconder-se perto ainda funciona, só demora mais.
func evasion_rate() -> float:
	if not PURSUIT.enabled or g.stars <= 0 or not g.last_known_valid: return 1.0
	var target: Node3D = g.pursuit_target()
	if not is_instance_valid(target): return 1.0
	var flat := Vector2(target.global_position.x - g.last_known.x, target.global_position.z - g.last_known.z).length()
	return 1.0 if flat > g.police_search_radius() else PURSUIT.EVASION_INSIDE_RATE

func police_investigation_active() -> bool:
	return g.police_case != null and g.police_case.investigation_active()

func police_investigation_point() -> Vector3:
	return g.police_case.case_point if g.police_case != null else g.last_known

func police_k9_restraint(seconds: float = 1.2) -> void:
	if g.health <= 0 or g.police_surrendering() or not g.state.weapons_allowed(): return
	g.player.set_meta("police_restraint_left", clampf(seconds, 0.0, 2.0))

## A testemunha informa a posição observada e antecipa a primeira viatura.
## Não cria crime novo nem procura quando o jogador não é suspeito.
func report_civilian_call(witness: Vector3, suspect: Vector3) -> bool:
	if g.stars <= 0 or g.health <= 0: return false
	if witness.distance_to(suspect) > 40.0: return false
	var ray := PhysicsRayQueryParameters3D.create(witness + Vector3.UP * 1.4, suspect + Vector3.UP, 1)
	if not g.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return false
	g.report_contact(suspect)
	if g.dispatch_owned:
		var dispatcher: Variant = g.world.get("dispatch") if is_instance_valid(g.world) else null
		if is_instance_valid(dispatcher) and dispatcher.has_method("witness_call"):
			dispatcher.witness_call(witness)
	else: g.dispatch_timer = minf(g.dispatch_timer, 1.5)
	return true

func police_can_see(officer: CharacterBody3D) -> bool:
	var place := String(g.state.place_id) if "place_id" in g.state else ""
	if String(officer.get_meta("police_place_id", "")) != place: return false
	var suspect: Node3D = g.pursuit_target()
	if g.health <= 0 or not g.state.weapons_allowed() or not suspect.visible: return false
	if officer.global_position.distance_to(suspect.global_position) > 26.875: return false
	var ray := PhysicsRayQueryParameters3D.create(officer.global_position + Vector3.UP * 1.4, suspect.global_position + Vector3.UP, 7, [officer.get_rid()])
	var hit := g.get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty() or hit.collider == suspect

func pursuit_target() -> Node3D:
	if g.world != null and g.world.get("driving") != null and g.world.driving.occupied:
		return g.world.driving.car
	return g.player

func police_evasion_seconds() -> float:
	if g.police_case != null and g.police_case.descending: return 8.0
	return g.EVASION_SECONDS[clampi(g.stars, 0, 6)]

func police_evasion_progress() -> float:
	if g.stars <= 0 or g.contact_age <= 1.0 or g.police_surrendering(): return 0.0
	return clampf(g.hidden_time / g.police_evasion_seconds(), 0.0, 1.0)

func _update_police(delta: float) -> void:
	if g.police_case != null: g.police_case.tick(delta)
	g.police = g.police.filter(func(unit): return is_instance_valid(unit) and not unit.dead)
	g.contact_age += delta
	if g.crime_points > 0 and g.contact_age > 1.0: g.hidden_time += delta * g.evasion_rate()
	elif g.crime_points == 0: g.hidden_time = 0.0
	if g.crime_points > 0 and g.stars == 0 and g.hidden_time > 12.0:
		g.crime_points = 0
		g.changed.emit()
	if g.stars == 0: return
	var evasion_seconds: float = g.police_evasion_seconds()
	if g.hidden_time > evasion_seconds:
		if g.stars <= 1:
			g.clear_wanted(true)
			g.message.emit("Você despistou a polícia.")
		else:
			g.crime_points = g.STAR_THRESHOLDS[g.stars - 1]
			g.update_stars()
			g.hidden_time = 0.0
			if g.police_case != null: g.police_case.descending = true
			g.changed.emit()
		return
	g.dispatch_timer -= delta
	if not g.dispatch_owned and g.dispatch_timer <= 0 and g.police.size() < g.MAX_ACTIVE[g.stars] and g.deployed < g.DEPLOYMENT[g.stars]:
		g.dispatch_timer = g.DISPATCH[g.stars]
		g.spawn_officer()

func spawn_officer() -> CharacterBody3D:
	if g.dispatch_owned: return null
	if not g.last_known_valid: return null
	for attempt in 16:
		var angle: float = g._rng.randf_range(0, TAU)
		var point: Vector3 = g.last_known + Vector3(cos(angle), 0, sin(angle)) * 16.0
		point.y = g.last_known.y + 0.05
		# No fundo do túnel do canal o círculo de 16 m cai quase todo dentro da
		# terra: o policial nasce ao longo do eixo do túnel, no piso da rampa.
		var tunnel := preload("res://world/urban_detail/CanalTunnel3D.gd")
		if tunnel.below_grade(g.last_known):
			point = Vector3(g.last_known.x + (16.0 if attempt % 2 == 0 else -16.0), 0.0, tunnel.CENTER_Z)
			point.y = tunnel.floor_y(point.x) + 0.05
		if not g.clear_at(point): continue
		var floor_ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP, point - Vector3.UP * 2.0, 1)
		var floor_hit := g.get_world_3d().direct_space_state.intersect_ray(floor_ray)
		if floor_hit.is_empty(): continue
		var unit := OFFICER.new()
		unit.controller = g
		unit.tier = clampi(g.stars - 2, 0, 4)
		unit.last_known = g.last_known
		g.add_child(unit)
		unit.global_position = floor_hit.position + Vector3.UP * 0.05
		g.police.append(unit)
		g.deployed += 1
		return unit
	return null

func clear_wanted(keep_investigation: bool = false) -> void:
	# A fuga deixa as aeronaves livres para terminar de descer o esquadrão e ir embora.
	# Custódia, respawn e restauração de save encerram explicitamente a resposta antiga.
	if not keep_investigation and is_instance_valid(g.police_air): g.police_air.clear_response()
	if g.police_case != null and not keep_investigation: g.police_case.reset()
	elif g.police_case != null: g.police_case.escalation = g.police_case.ESCALATION.new()
	g.stars = 0
	g.crime_points = 0
	g.hidden_time = 0
	g.deployed = 0
	g.last_known_valid = false
	for unit in g.police:
		if is_instance_valid(unit): unit.queue_free()
	g.police.clear()
	g.changed.emit()

## V1 `ensure_minimum_wanted_level(2)`: ferir um policial nunca pode deixar o
## jogador abaixo de 30 pontos. Uma procura maior não recebe pontos artificiais
## a cada pelota ou tique contínuo.
func _report_police_assault(victim: Node3D) -> void:
	if not is_instance_valid(victim): return
	var missing := maxi(0, g.STAR_THRESHOLDS[2] - g.crime_points)
	g.register_crime(missing, victim.global_position, "police_assault")

## V1 `report_officer_killed`: depois da agressão soma pelo menos 30 pontos e
## chega ao piso de 60. O id impede duplicação entre origens de dano.
func _report_police_killed(victim: Node3D) -> void:
	if not is_instance_valid(victim): return
	var id := victim.get_instance_id()
	if g._police_kill_reported.has(id): return
	g._police_kill_reported[id] = true
	g.register_crime(maxi(30, g.STAR_THRESHOLDS[3] - g.crime_points), victim.global_position, "police_killed")
