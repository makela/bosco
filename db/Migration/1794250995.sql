-- Who changed which product or producer text, when, and from what: with
-- promoters editing the texts, a mistake is easy to see and undo. A row is
-- about a product or a producer, and goes with it if it is deleted.
CREATE TABLE text_changes (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    user_id UUID NOT NULL,
    product_id UUID DEFAULT NULL,
    producer_id UUID DEFAULT NULL,
    field_name TEXT NOT NULL,
    text_before TEXT NOT NULL,
    text_after TEXT NOT NULL
);
CREATE INDEX text_changes_product_id_index ON text_changes (product_id);
CREATE INDEX text_changes_producer_id_index ON text_changes (producer_id);
CREATE INDEX text_changes_user_id_index ON text_changes (user_id);
ALTER TABLE text_changes ADD CONSTRAINT text_changes_ref_producer_id FOREIGN KEY (producer_id) REFERENCES producers (id) ON DELETE CASCADE;
ALTER TABLE text_changes ADD CONSTRAINT text_changes_ref_product_id FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE;
ALTER TABLE text_changes ADD CONSTRAINT text_changes_ref_user_id FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE NO ACTION;
