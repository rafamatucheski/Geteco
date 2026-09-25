# Ammu-Nation — diagnóstico e otimização da construção, fase 4

Estado final: redução parcial do hitch, CPU causal e equivalência aprovados; travada na admissão ainda presente. FPS NÃO certificado. Partida do usuário PID86396 e editor76560 foram preservados durante toda a coleta. Não houve teste simultâneo de outros agentes nas janelas registradas.

## Escopo implementado

- `assets/regions/source/scripts/player/WeaponFinish3D.gd`: cache de malha chanfrada por tamanho exato (máximo256); agrupamento por material usa arrays compactos, preserva triângulos, UV/cores, transformações, normais por inversa transposta, tangentes, peças móveis e boca da arma. A inversa da matriz é calculada uma vez por peça; cada vértice é transformado uma vez, em vez de repetir por canto de triângulo. A edição independente do root em apply (dente externo da SMG) foi preservada.
- `assets/regions/source/guns/ammunation/AmmunationArt.gd`: somente helpers box/bevel_box, caches limitados de BoxMesh256, bevel256 e material64. Materiais têm cor exata como chave; metallic0/roughness.85/transparência desativada são fixos. O novo parâmetro unique_material preserva a mutação explícita do vidro; somente essa chamada do balcão usa true. Item/Vance/layout/câmera/iluminação não foram reescritos.
- A personalização existente duplica materiais antes de recolorir ou aplicar acabamento. O adaptador NativePlace duplica malhas antes de alterar tamanho no cutaway. Os caches não modificam as malhas ou os materiais depois de criados.

## Evidência causal e limites

NativePlace constrói AmmunationModel/ART.room de forma síncrona ao atravessar a entrada. O adaptador após ART custa cerca de2ms e o primeiro load cerca de4ms; o maior bloco é a construção visual. Headless não mede FPS.

O probe de atribuição usa cópia do script em memória, mantendo o runtime intacto, e cronometra somente as funções. Antes: sala44,707/43,798ms, Arsenal29,522/29,980ms, box8,007/6,765ms, bevel4,301/4,132ms. Após WeaponFinish: sala35,508/28,442ms; Arsenal20,108/14,584ms. Após cache ART e correções de arte independentes: sala24,596/18,709ms, Arsenal18,615/14,228ms, box3,120/1,845ms, bevel0,259/0,038ms. Esses últimos números incluem16 peças retiradas pela correção independente do guarda-mato; a comparação causal dos helpers abaixo usa exatamente a mesma arte atual.

Na prova A/B do kit atual, com Arsenal pré-aquecido, Harbor passou de26,313 para19,401ms. Ambas versões têm614 meshes; recursos distintos de malha614→192 e materiais606→150. A variante mountain passou de25,984 para17,004ms, mantendo635 meshes e a mesma geometria/material. O teste da variante compartilhada é regressão do helper, não migração do ambiente.

## Main renderizado, primeira etapa

Configuração: Godot4.7.2, Mobile/Vulkan RTX4060Laptop,2560×1440,MSAA2x,VSync ligado,limitador60FPS,clima limpo9:07,seed21092026,Main real. Entrada por caminhada física+zoom; saída/reentrada automáticas;30s andando no interior; prints fora dos intervalos medidos; nenhum save pessoal escrito. População normal solicitada40, com streaming/população dinâmica funcionando.

| Medida | Antes | Após WeaponFinish |
|---|---:|---:|
| Maior intervalo na primeira entrada |186,219ms|182,532ms|
| ART na primeira entrada |106,822ms|96,630ms|
| Maior intervalo na reentrada |148,465ms|147,525ms|
| ART na reentrada |103,815ms|88,373ms|
| Interior30s p95/p99 |17,257/17,517ms|17,481/17,854ms|
| CPU render principal p95 |1,137ms|1,102ms|
| GPU render principal p95 |4,138ms|4,174ms|
| Draw calls p95 |657|657|
| Intervalos>33,3ms no interior30s |0|0|

O hitch grave permaneceu nessa etapa. Essa série é diagnóstica: jogo/editor do usuário concorrentes; população real24/27 e veículos26/30 no instante de amostragem, nós10061/10557; FullSession mudou por trabalho paralelo. Não permite atribuir mudanças globais de CPU/física ao patch nem aprovarFPS. O monitor render CPU/GPU mede o viewport principal e não é somável ao TIME_PROCESS/física; intervalos incluem limitador, espera e escalonamento. O p95 da reentrada variou+6,1% em uma amostra curta sob essas condições; requer par comparável/exclusivo, não conclusão de regressão nem aprovação.

As quatro capturas antes/depois da primeira etapa foram abertas e inspecionadas: armas, balcão, vidro, Vance, piso, circulação, luz e sombras mantidos. Mesmos657 draw calls na sala estável. Arquivos `phase4-ammo-before-shared-*.png` e `phase4-ammo-after-shared-*.png` nesta pasta.

## Verificação funcional/geométrica

