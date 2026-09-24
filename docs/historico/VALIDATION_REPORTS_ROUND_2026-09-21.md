# Recebimento da rodada de validação

Consolidação dos relatos enviados pelo usuário e dos dois anexos lidos integralmente. Não houve reexecução ou auditoria independente nesta consolidação. Resultados abaixo são atribuídos às respectivas equipes; não comprovam paridade integral.

## Resultados relatados

- NPCs: 2031 verificações sem falha; rotinas de carga, turnos, conversas incrementais, suspensão/restauração e lodge sem duplicação. Ajustada uma rota do Porto Sul em 5,625m para evitar pallets. Rotinas não equivalem à operação portuária completa.
- Combate: fluxo produtivo de 62 checks e demais contratos aprovados segundo Claude. Corrigidos rumo da arma com controle/toque, zona morta de golpes, reação/queda de civis e recuo mirando. Mouse, atropelamento dos protegidos e morte real do jogador/veículo não foram exercitados. Chamada direta de _exit_tree não equivale a validar o descarregamento completo da cena.
- Progresso: 11 cenários de atomicidade e nove de estado; colete/recompensas/reparo integrados segundo equipe. Duas tentativas de suítes oficiais não chegaram a executar por importação concorrente. Só o beat prologue_call_completed foi conectado com evidência produtiva; não fabricar os demais a partir de outro arco.
- Som: motores próximos conectados, até seis veículos/doze vozes; contratos e sessão renderizada verificaram reprodução/sinal. Audição humana comparativa pendente; electric e monaliza usam fallback street.
- HUD: capturas isoladas em 1280×720 e 1024×768, estados e remapeamento conferidos. Isso não valida todos os fluxos da sessão integrada. Teste legado show_settings precisa de revisão de contrato.
- Luz: cunha de concreto na emenda é ausência de asfalto segundo diagnóstico reproduzido; não foi atribuída a iluminação ou streaming. Sombras noturnas estáveis são questão visual separada. Correção geométrica encaminhada.
- Exportação: 1428 verificações de árvore sem ausência, 523 entradas via JSON/ResourceLoader aprovadas segundo equipe; 99 WAVs falham pelo caminho FileAccess no pacote. Templates Windows 4.7.2 ausentes, sem EXE produzido. Corrigir carregadores de combate e repetir verificação no PCK antes de declarar distribuição funcional. Preset ignorado pelo Git é pendência futura de versionamento, não autorização para commit.

## Prioridades de integração

1. Revisar referências a atores liberados em Responder/DispatchUnit antes de encerrar ocorrências; erro foi exposto por remoção de corpos no teste, não estabelecido como ocorrência normal em toda sessão.
2. Corrigir cobertura de asfalto da emenda com a equipe de mundo e reset de interpolação da câmera/anchor ao entrar no lodge com o integrador.
3. Resolver WAVs exportados com a equipe de combate/exportação, preservando formato/duração usados no jogo.
4. Investigar dinheiro aumentado após cheat (R$0→100→200); hipótese de conquistas ainda não comprovada.
5. Conferir testes legados divergentes antes de mudar expectativas. Não transformar teste que não iniciou em teste aprovado.

## Proteção dos saves — incidente relatado

A equipe de NPCs informa que uma primeira tentativa de test_full_session iniciou com no_save=false e chegou a carregar a sessão. Não consegue garantir que save pessoal não tenha sido tocado. Não há prova de modificação, mas também não se pode declarar preservação integral dessa tentativa. As execuções posteriores foram protegidas por guardas --no-save --skip-arrival. Comunicar ao usuário e investigar somente com operações de leitura, sem restaurar/apagar sobrescrevendo arquivos.

## Performance

Sem aprovação global. Claude relata picos de 70ms e 167ms em amostras de combate, sem causa estabelecida e com concorrência em parte das medições. Não concluir regressão nem folga com base no limitador de 60FPS. Suspender benchmarks paralelos e medir cenários comparáveis em janela exclusiva antes de aumentar população/efeitos.

## Paridade ainda aberta

## Recebimento posterior — travessia Harbor–serra

Resultados atribuídos à equipe de mundo, recebidos por texto; não reexecutados nesta consolidação.

- Correções: NativeRegion exclui célula montanhosa (5,-5) que invadia aproximação de Harbor; WorldConnection3D passa a convergir faixas diagonalmente até (468.25,-285), eliminando cotovelo de tráfego na cabeceira.
- Equipe relata travessia a pé nos dois sentidos e dirigindo ida/volta, preservando objeto do veículo, ocupação, saúde 80 e velocidade 12.40→12.49m/s na emenda. Passageiro e segundo veículo de tráfego também atravessaram com identidade preservada.
- Física relatada: 353 amostras contínuas de piso y=0.05; barreiras laterais e teto livre; 252 verificações de acessos/terreno. Revisita recompõe piso, mantém no máximo nove chunks por região e uma conexão compartilhada. Teleférico suspende antes da remoção e reaplica horário em nova instância única.
- test_regions passou; test_gameplay 208 verificações sem falha; cold/test_terrain ficou em 672/673. Falha atribuída pelo autor à busca antiga OriginalSawmillYard; proposta procurar YardEarth como MeshInstance3D preservando as verificações de limites. Conferir semântica antes de ajustar teste, sem marcar a suíte atual como aprovada.
- Destino de passageiro na serra ainda não está exposto em PassengerTransport, que filtra Harbor. Rota injetada funcionar não comprova viagem disponível pela interface; falta planejar com ambas regiões residentes.
- Aparência ainda simplificada. Correção do cotovelo de tráfego não comprova que a cunha de asfalto ausente do relatório de iluminação foi corrigida; comparar a geometria atual antes de encerrar aquele achado.
- Duas tentativas de benchmark abortadas por execuções concorrentes, sem aproveitamento de amostras parciais. Performance permanece pendente; capturas isoladas não comprovam frame time.
- Equipe relata ausência de commit e de alterações de saves nesta frente.

Operação das duas docas e ciclo de navios; sepultamentos/agente funerário/rotina e segredo do cemitério; estações e ciclos físicos de moradores/lenhadores; fachadas e acessos restantes; aparência de combate/IK/pânico/sangue/fogo; importação V1 e eventos canônicos não demonstrados. A menção de luneta pendente no relato do combate deve ser conciliada com zoom fixo/retícula entregues pela equipe de câmera: não registrar ausência total sem reconferir.
