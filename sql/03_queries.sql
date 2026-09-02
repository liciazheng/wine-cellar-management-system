-- Wine Cellar Management System — analytical queries
-- Each query answers one of the use cases the schema was built for.

-- Q1. Full collection inventory: every bottle with its producer and owner.
--     Wine name, grape and appellation are separate columns, so the same
--     inventory can be sliced by any of the three.
SELECT
    Wine.wine_id,
    Wine.wine_name,
    Wine.vintage_year,
    Wine.grape_varietal,
    Wine.appellation,
    Producer.producer_name,
    Producer.region,
    Collector.name AS collector_name,
    Wine.quantity,
    Wine.purchase_price
FROM Wine
JOIN Producer  ON Wine.FK_producer_id  = Producer.producer_id
JOIN Collector ON Wine.FK_collector_id = Collector.collector_id
ORDER BY Collector.name, Wine.vintage_year;


-- Q2. What should I drink this year?
--     The motivating question for the whole project. Two integer columns make
--     it a BETWEEN, where a '2023-2028' string needed parsing.
--     `urgency` flags bottles whose window is about to close.
SELECT
    Wine.wine_name,
    Wine.vintage_year,
    Wine.grape_varietal,
    Producer.producer_name,
    Collector.name AS collector_name,
    Location.cellar_name,
    Wine.quantity,
    Wine.drink_from,
    Wine.drink_until,
    Wine.drink_until - CAST(strftime('%Y', 'now') AS INTEGER) AS years_left,
    CASE
        WHEN Wine.drink_until - CAST(strftime('%Y', 'now') AS INTEGER) <= 1 THEN 'drink now'
        WHEN Wine.drink_until - CAST(strftime('%Y', 'now') AS INTEGER) <= 3 THEN 'drink soon'
        ELSE 'holding well'
    END AS urgency
FROM Wine
JOIN Producer  ON Wine.FK_producer_id  = Producer.producer_id
JOIN Collector ON Wine.FK_collector_id = Collector.collector_id
JOIN Location  ON Wine.FK_location_id  = Location.location_id
WHERE CAST(strftime('%Y', 'now') AS INTEGER) BETWEEN Wine.drink_from AND Wine.drink_until
ORDER BY years_left, Wine.wine_name;


-- Q3. Wine ranking by average tasting score.
SELECT
    Wine.wine_id,
    Wine.wine_name,
    Wine.vintage_year,
    Wine.grape_varietal,
    Producer.producer_name,
    AVG(Tasting.rating)       AS avg_rating,
    COUNT(Tasting.tasting_id) AS num_tastings
FROM Wine
JOIN Producer ON Wine.FK_producer_id = Producer.producer_id
JOIN Tasting  ON Wine.wine_id        = Tasting.FK_wine_id
GROUP BY Wine.wine_id
HAVING COUNT(Tasting.tasting_id) > 0
ORDER BY avg_rating DESC, num_tastings DESC;


-- Q4. Holdings by grape varietal.
--     Only possible now that the varietal is its own column.
SELECT
    Wine.grape_varietal,
    COUNT(DISTINCT Wine.wine_id) AS labels,
    SUM(Wine.quantity)           AS total_bottles,
    ROUND(SUM(Wine.purchase_price * Wine.quantity), 2) AS total_value,
    ROUND(AVG(Wine.purchase_price), 2)                 AS avg_bottle_price,
    COUNT(DISTINCT Wine.appellation)                   AS appellations
FROM Wine
GROUP BY Wine.grape_varietal
ORDER BY total_bottles DESC;


-- Q5. Cellar utilisation and storage conditions.
SELECT
    Location.location_id,
    Location.cellar_name,
    Location.temperature,
    Location.humidity,
    COUNT(Wine.wine_id) AS total_wines,
    SUM(Wine.quantity)  AS total_bottles,
    Location.capacity,
    (SUM(Wine.quantity) * 100.0 / Location.capacity) AS capacity_used_percent
FROM Location
JOIN Wine ON Location.location_id = Wine.FK_location_id
GROUP BY Location.location_id
ORDER BY capacity_used_percent DESC;


-- Q6. Highly rated tastings, with the person who wrote the note.
SELECT
    Wine.wine_name,
    Wine.vintage_year,
    Producer.producer_name,
    Taster.name AS tasted_by,
    Owner.name  AS owned_by,
    Tasting.rating,
    Tasting.tasting_date,
    Tasting.tasting_notes,
    Tasting.food_pairing
FROM Tasting
JOIN Wine      ON Tasting.FK_wine_id      = Wine.wine_id
JOIN Producer  ON Wine.FK_producer_id     = Producer.producer_id
JOIN Collector Taster ON Tasting.FK_taster_id  = Taster.collector_id
JOIN Collector Owner  ON Wine.FK_collector_id  = Owner.collector_id
WHERE Tasting.rating >= 4
ORDER BY Tasting.rating DESC, Tasting.tasting_date DESC;


-- Q7. Notes written on someone else's bottle.
--     The shared-tasting case: two joins back to Collector from the same
--     tasting row, filtered to where taster and owner differ.
SELECT
    Taster.name AS tasted_by,
    Owner.name  AS bottle_owner,
    Wine.wine_name,
    Wine.vintage_year,
    Tasting.rating,
    Tasting.tasting_date
FROM Tasting
JOIN Wine ON Tasting.FK_wine_id = Wine.wine_id
JOIN Collector Taster ON Tasting.FK_taster_id = Taster.collector_id
JOIN Collector Owner  ON Wine.FK_collector_id = Owner.collector_id
WHERE Tasting.FK_taster_id <> Wine.FK_collector_id
ORDER BY Tasting.tasting_date DESC;


-- Q8. Collector portfolio value.
SELECT
    Collector.collector_id,
    Collector.name,
    Collector.email,
    COUNT(DISTINCT Wine.wine_id) AS unique_wines,
    SUM(Wine.quantity)           AS total_bottles,
    ROUND(SUM(Wine.purchase_price * Wine.quantity), 2) AS total_investment,
    ROUND(AVG(Wine.purchase_price), 2)                 AS avg_bottle_price,
    COUNT(DISTINCT Producer.producer_id)               AS num_producers
FROM Collector
JOIN Wine     ON Collector.collector_id = Wine.FK_collector_id
JOIN Producer ON Wine.FK_producer_id    = Producer.producer_id
GROUP BY Collector.collector_id
ORDER BY total_investment DESC;
