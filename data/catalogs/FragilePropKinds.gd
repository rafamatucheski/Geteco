extends RefCounted
## Tabelas dos adereços que o carro derruba: perfil por tipo (KINDS), altura padrão do poste (POST_HEIGHT),
## massa (MASSES) e os tipos leves e fofos (SOFT_KINDS). Saíram de gameplay/street_physics/FragileProps3D.gd
## em 01/11 (só dados, para o dono caber na leitura); o dono reexporta as quatro com o mesmo nome, então
## FRAGILE.KINDS/MASSES (testes, editor de mundo, CityChunkDressing) não mudam. A razão de cada número
## continua ao lado dele.

## raio de contato, perda de velocidade do carro ao atravessar, dano no carro.
## fall_speed é a velocidade de APROXIMAÇÃO (componente na direção do poste, StreetPhysics._hit_props),
## não a do velocímetro: num choque a 45° do centro o carro precisa de ~1,4× esse valor.
## Playtest 29/10 ("tudo tá bem difícil de derrubar"): poste 6 → 4,5 m/s (16 km/h) e semáforo
## 8 → 6 m/s (22 km/h). Abaixo de ~4 m/s continua manobra de estacionar: o poste balança e segura
## o carro (test_slow_post_block cobre 0,4/2/4 m/s). Ambos seguem ancorados (16/10): tombam na
## base em qualquer velocidade, nunca saem voando.
## "sound" é o material do som (playtest 30/10, VehicleCrashAudio.PROP_VOICE): pole (chapa de poste e
## placa), can (lata/tambor), bag (saco, papelão, rede), plastic (plástico duro, pneu), wood, glass,
## concrete; "metal" fica só para o que é grande como carro (caçamba, moto) e usa a batida de veículo.
const KINDS := {
	"lamp": {"family": "post", "radius": 0.22, "drag": 0.30, "damage": 8.0, "sound": "pole", "anchored": true, "fall_speed": 4.5},
	"signal_pole": {"family": "post", "radius": 0.25, "drag": 0.35, "damage": 10.0, "sound": "pole", "anchored": true, "fall_speed": 6.0},
	"stop_sign": {"family": "post", "radius": 0.12, "drag": 0.06, "damage": 2.0, "sound": "pole"},
	"hydrant": {"family": "hydrant", "radius": 0.2, "drag": 0.18, "damage": 5.0, "sound": "pole"},
	"trash_can": {"family": "light", "radius": 0.3, "drag": 0.03, "damage": 0.0, "sound": "can"},
	"news_box": {"family": "light", "radius": 0.45, "drag": 0.05, "damage": 1.0, "sound": "pole"},
	"mailbox": {"family": "light", "radius": 0.3, "drag": 0.06, "damage": 1.0, "sound": "pole"},
	"phone_booth": {"family": "post", "radius": 0.5, "drag": 0.22, "damage": 6.0, "sound": "glass"},
	"bench_seat": {"family": "light", "radius": 1.4, "drag": 0.12, "damage": 3.0, "sound": "wood"},
	"dumpster": {"family": "light", "radius": 1.2, "drag": 0.16, "damage": 4.0, "sound": "metal"},
	"trash_bags": {"family": "light", "radius": 0.6, "drag": 0.01, "damage": 0.0, "sound": "bag"},
	"planter": {"family": "light", "radius": 0.78, "drag": 0.18, "damage": 5.0, "sound": "concrete"},
	"barrel": {"family": "light", "radius": 0.37, "drag": 0.04, "damage": 1.0, "sound": "can"},
	"pallet": {"family": "light", "radius": 1.2, "drag": 0.05, "damage": 1.0, "sound": "wood"},
	"desert_rock": {"family": "light", "radius": 1.1, "drag": 0.20, "damage": 7.0, "sound": "concrete"},
	"harbor_tree": {"family": "post", "radius": 0.4, "drag": 0.18, "damage": 5.0, "sound": "wood", "fall_speed": 3.0, "anchored": true},
	"desert_tree": {"family": "light", "radius": 0.4, "drag": 0.10, "damage": 3.0, "sound": "wood"},
	# Pinheiro de 8-13 m da mata (FishingWoodland/HarborCoastWoodland): tronco de 25-39 cm pede mais
	# que a árvore de calçada. Caído fica no chão (keep_fallen): sumir por transparência levaria
	# o material da mata ao passe alfa, pipeline que nenhum pré-aquecimento cobre.
	"woodland_tree": {"family": "post", "radius": 0.45, "drag": 0.25, "damage": 6.0, "sound": "wood", "fall_speed": 5.0, "anchored": true, "keep_fallen": true},
	# Placa de curva/divisa e balizador da serra (MountainTrafficSigns, MountainRoadside3D): mesmos
	# números da stop_sign. Ancorada e caída fica (keep_fallen): o destroço rígido (stop_sign a 16 m/s)
	# e o sumiço por transparência levariam o material da placa ao passe alfa, que nenhum
	# pré-aquecimento cobre (placa da 3ª onda num quadro de 864 ms, DestroyedFade3D). Volta de pé
	# quando a beira de estrada da serra é remontada.
	"mountain_sign": {"family": "post", "radius": 0.12, "drag": 0.06, "damage": 2.0, "sound": "pole", "anchored": true, "keep_fallen": true},
	# Placa de trânsito de beira de rua fora do CityLook (A-32b do Harbor em HarborTrafficSigns, aviso
	# de queda de pedras da passagem norte do deserto). Mesmos números e razões da mountain_sign: a face
	# é alpha scissor, então nada de destroço rígido nem sumiço por transparência; volta de pé quando o
	# trecho é remontado.
	"road_sign": {"family": "post", "radius": 0.12, "drag": 0.06, "damage": 2.0, "sound": "pole", "anchored": true, "keep_fallen": true},
	# Chão povoado do deserto (DesertGroundCover): moita grande e pedra solta.
	"desert_shrub": {"family": "light", "radius": 0.55, "drag": 0.04, "damage": 0.0, "sound": "wood"},
	"desert_stone": {"family": "light", "radius": 0.45, "drag": 0.18, "damage": 2.0, "sound": "concrete"},
	"desert_gravel": {"family": "light", "radius": 0.15, "drag": 0.0, "damage": 0.0, "sound": "concrete"},
	"desert_grass": {"family": "light", "radius": 0.25, "drag": 0.0, "damage": 0.0, "sound": "wood"},
	# Térreo da calçada (SidewalkFill): plástico, madeira e lata que o carro espalha.
	"cafe_set": {"family": "light", "radius": 0.85, "drag": 0.04, "damage": 0.5, "sound": "plastic"},
	"cafe_parasol": {"family": "light", "radius": 0.9, "drag": 0.05, "damage": 0.5, "sound": "wood"},
	"produce_stand": {"family": "light", "radius": 0.9, "drag": 0.05, "damage": 0.5, "sound": "wood"},
	"a_frame": {"family": "light", "radius": 0.35, "drag": 0.01, "damage": 0.0, "sound": "wood"},
	"beer_crates": {"family": "light", "radius": 0.45, "drag": 0.02, "damage": 0.0, "sound": "glass"},
	"pot_plant": {"family": "light", "radius": 0.38, "drag": 0.04, "damage": 0.5, "sound": "concrete"},
	"wheelie_bins": {"family": "light", "radius": 0.7, "drag": 0.03, "damage": 0.0, "sound": "plastic"},
	"bike_rack": {"family": "light", "radius": 1.2, "drag": 0.06, "damage": 1.0, "sound": "pole"},
	"pallet_stack": {"family": "light", "radius": 0.75, "drag": 0.06, "damage": 1.0, "sound": "wood"},
	"tire_stack": {"family": "light", "radius": 0.75, "drag": 0.04, "damage": 0.5, "sound": "plastic"},
	"drums": {"family": "light", "radius": 0.65, "drag": 0.06, "damage": 1.0, "sound": "can"},
	"cafe_parasol_b": {"family": "light", "radius": 0.9, "drag": 0.05, "damage": 0.5, "sound": "wood"},
	"food_cart": {"family": "light", "radius": 0.9, "drag": 0.1, "damage": 2.0, "sound": "pole"},
	"ice_freezer": {"family": "light", "radius": 0.6, "drag": 0.12, "damage": 2.0, "sound": "pole"},
	"clothes_rack": {"family": "light", "radius": 0.8, "drag": 0.02, "damage": 0.0, "sound": "pole"},
	"flower_buckets": {"family": "light", "radius": 0.7, "drag": 0.02, "damage": 0.0, "sound": "can"},
	"gas_cylinders": {"family": "light", "radius": 0.55, "drag": 0.05, "damage": 1.0, "sound": "pole"},
	"door_bench": {"family": "light", "radius": 0.65, "drag": 0.04, "damage": 0.5, "sound": "wood"},
	"motorcycle": {"family": "light", "radius": 1.0, "drag": 0.18, "damage": 4.0, "sound": "metal"},
	# Objetos soltos da rua (StreetJunk, 29/10): saco, papelão, caixote, rede e cadeira cedem quase sem
	# segurar o carro; entulho e caçamba de entulho pesam (seguram e amassam mais).
	"bag_single": {"family": "light", "radius": 0.35, "drag": 0.005, "damage": 0.0, "sound": "bag"},
	"bag_pile": {"family": "light", "radius": 0.75, "drag": 0.02, "damage": 0.0, "sound": "bag"},
	"bag_torn": {"family": "light", "radius": 0.6, "drag": 0.005, "damage": 0.0, "sound": "bag"},
	"cardboard": {"family": "light", "radius": 0.65, "drag": 0.01, "damage": 0.0, "sound": "bag"},
	"refuse_heap": {"family": "light", "radius": 1.05, "drag": 0.05, "damage": 0.5, "sound": "bag"},
	"wood_crates": {"family": "light", "radius": 0.7, "drag": 0.05, "damage": 1.0, "sound": "wood"},
	"fish_crates": {"family": "light", "radius": 0.7, "drag": 0.03, "damage": 0.5, "sound": "plastic"},
	"rusty_barrels": {"family": "light", "radius": 0.72, "drag": 0.08, "damage": 1.5, "sound": "can"},
	"rope_coil": {"family": "light", "radius": 0.55, "drag": 0.03, "damage": 0.0, "sound": "bag"},
	"fishing_net": {"family": "light", "radius": 0.8, "drag": 0.02, "damage": 0.0, "sound": "bag"},
	"loose_tires": {"family": "light", "radius": 0.65, "drag": 0.04, "damage": 0.5, "sound": "plastic"},
	"rubble": {"family": "light", "radius": 0.85, "drag": 0.15, "damage": 2.0, "sound": "concrete"},
	"rubble_skip": {"family": "light", "radius": 1.6, "drag": 0.35, "damage": 8.0, "sound": "metal"},
	"beach_parasol": {"family": "light", "radius": 0.5, "drag": 0.02, "damage": 0.0, "sound": "wood"},
	"beach_parasol_b": {"family": "light", "radius": 0.5, "drag": 0.02, "damage": 0.0, "sound": "wood"},
	"beach_chairs": {"family": "light", "radius": 0.85, "drag": 0.02, "damage": 0.0, "sound": "pole"},
	"plastic_chairs": {"family": "light", "radius": 0.55, "drag": 0.02, "damage": 0.0, "sound": "plastic"},
	"bar_table": {"family": "light", "radius": 1.0, "drag": 0.04, "damage": 0.5, "sound": "plastic"},
}

