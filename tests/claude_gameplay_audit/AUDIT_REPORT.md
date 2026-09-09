# Auditoria executável de gameplay — GETECO (Harbor Preview)

Data: 2026-09-08 (auditoria inicial + duas rodadas de aprofundamento na mesma sessão)
Escopo desta rodada: `tests/claude_gameplay_audit/` (11 testes + harness),
mais três arquivos compartilhados especificamente autorizados por esta
tarefa: `world/mountain_pass/MountainGunShopFacade.gd` (correção local do
sensor da porta) e `tests/test_harbor_mountain_drive.gd` (contrato de região
atualizado). Nenhum outro arquivo fora desse escopo foi alterado.
Mundo auditado: `res://world/harbor/HarborGame.tscn` (entrada real
de "Novo Jogo"; `Main.tscn` é legado, usado só por saves antigos)
Motor: Godot 4.7.2 (`Godot_v4.7.2-stable_win64_console.exe`)

Todos os 11 testes usam cenas e controladores reais de produção (nenhum
mock), com entradas simuladas via `Input.action_press`/`InputEventKey` reais
e circulação por caminhada real (`walk_to`, sem teleporte de contorno onde a
tarefa pediu explicitamente), e save/load isolado em diretório temporário
(nunca `user://saves/slot_01..05` nem `autosave` do jogador).

## ⚠️ Nota de transparência: edições concorrentes de terceiros

Este projeto tem outras sessões trabalhando em paralelo no mesmo repositório
(peer sessions). Ao longo desta auditoria (auditoria original + duas rodadas
de aprofundamento), dois arquivos compartilhados relevantes para o tema
"Ammu-Nation" foram alterados **por outra sessão, não por mim**:
- `world/harbor/interiors/HarborAmmunationInterior.gd` foi
  totalmente reescrito (nova UI com catálogo/preview 3D giratório, sem
  Area2D de balcão nem NPC de diálogo separado — ver achado nº 4 revisado).
- Uma entrada real de Ammu-Nation apareceu no Porto, em
  `District/NorthFrontage2/AmmunationEntrance`, **entre a auditoria original
  e a primeira rodada de aprofundamento** — não existia na auditoria
  original, e passou a existir e a funcionar sem qualquer ação minha.
Essas mudanças de terceiros foram **preservadas integralmente**; nada deste
arquivo foi revertido ou sobrescrito. Como o repositório está em edição
ativa por terceiros, **revalide reexecutando a suíte antes de tomar
decisões**, especialmente qualquer coisa relacionada a "Ammu-Nation"/lojas.

## Mudanças aplicadas nesta rodada (resumo)

1. **`world/mountain_pass/MountainGunShopFacade.gd`** — correção local de
   1 linha: `entrance.get_node("InteractionArea").collision_mask = 4` logo
   após instanciar a porta da loja da montanha, em `install_entrance()`.
   Nenhuma outra porta, nem a cena padrão `BuildingEntrance.tscn`, nem
   `HarborEntrance.gd`, foram tocados — a correção é local a esta única porta
   (pedestre, `EntranceKind.SHOP`).
2. **`tests/claude_gameplay_audit/test_audit_10_mountain_ammunation_full_path.gd`**
   — reescrito para remover o teleporte direto por
   `MountainInteriorManager._on_entrance_requested()` (o contorno da rodada
   anterior). Agora o jogador caminha de verdade (`walk_to`, entrada real,
   sem obstáculo) até o sensor da porta; se a detecção falhar, o teste
   registra o achado e **para ali, sem continuar por bypass** — a única
   forma de a suíte chegar às etapas seguintes agora é a porta real
   funcionar de verdade. Roda hoje: **APROVADO, 29/29**, porque a correção
   acima resolveu o defeito.
3. **`tests/test_harbor_mountain_drive.gd`** (arquivo original do
   repositório, autorizado nesta tarefa) — atualizado para checar
   `ContinuousWorld.current_region`/`ready_for_crossing` em vez de
   `current_scene.scene_file_path` (que nunca mais muda desde o streaming
   contínuo). A condução física real, as colisões reais contra a ponte, a
   identidade do veículo (`RegionTravel.controlled_car()`) e a travessia nos
   dois sentidos foram **preservadas sem nenhuma alteração de lógica** — só
   as duas condições de sucesso e os prazos de espera mudaram, agora com
   `_wait_until()` (prazo máximo explícito + mensagem de timeout específica,
   em vez de checar uma vez após um número fixo de quadros). Roda hoje:
   **APROVADO** (headless e Vulkan).
