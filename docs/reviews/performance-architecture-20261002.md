# Auditoria de arquitetura e performance do Geteco

Avaliação iniciada em 2 de outubro de 2026, com continuação em 3 de outubro, dois agentes auxiliares, leitura de código, exame do vídeo enviado e consulta à documentação e a exemplos oficiais do Godot.

**Parecer atualizado:** vinte e quatro correções chegaram ao principal. As últimas duas preservam a integridade dos filhos de modelos importados e antecipam os materiais compartilhados do interior; o pico de primeira preparação caiu de **51,793 para 10,049 ms** no experimento dirigido. Na conferência final da cena real, foram **129,43 FPS parado** e **115,93 FPS em combate**, sem frame acima de 66,7 ms nem erro de runtime nessas janelas. O combate ainda teve um pico de **37,627 ms**. População, eventos e teto de passos diferem entre cenários: esses números não demonstram ganho causal global nem certificam todas as áreas. **O jogo não está certificado como livre de quedas.** As correções abrangem renderização, caches, streaming, trânsito, recuperação de entidades, efeitos e persistência; os limites e pendências permanecem explícitos abaixo. Fechamentos de etapas anteriores são históricos.

A árvore de trabalho estava sendo alterada por outras sessões. O HEAD observado foi `804d82d94f04d4b40bc7d6cad6bd06e00b302ec4`, com modificações locais; ele não identifica sozinho todo o código auditado. Os benchmarks usaram uma cópia isolada desse estado, com C# compilado. Os primeiros arquivos portados foram `VehicleTireEffects.gd` e `PoliceModel.gd`; a continuação acrescentou os arquivos de sangue, `PoliceVisualPrewarm.gd`, uma chamada no carregamento e a correção do sorteio desnecessário em `RigBodySwap.gd`. Cada integração preservou as alterações locais existentes. Preferências e saves pessoais foram preservados. As linhas da revisão inicial podem deslocar-se com o trabalho concorrente.

| Pendência principal | Evidência atual | O que falta para encerrar |
|---|---|---|
| Travadas intermitentes da cena real | Pausa de primeira preparação do interior corrigida; última coleta de fronteiras teve máximo 34,349 ms e não repetiu a espiral grave | Confirmar comportamento em outros percursos/condições; o método do pico residual dentro dos callbacks físicos não foi identificado |
| Canhão do caminhão de bombeiros | Candidato preserva geometria e passa em 64 checks com os dois jatos reais | Validação temporal renderizada e comparação de custo antes de integrar |
| Save acima do orçamento total | Reprodução original passa em 54/55; os arquivos anteriores ficam protegidos | Contrato de admissão por componente, incluindo dados de mundo e rollback |
| Cobertura global do jogo | Código, cenários locais e contratos descritos neste relatório | Percursos, acessos e condições da matriz final; testes locais não aprovam toda a cidade |

Após a etapa de testes lógicos enquanto o usuário jogava, a execução pelo editor foi encerrada. A continuação abaixo usou o principal atual, sem outro jogo/teste concorrente; o editor permaneceu aberto. A aprovação de estabilidade continua pendente.

## Continuação: conferência sem sondas detalhadas

Parado na Union, Main com população/tráfego vivos, Mobile 1080p/MSAA 2×/escala 1, VSync desligado, FPS ilimitado e teto de oito passos: **129,43 FPS**, p95 **12,103 ms**, p99 **13,149 ms**, máximo **30,910 ms**, **0/0** frames acima de 33,3/66,7 ms. Foram 3.883 frames em 30,001 s, todos focados, fontes estáveis, processo exclusivo, exit 0 e zero erros de runtime. Essa medição inclui as 24 integrações, mas não é um A/B que atribua a elas a diferença em relação aos 80 FPS do vídeo. [Coleta sem sondas](D:/geteco/game/evidence/performance-implementation-20261002/live-twentyfour-idle-20261003/live-twentyfour-idle-20261003.json), [validade](D:/geteco/game/evidence/performance-implementation-20261002/live-twentyfour-idle-20261003/validity.json).

Em combate, preservando o teto de **três passos e StallLog do atalho existente**, sem as sondas detalhadas: **115,93 FPS**, p95 **13,021 ms**, p99 **14,410 ms**, máximo **37,627 ms**, **1/0** frames acima de 33,3/66,7 ms. Foram 3.478 frames em 30,001 s, foco integral, fontes estáveis, processo exclusivo, exit 0 e zero erros. Os dez segundos de aquecimento tiveram máximos de 14,857 ms parado e 25,226 ms em combate, sem frame acima de 33,3 ms. O caminho C# do roteador estava ativo. O screenshot final confirma cena real com veículos/policiais, combate e HUD; ele não comprova estabilidade temporal sozinho. [Combate com opções do atalho](D:/geteco/game/evidence/performance-implementation-20261002/live-twentyfour-launcher-chaos-20261003/live-twentyfour-launcher-chaos-20261003.json), [validade](D:/geteco/game/evidence/performance-implementation-20261002/live-twentyfour-launcher-chaos-20261003/validity.json), [captura](D:/geteco/game/evidence/performance-implementation-20261002/live-twentyfour-launcher-chaos-20261003/live-twentyfour-launcher-chaos-20261003.png).

Não foi reduzida a qualidade, removida simulação ou alterado o launcher para obter esses resultados. As travadas de mais de um segundo não reapareceram nas últimas coletas integradas, inclusive na coleta de diagnóstico com oito passos, mas a amostra finita não prova eliminação universal. Há picos isolados acima do orçamento de 16,67 ms; permanecem pendentes a atribuição do método nos callbacks físicos e os cenários/rotas da matriz de cobertura. As duas correções desta continuação passaram em **347 checks** (42 de identidade dos modelos, 264 de ciclo da frota e 41 de interiores), além do build .NET sem erros/warnings. Esses checks não equivalem à aprovação de todas as funcionalidades do jogo.

## Continuação: física após as 24 integrações

O diagnóstico limitado no principal usou somente sentinelas de início/fim dos callbacks físicos, fim dos callbacks de processo, pre/post draw e contadores nativos da thread. Sem WCT, profiler remoto, censo contínuo de nós ou agregados por método. O build do helper C# e o parser passaram; a execução foi exclusiva, com fontes estáveis, exit 0 e zero erros.

Em 30,004 s de combate com oito passos máximos, foram **111,22 FPS**, p95 **13,422 ms**, p99 **15,030 ms**, máximo **34,349 ms**, **1/0** frames acima de 33,3/66,7 ms. Os dez segundos de aquecimento também não tiveram frame acima de 66,7 ms (máximo 33,958 ms). Os 3.337 frames medidos estavam focados; 1.800 passos físicos, zero descartes, inconsistências de pares, erro de contadores ou perda de intervalos. Não houve a espiral de oito passos: 1.540 frames sem passo, 1.794 com um e três com dois.

O passo físico entre sentinelas teve p50/p95/p99 de 5,645/6,832/8,333 ms e máximo 24,638 ms. O único frame acima de 33,3 ms continha um passo de 22,807 ms entre callbacks, com pipelines constantes; isso localiza o custo, sem identificar o método ou causa nativa. A captura declarou cerca de 0,779% da janela em custo próprio observado, incluído nos resultados e sem contar todo o despacho do motor. Não subtrair esses valores para anunciar FPS hipotético.

Esta coleta não reproduziu as travadas graves anteriores, mas não demonstra sua eliminação universal. População/tráfego são vivos e variaram de 35 pessoas/45 veículos para 24/34, com crescimento de duas para seis unidades de despacho. O ganho de FPS global não é atribuído causalmente ao patch. A confirmação sem os observadores e com o teto normal de três passos é separada. [Relatório da cena](D:/geteco/game/evidence/performance-implementation-20261002/live-physics-boundaries-chaos-20261003/live-physics-boundaries-chaos-20261003.json), [fronteiras e contadores](D:/geteco/game/evidence/performance-implementation-20261002/live-physics-boundaries-chaos-20261003/live-physics-boundaries-chaos-20261003-physics-boundaries.json).

## Continuação: preparação dos materiais do interior

**Vigésima quarta correção:** `VehicleInteriorMaterialPrewarm` inicializa os dois materiais reais compartilhados usados por `mesh_for`, solicita seus RIDs e aguarda três desenhos sob a cortina existente após `ReactionVisualPrewarm`. A espera é limitada a 24 frames; revalida mundo, câmera e cobertura, desconecta seu sinal e não marca famílias como preparadas. Não cria veículos/malhas/nós temporários, não reduz qualidade e mantém o preparo normal de cada família como fallback. A receita alfa foi apenas extraída para preservar identidade e propriedades.

A comparação final usa o mesmo medidor com eventos somente em memória, sem prints por fase. O braço sem antecipação retira apenas as duas linhas desse hook; elas foram recolocadas após a contraprova. Ambos os processos foram exclusivos, com fontes estáveis, foco integral, observador sem descarte, exit 0 e zero erros de runtime.

| Medida dirigida | Sem antecipação | Com antecipação |
|---|---:|---:|
| Maior frame durante a primeira preparação | 51,793 ms | 10,049 ms |
| Maior intervalo pre→post draw nessa preparação | 49,670 ms | 2,242 ms |
| Duração da coroutine, incluindo três frames | 65,821 ms | 24,742 ms |
| Máximo da janela completa de 30 s | 51,793 ms | 15,277 ms |
| Frames acima de 33,3 / 66,7 ms | 1 / 0 | 0 / 0 |
| p95 / p99 da janela | 9,083 / 9,274 ms | 9,125 / 9,539 ms |

O teste renderiza Main com callbacks do mundo suspensos e limite de 120 FPS. A população maturada antes da suspensão variou (35 versus 32); não atribuímos mudança de FPS global ao patch. O recurso estático `_drawn` permaneceu falso no controle e verdadeiro no candidato, sem aquecer prematuramente a família Union. A variação do p99 foi +2,9%, abaixo do sinal de investigação de 5%. **Aprovação restrita ao custo de primeira preparação neste cenário**, não às travadas gerais de combate. [Controle](D:/geteco/game/evidence/performance-implementation-20261002/live-union-buffered-no-material-prep-20261003/live-union-buffered-no-material-prep-20261003.json), [candidato](D:/geteco/game/evidence/performance-implementation-20261002/live-union-materials-buffered-20261003/live-union-materials-buffered-20261003.json), [validade do candidato](D:/geteco/game/evidence/performance-implementation-20261002/live-union-materials-buffered-20261003/validity.json).

Os **41 checks** de ciclo de vida/material passaram: cancelamento, retomada por outro proprietário, duplicatas, recursos compartilhados, cores/transparência, consumo real pelas malhas e ausência de marcação prematura. A compilação .NET, incluindo o helper de diagnóstico físico, terminou com zero warnings/erros após permitir escrita no cache de build do projeto. [Teste lógico](D:/geteco/game/evidence/performance-implementation-20261002/interior-materials-lifecycle-20261003/console.log).

Uma tentativa intermediária com prints por fase (`live-union-interior-materials-20261003`) apresentou 1.342,968 ms entre marcadores de uma consulta já em cache, dentro do mesmo frame, quase tudo antes de pre_draw. Após retirar esses prints, a consulta levou 27 µs. Isso sustenta interferência da instrumentação, sem identificar definitivamente a espera interna do stdout. A tentativa ruim foi preservada; ela não é usada como ganho do produto nem explica retroativamente os picos anteriores dentro do desenho.

## Continuação: integridade da frota e isolamento da pausa do interior

**Vigésima terceira correção:** os decoradores da frota adicionavam irmãos com nomes repetidos a modelos que já continham nomes automáticos gravados, como `@MeshInstance3D@6236`. Quando o contador global alcançava esses nomes, a inserção automática substituía a referência de outro filho no mapa interno. O caso dirigido do caminhão reproduziu cinco referências incorretas. Os cinco pontos de montagem em `HeavyVehicleDetail`, `PoliceGroundModels` e `PoliceTransportModel`, mais os dois pontos equivalentes de WarmUp/teto em `VehicleInterior`, agora solicitam nomes legíveis únicos com `add_child(node, true)`. Os nomes importados e a geometria foram preservados.

Após a correção, caminhão, moto e transporte passaram em **14 checks cada**; a sequência de fábricas, criação, dano, reparo, carcaça e descarte passou em **264 checks**, sem órfãos sobreviventes. Essa sequência antes produzia órfãos e crash nativo. A execução renderizada seguinte também terminou com stderr vazio, eliminando os cinco recursos do caminhão que vazavam nas coletas anteriores. Isso comprova correção de integridade/ciclo de vida, não um ganho global de FPS. [Reprodução original](D:/geteco/game/evidence/performance-implementation-20261002/fleet-name-cargo-original-20261003/user/GetecoV2/fleet-child-name-collision.json), [caminhão corrigido](D:/geteco/game/evidence/performance-implementation-20261002/fleet-name-cargo-fixed-20261003/user/GetecoV2/fleet-child-name-collision.json), [sequência da frota](D:/geteco/game/evidence/performance-implementation-20261002/fleet-order-name-fixed-20261003/console.log).

O experimento dirigido renderiza Main com callbacks do mundo suspensos e o mesmo limite de 120 FPS nos braços; **não mede FPS de gameplay**. Sem solicitar o interior, o máximo foi 16,531 ms. A primeira preparação normal produziu 70,608 ms, e a repetição em cache não reproduziu a pausa. Preparar somente os vidros durante o carregamento não resolveu: o máximo continuou em 65,134 ms. Esse candidato foi preservado em evidência e removido do runtime.

Separando as etapas, construir spec/malha levou 5,859 ms síncronos e provocou no frame seguinte **62,476 ms**, dos quais 53,089 ms entre pre/post draw, sem nenhum nó WarmUp. Cinco segundos depois, a preparação dos vidros usando a geometria já em cache terminou em três frames sem repetir o pico. Isso localiza a pausa na primeira preparação dos recursos do interior. A próxima comparação testa antecipar somente os dois materiais compartilhados para a cortina de carregamento. Não há prova de que isso resolva o pico de 1,4 s ou a espiral física distinta. [Etapas separadas](D:/geteco/game/evidence/performance-implementation-20261002/live-union-interior-stages-20261003/live-union-interior-stages-20261003.json).

Limitação da execução de etapas: o JSON completo, foco integral, observador sem descarte, hashes e vigilância de processos foram registrados, mas o runner falhou ao aplicar regex ao log stderr vazio, antes de persistir o código de saída em `validity.json`. O caso de log vazio foi corrigido sem ignorar logs de erro; essa execução continua sendo evidência diagnóstica, não uma aprovação completa do runner.

