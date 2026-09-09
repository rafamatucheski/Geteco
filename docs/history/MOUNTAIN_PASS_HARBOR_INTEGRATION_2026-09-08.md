# Harbor e Serra da Nevasca — entrega de 08/09/2026

Os relatórios de Claude e Antigravity foram lidos antes da integração. As instruções
do usuário prevalecem sobre as propostas e limitações históricas desses relatórios.
Os arquivos foram salvos no projeto local, preservando as alterações paralelas.
Não foi criado commit contendo indiscriminadamente o trabalho de outros agentes.

## Percurso e persistência

- A avenida norte do Harbor agora curva à direita para uma segunda ponte e leva
  oficialmente à montanha. A continuação reta permanece reservada, com obra física.
- O retorno usa a pista oposta. Foram removidas colisões de água que bloqueavam
  invisivelmente as curvas e a ponte. O grafo rodoviário foi atualizado.
- A troca de região conserva jogador e o próprio carro dirigido. Salvar/carregar
  restaura região, veículo, pintura, dano, nitro e melhorias suportadas.
- Salvar dentro do chalé restaura interior, posição de saída, temperatura e clima.
- A montanha usa HUD e menu de pausa completos. O acesso isolado continua possível.

## Montanha jogável

- Túnel com paredes físicas, corte visual do teto e aproximação de câmera.
- Interiores protegidos da neve, personagem calibrado para referência humana de
  1,80 m, colisões compatíveis e efeitos discretos de fogo, fumaça e iluminação.
- Rifle e faca são objetos 3D rotativos no chão: aproximação recolhe e anuncia a
  nova arma. Os IDs persistem no save para impedir coleta repetida de munição.
- Roupa térmica comprável no ponto comercial depois do túnel; reduz exposição.
  Frio esgotado retira vida gradualmente. Abrigos recuperam calor.
- Frente de neve cíclica, com intervalos calmos e intensidade variável.
- Três microchalés com entradas, lenha, abrigo de patrulha e sinalização. Modelos
  do Antigravity integrados com projeção e colisão no mundo 2D.
- Cinco moradores externos com parkas, acessórios, pequenas rotinas e falas locais.
  Silas também recebeu modelo humano detalhado no chalé.
- Dois ursos afastados perseguem e atacam a pé, respeitando território e intervalo
  entre mordidas. Não perseguem indefinidamente pelo mapa.
- Tráfego montanhoso com SUV, jipe e picape utilizáveis. Jipe com modelo próprio,
  SUV com rodas completas e faróis posicionados nos conjuntos dianteiros.
- Pintura altera carroceria sem tingir vidros e faróis; rodas do tráfego giram
  pelos centros reais das malhas. Whiteout é o veículo especial no alto da serra.
- Bunker explorável preparado para boss 2, limites físicos e leitura de altitude.
- Mirante 3D com cidade distante, montanhas e estrada do deserto. F abre; F ou Esc
  fecha, restaurando controle e estado de pausa.

## Colecionáveis

A tela entregue por Claude foi validada no Godot, com estados vazio, parcial e
legado. Traduções PT/EN foram integradas. IDs desconhecidos são preservados e não
alteram o denominador dos seis colecionáveis conhecidos. Contagem ignora duplicatas.

## Verificação executada

Godot 4.7.2; capturas reais em Vulkan/RTX 4060, sem reproduções HTML do jogo.

| Teste | Resultado |
| --- | --- |
| test_harbor_mountain_drive | Ida e volta dirigindo fisicamente pelas curvas e sensores |
| test_region_travel | Transferência do carro e estado entre regiões |
| test_harbor_road_contract | 22 vias, 44 faixas, 38 cruzamentos; validação sem erros |
| test_harbor_gateway | Percursos, retornos e acesso ao corredor |
| test_mountain_traffic_vehicle | Movimento, malhas das rodas, pintura, save e transferência |
| test_mountain_saved_room | Save real isolado em disco; restauração de interior e ambiente |
| test_mountain_life | Moradores, ursos, clima e pickups persistentes |
| test_mountain_cabin_scale | Escala, entradas, saída, colisões e respawn |
| test_mountain_bunker | Interior do bunker |
| test_mountain_refinement | Frio, roupa, túnel e faróis |
| test_mountain_pass_integration | Integração da região |
| test_full_driving_to_tunnel | Direção e passagem pelo túnel |
| test_in_game_fleet_integration | Frota existente e modelos 3D |
| test_pause_collectibles_screen | Progresso, ocultação, legado e fechamento |
| test_winter_props | Contratos, escala e recoloração; zero falhas |
| test_mountain_vista | Captura e restauração de controles |

Todos os testes acima passaram nas respectivas execuções. A importação final do
editor passou sem erros de script. Alguns testes headless ainda emitem avisos de
objetos restantes no encerramento; isso não foi apresentado como execução sem
qualquer aviso. Os testes de save usaram diretório próprio, sem substituir saves
do jogador.

Evidências em `D:/geteco`: `physical-both-directions2.log`, `final-saved-room.log`,
`final-cabin-render.log`, `final-winter-props.log`, `final-vista.log`,
`gateway-regression.log` e `final-project-import.log`.

Capturas reais: `harbor-mountain-connection.png`, `mountain-cabin-human-scale.png`,
`forest-settlement.png`, `winter-patrol.png`, `bear-forest.png`, `winter-fleet.png`,
`mountain-city-vista.png`, `collectibles-pt_BR.png` e `collectibles-en.png`.

## Limites e próxima etapa

- A ligação troca cenas; não é streaming contínuo. O carro do jogador atravessa,
  enquanto as frotas ambientes são populadas por região, sem persistir cada NPC.
- Os microchalés reutilizam o interior existente, com saídas exteriores distintas.
  A compra de roupa ocorre no ponto comercial exterior, sem novo interior de loja.
- O bunker é cenário funcional: combate do boss 2 e missões ainda precisam ser
  implementados. O mirante é uma prévia disponível; não há desbloqueio por vitória.
- Deserto de corridas e cidade seguinte ainda não são mapas jogáveis.
- Porta-malas e limite de armas não foram implementados. Proposta para a próxima
  etapa: duas armas longas e uma curta equipadas; excedentes guardados no veículo,
  com migração explícita do inventário antigo e persistência por carro.
- A subida usa estrada, ambientação e altitude; não converte toda a física 2D em
  terreno tridimensional com inclinação física dos veículos.

O desligamento solicitado pelo usuário será iniciado após salvar esta entrega e
concluir as verificações, sem opção de fechamento forçado de aplicativos.
