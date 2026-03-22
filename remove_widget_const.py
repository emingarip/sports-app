import os
import re

def strip_widget_const(folder):
    count = 0
    for root, dirs, files in os.walk(folder):
        for file in files:
            if file.endswith('.dart'):
                filepath = os.path.join(root, file)
                with open(filepath, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                new_content = re.sub(r'\bconst\s+(?=[A-Z])', '', content)
                
                if new_content != content:
                    with open(filepath, 'w', encoding='utf-8') as f:
                        f.write(new_content)
                    count += 1
    print(f"Modified {count} files.")

if __name__ == '__main__':
    strip_widget_const('lib')
