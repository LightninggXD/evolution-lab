import os

filepath = 'src/StarterPlayer/StarterPlayerScripts/MainUI.client.lua'
with open(filepath, 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i in range(2950, 3050):
    if 'journalPaintDetail' in lines[i]:
        print(f"{i+1}: {lines[i].strip()}")