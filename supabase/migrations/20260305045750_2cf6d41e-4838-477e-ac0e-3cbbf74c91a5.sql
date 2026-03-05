
-- Create function to update timestamps
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- PROFILES TABLE
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT,
  email TEXT,
  employee_id TEXT,
  avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Profiles viewable by authenticated users" ON public.profiles
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Users can insert own profile" ON public.profiles
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own profile" ON public.profiles
  FOR UPDATE TO authenticated USING (auth.uid() = user_id);

CREATE TRIGGER update_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (user_id, email, display_name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data ->> 'display_name', split_part(NEW.email, '@', 1))
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- WORKSPACES TABLE
CREATE TABLE public.workspaces (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  invite_code TEXT NOT NULL UNIQUE DEFAULT upper(substr(md5(random()::text), 1, 12)),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;

CREATE TRIGGER update_workspaces_updated_at
  BEFORE UPDATE ON public.workspaces
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- WORKSPACE MEMBERS TABLE
CREATE TABLE public.workspace_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'team-lead', 'member')),
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(workspace_id, user_id)
);

ALTER TABLE public.workspace_members ENABLE ROW LEVEL SECURITY;

-- Security definer function to check workspace membership
CREATE OR REPLACE FUNCTION public.is_workspace_member(_user_id UUID, _workspace_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE user_id = _user_id AND workspace_id = _workspace_id
  )
$$;

-- Workspace policies
CREATE POLICY "Members can view their workspaces" ON public.workspaces
  FOR SELECT TO authenticated USING (public.is_workspace_member(auth.uid(), id));

CREATE POLICY "Authenticated users can create workspaces" ON public.workspaces
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "Owners can update their workspaces" ON public.workspaces
  FOR UPDATE TO authenticated USING (auth.uid() = owner_id);

CREATE POLICY "Owners can delete their workspaces" ON public.workspaces
  FOR DELETE TO authenticated USING (auth.uid() = owner_id);

-- Workspace members policies
CREATE POLICY "Members can view workspace members" ON public.workspace_members
  FOR SELECT TO authenticated USING (public.is_workspace_member(auth.uid(), workspace_id));

CREATE POLICY "Members can insert themselves" ON public.workspace_members
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Members can leave workspaces" ON public.workspace_members
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- TASKS TABLE
CREATE TABLE public.tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  description TEXT,
  assignee TEXT,
  assignee_email TEXT,
  due_date DATE,
  due_time TIME,
  status TEXT NOT NULL DEFAULT 'todo' CHECK (status IN ('todo', 'inprogress', 'done')),
  points INTEGER DEFAULT 25,
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Workspace members can view tasks" ON public.tasks
  FOR SELECT TO authenticated USING (public.is_workspace_member(auth.uid(), workspace_id));

CREATE POLICY "Workspace members can create tasks" ON public.tasks
  FOR INSERT TO authenticated WITH CHECK (public.is_workspace_member(auth.uid(), workspace_id) AND auth.uid() = created_by);

CREATE POLICY "Workspace members can update tasks" ON public.tasks
  FOR UPDATE TO authenticated USING (public.is_workspace_member(auth.uid(), workspace_id));

CREATE POLICY "Task creators can delete tasks" ON public.tasks
  FOR DELETE TO authenticated USING (auth.uid() = created_by);

CREATE TRIGGER update_tasks_updated_at
  BEFORE UPDATE ON public.tasks
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- MEETINGS TABLE
CREATE TABLE public.meetings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  participant_emails TEXT[],
  meeting_date DATE NOT NULL,
  meeting_time TIME NOT NULL,
  duration INTEGER DEFAULT 30,
  type TEXT DEFAULT 'video' CHECK (type IN ('video', 'audio')),
  status TEXT DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'ongoing', 'completed')),
  notes TEXT,
  recordings TEXT[],
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.meetings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Workspace members can view meetings" ON public.meetings
  FOR SELECT TO authenticated USING (public.is_workspace_member(auth.uid(), workspace_id));

CREATE POLICY "Workspace members can create meetings" ON public.meetings
  FOR INSERT TO authenticated WITH CHECK (public.is_workspace_member(auth.uid(), workspace_id) AND auth.uid() = created_by);

CREATE POLICY "Workspace members can update meetings" ON public.meetings
  FOR UPDATE TO authenticated USING (public.is_workspace_member(auth.uid(), workspace_id));

CREATE POLICY "Meeting creators can delete meetings" ON public.meetings
  FOR DELETE TO authenticated USING (auth.uid() = created_by);

CREATE TRIGGER update_meetings_updated_at
  BEFORE UPDATE ON public.meetings
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- CHAT MESSAGES TABLE
CREATE TABLE public.chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  content TEXT NOT NULL,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  type TEXT NOT NULL DEFAULT 'text' CHECK (type IN ('text', 'file')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Workspace members can view messages" ON public.chat_messages
  FOR SELECT TO authenticated USING (public.is_workspace_member(auth.uid(), workspace_id));

CREATE POLICY "Workspace members can send messages" ON public.chat_messages
  FOR INSERT TO authenticated WITH CHECK (public.is_workspace_member(auth.uid(), workspace_id) AND auth.uid() = sender_id);

-- MOOD CHECKS TABLE
CREATE TABLE public.mood_checks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  mood TEXT NOT NULL CHECK (mood IN ('great', 'good', 'okay', 'stressed', 'overwhelmed')),
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.mood_checks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own mood checks" ON public.mood_checks
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE POLICY "Users can create own mood checks" ON public.mood_checks
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

-- INDEXES
CREATE INDEX idx_tasks_workspace ON public.tasks(workspace_id);
CREATE INDEX idx_tasks_status ON public.tasks(status);
CREATE INDEX idx_meetings_workspace ON public.meetings(workspace_id);
CREATE INDEX idx_chat_messages_workspace ON public.chat_messages(workspace_id, created_at);
CREATE INDEX idx_workspace_members_user ON public.workspace_members(user_id);
CREATE INDEX idx_workspace_members_workspace ON public.workspace_members(workspace_id);
