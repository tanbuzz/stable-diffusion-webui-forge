#!/usr/bin/env python3
"""
fix-setup.sh - Fix script for stable-diffusion-webui-forge Linux setup issues

This script fixes multiple errors preventing ./webui.sh from running successfully on Linux.
It configures PyTorch 2.3.1 with CUDA 12.1 and xformers 0.0.27 (fully compatible).

Usage:
    ./fix-setup.sh              # Apply fixes
    ./fix-setup.sh --revert     # Restore original files from backup
    ./fix-setup.sh --help       # Show this help message

Fixes applied:
    1. Missing pkg_resources module (CLIP installation failure)
    2. Missing wheel package
    3. NumPy version incompatibility with scikit-image
    4. Missing joblib dependency
    5. PyTorch 2.3.1 with CUDA 12.1 and xformers configuration
"""

import os
import sys
import re
import shutil
import argparse
from datetime import datetime
from pathlib import Path


# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR = Path(__file__).resolve().parent
BACKUP_DIR_NAME = ".fix_backup"

# Files to modify and their backup names
FILES_TO_MODIFY = {
    "modules/launch_utils.py": "launch_utils.py.bak",
    "requirements_versions.txt": "requirements_versions.txt.bak",
    "webui-user.sh": "webui-user.sh.bak",
}

# Expected content patterns for sanity checks
SANITY_CHECKS = {
    "modules/launch_utils.py": [
        "def run_pip(",
        "startup_timer.record(",
        "if not is_installed(",
    ],
    "requirements_versions.txt": [
        "setuptools==",
        "torch",
    ],
    "webui-user.sh": [
        "COMMANDLINE_ARGS",
        "TORCH_COMMAND",
    ],
}


# ============================================================================
# Utility Functions
# ============================================================================

def print_header(text):
    """Print a formatted section header."""
    print("\n" + "=" * 60)
    print(text)
    print("=" * 60 + "\n")


def print_step(step_num, description):
    """Print a step description."""
    print(f"[{step_num}] {description}...")


def print_success(message):
    """Print a success message."""
    print(f"      ✓ {message}")


def print_error(message):
    """Print an error message."""
    print(f"      ✗ ERROR: {message}", file=sys.stderr)


def print_warning(message):
    """Print a warning message."""
    print(f"      ⚠ WARNING: {message}")


def backup_file(src_path, backup_path):
    """Create a backup of a file."""
    try:
        shutil.copy2(src_path, backup_path)
        return True
    except Exception as e:
        print_error(f"Failed to backup {src_path}: {e}")
        return False


def restore_file(backup_path, dest_path):
    """Restore a file from backup."""
    try:
        shutil.copy2(backup_path, dest_path)
        return True
    except Exception as e:
        print_error(f"Failed to restore {dest_path}: {e}")
        return False


def read_file(file_path):
    """Read file content, handling different line endings."""
    with open(file_path, 'r', encoding='utf-8') as f:
        return f.read()


def write_file(file_path, content):
    """Write content to file, preserving original line endings if possible."""
    # Detect original line endings
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            original = f.read()
        if '\r\n' in original:
            line_ending = '\r\n'
        else:
            line_ending = '\n'
    except FileNotFoundError:
        line_ending = '\n'
    
    # Normalize content to detected line ending
    content = content.replace('\r\n', '\n').replace('\r', '\n')
    if line_ending == '\r\n':
        content = content.replace('\n', '\r\n')
    
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)


def sanity_check(file_path, patterns):
    """
    Check if a file contains expected patterns.
    Returns True if all patterns are found.
    """
    try:
        content = read_file(file_path)
        for pattern in patterns:
            if pattern not in content:
                return False
        return True
    except Exception:
        return False


def get_backup_dir():
    """Get or create backup directory with timestamp."""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir = SCRIPT_DIR / f"{BACKUP_DIR_NAME}_{timestamp}"
    backup_dir.mkdir(parents=True, exist_ok=True)
    return backup_dir


