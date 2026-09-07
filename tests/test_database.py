"""
Tests for the wine cellar database.

Two things are checked here: that the SQL scripts build a database matching
the one committed to database/, and that the constraints in the schema
actually reject bad data rather than merely documenting an intention.

    pip install pytest
    pytest
"""

import sqlite3
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SQL = ROOT / "sql"
SHIPPED_DB = ROOT / "database" / "wine_collection.db"

EXPECTED_ROWS = {
    "Collector": 4,
    "Producer": 6,
    "Appellation": 9,
    "Location": 4,
    "Wine": 15,
    "Tasting": 18,
    "Consumption": 27,
}

REMAINING = """
    Wine.bottles_purchased - COALESCE((
        SELECT SUM(bottles) FROM Consumption WHERE FK_wine_id = Wine.wine_id
    ), 0)
"""


def split_statements(sql):
    """Split a script into complete statements using SQLite's own parser."""
    statements, buffer = [], ""
    for line in sql.splitlines(keepends=True):
        buffer += line
        if sqlite3.complete_statement(buffer):
            statements.append(buffer)
            buffer = ""
    return statements


@pytest.fixture
def db():
    """A fresh in-memory database built from the SQL scripts."""
    conn = sqlite3.connect(":memory:")
    conn.execute("PRAGMA foreign_keys = ON")
    for name in ("01_schema.sql", "02_seed_data.sql"):
        conn.executescript((SQL / name).read_text(encoding="utf-8"))
    # executescript commits and resets pragmas, so re-arm foreign keys.
    conn.execute("PRAGMA foreign_keys = ON")
    yield conn
    conn.close()


@pytest.fixture
def shipped():
    conn = sqlite3.connect(f"file:{SHIPPED_DB}?mode=ro", uri=True)
    yield conn
    conn.close()


# --- the scripts build what they claim -----------------------------------

def test_scripts_create_expected_tables(db):
    tables = {r[0] for r in db.execute(
        "SELECT name FROM sqlite_master WHERE type='table'")}
    assert tables == set(EXPECTED_ROWS)


@pytest.mark.parametrize("table,count", EXPECTED_ROWS.items())
def test_row_counts(db, table, count):
    assert db.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0] == count


def test_no_foreign_key_violations(db):
    assert db.execute("PRAGMA foreign_key_check").fetchall() == []


def test_indexes_exist(db):
    indexes = {r[0] for r in db.execute(
        "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'")}
    assert "idx_wine_drink_window" in indexes
    assert "idx_tasting_taster" in indexes


def test_shipped_db_matches_the_scripts(db, shipped):
    """The committed .db should not drift from the SQL that generates it."""
    for table, count in EXPECTED_ROWS.items():
        assert shipped.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0] == count

    def columns(conn, table):
        return [(r[1], r[2]) for r in conn.execute(f"PRAGMA table_info({table})")]

    for table in EXPECTED_ROWS:
        assert columns(shipped, table) == columns(db, table), f"{table} schema drifted"


# --- constraints actually bite -------------------------------------------

def test_rating_above_five_is_rejected(db):
    with pytest.raises(sqlite3.IntegrityError):
        db.execute("INSERT INTO Tasting VALUES (99, 1, 1, '2024-01-01', 6, 'x', 'y')")


def test_rating_below_one_is_rejected(db):
    with pytest.raises(sqlite3.IntegrityError):
        db.execute("INSERT INTO Tasting VALUES (99, 1, 1, '2024-01-01', 0, 'x', 'y')")


def insert_wine(db, **overrides):
    """
    Insert a wine by column name, not by position.

    These tests used positional VALUES until FK_appellation_id was added in the
    middle of Wine, at which point a NULL aimed at wine_name silently landed on
    a nullable column instead and the test stopped testing anything.
    """
    row = {
        "wine_id": 99, "FK_collector_id": 1, "FK_producer_id": 1,
        "FK_location_id": 1, "FK_appellation_id": 1, "wine_name": "Test Wine",
        "grape_varietal": "Sangiovese", "vintage_year": 2020,
        "purchase_date": "2021-01-01", "purchase_price": 50.0,
        "bottles_purchased": 1, "drink_from": 2025, "drink_until": 2030,
    }
    row.update(overrides)
    columns = ", ".join(row)
    placeholders = ", ".join("?" * len(row))
    return db.execute(
        f"INSERT INTO Wine ({columns}) VALUES ({placeholders})", list(row.values()))


