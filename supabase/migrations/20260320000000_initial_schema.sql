-- Initial Schema for Supabase Sports App Backend

-- User Profiles (Linked to Supabase Auth)
CREATE TABLE public.users (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  email TEXT UNIQUE NOT NULL,
  avatar_url TEXT,
  reputation_score INT DEFAULT 0,
  virtual_currency_balance INT DEFAULT 1000,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Function to handle new user registration automatically via triggers
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id, username, email, avatar_url)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'username', 'user_' || substr(NEW.id::text, 1, 8)),
    NEW.email,
    NEW.raw_user_meta_data->>'avatar_url'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to call the function upon user signup
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


-- Matches Table
CREATE TABLE public.matches (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  home_team TEXT NOT NULL,
  away_team TEXT NOT NULL,
  home_logo_url TEXT,
  away_logo_url TEXT,
  status TEXT CHECK (status IN ('pre_match', 'live', 'finished')) DEFAULT 'pre_match',
  home_score INT DEFAULT 0,
  away_score INT DEFAULT 0,
  minute TEXT,
  started_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- AI Match Insights
CREATE TABLE public.match_insights (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  match_id UUID REFERENCES public.matches(id) ON DELETE CASCADE,
  insight_text TEXT NOT NULL,
  type TEXT CHECK (type IN ('pre_match', 'live', 'post_match')),
  agree_count INT DEFAULT 0,
  unsure_count INT DEFAULT 0,
  disagree_count INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User Votes on AI Insights
CREATE TABLE public.user_insight_votes (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  insight_id UUID REFERENCES public.match_insights(id) ON DELETE CASCADE,
  vote_type TEXT CHECK (vote_type IN ('agree', 'unsure', 'disagree')),
  disagree_reason TEXT,
  custom_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, insight_id)
);

-- Prediction Market (The available bets for a match)
CREATE TABLE public.predictions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  match_id UUID REFERENCES public.matches(id) ON DELETE CASCADE,
  prediction_type TEXT NOT NULL, -- e.g. "Real Madrid to Win", "Next Goal Liverpool"
  odds DECIMAL NOT NULL,
  status TEXT CHECK (status IN ('open', 'resolved', 'cancelled')) DEFAULT 'open',
  result TEXT CHECK (result IN ('won', 'lost', 'null')),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User Bets (Virtual Currency placements)
CREATE TABLE public.user_bets (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  prediction_id UUID REFERENCES public.predictions(id) ON DELETE CASCADE,
  amount_staked INT NOT NULL CHECK (amount_staked > 0),
  potential_payout INT NOT NULL,
  status TEXT CHECK (status IN ('pending', 'won', 'lost', 'refunded')) DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Live Match Room Chat
CREATE TABLE public.chat_messages (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  match_id UUID REFERENCES public.matches(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  message TEXT NOT NULL,
  type TEXT CHECK (type IN ('text', 'system_event')) DEFAULT 'text',
  created_at TIMESTAMPTZ DEFAULT NOW()
);


-- =========================================
-- Enabling Row Level Security (RLS)
-- =========================================

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.match_insights ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_insight_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.predictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_bets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;


-- =========================================
-- Basic RLS Policies
-- =========================================

-- USERS: Anyone can read profiles, but only users can update their own profiles
CREATE POLICY "Public profiles are viewable by everyone." 
  ON public.users FOR SELECT USING (true);
CREATE POLICY "Users can update own profile." 
  ON public.users FOR UPDATE USING (auth.uid() = id);

-- MATCHES: Everyone can read, only service role can insert/update (e.g. from data provider API)
CREATE POLICY "Matches are viewable by everyone." 
  ON public.matches FOR SELECT USING (true);

-- INSIGHTS: Everyone can read
CREATE POLICY "Insights are viewable by everyone." 
  ON public.match_insights FOR SELECT USING (true);

-- VOTES: Users can only see and insert/update their own votes
CREATE POLICY "Users can view own votes." 
  ON public.user_insight_votes FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own votes." 
  ON public.user_insight_votes FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own votes." 
  ON public.user_insight_votes FOR UPDATE USING (auth.uid() = user_id);

-- PREDICTIONS (Market options): Everyone can read
CREATE POLICY "Predictions are viewable by everyone." 
  ON public.predictions FOR SELECT USING (true);

-- USER BETS: Users can only view and insert their own bets
CREATE POLICY "Users can view own bets." 
  ON public.user_bets FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can place bets." 
  ON public.user_bets FOR INSERT WITH CHECK (auth.uid() = user_id);

-- CHAT: Everyone can read, authenticated users can insert (send messages)
CREATE POLICY "Chat messages are viewable by everyone." 
  ON public.chat_messages FOR SELECT USING (true);
CREATE POLICY "Authenticated users can insert chat messages." 
  ON public.chat_messages FOR INSERT WITH CHECK (auth.uid() = user_id);
