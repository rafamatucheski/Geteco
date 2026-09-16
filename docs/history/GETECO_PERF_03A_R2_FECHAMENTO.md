# GETECO-PERF-03A-R2 — Fechamento e runner seguro

Data: 2026-09-16. Autor: Claude. Fecha a MESMA 03A-R2 (não é uma nova
auditoria, não refaz a correção da soundscape, não roda a bateria de
áudio de novo). Objetivo: deixar um estado identificável para o
Antigravity validar a 03B, e um runner que não trave a máquina do usuário
de novo.

---

## 0. Confirmação da base e preservação

Nenhum conflito real encontrado: `git status` mostra arquivos
modificados/pastas recentes/um ZIP da 03B — nada disso é, por si só,
prova de edição em andamento (a própria autorização desta etapa já
adianta isso). Nenhum processo Godot de teste/benchmark ativo no início;
o único processo Godot era o launcher/project manager sem `--path`
(sem argumentos de linha de comando), não um teste em andamento.

| item | valor |
|---|---|
| Branch | `main` |
| HEAD | `a76adbf` — **é o commit da correção R2** (não é só o commit da 03A) |
| Índice (staged) | vazio até o commit desta etapa (ver seção 5) |
| `world/harbor/HarborGame.gd` | hash `c0cbc508aafc645f8b087599a69cdddf5e172469`; `add_child(soundscape)` presente na linha 56; **idêntico ao commit `a76adbf`** (`git diff HEAD` vazio) |
| `ui/HarborMinimap.gd` | hash `addefff2936af55785156f68bacb1b1694388d64` — **inalterado** desde a R1; nenhuma referência a `port_ready` no arquivo (patch condicional confirmadamente NÃO aplicado) |

**Nota sobre identidade de árvore**: o HEAD por si só (`a76adbf`) identifica
a *base de código*, mas esta árvore de trabalho tem outras alterações
locais não commitadas (Mountain Pass da 03B, arquivos de outras sessões)
que não são parte da identidade do commit — por isso a seção 4 lista um
manifesto separado das alterações locais que continuam presentes, além do
hash do commit.

**Preservado intacto, verificado antes e depois desta etapa**: os 6
arquivos de `world/mountain_pass/` da 03B, `tests/perf_audit_antigravity/`
inteiro, `docs/history/GETECO_PERF_03B_MOUNTAIN_STREAMING_2026-09-15.md`,
e as alterações locais de outras sessões já documentadas (`characters/
Player.gd`, `systems/RegionTravel.gd`, `systems/interiors/
ExteriorOcclusion.gd`, `world/harbor/HarborArrivalStop.gd`, `world/harbor/
campaign/HarborArrivalMission.gd`, `tests/test_police_death_departure.gd`).
Nenhum destes foi lido para modificação, só verificados via `git status`
para confirmar ausência.

**A correção da soundscape já estava commitada** antes desta etapa
começar (commit `a76adbf`, feito na entrega anterior). Esta etapa não
reaplicou nem re-testou essa correção — só confirmou o estado (seção 0)
e corrigiu a documentação (seção 2).

---

## 2. Reconciliação da contradição documental

### 2.1 A contradição

`GETECO_PERF_03A_R2_CORRECTNESS.md` (versão aplicada) contém duas
afirmações incompatíveis:
- Seção 1.1: a worktree "antes" (`wt_03a_before_45ba477`, = `45ba477` +
  `local_changes_others.diff`) **também não tinha** `add_child(soundscape)`.
- Seção 3: "toda execução 'antes'/'before' rodou com o subsistema
  presente."

### 2.2 Reconciliação por ID de execução

Nenhuma medição foi refeita para esta reconciliação — só releitura de
`run_info.txt`/`tree_info.txt`/`report.json` já existentes, e da própria
transcrição desta sessão (comandos que eu mesmo digitei, com o caminho da
árvore explícito nos parâmetros `$wt_before`/`$WT`).

