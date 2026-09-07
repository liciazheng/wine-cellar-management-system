-- Wine Cellar Management System — schema
-- SQLite / DB Browser for SQLite
-- Seven entities: Collector, Producer, Appellation, Location, Wine, Tasting,
-- Consumption

-- A note on dates. SQLite has no date type, so every date here is ISO-8601
-- text guarded by `x IS date(x)`. date() returns NULL for anything it cannot
-- parse — including '2025-1-1', which is missing its zero padding — and
-- NULL IS NULL is false, so the CHECK rejects it. Without this the column
-- would accept 'not-a-date' and every julianday() calculation built on it
-- would silently return NULL.
CREATE TABLE Collector (
    collector_id INTEGER PRIMARY KEY,
    name         TEXT NOT NULL,
    -- Two collectors sharing an address would make "whose note is this" and
    -- "who do I contact about this bottle" ambiguous.
    email        TEXT NOT NULL UNIQUE
);

CREATE TABLE Producer (
    producer_id   INTEGER PRIMARY KEY,
    producer_name TEXT NOT NULL,

    -- Where the winery is based, which is not the same as where any given
    -- bottle comes from. Antinori is a Tuscan house that bottles Chianti
    -- Classico in Chianti and Solaia in Bolgheri, so a wine's region has to
    -- come from its appellation and not from here.
    home_region   TEXT,
    country       TEXT
);

-- Appellations, split out of Wine. The old design stored the appellation as
-- free text on every wine, which repeated 'Chianti Classico DOCG' three times
-- and — worse — buried a transitive dependency: an appellation determines its
-- region and its classification, so those facts belonged with the appellation
-- rather than with each bottle. This is the third-normal-form fix.
CREATE TABLE Appellation (
    appellation_id   INTEGER PRIMARY KEY,
    appellation_name TEXT NOT NULL,
    classification   TEXT CHECK (classification IN ('DOCG', 'DOC', 'IGT')),
    region           TEXT NOT NULL,
    country          TEXT NOT NULL,
    UNIQUE (appellation_name, classification)
);

CREATE TABLE Location (
    location_id INTEGER PRIMARY KEY,
    cellar_name TEXT NOT NULL,
    temperature REAL,
    humidity    REAL CHECK (humidity IS NULL OR humidity BETWEEN 0 AND 100),
    -- CellarOccupancy divides by this. A zero would not raise, it would
    -- quietly hand back a NULL utilisation figure.
    capacity    INTEGER NOT NULL CHECK (capacity > 0)
);

CREATE TABLE Wine (
    wine_id           INTEGER PRIMARY KEY,
    FK_collector_id   INTEGER NOT NULL,
    FK_producer_id    INTEGER NOT NULL,
    FK_location_id    INTEGER NOT NULL,
    FK_appellation_id INTEGER,

    -- Three separate concepts, deliberately kept apart. The label on the
    -- bottle ("Tignanello"), the grape it is made from ("Sangiovese"), and
    -- the appellation it is bottled under ("Toscana IGT") vary
    -- independently: Chianti Classico is an appellation made from Sangiovese,
    -- Solaia is a proprietary name for a Cabernet bottled as Toscana IGT.
    -- Collapsing them into one column makes it impossible to ask "how much
    -- Sangiovese do I own?" or "what is in my cellar from Piedmont?"
    --
    -- Ageing designations stay in wine_name, not in the appellation. A
    -- "Chianti Classico Riserva" is a Chianti Classico DOCG that was aged
    -- longer; treating Riserva as its own appellation would have split one
    -- region's holdings across two rows that mean the same place.
    wine_name       TEXT NOT NULL,
    grape_varietal  TEXT,

    vintage_year    INTEGER,
    purchase_date   TEXT CHECK (purchase_date IS date(purchase_date)),
    purchase_price  REAL CHECK (purchase_price IS NULL OR purchase_price >= 0),

    -- How many bottles were bought, which never changes. What is left in the
    -- cellar is this minus everything recorded in Consumption. An earlier
    -- version called this `quantity` and left it static while bottles were
    -- being tasted, so the number silently meant "purchased" while reading
    -- like "in stock".
    bottles_purchased INTEGER NOT NULL CHECK (bottles_purchased > 0),

    -- Stored as two integers rather than a '2023-2028' string, so the drinking
    -- window is queryable with a plain BETWEEN instead of string parsing.
    drink_from      INTEGER,
    drink_until     INTEGER,

    FOREIGN KEY (FK_collector_id)   REFERENCES Collector(collector_id),
    FOREIGN KEY (FK_producer_id)    REFERENCES Producer(producer_id),
    FOREIGN KEY (FK_location_id)    REFERENCES Location(location_id),
    FOREIGN KEY (FK_appellation_id) REFERENCES Appellation(appellation_id),

    -- A window is either fully known or not recorded. `drink_until >=
    -- drink_from` alone was not enough: with one end NULL the comparison is
    -- NULL, which SQLite treats as a pass, so a half-open window slipped
    -- through and then silently failed every BETWEEN that used it.
    CHECK ((drink_from IS NULL) = (drink_until IS NULL)),
    CHECK (drink_until IS NULL OR drink_until >= drink_from),
    CHECK (drink_from IS NULL OR vintage_year IS NULL OR drink_from >= vintage_year)
);

