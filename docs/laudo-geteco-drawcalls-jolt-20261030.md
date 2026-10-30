**Laudo final — Geteco / Harbor: draw calls, sombras, câmera, reveal e experimento Jolt. Encerrado em 30/10/2026, UTC−03:00.**

O trabalho foi encerrado a pedido do usuário. A coleta própria parou; não haverá continuação automática, novos testes ou aplicação das propostas restantes. Os arquivos e resultados foram preservados. A meta original de reduzir os draw calls do Harbor em 70–80%, sem novas travadas, **não foi alcançada nem demonstrada**. Nenhuma otimização experimental foi promovida a padrão e o motor físico padrão continua GodotPhysics3D.

Há resultados úteis e verificáveis: o A/B release do Jolt terminou com 36 sessões; as fases 1–3 têm código aplicado e validação funcional, mas sua matriz release terminou parcial, em 74 de 108 sessões; a fase 4, que poderia atacar uma parcela maior das fachadas, ficou somente em propostas. Este laudo distingue implementação, medição, aprovação e proposta. Não conta arquivos preparados como melhoria entregue ao jogo.

**1. Estado da entrega e resposta direta ao objetivo**

| Frente | O que existe ao encerrar | Situação de aceite / padrão |
|---|---|---|
| Fase 0 — baseline | 18 sessões release, antes das otimizações | Completa para as métricas que a bancada antiga gravava; faltam contadores por viewport durante toda a janela |
| Fase 1 — proxy de sombra | Implementado para três perfis de sedã, com recuperação dos casters em ações incompatíveis | OFF; ganho menor que o objetivo e caudas piores no contraste N=3 do porto |
| Fase 2 — duas cascatas | Interruptor existente medido | Quatro cascatas continuam padrão; resultado parcial e revisão visual incompleta |
| Fase 2 — far da câmera | Alcance exterior protegido geometricamente, flag fixa e opção experimental ligada à preferência | OFF; medido parcialmente o candidato 120 m, não a modalidade settings |
| Fase 3 — reveal guard | Implementado, proteção depende do estado real do reveal | OFF; censo mostrou ganho pequeno, matriz parcial e limite de reativação tardia |
| Fase 4 — fachadas Texture2DArray | Projeto de implementação, patches, harness e contratos offline | NÃO aplicada; assets não gerados/importados; nenhum ganho medido |
| Fase 5 — Jolt | 36/36 sessões release, testes funcionais e diagnóstico de esmagamento | Experimento concluído; migração não aprovada; GodotPhysics3D preservado |
| Commits | Alterações e evidências no checkout | Nenhum commit desta tarefa; não houve troca de motor em project.godot |

O conjunto das quatro opções gráficas apresentou redução descritiva de draws globais entre **10,47% e 18,99%**, conforme cenário, nas duas rodadas completas. No porto com estresse foram **15,21%**; no porto calmo, **18,99%**. Esses números não são aceite: há N=2, pioras de cauda em alguns casos e lacunas visuais. Mesmo a maior redução observada fica 51,01 a 61,01 pontos percentuais abaixo da meta de 70–80%. As reduções isoladas não podem ser somadas, porque atingem trabalho sobreposto.

**2. O que foi encerrado e o que foi preservado**

O controlador próprio da matriz e o executável da pasta exclusiva ab-phases123 foram identificados e encerrados. O jogo aceitou fechamento da janela e saiu em até cinco segundos. Os processos da outra sessão foram preservados. A fila registra o fim da execução interrompida às 08:16:14; ela não entra nas estatísticas nem é classificada como travada espontânea do jogo.

São **74 resultados completos, uma execução interrompida e 33 não iniciadas**. As duas primeiras rodadas completas fornecem 72 resultados: seis braços × três rotas × duas cargas × duas rodadas. Os dois resultados adicionais completam somente o contraste OFF/PROXY de porto/estresse com N=3. Não apresento a matriz inteira como N=3.

A parada do controlador impediu seu bloco final de conferência. Foi feita uma conferência offline independente, uma única vez: **199/199 inputs e inventário correspondentes, 74/74 relatórios e 74/74 logs com hashes coincidentes, zero divergências**. Isso preserva a confiabilidade documental do conjunto completo disponível, sem transformar a matriz incompleta em aceita. [Recibo de encerramento](D:/geteco/game/artifacts/codex-drawcalls/encerramento-20261030/stop-receipt.md).

**3. Ambiente, método e limites de interpretação**

As medições release usaram Godot 4.7.2 .NET, GDScript e C# efetivamente carregado, Forward+/Vulkan, i7-13650HX, RTX 4060 Laptop, resolução 3440×1440, VSync e limite de FPS desligados. A instalação .NET e o payload C# foram conferidos. As execuções passaram pela fila única do Godot. Exports e saves de teste ficaram na pasta exclusiva da tarefa; builds/jogar não foi usado.

O A/B Jolt usa o mesmo EXE, PCK e payload .NET, alterando o override do motor físico. A matriz gráfica usa o mesmo pacote instrumentado com GodotPhysics3D, alterando os interruptores. **Não foi medida a combinação Jolt + otimizações gráficas ligadas**; não é válido somar os ganhos desses experimentos ou afirmar que suas interações foram verificadas.

Os dois conjuntos usam controle contemporâneo dentro do próprio pacote. A baseline anterior e os cinco checkpoints de 29/10 não foram misturados aos controles de 30/10. Há desenvolvimento concorrente autorizado: a fila evita dois Godots simultâneos, mas não garante máquina exclusiva, estabilidade térmica ou ausência de outros processos. Diferenças pequenas não são prova causal.

- FPS agregado = quantidade de intervalos × 1000 / soma dos intervalos em ms. Não é média de FPS instantâneo nem 1000 dividido pelo p50.
- p50, p95, p99 e máximo vêm dos intervalos brutos agrupados de process_frame. A série de frame_post_draw é separada; nenhuma das duas equivale a medição de apresentação física no monitor.
- Draws, objetos e tempos de monitor nas tabelas são medianas das médias de cada rodada. O relatório completo preserva faixas e deltas pareados.
- Draws globais abrangem outras viewports; visível e sombra referem-se à viewport principal. Por isso visível + sombra não precisa igualar o global.
- O monitor de física repete o máximo de um intervalo publicado aproximadamente por segundo. Não mede cada passo nem somente o solver. CPU de render, GPU e física não devem ser somadas como fases sequenciais.
- Contagens >33 e >100 são estritas, calculadas a partir dos frames brutos. A bancada antiga também possuía um campo legado >33,3; ele não foi confundido com >33,0.
- Máximos e outliers foram preservados. A regra conservadora de manter OFF diante de piora impede uma promoção sem evidência; não demonstra, sozinha, que a flag causou a piora.

