# Morte, IML e sepultamento

O óbito de um NPC humano passa a pertencer a `CoronerCare`. A ambulância continua
responsável por pessoas vivas incapacitadas. Uma internação, passagem de dias ou
reposição de população não pode ressuscitar uma identidade com óbito registrado.

## Fluxo

1. O óbito registra identidade, nome conhecido, causa, região e posição.
2. Uma testemunha ou socorrista comunica a ocorrência pelo sistema existente.
3. O diretor despacha um rabecão da frota finita. A equipe desembarca e caminha
   até a vítima; distância e visão livre são verificadas antes da coleta.
4. Corpo ou fragmentos pertencem à mesma ocorrência. Apenas um portador assume
   a custódia; a carga só entra no veículo quando ele efetivamente embarca.
5. O veículo volta à base do IML. A recepção dura oito segundos de simulação.
6. O rabecão segue pela malha viária até o acesso externo do cemitério.
7. Um agente entra pelo portão e leva a carga à sepultura reservada. Anselmo
   participa quando está vivo, disponível e trabalhando. O sepultamento exige
   presença no local e trabalho concluído; depois a equipe volta ao veículo.

O livro do IML apresenta os estados reais. Sepulturas possuem identidade própria
e persistem no save. Não identificado é diferente de um personagem com nome
conhecido. O estado `unrecovered` significa não recolhido, nunca sepultado.

## Interrupções e limites

- Save/load preserva óbito, custódia, fragmentos pendentes e ocupação das sepulturas.
  Se a região for descarregada, uma carga sem veículo é recuperada ao retornar
  à região. Não há sepultamento fictício durante o descarregamento da região.
- Morte do portador ou perda do veículo gera carga recuperável em piso livre.
  Em interiores projetados, o saco usa o mesmo buffer de profundidade da sala;
  sua obstrução física vem da projeção da própria malha.
- A equipe usa as portas registradas pelo gerenciador de interiores do Harbor.
  Interiores sem adaptador de projeção e porta registrada permanecem pendentes;
  este trabalho não certifica todos os ambientes legados do jogo.
- As 12 sepulturas operacionais não são sobrescritas. Com todas ocupadas, a
  ocorrência fica aguardando vaga e a carga continua sob custódia.
- O recolhimento limpa o sangue associado à vítima. Dinheiro e outros itens
  independentes não são apagados pela rotina do IML.
- Apenas pedestres ambientes do Harbor recebem substitutos, fora da câmera,
  com outra identidade. Personagens importantes não são substituídos.
- Agentes novos do IML recebem identificadores sequenciais persistidos; reutilizar
  uma vaga da frota não reutiliza a identidade de um funcionário morto.

## Validação

Testes em `res://tests/`:

- `test_coroner_custody.gd`: exclusividade, save, perda de viatura, registro,
  sepultura idempotente, capacidade e proibição de ressuscitar.
- `test_coroner_physical_flow.gd`: percurso físico completo; opções `fragments`,
  `multiple` e `crew_loss` cobrem fragmentos, várias vítimas e morte do portador.
- `test_coroner_interior_access.gd`: entrada/coleta/saída reais; opção `crew_loss`
  exercita recuperação de carga dentro do ambiente.
- `test_projected_interior_contract.gd -- coroner`: varreduras de colisão com
  jogador/agente e comparação de pixels com oclusor e controle positivo.
- `test_coroner_keeper_burial.gd`, `test_coroner_crew_passing.gd` e
  `test_coroner_population.gd`: trabalho de Anselmo, circulação e substituição.
- `test_emergency_braking_clearance.gd`: distância de frenagem e contato imediato
  para os quatro tipos de veículo de emergência.
- `test_coroner_harbor_flow.gd`: cenário completo no Harbor, validando primeiro
  que a vítima está em piso livre, sem teletransportar equipe ou veículo.

Os testes de persistência médica e triagem continuam cobrindo pacientes vivos.
Testes headless comprovam comportamento, não desempenho de renderização.
Resultados e limites: [validação do IML](measurements/coroner-2026-09-13.md).
