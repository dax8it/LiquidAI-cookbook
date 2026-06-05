# Telco Triage Model Pack

This file documents the artifacts needed by the current Telco Triage iOS
runtime. It is deliberately narrower than an internal research archive.

## Current Runtime Contract

Normal Q&A is not a generative model path:

```text
rag-units-v1.json
  -> BM25HierarchyRetriever
  -> route policy
  -> DeterministicAnswerComposer
  -> source chip + optional confirmed action
```

The app still packages an LFM2.5-350M base model for optional model-backed
features and tool support, but grounded support answers are composed from the
selected RAG unit.

## Required GGUF Files

| File | Required | Role |
| --- | --- | --- |
| `lfm25-350m-base-Q4_K_M.gguf` | Yes | Resident LFM2.5-350M base model for optional model-backed execution. |
| `telco-tool-selector-v3.gguf` | Yes | Tool-support adapter used when explicit tool paths need model assistance. |

These files are copied into `TelcoTriage/Resources/Models/` by
`bootstrap-models.sh`. They are not committed to Git.

## Required RAG Resources

| File | Role |
| --- | --- |
| `TelcoTriage/Resources/rag-units-v1.json` | Canonical support corpus used by the retriever and composer. |
| `TelcoTriage/Resources/page-link-table-v1.json` | Canonical link IDs and source-chip destinations. |

## Optional / Development Artifacts

The source tree still contains interfaces for model-backed classifiers, tool
selection experiments, and evaluation surfaces. They are useful for continued
applied-ML work, but they are not part of the customer Q&A critical path.

Do not add extra GGUFs to the customer model pack unless a runtime dependency
or eval gate proves they are needed. Extra adapters increase bundle size and
make the architecture harder to explain.

## Hugging Face Packaging

Use the scripts in `hf/`:

```bash
./hf/prepare-hf-bundle.sh
HF_REPO_ID=LiquidAI/TelcoTriage-POC ./hf/upload-hf-bundle.sh
```

The prepared bundle includes:

- required GGUFs
- `rag-units-v1.json`
- `page-link-table-v1.json`
- `knowledge-base.json`
- `model_manifest.json`
- `checksums.sha256`
- a Hugging Face README/model card

## Token Guidance

Use a Hugging Face **write** token or a fine-grained token scoped to the target
model repo. Do not paste the token into chat. Run `hf auth login` locally, or
set `HF_TOKEN` only in your shell for the upload command.