**4. Jolt: foi usado, medido e comparado em release**

O prompt original pedia explicitamente o experimento Jolt na fase 5 e também dizia para não mudar o padrão sem aprovação. O experimento foi finalmente realizado com o backend concreto confirmado, não somente com uma configuração escrita. Foram **36/36 sessões válidas**, três rodadas por motor, em porto/oeste/sobrados, com e sem estresse. A última sessão terminou às 03:28:42 e o runner concluiu às 03:28:54 de 30/10, exit 0 e conferência final de identidade.

Na tabela, cada seta significa GodotPhysics3D → Jolt; tempos em ms.

| Cenário | FPS | Variação | Física, monitor | p99 | Máximo | Frames >100 |
|---|---:|---:|---:|---:|---:|---:|
| Porto / estresse | 78,54 → 85,53 | +8,90% | 8,32 → 7,81 | 26,94 → 21,06 | 107,97 → 86,09 | 1 → 0 |
| Oeste / estresse | 79,53 → 79,35 | −0,23% | 7,00 → 7,82 | 19,56 → 20,22 | 1029,52 → 119,14 | 2 → 1 |
| Sobrados / estresse | 94,95 → 100,50 | +5,84% | 7,05 → 7,00 | 20,61 → 20,13 | 51,49 → 47,03 | 0 → 0 |
| Porto / calmo | 133,55 → 135,52 | +1,47% | 4,35 → 4,28 | 12,65 → 12,04 | 26,98 → 20,59 | 0 → 0 |
| Oeste / calmo | 128,07 → 131,16 | +2,42% | 4,59 → 4,14 | 13,54 → 12,54 | 130,50 → 23,48 | 1 → 0 |
| Sobrados / calmo | 150,92 → 150,29 | −0,41% | 4,89 → 4,64 | 13,81 → 13,82 | 54,00 → 36,53 | 0 → 0 |

O melhor resultado de FPS foi no porto sob estresse. Oeste sob estresse ficou praticamente igual em FPS e pior no p99 e no monitor de física. Sobrados calmos ficaram praticamente iguais. Mesmo onde o agregado melhora, há pares individuais piores; a amostra pequena e a máquina compartilhada limitam a inferência. Jolt não resolve por si só materiais, superfícies ou draw calls.

Ser mais novo não elimina diferenças de comportamento físico nem torna a migração automaticamente correta neste projeto. O impedimento concreto para recomendar sua adoção agora é a combinação de ganho não uniforme, falhas funcionais ainda abertas e uma diferença reproduzida no esmagamento. [Relatório Jolt](D:/geteco/game/artifacts/codex-drawcalls/jolt-release-20261030.md) e [métricas completas](D:/geteco/game/artifacts/codex-drawcalls/matrix-evaluator/jolt_20261030_v1.md).

**5. Jolt: testes de comportamento e diferença reproduzida**

Os testes funcionais usaram host editor .NET com o mesmo pacote e DLL ExportRelease. São evidência de comportamento, não medição de FPS do executável release. As assertions originais foram preservadas.

| Teste | GodotPhysics3D | Jolt | Interpretação |
|---|---:|---:|---|
| native_driving | ENTRY PASS | ENTRY PASS | Jolt contém oito erros de engine; PASS não significa log limpo |
| body_ragdoll | 2 falhas / 66 checks | 3 / 66 | Uma diferença adicional na assertion de parede, causa não comprovada |
| vehicle_contact_release | 4 / 36 | 4 / 36 | Mesmas quatro mensagens |
| heavy_impacts | 22 / 80 | 23 / 80 | Diferença adicional na passagem sobre carro esmagado |
| handbrake_never_accelerates | 0 / 3360 | 0 / 3360 | Nenhuma diferença de assertions neste escopo |

As 28 falhas de assertions do controle também aparecem no Jolt, que acrescenta duas. Isso não prova que as 28 já existiam antes da tarefa: o controle aqui é o pacote instrumentado com flags OFF. Parte do diagnóstico aponta fixtures incompatíveis com contratos atuais — tanque sem arquétipo esperado, limpa-neves excluído do contrato pesado, fallback de contatos e janelas menores que o tempo de recuperação. Algumas falhas de postura continuam sem causa demonstrada. Não foram apagadas nem reclassificadas como aprovação.

No diagnóstico final **Crush V2**, as assinaturas iniciais eram idênticas e a integridade estava preservada. Godot passou 8/8 checks, sem ERROR; Jolt passou 7/8, com a única ERROR sendo a assertion original de passagem física. O carro Godot terminou em Z≈−47,706 m e atingiu Y≈0,477 m; o carro Jolt ficou em Z≈−3,648 m, praticamente sem subir, embora a velocidade lógica permanecesse em 25 m/s.

O ponto de divergência observado é concreto: no mesmo casco convexo de oito pontos, a normal de contato correspondia a aproximadamente 21,79° com Godot e 48,67° com Jolt; o limite de piso é 45°. O caminho Godot subiu cerca de 5,19 cm nesse movimento. No Jolt, o contato foi tratado também como parede e a velocidade planar Z ficou zero. A rotina posterior restaurou a velocidade lógica sem produzir avanço. A parada persistiu por 106 passos adicionais dentre 115 observados.

A repetição V1→V2 preservou exatamente os demais valores de 920 registros por execução, excluindo somente timestamp e identificador de instância da comparação. Isso sustenta uma diferença reproduzida entre o projeto e os backends. **Não identifica um bug interno específico do Jolt** nem demonstra que a única solução é trocar o motor. [Diagnóstico Crush V2](D:/geteco/game/artifacts/codex-drawcalls/jolt-crush-v2-findings.md).

O diagnóstico de parede V1 não permite a mesma conclusão: as 11 partes do ragdoll já começavam deslocadas aproximadamente 4,86 cm em Z entre os motores. O pareamento foi rejeitado. A assertion observava Z e não distinguia atravessar a parede de passar por cima. Não houve nova execução da parede. Além disso, parâmetros de juntas usados pelo projeto são avisados como não suportados/ignorados no Jolt. É uma diferença real de configuração efetiva, mas não prova isolada da causa do caso da parede.

