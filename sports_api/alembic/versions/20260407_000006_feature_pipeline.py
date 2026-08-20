"""add feature pipeline tables

Revision ID: 20260407_000006
Revises: 20260407_000005
Create Date: 2026-04-07 19:30:00
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "20260407_000006"
down_revision = "20260407_000005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    snapshot_phase_enum = sa.Enum("pre", "live", "finalized", name="snapshot_phase")
    feature_snapshot_phase_enum = sa.Enum("pre", "live", "finalized", name="match_feature_snapshot_phase")

    op.create_table(
        "match_event_timeline",
        sa.Column("provider_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("match_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("provider_event_id", sa.String(length=180), nullable=False),
        sa.Column("event_type", sa.String(length=64), nullable=False),
        sa.Column("event_subtype", sa.String(length=64), nullable=True),
        sa.Column("team_side", sa.String(length=8), nullable=True),
        sa.Column("minute", sa.Integer(), nullable=True),
        sa.Column("stoppage_minute", sa.Integer(), nullable=True),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("player_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("related_player_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("player_name", sa.String(length=180), nullable=True),
        sa.Column("related_player_name", sa.String(length=180), nullable=True),
        sa.Column("score_home", sa.Integer(), nullable=True),
        sa.Column("score_away", sa.Integer(), nullable=True),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
        sa.Column("metadata", postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'{}'::jsonb"), nullable=False),
        sa.ForeignKeyConstraint(["provider_id"], ["providers.id"], name=op.f("fk_match_event_timeline_provider_id_providers")),
        sa.ForeignKeyConstraint(["match_id"], ["matches.id"], name=op.f("fk_match_event_timeline_match_id_matches")),
        sa.ForeignKeyConstraint(["player_id"], ["players.id"], name=op.f("fk_match_event_timeline_player_id_players")),
        sa.ForeignKeyConstraint(["related_player_id"], ["players.id"], name=op.f("fk_match_event_timeline_related_player_id_players")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_match_event_timeline")),
        sa.UniqueConstraint("provider_id", "match_id", "provider_event_id", name=op.f("uq_match_event_timeline_provider_id")),
    )
    op.create_index("ix_match_event_timeline_match_minute", "match_event_timeline", ["match_id", "minute", "sort_order"], unique=False)

    op.create_table(
        "match_market_ticks",
        sa.Column("provider_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("match_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("snapshot_phase", snapshot_phase_enum, nullable=False),
        sa.Column("market_type", sa.String(length=64), nullable=False),
        sa.Column("selection_key", sa.String(length=64), nullable=False),
        sa.Column("tick_time", sa.DateTime(timezone=True), nullable=False),
        sa.Column("minute", sa.Integer(), nullable=True),
        sa.Column("line_value", sa.Float(), nullable=True),
        sa.Column("odds_decimal", sa.Float(), nullable=True),
        sa.Column("implied_prob", sa.Float(), nullable=True),
        sa.Column("normalized_prob", sa.Float(), nullable=True),
        sa.Column("bookmaker_key", sa.String(length=80), nullable=True),
        sa.Column("suspended", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
        sa.Column("metadata", postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'{}'::jsonb"), nullable=False),
        sa.ForeignKeyConstraint(["provider_id"], ["providers.id"], name=op.f("fk_match_market_ticks_provider_id_providers")),
        sa.ForeignKeyConstraint(["match_id"], ["matches.id"], name=op.f("fk_match_market_ticks_match_id_matches")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_match_market_ticks")),
        sa.UniqueConstraint(
            "provider_id",
            "match_id",
            "snapshot_phase",
            "market_type",
            "selection_key",
            "line_value",
            "tick_time",
            name=op.f("uq_match_market_ticks_provider_id"),
        ),
    )
    op.create_index("ix_match_market_ticks_match_time", "match_market_ticks", ["match_id", "tick_time"], unique=False)

    op.create_table(
        "match_live_stat_frames",
        sa.Column("provider_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("match_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("tick_time", sa.DateTime(timezone=True), nullable=False),
        sa.Column("minute", sa.Integer(), nullable=True),
        sa.Column("home_xg", sa.Float(), nullable=True),
        sa.Column("away_xg", sa.Float(), nullable=True),
        sa.Column("home_shots", sa.Integer(), nullable=True),
        sa.Column("away_shots", sa.Integer(), nullable=True),
        sa.Column("home_shots_on_target", sa.Integer(), nullable=True),
        sa.Column("away_shots_on_target", sa.Integer(), nullable=True),
        sa.Column("home_corners", sa.Integer(), nullable=True),
        sa.Column("away_corners", sa.Integer(), nullable=True),
        sa.Column("home_possession", sa.Float(), nullable=True),
        sa.Column("away_possession", sa.Float(), nullable=True),
        sa.Column("home_dangerous_attacks", sa.Integer(), nullable=True),
        sa.Column("away_dangerous_attacks", sa.Integer(), nullable=True),
        sa.Column("home_box_entries", sa.Integer(), nullable=True),
        sa.Column("away_box_entries", sa.Integer(), nullable=True),
        sa.Column("home_pressure_index", sa.Float(), nullable=True),
        sa.Column("away_pressure_index", sa.Float(), nullable=True),
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
        sa.Column("metadata", postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'{}'::jsonb"), nullable=False),
        sa.ForeignKeyConstraint(["provider_id"], ["providers.id"], name=op.f("fk_match_live_stat_frames_provider_id_providers")),
        sa.ForeignKeyConstraint(["match_id"], ["matches.id"], name=op.f("fk_match_live_stat_frames_match_id_matches")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_match_live_stat_frames")),
        sa.UniqueConstraint("provider_id", "match_id", "minute", "tick_time", name=op.f("uq_match_live_stat_frames_provider_id")),
    )
    op.create_index("ix_match_live_stat_frames_match_time", "match_live_stat_frames", ["match_id", "tick_time"], unique=False)

    op.create_table(
        "team_rating_daily",
        sa.Column("team_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("competition_season_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("rating_date", sa.Date(), nullable=False),
        sa.Column("feature_version", sa.String(length=32), nullable=False),
        sa.Column("elo_rating", sa.Float(), nullable=True),
        sa.Column("team_strength", sa.Float(), nullable=True),
        sa.Column("form_points_avg", sa.Float(), nullable=True),
        sa.Column("xg_form_avg", sa.Float(), nullable=True),
        sa.Column("xga_form_avg", sa.Float(), nullable=True),
        sa.Column("rest_days", sa.Float(), nullable=True),
        sa.Column("fatigue_minutes_14d", sa.Integer(), nullable=True),
        sa.Column("matches_sampled", sa.Integer(), nullable=True),
        sa.Column("availability_json", postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'{}'::jsonb"), nullable=False),
        sa.Column("quality_json", postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'{}'::jsonb"), nullable=False),
        sa.Column("source_json", postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'{}'::jsonb"), nullable=False),
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
        sa.Column("metadata", postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'{}'::jsonb"), nullable=False),
        sa.ForeignKeyConstraint(["competition_season_id"], ["competition_seasons.id"], name=op.f("fk_team_rating_daily_competition_season_id_competition_seasons")),
        sa.ForeignKeyConstraint(["team_id"], ["teams.id"], name=op.f("fk_team_rating_daily_team_id_teams")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_team_rating_daily")),
        sa.UniqueConstraint("team_id", "rating_date", "feature_version", name=op.f("uq_team_rating_daily_team_id")),
    )
    op.create_index("ix_team_rating_daily_date", "team_rating_daily", ["rating_date"], unique=False)

    op.create_table(
        "player_rating_daily",
        sa.Column("player_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("team_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("rating_date", sa.Date(), nullable=False),
        sa.Column("feature_version", sa.String(length=32), nullable=False),
        sa.Column("player_power", sa.Float(), nullable=True),
        sa.Column("appearance_rating", sa.Float(), nullable=True),
        sa.Column("recent_minutes", sa.Integer(), nullable=True),
        sa.Column("appearances_sampled", sa.Integer(), nullable=True),
        sa.Column("role_code", sa.String(length=32), nullable=True),
        sa.Column("availability_json", postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'{}'::jsonb"), nullable=False),
        sa.Column("quality_json", postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'{}'::jsonb"), nullable=False),
        sa.Column("source_json", postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'{}'::jsonb"), nullable=False),
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
        sa.Column("metadata", postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'{}'::jsonb"), nullable=False),
        sa.ForeignKeyConstraint(["player_id"], ["players.id"], name=op.f("fk_player_rating_daily_player_id_players")),
        sa.ForeignKeyConstraint(["team_id"], ["teams.id"], name=op.f("fk_player_rating_daily_team_id_teams")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_player_rating_daily")),
        sa.UniqueConstraint("player_id", "rating_date", "feature_version", name=op.f("uq_player_rating_daily_player_id")),
    )
    op.create_index("ix_player_rating_daily_date", "player_rating_daily", ["rating_date"], unique=False)

    op.create_table(
        "match_feature_snapshots",
        sa.Column("match_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("snapshot_phase", feature_snapshot_phase_enum, nullable=False),
        sa.Column("snapshot_minute", sa.Integer(), nullable=False),
        sa.Column("snapshot_ts", sa.DateTime(timezone=True), nullable=False),
        sa.Column("feature_version", sa.String(length=32), nullable=False),
        sa.Column("is_finalized", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("availability_json", postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'{}'::jsonb"), nullable=False),
        sa.Column("quality_json", postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'{}'::jsonb"), nullable=False),
        sa.Column("source_json", postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'{}'::jsonb"), nullable=False),
        sa.Column("expected_goal_line_proxy", sa.Boolean(), nullable=True),
        sa.Column("predicted_lineup_low_history", sa.Boolean(), nullable=True),
        sa.Column("betfair_unavailable", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("state_model_home_prob", sa.Float(), nullable=True),
        sa.Column("pre_home_prob", sa.Float(), nullable=True),
        sa.Column("pre_draw_prob", sa.Float(), nullable=True),
        sa.Column("pre_away_prob", sa.Float(), nullable=True),
        sa.Column("pre_favorite_gap", sa.Float(), nullable=True),
        sa.Column("pre_expected_goal_line", sa.Float(), nullable=True),
        sa.Column("team_strength_diff", sa.Float(), nullable=True),
        sa.Column("elo_diff", sa.Float(), nullable=True),
        sa.Column("form_points_diff", sa.Float(), nullable=True),
        sa.Column("xg_form_diff", sa.Float(), nullable=True),
        sa.Column("xga_form_diff", sa.Float(), nullable=True),
        sa.Column("rest_days_diff", sa.Float(), nullable=True),
        sa.Column("fatigue_diff", sa.Float(), nullable=True),
        sa.Column("pred_home_lineup_strength", sa.Float(), nullable=True),
        sa.Column("pred_away_lineup_strength", sa.Float(), nullable=True),
        sa.Column("pred_lineup_strength_diff", sa.Float(), nullable=True),
        sa.Column("real_home_lineup_strength", sa.Float(), nullable=True),
        sa.Column("real_away_lineup_strength", sa.Float(), nullable=True),
        sa.Column("real_lineup_strength_diff", sa.Float(), nullable=True),
        sa.Column("home_defense_strength", sa.Float(), nullable=True),
        sa.Column("away_defense_strength", sa.Float(), nullable=True),
        sa.Column("midfield_strength_diff", sa.Float(), nullable=True),
        sa.Column("attack_strength_diff", sa.Float(), nullable=True),
        sa.Column("lineup_surprise_score", sa.Float(), nullable=True),
        sa.Column("rotation_diff", sa.Float(), nullable=True),
        sa.Column("missing_strength_diff", sa.Float(), nullable=True),
        sa.Column("minute_norm", sa.Float(), nullable=True),
        sa.Column("time_remaining_norm", sa.Float(), nullable=True),
        sa.Column("home_score", sa.Integer(), nullable=True),
        sa.Column("away_score", sa.Integer(), nullable=True),
        sa.Column("score_diff", sa.Integer(), nullable=True),
        sa.Column("goal_total", sa.Integer(), nullable=True),
        sa.Column("home_red_cards", sa.Integer(), nullable=True),
        sa.Column("away_red_cards", sa.Integer(), nullable=True),
        sa.Column("red_card_diff", sa.Integer(), nullable=True),
        sa.Column("yellow_card_diff", sa.Integer(), nullable=True),
        sa.Column("subs_diff", sa.Integer(), nullable=True),
        sa.Column("time_since_last_goal", sa.Float(), nullable=True),
        sa.Column("time_since_last_red_card", sa.Float(), nullable=True),
        sa.Column("xg_diff_total", sa.Float(), nullable=True),
        sa.Column("shots_diff_total", sa.Float(), nullable=True),
        sa.Column("sot_diff_total", sa.Float(), nullable=True),
        sa.Column("corners_diff_total", sa.Float(), nullable=True),
        sa.Column("possession_diff", sa.Float(), nullable=True),
        sa.Column("xg_diff_last5", sa.Float(), nullable=True),
        sa.Column("xg_diff_last10", sa.Float(), nullable=True),
        sa.Column("shots_diff_last5", sa.Float(), nullable=True),
        sa.Column("shots_diff_last10", sa.Float(), nullable=True),
        sa.Column("sot_diff_last10", sa.Float(), nullable=True),
        sa.Column("dangerous_attacks_diff_last10", sa.Float(), nullable=True),
        sa.Column("box_entries_diff_last10", sa.Float(), nullable=True),
        sa.Column("pressure_diff_last10", sa.Float(), nullable=True),
        sa.Column("momentum_diff", sa.Float(), nullable=True),
        sa.Column("live_home_prob", sa.Float(), nullable=True),
        sa.Column("live_draw_prob", sa.Float(), nullable=True),
        sa.Column("live_away_prob", sa.Float(), nullable=True),
        sa.Column("live_over25_prob", sa.Float(), nullable=True),
        sa.Column("live_under25_prob", sa.Float(), nullable=True),
        sa.Column("live_next_goal_home_prob", sa.Float(), nullable=True),
        sa.Column("home_prob_shift_from_pre", sa.Float(), nullable=True),
        sa.Column("draw_prob_shift_from_pre", sa.Float(), nullable=True),
        sa.Column("away_prob_shift_from_pre", sa.Float(), nullable=True),
        sa.Column("home_prob_change_last1", sa.Float(), nullable=True),
        sa.Column("home_prob_change_last5", sa.Float(), nullable=True),
        sa.Column("market_volatility_last5", sa.Float(), nullable=True),
        sa.Column("betfair_total_matched", sa.Float(), nullable=True),
        sa.Column("betfair_liquidity_score", sa.Float(), nullable=True),
        sa.Column("betfair_home_spread", sa.Float(), nullable=True),
        sa.Column("market_overreaction_score", sa.Float(), nullable=True),
        sa.Column("market_underreaction_score", sa.Float(), nullable=True),
        sa.Column("favorite_fragility_score", sa.Float(), nullable=True),
        sa.Column("underdog_resistance_score", sa.Float(), nullable=True),
        sa.Column("comeback_potential_score", sa.Float(), nullable=True),
        sa.Column("late_goal_risk_score", sa.Float(), nullable=True),
        sa.Column("state_cluster_id", sa.Integer(), nullable=True),
        sa.Column("score_state_class", sa.String(length=64), nullable=True),
        sa.Column("market_state_class", sa.String(length=64), nullable=True),
        sa.Column("label_final_result_1x2", sa.String(length=8), nullable=True),
        sa.Column("label_home_win", sa.Boolean(), nullable=True),
        sa.Column("label_goal_next10min", sa.Boolean(), nullable=True),
        sa.Column("label_next_goal_team", sa.String(length=16), nullable=True),
        sa.Column("label_result_from_snapshot_to_end", sa.String(length=16), nullable=True),
        sa.Column("label_over25_from_snapshot", sa.Boolean(), nullable=True),
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
        sa.Column("metadata", postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'{}'::jsonb"), nullable=False),
        sa.ForeignKeyConstraint(["match_id"], ["matches.id"], name=op.f("fk_match_feature_snapshots_match_id_matches")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_match_feature_snapshots")),
        sa.UniqueConstraint("match_id", "snapshot_phase", "snapshot_minute", "feature_version", name=op.f("uq_match_feature_snapshots_match_id")),
    )
    op.create_index("ix_match_feature_snapshots_match_phase_minute", "match_feature_snapshots", ["match_id", "snapshot_phase", "snapshot_minute"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_match_feature_snapshots_match_phase_minute", table_name="match_feature_snapshots")
    op.drop_table("match_feature_snapshots")
    op.drop_index("ix_player_rating_daily_date", table_name="player_rating_daily")
    op.drop_table("player_rating_daily")
    op.drop_index("ix_team_rating_daily_date", table_name="team_rating_daily")
    op.drop_table("team_rating_daily")
    op.drop_index("ix_match_live_stat_frames_match_time", table_name="match_live_stat_frames")
    op.drop_table("match_live_stat_frames")
    op.drop_index("ix_match_market_ticks_match_time", table_name="match_market_ticks")
    op.drop_table("match_market_ticks")
    op.drop_index("ix_match_event_timeline_match_minute", table_name="match_event_timeline")
    op.drop_table("match_event_timeline")
    sa.Enum(name="match_feature_snapshot_phase").drop(op.get_bind(), checkfirst=True)
    sa.Enum(name="snapshot_phase").drop(op.get_bind(), checkfirst=True)
