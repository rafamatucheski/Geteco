# Rodoviária: admissão durante a abertura

O Novo Jogo pausa a simulação durante a CGI. O serviço regional aguardava
`physics_frame` e consultava apenas `direct_space_state` para decidir se podia
nascer na rua. O sinal também ocorre com a árvore pausada, antes de o servidor
de física registrar os corpos recém-criados. O regional nascia sobre o ônibus
da plataforma 4, em frente à entrada. Esse ônibus já possuía a reserva do pátio;
preso na sobreposição, bloqueava também a saída das outras três plataformas.

A admissão agora verifica também os volumes dos veículos presentes na árvore,
nas suas transformações globais, sem depender da sincronização do servidor de
física. A consulta física continua cobrindo os demais obstáculos. Não há
teletransporte, remoção de colisão ou mudança de tamanho dos ônibus.

`test_harbor_terminal_shared_berth.gd -- --opening` cobre o Novo Jogo pausado,
a ausência de um regional duplicado e a admissão depois da entrada do primeiro
ônibus. A variante sem argumento continua cobrindo a inicialização após a
abertura. `diagnose_terminal_circuit.gd` observa a cena HarborGame, registra
estados da frota, sobreposições, capturas e amostras de frame time.

Evidência anterior: `D:/geteco/artifacts/terminal-render-baseline.log` e
`D:/geteco/artifacts/terminal-circuit-0913/baseline/`. Em 120 segundos:
zero entradas, zero saídas, zero pedidos às cancelas e sobreposição contínua
entre o regional e o ônibus da plataforma 4. A captura reproduz o problema
reportado. O teste antigo que marcava a abertura como já vista não reproduzia
essa condição.

Medição anterior: Godot 4.7.2, Forward Mobile, RTX 4060 Laptop, 1280×720,
limite normal de 60 FPS. Depois de 10 segundos de aquecimento, 4.851 frames em
110,05 segundos: média 44,08 FPS, p50 19,10 ms, p95 35,90 ms, p99 51,56 ms,
máximo 366,39 ms, 345 frames acima de 33,3 ms e 23 acima de 66,7 ms.
Outras cenas renderizadas e benchmarks de tarefas independentes estavam
executando na mesma máquina. Esses números são diagnósticos, não certificam
performance nem isolam uma regressão da alteração. Alvo: 60 FPS / 16,67 ms;
aumento de 5% em p95/p99 exige confirmação em ambiente comparável.

Depois da correção, a mesma observação renderizada de 120 segundos registrou
uma entrada, duas saídas, quatro autorizações de cancela, zero sobreposições
nas amostras e 6.543 pixels percorridos pela frota. O urbano completou duas
visitas e duas partidas, com quatro embarques e quatro desembarques. Evidência:
`D:/geteco/artifacts/terminal-render-after.log` e a pasta
`D:/geteco/artifacts/terminal-circuit-0913/after/`.

Medição posterior, também com interferência de processos independentes:
4.210 frames em 110,04 segundos, média 38,26 FPS; p50 24,25 ms,
p95 36,27 ms, p99 48,92 ms, máximo 386,64 ms; 403 frames acima de
33,3 ms e 19 acima de 66,7 ms. Performance permanece sem certificação.

Regressão específica da abertura: aprovada, oito verificações, incluindo
teste de sobreposição a cada tick durante a admissão e a manobra completa.
Log: `D:/geteco/artifacts/terminal-opening-regression.log`.

A observação adicional após a abertura, em cadência acelerada, registrou
quatro saídas, duas entradas, o primeiro circuito completo, seis passagens
autorizadas e nenhuma sobreposição nas amostras. O urbano completou sua
segunda partida normalmente. Log: `D:/geteco/artifacts/terminal-return-after.log`.
Houve avisos de recursos pendentes no descarregamento dessa cena; a execução
renderizada e a regressão específica da abertura encerraram normalmente.

`test_harbor_terminal_operations.gd -- --production` concluiu na última
execução com zero falhas: todos os quatro ônibus completaram uma volta,
com quatro saídas, cinco entradas (incluindo a chegada inicial), oito visitas
às plataformas, 16 embarques, 16 desembarques e nove passagens autorizadas.
O teste também varreu os volumes completos das rotas contra os sólidos e
conferiu continuidade de movimento e conservação de passageiros.
Log: `D:/geteco/artifacts/terminal-crossing-physical.log`.
O processo retornou 0, mas também emitiu avisos de recursos/RIDs ainda ativos
no descarregamento. Portanto, a aprovação acima é dos contratos funcionais;
ela não aprova o ciclo de descarregamento global da cena.

## Pendência distinta no trânsito

Isso não elimina as falhas intermitentes observadas antes na validação longa.
`terminal-circuit-regression.log` ficou com dois ônibus aguardando o urbano
em Foundry × Union; o controlador permanecia em ALL_RED sem veículo dono.
`terminal-crossing-detail.log` reproduziu uma retenção em Foundry × Warehouse
com pedestres vivos na faixa, enquanto a fila mantinha os quatro ônibus fora
do terminal. Essas execuções foram interrompidas depois de registrar ausência
de progresso. A causa de navegação desses pedestres não foi corrigida nesta
alteração. A passagem posterior não certifica a ausência dessa intermitência.

O teste de operações agora identifica os ocupantes físicos da faixa, seus
obstáculos, vizinhos e estado de navegação, para distinguir uma espera real de
uma retenção indevida. Não foram alteradas regras de semáforo, colisões ou
navegação de pedestres para fazer o teste passar. O projeto recebeu edições
concorrentes durante essas execuções, inclusive falhas transitórias de carga
de arquivos fora do terminal; a correção aqui é a admissão segura na abertura.
