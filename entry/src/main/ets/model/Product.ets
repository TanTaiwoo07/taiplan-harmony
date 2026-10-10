export interface FeatureSettings { focus: boolean; habits: boolean; countdowns: boolean; ai: boolean; }
export interface FocusOptions { work: number; shortBreak: number; longBreak: number; cycles: number; }
export interface FocusSession {
  id: string; taskId: string; title: string; phase: string; status: string;
  startedAt: number; resumedAt: number; targetSeconds: number; elapsedSeconds: number; finishedAt: number;
}
export interface Habit {
  reminderMinute?: number;
  id: string; title: string; createdDate: string; weekdays: number[]; weeklyTarget: number; dailyTarget: number;
  checks: HabitCheck[];
}
export interface HabitCheck { date: string; count: number; updatedAt: number; }
export interface Countdown { id: string; title: string; date: string; annual: boolean; pinned: boolean; category: string; reminderDays?: number; }
export interface ProductState {
  workStart?: number; workEnd?: number;
  version: number; features: FeatureSettings; focusOptions: FocusOptions;
  sessions: FocusSession[]; habits: Habit[]; countdowns: Countdown[];
}
