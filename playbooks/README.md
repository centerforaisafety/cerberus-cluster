This is the '/playbooks' directory. In this directory are a collection of playbooks that are used to configure the compute cluster and high availability NFS. 
The original playbooks were written by Oracle Cloud Infrastructure engineers. New playbooks and updates to existing playbooks is done by engineers at the Center for AI Safety. 

Most of these playbooks should not be executed manually. 

Those playbooks that can be run manually are:
- add_root_ssh_key.yml
- remove_root_ssh_key.yml
- mount_nfs_exports_on_to_bastion.yml
- swap_data.yml
- swap_home.yml