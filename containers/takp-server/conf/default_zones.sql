-- Applied once, right after the initial database load.
-- Zone ports come from world's zones.ports pool (PORT_RANGE_LOW-PORT_RANGE_HIGH)
-- instead of fixed per-zone ports.
UPDATE launcher_zones SET port = 0;

-- Default to 30 static zones: the 12 boat docks plus 18 core zones.
-- Enabled zones must stay below the number of ports in PORT_RANGE.
UPDATE launcher_zones SET enabled = 0;
UPDATE launcher_zones SET enabled = 1
WHERE launcher = 'boats'
  OR zone IN (
    'commons', 'ecommons', 'nexus', 'poknowledge',
    'freportw', 'freportn', 'qeynos2', 'gfaydark', 'lfaydark',
    'neriakb', 'neriakc', 'cabeast', 'oggok', 'rathemtn',
    'northkarana', 'southkarana', 'highkeep', 'steamfont'
  );

