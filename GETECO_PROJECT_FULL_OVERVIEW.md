# GETECO — Visão Geral Completa do Projeto

> **Documento de Contexto Técnico, Arquitetura, Features e Estado Atual**  
> *Destinado a alimentar modelos de linguagem (ex.: ChatGPT/Claude) e desenvolvedores que precisam de compreensão integral e imediata do projeto sem perdas de contexto.*  
> Data de consolidação: **Setembro de 2026** | Versão da Engine: **Godot 4.7.2**

---

## 1. O que é o GETECO

O **GETECO** é um jogo de ação *top-down* em mundo aberto 2D/3D no espírito dos GTA clássicos (estilo GTA 1, GTA 2 e Chinatown Wars), ambientado em uma metrópole portuária viva e industrial interligada a uma região montanhosa de serra e neve por **streaming contínuo em tempo real** (sem telas pretas de transição).

O jogo combina a precisão e velocidade de colisão e controle da física 2D com a riqueza estética e de iluminação da modelagem 3D, apresentando um ecossistema urbano autônomo com pedestres, tráfego com semáforos inteligentes, perseguição policial de múltiplos escalões (1 a 6 estrelas), corpo de bombeiros, resgate médico com ambulâncias, legistas (coroner), ferro-velho funcional de recuperação de veículos, gangues territoriais, assaltos planejados e uma campanha narrativa com protagonista expressivo.

---

## 2. Stack Tecnológica e Decisões de Engenharia

| Componente | Tecnologia / Decisão | Detalhes Técnicos |
|---|---|---|
| **Motor de Jogo** | **Godot Engine 4.7.2** | Perfil Mobile/Forward+ (Vulkan), visando alta performance e esteira futura mobile. |
| **Linguagem** | **GDScript puro** | GDScript estático e tipado em praticamente 100% dos scripts vivos (>670 scripts). |
| **Simulação Física** | **2D Nativa** | `CharacterBody2D`, `Area2D`, `Path2D` para faixas de rodagem; gravidade zero; `physics_interpolation = true`. |
| **Apresentação Visual** | **3D Híbrida em SubViewports** | Modelos 3D com rigs e animações renderizados em `SubViewport`s isolados, projetados no mundo como sprites/canvases 2D. |
| **Áudio** | **Síntese Procedural** | Motores gerados via síntese harmônica física em tempo real, sem dependência de loops de samples repetitivos. |
| **Entrada e Menus** | **Godot CanvasItem / Theme** | Tipografia Barlow unificada; menus com pré-carregamento assíncrono (threaded prefetch). |
| **Gestão de Testes** | **Scripts SceneTree Standalone** | Mais de 760 arquivos de teste dedicados executados diretamente via linha de comando (`--script`), sem frameworks externos. |
| **Arquitetura de Pastas** | **Por Domínio Funcional** | Reorganizado em pastas de alto nível: `cars/`, `characters/`, `guns/`, `police/`, `emergency/`, `economy/`, `geodata/`, `systems/`, `world/`. |

---

## 3. A Decisão Técnica Central: "Física 2D com Apresentação 3D"

A espinha dorsal do projeto é o desacoplamento estrito entre simulação física e renderização visual:
1. **No Mundo 2D**:
   - Toda movimentação, detecção de colisões, raycasts de tiro, cones de visão e limites de calçadas operam em coordenadas 2D cartesianas.
   - O corpo do jogador (`Player.gd`) não gira o nó 2D (`rotation = 0` constante); a direção para onde ele olha ou mira controla exclusivamente a orientação da câmera/nó 3D interno.
2. **Dentro dos SubViewports 3D**:
   - Veículos (`BaseVehicle3DModel`), pedestres (`AnimatedPedestrian3D`) e armas possuem malhas 3D (`MeshInstance3D`), materiais PBR com shaders, deformações de impacto e esqueletos de animação.
   - Para manter alta taxa de quadros (60 FPS estáveis), a grande maioria dos `SubViewport`s opera em modo `UPDATE_ONCE` ou `UPDATE_DISABLED`, sendo renderizados sob demanda ou atualizados com orçamento de tempo fatiado via `PresentationBudget` (máximo de ~2000 µs por frame).

---

## 4. Estrutura de Domínios e Pastas

