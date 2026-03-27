import React, { useEffect, useRef, useState } from 'react';

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
  const requestRef = useRef<number>();
  
  const [score, setScore] = useState(0);
  const [isGameOver, setIsGameOver] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [countdown, setCountdown] = useState(3);

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
  }, [screenWidth]);

  useEffect(() => {
    // Only start game loop if countdown is 0 and game is not over
    if (countdown > 0 || isGameOver) return;

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
        handleGameOver();
        return;
      }

      requestRef.current = requestAnimationFrame(render);
    };

    requestRef.current = requestAnimationFrame(render);

    return () => {
      if (requestRef.current) cancelAnimationFrame(requestRef.current);
    };
  }, [countdown, isGameOver, screenWidth, screenHeight]);

  const handleGameOver = async () => {
    setIsGameOver(true);
    if (requestRef.current) cancelAnimationFrame(requestRef.current);
  };

  const submitScore = async () => {
    setIsSubmitting(true);
    try {
      const payload = JSON.stringify({
        type: 'GAME_OVER',
        score: score,
        roomId: roomId,
        gameId: gameId,
      });
      if (window.MiniGameBridge) {
        window.MiniGameBridge.postMessage(payload);
      } else {
        // Fallback for Flutter Web (iframe)
        window.parent.postMessage(payload, '*');
      }
    } catch (err) {
      console.error("Failed to send game over signal:", err);
    }
  };

  const handleTap = (e: React.MouseEvent | React.TouchEvent) => {
    if (countdown > 0 || isGameOver) return;
    
    let clientX, clientY;
    if ('touches' in e) {
      clientX = e.touches[0].clientX;
      clientY = e.touches[0].clientY;
    } else {
      clientX = (e as React.MouseEvent).clientX;
      clientY = (e as React.MouseEvent).clientY;
    }

    // Hitbox check (make it generous for mobile)
    const dist = Math.sqrt(
      Math.pow(clientX - ball.current.x, 2) + 
      Math.pow(clientY - ball.current.y, 2)
    );

    if (dist < ball.current.radius * 3) {
      // Hit!
      setScore(s => s + 1);
      
      // Calculate bounce direction based on hit offset
      const xOffset = clientX - ball.current.x;
      
      ball.current.dy = ball.current.bounce; // Bounce up
      ball.current.dx = -(xOffset * 0.15);   // Push horizontally opposite to tap
      ball.current.rotationSpeed = (xOffset * 0.01);
      
      // Make it slightly harder over time
      ball.current.gravity += 0.005;
    }
  };

  return (
    <div 
      className="w-full h-full relative overflow-hidden bg-gradient-to-b from-blue-400 to-green-600 select-none touch-none"
      onMouseDown={handleTap}
      onTouchStart={handleTap}
    >
      {/* Stadium Background Decor */}
      <div className="absolute inset-0 opacity-20 pointer-events-none flex flex-col justify-end">
        <div className="w-full h-1/2 bg-[repeating-linear-gradient(0deg,transparent,transparent_20px,rgba(255,255,255,0.1)_20px,rgba(255,255,255,0.1)_40px)]"></div>
      </div>

      <div className="absolute top-8 left-0 right-0 z-10 flex justify-between px-6 pointer-events-none">
        <div className="bg-black/40 backdrop-blur-sm rounded-full px-4 py-2 text-white font-bold tabular-nums border border-white/20 shadow-xl">
          Skor: <span className="text-2xl text-yellow-400">{score}</span>
        </div>
      </div>

      {countdown > 0 && (
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
            Top Düştü!
          </h2>
          <p className="text-white text-lg mb-8 text-center text-white/80">
            Nihai Skorun: <span className="font-bold text-yellow-400 text-3xl block mt-2">{score}</span>
          </p>
          <button
            onClick={(e) => {
              e.stopPropagation();
              submitScore();
            }}
            disabled={isSubmitting}
            className="w-full max-w-sm py-4 bg-gradient-to-r from-green-500 to-emerald-600 hover:from-green-400 hover:to-emerald-500 text-white font-bold rounded-2xl shadow-[0_0_20px_rgba(16,185,129,0.4)] transition-all transform active:scale-95 text-lg disabled:opacity-50 disabled:cursor-not-allowed border border-white/20"
          >
            {isSubmitting ? 'Skor Gönderiliyor...' : '🎁 Katılım Ödülü İçin Skoru Gönder'}
          </button>
        </div>
      )}
    </div>
  );
}
