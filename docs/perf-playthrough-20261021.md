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
**2ª rodada (22/10, seção 7):** quadros > 33 ms no estresse 37 → 19 em 6 rotas × 2 rodadas (deserto 178 → 49 ms de
máximo), p50 igual; a meta ainda não foi cumprida, o cache frio ainda tem quadros de 0,6–1,1 s no primeiro tiro e
a carga a quente ficou só 0,5 s mais curta.
**3ª rodada (22/10, seção 8):** no frio do oeste, jogável 118,3 → 76,7 s e maior quadro 2 069 → 1 115 ms (o motor
regravava o cache de pipelines inteiro a cada 3 MB; agora só ao sair); pipelines novas no jogo a quente 58 → 4; tempo
de quadro a quente sem mudança mensurável nas rotas medidas limpas; oeste, porto e travessia sem A/B limpo a quente
(outra sessão rodou Godot fora da fila).

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

## 7. 2ª rodada (22/10): quadros > 33 ms no estresse, deserto, cache frio e carregamento

Pedido: pior caso liso (3440x1440 com as opções do jogador, chuva forte, tiro, 3 estrelas, alta velocidade,
explosões, qualquer região), p50 ≤ 16,7 ms e **nenhum quadro > 33 ms depois de jogável**, e carga mais curta.

**Resumo.** No export final medido (E) contra o mesmo export com os interruptores novos em 0, estresse completo,
6 rotas × 2 rodadas por lado: quadros > 33 ms **37 → 19** pelo laço da bancada e **20 → 9** pelo intervalo de
desenho; quadros > 45 ms **11 → 2**; o deserto saiu de 178/171 ms de máximo para 49/45. Média e p50 não mudaram
além do ruído (5,6–10 ms nos dois lados; p50 sempre ≤ 16,7). **A meta "nada > 33 ms" continua não cumprida:**
sobram (2 rodadas somadas) 1 quadro em oeste, serra e travessia, 4 no porto, 8 nos sobrados e 4 no deserto, de
34–49 ms, e a travessia ainda tem 2–3 intervalos de desenho de ~45 ms por rodada nos dois lados. O que
sobra está em 7.5 (pipelines de carro novo e do início do estresse, desenho sem pipeline, física nativa, sinal
`process_frame`). Carga a quente 31,4 → 30,9 s (média das 12 rodadas): **não ficou "bem mais curta"**. Com cache
frio de verdade ainda há 2–5 quadros de 0,1–1,3 s por rodada: o pré-aquecimento de combate novo não pegou as
pipelines que compilam (7.3).

### 7.1 Como foi medido (e dois defeitos da medida)

- Exports, todos pela fila (`GODOT_RUN_TIMEOUT=300 tools/run_godot_locked.sh --headless --path . --export-release
  "Geteco V2 Windows" ...`), cada um com o `working.patch` exato: `artifacts/perf-r2-base-20261022/` (HEAD
  b68ce51d, linha de base com logs), `perf-r2-a/b/c/d` (correções em andamento e diagnóstico),
  **`perf-r2-e-20261022/` (export final medido: A/B completo, noite e cache frio)**, `perf-r2-f-20261022/`
  (E + topo da cabine sem leitura da GPU + guarda do `prewarm_rest`) e `perf-r2-g-20261022/` (F + span
  `vehicle.dents.rest_miss` + leitura antecipada do documento do editor de mundo, depois revertida). F e G só
  rodaram com logs, para atribuição.
- Estresse igual ao da 1ª rodada: `BENCH_DISPATCH=1 BENCH_SETTINGS=tools/bench/settings-jogador-3440.cfg
  BENCH_EXTRA="--benchmark-stress --benchmark-cold --benchmark-weapon-cycle=5 --skip-arrival"`, 90 s medidos,
  tela cheia 3440x1440. A/B no mesmo export e no mesmo dia: "antes" = os interruptores novos em 0 (lista em 7.7),
  alternando antes/depois por rota, 2 rodadas por lado, sem logs. A bancada mede a partir de jogável + 3 s; os
  quadros "t+0,x s" das tabelas de atribuição ficam fora da amostra dela, mas o jogador os vê.
- **A medida da bancada não é o intervalo de quadro do jogo.** O laço do `ReleaseBenchmark` mede entre retornos
  de `await process_frame`; corrotinas que esperam o mesmo sinal mudam de posição dentro do quadro e empurram
  trabalho de um intervalo para o seguinte. Nos sobrados a bancada viu 6 quadros > 33 ms e o registro da sessão
  (intervalo exato entre dois `_process` de prioridade fixa), 2. O JSON grava agora também `present_ms` /
  `present_over_33ms` (intervalo entre dois `frame_post_draw`). As tabelas trazem os dois.
- **Defeito encontrado no meio do A/B (export D):** a bancada nasce antes de a cortina sair e o `LoadingTurbo`
  devolvia o teto do jogador (144 fps) no `lift`, depois de a bancada ter tirado o teto. O lado "depois" do D
  mediu preso em 144 fps (p50 do deserto 6,96 = 1/144 s): média e p50 do A/B do D não valem. Corrigido nos dois
  lados (`ReleaseBenchmark` tira o teto de novo depois da janela estável; `LoadingTurbo` devolve o teto no `lift`
  e limpa as coberturas) e conferido em todos os JSON do E. O D também teve, uma vez, um quadro de 975 ms em
  oeste que não se repetiu no E e não foi atribuído (rodada sem logs).
- Com logs (`HARBOR_SESSION_LOG/PROFILE/STALL_LOG=1`, `HARBOR_STALL_MS=25`) o p50 sobe 1–2 ms e quadros de
  31–33 ms passam de 33; as rodadas com logs servem para atribuir, não para contar.
- Atribuição: `tools/perf_spikes.py` (novo) cruza `frame_spike` do registro da sessão (spans, fases,
  `operation_timing`) com o StallLog (`pipelines_delta`, memória de vídeo). Fases novas no `SessionSystemProfile`
  (só com `HARBOR_SESSION_PROFILE=1`): `late_to_deferred_tail_ms` (fila de `call_deferred`),
  `deferred_tail_to_render_pre_ms` (remoções, sync do RenderingServer), `post_render_to_process_signal_ms`
  (física e entrada) e `process_signal_to_callback_ms` (corrotinas e temporizadores do sinal `process_frame`).
- Spans novos e permanentes: `sys.<sistema>.process/physics` em 20 sistemas grandes (sessão, clima, CityLook,
  poças, beira da serra, fauna, transporte urbano, áudio do mundo, rotinas, estacionamento, reações civis,
  cedência, grama, despacho, ProductionWorld, NativeRegion, câmera, direção, World), `stream.desert.process`,
  `stream.desert.dress_stage.N/expansion_stage.N/mining/workshop_stage`, `routes.*`, `mount.add_child/set_focus`,
  `vehicle.dents.*` (inclusive `rest_miss` com modelo e peça), `vehicle.pre_tick/rails_*/ground_support`,
  `traffic_yield.begin/tick`, `gpu_release.drain/orphans`, `body.install`, `mining.exterior.*`,
  `drag_meet.ground.*`, `bench.*`, marcadores `marker.fire_ignite/fire_free/vehicle_despawn`; `DispatchTrace`
  manda trechos ≥ 2 ms (antes 20). Para achar o mecânico do Digo foram envolvidos temporariamente ~120 `_process`
  (desfeito e conferido contra o HEAD antes do export D).
- Cache frio: `tools/bench/cold_cache_run.sh` (novo) afasta (não apaga) `%APPDATA%/GetecoV2/vulkan` e
  `shader_cache`, roda com `__GL_SHADER_DISK_CACHE_PATH` numa pasta vazia (o driver NVIDIA respeita: o cache dele
  aparece lá) e devolve os caches quentes no fim, mesmo se a rodada cair. Saves e `settings.cfg` não são tocados;
  o cache frio de cada rodada fica em `%APPDATA%/GetecoV2/cache-cold-<rótulo>/` (~90 MB cada; pode ser apagado).

### 7.2 Resultado a quente, export E (antes = interruptores em 0, mesmo export, mesmo dia)

Por rota, 2 rodadas (média/p50/p95/p99 = média das 2; máx = maior das 2; contagens somadas; "desenho" = intervalo
entre dois `frame_post_draw`; jogável = do início do processo até 3 s seguidos de mundo jogável, média das 2):

| rota | lado | média | p50 | p95 | p99 | máx | > 33 ms | > 45 ms | desenho > 33 / máx | jogável (s) |
|---|---|---|---|---|---|---|---|---|---|---|
| oeste | antes | 9,33 | 9,68 | 13,44 | 16,34 | 50,17 | 5 | 1 | 4 / 52,14 | 31,15 |
| oeste | depois | 9,39 | 9,95 | 13,31 | 15,35 | 33,95 | 1 | 0 | 1 / 35,19 | 30,09 |
| porto | antes | 8,63 | 8,81 | 13,43 | 15,68 | 48,47 | 7 | 1 | 2 / 49,92 | 30,71 |
| porto | depois | 8,26 | 8,36 | 12,70 | 14,77 | 43,82 | 4 | 0 | 1 / 38,91 | 30,41 |
| sobrados | antes | 7,84 | 7,08 | 12,48 | 17,20 | 47,49 | 14 | 1 | 3 / 45,54 | 30,34 |
| sobrados | depois | 7,71 | 7,04 | 12,41 | 17,04 | 41,25 | 8 | 0 | 2 / 53,52 | 30,29 |
| serra | antes | 7,38 | 6,60 | 12,04 | 14,30 | 32,43 | 0 | 0 | 0 / 31,45 | 31,95 |
| serra | depois | 7,33 | 6,54 | 12,02 | 14,22 | 34,77 | 1 | 0 | 0 / 32,62 | 31,40 |
| deserto | antes | 6,85 | 6,48 | 10,12 | 14,11 | 177,70 | 10 | 8 | 7 / 169,93 | 32,53 |
| deserto | depois | 6,62 | 6,31 | 9,87 | 13,69 | 49,31 | 4 | 2 | 0 / 32,80 | 31,77 |
| travessia | antes | 6,33 | 5,63 | 10,88 | 14,16 | 34,30 | 1 | 0 | 4 / 50,55 | 31,79 |
| travessia | depois | 6,56 | 5,96 | 11,03 | 14,19 | 33,73 | 1 | 0 | 5 / 44,98 | 31,29 |
| **total** | antes | | | | | | **37** | **11** | **20** | 31,41 |
| **total** | depois | | | | | | **19** | **2** | **9** | 30,87 |

Cada rodada (laço da bancada; desenho = p99 / máx / quadros > 33):

| rota | lado | rodada | média | p50 | p95 | p99 | máx | > 33 ms | > 100 ms | desenho: p99 / máx / > 33 | jogável (s) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| oeste | antes | 1 | 9,36 | 9,61 | 13,55 | 16,23 | 50,17 | 2 | 0 | 16,27 / 52,14 / 2 | 32,23 |
| oeste | antes | 2 | 9,30 | 9,76 | 13,33 | 16,46 | 41,48 | 3 | 0 | 16,30 / 44,57 / 2 | 30,07 |
| oeste | depois | 1 | 9,91 | 10,57 | 14,12 | 16,20 | 30,55 | 0 | 0 | 15,81 / 35,19 / 1 | 30,36 |
| oeste | depois | 2 | 8,87 | 9,32 | 12,50 | 14,50 | 33,95 | 1 | 0 | 14,36 / 30,51 / 0 | 29,81 |
| porto | antes | 1 | 8,61 | 8,93 | 13,02 | 15,66 | 48,47 | 4 | 0 | 15,23 / 49,92 / 2 | 29,89 |
| porto | antes | 2 | 8,65 | 8,69 | 13,83 | 15,69 | 43,66 | 3 | 0 | 15,50 / 29,88 / 0 | 31,54 |
| porto | depois | 1 | 7,93 | 7,73 | 12,30 | 14,26 | 36,80 | 2 | 0 | 14,04 / 27,92 / 0 | 31,32 |
| porto | depois | 2 | 8,59 | 8,99 | 13,10 | 15,28 | 43,82 | 2 | 0 | 15,00 / 38,91 / 1 | 29,49 |
| sobrados | antes | 1 | 7,77 | 7,00 | 12,31 | 17,29 | 47,49 | 6 | 0 | 15,71 / 45,54 / 2 | 30,21 |
| sobrados | antes | 2 | 7,92 | 7,16 | 12,64 | 17,10 | 44,41 | 8 | 0 | 16,09 / 33,63 / 1 | 30,46 |
| sobrados | depois | 1 | 7,42 | 6,38 | 11,89 | 16,71 | 40,88 | 4 | 0 | 15,48 / 31,62 / 0 | 31,21 |
| sobrados | depois | 2 | 8,00 | 7,70 | 12,92 | 17,36 | 41,25 | 4 | 0 | 16,38 / 53,52 / 2 | 29,36 |
| serra | antes | 1 | 7,18 | 6,26 | 11,86 | 13,96 | 31,64 | 0 | 0 | 12,82 / 31,45 / 0 | 32,76 |
| serra | antes | 2 | 7,59 | 6,94 | 12,22 | 14,63 | 32,43 | 0 | 0 | 13,13 / 29,67 / 0 | 31,14 |
| serra | depois | 1 | 7,07 | 6,20 | 11,74 | 13,26 | 30,40 | 0 | 0 | 12,29 / 27,45 / 0 | 32,49 |
| serra | depois | 2 | 7,59 | 6,88 | 12,29 | 15,19 | 34,77 | 1 | 0 | 13,54 / 32,62 / 0 | 30,31 |
| deserto | antes | 1 | 6,96 | 6,60 | 10,26 | 14,14 | 177,70 | 5 | 2 | 12,48 / 169,93 / 3 | 32,62 |
| deserto | antes | 2 | 6,74 | 6,36 | 9,97 | 14,07 | 170,71 | 5 | 2 | 12,41 / 161,54 / 4 | 32,44 |
| deserto | depois | 1 | 6,67 | 6,34 | 9,89 | 13,95 | 49,31 | 3 | 0 | 12,24 / 32,80 / 0 | 32,01 |
| deserto | depois | 2 | 6,58 | 6,29 | 9,85 | 13,43 | 45,33 | 1 | 0 | 11,89 / 30,18 / 0 | 31,54 |
| travessia | antes | 1 | 6,31 | 5,60 | 10,82 | 14,16 | 34,30 | 1 | 0 | 12,91 / 50,55 / 2 | 31,82 |
| travessia | antes | 2 | 6,36 | 5,67 | 10,95 | 14,15 | 27,42 | 0 | 0 | 12,89 / 41,41 / 2 | 31,76 |
| travessia | depois | 1 | 6,76 | 6,23 | 11,24 | 14,57 | 30,52 | 0 | 0 | 13,21 / 44,98 / 2 | 30,24 |
| travessia | depois | 2 | 6,37 | 5,69 | 10,82 | 13,81 | 33,73 | 1 | 0 | 12,65 / 44,37 / 3 | 32,34 |

