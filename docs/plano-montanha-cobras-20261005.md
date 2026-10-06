# Missões e corridas da montanha de gelo

A montanha terá pelo menos duas missões ou side quests com objetivos próprios. O pacote definido nesta conversa reúne duas investigações ligadas aos Cobras e a Vicente, uma descida noturna contra seis rivais e uma corrida de jipe por checkpoints. O jogador terá motivos narrativos e desafios de direção para visitar o mapa.

Este documento registra a direção solicitada e o estado do pacote. Os módulos das quatro atividades foram escritos em arquivos novos por três subagentes, com um agregador de sessão e um patch de integração preparado. O patch ainda não foi aplicado: outra sessão está corrigindo e testando Jessica, chegada, streaming e áudio. As atividades ainda não estão habilitadas nem validadas no jogo. Consulte [a entrega para integração](integracao-montanha-20261005.md).

## Conteúdo existente

O avião acidentado já está no lago da montanha, em `world/regions/NativeRegion.gd`, nas coordenadas originais `(5450, -1150)`. `world/places/CargoPlaneNative.gd` monta o corredor acessível, os sólidos e as recompensas existentes do avião.

A Caverna da Queda já consta em `world/places/PlaceCatalog.gd`, nas coordenadas originais `(6200, -320)`. Há mochila, diário e câmera da expedição em `activities/ActivityDefinitions.gd`, usados pela progressão de esqui. As coordenadas são locais da região na escala original; os adaptadores existentes fazem a conversão para o mundo 3D.

As sete missões atuais de `data/campaign/HarborMissions.gd` acontecem em Harbor. O diálogo de Neco já menciona uma ordem assinada por V. Ferraz e a rota da serra, oferecendo um gancho para levar a investigação à montanha. A corrida urbana atual reúne seis participantes no total; a nova descida precisa de sete, pois o pedido é de seis adversários.

## Investigar a carga dos Cobras

A implementação isolada usa a side quest **Carga dos Cobras**, com duas descobertas físicas no avião. A proposta anterior de ampliar **Cortar o abastecimento**, antes de **A última volta**, fica reservada à agente da campanha: este pacote não altera a ordem das missões nem exige migração de objetivos de Harbor.

O jogador chega ao lago, acessa o compartimento de carga pelo corredor real e encontra um manifesto de transporte. A identificação visual das caixas e do avião estabelece a ligação com os Cobras; o documento relaciona a carga à rota mencionada na ordem de serviço. A coleta física conclui a investigação da carga e aponta a caverna como um lugar para procurar mais vestígios.

O estado novo usa recibos próprios para as descobertas. O dinheiro e a SMG do avião conservam os recibos existentes; examinar o manifesto não os concede novamente. Saves antigos começam as side quests sem apagar progresso ou exigir repetir colecionáveis já recolhidos.

## Encontrar o rastro de Vicente

Proposta de side quest: **Rastro de Vicente**, iniciada pela pista encontrada no avião. Dante precisa percorrer o acesso real entre o lago e a caverna e examinar um vestígio específico dentro dela.

A proposta narrativa é uma anotação de Vicente acompanhada de um objeto pessoal que Dante reconhece. Ela mostra que Vicente usou o lugar como abrigo pouco antes da chegada de Dante e depois seguiu para o deserto. A descoberta produz o quase encontro pedido pelo usuário: Dante esteve perto do irmão, mas chegou depois que ele partiu.

O módulo preparado usa uma anotação e uma arruela presa em um cordão, reconhecida por Dante, com diálogos em português e inglês. A pista estabelece a passagem recente de Vicente sem antecipar toda a história da prisão e da armação, reservada ao ato 2. A apresentação física e a leitura dos objetos ainda precisam ser verificadas na cena.

Os três colecionáveis da expedição e a abertura da Pista da Sombra conservam sua progressão. O vestígio de Vicente precisa de estado próprio, inclusive para saves que já recolheram o diário e a câmera. Descoberta, diálogo e conclusão ficam persistidos sem recompensas duplicadas.

## Descer a serra à noite

Proposta de corrida paralela: **Descida da Meia Noite**. Dante disputa uma prova de carro em alta velocidade contra **seis NPCs competitivos**, formando um grid de **sete carros**. A rota desce pela estrada da montanha, com largada no alto, checkpoints sequenciais e chegada em um trecho inferior com espaço para desacelerar.

O módulo aceita largada entre 20h e 5h, limite de 240 segundos e prêmio único de R$ 2.400 pela primeira vitória. O relógio do mundo não é alterado para iniciar a corrida. Esses valores ainda precisam de calibração dirigindo. A largada verifica o apoio e o espaço dos sete carros antes de reposicionar Dante, e a chegada reserva 75 metros de estrada para desacelerar.

Os rivais aceleram, freiam, esterçam, ultrapassam quando há espaço e se recuperam de erros usando a física real dos veículos. A dificuldade deve vir da direção competente e dos carros escolhidos. Todos passam pelos mesmos checkpoints, com colisão e sem teleporte para avançar na classificação. Retas devem permitir velocidade alta; curvas precisam de frenagem e leitura antecipada.

Faróis, contraste do asfalto, bordas e marcação dos checkpoints devem permitir dirigir à noite. A adaptação do cenário inclui áreas de largada e chegada, proteção nos pontos de queda e correção de obstáculos que invadam a pista, preservando a atmosfera da montanha.

## Disputar a trilha de jipe

