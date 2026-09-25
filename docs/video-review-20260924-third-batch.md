# Revisão do vídeo — terceiro lote, 24/09/2026

Três agentes implementaram correções de veículos, reações de NPCs e três novos acessos. O coordenador integrou atendimento, minimapa, salvamento e morte. Este relatório complementa o [plano de ação](video-review-20260924-action-plan.md); não encerra os 36 achados da gravação.

## Comportamento implementado

| Frente | Correção e evidência | Limite |
|---|---|---|
| Roubo após colisão | Uma batida real deixava impulso lateral ativo com velocímetro zero. O cupê deslizava **3,227 m** enquanto a apresentação usava porta/assento fixos; agora esse deslocamento residual é zero. | A queda original abaixo do mapa não foi reproduzida e continua aberta. |
| Controle do veículo | Trânsito suspenso pelo impacto podia reassumir o carro durante o roubo. A transferência agora reconhece essa origem e cancela a retomada da IA. | Colisões posteriores continuam empurrando e danificando o carro; não se desativou sua física. |
| Trabalhadores e atendentes | Tiros, explosões e fogo próximo interrompem atividades e atendimento. Personagens com corpo móvel recuam por um percurso com colisão e voltam depois que a ameaça cessa; rotinas/carga são preservadas. | Recuo curto, de até 1,6 m; um sólido impede o retorno até a passagem liberar. Não é uma nova IA de fuga pelo mapa. |
| Banco, portaria e Vance | Atendentes protegem a cabeça; guardas do banco continuam combatendo. Conversas/loja abertas são interrompidas e ações antigas não cobram por um atendimento indisponível. Vance recebe articulação local dos braços e recupera a pose original. | Maciota e mecânico ficam excluídos; nenhuma rotina de dano/morte foi acrescentada aos protegidos. Inventário independente permanece aberto. |
| Union, conveniência e Bay Medical | Portas físicas por proximidade, entrada caminhando, zoom de entrada/saída e retorno sem E de passagem. Fechadas bloqueiam; abertas permitem atravessar. | Três acessos a três interiores existentes. Entrada de ambulância preservada. Bombeiros requer revisão própria da fachada. |
| Fachadas | Publicidade aleatória sobre Union/conveniência removida; Union apresenta apenas seu nome próprio. | Não se inventou uma marca para a conveniência. Estação próxima da Union e iluminação intensa do hospital permanecem. |
| Minimapa | Continua visível e acompanha o veículo durante embarque e desembarque. | Modais, pausa, resgate e outros bloqueios continuam ocultando o mapa. |
| Salvamento | Autosave bem-sucedido não substitui mensagens úteis por “Progresso salvo”. F5 e botão Salvar mantêm confirmação; falhas continuam avisadas. | Persistência e economia preservadas. Testes usam arquivo próprio, sem gravar o save pessoal. |
| Morte e resgate | Morte forçada por queda zera saúde/HUD no mesmo fluxo; morte durante embarque mantém colisão e física do morto desativadas até o resgate. | Corrige o estado após a morte, não a causa da queda original. |
| Integração | Foco adiado verifica se o botão ainda pertence ao menu visível; reentrada não duplica a conexão de ameaça de Vance. Leitura de metadados opcionais do monitor dos bombeiros recebeu guarda de existência. | Correções motivadas por erros observados durante os testes, sem reformar outros sistemas. |

O componente de reação escuta eventos e consulta somente a lista limitada de incêndios a 4 Hz. Movimento físico adicional ocorre enquanto a reação está ativa. Isso limita o trabalho acrescentado, mas **não substitui medição de performance**.

## Validações executadas

Godot 4.7.2, sessão Main real. Capturas Vulkan Mobile, RTX 4060 Laptop, 2560×1440. As confirmações finais passaram; o erro de foco da rodada anterior está identificado na tabela. Capturas e headless não certificam FPS.

