# Revisão do vídeo — segundo lote, 24/09/2026

Três agentes trabalharam em acessos, porto/sinalização e polícia; o coordenador integrou sessão, áudio, testes e evidências. Este lote implementa correções específicas do [plano de ação](video-review-20260924-action-plan.md). Não encerra os 36 achados nem certifica performance ou todos os interiores.

## Resultado implementado

| Frente | Comportamento atual | Limite do escopo |
|---|---|---|
| Banco North Pier, Maciota e Garagem do Chefe | Entrada ao caminhar para dentro do acesso, zoom de entrada e saída, retorno e reentrada sem E de passagem. Movimento lateral e simples permanência perto da porta não entram. | Três acessos a três interiores existentes; demais acessos não migrados neste lote. |
| Porta do banco | Folha articulada com colisão acompanha a abertura por proximidade; batentes e recesso central deixam espaço para a travessia. | Durante investigação, a folha pode abrir, mas a admissão é recusada uma vez, antes do zoom. |
| Disponibilidade e interrupções | Horário 1h–5h do Chefe preservado; morte, prisão e modal cancelam a entrada pendente e devolvem controle/câmera. É necessário recuar antes de tentar novamente. | Portões já abertos das garagens e transferência veicular existente preservados. |
| Sinalização | Letreiro rosa North Pier substituído por `$` dourado; letreiro decorativo da Garagem do Chefe removido. | Nomes funcionais no catálogo permanecem. Nenhuma luz adicionada. |
| Portaria | Conversa chega ao menu real; pagamento de R$100 recusa saldo insuficiente, não cobra duas vezes e salva saldo/autorização juntos. | Recupera o uso do conteúdo existente; não cria novas missões ou empregos. |
| Visita ao porto | Autorização sobrevive à restauração e ao percurso porão → convés → passarela → cais. Sair para a rua encerra a visita; invasão sem autorização continua sendo crime. | Perímetro segue casco, passarela e píeres; mar aberto não foi incluído. |
| Polícia | Patrulha comum usa pistola; interceptor usa SMG; equipes táticas usam M4A1. A equipe conserva sua categoria ao desembarcar, inclusive após roubo da viatura ou mudança nas estrelas. | São três famílias de armas, não seis armas diferentes. Áudio de disparo acompanha a arma equipada. |

Maciota e mecânico continuam protegidos; a garagem guarda e bloqueia armas, mantém inventário e libera uso na saída. Marcadores de conversa/objetivo foram preservados, removendo somente a indicação de E para passagem automática.

## Arquivos desta frente

- Acessos: `runtime/WeaponShopEntrance.gd`, `runtime/FullSession.gd`, `world/urban_detail/UrbanLandmarkFrontage3D.gd` e ajuste pontual de grupo/estado inicial em `world/regions/NativeRegion.gd`.
- Porto e sinais: `gameplay/urban_v1/HarborPortSecurity.gd`, `gameplay/urban_v1/UrbanOperations.gd`, `world/city_look/BuildingLife.gd`, `world/urban_detail/PortBossGarageExterior3D.gd`.
- Polícia: `gameplay/dispatch/DispatchRules.gd`, uma chamada de spawn em `gameplay/dispatch/DispatchController.gd` e seleção do áudio em `gameplay/Gameplay.gd`.
- Testes novos: `tests/test_video_phase2_access.gd`, `tests/test_video_phase2_port.gd`, `tests/test_video_phase2_police_loadouts.gd` e quatro scripts `tests/capture/video_phase2_*.gd`.
- Adaptadores de testes existentes passaram a caminhar pelos novos acessos e aguardar o término do zoom de saída: `tests/test_harbor_establishments.gd`, `tests/test_harbor_gameplay_acceptance.gd`, `tests/test_video_session_transitions.gd`. O segundo recebeu verificação de parser; sua suíte ampla não foi executada nesta rodada.

Catálogo e bancada continuaram sob responsabilidade do Claude. Não editamos `runtime/HarborAmmunationCatalog.gd` nem `runtime/HarborWeaponWorkbench.gd`. Alterações locais de outras sessões foram preservadas, sem limpeza, descarte ou commit.

## Validação executada

Godot 4.7.2. Testes de sessão usam Main real e `--no-save --skip-arrival`, sem escrever progresso pessoal. Capturas: Vulkan Mobile, RTX 4060 Laptop, 2560×1440. Resultados abaixo são funcionais e visuais específicos, não medições de FPS.

