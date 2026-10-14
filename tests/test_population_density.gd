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
	# Com GETECO_POP_VC ligado (padrão desde a P1, 2026-10-13) os tetos de projeto são 25 pedestres e 16 carros;
	# os mesmos fatores de densidade e de área valem sobre eles. Desligado volta aos 40/40 antigos.
	var vc: bool = WORLD.population_vc_enabled
	world.requested_population = 40
	world.density_scale = 1.0
	check(world._population_cap() == (WORLD.VC_MAX_POPULATION if vc else 40) and world._traffic_cap() == (WORLD.VC_TRAFFIC_TARGET if vc else WORLD.TRAFFIC_TARGET),"escala 1 mantém os tetos de projeto")
	world.density_scale = WORLD.DENSITY_MIN
	check(world._population_cap() == (10 if vc else 16) and world._traffic_cap() == (7 if vc else 16),"piso de 40% reduz os tetos")
	var market := WORLD.area_density_target("harbor",Vector3(107,0,23))
	var neighborhood := WORLD.area_density_target("harbor",Vector3(320,0,-22))
	check(market.x > market.y,"mercado preserva mais pedestres que trânsito")
	check(neighborhood.x > market.x and neighborhood.y > market.y,"bairro comporta mais população que o trecho carregado do mercado")
	check(WORLD.area_density_target("harbor",Vector3(145,0,200)).x < neighborhood.x,"orla industrial tem menos pedestres que o bairro")
	var border_a := WORLD.area_density_target("harbor",Vector3(165,0,50))
	var border_b := WORLD.area_density_target("harbor",Vector3(165.01,0,50))
	check(border_a.distance_to(border_b) < .001,"perfil espacial é contínuo na borda do mercado")
	world.area_density_scale = market
	check(world._population_cap() == (10 if vc else 16) and world._traffic_cap() == (7 if vc else 16),"emergência e área não multiplicam a redução")
	world.density_scale = 1.0
	check(world._population_cap() == (23 if vc else 36) and world._traffic_cap() == (12 if vc else 28),"mercado mantém 90% dos pedestres e 70% dos carros civis sem emergência")
	world.area_density_scale = WORLD.area_density_target("mountain",Vector3.ZERO)
	check(world._population_cap() == (15 if vc else 24) and world._traffic_cap() == (12 if vc else 28),"montanha respeita os tetos inteiros sem arredondamento float32")
	world.area_density_scale = WORLD.area_density_target("desert",Vector3.ZERO)
	check(world._population_cap() == (18 if vc else 28) and world._traffic_cap() == (13 if vc else 32),"deserto respeita os tetos inteiros sem arredondamento float32")
	check(WORLD.area_density_target("other",Vector3(107,0,23)) == Vector2.ONE,"outras regiões não herdam o perfil geográfico do porto")
	world.requested_population = 0
	check(world._population_cap() == 0,"perfil não cria população quando explicitamente desativada")
	world.free()
	print("POPULATION_DENSITY failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
