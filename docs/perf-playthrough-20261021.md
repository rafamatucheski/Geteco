# Partida do jogador de 21/10/2026: por que o FPS ficou baixo e o que foi feito

Queixa: "tá lento, FPS tá baixo, parece que tá muito pesado". Partida de ~13 min (21:18–21:31 local),
log `%APPDATA%/GetecoV2/session-logs/20261022-001835-902-17608-79a7a9cd/` (summary.json + 4 partes,
122 MB) e `evidence/stall-logs/stalls-20261021-211836.log`. Todos os tempos em milissegundos.

**Resumo.** O jogo rodou no binário do editor (GDScript de depuração, +38 % no p50 numa rota igual), com D3D12
(sem cache de pipeline no Godot 4.7.2: compilações de 0,1–1 s no meio do jogo, todo dia) e salvamentos de 22–34 ms
que viravam quadros > 33 ms. A placa não é o limite: a 3440x1440 com tudo no alto e chuva a GPU fica em 5–7 ms.
Feito: driver Vulkan no `project.godot`; salvamento 22 → 7,4 ms; preparo de porta de viatura sem leitura da GPU;
carregamento 1,3–4 s mais curto (frota em lote, orçamento maior só sob a cortina, Vulkan); oficina do Digo
265 → 147 ms; bancada de estresse nova. No estresse a 3440x1440 (chuva, 3 estrelas, perseguição, tiro, explosões,
25 m/s) o p50 ficou entre 6,8 e 9,8 ms em todas as rotas e os quadros > 33 ms caíram de 49 para 19 nas 5 rotas
(S5, uma rodada por lado); porto sem nenhum; deserto ainda tem um início de 170 ms. **A meta "nada > 33 ms" não
foi cumprida em 4 de 5 rotas** (seção 6). Para jogar: usar um export release (seção 4).

## 1. Como o jogo rodou na partida

- **Binário do editor** (`Godot_v4.7.2-stable_mono_win64.exe`, `debug_build=true`, `build_kind=editor`), aberto
  pelo `Jogar.cmd` → `JogarCSharp.cmd` → `Open.ps1`. GDScript roda com as verificações de depuração.
- Renderizador Forward+ com **D3D12** (`project.godot` desde 28237f5c), tela cheia **3440x1440** (monitor a
  159 Hz), v-sync ligado e teto de 144 fps até ~697 s (aí o jogador desligou o v-sync).
- Opções do jogador: sombra alta (atlas 8192, 80 m), reflexo/detalhe altos, SSAO e névoa volumétrica
  ligados, MSAA 2x, anisotropia 16x, glow 1,0 (`tools/bench/settings-jogador-3440.cfg` reproduz).
- `Jogar.cmd` (alterado, sem commit) liga `HARBOR_SESSION_LOG=1 HARBOR_SESSION_PROFILE=1 HARBOR_STALL_LOG=1
  HARBOR_STALL_STACKS=1`; `JogarCSharp.cmd` põe `HARBOR_MAX_PHYSICS_STEPS=3`.

### Tempo de quadro por situação (summary.json, quadros exatos)

| situação | duração | p50 | p95 | p99 | máx | > 33 ms |
|---|---|---|---|---|---|---|
| Harbor a pé (jogável) | 217 s | 8,8 | 14,5 | 21,2 | 149 | 38 |
| Harbor dirigindo | 220 s | 10,3 | 18,1 | 25,1 | 969 | 42 |
| Oficina do Maciota | 180 s | 7,7 | 10,5 | 11,6 | 164,5 | 9 |
| Banco | 58 s | 10,3 | 12,4 | 13,4 | 30,2 | 0 |
| Carregamento (`ready=False`, sob a cortina) | 25 s | 10,6 | 56,3 | 196,9 | 2214 | 100 |

O trecho `ready=False` é o carregamento: a cortina só sai em "Pronto" (71,4 s de sessão). O incidente de
2,2 s com `urban_ops.ready.village` (705 ms) e `urban_ops.ready.cargo_handling` (703 ms) acontece em
"Montando o porto", **sob a cortina** — custa tempo de carregamento, não FPS de jogo.

### Para onde vai o quadro normal (frame_history, ~19,6 mil quadros jogáveis em volta dos picos)

| situação | intervalo p50 / p95 | `_process` p50 / p95 | desenho (CPU) p50 | pós-desenho p50 / p95 (física de script) | GPU (média) |
|---|---|---|---|---|---|
| dirigindo na rua | 12,2 / 22,4 | 3,6 / 11,6 | 3,3 | 4,4 / 7,5 (3,4 / 5,3) | ~4,7 |
| a pé na rua | 9,8 / 18,1 | 3,1 / 8,7 | 3,1 | 3,8 / 5,9 (2,6 / 4,7) | ~4,6 |
| Maciota | 7,0 / 10,9 | 2,0 / 5,5 | 2,1 | 2,4 / 5,9 | ~2,8 |

