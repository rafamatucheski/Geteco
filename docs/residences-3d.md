# Residências 3D

Três opções no Porto, a $10.000, $25.000 e $45.000. Uma residência ativa por campanha; crédito de 70% na troca. Fachadas sem letreiros, interiores 3D em projeção ortográfica, mobiliário com colisões projetadas e escala do Dante pelo mesmo adaptador do banco. Roupa, arsenal, refeição, escolha de horário e checkpoint preservados.

Cada propriedade tem calçada, acesso à rua e duas vagas: Monaliza e um carro extra. Para registrar o extra, estacione completamente dentro de uma vaga, pare e saia do carro. O save captura o carro imediatamente e o restaura com posição, rotação, pintura, vida e melhorias suportadas. Um carro parado fora das vagas não é registrado. A integração com RegionTravel evita duplicação ao salvar dirigindo o carro anteriormente estacionado.

## Verificação

- `tests/test_residence_prototype.gd`: compra/troca, ações internas, transições, checkpoint, save real em diretório temporário, recarga da cena com carro estacionado e dirigindo, limite de uma vaga extra, caminhos externos e alcance de todas as interações internas com colisões reais.
- `tests/capture_residence_prototype.gd`: três exteriores, três interiores, compra, estacionamento e noite, em HarborGame renderizado.
- `tests/measure_residences.gd`: seed 4702, HarborGame, 1280×720, GPU RTX 4060 Laptop, Godot 4.7.2 Mobile/Vulkan, VSync desativado e limite normal de 60 FPS; 5 s de aquecimento e pelo menos 30 s de amostragem por cenário. Comparativo em dia claro. Editor e processo headless preexistentes permaneceram abertos nos dois lados; nenhum benchmark concorrente.

| Cenário | Versão | Frames / segundos | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 / >66,7 ms |
|---|---|---|---|---|---|---|---|---|
| Exterior | Greybox | 1799 / 30,000771 | 59,965 | 16,691 | 17,982 | 20,743 | 59,831 | 1 / 0 |
| Exterior | 3D | 1799 / 30,000288 | 59,966 | 16,637 | 17,854 | 18,550 | 57,875 | 2 / 0 |
| Interior | Greybox | 1800 / 30,000945 | 59,998 | 16,644 | 17,671 | 18,605 | 42,090 | 1 / 0 |
| Interior | 3D | 1801 / 30,010051 | 60,013 | 16,677 | 17,782 | 18,323 | 22,232 | 0 / 0 |

Sem regressão acima do critério prévio de 5% em p95/p99 nos cenários medidos. Os tempos são intervalos reais entre frames, não tempo GPU isolado. A meta provisória de 60 FPS foi mantida em média; p95 não está abaixo de 16,67 ms em todos os frames. A conclusão não certifica outras máquinas, chuva, todas as regiões ou latência da primeira visita.

As fachadas fazem quatro quadros de preparação e ficam em cache. Interiores renderizam ao entrar e ficam sem atualizações contínuas; a projeção e os controles continuam ativos. Não foram adicionadas luzes 2D por casa. Cada interior possui uma luz direcional com sombra, avaliada apenas nos quadros que atualizam o cache.
