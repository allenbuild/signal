CREATE TABLE `shared_profiles` (
	`share_code` text PRIMARY KEY NOT NULL,
	`profile_id` text NOT NULL,
	`profile_json` text NOT NULL,
	`revoke_token_hash` text NOT NULL,
	`created_at_ms` integer NOT NULL,
	`revoked_at_ms` integer
);
--> statement-breakpoint
CREATE INDEX `shared_profiles_profile_id_idx` ON `shared_profiles` (`profile_id`);--> statement-breakpoint
CREATE INDEX `shared_profiles_revoked_at_idx` ON `shared_profiles` (`revoked_at_ms`);