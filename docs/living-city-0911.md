# Vida de rua — restaurantes e ocorrências locais

A partida `HarborGame.tscn` cria `RestaurantLife` e mantém `WorldEvents` como
diretor de ocorrências. O relógio da cidade agora avança: um dia dura 24 minutos
reais e a pausa também congela o horário. O relógio continua usando o gerenciador
de clima existente; não há relógio paralelo para as mesas.

## Restaurantes

| Local | Horário do jogo | Mesas |
|---|---|---|
| Anchor Diner | 07h–23h | (555, 1132), (685, 1132) |
| Tideline | 10h–23h | (5735, 1644), (5845, 1644) |
| Early Shift | 05h–18h | (6145, -1238), (6255, -1238) |

Cada local tem duas mesas e até quatro clientes. Uma mesa permanece ocupada
durante o expediente; a segunda enche nos períodos de café da manhã, almoço e
jantar. Pequenos deslocamentos no horário evitam que todos levantem juntos.

Mesas, cadeiras, comida, pratos, copos, talheres, clientes e guarda-sóis são
geometria 3D. Os clientes dobram quadris e joelhos para sentar, gesticulam e levam
o garfo à boca. Ao fechar ou ouvir disparos próximos, levantam e se afastam em
direção à fachada. Após 20–22,5 segundos sem ameaça, podem voltar.

A cobertura abre gradualmente com chuva e recolhe ao secar. Cada mesa compartilha
um SubViewport de 224×224 entre todos os seus elementos. A apresentação é criada
pelo orçamento existente e só atualiza perto da câmera. As colisões das mesas e
cadeiras continuam presentes à distância e deixam livre o acesso central.

Clientes sentados são atores visuais da mesa: reagem ao ambiente, mas não têm
saúde, inventário ou atendimento médico individual. A entrada na fachada é uma
transição visual local, não uma simulação de clientes dentro do restaurante.

## Ocorrências

O assalto antigo com despacho imediato foi substituído por aproximação, ameaça,
entrega da bolsa, chamada pelo telefone, perseguição e prisão ou fuga. Bolsa e
telefone acompanham os gestos do personagem. O policial usa a navegação e a prisão
com verificação de visão do sistema existente.

Dois pontos ficam nos passeios próximos às Cobras e um no centro. O intervalo
global é de 3–5 minutos; o centro tem intervalo adicional de 8–12 minutos. Todos
os participantes entram fora da tela. Apenas uma ocorrência de rua/incêndio
pode ocupar esse orçamento de cada vez. Uma perseguição ativa ao jogador ou um
confronto das Cobras impede a introdução automática de outro assalto.

O suspeito é desarmado e a resposta usa um policial a pé, sem disparo automático
nem alteração do procurado do jogador inocente. Ataques reais do jogador aos
participantes continuam usando a atribuição de dano existente. Funeral e incêndio
mantêm seus fluxos anteriores.

Disparos alertam civis até 240 pixels, ou pessoas numa faixa de 42 pixels da
trajetória. A trajetória termina na primeira obstrução e a reação respeita
cobertura lateral. Clientes das mesas recebem o mesmo aviso, sem serem inseridos
no grupo de personagens com saúde.

## Validação

- `tests/test_restaurant_life.gd`: horários, geometria articulada, guarda-sol,
  saída gradual, passagem livre e suspensão de apresentações distantes.
- `tests/test_local_gunfire_neighborhood.gd`: distância, trajetória, cobertura,
  rajadas e alerta efetivo através da própria colisão da mesa.
- `tests/test_civilian_gunfire_response.gd`: civis reais correm, evitam obstáculos
  e retomam a rotina após silêncio.
- `tests/test_living_city_integration.gd`: cena real, três locais, relógio/pausa,
  chuva, fechamento e som. `-- --capture` salva imagens em
  `D:/geteco/artifacts/living-city-0911/`.
- `tests/test_street_robbery_routine.gd`: deslocamento e prisão reais, isolamento
  do procurado, intervalo e interrupção quando o policial é removido.
- `tests/test_cemetery_world_events.gd`: funeral e despacho real de incêndio.
  Imagens da ocorrência em `docs/measurements/street-life-0911/`.

A suíte preexistente `test_police_sensitivity.gd` aprovou as verificações de
atribuição de crime, mas emitiu erros de callbacks médicos para objetos já
liberados pelo teste; ela não é usada como evidência de execução sem erros.
O teste preexistente `test_living_city_soundscape.gd` também permanece incompatível
com o catálogo atual de rádio: assume cinco estações e acessa `.data` numa estação
que agora é OggVorbis. O fechamento do som do café foi verificado separadamente
em `test_living_city_integration.gd`.
