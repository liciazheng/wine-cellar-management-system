-- Wine Cellar Management System — sample data
-- 4 collectors, 6 Italian producers, 4 storage locations, 15 wines, 18 tastings

INSERT INTO Collector VALUES (1, 'John Smith', 'john.smith@email.com');
INSERT INTO Collector VALUES (2, 'Emily Johnson', 'emily.johnson@email.com');
INSERT INTO Collector VALUES (3, 'Michael Brown', 'michael.brown@email.com');
INSERT INTO Collector VALUES (4, 'Sarah Davis', 'sarah.davis@email.com');

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

INSERT INTO Wine VALUES (1,  1, 1, 1, 2018, 'Chianti Classico',           '2020-03-15',  45.50, 6, '2023-2028');
INSERT INTO Wine VALUES (2,  1, 2, 1, 2016, 'Barolo',                     '2021-05-20', 120.00, 3, '2026-2036');
INSERT INTO Wine VALUES (3,  1, 3, 2, 2019, 'Cabernet Sauvignon',         '2022-01-10', 180.00, 2, '2029-2039');
INSERT INTO Wine VALUES (4,  2, 1, 1, 2020, 'Brunello di Montalcino',     '2023-06-15',  95.00, 4, '2028-2038');
INSERT INTO Wine VALUES (5,  2, 4, 2, 2017, 'Sangiovese',                 '2020-11-20',  65.00, 5, '2022-2027');
INSERT INTO Wine VALUES (6,  2, 5, 1, 2015, 'Barolo Riserva',             '2021-08-05', 150.00, 2, '2025-2040');
INSERT INTO Wine VALUES (7,  3, 6, 3, 2021, 'Amarone della Valpolicella', '2023-12-01',  85.00, 6, '2026-2036');
INSERT INTO Wine VALUES (8,  3, 1, 3, 2019, 'Tignanello',                 '2022-03-18', 110.00, 3, '2024-2034');
INSERT INTO Wine VALUES (9,  3, 2, 2, 2018, 'Barbaresco',                 '2023-02-14',  98.00, 4, '2023-2033');
INSERT INTO Wine VALUES (10, 4, 3, 4, 2020, 'Bolgheri Rosso',             '2023-09-10',  75.00, 5, '2025-2030');
INSERT INTO Wine VALUES (11, 4, 4, 4, 2019, 'Chianti Classico Riserva',   '2022-07-22',  55.00, 8, '2024-2029');
INSERT INTO Wine VALUES (12, 1, 5, 1, 2017, 'Nebbiolo',                   '2021-10-30',  88.00, 3, '2022-2032');
INSERT INTO Wine VALUES (13, 2, 6, 2, 2020, 'Valpolicella Superiore',     '2023-05-15',  42.00, 6, '2023-2028');
INSERT INTO Wine VALUES (14, 3, 1, 3, 2016, 'Solaia',                     '2020-12-20', 250.00, 2, '2026-2041');
INSERT INTO Wine VALUES (15, 4, 2, 4, 2019, 'Gaja Barbaresco',            '2023-01-08', 195.00, 3, '2024-2034');

INSERT INTO Tasting VALUES (1,  1,  '2023-12-25', 4, 'Fruity with cherry notes and good acidity. Medium body with smooth tannins.', 'Pasta with tomato sauce');
INSERT INTO Tasting VALUES (2,  1,  '2024-06-10', 5, 'Excellent balance, more complex than first tasting. Ready to drink now.', 'Grilled steak');
INSERT INTO Tasting VALUES (3,  2,  '2023-11-15', 5, 'Powerful and structured. Notes of rose, tar, and red fruits. Still needs time.', 'Braised beef');
INSERT INTO Tasting VALUES (4,  3,  '2024-01-20', 4, 'Rich and full-bodied with blackcurrant and cedar. Long finish.', 'Lamb chops');
INSERT INTO Tasting VALUES (5,  4,  '2024-07-04', 5, 'Outstanding Brunello. Complex with leather, tobacco, and dark cherry.', 'Wild boar ragu');
INSERT INTO Tasting VALUES (6,  5,  '2023-08-30', 3, 'Good but a bit young. Bright acidity with red fruit flavors.', 'Margherita pizza');
INSERT INTO Tasting VALUES (7,  6,  '2024-02-14', 5, 'Magnificent Barolo Riserva. Layers of flavor with velvety texture.', 'Truffle risotto');
INSERT INTO Tasting VALUES (8,  7,  '2024-03-10', 4, 'Rich Amarone with dried fruit and chocolate notes. Well balanced.', 'Aged cheese');
INSERT INTO Tasting VALUES (9,  8,  '2023-10-05', 5, 'Classic Tignanello. Elegant with blackberry, vanilla, and spice.', 'Bistecca fiorentina');
INSERT INTO Tasting VALUES (10, 9,  '2024-05-18', 4, 'Refined Barbaresco with floral aromas and red cherry. Elegant tannins.', 'Roasted duck');
INSERT INTO Tasting VALUES (11, 10, '2024-08-22', 4, 'Well-made Bolgheri with good structure and berry fruit character.', 'Grilled vegetables');
INSERT INTO Tasting VALUES (12, 11, '2023-09-12', 4, 'Solid Chianti Riserva. Bright acidity with cherry and herbs.', 'Tomato bruschetta');
INSERT INTO Tasting VALUES (13, 12, '2024-01-30', 3, 'Decent Nebbiolo but still quite tannic. Needs more aging.', 'Mushroom risotto');
INSERT INTO Tasting VALUES (14, 13, '2024-04-25', 4, 'Pleasant Valpolicella with cherry and almond notes. Easy drinking.', 'Pasta carbonara');
INSERT INTO Tasting VALUES (15, 14, '2023-12-31', 5, 'Exceptional Super Tuscan. Complex, powerful, perfectly balanced.', 'Prime ribeye steak');
INSERT INTO Tasting VALUES (16, 1,  '2024-10-15', 4, 'Third tasting - wine is evolving beautifully. More tertiary notes.', 'Pork roast');
INSERT INTO Tasting VALUES (17, 7,  '2024-09-08', 5, 'Second tasting confirms this is an excellent vintage Amarone.', 'Blue cheese');
INSERT INTO Tasting VALUES (18, 11, '2024-11-20', 5, 'Improved significantly. Now showing great complexity and depth.', 'Osso buco');