def test_backwards_drinking_window_is_rejected(db):
    """drink_until before drink_from is incoherent and must not be storable."""
    with pytest.raises(sqlite3.IntegrityError):
        insert_wine(db, drink_from=2030, drink_until=2025)


def test_wine_requires_a_name(db):
    with pytest.raises(sqlite3.IntegrityError):
        insert_wine(db, wine_name=None)


def test_wine_requires_a_bottle_count(db):
    with pytest.raises(sqlite3.IntegrityError):
        insert_wine(db, bottles_purchased=None)


def test_buying_zero_bottles_is_not_a_purchase(db):
    with pytest.raises(sqlite3.IntegrityError):
        insert_wine(db, bottles_purchased=0)


def test_wine_cannot_reference_a_missing_collector(db):
    with pytest.raises(sqlite3.IntegrityError):
        insert_wine(db, FK_collector_id=999)


def test_the_baseline_wine_is_actually_insertable(db):
    """
    Guard on the helper itself: if the defaults were invalid, every test above
    would pass for the wrong reason.
    """
    insert_wine(db)
    assert db.execute(
        "SELECT wine_name FROM Wine WHERE wine_id = 99").fetchone()[0] == "Test Wine"


def test_tasting_cannot_reference_a_missing_taster(db):
    with pytest.raises(sqlite3.IntegrityError):
        db.execute("INSERT INTO Tasting VALUES (99, 1, 999, '2024-01-01', 4, 'x', 'y')")


# --- the queries run and mean what they say ------------------------------

def test_every_query_executes(db):
    sql = (SQL / "03_queries.sql").read_text(encoding="utf-8")
    queries = [s for s in split_statements(sql) if "SELECT" in s.upper()]
    assert len(queries) == 12
    for i, query in enumerate(queries, 1):
        rows = db.execute(query).fetchall()
        assert rows, f"Q{i} returned no rows"


# --- the views ------------------------------------------------------------

def test_views_exist(db):
    views = {r[0] for r in db.execute(
        "SELECT name FROM sqlite_master WHERE type='view'")}
    assert views == {"WineStock", "CellarOccupancy"}


def test_winestock_remaining_matches_the_raw_subtraction(db):
    """
    The view exists to stop that subtraction being retyped in every query, so
    it had better agree with the long way round for every wine.
    """
    from_view = dict(db.execute(
        "SELECT wine_id, bottles_remaining FROM WineStock"))
    the_long_way = dict(db.execute(f"SELECT wine_id, {REMAINING} FROM Wine"))
    assert from_view == the_long_way


def test_winestock_covers_every_wine_including_untouched_ones(db):
    """A LEFT JOIN, not a JOIN: a wine nobody has opened still has stock."""
    assert db.execute("SELECT COUNT(*) FROM WineStock").fetchone()[0] == \
           db.execute("SELECT COUNT(*) FROM Wine").fetchone()[0]
    untouched = db.execute(
        "SELECT COUNT(*) FROM WineStock WHERE bottles_drunk = 0").fetchone()[0]
    assert untouched > 0


def test_is_finished_flags_exactly_the_empty_wines(db):
    flagged = {r[0] for r in db.execute(
        "SELECT wine_id FROM WineStock WHERE is_finished = 1")}
    empty = {r[0] for r in db.execute(
        "SELECT wine_id FROM WineStock WHERE bottles_remaining = 0")}
    assert flagged == empty
    assert flagged, "the sample data should contain at least one finished wine"


def test_cellar_occupancy_agrees_with_winestock(db):
    per_cellar = dict(db.execute(
        "SELECT location_id, bottles_on_hand FROM CellarOccupancy"))
    rolled_up = dict(db.execute("""
        SELECT FK_location_id, SUM(bottles_remaining)
        FROM WineStock GROUP BY FK_location_id
    """))
    assert per_cellar == rolled_up


