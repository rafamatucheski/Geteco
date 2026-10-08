# Ônibus regional — 07/10/2026

Rodoviária de Harbor, Estação de Gelo na vila da serra e Cobre no deserto compartilham um menu de destinos. **Embarcar** acompanha o ônibus pelas estradas; **Viagem rápida** conclui a transferência com admissão física no destino. Durante o percurso, a mesma interface usada pelo trem oferece vista interna, vista externa e conclusão rápida. O acesso antigo da rodoviária e o da serra também abrem esse menu.

O deserto exige a conclusão final da campanha da cidade 1. A montanha permanece disponível antes dessa conclusão. As seis viagens dirigidas usam o grafo das ruas, a ponte norte autorizada e o acesso independente da montanha. A ferrovia e a linha urbana 510 continuam serviços separados.

Cobre recebeu uma parada exterior com cobertura, banco sólido, placa com o nome e piso junto ao acostamento. Sua estrutura acompanha os chunks do deserto, preserva o corredor de desembarque e reserva o espaço contra pedras/vegetação procedural. Não acrescenta um interior fechado nem fontes de luz; usa os materiais e a iluminação viária existentes.

## Passageiros e condução

O ônibus tem cabine 3D, seis passageiros sentados, motorista e o próprio Dante com aparência/inventário preservados. Os civis sentados não executam física ou animação individual por frame. Dante permanece sentado durante o percurso; não é um interior para caminhar livremente. A câmera interna olha pelo corredor e para a estrada; a externa acompanha o mesmo veículo.

O motorista reutiliza `Vehicle.gd`, com colisão varrida, frenagem, semáforos, reservas de cruzamento e identificação das faixas. A velocidade urbana nativa é mantida: congestionamentos podem atrasar a chegada e o tempo mostrado é estimado. Após espera prolongada, a interface informa a opção de concluir a viagem rapidamente. Os faróis e o motor usam os sistemas compartilhados do jogo.

O embarque não é permitido durante combate, procura, atividades incompatíveis ou outras transições. Armas ficam guardadas, disparo e troca ficam bloqueados e o save aguarda o desembarque. A admissão verifica apoio e cápsula em pontos próximos da parada; se o destino estiver ocupado, conserva a viagem e permite tentar novamente. Morte/resgate libera posse de câmera, pose, colisão e veículo pelo cancelamento da sessão.

## Evidência disponível

- A reprodução anterior mostrou os pontos de Harbor e Cobre sem ação; na serra havia apenas a viagem antiga para o porto. Os três pontos tinham apoio físico. Log: `evidence/regional-baseline.log`.
- Viagens rápidas nas seis direções, campanha, procura, menu, controles, cápsula e save isolado: **50 verificações aprovadas** em `evidence/regional-quick.log`. Não é prova de percurso físico completo.
- Grafo C# das seis rotas, passageiros, faróis dia/noite, elegibilidade para o áudio compartilhado e casco contra parede: **20 verificações aprovadas** em `evidence/biarticulated/task-20261007-coach-network-final.log`.
- Geometria estática das seis rotas: **3.270 amostras, zero obstáculos ou falhas de apoio** em `evidence/regional-coach-clearance-49216-4847846/clearance.json`. O teste separa geometria de tráfego e não substitui o motorista real. A primeira fixture media apoio pela altura interpolada da curva e acusou o chão da rampa; a versão final mede o piso físico com raios.

