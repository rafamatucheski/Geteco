# Avião da montanha de gelo — 07/10/2026

Reforma de um lugar existente, com dois agentes: modelagem e áudio. Nenhum lugar ou recompensa novo. A fuselagem recebeu perfil facetado, nariz afilado, asas trapezoidais danificadas, naceles, hélices, cauda T, costuras, roletes e uma insígnia gráfica dos Cobras, sem textos decorativos ou novas luzes.

Perto do avião, o teto e a lateral voltada à câmera são recortados. A câmera sobe suavemente para aproximadamente 70°: a primeira rodada renderizada demonstrou que a asa ainda escondia Dante na diagonal original. A parede oposta conserva o volume da fuselagem. Saída, ausência de alvo, câmera bloqueada e descarregamento restauram a apresentação exterior; a câmera comum conserva seus contratos.

Baú e SMG usam o toque original da V1 como sinal de proximidade, com volume por distância do jogador, limite de 9 m e intervalo de 4 s. Os sons de dinheiro/arma continuam no evento real de coleta. O áudio para ao esconder/coletar/descarregar, acompanha a troca de alvo e obedece ao canal SFX. Foi corrigido o sólido invisível que permanecia após a coleta do baú. Os recibos também são aplicados em `_ready`, antes de admitir o jogador: a carga fria inicialmente reproduziu um fallback até o spawn da montanha porque o baú já recolhido voltava a bloquear o ponto salvo. As recompensas continuam R$ 1.800 e SMG com 20 munições, com os mesmos identificadores persistentes.

## Verificações

Godot **4.7.2 .NET**, Harbor.csproj compilado com zero erros/avisos; Main real, roteador C# ativo, checkpoints exclusivos e `--no-save`. Saves pessoais preservados.

| Verificação | Resultado | Evidência |
| --- | --- | --- |
| Câmera, rampa, carga, cockpit, saída/reentrada, jogador/NPC e sólidos laterais | 52/52 | [Log final](../../evidence/cargo-plane-sightline-final.log), [checks e máscaras](../../evidence/cargo-plane-final-97540/checks.json) |
| Coleta física, reprodução de áudio, volume livre do baú e save/recibos sem duplicação | 30/30 após a correção de admissão | [Log final](../../evidence/cargo-plane-pickups-final.log) |
| Carga fria no espaço do baú coletado: posição/deck, itens ocultos e recompensas preservadas | PASS | [Log](../../evidence/cargo-plane-restore-fixed.log), [resultado](../../evidence/cargo-plane-restore-107096/result.json) |
| Proximidade, troca de alvo, ocultação e liberação da voz | 20/20 | [Log](../../evidence/cargo-plane-proximity-unit.log) |
| Regressão dos sons/recompensas | 18 verificações, zero falhas | [Log](../../evidence/cargo-plane-reward-regression.log) |
| Contratos existentes da câmera | PASS | [Log](../../evidence/cargo-plane-camera-regression.log) |

A profundidade usa ator real, material diagnóstico, oito direções na carga, quatro no cockpit e duas vistas de NPC. Cada vista tem controle positivo com o modelo oculto e controle negativo com o visual do ator oculto. A verificação física identifica a parede e sua normal, sem considerar qualquer colisão como aprovação. A rodada anterior teve uma falha real de oclusão pela asa e duas falhas de fixture: desabilitar process_mode removia Dante do espaço físico. Foram corrigidas a câmera e a pausa do teste, sem reduzir a exigência de visibilidade ou remover assertions. Logs anteriores foram preservados.

## Frame time renderizado

Mesmo Main, RTX 4060 Laptop, renderer Mobile/Vulkan, 1280×720, MSAA 2x, VSync ativo e limite efetivo de **144 FPS** da preferência existente. Seed 610207, horário .45, clima limpo, 40 pedestres/4 carros e percurso local de 69,80 m com órbita. Cinco segundos de aquecimento, depois 30 segundos por versão. Meta provisória: 60 FPS/16,67 ms; aumento superior a 5% em p95/p99 exigiria confirmação finita.

| Métrica | Antes | Depois |
| --- | ---: | ---: |
| Quadros / duração | 4.309 / 30,0065 s | 4.307 / 30,0048 s |
| FPS médio por quadros/tempo | 143,60 | 143,54 |
| p50 | 6,974 ms | 6,972 ms |
| p95 | 10,791 ms | 10,450 ms |
| p99 | 13,684 ms | 13,374 ms |
| Máximo | 34,828 ms | 36,376 ms |
| Quadros >33,3 / >66,7 ms | 1 / 0 | 1 / 0 |

p95 -3,16%; p99 -2,27%. Sem regressão observada no cenário medido; não foi necessário repetir o benchmark. O aquecimento final teve p95 9,560 ms, p99 12,483 ms e máximo 25,064 ms. [Amostras antes](../../evidence/cargo-plane-before-153176/report.json) e [depois](../../evidence/cargo-plane-after-124360/report.json) preservam intervalos brutos e monitores CPU/física; tempo GPU não foi instrumentado separadamente.

As dependências comuns verificadas (NativeRegion, FullSession, ProductionWorld, project.godot e Harbor.dll) permaneceram iguais entre as versões; os arquivos da intervenção foram alterados intencionalmente. Havia processos de outras sessões durante a baseline, sem encerrá-los; nas inspeções seguintes eram testes headless, e não havia outro Godot ativo ao iniciar a amostra final. Isso limita a conclusão a este comparativo local, sem certificação global de isolamento ou FPS. O fingerprint original do arquivo CargoPlaneNative tinha um prefixo res:// duplicado; a instrumentação foi corrigida para próximas execuções, sem reescrever a baseline.

A reconciliação inicial dos recibos foi acrescentada após o benchmark e executa uma vez na construção, sem nova atualização por frame. A evidência de regime estável acima é reutilizada para modelagem, câmera e áudio; o custo isolado dessa preparação adicional não foi instrumentado. A admissão final foi exercitada por carregamento frio renderizado no ponto do baú.

As fotografias têm readback da GPU e enquadramentos de revisão; seus contadores de FPS/pico não pertencem à janela de medição. Não foram certificadas outras áreas, noite/climas adicionais ou travamentos do percurso completo cidade→lago. A primeira visita começa por checkpoint; o aquecimento medido não substitui essa viagem. O áudio foi verificado por amostra original, sinal não vazio, rota SFX e reprodução/ciclo de vida reais; não houve avaliação auditiva humana.

## Fotografias reais

- Antes: [aproximação](../../evidence/cargo-plane-before-153176/approach.png), [lateral](../../evidence/cargo-plane-before-153176/starboard.png).
- Depois: [avião fechado](../../evidence/cargo-plane-after-124360/airframe-closed.png), [interior com itens](../../evidence/cargo-plane-after-124360/cargo-open.png), [vista lateral elevada](../../evidence/cargo-plane-final-97540/starboard.png).

Visual, circulação/colisão, profundidade, coleta/persistência e frame time aprovados somente nos casos descritos. Cobertura adicional do jogo permanece fora desta reforma local.
