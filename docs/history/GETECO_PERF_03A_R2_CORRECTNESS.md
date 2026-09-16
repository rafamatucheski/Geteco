# GETECO-PERF-03A-R2 — Correção delimitada: HarborSoundscape e contrato do minimapa

Data: 2026-09-16. Autor: Claude. **Retomada autorizada** após a 03B ter
sido entregue pelo Antigravity. Esta entrega conclui a correção que a
primeira passagem desta tarefa deixou preparada, mas não aplicada
(coordenação pendente na ocasião).

---

## 0. Confirmação da janela e preservação

Antes de tocar qualquer arquivo, reconferi: `git status` mostrava
arquivos modificados/pastas recentes/um ZIP da 03B — nenhum disso é, por
si só, prova de edição em andamento (instrução explícita desta rodada).
O único processo Godot ativo no início era o editor interativo do
usuário (`--editor`), não um processo de teste/benchmark. Sem conflito
real identificado, segui.

**Estado registrado**: branch `main`, HEAD `c1741ad` (inalterado durante
toda a tarefa — nenhum commit da 03B foi feito neste branch ainda).
Hashes de `world/harbor/HarborGame.gd` (`e7b9c6f1a9bcd3fe1eb3d3acd56d34f1b9a9b1cd`)
e `ui/HarborMinimap.gd` (`addefff2936af55785156f68bacb1b1694388d64`)
confirmados **idênticos** aos registrados na preparação anterior — nenhuma
mudança concorrente nos dois arquivos-alvo.

**Preservado intacto, não tocado em nenhum momento**: os 6 arquivos de
`world/mountain_pass/` modificados pela 03B, `tests/perf_audit_antigravity/`
inteiro, `docs/history/GETECO_PERF_03B_MOUNTAIN_STREAMING_2026-09-15.md`,
e as alterações locais de outras sessões já documentadas nas rodadas
anteriores (`characters/Player.gd`, `systems/RegionTravel.gd`,
`systems/interiors/ExteriorOcclusion.gd`, `world/harbor/HarborArrivalStop.gd`,
`world/harbor/campaign/HarborArrivalMission.gd`, `tests/test_police_death_departure.gd`).

**Incidente durante a execução, registrado com transparência**: rodei duas
baterias de teste em segundo plano ao mesmo tempo (contrariando a própria
regra de "um Godot por vez") e isso tornou a máquina do usuário
inutilizável por alguns minutos. Um processo de teste anterior (da
reprodução do defeito, seção 3) também tinha ficado pendurado num loop de
erro sem conseguir terminar por conta própria. O usuário reportou
diretamente a lentidão; parei todas as tarefas em segundo plano
(`TaskStop`) e encerrei os processos Godot que eram meus (preservando o
editor do usuário). Depois disso, segui rigorosamente um processo por
vez, aguardando cada um terminar antes de iniciar o próximo, como
descrito nas seções seguintes.

---

## 1. `HarborSoundscape` — defeito confirmado em runtime, corrigido, validado

### 1.1 Atribuição corrigida da causa raiz

Ao investigar a fundo para montar a bateria de comparação da seção 2,
encontrei o hunk **original** da outra sessão salvo em
`tests/perf_audit_claude/results/02b_baseline_state/local_changes_others.diff`:

```diff
@@ -45,13 +45,17 @@ func _start_gameplay() -> void:
 	_restore_room_presentation()
 	var soundscape := preload("res://world/harbor/HarborSoundscape.gd").new()
 	soundscape.name = "HarborSoundscape"
-	add_child(soundscape)
-	$ArrivalStop.prepare_player($Player)
+	if not loaded_from_save:
+		$ArrivalStop.prepare_player($Player)
+	else:
+		$Player.show()
```

**Correção em relação às rodadas anteriores (R1 e à preparação desta
R2)**: eu tinha atribuído a omissão a "a linha caiu ao reescrever a
função em torno dos dois hunks" — implicando que o meu processo de
entrelaçar checkpoints teria descartado a linha. **Isso está errado.** A
própria edição não-commitada da outra sessão, salva antes de eu tocar no
arquivo, já remove `add_child(soundscape)` como parte de substituir duas
linhas por seu bloco condicional. Eu preservei esse hunk exatamente como
instruído — e, ao preservá-lo, herdei o defeito que já estava nele, sem
introduzi-lo. Confirmei isso na prática: a worktree `wt_03a_before_45ba477`
(commit `45ba477` + este mesmo diff aplicado, usada como "antes" nas
rodadas anteriores) **também** não tem `add_child(soundscape)` — só a
árvore verdadeiramente limpa (`45ba477` sem nenhum diff local) tem.

