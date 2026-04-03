import { useEffect, useRef, useState } from 'react';
import { supabase } from '../lib/supabase';
import { DifficultyScaler, ParticleSystem, ScreenShake, FloatingTextSystem, AudioSynthesizer } from '../lib/gameUtils';

declare global {
  interface Window { MiniGameBridge?: { postMessage: (message: string) => void; }; }
}

interface GoalCelebrationRhythmProps { readonly roomId: string; readonly gameId: string; }

interface GameNote {
  id: number;
  radius: number;
  speed: number;
  hit: boolean;
  miss: boolean;
  isDouble?: boolean;
}

interface Shockwave {
  x: number;
  y: number;
  radius: number;
  maxRadius: number;
  color: string;
  alpha: number;
  thickness: number;
}

interface LeaderboardEntry {
  id: string;
  score: number;
  username: string;
}

interface BotPersona {
  user_id: string;
  team: string;
}

export default function GoalCelebrationRhythm({ roomId, gameId }: GoalCelebrationRhythmProps) {
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

  const screenWidth = typeof window !== 'undefined' ? window.innerWidth : 300;
  const screenHeight = typeof window !== 'undefined' ? window.innerHeight : 500;

  const cx = screenWidth / 2;
  const cy = screenHeight / 2;
  const targetRadius = 60;
  const hitZoneTolerance = 25; 

  // Game state
  const notes = useRef<GameNote[]>([]);
  const [multiplier, setMultiplier] = useState(1);
  const [level, setLevel] = useState(1);
  const lastSpawn = useRef(0);
  const difficulty = useRef(new DifficultyScaler());
  const streak = useRef(0);
  const idCounter = useRef(0);
  
  // Juice systems
  const particles = useRef(new ParticleSystem());
  const shake = useRef(new ScreenShake());
  const floatingText = useRef(new FloatingTextSystem());
  const audio = useRef<AudioSynthesizer | null>(null);
  const shockwaves = useRef<Shockwave[]>([]);

  useEffect(() => {
    audio.current = new AudioSynthesizer();
  }, []);

  useEffect(() => {
    if (!gameId) return;
    const fetchLeaderboard = async () => {
      const { data } = await supabase.from('mini_game_logs')
        .select('id, user_id, score, users(username)')
        .eq('game_id', gameId)
        .order('score', { ascending: false })
        .limit(3);
        
      if (data) {
        const rawData = data as unknown as { id: string, user_id: string, score: number, users: { username: string } | { username: string }[] | null }[];
        
        const anonIds = rawData.filter(d => {
          const user = Array.isArray(d.users) ? d.users[0] : d.users;
          return !user?.username;
        }).map(d => d.user_id);
        
        const botLogos: Record<string, string> = {};
        
        if (anonIds.length > 0) {
            const { data: bots } = await supabase.from('bot_personas').select('user_id, team').in('user_id', anonIds);
            if (bots) {
                (bots as unknown as BotPersona[]).forEach((b) => { botLogos[b.user_id] = `${b.team || 'Anonim'} Bot`; });
            }
        }

        setTopScores(rawData.map(d => {
          const user = Array.isArray(d.users) ? d.users[0] : d.users;
          return {
            id: String(d.id),
            score: Number(d.score),
            username: String(user?.username || botLogos[d.user_id] || 'Anonim')
          };
        }));
      }
      
      const { data: authData } = await supabase.auth.getUser();
      if (authData?.user) {
         const { data: myData } = await supabase.from('mini_game_logs')
          .select('score')
          .eq('game_id', gameId)
          .eq('user_id', authData.user.id)
          .maybeSingle();
         if (myData) setMyHighScore(Number(myData.score));
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
    let duration = 120; 
    let startTimeValue = Date.now();
    const parts = gameId.split('_');
    if (parts.length >= 4) {
      if (!Number.isNaN(Number.parseInt(parts[2], 10))) startTimeValue = Number.parseInt(parts[2], 10);
      if (!Number.isNaN(Number.parseInt(parts[3], 10))) duration = Number.parseInt(parts[3], 10);
    }
    const calc = () => Math.max(0, duration - Math.floor((Date.now() - startTimeValue) / 1000));
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

    const spawnNote = (speedMult: number) => {
      const currentLevel = difficulty.current.getLevel(scoreRef.current);
      if (currentLevel !== level) setLevel(currentLevel);

      const speed = (3.5 + Math.random() * 2) * speedMult;
      notes.current.push({ 
        id: idCounter.current++, 
        radius: screenWidth * 0.8, 
        speed, 
        hit: false, 
        miss: false 
      });
      
      if (currentLevel >= 3 && Math.random() < 0.25) {
        notes.current.push({ 
          id: idCounter.current++, 
          radius: screenWidth * 1.0, 
          speed, 
          hit: false, 
          miss: false, 
          isDouble: true 
        });
      }
    };

    const updateAndDrawNotes = (ctx: CanvasRenderingContext2D) => {
      for (let i = notes.current.length - 1; i >= 0; i--) {
        const n = notes.current[i];
        if (n.hit) continue;

        n.radius -= n.speed;
        
        ctx.beginPath();
        ctx.arc(cx, cy, Math.max(0, n.radius), 0, Math.PI * 2);
        ctx.lineWidth = 6;
        ctx.strokeStyle = n.miss ? '#ef4444' : (n.isDouble ? '#a855f7' : '#FDB022');
        ctx.stroke();

        if (!n.miss && n.radius < targetRadius - hitZoneTolerance) {
          handleNoteMiss(n);
        }

        if (n.radius <= 0) {
          notes.current.splice(i, 1);
        }
      }
    };

    const handleNoteMiss = (n: GameNote) => {
      n.miss = true;
      streak.current = 0;
      setMultiplier(1);
      setScore(s => Math.max(0, s - 1));
      floatingText.current.add(cx, cy - 80, "KAÇTI!", "#ef4444", 24);
      shake.current.trigger(5);
      audio.current?.playCrash();
      shockwaves.current.push({ 
        x: cx, y: cy, radius: targetRadius, 
        maxRadius: targetRadius + 60, color: '#ef4444', 
        alpha: 0.8, thickness: 2 
      });
    };

    const updateAndDrawShockwaves = (ctx: CanvasRenderingContext2D) => {
      for (let i = shockwaves.current.length - 1; i >= 0; i--) {
        const sw = shockwaves.current[i];
        sw.radius += 5;
        sw.alpha -= 0.05;
        if (sw.alpha <= 0) {
          shockwaves.current.splice(i, 1);
        } else {
          ctx.save();
          ctx.globalAlpha = sw.alpha;
          ctx.strokeStyle = sw.color;
          ctx.lineWidth = sw.thickness;
          ctx.beginPath();
          ctx.arc(sw.x, sw.y, sw.radius, 0, Math.PI * 2);
          ctx.stroke();
          ctx.restore();
        }
      }
    };

    const drawTargetArea = (ctx: CanvasRenderingContext2D) => {
      ctx.beginPath();
      ctx.arc(cx, cy, targetRadius, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(255, 255, 255, 0.1)';
      ctx.fill();
      ctx.lineWidth = 4;
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.8)';
      ctx.stroke();
      
      // Pulse effect based on time
      const pulse = Math.sin(Date.now() * 0.01) * 5;
      ctx.beginPath();
      ctx.arc(cx, cy, targetRadius + pulse, 0, Math.PI * 2);
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.2)';
      ctx.lineWidth = 2;
      ctx.stroke();
    };

    const render = (timestamp: number) => {
      // Fix: Don't let lastSpawn lag behind if frame skips or tab backgrounded
      if (lastSpawn.current === 0) {
        lastSpawn.current = timestamp;
      }
      
      const scoreValue = scoreRef.current;
      const effectiveSpawnRate = difficulty.current.getSpawnRate(scoreValue);
      const speedMult = difficulty.current.getSpeedMultiplier(scoreValue);

      ctx.save();
      shake.current.apply(ctx);
      ctx.clearRect(-50, -50, screenWidth + 100, screenHeight + 100);

      drawTargetArea(ctx);

      const timeSinceLast = timestamp - lastSpawn.current;
      if (timeSinceLast > effectiveSpawnRate) {
        // Spawn a note and update lastSpawn
        // Using timestamp - (timeSinceLast % effectiveSpawnRate) to maintain rhythm integrity
        lastSpawn.current = timestamp - (timeSinceLast % effectiveSpawnRate);
        spawnNote(speedMult);
      }

      updateAndDrawNotes(ctx);
      updateAndDrawShockwaves(ctx);
      particles.current.updateAndDraw(ctx);
      floatingText.current.updateAndDraw(ctx);

      ctx.restore();
      requestRef.current = requestAnimationFrame(render);
    };

    requestRef.current = requestAnimationFrame(render);
    return () => { if (requestRef.current) cancelAnimationFrame(requestRef.current); };
  }, [countdown, isGameOver, isTimeUp, screenWidth, screenHeight, gameKey]);

  const autoSaveScore = async (finalScore: number) => {
    if (finalScore > myHighScore || myHighScore === 0) {
       if (finalScore > myHighScore) setMyHighScore(finalScore);
      try {
        await supabase.functions.invoke('process-mini-game', { body: { gameId, roomId, score: finalScore } });
      } catch (err) {
        console.error("Error saving score:", err);
      }
    }
  };

  const handleGameOver = async (fromTimeout = false) => {
    if (isGameOver || isSubmitting) return;
    setIsGameOver(true);
    setIsSubmitting(true);
    
    if (requestRef.current) cancelAnimationFrame(requestRef.current);
    audio.current?.playCrash();

    const finalScore = scoreRef.current;
    if (fromTimeout) {
      floatingText.current.add(cx, cy, "SÜRE DOLDU!", "#EF4444", 40);
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

  const playAgain = () => {
    setScore(0); lastSavedScoreRef.current = 0; setIsGameOver(false); setCountdown(3); setGameKey(k => k + 1);
    notes.current = []; lastSpawn.current = 0; shockwaves.current = [];
    streak.current = 0; setMultiplier(1); setLevel(1);
  };

  const exitGame = () => {
    setIsSubmitting(true);
    const payload = JSON.stringify({ type: 'GAME_OVER', score: Math.max(score, myHighScore), roomId, gameId });
    if (globalThis.window?.MiniGameBridge) globalThis.window.MiniGameBridge.postMessage(payload);
    globalThis.window?.parent?.postMessage(payload, '*');
  };

  const handleTap = () => {
    if (countdown > 0 || isGameOver || isTimeUp) return;

    let closestIndex = -1;
    let minDistance = 9999;

    for (let i = 0; i < notes.current.length; i++) {
       const n = notes.current[i];
       if (n.hit || n.miss) continue;
       const dist = Math.abs(n.radius - targetRadius);
       if (dist < minDistance) {
          minDistance = dist;
          closestIndex = i;
       }
    }

    if (closestIndex !== -1 && minDistance <= hitZoneTolerance * 1.5) {
       const note = notes.current[closestIndex];
       note.hit = true;
       
       streak.current += 1;
       const currentStreak = streak.current;
       
       let newMult = 1;
       if (currentStreak >= 20) newMult = 3;
       else if (currentStreak >= 10) newMult = 2;
       
       if (newMult > multiplier) {
          setMultiplier(newMult);
          audio.current?.playPowerUp();
          floatingText.current.add(cx, cy - 130, `ALEV ALDIN! x${newMult}`, "#ff4500", 34);
       }

       let pts = 1 * newMult;
       let color = 'white';
       let text = 'ORTA';

       if (minDistance < 8) { 
           pts = 3 * newMult; color = '#FFD700'; text = 'MÜKEMMEL!'; 
           audio.current?.playGoal();
           shockwaves.current.push({ x: cx, y: cy, radius: targetRadius, maxRadius: targetRadius + 150, color: '#FFD700', alpha: 1, thickness: 10 });
           particles.current.explosion(cx, cy, '#FFD700', 30);
           shake.current.trigger(15);
       }
       else if (minDistance < 18) { 
           pts = 2 * newMult; color = '#00FF00'; text = 'HARİKA!'; 
           audio.current?.playBounce();
           shockwaves.current.push({ x: cx, y: cy, radius: targetRadius, maxRadius: targetRadius + 100, color: '#00FF00', alpha: 0.8, thickness: 5 });
           particles.current.explosion(cx, cy, '#00FF00', 20);
           shake.current.trigger(8);
       }
       else {
           audio.current?.playBounce();
           shockwaves.current.push({ x: cx, y: cy, radius: targetRadius, maxRadius: targetRadius + 60, color: '#FFFFFF', alpha: 0.6, thickness: 2 });
           particles.current.explosion(cx, cy, '#FFFFFF', 10);
       }
       
       setScore(s => s + pts);
       floatingText.current.add(cx, cy - 100, text, color, 28);
    } else {
       streak.current = 0;
       setMultiplier(1);
       setScore(s => Math.max(0, s - 1));
       floatingText.current.add(cx, cy - 100, 'ISKALADIN!', 'red', 30);
       
       audio.current?.playCrash();
       shake.current.trigger(10);
       shockwaves.current.push({ x: cx, y: cy, radius: targetRadius, maxRadius: targetRadius + 60, color: 'red', alpha: 0.8, thickness: 2 });
    }
  };

  const min = Math.floor(overallTimeLeft / 60); const sec = overallTimeLeft % 60;

  return (
    <div 
      className="w-full h-full relative overflow-hidden bg-gradient-to-br from-purple-900 via-indigo-950 to-black select-none touch-none font-sans outline-none" 
      onMouseDown={handleTap} 
      onTouchStart={handleTap}
      onKeyDown={(e) => (e.key === ' ' || e.key === 'Enter') && handleTap()}
      role="button"
      tabIndex={0}
      aria-label="Goal Celebration Rhythm Game"
    >
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
        <div className="bg-black/40 backdrop-blur-sm rounded-xl p-3 border border-white/20 shadow-xl min-w-[140px]">
           <div className="flex justify-between items-center mb-1">
             <span className="text-white/60 text-[10px] font-bold uppercase tracking-widest">Skor</span>
             <span className="text-white font-black text-2xl drop-shadow-lg">{score}</span>
           </div>
           <div className="flex justify-between items-center mb-1">
             <span className="text-white/60 text-[10px] font-bold uppercase tracking-widest">Süre</span>
             <span className="text-white font-mono font-bold text-lg">{min}:{sec < 10 ? '0' + sec : sec}</span>
           </div>
           <div className="flex justify-between items-center pt-1 border-t border-white/10">
             <span className="text-white/60 text-[10px] font-bold uppercase tracking-widest">Kombo</span>
             <span className="text-yellow-400 font-black text-lg animate-pulse">x{multiplier}</span>
           </div>
           <div className="flex justify-between items-center">
             <span className="text-white/60 text-[10px] font-bold uppercase tracking-widest">Seri</span>
             <span className="text-white font-bold text-sm tracking-widest">{streak.current}</span>
           </div>
           <div className="flex justify-between items-center mt-1">
             <span className="text-white/60 text-[10px] font-bold uppercase tracking-widest">Seviye</span>
             <span className="text-purple-400 font-bold text-sm tracking-widest">{level}</span>
           </div>
        </div>
      </div>

      {countdown > 0 && !isTimeUp && (
        <div className="absolute inset-0 z-20 flex flex-col items-center justify-center bg-black/60 backdrop-blur-sm pointer-events-none">
          <div className="animate-bounce text-8xl font-black text-white drop-shadow-[0_4px_20px_rgba(255,255,255,0.8)]">{countdown}</div>
          <div className="text-white text-xl mt-4 font-semibold opacity-90">Ritme Göre Dokun!</div>
        </div>
      )}

      <canvas ref={canvasRef} width={screenWidth} height={screenHeight} className="block" />

      {isGameOver && (
        <div className="absolute inset-0 z-50 flex flex-col items-center justify-center bg-black/80 backdrop-blur-md px-6">
          <h2 className="text-4xl font-black text-purple-400 mb-2 uppercase tracking-widest drop-shadow-[0_2px_10px_rgba(192,132,252,0.5)]">
             {isTimeUp ? 'Süre Doldu!' : 'Oyun Bitti!'}
          </h2>
          <div className="bg-white/10 rounded-2xl p-6 border border-white/20 w-full max-w-sm mb-8 text-center">
            <p className="text-white text-sm opacity-80 uppercase tracking-widest mb-1">Bu Eldeki Skor</p>
            <p className="font-bold text-yellow-400 text-5xl tabular-nums drop-shadow-lg mb-4">{score}</p>
            <div className="w-full h-px bg-gradient-to-r from-transparent via-white/20 to-transparent my-4"></div>
            <p className="text-white/60 text-sm">En Yüksek</p>
            <p className="font-bold text-white text-2xl tabular-nums">{Math.max(score, myHighScore)}</p>
          </div>
          {!isTimeUp && (
             <button onClick={(e) => { e.stopPropagation(); playAgain(); }} className="w-full max-w-sm mb-4 py-4 bg-gradient-to-r from-purple-500 to-pink-600 font-bold rounded-2xl shadow-[0_0_20px_rgba(168,85,247,0.4)] text-lg text-white">🔄 Tekrar Oyna</button>
          )}
          <button onClick={() => exitGame()} className="w-full max-w-sm py-4 bg-white/10 hover:bg-white/20 text-white font-bold rounded-2xl border border-white/20 text-lg">🚪 Çıkış ve Maça Dön</button>
        </div>
      )}

      {isSubmitting && (
        <div className="absolute inset-0 z-[100] flex items-center justify-center bg-black/40 backdrop-blur-md text-white flex-col gap-4">
          <div className="animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-white"></div>
          <span className="font-medium tracking-widest animate-pulse">SONUÇLAR KAYDEDİLİYOR...</span>
        </div>
      )}
    </div>
  );
}
