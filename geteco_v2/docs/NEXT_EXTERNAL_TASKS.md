# Próximas tarefas externas — 21/09/2026

O integrador está conectando mountain_detail, suas fontes de calor e TrafficYieldController à Main. Não editar NativeRegion, ProductionWorld, FullSession, Vehicle, HeatPresentation ou os módulos de montanha entregues durante esta etapa. Não executar Godot, testes ou benchmarks: implementação agora, validação depois. Preservar alterações locais de outras sessões.

## Claude — ultrapassagem das viaturas

Complete a interação entre trânsito cedendo passagem e viaturas. Seu ownership é `geteco_v2/gameplay/dispatch/DispatchDriver.gd`, helpers novos em `gameplay/dispatch/overtaking/` e, se necessário, o módulo `gameplay/traffic_yield/` que você entregou. Não editar outros arquivos de dispatch sem coordenar com o integrador.

Implemente desvio físico à esquerda de um carro ambiente em `held` ou `pulling`, usando o grafo real e o casco completo. Verifique largura útil, sentido/faixas, cruzamentos, veículos em aproximação e espaço para retornar. Não entrar em calçada, contramão proibida, sólidos ou atravessar outros carros. Quando não couber, aguardar e reavaliar, sem teletransporte. A cessão pode falhar em ruas estreitas; não prometer passagem universal.

Mantenha o Vehicle como único executor da física; não duplicar `_drive_player`, nem alternar `controlled` para contornar atribuição de crime. A integração já fornece `set_external_driver()` e `is_player_damage_source()`. Preserve freios, motor bloqueado, retorno à rota e limpeza na suspensão, destruição e troca de região. Leia a versão atual desses contratos antes de editar.

Entregue a implementação e um README com API, parâmetros, situações de espera, cancelamento e limitações. Não mudar os pontos de conexão que o integrador está instalando: `TrafficYieldController.configure(world, traffic_routes)`, `release_all(reason)` e `refresh_roads(traffic_routes)`. Testes e medições ficam pendentes explicitamente.

## Antigravity — apresentação da prensa do Neco

Prepare um componente 3D independente da prensa do Neco, reaproveitando a geometria e a sequência visual da fonte V1. Ownership exclusivo de arquivos novos em `geteco_v2/world/neco_press/` e `geteco_v2/assets/neco_press/`. Não modificar madeireira, vilarejo, NativeRegion, GarageRewards, MissionWorld, Vehicle, interiores ou economia.

Entregue uma fábrica com prensa, plataforma e partes móveis, na escala do V2, além de uma API explícita de apresentação: iniciar com a representação visual de um veículo fornecida pelo integrador, cancelar e emitir conclusão. Documente a pose/orientação e dimensões da área de recepção em relação à origem do componente. A animação não pode deslocar o veículo real, apagar entidades do jogo, alterar save, conceder dinheiro ou decidir elegibilidade: isso permanece com GarageRewards.

Preserve materiais, proporções e sequência originais; se a fonte não oferecer alguma geometria, identifique a reconstrução. Evite textos decorativos. Não instalar outra cópia do ferro-velho, do Neco ou de veículos. Se houver partes móveis sólidas, exponha explicitamente seus volumes e fases para o integrador decidir a interação física; não criar esmagamento/dano por conta própria.

Documente instalação, uso, cancelamento/limpeza e o que não foi validado. Não executar testes, renderização ou benchmarks nesta etapa.
