# Tipografia do Geteco

Família principal: **Barlow Semi Condensed**, de Jeremy Tribby / The Barlow Project Authors.

- Regular: textos, HUD, legendas e texto procedural do mundo.
- Medium: botões, títulos curtos e números de destaque.
- SemiBold: ênfase dentro de textos ricos.
- Medium Italic: nome de veículo e ênfases pontuais.

Os arquivos estão incluídos no projeto; não dependem das fontes instaladas no computador.

Fonte dos binários: https://github.com/google/fonts/tree/main/ofl/barlowsemicondensed

Projeto original: https://github.com/jpt/barlow

Licença: SIL Open Font License 1.1, em `OFL.txt` nesta pasta.

A base fica em `ui/ProjectTheme.tres`; `ui/ProjectTypography.gd` fornece também a fonte para desenhos procedurais. Prefira herdar o tema a criar fontes locais. Preserve o tamanho de texto configurável e evite contornos grossos ou pesos pesados em blocos longos.
