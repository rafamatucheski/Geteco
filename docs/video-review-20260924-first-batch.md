# Revisão do vídeo — primeiro lote executado

Este é o início da execução do [plano](video-review-20260924-action-plan.md), com três agentes e integração pelo agente principal. Não representa encerramento dos 36 achados. O [prompt do Claude](video-review-20260924-claude-prompt.md) reserva catálogo e bancada de acessórios para uma frente independente.

## Alterações implementadas

| Problema | Alteração | Limite da comprovação |
|---|---|---|
| Moto desaparece no porto, depois save/respawn acessa veículo liberado | Roubo retira propriedade de trânsito; limpeza protege veículo selecionado; remoção invalida referência e trata snapshot por ID | Fluxo causal testado; não representa toda a rota de trânsito do vídeo |
| Corpo progressivamente enterrado após veículos | Restaura deslocamento temporário da apresentação de embarque; cancela continuação de roubo interrompido | Dois ciclos reais de carro, moto, desembarque e interiores exercitados |
| Carro desliza com velocímetro zero no embarque | Zera velocidade horizontal residual e estado de direção ao fixar as âncoras da animação | O voo completo para fora do mapa permanece a reproduzir |
| Piloto antigo permanece na moto | Oculta 29 peças do piloto embutido em cada uma das três motos; Dante assume o assento | Pose estática e transição verificadas; pilotagem dinâmica ainda precisa avaliação |
| Painéis azuis extras junto do carro | Portas substitutas ficam visíveis somente enquanto abertas | Não é reforma dos modelos; portas reais do cupê preservadas |
| Atendimento longe do vendedor | Alvo das duas Ammu-Nation passa ao lado acessível do balcão | Posição/ação verificadas; compra continua na frente existente/Claude |
| Guardas do banco apontam arma fora do alvo | Usa rig nativo de corpo, mãos, arma, muzzle e flash | Mira em três direções testada; reação de atendentes a fogo continua aberta |
| Chuva/luz/câmera chegam atrasadas aos interiores | Atualiza clima na admissão/saída; oculta partículas sob cobertura; posiciona câmera antes de renderizar retorno | Fotos reais de entrada/saída; FPS não certificado |
| Ammu-Nation sai sem zoom correspondente | Estende zoom de saída e aplica a posição inicial no mesmo quadro | Teste cobre helper real e devolução do movimento; outros estabelecimentos permanecem abertos |
| Pistola e “Entrar” aparecem dentro da garagem no primeiro quadro | Sincroniza arma visível, HUD e limpa prompt na transição; morte/prisão também limpam interações | Regras de armas testadas; rotinas de invulnerabilidade dos residentes não alteradas |
| Pés atravessam visualmente o balcão e mancha branca aparece no piloto | Restringe silhueta ao exterior; caixa compartilhada por piloto/veículo atualiza imediatamente quando termina o embarque | Banco validado diante/atrás do balcão; moto limpa desde o primeiro render e contorno exterior preservado |

## Arquivos desta frente

- Veículos: `runtime/ProductionWorld.gd`, `scripts/Driving.gd`, `scripts/Vehicle.gd`, `gameplay/VehicleBoardingPresentation.gd`, `gameplay/VehicleDoorPresentation.gd`; correção defensiva do consumidor de rota em `scripts/RouteActivity.gd`.
- Interiores: `world/places/NativePlace.gd`, `runtime/RobberyActor.gd`, `runtime/BankGuardModel.gd`, `runtime/WeaponShopEntrance.gd`.
- Integração: `runtime/FullSession.gd`, `runtime/Weather.gd`, `ui/ClassicGameplayHUD.gd`.
- Profundidade/silhueta: ajuste pontual em `world/city_look/CityLook.gd` e comentário do shader associado, motivado pelas capturas. Mudanças anteriores de semáforos permanecem preservadas.
- Testes novos: `tests/test_video_vehicle_lifecycle.gd`, `tests/test_video_interior.gd`, `tests/test_video_session_transitions.gd`, `tests/test_video_interior_silhouette.gd`.
- Instrumentação: `tests/measure/video_review_probe.gd`. Capturas: `tests/capture/video_review_interiors.gd`, `tests/capture/video_review_final.gd`, `tests/capture/video_review_silhouette.gd`, `tests/capture/video_review_motorcycle_layers.gd`; evidências em `evidence/video-review-20260924/`.

Esses arquivos contêm alterações anteriores quando já estavam modificados. A lista atribui a esta frente apenas os deltas descritos acima. Não houve limpeza de Git, commit, alteração do save pessoal ou encerramento de processos do usuário. Os dois arquivos reservados ao Claude permanecem fora desta frente.

## Validação