A GPU ficou em ~4,7 ms mesmo a 3440x1440 com tudo alto: **o limite era a CPU**. Os spans de script por quadro
dirigindo são difusos (`vehicle.physics` 1,23 ms, `meshy.pose_driver` 0,31, `vehicle.effects` 0,24,
`vehicle.drive` 0,22, `vehicle.street_pre` 0,19, resto < 0,15 cada): não há um sistema único dominante; o
custo é o GDScript inteiro rodando no binário de depuração.

### Os 91 quadros > 33 ms jogáveis (sem pausa), por causa

| causa (span dominante / fase) | quadros | mediana | máx |
|---|---|---|---|
| streaming (`stream.harbor.record.building` 37–38, `dressing_step.12` 50, `south_port_model` 33, `original_facade` 14–20, `cemetery` 17) | 32 | 40,2 | 78,0 |
| **salvamento automático** (`session.save_game` 32–36 cada) | 24 | 54,0 | 164,0 |
| `_process` sem span (dirigindo, cidade) | 14 | 36,3 | 109,8 |
| pós-desenho sem span (física do motor / apresentação) | 10 | 44,2 | 76,3 |
| batida em poste (`street.crash`) e `vehicle.doors.prepare` | 4 | 52,4 | 54,6 |
| entrada em interior (banco 2×, escritório; sob o fade da porta) | 3 | 143,2 | 148,7 |
| compilação de pipeline no desenho (D3D12) | 2* | 968,6 | 968,6 |
| terminal rodoviário (`terminal.build`) | 1 | 41,1 | 41,1 |

\* o mesmo quadro de 969 ms aparece como `frame_spike` e no StallLog: `pipelines_delta` = 5 `surface` + 5
`specialization`, `setup_ms` 265, 942 ms dentro do desenho, thread principal esperando (`ntdll`, 100 % das
amostras do `StallStackSampler`) enquanto outra thread compila. Foi logo ao sair do Maciota de carro (~302 s).

- **Salvamento**: 29 salvamentos depois do carregamento, 32–36 ms cada no binário do editor, até **4 no mesmo
  quadro** (164 ms, ~195 s, dentro do Maciota). `SaveStore.save` interpretava e validava o JSON 3 vezes e
  rodava `GameState.restore_snapshot` 4 vezes por gravação (memória, temporário, principal e backup).
- **D3D12 não guarda cache de pipeline no Godot 4.7.2**: o binário só tem o caminho `user://vulkan/pipelines`
  e nenhuma chamada a `ID3D12PipelineLibrary`; em `%APPDATA%/GetecoV2` não existe cache D3D12. Cada sessão
  recompila todo pipeline, e o que não foi pré-aquecido compila no meio do jogo (aqui ~95 ms por pipeline).
- **Logs**: o custo na thread principal é pequeno mas existe — o perfil em GDScript (`SessionSystemProfile`)
  somou 11,6 s em 795 s (14,6 ms/s, ~1,5 % do tempo); o lado C# 1,4 s; callbacks do inventário de nós 0,17 s.
  Volume: 122 MB em 13 min (`context_update` 62 MB, `frame_history` 27 MB, `metrics` 18 MB), gravados em
  thread própria. O `StallStackSampler` só suspende a thread principal quando ela passa de 30 ms parada.

## 2. Medição em release (export, mesma máquina, 21–22/10)

