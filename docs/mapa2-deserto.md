# Mapa 2 — deserto

Estado em 06/10/2026: módulos, integração central e revisão de detalhes aplicados. A validação usa Godot 4.7.2 .NET e fila compartilhada com os chats de estacionamento e ambiente sonoro. Ponte, progressão/economia/carros, colisão/oclusão dos interiores, corrida física e oficina com recarga passaram. A revisão visual cobriu dez pontos no Main e a sequência temporal da primeira corrida. Medições renderizadas concluídas; desempenho permanece **pendente**, com piora e picos registrados abaixo.

## Missões secundárias — Bia e Raul

- **Peças na estrada:** fale com Bia no pátio do Digo, aceite a entrega, leve as peças a Raul no Miragem e devolva o recibo à Bia. Pagamento único de R$ 1.200.
- **O último ramal:** fale com Raul no Miragem, confira o livro de despachos na antiga estação, compare o lacre da carga no vagão descarrilado e retorne a Raul. Pagamento único de R$ 2.200. A descoberta é independente das provas da campanha de Vicente.
- Os contatos preservam a opção **Conversar**. É possível aceitar as duas tarefas, alternar o acompanhamento ou voltar ao objetivo da história principal pelo menu dos contatos. O HUD aponta a etapa acompanhada; arrancadas em andamento mantêm prioridade.
- Etapas e recibos persistem em `desert_contracts`, com validação cruzada da carteira. Save antigo sem essa chave continua válido. Uma carteira cheia mantém a entrega pendente. Repetir a interação não duplica pagamento.
- As novas falas têm legenda, ainda sem gravações de voz. Não foram adicionados prédios, luzes, NPCs ou loops por frame; os objetivos usam contatos e vestígios físicos existentes.

Validação e limites: [missões secundárias do deserto](reviews/desert-contracts-20261006.md).

## Direção e percurso

A continuação norte da ponte, depois da missão final de Harbor, chega a uma rampa de 71,5 m e às rodovias do deserto. O acesso leste à montanha e a condição da obra permanecem independentes. A cidade é pequena, com construções baixas de reboco/adobe, marquises, coberturas planas e tons de areia. Fachadas exibem somente nomes próprios.

As estradas seguem a referência Route 66: asfalto desbotado, fissuras e remendos, faixas gastas, acostamentos de cascalho/areia e retas longas. A rodovia de chegada tem aproximadamente 1,16 km; a reta sul, 1,54 km. Mesas rochosas e a bacia distante mantêm o horizonte desértico enquanto os detalhes e colisões próximos carregam por células.

O posto Miragem possui quatro bitrens, cada um com dois reboques. Cobre é um banco próprio, Digo tem uma oficina acessível, e o Horizonte marca o encontro com Vicente e o descanso até a noite. Banco e oficina têm geometrias interiores próprias; não são cópias do banco de Harbor.

## Corridas e preparação

A pista comporta dois carros lado a lado e 800 m de prova, mais escape. Os eventos abrem entre 20h e 5h. Digo, Lívia, Raul, Jessica e Nadir usam veículos físicos e progressão sequencial; todas as provas têm 800 m. A simulação de transmissão mediu 19,78–24,65 s nos cinco carros originais e 15,58–19,42 s com preparação completa. Isso cobre a mecânica isolada; a primeira prova física no Main também passou no intervalo de 15–30 s, com 39 checks do fluxo e recuperação.

A apresentação inclui câmera lateral baixa, velocímetro, conta-giros, marcha, sinal de largada e nitro. Espaço troca marcha, Shift aciona nitro, acelerador mantém o giro e Q abandona; o módulo também trata comandos de controle. Largada antecipada, cancelamento, destruição e recuperação restauram câmera/controle sem registrar vitória fictícia.

Os cinco novos carros são Faísca GT, Coyote 440, Siroco T, Bison D e Mirage R. O mesmo modelo de força, rotação, câmbio, patinação e nitro atende condução livre e drag. Treze peças alteram motor, turbo, câmbio, pneus, peso, nitro, suspensão e escape com vantagens e perdas. O áudio acompanha giro/carga e preparação.

