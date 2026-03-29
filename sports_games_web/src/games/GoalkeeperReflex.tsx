import React, { useEffect, useRef, useState } from 'react';
import { supabase } from '../lib/supabase';

declare global {
  interface Window { MiniGameBridge?: { postMessage: (message: string) => void; }; }
}

interface GoalkeeperReflexProps { roomId: string; gameId: string; }

export default function GoalkeeperReflex({ roomId, gameId }: GoalkeeperReflexProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const requestRef = useRef<number | undefined>(undefined);
  
  const [score, setScore] = useState(0);
  const scoreRef = useRef(0);
  useEffect(() => { scoreRef.current = score; }, [score]);
  
  const [isGameOver, setIsGameOver] = useState(false);
  const [, setIsSubmitting] = useState(false);
  const [countdown, setCountdown] = useState(3);
  const [overallTimeLeft, setOverallTimeLeft] = useState(120);
  const [isTimeUp, setIsTimeUp] = useState(false);
  const lastSavedScoreRef = useRef(0);
  const [topScores, setTopScores] = useState<any[]>([]);
  const [myHighScore, setMyHighScore] = useState(0);


  const screenWidth = typeof window !== 'undefined' ? window.innerWidth : 300;
  const screenHeight = typeof window !== 'undefined' ? window.innerHeight : 500;

  // Game specific state
  const balls = useRef<Array<{ id: number; x: number; y: number; size: number; max_size: number; speed: number }>>([]);
  const lastSpawn = useRef(0);
  const spawnRate = useRef(1500); // gets faster
  const idCounter = useRef(0);

  useEffect(() => {
    if (!gameId) return;
    const fetchLeaderboard = async () => {
      const { data } = await supabase.from('mini_game_logs').select('id, user_id, score, users(username)').eq('game_id', gameId).order('score', { ascending: false }).limit(3);
      if (data) {
        // Resolve bot usernames for 'Anonim' entries
        const anonIds = data.filter((d: any) => !d.users?.username).map((d: any) => d.user_id);
        let botLogos: Record<string, string> = {};
        if (anonIds.length > 0) {
            const { data: bots } = await supabase.from('bot_personas').select('user_id, team').in('user_id', anonIds);
            if (bots) {
                bots.forEach((b: any) => { botLogos[b.user_id] = (b.team || 'Anonim') + ' Bot'; });
            }
        }

        setTopScores(data.map((d: any) => ({
          id: d.id,
          score: d.score,
          username: d.users?.username || botLogos[d.user_id] || 'Anonim'
        })));
      }
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
  }, []);

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
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const render = (time: number) => {
      ctx.clearRect(0, 0, screenWidth, screenHeight);

      // Draw background goal net
      ctx.strokeStyle = 'rgba(255,255,255,0.1)';
      ctx.lineWidth = 1;
      for (let i = 0; i < screenWidth; i += 30) { ctx.beginPath(); ctx.moveTo(i, 0); ctx.lineTo(i, screenHeight); ctx.stroke(); }
      for (let i = 0; i < screenHeight; i += 30) { ctx.beginPath(); ctx.moveTo(0, i); ctx.lineTo(screenWidth, i); ctx.stroke(); }

      // Spawn new balls
      if (time - lastSpawn.current > spawnRate.current) {
         lastSpawn.current = time;
         balls.current.push({
           id: idCounter.current++,
           x: Math.random() * (screenWidth - 100) + 50,
           y: Math.random() * (screenHeight - 200) + 100,
           size: 5,
           max_size: 60,
           speed: 0.5 + Math.random() * 0.5
         });
         // Increase difficulty
         spawnRate.current = Math.max(400, spawnRate.current - 20);
      }

      // Update and draw balls
      for (let i = balls.current.length - 1; i >= 0; i--) {
        const b = balls.current[i];
        b.size += b.speed;
        
        ctx.beginPath();
        ctx.arc(b.x, b.y, b.size, 0, Math.PI * 2);
        ctx.fillStyle = b.size > b.max_size - 10 ? 'rgba(255,100,100,0.9)' : 'white';
        ctx.fill();
        ctx.lineWidth = 2;
        ctx.strokeStyle = '#333';
        ctx.stroke();

        // Soccer pattern
        ctx.fillStyle = '#222';
        ctx.beginPath();
        for (let j = 0; j < 5; j++) {
          ctx.lineTo(b.x + Math.cos((18 + j * 72) * Math.PI / 180) * (b.size * 0.4), b.y - Math.sin((18 + j * 72) * Math.PI / 180) * (b.size * 0.4));
        }
        ctx.closePath();
        ctx.fill();

        if (b.size >= b.max_size) {
           // Conceded a goal!
           // Deduct score or end game. Let's deduct score by 1 for arcade feel.
           setScore(s => Math.max(0, s - 1));
           balls.current.splice(i, 1);
           
           // Screen flash red
           ctx.fillStyle = 'rgba(255,0,0,0.3)';
           ctx.fillRect(0,0,screenWidth, screenHeight);
        }
      }

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

  const exitGame = () => {
    setIsSubmitting(true);
    const payload = JSON.stringify({ type: 'GAME_OVER', score: Math.max(score, myHighScore), roomId, gameId });
    if (window.MiniGameBridge) window.MiniGameBridge.postMessage(payload);
    window.parent.postMessage(payload, '*');
  };

  const handleTap = (e: React.TouchEvent | React.MouseEvent) => {
    if (countdown > 0 || isGameOver || isTimeUp) return;
    let clientX, clientY;
    if ('touches' in e) { clientX = e.touches[0].clientX; clientY = e.touches[0].clientY; }
    else { clientX = (e as React.MouseEvent).clientX; clientY = (e as React.MouseEvent).clientY; }
    
    // Check if tapped a ball (prioritize largest/closest balls)
    let tappedIndex = -1;
    let maxFoundSize = -1;

    for (let i = 0; i < balls.current.length; i++) {
       const b = balls.current[i];
       const dist = Math.sqrt(Math.pow(clientX - b.x, 2) + Math.pow(clientY - b.y, 2));
       if (dist < b.size * 1.5) { // slightly generous hitbox
          if (b.size > maxFoundSize) {
             maxFoundSize = b.size;
             tappedIndex = i;
          }
       }
    }

    if (tappedIndex !== -1) {
       balls.current.splice(tappedIndex, 1);
       setScore(s => s + 1);
    }
  };

  const min = Math.floor(overallTimeLeft / 60);
  const sec = overallTimeLeft % 60;

  return (
    <div className="w-full h-full relative overflow-hidden bg-gradient-to-b from-blue-800 to-indigo-900 select-none touch-none font-sans" onMouseDown={handleTap} onTouchStart={handleTap}>
      <div className="absolute top-4 right-4 z-10 flex flex-col items-end gap-2 pointer-events-none">
        <div className="bg-black/40 backdrop-blur-sm rounded-xl p-3 border border-white/20 shadow-xl min-w-[140px] order-last">
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
            Kurtarış: <span className="text-2xl text-yellow-400">{score}</span>
          </div>
        </div>
      </div>

      {countdown > 0 && !isTimeUp && (
        <div className="absolute inset-0 z-20 flex flex-col items-center justify-center bg-black/60 backdrop-blur-sm pointer-events-none">
          <div className="animate-bounce text-8xl font-black text-white drop-shadow-[0_4px_20px_rgba(255,255,255,0.8)]">{countdown}</div>
          <div className="text-white text-xl mt-4 font-semibold opacity-90">Gelen Şutlara Dokun!</div>
        </div>
      )}

      <canvas ref={canvasRef} width={screenWidth} height={screenHeight} className="block" />

      {isGameOver && (
        <div className="absolute inset-0 z-50 flex flex-col items-center justify-center bg-black/80 backdrop-blur-md px-6">
          <h2 className="text-4xl font-black text-red-500 mb-2 uppercase tracking-widest drop-shadow-[0_2px_10px_rgba(239,68,68,0.5)]">Süre Doldu!</h2>
          <div className="bg-white/10 rounded-2xl p-6 border border-white/20 w-full max-w-sm mb-8 text-center">
            <p className="text-white text-sm opacity-80 uppercase tracking-widest mb-1">Bu Kurtarış</p>
            <p className="font-bold text-yellow-400 text-5xl tabular-nums drop-shadow-lg mb-4">{score}</p>
            <div className="w-full h-px bg-gradient-to-r from-transparent via-white/20 to-transparent my-4"></div>
            <p className="text-white/60 text-sm">En Yüksek</p>
            <p className="font-bold text-white text-2xl tabular-nums">{Math.max(score, myHighScore)}</p>
          </div>
          <button onClick={() => exitGame()} className="w-full max-w-sm py-4 bg-white/10 hover:bg-white/20 text-white font-bold rounded-2xl transition-all active:scale-95 text-lg border border-white/20">🚪 Çıkış ve Maça Dön</button>
        </div>
      )}
    </div>
  );
}
