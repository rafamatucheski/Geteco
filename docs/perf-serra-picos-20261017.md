# Serra: picos de quadro > 33 ms — 17/10/2026

Rota `serra` do `ReleaseBenchmark` (4 pontos em (650..745, -290..-425), 12 m/s, 1 volta de aquecimento e 2 medidas),
export release, `HARBOR_STALL_LOG=1`, pela fila `tools/run_godot_locked.sh`. A/B por variável de ambiente no **mesmo
export**, rodadas intercaladas. Tabelas em `evidence/perf-cross-20261015/{ursos,grama}_20261017_*.tsv`, JSONs em
`%APPDATA%/GetecoV2/benchmark-west/`, logs de sessão em `%APPDATA%/GetecoV2/session-logs/20261017-1[01]*`.

A máquina estava mais lenta que de manhã (p50 entre 5,1 e 7,3 ms em vez dos 3,4 ms do export 17g às 02h); por isso só
valem comparações dentro do mesmo bloco de rodadas. Os p50 abaixo não devem ser comparados com os do
`docs/perf-exe-20261017.md`.

## Causa 1: urso recriado a cada volta (pico de 57-90 ms, 3 por rodada)

- Evidência: no export 17h o pico de cada volta (t≈9, 46, 83 s) traz o span `wildlife.bear_spawn` de 22-29 ms e mais
  ~30 ms sem span logo depois (`late_to_render_pre`). As duas tocas (`MountainWildlife.DENS`, em (810,-322) e
  (782,-382)) ficam a mais de `DESPAWN_RADIUS` (160 m) do início da rota: a cada volta os 4 ursos eram destruídos e
  remontados, ~90 `MeshInstance3D` e ~90 `StandardMaterial3D` novos por urso.
- Correção: os 4 ursos são montados uma vez no `_ready` da fauna (sob a cortina) e **estacionados** fora do raio
  (`MountainBear3D.park()`: escondido e com processo desligado, o que tira o corpo do espaço de física). Na volta à toca,
  `wake()` os põe no chão, curados, como na V1. `GETECO_BEAR_POOL=0` volta ao jeito antigo; `GETECO_WILDLIFE=0` (diagnóstico)
  não monta fauna nenhuma.
- Medição (export `artifacts/export-20261017-ursos`, 2 rodadas por cenário; picos contados no log da sessão, aquecimento incluído):

| cenário | picos do urso | pior quadro ms | quadros > 33 ms (benchmark) |
|---|---|---|---|
| estacionamento | 0, 0 | 52,8; 66,0 | 19; 27 |
| `GETECO_BEAR_POOL=0` | 3, 3 | 70,4; 90,2 | 14; 24 |
| `GETECO_WILDLIFE=0` | 0, 0 | 50,0; 49,6 | 15; 12 |

  Com o estacionamento o caso fica igual ao sem ursos. A contagem de quadros > 33 ms quase não muda porque ela era
  dominada pela causa 2 (abaixo), igual nos três cenários.

## Causa 2: montagem da grama da serra num passo de física (28-45 ms, 12-22 por rodada)

- Evidência: um único passo de física de 28-45 ms a cada ~0,6 s, de (745,-381) por toda a perna (745→671, -425), em
  todas as voltas. Os sistemas instrumentados somavam < 1 ms. Pela ordem do laço do Godot, os probes de
  `SessionSystemProfile` cercam só os `_physics_process` de script, então era um script sem span. Não eram os ursos (sem
  fauna continua igual) nem os marcadores de esqui (span `ski.course_markers` nunca passou de 2 ms; `GETECO_SKI_MARKER_RAYS=0`
  manteve 12-13 quadros > 33 ms). A pilha nativa (`HARBOR_STALL_STACKS=1`) não ajudou: o binário oficial não tem símbolos
  e só dá `GetecoV2.exe+offset`.
- Causa: `MountainGrass3D._build_tile` testa até 324 pontos por bloco de 16 m (reserva, altura e um raio de física cada) e
  montava 2 blocos inteiros por passo de física. Em chão sem neve, cada fileira nova de blocos à frente do jogador
  custava um passo inteiro.
- Correção: a amostragem é fatiada em `BUILD_BUDGET_USEC` (2 ms) por passo de física, retomando de onde parou. O bloco
  só aparece quando termina, com os mesmos pontos (mesma ordem de sorteio). Span `mountain.grass.build`.
  `GETECO_GRASS_SLICED=0` volta aos 2 blocos inteiros por passo.
