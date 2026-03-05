import React, { useState, useEffect } from 'react';
import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { Auth } from "./pages/Auth";
import { WorkspaceSelection } from "./pages/WorkspaceSelection";
import Index from "./pages/Index";
import NotFound from "./pages/NotFound";
import { supabase } from "@/integrations/supabase/client";
import type { User } from "@supabase/supabase-js";

const queryClient = new QueryClient();

interface Profile {
  display_name: string | null;
  email: string | null;
  employee_id: string | null;
  avatar_url: string | null;
}

interface Workspace {
  id: string;
  name: string;
  description: string | null;
  invite_code: string;
  owner_id: string;
  memberCount?: number;
  isOwner: boolean;
  role: string;
}

const App = () => {
  const [authUser, setAuthUser] = useState<User | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [selectedWorkspace, setSelectedWorkspace] = useState<Workspace | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const { data: { subscription } } = supabase.auth.onAuthStateChange(async (event, session) => {
      setAuthUser(session?.user ?? null);
      if (session?.user) {
        // Fetch profile with setTimeout to avoid deadlock
        setTimeout(async () => {
          const { data } = await supabase
            .from('profiles')
            .select('display_name, email, employee_id, avatar_url')
            .eq('user_id', session.user.id)
            .maybeSingle();
          setProfile(data);
        }, 0);
      } else {
        setProfile(null);
        setSelectedWorkspace(null);
      }
      setLoading(false);
    });

    supabase.auth.getSession().then(({ data: { session } }) => {
      setAuthUser(session?.user ?? null);
      if (session?.user) {
        supabase
          .from('profiles')
          .select('display_name, email, employee_id, avatar_url')
          .eq('user_id', session.user.id)
          .maybeSingle()
          .then(({ data }) => setProfile(data));
      }
      setLoading(false);
    });

    return () => subscription.unsubscribe();
  }, []);

  const handleLogout = async () => {
    await supabase.auth.signOut();
    setSelectedWorkspace(null);
  };

  const handleSelectWorkspace = (workspace: Workspace) => {
    setSelectedWorkspace(workspace);
  };

  const handleLeaveWorkspace = () => {
    setSelectedWorkspace(null);
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-purple-50 via-blue-50 to-indigo-100 flex items-center justify-center">
        <p className="text-gray-600">Loading...</p>
      </div>
    );
  }

  // Build user object from auth + profile
  const user = authUser ? {
    id: authUser.id,
    email: authUser.email,
    name: profile?.display_name || authUser.email?.split('@')[0] || 'User',
    employeeId: profile?.employee_id || `EMP-${authUser.id.slice(0, 6).toUpperCase()}`,
    avatar: (profile?.display_name || authUser.email?.split('@')[0] || 'U').split(' ').map(n => n[0]).join('').toUpperCase().slice(0, 2),
  } : null;

  if (!user) {
    return (
      <QueryClientProvider client={queryClient}>
        <TooltipProvider>
          <Toaster />
          <Sonner />
          <Auth />
        </TooltipProvider>
      </QueryClientProvider>
    );
  }

  if (!selectedWorkspace) {
    return (
      <QueryClientProvider client={queryClient}>
        <TooltipProvider>
          <Toaster />
          <Sonner />
          <WorkspaceSelection
            user={user}
            onSelectWorkspace={handleSelectWorkspace}
            onLogout={handleLogout}
          />
        </TooltipProvider>
      </QueryClientProvider>
    );
  }

  return (
    <QueryClientProvider client={queryClient}>
      <TooltipProvider>
        <Toaster />
        <Sonner />
        <BrowserRouter>
          <Routes>
            <Route
              path="/"
              element={
                <Index
                  user={user}
                  workspace={selectedWorkspace}
                  onLogout={handleLogout}
                  onLeaveWorkspace={handleLeaveWorkspace}
                />
              }
            />
            <Route path="*" element={<NotFound />} />
          </Routes>
        </BrowserRouter>
      </TooltipProvider>
    </QueryClientProvider>
  );
};

export default App;
