# Tarefas externas — revisão Harbor/Mountain Pass

## Claude Code — UI e minimapa

Trabalhe em `D:/geteco/game`, exclusivamente na apresentação da UI e no minimapa.

1. Corrija a sobreposição entre objetivo da missão, temperatura, proteção térmica e altitude. Eles devem funcionar juntos em 1280×720 e resoluções maiores, sem cortar textos.
2. Em `ui/HarborMinimap.gd`, faça a seta do pedestre acompanhar sua direção real de movimento, conservando a última direção ao parar. Ao dirigir, use a orientação do veículo. Preserve os ícones da Monaliza e do spray.
3. Revise legibilidade, margens e convivência dos avisos temporários.

Leia os arquivos antes de editar. Pode alterar scripts/cenas da UI e a apresentação do HUD de frio. Não altere Player.gd, SaveManager.gd, WantedManager.gd, policiais, veículos, física, estradas, streaming ou missões. Se precisar de uma propriedade desses sistemas, documente o contrato para Astra integrar. Execute testes e tire capturas reais nas duas resoluções. Entregue arquivos alterados e resultados efetivamente executados. Não faça commit, reset ou desligamento.

## Anti Gravity — oficina 3D do Maciota

Trabalhe em `D:/geteco/game`, exclusivamente no cenário 3D da oficina. Inspecione primeiro `district/harbor_preview/art/monaliza_workshop/` e o interior atual. Desenvolva nesse diretório, com demonstração independente para Astra integrar.

A oficina precisa ter volume e escala coerentes com Dante e a Monaliza: ferramentas, bancada, elevador e iluminação discreta. Crie sala própria do Maciota, acessível a pé, com mesa, cadeira e objetos que deem personalidade. Preserve espaço para caminhar, conversar e entrar no carro. Modele portas/acessos compatíveis com as colisões, sem objetos gigantescos.

Não adicione letreiros flutuantes ou instruções sobre a Monaliza. A entrega do carro será explicada pela missão. Não altere controladores de interiores, HarborGame.gd, Player.gd, missões, diálogos, áudio, veículos ou saves. Entregue posições locais dos acessos, colisores e pontos de interação. Faça capturas reais no Godot e informe custo de renderização se conseguir medir; não apresente reprodução como captura do jogo. Não faça commit, reset ou desligamento.

## Integração Astra

Astra cuida de física, trânsito, ponte, polícia/prisão, saves, nitro, faróis, som dos veículos, diálogos e integração das entregas externas. Antes de alterar um arquivo fora do escopo acima, descreva a dependência em seu relatório para evitar sobreposição de trabalho.
