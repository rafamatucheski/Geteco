# City Ammu-Nation

Harbor bank is NorthFrontage0 (north frontage, western end). City Ammu-Nation is NorthFrontage2 on the same row, replacing the coffee facade label. Entrance/return bind through HarborInteriorManager; weapon_shop supplies its minimap icon.

The room uses a 3D perspective viewport and projected collision polygons, with cabin actor scaling. Approach the central counter and press E. Previous/next buttons or left/right browse rotating ArsenalWeapon3D models; buy calls Player.buy_weapon and preserves catalog discovery locks and prices. Escape/Close releases the interior modal lock. No new save format.

The mountain room keeps its existing geometry and counter through MountainGunCounterSupport, separating its older UI contract from the city's new catalog.

Validation: test_city_ammunation.gd checks entrance/return, preview geometry, modal lock, purchase debit, duplicate prevention and insufficient funds. Real Vulkan captures: D:/geteco/ammunation-catalog.png and D:/geteco/ammunation-interior.png. One ObjectDB exit leak remains in the world integration test.
