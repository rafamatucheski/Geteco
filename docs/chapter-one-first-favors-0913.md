# Primeiro giro e a recuperação para Ferrugem — 13/09/2026

O início do capítulo agora liga o banco, o porto, a garagem e o guincho às pistas de Vicente. O trabalho entrega **Primeiro giro** e amplia **Dentro do território / contato com Ferrugem**. Esqui, compra narrativa de arma e as demais propostas do storyboard não estão implementados por esta extensão.

## Primeiro giro

1. Aceitar no quadro, junto ao jogador, prepara o horário do banco pelo `CobraCampaign.prepare_story_time("primeiro_giro")`: 10h, com a janela de chegada definida em `ChapterOneSchedule`. Aceitar à noite avança até o dia seguinte. O salto não paga recompensas.
2. Maciota explica por que Dante precisa retirar o comprovante de uma peça já paga. Helena ajudou a oficina e conhece o nome de Vicente nas transferências. Não se exige compra, saque de dinheiro do jogador ou assalto.
3. O objetivo aponta para o Banco North Pier. A entrada usa a passagem real. Dentro, Dante precisa estar a pé, próximo de Helena e com a arma guardada; a interação abre uma conversa que o jogador avança manualmente.
4. O comprovante libera a retirada da encomenda marcada no porto. Ir direto à caixa não pula o banco. A retirada exige jogador vivo, visível, a pé e com controle livre.
5. Retornar a Maciota inicia o diálogo de entrega. Ao terminar, o jogo marca a conclusão antes de conceder os $150. A conclusão repetida não duplica pagamento. A chegada da Monaliza e suas falas continuam usando a implementação de produção.

Se um assalto anterior fechou o banco, disparou o alarme ou deixou Helena indisponível, o objetivo manda sair e telefonar a Maciota junto à fachada. Essa interação exige estar fora e sem perseguição policial. Maciota explica que enviará a segunda via diretamente ao porto. O fluxo não apaga a interdição, não ressuscita pessoas e não remove consequências do assalto. Num banco funcionando, não é possível retirar remotamente o comprovante.

As fases têm objetivo funcional visível quando o jogador está livre, e o destino continua no GPS. Painéis narrativos preservam as informações em português e inglês. Trocar idioma atualiza a linha exibida sem tocar novamente a voz já em andamento.

## Recuperação para Ferrugem

1. Ferrugem recebe a peça e explica que ela pertence ao carro de uma cliente. A ordem foi aberta por Vicente. É necessário recuperar o carro de verdade antes de conseguir acesso à prova de rua.
2. A missão reserva um carro estacionado existente e o guincho amarelo do Neco. O GPS primeiro indica o caminhão; ao assumir seu volante, indica o carro da cliente. Não é criado um segundo sistema de transporte.
3. Parar com a traseira do caminhão perto do carro e usar a interação carrega o veículo pelo `TowService`. As consultas de raio e varredura física existentes impedem guinchar através de muros ou outros sólidos. É preciso estar parado e o carro precisa estar vazio.
4. O GPS aponta para a baia do Neco. O jogador precisa alinhar a traseira, parar e descarregar fisicamente. Levar o carro à baia dirigindo o próprio carro não substitui o uso da plataforma.
5. Depois de descarregar, sair do caminhão e falar com Neco confirma a entrega. Se houver perseguição, ele pede que o jogador a despiste primeiro. A ordem 017 traz a assinatura V. Ferraz e a procura de motoristas para a rota da serra.
6. Voltar a Ferrugem com essa informação conclui o contato, paga os $120 existentes uma única vez e libera a corrida. Nenhum contrato de sucata é criado, nenhum pagamento extra do guincho é concedido e o carro da cliente não pode ser levado à prensa.

A interação do caminhão é tratada pelo `TowService`, inclusive carga/descarga e mensagens de falta de espaço. Enquanto a recuperação reserva o guincho, sua oferta de novos serviços explica o compromisso atual; a recuperação do caminhão danificado continua disponível. Um serviço lateral ou carga alheia já em andamento não é cancelado: Ferrugem pede que o jogador termine antes de iniciar a recuperação.

Se o jogador abandona o guincho carregado para explorar, o GPS volta a indicar o próprio caminhão e o objetivo pede que retorne à carga. Ao reassumir o volante, o destino volta à baia. `test_story_tow_navigation.gd` valida isoladamente esses dois destinos; ele complementa o teste físico de transporte, sem substituí-lo.

## Interrupção e persistência

- Novas aceitações de Primeiro giro usam `harbor_first_favors_v3`. Saves antigos com entrega em andamento seguem o percurso original. Os checkpoints do comprovante e da peça persistem pelas flags da campanha.
- Morte/prisão interrompem diálogos da entrega sem pagar ou apagar checkpoints. No contato com Ferrugem, a missão falha e volta a ficar disponível; a reserva do carro é liberada. Destruir carro ou guincho informa a causa e permite reorganizar o serviço.
- O alvo em uso mantém `mission_vehicle`, impedindo venda à prensa. A autorização de guincho é específica e mantém as restrições para veículos pessoais, emergência, motos, carros em movimento, ocupados e destruídos.
- Salvar com o carro na plataforma grava sua identidade narrativa no payload existente do `TowService`. Ao carregar a partida, a missão interrompida exige nova aceitação; Ferrugem reconhece a carga restaurada e usa o mesmo carro, sem gerar cópia.
- Depois que Neco recebe o carro, ele continua protegido contra venda e novo guincho enquanto aguarda a cliente. A autorização temporária de transporte termina na entrega. O TowService cuida da retirada posterior, inclusive após concluir a missão: somente com jogador a mais de 700 px do carro e do pátio, carro fora da câmera com margem, parado, vazio, sem embarque nem carga. Assim a baia fica livre para próximas encomendas, sem prensa, movimento através de sólidos ou recompensa extra.

