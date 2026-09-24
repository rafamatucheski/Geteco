# Migração de interiores — checklist

## Interiores físicos na campanha V1 — plano de 22/09/2026

[Inventário completo e ordem de execução](inline-interior-migration-plan.md): 29 interiores distintos acessíveis no porto e na serra. No início deste plano havia 2 Ammu-Nation contínuos e 27 salas isoladas; agora são **29 concluídos** (15 na serra, 14 no porto) e **0 aguardando aprovação integral**. A contagem não inclui Northgate Auto, avião exterior nem necrotério sem acesso. A aprovação cobre circulação, colisão, oclusão, reentrada/save, fotos e frame time renderizado nos cenários registrados; as caudas transitórias ficam documentadas abaixo.

### Andamento da migração integral em 22/09/2026

Os cinco testes legados da serra (`test_ski_lodge_cutaway.gd`, `test_mountain_bunker.gd`, `test_distinct_mountain_cabins.gd`, `test_mountain_cabin_scale.gd` e `test_mountain_refinement.gd`) passaram após atualizar expectativas de porta, escala e coleta automática. Quatro reloads da campanha também terminaram sem os erros anteriores de teardown durante a construção assíncrona das salas.

- **Serra, 13 interiores concluídos:** Último Abrigo, Casacos da Vila e sete chalés passaram **201/201 checks renderizados** de caminhada sem E/marcador, portas, teto, câmera, recompensas, compra, colisão e oclusão real de jogador/NPC; após estreitar a câmera das fachadas menores, passaram **165/165 checks headless**. Save/reload do Último Abrigo passou **7/7** com posição, câmera compacta, balcão e recuperação do antigo spawn fora do mapa; Casacos compartilha a mesma sala e passou o snapshot físico. O chalé Pinhais passou **7/7** no reload em disco com posição, abrigo da neve, câmera e saída, cobrindo o fluxo de save compartilhado pelos sete. Abrigo dos lenhadores (três instâncias físicas, recompensa única), Cume Branco (duas saídas), Estação Zero e Caverna da Queda passaram **150/150 checks renderizados**, incluindo sólidos, profundidade, missões, saves escritos em disco e recuperação de posições antigas. O RPG da caverna passou todos os checks do teste `test_mountain_cave_reward.gd` após limitar seu alcance inline. Fotos e JSONs reais: `%TEMP%/geteco-mountain-inline-0922/{before,after}-<id>-{exterior,interior}.{png,json}`; a foto exterior de Último Abrigo contém uma UI transitória `Game eng...`, sem relação com a fachada. RTX 4060 Laptop, Mobile, 1280×720, VSync, 30 s: p95 interno antes → depois, Último 16,912 → 16,981; Casacos 16,921 → 17,037; abrigo 16,904 → 17,019; lodge 16,902 → 16,912; bunker 16,929 → 17,052; caverna 16,897 → 16,882 ms, todos com 0 quadros >33,3 ms na amostra final. A primeira amostra serial da caverna (p95 19,209; 11 quadros >33,3) e a primeira após zoom de Último (p95 18,765; 5 quadros >33,3) ficaram preservadas como `*-interior-first.json`; repetições isoladas não confirmaram a cauda. Os sete chalés têm amostras atuais p95 16,931–17,011 ms, 0 quadros >33,3, comparadas às sete amostras históricas equivalentes por sala em `docs/measurements/interior-standard-0920/route-mountain_cabin*.json` (p95 16,912–17,036 ms; Godot 4.7.2, Mobile, RTX 4060, VSync e 30 s iguais; código de 20/09 anterior). Vila 02/03/04: 17,036 → 17,011; 16,912 → 16,983; 16,931 → 16,971 ms. A amostra histórica `cabins-expansion-before` usa outro cenário e não entrou na comparação.
- **Porto, residências e coveiro concluídos:** `test_inline_homes.gd` passou **61/61** após aguardar a preparação da fachada Canal; compra, entrada/saída caminhando sem E ou marcador, porta, teto, câmera, quatro estações e recompensas foram verificados nas quatro salas. Save/reload em disco passou **22/22** nas três residências (inclui coordenada antiga de Canal) e **6/6** no coveiro em execução isolada. `test_inline_homes_depth.gd` passou **24/24 renderizados**, com oclusão positiva/negativa de jogador/NPC e colisão do NPC com móveis em cada sala. Fotos reais limpas de exterior/interior: `%TEMP%/geteco-inline-homes-0922/retake-{exterior,interior}-{westgate_garden,quayside_house,canal_north,keeper}.png`; JSONs no mesmo diretório. Na RTX 4060 Laptop, Mobile, 1280×720, VSync e 30 s, p95 interno Westgate 17,608 → 17,790 ms e coveiro 18,849 → 17,620 ms, zero quadros >33,3 ms após. Baselines históricos de 20/09 nas mesmas condições para Quayside e Canal: p95/p99 18,174/19,091 (8 quadros >33,3) e 18,184/18,888 ms (1 quadro), respectivamente. Canal após migração: 17,987/18,321 ms e zero quadros >33,3. Quayside teve duas caudas iniciais de 23,690/43,781 ms (53 quadros >33,3) e 20,690/39,631 ms (42); dois controles posteriores com viewport normal ativo ficaram em 17,908/18,387 (0) e 18,281/18,908 ms (1). Logs `%TEMP%/inline-quayside-ablation-0923{,b}.log` comprovam `UPDATE_ALWAYS` nesses controles. Uma ablação 2×2 posterior deu 17,875/18,508 ms, mas o frame time já normalizara antes; não foi atribuído custo causal ao viewport nem reduzida sua resolução. A comparação histórica usa código anterior de 20/09 e a cauda intermitente fica registrada.
- **Porto, delegacia e clínica concluídos:** `test_inline_harbor_services.gd` passou **22/22**, save/reload **12/12** e `test_inline_harbor_services_depth.gd` **19/19 renderizados**. Passagem sem E/indicador, atendimento/cura, corredor, colisão/oclusão de jogador/NPC e restauração física foram confirmados; as formas 1–3 do prédio Bay Medical continuam protegendo as ambulâncias. Fotos/JSONs reais em `%TEMP%/geteco-inline-services-0922/`; retake limpo da clínica `retake-{exterior,interior}-clinic.png` remove o vazamento RGB e mostra a cruz de cura proporcional. Em 30 s, p95/p99 internos Harbor Patrol 17,753/18,562 → 17,464/17,895 ms (quadros >33,3: 1 → 0) e Bay Medical 17,596/18,048 → 17,769/18,236 ms (0 → 0). Exterior Patrol 17,583/19,894 → 17,684/19,560 ms (2 → 1); clínica 17,834/19,681 → 17,968/18,767 ms (1 → 0).
- **Porto, Maciota, Fire e Boss concluídos com caudas iniciais registradas:** `test_inline_harbor_complexes.gd` passou **39/39** nas três salas, save/reload a pé e em carro **25/25**, e `test_inline_harbor_complexes_depth.gd` **25/25 renderizados** para jogador/NPC. O gate obrigatório `test_garage_weapon_restrictions.gd` terminou sem falhas: Maciota e mecânico invulneráveis, arma guardada/bloqueada no interior, inventário e uso restaurados ao sair. Maciota p95/p99 interno 24,691/41,963 → 19,207/26,027 ms (quadros >33,3: 54 → 6) e exterior 23,420/41,876 → 18,379/23,878 ms (43 → 11). Em Northgate Fire, as três portas e os três caminhões permanecem físicos; `test_harbor_fire_station_trucks.gd` passou **23/23** ao dirigir cada veículo para fora e de volta sem duplicá-lo. A persiana se recolhe, os lintéis saem do recorte interno e o jogador fica visível; foto limpa `%TEMP%/geteco-inline-complexes-0922/retake-interior-fire.png`. Apesar de uma primeira amostra interna após migração em 17,969/18,325 ms (0 quadros >33,3) contra baseline 17,777/18,242, após o ajuste visual duas amostras deram p95/p99 18,406/27,746 (11 >33,3; 4 >66,7) e 18,681/27,685 ms (13 >33,3; 4 >66,7). Viewport reduzido só no harness a 2×2 continuou lento (18,731/29,108); ocultar visualmente NorthDistrict também (18,395/26,650). Controle pareado no mesmo boot: interior 19,656/34,941 ms, 22 quadros >33,3; ao sair, exterior 17,795/18,240 ms, zero. **Fire aprovado após aquecimento, com caudas iniciais registradas e causa não atribuída:** a amostra interna aquecida `%TEMP%/geteco-inline-complexes-0922/confirm-fire-interior.json` deu 60,063 FPS, p95/p99 17,722/18,120 ms e zero quadros >33,3, comparável ao baseline de 60,06 FPS e p95 17,777 ms. As ablações não localizaram o motivo dos picos transitórios. Garagem do chefe: `test_port_boss_garage.gd` passou **181/181** após isolar no fixture a sondagem de sólidos dos seawalls/portal do mundo; roubo, cinco carros, guardas, alarme/polícia, Neco R$50 mil e save preservados. Fotos limpas `%TEMP%/geteco-inline-complexes-0922/retake-{exterior,interior}-boss.png`. Baseline interno p95/p99 17,654/19,926 ms; duas amostras após foram 19,742/20,968 (0 >33,3) e 21,604/32,188 (16), mas a restauração do viewport normal no mesmo boot terminou em 17,663/18,160 (0), enquanto 2×2 ficou em 21,513/40,308 (34). **Performance Boss variável; não atribuir a cauda à resolução do showroom.** Fotos/JSONs gerais dos três complexos: `%TEMP%/geteco-inline-complexes-0922/`.

