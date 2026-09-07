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


@pytest.mark.parametrize("kind", ["view", "trigger", "index"])
def test_shipped_db_has_every_schema_object(db, shipped, kind):
    """
    Row counts and columns matched while the shipped .db could still have been
    built before the views and triggers existed — which is exactly the drift a
    ready-to-open database invites, since it is a binary nobody re-reads.
    """
    def names(conn):
        return {r[0] for r in conn.execute(
            "SELECT name FROM sqlite_master WHERE type = ?", (kind,))}

    from_scripts = names(db)
    assert from_scripts, f"no {kind}s in the schema, so nothing was compared"
    assert names(shipped) == from_scripts


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
        assert row["runs_out_around"] in (
            "finished", "untouched", "owned under a year", "no purchase date")


def run_q9(db):
    sql = (SQL / "03_queries.sql").read_text(encoding="utf-8")
    q9 = [s for s in split_statements(sql) if "runs_out_around" in s][0]
    cursor = db.execute(q9)
    columns = [d[0] for d in cursor.description]
    return {r[columns.index("wine_name")]: dict(zip(columns, r))
            for r in cursor.fetchall()}


def test_q9_refuses_to_annualise_a_few_weeks_of_ownership(db):
    """
    A wine bought today with one bottle already gone used to extrapolate to
    hundreds of bottles a year — not an error or a NULL, but a plausible number
    that was wrong, which then poisoned the run-out projection.
    """
    today = db.execute("SELECT date('now')").fetchone()[0]
    insert_wine(db, wine_id=90, wine_name="Bought Today",
                purchase_date=today, bottles_purchased=2)
    db.execute("""INSERT INTO Consumption
                  (consumption_id, FK_wine_id, FK_tasting_id, consumed_date, bottles)
                  VALUES (90, 90, NULL, ?, 1)""", (today,))

    row = run_q9(db)["Bought Today"]

    assert row["bottles_per_year"] is None
    assert row["runs_out_around"] == "owned under a year"
    assert row["verdict"] is None


def test_q9_says_so_when_there_is_no_purchase_date(db):
    """purchase_date is nullable, and every derived column used to go NULL
    without the query ever explaining which input was missing."""
    insert_wine(db, wine_id=91, wine_name="No Date",
                purchase_date=None, bottles_purchased=2)
    db.execute("""INSERT INTO Consumption
                  (consumption_id, FK_wine_id, FK_tasting_id, consumed_date, bottles)
                  VALUES (91, 91, NULL, '2025-01-01', 1)""")

    row = run_q9(db)["No Date"]

    assert row["years_owned"] is None
    assert row["bottles_per_year"] is None
    assert row["runs_out_around"] == "no purchase date"
    assert row["verdict"] is None


def test_q9_still_rates_wines_held_long_enough(db):
    """The guard must not have silenced the query for ordinary wines."""
    rated = [r for r in run_q9(db).values() if r["bottles_per_year"] is not None]
    assert len(rated) >= 10


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

# --- rules that reach across rows and tables -------------------------------

def add_note(db, tasting_id=90, wine_id=1, date="2025-09-01"):
    db.execute("INSERT INTO Tasting VALUES (?, ?, 1, ?, 4, 'note', 'x')",
               (tasting_id, wine_id, date))


def add_opening(db, consumption_id=90, wine_id=15, tasting_id=None,
                date="2025-09-02", bottles=1):
    db.execute("""INSERT INTO Consumption
                  (consumption_id, FK_wine_id, FK_tasting_id, consumed_date, bottles)
                  VALUES (?, ?, ?, ?, ?)""",
               (consumption_id, wine_id, tasting_id, date, bottles))


def test_an_opening_cannot_borrow_a_note_about_another_wine(db):
    """
    Both foreign keys are individually valid while still disagreeing: each
    points at a row that exists, so referential integrity is satisfied and the
    link is still nonsense. Only a trigger sees it.
    """
    add_note(db, wine_id=1)
    with pytest.raises(sqlite3.IntegrityError, match="different wine"):
        add_opening(db, wine_id=15, tasting_id=90)


