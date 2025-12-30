#!/bin/bash

# Script: pyvenv-manager.sh
# Description: List and manage Python virtual environments in specified directories
# Usage: source pyvenv-manager.sh

# Configuration - User can modify these paths
VENV_DIRS=(
    "$HOME/virtualenvs"
    "$HOME/.virtualenvs"
    "$HOME/venvs"
    "$HOME/.venvs"
    "/opt/venvs"
    "./venvs"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Main function
pyvenv() {
    local command="$1"
    
    case "$command" in
        env)
            # Handle pyvenv env list
            if [ "$2" = "list" ]; then
                _pyvenv_list
            else
                echo -e "${RED}Error: Unknown env subcommand '${2:-}'${NC}"
                echo "Usage: pyvenv env list"
                return 1
            fi
            ;;
        activate)
            _pyvenv_activate "$2"
            ;;
        deactivate)
            _pyvenv_deactivate
            ;;
        remove)
            _pyvenv_remove "$2"
            ;;
        packages|pkgs)
            _pyvenv_packages "$2" "$3"
            ;;
        help|--help|-h)
            _pyvenv_help
            ;;
        *)
            if [ -z "$command" ]; then
                _pyvenv_help
            else
                echo -e "${RED}Error: Unknown command '$command'${NC}"
                echo "Type 'pyvenv help' for available commands"
                return 1
            fi
            ;;
    esac
}

