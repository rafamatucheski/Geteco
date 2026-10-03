# Digo

Direção do personagem definida pelo usuário em 02/10/2026 e ampliada em 03/10/2026.

Digo é o instrutor de motocross e organiza as provas de motos. Ensina Dante a
acelerar, frear e contornar a pista. A aula é gratuita e opcional; os valores e
prêmios das provas existentes continuam no progresso do motocross.

A apresentação usa o personagem Meshy fornecido pelo usuário, preservado em
`assets/digo/digo.glb`: rig de 74 ossos e malha de 4.207 triângulos. O arquivo
fonte permanece intacto; o pós-importador prepara a máscara da camiseta no
alpha dos vértices do recurso importado. O jogo ajusta a pose dos braços e
aplica uma respiração discreta. As fotografias ficam em `assets/digo/reference/`.

As três camisetas acompanham o calendário do jogo, usando `weather.moon_day()`:
dia 2, camiseta original vermelha; dia 3, cinza com **Eu amo volkswagen**;
dia 4, escura com **saudades amarok**. O ciclo se repete a cada três dias,
inclusive ao reencontrar Digo depois do streaming ou da restauração do save.

Seu carro é um Volkswagen Gol quadrado 1993, prata, duas portas, turbo, rodas
aro 15, placa preta e som alto. A segunda fotografia é a referência principal:
grade preta de lâminas horizontais, emblema central, faróis retangulares,
setas âmbar externas, para-choques cinza-escuros, milhas retangulares inferiores,
retrovisores e frisos pretos e rodas prateadas com grandes aberturas.

Digo também tem uma Volkswagen Amarok 2014 branca, cabine dupla, preparada
Stage 2, tração 4x4, rodas e estribos pretos. A apresentação segue a referência
fornecida para esse segundo veículo. Os dois faróis usam o perfil xenon da
infraestrutura existente. O diesel tem uma camada própria de escape e uma
descarga de turbo separada do estéreo do Gol, ativadas conforme motor,
aceleração, alívio do pedal e proximidade.

## Continuidade obrigatória — mapa 2

1. Digo reaparece como adversário na corrida do deserto, com esse mesmo Gol.
2. Depois da corrida, ele e Dante se tornam amigos. O pedido não condiciona a
   amizade à vitória; completar a prova é o acontecimento narrativo.
3. Digo tem uma oficina no mapa 2 e será responsável pelos upgrades dos carros
   do jogador. O nome próprio reservado para a fachada é **Digo**.
4. A oficina deve usar o padrão de interiores do projeto, colisão e oclusão
   reais, e upgrades com efeitos na dirigibilidade e persistência por veículo.

O mapa do deserto e sua oficina ainda não existem na V2 atual, que aceita as
regiões `harbor` e `mountain`. Este registro preserva a direção futura; não
representa uma corrida ou oficina já jogável. `DigoProgress` reserva o evento
`digo_desert_race` e o desbloqueio `digo_workshop`, sem liberar upgrades antes
da corrida. A integração futura deverá chamar o evento somente a partir de
uma chegada válida, nunca de abandono ou abertura de diálogo.

## Implementação atual

- `activities/motocross/Motocross.gd`: conversa, provas, empréstimo para aula e
  ciclo de vida dos dois veículos e sincronização das camisetas. Digo fica
  junto à entrada do motocross da Vértice.
- `gameplay/digo/DigoActor.gd`: personagem com colisão e apresentação 3D.
- `gameplay/digo/DigoMeshyModel.gd`: modelo importado, pose e três camisetas.
- `assets/digo/DigoImport.gd`: máscara da roupa gerada no recurso importado,
  sem substituir o GLB original.
- `gameplay/digo/DigoGolModel.gd`: modelo próprio baseado nas duas fotografias.
- `gameplay/digo/DigoCarSpec.gd`: tração dianteira, desempenho preparado,
  rodas aro 15 e integração com o áudio de turbo existente.
- `gameplay/digo/DigoCar.gd`: veículo dirigível e estéreo espacial. O áudio
  é uma faixa já existente do jogo, com alcance de 42 m e desligamento distante.
- `gameplay/digo/DigoAmarokModel.gd` e `DigoAmarokSpec.gd`: modelo e configuração
  da picape branca Stage 2.
- `gameplay/digo/DigoAmarok.gd` e `DigoAmarokAudio.gd`: carro dirigível e áudio
  de escape/turbo, também instalado em veículos genéricos restaurados do save.
- `systems/campaign/DigoProgress.gd`: encontro, aula e contrato do reencontro
  futuro. Não há taxa de aula nem recompensa que possa ser duplicada.

O save guarda `world.digo`, `world.digo_vehicle` para o Gol e
`world.digo_amarok_vehicle` para a Amarok. Saves antigos sem esses campos
continuam aceitos; registros presentes exigem IDs/modelos exatos e validação
pelo contrato `FleetState`, antes de restaurar qualquer estado.

Cada carro mantém posição, região, pintura, danos, pneus e equipamento em seu
próprio registro, mesmo sem ser o carro selecionado pelo jogador. A seleção
restaurada é adotada pelo ID existente, sem criar outro exemplar no pátio.
O save normal e a retirada por streaming capturam os registros; a volta
restaura cada veículo apenas próximo de sua posição e com apoio e espaço
físico para a carroceria. O Gol estaciona em `(-237, .13, -43.5)` e a Amarok
em `(-237, .13, -47)`, ambos fora do corredor de Digo e dos pontos das motos.

## Validação desta integração

- `tests/test_digo_progress.gd`: 18 verificações de estado, save/load em
  arquivo isolado, compatibilidade e rejeição de registros inválidos.
- `tests/test_digo_lesson.gd`: 15 verificações dos critérios da aula,
  presença do rig Meshy e rotação das três camisetas.
- `tests/test_digo_session.gd`: 30 verificações na cena real renderizada,
  incluindo colisão do jogador com Digo, corredor livre, aula gratuita,
  pausa, devolução da moto, câmera, apoio dos dois carros, save/load e
  retirada/restauração da Amarok sem duplicação.

A sessão integrada passa os 30 critérios funcionais, mas registra ao encerrar
16 objetos e recursos de renderização ainda alocados. Aguardar a saída da
cena e o fim do frame não eliminou o aviso; sua origem ainda precisa ser
identificada. Logs: `evidence/digo/session-amarok.log` e
`evidence/digo/session-amarok-cleanup.log`. Isso permanece uma pendência de
limpeza, sem atribuição demonstrada ao modelo, ao veículo ou ao mundo.

Esses testes não certificam uma aula inteira pilotada manualmente, toda a
iluminação do jogo nem o conteúdo futuro do mapa 2. Performance, apresentação
das roupas e iluminação temporal usam suas evidências renderizadas próprias.