Noite (porto, 22 h, 1 rodada por lado, mesmo estresse): antes média 8,44, p50 8,51, p95 13,44, p99 15,98, máx
36,45, 1 quadro > 33 (desenho máx 34,66, 1 > 33), jogável 31,7 s; depois 8,01 / 8,00 / 12,54 / 14,58 / máx 35,02,
2 > 33 (desenho máx 27,71, 0 > 33), jogável 31,0 s. A noite não trouxe pico novo.

Leitura honesta: entre rodadas iguais a média varia ±0,5 ms e a contagem > 33 ms, 1–4 quadros; as diferenças de
média/p50 estão dentro disso. O que mudou de verdade foram os picos grandes (deserto 170 → 49, quadros > 45 ms
11 → 2) e a contagem de 34–50 ms em oeste, porto e sobrados. A travessia não melhorou no desenho.

### 7.3 Cache frio (primeira sessão de uma instalação nova ou depois de atualizar o driver)

`tools/bench/cold_cache_run.sh` (cache do Vulkan do jogo e do driver vazios), export E, 1 rodada por lado, sem
logs; oeste 90 s medidos, serra e deserto 20 s:

| rota | lado | média | p50 | p95 | p99 | máx | > 33 ms | > 100 ms | > 250 ms | desenho > 33 / máx | jogável (s) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| oeste | antes | 13,63 | 13,27 | 17,83 | 22,76 | 2244,72 | 15 | 6 | 4 | 17 / 2243,73 | 76,6 |
| oeste | depois | 13,26 | 13,50 | 17,49 | 21,11 | 1268,15 | 12 | 5 | 2 | 15 / 1214,56 | 78,5 |
| serra | antes | 9,36 | 8,41 | 14,49 | 22,89 | 891,64 | 11 | 4 | 2 | 9 / 880,00 | 87,2 |
| serra | depois | 9,09 | 7,84 | 13,82 | 20,31 | 871,58 | 8 | 5 | 2 | 10 / 861,69 | 88,3 |
| deserto | antes | 8,72 | 7,27 | 14,01 | 26,33 | 1245,70 | 10 | 6 | 1 | 8 / 188,65 | 83,5 |
| deserto | depois | 7,78 | 6,78 | 13,12 | 15,63 | 1038,45 | 6 | 2 | 1 | 4 / 134,62 | 78,8 |

Com logs (export E, oeste, frio, 1 rodada; jogável 75,2 s) os quadros grandes caem nos mesmos momentos da linha
de base fria (653 ms submetralhadora, 1 057 ms fuzil com polícia atirando, 107 ms pistola): **604 ms** com
submetralhadora dirigindo (1 pipeline `surface` + 1 `specialization`, 3 efeitos emitindo), **1 072 ms** com AK-47 e
fogo no chão (2 + 2), **110 ms** com pistola (1 + 1), todos dentro do desenho (`render_bracket`) e sem span de
script. O `CombatEffectsPrewarm` (cada pool do `CombatEffects`, todas as armas com clarão, 3 desenhos diante da
câmera) **não cobre a variante que compila**. Candidatas, não testadas: a passada de sombra/profundidade dos
efeitos ou a luz do clarão (o pré-aquecimento desenha perto da câmera, sem as mesmas luzes), o fogo do
`EmergencyManager` (`Fire.gd`, fora dos pools do `CombatEffects`) e o tiro de dentro do carro. Achar exige saber
qual material criou a pipeline (o StallLog só conta por tipo). Também no frio: `native.ready.rewards` 32 ms +
`building.ready.floor_add_child` 37 ms com 4 pipelines `specialization` logo depois da cortina (quadro de 78 ms) e
`stream.harbor.prepare_collision` 11–15 ms em três quadros de 61–131 ms (no quente ~7 ms).

Carga fria, oeste com logs: linha de base 74,9 s até jogável (`startup:prepared` 65,6 s), E 75,2 s (65,6 s). Nos
dois o maior bloco é `startup:combat_resources`, 30,6 / 31,1 s (5,0 s a quente): o pré-aquecimento de recursos de
combate que já existia compila centenas de pipelines e mesmo assim o tiro compila mais no jogo. A frota pedida
cedo tirou 7,2 s de `fleet_hold` (7,5 → 0,3 s), que voltaram em `fleet_shaders` (1,1 → 5,9 s) e nos
pré-aquecimentos novos. Sem logs, 1 rodada por lado: oeste +1,9 s, serra +1,1 s, deserto −4,7 s, sem como separar
do ruído.

### 7.4 Carregamento (do início do processo até 3 s seguidos de mundo jogável; a bancada pula o menu)

| começa em | quente, E, antes / depois (média de 2, sem logs) | frio, E, antes / depois (1 rodada, sem logs) |
|---|---|---|
| Harbor (oeste) | 31,15 / 30,09 s | 76,6 / 78,5 s |
| Harbor (porto) | 30,71 / 30,41 s | — |
| Harbor (sobrados) | 30,34 / 30,29 s | — |
| Harbor (travessia) | 31,79 / 31,29 s | — |
| serra | 31,95 / 31,40 s | 87,2 / 88,3 s |
| deserto | 32,53 / 31,77 s | 83,5 / 78,8 s |

Etapas da carga a quente em oeste, com logs (ms; linha de base = 2 rodadas no export base, F = 1 rodada):

| etapa | base r1 | base r2 | F |
|---|---|---|---|
| `startup:fleet_hold` | 1 965 | 2 003 | 87 |
| `startup:dispatch_models` | 97 | 95 | 262 |
| `startup:fleet_shaders` | 931 | 930 | 2 138 |
| `startup:combat_resources` | 4 971 | 4 984 | 5 100 |
| `startup:resident_prewarm` | 4 689 | 4 895 | 4 925 |
| `startup:distant_prewarm:mountain` | 800 | 799 | 1 859 (porto F: 922 / 1 360) |
| `startup:route_graphs` | 293 | 300 | 370 |
| `startup:prepared` | 23 010 | 22 737 | 23 821 |
| jogável | 30 681 | 30 457 | 31 719 |

A frota pedida em thread no começo da carga tirou ~1,9 s de `fleet_hold`, mas o tempo voltou nos
pré-aquecimentos novos que tiram trabalho do jogo: lentes apagadas desenhadas junto com cada lote da frota e
arrays em repouso da frota para o amassado (`fleet_shaders` +1,2 s), viaturas (+0,2 s), grafo serra+deserto
(+0,1 s), combate, oficina e mecânico do Digo. Saldo a quente sem logs: −0,5 s em média (31,41 → 30,87 s), dentro
da variação de ±1 s entre rodadas iguais. **Não feito nesta rodada:** os blocos grandes do pedido continuam como
estavam — túnel `prime_corridor` ~2,2 s, `resident_prewarm` ~4,9 s, `combat_resources` ~5,0 s (31 s no frio),
"Montando o porto" ~5,7 s com `urban_operations` ~1,7 s num quadro só. São montagem de nós no thread principal;
encurtar exige montar subárvores fora da árvore em `WorkerThreadPool`, sistema por sistema, e provar que nada
disso escorrega para depois da cortina. A prioridade ficou com os quadros do jogo.

### 7.5 Atribuição: cada quadro > 33 ms da linha de base, e o que sobrou

Linha de base = export do HEAD b68ce51d, estresse com logs, 2 rodadas por rota (oeste, porto, sobrados, serra,
deserto, travessia). Intervalo exato do registro da sessão; "t+" = segundos depois de jogável.

| rota | quando | quadro | causa (span) | rodadas |
|---|---|---|---|---|
| deserto | t+3,1 | 90–99 | desmontagem do porto 46 ms, quase toda em `routes.configure` 40 ms (a combinação serra+deserto não estava entre os grafos de rota pré-calculados) + chão síncrono do trecho do carro 22 ms (`surface_stage.12` 18) | 2/2 |
| deserto | t+3,4 | 55–64 | quadro da arrancada (`surface_stage.15`) 49–57 ms: `DesertTownMaterials.batch_visuals` lia cada BoxMesh da GPU (~140 leituras) | 2/2 |
| deserto | t+5,1 | 161–172 | oficina do Digo (`record.drag_workshop`) 142–154 ms: pátio 64–73, lote 26–28, mesmas leituras + montagem inteira | 2/2 |
| deserto | t+7,9 | 54–61 | mecânico Digo nascendo a 75 m (`DesertDigoRoutine._process` 29 ms + 14 ms de trabalho do RenderingServer no fim do quadro); achado só com spans em ~120 `_process` | 2/2 |
| deserto | t+17 | 34–38 | `record.building` 17–20 ms, `painted.build` 6–7, etapa da mina 22–24 ms (`stream.desert.mining`) | 2/2 |
| oeste, sobrados, porto, travessia | 1ª batida de cada modelo | 35–42 | `vehicle.impact.dents` 16–21 ms: leitura das arrays em repouso da GPU 6–14 ms (até 8 superfícies) + reconstrução da lataria 8–10 ms em GDScript, no quadro de física da batida | 5 de 8 rodadas |
| sobrados | viatura chegando | 49 | `dispatch.doors.prewarm` 19 ms: recorte da porta trocava a malha e o amassado relia 5 superfícies da GPU e refazia tudo no mesmo quadro | 1 |
| oeste | t+0,5 | 38–40 | rodoviária montada no 1º tique jogável (`terminal.build` 13 ms) | 2/2 |
| oeste | t+0,2 | 39 | `native.ready.rewards` 21 ms no 1º lugar com interior (`harbor_building_patrol_court_north`): `WorldInteriorEdits.apply_saved` + `_install_reward`. **Não é** a leitura do documento do editor: com o documento em cache e lido sob a cortina continuou 18–21 ms (cache revertido) | 2/2 |
| sobrados, porto | carro novo no trânsito | 34–40 | `population_job:equipment` 4–10 ms + 13,6 ms depois das chamadas diferidas (sync do RenderingServer) com 2 pipelines `surface` novas | 4 |
| serra | a cada volta perto da ponte | 35–40 | remontar o porto guardado 13–17 ms: `mount.add_child` 7,8 (2.400 nós de trechos em descarte que a região levava junto), foco 1,9, conexão da ponte remontada 3,2, consumidores de rota 3–5 | 4/4 |
| travessia | entrando no porto | 33–35 | `stream.harbor.prepare_collision` 7 + 7 ms (dois trechos de apoio síncronos) | 2 |
| porto, oeste, travessia | raro | 34–48 | desenho de 19–35 ms (`render_bracket`) sem pipeline nova, CPU da viewport 1–2 ms, GPU 5–7 ms | 1–2 por rodada |
| sobrados, porto | raro | 35–50 | 25–36 ms entre o fim do desenho e o 1º `_process` sem span de script (física do motor ou entrada) ou 18,7 ms no sinal `process_frame` (corrotinas/temporizadores) | 1 por rodada |

**O que sobrou** (exports E/F/G com logs: deserto 2 rodadas, sobrados 3, porto 2, oeste 2; logs somam 1–2 ms):

| classe | onde | quadro | evidência |
|---|---|---|---|
| carro novo no trânsito: 2 pipelines `surface` (cache quente) + 14–17 ms de sync do RenderingServer depois das diferidas | sobrados 3, oeste 1 | 33–38 | `population_job:equipment` só 1–4 ms no quadro; as cópias de lente apagada pré-aquecidas não pegaram essa variante; o StallLog conta pipelines por tipo, não diz o material |
| início do estresse: a bancada liga chuva forte, 3 estrelas e perseguição e teleporta o carro no mesmo quadro | todas as rotas rodadas com logs (oeste, porto, sobrados, deserto), t+3 s | 37–50 | 1–10 pipelines `specialization` + 1–2 `surface`/`canvas`, desenho 21–25 ms. Parte é artefato (tudo de uma vez), mas as pipelines são as da 1ª chuva/1ª perseguição de uma partida |
| deserto, mesmo quadro t+3 s | deserto | 50 | idem + desmontagem do porto 5,9 ms (era 46) e chão do trecho para onde a bancada teleporta |
| viatura nascendo logo depois da cortina | oeste G, t+0,4 | 56 | `spawn_vehicle_add_child:police_cruiser` 25 ms + 2 pipelines `mesh` (fora da amostra da bancada) |
| desenho de 28 ms sem pipeline | porto F t+77, oeste G t+76 | 44–49 | `render_bracket` 28 ms, CPU da viewport 2–3 ms |
| física/entrada sem script | sobrados F t+81 (batida: `vehicle.physics` 7,0, `street.crash` 6,7, amassado 5,5), sobrados G t+82 (36 ms sem span) | 34–41 | fase `post_render_to_process_signal` |
| sinal `process_frame` 22 ms | sobrados F, 2 vezes | 33–35 | corrotinas/temporizadores sem span |
| trânsito: `population_job:traffic` / `traffic_spawn` 7 ms | porto F | 35 | |
| 1ª batida: `vehicle.impact.dents` 4–10 ms (era 16–21) | todas | sozinho não passa de 33 | reconstrução saiu do quadro; sobra `prepare` com leitura da GPU de 2–6,5 ms (`vehicle.dents.rest_miss`): porta recortada `DriverDoorPresentation/DriverDoorL/Skin` e capô solto `Breakaway_hood` da viatura, `Body` do `metro_hatch` — malhas únicas de cada carro, fora do cache da frota e além das 48 do cache limitado |
| deserto, mina | — | — | etapa da mina 24,9 ms apareceu numa rodada com logs de um export intermediário e não na do E final (1 rodada cada): não dá para dizer que acabou |
| travessia, desenho ~45 ms | travessia, 2–3 por rodada nos dois lados | 44–45 (desenho) | não atribuído nesta rodada (sem rodada da travessia com logs depois das correções) |

