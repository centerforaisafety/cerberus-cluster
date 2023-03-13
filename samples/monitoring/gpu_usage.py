import json
import subprocess
import yaml

# What does the file do?
# get ansible hosts "ansible all --list-hosts"
# parse out the compute nodes
# run ssh compute_node "nvidia-smi --query-compute-apps=pid,gpu_uuid,process_name,used_gpu_memory --format=csv,noheader"
# nvidia-smi --query-gpu=index,memory.used,memory.total,uuid --format=csv,noheader,nounits
# get the pids and get the users from the pid with "ps -o pid,uname= --no-headers -A r"
# use uuid and hack them into gpu number.
# parse the output for every node

save_file = "/home/opc/logs/gpu_usage.json"

# get the hosts to get compute nodes
command = "ansible all --list-hosts"
returned_val = subprocess.check_output(command, shell=True).decode("utf-8")
host_dict = yaml.safe_load(returned_val)

compute_nodes = [x for x in host_dict[list(host_dict.keys())[0]].split() if not x.startswith("watch-tower")]

# store the results in a dict
compute_node_usage = {}
# format
# {
#     node: {
#         gpu_num: [
#             user,
#             pid,
#             process_name,
#             pid_mem_usage,
#             total_gpu_mem_used,
#             total_gpu_mem
#         ]
#     }
# }

for compute_node in compute_nodes:
    if not compute_node:
        continue
    ssh_command = f"ssh {compute_node} 'nvidia-smi --query-compute-apps=pid,gpu_uuid,process_name,used_gpu_memory --format=csv,noheader'"
    ssh_returned_val = subprocess.check_output(ssh_command, shell=True).decode("utf-8")

    ssh_mem_command = f"ssh {compute_node} 'nvidia-smi --query-gpu=index,memory.used,memory.total,uuid --format=csv,noheader,nounits'"
    ssh_mem_returned_val = subprocess.check_output(ssh_mem_command, shell=True).decode("utf-8")

    ps_command = f"ssh {compute_node} 'ps -o pid,uname= --no-headers -A r'"
    ps_returned_val = subprocess.check_output(ps_command, shell=True).decode("utf-8")
    pids_to_users = {}
    for pid_user in ps_returned_val.split("\n"):
        if not pid_user:
            continue
        pid, user = pid_user.split()
        pids_to_users[pid] = user

    gpu_uuid_to_index = {}
    for tmp in ssh_mem_returned_val.split("\n"):
        if not tmp:
            continue
        gpu_index, used_mem, max_mem, uuid = tmp.split(", ")
        gpu_uuid_to_index[uuid] = {
            "gpu_index": gpu_index,
            "used_mem": used_mem,
            "max_mem": max_mem,
        }

    # get the pids and add them to a set
    gpu_processes = ssh_returned_val.split("\n")
    for process in gpu_processes:
        if not process:
            continue
        pid, uuid, process_name, memory_usage = process.split(", ")

        if compute_node_usage.get(compute_node) is None:
            compute_node_usage[compute_node] = {
                gpu_uuid_to_index[uuid]["gpu_index"]:
                    [[
                    pids_to_users.get(pid), 
                    pid,
                    process_name,
                    memory_usage,
                    gpu_uuid_to_index[uuid]["used_mem"],
                    gpu_uuid_to_index[uuid]["max_mem"]
                    ]]
                }
        else:
            if compute_node_usage[compute_node].get(gpu_uuid_to_index[uuid]["gpu_index"]) is None:
                compute_node_usage[compute_node].update({
                    gpu_uuid_to_index[uuid]["gpu_index"]:
                        [[
                        pids_to_users.get(pid), 
                        pid,
                        process_name,
                        memory_usage,
                        gpu_uuid_to_index[uuid]["used_mem"],
                        gpu_uuid_to_index[uuid]["max_mem"]
                        ]]
                    })
            else:
                compute_node_usage[compute_node][gpu_uuid_to_index[uuid]["gpu_index"]].append(
                        [
                        pids_to_users.get(pid), 
                        pid,
                        process_name,
                        memory_usage,
                        gpu_uuid_to_index[uuid]["used_mem"],
                        gpu_uuid_to_index[uuid]["max_mem"]
                        ]
                )

with open(save_file, "w") as f:
    json.dump(compute_node_usage, f, indent=4)