# Internal function to list all virtual environments in conda-style format
_pyvenv_list() {
    echo -e "${BLUE}# conda environments:${NC}"
    echo ""
    
    local env_count=0
    local current_env_path="$VIRTUAL_ENV"
    
    # Create arrays to store environments
    declare -a all_envs
    
    # Collect all environments from all directories
    for dir in "${VENV_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            # Check each subdirectory in the venv directory
            for item in "$dir"/*; do
                if [ -d "$item" ]; then
                    # Check if it's a virtual environment by looking for activate script or pyvenv.cfg
                    if [ -f "$item/bin/activate" ] || [ -f "$item/pyvenv.cfg" ]; then
                        env_name=$(basename "$item")
                        env_path=$(realpath "$item")
                        all_envs+=("$env_name:$env_path")
                        ((env_count++))
                    fi
                fi
            done
        fi
    done
    
    # Also check for virtual environments directly in current directory structure
    if [ -d "./venv" ] && { [ -f "./venv/bin/activate" ] || [ -f "./venv/pyvenv.cfg" ]; }; then
        env_name="venv"
        env_path=$(realpath "./venv")
        all_envs+=("$env_name:$env_path")
        ((env_count++))
    fi
    
    # Print header similar to conda
    printf "%-30s %s\n" "Environment" "Location"
    printf "%-30s %s\n" "-----------" "--------"
    
    # Sort and display environments
    if [ ${#all_envs[@]} -gt 0 ]; then
        # Sort environments by name
        IFS=$'\n' sorted_envs=($(sort <<<"${all_envs[*]}"))
        unset IFS
        
        # Display each environment
        for env in "${sorted_envs[@]}"; do
            env_name="${env%%:*}"
            env_path="${env#*:}"
            
            # Check if this environment is currently active
            if [ -n "$current_env_path" ] && [ "$(realpath "$current_env_path")" = "$env_path" ]; then
                printf "${GREEN}%s${NC} ${CYAN}%s${NC}\n" "$env_name" "$env_path"
            else
                printf "%-30s %s\n" "$env_name" "$env_path"
            fi
        done
    fi
    
    if [ $env_count -eq 0 ]; then
        echo -e "\n${YELLOW}No virtual environments found.${NC}"
        echo -e "${YELLOW}Configured search directories:${NC}"
        for dir in "${VENV_DIRS[@]}"; do
            if [ -d "$dir" ]; then
                echo -e "  ${GREEN}✓${NC} $dir"
            else
                echo -e "  ${YELLOW}✗${NC} $dir (not found)"
            fi
        done
        echo -e "\n${YELLOW}You can create a virtual environment with:${NC}"
        echo "  python -m venv /path/to/your/venv"
    else
        echo -e "\n${BLUE}Total environments found: $env_count${NC}"
        if [ -n "$current_env_path" ]; then
            echo -e "${GREEN}Current active environment: $(basename "$current_env_path")${NC}"
        fi
    fi
}

# Internal function to list packages in a virtual environment without activating it
_pyvenv_packages() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Please specify environment name or path${NC}"
        echo "Usage: pyvenv packages <environment_name_or_path> [options]"
        echo "       pyvenv pkgs <environment_name_or_path> [options]"
        return 1
    fi
    
    local target="$1"
    local option="$2"
    local env_path=""
    local env_name=""
    
    # Check if target is a path
    if [[ "$target" == */* ]] || [[ "$target" == .* ]] || [[ "$target" == /* ]]; then
        # Target looks like a path
        if [ -d "$target" ]; then
            env_path=$(realpath "$target")
            env_name=$(basename "$env_path")
            # Verify it's a virtual environment
            if [ ! -f "$env_path/bin/activate" ] && [ ! -f "$env_path/pyvenv.cfg" ]; then
                echo -e "${RED}Error: '$target' is not a valid virtual environment${NC}"
                return 1
            fi
        else
            echo -e "${RED}Error: Path '$target' not found${NC}"
            return 1
        fi
    else
        # Target is a name, search for it
        for dir in "${VENV_DIRS[@]}"; do
            if [ -d "$dir" ] && [ -d "$dir/$target" ]; then
                if [ -f "$dir/$target/bin/activate" ] || [ -f "$dir/$target/pyvenv.cfg" ]; then
                    env_path="$dir/$target"
                    env_name="$target"
                    break
                fi
            fi
        done
        
        # Also check if it's a venv in current directory
        if [ -z "$env_path" ] && [ "$target" = "venv" ] && [ -d "./venv" ]; then
            if [ -f "./venv/bin/activate" ] || [ -f "./venv/pyvenv.cfg" ]; then
                env_path=$(realpath "./venv")
                env_name="venv"
            fi
        fi
        
        if [ -z "$env_path" ]; then
            echo -e "${RED}Error: Environment '$target' not found${NC}"
            return 1
        fi
    fi
    
    # Check if the environment has a python interpreter
    local python_bin="$env_path/bin/python"
    if [ ! -f "$python_bin" ]; then
        # Try alternative locations
        python_bin="$env_path/bin/python3"
        if [ ! -f "$python_bin" ]; then
            python_bin="$env_path/Scripts/python.exe"  # Windows
            if [ ! -f "$python_bin" ]; then
                echo -e "${RED}Error: Python interpreter not found in environment${NC}"
                return 1
            fi
        fi
    fi
    
    echo -e "${PURPLE}Packages in environment: ${CYAN}$env_name${NC}"
    echo -e "${PURPLE}Path: ${CYAN}$env_path${NC}"
    echo ""
    
    # Get Python version
    local python_version
    python_version=$("$python_bin" --version 2>&1)
    echo -e "${BLUE}Python: ${CYAN}$python_version${NC}"
    
    # Try to get pip list
    echo -e "\n${BLUE}Installed packages:${NC}"
    echo "-----------------"
    
    # Check if pip is available
    local pip_cmd
    if [ -f "$env_path/bin/pip" ]; then
        pip_cmd="$env_path/bin/pip"
    elif [ -f "$env_path/bin/pip3" ]; then
        pip_cmd="$env_path/bin/pip3"
    elif [ -f "$env_path/Scripts/pip.exe" ]; then
        pip_cmd="$env_path/Scripts/pip.exe"
    else
        # Try to use python -m pip
        if "$python_bin" -m pip --version >/dev/null 2>&1; then
            pip_cmd="$python_bin -m pip"
        else
            echo -e "${YELLOW}Warning: pip not found in environment${NC}"
            echo -e "${YELLOW}Trying to use system pip with environment interpreter...${NC}"
            
            # Try to get packages by inspecting site-packages directory
            local site_packages
            site_packages=$("$python_bin" -c "import site; print(site.getsitepackages()[0])" 2>/dev/null)
            if [ -n "$site_packages" ] && [ -d "$site_packages" ]; then
                echo -e "\n${BLUE}Packages found in site-packages:${NC}"
                echo "------------------------------"
                ls -1 "$site_packages" | grep -v "\.dist-info$" | grep -v "\.egg-info$" | sort
                return 0
            else
                echo -e "${RED}Error: Could not list packages${NC}"
                return 1
            fi
        fi
    fi
    
    # List packages with pip
    case "$option" in
        --tree|-t)
            # Show dependency tree if requested
            if "$python_bin" -c "import pipdeptree" 2>/dev/null; then
                "$python_bin" -m pipdeptree
            else
                echo -e "${YELLOW}pipdeptree not installed. Installing temporarily...${NC}"
                "$python_bin" -m pip install --quiet pipdeptree
                "$python_bin" -m pipdeptree
                "$python_bin" -m pip uninstall --quiet --yes pipdeptree
            fi
            ;;
        --outdated|-o)
            # Show outdated packages
            $pip_cmd list --outdated
            ;;
        --freeze|-f)
            # Show in requirements format
            $pip_cmd freeze
            ;;
        *)
            # Show normal package list
            $pip_cmd list
            ;;
    esac
    
    # Show summary
    local package_count
    package_count=$($pip_cmd list --format=freeze 2>/dev/null | wc -l)
    echo -e "\n${BLUE}Total packages: ${CYAN}$package_count${NC}"
}

# Internal function to activate a virtual environment by name or path
_pyvenv_activate() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Please specify environment name or path${NC}"
        echo "Usage: pyvenv activate <environment_name_or_path>"
        return 1
    fi
    
    local target="$1"
    local env_path=""
    
    # Check if target is a path (contains '/' or starts with '.' or '/')
    if [[ "$target" == */* ]] || [[ "$target" == .* ]] || [[ "$target" == /* ]]; then
        # Target looks like a path
        if [ -d "$target" ]; then
            env_path=$(realpath "$target")
            # Check if it's a valid virtual environment
            if [ ! -f "$env_path/bin/activate" ] && [ ! -f "$env_path/pyvenv.cfg" ]; then
                echo -e "${RED}Error: '$target' is not a valid virtual environment${NC}"
                echo "A virtual environment should have either bin/activate or pyvenv.cfg"
                return 1
            fi
        else
            echo -e "${RED}Error: Path '$target' not found${NC}"
            return 1
        fi
    else
        # Target is a name, search for it in configured directories
        for dir in "${VENV_DIRS[@]}"; do
            if [ -d "$dir" ] && [ -d "$dir/$target" ]; then
                # Verify it's actually a virtual environment
                if [ -f "$dir/$target/bin/activate" ] || [ -f "$dir/$target/pyvenv.cfg" ]; then
                    env_path="$dir/$target"
                    break
                fi
            fi
        done
        
        # Also check if it's a venv in current directory
        if [ -z "$env_path" ] && [ "$target" = "venv" ] && [ -d "./venv" ]; then
            if [ -f "./venv/bin/activate" ] || [ -f "./venv/pyvenv.cfg" ]; then
                env_path=$(realpath "./venv")
            fi
        fi
        
        if [ -z "$env_path" ]; then
            echo -e "${RED}Error: Environment '$target' not found${NC}"
            echo -e "${YELLOW}Searching in:${NC}"
            for dir in "${VENV_DIRS[@]}"; do
                if [ -d "$dir" ]; then
                    echo "  $dir"
                fi
            done
            echo -e "\n${YELLOW}You can also activate by providing the full path:${NC}"
            echo "  pyvenv activate /path/to/your/venv"
            return 1
        fi
    fi
    
    # Check if already activated
    if [ -n "$VIRTUAL_ENV" ]; then
        if [ "$(realpath "$VIRTUAL_ENV")" = "$(realpath "$env_path")" ]; then
            echo -e "${YELLOW}Environment '$(basename "$env_path")' is already active${NC}"
            return 0
        else
            echo -e "${YELLOW}Deactivating current environment '${VIRTUAL_ENV##*/}'...${NC}"
            deactivate 2>/dev/null || true
        fi
    fi
    
    # Activate the environment
    if [ -f "$env_path/bin/activate" ]; then
        source "$env_path/bin/activate"
        echo -e "${GREEN}✓ Activated environment: $(basename "$env_path")${NC}"
        echo -e "${CYAN}  Python: $(python --version 2>&1)${NC}"
        echo -e "${CYAN}  Path: $env_path${NC}"
    elif [ -f "$env_path/Scripts/activate" ]; then
        # For Windows-style virtual environments (if running in Git Bash/Cygwin)
        source "$env_path/Scripts/activate"
        echo -e "${GREEN}✓ Activated environment: $(basename "$env_path")${NC}"
        echo -e "${CYAN}  Python: $(python --version 2>&1)${NC}"
        echo -e "${CYAN}  Path: $env_path${NC}"
    else
        echo -e "${RED}Error: Cannot activate '$(basename "$env_path")' - no activate script found${NC}"
        echo "Looked for:"
        echo "  $env_path/bin/activate"
        echo "  $env_path/Scripts/activate"
        return 1
    fi
}