Atualização final de 23/09/2026 para os complexos do porto: a Monaliza estacionada usa o passe 3D da oficina quando ocupada; com o teto fechado, sprite e sombra 2D ficam ocultos sem alterar colisão, save ou embarque. Ao sair dirigindo, modelo, sprite e sombra retornam à rua. `test_inline_harbor_complexes.gd` passou **45/45**, incluindo esse ciclo, `test_inline_harbor_complexes_depth.gd` **25/25 renderizados**, `test_inline_fire_trucks.gd` **23/23** e `test_garage_weapon_restrictions.gd` **0 falhas**. Foto exterior final sem vazamento e foto interior com carro no elevador: `%TEMP%/geteco-inline-complexes-0922/retake-exterior-maciota.png` e `after-interior-maciota.png`. Fire e Boss tiveram caudas nas primeiras amostras, sem causa conclusiva; controles aquecidos no mesmo cenário renderizado deram Fire **60,063 FPS, p95/p99 17,722/18,120 ms, 0 quadros >33,3 ms** e Boss **60,061 FPS, p95/p99 17,674/17,961 ms, 0 quadros >33,3 ms**. A aprovação de desempenho se limita a essas janelas e ao hardware registrado. Na última janela Maciota de 30 s após ocultar também a sombra, RTX 4060 Laptop/Mobile/1280×720/VSync: exterior **59,712 FPS, p95/p99 18,593/23,216 ms, 5 quadros >33,3 ms** contra baseline **23,420/41,876 ms, 43 quadros**; interior **59,908 FPS, 18,727/22,297 ms, 4 quadros** contra **24,691/41,963 ms, 54 quadros**. O fixture de medição reportou dois erros de liberação tardia em `MedicalRescueWorkZone.gd:77` depois das amostras; não foram atribuídos à garagem.

- **Union, concluída:** passagem física, porta automática sem E/indicador, compra, recompensa única e retorno passaram no teste dirigido headless e renderizado. A execução renderizada também ocultou jogador e NPC atrás do anteparo, mostrou ambos em piso aberto e confirmou colisão de cada um com o balcão. Save dentro da loja passou 8/8. No mesmo cenário renderizado por 30 s, exterior p95/p99 antes → depois 24,643/45,680 → 17,867/22,700 ms, 2 quadros >33,3 ms após; interior 17,579/17,955 → 17,595/19,192 ms, 0 quadros >33,3 ms após. O retake após ajuste de ordem de desenho mostra o rack sem poste; a segunda amostra interna manteve 59,99 FPS e p95/p99 18,261/19,453 ms, sem quadro >33,3 ms. Houve amostras variáveis de 55–56 FPS em exterior/interior alternados nas duas reexecuções; a causa não foi atribuída à loja. Os JSONs no diretório são da última execução. Fotos e JSONs em `%TEMP%/geteco-union-inline-0922/`.
- **Banco de North Pier, concluído:** `test_bank_inline_migration.gd` passou 34/34 checks renderizados, incluindo circulação, roubo, recompensa única, colisão de balcão e profundidade de jogador/guarda; 30/30 na reexecução headless após compactar a textura. `test_bank_inline_save.gd` passou 8/8 em disco; save antigo fora do mapa é recuperado em piso físico seguro. Na cena real renderizada por 30 s, exterior p95/p99 17,668/19,008 → 17,870/20,467 ms, um quadro >33,3 ms em ambas; interior 17,710/18,123 → 18,048/18,389 ms e zero quadros >33,3 ms em ambas. A primeira textura interna mais pesada produziu 31 quadros >33,3 ms e foi reduzida antes da medição final. Fotos e JSONs em `%TEMP%/geteco-bank-inline-0922/`.
- **Esgoto, concluído:** entrada/saída automática e combate no mesmo XY, em camada física subterrânea, passaram no teste dirigido, assim como save seguro, cobertura animada e ausência dos indicadores E. A execução renderizada adicional confirmou oclusão de Dante e NPC atrás de parede opaca, visibilidade em piso aberto e colisão do NPC com a parede; terminou com zero falhas. Exterior renderizado antes → depois: p95/p99 19,167/25,777 → 17,601/21,150 ms; interior 16,847/17,037 → 16,953/17,346 ms, sem quadros >33,3 ms no interior. Fotos/JSONs em `%TEMP%/geteco-sewer-inline-0922/`.

- Fuel, baseline renderizado no porto, 1280×720 Mobile/RTX 4060 Laptop, 30 s: exterior 40,76 FPS, p95/p99 42,357/55,260 ms, 190 quadros >33,3 ms; interior ainda isolado 57,89 FPS, p95/p99 24,550/35,890 ms, 24 quadros >33,3 ms. Fotos e dados em `%TEMP%/geteco-fuel-cutaway-0922/before-{exterior,interior}.{png,json}`. O gargalo exterior precede esta migração; comparar o mesmo cenário após a mudança.
- Boutique Alpina, baseline renderizado na MountainPass real, mesmo renderer/GPU/resolução e 30 s por cenário: exterior 60,005 FPS, p95/p99 17,326/18,890 ms, 2 quadros >33,3 ms; interior ainda isolado 60,009 FPS, p95/p99 17,189/17,561 ms, 0 quadros >33,3 ms. Fotos e dados em `%TEMP%/geteco-boutique-inline-0922/before-{exterior,interior}.{png,json}`.
- Histórico de investigação: Boutique passou primeiro 19/19 checks funcionais; a verificação foi ampliada abaixo. Fuel passou inicialmente 32 checks e falhou dois por tempo insuficiente de caminhada no teste: 150 quadros cobriam 69 px dos cerca de 84 px exigidos. O limite foi corrigido após medir porta aberta, bloqueador desligado e ausência de colisão à frente; 38/38 checks físicos e funcionais passaram depois.
- Boutique, validação concluída: `test_boutique_inline.gd` passou **59/59 checks**, incluindo 176 aproximações de jogador/NPC contra 11 sólidos, corredor livre, compra, recompensa única de R$ 1.250, save em disco com coordenada física, migração de save antigo, teto/câmera e viewport desligado ao sair. O teste renderizado anterior passou 37/37, com parede frontal encobrindo por inteiro jogador e NPC (0 pixels visíveis) e controles positivos de 2.060 e 1.306 pixels. `test_standard_clothing_rooms.gd` passou nas outras duas lojas ainda isoladas. Fotos reais em `%TEMP%/geteco-boutique-inline-0922/{before-exterior,before-interior,after-exterior,after-interior}.png`. Exterior p95/p99 antes → depois: 17,326/18,890 → 17,356/18,286 ms, quadros >33,3 ms 2 → 1. Interior: a primeira amostra mostrou p99 19,183 ms, mas a confirmação equivalente de 30 s mostrou p95/p99 17,091/17,498 ms versus 17,189/17,561 ms antes, 60,009 FPS e zero quadros >33,3 ms. JSONs na mesma pasta.
- Fuel, validação concluída da migração: `test_fuel_inline.gd` passou 38/38 renderizado, teste de save isolado em disco 8/8 e oclusão renderizada jogador/NPC 4/4. `test_standard_bank_and_fuel.gd` passou, preservando o banco. Pisos e produtos repetidos foram agrupados em seis MultiMesh, sem alterar sólidos ou aparência na captura comparável. Duas amostras pós-ajuste de 30 s no interior: primeira 60,03 FPS, p95/p99 17,83/18,75 ms, zero quadros >33,3; confirmação 57,76 FPS, p95/p99 19,95/35,48 ms, 29 quadros >33,3. Baseline da sala isolada: 57,89 FPS, p95/p99 24,55/35,89 ms, 24 quadros >33,3. **Não houve regressão reproduzível em p95/p99; a meta provisória de 60 FPS constantes não foi demonstrada** no segundo ensaio e a cauda variou entre amostras. Fotos reais e JSONs em `%TEMP%/geteco-fuel-cutaway-0922/`; fotos de oclusão `test-player-depth.png` e `test-npc-depth.png`.

## Ammu-Nation no próprio prédio — 22/09/2026

As duas filiais agora ocupam os 8,4 × 4,4 m da própria fachada. A porta deslizante abre por proximidade; a entrada e a saída ocorrem caminhando, sem ação E nem teleporte. O teto some ao cruzar o limiar, a câmera aproxima e os expositores laterais deixam um corredor livre até o balcão. E continua apenas como ação funcional de compra junto ao vendedor. O marcador laranja e a mensagem flutuante de compra foram removidos das duas filiais a pedido do usuário.

- Porto: `test_ammunation_inline.gd` renderizado aprovou 42 checks nas duas filiais, incluindo ausência do marcador e da mensagem de compra, entrada sem E, circulação, suspensão do render vazio, colisão de jogador/NPC e oclusão com controle positivo (0 pixels ocultos / 1.719 visíveis). `test_ammunation_identity_navigation.gd` aprovou 38 checks de compras, cobrança única, circulação e retorno. `test_city_ammunation.gd` passou renderizado, com catálogo, compra, cobrança única e saída.
- Serra: `test_ammunation_mountain_world.gd` no mapa real aprovou 14 checks, incluindo compra, colisão do fogão, entrada/saída e restauração de save legado. O teste renderizado compartilhado aprovou porta, teto e catálogo também na filial da serra.
- Fotos reais antes/depois do porto e fotos atuais das duas filiais: `C:/Users/rafae/AppData/Local/Temp/geteco-ammunation-cutaway-0922/{before-exterior,before-interior,after-exterior,after-interior,mountain-exterior,mountain-interior}.png`. Os JSONs das medições estão na mesma pasta. A cópia dessas imagens para `docs/measurements` ficou pendente porque o sistema negou criação de diretório no workspace.
- Porto, Vulkan Mobile / RTX 4060 Laptop / 1280×720, janelas de 30 s: exterior antes 51,42 FPS, p95/p99 31,512/39,942 ms, 58 quadros >33,3 ms; segunda medição depois 59,32 FPS, p95/p99 18,768/28,692 ms, 9 quadros >33,3 ms. Interior antes 59,18 FPS, p95/p99 20,818/28,982 ms, 9 quadros >33,3 ms; segunda medição depois 60,03 FPS, p95/p99 17,944/18,384 ms, 0 quadros >33,3 ms. A primeira medição depois ficou mais lenta, mas a repetição não confirmou regressão; condições concorrentes podem explicar a variação.
- Serra, cena real renderizada na mesma GPU e resolução, 30 s por cenário: exterior 60,00 FPS, p95/p99 16,996/17,431 ms; interior 60,00 FPS, p95/p99 17,110/17,705 ms; nenhum quadro >33,3 ms. Repetição dirigida com seed, VSync e limite de FPS iguais ao [baseline anterior](measurements/interior-standard-0920/gunshop-before.log): interior 60,01 FPS; p95 17,008 → 16,902 ms; p99 17,403 → 17,157 ms; 0 quadros >33,3 ms em ambas as medições.
- A primeira tentativa de reexecução após a suspensão do SubViewport encontrou erros de parse transitórios em arquivos de pedestres alterados por outra sessão. Após a compilação voltar a funcionar, a reexecução renderizada passou 38/38 checks, incluindo a suspensão em ambas as filiais.