4. **`tests/claude_gameplay_audit/test_audit_11_harbor_ammunation_revalidation.gd`**
   (novo) — revalida o estado atual da porta do Porto
   (`District/NorthFrontage2/AmmunationEntrance`), com entrada e saída reais
   por circulação, e compra real pelo catálogo do armeiro (adaptado à nova
   UI reescrita pela sessão concorrente — ver nota de transparência). Não
   criou nenhuma loja nova. Roda hoje: **APROVADO, 14/14**.
5. `AuditCommon.gd` (harness) ganhou dois helpers reaproveitados pelos itens
   acima: `walk_to()` (circulação real por input, não teleporte) e
   `wait_until()` (espera por condição com prazo máximo e mensagem de
   timeout — o mesmo padrão replicado manualmente dentro de
   `tests/test_harbor_mountain_drive.gd`, que não pode depender deste
   harness por estar fora de `tests/claude_gameplay_audit/`).

`world/harbor/HarborDistrict.gd` (onde vive a integração com
`HarborStorageArt.gd`) **não foi tocado**; a integração permanece exatamente
como estava.

## Como executar a suíte

```powershell
powershell -ExecutionPolicy Bypass -File tests\claude_gameplay_audit\run_all.ps1
```

Testes individuais mais relevantes desta rodada:

```powershell
& "D:\Downloads Chrome\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path . --script res://tests/claude_gameplay_audit/test_audit_10_mountain_ammunation_full_path.gd
& "D:\Downloads Chrome\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path . --script res://tests/claude_gameplay_audit/test_audit_11_harbor_ammunation_revalidation.gd
& "D:\Downloads Chrome\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path . --script res://tests/test_harbor_mountain_drive.gd
```

(sem `--headless`: roda com renderização real/Vulkan, necessário para
capturas de tela — usado nesta rodada para todas as evidências visuais).

Convenção de saída: **exit 0 = APROVADO**, **exit 1 = FALHOU**, **exit 2 ou
outro = NÃO EXECUTADO** (watchdog/crash/erro de parse).

## Resultado consolidado (última execução, headless)

| # | Teste | Fluxo auditado | Resultado |
|---|-------|-----------------|-----------|
| 01 | test_audit_01_arrival_and_control_release.gd | Chegada inicial e liberação do controle | **APROVADO** (14/14) |
| 02 | test_audit_02_vehicle_boarding.gd | Entrada e saída de veículos | **APROVADO** (28/28) |
| 03 | test_audit_03_workshop_entry_exit_and_bench.gd | Entrada/saída da oficina (Northgate Auto) + bancada | **APROVADO** (28/28) |
| 04 | test_audit_04_maciota_and_chalkboard.gd | Conversa com Maciota + lousa + contrato "primeiro giro" | **APROVADO** (31/31) |
| 05 | test_audit_05_mission_start_fail_complete.gd | Início, falha e conclusão de missão (cobra_contact) | **APROVADO** (15/15) |
| 06 | test_audit_06_weapons_purchase_and_selection.gd | Compra e seleção de armas | **APROVADO** (21/21) |
| 07 | test_audit_07_death_and_recovery.gd | Morte e recuperação | **APROVADO** (22/22) |
| 08 | test_audit_08_save_load_midmission.gd | Save/load com missão em andamento | **APROVADO** (17/17) |
| 09 | test_audit_09_port_mountain_transition.gd | Transição porto ↔ montanha | **APROVADO** (14/14) |
| 10 | test_audit_10_mountain_ammunation_full_path.gd | Percurso completo até a Ammu-Nation da montanha, **sem bypass** | **APROVADO** (29/29) |
| 11 | test_audit_11_harbor_ammunation_revalidation.gd | Revalidação da Ammu-Nation do Porto (nova) | **APROVADO** (14/14) |

Mais, fora da suíte numerada, com o contrato de região corrigido:
`tests/test_harbor_mountain_drive.gd` → **APROVADO** (headless e Vulkan).

**11/11 aprovados, 0 falharam, 0 não executados.** Logs em
`tests/claude_gameplay_audit/logs/*.log` (escritos pelo harness) e
`logs/*.stdout.log` (saída da última corrida via `run_all.ps1`). Capturas
reais (Vulkan, RTX 4060 Laptop GPU) em `captures/*.png`.

---

## Achados, por gravidade

### 1. [CORRIGIDO NESTA RODADA] Porta física da Ammu-Nation da montanha não detectava o jogador a pé

