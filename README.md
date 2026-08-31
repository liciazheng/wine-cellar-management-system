# Wine Cellar Management System

A relational database for tracking a private wine collection — what is in the cellar, where it is stored, what it cost, and how each bottle tasted over time.

SQLite, no dependencies. Clone it and open the `.db`.

## Why

Most collectors track their bottles on paper or in a spreadsheet, which stops scaling once the collection grows past a couple of shelves. Purchase details, storage conditions, and tasting notes end up in three different places, and nothing links them.

I grew up around people who collect wine and got curious about the difference between Italian and American palates, which is what got me into the data side of it. This schema puts everything in one place so a collector can answer practical questions: which bottle is entering its drinking window, which cellar is running out of room, and what the collection is actually worth.

## Schema

Five tables, third normal form:

| Table | Rows | Description |
|---|---|---|
| `Collector` | 4 | Collection owners |
| `Producer` | 6 | Wineries, with region and country |
| `Location` | 4 | Storage areas, with temperature, humidity, capacity |
| `Wine` | 15 | Bottles — vintage, varietal, purchase price, quantity, drinking window |
| `Tasting` | 18 | Dated tasting events — 1–5 rating, notes, food pairing |

```
Collector ──┐
Producer  ──┼──< Wine ──< Tasting
Location  ──┘
```

`Wine` is the central table, carrying three foreign keys (`FK_collector_id`, `FK_producer_id`, `FK_location_id`). `Tasting` is many-to-one against `Wine`, so a bottle can be tasted repeatedly and its evolution tracked — wine 1 has three tastings across two years, climbing from 4 to 5 as it opened up. Ratings are constrained with `CHECK(rating >= 1 AND rating <= 5)`.

## Queries

[`sql/03_queries.sql`](sql/03_queries.sql) holds five multi-table queries, one per use case:

1. **Collection inventory** — every bottle joined to its producer and owner.
2. **Wine ranking** — average rating per wine, `GROUP BY` + `HAVING`.
3. **Cellar utilisation** — bottles stored against capacity, as a percentage.
4. **Highly rated tastings** — every tasting scoring 4 or above, with notes and pairings.
5. **Collector portfolio value** — unique wines, total bottles, and total spend per collector.

Sample output:

| Collector | Unique wines | Bottles | Total investment |
|---|---|---|---|
| Michael Brown | 4 | 15 | $1,732.00 |
| Sarah Davis | 3 | 16 | $1,400.00 |
| John Smith | 4 | 14 | $1,257.00 |
| Emily Johnson | 4 | 17 | $1,257.00 |

| Cellar | Bottles | Capacity | Used |
|---|---|---|---|
| Wine Refrigerator | 11 | 50 | 22.0% |
| Guest House Cellar | 16 | 100 | 16.0% |
| Basement Storage | 17 | 200 | 8.5% |
| Main Cellar | 18 | 500 | 3.6% |

## Layout

```
sql/
  01_schema.sql      table definitions, keys, constraints
  02_seed_data.sql   sample data (4 collectors, 6 producers, 15 wines, 18 tastings)
  03_queries.sql     the five analytical queries
database/
  wine_collection.db ready-to-open SQLite database
```

## Running it

Open `database/wine_collection.db` in [DB Browser for SQLite](https://sqlitebrowser.org/) and run anything from `sql/03_queries.sql`.

Or build it from scratch:

```bash
sqlite3 wine_collection.db < sql/01_schema.sql
sqlite3 wine_collection.db < sql/02_seed_data.sql
sqlite3 wine_collection.db < sql/03_queries.sql
```

## About the data

The collection is realistic sample data — real Italian producers (Antinori, Gaja, Sassicaia, Fontodi, Marchesi di Barolo, Allegrini) with plausible vintages, prices, and drinking windows. The collectors and their email addresses are fictional.