Bancada: `ReleaseBenchmark` pelo `tools/run_godot_locked.sh`, sem v-sync nem teto (o benchmark desliga), uma rodada
por linha salvo indicado. Opções: `tools/bench/settings.cfg` (Média, 1280x720) ou as do jogador
(`tools/bench/settings-jogador-3440.cfg`, tela cheia 3440x1440; `settings-jogador-1080.cfg`, janela 1920x1080).
Exports: `artifacts/perf-playthrough-20261021/` (#1), `artifacts/perf-stress-20261021/` (#2),
`artifacts/perf-final-20261022/` (#3b; o #3 saiu quebrado, ver incidente na seção 5),
`artifacts/perf-final2-20261022/` (#4) e `artifacts/perf-final3-20261022/` (#5). JSON das rodadas em
`%APPDATA%/GetecoV2/benchmark-west/<rótulo>_<rota>_1.json` (rótulos `pt_*`, `pt2_*`, `st_*`, `s3_*`, `s5_*`);
registro das rodadas em `matrix.log` dentro de cada pasta. Os exports leem a árvore de trabalho, então incluem
mudanças não commitadas de outras sessões (Maciota, deserto, áudio) do momento do export.

### 2.1 Rota calma (oeste, câmera a 12 m/s, export #1): editor × release, D3D12 × Vulkan, resolução

| configuração | média | p50 | p95 | p99 | máx | > 33 ms | GPU p50 |
|---|---|---|---|---|---|---|---|
| **binário do editor**, D3D12, jogador 3440 | 8,85 | 8,95 | 12,51 | 14,66 | 28,4 | 0 | 4,66 |
| release D3D12, jogador 3440 (3 rodadas) | 6,94 / 7,13 / 6,99 | 6,32 / 6,40 / 6,57 | 10,12 / 10,12 / 9,63 | 11,96 / 11,71 / 11,09 | 22,5 / 76,3 / 19,6 | 0 / 1 / 0 | 4,5–4,9 |
| release Vulkan, jogador 3440 (3 rodadas) | 6,82 / 6,81 / 6,71 | 6,17 / 6,23 / 6,04 | 10,09 / 9,60 / 9,67 | 11,96 / 10,78 / 11,14 | 21,1 / 19,9 / 30,2 | 0 / 0 / 0 | 4,7–4,8 |
| release D3D12, jogador 1920x1080 | 6,64 | 5,96 | 9,74 | 11,02 | 22,1 | 0 | 2,26 |
| release Vulkan, jogador 1920x1080 | 6,20 | 5,55 | 9,00 | 9,91 | 40,5 | 1 | 2,23 |
| release D3D12, Média 1280x720 (2 rodadas) | 6,32 / 6,08 | 5,59 / 5,42 | 9,39 / 9,11 | 10,37 / 10,42 | 42,9 / 18,2 | 1 / 0 | 1,6–1,8 |
| release Vulkan, Média 1280x720 (2 rodadas) | 5,92 / 5,71 | 5,21 / 5,08 | 8,93 / 8,57 | 10,04 / 9,55 | 24,7 / 15,8 | 0 / 0 | 1,5–1,7 |

- O **binário do editor é ~2,5 ms mais lento no p50 (+38 %)** que o release na mesma rota e nas mesmas opções.
- **Vulkan ganhou nas 5 duplas** (média −4 a −7 %); D3D12 teve os dois únicos quadros > 33 ms da rota calma.
- 3440x1440 custa ~0,4–0,6 ms sobre 1080 com as mesmas opções; a GPU fica em ~4,7 ms (sobra para 144 fps):
  **o limite é a CPU**, não a placa.

### 2.2 Estresse: o pior caso pedido pelo jogador

`--benchmark-stress` (novo, `runtime/ReleaseBenchmark.gd`): chuva forte já molhada, 3 estrelas com o despacho
LIGADO e o carro como alvo da polícia, tiro do jogador por `Gameplay.fire_at` com recarga do jogo, um carro do
trânsito destruído a cada 8 s (explosão, fogo e carcaça do jogo), câmera a 25 m/s e 90 s medidos. Com
`--benchmark-cold` mede desde o primeiro quadro jogável (o JSON traz `first_60s`); `--skip-arrival` pula o
filme da balsa, então `playable_ms` passa a ser o tempo do processo até jogável. Rodar sem `--no-dispatch`
(`BENCH_DISPATCH=1` em `tools/perf_cross_bench.sh`). Opções do jogador a 3440x1440.

**Defeito da bancada, corrigido no export #4:** com o carro como alvo (`driving.occupied`), o jogo recusa empunhar
arma; até o export #3 a troca falhava calada e os "tiros" das tabelas S1 e S3 eram socos (`fire_at` com os
punhos). Polícia atirando, explosões, chuva e velocidade estavam lá; tiro de fuzil do jogador não. A tabela S4
(abaixo) tem os tiros e as trocas de arma de verdade.

**S1 — D3D12 × Vulkan no estresse (export #2, logs ligados, 90 s; estes ainda com o filme antes da medição)**

| rota | driver | média | p50 | p95 | p99 | máx | > 33 ms | > 100 ms | GPU p50 |
|---|---|---|---|---|---|---|---|---|---|
| oeste | D3D12 | 11,33 | 11,56 | 16,41 | 22,74 | 358,6 | 18 | 4 | 5,90 |
| oeste | Vulkan | 9,77 | 10,23 | 14,31 | 18,03 | 51,6 | 4 | 0 | 5,59 |
| porto | D3D12 | 10,27 | 10,47 | 15,69 | 21,40 | 50,8 | 10 | 0 | 5,96 |
| porto | Vulkan | 8,99 | 9,05 | 14,18 | 17,94 | 1034,1 | 4 | 1 | 5,55 |
| serra | D3D12 | 8,34 | 8,32 | 13,30 | 16,87 | 40,8 | 4 | 0 | 6,72 |
| serra | Vulkan | 7,94 | 7,20 | 12,90 | 17,09 | 37,1 | 1 | 0 | 6,48 |
| sobrados | Vulkan | 8,42 | 8,39 | 14,37 | 19,84 | 38,9 | 7 | 0 | 5,27 |
| ponte | Vulkan | 6,18 | 5,67 | 10,03 | 15,74 | 27,5 | 0 | 0 | 5,05 |
| deserto | Vulkan | 7,10 | 6,70 | 10,55 | 14,33 | 367,4 | 5 | 2 | 6,06 |
| oeste, `GETECO_CITY_LIFE_AUDIO=0` | Vulkan | 10,59 | 11,14 | 15,39 | 19,21 | 50,1 | 5 | 0 | 5,71 |
| oeste, janela 1920x1080 | Vulkan | 9,52 | 9,84 | 13,98 | 16,53 | 47,1 | 1 | 0 | 2,95 |

- D3D12 no estresse: 4 quadros de 115–359 ms em 90 s na cidade, todos com `pipelines_delta` (fogo, viatura,
  efeitos) e `setup_ms` de 250–320 ms — o mesmo sintoma do quadro de 969 ms da partida. Vulkan: 1 em 6 rotas
  (o de 1034 ms no porto, 2 `surface` + 2 `specialization` depois de uma batida em poste: destroço de prop
  derrubada desenhado pela primeira vez neste cache; no Vulkan isso fica guardado para as sessões seguintes).
- A camada de áudio "cidade viva" (d4496c39) não mostrou custo: sem ela a rodada saiu 0,8 ms **mais lenta**
  (uma rodada de cada; a diferença está dentro da variação entre rodadas, que muda o trânsito sorteado).
- A GPU a 3440x1440 com tudo no alto e chuva fica em 5,1–6,7 ms (p50) e 5,6–7,8 ms (p95): **não falta GPU** para
  60 nem para 144 fps; nenhum ajuste de qualidade ou FSR é necessário para a meta. Em 1080 cai para ~3 ms, mas o
  quadro só melhora ~0,3–0,8 ms porque o gargalo é a CPU.

**S3 — antes × depois (export #3b, sem logs, sem tiro de fuzil; ver aviso acima)**
"antes" = D3D12 + `GETECO_SAVE_VERIFY=0 GETECO_WEAPON_TEMPLATE=0 GETECO_LOADING_TURBO=0 GETECO_DOOR_ARRAY_CACHE=0`;
"depois" = padrão novo (Vulkan, tudo ligado). `jogável` = do processo até jogável (`--skip-arrival`).

| rota | lado | média | p50 | p95 | p99 | máx | > 33 ms | > 100 ms | 1º minuto: p99 / máx / > 33 | jogável (s) |
|---|---|---|---|---|---|---|---|---|---|---|
| oeste | antes | 9,29 | 9,23 | 13,79 | 18,77 | 41,6 | 3 | 0 | 19,6 / 41,6 / 3 | 34,3 |
| oeste | depois | 9,56 | 9,77 | 13,77 | 15,85 | 31,4 | **0** | 0 | 15,8 / 31,4 / 0 | 30,3 |
| porto | antes | 9,27 | 9,70 | 14,02 | 18,72 | 41,7 | 2 | 0 | 18,2 / 41,7 / 2 | 31,6 |
| porto | depois | 8,46 | 8,77 | 12,92 | 14,74 | 38,0 | 1 | 0 | 15,0 / 26,0 / 0 | 30,2 |
| sobrados | antes | 8,87 | 9,01 | 15,02 | 20,09 | 55,0 | 10 | 0 | 21,0 / 53,4 / 7 | 31,7 |
| sobrados | depois | 7,97 | 7,51 | 12,98 | 17,66 | 51,5 | 9 | 0 | 17,5 / 51,5 / 8 | 30,1 |
| ponte | antes | 6,37 | 5,83 | 10,37 | 15,80 | 52,2 | 3 | 0 | 15,4 / 52,2 / 2 | 33,7 |
| ponte | depois | 6,15 | 5,77 | 9,63 | 14,42 | 36,9 | 1 | 0 | 14,4 / 36,9 / 1 | 30,8 |
| serra | antes | 8,25 | 7,94 | 13,34 | 17,41 | 45,9 | 8 | 0 | 18,0 / 45,9 / 7 | 34,3 |
| serra | depois | 7,70 | 7,11 | 12,34 | 15,49 | 35,5 | 2 | 0 | 15,2 / 35,5 / 1 | 31,6 |
| deserto | antes | 7,46 | 6,91 | 11,00 | 14,71 | 790,9 | 14 | 2 | 15,5 / 790,9 / 14 | 34,3 |
| deserto | depois | 7,07 | 6,77 | 10,42 | 13,93 | 172,2 | 5 | 1 | 14,5 / 172,2 / 5 | 32,5 |

Isolando partes na rota oeste (mesmo export, uma rodada cada): código novo com D3D12 → máx 42,6 / 4 quadros
> 33 ms; Vulkan com o código antigo (todos os interruptores em 0) → máx 51,1 / 2; Vulkan + código novo → máx
31,4 / 0. Vulkan sem `LOADING_TURBO` → mesmo jogo (máx 32,1 / 0), carga 1,2 s mais longa. 1920x1080 (depois):
média 8,84, máx 33,8 / 1. Com logs ligados (depois): oeste 10,06 / máx 49,5 / 4, porto 9,07 / 37,1 / 1,
sobrados 8,32 / 40,2 / 5 — os logs pesados pioram um pouco e não servem de "antes/depois".

**S5 — antes × depois com tiro de verdade (export #4/#5: `--benchmark-stress --benchmark-cold
--benchmark-weapon-cycle=5 --skip-arrival`, arsenal de depuração do jogo; 78 tiros por rodada — fuzil 30,
submetralhadora 30, pistola 12, escopeta 6 — e 18 trocas de arma; sem logs; Vulkan já aquecido por uma
rodada antes)** "antes" = D3D12 + todos os interruptores novos em 0; "depois" = padrão novo.
A rodada S4 (export #4) ficou com só pistola/escopeta (o inventário em grade recusava o fuzil) e foi
interrompida; não entra nas conclusões.

| rota | lado | média | p50 | p95 | p99 | máx | > 33 ms | > 100 ms | 1º minuto: p99 / máx / > 33 | jogável (s) | GPU p50 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| oeste | antes | 10,24 | 10,70 | 14,51 | 19,11 | 52,9 | 7 | 0 | 20,7 / 52,9 / 6 | 32,6 | 5,90 |
| oeste | depois | 9,26 | 9,70 | 13,72 | 16,74 | 49,1 | 3 | 0 | 17,3 / 49,1 / 3 | 30,4 | 5,74 |
| porto | antes | 9,98 | 10,31 | 15,25 | 19,02 | 44,2 | 5 | 0 | 20,1 / 44,2 / 4 | 32,1 | 5,93 |
| porto | depois | 9,29 | 9,79 | 14,88 | 17,33 | 32,8 | **0** | 0 | 17,2 / 32,8 / 0 | 29,9 | 5,79 |
| sobrados | antes | 9,16 | 9,30 | 16,13 | 21,32 | 50,8 | 13 | 0 | 20,9 / 50,2 / 9 | 31,7 | 5,58 |
| sobrados | depois | 8,09 | 7,77 | 13,32 | 17,35 | 37,5 | 9 | 0 | 16,9 / 34,5 / 4 | 30,4 | 5,40 |
| serra | antes | 8,27 | 8,12 | 13,13 | 16,89 | 51,2 | 5 | 0 | 17,4 / 51,3 / 4 | 34,1 | 6,75 |
| serra | depois | 7,74 | 7,08 | 12,45 | 14,75 | 35,6 | 1 | 0 | 15,0 / 33,0 / 0 | 31,0 | 6,48 |
| deserto | antes | 7,46 | 6,99 | 11,20 | 15,62 | 335,5 | 19 | 1 | 16,2 / 335,5 / 19 | 34,9 | 6,34 |
| deserto | depois | 7,12 | 6,79 | 10,48 | 14,61 | 169,6 | 6 | 1 | 15,3 / 169,6 / 6 | 32,2 | 6,09 |

Na mesma série: Vulkan com `GETECO_WEAPON_TEMPLATE=0` (oeste) 9,11 / máx 46,7 / 1 quadro > 33 ms — a troca de
arma não mostrou ganho medido (nenhum span `gameplay.weapon_visual` ≥ 2 ms nas rodadas com logs; com o modelo
antigo não houve rodada com logs). **Primeira vez neste cache do Vulkan:** a rodada de aquecimento (a primeira
com fuzil e submetralhadora) teve 2 quadros de 988 e 938 ms (`pipelines_delta` 5–6 `draw` + 6 `specialization`,
fogo e viatura em cena); na rodada seguinte, zero. Um jogador numa instalação nova veria esses dois na
primeira troca de tiros.

**Meta (p50 ≤ 16,7 ms; nada > 33 ms depois de jogável) no estresse a 3440x1440:** p50 cumprido em todas as
rotas (máximo 9,8 ms). Sem quadro > 33 ms: só o porto (S5) e a ponte (S1). Oeste 3, serra 1, sobrados 9
(todos 33–50 ms), deserto 6 (até 170 ms) — seção 6.

### 2.3 Salvamento automático (o mesmo `FullSession.save_game()` do jogo, a cada 3 s, 15 chamadas)

| build | caminho | save p50 | save máx | quadros > 33 ms na rodada |
|---|---|---|---|---|
| editor (como o jogador jogou) | antigo | 34,3 | 44,9 | 15 |
| release #1 (2 rodadas) | antigo | 22,8 / 23,9 | 24,2 / 28,9 | 10 / 12 |
| release #1 (2 rodadas) | 1ª versão (bytes, reabrindo o temporário) | 16,1 / 15,8 | 17,1 / 21,9 | 0 / 3 |
| release #2 | antigo | 22,5 | 24,6 | 11 |
| release #2 | **novo** | **7,6** | **8,2** | **0** |
| release #3b | antigo / **novo** | 21,7 / **7,4** | 23,0 / **7,7** | 2 / **0** |

Etapas no caminho novo (release, média por save): validar o JSON exato na memória 3,3 ms, girar arquivos 0,5,
conferir principal/backup por data+tamanho 0,4, codificar 0,2, gravar 0,1, conferir o temporário pelo mesmo
handle 0,02; o resto (~2,9 ms) são os snapshots da sessão (`FullSession._save_game`). A primeira versão ainda
reabria o temporário: **reabrir um arquivo recém-gravado custava 6,4 ms no jogo e 17 ms em Python** — o
antivírus examina o arquivo na primeira abertura de dados depois da escrita (stat/data de modificação não
dispara o exame: 0,3 ms medidos no Godot).

### 2.4 Carregamento

| medida (release, oeste, jogador 3440) | antes | depois |
|---|---|---|
| processo → jogável (`--skip-arrival`, S3) | 34,3 s (D3D12, código antigo) | 30,3 s (Vulkan) — Vulkan com código antigo 31,2 s, sem turbo 31,5 s |
| "world startup" (log, S1 → S3 com logs) | 25,4 s (D3D12) / 24,9 s (Vulkan) | 22,0 s |
| "Compilando shaders do tráfego" | 3,0 s | 0,98 s (4 modelos da frota por vez sob a cortina) |
| "Preparando texturas e prédios" | 4,9 s | 4,7 s (túnel: `prime_corridor` 2,2 s, trabalho real, não orçamento) |
| "Carregando áudio" (na verdade todos os pré-aquecimentos de efeitos/materiais) | 4,9 s | 4,9 s |
| "Montando o porto" | 6,3 s | 5,6 s (`urban_operations` 1,6 s, parque 0,6 s, mirante 0,7 s num quadro cada) |

Só foi medido com o cache de pipeline do Vulkan desta máquina já cheio ("a quente"); a primeira sessão de um
computador novo (ou depois de atualizar o driver) não foi medida.

### 2.5 Logs pesados do `Jogar.cmd` (release, mesma rota, uma rodada de cada)

| rodada | sem logs | com `HARBOR_SESSION_LOG/PROFILE/STALL_LOG/STALL_STACKS=1` |
|---|---|---|
| rota calma oeste, D3D12, 3440 (média / p50) | 7,13 e 6,99 / 6,40 e 6,57 | 7,89 / 7,60 |
| dirigindo (piloto automático), Vulkan, 3440 (média / p50) | 7,66 / 7,02 | 7,56 / 6,96 |

Inconclusivo: numa dupla +0,8 ms, na outra nada. Na partida (binário do editor) o perfil em GDScript somou
1,5 % do tempo da thread principal. Não é a causa do FPS baixo; custa disco (122 MB em 13 min).

## 3. Causas, com evidência, e o que foi feito

| # | causa | evidência | correção | interruptor (padrão ligado) |
|---|---|---|---|---|
| 1 | **Jogar no binário do editor** (GDScript de depuração) | rota igual: p50 8,95 (editor) × 6,40–6,57 (release); save 34,3 × 22,5 ms | proposta para o `Jogar.cmd` (seção 4), não aplicada | — |
| 2 | **D3D12 sem cache de pipeline** (Godot 4.7.2) | 969 ms na partida; estresse D3D12 com 4 quadros de 115–359 ms em 90 s, Vulkan 0 na mesma rota; Vulkan 4–14 % mais rápido em todas as duplas | `project.godot`: `rendering_device/driver.windows="vulkan"` (decisão do usuário: "se Vulkan for melhor usa Vulkan") | `--rendering-driver d3d12` volta, por linha de comando |
| 3 | **Salvamento validando o JSON 4 vezes e reabrindo arquivo recém-gravado** | 22–24 ms por save no release (34 no editor), 10–12 quadros > 33 ms por rodada | `runtime/SaveStore.gd`: valida o JSON exato uma vez antes de tocar em arquivo, confere o temporário pelo mesmo handle, principal/backup por data+tamanho (stat) quando são os que esta store gravou; senão `read_valid()` como antes. 7,4–7,6 ms, 0 quadros > 33 ms | `GETECO_SAVE_VERIFY=0` |
| 4 | **Preparo da porta da viatura lendo a malha da GPU** (`surface_get_arrays`) | `dispatch.doors.prewarm` 6–22 ms por chamada, 64–161 chamadas por rodada de estresse (0,4–0,9 s somados) | `gameplay/VehicleDoorBuilder.gd` lê pela `MeshArrayCache`; `ProductionWorld._prewarm_dispatch_models` lê as malhas das viaturas (portas e amassado) sob a cortina. Depois: 16 chamadas, ~0,1 s somados, máx 7 ms | `GETECO_DOOR_ARRAY_CACHE=0` |
| 5 | Troca de arma montando o modelo procedural inteiro (suspeita) | **não confirmada**: com tiro e 18 trocas reais (S5) não houve span `gameplay.weapon_visual` ≥ 2 ms, e a rodada com o modelo antigo não piorou (máx 46,7, 1 quadro). O quadro de 55–64 ms do começo das rodadas S1 era outra coisa (302 nós ao ligar o estresse) | `Gameplay.gd` usa `ArsenalWeapon3D.build_cached`; `warm_templates` monta os modelos sob a cortina; span `gameplay.weapon_visual`. Sem ganho medido: pode ficar desligado ou ser revertido | `GETECO_WEAPON_TEMPLATE=0` |
| 6 | **Carregamento fatiado com orçamento de jogo** (1–4 ms por quadro sob a cortina) e frota pré-aquecida um modelo por vez | "Compilando shaders do tráfego" 3,0 s | `runtime/LoadingTurbo.gd` (orçamento ×6 só enquanto a `StartupCurtain` cobre a tela; volta ao normal no `lift`), aplicado em `NativeRegion`, `RetainedRegionPreparation`, `FullSession._startup_frame`; frota 4 por vez. 3,0 → 0,98 s; carga total −1,2 s | `GETECO_LOADING_TURBO=0` |
| 7 | **Oficina do Digo (deserto) lendo a malha do Gol da GPU** ao entrar no streaming | `stream.desert.record.drag_workshop` 265 ms num quadro | `DesertDigoWorkshop.gd`: malha sem capô por malha-fonte, leitura pela `MeshArrayCache`, `prewarm_hoods()` sob a cortina; spans por etapa. **Parcial:** 265 → 147 ms; o resto é o pátio (`desert.digo_workshop.yard` 70 ms) e o lote de materiais (25 ms), ainda num quadro só | `GETECO_DIGO_HOOD_CACHE=0` |
| 8 | Quadro da arrancada (deserto), suspeita de fonte carregada no streaming | `stream.desert.surface_stage.15` 54 ms | `DesertDragBoardProp.gd`: fonte guardada e nomes rasterizados sob a cortina. **Não resolveu:** a etapa continuou em 54 ms; a causa é outra parte de `build_chunk` (não medida) | `GETECO_DRAG_BOARD_FONT=0` |
| 9 | batida de carro: amassado na 1ª batida de cada modelo | `vehicle.impact.dents` 18 ms; `street.crash` 13–20 ms | só spans novos (`vehicle.impact.dents/breakaway/damage`) para atribuir; correção em aberto | — |

## 4. Recomendações

- **`Jogar.cmd` (não alterado):** para jogar, abrir um export release em vez do binário do editor. Proposta:
  um `JogarRelease.cmd` que (1) roda `Open.ps1 -PrepareOnly` (compila o C# e importa), (2) exporta release
  pela fila (`GODOT_RUN_TIMEOUT=300 tools/run_godot_locked.sh --headless --path . --export-release "Geteco V2
  Windows" builds/jogar/GetecoV2.exe`, ~1–5 min; o export às vezes não sai sozinho depois de gravar o pacote,
  o timeout resolve), só quando houver arquivo `.gd/.tscn/.tres/.cs` mais novo que o `.pck`, e (3) abre
  `builds/jogar/GetecoV2.exe`. O save e as opções são os mesmos (`%APPDATA%/GetecoV2`). Manter o `Jogar.cmd` atual
  para desenvolvimento.
- **Logs:** no uso normal, só `HARBOR_SESSION_LOG=1` (modo essencial) e `HARBOR_STALL_LOG=1`;
  `HARBOR_SESSION_PROFILE=1` e `HARBOR_STALL_STACKS=1` só quando for caçar um pico (122 MB em 13 min, custo
  não provado mas não nulo).
- **Driver:** ficou Vulkan no `project.godot`. Quem quiser comparar: `--rendering-driver d3d12` no motor
  (`ENGINE_EXTRA` na bancada).
- **Opções gráficas:** a 3440x1440 com tudo no alto a GPU tem folga (p95 ≤ 7,8 ms no estresse). Não precisa
  baixar qualidade nem usar FSR para a meta de 60 fps; para 144 fps o limite é CPU.
- **V-sync a 159 Hz com teto de 144:** com v-sync o quadro só pode sair em múltiplos de 6,3 ms; melhor teto
  igual à taxa do monitor ou v-sync desligado com teto (o jogador acabou desligando o v-sync).

## 5. Arquivos e interruptores

Código (sem commit): `runtime/SaveStore.gd`, `runtime/LoadingTurbo.gd` (novo, com `.uid`),
`runtime/StartupCurtain.gd`, `runtime/RetainedRegionPreparation.gd`, `world/regions/NativeRegion.gd`,
`runtime/FullSession.gd` (só `_startup_frame`), `runtime/ProductionWorld.gd` (pré-aquecimentos: frota em lote,
malhas das viaturas, armas, Gol, fonte), `gameplay/Gameplay.gd`, `gameplay/ArsenalWeapon3D.gd`,
`gameplay/VehicleDoorBuilder.gd`, `scripts/Vehicle.gd` (só spans), `world/desert/drag_meet/DesertDigoWorkshop.gd`,
`activities/desert_drag/DesertDragBoardProp.gd`, `project.godot` (driver).
Bancada: `runtime/ReleaseBenchmark.gd` (`--benchmark-save`, `--benchmark-stress`, `--benchmark-speed`,
`--benchmark-shoot`, `--benchmark-explode`, `--benchmark-measure-seconds`, `--benchmark-cold`,
`--benchmark-weapon-cycle`), `tools/perf_cross_bench.sh` (`BENCH_DISPATCH=1`),
`tools/bench/settings-jogador-3440.cfg`, `tools/bench/settings-jogador-1080.cfg`.
Teste novo: `tests/test_save_store_fast_verify.gd` (com `.uid`): o caminho novo e o antigo deixam os mesmos
arquivos e devolvem os mesmos resultados em save normal, principal estragado, backup estragado, recuperação e
regravação idêntica (28 checks).
Interruptores: `GETECO_SAVE_VERIFY`, `GETECO_DOOR_ARRAY_CACHE`, `GETECO_WEAPON_TEMPLATE`,
`GETECO_LOADING_TURBO`, `GETECO_DIGO_HOOD_CACHE`, `GETECO_DRAG_BOARD_FONT` (todos `=0` desligam).

Verificação: `tools/run_core_suite.sh` (22/10 02:21, com tudo): 9 passaram, 1 falhou (`test_core_contracts`, 13
falhas de posição de lugares do deserto e eventos da Route 66, as mesmas da rodada de 21/10 22:08, antes de
qualquer mudança desta sessão). Passaram também `test_save_store_fast_verify` (28), `test_save_store_byte_preflight`
(53), `test_full_save` (nos dois caminhos do save), `test_consumed_world_reward_save`,
`test_vehicle_door_builder_equivalence` (6115 checks, 45 modelos), `test_weapon_model_catalog_consistency` (200),
`test_retained_preparation_scheduler`, `test_retained_region_preparation`, `test_firearm_rig` (192).
`test_vehicle_doors` falha em 2 casos (`medic_box` x 0,97 ≠ 1,03; `sport_estate` 0,94 ≠ 0,97) **igual com
`GETECO_DOOR_ARRAY_CACHE=0`**: tabela da frota nova (22b180ed), não destas mudanças.
`python -I tools/check_frame_rules.py` ok (`mesh_readback` 69 → 67). Não rodei `run_core_suite.sh full` nem
abri o jogo pelo `Jogar.cmd` depois das mudanças (as rodadas de release carregaram e jogaram as 6 rotas).

## 6. O que ainda não fica liso, e por quê

- **Deserto, primeiros ~8 s depois de jogável:** 6 quadros, até 170 ms. Com logs: `world.unmount_region` do porto
  46 ms (o porto é montado na carga e desmontado logo depois de jogável; pode ser artefato do `--play-at`),
  `stream.desert.surface_stage.15` 54 ms (quadro da arrancada, causa não isolada), oficina do Digo 147 ms (pátio
  70, materiais 25), `surface_stage.12` 18 ms, prédios 23 ms. Precisa fatiar esses registros ou montá-los sob a
  cortina quando o jogo começa no deserto.
- **Sobrados (9 quadros de 34–38 ms) e oeste (3 de 33–49 ms):** quadros de batida (`street.crash` 13–20 ms,
  `vehicle.impact.dents` 18 ms: a primeira batida de cada modelo de carro lê as arrays em repouso da GPU — só as
  viaturas foram pré-lidas; ler a frota inteira esbarra no limite de 48 malhas do cache do amassado), desenho sem
  pipeline novo de 24–34 ms (fogo/explosão; causa não provada, mesmo sabor "A" do relatório de 16/10) e streaming
  logo no começo (`prepare_collision` + `surfaces`, ~34 ms).
- **Primeira sessão de um computador novo:** o tiro de fuzil/submetralhadora com fogo e viatura compilou 2 grupos
  de pipelines de ~0,95 s cada; destroço de poste derrubado, 1 s. No Vulkan isso fica no cache e não volta; um
  pré-aquecimento dos efeitos de tiro e dos destroços sob a cortina resolveria para quem joga pela primeira vez.
- **Viatura chegando:** o preparo da porta ainda custa ~7 ms por chamada (agora 16–19 chamadas por rodada em
  vez de 64–161): a granularidade do construtor (etapa de upload da superfície) é maior que o orçamento de 1 ms.
- **Carregamento:** ~30 s do processo até jogável a 3440x1440 (era 34). Os maiores blocos que sobraram são
  trabalho de verdade, não espera de quadro: túnel `prime_corridor` 2,2 s, pré-aquecimentos de efeitos/materiais
  4,9 s (alguns quadros de 200–700 ms sob a cortina sem span), `urban_operations` 1,6 s num quadro só.
- **Não medido:** cache de pipeline frio de verdade (apagar o cache do Vulkan e do driver), jogar com o
  `Jogar.cmd` depois das mudanças, segunda rodada de cada linha do S5 (a variação entre rodadas iguais é de
  ±0,5 ms na média e de alguns quadros > 33 ms), rota da travessia, noite.

**Incidente:** entre ~00:25 e 01:09 de 22/10 o `runtime/ProductionWorld.gd` desta sessão tinha um erro de
tipo (`fleet.all()` devolve Dictionary); todo teste que carrega `World.gd` nesse intervalo falhou por isso
(inclusive de outras sessões: `test_native_driving`, `test_regions`, `test_door_audit`, núcleo de outra sessão
às 00:57–01:04). Corrigido às 01:09; repetir esses testes se tiverem falhado nesse horário.
