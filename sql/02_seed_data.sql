-- Wine Cellar Management System — sample data
--
-- Every row is invented. See the "About the data" section of the README:
-- the producer names and appellations are real reference data, but the
-- collectors, bottles, prices, dates, ratings and tasting notes are all
-- fabricated to exercise the schema.
--
-- 4 collectors, 6 producers, 4 storage locations, 15 wines, 18 tastings,
-- 27 bottles consumed.

INSERT INTO Collector VALUES (1, 'John Smith', 'john.smith@example.com');
INSERT INTO Collector VALUES (2, 'Emily Johnson', 'emily.johnson@example.com');
INSERT INTO Collector VALUES (3, 'Michael Brown', 'michael.brown@example.com');
INSERT INTO Collector VALUES (4, 'Sarah Davis', 'sarah.davis@example.com');

INSERT INTO Producer VALUES (1, 'Antinori', 'Tuscany', 'Italy');
INSERT INTO Producer VALUES (2, 'Gaja', 'Piedmont', 'Italy');
INSERT INTO Producer VALUES (3, 'Sassicaia', 'Tuscany', 'Italy');
INSERT INTO Producer VALUES (4, 'Fontodi', 'Tuscany', 'Italy');
INSERT INTO Producer VALUES (5, 'Marchesi di Barolo', 'Piedmont', 'Italy');
INSERT INTO Producer VALUES (6, 'Allegrini', 'Veneto', 'Italy');

INSERT INTO Location VALUES (1, 'Main Cellar', 14.0, 70.0, 500);
INSERT INTO Location VALUES (2, 'Basement Storage', 13.5, 65.0, 200);
INSERT INTO Location VALUES (3, 'Wine Refrigerator', 12.0, 60.0, 50);
INSERT INTO Location VALUES (4, 'Guest House Cellar', 15.0, 68.0, 100);

-- wine_id, collector, producer, location, wine_name, grape, appellation,
-- vintage, purchase_date, price, bottles_purchased, drink_from, drink_until
INSERT INTO Wine VALUES (1,  1, 1, 1, 'Chianti Classico',           'Sangiovese',         'Chianti Classico DOCG',           2018, '2020-03-15',  45.50, 6, 2023, 2028);
INSERT INTO Wine VALUES (2,  1, 2, 1, 'Barolo',                     'Nebbiolo',           'Barolo DOCG',                     2016, '2021-05-20', 120.00, 3, 2026, 2036);
INSERT INTO Wine VALUES (3,  1, 3, 2, 'Bolgheri Superiore',         'Cabernet Sauvignon', 'Bolgheri DOC',                    2019, '2022-01-10', 180.00, 2, 2029, 2039);
INSERT INTO Wine VALUES (4,  2, 1, 1, 'Brunello di Montalcino',     'Sangiovese',         'Brunello di Montalcino DOCG',     2020, '2023-06-15',  95.00, 4, 2028, 2038);
INSERT INTO Wine VALUES (5,  2, 4, 2, 'Chianti Classico',           'Sangiovese',         'Chianti Classico DOCG',           2017, '2020-11-20',  65.00, 5, 2022, 2027);
INSERT INTO Wine VALUES (6,  2, 5, 1, 'Barolo Riserva',             'Nebbiolo',           'Barolo DOCG',                     2015, '2021-08-05', 150.00, 2, 2025, 2040);
INSERT INTO Wine VALUES (7,  3, 6, 3, 'Amarone della Valpolicella', 'Corvina',            'Amarone della Valpolicella DOCG', 2021, '2023-12-01',  85.00, 6, 2026, 2036);
INSERT INTO Wine VALUES (8,  3, 1, 3, 'Tignanello',                 'Sangiovese',         'Toscana IGT',                     2019, '2022-03-18', 110.00, 3, 2024, 2034);
INSERT INTO Wine VALUES (9,  3, 2, 2, 'Barbaresco',                 'Nebbiolo',           'Barbaresco DOCG',                 2018, '2023-02-14',  98.00, 4, 2023, 2033);
INSERT INTO Wine VALUES (10, 4, 3, 4, 'Bolgheri Rosso',             'Cabernet Sauvignon', 'Bolgheri DOC',                    2020, '2023-09-10',  75.00, 5, 2025, 2030);
INSERT INTO Wine VALUES (11, 4, 4, 4, 'Chianti Classico Riserva',   'Sangiovese',         'Chianti Classico DOCG',           2019, '2022-07-22',  55.00, 8, 2024, 2029);
INSERT INTO Wine VALUES (12, 1, 5, 1, 'Nebbiolo d''Alba',           'Nebbiolo',           'Nebbiolo d''Alba DOC',            2017, '2021-10-30',  88.00, 3, 2022, 2032);
INSERT INTO Wine VALUES (13, 2, 6, 2, 'Valpolicella Superiore',     'Corvina',            'Valpolicella Superiore DOC',      2020, '2023-05-15',  42.00, 6, 2023, 2028);
INSERT INTO Wine VALUES (14, 3, 1, 3, 'Solaia',                     'Cabernet Sauvignon', 'Toscana IGT',                     2016, '2020-12-20', 250.00, 2, 2026, 2041);
INSERT INTO Wine VALUES (15, 4, 2, 4, 'Barbaresco',                 'Nebbiolo',           'Barbaresco DOCG',                 2019, '2023-01-08', 195.00, 3, 2024, 2034);

