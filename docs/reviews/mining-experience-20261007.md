# Mineradora e Galeria Santa Brasa — revisão de 7/10/2026

Escopo: NPCs, combate e saque da galeria, emboscada exterior, veículos industriais e de fuga, legibilidade da espiral e câmera durante quedas na cava. Trabalho dividido entre três agentes, com execução do motor centralizada. Alterações concorrentes de terreno, combate e deserto foram preservadas.

## Implementação

- Mineiros participam do contrato de dano, interrompem o trabalho, fogem, caminham nas estações e caem ao morrer. Equipamentos das estações permanecem fixos. A revisão posterior de repovoamento permite reposição após cinco minutos, com o jogador longe da mina.
- A bolsa toca som ao ser recolhida. Sair com ela inicia três reforços exteriores. O recibo de R$ 12.000 é concedido uma única vez após eliminar a emboscada ou afastar-se 52 m. Morte/cancelamento descartam o saque pendente; salvar fica bloqueado durante a tentativa.
- Quatro carros decorativos do estacionamento foram substituídos por veículos reais e persistentes. Uma Bison de fuga fica em baia livre junto da galeria.
- Seleção de embarque usa a porta alcançável, evitando que um veículo vizinho ou o tamanho do caminhão escondam uma interação válida. Cabines receberam vidros e painéis ajustados; hidráulica fica fora do recorte das portas. Espera de embarque do caminhão contorna a folha aberta.
- Estrada de cascalho com contraste neutro, balizadores nos dois sentidos e bermas exteriores. A largura útil de 14 m e o traçado físico foram preservados.
- Galeria e britador usam áudio posicional com suspensão/descarregamento explícitos. Câmera retém a inclinação elevada durante quedas e recupera gradualmente após a passagem ficar livre.
- Após o pedido de mais detalhes, bancadas ganharam recortes por setores geológicos e perímetro quebrado, preservando o fundo e a estrada. Rochas e minério usam blocos fraturados assimétricos, com colisão correspondente. Britador, esteira e portal receberam nervuras, emendas, ferragens e madeira rachada; a galeria tem tábuas, pregos, remendos do vagão, ferramentas e material de embalagem sobre os móveis existentes, em lotes estáticos.
- Máquinas receberam caçamba com painéis inclinados, reforços e pinos, grelhas, degraus, mangueiras, transmissão e metal desgastado. Não foram adicionadas luzes ou loops por detalhe.
- A revisão pela câmera geral revelou que ferragens pequenas eram insuficientes. Uma segunda passada acrescentou material de cascalho/carvão/manchas, estratos nas faces grandes das rochas, escoras diagonais, cintas e objetos médios nas bancadas, preservando os sólidos. Oclusão final: **36/36**, com imagem real em `evidence/mining-20261006/coal-depth/player-natural.png`.

## Evidências funcionais

Godot **4.7.2 .NET**, `Harbor.csproj` compilado sem erros; testes Main confirmaram roteador C# ativo. Saves dos testes ficaram em arquivos próprios em `evidence/`.

| Teste | Resultado |
|---|---|
| `test_mining_workers.gd` | 11/11 após a última alteração de suporte inicial |
| `test_mining_vehicle_access.gd` | 11/11: alcance, seleção entre vizinhos e integridade hidráulica após recorte |
| `test_vehicle_doors.gd -- mining_backhoe mining_tractor mining_haul_truck` | 347/347 após o detalhamento; folga mínima da folha 0,46 m no caminhão e 0,34 m nas outras máquinas |
| `test_mining_machine.gd` | 33/33: captura, elevação e soltura de cargas reais |
| `test_coal_mine.gd` | 65/65 após o detalhamento: cápsula, apoio, móveis, acessos e ciclo de vida do segredo |
| `test_mining_access.gd` | 15/15; quatro varreduras de 1.996 amostras, carro/caminhão na subida e descida, sem colisões nem falta de apoio |
| `test_mining_ambience.gd` | 22/22: recursos, canais, suspensão, reentrada, distância e liberação |
| `test_mining_camera_stability.gd` | 1.100 frames de queda no campo de alturas final, zero inversões da inclinação durante a queda |
| `test_mining_session.gd --machines-only` | Três máquinas embarcaram, dirigiram e desembarcaram; Bison corrigida e validada separadamente em 14/14 |
| `test_garage_rewards.gd` / `test_garage_vehicle_transfer.gd` / `test_garage_driver_restore.gd` | 47/47, 11/11 e 34/34; transferência preservou restrição de armas |

