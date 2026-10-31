extends SceneTree
## Contratos puros de jogabilidade; o teste de sessão do fliperama cobre a tela e a sala reais.
const Pinball := preload("res://activities/arcade/games/PinballGame.gd")
const Blocks := preload("res://activities/arcade/games/BlocksGame.gd")
const Racer := preload("res://activities/arcade/games/RacerGame.gd")
const Fighter := preload("res://activities/arcade/games/FighterGame.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)

func ticks(game: RefCounted, count: int, controls: Dictionary = {}) -> void:
	for frame in range(count):
		game.step(1.0 / 60.0, controls)

func _run() -> void:
	# As strings do contrato não podem depender do idioma salvo do desenvolvedor.
	TranslationServer.set_locale("pt_BR")
	_test_pinball()
	_test_blocks()
	_test_racer()
	_test_fighter()
	_test_contract()
	for failure in failures:
		push_error(failure)
	print("ARCADE GAMES: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_pinball() -> void:
	var game := Pinball.new()
	game.reset(81)
	check(game.waiting and game.lives == 3 and not game.finished, "Pinball starts with three balls, waiting for launch")
	ticks(game, 60)
	check(game.waiting and game.ball == Vector2(553, 395), "Pinball does not launch without a button")
	game.step(0.016, {"action_pressed": true})
	check(not game.waiting and game.velocity.y < -500, "Pinball launch releases the ball upward")
	game.ball = Vector2(337, 112)
	game.velocity = Vector2(0, 300)
	game.step(0.025, {})
	check(game.score == 100 and game.velocity.y < 0.0, "A bumper reflects the ball and awards points once")
	# Encontra a raquete em movimento na altura atual, abaixo do campo de bumpers.
	game.ball = Vector2(350, 406)
	game.velocity = Vector2(0, 180)
	game.step(0.025, {"left": true})
	check(game.left_flipper and game.velocity.y < 0, "The powered left paddle sends the ball back upward")
	game.ball = Vector2(400,479)
	game.velocity = Vector2.DOWN*100
	game.step(.016,{})
	check(game.lives == 3 and game.velocity.y < 0, "Launch protection returns an early drain without consuming a ball")
	for lost in range(3):
		# Exercita uma perda de bola real depois do salva-bola existente de cinco segundos.
		game._save_time = 0.0
		game.waiting = false
		game.ball = Vector2(400, 479)
		game.velocity = Vector2.DOWN * 100
		game.step(0.016, {})
		check(game.lives == 2 - lost, "Each drain consumes exactly one ball")
	check(game.finished and game.status == "FIM DE JOGO", "Three drains end the pinball match")
	game.reset(81)
	game.step(0.016, {"action_pressed": true})
	for frame in range(1800):
		game.step(1.0 / 60.0, {"left": frame % 60 < 30, "right": frame % 45 < 23, "action_pressed": true})
	check(game.ball.is_finite() and game.velocity.is_finite() and game.lives >= 0, "Pinball remains finite during a 30-second input sequence")
	for seed_value in range(1, 9):
		game.reset(seed_value)
		game.step(1.0 / 60.0, {"action_pressed": true})
		var entered_field := false
		var minimum_y := game.ball.y
		for frame in range(120):
			game.step(1.0 / 60.0, {})
			minimum_y = minf(minimum_y, game.ball.y)
			if game.ball.y < 270.0:
				entered_field = true
				break
			if game.lives < 3:
				break
		check(entered_field and game.lives == 3, "Natural pinball launch reaches bumper field before draining (seed %d, minimum y %.1f, lives %d)" % [seed_value, minimum_y, game.lives])

func _test_blocks() -> void:
	var game := Blocks.new()
	game.reset(41)
	check(game.board.size() == 18 and game.board[0].size() == 10, "Falling blocks uses a 10 by 18 board")
	var first_piece := game.piece
	var first_next := game.next_piece
	game.reset(41)
	check(game.piece == first_piece and game.next_piece == first_next, "Identical seeds reproduce the opening pieces")
	for kind in range(7):
		for turns in range(4):
			var unique: Dictionary = {}
			for cell in game.cells(kind, turns):
				unique[cell] = true
			check(unique.size() == 4, "Each piece and rotation has four distinct cells")
	game.piece = 2
	game.origin = Vector2i(3, 4)
	game.step(0.016, {"action_pressed": true})
	check(game.rotation == 1, "Action rotates the active piece")
	ticks(game, 240, {"left": true})
	check(game._fits(game.origin, game.rotation), "Held horizontal input cannot leave the board")
	game.reset(7)
	game.step(0.016, {"action_alt_pressed": true})
	var occupied := 0
	for row in game.board:
		occupied += 10 - row.count(0)
	check(occupied == 4 and game.score > 0, "Hard drop locks exactly four blocks and awards distance points")
	game.reset(7)
	for y in [16, 17]:
		game.board[y].fill(1)
		game.board[y][4] = 0
		game.board[y][5] = 0
	game.piece = 1
	game.rotation = 0
	game.origin = Vector2i(3, 16)
	game.step(0.016, {"action_alt_pressed": true})
	check(game.lines == 2 and game.score == 300, "Completing two rows clears both with the two-line award")
	check(game.board.size() == 18 and game.board[17].count(0) == 10, "Clearing rows preserves board size and adds empty rows")
	game.reset(9)
	game.board[0].fill(1)
	game.piece = 1
	game.rotation = 0
	game.origin = Vector2i(3, -1)
	game.step(0.1, {"action_alt_pressed": true})
	check(game.finished, "A locked piece above the ceiling ends the match without negative indexing")

func _test_racer() -> void:
	var game := Racer.new()
	game.reset(17)
	game.step(.1,{"steering":.5})
	var half_lane: float = game.lane
	game.reset(17)
	game.step(.1,{"steering":1.0})
	check(is_equal_approx(game.lane,half_lane*2), "Half analog steering produces half the lateral movement")
	game.reset(17)
	check(game.rivals.size() == 6 and game.rank == 7, "Race begins with six rivals plus the player")
	ticks(game, 120, {"up": true})
	check(game.speed > 100 and game.distance > 100, "Acceleration increases speed and advances the race")
	var speed_before := game.speed
	ticks(game, 30, {"down": true})
	check(game.speed < speed_before, "Braking reduces speed")
	var nitro_before := game.nitro
	ticks(game, 30, {"action": true, "action_alt": true})
	check(game.nitro < nitro_before and game.boosting, "Boost consumes a finite nitro supply")
	ticks(game, 400, {"right": true})
	check(absf(game.lane) <= 1.4 and game.speed >= 0, "Roadside steering remains bounded")
	game.reset(17)
	game.distance = 1000
	game.speed = 200
	game.rivals[0]["distance"] = 1001.0
	game.rivals[0]["lane"] = 0.0
	game.step(0.016, {"up": true})
	check(game.collisions == 1 and game.speed < 100, "A rival contact slows the player and records one impact")
	game.reset(17)
	game.distance = Racer.RACE_LENGTH - 1
	game.speed = 248
	game.step(0.016, {"up": true})
	check(game.finished and game.status.contains("CHEGADA") and game.rank == 1, "Crossing the finish resolves placing and the final score")
	game.reset(17)
	ticks(game, 60 * 49)
	check(game.finished and game.status == "TEMPO ESGOTADO", "Failing to finish before the timer ends the race")
	game.reset(17)
	for frame in range(60 * 47):
		var target := -0.3
		for rival in game.rivals:
			var gap: float = float(rival["distance"]) - game.distance
			if gap > -45 and gap < 135 and absf(float(rival["lane"]) - target) < 0.3:
				target = 0.34 if float(rival["lane"]) < 0.1 else -0.36
		game.step(1.0 / 60.0, {"up": true, "action_alt": game.distance > 2200, "left": game.lane > target + 0.04, "right": game.lane < target - 0.04})
		if game.finished:
			break
	check(game.finished and game.status.contains("CHEGADA"), "The complete course is finishable with ordinary acceleration and steering")

func _test_fighter() -> void:
	var game := Fighter.new()
	game.reset(11)
	game.step(.1,{"steering":.5})
	check(is_equal_approx(game.player_x,233.5), "Analog walking preserves partial stick movement")
	game.reset(11)
	check(game.player_health == 100 and game.enemy_health == 100, "Fighters start with full health")
	game.player_x = 320
	game.enemy_x = 400
	game._enemy_cooldown = 10
	game.step(0.016, {"action_pressed": true})
	ticks(game, 7)
	check(game.enemy_health == 90 and game.score == 120, "A punch hits once and awards damage points")
	ticks(game, 30)
	check(game.enemy_health == 90, "A completed punch does not apply damage repeatedly")
	game.reset(11)
	game.player_x = 320
	game.enemy_x = 440
	game._enemy_cooldown = 10
	game.step(0.016, {"action_alt_pressed": true})
	ticks(game, 9)
	check(game.enemy_health == 83, "A kick reaches farther and deals its distinct damage")
	game.reset(11)
	game.player_x = 320
	game.enemy_x = 400
	game.enemy_windup = 0.01
	game.step(0.02, {"down": true})
	check(game.player_health == 98 and game.blocking, "Defending reduces a landed enemy attack to chip damage")
	game.reset(11)
	game.player_x = 320
	game.enemy_x = 400
	game.enemy_windup = 0.01
	game.step(0.02, {})
	check(game.player_health == 89, "An undefended enemy punch removes eleven health")
	game.reset(11)
	game.step(0.016, {"up_pressed": true})
	ticks(game, 8)
	check(game.player_height > 36, "Jump raises the player above the enemy strike")
	ticks(game, 60)
	check(game.player_height == 0, "Jump lands back on the arena floor")
	game.reset(11)
	game.enemy_health = 10
	game.player_x = 320
	game.enemy_x = 400
	game._enemy_cooldown = 10
	game.step(0.016, {"action_pressed": true})
	ticks(game, 8)
	check(game.finished and game.status == "VITÓRIA!" and game.score >= 1000, "Defeating the opponent ends the round with a victory award")
	game.reset(11)
	ticks(game, 60 * 20)
	check(game.finished and game.status == "DERROTA", "The opponent closes distance and can defeat an idle player")

func _test_contract() -> void:
	for script in [Pinball, Blocks, Racer, Fighter]:
		var game: RefCounted = script.new()
		game.reset(4)
		check(not game.title().is_empty() and not game.instructions().is_empty(), "Every game exposes a title and functional controls")
		game.finished = true
		game.score = 431
		game.step(0.1, {"action_pressed": true, "action_alt_pressed": true, "up": true})
		check(game.score == 431 and game.finished, "Finished games ignore gameplay input until reset")
		game.reset(4)
		check(game.score == 0 and not game.finished, "Reset cleanly starts a replay")
