# Anti-aliasing e desempenho — 11/09/2026

A meta continua sendo 60 FPS sustentados, com orçamento de 16,67 ms por quadro. As médias melhoraram substancialmente, mas os picos ainda reprovam essa meta. A configuração entregue usa Mobile, MSAA 2× e mantém limite de 60 FPS com interpolação física. Não há certificação de todas as cenas, combate, transições ou todas as configurações de hardware.

## Resultado integrado

Godot 4.7.2, Vulkan Mobile, RTX 4060 Laptop, 1920×1080, MSAA 2×, VSync desligado para medir capacidade. O editor permaneceu aberto; nenhuma outra execução do jogo rodava durante a matriz final. Cada cenário aquece por 120 quadros e mede 300. As áreas externas foram medidas também com a serra residente.

| Cenário | FPS médio sem limite | p90 (ms) | p99 (ms) |
|---|---:|---:|---:|
| centro | 98.5 | 13.39 | 17.91 |
| terminal | 67.1 | 17.22 | 21.74 |
| cais | 88.6 | 17.45 | 19.58 |
| porto_sul | 87.3 | 17.77 | 20.02 |
| cemiterio | 80.6 | 15.91 | 31.42 |
| acesso_norte | 91.8 | 15.79 | 36.25 |
| serra | 82.2 | 16.07 | 20.42 |
| cume | 77.2 | 16.68 | 20.33 |
| terminal_night_storm | 63.2 | 18.11 | 20.91 |
| porto_sul_night_storm | 109.4 | 13.79 | 18.13 |
| interior_GarageInterior | 98.3 | 16.36 | 19.92 |
| interior_PoliceInterior | 144.4 | 9.30 | 27.45 |
| interior_ClinicInterior | 152.3 | 9.13 | 13.40 |
| interior_WorkshopInterior | 136.4 | 9.78 | 28.60 |
| interior_FireStationInterior | 137.3 | 9.72 | 13.73 |
| interior_AmmunationInterior | 147.1 | 9.20 | 12.14 |
| interior_MorgueInterior | 161.4 | 9.08 | 12.74 |
| interior_CemeteryKeeperInterior | 165.1 | 8.65 | 13.60 |
| interior_BankInterior | 154.9 | 9.06 | 13.17 |
| interior_FuelInterior | 142.5 | 9.34 | 13.90 |
| interior_ClothingRoom0 | 153.0 | 9.04 | 11.39 |

Dados: `final-matrix.json`. Sua última linha de direção é inválida (distância zero após a sequência de interiores) e foi excluída acima. O roteiro foi corrigido para dirigir antes de entrar nos interiores e só aprovar se houver deslocamento real. A medição independente `event-redraw.json`, com renderização instrumentada, registrou 87,1 FPS parado e 66,7 dirigindo, com 853 px percorridos.

A matriz com limite de 60 FPS está em `final-capped-matrix.json`. Ela mede o ritmo efetivo de apresentação; 60 de média não significa ausência de quadros lentos. Valores dos monitores globais `physics_ms`/`process_ms` podem reter a última amostra do Godot entre atualizações e não devem ser somados nem usados como duração de cada quadro. Os percentis vêm de timestamps contínuos entre `process_frame`, incluindo o custo da própria amostragem.

## Causas corrigidas

- O desenho de todas as ruas era reenviado como uma lista enorme, mesmo com a câmera vendo só parte do mapa. Malhas por setores de 512 px permitem descarte das áreas distantes. O custo medido do viewport principal caiu de aproximadamente 7,2 para 1,7–2,0 ms de CPU nos ensaios isolados. O shader de recorte das pontes continua herdado pelas malhas.
- Vários viewports de personagens e estações renderizavam continuamente fora da tela. Agora respeitam visibilidade; os estados de animação e renderização sob demanda foram preservados.
- Cruzamentos e pedestres faziam buscas repetidas em grupos inteiros. Índices espaciais limitam candidatos; a demanda dos braços de um cruzamento reaproveita o índice do mesmo tick, mantendo ocupantes atuais.
- O grafo de navegação fazia interseções quadráticas. O caso de regressão passou de 157.641 para 5.998 pares candidatos, mantendo conexões e rotas; construção do minimapa distribuída entre quadros e publicação do grafo completo ao terminar. O desenho também descarta ruas fora da área do minimapa.
- Veículos repetidos reconstruíam as mesmas malhas. O cache guarda geometria inicial, mantém pinturas independentes e invalida lotes quando a malha fonte muda. Modelos com referências de gameplay ou descendentes com script ficam fora do cache. Nove modelos comuns são preparados durante o carregamento, um tipo por quadro.
- A rotina das embarcações redesenhava cerca de 60 caixas a cada quadro. O desenho agora responde a transferência/queda de carga e troca de fase; a movimentação dos barcos continua sendo atualizada.
- A área de simulação acompanha câmera e zoom com margem; o entorno da porta exterior continua ativo em interiores. Donos de cruzamentos e suas cadeias de bloqueadores continuam acordados, assim como o entorno dos ônibus regionais.