Os contadores de pipeline não incluem toda a preparação GLSL/SPIR-V e espera por compilação de materiais. O código do motor separa essas tarefas; contadores estáticos não descartam essa hipótese. [Materiais do motor utilizado](https://github.com/godotengine/godot/blob/ed1daf0bf/scene/resources/material.cpp), [compilação de shaders](https://github.com/godotengine/godot/blob/ed1daf0bf/servers/rendering/renderer_rd/shader_rd.cpp), [nomes e inserção de filhos](https://github.com/godotengine/godot/blob/ed1daf0bf/scene/main/node.cpp).

## Continuação: medição das 22 integrações no principal

O principal foi compilado com Godot .NET 4.7.2, sem warnings ou erros de C#. O medidor passou a aguardar sessão e produção prontas e a retirada da cortina de carregamento; também limpa o movimento acumulado da câmera antes da fixture. A cópia antiga tem diferenças de conteúdo e não foi usada para certificar a árvore atual. As três coletas abaixo mantiveram fontes estáveis durante cada execução; entre elas, mudou somente o medidor. Hardware: i7-13650HX e RTX 4060 Laptop; Mobile, 1920×1080, MSAA 2×, escala 1, VSync desligado, sem limite de FPS, física 60 Hz e teto de oito passos. Esse teto não é o de três passos do launcher normal.

| Coleta | FPS médio | p95 / p99 (ms) | Máximo (ms) | >33,3 / >66,7 ms | Limitação |
|---|---:|---:|---:|---:|---|
| `live-twentytwo-idle-20261003` | 129,86 | 12,296 / 13,598 | 24,553 | 0 / 0 | 3.896/3.896 frames com foco; erros de recursos no encerramento |
| `live-twentytwo-chaos-20261003` | 81,70 | 17,286 / 33,479 | 1.570,113 | 26 / 9 | Log verbose, 180 frames sem foco e erros no encerramento; não serve de aprovação |
| `live-warmup-identity-chaos-20261003` | 77,32 | 17,032 / 43,126 | 1.397,965 | 41 / 16 | Diagnóstico com observadores/StallLog; 2.320/2.320 frames com foco; mesmos erros no encerramento |

Cada janela medida tem pelo menos 30 segundos após dez segundos de aquecimento e maturação da população/tráfego. Esses valores não demonstram ganho causal sobre as coletas históricas. A janela parada foi suave, mas o combate reproduziu pausas graves; não há aprovação global. [Dados parado](D:/geteco/game/evidence/performance-implementation-20261002/live-twentytwo-idle-20261003/live-twentytwo-idle-20261003.json), [combate com verbose](D:/geteco/game/evidence/performance-implementation-20261002/live-twentytwo-chaos-20261003/live-twentytwo-chaos-20261003.json), [diagnóstico com identidade](D:/geteco/game/evidence/performance-implementation-20261002/live-warmup-identity-chaos-20261003/live-warmup-identity-chaos-20261003.json).

O diagnóstico separou dois padrões. No frame 11082, um WarmUp pertencente ao `union_sedan` `street_25501838` foi criado 3,943 ms após o começo do intervalo de 1.397,965 ms. Entre `frame_pre_draw` e `frame_post_draw` decorreram 1.323,755 ms. Surface/Draw/Specialization não aumentaram nesse intervalo; Draw +1 e Specialization +3 apareceram no seguinte. O tempo GPU registrado era 3,78 ms e render CPU 1,64 ms, portanto não há atribuição demonstrada a GPU saturada, compilação ou driver. A correlação localiza o próximo experimento, não prova a causa nativa. Outro WarmUp de `sport_coupe` ficou em 14,296 ms. Uma sequência distinta apresentou cinco a oito passos físicos e grandes intervalos após o desenho, sem WarmUp. [StallLog correlacionado](D:/geteco/game/evidence/stall-logs/stalls-20261003-035905.log).

O coletor opt-in registrou 3.007 intervalos sem descarte e média de 16 µs por captura de intervalo; isso não inclui todo o custo dos observadores. Identifica o proprietário pelo token real de preparação, material, posição e parentesco, inclusive irmãos renomeados automaticamente pelo motor. Não lê arrays de malha. A perda de foco agora também marca explicitamente o relatório como inválido.

Os erros de saída foram localizados em cinco `MeshInstance3D` órfãos, cinco malhas, três `TriangleMesh` e três materiais, incluindo dois recursos de `cargo_flatbed_truck.scn`. O teste dirigido de cena crua, decoradores frios/cache e fábrica passou em 26/26, com todos os nós liberados. Portanto a fábrica isolada não reproduz o vazamento; os consumidores continuam sob investigação. Não foram suprimidos os erros nem alterado o critério do runner. [Reprodução inicial de ownership](D:/geteco/game/evidence/performance-implementation-20261002/cargo-orphan-baseline-20261003/console.log).

## Coletas renderizadas no projeto principal

As duas coletas `live-six-fixes-*` usaram a árvore principal daquela etapa, incluindo alterações concorrentes preexistentes, com C# compilado. O monitor de processos não encontrou outro jogo/teste; os hashes permaneceram estáveis e os processos encerraram com código zero. Ambas medem 30 segundos após estabilização e aquecimento, com cidade ativa, 1080p/Mobile/MSAA 2×, escala 1, VSync desligado e FPS ilimitado.

| Coleta no principal | FPS | p50 | p95 | p99 | Máximo | >33,3 / >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|
| `live-six-fixes-idle` | 124,98 | 5,653 | 12,405 | 13,594 | 36,630 | 1 / 0 |
| `live-six-fixes-chaos` | 88,38 | 11,878 | 16,055 | 31,444 | 269,602 | 25 / 17 |
| `live-eight-fixes-idle` | 126,22 | 5,711 | 12,382 | 13,472 | 28,708 | 0 / 0 |
| `live-ttl-idle` | 136,12 | 5,230 | 11,890 | 13,233 | 93,877 | 2 / 1 |
| `live-ttl-chaos` | 102,96 | 11,425 | 13,625 | 14,923 | 118,177 | 3 / 2 |

A coleta com oito correções manteve o mesmo protocolo, 3.787 frames em 30,002212 s, hashes estáveis, processo exclusivo e roteador C# ativo. Havia 38 pessoas e 48 veículos no início e no fim. GPU média de 2,487 ms e render CPU de 0,978 ms. É uma janela sem travadas observadas, não prova de que os episódios intermitentes foram eliminados. [Resultado atual parado](D:/geteco/game/evidence/performance-implementation-20261002/live-eight-fixes-idle/live-eight-fixes-idle.json).

As duas coletas após o TTL também foram válidas, mas o parado teve duas a três unidades de serviço e sua população caiu de 35 para 32, contra 38 no controle anterior. **Não atribuir os 7,8% a mais de FPS ao TTL.** O combate teve 3.090 frames em 30,011894 s; p95/p99 melhores que os controles disponíveis, mas ainda duas pausas acima de 66,7 ms. Sem coletores detalhados nessas execuções, suas causas continuam indeterminadas. [Parado após TTL](D:/geteco/game/evidence/performance-implementation-20261002/live-ttl-idle/live-ttl-idle.json), [combate após TTL](D:/geteco/game/evidence/performance-implementation-20261002/live-ttl-chaos/live-ttl-chaos.json).

Tempos em milissegundos. O combate concentrou 24 dos 25 frames acima de 33,3 ms entre 22,58 e 25,09 segundos; o restante ocorreu em 28,72 s. Não havia os coletores detalhados de passos/CPU nessa execução: a semelhança com a recuperação física anterior é uma hipótese, sem atribuição por frame confirmada. Os monitores de física do Godot registram máximos por segundo, não custos individuais dos passos. **As travadas gerais continuam sem aprovação.**

**Diferença do atalho de jogo:** o protocolo controlado mantém 60 Hz e o padrão do motor de oito passos físicos máximos por frame, removendo o override de ambiente e desativando StallLog nas duas coletas acima. O `JogarCSharp.cmd` atual já tinha `HARBOR_MAX_PHYSICS_STEPS=3` e `HARBOR_STALL_LOG=1`. Não alteramos esse launcher. Estes números não são reprodução exata da configuração desse atalho. Reduzir o teto limita a recuperação em um frame, mas pode desacelerar a simulação sob sobrecarga; não elimina a causa do custo.

Evidências: [parado](D:/geteco/game/evidence/performance-implementation-20261002/live-six-fixes-idle/live-six-fixes-idle.json), [combate](D:/geteco/game/evidence/performance-implementation-20261002/live-six-fixes-chaos/live-six-fixes-chaos.json), [validade](D:/geteco/game/evidence/performance-implementation-20261002/live-six-fixes-chaos/validity.json).

A conferência adicional `live-launcher-chaos` usou as duas opções existentes do atalho (StallLog ligado e teto de três passos), sem alteração do produto: **94,10 FPS**, p50/p95/p99 de **11,855/15,493/17,197 ms**, máximo **33,819 ms**, **1/0** frames acima de 33,3/66,7 ms em 30,000 s. Os hashes e a exclusividade do motor permaneceram válidos; o roteador C# estava ativo antes da janela medida e em todos os seus estados amostrados. Ele ainda não havia sido criado no primeiro READY, quando não havia unidade despachada, e apareceu durante o aquecimento. Esta coleta não reproduziu a sequência grave. Eventos/população diferem, portanto não atribuímos a diferença de FPS ou o desaparecimento da sequência exclusivamente ao teto de três passos. [Dados da configuração do atalho](D:/geteco/game/evidence/performance-implementation-20261002/live-launcher-chaos/live-launcher-chaos.json).

## Continuação: custo recorrente, primeira apresentação e skates

### Histórico econômico: primeira compactação integrada

**Décima sétima correção:** `RecurringReceipts` representa novos recibos contíguos de cinco contratos determinísticos por intervalos: aluguel de motocross, aluguel de esqui, oficina Northgate, bebida e caixa do Tonico. Os recibos anteriores e opacos continuam exatos. Lacunas, grafias não canônicas e valores diferentes não são inventados como pagamentos; permanecem no formato opaco. Membership reconstrói no máximo um recibo consultado, sem expandir todo o histórico no snapshot. Motocross e Tonico agora consultam também os intervalos compactos.

O primeiro recibo compacto muda o envelope econômico para versão 2: leitores antigos rejeitam o formato, em vez de ignorarem silenciosamente as provas de pagamentos. Os valores dos cinco contratos fazem parte do formato persistido; mudar um preço não autoriza reescrever o significado dos recibos antigos. Save, rollback e importação preservam juntos os dados econômicos e os intervalos. Recompensas permanentes de campanha/mundo, munição e compras variáveis mantêm sua representação anterior.

A comparação diferencial executou **92 checks**, incluindo **100.000 operações aceitas**, com **2.013 bytes** no save completo da fixture, um recibo opaco e cinco intervalos. Passaram também motocross (27), comércio da vila (26), campanha/economia (162), conversor V1 (42), importação V1 (10) e full save sem falhas. A primeira tentativa de importação encontrou dois scripts ausentes no snapshot: foram copiados intactos com hashes e os contratos executados depois; não foi tratada como defeito do jogo. No principal, passaram novamente 92 checks, campanha/economia (162) e full save, sem erro de runtime e com armazenamento isolado. [Integração e arquivos preservados](D:/geteco/game/evidence/performance-implementation-20261002/recurring-ledger-live-port/manifest.json), [contrato no principal](D:/geteco/game/evidence/performance-implementation-20261002/live-recurring-ledger-stage1/result.json), [teste durável](D:/geteco/game/tests/test_recurring_receipts.gd).

**Limite desta entrega:** entradas/prêmios de motocross, bônus esparsos de esqui, compras genéricas e outros IDs opacos ainda podem crescer. Esses domínios não foram apagados nem representados incorretamente por um maior serial. O resultado de 2.013 bytes pertence à fixture dos cinco contratos cobertos; não é previsão do tamanho de qualquer save, certificação de FPS ou solução de todo o histórico econômico.

### Histórico econômico: resultados exatos de motocross e esqui

**Décima nona correção integrada:** os novos recibos de entrada/prêmio de motocross e chegada/recorde das três pistas autorais de esqui agora usam páginas esparsas de 256 símbolos. Cada símbolo conserva exatamente os pagamentos e seus valores históricos; ausência, derrota e lacuna continuam distintas. Uma tentativa distante aloca apenas sua página. Recibos antigos, valores diferentes e IDs não canônicos permanecem opacos. A consulta reconstrói somente o recibo pedido, sem expandir o histórico inteiro.

O primeiro evento compacto promove carteira e ledger para V3. O novo leitor aceita V1/V2; leitores anteriores rejeitam V3. O codec não depende de preços futuros do catálogo. Motocross valida entradas e vitórias por um resumo exato dos 25 pares possíveis, cruzando as exceções opacas. Esqui combina seriais realmente registrados nos dois formatos e mantém o rollback das duas parcelas. Recompensas permanentes continuam passando pelos contratos de campanha e mundo.

A fixture passou em **228/228**, incluindo misturas de recibos opacos/compactos, tentativa ativa, recompensa órfã, retries iguais/conflitantes, páginas inválidas, grandes saltos, migração, JSON, rollback e **100.000 atividades pelas APIs reais**: 50.000 corridas e 50.000 descidas. O save completo dessa fixture ficou em **109.088 bytes**, abaixo dos 2 MiB inalterados, e preservou saldo e repetição do primeiro pagamento após reload. Com regressões dos consumidores, foram **587 checks contados + full save** no snapshot; no principal, **228 + 162 = 390 checks + full save**, sem erros nem mudança nas fontes observadas. As tentativas iniciais com erro de inferência e comparação de versões após JSON foram preservadas e corrigidas antes dessas passagens.

Há custo residual mensurado: na execução lógica concorrente do principal, snapshot levou 51 µs, restore integral cerca de 46 ms, save completo 113,3 ms e load 99,1 ms no caso de 100.000 atividades. A compactação reduz crescimento, mas **não torna save síncrono livre de pausas nem comprova FPS**. Outros históricos opacos e distribuições muito esparsas ainda podem alcançar os limites. [Desenho, medidas e limites](D:/geteco/game/evidence/performance-implementation-20261002/economy-ledger-versioned-design.md), [manifesto de integração](D:/geteco/game/evidence/performance-implementation-20261002/race-ledger-live-port/manifest.json), [teste durável](D:/geteco/game/tests/test_race_receipts.gd).

Uma revisão complementar encontrou colisão de nomes na API genérica: usar `motocross` como ID de uma pista de esqui podia consultar as páginas de corridas. O leitor de seriais agora aceita somente as três pistas autorais. O caso dirigido passou de duas falhas em oito checks para **8/8**; o controle entrou no teste durável. Esse guard não altera os caminhos das 100.000 atividades já testadas, que não foram repetidas apenas para essa condição.

### Histórico econômico: recusa atômica no limite opaco

**Vigésima correção integrada:** `Economy` mantém o teto existente de 10.000 recibos opacos também nas operações que os criam. Depois de validar a operação e reconhecer um retry, gastos, recompensas, compras e munição verificam a capacidade antes de alterar dinheiro ou inventário. Novos recibos compactos continuam permitidos no teto. Recompensas de mundo conservam o rollback completo, e compras retornam `receipt_limit`; nenhum recibo foi apagado para abrir espaço.

A fixture passou em **77/77** no candidato e no principal, com e sem inventário em grid, limite exato, replays antigos, valores fora do codec, recompensa composta e continuação dos domínios compactos. O teste completo de save também passou no principal, sem erro de runtime nem mudança nas fontes guardadas. O primeiro controle com SMG e grid já falhava por falta de capacidade de inventário antes de testar recibos; foi substituído por shotgun com capacidade demonstrada, preservando o log da precondição inválida. [Manifesto](D:/geteco/game/evidence/performance-implementation-20261002/opaque-guard-live-port/manifest.json), [principal](D:/geteco/game/evidence/performance-implementation-20261002/live-opaque-capacity/result.json), [teste durável](D:/geteco/game/tests/test_opaque_receipt_capacity.gd).

A reprodução original de **55 verificações**, preservada sem alterar assertions, passou de oito falhas para **uma falha restante**. Os sete casos estruturais agora aceitam estado restaurável ou recusam sem mudança; o esqui genérico reverte inclusive a primeira parcela quando a segunda não cabe. **O orçamento total de bytes permanece aberto:** IDs legais longos ainda podem formar um estado maior que 2 MiB antes de atingir 10.000 recibos. SaveStore protege os arquivos existentes, mas isso não torna esse estado gravável. A correção não promete histórico ilimitado nem aprovação de FPS.

A revisão do contrato confirmou que o teto de 2 MiB é local e também rege backup, temporário e importação. Os validadores limitam várias contagens, mas os seis componentes principais preservam campos adicionais sem um máximo global de tamanho; as páginas esparsas V3 também podem ultrapassar o orçamento. Portanto, aumentar uma constante não garante persistência de todo estado atualmente aceito. A solução geral exige definir os limites dos componentes e reservar bytes antes de publicar mudanças persistentes, incluindo captura do mundo e rollback de ações compostas. Isso permanece uma mudança arquitetural a desenvolver, separada das correções já integradas. [Alternativas e limites demonstrados](D:/geteco/game/evidence/performance-implementation-20261002/save-byte-budget-options.md).

### Recuperação de equipes: água e corpos suspensos

**Canhão do caminhão, candidato pronto sem integração:** a sonda por etapas confirmou que `FleetSpeedPass` fundia cano e bico às peças fixas. O rig existia antes desse passe e desaparecia depois, tanto na criação fria quanto no cache. O candidato preserva as peças articuladas pelo contrato geométrico existente, mantendo o agrupamento restante: **42 → 44 meshes**, com os mesmos **38.856 triângulos por instância**, posição, orientação das faces, normais, UV e materiais. O original falhou em seis de 16 checks; o candidato passou em 23/23, incluindo independência entre dois pivôs. Com esse candidato, o callback real do bombeiro passou em 64/64, com os dois jatos ativos sem injeção da emissão.

Uma primeira sonda usava `duplicate()` com reinstanciação de PackedScene e podia recriar peças removidas; foi corrigida para `duplicate(0)` antes de concluir sobre o rig. As execuções anteriores foram preservadas. O patch ficou externo e o snapshot voltou ao original com guard de hash. **Ainda faltam aparência temporal e custo renderizado**: além de duas malhas, restaurar o canhão ativa até 460 partículas configuradas adicionais. Não é correto chamar essa recuperação de funcionalidade de ganho de FPS. [Patch revisável](D:/geteco/game/evidence/performance-implementation-20261002/FleetSpeedPass.pumper.patch), [geometria do candidato](D:/geteco/game/evidence/performance-implementation-20261002/pumper-rig-geometry-candidate/result.json), [integração real dos jatos](D:/geteco/game/evidence/performance-implementation-20261002/pumper-real-water-candidate/result.json).

**Água, décima quinta correção integrada:** sair do modo `service` do bombeiro encerra os jatos imediatamente, inclusive quando `DispatchUnit` força retorno por perda da fonte ou cancelamento. A mesma fixture corrigida reproduziu quatro falhas em 54 verificações no original e passou em 54/54 no candidato. Os caminhos usam Fire, Responder, DispatchUnit e WaterJet reais e verificam retorno físico, embarque e reutilização. O cenário montado já começa estacionado; não valida chegada nem FPS. O teste separa explicitamente o jato de mão real de um contrato com dois emissores ativados, porque encontrou outra falha: o caminhão decorado não expõe as peças que `_rig_pumper` procura para montar o canhão. Essa falha permanece em investigação própria; não foi encoberta pela correção do cleanup. [Matriz de água e limites](D:/geteco/game/evidence/performance-implementation-20261002/responder-water-recovery-analysis.md).

**Suspensão, décima sexta correção integrada:** o filho `BurningActor` continua processando enquanto o corpo do socorrista está suspenso. Se ele morria, a retomada restaurava camadas/máscaras de quando estava vivo; se o corpo era removido, a atribuição a `CharacterBody3D` antes de verificar validade gerava erro repetido e impedia retomar. Agora referências são verificadas como Variant antes de uso, corpos mortos não exigem cápsula de pessoa viva e sua colisão permanece no estado de morte. O cadáver volta à apresentação e continua disponível para o legista. Não foi desativado o dano do fogo para esconder a falha.

O teste executa despacho e caminhada reais, afasta o observador para suspender, deixa o fogo matar por seus callbacks normais e também remove um corpo durante suspensão. Acrescenta um sólido na posição antiga, remove-o depois e inclui o contrato saudável já existente. Original: 28 verificações, seis falhas e 60 erros de referência removida; candidato: 28/28, sem erros; principal: **30/30, sem erros**, com duas verificações adicionais do roteador C# ativo. A primeira fixture exigia uma contagem mínima incorreta de 29; foi corrigida para os 28 checks existentes sem remover nenhuma assertion, preservando a execução anterior. [Baseline corrigida](D:/geteco/game/evidence/performance-implementation-20261002/dispatch-suspended-loss-baseline-v2/result.json), [candidato](D:/geteco/game/evidence/performance-implementation-20261002/dispatch-suspended-loss-candidate/result.json), [principal](D:/geteco/game/evidence/performance-implementation-20261002/live-dispatch-suspended-loss/result.json).

As verificações acima são lógicas, headless, com storage isolado e processos concorrentes registrados. Comprovam o ciclo de vida coberto; não certificam aparência nem ganho de FPS. O erro de compilação do supermercado surgido nas primeiras validações LIVE da água foi corrigido por outra sessão e não é contado como alteração desta auditoria. Após essa correção, a revalidação no principal passou limpa em **54/54** e o teste existente de lifecycle do fogo em **5/5**, com código zero, sem ERROR/Parse Error e sem mudança dos hashes monitorados. [Água no principal](D:/geteco/game/evidence/performance-implementation-20261002/live-responder-water-recovery-clean/result.json), [regressão existente](D:/geteco/game/evidence/performance-implementation-20261002/live-responder-fire-lifecycle-clean/result.json).

### Veículo destruído durante suspensão: colisão e reparo

**Décima oitava correção integrada:** a queima podia destruir um veículo enquanto o despacho o mantinha oculto e sem colisão. A carcaça capturava os zeros temporários como estado de condução; ao voltar, o despacho reativava o CharacterBody errado, e um reparo posterior deixava o carro saudável sem colisão nem processamento. Uma carcaça criada antes da pausa também continuava integrando e podia impedir sua própria retomada.

`VehicleDamage` agora guarda o estado anterior e suspende o dono físico atual. Uma carcaça fica congelada e sem colisão durante a pausa; na retomada, somente o corpo rígido recupera suas máscaras. Reparo durante a suspensão conserva o estado de condução para quando o carro voltar. O fallback do despacho preserva também um callback originalmente desligado. A queima continua seguindo seus callbacks reais; não foi desativada para evitar o defeito.

O original falhou em **11 de 44 checks**. Candidato e principal passaram em **44/44**, incluindo raycast nativo, destruição antes/durante a pausa, reparo e adoção única da carcaça. A regressão existente passou em **36/36** com dois modelos, piso plano e rampa, salto, apoio, repouso e reparo. Equipes passaram em 28/28 no snapshot e 30/30 no principal, que acrescenta dois checks do roteador C#. Build .NET sem erros/avisos; execuções sem erros de runtime nem mudanças nas fontes monitoradas. São evidências de física e ciclo de vida, com aparência e FPS ainda pendentes. [Análise e matriz](D:/geteco/game/evidence/performance-implementation-20261002/dispatch-vehicle-suspension-analysis.md), [manifesto de integração](D:/geteco/game/evidence/performance-implementation-20261002/dispatch-vehicle-suspension-integration.json), [teste durável](D:/geteco/game/tests/dispatch/test_dispatch_suspended_vehicle_wreck.gd).

### Personagens arremessados: suspensão e disputa pela pose

**Vigésima primeira correção integrada:** desligar o callback do socorrista não interrompia seu filho `BodyFlight3D`, que continuava movendo um personagem oculto. O tween de recuperação podia devolver colisão antes da retomada, e depois o despacho reaplicava o estado antigo. Agora despacho e dono do movimento compartilham o estado desejado: pausam e retomam o callback e o tween apropriados, preservam callbacks já desligados, tratam cancelamentos e mantêm os efeitos reais de morte por fogo. O personagem não volta como um colisor invisível nem recebe dois donos de movimento.

A retomada verifica a cápsula caída e as formas que retornarão à posição em pé. Paredes, tetos e saturação da consulta bloqueiam. O apoio residual legítimo vem do último movimento físico real e só é reconhecido com a mesma pose, mundo e cápsula; um piso elevado antes da pausa não vira automaticamente apoio permitido. Uma diferença de aproximadamente 6×10⁻⁹ m entre cálculo e consulta exigiu equivalência numérica local ao apoio identificado, usando o epsilon interno do Godot. Isso não adiciona uma consulta por contato nem uma margem física global. [Pares de contato nativos](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate3d.html#class-physicsdirectspacestate3d-method-collide-shape), [comparação numérica do Godot](https://docs.godotengine.org/en/stable/classes/class_@globalscope.html#class-globalscope-method-is-equal-approx).

O original teve **17 falhas em 99 verificações**, sem erros de runtime. O contrato final ampliado passou em **103/103**, incluindo voo, recuperação, morte, remoção, cancelamento enfileirado, rampa, segunda suspensão e piso novo. As tentativas com erros do observador/print da fixture e os candidatos ainda incompletos foram preservados, sem alterar assertions para obter aprovação.

**Vigésima segunda correção integrada:** havia um segundo escritor da pose: o efeito de impacto continuava girando o corpo enquanto a recuperação estava pausada. `BodyFlight3D` cancela e restaura o hit anterior antes de capturar sua base; novos hits respeitam queda e recuperação. Dano e animação de morte continuam ativos, e impactos normais voltam após levantar. A baseline independente teve **seis falhas em 40 verificações**; o candidato passou em **40/40**. O Godot recomenda evitar tweens concorrentes sobre a mesma propriedade. [Contrato de Tween](https://docs.godotengine.org/en/stable/classes/class_tween.html).

No principal, passaram **103 + 40 + 30 = 173 verificações**, com compilação .NET sem erros/avisos, código zero, nenhum erro de runtime e hashes estáveis. As regressões no snapshot passaram em 30/30 para BodyFlight, 30/30 para equipes e 44/44 para carcaças. Os cinco arquivos integrados conferem com o manifesto. São contratos lógicos com armazenamento isolado; aparência temporal dos diferentes modelos e FPS ainda precisam de validação renderizada. [Análise e matriz](D:/geteco/game/evidence/performance-implementation-20261002/dispatch-body-flight-suspension-analysis.md), [manifesto](D:/geteco/game/evidence/performance-implementation-20261002/dispatch-body-flight-suspension-integration.json), [suspensão no principal](D:/geteco/game/evidence/performance-implementation-20261002/live-dispatch-body-flight-suspension/result.json), [teste de suspensão](D:/geteco/game/tests/dispatch/test_dispatch_body_flight_suspension.gd), [teste de impacto](D:/geteco/game/tests/dispatch/test_body_flight_hit_owner.gd).

### Save: recusar excesso antes de tocar nos arquivos

**Décima quarta correção integrada:** `SaveStore.save` serializa uma única vez, mede os bytes UTF-8 exatos e recusa o excesso antes de criar diretórios, mexer em temporários, backups ou flags de recuperação. O mesmo buffer validado é escrito. A versão original falhou em sete das 53 verificações da fixture corrigida; candidato e principal passaram em 53/53 sem erros de script. Inclui Unicode que excede 2 MiB mesmo com menos caracteres, o limite exato de 2 MiB, um byte a mais, recuperação por temporário/backup e preservação do estado do chamador. A primeira fixture tinha uma comparação int/float inadequada após JSON; essa evidência foi preservada e corrigida antes do par válido. [Manifesto de integração](D:/geteco/game/evidence/performance-implementation-20261002/save-byte-preflight-live-port/manifest.json).

Esses testes são contratos headless com armazenamento isolado e concorrência registrada. Não medem FPS, nem resolvem o crescimento do histórico econômico: um estado grande demais agora é recusado sem danificar arquivos existentes, mas a progressão longa ainda exige compactação correta.

### Diagnóstico nativo e correção do logger

**Décima terceira correção:** duas leituras de `perf_costs` no `StallLog` agora verificam `has_meta` antes de consultar a metadata. Com o rastreamento detalhado desligado, o original emitia erros quando esses dados não existiam. O mesmo contrato headless passou em 30 checks nas duas variantes, mas o original registrou dois ERROR e o candidato nenhum. Os dois guards e as 13 verificações adicionais foram integrados com hashes preservados. Execução lógica com storage isolado e concorrência registrada; não é uma comparação de FPS. [Evidência do candidato](D:/geteco/game/evidence/performance-implementation-20261002/logger-meta-guard-candidate/result.json).

A primeira coleta WCT permanece marcada como inválida para aprovação de desempenho: teve 74 erros do logger. Ela localizou um intervalo de desenho de 58,966 ms junto de duas novas compilações Surface e um `WarmUp` de veículo; a cadeia nativa de espera não foi resolvida. O GC gerenciado não apresentou nova coleta/pausa nessa janela. A identificação do arquétipo foi acrescentada apenas ao harness isolado, para decidir o próximo experimento; não foi feita nova coleta renderizada enquanto outro jogo estava ativo. [Análise da sequência e limites](D:/geteco/game/evidence/performance-implementation-20261002/wct-chaos-analysis.md).

### Investigação em andamento: streaming e ocupação de cruzamentos

A fixture renderizada `chunk-3-3-baseline-isolated` usa a Main e os registros reais do porto, suspende explicitamente a simulação não relacionada e mantém os callbacks normais do `NativeRegion`. Três pedidos/liberações do trecho (3,3) passaram em 24 verificações, incluindo suporte físico por raycast, conclusão e descarte. A construção síncrona das superfícies custou **10,491–10,769 ms** por pedido; dentro dela, ruas **5,641–6,008 ms** e oceano **3,077–3,366 ms**. O primeiro frame ainda incluiu a construção indivisível do escritório, chegando a **19,389–21,187 ms**. Carga solta e holofote custaram aproximadamente 9–10 e 5 ms em frames seguintes. São custos de streaming isolados, não FPS de gameplay com a cidade ativa. A primeira tentativa da fixture não congelou um descendente com `PROCESS_MODE_ALWAYS` e falhou antes de medir; seu resultado foi preservado e a condição de isolamento foi corrigida sem remover assertions.

O oceano agora filtra uma vez por trecho as arestas da costa que podem influenciar o resultado limitado a 24 metros. Preservou exatamente 36 assinaturas completas das malhas e passou em 20.916 checks em cada variante e no principal. O custo local caiu de **3,146 para 1,662 ms**. A filtragem conservadora de ruas evita recortes de polígonos cujos limites não tocam o trecho; 95 casos e 71 células produtivas mantiveram arrays, materiais e colisões equivalentes. Combinadas, as superfícies do trecho medido passaram de **10,594 para 7,182 ms** (−32,21%). Ambas foram integradas, com build .NET sem erros/avisos e o teste existente de oceano passando. [Evidência integrada](D:/geteco/game/evidence/performance-implementation-20261002/ocean-edges-analysis.md).

O combate renderizado com ruas/oceano otimizados marcou **94,532 FPS**, p95/p99 **14,911/15,987 ms**, máximo **96,762 ms**, 1/1 frames acima de 33,3/66,7 ms. Uma confirmação finita com os dois builders originais marcou **94,387 FPS**, p95/p99 **15,681/18,007 ms**, máximo **118,638 ms**, 5/2 frames lentos. População e eventos variaram; o controle não confirmou regressão causada pelos builders, nem autoriza atribuir ganho global de FPS. Eles não executaram no maior pico do candidato: ali houve preparo de materiais do interior de um veículo e intervalo de desenho de 52 ms, ainda sem causa nativa isolada.

O teste antigo de fidelidade viária falhou igualmente no original e nas otimizações: esperava 39 vias onde a fonte já define 40; exigia o nome do asfalto genérico numa rampa pertencente ao CanalTunnel; e o raio do acesso 5 terminava em −2 m, acima do piso em −2,0390625 m. A correção do teste compara IDs/coordenadas/larguras com a fonte e exige dono, altura e normal física das rampas. **Passou sem falhas** em `road-fidelity-current-contract`: os raios encontraram −1,456249 m e −2,039062 m, com as normais analíticas corretas e colliders pertencentes ao CanalTunnel. Não havia piso faltando nesses pontos e nenhum piso foi alterado. Controle válido: `road-fidelity-original-control-valid-path`; duas tentativas anteriores usaram caminho incorreto e não contam como evidência.

A falha de reserva de cruzamento abaixo também foi reproduzida: `junction-ttl-baseline` passou nos controles geométricos, mas falhou em quatro dos 34 checks. Após o TTL, o registro permitiu entrada conflitante com carro ativo, pausado ou destruído ainda no miolo, e com apenas a última seção do ônibus biarticulado presente. O teste usa veículos e colisões reais; apenas o timestamp da reserva é envelhecido. Casos de saída, remoção e desnível passaram. A ampliação revelou 21 manifestações em 137 checks no original, todas corrigidas no candidato. [Evidência funcional](D:/geteco/game/evidence/performance-implementation-20261002/junction-ttl-baseline/user/GetecoV2/traffic-junction-ttl.json).

**Nona correção, de trânsito:** integrada em `TrafficJunctions`, `Vehicle` e `BiarticulatedBus`, após revisão independente e **148 checks específicos + 65 regressões existentes** (semáforos, conversão Market/Quay, lentes, entradas e lifecycle do biarticulado). As 148 verificações passaram também no principal; build .NET sem avisos/erros. Um token só continua válido se existir no registro; ao vencer, ocupação física conserva a reserva, inclusive no ônibus pela última seção. Remoção/saída libera; reconstrução do grafo preserva cruzamentos sobreviventes e mundos físicos distintos não bloqueiam uns aos outros. O custo geométrico é limitado à expiração e à liberação da traseira, sem busca física global por pedido.

O snapshot com a correção marcou 128,624 FPS, p95/p99 11,874/12,713 ms e um frame de 92,339 ms. O principal sem TTL tinha 126,224 FPS, 12,382/13,472 ms e máximo 28,708 ms. O snapshot contém wrappers desligados e eventos diferentes: não atribuir o ganho ou o pico ao TTL. A comparação final no principal está na tabela inicial; não apresentou regressão de percentis, mas a carga variou e os picos isolados permanecem. A regra conserva os limites atuais de dois eixos e chaves XZ; não é aprovação de todos os movimentos/níveis da cidade. [Contratos, limites e custos](D:/geteco/game/evidence/performance-implementation-20261002/junction-ttl-analysis.md).

**Décima segunda correção:** o token único de `Vehicle` liberava a reserva anterior ao adquirir o próximo cruzamento, mesmo com a traseira ainda no primeiro. A fixture ampliada, com veículo e colisões reais, falhou em oito de 25 checks no original e passou inteira no candidato. O veículo agora conserva somente as reservas anteriores ainda ocupadas; saída física, token perdido, mudança explícita de rota e remoção limpam corretamente essas reservas. Passaram também TTL148, conversão4 e terminal10, além dos 25 checks no principal e build .NET sem erros/avisos.

O par renderizado com apenas essa mudança em `Vehicle` marcou 124,05 → 155,66 FPS e p95/p99 12,469/13,423 → 10,854/11,902 ms. Porém pessoas/tráfego caíram de 38 para 35, unidades subiram de uma para duas e a média de carros em movimento caiu de 20,77 para 8,57. **Não atribuímos ganho de FPS; o fluxo total da cidade é inconclusivo nessa comparação dinâmica.** O candidato teve ainda um frame de 93,267 ms. A confirmação dirigida `junction-overlap-autonomous-v2` passou em **13 checks e 16,98 s**: dois veículos dirigiram normalmente, o sedan perpendicular aguardou, ambos avançaram sem reposicionamento, dano ou entrada simultânea no núcleo e todas as reservas foram liberadas em até um frame observado após a saída. A tentativa inicial tinha duas inferências de tipo inválidas na fixture e não chegou a executar; seu log foi preservado. [Reprodução, patch e limitações](D:/geteco/game/evidence/performance-implementation-20261002/junction-overlap-analysis.md).

### Interiores de veículos: cancelamento e retomada do preparo

**Décima correção:** `VehicleInterior.prewarm` marcava a família como concluída antes dos `await`. Se o veículo fosse removido durante o preparo, a família podia continuar marcada apesar de faltar a malha, impedindo uma tentativa posterior. O original falhou em sete de 31 checks; o candidato e o principal passaram nos 31. A implementação registra o dono temporário por ID, marca conclusão somente após terminar e permite retomada quando esse dono desaparece. Uma tarefa antiga não pode apagar o token de sua sucessora. Não há fila crescente de waiters nem alteração da pose/cabine.

A regressão renderizada no principal passou também nos **30 checks do embarque/desembarque normal de sport_coupe e union_sedan**, com barreira de carregamento final; os callbacks de jogo não são invocados manualmente. Build .NET sem avisos/erros. O primeiro preparo de uma família fria custou 7,891 ms distribuídos por três frames; a primeira finalização de portas, 9,921 ms. Esse diagnóstico não reproduziu a espera nativa de 52 ms e não a atribuímos ao bug de cancelamento. A primeira abertura ainda gerou um pipeline Draw: preparar materiais fora da vista não garante o desenho final. [Lifecycle no principal](D:/geteco/game/evidence/performance-implementation-20261002/live-interior-lifecycle-final/result.json), [fluxo no principal](D:/geteco/game/evidence/performance-implementation-20261002/live-seated-flow-interior-final/result.json).

### Porto: construir sem malhas intermediárias

**Décima primeira correção:** escritórios, carga solta e holofotes agora calculam as normais nos arrays CPU e criam somente a malha final. Os outros consumidores de `PortMeshOptimizer` preservam o padrão anterior. Foram 2.422 checks em 23 registros reais: geometria, colisão, materiais e normais equivalentes; pequena diferença quantizada nas tangentes de 22 das 84 superfícies, dentro da tolerância definida antes da comparação. Custo médio local de construção de 8,667 para 5,832 ms, com efeito de ordem documentado; não é ganho de FPS nem CPU exclusiva.

A Main renderizada no porto, com simulação normal e população solicitada inalterada, marcou **436,680 → 440,284 FPS**, p95 **3,728 → 3,697 ms**, p99 **4,274 → 4,161 ms**, zero frames acima de 33,3 ms nas duas janelas de 30 s. Essa região tem menos entidades que o centro; nunca comparar esses 440 FPS aos 80 do vídeo como resultado da otimização. O custo recorrente ficou estável. Três pedidos/liberações do trecho passaram em checks físicos e de descarte, com capturas examinadas. Integração guardada no principal e build .NET sem erros/avisos. O teste de identidade de materiais tinha uma falha de comparação de nulos reproduzida no original; a fixture foi corrigida sem alterar expectativas e passou nas duas variantes. [Evidências e limitações](D:/geteco/game/evidence/performance-implementation-20261002/port-cpu-analysis.md).

### Sangue: busca de contato e marcas expiradas

`BloodTracks3D` precisava apenas saber se existe uma mancha em contato, mas chamava `stains_near`, que percorria todas as manchas e construía uma lista completa. `GroundBlood3D.has_stain_near` mantém a condição geométrica original, incluindo escala e limite estrito, e retorna no primeiro contato. A API de lista permanece para seus consumidores. Marcas que já chegaram a alpha zero deixam de reenviar essa mesma cor a cada 0,25 s; o reuso do slot restaura sua opacidade normalmente.

| Carga fixa | Antes | Depois | Observação |
|---|---:|---:|---|
| 2.000 consultas, contato na primeira das 64 manchas | 43,575 ms | 1,114 ms | −97,44% neste caso |
| 2.000 consultas, contato somente na última | 42,923 ms | 43,218 ms | Sem ganho relevante |
| 2.000 consultas sem contato | 42,767 ms | 43,217 ms | Sem ganho relevante |
| 100 atualizações de 700 marcas expiradas | 5,872 ms | 0,887 ms | −84,89% |
| 100 atualizações de 700 marcas ainda no fade | 5,849 ms | 7,185 ms | +13,36 µs por chamada; custo do novo teste por slot |

São tempos CPU dos métodos, não percentuais de FPS. As **410 verificações** passaram no controle, no candidato e no projeto principal: cor, geometria, vida útil, reuso, limite de contato, escala, objetos removidos e aquisição/gasto de resíduo por distância. O teste inicialmente leu o MultiMesh antes da publicação e depois durante a interpolação. A correção da fixture aguardou dois passos físicos e desenho, preservando interpolação, expectativas e tolerâncias. [Análise e evidências](D:/geteco/game/evidence/performance-implementation-20261002/blood-optimization-analysis.md).

### Polícia: compilar apresentação durante o carregamento

A fixture renderizou a `Main`, congelou sua simulação somente para isolar as famílias visuais e exercitou corpo, arma, clarão, overlay e transparência em cinco patamares e duas séries de aparências. No controle, o primeiro corpo gerou **2 pipelines Draw e 4 Surface**; o primeiro clarão gerou outro Draw. A segunda série não repetiu esses eventos. A transparência dos corpos não produziu novos pipelines nessa fixture.

`PoliceVisualPrewarm` prepara as cinco apresentações sob a cobertura de carregamento, usando a câmera e o viewport reais. Cria somente modelos e remove seus nós antes de revelar o mundo. Índices de aparência explícitos mantêm o contador; o fallback de `RigBodySwap` agora só sorteia uma variante quando ela não foi fornecida, evitando o consumo de RNG causado pela avaliação antecipada dos argumentos de `Dictionary.get`.

Com o preparo, **Draw e Surface ficaram em zero em todas as fases posteriores**. O maior intervalo de desenho do corpo caiu de 18,941 para 2,824 ms na fixture. Ainda ocorreram especializações de background; elas não equivalem à compilação síncrona no Draw. Essa distinção segue a [documentação oficial de pipelines](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html). A comparação não atribui retrospectivamente todos os picos antigos ao mesmo shader.

Uma confirmação posterior corrigiu a barreira da fixture: aguardou também Production pronta e ausência da cobertura, com glow final ativo, contador de aparência zero e nenhum policial de gameplay previamente criado. **Draw/Surface continuaram zero nas 13 fases**, com corpo até 2,967 ms e flash até 1,708 ms. A hipótese de preparo policial incompleto pela ordem de CityLook não se confirmou nesses modelos; não alteramos o runtime com base nela. [Confirmação do ambiente final](D:/geteco/game/evidence/performance-implementation-20261002/police-visual-prewarm-results.md).

O teste funcional no projeto principal passou em **28 verificações**, incluindo perda da cobertura, câmera errada, destruição do host durante o await, remoção dos nós temporários, desconexão do sinal de desenho, reentrada e preservação do RNG e dos grupos. Build .NET: zero erros e avisos. Evidências: [antes](D:/geteco/game/evidence/performance-implementation-20261002/before-police-pipeline-fade/user/GetecoV2/police-pipeline-stages.json), [depois](D:/geteco/game/evidence/performance-implementation-20261002/after-police-pipeline-prewarm/user/GetecoV2/police-pipeline-stages.json), [ciclo de vida no principal](D:/geteco/game/evidence/performance-implementation-20261002/live-police-prewarm-lifecycle/user/GetecoV2/police-visual-prewarm-functional.json).

### Medição integrada e descoberta dos picos restantes

Mesmo hardware, Godot .NET, Mobile, 1920×1080, MSAA 2×, VSync desligado, FPS ilimitado, simulação normal e 30 s após aquecimento:

| Coleta | FPS médio | p95 | p99 | Máximo | >33,3 / >66,7 ms |
|---|---:|---:|---:|---:|---:|
| `native-cpu-chaos`, antes das duas mudanças | 103,82 | 13,803 ms | 15,003 ms | 92,159 ms | 2 / 1 |
| `remaining-callbacks-baseline`, novas fronteiras | 93,69 | 14,697 ms | 16,400 ms | 86,926 ms | 4 / 1 |
| `blood-police-prewarm-chaos` | 102,66 | 14,325 ms | 16,300 ms | 42,420 ms | 1 / 0 |
| `skate-cache-chaos` | 93,98 | 14,661 ms | 16,487 ms | 45,399 ms | 2 / 0 |
| `skate-cache-idle`, jogador parado | 118,42 | 12,922 ms | 13,863 ms | 25,337 ms | 0 / 0 |
| `reaction-prewarm-chaos` | 108,70 | 13,276 ms | 14,603 ms | 53,012 ms | 3 / 0 |

A população e os eventos variam: o último cenário chegou a quatro estrelas e seis unidades. A tabela demonstra o comportamento observado, não um ganho causal de FPS de 9,6%. As provas causais locais são as fixtures acima. A comparação com a coleta de fronteiras não apresentou aumento superior a 5% em p95/p99; isso não elimina a necessidade de medir as próximas alterações.

A sonda nativa anterior mediu a thread principal ocupada durante cerca de 96% da janela, com GPU perto de 3 ms. Nos picos de desenho de aproximadamente 50 ms, a thread executou poucos ciclos adicionais, compatível com espera/desagendamento; a causa interna não foi inferida somente do intervalo de parede. `GetThreadTimes` é quantizado nessa máquina e foi analisado em janelas contíguas, não usado para atribuir CPU de cada método curto. [Análise de sistema](D:/geteco/game/evidence/performance-implementation-20261002/native-cpu-system-analysis.md).

O registro de nós adicionados localizou outra família: frames 8132 e 10608 da coleta `blood-police-prewarm-chaos` criaram somente os 15 nós do `SkateModel`, sem novos pipelines, e apresentaram aproximadamente 15–16 ms de callbacks físicos ainda sem rótulo. O maior frame, 9367/42,420 ms, combinou essa criação com dois policiais e a primeira porta. `SkateModel._ready` reconstruía deck, trucks e quatro rodas com SurfaceTool a cada instância; somente o material de grip tinha cache.

### Skate: recursos compartilhados, pivôs independentes

O cache aplicado guarda geometria e materiais imutáveis de até **oito cores exatas**, com descarte FIFO. Cada skate mantém seus próprios nós, pivôs, rotação de rodas e transparência. A paleta de cinco cores é preparada sob a cortina, uma por frame, sem criar corpos físicos nem NPCs. Os SurfaceTools de construção são liberados depois do commit.

Nas 25 construções repetidas da mesma carga, o total CPU caiu de **430,809 para 1,642 ms**; mediana de **17,089 para 0,063 ms**. É redução de 99,619% desse trabalho local, não de todo o frame. O custo da primeira construção continua existindo e foi deslocado para o carregamento. As cinco assinaturas completas de geometria/material coincidiram; **1.904 verificações por variante** passaram. No projeto principal, passaram **154 checks** de cache/prewarm e **37 checks** existentes de física, manobras, colisão e save isolado. O primeiro teste de limpeza contou o autoload `StallLog` antes de sua remoção diferida: o inventário demonstrou apenas essa remoção, sem nós novos residuais. A fixture corrigida espera a inicialização dos autoloads antes da contagem; preserva ambas as assertions de limpeza. [Evidência detalhada](D:/geteco/game/evidence/performance-implementation-20261002/skate-cache-analysis.md).

A rodada integrada não criou novos skates durante a janela medida; por isso a prova direta do ganho de construção vem da fixture. O p95/p99 de combate variou +2,3%/+1,1%, dentro do limiar de investigação predefinido, com carga de policiais diferente. Seu maior pico adicionou um Label3D e o telefone de reação de um civil, com Surface +2; não houve atribuição nativa suficiente para concluir compilação como causa. O censo detalhado truncou 440 nomes nas grandes criações, mas não nesse pico; os contadores de frames, passos e trabalho não perderam amostras.

No cenário parado, a carga permaneceu em 38 pedestres, 48 veículos e uma unidade policial, com a mesma câmera e todos os frames focados. Os 3.553 frames em 30,004 s não passaram de 33,3 ms. Ainda existiam 39 veículos com processamento físico ao final: jogador parado não significa cidade ociosa. GPU média de 2,612 ms; nenhuma configuração visual ou limite físico foi reduzido.

### Experimento rejeitado: reatribuição de energia dos faróis

Evitar a reatribuição do mesmo multiplicador de emissão preservou o comportamento em 184 checks, mas não apresentou ganho consistente: medianas por chamada variaram −0,4% no modo desligado, +1,5% no automático e +2,1% no manual, em 12 pares AB/BA. O candidato não foi levado ao produto. [Resultados](D:/geteco/game/evidence/performance-implementation-20261002/equipment-energy-result.md).

### Hipóteses delimitadas pelas novas medições

Na coleta de trânsito, a projeção em rota ocorreu **28.948 vezes com posição exatamente repetida**, somando 151,040 ms em 30 s; média de 5,218 µs por chamada. Eliminar todo esse trabalho pouparia no máximo aproximadamente 0,084 ms por passo de 60 Hz, antes do custo de cache/invalidação. É oportunidade pequena nessa cena e não explica pausas de 117 ms. Houve **zero consultas de rotação com ângulo exatamente idêntico**; o guard sugerido pela leitura estática não demonstrou incidência nessa execução. A instrumentação adicional ficou somente no snapshot.

Outra candidata, evitar reler superfícies intactas durante o recorte das portas, teve **zero oportunidades nas três viaturas reais**. A baseline corrigida passou em 1.626 checks; o ramo redundante existe, mas não é usado por essas apresentações. A candidata de duas linhas foi descartada sem portá-la. [Análise](D:/geteco/game/evidence/performance-implementation-20261002/door-array-analysis.md).

A configuração de energia lida no Windows foi esquema Equilibrado, alimentação AC presente, bateria 100%, economia desligada e `PROCTHROTTLEMAX=99%`. A investigação adicional esclareceu a CPU híbrida: **`PROCTHROTTLEMAX1=100%` para os núcleos rápidos**, EPP 45 nas duas classes e boost configurado em modo 2. Os 91 inícios de passo da janela ruim ocorreram nos processadores lógicos 0–11, todos de classe rápida, e outra coleta registrou frequências de até 4.363 MHz nesses núcleos. Portanto, não é correto dizer que o turbo do jogo estava desligado pelos 99%. A proposta de teste global foi retirada; nenhuma configuração de energia foi alterada. [Limites por classe](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/options-for-perf-state-engine-maxperformance).

Uma captura ETW com WPR e sessão própria foi tentada, mas falhou com `0xc5585011` ao habilitar a política de perfil do sistema. Nenhuma gravação iniciou. O token disponível não anuncia `SeSystemProfilePrivilege`; a escalada do sandbox não fornece esse privilégio do Windows. Ficou preparado o [capturador nativo](D:/geteco/game/evidence/performance-implementation-20261002/capture-native-cpu.ps1), que exige terminal elevado e encerra somente sua própria sessão de WPR. Não foi executado com elevação do Windows; o script e o perfil foram validados por parsing, não por captura concluída.

A coleta `cpu99-telemetry-idle`, preservando os valores originais, teve 116,68 FPS, p95/p99 de 13,313/14,763 ms e máximo de 40,873 ms; não reproduziu a espiral de recuperação. Os contadores de processo acessíveis registraram 34,375 CPU-s nas threads do Godot e 28,125 CPU-s num serviço de sincronização do OneDrive durante aproximadamente 30 s. Isso mostra demanda concorrente, mas **não prova que ela causou a sequência anterior**. Processos protegidos sem leitura de CPU permaneceram como dados indisponíveis. A telemetria de 1 Hz não resolve causas de cada frame.

### Reações: primeiro balão e configuração final do renderizador

A fixture separou telefone, texto, repetição e sete frases usando o Presenter real na Main renderizada. O telefone não gerou pipelines novos. O primeiro balão gerou **Surface +2 e Draw +1**, com 26,494 ms no intervalo de desenho; a repetição ficou em 1,398 ms e zero pipelines.

O primeiro candidato preparava o balão antes de `CityLook` ativar glow: zerou Surface, mas **ainda gerou Draw +1** depois. Essa tentativa não foi aprovada. No Mobile, a configuração de glow altera o caminho de framebuffer, que participa da chave do pipeline. Mover o preparo para depois da configuração final do ambiente, ainda sob a cobertura de carregamento, zerou todas as cinco categorias de compilação nas **19 fases** da fixture. O primeiro intervalo de desenho ficou em **1,870 ms**; maior dos três desenhos dessa fase, 2,191 ms.

A correção aplicada extrai uma única fábrica com as propriedades originais do Label3D. `ReactionVisualPrewarm` usa essa apresentação, aguarda três desenhos e remove todos os nós, sem acionar reação, áudio ou RNG. Não mantém labels invisíveis vivos. No principal, **32 verificações de ciclo de vida** passaram e o build .NET teve zero erros/avisos. A diferença de tempos da fixture é de primeiro uso; não representa ganho recorrente de FPS. [Comparação e fonte do renderizador](D:/geteco/game/evidence/performance-implementation-20261002/reaction-visual-prewarm-analysis.md).

## Continuação: equipamentos policiais e atribuição das travadas

### Segunda melhoria aplicada

Em [PoliceModel.gd](D:/geteco/game/gameplay/PoliceModel.gd:427), a montagem dos equipamentos táticos agora usa diretamente os arrays CPU do builder. Antes, criava uma `ArrayMesh` temporária, enviava os equipamentos ao renderizador e imediatamente chamava `surface_get_arrays` para recuperá-los e anexá-los ao corpo. A leitura da malha original continua; foram eliminados somente o recurso e a transferência intermediários dos equipamentos. Chave do cache, materiais, geometria, quantidade de superfícies e ciclo de vida permanecem iguais. Não foi introduzido outro cache global.

Essa leitura pode exigir sincronização: o backend RD recupera buffers de vértices, atributos e índices por `buffer_get_data`, cuja documentação descreve a espera pelos dados. [Código Godot 4.7.2](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/storage_rd/mesh_storage.cpp#L586), [RenderingDevice.buffer_get_data](https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html#class-renderingdevice-method-buffer-get-data).

O teste renderizado comparou **36 combinações** — três patamares, seis peças e dois perfis — com a montagem original. Houve **33 primeiras montagens**; as outras já reutilizavam a mesma identidade no cache.

| Custo CPU das primeiras montagens | Original | Candidato |
|---|---:|---:|
| Soma das 33 chamadas | 62,960 ms | 29,803 ms |
| Média por chamada | 1.907,88 µs | 903,12 µs |
| Mediana | 1.457 µs | 651 µs |
| Maior chamada | 5.730 µs | 2.470 µs |

**Redução de 52,66% na soma dessa carga fixa.** Isso mede o método de montagem, não todo o nascimento do policial nem uma porcentagem de ganho de FPS. Trinta e duas chamadas pareadas ficaram mais rápidas; uma passou de 2.381 para 2.470 µs. A reutilização de cache já custava poucos microssegundos e não fundamenta alegação adicional de ganho.

[test_police_equipment_geometry.gd](D:/geteco/game/tests/test_police_equipment_geometry.gd) passou em **646 verificações em cada versão**, incluindo captura. Posições, índices e cores coincidiram; a diferença máxima de normais foi 0,000121639, dentro da tolerância previamente definida para a quantização, sem mudar os slots do material. Foram preservados superfícies adicionais, recursos compartilhados, transformações, cache e limpeza. A [comparação renderizada](D:/geteco/game/evidence/performance-implementation-20261002/after-police-equipment-geometry/user/GetecoV2/police-equipment.png) mostra original à esquerda e candidato à direita de cada par. O teste existente de [poses policiais](D:/geteco/game/tests/police_response/test_officer_poses.gd) passou em **101 verificações**, cobrindo todos os patamares, mãos/armas, recarga e rapel. Build .NET do principal após portar: zero erros e zero avisos.

Evidências: [controle](D:/geteco/game/evidence/performance-implementation-20261002/before-police-equipment-geometry/stdout.log), [candidato](D:/geteco/game/evidence/performance-implementation-20261002/after-police-equipment-geometry/stdout.log), [poses](D:/geteco/game/evidence/performance-implementation-20261002/after-police-equipment-poses/stdout.log). Após portar, o teste de geometria passou novamente no [projeto principal](D:/geteco/game/evidence/performance-implementation-20261002/live-police-equipment-geometry/stdout.log): **645 verificações**, sem executar a verificação opcional de salvar captura.

### Coleta ampliada na cena real

Apenas no snapshot, o rastreador recebeu contagem, total e máximo por rótulo, incluindo chamadas abaixo do limiar anterior. Sentinelas enquadram os callbacks de cada passo físico, sem chamar manualmente a simulação. O relatório registra relógios absolutos, fim dos callbacks de processamento e sinais antes/depois do desenho. Esses intervalos são tempos de parede: não constituem medição exclusiva de CPU/GPU, e os callbacks não incluem o solver nativo que roda fora deles. Rótulos pai/filho são inclusivos e não devem ser somados.

Ativação do diagnóstico: `HARBOR_STALL_AGGREGATE=1` e runner `-Stall`. Os cinco arquivos instrumentados do snapshot não foram portados para o runtime principal. A coleta guarda no máximo 12.000 frames, 32 passos pendentes e 128 rótulos, com descartes explícitos. Os números abaixo têm essa instrumentação e não devem ser comparados diretamente aos benchmarks anteriores sem ela.

| Cena de combate, 30 s | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 ms | >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| `remaining-chaos-diagnostic-before` | 73,99 | 13,040 | 19,435 | 39,892 | 908,821 | 40 | 10 |
| `remaining-chaos-diagnostic-after` | 93,59 | 12,296 | 15,118 | 18,294 | 87,806 | 2 | 1 |
| `remaining-spawn-boundaries` — quatro spans extras | 84,53 | 12,448 | 16,559 | 34,512 | 154,041 | 28 | 18 |

As duas rodadas foram válidas, focadas e sem outro jogo/teste Godot concorrente. Carga média: 24,45 → 25,43 civis; 24,41 → 25,43 veículos ambiente; 4,83 → 5,00 unidades de despacho. Entretanto, decisões, trajetórias e eventos continuaram variando: foram **3.089 contra 899 chamadas físicas de policiais a pé**, diferença importante que a contagem de viaturas não revela. **O pico de 909 ms ocorreu em um detetive (`tier1`), que não usa a montagem tática alterada. Sua ausência na rodada seguinte não comprova que o patch resolveu aquela trava.** O resultado controlado de 52,66% é a evidência direta do ganho local.

### O que agora sabemos sobre as travadas

No controle, o frame **7957, de 908,821 ms**, contém oito passos físicos. O primeiro dura **747,120 ms**; dentro dele, `officer.spawn:tier1` ocupa **730,635 ms**, aninhado em cerca de 735 ms do controlador de despacho. O escopo de `spawn_officer` inclui tanto a construção do personagem quanto `begin_disembark`, que pode terminar a porta sincronamente. O span ainda não permite escolher entre esses dois trechos.

A sequência já vinha crescendo antes: frames 7949–7956 passaram de dois para quatro passos, incluindo um passo de 50,237 ms ainda sem trecho dominante. Portanto, a criação/desembarque explica o **maior pico dessa coleta**, mas não demonstra o primeiro gatilho de toda a sequência. Depois, vários frames acumulam oito passos e aproximadamente 88–117 ms de callbacks físicos: recuperação acumulada demonstrada, não hipótese baseada só em FPS. O Godot documenta esse mecanismo e também os efeitos de reduzir o limite; nenhuma mudança no limite de oito passos ou nos 60 Hz foi aplicada. [ProjectSettings: passos físicos](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-physics-common-max-physics-steps-per-frame).

Também foram encontrados picos independentes concentrados entre os sinais de desenho: aproximadamente **94,207 e 83,893 ms**, com tempo GPU do viewport próximo de 4,5 ms. Há atividade de pipelines registrada, mas isso não prova sozinho compilação como causa. A categoria correta é custo/espera no caminho de desenho, ainda sem atribuição nativa definitiva.

No controle, os 2.220 intervalos da instrumentação coincidiram exatamente com a série de frames, sem descartes ou divergências de contagem de passos. O empacotamento da amostra custou em média 13,5 µs, p95 20 µs e máximo 227 µs; isso **não inclui** o custo dos contadores adicionados a cada chamada.

Outra limitação foi identificada: `DispatchTrace` filtra chamadas abaixo de 20 ms antes de encaminhá-las ao `StallWorkTrace`. Os agregados capturam as chamadas curtas que chegam ao rastreador, mas não recuperam as descartadas nessa etapa anterior. Assim, zero em um rótulo de despacho não significa zero trabalho. A coleta dirigida seguinte usa quatro spans diretos para construção/configuração, `add_child`/`_ready`, colisão/posição e `begin_disembark`, fechando essa lacuna em `spawn_officer`.

### Resultado da coleta dirigida final

`remaining-spawn-boundaries` foi válida, sem outro jogo/teste, com todos os 2.536 frames focados e nenhum frame descartado. Médias: 27,6 civis, 27,6 veículos ambiente e 3,83 unidades de despacho. A média de GPU foi 3,39 ms. Os resultados piores que a primeira rodada do candidato foram mantidos na tabela: **84,53 FPS, p99 34,512 ms e pico 154,041 ms**. Não são descartados nem usados para declarar estabilidade.

Não houve spawn durante os dez segundos de aquecimento registrados; durante a medição ocorreram três. Os quatro spans diretos mediram:

| Etapa | Soma das três chamadas | Maior chamada |
|---|---:|---:|
| Construção/configuração | 0,120 ms | 0,043 ms |
| Inserção na árvore e `_ready` | 5,555 ms | 1,893 ms |
| Colisão/posicionamento | 0,035 ms | 0,012 ms |
| `begin_disembark`, incluindo porta | 12,959 ms | 12,902 ms |

O maior custo observado nesse grupo foi a etapa de desembarque, mas **não reproduziu o evento de 730,635 ms e não determina retroativamente sua causa interna**. Além disso, a sequência de atraso da rodada final ocorreu aproximadamente entre 21,26 e 23,51 s do cenário; os spawns vieram depois, por volta de 23,95 e 25,03 s. No frame de 154,041 ms, oito passos somaram 123,610 ms entre os callbacks, sem chamada isolada dominante. Logo, essa sequência não foi iniciada pela criação desses policiais.

Próxima investigação de maior valor: perfil nativo/CPU com fronteiras de renderização e dos passos físicos para localizar custos ainda não cobertos, esperas e agendamento, especialmente nos frames que antecedem o acúmulo. Repetir somente o contador de FPS não discrimina essas hipóteses. Uma alteração global de física, redução de população ou nova arquitetura de portas ainda não possui evidência suficiente de causa e equivalência para ser aplicada como solução dessas travadas.

A [análise detalhada](D:/geteco/game/evidence/performance-implementation-20261002/remaining-diagnostic-analysis.md) contém a atribuição temporal e seus limites. As séries estão em [controle](D:/geteco/game/evidence/performance-implementation-20261002/remaining-chaos-diagnostic-before/remaining-chaos-diagnostic-before.json), [candidato](D:/geteco/game/evidence/performance-implementation-20261002/remaining-chaos-diagnostic-after/remaining-chaos-diagnostic-after.json) e [fronteiras do spawn](D:/geteco/game/evidence/performance-implementation-20261002/remaining-spawn-boundaries/remaining-spawn-boundaries.json).

**Fechamento desta etapa:** segunda otimização portada e validada, sem reduzir qualidade ou mudar comportamento. Persistem picos e custo acumulado por passo físico; performance global continua não aprovada. A instrumentação adicional fica restrita à cópia de diagnóstico. Não foram feitas mais rodadas até obter um resultado favorável.

### Portas e outras frentes delimitadas

- **Desembarque policial:** `DispatchController.spawn_officer` → `DispatchOfficer.begin_disembark` → `Vehicle.animate_driver_door` → configuração/finalização síncrona. O preparo de `warm_doors(2500)` é usado pelo `Driving` para o carro próximo do jogador; não prepara automaticamente as viaturas que vão desembarcar. O prewarm da frota cria/desenha modelos do catálogo, mas não esse ciclo de portas nem o `PoliceModel` completo.
- **Orçamento incompleto:** `VehicleDoorBuilder.step` verifica o prazo depois de `_cut_part`; uma peça grande pode exceder sozinha os 2,5 ms. Preparar durante a aproximação e admitir o policial apenas quando a porta estiver pronta exige preservar a sequência do desembarque e a aplicação atômica do recorte. Só antecipar `warm_doors` não garante esse teto.
- **Readback repetido nas portas:** uma superfície intacta já foi lida na primeira passagem, mas `rebuilt.append(null)` provoca nova leitura ao reconstruir outra superfície da mesma peça. Reter aquele array localmente pode evitar a segunda leitura, sem cache global ou compartilhar pintura entre carros. Ainda não implementado nem medido separadamente.
- **Equipamento dos veículos:** centros de superfícies e teto da cabine já possuem caches. O `_refresh` contínuo permanece um custo separado; não faz esses readbacks e não deve ser confundido com a primeira construção.

Correção de interpretação do perfil antigo: os 27,583 ms de `Mesh.surface_get_arrays` exibidos sob o nome `VehicleDoorBuilder` não podem ser todos atribuídos às portas. A entrada nativa agrega chamadas e supera o custo inclusivo do próprio `_cut_part` naquele frame. A leitura temporária dos equipamentos policiais também participava desse tipo de operação; o teste isolado acima é a evidência apropriada para a correção aplicada.

## Primeira melhoria: marcas de pneus e medições iniciais

### Resultado demonstrado

[VehicleTireEffects.gd](D:/geteco/game/gameplay/vehicle_effects/VehicleTireEffects.gd:297) passa a montar arrays de vértices, normais e cores e enviá-los em um upload por redesenho. Antes, cada segmento criava arrays temporários e fazia 18 chamadas individuais de malha. A mudança preserva os seis vértices e sua ordem, material, cores, normais, largura, fade, frequência de 0,1 s, limite de 320 segmentos e limpeza. Não reduz população, efeitos, qualidade gráfica ou frequência da física.

Com **320 segmentos fixos**, dez redesenhos de aquecimento e cem medidos no mesmo teste renderizado, o tempo CPU médio do método caiu de **949,09 para 416,29 µs: redução de 56,1%**. É uma medida do método, não uma porcentagem de ganho de FPS ou tempo GPU. O profiler da cena real havia apontado cerca de **1,204 s cumulativos em redesenho durante 30 s**, dos quais 929 ms próprios; `VehicleTireEffects` inteiro somava 2,098 s inclusivos. Não somar pais e filhos do perfil.

A mudança foi aplicada no projeto principal. [O novo teste de geometria](D:/geteco/game/tests/test_tire_mark_geometry.gd) passou em **62 verificações**, tanto com a implementação original quanto com a nova. [O teste dos efeitos](D:/geteco/game/tests/test_vehicle_effects.gd) passou em **40 verificações** nas duas versões e novamente no projeto principal após portar. O build .NET do principal passou com zero erros e zero avisos. A tipagem de um `WeakRef` no teste novo precisou ser corrigida antes da execução válida; nenhuma expectativa foi afrouxada.

A validação visual renderizada acompanhou 72 marcas de asfalto, terra, neve e grama, com capturas em 0, 3, 6,5 e 10,5 s nas duas versões. As marcas permaneceram fixas enquanto o proprietário se movia; cores/fade e desaparecimento final foram preservados. Ambas terminaram com zero marcas e malha invisível. Essa fixture visual não é benchmark de FPS.

### Ambiente e método

- Godot **4.7.2 .NET**, renderer **Mobile**, i7-13650HX e RTX 4060 Laptop, 1920×1080, MSAA 2×, escala 100%, VSync desligado e FPS ilimitado, conforme as preferências locais copiadas para armazenamento isolado.
- Física a 60 Hz, limite original de oito passos por frame. Nenhum ajuste desses parâmetros foi portado.
- Cena `Main.tscn`, região Union/Ammu-Nation, jogador estacionário em `(107, 0, 23)`, câmera alternativa e horário controlado. Não é reprodução completa do congestionamento, fogo e helicóptero do vídeo.
- O argumento `--population=100` é limitado pelo produto a **40 civis ambiente**. O tráfego ambiente também tem teto 40, separado dos veículos especiais. NPCs de rotinas/despacho não estão todos em `world.people`.
- Após posicionar o jogador, o medidor espera população e tráfego atingirem os **tetos dinâmicos efetivos**, além de streaming/descarte terminarem. Seguem dez segundos de aquecimento e pelo menos trinta segundos de intervalos reais. Emergências autônomas podem reduzir os tetos antes mesmo do estímulo de combate.
- Combate usa arsenal, invulnerabilidade e disparos pela API produtiva, iniciados após estabilização; decisões, movimento, colisões, reações e despacho continuam ativos. É cenário de diagnóstico, não teste completo dos controles do jogador.
- Fonte e configuração são registradas por execução. Um monitor encerra apenas o processo próprio se aparecer outro Godot executando jogo/teste. Uma rodada foi abortada por essa condição e não entrou nos resultados. O editor existente ficou aberto durante o conjunto; não houve execução concorrente de jogo/teste nas rodadas válidas.
- No último par, a direção de mira foi fixada pelo caminho de controle. Antes disso, `FullSession` ainda consultava o mouse mesmo com os callbacks de input desativados. A câmera continua com a antecipação normal da mira e pode variar com disparo/recarga; não é câmera artificialmente congelada.
- Todos os frames das sete amostras maduras abaixo estavam com a janela focada. Não houve falha de runtime nos logs. Os 18 registros do receiver de profiler eram avisos de carregamento, anteriores à amostra.

O medidor está em [measure_performance_plan.gd](D:/geteco/game/tests/measure/measure_performance_plan.gd). Execuções e resultados estão em [performance-implementation-20261002](D:/geteco/game/evidence/performance-implementation-20261002); o runner é [run.ps1](D:/geteco/game/evidence/performance-implementation-20261002/run.ps1). Usa cópia compilada, `--no-save` e APPDATA/LOCALAPPDATA exclusivos. As séries de frames, estados, configuração, hashes, capturas e validade estão nos diretórios com os nomes das rodadas abaixo.

### Todas as amostras maduras sem profiler

Tempos em milissegundos; FPS = quantidade de frames / duração total. Cada linha cobre cerca de 30 segundos.

| Rodada | FPS médio | p50 | p95 | p99 | Máximo | >33,3 ms | >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| `before-idle-mature` | 117,13 | 10,196 | 13,115 | 14,061 | 89,873 | 1 | 1 |
| `after-idle-mature` | 126,53 | 5,733 | 12,340 | 13,623 | 84,962 | 1 | 1 |
| `before-chaos-mature` | 93,60 | 12,259 | 14,509 | 16,452 | 116,646 | 3 | 1 |
| `after-chaos-mature` | 81,23 | 12,237 | 16,726 | 50,278 | 1049,315 | 32 | 21 |
| `after-chaos-confirm` — rastros ativos | 103,94 | 11,327 | 14,100 | 16,659 | 96,490 | 2 | 1 |
| `before-chaos-fixed-aim` — mira controlada + rastros | 81,98 | 12,283 | 16,851 | 44,198 | 199,652 | 40 | 20 |
| `after-chaos-fixed-aim` — mira controlada + rastros | 110,16 | 10,740 | 13,555 | 15,477 | 85,327 | 2 | 1 |

**Não interpretar 81,98 → 110,16 como ganho causal de 34%.** A carga autônoma variou mesmo com a seed global fixa. No último par, as médias amostradas foram 25,5 → 27,7 civis, 25,5 → 27,4 veículos ambientes e 5,3 → 4,3 unidades de despacho. No idle, houve 40 civis/zero unidades antes, contra 35 civis/duas unidades depois. Assim, os números são observações integradas e evidência de ausência de regressão reproduzível atribuída ao patch neste conjunto; não isolam uma porcentagem global de ganho.

A primeira amostra `baseline-idle` deu 180,32 FPS, mas media o preenchimento de 0 para cerca de 34 civis. Ela foi mantida como diagnóstico inicial e **não usada para comparar a otimização**. A amostra `profile-chaos-mature` deu 51,93 FPS com instrumentação; também não é comparada diretamente às rodadas sem profiler. A documentação alerta para o custo do profiler. [Godot CPU optimization](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html).

Os tempos médios GPU do viewport foram aproximadamente 2,65 → 2,43 ms no par idle e 3,38 → 2,78 ms no último par de combate. Isso deixa margem nesse viewport, mas não mede toda espera do frame. Os monitores `TIME_PROCESS` e `TIME_PHYSICS_PROCESS` representam máximos do segundo anterior repetidos pela amostragem; não são médias de CPU por frame/passo. O total inclusivo da coroutine `run` foi descartado do ranking, pois incorpora os `await`.

### Travadas e trabalho ainda necessário

O candidato teve uma rodada ruim, incluindo **1049 ms**, preservada na tabela. Esse pico de um segundo não se repetiu nas confirmações e continua sem causa isolada. Também houve sequência grave no **original**: entre aproximadamente 99,08 e 101,51 s do [StallLog do controle](D:/geteco/game/evidence/performance-implementation-20261002/snapshot/evidence/stall-logs/stalls-20261002-181842.log), vários frames consumiram 140–198 ms com **6–8 passos físicos por frame**. Corpos e pares de colisão permaneceram relativamente estáveis. Isso demonstra amplificação por recuperação de passos físicos, mas não identifica o gatilho inicial.

Nenhum span registrado explica sozinho aquela sequência. Tempo ausente dos spans pode ser soma de trabalho curto, trecho sem instrumentação, trabalho nativo ou espera externa. Picos de serialização do relatório e readback da captura **posteriores ao fim da janela** foram excluídos das conclusões de gameplay. O perfil anterior também revelou criação/combinação de modelos e readback de malhas durante a partida, incluindo cerca de 27,6 ms em `surface_get_arrays`; é uma frente distinta do custo contínuo dos pneus.

Prioridades atualizadas:

1. **Concluído:** montagem em lote das marcas de pneus, com equivalência e redução de custo do método demonstradas.
2. **Próximo diagnóstico:** capturar o início da sequência de atraso com perfil nativo/CPU e duração por passo físico, distinguindo criação, espera e soma de callbacks. Avaliar recuperação com limites de passos apenas como experimento: alterar o limite global pode afetar avanço da simulação e não foi implementado.
3. **Parcialmente concluído na continuação:** eliminada a malha intermediária dos equipamentos táticos, com redução de 52,66% no teste de primeiras montagens. Construção/desembarque de policiais e custo das portas continuam exigindo atribuição separada; ver a seção de continuação acima.
4. **Candidatos menores:** consultas booleanas de manchas de sangue (a lista inteira é criada só para saber se existe contato), cache exato de projeção do carro imóvel e consulta de giro apenas quando o ângulo muda. Seus custos aparecem no perfil, mas não foram misturados ao patch validado.
5. Terreno natural opaco: incidência na Union não demonstrada; permanece prevenção do editor, não causa comprovada deste vídeo.

**Estado da entrega:** patch local aplicado e validado funcionalmente, visualmente e quanto ao custo CPU do método. FPS renderizado medido, com variabilidade e falhas preservadas. Performance global **não aprovada**: ainda existem travadas gerais sem causa isolada. Não foram certificados todos os mapas, interiores, transições, noite/chuva, save/load ou o caos completo com incêndios/helicóptero. As recomendações de arquitetura seguintes continuam propostas, não alterações já implementadas.

## O que o vídeo demonstra

O arquivo tem 64,73 segundos, 1924 × 1244 pixels e gravação a 30 quadros por segundo. A taxa de captura não é o FPS do jogo. A região observada é a rua da Union e da Ammu-Nation, com tráfego congestionado, serviços de emergência e busca/perseguição; depois aparecem tiros, incêndios e helicóptero. Personagem imóvel não significa simulação ociosa.

| Momento aproximado | Leitura visível do contador | Contexto e limite |
|---|---|---|
| 1 s | 61 FPS, pico de 35,8 ms | Cruzamento com fila de veículos |
| 13 s | 15 FPS, pico de 199,0 ms | Editor sobreposto; troca de foco/profiler impede tratar como amostra isolada |
| 22 s | 16 FPS, pico de 73,9 ms | Jogo visível, perseguição e veículo em chamas |
| 40 s | 52 FPS, pico de 33,8 ms | Deslocamento por outro trecho |
| 55 s | 90 FPS, pico de 65,8 ms | Próximo da água/helicóptero |

São leituras pontuais do overlay, não médias ou percentis calculados do vídeo. O contador é atualizado aproximadamente a cada segundo e o “pico” é o maior intervalo observado nessa janela: [Settings.gd](D:/geteco/game/runtime/Settings.gd:174).

O problema observado é mais amplo do que “80 FPS parado”: há grande variação e picos longos. O vídeo não permite afirmar se cada queda veio da CPU, GPU, criação de recursos, captura ou depuração. Na imagem do analisador gráfico por volta de 10,4 s, o quadro selecionado mostra aproximadamente 3,16 ms de CPU de renderização e 4,87 ms de GPU do viewport. Isso não representa toda a CPU do jogo nem pode ser associado automaticamente ao FPS simultâneo do overlay.

80 FPS equivalem a 12,5 ms por frame; 120 FPS exigem 8,33 ms, e 144 FPS exigem 6,94 ms. Por isso, obter margem exige reduzir trabalho real. Um teto de FPS ou uma média alta não resolve travadas. A documentação distingue explicitamente custo contínuo, picos e carregamento. [Godot General optimization](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html).

As preferências locais lidas estavam em 1920 × 1080, VSync desligado, FPS ilimitado, MSAA 2×, escala 3D de 100%, sombras baixas e câmera alternativa. São as preferências presentes durante a auditoria, não uma prova de todos os parâmetros da gravação. `Settings.gd` sobrescreve os padrões de `project.godot`; portanto, o limite de 60 do projeto não explica sozinho o vídeo.

## Onde começar

“Alta” indica ordem proposta de investigação/correção, não ganho medido. A confiança no comportamento do código e a confiança em seu impacto no FPS são coisas diferentes.

| Ordem | Frente | Motivo |
|---|---|---|
| 1 | Tráfego parado, projeção em rotas e consultas físicas redundantes | Trabalho contínuo diretamente relacionado ao congestionamento visível |
| 2 | Consultas locais de pessoas e repouso físico de NPCs | Custos multiplicados pelo número de entidades |
| 3 | Organização de instâncias e transparência onde houver consumidor visível | Precisa censo runtime e A/B da cena afetada; shader natural não demonstrado na Union |
| 4 | Streaming e primeira criação de modelos/colisões | Unidades indivisíveis podem provocar travadas apesar da fila |
| 5 | Ocupação de cruzamentos e recuperação do caos | Correção funcional pode reduzir acúmulo de contatos e decisões |
| 6 | Save, inventário e crescimento de recibos | Travadas de interação e risco independente de falha ao salvar |
| 7 | LOD, iluminação, shaders, renderer e física alternativa | Experimentos dirigidos pelo perfil depois das frentes anteriores |

## Simulação e física

**Carros refazem a busca global na curva da rota.** [Vehicle.gd](D:/geteco/game/scripts/Vehicle.gd:685) usa `get_closest_offset` em cada passo executado; o despacho também o usa em [DispatchDriver.gd](D:/geteco/game/gameplay/dispatch/DispatchDriver.gd:177). A implementação oficial consultada percorre os segmentos da curva, embora a revisão consultada não seja uma análise do binário local. [Fonte do Godot](https://github.com/godotengine/godot/blob/master/scene/resources/curve.cpp).

Proposta: guardar o segmento/progresso anterior e pesquisar uma janela local; recorrer à busca completa quando a rota muda, há teleporte ou desvio grande. O progresso precisa continuar baseado na posição física real. Avançar apenas pelo velocímetro permitiria que um carro bloqueado progredisse ficticiamente.

**O repouso da fila ocorre tarde.** A saída antecipada de [Vehicle.gd](D:/geteco/game/scripts/Vehicle.gd:370) vem depois de `_drive_traffic`. O carro pode evitar movimento físico e ainda repetir geometria de rota e decisões. Separar sensores/sinalização, planejamento e movimento; reutilizar resultados quando a posição não mudou. O despertar deve reagir a abertura do sinal, movimento do veículo à frente, colisão e cessão de passagem.

**Há consulta de rotação mesmo seguindo reto.** Em [Vehicle.gd](D:/geteco/game/scripts/Vehicle.gd:716), `can_rotate(next_yaw)` é chamado quando a velocidade supera 0,2, sem exigir mudança angular. O caminho de direção do jogador já verifica alteração relevante do giro. Aplicar condição equivalente ao tráfego é candidato localizado; validar manobras apertadas, ré, paredes e contato entre veículos.

**Cada carro procura pessoas numa lista global.** [StreetPhysics.gd](D:/geteco/game/gameplay/street_physics/StreetPhysics.gd:114) percorre `_people_cache` para decidir se fará a varredura física de atropelamento. No pior caso, o trabalho cresce como veículos × pessoas. Criar um índice espacial compartilhado para consultas próximas, ou comparar uma consulta física filtrada com o laço atual. A escolha deve preservar pessoas caídas, proteção de personagens, colisão contínua e alcance de caminhões.

**Subir meio-fio custa uma consulta adicional por pedestre em movimento.** [PedestrianStep3D.gd](D:/geteco/game/gameplay/crowd/PedestrianStep3D.gd:8) cria `KinematicCollision3D` e executa `test_move`; o [Actor.gd](D:/geteco/game/scripts/Actor.gd:216) ainda faz `move_and_slide`. Reutilizar o resultado/objeto e avaliar ativação contextual pode reduzir trabalho. Não remover a proteção indiscriminadamente: o teste precisa manter acesso a calçadas e impedir que NPCs subam móveis.

**Parte das rotinas simula contato com o chão mesmo em repouso.** [V1RoutineActor.gd](D:/geteco/game/gameplay/routines_v1/V1RoutineActor.gd:110) e [UrbanRoutineActor.gd](D:/geteco/game/gameplay/urban_v1/UrbanRoutineActor.gd:113) mantêm movimento físico em estados de trabalho/descanso. Separar repouso físico de animação e despertar com reação, apoio alterado, impacto ou transição. Um NPC pode continuar respirando e trabalhando visualmente sem refazer locomoção integral.

## Reações, navegação, combate e trânsito

A arquitetura de reações já separa percepção, decisão, movimento e apresentação. Existe fila justa e orçamento de raios; a navegação policial também tem orçamento incremental. O problema restante é que cada sistema decide seu limite independentemente.

- [CivilianReactionDirector.gd](D:/geteco/game/gameplay/civilian_reactions/CivilianReactionDirector.gd:167) verifica vida/referências e procura buzinas em listas periodicamente. [StreetPhysics.gd](D:/geteco/game/gameplay/street_physics/StreetPhysics.gd:434) volta a verificar população/vida. Um registro compartilhado e eventos explícitos de dano, morte e buzina evitariam inferências duplicadas. Não transformar todos os sinais em processamento imediato pesado.
- [LocalGridPathSearch.gd](D:/geteco/game/gameplay/navigation/LocalGridPathSearch.gd:46) extrai o menor custo percorrendo a fronteira e usa busca linear de pertencimento. Heap e conjunto são candidatos, depois de separar esse custo das consultas físicas. A busca já possui limites; não é correto classificá-la como ilimitada.
- `duplicate/filter` em [DispatchController.gd](D:/geteco/game/gameplay/dispatch/DispatchController.gd:140) e [DispatchUnit.gd](D:/geteco/game/gameplay/dispatch/DispatchUnit.gd:333) criam trabalho contínuo. Como as listas são limitadas, são candidatos secundários; não culpar “GC” sem perfil.
- [RoadGraphSearch.cs](D:/geteco/game/gameplay/dispatch/RoadGraphSearch.cs:301) copia arrays no resultado; a construção da curva atravessa repetidamente a fronteira C#/motor. Manter estruturas internas .NET e passar resultados em lote é a direção indicada se aparecer no perfil. [Coleções C# no Godot](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/c_sharp_collections.html).

Há riscos funcionais na ocupação dos cruzamentos:

1. **Corrigido e reproduzido na continuação:** a reserva expirava após nove segundos mesmo com ocupação física, enquanto o token local podia sobreviver. Agora a ocupação conserva a reserva e os tokens são reconciliados, com 148 checks específicos no principal. Isso confirma o defeito, mas não atribui retrospectivamente a fila do vídeo a ele. A perda de uma reserva anterior ao entrar em outro cruzamento próximo também foi reproduzida e corrigida: cada reserva permanece até a traseira liberar sua própria área. Os contratos locais passaram; fluxo e conflitos de conversão na cidade inteira continuam pendentes.
2. O conflito é representado por dois eixos, não por trajetórias completas. Conversões conflitantes do mesmo eixo precisam de zonas de conflito ou matriz de movimentos.
3. Chaves/proximidade dos semáforos descartam a altura, enquanto o grafo viário preserva Y. Verificar cruzamentos sobrepostos; ainda não há local afetado demonstrado.
4. [NativeTrafficRoutes.gd](D:/geteco/game/gameplay/NativeTrafficRoutes.gd:20) infere mão única pelo nome do trecho. Sentido, nível e movimentos permitidos devem ser dados explícitos do editor e do grafo.

Não há evidência suficiente para declarar vazamento de incêndios, ambulâncias ou helicópteros. O código possui limites e limpeza. A auditoria de execução necessária é crime → perseguição → colisões/fogo → emergência → cessação → dispersão/retorno, medindo entidades residuais, contatos, memória e tempo de recuperação.

## Renderização, iluminação e terrenos

**O solo chamado de opaco usa shader transparente.** [WorldGroundFactory.gd](D:/geteco/game/world/editing/WorldGroundFactory.gd:33) usa `natural_ground.gdshader` para terra, grama, areia e cascalho. O shader escreve `ALPHA` em [natural_ground.gdshader](D:/geteco/game/world/regions/natural_ground.gdshader:110), dentro de uma condição uniforme. A seleção da pipeline considera o uso de ALPHA; desligar `edge_alpha` não cria uma variante opaca. A documentação confirma essa regra. [Spatial shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html).

Separar o miolo opaco das bordas transparentes é uma correção estrutural potencial. A revisão posterior do mapa atual não localizou consumidor visível de `edge_alpha=false`: o único ground editado é concreto; a malha natural de estrada criada em NativeRegion fica escondida; a serraria visível usa `edge_alpha=true` e precisa das bordas. Portanto, esta frente fica como prevenção para o editor, com incidência atual não demonstrada. Não atribuir a queda da Union a esse shader nem modificar a serraria para obter FPS.

**Recursos compartilhados não equivalem a poucas chamadas de desenho.** [NativePine.gd](D:/geteco/game/world/regions/NativePine.gd:6) compartilha meshes/materiais, mas cria instâncias por árvore/material. O renderer Mobile não oferece o batching automático de MeshInstances disponível no Forward+. Usar MultiMesh por chunk/material/família para decoração repetida, mantendo colisores e interações adequados. [Otimização 3D](https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html).

**Um lote grande demais também desperdiça trabalho.** [MountainRoadside3D.gd](D:/geteco/game/world/mountain_detail/MountainRoadside3D.gd:131) agrega os postes da região em quatro MultiMeshes. O descarte por visibilidade ocorre no grupo, não em cada poste. Dividir por trecho espacial e medir o equilíbrio entre instâncias invisíveis e chamadas adicionais. [MultiMesh](https://docs.godotengine.org/en/stable/classes/class_multimesh.html).

**Há cálculo procedural estático por pixel.** Terrenos repetem ruídos e diferenças finitas para normais. Comparar versões com texturas de ruído/normal pré-calculadas e informação de cobertura por chunk; manter escala, mistura, neve e emendas. Não substituir o material por uma cor lisa para obter um número melhor.

**LOD visual ainda é parcial.** Há LOD no Dante importado e faixas de visibilidade em pontos específicos, mas não uma política equivalente para todas as famílias procedurais. Avaliar LOD em árvores, props e veículos distantes. Occlusion culling não foi encontrado como política ativa nos caminhos pesquisados; testar em prédios/interiores/túneis, considerando o custo na CPU e a câmera elevada. [Occlusion culling](https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html).

**Iluminação já tem contenção.** A cidade usa pool de seis luzes locais, a montanha oito, com seleção periódica; faróis têm atenuação por distância e não usam sombras. Não encontrei evidência para culpar centenas de fontes simultaneamente ativas, ray tracing ou SubViewports por carro na V2. Ainda falta medir sombras solares, chuva, fogo, faróis e sobreposição noturna. No Mobile, limites de luz por mesh tornam grandes lotes/chãos importantes também para estabilidade visual. [Renderers do Godot](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html).

## Streaming, assets e primeira visita

A fila de [NativeRegion.gd](D:/geteco/game/world/regions/NativeRegion.gd:492) recebe aproximadamente 1–2 ms por frame, mas `_build_surfaces` e `_build_record_cached` executam unidades inteiras antes de conferir o tempo. Um orçamento cooperativo não interrompe uma etapa cara.

Preparar meshes/colisões autoradas como recursos de importação; dividir etapas procedurais em partes retomáveis; limitar também montagem, upload e descarte. Separar construção inicial, visita fria, retorno com cache e regime estável.

O caso do navio merece medição específica: [NativeRegion.gd](D:/geteco/game/world/regions/NativeRegion.gd:816) pula o cargo no aquecimento, [HarborPortModel3D.gd](D:/geteco/game/assets/regions/source/world/harbor/HarborPortModel3D.gd:222) gera contêineres e normais, e [OriginalSouthPort.gd](D:/geteco/game/world/regions/OriginalSouthPort.gd:42) gera colisão ao montar. Existe cache de mesh: o comentário histórico de 1,7 s não é prova de travada atual em toda visita.

[MountainGrass3D.gd](D:/geteco/game/world/mountain_detail/MountainGrass3D.gd:110) pode considerar até 648 candidatos em dois tiles por tick e fazer raycasts para os candidatos restantes após exclusões. Dar orçamento por tempo/cursor e cache por versão do terreno. É risco de travada ao avançar, não explicação automática para custo contínuo parado.

Threads podem preparar dados puros e buffers. Alterar a SceneTree ativa ou mandar toda a física para workers indiscriminadamente não é uma solução segura. A montagem e os recursos compartilhados exigem cuidado. [Thread-safe APIs](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html).

## Áudio, UI, inventário e persistência

**Áudio:** [EngineBankCache.gd](D:/geteco/game/audio/EngineBankCache.gd:55) chama `load_threaded_get` inclusive em `THREAD_LOAD_IN_PROGRESS`. A chamada pode esperar a carga terminar. O prewarm reduz a exposição, mas não é uma garantia universal para o primeiro consumidor. Só consumir banco pronto; ter uma família já disponível como transição e trocar sem estalo quando a correta terminar. [Background loading](https://docs.godotengine.org/en/stable/tutorials/io/background_loading.html).

**HUD e menus:** já há frequência limitada, minimapa cacheado e desligamento de prévias ao fechar. Procurar mudança de estado real antes de reconstruir listas, ícones ou textos. Não há prova de que o HUD seja o principal gargalo. [ContextualHUDManager.gd](D:/geteco/game/ui/hud/ContextualHUDManager.gd:87) e [HarborMinimap3D.gd](D:/geteco/game/ui/v1/HarborMinimap3D.gd:94).

**Inventário e saves:** [FieldInventoryRuntime.gd](D:/geteco/game/systems/inventory/FieldInventoryRuntime.gd:114) chama `save_game` em alterações bem-sucedidas. [FullSession.gd](D:/geteco/game/runtime/FullSession.gd:1667) coleta vários subsistemas; [SaveStore.gd](D:/geteco/game/runtime/SaveStore.gd:25) valida, serializa, grava, faz flush, relê e rotaciona backup sincronicamente. Isso pode provocar travadas de interação. Coalescer mudanças de organização e transferir serialização/I/O de snapshot imutável para uma fila é candidato, com confirmação de gravação durável nos checkpoints importantes. Preservar comportamento de recuperação e não perder progresso para ganhar FPS.

**Sessão longa, estado atualizado:** [Economy.gd](D:/geteco/game/systems/economy/Economy.gd) aceitava novas operações além do limite de 10.000 recibos do próprio restore. As correções 17, 19 e 20 compactam os contratos conhecidos e recusam recibos opacos excedentes antes de alterar o estado. A reprodução pelas APIs reais passou de oito falhas em 55 verificações para uma: 8.001 recibos com IDs legais longos ainda produzem 2.369.353 bytes, acima dos 2 MiB de SaveStore. A proteção dos arquivos existentes está corrigida; impedir todo estado aceito que exceda o orçamento de bytes continua aberto. O [inventário dos consumidores e desenho versionado](D:/geteco/game/evidence/performance-implementation-20261002/economy-ledger-versioned-design.md) distingue os formatos e as medições, e a [análise de orçamento](D:/geteco/game/evidence/performance-implementation-20261002/save-byte-budget-options.md) delimita as alternativas. Não é seguro apagar os recibos ou substituir todos por um maior serial: isso pode duplicar recompensas ou inventar pagamentos que nunca ocorreram.

**Custos condicionais adicionais:** o inventário tenta até 16 posições para bagagem migrada a cada 0,25 s enquanto não consegue posicioná-la, e percorre drops a 4 Hz, com limite de 512. Indexar por região/célula e repetir a procura após mudança relevante evita consultas persistentes: [FieldInventoryRuntime.gd](D:/geteco/game/systems/inventory/FieldInventoryRuntime.gd:191). A restauração de veículos de residência também pode repetir tentativas em vaga bloqueada, embora tenha apenas dois slots. [Residence.gd](D:/geteco/game/activities/Residence.gd:210).

**Missões e atividades:** economia e campanha são estados sem loops próprios; corrida, esqui e motocross possuem limites de contexto. Não há evidência de que sejam o gargalo de repouso do vídeo. Há risco localizado em [MissionWorld.gd](D:/geteco/game/runtime/MissionWorld.gd): criar e liberar personagens no mesmo limiar de 60 m pode causar alternância junto à fronteira. Usar histerese é uma oportunidade ainda sem medição própria. A liquidação do esqui agora consulta páginas compactas e exceções opacas, reutilizando o snapshot recebido; isso reduz o crescimento anterior, mas a busca do maior serial ainda depende da quantidade de páginas/recibos existentes: [V1OptionalRewardPolicy.gd](D:/geteco/game/activities/V1OptionalRewardPolicy.gd).

## O que já está sendo feito de forma correta

| Sistema | Base boa que deve continuar |
|---|---|
| Mundo | V2 nativa 3D; chunks de 64 m; retenção, aquecimento, liberação gradual |
| Decoração | Cidade já usa MultiMesh por chunk/material; malhas e materiais compartilhados |
| Pedestres | Frequência física menor à distância, distribuída entre identidades |
| Veículos | Atualização reduzida à distância e repouso parcial para estacionados/filas |
| Reações | Separação de responsabilidades, limites de percepção e fila de fuga |
| Polícia | Fila incremental de navegação, cancelamento, referências fracas e orçamento por frame desenhado |
| C# | Grafo compacto, índice espacial, heap reutilizado e cálculo intensivo separado da coordenação |
| Combate | Pools de efeitos e tetos de fogos/unidades; processamento de efeitos ociosos desligado |
| Áudio | Bancos compartilhados, prewarm, limite de veículos audíveis e vozes |
| Clima | Poças, respingos e vozes com limites/reutilização |
| UI | Atualização de status limitada, minimapa cacheado e prévias suspensas |
| Interiores | Sala inativa suspensa; atores e cenário no mesmo espaço 3D; sólidos por grupos |
| Persistência | Validação de schema, temporário, backup, recuperação e preservação de arquivos corrompidos |
| Diagnóstico | Medidores renderizados e StallLog com tempo real entre frames e escrita em thread |

Não recomendo reescrever tudo em C#, instalar ECS global, reduzir toda a física a 30 Hz, eliminar NPCs ou apagar iluminação como primeiro passo. O problema predominante da revisão é quando e quanto trabalho executamos, não a existência de GDScript. C# é apropriado para algoritmos medidos, com poucas travessias para o motor.

Mobile versus Forward+ e GodotPhysics versus Jolt são experimentos separados, com a mesma cena e a mesma qualidade. Não são upgrades automaticamente mais rápidos. Uma mudança de backend físico exige regressões de rampas, meio-fio, veículos, interiores e contatos. [Jolt Physics](https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html).

## Comparação com projetos oficiais

Foram consultados exemplos oficiais para técnicas específicas, não para importar uma arquitetura inteira ou prometer o FPS de uma demo.

| Projeto e código consultado | O que aproveitar | O que ele não demonstra |
|---|---|---|
| [TPS oficial](https://github.com/godotengine/tps-demo/blob/master/player/player.gd) | CharacterBody3D, AnimationTree, root motion e separação da entrada; referências de nós cacheadas | Escala de cidade com 100 NPCs. A instanciação direta de projéteis da demo não é receita universal para nosso combate |
| [Truck Town](https://github.com/godotengine/godot-demo-projects/tree/master/3d/truck_town) | Referência de física veicular, câmera e articulação de reboques | Ganho ao trocar a frota por VehicleBody3D. A demo usa Forward+ e não reproduz a densidade nem as interações do Geteco |
| [Threaded Loading](https://github.com/godotengine/godot-demo-projects/blob/master/loading/load_threaded/load_threaded.gd) | Separação entre pedir recurso e obter o resultado | Ausência de bloqueio: o exemplo simplificado também pode esperar se o botão obtiver o recurso cedo demais; aplicar a checagem de status descrita na documentação |

Links de branches como master são móveis. Fixar a revisão quando um exemplo virar especificação de implementação. Nenhum desses projetos foi executado aqui como benchmark comparável.

## Evolução da arquitetura

As falhas reproduzidas acrescentam dois contratos concretos à evolução. A otimização de malhas deve preservar também peças que a jogabilidade articula: conservar triângulos e materiais não basta quando um consumidor precisa encontrar cano, porta ou bico separadamente. Na suspensão, retomada e reparo, o dono atual da colisão precisa ser explícito; reaplicar cegamente as máscaras anteriores pode reativar um cadáver ou ignorar a carcaça física criada durante a pausa. São conclusões dos testes locais, não uma recomendação de reescrever todos os sistemas.

A documentação distingue callbacks de script e processamento interno do motor. Desligar `_physics_process` de um nó não deve ser tratado como contrato suficiente para congelar toda uma entidade composta. O projeto precisa decidir quais filhos continuam simulando dano, quais efeitos cessam e qual corpo físico será retomado. [Processamento de Node](https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-set-physics-process), [processamento físico interno](https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-set-physics-process-internal).

Quatro capacidades compartilhadas resolveriam causas recorrentes:

1. **Registro espacial de entidades:** posição, tipo, estado e consultas por área, atualizado de forma controlada. Reutilizar infraestrutura existente onde possível.
2. **Eventos de mudança de estado:** dano, morte, buzina, ocupação, entrada/saída e descarte. Reduzir polling duplicado e deixar claro quem é dono de cada entidade.
3. **Frequências distintas por responsabilidade:** colisão/movimento próximo no passo físico; planejamento menos frequente; animação conforme relevância visual; repouso com despertar definido.
4. **Orçamento total para trabalho adiável:** streaming, navegação, criação de população, equipamentos e descarte compartilham prioridade, prazo e cancelamento. Preservar resposta imediata de tiro/colisão e não deixar filas sem atendimento.

`FullSession` e `ProductionWorld` concentram muitas responsabilidades. Extrair transições, persistência e coordenação de população aos poucos ajuda a medir e controlar custos. Apenas repartir um arquivo grande não melhora FPS.

A documentação dos interiores foi alinhada à V2: [interior-physics-and-depth.md](D:/geteco/game/docs/interior-physics-and-depth.md) e [interior-standard.md](D:/geteco/game/docs/interior-standard.md) agora referenciam `NativePlace`, `MaciotaPlace`, `FullSession` e corpos 3D reais. As prescrições antigas de projeção para física 2D, sprites e SubViewport por sala passaram a ser históricas. Exigências de colisão, spawn, circulação, profundidade e direção visual foram preservadas. Foi uma correção documental: não altera nem certifica ambientes ou FPS.

## Qualidade das medições e critérios de aceitação

O profiler GDScript não detalha scripts C#; usar ferramenta .NET ou instrumentação apropriada além do analisador gráfico. Não somar tempos inclusivos de pai e filho. [Profiler do Godot](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/the_profiler.html).

O medidor [measure_script_ranking.gd](D:/geteco/game/tests/measure/measure_script_ranking.gd:31) desliga o processamento normal e chama callbacks manualmente. A fila policial e o trânsito verificam `is_physics_processing`, portanto esse método altera contratos do sistema que mede. Tratá-lo como experimento intrusivo, não como certificação do gameplay. O medidor de modelos de pedestres também faz chamada extra a `_process(0)` num palco sintético.

O registro `finish_slow` de [StallWorkTrace.gd](D:/geteco/game/runtime/StallWorkTrace.gd:22) filtra chamadas individuais abaixo do limiar; outros spans completos existem, mas ainda falta uma visão agregada uniforme por sistema. Muitas chamadas pequenas podem dominar um frame sem aparecer no relatório de eventos lentos.

A medição local de jogador parado e tiros/perseguição na Union foi executada conforme a seção inicial. Ainda faltam o mesmo congestionamento do vídeo, perseguição com fogo e recuperação, noite/chuva, deslocamento entre regiões e interiores representativos. Fixar máquina, renderer, resolução, câmera, população, estado e revisão; considerar a variação das entidades autônomas. Separar 10 s de aquecimento e pelo menos 30 s de amostragem por cenário.

Guardar média por frames/tempo, p50/p95/p99, máximo, frames acima de 33,3 e 66,7 ms, CPU/GPU/física, entidades, draw calls, contatos e memória. Medir visitas frias separadamente. A/B deve mudar um fator por vez e confirmar qualidade/jogabilidade. Um ganho com sistemas desligados localiza custo, mas não aprova removê-los.

Meta provisória do projeto: 60 FPS sustentados, orçamento de 16,67 ms; uma meta superior de 120/144 precisa de definição e medição no hardware de referência. Aumento superior a 5% em p95/p99 é sinal para confirmação equivalente, não critério ajustável para aprovar. As confirmações preservadas na seção inicial encontraram sequências graves também no original; o cenário exato do vídeo ainda não foi reproduzido integralmente.

## Inventário para a próxima validação integrada

Os registros atuais identificam duas regiões produtivas, Harbor e Mountain. O catálogo contém 31 IDs de lugares e 31 acessos públicos derivados; a garagem do Maciota é tratada separadamente, formando uma base de 32 acessos convencionais. As seis casas da vila também têm tratamento próprio. Essas contagens de registros não certificam a acessibilidade, nem resolvem sozinhas a identidade de todos os interiores compartilhados e espaços ocultos.

Há seis missões executáveis de Harbor com 23 etapas/eventos; o ledger canônico tem nove beats e quatro contratos, que não instanciam conteúdo por si só. Catálogos de atividades incluem duas corridas, dois drifts, dez colecionáveis, três residências, cinco contratos cíclicos de guincho e três percursos de esqui, além de adaptadores próprios de motocross, skate e vila.

A matriz de execução deve começar pelos dois sentidos Harbor–Mountain e pelas 64 direções de entrada/saída dos 32 acessos convencionais. Acrescentar casas da vila, Vértice oculto, porão/túnel/esgoto/Forte/saída do esqui e variantes de embarque, resgate, prisão, restore e cancelamento. Não somar essas variantes cegamente como novos interiores. Nesta auditoria, todas permanecem pendentes de execução própria.

## Cobertura e limites

| Família | Examinado nesta auditoria | Ainda não comprovado |
|---|---|---|
| Sessão, carregamento e streaming | Código e contratos | Rotas completas, primeira visita e retorno |
| Jogador, câmera, input | Integração, vídeo e configuração | Latência medida, todos os controles/plataformas |
| Pessoas e rotinas | Física, frequência, repouso, spawn | Multidões em todas as regiões |
| Reações, combate e polícia | Código, perfil e amostras renderizadas locais de tiros/perseguição | Caos completo com fogo/helicóptero e recuperação instrumentada |
| Tráfego e semáforos | Rotas, consultas, reservas e vídeo | Todos os cruzamentos e conflitos de conversão |
| Terrenos, modelos e vegetação | Materiais, batching, construção e culling | Ganho de GPU, emendas e LOD em movimento |
| Luz, sombras, água e clima | Organização e limites de código | Flickering noturno/chuva e custo separado |
| Efeitos de pneus | Patch, 102 contratos, custo CPU e fade renderizado antes/depois | Certificação de todas as situações e plataformas |
| Interiores e garagem | Ciclo de vida e contratos | Todos os acessos, colisão/oclusão e armas |
| Áudio | Cache, carregamento e limites | Mix audível e latência de todas as famílias |
| UI e inventário | Frequência, reconstrução e persistência | Custos de interação medidos |
| Economia e missões | Estado, recibos, snapshot e ciclo geral | Campanha completa e sessão longa |
| Atividades opcionais | Integrações e ciclo de vida | Execução de todas; skate estava em edição concorrente |
| C# e ferramentas | Build e fronteiras principais | Perfil .NET do cenário do vídeo |
| Android/exportação | Configuração observada | FPS, memória e estabilidade em dispositivo/export release |

A amplitude é de arquitetura e revisão de caminhos críticos, não leitura exaustiva de cada linha nem certificação de todas as combinações. Houve execução renderizada local na Union e fixtures dos efeitos; isso **não certifica uma região inteira ou suas transições**. O vídeo do usuário foi examinado por amostras temporais, que não comprovam ausência de flicker entre amostras.

Skills aplicadas pela equipe: performance-do-jogo, testes-com-criterio, guardiao-do-jogo, auditoria-viaria, validar-iluminacao, padrao-interiores e validar-terrenos-pisos. A skill write-page orientou o relatório de documentação. “Megabrain” não estava disponível no catálogo nem na busca local realizada; não foi utilizado um recurso inexistente.

Na etapa inicial, o usuário havia escolhido auditoria sem benchmark isolado após detectar concorrência. A autorização posterior substituiu essa restrição. A validação atual inclui compilação .NET, contratos de geometria/efeitos e medições renderizadas descritas no início, com armazenamento isolado e preservação dos resultados ruins. A compilação não certifica todos os GDScripts, e o ganho CPU do método não deve ser apresentado como ganho global de FPS.

Na continuação de 3 de outubro, o usuário escolheu **continuar os testes lógicos enquanto joga**. Não foi iniciada nova comparação renderizada concorrente. Os contratos estreitos usam armazenamento separado, Godot .NET e registro dos processos coexistentes; não geram aprovação de FPS. Permanecem preparados o diagnóstico da família de veículo associada ao WarmUp, os percursos de regiões e a comparação visual/performance do canhão.

[Registro da concorrência detectada](D:/geteco/game/evidence/performance-audit-20261002/blocked-processes.json). [Amostras do contador do vídeo](C:/Users/rafae/.codex/visualizations/2026/10/02/01a0fdee-c745-7142-86e0-f6e8db094210/video-fps-samples.png).

## Sequência de trabalho sugerida

Já foram executados perfil, comparativos locais e as integrações descritas na abertura. A prioridade restante é isolar o gatilho das sequências de atraso da física e das esperas nativas durante gameplay. Sangue, equipamentos policiais, skates e três famílias do porto já receberam correções medidas. Os contadores limitaram o benefício teórico do cache de projeção imóvel a aproximadamente 0,084 ms por passo: não explica a duplicação observada do custo de física. Não houve atribuições de rotação exatamente igual na coleta. Esses caches não serão apresentados como solução das travadas sem nova evidência. O shader opaco só deve voltar à execução após identificar consumidor visível afetado.

Depois, consolidar consultas espaciais e eventos e testar repouso de NPCs. As duas falhas comprovadas nas reservas de cruzamentos já foram corrigidas; a confirmação do fluxo da cidade inteira continua pendente. Validar atropelamento, meio-fio, reações e perseguição a cada mudança.

Na sequência, preparar meshes/colisões antes do gameplay e dividir os trabalhos indivisíveis de streaming. Medir transições frias e retornos, incluindo navio e montanha.

Por fim, comparar batching/LOD e variantes de terreno, revisar áudio/save e testar alternativas de renderer/física somente onde o perfil justificar. A contagem de transações e os contratos recorrentes já receberam correções independentes da investigação de FPS; permanece o orçamento total de bytes, preservando idempotência e compatibilidade.

A entrega de cada mudança deve mostrar milissegundos antes/depois e efeitos na jogabilidade. As correções integradas e seus limites estão nas seções iniciais; as propostas arquiteturais que não receberam evidência própria continuam oportunidades, e as travadas gerais seguem explicitamente pendentes.
