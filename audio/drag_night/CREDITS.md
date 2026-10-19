# Noite de Acerto — trilha original do Geteco

Composição instrumental criada para este encontro em 18/10/2026: 104 BPM, 32 compassos de 4/4, centro tonal em ré menor. A sequência harmônica alterna acordes abertos, o motivo de teclas deixa espaço entre frases e a seção central reduz a bateria. Baixo, bumbo, caixa, chimbal, percussão e teclas foram sintetizados para esta composição, sem samples externos ou reprodução de uma obra de referência.

Fonte reproduzível: [`tools/audio/build_drag_night_score.py`](../../tools/audio/build_drag_night_score.py). O script usa seed fixa, renderiza offline em 44,1 kHz e produz dois stems de duração idêntica:

- `patio.ogg`: harmonia e motivo de teclas.
- `pulso.ogg`: baixo e bateria.

O arranjo soma as caudas no começo do loop para preservar a continuidade. Ambos os players iniciam no mesmo relógio; o jogo só mistura os ganhos de arquivos Ogg nativos. Não existe síntese musical por frame, alteração do volume global ou envio para serviços externos. O arquivo `composition.json` registra os hashes e medições dos arquivos decodificados. O preview combinado é salvo em `artifacts/rachas-continuation-20261018/noite_de_acerto_preview.ogg`, fora dos assets de runtime.

Ambiente, ferramentas, público, motores e falas continuam usando os bancos existentes do projeto com suas próprias procedências. A trilha inédita não é apresentada como nova gravação de atores.
