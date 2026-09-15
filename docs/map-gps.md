# Mapa e GPS — 13/09/2026

M abre/fecha o mapa durante a exploração, a pé ou dirigindo. Esc fecha o mapa sem abrir o menu de pausa. O atalho `world_map` aparece na configuração de controles e pode ser remapeado.

Clique marca um destino; arraste move a vista; roda ajusta o zoom ao redor do cursor; botão direito limpa o GPS. Minha posição recentraliza a vista. Pontos próximos dos ícones selecionam o respectivo local. O mapa pausa a simulação e respeita diálogos, morte, bloqueios de controle e a pausa de outros menus.

O destino pessoal usa verde no mapa e no minimapa, com distância em linha reta em metros. A rota acompanha as ruas do `StreetRoute` e é recalculada na cadência existente de navegação. O marcador permanece mesmo quando não existe rota viária, com aviso no mapa. Chegar a menos de 65 unidades do ponto limpa o GPS. O objetivo da missão continua independente. O destino dura durante a sessão da cena e não é gravado no save.

`WorldMap.gd` compartilha a geometria já armazenada pelo minimapa. Não instancia outra câmera, viewport ou simulação. O desenho da tela completa atualiza quando a vista/destino muda; não há loop de atualização próprio. A preparação incremental da malha termina mesmo com o mapa pausado e atualiza a rota pendente.

## Validação

- `tests/test_map_gps.gd`: entrada pela viewport real, abrir/fechar, pausa, coordenadas do clique, rota viária, missão preservada, zoom, arraste, retenção/limpeza, origem `(0,0)`, ponto sem rota, chegada, carro e conflitos com diálogos/pausa.
- Capturas inspecionadas em 1280×720 e 1920×1080: `D:/geteco/artifacts/map-gps/map-1280.png` e `map-1920.png`.
- `-- early` exercita seleção imediatamente após a criação da interface, sem aguardar previamente a malha de ruas.
- As verificações funcionais do mapa passaram, incluindo a seleção enquanto a malha ainda estava pendente (`test-early.log`, `MAP_GPS_RESULT failures=0`). Essa última execução também registrou erros externos de compilação nos consumidores de `VehicleEngineSound.gd` (MonalizaAudioKit e GameLoading), durante alterações concorrentes desse arquivo. Portanto, o resultado aprova os comportamentos verificados do mapa, não uma inicialização sem erros do projeto inteiro. Os arquivos de áudio não foram alterados nesta tarefa.
- `tests/measure_map_gps.gd`: HarborGame real, seed 913, estado pós-chegada, saves isolados, 20 s de aquecimento e amostras reais entre frames por pelo menos 30 s. Sem argumentos mede baseline; `-- gps` mede minimapa com destino e depois mapa aberto. Amostras em `D:/geteco/artifacts/map-gps/`.

Referência: Godot 4.7.2, Vulkan Mobile, RTX 4060 Laptop, configuração normal com limite de 60 FPS. O orçamento de referência é 16,67 ms; piora acima de 5% em p95/p99 exige confirmação. Outras instâncias de Godot e alterações concorrentes de áudio impedem certificar uma comparação controlada de performance nesta sessão. O benchmark não certifica circulação nem física dos locais representados.

| Amostra | Frames / segundos | FPS médio | p50 / p95 / p99 (ms) | Máximo (ms) | >33,3 / >66,7 ms |
|---|---|---|---|---|---|
| Antes | 1670 / 30,004 | 55,66 | 17,039 / 25,716 / 29,790 | 36,186 | 3 / 0 |
| GPS ativo | 1770 / 30,013 | 58,97 | 16,644 / 19,923 / 28,457 | 45,285 | 7 / 0 |
| Mapa aberto, mundo pausado | 1801 / 30,015 | 60,00 | 16,665 / 16,802 / 16,985 | 17,681 | 0 / 0 |

Os números são observações do ambiente disponível, não prova de ganho de FPS. O máximo de frame aumentou no cenário GPS, embora p95/p99 tenham diminuído; CPU, GPU e interferência de outros processos não foram isoladas. O carregamento anterior à janela estável também não está certificado por estas amostras.
