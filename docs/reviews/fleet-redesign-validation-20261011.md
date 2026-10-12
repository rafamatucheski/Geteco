# Validação da frota — 11/10/2026

O pedido posterior de testar os carros e sua performance substituiu a dispensa inicial. Esta revisão separa contratos dos 59 recursos, fluxos selecionados em gameplay, evidência temporal e medição renderizada. A redução de geometria não equivale a ganho proporcional de FPS.

## Funcionamento e correções

Godot **4.7.2 .NET**, `Harbor.csproj` compilado previamente, zero erros/avisos. Os testes de Main usaram sessões `--no-save`; a medição registra o autoload C# ativo. Não se usou fallback GDScript para substituir o caminho .NET.

| Cobertura | Resultado |
|---|---|
| 59 recursos pelo factory e Vehicle reais | 2.882 verificações finais aprovadas; cobertura composta por 49 recursos inalterados da primeira rodada e dez retestados após correção |
| Portas | 114 folhas verificadas, incluindo abrir e retornar à posição fechada |
| Equipamentos existentes | 41 verificações aprovadas |
| Identificação de lentes e preservação de acabamentos, 59 modelos | 817 verificações aprovadas após correção compartilhada; equipamento existente repetido com 41 aprovadas |
| Cinco picapes, carga e restauração | 241 verificações aprovadas após correção |
| Variante de sorvete | 24 verificações aprovadas |
| Embarque na variante de sorvete | 110 verificações aprovadas |
| Cofre real isolado e semântica da variante | 17 verificações aprovadas; não representa uma missão completa de assalto |
| Entrar, dirigir e sair em Main, seis modelos | Runner corrigido: 102/102 no novo e 102/102 no legado; todas as 12 saídas paradas com a apresentação normal |
| Cabines corrigidas de ambulância e conversível | 80 verificações com Actor real aprovadas; posição do banco dentro do intervalo da porta |

Os contratos cobrem rodas/pivôs, geometria finita, pintura independente entre instâncias, preservação de vidro/pneu/lentes/acabamento, portas, desgaste, carcaça e restauração após reparo. Não substituem a observação de todos os 59 carros em todas as situações do jogo.

Foram corrigidos dez recursos:

- **Gol 1993 e Jetta GLI:** as duas lentes dianteiras compartilhavam uma superfície central, produzindo apenas um projetor. O legado reproduziu as quatro falhas. A autoria agora separa as lentes por lado, com uma superfície adicional por carro e os mesmos triângulos/malhas. O reteste também quebra a lente esquerda e confirma que a direita permanece acesa.
- **Ranch Single, Ranch Pickup, Lumber Pickup, Atlas Crew e Sertão Trail:** piso da caçamba alinhado ao contrato de carga; metadado de caçamba aberta impede que o recorte legado destrua as superfícies já autoradas. Mantidas as contagens de geometria. Cargas vazias/ocupadas e restauração foram retestadas.
- **Ambulância e Beach Cabriolet:** dimensões explícitas da cabine impedem que vidros agrupados ou acabamento refletivo desloquem o banco. Na ambulância, o banco inferido estava em z=+2,552 m, dentro do baú; o perfil da cabine original o situava em −0,967 m. No conversível, estava em −1,479 m, fora do intervalo da porta. `CabinMetadataFix` aplica os dados apenas nesses dois recursos e nos respectivos autoradores, usando o suporte existente de `VehicleInterior`. Não houve edição desse runtime compartilhado. O fingerprint de todas as propriedades armazenadas dos descendentes, incluindo malhas, materiais e transforms, permaneceu idêntico após salvar/recarregar; fotos exteriores sem ocupante continuam representativas. O diagnóstico numérico percorreu os 59 modelos, mas não certifica visualmente as outras 57 cabines.
- **Carro-forte:** a simplificação havia removido as duas faces da chapa inferior da porta. A superfície pintada original foi preservada na autoria desse modelo; a área projetada por lado voltou de 0,31 para 2,70 m², com quatro verificações dirigidas aprovadas. O modelo ficou com **3.500 triângulos, 18 malhas e 25 superfícies**, contra 6.852/35/35 do original: +192 triângulos sobre a primeira proposta, para manter a porta íntegra. As duas fotos da galeria foram atualizadas.

