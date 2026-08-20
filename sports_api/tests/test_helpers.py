from app.core.text import slugify_text
from app.db.models.domain import CompetitionType
from app.services.bootstrap_persistence import infer_competition_type


def test_slugify_text_normalizes_unicode() -> None:
    assert slugify_text("İngiltere Kupası") == "ingiltere-kupas"


def test_infer_competition_type_detects_common_patterns() -> None:
    assert infer_competition_type("FA Cup") is CompetitionType.cup
    assert infer_competition_type("UEFA Nations League") is CompetitionType.international
    assert infer_competition_type("Club Friendly Games") is CompetitionType.friendly
    assert infer_competition_type("Premier League") is CompetitionType.league
