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
_pyenv_deactivate() {
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
        echo -e "${GREEN}✓ Successfully removed environment: $env_name${NC}"
    else
        echo -e "${RED}Error: Failed to remove environment${NC}"
        echo "You may need to use 'sudo' if you don't have write permissions"
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
    echo "Type 'pyenv help' for available commands"
    echo ""
}

# Initialize on source
_pyenv_init

# Export the main function to make it available
export -f pyenv



=============
#!/bin/bash
# ============================================================
# Script: pyvenv-manager.sh
# Description: Conda-like manager for Python venv/virtualenv
# Usage: source pyvenv-manager.sh
# ============================================================

# ------------------------------------------------------------
# CONFIGURATION: directories to search for virtual envs
# ------------------------------------------------------------
VENV_DIRS=(
    "$HOME/virtualenvs"
    "$HOME/.virtualenvs"
    "$HOME/venvs"
    "$HOME/.venvs"
    "/opt/venvs"
    "./venvs"
)

# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ------------------------------------------------------------
# MAIN COMMAND
# ------------------------------------------------------------
pyvenv() {
    local cmd="$1"
    shift || true

    case "$cmd" in
        list)        _pyvenv_list ;;
        activate)    _pyvenv_activate "$@" ;;
        deactivate)  _pyvenv_deactivate ;;
        remove)      _pyvenv_remove "$@" ;;
        help|-h|--help|"")
            _pyvenv_help
            ;;
        *)
            echo -e "${RED}Error:${NC} Unknown command '$cmd'"
            echo "Run: pyvenv help"
            return 1
            ;;
    esac
}

# ------------------------------------------------------------
# LIST ALL ENVIRONMENTS (SHOW DUPLICATES)
# ------------------------------------------------------------
_pyvenv_list() {
    echo -e "${BLUE}# python virtual environments:${NC}\n"

    local current_env=""
    [ -n "$VIRTUAL_ENV" ] && current_env="$(realpath "$VIRTUAL_ENV")"

    declare -a envs

    for base in "${VENV_DIRS[@]}"; do
        [ -d "$base" ] || continue
        for d in "$base"/*; do
            [ -d "$d" ] || continue
            if [ -f "$d/bin/activate" ] || [ -f "$d/pyvenv.cfg" ]; then
                envs+=("$(basename "$d")|$(realpath "$d")")
            fi
        done
    done

    if [ "${#envs[@]}" -eq 0 ]; then
        echo -e "${YELLOW}No virtual environments found.${NC}"
        return
    fi

    printf "%-30s %s\n" "Environment" "Location"
    printf "%-30s %s\n" "-----------" "--------"

    IFS=$'\n' sorted_envs=($(printf "%s\n" "${envs[@]}" | sort))
    unset IFS

    for entry in "${sorted_envs[@]}"; do
        local name="${entry%%|*}"
        local path="${entry##*|}"

        if [ "$path" = "$current_env" ]; then
            printf "${GREEN}* %-28s${NC} %s\n" "$name" "$path"
        else
            printf "  %-28s %s\n" "$name" "$path"
        fi
    done

    echo -e "\n${BLUE}Total:${NC} ${#envs[@]}"
}

# ------------------------------------------------------------
# ACTIVATE ENVIRONMENT (SAFE)
# ------------------------------------------------------------
_pyvenv_activate() {
    local target="$1"
    [ -z "$target" ] && {
        echo -e "${RED}Error:${NC} pyvenv activate <env_name|path>"
        return 1
    }

    local matches=()

    # Path-based activation
    if [[ "$target" == /* || "$target" == .* || "$target" == */* ]]; then
        [ -d "$target" ] || {
            echo -e "${RED}Error:${NC} Path not found: $target"
            return 1
        }
        if [ -f "$target/bin/activate" ]; then
            matches+=("$(realpath "$target")")
        fi
    else
        # Name-based search
        for base in "${VENV_DIRS[@]}"; do
            if [ -d "$base/$target" ] && \
               { [ -f "$base/$target/bin/activate" ] || [ -f "$base/$target/pyvenv.cfg" ]; }; then
                matches+=("$(realpath "$base/$target")")
            fi
        done
    fi

    if [ "${#matches[@]}" -eq 0 ]; then
        echo -e "${RED}Error:${NC} Environment not found: $target"
        return 1
    fi

    if [ "${#matches[@]}" -gt 1 ]; then
        echo -e "${RED}Error:${NC} Multiple environments named '$target':"
        for m in "${matches[@]}"; do
            echo "  $m"
        done
        echo "Activate using full path."
        return 1
    fi

    local env_path="${matches[0]}"

    # Deactivate existing env if different
    if [ -n "$VIRTUAL_ENV" ] && [ "$(realpath "$VIRTUAL_ENV")" != "$env_path" ]; then
        deactivate 2>/dev/null || true
    fi

    source "$env_path/bin/activate"

    echo -e "${GREEN}✓ Activated:${NC} $(basename "$env_path")"
    echo -e "${CYAN}  Python:${NC} $(python --version 2>&1)"
    echo -e "${CYAN}  Path:${NC}   $env_path"
}

