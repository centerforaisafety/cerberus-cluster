import datetime
import json
import subprocess
from pathlib import Path


#Example command we want to extract
#sacct -a -S 2023-02-28-12:00:00 -E  2023-02-28-13:00:00 -P --noconvert --noheader -o 'user,JobID,Account,NCPUs,ReqMem,elapsedraw,cputimeraw,alloctres'

date_time_list = []
job_dict = {
    "job_ids": {},
    "dates": {},
    "users": {},
    }
save_file = "/home/opc/logs/slurm_usage.json"

def roundTime(dt=None, roundTo=60):
    """
    Round a datetime object to any time lapse in seconds.
    Source: https://stackoverflow.com/questions/3463930/how-to-round-the-minute-of-a-datetime-object/10854034#10854034
    Author: Thierry Husson 2012 - Use it as you want but don't blame me.
    Args:
        dt : datetime.datetime object, default now.
        roundTo : Closest number of seconds to round to, default 1 minute.    
    Returns:
        datetime object rounded to whatever value.
    """
    if dt == None : dt = datetime.datetime.now()
    seconds = (dt.replace(tzinfo=None) - dt.min).seconds
    rounding = (seconds+roundTo/2) // roundTo * roundTo
    return dt + datetime.timedelta(0,rounding-seconds,-dt.microsecond)

now = roundTime()
end = now - datetime.timedelta(days=30)

while now > end:
    date_time_list.append(now.strftime("%Y-%m-%d-%H:%M:%S"))
    now = now - datetime.timedelta(hours=1)


def add_or_remove_to_dict(returned_val, date_time_list, index, add=False, remove=False):
    """
    Updates the global job_dict to either add or remove elements. 
    Such as jobs that were run, total gpu usage, and mapping of users to gpu usage.
    Args:
        returned_val: string of what sacct shell command returns.
        date_time_list: list of datetimes in the proper format e.g. strftime("%Y-%m-%d-%H:%M:%S")
        index: int which element of date_time_list to use.
        add: bool whether to add elements to job_dict.
        remove: bool whether to remove elements from job_dict.

    """
    if add == remove:
        print("Error in use of add or remove.")
        exit()

    total_gpus = 0
    for item in returned_val:
        if not item:
            continue
        slurm_data = item.split("|")
        user = slurm_data[0]
        job_id = slurm_data[1]
        account = slurm_data[2]
        n_cpus = int(slurm_data[3])
        req_mem = slurm_data[4]
        elapsed_time = int(slurm_data[5])
        alloc_tres = slurm_data[7]
        alloc_tres = alloc_tres.split(",")
        # ignore the cpu jobs on the cluster for now
        if len(alloc_tres) < 4:
            continue
        num_gpus = int(alloc_tres[2][alloc_tres[2].find("=")+1:])
        num_nodes = int(alloc_tres[3][alloc_tres[3].find("=")+1:])
        total_gpus += num_gpus
        if add:
            job_dict["job_ids"][job_id] = {
                "user": user,
                "job_id": job_id,
                "account": account,
                "n_cpus": n_cpus,
                "req_mem": req_mem,
                "elapsed_time": elapsed_time,
                "num_gpus": num_gpus,
                "num_nodes": num_nodes,
            }
            user_stats = job_dict["users"].get(user)
            if user_stats is None:
                job_dict["users"][user] = elapsed_time * num_gpus
            else:
                job_dict["users"][user] += elapsed_time * num_gpus
        elif remove:
            del job_dict["job_ids"][job_id]
            user_stats = job_dict["users"].get(user)
            if user_stats is not None:
                job_dict["users"][user] -= elapsed_time * num_gpus
            if job_dict["users"][user] < 0:
                del job_dict["users"][user]
    if add:
        job_dict["dates"][date_time_list[index]] = total_gpus
    elif remove:
        del job_dict["dates"][date_time_list[index]]


my_file = Path(save_file)

# if it exists just update the latest one and remove the old one.
if my_file.is_file():
    # Remove old entries.
    older_end = (end - datetime.timedelta(hours=1)).strftime("%Y-%m-%d-%H:%M:%S")
    command = ("sacct -a -S {} ".format(older_end) +
                "-E {} -P ".format(end.strftime("%Y-%m-%d-%H:%M:%S")) +
                "--noconvert --noheader "
                "-o 'user,JobID,Account,NCPUs,ReqMem,elapsedraw,cputimeraw,alloctres' " 
        )
    returned_val = subprocess.check_output(command, shell=True).decode("utf-8").split("\n")[::3]
    add_or_remove_to_dict(returned_val, [older_end], 0, remove=True)

    # Add new entries.
    hour_less_than_now = (now - datetime.timedelta(hours=1)).strftime("%Y-%m-%d-%H:%M:%S")
    command = ("sacct -a -S {} ".format(hour_less_than_now) +
                "-E {} -P ".format(now.strftime("%Y-%m-%d-%H:%M:%S")) +
                "--noconvert --noheader "
                "-o 'user,JobID,Account,NCPUs,ReqMem,elapsedraw,cputimeraw,alloctres' " 
        )
    returned_val = subprocess.check_output(command, shell=True).decode("utf-8").split("\n")[::3]

    add_or_remove_to_dict(returned_val, [hour_less_than_now], 0, add=True)

# Otherwise just grab all of the entries for the past month.
else:
    for index, date_time_val in enumerate(date_time_list[:-1]):
        command = ("sacct -a -S {} ".format(date_time_list[index+1]) +
                "-E {} -P ".format(date_time_list[index]) +
                "--noconvert --noheader "
                "-o 'user,JobID,Account,NCPUs,ReqMem,elapsedraw,cputimeraw,alloctres' " 
        )

        returned_val = subprocess.check_output(command, shell=True).decode("utf-8")
        # sacct returns almost triplicate results so instead only select just one.
        returned_val = returned_val.split("\n")[::3]

        add_or_remove_to_dict(returned_val, date_time_list, index+1, add=True)

with open(save_file, "w") as f:
    json.dump(job_dict, f, indent=4)
