"""
Restores LDAP configurations by creating groups, adding users, and associating users with groups using the `cluster` command. Data is loaded from a JSON file at /tmp/ldap_backup.json.
"""
import json
import subprocess
import progressbar
import getpass

def run_command(command_list):
    """Executes a shell command safely and logs the output."""
    try:
        subprocess.run(command_list, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as e:
        print(f"Failed to execute command '{' '.join(command_list)}': {e.stderr.decode().strip()}")

def extract_info_from_json(json_file_path):
    """Extracts group information from the JSON file."""
    with open(json_file_path, 'r') as file:
        data = json.load(file)
    return data.get("groups", {}), data.get("users", {}), data.get("associations", {})

def restore_ldap_configuration(group_info, user_info, user_groups_dict, password):
    """Executes commands to restore LDAP configurations."""
    # Define the maximum width of the progress bar
    MAX_BAR_WIDTH = 50  # Adjust this value as needed
    MAX_TERMINAL_WIDTH = 80  # Total width of the progress bar display

    # Create groups
    print("Restoring groups...")
    bar = progressbar.ProgressBar(
        max_value=len(group_info),
        term_width=MAX_TERMINAL_WIDTH,
        widgets=[
            progressbar.Bar('=', '[', ']', length=MAX_BAR_WIDTH),
            ' ',
            progressbar.Percentage(),
            ' (', progressbar.SimpleProgress(), ')',
            ' ', progressbar.Timer(),
            ' ', progressbar.ETA()
        ]
    )
    for i, (group, gid) in enumerate(group_info.items()):
        command = ["cluster", "group", "create", group, "--gid", gid]
        run_command(command)
        bar.update(i + 1)
    bar.finish()

    # Add users
    print("Restoring users...")
    bar = progressbar.ProgressBar(
        max_value=len(user_info),
        term_width=MAX_TERMINAL_WIDTH,
        widgets=[
            progressbar.Bar('=', '[', ']', length=MAX_BAR_WIDTH),
            ' ',
            progressbar.Percentage(),
            ' (', progressbar.SimpleProgress(), ')',
            ' ', progressbar.Timer(),
            ' ', progressbar.ETA()
        ]
    )
    for i, (user, details) in enumerate(user_info.items()):
        command = [
            "cluster", "user", "add", user,
            "--uid", str(details['uidNumber']),
            "--gid", str(details['gidNumber']),
            "--password", password,
            "--name", details['displayName']
        ]
        run_command(command)
        bar.update(i + 1)
    bar.finish()

    # Associate users with groups
    print("Restoring user and group associations...")
    total_associations = sum(len(groups) for groups in user_groups_dict.values())
    bar = progressbar.ProgressBar(
        max_value=total_associations,
        term_width=MAX_TERMINAL_WIDTH,
        widgets=[
            progressbar.Bar('=', '[', ']', length=MAX_BAR_WIDTH),
            ' ',
            progressbar.Percentage(),
            ' (', progressbar.SimpleProgress(), ')',
            ' ', progressbar.Timer(),
            ' ', progressbar.ETA()
        ]
    )
    current = 0
    for user, groups in user_groups_dict.items():
        for group in groups:
            command = ["cluster", "group", "add", group, user]
            run_command(command)
            current += 1
            bar.update(current)
    bar.finish()

def main():
    path = '/tmp/ldap_backup.json'  # Path to the JSON file

    # Prompt the user for the LDAP password
    print("Please enter the LDAP user password.")
    password = getpass.getpass(prompt="Password: ")

    # Extract information from JSON
    group_info, user_info, association_info = extract_info_from_json(path)

    # Restore LDAP configuration
    restore_ldap_configuration(group_info, user_info, association_info, password)

# Call the main function to run the program
if __name__ == '__main__':
    main()