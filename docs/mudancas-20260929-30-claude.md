# Mudanças da sessão Claude, 29/09–30/09/2026

Só o que esta sessão fez, com o commit de cada parte. Nada foi enviado (sem push). Tudo abaixo passou
nos testes citados; **nada foi validado jogando** além de capturas e sondas. A coluna "Validar no jogo"
é o roteiro para você.

## 1. Motocross: dia de corrida (`31cdeb1`)

Grade de largada com giro (holeshot, empinada, largada lenta), nota de pouso com dica de inclinação no HUD,
tempos por ponto de controle e diferença para o rival, anúncios, etiquetas, cartão de classificação,
recorde da pista salvo (`best_lap`), treino cronometrado, estacas refeitas (as antigas flutuavam), fita,
fardos, arquibancada com 5 torcedores, placar, faixas e tenda de mecânico. Detalhes: `docs/motocross.md`,
`evidence/motocross/README.md`, teste `tests/test_motocross_raceday.gd`.

Validar no jogo: largar segurando W (faixa verde), pousar inclinando W/S, terminar uma prova e ver o cartão,
passar perto do parque sem travada.

## 2. Frota de veículos

| Commit | O quê |
|---|---|
| `a5eda2d`, `f59278b` | `tools/fleet_ingest/ingest_glb_car.gd`: prepara um carro de IA (GLB) no formato da frota (rodas soltas, vidro, faróis, lanternas). Mirage de teste em `assets/fleet/incoming/` (**não está no catálogo**). |
| `743e69f` | Aurora Executive: os 248 triângulos dos flancos estavam invertidos (lateral preta de lado); vidro, faróis, linhas de porta, placa; 110 → 55 peças. |
| `39f65de`, `f009b21` | `runtime/FleetSpeedPass.gd` para a frota inteira: junta peças de roda, fixas, tinta, vidro e luzes; corrige casco sem laterais (16 modelos); linhas de porta. 4579 → 2707 peças. |
| `d8081b5` | O passe custava 30–58 ms por carro nascido; agora o plano de fusão é cacheado por modelo. `--no-fleet-pass` desliga. |

Validar no jogo: **vista de lado dos 16 carros com casco corrigido** (`atlas_crew_pickup`, `beach_buggy`,
`bravio_crew`, `dock_delivery_van`, `dune_buggy`, `lumber_pickup_4x4`, `medic_box`, `orbita_micro`,
`porto_rosso`, `ranch_pickup`, `ranch_single`, `sertao_trail_pickup`, `snow_plow_truck`, `surf_woody_wagon`,
`vale_crossover`, `vertice_midengine`), rodas girando/esterçando, troca de cor e carro de duas cores,
faróis dos dois lados à noite, abrir porta. Se algum carro quebrar, é só excluir o id em
`FleetSpeedPass.decorate`.

## 3. Picos de quadro (travadas)

Ferramenta: `tests/measure/probe_region_hitches.gd` (atravessa porto → costura → montanha; opções
`--per-script`, `--diff-nodes`, duas voltas). Resultados em `evidence/region-hitches/`.

| Commit | O quê |
|---|---|
| `079095f` | Pista de motocross montava em 1,4 s num quadro → etapas por quadro; `nearest()` com grade; liberação de chunk em fatias. |
| `20c2478` | `prepare_collision_at` só constrói o chão (era 41–73 ms por chamada); suspensão de veículo respeita o lado da costura. |
| `050b239` | Liberação de chunk desce até subárvores pequenas; vegetação da montanha retomável. |
| `9f7715e` | Bancos de motor (17 famílias, 1,4 s) carregam em segundo plano: some o pico de ~1 s do começo. |
| `13b2346` | Vila e serraria da montanha em cache entre visitas. |
| `292b459` | Costura (100–170 → ~50 ms), começo da rota (etapas do cenário do motocross), ursos um por quadro, `union_plaza` em cache. |

Na mesma rota: quadros acima de 40 ms 43–51 → 25–29; máximo típico 123–160 ms (era 1.375 ms).

## 4. Avisos

- **Três linhas de outra sessão foram perdidas** em `world/regions/NativeRegion.gd`
  (`_suspend_chunk_vehicles`) quando um erro meu esvaziou o arquivo. Refiz a lógica de
  `tests/test_region_vehicle_suspension.gd` (passa), mas confira se a versão original difere.
- `FleetCatalog.gd`, `VehicleFinish.gd`, `LootablePortContainer.gd` e outros têm alterações **de outras
  sessões** no diretório de trabalho; não foram incluídas nos meus commits.
- Ainda existe uma parada rara de 0,7–1,4 s (1 em ~3 rodadas da sonda), com o tempo em física/espera e
  sem script lento; ver `evidence/region-hitches/README.md`.
- `test_fleet_finish` falha em `bike_police` e `army_tank` (modelos que não toquei).
