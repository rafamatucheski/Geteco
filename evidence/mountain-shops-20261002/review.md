# Lojas da montanha — 02/10/2026

Escopo: Boutique Alpina, Casacos da Vila e Último Abrigo. Três lugares físicos e três interiores distintos; nenhum novo lugar. Reforma implementada, sem certificação integral de performance.

## Diagnóstico e correções

- Fachadas compartilhavam acabamento liso e manequins antigos. Agora madeira, pedra e fundo de tecido têm texturas compartilhadas; cada loja tem paleta própria e manequins no corpo articulado atual. Fachadas conservam somente os nomes dos estabelecimentos.
- Manequins internos cilíndricos substituídos por jaquetas e sobretudos proporcionais. Expositores ficam congelados, sem animação por frame.
- Balcões deixavam espaço insuficiente atrás e atendimento ficava junto ao spawn. Balcões avançados, vendedores reais acrescentados em espaço livre e compra movida para o lado do cliente.
- Araras com cabides e mangas, bancos com pés, espelhos emoldurados, rodapés e materiais de madeira/tecido. Casacos da Vila recebeu banco junto à área de prova e manequim afastado da circulação.
- Texturas aplicadas por identidade explícita da peça, evitando perda nas malhas com nomes automáticos do Godot. Union e modelos globais de NPC não foram reformados.

## Evidência

Godot 4.7.2 .NET, Vulkan Mobile, RTX 4060 Laptop GPU, capturas Main 1280×720. Harbor.csproj compilado com zero erros/avisos. Saves pessoais preservados (`--no-save`).

| Verificação | Resultado |
|---|---|
| Física — jogador/NPC, spawn, atendimento, sólidos, faces/cantos, portas das três fachadas | 652 checks aprovados em `tests/test_mountain_shop_review.gd`; [log](../mountain-shops-review-20261002-physics.log) |
| Profundidade renderizada — jogador e vendedor antes/atrás/ao lado dos balcões, com controles positivos | 36 checks aprovados em `tests/test_mountain_shop_occlusion.gd`; [log](occlusion.log), [imagens](occlusion/) |
| Main real — caminhar até o caixa, abrir menu, sair, limpar vendedor e reentrar com um único vendedor | 18 checks aprovados; [relatório](after/report.json) |
| Acabamento final após correção de textura/vestuário | 6 fotos reais inspecionadas; [relatório da captura](final/report.json), [log sem erros](final.log) |
| Frame time antes/depois | Inconclusivo: outras sessões iniciaram jogos durante a base. Amostras rejeitadas para aprovação; nenhuma atribuição de ganho ou regressão |

O fluxo Main usa teleporte para preparar cada local e admissão direta da sessão; a caminhada até o caixa usa movimento real. Abertura e bloqueio das portas têm teste físico separado. Isso não certifica a caminhada contínua por todos os limiares, save/load, todas as oclusões de cada móvel, nem cenários de combate, chuva/noite. Luzes e câmera existentes foram preservadas.

A base contém seis amostras de 30s, aquecimento separado e intervalos brutos em [before/report.json](before/report.json), mas houve concorrência documentada em [processes-before.json](processes-before.json). Metas previamente adotadas: 60 FPS/16,67ms; aumento >5% em p95/p99 pede confirmação. Não há comparação isolada válida; capturas posteriores não são benchmark. Não encerrar processos de outras sessões para obter números.

## Fotos antes/depois

| Loja | Antes exterior | Depois exterior | Antes interior | Depois interior |
|---|---|---|---|---|
| Boutique Alpina | [foto](before/mountain_boutique-outside.png) | [foto](final/mountain_boutique-outside.png) | [foto](before/mountain_boutique-inside.png) | [foto](final/mountain_boutique-inside.png) |
| Casacos da Vila | [foto](before/mountain_village_outfitters-outside.png) | [foto](final/mountain_village_outfitters-outside.png) | [foto](before/mountain_village_outfitters-inside.png) | [foto](final/mountain_village_outfitters-inside.png) |
| Último Abrigo | [foto](before/mountain_outfitters-outside.png) | [foto](final/mountain_outfitters-outside.png) | [foto](before/mountain_outfitters-inside.png) | [foto](final/mountain_outfitters-inside.png) |

Estado do lote: implementação em 3/3; certificação integral 0/3, três em validação por pendências acima. Nenhuma aprovação global de interiores.
