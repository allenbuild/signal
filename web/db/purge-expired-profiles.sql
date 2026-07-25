-- Signal D1 retention policy enforcement.
--
-- Schedule this statement at least once every 24 hours in production. Profile
-- API access also performs the same purge opportunistically, but that does not
-- bound physical retention in a completely idle database.
--
-- Active shares expire 365 days after creation. Revoked rows are removed 30
-- days after revocation. Deleting a row also deletes its revoke-token hash.
DELETE FROM shared_profiles
WHERE created_at_ms < (unixepoch('now', '-365 days') * 1000)
   OR (
     revoked_at_ms IS NOT NULL
     AND revoked_at_ms < (unixepoch('now', '-30 days') * 1000)
   );