- `tests/test_video_phase4_weapon_batch.gd`:144/144 PASS no modo portátil, compara15 armas atuais com geometria acabada antes de agrupar; escala não uniforme e reflexão, dentro/fora da árvore, triângulos indexados/não indexados, UV/cores, identidade de material, partes móveis e limite de cache. Primeira prova142/142 usou snapshot prévio literal; o modo legado atual compõe apply atual com helpers antigos para isolar mudanças de arte concorrentes.
- `tests/test_video_phase4_art_cache.gd`:29/29 PASS; geometria/transforms/materials Harbor+mountain idênticos ao helper sem cache, vidro isolado por sala, futuras instâncias opacas não contaminadas, finalização/recoloração de pistola/granada/colete não contaminam outras instâncias nem futuras prévias, metadados de reação de Vance e limites dos caches preservados.
- `tests/measure/video_phase4_art_cost.gd`: atribuição de construção somente, sem Main/FPS.
- `tests/measure/video_phase4_ammunation.gd`: Main, caminhada real/zoom,30s,saída/reentrada,amostras brutas,contexto,hashes,CPU/GPU e PNGs. Recusa headless sem --causal-headless explícito; nunca marca fps_certified=true.

Logs relevantes: `phase4-weapon-equivalence-portable.log`, `phase4-art-cache-runtime.log`, `phase4-art-cache-candidate.log`, `phase4-art-attribution-cache-after.log`. Todos exit0. Único erro de ambiente recorrente: leitura do repositório de certificados raiz doWindows, já presente no baseline e sem erro de script.

Comando Main reproduzível (agendar janela exclusiva antes de aprovarFPS):

```powershell
& 'D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --path 'D:/geteco/game' --log-file '<evidence>/phase4-ammo-final.log' --script res://tests/measure/video_phase4_ammunation.gd -- --no-save --skip-arrival --benchmark --population=40 --label=phase4-ammo-final --condition=EXPLICIT_CONDITION --evidence-dir=<evidence>
```

Artefatos: JSONs antes/depois contêm amostras brutas e hashes; `phase4-ammo-comparison.json` contém a comparação da primeira etapa; `phase4-ammo-source-hashes.json` identifica os fontes. Snapshots legados foram escritos somente como evidência: nunca restaurados sobre o trabalho compartilhado.

## Main final após os dois caches

Processo engine102520 / console107364, iniciado22:02:14 e encerrado exit0, failures[]. Nenhum processo nosso permanece ativo. As duas PNGs finais foram abertas e inspecionadas: forma/circulação/Vance/vidro/luz/sombras preservados; entrada/saída/reentrada automáticas completadas.

| Medida | Antes | WeaponFinish | Dois caches finais |
|---|---:|---:|---:|
| Pico primeira entrada |186,219ms|182,532ms|151,349ms|
| ART primeira entrada |106,822ms|96,630ms|77,552ms|
| Pico reentrada |148,465ms|147,525ms|114,780ms|
| ART reentrada |103,815ms|88,373ms|68,609ms|
| Interior30s p95 |17,257ms|17,481ms|17,521ms|
| Interior30s p99 |17,517ms|17,854ms|17,912ms|
| CPU render principal p95 |1,137ms|1,102ms|0,909ms|
| GPU render principal p95 |4,138ms|4,174ms|4,180ms|
| Draw calls p95 |657|657|641|
| Intervalos>33,3ms no interior30s |0|0|0|
| Pessoas/carros capturados |24/26|27/30|28/29|
| Nós no interior |10061|10557|10337|

O pico observado reduziu18,7% na primeira entrada e22,7% na reentrada, mas151/115ms continuam fora da meta. A montagem ART permaneceu77,6/68,6ms. A série renderizada continua DIAGNÓSTICA, com população dinâmica e sessão concorrente. Os16 meshes/draw calls a menos na etapa final são a correção independente do guarda-mato pelo root, não simplificação aplicada pelo cache. A prova causal do cache comparou a mesma geometria atual614meshes, incluindo o item já corrigido e a SMG atual.

Hashes de FullSession e ProductionWorld podem mudar entre etapas por trabalho paralelo; o segundo cache foi precedido de snapshot específico de AmmunationArt já com a correção do item. Não atribuir a diferença global inteira a um único patch. Nenhuma redução de resolução/MSAA/luz/sombras/população solicitada foi usada como otimização. Main final tem30,013s/1801amostras, sem intervalos>33,3ms dentro do período estável.

Pendência: primeira admissão e reentrada ainda engasgam; requer investigação posterior do restante da montagem síncrona e um novo par renderizado em janela exclusiva antes de aprovarFPS. Não foram certificados todos os interiores/mapas, chuva/noite, UI de catálogo ou combate. A meta provisória60FPS/p9516,67ms não foi aprovada. Não foi aberto outro ciclo de otimização nesta rodada, conforme coordenação do root.

As imagens e dados brutos desta entrega ficam em `D:/geteco/game/evidence/video-review-phase4-20260924/ammunation/`. Os snapshots de scripts são `.gd.txt`, somente evidência, para não se tornarem recursos runtime do projeto. Logs dos testes portáteis completos:144/144 e29/29. Handoff final e manifest SHA256 acompanham os6PNGs das3etapas, seus JSONs e logs.
