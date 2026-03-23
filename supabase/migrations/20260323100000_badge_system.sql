-- Badge Achievement System
-- Creates tables for badge definitions, user badge progress, and login streaks.

-- 1. Badge definitions (static seed data)
CREATE TABLE IF NOT EXISTS badges (
  id TEXT PRIMARY KEY,
  category TEXT NOT NULL,
  name_tr TEXT NOT NULL,
  name_en TEXT NOT NULL,
  description_tr TEXT NOT NULL,
  description_en TEXT NOT NULL,
  icon_name TEXT NOT NULL,
  max_tier INT DEFAULT 3,
  trigger_type TEXT NOT NULL,
  trigger_target INT NOT NULL,
  tier2_target INT,
  tier3_target INT,
  k_coin_reward INT DEFAULT 0,
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. User badge progress
CREATE TABLE IF NOT EXISTS user_badges (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  badge_id TEXT REFERENCES badges(id) NOT NULL,
  current_tier INT DEFAULT 0,
  progress INT DEFAULT 0,
  unlocked_at TIMESTAMPTZ,
  last_tier_up TIMESTAMPTZ,
  UNIQUE(user_id, badge_id)
);

-- 3. User login streaks
CREATE TABLE IF NOT EXISTS user_streaks (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  current_streak INT DEFAULT 0,
  longest_streak INT DEFAULT 0,
  last_login_date DATE,
  total_logins INT DEFAULT 0
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_user_badges_user ON user_badges(user_id);
CREATE INDEX IF NOT EXISTS idx_user_badges_badge ON user_badges(badge_id);

-- RLS Policies
ALTER TABLE badges ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_badges ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_streaks ENABLE ROW LEVEL SECURITY;

-- Everyone can read badge definitions
CREATE POLICY "Anyone can read badges" ON badges FOR SELECT USING (true);

-- Users can only read/write their own badge data
CREATE POLICY "Users read own badges" ON user_badges FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users insert own badges" ON user_badges FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users update own badges" ON user_badges FOR UPDATE USING (auth.uid() = user_id);

-- Users can only read/write their own streaks
CREATE POLICY "Users read own streaks" ON user_streaks FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users insert own streaks" ON user_streaks FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users update own streaks" ON user_streaks FOR UPDATE USING (auth.uid() = user_id);

-- =============================================
-- SEED DATA: Badge Definitions
-- =============================================

-- Onboarding Badges
INSERT INTO badges (id, category, name_tr, name_en, description_tr, description_en, icon_name, trigger_type, trigger_target, tier2_target, tier3_target, k_coin_reward, sort_order) VALUES
('first_step',    'onboarding', 'İlk Adım',    'First Step',   'Hesabını oluştur ve profilini tamamla', 'Create account and complete profile', 'person_add', 'one_time', 1, NULL, NULL, 50, 1),
('verified',      'onboarding', 'Doğrulanmış',  'Verified',     'E-posta doğrulamasını tamamla', 'Complete email verification', 'verified', 'one_time', 1, NULL, NULL, 100, 2),
('photo_ready',   'onboarding', 'Fotoğraflı',   'Photo Ready',  'Profil fotoğrafı yükle', 'Upload a profile photo', 'camera_alt', 'one_time', 1, NULL, NULL, 25, 3);

-- Engagement Badges
INSERT INTO badges (id, category, name_tr, name_en, description_tr, description_en, icon_name, trigger_type, trigger_target, tier2_target, tier3_target, k_coin_reward, sort_order) VALUES
('curious',       'engagement', 'Meraklı',      'Curious',      'Maç detaylarını keşfet', 'Explore match details', 'visibility', 'counter', 10, 50, 200, 50, 10),
('explorer',      'engagement', 'Gezgin',       'Explorer',     'Farklı liglerden maç görüntüle', 'View matches from different leagues', 'explore', 'counter', 5, 10, 20, 100, 11);

-- Prediction Badges
INSERT INTO badges (id, category, name_tr, name_en, description_tr, description_en, icon_name, trigger_type, trigger_target, tier2_target, tier3_target, k_coin_reward, sort_order) VALUES
('rookie_pred',   'prediction', 'Çaylak Tahminci', 'Rookie Predictor', 'İlk tahminini yap', 'Make your first prediction', 'casino', 'one_time', 1, NULL, NULL, 25, 20),
('sharp_eye',     'prediction', 'Keskin Göz',   'Sharp Eye',    'Doğru tahminler yap', 'Make correct predictions', 'gps_fixed', 'counter', 5, 25, 100, 100, 21),
('streak_killer', 'prediction', 'Seri Katil',   'Streak Killer', 'Arka arkaya doğru tahminler', 'Consecutive correct predictions', 'local_fire_department', 'streak', 3, 5, 10, 200, 22);

-- Economy Badges
INSERT INTO badges (id, category, name_tr, name_en, description_tr, description_en, icon_name, trigger_type, trigger_target, tier2_target, tier3_target, k_coin_reward, sort_order) VALUES
('first_earn',    'economy', 'İlk Kazancım',  'First Earnings', 'K-Coin biriktirmeye başla', 'Start earning K-Coins', 'savings', 'threshold', 100, 5000, 25000, 0, 30),
('big_spender',   'economy', 'Harcamacı',     'Big Spender',   'K-Coin harcaması yap', 'Spend K-Coins', 'shopping_cart', 'counter', 5, 25, 100, 0, 31);

-- Social/Leaderboard Badges
INSERT INTO badges (id, category, name_tr, name_en, description_tr, description_en, icon_name, trigger_type, trigger_target, tier2_target, tier3_target, k_coin_reward, sort_order) VALUES
('rising_star',   'social', 'Yıldız Aday',    'Rising Star',   'Liderlik tablosunda yüksel', 'Climb the leaderboard', 'trending_up', 'threshold', 50, 10, 1, 200, 40),
('champion',      'social', 'Kral',           'Champion',      'Liderlik tablosunda zirveye ulaş', 'Reach the top of the leaderboard', 'emoji_events', 'one_time', 1, NULL, NULL, 1000, 41);

-- Streak Badges
INSERT INTO badges (id, category, name_tr, name_en, description_tr, description_en, icon_name, trigger_type, trigger_target, tier2_target, tier3_target, k_coin_reward, sort_order) VALUES
('weekly',        'streak', 'Haftalık',       'Weekly',        'Üst üste gün giriş yap', 'Login on consecutive days', 'date_range', 'streak', 7, 30, 90, 100, 50),
('dedicated',     'streak', 'Sadık',          'Dedicated',     'Toplam giriş sayısına ulaş', 'Reach total login count', 'loyalty', 'counter', 30, 100, 365, 150, 51);
