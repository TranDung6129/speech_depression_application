import re
import sys

def fix_errors(log_path):
    with open(log_path, 'r') as f:
        log = f.read()

    pattern = r"(lib/[^:]+):(\d+):(\d+): Error: (Not a constant expression\.|Method invocation is not a constant expression\.)"
    matches = re.findall(pattern, log)

    files_to_fix = {}
    for match in matches:
        file_path, line_str, col_str, _ = match
        line = int(line_str)
        if file_path not in files_to_fix:
            files_to_fix[file_path] = set()
        files_to_fix[file_path].add(line)

    for file_path, lines in files_to_fix.items():
        with open(file_path, 'r') as f:
            content_lines = f.readlines()
        
        for line_num in lines:
            idx = line_num - 1
            if idx < 0 or idx >= len(content_lines): continue
            
            content_lines[idx] = content_lines[idx].replace('const ', '')
            
            for i in range(1, 10):
                prev = idx - i
                if prev >= 0 and 'const ' in content_lines[prev]:
                    content_lines[prev] = content_lines[prev].replace('const ', '')
                        
        with open(file_path, 'w') as f:
            f.writelines(content_lines)

fix_errors('/home/trandung/.gemini/antigravity/brain/12894521-6601-47af-85f6-9fa6cdcbcae3/.system_generated/tasks/task-329.log')
