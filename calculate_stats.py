#! /usr/bin/env python3

from pathlib import Path
import collections

if not Path(".report").exists():
  print("Empty reactions")
  exit(0)

for username in Path(".report").iterdir():
  reactions = (username / "reactions").read_text().split()
  stats = dict()

  for e in reactions: stats[e] = stats.get(e, 0) + 1

  if len(stats.keys()) == 0:
    continue
    
  print(username.name.replace('"', ""), ":")
  for k, v in stats.items():
    print("  ", k.replace('"', ''), " - ", v)
