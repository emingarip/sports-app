import { useEffect, useRef, useState } from 'react';
import { supabase } from '../lib/supabase';
import { ParticleSystem, ScreenShake, FloatingTextSystem, AudioSynthesizer, drawSoccerBall, DifficultyScaler } from '../lib/gameUtils';

declare global {
  interface Window { MiniGameBridge?: { postMessage: (message: string) => void; }; }
}

interface HeaderHeroProps { roomId: string; gameId: string; }

export default function HeaderHero({ roomId, gameId }: HeaderHeroProps) {
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
  const [gameKey, setGameKey] = useState(0);
  const [lives, setLives] = useState(3);
  const livesRef = useRef(3);
  const [level, setLevel] = useState(1);
  const hasHelmet = useRef(false);

  const screenWidth = typeof window !== 'undefined' ? window.innerWidth : 300;
  const screenHeight = typeof window !== 'undefined' ? window.innerHeight : 500;

  // Game state
  const player = useRef({
    x: screenWidth / 2,
    y: screenHeight - 80,
    width: 40,
    height: 60,
    isJumping: false,
    jumpProgress: 0,
  });

  const objects = useRef<Array<{ id: number; type: 'ball' | 'boot' | 'item'; x: number; y: number; dx: number; dy: number; gravity: number; active: boolean; isGold?: boolean; isHelmet?: boolean; isArc?: boolean }>>([]);
  const difficultyScaler = useRef(new DifficultyScaler());

  // Juice systems
  const particles = useRef(new ParticleSystem());
  const shake = useRef(new ScreenShake());
  const floatingText = useRef(new FloatingTextSystem());
  const audio = useRef<AudioSynthesizer | null>(null);
  const impactFrame = useRef(0);

  useEffect(() => {
    audio.current = new AudioSynthesizer();
  }, []);

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

    let frames = 0;

    const render = () => {
      ctx.save();
      shake.current.apply(ctx);

      // Impact Frame (flashing background)
      if (impactFrame.current > 0) {
        impactFrame.current--;
        ctx.fillStyle = impactFrame.current % 2 === 0 ? 'white' : 'black';
        ctx.fillRect(-50, -50, screenWidth + 100, screenHeight + 100);
      } else {
        ctx.clearRect(-50, -50, screenWidth + 100, screenHeight + 100);
      }

      // Player jump logic
      let currentY = player.current.y;
      if (player.current.isJumping) {
         player.current.jumpProgress += 0.15; // slightly faster jump
         if (player.current.jumpProgress >= Math.PI) {
            player.current.isJumping = false;
            player.current.jumpProgress = 0;
            // particles when landing
            particles.current.emit(player.current.x, player.current.y, 'rgba(255,255,255,0.3)', 5, 2);
         } else {
            currentY = player.current.y - Math.sin(player.current.jumpProgress) * 120; // Jump height 120
         }
      }

      // Draw player (simple person shape) - if impact frame is active, invert player color for stark contrast
      if (impactFrame.current > 0) {
         ctx.fillStyle = 'black';
         ctx.beginPath(); ctx.arc(player.current.x, currentY - 20, 15, 0, Math.PI*2); ctx.fill(); // Head
         ctx.fillRect(player.current.x - 15, currentY, 30, 40);
      } else {
         ctx.fillStyle = '#fca5a5'; // skin
         ctx.beginPath(); ctx.arc(player.current.x, currentY - 20, 15, 0, Math.PI*2); ctx.fill(); // Head
         ctx.fillStyle = '#ef4444'; // shirt
         ctx.fillRect(player.current.x - 15, currentY, 30, 40);
      }

      // Spawn objects
      const currentSpawnRate = difficultyScaler.current.getSpawnRate(scoreRef.current);
      if (frames % Math.floor(currentSpawnRate / 16) === 0) {
         const isLeft = Math.random() > 0.5;
         const rand = Math.random();
         let type: 'ball' | 'boot' | 'item' = 'ball';
         let isGold = false;
         let isHelmet = false;
         let isArc = Math.random() > 0.7; // 30% chance for curved trajectory

         if (rand > 0.85) type = 'boot';
         else if (rand < 0.05) { type = 'item'; isHelmet = true; } 
         else if (rand < 0.15) { type = 'ball'; isGold = true; }

         const speedMult = difficultyScaler.current.getSpeedMultiplier(scoreRef.current);
         
         objects.current.push({
            id: Date.now(), 
            type,
            x: isLeft ? -30 : screenWidth + 30,
            y: isArc ? screenHeight - 150 : screenHeight - 250,
            dx: (isLeft ? (3 + Math.random()*2) : -(3 + Math.random()*2)) * speedMult,
            dy: (isArc ? -(9 + Math.random()*4) : -(5 + Math.random()*3)),
            gravity: isArc ? 0.25 : 0.15,
            active: true,
            isGold,
            isHelmet,
            isArc
         });
         
         setLevel(difficultyScaler.current.getLevel(scoreRef.current));
      }

      // Update and draw objects
      for (let i = objects.current.length - 1; i >= 0; i--) {
        const obj = objects.current[i];
        if (!obj.active) continue;

        obj.dy += obj.gravity;
        obj.x += obj.dx;
        obj.y += obj.dy;

        ctx.beginPath();
        if (obj.type === 'ball') {
           drawSoccerBall(ctx, obj.x, obj.y, 15, frames * 0.1);
        } else {
           // draw boot (brown rect) with rotation
           ctx.save();
           ctx.translate(obj.x, obj.y);
           ctx.rotate(frames * 0.08 * Math.sign(obj.dx));
           ctx.fillStyle = '#8B4513';
           ctx.fillRect(-12, -8, 24, 16);
           ctx.fillStyle = '#5A2A0C';
           ctx.fillRect(-12, -8, 6, 16);
           ctx.restore();
        }

        // Collision with player HEAD
        const dist = Math.sqrt(Math.pow(obj.x - player.current.x, 2) + Math.pow(obj.y - (currentY - 20), 2));
        if (dist < 35) { // generous hitbox for header
           obj.active = false;
           
           if (obj.isHelmet) {
             hasHelmet.current = true;
             floatingText.current.addSpecial(obj.x, obj.y - 40, "CRITICAL", "KASK!");
             audio.current?.playPowerUp(); // Assuming this exists or falls back
             particles.current.explosion(obj.x, obj.y, "#3b82f6", 30);
           } else if (obj.type === 'ball') {
              const points = obj.isGold ? 3 : 1;
              setScore(s => s + points);
              impactFrame.current = 3;
              shake.current.trigger(obj.isGold ? 20 : 10);
              
              if (obj.isGold) {
                floatingText.current.addSpecial(obj.x, obj.y - 40, "PERFECT");
                particles.current.explosion(obj.x, obj.y, "#fbbf24", 25);
              } else {
                particles.current.emit(obj.x, obj.y, '#FFD700', 15, 6);
                floatingText.current.add(obj.x, obj.y - 30, "+1", "rgba(255, 255, 0, 1)");
              }
              
              audio.current?.playBounce();
           } else {
              // BOOT (Danger)
              if (hasHelmet.current) {
                hasHelmet.current = false;
                floatingText.current.add(obj.x, obj.y - 40, "KASK KIRILDI!", "#f87171", 20);
                shake.current.trigger(15);
                particles.current.explosion(obj.x, obj.y, "#94a3b8", 20);
              } else {
                setLives(l => {
                  const newLives = l - 1;
                  livesRef.current = newLives;
                  if (newLives <= 0) handleGameOver();
                  return newLives;
                });
                shake.current.trigger(25);
                particles.current.explosion(obj.x, obj.y, '#FF0000', 30, 10);
                floatingText.current.add(obj.x, obj.y - 30, "-1 CAN", "rgba(255, 0, 0, 1)");
                audio.current?.playCrash();
                
                // Flash red background
                ctx.fillStyle = 'rgba(255,0,0,0.5)'; 
                ctx.fillRect(-50,-50,screenWidth + 100, screenHeight + 100);
              }
           }
        }

        if (obj.y > screenHeight) {
          if (obj.type === 'ball' && !obj.active && !obj.isGold) {
            // Already hit, safely remove
          } else if (obj.type === 'ball' && obj.active && !obj.isGold) {
            // Missed a normal ball
            if (hasHelmet.current) {
              hasHelmet.current = false;
              floatingText.current.add(player.current.x, player.current.y - 40, "KASK KIRILDI!", "#f87171", 20);
            } else {
              livesRef.current -= 1;
              setLives(livesRef.current);
              if (livesRef.current <= 0) handleGameOver();
              floatingText.current.add(obj.x, screenHeight - 20, "KAÇTI!", "#ff0000", 20);
            }
          }
          objects.current.splice(i, 1);
        }
      }

      particles.current.updateAndDraw(ctx);
      floatingText.current.updateAndDraw(ctx);

      ctx.restore();

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
    objects.current = []; livesRef.current = 3; setLives(3); setLevel(1);
  };

  const exitGame = () => {
    setIsSubmitting(true);
    const payload = JSON.stringify({ type: 'GAME_OVER', score: Math.max(score, myHighScore), roomId, gameId });
    if (globalThis.window?.MiniGameBridge) globalThis.window.MiniGameBridge.postMessage(payload);
    globalThis.window?.parent?.postMessage(payload, '*');
  };

  const handleTap = () => {
    if (countdown > 0 || isGameOver || isTimeUp) return;
    if (!player.current.isJumping) {
       player.current.isJumping = true;
       player.current.jumpProgress = 0;
    }
  };

  const min = Math.floor(overallTimeLeft / 60); const sec = overallTimeLeft % 60;

  return (
    <div className="w-full h-full relative overflow-hidden bg-gradient-to-b from-orange-400 to-red-500 select-none touch-none font-sans" onMouseDown={handleTap} onTouchStart={handleTap}>
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
             <span className="text-white/60 text-[10px] font-bold uppercase tracking-widest">Kafa</span>
             <span className="text-white font-black text-2xl drop-shadow-lg">{score}</span>
           </div>
           <div className="flex justify-between items-center mb-1">
             <span className="text-white/60 text-[10px] font-bold uppercase tracking-widest">Süre</span>
             <span className="text-white font-mono font-bold text-lg">{min}:{sec < 10 ? '0' + sec : sec}</span>
           </div>
           <div className="flex justify-between items-center pt-1 border-t border-white/10">
             <span className="text-white/60 text-[10px] font-bold uppercase tracking-widest">Can</span>
             <span className="text-red-400 text-sm animate-pulse">{"❤️".repeat(Math.max(0, lives))}</span>
           </div>
           <div className="flex justify-between items-center mt-1">
             <span className="text-white/60 text-[10px] font-bold uppercase tracking-widest">Seviye</span>
             <span className="text-yellow-400 font-bold text-sm tracking-widest">{level}</span>
           </div>
        </div>
      </div>

      {countdown > 0 && !isTimeUp && (
        <div className="absolute inset-0 z-20 flex flex-col items-center justify-center bg-black/60 backdrop-blur-sm pointer-events-none">
          <div className="animate-bounce text-8xl font-black text-white drop-shadow-[0_4px_20px_rgba(255,255,255,0.8)]">{countdown}</div>
          <div className="text-white text-xl mt-4 font-semibold opacity-90">Kafa Vurmak İçin Dokun!</div>
        </div>
      )}

      <canvas ref={canvasRef} width={screenWidth} height={screenHeight} className="block" />

      {isGameOver && (
        <div className="absolute inset-0 z-50 flex flex-col items-center justify-center bg-black/80 backdrop-blur-md px-6">
          <h2 className="text-4xl font-black text-red-500 mb-2 uppercase tracking-widest drop-shadow-[0_2px_10px_rgba(239,68,68,0.5)]">
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
            <button onClick={(e) => { e.stopPropagation(); playAgain(); }} className="w-full max-w-sm mb-4 py-4 bg-gradient-to-r from-blue-500 to-indigo-600 font-bold rounded-2xl shadow-[0_0_20px_rgba(59,130,246,0.4)] text-lg text-white">🔄 Tekrar Oyna</button>
          )}
          <button onClick={() => exitGame()} className="w-full max-w-sm py-4 bg-white/10 hover:bg-white/20 text-white font-bold rounded-2xl border border-white/20 text-lg">🚪 Çıkış ve Maça Dön</button>
        </div>
      )}
    </div>
  );
}