| Verificação | Resultado final | Evidência |
|---|---:|---|
| Três novos acessos: porta física, caminhada, zoom, retorno, reentrada, horário, investigação, cancelamentos e garagem protegida | 76 funcionais + 16 PNG = 92/92 | [Log](../evidence/video-review-phase2-20260924/phase2-access-render-final.log) |
| Portaria, saldo, persistência, saves antigos/inválidos, cancela e percurso do navio | 52/52 | [Log](../evidence/video-review-phase2-20260924/phase2-port-test-3.log) |
| Portaria renderizada e quatro imagens | 10/10, incluindo capturas | [Log](../evidence/video-review-phase2-20260924/port.stdout.log) |
| Polícia: desembarque real, arma/modelo, projétil, muzzle, áudio, munição, recarga e bloqueio de armas | 93 verificações / 8 cenários | [Log](../evidence/video-review-20260924/phase2-police-loadouts.log) |
| Integração de transições, HUD, chuva, morte e restrição de armas | 31/31 | [Log](../evidence/video-review-phase2-20260924/phase2-session-transitions-final.log) |
| Recompensas da garagem | 47/47 | [Log](../evidence/video-review-phase2-20260924/phase2-garage-rewards-final.log) |
| Restauração do motorista na garagem | 26/26 | [Log](../evidence/video-review-phase2-20260924/phase2-garage-driver-restore.log) |
| Transferência física de veículos na garagem | 11/11 | [Log](../evidence/video-review-phase2-20260924/phase2-garage-vehicle-transfer.log) |
| Integração dos estabelecimentos, incluindo interface do Claude, roupas, banco e Maciota | 77/77 | [Log](../evidence/video-review-phase2-20260924/phase2-claude-integration.log) |
| Catálogo/bancada do Claude renderizados | 25 funcionais + 4 PNG = 29/29 | [Log](../evidence/video-review-phase2-20260924/claude-ui.engine.log) |

Todos esses processos terminaram com código 0. A verificação de diferenças não encontrou erros de whitespace; houve somente avisos de conversão CRLF.

**Ressalvas de encerramento:** a saída de dois testes antigos da garagem registrou retenções de objetos ao encerrar: recompensas, 2 ObjectDB; transferência, 14 ObjectDB e 4 recursos. Esses avisos não são prova de vazamento durante a partida, mas sua causa não foi isolada e não há certificação de ausência de vazamentos. Alguns processos headless também registraram falha de leitura do repositório de certificados do Windows, sem uso de rede ou falha funcional associada.

### Integração com o Claude e trabalho concorrente

As quatro telas foram inspecionadas: posse/preço, saldo insuficiente, peça selecionada versus instalada e prévia sem acessório. Os rótulos estavam legíveis e sem cortes na resolução capturada. A falha anterior de entrada na loja de roupas, registrada no [relatório do Claude](claude-arsenal-ui-20260924.md), não se repetiu na integração de 77 verificações, após os adaptadores aguardarem o zoom terminar.

O Claude continuou a ampliar a bancada depois das imagens das 20h17, alterando `HarborWeaponWorkbench.gd` às 20h18 e acrescentando testes de peças. Reexecutamos o contrato da interface sobre essa revisão: **25/25 funcionais**, código 0, em [log posterior](C:/Users/rafae/.codex/visualizations/2026/09/24/01a0d558-4410-7471-98cb-1032e2e21647/phase2-claude-ui-latest.log). Essa execução também registrou 4 ObjectDB e 1 recurso retidos ao encerrar. As imagens abaixo pertencem à revisão anterior à ampliação; não certificam o layout ou o balanceamento das novas peças. Não reescrevemos o relatório histórico nem o código do Claude.

## Evidências visuais