O teste de direção Jolt também registrou erros de RID/material, com primeiro backtrace em construção de fachada, e vazamentos na saída; não há evidência suficiente para atribuí-los ao solver. Os quatro DriveCold adicionais completaram 30 s por caso, sem frames >100 ms, mas tiveram quedas/recuperações e trajetórias diferentes. Não demonstram condução contínua sem problemas e não entram na matriz aquecida.

**6. Fases 1–3: resultado parcial das mudanças gráficas**

A coorte comum de 72 sessões tem N=2 por braço/cenário. As 74 completas somam **593.735 intervalos e 90,262 minutos medidos**, com **271 intervalos >33 ms e três >100 ms**. Isso é duração da janela medida, não duração total dos processos.

O efeito varia conforme a rota. Na tabela seguinte, cada célula mostra redução/aumento dos draws globais e variação do FPS, nessa ordem, comparados ao OFF do mesmo cenário. Valores negativos de draws são redução; positivos de FPS são melhora. Todos permanecem diagnósticos, sem aceite N=3 completo.

| Variante | Porto estresse | Oeste estresse | Sobrados estresse | Porto calmo | Oeste calmo | Sobrados calmo |
|---|---|---|---|---|---|---|
| Proxy | −0,97% / +4,81% | −4,64% / −4,54% | −3,47% / +3,77% | +1,51% / +3,94% | +2,30% / +3,71% | −4,40% / −0,40% |
| Duas cascatas | −10,09% / +4,76% | −10,56% / −1,58% | −8,73% / −3,74% | −10,47% / +1,96% | −11,28% / +8,88% | −13,06% / −0,22% |
| Far 120 | −11,23% / +8,50% | −6,06% / −2,67% | −3,01% / −1,73% | −5,22% / +5,80% | −0,89% / +3,99% | −7,60% / −8,56% |
| Reveal guard | −5,13% / +8,63% | −3,73% / −6,12% | −1,48% / −12,67% | +1,65% / +8,27% | +2,25% / +1,12% | −1,37% / +0,48% |
| Combinado | −15,21% / +9,43% | −12,63% / −6,62% | −10,47% / −6,35% | −18,99% / +6,66% | −13,82% / +4,99% | −18,07% / −0,76% |

A redução de draws é mais consistente em duas cascatas e no combinado; isso não se converte em ganho consistente de FPS. A presença de outros custos e a variação entre execuções impedem atribuir todas as mudanças de FPS à CPU de render. Por exemplo, o combinado reduz draws em oeste/estresse e sobrados/estresse, mas esses agregados têm FPS menor. Reveal em sobrados/estresse teve −12,67% de FPS; far120 em sobrados/calmo, −8,56%. Esses resultados são preservados, sem escolher somente os cenários favoráveis.

Para o porto sob estresse, o detalhamento N=2 mostra a distância entre menos draws e ausência de travadas:

| Variante | Global | Visível / sombra | Render CPU / GPU ms | p50 / p95 / p99 ms | Máx ms | >33 / >100 |
|---|---:|---:|---:|---:|---:|---:|
| OFF | 1373,42 | 351,49 / 777,92 | 1,535 / 6,340 | 12,050 / 17,048 / 20,513 | 57,022 | 12 / 0 |
| Proxy | 1360,15 | 353,17 / 774,34 | 1,520 / 6,375 | 11,393 / 16,976 / 19,455 | 921,599 | 10 / 1 |
| Duas cascatas | 1234,83 | 348,85 / 655,28 | 1,480 / 6,510 | 11,548 / 16,862 / 21,330 | 75,746 | 19 / 0 |
| Far 120 | 1219,22 | 337,56 / 651,46 | 1,425 / 6,330 | 11,294 / 16,154 / 18,970 | 64,412 | 8 / 0 |
| Reveal | 1303,02 | 332,16 / 756,30 | 1,495 / 6,340 | 11,200 / 16,168 / 18,787 | 63,816 | 7 / 0 |
| Combinado | 1164,47 | 346,60 / 592,83 | 1,435 / 6,525 | 11,283 / 15,762 / 18,434 | 75,532 | 8 / 0 |

O contraste específico **porto/estresse OFF versus PROXY tem N=3**, incluindo as duas sessões adicionais. Nele, draws globais passaram de 1372,95 para 1362,86 (−0,735%); sombras de 791,14 para 775,25 (−2,008%); FPS de 83,198 para 87,197 (+4,806%); p99 de 25,718 para 21,111 ms. Entretanto, o máximo passou de **61,745 para 921,599 ms** e frames >100 de **zero para dois**. Isso impede ativar a flag segundo o critério pedido, mesmo com melhoria no FPS e no p99 agregados.

Os três picos >100 da matriz gráfica foram 921,599 ms em proxy/porto/estresse/rodada 1; 196,791 ms em combinado/oeste/calmo/rodada 2; e 120,737 ms em proxy/porto/estresse/rodada 3. Sua presença está confirmada nos frames brutos. Sua causa **não foi determinada**. O analisador de spans existente recusou esse manifesto por ausência de export_dir; não foi adaptado nem repetido depois do encerramento. Não atribuo os picos automaticamente ao proxy, à outra sessão, ao Jolt ou a compilação de shader. A matriz gráfica usou GodotPhysics3D.

[Análise completa das 74 sessões, com objetos, física, faixas e pares](D:/geteco/game/artifacts/codex-drawcalls/encerramento-20261030/partial-analysis.md) e [JSON integral](D:/geteco/game/artifacts/codex-drawcalls/encerramento-20261030/partial-analysis.json).

**7. O que mudou no código e por que o ganho ficou aquém da expectativa**

**Proxy de veículos.** A implementação cobre Body intacto de Aurora, Union e Classic, com casco simples de 84 triângulos/252 vértices, SHADOWS_ONLY e GI desligado, sem loop novo por frame. Não substitui indiscriminadamente toda a frota: rodas/acabamentos mantêm casters e outros perfis usam o caminho original. Porta, tuning, dano e fade restauram os casters originais de forma síncrona; a reinstalação após reparo depende da elegibilidade. Classic com portas já preparadas permanece inelegível à reinstalação. Os formatos foram incluídos no prewarm local e retidos. Os faróis e o arquivo VehicleEquipment ocupado ficaram fora da alteração.

A premissa de 55 malhas do Aurora no prompt já não representava a frota encontrada: o censo atual mostrou **sete meshes e 28 superfícies, das quais 14 no Body**. Portanto a expectativa de cortar 30–55 draws de sombra por carro, baseada na composição anterior, não pode ser transferida diretamente. O proxy implementado preserva partes dinâmicas e cobre três perfis; a meta de −600 a −1200 draws em perseguição não foi comprovada. Fundir peças da frota permaneceu fora do escopo, apenas com plano escrito.