| Verificação | Resultado | Evidência |
|---|---:|---|
| Veículos: parado, em movimento, recém-colidido, recuperação do impacto, entrada/saída e nova colisão | 78/78 funcionais | [Log](../evidence/video-review-20260924/phase3-vehicle-after.log) |
| Dois veículos renderizados com física real | 47/47 verificações, incluindo 8 PNGs | [Log](../evidence/video-review-20260924/phase3-vehicle-render.log) |
| Interrupção/reversão da apresentação veicular | 21/21 | [Log](../evidence/video-review-20260924/phase3-vehicle-body-regression.log) |
| Restauração do motorista / transferência entre garagens | 26/26 e 11/11 | [Restauração](../evidence/video-review-20260924/phase3-garage-driver-restore.log), [transferência](../evidence/video-review-20260924/phase3-garage-vehicle-transfer.log) |
| Union, conveniência, hospital: portas, corpo inteiro, caminhada, zoom, retorno, reentrada e interrupções | 99 funcionais + 18 PNGs = 117/117 | [Log](../evidence/video-review-phase3-20260924/phase3-access-after-render.log) |
| Recaptura dirigida das três portas fechadas após a cortina inicial | 17/17, incluindo 3 PNGs | [Log](../evidence/video-review-phase3-20260924/phase3-access-closed-render.log) |
| Reações: tiro/fogo, atividade/carga, retorno bloqueado, banco, loja, garagem e hospital | 60/60 asserções; erro de foco encontrado e corrigido depois | [Main causal](../evidence/video-review-phase3-20260924/phase3-reactions-test-2.log) |
| Registro de NPC exterior com jogador na garagem e exclusão de protegidos | 5/5 | [Escopo](../evidence/video-review-phase3-20260924/phase3-reactions-scope.log) |
| Confirmação final dirigida: foco, reentrada, Vance/loja, garagem, hospital e inventário | 28/28, sem erro de foco | [Log final](../evidence/video-review-phase3-20260924/phase3-reactions-remaining-final.log) |
| Reações renderizadas no porto, banco e Vance | 7 PNGs, zero falhas de captura | [Log](../evidence/video-review-phase3-20260924/phase3-reactions-after.log) |
| Minimapa, autosave isolado, F5, botão Salvar, erro de escrita e morte forçada | 33 funcionais + 4 PNGs = 37/37 | [Log renderizado](../evidence/video-review-phase3-20260924/phase3-hud-after-render.log) |
| Morte comum durante embarque e recuperação pelo resgate, execução dirigida | 10/10, incluindo 2 verificações de inicialização | [Log](../evidence/video-review-phase3-20260924/phase3-hud-death-boarding.log) |
| Integração dos estabelecimentos, incluindo roupas e catálogo/bancada | 77/77 | [Log](../evidence/video-review-phase3-20260924/phase3-establishments.log) |
| Integração de sessão, câmera, clima, morte e garagem sem armas | 31/31 | [Log](../evidence/video-review-phase3-20260924/phase3-session-transitions.log) |

As rodadas de reações se sobrepõem; 60 + 5 + 28 não significam 93 casos distintos. Os sete PNGs também não são sete testes funcionais adicionais. O adaptador de `test_harbor_gameplay_acceptance.gd` recebeu verificação de parser, não execução da suíte ampla.

### Diagnósticos preservados

