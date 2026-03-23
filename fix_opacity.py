import re
import sys

def replace_in_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Replace .withOpacity(x) with .withValues(alpha: x)
    new_content = re.sub(r'\.withOpacity\(([^)]+)\)', r'.withValues(alpha: \1)', content)
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(new_content)

files = [
    r'd:\Projects\SportsApp\lib\screens\home_dashboard.dart',
    r'd:\Projects\SportsApp\lib\screens\match_detail_screen.dart'
]

for f in files:
    replace_in_file(f)

print("Done")