**Câmera e cascatas.** A opção far120 calcula um limite protegido a partir da pose real, projeção ortográfica, recuo/roll e plano de chão com margem. Por isso o far efetivo não fica cegamente em 120 m. A modalidade settings liga a preferência de distância a essa lógica, mas ficou experimental e fora da matriz do candidato fixo. Reflexões preservam o alcance anterior. Duas cascatas usam o interruptor existente, enquanto o padrão continua quatro.

**Reveal.** A proteção agora consulta o estado real do reveal e usa geração/WeakRef, mantendo proteção para objetos interativos/diagnósticos. O censo de quatro chunks passou de **732 para 731 superfícies** e de **458 para 457 superfícies de sombra**; apenas o trecho (1,1) mudou. Esse ganho estático pequeno é evidência contra a hipótese de grande economia apenas removendo essa exclusão. Não se deve atribuir os vários pontos percentuais de variação da bancada exclusivamente a uma superfície. Há um limite conhecido: o rollback cobre trabalho em andamento; não restaura automaticamente lotes já publicados se alguém ligar reveal arbitrariamente depois. O caminho atual do jogo não faz essa ativação tardia, mas a limitação permanece.

**Correções de apoio.** A linha de HarborRoadWear com inferência de center recebeu tipo Vector2 explícito, após sua autorização, corrigindo o erro de compilação observado. Foram ajustadas cinco traduções e o tempo do fixture de lifecycle de quatro para oito segundos, porque a aproximação autorada medida pode levar de 4,04 a 7,09 s; as assertions não foram afrouxadas. O benchmark ganhou contadores e verificações de identidade necessários ao A/B. O patch de PaintedFacadePrewarm autorizado para a fase 4 **não foi aplicado**; suas alterações alheias existentes foram preservadas.

**8. Validação funcional das fases 1–3 e limites visuais**

A suíte central full inicial teve 25/27 processos aprovados. Após as correções de apoio, a suíte full de 30/10 terminou **27/27 PASS**, exit 0, com C# compilado antes. Os 16 testes de área registrados também terminaram com exit 0. Testes dirigidos contabilizaram 92 checks do proxy, 480 da profundidade e 46 do guard; são verificações dentro de processos, não centenas de partidas. A checagem frame-rules terminou exit 0 com contagens de referência preservadas. [Suíte central final](D:/geteco/game/evidence/test-suite/core/20261030-041837/RESUMO.md).

Isso não significa que todos os testes Jolt passaram, nem que toda a apresentação visual está aprovada. As evidências visuais têm coberturas distintas:

| Evidência | O que foi observado | O que não comprova |
|---|---|---|
| Proxy temporal | Quatro sequências dia/noite × OFF/ON, aproximadamente 52 s cada, pelo menos 30 s intactos, depois porta/dano/reparo; zero falhas de fluxo/omissões de escrita | Não é benchmark release nem certificação de toda a frota |
| Proxy, regiões de imagem | 3.587 JPEGs decodificados; nove regiões estáticas; 32 mudanças persistentes compatíveis com ações inspecionadas; zero candidatos de pulso nas regiões cobertas | Cerca de 20 s do arco de câmera intacto ficaram fora da análise pixel a pixel; detector não é calibrado perceptualmente |
| Oclusão V3 OFF/ON | 78/78 checks por variante; 1.921 frames de movimento em cada; 104 posições cobertas sem vazamento, 505 abertas sem escurecimento indevido | Posições intermediárias não têm todas a mesma assertion extrema; dez instâncias ObjectDB vazadas na saída por variante |
| Câmera e chuva | 12 sequências de aproximadamente 30 s em oeste/prédio alto/ponte/chuva; 9.189 frames; far numericamente protegeu o chão | Revisão visual final parcial; 38 candidatos inconclusivos; nenhum playback contínuo integral comprovado |

No proxy, foram vistas diferenças de contorno/comprimento da sombra; a lateral do Union perde faixas finas e passa a uma sombra contínua. Isso é compatível com um casco simplificado, mas não equivale a identidade visual. A proteção principal contra luz permaneceu no teste. À noite, somente Aurora emitia os dois faróis; Union e Classic funcionavam como receptores/oclusores. O farol Aurora apagou após dano e continuou apagado após reparo nos dois braços, portanto esse evento não foi exclusivo do proxy.

Na câmera, o far efetivo variou de 120 a 153,955 m no oeste; ficou em 120 m no prédio alto; foi de 136,899 a 159,557 m na ponte; e de 120 a 150,062 m com chuva. Não houve chão numericamente além do far nas capturas. Entretanto, em ponte/far120 não houve pares A/B aceitos entre 20 e 27 s; o maior intervalo sem par foi 8,899 s. A posição em um ponto diferia 0,222 m, acima da tolerância de 0,15 m, que não foi relaxada. Há lacunas de captura de até 407 ms na sequência chuva/duas cascatas.

As regiões estáticas úteis de câmera cobrem apenas aproximadamente 3,9–4,9 s; os 38 candidatos continuam inconclusivos, não defeitos confirmados nem falsos positivos provados. Uma máscara inicial de parapeito atingia água; os sinais correspondentes foram invalidados para aquele propósito e a máscara foi corrigida sem mudar limiares. A chuva tinha piso molhado, mas **zero receptores de reflexo de fachada** no local escolhido: esse aspecto ficou N/A, não aprovado.

[Revisão proxy](D:/geteco/game/artifacts/codex-drawcalls/proxy-review-20261030-v1/README.md) e [revisão câmera](D:/geteco/game/artifacts/codex-drawcalls/camera-review-20261030-v1/REVIEW.md) preservam as limitações. Não declaro ausência global de flicker com base em screenshots, regiões parciais ou testes headless.

**9. O que os logs de travada do Jolt realmente indicaram**

A análise documental dos 36 logs Jolt/Godot encontrou correspondência única das sessões, sem problemas de mapeamento. As associações abaixo são por proximidade de duração e contexto; o logger não fornece correspondência exata entre o frame bruto medido e o evento de sessão. Os números de eventos >100 no log e na janela medida não são intercambiáveis.