Após a grande reorganização de arquitetura executada em setembro de 2026, a base de código está segmentada em domínios limpos:

```
geteco/
├── ui/                   # Menus principais, HUD, inputs e telas de carregamento
├── characters/           # Player, pedestres com IA comportamental, rotinas diárias e roupas
├── cars/                 # Catálogo de veículos, física de condução (PlayerCar), desgaste e portas
├── guns/                 # Catálogo de 16 armas, balística, projéteis, combate melee e recarga
├── police/               # WantedManager (1-6 estrelas), policiais, viaturas e perseguições
├── emergency/            # Ambulâncias, bombeiros, rabecão (coroner), despacho e hospitais
├── economy/              # Lojas, caixas eletrônicos, compras, colecionáveis e inventário
├── geodata/              # Malhas viárias, semáforos inteligentes, postes de luz, pontes e mapa
├── systems/              # Autoloads globais, SaveManager, Settings, Localization, Streaming
├── audio/                # Motores procedurais, mixador de vozes de missão, rádio, sirenes
├── cutscenes/            # Cutscene de abertura fotográfica (v3 - 25 telas cinematográficas)
├── world/
│   ├── harbor/           # O distrito portuário vivo: prédios, gangue Cobras, banco, interiores
│   ├── mountain_pass/    # Região de serra/neve: estações de esqui, bunker, frio e tempestades
│   └── shared/           # Infraestrutura compartilhada entre biomas (ferrovia, vegetação, salvados)
├── tests/                # Suíte com mais de 760 testes automatizados de regressão e performance
├── tools/                # Scripts Python e utilitários (auditoria de referências, áudio, máscaras UV)
└── legacy/               # Código da geração anterior preservado para retrocompatibilidade de saves
```

---

## 5. Sistemas Centrais e Features de Gameplay

### 5.1. Movimentação e Condução
- **A Pé**: Sistema de caminhada com sincronização estrita de passadas ("gait") por deslocamento real de pixels, esquiva rápida, sistema de sprint com estamina e mira em 360 graus.
- **Ao Volante (`PlayerCar.gd`)**: Curva de torque realista, simulação de aderência dinâmica (`VehicleMotionSafety.grip()`), freio de mão com derrapagem controlada (drift), nitro limitado e física de colisão que amassa a geometria do carro de acordo com o vetor de impacto.
- **Câmera Dinâmica (`DynamicCamera.gd`)**: Ajuste automático de zoom conforme a velocidade do veículo, amortecimento suave de transições, vinheta neon noturna e modo overview tático em tela cheia (F9).

### 5.2. Arsenal e Combate (`guns/WeaponCatalog.gd`)
- **Catálogo com 16 Armas**:
  - *Corpo-a-corpo*: Punhos, Soco Inglês, Faca de Combate, Taco de Beisebol, Machado de Bombeiro (com detecção em arco cônico e janelas precisas de frame).
  - *Armas Leves*: Pistola 9mm, Revólver Magnum .44, Submetralhadora SMG, Espingarda Shotgun e Shotgun Serrada.
  - *Fuzis e Pesadas*: Fuzil de Assalto AK-47, M4A1 Militar, Rifle de Caça de Longo Alcance, Lança-Chamas com propagação de fogo contínuo e RPG explosivo.
  - *Arremesso*: Granadas de fragmentação com contagem de fusível e ricochete.
- **Balística Realista**: Redução gradual de dano com base na distância (`distance_damage()`), recargas manuais com áudio tático, marcas de impacto dinâmicas nas superfícies e ejeção de cápsulas 3D.

### 5.3. Polícia, Nível de Procurado e Resposta Pública (`police/` e `emergency/`)
- **Sistema de Nível de Procurado (`WantedManager.gd`)**:
  - 1 a 6 estrelas baseadas em pontos de infração acumulados.
  - Pequenos delitos (como colisões leves) expiram em 12 segundos se o jogador se afastar da visão policial.
- **5 Escalões da Polícia (`PoliceOfficer.gd`)**:
  1. *Ronda Comum*: Oficiais de trânsito e patrulha em sedãs.
  2. *Detetives à Paisana*: Veículos descaracterizados rápidos.
  3. *Tático / SWAT*: Vans blindadas, fuzis e capacetes balísticos.
  4. *Agência / FBI*: SUVs pretos com unidades de assalto pesado.
  5. *Forças Especiais / Exército*: Bloqueios de rua pesados com blindados e resposta letal contínua.