## Validação

Passaram: referências (zero quebras), comparação visual das malhas 2D inclusive shader herdado (erro médio 0,000858; 0,21% dos pixels com diferença >0,15), índices de cruzamento (750 consultas), rotas equivalentes, preservação de cruzamentos reservados, área da câmera em três níveis de zoom, modelos com materiais/dano independentes, invalidação do cache, rodas/portas/reparo e menu/novo jogo/save/load. Rodoviária, estações, abertura e rotinas/LOD de pedestres também passaram durante a integração.

O teste de streaming dos veículos cumpriu suas asserções, mas registrou um erro de callback adiado em NPCMedicalCare ao destruir o cenário. O teste ferroviário legado também falhou; a mesma falha foi reproduzida na cópia anterior à integração, com o mesmo veículo parado na barreira física. Esses erros não foram escondidos nem convertidos em aprovação.

## Integração com trabalho concorrente

O commit contém apenas mudanças próprias. Algumas otimizações se sobrepõem a arquivos novos ou trechos ainda não commitados de outras sessões (rodoviária, estações, porto, acesso norte e preservação de reservas). Elas estão aplicadas no diretório de trabalho e registradas, somente como diferenças, em `shared-working-tree.patch`; os arquivos completos das outras sessões não foram incluídos neste commit. O patch é um registro para integração após esses arquivos serem versionados: não reaplicar sobre este diretório, que já contém as alterações. As medições usam o diretório completo.

## Pendências da meta

- Eliminar picos de 20–36 ms nas áreas externas e eventos esparsos nos interiores, com perfil específico de quadros lentos.
- Validar combate, perseguições, colisões em massa, tempestade na serra, entrada/saída de regiões e sessões prolongadas; os pontos desta matriz não cobrem todas as situações do jogo.
- A preparação inicial do mundo ainda tem etapas síncronas longas. O cache e o grafo assíncrono reduzem parte do custo, mas o carregamento completo ainda precisa de divisão das construções pesadas.
- Repetir em execução exportada e no hardware/resolução finais. Resultados de um editor em desenvolvimento não garantem um mínimo universal de FPS.

## Matriz limitada a 60 FPS

22 cenários, incluindo direção (611 px), exteriores com tempestade e 11 interiores. O processo terminou com código zero. Essa validação do roteiro não equivale a aprovação da meta.

| Cenário | FPS médio | p90 (ms) | p99 (ms) |
|---|---:|---:|---:|
| centro | 59.43 | 17.30 | 22.98 |
| terminal | 59.95 | 19.89 | 23.86 |
| cais | 59.97 | 19.34 | 23.94 |
| porto_sul | 60.00 | 18.31 | 23.03 |
| cemiterio | 60.00 | 17.41 | 34.36 |
| acesso_norte | 60.00 | 17.40 | 23.08 |
| serra | 60.00 | 17.34 | 22.50 |
| cume | 60.00 | 17.15 | 21.86 |
| driving | 59.59 | 21.00 | 24.43 |
| terminal_night_storm | 59.47 | 19.01 | 25.70 |
| porto_sul_night_storm | 60.02 | 20.70 | 26.03 |
| interior_GarageInterior | 58.46 | 17.60 | 27.05 |
| interior_PoliceInterior | 59.87 | 17.15 | 37.49 |
| interior_ClinicInterior | 59.99 | 17.25 | 21.47 |
| interior_WorkshopInterior | 60.00 | 17.19 | 21.39 |
| interior_FireStationInterior | 60.00 | 17.14 | 21.85 |
| interior_AmmunationInterior | 60.00 | 17.04 | 21.87 |
| interior_MorgueInterior | 59.88 | 17.17 | 21.77 |
| interior_CemeteryKeeperInterior | 60.02 | 17.14 | 23.09 |
| interior_BankInterior | 59.80 | 17.10 | 21.67 |
| interior_FuelInterior | 59.81 | 17.38 | 21.68 |
| interior_ClothingRoom0 | 59.63 | 17.18 | 39.48 |

Depois desta matriz, a margem de simulação dos pedestres fora da câmera foi reduzida a 120 px (veículos mantêm 360 px); pedestres a até 600 px dos ônibus regionais continuam ativos. A comparação seguinte verifica também a sincronização vertical, pois um limite de média não elimina atrasos de apresentação.

## Sincronização com o monitor

