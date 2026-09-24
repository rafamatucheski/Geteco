# Aceitação integrada V1 → V2 — Harbor

Data: 2026-09-21
Resultado: **não aprovada para entrega integrada**. A rodada de conexão corrigiu o bloqueador de interface e a reação civil a tiros reais. Resta 1 lacuna de transição corporal no embarque e 1 lacuna de apresentação do serviço, ambas fora da responsabilidade desta integração.

## Escopo, referência e segurança

- Referência produtiva V1: `res://world/harbor/HarborGame.tscn` e os controladores atuais chamados por `world/harbor/HarborGame.gd`. O relatório antigo de `tests/claude_gameplay_audit/` foi usado só como mapa do roteiro; diferenças foram reconferidas no código V1 atual.
- Alvo V2: `geteco_v2/Main.tscn`, instanciado diretamente para não passar pelo menu que procura slots existentes.
- Todas as execuções de gameplay usaram `--no-save` e um `APPDATA` temporário exclusivo. Nenhum slot, autosave ou arquivo pessoal foi aberto.
- Persistência foi exercitada sem instanciar o mundo, com `SaveStore.path` injetado em `C:/Users/rafae/AppData/Local/Temp/geteco-v2-save-7f9b96e8580a4f7bbab1af9c8e5a4699/progress.json`. O validador recusa qualquer raiz que não seja um subdiretório absoluto e exclusivo de `OS.get_temp_dir()`.
- Não foi executada suíte ampla. Havia importações/testes Godot concorrentes durante a rodada; por isso não há aprovação de performance e timeouts de validadores V1 antigos foram registrados como impedimento, não como defeito do jogo.

## Roteiro de aceitação

| Ordem | Fluxo e referência V1 | Ação dirigida no V2 | Resultado observado |
|---|---|---|---|
| 1 | `HarborArrivalMission`/`HarborStoryArrival`: chegada, desembarque, delegacia e telefone | sessão nova isolada, desembarque físico, delegacia, conversa e telefone | passou sem falhas do cenário; ocorreram avisos de foco ao remover diálogos rapidamente, portanto o acabamento da interface não está aprovado |
| 2 | `Player`: andar/correr, passos e interação | caminhar, correr, entrar em Maciota, conversar, pegar peça e sair | passou; 2,57 m andando, 4,87 m correndo na mesma janela, clipes `Walking`/`Running` e voz de passos ativa |
| 3 | `PlayerCar` + `VehicleBoarding`: entrar, dirigir, frear e sair | entrada por `F`, 13,43 m dirigidos, roda/mixer, parada e saída | condução, roda, áudio e saída passaram; transição corporal de embarque ausente |
| 4 | Ammu-Nation + combate produtivo | entrar, abrir loja, obter/equipar pistola, mirar, disparar e recarregar | passou; mira teve alinhamento 1,000, dano 100→84, munição/crime, queda, áudio, recarga e `Enter` no botão focado passaram |
| 5 | `PedestrianDanger`/`AnimatedPedestrian3D` + Wanted | atirar em civil com testemunha próxima, matar e aguardar despacho | passou; o tiro real acionou fuga a 5 m/s, crime chegou a 112/4 estrelas e houve evento de despacho |
| 6 | `HarborAutoService` | estacionar carro danificado na baia Northgate e aguardar 4,5 s | cobrança única 350→250, reparo, limpeza do procurado e mensagem passaram; apresentação V1 não existe no V2 |
| 7 | `HarborFirstFavors` | diário → Helena no banco desarmado → encomenda no cais → Maciota | objetivo, três etapas, conclusão e recompensa única 250→400 passaram |
| 8 | `Player._wasted` | dano fatal, tela de resgate, continuar e reaparecer | passou por Enter e botão A em mortes separadas; vida, controle, exterior seguro e câmera restaurados; saldo permaneceu 400, em paridade com o V1 atual |
| 9 | save sintético | dois snapshots, carga, corrupção controlada do primário, recuperação do backup, compatibilidade e estado urbano | 18/18 no estado geral e 14/14 no contrato porto/cemitério; saves V2 anteriores sem o campo urbano continuam válidos e payload parcial é rejeitado sem alterar o estado vivo |

Os quadros renderizados tinham 1280×720 e assinaturas não vazias distintas em início, garagem, condução, loja, mira, reação ao tiro, Northgate, missão e resgate. Isso comprova que houve saída visual, não qualidade estética. Vozes de áudio ativas comprovam roteamento, não mixagem, volume percebido ou qualidade. Nenhuma animação, interface ou paisagem sonora recebe aprovação humana nesta rodada.

## Diferenças priorizadas, sem duplicações

### Resolvido — Botões focados de modal não aceitavam `Enter`/`ui_accept`

