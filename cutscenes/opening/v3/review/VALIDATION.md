# Verificação da abertura — 11/09/2026

## Correção de direção artística

A fotografia de aparência realista foi substituída por um retrato renderizado no Godot, usando o construtor de personagens de produção. Conferidos visualmente o asset, o quadro na casa e a fotografia nas mãos de Dante no ônibus. A captura dos planos passou; `test_opening_stage_v3.gd` passou nas verificações de identidade da textura, poses e idioma. Essa execução headless reportou recursos de áudio ainda em uso no encerramento; não se considera esse aviso resolvido por esta alteração de arte. A importação geral também reportou `CarjackedDriver.tscn: Busy`; o carregamento e a captura da abertura concluíram. Verificador de referências: 0 quebras novas. Prévia completa atualizada com a fotografia estilizada.

Godot 4.7.2, Windows. Captura real: Vulkan / Forward Mobile / RTX 4060 Laptop. Testes headless foram usados para comportamento, nunca para alegar desempenho gráfico.

| Verificação | Resultado |
|---|---|
| `test_opening_cutscene_runtime.gd` | PASS: reprodução natural de 68 s, ordem/duração dos planos, pausa, retomada, seek, pulo e conclusão única |
| `test_opening_audio_sync.gd` | PASS: preparo sem autoplay, início após primeiro desenho e preenchimento da janela |
| `test_harbor_presentation_audio.gd` | Trecho de abertura PASS: RCM de 2,8 s, filme completo e pulo; trecho do áudio da cidade com 3 falhas descritas abaixo |
| `test_opening_stage_v3.gd` | PASS: contatos de mão, proporções dos olhos, fotografia compartilhada, porta, legendas e voz EN; encerramento sem vazamento de streams |
| `test_opening_campaign_v3.gd` | PASS: missão real usa V3; cidade pausada; flag ao terminar; madrugada e chuva; desembarque; ligação de Maciota; primeiro objetivo disponível |
| Captura natural MovieWriter | PASS: 2048 quadros / 30 fps, aproximadamente 68,27 s, `OPENING_V3_MOVIE_COMPLETE`; sem erros no log final |
| Inspeção visual | Planos de café, fotografia, ligação, decisão, mochila, quadro vazio, estrada, cabine e terminal revisados por captura Vulkan |
| `tools/check_references.py` | PASS: 0 referências novas quebradas |
| `profile_load_time_0909.gd` | Carregamento concluiu; auditorias da rua e Breakwater com 0 erros/ocorrências; aviso Camera2D de interpolação |
| `test_pedestrian_life_routines.gd` | PASS |
| `test_pedestrian_render_lod.gd` | PASS: failures=0 |

A integração da campanha testa o fim natural a partir dos últimos dois segundos; a reprodução integral é verificada separadamente pelo teste de runtime e pelo vídeo. Nenhum teste acelerado é apresentado como prova de que o filme completo foi assistido em tempo real.

## Limite da suíte geral

`test_menu_flow_integration.gd` passou por Novo Jogo, pulo da abertura, desembarque, pausa, salvar, configurações e retorno ao menu, mas terminou com duas falhas na seleção/carregamento de slot. O teste procura um Button diretamente em SlotListContainer; a UI atual envolve o botão em SaveSlotRow/HBoxContainer. Também surgiram erros ao descarregar a montanha durante construção assíncrona (`IceStormManager`, `MountainPass`, `ContinuousWorld`). Esses módulos e esse teste não foram alterados por esta entrega. Não se declara a suíte geral inteira aprovada.

O trecho de cidade de `test_harbor_presentation_audio.gd` falhou em três expectativas: quantidade fixa de fontes (duas verificações) e crossfade no porto. As alterações desta entrega nesse teste atualizam apenas a duração da abertura e o nome da cartela RCM; não alteram as expectativas nem o sistema sonoro da cidade. A reprodução integral da abertura, a logo e o pulo passaram também nessa execução.

Limites artísticos: animação procedural estilizada e voz sintética. A execução técnica está integrada; avaliação de direção, atuação e gosto continua sendo feita pelo vídeo e pelo jogo.
