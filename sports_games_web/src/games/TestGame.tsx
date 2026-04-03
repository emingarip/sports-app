import React, { useEffect, useState, useRef } from 'react';
import { supabase } from '../lib/supabase';
import { postMessageToHost } from '../lib/bridge';
import { Trophy, Activity, Users } from 'lucide-react';

interface TestGameProps {
  roomId: string;
}

const TestGame: React.FC<TestGameProps> = ({ roomId }) => {
  const [score, setScore] = useState(0);
  const [onlineUsers, setOnlineUsers] = useState(0);
  const [isFinished, setIsFinished] = useState(false);
  const [timeLeft, setTimeLeft] = useState(60); // 1 minute test duration
  
  const channelRef = useRef<any>(null);

  useEffect(() => {
    // 1. Join the Realtime Room for this specific game
    const channel = supabase.channel(`game:test:${roomId}`, {
      config: {
        broadcast: { ack: false },
        presence: { key: '' },
      },
    });
    
    channelRef.current = channel;

    channel
      .on('broadcast', { event: 'button_clicked' }, (payload) => {
        // When someone else clicks, we increment the score
        setScore((prev) => prev + (payload.payload.points || 1));
      })
      .on('presence', { event: 'sync' }, () => {
        const state = channel.presenceState();
        setOnlineUsers(Object.keys(state).length);
      })
      .subscribe(async (status) => {
        if (status === 'SUBSCRIBED') {
          // Track our own presence
          await channel.track({ online_at: new Date().toISOString() });
        }
      });

    // 2. Simple Global Timer 
    const timerId = setInterval(() => {
      setTimeLeft((prev) => {
        if (prev <= 1) {
          clearInterval(timerId);
          setIsFinished(true);
          return 0;
        }
        return prev - 1;
      });
    }, 1000);

    return () => {
      clearInterval(timerId);
      supabase.removeChannel(channel);
    };
  }, [roomId]);

  // Tell Flutter we are done!
  useEffect(() => {
    if (isFinished) {
      // Small delay to let user see "Oyun Bitti"
      setTimeout(() => {
        if (window.parent) {
           // Send message to WebView bridge in Flutter
           try {
             const msg = JSON.stringify({ 
               type: 'GAME_OVER',
               score: score,
               gameId: 'test_game',
               roomId: roomId
             });

             postMessageToHost(msg);
           } catch(e) {
             console.error("Flutter bridge error", e);
           }
        }
      }, 3000);
    }
  }, [isFinished, score, roomId]);

  const handleScoreClick = () => {
    if (isFinished) return;
    
    // Optimistic UI update
    setScore((prev) => prev + 1);

    // Broadcast click to others
    channelRef.current?.send({
      type: 'broadcast',
      event: 'button_clicked',
      payload: { points: 1 },
    });
  };

  return (
    <div className="flex flex-col items-center justify-center min-h-screen p-4 bg-gradient-to-br from-indigo-950 to-neutral-900 border-8 border-transparent overflow-hidden">
      
      {/* Header Stats */}
      <div className="absolute top-6 left-0 right-0 px-6 flex justify-between w-full">
        <div className="flex items-center space-x-2 bg-neutral-800/80 backdrop-blur pb-1 pt-1 px-3 rounded-full border border-neutral-700">
           <Activity className="w-4 h-4 text-green-400 animate-pulse" />
           <span className="font-mono text-xs text-neutral-300">Room: {roomId}</span>
        </div>
        <div className="flex items-center space-x-2 bg-neutral-800/80 backdrop-blur pb-1 pt-1 px-3 rounded-full border border-neutral-700">
           <Users className="w-4 h-4 text-blue-400" />
           <span className="font-bold text-sm text-neutral-200">{onlineUsers}</span>
        </div>
      </div>

      <div className="w-full max-w-sm flex flex-col items-center">
        {/* Timer */}
        <h2 className={`text-6xl font-black tracking-tighter mb-8 font-mono shadow-sm
          ${timeLeft <= 10 ? 'text-red-500 animate-pulse' : 'text-neutral-200'}`}>
          00:{timeLeft.toString().padStart(2, '0')}
        </h2>

        {/* The Action Button */}
        <button 
          onClick={handleScoreClick}
          disabled={isFinished}
          className={`relative group flex items-center justify-center w-64 h-64 rounded-full shadow-2xl transition-all duration-100 ease-out active:scale-95 active:shadow-inner
          ${isFinished 
             ? 'bg-neutral-800 cursor-not-allowed grayscale' 
             : 'bg-gradient-to-tr from-rose-600 via-rose-500 to-orange-500 hover:brightness-110 shadow-rose-500/50'
          }`}
        >
          {/* Inner ring for depth */}
          <div className="absolute inset-2 rounded-full border border-white/20"></div>
          {/* Score display inside button */}
          <div className="flex flex-col items-center pointer-events-none">
            <span className="text-8xl font-black tracking-tighter text-white drop-shadow-md">{score}</span>
            <span className="text-sm font-bold tracking-widest text-rose-200 uppercase mt-2">Team Score</span>
          </div>
        </button>

        {isFinished && (
           <div className="mt-12 flex flex-col items-center animate-bounce">
             <Trophy className="w-12 h-12 text-yellow-400 mb-2 drop-shadow-lg" />
             <p className="text-xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-yellow-400 to-orange-400">
               ETKİNLİK SONLANDI!
             </p>
             <p className="text-sm text-neutral-400 mt-2">Ödül hesaplanıyor...</p>
           </div>
        )}
      </div>

    </div>
  );
};

export default TestGame;
