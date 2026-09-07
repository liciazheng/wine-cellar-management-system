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
    WineStock.appellation_name,
    WineStock.classification,
    WineStock.region,
    Producer.producer_name,
    Producer.home_region,
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
    COUNT(DISTINCT WineStock.FK_appellation_id)                          AS appellations
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
--
--     Two guards, both of which the first version of this query got wrong.
--     A rate annualised from a few weeks of ownership is not a rate: one
--     bottle opened a fortnight after purchase extrapolates to 26 a year,
--     which is not a NULL or an error but a plausible-looking wrong number,
--     so anything held under a year reports no rate at all. And purchase_date
--     is nullable, which made every derived column NULL without saying why.
--
--     The pace CTE also exists so the julianday expression is written once
--     rather than three times.
WITH pace AS (
    SELECT
        WineStock.*,
        (julianday('now') - julianday(WineStock.purchase_date)) / 365.25 AS years_owned
    FROM WineStock
),
rate AS (
    SELECT
        pace.*,
        CASE WHEN years_owned >= 1.0
             THEN bottles_drunk / years_owned
        END AS per_year
    FROM pace
),
projection AS (
    SELECT
        rate.*,
        CASE WHEN per_year > 0
             THEN CAST(strftime('%Y', 'now') AS INTEGER)
                  + CAST(ROUND(bottles_remaining / per_year) AS INTEGER)
        END AS runs_out_year
    FROM rate
)
SELECT
    projection.wine_name,
    projection.vintage_year,
    Producer.producer_name,
    projection.bottles_purchased,
    projection.bottles_remaining,
    ROUND(projection.years_owned, 1) AS years_owned,
    ROUND(projection.per_year, 2)    AS bottles_per_year,
    CASE
        WHEN projection.purchase_date IS NULL  THEN 'no purchase date'
        WHEN projection.years_owned < 1.0      THEN 'owned under a year'
        WHEN projection.bottles_remaining = 0  THEN 'finished'
        WHEN projection.bottles_drunk = 0      THEN 'untouched'
        ELSE CAST(projection.runs_out_year AS TEXT)
    END AS runs_out_around,
    projection.drink_until,
    -- The point of the projection: bottles you will still be holding after
    -- they are past their best.
    CASE
        WHEN projection.runs_out_year IS NULL              THEN NULL
        WHEN projection.bottles_remaining = 0              THEN NULL
        WHEN projection.runs_out_year > projection.drink_until THEN 'drinking too slowly'
        ELSE 'on track'
    END AS verdict
FROM projection
JOIN Producer ON projection.FK_producer_id = Producer.producer_id
ORDER BY projection.per_year DESC NULLS LAST, projection.wine_name;


-- Q10. The drinking log, by year.
--      How many bottles were opened, how many openings produced a written
--      note, and what those notes averaged. The gap is the reason
--      FK_tasting_id is nullable.
--
--      Openings and bottles are counted separately and never subtracted from
--      each other. An earlier version did `SUM(bottles) - COUNT(FK_tasting_id)`,
--      which mixed a bottle count with a row count. Every row in the sample
--      data opens exactly one bottle, so the two happened to agree and the
--      error stayed invisible until a single opening covered two bottles.
SELECT
    strftime('%Y', Consumption.consumed_date) AS year,
    COUNT(*)                                  AS openings,
    SUM(Consumption.bottles)                  AS bottles_opened,
    COUNT(Consumption.FK_tasting_id)          AS openings_with_a_note,
    COUNT(*) - COUNT(Consumption.FK_tasting_id) AS openings_without_a_note,
    SUM(CASE WHEN Consumption.FK_tasting_id IS NULL
             THEN Consumption.bottles ELSE 0 END) AS bottles_without_a_note,
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
    WineStock.appellation_name,
    WineStock.classification,
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


-- Q12. Holdings by region and classification.
--      The query the old schema could not answer. Region used to be read off
--      the producer, which put Antinori's Bolgheri wines in Chianti; it now
--      comes from the appellation, where it actually belongs.
SELECT
    Appellation.region,
    Appellation.classification,
    COUNT(DISTINCT WineStock.wine_id)      AS labels,
    COUNT(DISTINCT WineStock.FK_producer_id) AS producers,
    SUM(WineStock.bottles_purchased)       AS bottles_bought,
    SUM(WineStock.bottles_remaining)       AS bottles_on_hand,
    ROUND(SUM(WineStock.purchase_price * WineStock.bottles_remaining), 2) AS value_on_hand
FROM WineStock
JOIN Appellation ON Appellation.appellation_id = WineStock.FK_appellation_id
GROUP BY Appellation.region, Appellation.classification
ORDER BY value_on_hand DESC;