def test_an_opening_can_carry_a_note_about_its_own_wine(db):
    """The other half: the trigger must not block the legitimate case."""
    add_note(db, wine_id=15)
    add_opening(db, wine_id=15, tasting_id=90)
    assert db.execute(
        "SELECT COUNT(*) FROM Consumption WHERE FK_tasting_id = 90").fetchone()[0] == 1


def test_editing_an_opening_onto_a_foreign_note_is_rejected(db):
    """The UPDATE half of the same rule."""
    add_note(db, wine_id=1)
    add_opening(db, wine_id=1, tasting_id=90, date="2025-09-02")
    with pytest.raises(sqlite3.IntegrityError, match="different wine"):
        db.execute("UPDATE Consumption SET FK_wine_id = 15 WHERE consumption_id = 90")


def test_a_bottle_cannot_be_drunk_before_it_was_bought(db):
    purchased = db.execute(
        "SELECT purchase_date FROM Wine WHERE wine_id = 15").fetchone()[0]
    assert purchased > "2015-01-01"
    with pytest.raises(sqlite3.IntegrityError, match="before it was purchased"):
        add_opening(db, date="2015-01-01")


def test_a_wine_cannot_be_tasted_before_it_was_bought(db):
    with pytest.raises(sqlite3.IntegrityError, match="before it was purchased"):
        add_note(db, wine_id=1, date="2015-01-01")


def test_dates_must_be_real_iso_dates(db):
    with pytest.raises(sqlite3.IntegrityError):
        add_opening(db, date="not-a-date")


def test_dates_must_be_zero_padded(db):
    """
    date('2025-1-1') is NULL in SQLite, so the CHECK catches the unpadded form
    that a hand-typed spreadsheet export would produce.
    """
    with pytest.raises(sqlite3.IntegrityError):
        add_opening(db, date="2025-1-1")


def test_a_drinking_window_cannot_be_half_open(db):
    """
    `drink_until >= drink_from` alone let this through: with one end NULL the
    comparison is NULL, which SQLite treats as a pass, and every BETWEEN built
    on the column then silently matched nothing.
    """
    with pytest.raises(sqlite3.IntegrityError):
        insert_wine(db, drink_from=2025, drink_until=None)
    with pytest.raises(sqlite3.IntegrityError):
        insert_wine(db, drink_from=None, drink_until=2030)


def test_a_window_may_be_left_entirely_unrecorded(db):
    """Both ends NULL is the legitimate "not assessed yet" case."""
    insert_wine(db, drink_from=None, drink_until=None)
    assert db.execute(
        "SELECT drink_from FROM Wine WHERE wine_id = 99").fetchone()[0] is None


def test_collectors_cannot_share_an_email(db):
    existing = db.execute("SELECT email FROM Collector LIMIT 1").fetchone()[0]
    with pytest.raises(sqlite3.IntegrityError):
        db.execute("INSERT INTO Collector VALUES (90, 'Impostor', ?)", (existing,))


def test_a_cellar_must_have_room_in_it(db):
    """CellarOccupancy divides by capacity, and zero would give NULL not error."""
    with pytest.raises(sqlite3.IntegrityError):
        db.execute("INSERT INTO Location VALUES (90, 'Broken', 14.0, 70.0, 0)")


def test_humidity_is_a_percentage(db):
    with pytest.raises(sqlite3.IntegrityError):
        db.execute("INSERT INTO Location VALUES (90, 'Swamp', 14.0, 250.0, 100)")


def test_a_bottle_cannot_cost_a_negative_amount(db):
    with pytest.raises(sqlite3.IntegrityError):
        insert_wine(db, purchase_price=-5.0)


def test_a_window_cannot_open_before_the_vintage(db):
    with pytest.raises(sqlite3.IntegrityError):
        insert_wine(db, vintage_year=2020, drink_from=2015, drink_until=2030)


def test_an_empty_cellar_reads_as_empty_not_unknown(db):
    """
    The LEFT JOIN in CellarOccupancy exists so a cellar with nothing in it
    still appears. Without COALESCE, SUM() over no rows returned NULL and
    undid that.
    """
    db.execute("INSERT INTO Location VALUES (91, 'Empty Cellar', 14.0, 70.0, 100)")
    row = db.execute("""
        SELECT labels_stored, bottles_bought, bottles_on_hand, capacity_used_percent
        FROM CellarOccupancy WHERE location_id = 91
    """).fetchone()
    assert row == (0, 0, 0, 0.0)


