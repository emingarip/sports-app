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

function App() {
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
      setLoading(false);
    });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session);
    });

    return () => subscription.unsubscribe();
  }, []);

  if (loading) {
    return <div className="h-screen w-screen flex items-center justify-center bg-background text-foreground">Yükleniyor...</div>;
  }

  return (
    <Router>
      <Routes>
        <Route path="/login" element={!session ? <Login /> : <Navigate to="/" />} />
        
        {/* Protected Routes */}
        <Route element={session ? <Layout /> : <Navigate to="/login" />}>
          <Route path="/" element={<Dashboard _session={session} />} />
          <Route path="users" element={<Users />} />
          <Route path="matches" element={<Matches />} />
          <Route path="bots" element={<Bots />} />
          <Route path="announcements" element={<Announcements />} />
          <Route path="products" element={<Products />} />
        </Route>
      </Routes>
    </Router>
  );
}

export default App;
