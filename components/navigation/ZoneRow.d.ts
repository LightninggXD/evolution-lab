import React from 'react';
export interface ZoneRowProps {
  icon: React.ReactNode;
  name: string;
  requirement?: string;
  unlocked?: boolean;
  onGo?: () => void;
}
