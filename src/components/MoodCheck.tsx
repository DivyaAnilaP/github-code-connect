import React, { useState, useEffect } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Smile, Meh, Frown, Heart, Coffee, Zap } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';

interface MoodEntry {
  id: string;
  mood: string;
  note: string | null;
  created_at: string;
}

interface MoodCheckProps { user: any; }

export const MoodCheck: React.FC<MoodCheckProps> = ({ user }) => {
  const [currentMood, setCurrentMood] = useState<string>('');
  const [note, setNote] = useState<string>('');
  const [moodHistory, setMoodHistory] = useState<MoodEntry[]>([]);
  const [loading, setLoading] = useState(true);

  const moods = [
    { id: 'great', icon: Smile, label: 'Great', color: 'bg-green-100 text-green-600' },
    { id: 'good', icon: Smile, label: 'Good', color: 'bg-blue-100 text-blue-600' },
    { id: 'okay', icon: Meh, label: 'Okay', color: 'bg-yellow-100 text-yellow-600' },
    { id: 'stressed', icon: Frown, label: 'Stressed', color: 'bg-red-100 text-red-600' },
    { id: 'overwhelmed', icon: Coffee, label: 'Overwhelmed', color: 'bg-purple-100 text-purple-600' },
  ];

  useEffect(() => { fetchMoods(); }, []);

  const fetchMoods = async () => {
    try {
      const { data, error } = await supabase
        .from('mood_checks')
        .select('*')
        .eq('user_id', user.id)
        .order('created_at', { ascending: false })
        .limit(10);
      if (error) throw error;
      setMoodHistory(data || []);
    } catch (error) {
      console.error('Error fetching moods:', error);
    } finally { setLoading(false); }
  };

  const submitMood = async () => {
    if (!currentMood) return;
    try {
      const { data, error } = await supabase.from('mood_checks').insert({
        user_id: user.id,
        mood: currentMood,
        note: note.trim() || null,
      }).select().single();
      if (error) throw error;
      setMoodHistory(prev => [data, ...prev]);
      setCurrentMood('');
      setNote('');
      toast({ title: "Mood Recorded! 💚", description: "Thanks for checking in." });
    } catch (error) {
      console.error('Error saving mood:', error);
      toast({ title: "Error", description: "Failed to save mood", variant: "destructive" });
    }
  };

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader><CardTitle className="flex items-center gap-2"><Heart className="text-pink-500" size={24} />Daily Mood Check</CardTitle></CardHeader>
        <CardContent className="space-y-4">
          <div><h4 className="font-medium mb-3">How are you feeling today?</h4>
            <div className="grid grid-cols-3 md:grid-cols-5 gap-2">
              {moods.map(mood => { const Icon = mood.icon; return (
                <button key={mood.id} onClick={() => setCurrentMood(mood.id)} className={`p-3 rounded-lg border-2 transition-all ${currentMood === mood.id ? 'border-purple-500 bg-purple-50' : 'border-gray-200 hover:border-purple-300'}`}>
                  <Icon size={20} className={`mx-auto mb-1 ${mood.color.split(' ')[1]}`} /><p className="text-xs font-medium">{mood.label}</p>
                </button>
              ); })}
            </div>
          </div>
          <textarea placeholder="Any notes about your day? (optional)" value={note} onChange={(e) => setNote(e.target.value)} className="w-full p-2 border rounded-md" rows={2} />
          <Button onClick={submitMood} disabled={!currentMood} className="w-full bg-gradient-to-r from-pink-500 to-purple-500">Submit Mood Check</Button>
        </CardContent>
      </Card>
      <Card>
        <CardHeader><CardTitle>Your Mood History</CardTitle></CardHeader>
        <CardContent>
          {loading && <p className="text-gray-500">Loading...</p>}
          {!loading && moodHistory.length === 0 && <p className="text-gray-500 text-center py-4">No mood entries yet.</p>}
          <div className="space-y-3">
            {moodHistory.map(entry => {
              const mood = moods.find(m => m.id === entry.mood);
              const Icon = mood?.icon || Smile;
              return (
                <div key={entry.id} className="flex items-center gap-3 p-2 bg-gray-50 rounded-lg">
                  <Icon size={16} /><div className="flex-1"><span className="font-medium capitalize">{entry.mood}</span><span className="text-sm text-gray-600 ml-2">{new Date(entry.created_at).toLocaleString()}</span>{entry.note && <p className="text-sm text-gray-500 mt-1">{entry.note}</p>}</div>
                </div>
              );
            })}
          </div>
        </CardContent>
      </Card>
    </div>
  );
};
