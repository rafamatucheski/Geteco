extends SceneTree
## Decisões sociais mais cápsulas reais de moradores, recuo diante de ameaça e o atraso
## existente da evidência policial. Profundidade visual/FPS são validados na fixture de sessão.
const SOCIAL := preload("res://gameplay/civilian_social/CivilianSocialState.gd")
const RESIDENT := preload("res://world/places/harbor_buildings/HarborBuildingResident.gd")
const REACTION := preload("res://gameplay/civilian_reactions/WorkplaceThreatReaction.gd")
const DIRECTOR := preload("res://gameplay/police_response/PoliceCaseDirector.gd")
var checks := 0
var failures: Array[String] = []

class State extends RefCounted:
	var place_id := "social_test_room"
	var region_id := "harbor"
	func weapons_allowed() -> bool: return true

class Gameplay extends Node3D:
	signal weapon_fired(id: String, point: Vector3)
	signal npc_gunfire(point: Vector3, direction: Vector3, shooter: Node3D)
	signal explosion_occurred(point: Vector3, radius: float, source: Node)
	signal changed
	var player: Node3D
	var state := State.new()
	var health := 100.0
	var stars := 0
	var contact_age := 0.0
	var world: Node3D
	var police_case: Node
	var aim_active := false
	var weapon := "fists"
	var points := 0
	var emergency: Node
	var direction := Vector3.RIGHT
	func equipped() -> String: return weapon
	func weapon_data(id: String) -> Dictionary: return {"is_melee":id == "fists"}
	func _aim_direction() -> Vector3: return direction
	func report_observed_crime(amount: int, point: Vector3, kind: String, victim: Node3D = null) -> bool:
		return police_case.observe(amount, point, kind, victim)
	func register_crime(amount: int, _point: Vector3, _kind: String, _testimony: Dictionary = {}) -> void:
		points += amount
		stars = 1
	func report_contact(_point: Vector3) -> void: pass

