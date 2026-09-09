# Minimapa e Pay 'n' Spray

O Harbor oficial recebeu um minimapa vetorial no canto inferior esquerdo. Desenha as ruas e os lotes existentes, atualiza as posições a 10 Hz e acrescenta a estrada da montanha quando o streaming termina. Não cria uma segunda câmera ou renderização do mundo.

- Seta branca: jogador/veículo atual; mapa orientado para o norte.
- Carro laranja: Monaliza desbloqueada e estacionada. Quando longe, o marcador fica na borda na direção do carro, com distância em metros. Dirigindo outro carro, a Monaliza continua marcada.
- Ícone de lata de spray: oficina, também indicado na borda quando distante, sem legenda escrita.
- Carros guardados e jogadores em interiores do Harbor são representados no acesso exterior correspondente, sem expor as coordenadas remotas usadas pelos interiores.

## Serviço automático

A oficina Northgate existente (`NorthDistrict/MotorWorkshop`, acesso em torno de 4925, -1198) recebe o serviço. A fachada e o piso ficam sem texto ou marca colorida; a identificação está no ícone do minimapa. Aproxime o carro devagar da porta. Preço: **$100**.

O mesmo carro é alinhado e conduzido para dentro; a persiana fecha, o serviço aguarda **4,5 segundos**, depois o veículo reaparece e recua para o acesso. As animações de entrada e saída são adicionais à espera. A mensagem final é **RESTAURADO / -$100**. O jogador continua ao volante e precisa soltar o acelerador antes de retomar a condução; a saída não dispara cobranças repetidas.

Na Monaliza, a pintura é preservada integralmente, inclusive se já tiver uma cor personalizada. O reparo recupera integridade, pneus e desempenho. Carros comuns mantêm o reparo com repintura. O protótipo gratuito de escolha de cores ficou restrito ao modo de revisão; não aparece mais no Harbor oficial.

Durante o movimento automático, colisões/controle do veículo são suspensos e devolvidos ao finalizar ou cancelar. A saída da Monaliza fica entre a fachada e as faixas de trânsito. Saves realizados durante o serviço registram uma posição segura no acesso exterior, tanto no estado pessoal quanto no snapshot do veículo dirigido.

## Arquivos principais

- `ui/HarborMinimap.gd`: desenho vetorial, marcadores, distâncias e projeção de interiores.
- `world/harbor/HarborAutoService.gd`: entrada, persiana, espera, reparo, preço e saída.
- `HarborGame.gd`: instalação dos dois sistemas no mundo oficial.
- `RegionTravel.gd` e `PersonalCarManager.gd`: posição segura nos snapshots durante o serviço.

## Validação

`tests/test_minimap_auto_service.gd`, Godot 4.7.2 com Vulkan: marcadores próximos/distantes e em garagem, ocultação enquanto dirige a Monaliza, ruas reais, saldo insuficiente, disparo automático, snapshots seguros, duração real da espera, preservação de pintura, cobrança única, restauração de controle/visibilidade/colisões, saída fora dos sólidos/faixas, não repetição, reparo/repintura de carro comum, pneus e cancelamento. Captura real: `D:/geteco/minimap-paynspray-review.png`.

Também foi executado `tests/test_monaliza_reward.gd` com os novos sistemas instalados: recompensa, porta-malas e save/load continuaram passando. Não houve alteração dos slots pessoais de save pelo teste.

Na inspeção visual, foi corrigida a exibição transitória da barra de frio durante a preparação da montanha em segundo plano: regiões carregadas por streaming começam não selecionadas, com HUD/clima/frio protegidos até a ativação regional.

O minimapa indica direção e distância; ainda não calcula uma rota de GPS. A validação não equivale a uma medição conclusiva de FPS do mundo completo.

Os farois deixam de emitir luz durante a entrada, reparo e saida automatica, evitando que o feixe atravesse a fachada. O estado de emissao anterior retorna no acesso exterior, inclusive no cancelamento. O servico aguarda o fim da entrada do personagem no carro.
