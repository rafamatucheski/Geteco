# Antigravity — cenário da oficina da Monaliza

Crie um kit 3D procedural isolado para a área de apresentação do primeiro carro pessoal do Dante: um cupê Monaliza azul e laranja, baixo, turbo e com aerofólio, inspirado na referência enviada pelo usuário. A Astra está construindo o carro e toda a lógica: NÃO modele outro carro nem edite o carro oficial.

Trabalhe apenas em district/harbor_preview/art/monaliza_workshop/ e tests/test_monaliza_workshop_art.gd. Entregue MonalizaWorkshopProps3D.gd, com escala em metros, origem no centro da vaga e piso y=0. Vaga livre de 3,5 × 6 m para um cupê de 1,86 × 4,46 m; deixe corredores e saída frontal livres. Coloque bancada turbo desmontado/intercooler, armário de ferramentas, mangueira de ar enrolada, banner WESTGATE / MONALIZA, luminárias industriais, materiais de borracha e metal. Silhuetas legíveis, detalhes delicados e econômicos, sem 151 objetos minúsculos invisíveis no zoom normal.

Não crie corpos físicos nem luzes com sombras por objeto; exponha get_obstacle_bounds() em metros para a Astra gerar colisões consistentes. Nada de lógica, NPC, missão, Player, SaveManager, garagem existente, interfaces ou sons. Crie demo independente com manequim 1,80 m, caixa métrica do carro reservando o espaço, captura real Vulkan e teste que termina sozinho. Relate dimensões, meshes, performance e resultado, sem commit/reset/desligamento.