class Stage extends Node3D:
	var gameplay: Node

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("BUILDING_SOCIAL ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)

func solid(parent: Node3D, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	parent.add_child(body)
	return body

func run() -> void:
	create_timer(45).timeout.connect(func(): quit(3))
	var social := SOCIAL.new()
	social.configure({"name":"Lia", "identity":0, "activity":"cook"})
	check(social.begin(), "peaceful worker accepts attention")
	var greeting := social.interact("greet")
	check(greeting.ok and greeting.state == "happy" and social.trust == 1, "greeting creates happiness and trust")
	check(not social.interact("greet").ok and social.trust == 1, "button repeat cooldown prevents duplicated mood gain")
	social.advance(1.5)
	social.interact("greet")
	social.advance(1.5)
	check(social.interact("greet").state == "annoyed", "repeated interruption causes irritation")
	social.finish()
	social.advance(6.0)
	check(social.state == "calm", "worker returns to routine after conversation")
	social.routine_clock = 15.6
	social.advance(.3)
	check(social.routine_phase == "pause", "routine includes a bounded working break")
	social.frightened(8.0)
	var comfort := social.interact("reassure")
	check(comfort.ok and comfort.state == "recovering", "unarmed reassurance calms residual fear")
	social.advance(6.0)
	check(social.state == "calm", "reassurance returns worker to calm")
	check(not social.interact("chat", true).ok and social.state == "scared", "visible weapon blocks friendly banter")
	social.advance(6.0)
	var intimidation := social.interact("intimidate")
	check(intimidation.ok and intimidation.close and intimidation.report, "explicit threat closes conversation and requests one report")
	social.advance(12.0)
	check(not social.interact("intimidate").report, "threat report cooldown avoids police point farming")
	social.advance(.25, false, true)
	check(social.state == "calling_police" and not social.can_interact(), "pending testimony owns call state and blocks dialogue")
	check(not social.interact("reassure").ok, "reassurance cannot erase an ongoing police report")
	var reserved := SOCIAL.new()
	reserved.configure({"identity":1})
	check(reserved.interact("joke").state == "annoyed", "reserved personality differs from friendly reactions")
	var stage := Stage.new()
	root.add_child(stage)
	var gameplay := Gameplay.new()
	stage.gameplay = gameplay
	stage.add_child(gameplay)
	var director := DIRECTOR.new()
	director.configure(gameplay)
	gameplay.police_case = director
	gameplay.add_child(director)
	solid(stage, Vector3(0, -.1, 0), Vector3(20, .2, 20))
	var wall := solid(stage, Vector3(1.0, 1.0, 0), Vector3(.2, 2.0, 4))
	var resident := RESIDENT.new()
	resident.specification = {"id":"social_worker", "name":"Lia", "identity":0, "activity":"read"}
	resident.position = Vector3(2.0, .03, 0)
	stage.add_child(resident)
	var player := CharacterBody3D.new()
	player.position = Vector3(0, .03, 0)
	stage.add_child(player)
	gameplay.player = player
	var reaction := REACTION.install(resident, resident.resident_model, gameplay)
	resident.configure_social(gameplay, reaction, false)
	await physics_frame
	await physics_frame
	check(not resident.begin_social(player), "wall blocks conversation even inside interaction radius")
	gameplay.weapon = "pistol"
	gameplay.aim_active = true
	resident.social_routine._process(2.0)
	check(director.pending.is_empty() and not reaction.active, "wall prevents aim perception and unjustified police calls")
	wall.queue_free()
	await physics_frame
	await physics_frame
	player.position.y = 4.0
	resident.social_routine._process(2.0)
	check(director.pending.is_empty() and not reaction.active, "armed player on another floor cannot threaten this resident")
	player.position.y = .03
	gameplay.weapon = "fists"
	resident.social_routine._process(2.0)
	check(director.pending.is_empty() and not reaction.active, "empty hands never count as armed aim")
	gameplay.aim_active = false
	gameplay.weapon = "pistol"
	resident.social_routine._process(.3)
	check(resident.social_snapshot().state == "scared" and director.pending.is_empty(), "carrying weapon causes fear without inventing a crime")
	gameplay.weapon = "fists"
	resident.social_routine._process(7.0)
	check(resident.begin_social(player), "peaceful player can talk after weapon is put away")
	var start := resident.global_position
	var result := resident.social_interact("intimidate", player)
	check(result.ok and reaction.active and not resident.social_snapshot().can_interact, "threat interrupts native work and social controls immediately")
	check(director.pending.size() == 1 and gameplay.points == 0, "threat uses pending witness evidence instead of instant stars")
	resident.social_routine._process(.3)
	check(resident.social_snapshot().state == "calling_police" and resident.social_phone.visible and not resident.prop.visible, "caller holds real phone and hides interrupted work prop")
	check(resident.test_move(resident.global_transform, Vector3.DOWN * .1), "native resident capsule is supported by physical floor")
	for index in 25: await physics_frame
	check(resident.global_position.distance_to(start) > .1 and resident.is_on_floor(), "scared resident retreats using actual body movement")
	director.tick(2.4)
	check(gameplay.points == 0, "unfinished call cannot assign wanted points")
	director.tick(.2)
	check(gameplay.points == 12 and director.pending.is_empty(), "completed testimony reaches the existing police director once")
	await create_timer(12.0).timeout
	check(not reaction.active and resident.global_position.distance_to(start) < .08, "quiet recovery walks back to the interrupted station")
	var recovered: Dictionary = resident.social_snapshot()
	print("BUILDING_SOCIAL_RECOVERED ", JSON.stringify({"social":recovered, "clock":resident.social_routine.social.routine_clock,
		"fear_left":resident.social_routine.social.fear_left, "reaction_active":reaction.active, "prop":resident.prop.visible}))
	# Recuo/volta e recuperação emocional são distintos. O medo é mantido enquanto
	# o perigo ou uma denúncia por telefone está ativo e depois decai a partir do valor retido.
	# Mede esse valor uma vez; um timer travado não pode estender este prazo de novo.
	var residual: float = resident.social_routine.social.fear_left
	check(residual >= 0.0 and residual <= 10.0 and recovered.state in ["scared", "recovering", "calm"], "returning to the post may retain a bounded fear reaction")
	var recovery_window := maxf(residual, float(resident.social_routine.social.state_left)) + .35
	await create_timer(recovery_window).timeout
	recovered = resident.social_snapshot()
	check(recovered.state == "calm" and not resident.social_phone.visible and resident.prop.visible == (recovered.routine == "work"), "recovered resident resumes its work or authored break with matching props")
	# Uma pausa agendada dura 3.5 segundos do ciclo de trabalho de 19 segundos. É um
	# estado válido da rotina, mas também precisa terminar e mostrar o prop de trabalho de novo.
	if recovered.routine == "pause": await create_timer(4.0).timeout
	check(resident.prop.visible and resident.social_snapshot().state == "calm", "routine break finishes and native activity prop returns")
	# Um sólido atrás do trabalhador bloqueia o segmento inteiro de fuga. Mantém o
	# posto autoral; não teleporta por cima da mobília para simular fuga.
	var furniture := solid(stage, resident.global_position + Vector3(1.0, 1.0, 0), Vector3(.8, 2.0, 3.0))
	await physics_frame
	await physics_frame
	var no_escape: Vector3 = reaction._retreat_target(player.global_position)
	check(no_escape.distance_to(resident.global_position) < .01, "furniture blocks every swept escape choice and leaves actor in safe position")
	furniture.queue_free()
	await physics_frame
	await physics_frame
	# Uma mira curta é interrompida por uma parede. A duração parcial dela não pode ser reaproveitada
	# quando o jogador aparece do outro lado ou volta a ficar à vista.
	# O cooldown do evento verbal anterior não tem relação com este novo caso de mira.
	resident.social_routine.social.threat_cooldown = 0.0
	gameplay.weapon = "pistol"
	gameplay.aim_active = true
	for index in 3: resident.social_routine._process(.3)
	check(director.pending.is_empty(), "brief armed aim has a grace interval before a report")
	wall = solid(stage, Vector3(1.0, 1.0, 0), Vector3(.2, 2.0, 4))
	await physics_frame
	await physics_frame
	resident.social_routine._process(.3)
	check(resident.social_routine._aim_seconds == 0.0 and director.pending.is_empty(), "losing sight cancels the unfinished aim report")
	wall.queue_free()
	await physics_frame
	await physics_frame
	# Um novo evento hostil precisa ser visto de novo pelo intervalo de tolerância completo.
	var second := RESIDENT.new()
	second.specification = {"id":"social_neighbor", "identity":3, "activity":"phone"}
	second.position = Vector3(3.8, .03, 1.0)
	stage.add_child(second)
	second.configure_social(gameplay, REACTION.install(second, second.resident_model, gameplay), false)
	for index in 6:
		resident.social_routine._process(.3)
		second.social_routine._process(.3)
	check(director.pending.size() == 1 and director.pending[0].points == 12, "sustained visible armed aim creates exactly one testimony")
	check(second.social_snapshot().state == "calling_police", "second witness shares the same call instead of adding another offense")
	for index in 8: resident.social_routine._process(.3)
	check(director.pending.size() == 1 and director.pending[0].points == 12, "continuous aim does not multiply the same report")
	gameplay.weapon_fired.emit("pistol", player.global_position)
	gameplay.report_observed_crime(4, player.global_position, "gunfire")
	resident.social_routine._process(.3)
	check(director.pending.size() == 2 and director.pending[1].kind == "gunfire" and director.pending[1].points == 4, "social fear reuses the real gunfire report without duplicating the offense")
	second.free()
	director.reset()
	gameplay.points = 0
	director.observe(6, player.global_position, "intimidation", resident)
	resident.dead = true
	resident.social_routine._process(.3)
	director.tick(2.6)
	check(gameplay.points == 0 and not resident.social_snapshot().can_interact and not resident.social_phone.visible, "dead witness cannot finish call or remain interactive")
	stage.queue_free()
	await process_frame
	check(get_nodes_in_group("building_resident").is_empty(), "unloading the room releases social residents")
	print(JSON.stringify({"test":"building_social_reactions", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
