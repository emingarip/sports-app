from dataclasses import dataclass, field

from app.db.models.domain import Match, RelationType


@dataclass(slots=True)
class RelationDraft:
    source_entity_uid: str
    target_entity_uid: str
    relation_type: RelationType
    weight: float = 1.0
    metadata: dict = field(default_factory=dict)


def build_match_relation_drafts(match: Match) -> list[RelationDraft]:
    drafts: list[RelationDraft] = [
        RelationDraft(
            source_entity_uid=match.entity_uid,
            target_entity_uid=match.home_team.entity_uid,
            relation_type=RelationType.match_home_team,
        ),
        RelationDraft(
            source_entity_uid=match.entity_uid,
            target_entity_uid=match.away_team.entity_uid,
            relation_type=RelationType.match_away_team,
        ),
    ]

    if match.competition_season is not None:
        drafts.append(
            RelationDraft(
                source_entity_uid=match.entity_uid,
                target_entity_uid=match.competition_season.entity_uid,
                relation_type=RelationType.match_belongs_to_competition_season,
            )
        )

    return drafts