- No controle Godot, oeste/estresse, houve pico medido de 1029,523 ms. Um evento próximo contém incremento de pipeline/especialização e CPU da viewport de 986,59 ms na sondagem seguinte, com GPU próxima de 6–7 ms e oito passos físicos. É indício de trabalho longo no lado CPU naquele contexto, não prova de causa no backend físico.
- No Jolt, oeste/estresse, o pico medido de 119,136 ms tem evento próximo com construção de ragdoll de 102,982 ms, contida em spans maiores de pessoas/pré-física/veículo. Esses spans são inclusivos: não devem ser somados. O delta de pipeline era zero e houve um passo físico. O rastro localiza construção de ragdoll, sem isolar custo interno do solver.
- No controle Godot, oeste/calmo, o pico de 130,495 ms permaneceu sem causa explicada pelos spans disponíveis.
- Em porto/estresse, ambos os motores apresentaram trabalho de decoração Harbor perto de máximos, aproximadamente 41,6–55,8 ms. Há trabalho de criação/montagem a investigar independentemente da escolha do backend.

Esses achados sugerem frentes específicas para eventual trabalho futuro, mas não justificam afirmar que todos os engasgos são de física ou que reduzir draws os elimina. [Travadas Jolt](D:/geteco/game/artifacts/codex-drawcalls/jolt-stalls-20261030-v1/findings.md).

**10. Fase 4: proposta preparada, nenhuma economia entregue**

A proposta de fachadas prevê 26 estilos/60 materiais distribuídos em seis páginas Texture2DArray, dimensões exatas de 768×384, 1024×512 e 2048×384, BC7 com mipmaps e estimativa de 63,17 MiB. Usa camada em UV2, máscara de emissão, uniform global de noite, carga em thread sob cortina e retenção de recursos. A estimativa estática de 60 superfícies para 28 lotes por proprietário não é um número de draw calls medido e não demonstra a meta de −80–90% dos prédios pintados.

O plano de células mantém portas e recortes, filtra materiais conhecidos, conserva o caminho original para fontes protegidas/desconhecidas e libera o lote antes de acesso/unload. Define limites de fontes, proprietários e vértices, com orçamento de aproximadamente 2 ms ainda **não medido**. Os originais seriam retidos; ocultação de RID não deve ser confundida com Node.visible. Uma revisão adicional separa fontes montadas de chunks aposentados/cacheados para evitar falso positivo de ativação.

Existem patches de compatibilidade/lifecycle/prewarm, testes propostos, runner de três braços e avaliador separado, com 18 contratos de runner e 19 testes offline aprovados na validação final. São fixtures de infraestrutura, não execuções do jogo. A matriz futura de 54 sessões **não foi iniciada**. Não foram gerados/importados os assets, integrado o shader, aplicado o prewarm autorizado ou demonstrados acesso/streaming/reflexos/performance na cena real. O trabalho para nesta condição. [Pacote de staging](D:/geteco/game/artifacts/codex-drawcalls/staging-facade/README.md).

**11. Por que demorou e quanto foi realmente coletado**

Há **137 execuções de benchmark completas** em cinco conjuntos distintos, além da execução final interrompida. Não são 137 repetições do mesmo teste e não podem ser juntadas num único A/B.

| Conjunto | Sessões completas | Intervalo local documentado | Tempo de relógio |
|---|---:|---|---:|
| Baseline | 18 | 29/10 20:55:49–21:37:23 | 41 min 34 s |
| Checkpoint de ativação | 5 | 29/10 22:04:07–22:31:07 | 27 min 01 s |
| DriveCold | 4 | 30/10 00:00:43–00:06:28 | 5 min 45 s |
| Jolt/Godot | 36 | 30/10 00:07:12–03:28:42 | 3 h 21 min 30 s |
| Fases 1–3, parcial | 74 | 30/10 04:34:10–08:14:59 | 3 h 40 min 49 s |

Os intervalos desses cinco conjuntos somam **8 h 16 min 39 s**, incluindo inicialização, aquecimento, encerramento e espera. Entre o início da baseline e o último resultado completo passaram **11 h 19 min 10 s**; a tarefa já estava em andamento antes disso. Não é correto chamar tudo isso de tempo útil medindo FPS.

Na matriz parcial, o cruzamento exato das 74 entradas com a fila separou 48 min 39 s antes do lançamento, 2 h 50 min 55 s dentro dos próprios processos e cerca de 70 s de retorno/acabamento. Dos 48 min 39 s, **39 min 13 s** coincidem com 54 outros jobs ocupando a fila. Os 9 min 26 s restantes não podem ser separados precisamente entre shell, consulta e espera. Os comandos não identificam, por si só, o autor de cada job; não atribuo todos automaticamente à outra sessão, nem uso a espera como explicação causal dos picos.

O prompt exigia pelo menos três rodadas por rota e carga: cada braço custa 18 sessões. Jolt/Godot exige 36. Para quatro mudanças gráficas isoladas com controle compartilhado, seriam 90 sessões. **Eu acrescentei o braço combinado, mais 18 previstas, levando a 108; 12 dessas extras chegaram a terminar.** Também acrescentei checkpoint, DriveCold, sondas e infraestrutura de revisão temporal. Havia motivo técnico para algumas dessas verificações, mas o número, o encadeamento e o investimento em tooling foram decisões minhas.

Houve ainda retrabalho: erro de compilação em arquivo ocupado, export cujo processo não encerrou apesar do pacote salvo, problemas de parser/runner, caminhos e encerramento de harness de captura e erro do próprio diagnóstico V1. Alguns exigiram nova tentativa para obter evidência válida. A documentação preserva essas tentativas em vez de ocultá-las.

Os três agentes ajudaram em implementação, revisão e análise, mas não podiam acelerar o motor executando três instâncias simultâneas: a fila única e a RAM limitada eram restrições reais. Ainda assim, **a demora não se explica somente pela fila nem pelas exigências do usuário**. Eu ampliei a investigação e preparei a fase 4 antes de converter as conclusões já disponíveis em uma decisão clara. Isso aumentou o tempo sem concluir o objetivo principal. A comunicação também deveria ter destacado mais cedo o ganho limitado e a ausência de condições para ativar os experimentos.

[Cronologia auditada e distinção entre execuções/assertions](D:/geteco/game/artifacts/codex-drawcalls/encerramento-20261030/timeline-and-scope.md).

**12. Pendências reais, sem execução automática**

O trabalho foi encerrado. Os itens abaixo são recomendações para uma decisão futura, não um plano em execução:

1. Antes de migrar para Jolt, resolver/adaptar o contato do esmagamento, os parâmetros de juntas ignorados e as falhas funcionais com fixtures válidas. O caso de parede exige pareamento inicial correto antes de qualquer conclusão sobre atravessamento.
2. Antes de ligar proxy/câmera/reveal, completar somente o recorte de evidência necessário para a opção escolhida, investigar as caudas e fechar as lacunas visuais. Não há justificativa para ativação automática com os resultados atuais.
3. Para buscar redução de 70–80%, reavaliar a composição atual da cena/frota antes de usar estimativas antigas. A fase 4 precisa de integração real e medição; a fusão da frota continua fora do escopo original e deve ser trabalho separado se autorizada.
4. Para travadas, priorizar os pontos concretos registrados — construção de ragdoll, decoração/streaming e possível trabalho de pipeline — em vez de pressupor que o número de draws ou o backend físico explica tudo.
5. As alterações permanecem sem commit, junto ao trabalho concorrente. Qualquer futura organização em commits precisa separar os arquivos/hunks da tarefa, especialmente a correção autorizada em HarborRoadWear e o prewarm alheio preservado; nunca descartar o checkout para tentar obter uma base limpa.

**13. Evidências e identidade preservadas**

- [Relatório histórico com estado final atualizado](D:/geteco/game/docs/perf-harbor-drawcalls-20261029.md).
- [Baseline](D:/geteco/game/artifacts/codex-drawcalls/baseline-final.md) e [checkpoint diagnóstico](D:/geteco/game/artifacts/codex-drawcalls/checkpoint-diagnostic.md).
- [Jolt, resultado consolidado](D:/geteco/game/artifacts/codex-drawcalls/jolt-release-20261030.md), [manifesto 36](D:/geteco/game/artifacts/codex-drawcalls/codex_jolt_20261030_v1_matrix-results.json) e [identidade](D:/geteco/game/artifacts/codex-drawcalls/codex_jolt_20261030_v1_matrix-identity.json).
- [Delta funcional](D:/geteco/game/artifacts/codex-drawcalls/jolt-functional-delta.md), [diagnóstico do controle](D:/geteco/game/artifacts/codex-drawcalls/jolt-functional-control-diagnosis.md), [Crush V2](D:/geteco/game/artifacts/codex-drawcalls/jolt-crush-v2-findings.md), [limites Wall V1](D:/geteco/game/artifacts/codex-drawcalls/jolt-deltas-v1-findings.md) e [DriveCold](D:/geteco/game/artifacts/codex-drawcalls/jolt-drivecold-20261030-summary.md).
- [Manifesto 74](D:/geteco/game/artifacts/codex-drawcalls/codex_draw_p123_20261030_v2-results.json), [identidade](D:/geteco/game/artifacts/codex-drawcalls/codex_draw_p123_20261030_v2-identity.json), [análise parcial](D:/geteco/game/artifacts/codex-drawcalls/encerramento-20261030/partial-analysis.md) e [JSON de todos os números/pares](D:/geteco/game/artifacts/codex-drawcalls/encerramento-20261030/partial-analysis.json).
- [Inventário de código e validação visual](D:/geteco/game/artifacts/codex-drawcalls/encerramento-20261030/code-and-visual-status.md), [cronologia](D:/geteco/game/artifacts/codex-drawcalls/encerramento-20261030/timeline-and-scope.md) e [recibo de parada](D:/geteco/game/artifacts/codex-drawcalls/encerramento-20261030/stop-receipt.md).

PCK congelado SHA-256: 8774736011dc37280025e9a33156f2b1ed6245e9f62bacb6dbb30b86c7bd6127.

DLL ExportRelease SHA-256: b7f1ab2436ae3e8620e7a6c5ac24e8ec8ca2c58b65469a1c21cbaa77a6938c41.

Config da matriz gráfica SHA-256: 9a336cec9da5ae537476199cc7a1fefcd2dd00303baf74bc2a7d3dbf8aac0378. Runner: 5cf48c3d784cf7a58b3ed147ba86490b9a0dcc360f6b8da306769f106c24d8fd.

As pastas ab-phases123, jolt-bench-godot e jolt-bench-jolt compartilham PCK por hardlink. Estão preservadas como evidência; uma futura exportação deve usar outra pasta. O comando de export instrumentado teve timeout após salvar o PCK, fato mantido no histórico. O funcionamento posterior do executável e as identidades conferidas não transformam esse comando em export com encerramento limpo.

**14. Anexos numéricos integrais**

As tabelas anexadas abaixo são copiadas dos relatórios já calculados, sem nova coleta ou alteração dos dados. O primeiro bloco é o A/B Jolt completo; o segundo é a coorte gráfica comum N=2. Para pares individuais, faixas, contraste proxy N=3 e contagens completas, use os arquivos vinculados acima.


**Anexo A — Jolt: monitores e distribuição completa dos intervalos, N=3.**

| Variante | Cenário | N | Draws global | Draws visíveis | Draws sombra | Objetos visíveis | Objetos sombra | CPU render ms | GPU ms | Física ms |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| godot | porto/stress | 3 | 1377.24 | 349.54 | 784.45 | 362.01 | 808.74 | 1.60 | 6.81 | 8.32 |
| godot | oeste/stress | 3 | 1787.75 | 472.67 | 1019.55 | 482.95 | 1040.01 | 2.02 | 6.49 | 7.00 |
| godot | sobrados/stress | 3 | 1022.46 | 310.40 | 472.02 | 314.79 | 475.55 | 1.39 | 5.98 | 7.05 |
| godot | porto/calm | 3 | 928.30 | 239.87 | 588.37 | 249.75 | 609.48 | 1.23 | 5.46 | 4.35 |
| godot | oeste/calm | 3 | 1364.33 | 372.36 | 857.09 | 378.78 | 875.54 | 1.58 | 5.02 | 4.59 |
| godot | sobrados/calm | 3 | 714.71 | 233.14 | 353.13 | 234.59 | 355.31 | 1.14 | 4.79 | 4.89 |
| jolt | porto/stress | 3 | 1405.46 | 363.85 | 792.98 | 374.03 | 810.16 | 1.59 | 6.79 | 7.81 |
| jolt | oeste/stress | 3 | 1851.29 | 501.95 | 1028.37 | 513.16 | 1052.21 | 1.90 | 6.45 | 7.82 |
| jolt | sobrados/stress | 3 | 996.74 | 305.00 | 460.11 | 308.77 | 464.17 | 1.35 | 6.01 | 7.00 |
| jolt | porto/calm | 3 | 936.39 | 248.16 | 586.20 | 259.73 | 607.98 | 1.24 | 5.38 | 4.28 |
| jolt | oeste/calm | 3 | 1312.26 | 363.09 | 813.53 | 369.40 | 832.35 | 1.54 | 5.01 | 4.14 |
| jolt | sobrados/calm | 3 | 713.97 | 233.68 | 351.88 | 235.15 | 353.35 | 1.12 | 4.80 | 4.64 |