- Medição (export `artifacts/export-20261017-grama`, que já inclui a causa 1; 2 rodadas de cada):

| cenário | p50 ms | p95 ms | p99 ms | pior ms | > 33 ms | passos de física lentos |
|---|---|---|---|---|---|---|
| fatiada r1 | 5,13 | 10,55 | 13,36 | 54,46 | 1 | 0 |
| fatiada r2 | 5,45 | 10,11 | 12,31 | 56,81 | 1 | 0 |
| inteira r1 (`GETECO_GRASS_SLICED=0`) | 5,62 | 10,36 | 15,54 | 42,19 | 17 | 22 |
| inteira r2 | 5,34 | 9,22 | 14,01 | 46,55 | 12 | 17 |

  O maior span `mountain.grass.build` na rodada fatiada ficou em ~2,0 ms.

## Causa 3: fontes de calor do frio montadas no `_process` (t≈107,6 s, 47 ms)

- Evidência: o quadro de 54-57 ms de t≈107,6 s tinha `early_to_late` ~47 ms e nenhum span. `early_to_late` mede só os
  `_process` dos nós (os passos de física caem em `post_render_to_next_callback`). Uma sonda temporária por subárvore
  (uma marca como primeiro filho de cada nó de `/root`, de `World3D` e dos contêineres dentro dele; prioridade igual
  processa em ordem de árvore) pôs 43,6 e 44,9 ms, nas duas rodadas em que o pico caiu, entre `/root/World3D/Fishing`
  (sem `_process`) e o nó seguinte, `ColdSurvival`. O `_process` dele chama `HeatPresentation.update_sources`, que
  monta inteiro (fogo, pedras/braseiro, colisão) cada fonte de calor ao entrar no raio de 80 m e a libera ao sair.
  Perto de (656,-371) ficam a fogueira do lago (`smuggler_camp`, 34 m) e o abrigo da patrulha (26 m).
- O pico é intermitente: caiu em 10 de 15 rodadas sem a correção (todas as de 17/10 na rota, exports grama a calor). Coincide com o summit_suv que o estacionamento de
  beira de estrada põe na vaga `snow_0` só na 3ª volta. Uma rodada com `--no-roadside-parking` não teve o pico, mas
  essa relação não foi explicada (veja "Não verificado").
- Correção: as 7 fontes são montadas uma vez sob a cortina (`HeatPresentation.prewarm`, chamado em
  `ColdSurvival.configure`) e, fora do raio, **estacionadas** (escondidas, colisão zerada, processo desligado) em vez
  de liberadas. A variante "invólucro" (fonte já fornecida pelo trecho) é montada na 1ª vez e também reaproveitada.
  Span `cold.heat_source.build` em qualquer montagem em jogo. `GETECO_HEAT_POOL=0` volta ao jeito antigo.
- Medição (export `artifacts/export-20261017-calor`, intercalado):

| cenário | p50 ms | p95 ms | p99 ms | pior ms | > 33 ms | quadro ~47 ms em `_process` (~107 s) | montagens em jogo |
|---|---|---|---|---|---|---|---|
| pool r1 | 4,89 | 9,41 | 11,57 | 45,49 | 1 | não | 0 |
| `GETECO_HEAT_POOL=0` r1 | 4,93 | 9,64 | 11,92 | 58,58 | 1 | sim (108,2 s, 47,5 ms) | 9,3 e 5,5 ms |
| pool r2 | 5,03 | 9,60 | 11,82 | 49,64 | 1 | não | 0 |
| `GETECO_HEAT_POOL=0` r2 | 6,45 | 11,80 | 14,51 | 63,33 | 1 | não (intermitente) | 12,3 e 8,8 ms |

  Com pool não houve montagem em jogo e nem o quadro de 47 ms. O quadro que ainda passa de 33 ms nas rodadas com pool
  é **outro** (abaixo). Dois sorteios sem o pico, num caso que aparece em ~2/3 das rodadas, ainda deixam ~1 chance em
  9 de ser acaso: o nome da causa vem da sonda, não só do A/B.

## Também corrigido de passagem: cabine medida pela GPU (8,5-8,9 ms em t≈4,2 s)

