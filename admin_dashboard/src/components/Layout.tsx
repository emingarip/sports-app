import { Outlet, NavLink } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { LayoutDashboard, Users, Trophy, LogOut, Activity, Bot, Megaphone, ShoppingBag, Settings as SettingsIcon, Bug, MessageSquare } from 'lucide-react';

export default function Layout() {
  const handleLogout = async () => {
    await supabase.auth.signOut();
  };

  return (
    <div className="flex h-screen bg-muted/20">
      {/* Sidebar */}
      <aside className="w-64 bg-card text-card-foreground border-r border-border flex flex-col">
        <div className="h-16 flex items-center px-6 border-b border-border">
          <Trophy className="w-6 h-6 text-primary mr-2" />
          <h1 className="text-xl font-bold tracking-tight">SportsApp Admin</h1>
        </div>
        
        <nav className="flex-1 px-4 flex flex-col gap-2 pt-6">
          <NavLink
            to="/"
            className={({ isActive }) =>
              `flex items-center gap-3 px-3 py-2 rounded-md transition-colors ${
                isActive ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'
              }`
            }
          >
            <LayoutDashboard className="w-5 h-5" />
            <span>Genel Bakış</span>
          </NavLink>
          <NavLink
            to="/users"
            className={({ isActive }) =>
              `flex items-center gap-3 px-3 py-2 rounded-md transition-colors ${
                isActive ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'
              }`
            }
          >
             <Users className="w-5 h-5" />
             <span>Kullanıcılar</span>
          </NavLink>
          <NavLink
            to="/matches"
            className={({ isActive }) =>
              `flex items-center gap-3 px-3 py-2 rounded-md transition-colors ${
                isActive ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'
              }`
            }
          >
             <Activity className="w-5 h-5" />
             <span>Canlı Maçlar</span>
          </NavLink>
          <NavLink
            to="/bots"
            className={({ isActive }) =>
              `flex items-center gap-3 px-3 py-2 rounded-md transition-colors ${
                isActive ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'
              }`
            }
          >
             <Bot className="w-5 h-5" />
             <span>Simülasyon Botları</span>
          </NavLink>
          <NavLink
            to="/announcements"
            className={({ isActive }) =>
              `flex items-center gap-3 px-3 py-2 rounded-md transition-colors ${
                isActive ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'
              }`
            }
          >
             <Megaphone className="w-5 h-5" />
             <span>Duyurular</span>
          </NavLink>
          <NavLink
            to="/products"
            className={({ isActive }) =>
              `flex items-center gap-3 px-3 py-2 rounded-md transition-colors ${
                isActive ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'
              }`
            }
          >
             <ShoppingBag className="w-5 h-5" />
             <span>Mağaza Ürünleri</span>
          </NavLink>
          <NavLink
            to="/settings"
            className={({ isActive }) =>
              `flex items-center gap-3 px-3 py-2 rounded-md transition-colors ${
                isActive ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'
              }`
            }
          >
             <SettingsIcon className="w-5 h-5" />
             <span>Ayarlar</span>
          </NavLink>
          <NavLink
            to="/feedbacks"
            className={({ isActive }) =>
              `flex items-center gap-3 px-3 py-2 rounded-md transition-colors ${
                isActive ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'
              }`
            }
          >
             <Bug className="w-5 h-5" />
             <span>Hata Bildirimleri</span>
          </NavLink>
          <NavLink
            to="/support-chat"
            className={({ isActive }) =>
              `flex items-center gap-3 px-3 py-2 rounded-md transition-colors ${
                isActive ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'
              }`
            }
          >
             <MessageSquare className="w-5 h-5" />
             <span>Destek Mesajları</span>
          </NavLink>
        </nav>

        <div className="p-4 border-t border-border">
          <button 
            onClick={handleLogout}
            className="flex w-full items-center gap-3 px-3 py-2 rounded-md transition-colors hover:bg-destructive/10 text-destructive"
          >
            <LogOut className="w-5 h-5" />
            <span>Çıkış Yap</span>
          </button>
        </div>
      </aside>

      {/* Main Content */}
      <main className="flex-1 overflow-y-auto">
        <header className="h-16 flex items-center justify-between px-8 bg-card border-b border-border">
          <h2 className="text-sm font-medium text-muted-foreground">Yönetim Paneli</h2>
        </header>
        <div className="p-8">
           <Outlet />
        </div>
      </main>
    </div>
  );
}
