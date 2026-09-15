# Chegada de Dante — delegacia, Neko e Maciota

Implementação de 11/09/2026 no começo de `HarborGame.tscn`.

## Sequência jogável

1. A CGI e o desembarque terminam com Dante livre para ir à delegacia. O objetivo e o GPS apontam para a entrada existente.
2. Dentro, E perto do balcão inicia a conversa: soltura há alguns meses, contrabando de mercadorias para carros, rachas e busca policial. A conversa termina pedindo que Dante saia.
3. Quatro segundos depois da saída, o telefone toca. A chamada indica o ferro-velho do Neko e o sedã preto de alto desempenho de Maciota, no estilo M8 Competition.
4. E perto de Maciota inicia as apresentações. Ele confirma a chamada e convida Dante para uma volta. Maciota entra no lado do motorista e Dante no passageiro.
5. O carro sai pelo acesso do ferro-velho, segue Memorial North, Westgate Drive e Dock Street, e entra no pátio da Westgate. A rota é formada pelas faixas e curvas reais do mapa e pelos dois acessos autorados. O minimapa acompanha a rota restante. Maciota comenta a cidade durante o passeio.
6. Ambos descem. Maciota segue até a entrada. Dentro da garagem, oferece ajuda para encontrar o irmão em troca de favores. A conversa libera o quadro e o Primeiro giro existente. A Monaliza permanece escondida e sem colisão até a recompensa da entrega.

Os diálogos novos usam as tomadas neurais expressivas do piloto; elas ainda não são gravações humanas finais. O carro é um sedã 3D estilizado criado em código, com pintura full black, portas, rodas, ocupantes, faróis e perfil de motor V8 próprio.

Revisão do tuning: carroceria alargada com para-lamas integrados, altura reduzida, rodas maiores de cinco raios em bronze e pneus de perfil baixo, pinças vermelhas, saias, splitter, entradas de ar com intercooler aparente, respiros no capô, aerofólio GT, difusor e escapamento duplo. O modelo utilizado no passeio recebe essas peças diretamente.

## Controles, colisões e salvamento

- Enter ou Continuar avança a conversa. E interage com os personagens e as portas.
- Esc durante a volta permite descer; E na porta do passageiro retoma a rota do ponto onde o carro parou.
- O carro verifica colisões antes de avançar e espera obstáculos. Só tenta passar um veículo de tráfego observado parado se todo o corredor lateral estiver livre.
- A iluminação reserva o acesso do ferro-velho, impedindo postes no meio da entrada.
- Flags: `harbor_story_arrival_v2`, `harbor_police_briefed`, `harbor_city_tour_started`, `harbor_city_tour_complete`. Os marcos existentes da ligação, contato e entrega continuam sendo usados.
- Save durante a volta retoma o encontro no ferro-velho, com Dante a pé. Save após a volta retoma a conversa na garagem. Saves que já haviam conhecido Maciota ou começado a entrega preservam seu progresso.

## Arquivos e verificação

- `world/harbor/campaign/HarborStoryArrival.gd`: etapas, encontros e passeio.
- `world/harbor/campaign/MaciotaTourCar.gd`: movimento físico e apresentação do carro.
- `world/harbor/campaign/MaciotaM8SedanModel.gd`: geometria, materiais e ocupantes do sedã.
- `tests/test_story_arrival_v2.gd`: integração na cena de produção, colisão da rota, trânsito ativo, saída/retomada, marcos de save e conversa na garagem.
- `tests/capture_story_arrival_v2.gd` e `tests/render_maciota_m8.gd`: capturas reais do jogo e do modelo.
- `measurements/story-arrival-route.json`: pontos da rota gerados durante o teste.

Artefatos de revisão no diretório `D:/geteco/artifacts`: `story-arrival-route.svg`, `maciota-m8-front.png`, `maciota-m8-rear.png`, `story-v2-yard.png`, `story-v2-introductions.png`, `story-v2-police.png` e `story-arrival-v2-test.log`.