- `VehicleInterior._derive` lia os vidros com `surface_get_arrays` (volta da GPU) na 1ª vez que o jogador chegava a
  1,8 m de um modelo (`Driving._process` → `INTERIOR.prewarm` → `spec`). Agora os vértices dos vidros de cada modelo da
  frota são lidos sob a cortina (`_prewarm_fleet_shaders` → `VehicleInterior.cache_glass`) e o recorte da porta
  herda o cache ao trocar a malha. Span `vehicle.interior.spec`; `GETECO_INTERIOR_SPEC_CACHE=0` volta ao antigo.
- Medição (export `artifacts/export-20261017-interior`, intercalado): `vehicle.interior.spec` de 8,5 e 8,9 ms com o
  interruptor desligado, nenhum span ≥ 2 ms com o cache (2 rodadas de cada). Não era o pico de 107 s.

## O que sobra (não resolvido)

- **Passo de física de 40-43 ms sem span no começo da 3ª volta** (t≈82-87 s, jogador em (705,-296) ou (745,-312),
  perto das tocas): `physics_callback_ms` 40-43 em 1 passo. Apareceu em 3 de 5 rodadas recentes, com e sem o pool de
  calor. Suspeita, não provada: os ursos estacionados acordando (`MountainBear3D.wake`, commit 62797e0b) ao voltar ao
  raio da toca. É hoje o quadro > 33 ms que sobra dentro da medição.
  **Ursos descartados (17/10, 1 rodada, export `builds/bearphys`):** com `wildlife.bear_physics` (span de
  `MountainBear3D._physics_process`, `finish_slow` ≥ 5 ms) o pico apareceu em t≈135 s com 49,8 ms em 1 passo, mas os
  ursos tinham acordado em t≈122 s (`wildlife.bear_wake` 0,2 ms) e no passo do pico nenhum span de script de física
  passou de 0,4 ms (urso 0,16 ms, veículo 0,40 ms). O único passo lento do urso foi o 1º depois do 1º despertar (4,5 ms,
  t≈48 s). Então o custo está fora dos scripts medidos: passo nativo da física (Jolt) ou um `_physics_process` sem span.
  Próximo passo: span em volta de `PhysicsServer3D` (ou contar corpos ativos/pares no passo) e cobrir os demais
  `_physics_process` da serra. Uma rodada só: o horário do pico varia entre rodadas.
- Primeira volta (aquecimento, fora da medição mas depois de jogável): `stream.mountain.surfaces` de 27-35 ms em
  t≈13,8 s em toda rodada, e 1-2 quadros de 33-36 ms em `render_bracket` em t≈4,5 e 16,6 s.
- t≈114 s, ~40-45 ms em `post_render`: fim do benchmark (gravação do resultado), fora da medição.
- Com a causa 3 corrigida o pior quadro da medição ficou em 45-50 ms (o passo de física acima), não 54-58 ms.

## Não verificado

- Grama: só a rota a pé a 12 m/s. Dirigindo rápido, os blocos aparecem mais devagar que antes (2 ms por passo em vez de
  2 blocos inteiros); não olhei se o capim surge visivelmente atrasado ao lado do carro.
- Ursos: o comportamento depois de acordar (ataque, filhotes, morte e renascimento) não foi testado no jogo.
  `tests/test_mountain_bears.gd` já estava quebrado antes desta mudança: a viagem para a serra é recusada na sessão de
  teste, e com `--play-at` a fauna não aparece (0 ursos com e sem `GETECO_BEAR_POOL`). Ajustei o teste para o
  estacionamento (visível = presente, ursa volta curada), mas ele não roda até o ambiente de teste ser consertado.
- Os erros de motor `Condition "p_elem->_root" is true` (6 por execução) aparecem com e sem o estacionamento: não vêm
  desta mudança, e a origem não foi investigada.
- Fontes de calor: não olhei no jogo se a fogueira estacionada reaparece certa (fogo animando, colisão) ao voltar;
  `tests/cold/test_admission.gd` passou (11 verificações). Por que o pico só caía com o estacionamento de beira de
  estrada ligado não foi explicado; a montagem da fonte não teve span lento no quadro de 47 ms do cenário antigo, então
  o passo exato dentro de `ColdSurvival._process` (montagem, troca de invólucro ou descarte) não foi isolado.
- Exports pararam de sair sozinhos depois de gravar o pacote (4 de 6); usei `GODOT_RUN_TIMEOUT=240` no export.
- Nada disso foi olhado no jogo (`Jogar.cmd`) por uma pessoa.