## Evidência de validação

`tests/test_first_favors.gd` executou **54 checks, zero falhas**, em HarborGame de produção, Godot 4.7.2 headless. Cobriu horário noite→10h, aceite remoto rejeitado, bloqueio de pular banco, entrada e saída caminhando pela porta real, diálogo com Helena, flags/JSON, retirada/entrega e recompensa idempotente, chegada da Monaliza, morte/prisão e retry, proteção contra prensa, carga/descarga física, deslocamento do guincho com acelerador real, save ao volante com carga e restauração integral da cena. A restauração confirmou exatamente um guincho, um carro da cliente, o motorista e reutilização da carga no retry.

As viagens entre os pontos de missão nesse teste são posicionadas pela fixture. Isso valida as integrações e os estados descritos, **não certifica dirigir todo o itinerário urbano nem seu desempenho**. A colisão/profundidade do banco e o comparativo renderizado pertencem à validação própria do banco. Capturas estáticas também não certificam FPS.

O teste aceita `-- --capture` para registrar imagens de Helena, Maciota e do guincho carregado em `D:/geteco/artifacts/chapter-one-0913/`. O teste legado `test_cobra_campaign_gameplay.gd` agora verifica que conversar duas vezes não conclui a recuperação e usa um pré-requisito concluído declarado somente para seus casos posteriores de diário, descanso e interface da corrida. Ele não simula o guincho para se apresentar como teste de transporte.

O mesmo fluxo rodou renderizado com Vulkan Mobile / NVIDIA RTX 4060 Laptop GPU: **57 checks, zero falhas**, incluindo escrita das três capturas. A imagem de retorno a Maciota foi refeita com `capture_first_favor_return.gd`, entrando pela porta real da garagem e confirmando a transição e o diálogo; esse trecho de entrada também foi acrescentado ao teste principal. As três imagens foram inspecionadas. O caso renderizado é validação funcional/visual, sem medição de FPS.

A regressão existente `test_salvage_towing.gd` passou **68 checks, zero falhas**: encomendas comuns, bloqueio de guinchar através de parede, movimento com controles, save com carga a pé e ao volante, restauração sem duplicatas, descarga, prensa, pagamento/progressão e alerta de viatura por horário. A expectativa antiga de saldo foi corrigida porque a primeira entrega também concede os $100 da conquista `first_scrap`: o teste mantém os $1800 exatos do contrato e contabiliza separadamente somente conquistas recém-desbloqueadas. Nenhuma recompensa de produção foi alterada para satisfazer o teste.

`test_garage_weapon_restrictions.gd` também passou sem falhas: entrada real guarda armas, ataques/troca/recarga permanecem bloqueados, Maciota e seu mecânico mantêm ausência de rotinas de dano e morte, saída restaura inventário/uso e restauração/respawn não deixam restrição obsoleta.

`test_cobra_campaign_gameplay.gd` terminou com **zero falhas** após atualizar suas fixtures à garagem atual: aguarda `gameplay_ready`, entra pela porta, usa o ponto de interação autorado do quadro e aguarda embarque/desembarque. Verifica aceite pelo quadro, conversa com Ferrugem, ausência de conclusão antecipada, diário/concluídos/idioma, descanso opcional, pausa modal de veículos e limpeza ao sair da cena. Na prova, R precisa preservar o motorista e iniciar a contagem **ou** explicar a quantidade real de carros que ainda sai da praça; a interdição física e a volta completa são responsabilidade do teste específico da corrida.

Arquivos principais: `HarborFirstFavors.gd`, integração em `HarborArrivalMission.gd`, `HarborStoryTow.gd`, hooks de `CobraCampaignController.gd` e extensão restrita de `TowService.gd`.

`capture_bank_furniture_depth.gd` registrou e permitiu inspecionar **10 imagens, zero posições bloqueadas**: jogador e Helena à frente, atrás e ao lado do balcão esquerdo, atrás da divisória e diante do cofre. `_placement_is_clear` aprovou cada posição. O tampo encobre pernas atrás do balcão; a divisória encobre o corpo preservando a cabeça; frente/lado/cofre mantêm o ator visível no piso. A fixture usa Camera2D fixa para comparação; geometria, Camera3D e apresentação dos atores são as de produção. Imagens em `D:/geteco/artifacts/chapter-one-0913/bank-furniture-depth/`. Esta evidência visual complementa os testes comportamentais do banco, sem medir desempenho.

`test_story_customer_pickup.gd` passou **19 checks, zero falhas** na regressão dirigida de liberação da baia: entrega a Neco, carro preservado perto/em câmera/ocupado/em embarque/carregado, retirada assíncrona após concluir Ferrugem, recompensa limitada aos $120 existentes, aceite da encomenda seguinte e carga/descarga reais do próximo carro na baia liberada. A recuperação anterior e viagens são fixtures explícitas; este teste cobre somente o ciclo de propriedade e reutilização da baia. A checagem nova roda a cada 0,5 s apenas enquanto há carro aguardando retirada.
