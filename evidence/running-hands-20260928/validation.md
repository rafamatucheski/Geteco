# Soco em movimento e granada — 28/09/2026

- `scripts/Actor.gd`: a torção de quadril do golpe só se aplica parado. Em movimento, o tronco faz o golpe e a passada conserva os pés. Reprodução anterior: deslocamento adicional dos pés de 0,0683 m; depois: 0 m.
- `gameplay/WeaponRigPose.gd`: a granada acompanha a oscilação do corpo/passada ao carregar; recuperação de 0,70 s compartilhada com Gameplay.
- `gameplay/Gameplay.gd`: prepara uma granada da reserva ao equipar com mão vazia ou ao terminar a recuperação. Não repõe durante contato pendente, recarga ou bloqueio de combate. Transfere munição pela API existente do inventário.

Validação: Godot 4.7.2. `tests/test_running_hands.gd`: 15 checks aprovados, incluindo esqueleto real, munição real sem cheat e garagem. `tests/test_dante_combat_timing.gd`: sessão Main com `--no-save --skip-arrival --population=8 --seed=7`, sem falhas; contato, dano único, soltura, troca e morte. Capturas `before-*` / `after-*` usam renderer Mobile na RTX 4060 Laptop, em cenário isolado do personagem. A granada já estava visível nesse cenário com munição na mão; o defeito de desaparecimento corrigido está na reposição da reserva, não na geometria do modelo.

Performance **não medida/aprovada**: havia seis processos Godot existentes; nenhum foi encerrado. Não executar benchmarks concorrentes. Alvo provisório para comparação futura: 60 FPS / 16,67 ms, com p95/p99 e mesma cena Main, rota e população; investigar aumento acima de 5%. As capturas avançam poses manualmente e o contador de FPS delas não é uma medição de gameplay.

Limitação: o motor reportou recursos/RIDs pendentes no encerramento, tanto nas capturas anteriores à correção como nas posteriores. Os testes headless também reportaram dependências/objetos pendentes no encerramento; isso não foi tratado como aprovação de ausência de vazamentos. Alterações locais anteriores em Actor e Gameplay foram preservadas.

## Revisão do ombro após feedback

A captura `after-grenade-67.png` ainda mostrava a manga elevada contra a cabeça; a revisão visual inicial deixou passar esse defeito. A trajetória de preparação, soltura e recuperação foi baixada e afastada do rosto, com arremesso pela frente e pelo lado direito. Tempos de soltura/recuperação permanecem iguais. Revisadas 16 etapas em corrida (`shoulder-sequence.jpg`) e vistas frontais parado (`shoulder-front-grenade-67.png`, `shoulder-front-grenade-72.png`), sem a invasão da cabeça observada anteriormente. Os 15 checks em corrida e 13 parado passaram. Persistem avisos de encerramento e ausência de comparativo de performance; havia quatro processos Godot alheios ativos nesta revisão.

## Direção do cotovelo — segunda revisão visual

O ajuste de trajetória acima não corrigia a dobra anterior do cotovelo apontada pelo usuário. Corrigido em `Actor._solve_combat_arm`: somente o braço direito com granada usa polo posterior (+Z local). A nova verificação mede a projeção real do cotovelo em relação à linha ombro–punho durante carregar, arremessar e recuperar. Antes: -0,1408 m (dobra anterior, falha). Depois: mínimo +0,0250 m correndo e +0,0223 m parado, ambos aprovados. Capturas laterais `elbow-side-grenade-67.png` / `72.png` e perspectiva `elbow-standing-grenade-67.png` conferidas. 16 checks em corrida e 14 parado passaram. O baseline encontrou erro transitório em `TruckersVillageSecretPassage.gd:536` de trabalho concorrente, não alterado nesta tarefa; as execuções posteriores não apresentaram esse erro. Avisos de encerramento e performance não medida continuam pendentes.
