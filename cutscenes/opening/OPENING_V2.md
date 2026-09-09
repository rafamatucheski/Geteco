# Abertura V2 — cotidiano antes da notícia

Cinco planos novos integrados, cinco de viagem/saída reaproveitados. Os originais
permanecem no disco, mas os primeiros cinco não são mais usados pela montagem.
Preservados 41,5 s e destino `bus_terminal_arrival`; RCM vem antes desse tempo.

## Montagem

1. 0–4 s: café e rotina, ambiente distante discreto, sem chuva/trovão/trilha de ameaça.
2. 4–7,5 s: fotos da carreira policial e com o irmão, uniforme guardado.
3. 7,5–10,5 s: telefone interrompe a manhã.
4. 10,5–17,5 s: notícia de soltura/desaparecimento; vocalizações nos tempos das legendas.
5. 17,5–20,5 s: silêncio e olhar para a foto; mochila sugere decisão.
6. 20,5–24 s: preparação antiga reaproveitada; legenda “NAQUELA NOITE” situa mudança de luz.
7. 24–27,5 s: saída do apartamento.
8. 27,5–32 s: estrada chuvosa; loop de chuva começa aqui, depois do efeito de
   rajada na saída. Sem limpador ouvido de fora do ônibus.
9. 32–37 s: interior do ônibus e limpador.
10. 37–41,5 s: chegada identificada como Harbor, sem a antiga semana de espera arbitrária.

São imagens com movimento de câmera/transições, não animação corporal contínua
nem lip-sync. A história completa da expulsão é guardada para cenas posteriores;
as fotografias estabelecem o passado sem texto expositivo ou spoiler do boss.

## Assets e geração

Ferramenta nativa de geração de imagens (skill imagegen), sem CLI/API externa.
Arquivos finais em `res://cutscenes/opening/frames/`:
- `frame_v2_morning_coffee.png` (gerado na etapa anterior).
- `frame_v2_family_photos.png`
- `frame_v2_phone.png`
- `frame_v2_call.png`
- `frame_v2_decision.png`

Conjunto de prompts usado: stills 16:9 em 3D low-poly facetado/pictórico,
identidade do Dante e cozinha da imagem do café como referência; roupa xadrez
carvão, camisa vinho, cabelo escuro e barba constantes, luz diurna suave,
sem textos incorporados, violência ou pistas da identidade futura do irmão.

Especificações individuais dos prompts:
- Fotos: dois porta-retratos físicos no aparador, Dante jovem fardado e Dante
  sorrindo junto do irmão adulto mais novo; caixa com uniforme dobrado.
- Telefone: close do celular antigo acendendo com ícone de chamada, caneca
  de café e mão hesitando antes de pegar, mantendo madeira/manga/luz.
- Ligação: Dante sentado ouvindo a notícia, expressão vulnerável/preocupada,
  celular ao ouvido e café pela metade, mesma cozinha diurna, sem raiva.
- Decisão: Dante olhando em silêncio a fotografia dos irmãos, telefone na mesa,
  mochila aberta na cadeira; referência adicional do plano das fotografias.

## Verificação

`test_opening_cutscene_runtime.gd` verifica montagem, assets, ausência de cues
de tempestade nos cinco planos diurnos, reprodução natural, áudio e skip.
Resultado headless: exit 0, zero falhas.
`tests/visual/capture_opening_v2.gd` captura reprodução real sem seek/aceleração.
Resultado: exit 0, reprodução completa, cinco capturas; fotos e legenda da
ligação conferidas a 1280 × 720. Capturas em `D:/geteco/opening-v2-shot-XX.png`.
Não equivale à validação da campanha inteira ou a avaliação auditiva humana.

A importação geral apontou erro de parsing em LandmarksV2.tscn, fora deste
trabalho; arquivo não alterado. Também existem restrições ambientais de
logs/certificados/editor settings. Sem commits.
