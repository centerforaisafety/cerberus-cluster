"""
Automates the LDAP backup process, including:
- Extracting group, user, and association information.
- Compressing the backup file.
- Uploading the backup to Object Storage.

Logging: Outputs logs to /opt/oci-hpc/logs/backups/backup_ldap.log

Dependencies:
- Python 3.x
- `cluster` CLI tool for retrieving LDAP data
- `oci` CLI tool for uploading to Object Storage
"""

import subprocess
import re
import json
import logging
from typing import Dict, List
from datetime import datetime

# Configure logging
logging.basicConfig(
    filename='/opt/oci-hpc/logs/backups/backup_ldap.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

def run_command(command: str) -> str:
    """Executes a shell command and returns the output as a string."""
    try:
        process = subprocess.run(command, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return process.stdout
    except subprocess.CalledProcessError as e:
        logging.error(f"Command '{command}' failed with error: {e.stderr}")
        return ""

# Extract group information
def extract_group_info(output: str) -> Dict[str, str]:
    """Parses the command output to extract group information."""
    group_info = {}
    lines = output.splitlines()
    
    current_group_name = None
    for line in lines:
        line = line.strip()
        if line.startswith('cn:'):
            current_group_name = line.split(':')[1].strip()
        elif line.startswith('gidNumber:'):
            group_id = line.split(':')[1].strip()
            if current_group_name:
                group_info[current_group_name] = group_id
    return group_info

# Extract user information
def extract_user_info(output: str) -> Dict[str, Dict[str, str]]:
    """Parses the command output to extract user information."""
    user_info = {}
    user_blocks = re.findall(r"DN: cn=(.*?)(?=DN: cn=|$)", output, re.DOTALL)
    
    for block in user_blocks:
        uid = re.search(r"uid: (\S+)", block)
        uid_number = re.search(r"uidNumber: (\d+)", block)
        gid_number = re.search(r"gidNumber: (\d+)", block)
        display_name = re.search(r"displayName: (.*)", block)

        if uid and uid_number and gid_number:
            user_info[uid.group(1)] = {
                'uidNumber': uid_number.group(1),
                'gidNumber': gid_number.group(1),
                'displayName': display_name.group(1).strip() if display_name else "Unknown"
            }
    return user_info

# Extract user-group associations
def extract_users(output: str) -> List[str]:
    """Extracts user names from the command output using regular expressions."""
    user_entries = re.findall(r'uid:\s*(\w+)', output)
    return user_entries

def get_user_groups(user: str) -> List[str]:
    """Retrieves the groups for a given user using the 'id -Gn' command."""
    try:
        result = subprocess.run(['id', '-Gn', user], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if result.returncode == 0:
            return result.stdout.strip().split()
        else:
            logging.error(f"Error retrieving groups for user {user}: {result.stderr}")
            return []
    except Exception as e:
        logging.error(f"An error occurred while retrieving groups for user {user}: {e}")
        return []

# Main function to generate, compress, and upload the backup
def main():
    """Main function to run commands, parse output, compress, and upload the backup."""
    # Generate a timestamp for the backup file
    timestamp = datetime.now().strftime('%Y_%m_%d')
    output_file = f'/tmp/ldap_backup_{timestamp}.json'
    compressed_file = f'{output_file}.gz'
    
    logging.info("Starting LDAP backup process.")

    # Extract group information
    group_command = 'cluster group list'
    group_output = run_command(group_command)
    groups = extract_group_info(group_output)

    # Extract user information
    user_command = 'cluster user list'
    user_output = run_command(user_command)
    users = extract_user_info(user_output)

    # Extract user-group associations
    user_names = extract_users(user_output)
    associations = {user: get_user_groups(user) for user in user_names}

    # Combine all dictionaries into one JSON
    combined_data = {
        "groups": groups,
        "users": users,
        "associations": associations
    }

    # Write to JSON file
    try:
        with open(output_file, 'w') as json_file:
            json.dump(combined_data, json_file, indent=4)
    except IOError as e:
        logging.error(f"Failed to write to {output_file}: {e}")
        return

    # Compress the JSON file
    try:
        subprocess.run(['gzip', output_file], check=True)
    except subprocess.CalledProcessError as e:
        logging.error(f"Compression failed: {e}")
        return

    # Upload the compressed file to Object Storage
    try:
        bucket_name = 'backups'
        oci_command = f'oci os object put --bucket-name {bucket_name} --file {compressed_file}'
        subprocess.run(oci_command, shell=True, check=True)
    except subprocess.CalledProcessError as e:
        logging.error(f"Upload failed: {e}")

    logging.info("LDAP backup process completed.")

# Run the main function
if __name__ == '__main__':
    main()