Isso não muda a correção (é a mesma linha), mas muda a atribuição: não é
um artefato do meu processo de fatiamento, é uma linha que já faltava no
diff que recebi para preservar.

### 1.2 Falha real registrada ANTES do patch

`tests/test_footstep_ambience.gd` contra `c1741ad` sem o patch
(`tests/perf_audit_claude/results/03a_r2_before_patch/test_footstep_ambience.txt`):

```
ERROR: Node not found: "HarborSoundscape" (relative to "/root/HarborGame").
SCRIPT ERROR: Attempt to call function '_update_zones' in base 'null instance' on a null instance.
```

Este processo entrou num laço de erro (`Viewport Texture must be set`
repetido indefinidamente) e não conseguiu terminar por conta própria —
consistente com o achado da R1 de que a ausência do nó deixa
`_restore_room_presentation`/apresentação num estado quebrado. Encerrei
esse processo manualmente mais tarde (seção 0).

### 1.3 Patch aplicado

`world/harbor/HarborGame.gd`, uma linha, mesma posição relativa que tinha
antes da 03A, sem tocar em nenhum outro hunk:

```diff
@@ -53,6 +53,7 @@ func _start_gameplay() -> void:
 	await batch.checkpoint(get_tree())
 	var soundscape := preload("res://world/harbor/HarborSoundscape.gd").new()
 	soundscape.name = "HarborSoundscape"
+	add_child(soundscape)
 	if not loaded_from_save:
 		$ArrivalStop.prepare_player($Player)
 	else:
```

Verificado: nenhuma segunda instância foi criada (o defeito era ausência
total, não duplicação — não havia risco de duplicar ao corrigir).

### 1.4 Testes reais depois do patch

Um processo por vez, `APPDATA` isolado por execução
(`tests/perf_audit_claude/results/03a_r2_after_patch/`):

| teste | resultado |
|---|---|
| `test_footstep_ambience` | **0 failures** (antes: crash + loop) |
| `test_footstep_movement_and_mix` | 2 falhas — **confirmado pré-existente**, seção 1.5 |
| `test_garage_audio_context` | 3 falhas — **confirmado pré-existente**, seção 1.5 |
| `test_garage_quiet_audio` | exit=0, sem falhas |
| `test_harbor_presentation_audio` | 5 falhas — **confirmado pré-existente**, seção 1.5 |
| `test_living_city_integration` | exit=0, sem falhas |
| `test_living_city_soundscape` | falha (`SCRIPT ERROR` + timeout) — **confirmado pré-existente**, seção 1.5 |
| `test_regional_soundscape` | 1 falha — **confirmado pré-existente**, seção 1.5 |
| `test_water_presentation` | exit=0, sem falhas |

### 1.5 Não confundir falha nova com pré-existente — verificação real, não suposição

Cinco dos nove testes acima passaram a rodar **muito mais longe** do que
antes do patch (antes, todos os nove crashavam no mesmo `get_node(
"HarborSoundscape")`; agora, cinco alcançam checagens de comportamento
específicas — rádio da garagem, crossfade do porto, vento da cabana,
cadência de passos). Como nenhum dos nove chegava a essas checagens
**antes** do patch, eu não podia simplesmente presumir que essas 5 falhas
já existiam — e a tarefa foi explícita em proibir isso.

Confirmei rodando os mesmos 5 testes contra uma segunda worktree,
**genuinamente limpa** (`git worktree add --detach ... 45ba477`, importada,
`add_child(soundscape)` intacto, nenhum diff de nenhuma sessão aplicado):

| teste | assinatura em `c1741ad` + patch | assinatura em `45ba477` limpo | idêntica? |
|---|---|---|---|
| `test_footstep_movement_and_mix` | `MOVEMENT walking=0 running=0 wall=0`, 2 falhas | idêntico | ✅ |
| `test_garage_audio_context` | `["Only the interior radio plays while inside", "Metal details do not use the loud bus-brake gain", "Interior decoders stop after the exit fade"]` | idêntico | ✅ |
| `test_harbor_presentation_audio` | `["Bounded audio voices and authored quarter", "Port crossfade", "Garage replaces exterior sound", "Distant water stops decoding after fade", "No per-frame audio allocations"]`, 5 falhas | idêntico | ✅ |
| `test_regional_soundscape` | `"Cabana mantém vento de neve abafado"`, 1 falha | idêntico | ✅ |
| `test_living_city_soundscape` | `SCRIPT ERROR: Invalid access to property or key 'text'` linha 116 + `Tempo limite da ambientação` | idêntico | ✅ |

