# F — Integração, benchmark e correções — 2026-10-13

Tarefa final do plano `docs/otimizacao-paralela-20261013.md`: medir P1–P9 juntas, de forma controlada,
corrigir o que a medição mostrou e preparar o export para o teste do usuário.

## Como foi medido

`tests/measure/benchmark_west_route.gd`, Godot 4.7.2 .NET **no editor** (não headless), 3440×1440,
RTX 4060 Laptop. Circuito fixo no oeste do porto a 12 m/s, 1 volta de aquecimento e 2 medidas, v-sync
desligado, sem limite de fps, sem despacho. Um Godot por vez; os interruptores entram por ambiente.
O benchmark ganhou `--hora=`, `--chuva`, `--max-passos=` e grava no JSON todos os interruptores e o motor
de física. JSONs em `evidence/benchmark-west/` (fora do Git). Uma rodada tem ruído de ~±1 ms no p50.

O circuito move o carro do jogador sem física: mede trânsito, pedestres, cidade e render, não a direção
nem caos/perseguição.

## Resultado final (tempo de quadro, ms)

| Rodada | p50 | p95 | p99 | GPU p50 | Veículos / pessoas |
|---|---:|---:|---:|---:|---|
| Tudo desligado, dia, rodada 1 | 16,02 | 31,98 | 49,98 | 4,65 | 38 / 36 |
| Tudo desligado, dia, rodada 2 | 13,65 | 17,92 | 25,11 | 3,80 | 37 / 36 |
| **Tudo ligado, dia, rodada 1** | **8,86** | **13,47** | **18,89** | 2,57 | 21 / 14 |
| **Tudo ligado, dia, rodada 2** | **10,16** | **15,85** | **20,97** | 2,72 | 21 / 11 |
| Ligado sem fantoche (`GETECO_PED_DUMMY=0`) | 9,22 | 14,60 | 20,09 | 2,70 | 21 / 10 |
| Ligado sem trilhos (`GETECO_TRAFFIC_RAILS=0`) | 8,68 | 12,91 | 17,43 | 2,54 | 21 / 11 |

Noite e chuva (rodadas anteriores às correções abaixo, população ainda errada no ligado):
desligado 14,2–14,5 / 15,8 ms p50 contra ligado 9,8 / 10,4 ms.

Leitura: ~35% menos tempo de quadro típico e a cauda (p99) de 25–50 ms para ~19–21 ms. A maior parte vem
de menos trânsito e pedestres (P1); P6, P7 e P8 deram ~1,2–1,4 ms cada e P4/P9 ~0,5 ms cada, na rodada de
um interruptor por vez. Sombra a 55 m, P5, trilhos e fantoche ficaram dentro do ruído neste circuito.

## Defeitos que a medição encontrou e foram corrigidos

1. **P1 esvaziava a rua (3 pessoas).** O anel de 30 m do reVC não serve para a nossa câmera a ~30 m de
   altura no ultrawide: quase tudo até 30 m está na tela, então ninguém nascia. Agora nasce fora da tela até
   55 m, some fora da tela além de 60 m ou na tela além de 95 m (`ProductionWorld.gd`). Rua com 10–16 pessoas.
2. **P3 custava ~2 ms.** Forçava pose todo quadro em 38 de 46 corpos (rotina, conversa, mão dirigida,
   controle automático), inclusive fora da tela. Esses voltaram à cadência anterior; só jogador, impacto,
   queda, morte e combate ficam todo quadro (`CivilianModel.gd`). Ficou neutra.
3. **P2 custava ~4 ms com 37 carros.** O trilho desligava o LOD antigo (o carro distante passava a rodar
   motorista e sensores todo passo) e testava todos os vizinhos duas vezes por passo. Agora o trilho segue a
   cadência do LOD, testa perigo uma vez por passo e usa grade de 16 m para vizinhos (`Vehicle.gd`,
   `TrafficRails.gd`). Ficou neutra; não há ganho medido com 21 carros.

## Novos nesta tarefa

- **Pedestre fantoche** (`Actor.gd`, `GETECO_PED_DUMMY=0` desliga): pedestre comum fora da tela (margem
  de 3 m do quadro) segue a rota da calçada sem desvio, degrau nem `move_and_slide`, acompanhando a altura
  de rampas da rota. Volta à física ao entrar na tela. Neutro neste circuito.
- **Grade de vizinhança** nos trilhos (acima).

## Testado e descartado

Rodada única cada, tudo ligado: base 8,98 ms p50; Jolt 12,6; Jolt + 3 passos 11,9; GodotPhysics com no
máximo 3 passos 13,8 (essa teve um erro de script `emission_energy_multiplier` em Nil, não investigado).
Jolt fica mais lento no nosso padrão (muitas consultas pequenas de GDScript ao `direct_space_state`).
Nada foi alterado no projeto.

## Testes

Com tudo ligado, passaram: `test_regions`, `test_bridge_approach_terrain`, `test_native_driving`,
`cold/test_admission`, `test_traffic_rails` (61 ligado / 10 desligado), `test_edited_traffic_drive`
(também desligado), `test_vehicle_effects`, `test_vehicle_equipment`, `test_population_density` (ligado e
`GETECO_POP_VC=0`), `test_citizen_route_clipping`, `test_civilian_blocked_retry`, `test_crowd_avoidance`,
`test_desert_population`, `test_harbor_life`, `test_jessica_pedestrian_queue`,
`test_pedestrian_vehicle_danger`.

Falham **igual com fantoche e trilhos desligados** (anteriores a esta tarefa, não investigados):
`test_civilian_reactions` (13 casos, começando por "Gameplay aceita o disparo"),
`test_civilian_shot_resume_independent` (saída 2), `test_civilian_varied_reactions`,
`test_arrival_street_path`.

Mudanças em testes: `test_population_density` passou a esperar os tetos 25/16 quando `GETECO_POP_VC`
está ligado; `test_traffic_rails` espera o passo executado pelo LOD (`tick_executed`) e o limite do passo de
retorno passou de 0,3 para 0,5 m, o mesmo do modo desligado, porque o trilho agora anda na cadência do LOD.

## Não verificado

Export release (próximo passo), caos/perseguição, direção e moto, aparência temporal (pop-in de
pedestres a 55–95 m, sombra a 55 m, faróis, rastros, prédios assados a 50 m), outras regiões além do oeste
do porto.
