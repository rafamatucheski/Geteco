# Harbor: primeira missão jogável

## Entrega

Novo Jogo no menu abre `HarborGame.tscn`. A cena herda o distrito existente,
mas não oferece os atalhos de teleporte/visão geral do protótipo.
`HarborPreview.tscn` continua disponível para revisão; `Main.tscn` permanece
disponível para saves antigos. Nenhuma cena antiga foi apagada.

Fluxo: abertura original de dez imagens (41,5 s) → ligação por texto → entrada física da
garagem → conversa com Maciota → quadro → contrato Primeiro giro → encomenda
no cais → retorno → $150, uma única vez. Enter avança a ligação; E interage
com portas, personagem, quadro e encomenda. Espaço avança a fala do Maciota;
Esc cancela sem concluir o contato. Esc fora dos diálogos abre a pausa.
Na CGI, Esc/Enter/Espaço pulam a apresentação, não o encontro com Maciota.
O mundo fica pausado durante a CGI para evitar atropelamentos fora de tela.

Maciota mantém a identidade roxa com modelo refinado: paletó, lapelas, lenço,
corrente, fedora, óculos separados, mãos articuladas e sapatos. Gestos distintos
de acolhida, explicação, indicação e concordância têm acentos finitos, em vez
de uma onda contínua. A bengala fica apoiada no chão. Boca acompanha um
envelope de fala, não lip-sync de dublagem. O viewport permanece em 112px e
para quando oculto; a escala acompanha o Player.

## Persistência e compatibilidade

Flags `harbor_campaign_active`, `harbor_arrival_seen`,
`harbor_arrival_call_complete`, `harbor_maciota_met`,
`harbor_delivery_started`, `harbor_delivery_picked_up` e
`harbor_delivery_complete` são salvas pelo CampaignState existente.
Ao assistir ou pular a abertura, somente o beat `prologue_call` é concluído
quando ainda está ativo. Não são completados os beats de roubo/prisão.
Saves sem a flag de Harbor continuam abrindo Main; o carregar pelo menu de
pausa recria a cena correta. O hospital local possui `hospital_spawn`.
O bootstrap restaura câmera, clima e visibilidade dos NPCs de interiores.

## Validação

Rodada CGI + Maciota: quatro testes headless passaram (`opening_cutscene_runtime`,
`maciota_character`, `harbor_campaign_flow`, `menu_flow_integration`), sem falhas
de asserção ou SCRIPT ERROR. A captura com renderização real percorreu toda a
CGI sem acelerar, terminou com sucesso e confirmou a continuação no telefone.
Auditorias de distrito/portas abaixo passaram na rodada anterior.

- `test_opening_cutscene_runtime.gd`: dez imagens originais, reprodução natural,
  fim/pulo com fade e sinais únicos, áudio e pausa da simulação.
- `test_maciota_character.gd`: quatro poses distintas, boca, bengala no chão,
  tamanho e suspensão de animação/renderização enquanto oculto.

- `test_harbor_campaign_flow.gd`: fluxo integrado, entradas E, cancelamento,
  gestos 3D, botão real do quadro, coleta/entrega por proximidade, recompensa
  única, respawn, restauração exterior/interior e saída após carregar.
- `test_menu_flow_integration.gd`: menu → Harbor → pausa/configuração/save →
  menu → carregar. Save e configuração de teste usam diretórios temporários,
  sem sobrescrever slots reais do jogador.
- `test_harbor_district.gd`: auditoria física de prédios/acessos/pistas.
- `test_harbor_entrances.gd`: nove portas animadas, sete entradas habilitadas,
  1.506,6 px de caminhada por input e entrada de veículo preservados.
- `tests/visual/capture_harbor_campaign.gd`: reprodução natural da CGI inteira
  e capturas reais da abertura, ligação, conversa, rig 3D e quadro.

Os deslocamentos longos do teste de missão são posicionamentos de fixture;
isso não equivale a uma viagem completa dirigindo nem certifica o tráfego
inteiro. A suíte completa do projeto não foi executada nesta rodada.

## Próximas etapas / limites

- Expansão planejada: covil da Cobra no mapa 1, Bairro 1 a oeste, carros
  secretos e corridas autoradas. Decisões, sugestões e critérios separados
  em `MAP1_EXPANSION_BACKLOG.md`; ainda não implementados.

- Correção da busca anterior: a CGI já existia fora de `game`, no projeto
  `D:/geteco/cutscene_godot_preview`. O pacote original foi reaproveitado em
  `game/cutscenes/opening`, com imagens/timeline preservados. Sons procedurais
  estão presentes; locução gravada das falas ainda não está incluída.
- A plataforma compacta agora opera um ônibus local com embarque/desembarque
  e Dante saindo após a CGI. Veja `TERMINAL_VALIDATION.md`. Rodoviária de
  múltiplas linhas e viagens entre distritos ainda não estão implementadas.
- Primeiro giro é um contrato introdutório completo; não é a campanha inteira.
  Próximos serviços, arco do irmão, prisão e demais beats ainda exigem autoria.
- A regressão de circulação Courtyard Lane já documentada nas etapas de
  performance não foi resolvida por esta integração.
- Warnings de permissões de logs/certificados/cache aparecem no ambiente
  restrito. A gravação real via renderer também depende de acesso ao user://;
  o teste headless usa armazenamento temporário e não prova essa permissão.

Sem commits e sem consumo de reset de cota.
