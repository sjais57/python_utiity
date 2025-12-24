#!/bin/bash

cur_timestamp=$(date +%Y/%m/%d_%H:%M:%S)
log_timestamp=$(date +%Y%m%d%H%M%S)
cur_date=$(date +%Y-%m-%d)

declare pvt_venv_dirs="/nas/data/data/$USER/pyvenv/envs"

# Ensure cfg_fl is initialized
cfg_fl=0

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
        read -p "Please enter the Python version to use (Default to 3.10 if not specified): " pyVersion

        # Validate Python version
        if [ -z "$pyVersion" ]; then
            pyVersion="3.10"
        fi
    fi

    # Check if the exact Python version exists
    ls /efs/dist/python/core/ | grep -Eq "^${pyVersion}$"
    st_available_py_version=$?

    # If the exact version is not available, check for subversions
    if [ $st_available_py_version -ne 0 ]; then
        major_minor_version=$(echo "$pyVersion" | cut -d'.' -f1,2)
        
        # Get all directories and filter for proper version numbers
        # Using regex to match only X.Y.Z format (where Z can be any number)
        subversions=($(ls /efs/dist/python/core/ | grep -E "^${major_minor_version}\.[0-9]+$"))
        
        # If no exact X.Y.Z versions found, try a more flexible pattern
        if [ ${#subversions[@]} -eq 0 ]; then
            subversions=($(ls /efs/dist/python/core/ | grep -E "^${major_minor_version}\.[0-9]+[^[:alpha:]]*$" | grep -vE '.*-.*'))
        fi
        
        # Clean up the list - remove any non-version directories that might have slipped through
        clean_subversions=()
        for version in "${subversions[@]}"; do
            # Check if it matches the pattern of a version number (X.Y or X.Y.Z)
            if [[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
                clean_subversions+=("$version")
            fi
        done
        subversions=("${clean_subversions[@]}")
        
        if [ ${#subversions[@]} -eq 0 ]; then
            echo -e "\nError: No available versions found for Python ${major_minor_version}. Please install one."
            exit 1
        else
            echo -e "\nThe exact version '${pyVersion}' is not available. Here are the available subversions:"
            # Sort versions numerically
            IFS=$'\n' sorted_subversions=($(sort -V <<<"${subversions[*]}"))
            unset IFS
            
            # Create an associative array for quick lookup
            declare -A version_map
            for i in "${!sorted_subversions[@]}"; do
                echo "$((i + 1)). ${sorted_subversions[$i]}"
                version_map[$((i + 1))]="${sorted_subversions[$i]}"
                version_map["${sorted_subversions[$i]}"]="${sorted_subversions[$i]}"
            done

            # Prompt user to select a subversion
            echo -e "\nYou can enter either the number (e.g., 1) or the version (e.g., 3.11.12)"
            read -p "Please select a version by entering the corresponding number or version: " version_choice
            
            # Check if input is a number
            if [[ $version_choice =~ ^[0-9]+$ ]]; then
                # User entered a number
                if [[ $version_choice -gt 0 && $version_choice -le ${#sorted_subversions[@]} ]]; then
                    pyVersion=${version_map[$version_choice]}
                    echo -e "\nYou selected Python version: $pyVersion\n"
                else
                    echo -e "\nInvalid number selection. Please enter a number between 1 and ${#sorted_subversions[@]}."
                    exit 1
                fi
            else
                # User entered a version string
                version_found=false
                for version in "${sorted_subversions[@]}"; do
                    if [[ "$version_choice" == "$version" ]]; then
                        pyVersion="$version_choice"
                        version_found=true
                        echo -e "\nYou selected Python version: $pyVersion\n"
                        break
                    fi
                done
                
                if [ "$version_found" = false ]; then
                    echo -e "\nInvalid version selection. '$version_choice' is not in the list of available versions."
                    exit 1
                fi
            fi
        fi
    fi

    pyExec="/efs/dist/python/core/${pyVersion}/bin/python3"

    # Prompt for default packages
    read -p "Please enter the specific packages to be installed with the VE, each separated by comma. This is optional (Ex: graphviz,matplotlib==3.10.3,plotly): " default_packages

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

# Call the function
createPvtEnv
