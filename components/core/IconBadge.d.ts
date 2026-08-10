import React from 'react';
export interface IconBadgeProps {
  icon: React.ReactNode;
  label: string;
  tag?: { label: string; variant?: 'new' | 'op' | 'free' | 'limited' };
  timer?: string;
  size?: number;
  /** Cycles through the accent palette + alternating tilt for a playful look */
  index?: number;
}
