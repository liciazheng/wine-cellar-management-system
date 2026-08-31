-- Wine Cellar Management System — analytical queries
-- Each query answers one of the use cases from the project proposal.

-- Q1. Full collection inventory: every bottle with its producer and owner.
--     Use case: "Search collection by region, varietal, vintage."
SELECT
    Wine.wine_id,
    Wine.vintage_year,
    Wine.grape_varietal,
    Producer.producer_name,
    Producer.region,
    Collector.name AS collector_name,
    Wine.quantity,
    Wine.purchase_price
FROM Wine
JOIN Producer  ON Wine.FK_producer_id  = Producer.producer_id
JOIN Collector ON Wine.FK_collector_id = Collector.collector_id
ORDER BY Collector.name, Wine.vintage_year;


-- Q2. Wine ranking by average tasting score.
--     Use case: decide which bottles are drinking best right now.
SELECT
    Wine.wine_id,
    Wine.grape_varietal,
    Wine.vintage_year,
    Producer.producer_name,
    AVG(Tasting.rating)        AS avg_rating,
    COUNT(Tasting.tasting_id)  AS num_tastings
FROM Wine
JOIN Producer ON Wine.FK_producer_id = Producer.producer_id
JOIN Tasting  ON Wine.wine_id        = Tasting.FK_wine_id
GROUP BY Wine.wine_id
HAVING COUNT(Tasting.tasting_id) > 0
ORDER BY avg_rating DESC, num_tastings DESC;


-- Q3. Cellar utilisation and storage conditions.
--     Use case: know which cellar is filling up and whether temp/humidity are in range.
SELECT
    Location.location_id,
    Location.cellar_name,
    Location.temperature,
    Location.humidity,
    COUNT(Wine.wine_id)  AS total_wines,
    SUM(Wine.quantity)   AS total_bottles,
    Location.capacity,
    (SUM(Wine.quantity) * 100.0 / Location.capacity) AS capacity_used_percent
FROM Location
JOIN Wine ON Location.location_id = Wine.FK_location_id
GROUP BY Location.location_id
ORDER BY capacity_used_percent DESC;


-- Q4. Highly rated tastings with notes and food pairings.
--     Use case: "Share tasting experiences with other users."
SELECT
    Wine.wine_id,
    Wine.grape_varietal,
    Wine.vintage_year,
    Producer.producer_name,
    Tasting.rating,
    Tasting.tasting_date,
    Tasting.tasting_notes,
    Tasting.food_pairing
FROM Wine
JOIN Producer ON Wine.FK_producer_id = Producer.producer_id
JOIN Tasting  ON Wine.wine_id        = Tasting.FK_wine_id
WHERE Tasting.rating >= 4
ORDER BY Tasting.rating DESC, Tasting.tasting_date DESC;


-- Q5. Collector portfolio value.
--     Use case: "Generate the value" of each collection.
SELECT
    Collector.collector_id,
    Collector.name,
    Collector.email,
    COUNT(DISTINCT Wine.wine_id)     AS unique_wines,
    SUM(Wine.quantity)               AS total_bottles,
    ROUND(SUM(Wine.purchase_price * Wine.quantity), 2) AS total_investment,
    ROUND(AVG(Wine.purchase_price), 2)                 AS avg_bottle_price,
    COUNT(DISTINCT Producer.producer_id)               AS num_producers
FROM Collector
JOIN Wine     ON Collector.collector_id = Wine.FK_collector_id
JOIN Producer ON Wine.FK_producer_id    = Producer.producer_id
GROUP BY Collector.collector_id
ORDER BY total_investment DESC;
