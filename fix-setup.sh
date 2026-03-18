#!/bin/bash
# fix-setup.sh - Fix script for stable-diffusion-webui-forge Linux setup issues
# Date: 2026-03-18
# 
# This script fixes the following issues:
# 1. Missing pkg_resources module (CLIP installation failure)
# 2. Missing wheel package
# 3. NumPy version incompatibility with scikit-image
# 4. Missing joblib dependency

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=================================================="
echo "Fixing stable-diffusion-webui-forge setup issues"
echo "=================================================="
echo ""

# Backup original files
echo "[1/4] Creating backups of original files..."
BACKUP_DIR="$SCRIPT_DIR/.fix_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

cp "$SCRIPT_DIR/modules/launch_utils.py" "$BACKUP_DIR/launch_utils.py.bak" 2>/dev/null || true
cp "$SCRIPT_DIR/requirements_versions.txt" "$BACKUP_DIR/requirements_versions.txt.bak" 2>/dev/null || true

echo "      Backups saved to: $BACKUP_DIR"
echo ""

# Fix 1: Modify modules/launch_utils.py to add setuptools, wheel, and --no-build-isolation
echo "[2/4] Fixing modules/launch_utils.py (setuptools, wheel, build isolation)..."

# Check if the fix is already applied
if grep -q "if not is_installed(\"setuptools\"):" "$SCRIPT_DIR/modules/launch_utils.py"; then
    echo "      setuptools fix already applied, skipping..."
else
    python3 << 'PYTHON_SCRIPT'
file_path = "modules/launch_utils.py"
with open(file_path, 'r') as f:
    lines = f.readlines()

new_lines = []
i = 0
while i < len(lines):
    line = lines[i]
    new_lines.append(line)
    
    # Look for the pattern: startup_timer.record("torch GPU test")
    if 'startup_timer.record("torch GPU test")' in line:
        indent = "    "
        new_lines.append("\n")
        new_lines.append(indent + 'if not is_installed("setuptools"):\n')
        new_lines.append(indent + '    run_pip("install -U setuptools", "setuptools")\n')
        new_lines.append(indent + '    startup_timer.record("install setuptools")\n')
        new_lines.append("\n")
        new_lines.append(indent + 'if not is_installed("wheel"):\n')
        new_lines.append(indent + '    run_pip("install -U wheel", "wheel")\n')
        new_lines.append(indent + '    startup_timer.record("install wheel")\n')
    
    # Look for clip installation and add --no-build-isolation
    if 'if not is_installed("clip"):' in line and i + 1 < len(lines):
        next_line = lines[i + 1]
        if 'run_pip(f"install {clip_package}"' in next_line and '--no-build-isolation' not in next_line:
            new_lines.pop()
            new_lines.append(line)
            new_lines.append('        run_pip(f"install {clip_package} --no-build-isolation", "clip")\n')
            i += 1
    
    # Look for open_clip installation and add --no-build-isolation
    if 'if not is_installed("open_clip"):' in line and i + 1 < len(lines):
        next_line = lines[i + 1]
        if 'run_pip(f"install {openclip_package}"' in next_line and '--no-build-isolation' not in next_line:
            new_lines.pop()
            new_lines.append(line)
            new_lines.append('        run_pip(f"install {openclip_package} --no-build-isolation", "open_clip")\n')
            i += 1
    
    i += 1

with open(file_path, 'w') as f:
    f.writelines(new_lines)

print("      Added setuptools and wheel installation with --no-build-isolation flags")
PYTHON_SCRIPT
fi

echo ""

# Fix 2 & 3: Use Python to modify requirements_versions.txt
echo "[3/4] Fixing requirements_versions.txt (numpy version constraint and joblib)..."

python3 << 'PYTHON_SCRIPT'
file_path = "requirements_versions.txt"

with open(file_path, 'r') as f:
    content = f.read()

content = content.replace('\r\n', '\n')
lines = content.split('\n')

new_lines = []
numpy_fixed = False
joblib_added = False

for line in lines:
    if line.strip() == 'numpy==1.26.2':
        new_lines.append('numpy<2.0.0,>=1.26.2')
        numpy_fixed = True
    else:
        new_lines.append(line)
    
    if line.strip() == 'inflection==0.5.1':
        new_lines.append('joblib==1.3.2')
        joblib_added = True

output = '\r\n'.join(new_lines)
with open(file_path, 'w') as f:
    f.write(output)

if numpy_fixed:
    print("      Updated numpy==1.26.2 to numpy<2.0.0,>=1.26.2")
else:
    print("      WARNING: Failed to update numpy version")

if joblib_added:
    print("      Added joblib==1.3.2 to requirements")
else:
    print("      WARNING: Failed to add joblib")
PYTHON_SCRIPT

echo ""

# Fix 4: Add numpy downgrade after extension installations
echo "[4/4] Adding numpy downgrade after extension installations..."

python3 << 'PYTHON_SCRIPT'
file_path = "modules/launch_utils.py"
with open(file_path, 'r') as f:
    content = f.read()

old_text = '''    if not args.skip_install:
        run_extensions_installers(settings_file=args.ui_settings_file)

    if args.update_check:'''

new_text = '''    if not args.skip_install:
        run_extensions_installers(settings_file=args.ui_settings_file)

    # Downgrade numpy if version 2.x is installed (incompatible with scikit-image)
    # This must run after all package installations to ensure final numpy version is correct
    import subprocess
    result = subprocess.run([python, "-c", "import numpy; print(numpy.__version__)"], capture_output=True, text=True)
    if result.returncode == 0 and result.stdout.strip().startswith("2."):
        run_pip("install 'numpy<2.0.0,>=1.26.2' --force-reinstall", "downgrade numpy")
        # Reinstall scikit-image to ensure it's built against correct numpy version
        run_pip("install scikit-image==0.21.0 --force-reinstall --no-cache-dir --no-deps", "reinstall scikit-image")
    startup_timer.record("downgrade numpy")

    if args.update_check:'''

if old_text in content:
    content = content.replace(old_text, new_text)
    with open(file_path, 'w') as f:
        f.write(content)
    print("      Added numpy downgrade after extension installations")
else:
    print("      WARNING: Could not find extension installation section")
PYTHON_SCRIPT

echo ""
echo "=================================================="
echo "Fix completed successfully!"
echo "=================================================="
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
echo "To restore original files, run:"
echo "  cp $BACKUP_DIR/launch_utils.py.bak modules/launch_utils.py"
echo "  cp $BACKUP_DIR/requirements_versions.txt.bak requirements_versions.txt"
echo ""
echo "You can now run ./webui.sh"
echo ""