**As 5 assinaturas são byte-a-byte idênticas** na árvore limpa de antes de
qualquer coisa desta rodada existir. Conclusão: **pré-existentes,
confirmadas por comparação real, não por suposição.** Nenhuma delas foi
tocada, "corrigida" ou reclassificada para esconder o resultado — ficam
registradas como pendência de outro domínio (áudio de garagem/porto/
regional/cidade viva), fora do escopo desta tarefa.

Não foi necessário criar `tests/test_harbor_soundscape_present.gd` — os
testes existentes já cobrem a asserção de existência como efeito
colateral do próprio `get_node`.

### 1.6 Validação de ciclo de vida — Novo Jogo, Continuar, retorno+reentrada

Escrevi `tests/perf_audit_claude/probe_soundscape_lifecycle_r2.gd`: usa
os mesmos handlers de botão do jogo real (`_on_btn_new_game_pressed`,
`_select_and_load_slot`, `PauseMenu._on_main_menu_pressed`) — **nunca**
instala o nó manualmente. Resultado real
(`tests/perf_audit_claude/results/03a_r2_lifecycle_probe/console.txt`):

```
PASS Novo Jogo: exatamente 1 HarborSoundscape (encontrado 1)
PASS Novo Jogo: HarborSoundscape é filho direto do mundo
PASS Novo Jogo: script correto
PASS Novo Jogo: listener (AudioListener2D) criado e válido
PASS Novo Jogo: listener é AudioListener2D
PASS Novo Jogo: listener é filho de HarborSoundscape
PASS Novo Jogo: weights inicializado
PASS Continuar: exatamente 1 HarborSoundscape (encontrado 1)
PASS Continuar: [demais checagens iguais]
PASS Retorno ao menu: HarborSoundscape antigo não continua na árvore ativa
PASS Reentrada após retorno ao menu: exatamente 1 HarborSoundscape (encontrado 1)
PASS Reentrada após retorno ao menu: [demais checagens iguais]
PROBE_R2_LIFECYCLE failures=0
```

**21 checagens, 0 falhas.** Validado estruturalmente: nó único, filho
correto, script correto, `AudioListener2D` criado e válido, `weights`
inicializado — nos três estados (Novo Jogo, Continuar, reentrada), sem
duplicação e sem referência pendente ao nó antigo após voltar ao menu.

**O que isto NÃO prova** (distinção exigida pela tarefa): que o áudio
efetivamente soa nos alto-falantes. `listener != null` e `AudioListener2D.
make_current()` terem sido chamados é estado correto dos componentes, não
escuta real. Nenhuma captura de áudio foi feita. Não afirmo que o áudio
"funciona" no sentido perceptual — afirmo que a estrutura que o produz
está correta e presente.

Ruído registrado, não investigado (fora do escopo): a mesma execução
produziu várias `SCRIPT ERROR: Invalid access to property or key 'users'
on a base object of type 'Dictionary'` e um `Cannot call method
'get_nodes_in_group' on a null value`, sem relação com `HarborSoundscape`
(o nome não aparece em nenhuma). Provavelmente um efeito da sequência
não-convencional de trocas de cena do probe (Novo Jogo → menu → Continuar
→ menu → Novo Jogo, tudo num único processo). Não impediu nenhuma das 21
checagens de passar; não investiguei a causa raiz por estar fora do
escopo desta tarefa.

**Não afirmo** que todo áudio do jogo estava ausente antes do patch, nem
que o primeiro impacto sonoro da 02A foi afetado — `CombatImpactAudio.
prepare(world)` é chamado por `GameLoading.gd` diretamente, sem depender
de `HarborSoundscape`; nenhuma evidência encontrada de acoplamento entre
os dois sistemas.

---

## 2. Risco do minimapa — testado, **não demonstrado**, patch NÃO aplicado

### 2.1 O que foi observado (sem atraso artificial)

`tests/perf_audit_claude/probe_minimap_south_port_race_r2.gd`: escuta
`SceneTree.node_added`, guarda a referência a `SouthPort`, e no instante
em que `Minimap` aparece na árvore, lê `SouthPort.sites.size()` e
`SouthPort.port_ready` — no mesmo ponto temporal em que
`HarborMinimap._ready()` os leria (justificativa de que não há hiato real
entre `node_added` e `_ready()` do mesmo `add_child()`: seção 2.2).

