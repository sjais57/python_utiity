#!/bin/bash

cur_timestamp=$(date +%Y/%m/%d_%H:%M:%S)
log_timestamp=$(date +%Y%m%d%H%M%S)
cur_date=$(date +%Y-%m-%d)

declare pvt_venv_dirs="/nas/data/data/$USER/.pyvenv/envs"

# Ensure cfg_fl is initialized
cfg_fl=0

############################################
# Function: selectPythonVersion
# Description: Checks if Python version exists and allows selection of subversions
# Usage: selectPythonVersion "initial_version"
# Returns: Selected Python version via echo
############################################
function selectPythonVersion() {
    local pyVersion="$1"
    local major_minor_version
    local subversions=()
    local clean_subversions=()
    local sorted_subversions=()
    local version_choice
    local version_found=false
    declare -A version_map
    
    # Check if the exact Python version exists
    ls /efs/dist/python/core/ | grep -Eq "^${pyVersion}$"
    local st_available_py_version=$?
    
    # If the exact version is available, return it
    if [ $st_available_py_version -eq 0 ]; then
        echo "$pyVersion"
        return 0
    fi
    
    # If the exact version is not available, check for subversions
    major_minor_version=$(echo "$pyVersion" | cut -d'.' -f1,2)
    
    # Get all directories and filter for proper version numbers
    # Using regex to match only X.Y.Z format (where Z can be any number)
    subversions=($(ls /efs/dist/python/core/ | grep -E "^${major_minor_version}\.[0-9]+$"))
    
    # If no exact X.Y.Z versions found, try a more flexible pattern
    if [ ${#subversions[@]} -eq 0 ]; then
        subversions=($(ls /efs/dist/python/core/ | grep -E "^${major_minor_version}\.[0-9]+[^[:alpha:]]*$" | grep -vE '.*-.*'))
    fi
    
    # Clean up the list - remove any non-version directories that might have slipped through
    for version in "${subversions[@]}"; do
        # Check if it matches the pattern of a version number (X.Y or X.Y.Z)
        if [[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
            clean_subversions+=("$version")
        fi
    done
    subversions=("${clean_subversions[@]}")
    
    if [ ${#subversions[@]} -eq 0 ]; then
        echo -e "\nError: No available versions found for Python ${major_minor_version}. Please install one." >&2
        return 1
    fi
    
    echo -e "\nThe exact version '${pyVersion}' is not available. Here are the available subversions:" >&2
    # Sort versions numerically
    IFS=$'\n' sorted_subversions=($(sort -V <<<"${subversions[*]}"))
    unset IFS
    
    # Create an associative array for quick lookup
    for i in "${!sorted_subversions[@]}"; do
        echo "$((i + 1)). ${sorted_subversions[$i]}" >&2
        version_map[$((i + 1))]="${sorted_subversions[$i]}"
        version_map["${sorted_subversions[$i]}"]="${sorted_subversions[$i]}"
    done

    # Prompt user to select a subversion
    echo -e "\nYou can enter either the number (e.g., 1) or the version (e.g., 3.11.12)" >&2
    read -p "Please select a version by entering the corresponding number or version: " version_choice
    
    # Check if input is a number
    if [[ $version_choice =~ ^[0-9]+$ ]]; then
        # User entered a number
        if [[ $version_choice -gt 0 && $version_choice -le ${#sorted_subversions[@]} ]]; then
            echo "${version_map[$version_choice]}"
            return 0
        else
            echo -e "\nInvalid number selection. Please enter a number between 1 and ${#sorted_subversions[@]}." >&2
            return 1
        fi
    else
        # User entered a version string
        for version in "${sorted_subversions[@]}"; do
            if [[ "$version_choice" == "$version" ]]; then
                echo "$version_choice"
                return 0
            fi
        done
        
        echo -e "\nInvalid version selection. '$version_choice' is not in the list of available versions." >&2
        return 1
    fi
}

############################################
# Function: validatePythonVersion
# Description: Validates if a Python version exists
# Usage: validatePythonVersion "version"
# Returns: 0 if exists, 1 if not exists
############################################
function validatePythonVersion() {
    local pyVersion="$1"
    
    # Check if the exact Python version exists
    ls /efs/dist/python/core/ | grep -Eq "^${pyVersion}$"
    local st_available=$?
    
    # If exact version doesn't exist, check if it's a valid major.minor
    if [ $st_available -ne 0 ]; then
        local major_minor_version=$(echo "$pyVersion" | cut -d'.' -f1,2)
        local subversions=($(ls /efs/dist/python/core/ | grep -E "^${major_minor_version}\.[0-9]+$"))
        
        if [ ${#subversions[@]} -eq 0 ]; then
            # Try a more flexible pattern
            subversions=($(ls /efs/dist/python/core/ | grep -E "^${major_minor_version}\.[0-9]+[^[:alpha:]]*$" | grep -vE '.*-.*'))
            
            # Clean up the list
            local clean_subversions=()
            for version in "${subversions[@]}"; do
                if [[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
                    clean_subversions+=("$version")
                fi
            done
            
            if [ ${#clean_subversions[@]} -eq 0 ]; then
                return 1
            fi
        fi
    fi
    
    return 0
}

############################################
# Function: createPvtEnv
############################################
function createPvtEnv() {

    # Set log file in the user's home directory
    echo -e "\nFunction to create User private PY Virtual Environment\n"

    if [ $cfg_fl -eq 0 ]; then

        # Prompt for environment name
        read -p "Please enter the private Virtual Environment name you wish to create. Note: it will be prefixed by pvt_ : " pvtVENname
        pvtVENname=$(echo "$pvtVENname" | tr '[:upper:]' '[:lower:]')

        # Validate environment name
        if [ -z "$pvtVENname" ]; then
            echo -e "\nError: The private virtual environment name cannot be empty."
            exit 1
        fi

        echo -e "\n"

        # Prompt for Python version
        read -p "Please enter the Python version to use (Default to 3.10.12 if not specified): " pyVersion

        # Validate Python version
        if [ -z "$pyVersion" ]; then
            pyVersion="3.10.12"
        fi
    fi

    # Use the reusable function to select Python version
    selected_version=$(selectPythonVersion "$pyVersion")
    if [ $? -ne 0 ]; then
        exit 1
    fi
    pyVersion="$selected_version"

    pyExec="/efs/dist/python/core/${pyVersion}/exec/bin/python3"

    # Prompt for default packages
    read -p "Please enter the specific packages to be installed with the VE, each separated by comma. This is optional (Ex: graphviz,matplotlib==3.10.12.3,plotly): " default_packages

    dfltPkg=$(echo "$default_packages" | tr "," " ")

    # Check if env already exists
    ls "$pvt_venv_dirs" | tr " " "\n" | grep -Eq "^pvt_${pvtVENname}$"
    st_available_pvt_envs=$?

    if [ $st_available_pvt_envs -ne 0 ]; then
        pvtVENname="pvt_${pvtVENname}"
        echo -e "\nCreating py virtual environment at $pvt_venv_dirs using $pyExec\n"
        $pyExec -m venv "$pvt_venv_dirs/$pvtVENname"

        if [ $? -eq 0 ]; then
            echo -e "\nActivating virtual environment and installing packages: $dfltPkg\n"
            source "$pvt_venv_dirs/$pvtVENname/bin/activate"

            if [ ! -z "$dfltPkg" ]; then
                pip install $dfltPkg
                pip_status=$?

                if [ $pip_status -eq 0 ]; then
                    echo -e "\nPip packages installed successfully.\n"
                else
                    echo -e "\nError: Pip installation failed with status code $pip_status.\n"
                    return 1
                fi
            fi
        else
            echo -e "\nPip virtual environment creation failed.\n"
            return 1
        fi
    else
        echo -e "\nError: A private environment with the name '$pvtVENname' already exists. Please try a different name.\n"
        return 1
    fi

    deactivate

    echo -e "\nSuccessfully created py virtual environment at $pvt_venv_dirs/$pvtVENname"
    echo -e "To activate this environment, run: source $pvt_venv_dirs/$pvtVENname/bin/activate"
    echo -e "To deactivate, simply run: deactivate\n"
}

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
        # Install packages from requirements file
        if [ -f "$specFileName" ]; then
            echo -e "Installing packages from: $specFileName\n"
            pip install -r "$specFileName"
            pip_status=$?
        
            if [ $pip_status -eq 0 ]; then
                echo -e "\n✓ All packages installed successfully from requirements file.\n"
            else
                echo -e "\n⚠ Warning: Some packages failed to install (exit code: $pip_status).\n"
                echo -e "The virtual environment was created successfully, but you may need to:"
                echo -e "1. Check the error messages above"
                echo -e "2. Fix the requirements file"
                echo -e "3. Manually install missing packages:"
                echo -e "   source $pvt_venv_dirs/$pvtVEName/bin/activate"
                echo -e "   pip install <package_name>"
                echo -e "   deactivate\n"
            fi
        else
            echo -e "\n✗ Error: Requirements file not found: $specFileName\n"
            echo -e "Please verify the file path and try again.\n"
            deactivate
            return 1
        fi
        
        deactivate
        
        echo -e "\n✓ Virtual environment created successfully: $pvtVEName\n"
        echo -e "Location: $pvt_venv_dirs/$pvtVEName"
        echo -e "Python version: $pyVersion"
        if [ -f "$specFileName" ]; then
            echo -e "Requirements file: $specFileName"
        fi
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
############################################
# Function: createSpecPrjEnv
############################################
############################################
# Function: createSpecPrjEnv
############################################
function createSpecPrjEnv() {
    echo -e "\nFunction to create User Project Python Virtual Environment using requirements file\n"

    # Set project environment directory
    declare prj_venv_dirs="/nas/data/data/projects/pyvenv/envs"

    # Reset variables
    local prjVEName=""
    local pyVersion=""
    local specFileName=""
    local grpName=""
    
    read -p "Please enter the project Virtual Environment Name you wish to create. Note: it will be prefixed by 'prj_' : " prjVEName
    prjVEName=$(echo "$prjVEName" | tr '[:upper:]' '[:lower:]')
    
    # Validate environment name
    if [ -z "$prjVEName" ]; then
        echo -e "\nError: The project virtual environment name cannot be empty."
        exit 1
    fi
    
    echo -e "\n"
    read -p "Please enter the Python version to use (Default to 3.10.12 if not specified): " pyVersion

    # Validate Python version
    if [ -z "$pyVersion" ]; then
        pyVersion="3.10.12"
    fi
    
    # Use the reusable function to select Python version
    echo -e "\nChecking Python version availability..."
    selected_version=$(selectPythonVersion "$pyVersion")
    if [ $? -ne 0 ]; then
        exit 1
    fi
    pyVersion="$selected_version"
    
    echo -e "\nSelected Python version: $pyVersion\n"
    
    # FIXED: Corrected Python executable path (removed /exec from path)
    pyExec="/efs/dist/python/core/${pyVersion}/bin/python3"
    
    echo -e "\n"
    read -p "Please enter the requirements file name with complete path. Ex: /nas-path/requirements.txt : " specFileName
    
    # Clean up the filename
    specFileName=$(echo "$specFileName" | xargs)
    
    echo -e "\n"
    read -p "Please enter the group Name which will own the Virtual Environment $prjVEName: " grpName
    echo -e "\n"

    # Check if env already exists
    ls "$prj_venv_dirs" | tr " " "\n" | grep -Eq "^prj_${prjVEName}$"
    st_available_prj_envs=$?

    # Check if group exists
    getent group "$grpName" | grep -oq "$grpName"
    st_grp=$?

    if [ $st_grp -ne 0 ]; then
        echo -e "\n✗ Error: Group '$grpName' does not exist. Please provide a valid group name.\n"
        return 1
    else
        if [ -f "$specFileName" ] && [ ! -z "$prjVEName" ] && [ $st_available_prj_envs -ne 0 ]; then
            prjVEName="prj_${prjVEName}"
            
            echo -e "\nCreating project Python Virtual Environment '$prjVEName' using requirements file: $specFileName\n"
            echo -e "Using Python: $pyExec\n"
            echo -e "Group owner: $grpName\n"

            # Create virtual environment
            $pyExec -m venv "$prj_venv_dirs/$prjVEName"
            if [ $? -ne 0 ]; then
                echo -e "\n✗ Failed to create Python virtual environment."
                return 1
            fi

            echo -e "✓ Virtual environment created: $prj_venv_dirs/$prjVEName\n"
            echo -e "Activating environment and installing packages...\n"
            source "$prj_venv_dirs/$prjVEName/bin/activate"

            # Install packages from requirements file
            if [ -f "$specFileName" ]; then
                echo -e "=== Installing packages from: $specFileName ===\n"
                
                # Install packages and capture status
                pip install -r "$specFileName"
                pip_status=$?
                
                if [ $pip_status -eq 0 ]; then
                    echo -e "\n✓ All packages installed successfully.\n"
                else
                    echo -e "\n⚠ Package installation completed with errors (exit code: $pip_status)."
                    echo -e "The environment was created, but some packages may not be installed correctly."
                    echo -e "Check the error messages above for problematic packages.\n"
                fi
            else
                echo -e "\n✗ Error: Requirements file not found: $specFileName\n"
                echo -e "Please verify the file path and try again.\n"
                deactivate
                return 1
            fi

            deactivate

            # Set group ownership and permissions
            echo -e "\nSetting group ownership and permissions...\n"
            
            echo -e "Changing group ownership to: $grpName"
            chgrp -R "$grpName" "$prj_venv_dirs/$prjVEName"
            
            echo -e "Setting group read permissions..."
            chmod -R g+r "$prj_venv_dirs/$prjVEName"
            
            echo -e "Setting group write permissions..."
            chmod -R g+w "$prj_venv_dirs/$prjVEName"
            
            echo -e "Setting setgid bit on directories..."
            find "$prj_venv_dirs/$prjVEName" -type d -exec chmod g+s {} \;
            
            echo -e "Setting execute permissions..."
            chmod -R ug+x "$prj_venv_dirs/$prjVEName/bin" 2>/dev/null || true
            
            echo -e "\n✓ Permissions set successfully.\n"

            echo -e "\n✅ Summary:\n"
            echo -e "✓ Virtual environment: $prjVEName"
            echo -e "✓ Location: $prj_venv_dirs/$prjVEName"
            echo -e "✓ Python version: $pyVersion"
            echo -e "✓ Group owner: $grpName"
            
            if [ -f "$specFileName" ]; then
                if [ $pip_status -eq 0 ]; then
                    echo -e "✓ Packages: Successfully installed from $specFileName"
                else
                    echo -e "⚠ Packages: Some packages failed to install (see errors above)"
                fi
            fi
            
            echo -e "\n Commands:"
            echo -e "  To activate:   source $prj_venv_dirs/$prjVEName/bin/activate"
            echo -e "  To deactivate: deactivate"
            echo -e "\n Permissions:"
            echo -e "  - Group '$grpName' has read/write access"
            echo -e "  - New files will inherit group ownership"
            echo -e "\n"

        elif [ -z "$prjVEName" ]; then
            echo -e "\n✗ Error: Empty project VE Name\n"

        elif [ ! -f "$specFileName" ]; then
            echo -e "\n✗ Error: Requirements file does not exist: $specFileName\n"
            echo -e "Please provide the complete path, for example:"
            echo -e "  /home/user/requirements.txt"
            echo -e "  /nas/data/projects/myproject/requirements.txt\n"

        elif [ $st_available_prj_envs -eq 0 ]; then
            echo -e "\n✗ Error: Project VE name 'prj_${prjVEName}' already exists. Please try a different name.\n"
        fi
    fi
}

# Call the function
# createPvtEnv
# createSpecPvtEnv
# createSpecPrjEnv
