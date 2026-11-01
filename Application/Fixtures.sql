

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

INSERT INTO public.producers (id, name, subject, description) VALUES ('b90814ae-04e5-4703-bddf-03e61f56cc3a', 'Quetzal', 'Modican luomusuklaat', 'Modican kaupungin kuuluisaa luomusuklaata valmistetaan yhä muinaisten asteekien reseptien ja valmistusmetodian mukaan. Perinteen toivat Modicaan 1500-luvulla espanjalaiset, jotka olivat oppineet suklaan valmistuksen salat löytöretkillään uudelle mantereelle nykyisen Mexicon alueelle. Myöhemmin suklaa levisi muualle Eurooppaan ja valmistusmenetelmät ja raaka-aineet muuttuivat. Modica on aina kaupunki Euroopassa, jossa suklaata tehdään edelleen alkuperäisin menetelmin. Modican suklaa eroaa tavanomaisesta suklaasta mm. sen hiekkaisen tai rakeisen rakenteen johdosta. Valmistuksessa ei käytetä korkeita lämpötiloja, jolloin osa sokerista ei sula vaan jää rakeiksi. Näin sokereiden lopullinen sulaminen tapahtuu vasta maistajan suussa!

Quetzal on Reilun Kauppan osuuskunta, joka tekee yhteistyötä mm. Guatemalassa ja Ecuadorissa.

<http://www.cioccolato-quetzal.it>');
INSERT INTO public.producers (id, name, subject, description) VALUES ('3c49ba6b-f716-4ec1-9598-ddd04601f822', 'Valdibella', 'Luomumanteli', 'Valdibellan mantelit ovat paikallisia sisilialaisia lajikkeita; Tuono, Genco, Supernova Ferragnes, Romana, Pizzuta sekä Fascionello.  Mantelinkorjuu tapahtuu elo-syyskuussa.  Korjuun jälkeen mantelit kuivatetaan auringossa 3-4 päivää.

Valdibella on Palermon maakunnassa vuonna 1989 paikallisten maanviljeilijöiden perustama osuuskunta keskittyen mm. viinin, oliivien, manteleiden sekä viljan tuotantoon.

<http://www.valdibella.com/>');
INSERT INTO public.producers (id, name, subject, description) VALUES ('43156171-db64-4afa-922a-f5c91a34aecd', 'Bonomo & Giglio', 'Pantellerian luomukapris ja Zibibbo-rusinat', 'Pantellerian saaren kuuluisaa kaprista. Kapris on Etelä-Euroopassa yleinen kasvi, jonka avautumattomat kukkanuput kerätään ja suolataan. Erinomainen lisä salaatteihin, pastakastikkeisiin, pizzaan ja liharuokiin.

Bonomo & Giglio on yksi vanhimmista kapriksen tuottajista Pantellerian saarella.

<http://www.lanicchia.com>');
INSERT INTO public.producers (id, name, subject, description) VALUES ('054a4366-24a6-45c7-9fd9-d445c65f4219', 'Bosco Falconeria', 'Luomu ekstra-neitsytoliiviöljyä sekä viinietikkaa', 'Maatilamme Bosco Falconeria on pieni luomutila Sisiliassa lähellä Palermoa ja tuotamme mm. luomuviiniä, luomuoliiviöljyä, viinietikkaa sekä luomuvihanneksia ja -hedelmiä. Olemme Länsi-Sisilian ensimmäisiä täysin luomutuotantoon siirtyneitä maatiloja. Pyrimme tukemaan ja edistämään luonnon monimuotoisuutta, kestävää kehitystä ja ekologista elämäntapaa. Olemme osallisia myös mm. mafian vastaisessa Addio Pizzo-toiminnassa sekä Slow Food-liikkeessä.

<http://www.boscofalconeria.it>

<http://www.facebook.com/boscofalconeria>');
INSERT INTO public.producers (id, name, subject, description) VALUES ('ebb59d33-10e3-4399-ad8d-6866c126e0d3', 'Lorcam', 'Pistaasipähkinä', 'Bronte on pieni kaupunki Etna tulivuoren rinteellä Itä-Sisiliassa. Bronte on kuuluisa ainutlaatuisista pistaasipähkinöistään. Niiden maku on makeahko ja väri kauniin smaragdinvihreä. Pähkinät kasvavat Etnan vulkaanisella maaperällä ja sisältävät runsaasti ravintoaineita. Pistaaseilla on DOP-laatuluokitus (Denominazione Origine Protetta) ja ne ovat SLOW FOOD-liikkeen suojelemia.

LORCAM on brontelaisen pistaasikasvattajasuvun nuoremman polven perustama pistaasiyritys.

<http://www.lorcamfood.com>');
INSERT INTO public.producers (id, name, subject, description) VALUES ('4a9cb47a-c19f-48df-ac3a-837a14d78e9f', 'Stramondo', 'Luomumarsipaani', 'Sisilian mantelilajikkeita pidetään ensiluokkaisina makunsa ja ravintopitoisuutensa johdosta. Nämä gourmet-mantelit ovat erinomaisia mm. makeisten ja leivonnaisten valmistukseen. Erityisesti manteleista ja sokerista tai hunajasta valmistettu marsipaani on yleinen raaka-aine monissa sisilialaisissa leivonnaisissa. Tunnettuja ovat mm. Martoranan marsipaanihedelmät, Cassata ja perinteinen mantelimaito.

Stramondo on Länsi-Sisiliassa sijaitseva yritys, joka keskittyy sokerileipurien raaka-aineiden tuottamiseen.

<http://www.stramondo.it>');


ALTER TABLE public.producers ENABLE TRIGGER ALL;


ALTER TABLE public.products DISABLE TRIGGER ALL;

INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('fa27ca70-14de-4165-b31c-1a70d96a5175', 'Zibibbo rusinoita', 980, '43156171-db64-4afa-922a-f5c91a34aecd', 'uva passa zibibbo in grappolo, sacchetto

"Zibibbo Muscat raisins, aromatic, sweet and soft. The seeds inside the raisins give a crunchy note but they are neither hard not tannic when you chew them. They are sun-dried and packed as a whole a cluster for the pleasure of picking raisin after raisin from the grape-stalk. Ideal as a dessert at the end of a meal, energizing after sports and excellent for making cakes and desserts."', '250 g');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('95abe179-aa15-4a80-babe-b8bbedef0cb9', 'Basilikankukkaviinietikkaa', 550, '054a4366-24a6-45c7-9fd9-d445c65f4219', 'Aceto di vino bianco aromatizzato ai fiori di basilico', '250 ml lasipullo');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('16391745-e05d-4e44-aea1-6c6ac972c59d', 'Bronten pistaasipähkinöitä, kuivattuja', 820, 'ebb59d33-10e3-4399-ad8d-6866c126e0d3', 'Pistacchio verde di Bronte DOP, sgusciato', '100 g');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('c5292736-21d4-4846-a192-2447ef3fdf9f', 'Chilisuklaa', 410, 'b90814ae-04e5-4703-bddf-03e61f56cc3a', 'cioccolato al peperoncino bio', '60 g');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('2d6198a5-6ca6-4b4a-8851-931d13c853ad', 'Inkiväärisuklaa', 410, 'b90814ae-04e5-4703-bddf-03e61f56cc3a', 'cioccolato allo zenzero bio', '60 g');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('2b67b2dd-c5d2-48fa-b110-098dfd0e2688', 'Kahvisuklaa', 410, 'b90814ae-04e5-4703-bddf-03e61f56cc3a', 'cioccolato al caffé bio', '60 g');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('14c0e00b-3331-4816-aee6-bfd7bc35d8d9', 'Kanelisuklaa', 410, 'b90814ae-04e5-4703-bddf-03e61f56cc3a', 'cioccolato alla cannella bio', '60 g');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('ef8d7a42-7c13-42c6-a4e0-f2947a08b865', 'Luomukaprista suolassa', 860, '43156171-db64-4afa-922a-f5c91a34aecd', 'capperi biologici al sale, sacchetto', '200 g');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('8e153c75-45c8-47ea-94d9-05f68e72da33', 'Luomumantelit, kuorellinen', 1010, '3c49ba6b-f716-4ec1-9598-ddd04601f822', 'Mandorle biologiche, sgusciate', '500g');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('9244ef2a-ad53-4349-a1f1-cf78f22a9ce5', 'Luomumarsipaania', 610, '4a9cb47a-c19f-48df-ac3a-837a14d78e9f', 'Marzapane biologico', '250 g');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('6d287d19-7480-41da-91ab-d2fa6ea1a9c9', 'Minttu-laventeliviinietikkaa', 550, '054a4366-24a6-45c7-9fd9-d445c65f4219', 'Aceto di vino bianco aromatizzato alla lavanda e menta', '250 ml lasipullo');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('61db0ec5-698a-4b48-b19b-995d41472bb1', 'Oliiviöljyä', 750, '054a4366-24a6-45c7-9fd9-d445c65f4219', 'Olio extra vergine d''oliva (2021)', '250 ml lasipullo');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('0fa0cd0f-921a-429e-a184-3a9a547f0990', 'Oliiviöljyä', 5100, '054a4366-24a6-45c7-9fd9-d445c65f4219', 'Olio extra vergine d''oliva (2021)

Vuodesta 2008 olemme lähettäneet öljyä Helsinkiin pienelle tilaajaryhmälle. Oliiviöljyssämme on käytetty seuraavia oliivilajikkeita; Biancolilla, Cerasuola ja Nocellara. Oliivit poimitaan käsin ja välittömästi kylmäpuristetaan korkealuokkaiseksi oliiviöljyksi. Väri on syvän vihreää, maku hedelmäistä ja hieman mausteista. Öljyämme on sameaa ts. sitä ei ole suodatettu. Näin öljyssä säilyy sen maukkaat aromit sekä luontaiset terveelliset ravintoarvot. Öljyä on tilattavissa peltikanistereissa (3 l) sekä pienissä lahjapulloissa (250 ml).', '3 l kanisteri');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('57fa998f-04ca-4a00-a7f7-b1b12b85772f', 'Sesam-appelsiinisuklaa', 450, 'b90814ae-04e5-4703-bddf-03e61f56cc3a', 'sherazade, cioccolato con sesamo e arancia bio', '60 g');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('665599eb-3a59-4c8a-865f-be5420183fa3', 'Suolasuklaa', 450, 'b90814ae-04e5-4703-bddf-03e61f56cc3a', 'salis (suola WWF:n suojelemalta Trapanin suola-altailta)', '60 g');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('aab46947-1f96-45bd-b907-e709b00eb85b', 'Valkoviinietikkaa', 440, '054a4366-24a6-45c7-9fd9-d445c65f4219', 'Aceto di vino bianco', '250 ml lasipullo');
INSERT INTO public.products (id, name, price, producer_id, description, package) VALUES ('b18d1345-085d-4e9d-81aa-01d1e132d4d9', 'Valkoviinietikkaa', 650, '054a4366-24a6-45c7-9fd9-d445c65f4219', 'Aceto di vino bianco

Viinietikkamme on perinteisin menetelmin valmistettu omista luomuviineistämme (Nero d''Avola, Catarratto).  Etikka on kypsynyt pitkään tammi- ja kastanjatunnyreissä.
www.boscofalconeria.it/en/vinegar.html', '500 ml lasipullo');


ALTER TABLE public.products ENABLE TRIGGER ALL;


ALTER TABLE public.ordered_products DISABLE TRIGGER ALL;



ALTER TABLE public.ordered_products ENABLE TRIGGER ALL;


ALTER TABLE public.welcome_messages DISABLE TRIGGER ALL;

INSERT INTO public.welcome_messages (id, text, published_at) VALUES ('618c00ce-0c88-47f2-a863-b6198c94b6d7', 'Oliivinpoiminta on päättynyt ja oliiviöljyä ym. herkkuja on taas tilattavissa.
Punaviinietikkaamme ei ole tällä hetkellä tarjolla, sillä etikkabakteerimme on tänä vuonna ollut poikkeuksellisen hidas eikä etikka ole vielä valmista.
Aurinkokuivattuja tomaatteja ei ole saatavilla huonon satovuoden johdosta.
Oreganoa emme myöskään saaneet listalle.

Tilattavissa olevat herkut:

-  Bosco Falconeria luomuoliiviöljy ja viinietikat
-  Modican luomusuklaat
-  Pantellerian luomukapris ja Zibibbo-rusinat
-  Luomumarsipaani
-  Bronten pistaasipähkinät
-  Luomumantelit



Otamme tilauksia vastaan MARRASKUUN 12. päivään asti!', '2022-04-29 11:36:56.661449+03');


ALTER TABLE public.welcome_messages ENABLE TRIGGER ALL;


