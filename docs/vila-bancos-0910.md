# Revisão do abrigo, acesso e bancos da serra

A parada vizinha à Vila da Neve mantém o centro local `(7110, -1510)`. A vaga
do SUV fica separada do abrigo, com demarcação própria. O acesso desemboca no
pátio frontal e abre o guard-rail no mesmo percurso. A borda de neve passa a
variar de largura gradualmente, eliminando o recorte abrupto da curva inferior.
Os nomes escritos nas fachadas dos quatro chalés foram removidos.
O mirante semicircular antigo, sobreposto à curva inferior, foi substituído
por uma plataforma integrada ao pátio em `(7240, -1450)`, com guarda-corpo
e colisão nos lados leste e sul. As três placas deslocadas foram removidas.

## Geodata

Os modelos são renderizados em 3D e a movimentação usa física 2D. As colisões
do abrigo, bancos e telhados são derivadas da geometria projetada, com corpos
na camada 1 e polígonos compatíveis com a apresentação. As portas, caminhos e
pontos de aproximação dos bancos continuam transitáveis. `ResponderNavigation`
consulta esses corpos reais ao planejar o movimento dos pedestres.
O mini terminal foi deslocado 18 px ao sul para que sua cobertura projetada
não ocupe a vaga do ônibus. Os bancos da vila têm acessos explícitos: depois
do descanso, a pessoa retorna ao caminho público antes de seguir ao chalé.

`MountainBenchGeometry` instala assentos do grupo `mountain_bench_seat`, com
altura, orientação, aproximação, ajuste de projeção, corpo de apoio e rota de
entrada quando necessária. A reserva pertence a uma única pessoa por assento.
A pessoa caminha com colisão até a frente do banco, recua para sentar e sai
pela frente ao levantar. Somente o corpo do próprio banco recebe uma exceção
temporária para o ocupante; paredes e demais objetos permanecem sólidos.

## Rotinas e animação

`MountainBenchRest` controla aproximação, sentar, descanso, levantar e saída.
Moradores fazem pausas periódicas com durações variadas. Os passageiros da
rodoviária descansam depois de chegar à praça ou retornar da loja de inverno,
antes de seguir aos chalés. Sem lugar disponível, continuam seu percurso.

O modelo dos moradores articula quadril, joelhos e braços, com transições
graduais e pequenos movimentos durante o descanso. O ajuste visual do assento
compensa a diferença entre as câmeras dos personagens e dos bancos.
Perigo interrompe o descanso; morte ou remoção do personagem libera a reserva.
Nos bancos internos, o abrigo encobre corretamente o personagem enquanto ele
está sob o telhado. A camada de apresentação é restaurada ao sair.

## Verificação

- `tests/test_mountain_bench_rest.gd`: ciclo físico contornando parede, reserva
  exclusiva, animação, restauração de colisão, perigo, morte e remoção.
- `tests/test_mountain_transit_village.gd`: duas chegadas, sete desembarques,
  três compras, descanso em bancos e chegada aos chalés.
- `tests/test_mountain_geodata.gd`: caminhos públicos com círculo de 9 px e
  raios laterais de navegação; acesso do carro, vaga e volumes dos telhados.
- `tests/capture_mountain_bench_revision.gd`: aproximação e ciclo completo de
  um morador no banco externo real. `--production` carrega Harbor e a região
  contínua, incluindo o acesso da linha de ônibus.

Capturas e registros desta revisão ficam em
`D:/geteco/artifacts/vila-bancos-0910/`. Os testes usam APPDATA isolado;
as capturas utilizam o renderizador Forward+.
`capture.json` registra a conclusão do ciclo e a quantidade de quadros válidos;
`make_preview.py` converte esses quadros nativos em `sentar_levantar.gif`.

Resultado na geometria final: `test_mountain_bench_rest.gd` passou com zero
falhas, incluindo o banco interno e a restauração da oclusão. O teste da vila
completou duas chegadas, sete desembarques, três compras e sete descansos;
todos os viajantes chegaram aos chalés. Registros:
`D:/geteco/artifacts/rodoviaria-3d-0910/mountain-bench-rest.log` e
`D:/geteco/artifacts/rodoviaria-3d-0910/mountain-bench-village-final.log`.

`test_mountain_geodata.gd` passou nas 15 rotas, sem amostras bloqueadas nem
obstrução do acesso. A verificação geométrica de `test_harbor_mountain_coach.gd
-- --geometry-only` passou nos 17 trechos de ida e 17 de volta, incluindo o
casco real de 120 × 34 px e a vaga. Esta revisão repetiu a varredura física
do circuito; a viagem temporal completa já havia sido validada na revisão
anterior. Logs em `D:/geteco/artifacts/mountain-geodata-0910/`.
