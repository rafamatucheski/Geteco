# Tarefa para Antigravity — congelamentos restantes

Investigar e corrigir os picos de tempo de quadro que continuam no Geteco. As alterações de missão, estacionamento, desvios, áudio, vagas e semáforos já foram implementadas. Preservar esse trabalho e as demais alterações locais existentes; não restaurar o repositório inteiro.

Leia `AGENTS.md`, as skills `performance-do-jogo` e `testes-com-criterio` e o [relatório desta entrega](resultado-feedback-2026-09-14-teste-2.md). Projeto: `D:/geteco/game`.

## Evidência disponível

- `D:/geteco/artifacts/feedback-0914-teste2/before-stability/driving.json` e `.csv`: 53,14 FPS, p95 25,89 ms, máximo 121,16 ms.
- `D:/geteco/artifacts/feedback-0914-teste2/after-stability/driving.json` e `.csv`: 53,84 FPS, p95 25,92 ms, máximo 121,06 ms; 11 quadros acima de 66,7 ms.
- O CSV contém tempo de quadro, processo, física, draw calls e posição. Picos aparecem, entre outros pontos, perto de x=709–840 e x=1752–1932, y=425. Parte coincide com indicadores de processo de 70–86 ms; a física fica perto de 6–7 ms. Esses indicadores não são atribuição de custo por função.
- `tour-final/frames.json`: missão concluída, pico de 234,60 ms. A captura `tour-final/final.png` mostra o estacionamento final.
- Uma cópia anterior preservada está em `D:/geteco/artifacts/feedback-0914-teste2/baseline-project`. Não editar essa referência.

## Execução sugerida

1. Reproduzir uma única janela com o cenário abaixo e registrar um perfil de funções. Usar os eventos e posições dos CSVs para procurar trabalho síncrono caro. Investigar apresentação de entidades, geração de recursos, áudio e renderização conforme o perfil; não tratar uma hipótese como causa.
2. `PresentationBudget.gd` limita trabalho entre entidades, mas uma chamada individual de `ensure_presentation()` ainda pode exceder o orçamento. Verificar se isso ocorre nos picos antes de alterar o sistema. Separar tempo de script de espera do render/GPU.
3. Corrigir apenas a causa demonstrada, mantendo colisão, qualidade visual e tráfego. Fazer uma comparação finita antes/depois nas mesmas condições. Não rodar benchmarks em paralelo.
4. Confirmar o passeio com `tests/measure_feedback_tour_0914.gd` e executar as regressões pertinentes ao código alterado. Não repetir toda a suíte sem necessidade.

Comando PowerShell para a circulação livre (usar um diretório de saída novo):

```powershell
& 'D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --path D:/geteco/game --script res://tests/measure_game_frame_stability.gd -- --normal-cap out_dir=D:/geteco/artifacts/feedback-0914-antigravity/profile
```

O cenário usa seed 12092026, resolução 1280 × 720, Vulkan Mobile, VSync e limite de 60 FPS, preparação de recursos, 10 s de aquecimento e 30 s de circulação. A flag `ready` das estatísticas de `ContinuousWorld` refere-se à travessia para a montanha; `false` sozinho não demonstra um carregamento travado.

Entrega esperada: causa comprovada, alteração revisável, métricas p50/p95/p99/máximo e contagem de quadros >33,3/>66,7 ms, regressões pertinentes e limitações restantes. Alvo provisório: 60 FPS/16,67 ms. Não marcar o problema resolvido apenas por uma captura parada, resultado headless ou aumento do FPS médio.
