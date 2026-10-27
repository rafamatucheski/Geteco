# Deserto: varredura de paredes invisíveis (27/10/2026)

Cartão `bug-colisores-invisiveis-deserto-20261012`: "em pontos do chão do deserto o jogador ou o carro bate numa
parede invisível", sem local exato.

## Como foi medido

`tests/probe_desert_invisible_walls.gd` monta a região do deserto real (layout compacto), célula por célula de 96 m
(171 células), e compara a colisão com o que se vê: toda malha visível da célula vira um corpo num espaço físico à
parte, só da sonda, e cada raio vai aos dois espaços.

- **Parede:** grade de 1 m; raios horizontais a 0,3 m e 1,0 m do chão nas quatro direções. Batida em face quase
  vertical sem superfície visível até 0,4 m atrás dela.
- **Ressalto:** a altura da colisão acima da altura visível (> 8 cm).
- **Degrau** (`--steps`): grade de 0,5 m; vizinhos com o chão a alturas de 8 mm a 35 cm e face quase vertical entre
  eles. É o que importa para o carro: o casco do `Vehicle` é uma caixa apoiada em y=0 e não sobe degrau nenhum.

**Rodar com janela.** Em `--headless` o servidor de render falso devolve toda instância de MultiMesh na origem, e
toda peça agrupada (ponte do cânion, ferrovia, mina) aparece como parede falsa. A primeira passada headless deu 76
tipos de colisor; com janela, 55, quase todos explicados abaixo.

Números: 15,7 milhões de raios em 305 s (paredes e ressaltos) e 14,0 milhões em 333 s (degraus).

## O que achou

| achado | onde | leitura |
|---|---|---|
| **Pátio do ponto de ônibus Cobre sólido com tampo a +1,5 cm** | (-187, -551) | **Defeito.** A quina vertical de 1,5 cm segura o casco do carro, e o visual não mostra degrau. Corrigido: o pátio ficou só visual (o chão do deserto já apoia carro e jogador). `tests/test_desert_flush_slabs.gd` arrasta um casco de carro por cima. |
| Rochas de arenito soltas: casco convexo maior que a pedra | espalhadas, p.ex. (-815, -868), (-389, -1107) | Até 22–34 cm de colisão fora da pedra na base. Inerente ao casco convexo de rocha côncava; poucos pontos. Não mexido. |
| Rochas grandes da mina (`MiningBatch.rock`) | borda norte e fundo da cava | Até 1 m de casco acima do visual em rochas grandes. Mesma causa. Não mexido. |
| Grade da ponte do cânion | x≈-1204, z -611…-516 | Barreira contínua atrás da treliça aberta: de propósito (comentário no código). |
| Caixas de carro estacionado, caminhão, tralha do pátio do Digo | arrancada, Miragem, oficina | Caixa de colisão em volta de forma curva: esperado. |
| Cactos, poste de madeira | poucos | Cilindro uns cm mais largo que o tronco. |
| Ilha das bombas do Miragem (degrau de 20 cm) | (290, -487) | Alarme falso: a sonda mediu o telhado da cobertura acima. |

## O que não foi medido

- Só a região montada sozinha: o que a sessão põe no deserto em tempo de jogo (encontros, veículos da população,
  atividades) não entrou.
- Degraus menores que 8 mm e lajes menores que a grade de 0,5 m podem ter escapado.
- Ninguém dirigiu no jogo para confirmar que o relato original era o ponto Cobre. O relato é de 12/10, antes da
  compactação do deserto (21/10); o ponto Cobre é o único degrau invisível achado no chão aberto.