## Geteco V2 — escopo independente, 21/09/2026

**A validação ampla de `urban_detail` segue adiada.** A integração altera fachadas e aproximações dos acessos, e o despacho acrescenta veículos/equipes no exterior. Checks e capturas anteriores abaixo são históricos; não aprovam a nova montagem. O acesso do bueiro foi revalidado separadamente em 22/09, como registrado abaixo. Revalidar os demais acessos e o tráfego após concluir a implementação. A contagem permanece 31 acessos / 29 interiores, sem acrescentar salas por trocar fachadas.

Integração urbana de 21/09: Ammu-Nation externa foi reconciliada com `NorthFrontage2` em `(1550,140)` em catálogo, fachada, entrada e retorno; garagem do chefe do porto ganhou portal exterior nas dimensões V1, aproximação pelo oeste e retorno no `EXTERIOR` exato; esgoto ganhou bueiro transitável no ponto V1. Os contratos estruturais de Ammu (14 checks) e dos dois exteriores (10 checks, incluindo cápsula e paredes) passaram. As salas internas não mudaram e suas fotos históricas continuam válidas apenas para o interior; entrada real, retorno, save e oclusão exterior precisam de nova captura antes de concluir estes três acessos.

Revisão do bueiro no jogo 3D, 22/09: tampa fechada por padrão, abertura deslizante, descida com pose de escada e enquadramento temporário foram verificados na sessão real. O canteiro que ocupava o acesso e um balizador que cruzava a leitura da animação foram removidos; o piso visual e sua colisão têm um vão alinhado ao poço, com tampa sólida quando fechada e sem piso atravessando a descida quando aberta. `review_sewer_animation.gd` passou na execução renderizada limpa, incluindo a ação `E`, colisão, oclusão, entrada, saída e restauração da câmera; capturas em `geteco_v2/evidence/sewer-entry-0922/final3d-*.png`. Nova execução física confirmou que a cápsula cabe no poço e que os controles destravam no retorno. `test_harbor_access_exteriors.gd` passou 11 checks, `test_sewer_session.gd` passou 12 e `test_regions.gd` passou. Save e comparação de frame time antes/depois ainda pendentes, sem promover o acesso a concluído.

### Migração completa em andamento — atualização posterior ao primeiro trecho

**31 acessos físicos / 29 interiores distintos** no V2: garagem do Maciota e 28 definições adicionais. Os acessos compartilhados dos abrigos não multiplicam interiores. A evidência histórica do primeiro trecho abaixo permanece restrita àquele cenário.

- [x] Geometria e posições: testes dirigidos de regiões, cápsulas dos oito residentes originais e sete posições de veículos da garagem do chefe aprovados.
- [x] Apresentação e oclusão amostradas separadamente: 56 fotos de entrada/atrás de mobiliário, mais quatro salas povoadas; [relatório e fotos reais](../geteco_v2/docs/interior-visual-review.md). A aprovação é dos enquadramentos e pontos registrados.
- [x] Sessão integrada: tarefa do Maciota, transições, banco, câmera, restrição de armas, aproximação e diálogos dos oito residentes e coleta hospitalar aprovados em `test_full_session.gd`.
- [x] Maciota nativo atual: passagem do escritório e braços do elevador recolhidos com colisão; oclusão separada em [amostras reais](../geteco_v2/evidence/native-v2-depth.json), 85,23% da silhueta atrás da mesa. [Foto atual](../geteco_v2/evidence/full-native-interior-final-isolated-population24.png) e comparação de desempenho em [FULL_MIGRATION](../geteco_v2/docs/FULL_MIGRATION.md).
- [x] Garagem do chefe: cinco carros e dois guardas com física dirigida e [foto renderizada](../geteco_v2/evidence/garage-guards-product.png). Comparação neutra 60 FPS, p95 17,460 → 17,615 ms, sem quadros >33,3 ms na janela estável. Pausas iniciais de aproximadamente 1,4 s e combate dos guardas permanecem fora desta aprovação.
- [x] Teste obrigatório V1: `full-v1-garage-test.log`, zero falhas; avisos de recursos retidos ao encerrar continuam registrados.
- [ ] Fluxos integrados de todos os ambientes, residentes, serviços, recompensas e restauração de saves.
- [ ] Entrada, saída e circulação completa dos veículos nas duas garagens; destino exterior com carro inteiro e apoio físico.
- Transferências dirigidas já aprovadas: 11 verificações nas duas garagens e 26 de restauração do motorista, incluindo casco completo, apoios, acesso físico à porta, câmera, inventário e ausência de duplicação. Não certificam todas as manobras de todos os 49 modelos.
- [ ] Desempenho comparável dos interiores adicionais com moradores e sistemas ativos. Medições do Maciota não aprovam as outras salas.

Migração integral **não concluída**. Estado geral em [FULL_MIGRATION](../geteco_v2/docs/FULL_MIGRATION.md).

### Evidência histórica — primeiro trecho

**1 lugar físico / 1 interior distinto nesta etapa histórica:** garagem do Maciota no projeto separado `geteco_v2`. Não soma à contagem V1 abaixo nem implica migração da campanha completa. Primeiro trecho nativo 3D implementado e validado: entrada/saída, câmera fixa, conversa, peça, entrega e checkpoint próprio. Modelos originais preservados; residentes sem dano/morte. Naquela etapa o combate ainda não estava implementado; sua integração posterior preserva o bloqueio de armas.

- [x] Física: cápsulas e varreduras, moradores fora dos móveis, passagem do escritório e caminhada contínua pelos pontos da tarefa.
- [x] Função: ordem, repetição, coleta única, transições recusando destino ocupado e restauração física de save/câmera/etapa/restrição.
- [x] Visual: [fachada real](../geteco_v2/evidence/v2-exterior.png), [interior real](../geteco_v2/evidence/v2-interior-entry.png), [diálogo](../geteco_v2/evidence/v2-dialogue.png). Câmera alinhada, escala humana e marcador compacto.
- [x] Oclusão separada: [controle atrás da mesa](../geteco_v2/evidence/v2-depth-behind.png), [amostras](../geteco_v2/evidence/v2-depth.json), 84,8% da silhueta visível atrás contra 99,9% na frente.
- [x] Desempenho estável renderizado: mesma rota exterior antes/depois 60 FPS; interior 60 FPS durante 30 s, 52,50 m caminhados; condução com 96 pessoas também 60 FPS. Sem quadros >33,3 ms nas amostras estáveis. Aquecimento tem picos até74,296 ms; ausência de engasgos iniciais não certificada.
- [x] Teste obrigatório V1 de restrição de armas: 0 falhas; avisos de limpeza de recursos no encerramento registrados.

Detalhes, métricas e limites: [validação V2](../geteco_v2/docs/VALIDATION.md). A comparação exterior avalia o acréscimo desta integração; o novo interior fornece baseline própria, sem alegação de superioridade sobre a sala híbrida V1.

### Acesso às lojas de armas na V2 — 23/09/2026

**2 fachadas / 2 interiores distintos nesta revisão V2:** Ammu-Nation do porto (`harbor_ammunation`) e loja de armas da serra (`mountain_gunshop`). Não alteram a contagem da migração V1. Aproximação abre a porta, caminhar pelo centro da entrada inicia um zoom curto centralizado na fachada e carrega o interior já existente. A saída também é por caminhada; E permanece apenas para ações funcionais como atendimento no balcão. A passagem exterior–interior ainda usa a troca de cena da V2 após o zoom, portanto não é uma sala física contínua no mapa.

`geteco_v2/tests/test_weapon_shop_walkin.gd` passou nas duas filiais em execução headless e renderizada: ausência de E para entrar/sair, zoom observado, entrada, câmera interna, atendimento com E e saída. `geteco_v2/tests/test_harbor_establishments.gd` passou 77 verificações renderizadas; `geteco_v2/tests/test_regions.gd` aprovou os sólidos e spawns das duas lojas; `geteco_v2/tests/test_camera_rig.gd` passou sem falhas. Fotos reais exterior/zoom/interior das duas lojas: `C:/Users/rafae/.codex/visualizations/2026/09/23/01a0cf97-e522-7a51-912d-8349c2270087/v2-weapon-walkin/`.

**Aprovação integral pendente:** medir frame time renderizado antes/depois em sessão isolada, sem os processos Godot concorrentes observados nesta revisão; confirmar colisão por aproximações e oclusão de jogador/NPC especificamente nesta nova rota. Os testes funcionais e as capturas acima não substituem esses dois gates.

Atualização: 20/09/2026. Padrão: [Chalé + Maciota](interior-standard.md).

### Hospital, árvores e guindastes — revisão de acesso de 20/09/2026

Revisão em andamento no Bay Medical: a porta interna foi transferida para a face sul, coerente com a fachada pública. Câmera ortográfica alinhada, escala humana, móveis e luz clínica preservados; o spawn abre para o corredor central. Removido o vidro fixo que duplicava as folhas móveis da fachada. A revisão invalida a conclusão anterior deste hospital até fechar os checks atuais; inventário permanece 30 lugares no escopo e 29 interiores distintos.

Fotos reais anteriores em `measurements/hospital-cranes-0920/before-facade.png`, `before-interior.png`, `before-northstar-crane.png` e `before-tree-behind.png`. São fixtures renderizadas, não benchmark. `test_hospital_and_crane_access.gd` verifica orientação, ciclo das folhas, corpo inteiro no spawn/corredor e colisões dos pedestais; `test_tree_canopy_occlusion.gd` reproduziu três falhas lógicas e três visuais antes da correção do adaptador de cenários desenhados. `test_south_port.gd` passou após calibrar pedestal: 4.686 passos, 32 trabalhadores, três caminhões, carregamento e partida, zero falhas; recursos retidos ao encerrar fixture registrados como limitação.