Os três últimos recursos passaram em **136/136 verificações dirigidas** de contratos, substituindo suas linhas anteriores na cobertura composta. A captura posterior e seus limites aparecem no fim deste relatório. [Correção e fingerprints das cabines](../../evidence/fleet-redesign-20261011/validation/cabin-metadata-fix/patch.json) · [Diagnóstico de área da porta](../../evidence/fleet-redesign-20261011/temporal/armored-door-geometry.json).

**Correção de um falso alarme do teste de saída:** na primeira tentativa houve seis falhas em três modelos, tanto novos quanto legados. O runner soltava o controle externo do freio, forçava somente `car.speed=0` e não confirmava velocidade horizontal zero. A reprodução dessa fase deixou o Union a 5,720 m/s e o Dune Buggy a 6,965/7,069 m/s, acima dos 2 m/s que acionam `VehicleBailout`. Portanto, retiro a conclusão inicial de defeito herdado na saída normal: o teste não garantia que estava exercitando esse fluxo.

O runner corrigido usa o comando real de freio de mão, exige três ticks parado e registra velocidade/tipo de transição. Passou em **102/102 verificações nos seis modelos novos e 102/102 no legado**. Todas as 12 saídas ocorreram a **0,0 m/s** com `VehicleBoardingPresentation`, sem saltos fora dos limites. Modelos: Union Sedan, Ranch Pickup, Courier Van, American Dump Truck, Dune Buggy e Desert Mirage. Os logs anteriores foram preservados como tentativa com fixture inválido para saída normal. Nenhum runtime de embarque foi alterado para obter esse resultado.

[Contratos e tentativas preservadas](../../evidence/fleet-redesign-20261011/validation/contracts-summary.md) · [Cobertura final e hashes](../../evidence/fleet-redesign-20261011/validation/contracts-final.json) · [Fluxos de uso, sorvete e saída](../../evidence/fleet-redesign-20261011/utility/validation-summary.md).

## Correção compartilhada descoberta em movimento

A captura do Union mostrou a grade emitindo vermelho, e um NPC apresentou bagageiro/retrovisores/estepe vermelhos. A expressão `"tail" in key` reconhecia `detail` e `service_detail` como lanternas; uma superfície consolidada podia incluir peças dianteiras e traseiras. A condição era ativada pelo centro da superfície. Isso não é apenas uma questão de contagem de triângulos.

`VehicleSurfaceRoles` agora reconhece os aliases reais de lente/lanterna e o sufixo de exportação `#`, excluindo `detail`, `service_detail` e `brake_metal`. `VehicleEquipment` usa essa identificação no vínculo e no reconhecimento das lentes. Os classificadores de `VehicleFinish` e do autorador `FleetBatchMesh` também usam o helper para não perpetuar a ambiguidade. Foram preservadas cópias dos arquivos anteriores; nenhum asset foi regenerado por essa correção.

O teste dirigido percorreu os 59 carros, ligando farol/freio/sirene quando aplicável e desligando o equipamento: **817 verificações aprovadas**, incluindo materiais que não são lentes sem mutação. Os 41 checks de equipamento existentes passaram novamente. Isso prova a separação funcional; a evidência temporal é tratada separadamente.

[Teste e resultados dos materiais](../../evidence/fleet-redesign-20261011/validation/lens-role-fix/contracts.json) · [Imagem que revelou o defeito](../../evidence/fleet-redesign-20261011/temporal/attempt-01/union_sedan/04-night-moving.png). A versão corrigida foi medida separadamente; o histórico anterior permanece identificado abaixo.

## Performance: método e limites

Main real da cidade 1, **1920 × 1080**, renderizador Mobile, **RTX 4060 Laptop GPU**, **Intel i7-13650HX**, driver Windows 32.0.16.1047. Dez veículos estacionados fisicamente perto da garagem do Maciota, com tráfego, pedestres, streaming, colisão, sombras e luzes da cidade ativos. Câmera idêntica, dez alvos dentro do enquadramento, nenhum deslocamento/dano durante as amostras. Não houve outro Godot, build ou encoder concorrente durante a medição.

