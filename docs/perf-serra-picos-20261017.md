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

## O que sobra (não resolvido)

- **t≈107,6 s, 54-57 ms**: `early_to_late` ~47 ms sem span, uma vez por rodada, no mesmo instante nas duas rodadas
  fatiadas (3ª volta, perna (660,-425)→(650,-290)). É o único quadro > 33 ms que fica dentro da medição. Causa não
  identificada; precisa de span no processo (o candidato óbvio é o streaming de um trecho, mas não foi provado).
- Primeira volta (aquecimento, fora da medição mas depois de jogável): `stream.mountain.surfaces` de 27-35 ms em
  t≈13,8 s em toda rodada, e 1-2 quadros de 33-36 ms em `render_bracket` em t≈4,5 e 16,6 s.
- t≈114 s, ~40-45 ms em `post_render`: fim do benchmark (gravação do resultado), fora da medição.
- Por isso o pior quadro não caiu (54-57 ms): ele vem do item de t≈107,6 s, não das causas acima.

## Não verificado

- Grama: só a rota a pé a 12 m/s. Dirigindo rápido, os blocos aparecem mais devagar que antes (2 ms por passo em vez de
  2 blocos inteiros); não olhei se o capim surge visivelmente atrasado ao lado do carro.
- Ursos: o comportamento depois de acordar (ataque, filhotes, morte e renascimento) não foi testado no jogo.
  `tests/test_mountain_bears.gd` já estava quebrado antes desta mudança: a viagem para a serra é recusada na sessão de
  teste, e com `--play-at` a fauna não aparece (0 ursos com e sem `GETECO_BEAR_POOL`). Ajustei o teste para o
  estacionamento (visível = presente, ursa volta curada), mas ele não roda até o ambiente de teste ser consertado.
- Os erros de motor `Condition "p_elem->_root" is true` (6 por execução) aparecem com e sem o estacionamento: não vêm
  desta mudança, e a origem não foi investigada.
- Nada disso foi olhado no jogo (`Jogar.cmd`) por uma pessoa.