- **Serviços de Emergência Completos e Vivos**:
  - **Bombeiros**: Caminhões tanque que respondem a explosões reais, desenrolam mangueiras e utilizam canhões d'água (`VehicleWaterCannon`) para apagar chamas.
  - **Ambulâncias e Paramédicos**: Despachados para qualquer NPC ferido; usam macas físicas (`MedicalStretcher`), prestam socorro e transportam o paciente de volta ao hospital.
  - **Legistas (Coroner / Rabecão)**: Quando há fatalidades, o legista vai até o local, embala o corpo e o conduz à morgue para registro no livro de óbitos (`CoronerCare`).

### 5.4. Ferro-Velho do Neco e Reboque (`world/shared/salvage/`)
- Não existem menus instantâneos mágicos de reparo: o jogador opera um **caminhão guincho físico** com braço de engate operado por raycast.
- É possível rebocar veículos acidentados ou abandonados até o pátio de desmanche.
- **Prensa 3D Esmagadora**: Prensa hidráulica que amassa os carros fisicamente, concedendo pagamentos proporcionais ao estado da sucata. Guinchar e amassar viaturas policiais gera estrelas imediatas.

### 5.5. Gangues Territoriais e População Viva
- **Gangue Cobras (Harbor)**: Ocupam o enclave "Ashbend Court". Possuem sistema de reconhecimento territorial: aviso verbal de afastamento → agressão coordenada com armas brancas e de fogo → fuga tática se sofrerem perdas pesadas.
- **Lobos de Gelo (Mountain Pass)**: Milícia armada que domina as estradas serranas, mantendo barricadas na pista de pouso do cume e ocupando bunkers militares desativados.
- **Pedestres Autônomos (`AnimatedPedestrian3D`)**: Roupas variadas, rotinas de atravessar faixas de pedestre, fuga desesperada ao ouvir disparos e possibilidade de serem atropelados com consequências de resgate médico.

### 5.6. Os Mundos Interligados: Harbor & Mountain Pass
- **Harbor (Distrito Portuário)**:
  - Cidade costeira com indústrias pesadas, contêineres, ferrovia com trens de carga ativos (`HarborRailLine`), cais com o navio cargueiro "Northstar" (explorável a pé), cemitério gótico, restaurantes, lojas de roupas e delegacias acessíveis.
  - **Assalto ao Banco Central**: Sistema elaborado de roubo em etapas (infiltração, desarme de segurança, quebra de cofres, recolhimento de malotes e rota de fuga com cerco policial tático).
- **Mountain Pass (Passo da Montanha)**:
  - Bioma alpino com neve profunda, curvas sinuosas "hairpin", pistas escorregadias de gelo e sistema climático de nevasca com mecânica de **hipotermia**.
  - Cenários únicos: vila de chalés de esqui, teleférico funcional, madeireira abandonada, ponte suspensa sobre lago congelado, avião de carga bimotor militar acidentado (com interior modelado e teto rasgado para exploração) e um mistério envolvendo uma criatura oculta na névoa.
- **Streaming Contínuo (`ContinuousWorld.gd`)**:
  - Ao atravessar a colossal ponte estaiada (`HarborBridge`), a montanha é instanciada e carregada assincronamente em thread de fundo.
  - Veículos e tráfego que cruzam a ponte sofrem um **handoff suave de nós**, mudando de domínio sem sumir da visão do jogador.

### 5.7. Áudio Procedural e Imersão
- **Motores com Física de Ressonância**: Os veículos não usam amostras pré-gravadas simples de áudio. Cada classe de veículo (muscle, esportivo, caminhão diesel, ônibus urbano, viatura) possui geradores procedurais com faixas de RPM, explosões de cilindro, silvados de turbo e alívio de ar de freios pneumáticos.
- **Vozes e Diálogos (`audio/mission_voices/`)**: Sistema híbrido com vozes sintetizadas expressivas (`ExpressiveVoice.gd`) em fase de substituição por dublagem gravada em estúdio (Dante, Maciota e interlocutores), com sistema automático de atenuação (*ducking*) de -16 dB nos efeitos sonoros da cidade durante diálogos.

