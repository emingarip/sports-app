import subprocess
import re

def fix_const_errors():
    for i in range(15):
        print(f"--- Pass {i+1} ---")
        process = subprocess.Popen('flutter analyze', shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        stdout_data, _ = process.communicate()
        output = stdout_data.decode('utf-8', errors='replace')
        
        if process.returncode == 0:
            print("No errors!")
            break
            
        lines = output.split('\n')
        errors_fixed = 0
        for line in lines:
            match = re.search(r'(lib[\\/][^\s]+\.dart):(\d+):(\d+)', line)
            if match:
                file_path, line_no, col = match.groups()
                line_no = int(line_no)
                
                try:
                    with open(file_path, 'r', encoding='utf-8') as f:
                        file_lines = f.readlines()
                    
                    if 0 <= line_no - 1 < len(file_lines):
                        original = file_lines[line_no - 1]
                        modified = re.sub(r'\bconst\s+', '', original)
                        if modified != original:
                            file_lines[line_no - 1] = modified
                            with open(file_path, 'w', encoding='utf-8') as f:
                                f.writelines(file_lines)
                            errors_fixed += 1
                except Exception:
                    pass
                                
        if errors_fixed == 0:
            print("No const errors could be fixed in this pass.")
            break
        print(f"Fixed {errors_fixed} const errors.")

if __name__ == '__main__':
    fix_const_errors()
