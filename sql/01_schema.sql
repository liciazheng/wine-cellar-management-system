-- Wine Cellar Management System — schema
-- SQLite / DB Browser for SQLite
-- Five entities: Collector, Producer, Location, Wine, Tasting

CREATE TABLE Collector (
    collector_id INTEGER PRIMARY KEY,
    name         TEXT NOT NULL,
    email        TEXT NOT NULL
);

CREATE TABLE Producer (
    producer_id   INTEGER PRIMARY KEY,
    producer_name TEXT NOT NULL,
    region        TEXT,
    country       TEXT
);

CREATE TABLE Location (
    location_id INTEGER PRIMARY KEY,
    cellar_name TEXT NOT NULL,
    temperature REAL,
    humidity    REAL,
    capacity    INTEGER
);

CREATE TABLE Wine (
    wine_id         INTEGER PRIMARY KEY,
    FK_collector_id INTEGER NOT NULL,
    FK_producer_id  INTEGER NOT NULL,
    FK_location_id  INTEGER NOT NULL,

    -- Three separate concepts, deliberately kept apart. The label on the
    -- bottle ("Tignanello"), the grape it is made from ("Sangiovese"), and
    -- the appellation it is bottled under ("Toscana IGT") vary
    -- independently: Chianti Classico is an appellation made from Sangiovese,
    -- Solaia is a proprietary name for a Cabernet bottled as Toscana IGT.
    -- Collapsing them into one column makes it impossible to ask "how much
    -- Sangiovese do I own?" or "what is in my cellar from Piedmont?"
    wine_name       TEXT NOT NULL,
    grape_varietal  TEXT,
    appellation     TEXT,

    vintage_year    INTEGER,
    purchase_date   TEXT,
    purchase_price  REAL,
    quantity        INTEGER,

    -- Stored as two integers rather than a '2023-2028' string, so the drinking
    -- window is queryable with a plain BETWEEN instead of string parsing.
    drink_from      INTEGER,
    drink_until     INTEGER,

    FOREIGN KEY (FK_collector_id) REFERENCES Collector(collector_id),
    FOREIGN KEY (FK_producer_id)  REFERENCES Producer(producer_id),
    FOREIGN KEY (FK_location_id)  REFERENCES Location(location_id),
    CHECK (drink_until >= drink_from)
);

CREATE TABLE Tasting (
    tasting_id    INTEGER PRIMARY KEY,
    FK_wine_id    INTEGER NOT NULL,

    -- Who poured it. A bottle is often tasted by someone other than its
    -- owner, so without this the collection cannot answer "whose note is
    -- this?" — which is the whole point of sharing tasting experiences.
    FK_taster_id  INTEGER NOT NULL,

    tasting_date  TEXT,
    rating        INTEGER CHECK (rating >= 1 AND rating <= 5),
    tasting_notes TEXT,
    food_pairing  TEXT,

    FOREIGN KEY (FK_wine_id)   REFERENCES Wine(wine_id),
    FOREIGN KEY (FK_taster_id) REFERENCES Collector(collector_id)
);

-- The foreign keys carry every join in 03_queries.sql. The drinking-window
-- index supports the "what should I drink this year" lookup.
CREATE INDEX idx_wine_collector    ON Wine(FK_collector_id);
CREATE INDEX idx_wine_producer     ON Wine(FK_producer_id);
CREATE INDEX idx_wine_location     ON Wine(FK_location_id);
CREATE INDEX idx_wine_drink_window ON Wine(drink_from, drink_until);
CREATE INDEX idx_tasting_wine      ON Tasting(FK_wine_id);
CREATE INDEX idx_tasting_taster    ON Tasting(FK_taster_id);
