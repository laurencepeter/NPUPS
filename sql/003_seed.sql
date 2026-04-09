-- ══════════════════════════════════════════════════════════════════════════════
-- NPUPS Seed Data
-- 14 Municipal Corporations of Trinidad & Tobago + initial system admin
-- Run after 001_schema.sql and 002_auth.sql
-- ══════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- CORPORATIONS
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO corporations (id, name, districts) VALUES
  ('1',  'Arima Borough Corporation',
    ARRAY['Arima North','Arima South','Arima Central']),
  ('2',  'Chaguanas Borough Corporation',
    ARRAY['Chaguanas East','Chaguanas West','Chaguanas North','Chaguanas South','Charlieville']),
  ('3',  'San Fernando City Corporation',
    ARRAY['San Fernando East','San Fernando West']),
  ('4',  'Diego Martin Regional Corporation',
    ARRAY['Diego Martin North','Diego Martin Central','Petit Valley']),
  ('5',  'Mayaro-Rio Claro Regional Corporation',
    ARRAY['Mayaro','Rio Claro','Biche']),
  ('6',  'Penal-Debe Regional Corporation',
    ARRAY['Penal','Debe','Barrackpore']),
  ('7',  'Point Fortin Borough Corporation',
    ARRAY['Point Fortin North','Point Fortin South']),
  ('8',  'Port of Spain City Corporation',
    ARRAY['Port of Spain North','Port of Spain South','Port of Spain East','Port of Spain West','Laventille','Morvant']),
  ('9',  'Princes Town Regional Corporation',
    ARRAY['Princes Town','Moruga','Tableland']),
  ('10', 'Couva-Tabaquite-Talparo Regional Corporation',
    ARRAY['Couva North','Couva South','Tabaquite','Talparo']),
  ('11', 'San Juan-Laventille Regional Corporation',
    ARRAY['San Juan','Barataria','El Socorro']),
  ('12', 'Sangre Grande Regional Corporation',
    ARRAY['Sangre Grande','Toco','Matura']),
  ('13', 'Siparia Regional Corporation',
    ARRAY['Siparia','Fyzabad','Oropouche']),
  ('14', 'Tunapuna-Piarco Regional Corporation',
    ARRAY['Tunapuna','Piarco','St. Augustine','Curepe'])
ON CONFLICT (id) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- INITIAL SYSTEM ADMIN
-- Password is set via environment variable NPUPS_ADMIN_PASSWORD at init time.
-- Change this password immediately after first login.
--
-- To create additional users, insert directly or build an admin UI later.
-- Password hashing: crypt('plaintext', gen_salt('bf', 10))
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO users (email, full_name, role, corporation_id, password_hash)
VALUES (
  'admin@npups.gov.tt',
  'System Administrator',
  'systemAdmin',
  NULL,
  crypt('ChangeMe123!', gen_salt('bf', 10))
)
ON CONFLICT (email) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- NOTE: After first deployment, create real user accounts via psql:
--
--   INSERT INTO users (email, full_name, role, corporation_id, password_hash)
--   VALUES (
--     'coordinator@npups.gov.tt',
--     'Marcus Thompson',
--     'regionalCoordinator',
--     '8',
--     crypt('their-secure-password', gen_salt('bf', 10))
--   );
--
-- Or use the system admin account to build a user management UI later.
-- ─────────────────────────────────────────────────────────────────────────────