### 7.6 O que foi feito (cada item atrás de um interruptor, padrão ligado; `=0` desliga)

| # | causa | correção | interruptor | efeito medido |
|---|---|---|---|---|
| 1 | caixas/cilindros de `G.box`/`G.cylinder` lidos da GPU um por um nas fusões do deserto | `MeshArrayCache.arrays_of`: BoxMesh sem subdivisão e CylinderMesh reto saem da forma unitária escalada na CPU (lida uma vez por tipo, `prewarm_unit_shapes` sob a cortina); `DesertTownMaterials.batch_visuals` e `MiningBatch` (rocha) passam por ela | `GETECO_PRIMITIVE_CPU_ARRAYS` | quadro da arrancada 49–57 ms → não aparece |
| 2 | oficina do Digo montada a cada visita | montada uma vez sob a cortina (`DesertRegion.prebuild_workshop`), estacionada fora da árvore quando o trecho sai e devolvida no próximo (`ChunkCellMerge.restore_sources`); pátio e Gol voltam um por quadro (`stream.desert.workshop_stage`) | `GETECO_DIGO_WORKSHOP_PARK` | 142–154 ms → não aparece |
| 3 | mecânico Digo criado/liberado a cada aproximação | montado sob a cortina e estacionado (`DesertDigoRoutine`) | `GETECO_DIGO_WORKER_PARK` | 54–61 ms → não aparece |
| 4 | grafo de rota serra+deserto refeito no jogo | combinação pré-calculada sob a cortina | `GETECO_ROUTE_COMBO_MD` | desmontagem do porto 46 → 5,9 ms |
| 5 | 1ª batida de cada modelo: leitura + reconstrução no quadro | arrays em repouso da frota lidas sob a cortina (`VehicleBodyDents.prewarm_rest`, ~285 mil vértices, fora do limite de 48 do cache), porta recortada entra com as arrays da CPU (`prime_rest`), reconstrução (posições, normais, tangentes) no `WorkerThreadPool` com o mesmo código do síncrono (diferença 0,0 no teste); troca de malha da porta também assíncrona | `GETECO_DENTS_FLEET_PREWARM`, `GETECO_DENTS_DOOR_PRIME`, `GETECO_DENTS_ASYNC` | `vehicle.impact.dents` 16–21 → 4–10 ms; resto em 7.5 |
| 6 | rodoviária montada no 1º tique jogável | sob a cortina quando o jogo começa perto dela (`TerminalOperations.prepare_startup_build`) | `GETECO_TERMINAL_STARTUP_BUILD` | `terminal.build` 13–16 ms agora ~1,1 s antes de a cortina sair (F e G com logs) |
| 7 | lentes apagadas compilando no jogo | cada lote da frota sob a cortina é desenhado também com as lentes emissivas apagadas (cópias retidas) | `GETECO_LENS_VARIANT_PREWARM` | **não resolveu** o carro novo com 2 pipelines (7.5) |
| 8 | porto remontado na serra com os trechos velhos e a conexão da ponte refeita | trechos em descarte vão para a `GpuReleaseQueue` antes de a região sair da árvore (`NativeRegion.hand_off_retiring`); conexão da ponte estacionada; consumidores de rota refeitos no quadro seguinte (só jogando) | `GETECO_RETIRE_HANDOFF`, `GETECO_CONNECTION_PARK`, `GETECO_ROUTE_REFRESH_DEFER` | export D com logs: serra sem quadro > 30 ms; no A/B do E a serra já era a melhor rota (0 / 1 quadro > 33) |
| 9 | cache de pipeline frio: tiros, impactos, explosão | `gameplay/CombatEffectsPrewarm.gd` (novo): cada pool do `CombatEffects` (faíscas/poeira de 9 materiais, sangue, fumaça, explosão, chama, sopro, cápsulas, traçante, mancha, queimado) e todas as armas do catálogo com o clarão, 3 desenhos diante da câmera sob a cortina, depois `clear()` | `GETECO_COMBAT_PREWARM` | **insuficiente**: no frio os quadros de 0,6–1,1 s do tiro continuam (7.3) |
| 10 | destroço de prop derrubada lia a malha da GPU a cada choque | `PropFracture3D` lê pela `MeshArrayCache` (1 leitura por tipo) | `GETECO_PROP_FRACTURE_CACHE` | não isolado |
| 11 | recursos da preparação em segundo plano (46 shaders) carregados no jogo | pedidos em thread no começo da carga e recolhidos antes de a cortina sair (`BackgroundRegionPreparation.prefetch_start/collect`, prazo 3 s) | `GETECO_BG_PREFETCH` | não isolado (carga, 7.4) |
| 12 | carregamento esperando quadros no teto de 144 fps / v-sync | `LoadingTurbo`: sem teto nem v-sync enquanto a cortina cobre; volta no `lift` | `GETECO_LOADING_UNCAP` | não isolado (carga, 7.4) |
| 13 | corpo de colisão da mina somando formas já no espaço | `MiningBatch`: corpo entra na árvore só no `finish()` | `GETECO_MINING_BODY_LATE` | não provado (7.5) |
| 14 | cenas da frota pedidas 2 por vez depois de montar o porto | todas pedidas em thread no começo da carga (`_request_fleet_scenes_early`) | `GETECO_FLEET_EARLY` | `fleet_hold` 2,0 → 0,1 s a quente (o tempo voltou em outras etapas, 7.4) |
| 15 | chão do paddock do encontro de arrancada (material criado no streaming, `drag_meet.ground.quad` 17 ms) | material criado e desenhado uma vez sob a cortina (quad escondido a −500 m) | `GETECO_PADDOCK_PREWARM` | não apareceu na rodada com logs do E (1 rodada) |
| 16 | topo da cabine do 1º caminhão de cada modelo lia a malha da GPU (`VehicleEquipment._car_points`) | usa as arrays da frota já lidas pelo amassado (`VehicleBodyDents.cached_rest`) e as primitivas da `MeshArrayCache`; leitura direta só para peça fora da frota (só nos exports F/G) | `GETECO_CAB_REST_ARRAYS` | sem efeito visível: `population_job:equipment` máx 9–11,5 ms no F (10,5 na base); o custo do equipamento é outro |
| — | documento do editor de mundo relido a cada lugar com interior (suspeita) | cache por md5 + leitura sob a cortina | — | **revertido**: `native.ready.rewards` ficou em 18–21 ms; a causa é outra (7.5) |

### 7.7 Arquivos e interruptores

Código (sem commit):
- Novos: `gameplay/CombatEffectsPrewarm.gd` (+ `.uid`), `tests/test_vehicle_body_dents_async.gd` (+ `.uid`),
  `tools/perf_spikes.py`, `tools/bench/cold_cache_run.sh`.
- Correções: `world/chunk_bake/MeshArrayCache.gd`, `world/desert/DesertTownMaterials.gd`,
  `world/desert/DesertRegion.gd`, `runtime/desert/DesertDigoRoutine.gd`, `gameplay/vehicle_effects/VehicleBodyDents.gd`,
  `gameplay/VehicleDoorBuilder.gd`, `gameplay/VehicleEquipment.gd`, `runtime/ProductionWorld.gd`,
  `runtime/BackgroundRegionPreparation.gd`, `runtime/LoadingTurbo.gd`, `runtime/terminal/TerminalOperations.gd`,
  `world/regions/NativeRegion.gd`, `world/mining/MiningBatch.gd`, `gameplay/street_physics/PropFracture3D.gd`.
- Bancada e perfil: `runtime/ReleaseBenchmark.gd` (intervalo de desenho, spans `bench.*`, teto tirado de novo),
  `runtime/SessionSystemProfile.gd` (fases novas).
- Só spans/marcadores: `runtime/GpuReleaseQueue.gd`, `world/mining/MiningExterior.gd`,
  `world/desert/drag_meet/DesertDragMeet.gd`, `gameplay/emergency/Fire.gd`, `gameplay/emergency/EmergencyManager.gd`,
  `assets/civilians/RigBodySwap.gd`, `gameplay/dispatch/DispatchTrace.gd`, `scripts/Vehicle.gd` e os `sys.*` em
  `runtime/FullSession.gd`, `runtime/Weather.gd`, `world/city_look/CityLook.gd`, `world/rain/RainPuddles3D.gd`,
  `world/mountain_detail/MountainRoadside3D.gd`, `gameplay/wildlife/MountainWildlife.gd`,
  `runtime/UrbanTransitPresentation.gd`, `audio/WorldAudio.gd`, `gameplay/routines_v1/RoutineDirector.gd`,
  `runtime/RoadsideParking.gd`, `gameplay/civilian_reactions/CivilianReactionDirector.gd`,
  `gameplay/traffic_yield/TrafficYieldController.gd`, `world/mountain_detail/MountainGrass3D.gd`,
  `gameplay/dispatch/DispatchController.gd`, `scripts/CameraRig.gd`, `scripts/Driving.gd`, `scripts/World.gd`
  (e `ProductionWorld`, `NativeRegion`).
- Teste alterado: `tests/test_cab_top_exact.gd` (confere também o caminho com a lataria da frota já lida).

Interruptores novos (`=0` desliga, padrão ligado): `GETECO_PRIMITIVE_CPU_ARRAYS`, `GETECO_DIGO_WORKSHOP_PARK`,
`GETECO_DIGO_WORKER_PARK`, `GETECO_ROUTE_COMBO_MD`, `GETECO_DENTS_FLEET_PREWARM`, `GETECO_DENTS_DOOR_PRIME`,
`GETECO_DENTS_ASYNC`, `GETECO_TERMINAL_STARTUP_BUILD`, `GETECO_LENS_VARIANT_PREWARM`, `GETECO_RETIRE_HANDOFF`,
`GETECO_CONNECTION_PARK`, `GETECO_ROUTE_REFRESH_DEFER`, `GETECO_COMBAT_PREWARM`, `GETECO_PROP_FRACTURE_CACHE`,
`GETECO_BG_PREFETCH`, `GETECO_LOADING_UNCAP`, `GETECO_MINING_BODY_LATE`, `GETECO_FLEET_EARLY`,
`GETECO_PADDOCK_PREWARM`, `GETECO_CAB_REST_ARRAYS`. Diagnóstico (`=1` liga): `GETECO_MOUNT_CENSUS` (nós por
filho ao montar região), `GETECO_LOADING_TRACE` (etapas do `LoadingTurbo`).

### 7.8 Verificação

Sobre o código final (o do export G sem a leitura antecipada do documento e com o cache do editor revertido):
- `tools/run_core_suite.sh` (22/10 08:28): 9 passaram, 1 falhou — `test_core_contracts`, as mesmas 13 falhas de
  posição de lugares do deserto e eventos da Route 66 de antes desta rodada.
- Verificação estrutural e os testes que a suíte `full` das 06:15 marcou: `test_regions`,
  `test_bridge_approach_terrain`, `test_native_driving`, `cold/test_admission`, `test_save_indicator`,
  `test_recovery_penalty_session`, `test_desert_wilds`, `test_desert_roadside_session`, `test_dialogue_flow`,
  `test_video_vehicle_lifecycle` — todos com saída 0 e nenhum erro novo no log. A suíte `full` das 06:15 tinha
  marcado 7 deles por "erro no log": era o `prewarm_rest` chamando `surface_get_array_len` em BoxMesh/CylinderMesh
  (corrigido: só ArrayMesh) mais o erro antigo "Editor de mundo: alteração inválida ou origem ausente:
  path/mountain_zoo_walk", que já aparece na suíte de 19/10 e continua (não é desta rodada).
- Sistemas tocados: `test_vehicle_body_dents`, `test_vehicle_body_dents_incremental`,
  `test_vehicle_body_dents_async` (novo: assíncrono = síncrono, diferença 0,0, reparo no meio do cálculo),
  `test_cab_top_exact` (55 modelos, também pelo caminho da frota), `test_vehicle_equipment` (57),
  `test_desert_digo_routine`, `test_terminal_mesh_preparation`, `test_terminal_route_preparation`,
  `test_background_region_preparation`, `test_world_editor_interiors`, `test_dispatch_ground_owners`,
  `test_gpu_release_detached_subtree`, `test_unified_bridge_physics`, `test_chunk_cell_merge`,
  `test_vehicle_door_builder_equivalence`, `test_vehicle_crash_damage`, `test_vehicle_breakaway`: passaram.
  Falham igual com os interruptores desta rodada em 0 (antigos): `test_desert_chunk_reuse` (1 caso),
  `test_drag_ground_cover_batches` (2), `test_desert_ground_ownership` (3). `test_combat_fx_0922` falha em "explosão dispara a bola
  de fogo" e na camada de áudio da Magnum (erro de script e não sai sozinho); nem o teste nem `CombatEffects.gd`
  foram mexidos e o teste monta o `CombatEffects` direto, sem o pré-aquecimento novo. Não conferi no HEAD.
- `python -I tools/check_frame_rules.py`: ok (`mesh_readback` 67, igual).
- O jogo carregou e jogou as 6 rotas em release (E, F, G); não abri pelo `Jogar.cmd` nem joguei à mão.

### 7.9 O que ainda não fica liso, e por quê

- **Carro novo no trânsito (sobrados, oeste): 33–38 ms.** Duas pipelines `surface` criadas no quadro (mesmo com
  cache quente) e 14–17 ms de sync do RenderingServer. O pré-aquecimento da frota e das lentes apagadas não pega
  essa variante; falta saber qual material é (o StallLog conta por tipo). Próximo passo: registrar o material
  novo no primeiro desenho de cada carro (ou desenhar sob a cortina cada combinação pintura × lente × sujeira).
- **Primeira chuva / primeira perseguição: 1–10 pipelines `specialization`, desenho 21–25 ms.** Na bancada cai
  tudo no mesmo quadro (t+3 s); numa partida aparece na primeira vez que cada coisa liga. Pré-aquecer exige
  desenhar, sob a cortina, a cena com chuva forte e com as luzes da perseguição ligadas.
