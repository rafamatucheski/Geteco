# Carros do Digo — geometria ao embarcar — 03/10/2026

Escopo: duas cabines existentes, Gol 1993 e Amarok 2014. Nenhum edifício, acesso ou interior novo.

## Correção

O cálculo genérico incluía os espelhos na largura interna. Ao embarcar, painéis e acabamento invadiam o exterior. Os dois modelos agora fornecem dimensões próprias de cabine. No Gol, o acabamento superior termina no teto, antes do vidro inclinado da tampa traseira.

As caixas maciças que atravessavam a cabine foram substituídas por fechamento do compartimento do motor e piso baixo. Teto, colunas e piso ficam em lotes fixos marcados `door_cut_exempt`, preservados pelo recorte das portas. Os demais veículos mantêm o comportamento existente.

## Evidências e cobertura

- Build de Harbor.csproj: sucesso, zero erros e avisos, Godot 4.7.2 .NET.
- `tests/test_digo_cabins.gd`: 30 verificações aprovadas. Portas dos dois lados, estrutura fixa, limites da cabine, acabamento superior, fechamento e reentrada sem duplicação.
- `tests/measure/measure_digo_boarding.gd`: interação pública no mapa real; dois ciclos de entrada/saída por carro. Capturas estacionado, abrindo, ocupado e após sair; amostras renderizadas de 30 segundos por carro, após aquecimento.
- Evidências em `evidence/digo/boarding-before-*`, `boarding-final-*`, `boarding-before.json`, `boarding-final.json` e `cabins-test.log`.

A validação é local ao embarque e à apresentação das cabines. Não certifica colisões de alta velocidade, combate, todas as câmeras ou iluminação global. Performance medida em sessão compartilhada tem caráter diagnóstico; isolamento de carga externa não foi demonstrado.

## Medição renderizada

RTX 4060 Laptop, Vulkan Mobile, 1920 × 1080. Execuções próprias sequenciais; 30 segundos por amostra. Runner final concluiu `DIGO_BOARDING_PASS final two cycles per vehicle` sem erro. Capturas finais de ambos os carros com portas fechadas e ocupante foram inspecionadas; acabamento do Gol não ultrapassa mais o teto e painéis da Amarok permanecem dentro da cabine.

| Veículo | p95 antes → final | p99 antes → final | FPS médio antes → final |
|---|---|---|---|
| Gol | 5,732 → 6,182 ms | 6,795 → 7,672 ms | 338,7 → 303,6 |
| Amarok | 6,763 → 6,588 ms | 8,303 → 7,868 ms | 279,6 → 296,6 |

Gol: aumento observado de 7,9% no p95 e 12,9% no p99; a execução intermediária também mostrou aumento (6,165/7,390 ms). Não aprovado como livre de regressão de performance. É necessário comparar sob carga externa isolada para atribuir a causa. Amarok: amostra final melhor que baseline, mas pico isolado de 135,319 ms (baseline 138,845 ms). Nenhuma alegação de certificação global de FPS.
