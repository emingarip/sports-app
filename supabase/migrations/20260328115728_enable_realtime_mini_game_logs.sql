-- Enable realtime for mini_game_logs so the "Canlı Liderlik" components can receive live score updates
ALTER PUBLICATION supabase_realtime ADD TABLE mini_game_logs;
