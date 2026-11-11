-- The catalog of an English demo: Fixtures.sql with its texts in English,
-- the same ids and prices. See nix/module.nix (fixtures).


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


SET SESSION AUTHORIZATION DEFAULT;

ALTER TABLE public.customers DISABLE TRIGGER ALL;



ALTER TABLE public.customers ENABLE TRIGGER ALL;


ALTER TABLE public.orders DISABLE TRIGGER ALL;



ALTER TABLE public.orders ENABLE TRIGGER ALL;


ALTER TABLE public.producers DISABLE TRIGGER ALL;

INSERT INTO public.producers (id, name, subject, description) VALUES ('b90814ae-04e5-4703-bddf-03e61f56cc3a', 'Quetzal', 'Organic chocolates from Modica', 'Modica''s famous organic chocolate is still made according to ancient Aztec recipes and methods. The tradition was brought to Modica in the 16th century by the Spanish, who had learned the secrets of making chocolate on their voyages of discovery to the New World, in what is now Mexico. Later, chocolate spread to the rest of Europe, and the methods and ingredients changed. Modica is the only town in Europe where chocolate is still made by the original methods. Modica chocolate differs from ordinary chocolate in its sandy or grainy texture, among other things. No high temperatures are used in making it, so part of the sugar doesn''t melt but stays as grains. That way the sugar only melts at last in the taster''s mouth!

Quetzal is a Fair Trade cooperative that works with partners in Guatemala and Ecuador, among others.

<http://www.cioccolato-quetzal.it>');
INSERT INTO public.producers (id, name, subject, description) VALUES ('3c49ba6b-f716-4ec1-9598-ddd04601f822', 'Valdibella', 'Organic almonds', 'Valdibella''s almonds are local Sicilian varieties: Tuono, Genco, Supernova Ferragnes, Romana, Pizzuta and Fascionello. The almonds are harvested in August and September. After the harvest they are dried in the sun for 3-4 days.

Valdibella is a cooperative founded in 1989 by local farmers in the province of Palermo. It focuses on wine, olives, almonds and grain, among others.

<http://www.valdibella.com/>');
INSERT INTO public.producers (id, name, subject, description) VALUES ('43156171-db64-4afa-922a-f5c91a34aecd', 'Bonomo & Giglio', 'Organic capers and Zibibbo raisins from Pantelleria', 'The famous capers of the island of Pantelleria. The caper is a common plant in Southern Europe, whose unopened flower buds are picked and salted. An excellent addition to salads, pasta sauces, pizza and meat dishes.

Bonomo & Giglio is one of the oldest caper producers on the island of Pantelleria.

<http://www.lanicchia.com>');
INSERT INTO public.producers (id, name, subject, description) VALUES ('054a4366-24a6-45c7-9fd9-d445c65f4219', 'Bosco Falconeria', 'Organic extra virgin olive oil and wine vinegar', 'Our farm, Bosco Falconeria, is a small organic farm in Sicily near Palermo. We produce organic wine, organic olive oil, wine vinegar and organic vegetables and fruit, among other things. We are one of the first farms in Western Sicily to have switched fully to organic farming. We aim to support and promote biodiversity, sustainable development and an ecological way of life. We also take part in the anti-mafia Addio Pizzo movement and in the Slow Food movement.

<http://www.boscofalconeria.it>

<http://www.facebook.com/boscofalconeria>');
INSERT INTO public.producers (id, name, subject, description) VALUES ('ebb59d33-10e3-4399-ad8d-6866c126e0d3', 'Lorcam', 'Pistachios', 'Bronte is a small town on the slopes of Mount Etna in eastern Sicily. Bronte is famous for its unique pistachios. They taste slightly sweet, and their color is a beautiful emerald green. The nuts grow in Etna''s volcanic soil and are rich in nutrients. The pistachios have the DOP quality label (Denominazione Origine Protetta) and are protected by the SLOW FOOD movement.

LORCAM is a pistachio company founded by the younger generation of a family of pistachio growers from Bronte.

<http://www.lorcamfood.com>');
INSERT INTO public.producers (id, name, subject, description) VALUES ('4a9cb47a-c19f-48df-ac3a-837a14d78e9f', 'Stramondo', 'Organic marzipan', 'Sicilian almond varieties are considered first-class for their flavor and nutritional value. These gourmet almonds are excellent for making sweets and pastries, among other things. Marzipan, made of almonds and sugar or honey, is a common ingredient in many Sicilian pastries. Well-known ones are the marzipan fruits of Martorana, cassata and traditional almond milk.

Stramondo is a company in Western Sicily that focuses on producing ingredients for confectioners.

<http://www.stramondo.it>');


ALTER TABLE public.producers ENABLE TRIGGER ALL;


ALTER TABLE public.products DISABLE TRIGGER ALL;

INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('fa27ca70-14de-4165-b31c-1a70d96a5175', 'Zibibbo raisins', 980, '43156171-db64-4afa-922a-f5c91a34aecd', 'uva passa zibibbo in grappolo, sacchetto

"Zibibbo Muscat raisins, aromatic, sweet and soft. The seeds inside the raisins give a crunchy note but they are neither hard not tannic when you chew them. They are sun-dried and packed as a whole a cluster for the pleasure of picking raisin after raisin from the grape-stalk. Ideal as a dessert at the end of a meal, energizing after sports and excellent for making cakes and desserts."', '250 g');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('95abe179-aa15-4a80-babe-b8bbedef0cb9', 'Basil flower wine vinegar', 550, '054a4366-24a6-45c7-9fd9-d445c65f4219', 'Aceto di vino bianco aromatizzato ai fiori di basilico', '250 ml glass bottle');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('16391745-e05d-4e44-aea1-6c6ac972c59d', 'Bronte pistachios, dried', 820, 'ebb59d33-10e3-4399-ad8d-6866c126e0d3', 'Pistacchio verde di Bronte DOP, sgusciato', '100 g');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('c5292736-21d4-4846-a192-2447ef3fdf9f', 'Chili chocolate', 410, 'b90814ae-04e5-4703-bddf-03e61f56cc3a', 'cioccolato al peperoncino bio', '60 g');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('2d6198a5-6ca6-4b4a-8851-931d13c853ad', 'Ginger chocolate', 410, 'b90814ae-04e5-4703-bddf-03e61f56cc3a', 'cioccolato allo zenzero bio', '60 g');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('2b67b2dd-c5d2-48fa-b110-098dfd0e2688', 'Coffee chocolate', 410, 'b90814ae-04e5-4703-bddf-03e61f56cc3a', 'cioccolato al caffé bio', '60 g');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('14c0e00b-3331-4816-aee6-bfd7bc35d8d9', 'Cinnamon chocolate', 410, 'b90814ae-04e5-4703-bddf-03e61f56cc3a', 'cioccolato alla cannella bio', '60 g');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('ef8d7a42-7c13-42c6-a4e0-f2947a08b865', 'Organic capers in salt', 860, '43156171-db64-4afa-922a-f5c91a34aecd', 'capperi biologici al sale, sacchetto', '200 g');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('8e153c75-45c8-47ea-94d9-05f68e72da33', 'Organic almonds, shelled', 1010, '3c49ba6b-f716-4ec1-9598-ddd04601f822', 'Mandorle biologiche, sgusciate', '500g');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('9244ef2a-ad53-4349-a1f1-cf78f22a9ce5', 'Organic marzipan', 610, '4a9cb47a-c19f-48df-ac3a-837a14d78e9f', 'Marzapane biologico', '250 g');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('6d287d19-7480-41da-91ab-d2fa6ea1a9c9', 'Mint and lavender wine vinegar', 550, '054a4366-24a6-45c7-9fd9-d445c65f4219', 'Aceto di vino bianco aromatizzato alla lavanda e menta', '250 ml glass bottle');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('61db0ec5-698a-4b48-b19b-995d41472bb1', 'Olive oil', 750, '054a4366-24a6-45c7-9fd9-d445c65f4219', 'Olio extra vergine d''oliva (2021)', '250 ml glass bottle');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('0fa0cd0f-921a-429e-a184-3a9a547f0990', 'Olive oil', 5100, '054a4366-24a6-45c7-9fd9-d445c65f4219', 'Olio extra vergine d''oliva (2021)

Since 2008 we have been sending our oil to a small group of subscribers in Helsinki. Our olive oil is made from these olive varieties: Biancolilla, Cerasuola and Nocellara. The olives are picked by hand and cold-pressed right away into high-quality olive oil. Its color is deep green, and its taste fruity and slightly spicy. Our oil is cloudy, that is, it hasn''t been filtered. That way the oil keeps its flavorful aromas and its natural nutrients. The oil can be ordered in tins (3 l) and in small gift bottles (250 ml).', '3 l tin');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('57fa998f-04ca-4a00-a7f7-b1b12b85772f', 'Sesame and orange chocolate', 450, 'b90814ae-04e5-4703-bddf-03e61f56cc3a', 'sherazade, cioccolato con sesamo e arancia bio', '60 g');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('665599eb-3a59-4c8a-865f-be5420183fa3', 'Salt chocolate', 450, 'b90814ae-04e5-4703-bddf-03e61f56cc3a', 'salis (salt from the WWF-protected salt pans of Trapani)', '60 g');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('aab46947-1f96-45bd-b907-e709b00eb85b', 'White wine vinegar', 440, '054a4366-24a6-45c7-9fd9-d445c65f4219', 'Aceto di vino bianco', '250 ml glass bottle');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('b18d1345-085d-4e9d-81aa-01d1e132d4d9', 'White wine vinegar', 650, '054a4366-24a6-45c7-9fd9-d445c65f4219', 'Aceto di vino bianco

Our wine vinegar is made by traditional methods from our own organic wines (Nero d''Avola, Catarratto). The vinegar has matured for a long time in oak and chestnut barrels.
www.boscofalconeria.it/en/vinegar.html', '500 ml glass bottle');


ALTER TABLE public.products ENABLE TRIGGER ALL;


ALTER TABLE public.ordered_products DISABLE TRIGGER ALL;



ALTER TABLE public.ordered_products ENABLE TRIGGER ALL;


ALTER TABLE public.welcome_messages DISABLE TRIGGER ALL;

INSERT INTO public.welcome_messages (id, text, published_at, is_ordering_enabled) VALUES ('618c00ce-0c88-47f2-a863-b6198c94b6d7', 'The olive harvest is over, and olive oil and other delicacies can be ordered again.
Our red wine vinegar isn''t available at the moment, as our vinegar bacteria have been unusually slow this year and the vinegar isn''t ready yet.
Sun-dried tomatoes aren''t available because of a poor harvest.
We didn''t get oregano on the list either.

Delicacies you can order:

-  Bosco Falconeria organic olive oil and wine vinegars
-  Organic chocolates from Modica
-  Organic capers and Zibibbo raisins from Pantelleria
-  Organic marzipan
-  Bronte pistachios
-  Organic almonds



We take orders until NOVEMBER 12!', '2022-04-29 11:36:56.661449+03', true);


ALTER TABLE public.welcome_messages ENABLE TRIGGER ALL;