Terminar a prova com Digo, mesmo perdendo, libera sua oficina. Vitórias diferentes liberam peças; a primeira vitória sobre cada rival concede um prêmio único. Carteira cheia mantém prêmio pendente. A oficina permite preparar o carro selecionado estacionado no pátio, guardar três conjuntos de ajustes e comprar carros. A entrega verifica a vaga antes da cobrança. Peças e carros usam recibos da economia existente e identidade persistente por veículo.

## História

Vicente, Lívia, Raul, Nadir, Bia e Irene têm apresentações próprias. O encontro com Vicente inicia a investigação da carga dos Cobras no posto; o manifesto permite conferir a autorização no Cobre. O reencontro com Jessica integra as provas noturnas. A prova da armação é levada a Vicente, preservando sua reação aos oito anos perdidos. O resultado da corrida de Jessica é físico, sem vitória roteirizada artificial.

## Integração e validação

Os módulos ficam em `world/desert`, `activities/desert_drag`, `gameplay/desert_cars`, `audio/desert_cars` e `runtime/desert`. A integração foi aplicada por `D:/geteco/artifacts/desert-20261006/integrate.py`, com prévias, hashes e cópias anteriores em `integration/`. Ela relê os arquivos compartilhados e exige âncoras únicas; não descarta alterações de outros chats. **17 arquivos centrais receberam ganchos aditivos**, preservando o trabalho concorrente. O script registra o lote aplicado; não deve ser reaplicado sobre fontes posteriores.

A fila usa `D:/geteco/artifacts/runtime-queue/active.json`, além de conferir os processos. O runner deste lote é `Run-DesertCheck.ps1` no mesmo diretório. Compilar `Harbor.csproj` e usar exclusivamente Godot 4.7.2 .NET; nenhuma validação pelo fallback GDScript.

| Verificação preparada | Situação |
| --- | --- |
| `gdparse` dos módulos e prévias centrais | Passou na revisão sintática; não substitui parser/execução Godot |
| `test_desert_drag_progress.gd`, `test_desert_save_and_garage.gd` | Passaram: 47 checks de corrida e 22 de save/garagem |
| `desert_cars_powertrain.gd`, `desert_cars_fleet.gd` | Passaram: tempos, ganhos/perdas, modelos, portas e integração de frota |
| `desert_world_contract.gd` | 71 checks passaram: piso, pneus, entradas, bitrens, streaming, minimapa, prédios fora das ruas e camadas da rampa |
| `test_desert_session.gd` | 14 checks passaram: embarque real, direção ponte→rampa→deserto, desembarque e save em disco isolado |
| `test_desert_drag_runtime.gd --temporal` | 59 checks passaram: Main, dois carros físicos, chegada real em 19,94 s, Espaço/Q pelo input real, queimada/abandono/destruição/pausa, faróis, câmera limitada e supressão/restauração do HUD comum |
| `desert_cars_workshop_session.gd` | 49 checks passaram: interface real, compras e vaga, save/load do Main, pintura/dano e streaming; correção de disputa de foco no HUD |
| `desert_world_depth.gd` | 52 checks renderizados passaram; colisão e oclusão separadas, Actor/NPC reais |
| `desert_detail_capture.gd`, `desert_cars_capture.gd` | Dez pontos no Main capturados; moradores observados caminhando no piso, trocas de área sem erros; cinco carros e conjunto capturados em fixture própria |
| `desert_roads_geometry.gd`, `desert_curve_drive.gd` | 30 contratos de vias e 28 checks no Main passaram, incluindo três curvas conduzidas com input e caminhada ao Cobre |
| `desert_bank_return.gd --blocked-return` | Reproduziu carro estacionado bloqueando os cinco pontos antigos; após correção, saída lateral passou com o mesmo carro imóvel e verificação real de piso/cápsula |
| `measure_desert_gateway.gd`, antes/depois | Comparativo estático: antes p95/p99 4,130/5,318 ms; depois 6,639/8,201; confirmação instrumentada 7,200/9,006. Piora confirmada; atribuição pendente |
| `measure_desert.gd` | Rodada final completa e válida, sem sobreposição ou alteração de fontes; cinco cenários, entradas/saídas e direção física passaram. Desempenho pendente: aumento de tempos e picos de primeira visita |

