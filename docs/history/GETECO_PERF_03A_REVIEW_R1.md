# GETECO-PERF-03A-R1 — Revisão de prontidão e errata técnica

Data: 2026-09-15/16. Autor: Claude. Revisão **somente leitura** da entrega
`c1741ad` (GETECO-PERF-03A). Nenhum código de produção, teste existente,
save ou configuração foi alterado nesta rodada. Nenhum Godot foi executado
(sem import, sem benchmark, sem suíte de regressão, sem profiler). O
Antigravity trabalha em paralelo na 03B/Mountain Pass — nada aqui toca
`world/mountain_pass/` ou `prototypes/gameplay_repair_art_0909/`.

## 0. Estado do repositório e proteção do trabalho

| item | valor |
|---|---|
| Branch | `main` |
| HEAD no início e no fim desta revisão | `c1741addab4f5e1bb3e579a2a40e9b2104981e02` (idêntico nas duas pontas — ver hashes abaixo) |
| Commit da entrega 03A revisado | `c1741ad`, confirmado presente em `git log`, examinado via `git diff 45ba477 c1741ad -- <arquivo>` sem checkout |
| Base anterior (45ba477) vs patch entregue (c1741ad) vs árvore atual | **coincidem**: a árvore de trabalho atual é bit-a-bit igual a `c1741ad` para os 4 arquivos de produção e para `tests/test_south_port.gd` (`git diff HEAD -- <arquivos>` vazio) |
| Alterações locais de outras sessões, preservadas intactas | `characters/Player.gd`, `systems/RegionTravel.gd`, `systems/interiors/ExteriorOcclusion.gd`, `world/harbor/HarborArrivalStop.gd`, `world/harbor/campaign/HarborArrivalMission.gd`, `docs/measurements/review-0909/load_profile.txt`, 2 testes apagados por outra sessão — nada disso foi tocado ou staged |
| Arquivos novos do Antigravity detectados (não tocados) | `tests/perf_audit_antigravity/probe_isolate_mountain_jobs.gd`, `profile_mountain_construction.gd`, `profile_mountain_steps.gd`, `results/isolate_appdata/`, `results/profile_appdata/`, `results/test_drive_appdata/` — apareceram entre o início e o fim desta revisão; confirma trabalho concorrente real, nenhum arquivo meu foi afetado |
| Comandos proibidos executados | nenhum (`checkout`/`restore`/`reset`/`clean`/`stash`/`git add`/`commit`/`push`/worktree: **nenhum**) |
| Godot/benchmarks/import/suíte de regressão executados nesta revisão | **nenhum** — apenas leitura de `.gd`/`.md` e cálculos em Python/bash sobre `report.json`/`summary.json` já existentes de execuções da própria rodada 03A |

### Hashes dos arquivos centrais (`git hash-object`)

Idênticos no início e no fim desta revisão — nenhuma mudança concorrente
nos arquivos revisados durante a leitura:

```
fcbee9c2bff84dbb15c11e85848fa8a541d3a26e  world/harbor/HarborSouthPort.gd
28b28fab33af985f1e6709e8fc31f26f96d59b90  world/harbor/HarborPreview.gd
e7b9c6f1a9bcd3fe1eb3d3acd56d34f1b9a9b1cd  world/harbor/HarborGame.gd
8baf83d051fba241e9354079f469c7b510bbfe7f  geodata/roads/RoadLighting.gd
ffbeb1a53ab6bbb67a0b6498caec6b42eb3a84ba  tests/perf_audit_claude/measure_loading_03a.gd
2a48a8e548d39721fb1257515bd6c4bba8fd693c  docs/history/GETECO_PERF_03A_LOADING_2026-09-15.md
4288065a0d24064b100f78f97ca87eb7e1308d6d  tests/test_south_port.gd
55bcaf72ec8a3e804c4ca2673cb1b3665644d651  ui/GameLoading.gd
3857be44321c4ea11123e242f82aaadba8c6e32a  ui/LoadingWorkBatch.gd
addefff2936af55785156f68bacb1b1694388d64  ui/HarborMinimap.gd
```

Nenhuma combinação de estados diferentes foi apresentada como versão
estável: tudo abaixo se refere a `c1741ad` == árvore de trabalho no momento
desta revisão.

---

## 1. Resumo executivo (até três conclusões, com limites)

1. **Defeito confirmado por leitura estática, não por execução**:
   `world/harbor/HarborGame.gd` perdeu a linha `add_child(soundscape)` ao
   entrelaçar meus checkpoints com os dois hunks da outra sessão. O nó
   `HarborSoundscape` é criado mas nunca entra na árvore — nenhum
   `_ready()`, nenhum `AudioListener2D`, e pelo menos 9 arquivos de teste
   (`test_footstep_ambience.gd` etc.) chamam `get_node("HarborSoundscape")`
   sem `_or_null`, o que deve falhar. **Limite**: não executei Godot para
   confirmar em runtime; é evidência estática de alta confiança (a linha
   está ausente e nada mais no arquivo a substitui), não reprodução.
2. **As tabelas de métricas da seção 4/4.1 do relatório original têm
   números corretos individualmente, mas em várias linhas a coluna
   "depois" foi ordenada de forma independente da coluna "antes"** (por
   valor, não por execução), quebrando o pareamento execução-a-execução.
   O sintoma que a tarefa apontou (par de Continuar com aparente redução)
   é exatamente esse artefato de exibição — confirmado e corrigido na
   seção 4 abaixo. As faixas de variação publicadas (ex.: "+65% a +115%")
   coincidem por sorte com o pareamento correto na maioria das linhas, mas
   duas ou três não coincidem (detalhado abaixo). **Limite**: a causa raiz
   de fundo dos números (o fatiamento em si) não muda; é um erro de
   apresentação/pareamento, não de medição.
3. **O contrato de prontidão (`gameplay_ready`/`world_build_ready`/
   `port_ready`) está, na prática, protegido pela árvore pausada** — nenhum
   consumidor pausável roda entre `gameplay_ready=true` e o despausar real
   em `GameLoading._run()`. Mas existe **um consumidor real, não coberto
   por nenhuma espera, que assume `SouthPort` completo só porque foi
   `add_child`ado antes**: `ui/HarborMinimap.gd:93-96` lê
   `SouthPort.sites` sem checar `port_ready`. Isso é uma hipótese de risco
   com evidência de código concreta, **não reproduzida em runtime**
   (mesma classificação da regressão do `RoadLighting` antes de eu
   corrigi-la — a diferença é que aqui eu ainda não corrigi nem reproduzi).

