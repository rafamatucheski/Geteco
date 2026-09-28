# Táxis e pintura bitom — 28/09/2026

## Implementação

- Union, Sedan Classic e Metro têm material de teto separado. Branco e cinza recebem teto preto; preto recebe teto marfim. Azul e vinho permanecem monocromáticos. As combinações são calculadas a partir da pintura salva, sem sorteio independente da cor do teto. Desgaste e reparo continuam usando os materiais individuais do veículo.
- O táxi amarelo recebe a mesma cabine inclinada com vidros do Union, letreiro TAXI legível nas duas faces e placas dianteira/traseira vinculadas ao identificador persistente do carro. O luminoso usa emissão no material, sem adicionar fonte de luz à cena; apaga com passageiro ou após roubo.
- Táxis entram no tráfego normal. E nas proximidades ou F junto à porta abre a escolha entre corrida e roubo. A corrida reutiliza o carro abordado, com rota viária física, verificação da saída, embarque lateral e desembarque seguro do PassengerTransport. Fechar o menu devolve o táxi de rua ao trânsito.
- O ponto fica a leste da Rodoviária, na calçada norte da Market Street: quatro vagas nos x=148,158,166,174; z=74, orientadas para oeste. A primeira vaga foi deslocada após revisão visual para afastá-la da faixa de pedestres. Quatro motoristas têm colisão, dano e reação a ameaça/roubo.
- O ponto monta no máximo um veículo e um motorista a cada 0,5 s quando o jogador está a menos de 95 m. Descarrega acima de 135 m ou ao sair da região. Carros tomados pelo jogador não são apagados pelo ponto nem duplicados a partir do mesmo identificador. As vagas usadas só são repostas depois de sair da área e quando não existe outro carro com o mesmo identificador.
- O roubo usa a entrada e o sistema de crime existentes. O dono do táxi estacionado foge; o motorista de táxi de rua usa a ejeção nativa. Táxi restaurado como veículo do jogador não anuncia corridas.

## Evidências e estado da validação

Godot 4.7.2. Todos os fluxos integrados usam --no-save; nenhum save do usuário foi gravado.

| Teste | Evidência |
|---|---|
| test_vehicle_twotone.gd | 31 verificações aprovadas: paletas, teto independente, persistência de pintura, desgaste, placas e isolamento do luminoso |
| test_fleet_finish.gd | 628 verificações aprovadas, incluindo cabine/vidros/luzes do táxi |
| test_vehicle_equipment.gd | 41 verificações aprovadas |
| test_vehicle_damage_look.gd | 104 verificações aprovadas |
| test_taxi_service.gd | Primeira integração: 38 verificações aprovadas de oferta, cancelamento, embarque, deslocamento real, pedido de desembarque, roubo, crime e reação do dono |

A ampliação do teste integrado, depois de mover a primeira vaga, encontrou falha ao solicitar uma segunda corrida para um ponto lateral à direção atual e falhas subsequentes com o menu ainda aberto. O cenário passou a escolher o próximo destino à frente e a fechar o menu em caso de recusa; essa revisão ainda precisa executar. A nova verificação inclui chegada automática, espaço dos NPCs, persistência do veículo roubado e descarregamento.

A execução seguinte foi interrompida antes de carregar Main por duas declarações idênticas de CANAL_TUNNEL em runtime/ProductionWorld.gd, introduzidas por edição concorrente. A revisão automática bloqueou remover a repetição no arquivo compartilhado. A correção específica foi apresentada ao usuário para autorização. **Validação final integrada pendente**, inclusive os últimos ajustes da entrada de táxis no Driving.

Capturas dos modelos: evidence/taxi-20260928/gallery/, geradas por tests/capture/capture_taxi_finish.gd. Capturas integradas de dia/noite em after/ ainda mostram a primeira disposição das vagas; não são evidência da posição final.

## Desempenho — não aprovado

Main.tscn real renderizada na área da Rodoviária, câmera/posição fixas, RTX 4060 Laptop, Vulkan Mobile, 1280×720, configurações locais preservadas. Janela de 8 s de aquecimento seguida de 30 s por cenário. Meta provisória: 60 FPS / 16,67 ms; tolerância de investigação: aumento >5% em p95 ou p99.

| Cenário | Antes FPS | Depois FPS | Antes p95 / p99 ms | Depois p95 / p99 ms |
|---|---:|---:|---:|---:|
| Dia | 80,08 | 55,95 | 18,22 / 27,79 | 34,31 / 69,87 |
| Noite e chuva | 45,58 | 37,01 | 31,35 / 37,56 | 44,04 / 136,01 |

Há piora medida e a meta não foi atendida. Durante a segunda execução havia outro teste renderizado, test_canal_tunnel_traffic.gd, iniciado às 12:47:59, além do editor; a causa da diferença não está isolada. Nenhum processo de outra sessão foi encerrado. Não se atribui a piora exclusivamente ao ponto, nem se declara ausência de regressão. Requer confirmação com carga externa estável após resolver o bloqueio de compilação.

JSONs em evidence/taxi-20260928/before/ e after/ contêm todas as amostras, aquecimento, hardware, limites e contagens de frames lentos. Antes: dia 2 frames >33,3 ms e 0 >66,7 ms; noite 38/0. Depois: dia 101/18; noite 100/44. Máximos posteriores: 207,74 ms de dia e 664,78 ms à noite. Testes headless não certificam desempenho.