Fotos posteriores no mesmo diretório: `after-interior.png`, `after-facade.png`, `after-facade-open.png`, `after-tree-behind.png`, `after-tree-front.png` e `after-crane-depth0.png` a `after-crane-depth2.png`. Inspeção confirma saída sul e copas/treliças sobre o ator atrás. `test_hospital_and_crane_access.gd`: 22 checks renderizados aprovados, incluindo 4 aproximações físicas do tronco, três pedestais e pixels dos três braços dos guindastes com controles positivos à frente. `test_tree_canopy_occlusion.gd`: 30 checks renderizados, zero falhas; árvore de rua reduziu pixels expostos do ator atrás de 14.080 para 7.109, preservando a frente. A gravação de uma foto coastal no diretório legado falhou por acesso, mas seu teste de pixels passou.

`test_standard_harbor_rooms.gd -- ClinicInterior` aprovado no HarborGame real: 512 aproximações varridas com jogador/NPC, entrada/saída, corredor/vida, posições autoradas dos funcionários, profundidade compartilhada e suspensão da sala vazia, zero falhas. Oclusão por pixels: ator encoberto 0 pixels alterados em ambos; controles visíveis 931 (jogador) e 1.041 (NPC). Foto integrada `measurements/interior-standard-0920/ClinicInterior-standard.png`. O fixture deixa recursos/RIDs retidos ao encerrar, registrado como limitação de teardown.

Inspeção dirigida após confirmação do local pelo usuário: os três guindastes ao lado do **Northstar**, em y=990/1460/1700. Bases inteiras no cais x=3140..3191; cinco superfícies de água/ripples em z=-1, casco/convés em z=0 e estruturas separadas em z=4. Comparação renderizada água ligada/oculta em 30 pontos (duas posições de pedestal e oito nas duas longarinas de cada guindaste) teve diferença RGB zero em todos, confirmando metal acima da água nesses pontos. Fotos integrais `after-northstar-full0.png`, `after-northstar-full1.png`, `after-northstar-full2.png`; log `northstar-water-layer.log`, todos em `measurements/hospital-cranes-0920/`. O teste dirigido ampliado passou 26 checks; não houve mudança adicional de runtime após esta inspeção. A captura anterior não demonstrou água cobrindo metal, portanto esta evidência certifica a ordenação atual observada, sem atribuir uma causa anterior não reproduzida.

Pendente nesta revisão: comparação de desempenho renderizado equivalente. Nenhum FPS aprovado por testes headless; meta provisória 60 FPS / 16,67 ms, investigar p95/p99 com regressão superior a 5% em amostras equivalentes. A primeira tentativa geral não teve foco de janela válido; uma amostra posterior isolada não substitui baseline comparável.

### Pedras da travessia junto ao avião e orientação automática — 20/09/2026

As três plataformas planas receberam laterais com volume, contorno chanfrado irregular, faces minerais, grãos, rachaduras e faixa úmida. Os anéis geométricos foram substituídos por reflexos discretos interrompidos. Desenho estático em CanvasItem, sem novos viewports, luzes ou loops por quadro. As posições e os polígonos transitáveis usados pelo sistema de água permanecem idênticos.

Removidas as mensagens automáticas que indicavam loja de roupa térmica e rota do chefe. O aviso de temperatura ficou apenas “FRIO INTENSO”; indicadores de condição, interações e objetivos funcionais permanecem. [Antes](measurements/interior-standard-0920/lake-rocks-before-plane.png) · [Depois](measurements/interior-standard-0920/lake-rocks-after-plane.png).

Validação integrada: três áreas secas originais, passos fora da água nas pedras, apresentação estática e ausência do aviso de rota aprovados. Mesmo MountainPass, câmera, seed, Mobile/RTX 4060 Laptop, 1280×720, VSync/limite 60 e janelas 5+5+30 s; monitor sem concorrência detectada. Antes → depois: **59,93 → 60,01 FPS**, p95 **17,113 → 16,951 ms**, p99 **18,890 → 17,163 ms**, máximos estáveis **28,795 → 17,882 ms**, zero quadros acima de 33,3 ms em ambos. Primeiro quadro global **1.639,118 → 1.695,157 ms**, separado da visita conforme diagnóstico anterior. Logs/JSONs `lake-rocks-before*` e `lake-rocks-after*`. Não acrescenta lugares nem altera a contagem de 28/30 aprovações.

### Fachada compacta do Maciota — 20/09/2026

Revisão exterior em andamento: largura 19,5 → 7,8 m e profundidade 15,625 → 6,25 m (redução de 60% em cada eixo); altura e vão de carros preservados. Prédio vizinho fechado, com janelas, cornijas, calha e chaminé, no mesmo viewport estático. Nenhum novo interior acessível; contagens de lugares acessíveis e interiores permanecem iguais. A certificação anterior do interior não certifica esta revisão exterior.

Capturas reais do motor em fixture de fachada: [antes](measurements/maciota-exterior-before.png), [depois](measurements/maciota-exterior-after.png). Não são capturas da cena integrada. `capture_maciota_compact_exterior.gd`: quatro movimentos varridos contra as fachadas bloqueados e passagem lateral livre. `test_garage_weapon_restrictions.gd`: zero falhas, incluindo entrada/saída, restauração, inventário e invulnerabilidade; avisos de recursos retidos ao encerrar o teste headless. Pendente: oclusão de jogador/NPC e aproximação física com carro no cenário integrado, fotos integradas e benchmark renderizado antes/depois. Outras instâncias Godot estavam abertas; nenhum resultado de FPS atribuído a esta alteração. Meta provisória 60 FPS / 16,67 ms, investigar regressão superior a 5% em p95/p99, em comparação equivalente na RTX 4060 Laptop. Não aprovar esta revisão exterior até concluir os checks pendentes.

### Identidade exterior do Maciota no V2 — 22/09/2026

Garagem existente, sem novo acesso ou interior: **31 acessos físicos / 29 interiores distintos** continuam. A fachada ganhou pórtico de metal e latão, nome próprio MACIOTA, cobertura e telhado de oficina, baia com elevador e carro visíveis em sombra, luminárias que acompanham a noite e marcas de uso no piso. Os quatro sólidos originais da fachada e o ponto de entrada não mudaram; os novos detalhes são visuais, sem `interior_solid_id` ou colisão.

- [x] Capturas reais isoladas com a mesma câmera: `C:/Users/rafae/.codex/visualizations/2026/09/22/01a0cb63-0146-7b31-ac11-ff2a15165ffd/maciota/isolated-before.png` e `isolated-after.png`. Fotos reais integradas em `city-before.png`, `city-after.png` e `city-night.png` na mesma pasta; estas têm tráfego e população variáveis e não são benchmark.
- [x] Geometria, acesso e colisão: `capture_maciota_exterior_life.gd` verificou os quatro sólidos originais; `test_maciota_exterior_access.gd` passou entrada/retorno livres e quatro varreduras contra parede/pilares; `test_maciota_world.gd` passou sem falhas. A cena `Main.tscn` carregou e foi fotografada de dia e à noite.
- [x] Entrada e saída integradas: `test_full_session.gd` passou pelas etapas da garagem, incluindo restrição de armas, snapshot em memória e retorno ao exterior; `test_maciota_exterior_access.gd` confirmou a cápsula livre nos pontos de entrada e retorno.
- [ ] Restauração integral de save: `test_full_session.gd` terminou com uma falha posterior em “Cancelled mission can be saved and restored”, após sair da garagem e visitar outros locais. A suíte completa não está aprovada nesta revisão.
- [ ] Oclusão de jogador e NPC na aproximação, circulação veicular completa e desempenho renderizado comparável. A primeira amostra A/B de 30 s foi invalidada por outras instâncias Godot concorrentes e por erro de escrita do relatório após as amostras. A segunda A/B/A renderizada em `Main.tscn` (Mobile, RTX 4060 Laptop, 3440×1440, 100 pessoas, 103 veículos, noite, limite 60, VSync desligado, foco 100%) registrou 48,16 → 20,56 → 11,02 FPS, com p95 34,56 → 140,76 → 183,07 ms. O controle final piorou mesmo com o acabamento novamente oculto; outras instâncias surgiram durante a medição. Dados brutos: `C:/Users/rafae/.codex/visualizations/2026/09/22/01a0cb63-0146-7b31-ac11-ff2a15165ffd/maciota/frame-times-contended.json`. **Comparação inválida para atribuir custo à fachada; desempenho não aprovado.** Repetir isolado na resolução normal 1280×720, com meta provisória 60 FPS / 16,67 ms e confirmação se p95/p99 crescerem mais de 5%.

**Revisão exterior ainda em andamento.** A evidência visual e física acima não conclui os checks pendentes.

### Histórico da revisão dos indicadores — 20/09/2026

Regra permanente do Maciota: `test_garage_weapon_restrictions.gd` aprovado, zero falhas (entrada, saída, restauração, bloqueio de armas e proteção dos dois personagens).

Pedido atual corrigido pelo usuário: retângulo laranja com cantos arredondados já implementado (26×14, raio 4), sem E ou símbolo de controle; não um quadrado. Corrigido o componente compartilhado `DoorAccessMarker`, usado pelo `BuildingEntrance` no porto e na montanha, incluindo casa do coveiro, lojas, cabanas, caverna, lodge, estação, delegacia, hospital, garagem e bombeiros. Fachadas sem interior conectado não anunciam acesso. Revisados separadamente os avisos das três residências, garagem do chefe e entrada/saída do esgoto; compra, horário fechado e interações com objetos mantêm seus textos funcionais. O retângulo usa desenho estático compartilhado, sem animação por frame.

Correção do formato conferida em captura renderizada: [retângulo arredondado na porta](measurements/interior-standard-0920/rounded-door-marker.png). Os 24 checks dirigidos passaram novamente após a correção; registro em `measurements/interior-standard-0920/rounded-door-marker-checks.log`. A skill e o padrão versionados também registram esse formato. Esta validação é do indicador e não conclui a reforma global dos interiores.

