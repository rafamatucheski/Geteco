# Verificação cruzada de desempenho (15/10/2026): regras comuns dos agentes

Objetivo do usuário: **60 fps estáveis no mínimo** (p50 ≤ 16,7 ms), sem quedas, sem quadros
grandes, inclusive nas transições de mapa e no carregamento; 144 fps (6,9 ms) onde der.
"Faça certo de uma vez": revisão sistemática do código, nada de "esqueci isso".

## Fases
1. **Agora (vocês):** revisão de código do seu sistema + correções. Sem medir desempenho.
2. **Depois (coordenador):** um export release e benchmarks em fila, 2 rodadas por cenário.
3. O que ainda cair volta para o dono do sistema com o número na mão.

## Onde olhar primeiro (evidência real)
- Linha de base em release rodando agora: `evidence/perf-cross-20261015/base.tsv` (ao terminar)
  e os JSON em `%APPDATA%/GetecoV2/benchmark-west/base_*.json`.
- Logs de sessão de cada rodada: `%APPDATA%/GetecoV2/session-logs/<data-hora>/session-000.jsonl`
  (JSON por linha). Tipos úteis: `slow_operations`, `operation_timing` (spans com nome e duração),
  `frame_spike`, `perf_window` (1/s: p50/p95/p99, draw calls, objetos), `main_thread_unresponsive`,
  `stdout` (prints de pré-aquecimento). Rodadas do benchmark começam com `--label=base_<rota>_<n>`
  nos `stdout`. Leia com `python -I`.
- Memórias do projeto: travadas já achadas e o caminho de pré-aquecimento real
  (RetainedRegionPreparation, não prewarm_incremental) — veja AGENTS.md e docs/.

## O que procurar no código (lista mínima, aplique toda)
- Trabalho por quadro sem necessidade (`_process`/`_physics_process` que poderia ser evento,
  timer ou espalhado entre quadros); varredura de cena (`find_children`, `get_nodes_in_group`)
  por quadro; alocação por quadro (arrays/dicionários/strings em laço quente).
- Construção pesada num quadro só no thread principal (montagem de prédio, chunk, interior,
  NPC, veículo); `load()`/`ResourceLoader` síncrono no meio do jogo; GLB/textura lida do disco
  na primeira aparição.
- Shader/variante de material compilada no primeiro desenho (material novo por instância,
  `duplicate()` de material, uniforms que mudam variante) sem pré-aquecimento sob a cortina.
- Luzes dinâmicas e sombras em excesso; materiais transparentes desnecessários; draw calls
  que poderiam ser MultiMesh/fusão; colisões com forma cara (trimesh) onde caixa basta.
- Física: corpos ativos demais, `move_and_slide` de quem não se vê, áreas sobrepostas.
- Transição de região/streaming: picos ao entrar trecho novo, ao trocar de mapa, ao entrar e
  sair de prédio.

## Regras de trabalho
- Leia CLAUDE.md e AGENTS.md. Comentário explica o porquê (e a medição que motivou).
- **Godot só pela fila:** `tools/run_godot_locked.sh <args>` (nunca chame o binário direto;
  ela garante um Godot por vez na máquina). Pode rodar testes funcionais para validar suas
  correções. **Não meça desempenho** (fica para a fase 2) e nunca use `--headless` para algo visual.
- **Só o seu sistema.** Se precisar mexer em arquivo de outro dono, descreva a mudança no
  relatório em vez de editar. Muitos arquivos já têm mudanças não commitadas de OUTRAS sessões:
  nunca as commite. Se o seu arquivo já estava modificado por outro, commite só os seus trechos
  (`git diff` do seu pedaço → `git apply --cached`), como já foi feito antes neste repo.
- Commits em português explicando o porquê e o que foi verificado; stage explícito; sem push;
  nunca reset/checkout/clean/stash.
- Não reduza qualidade visual nem jogabilidade para ganhar fps sem dizer explicitamente o
  tradeoff no relatório (prefira consertar código ruim a cortar conteúdo).

## Entrega (relatório curto em português)
1. Achados: arquivo:linha, por que custa, evidência (log/medição ou leitura), gravidade.
2. Correções feitas (arquivo, motivo) e commits.
3. Testes funcionais rodados e resultado.
4. O que você NÃO corrigiu e por quê; o que depende de outro dono.
5. Cenário de benchmark que você quer ver medido para confirmar (rota/ponto/ação).