---

## 2. Mapa de produtores/consumidores e revisão de prontidão

### 2.1 Tabela produtor/consumidor

| flag/sinal | produtor | momento | consumidor | dependências exigidas | arquivo:função:linhas |
|---|---|---|---|---|---|
| `gameplay_ready` | `HarborGame._start_gameplay()` | após `_spawn_motorsport_weather()`, antes de `PersonalCarManager` | `GameLoading._run()` (poll) | também `world_build_ready`; termina fase `world_build`, mas **não** espera o resto de `_start_gameplay()` | `world/harbor/HarborGame.gd:95` produtor; `ui/GameLoading.gd:153` consumidor |
| `gameplay_ready` | idem | idem | `HarborGame._process()` | `is_instance_valid(restaurant_life)` — protegido | `world/harbor/HarborGame.gd:203-208` |
| `gameplay_ready` | idem | idem | `PortBossGarage._process()` | `player()`/`actor()` (nó `$Player`, sempre existe; não depende da cauda de `_start_gameplay()`) | `world/harbor/PortBossGarage.gd:257-264` |
| `gameplay_ready` | idem | idem | `HarborWorldEvents._process()` | o próprio `WorldEvents` só é criado **depois** de `gameplay_ready=true` — checagem sempre verdadeira quando o nó existe, guarda redundante mas inofensiva | `world/harbor/events/HarborWorldEvents.gd:25` |
| `gameplay_ready` | idem | idem | `BankAftermath._sync()` | nó de sala do banco, não depende da cauda de `_start_gameplay()` | `world/harbor/events/BankAftermath.gd:22` |
| `gameplay_ready` | idem | idem | ~60 testes/capturas (`while not world.gameplay_ready: await process_frame`) | variável por teste | `tests/*.gd` (grep completo na seção 3.4) |
| `world_build_ready` | `HarborPreview._start_review()` | após esperar `SouthPort.port_ready` (quando existe) | `GameLoading._run()` (mesmo poll) | — | `world/harbor/HarborPreview.gd:89` produtor; `ui/GameLoading.gd:153` |
| `SouthPort.port_ready` | `HarborSouthPort._ready()` | ao final, após markers/lights/checkpoint/HUD | `HarborPreview._start_review()` | espera explícita, correta | `world/harbor/HarborSouthPort.gd:86` produtor; `world/harbor/HarborPreview.gd:87` consumidor |
| `SouthPort.port_ready` | idem | idem | `RoadLighting._build()` | espera explícita, correta (correção 03A) | `geodata/roads/RoadLighting.gd:44` |
| `SouthPort.port_ready` | idem | idem | **`HarborMinimap._ready()` — NÃO CONSOME A FLAG** | lê `SouthPort.sites` sem esperar `port_ready` | `ui/HarborMinimap.gd:93-96` — ver 2.3.D |

### 2.2 O que realmente termina o loading e libera o jogador

`ui/GameLoading.gd` mantém `get_tree().paused = true` desde o início de
`_run()` até imediatamente antes de `finished.emit()` (linhas 183 e 198,
os dois pontos de saída — novo jogo e continuar). Isso significa que
**toda e qualquer lógica `PROCESS_MODE_PAUSABLE`** (o padrão do motor;
nenhum dos nós discutidos abaixo declara `PROCESS_MODE_ALWAYS`, exceto os
já catalogados) fica inerte entre `gameplay_ready=true` e o despausar —
independentemente de quando a flag virou true. Isso é a proteção de fato
contra a maior parte dos riscos que a rodada 03A introduziu.

`get_tree().paused=false` só acontece depois de: `world_build`,
`vehicle_models`, `resident_vehicles`, `emergency`, `audio`, 4 quadros de
`_draw_frame()`, e (novo jogo) esperar `opening_complete`. **Nenhuma dessas
fases espera a cauda de `_start_gameplay()` terminar** (`PersonalCarManager`
até `GameplayPresentation`) — elas correm como corrotina independente,
sincronizada só por `gameplay_ready`/`world_build_ready`, não por um sinal
de "`_start_gameplay()` completo".

### 2.3 Respostas específicas

**A. Existem checkpoints depois de `gameplay_ready=true`? Sob quais
condições eles realmente suspendem?**

Sim — 5 dos ~9 `await batch.checkpoint(get_tree())` de
`HarborGame._start_gameplay()` ficam depois da linha 95
(`gameplay_ready = true`). `LoadingWorkBatch.checkpoint()`
(`ui/LoadingWorkBatch.gd:7-10`) só suspende de fato (`await
tree.process_frame`) quando `GameLoading` não existe/não está ativo **ou**
já passaram ≥6000 µs desde o último yield real; do contrário retorna
imediatamente, sem ceder o quadro. **Presença de `await` no texto não é
suspensão garantida** — é condicional ao orçamento de 6 ms acumulado.
Confirmado na prática nesta revisão: o grupo `WorldEvents`→`Minimap`
(6 `add_child` sem checkpoint interno) e o checkpoint imediatamente depois
dele **não geram nenhum quadro real perceptível entre os marcadores**
(diferença de 2,2 ms entre os timestamps de `Minimap` e
`GameplayPresentation` em `deferred_child_added`, medido em
`03a_after_fixed_new_1/report.json`) — mesmo havendo, em tese, um
`await batch.checkpoint()` entre eles.

**B. Durante uma suspensão, qual consumidor pode avançar? Ele espera
outro estado que já o protege?**

Qualquer nó `PROCESS_MODE_ALWAYS` na árvore pode avançar durante uma
suspensão real (a árvore continua paused, mas nós `ALWAYS` ignoram pause).
Catalogados como `ALWAYS` e relevantes à cadeia de `_start_gameplay()`:
`HarborArrivalMission.gd`, `CobraCampaignController.gd`,
`CobraCampaignBridge.gd`, `CobraAftermath.gd` — todos adicionados **antes**
de `gameplay_ready=true` (grupos 2 e 4 de checkpoint). Inspecionei seus
`_process`/`_physics_process`: nenhum lê `ResidenceManager`,
`ContinuousWorld`, `PersonalCarManager`, `Minimap`, `UrbanTransit` ou
`WorldEvents` (os nós criados na cauda, depois de `gameplay_ready`).
`HarborArrivalMission._process()` lê `first_favors` só via
`is_instance_valid()` — protegido. **Isto não é novo desta rodada**: esses
nós já eram `ALWAYS` e já tickavam antes de qualquer coisa; a única
diferença é que agora há mais quadros reais de intervalo antes que o resto
de `_start_gameplay()` exista — mas como nenhum deles lê os nós tardios,
não encontrei um caminho de execução que quebre por isso.