def test_cellar_occupancy_never_exceeds_capacity(db):
    over = db.execute("""
        SELECT cellar_name FROM CellarOccupancy
        WHERE bottles_on_hand > capacity
    """).fetchall()
    assert over == []


def test_q9_verdict_agrees_with_its_own_projection(db):
    """
    Q9's verdict is the one piece of judgement in the query file. It is derived
    from runs_out_around and drink_until, both of which the query also reports,
    so the three columns must not be able to contradict each other.
    """
    sql = (SQL / "03_queries.sql").read_text(encoding="utf-8")
    q9 = [s for s in split_statements(sql) if "runs_out_around" in s][0]

    cursor = db.execute(q9)
    columns = [d[0] for d in cursor.description]
    rows = [dict(zip(columns, r)) for r in cursor.fetchall()]

    judged = [r for r in rows if r["verdict"] is not None]
    assert judged, "no wine got a verdict, so nothing was checked"
    assert any(r["verdict"] == "drinking too slowly" for r in judged)
    assert any(r["verdict"] == "on track" for r in judged)

    for row in judged:
        runs_out = int(row["runs_out_around"])
        expected = "drinking too slowly" if runs_out > row["drink_until"] else "on track"
        assert row["verdict"] == expected, row["wine_name"]

    # Finished and untouched wines carry no verdict, because there is no rate
    # to project from.
    for row in (r for r in rows if r["verdict"] is None):
        assert row["runs_out_around"] in ("finished", "untouched")


def test_drink_now_query_only_returns_open_windows(db):
    """Q2's whole point: every row it returns is drinkable in the current year."""
    year = int(db.execute("SELECT strftime('%Y', 'now')").fetchone()[0])
    rows = db.execute("""
        SELECT wine_name, drink_from, drink_until FROM Wine
        WHERE CAST(strftime('%Y', 'now') AS INTEGER)
              BETWEEN drink_from AND drink_until
    """).fetchall()
    assert rows
    for name, start, end in rows:
        assert start <= year <= end, f"{name} is outside its window"

    # And the bottles it excludes really are closed or not yet open.
    excluded = db.execute("""
        SELECT wine_name, drink_from, drink_until FROM Wine
        WHERE CAST(strftime('%Y', 'now') AS INTEGER)
              NOT BETWEEN drink_from AND drink_until
    """).fetchall()
    for name, start, end in excluded:
        assert not (start <= year <= end), f"{name} should have been included"


def test_shared_tastings_exist_in_the_sample_data(db):
    """The taster FK is pointless if nobody ever tastes someone else's bottle."""
    count = db.execute("""
        SELECT COUNT(*) FROM Tasting
        JOIN Wine ON Tasting.FK_wine_id = Wine.wine_id
        WHERE Tasting.FK_taster_id <> Wine.FK_collector_id
    """).fetchone()[0]
    assert count > 0


def test_a_wine_can_have_several_tastings_over_time(db):
    """The many-to-one Tasting design exists to track how a bottle evolves."""
    wine_id, n = db.execute("""
        SELECT FK_wine_id, COUNT(*) FROM Tasting
        GROUP BY FK_wine_id ORDER BY COUNT(*) DESC LIMIT 1
    """).fetchone()
    assert n >= 3
    dates = [r[0] for r in db.execute(
        "SELECT tasting_date FROM Tasting WHERE FK_wine_id = ? ORDER BY tasting_date",
        (wine_id,))]
    assert dates == sorted(dates)
    assert len(set(dates)) == len(dates)


# --- data sanity ----------------------------------------------------------

# --- appellations -----------------------------------------------------------

def test_an_appellation_has_exactly_one_region(db):
    """
    The transitive dependency the Appellation table exists to remove. When the
    appellation was free text on Wine, nothing stopped two bottles of Chianti
    Classico claiming different regions.
    """
    split = db.execute("""
        SELECT appellation_name, COUNT(DISTINCT region)
        FROM Appellation GROUP BY appellation_name
        HAVING COUNT(DISTINCT region) > 1
    """).fetchall()
    assert split == []


