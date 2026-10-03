# Serra Viva — zoológico da montanha

Implementação em 03/10/2026. Local: `(716, 0, -363)`, ao norte do lago alpino, com acesso de pedestres pela estrada em `(716, 0, -330)`.

## Conteúdo

- Doze animais próprios e estilizados: girafas, leões, macacos-vervet e zebras, com proporções, pelagem e vocalizações referenciadas em animais reais.
- Quatro recintos com contornos irregulares, cercas físicas, abrigos, bebedouros, passeio periférico e caminhos centrais. O terreno editável reserva a clareira e remove árvores que invadiriam os recintos.
- Entrada de $30 por visita. O ingresso é validado contra o recibo da economia no save; sair encerra a visita. Saldo insuficiente não abre a passagem.
- Quatro visitantes com carteiras individuais, fila, gesto de pagamento, passeio e saída. A autorização de passagem é individual: um NPC pagando não libera o jogador sem ingresso.
- Gravações reais com atenuação espacial; a vocalização de girafa toca apenas à noite. Autoria, fontes, licenças e referências: [créditos](../../assets/zoo/audio/CREDITS.md).

## Validação

Motor obrigatório: Godot 4.7.2 .NET, `Harbor.csproj` compilado sem erros ou avisos. Testes isolados e sessões completas usam estado temporário, sem gravar saves do jogador.

- `tests/test_mountain_zoo.gd`: PASS — região editável real, população, limites de movimento, obstáculos para jogador/NPC, suporte do solo e descarregamento/retorno.
- `tests/test_mountain_zoo_tickets.gd`: PASS — insuficiência de saldo, cobrança única, nova visita, restore, rejeição de recibo forjado, quatro NPCs pagando $120 sem debitar o jogador, NPC sem dinheiro barrado e ciclo de vida.
- `tests/test_mountain_zoo_depth.gd`: PASS — 12 comparações renderizadas, dois atores, banco/cerca, posições à frente/atrás/ao lado, com controle positivo. Evidência em `artifacts/mountain-zoo/depth.json`.
- `tests/test_mountain_zoo_audio.gd`: PASS — quatro recursos importados decodificados pelo mixer 3D, sinal próximo diferente de zero, silêncio a 150 m. Evidência em `artifacts/mountain-zoo/audio.json`. A primeira tentativa do fixture não tinha câmera ativa e não constitui falha das gravações; foi corrigida antes da execução válida.
- `tests/measure/review_mountain_zoo.gd`: PASS nos 16 pontos — sessão completa, compra pela interação normal, passeio central/periférico e saída. Capturas e alturas em `artifacts/mountain-zoo/tour/`. Ver ressalva de encerramento abaixo.

## Desempenho e limitações

RTX 4060 Laptop, Vulkan Mobile, janela 1280 × 720, VSync desligado, FPS sem limite, 40 civis da sessão e até quatro visitantes + caixa do zoológico. Comparações de 30 segundos na mesma sessão, câmera e local. Roupa de ski equipada nos dois cenários, para manter o sistema de frio funcionando sem acionar resgate. Os controles retiram apenas o zoológico da árvore: medem seu custo incremental na clareira atual, não recompõem a floresta anterior.

O agrupamento de peças por forma e cor de instância reduz chamadas de desenho sem retirar geometria, animações ou sombras. A correção sRGB mantém as cores originais.

Na visão panorâmica, a série `batched-*` mediu:

| Passagem | Controle sem zoológico (FPS / p95 / p99) | Com zoológico (FPS / p95 / p99) |
| --- | --- | --- |
| 1 | 63,75 / 22,70 ms / 35,55 ms | 52,53 / 27,30 ms / 31,21 ms |
| 2 | 84,02 / 16,06 ms / 23,26 ms | 61,60 / 18,75 ms / 32,16 ms |

Há variação da carga ambiente e custo incremental acima de 5%; **performance panorâmica não aprovada**. Os dados completos preservam máximos, contagem de frames acima de 33,3/66,7 ms e amostras individuais.

A série `walking-*`, com a câmera normal de caminhada, mediu:

| Passagem | Controle sem zoológico (FPS / p95 / p99) | Com zoológico (FPS / p95 / p99) |
| --- | --- | --- |
| 1 | 100,86 / 14,41 ms / 21,79 ms | 85,63 / 15,43 ms / 16,32 ms |
| 2 | 76,09 / 20,98 ms / 42,20 ms | 74,32 / 16,28 ms / 23,97 ms |

Na primeira passagem, o tempo médio de GPU foi de 1,94 para 2,45 ms; o tempo de CPU de renderização, de 0,95 para 1,29 ms. Os dois p95 com zoológico ficaram abaixo de 16,67 ms, mas a segunda amostra teve 14 quadros acima de 66,7 ms (também 14 no controle). O log mostra carregamentos de recursos da sessão durante o experimento. Não há base para declarar ausência de regressão ou 60 FPS estáveis. Não foram removidos tráfego, sombras, civis ou sistemas globais para obter um resultado artificialmente favorável. Não ampliar a conclusão para outros equipamentos ou câmeras.

As sessões completas terminaram com avisos do motor sobre 16 objetos/2 recursos e cinco instâncias de renderização ainda alocados. Os testes isolados de bilheteria e áudio terminam sem esses avisos; a origem no ciclo de vida da sessão completa não foi estabelecida. Isso permanece pendente, sem certificar estabilidade global.

As primeiras capturas e medições são diagnósticas, anteriores à revisão do terreno. A série `paired-*` é inválida: hipotermia provocou resgate e troca de região durante a medição. Não deve ser usada para aprovar performance. A série corrigida equipa a roupa de ski nos dois cenários e aborta se o jogador sair da posição medida.

Escopo: cadeia local da montanha, bilheteria, economia/save, visitantes, áudio, física e apresentação. Não certifica todos os mapas, combate ou iluminação global. Nenhuma luz adicional foi criada.