Foi testado deixar a apresentação acompanhar o monitor com VSync, sem teto adicional. Essa mudança em SettingsManager foi revertida após o teste isolado de movimento. O jogo mantém o limite de 60 FPS e a interpolação física ligada. A documentação do Godot distingue o [limite de renderização e VSync](https://docs.godotengine.org/en/stable/classes/class_engine.html#class-engine-property-max-fps) da [taxa fixa de simulação e sua interpolação](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/physics_interpolation_introduction.html). O monitor medido informa 159,962 Hz.

`vsync-pacing.json`: 100,9 FPS parado e 75,4 dirigindo; p99 de 18,84 e 20,48 ms, respectivamente. A física não foi acelerada nem os efeitos desligados. Esta comparação inclui a nova margem dos pedestres, portanto não atribui todo o ganho isoladamente ao VSync.

## Experimento sem teto adicional, com VSync

VSync ligado, apresentação sem teto adicional, física em 60 Hz, AA 2×, 1080p. A sequência completa terminou sem erros de script, com 752 px na fase de direção.

| Cenário | FPS médio | p90 (ms) | p99 (ms) |
|---|---:|---:|---:|
| centro | 99.9 | 13.61 | 16.66 |
| terminal | 70.5 | 16.67 | 20.08 |
| cais | 90.9 | 17.10 | 20.50 |
| porto_sul | 92.8 | 16.62 | 19.90 |
| cemiterio | 85.8 | 15.15 | 29.15 |
| acesso_norte | 94.7 | 15.13 | 37.60 |
| serra | 85.8 | 15.73 | 18.66 |
| cume | 77.2 | 16.61 | 19.74 |
| driving | 73.0 | 17.36 | 20.56 |
| terminal_night_storm | 63.6 | 18.09 | 23.17 |
| porto_sul_night_storm | 90.7 | 16.30 | 18.88 |
| interior_GarageInterior | 94.9 | 15.77 | 22.87 |
| interior_PoliceInterior | 144.0 | 9.37 | 16.22 |
| interior_ClinicInterior | 126.8 | 10.66 | 30.72 |
| interior_WorkshopInterior | 137.3 | 9.57 | 30.17 |
| interior_FireStationInterior | 133.4 | 9.86 | 13.97 |
| interior_AmmunationInterior | 132.9 | 9.81 | 15.06 |
| interior_MorgueInterior | 127.0 | 10.12 | 14.91 |
| interior_CemeteryKeeperInterior | 142.8 | 9.62 | 12.48 |
| interior_BankInterior | 134.8 | 11.06 | 13.40 |
| interior_FuelInterior | 134.8 | 9.93 | 13.69 |
| interior_ClothingRoom0 | 134.3 | 9.87 | 14.45 |

A média mais baixa foi 63,6 FPS no terminal à noite com tempestade; o maior p99 exterior foi 37,60 ms no acesso norte. A exigência de 60 FPS mínimos em toda situação permanece não atendida.

Após essa matriz, a busca da rua mais próxima pelo GPS também passou a consultar o índice espacial dentro dos limites originais de 350/450 px. Foram comparadas 300 consultas com o algoritmo completo, além das rotas e conexões: resultados idênticos. Nenhuma nova média de FPS é atribuída isoladamente a essa última alteração.

O erro de callback em NPCMedicalCare no teste de streaming foi reproduzido também na cópia anterior às otimizações (`performance-regression-0911/streaming-before.log`), confirmando que ele não foi introduzido pelo cache.

## Decisão final de cadência e carregamento

A configuração entregue mantém limite de 60 FPS e física interpolada a 60 Hz. No teste isolado de movimento, o avanço aparente apresentou JERK relativo 0,097 sem teto, contra 0,000 com teto 60. Assim, o teste sem teto serve para medir capacidade e não alterou a preferência final de cadência. Os resultados estão em `validation-results.json` (campo `motion`).

A última auditoria de carregamento com Vulkan não teve erros de referências/estradas nem órfãos: 3.107 ms de recursos + 5.639 ms adicionando a árvore + 11.379 ms para os primeiros 180 quadros = 20.125 ms. O primeiro quadro ainda levou 8.323 ms. Esse pico de preparação é uma pendência real; não foi contado como jogo a 60 FPS. O pré-aquecimento durante GameLoading protege o início da partida de parte das construções posteriores, mas não torna assíncrona a montagem inicial inteira.

Uma execução da suíte final atingiu o timeout de 120 s carregando pelo menu, seguida de erros de recursos BuildingEntrance/Bullet ao encerrar. A repetição isolada passou pelo fluxo inteiro em cerca de 35 s. Esse timeout intermitente permanece registrado como pendência de carregamento, além dos testes que passaram.

A importação gerou os UIDs novos, mas a reabertura do layout do editor acusou `Parse Error: Busy` em CarjackedDriver.tscn. O carregamento real do mundo e a repetição isolada dos menus passaram separadamente; a importação não está registrada como limpa. Os artefatos desta pasta recebem `.gdignore` para não importar capturas de diagnóstico como texturas do jogo.