---

## 6. Narrativa e Personagens Canônicos

- **Dante Ferraz (29 anos)**: Protagonista. Ex-policial expulso da corporação após cruzar limites éticos para acobertar as atividades clandestinas do irmão. Chega ao porto de ônibus após cumprir penalidades.
- **Vicente "Vico" Ferraz (36 anos)**: Irmão mais velho de Dante. Líder de uma facção criminosa em ascensão ligada a contrabando pesado e rachas interestaduais. É a figura que move os passos de Dante.
- **Márcio "Maciota" Azevedo (48 anos)**: Mecânico experiente, despachante e informante respeitado da região portuária. É o mentor e contratante inicial de Dante.
  - *Regra Permanente de Design*: Maciota e seu mecânico assistente **são imortais** (protegidos contra qualquer dano de tiros, chamas, explosões ou atropelamentos).
  - *Zona Segura*: A Garagem do Maciota é estritamente desarmada; as armas do jogador são guardadas automaticamente ao entrar e devolvidas ao sair.
- **"Monaliza"**: É o **carro pessoal de Dante** (um cupê turbo estilizado em tons de azul e laranja), desbloqueado na missão "Primeiro Giro", com comportamento mecânico refinado e persistência garantida na garagem.

---

## 7. Pontos Fortes e Destaques de Engenharia (Strengths)

1. **Eficiência de Simulação 2D com Apelo Visual 3D**:
   - Entrega uma experiência visual rica em iluminação e perspectiva sem o custo proibitivo de colisão volumétrica tridimensional, permitindo dezenas de veículos e NPCs simultâneos na tela.
2. **Mundo Contínuo Verdadeiro (Sem Telas Pretas de Loading)**:
   - A transição do ambiente urbano ensolarado do porto para as montanhas geladas ocorre sem quebrar a ação ou pausar o jogo.
3. **Cadeia Sistêmica Realista e Autônoma**:
   - A cidade não "finge" eventos: quando um civil é baleado, uma ambulância real parte de um hospital real, paramédicos reais descem, colocam a vítima na maca e a transportam pelas ruas físicas. Se a vítima falecer, o rabecão assume o trajeto.
4. **Motor de Áudio Leve e Dinâmico**:
   - Síntese de motores que responde a cada fração de aceleração, derrapagem e troca de marcha, economizando megabytes em pacotes de áudio.
5. **Cultura de Rigor e Testes de Software**:
   - Presença de centenas de scripts de teste automatizado que cobrem desde a física de balanço de um machado (`test_axe_swing.gd`) até rotinas de salvamento atômico e taxas de entrega de frames em Vulkan real.
6. **Código Limpo e Organizado**:
   - Menos de 0,3% de arquivos órfãos em todo o projeto ativo, com convenção estrita de nomenclatura e separação clara de responsabilidades por domínios.

---

## 8. Pontos Fracos, Gargalos e Débito Técnico (Flaws & Bottlenecks)

1. **Pico de Congelamento na Inicialização do Mundo**:
   - O primeiro frame após o `add_child()` em `HarborPreview._start_review()` historicamente concentrava a instanciação de dezenas de nós, gerando um travamento sensível de alguns segundos. O carregamento foi fatiado recentemente em lotes assíncronos (`GETECO-PERF-03A`), mas ainda demanda cuidados constantes.
2. **Navegação de Emergência sem NavMesh2D Tradicional**:
   - As viaturas em `EmergencyVehicle.gd` utilizam um roteador próprio sobre faixas (`EmergencyLaneRouter`) com interpolação angular direta (`lerp_angle`) em vez de um sistema de grafo com desvio dinâmico de obstáculos (`NavigationAgent2D`). Se um veículo de resgate for bloqueado por tráfego caótico fora de sua faixa, ele entra em rotinas de ré e manobra que podem gerar ciclos repetitivos de travamento.
3. **Alto Número de SubViewports**:
   - Com mais de duas centenas de `SubViewport`s alocados para instâncias 3D, a sobrecarga de alocação de texturas em VRAM e o custo inicial de setup na GPU são elevados, demandando orçamentos rígidos como o `PresentationBudget`.