**C. Quem encerra o loading, libera input, restaura o save e inicia
campanha/simulação? As dependências necessárias estão disponíveis?**

`GameLoading._run()` encerra (linhas 183/198): despausa, silencia
`finished.emit()`. A restauração de save e o início de campanha
(`campaign_controller.start_or_resume()`) acontecem **dentro** de
`_start_gameplay()`, no grupo 2, **antes** de `gameplay_ready=true` — ou
seja, antes mesmo do ponto que `GameLoading` espera. Isso está protegido.
O que **não** está garantido disponível no momento do despausar: `Minimap`,
`UrbanTransit`, `ResidenceManager`, `ContinuousWorld`,
`PersonalCarManager`, `WorldEvents`/`restaurant_life`/`Robberies`/
`ClothingShops`, e a chamada `RegionTravel.finish_arrival(self)` — todos
na cauda de `_start_gameplay()`, sem qualquer gate esperando por eles antes
do despausar. **Diferença entre nó existente, configuração concluída e
disponibilidade de uso**: o nó pode não existir ainda (`has_node()`
retornaria false) no instante exato do despausar, se a cauda ainda não
tiver alcançado aquele `add_child`. Não encontrei nenhum consumidor de UI
ou gameplay que leia esses nós **antes** de eles existirem sem checar
`has_node`/`is_instance_valid` primeiro — mas também não tive tempo de
auditar exaustivamente todo consumidor de `Minimap`/`UrbanTransit` fora do
próprio `_start_gameplay()`; isso é uma lacuna registrada, não uma
garantia.

**D. Há consumidores que assumem que `SouthPort` terminou logo após
`add_child`/`_ready`? Esperas circulares?**

Sem ciclo: `RoadLighting` e `HarborPreview` esperam `SouthPort.port_ready`;
`SouthPort` não espera nenhum dos dois. Confirmado por leitura completa dos
três arquivos.

Mas **sim, existe um consumidor desprotegido**: `ui/HarborMinimap.gd`,
`_ready()`, linhas 93-96:

```gdscript
for path in ["District","EastDistrict","NorthDistrict","SouthPort"]:
    var district: Node2D = world.get_node(path)
    for site: Dictionary in district.sites:
        _buildings.append(Rect2(district.to_global(site.bounds.position),site.bounds.size))
```

`SouthPort.sites` é populado progressivamente dentro de
`_build_buildings()`/`_build_port_models()`, ao longo de **dezenas** de
`await batch.checkpoint()` — só está completo quando `port_ready=true`.
`HarborMinimap` é criado dentro de `HarborGame._start_gameplay()`, numa
corrotina **completamente independente** de `HarborPreview._start_review()`
(a que espera `port_ready`) — as duas são disparadas por
`call_deferred()` separados a partir de `HarborGame._ready()`/
`super._ready()`, sem nenhuma sincronização entre si além de ambas lerem
(ou não) a mesma flag. **Antes da 03A isso não era um risco**: `SouthPort`
era 100% síncrono, então qualquer `call_deferred()` (incluindo o que
dispara `_start_gameplay()`) só rodava depois que a árvore inteira,
`SouthPort` incluso, já estava construída dentro do mesmo quadro. A 03A
introduziu a possibilidade de `Minimap` nascer **antes** de `port_ready`
virar true.

- **Sequência de execução que permite o defeito**: (1) cena carrega,
  `HarborPreview._ready()`/`HarborGame._ready()` disparam
  `_start_review()` e `_start_gameplay()` via `call_deferred`; (2)
  `_start_gameplay()` progride mais rápido que `_start_review()` através de
  seus próprios ~9 checkpoints (isso depende do custo relativo de cada
  cadeia, não é garantido nem impossível); (3) `_start_gameplay()` alcança
  `add_child(minimap)` enquanto `SouthPort._ready()` ainda está em algum
  `await batch.checkpoint()` no meio de `_build_buildings()`/
  `_build_port_models()`; (4) `HarborMinimap._ready()` lê
  `SouthPort.sites` com menos de 5 entradas (o array final tem 5 — ver
  `HarborSouthPortLayout.WAREHOUSES`/definitions).
- **Condições necessárias**: a corrotina de `_start_gameplay()` (7
  checkpoints até o grupo do Minimap) precisa ser, na soma, mais rápida em
  tempo real do que a de `_start_review()` até completar a espera de
  `port_ready` (que por sua vez depende de todo `SouthPort._ready()`,
  dezenas de checkpoints). Não medi os dois lados desta corrida
  diretamente — **classificação: evidência estática, não reproduzida em
  runtime**.
- **Correção mínima proposta (não aplicada)**: no início de
  `HarborGame._start_gameplay()`, ou imediatamente antes da criação do
  `Minimap`, adicionar o mesmo padrão já usado em
  `HarborPreview._start_review()`/`RoadLighting._build()`:
  ```gdscript
  if has_node("SouthPort"):
      while not $SouthPort.port_ready: await get_tree().process_frame
  ```
  Escopo mínimo: só afeta a criação do `Minimap` dentro de
  `_start_gameplay()`, não move nenhuma flag global e não pausa nada além
  do que já está pausado.
- **Teste necessário para confirmar (não executado)**: instrumentar
  `HarborMinimap._ready()` para imprimir
  `world.get_node("SouthPort").sites.size()` no momento da leitura, correr
  `mode=new` algumas vezes, e comparar contra `5` (contagem final
  esperada). Se algum dia vier `<5`, o defeito está reproduzido.

**E. O contrato `port_ready` garante o que `RoadLighting` precisa
consultar na física?**