Não há aprovação de desempenho nem certificação de estabilidade temporal de toda a iluminação. Física/oclusão e transições dos interiores passaram; a certificação integral ainda depende de desempenho e cobertura temporal própria dos interiores. As medições devem permanecer serializadas e usar saves exclusivos das fixtures.

### Revisão de acabamento solicitada em 06/10

A primeira versão visual foi rejeitada por falta de detalhes, superfícies planas, escala e conexões viárias. A revisão divide o trabalho em direção de arte dedicada, geometria/fiação e materiais/ambiente, com uma única fila de execução do motor.

- Rodovias com curvas de raio 40 m, rua do Digo com raio 16 m, bocas de cruzamento arredondadas e faixas interrompidas nas conexões. A via e a colisão seguem os mesmos polígonos; as rotas usam suas linhas centrais. Barras de retenção correspondem às paradas do trânsito existente. O Cobre recebe terminal arredondado e rampa para seu passeio.
- Rede de postes de madeira com travessas, isoladores, três condutores com flecha e ramais de serviço. Geometria estática descarregada junto das células; não acrescenta luzes por poste.
- Reboco, alvenaria, coberturas e pavimentos texturizados; janelas recuadas, climatizadores, conduítes, mobiliário, ferramentas e detalhes dos bitrens. O posto passou a duas coberturas menores; a lanchonete recebeu terraço lateral visível. Sem legendas decorativas.
- Areia com variação mineral e relevo de iluminação, acostamento em cascalho, asfalto com remendos e fissuras, pedras facetadas, gramíneas ao vento, poeira e aves. A captura no Main identificou cores sRGB usadas incorretamente como lineares no shader; a paleta foi corrigida antes de nova revisão.
- Cinco rotinas de moradores usam Actor nativo, colisão, reação e o teto existente de população. A captura entre áreas revelou referência a morador já removido pelo streaming; a leitura agora verifica validade antes de converter o corpo.

As verificações viárias incluem 6.276 amostras de rotas com largura de carro, raios sobre curvas/cruzamentos e postes fora das vias/prédios. `desert-world-3` passou os 71 contratos sobre a geometria revisada. `desert-gateway-progress` passou 40 checks da condição de abertura e migração de saves. `desert-modal-regression` passou 24 checks independentes de teclado/controle, resgate e prisão após a correção de foco.

A rodada final `desert-roads-3` passou **30 checks**, agora com terminal do banco e três pontos da rampa física. `desert-curves-drive-1` passou **28 checks no Main**: Coyote percorreu 124,56 m na curva da Route 66, Bison 117,59 m na curva oeste e Faísca 55,08 m na rua do Digo. Nenhum canto dos cascos saiu do asfalto, nenhum contato lateral, dano ou perda de apoio; erro máximo até 15 cm em relação à rota. O teste aplica acelerador/direção analógicos, sem escrever pose ou velocidade durante o percurso. Dante caminhou de fato pela rampa até a entrada do banco e fez a transição de ida e volta. Evidência: `evidence/desert-curve-drive-54884-7050518`.

A sequência antiga identificou faróis solicitados mas apagados no rival e recuo exagerado da câmera. `VehicleEquipment` agora reconhece a posse física temporária da prova, sem atribuir ao jogador o controle do adversário; a limpeza remove essa condição e preserva o orçamento normal do tráfego. A câmera recua no máximo 27 m, acompanha Dante e indica posição/distância do rival quando a vantagem real o leva para fora do quadro. Não há teletransporte ou alteração artificial do resultado. `desert-temporal-3` passou **59 checks**, corrida física de 19,943 s contra 23,905 s do rival; evidência em `evidence/desert-drag-temporal-59764-41845574`. O HUD da corrida começa preenchido e o HUD comum retorna após vitória, queimada, abandono e destruição. Os testes de destruição ocorrem depois da sequência limpa, evitando fogo residual nas imagens. A inspeção e seus limites estão em [desert-temporal-20261006.md](reviews/desert-temporal-20261006.md); não certificam toda a iluminação nem desempenho.

