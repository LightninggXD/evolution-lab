import os

filepath = 'src/StarterPlayer/StarterPlayerScripts/MainUI.client.lua'
with open(filepath, 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if 'journalPaintDetail' in line:
        print(f"{i+1}: {line.strip()}")