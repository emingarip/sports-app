from sqlalchemy.dialects import postgresql

from app.services.catalog_service import _build_seasons_stmt


def test_build_seasons_stmt_uses_subquery_for_competition_filter() -> None:
    stmt = _build_seasons_stmt(
        competition_slug="england-premier-league",
        current_only=True,
        limit=25,
    )

    compiled = str(
        stmt.compile(
            dialect=postgresql.dialect(),
            compile_kwargs={"literal_binds": True},
        )
    )

    assert "DISTINCT ON" not in compiled
    assert "SELECT DISTINCT competition_seasons.season_id" in compiled
    assert "competitions.slug = 'england-premier-league'" in compiled
    assert "seasons.is_current IS true" in compiled


def test_build_seasons_stmt_without_competition_filter_has_simple_ordering() -> None:
    stmt = _build_seasons_stmt(
        competition_slug=None,
        current_only=False,
        limit=10,
    )

    compiled = str(
        stmt.compile(
            dialect=postgresql.dialect(),
            compile_kwargs={"literal_binds": True},
        )
    )

    assert "FROM seasons" in compiled
    assert "ORDER BY seasons.label DESC, seasons.id DESC" in compiled
    assert "LIMIT 10" in compiled
