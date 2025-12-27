function createSpecPvtEnv() {

    echo -e "\nCreate User Private Python Virtual Environment (PyPI based)\n"

    if [ "$cfg_fl" -eq 0 ]; then

        read -p "Enter private Virtual Environment name (prefix pvt_ will be added): " pvtVEName
        pvtVEName="$(echo "$pvtVEName" | tr '[:upper:]' '[:lower:]')"

        if [ -z "$pvtVEName" ]; then
            echo "Error: VE name cannot be empty"
            return 1
        fi

        echo
        read -p "Enter Python version (default 3.10): " pyVersion
        pyVersion="${pyVersion:-3.10}"

        # Validate python version BEFORE proceeding
        selected_version="$(selectPythonVersion "$pyVersion")" || return 1
        pyVersion="$selected_version"

        pyExec="/efs/dist/python/core/${pyVersion}/bin/python3"

        if [ ! -x "$pyExec" ]; then
            echo "Error: Python $pyVersion not found at $pyExec"
            return 1
        fi

        echo
        read -p "Enter full path to requirements.txt: " specFileName

        # Normalize path
        specFileName="$(readlink -f "$specFileName" 2>/dev/null)"

        if [ ! -f "$specFileName" ]; then
            echo "Error: Requirements file not found"
            return 1
        fi
    fi

    pvtVEName="pvt_${pvtVEName}"

    if [ -d "$pvt_venv_dirs/$pvtVEName" ]; then
        echo "Error: Virtual env already exists: $pvtVEName"
        return 1
    fi

    echo -e "\nCreating virtual environment: $pvtVEName"
    "$pyExec" -m venv "$pvt_venv_dirs/$pvtVEName" || return 1

    echo "Activating environment and installing packages"
    source "$pvt_venv_dirs/$pvtVEName/bin/activate"

    pip install --upgrade pip setuptools wheel
    pip install -r "$specFileName" || {
        deactivate
        return 1
    }

    deactivate

    echo -e "\nSuccessfully created $pvtVEName"
    echo "Activate using:"
    echo "source $pvt_venv_dirs/$pvtVEName/bin/activate"
}


