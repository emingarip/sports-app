import { useEffect, useState } from 'react';
import { supabase } from './lib/supabase';
import KeepyUppy from './games/KeepyUppy';
import PenaltyShootout from './games/PenaltyShootout';
import GoalkeeperReflex from './games/GoalkeeperReflex';
import FlappyBall from './games/FlappyBall';
import HeaderHero from './games/HeaderHero';
import GoalCelebrationRhythm from './games/GoalCelebrationRhythm';

function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [roomId, setRoomId] = useState<string>('');
  const [gameId, setGameId] = useState<string>('');
  const [gameType, setGameType] = useState<string>('play_keepy_uppy');

  useEffect(() => {
    const urlParams = new URLSearchParams(window.location.search);
    const tokenFromUrl = urlParams.get('token');
    const refreshFromUrl = urlParams.get('refresh');
    const roomIdFromUrl = urlParams.get('roomId');
    const gameIdFromUrl = urlParams.get('gameId');
    const gameTypeFromUrl = urlParams.get('gameType');
    
    if (gameTypeFromUrl) setGameType(gameTypeFromUrl);

    const authenticate = async (token: string, refresh: string, room: string, game: string) => {
      try {
        const { data, error } = await supabase.auth.setSession({
           access_token: token,
           refresh_token: refresh || token, 
        });
        
        if (!error && data.session) {
          setIsAuthenticated(true);
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

  const renderGame = () => {
    switch (gameType) {
      case 'penalty_shootout':
        return <PenaltyShootout roomId={roomId} gameId={gameId} />;
      case 'goalkeeper_reflex':
        return <GoalkeeperReflex roomId={roomId} gameId={gameId} />;
      case 'flappy_ball':
        return <FlappyBall roomId={roomId} gameId={gameId} />;
      case 'header_hero':
        return <HeaderHero roomId={roomId} gameId={gameId} />;
      case 'goal_celebration_rhythm':
        return <GoalCelebrationRhythm roomId={roomId} gameId={gameId} />;
      case 'play_keepy_uppy':
      default:
        return <KeepyUppy roomId={roomId} gameId={gameId} />;
    }
  };

  return (
    <div className="min-h-screen bg-neutral-900 text-white font-sans overflow-hidden">
       {renderGame()}
    </div>
  );
}

export default App;