1. **V1 produtivo:** os fluxos críticos de chegada usam `ui_accept`/Enter; a morte executa a recuperação automaticamente depois da apresentação e não deixa o jogador dependente de um botão inacessível (`characters/Player.gd::_wasted`).
2. **V2 observado:** antes da correção, o botão da pistola recebeu foco, mas Enter não o acionou. Depois, Enter comprou/equipou a arma e Enter/botão A confirmaram o resgate em mortes reais separadas.
3. **Reprodução mínima:** entrar na Ammu-Nation → interagir no balcão → focar “PISTOLA 9MM” → pressionar Enter. Alternativa crítica: morrer → deixar “Continuar” focado → pressionar Enter.
4. **Impacto no jogador:** o bloqueio de teclado/controle foi removido; o ponteiro continua funcionando.
5. **Arquivo/sistema provável:** `geteco_v2/runtime/FullSession.gd`, ramo `if modal` de `_input` (consome `ui_accept` e retorna antes do `Button`) e criação dos botões em `_button`/`_show_shop`/`_on_death`.
6. **Equipe responsável:** integração de interface e controles / dona de `FullSession`.
7. **Evidência e certeza:** falha reproduzida antes; depois, percurso integrado passou o botão da loja e `test_modal_ui_accept_independent.gd` passou 11/11 com teclado, controle e duas mortes. **Certeza alta.**

### Resolvido — Tiros reais não acionavam fuga das testemunhas civis

1. **V1 produtivo:** disparos notificam pedestres; `PedestrianDanger` chama `hear_gunfire`, e `AnimatedPedestrian3D.panic()` inicia fuga por 9–12 s.
2. **V2 observado:** antes, a testemunha a 4 m permaneceu sem fuga. Depois, existe um único diretor produtivo e a mesma testemunha assumiu fuga (`controlled_automatically=true`, velocidade 5,0) pelo sinal real do tiro.
3. **Reprodução mínima:** obter pistola → colocar um civil testemunha próximo e fora da linha → atirar em outro civil → observar a testemunha.
4. **Impacto no jogador:** a leitura social do tiro foi restaurada para civis genéricos elegíveis.
5. **Arquivo/sistema provável:** `geteco_v2/runtime/ProductionWorld.gd`, `geteco_v2/gameplay/civilian_reactions/CivilianReactionDirector.gd` e sinal de disparo em `geteco_v2/gameplay/Gameplay.gd`.
6. **Equipe responsável:** vida urbana/reações civis, com integração em `ProductionWorld`.
7. **Evidência e certeza:** falha reproduzida antes; depois, o percurso integrado passou e o validador específico confirmou 1 sinal/1 tratamento, tiro normal, acessório real `suppressor`, raio curto e continuidade cidade–serra. **Certeza alta.**

### P1 — Embarque normal troca de estado instantaneamente, sem a transição corporal V1

1. **V1 produtivo:** `PlayerCar.enter_vehicle()` cria `cars/VehicleBoarding.gd`; o carro mantém `vehicle_boarding` por uma sequência de 1,45–2,45 s, com aproximação, porta, pose e ocupante de cabine.
2. **V2 observado:** `F` tornou o carro controlado e ocultou Dante em até dois quadros, sem fase/metadado de embarque. Direção e desembarque continuaram funcionais.
3. **Reprodução mínima:** parar ao lado de qualquer carro dirigível → pressionar `F` → observar Dante e o estado do carro nos quadros seguintes.
4. **Impacto no jogador:** teleporte visual brusco para dentro do carro e perda de continuidade corporal, apesar de a lógica veicular funcionar.
5. **Arquivo/sistema provável:** `geteco_v2/scripts/Driving.gd::interact/leave`; integração ausente com uma apresentação equivalente a `cars/VehicleBoarding.gd`.
6. **Equipe responsável:** veículos e animação do jogador.
7. **Evidência e certeza:** falhou em três passagens renderizadas; leitura V1/V2 mostra caminhos estruturalmente diferentes. **Certeza alta.**

### P2 — Northgate entrega o estado correto sem a apresentação do serviço V1

1. **V1 produtivo:** `world/harbor/HarborAutoService.gd` fecha/abre persiana, oculta e reposiciona o carro, emite spray e toca som durante 4,5 s, mantendo o jogador bloqueado até a saída.
2. **V2 observado:** `Services.gd` contou 4,5 s, cobrou, reparou, limpou procurado e mostrou “Veículo reparado.”; não há persiana, spray ou áudio de serviço no caminho V2.
3. **Reprodução mínima:** danificar carro → estacionar parado na baia Northgate com R$ 100 → aguardar conclusão sem mover.
4. **Impacto no jogador:** o serviço parece um temporizador invisível; a mensagem confirma o resultado, mas falta a entrega audiovisual que comunica trabalho em andamento e conclusão.
5. **Arquivo/sistema provável:** `geteco_v2/runtime/Services.gd` e apresentação da fachada/baia em `geteco_v2/world/regions/NativeRegion.gd`.
6. **Equipe responsável:** serviços e apresentação de mundo/Harbor.
7. **Evidência e certeza:** lógica confirmada em runtime; ausência confirmada por comparação dos dois caminhos produtivos e já declarada em `geteco_v2/docs/services-migration.md`. **Certeza alta.**