FPS médio = total de frames / duração total em segundos; não é média de FPS instantâneo nem 1000/p50. As caudas abaixo são contagens de frames estritamente acima de cada limite em ms.

A série `frame_samples_ms` mede intervalos entre retomadas do loop em `process_frame`. `present_samples_ms`, baseada em `frame_post_draw`, é separada e não entra nesta análise; nem esse sinal garante apresentação efetiva na tela.

| Variante | Cenário | N | FPS médio | Frame médio ms | p50 ms | p95 ms | p99 ms | Máx ms | >16,7 ms | >33,0 ms | >33,3 ms | >66,7 ms | >100 ms |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| godot | porto/stress | 3 | 78.540 | 12.732 | 12.996 | 18.726 | 26.936 | 107.966 | 2715 | 44 | 39 | 2 | 1 |
| godot | oeste/stress | 3 | 79.529 | 12.574 | 13.002 | 16.911 | 19.564 | 1029.523 | 1221 | 7 | 7 | 2 | 2 |
| godot | sobrados/stress | 3 | 94.953 | 10.532 | 10.850 | 16.457 | 20.611 | 51.493 | 1158 | 20 | 20 | 0 | 0 |
| godot | porto/calm | 3 | 133.548 | 7.488 | 7.141 | 11.044 | 12.651 | 26.976 | 33 | 0 | 0 | 0 | 0 |
| godot | oeste/calm | 3 | 128.068 | 7.808 | 7.508 | 11.399 | 13.542 | 130.495 | 28 | 2 | 2 | 1 | 1 |
| godot | sobrados/calm | 3 | 150.919 | 6.626 | 5.916 | 10.334 | 13.813 | 53.997 | 92 | 5 | 5 | 0 | 0 |
| jolt | porto/stress | 3 | 85.533 | 11.691 | 12.018 | 17.375 | 21.061 | 86.091 | 1714 | 19 | 19 | 3 | 0 |
| jolt | oeste/stress | 3 | 79.347 | 12.603 | 13.029 | 17.285 | 20.217 | 119.136 | 1580 | 11 | 10 | 1 | 1 |
| jolt | sobrados/stress | 3 | 100.502 | 9.950 | 10.193 | 15.920 | 20.133 | 47.035 | 989 | 31 | 31 | 0 | 0 |
| jolt | porto/calm | 3 | 135.517 | 7.379 | 7.034 | 10.616 | 12.036 | 20.585 | 21 | 0 | 0 | 0 | 0 |
| jolt | oeste/calm | 3 | 131.164 | 7.624 | 7.443 | 10.855 | 12.544 | 23.480 | 10 | 0 | 0 | 0 | 0 |
| jolt | sobrados/calm | 3 | 150.294 | 6.654 | 5.921 | 10.267 | 13.817 | 36.533 | 94 | 3 | 3 | 0 | 0 |

**Anexo B — fases 1–3: coorte comum de 72 sessões, N=2.**