Duas execuções reais, mesmo fluxo (`mode=new` via `HarborGame.tscn`
direto):

```
Execução 1: south_port_sites=5 port_ready=false
Execução 2: south_port_sites=5 port_ready=false
```

### 2.2 Por que isto não é prova de proteção, mas também não é prova de defeito

`port_ready=false` no momento — exatamente a condição que a tarefa avisou
para não tratar como prova de risco por si só. O dado que
`HarborMinimap._ready()` efetivamente lê é `SouthPort.sites` (comparei
diretamente com o array-alvo, não com uma contagem aproximada): 5
entradas, que é a contagem **final** de `HarborSouthPortLayout.
WAREHOUSES`/definitions (`_build_buildings()` faz só `append()`, nunca
remove ou reescreve — uma vez que `sites.size()==5`, esses 5 elementos
JÁ SÃO os finais, por construção do código, não uma coincidência de
contagem). `sites` é preenchido bem no início de `SouthPort._ready()`
(1 checkpoint + 5 dentro de `_build_buildings`), muito antes de
`port_ready` exigir que TODO o resto (modelos 3D, vida, HUD) também
termine. Nas duas execuções reais, essa parte inicial já tinha terminado
quando `_start_gameplay()` alcançou o `Minimap` — mesmo com `port_ready`
ainda false.

**Isto não prova que o risco não existe** — é uma amostra de 2 execuções
no mesmo hardware, sem variar carga do sistema. A ordem relativa entre as
duas corrotinas (`_start_review()`, que constrói `SouthPort`, e
`_start_gameplay()`, que cria o `Minimap`) depende de custo relativo que
pode mudar sob outra carga de máquina/thread scheduling — algo que não
testei deliberadamente (a tarefa proíbe atraso artificial em produção; um
teste com atraso controlado *só do lado do teste*, proposto na preparação
anterior, não foi executado por prudência com o estado da máquina do
usuário durante esta sessão, e por já ter uma amostra real consistente
que não demonstrou o defeito).

### 2.3 Decisão

**Patch (`r2_proposed_patch_minimap.diff`) NÃO aplicado.** `ui/
HarborMinimap.gd` permanece com hash idêntico ao início desta tarefa e
das duas anteriores. Não declaro que o risco é inexistente — registro que
**não foi demonstrado** nas execuções reais feitas, e que a proteção de
fato encontrada é: `_build_buildings()` (a parte de `SouthPort` que
`Minimap` de fato lê) historicamente termina bem antes do ponto em que
`_start_gameplay()` cria o `Minimap`, mesmo que `port_ready` (que exige
muito mais trabalho) ainda esteja false.

**Teste ainda necessário, não feito aqui**: repetir a observação sob
carga artificial da máquina (não do jogo) — por exemplo, rodando o probe
enquanto outro processo pesado ocupa a CPU — para checar se a folga
observada (6 checkpoints de `SouthPort` vs. ~9 de `_start_gameplay()`) é
robusta a variação de escalonamento, ou se é uma coincidência de
hardware. Também vale confirmar em `mode=continue`, não testado aqui (só
`mode=new`).

### 2.4 Testes de menu/loading/minimap/SouthPort — após o patch da soundscape

Um processo por vez:

| teste | resultado |
|---|---|
| `test_menu_flow_integration` | **SUCESSO COMPLETO** (exit 0, 16/16 checagens) |
| `test_south_port` | `failures=0`, `steps=4686` (idêntico ao histórico) |
| `test_south_port_production` | `PASS` (exercita `Minimap` também) |
| `test_hud_layout_and_minimap_heading` | 2 falhas — **confirmado pré-existente** (idêntico contra `45ba477` limpo): `"driving heading matches the vehicle's real orientation"`, `"driving heading tracks vehicle rotation changes"` — sobre a direção do ícone do carro, não sobre contagem de prédios/`sites` |
| `test_continue_skips_opening` | `failures=7` — **mesma falha histórica, isolada, não tocada** |

---

## 3. Consequência para os números de desempenho — reafirmado, não medido de novo

