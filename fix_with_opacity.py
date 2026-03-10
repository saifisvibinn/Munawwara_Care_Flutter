"""
Replaces all deprecated .withOpacity(x) calls with .withValues(alpha: x)
across every .dart file under the lib/ directory.
Handles nested parentheses correctly (e.g. .withOpacity(x.clamp(0.0, 1.0))).
"""

import os

PATTERN = '.withOpacity('


def replace_with_opacity(content: str) -> tuple[str, int]:
    parts = []
    count = 0
    i = 0
    while i < len(content):
        idx = content.find(PATTERN, i)
        if idx == -1:
            parts.append(content[i:])
            break
        parts.append(content[i:idx])
        # advance past '.withOpacity('
        i = idx + len(PATTERN)
        # find matching closing paren, respecting nesting
        depth = 1
        arg_start = i
        while i < len(content) and depth > 0:
            ch = content[i]
            if ch == '(':
                depth += 1
            elif ch == ')':
                depth -= 1
                if depth == 0:
                    break
            i += 1
        arg = content[arg_start:i]
        parts.append(f'.withValues(alpha: {arg})')
        i += 1  # skip the matched closing ')'
        count += 1
    return ''.join(parts), count


def main():
    lib_dir = os.path.join(os.path.dirname(__file__), 'lib')
    total_files = 0
    total_replacements = 0

    for root, dirs, files in os.walk(lib_dir):
        # skip generated / build output dirs
        dirs[:] = [d for d in dirs if d not in ('build', '.dart_tool')]
        for filename in files:
            if not filename.endswith('.dart'):
                continue
            filepath = os.path.join(root, filename)
            with open(filepath, 'r', encoding='utf-8') as f:
                original = f.read()
            if PATTERN not in original:
                continue
            modified, count = replace_with_opacity(original)
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(modified)
            rel = os.path.relpath(filepath, os.path.dirname(__file__))
            print(f'  [{count:3d}] {rel}')
            total_files += 1
            total_replacements += count

    print(f'\nDone — replaced {total_replacements} occurrence(s) across {total_files} file(s).')


if __name__ == '__main__':
    main()