- Interiores: **39 verificações passaram**, abrangendo apoio físico/altura de pés em três salas, alcance do serviço e poses dos dois guardas em três direções.
- Integração final: **31 verificações passaram** na Main real em modo headless: garagem sem armas, arma/HUD atualizados no primeiro quadro, chuva, balcão, zoom real de saída, câmera, morte no banco e resgate com save isolado.
- Veículos: **51 verificações passaram**; a rodada final acrescentou remoção definitiva sem restauração indevida, conservação de outro snapshot, reparenting, carcaça e consumidor de rota.
- Escopo/atualização da silhueta: **17 verificações passaram** — efeito restrito ao exterior, remoção imediata nos interiores, retorno ao sair/desmontar, caixa de autoclusão comum a piloto/veículo e preservação de overlays de outros sistemas. Uma falha temporal foi reproduzida antes: a caixa calculada com Dante oculto no embarque não acompanhava seu reaparecimento/pose final. A correção atualiza apenas quando visibilidade ou transição muda, preservando as varreduras periódicas a 4 Hz. [Reprodução com duas falhas](../evidence/video-review-20260924/interior-silhouette-before-visibility.log) e [resultado final sem falhas](../evidence/video-review-20260924/interior-silhouette-final.log).
- Captura inicial: **20 PNGs**, relatório sem falhas de roteiro, Godot 4.7.2 / Mobile / RTX 4060 Laptop, resolução efetiva 2560×1440. A inspeção identificou e motivou a última correção de HUD da garagem. Essas fotos anteriores à correção foram preservadas.
- Segunda captura: **15 PNGs**, incluindo primeiro quadro da garagem com punho/arma guardada e sem “Entrar”, serviço no balcão e sequência real do zoom de saída. O controle de oclusão do banco identificou uma silhueta branca sobre o tampo; a moto também revelou autoclusão indevida desse efeito. As imagens foram preservadas para comparação e motivaram correção adicional de escopo do efeito.
- Confirmação de oclusão: banco inspecionado [diante](../evidence/video-review-20260924/depth-fixed-bank-occlusion-front.png) e [atrás](../evidence/video-review-20260924/depth-fixed-bank-occlusion-behind.png) do balcão, sem silhueta sobre o tampo. A rodada temporal final produziu **11 PNGs**, sem falhas de roteiro e stderr vazio: moto sem mancha no [primeiro render](../evidence/video-review-20260924/temporal-final-mounted-frame-000.png), [após 100 ms](../evidence/video-review-20260924/temporal-final-mounted-frame-100.png) e [após 300 ms](../evidence/video-review-20260924/temporal-final-mounted-frame-300.png). O [contorno atrás da fachada](../evidence/video-review-20260924/temporal-final-mounted-behind-building.png) permanece útil e o conjunto desaparece [sem o efeito](../evidence/video-review-20260924/temporal-final-mounted-behind-building-without-silhouette.png). Tempos de captura não são métricas de FPS. Diagnóstico, rodadas intermediárias e limites no [relatório visual](../evidence/video-review-20260924/visual-validation.md).

Total: **138 verificações funcionais passaram**. A confirmação visual específica não equivale à aprovação completa dos interiores, direção dinâmica ou performance.

Logs funcionais finais: [veículos](../evidence/video-review-20260924/vehicle-lifecycle-final.log), [interiores](../evidence/video-review-20260924/interior-headless.log), [integração](../evidence/video-review-20260924/session-transitions-final.log). O teste de veículos encerrou sem aviso de objetos/recursos retidos após liberar a referência de GameState usada exclusivamente pelo harness.

Os testes headless emitiram mensagem de acesso ao repositório de certificados do Windows antes do startup. Os testes citados concluíram com código 0 e sem erro de script; isso não constitui medição renderizada nem diagnóstico de rede.

Evidências de apresentação: [banco após veículos](../evidence/video-review-20260924/bank-standing-armed-guards.png), [Ammu-Nation após veículos](../evidence/video-review-20260924/ammunation-counter-approach.png), [moto tomada](../evidence/video-review-20260924/motorcycle-after-theft-dante-mounted.png), [retorno exterior](../evidence/video-review-20260924/harbor_ammunation-exit-first-render.png). O vazio ao redor das salas e a diferença de qualidade do vendedor ainda aparecem; não foram declarados corrigidos.

**Performance pendente.** Um jogo do usuário estava aberto durante esta frente, impedindo comparação isolada. Nenhuma melhoria de FPS foi declarada. O [protocolo](../evidence/video-review-20260924/performance-status.md) explica o probe, cenários, argumentos, métricas e limites; não há baseline congelado equivalente à build do vídeo.

Permanecem no plano: utilidade do porto, reações dos atendentes, letreiros/cifrão, progressão de armas da polícia, migração dos demais acessos, acabamento visual, congelamentos e reprodução do carro fora do mapa. Colisão completa e oclusão de todos os obstáculos não se deduzem do teste de apoio do piso; a aprovação global de interiores continua aberta.
