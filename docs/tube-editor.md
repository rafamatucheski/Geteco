# Tubos de ônibus editáveis — 26/09/2026

Os seis tubos de Harbor agora aparecem como peças editáveis, identificadas na biblioteca por “Tubo · nome da parada”. Catálogos existentes são atualizados ao abrir o editor, sem exigir regeneração manual. O exportador também produz esses registros.

É possível mover, girar, ajustar largura/profundidade, excluir, desfazer/refazer e restaurar o original, no editor 2D ou 3D. O conjunto mantém sua identidade na linha; não é convertido em um prédio genérico nem duplicado pela biblioteca.

`UrbanTransitPresentation` aplica o documento ao construir a arquitetura. A transformação usa o mesmo adaptador físico das outras peças: geometria e sólidos acompanham a edição, com formas de colisão recalculadas e sem colisão fantasma na posição anterior. IDs e índices da linha permanecem estáveis. Os pontos usados pelo transporte são transformados junto do tubo; paradas excluídas deixam de oferecer interação e são puladas pela linha 510. Sem duas paradas ativas, uma nova viagem de ônibus é recusada. O roteador existente continua exigindo uma rua alcançável próxima ao destino.

A rodoviária e suas manobras não são deslocadas por essas edições. Não há novo interior nem alteração na contagem de acessos/interiores. Os testes usam documentos temporários e preservam o mapa oficial.

## Validação

- `test_tube_edits.gd`: 15 verificações aprovadas — posição, transformação do ponto da linha e aproximação de passageiros, identidade, colisão física no novo local, ausência no antigo, interação e exclusão de paradas.
- `test_tube_editor.gd`: 14 verificações aprovadas em execução renderizada — catálogo, controles 3D, prévia passiva, exclusão visual, desfazer, gravação, recarregamento e restauração.
- `test_terminal_lifecycle.gd`: 5 verificações aprovadas de ativação, suspensão e retomada da operação compartilhada da rodoviária; o encerramento ainda reportou objetos/recursos pendentes de liberação.
- Capturas reais: [editor](../evidence/tube-editor/editor.png) e [jogo com tubo alterado](../evidence/tube-editor/after/world.png).

O teste de transporte verifica integração dos pontos e seleção de paradas; não equivale a uma viagem completa por todas as combinações de tubos reposicionados.

## Performance

Main renderizada, Godot 4.7.2 Mobile/Vulkan, RTX 4060 Laptop, 1280×720, limite normal 144 FPS, tráfego normal e clima fixo. Câmera igual sobre o tubo Centro / Comércio, 8 s de aquecimento e 30 s medidos, sem benchmarks simultâneos. Depois: tubo movido 2 m por eixo, girado 5° e ampliado 10% nos dois eixos horizontais. Meta provisória 60 FPS; tolerância p95/p99 de 5%.

| Amostra | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 / >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|
| Antes | 143,58 | 5,466 | 10,822 | 11,745 | 16,615 | 0 / 0 |
| Depois | 143,25 | 5,534 | 10,955 | 11,956 | 21,653 | 0 / 0 |

Sem regressão acima do critério neste cenário: p95 +1,23%, p99 +1,80%. Não certifica ampliações arbitrárias nem outros mapas. Amostras, aquecimento e configuração em `evidence/tube-editor/{before,after}/performance.json`. Avisos de liberação de texturas no encerramento também ocorreram na base.
