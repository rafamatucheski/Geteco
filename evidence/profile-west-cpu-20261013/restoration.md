Instrumentação temporária removida manualmente dos 14 arquivos após a bateria. O script exigiu SHA bruto aplicado de todas as fontes antes da remoção e recuperou o SHA normalizado original nos 14 arquivos. Nenhum texto ou código foi substituído por conteúdo do HEAD e nenhum comando de descarte do Git foi usado.

**11/14 arquivos** recuperaram exatamente os bytes originais. Os SHA brutos originais dos três restantes não foram recuperados: a aplicação do patch com `core.autocrlf=true` havia normalizado finais originalmente mistos. Após a remoção, foi autorizado um ajuste final exclusivo das terminações de linha desses três para o padrão versionado. O ajuste preservou cada corpo de linha atual byte a byte, usando o blob HEAD somente como mapa de terminações; exigiu SHA atual idêntico ao registro de restauração e SHA normalizado original antes e depois.

Arquivos ajustados somente em finais de linha:

- `gameplay/street_physics/StreetPhysics.gd`
- `gameplay/dispatch/DispatchRoadRouter.gd`
- `audio/WorldAudio.gd`

Os **14/14 arquivos têm o texto original integral**, sem instrumentação ou mudança lógica. O SHA bruto desses três permanece diferente do original pré-instrumentação e equivale ao padrão de EOL versionado. Saída histórica da remoção, hashes originais/finais e prova do ajuste estão em `restoration.json`. A conferência final de conteúdo passou: diff normal e diff com EOL normalizado dos 14 arquivos vazios/código 0. Nos três arquivos ajustados, os objetos do arquivo atual filtrado, índice e HEAD são idênticos. O coordenador atualizou somente os metadados do índice; o status final dos três arquivos está limpo, sem conteúdo de produção staged.
