# Auditoria final do jogo e observadores — WPR rec3

A segunda e última captura do lote terminou válida, exit 0, com save/cleanup WPR confirmados. **Zero frames de gameplay/cauda ≥250 ms e zero gaps ≥250 ms depois do último callback físico.** O máximo desse gap foi 4,584 ms no f12458 de evento (frame 26,478 ms); na recuperação, 4,468 ms no f13849 (frame 17,554 ms). A assinatura histórica de 1.709,627 ms não se reproduziu e continua sem causa ou correção demonstrada.

Rec2 e rec3 consumiram os dois motores permitidos; rec1 foi falha de preparação sem Game. O [plano rec3](D:/geteco/game/evidence/stalls-1709-20261005/rec3-plan.md) alterou somente a consulta de identidade do helper de observação, de 4A9 para DD62, sem código de gameplay, controles, Bluetooth, drivers, políticas ou carga ccusage própria. Este relatório foi produzido offline, sem nova execução, build, UAC ou consulta de processo alheio. [JSON causal](D:/geteco/game/evidence/stalls-1709-20261005/wpr-rec3-causal-audit.json), [analisador](D:/geteco/game/evidence/stalls-1709-20261005/analyze_wpr_rec3_causal.py) e [bruto renderizado](D:/geteco/game/evidence/intermittent-stalls-20261004/stall1709-wpr-rec3/stall1709-wpr-rec3.json).

## Métricas e alcance da comparação

| Fase | Frames | s | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 | /s | >66,7 | /s |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Gameplay | 15582 | 120,017 | 6,198 | 14,026 | 15,735 | 94,667 | 13 | 0,108318 | 4 | 0,033329 |
| Primeira passagem | 5576 | 30,011 | 4,215 | 8,873 | 11,528 | 94,667 | 7 | 0,233 | 3 | 0,100 |
| Retorno | 4008 | 30,003 | 5,467 | 12,133 | 13,807 | 37,916 | 2 | 0,067 | 0 | 0 |
| Evento | 3352 | 30,000 | 10,467 | 13,612 | 15,410 | 94,167 | 1 | 0,033 | 1 | 0,033 |
| Recuperação | 2646 | 30,003 | 12,883 | 15,404 | 17,331 | 40,514 | 3 | 0,100 | 0 | 0 |
| Loading | 543 | 19,358 | 2,320 | 73,401 | 136,963 | 7173,424 | 53 | 2,738 | 38 | 1,963 |
| Cauda | 268 | 3,003 | 13,094 | 14,721 | 15,267 | 16,265 | 0 | 0 | 0 | 0 |

Percentis usam todos os frames, sem descarte de loading ou primeira passagem. Detalhes sem arredondamento constam na [análise canônica](D:/geteco/game/evidence/stalls-1709-20261005/wpr-rec3-analysis.json). GP p95/p99 ficaram 7,992%/7,597% acima de rec2 (12,988/14,624→14,026/15,735 ms); não aprovar FPS nem atribuir essa diferença à mudança do helper. São duas observações com ETW e cargas reais diferentes, não um A/B de correção do jogo. A cauda menor também não demonstra que o helper eliminou os picos anteriores.

## Recuperação realmente alcançada

Rec3 alcançou o local e estado pertinentes à assinatura antiga, ao contrário da custódia na rec2. Ida/volta efetivas: max_x 179,042984 e retorno 107,991684, sem atalhos do medidor durante esses segmentos. O campo literal `teleports_during_capture=0` não é um contador de transições automáticas; as conclusões abaixo vêm dos contextos/markers preservados.

| Marco | READY +s bruto | Frame/registro | Posição x/z | Estrelas/unidades | Pessoas/veículos/chunks |
|---|---:|---|---|---|---|
| Início do evento | 60,004859 | phase_changed | 107,9917 / 23,00001 | 0 / 3 | 32 / 40 / 16 |
| Início da recuperação | 90,005018 | phase_changed | 107,9917 / 23,00001 | 3 / 4 | 29 / 39 / 15 |
| Próximo ao comparador antigo +97,393732 | 97,391847 | f14175, 13,442 ms | 107,9917 / 23,00001 | 3 / 4 | 29 / 38 / 16 |
| Próximo ao alvo antigo +102,102540 | 102,105662 | f14590, 5,857 ms | 107,9917 / 23,00001 | 3 / 4 | 29 / 38 / 16 |
| Fim da rota | 120,007552 | route_end | 107,9917 / 23,00001 | 3 / 4 | 29 / 39 / 16 |
| Fim da cauda | 123,010249 | end | 107,9917 / 23,00001 | 3 / 4 | 29 / 40 / 16 |