Uma execução de benchmark parou na saída do Cobre. O diagnóstico normal subsequente não reproduziu essa falha, mas o caso controlado com Coyote estacionado mostrou todos os cinco pontos antigos bloqueados. O banco agora declara dois retornos laterais no pátio, usados somente se livres de sólidos e com piso. A reprodução falhou antes (`evidence/desert-bank-return-87180-6853752`) e passou depois (`evidence/desert-bank-return-69448-7341101`), sem mover o carro. Isso corrige o bloqueio demonstrado; não comprova retroativamente a causa exata da primeira falha sem telemetria.

O comparativo de acabamento usa `evidence/desert-main-measure-54904-5114338` como baseline auditado. Seu relatório bruto permanece `source_stable=false`: apareceram apenas dois shaders novos ainda não referenciados durante a execução; os hashes de todos os arquivos preexistentes permaneceram iguais. Não se altera retroativamente esse sinalizador. As cenas duram 30 s após aquecimento, no Main .NET renderizado, 1280×720, RTX 4060 Laptop, população solicitada 24.

A rodada final `desert-main-after-detail-3`, em `evidence/desert-main-measure-47640-7199804/report.json`, terminou com `valid=true`, `source_stable=true`, stderr vazio e nenhuma sobreposição de processos. As transições de Cobre e Digo passaram. A direção física percorreu 161,50 m (antes 164,86 m).

| Cenário | Antes p95 / p99 (ms) | Depois p95 / p99 (ms) | FPS médio depois | Máximo depois (ms) | Frames >33,3 / >66,7 ms |
| --- | --- | --- | --- | --- | --- |
| Posto diurno | 5,850 / 7,485 | 7,078 / 9,013 | 255,9 | 41,619 | 1 / 0 |
| Cidade noturna | 8,677 / 10,796 | 10,185 / 12,898 | 180,9 | 24,484 | 0 / 0 |
| Cobre | 6,283 / 7,517 | 6,435 / 8,238 | 272,5 | 15,534 | 0 / 0 |
| Digo | 6,203 / 7,575 | 4,319 / 5,749 | 422,8 | 12,070 | 0 / 0 |
| Rodovia, primeira passagem | 6,512 / 7,819 | 8,459 / 10,528 | 207,7 | 128,377 | 6 / 6 |

**Desempenho não aprovado.** O aumento supera o sinal de 5% em vários cenários e a primeira visita tem seis picos acima de 66,7 ms. A referência possuía 24 pedestres e 9/20/20/20/9 veículos; a execução final tem 24/24/23/23/24 pedestres e 7/17/17/3/9 veículos. A melhora da oficina não pode ser atribuída ao acabamento: há muito menos veículos. Mudanças compartilhadas de outros chats também ocorreram entre as medições. Assim, o par documenta o custo observado, mas não isola causalidade de um módulo. A primeira tentativa posterior, `desert-main-measure-126428-6455432`, é inválida como benchmark por sobreposição de dois headless; a segunda parou na transição e não gerou relatório final. Não misturar essas tentativas com a rodada válida.

### Limites visuais desta revisão

O agente dedicado inspecionou dez capturas diurnas no Main, em `evidence/desert-detail-main-76852-5157284`. A revisão confirma fiação, materiais, objetos nas fachadas, ferramentas, terraço, varanda, acesso do Cobre e bombas visíveis. Restam pátios com grandes vazios, arquitetura/telhados de volumes simples e repetição perceptível do padrão do asfalto. Os quatro bitrens ainda repetem cobertura/cor; as fotos traseiras não certificam cabines e engates. Esse registro não equivale a acabamento artístico definitivo nem a revisão noturna de todos os locais.

### Ponte — comparação de desempenho

O comparativo estático usa a mesma câmera, posição, horário, resolução e parâmetros no Main .NET: `evidence/desert-gateway-static-candidate-complete-90800-4824936` antes, `...-178276-6446602` depois e `...-2932-8441498` na confirmação instrumentada. Antes p95/p99 4,130/5,318 ms; depois 6,639/8,201; confirmação 7,200/9,006. A confirmação registrou 277,45 FPS médios, máximo 44,404 ms, um frame acima de 33,3 ms e nenhum acima de 66,7 ms. As duas execuções posteriores têm fontes estáveis, erros vazios e nenhum motor concorrente.

