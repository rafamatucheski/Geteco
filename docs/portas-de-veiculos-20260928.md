# Portas de veículos, entrada e saída (2026-09-28)

Pedido: as portas de todos os carros abrem direito, não "voam", o corpo não atravessa
lataria nem folha, há contato (mão no batente), a porta tem detalhes, e vale conferir carro
por carro por onde o motorista entra e por onde sai.

## Por que a porta antiga voava

Os modelos de `assets/fleet` são fotografias achatadas: a porta é só um pedaço da lataria,
sem dobradiça. A "folha substituta" (`VehicleDoorPresentation`, versão antiga) era uma placa
de caixa que aparecia ao lado da porta fechada, que continuava no casco. Aberta, a placa
flutuava na frente de uma parede intacta e o corpo entrava pelo meio da lataria.
Só o cupê (`VehicleCoupeDoors`) tinha recorte real.

## Como é agora

- `data/catalogs/VehicleDoorSpecs.gd`: por modelo, o vão da porta do motorista medido sobre
  a grade métrica (`tests/capture/capture_vehicle_doors.gd -- grid`): z de frente (dobradiça)
  e de trás, rodapé, cintura e teto; `class` (car/tall/truck) quando a altura do casco engana
  (vans e picapes não são caminhões). Veículo novo precisa de uma linha ali; o teste de
  portas reprova o que não tiver.
- `gameplay/VehicleDoorBuilder.gd`: recorta a folha dos MESMOS triângulos da lataria e do
  vidro, cortando os triângulos pelo prisma do vão (Sutherland–Hodgman) e deixando o resto no
  casco. Peças pequenas dentro do vão (retrovisor, frisos) vão inteiras para a folha. A tinta
  é o mesmo objeto de material do casco, então repintar e o dano continuam valendo. A
  lataria é medida na malha (coluna de 1 cm com mais área, abaixo da cintura).
  O enrolamento dos triângulos NÃO é confiável nos modelos (caixas de dentro para fora,
  vidro de face dupla), então o recorte vale para os dois sentidos.
- `gameplay/VehicleDoorPresentation.gd`: dobradiça na frente do vão, cartão interno
  (cópia invertida da lataria, recuada), batentes que fecham as bordas da folha, maçaneta
  com rebaixo, apoio de braço, puxador, comando do vidro e alto-falante; frestas escuras na
  lataria e o "poço" escuro atrás (sem ele o casco oco mostrava o cenário através do carro).
  Fechada, a imagem é a original mais as frestas e a maçaneta.
- `gameplay/VehicleBoardingPresentation.gd`: o ramo novo `_apply_door` usa a geometria real
  da folha aberta (`Vehicle.door_layout(side)`):
  1. o corpo espera num ponto FORA do círculo que a ponta da folha varre (atrás do vão), então
     fechar a porta com ele parado ali nunca o atinge;
  2. quem aperta F colado na porta dá um passo para trás e só então a porta abre;
  3. o caminho contorna casco e folha (menor caminho em grafo de visibilidade);
  4. mão no batente traseiro (o alvo sobe com o corpo no degrau), passo até o vão, cruza o
     plano da lataria só pelo vão, agacha/encolhe o necessário para a cabeça passar sob o teto
     do vão e vira para o volante;
  5. na saída, o mesmo caminho ao contrário; `Driving.exit_position` tenta o ponto de espera
     primeiro (se estiver bloqueado usa as alternativas antigas e a porta só fecha depois de
     1,6 s se o pouso estiver dentro do arco).
  Moto, buggy, empilhadeira e ônibus (sem folha) continuam no ramo antigo.
- `Vehicle.driver_seat_anchor()` e `_cab_z()` agora vêm do centro do vão da tabela. Antes
  vinham de uma fração do comprimento do casco: em van, ambulância e caminhão o motorista
  entrava no meio da carga.

## Verificação

- `tests/test_vehicle_doors.gd` (headless, sem renderizar): todos os 46 veículos com porta,
  os dois lados, três pontos de partida (ao lado, à frente, atrás) e duas orientações.
  Mede: distância do corpo à folha no ângulo que ela tem naquele instante (≥ 0,27 m), corpo
  cruzando a lataria fora do vão, corpo dentro do casco na aproximação, cabeça acima do teto
  do vão, mão a ≤ 0,32 m do batente por ≥ 3 quadros, chegada ao banco / ao ponto de saída
  (≤ 0,16 m) e varredura do fechamento da porta com o corpo parado no pouso.
- `tests/capture/capture_vehicle_doors.gd -- grid|open|shut|base [id ...]`: capturas
  renderizadas (grade métrica; portas abertas; fechadas; original). `base` × `shut` só
  diferem nas frestas/maçaneta.
- `tests/capture/capture_boarding_doors.gd -- entry|exit lado [zoom=.6] id ...`: 8 quadros
  da entrada ou saída com o corpo.

O que NÃO foi medido: custo de quadro (o recorte roda uma vez, no primeiro embarque do
veículo, ~poucos ms; não medi com o `measure`), colisão física da folha com paredes e
meio-fio (a folha é só apresentação; quem manda no espaço livre é `Driving`), e a folha
de ônibus (`route_city` continua com a porta de serviço sem folha).