## Diferenças conferidas que não foram classificadas como bug

- Northgate V2 cancela ao mover ou sair antes de 4,5 s, sem cobrar; o V1 bloqueia o jogador durante a sequência. A documentação V2 define explicitamente o cancelamento como regra, então não foi tratado como regressão.
- V2 pede confirmação “Continuar” no resgate; V1 conclui automaticamente. A escolha em si não foi classificada como bug — somente a impossibilidade de confirmar por `ui_accept`.
- Morte sem cobrança no V2 coincide com o `characters/Player.gd` atual. A expectativa antiga de desconto de R$ 100 em `test_audit_07_death_and_recovery.gd` está obsoleta e não foi usada.
- O JSON normaliza alguns números inteiros para ponto flutuante (`32`→`32.0`, `0`→`0.0`). O validador compara a representação JSON garantida e continuou exigindo todas as chaves e valores; não houve perda de estado.

## Evidência executável e impedimentos

- `geteco_v2/tests/test_harbor_gameplay_acceptance.gd`: antes, **90 verificações e 3 falhas**; depois, **90 verificações e 1 falha**, somente a transição de embarque fora deste escopo. Modal e testemunha passaram por ações produtivas.
- `geteco_v2/tests/test_modal_ui_accept_independent.gd`: **11/11**, com Enter e botão A em modal comum e resgate após duas mortes reais.
- `geteco_v2/tests/test_civilian_reactions.gd`: **35/35**, incluindo tiro real normal/silenciado, instância única, ausência de duplicação, origem de agressão e continuidade lógica cidade–serra.
- `geteco_v2/tests/test_harbor_synthetic_save_acceptance.gd`: **18/18**, inclusive backup após corrupção controlada apenas do primário sintético.
- `geteco_v2/tests/test_urban_snapshot_persistence.gd`: **14/14**, em raiz temporária exclusiva; valida compatibilidade anterior, round-trip completo e rejeição atômica de estado parcial.
- `geteco_v2/tests/test_urban_operations.gd`: passou sem falhas na sessão produtiva `--no-save`.
- `geteco_v2/tests/test_arrival_flow.gd`: exit 0, sem falhas; emitiu avisos `grab_focus` durante avanço acelerado de diálogo. Não foram convertidos em achado sem reprodução pelo jogador.
- `tests/claude_gameplay_audit/test_audit_01_arrival_and_control_release.gd`: falhou antes do cenário porque o prazo fixo de 30 quadros terminou antes de `campaign_controller` ser anexado.
- `tests/claude_gameplay_audit/test_audit_02_vehicle_boarding.gd`: não executado; o mesmo prazo encontrou `PersonalCarManager` ainda ausente e o watchdog encerrou em 90 s durante construções/importações concorrentes. O V1 de embarque foi confirmado no código produtivo, não por essa corrida.
- Não foram executados benchmarks: a checagem final encontrou o editor e dois validadores de outra frente ativos, portanto medir agora violaria o critério de isolamento. Também não houve suíte completa, abertura do menu principal, leitura de slots ou avaliação humana de imagem/som.

## Critério de saída para os implementadores

Reexecutar o percurso renderizado com `--no-save --skip-arrival --population=8` e armazenamento de aplicativo temporário. A aceitação integrada exige 0 falhas; a pendência executável é a apresentação do embarque. Revisão humana ainda deve confirmar embarque, Northgate, foco/feedback dos modais e fuga civil visíveis e audíveis. Persistência deve continuar sendo executada somente com `--isolated-save-root` sob o diretório temporário.

## Revalidação independente após as entregas — 2026-09-21

Esta seção é posterior aos resultados acima. Ela registra a versão exata observada antes de cada cenário e não promove passes de uma versão anterior para arquivos que mudaram depois. Todas as sessões de mundo usaram `--no-save`; `APPDATA` foi redirecionado para subdiretórios exclusivos de `C:/Users/rafae/AppData/Local/Temp/geteco-independent-20260921-1948/`. A única escrita de progresso ocorreu em raízes sintéticas exclusivas sob esse mesmo diretório. Nenhum save pessoal foi aberto.