Referência anterior: imagem fornecida pelo usuário `C:/Users/rafae/AppData/Local/Temp/codex-clipboard-03ace57d-c7c8-4a9e-a871-301553d54f9f.png`. Captura renderizada posterior: `C:/Users/rafae/AppData/Local/Temp/geteco-door-marker-after.png`, reproduzível com `tests/capture_door_marker_review.gd`. Revisão visual integrada de todos os locais e comparação de frame time permanecem pendentes; uma sessão de jogo já estava aberta. Esta correção de indicadores não certifica colisão/oclusão nem altera a contagem de interiores aprovados abaixo.

Validação dirigida: `test_interaction_keycap.gd` passou 24 checks (marcador em aproximação, controle, bloqueio/transição e destino conectado; teclas de outras interações preservadas). `test_cemetery_keeper_home.gd` passou, incluindo entrada e retorno à porta; o relógio simulado recebeu o campo `is_dynamic_time` exigido pelo serviço médico. `test_port_boss_garage.gd`: 172 checks, duas falhas no prazo/chamada da polícia. `test_residence_prototype.gd`: entradas, saídas, circulação e restauração passaram; três falhas nas expectativas de preço/troca de imóvel. `test_manhole_sewer.gd`: entrada, saída, circulação, coleta e restauração passaram; cinco falhas de arma/projétil/granada no mundo físico isolado. Essas falhas não foram corrigidas nesta revisão visual, e os testes amplos não estão aprovados. O ambiente também reportou restrições na gravação de logs, leitura de certificados e recursos retidos ao encerrar.

## Escopo aprovado em 20/09/2026

O usuário aprovou o resultado visual do chalé alinhado e autorizou a migração global. Escopo reconciliado: **29 interiores + baia externa Northgate Auto + avião externo = 31 lugares**. As sete cabanas e três lojas de inverno agora têm plantas e recompensas independentes. O Chalé da Encosta oferece R$ 5.000. A antiga WorkshopInterior não tem porta conectada; o local acessível correspondente é a baia drive-in externa.

## Contagem atual

O inventário inicial incluía uma sala sem acesso e compartilhava sete cabanas e três lojas de inverno. Após conferir acessos e separar essas salas, são **29 interiores distintos acessíveis**. Salas criadas sob demanda contam como interiores distintos, mesmo quando não estão carregadas. Não é contagem de portas: bombeiros tem três portões, lodge tem duas saídas.

| Unidade | Total | Concluídos | Em andamento | Não iniciados | Restantes para aprovação |
|---|---:|---:|---:|---:|---:|
| Lugares no escopo atual, incluindo o avião externo | 30 | 27 | 3 | 0 | 3 |
| Interiores distintos acessíveis | 29 | 26 | 3 | 0 | 3 |

**Ajuste de escopo solicitado pelo usuário:** Northgate Auto foi retirado da reforma. A oficina de reparo preserva apenas o fluxo/animação do carro entrando e saindo e o reparo existente; sua reforma visual foi desfeita manualmente. O inventário continua tendo 31 lugares acessíveis, mas esta migração abrange 30. Não contar a oficina como interior reformado ou como pendência dos outros ambientes.

Continuação autorizada com dois agentes: montanha (seis lugares), locais especiais do porto (cinco após retirar Northgate Auto) e integração/porto (nove). As implementações estão aplicadas; a contagem de conclusão depende dos checks e das medições, não da distribuição do trabalho. As evidências atuais por local prevalecem sobre os registros históricos de tentativas abaixo.

Comparativos atuais de câmera, qualidade e desempenho: [nove interiores do porto](measurements/interior-standard-0920/harbor-performance-report.md), [casas, esgoto e garagem do chefe](measurements/interior-standard-0920/special-harbor-report.md) e [diagnóstico monitorado dos picos](measurements/interior-standard-0920/harbor-stall-trace-report.md). Os relatórios distinguem FPS medido, resolução interna, amostragem de bordas e frequência de atualização; o limite de 60 FPS não é uma medição.

“Em andamento” indica critérios ainda pendentes, mesmo quando a apresentação já foi aplicada. As referências também passam pelos mesmos critérios; não contam como concluídas apenas por escolha artística.

## Inventário

Em cada linha, conclusão exige: visual; entrada/saída e indicador; colisão/spawn/circulação; oclusão de jogador e NPC; FPS e suspensão da sala vazia. “Concluído” refere-se aos cenários e hardware medidos, não a certificação de todo o jogo.

| Interior / lugares físicos | Quantidade | Estado | Evidência / próxima pendência |
|---|---:|---|---|
| Porto — Garagem do Maciota / Westgate | 1 | Concluído | [Foto final](measurements/interior-standard-0920/harbor-final-GarageInterior.png); 1.008 aproximações, profundidade, retorno do ator e regras de armas aprovados; 59,98 FPS, p95 18,137 / p99 18,490 ms, sem regressão no comparativo |
| Porto — Harbor Patrol | 1 | Pendente de desempenho | [Foto final](measurements/interior-standard-0920/harbor-stall-trace-PoliceInterior.png); câmera, dinheiro, 2.384 aproximações e profundidade aprovados. Medição monitorada 52,52 FPS, p95 33,574 / p99 47,723 ms durante trabalho regional solicitado pelo ônibus; meta 60 não aprovada |
| Porto — Bay Medical | 1 | Pendente de desempenho após revisão de acesso | Porta interior sul; vidro fixo removido da abertura exterior. 512 aproximações jogador/NPC, entrada/saída/cura/profundidade/suspensão e 22 checks da fixture aprovados. Evidências atuais acima. Medição anterior de 60,02 FPS não certifica esta revisão. |
| Porto — Northgate Auto, baia de serviço externa | 1 | Fora da reforma a pedido | Reforma desfeita manualmente. `northgate-preserved-final.log`: 0 falhas, animação/porta, reparo, cobrança única de R$ 100 e controle aprovados. [Foto preservada](measurements/interior-standard-0920/northgate-preserved.png). Não entra nos 30 lugares deste escopo |
| Porto — Northgate Fire / 03 | 1 | Concluído no cenário isolado | [Foto final](measurements/interior-standard-0920/harbor-stall-trace-FireStationInterior.png); 240 aproximações, profundidade, ciclo dos três caminhões/portões e cura aprovados. Medição monitorada 60,01 FPS, p95 17,759 / p99 18,177 ms; picos da conferência anterior permanecem documentados |
| Porto — Ammu-Nation | 1 | Concluído na reforma em linha | Fotos e medições atuais na seção de 22/09; entrada/saída caminhando, teto, câmera, catálogo, colisão, oclusão e suspensão do render aprovados; segunda medição renderizada 60,03 FPS no interior, p95 17,944 / p99 18,384 ms, 0 quadros >33,3 ms |
| Porto — Union | 1 | Concluído | [Foto final](measurements/interior-standard-0920/harbor-final-ClothingRoom0.png); planta própria, dinheiro, compra, física, profundidade e suspensão aprovadas; 60,01 FPS, p95 17,693 / p99 18,071 ms, sem quadros estáveis acima de 33,3 ms |
| Porto — Banco North Pier | 1 | Concluído | [Foto final](measurements/interior-standard-0920/harbor-confirm-BankInterior.png); NPCs proporcionais, 400 aproximações, profundidade, guardas, cartão/gazua, cofre e R$ 10.000 sem duplicação aprovados. Confirmação 60,01 FPS, p95 17,959 / p99 18,899 ms, primeira visita 21,994 ms; pico anterior não se repetiu |
| Porto — Conveniência do posto | 1 | Concluído | [Foto final](measurements/interior-standard-0920/harbor-fuel-isolated-FuelInterior.png); atendente proporcional, planta própria, 192 aproximações, dinheiro, profundidade e caixa com cobrança única aprovados. Medição isolada monitorada: 59,98 FPS, p95 17,614 / p99 18,349 ms, primeira visita 33,269 ms; nenhuma captura concorrente detectada |
| Porto — Garagem do chefe | 1 | Concluído | [Foto](measurements/interior-standard-0920/port-boss-garagem.png); 174 checks de gameplay/física/profundidade e cinco de save/pausa do alarme aprovados; 60,01 FPS, p95 18,144 / p99 18,491 ms |
| Porto — Casa do zelador | 1 | Concluído | [Foto final](measurements/interior-standard-0920/harbor-final-CemeteryKeeperInterior.png); dinheiro, 192 aproximações, profundidade e suspensão aprovadas; 60,01 FPS, p95 18,084 / p99 18,382 ms, sem quadros estáveis acima de 33,3 ms |
| Porto — Casa Westgate Garden | 1 | Concluído | [Foto final](measurements/interior-standard-0920/special-harbor-after-westgate_garden.png); planta própria, R$ 300, marcador, física, profundidade, save e suspensão aprovados; 59,98 FPS, p95 17,839 / p99 18,283 ms |
| Porto — Casa Quayside | 1 | Pendente de desempenho | [Foto final](measurements/interior-standard-0920/special-harbor-after-quayside_house.png); planta própria, R$ 700, marcador, física, profundidade, save e suspensão aprovados. Confirmação 57,38 FPS, p95 17,675 / p99 18,263 ms, com picos regionais já presentes no baseline; meta 60 não aprovada |
| Porto — Casa Canal North | 1 | Concluído | [Foto final](measurements/interior-standard-0920/special-harbor-after-canal_north.png); planta própria, R$ 1.500, marcador, física, profundidade, save e suspensão aprovados; 60,01 FPS, p95 17,936 / p99 18,298 ms |
| Porto — Galeria subterrânea / esgoto | 1 | Concluído | [Foto final](measurements/interior-standard-0920/special-harbor-after-sewer.png); física, profundidade, escada, arma por contato, save e combate isolado aprovados; 60,00 FPS, p95 16,785 / p99 16,993 ms |
| Montanha — Ammu-Nation | 1 | Concluído na reforma em linha | Foto atual e medições na seção de 22/09; entrada/saída, teto, catálogo, colisão, save e suspensão do render aprovados. Comparativo equivalente: p95 17,008 → 16,902 ms, p99 17,403 → 17,157 ms, 0 quadros >33,3 ms |
| Montanha — Último Abrigo, Boutique Alpina, Casacos da Vila | 3 | Concluídos | Plantas separadas, compras, contato com dinheiro, jogador/NPC, colisão e oclusão aprovados; 59,97–60,01 FPS. Evidências na seção de lojas abaixo |
| Montanha — Chalé dos Pinhais, Chalé da Encosta, Posto Florestal, Chalés 01–04 da vila | 7 | Concluídos | Sete plantas, 1.776 aproximações físicas, oclusão, save em disco, recompensas, entrada/retorno, suspensão e desempenho validados. Indicador compartilhado: 24 checks |
| Montanha — Abrigo dos lenhadores | 1 | Concluído | [Foto](measurements/interior-standard-0920/lumberjack_shelter-standard-final.png); coleta do machado, acesso/retorno, suspensão, 224 aproximações e profundidade jogador/NPC aprovados. Benchmark vigente reutilizado: 60,01 FPS, p95 16,972 ms / p99 17,375 ms; sem alteração de runtime posterior |
| Montanha — Cume Branco / lodge | 1 | Concluído | [Foto final](measurements/interior-standard-0920/mountain-final-ski_lodge.png); R$ 900, 304 aproximações, profundidade, aluguel, ski, ambas as saídas, save e respawn aprovados; 60,01 FPS, p95 17,014 / p99 17,264 ms, sem quadros acima de 33,3 ms |
| Montanha — Bunker | 1 | Concluído | [Foto final](measurements/interior-standard-0920/mountain-final-mountain_bunker.png); entrada órfã corrigida, câmera alinhada, iluminação renovada e R$ 1.500; rádio, 432 aproximações, profundidade e retorno aprovados; 60,01 FPS, p95 16,997 / p99 17,266 ms |
| Montanha — Caverna da Queda | 1 | Concluído | [Foto final](measurements/interior-standard-0920/mountain-final-mountain_mystery_cave.png); planta irregular inteira, lanternas e sólidos; RPG, fluxo, 640 aproximações e profundidade aprovados; 60,01 FPS, p95 16,952 / p99 17,130 ms |
| Montanha — Avião cargueiro externo | 1 | Concluído no fluxo real | [Foto final](measurements/interior-standard-0920/mountain-final-plane-cargo.png); render 1440×1000, convés compartilhado, luzes, SMG por contato, baú, 176 aproximações e profundidade aprovados. Primeira entrada real: pico 17,123 ms, primeira aproximação 40,962 ms; regime 60,00 FPS, p95 16,986 / p99 17,269 ms. Startup global de 1,7 s também ocorre sem estar no avião e permanece registrado separadamente |

