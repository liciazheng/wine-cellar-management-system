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
    vintage_year    INTEGER,
    grape_varietal  TEXT,
    purchase_date   TEXT,
    purchase_price  REAL,
    quantity        INTEGER,
    drinking_window TEXT,
    FOREIGN KEY (FK_collector_id) REFERENCES Collector(collector_id),
    FOREIGN KEY (FK_producer_id)  REFERENCES Producer(producer_id),
    FOREIGN KEY (FK_location_id)  REFERENCES Location(location_id)
);

CREATE TABLE Tasting (
    tasting_id    INTEGER PRIMARY KEY,
    FK_wine_id    INTEGER NOT NULL,
    tasting_date  TEXT,
    rating        INTEGER CHECK(rating >= 1 AND rating <= 5),
    tasting_notes TEXT,
    food_pairing  TEXT,
    FOREIGN KEY (FK_wine_id) REFERENCES Wine(wine_id)
);