A piora se repete, portanto **não aprovada**. População/composição de veículos e trabalho concorrente entre versões limitam atribuição; no primeiro par, pedestres médios 11,90→12,27, veículos 13,23→13,67 e draw calls finais 85→122. Não há postes/cidade nas três células do deserto próximas desta câmera. `NativeTrafficRoutes` e `Harbor.dll` mantêm hashes iguais nesse par. A confirmação acrescenta instrumentação existente de custos >2 ms, coleta de regiões/grafos/modelos a 1 Hz e seu próprio overhead; esses dados não equivalem a profiler completo de CPU/GPU. O teste móvel anterior parou num veículo existente e não é evidência de percurso aprovado.

O pico isolado de 44,404 ms coincide no mesmo quadro com `population_job:traffic` de 34,065 ms, contendo criação de `ranch_single` de 30,877 ms e `vehicle_ready_pivots` de 29,586 ms. São spans aninhados: não somar suas durações. Isso demonstra a origem desse pico, mas não explica a piora sustentada de p95/p99. O diálogo de Dante aparece nas capturas antes/depois; a confirmação registra `modal=true` nos 30 samples de regime estável. A referência não registra o estado modal continuamente. Portanto este comparativo cobre a câmera estática com diálogo observado, não condução livre; a condução possui a medição independente acima.

### Evidências confirmadas

- Ponte real e save: `evidence/desert-session-64812-8556898/arrival.png`; logs `D:/geteco/artifacts/runtime-queue/desert-session-4.*`.
- Oficina e recarga completa: `evidence/desert-workshop-session-54988-7507128`; logs `desert-workshop-4.*`.
- Colisão/oclusão: `D:/geteco/artifacts/desert-20261006/depth`; logs `desert-depth-2.*`.
- Frota/áudio: `desert-fleet-2.*` inclui observação de RPM do tráfego sem modificar forças, transmissão do jogador ou drag.
- Mundo: `desert-world-2.*` inclui regressão de rua atravessando prédio e camadas da rampa flutuando. Primeira captura visual revelou esses defeitos e a areia quadriculada. Nova captura `D:/geteco/artifacts/desert-20261006/world-final` confirma o contorno livre, areia contínua e quatro bitrens enquadrados; a sequência do componente tem 349 quadros em 30 s, insuficiente para concluir estabilidade de alta frequência. A sequência integrada será avaliada separadamente.

### Cânion, fauna e descobertas — 06/10

O horizonte da drag recebeu cristas rochosas irregulares no lugar dos cilindros. Além da rodovia de sal, a entrada em `(-860, 0, -1540)` conduz ao cânion com piso físico contínuo e uma alça de terra até o platô de 22 m. Rochas, vegetação seca, três cobras e dois escorpiões completam as margens; a vegetação maior tem colisão e preserva os acessos.

A casa abandonada em `(-1300, 0, -1720)` e a cabana a 35 m dela contêm objetos recolhíveis e recompensas persistentes. A pista da casa liga a exploração a Vicente sem antecipar a revelação do ato 2. Mais adiante há um acampamento de três bandidos, com projéteis, cobertura, saque e derrotas salvas. A abertura da ponte continua dependente da missão final da cidade 1.

O [relatório da fronteira](deserto-fronteira-validacao-20261006.md) separa os resultados: ruínas 90 checks aprovados; combate 33. A câmera do relevo recebeu correção local para evitar atravessar encostas; o percurso da versão final passou 37 checks, com 551,6 m de subida, 100,7 m de retorno e duas saídas normais do carro. O refinamento local das encostas reduziu os dentes grandes das sombras e conserva correspondência entre malha visível e colisão; ainda resta serrilhado fino. As aves receberam corpo, cabeça, cauda e asas segmentadas. Há medições renderizadas válidas, mas desempenho não está aprovado; a comparação e seus limites constam no relatório. A falha isolada de inicialização dos bandidos não foi declarada corrigida só por não reaparecer na rodada seguinte.
