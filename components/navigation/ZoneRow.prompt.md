Row in a zone/world select list — locked zones show a requirement and a gray lock button, unlocked ones get a green Go button.

```jsx
<ZoneRow icon="🌲" name="Forest" unlocked onGo={go} />
<ZoneRow icon="🏜️" name="Desert" requirement="Bacteria" />
```
