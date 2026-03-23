import re
import sys
import glob

def replace_in_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Replace .withOpacity(x) with .withValues(alpha: x)
    new_content = re.sub(r'\.withOpacity\(([^)]+)\)', r'.withValues(alpha: \1)', content)
    
    if new_content != content:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"Fixed {filepath}")

files = [
    r'd:\Projects\SportsApp\lib\screens\onboarding\pick_teams_screen.dart',
    r'd:\Projects\SportsApp\lib\screens\onboarding\pick_competitions_screen.dart',
    r'd:\Projects\SportsApp\lib\screens\onboarding\onboarding_ready_screen.dart',
    r'd:\Projects\SportsApp\lib\providers\onboarding_provider.dart'
]

for f in files:
    replace_in_file(f)

print("Done")