Fora do total: IML instanciado sem acesso exterior encontrado; clínica 2D legada usada como base do hospital; restaurantes com mesas externas sem salão interno conectado. Se um acesso jogável for confirmado, atualizar esta classificação.

## Lote inicial: documentação e textos

- [x] Skill criada e instalada em `C:/Users/rafae/.codex/skills/padrao-interiores/SKILL.md`.
- [x] Cópia versionada em `docs/skills/padrao-interiores/SKILL.md`; ambas passaram no validador oficial.
- [x] AGENTS.md exige carregar a skill em trabalhos de interiores e seus acessos.
- [x] Entrada/saída das casas e entrada aberta da garagem do chefe usam E. Teste compartilhado de keycap: 10 checks aprovados na etapa anterior; inclui controle, remapeamento, ocultação e restauração de estilo.
- [x] Letreiro da Union e variante de inverno sem categorias decorativas. Mudança apenas de texto.
- [x] Foto antes e depois da Union, mesma sala e enquadramento, render Vulkan Mobile / RTX 4060 Laptop / 1280×800.
- [x] Fotos atuais das duas referências escolhidas.
- [ ] Fotos no fluxo integrado, com jogador, e visitas a cada acesso físico.
- [ ] Validação física e de oclusão por ambiente.
- [ ] Benchmark comparável antes/depois para mudanças de runtime.

### Union — correção parcial

Antes: [union-before.png](measurements/interior-standard-0920/union-before.png).

Depois: [union-after.png](measurements/interior-standard-0920/union-after.png).

As fotos são de salas reais instanciadas isoladamente, sem jogador. Servem para revisar arte e letreiro, não para aprovar câmera de gameplay, colisão, profundidade ou FPS. A Union ainda mostra uma leitura excessivamente superior/plana nesta captura; investigar enquadramento e primeiro render antes de migrar câmera, pois caches e interpolação também podem alterar a vista.

### Pendência concreta de desempenho

Com autorização explícita do usuário, os oito processos antigos de testes (eventos de cemitério e inspeção de animação) foram encerrados após conferência dos comandos; o editor foi preservado. Baseline do chalé aprovado na cena MountainPass real, Vulkan Mobile / RTX 4060 Laptop / 1280×720, limite 60 FPS, VSync ligado, cinco segundos de aquecimento e amostra de 30 segundos: **30,06 FPS**, p50 **33,315 ms**, p95 **34,770 ms**, p99 **36,853 ms**, máximo **49,850 ms**, 458/902 quadros acima de 33,3 ms e nenhum acima de 66,7 ms. Desempenho ainda não aprovado: não atende à meta de 60 FPS. Evidências: [log](measurements/interior-standard-0920/cabin-baseline.log), [tempos brutos](measurements/interior-standard-0920/cabin-baseline.json), [foto](measurements/interior-standard-0920/cabin-baseline.png).

## Ordem inicial de trabalho

### Piloto solicitado: câmera do chalé

- Câmera ortográfica centralizada, sem giro lateral, mesma direção da garagem; tamanho 11,5 para enquadrar a planta do chalé. Materiais, luzes e geometria preservados.
- Timer da lareira não substitui mais render contínuo quando há atores no viewport compartilhado. Sala vazia continua suspensa.
- Contrato renderizado após correção: **0 falhas, 17 grupos sólidos, 136 aproximações varridas**; oclusão com jogador e NPC aprovada com controle positivo de visibilidade.
- Gameplay MountainPass: **0 falhas** em entrada, spawn, perímetro, circulação, coleta das três armas, saída, reentrada, respawn e restauração de save. A execução emitiu avisos de recursos ainda vivos no encerramento; isso não está aprovado como ausência de vazamentos do mundo completo.
- Fotos: [antes diagonal](measurements/interior-standard-0920/cabin-reference.png), [depois alinhado](measurements/interior-standard-0920/cabin-aligned.png), [com jogador no gameplay](measurements/interior-standard-0920/cabin-aligned-gameplay.png). A foto de gameplay foi feita após coleta, com avisos funcionais na tela; a vista geral é uma captura isolada do mesmo interior.
- Logs: [colisão e oclusão](measurements/interior-standard-0920/aligned-contract-after.log), [fluxos reais](measurements/interior-standard-0920/aligned-gameplay.log).
- Piloto visual aprovado pelo usuário; propagação autorizada. As sete fachadas ainda usam a mesma sala; separar sua identidade faz parte da migração.
- FPS continua não aprovado: baseline de 30,06 FPS registrado acima. Não confundir passagem dos testes físicos/visuais com desempenho aprovado.

### Primeiro ajuste da caverna — câmera e RPG

- [x] Câmera usa a direção alinhada do padrão, finalizada antes da projeção física.
- [x] RPG flutuante com oscilação vertical, rotação e círculo dourado legível. Modelo e área de contato sobre o mesmo piso livre, à frente do estojo.
- [x] Coleta ao caminhar, sem exigir E. Interação opcional usa indicador curto. Jogador morto ou em diálogo não recebe recompensa.
- [x] Fluxo real: 30 checks, zero falhas, incluindo exatamente quatro foguetes, controle após equipar, save, reconstrução sem duplicação e saída. [Log](measurements/interior-standard-0920/cave-contact-validation-fixed.log).
- [x] Oclusão do jogador e NPC explicitamente testada na caverna: zero pixels diferentes atrás do anteparo; controles visíveis de 1.725 e 1.034 pixels. Render ocupado contínuo; sala desativada suspensa. [Contrato renderizado](measurements/interior-standard-0920/cave-final-depth.log). As 136 aproximações reportadas pelo teste pertencem ao chalé; não são cobertura de todos os sólidos da caverna.
- [x] Regressão do coletável compartilhado no avião: zero falhas em flutuação, coleta, munição e persistência. Teste headless funcional, não benchmark. [Log](measurements/interior-standard-0920/shared-pickup-plane-regression.log).
- [x] Regressão renderizada no chalé após ajustar a flutuação compartilhada: 32 checks, zero falhas, incluindo coleta das três armas por contato, circulação, saída, suspensão vazia, reentrada e save. [Log](measurements/interior-standard-0920/cabin-pickup-regression.log). Novo comparativo de desempenho do chalé e do abrigo continua pendente.
- [x] Fotos reais no gameplay: [antes](measurements/interior-standard-0920/cave-baseline.png), [depois](measurements/interior-standard-0920/cave-final.png).
- [ ] Reforma artística completa e revisão de todos os sólidos do cenário. Não contar este ajuste como caverna concluída.
- [ ] Meta de 60 FPS. Comparativo abaixo permanece insuficiente para aprovação absoluta.

| Caverna / amostra de 30 s | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 ms | >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| Antes | 31,59 | 33,014 | 34,937 | 40,357 | 54,196 | 373/948 | 0 |
| Depois final | 30,09 | 33,281 | 35,441 | 37,385 | 49,844 | 441/903 | 0 |

Mesma máquina, renderer, cena real, resolução e harness do baseline do chalé. p95 aumentou 1,44%, p99 caiu 7,36%; média de FPS caiu 4,77%. Causa da limitação próxima de 30 FPS ainda não isolada. Não há aprovação de 60 FPS. [Log final](measurements/interior-standard-0920/cave-final.log), [amostras](measurements/interior-standard-0920/cave-final.json). Execuções do mundo completo ainda emitem avisos de recursos vivos no encerramento; ausência de vazamentos permanece não validada.

### Próximos lotes

1. Validar as referências no gameplay e resolver apresentação contínua sem perder desempenho.
2. Union e lojas de inverno: câmera, escala, manequins e profundidade; reaproveitar a base validada.
3. Northgate Auto e bombeiros: maiores diferenças de construção 2D/3D.
4. Hospital, delegacia, casas e zelador.
5. Banco, conveniência, lojas de armas, garagem do chefe e ambientes especiais de montanha/esgoto.

