import { useState } from 'react';
import { supabase } from '../lib/supabase';
import { Trophy } from 'lucide-react';

export default function Login() {
  const [email, setEmail] = useState('');
  const [token, setToken] = useState('');
  const [step, setStep] = useState<'email' | 'otp'>('email');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError('');

    if (!email.toLowerCase().includes('emin')) {
        setError('Erişim reddedildi: Bu e-posta adresinin yetkisi yok.');
        setLoading(false);
        return;
    }

    if (step === 'email') {
      const { error } = await supabase.auth.signInWithOtp({
        email,
      });

      if (error) {
        setError(error.message);
      } else {
        setStep('otp');
      }
    } else if (step === 'otp') {
      const { error } = await supabase.auth.verifyOtp({
        email,
        token,
        type: 'email'
      });

      if (error) {
        setError('Hatalı kod: ' + error.message);
      }
    }
    setLoading(false);
  };

  return (
    <div className="min-h-screen bg-muted flex flex-col justify-center items-center p-4">
      <div className="max-w-md w-full bg-card rounded-xl shadow-lg border border-border p-8 text-card-foreground">
        <div className="flex flex-col items-center mb-8">
          <div className="w-12 h-12 bg-primary text-primary-foreground rounded-full flex items-center justify-center mb-4">
            <Trophy className="w-6 h-6" />
          </div>
          <h2 className="text-2xl font-bold">SportsApp Yönetim</h2>
          <p className="text-sm text-muted-foreground mt-2">Giriş yapmak için bilgilerinizi girin</p>
        </div>

        {error && (
          <div className="bg-destructive/10 text-destructive text-sm p-3 rounded-md mb-4 border border-destructive/20">
            {error}
          </div>
        )}

        {step === 'otp' && !error && (
          <div className="bg-emerald-500/10 text-emerald-500 text-sm p-4 rounded-md mb-6 border border-emerald-500/20">
            <strong>Doğrulama Kodu Gönderildi!</strong> Lütfen e-posta kutunuzu kontrol edin.
          </div>
        )}

        <form onSubmit={handleLogin} className="space-y-4">
          {step === 'email' ? (
            <div>
              <label className="block text-sm font-medium mb-1">E-posta</label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="w-full border border-border bg-background rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary h-10 transition-colors"
                placeholder="admin@example.com"
                required
              />
            </div>
          ) : (
            <div>
              <label className="block text-sm font-medium mb-1">8 Haneli Doğrulama Kodu</label>
              <input
                type="text"
                value={token}
                onChange={(e) => setToken(e.target.value)}
                className="w-full border border-border bg-background rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary h-10 transition-colors text-center tracking-widest text-lg"
                placeholder="00000000"
                maxLength={8}
                required
              />
              <p className="text-xs text-muted-foreground mt-2 text-center">
                E-postanıza gönderilen 8 haneli kodu girin.
              </p>
            </div>
          )}

          <button
            type="submit"
            disabled={loading}
            className="w-full bg-primary text-primary-foreground h-10 rounded-md font-medium transition-colors hover:bg-primary/90 disabled:opacity-50 mt-4"
          >
            {loading ? 'Bekleniyor...' : step === 'email' ? 'Doğrulama Kodu Gönder' : 'Giriş Yap'}
          </button>
        </form>
      </div>
    </div>
  );
}
