-- job_submit.lua for Slurm 24.05.1 + Lua 5.4.6
-- Interactive (srun) jobs:
--   - Max total GPUs per job: 2
--   - Max time: 120 minutes
--   - Single-node only
--   - Priority BOOST to favor fast allocation
--   - Whenever a limit is exceeded, user gets a clear message
--
-- Batch (sbatch) jobs: untouched.
-- --------------------------------------------------------------------
-- Helpers
-- --------------------------------------------------------------------
local function safe_int(v, default)
    if v == nil or v < 0 or v > 1024 then
        return default
    end
    return v
end

-- Parse GPU count from gres string of the form "gpu:N" or "gpu:TYPE:N"
local function parse_gpus_from_gres(gres)
    if not gres or gres == "" then
        return 0
    end

    -- Try "gpu:N"
    local n = gres:match("gpu:(%d+)")
    if n then
        return tonumber(n) or 0
    end

    -- Try "gpu:TYPE:N"
    n = gres:match("gpu:[^:]+:(%d+)")
    if n then
        return tonumber(n) or 0
    end

    return 0
end

local function cap_timelimit(job_desc, max_minutes)
    local orig = job_desc.time_limit or 0

    if orig == 0 then
        job_desc.time_limit = max_minutes
        return
    end

    if orig > max_minutes then
        job_desc.time_limit = max_minutes
        slurm.log_user(
            "Interactive jobs are limited to %d minutes (requested %d). " ..
            "Capping to %d minutes.",
            max_minutes, orig, max_minutes
        )
    end
end

-- --------------------------------------------------------------------
-- Main submit hook
-- --------------------------------------------------------------------

function slurm_job_submit(job_desc, part_list, submit_uid)
    local is_batch = (job_desc.script ~= nil)

    local partition  = job_desc.partition or "nil"
    local gres       = job_desc.gres or ""
    local timelimit  = job_desc.time_limit or 0
    local gpu_count  = parse_gpus_from_gres(gres)

    slurm.log_info(
        "job_submit.lua: uid=%d is_batch=%s part=%s gres=%s " ..
        "gpus=%d timelimit=%d",
        submit_uid,
        tostring(is_batch),
        partition,
        gres,
        gpu_count,
        timelimit
    )

    -- ------------------------------------------------------------
    -- INTERACTIVE JOB POLICY (srun -> no script)
    -- ------------------------------------------------------------
    if not is_batch then
        local max_minutes     = 120    -- 2 hours
        local max_total_gpus  = 2      -- total GPUs per job
        local max_nodes       = 1      -- single node

        -- --------------------------------------------------------
        -- 1) Cap runtime
        -- --------------------------------------------------------
        cap_timelimit(job_desc, max_minutes)

        -- --------------------------------------------------------
        -- 2) Cap nodes (force single node)
        -- --------------------------------------------------------
        local req_min_nodes = safe_int(job_desc.min_nodes or job_desc.num_nodes or 1, 1)
        local req_max_nodes = safe_int(job_desc.max_nodes or req_min_nodes, 1)

        if req_max_nodes > max_nodes then
            slurm.log_user(
                "Interactive jobs are limited to %d node(s) (requested up to %d). " ..
                "Capping to %d node.",
                max_nodes, req_max_nodes, max_nodes
            )
        end

        job_desc.min_nodes = max_nodes
        job_desc.max_nodes = max_nodes

        -- --------------------------------------------------------
        -- 3) Cap total GPUs (via gres)
        -- --------------------------------------------------------
        if gpu_count > max_total_gpus then
            slurm.log_user(
                "Interactive jobs are limited to %d total GPU(s) (requested %d). " ..
                "Capping to %d.",
                max_total_gpus, gpu_count, max_total_gpus
            )

            -- Replace gres string with capped GPU count
            local capped_gres = gres:gsub("gpu:([^:]+):%d+", "gpu:%1:" .. max_total_gpus)
            capped_gres = capped_gres:gsub("gpu:%d+", "gpu:" .. max_total_gpus)
            job_desc.gres = capped_gres
            gpu_count = max_total_gpus
        end

        -- --------------------------------------------------------
        -- 4) BOOST priority
        -- --------------------------------------------------------
        local priority_boost = 5000
        local base_prio = job_desc.priority

        if base_prio == nil or base_prio <= 0 or base_prio > 100000000 then
            base_prio = 1000
        end

        job_desc.priority = base_prio + priority_boost

        slurm.log_info(
            "job_submit.lua: INTERACTIVE policy applied uid=%d gpus=%d " ..
            "time=%d priority=%d (base=%d + boost=%d)",
            submit_uid,
            gpu_count,
            job_desc.time_limit or -1,
            job_desc.priority or -1,
            base_prio,
            priority_boost
        )

    -- ------------------------------------------------------------
    -- BATCH JOBS
    -- ------------------------------------------------------------
    else
        slurm.log_info(
            "job_submit.lua: BATCH job (uid=%d) normal priority",
            submit_uid
        )
    end

    return slurm.SUCCESS
end

function slurm_job_modify(job_desc, job_rec, part_list, modify_uid)
    return slurm.SUCCESS
end