| execução | revisão + alterações locais | evidência disponível | soundscape |
|---|---|---|---|
| `03a_before_new_2` | `45ba477` + `local_changes_others.diff` | `run_info.txt`: `tree=wt_03a_before_45ba477 head=45ba477` | **ausente** (confirmado — o diff remove `add_child`) |
| `03a_before_new_3` | idem | `run_info.txt` idem | **ausente** (confirmado) |
| `03a_fresh_baseline_new` | provavelmente idem (mesmo lote/metodologia) | `report.json` não registra `--path`; nenhum `run_info.txt` (script ainda não tinha esse campo nesta execução) | **não demonstrado por evidência direta desta execução**; mesma configuração das duas seguintes por padrão de lote, mas sem prova própria |
| `03a_continue_before_fixed`, `_2`, `_3` | `45ba477` + diff | comando explícito na transcrição desta sessão (`$wt_before = ".../wt_03a_before_45ba477"; Run-Continue $wt_before "03a_continue_before_fixed"`) | **ausente** (confirmado) |
| `03a_regressions_before` | `45ba477` + diff | `tree_info.txt`: `tree=wt_03a_before_45ba477 head=45ba477` | **ausente** (confirmado) |
| `03a_positions_before` | `45ba477` + diff | comando explícito na transcrição (`--path $WT` onde `$WT=wt_03a_before_45ba477`) | **ausente** (confirmado) |
| `03a_after_new_*`, `03a_after_fixed_new_*`, `03a_continue_after_fixed*`, `03a_regressions_after[_fixed]`, `03a_positions_after` | árvore principal, commit `c1741ad`, **antes** do patch R2 | comando `--path .` documentado nos relatórios 03A/R1 | **ausente** (confirmado — mesmo defeito, ainda não corrigido nessas execuções) |
| `03a_r2_before_patch/test_footstep_ambience` | árvore principal, `c1741ad`, antes do patch R2 | comando direto desta rodada anterior | **ausente** (confirmado — reproduziu o crash) |
| `03a_r2_baseline_45ba477/*` | `45ba477` + diff (mesma worktree `wt_03a_before_45ba477`) | comando direto | **ausente** (confirmado — foi essa checagem que revelou a contradição) |
| `03a_r2_baseline_clean_45ba477/*` | `45ba477` **puro**, sem nenhum diff local (`wt_r2_bare_45ba477`) | `grep add_child` confirmado presente no arquivo antes de rodar | **presente** (confirmado) |
| `03a_r2_after_patch/*`, `03a_r2_lifecycle_probe`, `03a_r2_minimap_probe[_2]` | árvore principal, commit `a76adbf` (com o patch R2) | comando direto, `git diff HEAD` vazio no momento | **presente** (confirmado) |

### 2.3 Conclusão corrigida

**Todas as execuções "antes"/"before" dos relatórios 03A e da errata R1
que têm evidência direta ou por comando explícito rodaram SEM
`HarborSoundscape`** — a mesma ausência do lado "depois", não uma
diferença entre os lados. A única execução sem confirmação direta
(`03a_fresh_baseline_new`) fica registrada como **não demonstrada**, não
como presumida — não estendo a conclusão das outras duas do mesmo lote
para ela sem prova própria.

**Isso não é a mesma coisa que a seção 3 original afirmava (assimetria
antes-tem/depois-não-tem).** É uma configuração incompleta **nos dois
lados**, nas execuções históricas da 03A/R1. Como consequência: a
comparação relativa entre "antes" e "depois" dessas execuções históricas
**não fica mais distorcida por essa diferença específica** (já que ambos
os lados a compartilham) — mas nenhum dos dois lados representa a
configuração completa de produção (a que existe a partir do commit
`a76adbf`). Não meço quanto isso custaria nem repito nenhuma medição para
descobrir — os números históricos ficam como estão, com esta ressalva
correta no lugar da anterior.

**Isto se aplica só às execuções listadas na tabela.** Não estendo a
conclusão a nenhuma execução da 03B/Mountain Pass — não teria como, são
sistemas diferentes, e não investiguei o estado de nenhuma medição do
Antigravity.

### 2.4 Reclassificação dos erros `users`/`get_nodes_in_group`

O documento anterior classificava esses erros como "sem relação com
`HarborSoundscape`, causa não investigada." Reli o log completo do probe
de ciclo de vida com mais atenção: o erro tem pilha de chamada completa,
não só a linha final:

```
SCRIPT ERROR: Invalid access to property or key 'users' on a base object of type 'Dictionary'.
   at: set_lit (res://geodata/roads/RoadLuminaire3D.gd:106)
   ... start_or_resume (res://world/harbor/campaign/HarborArrivalMission.gd:143)
   ... _run (res://ui/GameLoading.gd:186)
   ... _draw_frame (res://ui/GameLoading.gd:110)
```

