import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { useEffect, useState } from 'react';
import { supabase } from './lib/supabase';
import type { Session } from '@supabase/supabase-js';

import Layout from './components/Layout';
import Dashboard from './pages/Dashboard';
import Login from './pages/Login';
import Users from './pages/Users';
import Matches from './pages/Matches';
import Bots from './pages/Bots';
import Announcements from './pages/Announcements';
import Products from './pages/Products';
import Themes from './pages/Themes';
import Settings from './pages/Settings';
import Feedbacks from './pages/Feedbacks';
import SupportChat from './pages/SupportChat';

function App() {
  const [session, setSession] = useState<Session | null>(null);
  const [isAdmin, setIsAdmin] = useState(false);
  const [loading, setLoading] = useState(true);
  const [accessError, setAccessError] = useState('');

  // Authorisation used to be a client-side string test in Login.tsx
  // (`email.includes('emin')`), which any visitor could step over from the
  // browser console. The real gate is the users.is_admin column plus RLS; this
  // check makes the UI agree with it instead of inventing its own rule.
  useEffect(() => {
    let active = true;

    async function resolveAdmin(next: Session | null) {
      if (!next) {
        if (!active) return;
        setSession(null);
        setIsAdmin(false);
        setLoading(false);
        return;
      }

      const { data, error } = await supabase
        .from('users')
        .select('is_admin')
        .eq('id', next.user.id)
        .maybeSingle();

      if (!active) return;

      if (error || !data?.is_admin) {
        setAccessError('Bu hesabın yönetim paneli yetkisi yok.');
        setIsAdmin(false);
        setSession(null);
        await supabase.auth.signOut();
      } else {
        setAccessError('');
        setIsAdmin(true);
        setSession(next);
      }
      setLoading(false);
    }

    supabase.auth.getSession().then(({ data: { session } }) => {
      void resolveAdmin(session);
    });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, next) => {
      setLoading(true);
      void resolveAdmin(next);
    });

    return () => {
      active = false;
      subscription.unsubscribe();
    };
  }, []);

  if (loading) {
    return <div className="h-screen w-screen flex items-center justify-center bg-background text-foreground">Yükleniyor...</div>;
  }

  return (
    <Router>
      <Routes>
        <Route
          path="/login"
          element={
            !session || !isAdmin ? (
              <Login accessError={accessError} />
            ) : (
              <Navigate to="/" />
            )
          }
        />
        
        {/* Protected Routes */}
        <Route element={session && isAdmin ? <Layout /> : <Navigate to="/login" />}>
          <Route path="/" element={<Dashboard _session={session} />} />
          <Route path="users" element={<Users />} />
          <Route path="matches" element={<Matches />} />
          <Route path="bots" element={<Bots />} />
          <Route path="announcements" element={<Announcements />} />
          <Route path="products" element={<Products />} />
          <Route path="themes" element={<Themes />} />
          <Route path="settings" element={<Settings />} />
          <Route path="feedbacks" element={<Feedbacks />} />
          <Route path="support-chat" element={<SupportChat />} />
        </Route>
      </Routes>
    </Router>
  );
}

export default App;
