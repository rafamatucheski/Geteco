# Terminal Harbor — plataforma em operação

## O que está implementado

- Terminal urbano compacto de uma plataforma na praça da Market Street, com
  abrigo, bancos, telefone, armários e sinalização de parada.
- Ônibus urbano próprio de 120 × 34 px, portas laterais animadas e circuito
  **Market → Warehouse → Foundry → Union → Market**.
- O ônibus é um consumidor de `DemoTrafficVehicle`: usa as faixas geradas,
  os conectores, as reservas de junção, frenagem e espaçamento existentes.
  Não há teleporte entre ruas nem uma pista invisível separada do tráfego.
- Dois passageiros sobem e dois descem por visita. Quatro civis articulados
  são reutilizados entre ciclos; passageiros embarcados ficam invisíveis e
  fora das consultas físicas, sem deixar obstáculos invisíveis na parada.
- No Novo Jogo, Dante permanece no ônibus durante a CGI. Quando ela termina
  ou é pulada, a porta abre, ele sai e caminha com colisão até a plataforma.
  Após sete segundos na plataforma, o telefone toca para Maciota. A missão e os saves continuam
  usando os contratos existentes.

## Escolhas locais e limites

A faixa canônica no lado norte da Market é a forward. O ônibus possui acesso
em ambos os lados e usa o lado da plataforma para não fazer passageiros
cruzarem a faixa oposta. Não foi invertida a circulação do distrito inteiro.

Esta é uma parada operacional em faixa: carros aguardam atrás durante o
embarque e seguem após a partida. Não foi construída uma baia com ultrapassagem
nem um terminal rodoviário grande com múltiplas linhas. O percurso é local;
viagens entre distritos e dirigir/roubar esse ônibus não estão habilitados.
Ônibus danificado e interferência prolongada de jogador podem interromper o
serviço; não há reciclagem/teleporte para mascarar bloqueios.

## Arquivos desta etapa

- `HarborArrivalStop.gd`: plataforma, passageiros, fases de serviço e desembarque.
- `HarborTransitBus.gd`: visual do ônibus, parada e escolha do circuito local.
- `HarborTransitPassenger.gd`: civis com destinos de embarque/desembarque.
- `HarborGame.gd`, `campaign/HarborArrivalMission.gd`: conexão com a chegada.
- `tests/test_harbor_terminal.gd`: operação no mundo real, retorno, segundo
  atendimento, corpo sem sobrepor paredes/prédios e handoffs sem teleporte.
- Testes de campanha/menu e captura atualizados para aguardar o desembarque.
- `tests/visual/capture_harbor_terminal.gd`: imagens reais do serviço.

## Como jogar

Escolha Novo Jogo. Assista à CGI ou use Esc para pular. Espere Dante sair do
ônibus; use Enter na ligação e siga para a garagem. Para observar o serviço,
fique na plataforma: o ônibus parte, percorre o quarteirão e retorna. O tempo
varia com semáforos, pedestres e a fila de tráfego, não é um relógio fixo.

## Resultados desta etapa

- `test_harbor_terminal.gd`: exit 0, zero falhas. Duas visitas e duas partidas,
  quatro embarques e quatro desembarques; percurso físico de 3185,35 px.
  Nenhuma sobreposição com paredes/prédios ou salto de handoff detectado.
- `test_harbor_campaign_flow.gd`: exit 0, zero falhas.
- `test_menu_flow_integration.gd`: exit 0, aprovado.
- Captura com renderização real revisada: plataforma, ônibus e passageiros
  visíveis; imagens em `D:/geteco/harbor-terminal-disembark.png` e
  `D:/geteco/harbor-terminal-passengers.png`.
- O teste final do terminal ainda emite aviso de duas instâncias ObjectDB
  retidas ao encerrar. A origem não foi isolada nesta etapa; não equivale a
  uma validação de ausência de vazamentos em sessões longas.

Teste de campanha e menu usam saves de teste, sem sobrescrever slots reais.
A suíte completa do projeto não foi executada nesta etapa. Warnings de
logs/certificados/cache e acesso a user:// permanecem limitações do ambiente
restrito, não foram tratados como falhas dos scripts de trânsito.

Sem commits. Mapa de revisão antigo e restante da malha preservados.

## Correção da saída após a espera do telefone — 2026-09-05

Reprodução física identificou passageiros retornando pela mesma linha y=1130
do ponto de chegada de Dante. Durante a espera de sete segundos, eles o
empurravam de aproximadamente (1701, 1130) até (1647, 1115); um passageiro em
repouso impedia avançar ao sul. O teste de campanha falhava com avanço de 0 px.

A fila e a aproximação dos passageiros agora usam y=1155, na frente do abrigo,
separadas do ponto de espera. O asfalto começa em y=1190; o raio físico de 11 px
dos passageiros permanece fora da pista. Não houve desativação de colisões,
teleporte de correção nem mudança do controle de Dante.

O teste de campanha preserva sua caminhada real de 24 frames e agora também
verifica que os passageiros não deslocam Dante mais de 3 px do ArrivalSpawn
durante a espera. O reteste final, após a correção compartilhada de junções,
terminou com exit 0 e zero falhas. Na execução instrumentada, Dante permaneceu
em (1701.287, 1130.07) e avançou 31.215 px, contra os 0 px anteriores.

Regressão final de `test_harbor_terminal.gd`: exit 0, zero falhas, duas visitas,
duas partidas, quatro embarques e quatro desembarques, população mantida em
quatro passageiros e 3185.390 px percorridos fisicamente. As verificações de
corpo contra prédios/paredes e de ausência de teleporte continuaram ativas.
Não houve warning ObjectDB nesta execução; continuam os erros ambientais de
acesso ao log e ao repositório de certificados. A suíte completa não foi rodada
nesta correção local.
