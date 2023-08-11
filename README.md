# Docker Image Cleanup Script for Gitlab Registry

This Bash script automates the management of Docker image tags in your GitLab registry. It performs the following steps:

1. **Matching Docker Tags**: The script starts by using regular expressions to match Docker image tags. If a tag matches the specified regex pattern, it proceeds to the next step.

2. **Retention Period Check**: For matched tags, the script checks if they fall within the specified retention period. Tags within the retention period are saved to an array along with their creation timestamps.

3. **Sorting and Retention**: Once all tags for a repository are collected in the array, the script sorts them based on their creation timestamps. It then retains only the N latest tags as defined. These retained tags are kept for further processing, ensuring only the most recent ones are considered.

4. **Deletion of Older Tags**: The script iterates through the remaining tags (those not retained) and checks if they exceed the retention period. Tags outside the retention period are deleted from the repository, freeing up space and maintaining a manageable tag history.

5. **Record Keeping**: The script will create three files in the currect directory.\
  i. `deleted_tags_file`: This file keeps the record of all the deleted tags and their age.\
  ii. `keep_n_tags_file`: This file keeps the record of all the retained tags and their age.\
  iii. `deleted_tags_proj`: This file keeps the number of images that are deleted in the whole project. If the project has multiple repository it will list all the repository and the total tags deleted in all the repository. If any project does not have a repository, this file will also have such information

## Parameters

Before using the script, configure the following parameters:

- **GITLAB_API_URL**: The URL of your GitLab API (e.g., `https://gitlab.example.com`).
- **TOKEN**: Your GitLab personal access token.
- **NAME_REGEX_DELETE**: The regex pattern used to match Docker image tags for deletion.
- **RETENTION_DAYS**: The maximum age (in days) of Docker image tags to be retained.
- **NUM_LATEST_TO_RETAIN**: Number of Latest tags by creation date of Matched Regex to Retain in Repository.


## Usage

1. Update the script with your GitLab credentials and repository information.
2. Set the desired regular expression (`NAME_REGEX_DELETE`) to match Docker tags.
3. Configure the retention period (`RETENTION_DAYS`) and the number of latest tags to retain (`NUM_LATEST_TO_RETAIN`).
4. Run the script using `bash gitlab-registry-cleaner.sh`.

By using this script, you can effectively manage your Docker image tags in a GitLab registry, automatically keeping the most recent tags and removing older ones. This helps optimize storage usage and keeps your tag history organized.

## Disclaimer

Please ensure thorough testing in a controlled environment before deploying any changes to a production environment. Docker image management can have critical implications, so take appropriate precautions.

## License

This script is provided under the [MIT License](LICENSE).