Os contextos retidos de recuperação têm estrelas 3..3 e unidades 3..4; as unidades não são constantes em todos os frames. Não há salto >30 m entre contextos de recuperação consecutivos, estrelas zeradas ou custódia evidenciada nos dados retidos e nos snapshots de fase/fim. Os dois contextos próximos aos tempos dos picos antigos distam −1,885/+3,122 ms dos alvos e têm filas zeradas. Isso melhora a comparabilidade de local/procura/unidades; não torna física, veículos, trabalhadores, populações e host idênticos nem transforma ausência em eliminação causal.

Detalhes não são retidos em todo frame: o contexto de recovery mais perto de +120 s fora dos eventos está em +116,808969; route_end/end suprem snapshots posteriores, sem preencher artificialmente os frames intermediários. Um salto de 32,2 m entre detalhes da primeira passagem separados por 1849 frames/9,6 s é movimento normal da rota, não prova de teleporte. Na [rec2](D:/geteco/game/evidence/stalls-1709-20261005/wpr-rec2-causal-audit.md), a recuperação começou com 1 estrela/5 unidades e depois passou para custódia 66/125,728, com 0/0. Portanto comparar as duas caudas como se fossem a mesma cena/carga seria incorreto.

## Picos e localização causal

| Frame / fase | READY +s bruto | Frame ms | Maior trecho observado | Wall ms | CPU principal contabilizada no trecho ms |
|---|---:|---:|---|---:|---:|
| 748 primeira passagem | 1,311835 | 94,667 | pre_draw→post_draw | 55,297 | 15,625 |
| 2065 primeira passagem | 8,454387 | 81,836 | pre_draw→post_draw | 59,732 | 0 |
| 7532 retorno | 39,353718 | 37,916 | processEnd→pre_draw | 19,547 | 31,250 |
| 11673 evento | 73,128397 | 94,167 | pre_draw→post_draw | 55,752 | 0 |
| 13694 recuperação | 92,193832 | 35,262 | process_frame anterior→processEnd | 16,940 | 0 |
| 13695 recuperação | 92,229094 | 33,417 | process_frame anterior→processEnd | 14,111 | 0 |
| 15611 recuperação | 113,792856 | 40,514 | process_frame anterior→processEnd | 20,396 | 31,250 |

CPU é contador quantizado em 15,625 ms; zero não é zero instruções. Draw é wall, não GPU exclusiva. A ordem processEnd/draw/callbacks físicos é a dos timestamps reais; spans inclusivos de pai/filho não foram somados. Os máximos de draw em +1,31/+8,45/+73,13 s ficam fora da janela WPR dirigida a +85 s em diante e continuam positivos do jogo com lacuna nativa nesta coleta.

O f15611 tem 115 nós criados/20 liberados, sem WORK ≥1 ms sobreposto e sem localização de API exclusiva pelo collector. Dois callbacks físicos somam 13,716 ms, draw 2,504 ms e gap final 1,489 ms. Isso não reproduz a lacuna pós-física de 1,695 s, nem demonstra que os nós causaram seus 20,396 ms de processamento. F13694/f13695 têm 104/10 e 43/32 nós criados/liberados, também sem WORK ≥1 ms no próprio intervalo. A interpretação de espera/execução desses trechos pertence ao ETL com cobertura/continuidade auditadas.

Na abertura f543/83,134 ms preserva criação 991/liberação 484, callbacks e trabalho urbano; o f545/63,712 ms concentra 54,817 ms antes de processEnd com criação 273/liberação 32, sem WORK ≥1 ms. Loading conserva f0 7173,424 ms, resource_load 2738,896 ms; f304 3655,411 ms, f305 2301,548 ms e f306 415,806 ms. Não chamar esses frames de aquecimento descartável ou atribuí-los à janela nativa de recuperação.

Getter de sangue `ground_blood.material.get_rid` custa 19,682 ms em READY −1,091282 s, loading. O resumo diagnóstico das sete APIs de áudio custa 1,090 ms em +24,115245 s, abaixo do limiar de 25 ms e retido por cause sample. Não reproduz a pausa de áudio de 1,35 s nem explica os picos de recuperação. Nenhuma operação foi corrigida com base nessas coincidências.

## Retenção e validade

Todos os timings estão preservados; zero ring overflow, detalhes descartados, cause samples descartados, CPU inválida, tick mismatches, trace.events_dropped e writer drops. Prefixos START−3 s dos positivos selecionados têm os detalhes disponíveis retidos. Loading f0 não possui 3 s anteriores ao começo da coleta.

Cinco janelas omitem apenas o último frame que cruza POST: f2065 perde 6,610 ms; f5714 5,270 ms; f7532 2,819 ms; f8604 2,822 ms; f13695 1,295 ms. A do máximo de recuperação f15611 também omite o frame cruzante, 9,214 ms. Os timings desses frames existem; não é perda de prefixo ou overflow. Não declarar ±3 s estritamente completo sem registrar essa fronteira. As janelas de f748, f11673 e f13694 não têm detalhe faltante.