A cada lote atualizar fotos, checks e contadores; não confundir quantidade de portas, lugares físicos, scripts compartilhados e interiores aprovados.

## Sete cabanas distintas — implementação de 20/09

As seis cabanas adicionais são construídas na primeira entrada, com IDs estáveis por fachada. O chalé aprovado conserva o ID antigo e suas três armas, mantendo compatibilidade com saves anteriores. Salas vazias ficam sem processamento e render. O enquadramento agora mostra a sala inteira e a câmera não atravessa o vazio entre fachada e interior.

| Lugar | Identidade | Recompensa | Foto real |
|---|---|---|---|
| Chalé dos Pinhais | Refúgio dos caçadores aprovado | Rifle, machado e faca | [Foto](measurements/interior-standard-0920/mountain_cabin-unique.png) |
| Chalé da Encosta | Dormitório a leste e mesa de trabalho a oeste | $ 5.000 | [Foto](measurements/interior-standard-0920/mountain_cabin_encosta-unique.png) |
| Posto Florestal | Mesa de levantamento e arquivo de campo | $ 850 | [Foto](measurements/interior-standard-0920/mountain_cabin_forest-unique.png) |
| Chalé 01 | Bancada de pesca e caixas de equipamento | $ 450 | [Foto](measurements/interior-standard-0920/mountain_cabin_village_1-unique.png) |
| Chalé 02 | Máquina de costura e rolos de tecido | $ 1.200 | [Foto](measurements/interior-standard-0920/mountain_cabin_village_2-unique.png) |
| Chalé 03 | Piano vertical e espaço de ensaio | $ 650 | [Foto](measurements/interior-standard-0920/mountain_cabin_village_3-unique.png) |
| Chalé 04 | Mesa de revelação e câmera em tripé | $ 1.800 | [Foto](measurements/interior-standard-0920/mountain_cabin_village_4-unique.png) |

- `test_distinct_mountain_cabins.gd`: **0 falhas, 7 layouts diferentes e 1.776 aproximações físicas**, com jogador e NPC. Inclui acesso real, spawn, rota de recompensa, valores exatos, retorno à fachada correta, enquadramento integral e suspensão vazia. [Log](measurements/interior-standard-0920/distinct-cabins-final.log).
- Oclusão renderizada de jogador e NPC com controle positivo em cada cabana: aprovada. As fotos acima mostram o gameplay real.
- Baseline atualizado imediatamente antes da expansão: **60,01 FPS**, p95 **17,127 ms**, p99 **18,110 ms**, máximo **27,472 ms**. A queda para 30 FPS da rodada anterior não se repetiu; não atribuir sua causa a uma correção sem evidência. [Baseline](measurements/interior-standard-0920/cabins-expansion-before.log).
- Depois: todas as sete cabanas em **60,01–60,03 FPS**, p95 **16,912–17,036 ms**, p99 **17,102–17,396 ms**, sem quadros acima de 33,3 ms nas amostras estáveis de 30 segundos. Máximo na primeira visita: **24,564–50,867 ms**; há picos de entrada registrados, sem escondê-los no aquecimento. [Rota e métricas](measurements/interior-standard-0920/cabins-route.log).
- Save em disco e reconstrução das seis novas cabanas: **0 falhas**, R$ 9.950 preservados sem duplicação. [Log](measurements/interior-standard-0920/distinct-cabin-save.log). O chalé original passou novamente por seus 32 checks de gameplay, incluindo armas, circulação, save, respawn e retorno. [Log](measurements/interior-standard-0920/cabin-gameplay-final.log).
- Indicador efetivo de BuildingEntrance: a rodada anterior de 16 checks foi substituída pela correção solicitada pelo usuário — retângulo laranja arredondado sem letras. **24 checks passaram** no formato final. [Log vigente](measurements/interior-standard-0920/rounded-door-marker-checks.log).
- O baseline `harbor-before-WorkshopInterior` é **inválido e não deve ser utilizado**: a fachada MotorWorkshop não expõe a porta do interior legado. Northgate Auto permanece no inventário como baia externa acessível de serviço, não como aquela instância de sala.

## Verificações finais do porto — em andamento

- `harbor-directed-final.log`: **0 falhas / 1.120 aproximações**, cobrindo clínica (480), bombeiros (240) e banco (400), com oclusão renderizada e controles positivos para jogador e NPC. Banco com atendentes/guardas proporcionais e clínica sem o multiplicador antigo de 1,3 nos funcionários.
- `harbor-final-physical.log`: garagem (1.008), zelador (192), Ammu-Nation (160) e conveniência (192) passaram seus casos físicos e de profundidade. As duas falhas daquele lote eram na admissão dos bombeiros e foram corrigidas, com nova aprovação dirigida acima. Não tratar o log antigo inteiro como aprovado.
- `police-directed-physics.log`: **0 falhas / 2.384 aproximações** na delegacia.
- `fire-trucks-controls-final.log`: **0 falhas / três baias**. Entrada a pé, embarque, condução real pelo portão, retorno ao acesso correspondente sem duplicar caminhão, desembarque e cura. O teste antigo usava a ação obsoleta `ui_up`; passou a usar `move_up` e aguardar a animação nativa antes de acelerar.
- `garage-weapons-final.log`: **0 falhas**. Entrada guarda arma e apaga lanterna; saque, ataque, troca e recarga bloqueados; inventário preservado na saída; restauração/respawn e invulnerabilidade de Maciota/mecânico conferidos.
- `bank-fuel-payout-final.log`: **0 falhas**. Modelos proporcionais preservam mãos na arma e disparos reais; cartão, fechadura e caminhada até o cofre funcionam. As pilhas pagam R$ 10.000 uma única vez, com conquistas contabilizadas separadamente (R$ 100 e R$ 200 nesta partida). Caixa deslocado da conveniência paga R$ 180 sem duplicação. O atendente da conveniência também recebeu proporções ajustadas. Recompensas de chão atualizam diretamente o saldo do HUD, preservando seu comportamento de coleta.
- Primeira rodada final dos nove ambientes concluída: [comparativo, qualidade efetiva e pendências](measurements/interior-standard-0920/harbor-performance-report.md). Delegacia, clínica e Ammu-Nation exigem confirmação dos picos; banco exige conferir primeira visita e conveniência aguarda captura da correção de roupa. Os resultados aprovados já constam na contagem.

## Lojas de inverno — três ambientes independentes

| Lugar | Recompensa | Foto real |
|---|---:|---|
| Último Abrigo | $ 750 | [Foto](measurements/interior-standard-0920/mountain_outfitters-standard.png) |
| Boutique Alpina | $ 1.250 | [Foto](measurements/interior-standard-0920/mountain_boutique-standard.png) |
| Casacos da Vila | $ 450 | [Foto](measurements/interior-standard-0920/mountain_village_outfitters-standard.png) |

Plantas diferentes, manequins com proporção humana, câmera alinhada e caixa funcional. Teste integrado: **0 falhas / 3 layouts distintos**; compras, contato com dinheiro, colisão de jogador/NPC, oclusão com controle positivo, retorno à própria fachada e sala vazia suspensa. [Log final](measurements/interior-standard-0920/clothing-standard-verified.log). As execuções anteriores expuseram um erro real: o corpo da prévia de roupas era admitido como residente; corrigido no filtro de residentes da sala, sem desabilitar a prévia.

Medição real, Mobile / RTX 4060 Laptop / 1280×720 / VSync e limite 60: baseline compartilhado anterior **60,01 FPS**, p95 **16,964**, p99 **17,297 ms**. Depois: Último Abrigo **60,01 / 17,077 / 17,320**; Boutique **60,01 / 17,047 / 17,357**; Casacos **59,97 / 17,163 / 17,957** (FPS / p95 / p99 em ms). Nenhum quadro estável acima de 33,3 ms; máximos de primeira visita **29,054 / 30,299 / 27,152 ms**. [Log e identificação do hardware](measurements/interior-standard-0920/shops-lumberjack-after.log).

O mesmo log mede o abrigo dos lenhadores: antes **60,01 FPS**, p95 **16,983**, p99 **17,292 ms**; depois **60,01 FPS**, p95 **16,972**, p99 **17,375 ms**. A validação física e de profundidade foi concluída no lote de seis lugares abaixo; o comparativo final da integração permanece pendente.

## Lote final da montanha — seis lugares

Todos usam câmera ortográfica alinhada no eixo frontal, direção relativa `(0,18,15)`, e atores 3D compartilhando profundidade com o cenário. O tamanho ortográfico e a textura variam conforme a dimensão da planta, sem mudar o padrão visual. Renderização contínua enquanto ocupado; interiores vazios suspendem o viewport e o avião vazio conserva imagem estática. Esses modos não são uma medição de FPS nem da taxa física.

| Lugar | Textura 3D | Tamanho ortográfico | Identidade visual |
|---|---|---:|---|
| Abrigo dos lenhadores | 1080×750 | 11,5 m | Alojamento de madeira, beliches, fogão e ferramentas |
| Cume Branco | 1440×1000 | 14,2 m | Salão de ski, lareira, lustres e equipamentos |
| Estação Zero | 1280×960 | 17,5 m | Bunker militar, comando, rádio e dormitórios |
| Caverna da Queda | 1280×960 | 14,5 m | Contorno rochoso irregular, acampamento e lanternas |
| Ammu-Nation da serra | 1440×1000 | 16,4 m | Loja de armas em madeira, balcão, ilha e fogão |
| Avião cargueiro | 1440×1000 | 36 m | Fuselagem, convés elevado, duas fileiras de carga e luzes de emergência |

