"""Optional enrichment interfaces. The baseline engine does not require a provider."""

# Providers return evidence-bearing page records instead of mutating the native
# text path. Hosts can negotiate availability through provider_capabilities().
abstract type AbstractOCRProvider end
abstract type AbstractEnrichmentProvider end

struct OCRPage
    page_number::Int
    text::String
    confidence::Union{Nothing,Float64}
    source::String
end

# Confidence is nullable because providers may return text without a calibrated
# score; `source` identifies the image/page origin for downstream auditability.
struct OCRResult
    provider::String
    version::String
    pages::Vector{OCRPage}
    warnings::Vector{String}
end

struct UnconfiguredOCRProvider <: AbstractOCRProvider end
const NO_OCR_PROVIDER = UnconfiguredOCRProvider()

provider_name(::UnconfiguredOCRProvider) = "none"
provider_version(::UnconfiguredOCRProvider) = "0"

function ocr(::UnconfiguredOCRProvider, source::AbstractString; pages=nothing, kwargs...)
    throw(ArgumentError("no OCR provider is configured for $(source)"))
end

"""Describe the optional provider capabilities available to an embedding host."""
function provider_capabilities()
    Dict{String,Any}(
        "ocr" => Dict{String,Any}("available" => false, "provider" => provider_name(NO_OCR_PROVIDER),
                                  "version" => provider_version(NO_OCR_PROVIDER)),
        "enrichment" => Dict{String,Any}("available" => false, "providers" => String[]),
    )
end
