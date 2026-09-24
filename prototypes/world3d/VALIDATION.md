# Validação da primeira base — 21/09/2026

Registro histórico da primeira entrega. A versão seguinte, com direção e tráfego, tem medição isolada antes/depois em **SYSTEMS.md**.

## Estado

Base independente jogável; validações funcionais e de profundidade aprovadas nos casos abaixo. **Desempenho medido de forma preliminar, sem aprovação isolada e sem comparação equivalente com o jogo atual.**

## Funcional e visual

- Inicialização sem erros de script, usando a cena Main e os modelos originais locais.
- Movimento real por teclado, colisão do jogador contra caixa, manutenção da altura do piso, zoom, giro e pausa / retomada.
- Varredura dos corpos reais do jogador e de um NPC contra as quatro faces dos sólidos, com deslocamentos que atravessariam o objeto inteiro sem colisão.
- Spawns de 24 moradores livres de sobreposição; percurso físico de aproximadamente 100,75 m por pessoa em 65 s simulados, completando um quarteirão.
- Aumento de população para 96 sem sobrepor corpos; remoção para zero e restauração para 24.
- Ausência de SubViewports e objetos de colisão 2D na cena.
- Profundidade verificada em imagens: atrás da caixa, a imagem retém aproximadamente 55% dos pixels atribuídos ao ator; na frente e ao lado, ele permanece visível. Controles com ator e caixa ocultos evitam aprovar um personagem sempre invisível. Sombras contribuem para a diferença entre imagens; a conferência visual complementa o limiar numérico.
- Materiais do cupê vinculados, câmera e escala conferidas em capturas reais. A decoração e os edifícios ainda são uma base visual de estudo.

Evidências: `evidence/functional.json`, `evidence/depth.json`, `evidence/depth-*.png`, `evidence/world-*.png`.

O primeiro roteiro detectou vasos bloqueando a passagem no canto de cada quarteirão. Foram deslocados para liberar a rota. O roteiro final passou sem reduzir o requisito de circulação. A colisão e a oclusão foram avaliadas separadamente.

## Medição renderizada preliminar

Godot 4.7.2, Vulkan Mobile, NVIDIA RTX 4060 Laptop, 1280×720, MSAA 2×, VSync ligado e limite de 60 FPS. Mesma cena e rota física do Dante, oito carros estacionados e população indicada. Cada amostra contém 1.801 quadros e aproximadamente 30,015 segundos, após cinco segundos de aquecimento. Os dados são intervalos reais entre frames, não o contador suavizado da interface.

| Moradores no mundo | FPS médio | p50 (ms) | p95 (ms) | p99 (ms) | Máximo estável (ms) | Quadros >33,3 / >66,7 ms | Máximo aquecimento (ms) |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 | 60,00 | 16,667 | 16,767 | 16,858 | 17,101 | 0 / 0 | 27,897 |
| 24 | 60,00 | 16,667 | 17,116 | 17,742 | 19,445 | 0 / 0 | 46,035 |
| 96 | 60,00 | 16,669 | 17,193 | 17,472 | 20,193 | 0 / 0 | 75,857 |

**Concorrência conhecida:** o editor PID 48296 e o jogo atual PID 59692 permaneceram abertos. Não foram encerrados. O inventário foi coletado antes e aproximadamente a cada segundo durante cada execução; ver `evidence/concurrent-population*-processes.json`. As três execuções deste protótipo foram sequenciais.

Esses resultados mostram que as amostras realizadas mantiveram a cadência de aproximadamente 60 FPS, mesmo com a concorrência observada. Não quantificam a capacidade máxima, não isolam CPU/GPU, não certificam desempenho em outra máquina e não comprovam superioridade arquitetural. 96 pessoas estão distribuídas pelos quarteirões; não estão todas simultaneamente enquadradas. Não há trânsito, combate, clima ou streaming nesta base.

As janelas de aquecimento incluem picos, chegando a 75,857 ms com 96 pessoas. A criação síncrona inicial da cena ocorre antes dessas janelas, portanto o tempo total de abertura não está certificado por essa medição. A construção por lotes em tempo de jogo ainda precisará ser avaliada se virar requisito; o ajuste manual de população não é parte da amostra estável.

## Pendência objetiva

Para confirmar a linha de base sem outra execução concorrente, fechar a janela do jogo atual e executar `tests/Measure.ps1` sem `-AllowConcurrent`. O editor pode ficar aberto, mas isso deve continuar registrado. Esta pendência não impede jogar o protótipo; impede apresentar os números como aprovação isolada ou ganho frente ao jogo completo.