====================================
############################################
# Function: createSpecPvtEnv
############################################
function createSpecPvtEnv() {
    echo -e "\nFunction to create User private Python Virtual Environment using requirements file\n"

    # Reset variables to avoid any contamination
    local pvtVEName=""
    local pyVersion=""
    local specFileName=""
    
    read -p "Please enter the private Virtual Environment Name you wish to create. Note: it will be prefixed by 'pvt_' : " pvtVEName
    pvtVEName=$(echo "$pvtVEName" | tr '[:upper:]' '[:lower:]')
    
    # Validate environment name
    if [ -z "$pvtVEName" ]; then
        echo -e "\nError: The private virtual environment name cannot be empty."
        exit 1
    fi
    
    echo -e "\n"
    read -p "Please enter the Python version to use (Default to 3.10 if not specified): " pyVersion

    # Validate Python version
    if [ -z "$pyVersion" ]; then
        pyVersion="3.10"
    fi
    
    # Use the reusable function to select Python version
    echo -e "\nChecking Python version availability..."
    selected_version=$(selectPythonVersion "$pyVersion")
    if [ $? -ne 0 ]; then
        exit 1
    fi
    pyVersion="$selected_version"
    
    echo -e "\nSelected Python version: $pyVersion\n"
    
    pyExec="/efs/dist/python/core/${pyVersion}/bin/python3"
    
    # Now ask for requirements file
    read -p "Please enter the requirements file name with complete path. Ex: /nas-path/requirements.txt : " specFileName
    
    # Clean up the filename - remove any trailing spaces or newlines
    specFileName=$(echo "$specFileName" | xargs)
    
    echo -e "\n"

    # Check if env already exists
    ls "$pvt_venv_dirs" | tr " " "\n" | grep -Eq "^pvt_${pvtVEName}$"
    st_available_pvt_envs=$?

    if [ -f "$specFileName" ] && [ ! -z "$pvtVEName" ] && [ $st_available_pvt_envs -ne 0 ]; then
        pvtVEName="pvt_${pvtVEName}"
        echo -e "\nCreating User private Python Virtual Environment '$pvtVEName' using requirements file: $specFileName\n"
        echo -e "Using Python: $pyExec\n"

        # Create virtual environment
        $pyExec -m venv "$pvt_venv_dirs/$pvtVEName"
        if [ $? -ne 0 ]; then
            echo -e "\nFailed to create Python virtual environment."
            return 1
        fi

        echo -e "\nActivating virtual environment and installing packages from requirements file\n"
        source "$pvt_venv_dirs/$pvtVEName/bin/activate"

        # Install packages from requirements file
        if [ -f "$specFileName" ]; then
            echo -e "Installing packages from: $specFileName\n"
            pip install -r "$specFileName"
            pip_status=$?

            if [ $pip_status -eq 0 ]; then
                echo -e "\n✓ Packages installed successfully from requirements file.\n"
            else
                echo -e "\n✗ Error: Pip installation failed with status code $pip_status.\n"
                deactivate
                return 1
            fi
        else
            echo -e "\n✗ Error: Requirements file not found: $specFileName\n"
            echo -e "Please verify the file path and try again.\n"
            deactivate
            return 1
        fi

        deactivate

        # Create activation script for JAVA_HOME if needed (optional - remove if not needed)
        # For venv, we can create an activation script in the bin/activate.d directory
        pvtVEActivateDir="$pvt_venv_dirs/$pvtVEName/bin/activate.d"
        pvtVEDeactivateDir="$pvt_venv_dirs/$pvtVEName/bin/deactivate.d"
        
        if [ ! -d "$pvtVEActivateDir" ]; then
            mkdir -p "$pvtVEActivateDir"
        fi
        if [ ! -d "$pvtVEDeactivateDir" ]; then
            mkdir -p "$pvtVEDeactivateDir"
        fi

        # Create JAVA_HOME scripts (optional - only if Java is needed)
        echo -e "\nCreating JAVA_HOME environment scripts (optional)..."
        
        echo -e "export VENV_BACKUP_JAVA_HOME=\${JAVA_HOME:-}\n\
export JAVA_HOME=\${VENV_JAVA_HOME:-\${JAVA_HOME:-/usr/lib/jvm/java-11-openjdk}}\n\
export VENV_BACKUP_JAVA_LD_LIBRARY_PATH=\${JAVA_LD_LIBRARY_PATH:-}\n\
export JAVA_LD_LIBRARY_PATH=\${JAVA_HOME}/lib/server" \
> "$pvtVEActivateDir/java_env.sh"

        echo -e "export JAVA_HOME=\${VENV_BACKUP_JAVA_HOME}\n\
unset VENV_BACKUP_JAVA_HOME\n\
export JAVA_LD_LIBRARY_PATH=\${VENV_BACKUP_JAVA_LD_LIBRARY_PATH}\n\
unset VENV_BACKUP_JAVA_LD_LIBRARY_PATH" \
> "$pvtVEDeactivateDir/java_env.sh"

        chmod 755 "$pvtVEActivateDir/java_env.sh"
        chmod 755 "$pvtVEDeactivateDir/java_env.sh"

        echo -e "\n✓ Successfully created virtual environment: $pvtVEName\n"
        echo -e "Location: $pvt_venv_dirs/$pvtVEName"
        echo -e "Python version: $pyVersion"
        echo -e "Packages installed from: $specFileName"
        echo -e "\nTo activate this environment, run:"
        echo -e "  source $pvt_venv_dirs/$pvtVEName/bin/activate"
        echo -e "\nTo deactivate, run:"
        echo -e "  deactivate\n"

    elif [ -z "$pvtVEName" ]; then
        echo -e "\n✗ Error: Empty private VE Name\n"

    elif [ ! -f "$specFileName" ]; then
        echo -e "\n✗ Error: Requirements file does not exist: $specFileName\n"
        echo -e "Please provide the complete path, for example:"
        echo -e "  /home/user/requirements.txt"
        echo -e "  /nas/data/projects/myproject/requirements.txt\n"

    elif [ $st_available_pvt_envs -eq 0 ]; then
        echo -e "\n✗ Error: Private VE name 'pvt_${pvtVEName}' already exists. Please try a different name.\n"
    fi
}


====================================
