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

local function trim(value)
    if not value then
        return ""
    end
    return value:match("^%s*(.-)%s*$")
end
-- To avoid false positivies, the function looks through the script and strips the script of shebangs, comments etc 
-- until we find just the command
local function script_invokes_srun(script)
    if not script or script == "" then
        return false
    end

    local normalized = script:gsub("\r\n", "\n")
    for line in normalized:gmatch("[^\n]+") do
        local trimmed_line = trim(line)
        if trimmed_line ~= "" then
            -- Skip shebangs, SBATCH directives, and normal comments.
            if trimmed_line:sub(1, 1) == "#" then
                goto continue
            end

            -- Remove simple trailing comments.
            local code = trimmed_line:gsub("%s+#.*$", "")
            if code ~= "" then
                -- Split on basic shell separators to inspect each command chunk.
                for chunk in code:gmatch("[^;&|]+") do
                    local text = trim(chunk)
                    if text ~= "" then
                        -- Drop simple negations.
                        text = text:gsub("^!+%s*", "")

                        -- Drop leading KEY=VALUE assignments.
                        while true do
                            local key, rest = text:match("^([_%w][_%w%d]*)%s*=%s*(.+)$")
                            if not key then
                                break
                            end
                            text = trim(rest)
                            if text == "" then
                                break
                            end
                        end

                        local cmd = text:match("^(%S+)")
                        if cmd then
                            local basename = cmd:match("([^/]+)$") or cmd
                            if basename == "srun" then
                                return true
                            end
                        end
                    end
                end
            end
        end
        ::continue::
    end

    return false
end

-- Parse GPU count from gres strings such as:
--   * gpu:4
--   * gpu:a100:1g.10gb:2
--   * gpu:a100:2(IDX:0-1)
--   * gpu=2
local function parse_gpus_from_gres(gres)
    if not gres or gres == "" then
        return 0
    end

    local total = 0

    for token in gres:gmatch("[^,]+") do
        local entry = trim(token)
        if entry ~= "" then
            local lower = entry:lower()
            if lower:find("^gpu") then
                local sanitized = entry:gsub("%b()", "")
                local count = sanitized:match(":(%d+)%s*$") or sanitized:match("=(%d+)%s*$")

                if count then
                    total = total + (tonumber(count) or 0)
                else
                    -- Assume a single GPU if none specified explicitly.
                    total = total + 1
                end
            end
        end
    end

    return total
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
    if job_desc.batch_flag ~= nil then
        is_batch = job_desc.batch_flag ~= 0
    end

    local partition  = job_desc.partition or "nil"
    local gres       = job_desc.gres or ""
    local timelimit  = job_desc.time_limit or 0
    local gpu_count  = parse_gpus_from_gres(gres)
    local script_has_srun = script_invokes_srun(job_desc.script)

    slurm.log_info(
        "job_submit.lua: uid=%d is_batch=%s part=%s gres=%s " ..
        "gpus=%d timelimit=%d script_has_srun=%s",
        submit_uid,
        tostring(is_batch),
        partition,
        gres,
        gpu_count,
        timelimit,
        tostring(script_has_srun)
    )

    -- checks for both conditions
    local enforce_interactive = (not is_batch) or script_has_srun

    -- ------------------------------------------------------------
    -- INTERACTIVE JOB POLICY (srun -> no script)
    -- ------------------------------------------------------------
    if enforce_interactive then
        local max_minutes     = 120    -- 2 hours
        local max_total_gpus  = 4      -- total GPUs per job
        local max_nodes       = 1      -- single node

        if script_has_srun then
            slurm.log_info(
                "job_submit.lua: SBATCH script uses srun; enforcing interactive limits (uid=%d)",
                submit_uid
            )
            slurm.log_user(
                "Detected srun usage inside an sbatch script. Interactive job limits apply: " ..
                "max %d minutes, %d node(s), %d GPU(s).",
                max_minutes,
                max_nodes,
                max_total_gpus
            )
        end

        -- --------------------------------------------------------
        -- 1) Cap runtime
        -- --------------------------------------------------------
        cap_timelimit(job_desc, max_minutes)

        -- --------------------------------------------------------
        -- 2) Cap nodes (force single node)
        -- --------------------------------------------------------
        local req_min_nodes = safe_int(job_desc.min_nodes or job_desc.num_nodes or 1, 1)
        local req_max_nodes = safe_int(job_desc.max_nodes or req_min_nodes, 1)

        if req_min_nodes > max_nodes or req_max_nodes > max_nodes then
            local requested = math.max(req_min_nodes, req_max_nodes)
            slurm.log_user(
                "Interactive jobs are limited to %d node(s) (requested up to %d). " ..
                "Please submit a batch job via sbatch for multi-node workloads.",
                max_nodes, requested
            )
            return slurm.ERROR
        end

        job_desc.min_nodes = max_nodes
        job_desc.max_nodes = max_nodes

        -- --------------------------------------------------------
        -- 3) Cap total GPUs (via gres)
        -- --------------------------------------------------------
        if gpu_count > max_total_gpus then
            slurm.log_user(
                "Interactive jobs are limited to %d total GPU(s) (requested %d). " ..
                "Please submit a batch job via sbatch for larger GPU requests.",
                max_total_gpus, gpu_count
            )
            return slurm.ERROR
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