| # | Cenário independente | Estado da versão corrente | Evidência da última versão efetivamente executada |
|---|---|---|---|
| 1 | `Enter`/`ui_accept` em modal e resgate, teclado e controle | **bloqueado** | `test_modal_ui_accept_independent.gd`: 11/11 em `FullSession.gd` SHA-256 `ABEFB425...FA948`; botão focado acionado por Enter e A, inclusive em duas mortes/resgates separados. O mundo compartilhado (`Gameplay.gd`) mudou depois, portanto o passe comprova a correção de `FullSession`, mas não certifica a composição corrente |
| 2 | tiro real → percepção civil → fuga → retomada | **bloqueado** | o encadeamento produtivo passou 10/10 em `Gameplay.gd` `46521D11...C284C41`, diretor `23F16CD0...F2211` e `Actor.gd` `9D1C0834...F1E7F`: munição consumida, fuga de 6,88 m, velocidade original 1,73 e rota de 2 pontos restauradas; `Actor.gd` mudou depois para `7D10AB06...AD7B5`, sem nova janela estável |
| 3 | caminhar/correr → parar → repouso | **bloqueado** | passou 8/8 em `Actor.gd` `9D1C0834...F1E7F`: deriva 0, peso de locomoção 0 e diferença residual de pose 0,0014 rad; o arquivo mudou depois para `7D10AB06...AD7B5`, invalidando a certificação da versão corrente |
| 4 | crime → polícia → encerramento | **bloqueado** | `test_dispatch_integrated_pursuit.gd` passou 14/14 em `Gameplay.gd` `46521D11...C284C41`, incluindo policiais a pé e limpeza sem órfãos; depois `Gameplay.gd` passou por `4EA1D5C3...2EB7`, que não compilou nas linhas 864/867, e mudou novamente para `B6106C8B...44D70` antes do fechamento, sem nova janela de teste |
| 5 | colete, coleta e serviço → resultado → save/restauração | **bloqueado** | rota renderizada comprovou serviço e coleta; `test_harbor_synthetic_save_acceptance.gd` passou 18/18 com primário, backup e corrupção sintéticos. O fechamento atômico conjunto foi impedido pela edição concorrente de `Gameplay.gd`; o arquivo mudou novamente depois do impedimento e não foi reexecutado em laço |
| 6 | porto/cemitério após afastamento e restauração | **bloqueado** | não executado contra a versão corrente: `PortOperations.gd` estava em `E33CE9E9...35CDF`, `CemeteryOperations.gd` em `EFDA729F...F42D` e o próprio validador em `C7B66E9E...9787`, todos posteriores à evidência anterior; a dependência comum `Gameplay.gd` falhou na compilação e voltou a mudar durante o fechamento |
| 7 | HUD original e câmera atual nos fluxos reais | **bloqueado** | a rota renderizada anterior percorreu início, interiores, condução, loja, combate, serviço, missão e resgate em 1280×720, com câmera restaurada e HUD funcional; como `Gameplay.gd` e `Actor.gd` mudaram depois, essas imagens/estados não aprovam a versão atual |

### Controle de concorrência e fixtures

- `FullSession.gd` mudou de `21155E01...F13F5` para `ABEFB425...FA948` durante a rodada. O primeiro resultado de modal foi descartado e houve uma única reexecução dirigida na nova versão, que passou.
- `Actor.gd` mudou duas vezes durante a rodada. Passes de fuga/retomada e repouso permanecem evidência da versão `9D1C0834...F1E7F`, não aprovação de `7D10AB06...AD7B5`.
- `Gameplay.gd` mudou entre a fotografia e a compilação do cenário 5, falhou nessa fotografia intermediária e mudou de novo às 19:54 (SHA-256 `B6106C8B...44D70`). A execução foi classificada como impedida, sem repetição em laço e sem encerrar processos alheios.
- `test_civilian_reactions.gd` cria um segundo diretor e espera velocidade fixa 1,6; isso contradiz a população produtiva, cuja testemunha desta rodada tinha velocidade original 1,73. O validador independente usou o diretor de `ProductionWorld` e exigiu restauração do valor capturado, sem afrouxar rota, controle ou movimento retomado.
- `test_full_save.gd` não executou por erro de inferência em `orphan_weapon` na linha 71. Isso é defeito da fixture, não falha reproduzida do save. O validador sintético oficial continuou exigindo round-trip completo e recuperação de backup.
- A nova locomoção conserva a fase do ciclo como memória interna, mas aplica uma pose de repouso cacheada. O critério independente mede parada, peso de locomoção e pose do rig; não exige zerar uma variável interna que já não representa a aparência.

### Diferenças ainda percebidas pelo jogador

- O embarque continua instantâneo, sem a transição corporal V1; foi a única falha da rota renderizada de 90 verificações.
- Northgate conclui cobrança, reparo e limpeza do procurado, mas ainda não apresenta persiana, spray e áudio do serviço V1.
- Por causa da edição corrente sem janela estável de revalidação, Harbor como conjunto permanece **não aprovado**. Os checks acima não podem ser somados para contornar os cenários bloqueados.
