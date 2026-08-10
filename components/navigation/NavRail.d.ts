import React from 'react';
/**
 * @startingPoint section="Components" subtitle="Vertical icon nav rail (Zones, Pets, Shop, Rebirth…)" viewport="200x460"
 */
export interface NavRailItem { icon: React.ReactNode; label: string; }
export interface NavRailProps {
  items: NavRailItem[];
  activeIndex?: number;
  onSelect?: (i: number) => void;
}