CREATE TABLE Tasting (
    tasting_id    INTEGER PRIMARY KEY,
    FK_wine_id    INTEGER NOT NULL,

    -- Who poured it. A bottle is often tasted by someone other than its
    -- owner, so without this the collection cannot answer "whose note is
    -- this?" — which is the whole point of sharing tasting experiences.
    FK_taster_id  INTEGER NOT NULL,

    tasting_date  TEXT CHECK (tasting_date IS date(tasting_date)),
    rating        INTEGER CHECK (rating >= 1 AND rating <= 5),
    tasting_notes TEXT,
    food_pairing  TEXT,

    FOREIGN KEY (FK_wine_id)   REFERENCES Wine(wine_id),
    FOREIGN KEY (FK_taster_id) REFERENCES Collector(collector_id)
);

CREATE TABLE Consumption (
    consumption_id INTEGER PRIMARY KEY,
    FK_wine_id     INTEGER NOT NULL,

    -- Optional. A bottle can be opened without anyone writing a note, and a
    -- note can exist without a bottle leaving this cellar (tasting someone
    -- else's). UNIQUE over a nullable column is exactly what is wanted here:
    -- SQLite permits many NULLs, so any number of bottles can go unrecorded,
    -- but a given note cannot be claimed by two openings.
    FK_tasting_id  INTEGER UNIQUE,

    consumed_date  TEXT NOT NULL CHECK (consumed_date IS date(consumed_date)),
    bottles        INTEGER NOT NULL DEFAULT 1 CHECK (bottles > 0),
    occasion       TEXT,

    -- No collector column here on purpose. Whose cellar the bottle left is a
    -- fact about the Wine, and who drank it is a fact about the Tasting;
    -- repeating either one would denormalise this table into a copy of them.
    FOREIGN KEY (FK_wine_id)    REFERENCES Wine(wine_id),
    FOREIGN KEY (FK_tasting_id) REFERENCES Tasting(tasting_id)
);

-- ---------------------------------------------------------------------------
-- Triggers
--
-- Everything below is a rule a CHECK cannot state, because it reaches other
-- rows or other tables. A CHECK sees only the row being written.
--   * within_stock  — consumption must not exceed what was purchased
--   * matches_wine  — a note attached to an opening must be about that wine
--   * after_purchase — nothing can be tasted or drunk before it was bought
-- Each rule needs an INSERT and an UPDATE version, since a value that was
-- legal on the way in can be edited into an illegal one afterwards.
-- ---------------------------------------------------------------------------

-- You cannot drink more bottles than you bought. Without this the schema
-- would happily record a cellar holding negative stock.
CREATE TRIGGER trg_consumption_insert_within_stock
BEFORE INSERT ON Consumption
BEGIN
    SELECT RAISE(ABORT, 'consumption would exceed bottles purchased')
    WHERE NEW.bottles + (
              SELECT COALESCE(SUM(bottles), 0) FROM Consumption
              WHERE FK_wine_id = NEW.FK_wine_id
          ) > (
              SELECT bottles_purchased FROM Wine WHERE wine_id = NEW.FK_wine_id
          );
END;

-- The same rule for edits. The row being changed is excluded from the running
-- total, or correcting a single row upward would count itself twice.
CREATE TRIGGER trg_consumption_update_within_stock
BEFORE UPDATE ON Consumption
BEGIN
    SELECT RAISE(ABORT, 'consumption would exceed bottles purchased')
    WHERE NEW.bottles + (
              SELECT COALESCE(SUM(bottles), 0) FROM Consumption
              WHERE FK_wine_id = NEW.FK_wine_id
                AND consumption_id <> OLD.consumption_id
          ) > (
              SELECT bottles_purchased FROM Wine WHERE wine_id = NEW.FK_wine_id
          );
END;

-- Both foreign keys on Consumption are valid on their own while still
-- disagreeing with each other: an opening of wine 15 could carry the note
-- written about wine 1. Referential integrity does not catch that, because
-- each key points at a row that exists.
CREATE TRIGGER trg_consumption_insert_matches_wine
BEFORE INSERT ON Consumption
WHEN NEW.FK_tasting_id IS NOT NULL
BEGIN
    SELECT RAISE(ABORT, 'tasting note is about a different wine')
    WHERE (SELECT FK_wine_id FROM Tasting WHERE tasting_id = NEW.FK_tasting_id)
          <> NEW.FK_wine_id;
END;

CREATE TRIGGER trg_consumption_update_matches_wine
BEFORE UPDATE ON Consumption
WHEN NEW.FK_tasting_id IS NOT NULL
BEGIN
    SELECT RAISE(ABORT, 'tasting note is about a different wine')
    WHERE (SELECT FK_wine_id FROM Tasting WHERE tasting_id = NEW.FK_tasting_id)
          <> NEW.FK_wine_id;
END;

-- A bottle cannot leave the cellar before it arrived.
CREATE TRIGGER trg_consumption_insert_after_purchase
BEFORE INSERT ON Consumption
BEGIN
    SELECT RAISE(ABORT, 'bottle drunk before it was purchased')
    WHERE NEW.consumed_date
          < (SELECT purchase_date FROM Wine WHERE wine_id = NEW.FK_wine_id);
END;

CREATE TRIGGER trg_consumption_update_after_purchase
BEFORE UPDATE ON Consumption
BEGIN
    SELECT RAISE(ABORT, 'bottle drunk before it was purchased')
    WHERE NEW.consumed_date
          < (SELECT purchase_date FROM Wine WHERE wine_id = NEW.FK_wine_id);
END;

-- And it cannot be tasted before it arrived either.
CREATE TRIGGER trg_tasting_insert_after_purchase
BEFORE INSERT ON Tasting
BEGIN
    SELECT RAISE(ABORT, 'wine tasted before it was purchased')
    WHERE NEW.tasting_date
          < (SELECT purchase_date FROM Wine WHERE wine_id = NEW.FK_wine_id);
END;

CREATE TRIGGER trg_tasting_update_after_purchase
BEFORE UPDATE ON Tasting
BEGIN
    SELECT RAISE(ABORT, 'wine tasted before it was purchased')
    WHERE NEW.tasting_date
          < (SELECT purchase_date FROM Wine WHERE wine_id = NEW.FK_wine_id);
END;

-- The foreign keys carry every join in 03_queries.sql. The drinking-window
-- index supports the "what should I drink this year" lookup, and the
-- Consumption index supports the remaining-stock subtraction.
CREATE INDEX idx_wine_collector    ON Wine(FK_collector_id);
CREATE INDEX idx_wine_producer     ON Wine(FK_producer_id);
CREATE INDEX idx_wine_location     ON Wine(FK_location_id);
CREATE INDEX idx_wine_appellation  ON Wine(FK_appellation_id);
CREATE INDEX idx_wine_drink_window ON Wine(drink_from, drink_until);
CREATE INDEX idx_tasting_wine      ON Tasting(FK_wine_id);
CREATE INDEX idx_tasting_taster    ON Tasting(FK_taster_id);
CREATE INDEX idx_consumption_wine  ON Consumption(FK_wine_id);


-- ---------------------------------------------------------------------------
-- Views
--
-- Remaining stock is needed by almost every question worth asking, and
-- spelling it out inline meant repeating a correlated subquery in each query
-- that touched it. Once as a view is both clearer and cheaper: the aggregate
-- over Consumption runs once per wine instead of once per row of the outer
-- query.
-- ---------------------------------------------------------------------------

CREATE VIEW WineStock AS
SELECT
    Wine.wine_id,
    Wine.wine_name,
    Wine.grape_varietal,
    Wine.vintage_year,
    Wine.FK_collector_id,
    Wine.FK_producer_id,
    Wine.FK_location_id,
    Wine.FK_appellation_id,
    -- Denormalised into the view, not into the table: readable appellation and
    -- region without every query having to repeat the join.
    Appellation.appellation_name,
    Appellation.classification,
    Appellation.region,
    Wine.purchase_date,
    Wine.purchase_price,
    Wine.drink_from,
    Wine.drink_until,
    Wine.bottles_purchased,
    COALESCE(drunk.bottles, 0)                        AS bottles_drunk,
    Wine.bottles_purchased - COALESCE(drunk.bottles, 0) AS bottles_remaining,
    CASE WHEN Wine.bottles_purchased = COALESCE(drunk.bottles, 0)
         THEN 1 ELSE 0 END                            AS is_finished
FROM Wine
LEFT JOIN Appellation ON Appellation.appellation_id = Wine.FK_appellation_id
LEFT JOIN (
    SELECT FK_wine_id, SUM(bottles) AS bottles
    FROM Consumption
    GROUP BY FK_wine_id
) AS drunk ON drunk.FK_wine_id = Wine.wine_id;

-- What is physically on the racks, which is what capacity should be measured
-- against. A cellar holding wines that have all been drunk is empty.
CREATE VIEW CellarOccupancy AS
SELECT
    Location.location_id,
    Location.cellar_name,
    Location.temperature,
    Location.humidity,
    Location.capacity,
    COUNT(WineStock.wine_id)                     AS labels_stored,
    -- COALESCE, or the LEFT JOIN is pointless: it is there so a cellar with
    -- nothing in it still appears, and then SUM() over no rows returns NULL
    -- and undoes that. An empty cellar is 0% full, not unknown.
    COALESCE(SUM(WineStock.bottles_purchased), 0) AS bottles_bought,
    COALESCE(SUM(WineStock.bottles_remaining), 0) AS bottles_on_hand,
    ROUND(COALESCE(SUM(WineStock.bottles_remaining), 0) * 100.0
          / Location.capacity, 1)                AS capacity_used_percent
FROM Location
LEFT JOIN WineStock ON Location.location_id = WineStock.FK_location_id
GROUP BY Location.location_id;
