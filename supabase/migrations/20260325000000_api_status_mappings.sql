-- Dynamic API Status Mappings to replace hardcoded edge function logic
CREATE TABLE public.api_status_mappings (
    api_status_string TEXT PRIMARY KEY,
    app_status TEXT NOT NULL CHECK (app_status IN ('live', 'finished', 'pre_match')),
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Seed with official Highlightly API Mapping
INSERT INTO public.api_status_mappings (api_status_string, app_status, description) VALUES
('Not started', 'pre_match', 'Match has not been started yet.'),
('First half', 'live', 'Match is considered in play and is in the first half.'),
('Second half', 'live', 'Match is considered in play and is in the second half.'),
('Half time', 'live', 'Half time pause between first and second half.'),
('Extra time', 'live', 'Additional extra time is needed to decide the winner.'),
('Break time', 'live', 'Short pause between in play periods and extra time.'),
('Penalties', 'live', 'Penalty shootout to decide the winner of the match.'),
('Finished', 'finished', 'Match has been concluded.'),
('Finished after penalties', 'finished', 'Match has been concluded with the penalty shootout.'),
('Finished after extra time', 'finished', 'Match has been concluded in extra time.'),
('Postponed', 'finished', 'Event start time changed to future. Marked finished to hide from live.'),
('Suspended', 'live', 'Suspended but will resume. Kept live.'),
('Cancelled', 'finished', 'Game will not be played. Marked finished to hide.'),
('Awarded', 'finished', 'Game awarded (forfeit).'),
('Interrupted', 'live', 'Issue arose preventing game, but might resume.'),
('Abandoned', 'finished', 'Prematurely ended, cannot be completed.'),
('In progress', 'live', 'Match is considered in play but minimal coverage.'),
('Unknown', 'pre_match', 'Unknown match coverage or state.'),
('To be announced', 'pre_match', 'Start time TBA.');

-- Grant read access to the service role / authenticated users if needed
ALTER TABLE public.api_status_mappings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow public read access to mappings"
ON public.api_status_mappings
FOR SELECT
TO public, authenticated
USING (true);