Modelos: Aurora Executive, Monaliza, Muscle Classic, Sedan Classic, Station Wagon, Porto Rosso, Arctic Jeep, Courier Van, Police Cruiser e Medic Box. Nos dez alvos: **528 → 70 malhas**, **525 → 217 superfícies**, **232.484 → 48.985 triângulos**. É uma comparação mista de dez modelos; não são dez cópias do primeiro cupê de 61 mil triângulos.

Os mesmos corpos físicos mantêm ambas as apresentações residentes; alterna-se apenas qual fica visível. Colisão, equipamento, pintura, posição e câmera permanecem iguais. Isso isola a apresentação renderizada e **não mede a economia total de memória/carregamento ou de CPU pela remoção definitiva dos nós antigos**, nem dez pilotos dirigindo, nem substitui uma medição de toda a frota em todos os mapas. Outros veículos da cidade permanecem na mesma versão durante a comparação.

Após preparação e 60 s de estabilização, cada janela tem 10 s de aquecimento e pelo menos 30 s de coleta sem screenshots/readback. Ordem ABBA de dia e de noite, duas janelas por variante/cenário. Foco estável selecionado antes da coleta e mantido, janela não minimizada, modo de baixo uso de CPU desativado. Diagnóstico sem limite/VSync; configurações normais verificadas separadamente. A população real e os veículos em frustum são registrados a cada segundo: a cidade permanece ativa e sua variação residual limita atribuir diferenças pequenas exclusivamente à malha.

Alvo provisório: 60 FPS / 16,67 ms. Aumento acima de 5% em p95 ou p99 exige uma única confirmação equivalente. p95/p99 são percentis de tempo por quadro; menor é melhor. FPS é quadros/tempo, não média do contador desenhado na tela. CPU/GPU abaixo medem o viewport principal; CPU não é todo o processo, GPU não é percentual de utilização, e esses tempos não devem ser somados por causa da sobreposição do trabalho.

## Versão final após as correções

Rodada `ten-cars-rolefix-stable`: **oito janelas completas e válidas**, com foco em todos os quadros, nenhuma minimização, nenhum descarte e nenhuma reescolha de foco. Invariantes de câmera, corpos e modelos válidos em todas as janelas. Os **1.256 hashes de código, cenas, recursos da frota e DLL** permaneceram idênticos antes/depois; nenhum fonte C# estava mais novo que a DLL utilizada. Sem erros ou avisos no log.

| Comparativo da versão final | FPS antes → depois | p95 ms | p99 ms | CPU render média ms | GPU render média ms |
|---|---:|---:|---:|---:|---:|
| Dia, ABBA | 107,77 → 97,72 (−9,3%) | 11,947 → 14,566 | 14,162 → 29,050 | 2,977 → 3,109 | 2,982 → 3,184 |
| Noite, ABBA | 103,62 → 109,41 (+5,6%) | 12,281 → 11,766 | 13,993 → 13,856 | 3,144 → 2,913 | 3,209 → 3,006 |
| Dia, confirmação BAAB | 93,03 → 112,47 (+20,9%) | 15,439 → 11,683 | 36,168 → 13,632 | 3,252 → 2,770 | 3,309 → 2,856 |

**Resultado misto; ganho geral de performance não aprovado. A piora diurna não se repetiu na única confirmação prevista.** No ABBA, o p95 diurno aumentou 21,9% e o p99 105,1%, acionando essa confirmação BAAB. A piora concentrou-se na segunda janela nova (`day-03-final`): 87,16 FPS, p99 de 36,451 ms e 43 quadros acima de 33,3 ms, com máximo de 66,149 ms. A outra janela nova teve 108,28 FPS e p99 de 14,560 ms. Ambas foram mantidas na agregação. As duas janelas antigas tiveram 106,96/108,58 FPS e nenhum quadro acima de 33,3 ms.

