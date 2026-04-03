/**
 * gameUtils.ts
 * Shared utilities for mini-games to provide "Juice" and Game Feel.
 */

// --- AUDIO SYNTHESIZER ---
export class AudioSynthesizer {
  private ctx: AudioContext | null = null;

  constructor() {
    this.init();
  }

  private init() {
    if (typeof globalThis.window !== 'undefined') {
      const AudioContextClass = globalThis.window.AudioContext || (globalThis.window as any).webkitAudioContext;
      if (AudioContextClass) {
        this.ctx = new AudioContextClass();
      }
    }
  }

  private playTone(frequency: number, type: OscillatorType, duration: number, vol = 0.1) {
    if (!this.ctx) return;
    if (this.ctx.state === 'suspended') this.ctx.resume();

    const osc = this.ctx.createOscillator();
    const gainNode = this.ctx.createGain();

    osc.type = type;
    osc.frequency.setValueAtTime(frequency, this.ctx.currentTime);
    
    gainNode.gain.setValueAtTime(vol, this.ctx.currentTime);
    gainNode.gain.exponentialRampToValueAtTime(0.001, this.ctx.currentTime + duration);

    osc.connect(gainNode);
    gainNode.connect(this.ctx.destination);

    osc.start();
    osc.stop(this.ctx.currentTime + duration);
  }

  playBounce() {
    this.playTone(300, 'sine', 0.2, 0.2);
  }

  playGoal() {
    if (!this.ctx) return;
    this.playTone(523.25, 'triangle', 0.1, 0.2); // C5
    setTimeout(() => this.playTone(659.25, 'triangle', 0.1, 0.2), 100); // E5
    setTimeout(() => this.playTone(783.99, 'triangle', 0.3, 0.2), 200); // G5
  }

  playCrash() {
    this.playTone(100, 'sawtooth', 0.3, 0.3);
  }

  playWhistle() {
    if (!this.ctx) return;
    this.playTone(1500, 'sine', 0.4, 0.2);
    setTimeout(() => this.playTone(1500, 'sine', 0.6, 0.3), 500);
  }

  playLevelUp() {
    if (!this.ctx) return;
    this.playTone(440, 'square', 0.1, 0.1);
    setTimeout(() => this.playTone(554.37, 'square', 0.1, 0.1), 100);
    setTimeout(() => this.playTone(659.25, 'square', 0.3, 0.1), 200);
  }

  playPowerUp() {
    this.playTone(523.25, 'sine', 0.1, 0.1); // C5
    setTimeout(() => this.playTone(659.25, 'sine', 0.15, 0.1), 100); // E5
    setTimeout(() => this.playTone(783.99, 'sine', 0.2, 0.2), 200); // G5
  }
}

// --- DIFFICULTY SCALER ---
export class DifficultyScaler {
  level: number = 1;
  scoreThreshold: number;
  increment: number;

  constructor(scoreThreshold: number = 10, increment: number = 1) {
    this.scoreThreshold = scoreThreshold;
    this.increment = increment;
  }

  update(currentScore: number): boolean {
    const newLevel = Math.floor(currentScore / this.scoreThreshold) + 1;
    if (newLevel > this.level) {
      this.level = newLevel;
      return true; // Level up!
    }
    return false;
  }

  reset() {
    this.level = 1;
  }

  get multiplier(): number {
    return 1 + (this.level - 1) * 0.2; // 20% increase per level
  }

  getSpeedMultiplier(score: number): number {
    const level = this.getLevel(score);
    return 1.0 + (level - 1) * 0.15;
  }

  getSpawnRate(score: number): number {
    const level = this.getLevel(score);
    return Math.max(800, 2000 - (level - 1) * 150);
  }

  getLevel(score: number): number {
    return Math.floor(score / 15) + 1;
  }
}

// --- PARTICLE SYSTEM ---
interface Particle {
  x: number;
  y: number;
  vx: number;
  vy: number;
  life: number;
  maxLife: number;
  color: string;
  size: number;
}

export class ParticleSystem {
  particles: Particle[] = [];

  emit(x: number, y: number, color: string, count: number = 20, speed: number = 5) {
    for (let i = 0; i < count; i++) {
      const angle = Math.random() * Math.PI * 2;
      const v = Math.random() * speed;
      this.particles.push({
        x,
        y,
        vx: Math.cos(angle) * v,
        vy: Math.sin(angle) * v,
        life: 1.0,
        maxLife: 1.0,
        color,
        size: Math.random() * 4 + 2,
      });
    }
  }

  explosion(x: number, y: number, color: string, count: number = 30, speed: number = 8) {
    this.emit(x, y, color, count, speed);
  }

