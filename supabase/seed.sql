-- Seed Data for SportsApp MVP Testing

-- 1. Insert Mock Users
-- Note: In a real Supabase environment with Auth, you would create users through the Auth endpoint.
-- We are skipping inserting mock users to avoid auth.users FK constraint issues in active Supabase instances.

-- 2. Insert a Mock Match
INSERT INTO public.matches (id, home_team, away_team, status, home_score, away_score, minute) VALUES
('11111111-1111-1111-1111-111111111111', 'LIVERPOOL', 'R. MADRID', 'live', 2, 1, '74');

-- 3. Insert AI Insights for this match
INSERT INTO public.match_insights (id, match_id, insight_text, type, agree_count, unsure_count, disagree_count) VALUES
('22222222-2222-2222-2222-222222222221', '11111111-1111-1111-1111-111111111111', 'Liverpool has scored in 12 consecutive home matches across all competitions.', 'pre_match', 85, 10, 5),
('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'Real Madrid typically concedes 65% of their goals in the final 20 minutes of away games.', 'pre_match', 78, 10, 12),
('22222222-2222-2222-2222-222222222223', '11111111-1111-1111-1111-111111111111', 'Mohamed Salah has a 92% success rate in 1v1 situations against Ferland Mendy.', 'live', 60, 20, 20);

-- 4. Insert Predictions (Market bets available)
INSERT INTO public.predictions (id, match_id, prediction_type, odds, status) VALUES
('33333333-3333-3333-3333-333333333331', '11111111-1111-1111-1111-111111111111', 'Real Madrid to Win or Draw', 2.10, 'open'),
('33333333-3333-3333-3333-333333333332', '11111111-1111-1111-1111-111111111111', 'Next Goal Liverpool', 1.85, 'open'),
('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 'Total Goals Over 3.5', 1.65, 'open');

-- 5. Insert Chat Messages for Match Room
INSERT INTO public.chat_messages (id, match_id, user_id, message, type) VALUES
('44444444-4444-4444-4444-444444444441', '11111111-1111-1111-1111-111111111111', NULL, 'What a start to this half!', 'text'),
('44444444-4444-4444-4444-444444444442', '11111111-1111-1111-1111-111111111111', NULL, 'Madrid looks dangerous on the counter.', 'text'),
('44444444-4444-4444-4444-444444444443', '11111111-1111-1111-1111-111111111111', NULL, 'Vinicius is too fast!', 'text'),
('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', NULL, 'Yellow Card: Eder Militao', 'system_event');
