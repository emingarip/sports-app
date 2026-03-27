import React, { useEffect, useState } from 'react';
import { supabase } from './lib/supabase';
import KeepyUppy from './games/KeepyUppy';

function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [sessionToken, setSessionToken] = useState<string | null>(null);
  const [roomId, setRoomId] = useState<string>('');
  const [gameId, setGameId] = useState<string>('');

  useEffect(() => {
    const urlParams = new URLSearchParams(window.location.search);
    const tokenFromUrl = urlParams.get('token');
    const refreshFromUrl = urlParams.get('refresh');
    const roomIdFromUrl = urlParams.get('roomId');
    const gameIdFromUrl = urlParams.get('gameId');

    const authenticate = async (token: string, refresh: string, room: string, game: string) => {
      try {
        // Supabase v2 throws AuthSessionMissingError if refresh_token is precisely empty string ''
        // If it's passed as the same as access_token, it creates an ephemeral session that is valid
        // until the access token expires.
        const { data, error } = await supabase.auth.setSession({
           access_token: token,
           refresh_token: refresh || token, 
        });
        
        if (!error && data.session) {
          setIsAuthenticated(true);
          setSessionToken(token);
          setRoomId(room);
          setGameId(game);
        } else {
           console.error("Auth error:", error);
        }
      } catch (err) {
        console.error("Auth Exception:", err);
      }
    };

    if (tokenFromUrl && roomIdFromUrl) {
      authenticate(tokenFromUrl, refreshFromUrl || '', roomIdFromUrl, gameIdFromUrl || '');
    } else {
      // DEVELOPMENT OVERRIDE: 
      if (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1') {
        if (urlParams.get('dev') === 'true') {
          setIsAuthenticated(true);
          setRoomId('test_room_123');
          setGameId('test_game_123');
        }
      }
    }
  }, []);

  if (!isAuthenticated) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-neutral-900 text-white font-sans">
        <div className="text-center space-y-4">
          <div className="w-12 h-12 border-4 border-green-500 border-t-transparent rounded-full animate-spin mx-auto"></div>
          <p className="text-neutral-400 font-medium">Spor arenasına bağlanıyor...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-neutral-900 text-white font-sans overflow-hidden">
       {/* Future Factory Pattern can go here: render game based on URL params */}
      <KeepyUppy roomId={roomId || 'default_room'} gameId={gameId || 'default_game'} />
    </div>
  );
}

export default App;
