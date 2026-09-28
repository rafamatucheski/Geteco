# Rodoviária — restauração de 26/09/2026

O prédio existia na apresentação de transporte do jogo, mas o worker da prévia não instanciava essa apresentação. A operação da V1 não tinha sido migrada. A prévia e o catálogo 2D agora usam a mesma geometria da produção: edifício, quatro plataformas e guarita em Harbor, X 106,25 / Z 66,25.

## Operação migrada

- Quatro serviços com o modelo de ônibus da V1 e dezesseis passageiros com identidades conservadas durante a sessão.
- Desembarque e embarque caminhando até a porta, fechamento, ré, saída, circulação nas ruas atuais, retorno e nova troca de passageiros.
- Duas cancelas físicas, autorização da guarita, espera antes da barreira e fechamento somente após a traseira passar e a área ficar livre.
- Um ônibus por vez nas manobras do pátio. Nas ruas, usa o motorista nativo de `Vehicle.gd`, incluindo trânsito e semáforos.
- Suspensão de processamento e colisões à distância, retomando as mesmas instâncias. Passageiros aguardando não executam física depois de assentados no chão.
- Rotas corrigidas para o sentido das faixas da V2; bicicletário, poste e piso lateral ajustados para liberar a saída. Se as ruas editadas não formarem uma rota, os serviços aguardam nas plataformas.

A chegada M00 e os transportes já existentes continuam independentes. A prévia contém apenas arquitetura, sem iniciar ônibus ou passageiros. Esta migração não inclui assumir o volante/roubar os ônibus da V1 nem cria um interior acessível.

## Evidências e validação

Capturas reais: [editor 2D + 3D](../evidence/terminal-20260926/preview.png) e [operação no jogo](../evidence/terminal-20260926/operation.png). A captura de operação usa simulação acelerada para percorrer o ciclo e não serve como benchmark.

- Cancelas: 10 verificações aprovadas, incluindo bloqueio físico, autorização, traseira e pedestre impedindo fechamento.
- Ciclo completo: 24 verificações aprovadas tanto sem trânsito quanto em execução renderizada com trânsito normal; quatro partidas e primeiro retorno, sem substituir passageiros.
- Validação final após suspensão da física dos passageiros parados: 25 verificações aprovadas sem trânsito, incluindo a segunda troca de passageiros após retornar à plataforma.
- Ciclo de vida: 5 verificações aprovadas; suspensão, retorno sem duplicação e retenção segura sem rota.
- Editor: 6 verificações aprovadas; geometria correta e passiva, sem modificar o mapa salvo.
- Seleção do editor: 21 verificações aprovadas, incluindo objetos pequenos e piso da rodoviária.
- Chegada M00: teste aprovado, incluindo desembarque e progressão inicial.

Os testes usam `--no-save`. Permanecem avisos de recursos de renderização no encerramento, também observados na base.

## Performance: medida, com estabilidade ainda pendente

Cena Main real, RTX 4060 Laptop, Godot 4.7.2 Mobile/Vulkan, 1280×720, VSync desligado, limite 144 FPS, câmera e clima fixados, trânsito normal. Cada amostra tem 8 s de aquecimento e 30 s medidos. Meta provisória: 60 FPS; sinal de investigação: regressão maior que 5% em p95/p99.

| Amostra | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms | Frames >33,3 / >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|
| Base anterior | 119,72 | 6,031 | 12,651 | 19,099 | 140,369 | 31 / 17 |
| Controle atual, operação desligada | 117,67 | 8,779 | 13,845 | 15,410 | 61,663 | 1 / 0 |
| Operação final, amostra com travadas | 96,44 | 9,879 | 16,059 | 36,524 | 637,491 | 35 / 12 |
| Confirmação da mesma operação | 112,32 | 9,549 | 13,425 | 14,817 | 23,247 | 0 / 0 |

A confirmação não reproduziu as travadas e ficou próxima do controle em p95/p99. Isso não demonstra a causa da intermitência nem autoriza apagar a amostra ruim. O p95 da confirmação ainda é 6,1% maior que o baseline original; o próprio controle atual também difere daquele baseline. Não há certificação de estabilidade de performance: permanece pendente isolar as travadas intermitentes. O aquecimento da confirmação teve máximo de 163,121 ms, separado do regime medido.

Amostras brutas e configuração em `evidence/terminal-20260926/{before,control,after,after-confirm}/performance.json`; a primeira medição após a implementação foi preservada em `after/performance-initial.json`.

Nenhum interior novo: permanecem 32 acessos / 30 interiores distintos e zero novas certificações integrais de interiores.
