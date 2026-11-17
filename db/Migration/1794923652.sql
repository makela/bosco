-- The privacy notice, which the admin writes and publishes like the
-- payment instructions: the newest is the one shown, and the older ones
-- tell what the site said when. With none, the site shows a default text.
CREATE TABLE privacy_notices (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    published_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    text TEXT NOT NULL
);
