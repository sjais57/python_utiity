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
# Function: createPrjEnv
# Description: Creates a project environment without requirements file
# Similar to createSpecPrjEnv but without spec file requirement
############################################
function createPrjEnv() {
    echo -e "\nFunction to create User Project Python Virtual Environment (without requirements file)\n"

    # Set project environment directory
    declare prj_venv_dirs="/nas/data/data/projects/pyvenv/envs"

    # Reset variables
    local prjVEName=""
    local pyVersion=""
    local default_packages=""
    local dfltPkg=""
    local grpName=""
    
    read -p "Please enter the project Virtual Environment Name you wish to create. Note: it will be prefixed by 'prj_' : " prjVEName
    prjVEName=$(echo "$prjVEName" | tr '[:upper:]' '[:lower:]")
    
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
    
    # Prompt for optional default packages
    read -p "Please enter specific packages to be installed (optional, comma-separated). Ex: numpy,pandas,matplotlib: " default_packages
    
    if [ ! -z "$default_packages" ]; then
        dfltPkg=$(echo "$default_packages" | tr "," " ")
    fi
    
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
        if [ ! -z "$prjVEName" ] && [ $st_available_prj_envs -ne 0 ]; then
            prjVEName="prj_${prjVEName}"
            
            echo -e "\nCreating project Python Virtual Environment '$prjVEName'\n"
            echo -e "Using Python: $pyExec\n"
            echo -e "Group owner: $grpName\n"
            
            if [ ! -z "$dfltPkg" ]; then
                echo -e "Packages to install: $dfltPkg\n"
            else
                echo -e "No additional packages specified (only base packages will be installed).\n"
            fi

            # Create virtual environment
            $pyExec -m venv "$prj_venv_dirs/$prjVEName"
            if [ $? -ne 0 ]; then
                echo -e "\n✗ Failed to create Python virtual environment."
                return 1
            fi

            echo -e "✓ Virtual environment created: $prj_venv_dirs/$prjVEName\n"
            
            # Install packages if specified
            if [ ! -z "$dfltPkg" ]; then
                echo -e "Activating environment and installing packages...\n"
                source "$prj_venv_dirs/$prjVEName/bin/activate"

                echo -e "=== Installing packages ===\n"
                
                # Install packages and capture status
                pip install $dfltPkg
                pip_status=$?
                
                if [ $pip_status -eq 0 ]; then
                    echo -e "\n✓ All packages installed successfully.\n"
                else
                    echo -e "\n⚠ Package installation completed with errors (exit code: $pip_status)."
                    echo -e "The environment was created, but some packages may not be installed correctly."
                    echo -e "Check the error messages above for problematic packages.\n"
                fi
                
                deactivate
            else
                echo -e "✓ Base virtual environment created (no additional packages installed).\n"
            fi

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
            
            if [ ! -z "$dfltPkg" ]; then
                if [ $pip_status -eq 0 ]; then
                    echo -e "✓ Packages: Successfully installed: $dfltPkg"
                else
                    echo -e "⚠ Packages: Some packages failed to install (see errors above)"
                fi
            else
                echo -e "✓ Packages: Base environment only (pip, setuptools, wheel)"
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

        elif [ $st_available_prj_envs -eq 0 ]; then
            echo -e "\n✗ Error: Project VE name 'prj_${prjVEName}' already exists. Please try a different name.\n"
        fi
    fi
}

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
    prjVEName=$(echo "$prjVEName" | tr '[:upper:]' '[:lower:]")
    
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

############################################
# Function: removePvtEnv
# Description: Removes a user's private virtual environment
# Usage: removePvtEnv
############################################
function removePvtEnv() {
    echo -e "\nFunction to remove User private Python Virtual Environment\n"
    
    # Reset variables
    local env_name=""
    local full_env_name=""
    local confirm=""
    
    # List available private environments
    echo -e "Available private virtual environments:\n"
    
    local env_count=0
    local env_list=()
    
    if [ -d "$pvt_venv_dirs" ]; then
        # Get all environments that start with 'pvt_'
        for env in "$pvt_venv_dirs"/*; do
            if [ -d "$env" ]; then
                env_name=$(basename "$env")
                env_list+=("$env_name")
                ((env_count++))
            fi
        done
    fi
    
    if [ $env_count -eq 0 ]; then
        echo -e "No private virtual environments found in: $pvt_venv_dirs\n"
        return 0
    fi
    
    # Display environments with numbers
    for i in "${!env_list[@]}"; do
        echo "$((i + 1)). ${env_list[$i]}"
    done
    
    echo -e "\n"
    
    # Prompt user for environment to remove
    read -p "Enter the environment name or number to remove (or 'q' to quit): " env_input
    
    if [[ "$env_input" == "q" || "$env_input" == "Q" ]]; then
        echo -e "\nOperation cancelled.\n"
        return 0
    fi
    
    # Determine environment name
    if [[ $env_input =~ ^[0-9]+$ ]]; then
        # User entered a number
        if [ $env_input -gt 0 ] && [ $env_input -le ${#env_list[@]} ]; then
            env_name="${env_list[$((env_input - 1))]}"
        else
            echo -e "\n✗ Error: Invalid number. Please enter a number between 1 and ${#env_list[@]}.\n"
            return 1
        fi
    else
        # User entered a name
        env_name="$env_input"
        
        # Check if environment exists
        if [ ! -d "$pvt_venv_dirs/$env_name" ]; then
            # Try adding pvt_ prefix if not already present
            if [[ ! "$env_name" =~ ^pvt_ ]]; then
                env_name="pvt_$env_name"
            fi
            
            if [ ! -d "$pvt_venv_dirs/$env_name" ]; then
                echo -e "\n✗ Error: Environment '$env_name' does not exist.\n"
                return 1
            fi
        fi
    fi
    
    full_env_name="$env_name"
    
    # Display environment info
    echo -e "\nEnvironment to be removed:"
    echo -e "  Name: $full_env_name"
    echo -e "  Path: $pvt_venv_dirs/$full_env_name"
    
    # Show size of environment
    if [ -d "$pvt_venv_dirs/$full_env_name" ]; then
        env_size=$(du -sh "$pvt_venv_dirs/$full_env_name" 2>/dev/null | cut -f1)
        echo -e "  Size: $env_size"
    fi
    
    echo -e "\n⚠ WARNING: This action cannot be undone!"
    echo -e "All packages and data in this virtual environment will be permanently deleted.\n"
    
    # Confirm deletion
    read -p "Are you sure you want to remove '$full_env_name'? (yes/NO): " confirm
    
    if [[ "$confirm" != "yes" && "$confirm" != "YES" && "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "\n✗ Operation cancelled. Environment '$full_env_name' was NOT removed.\n"
        return 0
    fi
    
    # Double confirmation for safety
    echo -e "\n⚠ Final warning: This will permanently delete '$full_env_name'."
    read -p "Type 'DELETE' to confirm removal: " final_confirm
    
    if [[ "$final_confirm" != "DELETE" ]]; then
        echo -e "\n✗ Operation cancelled. Environment '$full_env_name' was NOT removed.\n"
        return 0
    fi
    
    # Remove the environment
    echo -e "\nRemoving environment '$full_env_name'...\n"
    
    if rm -rf "$pvt_venv_dirs/$full_env_name"; then
        echo -e "✓ Successfully removed private virtual environment: $full_env_name\n"
        
        # Verify removal
        if [ ! -d "$pvt_venv_dirs/$full_env_name" ]; then
            echo -e "✓ Verification: Environment '$full_env_name' has been completely removed.\n"
        else
            echo -e "⚠ Warning: Some files may still exist. Please check manually.\n"
        fi
    else
        echo -e "\n✗ Error: Failed to remove environment '$full_env_name'."
        echo -e "You may need to check permissions or remove it manually.\n"
        return 1
    fi
}

############################################
# Function: removePrjEnv
# Description: Removes a project virtual environment
# Usage: removePrjEnv
############################################
function removePrjEnv() {
    echo -e "\nFunction to remove Project Python Virtual Environment\n"
    
    # Set project environment directory
    declare prj_venv_dirs="/nas/data/data/projects/pyvenv/envs"
    
    # Reset variables
    local env_name=""
    local full_env_name=""
    local confirm=""
    local current_user=$(whoami)
    
    # Check if user has permission to access project environments
    if [ ! -d "$prj_venv_dirs" ]; then
        echo -e "\n✗ Error: Project virtual environment directory not found:"
        echo -e "  $prj_venv_dirs\n"
        return 1
    fi
    
    # Check if user can read the directory
    if [ ! -r "$prj_venv_dirs" ]; then
        echo -e "\n✗ Error: You don't have permission to read project environments."
        echo -e "  Contact your system administrator.\n"
        return 1
    fi
    
    # List available project environments
    echo -e "Available project virtual environments:\n"
    
    local env_count=0
    local env_list=()
    
    # Get all environments that start with 'prj_'
    for env in "$prj_venv_dirs"/*; do
        if [ -d "$env" ]; then
            env_name=$(basename "$env")
            
            # Check if user has permission to remove this environment
            # (User needs write permission on the directory or be in the owning group)
            if [ -w "$env" ] || [ "$(stat -c '%G' "$env")" == "$(id -gn "$current_user")" ]; then
                env_list+=("$env_name")
                ((env_count++))
            else
                echo -e "  $env_name (no write permission)"
            fi
        fi
    done
    
    if [ $env_count -eq 0 ]; then
        echo -e "No project virtual environments found that you have permission to remove.\n"
        echo -e "Note: You need write permission or group membership to remove project environments.\n"
        return 0
    fi
    
    # Display environments with numbers
    for i in "${!env_list[@]}"; do
        # Get environment info
        env_path="$prj_venv_dirs/${env_list[$i]}"
        env_group=$(stat -c '%G' "$env_path" 2>/dev/null || echo "unknown")
        env_owner=$(stat -c '%U' "$env_path" 2>/dev/null || echo "unknown")
        
        echo "$((i + 1)). ${env_list[$i]} (Group: $env_group, Owner: $env_owner)"
    done
    
    echo -e "\n"
    
    # Prompt user for environment to remove
    read -p "Enter the environment name or number to remove (or 'q' to quit): " env_input
    
    if [[ "$env_input" == "q" || "$env_input" == "Q" ]]; then
        echo -e "\nOperation cancelled.\n"
        return 0
    fi
    
    # Determine environment name
    if [[ $env_input =~ ^[0-9]+$ ]]; then
        # User entered a number
        if [ $env_input -gt 0 ] && [ $env_input -le ${#env_list[@]} ]; then
            env_name="${env_list[$((env_input - 1))]}"
        else
            echo -e "\n✗ Error: Invalid number. Please enter a number between 1 and ${#env_list[@]}.\n"
            return 1
        fi
    else
        # User entered a name
        env_name="$env_input"
        
        # Check if environment exists
        if [ ! -d "$prj_venv_dirs/$env_name" ]; then
            # Try adding prj_ prefix if not already present
            if [[ ! "$env_name" =~ ^prj_ ]]; then
                env_name="prj_$env_name"
            fi
            
            if [ ! -d "$prj_venv_dirs/$env_name" ]; then
                echo -e "\n✗ Error: Environment '$env_name' does not exist.\n"
                return 1
            fi
        fi
        
        # Check if user has permission to remove this environment
        env_path="$prj_venv_dirs/$env_name"
        if [ ! -w "$env_path" ] && [ "$(stat -c '%G' "$env_path")" != "$(id -gn "$current_user")" ]; then
            echo -e "\n✗ Error: You don't have permission to remove '$env_name'."
            echo -e "  You need write permission or be a member of the owning group.\n"
            return 1
        fi
    fi
    
    full_env_name="$env_name"
    env_path="$prj_venv_dirs/$full_env_name"
    
    # Display environment info
    echo -e "\nEnvironment to be removed:"
    echo -e "  Name: $full_env_name"
    echo -e "  Path: $env_path"
    
    # Get environment details
    env_group=$(stat -c '%G' "$env_path" 2>/dev/null || echo "unknown")
    env_owner=$(stat -c '%U' "$env_path" 2>/dev/null || echo "unknown")
    echo -e "  Group: $env_group"
    echo -e "  Owner: $env_owner"
    
    # Show size of environment
    if [ -d "$env_path" ]; then
        env_size=$(du -sh "$env_path" 2>/dev/null | cut -f1)
        echo -e "  Size: $env_size"
    fi
    
    # Check if environment is currently active
    if [[ "$VIRTUAL_ENV" == "$env_path" ]]; then
        echo -e "\n⚠ WARNING: This environment is currently active!"
        echo -e "  You are currently using: $VIRTUAL_ENV"
        echo -e "  Please deactivate before removing.\n"
        return 1
    fi
    
    echo -e "\n⚠ WARNING: This action cannot be undone!"
    echo -e "All packages and data in this project environment will be permanently deleted.\n"
    
    # Confirm deletion
    read -p "Are you sure you want to remove '$full_env_name'? (yes/NO): " confirm
    
    if [[ "$confirm" != "yes" && "$confirm" != "YES" && "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "\n✗ Operation cancelled. Environment '$full_env_name' was NOT removed.\n"
        return 0
    fi
    
    # Double confirmation for safety
    echo -e "\n⚠ Final warning: This will permanently delete the project environment '$full_env_name'."
    read -p "Type 'DELETE-PROJECT' to confirm removal: " final_confirm
    
    if [[ "$final_confirm" != "DELETE-PROJECT" ]]; then
        echo -e "\n✗ Operation cancelled. Environment '$full_env_name' was NOT removed.\n"
        return 0
    fi
    
    # Remove the environment
    echo -e "\nRemoving project environment '$full_env_name'...\n"
    
    # Try to remove with sudo if needed (but only if user is in the group)
    if rm -rf "$env_path"; then
        echo -e "✓ Successfully removed project virtual environment: $full_env_name\n"
        
        # Verify removal
        if [ ! -d "$env_path" ]; then
            echo -e "✓ Verification: Environment '$full_env_name' has been completely removed.\n"
            
            # Suggest to notify team members if this was a shared environment
            if [[ "$env_group" != "$current_user" && "$env_group" != "unknown" ]]; then
                echo -e "⚠ Note: This was a shared environment owned by group '$env_group'."
                echo -e "  You may want to notify other team members about this removal.\n"
            fi
        else
            echo -e "⚠ Warning: Some files may still exist. You may need administrator help.\n"
            return 1
        fi
    else
        echo -e "\n✗ Error: Failed to remove environment '$full_env_name'."
        echo -e "Possible reasons:"
        echo -e "  1. Insufficient permissions (try with sudo if you're in the correct group)"
        echo -e "  2. Files are in use by another process"
        echo -e "  3. Directory is mounted or has special permissions\n"
        
        # Suggest alternative command
        echo -e "You can try removing it manually with appropriate permissions:"
        echo -e "  sudo rm -rf '$env_path'\n"
        echo -e "Or contact your system administrator.\n"
        return 1
    fi
}

# Call the function
# createPvtEnv
# createSpecPvtEnv
# createPrjEnv
# createSpecPrjEnv
# removePvtEnv
# removePrjEnv
