# Harbor — auditoria para fechar o primeiro bairro

Data: 2026-09-06. Três agentes e coordenação principal. Auditoria do worktree
atual, que contém mudanças não commitadas e trabalho paralelo de outros agentes.
Nenhum arquivo de produção foi alterado nesta auditoria. Não houve commit.

## Decisões atuais do projeto

- Fechar um bairro jogável antes de ampliar novamente sua área.
- Boss dos Cobras com identidade própria; prêmio será um muscle car inspirado
  em Mustang, 3D como o cupê, com som próprio de V8. Ainda não entregue.
- Usar a conexão norte existente, sem duplicar acessos. O mapa 2 será uma ilha
  de floresta. Não abrir passagem para uma cena inexistente.
- Obra desde o início com trabalhadores, máquinas e barreiras. Depois do Boss,
  telefonema para Maciota; após 5–10 segundos em condição segura, câmera apresenta
  o fim dos serviços e retirada do bloqueio. Pular deve ter o mesmo resultado.
- Melhorar pedras, árvores e quinas sem bloquear pistas, portas ou calçadas.

## Bloqueadores e riscos para fechar o bairro

### 1. Corrida obrigatória não está comprovadamente estável

Nesta auditoria `test_cobra_campaign_runtime` e `test_cobra_campaign_gameplay`
passaram, mas duas execuções de `test_cobra_race_player_car` falharam. Primeira: 1.535,2 px,
checkpoint 3/4, aproximadamente 16,53 s, posição (7689,687; 1998,377), mensagem de
hospitalização. O rastro contém dano por impacto de PlayerCar e pedido de bombeiro.
Segunda: 1.623,6 px, checkpoint 3/4, 16,98 s, posição (7634,497; 1985,693), com
a mesma hospitalização. Guard rails estão desligados. O piloto automatizado não
desvia de outros carros: a falha não prova que um humano seja incapaz de vencer.
Não foi identificado o collider culpado; não atribuir a falha aos guard rails ou
ao trabalho do Antigravity sem evidência. Um teste ter passado antes não elimina
este resultado. Próxima correção deve registrar collider, vida, velocidade e
trajetória, mantendo trânsito/colisões e sem tornar o jogador invencível.

### 2. Atendimento automático de incêndio ausente em Harbor

HarborPreview/HarborGame não integram EmergencyDepotDirector. PlayerCar procura
o grupo `emergency_depot_director`; na ausência, retira um veículo do pool, emite
`EmergencyDepotDirector missing: fire dispatch cancelled` e o devolve sem atender.
Os caminhões dirigíveis do quartel não equivalem a esse serviço de emergência.

A polícia tem fallback em WantedManager, portanto não está simplesmente ausente.
Esse fallback posiciona viatura por deslocamento aleatório de 520–720 px, sem
consulta de terreno/rua nesse trecho. Spawn inválido é um risco identificado por
código, não um caso físico reproduzido nesta auditoria.

### 3. Pátio visualmente livre possui colisão invisível

FoundryLofts: consulta física em (1030,720) encontra
`District/FoundryLofts/BuildingSolid` no vazio do prédio em L. A colisão é o
retângulo integral da footprint. Corrigir para volumes correspondentes aos dois
braços, mantendo paredes reais e testando entrada/percurso no pátio.

### 4. Postes duplicados e áreas sem postes locais

District, EastDistrict e NorthDistrict criam os mesmos cinco postes herdados.
Em (743,1136) há três corpos de postes distintos sobrepostos. A cena possui cinco
filhos de poste em cada provider, mas nenhum StreetLamp dentro das regiões
geográficas East/North verificadas; Cobras tem seis. Corrigir distribuição por
provider e conferir a conexão com noite/clima, não apenas remover duplicados.

### 5. Integração final e duração ainda não certificadas

Os testes de campanha exercitam estados, recompensas e encontros reais, mas parte
do deslocamento é preparada por fixture e o teste de combate usa a API de dano.
Falta uma sessão contínua com mira, derrota/repetição, serviços e save/load.
Não foi estabelecida uma campanha de 50–70 minutos. Não usar esperas artificiais
para atingir duração. Integração Dante/garagem cabe ao Antigravity; UI/idioma e
isolamento dos testes de configurações cabem ao Claude, conforme tarefas atuais.

O Player de Harbor usa cápsula raio 5/altura 16. O protótipo de garagem anterior
usava raio 4/altura 14 manualmente: a integração deve testar a instância efetiva
de Harbor, e não assumir que os dois envelopes são iguais.

## Acabamento visual com locais concretos

| Local | Problema | Correção proposta |
|---|---|---|
| Laundry, x760–766 / y970–1120 | Pintura antiga de beco entra 6 px no prédio | Eliminar o desenho legado e usar a geometria atual de HarborAlleys como fonte |
| Acesso do carro secreto, (7220,1700) | Guia desenhada atravessa o driveway | Incluir apron no contrato de aberturas visuais da borda |
| Anel Cobra, (7700,1400), (8000,1700), (7700,2000) | Ressaltos na união dos arcos com junções | Refinar tangência e união do contorno local; não apagar calçadas |
| Jardim Cobra | Caminho interno não encontra de forma pavimentada a travessia norte | Criar ligação legível, sem fechar a área livre |
| East/North | Persistem nomes gigantes desenhados no chão | Remover rótulos de apresentação, preservando UI e sinalização útil |
| NorthbankHomes, x4900/5120/5330, y1510 | Três casas com mesma forma, dimensão e destaque | Variar recuo, cobertura, anexos, acesso e jardim, não só cor |
| Promenade y2397 | Treze módulos de banco/arbusto com passo de 175 px | Compor áreas de permanência e intervalos por uso, sem repetir o mesmo módulo |

