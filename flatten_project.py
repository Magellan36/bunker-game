import os

output_file = "project_dump.txt"
extensions = ['.gd', '.tscn', '.tres', '.gdshader', '.cfg', '.import', '.json', '.txt']
ignore_dirs = ['.godot', '.git', 'addons'] # Add any other folders you want to ignore

with open(output_file, "w", encoding="utf-8") as f:
    for root, dirs, files in os.walk("."):
        dirs[:] = [d for d in dirs if d not in ignore_dirs]
        for file in files:
            if any(file.endswith(ext) for ext in extensions):
                filepath = os.path.join(root, file)
                f.write(f"\n\n=== File: {filepath} ===\n")
                try:
                    with open(filepath, "r", encoding="utf-8") as code_file:
                        f.write(code_file.read())
                except Exception as e:
                    f.write(f"[Error reading file: {e}]")

print(f"Created {output_file}")