`RoadLuminaire3D.gd:106` faz `_models[key].users += 1` sobre um cache de
modelos (`_models`, provavelmente estático/compartilhado entre
instâncias). **Evidência concreta agora disponível**: a chamada vem de
`GameLoading`/`start_or_resume`, no MEIO do fluxo real de carregamento —
não de nada relacionado a áudio. O padrão mais provável (não confirmado
por execução adicional, pois isso reabriria uma investigação fora de
escopo): meu probe de ciclo de vida recarrega a cena Harbor **três vezes**
no mesmo processo (Novo Jogo → menu → Continuar → menu → Novo Jogo),
algo que nenhum teste existente faz duas vezes seguidas; um cache estático
como `_models` pode ficar com uma entrada apontando para um recurso já
liberado pela cena anterior, entre uma recarga e outra.

**Reclassificação**: causa **atribuída ao padrão de recarga repetida do
meu probe** (não ao jogo em condição normal — `test_menu_flow_integration.gd`,
que recarrega uma vez, passou 100% limpo), **não a `HarborSoundscape`**
(o nome não aparece na pilha, e agora tenho a pilha completa, não só a
ausência do nome, como evidência) e **não ao meu patch** (não toquei
`RoadLuminaire3D.gd` nem `HarborArrivalMission.gd`). Não investigado a
fundo — fora do escopo desta correção — e não afetou nenhuma das 21
checagens de estrutura da soundscape, que passaram limpas antes, durante
e depois dessas mensagens.

---

## 3. Runner seguro — `Invoke-GodotTestLocked.ps1`

### 3.1 Caminho e comando exato

```
tests/perf_audit_claude/Invoke-GodotTestLocked.ps1
```

Uso real (dentro de `run_03a_regressions.ps1`, que passou a chamá-lo por
teste em vez de `& $godot` direto):

```powershell
./tests/perf_audit_claude/Invoke-GodotTestLocked.ps1 `
  -ScriptPath "res://tests/test_south_port.gd" -Path "D:/geteco/game" `
  -Run "test_south_port" -OutDir "<pasta_de_resultado>" -TimeoutSec 150
```

### 3.2 Mecanismo