def find_latest_backup():
    """Find the most recent backup directory."""
    backup_dirs = [d for d in SCRIPT_DIR.iterdir() 
                   if d.is_dir() and d.name.startswith(BACKUP_DIR_NAME)]
    if not backup_dirs:
        return None
    return max(backup_dirs, key=lambda d: d.name)


# ============================================================================
# Fix Functions
# ============================================================================

def fix_launch_utils(content):
    """
    Apply fixes to modules/launch_utils.py.
    Returns modified content and list of changes made.
    """
    changes = []
    
    # Fix 1: Add setuptools and wheel installation after "torch GPU test"
    setuptools_pattern = r'(startup_timer\.record\("torch GPU test"\))'
    setuptools_replacement = r'''\1

    if not is_installed("setuptools"):
        run_pip("install -U setuptools", "setuptools")
        startup_timer.record("install setuptools")

    if not is_installed("wheel"):
        run_pip("install -U wheel", "wheel")
        startup_timer.record("install wheel")'''
    
    if 'if not is_installed("setuptools"):' not in content:
        content = re.sub(setuptools_pattern, setuptools_replacement, content)
        changes.append("Added setuptools and wheel installation")
    
    # Fix 2: Add --no-build-isolation to CLIP installation
    clip_pattern = r'(if not is_installed\("clip"\):\s+run_pip\(f"install \{clip_package\}")'
    clip_replacement = r'if not is_installed("clip"):\n        run_pip(f"install {clip_package} --no-build-isolation"'
    
    if '--no-build-isolation' not in content or 'clip' not in content.split('--no-build-isolation')[0].split('\n')[-1]:
        old_clip = 'if not is_installed("clip"):\n        run_pip(f"install {clip_package}", "clip")'
        new_clip = 'if not is_installed("clip"):\n        run_pip(f"install {clip_package} --no-build-isolation", "clip")'
        if old_clip in content:
            content = content.replace(old_clip, new_clip)
            changes.append("Added --no-build-isolation to CLIP installation")
    
    # Fix 3: Add --no-build-isolation to open_clip installation
    old_openclip = 'if not is_installed("open_clip"):\n        run_pip(f"install {openclip_package}", "open_clip")'
    new_openclip = 'if not is_installed("open_clip"):\n        run_pip(f"install {openclip_package} --no-build-isolation", "open_clip")'
    if old_openclip in content:
        content = content.replace(old_openclip, new_openclip)
        changes.append("Added --no-build-isolation to open_clip installation")
    
    # Fix 4: Add numpy downgrade AFTER all installations (including extensions)
    numpy_code = '''    if not requirements_met(requirements_file):
        run_pip(f"install -r \\"{requirements_file}\\"", "requirements")
        startup_timer.record("install requirements")

    if not os.path.isfile(requirements_file_for_npu):
        requirements_file_for_npu = os.path.join(script_path, requirements_file_for_npu)

    if "torch_npu" in torch_command and not requirements_met(requirements_file_for_npu):
        run_pip(f"install -r \\"{requirements_file_for_npu}\\"", "requirements_for_npu")
        startup_timer.record("install requirements_for_npu")

    if not args.skip_install:
        run_extensions_installers(settings_file=args.ui_settings_file)

    # Downgrade numpy if version 2.x is installed (incompatible with scikit-image)
    # This runs after ALL installations to ensure final numpy version is correct
    import subprocess
    result = subprocess.run([python, "-c", "import numpy; print(numpy.__version__)"], capture_output=True, text=True)
    if result.returncode == 0 and result.stdout.strip().startswith("2."):
        run_pip("install 'numpy<2.0.0,>=1.26.2' --force-reinstall", "downgrade numpy", live=True)
        run_pip("install scikit-image==0.21.0 --force-reinstall --no-cache-dir --no-deps", "reinstall scikit-image", live=True)
    startup_timer.record("downgrade numpy")'''
    
    old_req_block = '''    if not requirements_met(requirements_file):
        run_pip(f"install -r \\"{requirements_file}\\"", "requirements")
        startup_timer.record("install requirements")

    if not os.path.isfile(requirements_file_for_npu):
        requirements_file_for_npu = os.path.join(script_path, requirements_file_for_npu)

    if "torch_npu" in torch_command and not requirements_met(requirements_file_for_npu):
        run_pip(f"install -r \\"{requirements_file_for_npu}\\"", "requirements_for_npu")
        startup_timer.record("install requirements_for_npu")

    if not args.skip_install:
        run_extensions_installers(settings_file=args.ui_settings_file)'''
    
    if 'Downgrade numpy' not in content and old_req_block in content:
        content = content.replace(old_req_block, numpy_code)
        changes.append("Added numpy downgrade after all installations")
    
    # Fix 5: Update xformers installation to always reinstall
    old_xformers = '''if (not is_installed("xformers") or args.reinstall_xformers) and args.xformers:
        run_pip(f"install -U -I --no-deps {xformers_package}", "xformers")'''
    
    new_xformers = '''# Reinstall xformers to ensure compatibility with PyTorch 2.3.1+cu121
    # xformers 0.0.27 is fully compatible with PyTorch 2.3.1+cu121
    if args.xformers:
        run_pip(f"install -U -I --no-deps xformers==0.0.27", "xformers", live=True)'''
    
    if old_xformers in content:
        content = content.replace(old_xformers, new_xformers)
        changes.append("Updated xformers installation for automatic reinstall")
    
    return content, changes


