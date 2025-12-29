#!/bin/bash

# Script: pyenv-manager.sh
# Description: List and manage Python virtual environments in specified directories
# Usage: source pyenv-manager.sh

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
NC='\033[0m' # No Color

# Function to list all virtual environments
pyenv() {
    local command="$1"
    
    case "$command" in
        list)
            _pyenv_list
            ;;
        activate)
            _pyenv_activate "$2"
            ;;
        deactivate)
            _pyenv_deactivate
            ;;
        remove)
            _pyenv_remove "$2"
            ;;
        help|--help|-h)
            _pyenv_help
            ;;
        *)
            if [ -z "$command" ]; then
                _pyenv_help
            else
                echo -e "${RED}Error: Unknown command '$command'${NC}"
                echo "Type 'pyenv help' for available commands"
                return 1
            fi
            ;;
    esac
}

# Internal function to list all virtual environments in conda-style format
_pyenv_list() {
    echo -e "${BLUE}# conda environments:${NC}"
    echo ""
    
    local env_count=0
    local current_env_path="$VIRTUAL_ENV"
    
    # Create an array to store all found environments with their paths
    declare -A env_map
    declare -a env_paths
    
    # Collect all environments
    for dir in "${VENV_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            # Find all virtual environments
            find "$dir" -maxdepth 2 -type f \( -name "activate" -o -name "pyvenv.cfg" \) 2>/dev/null | \
            while read -r file; do
                if [[ "$file" == *"activate" ]]; then
                    env_path=$(dirname "$(dirname "$file")")
                else
                    env_path=$(dirname "$file")
                fi
                
                env_name=$(basename "$env_path")
                env_map["$env_path"]="$env_name"
                env_paths+=("$env_path")
                ((env_count++))
            done
        fi
    done
    
    # Sort environments by name
    IFS=$'\n' sorted_paths=($(sort -t/ -k2 <<<"${env_paths[*]}"))
    unset IFS
    
    # Print header similar to conda
    printf "%-30s %s\n" "Environment" "Location"
    printf "%-30s %s\n" "-----------" "--------"
    
    # Print all environments
    for env_path in "${sorted_paths[@]}"; do
        local env_name="${env_map[$env_path]}"
        
        # Check if this environment is currently active
        if [ -n "$current_env_path" ] && [ "$(realpath "$current_env_path")" = "$(realpath "$env_path")" ]; then
            printf "${GREEN}%-30s${NC} ${CYAN}%s${NC}\n" "$env_name" "$env_path"
        else
            printf "%-30s %s\n" "$env_name" "$env_path"
        fi
    done
    
    if [ $env_count -eq 0 ]; then
        echo -e "\n${YELLOW}No virtual environments found in configured directories.${NC}"
        echo -e "${YELLOW}Configure VENV_DIRS array at the top of this script.${NC}"
    else
        echo -e "\n${BLUE}Total environments found: $env_count${NC}"
        if [ -n "$current_env_path" ]; then
            echo -e "${GREEN}Current active environment: $(basename "$current_env_path")${NC}"
        fi
    fi
}

# Internal function to activate a virtual environment by name or path
_pyenv_activate() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Please specify environment name or path${NC}"
        echo "Usage: pyenv activate <environment_name_or_path>"
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
                return 1
            fi
        else
            echo -e "${RED}Error: Path '$target' not found${NC}"
            return 1
        fi
    else
        # Target is a name, search for it in configured directories
        for dir in "${VENV_DIRS[@]}"; do
            if [ -d "$dir/$target" ]; then
                env_path="$dir/$target"
                break
            fi
        done
        
        if [ -z "$env_path" ]; then
            echo -e "${RED}Error: Environment '$target' not found${NC}"
            echo -e "${YELLOW}Searching in:${NC}"
            for dir in "${VENV_DIRS[@]}"; do
                echo "  $dir"
            done
            echo -e "\n${YELLOW}You can also activate by providing the full path:${NC}"
            echo "  pyenv activate /path/to/your/venv"
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
        echo -e "${GREEN}Activated environment: $(basename "$env_path")${NC}"
        echo -e "${CYAN}Python: $(python --version 2>&1)${NC}"
        echo -e "${CYAN}Path: $env_path${NC}"
    else
        echo -e "${RED}Error: Cannot activate '$(basename "$env_path")' - activate script not found${NC}"
        return 1
    fi
}