- Veículos antes da correção: 67 verificações, três falhas. Depois: 78 sem falhas. Altura/contato com o pavimento e retomada de IA foram observados durante toda a apresentação; não se inferiu a causa do voo apenas pelas fotos. [Diagnóstico completo e amostras](../evidence/video-review-20260924/phase3-vehicle-findings.md).
- O retorno original da Union cruza a colisão da estação existente. O código já procura posições alternativas seguras; o teste passou a aceitar apenas esses candidatos e a exigir corpo inteiro livre. O retorno usado foi Z + 0,75 m. Nenhum sólido foi retirado para passar.
- A primeira foto da porta fechada da Union ainda continha a cortina inicial. O teste passou a aguardar sua conclusão; somente as três fotos de porta fechada foram repetidas.
- O trabalhador demorava a retomar porque novos tiros da polícia legada renovavam o perigo. `skip_dispatch` não desliga essa polícia. O cenário de recuperação passou a isolar novas intervenções depois do estímulo real, preservando a exigência de retorno físico. Uma parede temporária comprova que o NPC espera, sem atravessar o obstáculo.
- Vance pertence à arte estática da loja e não ao cadastro genérico de NPCs. A integração agora inclui esse ator. A proteção da garagem considera a identidade/ancestralidade do ator; um trabalhador exterior continua sendo registrado mesmo se o save carregar o jogador dentro de Maciota.
- O teste de autosave provoca uma falha de escrita deliberada. A mensagem “Não foi possível salvar (20)” na foto posterior de morte pertence a esse cenário negativo. “Mensagem funcional de controle” na foto de autosave é texto do teste para verificar que o salvamento não substitui uma mensagem existente.

**Avisos de encerramento:** o teste preexistente de apresentação veicular registrou 4 objetos ObjectDB/1 recurso retidos; transferência de garagem, 18 objetos/5 recursos. Não se isolou sua causa nem se declarou ausência de vazamentos. Alguns processos registram falha ambiental de leitura dos certificados do Windows; a verificação isolada de parser também encontrou bloqueio de escrita do log padrão pelo sandbox. Não houve uso de rede nesses cenários. Os testes novos de veículos e sua captura não registraram retenção ao encerrar.

## Evidências visuais

| Cena | Antes ou controle | Depois |
|---|---|---|
| Union | [Fachada anterior](../evidence/video-review-phase3-20260924/phase3-access-before-harbor_clothing-approach.png) | [Nome e acesso](../evidence/video-review-phase3-20260924/phase3-access-after-harbor_clothing-approach.png), [interior](../evidence/video-review-phase3-20260924/phase3-access-after-harbor_clothing-inside.png) |
| Conveniência | [Porta fechada](../evidence/video-review-phase3-20260924/phase3-access-after-harbor_fuel-door-closed.png) | [Aproximação](../evidence/video-review-phase3-20260924/phase3-access-after-harbor_fuel-approach.png), [saída com zoom](../evidence/video-review-phase3-20260924/phase3-access-after-harbor_fuel-exit-zoom.png) |
| Hospital | [Porta fechada](../evidence/video-review-phase3-20260924/phase3-access-after-harbor_hospital-door-closed.png) | [Porta aberta](../evidence/video-review-phase3-20260924/phase3-access-after-harbor_hospital-approach.png), [interior](../evidence/video-review-phase3-20260924/phase3-access-after-harbor_hospital-inside.png) |
| Atendentes do banco | [Sem reação antes](../evidence/video-review-phase3-20260924/before-bank-clerks-shot.png) | [Proteção atrás do balcão](../evidence/video-review-phase3-20260924/after-bank-clerks-shot.png) |
| Portaria | [Sem reação antes](../evidence/video-review-phase3-20260924/before-port-worker-shot.png) | [Reação ao tiro](../evidence/video-review-phase3-20260924/after-port-worker-shot.png) |
| Vance | [Repouso](../evidence/video-review-phase3-20260924/after-vance-idle.png) | [Ameaça](../evidence/video-review-phase3-20260924/after-vance-shot.png), [recuperado](../evidence/video-review-phase3-20260924/after-vance-recovered.png) |
| Minimapa no embarque | [Antes](../evidence/video-review-phase3-20260924/hud/before-entry-minimap.png) | [Depois](../evidence/video-review-phase3-20260924/hud/after-entry-minimap.png) |
| Autosave | [Aviso anterior](../evidence/video-review-phase3-20260924/hud/before-autosave-feedback.png) | [Mensagem preservada](../evidence/video-review-phase3-20260924/hud/after-autosave-feedback.png) |
| Saúde na morte por queda | [Vida cheia indevida](../evidence/video-review-phase3-20260924/hud/before-forced-death.png) | [Saúde zero](../evidence/video-review-phase3-20260924/hud/after-forced-death.png) |

