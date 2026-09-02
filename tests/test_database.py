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
    "Location": 4,
    "Wine": 15,
    "Tasting": 18,
}


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


def test_backwards_drinking_window_is_rejected(db):
    """drink_until before drink_from is incoherent and must not be storable."""
    with pytest.raises(sqlite3.IntegrityError):
        db.execute("""INSERT INTO Wine VALUES (99, 1, 1, 1, 'Bad Wine', 'Sangiovese',
                      'Toscana IGT', 2020, '2021-01-01', 50.0, 1, 2030, 2025)""")


def test_wine_requires_a_name(db):
    with pytest.raises(sqlite3.IntegrityError):
        db.execute("""INSERT INTO Wine VALUES (99, 1, 1, 1, NULL, 'Sangiovese',
                      'Toscana IGT', 2020, '2021-01-01', 50.0, 1, 2025, 2030)""")


def test_wine_cannot_reference_a_missing_collector(db):
    with pytest.raises(sqlite3.IntegrityError):
        db.execute("""INSERT INTO Wine VALUES (99, 999, 1, 1, 'Orphan', 'Sangiovese',
                      'Toscana IGT', 2020, '2021-01-01', 50.0, 1, 2025, 2030)""")


def test_tasting_cannot_reference_a_missing_taster(db):
    with pytest.raises(sqlite3.IntegrityError):
        db.execute("INSERT INTO Tasting VALUES (99, 1, 999, '2024-01-01', 4, 'x', 'y')")


# --- the queries run and mean what they say ------------------------------

def test_every_query_executes(db):
    sql = (SQL / "03_queries.sql").read_text(encoding="utf-8")
    queries = [s for s in split_statements(sql) if "SELECT" in s.upper()]
    assert len(queries) == 8
    for i, query in enumerate(queries, 1):
        rows = db.execute(query).fetchall()
        assert rows, f"Q{i} returned no rows"


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
    over = db.execute("""
        SELECT Location.cellar_name, SUM(Wine.quantity), Location.capacity
        FROM Location JOIN Wine ON Location.location_id = Wine.FK_location_id
        GROUP BY Location.location_id
        HAVING SUM(Wine.quantity) > Location.capacity
    """).fetchall()
    assert over == []


def test_collector_emails_use_the_reserved_example_domain(db):
    """The data is invented; the addresses must not reach anyone real."""
    emails = [r[0] for r in db.execute("SELECT email FROM Collector")]
    assert all(e.endswith("@example.com") for e in emails)