  updateAndDraw(ctx: CanvasRenderingContext2D) {
    for (let i = this.particles.length - 1; i >= 0; i--) {
      const p = this.particles[i];
      p.x += p.vx;
      p.y += p.vy;
      p.life -= 0.02; // fade factor

      if (p.life <= 0) {
        this.particles.splice(i, 1);
        continue;
      }

      ctx.save();
      ctx.globalAlpha = p.life;
      ctx.fillStyle = p.color;
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    }
  }
}

// --- FLOATING TEXT SYSTEM ---
interface FloatingText {
  x: number;
  y: number;
  text: string;
  life: number;
  color: string;
  velocity: number;
  size: number;
}

export class FloatingTextSystem {
  texts: FloatingText[] = [];

  add(x: number, y: number, text: string, color: string = '#FFF', size: number = 24) {
    this.texts.push({ x, y, text, life: 1.0, color, velocity: 1.5, size } as any);
  }

  addSpecial(x: number, y: number, type: 'PERFECT' | 'COMBO' | 'CRITICAL', value?: string) {
    let color = '#FFF';
    let size = 28;
    let text = type as string;

    if (type === 'PERFECT') {
      color = '#fbbf24'; // Gold
      size = 36;
      text = 'PERFECT!';
    } else if (type === 'COMBO') {
      color = '#60a5fa'; // Blue
      size = 30;
      text = value ? `x${value} COMBO` : 'COMBO!';
    } else if (type === 'CRITICAL') {
      color = '#f87171'; // Red
      size = 40;
      text = 'CRITICAL!!';
    }

    this.add(x, y, text, color, size);
  }

  updateAndDraw(ctx: CanvasRenderingContext2D) {
    for (let i = this.texts.length - 1; i >= 0; i--) {
      const t = this.texts[i];
      t.y -= t.velocity;
      t.life -= 0.02;

      if (t.life <= 0) {
        this.texts.splice(i, 1);
        continue;
      }

      ctx.save();
      ctx.globalAlpha = t.life;
      ctx.fillStyle = t.color;
      ctx.font = `bold ${t.size || 24}px sans-serif`;
      ctx.textAlign = 'center';
      ctx.shadowColor = 'rgba(0,0,0,0.5)';
      ctx.shadowBlur = 4;
      ctx.fillText(t.text, t.x, t.y);
      ctx.restore();
    }
  }
}

// --- SCREEN SHAKE ---
export class ScreenShake {
  intensity: number = 0;

  trigger(intensity: number = 10) {
    this.intensity = intensity;
  }

  apply(ctx: CanvasRenderingContext2D) {
    if (this.intensity > 0) {
      const dx = (Math.random() - 0.5) * this.intensity;
      const dy = (Math.random() - 0.5) * this.intensity;
      ctx.translate(dx, dy);
      this.intensity *= 0.9; // decay
      if (this.intensity < 0.5) this.intensity = 0;
    }
  }
}

// --- COMMON DRAWING UTILS ---
export function drawSoccerBall(ctx: CanvasRenderingContext2D, x: number, y: number, radius: number, rotationAngles: number = 0, scaleY: number = 1) {
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(rotationAngles);
  ctx.scale(1, scaleY);
  
  // Base circle
  ctx.beginPath(); 
  ctx.arc(0, 0, radius, 0, Math.PI * 2);
  ctx.fillStyle = '#ffffff'; 
  ctx.fill();
  ctx.lineWidth = 2; 
  ctx.strokeStyle = '#333'; 
  ctx.stroke();
  
  // Soccer pattern (simplified pentagon/hexagon illusion)
  ctx.fillStyle = '#222'; 
  ctx.beginPath();
  for (let i = 0; i < 5; i++) {
    const a = (18 + i * 72) * Math.PI / 180;
    ctx.lineTo(Math.cos(a) * (radius * 0.45), -Math.sin(a) * (radius * 0.45));
  }
  ctx.closePath(); 
  ctx.fill();
  
  ctx.beginPath();
  for (let i = 0; i < 5; i++) {
    const a1 = (18 + i * 72) * Math.PI / 180;
    const a2 = (18 + (i+1) * 72) * Math.PI / 180;
    const innerX = Math.cos(a1) * (radius * 0.45);
    const innerY = -Math.sin(a1) * (radius * 0.45);
    const innerX2 = Math.cos(a2) * (radius * 0.45);
    const innerY2 = -Math.sin(a2) * (radius * 0.45);
    const outerX = Math.cos((a1+a2)/2) * radius;
    const outerY = -Math.sin((a1+a2)/2) * radius;
    
    ctx.moveTo(innerX, innerY);
    ctx.lineTo(outerX, outerY);
    ctx.lineTo(innerX2, innerY2);
    ctx.stroke();
  }
  
  ctx.restore();
}