## Altura padrão quando a malha não diz (lote-pivô vazio sem peças, nó sem MeshInstance3D).
const POST_HEIGHT := {"lamp": 6.0, "signal_pole": 5.5, "stop_sign": 2.6, "road_sign": 2.6, "mountain_sign": 2.0,
	"harbor_tree": 5.0, "woodland_tree": 10.0, "phone_booth": 2.4}

## kg, com o conteúdo (lata com lixo, caçamba de aço, vaso com terra). O carro leva ~1200 kg.
## 29/10: lata 11→28, caçamba 100→320, sacos 5→9, vaso 90→300 e afins; leves demais
## somavam ao lançamento antigo e tudo voava como papel.
const MASSES := {"trash_can": 28.0, "news_box": 45.0, "mailbox": 60.0, "hydrant": 60.0, "bench_seat": 70.0, "dumpster": 320.0, "trash_bags": 9.0, "planter": 300.0, "desert_rock": 180.0, "desert_tree": 35.0, "desert_shrub": 8.0, "desert_stone": 60.0, "lamp": 90.0, "signal_pole": 120.0, "stop_sign": 18.0, "phone_booth": 200.0,
	"cafe_set": 14.0, "cafe_parasol": 18.0, "produce_stand": 40.0, "a_frame": 8.0, "beer_crates": 25.0, "pot_plant": 40.0, "wheelie_bins": 35.0, "bike_rack": 40.0, "pallet_stack": 90.0, "tire_stack": 50.0, "drums": 80.0,
	"cafe_parasol_b": 18.0, "food_cart": 90.0, "ice_freezer": 90.0, "clothes_rack": 15.0, "flower_buckets": 20.0, "gas_cylinders": 60.0, "door_bench": 20.0, "motorcycle": 180.0, "barrel": 40.0, "pallet": 22.0,
	# StreetJunk: a caçamba de entulho cheia (~1,4 t) só escorrega; o monte de entulho pesa como um vaso.
	"bag_single": 6.0, "bag_pile": 24.0, "bag_torn": 5.0, "cardboard": 8.0, "refuse_heap": 45.0, "wood_crates": 40.0, "fish_crates": 25.0, "rusty_barrels": 90.0,
	"rope_coil": 25.0, "fishing_net": 20.0, "loose_tires": 30.0, "rubble": 250.0, "rubble_skip": 1400.0, "beach_parasol": 8.0, "beach_parasol_b": 8.0,
	"beach_chairs": 10.0, "plastic_chairs": 12.0, "bar_table": 18.0}

## Leves e fofos: sobem um pouco, rolam e quicam (saco, papelão, rede, cadeira de plástico).
const SOFT_KINDS := ["trash_bags", "bag_single", "bag_pile", "bag_torn", "cardboard", "fishing_net", "a_frame",
	"plastic_chairs", "beach_chairs", "clothes_rack", "flower_buckets", "cafe_parasol", "cafe_parasol_b", "beach_parasol", "beach_parasol_b"]
