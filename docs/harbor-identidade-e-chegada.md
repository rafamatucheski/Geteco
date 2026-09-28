# Harbor — identidade e nova chegada

Decisão de direção registrada em 28/09/2026. Após o desenvolvimento do conceito,
o usuário autorizou sua implementação com um único agente. O terminal, a chegada
de barco, pescadores, ciclos de passageiros e dano/retorno dos trabalhadores foram
implementados. Testes funcionais e físicos passaram; a comparação renderizada
mantém pendência de percentis e picos. [Entrega, fotos e métricas](harbor-life-20260928.md).

## Nome e alcance

O nome escolhido para o jogo é **Harbor**, sem subtítulo definido. Geteco passa a
ser o nome histórico do projeto. A troca da marca nas telas, executável e demais
materiais foi iniciada pelo nome da aplicação e pelo título do menu. Caminhos e
identificadores de saves permanecem preservados.

Harbor é o ponto de origem da jornada, não um limite geográfico. A visão futura
inclui cidade no deserto, cidade inspirada em Las Vegas, outra cidade ainda por
definir e barcos como parte da expansão da jogabilidade. Esses itens são direção
futura, sem implicar implementação ou cronograma aprovado.

## Direção definida pelo usuário

- Dante chega de barco e desembarca junto com outros passageiros.
- A chegada acontece em um pequeno terminal de passageiros, separado da operação
  do porto de cargas, mas com relação visual clara com ele.
- Uma passarela elevada conduz as pessoas e permite ver o porto vivo.
- O início deve transmitir movimento e vida desde o desembarque.
- A imagem recuperada abaixo foi adotada pelo usuário como referência para a
  iluminação e a composição mais condensada do porto.
- Barcos de pescadores ficam ao lado, com NPCs executando ciclos de pesca.
- Pescadores mortos reaparecem depois de alguns minutos e retomam a rotina.
- O barco de passageiros repete chegada, desembarque, permanência e partida,
  retornando depois com mais pessoas. A chegada de Dante participa desse mundo vivo.

### Referência recuperada no histórico

Foi localizada e inspecionada uma imagem gerada em 20/09/2026 para o conceito de
menu: porto à noite, guindastes amarelos, contêineres, asfalto molhado, água azul
escura e iluminação quente. O registro de geração seguinte a utiliza como
referência de estilo aprovada. Em seguida, nesta conversa, o usuário adotou a
iluminação e a composição desta imagem como direção para o porto do jogo.

[Abrir imagem local](D:/CodexData/codex-home-clean/generated_images/01a0c13d-c873-79c0-b022-ce7758d74632/exec-50144322-e25b-4479-963e-f705add1926c.png).
Conversa de origem: `01a0c13d-c873-79c0-b022-ce7758d74632`.
É arte conceitual, não captura do jogo nem validação do cenário implementado.
A referência ajuda a definir materiais, profundidade e contraste de luz;
não fixa, por si só, o horário da nova abertura.

## Proposta de sequência

1. **Aproximação:** breve vista a bordo apresenta a costa e o porto ao fundo.
   O barco de passageiros tem escala compatível com o pequeno terminal.
2. **Desembarque:** outros passageiros começam a sair; Dante acompanha o fluxo
   por uma rampa de desembarque até o cais público. Funcionários e pessoas
   aguardando dão contexto ao lugar sem explicações decorativas na tela.
3. **Primeiros passos:** o jogador assume o controle cedo, com espaço para
   aprender a caminhar e observar, sem uma longa sequência obrigatória.
4. **Passarela:** o caminho sobe e revela gradualmente navios, guindastes,
   movimentação de carga e veículos de serviço. A vista principal acontece
   durante a travessia jogável; uma pausa para olhar é possível.
5. **Saída para a cidade:** o percurso desce para uma área pública conectada às
   ruas. A continuação da história será ajustada a partir desse ponto.