- **Desenho de 19–35 ms sem pipeline nova** (porto, oeste, travessia; a travessia tem 2–3 por rodada nos dois
  lados): CPU da viewport 1–3 ms, GPU 5–7 ms; o tempo está dentro de `RenderingServer.draw` mas fora do desenho da
  viewport. Hipótese da 1ª rodada (driver liberando memória de vídeo) não testada: `GETECO_GPU_HOLD_ALL=1` e
  estacionar os emissores do fogo em vez de liberá-los.
- **25–36 ms entre o fim do desenho e o 1º `_process`** (física do motor ou entrada; uma vez numa batida com
  `vehicle.physics` 7 + `street.crash` 6,7 + amassado 5,5) e **22 ms no sinal `process_frame`** (corrotinas e
  temporizadores sem span): o perfil de script não vê o passo nativo.
- **Primeira batida:** amassado ainda 4–10 ms, com 2–6,5 ms de leitura da GPU de malhas únicas de cada carro
  (porta recortada e capô solto da viatura, carroceria recortada do `metro_hatch`); caberia reaproveitar a malha
  recortada por modelo ou guardar as arrays de quem recorta sem o limite de 48.
- **Cache frio:** 0,6–1,1 s no primeiro tiro de submetralhadora/fuzil com fogo; o pré-aquecimento novo não pegou
  (7.3). Sem saber o material, o caminho é o mesmo do item do carro novo.
- **Carregamento:** ~30–32 s a quente, 75–88 s no frio; os blocos grandes não foram mexidos (7.4).
- **Logo depois da cortina** (fora da amostra da bancada): viatura nascendo com `spawn_vehicle_add_child` 25 ms,
  `native.ready.rewards` 18–21 ms no 1º lugar com interior (causa dentro de `apply_saved`/`_install_reward`, não
  isolada), `stream.harbor.prepare_collision` 7–8 ms.
- **Não medido:** rota 66, cidade do deserto, cavernas, chuva + noite juntas, 1080, D3D12, partida real pelo
  `Jogar.cmd` (clique no menu → jogável), travessia com logs depois das correções, mais de 1 rodada no frio.

## 8. 3ª rodada (22/10): pipelines com nome, cache frio e a gravação do cache de pipelines

Pedido: o mesmo pior caso (3440x1440 com as opções do jogador, chuva forte, tiro, 3 estrelas com perseguição,
25 m/s, explosões) liso em qualquer região, e carga rápida — principalmente a **primeira sessão com cache frio**.

**Resumo.** Uma sonda nova (`GETECO_PIPELINE_PROBE=1`) deu nome a cada pipeline criada no jogo. Com ela e com o
cache frio de verdade apareceram as causas: (1) o motor **regrava o arquivo inteiro do cache de pipelines a cada
3 MB novos** e isso trava a thread principal por 1–18 s na sessão fria; (2) o `RainPrewarm` **nunca tinha rodado**
(o `Weather` nascia depois dele); (3) o pipeline é por **formato de vértice**, e as variantes de pintura eram
aquecidas numa caixa; (4) faltavam combinações de pintura, o casco de peças soltas de 4 modelos, a porta da viatura
e efeitos de rua. Medido limpo, no frio do oeste (mesmo export, mesmo dia): **jogável em 118,3 → 76,7 s, maior
quadro 2 069 → 1 115 ms, quadros > 250 ms 5 → 1**. No jogo a quente as pipelines novas caíram de **58 para 4** no
oeste, mas o tempo de quadro a quente **não mudou de forma mensurável** nas rotas que ficaram limpas, e **oeste,
porto e travessia ficaram sem A/B limpo a quente**: outra sessão rodou Godot fora da fila durante quase toda a
bancada (8.1). O que não provou ganho em medição limpa ficou **desligado por padrão** (8.3).

### 8.1 Como foi medido (e o que contaminou)

- Exports pela fila (`GODOT_RUN_TIMEOUT=240 tools/run_godot_locked.sh --headless ... --export-release`), cada um
  com `working.patch` e `status.txt`: `artifacts/perf-r3-a-20261022/` (HEAD c4287f45 + sonda e marcas de etapa, sem
  mudança de comportamento) até `perf-r3-g-20261022/` (export do A/B). B–F foram passos intermediários (8.4).
- Estresse igual ao da 2ª rodada (`BENCH_DISPATCH=1`, `settings-jogador-3440.cfg`, `--benchmark-stress
  --benchmark-cold --benchmark-weapon-cycle=5 --skip-arrival`, 90 s). "Antes" = os interruptores desta rodada em 0
  no mesmo export (volta ao HEAD, que já tem os da 1ª e 2ª rodadas); "depois" = todos ligados (no export G,
  inclusive os que depois ficaram desligados por padrão, 8.3). Sem logs. Frio: `tools/bench/cold_cache_run.sh`.
- **Outra sessão rodou Godot fora da fila** (`--path D:/geteco/game --script C:/Users/rafae/Documents/Codex/...`,
  renderizado 1920x1080, ~1–4 min por vez) em 11:52–11:56, 11:58–12:04, 12:24–12:40 e várias vezes depois de 12:50.
  Um registro dos processos a cada 10 s separou as rodadas; **toda rodada com sobreposição foi descartada** (nenhuma
  aceita "marcada"), e a partir de 12:42 o executor esperava a outra sessão sair e repetia a rodada se ela
  aparecesse no meio. A mesma sessão também mexia no apresentador de loading (`ui/LoadingPresenter.cs`,
  `ui/LoadingCanvas.cs`, `runtime/StartupCurtain.gd`, `ui/MainMenu.gd`, `ui/SkyMenu.gd`); os exports E–G incluem esse
  trabalho em andamento, nos dois lados do A/B. Às 13:35 a bancada parou porque o usuário passou a usar o PC.
- Descartadas: oeste (as 4 rodadas a quente), porto (4), sobrados D1 e A2, travessia D1, deserto da 2ª volta (5
  tentativas, todas com sobreposição), travessia D2 (o frio seguinte afastou as pastas de cache com ela aberta) e o
  1º frio "antes" do oeste (13:19; a travessia D2 ainda rodava e, ao sair, gravou o cache quente na pasta afastada:
  deu 70,1 s / 915 ms, não era frio). O frio "antes" válido é o de 13:31.
- Rodadas com a sonda servem para atribuir, não para medir (ela descreve cada nó novo e revarre ~10 mil nós a cada
  quadro com pipeline nova).

### 8.2 Sonda de pipelines (`runtime/PipelineProbe.gd`, novo; diagnóstico, desligada)

`GETECO_PIPELINE_PROBE=1` cria a sonda antes do mundo (pelo `StallLog`). A cada `frame_post_draw` ela lê os 5
contadores de pipeline do motor; quando sobem, grava em `<pasta do exe>/evidence/pipeline-probe/probe-*.jsonl` as
chaves novas das `GeometryInstance3D` que entraram desde o desenho anterior: shader (ShaderMaterial pelo arquivo,
BaseMaterial3D pelas flags e texturas que mudam o código, com os nomes em `desc`), formato de vértice, primitiva,
sombra, transparência, multimesh/partícula, nó, malha e material. Com a partida jogável, o quadro com pipeline
nova também revarre os nós já vistos (material trocado em nó existente). `ProductionWorld` marca as etapas da
carga (`PipelineProbe.stage`), com duração e pipelines de cada uma. Limites: o "novo" é por quadro (não aponta a
pipeline exata dentro do quadro) e ela não vê compute de partícula nem a gravação do cache.

Dois achados laterais: **no frio o caro é o driver**, não o SPIR-V — com o Shader Baker (export sem `--headless`,
+13 MB de shaders assados) a carga fria não mudou (80,0 × 85,0 s, mesmo código, rodadas com sonda) — e **mais
trabalhadores pioraram** (`threading/worker_pool/low_priority_thread_ratio=0.9` por `override.cfg`: carga fria de
164,6 s, contra ~76–85 s). O Baker não foi adotado: só assa com o editor aberto em Vulkan, e esse export regravou o
`project.godot` (tirou a linha do driver Vulkan; devolvida, `project.godot` e `export_presets.cfg` iguais ao HEAD).
Medido no editor (12 shaders de código único): desenhados direto travam 4,3–4,8 s num quadro, um shader depois do
outro na thread principal; com `visible=false` ficam prontos em 0,6 s (os trabalhadores compilam a "ubershader" de
toda superfície criada, mesmo invisível) e ao aparecer não criam nenhuma pipeline `surface` nova.

### 8.3 Causas, correções e o que ficou ligado

"Ganho" diz como a correção foi provada. Desligado por padrão = não provou ganho em medição limpa; `=1` liga.

| # | causa | evidência | correção | ganho | padrão |
|---|---|---|---|---|---|
| 1 | **Cache de pipelines regravado inteiro a cada 3 MB novos** (`rendering/rendering_device/pipeline_cache/save_chunk_size_mb`=3) | frio, oeste, export C: padrão → quadros de 1,2 s, 1,5 s e 18,0 s sem pipeline nem shader novo no quadro, jogável em 94,8 s; com 4096 por `override.cfg` → máximo 1,33 s, 74,8 s (rodadas de 10:26–10:35, antes do registro de processos). Uma sessão fria leva o arquivo de 0 a ~75 MB; o do jogador tem 230 MB e também é regravado inteiro a cada 3 MB que a sessão junta | `Settings.apply_pipeline_cache_policy()` no autoload: 4096 MB, grava só ao sair (se o jogo cair, as pipelines da sessão se perdem; o cache de shader fica) | **medido limpo** (frio G, 8.6) | ligado, `GETECO_PIPELINE_SAVE_ON_EXIT` |
| 2 | **`RainPrewarm` nunca rodou**: chamado antes de o `Weather` existir | sonda: etapa "rain" 0,1 ms e 0 pipelines; frio (A): poça `RainPuddle.gdshader` compilando a t+4 s num quadro de 842 ms; nos exports C, D e G a poça não aparece mais no jogo | chamado depois do Weather/CityLook | sonda (contagem), sem A/B de tempo isolado | ligado, `GETECO_RAIN_PREWARM_LATE` |
| 3 | **Pipeline é por formato de vértice**; variantes de pintura aquecidas numa BoxMesh | sonda a quente, oeste: 58 pipelines `surface` no jogo (A), quase todas pintura suja/molhada/limpa e porta da viatura em formatos de carro; no editor, triângulo com o mesmo formato cobre a malha real | `runtime/FormatPrewarm.gd`: triângulo de cada formato real da frota e da porta recortada; pintura, para-brisa molhado, limpador, marca de pneu, detritos, materiais da porta da viatura (também do casco de peças soltas), cartão/poço da porta; montado **escondido** logo depois da frota (compila nos trabalhadores) e retirado antes da cortina | sonda: 58 → 16 (B) → 6 (C) → 4 (G) a quente; carga a quente igual (26,4 × 26,8 s na soma das etapas) | ligado, `GETECO_FORMAT_PREWARM`, `GETECO_FORMAT_HIDDEN` |
| 4 | **Combinações de pintura que faltavam** | frio (A): shader novo num quadro de 1 157 ms ao atirar no trânsito (sujeira + gotas que o desgaste desligou) | `_lattice`: detalhe × verniz × normal, até 18 por base | sonda (a combinação some do jogo) | ligado, `GETECO_PAINT_LATTICE` |
| 5 | **Casco de peças soltas** (cupê, Monaliza, Metro, viatura) fora do aquecimento da frota | sonda: pintura e vidro desses quatro compilando no jogo | entram no aquecimento da frota e nas bases de pintura | sonda (C: 6 no jogo) | ligado, `GETECO_BREAKAWAY_PREWARM` |
| 6 | **Efeitos de rua só no jogo** | frio (A): estouro de vidro 48 ms, gêiser 132 ms; poça de sangue | `gameplay/street_physics/StreetEffectsPrewarm.gd` com as peças do jogo | sonda (não aparecem mais em C/D/G) | ligado, `GETECO_STREET_FX_PREWARM` |
| 7 | Pré-aquecimentos em série; shader desenhado compila um por vez | soma das 13 etapas 28,8 s no frio (A) | filas paralelas de corrotina (`_prewarm_lane`, prazo de 180 s) e peças escondidas antes do desenho (`runtime/HiddenCompile.gd`; frota só escondida, `GETECO_FLEET_HIDDEN_ONLY`) | **não provado**: a carga fria com sonda não encurtou (A 78,6 s × D 76,0 s de soma das etapas) e a carga a quente limpa ficou igual | **desligado**, `GETECO_PREWARM_PARALLEL=1`, `GETECO_HIDDEN_COMPILE=1` |
| 8 | Carcaça sumindo (`transparency` em todas as malhas) | frio (D, sonda): 5 pipelines `draw` num quadro de 3 029 ms | cópia escondida de cada modelo com `transparency` 0,5 e a brasa em todos os formatos | **não provado** (não houve frio com sonda depois) | **desligado**, `GETECO_WRECK_FADE_PREWARM=1` |
| 9 | Mirante costeiro com shaders próprios a 190 m | sobrados a quente (sonda): 7 `surface` num quadro de 36 ms | entra escondido e aparece 0,5 s depois | só em rodada com sonda (36 → 24 ms) | **desligado**, `GETECO_LOOKOUT_HIDDEN_FIRST=1` |
| 10 | Raio da tempestade | frio (A): 100 ms | raio disparado (sem trovão) no aquecimento da chuva | **não**: a sonda ainda viu o raio compilar no jogo | **desligado**, `GETECO_RAIN_PREWARM_BOLT=1` |

Nada foi medido como pior em rodada limpa. A configuração padrão final (1–6 ligados, 7–10 desligados) não foi medida
inteira: o A/B do G tinha todos ligados (o frio de 8.6 inclui 7–10), e o export C (1–6 sem HiddenCompile, com as
filas paralelas) é o mais parecido medido (frio com sonda 79,2 s; a quente soma das etapas 26,1 s).

### 8.4 Pipelines criadas com a partida jogável (sonda, estresse no oeste, 90 s)

