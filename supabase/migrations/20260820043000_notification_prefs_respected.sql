-- Eski gol/mac-basladi trigger'i kullanici tercihini HIC okumuyordu.
--
-- `process_match_events_for_notifications()` (20260322000000_notifications_engine.sql)
-- maci favorileyen TUM kullanicilara bildirim yaziyor; arayuzdeki
-- "Goals" / "Match Started" anahtarlari (`user_notification_preferences`)
-- veritabanina yaziliyor ama okunmuyordu. Yani kullanici bildirimi kapatsa
-- bile almaya devam ederdi.
--
-- Bu trigger `public.matches` uzerinde duruyor ve o tabloyu `sync-live-matches`
-- edge function'i (Highlightly kaynakli) besliyor. Uygulamanin ana ekrani artik
-- maclari AI Sport Agent'tan okudugu icin bu yol ikincil kaldi; agent tarafinin
-- bildirimlerini `scripts/goal_notifier.py` uretiyor. Trigger yine de duruyor:
-- uygulama Supabase kaynagina geri alinirsa calismaya devam etsin diye
-- SILMIYORUZ, sadece tercihe saygili hale getiriyoruz.

CREATE OR REPLACE FUNCTION public.process_match_events_for_notifications()
RETURNS TRIGGER AS $$
DECLARE
  home_team_name TEXT;
  away_team_name TEXT;
  notification_title TEXT;
  notification_message TEXT;
  notification_type TEXT;
  pref_column TEXT;
  fav_record RECORD;
BEGIN
  IF TG_OP <> 'UPDATE' THEN
    RETURN NEW;
  END IF;

  IF NEW.home_score > OLD.home_score THEN
    notification_type := 'GOAL';
    SELECT t.name INTO home_team_name FROM public.teams t WHERE t.id = NEW.home_team_id;
    SELECT t.name INTO away_team_name FROM public.teams t WHERE t.id = NEW.away_team_id;
    notification_title := '🚨 GOL! ' || home_team_name;
    notification_message := home_team_name || ' golü buldu! Skor: ' || NEW.home_score || ' - ' || NEW.away_score || ' (' || away_team_name || ')';

  ELSIF NEW.away_score > OLD.away_score THEN
    notification_type := 'GOAL';
    SELECT t.name INTO home_team_name FROM public.teams t WHERE t.id = NEW.home_team_id;
    SELECT t.name INTO away_team_name FROM public.teams t WHERE t.id = NEW.away_team_id;
    notification_title := '🚨 GOL! ' || away_team_name;
    notification_message := away_team_name || ' golü buldu! Skor: ' || NEW.home_score || ' - ' || NEW.away_score || ' (' || home_team_name || ')';

  ELSIF OLD.status <> 'LIVE' AND NEW.status = 'LIVE' THEN
    notification_type := 'MATCH_START';
    SELECT t.name INTO home_team_name FROM public.teams t WHERE t.id = NEW.home_team_id;
    SELECT t.name INTO away_team_name FROM public.teams t WHERE t.id = NEW.away_team_id;
    notification_title := '⚽ Maç Başladı!';
    notification_message := home_team_name || ' - ' || away_team_name || ' maçı an itibariyle başladı.';

  ELSE
    RETURN NEW;
  END IF;

  -- Hangi tercih kolonu bu olayi yonetiyor.
  pref_column := CASE notification_type
                   WHEN 'GOAL' THEN 'notify_goals'
                   ELSE 'notify_match_start'
                 END;

  -- Maci favorileyen ve ilgili bildirimi KAPATMAMIS kullanicilar.
  -- Tercih satiri yoksa varsayilan ACIK (uygulamadaki varsayilanla ayni).
  FOR fav_record IN (
    SELECT f.user_id
    FROM public.user_favorite_matches f
    LEFT JOIN public.user_notification_preferences p ON p.user_id = f.user_id
    WHERE f.match_id = NEW.id::text
      AND COALESCE(
            CASE pref_column
              WHEN 'notify_goals' THEN p.notify_goals
              ELSE p.notify_match_start
            END,
            TRUE
          ) IS TRUE
  ) LOOP
    INSERT INTO public.notifications (user_id, match_id, title, message, type)
    VALUES (fav_record.user_id, NEW.id, notification_title, notification_message, notification_type);
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
