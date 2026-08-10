import React from 'react';
export interface ModalProps {
  title: string;
  icon?: string;
  onClose?: () => void;
  accent?: 'gold' | 'green' | 'purple' | 'blue';
  children?: React.ReactNode;
  footer?: React.ReactNode;
  /** CSS background (usually a gradient) — renders the title in a full-width colored banner bar instead of floating text */
  banner?: string;
}
