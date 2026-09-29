extends SceneTree

## Densidade dinâmica: o teto de pedestres e de trânsito civil cai com a emergência em cena
## (unidades de despacho e estrelas) e nunca passa dos limites de projeto.
const WORLD := preload("res://runtime/ProductionWorld.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if ok: return
	failures.append(message)
	push_error(message)

func _initialize() -> void:
	check(is_equal_approx(WORLD.density_target(0,0),1.0),"sem emergência o teto fica inteiro")
	check(is_equal_approx(WORLD.density_target(0,3),1.0),"3 estrelas sozinhas ainda não reduzem")
	check(WORLD.density_target(4,0) < WORLD.density_target(2,0),"mais unidades, teto menor")
	check(is_equal_approx(WORLD.density_target(10,0),WORLD.DENSITY_MIN),"muitas unidades chegam ao piso")
	check(WORLD.density_target(50,6) >= WORLD.DENSITY_MIN - .0001,"nunca abaixo do piso")
	check(WORLD.density_target(0,4) <= WORLD.DENSITY_STARS_SCALE + .0001,"de 4 estrelas para cima o teto é limitado")
	check(WORLD.density_target(1,5) <= WORLD.density_target(1,0),"estrelas nunca aumentam o teto")
	var world = WORLD.new()
	world.requested_population = 40
	world.density_scale = 1.0
	check(world._population_cap() == 40 and world._traffic_cap() == WORLD.TRAFFIC_TARGET,"escala 1 mantém os tetos de projeto")
	world.density_scale = WORLD.DENSITY_MIN
	check(world._population_cap() == 16 and world._traffic_cap() == 16,"piso de 40% reduz para 16 de 40")
	world.free()
	print("POPULATION_DENSITY failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
