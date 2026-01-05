############################################
# Function: generateMetadata
# Description: Generates metadata, requirements file, and backup for existing private/project venv
# Usage: generateMetadata [environment_name]
############################################
function generateMetadata() {
    echo -e "\nFunction to generate metadata and backup files for an existing private/project Python virtual environment\n"
    
    # Set directories - using same variables as other functions
    local pvt_envs_dirs="/nas/data/data/$USER/.pyvenv/envs"
    local prj_envs_dirs="/nas/data/data/projects/pyvenv/envs"
    local log_timestamp=$(date +%Y%m%d%H%M%S)
    local logFile="$HOME/venv_metadata_${log_timestamp}.log"
    
    # Clear log file
    > "$logFile"
    
    # Initialize variables matching the original function pattern
    local array_envs=()
    local cfg_fl=1
    local vEName=""
    
    # Check if environment name was passed as argument (preserving original pattern)
    if [ $# -gt 0 ] && [ ! -z "$1" ]; then
        vEName="$1"
        echo -e "cfg_fl func: $cfg_fl" | tee -a "$logFile"
        echo -e "vEName func: $vEName" | tee -a "$logFile"
    else
        cfg_fl=0
    fi
    
    # Get all available environments (venv style instead of conda)
    echo -e "Scanning for available virtual environments..." | tee -a "$logFile"
    
    # Get private environments
    if [ -d "$pvt_envs_dirs" ]; then
        for env in "$pvt_envs_dirs"/*; do
            if [ -d "$env" ] && [ -f "$env/bin/activate" ]; then
                env_name=$(basename "$env")
                array_envs+=("$env_name")
            fi
        done
    fi
    
    # Get project environments
    if [ -d "$prj_envs_dirs" ]; then
        for env in "$prj_envs_dirs"/*; do
            if [ -d "$env" ] && [ -f "$env/bin/activate" ]; then
                env_name=$(basename "$env")
                array_envs+=("$env_name")
            fi
        done
    fi
    
    # Sort environments
    array_envs=($(echo "${array_envs[@]}" | tr ' ' '\n' | sort))
    
    # If no environment name provided via argument or cfg_fl is 0, prompt user
    if [ -z "$cfg_fl" ] || [ "$cfg_fl" -ne 1 ] || [ -z "$vEName" ]; then
        echo -e "Here is the list of all private & project envs user- $USER can access:" | tee -a "$logFile"
        echo "${array_envs[*]}" | tr " " "\n" | tee -a "$logFile"
        
        if [ ${#array_envs[@]} -eq 0 ]; then
            echo -e "\nNo virtual environments found." | tee -a "$logFile"
            return 1
        fi
        
        read -p "Please enter the Virtual Environment Name from the above list, for which you wish to generate the metadata: " vEName
    fi
    
    # Validate environment name
    if [ -z "$vEName" ]; then
        echo -e "\nError: project/private VE name is empty- vEName: ''" | tee -a "$logFile"
        return 1
    fi
    
    # Check if environment exists in the list
    echo "${array_envs[*]}" | tr " " "\n" | grep -Eq "^$vEName$"
    st_available_envs=$?
    
    if [ $st_available_envs -eq 0 ]; then
        prefix=$(echo "$vEName" | cut -f1 -d "_")
        
        case "$prefix" in
            pvt) 
                vEPath="$pvt_envs_dirs"
                env_type="Private"
                ;;
            prj) 
                vEPath="$prj_envs_dirs"
                env_type="Project"
                ;;
            *)   
                vEPath="$pvt_envs_dirs"
                env_type="Private"
                ;;
        esac
        
        local full_env_path="$vEPath/$vEName"
        
        # Generate metadata file
        local metadata_file="$HOME/$vEName-metadata-${log_timestamp}.txt"
        echo -e "\nGenerating metadata file: $metadata_file for VE - $vEName\n" | tee -a "$logFile"
        
        # Write basic metadata
        {
            echo -e "Virtual Environment Name: $vEName"
            echo -e "Virtual Environment Type: $prefix"
            
            # Get group information
            if [ -d "$full_env_path" ]; then
                grpName=$(stat -c '%G' "$full_env_path" 2>/dev/null || echo "unknown")
                echo -e "Virtual Environment Group Name: $grpName"
                
                # Get owner
                owner=$(stat -c '%U' "$full_env_path" 2>/dev/null || echo "unknown")
                echo -e "Virtual Environment Owner: $owner"
                
                # Get permissions
                perms=$(stat -c '%A' "$full_env_path" 2>/dev/null || echo "unknown")
                echo -e "Virtual Environment Permissions: $perms"
                
                # Get size
                size=$(du -sh "$full_env_path" 2>/dev/null | cut -f1 || echo "unknown")
                echo -e "Virtual Environment Size: $size"
            fi
            
            echo -e "\nVirtual Environment Python Version:"
        } > "$metadata_file"
        
        # Get Python version (using the virtual environment's python)
        echo -e "\nGetting Python version..." | tee -a "$logFile"
        local python_exec="$full_env_path/bin/python"
        if [ -f "$python_exec" ]; then
            "$python_exec" --version >> "$metadata_file" 2>&1
            echo "Python executable: $python_exec" >> "$metadata_file"
        else
            echo "Python executable not found in virtual environment" >> "$metadata_file"
        fi
        
        # Get pip version
        local pip_exec="$full_env_path/bin/pip"
        if [ -f "$pip_exec" ]; then
            echo -e "Pip Version:" >> "$metadata_file"
            "$pip_exec" --version >> "$metadata_file" 2>&1
        fi
        
        # Generate package list (venv style - pip freeze)
        echo -e "\nWriting all installed Packages to the metadata file\n" | tee -a "$logFile"
        
        echo -e "\nList of pip installed packages:\n" >> "$metadata_file"
        echo -e "# Package    Version" >> "$metadata_file"
        
        if [ -f "$pip_exec" ]; then
            # Activate environment and get package list
            source "$full_env_path/bin/activate" && \
                pip list --format=columns >> "$metadata_file" 2>&1
            deactivate
        else
            echo "pip not found in virtual environment" >> "$metadata_file"
        fi
        
        # Generate detailed package list in freeze format
        echo -e "\nDetailed package list (pip freeze format):\n" >> "$metadata_file"
        
        if [ -f "$pip_exec" ]; then
            source "$full_env_path/bin/activate" && \
                pip freeze >> "$metadata_file" 2>&1
            deactivate
        fi
        
        # Generate requirements file (venv equivalent of conda spec file)
        local requirements_file="$HOME/$vEName-requirements-${log_timestamp}.txt"
        echo -e "\nGenerating requirements file: $requirements_file for VE - $vEName\n" | tee -a "$logFile"
        
        if [ -f "$pip_exec" ]; then
            source "$full_env_path/bin/activate" && \
                pip freeze > "$requirements_file" 2>&1
            deactivate
            
            st_metadata=${PIPESTATUS[0]}
            
            if [ $st_metadata -eq 0 ]; then
                echo -e "Successfully generated requirements file $requirements_file\n" | tee -a "$logFile"
                
                # Count packages
                local package_count=$(wc -l < "$requirements_file" 2>/dev/null || echo "0")
                echo -e "Total packages: $package_count" | tee -a "$logFile"
                
                # Generate backup file (venv backup)
                local backup_file="$HOME/$vEName-backup-${log_timestamp}.tar.gz"
                echo -e "\nGenerating backup file: $backup_file for VE - $vEName\n" | tee -a "$logFile"
                
                # Create tar.gz backup (excluding cache files)
                if tar --exclude="__pycache__" --exclude="*.pyc" --exclude="*.pyo" \
                     -czf "$backup_file" -C "$vEPath" "$vEName" 2>&1 | tee -a "$logFile"; then
                    st_backup=${PIPESTATUS[0]}
                    
                    if [ $st_backup -eq 0 ]; then
                        local backup_size=$(du -h "$backup_file" | cut -f1)
                        echo -e "\nSuccessfully generated backup file $backup_file ($backup_size)\n" | tee -a "$logFile"
                        
                        # Add backup info to metadata
                        echo -e "\nBackup Information:" >> "$metadata_file"
                        echo -e "Backup file: $(basename "$backup_file")" >> "$metadata_file"
                        echo -e "Backup size: $backup_size" >> "$metadata_file"
                        echo -e "Backup MD5: $(md5sum "$backup_file" | cut -d' ' -f1)" >> "$metadata_file"
                        
                        # Add requirements file info to metadata
                        echo -e "\nRequirements File:" >> "$metadata_file"
                        echo -e "File: $(basename "$requirements_file")" >> "$metadata_file"
                        echo -e "Package count: $package_count" >> "$metadata_file"
                        
                        # Add recreation instructions
                        echo -e "\nRecreation Instructions:" >> "$metadata_file"
                        echo -e "1. Extract backup: tar -xzf $backup_file -C /desired/path" >> "$metadata_file"
                        echo -e "2. OR create new environment and install packages:" >> "$metadata_file"
                        echo -e "   python -m venv new_env_name" >> "$metadata_file"
                        echo -e "   source new_env_name/bin/activate" >> "$metadata_file"
                        echo -e "   pip install -r $requirements_file" >> "$metadata_file"
                        
                        # Display summary
                        echo -e "\n✅ METADATA GENERATION COMPLETE" | tee -a "$logFile"
                        echo -e "=========================================" | tee -a "$logFile"
                        echo -e "Generated files in $HOME:" | tee -a "$logFile"
                        echo -e "  1. Metadata: $(basename "$metadata_file")" | tee -a "$logFile"
                        echo -e "  2. Requirements: $(basename "$requirements_file") ($package_count packages)" | tee -a "$logFile"
                        echo -e "  3. Backup: $(basename "$backup_file") ($backup_size)" | tee -a "$logFile"
                        echo -e "  4. Log file: $(basename "$logFile")" | tee -a "$logFile"
                        echo -e "\nTo recreate this environment elsewhere:" | tee -a "$logFile"
                        echo -e "  Use the requirements file: pip install -r $requirements_file" | tee -a "$logFile"
                        echo -e "  OR extract the backup archive.\n" | tee -a "$logFile"
                    else
                        echo -e "\nError: Failed to generate backup file for VE - $vEName. Please check logfile $logFile for more details.\n" | tee -a "$logFile"
                    fi
                else
                    st_backup=${PIPESTATUS[0]}
                    echo -e "\nError: Failed to generate backup file for VE - $vEName (tar exit code: $st_backup). Please check logfile $logFile for more details.\n" | tee -a "$logFile"
                fi
            else
                echo -e "\nError: Failed to generate requirements file for VE - $vEName. Please check logfile $logFile for more details.\n" | tee -a "$logFile"
            fi
        else
            echo -e "\nError: pip not found in virtual environment $vEName. Cannot generate package list.\n" | tee -a "$logFile"
            return 1
        fi
        
    else
        echo -e "\nError: $vEName not found in the list of prj & pvt envs user- $USER have access:" | tee -a "$logFile"
        echo -e "$(echo ${array_envs[*]} | tr ' ' '\n')\n" | tee -a "$logFile"
        return 1
    fi
}



========================

function generatePyVenvMetadata()
{
    echo -e "\nFunction to generate metadata and backup files for an existing Python virtual environment\n" \
        | tee -a ${logFile}

    # Collect all available python venvs
    array_envs=(
        $(find "$pvt_venvs_dirs" "$prj_venvs_dirs" -maxdepth 1 -mindepth 1 -type d 2>/dev/null \
          -exec basename {} \;)
    )

    cfg_fl=1
    vEName=$2

    echo -e "cfg_fl func: $cfg_fl"
    echo -e "vEName func: $vEName"

    if [ -z "$cfg_fl" ] || [ "$cfg_fl" -ne 1 ]
    then
        echo -e "Here is the list of all private & project python venvs user- $USER can access:"
        echo ${array_envs[*]} | tr " " "\n"
        read -p "Please enter the Virtual Environment Name from the above list: " vEName
    fi

    echo ${array_envs[*]} | tr " " "\n" | grep -Eq "^$vEName$"
    st_available_envs=$?

    if [[ -z "${vEName}" ]]
    then
        echo -e "\nError: python venv name is empty\n" | tee -a ${logFile}

    elif [ $st_available_envs -eq 0 ]
    then
        prefix=$(echo $vEName | cut -f1 -d "_")

        case "$prefix" in
            pvt) vEPath="$pvt_venvs_dirs" ;;
            prj) vEPath="$prj_venvs_dirs" ;;
            *)   vEPath="$pvt_venvs_dirs" ;;
        esac

        ACTIVATE_SCRIPT="$vEPath/$vEName/bin/activate"

        if [ ! -f "$ACTIVATE_SCRIPT" ]
        then
            echo -e "\nError: activate script not found for venv $vEName\n" | tee -a ${logFile}
            return 1
        fi

        META_FILE="$HOME/$vEName-metadata-${log_timestamp}.txt"
        SPEC_FILE="$HOME/$vEName-requirements-${log_timestamp}.txt"
        BACKUP_FILE="$HOME/$vEName-backup-${log_timestamp}.zip"

        echo -e "\nGenerating metadata file: $META_FILE\n" | tee -a ${logFile}

        echo -e "Virtual Environment Name: $vEName"            | tee -a "$META_FILE"
        echo -e "Virtual Environment Type: python-venv"       | tee -a "$META_FILE"
        echo -e "Virtual Environment Path: $vEPath/$vEName"   | tee -a "$META_FILE"

        grpName=$(stat -c '%G' "$vEPath/$vEName")
        echo -e "Virtual Environment Group Name: $grpName"    | tee -a "$META_FILE"

        echo -e "Python Version:"                              | tee -a "$META_FILE"
        source "$ACTIVATE_SCRIPT" && python --version 2>&1    | tee -a "$META_FILE"

        echo -e "\nPip Version:"                               | tee -a "$META_FILE"
        pip --version 2>&1                                    | tee -a "$META_FILE"

        echo -e "\nWriting installed packages to metadata\n"  | tee -a ${logFile}

        echo -e "\nList of pip installed packages:\n"          >> "$META_FILE"
        echo -e "# Name    Version"                             >> "$META_FILE"

        pip list --format=columns                              >> "$META_FILE" 2>&1
        pip list --format=freeze                               >  "$SPEC_FILE" 2>&1

        st_metadata=$?

        if [ $st_metadata -eq 0 ]
        then
            echo -e "\nSuccessfully generated pip metadata and requirements file\n" | tee -a ${logFile}

            echo -e "\nGenerating backup file: $BACKUP_FILE\n" | tee -a ${logFile}

            zip -r "$BACKUP_FILE" "$vEPath/$vEName" \
                2>&1 | tee -a ${logFile}

            st_backup=${PIPESTATUS[0]}

            if [ $st_backup -eq 0 ]
            then
                echo -e "\nSuccessfully generated backup file $BACKUP_FILE\n" | tee -a ${logFile}
            else
                echo -e "\nError: Failed to generate backup file for venv $vEName\n" | tee -a ${logFile}
            fi
        else
            echo -e "\nError: Failed to generate metadata for venv $vEName\n" | tee -a ${logFile}
        fi
    else
        echo -e "\nError: $vEName not found in available python venvs:\n$(echo ${array_envs[*]} | tr ' ' '\n')\n" \
            | tee -a ${logFile}
    fi
}