def test_the_drinking_log_never_subtracts_rows_from_bottles(db):
    """
    Q10 counts openings and bottles separately. It used to do
    SUM(bottles) - COUNT(FK_tasting_id), mixing the two; every sample row
    opens one bottle so they agreed and the error was invisible.
    """
    add_note(db, wine_id=15)
    add_opening(db, wine_id=15, tasting_id=90, bottles=2)

    sql = (SQL / "03_queries.sql").read_text(encoding="utf-8")
    q10 = [s for s in split_statements(sql) if "openings_without_a_note" in s][0]
    cursor = db.execute(q10)
    columns = [d[0] for d in cursor.description]
    rows = [dict(zip(columns, r)) for r in cursor.fetchall()]

    for row in rows:
        assert row["openings"] == row["openings_with_a_note"] + row["openings_without_a_note"]
        assert row["bottles_opened"] >= row["openings"]

    year = next(r for r in rows if r["year"] == "2025")
    truth = db.execute("""
        SELECT COUNT(*) FROM Consumption
        WHERE strftime('%Y', consumed_date) = '2025' AND FK_tasting_id IS NULL
    """).fetchone()[0]
    assert year["openings_without_a_note"] == truth


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


def test_one_appellation_cannot_hold_two_classifications(db):
    """
    The key used to be (name, classification), which let 'Chianti Classico'
    exist as DOCG and DOC at once and split one place's holdings over two rows.
    A denomination carries exactly one classification.
    """
    with pytest.raises(sqlite3.IntegrityError):
        db.execute("""INSERT INTO Appellation
                      VALUES (99, 'Chianti Classico', 'DOC', 'Tuscany', 'Italy')""")


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


def test_bottles_purchased_cannot_be_cut_below_what_was_drunk(db):
    """
    The hole the Consumption triggers left open. They all watch the child
    table, so editing the parent reached the same forbidden state from the
    other side: wine 1 has five bottles drunk, and setting its purchase down
    to one produced a remaining stock of -4.
    """
    drunk = db.execute(
        "SELECT bottles_drunk FROM WineStock WHERE wine_id = 1").fetchone()[0]
    assert drunk > 1

    with pytest.raises(sqlite3.IntegrityError, match="below what has already been drunk"):
        db.execute("UPDATE Wine SET bottles_purchased = 1 WHERE wine_id = 1")


def test_bottles_purchased_can_still_be_corrected_downward_within_reason(db):
    """The guard must stop over-cutting, not stop corrections altogether."""
    drunk = db.execute(
        "SELECT bottles_drunk FROM WineStock WHERE wine_id = 1").fetchone()[0]
    db.execute("UPDATE Wine SET bottles_purchased = ? WHERE wine_id = 1", (drunk,))
    assert db.execute(
        "SELECT bottles_remaining FROM WineStock WHERE wine_id = 1").fetchone()[0] == 0


def test_purchase_date_cannot_move_past_an_existing_opening(db):
    with pytest.raises(sqlite3.IntegrityError, match="already drunk"):
        db.execute("UPDATE Wine SET purchase_date = '2030-01-01' WHERE wine_id = 1")


def test_purchase_date_cannot_move_past_an_existing_tasting(db):
    """
    Wine 15 has a tasting but no consumption, so this exercises the tasting
    branch of the trigger rather than the consumption one.
    """
    db.execute("""INSERT INTO Tasting
                  VALUES (90, 15, 1, '2024-01-01', 4, 'note', 'food')""")
    with pytest.raises(sqlite3.IntegrityError, match="already tasted"):
        db.execute("UPDATE Wine SET purchase_date = '2030-01-01' WHERE wine_id = 15")


def test_no_wine_ends_up_with_negative_stock(db):
    """The invariant itself, stated once over the whole table."""
    negative = db.execute(
        "SELECT wine_name FROM WineStock WHERE bottles_remaining < 0").fetchall()
    assert negative == []


def test_an_appellation_must_state_its_classification(db):
    with pytest.raises(sqlite3.IntegrityError):
        db.execute("""INSERT INTO Appellation
                      VALUES (99, 'Nowhere', NULL, 'Tuscany', 'Italy')""")


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