| export | o que tem | a quente: `surface` / `draw` / `specialization` | frio: `surface` / `draw` | maior quadro do jogo ligado a compilação, frio |
|---|---|---|---|---|
| A | HEAD (só a sonda) | 58 / 0 / 132 | 60 / 0 | 1 157 ms (pintura), 842 ms (poça); 7,9 s sem pipeline (gravação do cache) |
| B | + chuva depois do Weather, formatos, lattice, rua, filas paralelas | 16 / 0 / 133 | — | — |
| C | + casco de peças soltas, pintura escondida | 6 / 0 / 125 | 7 / 0 | 1 356 ms (pintura numa porta) |
| D | + HiddenCompile, gravação do cache só ao sair | — | 6 / 5 | 3 029 ms (carcaça sumindo) |
| G | + carcaça, porta da viatura do casco, insígnia, mirante, frota só escondida | **4** / 0 / 131 | — | (8.6, sem sonda) |

Nos sobrados (E/F, a quente) sobraram 20–24 `surface`, a maioria o mirante e a porta de outra viatura, e o 1º quadro
depois da cortina. As `specialization` (~130 por rodada) compilam em segundo plano enquanto o motor desenha com a
"ubershader": não esperam no quadro.

### 8.5 Resultado a quente (export G, só rodadas sem Godot externo)

| rota | lado | rodadas limpas | média | p50 | p95 | p99 | máx | > 33 ms | > 45 ms | desenho > 33 / máx | jogável (s) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| sobrados | antes | 1 | 7,08 | 5,91 | 11,48 | 15,83 | 47,46 | 5 | 1 | 2 / 48,71 | 30,81 |
| sobrados | depois | 1 | 6,81 | 5,58 | 11,07 | 15,23 | 36,53 | 2 | 0 | 0 / 26,92 | 31,78 |
| serra | antes | 2 | 6,88 | 6,08 | 11,35 | 12,95 | 32,36 | 0 | 0 | 0 / 26,12 | 31,38 |
| serra | depois | 2 | 7,04 | 6,12 | 11,65 | 13,80 | 43,71 | 5 | 0 | 2 / 37,82 | 32,44 |
| deserto | antes | 1 | 5,98 | 5,55 | 9,00 | 12,68 | 53,03 | 4 | 2 | 1 / 49,46 | 33,00 |
| deserto | depois | 1 | 6,24 | 5,89 | 9,34 | 12,83 | 51,53 | 1 | 1 | 0 / 28,25 | 31,85 |
| travessia | antes | 1 | 6,21 | 5,62 | 10,63 | 13,29 | 30,37 | 0 | 0 | 2 / 38,89 | 30,64 |
| oeste, porto | — | 0 | sem rodada limpa | | | | | | | | |

Por rodada: serra antes 6,80/6,97 de média, 0/0 quadros > 33; depois 6,82/7,26, 0/5 (máx 31,3 e 43,7). Leitura:
as diferenças de média, p50 e quadros > 33 ms estão dentro da variação entre rodadas iguais (±0,5 ms, ±1–5 quadros,
7.2) — **a 3ª rodada não mudou o tempo de quadro a quente de forma mensurável** nessas rotas; ela mudou o número de
pipelines criadas no jogo (8.4), que a quente custam 5–15 ms cada no sync do RenderingServer.

### 8.6 Cache frio (primeira sessão), oeste, 90 s, export G, sem Godot externo

| lado | média | p50 | p95 | p99 | máx | > 33 ms | > 100 ms | > 250 ms | desenho > 33 / máx | jogável (s) |
|---|---|---|---|---|---|---|---|---|---|---|
| antes (13:31) | 10,01 | 9,68 | 14,28 | 17,25 | 2 069,21 | 15 | 7 | 5 | 16 / 939,82 | 118,3 |
| depois (13:24) | 10,08 | 10,05 | 15,13 | 17,90 | 1 115,23 | 5 | 2 | 1 | 5 / 1 093,45 | 76,7 |
| ref.: só a gravação do cache, export C, padrão | 21,34 | 15,34 | 28,35 | 38,55 | 17 997,33 | 82 | 13 | 5 | 76 / 17 966,21 | 94,8 |
| ref.: só a gravação do cache, export C, 4096 MB | 10,71 | 10,62 | 16,23 | 20,57 | 1 329,85 | 20 | 2 | 2 | 15 / 1 270,92 | 74,8 |

Uma rodada por lado; o "depois" tem todos os interruptores ligados (inclusive 7–10 de 8.3, hoje desligados). As
duas linhas do export C foram rodadas antes do registro de processos (10:26–10:35): não dá para garantir que estavam
sem Godot externo. Na 2ª rodada (7.3, export E) o frio do oeste era 76,6 / 78,5 s e 2 245 / 1 268 ms. O "depois"
ainda tem **um quadro de 1,1 s a t+32 s, não atribuído** (rodada sem sonda); serra e deserto frios não foram medidos
nesta rodada.

### 8.7 Carregamento