| Cena | Antes / controle | Depois / execução real |
|---|---|---|
| Banco e cifrão | [Fachada anterior](../evidence/video-review-phase2-20260924/before-harbor_bank.png) | [Fachada atual](../evidence/video-review-phase2-20260924/after-harbor_bank.png) |
| Garagem do Chefe | [Letreiro anterior](../evidence/video-review-phase2-20260924/before-port_boss_garage.png) | [Letreiro removido](../evidence/video-review-phase2-20260924/after-port_boss_garage.png) |
| Porta física do banco | [Fechada](../evidence/video-review-phase2-20260924/phase2-access-bank-door-closed.png) | [Entrada com zoom](../evidence/video-review-phase2-20260924/phase2-access-harbor_bank-entry-zoom.png), [saída com zoom](../evidence/video-review-phase2-20260924/phase2-access-harbor_bank-exit-zoom.png) |
| Maciota | [Aproximação](../evidence/video-review-phase2-20260924/phase2-access-maciota-approach.png) | [Interior e marcador funcional](../evidence/video-review-phase2-20260924/phase2-access-maciota-inside.png), [retorno](../evidence/video-review-phase2-20260924/phase2-access-maciota-returned.png) |
| Chefe em horário de funcionamento | [Aproximação](../evidence/video-review-phase2-20260924/phase2-access-port_boss_garage-approach.png) | [Interior](../evidence/video-review-phase2-20260924/phase2-access-port_boss_garage-inside.png), [retorno](../evidence/video-review-phase2-20260924/phase2-access-port_boss_garage-returned.png) |
| Portaria | [Guarda e cancela fechada](../evidence/video-review-phase2-20260924/after-port-guard-before-payment.png) | [Pagamento](../evidence/video-review-phase2-20260924/after-port-payment-menu.png), [cancela aberta](../evidence/video-review-phase2-20260924/after-port-gate-authorized.png), [visita sem estrelas](../evidence/video-review-phase2-20260924/after-port-authorized-visit.png) |
| Polícia | Equipes reais posicionadas para inspeção, com IA/viatura congeladas | [Pistola, SMG e M4A1](../evidence/video-review-20260924/phase2-police-lineup-aiming.png) |
| Catálogo do Claude, antes da ampliação posterior | [Arma possuída](../evidence/claude-arsenal-ui-20260924/catalogo-pistola-possuida.png) | [Saldo insuficiente](../evidence/claude-arsenal-ui-20260924/catalogo-saldo-insuficiente.png) |
| Bancada do Claude, antes da ampliação posterior | [Silenciador selecionado](../evidence/claude-arsenal-ui-20260924/bancada-previa-silenciador-saldo-curto.png) | [Original selecionado](../evidence/claude-arsenal-ui-20260924/bancada-previa-original.png) |

As 16 imagens de acesso, quatro da portaria e cinco da polícia foram inspecionadas pelos responsáveis; o coordenador conferiu amostras desses fluxos e as quatro telas da interface. A iluminação noturna do Chefe permanece escura. Nas imagens do teste de acesso, o aviso de horário pode persistir porque o teste avança de meio-dia para 2h logo após uma recusa; estrelas nas capturas que se posicionam diretamente no porto decorrem de não pagar a portaria. A captura da visita autorizada percorre o pagamento e não apresenta essa infração.

## Diagnósticos que orientaram os testes

- Horário do Chefe: alterar só o relógio salvo não basta, pois Weather atualiza esse valor; o teste passou a sincronizar ambos. A recusa fora do horário estava correta.
- A primeira captura dos acessos passou nos 76 casos funcionais, mas não conseguiu gravar PNG na pasta de evidências pelo sandbox. O teste recebeu saída configurável, e a execução final gravou e verificou as 16 imagens.
- O teste inicial da passarela andava contra um trabalhador. A investigação encontrou faixas laterais transitáveis; a rota final caminha pela lateral, mantendo o NPC e todas as colisões. Nenhuma geometria foi removida para fazer o teste passar.
- O teste antigo de saída do banco ainda exigia E. Foi atualizado para a passagem automática solicitada, mantendo a verificação de que morte elimina prompts funcionais obsoletos.

## Pendências reais

1. **Performance:** falta comparar frame time antes/depois nas cenas afetadas. Editor PID 76560 e jogo PID 86396 permaneceram ativos e foram preservados. Todos os processos desta frente terminaram. Capturas e testes headless não aprovam FPS.
2. **Cobertura de interiores:** há 6 acessos automáticos para 6 interiores; o inventário tem 32 acessos físicos e 30 interiores distintos. Restam 26 acessos/24 interiores fora desta migração, incluindo fluxos especiais que precisam de desenho próprio. Nenhum interior recebeu nova certificação completa neste lote: falta cobertura integral de colisão, oclusão e performance.
3. **Porto:** acesso, pagamento e persistência foram reparados; desenho de atividades, reações dos trabalhadores e revisão visual/jogável do conjunto continuam abertos. O lote não comprova coleta integral de todas as recompensas existentes.
4. **Ocorrências anteriores:** voo completo do carro, travamentos da rota moto/porto/explosões, navegação/minimapa, iluminação/void, reação de atendentes e geometria da prévia da pistola não estão encerrados por estes testes.
5. **Interface em evolução:** contraste foi inspecionado, sem medição formal, em uma resolução. Controle, outras resoluções e a ampliação posterior das peças pelo Claude ainda exigem validação própria.

Contagem e critérios de interiores registrados no [checklist](interior-standard-checklist.md). O [primeiro lote](video-review-20260924-first-batch.md) mantém suas evidências e limitações históricas.