def test_every_wine_region_comes_from_its_appellation(db):
    """
    Not from its producer. Producer.home_region is where the winery is, which
    is a different fact and is allowed to differ.
    """
    columns = {r[1] for r in db.execute("PRAGMA table_info(Producer)")}
    assert "region" not in columns, "Producer.region invited being read as the wine's region"
    assert "home_region" in columns

    unsourced = db.execute("""
        SELECT wine_name FROM WineStock
        WHERE FK_appellation_id IS NOT NULL AND region IS NULL
    """).fetchall()
    assert unsourced == []


def test_classification_is_a_known_designation(db):
    with pytest.raises(sqlite3.IntegrityError):
        db.execute("""INSERT INTO Appellation
                      VALUES (99, 'Somewhere', 'GRAND CRU', 'Tuscany', 'Italy')""")


def test_appellations_are_not_duplicated(db):
    with pytest.raises(sqlite3.IntegrityError):
        db.execute("""INSERT INTO Appellation
                      VALUES (99, 'Chianti Classico', 'DOCG', 'Tuscany', 'Italy')""")


def test_wine_cannot_reference_a_missing_appellation(db):
    with pytest.raises(sqlite3.IntegrityError):
        insert_wine(db, FK_appellation_id=999)


def test_no_wine_is_masquerading_as_a_producer(db):
    """
    Sassicaia sat in the Producer table until this was fixed. It is a wine; the
    estate is Tenuta San Guido. A producer name that matches a wine name is the
    signal that the two got conflated again.
    """
    producers = {r[0] for r in db.execute("SELECT producer_name FROM Producer")}
    wines = {r[0] for r in db.execute("SELECT wine_name FROM Wine")}
    assert producers & wines == set()
    assert "Sassicaia" not in producers


def test_classification_is_not_glued_onto_the_appellation_name(db):
    """The designation is its own column, so it must not also be in the name."""
    names = [r[0] for r in db.execute("SELECT appellation_name FROM Appellation")]
    for name in names:
        assert not any(name.endswith(f" {c}") for c in ("DOCG", "DOC", "IGT")), name


def test_ageing_designations_stay_out_of_the_appellation(db):
    """
    A Chianti Classico Riserva is a Chianti Classico DOCG aged longer. Treating
    Riserva as its own appellation would split one region's holdings in two.
    """
    names = [r[0] for r in db.execute("SELECT appellation_name FROM Appellation")]
    for name in names:
        assert "Riserva" not in name, name

    riserva = db.execute("""
        SELECT appellation_name FROM WineStock WHERE wine_name LIKE '%Riserva%'
    """).fetchall()
    assert riserva, "no Riserva in the sample data, so nothing was checked"
    for (appellation,) in riserva:
        assert "Riserva" not in appellation


def test_grape_varietal_is_not_holding_appellations(db):
    """
    The bug this schema was fixed to avoid: appellation names leaking back
    into the varietal column.
    """
    varietals = {r[0] for r in db.execute("SELECT DISTINCT grape_varietal FROM Wine")}
    appellation_words = {"DOCG", "DOC", "IGT", "Riserva", "Classico", "Superiore"}
    for varietal in varietals:
        assert not appellation_words & set(varietal.split()), \
            f"'{varietal}' looks like an appellation, not a grape"


def test_drinking_window_starts_after_the_vintage(db):
    bad = db.execute(
        "SELECT wine_name FROM Wine WHERE drink_from < vintage_year").fetchall()
    assert bad == []


def test_no_cellar_is_over_capacity(db):
    over = db.execute(f"""
        SELECT Location.cellar_name, SUM({REMAINING}), Location.capacity
        FROM Location JOIN Wine ON Location.location_id = Wine.FK_location_id
        GROUP BY Location.location_id
        HAVING SUM({REMAINING}) > Location.capacity
    """).fetchall()
    assert over == []


# --- consumption and remaining stock -------------------------------------

def test_no_wine_is_over_consumed(db):
    """The invariant the triggers exist to protect, checked against the seed."""
    negative = db.execute(f"""
        SELECT wine_name, {REMAINING} AS remaining FROM Wine
        WHERE {REMAINING} < 0
    """).fetchall()
    assert negative == []


