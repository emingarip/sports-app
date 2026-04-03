import React, { useEffect, useRef, useState } from 'react';
import { supabase } from '../lib/supabase';
import { ParticleSystem, ScreenShake, FloatingTextSystem, AudioSynthesizer, drawSoccerBall, DifficultyScaler } from '../lib/gameUtils';

declare global {
  interface Window { MiniGameBridge?: { postMessage: (message: string) => void; }; }
}

interface FlappyBallProps { readonly roomId: string; readonly gameId: string; }

interface Star { x: number; y: number; radius: number; collected: boolean; }
interface Pipe { x: number; width: number; topHeight: number; bottomHeight: number; passed: boolean; vy?: number; offset?: number; }
interface LeaderboardEntry { id: string; score: number; username: string; user_id?: string; }
interface BotPersona { user_id: string; team: string; }

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
  const [topScores, setTopScores] = useState<LeaderboardEntry[]>([]);
  const [myHighScore, setMyHighScore] = useState(0);
  const [gameKey, setGameKey] = useState(0);

  const screenWidth = globalThis.window === undefined ? 300 : globalThis.window.innerWidth;
  const screenHeight = globalThis.window === undefined ? 500 : globalThis.window.innerHeight;

  // Game specific state
  const ball = useRef({
    x: 100,
    y: screenHeight / 2,
    radius: 15,
    dy: 0,
    gravity: 0.25,
    bounce: -6,
  });

  const engineRef = useRef({
    particles: new ParticleSystem(),
    shake: new ScreenShake(),
    texts: new FloatingTextSystem(),
    audio: new AudioSynthesizer(),
  });
  const trailRef = useRef<{x: number, y: number}[]>([]);

  const difficulty = useRef(new DifficultyScaler(10));
  const stars = useRef<Star[]>([]);
  const pipes = useRef<Pipe[]>([]);
  const baseGap = 220; 

  useEffect(() => {
    if (!gameId) return;
    const fetchLeaderboard = async () => {
      const { data } = await supabase.from('mini_game_logs').select('id, user_id, score, users(username)').eq('game_id', gameId).order('score', { ascending: false }).limit(3);
      if (data) {
        const rawData = data as unknown as { id: string; user_id: string; score: number; users: { username: string } | { username: string }[] | null }[];
        const anonIds = rawData.filter(d => {
            const user = Array.isArray(d.users) ? d.users[0] : d.users;
            return !user?.username;
        }).map(d => d.user_id);
        
        const botLogos: Record<string, string> = {};
        if (anonIds.length > 0) {
            const { data: bots } = await supabase.from('bot_personas').select('user_id, team').in('user_id', anonIds);
            if (bots) {
                (bots as unknown as BotPersona[]).forEach((b) => { botLogos[b.user_id] = (b.team || 'Anonim') + ' Bot'; });
            }
        }

        setTopScores(rawData.map(d => {
            const user = Array.isArray(d.users) ? d.users[0] : d.users;
            return {
              id: d.id,
              user_id: d.user_id,
              score: d.score,
              username: user?.username || botLogos[d.user_id] || 'Anonim'
            };
        }));
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
  }, [gameKey]);

  useEffect(() => {
    if (!gameId) return;
    let duration = 120; let startTime = Date.now();
    const parts = gameId.split('_');
    if (parts.length >= 4) {
      if (!Number.isNaN(Number.parseInt(parts[2], 10))) startTime = Number.parseInt(parts[2], 10);
      if (!Number.isNaN(Number.parseInt(parts[3], 10))) duration = Number.parseInt(parts[3], 10);
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

    let lastGameTime = 0;
    let gameFrames = 0;

    const updateBall = () => {
      ball.current.dy += ball.current.gravity;
      ball.current.y += ball.current.dy;
      trailRef.current.push({ x: ball.current.x, y: ball.current.y });
      if (trailRef.current.length > 10) trailRef.current.shift();
      return ball.current.y + ball.current.radius <= screenHeight && ball.current.y - ball.current.radius >= 0;
    };

    const spawnPipesAndStars = (f: number, level: number, gap: number) => {
      const spawnInterval = Math.max(70, 110 - level * 5);
      if (f % spawnInterval === 0) {
        const topHeight = Math.random() * (screenHeight - gap - 120) + 60;
        pipes.current.push({ 
          x: screenWidth, width: 55, topHeight, 
          bottomHeight: screenHeight - gap - topHeight, 
          passed: false, 
          vy: level >= 3 ? (Math.random() - 0.5) * 1.5 : 0, 
          offset: 0 
        });
        if (Math.random() > 0.4) {
          stars.current.push({ x: screenWidth + 27, y: topHeight + gap / 2, radius: 11, collected: false });
        }
      }
    };

    const updateStars = (speed: number) => {
      for (let i = stars.current.length - 1; i >= 0; i--) {
        const s = stars.current[i];
        s.x -= speed;
        if (!s.collected) {
          const dist = Math.hypot(ball.current.x - s.x, ball.current.y - s.y);
          if (dist < ball.current.radius + s.radius) {
            s.collected = true;
            setScore(prev => prev + 5);
            engineRef.current.audio.playGoal();
            engineRef.current.particles.emit(s.x, s.y, '#FACC15', 10, 2);
            engineRef.current.texts.add(s.x, s.y, '+5 YILDIZ!', '#FACC15');
          }
        }
        if (s.x + s.radius < 0) stars.current.splice(i, 1);
      }
    };

    const updatePipes = (speed: number, gap: number) => {
      for (let i = pipes.current.length - 1; i >= 0; i--) {
        const p = pipes.current[i];
        p.x -= speed;
        if (p.vy) {
          p.offset = (p.offset || 0) + p.vy;
          if (Math.abs(p.offset) > 60) p.vy *= -1;
        }
        const topH = p.topHeight + (p.offset || 0);
        const botY = topH + gap;
        if (ball.current.x + ball.current.radius > p.x && ball.current.x - ball.current.radius < p.x + p.width) {
          if (ball.current.y - ball.current.radius < topH || ball.current.y + ball.current.radius > botY) return false;
        }
        if (!p.passed && ball.current.x > p.x + p.width) {
          p.passed = true;
          setScore(s => s + 1);
          engineRef.current.audio.playGoal();
          engineRef.current.particles.emit(p.x + p.width, ball.current.y, '#FDB022', 15, 3);
          engineRef.current.texts.add(p.x + p.width, ball.current.y - 20, '+1', '#FDB022');
        }
        if (p.x + p.width < 0) pipes.current.splice(i, 1);
      }
      return true;
    };

    const updateGame = (f: number) => {
      const level = difficulty.current.level;
      const speed = 3 + (level * 0.5);
      const gap = Math.max(180, baseGap - (level * 4));
      if (!updateBall()) { engineRef.current.audio.playCrash(); handleGameOver(false); return false; }
      spawnPipesAndStars(f, level, gap);
      updateStars(speed);
      if (!updatePipes(speed, gap)) { engineRef.current.audio.playCrash(); handleGameOver(false); return false; }
      if (difficulty.current.update(scoreRef.current)) {
        engineRef.current.audio.playLevelUp();
        engineRef.current.texts.add(screenWidth / 2, screenHeight / 2, `SEVİYE ${level}`, '#FACC15', 30);
      }
      return true;
    };

    const drawGame = (f: number) => {
      const level = difficulty.current.level;
      const gap = Math.max(180, baseGap - (level * 4));
      ctx.clearRect(0, 0, screenWidth, screenHeight);
      ctx.save();
      engineRef.current.shake.apply(ctx);
      ctx.strokeStyle = 'rgba(255,255,255,0.05)';
      ctx.lineWidth = 1;
      for (let i = 0; i < screenWidth; i += 40) {
        ctx.beginPath(); ctx.moveTo(i - (f % 40), 0); ctx.lineTo(i - (f % 40), screenHeight); ctx.stroke();
      }
      if (trailRef.current.length > 1) {
        ctx.beginPath();
        trailRef.current.forEach((pt, i) => { if (i === 0) ctx.moveTo(pt.x, pt.y); else ctx.lineTo(pt.x, pt.y); });
        ctx.lineWidth = ball.current.radius * 0.8; ctx.strokeStyle = 'rgba(255, 255, 255, 0.3)'; ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.stroke();
      }
      drawSoccerBall(ctx, ball.current.x, ball.current.y, ball.current.radius, f * 0.05);
      stars.current.forEach(s => {
        if (!s.collected) {
          ctx.fillStyle = '#FACC15'; ctx.beginPath(); ctx.moveTo(s.x, s.y - s.radius); ctx.lineTo(s.x + s.radius, s.y); ctx.lineTo(s.x, s.y + s.radius); ctx.lineTo(s.x - s.radius, s.y); ctx.closePath(); ctx.fill();
          ctx.shadowBlur = 10; ctx.shadowColor = '#FACC15'; ctx.stroke(); ctx.shadowBlur = 0;
        }
      });
      for (const p of pipes.current) {
        const topH = p.topHeight + (p.offset || 0);
        const botY = topH + gap;
        ctx.fillStyle = '#D92D20'; ctx.fillRect(p.x, 0, p.width, topH);
        ctx.strokeStyle = '#912018'; ctx.strokeRect(p.x, 0, p.width, topH);
        ctx.fillStyle = '#FDB022'; ctx.fillRect(p.x, botY, p.width, screenHeight - botY);
        ctx.strokeStyle = '#B54708'; ctx.strokeRect(p.x, botY, p.width, screenHeight - botY);
      }
      engineRef.current.particles.updateAndDraw(ctx);
      engineRef.current.texts.updateAndDraw(ctx);
      ctx.restore();
    };

    const render = (timestamp: number) => {
      if (!lastGameTime) lastGameTime = timestamp;
      lastGameTime = timestamp;
      if (!updateGame(gameFrames)) return;
      drawGame(gameFrames);
      gameFrames++;
      requestRef.current = requestAnimationFrame(render);
    };

    requestRef.current = requestAnimationFrame(render);
    return () => { if (requestRef.current) cancelAnimationFrame(requestRef.current); };
  }, [countdown, isGameOver, isTimeUp, screenWidth, screenHeight]);

  const handleGameOver = async (fromTimeout = false) => {
    if (isGameOver || isSubmitting) return;
    setIsGameOver(true);
    setIsSubmitting(true);
    
    if (requestRef.current) cancelAnimationFrame(requestRef.current);
    engineRef.current.audio.playCrash();
    
    const finalScore = scoreRef.current;
    if (fromTimeout) {
      engineRef.current.texts.add(screenWidth / 2, screenHeight / 2, "SÜRE DOLDU!", "#EF4444", 40);
    }

    try {
      await autoSaveScore(finalScore);
    } catch (err) {
      console.error("Score submission failed:", err);
    } finally {
      setIsSubmitting(false);
      const payload = JSON.stringify({ type: 'GAME_OVER', score: Math.max(finalScore, myHighScore), roomId, gameId });
      if (globalThis.window.MiniGameBridge) globalThis.window.MiniGameBridge.postMessage(payload);
      globalThis.window.parent.postMessage(payload, globalThis.window.location.origin);
    }
  };

  const autoSaveScore = async (finalScore: number) => {
    if (finalScore > myHighScore || myHighScore === 0) {
       if (finalScore > myHighScore) setMyHighScore(finalScore);
       await supabase.functions.invoke('process-mini-game', { body: { gameId, roomId, score: finalScore } });
    }
  };

  const playAgain = () => {
    if (isSubmitting) return;
    setScore(0); lastSavedScoreRef.current = 0; setIsGameOver(false); setCountdown(3); setGameKey(k => k + 1);
    ball.current = { x: 100, y: screenHeight / 2, radius: 15, dy: 0, gravity: 0.25, bounce: -6 };
    pipes.current = []; stars.current = []; difficulty.current.reset(); trailRef.current = [];
    engineRef.current.particles.particles = []; engineRef.current.texts.texts = [];
  };

  const exitGame = () => {
    if (isSubmitting) return;
    handleGameOver(false);
  };

  const handleTap = (_e: React.TouchEvent | React.MouseEvent | React.KeyboardEvent) => {
    if (countdown > 0 || isGameOver || isTimeUp) return;
    ball.current.dy = ball.current.bounce;
    engineRef.current.audio.playBounce();
    engineRef.current.particles.emit(ball.current.x, ball.current.y + ball.current.radius, '#ffffff', 5, 1);
  };

  const getRankColor = (idx: number) => {
    if (idx === 0) return 'text-yellow-400';
    if (idx === 1) return 'text-gray-300';
    if (idx === 2) return 'text-orange-300';
    return 'text-white';
  };

  const min = Math.floor(overallTimeLeft / 60);
  const sec = overallTimeLeft % 60;

  return (
    <div 
      className="w-full h-full relative overflow-hidden bg-gradient-to-b from-sky-400 to-sky-200 select-none touch-none font-sans outline-none" 
      onMouseDown={handleTap} 
      onTouchStart={handleTap}
      onKeyDown={(e) => (e.key === ' ' || e.key === 'Enter') && handleTap(e)}
      role="button"
      tabIndex={0}
      aria-label="Soccer Ball Flappy Game"
    >
      <div className="absolute top-4 right-4 z-10 flex flex-col items-end gap-2 pointer-events-none">
        <div className="bg-black/40 backdrop-blur-sm rounded-xl p-3 border border-white/20 shadow-xl min-w-[140px] order-last">
          <h3 className="text-white/80 text-xs font-bold uppercase tracking-wider mb-2 border-b border-white/10 pb-1">Canlı Liderlik</h3>
          {topScores.length === 0 ? <p className="text-white/50 text-xs">Henüz skor yok</p> : (
             <div className="space-y-1">
               {topScores.map((ts, idx) => (
                 <div key={ts.user_id || ts.id} className="flex justify-between items-center text-sm">
                   <span className={`font-medium ${getRankColor(idx)}`}>{idx + 1}. {(ts.username || 'Anonim').slice(0, 10)}</span>
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
            Skor: <span className="text-2xl text-yellow-400">{score}</span>
          </div>
          <div className="bg-black/40 backdrop-blur-sm rounded-full px-4 py-2 text-white font-bold tabular-nums border border-white/20 shadow-xl">
            Seviye: <span className="text-2xl text-blue-400">{difficulty.current.level}</span>
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
            <button onClick={(e) => { e.stopPropagation(); playAgain(); }} className="w-full max-w-sm mb-4 py-4 bg-gradient-to-r from-blue-500 to-indigo-600 font-bold rounded-2xl shadow-[0_0_20px_rgba(59,130,246,0.4)] text-lg text-white outline-none">🔄 Tekrar Oyna</button>
          )}
          <button onClick={() => exitGame()} className="w-full max-w-sm py-4 bg-white/10 hover:bg-white/20 text-white font-bold rounded-2xl border border-white/20 text-lg flex items-center justify-center gap-3 outline-none">
             {isSubmitting ? (
               <>
                 <div className="w-5 h-5 border-2 border-white/30 border-t-white rounded-full animate-spin"></div>
                 <span>Yükleniyor...</span>
               </>
             ) : (
               <>🚪 Çıkış ve Maça Dön</>
             )}
          </button>
        </div>
      )}
    </div>
  );
}