Esta sequência é proposta de desenvolvimento, não roteiro final aprovado.
Horário, clima, modelo do barco, número de passageiros e duração permanecem abertos.

## Organização espacial e atmosfera

Fluxo proposto: água → atracação de passageiros → cais público → acesso à
passarela → vista do porto → saída urbana.

A passarela deve ter uma função real de circulação, atravessando uma via de
serviço ou outra separação física a definir no mapa. A altura e o enquadramento
precisam revelar o porto sem permitir que passageiros desemboquem no pátio
restrito de carga. O terminal deve continuar pequeno, com escala humana.

O primeiro plano é formado pelos passageiros e pelo cais; o plano intermediário,
pela passarela e circulação de serviço; o fundo, pelos navios, guindastes e cidade.
Motores, água, passos, conversas e sons de trabalho sustentam a sensação de vida.
Movimentos visíveis devem corresponder à operação do mundo sempre que possível.
Não acrescentar slogans, descrições ou placas explicando a ambientação.

## Iluminação e composição do porto

Direção solicitada: reproduzir o tom portuário da referência e uma composição
mais condensada. Interpretar essa condensação como proximidade visual entre cais,
barcos, galpões e equipamentos, com percursos legíveis e escala física preservada.

Usar luz quente localizada nas bordas do cais, acessos, galpões e áreas de trabalho,
em contraste com água azul escura e sombras frias. Valorizar reflexos próximos às
fontes, volumes dos guindastes e silhuetas dos barcos. Evitar clarear uniformemente
todo o pátio ou usar luzes sem origem visível. O brilho do piso deve acompanhar
o clima e os materiais; a referência chuvosa não implica piso permanentemente molhado.
O porto precisa continuar legível e ativo de dia, com o ciclo de iluminação do jogo.

## Ciclo dos pescadores

Os pequenos barcos de pesca ocupam uma faixa lateral do cais, visualmente
conectada ao terminal, sem bloquear a atracação de passageiros ou as rotas de carga.
Proposta de rotina: preparar a vara → lançar a linha → aguardar com pequenos gestos
→ recolher → lidar com a captura ou equipamento → repetir. Variar as pausas entre
NPCs para evitar que todos façam a mesma animação ao mesmo tempo.

Se um pescador morrer, interromper sua rotina e iniciar um intervalo de alguns
minutos. Depois, repor o posto e retomar a pesca. O tempo exato permanece por definir.
Como proposta de apresentação, a reposição deve ocorrer fora da vista do jogador,
em ponto livre e seguro; se ele continuar olhando, adiar a aparição. Não levantar
o corpo morto nem duplicar o NPC original. Integrar limpeza de corpos e reações a
ameaças às regras existentes. Uma ameaça ainda ativa deve impedir retorno imediato
à pesca. Esse ciclo não altera as proteções permanentes de Maciota e do mecânico.

## Ciclo do barco de passageiros

Fluxo contínuo proposto: aproximar-se pela água → atracar → liberar desembarque
→ passageiros caminharem até a passarela e a cidade → permanecer alguns minutos
→ fechar o acesso → desatracar e partir → sair da área visível → retornar depois
com um novo grupo.

O barco deve sair navegando enquanto estiver visível; sua remoção e preparação
para o próximo ciclo acontecem fora de vista. O intervalo de retorno, a permanência
e a quantidade de pessoas ainda serão ajustados. Os passageiros devem seguir
percursos reais, com espaço entre si, sem aparecer de uma vez no cais ou desaparecer
ao terminar a rampa. A população precisa ter destino e limite para não crescer
indefinidamente a cada chegada.

O primeiro desembarque inclui Dante e conduz à abertura. As viagens seguintes são
ambientais e não repetem a introdução, os diálogos ou recompensas da campanha.
Antes de partir, o acesso deve estar livre; definir o comportamento caso o jogador
permaneça a bordo ou bloqueie a passagem. Pilotagem e transporte livre entre cidades
continuam sendo decisões futuras, não consequências automáticas deste ciclo.

