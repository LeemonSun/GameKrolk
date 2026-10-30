"""Local reproducible checks; no network and no user-save reset."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', type=Path)
    parser.add_argument('--gui', action='store_true', help='Also render and capture the real UI')
    parser.add_argument('--stress', action='store_true', help='Run nine ordinary-budget twenty-minute sessions')
    args = parser.parse_args()
    default = ROOT.parent / 'local/godot/Godot_v4.7.2-stable_win64_console.exe'
    engine = args.godot or Path(os.environ.get('GAMEKROLK_GODOT', str(default)))
    if not engine.is_file():
        print('Godot not found; pass --godot PATH', file=sys.stderr)
        return 2
    work = ROOT / 'work'
    work.mkdir(exist_ok=True)
    (work / '.gdignore').touch()
    json.loads((ROOT / 'data/game.json').read_text(encoding='utf-8'))
    cases = [('import', ['--headless', '--editor', '--import'])]
    cases += [(name, ['--headless', '--script', f'res://tests/{name}.gd']) for name in ['test_core', 'test_world', 'test_settlement', 'test_cycle', 'test_simulation', 'test_orders', 'test_logistics', 'test_crisis', 'test_personnel', 'test_tactics', 'test_lore_boundaries', 'test_spatial', 'test_soak']]
    if args.gui:
        cases.append(('test_world_ui', ['--script', 'res://tests/test_world_ui.gd']))
        cases.append(('test_menu', ['--script', 'res://tests/test_menu.gd']))
        cases.append(('test_care_ui', ['--script', 'res://tests/test_care_ui.gd']))
    if args.stress:
        cases.append(('test_session', ['--headless', '--script', 'res://tests/test_session.gd']))
    results = []
    for name, options in cases:
        command = [str(engine), '--path', str(ROOT), *options, '--log-file', str(work / f'{name}.log'), '--', '--test-mode']
        try:
            run = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300 if name == 'test_session' else 120)
            output = run.stdout.decode('utf-8', errors='replace')
            (work / f'{name}-console.log').write_text(output, encoding='utf-8')
            errors = [line for line in output.splitlines() if line.startswith(('ERROR:', 'SCRIPT ERROR:'))]
            passed = run.returncode == 0 and not errors
            results.append({'case': name, 'passed': passed, 'exit_code': run.returncode, 'errors': errors})
            print(f'{name}: {"PASS" if passed else "FAIL"}')
            for line in output.splitlines():
                if line.startswith(('CORE_TESTS', 'WORLD_TESTS', 'SETTLEMENT_TESTS', 'CYCLE_TESTS', 'SIMULATION_TESTS', 'ORDER_TESTS', 'LOGISTICS_TESTS', 'CRISIS_TESTS', 'PERSONNEL_TESTS', 'TACTICS_TESTS', 'LORE_TESTS', 'SPATIAL_TESTS', 'CARE_UI_TESTS', 'SOAK_TESTS', 'WORLD_UI_READY', 'MENU_TESTS', 'SESSION_TESTS', 'SESSION_RUN')):
                    print(line)
            if not passed:
                print(output[-6000:])
                break
        except subprocess.TimeoutExpired:
            results.append({'case': name, 'passed': False, 'error': 'timeout'})
            print(f'{name}: TIMEOUT')
            break
    (work / 'verification.json').write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
    return 0 if len(results) == len(cases) and all(r['passed'] for r in results) else 1

if __name__ == '__main__':
    raise SystemExit(main())
