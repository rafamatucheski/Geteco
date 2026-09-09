# Atividade planejada: frota e população por região

## Estado confirmado versus proposta

Inspeção em 05/09/2026: `DayNightWeatherManager.gd` já define cinco temas
ambientais: metrópole, inverno/ártico, deserto/badlands, floresta/montanha e
costa/praia. `VehicleCatalog.DISTRICT_VEHICLES` já separa city, winter,
desert, forest, beach, industrial e gang_specials.

Isso confirma vocabulário e suporte inicial de clima/catálogos, **não cinco
mapas construídos nem limites, ordem de conexão ou elenco final aprovados**.
Industrial/porto e gangue são categorias locais, não necessariamente mapas
adicionais. Harbor é o distrito atual em desenvolvimento. Usar os cinco
temas como base de planejamento, sem inventar geografia definitiva.

## Perfis regionais propostos

| Região/ambiente | Pessoas e vestuário | Veículos predominantes |
|---|---|---|
| Cidade e porto | Moradores, comerciantes, Cestudantes adultos, entregadores, estivadores, mecânicos; roupas casuais, uniformes, coletes e capacetes conforme função | Sedãs, hatches, táxis, vans, ônibus, caminhões portuários; esportivos raros |
| Neve e montanha fria | Moradores, turistas, trabalhadores de manutenção e resgatistas; casacos de espessuras diferentes, gorros, luvas, botas | SUVs, 4x4, vans fechadas, ônibus regionais e limpa-neve |
| Deserto e periferia árida | Moradores, caminhoneiros, mecânicos, trabalhadores rurais e viajantes; roupas leves, proteção solar e equipamento de trabalho quando necessário | Picapes, jipes, buggies, caminhões, ônibus rodoviários |
| Floresta e interior | Moradores, agricultores, guardas florestais, caminhantes, trabalhadores de madeira; botas, capas, roupas de trabalho e mochilas | Peruas, picapes, tratores, caminhões de madeira, resgate 4x4 |
| Costa e praia | Moradores, pescadores, turistas, surfistas, vendedores e salva-vidas; roupas leves, esportivas e uniformes apropriados | Conversíveis, peruas, campers, scooters, vans e ônibus turísticos |

Neve, deserto e floresta precisam de carrocerias adicionais como limpa-neve,
buggy e transporte de madeira. Já existem entradas no catálogo antigo;
revisar esses assets antes de acrescentar modelos à lista de 66. Adaptações
de pneus, bagageiros e sujeira não contam automaticamente como novo modelo.

## Backlog de personagens

- [ ] Expandir os seis civis do laboratório em famílias de corpos, rostos,
  cabelos, roupas e acessórios; não apenas trocar a cor da mesma pessoa.
- [ ] Primeiro lote proposto: 8 perfis por tema ambiental, 40 perfis ao todo,
  usando peças e rigs compartilhados. Meta de produção, não elenco pronto.
- [ ] Variar altura, constituição, idade adulta/idosa, tons de pele e gênero
  em todas as regiões. Ambiente determina roupa e atividade, não etnia.
- [ ] Elenco de serviço: policiais, bombeiros, paramédicos, equipe do IML,
  motoristas de ônibus, mecânicos, guardas florestais e trabalhadores do porto.
- [ ] Preservar personagens autorais, especialmente Maciota; não substituí-los
  por NPC aleatório nem randomizar aparências entre encontros da mesma sessão.
- [ ] Animações: parado, caminhada, corrida, pânico, reação a impacto, queda/
  morte, conversa, trabalho, entrada/saída e viagem em veículo.
- [ ] Soco com preparação/contato/recuperação e poses distintas por arma,
  somente para perfis que realmente podem lutar ou portar armas.
- [ ] Separar aparência de comportamento: civil não vira agressor por roupa,
  corpo ou origem. Respostas dependem de papel, facção e evento de gameplay.
- [ ] Validar encaixe mãos/arma, pés/chão, volume de roupa, animações e
  colisões em todas as variações, sem atravessar paredes nem atacar à distância.

## Distribuição e cidade viva

- [ ] Spawn por zona, horário, clima e função; densidade limitada por câmera.
  Misturar perfis locais e visitantes, não repetir uma fila de clones.
- [ ] Zonas de transição entre regiões; turistas e transporte inter-regional
  evitam fronteiras artificiais onde toda roupa e todo carro mudam de repente.
- [ ] Porto: turnos de trabalho e carga; rodoviária: fila, embarque, viagem e
  desembarque; hospital: equipe, pacientes e retorno do jogador conforme missão.
- [ ] Preservar o contrato da missão 1 (rodoviária) e hospital no respawn
  posterior; integrar somente após conferir os contratos atuais de missão.
- [ ] Bombeiros: manter veículos externos e as três opções internas; não
  remover viaturas existentes para introduzir os novos modelos.
- [ ] Área da primeira gangue: distribuição por território/facção e rotina,
  sem transformar todos os moradores daquela área em inimigos.
- [ ] Pooling/LOD e recursos compartilhados; medir CPU/GPU, frame time e
  picos em tráfego e multidão antes de aumentar a população.

## Ordem e aceite

1. Fechar cupê e Paint & Spray no Harbor; lista em `FROTA_PLANEJADA.md`.
2. Produzir uma pequena quadra demonstrável: 8 perfis civis locais, 5 famílias
   de carros e serviços prioritários, com diferenças visíveis e funcionais.
3. Testar navegação, embarque, combate contextual, reparo, dano, luzes e
   desempenho; guardar capturas e testes, não apenas validar compilação.
4. Expandir para frio, deserto, floresta e costa em lotes após definir quais
   mapas representam esses temas. Não iniciar todos os mapas nesta atividade.

Esta atualização é de planejamento. Não cria NPCs, veículos, mapas ou
alterações de missões; não estabelece data de entrega para toda a frota.
