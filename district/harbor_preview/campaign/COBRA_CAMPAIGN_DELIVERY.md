# Campanha Cobra — integração em HarborGame

## Entrega

A chegada/telefone/Maciota e `primeiro_giro` continuam no controlador existente.
`CobraCampaignBridge` acrescenta cinco serviços ao mesmo quadro, sem substituir
o diálogo do Maciota nem gerar contratos aleatórios. O quadro mantém sete linhas
fixas e risca as concluídas.

1. Dentro do território: levar uma peça e conversar na oficina Cobra.
2. Prova de rua: uma volta na praça, com rival nas faixas/conexões reais.
3. A conta chega: proteger uma moradora contra dois cobradores.
4. Cortar o abastecimento: neutralizar oposição e recuperar registros físicos.
5. A última cobrança: derrotar a liderança; a pista sobre o irmão é ambígua.

Ao concluir um serviço, o seguinte exige o próximo dia **do jogo**, não um dia
real. Um dia corresponde a dez minutos ativos. O jogador pode explorar ou usar
o diário `[J]` para descansar perto do Maciota. Descanso tem fade, não inicia uma
missão, e não funciona durante missão, perseguição, combate ou fora da garagem.
Cada serviço ainda requer aceitação explícita no quadro.

`E` continua sendo interação a pé e entrar/sair de carro. A largada usa `R` para
não conflitar com a saída do PlayerCar. Conversas suspendem também o controlador
do veículo dirigido. Diário/conversas têm bloqueio de movimento e textos PT/EN.

O ledger vive em `CampaignState.cobra_campaign`: dias, conclusões, acesso aos
Cobras, respeito dos moradores, recompensas já pagas, vantagem opcional e carro
secreto. Carregamento cancela uma tentativa ativa de forma repetível; **não**
restaura combate no meio. Conclusões/recompensas permanecem. O cupê existente é
restaurado, sem clones, com posição/pintura/vida; interiores reais são válidos.

## Identidade e consequências

Cobras usam vinho, carvão e cobre, com variação de porte/acessórios. Olheiro tem
pistola, cobrador tem escopeta e líder tem SMG. Usam o rig articulado existente,
meshes de armas distintos, projéteis/dano reais e linha de visão. Civis têm cores
neutras distintas. Encontros têm elenco finito e não geram ondas infinitas.

Acesso autoriza permanecer no bairro; não deve autorizar agressão sem reação.
Durante um encontro autorado, a oposição daquele encontro assume o combate, sem
somar todos os guardas ambientes. Derrota final encerra o controle hostil sem
apagar a população. Ouvir uma moradora fora de missão concede uma vantagem no
final; ainda é uma interação curta, não uma missão secundária longa.

## Evidências e limites

- `test_cobra_campaign_state`: gates, dias, recompensas únicas e JSON/namespace.
- `test_cobra_discovery`: carro real, pintura/vida, JSON e garagem real sem clones.
- `test_cobra_campaign_runtime`: cinco conclusões, falha/repetição, rival real,
  checkpoints, morte de atores e pagamento total único de $1.520.
- `test_cobra_campaign_gameplay`: HarborGame completo, E no quadro/conversa,
  J/Enter/Escape, descanso/fade, R com PlayerCar e bloqueio durante diálogo.
- `test_cobra_campaign_spatial`: moradora e sete oponentes em encontros reais,
  sem nascer em prédios/postes/veículos/guardas; aproximações físicas livres.
- `test_cobra_race_player_car`: carro de produção dirigido por Input após
  posicionamento inicial, aproximadamente 1.873 px, sem saltos de posição na volta.
- `test_cobra_encounter`: armas, projéteis, LOS, fase do chefe e conclusão única.

O teste geral do runtime usa fixture para deslocamentos e aplica dano via API
real. Não representa mira humana. O teste dedicado da corrida usa o controlador
real, aceleração e esterçamento. O teste UI usa viagens posicionadas pela fixture;
não representa uma sessão humana contínua de uma hora.

Ainda precisam de produção/balanceamento: duas corridas opcionais adicionais,
um favor secundário mais elaborado, duração e dificuldade com jogador humano.
A recuperação de registros é estática, não um comboio; o chefe se reposiciona,
mas não foge de carro. Não foi comprovada uma campanha de 50–70 minutos, nem
prometidos 60 FPS em todas as áreas. Não ampliar esperas artificiais para simular
duração. Os diálogos novos são textuais, sem nova dublagem nesta entrega.

Mudanças globais nesta etapa: extensão pequena de CampaignState para persistir
o namespace e ligação da bridge em HarborGame. Sem mudanças no PlayerCar,
SaveManager, rig global, quadro existente, localização global ou CGI. Sem commit.

## Resultado da rodada

Dezesseis testes selecionados passaram: os sete novos acima, mais
`test_cobra_territory`, `test_cobra_neighborhood`, `test_cobra_vehicles`,
`test_cobra_traffic`, `test_harbor_road_contract`, `test_harbor_safety`,
`test_harbor_coupe`, `test_harbor_terminal` e `test_harbor_campaign_flow`.
Os módulos afetados foram reexecutados após correções posteriores. Não é a
suíte inteira do repositório. O teste UI também passou com OpenGL/renderização
real; imagem revisada: `D:/geteco/cobra-campaign-journal.png`.

Correções encontradas na integração: largada E conflitava com sair do carro;
rival precisava parar em `_process` na contagem e usar faixas canônicas; chefe
sobrepunha guarda; marcador permanecia após conclusão; acesso confundia-se com
imunidade à agressão; Ferrugem morto permitia conversa; save de carro descartava
garagem legítima. Cada caso recebeu cobertura específica. O primeiro teste UI
também usava flags de chegada inexistentes; a fixture foi alinhada às flags
reais, sem remover as asserções.

Restam avisos ambientais de log/certificados, cache de shader/save-dir no modo
renderizado e alguns avisos ObjectDB no encerramento de fixtures. A persistência
nova foi exercitada por serialização/JSON/restauração, sem sobrescrever slots do
jogador. Isso não constitui prova de gravação de um slot físico em `user://`.
