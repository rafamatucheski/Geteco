# Map presentation baseline

Frozen map presentation before the October 2026 Harbor redesign, used only by
`tests/measure/measure_world_map.gd -- --no-save --atlas-compare`.

These five files preserve the previous UI, atlas collection, symbols and terrain
shader. Local preloads point to this directory; production world geometry is
shared so a comparison uses the same scene and navigation coordinates.

The comparison is an explicit, long rendered benchmark. It is not part of normal
game startup or the lightweight map contract tests. Do not start it while another
game/test is running. The design captures and contract tests are the normal
checks for small map presentation changes.