-- tasting_id, wine, taster, date, rating, notes, pairing
-- Tasters are a mix of owners and guests, so the cross-collector case is
-- present in the data rather than only possible in the schema.
INSERT INTO Tasting VALUES (1,  1,  1, '2023-12-25', 4, 'Fruity with cherry notes and good acidity. Medium body with smooth tannins.', 'Pasta with tomato sauce');
INSERT INTO Tasting VALUES (2,  1,  2, '2024-06-10', 5, 'Excellent balance, more complex than first tasting. Ready to drink now.', 'Grilled steak');
INSERT INTO Tasting VALUES (3,  2,  1, '2023-11-15', 5, 'Powerful and structured. Notes of rose, tar, and red fruits. Still needs time.', 'Braised beef');
INSERT INTO Tasting VALUES (4,  3,  3, '2024-01-20', 4, 'Rich and full-bodied with blackcurrant and cedar. Long finish.', 'Lamb chops');
INSERT INTO Tasting VALUES (5,  4,  2, '2024-07-04', 5, 'Outstanding Brunello. Complex with leather, tobacco, and dark cherry.', 'Wild boar ragu');
INSERT INTO Tasting VALUES (6,  5,  2, '2023-08-30', 3, 'Good but a bit young. Bright acidity with red fruit flavors.', 'Margherita pizza');
INSERT INTO Tasting VALUES (7,  6,  4, '2024-02-14', 5, 'Magnificent Barolo Riserva. Layers of flavor with velvety texture.', 'Truffle risotto');
INSERT INTO Tasting VALUES (8,  7,  3, '2024-03-10', 4, 'Rich Amarone with dried fruit and chocolate notes. Well balanced.', 'Aged cheese');
INSERT INTO Tasting VALUES (9,  8,  3, '2023-10-05', 5, 'Classic Tignanello. Elegant with blackberry, vanilla, and spice.', 'Bistecca fiorentina');
INSERT INTO Tasting VALUES (10, 9,  1, '2024-05-18', 4, 'Refined Barbaresco with floral aromas and red cherry. Elegant tannins.', 'Roasted duck');
INSERT INTO Tasting VALUES (11, 10, 4, '2024-08-22', 4, 'Well-made Bolgheri with good structure and berry fruit character.', 'Grilled vegetables');
INSERT INTO Tasting VALUES (12, 11, 4, '2023-09-12', 4, 'Solid Chianti Riserva. Bright acidity with cherry and herbs.', 'Tomato bruschetta');
INSERT INTO Tasting VALUES (13, 12, 1, '2024-01-30', 3, 'Decent Nebbiolo but still quite tannic. Needs more aging.', 'Mushroom risotto');
INSERT INTO Tasting VALUES (14, 13, 2, '2024-04-25', 4, 'Pleasant Valpolicella with cherry and almond notes. Easy drinking.', 'Pasta carbonara');
INSERT INTO Tasting VALUES (15, 14, 3, '2023-12-31', 5, 'Exceptional Super Tuscan. Complex, powerful, perfectly balanced.', 'Prime ribeye steak');
INSERT INTO Tasting VALUES (16, 1,  1, '2024-10-15', 4, 'Third tasting - wine is evolving beautifully. More tertiary notes.', 'Pork roast');
INSERT INTO Tasting VALUES (17, 7,  4, '2024-09-08', 5, 'Second tasting confirms this is an excellent vintage Amarone.', 'Blue cheese');
INSERT INTO Tasting VALUES (18, 11, 2, '2024-11-20', 5, 'Improved significantly. Now showing great complexity and depth.', 'Osso buco');