Acesso 15/15, seleção de veículo 11/11, hidráulica 33/33 e estabilidade numérica da câmera foram repetidos após os recortes das bancadas e a troca da forma do minério. Os percursos de subida/descida são varreduras do corpo inteiro sobre os colisores reais; não são uma gravação de condução manual da espiral.

O teste completo de confronto verificou tiros inimigos com dano real, mortes por tiros do jogador, pausa, bolsa, morte/resgate, cancelamento, emboscada exterior, pagamento e save/load. Sua última caminhada de retorno cortava o trator estacionado: 156/157 checks passaram nessa execução. A rota de teste foi corrigida sem teleporte e o ramo final passou **15/15**, partindo do checkpoint real salvo. Evidências: `evidence/mining-raid-128768-5514919` e `evidence/mining-raid-99648-5620579`.

O ramo de fuga de Bison passou **22/22**: caminhada real até a porta, embarque, **51,92 m dirigidos** por acelerador/direção, distância final de 52,73 m do portal, recibo único e desembarque com apoio e cápsula livre. Evidência: `evidence/mining-raid-27400-6107435`. Esse ramo começa com bolsa e emboscada preparadas e proteção de vida, para isolar a direção; combate e coleta reais são comprovados pela execução anterior. O primeiro estacionamento sobrepunha uma pilha e foi corrigido; uma curva posterior da fixture cortava um pilar da esteira. A curva foi corrigida após análise do casco e raio de giro, sem remover o pilar ou alterar o veículo.

Queda renderizada de **18,01 m**, 77 frames em queda, velocidade vertical máxima 26,67 m/s, **zero inversões de inclinação durante a queda**, aterrissagem e 3,01 m de caminhada de recuperação no terreno final: `evidence/mining-fall-review-88524-5764678/report.json`. O início foi posicionado para provocar a queda; isso não certifica uma caminhada desde a borda inteira.

As três máquinas têm fotos em `evidence/mining-session-17468-5482116`; Bison dirigível e desembarque em `evidence/mining-session-27556-5172307`. Fotos estáticas não certificam toda a animação hidráulica.

## Limites da comparação

O baseline renderizado está em `evidence/mining-measure-80048-5818417`: p95 de 2,583 ms no pátio diurno, 3,356 ms no fundo noturno e 3,297 ms na galeria, em janelas de 30 s. Houve outro teste gráfico concorrente em parte da captura e alterações externas posteriores em dependências compartilhadas. Portanto, esse baseline **não permite aprovar regressão de FPS** nesta entrega. Meta provisória: 60 FPS / 16,67 ms.

A aprovação do áudio acima cobre recursos e ciclo de vida; a qualidade percebida do mix não foi certificada por escuta. A revisão não certifica a montanha de gelo, outras minas, iluminação global ou outras áreas do jogo.

## Medição e revisão finais

`evidence/mining-measure-82232-5802516/report.json`: fontes relevantes estáveis durante a captura, Godot 4.7.2 .NET, RTX 4060 Laptop / i7-13650HX, Mobile, 1280×720, MSAA 4× (enum 2), população solicitada 40, VSync e limitador desativados somente no diagnóstico. Cada cenário teve aquecimento separado e 30 s de amostras reais entre frames.

| Cenário | FPS médio | p50 / p95 / p99 (ms) | Máximo (ms) | >33,3 / >66,7 ms |
|---|---:|---:|---:|---:|
| Pátio diurno | 521,27 | 1,777 / 3,132 / 4,296 | 7,907 | 0 / 0 |
| Fundo noturno | 605,20 | 1,492 / 2,765 / 4,070 | 16,929 | 0 / 0 |
| Galeria | 345,22 | 2,680 / 4,514 / 6,102 | 19,545 | 0 / 0 |

Preparação/chegada teve máximos de **60,128 / 173,697 / 33,621 ms**, respectivamente, separados da janela estável. O panorama diagnóstico admite todas as regiões e usa câmera distante após o benchmark; seu pico de captura não integra a medição de gameplay.

**Comparação antes/depois inconclusiva.** O p95 da galeria subiu de 3,297 para 4,514 ms (+36,9%) entre capturas, mas o baseline e o final tiveram testes gráficos externos concorrentes e alterações compartilhadas entre versões. Não atribuir a diferença ao detalhamento nem declarar ausência de regressão. As janelas finais ficaram dentro da meta absoluta provisória; isso não elimina a pendência comparativa ou os picos de preparação.