# Internal function to deactivate current environment
_pyenv_deactivate() {
    if [ -z "$VIRTUAL_ENV" ]; then
        echo -e "${YELLOW}No virtual environment is currently active${NC}"
        return 0
    fi
    
    local current_env="${VIRTUAL_ENV##*/}"
    local current_path="$VIRTUAL_ENV"
    deactivate
    echo -e "${GREEN}Deactivated environment: $current_env${NC}"
    echo -e "${CYAN}Path: $current_path${NC}"
}

# Internal function to remove a virtual environment
_pyenv_remove() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Please specify environment name or path${NC}"
        echo "Usage: pyenv remove <environment_name_or_path>"
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
            # Verify it's in one of our search directories
            local found_in_search_dirs=false
            for dir in "${VENV_DIRS[@]}"; do
                if [[ "$env_path" == "$dir"* ]] && [ -d "$dir" ]; then
                    found_in_search_dirs=true
                    break
                fi
            done
            
            if [ "$found_in_search_dirs" = false ]; then
                echo -e "${YELLOW}Warning: '$target' is not in configured search directories${NC}"
                echo -e "${YELLOW}Configured directories:${NC}"
                for dir in "${VENV_DIRS[@]}"; do
                    echo "  $dir"
                done
            fi
        else
            echo -e "${RED}Error: Path '$target' not found${NC}"
            return 1
        fi
    else
        # Target is a name, search for it
        for dir in "${VENV_DIRS[@]}"; do
            if [ -d "$dir/$target" ]; then
                env_path="$dir/$target"
                env_name="$target"
                break
            fi
        done
        
        if [ -z "$env_path" ]; then
            echo -e "${RED}Error: Environment '$target' not found${NC}"
            return 1
        fi
    fi
    
    # Check if currently active
    if [ -n "$VIRTUAL_ENV" ] && [ "$(realpath "$VIRTUAL_ENV")" = "$(realpath "$env_path")" ]; then
        echo -e "${YELLOW}Warning: '$env_name' is currently active${NC}"
        _pyenv_deactivate
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
        echo -e "${GREEN}Successfully removed environment: $env_name${NC}"
    else
        echo -e "${RED}Error: Failed to remove environment${NC}"
        return 1
    fi
}

# Internal function to show help
_pyenv_help() {
    echo -e "${BLUE}PyEnv Manager - Help${NC}"
    echo "========================="
    echo ""
    echo "Available commands:"
    echo "  pyenv list               - List all virtual environments (like 'conda env list')"
    echo "  pyenv activate <env>     - Activate a virtual environment by name or path"
    echo "  pyenv deactivate         - Deactivate current environment"
    echo "  pyenv remove <env>       - Remove a virtual environment by name or path"
    echo "  pyenv help               - Show this help message"
    echo ""
    echo "Examples:"
    echo "  pyenv list                          # List all environments"
    echo "  pyenv activate myenv               # Activate by name"
    echo "  pyenv activate ~/venvs/project     # Activate by path"
    echo "  pyenv activate ./venv              # Activate by relative path"
    echo "  pyenv deactivate                   # Deactivate current environment"
    echo "  pyenv remove oldenv                # Remove by name"
    echo "  pyenv remove ~/venvs/oldenv        # Remove by path"
    echo ""
    echo "Configure search directories by editing the VENV_DIRS array at the top of this script."
    echo ""
    echo "Note: You must source this script to use the activation functions:"
    echo "  source ./pyenv-manager.sh"
}

# Main function to initialize
_pyenv_init() {
    echo -e "${BLUE}PyEnv Manager Initialized${NC}"
    echo "========================"
    echo "Configured search directories:"
    for dir in "${VENV_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            echo -e "  ${GREEN}✓${NC} $dir"
        else
            echo -e "  ${YELLOW}✗${NC} $dir (not found)"
        fi
    done
    echo ""
    echo "Type 'pyenv help' for available commands"
    echo ""
}

# Initialize on source
_pyenv_init

# Export the main function to make it available
export -f pyenv
