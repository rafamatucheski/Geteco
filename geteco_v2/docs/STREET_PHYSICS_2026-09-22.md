# Física de rua (StreetPhysics) — 22/09/2026

Porte da V1 para 3D nativo, com melhorias: atropelamento, postes e mobília
derrubáveis, batida entre carros, sangue no chão e rastro de sangue. Tudo novo
fica em `gameplay/street_physics/`.

## Pontos de entrada

| Arquivo | O que foi acrescentado |
|---|---|
| `scripts/Vehicle.gd` | `STREET.vehicle_pre_move(self,delta)` antes do `move_and_slide`; `STREET.vehicle_post_move(self,incoming_velocity,delta)` depois do laço de contato |
| `runtime/ProductionWorld.gd` | cria o nó `StreetPhysics` depois do `CityLook` |
| `world/city_look/CityChunkDressing.gd` | registra postes (com a mancha de luz) e a mobília do CityLook como quebráveis |

Nenhum gancho em `Gameplay.gd`: o sangue de tiro, faca e explosão vem de um
observador que compara a vida dos corpos a cada 0,2 s (civil, polícia, Cobra,
socorrista e o próprio jogador via `Gameplay.health`).

## Fonte V1 → V2

| V1 | V2 | Números mantidos (px/s ÷ 16) |
|---|---|---|
| `guns/combat/VehiclePersonImpact.gd` + `AnimatedPedestrian3D.get_run_over` | `StreetPhysics._hit_people` + `BodyFlight3D` | atropela a partir de 3,75 m/s; morte a partir de 12,5 m/s; voo a 85% da velocidade, freio 59 m/s²; carro atravessa |
| `geodata/StreetLamp.gd`, `FixedTrafficSignal`, `BreakableProp` (`fragile_road_post`) | `FragileProps3D` | balança 0,94–2,2 m/s; tomba ≥2,2 m/s em 0,7 s até ~88°, apaga, perde colisão |
| `guns/combat/GroundBlood.gd` | `GroundBlood3D` | 64 manchas, 5 cadáveres, 18 s + 6 s de fade, escurece em 12 s, 4 perfis de forma |
| `BodyWound`/`BodyWoundTrail` | `StreetPhysics._wound` | 6 s sangrando, gota a cada 1,15 s se andou 1,75 m |
| `BloodTransferSystem` | `BloodTracks3D` | resíduo por distância: pneu 13 m, sapato 5,3 m; marca vive 14 s |

## Melhorias sobre a V1

- **Voo com arco e giro** no eixo do impacto, até 2 quiques, parada em parede
  por raio (nunca atravessa); o dano entra no pouso, então a queda da V2 roda
  uma vez só e crime/socorro saem pelo `receive_damage` com o carro como fonte.
- **Sobrevivente levanta**: com o paramédico (vida ≥ 60) ou sozinho após 45 s
  (na V1 ficava no chão se o incidente saísse do orçamento).
- **Batida carro × carro com momento**: o atingido é empurrado no rumo do
  choque e roda conforme o ponto de contato; tráfego atingido para de seguir a
  faixa por ~2,4 s e depois retoma. Vidro quebrado acima de 7 m/s, tremor de
  câmera no carro do jogador.
- **Hidrante vira gêiser** por ~14 s, com poça que cresce e seca (não existia na V1).
- **Lixeira/jornaleiro/caixa de correio voam e rolam**; lixeira espalha lixo.
- **Rastro contínuo** em qualquer velocidade (cada marca cobre o trecho
  andado) e num único MultiMesh em anel de 700 marcas.

## Verificado

Sonda renderizada (`--no-save --no-traffic`, fora do repositório): atropelamento
a 14 m/s mata e arremessa ~6 m, carro segue (29 m), poça + respingo + rastro de
pneu; 6 m/s derruba sem matar (vida 17); poste tomba a 9 m/s; hidrante jorra;
batida lateral a 12 m/s empurra o outro carro ~5–8 m; tiro não letal deixa poça
e gotas enquanto a pessoa anda. Capturas conferidas visualmente.

## Não feito / limites

- **Jogador atropelado pelo tráfego** continua só com dano (sem voo): voo do
  jogador exige travar entrada e câmera, fora deste escopo.
- **Moto e ciclista caindo** (V1 `_finish_rider_fall`) não foi portado: a V2 não
  tem moto no tráfego.
- A mobília derrubada volta ao lugar quando o chunk é recarregado (a V1 usava
  `WorldRenewal`; aqui é o próprio streaming).
- Objetos derrubados não têm colisão depois de caídos (poste no chão não
  bloqueia carro), igual à V1.
- Desempenho não medido em tempo de quadro. Custos por construção: a varredura
  de atropelamento só faz shape cast com alguém a menos de ~5 m do carro; o
  observador de vida roda a 5 Hz.
