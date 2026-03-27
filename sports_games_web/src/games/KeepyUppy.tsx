import React, { useEffect, useRef, useState } from 'react';
import { supabase } from '../lib/supabase';

// Declaration for the injected Flutter bridge
declare global {
  interface Window {
    MiniGameBridge?: {
      postMessage: (message: string) => void;
    };
  }
}

interface KeepyUppyProps {
  roomId: string;
  gameId: string;
}

export default function KeepyUppy({ roomId, gameId }: KeepyUppyProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const requestRef = useRef<number | undefined>(undefined);
  
  const [score, setScore] = useState(0);
  const scoreRef = useRef(0);
  useEffect(() => { scoreRef.current = score; }, [score]);
  
  const [isGameOver, setIsGameOver] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [countdown, setCountdown] = useState(3);
  
  const [overallTimeLeft, setOverallTimeLeft] = useState(120); // 2 minutes
  const [isTimeUp, setIsTimeUp] = useState(false);
  const [topScores, setTopScores] = useState<Array<{id: string, username: string, score: number}>>([]);
  const [myHighScore, setMyHighScore] = useState(0);
  const [gameKey, setGameKey] = useState(0);

  // Ball physics state
  const ball = useRef({
    x: typeof window !== 'undefined' ? window.innerWidth / 2 : 150,
    y: 100,
    radius: 30,
    dx: 0,
    dy: 0,
    gravity: 0.5,
    bounce: -10,
    rotation: 0,
    rotationSpeed: 0,
  });

  const screenWidth = typeof window !== 'undefined' ? window.innerWidth : 300;
  const screenHeight = typeof window !== 'undefined' ? window.innerHeight : 500;

  useEffect(() => {
    if (!gameId) return;

    const fetchLeaderboard = async () => {
      const { data } = await supabase
        .from('mini_game_logs')
        .select('id, user_id, score, users(username)')
        .eq('game_id', gameId)
        .order('score', { ascending: false })
        .limit(3);
        
      if (data) {
        setTopScores(data.map((d: any) => ({
          id: d.id,
          score: d.score,
          username: d.users?.username || 'Anonim'
        })));
      }

      const { data: authData } = await supabase.auth.getUser();
      if (authData?.user) {
         const { data: myData } = await supabase
           .from('mini_game_logs')
           .select('score')
           .eq('game_id', gameId)
           .eq('user_id', authData.user.id)
           .maybeSingle();
         if (myData) setMyHighScore(myData.score);
      }
    };

    fetchLeaderboard();

    const channel = supabase.channel(`public:mini_game_logs:game_id=eq.${gameId}`)
       .on('postgres_changes', { event: '*', schema: 'public', table: 'mini_game_logs', filter: `game_id=eq.${gameId}` }, () => {
         fetchLeaderboard();
       })
       .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [gameId]);


  useEffect(() => {
    ball.current.x = screenWidth / 2;
    // Setup countdown
    let count = 3;
    const interval = setInterval(() => {
      count -= 1;
      if (count <= 0) {
        clearInterval(interval);
        setCountdown(0);
      } else {
        setCountdown(count);
      }
    }, 1000);
    
    return () => clearInterval(interval);
  }, [screenWidth, gameKey]);


  // Game Timer setup
  useEffect(() => {
    if (countdown === 0 && overallTimeLeft > 0 && !isTimeUp) {
      const timer = setInterval(() => {
        setOverallTimeLeft((prev) => {
          if (prev <= 1) {
            clearInterval(timer);
            setIsTimeUp(true);
            handleGameOver(true);
            return 0;
          }
          return prev - 1;
        });
      }, 1000);
      return () => clearInterval(timer);
    }
  }, [countdown, overallTimeLeft, isTimeUp]);


  useEffect(() => {
    // Only start game loop if countdown is 0 and game is not over
    if (countdown > 0 || isGameOver || isTimeUp) return;

    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const render = () => {
      // Clear canvas
      ctx.clearRect(0, 0, screenWidth, screenHeight);

      // Update physics
      ball.current.dy += ball.current.gravity;
      ball.current.y += ball.current.dy;
      ball.current.x += ball.current.dx;
      ball.current.rotation += ball.current.rotationSpeed;

      // Wall collisions (bounce off left and right walls)
      if (ball.current.x + ball.current.radius > screenWidth) {
        ball.current.x = screenWidth - ball.current.radius;
        ball.current.dx *= -0.8;
        ball.current.rotationSpeed *= -0.5;
      } else if (ball.current.x - ball.current.radius < 0) {
        ball.current.x = ball.current.radius;
        ball.current.dx *= -0.8;
        ball.current.rotationSpeed *= -0.5;
      }

      // Draw shadow
      ctx.beginPath();
      const shadowY = screenHeight - 20;
      const heightRatio = Math.max(0, 1 - (shadowY - ball.current.y) / screenHeight);
      ctx.ellipse(
        ball.current.x,
        shadowY,
        ball.current.radius * (0.5 + heightRatio * 0.5),
        ball.current.radius * 0.2 * (0.5 + heightRatio * 0.5),
        0, 0, Math.PI * 2
      );
      ctx.fillStyle = `rgba(0,0,0, ${0.3 * (1 - heightRatio)})`;
      ctx.fill();
      ctx.closePath();

      // Draw pentagon soccer ball
      ctx.save();
      ctx.translate(ball.current.x, ball.current.y);
      ctx.rotate(ball.current.rotation);
      
      // Soccer ball base
      ctx.beginPath();
      ctx.arc(0, 0, ball.current.radius, 0, Math.PI * 2);
      ctx.fillStyle = 'white';
      ctx.fill();
      ctx.lineWidth = 2;
      ctx.strokeStyle = '#333';
      ctx.stroke();
      ctx.closePath();

      // Draw simple soccer pattern (just one black pentagon in center for simplicity + lines)
      ctx.beginPath();
      for (let i = 0; i < 5; i++) {
        ctx.lineTo(
          Math.cos((18 + i * 72) * Math.PI / 180) * (ball.current.radius * 0.4),
          -Math.sin((18 + i * 72) * Math.PI / 180) * (ball.current.radius * 0.4)
        );
      }
      ctx.closePath();
      ctx.fillStyle = '#222';
      ctx.fill();

      // Draw lines from pentagon corners to edge
      for (let i = 0; i < 5; i++) {
        ctx.beginPath();
        const startX = Math.cos((18 + i * 72) * Math.PI / 180) * (ball.current.radius * 0.4);
        const startY = -Math.sin((18 + i * 72) * Math.PI / 180) * (ball.current.radius * 0.4);
        const endX = Math.cos((18 + i * 72) * Math.PI / 180) * ball.current.radius;
        const endY = -Math.sin((18 + i * 72) * Math.PI / 180) * ball.current.radius;
        
        ctx.moveTo(startX, startY);
        ctx.lineTo(endX, endY);
        ctx.strokeStyle = '#222';
        ctx.lineWidth = 1.5;
        ctx.stroke();
      }
      ctx.restore();

      // Check Game Over (Ball hits bottom)
      if (ball.current.y + ball.current.radius >= screenHeight) {
        handleGameOver(false);
        return;
      }

      requestRef.current = requestAnimationFrame(render);
    };

    requestRef.current = requestAnimationFrame(render);

    return () => {
      if (requestRef.current) cancelAnimationFrame(requestRef.current);
    };
  }, [countdown, isGameOver, isTimeUp, screenWidth, screenHeight]);

  const autoSaveScore = async (finalScore: number) => {
    // Only auto-save if it beats high score (to prevent unnecessary calls, though edge function handles it gracefully)
    // Actually, always save first time, or if higher.
    if (finalScore > myHighScore || myHighScore === 0) {
      if (finalScore > myHighScore) setMyHighScore(finalScore);
      try {
        await supabase.functions.invoke('process-mini-game', {
          body: { gameId, roomId, score: finalScore },
        });
      } catch (err) {
        console.error("Auto-save failed:", err);
      }
    }
  };

  const handleGameOver = async (_fromTimeout = false) => {
    setIsGameOver(true);
    if (requestRef.current) cancelAnimationFrame(requestRef.current);
    
    // Use the ref since this function might be triggered by timeout where state is stale
    const finalScore = scoreRef.current;
    await autoSaveScore(finalScore);
  };

  const playAgain = () => {
    setScore(0);
    setIsGameOver(false);
    setCountdown(3);
    setGameKey(k => k + 1);
    ball.current = {
      x: screenWidth / 2,
      y: 100,
      radius: 30,
      dx: 0,
      dy: 0,
      gravity: 0.5,
      bounce: -10,
      rotation: 0,
      rotationSpeed: 0,
    };
  };

  const exitGame = () => {
    setIsSubmitting(true);
    try {
      const payload = JSON.stringify({
        type: 'GAME_OVER',
        score: myHighScore, // Give flutter the knowledge of highest score achieved
        roomId: roomId,
        gameId: gameId,
      });
      if (window.MiniGameBridge) {
        window.MiniGameBridge.postMessage(payload);
      } else {
        window.parent.postMessage(payload, '*');
      }
    } catch (err) {
      console.error("Failed to exit:", err);
    }
  };

  const handleTap = (e: React.MouseEvent | React.TouchEvent) => {
    if (countdown > 0 || isGameOver || isTimeUp) return;
    
    let clientX, clientY;
    if ('touches' in e) {
      clientX = e.touches[0].clientX;
      clientY = e.touches[0].clientY;
    } else {
      clientX = (e as React.MouseEvent).clientX;
      clientY = (e as React.MouseEvent).clientY;
    }

    const dist = Math.sqrt(
      Math.pow(clientX - ball.current.x, 2) + 
      Math.pow(clientY - ball.current.y, 2)
    );

    if (dist < ball.current.radius * 3) {
      setScore(s => s + 1);
      
      const xOffset = clientX - ball.current.x;
      
      ball.current.dy = ball.current.bounce;
      ball.current.dx = -(xOffset * 0.15);
      ball.current.rotationSpeed = (xOffset * 0.01);
      
      ball.current.gravity += 0.005;
    }
  };

  const min = Math.floor(overallTimeLeft / 60);
  const sec = overallTimeLeft % 60;
  const timeString = `${min}:${sec < 10 ? '0' : ''}${sec}`;

  return (
    <div 
      className="w-full h-full relative overflow-hidden bg-gradient-to-b from-blue-400 to-green-600 select-none touch-none font-sans"
      onMouseDown={handleTap}
      onTouchStart={handleTap}
    >
      <div className="absolute inset-0 opacity-20 pointer-events-none flex flex-col justify-end">
        <div className="w-full h-1/2 bg-[repeating-linear-gradient(0deg,transparent,transparent_20px,rgba(255,255,255,0.1)_20px,rgba(255,255,255,0.1)_40px)]"></div>
      </div>

      <div className="absolute top-4 left-4 right-4 z-10 flex justify-between items-start pointer-events-none">
        
        {/* Realtime Leaderboard */}
        <div className="bg-black/40 backdrop-blur-sm rounded-xl p-3 border border-white/20 shadow-xl min-w-[140px]">
          <h3 className="text-white/80 text-xs font-bold uppercase tracking-wider mb-2 border-b border-white/10 pb-1">Canlı Liderlik</h3>
          {topScores.length === 0 ? (
            <p className="text-white/50 text-xs">Henüz skor yok</p>
          ) : (
            <div className="space-y-1">
              {topScores.map((ts, idx) => (
                <div key={ts.id} className="flex justify-between items-center text-sm">
                  <span className={`font-medium ${idx === 0 ? 'text-yellow-400' : idx === 1 ? 'text-gray-300' : idx === 2 ? 'text-orange-300' : 'text-white'}`}>
                    {idx + 1}. {ts.username.slice(0, 10)}
                  </span>
                  <span className="font-bold text-white tabular-nums ml-3">{ts.score}</span>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Current Score & Timer */}
        <div className="flex flex-col items-end gap-2">
          <div className="bg-black/50 backdrop-blur-sm rounded-full px-4 py-2 text-white font-bold tabular-nums border border-white/20 shadow-xl flex items-center gap-2">
            <span className="text-red-400 text-sm">Süre: </span> 
            <span className={`text-xl ${overallTimeLeft <= 10 ? 'text-red-500 animate-pulse' : 'text-white'}`}>{timeString}</span>
          </div>
          <div className="bg-black/40 backdrop-blur-sm rounded-full px-4 py-2 text-white font-bold tabular-nums border border-white/20 shadow-xl">
            Skor: <span className="text-2xl text-yellow-400">{score}</span>
          </div>
        </div>
      </div>

      {countdown > 0 && !isTimeUp && (
        <div className="absolute inset-0 z-20 flex flex-col items-center justify-center bg-black/60 backdrop-blur-sm pointer-events-none">
          <div className="animate-bounce text-8xl font-black text-white drop-shadow-[0_4px_20px_rgba(255,255,255,0.8)]">
            {countdown}
          </div>
          <div className="text-white text-xl mt-4 font-semibold opacity-90">
            Top yere düşmeden sektir!
          </div>
        </div>
      )}

      <canvas
        ref={canvasRef}
        width={screenWidth}
        height={screenHeight}
        className="block"
      />

      {isGameOver && (
        <div className="absolute inset-0 z-50 flex flex-col items-center justify-center bg-black/80 backdrop-blur-md px-6">
          <h2 className="text-4xl font-black text-red-500 mb-2 uppercase tracking-widest drop-shadow-[0_2px_10px_rgba(239,68,68,0.5)]">
            {isTimeUp ? 'Süre Doldu!' : 'Top Düştü!'}
          </h2>
          <div className="bg-white/10 rounded-2xl p-6 border border-white/20 w-full max-w-sm mb-8 text-center">
            <p className="text-white text-sm opacity-80 uppercase tracking-widest mb-1">Bu Eldeki Skor</p>
            <p className="font-bold text-yellow-400 text-5xl tabular-nums drop-shadow-lg mb-4">{score}</p>
            
            <div className="w-full h-px bg-gradient-to-r from-transparent via-white/20 to-transparent my-4"></div>
            
            <p className="text-white/60 text-sm">En Yüksek Skorun</p>
            <p className="font-bold text-white text-2xl tabular-nums">{Math.max(score, myHighScore)}</p>
          </div>

          {!isTimeUp && (
            <button
              onClick={(e) => { e.stopPropagation(); playAgain(); }}
              className="w-full max-w-sm mb-4 py-4 bg-gradient-to-r from-blue-500 to-indigo-600 hover:from-blue-400 hover:to-indigo-500 text-white font-bold rounded-2xl shadow-[0_0_20px_rgba(59,130,246,0.4)] transition-all transform active:scale-95 text-lg border border-white/20"
            >
              🔄 Tekrar Oyna
            </button>
          )}

          <button
            onClick={(e) => { e.stopPropagation(); exitGame(); }}
            disabled={isSubmitting}
            className="w-full max-w-sm py-4 bg-white/10 hover:bg-white/20 text-white font-bold rounded-2xl transition-all transform active:scale-95 text-lg disabled:opacity-50 disabled:cursor-not-allowed border border-white/20"
          >
            {isSubmitting ? 'Çıkılıyor...' : (isTimeUp ? 'Sonuçları Gör' : '🚪 Çıkış ve Maça Dön')}
          </button>
        </div>
      )}
    </div>
  );
}
