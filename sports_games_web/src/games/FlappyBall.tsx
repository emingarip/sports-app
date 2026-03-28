import React, { useEffect, useRef, useState } from 'react';
import { supabase } from '../lib/supabase';

declare global {
  interface Window { MiniGameBridge?: { postMessage: (message: string) => void; }; }
}

interface FlappyBallProps { roomId: string; gameId: string; }

export default function FlappyBall({ roomId, gameId }: FlappyBallProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const requestRef = useRef<number | undefined>(undefined);
  
  const [score, setScore] = useState(0);
  const scoreRef = useRef(0);
  useEffect(() => { scoreRef.current = score; }, [score]);
  
  const [isGameOver, setIsGameOver] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [countdown, setCountdown] = useState(3);
  const [overallTimeLeft, setOverallTimeLeft] = useState(120);
  const [isTimeUp, setIsTimeUp] = useState(false);
  const lastSavedScoreRef = useRef(0);
  const [topScores, setTopScores] = useState<any[]>([]);
  const [myHighScore, setMyHighScore] = useState(0);
  const [gameKey, setGameKey] = useState(0);

  const screenWidth = typeof window !== 'undefined' ? window.innerWidth : 300;
  const screenHeight = typeof window !== 'undefined' ? window.innerHeight : 500;

  // Game specific state
  const ball = useRef({
    x: 100,
    y: screenHeight / 2,
    radius: 15,
    dy: 0,
    gravity: 0.25,
    bounce: -6,
  });

  const pipes = useRef<Array<{ x: number, width: number, topHeight: number, bottomHeight: number, passed: boolean }>>([]);
  const gap = 140; // Gap between top and bottom pipe

  useEffect(() => {
    if (!gameId) return;
    const fetchLeaderboard = async () => {
      const { data } = await supabase.from('mini_game_logs').select('id, user_id, score, users(username)').eq('game_id', gameId).order('score', { ascending: false }).limit(3);
      if (data) setTopScores(data.map((d: any) => ({ id: d.id, score: d.score, username: d.users?.username || 'Anonim' })));
      const { data: authData } = await supabase.auth.getUser();
      if (authData?.user) {
         const { data: myData } = await supabase.from('mini_game_logs').select('score').eq('game_id', gameId).eq('user_id', authData.user.id).maybeSingle();
         if (myData) setMyHighScore(myData.score);
      }
    };
    fetchLeaderboard();
    const channel = supabase.channel(`public:mini_game_logs:game_id=eq.${gameId}`).on('postgres_changes', { event: '*', schema: 'public', table: 'mini_game_logs', filter: `game_id=eq.${gameId}` }, fetchLeaderboard).subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [gameId]);

  useEffect(() => {
    let count = 3;
    const interval = setInterval(() => {
      count -= 1;
      if (count <= 0) { clearInterval(interval); setCountdown(0); } else { setCountdown(count); }
    }, 1000);
    return () => clearInterval(interval);
  }, [gameKey]);

  useEffect(() => {
    if (!gameId) return;
    let duration = 120; let startTime = Date.now();
    const parts = gameId.split('_');
    if (parts.length >= 4) {
      if (!isNaN(parseInt(parts[2], 10))) startTime = parseInt(parts[2], 10);
      if (!isNaN(parseInt(parts[3], 10))) duration = parseInt(parts[3], 10);
    }
    const calc = () => Math.max(0, duration - Math.floor((Date.now() - startTime) / 1000));
    setOverallTimeLeft(calc());
    if (calc() <= 0) setIsTimeUp(true);
    const globalTimer = setInterval(() => {
      const t = calc(); setOverallTimeLeft(t); if (t <= 0) { clearInterval(globalTimer); setIsTimeUp(true); }
    }, 1000);
    return () => clearInterval(globalTimer);
  }, [gameId]);

  useEffect(() => { if (isTimeUp && !isGameOver) handleGameOver(true); }, [isTimeUp]);

  useEffect(() => {
    if (isGameOver || isTimeUp || countdown > 0) return;
    const throttleTimer = setInterval(() => {
      if (scoreRef.current > lastSavedScoreRef.current) {
        lastSavedScoreRef.current = scoreRef.current;
        autoSaveScore(scoreRef.current);
      }
    }, 3000);
    return () => clearInterval(throttleTimer);
  }, [isGameOver, isTimeUp, countdown]);

  useEffect(() => {
    if (countdown > 0 || isGameOver || isTimeUp) return;
    const canvas = canvasRef.current; if (!canvas) return;
    const ctx = canvas.getContext('2d'); if (!ctx) return;

    let frames = 0;
    const pipeSpeed = 3;

    const render = () => {
      ctx.clearRect(0, 0, screenWidth, screenHeight);

      // Background moving lines
      ctx.strokeStyle = 'rgba(255,255,255,0.05)';
      ctx.lineWidth = 1;
      for (let i = 0; i < screenWidth; i += 40) {
         ctx.beginPath(); ctx.moveTo(i - (frames % 40), 0); ctx.lineTo(i - (frames % 40), screenHeight); ctx.stroke();
      }

      // Update ball
      ball.current.dy += ball.current.gravity;
      ball.current.y += ball.current.dy;

      // Draw ball
      ctx.beginPath(); ctx.arc(ball.current.x, ball.current.y, ball.current.radius, 0, Math.PI * 2);
      ctx.fillStyle = 'white'; ctx.fill();
      ctx.lineWidth = 2; ctx.strokeStyle = '#333'; ctx.stroke();
      // Soccer pattern
      ctx.fillStyle = '#222'; ctx.beginPath();
      const rAngle = frames * 0.05;
      for (let i = 0; i < 5; i++) {
        ctx.lineTo(ball.current.x + Math.cos((18 + i * 72) * Math.PI / 180 + rAngle) * (ball.current.radius * 0.4), ball.current.y - Math.sin((18 + i * 72) * Math.PI / 180 + rAngle) * (ball.current.radius * 0.4));
      }
      ctx.closePath(); ctx.fill();

      // Pipes
      if (frames % 100 === 0) {
         const topHeight = Math.random() * (screenHeight - gap - 100) + 50;
         pipes.current.push({ x: screenWidth, width: 50, topHeight, bottomHeight: screenHeight - gap - topHeight, passed: false });
      }

      for (let i = pipes.current.length - 1; i >= 0; i--) {
         const p = pipes.current[i];
         p.x -= pipeSpeed;

         // Draw top pipe (Red Card)
         ctx.fillStyle = '#D92D20'; ctx.fillRect(p.x, 0, p.width, p.topHeight);
         ctx.strokeStyle = '#912018'; ctx.strokeRect(p.x, 0, p.width, p.topHeight);

         // Draw bottom pipe (Yellow Card)
         ctx.fillStyle = '#FDB022'; ctx.fillRect(p.x, screenHeight - p.bottomHeight, p.width, p.bottomHeight);
         ctx.strokeStyle = '#B54708'; ctx.strokeRect(p.x, screenHeight - p.bottomHeight, p.width, p.bottomHeight);

         // Collision detection
         if (ball.current.x + ball.current.radius > p.x && ball.current.x - ball.current.radius < p.x + p.width) {
            if (ball.current.y - ball.current.radius < p.topHeight || ball.current.y + ball.current.radius > screenHeight - p.bottomHeight) {
               handleGameOver(false); return;
            }
         }

         // Score
         if (!p.passed && ball.current.x > p.x + p.width) {
            p.passed = true;
            setScore(s => s + 1);
         }

         if (p.x + p.width < 0) { pipes.current.splice(i, 1); }
      }

      // Ground collision
      if (ball.current.y + ball.current.radius > screenHeight || ball.current.y - ball.current.radius < 0) {
         handleGameOver(false); return;
      }

      frames++;
      requestRef.current = requestAnimationFrame(render);
    };

    requestRef.current = requestAnimationFrame(render);
    return () => { if (requestRef.current) cancelAnimationFrame(requestRef.current); };
  }, [countdown, isGameOver, isTimeUp, screenWidth, screenHeight]);

  const autoSaveScore = async (finalScore: number) => {
    if (finalScore > myHighScore || myHighScore === 0) {
       if (finalScore > myHighScore) setMyHighScore(finalScore);
       try { await supabase.functions.invoke('process-mini-game', { body: { gameId, roomId, score: finalScore } }); } catch (err) {}
    }
  };

  const handleGameOver = async (_fromTimeout = false) => {
    setIsGameOver(true);
    if (requestRef.current) cancelAnimationFrame(requestRef.current);
    await autoSaveScore(scoreRef.current);
  };

  const playAgain = () => {
    setScore(0); lastSavedScoreRef.current = 0; setIsGameOver(false); setCountdown(3); setGameKey(k => k + 1);
    ball.current = { x: 100, y: screenHeight / 2, radius: 15, dy: 0, gravity: 0.25, bounce: -6 };
    pipes.current = [];
  };

  const exitGame = () => {
    setIsSubmitting(true);
    const payload = JSON.stringify({ type: 'GAME_OVER', score: Math.max(score, myHighScore), roomId, gameId });
    if (window.MiniGameBridge) window.MiniGameBridge.postMessage(payload);
    window.parent.postMessage(payload, '*');
  };

  const handleTap = (e: React.TouchEvent | React.MouseEvent) => {
    if (countdown > 0 || isGameOver || isTimeUp) return;
    ball.current.dy = ball.current.bounce;
  };

  const min = Math.floor(overallTimeLeft / 60);
  const sec = overallTimeLeft % 60;

  return (
    <div className="w-full h-full relative overflow-hidden bg-gradient-to-b from-sky-400 to-sky-200 select-none touch-none font-sans" onMouseDown={handleTap} onTouchStart={handleTap}>
      <div className="absolute top-4 left-4 right-4 z-10 flex justify-between items-start pointer-events-none">
        <div className="bg-black/40 backdrop-blur-sm rounded-xl p-3 border border-white/20 shadow-xl min-w-[140px]">
          <h3 className="text-white/80 text-xs font-bold uppercase tracking-wider mb-2 border-b border-white/10 pb-1">Canlı Liderlik</h3>
          {topScores.length === 0 ? <p className="text-white/50 text-xs">Henüz skor yok</p> : (
             <div className="space-y-1">
               {topScores.map((ts, idx) => (
                 <div key={ts.id} className="flex justify-between items-center text-sm">
                   <span className={`font-medium ${idx === 0 ? 'text-yellow-400' : idx === 1 ? 'text-gray-300' : idx === 2 ? 'text-orange-300' : 'text-white'}`}>{idx + 1}. {ts.username.slice(0, 10)}</span>
                   <span className="font-bold text-white ml-3">{ts.score}</span>
                 </div>
               ))}
             </div>
          )}
        </div>
        <div className="flex flex-col items-end gap-2">
          <div className="bg-black/50 backdrop-blur-sm rounded-full px-4 py-2 text-white font-bold tabular-nums border border-white/20 shadow-xl flex items-center gap-2">
            <span className="text-red-400 text-sm">Süre: </span> 
            <span className={`text-xl ${overallTimeLeft <= 10 ? 'text-red-500 animate-pulse' : 'text-white'}`}>{`${min}:${sec < 10 ? '0' : ''}${sec}`}</span>
          </div>
          <div className="bg-black/40 backdrop-blur-sm rounded-full px-4 py-2 text-white font-bold tabular-nums border border-white/20 shadow-xl">
            Geçilen: <span className="text-2xl text-yellow-400">{score}</span>
          </div>
        </div>
      </div>

      {countdown > 0 && !isTimeUp && (
        <div className="absolute inset-0 z-20 flex flex-col items-center justify-center bg-black/60 backdrop-blur-sm pointer-events-none">
          <div className="animate-bounce text-8xl font-black text-white drop-shadow-[0_4px_20px_rgba(255,255,255,0.8)]">{countdown}</div>
          <div className="text-white text-xl mt-4 font-semibold opacity-90">Zıplamak İçin Dokun!</div>
        </div>
      )}

      <canvas ref={canvasRef} width={screenWidth} height={screenHeight} className="block" />

      {isGameOver && (
        <div className="absolute inset-0 z-50 flex flex-col items-center justify-center bg-black/80 backdrop-blur-md px-6">
          <h2 className="text-4xl font-black text-red-500 mb-2 uppercase tracking-widest drop-shadow-[0_2px_10px_rgba(239,68,68,0.5)]">
             {isTimeUp ? 'Süre Doldu!' : 'Çarptın!'}
          </h2>
          <div className="bg-white/10 rounded-2xl p-6 border border-white/20 w-full max-w-sm mb-8 text-center">
            <p className="text-white text-sm opacity-80 uppercase tracking-widest mb-1">Bu Eldeki Skor</p>
            <p className="font-bold text-yellow-400 text-5xl tabular-nums drop-shadow-lg mb-4">{score}</p>
            <div className="w-full h-px bg-gradient-to-r from-transparent via-white/20 to-transparent my-4"></div>
            <p className="text-white/60 text-sm">En Yüksek</p>
            <p className="font-bold text-white text-2xl tabular-nums">{Math.max(score, myHighScore)}</p>
          </div>
          {!isTimeUp && (
            <button onClick={(e) => { e.stopPropagation(); playAgain(); }} className="w-full max-w-sm mb-4 py-4 bg-gradient-to-r from-blue-500 to-indigo-600 font-bold rounded-2xl shadow-[0_0_20px_rgba(59,130,246,0.4)] text-lg text-white">🔄 Tekrar Oyna</button>
          )}
          <button onClick={() => exitGame()} className="w-full max-w-sm py-4 bg-white/10 hover:bg-white/20 text-white font-bold rounded-2xl border border-white/20 text-lg">🚪 Çıkış ve Maça Dön</button>
        </div>
      )}
    </div>
  );
}
