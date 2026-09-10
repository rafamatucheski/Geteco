# Ferro-velho, rodovia e neve — 2026-09-10

Capturas do mixer Master no `HarborGame.tscn` real, Godot 4.7.2,
Vulkan Forward+, RTX 4060 Laptop. O teste move o jogador entre pontos do mapa;
não representa uma viagem manual completa. Sem medição de desempenho.

`previa_regioes.mp3`: ferro-velho (13 s), mar na rodovia (8,7 s), nevasca (10 s)
e vento abafado no abrigo (5 s), separados por 0,7 s de silêncio.
Volumes preservados; não há normalização individual das capturas.
WAVs individuais e `metrics.json` permitem comparar os níveis originais.

Validação integrada: proximidade do pátio, alternância das batidas, pausa durante
a prensa, silêncio na cidade, ondas na ponte, posição do veículo com jogador
oculto, redução durante diálogo, brisa/nevasca, filtro no abrigo, suspensão
da serra e liberação do barramento ao encerrar a cena. Resultado: zero falhas
na execução headless e na captura com renderização real.

Regressão da ambientação do bairro e rádio: `test_living_city_soundscape.gd`,
zero falhas. Apresentação e áudio: `test_harbor_presentation_audio.gd`, zero falhas
(com aviso preexistente de uma instância ObjectDB no encerramento).
Os logs de inicialização ainda contêm os erros preexistentes
de ações ausentes no InputMap, originados por `GameInput.import_bindings`;
nenhum erro de script dos novos ambientes durante essas execuções.

Fontes e processamento: `audio/regional/README.md` e `SOURCES.json`.
