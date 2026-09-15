# Cume Branco — interior 3D, 14/09/2026

Refeito com a técnica do chalé: câmera em perspectiva fixa, materiais PBR compartilhados, parede de toras, piso de tábuas, balcão com painéis e tampo de ardósia, lareira vazada de cantaria com o mesmo MountainHearthEffects3D, lustres de ferro, cortinas com dobras, skis com fixações, botas e banco estofado. Não há novos rigs de personagens ou viewports por ator. Efeitos e renderização são suspensos com a sala vazia.

A posição final da câmera é aplicada antes da projeção dos sólidos, spawns e interações. Os bloqueios continuam derivados das próprias malhas por interior_solid_id. Soleiras delimitam o fim do piso; os sensores de saída foram centralizados nos vãos. Helena fica ao lado da lareira, em piso livre e visível.

## Validação

- `tests/test_ski_lodge_cutaway.gd`: aprovado headless e renderizado. Inventário/classificação das malhas; circulação real de jogador e visitante nas duas laterais, balcão, rack e portas; aluguel e retirada de equipamento; ambas as saídas via request_interaction; reentrada; recuperação de save inválido; respawn; suspensão do fogo e viewport vazio.
- Teste renderizado da própria lareira: região do ator atrás da pedra não muda ao ocultar o rig (0 pixels, jogador e visitante); ao lado, controle positivo de 187/192 pixels. O adaptador fica suspenso apenas durante a comparação para não restaurar a visibilidade entre capturas.
- `tests/test_projected_interior_contract.gd`: aprovado renderizado após ampliar as aproximações do Cume Branco para lados e diagonais dos sólidos. Residentes não precisam de fallback; rigs compartilham profundidade e são restaurados no descarregamento. O controle positivo foi corrigido para piso livre, fora do vestiário sólido, com o outro ator afastado. Resultado final: failures=0.
- Capturas reais: `D:/geteco/artifacts/lodge-cutaway/overview.png`, `room.png`, `gameplay.png`.
- Logs: `D:/geteco/artifacts/lodge-cutaway-headless.log`, `lodge-cutaway-rendered.log`, `lodge-3d-contract-rendered.log`.

## Desempenho local

`tests/measure_cabin_depth.gd -- lodge-3d-before ski_lodge` e `-- lodge-3d-after ski_lodge`, na cena MountainPass real, entrada pelo manager, mesma posição do jogador, seed e janela 1280×720. Godot 4.7.2 Mobile/Vulkan, RTX 4060 Laptop, VSync ligado, limite 60 FPS. Cinco segundos de aquecimento e 30 segundos de amostras de tempo real. Meta de referência: 60 FPS; aumento de p95/p99 acima de 5% exigiria investigação.

| Métrica | Antes | Depois |
|---|---:|---:|
| Frames | 1801 | 1801 |
| Duração (s) | 30,013638 | 30,012419 |
| FPS médio | 60,006 | 60,008 |
| p50 (ms) | 16,662 | 16,666 |
| p95 (ms) | 16,958 | 16,958 |
| p99 (ms) | 17,205 | 17,199 |
| Máximo (ms) | 17,937 | 17,818 |
| Frames >33,3 / >66,7 ms | 0 / 0 | 0 / 0 |

Amostras JSON e capturas em `D:/geteco/artifacts/interior-solids-0913/lodge-3d-{before,after}.*`. Não houve regressão observada neste cenário. Outras instâncias Godot estavam abertas e foram preservadas; o limite de FPS não mede margem de GPU. Não há certificação isolada de capacidade nem de primeira visita/compilação de shaders. Os runners integrados reportam recursos remanescentes ao encerrar, também presentes no baseline; o teste de contrato com descarregamento explícito termina sem essas mensagens. Não foram alterados subsistemas externos para eliminar esses avisos.
