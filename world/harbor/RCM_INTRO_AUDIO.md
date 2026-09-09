# RCM Studios — abertura e primeira passagem de ambiente

## Entrega

Novo Jogo faz um fade de 0,45 s no menu e na música. A apresentação contém
3,7 s de RCM Studios e 2,8 s de Harbor, antes dos dez quadros da CGI existente.
A frase provisória é “Uma nova cidade. Um assunto inacabado.” Não estabelece
uma data ou altera a história. A logo é uma proposta tipográfica vetorial,
com traço revelado, não uma marca final desenhada em bitmap.

Esc/Enter pula para o desembarque, com fade. O fim natural também revela
suavemente a plataforma. Abertura já vista não é repetida no fluxo de resume.
O estado de pausa e o processamento anterior do clima são restaurados;
a chuva do mundo não se sobrepõe à chuva própria da CGI.

## Áudio

- RCM: grave curto e três notas suaves; água começa na apresentação da cidade.
- Porto: água contínua localizada e gaivotas ocasionais de dia.
- Terminal: textura discreta de vozes indistintas, sem falas falsas; escape
  pneumático ligado às visitas/partidas reais do ônibus. Motor existente mantido.
- Garagem: ventilação/compressor e pequenos impactos metálicos ocasionais.
- Cidade: reutiliza o ambiente existente, reduzido à noite e nos interiores.
- Chuva, trem, motores, diálogos e demais efeitos existentes são preservados.
- O gerenciador antigo não sobrepõe seu ambiente/sirenes fictícias em Harbor;
  outros mapas conservam seu comportamento anterior.

Todos os novos sons obedecem ao bus SFX. Quatro beds e um emissor de detalhes,
sem criar fontes por NPC/frame; zonas consultadas 5 vezes/s, ganhos graduais.
Beds inaudíveis param. Buffers PCM determinísticos são cacheados por sessão.
Esta é uma primeira composição procedural, não gravação de campo ou dublagem.
Não foi feita medição de FPS nem avaliação auditiva humana nesta etapa.

## Validação

- `test_harbor_presentation_audio.gd`: exit 0, zero falhas; intro natural, pular apresentação,
  PCM não silencioso/sem saturação, cache, zonas e vozes limitadas.
- `test_harbor_campaign_flow.gd`: campanha, desembarque, garagem e saves.
- `test_menu_flow_integration.gd`: exit 0; fade, Novo Jogo, pausa, volumes e carregar.
- `tests/visual/capture_rcm_intro.gd`: capturas reais 1280 × 720 revisadas.

Há avisos de ObjectDB ao fechar alguns testes e restrições ambientais de
logs/certificados/saves no sandbox. A ausência de vazamentos em sessões longas
não foi comprovada. Não foi executada a suíte completa. Sem commits.

## Revisão pelo jogador

Escolha Novo Jogo e deixe a abertura tocar. Depois visite a plataforma, o cais
e a garagem; compare dia/noite e ajuste SFX nas configurações. Para comparar
a marca isoladamente: `D:/geteco/rcm-studios-signature.wav`.

Imagens: `D:/geteco/rcm-studios-intro.png`, `D:/geteco/rcm-harbor-card.png`,
`D:/geteco/rcm-cgi-transition.png`.
