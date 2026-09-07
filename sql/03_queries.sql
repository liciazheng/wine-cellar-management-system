-- Wine Cellar Management System — analytical queries
-- Each query answers one of the use cases the schema was built for.
--
-- Anything involving remaining stock goes through the WineStock view rather
-- than repeating the subtraction. See the Views section of 01_schema.sql.

-- Q1. Full collection inventory: every label with its producer and owner.
--     Wine name, grape and appellation are separate columns, so the same
--     inventory can be sliced by any of the three.
SELECT
    WineStock.wine_id,
    WineStock.wine_name,
    WineStock.vintage_year,
    WineStock.grape_varietal,
    WineStock.appellation,
    Producer.producer_name,
    Producer.region,
    Collector.name AS collector_name,
    WineStock.bottles_purchased,
    WineStock.bottles_drunk,
    WineStock.bottles_remaining,
    WineStock.purchase_price
FROM WineStock
JOIN Producer  ON WineStock.FK_producer_id  = Producer.producer_id
JOIN Collector ON WineStock.FK_collector_id = Collector.collector_id
ORDER BY Collector.name, WineStock.vintage_year;


-- Q2. What should I drink this year?
--     The motivating question for the whole project. Two integer columns make
--     it a BETWEEN, where a '2023-2028' string needed parsing. Bottles you
--     have already finished are excluded — being in the window is not enough.
SELECT
    WineStock.wine_name,
    WineStock.vintage_year,
    WineStock.grape_varietal,
    Producer.producer_name,
    Collector.name AS collector_name,
    Location.cellar_name,
    WineStock.bottles_remaining,
    WineStock.drink_from,
    WineStock.drink_until,
    WineStock.drink_until - CAST(strftime('%Y', 'now') AS INTEGER) AS years_left,
    CASE
        WHEN WineStock.drink_until - CAST(strftime('%Y', 'now') AS INTEGER) <= 1 THEN 'drink now'
        WHEN WineStock.drink_until - CAST(strftime('%Y', 'now') AS INTEGER) <= 3 THEN 'drink soon'
        ELSE 'holding well'
    END AS urgency
FROM WineStock
JOIN Producer  ON WineStock.FK_producer_id  = Producer.producer_id
JOIN Collector ON WineStock.FK_collector_id = Collector.collector_id
JOIN Location  ON WineStock.FK_location_id  = Location.location_id
WHERE CAST(strftime('%Y', 'now') AS INTEGER)
          BETWEEN WineStock.drink_from AND WineStock.drink_until
  AND WineStock.bottles_remaining > 0
ORDER BY years_left, WineStock.wine_name;


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
--     Only possible now that the varietal is its own column. Reported both as
--     bought and as still held, because they answer different questions.
SELECT
    WineStock.grape_varietal,
    COUNT(DISTINCT WineStock.wine_id)     AS labels,
    SUM(WineStock.bottles_purchased)      AS bottles_bought,
    SUM(WineStock.bottles_remaining)      AS bottles_on_hand,
    ROUND(SUM(WineStock.purchase_price * WineStock.bottles_purchased), 2) AS total_spend,
    ROUND(AVG(WineStock.purchase_price), 2)                              AS avg_bottle_price,
    COUNT(DISTINCT WineStock.appellation)                                AS appellations
FROM WineStock
GROUP BY WineStock.grape_varietal
ORDER BY bottles_bought DESC;


-- Q5. Cellar utilisation and storage conditions.
--     Straight from the view now. Utilisation counts what is on the racks.
SELECT
    cellar_name,
    temperature,
    humidity,
    labels_stored,
    bottles_bought,
    bottles_on_hand,
    capacity,
    capacity_used_percent
FROM CellarOccupancy
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


-- Q8. Collector portfolio: bought, drunk, and still held.
SELECT
    Collector.name,
    COUNT(DISTINCT WineStock.wine_id)      AS unique_wines,
    SUM(WineStock.bottles_purchased)       AS bottles_bought,
    SUM(WineStock.bottles_drunk)           AS bottles_drunk,
    SUM(WineStock.bottles_remaining)       AS bottles_on_hand,
    ROUND(SUM(WineStock.purchase_price * WineStock.bottles_purchased), 2) AS total_spend,
    ROUND(SUM(WineStock.purchase_price * WineStock.bottles_remaining), 2) AS value_on_hand,
    COUNT(DISTINCT WineStock.FK_producer_id)                             AS num_producers