A confirmação terminou com **quatro janelas completas**, os mesmos 1.256 hashes, invariantes válidos e **12.333/12.333 quadros com foco**, sem minimização, descarte ou reescolha de foco. Nela, os novos tiveram ganho médio de 20,9%, redução de p95/p99 de 24,3%/62,3% e redução média de renderização de **14,8% na CPU e 13,7% na GPU**. Nenhum quadro novo excedeu 33,3 ms; máximo de 19,578 ms. Os legados tiveram **73 quadros acima de 33,3 ms, dois acima de 66,7 ms e máximo de 91,165 ms**. Isso não apaga a primeira rodada nem prova um ganho fixo de 20,9%.

Os picos do ABBA novo ocorreram entre **15,631 e 17,964 s** de `day-03-final`. Na confirmação, os picos mudaram para ambos os legados: 41 entre **22,025 e 24,303 s** de `day-02-baseline` e 32 entre **21,396 e 23,081 s** de `day-03-baseline`. Não houve exclusão dessas amostras. Os monitores apontam elevação simultânea de tempos de render/processamento/física, sem explosão correspondente de geometria, mas não isolam a causa. A confirmação teve quatro pedestres, contra três no ABBA, além de tráfego variável; as rodadas ficam separadas. O resultado sustenta a economia de geometria e melhora em parte dos cenários, sem certificar estabilidade geral de frame time ou atribuir os picos exclusivamente aos modelos. A investigação finita encerrou aqui, sem novas repetições para escolher um resultado favorável.

As médias de CPU/GPU de render aumentaram 4,4%/6,8% de dia e caíram 7,3%/6,3% à noite. Na noite comparada não houve quadros acima de 33,3 ms em nenhuma variante. Chamadas de desenho da cena inteira caíram **10,4% de dia e 14,5% à noite**; primitivas renderizadas caíram **22,4%/25,5%**. A economia de geometria é comprovada, mas não garante melhoria em todo o tempo por quadro.

A cidade continuou variando: três pedestres; tráfego antigo/novo médio de **37,95/39,52 de dia** e **39,95/40,00 à noite**, com centros de veículos no frustum de 21,24/21,66 e 21,08/21,02. A variação da cena e a dispersão entre janelas não permitem atribuir a piora exclusivamente às malhas. Nenhuma população, sombra, luz, IA ou física foi removida para melhorar o número.

Na confirmação BAAB, o tráfego médio antigo/novo foi **35,31/35,24**, o total médio de veículos foi **54,31/54,31** e os centros no frustum foram **21,45/19,77**, com quatro pedestres nas duas variantes. A carga total média semelhante não elimina diferenças de distribuição/visibilidade. O log resumido do runner pai ainda imprime `valid:false` por esperar oito janelas; depois o runner da frota grava o JSON final conforme o contrato de confirmação de quatro janelas. Os quatro invariantes e a coleta completa foram conferidos diretamente; a divergência de log está registrada na revisão da confirmação.

Com a configuração normal (limite 144 e VSync ligado), as duas janelas novas também foram completas e mantiveram foco/invariantes: **114,25 FPS de dia**, p99 12,527 ms, máximo 16,527 ms, sem quadros acima de 33,3 ms; **94,86 FPS à noite**, p99 32,980 ms, máximo 54,255 ms e **28 quadros acima de 33,3 ms**. Não houve quadro acima de 66,7 ms. São observações finais em outro momento da cidade, sem baseline pareado; os picos noturnos impedem tratar o ganho médio do ABBA como ausência de travadas.

Duas tentativas pós-correção precederam a rodada válida, sem resultado comparável: `ten-cars-rolefix-abba` perdeu foco aos 31,182 s da primeira janela, descartou os dados pelo contrato e terminou o prazo de 120 s sem amostra; o runner acessou `summary.frames` ausente e foi encerrado pelo PID próprio. A correção usa acesso seguro ao campo vazio. `ten-cars-rolefix-background` permaneceu focado por 120 s apesar da política de segundo plano e encerrou corretamente sem amostras. Os dados e logs foram preservados. Não houve seleção por FPS.

