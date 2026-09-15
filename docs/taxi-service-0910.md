# Táxis amarelos e corridas

O táxi de tráfego usa `YellowCabModel.gd`: sedã amarelo, faixa quadriculada, identificação lateral e letreiro TAXI no teto. A faixa e as letras acompanham a abertura da porta.

Perto de um táxi com motorista, **E** abre a escolha entre entrar como passageiro e roubar. Entrar mantém o motorista e acomoda Dante no banco direito; roubar usa a ejeção e as reações de `CarjackedDriver` já existentes. Táxis estacionados sem motorista continuam usando a entrada normal para dirigir.

Depois do embarque, o motorista pergunta **“Para onde vamos?”**. O mapa mostra 12 pontos exteriores da cidade: garagem, delegacia, hospital, oficina, bombeiros, Pay 'n' Spray, cemitério, ferro-velho, Ammu-Nation, banco, posto e loja de roupas. Clique num marcador ou na lista e confirme. Os pontos são obtidos dos nós reais do mundo; não usam as coordenadas das salas interiores.

A corrida acontece pelas faixas e conexões do grafo viário, com as mesmas reservas de cruzamento, semáforos, travessias e verificações de colisão do tráfego. Destinos sem rota conectada ficam indisponíveis para confirmação. Não há cobrança nesta implementação. O passageiro pode pedir para descer com **F / Enter**; **Esc** cancela a escolha do destino. Ao chegar, o veículo para e desembarca o personagem.

`TaxiService.gd` mantém a conversa e a rota. O contrato legado `is_driven_by_player` permanece ativo durante a corrida para manter câmera, posição do jogador e streaming ligados ao carro; `taxi_passenger` separa essa posse da câmera dos comandos de direção. O minimapa acompanha o destino da corrida. `enter_vehicle(player)` mantém a assinatura usada pelas subclasses, inclusive o ônibus.

Validação em Godot 4.7.2:

- `test_taxi_service.gd`: escolha/cancelamento, pintura, banco do passageiro, NPC preservado, destinos reais, rota indisponível, chegada, cruzamento reservado, saída forçada e roubo; passou em headless e com renderização.
- `test_vehicle_boarding_sides.gd`: embarque dos dois lados, saída, câmera e interrupções nos outros carros; passou.
- `junction_traffic_contract_test.gd`: semáforos, reserva exclusiva, troca de faixa e travessias; passou.

Evidências em `D:/geteco/artifacts/`: `taxi-yellow-cab.png`, `taxi-map.png`, `taxi-rendered-test.log`, `taxi-boarding-regression.log` e `taxi-junction-regression.log`. Os logs ainda registram avisos de configuração de teclas carregadas pelo SettingsManager e de limpeza de objetos no encerramento do projeto; não há erros de script nem falhas nos testes finais acima.
