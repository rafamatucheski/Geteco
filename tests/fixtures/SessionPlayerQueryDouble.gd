extends RefCounted
## Mesmas leituras da fachada de jogador do FullSession (player_position, player_health...) para
## os dublês de sessão dos testes. Os dublês guardam `world` como Dictionary, Node3D ou classe
## interna; o parâmetro sem tipo mantém a leitura dinâmica, como a cadeia
## session.world.player/gameplay/driving que o jogo usava antes da fachada.

static func position(world) -> Vector3: return world.player.global_position
static func local_position(world) -> Vector3: return world.player.position
static func health(world) -> float: return world.gameplay.health
static func in_vehicle(world) -> bool: return world.driving.occupied
static func vehicle(world): return world.driving.car