def test_consuming_more_than_purchased_is_rejected(db):
    """
    Cross-table and cross-row, so a CHECK cannot express it. Wine 15 has three
    bottles and none drunk; a fourth has to be refused.
    """
    with pytest.raises(sqlite3.IntegrityError, match="exceed bottles purchased"):
        db.execute("""INSERT INTO Consumption
                      (consumption_id, FK_wine_id, FK_tasting_id, consumed_date, bottles)
                      VALUES (99, 15, NULL, '2025-09-01', 4)""")


def test_consuming_exactly_the_stock_is_allowed(db):
    """The trigger must draw the line at over-drawing, not at finishing a wine."""
    db.execute("""INSERT INTO Consumption
                  (consumption_id, FK_wine_id, FK_tasting_id, consumed_date, bottles)
                  VALUES (99, 15, NULL, '2025-09-01', 3)""")
    remaining = db.execute(
        f"SELECT {REMAINING} FROM Wine WHERE wine_id = 15").fetchone()[0]
    assert remaining == 0


def test_one_more_bottle_of_a_finished_wine_is_rejected(db):
    """Wine 14 is already drunk down to zero in the seed data."""
    with pytest.raises(sqlite3.IntegrityError, match="exceed bottles purchased"):
        db.execute("""INSERT INTO Consumption
                      (consumption_id, FK_wine_id, FK_tasting_id, consumed_date, bottles)
                      VALUES (99, 14, NULL, '2025-09-01', 1)""")


def test_updating_a_consumption_beyond_stock_is_rejected(db):
    """The UPDATE trigger, which the INSERT trigger alone would not cover."""
    with pytest.raises(sqlite3.IntegrityError, match="exceed bottles purchased"):
        db.execute("UPDATE Consumption SET bottles = 99 WHERE consumption_id = 1")


def test_updating_a_consumption_within_stock_is_allowed(db):
    """
    Regression guard on the UPDATE trigger: it must exclude the row being
    edited from the running total, or raising a row by one would double-count
    itself and be refused.
    """
    db.execute("UPDATE Consumption SET bottles = 2 WHERE consumption_id = 1")
    remaining = db.execute(
        f"SELECT {REMAINING} FROM Wine WHERE wine_id = 1").fetchone()[0]
    assert remaining == 0


def test_zero_bottles_is_not_a_consumption(db):
    with pytest.raises(sqlite3.IntegrityError):
        db.execute("""INSERT INTO Consumption
                      (consumption_id, FK_wine_id, FK_tasting_id, consumed_date, bottles)
                      VALUES (99, 15, NULL, '2025-09-01', 0)""")


def test_a_tasting_cannot_be_claimed_by_two_openings(db):
    with pytest.raises(sqlite3.IntegrityError):
        db.execute("""INSERT INTO Consumption
                      (consumption_id, FK_wine_id, FK_tasting_id, consumed_date, bottles)
                      VALUES (99, 15, 1, '2025-09-01', 1)""")


def test_bottles_can_be_drunk_without_a_tasting_note(db):
    """
    The nullable side of that UNIQUE. Several bottles were opened with no note,
    and the schema has to allow more than one of them.
    """
    unnoted = db.execute(
        "SELECT COUNT(*) FROM Consumption WHERE FK_tasting_id IS NULL").fetchone()[0]
    assert unnoted > 1


def test_every_tasting_opened_a_bottle(db):
    """
    Sample-data sanity rather than a schema rule: a note in this dataset always
    came from a bottle in this cellar, so none should be missing its opening.
    """
    orphans = db.execute("""
        SELECT Tasting.tasting_id FROM Tasting
        LEFT JOIN Consumption ON Consumption.FK_tasting_id = Tasting.tasting_id
        WHERE Consumption.consumption_id IS NULL
    """).fetchall()
    assert orphans == []


def test_at_least_one_wine_is_finished_and_one_untouched(db):
    """Both ends of the range need to be present or the queries go untested."""
    remaining = [r[0] for r in db.execute(f"SELECT {REMAINING} FROM Wine")]
    assert 0 in remaining
    assert any(
        r == p for r, p in db.execute(
            f"SELECT {REMAINING}, bottles_purchased FROM Wine")
    )


def test_collector_emails_use_the_reserved_example_domain(db):
    """The data is invented; the addresses must not reach anyone real."""
    emails = [r[0] for r in db.execute("SELECT email FROM Collector")]
    assert all(e.endswith("@example.com") for e in emails)