Fotos finais revisadas: `mine-overview-diagnostic.png`, `pit-day-gameplay.png`, `pit-night.png`, `coal-gallery.png` e as três `mining_*-detail-diagnostic.png` nessa pasta. A espiral é reconhecível; rochas, escoras, desgaste e elementos industriais são legíveis nos enquadramentos revistos. Os detalhes das máquinas aparecem sem peças deslocadas nessas vistas. Fotografias não certificam estabilidade temporal de toda a hidráulica/iluminação.

Verificação adicional com configurações normais carregadas, sem `--benchmark`: `evidence/mining-fall-review-40584-5912174`, limite de 144 FPS, queda de 18 m sem inversões, apoio e caminhada recuperados, sem erros no log. A primeira tentativa desse ramo encontrou um erro transitório de inferência em `ArmoredTransport.gd`, recém-criado por outra sessão; ela não foi aceita como validação limpa. A outra sessão corrigiu o tipo e a execução acima passou, sem alterações nossas nesse arquivo.

Fotografias:

- [Galeria final](../../evidence/mining-measure-82232-5802516/coal-gallery.png)
- [Trator detalhado](../../evidence/mining-measure-82232-5802516/mining_tractor-detail-diagnostic.png)
- [Caminhão detalhado](../../evidence/mining-measure-82232-5802516/mining_haul_truck-detail-diagnostic.png)
- [Percurso completo em câmera diagnóstica](../../evidence/mining-measure-82232-5802516/mine-overview-diagnostic.png)

## Repovoamento solicitado posteriormente

A mina não permanece vazia após a primeira conclusão. Mineiros mortos ficam elegíveis para reposição após **300 s**, apenas quando o foco estiver a mais de 184 m do centro de atividade. A visita seguinte reconstrói no máximo as seis estações existentes. Os bandidos podem reocupar a caverna após o mesmo intervalo, com Dante fora de interiores e a mais de 184 m da saída; o encontro só é admitido na próxima entrada. Nenhum slot morto é reposto durante a mesma luta. Enfrentar a nova gangue e sair chama novamente três reforços exteriores.

A bolsa de **R$ 12.000 continua única**, protegida pelo recibo persistente. Reencontros mantêm apenas os drops normais dos inimigos. O cooldown dos encontros é de sessão: ao carregar um save concluído, os bandidos começam outra espera de cinco minutos; as mortes individuais dos mineiros não são serializadas. Saves anteriores continuam compatíveis.

Validação: `test_mining_raid.gd --repopulation-only`, **40/40**, em `evidence/mining-raid-150384-7343801`. O teste prepara um save com o prêmio já recebido, avança os deadlines para testar fronteiras sem esperar cinco minutos reais e posiciona o exterior como fixture. Entrada, corpos dos quatro bandidos, caminhada, morte por disparo real, saída, três reforços, limpeza, recibo e compatibilidade do save usam o Main .NET. Não é uma nova comprovação da condução da espiral. A primeira assertion dos mineiros exigia `is_on_floor` também das estações distantes que dormem; foi corrigida para exigir apoio do trabalhador efetivamente reposto e contagem/vida das seis estações.

Mineiros: **15/15** em `test_mining_workers.gd`, incluindo retorno cedo, tempo vencido com jogador próximo, afastamento, reposição apoiada e ausência de duplicação. Build C# sem avisos/erros.

Diagnóstico renderizado após a alteração: `evidence/mining-measure-156712-7082106/report.json`, mesmas configurações e 30 s por cenário. Fundo: 336,87 FPS, p50/p95/p99 **2,715/4,972/6,500 ms**, máximo 17,122 ms. Galeria: 282,77 FPS, **3,310/5,353/6,933 ms**, máximo 10,972 ms. Nenhum frame >33,3 ms nas janelas estáveis; preparação teve máximos de 213,043/52,802 ms. **A execução terminou com status de medição inválida (`source_stable=false`)** porque `Gameplay.gd` e `Actor.gd` mudaram por trabalho concorrente durante a captura; também havia testes gráficos de combate e arrancada. Números são apenas diagnóstico, sem aprovação comparativa de performance e sem repetição automática sobre uma base em alteração.