def fix_requirements(content):
    """
    Apply fixes to requirements_versions.txt.
    Returns modified content and list of changes made.
    """
    changes = []
    lines = content.replace('\r\n', '\n').split('\n')
    new_lines = []
    
    numpy_fixed = False
    joblib_added = False
    
    for line in lines:
        # Fix numpy version constraint
        if line.strip() == 'numpy==1.26.2':
            new_lines.append('numpy<2.0.0,>=1.26.2')
            if not numpy_fixed:
                changes.append("Updated numpy==1.26.2 to numpy<2.0.0,>=1.26.2")
                numpy_fixed = True
        else:
            new_lines.append(line)
        
        # Add joblib after inflection
        if line.strip() == 'inflection==0.5.1':
            new_lines.append('joblib==1.3.2')
            if not joblib_added:
                changes.append("Added joblib==1.3.2 to requirements")
                joblib_added = True
    
    # Rejoin with CRLF to match original format
    content = '\r\n'.join(new_lines)
    return content, changes


def fix_webui_user(content):
    """
    Apply fixes to webui-user.sh.
    Returns modified content and list of changes made.
    """
    changes = []
    
    # Fix 1: Set TORCH_COMMAND for PyTorch 2.3.1 with CUDA 12.1
    torch_command = '# install command for torch\n# PyTorch 2.3.1 with CUDA 12.1 (compatible with xformers 0.0.27)\nexport TORCH_COMMAND="pip install torch==2.3.1 torchvision==0.18.1 torchaudio==2.3.1 --index-url https://download.pytorch.org/whl/cu121"'
    
    old_torch = '# install command for torch\n#export TORCH_COMMAND="pip install torch==1.12.1+cu113 --extra-index-url https://download.pytorch.org/whl/cu113"'
    
    if 'torch==2.3.1' not in content:
        if old_torch in content:
            content = content.replace(old_torch, torch_command)
            changes.append("Configured PyTorch 2.3.1 with CUDA 12.1")
        elif '#export TORCH_COMMAND=' in content:
            content = content.replace(
                '#export TORCH_COMMAND=',
                '# PyTorch 2.3.1 with CUDA 12.1\nexport TORCH_COMMAND="pip install torch==2.3.1 torchvision==0.18.1 torchaudio==2.3.1 --index-url https://download.pytorch.org/whl/cu121"\n#export TORCH_COMMAND='
            )
            changes.append("Configured PyTorch 2.3.1 with CUDA 12.1")
    
    # Fix 2: Enable xformers in COMMANDLINE_ARGS
    if '--xformers' not in content:
        old_args = '#export COMMANDLINE_ARGS=""'
        new_args = 'export COMMANDLINE_ARGS="--xformers"'
        if old_args in content:
            content = content.replace(old_args, new_args)
            changes.append("Enabled xformers in COMMANDLINE_ARGS")
        elif '#export COMMANDLINE_ARGS=' in content and 'COMMANDLINE_ARGS="--' not in content:
            content = content.replace('#export COMMANDLINE_ARGS=""', 'export COMMANDLINE_ARGS="--xformers"')
            changes.append("Enabled xformers in COMMANDLINE_ARGS")
    
    return content, changes


