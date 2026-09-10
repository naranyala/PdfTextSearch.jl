abstract type PDFProbeException <: Exception end

"""An ordinary user-facing failure with a stable process exit code."""
struct PDFProbeError <: PDFProbeException
    code::Int
    action::String
    target::String
    message::String
    recovery::String
end

const EXIT_SUCCESS = 0
const EXIT_USAGE = 2
const EXIT_INPUT = 3
const EXIT_PARSE = 4
const EXIT_INDEX = 5
const EXIT_INTERNAL = 10

function Base.showerror(io::IO, err::PDFProbeError)
    print(io, err.action, " failed")
    isempty(err.target) || print(io, " for ", repr(err.target))
    print(io, ": ", err.message)
    isempty(err.recovery) || print(io, ". ", err.recovery)
end

function probe_error(code::Integer, action, target, message; recovery="")
    throw(PDFProbeError(Int(code), String(action), String(target), String(message), String(recovery)))
end