**Não fiz nenhum benchmark novo nesta tarefa.** Reafirmo o que a
preparação anterior já registrou: toda execução "depois"/"after" citada
no relatório 03A e na errata R1 rodou sem `HarborSoundscape` na árvore;
toda execução "antes"/"before" rodou com o subsistema presente. Isso
permanece uma quebra de equivalência funcional entre os lados dessas
medições históricas — não invalida a direção qualitativa já registrada
(bloco máximo caiu, total/percentis pioraram nos dois lados), mas os
números exatos de "depois" foram medidos sobre uma árvore funcionalmente
incompleta.

**Nenhuma medição histórica foi apagada ou reinterpretada com um valor
inventado para o custo do componente ausente.** Qualquer comparação de
desempenho futura precisa ter `HarborSoundscape` presente nos dois lados
antes de ser comparável ao histórico da 03A/R1.

**Para a 03B**: se qualquer medição do Antigravity rodou sobre uma cópia
da árvore Harbor derivada de `c1741ad` (sem este patch), essa medição
também rodou sem `HarborSoundscape`. Não decido por eles se isso importa
para o que estão medindo (Mountain Pass, um sistema diferente) — só
registro o estado real para que a condição fique explícita em qualquer
relatório futuro que cite números gerais da árvore Harbor.

---

## 4. Commit

Staging explícito, só dos arquivos desta correção — nada de
`world/mountain_pass/`, `tests/perf_audit_antigravity/`, ou dos arquivos
de outras sessões listados na seção 0. Efeito colateral incidental
registrado, não incluído no commit: rodar `test_hud_layout_and_minimap_heading.gd`
regenerou 3 capturas de tela já versionadas
(`tests/_capture_hud_stack_1280x720.png`, `tests/_capture_hud_stack_1920x1080.png`,
`tests/_capture_minimap_pedestrian_heading.png`) — comportamento normal
do teste, não uma mudança minha; deixadas de fora do staging, sem
reverter (evitar qualquer `checkout`/`restore`).

Arquivos no commit: `world/harbor/HarborGame.gd` (o patch),
`docs/history/GETECO_PERF_03A_R2_CORRECTNESS.md` (este arquivo),
`docs/history/GETECO_PERF_03A_REVIEW_R1.md` (entregue antes, nunca
commitado), os 2 probes novos, os 2 diffs propostos (o da soundscape
agora histórico/aplicado, o do minimap ainda não aplicado), e as pastas
de resultado `tests/perf_audit_claude/results/03a_r2_*`.

---

## 5. Pendências e lacunas (não resolvidas nesta rodada)

- Risco do minimapa: **não demonstrado, não descartado** (seção 2.3) —
  teste sob carga variável ainda necessário.
- Equivalência de contagem de postes do `RoadLighting` (146→290→262,
  R1 seção 3.7) — não investigada nesta rodada.
- Bloqueio residual `WorldEvents`→`Minimap` (~3,8-5,0 s, R1 seção 6) —
  não tocado.
- 5 falhas pré-existentes de áudio (garagem, porto, regional, cidade
  viva) e 2 de heading do minimapa, todas confirmadas independentes desta
  correção — nenhuma foi investigada a fundo ou corrigida (fora de
  escopo).
- `test_continue_skips_opening`: falha pré-existente, confirmada
  novamente isolada, não tocada.
- O `Cannot infer the type`/`Function "get_tree()" not found` que
  apareceu ao escrever os dois probes (scripts `extends SceneTree` não
  têm `get_tree()`, é o próprio `self`) foi um erro meu de escrita,
  corrigido antes de qualquer execução real ser contabilizada como
  resultado — mencionado aqui só por transparência do processo, não é um
  achado sobre o jogo.

## 6. Handoff para a 03B

- `world/harbor/HarborGame.gd` mudou (mais uma linha) desde a última vez
  que qualquer relatório da 03B possa tê-lo referenciado. O contrato de
  `_start_gameplay()` (ordem, checkpoints, `gameplay_ready`) não mudou —
  só a linha que faltava foi restaurada.
- `ui/HarborMinimap.gd` **não mudou**. Se a Mountain Pass tiver ou vier a
  ter um minimapa/HUD equivalente que leia dados de um construtor fatiado
  sem esperar a flag de conclusão dele, o mesmo padrão de risco desta
  seção 2 se aplica — vale usar `probe_minimap_south_port_race_r2.gd`
  como modelo (adaptado) antes de presumir seguro.
- Toda medição de desempenho da árvore Harbor completa feita antes desta
  correção rodou sem `HarborSoundscape` — se a 03B citar números gerais
  (não específicos da Mountain Pass) derivados de uma árvore sem este
  patch, essa condição deveria ficar explícita.
