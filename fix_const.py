import subprocess
import re

def fix_const_errors():
    for i in range(10):  # Loop up to 10 times to resolve nested consts
        print(f"--- Pass {i+1} ---")
        result = subprocess.run('flutter analyze', capture_output=True, text=True, shell=True)
        if result.returncode == 0:
            print("No errors!")
            break

        lines = result.stdout.split('\n')
        
        errors_fixed = 0
        for line in lines:
            if 'lib/' in line and ('.dart:' in line):
                parts = line.split(' • ')
                if len(parts) >= 3:
                    file_info = parts[-2].strip()  # e.g., lib/widgets/match_card.dart:38:17
                    if ':' in file_info:
                        file_path, line_no, col = file_info.split(':')
                        line_no = int(line_no)
                        
                        # read file
                        try:
                            with open(file_path, 'r', encoding='utf-8') as f:
                                file_lines = f.readlines()
                            
                            if 0 <= line_no - 1 < len(file_lines):
                                original = file_lines[line_no - 1]
                                # Remove 'const ' if present
                                modified = re.sub(r'\bconst\s+', '', original)
                                if modified != original:
                                    file_lines[line_no - 1] = modified
                                    with open(file_path, 'w', encoding='utf-8') as f:
                                        f.writelines(file_lines)
                                    errors_fixed += 1
                        except Exception as e:
                            pass

        if errors_fixed == 0:
            print("No const errors could be fixed in this pass.")
            print(result.stdout)
            break
        print(f"Fixed {errors_fixed} const errors.")

if __name__ == '__main__':
    fix_const_errors()
