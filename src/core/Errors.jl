abstract type PdfTextSearchException <: Exception end

# These values are part of the integration contract: the CLI returns them and
# embedded callers can use the same taxonomy when translating failures.
"""An ordinary user-facing failure with a stable process exit code."""
struct PdfTextSearchError <: PdfTextSearchException
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

function Base.showerror(io::IO, err::PdfTextSearchError)
    print(io, err.action, " failed")
    isempty(err.target) || print(io, " for ", repr(err.target))
    print(io, ": ", err.message)
    isempty(err.recovery) || print(io, ". ", err.recovery)
end

function probe_error(code::Integer, action, target, message; recovery="")
    throw(PdfTextSearchError(Int(code), String(action), String(target), String(message), String(recovery)))
end