Os agentes inspecionaram as 24 imagens de acessos (6 antes/18 depois), 8 de veículos e 11 de NPCs (4 antes/7 depois). O coordenador conferiu amostras dos acessos, reações do porto/banco/Vance e as quatro imagens finais de HUD. As imagens comprovam os comportamentos específicos descritos, sem aprovação artística integral dos ambientes.

## Arquivos e trabalho concorrente

- Veículos: dois métodos em `scripts/Vehicle.gd` e `scripts/Driving.gd`.
- Reações: novo `gameplay/civilian_reactions/WorkplaceThreatReaction.gd`; integração em `V1RoutineActor.gd`, `RoutineDirector.gd`, `HarborPortSecurity.gd`, `RobberyActor.gd` e `FullSession.gd`. Articulação de Vance apenas na fábrica desse personagem em `AmmunationArt.gd`.
- Acessos: `WeaponShopEntrance.gd`, `UrbanLandmarkFrontage3D.gd`, `NativeRegion.gd`, `HarborHospitalModel3D.gd` e uma habilitação em `UrbanBuildingFactory.gd`; exclusão pontual de anúncios em `CityChunkDressing.gd`.
- Integração: `FullSession.gd`, `HarborMinimap3D.gd`, `PauseMenu.gd` e duas guardas de metadados em `Responder.gd`.
- Testes novos: `test_video_phase3_access.gd`, `test_video_phase3_vehicle.gd`, `test_video_phase3_reactions.gd`, `test_video_phase3_hud.gd` e capturas correspondentes. Adaptadores de acesso dos testes existentes acompanham o contrato sem E.

`HarborAmmunationCatalog.gd` e `HarborWeaponWorkbench.gd` continuam reservados ao Claude e não foram editados por esta equipe. Seu relatório colado pelo usuário é histórico: integração de 77 verificações e inspeção das quatro telas iniciais já constam do [segundo lote](video-review-20260924-second-batch.md). Ampliações posteriores da bancada não recebem certificação visual retroativa. Nenhuma edição concorrente foi descartada e nenhum commit foi feito.

Verificação final das diferenças sem erros de whitespace, somente avisos LF/CRLF. Os 41 links locais deste relatório foram conferidos e existem. Todos os processos desta frente terminaram; a inspeção final encontrou apenas os dois processos Godot do usuário.

## Pendências que permanecem abertas

1. **FPS e travamentos:** sem comparação isolada de frame time antes/depois. Editor PID 76560 e jogo PID 86396 do usuário foram preservados. Capturas sequenciais evitam sobrepor os testes entre si, mas não tornam o benchmark comparável enquanto outra partida está ativa.
2. **Queda original do carro:** o impulso e a retomada de IA foram corrigidos; o mergulho abaixo do mapa do vídeo ainda precisa de reprodução causal. Corrigir o HUD da morte não encerra esse achado.
3. **Acessos:** agora há **9 acessos automáticos/9 interiores**, de um inventário de 32 acessos físicos/30 interiores. Restam **23 acessos/21 interiores**, incluindo bombeiros e fluxos especiais. Não se migraram navio, alçapão e caverna sem projeto próprio.
4. **Certificação física/visual:** as portas e os percursos escolhidos passaram, mas falta contrato completo de circulação, colisão e oclusão de todos os móveis/NPCs. **Zero novas certificações completas de interiores** neste lote. [Checklist](interior-standard-checklist.md).
5. **Conteúdo e apresentação:** atividades e revisão ampla do porto, void, iluminação noturna, geometria da prévia da pistola, qualidade artística dos personagens e validação da interface em outras resoluções/controle continuam abertos. A reação de Vance não substitui a revisão do seu modelo.