**Como era (achados da rodada anterior):** o `$InteractionArea` desta porta
usava o `collision_mask` padrão da cena `BuildingEntrance.tscn` (`3` = camadas
1+2), que nunca incluía a camada do jogador (`4`). `3 & 4 == 0` — nenhuma
sobreposição física era possível, em nenhuma distância. As portas do Porto
funcionavam porque `HarborEntrance.gd` corrige isso; a montanha instanciava a
porta sem essa correção.

**Correção aplicada** (`world/mountain_pass/MountainGunShopFacade.gd`,
função `install_entrance()`):
```gdscript
entrance.get_node("InteractionArea").collision_mask = 4
```
Correção **local a esta porta** — não mexe no padrão de
`BuildingEntrance.tscn` nem em `HarborEntrance.gd`, então nenhuma outra porta
do jogo (garagem, oficina, delegacia, clínica, chalés da montanha) é afetada.
Chalés da montanha usam o mesmo padrão de construção sem correção
(`MountainSceneryBuilder.gd`, ~linha 788) e provavelmente têm o mesmo
problema — **não corrigido nesta tarefa**, fora do pedido específico (só a
fachada da loja foi autorizada).

**Verificação sem bypass:** `test_audit_10` foi reescrito para não usar mais
nenhum teleporte de contorno — o jogador caminha de verdade
(`walk_to`) até o sensor da porta; se a detecção falhar, o teste registra o
achado e para ali mesmo, sem prosseguir. Rodando de novo após a correção:
**29/29 aprovado**, incluindo entrada real pela porta, conversa com o
armeiro Vance, compra e reposição de munição pelo balcão, seleção por tecla
e saída real pela porta de trás. Capturas reais em
`captures/10_real_entry_door_approach.png` (jogador parado na porta com o
prompt "[E] ENTRAR") e `captures/10_real_exit_outside_shop.png` (jogador de
volta do lado de fora, com a arma comprada equipada).

---

### 2. [REVISADO — situação atual] Distribuição de lojas de armas: Porto e Montanha

O jogo tem **duas** Ammu-Nations reais, e **ambas funcionam agora**:
- **Montanha** ("Timber Ridge Guns & Ammo"): inacessível na rodada anterior
  (achado nº 1 acima); corrigida nesta rodada. Verificada de ponta a ponta
  sem bypass (`test_audit_10`, 29/29).
- **Porto** (`District/NorthFrontage2/AmmunationEntrance`): não existia na
  auditoria original; apareceu por uma edição concorrente de terceiros antes
  desta rodada. Revalidada explicitamente agora, com entrada/saída reais por
  circulação e compra real pelo catálogo (`test_audit_11`, 14/14) — a porta
  em si já tinha `collision_mask=4` correto (não precisou de correção), mas
  a aproximação pelo lado sul do prédio é bloqueada por uma parede física
  (a calçada real fica ao norte — apenas uma questão de direção de
  circulação para este prédio específico, não um defeito).

**Conclusão atual:** não há mais loja de armas inacessível conhecida em
nenhuma das duas regiões. Ambas foram verificadas com circulação real,
sem teleporte de contorno, com capturas de entrada e saída.

---

### 3. [MÉDIA] Preparação da região da montanha é muito lenta neste ambiente headless (sem GPU real)

Sem mudanças desde a rodada anterior — mantido para referência. Isolei com
uma sonda dedicada que `ContinuousWorld.ensure_mountain()` (interiores +
`MountainExpedition` + `MountainSettlement` + `MountainTraffic`, orçados por
quadro) levou **~74 segundos reais** para concluir numa execução limpa
headless neste ambiente (sem GPU). `test_audit_09`, `test_audit_10` e agora
`tests/test_harbor_mountain_drive.gd` esperam até 150s por essa preparação
via espera por condição (`wait_until`/`_wait_until`) em vez de um número fixo
de quadros, evitando falso-negativo por timeout curto. Isso não deve ser
lido como o tempo real em hardware de jogador (as capturas oficiais da
equipe foram feitas com Vulkan real numa RTX 4060), mas sugere que um
indicador discreto de carregamento seria uma boa adição de UX para
hardware mais fraco, já que a transição não tem tela de carregamento por
design.

**Arquivo:** `world/harbor/ContinuousWorld.gd::ensure_mountain()`
e `world/mountain_pass/MountainPass.gd::_setup_environment()`.

---

### 4. [MÉDIA] Mensagens da loja de armas com texto corrompido (UTF-8 duplamente codificado)