# Internal function to deactivate current environment
_pyvenv_deactivate() {
    if [ -z "$VIRTUAL_ENV" ]; then
        echo -e "${YELLOW}No virtual environment is currently active${NC}"
        return 0
    fi
    
    local current_env="${VIRTUAL_ENV##*/}"
    local current_path="$VIRTUAL_ENV"
    
    # Check if we're in a virtual environment before deactivating
    if command -v deactivate >/dev/null 2>&1; then
        deactivate
        echo -e "${GREEN}✓ Deactivated environment: $current_env${NC}"
        echo -e "${CYAN}  Path: $current_path${NC}"
    else
        echo -e "${YELLOW}Not in a virtual environment${NC}"
        unset VIRTUAL_ENV
    fi
}

# Internal function to remove a virtual environment
_pyvenv_remove() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Please specify environment name or path${NC}"
        echo "Usage: pyvenv remove <environment_name_or_path>"
        return 1
    fi
    
    local target="$1"
    local env_path=""
    local env_name=""
    
    # Check if target is a path
    if [[ "$target" == */* ]] || [[ "$target" == .* ]] || [[ "$target" == /* ]]; then
        # Target looks like a path
        if [ -d "$target" ]; then
            env_path=$(realpath "$target")
            env_name=$(basename "$env_path")
            # Verify it's a virtual environment
            if [ ! -f "$env_path/bin/activate" ] && [ ! -f "$env_path/pyvenv.cfg" ]; then
                echo -e "${RED}Error: '$target' is not a valid virtual environment${NC}"
                return 1
            fi
        else
            echo -e "${RED}Error: Path '$target' not found${NC}"
            return 1
        fi
    else
        # Target is a name, search for it
        for dir in "${VENV_DIRS[@]}"; do
            if [ -d "$dir" ] && [ -d "$dir/$target" ]; then
                if [ -f "$dir/$target/bin/activate" ] || [ -f "$dir/$target/pyvenv.cfg" ]; then
                    env_path="$dir/$target"
                    env_name="$target"
                    break
                fi
            fi
        done
        
        # Also check if it's a venv in current directory
        if [ -z "$env_path" ] && [ "$target" = "venv" ] && [ -d "./venv" ]; then
            if [ -f "./venv/bin/activate" ] || [ -f "./venv/pyvenv.cfg" ]; then
                env_path=$(realpath "./venv")
                env_name="venv"
            fi
        fi
        
        if [ -z "$env_path" ]; then
            echo -e "${RED}Error: Environment '$target' not found${NC}"
            return 1
        fi
    fi
    
    # Check if currently active
    if [ -n "$VIRTUAL_ENV" ] && [ "$(realpath "$VIRTUAL_ENV")" = "$(realpath "$env_path")" ]; then
        echo -e "${YELLOW}Warning: '$env_name' is currently active${NC}"
        _pyvenv_deactivate
    fi
    
    echo -e "${YELLOW}Removing environment: $env_name${NC}"
    echo -e "${CYAN}Path: $env_path${NC}"
    
    read -p "Are you sure? This cannot be undone. (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Removal cancelled"
        return 0
    fi
    
    if rm -rf "$env_path"; then
        echo -e "${GREEN}✓ Successfully removed environment: $env_name${NC}"
    else
        echo -e "${RED}Error: Failed to remove environment${NC}"
        echo "You may need to use 'sudo' if you don't have write permissions"
        return 1
    fi
}

# Internal function to show help
_pyvenv_help() {
    echo -e "${BLUE}PyVenv Manager - Help${NC}"
    echo "=========================="
    echo ""
    echo "Available commands:"
    echo "  pyvenv env list                 - List all virtual environments (like 'conda env list')"
    echo "  pyvenv activate <env>           - Activate a virtual environment by name or path"
    echo "  pyvenv deactivate               - Deactivate current environment"
    echo "  pyvenv remove <env>             - Remove a virtual environment by name or path"
    echo "  pyvenv packages <env> [options] - List packages in environment (without activating)"
    echo "  pyvenv pkgs <env> [options]     - Alias for packages command"
    echo "  pyvenv help                     - Show this help message"
    echo ""
    echo "Package list options:"
    echo "  --tree, -t       Show dependency tree"
    echo "  --outdated, -o   Show only outdated packages"
    echo "  --freeze, -f     Show in requirements.txt format"
    echo ""
    echo "Examples:"
    echo "  pyvenv env list                      # List all environments"
    echo "  pyvenv activate myenv               # Activate by name"
    echo "  pyvenv activate ~/venvs/project     # Activate by path"
    echo "  pyvenv packages myenv               # List packages in myenv"
    echo "  pyvenv packages myenv --tree        # Show dependency tree"
    echo "  pyvenv packages myenv --outdated    # Show outdated packages"
    echo "  pyvenv deactivate                   # Deactivate current environment"
    echo "  pyvenv remove oldenv                # Remove by name"
    echo ""
    echo "Configure search directories by editing the VENV_DIRS array at the top of this script."
    echo ""
    echo "Note: You must source this script to use the activation functions:"
    echo "  source ./pyvenv-manager.sh"
}

# Main function to initialize
_pyvenv_init() {
    echo -e "${BLUE}PyVenv Manager Initialized${NC}"
    echo "=========================="
    echo "Type 'pyvenv help' for available commands"
    echo ""
}

# Initialize on source
_pyvenv_init

# Export the main function to make it available
export -f pyvenv
