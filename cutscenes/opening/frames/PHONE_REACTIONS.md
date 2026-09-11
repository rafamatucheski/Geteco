# Reações durante a ligação

Três imagens novas, geradas pela ferramenta nativa `image_gen` a partir de `frame_v2_call.png` e `frame_expanded_call_close.png`. Prompts completos em `phone_emotions_prompts.json`.

- `frame_phone_surprise.png`: olhos e sobrancelhas erguidos, surpresa com a soltura; entra aos 26,05 s, durante “saiu da prisão”.
- `frame_phone_sadness.png`: olhar baixo e ombros caídos; entra aos 32,8 s, durante “não atende o telefone”.
- `frame_phone_reply.png`: boca em fala e gesto de pergunta; entra aos 36 s, junto de “Quem tá falando?”, e termina aos 37,094 s. Depois retorna à escuta, antes de a linha cair.

A montagem continua com 86 segundos, agora com 28 marcações de plano e 16 imagens distintas. Mantidos os cenários, personagem, estilo pictórico/facetado e áudio PT-BR. As novas imagens foram copiadas para esta pasta; originais e referências preservados.

Prévia completa: `../v3/review/opening_emotions.mp4`. O teste `tests/test_opening_stills.gd` verifica as imagens nos momentos de surpresa, tristeza e resposta e o retorno à escuta após a fala, além de carregamento, continuidade e idiomas.
