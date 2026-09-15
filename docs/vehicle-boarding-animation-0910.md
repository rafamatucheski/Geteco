# Entrada articulada em veículos — 10/09/2026

Atualização 11/09: a saída dos carros termina com 0,40 s junto ao veículo,
com um gesto discreto da mão para fechar a porta. O controle permanece bloqueado
até o painel fechar; motos mantêm a saída sem esse gesto. Polícia, bombeiros,
paramédicos e agentes funerários aguardam o fechamento antes de seguir a rota.
A sequência compartilhada da maca também espera as portas dianteiras fecharem.
O teste de embarque inclui uma saída em tempo real para verificar continuidade
de posição, bloqueio durante o fechamento e porta fechada ao devolver o controle.

O vídeo de referência mostrava Dante deitando ao entrar. `VehicleBoarding`
copiava a rotação 2D do carro para a imagem do personagem, enquanto sua física
e animação de caminhada estavam desligadas. A transição apenas deslocava e
reduzia a opacidade do corpo congelado.

A entrada agora mantém a imagem em pé e gira somente o modelo 3D. Uma sequência
compartilhada coordena aproximação, alcance da porta, passo, acomodação no banco
e fechamento. O novo `scripts/player/VehicleBoardingPose.gd` articula quadris,
joelhos, tornozelos, tronco e braços com os mesmos comprimentos do rig de Dante.
As mãos ficam livres durante o movimento; a arma é restaurada ao terminar.

- Carros: flexão moderada do tronco e descida dos quadris para sentar.
- SUVs, picapes e furgões: passo mais alto.
- Caminhões e ônibus: subida mais alta, entrada mais demorada e alinhamento
  com a porta da cabine extraída do próprio modelo.
- Motos: apoio da perna próxima e passagem da outra perna sobre o banco;
  transferência para o piloto existente ao concluir.
- Os alvos das articulações são espelhados para a entrada pela esquerda ou direita.

As portas nativas fornecem a posição da entrada, projetada pela mesma câmera
do veículo. Os offsets permanecem relativos ao veículo, inclusive em pontes.
A duração das portas acompanha a animação: 1,85–2,15 s para carros, 2,15–2,45 s
para caminhões e 1,45 s para motos. A entrada pelo passageiro reserva tempo
adicional para a acomodação no lado do motorista.

Nos veículos com cabine, `VehicleCabinOccupant.gd` coloca uma cópia articulada
do rig no mesmo espaço 3D do carro. A carroceria, a porta e o teto o encobrem
pelo teste de profundidade normal. A imagem 2D do ator fica escondida; não há
corpo desenhado acima da lataria nem desaparecimento por opacidade.

O ocupante atravessa a abertura e permanece no banco do motorista. A pose se
ajusta à altura da cabine, dobrando os joelhos e recolhendo as mãos, sem reduzir
a escala do personagem. Os modelos atuais usam vidros opacos: estar dentro
da cabine não implica aparecer através dos vidros. Ao sair ou interromper,
a cópia é removida e a apresentação original é restaurada.

As aberturas das portas usam a geometria dos vidros laterais para localizar
a cabine. Isso evita extrair partes do teto, capô ou baú como porta, e mantém
a entrada dos caminhões na cabine. As câmeras 3D estáticas usam seus transforms
atuais também no primeiro quadro após o carregamento do modelo.
As junções entre teto e para-brisas da Monaliza receberam as borrachas de
vedação, fechando pequenas frestas por onde o ocupante aparecia.

Pose, arma, opacidade, camada e modo de interpolação são restaurados ao concluir
ou interromper. O acelerador continua bloqueado até terminar e exige soltura.

## Validação

A saída usa a mesma trajetória em sentido inverso, desde o banco até o chão,
com a porta aberta durante a passagem. O ocupante continua no viewport 3D do
veículo e a lataria o encobre até ele cruzar a abertura. Na moto, a pose inicial
coincide com o piloto sentado; a perna passa sobre o banco antes de apoiar no
chão. O controle e a câmera só voltam ao pedestre ao concluir a saída.
Ao terminar a passagem pela porta, a imagem do pedestre assume a mesma posição
projetada dos pés e continua o movimento para fora. Isso mantém o corpo inteiro
visível ao se afastar, além dos limites do pequeno viewport 3D do veículo.

O lado da saída vem da posição livre consultada pelo veículo. Pedidos repetidos
mantêm a animação atual; sair durante a entrada reverte a partir da pose atual.
Morte, viagem de região e remoção do carro de corrida usam `force_exit_vehicle`
para concluir a limpeza antes de reposicionar ou remover os objetos. A abordagem
policial aguarda a saída física antes de começar a pose de algemamento.

`tests/test_vehicle_boarding_animation.gd` exercita Monaliza, cupê, SUV, picape,
furgão, caminhão baú, guincho e três motos, pelos dois lados e com veículos
girados. Verifica orientação vertical, articulação, visibilidade, conexão da
cabeça, interrupção, restauração de estado e passagem para o piloto da moto.
A execução com renderização captura três poses de Monaliza, caminhão e moto
por lado em `D:/geteco/artifacts/boarding-cabin-0910/`, além do estado sentado.
Verifica também que o rig está dentro da cabine e abaixo do teto. Um teste de
falsa-cor pinta o ocupante de magenta sem iluminação e exige zero pixels dele
visíveis fora da cabine fechada, detectando atravessamentos reais da lataria.

Os testes existentes de entrada lateral, motos e capacete passam a aguardar
o fim do embarque, em vez de presumir a antiga transição de 0,6 segundo.
O teste lateral também aguarda o mapa concluir sua inicialização.

Para repetir os testes, executar Godot com `--headless --path D:/geteco/game
--script res://tests/<nome>.gd`. Para capturas, omitir `--headless` e selecionar
`--rendering-method gl_compatibility`. As capturas são de uma cena de revisão
com os scripts e modelos reais. A revisão de saída salva as capturas em
`D:/geteco/artifacts/vehicle-exit-0910/`, em cinco momentos por lado. A matriz
também bloqueia a porta esquerda para verificar a saída pela direita e confere
que repetir o comando de saída não reinicia a animação. Testes de motos e capacete
aguardam agora a conclusão da saída antes de verificar o estado do pedestre.