Sem mudanças desde a rodada anterior — a causa raiz está em `Player.gd`, não
nas interfaces de loja que mudaram. Mensagens confirmadas:
`"VOCÃƒÅ  JÃƒÂ POSSUI ESTA ARMA"`, `"COLETE JÃƒÂ ESTÃƒÂ NO MÃƒÂXIMO"`, e no
código-fonte (não exercitadas diretamente) `"ARMA INDISPONÃƒÂVEL"` e
`"ARMA NÃƒÆ’O ENCONTRADA"`. Como a nova UI do Porto (reescrita por terceiros)
e a da montanha chamam a mesma `Player.buy_weapon()`, o problema aparece em
ambas as lojas.

**Proposta de correção (não aplicada — fora do escopo autorizado desta
tarefa, que não incluiu `Player.gd`):** reescrever as 4 strings literais em
`Player.gd` (`buy_weapon()`, `buy_ammo_for_weapon()`, `buy_armor_amount()`)
com a codificação UTF-8 correta.

---

### 5. [RESOLVIDO NESTA RODADA] `tests/test_harbor_mountain_drive.gd` estava desatualizado

Corrigido diretamente no arquivo original (autorizado por esta tarefa). A
condução física real, as colisões contra a geometria da ponte, a
preservação da identidade do veículo (`RegionTravel.controlled_car()`) e a
travessia nos dois sentidos foram **preservadas sem alteração de lógica**.
Apenas as duas condições de sucesso mudaram, de `current_scene.scene_file_path`
(nunca mais muda, pós-streaming contínuo) para
`ContinuousWorld.current_region`, com espera por condição
(`_wait_until(condition, timeout_seconds, timeout_message)`) em vez de um
número fixo de quadros — cada timeout agora produz uma mensagem específica
(qual sensor, qual direção, valor atual de `current_region`) em vez de uma
falha genérica.

```
> godot --headless --script res://tests/test_harbor_mountain_drive.gd
HARBOR MOUNTAIN DRIVE: []
(exit code 0)

> godot --script res://tests/test_harbor_mountain_drive.gd   (Vulkan real)
HARBOR MOUNTAIN DRIVE: []
(exit code 0)
```

O arquivo de proposta da rodada anterior
(`tests/claude_gameplay_audit/proposed_fix_test_harbor_mountain_drive.gd`)
foi mantido no diretório da auditoria como registro histórico da proposta
original, mas a correção real já está aplicada no arquivo de produção.

---

### 6. [BAIXA / higiene de código] Inconsistência entre classes de veículo na checagem de "veículo destruído" ao embarcar

Sem mudanças desde a rodada anterior. `PlayerCar.gd::enter_vehicle()` recusa
embarque quando `health <= 0`; `city_demo/scripts/TrafficVehicle.gd::enter_vehicle()`
só olha para `is_broken`. Não alcançável em jogo normal (os dois campos
ficam sempre sincronizados pelo caminho real, `take_damage()`). Reportado
por completude, não como bug jogável confirmado.

---

## Comportamentos verificados como corretos (não são bugs, mas valiam a checagem)

- **Respawn no hospital não usa mais a coordenada antiga de fallback** (`test_audit_07`).
- **Morte não desconta dinheiro do jogador** — comportamento atual confirmado, documentado como observação.
- **Salvar/carregar com uma missão da campanha Cobra em andamento não perde progresso silenciosamente** (`test_audit_08`) — retry seguro, intencional.
- **Entrada/saída de veículo real, repetida e com interrupção**, não deixa o pedestre travado (`test_audit_02`).
- **Diálogo cíclico do armeiro Vance não trava** ao dar a volta completa nas falas (`test_audit_10`).
- **A travessia porto↔montanha preserva o carro pessoal ocupado (dano, posição) em ambas as direções, duas vezes seguidas**, sem trocar de cena (`test_audit_09`).
- **A porta da Ammu-Nation do Porto tem o collision_mask correto por padrão** (`test_audit_11`) — só a direção de aproximação (norte, não sul) importava.

---

## Evidências visuais (renderização real, Vulkan, RTX 4060 Laptop GPU)