# ------------------------------------------------------------
# DEACTIVATE
# ------------------------------------------------------------
_pyvenv_deactivate() {
    if [ -z "$VIRTUAL_ENV" ]; then
        echo -e "${YELLOW}No active virtual environment.${NC}"
        return 0
    fi

    local name="$(basename "$VIRTUAL_ENV")"
    deactivate
    echo -e "${GREEN}✓ Deactivated:${NC} $name"
}

# ------------------------------------------------------------
# REMOVE ENVIRONMENT (SAFE)
# ------------------------------------------------------------
_pyvenv_remove() {
    local target="$1"
    [ -z "$target" ] && {
        echo -e "${RED}Error:${NC} pyvenv remove <env_name|path>"
        return 1
    }

    local matches=()

    if [[ "$target" == /* || "$target" == .* || "$target" == */* ]]; then
        [ -d "$target" ] && matches+=("$(realpath "$target")")
    else
        for base in "${VENV_DIRS[@]}"; do
            if [ -d "$base/$target" ] && \
               { [ -f "$base/$target/bin/activate" ] || [ -f "$base/$target/pyvenv.cfg" ]; }; then
                matches+=("$(realpath "$base/$target")")
            fi
        done
    fi

    if [ "${#matches[@]}" -eq 0 ]; then
        echo -e "${RED}Error:${NC} Environment not found."
        return 1
    fi

    if [ "${#matches[@]}" -gt 1 ]; then
        echo -e "${RED}Error:${NC} Multiple environments named '$target':"
        for m in "${matches[@]}"; do
            echo "  $m"
        done
        echo "Remove using full path."
        return 1
    fi

    local env_path="${matches[0]}"
    local name="$(basename "$env_path")"

    if [ -n "$VIRTUAL_ENV" ] && [ "$(realpath "$VIRTUAL_ENV")" = "$env_path" ]; then
        _pyvenv_deactivate
    fi

    echo -e "${YELLOW}About to remove:${NC} $name"
    echo "Path: $env_path"
    read -rp "Confirm? (y/N): " ans
    [[ "$ans" =~ ^[Yy]$ ]] || return 0

    rm -rf "$env_path"
    echo -e "${GREEN}✓ Removed:${NC} $name"
}

# ------------------------------------------------------------
# HELP
# ------------------------------------------------------------
_pyvenv_help() {
    cat <<EOF
PyVenv Manager (conda-like for python venv)

Usage:
  pyvenv list
  pyvenv activate <env_name|path>
  pyvenv deactivate
  pyvenv remove <env_name|path>
  pyvenv help

Examples:
  pyvenv list
  pyvenv activate myenv
  pyvenv activate /opt/venvs/myenv
  pyvenv deactivate
  pyvenv remove oldenv

NOTE:
  This script must be sourced:
    source pyvenv-manager.sh
EOF
}

# ------------------------------------------------------------
# INIT
# ------------------------------------------------------------
echo -e "${BLUE}PyVenv Manager loaded.${NC} Run: pyvenv help"

export -f pyvenv

