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

# Internal function to list all virtual environments
_pyenv_list() {
    echo -e "${BLUE}Python Virtual Environments${NC}"
    echo "========================"
    
    local env_count=0
    local current_env="${VIRTUAL_ENV##*/}"
    
    for dir in "${VENV_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            echo -e "\n${YELLOW}Directory: $dir${NC}"
            echo "------------------------"
            
            # Find all virtual environments (directories containing bin/activate or pyvenv.cfg)
            find "$dir" -maxdepth 2 -type f \( -name "activate" -o -name "pyvenv.cfg" \) 2>/dev/null | \
            while read -r file; do
                if [[ "$file" == *"activate" ]]; then
                    env_path=$(dirname "$(dirname "$file")")
                else
                    env_path=$(dirname "$file")
                fi
                
                env_name=$(basename "$env_path")
                
                # Check if this environment is currently active
                if [ -n "$VIRTUAL_ENV" ] && [ "$(realpath "$VIRTUAL_ENV")" = "$(realpath "$env_path")" ]; then
                    echo -e "${GREEN}  * $env_name${NC}    [Active]"
                else
                    echo "    $env_name"
                fi
                
                ((env_count++))
            done
        fi
    done
    
    if [ $env_count -eq 0 ]; then
        echo -e "\n${YELLOW}No virtual environments found in configured directories.${NC}"
        echo -e "${YELLOW}Configure VENV_DIRS array at the top of this script.${NC}"
    else
        echo -e "\nTotal environments found: $env_count"
    fi
}

# Internal function to activate a virtual environment
_pyenv_activate() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Please specify environment name${NC}"
        echo "Usage: pyenv activate <environment_name>"
        return 1
    fi
    
    local env_name="$1"
    local env_path=""
    
    # Search for the environment in all configured directories
    for dir in "${VENV_DIRS[@]}"; do
        if [ -d "$dir/$env_name" ]; then
            env_path="$dir/$env_name"
            break
        fi
    done
    
    if [ -z "$env_path" ]; then
        echo -e "${RED}Error: Environment '$env_name' not found${NC}"
        echo -e "${YELLOW}Searching in:${NC}"
        for dir in "${VENV_DIRS[@]}"; do
            echo "  $dir"
        done
        return 1
    fi
    
    # Check if already activated
    if [ -n "$VIRTUAL_ENV" ]; then
        echo -e "${YELLOW}Warning: Already in virtual environment '${VIRTUAL_ENV##*/}'${NC}"
        echo -e "${YELLOW}Deactivating current environment first...${NC}"
        deactivate 2>/dev/null || true
    fi
    
    # Activate the environment
    if [ -f "$env_path/bin/activate" ]; then
        source "$env_path/bin/activate"
        echo -e "${GREEN}Activated environment: $env_name${NC}"
        echo -e "Python: $(python --version 2>&1)"
        echo -e "Path: $env_path"
    else
        echo -e "${RED}Error: Cannot activate '$env_name' - activate script not found${NC}"
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
    deactivate
    echo -e "${GREEN}Deactivated environment: $current_env${NC}"
}

# Internal function to remove a virtual environment
_pyenv_remove() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Please specify environment name${NC}"
        echo "Usage: pyenv remove <environment_name>"
        return 1
    fi
    
    local env_name="$1"
    local env_path=""
    
    # Search for the environment
    for dir in "${VENV_DIRS[@]}"; do
        if [ -d "$dir/$env_name" ]; then
            env_path="$dir/$env_name"
            break
        fi
    done
    
    if [ -z "$env_path" ]; then
        echo -e "${RED}Error: Environment '$env_name' not found${NC}"
        return 1
    fi
    
    # Check if currently active
    if [ -n "$VIRTUAL_ENV" ] && [ "$(realpath "$VIRTUAL_ENV")" = "$(realpath "$env_path")" ]; then
        echo -e "${YELLOW}Warning: '$env_name' is currently active${NC}"
        _pyenv_deactivate
    fi
    
    echo -e "${YELLOW}Removing environment: $env_name${NC}"
    echo -e "Path: $env_path"
    
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
    echo "  pyenv activate <env>     - Activate a virtual environment"
    echo "  pyenv deactivate         - Deactivate current environment"
    echo "  pyenv remove <env>       - Remove a virtual environment"
    echo "  pyenv help               - Show this help message"
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