`port_ready=true` é atribuído em `HarborSouthPort.gd:86`, na **última**
linha de `_ready()`, depois de `_build_markers()`, `_build_lights()`,
criação do `checkpoint` e do HUD — ou seja, depois de todo `StaticBody2D`
relevante já ter sido criado via `add_child()`. Em Godot 4, `add_child()`
insere o nó na árvore e registra sua física (via `_enter_tree`/
`NOTIFICATION_ENTER_TREE`) de forma síncrona dentro da mesma chamada — não
há um quadro de atraso entre `add_child(static_body)` e a forma
existir para consultas de `PhysicsServer2D`/`intersect_shape` **no próximo
`physics_frame`**. `RoadLighting._build()` só faz sua consulta de física
depois de `await get_tree().physics_frame` (linha 44, dentro do laço de
espera, e novamente antes de cada `_safe_pole()` via o loop principal que
já passou por `await get_tree().physics_frame` no topo da função,
linha 31). Isso é suficiente: `port_ready=true` mais um `physics_frame`
de folga (que já existe na estrutura da função) garante que a forma física
do Godot Physics Server já processou as inserções. **Não proponho uma
espera arbitrária de N quadros** — o contrato atual (flag + o
`physics_frame` que a função já aguarda antes de consultar) é
suficiente pela forma como o motor sincroniza corpos estáticos, e isso já
está implementado, não é uma lacuna.
Diferença entre "geometria criada na árvore" e "disponibilidade para
consulta": a criação (`add_child`) é imediata; a disponibilidade para
`intersect_shape` depende do próximo passo de física, que o código já
aguarda. Nenhuma lacuna encontrada aqui.

**F. Saída de cena/retorno ao menu/reinicialização — esperas acessando
instâncias inválidas?**

