-- Production's schema before the deploy that introduced the NixOS module:
-- Application/Schema.sql as of migration 1760540031, plus the helper function
-- migration 1759991022 created and Schema.sql never listed.

-- Your database schema. Use the Schema Designer at http://localhost:8001/ to add some tables.
CREATE TABLE users (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    email TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    locked_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    failed_login_attempts INT DEFAULT 0 NOT NULL,
    is_admin BOOLEAN DEFAULT false NOT NULL
);
CREATE TABLE producers (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    subject TEXT NOT NULL,
    description TEXT NOT NULL,
    enabled BOOLEAN DEFAULT true NOT NULL
);
CREATE TABLE products (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    producer_id UUID NOT NULL,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    package TEXT NOT NULL,
    price INT NOT NULL,
    ordering INT DEFAULT NULL,
    enabled BOOLEAN DEFAULT true NOT NULL
);
CREATE TABLE customers (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    phone TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    last_modified_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    address TEXT DEFAULT '' NOT NULL,
    reverse_name TEXT DEFAULT '' NOT NULL
);
CREATE TABLE orders (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    customer_id UUID NOT NULL,
    ordered_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    paid_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    cancelled_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    delivered_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    invoiced_at TIMESTAMP WITH TIME ZONE DEFAULT NULL
);
CREATE INDEX orders_customer_id_index ON orders (customer_id);
CREATE TABLE ordered_products (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    order_id UUID NOT NULL,
    product_id UUID NOT NULL,
    quantity INT NOT NULL
);
CREATE INDEX ordered_products_order_id_index ON ordered_products (order_id);
CREATE INDEX ordered_products_product_id_index ON ordered_products (product_id);
CREATE INDEX products_producer_id_index ON products (producer_id);
CREATE TABLE welcome_messages (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    text TEXT NOT NULL,
    published_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    is_ordering_enabled BOOLEAN DEFAULT false NOT NULL
);
CREATE TABLE payment_instructions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    published_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    text TEXT NOT NULL
);
CREATE TABLE email_order_jobs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    status JOB_STATUS DEFAULT 'job_status_not_started' NOT NULL,
    last_error TEXT DEFAULT NULL,
    attempts_count INT DEFAULT 0 NOT NULL,
    locked_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    locked_by UUID DEFAULT NULL,
    run_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    order_id UUID NOT NULL
);
CREATE INDEX email_order_jobs_order_id_index ON email_order_jobs (order_id);
ALTER TABLE email_order_jobs ADD CONSTRAINT email_order_jobs_ref_order_id FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE NO ACTION;
ALTER TABLE ordered_products ADD CONSTRAINT ordered_products_ref_order_id FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE NO ACTION;
ALTER TABLE ordered_products ADD CONSTRAINT ordered_products_ref_product_id FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE NO ACTION;
ALTER TABLE orders ADD CONSTRAINT orders_ref_customer_id FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE NO ACTION;
ALTER TABLE products ADD CONSTRAINT products_ref_producer_id FOREIGN KEY (producer_id) REFERENCES producers (id) ON DELETE NO ACTION;
CREATE FUNCTION array_reverse(anyarray) RETURNS anyarray LANGUAGE SQL AS $$
  SELECT array_agg(val ORDER BY idx DESC)
  FROM unnest($1) WITH ORDINALITY AS t(val, idx);
$$;