A política final permite uma única reescolha por evento de foco **somente antes da primeira janela completa**, descartando todos os dados anteriores e reiniciando 10 s de aquecimento, ainda dentro do prazo de 120 s. Depois fixa a condição para toda a rodada. Essa possibilidade não foi usada na rodada válida: ela permaneceu focada desde o início. Não misturar FPS absolutos de execuções com condições ou versões distintas.

[ABBA final](../../evidence/fleet-redesign-20261011/validation/performance/ten-cars-rolefix-stable/paired-summary.json) · [Carga, picos e invariantes](../../evidence/fleet-redesign-20261011/validation/performance/ten-cars-rolefix-stable/comparison-detail.json) · [Hashes após a medição](../../evidence/fleet-redesign-20261011/validation/performance/ten-cars-rolefix-stable/source-check-after.json) · [Confirmação final](../../evidence/fleet-redesign-20261011/validation/performance/ten-cars-rolefix-day-confirm/paired-summary.json) · [Revisão da confirmação](../../evidence/fleet-redesign-20261011/validation/performance/ten-cars-rolefix-day-confirm/review.md).

## Histórico antes da correção das lentes

As rodadas desta seção **não medem a versão final** e não são agregadas aos resultados acima.

| Rodada ABBA | FPS antes → depois | p95 ms | p99 ms | CPU render média ms | GPU render média ms |
|---|---:|---:|---:|---:|---:|
| Dia | 98,60 → 96,12 (−2,5%) | 12,958 → 13,275 | 15,536 → 16,350 | 3,148 → 3,126 | 3,244 → 3,327 |
| Noite | 93,97 → 100,77 (+7,2%) | 15,811 → 13,809 | 22,502 → 19,863 | 3,339 → 3,058 | 3,404 → 3,153 |
| Confirmação diurna BAAB | 103,34 → 105,61 (+2,2%) | 12,516 → 13,540 | 15,358 → 16,155 | 3,173 → 2,946 | 3,115 → 3,014 |

A primeira rodada teve aumento diurno de p99 de **5,24%**, que acionou a única confirmação BAAB diurna. Nela, o p95 piorou **8,18%** e o p99 **5,19%**, apesar da média melhor. **Performance não aprovada como melhoria geral:** o aumento de p99 reapareceu acima da tolerância. A causa exclusiva nos modelos não foi estabelecida, pois o tráfego continua variando. Não repetir até obter resultado favorável.

As médias de renderização da confirmação caíram **7,2% na CPU** e **3,3% na GPU**; na primeira rodada diurna ficaram em −0,7%/+2,6%, e à noite em −8,4%/−7,4%. Os tempos médios de render medidos foram menores em parte das janelas, sem ganho consistente de frame time completo. Na confirmação, a GPU teve média menor, mas p95 maior em 8,45% (3,634 → 3,941 ms) e p99 maior em 15,82% (3,919 → 4,539 ms); a média isolada não aprova essa distribuição. O contador de primitivas da cena inteira caiu 20,7% de dia e 25,8% à noite no ABBA; chamadas de desenho caíram 11,3%/15,1%. A queda de 79% nos triângulos dos dez alvos não é uma queda de 79% em todo o trabalho do jogo.

A confirmação preserva um pico de **403,639 ms** na primeira janela do lote novo: 1 → 2 quadros acima de 33,3 ms e 0 → 1 acima de 66,7 ms. A noite da primeira rodada também registrou picos: 20 → 32 quadros acima de 33,3 ms e 4 → 2 acima de 66,7 ms, apesar da melhora nos percentis agregados. Não ocultar esses eventos nem usar a média para certificar ausência de travadas. Os p99 agregados diurnos ficaram abaixo de 16,67 ms; isso não anula a piora relativa nem o pico isolado.

