# Reforços após baixas em seis estrelas

O gerenciador de procurado e o pool policial são autoloads; o orçamento de população de `ContinuousWorld` atua sobre tráfego comum e pedestres. A inspeção não demonstrou descarregamento do gerenciador policial.

Foram corrigidos dois bloqueios de resposta: carros cuja equipe inteira morreu ainda contavam no limite de cinco viaturas e mantinham seus slots ocupados; carros com um sobrevivente embarcado esperavam eternamente pelo parceiro morto. Carros vazios também podiam reportar contato visual.

Agora a contagem de resposta exige equipe viva ou ocupante embarcado. A viatura só retoma movimento depois de todos os sobreviventes realmente embarcarem, conservando apenas os assentos ocupados. Sem sobreviventes, permanece imóvel e disponível no local. Fora da câmera com margem de 150 pixels de mundo e a pelo menos 1.800 pixels do suspeito, sua carcaça pode voltar ao pool para um novo despacho. Não há motorista inventado, aumento do pool nem reposição de mortos dentro de uma viatura visível. O orçamento de despachos por perseguição continua finito.

Seis estrelas agora exigem 120 segundos contínuos sem contato para encerrar a busca, em vez de 48. Os demais níveis mantêm seus tempos. A polícia continua buscando a última posição conhecida quando perde visão, sem seguir por GPS um suspeito escondido.

## Validação

Godot 4.7.2, headless, fixed-fps 60; logs em `D:/geteco/artifacts/police-six-stars-0913/`:

- `test_police_casualty_reinforcements.gd`: zero falhas. Moto de produção selecionada como suspeito; cinco viaturas, quatro mortes pelo caminho real de dano, vaga liberada e despacho real de substituição; preservação das carcaças próximas; sobrevivente embarcado retoma com um assento; busca não termina aos 48 segundos e ainda permite fuga ao término.
- `test_police_parked_without_crew.gd`: aprovado, sem movimento por timeout, ordem de retorno ou morte da equipe.
- `test_police_escalation_search.gd`: aprovado; percepção, busca, orçamento finito e disparos.
- `test_police_fair_arrest.gd`: aprovado.
- `test_continuous_police_pursuit.gd`: aprovado; a mesma viatura cruza cidade/montanha nos dois sentidos, sem teleporte. Maior passo medido: 4,30 pixels. Esse teste usa uma estrela; o cenário de baixas em seis estrelas é separado.

Há avisos de objetos/recursos no encerramento dos testes. A primeira execução do teste novo revelou acesso direto a uma propriedade opcional, corrigido; a extensão para sobrevivente revelou um retorno antecipado adicional, também corrigido. Resultados acima correspondem ao código corrigido.

Desempenho renderizado não medido: jogo/editor e outra captura renderizada estavam ativos. Custo novo limitado à inspeção dos sete slots por solicitação de veículo e da dupla por contagem/retorno, sem novo loop de população ou busca de caminhos. A duração maior da perseguição prolonga a carga existente; não há certificação de FPS nem reprodução manual completa da fuga relatada.
