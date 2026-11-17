-- Who gets the newsletter. subscribed_at is when they asked for it, on the
-- newsletter form or with the order form's box, which is ticked to begin
-- with; NULL when they don't get it. unsubscribed_at is when they last
-- left it, for when someone asks. The customers so far all got it.
ALTER TABLE customers ADD COLUMN subscribed_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;
ALTER TABLE customers ADD COLUMN unsubscribed_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;
UPDATE customers SET subscribed_at = created_at;
