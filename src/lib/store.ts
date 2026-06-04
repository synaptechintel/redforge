import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import type { Operation } from './sidecar';

export interface KillChainPlan {
  name: string;
  description: string;
  steps: Array<{
    phase: string;
    technique_id: string;
    description: string;
    suggested_command?: string;
  }>;
}

interface RedForgeState {
  activeOperation: Operation | null;
  setActiveOperation: (op: Operation | null) => void;

  // For clean kill chain import from Assistant
  pendingKillChainPlan: KillChainPlan | null;
  setPendingKillChainPlan: (plan: KillChainPlan | null) => void;

  // Simple signal for when assets have been updated (used to trigger suggestion refreshes)
  assetUpdateTick: number;
  bumpAssetUpdate: () => void;
}

export const useRedForgeStore = create<RedForgeState>()(
  persist(
    (set) => ({
      activeOperation: null,
      setActiveOperation: (op) => set({ activeOperation: op }),

      pendingKillChainPlan: null,
      setPendingKillChainPlan: (plan) => set({ pendingKillChainPlan: plan }),

      assetUpdateTick: 0,
      bumpAssetUpdate: () => set((state) => ({ assetUpdateTick: state.assetUpdateTick + 1 })),
    }),
    {
      name: 'redforge-active-operation',
      partialize: (state) => ({ activeOperation: state.activeOperation }),
    }
  )
);