A cauda máxima de 16,265 ms não foi retida em detalhe, por ficar abaixo de 25 ms e fora de uma janela disparada anteriormente; o bruto contém seus timings e o evento end contém estado final. Não inventar callbacks/WORK/estado por frame para essa cauda, nem afirmar a partir dela que uma assinatura específica foi resolvida. Novos picos na cauda, se existissem, ainda teriam pós-contexto truncado pelo limite finito.

## Observador: ganho local medido, separado de FPS

| Dado próprio do helper | Rec2, 4A9 | Rec3, DD62 |
|---|---:|---:|
| CPU entre anchors internos de recording ms | 3625,000 | 609,375 |
| Wall entre esses anchors s | 38,469753 | 38,535787 |
| Fração de um core nessa janela | 9,423% | 1,581% |
| Queries de identidade totais | 1843 | 2201 |
| Query wall total ms | 27473,858 | 301,309 |
| Query wall máxima ms | 130,901 | 17,927 |
| CPU desde entrada do helper ms | 34546,875 | 7000,000 |
| Wall desde entrada do helper s | 223,501 | 235,500 |

A CPU própria por wall durante recording caiu **83,218%**; query wall total caiu 98,903%, apesar de mais chamadas no helper novo. Este é um ganho local do aparato coerente com a [preflight de APIs](D:/geteco/game/evidence/stalls-1709-20261005/query-limited-helper-review.md), que comparou 50 consultas próprias. Não é custo total ETW/kernel, custo de driver, nem prova de FPS melhor do jogo. Os anchors de comando abrangem +85,539165..+124,076069 s e diferem ligeiramente dos anchors de CPU: seus envelopes e scopes estão separados no JSON. Status próprio comprova stop after FINISHED/save/cleanup e ETL de 607.125.504 bytes; tamanho/status não comprovam a cobertura ou perdas por CPU.

StallLog rec3: self máximo 1,200 ms, sort 0,113 ms e writer 0,106 ms. Contexto acumulado 1326,639 ms em 16.393 chamadas; Input 151,858 ms. Somente nos intervalos retidos, observer wall soma 607,099 ms, capture 180,893 ms e signal 35,481 ms. Não somar estes subconjuntos inclusivos nem subtrair overhead dos frames.

O [coletor externo v4](D:/geteco/game/evidence/stalls-1709-20261005/wpr-rec3-offline-process-cpu.json) registrou 292 amostras entre READY −21,243873..+124,273648 s, com 3,392% de um core; query p50/p95/p99/máximo 17,328/20,578/22,453/28,743 ms. Nenhuma CPU positiva de ccusage foi observada. OpenUsage ficou ativo normal; ausência observada não elimina disputa externa, memória, scheduler ou qualquer causa histórica. Brackets de processo não fornecem CPU exclusiva por frame nem Ready/Waiting contínuo.

## C# e preservação

Os 1.650 hashes de fontes rec3 são iguais aos de D1/rec2, com `source_changed=[]`; config do report rec3=rec2. Cinco arquivos pertinentes de projeto/C#/router coincidem live=frozen=capture. Harbor compilou sem avisos/erros; stdout registra Godot 4.7.2 .NET `ed1daf0bf` e Mobile/Vulkan na RTX 4060 Laptop. READY enabled=true/active=false é a instância global lazy; plans privados do terminal têm native_active=true (29,090/0,509/0,456 ms), e o global/end é ativo. ClockAnchor/ThreadCpuProbe correspondem PID101116/TID97080. Não foi aprovação silenciosa por fallback.

Os receipts de ownership confirmam helpers 4A9/DD62 e mesmo perfil 31441. A alteração de consulta está apenas na candidata privada; o helper anterior, fontes concorrentes e saves permanecem preservados. Nenhum port novo de gameplay ocorreu neste lote; a correção anterior de retenção do collector é observacional e não uma solução da pausa.

## Encerramento do lote e pendências

Dois jogos válidos concluídos, ambos sem o alvo ≥250 ms. A rec3 manteve a carga/local pertinentes perto dos horários históricos, mas uma rodada sem reprodução continua inconclusiva. O lote termina sem outra captura, intervenção em input/Bluetooth/drivers, CLR ou WPR implícitos. A pausa de 1,7 s não está resolvida.

A análise nativa final deve manter a cobertura comum retida, LastDroppedTimes, perdas, continuidade e símbolos; Running/Ready/Waiting/Unknown só são atribuídos por essa evidência. A família menor de cauda da rec2 tinha outro local/carga e gap antes dos callbacks; seu desaparecimento na rec3 não prova correção pelo helper. Os draws iniciais/evento e processamento de criação continuam assinaturas separadas. Qualquer próximo experimento exige hipótese nova apoiada pela atribuição nativa, sem terceira repetição equivalente deste lote.