-- Bottles leaving the cellar. Every tasting opened a bottle, so each of the 18
-- above has a matching row here. Nine more bottles were drunk without anyone
-- writing a note, which is the FK_tasting_id IS NULL case the schema allows.
INSERT INTO Consumption (consumption_id, FK_wine_id, FK_tasting_id, consumed_date, bottles, occasion) VALUES
    (1,  1,  1,    '2023-12-25', 1, 'Christmas dinner'),
    (2,  1,  2,    '2024-06-10', 1, 'Summer barbecue'),
    (3,  2,  3,    '2023-11-15', 1, 'Sunday roast'),
    (4,  3,  4,    '2024-01-20', 1, 'Anniversary'),
    (5,  4,  5,    '2024-07-04', 1, 'Fourth of July'),
    (6,  5,  6,    '2023-08-30', 1, 'Pizza night'),
    (7,  6,  7,    '2024-02-14', 1, 'Valentine''s dinner'),
    (8,  7,  8,    '2024-03-10', 1, 'Cheese course'),
    (9,  8,  9,    '2023-10-05', 1, 'Steak dinner'),
    (10, 9,  10,   '2024-05-18', 1, 'Dinner party'),
    (11, 10, 11,   '2024-08-22', 1, 'Garden lunch'),
    (12, 11, 12,   '2023-09-12', 1, 'Aperitivo'),
    (13, 12, 13,   '2024-01-30', 1, 'Risotto night'),
    (14, 13, 14,   '2024-04-25', 1, 'Weeknight pasta'),
    (15, 14, 15,   '2023-12-31', 1, 'New Year''s Eve'),
    (16, 1,  16,   '2024-10-15', 1, 'Sunday lunch'),
    (17, 7,  17,   '2024-09-08', 1, 'Late supper'),
    (18, 11, 18,   '2024-11-20', 1, 'Birthday dinner'),
    -- Opened, no note written.
    (19, 1,  NULL, '2025-02-08', 1, 'Weeknight dinner'),
    (20, 1,  NULL, '2025-05-30', 1, 'Friends visiting'),
    (21, 5,  NULL, '2024-09-14', 1, 'Weeknight dinner'),
    (22, 5,  NULL, '2025-01-11', 1, 'Weeknight dinner'),
    (23, 5,  NULL, '2025-04-19', 1, 'Picnic'),
    (24, 11, NULL, '2025-03-22', 1, 'Weeknight dinner'),
    (25, 13, NULL, '2024-11-02', 1, 'Weeknight dinner'),
    (26, 13, NULL, '2025-06-07', 1, 'Weeknight dinner'),
    (27, 14, NULL, '2025-08-16', 1, 'Last bottle, no notes taken');
