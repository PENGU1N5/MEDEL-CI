-- ========================
-- RLS Policies for MEDEL-CI
-- ========================
-- roles: regional (admin sees all), country (sees only their own)

-- 1. PROFILES
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS profiles_select ON profiles;
DROP POLICY IF EXISTS profiles_update ON profiles;
CREATE POLICY profiles_select ON profiles FOR SELECT USING (true); -- any authenticated user can read profiles
CREATE POLICY profiles_update ON profiles FOR UPDATE USING (auth.uid() = id); -- only your own profile

-- 2. COUNTRIES (reference — public read)
ALTER TABLE countries ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS countries_select ON countries;
CREATE POLICY countries_select ON countries FOR SELECT USING (true);

-- 3. DEVICE_MODELS (reference — public read)
ALTER TABLE device_models ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS device_models_select ON device_models;
CREATE POLICY device_models_select ON device_models FOR SELECT USING (true);

-- 4. POOL_DEVICES
ALTER TABLE pool_devices ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pool_devices_select ON pool_devices;
DROP POLICY IF EXISTS pool_devices_insert ON pool_devices;
DROP POLICY IF EXISTS pool_devices_update ON pool_devices;
DROP POLICY IF EXISTS pool_devices_delete ON pool_devices;

-- SELECT: everyone sees all (as discussed — visibility for comparison)
CREATE POLICY pool_devices_select ON pool_devices FOR SELECT USING (true);

-- INSERT: country users can only add to their country; regional adds anywhere
CREATE POLICY pool_devices_insert ON pool_devices FOR INSERT WITH CHECK (
  auth.role() = 'service_role' OR
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'regional' OR
  country_code = (SELECT country_code FROM profiles WHERE id = auth.uid())
);

-- UPDATE: only your own country's devices, or regional
CREATE POLICY pool_devices_update ON pool_devices FOR UPDATE USING (
  auth.role() = 'service_role' OR
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'regional' OR
  country_code = (SELECT country_code FROM profiles WHERE id = auth.uid())
);

-- DELETE: same as update
CREATE POLICY pool_devices_delete ON pool_devices FOR DELETE USING (
  auth.role() = 'service_role' OR
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'regional' OR
  country_code = (SELECT country_code FROM profiles WHERE id = auth.uid())
);

-- 5. MOVEMENTS
ALTER TABLE movements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS movements_select ON movements;
DROP POLICY IF EXISTS movements_insert ON movements;
DROP POLICY IF EXISTS movements_update ON movements;
DROP POLICY IF EXISTS movements_delete ON movements;

CREATE POLICY movements_select ON movements FOR SELECT USING (true); -- all visible
CREATE POLICY movements_insert ON movements FOR INSERT WITH CHECK (
  auth.role() = 'service_role' OR
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'regional' OR
  country_code = (SELECT country_code FROM profiles WHERE id = auth.uid())
);
CREATE POLICY movements_update ON movements FOR UPDATE USING (
  auth.role() = 'service_role' OR
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'regional' OR
  country_code = (SELECT country_code FROM profiles WHERE id = auth.uid())
);
CREATE POLICY movements_delete ON movements FOR DELETE USING (
  auth.role() = 'service_role' OR
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'regional' OR
  country_code = (SELECT country_code FROM profiles WHERE id = auth.uid())
);

-- 6. SHORTAGE_EVENTS
ALTER TABLE shortage_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS shortage_events_select ON shortage_events;
DROP POLICY IF EXISTS shortage_events_insert ON shortage_events;
DROP POLICY IF EXISTS shortage_events_update ON shortage_events;
DROP POLICY IF EXISTS shortage_events_delete ON shortage_events;

CREATE POLICY shortage_events_select ON shortage_events FOR SELECT USING (true); -- all visible
CREATE POLICY shortage_events_insert ON shortage_events FOR INSERT WITH CHECK (
  auth.role() = 'service_role' OR
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'regional' OR
  country_code = (SELECT country_code FROM profiles WHERE id = auth.uid())
);
CREATE POLICY shortage_events_update ON shortage_events FOR UPDATE USING (
  auth.role() = 'service_role' OR
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'regional' OR
  country_code = (SELECT country_code FROM profiles WHERE id = auth.uid())
);
CREATE POLICY shortage_events_delete ON shortage_events FOR DELETE USING (
  auth.role() = 'service_role' OR
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'regional' OR
  country_code = (SELECT country_code FROM profiles WHERE id = auth.uid())
);