| Captura | Teste | O que mostra |
|---|---|---|
| `captures/01_meet_maciota_reached.png` | test_audit_01 | HUD completo, objetivo "Encontre Maciota", minimapa, toast de conquista |
| `captures/03_northgate_bench_report_open.png` | test_audit_03 | Bancada de preparação da oficina Northgate Auto com relatório aberto |
| `captures/04_maciota_conversation_open.png` | test_audit_04 | Diálogo real com Jäger "Maciota" dentro da garagem Westgate |
| `captures/04_mission_board_open.png` | test_audit_04 | Quadro de serviços do Maciota, com o contrato "Primeiro giro" |
| `captures/09_crossed_into_mountain.png` | test_audit_09 | Carro pessoal atravessando a ponte real para "Serra da Nevasca" |
| `captures/10_real_entry_door_approach.png` | test_audit_10 | **Entrada real** — jogador na porta da Ammu-Nation da montanha, prompt "[E] ENTRAR" visível (porta corrigida) |
| `captures/10_real_entry_inside_shop.png` | test_audit_10 | Interior 3D logo após a entrada real pela porta |
| `captures/10_vance_conversation_open.png` | test_audit_10 | Diálogo real com o armeiro Vance |
| `captures/10_purchase_catalog_open.png` | test_audit_10 | Catálogo de compra real no balcão da montanha |
| `captures/10_real_exit_outside_shop.png` | test_audit_10 | **Saída real** — jogador de volta do lado de fora, arma comprada equipada, conquista "Arsenal Pessoal" |
| `captures/11_harbor_ammunation_real_entry.png` | test_audit_11 | **Entrada real** — jogador na porta da Ammu-Nation do Porto |
| `captures/11_harbor_ammunation_catalog_open.png` | test_audit_11 | Catálogo real do Porto (preview 3D giratório da arma) |
| `captures/11_harbor_ammunation_real_exit.png` | test_audit_11 | **Saída real** — jogador de volta na rua do Porto, arma equipada |

---

## Cobertura por fluxo solicitado

| Fluxo pedido | Teste(s) | Cenas/controladores reais usados |
|---|---|---|
| Chegada inicial e liberação do controle | `test_audit_01` | `HarborArrivalMission.gd` via `HarborGame.tscn` |
| Entrada e saída de veículos | `test_audit_02` | `PlayerCar.gd`, `VehicleBoarding.gd`, `ModernTrafficFactory` |
| Entrada e saída da oficina | `test_audit_03` | `HarborWorkshopInterior.gd`, `BuildingEntrance.gd`, `HarborInteriorManager.gd` |
| Conversa com Maciota | `test_audit_04` | `JagerNPC.gd` (Maciota), `HarborGarageInterior.gd` |
| Interação com lousa e bancada | `test_audit_03` + `test_audit_04` | `CarChalkboard.gd`, bancada de `HarborWorkshopInterior.gd` |
| Início, falha e conclusão de missão | `test_audit_05` (+ `test_audit_04`) | `CobraCampaignController.gd`, `CobraCampaignState.gd`, `HarborArrivalMission.gd` |
| Compra e seleção de armas | `test_audit_06`, `test_audit_10`, `test_audit_11` | `Player.gd`, `HarborAmmunationInterior.gd`, `MountainGunShopInterior.gd` |
| Morte e recuperação | `test_audit_07` | `Player.gd` |
| Save/load | `test_audit_08` | `SaveManager.gd`, `CampaignState.gd` |
| Transição porto ↔ montanha (com renderização e captura) | `test_audit_09`, `tests/test_harbor_mountain_drive.gd` | `ContinuousWorld.gd` |
| Percurso completo até a Ammu-Nation da montanha, sem bypass | `test_audit_10` | `MountainGunShopFacade.gd`, `MountainInteriorManager.gd`, `MountainGunShopInterior.gd` |
| Revalidação da Ammu-Nation do Porto | `test_audit_11` | `HarborAmmunationInterior.gd`, `HarborInteriorManager.gd` |

Todos os testes incluem repetição (ciclos de 2-3x) e pelo menos um cenário de
falha/recuperação.

## Arquivos desta entrega

**Dentro de `tests/claude_gameplay_audit/`:**
- `AuditCommon.gd` — harness compartilhado (+ `walk_to()`, `wait_until()` novos nesta rodada).
- `run_all.ps1` — comando único da suíte, descobre `test_audit_*.gd` automaticamente.
- `test_audit_01` a `test_audit_11` — os 11 testes numerados.
- `proposed_fix_test_harbor_mountain_drive.gd` — registro histórico da proposta (já aplicada ao arquivo real).
- `logs/`, `captures/` — evidências.

**Fora de `tests/claude_gameplay_audit/`, autorizados por esta tarefa:**
- `world/mountain_pass/MountainGunShopFacade.gd` — correção local de 1 linha (achado nº 1).
- `tests/test_harbor_mountain_drive.gd` — contrato de região atualizado (achado nº 5).

Nenhum outro arquivo compartilhado, save do jogador, ou a pasta do
Antigravity foram tocados. Nenhum reset nem commit foi executado.