Árvores em East repetem porte/cor e fileiras em y1100/1670; a repetição em uma
avenida formal pode fazer sentido, mas não deve representar toda a vegetação.
Cobras já tem massas naturais, porém repete a mesma composição de círculos/pedra.
Proposta: três famílias autoradas — sombra/quintal, borda costeira com rochas e
vegetação de transição. Variar porte, orientação, densidade e solo exposto.
Não espalhar objetos aleatoriamente em toda área verde. Preferir desenho estático
agrupado e colisão só onde há obstáculo real; medir impacto antes/depois.

## Ponte existente e ilha de floresta

A ponte estrutural atual liga oeste/leste em Foundry, x3200–4380, y400.
A conexão indicada ao norte existe como rodovia dividida em aterro, eixos x5880
e x6120, de y-2000 até o retorno em y-4200. Preservar esse eixo para a futura ilha;
essa distinção técnica não é proposta de substituir a conexão escolhida.

HarborGateway informa `connected=false` e `transition_scene=""`. Não há obra com
operários nem desbloqueio por Boss. Há retorno e limite físico; ainda não existe
transferência para o mapa 2. O trem atual é um circuito local elevado/subterrâneo,
sem handoff ferroviário para outro mapa.

Há também legado em `data/campaign/campaign_v1.json`: district_2 aponta para
`rural_badlands`, floresta para `future_west`, e a premissa inclui a notícia de
assassinato do irmão. Isso conflita com as decisões atuais. Não significa que a
CGI atual esteja usando essas falas; significa que não devemos ligar o novo fim
de capítulo aos desbloqueios legados sem reconciliar IDs, narrativa e saves.

## Evidências de execução desta rodada

- `test_cobra_campaign_runtime`: PASS, cinco serviços/estados/recompensas.
- `test_cobra_campaign_gameplay`: PASS, integração e UI pelos caminhos cobertos.
- `test_cobra_race_player_car`: duas execuções FAIL, detalhadas acima; não é estável
  apenas porque outras execuções passam.
- `test_harbor_bridge`: PASS, aproximadamente 1.386 px em cada sentido sem colisão.
- `test_harbor_gateway`: FAIL por expectativa antiga 20 ruas/40 faixas/38 junções.
  Validação da rede vazia e trajetos passam: cerca de 1.586 px por sentido; IA
  completa retornos de 3.675,6/3.824 px sem bloqueio. Atualizar a cobertura para a
  expansão, mantendo conectividade e colisão; não mudar produção para caber na conta.
- `test_harbor_life`: PASS completo nesta rodada, em cerca de 59 s. Courtyard e
  Exchange entram/saem nas duas direções sem obstáculo. Trem percorre 13.756,8 px,
  entra parcialmente no túnel, desaparece e emerge. Zero contratos de faixa
  inválidos/deadlocks registrados. Isso não prova ausência de falha em toda carga.
- `audit_harbor_finish_snapshot`: diagnóstico novo confirma pátio/postes/pintura.
  Exit 0 significa diagnóstico executado, não ausência de defeitos.
- `test_harbor_safety`: PASS, 96 travessias, pedido/concessão ao pedestre e 50
  handoffs. Quatro travessias ferroviárias em níveis separados, nenhuma em nível.
- `test_harbor_ship_access`: PASS, 641 amostras da cápsula, 38 sweeps, 316,7 px
  por input nativo, 1.089 amostras de água; acesso à proa e bloqueio/liberdade
  de projéteis nos locais previstos. O navio é acessível, não só cenário.

Não é uma execução de toda a suíte. Avisos ambientais de log/certificados não
foram tratados como prova de erro de malha. Não sobrescrevemos slots pessoais.
Não foi feita medição nova de FPS nesta rodada; os números dos relatórios de
performance/fluidez de 05/09 são históricos, não certificação do build atual.
Os benchmarks documentados usam Compatibility; `project.godot` não fixa esse
backend, portanto a futura comparação deve registrar o renderizador real usado.

## Ordem proposta para execução

1. Reproduzir e estabilizar a corrida; integrar despacho de emergência válido.
2. Corrigir pátio, postes e fontes duplicadas de pavimentação/recortes de guia.
3. Receber Dante/garagem/UI e validar novamente o percurso completo integrado.
4. Entregar Boss próprio + muscle car/V8 + prêmio único persistente, sem clones.
5. Preparar obra no acesso norte e fechamento do capítulo, com skip/save seguros.
6. Passar acabamento de vegetação/rochas/quinas e medir desempenho em cenário real.
7. Jogar o capítulo continuamente; só então considerar o primeiro bairro fechado.

A ligação física ao mapa 2 só abre para o jogador quando o destino estiver
jogável. Enquanto isso, validar o contrato sem enviar o jogador para o vazio.
