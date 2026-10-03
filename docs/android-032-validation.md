# Android 0.3.2 — 03/10/2026

APK de teste ARM64, pacote `com.geteco.harbor`, código 302. Gerado com
Godot 4.7.2 .NET e templates oficiais mono. O alvo Android usa .NET 9,
compatível com o runtime embarcado; desktop permanece em .NET 10.

## Controles e rotação

- Rotação automática nas quatro posições (`SCREEN_SENSOR`, valor 6).
  O manifesto exportado usa `fullUser` (13), atividade redimensionável e
  tratamento de alterações de configuração. Ative a rotação automática do Android.
- Layout específico para proporções estreitas/quase quadradas: alvos maiores,
  ataque acima da mira, comandos extras em três colunas.
- Zona morta central de 12% nos analógicos; corrida na borda preservada.
- Redimensionar libera dedos e ações. Opções e rádio preservam direção/aceleração.
- Garagem mantém bloqueio de ataque e troca de armas.

Referência de orientação: [DisplayServer](https://docs.godotengine.org/en/4.6/classes/class_displayserver.html#enum-displayserver-screenorientation).

## Verificações

Compilação desktop sem erros/avisos. Publicação C# Android concluída; APK contém
`assets/.godot/mono/publish/arm64/Harbor.dll` e runtime Mono ARM64.
Assinaturas v2/v3 verificadas. APKs e chaves permanecem fora do Git.

Seis testes passaram: `test_android_controls` (51 verificações),
`test_camera_controls`, `test_dualsense_controls`, `test_garage_driver_restore`,
`test_inventory_panel`, `test_settings_menu`.
Relatório local: `evidence/test-suite/suite-2026-10-03_130504_747-459b08d9e71e44208dc6d1b3b41b03df.json`.

O primeiro teste de toque falhou na expectativa da mira após soltar o dedo de
mira enquanto ainda andava. O comportamento existente acompanha o movimento
nessa situação. A sequência agora para o movimento antes de soltar a mira,
verificando preservação da última direção quando parado.

Capturas renderizadas revisadas em 1170×540, 540×1170, 900×840 e 840×900,
com opções abertas e fechadas. Evidências em `evidence/mobile-20261003/`;
runner `tests/capture/capture_mobile_layout.gd`. Isso verifica redimensionamento
desktop, não sensores, recortes físicos ou dobrar/desdobrar no Android.

## Comparação de performance desktop

Main real, 8 pedestres solicitados, 39 veículos, Mobile/Vulkan, RTX 4060 Laptop,
1920×1080, VSync desligado e sem limitador. Mesmo runner `measure_full.gd`,
5 segundos de aquecimento e 30 segundos medidos; editor aberto nos dois casos.
Alvo provisório 16,67 ms; tolerância de investigação 5% em p95/p99.

| Amostra | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 / >66,7 ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Antes | 180,96 | 4,587 | 8,899 | 9,859 | 21,063 | 0 / 0 |
| Depois | 179,46 | 4,687 | 9,057 | 9,984 | 17,316 | 0 / 0 |

Sem regressão material nessa amostra (+1,8% p95 / +1,3% p99).
Não certifica toda a cidade, eventos de primeira visita ou desempenho Android.
Dados brutos: `before.json`, `after.json` e respectivos logs/capturas no diretório
de evidências acima.

## Pendências e escopo

Nenhum dispositivo ADB conectado. Instalação, quatro posições físicas,
dobrar/desdobrar, multitarefa, aquecimento e FPS no Fold7 **não verificados**.
As alterações preexistentes foram incluídas a pedido do usuário; os testes desta
entrega cobrem controles e integrações citadas, sem aprovar globalmente cada
área/atividade alterada. A exportação ainda informa ausência de ícone próprio
e aviso do editor no encerramento; a assinatura do APK é verificada separadamente.
