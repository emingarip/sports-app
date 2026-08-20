-- ============================================================================
-- ACIL: matches tablosuna yazma tamamen kirikti.
--
-- `trg_match_events_notifications` (AFTER UPDATE ON public.matches) tetikleyicisi
-- `process_match_events_for_notifications()` fonksiyonunu cagiriyor. Fonksiyon
-- var olmayan iki seyi okuyor:
--
--   1. `public.teams` tablosu       -> hic yaratilmamis
--   2. `NEW.home_team_id` / `away_team_id` kolonlari -> matches'te yok
--
-- matches gercekte takim adlarini METIN olarak tutuyor: `home_team`, `away_team`.
--
-- Sonuc: skoru degistiren HER upsert `relation "public.teams" does not exist`
-- ile patliyordu. `sync-live-matches` edge function 500 donuyor, dolayisiyla
-- canli mac verisi donuyor: son basarili senkron 2026-08-20 01:15 UTC. Uygulama
-- bitmis maclari "canli" gosteriyor, simulation_engine de bitmis maclarin
-- odalarini canlandiriyordu.
--
-- Bu duzeltme bildirim/tercih mantigina DOKUNMUYOR; yalnizca sema referanslarini
-- gercek kolonlara ceviriyor.
--
-- Ayrica: status karsilastirmasi 'LIVE' (buyuk harf) yaziliyordu ama CHECK
-- kisiti yalnizca 'pre_match' | 'live' | 'finished' kabul ediyor. Yani
-- MATCH_START bildirimi hicbir zaman tetiklenmemisti. O da duzeltildi.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.process_match_events_for_notifications()
RETURNS TRIGGER AS $notif$
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

  -- Takim adlari zaten satirda; teams tablosuna bakmaya gerek yok (ve o tablo yok).
  home_team_name := COALESCE(NEW.home_team, 'Ev sahibi');
  away_team_name := COALESCE(NEW.away_team, 'Deplasman');

  IF NEW.home_score > OLD.home_score THEN
    notification_type := 'GOAL';
    notification_title := '🚨 GOL! ' || home_team_name;
    notification_message := home_team_name || ' golü buldu! Skor: ' || NEW.home_score || ' - ' || NEW.away_score || ' (' || away_team_name || ')';

  ELSIF NEW.away_score > OLD.away_score THEN
    notification_type := 'GOAL';
    notification_title := '🚨 GOL! ' || away_team_name;
    notification_message := away_team_name || ' golü buldu! Skor: ' || NEW.home_score || ' - ' || NEW.away_score || ' (' || home_team_name || ')';

  ELSIF COALESCE(OLD.status, '') <> 'live' AND NEW.status = 'live' THEN
    notification_type := 'MATCH_START';
    notification_title := '⚽ Maç Başladı!';
    notification_message := home_team_name || ' - ' || away_team_name || ' maçı an itibariyle başladı.';

  ELSE
    RETURN NEW;
  END IF;

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
$notif$ LANGUAGE plpgsql SECURITY DEFINER;
