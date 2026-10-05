# Critérios prospectivos das assinaturas na recuperação WPR

Aplicáveis a `stall1709-wpr-rec1` e, se necessária, `stall1709-wpr-rec2`, antes da coleta. [Plano](D:/geteco/game/evidence/stalls-1709-20261005/recovery-wpr-plan.md). Não agrupam automaticamente um máximo novo à pausa histórica.

| Classe | Positivo no bruto do jogo | Dado nativo que discrimina | Limite da conclusão |
|---|---|---|---|
| Gap após callbacks físicos, família alvo | Intervalo ≥250 ms e trecho ≥250 ms entre o último physicsEnd e próximo process_frame, com markers na ordem real | CSwitch/ReadyThread contínuos no próprio gap, wait stack/caller e samples de execução; thread sinalizadora se presente | Localização semelhante não demonstra identidade causal com f16083 sem stack/espera equivalente |
| Callback de rua, comparador | Intervalo ≥250 ms, callback grande e `vehicle.street_pre` nele, por overlap real | Switch-out/stack e execução dentro do WORK, com ID da unidade e caller preservados | O f15918 antigo não tem filhos medidos; solver/fila/áudio não podem ser escolhidos por palpite |
| Preparação de colisão/ground | Span positivo `dispatch.prepare_ground` ou filho medido, incluindo caso ≥250 ms | Stack dentro do span mais estados contínuos do PID/TID alvo | `.build` ausente não prova ausência de sync; não atribuir construção de chunk sem evento |
| Alocação de sangue | `ground_blood.allocate` atravessa pico, template/ID e stains registrados | Stack de espera/execução da operação, com continuidade auditada | Template retido corrige outra assinatura; allocate grande exige nova suboperação demonstrada |
| Caminho de desenho | Draw wall ≥40 ms dentro do intervalo, registrar também ≥25 ms | Caller/stack e threads próprias na janela draw, samples/CSwitch/Ready válidos | Não é GPU exclusiva; símbolos inválidos/compilação por contadores não provam causa |
| Catch-up/rampa | Operação ou gap anterior ao primeiro crescimento de passos; frames depois com 2/3 passos | Perfil do precursor e dos passos posteriores separados | Cap 3 não causou automaticamente o gatilho; reduzir cap não é correção demonstrada |
| Logger ou observador | WORK/self/command/query realmente cruza a pausa pelos timestamps | Stack/espera na operação própria e custo observado dentro do envelope | Registro anexado depois ou CPU pequeno não basta; não somar spans inclusivos nem subtrair observador |

Para cada positivo preservar frame, fase, engine_usec início/fim, READY+s pelo relógio bruto e QPC alinhado, posição e população, filas, passos e spans. Mostrar processEnd/draw/physicsStart/physicsEnd por ordem real: processEnd pode vir antes dos ticks físicos do intervalo. Não criar um process residual negativo para reclassificar o gap.

Uma partição nativa aceitável deixa explícito Running, Ready, Waiting e Unknown dentro do envelope recortado. Não assumir estado antes da primeira ou depois da última transição; cruzar migrações por CPU e pares switch-out→ready→switch-in. Quando o motivo de wait é reportado, aplicá-lo somente ao estado Waiting. ThreadCpuProbe quantizado confirma deltas, sem substituir CSwitch. CPUs/Ready/Wait separados não são percentuais de GPU.

Se a main acumular Ready, examinar os CPUs elegíveis, suas execuções e prioridades registradas antes de nomear contenção externa. Se estiver Waiting, identificar stack de switch-out, caller, objeto/thread que a libera quando os eventos permitirem. Se estiver Running, usar samples e chamadas medidas para localizar o trabalho; Scheduled-running sem DPC/Interrupt não é CPU exclusivo. Se transições forem incompletas ou sobrescritas, classificar Unknown. Sem hard-fault/DiskIO/DPC/IRQ, esses mecanismos continuam sem medida, mesmo que a RAM caia ou ccusage coincida.

OpenUsage normal pode iniciar consultas durante uma rodada. O v4 registra identidade/counters/foco, sem intervenção ou CLI própria; burst contemporâneo continua correlação. Não controlar o utilitário nesta etapa e não publicar comando/ambiente/billing privado. As duas exposições próprias anteriores eram negativas para o alvo, não uma prova de irrelevância externa.

Reprodução ≥250 ms sem cobertura ETL dentro do próprio trecho é positivo do jogo com lacuna nativa, não causa resolvida. Cobertura ETL adequada sem reprodução é negativo de observação, inconclusivo para a causa antiga. Positivo em draw, preparação ou sangue não substitui reprodução do gap alvo. Símbolos ausentes limitam função, ainda que scheduling seja mensurável. Nenhuma assinatura será declarada corrigida nesta etapa observacional.

Quando houver operação/espera identificada, o próximo experimento deve alterar uma única variável compatível com esse resultado, mantendo identidade, população, RNG, timers, materiais, colisão, visual e simulação. Seu controle precisa reproduzir a assinatura; antes/depois renderizado e contratos pertinentes serão planejados depois da evidência, sem novo jogo implícito neste documento.
