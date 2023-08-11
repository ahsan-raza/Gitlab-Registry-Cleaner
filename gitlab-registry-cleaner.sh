#!/bin/bash



# Docker Image Management Script
# This script automates the management of Docker image tags in a GitLab container registry. 
# It performs a series of steps to ensure that only the most relevant and recent tags are retained while older and unnecessary tags are deleted. 
# The script starts by matching Docker tags using regular expressions, then checks if they fall within the retention period. 
# Tags that meet the criteria are collected in an array along with their creation timestamps.
# After gathering all tags for a repository, the script sorts them based on their creation timestamps and retains only the N latest tags, deleting the rest. 
# This process helps optimize storage and ensures that repositories are maintained with up-to-date and relevant images.
#
# Please replace the placeholder variables below with your GitLab credentials and registry information.


echo -e "\n\n#############################################################################################"
echo -e "#                 Docker Image Management Script                                            #"
echo -e "# This script automates the management of Docker image tags in a GitLab container registry. # "
echo -e "#############################################################################################\n\n"

# Replace these variables with your GitLab credentials and registry information
GITLAB_URL="https://gitlab.example.com"
TOKEN="<acces_token>"
NAME_REGEX_DELETE="\\d+\\.\\d+-[a-zA-Z]+\\d+_[a-z]-[A-Z]+-\\d+-\\w{31,}"
RETENTION_DAYS=71
# Set the number of latest tags to retain
NUM_LATEST_TO_RETAIN=2


current_timestamp=$(date +%s)

deleted_tags_file="deleted_tags_$(date +"%Y-%m-%d_%H-%M-%S").txt"
echo "" > "$deleted_tags_file"

keep_n_tags_file="keep_n_tags_files$(date +"%Y-%m-%d_%H-%M-%S").txt"
echo "" > "$keep_n_tags_file"

deleted_tags_proj="deleted_tags_proj$(date +"%Y-%m-%d_%H-%M-%S").txt"
echo -e "This file Keeps the record of deleted images per project\n\n" > "$deleted_tags_proj"


# Function to delete Docker images using the API call
function delete_docker_image() {
    project_id="$1"
    repository_id="$2"
    tag_name="$3"
    curl -kL --request DELETE --header "PRIVATE-TOKEN: ${TOKEN}" "${GITLAB_URL}/api/v4/projects/${project_id}/registry/repositories/${repository_id}/tags/${tag_name}"
}

# Function to get the total number of pages from the API response headers
function get_total_pages() {
    curl -s -kL -I --header "PRIVATE-TOKEN: ${TOKEN}" "${GITLAB_URL}/api/v4/projects" | grep -i 'x-total-pages' | awk '{print $2}' | tr -d '\r\n'
}

# Get the total number of pages
total_pages=$(get_total_pages)
del_count=0
count_proj=0

