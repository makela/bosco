-- What IHP puts in a database before the app's schema (db/Schema.sql):
-- copied from IHP v1.6's ihp-schema-compiler/data/IHPSchema.sql (MIT License,
-- digitally induced GmbH), so that a new database is the same as the ones IHP
-- made, without IHP. The email jobs' status is still JOB_STATUS.
--
-- Provides all the default settings for a IHP database in development mode
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Used by IHP.Job
CREATE TYPE JOB_STATUS AS ENUM ('job_status_not_started', 'job_status_running', 'job_status_failed', 'job_status_timed_out', 'job_status_succeeded', 'job_status_retry');

-- Used by IHP.DataSync
CREATE FUNCTION ihp_user_id() RETURNS UUID AS $$
    SELECT NULLIF(current_setting('rls.ihp_user_id'), '')::uuid;
$$ LANGUAGE SQL;
