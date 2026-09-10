# Caixas nas mãos e circuitos do convés — 10/09/2026

Os braços dobravam para +Z (costas), enquanto a caixa estava presa ao peito em
-Z (frente). Agora os cotovelos dobram para a frente e a caixa acompanha o ponto
médio de dois apoios nas luvas. Sua largura acompanha a distância entre as mãos.
As capturas `grip_0.png` a `grip_3.png` mostram o próprio rig nas quatro orientações;
`grip_1.png` permite conferir o contato de perfil.

Cada operador tem um circuito retangular separado na área de triagem: aproxima
as mãos da pilha, retira uma caixa, percorre dois lados, deposita na outra pilha,
pausa e volta vazio pelos dois lados restantes. O operador gira antes de andar,
para não deslizar de costas durante a mudança de direção. Depois de transportar
as três caixas, os postos de origem e destino trocam de papel. Não se criam caixas
novas; pânico continua deixando a carga no chão.

Verificação com Godot 4.7.2, Forward+/Vulkan:

- `test_harbor_dock_crew.gd`: 21 verificações aprovadas em HarborGame, com 25 segundos
  de observação após a aproximação. Os três operadores concluíram circuitos reais,
  retornaram vazios e permaneceram fora dos contêineres. Estoques, frente do corpo,
  apoio das mãos, pânico e suspensão à distância foram verificados.
- A cápsula real do jogador percorreu convés e passarela sem bloqueio.
- `test_dock_carry_pose.gd`: zero falhas; encaixe e posição frontal da caixa
  conferidos nas quatro orientações, com capturas ampliadas do rig real.

`verification.txt` reúne as saídas resumidas. O carregamento continua registrando
os erros preexistentes de InputMap; a integração também registra o aviso de uma
instância ObjectDB ao sair. Nenhum erro de script nos operadores. Não houve medição
de desempenho. As imagens do convés mantêm a interface real do jogo.
