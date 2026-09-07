# Wine Cellar Management System

[![tests](https://github.com/liciazheng/wine-cellar-management-system/actions/workflows/ci.yml/badge.svg)](https://github.com/liciazheng/wine-cellar-management-system/actions/workflows/ci.yml)

A relational database for tracking a private wine collection — what is in the cellar, where it is stored, what it cost, and how each bottle tasted over time.

SQLite, no dependencies. Clone it and open the `.db`.

> **The data in this repository is entirely made up.** It is a demo dataset written to exercise the schema, not a record of a real collection. See [About the data](#about-the-data).

## Why

Most collectors track their bottles on paper or in a spreadsheet, which stops scaling once the collection grows past a couple of shelves. Purchase details, storage conditions, and tasting notes end up in three different places, and nothing links them.

I grew up around people who collect wine and got curious about the difference between Italian and American palates, which is what got me into the data side of it. This schema puts everything in one place so a collector can answer the questions that actually come up: which bottle is closing its drinking window, which cellar is running out of room, and what the collection is worth.

## Schema

Six tables, third normal form:

| Table | Rows | Description |
|---|---|---|
| `Collector` | 4 | Collection owners, who are also the tasters |
| `Producer` | 6 | Wineries, with region and country |
| `Location` | 4 | Storage areas, with temperature, humidity, capacity |
| `Wine` | 15 | Labels — name, grape, appellation, vintage, price, bottles bought, drinking window |
| `Tasting` | 18 | Dated tasting events — taster, 1–5 rating, notes, food pairing |
| `Consumption` | 27 | Bottles leaving the cellar, optionally tied to the note they produced |

```mermaid
erDiagram
    Collector ||--o{ Wine        : owns
    Producer  ||--o{ Wine        : makes
    Location  ||--o{ Wine        : stores
    Wine      ||--o{ Tasting     : "is tasted in"
    Collector ||--o{ Tasting     : "writes note for"
    Wine      ||--o{ Consumption : "is drunk in"
    Tasting   |o--o| Consumption : "note came from"

    Collector {
        INTEGER collector_id PK
        TEXT    name
        TEXT    email
    }

    Producer {
        INTEGER producer_id   PK
        TEXT    producer_name
        TEXT    region
        TEXT    country
    }

    Location {
        INTEGER location_id PK
        TEXT    cellar_name
        REAL    temperature
        REAL    humidity
        INTEGER capacity
    }

    Wine {
        INTEGER wine_id         PK
        INTEGER FK_collector_id FK "owner"
        INTEGER FK_producer_id  FK
        INTEGER FK_location_id  FK
        TEXT    wine_name          "label on the bottle"
        TEXT    grape_varietal     "e.g. Sangiovese"
        TEXT    appellation        "e.g. Chianti Classico DOCG"
        INTEGER vintage_year
        TEXT    purchase_date
        REAL    purchase_price
        INTEGER bottles_purchased  "never decrements - see Consumption"
        INTEGER drink_from         "CHECK drink_until >= drink_from"
        INTEGER drink_until
    }

    Tasting {
        INTEGER tasting_id   PK
        INTEGER FK_wine_id   FK
        INTEGER FK_taster_id FK "who poured it"
        TEXT    tasting_date
        INTEGER rating          "CHECK between 1 and 5"
        TEXT    tasting_notes
        TEXT    food_pairing
    }

    Consumption {
        INTEGER consumption_id PK
        INTEGER FK_wine_id     FK
        INTEGER FK_tasting_id  FK "nullable and UNIQUE"
        TEXT    consumed_date
        INTEGER bottles           "CHECK bottles > 0"
        TEXT    occasion
    }
```

`Collector` reaches `Tasting` twice over: once as the owner of the bottle (through `Wine`) and once as the author of the note (directly). Q7 is the query that uses both at the same time.

`Wine` is the central table, carrying three foreign keys. `Tasting` is many-to-one against `Wine`, so a bottle can be tasted repeatedly and its evolution tracked — wine 1 has three tastings across two years, climbing from 4 to 5 as it opened up.

Three modelling decisions worth calling out:

**Name, grape and appellation are separate columns.** They vary independently, and collapsing them into one field is a common shortcut that quietly breaks querying. *Chianti Classico* is an appellation made from Sangiovese; *Solaia* is a proprietary name for a Cabernet bottled as Toscana IGT; *Nebbiolo* is a grape. With one column you cannot ask "how much Sangiovese do I own?" — with three, it's a `GROUP BY`.

**The drinking window is two integers, not a string.** `drink_from` / `drink_until` instead of `'2023-2028'`, so the project's motivating question is a `BETWEEN` rather than string parsing. A `CHECK (drink_until >= drink_from)` keeps the pair coherent, and ratings are constrained with `CHECK (rating >= 1 AND rating <= 5)`.

**`Tasting` records who tasted, not just what.** `FK_taster_id` points back to `Collector`, so a note has an author. Bottles get opened by people other than their owner, and without this the "share tasting experiences" case has nowhere to live — 6 of the 18 tastings in the sample data are on someone else's bottle.

**Stock is derived, not stored.** `bottles_purchased` never changes; what is left is that minus everything in `Consumption`. An earlier version of this schema had a single `quantity` column that stayed put while bottles were being tasted, so the number silently meant "bought" while reading like "in stock" — a cellar that never empties. Of 62 bottles bought, 27 have been drunk and 35 are on the racks.

`Consumption` carries a nullable, `UNIQUE` `FK_tasting_id`. SQLite allows many NULLs in a unique column, which is exactly the behaviour wanted: any number of bottles can be opened without a note, but no single note can be claimed by two openings. It deliberately has no collector column — whose cellar the bottle left is a fact about the `Wine`, and who drank it is a fact about the `Tasting`, so storing either here would just duplicate them.

**You cannot drink more than you bought, and the database enforces it.** That rule spans rows and tables, so a `CHECK` cannot express it:

```sql
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
```

A companion trigger covers `UPDATE`, excluding the row being edited from the running total — otherwise raising one row by a bottle would count itself twice and be refused.

Foreign keys, the drinking window and `Consumption.FK_wine_id` are indexed.

## Queries

[`sql/03_queries.sql`](sql/03_queries.sql) holds eight queries:

| | Query | Demonstrates |
|---|---|---|
| Q1 | Full collection inventory | 3-table join |
| Q2 | **What should I drink this year?** | `BETWEEN` on the window, `CASE` urgency bucket, 4-table join |
| Q3 | Wine ranking by average score | `GROUP BY` + `HAVING` |
| Q4 | Holdings by grape varietal | aggregation over the split-out varietal column |
| Q5 | Cellar utilisation | correlated subquery for remaining stock, against capacity |
| Q6 | Highly rated tastings, with author | two joins to `Collector` from one row |
| Q7 | Notes on someone else's bottle | self-referencing filter on the same two joins |
| Q8 | Collector portfolio value | `COUNT DISTINCT`, `ROUND`, derived totals |

### Q2 — what should I drink this year

Reads the current year from `strftime('%Y', 'now')`, so it stays correct without editing. Run in 2026 it returns 12 wines, with bottles counted as what is left rather than what was bought:

| Wine | Vintage | Producer | Bottles left | Drink until | Years left | Urgency |
|---|---|---|---|---|---|---|
| Chianti Classico | 2017 | Fontodi | 1 | 2027 | 1 | **drink now** |
| Chianti Classico | 2018 | Antinori | 1 | 2028 | 2 | drink soon |
| Valpolicella Superiore | 2020 | Allegrini | 3 | 2028 | 2 | drink soon |
| Chianti Classico Riserva | 2019 | Fontodi | 5 | 2029 | 3 | drink soon |
| Bolgheri Rosso | 2020 | Sassicaia | 4 | 2030 | 4 | holding well |
| … | | | | | | |
| Barolo Riserva | 2015 | Marchesi di Barolo | 1 | 2040 | 14 | holding well |

Three wines are absent, for two different reasons. A 2019 Bolgheri Superiore (2029–2039) and a 2020 Brunello (2028–2038) are not yet open. **Solaia is in its window but gone** — both bottles were drunk, the second one without a note. Before consumption tracking existed this query recommended it anyway, which is the kind of wrong answer a schema can produce while every individual value in it is correct.

### Q4 — holdings by grape

Bottles bought, since this one is about what the collection is made of:

| Grape | Labels | Bottles bought | Total spend | Appellations |
|---|---|---|---|---|
| Sangiovese | 5 | 26 | $1,748.00 | 3 |
| Nebbiolo | 5 | 15 | $1,901.00 | 3 |
| Corvina | 2 | 12 | $762.00 | 2 |
| Cabernet Sauvignon | 3 | 9 | $1,235.00 | 2 |

### Q8 — collector portfolios

| Collector | Unique wines | Bottles bought | Total investment |
|---|---|---|---|
| Michael Brown | 4 | 15 | $1,732.00 |
| Sarah Davis | 3 | 16 | $1,400.00 |
| John Smith | 4 | 14 | $1,257.00 |
| Emily Johnson | 4 | 17 | $1,257.00 |

### Q5 — cellar utilisation

Bottles on hand, since this one is about how full the racks are. Both columns are shown because the gap between them is the point:

| Cellar | Bought | On hand | Capacity | Used |
|---|---|---|---|---|
| Wine Refrigerator | 11 | 6 | 50 | 12.0% |
| Guest House Cellar | 16 | 12 | 100 | 12.0% |
| Basement Storage | 17 | 8 | 200 | 4.0% |
| Main Cellar | 18 | 9 | 500 | 1.8% |

## Layout

```
sql/
  01_schema.sql      tables, keys, constraints, triggers, indexes
  02_seed_data.sql   sample data
  03_queries.sql     the eight queries
database/
  wine_collection.db ready-to-open SQLite database, built from the scripts above
tests/
  test_database.py   35 tests over the schema, constraints, triggers and queries
```

## Running it

Open `database/wine_collection.db` in [DB Browser for SQLite](https://sqlitebrowser.org/) and run anything from `sql/03_queries.sql`.

Or build it from scratch:

```bash
sqlite3 wine_collection.db < sql/01_schema.sql
sqlite3 wine_collection.db < sql/02_seed_data.sql
sqlite3 wine_collection.db < sql/03_queries.sql
```

## Tests

```bash
pip install pytest
pytest
```

23 tests, and they check more than "does it run":

- The SQL scripts build the schema they claim, and the **committed `.db` has not drifted** from them — same columns, same types, same row counts.
- **Every constraint actually rejects bad data.** A rating of 0 or 6, a `drink_until` earlier than `drink_from`, a wine with no name, a wine owned by a nonexistent collector, a tasting by a nonexistent taster — each is asserted to raise `IntegrityError` rather than being silently stored.
- All eight queries execute and return rows.
- Q2 is checked both ways: every bottle it returns is inside its drinking window, and every bottle it excludes really is closed or not yet open.
- The design intents hold in the data — shared tastings exist, and at least one wine has three dated tastings so the evolution case is real.
- The bug this schema was fixed to avoid stays fixed: no appellation word (`DOCG`, `Riserva`, `Classico` …) has leaked back into `grape_varietal`.
- No cellar is over capacity, no drinking window starts before its vintage, and every collector email is on the reserved `example.com` domain.

## About the data

**Every row is invented.** There is no real collection behind this repository.

- The **collectors** are fictional people. Their addresses use the reserved `example.com` domain and reach nobody.
- The **bottles, purchase prices, purchase dates, quantities and drinking windows** are all fabricated. The prices are in a plausible range for the appellations named, but no bottle here was bought, and none of the windows reflects a real assessment.
- The **ratings, tasting notes and food pairings** are written to look like tasting notes. Nobody tasted these wines. They are not opinions about any real wine.
- The **producer names, grape varieties and appellations** are real — they are reference data, the same way a country list is, and they are there so the joins operate on values that behave like the real thing.

The dataset is sized to demonstrate the schema and the queries, not to be analysed: 15 wines, 18 tastings and 27 opened bottles will not support any conclusion about wine.
