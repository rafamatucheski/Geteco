# Checkpoints de salvamento

O ponto de entrada do jogo é `FullSession.save_game()`. F5, menu de pausa e
autosaves passam pela mesma verificação antes de capturar ou escrever estado.

- Bloqueia qualquer estrela da polícia, missão de campanha ativa (inclusive
  suspensa), etapas intermediárias da missão introdutória, corrida/drift,
  contrato de guincho, prova de esqui, missão de Tonico e frete em andamento.
- Mantém os bloqueios de morte, transições, resgate, transporte e save inválido.
- Grava antes de aceitar missões e atividades. Falha de gravação impede a
  aceitação. Ao carregar esse checkpoint, a missão ainda pode ser aceita de novo.
- A campanha grava ao encerrar a missão; os objetivos intermediários ficam
  somente em memória. Compras e outras interações seguras continuam acionando
  autosave fora de missões e perseguições.
- Um autosave bloqueado temporariamente gera uma única solicitação pendente.
  Um Timer de um segundo reavalia as condições, pausando junto com o jogo.
  Quando permitido, captura o estado atual. Não enfileira snapshots intermediários.
  Falhas de disco não provocam tentativas infinitas. A solicitação desaparece
  ao sair da sessão; sair antes do checkpoint perde o progresso ainda não salvo.
- F5 e pausa são permitidos fora dessas condições. Nenhum aviso de salvamento
  substitui mensagens centrais de jogo: sucesso usa o círculo giratório;
  falha/recusa manual usa um círculo com exclamação no canto inferior direito.
  A pausa informa o bloqueio ou último erro no tooltip do botão de salvar.
- `SaveStore` mantém a escrita temporária validada, backup e recuperação de
  arquivos anteriores. Saves antigos continuam legíveis; não são apagados.

Validação funcional: `tests/test_save_indicator.gd`, com `--no-save --skip-arrival`,
usa arquivos isolados em `evidence/save-indicator`. O teste de persistência
genérico `tests/test_full_save.gd` cobre o armazenamento e a recuperação.
Esses testes não certificam performance renderizada.
