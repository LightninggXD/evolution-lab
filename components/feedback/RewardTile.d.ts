import React from 'react';
export interface RewardTileProps {
  day: number;
  reward: { icon: string; label: string; sub?: string };
  bonus?: string;
  claimed?: boolean;
  /** Day-7 style grand-prize tile spanning 2 rows, dark background with radial shine */
  big?: boolean;
  /** CSS background override (gradient or color) */
  bg?: string;
  /** Green "ready to claim today" highlight state */
  highlight?: boolean;
}
