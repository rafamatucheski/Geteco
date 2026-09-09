# Revisão de estabilidade, trânsito e polícia — 08/09/2026

## Entrega Astra

- Corrigido amortecimento lateral negativo: o coeficiente legado de drift acima de 1 aumentava a velocidade. Agora a aderência usa amortecimento exponencial positivo, inclusive na chuva e no freio de mão.
- Corpos dos veículos são top-down, sem herdar velocidade de plataformas móveis. Movimento inválido ou excepcionalmente grande é rejeitado; impactos consomem a componente de velocidade contra o obstáculo, evitando repetição de batidas em contato.
- Máscaras físicas incluem outros carros. Seguidores das faixas fazem varredura física antes de avançar e param diante de veículos estacionados.
- Nitro desativado nos controladores, upgrades, atribuição legada de missão e menu de customização. Turbo mecânico e áudio exclusivo da Monaliza permanecem.
- IDs antigos do catálogo resolvem para a frota 3D disponível, preservando IDs de missões e saves. Alguns modelos são compartilhados entre variantes; isto não é uma modelagem exclusiva nova para cada ID.
- Faróis do trânsito são projetados nas lentes dos modelos, com dois feixes menores. Frota de emergência também recebeu modelos 3D e faróis duplos.
- Atualização visual duplicada removida; carros fora da câmera não redesenham. Carros parados sem mudança de aparência não redesenham continuamente. Agrupamento por material reduz MeshInstances sem remover geometria: Summit 85→30, Union 80→31, Boxrunner 93→29, Coupe 173→36.
- Guardrails laterais acrescentados às curvas, mantendo a junção e o retorno livres. Auditoria: 8 faixas, 2.346 amostras, nenhum bloqueio estático nos corredores de carro e caminhão. Trânsito atravessa a costura e retorna com a mesma instância.
- Prisão exige aviso, visão livre, proximidade e Dante a pé parado. Abordagem não pode prender remotamente por proximidade à viatura. Policiais desembarcam, usam portas abertas como cobertura física e reembarcam para retomar perseguição.
- Pátio externo da delegacia recebeu marcação de vagas e corredor de saída, usando o acesso real de despacho existente. Não foram adicionadas viaturas decorativas para simular a frota.
- Save manual, rápido e automático bloqueados com estrelas. Carregamento legado limpa a perseguição na cópia em memória; arquivos anteriores permanecem intactos. Coordenadas inválidas usam recuperação regional segura.
- Primeira conversa Maciota/Dante reescrita em PT/EN, sem alterar a progressão da primeira missão. Cumprimentos com intervalo e voz procedural estilizada; letreiro da Monaliza removido, recompensa continua explicada no diálogo.

## Verificação

Testes específicos executados: física e colisões, dano/câmera, orçamento de renderização, agrupamento de meshes com dano/reparo/portas, saves/NOS/motores, recuperação de coordenadas, diálogo da campanha, recompensa Monaliza, abordagem policial e modelos/cobertura da emergência. Testes gráficos usaram Godot 4.7.2/Vulkan. Há avisos de ObjectDB no encerramento de alguns fixtures isolados; isso não é uma prova de ausência de vazamentos em partidas longas.

A auditoria estática da ponte não substitui todos os cenários de congestionamento. A redução de meshes é medida; não foi estabelecido um novo FPS garantido do mundo inteiro.

Captura de emergência: `D:/geteco/emergency-3d-cover-review.png`.

## Trabalho externo separado

Claude: entrega de HUD de frio/altitude e orientação do minimapa recebida e revisada. Suíte de 26 verificações executada no Vulkan, incluindo ocultação durante CGI e capturas em 1280×720/1920×1080. A seta usa velocidade a pé e conserva direção parado; veículos usam sua rotação. Ícones de Monaliza e spray preservados.

Astra: aviso de conquista reposicionado abaixo da pilha real de dinheiro/estrelas/relógio, acompanhando redimensionamento; cards de objetivo com fundo opaco para impedir interferência visual do cenário. `test_arrival_hud_regressions.gd` reproduz a abertura inteira sem skip nem remoção manual da CGI, desembarque real e telefone: 0 falhas, sem reproduzir o erro de `HarborArrivalStop.gd` relatado externamente. Também verifica separação da conquista nas duas resoluções. A suíte de layout passa a iniciar de um estado pós-chegada válido, mantendo sua regressão de CGI simulada, sem apagar uma cutscene em execução. Capturas: `D:/geteco/arrival-hud-1280.png` e `D:/geteco/arrival-hud-1920.png`.

Anti Gravity: cenário da oficina recebido e integrado por Astra. A garagem agora usa o piso e os volumes do cenário 3D completo, sem o antigo lounge/bancadas/paredes 2D. Maciota atende dentro da sala; o sensor da conversa fica do lado interno da divisória. A lousa tem representação 3D e acesso separado da bancada de diagnóstico. O enquadramento compacto é mantido na troca de câmera entre Dante e carro e removido ao voltar à rua. A renderização dos móveis permanece estática (UPDATE_ONCE ao entrar), com paredes dianteiras e estruturas altas translúcidas para visibilidade na câmera de jogo.

Validação da integração: `tests/test_workshop_gameplay_integration.gd`, com Vulkan e Player real, atravessa a entrada e a porta do escritório, inicia conversa por E, retorna pela lousa e sai ao Harbor; 0 falhas. `tests/test_monaliza_reward.gd` passou incluindo recompensa, porta-malas, restauração de estado e aceleração real até sair ao Harbor: saúde 180, nenhuma recuperação de movimento. Teste de câmera finita: 0 falhas. Posição histórica da baía preservada; visitantes restaurados fora do novo piso, mas dentro da área da antiga garagem, são recolocados na entrada acessível. Captura real: `D:/geteco/workshop-integrated-review.png`.