Verifiquei apenas os caminhos afetados por esta rodada (não uma auditoria
geral). `HarborPreview._start_review()`, `HarborGame._start_gameplay()` e
`RoadLighting._build()` são corrotinas em `self`/`get_tree()`; se a cena
for trocada enquanto uma delas está suspensa em `await
get_tree().process_frame`, o comportamento depende de o objeto (`self`)
ainda existir quando o motor tentar retomar a corrotina. Não encontrei
nenhum `await` novo desta rodada que dependa de um sinal de outro objeto
que pudesse já estar liberado (todos são `get_tree().process_frame`/
`physics_frame`, sinais da própria `SceneTree`, que sobrevive à troca de
cena) — isso reduz o risco (retomar em `self` inválido tende a gerar um
erro de script tratável pelo motor, não um crash), mas **não testei
retorno ao menu durante o loading fatiado nesta revisão nem na 03A
original**. Registrado como lacuna: o teste necessário é abrir Novo Jogo,
voltar ao menu no meio do carregamento (se a função de cancelar já
suportar isso — o relatório original diz "preservar cancelar/retornar ao
menu se já suportado", não que foi testado sob o novo fatiamento) e
observar o console por `SCRIPT ERROR` de nó inválido.

---

## 3. Errata

Formato: afirmação original | evidência | redação corrigida.

### 3.1 Atribuição categórica do gap de GPU/shader

> **Original** (seção 2 do relatório): *"O gap real é o tempo de
> desenho/present do primeiro quadro da cidade recém-populada... — GPU,
> não CPU/script, e portanto fora do escopo desta rodada."*
>
> **Evidência**: a mesma seção, duas frases depois, já se contradiz: *"é a
> hipótese que o relatório 01 já registrava sem prova, agora com uma
> medição que a torna plausível."* A única medição direta feita
> (`probe_emergency_director_03a.gd`) mediu `HarborEmergencyDirector.
> configure()` isolado sobre um mundo **já carregado** (15,319 ms) — isso
> descarta essa função como causa do gap de ~5 s, mas **não mede** o
> tempo de GPU/shader em lugar nenhum. Eliminar uma hipótese não confirma
> a outra.
>
> **Redação corrigida**: "Descartei `HarborEmergencyDirector.configure()`
> como causa do gap de ~5 s entre `CobraVehicles` e
> `HarborEmergencyDirector` (medição isolada: 15,319 ms, muito abaixo do
> gap). A causa real permanece **não isolada**: GPU/shader-pipeline no
> primeiro desenho é a hipótese mais provável dado que nenhum limite de
> quadro real cruza esse intervalo do lado do script, mas isso não foi
> medido diretamente (nenhum profiler de GPU foi usado). Rótulo: hipótese,
> não medição direta."

### 3.2 O gap de ~4,7 s não atribuído

> **Original** (seção 6): já rotulado corretamente como "não atribuído a
> uma função específica". **Sem erro aqui** — mantido como está. Rótulo:
> não atribuído.

### 3.3 Tabelas de métricas — pareamento execução-a-execução quebrado

**Isto é o achado central desta errata.** Reconstruí as tabelas a partir
dos `report.json` de cada execução nomeada (identidade de arquivo, não
posição na tabela publicada) e comparei com os números publicados.

**Seção 4 (Novo Jogo), coluna "depois"**: os números publicados em
`scene_ready`, `world_build`, `total`, `p95`, `p99`, `quadros>50ms` e
`quadros>100ms` estão em **ordem numérica** (crescente ou decrescente),
não na ordem das execuções `03a_after_fixed_new_1/_2/_3`. Exemplo
(`world_build`): publicado "22.358,2 / 22.549,6 / 27.941,9"; os valores
reais por execução são `_1=27941,9`, `_2=22358,2`, `_3=22549,6` — ou seja,
a tabela lista **execução 2, execução 3, execução 1**, nessa ordem, e o
mesmo padrão se repete nas outras linhas citadas. A coluna "antes" tem o
mesmo problema (compara `03a_fresh_baseline_new`/`03a_before_new_2`/
`03a_before_new_3` também fora de ordem em várias linhas).

**Seção 4.1 (Continuar)**: mesmo problema, mas só nas linhas
`world_build`, `total` e `p99` — as linhas `max_ms` (bloco máximo),
`p95` e `quadros>100ms` preservaram a ordem de execução corretamente.

**Isto explica exatamente o sintoma que a tarefa apontou**: pareando
`03a_continue_before_fixed` (39.134,4 ms) com a **posição 1** publicada de
"depois" (37.972,2 ms, que na verdade pertence a `03a_continue_after_
fixed_2`, não a `03a_continue_after_fixed`), o par aparenta uma queda de
~3%. Pareando pela identidade real do arquivo (`_fixed`↔`_fixed`,
`_fixed_2`↔`_fixed_2`, `_fixed_3`↔`_fixed_3`), as três execuções mostram
**aumento** de forma consistente. Recalculado abaixo (seção 4).

**Redação corrigida**: substituir as tabelas das seções 4 e 4.1 do
relatório original pelas tabelas da seção 4 desta errata, que preservam a
identidade de execução em cada linha. As faixas de variação em texto
("−36% a −56%", "+65% a +115%" etc.) **coincidem, por padrão do próprio
conjunto de dados, com o resultado correto em 6 de 9 linhas** — mas duas
faixas precisam de correção (detalhadas na seção 4) e o restante deve ser
tratado como coincidência confirmada, não como prova de que o pareamento
original estava certo.

### 3.4 "Alternadas" nem sempre descreve a coleta real das tabelas finais

> **Original** (seção 4): *"3 execuções por lado, alternadas
> (antes/depois/antes/depois...)"*.
>
> **Evidência**: os números finais de "depois" na seção 4 vêm de
> `03a_after_fixed_new_1/_2/_3`, uma bateria de 3 execuções **consecutivas**,
> rodada bem depois (em outra sessão de trabalho, após a correção do
> `RoadLighting`) das 3 execuções de "antes" (`03a_fresh_baseline_new`,
> `03a_before_new_2`, `03a_before_new_3`), que também foram, entre si,
> intercaladas com uma bateria **anterior e diferente** de "depois"
> (`03a_after_new_1/_2/_3`, a versão ainda com a regressão do
> `RoadLighting`, descartada). A alternância real ocorreu apenas dentro de
> cada bateria, não entre a bateria final de "antes" e a bateria final de
> "depois".
>
> Para o modo Continuar, a alternância **de fato ocorreu** entre as
> baterias finais: a ordem real de execução foi `after_fixed`,
> `before_fixed`, `after_fixed_2`, `before_fixed_2`, `after_fixed_3`,
> `before_fixed_3` — alternada, mas começando por "depois", não por
> "antes" como o texto de outras seções poderia sugerir.
>
> **Redação corrigida**: "Novo Jogo: 3 execuções de 'antes' e 3 de
> 'depois' no mesmo processo/máquina, mas coletadas em **duas baterias
> consecutivas separadas no tempo** (não intercaladas entre si), porque a
> bateria de 'depois' foi refeita depois da correção do `RoadLighting`
> (seção 5.4). Continuar: as duas baterias finais **foram** intercaladas,
> na ordem depois→antes→depois→antes→depois→antes."

### 3.5 `test_south_port`: "22 falhas" foi uma versão intermediária, não a entregue

> **Original** (seção 7.2, como eu mesmo já registrei): claramente
> rotulado como intermediário/corrigido. **Sem erro aqui** — mas a
> pergunta desta revisão pediu para eu confirmar que a contagem final de
> testes é exatamente **22 aprovados em 23**, com `test_continue_skips_
> opening` como a única falha, **nos dois lados** (antes e depois),
> reproduzida com assinatura idêntica. Confirmado por leitura de
> `tests/perf_audit_claude/results/03a_regressions_before/summary.json` e
> `.../03a_regressions_after_fixed/summary.json`: 22 testes com
> `exit=0` e 0 `error_lines` relevantes, 1 teste (`test_continue_skips_
> opening`) com `exit=1` e `error_lines=15`, **em ambos os lados**, mais
> `tools/check_references.py` (não conta como teste de comportamento).
> Nenhuma suíte "toda verde" foi declarada — o relatório já distingue
> corretamente "único vermelho" de "sem efeito sobre todos os fluxos"
> (seção 7.2 já tem essa frase). Rótulo: medido diretamente, confirmado
> nesta revisão.

### 3.6 `check_references.py`: 7 antes / 3 depois — classificação

Confirmado por leitura de `.../03a_regressions_before/check_references.txt`
e `.../03a_regressions_after_fixed/check_references.txt`:

- **Antes (7 achados)**: `res://../artifacts/*.png`/`*.wav` citados por
  scripts de captura visual (`tests/capture_*.gd`, `tests/render_*.gd`).
  Classificação: **arquivos de artefato não gerados nesta árvore
  específica** (a worktree temporária nunca rodou os scripts de captura
  que os produzem) — pré-existente, sem relação com o diff de produção
  desta rodada.
- **Depois (3 achados)**: `res://AchievementCatalog.gd`,
  `res://CollectibleCatalog.gd`, `res://world/shared/
  ProjectedSilhouette.gdshader`, todos citados por `.claude/settings.
  local.json`. Confirmei nesta revisão que esse arquivo é uma allowlist de
  permissões do Claude Code (contém uma string de comando `sed` histórica,
  não uma referência de recurso do jogo) e que os arquivos reais existem
  em `economy/AchievementCatalog.gd`, `economy/CollectibleCatalog.gd`,
  `systems/ProjectedSilhouette.gdshader` — um falso positivo do
  verificador (ele varre qualquer string `res://` em qualquer arquivo,
  incluindo configuração de ferramenta). **Não é uma regressão desta
  rodada.**
- Os dois conjuntos são **diferentes achados sobre árvores diferentes**
  (a worktree "antes" nunca teve esse allowlist verificado da mesma forma
  porque é uma árvore isolada fora do diretório real do projeto onde
  `.claude/` vive) — não são comparáveis como "7 corrigidos, 3 novos"; são
  duas listas de ruído não relacionado, cada uma específica ao ambiente em
  que rodou.

### 3.7 Equivalência de contagem de postes: 146 → 290 → 262 — **não demonstrada**

- `146`: contagem na worktree "antes" (`45ba477` + diffs de outras
  sessões, código original do `RoadLighting`/`HarborSouthPort`).
- `290`: contagem numa versão intermediária da 03A (fatiamento do
  `SouthPort` sem a correção do `RoadLighting`) — **descartada**, não é
  produção.
- `262`: valor de `_created`/`added` impresso por `RoadLighting._build()`
  (linha do print `ROAD_LIGHTING_AUDIT`) ao rodar `test_south_port.gd`
  sobre a árvore final (`c1741ad`), com a correção aplicada.

**146 ≠ 262.** O relatório original (seção 5.4) trata a correção como
"restaura a garantia" e mostra 262 como prova de correção, mas nunca
reconcilia por que o valor final (262) é ~79% maior que o valor original
(146) mesmo com `SouthPort` supostamente completo nos dois casos. Não
presumo que isso seja uma regressão (a lógica de `_place_pole()` é
gulosa e sensível à ordem/estado da física no instante exato da consulta;
mesmo com `SouthPort` igualmente completo nos dois casos, `RoadLighting`
agora roda **mais tarde em tempo real** — depois de esperar todo o
`SouthPort` — num mundo potencialmente com mais outros corpos físicos já
inseridos por corrotinas concorrentes de `_start_review()` como clima,
frota temática e serviços de emergência, o que pode legitimamente mudar
quais posições `_safe_pole()` aceita). Também não presumo equivalência.
**Declaro isto uma lacuna de validação**: nenhuma medida existente isola
a causa da diferença 146→262.

**Teste mínimo necessário (não executado)**: rodar
`tests/perf_audit_claude/probe_south_port_positions_03a.gd` diretamente
contra a árvore final (`c1741ad`) para obter a contagem "depois final" a
partir do mesmo instrumento usado para os 146/290 (em vez de inferir 262
do print de auditoria do `RoadLighting`, que mede a mesma grandeza mas por
um caminho de código diferente) — e comparar o **instante real** (`Time.
get_ticks_msec()`) em que `RoadLighting._build()` inicia sua primeira
consulta de física nos dois lados, para checar se a hipótese "mundo mais
cheio no momento da consulta" é plausível pela diferença de tempo
observada.

### 3.8 O que a medição "clique→pronto" realmente comprova

Verifiquei `tests/perf_audit_claude/measure_loading_03a.gd:219-220` e
`:236-237`: o coletor faz `await loader.finished` — o sinal `GameLoading.
finished`, emitido só depois de `get_tree().paused = false`
(`ui/GameLoading.gd:183/198`). Depois disso, o coletor **ainda espera 2
quadros reais adicionais** (`measure_loading_03a.gd:170`) antes de
registrar `t_first_frame_after_finished_ms`, com um comentário já correto
no próprio arquivo explicando essa escolha. **Isso é uma boa aproximação
de "primeiro input válido"** (a árvore está despausada e desenhou 2
quadros), mas não é literalmente "o jogador pressionou uma tecla e algo
respondeu" — nenhuma captura de latência de input real foi feita.
**Redação corrigida para o relatório**: onde o texto diz "clique→pronto"
sem qualificação, trocar por "clique→despausar completo (`GameLoading.
finished`) + 2 quadros de desenho real" para não implicar teste de input
literal.

### 3.9 Série temporal de frames não é captura visual — confirmado

Já declarado corretamente na seção 7.5 original ("não uma imagem
estática"). Confirmado nesta revisão: nenhum arquivo `.png`/comparação de
pixel foi encontrado em `tests/perf_audit_claude/results/03a_*`. Sem
correção necessária.

### 3.10 Medições "sequenciais" — confirmado, sem contradição

O relatório declara (seção 3): "um processo por vez, sequencial." Não
encontrei nenhuma frase no relatório que descreva as execuções como
paralelas ou simultâneas. O uso de tarefas em segundo plano nesta e na
sessão anterior foi só para orquestração do agente (aguardar um processo
Godot terminar antes de iniciar o próximo) — isso não aparece como
afirmação de concorrência no relatório entregue. Sem erro a corrigir.

---

## 4. Tabelas recalculadas (pareamento por identidade de execução)

### 4.1 Novo Jogo — antes: `03a_fresh_baseline_new`(E1), `03a_before_new_2`(E2),
`03a_before_new_3`(E3). Depois final: `03a_after_fixed_new_1`(E1),
`_new_2`(E2), `_new_3`(E3). Pareamento por posição cronológica dentro de
cada bateria (não há interleaving real entre baterias — seção 3.4).

| métrica | E1 antes→depois | E2 antes→depois | E3 antes→depois | faixa correta | faixa publicada |
|---|---:|---:|---:|---:|---:|
| bloco máximo (ms) | 22.484,8→14.427,4 (−35,8%) | 24.385,6→10.788,0 (−55,8%) | 24.226,2→10.726,0 (−55,7%) | **−35,8% a −55,8%** | −36% a −56% ✓ |
| `scene_ready` (ms) | 10.084,8→5.320,4 (−47,2%) | 11.401,2→4.795,8 (−57,9%) | 11.241,1→4.809,6 (−57,2%) | **−47,2% a −57,9%** | −53% a −58% ✗ (piso errado) |
| `world_build` (ms) | 12.973,5→27.941,9 (+115,4%) | 13.589,8→22.358,2 (+64,5%) | 13.593,5→22.549,6 (+65,9%) | **+64,5% a +115,4%** | +65% a +115% ✓ |
| `total` (ms) | 37.078,1→50.516,9 (+36,3%) | 39.801,2→43.188,0 (+8,5%) | 39.426,2→44.393,6 (+12,6%) | **+8,5% a +36,3%** | +10% a +36% ✗ (piso errado) |
| p95 (ms) | 98,9→233,2 (+135,8%) | 109,4→214,2 (+95,8%) | 106,5→180,5 (+69,5%) | **+69,5% a +135,8%** | (só números, sem %) |
| p99 (ms) | 317,9→844,9 (+165,7%) | 334,2→824,6 (+146,7%) | 332,6→960,7 (+188,9%) | **+146,7% a +188,9%** | (só números, sem %) |
| quadros >50ms | 51→156 (+206%) | 51→132 (+159%) | 51→135 (+165%) | **+159% a +206%** | "quase o dobro" ✗ (entendido) |
| quadros >100ms | 24→80 (+233%) | 31→69 (+123%) | 28→57 (+104%) | **+104% a +233%** | "quase o triplo no pior caso" ≈ ok |
| memória estática (MiB) | 986,6→984,1 | 987,1→983,7 | 987,4→985,1 | **~ -0,3%, sem mudança relevante** | sem mudança ✓ |
| VRAM (MiB) | 2.364,9→1.913,4 | 2.365,1→1.913,4 | 2.365,1→1.917,9 | **~ -19%, mesma ressalva de instante de leitura** | "mais baixa" ✓ |

### 4.2 Continuar — antes: `03a_continue_before_fixed`(E1), `_2`(E2), `_3`(E3).
Depois: `03a_continue_after_fixed`(E1), `_2`(E2), `_3`(E3). Estas duas
baterias **foram** intercaladas na execução real (seção 3.4).

| métrica | E1 antes→depois | E2 antes→depois | E3 antes→depois | faixa correta | faixa publicada |
|---|---:|---:|---:|---:|---:|
| bloco máximo (ms) | 22.279,8→13.422,7 (−39,7%) | 20.936,7→10.188,3 (−51,3%) | 22.856,6→14.893,2 (−34,8%) | **−34,8% a −51,3%** | −35% a −51% ✓ |
| `world_build` (ms) | 13.023,7→24.098,5 (+85,0%) | 12.284,0→20.467,2 (+66,6%) | 13.722,2→27.417,0 (+99,8%) | **+66,6% a +99,8%** | +57% a +100% ✗ (piso errado) |
| `total` (ms) | 39.134,4→41.174,7 (+5,2%) | 34.241,5→37.972,2 (+10,9%) | 40.839,3→51.963,4 (+27,2%) | **+5,2% a +27,2%** | +5% a +27% ✓ (mesmo com números na ordem errada na tabela original) |
| p95 (ms) | 96,8→167,9 (+73,5%) | 109,1→185,8 (+70,3%) | 131,7→251,9 (+91,3%) | **+70,3% a +91,3%** | (só números) |
| p99 (ms) | 186,2→951,7 (+411%) | 223,6→879,1 (+293%) | 273,2→965,2 (+253%) | **+253% a +411%** | "até ~4x" ≈ ok, ligeiramente subestimado |
| quadros >100ms | 29→54 (+86%) | 27→63 (+133%) | 53→75 (+42%) | **+42% a +133%** | "~1,4x-2x" ✗ (piso e teto errados) |
| memória (MiB) | 968,9→968,1 | 968,8→967,4 | 966,6→967,9 | **sem mudança relevante** | sem mudança ✓ |
| VRAM (MiB) | 2.296,1→1.854,1 | 2.296,1→1.852,6 | 2.297,7→1.854,1 | **~ -19%, mesma ressalva** | "mesma ressalva" ✓ |

**Conclusão que sobrevive à correção**: em TODAS as 6 execuções pareadas
corretamente (3 Novo Jogo + 3 Continuar), o bloco máximo cai e o `total`/
`world_build`/percentis sobem. A troca é real e consistente nos dois
fluxos — isso não muda com a correção do pareamento. O que muda são as
faixas numéricas exatas de 5 das 17 linhas de métrica (piso ou teto
levemente diferente do publicado), nunca o sinal da variação.

**Não se pode inferir FPS de gameplay** a partir destes números — são
métricas de carregamento (frame time até o despausar), não de simulação
em andamento; o relatório original já não fez essa inferência, e esta
errata reforça o limite.

---

## 5. Correção mínima proposta e teste necessário — defeitos identificados

### 5.1 `add_child(soundscape)` ausente (severidade alta, evidência estática)

**Sequência**: `HarborGame._start_gameplay()` linha 54-55 cria
`soundscape`, nunca chama `add_child(soundscape)` em nenhum ponto
subsequente da função (confirmado por `grep -n soundscape
world/harbor/HarborGame.gd` → só as 2 linhas de criação).

**Condições necessárias**: nenhuma — acontece sempre que `_start_gameplay()`
roda (todo Novo Jogo e todo Continuar).

**Correção mínima proposta (não aplicada)**:

```gdscript
var soundscape := preload("res://world/harbor/HarborSoundscape.gd").new()
soundscape.name = "HarborSoundscape"
add_child(soundscape)          # <- linha que falta
if not loaded_from_save:
    $ArrivalStop.prepare_player($Player)
else:
    $Player.show()
```

**Teste necessário**: rodar qualquer um de
`tests/test_footstep_ambience.gd`, `test_living_city_soundscape.gd`,
`test_regional_soundscape.gd`, `test_water_presentation.gd`,
`test_garage_audio_context.gd`, `test_garage_quiet_audio.gd`,
`test_harbor_presentation_audio.gd`, `test_living_city_integration.gd`,
`test_footstep_movement_and_mix.gd` — todos chamam `world.get_node(
"HarborSoundscape")` sem `_or_null` e devem falhar com `Node not found`
contra `c1741ad` sem a correção. **Nenhum destes 9 testes estava na lista
de `run_03a_regressions.ps1`** — é uma lacuna de cobertura da validação
original, não só do código.

### 5.2 `HarborMinimap.gd` não espera `SouthPort.port_ready` (severidade média,
hipótese de risco, não reproduzida)

Ver seção 2.3.D para sequência, condições e correção proposta.

---

## 6. Próximo experimento sobre o bloqueio residual (sem executar)

Usando os `report.json` finais (`03a_after_fixed_new_1/_2/_3`), o **maior
bloco totalmente síncrono ainda não fatiado dentro de `_start_gameplay()`**
(distinto do bloco dominante do `SouthPort`/`RoadLighting`, já atribuído
na seção 5/6 do relatório original) é reprodutível nas 3 execuções:

| execução | instante (`t_ms`, fim do quadro) | duração | marcador anterior | marcadores durante | marcador posterior |
|---|---:|---:|---|---|---|
| `03a_after_fixed_new_1` | 29.712,5 | 4.966,8 ms | `Cemetery` (23.989,0) | `WorldEvents`, `@Node2D` (restaurant_life), `Robberies`, `ClothingShops`, `UrbanTransit`, `Minimap`, `GameplayPresentation` (todos entre 24.838,6–24.841,4 — **span de 2,8 ms entre os `add_child`**) | `CombatImpactAudio` (51.264,4) |
| `03a_after_fixed_new_2` | 24.811,1 | 4.007,0 ms | idem (grupo anterior) | idem | idem (fase seguinte) |
| `03a_after_fixed_new_3` | 24.625,4 | 3.813,4 ms | idem | idem | idem |

**Parcela não atribuída**: 100% — nenhum checkpoint existe entre estes 6
`add_child` (é um único grupo do `LoadingWorkBatch`, igual às outras 8
divisões de `_start_gameplay()`), e o intervalo de 2,8 ms entre os
marcadores `deferred_child_added` mostra que **o custo não está na
chamada `add_child()` em si** — está em algum lugar entre elas e o próximo
`process_frame` real, que só chega ~4-5 s depois. Isso é consistente com
(a) o `_ready()` de um desses 6 nós fazendo trabalho síncrono pesado que
Godot executa em lote na notificação de entrada na árvore, ou (b) custo de
motor/GPU no primeiro desenho depois de adicionar UI nova (`Minimap` cria
um `CanvasLayer` com `Control`/`WorldMap`; `UrbanTransit`/`ClothingShops`/
`Robberies`/`WorldEvents` podem instanciar geometria nova) — a mesma
categoria de incerteza da seção 3.1, agora num ponto diferente da
timeline.

**Não uso os tempos antigos de `ResidenceManager`/`GangManager`/
caminhões/empilhadeiras (seção 2 do relatório original) para este bloco**:
eles vêm de um grupo de checkpoint **diferente** (mais cedo na sequência,
`ResidenceManager` tem seu próprio checkpoint isolado) e foram medidos na
versão **original não fatiada**, antes de qualquer slicing — não estão
vinculados a este evento específico.

**Experimento mínimo proposto (não executado)**:

1. Inserir marcadores de `Time.get_ticks_usec()` (não `await`, só
   leitura de tempo) imediatamente antes e depois de cada um dos 6
   `add_child()` deste grupo em `HarborGame._start_gameplay()` — um
   `print()` temporário por item, sem alterar ordem/conteúdo/comportamento.
2. Somar os 6 deltas medidos e comparar contra a duração externa
   observada (3,8–5,0 s). Se a soma for próxima da duração externa, o
   custo está dentro de um ou mais `_ready()` — identificar qual pelo
   maior delta individual. Se a soma for muito menor, o custo está fora
   do script (engine/GPU), reforçando a hipótese (b).
3. Se apontar para `HarborMinimap._ready()`: medir separadamente o custo
   de cada laço interno (`RoadNetwork._roads`, `HarborNorthAccess.curves()`,
   os 4 `world.get_node(path).sites`, `get_tree().get_nodes_in_group(
   "chop_shop")`, `refresh()`, `WorldMap.new()`) — isto também
   resolveria, de brinde, a pergunta da seção 2.3.D sobre quantas
   entradas `SouthPort.sites` tinha no momento da leitura.
4. Não atribuir o resultado ao Antigravity/Mountain Pass por exclusão —
   se a soma dos deltas não explicar o gap, o próximo passo é um profiler
   de GPU (fora do escopo desta revisão e desta rodada).

Este experimento separa exatamente as quatro categorias pedidas:
construção (delta de cada `add_child`/`_ready()`), espera (quanto do
checkpoint realmente suspendeu), trabalho recorrente durante o loading
(se algum desses `_process`/`_physics_process` já está ativo e competindo
por CPU nesse instante — nenhum dos 6 nós parece ter `_process` pesado por
leitura de código, mas não confirmei em runtime), e preparo gráfico
(primeiro desenho de UI/geometria nova).

---

## 7. Handoff curto ao Antigravity (03B)

Contratos que **não devem ser presumidos seguros** ao fatiar construtores
da Mountain Pass, com base no que esta revisão encontrou na versão Harbor
equivalente:

1. **`port_ready` (ou um flag equivalente) precisa ser consumido por
   TODO leitor da geometria/estado do nó fatiado, não só pelo gate
   "oficial" de loading.** Nesta rodada, `HarborPreview`/`RoadLighting`
   consomem `SouthPort.port_ready` corretamente, mas `ui/HarborMinimap.gd`
   lê `SouthPort.sites` sem checar a flag — porque ninguém audita todos os
   consumidores de um nó quando ele passa de síncrono para fatiado, só os
   que o próprio autor da mudança lembra. Antes de fatiar um construtor da
   Mountain Pass, `grep` por **todo** acesso ao nó (não só pelo nome da
   flag) e confirmar cada um.
2. **`gameplay_ready`/`world_build_ready` não esperam a cauda de
   `_start_gameplay()`** — a árvore pausada (`get_tree().paused`) é o que
   protege isso hoje, não a ordem das flags. Se qualquer construtor da
   Mountain Pass ganhar lógica `PROCESS_MODE_ALWAYS` que leia nós criados
   tardiamente em `_start_gameplay()`/equivalente, essa proteção não
   existe mais.
3. **`LoadingWorkBatch.checkpoint()` não garante suspensão a cada
   chamada** — só suspende se ≥6 ms já passaram desde o último yield real.
   Um grupo de `add_child()`s "rápidos" (na chamada) mas com `_ready()`
   caro pode atravessar múltiplos checkpoints sem nenhum quadro real
   render entre eles, exatamente como a seção 6 desta errata mostrou.
   Fatiar "por grupo" só ajuda se o custo estiver DENTRO de cada
   `add_child`/construtor, não em processamento posterior de `_ready()`.
4. **O contrato 146→262 postes de `RoadLighting` não está reconciliado**
   (seção 3.7). Se a Mountain Pass também usa `RoadLighting` (ramo
   `mountain_road`, não tocado pela 03A), o mesmo tipo de sensibilidade a
   timing pode existir lá — vale medir antes de assumir que "postes
   corretos" significa "mesma contagem de antes".

---

## Arquivos consultados nesta revisão

`AGENTS.md`, `CLAUDE.md`,
`docs/history/GETECO_PERF_03A_LOADING_2026-09-15.md` (completo),
`world/harbor/HarborSouthPort.gd`, `world/harbor/HarborPreview.gd`,
`world/harbor/HarborGame.gd`, `geodata/roads/RoadLighting.gd`,
`ui/GameLoading.gd`, `ui/LoadingWorkBatch.gd`, `ui/HarborMinimap.gd`,
`world/harbor/PortBossGarage.gd`, `world/harbor/events/HarborWorldEvents.gd`,
`world/harbor/events/BankAftermath.gd`,
`world/harbor/campaign/HarborArrivalMission.gd` (só `_process`),
`world/harbor/HarborSoundscape.gd` (início),
`tests/perf_audit_claude/measure_loading_03a.gd` (completo),
`tests/perf_audit_claude/run_03a_regressions.ps1`,
`tests/perf_audit_claude/package_03a.ps1`, `tests/test_south_port.gd`,
`git log`/`git diff 45ba477 c1741ad` para os 4 arquivos de produção,
`git status`, `git hash-object`, e os seguintes resultados já existentes
(lidos, não regenerados):
`tests/perf_audit_claude/results/{03a_fresh_baseline_new,03a_before_new_2,
03a_before_new_3,03a_after_fixed_new_1,03a_after_fixed_new_2,
03a_after_fixed_new_3,03a_continue_before_fixed,03a_continue_before_fixed_2,
03a_continue_before_fixed_3,03a_continue_after_fixed,
03a_continue_after_fixed_2,03a_continue_after_fixed_3,
03a_regressions_before,03a_regressions_after_fixed}/{report.json,
summary.json,check_references.txt}`.

## Arquivo criado nesta revisão

Somente `docs/history/GETECO_PERF_03A_REVIEW_R1.md` (este arquivo). Nenhum
outro arquivo foi criado, movido ou apagado. Nenhum arquivo de produção,
teste existente, dado bruto, save ou configuração foi alterado. Nenhum
novo teste de runtime foi escrito ou executado.
