CREATE TABLE payment_instructions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    published_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    text TEXT NOT NULL
);

INSERT INTO public.payment_instructions (id, published_at, text) VALUES ('abccda34-24c1-480f-bdf7-86324959b42e', '2022-10-16 21:40:14.374511+03', 'REMOVED-ACCOUNT-HOLDER

IBAN REMOVED-IBAN

BIC REMOVED-BIC (last digit is a zero)

Maksun eräpäivä on **15. marraskuuta**.');
