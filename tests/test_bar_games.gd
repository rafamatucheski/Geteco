extends SceneTree
const GAME := preload("res://world/places/bars/BarGames.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	check(GAME.dart_score(Vector2.ZERO) == 50,"Bull must score 50")
	check(GAME.dart_score(Vector2(0,-.07)) == 25,"Outer bull must score 25")
	check(GAME.dart_score(Vector2(0,-.595)) == 60,"Treble twenty must score 60")
	check(GAME.dart_score(Vector2(0,-.96)) == 40,"Double twenty must score 40")
	check(GAME.dart_score(Vector2(0,-1.01)) == 0,"Outside board must miss")
	var game = GAME.new()
	game.reset("bar_darts")
	for index in 9: check(game.shoot(),"Nine legal darts")
	check(game.finished and game.score == 450,"Nine bulls end at 450")
	check(not game.shoot() and game.shots == 9,"Finished game rejects tenth dart")
	game.reset("bar_pool")
	check(game.score == 0 and not game.finished and game.balls.size() == 7,"Reset clears previous game")
	check(game.shoot() and not game.shoot(),"Pool rejects shot while moving")
	var transferred := false
	for frame in 1500:
		game.step(1.0/120)
		for index in range(1,game.balls.size()):
			if game.balls[index].velocity.length() > 5: transferred = true
		if not game.moving: break
	check(transferred,"Cue shot must transfer momentum to target balls")
	check(not game.moving,"Balls must settle in a finite time")
	game.reset("bar_pool")
	game.balls[1].position = Vector2(10,10)
	game.moving = true
	game.step(1.0/120)
	check(game.sunk == 1 and game.score == 100 and game.balls[1].sunk,"Object ball sinks and scores exactly once")
	game.step(.1)
	check(game.score == 100,"Pocket cannot duplicate score")
	game.balls[0].position = Vector2(10,10)
	game.moving = true
	game.step(1.0/120)
	check(game.scratches == 1 and not game.balls[0].sunk,"Cue scratch restores cue for next shot")
	check(game.score == 100-GAME.SCRATCH_PENALTY,"Cue scratch costs the penalty")
	check(game.balls[0].position.x == 100,"Cue restored inside baulk area")
	game.reset("bar_pool")
	for a in game.balls.size():
		for b in range(a+1,game.balls.size()):
			check(game.balls[a].position.distance_to(game.balls[b].position) >= 20,"Rack balls must not overlap")
	game.balls[0].position = Vector2(10,10)
	game.moving = true
	game.step(1.0/120)
	check(game.score == 0,"Penalty never drives the score negative")
	game.shots = 10
	game.moving = true
	game.step(1.0/120)
	check(game.finished,"Ten pool shots end round")
	print("BAR_GAMES: %s"%("PASS" if failures == 0 else "%d failures"%failures))
	quit(0 if failures == 0 else 1)