- **Exclusão mútua atômica entre processos**: `System.Threading.Mutex`
  nomeado `Global\GETECO_GODOT_TEST_LOCK` — o prefixo `Global\` faz o
  nome ser o MESMO identificador para qualquer cópia do projeto (worktree
  A, worktree B, árvore principal), porque é um namespace do sistema, não
  amarrado a caminho de arquivo. Se o processo dono cair sem liberar, o
  Windows libera o mutex automaticamente (`AbandonedMutexException`,
  tratada no código) — não precisa de limpeza manual de um arquivo de
  lock órfão.
- **Timeout externo ao motor**: o processo é iniciado via
  `System.Diagnostics.Process` (não o cmdlet `Start-Process` — nesta
  máquina, `Start-Process -PassThru` não expõe `ExitCode` de forma
  confiável mesmo depois do processo terminar; verificado na seção 3.3) e
  monitorado com `WaitForExit($TimeoutSec*1000)`. Se expirar, finaliza só
  o PID que ESTE script iniciou e os processos filhos DIRETOS dele
  (`Get-CimInstance Win32_Process -Filter "ParentProcessId=..."`) — nunca
  por nome de processo.
- **Registro**: cada execução grava uma linha JSON em
  `<OutDir>/runner_log.jsonl` com `pid`, `command`, `created_at`,
  `started_at`, `ended_at`, `wall_s`, `exit_code`, `timed_out`,
  `lock_wait_s`.
- **Serialização**: o lock é adquirido ANTES de iniciar o processo e
  liberado só depois de finalizar/matar e coletar o resultado — chamar o
  script em sequência (como `run_03a_regressions.ps1` já fazia) nunca
  deixa dois testes rodando ao mesmo tempo, mesmo que outra sessão/cópia
  tente iniciar um teste no meio.
- **Isolamento de dados**: `APPDATA` isolado por execução em
  `<OutDir>/<Run>_appdata` (mesmo padrão de `measure_loading_03a.gd`),
  nunca os saves/configurações reais do usuário.
- **Log deduplicado**: linhas consecutivas idênticas são colapsadas em
  "linha (repetida xN)" — preserva a primeira ocorrência de cada
  assinatura e, se houver timeout, uma linha final explicando o motivo da
  interrupção.

### 3.3 Verificação feita (comandos leves, sem Godot, sem GPU)

Todos os 4 casos abaixo usaram `cmd.exe`/`powershell.exe` como substituto
de `$Godot` (parâmetro `-RawArgList`, feito exatamente para isso) — **não
carregaram o jogo, não tocaram GPU**. Resultados reais, arquivo por
arquivo em `tests/perf_audit_claude/results/03a_r2_runner_verification/`:

| caso | comando substituto | resultado |
|---|---|---|
| Término normal | `cmd.exe /c echo ola-do-teste && exit 0` | `exit_code=0`, `timed_out=false`, saída capturada corretamente (`ola-do-teste`) |
| Falha | `cmd.exe /c exit 3` | `exit_code=3`, `timed_out=false` |
| Timeout | `powershell.exe -Command "Start-Sleep -Seconds 60"` com `-TimeoutSec 3` | `timed_out=true`, `wall_s≈3.04`, processo confirmado **não existir mais** 1s depois (verificado com `Get-Process`) |
| Rejeição de segundo lançamento | processo separado real (`_holder_temp.ps1`) adquire o mesmo Mutex nomeado e segura por 8s; chamada com `-NoWait` no meio disso | `rejected=true`, `reason="lock ocupado por outro processo Godot de teste"`; uma chamada igual **depois** do holder liberar retorna `rejected=false` normalmente |

**O que isto NÃO comprova**: que o jogo em si funciona, que qualquer teste
específico passa, ou qualquer coisa sobre desempenho. Só que o mecanismo
de exclusão mútua, timeout externo e captura de PID/exit-code funciona
como projetado, sob comandos triviais e controlados. Nenhum benchmark, e
nenhuma bateria de teste do jogo foi executada para produzir esta seção.

### 3.4 Correção incidental encontrada ao verificar

`Start-Process -PassThru` nesta máquina não repopula `.ExitCode` de forma
confiável mesmo com `.Refresh()` chamado depois de `WaitForExit`
retornar — descoberto ao testar o caso "término normal" (retornava
`exit_code=null` mesmo para `exit 0`/`exit 3`). Troquei para
`System.Diagnostics.Process` direto (`.Start()`), que expôs o código de
saída correto nos mesmos casos. Registrado aqui porque é exatamente o
tipo de falha que teria produzido um `exit_code` errado silenciosamente
em qualquer bateria real rodada com a versão anterior do script — bom
que apareceu na verificação com comandos leves, antes de qualquer uso
real.

---

## 4. Estado final e inventário para a 03B

### 4.1 Hashes dos arquivos relevantes

```
world/harbor/HarborGame.gd    c0cbc508aafc645f8b087599a69cdddf5e172469  (add_child presente)
ui/HarborMinimap.gd           addefff2936af55785156f68bacb1b1694388d64  (inalterado, sem port_ready)
world/harbor/HarborSouthPort.gd  fcbee9c2bff84dbb15c11e85848fa8a541d3a26e  (inalterado desde a 03A/R1)
world/harbor/HarborPreview.gd    28b28fab33af985f1e6709e8fc31f26f96d59b90  (inalterado desde a 03A/R1)
geodata/roads/RoadLighting.gd    8baf83d051fba241e9354079f469c7b510bbfe7f  (inalterado desde a 03A/R1)
```

### 4.2 Inventário de diffs locais presentes nesta árvore (não commitados)

Necessário para a 03B saber o que está em cima da base `a76adbf` além do
que já foi commitado — lacunas históricas não impedem esta identificação,
que é sobre o estado ATUAL, não sobre o passado:

| arquivo | domínio | commitado nesta etapa? |
|---|---|---|
| `world/mountain_pass/MountainExpedition.gd` | Mountain Pass (03B) | **não** — preservado, fora do escopo desta correção |
| `world/mountain_pass/MountainMysteryDirector.gd` | Mountain Pass (03B) | não |
| `world/mountain_pass/MountainPass.gd` | Mountain Pass (03B) | não |
| `world/mountain_pass/MountainPassRoad.gd` | Mountain Pass (03B) | não |
| `world/mountain_pass/MountainSceneryBuilder.gd` | Mountain Pass (03B) | não |
| `world/mountain_pass/MountainSkiArea.gd` | Mountain Pass (03B) | não |
| `characters/Player.gd` | outra sessão | não |
| `systems/RegionTravel.gd` | outra sessão | não |
| `systems/interiors/ExteriorOcclusion.gd` | outra sessão | não |
| `world/harbor/HarborArrivalStop.gd` | outra sessão | não |
| `world/harbor/campaign/HarborArrivalMission.gd` | outra sessão | não |
| `docs/measurements/review-0909/load_profile.txt` | outra sessão | não |
| `tests/find_building.gd`, `tests/test_death_explosion_visibility.gd` (apagados) | outra sessão | não |
| `tests/_capture_hud_stack_*.png`, `tests/_capture_minimap_pedestrian_heading.png` | efeito colateral de eu ter rodado `test_hud_layout_and_minimap_heading.gd` na etapa anterior | não — não é uma mudança minha intencional |
| `tests/claude_gameplay_audit/captures/09_crossed_into_mountain.png` | não identificado (não investiguei; provavelmente 03B) | não |
| `tests/test_police_death_departure.gd`(`.uid`) | outra sessão | não |

Meus arquivos desta etapa (commitados agora, seção 5):
`tests/perf_audit_claude/Invoke-GodotTestLocked.ps1`,
`tests/perf_audit_claude/run_03a_regressions.ps1` (modificado),
este arquivo (a errata da contradição vive AQUI, não em
`GETECO_PERF_03A_R2_CORRECTNESS.md` — esse relatório é preservado como
foi entregue, sem edição, seção 2), e os
resultados de verificação da seção 3.3.

### 4.3 Encerramento de processos de teste

Confirmado ao final desta etapa: nenhum processo Godot de teste/benchmark
meu ficou rodando. O único processo Godot ativo é o launcher/editor do
usuário (sem argumentos de `--path`/`--script`), não tocado.

---

## 5. Commit

Staging explícito, só dos meus arquivos desta etapa — nada de
`world/mountain_pass/`, `tests/perf_audit_antigravity/`, capturas de
tela, ou qualquer arquivo já listado na seção 4.2 como preservado.

---

## 6. Pendências (sem transformar em aprovação nem em bloqueio genérico)

- Risco do minimapa: continua **não demonstrado, não descartado** (R2
  seção 2.3) — teste sob carga variável ainda não feito.
- Equivalência de contagem de postes do `RoadLighting` (146→290→262,
  R1 seção 3.7) — não investigada.
- Bloqueio residual `WorldEvents`→`Minimap` (R1 seção 6) — não tocado.
- Falhas de áudio/heading pré-existentes (7 no total, catalogadas na R2)
  — não investigadas nem corrigidas, fora de escopo.
- `03a_fresh_baseline_new`: configuração real não confirmada por evidência
  direta (seção 2.2) — se algum dia for preciso reafirmar os números da
  seção 4 do relatório 03A com precisão total, esta execução específica
  precisaria de uma nota à parte.
- Causa exata do erro `RoadLuminaire3D.gd:106` sob recarga repetida:
  atribuída ao padrão do meu probe (seção 2.4), não confirmada por
  isolamento dedicado — não é um bloqueador, é uma pista registrada.
- Nenhum benchmark novo foi rodado nesta etapa nem na anterior desde a
  correção da soundscape — os números de desempenho da 03A/R1 continuam
  como estavam, com a ressalva corrigida da seção 2.3.

---

## HANDOFF PARA ANTIGRAVITY

- **Base atual**: commit `a76adbf` em `main` (03A + correção da
  soundscape da R2). A 03B parte desta base — se a 03B foi desenvolvida
  sobre `c1741ad` (antes da correção), ela não teve `HarborSoundscape`
  disponível durante o desenvolvimento; nada na 03B deveria depender
  disso, mas vale confirmar se algum teste da 03B toca `HarborGame.tscn`
  diretamente.
- **Diffs que devem existir nos dois lados de qualquer futura comparação
  A/B envolvendo a árvore Harbor completa**: `add_child(soundscape)` em
  `world/harbor/HarborGame.gd` (já em `a76adbf`) — sem ele, ~9 testes de
  áudio quebram e qualquer medição de desempenho da árvore Harbor fica
  numa configuração incompleta (seção 2.3 desta entrega).
- **Comando do runner seguro**, para qualquer bateria futura que precise
  rodar testes Godot sem risco de travar a máquina ou concorrer com outro
  processo: `tests/perf_audit_claude/Invoke-GodotTestLocked.ps1`
  (parâmetros: `-ScriptPath`, `-Path`, `-Run`, `-OutDir`, `-TimeoutSec`;
  usa um Mutex nomeado `Global\GETECO_GODOT_TEST_LOCK` — **mesmo nome
  para qualquer cópia do projeto**, incluindo uma eventual worktree da
  03B). Se a 03B rodar testes Godot na mesma máquina/sessão ao mesmo
  tempo que outra bateria, usar este runner (ou adotar o mesmo nome de
  Mutex no próprio mecanismo) evita a repetição do incidente desta rodada.
- **Confirmação**: nenhum processo de teste Godot meu ficou rodando ao
  final desta entrega (seção 4.3). `ui/HarborMinimap.gd` não foi tocado —
  risco registrado, não corrigido, não descartado.

**PAREI APÓS ESTA ENTREGA.** Nenhuma mudança de produção, benchmark novo
ou auditoria geral foi feita além do que está descrito acima.
