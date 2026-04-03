-- Create faq_categories table
CREATE TABLE IF NOT EXISTS faq_categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    icon TEXT, -- e.g., MaterialIcons name or custom string
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create faq_articles table
CREATE TABLE IF NOT EXISTS faq_articles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category_id UUID REFERENCES faq_categories(id) ON DELETE CASCADE,
    question TEXT NOT NULL,
    answer TEXT NOT NULL,
    is_published BOOLEAN DEFAULT true,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS
ALTER TABLE faq_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE faq_articles ENABLE ROW LEVEL SECURITY;

-- Everyone can read published articles and categories
CREATE POLICY "Public can view categories"
    ON faq_categories FOR SELECT TO public
    USING (true);

CREATE POLICY "Public can view published articles"
    ON faq_articles FOR SELECT TO public
    USING (is_published = true);

-- Seed Data (Basic Defaults)
INSERT INTO faq_categories (name, icon, sort_order) VALUES 
('Hesap ve Profil', 'person', 1),
('Gamification & Puanlar', 'workspace_premium', 2),
('Tahminler & Bahis', 'sports_soccer', 3),
('Teknik & Destek', 'build', 4);

-- We use DO block to seed articles to get the UUIDs of categories
DO $$ 
DECLARE 
    cat_account UUID;
    cat_game UUID;
    cat_bet UUID;
    cat_tech UUID;
BEGIN
    SELECT id INTO cat_account FROM faq_categories WHERE name = 'Hesap ve Profil' LIMIT 1;
    SELECT id INTO cat_game FROM faq_categories WHERE name = 'Gamification & Puanlar' LIMIT 1;
    SELECT id INTO cat_bet FROM faq_categories WHERE name = 'Tahminler & Bahis' LIMIT 1;
    SELECT id INTO cat_tech FROM faq_categories WHERE name = 'Teknik & Destek' LIMIT 1;

    INSERT INTO faq_articles (category_id, question, answer, sort_order) VALUES 
    (cat_account, 'Şifremi nasıl değiştirebilirim?', 'Profil sekmesine giderek "Ayarlar" butonuna tıklayıp Güvenlik adımından şifrenizi sıfırlayabilir veya değiştirebilirsiniz.', 1),
    (cat_account, 'Kullanıcı adım başkası tarafından alınmış, ne yapmalıyım?', 'Sistemimiz her kullanıcı adının benzersiz olmasını şart koşar. Lütfen farklı harf veya sayı kombinasyonları deneyin.', 2),
    (cat_game, 'K-Coin nedir ve nasıl kazanılır?', 'K-Coin, uygulama içindeki puan/para birimidir. Günlük giriş yaparak, rozet kazanarak ve anlık maç içi görevleri tamamlayarak K-Coin kazanabilirsiniz.', 1),
    (cat_game, 'Rozet sistemi nasıl çalışır?', 'Sistemimizde belirlenen kuralları tetiklediğinizde (Örn: 7 gün üst üste giriş yapmak) algoritmamız bunu otomatik yakalar ve size ilgili rozeti ve ödülünü otomatik teslim eder.', 2),
    (cat_bet, 'Tahmin oranları nasıl belirleniyor?', 'Yapay zeka (MatchAIAnalyzer) modelimiz, takımların form durumu, sakatlıklar ve geçmiş binlerce maçın verisini analiz ederek bu oranları her saat başı günceller.', 1),
    (cat_tech, 'Canlı destek saatleri nedir?', 'Canlı destek ekibimiz haftanın 7 günü 09:00 - 00:00 saatleri arasında ana dilinizde hizmet vermektedir.', 1),
    (cat_tech, 'Uygulama çökerse ne yapmalıyım?', 'Profil ekranındaki "Sorun Bildir" (Bug Report) butonunu kullanarak, çökme anının açıklaması ile birlikte bize mesaj gönderebilirsiniz. Loglarınız otomatik olarak ekibimize ulaşır.', 2);
END $$;