O módulo **Trilha dos Pinheiros** é uma prova de jipe contra o relógio, com checkpoints em ordem e limite provisório de 110 segundos. Fornece um `desert_jeep_4x4` persistente ao lado da largada e aceita outro jipe do mesmo arquétipo. A primeira conclusão concede R$ 700; as seguintes registram tempos sem repetir o prêmio.

A trilha terá um corredor próprio de terra, pedra e neve, ligado a um acesso viário existente. O cenário precisa receber piso com colisão correspondente, curvas compatíveis com o jipe, trechos de subida e descida, marcas de pneus e portões legíveis. Árvores e pedras devem formar o desafio sem bloquear completamente o veículo.

Não transformar o acesso pedestre da caverna em pista de carros. Preservar os caminhos dos moradores, o esqui e o teleférico. A largada e a chegada devem permitir entrar, parar e retornar ao mundo aberto. Atalhos que ignorem checkpoints não concluem a prova; trocar de veículo ou sair a pé interrompe a tentativa.

## Progressão e cenário compartilhado

O pacote preparado mantém as duas investigações como side quests independentes; o rastro de Vicente segue a investigação do avião. As duas corridas e as investigações recebem acompanhamento pelo diário e objetivos funcionais no HUD quando os ganchos de integração forem instalados. Não foi aplicada nenhuma mudança à sequência que a outra agente está desenvolvendo.

A ponte para o mapa 2 continua em construção até a conclusão da última missão da cidade 1. O conteúdo da serra precisa ser acessível durante o ato 1; a implementação não deve confundir esse acesso com a ponte bloqueada para o mapa 2.

Esclarecimento do usuário em 05/10/2026: preservar a disposição da V1, com a continuação para cima/norte levando ao mapa 2 e a saída lateral à direita/leste levando à ponte da montanha. A saída precisa ter uma alça/derivação física reconhecível, conectada antes do bloqueio da obra, permitindo visitar e deixar a serra durante a cidade 1. A barreira e o término da construção pertencem somente ao ramal norte. O código da ponte foi posteriormente integrado em `world/north_gateway/`, com acesso junto ao retorno existente, canteiro, quatro operários e abertura pela conclusão da missão final. A execução no motor continua pendente; consulte [a revisão da ponte](../evidence/auditoria-viaria/2026-10-05-north-gateway/relatorio.md).

A leitura do ramo `v1-legado` confirmou essa separação em `world/harbor/HarborGateway.gd` (continuação norte e saída leste), `HarborNorthAccess.gd` (acessos próprios, inclusive passagem abaixo da ponte da montanha) e `HarborGatewayWorks.gd` (canteiro e barreiras ao norte). Os eixos das obras são `x=5860/6020`, com barreira em `y=-5510`, nas unidades originais da V1. Na V2, `WorldConnection3D.gd` implementa a conexão leste Harbor–montanha; os IDs antigos `map2_highway_inbound/outbound` no JSON não significam que essa conexão seja o mapa 2. Cruzamentos em alturas diferentes não podem virar junções de tráfego por proximidade em planta.

A V1 mantinha a fronteira fechada mesmo após `set_works_complete`; esse comportamento legado não atende à regra atual do usuário. O novo módulo lê o registro validado da campanha, inclusive saves antigos migrados, remove as barreiras da obra e completa o vão após a missão final. A V2 ainda não implementa a região do mapa 2: a extremidade acabada tem proteção e espaço para retornar, sem simular viagem para uma região inexistente. O acesso oeste seguido para norte evita cruzar a via leste, que na V2 está no mesmo nível. Somente `WorldConnection3D.gd` e `CoastalProtection.gd` receberam ganchos; os arquivos em edição pela outra agente foram preservados. Nenhum processo Godot foi iniciado nesta etapa.

O avião, a caverna e os percursos devem comunicar sua função pela aparência. Preservar a regra do projeto sobre ausência de textos decorativos; usar texto para interação, diálogo e objetivo quando necessário.

## Implementação e validação pendentes

- Integrar os objetivos, diálogos, marcadores e persistência das duas investigações; verificar acesso real ao avião e à caverna, colisão e oclusão separadamente.
- Adaptar o percurso noturno e criar a trilha de jipe com continuidade visual e física. Comparar cenário, grafo viário e comportamento dos motoristas onde a estrada for alterada.
- Exercitar a descida com os seis NPCs reais, checkpoints, classificação, vitória e derrota; observar condução, ultrapassagem, colisão e recuperação durante a prova inteira.
- Exercitar o percurso de jipe completo, checkpoints fora de ordem, tentativa de atalho, veículo incorreto e interrupção da tentativa.
- Verificar pausa, morte, prisão, cancelamento, troca de região e repetição das atividades; restaurar controles e remover rivais, marcadores e áudio da tentativa encerrada.
- Validar save e load em armazenamento temporário isolado, compatibilidade com saves anteriores e ausência de pagamentos repetidos indevidamente.
- Medir frame time antes e depois na cena real renderizada, incluindo primeira visita, largada dos sete carros, descida ativa à noite, trilha e retorno após cancelamento. Registrar p50, p95, p99 e picos com a mesma configuração e sem benchmarks concorrentes.
- Observar temporalmente a iluminação noturna e os faróis em movimento. Capturas isoladas e testes headless não aprovam iluminação, apresentação ou FPS.

Foram consultadas as skills do projeto pertinentes à implementação. Passaram as checagens leves de sintaxe e referências dos módulos e das prévias; nenhum build, teste Godot, benchmark ou captura foi executado nesta entrega concorrente. Os itens de integração e validação acima permanecem pendentes e não devem ser contados como aprovação física, visual, de iluminação ou de performance.
