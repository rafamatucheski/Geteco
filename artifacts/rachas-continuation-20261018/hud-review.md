# Revisão dirigida da HUD — 18/10/2026

O runner `capture_compact_drag_hud.gd` usa a HUD, o drivetrain e o formatador de objetivo reais, sobre fundo claro isolado. Cobertura: 960×540 e 1280×720, teclado/controle, Lívia com texto longo, Rauhz em corrida e no alinhamento. Não é captura de Main nem teste de performance ou dispositivo físico.

**Geometria e texto do objetivo aprovados nesta cobertura.** A matriz de 12 capturas terminou com código 0 e sem falhas funcionais. O arco e o painel ficam separados por aproximadamente 10,5 px em 960×540 e 14 px em 1280×720. Marcha, velocidade e aviso de troca permanecem legíveis. O objetivo mais longo de Lívia ocupa 311 dos 496 px lógicos disponíveis; os textos de Rauhz ocupam 235–243 px, sem corte. Teclado e controle mostram as legendas correspondentes.

**Contraste do rodapé corrigido e confirmado no caso afetado.** Fonte 16 com contorno 1 deixou o texto branco fraco sobre fundo claro. O coordenador alterou somente o contorno para 2; o runner foi filtrado com `--hint-review` e gerou apenas duas novas imagens, teclado e controle, em 960×540. Ambas terminaram sem falhas, código 0. A inspeção confirma instruções distinguíveis no fundo claro, com separação entre palavras e sem ampliar ou sobrepor os instrumentos. NITRO/SHIFT em 12 também permanecem legíveis. A pendência local está encerrada nessa cobertura; não se afirma legibilidade universal ou validação em movimento.

- [Confirmação final 960×540 — teclado](../../evidence/drag-hud-compact-173328-18436770/960x540-livia_long_status-keyboard.png)
- [Confirmação final 960×540 — controle](../../evidence/drag-hud-compact-173328-18436770/960x540-livia_long_status-gamepad.png)
- [Log da confirmação final, duas imagens](../../output/drag-compact-hud-hints-20261018.log)
- [Matriz preservada, 12 imagens](../../evidence/drag-hud-compact-25596-13240693/capture.json)
- [Log da matriz](../../output/drag-compact-hud-final-20261018.log)
- [Evidência anterior preservada](../../evidence/drag-hud-compact-152344-12985955/capture.json)

As imagens foram inspecionadas em resolução original. A execução final foi autorizada em paralelo a outra verificação funcional; nenhuma conclusão de FPS, estabilidade temporal ou condução é derivada deste runner. Nenhum arquivo de produção foi alterado por esta revisão.
