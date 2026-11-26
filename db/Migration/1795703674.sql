-- A login's sessions: the session cookie names one, so logging out ends it
-- there and then, and a changed password ends the others. Before, the
-- cookie alone was the login, which a copy of it kept for 30 days.
CREATE TABLE user_sessions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    user_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);
CREATE INDEX user_sessions_user_id_index ON user_sessions (user_id);
ALTER TABLE user_sessions ADD CONSTRAINT user_sessions_ref_user_id FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE;
