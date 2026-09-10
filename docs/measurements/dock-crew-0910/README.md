# Operação de carga no navio — 10/09/2026

Três operadores civis no convés, com capacetes amarelos/branco, coletes
refletivos laranja/amarelo, calças de trabalho, luvas e botas. Usam o rig,
as colisões, a reação a perigo e o orçamento de apresentação dos pedestres.

Cada operador pega uma caixa, carrega, apoia no outro ponto e faz uma pausa.
O estoque é conservado entre pilhas, mãos e caixas no chão; uma interrupção
por pânico, queda ou incapacitação deixa a caixa carregada no local.
Os contêineres e a passarela permanecem os existentes. O terceiro operador
trabalha na faixa transversal de carga, deixando o corredor lateral livre.

Gaivotas gravadas têm uma fonte espacial própria, com três variantes e
intervalos de 8–15 segundos durante o dia, mais espaçados e baixos à noite.
A primeira chamada acontece pouco depois da aproximação. O agendamento
anterior de gaivotas do porto fica suprimido enquanto esta fonte está ativa.
O manuseio das caixas dispara um som curto de madeira. Todos seguem SFX;
diálogos reduzem o volume e a distância suspende a operação e os sons.

Áudio reutilizado: gaivotas do banco
[living_city](../../../audio/living_city/README.md) e madeira do banco de
impactos existente. Não há novos downloads ou serviços externos.

## Verificação

- `test_harbor_dock_crew.gd`: **0 falhas**, com renderização Vulkan e WASAPI.
- Os três operadores completaram entregas durante 15 segundos de observação.
- Trajetórias conferidas contra o polígono do convés e os contêineres.
- Estoques conservados, caixa visível nas mãos, interrupção por pânico e
  suspensão à distância verificadas.
- A cápsula real do jogador percorreu todo o circuito autoral, cruzou a
  passarela e retornou ao cais usando `move_and_collide`, sem bloqueio.
  Essa verificação usa colisões reais, não entrada de teclado.
- `tools/check_references.py`: nenhuma referência nova quebrada.
- Capturas de imagem e 15 segundos de áudio estão nesta pasta.

O teste antigo `test_harbor_ship_access.gd`, na cena de prévia, não terminou
e foi interrompido. A verificação de circulação acima foi feita na cena
principal. O log final ainda registra erros preexistentes de importação de
controles salvos e um aviso de ObjectDB ao encerrar; nenhum erro de script
dos novos operadores. Não foi feita medição de desempenho.

Reproduzir: `--script res://tests/test_harbor_dock_crew.gd -- --capture`.
