"""Game profiles (games/<id>/game.toml): the one place game-specific values live.

usage: python -I tools/pipeline/profile.py [<game id>]     prints the profile (or all profiles) as JSON
       (the PowerShell pipeline and the launcher read profiles through this)
"""
import json
import os
import sys
import tomllib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GAMES = os.path.join(ROOT, 'games')


def load(game_id: str) -> dict:
    path = os.path.join(GAMES, game_id, 'game.toml')
    if not os.path.isfile(path):
        raise KeyError(f'no game profile {game_id} ({path})')
    with open(path, 'rb') as f:
        profile = tomllib.load(f)
    profile['_dir'] = os.path.dirname(path)
    return profile


def all_profiles() -> list:
    return [load(g) for g in sorted(os.listdir(GAMES)) if os.path.isfile(os.path.join(GAMES, g, 'game.toml'))]


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding="utf-8")
    out = load(sys.argv[1]) if len(sys.argv) > 1 else all_profiles()
    json.dump(out, sys.stdout, ensure_ascii=False, indent=1)
