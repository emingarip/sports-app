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
        return <KeepyUppy roomId={roomId} gameId={gameId} />;
      default:
        return (
          <div className="flex flex-col items-center justify-center min-h-screen bg-neutral-900 text-white p-6 text-center">
            <div className="w-16 h-16 bg-red-500/20 text-red-500 rounded-full flex items-center justify-center mb-4">
              <svg xmlns="http://www.w3.org/2000/svg" className="w-8 h-8" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
              </svg>
            </div>
            <h2 className="text-xl font-bold mb-2">Oyun Bulunamadı</h2>
            <p className="text-neutral-400 max-w-sm">
              Başlatılmak istenen oyun "{gameType}" şu an bulunamadı veya uygulamanız eski bir sürümde kalmış olabilir. 
              Devam etmek için uygulamanızı yeniden başlatmayı veya daha sonra tekrar denemeyi unutmayın.
            </p>
          </div>
        );
    }
  };

  return (
    <div className="min-h-screen bg-neutral-900 text-white font-sans overflow-hidden">
       {renderGame()}
    </div>
  );
}

export default App;
