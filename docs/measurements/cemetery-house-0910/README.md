# Casa do coveiro

Casa permanente no canto noroeste do cemitério, conectada ao corredor central.
Entrada/saída por **E**, usando o gerenciador de interiores existente e mantendo
o enquadramento, as colisões e o retorno à porta correta.

Seu Anselmo usa um único personagem e a pá 3D articulada já disponível no projeto.
Trabalha nas sepulturas durante o dia, volta fisicamente pela porta com antecedência
calculada para o relógio acelerado, conversa em casa no fim da noite e dorme de
00:00 a 06:00. Uma invasão acorda o morador; após 1,6 segundo de aviso ele dispara.
Sair cancela a reação, inclusive durante a animação de levantar. Não há perseguição
a quem apenas passa por fora. A morte do coveiro fica registrada na campanha.

O livro na bancada e a conversa diurna revelam o túmulo vazio de Samuel e a pista
para a carta existente junto ao muro sudeste. A descoberta é salva como flag de
campanha e usa o colecionável original, sem duplicá-lo.

Interior 3D com cama de ferro, colcha, bancada, livro, chave, ferramentas de parede,
lampião, fogareiro, café, botas, carrinho de mão, terra e cruzes de madeira.

Validação no Godot 4.7.2: `test_cemetery_keeper_home.gd` (entrada real, reação,
projéteis, saída, horários, retorno, persistência e morte), `test_cemetery_atmosphere.gd`
e `test_cemetery_world_events.gd` (cortejo e eventos existentes).
`capture_cemetery_keeper_home.gd` abre HarborGame com o jogador real para as imagens.
As vistas da cama e da intrusão pausam o relógio e posicionam os atores para revisão.

- `01-cottage-exterior.png`: casa, porta e acesso.
- `02-cottage-interior-day.png`: interior jogável e pista.
- `03-cottage-sleeping.png`: pose de descanso na cama.
- `04-cottage-intrusion.png`: reação do coveiro.