| Cenário | Braço | N | Draw global | Visível | Sombra | Objetos | Obj. sombra | CPU ms | GPU ms | Física ms | FPS | p50 | p95 | p99 | máx ms | >16,7 | >33 | >100 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| porto/stress | off | 2 | 1373.415 | 351.485 | 777.920 | 362.280 | 802.220 | 1.535 | 6.340 | 7.600 | 85.605 | 12.050 | 17.048 | 20.513 | 57.022 | 971 | 12 | 0 |
| porto/stress | proxy | 2 | 1360.145 | 353.170 | 774.335 | 360.925 | 792.375 | 1.520 | 6.375 | 7.980 | 89.722 | 11.393 | 16.976 | 19.455 | 921.599 | 949 | 10 | 1 |
| porto/stress | splits2 | 2 | 1234.830 | 348.850 | 655.280 | 358.655 | 679.420 | 1.480 | 6.510 | 7.510 | 89.676 | 11.548 | 16.862 | 21.330 | 75.746 | 873 | 19 | 0 |
| porto/stress | far120 | 2 | 1219.220 | 337.555 | 651.460 | 344.420 | 663.900 | 1.425 | 6.330 | 7.270 | 92.882 | 11.294 | 16.154 | 18.970 | 64.412 | 607 | 8 | 0 |
| porto/stress | reveal | 2 | 1303.020 | 332.155 | 756.295 | 341.175 | 776.505 | 1.495 | 6.340 | 8.640 | 92.991 | 11.200 | 16.168 | 18.787 | 63.816 | 579 | 7 | 0 |
| porto/stress | combined | 2 | 1164.465 | 346.600 | 592.830 | 354.115 | 610.495 | 1.435 | 6.525 | 7.145 | 93.674 | 11.283 | 15.762 | 18.434 | 75.532 | 429 | 8 | 0 |
| oeste/stress | off | 2 | 1879.725 | 498.570 | 1068.460 | 508.600 | 1089.745 | 1.905 | 6.190 | 7.065 | 82.254 | 12.623 | 16.584 | 18.995 | 64.720 | 681 | 5 | 0 |
| oeste/stress | proxy | 2 | 1792.475 | 491.890 | 992.655 | 502.105 | 1013.405 | 1.890 | 6.165 | 8.305 | 78.521 | 13.200 | 17.130 | 19.884 | 36.560 | 985 | 8 | 0 |
| oeste/stress | splits2 | 2 | 1681.205 | 494.495 | 867.610 | 505.065 | 888.635 | 1.860 | 6.320 | 7.115 | 80.959 | 12.893 | 16.732 | 19.003 | 44.112 | 748 | 7 | 0 |
| oeste/stress | far120 | 2 | 1765.865 | 488.695 | 964.300 | 497.715 | 984.440 | 1.885 | 6.365 | 7.625 | 80.061 | 12.976 | 17.006 | 19.899 | 35.068 | 895 | 3 | 0 |
| oeste/stress | reveal | 2 | 1809.520 | 493.480 | 992.795 | 504.125 | 1012.965 | 1.890 | 6.355 | 7.225 | 77.221 | 13.458 | 17.478 | 20.298 | 36.303 | 1229 | 5 | 0 |
| oeste/stress | combined | 2 | 1642.250 | 494.830 | 818.145 | 504.400 | 841.275 | 1.845 | 6.400 | 7.070 | 76.809 | 13.560 | 17.340 | 19.858 | 39.399 | 1175 | 6 | 0 |
| sobrados/stress | off | 2 | 1034.900 | 313.480 | 483.140 | 317.365 | 486.885 | 1.360 | 5.735 | 7.445 | 99.327 | 10.328 | 15.846 | 20.125 | 42.439 | 619 | 10 | 0 |
| sobrados/stress | proxy | 2 | 998.950 | 312.330 | 450.165 | 316.240 | 453.980 | 1.325 | 5.715 | 6.970 | 103.071 | 9.890 | 15.449 | 19.545 | 42.058 | 559 | 11 | 0 |
| sobrados/stress | splits2 | 2 | 944.535 | 313.160 | 386.620 | 317.255 | 390.520 | 1.295 | 5.920 | 7.045 | 95.613 | 10.737 | 16.378 | 20.789 | 47.876 | 765 | 21 | 0 |
| sobrados/stress | far120 | 2 | 1003.700 | 313.290 | 446.775 | 317.320 | 451.020 | 1.330 | 6.060 | 7.125 | 97.612 | 10.569 | 15.990 | 20.213 | 41.740 | 656 | 16 | 0 |
| sobrados/stress | reveal | 2 | 1019.620 | 307.350 | 463.530 | 311.415 | 467.420 | 1.390 | 6.110 | 7.505 | 86.742 | 11.717 | 17.676 | 24.005 | 57.334 | 1169 | 35 | 0 |
| sobrados/stress | combined | 2 | 926.500 | 314.410 | 362.970 | 318.225 | 367.190 | 1.320 | 5.935 | 7.125 | 93.023 | 11.063 | 16.485 | 20.647 | 43.696 | 754 | 14 | 0 |
| porto/calm | off | 2 | 916.385 | 238.680 | 578.320 | 248.220 | 599.700 | 1.220 | 5.220 | 4.615 | 134.127 | 7.015 | 11.405 | 14.464 | 30.596 | 40 | 0 | 0 |
| porto/calm | proxy | 2 | 930.200 | 243.320 | 587.255 | 253.145 | 609.730 | 1.200 | 5.225 | 4.410 | 139.411 | 6.673 | 10.542 | 11.930 | 29.961 | 14 | 0 | 0 |
| porto/calm | splits2 | 2 | 820.420 | 245.345 | 475.380 | 255.250 | 501.015 | 1.145 | 5.210 | 4.765 | 136.762 | 6.815 | 10.825 | 12.460 | 20.187 | 17 | 0 | 0 |
| porto/calm | far120 | 2 | 868.545 | 244.970 | 523.420 | 252.290 | 537.920 | 1.140 | 5.205 | 4.325 | 141.905 | 6.545 | 10.244 | 11.832 | 20.415 | 10 | 0 | 0 |
| porto/calm | reveal | 2 | 931.470 | 241.910 | 589.670 | 251.785 | 611.710 | 1.160 | 5.000 | 4.240 | 145.220 | 6.398 | 9.942 | 11.263 | 18.575 | 6 | 0 | 0 |
| porto/calm | combined | 2 | 742.330 | 245.735 | 396.625 | 252.955 | 415.485 | 1.075 | 4.980 | 4.460 | 143.057 | 6.420 | 10.497 | 12.524 | 27.887 | 13 | 0 | 0 |
| oeste/calm | off | 2 | 1326.850 | 364.750 | 827.150 | 371.240 | 844.905 | 1.510 | 4.725 | 4.195 | 132.018 | 7.338 | 11.198 | 13.646 | 19.999 | 19 | 0 | 0 |
| oeste/calm | proxy | 2 | 1357.440 | 373.855 | 848.705 | 381.260 | 866.850 | 1.465 | 4.760 | 4.050 | 136.915 | 6.985 | 10.463 | 12.172 | 18.297 | 2 | 0 | 0 |
| oeste/calm | splits2 | 2 | 1177.205 | 362.210 | 680.075 | 368.880 | 699.440 | 1.360 | 4.720 | 4.010 | 143.741 | 6.533 | 10.130 | 11.711 | 19.092 | 7 | 0 | 0 |
| oeste/calm | far120 | 2 | 1314.990 | 380.320 | 799.725 | 386.285 | 818.745 | 1.450 | 4.745 | 4.030 | 137.290 | 6.961 | 10.559 | 12.312 | 19.035 | 8 | 0 | 0 |
| oeste/calm | reveal | 2 | 1356.645 | 371.870 | 849.905 | 377.745 | 869.080 | 1.490 | 4.755 | 4.260 | 133.492 | 7.198 | 10.645 | 12.624 | 26.269 | 15 | 0 | 0 |
| oeste/calm | combined | 2 | 1143.515 | 374.295 | 634.315 | 378.415 | 652.340 | 1.380 | 4.930 | 4.095 | 138.606 | 6.852 | 10.365 | 12.532 | 196.791 | 12 | 1 | 1 |
| sobrados/calm | off | 2 | 725.110 | 233.305 | 362.420 | 234.850 | 363.805 | 1.045 | 4.395 | 4.420 | 159.969 | 5.462 | 9.577 | 12.974 | 34.535 | 40 | 1 | 0 |
| sobrados/calm | proxy | 2 | 693.240 | 226.920 | 337.880 | 228.985 | 339.990 | 1.040 | 4.395 | 4.385 | 159.326 | 5.515 | 9.556 | 13.030 | 31.254 | 45 | 0 | 0 |
| sobrados/calm | splits2 | 2 | 630.390 | 233.410 | 268.595 | 234.615 | 269.525 | 1.000 | 4.400 | 4.405 | 159.617 | 5.421 | 9.598 | 13.131 | 34.647 | 48 | 1 | 0 |
| sobrados/calm | far120 | 2 | 670.015 | 224.780 | 315.825 | 225.775 | 317.570 | 1.110 | 4.550 | 5.040 | 146.272 | 6.179 | 11.133 | 14.959 | 42.544 | 107 | 3 | 0 |
| sobrados/calm | reveal | 2 | 715.200 | 231.880 | 353.830 | 232.665 | 354.620 | 1.050 | 4.390 | 4.355 | 160.739 | 5.351 | 9.437 | 12.911 | 30.642 | 39 | 0 | 0 |
| sobrados/calm | combined | 2 | 594.050 | 227.025 | 238.550 | 227.985 | 240.015 | 0.975 | 4.610 | 4.345 | 158.746 | 5.513 | 9.511 | 12.947 | 35.250 | 51 | 2 | 0 |