FROM WineStock
JOIN Collector ON Collector.collector_id = WineStock.FK_collector_id
GROUP BY Collector.collector_id
ORDER BY total_spend DESC;


-- Q9. How fast is the cellar emptying, and when does each wine run out?
--     Rate is bottles drunk per year since purchase. Projecting stock forward
--     at that rate says which bottles will be gone before their window shuts
--     and which will still be sitting there after it does.
SELECT
    WineStock.wine_name,
    WineStock.vintage_year,
    Producer.producer_name,
    WineStock.bottles_purchased,
    WineStock.bottles_remaining,
    ROUND((julianday('now') - julianday(WineStock.purchase_date)) / 365.25, 1) AS years_owned,
    ROUND(WineStock.bottles_drunk * 365.25
          / (julianday('now') - julianday(WineStock.purchase_date)), 2)        AS bottles_per_year,
    CASE
        WHEN WineStock.bottles_remaining = 0 THEN 'finished'
        WHEN WineStock.bottles_drunk = 0     THEN 'untouched'
        -- CAST to INTEGER before TEXT, or ROUND leaves a '.0' on the year.
        ELSE CAST(CAST(CAST(strftime('%Y', 'now') AS INTEGER)
                  + ROUND(WineStock.bottles_remaining
                          * (julianday('now') - julianday(WineStock.purchase_date))
                          / 365.25 / WineStock.bottles_drunk) AS INTEGER) AS TEXT)
    END AS runs_out_around,
    WineStock.drink_until,
    -- The point of the projection: bottles you will still be holding after
    -- they are past their best.
    CASE
        WHEN WineStock.bottles_remaining = 0 OR WineStock.bottles_drunk = 0 THEN NULL
        WHEN CAST(strftime('%Y', 'now') AS INTEGER)
             + ROUND(WineStock.bottles_remaining
                     * (julianday('now') - julianday(WineStock.purchase_date))
                     / 365.25 / WineStock.bottles_drunk) > WineStock.drink_until
        THEN 'drinking too slowly'
        ELSE 'on track'
    END AS verdict
FROM WineStock
JOIN Producer ON WineStock.FK_producer_id = Producer.producer_id
ORDER BY bottles_per_year DESC, WineStock.wine_name;


-- Q10. The drinking log, by year.
--      How many bottles were opened, how many produced a written note, and
--      what the notes averaged. The gap between bottles and notes is the
--      reason FK_tasting_id is nullable.
SELECT
    strftime('%Y', Consumption.consumed_date) AS year,
    SUM(Consumption.bottles)                  AS bottles_opened,
    COUNT(Consumption.FK_tasting_id)          AS with_a_note,
    SUM(Consumption.bottles) - COUNT(Consumption.FK_tasting_id) AS without_a_note,
    ROUND(AVG(Tasting.rating), 2)             AS avg_rating_that_year
FROM Consumption
LEFT JOIN Tasting ON Consumption.FK_tasting_id = Tasting.tasting_id
GROUP BY year
ORDER BY year;


-- Q11. Wines that are gone — worth restocking?
--      Pairs what has been finished with how it actually rated, which is the
--      only version of this question a collector cares about.
SELECT
    WineStock.wine_name,
    WineStock.vintage_year,
    Producer.producer_name,
    WineStock.appellation,
    WineStock.bottles_purchased,
    WineStock.purchase_price,
    ROUND(AVG(Tasting.rating), 2)   AS avg_rating,
    COUNT(Tasting.tasting_id)       AS notes,
    MAX(Consumption.consumed_date)  AS last_bottle
FROM WineStock
JOIN Producer    ON WineStock.FK_producer_id = Producer.producer_id
JOIN Consumption ON Consumption.FK_wine_id   = WineStock.wine_id
LEFT JOIN Tasting ON Tasting.FK_wine_id      = WineStock.wine_id
WHERE WineStock.is_finished = 1
GROUP BY WineStock.wine_id
ORDER BY avg_rating DESC;