No ABBA, o tráfego registrado variou entre 35–40 veículos de dia e 38–40 à noite; na confirmação, 33–37. Foram quatro pedestres em todas essas janelas. As médias de tráfego antigo/novo foram 37,97/39,03 de dia, 39,76/39,55 à noite e 34,37/34,52 na confirmação. Os centros de veículos dentro do frustum foram, em média, 23,55/24,87, 23,18/23,00 e 19,44/19,97 respectivamente; esse contador não mede oclusão. O foco, a câmera, os dez corpos e a visibilidade dos alvos permaneceram válidos em todas as janelas, sem descarte por troca de foco. Hora e clima seco ficaram fixados igualmente por cenário, com evolução do Weather pausada. A carga da cidade não foi congelada e não é idêntica quadro a quadro; os valores brutos permitem auditar essa limitação.

Há dispersão forte entre as duas janelas noturnas de cada variante: p99 antigo de 15,361 e 31,186 ms; novo de 15,006 e 35,187 ms. A melhora noturna agregada não foi uniforme. Todos os percentis da tabela usam os frames concatenados de cada par de janelas, sem fazer média de percentis.

Com a configuração normal restaurada (limite 144, VSync ligado), somente o lote novo obteve **111,53 FPS de dia** e **105,00 à noite**, p99 de 12,952/14,048 ms, sem quadros acima de 33,3 ms nessas duas janelas. São verificações de funcionamento normal, feitas em outro momento da cidade; não constituem comparação antes/depois.

Uma tentativa anterior (`ten-cars-abba-run1`) terminou antes de medir: a política de janela sem foco não conseguiu obter a condição exigida em 120 s. Seu registro foi preservado. A regra corrigida admite foco ou ausência de foco estáveis, escolhidos antes da amostragem; a rodada válida manteve foco em todos os quadros. Nenhum resultado foi selecionado com base em FPS.

[ABBA: dados completos](../../evidence/fleet-redesign-20261011/validation/performance/ten-cars-abba-run2/paired-summary.json) · [Confirmação diurna](../../evidence/fleet-redesign-20261011/validation/performance/ten-cars-day-confirm/paired-summary.json) · [Cena diurna](../../evidence/fleet-redesign-20261011/validation/performance/ten-cars-abba-run2/day-02-final-gameplay.png) · [Cena noturna](../../evidence/fleet-redesign-20261011/validation/performance/ten-cars-abba-run2/night-02-final-gameplay.png).

## Evidência temporal e fotos

As capturas contínuas usam Main real na cidade 1, rota `warehouse_way`, clima seco e a câmera de gameplay. Exercitam entrada pela porta, condução diurna/noturna, frenagem e saída parada; sirene e giroflex entram na cobertura da viatura e da ambulância. Os seis casos de `attempt-03` passaram nos eventos funcionais registrados, mas a inspeção visual revelou dois defeitos que esses eventos não detectavam: banco da ambulância deslocado para o baú e chapas inferiores ausentes na porta do blindado. Essas tentativas foram preservadas e não recebem aprovação visual. O conversível foi acrescentado após o diagnóstico de posição do banco.

O [índice temporal consolidado](../../evidence/fleet-redesign-20261011/temporal/capture-summary.json) reúne **sete casos finais, 3.294 quadros e 244,826 s de gravação**, com links para vídeos, telemetria, revisões e tentativas rejeitadas preservadas.