# ============================================================================
# Main Operations
# ============================================================================

def check_modified_files():
    """
    Check if any tracked files have been modified (using git).
    Returns list of modified files from FILES_TO_MODIFY.
    """
    modified = []
    try:
        import subprocess
        result = subprocess.run(
            ["git", "status", "--porcelain"],
            capture_output=True,
            text=True,
            cwd=SCRIPT_DIR
        )
        if result.returncode == 0:
            for line in result.stdout.split('\n'):
                if line.strip():
                    # Parse git status output (e.g., " M modules/launch_utils.py")
                    parts = line.split()
                    if len(parts) >= 2:
                        filepath = parts[1]
                        if filepath in FILES_TO_MODIFY:
                            modified.append(filepath)
    except Exception:
        pass  # Not a git repo or git not available
    return modified


def apply_fixes():
    """Apply all fixes to the project files."""
    print_header("Fixing stable-diffusion-webui-forge setup issues")
    
    # Sanity check: Detect modified files without backup
    modified_files = check_modified_files()
    if modified_files:
        # Files are modified, check if backup exists
        existing_backup = find_latest_backup()
        if not existing_backup:
            print_warning("The following files appear to be modified:")
            for f in modified_files:
                print(f"  - {f}")
            print("")
            print_warning("But no backup directory was found!")
            print("")
            print("This means fixes were applied previously but the backup was deleted.")
            print("You have two options:")
            print("")
            print("1. Restore original files using git, then apply fixes:")
            print("   git checkout modules/launch_utils.py requirements_versions.txt webui-user.sh")
            print(f"   {sys.argv[0]}")
            print("")
            print("2. Remove the modifications manually and start fresh:")
            print("   git checkout modules/launch_utils.py requirements_versions.txt webui-user.sh")
            print(f"   {sys.argv[0]}")
            sys.exit(1)
        else:
            # Files modified AND backup exists - already applied
            print_error(f"Existing backup found: {existing_backup}")
            print_error("Fixes have already been applied to this installation.")
            print("")
            print("To apply fixes again, first revert:")
            print(f"  {sys.argv[0]} --revert")
            print("")
            print("Or remove the existing backup:")
            print(f"  rm -rf {existing_backup}")
            sys.exit(1)
    
    # Files are not modified (clean state), but check for existing backup
    existing_backup = find_latest_backup()
    if existing_backup:
        # Files are clean but backup exists - user reverted, allow re-apply
        print(f"Existing backup found: {existing_backup}")
        print("Files appear to be in original state (previously reverted).")
        print("Applying fixes will create a new backup and modify files.")
        response = input("Continue? [Y/n]: ").strip().lower()
        if response == 'n':
            print("Aborted.")
            sys.exit(0)
        # Remove old backup before creating new one
        try:
            shutil.rmtree(existing_backup)
            print(f"Removed old backup: {existing_backup}")
        except Exception as e:
            print_warning(f"Could not remove old backup: {e}")
            print("Please remove manually and try again.")
            sys.exit(1)
    
    # Create backup directory
    backup_dir = get_backup_dir()
    print(f"Backup directory: {backup_dir}")
    
    all_success = True
    total_changes = 0
    
    for file_rel_path, backup_name in FILES_TO_MODIFY.items():
        file_path = SCRIPT_DIR / file_rel_path
        backup_path = backup_dir / backup_name
        
        if not file_path.exists():
            print_error(f"File not found: {file_path}")
            all_success = False
            continue
        
        # Create backup
        print_step(1, f"Backing up {file_rel_path}")
        if not backup_file(file_path, backup_path):
            all_success = False
            continue
        print_success("Backup created")
        
        # Read and modify file
        print_step(2, f"Fixing {file_rel_path}")
        try:
            content = read_file(file_path)
            
            if file_rel_path == "modules/launch_utils.py":
                content, changes = fix_launch_utils(content)
            elif file_rel_path == "requirements_versions.txt":
                content, changes = fix_requirements(content)
            elif file_rel_path == "webui-user.sh":
                content, changes = fix_webui_user(content)
            else:
                changes = []
            
            # Write modified content
            write_file(file_path, content)
            
            # Report changes
            for change in changes:
                print_success(change)
            
            total_changes += len(changes)
            
        except Exception as e:
            print_error(f"Failed to fix {file_rel_path}: {e}")
            all_success = False
    
    # Final status
    print_header("Fix Summary")
    if all_success:
        print_success(f"Applied {total_changes} fixes successfully")
        print(f"\nBackup location: {backup_dir}")
        print("\nTo restore original files, run:")
        print(f"  {sys.argv[0]} --revert")
        print("\nYou can now run ./webui.sh")
    else:
        print_error("Some fixes failed. Check errors above.")
        print(f"\nPartial backups saved to: {backup_dir}")
        sys.exit(1)


