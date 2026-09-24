# Integração de arquitetura urbana e despacho

21/09/2026 — implementação em andamento, sem execução no Godot, testes, capturas ou medições por instrução do usuário. As medições históricas do V2 não aprovam estes módulos recém-conectados.

## Sessão e despacho

`World.dispatch` referencia o controlador nativo. `ProductionWorld` monta o controlador depois de `Gameplay`, reivindica o despacho e segura seu processamento durante a restauração inicial. Após restaurar a sessão, sincroniza a posição exterior e habilita o processamento. `skip_dispatch` e `--no-dispatch` permitem desativar a montagem para cenários isolados; não são a configuração padrão do jogo.

`FullSession.sync_dispatch_location()` mantém a porta exterior como referência durante visitas a interiores, incluindo transferências com carro nas garagens. Ao sair, volta a usar a posição física do jogador/veículo. Carregar uma sessão recolhe as unidades; resgate recolhe equipes e destroços antes de retomar o jogo. Trocar de região recolhe o despacho anterior e reconstrói o grafo sobre as novas ruas.

O controlador reutiliza procura, combate e ocorrências existentes. Viaturas não são duplicadas no tráfego ambiente nem capturadas como carro pessoal no save. Sua composição é transitória; estado de perseguição/ocorrências segue os respectivos gerenciadores.

`dispatch_owned` fecha explicitamente o envio legado em Gameplay e EmergencyManager. A troca de região invalida observadores e última posição do mapa anterior, preserva a procura e limpa ocorrências transitórias da região. A atribuição de atropelamento passa por `Vehicle.is_player_damage_source()`, sem alternar artificialmente `controlled` em cada passo físico da viatura.

## Arquitetura urbana

`NativeRegion._building` usa a fábrica para substituir cada registro original; a garagem do Maciota continua montada pelo lugar principal. Os vínculos de banco, Ammu-Nation, roupas, posto, delegacia, hospital, bombeiros e residência reconciliam nomes e posições com PlaceCatalog. As três fachadas extras do catálogo permanecem únicas.

A finalização da fábrica distingue geometria original de prédios procedurais já dotados de colisores, evitando criar trimesh duplicado sobre os BoxShape existentes. A apresentação da entrada policial foi alinhada ao acesso original. Nenhum novo interior foi adicionado.

## Estações e rodoviária

`ProductionWorld.urban_transit` monta `UrbanTransitPresentation` após a sessão e notifica a troca de região. O helper carrega seis estações e a rodoviária nas posições/faixas do V1; usa a porta exterior como foco durante visitas a interiores e remove a arquitetura ao sair de Harbor. A calibração transforma a antiga projeção do piso para a escala do mapa nativo, preservando a altura dos modelos.

O módulo é de apresentação: não cria outros ônibus, passageiros ou interações, preservando o fluxo de Arrival existente. Colisão e compatibilidade física do desembarque ainda precisam de execução. [Fontes e limites](urban-transit-presentation.md).

## Trabalho concorrente

`urban_detail` e `dispatch` já estão conectados. As entregas `mountain_detail` e `traffic_yield` entraram na etapa de integração. Próximos ownerships externos e instruções completas estão em [NEXT_EXTERNAL_TASKS](historico/NEXT_EXTERNAL_TASKS.md): Claude cuida da ultrapassagem no DispatchDriver/helpers e Antigravity de novos componentes de apresentação da prensa do Neco. O integrador não edita essas novas frentes.

## Montanha

A madeireira foi conectada ao streaming usando cabana e pilhas cobertas originais, além das pranchas nas posições da fonte. Escritório extra, galpão reconstruído e cercas sem correspondência não foram montados. O vilarejo reutiliza terreno, terminal e mobiliário da arquitetura original, omitindo fachadas que duplicariam as cinco já mantidas pelo catálogo. A reserva florestal da fonte evita árvores dentro do conjunto sem redistribuir as demais.

Fogueira e braseiro reconstruídos da entrega não são instanciados; HeatPresentation mantém as fontes originais. Seu protocolo agora reconcilia a presença de fontes do mapa e o fallback, sem transferir ou liberar nós pertencentes ao cenário. A admissão física aguarda a disponibilidade dos sólidos. [Detalhes de streaming térmico](heat-streaming-integration.md). Este lote não recebeu execução ou validação física/visual.

## Cessão de passagem — conexão

`World.traffic_yield` é montado depois do despacho, configurado com o mesmo grafo de ruas e ativado somente após restaurar a sessão. Lê os carros ambientes de ProductionWorld e as sirenes de dispatch/jogador. Troca de região, carregamento e resgate devolvem as rotas temporárias antes de recolher unidades; o novo mapa atualiza também o grafo de cessão. `skip_traffic_yield` / `--no-traffic-yield` permitem omitir o módulo em cenários isolados.

Esta conexão ativa redução de velocidade, aproximação lateral e retorno à rota implementados no módulo entregue. A entrega posterior de ultrapassagem foi conectada explicitamente em `DispatchController._make_unit`: cada piloto recebe o grafo via `enable_overtaking(routes, true)`. O planejador exige sirene e faixa livre para ocupar o sentido contrário; não existe classificação de proibição por trecho no grafo. Em ruas estreitas, curvas e cruzamentos pode aguardar. Se tráfego contrário aparecer durante o desvio, pode parar na faixa contrária até conseguir retornar. Essa limitação permanece; o comportamento não foi executado ou medido.

## Validação adiada

Ficam pendentes compilação/importação, acessos com jogador e veículos, oclusão, perseguições, atendimento completo, transições de região/interior, regras da garagem, ciclo de salvamento e desempenho renderizado. Instalar um módulo não equivale a aprová-lo nessas condições.