- Sessão real renderizada noturna: **79/79**, com seis direções rápidas, trechos rodoviários em Harbor e no deserto, dois modos de câmera, passageiros, pausa, desembarque ocupado com nova tentativa, cancelamento durante fade, destruição do ônibus e resgate produtivo. [Log](../evidence/regional-night-short.log), [cabine em movimento no deserto](../evidence/regional-session-166048-5932583/desert-harbor-interior-moving.png), [exterior](../evidence/regional-session-166048-5932583/harbor-mountain-exterior.png). Esse ensaio curto conclui os trajetos por **Pular viagem**; não comprova viagem física completa.
- Regressões da interface/profundidade do trem: **26/26 + 18/18**. Segurança da garagem após ampliar o bloqueio de armas ao ônibus: **37/37**, com Main/.NET headless e APPDATA isolado. [Resultado](../evidence/regional-maciota-safety/maciota-transition-safety.json).
- Primeiro percurso completo: deserto → Harbor chegou pelo motorista real; Harbor → gelo parou antes da vila. [Log preservado](../evidence/regional-full.log). Três falhas registradas representam a mesma parada, repetida por uma fixture que não excluía o fade do resgate rápido; o harness foi corrigido.
- Correção da aproximação do gelo: controles próximos no encontro `mountain_pass → mountain_track_5` comprimiam o arco entre faixas, fazendo a curva voltar **0,846 m** para norte. A geometria local agora reúne esses controles sem alterar as ruas, os sentidos, os vértices de cruzamento ou o motorista global. **26/26** verificações de rede/docagem, mais aproximação real sem oscilação. [Rede final](../evidence/biarticulated/task-20261007-coach-network-final2.log).
- Repetição completa Harbor → gelo pelo motorista real: **73/73**, incluindo portas de admissão, pausa, save, viagem rápida de retorno, cancelamento e resgate. [Log final](../evidence/regional-ice-final.log), [chegada](../evidence/regional-session-43528-5918964/arrival-mountain.png). Rodou acelerado a 4× mantendo passos físicos de 1/60 s; é teste funcional renderizado, **não benchmark**. As outras quatro direções têm rede, varredura e viagem rápida verificadas; não se afirma que todas receberam uma condução completa. O encerramento desse harness registrou RIDs remanescentes; a rotina final agora libera Main explicitamente antes de sair.

Performance ainda **inconclusiva**: não existe comparação isolada antes/depois do ônibus regional. A coleta junto ao ensaio noturno misturava uma pausa intencional da fixture com o tempo entre amostras (pico artificial de aproximadamente 300 ms); esses dados não são usados como benchmark. O coletor agora inicia a janela depois da pausa e das fotos. Execuções concorrentes e alterações do jogo também impediram uma referência estável. Fotos conferem apresentação, mas não certificam ausência de flickering.

## Parada de Cobre

`test_regional_coach_stop.gd`: **10/10** na Main renderizada, incluindo cápsula livre na chegada, caminhada até o banco com colisão real, apoio no piso, viagem rápida para Harbor, retorno e exatamente uma estrutura após a recarga do chunk. [Log](../evidence/cobre-stop-final.log), [foto da parada](../evidence/cobre-stop-final-169388-5943467/station.png), [colisão no banco](../evidence/cobre-stop-final-169388-5943467/bench-collision.png). Piso, colunas, cobertura e banco têm sólidos; o piso fica praticamente nivelado com a areia. A silhueta exterior normal mantém Dante localizável quando a cobertura o oculta.

Comparação local controlada, **30 s por amostra após 8 s de aquecimento**, Godot 4.7.2 .NET, Mobile, RTX 4060 Laptop, 1280×720, dia, mesma câmera/checkpoint/hash do mapa. O controle omite somente a nova estrutura no harness; não é uma versão histórica completa do jogo. Sem VSync/limitador apenas durante a medição; caminhada e transferências usam configuração normal de 144 FPS/VSync. Verificações de processos nos limites das execuções mostraram apenas o editor e o teste; não houve monitoramento contínuo de todos os processos.

| Medida | Controle sem parada | Com parada |
| --- | ---: | ---: |
| FPS médio | 460,33 | 460,35 |
| p50 / p95 / p99 (ms) | 1,845 / 3,953 / 5,457 | 1,855 / 3,943 / 5,401 |
| Máximo (ms) | 44,512 | 41,419 |
| Frames >33,3 / >66,7 ms | 2 / 0 | 2 / 0 |

[Controle bruto](../evidence/cobre-stop-before-148232-6018848/metrics.json), [resultado bruto](../evidence/cobre-stop-final-169388-5943467/metrics.json). Sem regressão relevante observada nessa vista da parada; os picos permanecem registrados. Isso não certifica ônibus em movimento, todas as condições de luz, nem ausência de flickering em sequência contínua. A primeira invocação da fixture teve dois erros de inferência de tipo, corrigidos antes das duas medições.

Implementação: `runtime/regional/RegionalCoachTransit.gd`, `RegionalCoachRoute.gd` e `RegionalCoach.gd`; integração em `FullSession`, foco de streaming em `ProductionWorld`, interface compartilhada em `ui/railway/RailwayUI.gd` e paradas no mapa.
