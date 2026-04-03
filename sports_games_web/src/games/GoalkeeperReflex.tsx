import React, { useEffect, useRef, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { postMessageToHost } from '../lib/bridge';
import { ParticleSystem, ScreenShake, FloatingTextSystem, AudioSynthesizer, drawSoccerBall, DifficultyScaler } from '../lib/gameUtils';

interface Ball {
  id: number;
  x: number;
  y: number;
  size: number;
  max_size: number;
  speed: number;
  isFake?: boolean;
  isShield?: boolean;
  targetX?: number;
  targetY?: number;
  fakeTriggered?: boolean;
  rotation: number;
}

interface LeaderboardEntry {
  id: string;
  score: number;
  username: string;
}

interface GoalkeeperReflexProps { readonly roomId: string; readonly gameId: string; }

export default function GoalkeeperReflex({ roomId, gameId }: GoalkeeperReflexProps) {
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

  const screenWidth = globalThis.window ? globalThis.window.innerWidth : 300;
  const screenHeight = globalThis.window ? globalThis.window.innerHeight : 500;

  // Game specific state
  const balls = useRef<Ball[]>([]);
  const lastSpawn = useRef(0);
  const idCounter = useRef(0);
  const difficulty = useRef(new DifficultyScaler());
  const combo = useRef(0);
  const [level, setLevel] = useState(1);

  // Juice systems
  const particles = useRef(new ParticleSystem());
  const shake = useRef(new ScreenShake());
  const floatingText = useRef(new FloatingTextSystem());
  const audio = useRef<AudioSynthesizer | null>(null);
  const hitStop = useRef(0);

  useEffect(() => {
    audio.current = new AudioSynthesizer();
  }, []);

  const fetchLeaderboard = useCallback(async () => {
    if (!gameId) return;
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
          bots.forEach((b: any) => { botLogos[b.user_id] = (b.team || 'Anonim') + ' Bot'; });
        }
      }

      setTopScores(rawData.map(d => {
        const user = Array.isArray(d.users) ? d.users[0] : d.users;
        return {
          id: d.id,
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
  }, [gameId]);

  useEffect(() => {
    fetchLeaderboard();
    const channel = supabase.channel(`public:mini_game_logs:game_id=eq.${gameId}`).on('postgres_changes', { event: '*', schema: 'public', table: 'mini_game_logs', filter: `game_id=eq.${gameId}` }, fetchLeaderboard).subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [gameId, fetchLeaderboard]);

  useEffect(() => {
    if (countdown <= 0) return;
    const interval = setInterval(() => {
      setCountdown(c => {
        if (c <= 1) { clearInterval(interval); return 0; }
        return c - 1;
      });
    }, 1000);
    return () => clearInterval(interval);
  }, [countdown]);

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

  const autoSaveScore = useCallback(async (finalScore: number) => {
    if (finalScore > myHighScore || myHighScore === 0) {
      if (finalScore > myHighScore) setMyHighScore(finalScore);
      try { await supabase.functions.invoke('process-mini-game', { body: { gameId, roomId, score: finalScore } }); } catch (err) {}
    }
  }, [gameId, roomId, myHighScore]);

  const handleGameOver = useCallback(async () => {
    setIsGameOver(true);
    if (requestRef.current) cancelAnimationFrame(requestRef.current);
    await autoSaveScore(scoreRef.current);
  }, [autoSaveScore]);

  useEffect(() => { if (isTimeUp && !isGameOver) handleGameOver(); }, [isTimeUp, isGameOver, handleGameOver]);

  useEffect(() => {
    if (isGameOver || isTimeUp || countdown > 0) return;
    const throttleTimer = setInterval(() => {
      if (scoreRef.current > lastSavedScoreRef.current) {
        lastSavedScoreRef.current = scoreRef.current;
        autoSaveScore(scoreRef.current);
      }
    }, 3000);
    return () => clearInterval(throttleTimer);
  }, [isGameOver, isTimeUp, countdown, autoSaveScore]);

  useEffect(() => {
    if (countdown > 0 || isGameOver || isTimeUp) return;
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext('2d');
    if (!canvas || !ctx) return;

    const drawBackground = (ctx: CanvasRenderingContext2D) => {
      ctx.strokeStyle = 'rgba(255,255,255,0.05)';
      ctx.lineWidth = 1;
      for (let i = 0; i < screenWidth; i += 30) {
        ctx.beginPath(); ctx.moveTo(i, 0); ctx.lineTo(i, screenHeight); ctx.stroke();
      }
      for (let i = 0; i < screenHeight; i += 30) {
        ctx.beginPath(); ctx.moveTo(0, i); ctx.lineTo(screenWidth, i); ctx.stroke();
      }
    };

    const spawnBall = (time: number, speedMult: number) => {
      const effectiveSpawnRate = difficulty.current.getSpawnRate(scoreRef.current);
      if (time - lastSpawn.current > effectiveSpawnRate) {
        lastSpawn.current = time;
        const currentLevel = difficulty.current.getLevel(scoreRef.current);
        if (currentLevel !== level) setLevel(currentLevel);

        const isShield = currentLevel >= 2 && Math.random() < 0.05 && !balls.current.some(b => b.isShield);
        const isFake = !isShield && currentLevel >= 3 && Math.random() < 0.15;
        const x = Math.random() * (screenWidth - 100) + 50;
        const y = Math.random() * (screenHeight - 200) + 100;

        balls.current.push({
          id: idCounter.current++,
          x, y, targetX: x, targetY: y,
          size: 5, max_size: 60,
          speed: (0.4 + Math.random() * 0.4) * speedMult,
          isFake, isShield, fakeTriggered: false,
          rotation: Math.random() * Math.PI * 2
        });
      }
    };

    const drawBall = (ctx: CanvasRenderingContext2D, b: Ball) => {
      if (b.isShield) {
        ctx.save(); ctx.shadowBlur = 15; ctx.shadowColor = '#00f';
        drawSoccerBall(ctx, b.x, b.y, b.size, b.rotation);
        ctx.strokeStyle = '#44f'; ctx.lineWidth = 3; ctx.beginPath(); ctx.arc(b.x, b.y, b.size + 5, 0, Math.PI * 2); ctx.stroke();
        ctx.restore();
      } else if (b.isFake && b.fakeTriggered) {
        ctx.save(); ctx.globalAlpha = 0.8;
        drawSoccerBall(ctx, b.x, b.y, b.size, b.rotation);
        ctx.restore();
      } else {
        drawSoccerBall(ctx, b.x, b.y, b.size, b.rotation);
      }

      if (b.size > b.max_size - 15) {
        ctx.beginPath(); ctx.arc(b.x, b.y, b.size, 0, Math.PI * 2);
        ctx.fillStyle = b.isShield ? 'rgba(0,0,255,0.2)' : 'rgba(255,0,0,0.4)';
        ctx.fill();
      }
    };

    const updateAndDrawBalls = (ctx: CanvasRenderingContext2D, shouldUpdate: boolean) => {
      for (let i = balls.current.length - 1; i >= 0; i--) {
        const b = balls.current[i];
        if (shouldUpdate) {
          b.size += b.speed;
          b.rotation += 0.1;

          if (b.isFake && b.size > b.max_size * 0.4 && !b.fakeTriggered) {
            b.fakeTriggered = true;
            b.targetX = Math.random() * (screenWidth - 100) + 50;
            b.targetY = Math.random() * (screenHeight - 200) + 100;
            floatingText.current.add(b.x, b.y - 20, "FAKE!", "rgba(255, 100, 100, 1)", 15);
          }

          if (b.targetX !== undefined && b.targetY !== undefined) {
            b.x += (b.targetX - b.x) * 0.15;
            b.y += (b.targetY - b.y) * 0.15;
          }
        }

        drawBall(ctx, b);
        if (b.size >= b.max_size && shouldUpdate) {
          if (!b.isShield) {
            setScore(s => Math.max(0, s - 1));
            combo.current = 0;
            audio.current?.playCrash();
            shake.current.trigger(15);
            floatingText.current.add(b.x, b.y, "-1", "rgba(255, 50, 50, 1)", 25);
            ctx.fillStyle = 'rgba(255,0,0,0.3)';
            ctx.fillRect(-50, -50, screenWidth + 100, screenHeight + 100);
          }
          balls.current.splice(i, 1);
        }
      }
    };

    const render = (time: number) => {
      if (lastSpawn.current === 0) lastSpawn.current = time;
      ctx.save();
      shake.current.apply(ctx);
      difficulty.current.update(scoreRef.current);

      if (difficulty.current.level !== level) {
        setLevel(difficulty.current.level);
        audio.current?.playLevelUp();
        floatingText.current.add(screenWidth / 2, screenHeight / 2, `LEVEL ${difficulty.current.level}`, "rgba(255, 255, 0, 1)", 40);
      }

      ctx.clearRect(-50, -50, screenWidth + 100, screenHeight + 100);
      drawBackground(ctx);

      let shouldUpdate = true;
      if (hitStop.current > 0) {
        hitStop.current--;
        shouldUpdate = false;
      }

      if (shouldUpdate) {
        spawnBall(time, difficulty.current.getSpeedMultiplier(scoreRef.current));
      }

      updateAndDrawBalls(ctx, shouldUpdate);
      particles.current.updateAndDraw(ctx);
      floatingText.current.updateAndDraw(ctx);

      ctx.restore();
      requestRef.current = requestAnimationFrame(render);
    };

    requestRef.current = requestAnimationFrame(render);
    return () => { if (requestRef.current) cancelAnimationFrame(requestRef.current); };
  }, [countdown, isGameOver, isTimeUp, screenWidth, screenHeight, level, gameKey]);

  const exitGame = () => {
    setIsSubmitting(true);
    const finalScore = Math.max(score, myHighScore);
    const payload = JSON.stringify({ type: 'GAME_OVER', score: finalScore, roomId, gameId });
    
    // Ensure last score is saved
    autoSaveScore(scoreRef.current).then(() => {
      setTimeout(() => {
        postMessageToHost(payload);
      }, 800);
    });
  };

  const playAgain = () => {
    balls.current = [];
    setScore(0);
    scoreRef.current = 0;
    lastSavedScoreRef.current = 0;
    combo.current = 0;
    idCounter.current = 0;
    lastSpawn.current = 0;
    difficulty.current = new DifficultyScaler();
    setLevel(1);
    setIsGameOver(false);
    setCountdown(3);
    setGameKey(k => k + 1);
  };

  const handleTap = (e: React.TouchEvent | React.MouseEvent) => {
    if (countdown > 0 || isGameOver || isTimeUp) return;
    
    const clientX = 'touches' in e ? e.touches[0].clientX : (e as React.MouseEvent).clientX;
    const clientY = 'touches' in e ? e.touches[0].clientY : (e as React.MouseEvent).clientY;
    
    let tappedIndex = -1;
    let maxFoundSize = -1;
    for (let i = 0; i < balls.current.length; i++) {
       const b = balls.current[i];
       const dist = Math.sqrt(Math.pow(clientX - b.x, 2) + Math.pow(clientY - b.y, 2));
       if (dist < b.size * 1.5 && b.size > maxFoundSize) {
          maxFoundSize = b.size; tappedIndex = i;
       }
    }

    if (tappedIndex !== -1) {
      const b = balls.current[tappedIndex];
      if (b.isShield) {
        const ballsToSave = balls.current.length;
        balls.current = [];
        setScore(s => s + (ballsToSave * 2) + 10);
        audio.current?.playGoal();
        shake.current.trigger(20);
        floatingText.current.add(b.x, b.y, "TAKIM SAVUNMASI!", "#44f", 30);
        particles.current.explosion(b.x, b.y, "#44f", 30);
      } else {
        combo.current += 1;
        const comboMult = Math.min(5, 1 + Math.floor(combo.current / 5) * 0.5);
        const timingBonus = b.size > b.max_size * 0.8 ? 3 : 1;
        const pointsToAdd = Math.floor((b.isFake ? 5 : 1) * timingBonus * comboMult);
        
        setScore(s => s + pointsToAdd);
        audio.current?.playBounce();
        particles.current.explosion(b.x, b.y, "#fff", 15);
        floatingText.current.add(b.x, b.y, `+${pointsToAdd}${combo.current > 1 ? ` (x${combo.current})` : ""}`, combo.current > 10 ? "#fbbf24" : "#fff", 20 + timingBonus * 2);
        balls.current.splice(tappedIndex, 1);
      }
      hitStop.current = 3;
    } else {
      combo.current = 0;
    }
  };

  const min = Math.floor(overallTimeLeft / 60);
  const sec = overallTimeLeft % 60;

  return (
    <div className="w-full h-full relative overflow-hidden bg-gradient-to-b from-blue-800 to-indigo-900 select-none touch-none font-sans" onMouseDown={handleTap} onTouchStart={handleTap}>
      {/* HUD components same as before with minor premium adjustments */}
      <div className="absolute top-4 left-4 right-4 z-10 flex justify-between items-start pointer-events-none">
        <div className="flex flex-col gap-2">
           <div className="bg-black/40 backdrop-blur-md rounded-2xl p-4 border border-white/10 shadow-2xl">
              <div className="text-white/60 text-[10px] font-bold uppercase tracking-widest mb-1">SKOR</div>
              <div className="text-4xl font-black text-white tabular-nums flex items-baseline gap-2">
                {score}
                {combo.current > 1 && (
                  <span className="text-yellow-400 text-xs italic animate-pulse">
                    x{combo.current} KOMBO
                  </span>
                )}
              </div>
           </div>
           <div className="bg-blue-500/20 backdrop-blur-md rounded-xl px-3 py-1 border border-blue-400/30 self-start">
             <span className="text-white font-black">Lvl {level}</span>
           </div>
        </div>

        <div className="flex flex-col items-end gap-2">
           <div className="bg-black/40 backdrop-blur-md rounded-xl p-3 border border-white/10 text-right">
             <div className="text-white/60 text-[10px] font-bold uppercase tracking-wider mb-1">SÜRE</div>
             <div className={`text-2xl font-black tabular-nums ${overallTimeLeft < 15 ? 'text-red-500 animate-pulse' : 'text-white'}`}>
               {min}:{sec < 10 ? '0' : ''}{sec}
             </div>
           </div>

           <div className="bg-black/40 backdrop-blur-sm rounded-xl p-3 border border-white/20 shadow-xl min-w-[120px]">
             {topScores.map((ts) => (
                <div key={ts.id} className="flex justify-between items-center text-[10px] mb-1 last:mb-0">
                  <span className="text-white/80 truncate max-w-[80px]">{ts.username}</span>
                  <span className="font-bold text-white pl-2">{ts.score}</span>
                </div>
             ))}
           </div>
        </div>
      </div>

      <canvas ref={canvasRef} width={screenWidth} height={screenHeight} className="block w-full h-full object-contain" />

      {countdown > 0 && !isTimeUp && (
        <div className="absolute inset-0 z-20 flex items-center justify-center bg-black/60 backdrop-blur-sm">
           <div className="text-8xl font-black text-white animate-ping">{countdown}</div>
        </div>
      )}

      {isGameOver && (
        <div className="absolute inset-0 z-50 flex flex-col items-center justify-center bg-black/90 backdrop-blur-xl px-6 text-center">
          <div className="w-full max-w-sm bg-gradient-to-b from-indigo-500/20 to-black/40 p-8 rounded-3xl border border-white/10 shadow-2xl">
            <h2 className="text-3xl font-black text-white mb-6 uppercase tracking-tighter">OYUN BİTTİ</h2>
            <div className="mb-8">
              <div className="text-white/40 text-xs uppercase tracking-widest mb-1">TOPLAM SKOR</div>
              <div className="text-7xl font-black text-yellow-400 drop-shadow-2xl">{score}</div>
            </div>
            
            <div className="grid grid-cols-2 gap-4 mb-8">
              <button onClick={playAgain} className="py-4 bg-white/10 hover:bg-white/20 text-white font-bold rounded-2xl transition-all border border-white/10">🔄 TEKRAR</button>
              <button 
                onClick={exitGame} 
                disabled={isSubmitting}
                className="py-4 bg-blue-600 hover:bg-blue-500 text-white font-bold rounded-2xl transition-all shadow-lg shadow-blue-900/20 flex items-center justify-center"
              >
                {isSubmitting ? <div className="w-5 h-5 border-2 border-white/30 border-t-white rounded-full animate-spin"></div> : '🚪 ÇIKIŞ'}
              </button>
            </div>
          </div>
        </div>
      )}

      {isSubmitting && !isGameOver && (
        <div className="absolute inset-0 z-[100] flex flex-col items-center justify-center bg-black/80 backdrop-blur-md">
          <div className="w-12 h-12 border-4 border-blue-500/30 border-t-blue-500 rounded-full animate-spin mb-4"></div>
          <p className="text-white font-bold animate-pulse">Skor Kaydediliyor...</p>
        </div>
      )}
    </div>
  );
}
