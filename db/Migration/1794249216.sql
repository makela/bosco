-- Users get roles besides admin: a user may be a deliverer, a promoter or
-- both (see Application/Permission.hs). Until now everyone who wasn't an
-- admin was a delivery person, so they stay one.
ALTER TABLE users
    ADD COLUMN is_deliverer BOOLEAN DEFAULT false NOT NULL,
    ADD COLUMN is_promoter BOOLEAN DEFAULT false NOT NULL;
UPDATE users SET is_deliverer = true WHERE NOT is_admin;