| Lugar | Coletável | Foto real | Estado da validação |
|---|---|---|---|
| Abrigo dos lenhadores | Machado flutuante | [Foto](measurements/interior-standard-0920/lumberjack_shelter-standard-final.png) | 224 aproximações jogador/NPC, controles de profundidade, rota da arma, entrada e saída aprovados |
| Cume Branco | R$ 900, além do equipamento de ski | [Foto](measurements/interior-standard-0920/ski_lodge-standard-final.png) | 304 aproximações, profundidade, recompensa, aluguel, equipamento, pistas, retorno e recuperação de save aprovados |
| Estação Zero | R$ 1.500 | [Foto](measurements/interior-standard-0920/mountain_bunker-standard-final.png) | 432 aproximações, profundidade, dinheiro, rádio e retorno aprovados |
| Caverna da Queda | RPG com quatro foguetes | [Foto](measurements/interior-standard-0920/mountain_mystery_cave-standard-final.png) | 640 aproximações, profundidade e rota real de coleta aprovados; contorno irregular, caixas, cama, rochas e estalagmites bloqueiam |
| Ammu-Nation da serra | Faca flutuante | [Vendedor e jogador](measurements/interior-standard-0920/ammunation-human-scale.png) | 176 aproximações, profundidade, contato, medidas do vendedor, compra e proteção contra cobrança repetida aprovados |
| Avião cargueiro | SMG e baú de R$ 1.800 | [Foto central](measurements/interior-standard-0920/mountain-final-plane-cargo.png) | 176 aproximações, profundidade jogador/NPC, rampa, SMG, baú e suspensão após saída do último NPC aprovados; regime estável e reentrada real aprovados, inicialização global com ressalva abaixo |

`test_remaining_mountain_standard.gd` aprovou as quatro primeiras salas, totalizando **1.152 aproximações** e oclusão com controle positivo para jogador e NPC. [Log](measurements/interior-standard-0920/mountain-standard-contract.log). A única falha da execução completa revelou a loja criada antes do jogador: a referência permanecia nula, impedindo integração do ator. Corrigido o reencontro do jogador no início do processamento da loja. Na execução dirigida seguinte, profundidade e 176 aproximações passaram; a compra resultou em saldo diferente do teste porque a conquista **BLINDADO** também paga R$ 50. A expectativa agora contabiliza recompensas do catálogo e verifica que uma segunda compra de colete cheio não cobra novamente. [Log da investigação](measurements/interior-standard-0920/ammunation-standard-contract.log).

O vendedor das duas Ammu-Nation mede **1,80 m de altura e 0,677 m de largura máxima**, em lugar do corpo excessivamente largo. A altura efetiva do modelo do jogador nesse adaptador é aproximadamente 1,73 m. O ajuste é de corpo/cabeça, sem mudar a escala global do jogador ou da loja.

A reexecução dirigida da Ammu-Nation e caverna terminou com **0 falhas / 816 aproximações**: inclui compra, proteção contra cobrança repetida e o novo contorno físico irregular da caverna. [Log final](measurements/interior-standard-0920/ammo-cave-final-contract.log). O conjunto final das cinco salas soma **1.776 aproximações físicas**, sem contar a versão antiga substituída da caverna. O fluxo específico do Cume Branco também terminou com **0 falhas**: aluguel, equipamento, pistas, retorno, oclusão real da lareira, recuperação de spawn inválido e restauração após respawn. [Log](measurements/interior-standard-0920/lodge-final-gameplay.log).

`test_plane_standard_gameplay.gd`: **0 falhas, 176 aproximações**, com NPC admitido automaticamente no mesmo viewport, pés no convés elevado, controle positivo de visibilidade, entrada/saída contínuas, ação remapeada do baú e coleta da SMG por contato. A rodada final inclui as luzes de emergência e confere que o NPC remanescente mantém o render ativo após a saída do jogador, e que a saída do último NPC restaura sua apresentação e suspende o render contínuo. [Log final](measurements/interior-standard-0920/plane-final-gameplay.log). Construção gradual preservada: **0 falhas**, 23 etapas em 12 quadros, máximo de duas etapas por quadro e pico de 4,823 ms; um quadro excedeu o orçamento interno de 2 ms, nenhum excedeu 16,667 ms. Esse teste headless verifica apenas a construção, não certifica FPS. [Log](measurements/interior-standard-0920/plane-final-staging.log).

Baselines em gameplay real, RTX 4060 Laptop / Vulkan Mobile / 1280×720 / limite 60 e VSync ligado, amostra estável de 30 segundos separada da primeira visita:

| Cenário | FPS | p95 / p99 (ms) | Máximo estável (ms) | >33,3 / >66,7 ms | Máximo primeira visita (ms) |
|---|---:|---:|---:|---:|---:|
| Estação Zero | 60,01 | 17,030 / 17,440 | 29,627 | 0 / 0 | 46,854 |
| Caverna | 59,92 | 17,004 / 17,959 | 70,255 | 2 / 1 | 50,825 |
| Ammu-Nation serra | 60,01 | 17,008 / 17,403 | 32,353 | 0 / 0 | 22,754 |
| Avião | 60,01 | 16,964 / 17,244 | 21,627 | 0 / 0 | 1.385,063 |

Dados brutos: `mountain-batch-before-*.json`, `gunshop-before-ammunation.json` e `mountain-before-plane.json`, na pasta de medições. Baseline do lodge preservado em `special-before-ski_lodge.json`.

### Desempenho final da montanha

Mesma RTX 4060 Laptop, Godot 4.7.2 Mobile, 1280×720, limite 60 e VSync ligado. Física confirmada em **60 Hz**. Cada amostra estável tem 30 segundos, além de cinco segundos de primeira visita e cinco de aquecimento. Render contínuo ocupado acompanha o jogo; não há limite artificial de 12/15/30 Hz nestes interiores.

| Lugar | FPS antes → depois | p95 antes → depois (ms) | p99 antes → depois (ms) | Máximo estável depois (ms) | Quadros >33,3 / >66,7 ms | Pico primeira visita depois (ms) |
|---|---:|---:|---:|---:|---:|---:|
| Abrigo dos lenhadores | 60,01 → 60,01 | 16,983 → 16,972 | 17,292 → 17,375 | 18,636 | 0 / 0 | 17,166 |
| Cume Branco | 60,01 → 60,01 | 17,015 → 17,014 | 17,378 → 17,264 | 17,679 | 0 / 0 | 21,819 |
| Estação Zero | 60,01 → 60,01 | 17,030 → 16,997 | 17,440 → 17,266 | 24,417 | 0 / 0 | 21,538 |
| Caverna | 59,92 → 60,01 | 17,004 → 16,952 | 17,959 → 17,130 | 17,775 | 0 / 0 | 33,512 |
| Ammu-Nation serra | 60,01 → 60,00 | 17,008 → 17,063 | 17,403 → 17,615 | 22,808 | 0 / 0 | 26,023 |
| Avião | 60,01 → 60,01 | 16,964 → 16,968 | 17,244 → 17,177 | 18,285 | 0 / 0 | 1.679,163 |

As cinco salas passaram os contratos funcionais, físicos, visuais e de desempenho. Logs finais: [quatro interiores](measurements/interior-standard-0920/mountain-final-performance.log), [abrigo com medição reutilizada](measurements/interior-standard-0920/shops-lumberjack-after.log). p50 final: Ammo **16,666**, lodge **16,671**, bunker **16,665**, caverna **16,667 ms**; amostras completas em `mountain-final-*.json`.

O avião passou o regime estável (p50 **16,669 ms**). O pico inicial aumentou de **1.385,063 para 1.679,163 ms** e a confirmação instrumentada registrou **1.701,384 ms**. Todos ocorrem no primeiro quadro da amostra, imediatamente após a construção da cena e antes da apresentação inicial; o harness mistura a inicialização do mundo com a primeira visão da aeronave. [Log principal](measurements/interior-standard-0920/plane-final-performance.log). [Foto central real com jogador, carga, luzes, SMG e baú](measurements/interior-standard-0920/mountain-final-plane-cargo.png).

A confirmação manteve a rota original e acrescentou saída e reentrada reais pela rampa depois de inicializar o mundo: **pico de entrada 17,391 ms**, seguido de **60,003 FPS / p50 16,669 / p95 16,979 / p99 17,232 / máximo 17,911 ms**, sem quadros acima de 33,3 ms nos 30 segundos estáveis. A construção CPU da vista custou **1,085 ms**; no primeiro quadro de 1,7 s, a fila de detalhes do avião ainda estava em **0/23 etapas**. A primeira etapa ocorreu depois e custou **10,335 ms**. O primeiro pico antecede métricas válidas de render; não permite atribuir sua causa a CPU, GPU ou shaders. Há uma limitação de inicialização global registrada, sem evidência de travamento local na entrada do avião. Não se alterou o carregador global para esconder esse custo.

Confirmação **sem processos de teste concorrentes**, verificada a cada dois segundos; o editor permaneceu aberto. [Log e reentrada](measurements/interior-standard-0920/plane-cold-confirm.log), [amostras instrumentadas](measurements/interior-standard-0920/plane-cold-confirm-plane-cold-trace.json), [monitor de processos](measurements/interior-standard-0920/plane-cold-confirm-processes.json). O harness carrega MountainPass diretamente e não chama `GameLoading.begin`; a ausência de tela de carregamento é inferida desse fluxo, não uma captura do primeiro quadro.

**Primeira visita normal, sem visita prévia ao avião:** carregamento mantido no spawn natural, com startup registrado separadamente; depois primeira aproximação exterior e entrada caminhando pela rampa. Pico de startup **1.700,189 ms** mesmo com jogador fora do avião; pico da primeira aproximação **40,962 ms**, pico da primeira entrada **17,123 ms**. Regime estável de 30 segundos: **60,002 FPS / p50 16,669 / p95 16,986 / p99 17,269 / máximo 17,948 ms**, zero quadros acima de 33,3/66,7 ms. Processo encerrado com código 0 e monitor sem sobreposição de outros testes. [Log](measurements/interior-standard-0920/plane-first-normal.log), [amostras completas](measurements/interior-standard-0920/plane-first-normal-plane-first-visit.json), [monitor](measurements/interior-standard-0920/plane-first-normal-processes.json).

O avião está aprovado nos fluxos reais, primeira visita e regime estável. O pico de 40,962 ms da primeira aproximação permanece registrado; a inicialização global de aproximadamente 1,7 s continua **não certificada**, sem causa interna isolada e sem alterações fora do escopo para escondê-la. A rodada original e todas as confirmações foram preservadas.