A quente, nas rodadas limpas: antes 30,8 / 31,4 / 33,0 s (sobrados, serra, deserto), depois 31,8 / 32,4 / 31,9 s —
igual dentro de ±1 s. Soma das etapas da carga na sonda (oeste, a quente): A 26,4 s, C 26,1 s, G 26,8 s. Os blocos
grandes do pedido (túnel ~2,2 s, `resident_prewarm` ~4,7 s, `urban_operations`) **não foram mexidos**. No frio, o
ganho de 118 → 77 s é quase todo a gravação do cache (8.3 #1); as etapas que mais pesam no frio continuam sendo a
compilação de pipeline pelo driver: `session_startup` (o mundo, 143 pipelines) ~12 s, a frota ~7–8 s, os
pré-aquecimentos ~17–28 s.

### 8.8 Arquivos e interruptores

Meus (sem commit):
- Novos: `runtime/PipelineProbe.gd`, `runtime/FormatPrewarm.gd`, `runtime/HiddenCompile.gd`,
  `gameplay/street_physics/StreetEffectsPrewarm.gd` (cada um com o `.uid` que o Godot gerou).
- `runtime/ProductionWorld.gd` (marcas de etapa, filas paralelas, chuva e efeitos depois do Weather, frota escondida,
  casco de peças soltas, materiais da porta da viatura, pintura escondida), `runtime/Settings.gd`
  (`apply_pipeline_cache_policy`), `runtime/RainPrewarm.gd`, `runtime/StallLog.gd` (cria a sonda),
  `gameplay/vehicle_effects/VehicleMaterialVariantPrewarm.gd`, `runtime/coastal_lookout/CoastalLookoutRuntime.gd`.
- Uma linha (`HiddenCompile.prepare`, sem efeito com o padrão desligado) em `gameplay/emergency/EffectsPrewarm.gd`,
  `ReactionVisualPrewarm.gd`, `SpawnVisualPrewarm.gd`, `runtime/BridgeLookPrewarm.gd`, `LocalLightShadowPrewarm.gd`,
  `FamilyVariantPrewarm.gd`, `PaintedFacadePrewarm.gd`, `WildlifePrewarm.gd`, `ForgePrewarm.gd`,
  `assets/civilians/MeshyBodyPrewarm.gd`, `world/desert/DesertGroundCover.gd`; este documento.
- **Não são meus** (outra sessão, no mesmo checkout): `ui/LoadingCanvas.cs`, `ui/LoadingPresenter.cs`,
  `ui/MainMenu.gd`, `ui/SkyMenu.gd`, `runtime/StartupCurtain.gd`, `tests/test_loading_presenter.gd`,
  `tests/test_loading_slideshow.gd`, `tests/test_loading_menu_handoff.gd`, `tests/measure/measure_loading_slideshow.gd`,
  `docs/loading-smooth-20261022.md`.

Ligados por padrão (`=0` desliga): `GETECO_PIPELINE_SAVE_ON_EXIT`, `GETECO_RAIN_PREWARM_LATE`,
`GETECO_FORMAT_PREWARM`, `GETECO_FORMAT_HIDDEN`, `GETECO_PAINT_LATTICE`, `GETECO_BREAKAWAY_PREWARM`,
`GETECO_STREET_FX_PREWARM`. Desligados por padrão (`=1` liga): `GETECO_PREWARM_PARALLEL`, `GETECO_HIDDEN_COMPILE`
(com ele, `GETECO_FLEET_HIDDEN_ONLY`, padrão ligado), `GETECO_WRECK_FADE_PREWARM`, `GETECO_LOOKOUT_HIDDEN_FIRST`,
`GETECO_RAIN_PREWARM_BOLT`, `GETECO_PIPELINE_PROBE` (diagnóstico).

### 8.9 Verificação

- `tools/run_core_suite.sh --no-build` (fast, 22/10 11:58–12:25, com as mudanças daquela hora): **10 passaram, 0
  falharam** (inclusive `test_core_contracts`). Depois de desligar os interruptores 7–10: `test_core_contracts` 418
  checks, 0 falhas; `test_reaction_visual_prewarm` 32 checks, 0 falhas; antes, `test_coastal_binoculars` 36, 0.
- `--check-only` de todos os arquivos tocados e `python -I tools/check_frame_rules.py`: ok (`dynamic_light` 73,
  `mesh_readback` 67, iguais).
- O jogo carregou e jogou em release em todos os exports (A–G). **Não rodei** `run_core_suite.sh full`, os testes de
  sessão inteira, nem `tools/PlayRelease.ps1 -NoLaunch -ForceExport` (ele exporta fora da fila e o usuário estava
  usando o PC; o `Jogar.cmd` exporta sozinho na próxima vez porque há arquivos mais novos que o pacote).

### 8.10 O que ainda não fica liso, e por quê

- **A quente:** quadros > 33 ms continuam (sobrados 2, serra 5 em 2 rodadas, deserto 1); as causas da 2ª rodada
  (desenho de 19–35 ms sem pipeline, física nativa, batida) não foram reatribuídas nesta rodada. Hipótese nova, não
  provada: parte dos "picos isolados de 220–250 ms" antigos (§7 do HOW-TO-DEVELOP) pode ser a regravação do cache de
  230 MB a cada 3 MB novos, que agora não acontece mais durante o jogo.
- **Frio:** 76,7 s até jogável e um quadro de 1,1 s não atribuído; o custo é a compilação de pipeline pelo driver
  (não o SPIR-V, e mais threads pioram). Encurtar exige menos pipelines distintas (ex.: pintura com todas as
  features fixas e variando só uniform, em vez de ligar/desligar flags do StandardMaterial3D).
- **Coberto mas desligado** (sem prova limpa): carcaça sumindo (3 s no frio), raio (a cobertura não pegou), mirante.
- **1º quadro depois da cortina** (oeste): mobília do pátio da delegacia norte (2 pipelines, 37–48 ms), fora da
  amostra da bancada.
- **Sem medição limpa:** oeste, porto e travessia a quente; serra e deserto no frio; rota 66, cidade do deserto,
  estrada do sal, cavernas e chuva + noite (as rodadas foram descartadas ou não chegaram a rodar); a configuração
  padrão final inteira (8.3).

## 9. 4ª rodada (24/10, PC livre): os interruptores 7–10 da 3ª rodada a limpo

**Como.** Export release do HEAD `4dd79486` (`artifacts/perf-r4-20261024/`, `matrix.sh`, `matrix.log`, `resumo.tsv`).
Estresse igual ao da 2ª/3ª rodada (`BENCH_DISPATCH=1`, `settings-jogador-3440.cfg`, `--benchmark-stress
--benchmark-cold --benchmark-weapon-cycle=5 --skip-arrival`, 90 s). A = padrão de hoje; B = A +
`GETECO_PREWARM_PARALLEL=1 GETECO_HIDDEN_COMPILE=1 GETECO_WRECK_FADE_PREWARM=1 GETECO_LOOKOUT_HIDDEN_FIRST=1
GETECO_RAIN_PREWARM_BOLT=1`. A quente: ordem A B B A por cenário; frio (`cold_cache_run.sh`): 1 por lado.
Vigia a cada 10 s (`watch.ps1`): **nenhum Godot externo** em 00:37–01:55. **Limite:** o viewport saiu
**1920x1200** (o monitor de 3440x1440 não estava ligado); o A/B vale, os absolutos ficam abaixo do pior caso.

| cenário | lado | p50 | p95 | p99 | máx por rodada | > 33 ms por rodada | jogável (s) |
|---|---|---|---|---|---|---|---|
| oeste | A | 7,38 | 12,54 | 14,44 | 40,6 / 41,0 | 3 / 1 | 31,7 / 29,9 |
| oeste | B | 6,88 | 12,39 | 14,29 | 62,5 / 47,3 | 5 / 2 | 31,5 / 29,9 |
| porto | A | 5,42 | 11,59 | 13,75 | 57,6 / 42,7 | 4 / 2 | 29,8 / 30,1 |
| porto | B | 5,40 | 11,66 | 13,94 | 72,3 / 60,4 | 4 / 6 | 29,7 / 30,0 |
| sobrados | A | 4,43 | 9,79 | 13,41 | 33,3 / 43,6 | 1 / 1 | 30,1 / 30,1 |
| sobrados | B | 4,32 | 9,61 | 12,91 | 38,7 / 69,3 | 2 / 1 | 29,8 / 29,7 |
| serra | A | 3,46 | 8,35 | 10,03 | **501,2** / 28,7 | 3 / 0 | 32,6 / 31,3 |
| serra | B | 3,45 | 8,30 | 10,20 | 36,6 / 78,2 | 2 / 1 | 31,1 / 30,7 |
| deserto | A | 3,12 | 5,86 | 7,92 | 38,5 / 40,1 | 1 / 1 | 31,8 / 32,0 |
| deserto | B | 3,12 | 5,89 | 8,02 | 38,0 / 38,3 | 2 / 1 | 31,3 / 31,3 |
| travessia | A | 3,28 | 7,15 | 9,36 | 28,7 / 28,8 | 0 / 0 | 30,8 / 30,4 |
| travessia | B | 3,29 | 7,24 | 9,41 | 52,5 / 29,1 | 2 / 0 | 30,9 / 30,0 |
| noite (oeste, 22 h) | A | 6,46 | 11,80 | 13,79 | 37,7 / 44,2 | 1 / 3 | 30,0 / 33,7 |
| noite (oeste, 22 h) | B | 6,92 | 12,29 | 14,24 | 28,1 / 37,1 | 0 / 2 | 29,8 / 29,6 |
| frio oeste | A | 7,26 | 12,80 | 14,87 | 867,2 | 6 | 70,4 |
| frio oeste | B | 6,97 | 12,41 | 14,19 | 866,8 | 3 | 68,7 |
| frio serra | A | 3,45 | 8,20 | 9,92 | 596,1 | 5 | 71,2 |
| frio serra | B | 3,45 | 8,24 | 10,32 | 588,9 | 5 | 67,9 |
| frio deserto | A | 3,12 | 5,96 | 8,05 | 922,9 | 4 | 73,7 |
| frio deserto | B | 3,09 | 5,94 | 8,05 | 981,0 | 5 | 70,7 |

p50/p95/p99 são a média das rodadas. Leitura:
- **A quente, B não ganha:** p50/p95 iguais dentro de ±0,5 ms; o máximo piora em oeste, porto, sobrados e
  travessia (47–72 ms contra 29–58 ms). **Os interruptores 7–10 continuam desligados.**
- **Frio, B carrega 1,7–3,3 s antes nas três rotas** (uma rodada por lado, a mesma direção nas três), com os
  mesmos picos (um quadro de 0,6–1,0 s por sessão fria). Ganho pequeno e sem separar qual dos cinco o dá; não
  justifica pagar os máximos piores a quente. Candidato a medir sozinho: `GETECO_PREWARM_PARALLEL=1`.
- **Pico isolado da serra** voltou numa rodada A (501 ms, > 250 ms: 1), sem estar ligado a interruptor.
- Frio de hoje ~70 s até jogável (8.6: 76,7 s); quente ~30 s; p50 a quente ≤ 7,4 ms em todas as rotas a 1920x1200.

**Não medido nesta rodada:** 3440x1440; rota 66, cidade do deserto, estrada do sal, cavernas, chuva + noite;
atribuição (StallLog) do pico da serra e do quadro de 0,6–1,0 s do frio.

## 10. 5ª rodada (24/10): `GETECO_PREWARM_PARALLEL` sozinho, carcaça sumindo e o quadro de ~0,9 s do frio

Export `artifacts/perf-r5-20261024/` (HEAD `fa090217`), mesmo estresse e viewport 1920x1200 da §9; vigia sem Godot
externo em nenhuma das três matrizes (`matrix.sh`, `matrix_hot.sh`, `matrix_wreck.sh`; `resumo.tsv`).

**Frio, jogável (s), A = padrão, P = `GETECO_PREWARM_PARALLEL=1`, ordem A P P A:**

| rota | A | P | máx A (ms) | máx P (ms) |
|---|---|---|---|---|
| oeste | 69,5 / 73,3 | 64,6 / 68,1 | 897 / 1 856 | 102 / 114 |
| serra | 72,5 / 73,2 | 69,6 / 69,4 | 596 / 648 | 612 / 637 |
| deserto | 75,9 / 75,2 | 72,2 / 71,7 | 1 017 / 965 | 968 / 977 |
| oeste (matriz da carcaça) | 81,5 / 72,7 | 70,2 / 69,9 (com WRECK_FADE) | 1 000 / 1 706 | 883 / 861 |

P carrega 3–5 s antes nas 8 rodadas. Os máximos de 102/114 ms do oeste P **não se repetiram** na outra matriz
(861–883 ms): o quadro de ~0,9 s não depende do P.

**A quente, P × A (2 rodadas cada, A P P A), p50 médio (ms):** oeste 7,59 → 7,34; porto 5,75 → 5,72; sobrados
4,88 → 4,77; serra 3,54 → 3,56; deserto 3,21 → 3,20; travessia 3,37 → 3,33. Máximos e quadros > 33 ms dentro da
variação entre rodadas iguais (sobrados 32/65 A × 44/85 P; travessia 32/37 × 53/29). **Decisão: P ligado por
padrão** (`!= "0"` em `ProductionWorld`); `=0` volta à série. Os outros quatro (HIDDEN_COMPILE, WRECK_FADE,
LOOKOUT_HIDDEN_FIRST, RAIN_PREWARM_BOLT) seguem desligados: na §9 eles pioraram os máximos a quente.

**Carcaça sumindo não é o quadro de ~0,9 s:** com `GETECO_WRECK_FADE_PREWARM=1` o frio do oeste ainda tem 864 /
886 ms (e 944 / 898 com StallLog). No StallLog esses quadros têm processo 10–15 ms, física 5–10 ms, GPU ~3 ms e
**1–6 pipelines `draw` novas**, com carcaças e fogo na cena e nenhum nó novo. Com a sonda de pipelines
(`GETECO_PIPELINE_PROBE=1`, 2 frios) o quadro some (máx 255–261 ms) e as **7 pipelines `draw` da sessão aparecem
na carga, logo depois da etapa `meshy_bodies`**: a hipótese, **não provada**, é que sem a sonda essas pipelines
dos corpos do Meshy terminam depois da cortina. Próximo passo: medir a etapa `meshy_bodies` esperando as
pipelines dela (ou deixando os corpos escondidos mais tempo) e repetir o frio do oeste.

**Pico isolado da serra** (501 ms na §9): não voltou em 4 rodadas a quente com StallLog (máx 31–51 ms) nem nas 8
quentes desta rodada.

## 11. 6ª rodada (24/10): atribuição do quadro de ~1 s do frio e dos picos a quente

Export `artifacts/perf-r6-20261024/` com `GETECO_PIPELINE_PROBE=lite` (novo) + `HARBOR_STALL_LOG=1`; 3 frios do
oeste e 3 quentes de porto e sobrados. Rodadas de diagnóstico, fora das médias (a revarredura da sonda põe
~200 ms nos quadros com pipeline nova a quente).

**Sonda leve.** A completa descreve cada nó novo na carga e atrasava o frio a ponto de o quadro de ~1 s sumir
(2 de 2 rodadas; um quadro de 2,9 s aparecia sob a cortina). A leve só guarda ids na carga, monta o "já visto"
uma vez no 1º quadro jogável (165 ms, 25 mil nós) e só descreve em quadro com pipeline nova. Com ela o quadro
de ~1 s **continua aparecendo** (1 114 / 1 166 / 1 145 ms em t = 127 / 154 / 142 s), então ela não perturba.
Limite: peças de pré-aquecimento já apagadas não entram no "já visto", e a lista de candidatos sai larga.

**Quadro de ~1 s do frio — continua sem causa provada.** Sempre 1 pipeline nova no quadro (`surface` em 2,
`draw` em 1), 50–80 s depois de jogável, processo 10–15 ms, GPU ~3 ms. Os candidatos mudam de rodada para
rodada (pintura suja de picape, carroceria amassada, placa `wave3_sinal.glb`) e a pintura suja já está no
pré-aquecimento. Descartados: carcaça sumindo (§10), as 7 pipelines `draw` da carga (saem nas duas sondas,
depois de `audio`/`meshy_bodies`). A pilha nativa não foi gravada. Hipótese em aberto: um evento único por
sessão fria (driver ou motor) que, com a carga mais lenta, cai sob a cortina.

**Picos a quente: trechos da thread principal ≥ 5 ms** (só aparecem em quadros > 40 ms, então subcontam):

| trecho | vezes | ms | o que é |
|---|---|---|---|
| `stream.harbor.prepare_collision` (= `stream.harbor.surfaces`) | 8 | 13–27 | ator físico (despacho, ônibus) entra numa célula sem chão: `NativeRegion.prepare_collision_at` monta as superfícies da célula inteira no quadro |
| `vehicle.dents.apply` | 9 | 8–20 | malha nova do amassado + reaplicação do vidro furado |
| `gameplay.fire_at` / `bench.shoot` | 1 | 33,6 | um tiro |
| `vehicle.doors.prepare` | 1 | 19,7 | portas do carro |

**Feito: vidro em lote** (`VehicleGlassDamage._reapply_part`, `GETECO_GLASS_BATCH_REAPPLY=0` volta). O
`reapply` depois do amassado chamava `_remove_panel` por registro, cada um remontando o mapa de vizinhança e a
malha inteira da peça. Agora cada superfície monta o mapa uma vez e a malha é remontada uma vez, com o mesmo
resultado (`tests/measure/measure_glass_reapply.gd`, 6 carros: vidro idêntico; 1,6 → 0,5 ms no union_sedan,
2,8 → 1,4 ms na monaliza). **Não explica os 8–20 ms do `dents.apply`:** com os painéis acabando, o reapply
fica ≤ 3 ms; o resto do trecho (malha nova no RenderingServer com a GPU ocupada?) não foi isolado — no editor,
fora do jogo, o `_apply_job` inteiro custa 0,2–0,7 ms.

**Próximos passos:** (1) `prepare_collision_at` antecipado e fatiado para atores do despacho/ônibus (pedir a
célula seguinte pela fila do streaming antes de precisar); (2) span por parte dentro de `vehicle.dents.apply`
(malha × vidro × chuva do para-brisa) numa rodada a quente; (3) `gameplay.fire_at` e `vehicle.doors.prepare`
com span interno; (4) quadro de ~1 s do frio: gravar a pilha nativa ou testar com o cache do driver já quente e
o do Godot frio (e vice-versa) para separar driver de motor.

## 12. 7ª rodada (24/10): chão do porto por célula — a pintura das faixas andava o mapa inteiro

**Quem chamava.** Os 8 quadros de `stream.harbor.prepare_collision` (13–27 ms, §11) eram todos no oeste, logo
depois da cortina: os caminhões do cais (`PortLogistics`, nascimento e `_ground_ready`) pedem chão nas células
(3,3) e (5,3), a 2–4 células do jogador. Congelar os caminhões longe do jogador (tentado e desfeito) quebra o
ciclo do cais (`test_port_real_loading_3d`: guindaste e portão).

**Onde o chão gastava** (editor, oeste, 28 células): `HarborRoadGeometry3D.build_chunk` era o grosso, e dentro
dele `_build_markings` (4,9 ms em média, até 10 ms). Cada célula andava **todos os tracinhos de todas as ruas**
do mapa e, para cada candidato, **todos os cruzamentos e faixas de pedestre** do mapa.

**Correção** (`GETECO_MARKING_CULL=0` volta): rua e trecho fora da célula (com a folga do deslocamento da faixa)
são pulados, somando o comprimento ao `travelled` (a fase do tracejado não muda); o teste de cruzamento usa só
os que alcançam a célula. `tests/test_harbor_marking_cull.gd`: **as 60 células com registro saem com os mesmos
925 tracinhos** (posição, rumo, comprimento, cor) e a pintura de todas custa 184 → 32 ms (headless, com a
criação dos nós).

**Release** (`artifacts/perf-r7-20261024/`, N = padrão, O = corte desligado, A/B alternado, StallLog nos dois,
vigia sem Godot externo; **o OneDrive.Sync estava ocupando CPU**: carga a quente 45–52 s e fria ~86 s nos dois
lados, contra ~30 / ~70 s nas rodadas anteriores — os absolutos desta rodada não valem):

| cenário | lado | p50 | p95 | máx por rodada | > 33 ms | `stream.harbor.surfaces` > 40 ms no StallLog |
|---|---|---|---|---|---|---|
| frio oeste | N | 6,97 | 12,13 | 883 / 891 | 7 / 3 | nenhum |
| frio oeste | O | 7,46 | 12,47 | 974 / 880 | 4 / 8 | 24,9 ms e 17,9 ms |
| quente oeste | N | 7,54 | 12,77 | 38 / 46 | 2 / 3 | — |
| quente oeste | O | 7,48 | 12,73 | 26 / 37 | 0 / 2 | — |
| quente porto | N | 6,09 | 12,15 | 42 / **921** | 3 / 5 | — |
| quente porto | O | 6,08 | 12,14 | 48 / 43 | 2 / 2 | — |

Leitura: o p50 não muda (a pintura é só no streaming); os quadros com o chão lento do porto somem do StallLog
com o corte (0 de 2 frios contra 2 de 2). Os demais quadros > 33 ms ficam dentro da variação entre rodadas.

**O quadro de ~0,9 s também acontece a quente:** porto N2, t = 102 s, 921 ms, 4 pipelines `draw` + 5
`specialization`, processo 13 ms, GPU 3 ms, 2 carcaças na cena. Junto com §10–11 (sempre carcaça e fogo; a sonda
leve aponta carroceria com `transparency=1` e material com brasa `emission_operator`), a pista mais forte é a
**carcaça queimando/sumindo** em combinações que `GETECO_WRECK_FADE_PREWARM` não cobre — o pipeline `draw` é
compilado na hora do desenho. Próximo passo: na sonda leve, gravar os materiais e formatos das carcaças no
quadro do pico e cobrir essas combinações no pré-aquecimento.

Também: `test_port_logistics` e `test_port_real_loading_3d` esperavam 2400 quadros pela carga (~40 s a 60 fps)
e não chegavam ao porto; agora esperam por tempo (até 180 s). O `real_loading` volta a ter só as 2 falhas antigas
(save pessoal e estivador com caixa), iguais com o corte desligado; `test_bridge_approach_terrain` tem 2 falhas
antigas, iguais com e sem o corte.

## 13. 8ª rodada (24/10): a carcaça sumindo NÃO é o quadro de ~0,9 s

Hipótese (§12): `Vehicle._begin_wreck_fade` põe `transparency` em todas as malhas da carcaça 10 s depois da
explosão, o que leva cada material ao passe alfa (pipelines `draw`). Teste: a carcaça afunda 2,2 m em vez de
ficar transparente (`GETECO_WRECK_SINK=1`), A/B no mesmo export (`artifacts/perf-r8-20261024/`, S = afunda,
T = transparência), StallLog, vigia sem Godot externo (OneDrive ainda ativo: absolutos de carga não valem).

| cenário | lado | p50 | máx por rodada | quadros > 150 ms no StallLog (t, ms, pipelines novas) |
|---|---|---|---|---|
| frio oeste | S | 7,41 / 6,97 | 897 / 896 | (102,6 s, 897, `draw` 1) · (123,5 s, 896, `draw` 1) |
| frio oeste | T | 8,08 / 7,39 | 884 / 867 | (85,8 s, 877, `draw` 1), (131,4 s, 884, `draw` 1) · (101,3 s, 870, `draw` 1) |
| quente porto | S | 5,57 / 5,79 | 40 / 47 | nenhum |
| quente porto | T | 5,92 / 5,86 | 48 / 48 | nenhum |

**Igual nos dois lados: hipótese descartada.** O afundamento ficou no código, desligado por padrão
(`GETECO_WRECK_SINK=1` liga), e `test_destroyed_cleanup` cobre os dois modos (as 3 falhas que restam já existiam:
erro em `FragileProps3D._fade_post`). O que se sabe do quadro: **uma** pipeline `draw` (compilada no desenho),
0,87–1,17 s, sempre com 1–3 carcaças na cena, 20–80 s depois de jogável; aconteceu também a quente (§12). Para
dar nome a ela a sonda precisa de um "já visto" que inclua as peças dos pré-aquecimentos sem atrasar a carga
(a completa atrasa e o quadro some; a leve não sabe o que os pré-aquecimentos já desenharam).

## 14. 9ª e 10ª rodadas (25/10): sonda de assinatura, destroço que encolhe — o quadro de ~0,9 s segue sem dono

**OneDrive encerrado** antes destas rodadas (processo `OneDrive.Sync.Service`; o vigia não o viu voltar). A carga
continuou lenta (quente 45–48 s, frio 82–95 s, contra ~30 / ~70 s até a 6ª rodada): **o OneDrive não era a
causa**; isso continua sem explicação e os absolutos de carga destas rodadas não valem (o A/B alternado vale).

**Sonda de assinatura** (`GETECO_PIPELINE_PROBE=sig`, nova): como a completa (tudo que a carga desenha, inclusive
os pré-aquecimentos, entra no "já visto"), mas o caminho do nó só vira texto quando a chave é nova e a chave de
cada material fica guardada a sessão inteira. **Não esconde o pico** (949 e 970 ms em 2 de 3 frios). No quadro
de 864 ms (t = 97 s) a única combinação nova foi a placa `wave3_sinal.glb` derrubada, com `transparency` > 0
(`DestroyedFade3D`); no outro (t = 84 s, 834 ms) **nenhuma** combinação nova.

**Destroço que encolhe** (`GETECO_DEBRIS_SHRINK=1`): os destroços de adereço (`FragileProps3D`) encolhem em vez
de ficar transparentes. A/B (`artifacts/perf-r10-20261025/`, K = encolhe, J = transparência, frio oeste K J J K,
quente porto K J J K): frio K 902 / 117 ms, J 900 / 122 ms (o quadro de ~0,9 s em 1 de 2 dos dois lados, t = 117
e 119 s); quente igual (41–56 ms). **Sem ganho: desligado por padrão.** Fica a correção de `_fade_post` (lia
`item.kind` de registro sem `kind`), que tirava uma falha do `test_destroyed_cleanup` (sobram 2, do sumiço de
corpos, antigas).

**Resumo do quadro de ~0,9 s até aqui:** 1 pipeline `draw` (compilada na hora do desenho), 0,83–1,17 s, com 1–3
carcaças e fogo na cena, 20–80 s depois de jogável, no frio quase sempre e às vezes a quente. Descartados com A/B:
carcaça sumindo (§13) e destroço sumindo (aqui). A sonda de assinatura não vê a combinação em parte dos casos, então
a pipeline vem de algo fora da chave dela (formato de framebuffer/SubViewport, partícula, passe interno). Próximo
passo sugerido: captura com RenderDoc ou um build do motor com log de criação de pipeline (nome do shader e do
framebuffer) num frio do oeste.

## 15. 11ª–12ª rodadas (25/10, PC reiniciado): eliminação — o quadro de ~0,9 s não é explosão, chama nem driver

**Máquina:** depois do reinício o export da 5ª rodada voltou a carregar a quente em 33–38 s (53–55 s antes do
reinício); a lentidão de 24–25/10 era da máquina. OneDrive encerrado de novo (voltou com o reinício).

Cada linha é uma rodada fria do oeste com o estresse, no export `artifacts/perf-r12-20261025/`:

| experimento | quadro de ~0,9 s | leitura |
|---|---|---|
| sem explosões (`--benchmark-explode=0`), 3 | 0 de 3 (máx 107–113 ms) | parecia a causa… |
| explosões registradas (`stress.explosion_log`, novo), 4 | 4 de 4, sempre 10–13 s depois de alguma explosão | …mas com explosão a cada 8 s sempre há uma 8–16 s antes: coincidência |
| carcaça vivendo 60 s em vez de 10, 3 | 3 de 3 | não é o sumiço da carcaça |
| chama da carcaça 40 s em vez de 11, 3 | 2 de 3 | não é o fim da chama |
| uma explosão a cada 60 s, 3 | 2 de 3; **um pico 11 s ANTES da única explosão** | **explosão não é necessária** |
| `__GL_SHADER_DISK_CACHE=0`, 3 | 2 de 3 | o driver ignora a variável no Vulkan do Windows (o `.bin` foi gravado) |
| vigia da data do cache do driver a cada 50 ms, 2 | 1 de 2 | o driver gravou 1 vez no meio do jogo (t = 141 / 145 s), longe do pico (t = 100 s) |

As 3 rodadas limpas sem explosão foram sorte (o pico sai em ~70 % das rodadas frias). Os dois ajustes de
diagnóstico (vida da carcaça e da chama) foram desfeitos; fica o `explosion_log` no JSON da bancada.

**O que se sabe, firme:** 1 pipeline `draw` (compilada no desenho) por pico, 0,88–1,86 s, 30–90 s depois de
jogável, ~70 % das sessões frias e às vezes a quente, sem nó novo no quadro, fora da chave das sondas. O que
falta é uma ferramenta que dê nome à pipeline no motor ou no driver: RenderDoc, NVIDIA Nsight Graphics ou PIX
(nenhum instalado) numa sessão fria do oeste, ou um build do Godot com log em `RenderingDevice::render_pipeline_create`.

## 16. 13ª–17ª rodadas (27/10, madrugada, PC sozinho): sem transparência e carga da caçamba — as duas pistas caem

**Máquina e base:** export release de main (`artifacts/perf-q09*-20261027/`), rota oeste com estresse e despacho,
`settings-jogador-3440.cfg`, **3440×1440 real** (o monitor grande estava ligado; p50 11,4–13,4 ms, acima dos ~7 ms
das rodadas em 1920×1200), cache de shader/pipeline frio em toda sessão (`tools/bench/cold_cache_run.sh`),
StallLog ligado. Tabelas de todas as rodadas, picos por tipo e a lista da sonda em
`docs/perf-quadro09-ab-20261027.md`; logs e JSON no disco (`evidence/claude-quadro09-20261027/`, `%APPDATA%/GetecoV2/benchmark-west/q09*`).

**13ª — as três versões sem transparência juntas** (X = padrão; D = `GETECO_WRECK_SINK=1 GETECO_DEBRIS_SHRINK=1
GETECO_RETIRE_SINK=1`; X D D X X D D X): o quadro de ~1 s em X 3 de 4 (1 019 / 1 161 / 1 093 ms) e em **D 1 de 4
(1 233 ms)**. O lado sem transparência também trava: **as três ficam desligadas**.

**14ª — sonda de assinatura** (`GETECO_PIPELINE_PROBE=sig`, 4 frias): o pico apareceu em 1 de 4 (a sonda atrasa a
carga e às vezes esconde o pico, como em §14). No quadro de 1 130 ms (t = 171 s) as três combinações novas foram a
**`BedLoad` (carga da caçamba, `VehicleUsage`) com a brasa da carcaça** (emissão + triplanar, opaca), a placa
`wave3_sinal.glb` caída e uma esfera, as duas com `transparency`. A placa já tinha aparecido em §14, e o destroço que
encolhe não mudou nada; a brasa é opaca, então nenhuma das três versões sem transparência a tirava.

**15ª — carga intacta na carcaça** (K = a carga fica com o próprio material na carcaça, interruptor só desta rodada, já removido; K X X K K X X K):

| lado | sessões | pico `draw` com carcaça na cena | outros picos |
|---|---|---|---|
| X (padrão, 13ª e 15ª) | 8 | 6 (1 019–1 420 ms) | 1 (`surface`, t = 98 s, sem carcaça) |
| D (13ª) | 4 | 1 | 0 |
| sonda (14ª) | 4 | 1 | 0 |
| **K** | 4 | **0** | 1 (`surface`, t = 99 s, sem carcaça) |

Todo pico `draw` destas rodadas tem 1–5 carcaças na cena e 1–3 pipelines `draw` novas. Com a carga fora da troca de
material, 0 de 4 (contra 8 de 16 nos outros lados). O pico `surface` perto de t = 98–99 s é outro, aparece nos dois
lados e fica para depois.

**16ª — pré-aquecimento da carga queimada** (as três malhas reais de carga × os materiais da carcaça desenhadas
diante da câmera sob a cortina, em `VehicleMaterialVariantPrewarm.run`; C = com, N = sem; C N N C C N N C): pico em
**C 1 de 4** (2 416 ms com 4 pipelines `draw` e 4 carcaças) e **N 4 de 4** (1 078–1 278 ms). Parecia ajudar; a 17ª mostrou que
não. O pré-aquecimento saiu do código.

**17ª — confirmação, que derrubou a hipótese** (`tools/bench/cold_ab.sh`; A = a carga some na carcaça, B =
queima como antes; ABBAABBA): pico em **A 3 de 4** (1 `draw` de 1 050 ms, 2 `surface` de 1 102 e 1 233 ms) e em
**B 1 de 4**. Os 0 de 4 da 15ª foram sorte. Somando a noite, pico `draw` em 13 de 24 sessões com a carga queimando
e em 3 de 12 sem ela (K, C, A): diferença que 4 sessões por lado não provam. **A mudança foi desfeita**; nenhum
interruptor novo ficou no código.

**O que fica desta noite:**
- As três versões sem transparência, a carga da caçamba e o pré-aquecimento dela não acabam com o quadro de ~1 s.
- Há duas famílias de pico, separadas por `tools/bench/cold_ab_spikes.py`: `draw` (1–4 pipelines compiladas no
  desenho, sempre com 1–5 carcaças na cena) e `surface` (superfície nova, muitas vezes com 17–25 nós novos no mesmo
  quadro, t = 98–121 s), cada uma em ~25–50 % das sessões frias.
- Em 3440×1440 o pico continua igual em tamanho (1,0–2,4 s).
- **Medição:** com o pico em ~50 % das sessões, 4 por lado só separam diferença de 0 contra 4. Para uma redução
  pela metade são precisas ~15–20 sessões por lado (~1,5 h por lado); ou um log de criação de pipeline no motor.

Combinações novas que a sonda viu em jogo (lista para o próximo pré-aquecimento): fim de
`docs/perf-quadro09-ab-20261027.md`.

## 17. Deserto a quente (27/10, madrugada): a mina criava o shader mineral no quadro

Rota deserto com estresse, 3440×1440, cache quente, registro da sessão (`HARBOR_SESSION_PROFILE=1`). Estado de
main: p50 6,1–8,0 ms, máximo 39,7–47,7 ms, 1–2 quadros > 33 ms por rodada (o cartão inv-092 ainda citava 170 /
147 / 54 ms de antes das rodadas de 21–25/10). O pico com nome era `stream.desert.mining` 21–27 ms, quase todo em
`MiningBatch.finish` (spans novos `mining.batch.multimesh` / `mining.batch.body`): 16,5 ms num grupo de **4 rochas**.
Medido com janela: o primeiro `ShaderMaterial` com `mineral_surface.gdshader` custa 15,4 ms para criar; os
seguintes, 0,01 ms. Montar o MultiMesh por buffer em vez de uma chamada por peça não mudou nada (16,2–18,6 ms nos
dois lados, desfeito).

**Conserto:** `MiningBatch.prewarm_minerals` cria as quatro rochas minerais sob a cortina (com uma peça escondida
de cada) no `DesertRegion.prewarm`, que roda tanto ao começar no deserto quanto na preparação distante.
`GETECO_MINERAL_PREWARM=0` desliga. A/B no mesmo export (P = com, Q = sem, P Q Q P): etapa da mina **P 8,6 / 4,2 ms**
contra **Q 21,0 / 21,3 ms**; máximo do quadro P 40,2 / 19,8 ms (o de 40 ms é desenho, sem pipeline nova), Q 29,5 /
42,2 ms. Sobram o quadro de ~58 ms aos 3 s (desmontagem da região anterior + etapa 4 do chão do deserto) e picos de
desenho de 40–48 ms sem pipeline nova.

O quadro de ~58 ms aos 3 s: a etapa 4 do chão é a montagem das estradas (`road_geometry.build_chunk`, ~7 ms),
somada à desmontagem da região anterior (~5,5 ms) e a ~20–23 ms de desenho com 2 pipelines `surface` novas.
Com janela, o primeiro acostamento e o primeiro asfalto custam 33 e 40 ms para criar num processo novo, mas
pré-aquecê-los não mudou o quadro (R 67,7 / 48,3 ms contra S 50,3 / 55,4 ms; etapa 4 ~7 ms nos dois lados): no
jogo eles já nascem sob a cortina. Desfeito. Fica para fatiar a etapa 4 ou adiar a desmontagem.

## 18. Consertos de código dos picos com causa conhecida e investigação do quadro de ~1 s (27/10, NÃO medido)

Pedido do usuário: "faça tudo, não teste ainda". Tudo abaixo está no código, atrás de interruptor `GETECO_*`
(padrão ligado, `=0` desliga, para o A/B no mesmo export), mas **nada foi medido nem rodado**: nem testes, nem
export, nem jogo. Os números citados são das rodadas anteriores, que motivaram cada mudança.

| # | pico (rodada que mediu) | mudança | interruptor |
|---|---|---|---|
| 1 | deserto aos 3 s, ~58 ms: estradas (~7 ms) + desmontagem da região anterior (~5,5 ms) no mesmo quadro (§17) | etapa 4 do chão em 4 partes (acostamento, asfalto, pintura, resto), uma por passo (`DesertRoadGeometry.build_chunk_part`); `HeavyFrameClaim` (novo): um trabalho pesado adiável por quadro — a desmontagem da residência física (`ProductionWorld._queue_unmount`) e o refazer de rotas esperam um quadro em que o chão do deserto não montou nada, e vice-versa | `GETECO_DESERT_ROAD_SLICES`, `GETECO_HEAVY_FRAME_CLAIM`, `GETECO_UNMOUNT_DEFER` |
| 2 | viatura/ônibus entrando em célula sem chão: `prepare_collision_at` montava as superfícies da célula no quadro, 13–27 ms (§11) | `NativeRegion.request_collision_soon`: a viatura do despacho pede pela fila fatiada o chão ~2,5 s à frente (mínimo 36 m) e o ônibus 40 m à frente; quando os 12/8 m chegam lá a célula já existe | `GETECO_COLLISION_LOOKAHEAD` |
| 3 | 1º quadro depois da cortina no oeste, 32–37 ms: mobília do pátio da delegacia norte (sonda, perf-r3/r5/r6/r9/r13) | etapa nova `late_surfaces` (`runtime/LateSurfacePrewarm.gd`): MultiMesh de cilindro e caixa de cada família de material do `HarborBuildingDressing` (a luz com emissão era a que faltava) e o envelope sem material | `GETECO_LATE_SURFACE_PREWARM` |
| 3b | silhueta de oclusão: 84–101 ms no oeste quando o casco do carro do jogador ganhava o overlay (`PlayerCoupe/Shell`, `occluded_silhouette`), e a do Dante no 1º quadro jogável | na mesma etapa: overlay da silhueta num triângulo de cada formato de lataria/porta e emprestado ao corpo do jogador por 3 desenhos | idem |
| 3c | porta animada dos carros comuns redesenhados: 7 pipelines `surface` em quadros de 25–37 ms (atlas_crew_pickup, ranch_single, ranch_pickup; sonda) | `door_materials` só tinha as viaturas do despacho: agora entra um material por assinatura de shader de cada carro redesenhado do trânsito (`_collect_traffic_door_materials`), cruzado com todos os formatos da porta (as ferragens saem com posição e cor) | `GETECO_DOOR_TRAFFIC_PREWARM` |
| 4 | `vehicle.dents.apply` 8–20 ms (§11) | aplicação fatiada: uma peça por vez até ~2 ms por quadro, vidro sozinho no fim; spans `vehicle.dents.apply.mesh` / `.glass`; batida nova durante a aplicação espera, como espera o cálculo | `GETECO_DENTS_SLICED_APPLY` |
| 4b | `gameplay.fire_at` ~33 ms e `vehicle.doors.prepare` ~20 ms sem dizer onde (§11) | spans por parte: `gameplay.fire_at.{sound,muzzle,weapon_shot,damage,impact_sound,hit_effect,tracer,flesh_effect,crime,clip_changed}`, `vehicle.doors.{cut,apply,sides,details,dents_glass}`; no preparo antecipado (`warm_doors`) a montagem da folha cai num quadro depois do último passo do recorte | — (só diagnóstico) |
| 6 | carga quente ~30 s: `combat_resources` ~5 s e `resident_prewarm` ~4,9 s esperando quadros em série (§7.4) | áudio, modelos das armas e a preparação das regiões residentes viram filas junto com as de desenho (que passam a maior parte do tempo esperando a GPU) | `GETECO_LOAD_LANES` (só com `GETECO_PREWARM_PARALLEL`) |

**Investigação do quadro de ~1 s do frio (sem rodar nada, só os 18 arquivos da sonda que sobraram em
`artifacts/perf-r*/evidence/pipeline-probe/`, `tools/bench/probe_spike_events.py`).** Os quadros grandes
jogáveis são sempre 1 pipeline de ~0,83–1,0 s (ou 6 de uma vez, 3,6 s), e os "novos" que a sonda lista no
quadro caem em dois casos:
- **pipelines `draw` com transparência de instância** (`tr1`): a placa da 3ª onda (`wave3_sinal.glb`) e uma esfera
  de material padrão sumindo (destroço do `FragileProps3D` via `DestroyedFade3D`), em perf-r6 (975 ms),
  perf-r9 (864 ms) e perf-r13 (871 ms); o resto do "sempre com carcaças" também é sumiço por transparência.
  `transparency` > 0 num material opaco pede a variante do passe alfa, que não nasce com a superfície;
- **material trocado num nó que já existe** ("rescan"): pintura molhada/suja, libré com emissão e chuva no
  para-brisa num carro já desenhado (perf-r13, 3 559 ms com 6 `draw`), carcaça e carga queimando (perf-r6).
O mecanismo comum é **mudança de material ou de passe num objeto já desenhado**, que compila no desenho e não
na criação. Na 10ª rodada o destroço que encolhe pareceu igual nos dois lados, mas com 1 sessão fria de pico
por lado; e cada teste tirou uma fonte só, deixando as outras.

O que entrou para fechar isto: (a) os adereços do kit no passe alfa, com malha e material reais, sob a cortina
(`GETECO_PROP_ALPHA_PREWARM`, parte do `late_surfaces`); (b) **registro de eventos na sonda**
(`PipelineProbe.note`): carcaça, carcaça sumindo/afundando, destroço sumindo, carro novo e pintura molhada vão
ao arquivo com tempo e quadro; `tools/bench/probe_spike_events.py` lista os eventos dos 3 s antes de cada
quadro grande e conta, por tipo, quantas vezes o evento precedeu um pico contra quantas aconteceu sem pico.

**Próximo passo (quando o usuário liberar o teste):** compilar e rodar a suíte; export; frio com
`GETECO_PIPELINE_PROBE=sig` em 15–20 sessões (o pico sai em ~50 %), ler `probe_spike_events.py`; A/B de cada
interruptor acima no mesmo export (quente para 1–4 e 6, frio para 3/3b/3c e o adereço). Combinar com
`GETECO_DEBRIS_SHRINK=1` + `GETECO_WRECK_SINK=1` + `GETECO_WRECK_FADE_PREWARM=1` juntos num lado (todas as
fontes de transparência fechadas ao mesmo tempo), que ainda não foi feito com sessões suficientes.

## 19. Quadro de ~1 s do frio: separar compilação de shader (Godot) de pipeline nativa (driver) (28/10, NÃO medido)

Feito só no código, sem abrir o jogo. **Por que as 17 rodadas não acharam o dono:** o contador do motor só diz
"1 pipeline `draw`". O tempo pode estar em dois lugares que ele não separa:
- **(S) código de material novo**: o Godot compila GLSL → SPIR-V e grava em `user://shader_cache`. Um material
  StandardMaterial3D com combinação nova de recursos (transparência, emissão, triplanar...) é shader novo, e nenhum
  contador de pipeline mostra essa compilação.
- **(P) pipeline nativa**: o driver compila o SPIR-V para a GPU (cache em `user://vulkan` e no cache do driver).

As duas pistas batem com o que se sabe: o pico só aparece frio, tem o mesmo tamanho em 1920 e em 3440 (é CPU) e
vem depois de material trocado num objeto já desenhado (§18). No cache de hoje, cada versão de material do
`SceneForwardClusteredShaderRD` tem ~115–130 KB de SPIR-V, então compilar uma delas não é barato.

**O que entrou:**
- `StallLog`: depois de um quadro de **≥ 250 ms**, uma tarefa de fundo lista o que nasceu desde o início do quadro
  em `user://shader_cache` (ShaderRD, versão, arquivo, bytes), no cache do driver (`__GL_SHADER_DISK_CACHE_PATH`)
  e em `user://vulkan`. O resultado vai para o registro `slow_compile_cache`. Na thread principal essa varredura
  levou 0,7–0,8 s com o cache real; na tarefa de fundo ela não pesa no quadro. Teste:
  `tests/test_stall_log_compile_cache.gd`.
- `tools/bench/cold_cache_run.sh`: `COLD_PART=all|shader|pipeline` escolhe o que esfria.
  `tools/bench/cold_ab.sh`: `COLD_PART_A` e `COLD_PART_B`, um por lado.
- `tools/bench/cold_ab_spikes.py`: cada pico mostra `godot=N driver=N [ShaderRDs]`.

**Como ler, numa noite com o PC sozinho:** export novo, e depois
`COLD_PART_A=shader COLD_PART_B=pipeline tools/bench/cold_ab.sh artifacts/<export> q10 ABBAABBAABBA`.
- Pico com `godot=1+` (SceneForwardClustered) e o lado `pipeline` (shader_cache quente) sem pico: é **(S)**. O
  conserto é pôr a combinação de material no pré-aquecimento ou reaproveitar o material em vez de duplicar.
- Pico com `godot=0` e o lado `shader` (pipeline quente) sem pico: é **(P)**. O conserto é desenhar aquela
  pipeline sob a cortina.

Uma sessão fria com pico e o registro `slow_compile_cache` já separa (S) de (P). O A/B só confirma.

## 20. Bancada fria de 28/10 (noite, PC sozinho, 3440×1440): o que caiu e o que sobrou

Export `artifacts/perf-q10-20261028` (main de 28/10 com `slow_compile_cache`), rota oeste com estresse e despacho,
`settings-jogador-3440.cfg`. Total de 18 sessões frias.

**Shader frio × pipeline fria** (`COLD_PART_A=shader COLD_PART_B=pipeline`, ABBAABBAABBA):

| lado | frio | sessões com quadro ≥ 1 s | `slow_compile_cache` no pico |
|---|---|---|---|
| A | só `shader_cache` | 3 de 6 (1,24 / 1,31+1,25 / 3,52 s) | `draw`: godot=0 nos 3 picos; `surface` (98,7 s): godot=1, SceneForwardClustered |
| B | `vulkan/` + driver | 2 de 6 (1,11 / 2,38 s) | o driver gravou no `.bin` do GLCache (um arquivo único de ~78 MB, que só cresce: prova pouco) |

**Sem explosão** (`--benchmark-explode=0`, frio total, 6 sessões): pico em **4 de 6** (1,21 / 2,24 / 2,28 / 3,36 s),
com **zero carcaças**, mais tarde (t = 166–182 s; com explosões era 92–104 s) e um `surface` de 1,15 s com godot=1.

**Conclusões:**
- **Família `surface` = código de material novo (S).** Nas duas sessões com o shader frio que tiveram esse pico, um
  `SceneForwardClustered` novo foi gravado no quadro. Falta saber qual material. Os arquivos ficaram em
  `%APPDATA%/GetecoV2/cache-cold-q10A8/` e `cache-cold-q10X1/`: mapear o hash para o material é o próximo passo.
- **Família `draw` não é (S)**: godot=0 em todos os picos `draw` com o shader frio.
- **Carcaça e explosão caem de vez**: sem explosão, o pico vem em 4 de 6, com zero carcaças. A ligação com
  carcaça das rodadas de 27/10 era coincidência de horário: explosão a cada 8 s.
- **O cache não salva o `draw`**: com `vulkan/` e o cache do driver quentes (lado A), o pico se repete em sessões
  seguidas (A4, A8, A9). Ou a pipeline não fica no cache, ou o tempo não é de compilar. Em todo pico `draw` há
  também 3–6 compilações `specialization` no mesmo quadro, e `render_cpu_ms` fica em ~2 ms. O tempo está numa
  espera fora do desenho medido, o que é compatível com a thread de render esperando compilação nos workers.
- **Nada nasce no quadro do pico** (nodes_delta 0, objects_delta −2…5): é algo que já existia, desenhado de um
  jeito novo (entrando na tela, passe novo, luz nova).
- Também descartadas: ambulância (há picos sem nenhuma) e troca de arma (só as quatro de sempre).

**Próximo passo:** (1) identificar o material do `surface` pelo arquivo do cache frio; (2) para o `draw`, testar a
espera nos workers, isto é, se `WorkerThreadPool` está ocupado no quadro do pico (StallLog pode contar tarefas
pendentes), e depois trace do motor (Tracy/Nsight). O pico em ~50 % das sessões frias continua.

### §20.1 — o pico "surface" era o shader do sangue no veículo (29/10)

`tests/measure/map_shader_cache_files.gd --watch` (editor com janela, cache frio numa pasta separada, bancada de
estresse oeste com troca de arma) pegou o arquivo do pico (`SceneForwardClustered cdfe2a8d…/1605d394…`, o mesmo das
sessões A8 e X1) na 2.ª rodada. Nos 3 quadros anteriores, só um material de shader novo apareceu pela primeira
vez: `VehicleBlood.gdshader`, no para-choque dianteiro de viatura que se solta (`VehiclePanelDebris` copia o
overlay de sangue do carro). Por isso é raro (2 de 18): precisa de viatura com sangue e peça arrancada.

Conserto: `VehicleBlood.warm_material()` entra nos materiais de efeito de `VehicleMaterialVariantPrewarm`.
Confirmado com cache frio: o arquivo `1605d394…` agora nasce na carga, sob a cortina (antes, 162 arquivos na carga
sem ele). **Não medido:** bancada fria no export release depois do conserto; o pico "draw" continua sem dono.

### §20.2 — A/B frio do sangue no export release (29/10)

Export `artifacts/perf-blood-20261029/` (HEAD `ddcc3337` + interruptor `GETECO_BLOOD_PREWARM=0`), rota oeste com
estresse, despacho e troca de arma, 3440x1440, cache frio em toda sessão, ordem ABBA. A = sangue pré-aquecido (o
padrão), B = `GETECO_BLOOD_PREWARM=0` (como antes de `077dd913`). 30 de 32 sessões (parado para o PC reiniciar).

| lado | sessões | com quadro > 700 ms | `surface` | `draw` |
|---|---|---|---|---|
| A, pré-aquecido | 15 | 1 | 0 | 1 (2341 ms) |
| B, sem | 15 | 6 | 2 | 5 |

- O `surface` sumiu do lado A (0 de 15 contra 2 de 15), como esperado pelo §20.1.
- O `draw` também caiu (1 contra 5). Não era esperado: o `draw` tem godot=0 (nenhum shader novo no quadro). Uma
  leitura possível é que o sangue sem pré-aquecimento compila o shader num quadro curto e a pipeline de outra
  passagem dele (sombra, profundidade) só é montada quando aparece de outro jeito. **Não provado**: 15 por lado
  separa 1 de 5 com folga razoável, mas não diz a causa do `draw` que sobrou no A.
- A sessão 30 (B) saiu anômala (p50 68 ms, carga 187 s; provável máquina ocupada perto do reinício) e conta como B com pico;
  sem ela o B fica 5 de 14.
- p50 e carga iguais entre os lados (p50 11–13 ms, carga ~84–87 s).
