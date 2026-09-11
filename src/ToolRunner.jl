"""Result of one external-tool invocation and its lifecycle state."""
struct ToolResult
    executable::String
    args::Vector{String}
    stdout::String
    stderr::String
    exit_code::Int
    timed_out::Bool
    cancelled::Bool
    duration_ms::Float64
end

Base.success(result::ToolResult) = result.exit_code == 0 && !result.timed_out && !result.cancelled

"""Configuration shared by parser and index external-tool boundaries."""
struct ToolRunner
    timeout::Float64
    poll_interval::Float64
    environment::Union{Nothing,Dict{String,String}}
end

function ToolRunner(; timeout=60.0, poll_interval=0.01, environment=nothing)
    timeout > 0 || throw(ArgumentError("tool timeout must be positive"))
    poll_interval > 0 || throw(ArgumentError("tool poll interval must be positive"))
    env = environment === nothing ? nothing : Dict{String,String}(String(key) => String(value) for (key, value) in pairs(environment))
    ToolRunner(Float64(timeout), Float64(poll_interval), env)
end

tool_path(executable::AbstractString) = Sys.which(String(executable))
tool_available(executable::AbstractString) = tool_path(executable) !== nothing

function _cancel_requested(cancel)
    cancel === nothing && return false
    cancel isa Function && return Bool(cancel())
    cancel isa Base.RefValue && return Bool(cancel[])
    Bool(cancel)
end

function _terminate_process(process)
    process_exited(process) && return
    try
        Base.kill(process, Base.SIGTERM)
    catch
        try Base.kill(process) catch end
    end
end

"""
    run_tool(runner, executable, args; stdin="", cancel=nothing)

Run an external command without invoking a shell. stdout and stderr are captured
separately, and the child is terminated when the wall-clock timeout expires or
`cancel` becomes true. `cancel` may be a `Ref{Bool}`, a zero-argument function,
or a boolean-like value. Output quotas are a separate future safety boundary.
"""
function run_tool(runner::ToolRunner, executable::AbstractString, args::AbstractVector{<:AbstractString}; stdin="", cancel=nothing)
    executable = String(executable)
    args = String.(args)
    command = Cmd([executable; args])
    runner.environment === nothing || (command = setenv(command, runner.environment))
    output_pipe = Pipe()
    error_pipe = Pipe()
    input_pipe = Pipe()
    started = time()
    process = try
        run(pipeline(command; stdin=input_pipe, stdout=output_pipe, stderr=error_pipe); wait=false)
    catch err
        return ToolResult(executable, args, "", sprint(showerror, err), -1, false, false,
                          (time() - started) * 1000)
    end

    close(output_pipe.in)
    close(error_pipe.in)
    stdout_task = @async try read(output_pipe, String) catch; "" end
    stderr_task = @async try read(error_pipe, String) catch; "" end
    stdin_task = @async begin
        try
            isempty(stdin) || write(input_pipe.in, String(stdin))
        catch
        finally
            try close(input_pipe.in) catch end
        end
    end

    timed_out = false
    cancelled = false
    while process_running(process)
        if _cancel_requested(cancel)
            cancelled = true
            _terminate_process(process)
            break
        elseif time() - started >= runner.timeout
            timed_out = true
            _terminate_process(process)
            break
        end
        sleep(runner.poll_interval)
    end
    try wait(process) catch end
    try wait(stdin_task) catch end
    stdout = try fetch(stdout_task) catch; "" end
    stderr = try fetch(stderr_task) catch; "" end
    exit_code = try Int(process.exitcode) catch; success(process) ? 0 : -1 end
    ToolResult(executable, args, stdout, stderr, exit_code, timed_out, cancelled,
               (time() - started) * 1000)
end