def revert_fixes():
    """Revert all fixes by restoring from backup."""
    print_header("Reverting fixes")
    
    # Find latest backup
    backup_dir = find_latest_backup()
    if not backup_dir:
        print_error("No backup directory found. Nothing to revert.")
        print("")
        print("Your files may have been modified but the backup was deleted.")
        print("To restore original files, use git:")
        print("  git checkout modules/launch_utils.py requirements_versions.txt webui-user.sh")
        sys.exit(1)
    
    print(f"Using backup from: {backup_dir}")
    
    all_success = True
    
    for file_rel_path, backup_name in FILES_TO_MODIFY.items():
        file_path = SCRIPT_DIR / file_rel_path
        backup_path = backup_dir / backup_name
        
        if not backup_path.exists():
            print_warning(f"No backup found for {file_rel_path}")
            continue
        
        # Sanity check backup file
        if file_rel_path in SANITY_CHECKS:
            patterns = SANITY_CHECKS[file_rel_path]
            if not sanity_check(backup_path, patterns):
                print_warning(f"Backup for {file_rel_path} may be corrupted (sanity check failed)")
                response = input("Continue anyway? [y/N]: ").strip().lower()
                if response != 'y':
                    all_success = False
                    continue
        
        # Restore file
        print_step(1, f"Restoring {file_rel_path}")
        if restore_file(backup_path, file_path):
            print_success("File restored")
        else:
            all_success = False
    
    # Final status - DO NOT remove backup
    print_header("Revert Summary")
    if all_success:
        print_success("All files restored to original state")
        print(f"\nBackup preserved at: {backup_dir}")
        print("")
        print("Backup is kept for safety. To remove it manually:")
        print(f"  rm -rf {backup_dir}")
        print("")
        print("You can run --revert again if needed, or apply fixes again.")
    else:
        print_error("Some files could not be restored")
        print(f"Backup preserved at: {backup_dir}")
        sys.exit(1)


def show_help():
    """Display help message."""
    print(__doc__)


# ============================================================================
# Entry Point
# ============================================================================

def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Fix script for stable-diffusion-webui-forge Linux setup issues",
        add_help=False
    )
    parser.add_argument(
        '--revert',
        action='store_true',
        help='Restore original files from backup'
    )
    parser.add_argument(
        '--help', '-h',
        action='store_true',
        help='Show this help message and exit'
    )
    
    args = parser.parse_args()
    
    if args.help:
        show_help()
        sys.exit(0)
    elif args.revert:
        revert_fixes()
    else:
        apply_fixes()


if __name__ == "__main__":
    main()
