import React, { useEffect, useRef, useState } from 'react';
import { supabase } from '../lib/supabase';
import { ParticleSystem, ScreenShake, FloatingTextSystem, AudioSynthesizer, drawSoccerBall, DifficultyScaler } from '../lib/gameUtils';

declare global {
  interface Window {
    MiniGameBridge?: {
      postMessage: (message: string) => void;
    };
  }
}

interface PenaltyShootoutProps {
  roomId: string;
  gameId: string;
}

export default function PenaltyShootout({ roomId, gameId }: PenaltyShootoutProps) {
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
  const [topScores, setTopScores] = useState<Array<{id: string, username: string, score: number}>>([]);
  const [myHighScore, setMyHighScore] = useState(0);


  const screenWidth = typeof window !== 'undefined' ? window.innerWidth : 300;
  const screenHeight = typeof window !== 'undefined' ? window.innerHeight : 500;

  // Game State Refs
  const ball = useRef({
    x: screenWidth / 2,
    y: screenHeight - 100,
    radius: 15,
    isShooting: false,
    targetX: 0,
    targetY: 0,
    startX: screenWidth / 2,
    startY: screenHeight - 100,
    progress: 0,
    curve: 0,
    rotation: 0,
  });

  const engineRef = useRef({
    particles: new ParticleSystem(),
    shake: new ScreenShake(),
    texts: new FloatingTextSystem(),
    audio: new AudioSynthesizer(),
  });
  const trailRef = useRef<{x: number, y: number, r: number}[]>([]);

  const keeper = useRef({
    x: screenWidth / 2,
    y: 130, // Goal line
    width: 60,
    height: 20,
    speed: 3,
    direction: 1,
    targetX: screenWidth / 2,
  });

  const difficulty = useRef(new DifficultyScaler(5)); // Level up every 5 goals
  const [wind, setWind] = useState({ speed: 0, display: '' });
  const windRef = useRef(0);
  
  const wall = useRef({
    active: false,
    players: [] as { x: number, y: number, height: number }[],
    jumpY: 0,
    jumpVelocity: 0,
  });

  const goal = {
    x: 50,
    y: 100,
    width: screenWidth - 100,
    height: 60,
  };

  const swipeStart = useRef({ x: 0, y: 0, time: 0 });

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

    return () => { supabase.removeChannel(channel); };
  }, [gameId]);

  useEffect(() => {
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
  }, []);

  useEffect(() => {
    if (!gameId) return;
    const parts = gameId.split('_');
    let duration = 120;
    let startTime = Date.now();
    
    if (parts.length >= 4) {
      const parsedTime = parseInt(parts[2], 10);
      const parsedDuration = parseInt(parts[3], 10);
      if (!isNaN(parsedTime)) startTime = parsedTime;
      if (!isNaN(parsedDuration)) duration = parsedDuration;
    }
        
    const calculateTimeLeft = () => {
      const elapsedSeconds = Math.floor((Date.now() - startTime) / 1000);
      return Math.max(0, duration - elapsedSeconds);
    };

    const initialTimeLeft = calculateTimeLeft();
    setOverallTimeLeft(initialTimeLeft);
    if (initialTimeLeft <= 0) setIsTimeUp(true);
    
    const globalTimer = setInterval(() => {
      const timeLeft = calculateTimeLeft();
      setOverallTimeLeft(timeLeft);
      if (timeLeft <= 0) {
         clearInterval(globalTimer);
         setIsTimeUp(true);
      }
    }, 1000);
    
    return () => clearInterval(globalTimer);
  }, [gameId]);

  useEffect(() => {
    if (isTimeUp && !isGameOver) {
      handleGameOver(true);
    }
  }, [isTimeUp]);

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

    const render = () => {
      ctx.clearRect(0, 0, screenWidth, screenHeight);

      ctx.save();
      engineRef.current.shake.apply(ctx);

      // Draw Goal Post
      ctx.strokeStyle = 'white';
      ctx.lineWidth = 5;
      ctx.strokeRect(goal.x, goal.y, goal.width, goal.height);

      // Draw Target Zones (Corners)
      ctx.fillStyle = 'rgba(255, 235, 59, 0.2)';
      const zoneSize = 40;
      // Top Left (2x)
      ctx.fillRect(goal.x + 5, goal.y + 5, zoneSize, zoneSize);
      ctx.strokeRect(goal.x + 5, goal.y + 5, zoneSize, zoneSize);
      // Top Right (2x)
      ctx.fillRect(goal.x + goal.width - zoneSize - 5, goal.y + 5, zoneSize, zoneSize);
      ctx.strokeRect(goal.x + goal.width - zoneSize - 5, goal.y + 5, zoneSize, zoneSize);
      // Bottom Corners (1.5x)
      ctx.fillStyle = 'rgba(76, 175, 80, 0.2)';
      ctx.fillRect(goal.x + 5, goal.y + goal.height - zoneSize - 5, zoneSize, zoneSize);
      ctx.fillRect(goal.x + goal.width - zoneSize - 5, goal.y + goal.height - zoneSize - 5, zoneSize, zoneSize);

      ctx.fillStyle = 'white';
      ctx.font = 'bold 10px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText('2x', goal.x + 5 + zoneSize/2, goal.y + 5 + zoneSize/2 + 4);
      ctx.fillText('2x', goal.x + goal.width - zoneSize/2 - 5, goal.y + 5 + zoneSize/2 + 4);
      ctx.fillText('1.5x', goal.x + 5 + zoneSize/2, goal.y + goal.height - zoneSize/2 - 5 + 4);
      ctx.fillText('1.5x', goal.x + goal.width - zoneSize/2 - 5, goal.y + goal.height - zoneSize/2 - 5 + 4);

      // Draw Net
      ctx.strokeStyle = 'rgba(255,255,255,0.3)';
      ctx.lineWidth = 1;
      for (let i = 0; i < goal.width; i += 15) {
        ctx.beginPath(); ctx.moveTo(goal.x + i, goal.y); ctx.lineTo(goal.x + i, goal.y + goal.height); ctx.stroke();
      }
      for (let i = 0; i < goal.height; i += 15) {
        ctx.beginPath(); ctx.moveTo(goal.x, goal.y + i); ctx.lineTo(goal.x + goal.width, goal.y + i); ctx.stroke();
      }

      // Update Keeper
      if (!ball.current.isShooting) {
        keeper.current.x += keeper.current.speed * keeper.current.direction;
        if (keeper.current.x < goal.x + 10 || keeper.current.x + keeper.current.width > goal.x + goal.width - 10) {
          keeper.current.direction *= -1;
        }
      } else {
        // Keeper dives towards the ball
        if (keeper.current.targetX < keeper.current.x) {
          keeper.current.x -= keeper.current.speed * 2;
        } else if (keeper.current.targetX > keeper.current.x + keeper.current.width) {
           keeper.current.x += keeper.current.speed * 2;
        }
      }

      // Draw Keeper
      ctx.fillStyle = '#ff4d4d'; // Red shirt
      ctx.fillRect(keeper.current.x, keeper.current.y - keeper.current.height, keeper.current.width, keeper.current.height);
      ctx.fillStyle = '#ffccaa'; // Head
      ctx.beginPath();
      ctx.arc(keeper.current.x + keeper.current.width / 2, keeper.current.y - keeper.current.height - 10, 10, 0, Math.PI * 2);
      ctx.fill();

      // Update & Draw Wall
      if (difficulty.current.level >= 2) {
        wall.current.active = true;
        if (wall.current.players.length === 0) {
          const startX = goal.x + goal.width / 4;
          wall.current.players = [
            { x: startX, y: 350, height: 40 },
            { x: startX + 25, y: 350, height: 40 },
          ];
        }

        // Periodic Jump
        if (ball.current.isShooting && wall.current.jumpY === 0 && Math.random() > 0.02) {
          wall.current.jumpVelocity = -8;
        }

        if (wall.current.jumpY < 0 || wall.current.jumpVelocity !== 0) {
          wall.current.jumpY += wall.current.jumpVelocity;
          wall.current.jumpVelocity += 0.5; // Gravity
          if (wall.current.jumpY > 0) {
            wall.current.jumpY = 0;
            wall.current.jumpVelocity = 0;
          }
        }

        ctx.fillStyle = '#3B82F6'; // Blue shirts for wall
        wall.current.players.forEach(p => {
          const py = p.y + wall.current.jumpY;
          ctx.fillRect(p.x, py - p.height, 20, p.height);
          ctx.beginPath();
          ctx.arc(p.x + 10, py - p.height - 8, 8, 0, Math.PI * 2);
          ctx.fill();
        });
      }

      // Update Ball
      if (ball.current.isShooting) {
        ball.current.progress += 0.04; // Animation speed
        if (ball.current.progress >= 1) {
          ball.current.progress = 1;
        }
        
        const t = ball.current.progress;
        const cx = (ball.current.startX + ball.current.targetX) / 2 + ball.current.curve;
        const cy = (ball.current.startY + ball.current.targetY) / 2;
        
        ball.current.x = Math.pow(1-t, 2) * ball.current.startX + 2 * (1-t) * t * cx + Math.pow(t, 2) * ball.current.targetX;
        ball.current.y = Math.pow(1-t, 2) * ball.current.startY + 2 * (1-t) * t * cy + Math.pow(t, 2) * ball.current.targetY;
        
        // Apply wind effect during flight
        ball.current.x += windRef.current * t * 2;
        
        ball.current.rotation += (ball.current.curve > 0 ? 0.2 : -0.2) + 0.1;
        
        // Scale down the ball to simulate depth
        const currentRadius = ball.current.radius * (1 - ball.current.progress * 0.5);

        if (ball.current.progress >= 1) {
          // Check collision with wall
          let hitWall = false;
          if (wall.current.active) {
            wall.current.players.forEach(p => {
               const py = p.y + wall.current.jumpY;
               if (ball.current.x > p.x && ball.current.x < p.x + 20 &&
                   ball.current.y > py - p.height && ball.current.y < py) {
                 hitWall = true;
               }
            });
          }

          // Check collision with keeper
          const hitKeeper = 
            !hitWall &&
            ball.current.x + currentRadius > keeper.current.x &&
            ball.current.x - currentRadius < keeper.current.x + keeper.current.width &&
            ball.current.y + currentRadius > keeper.current.y - keeper.current.height &&
            ball.current.y - currentRadius < keeper.current.y;

          const hitGoal = 
            ball.current.x > goal.x && ball.current.x < goal.x + goal.width &&
            ball.current.y > goal.y && ball.current.y < goal.y + goal.height;

          if (hitGoal && !hitKeeper) {
            let multiplier = 1;
            // Check target zones
            const isTopLeft = ball.current.x < goal.x + 50 && ball.current.y < goal.y + 50;
            const isTopRight = ball.current.x > goal.x + goal.width - 50 && ball.current.y < goal.y + 50;
            const isBottomLeft = ball.current.x < goal.x + 50 && ball.current.y > goal.y + goal.height - 50;
            const isBottomRight = ball.current.x > goal.x + goal.width - 50 && ball.current.y > goal.y + goal.height - 50;
            
            if (isTopLeft || isTopRight) multiplier = 2;
            else if (isBottomLeft || isBottomRight) multiplier = 1.5;

            const points = Math.floor(1 * multiplier);
            setScore(s => s + points);
            
            if (difficulty.current.update(scoreRef.current + points)) {
              engineRef.current.audio.playLevelUp();
              engineRef.current.texts.add(screenWidth/2, screenHeight/2, `LEVEL ${difficulty.current.level}!`, '#4ADE80');
              
              // Change wind on level up
              const newWind = (Math.random() - 0.5) * 4;
              windRef.current = newWind;
              setWind({ 
                speed: newWind, 
                display: newWind > 1 ? 'Strong East' : newWind < -1 ? 'Strong West' : newWind > 0 ? 'Light East' : 'Light West' 
              });
            }

            keeper.current.speed = 3 * difficulty.current.multiplier;
            engineRef.current.audio.playGoal();
            engineRef.current.particles.emit(ball.current.x, ball.current.y, '#ffffff', 30, 5);
            engineRef.current.texts.add(ball.current.x, ball.current.y - 20, multiplier > 1 ? `GOL X${multiplier}` : 'GOL!', '#FDB022');
          } else {
            engineRef.current.audio.playCrash();
            if (hitKeeper) {
               engineRef.current.shake.trigger(12);
               engineRef.current.particles.emit(ball.current.x, ball.current.y, '#ff4d4d', 15, 3);
            }
          }

          // Reset
          setTimeout(() => {
            ball.current = {
              ...ball.current,
              isShooting: false,
              x: screenWidth / 2,
              y: screenHeight - 100,
              progress: 0,
              curve: 0,
              rotation: 0,
            };
            keeper.current.x = screenWidth / 2 - keeper.current.width / 2;
            trailRef.current = [];
          }, 1000);
        }
      }

      // Draw Trail
      if (ball.current.isShooting && ball.current.progress < 1) {
         trailRef.current.push({ x: ball.current.x, y: ball.current.y, r: ball.current.radius * (1 - ball.current.progress * 0.5) });
         if (trailRef.current.length > 20) trailRef.current.shift();
      }
      
      if (trailRef.current.length > 1) {
        ctx.beginPath();
        for (let i = 0; i < trailRef.current.length; i++) {
          const pt = trailRef.current[i];
          if (i === 0) ctx.moveTo(pt.x, pt.y);
          else ctx.lineTo(pt.x, pt.y);
        }
        ctx.lineWidth = 10;
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.2)';
        ctx.lineCap = 'round';
        ctx.lineJoin = 'round';
        ctx.stroke();
      }

      // Draw Ball
      const r = ball.current.isShooting ? ball.current.radius * (1 - ball.current.progress * 0.5) : ball.current.radius;
      drawSoccerBall(ctx, ball.current.x, ball.current.y, r, ball.current.rotation);

      // Engine Update
      engineRef.current.particles.updateAndDraw(ctx);
      engineRef.current.texts.updateAndDraw(ctx);
      
      ctx.restore();

      requestRef.current = requestAnimationFrame(render);
    };

    requestRef.current = requestAnimationFrame(render);
    return () => {
      if (requestRef.current) cancelAnimationFrame(requestRef.current);
    };
  }, [countdown, isGameOver, isTimeUp, screenWidth, screenHeight]);

  const autoSaveScore = async (finalScore: number) => {
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
    await autoSaveScore(scoreRef.current);
  };


  const exitGame = () => {
    setIsSubmitting(true);
    try {
      const payload = JSON.stringify({ type: 'GAME_OVER', score: Math.max(score, myHighScore), roomId: roomId, gameId: gameId });
      if (window.MiniGameBridge) window.MiniGameBridge.postMessage(payload);
      window.parent.postMessage(payload, '*');
    } catch (err) {}
  };

  const handleTouchStart = (e: React.TouchEvent | React.MouseEvent) => {
    if (countdown > 0 || isGameOver || isTimeUp || ball.current.isShooting) return;
    let clientX, clientY;
    if ('touches' in e) { clientX = e.touches[0].clientX; clientY = e.touches[0].clientY; }
    else { clientX = (e as React.MouseEvent).clientX; clientY = (e as React.MouseEvent).clientY; }
    
    swipeStart.current = { x: clientX, y: clientY, time: Date.now() };
  };

  const handleTouchEnd = (e: React.TouchEvent | React.MouseEvent) => {
    if (countdown > 0 || isGameOver || isTimeUp || ball.current.isShooting || swipeStart.current.time === 0) return;
    let clientX, clientY;
    if ('changedTouches' in e) { clientX = e.changedTouches[0].clientX; clientY = e.changedTouches[0].clientY; }
    else { clientX = (e as React.MouseEvent).clientX; clientY = (e as React.MouseEvent).clientY; }
    
    const dx = clientX - swipeStart.current.x;
    const dy = clientY - swipeStart.current.y;
    const dt = Date.now() - swipeStart.current.time;

    // If swiped up fast enough
    if (dy < -50 && dt < 500) {
      ball.current.isShooting = true;
      ball.current.startX = ball.current.x;
      ball.current.startY = ball.current.y;
      
      // Calculate target based on swipe angle
      const targetY = goal.y + goal.height/2; 
      const distance = swipeStart.current.y - targetY;
      const angle = Math.atan2(dx, -dy); // 0 is straight up
      
      ball.current.targetX = ball.current.x + Math.tan(angle) * distance;
      ball.current.targetY = targetY;
      ball.current.curve = dx * 0.8; // Apply curve based on horizontal swipe distance

      engineRef.current.audio.playBounce(); // kick sound

      // Decide keeper dive
      // small chance keeper guesses wrong, mostly dives towards ball X
      const guessWrong = Math.random() > 0.7;
      if (guessWrong) {
        keeper.current.targetX = Math.random() > 0.5 ? goal.x + 20 : goal.x + goal.width - 20;
      } else {
        keeper.current.targetX = ball.current.targetX - keeper.current.width / 2;
      }
    }
    swipeStart.current.time = 0;
  };

  const min = Math.floor(overallTimeLeft / 60);
  const sec = overallTimeLeft % 60;

  return (
    <div 
      className="w-full h-full relative overflow-hidden bg-gradient-to-b from-green-800 to-green-600 select-none touch-none font-sans"
      onMouseDown={handleTouchStart}
      onMouseUp={handleTouchEnd}
      onTouchStart={handleTouchStart}
      onTouchEnd={handleTouchEnd}
    >
      <div className="absolute inset-0 opacity-20 pointer-events-none flex flex-col justify-end">
        <div className="w-full h-1/2 bg-[repeating-linear-gradient(0deg,transparent,transparent_20px,rgba(255,255,255,0.1)_20px,rgba(255,255,255,0.1)_40px)]"></div>
      </div>

      <div className="absolute top-4 right-4 z-10 flex flex-col items-end gap-2 pointer-events-none">
        <div className="bg-black/40 backdrop-blur-sm rounded-xl p-3 border border-white/20 shadow-xl min-w-[140px] order-last">
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
          <div className="bg-black/40 backdrop-blur-sm rounded-full px-4 py-2 text-white font-bold tabular-nums border border-white/20 shadow-xl text-sm">
            Level: <span className="text-green-400">{difficulty.current.level}</span>
          </div>
          {wind.speed !== 0 && (
            <div className="bg-blue-500/20 backdrop-blur-sm rounded-full px-3 py-1 text-xs text-blue-300 border border-blue-400/30 animate-pulse">
              🌬️ {wind.display}
            </div>
          )}
        </div>
      </div>

      {countdown > 0 && !isTimeUp && (
        <div className="absolute inset-0 z-20 flex flex-col items-center justify-center bg-black/60 backdrop-blur-sm pointer-events-none">
          <div className="animate-bounce text-8xl font-black text-white drop-shadow-[0_4px_20px_rgba(255,255,255,0.8)]">{countdown}</div>
          <div className="text-white text-xl mt-4 font-semibold opacity-90">Yukarı Kaydır (Swipe) & Gol At!</div>
        </div>
      )}

      <canvas ref={canvasRef} width={screenWidth} height={screenHeight} className="block" />

      {isGameOver && (
        <div className="absolute inset-0 z-50 flex flex-col items-center justify-center bg-black/80 backdrop-blur-md px-6">
          <h2 className="text-4xl font-black text-red-500 mb-2 uppercase tracking-widest drop-shadow-[0_2px_10px_rgba(239,68,68,0.5)]">Süre Doldu!</h2>
          <div className="bg-white/10 rounded-2xl p-6 border border-white/20 w-full max-w-sm mb-8 text-center">
            <p className="text-white text-sm opacity-80 uppercase tracking-widest mb-1">Bu Eldeki Skor</p>
            <p className="font-bold text-yellow-400 text-5xl tabular-nums drop-shadow-lg mb-4">{score}</p>
            <div className="w-full h-px bg-gradient-to-r from-transparent via-white/20 to-transparent my-4"></div>
            <p className="text-white/60 text-sm">En Yüksek Skorun</p>
            <p className="font-bold text-white text-2xl tabular-nums">{Math.max(score, myHighScore)}</p>
          </div>
          <button onClick={() => exitGame()} className="w-full max-w-sm py-4 bg-white/10 hover:bg-white/20 text-white font-bold rounded-2xl transition-all active:scale-95 text-lg border border-white/20">🚪 Çıkış ve Maça Dön</button>
        </div>
      )}
    </div>
  );
}