# Loop through each page of projects
for ((page = 1; page <= total_pages; page++)); do
    # Fetch the projects for the current page
    projects=$(curl -s -kL --header "PRIVATE-TOKEN: ${TOKEN}" "${GITLAB_URL}/api/v4/projects?page=${page}&per_page=100")
    echo -e "Current Gitlab API page is: $page \n"
    # Iterate through each project on the current page
    for project in $(echo "${projects}" | jq -r '.[] | @base64'); do
        project_id=$(echo "${project}" | base64 --decode | jq -r '.id')
        project_name=$(echo "${project}" | base64 --decode | jq -r '.name')
        echo '==================================================================================='
        echo "Processing project: ${project_name} (ID: ${project_id})"
        let "count_proj+=1"
        # Get the list of Docker repositories for each project
        repositories=$(curl -s -kL --header "PRIVATE-TOKEN: ${TOKEN}" "${GITLAB_URL}/api/v4/projects/${project_id}/registry/repositories")

        # Iterate through each Docker repository and delete the images based on the tags
        for repository in $(echo "${repositories}" | jq -r '.[] | @base64'); do
            latest_tags=()
            sorted_tags=()
            repository_id=$(echo "${repository}" | base64 --decode | jq -r '.id')
            repository_name=$(echo "${repository}" | base64 --decode | jq -r '.path')
            echo -e "\n\n    ###########################################################################"
            echo "     Processing repository:=============> ${repository_name} (ID: ${repository_id})"
            # Get the list of tags for each Docker repository
            tags=$(curl -s -kL --header "PRIVATE-TOKEN: ${TOKEN}" "${GITLAB_URL}/api/v4/projects/${project_id}/registry/repositories/${repository_id}/tags")
            current_timestamp=$(date +%s)
            # Iterate through each tag and delete the images based on the regex
            for tag in $(echo "${tags}" | jq -r '.[] | @base64'); do
                tag_name=$(echo "${tag}" | base64 --decode | jq -r '.name')
                echo "       Processing tag:=============> ${tag_name}"
                if echo "$tag_name" | grep -Pq "$NAME_REGEX_DELETE"; then
                    echo -e "         TAG NAME: $tag_name matches with REGEX $NAME_REGEX_DELETE but will check the retention policy in next step"
                    tag_details=$(curl -s -kL --header "PRIVATE-TOKEN: ${TOKEN}" "${GITLAB_URL}/api/v4/projects/${project_id}/registry/repositories/${repository_id}/tags/${tag_name}")
                    created_at=$(echo "${tag_details}"  | jq -r '.created_at')
                    created_at_timestamp=$(date -d "${created_at}" +%s)
                    age_in_days=$(( (current_timestamp - created_at_timestamp) / (60*60*24) ))
                    if [ "$age_in_days" -gt "$RETENTION_DAYS" ]; then
                        latest_tags+=("${tag_name} ${created_at_timestamp}")
                    fi
                    # printf '      Latest tags with TimeStamp in if condition %s\n' "${latest_tags[@]}"
                else
                    echo "      Tag does not match the regex pattern:=============> ${tag_name}"
                fi
            done

            # Sort the latest_tags array in reverse order (newest first)
            if [ "${#latest_tags[@]}" -gt 0 ]; then

                echo "         Total Tags matched with REGEX and fall outside retention period :  ${#latest_tags[@]}"

                # Sort the latest_tags array based on the creation timestamp (oldest first)
                IFS=$'\n' sorted_tags=($(sort -n -k2 <<<"${latest_tags[*]}"))
                unset IFS

                # Determine the number of sorted tags available
                
                num_sorted_tags="${#sorted_tags[@]}"
                # If there are fewer sorted tags than the specified number to retain,
                # move all sorted tags to latest_tags
                if [ "$num_sorted_tags" -le "$NUM_LATEST_TO_RETAIN" ]; then
                    latest_tags=("${sorted_tags[@]}")
                else
                    # If there are more sorted tags than the specified number to retain,
                    # move only the latest NUM_LATEST_TO_RETAIN tags to latest_tags
                    latest_tags=("${sorted_tags[@]: -$NUM_LATEST_TO_RETAIN}")
                fi
                echo -e "         Latest Tags to KEEP : \n"
                for element in "${latest_tags[@]%% *}"; do
                    echo -e "           $element \n"
                done
            fi

            # variable to store the count of deleted tags in all repository of one project
            del_local=0
            # Iterate through the latest N tags and retain them
            for tag_info in "${latest_tags[@]}"; do
                tag_name="${tag_info%% *}"  # Extract the tag name from the info
                created_at_timestamp="${tag_info##* }"  # Extract the creation timestamp from the info
                age_in_days=$(( (current_timestamp - created_at_timestamp) / (60*60*24) ))
                # Get the created_at date for the tag
                tag_details=$(curl -s -kL --header "PRIVATE-TOKEN: ${TOKEN}" "${GITLAB_URL}/api/v4/projects/${project_id}/registry/repositories/${repository_id}/tags/${tag_name}")
                location=$(echo "${tag_details}" | jq -r '.location')
                
                # Retain the tag (latest)
                echo "         Retaining tag (latest):=============> ${location}"
                echo "         Age of Retaining tag (latest):=============> ${age_in_days} days"
                echo "${location}" "    " "${age_in_days}" " days" >> "$keep_n_tags_file"

            done

            # Iterate through the rest of the tags and delete them
            for tag_info in "${sorted_tags[@]}"; do
                tag_name="${tag_info%% *}"  # Extract the tag name from the info
                created_at_timestamp="${tag_info##* }"  # Extract the creation timestamp from the info

                # Skip tags that are retained
                if [[ " ${latest_tags[*]} " == *" $tag_name "* ]]; then
                    continue
                fi

                # Calculate the age of the image in days
                age_in_days=$(( (current_timestamp - created_at_timestamp) / (60*60*24) ))
                
                if [ "$age_in_days" -gt "$RETENTION_DAYS" ]; then
                    let "del_local+=1"
                    let "del_count+=1"
                    echo "         Deleting tag:=============> ${tag_name}"
                    echo "         Age of deleting tag (latest):=============> ${age_in_days}" 
                    #delete_docker_image "${project_id}" "${repository_id}" "${tag_name}"
                    # Add the deleted tag URL to the text file
                    echo "${location}" "    " "${age_in_days}" " days" >> "$deleted_tags_file"
                # control will never come here as age is already checked before, its useless else but still keeping it.
                # else
                #     echo "      Tag is within retention period:=============> ${tag_name}"
                fi
            done
    
            echo -e "    ###########################################################################\n\n"

        done
        echo -e '===================================================================================\n\n'
        prj_details=$(curl -s -kL --header "PRIVATE-TOKEN: ${TOKEN}" "${GITLAB_URL}/api/v4/projects/${project_id}/registry/repositories")
        if [[ $(echo "$prj_details"  | jq -r '. | length') -eq 0 ]]; then
          echo -e "          Project: $project_name does not have repository\n\n"
          echo -e "Project: $project_name does not have repository\n" >> $deleted_tags_proj
        else
          prj_location=$(echo "${prj_details}" | jq -r '.[].location')
          echo -e "          Total Image(s) deleted in PROJECT: $prj_location  are =======================> $del_local\n\n"
          echo -e "Total Image(s) deleted in PROJECT: $prj_location  are =======================> $del_local \n" >> $deleted_tags_proj
        fi
    done
    echo -e "###############################################################################"

    echo -e  "    Projects Evaluated so far: =============> $count_proj\n"
    echo -e "     Number of Deleted Tags : =============> $del_count \n"
    echo -e "###############################################################################\n\n"

done