| Caso e revisão | Tentativa | Quadros | Duração (s) | Maior intervalo (ms) | Resultado observado |
|---|---|---:|---:|---:|---|
| [Union Sedan](../../evidence/fleet-redesign-20261011/temporal/attempt-03/union_sedan/visual-review.json) | 03 | 497 | 34,969 | 128,329 | Fluxo aprovado; grade cinza/faróis brancos após correção, sem novo defeito aparente nas amostras |
| [Police Cruiser](../../evidence/fleet-redesign-20261011/temporal/attempt-03/police_cruiser/visual-review.json) | 03 | 434 | 35,005 | 1.449,006 | Fluxo aprovado; fases vermelha/azul observadas, com intervalos longos limitando a continuidade |
| [Atlas Crew Pickup](../../evidence/fleet-redesign-20261011/temporal/attempt-03/atlas_crew_pickup/visual-review.json) | 03 | 429 | 34,973 | 1.025,355 | Fluxo aprovado; porta/acabamento unidos e caçamba vazia íntegra nas amostras |
| [American Tanker Truck](../../evidence/fleet-redesign-20261011/temporal/attempt-03/american_tanker_truck/visual-review.json) | 03 | 485 | 34,973 | 261,607 | Fluxo aprovado; seis rodas na telemetria, cabine/tanque e luzes coerentes nas amostras |
| [Armored Truck](../../evidence/fleet-redesign-20261011/temporal/attempt-04/armored_truck/visual-review.json) | 04 | 473 | 34,936 | 352,025 | Fluxo aprovado; chapas inferiores da porta restauradas e observadas durante entrada/saída |
| [Medic Box](../../evidence/fleet-redesign-20261011/temporal/attempt-04/medic_box/visual-review.json) | 04 | 516 | 34,975 | 127,280 | Fluxo aprovado; destino do motorista corrigido para a cabine e sem cabeça na junção com o baú nas amostras |
| [Beach Cabriolet](../../evidence/fleet-redesign-20261011/temporal/attempt-04/beach_cabriolet/visual-review.json) | 04 | 460 | 34,995 | 1.888,765 | Fluxo aprovado; destino do banco corrigido; para-brisa/painel ocultam a pose sentada nesta câmera |

**Limite da conclusão:** os sete reviews permanecem `reviewed_with_limitations`, com `visual_approved=false`. Foram inspecionados quadros originais selecionados e trechos consecutivos, cruzados com telemetria por quadro; os MP4 preservam os timestamps. Isso não equivale à inspeção de cada pixel de toda a gravação nem certifica ausência geral de flickering/popping. As fases intencionais do giroflex e o desligamento comandado ao sair foram distinguidos de falhas de iluminação. Semáforos e postes que passam diante da câmera também ocultam partes dos veículos. As novas tentativas resolvem as regressões localizadas do banco da ambulância/conversível e da chapa da porta blindada, sem certificar todos os interiores ou animações.

A cadência de aproximadamente **12–15 quadros/s inclui leitura do viewport e gravação das imagens**; não é um benchmark de gameplay. Não houve omissão de quadros desenhados nem falha de gravação nos sete casos finais, mas os intervalos de 1,449 s da viatura e 1,025 s do Atlas deixam transientes sem resolução. O maior intervalo do conversível, **1,889 s**, ocorreu depois da saída, com velocidade zero; seus extremos foram inspecionados, mas não existe imagem intermediária e a causa da pausa não foi isolada. Nem esses números nem o contador de FPS das fotos substituem a medição sem capturas.

A frenagem em movimento ficou pouco amostrada: Union, viatura, Atlas, blindado, ambulância e conversível finais têm **zero** quadros acesos de freio ainda em movimento; os respectivos 21, 20, 15, 21, 28 e 24 quadros são de freio de mão parado. O tanque tem apenas **um** quadro em movimento, já a 0,210 m/s, além de 20 parado. A câmera alta/frontal esconde grande parte das lanternas traseiras e do encaixe fino de mãos, pés e motorista sentado. A posição dos dois bancos corrigidos foi sustentada também pela telemetria e pelos testes separados com Actor real; a oclusão do personagem não foi usada como prova de encaixe. A cabine opaca da ambulância e o para-brisa/painel do conversível impedem aprovação visual completa da pose interna. Chuva, outros mapas, túneis, alta velocidade, ré, dano, restauração de save e interações de carga/cofre não foram exercitados por estas gravações; sua cobertura dirigida está documentada separadamente.

A galeria contém **236 fotos reais dos 59 modelos**: frente e traseira, antes e depois; todos os caminhos do inventário foram conferidos. As vistas dos recursos corrigidos foram atualizadas, incluindo o blindado após restaurar as chapas. Há ainda [dez vistas das cinco picapes vazias/carregadas](../../evidence/fleet-redesign-20261011/utility/validation-summary.md) e fotos da variante de sorvete. Fotos estáticas documentam desenho e encaixes nos ângulos mostrados; não comprovam estabilidade temporal nem performance.

[Galeria antes/depois dos 59 modelos](../../evidence/fleet-redesign-20261011/review.html) · [Inventário de geometria](../../evidence/fleet-redesign-20261011/manifest.json).