Na implementação, impedir barcos sobrepostos na mesma vaga, passageiros na água,
travessia por casco ou guarda-corpos e duplicação de grupos ao recarregar a região.
Persistência e streaming devem manter o estado temporal sem recriar todas as viagens
perdidas durante uma ausência. Validar também interrupção por combate e retomada.

## Relação com a abertura existente

A [chegada atual](arrival-migration.md) usa uma CGI com referências à viagem de
ônibus, seguida de desembarque urbano, delegacia, telefonema e encontro com
Maciota. A futura mudança deve revisar tanto o filme quanto o início jogável;
trocar apenas o ponto de nascimento deixaria a narrativa incoerente.

O motivo da viagem, o assunto Vicente e a ligação com Maciota precisam continuar
coerentes. Ainda não se decidiu alterar a ordem delegacia → telefonema → encontro.
A rodoviária pode continuar fazendo parte da cidade mesmo deixando de ser a
chegada inicial. Saves existentes não devem reiniciar a campanha.

## Próximas decisões e critérios de implementação

- Referência visual registrada acima; comparar a futura cena real com sua luz e composição.
- Definir intervalos dos ciclos, população máxima e condição segura de reaparecimento.
- Escolher no mapa o cais público, o trajeto elevado e o enquadramento principal.
- Fechar a transição narrativa entre o desembarque e o primeiro objetivo.
- Revisar os planos da CGI, falas e áudios que dependem da chegada de ônibus.
- Aplicar a marca Harbor nas superfícies públicas preservando compatibilidade.
- Na implementação, validar travessia física, guarda-corpos, rampas, colisão e
  oclusão separadamente, fluxo de passageiros, pulo da introdução e save/continue.
- Medir a cena real renderizada antes/depois no desembarque e na vista elevada,
  com tráfego, porto, NPCs e streaming ativos, seguindo as skills do projeto.

## Implementação em 28/09/2026

- `HarborPassengerTerminal.gd`: terminal público, embarcação com permanência de
  120 segundos, percurso de saída/retorno de 32 segundos e intervalo de 100 segundos;
  até seis pessoas por desembarque, máximo de 12 passageiros ambientais presentes.
- `PortLifeArt.gd`: detalhes agrupados por material, passarela compartilhada,
  abrigo aberto, bancos, cabeços de amarração, cordas, caixas, barcos e guarda-corpos.
- `PortVisitor.gd`: dois pescadores com ciclo de 26 segundos e passageiros com
  percurso físico pelo barco, rampa, cais, passarela e ligação urbana.
- `PortWorker.gd`: dano, morte e integração ao atropelamento, incluindo corpo
  arremessado. Frente do modelo civil e caixa carregada corrigidas.
- Trabalhadores, carregadores, pescadores e portaria retornam após 180 segundos,
  aguardando o posto ficar fora da vista e livre. Corpo pode ser recolhido pelo
  socorro; há limpeza após 60 segundos. Maciota e mecânico continuam protegidos.
- Temporizadores de morte e fase do terminal integram o save, com leitura dos
  saves antigos que ainda não contêm esses campos. Passageiros já desembarcados
  não são recriados ao carregar a partida.
- A CGI mantém a história anterior à viagem e termina antes dos planos de ônibus.
  A entrada jogável ocorre no barco, conservando os marcos da campanha e o pulo.
- Luz quente do porto usa o conjunto compartilhado de seis fontes sem sombras
  adicionais. O fade baseado na distância da câmera é dispensado nessas fontes,
  pois a câmera ortográfica alta anulava sua iluminação; mantém-se o corte por
  proximidade ao jogador.

Estado dos testes, imagens e desempenho no [registro da implementação](harbor-life-20260928.md).
A performance foi medida e permanece sem aprovação de ausência de regressão.