4. **Acoplamento por Strings de Caminho (`res://`)**:
   - O projeto utiliza caminhos em string absolutos em vez do sistema nativo de UIDs do Godot 4. Mover pastas ou renomear arquivos requer o uso de ferramentas dedicadas (`tools/move_folder_refactor.py`) para reescrever centenas de referências cruzadas sem quebrar o projeto.
5. **Legado Ativo para Retrocompatibilidade**:
   - Arquivos legados da primeira versão do jogo (`legacy/Main.tscn`, `GarageMenu.gd`, `VehicleUpgradeManager.gd`) ainda precisam residir no repositório para evitar que saves de versões antigas sofram crash ao carregar.
6. **Contradição de Mapas Narrativos vs. Técnicos**:
   - Os documentos de produção narrativa previam 4 grandes cidades (Harbor, Deserto, Cidade 2, Vegas). Tecnicamente, a transição para Mountain Pass é tratada como streaming contínuo sob a mesma infraestrutura, e a ponte para futuros mapas ainda possui stubs lógicos no código (`HarborGateway.get_map2_connection_contract()`).

---

## 9. Resumo das Otimizações Recentes (Auditorias de Setembro de 2026)

Nos últimos dias, o projeto passou por intensas baterias de auditoria de performance (`GETECO-PERF-01` a `03B`):
- **Otimização de Renderização de Frota (`02B`)**: Redução de alocações desnecessárias na fila de apresentação e correção no chaveamento de cache de malhas primitivas (`VehicleMeshBatcher`).
- **Fatiamento de Carregamento (`03A` e `03A-R2`)**: Quebra da rotina de inicialização de distritos portuários e iluminação viária (`RoadLighting`) em corrotinas, evitando que todas as luzes e nós concorram no mesmo instante.
- **Cache de Modelos em Textura**: Pré-renderização em texturas estáticas de 37 modelos 3D do Porto Sul para aliviar instâncias de Viewports.
- **IA de Tráfego Otimizada por Distância**: A taxa de atualização dos scripts de tráfego foi escalonada com base na proximidade do jogador (veículos distantes processam em intervalos maiores).
- **Desconflito de Viaturas de Polícia**: Ajuste nos vetores de chegada para viaturas policiais não colidirem e travarem empilhadas ao cercar o alvo.

---

## 10. Como Executar e Testar

### Abrir e Jogar
- **Entrypoint**: Configurado no `project.godot` como `res://ui/MainMenu.tscn`.
- O menu permite iniciar novo jogo (que dispara a cutscene cinematográfica de abertura) ou carregar slots existentes de save.

### Executar Testes Automatizados
Os testes não dependem de pacotes externos como GUT; utilizam o interpretador de linha de comando do Godot:
```powershell
# Exemplo: Testar integridade do fluxo de menus e inicialização
"Caminho/Para/Godot_v4.7.2-stable_win64_console.exe" --path . --script res://tests/test_menu_flow_integration.gd

# Exemplo: Testar restrições permanentes de armas na garagem do Maciota
"Caminho/Para/Godot_v4.7.2-stable_win64_console.exe" --path . --script res://tests/test_garage_weapon_restrictions.gd

# Verificar integridade de todos os caminhos e referências do projeto
python tools/check_references.py
```
> *Aviso Crítico*: Testes de performance, tempo de quadro e FPS **nunca** devem ser executados com a flag `--headless`, pois o driver dummy de renderização do Godot ignora os custos reais de draw calls e sombreadores Vulkan.

---

## 11. Dica para o ChatGPT / LLM Prompt

Se você estiver enviando este documento para um assistente de IA (como ChatGPT, Claude ou Gemini), utilize a introdução abaixo para dar as instruções de comportamento adequadas:

> *"Abaixo está o documento técnico completo do jogo GETECO, desenvolvido em Godot 4.7.2 com física 2D e renderização 3D híbrida. Leia as seções com atenção para compreender a arquitetura por domínios, as mecânicas de gameplay, os padrões de código, as limitações conhecidas de performance e as regras sagradas de design (como a imunidade do Maciota e o sistema de emergências). Por favor, use este contexto como fonte da verdade para qualquer sugestão de código, refatoração, criação de novas missões ou solução de bugs que eu solicitar a seguir."*
