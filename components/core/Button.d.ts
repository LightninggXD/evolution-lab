import React from 'react';
export interface ButtonProps {
  children: React.ReactNode;
  /** Visual style — primary(green action), secondary(dark neutral), locked(gray, disabled look), evolve(purple), danger(red) */
  variant?: 'primary' | 'secondary' | 'locked' | 'evolve' | 'danger';
  size?: 'sm' | 'md' | 'lg';
  disabled?: boolean;
  icon?: React.ReactNode;
  onClick?: () => void;
}
