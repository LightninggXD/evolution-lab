import React from 'react';
export interface StatCardProps {
  icon?: React.ReactNode;
  label: string;
  level?: number;
  cost?: number | string;
  costIcon?: string;
  wide?: boolean;
}
