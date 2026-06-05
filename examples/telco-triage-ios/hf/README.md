---
license: other
language:
  - en
tags:
  - gguf
  - ios
  - on-device
  - rag
  - telco
  - liquid-ai
library_name: llama.cpp
---

# Telco Triage iOS Model Pack

This private model pack supports the **Telco Triage iOS** cookbook example: an
on-device support assistant for home-internet Q&A, safe local actions, and
handoff flows.

The current customer Q&A runtime is **zero-generation composer RAG**:

```text
User turn
  -> conversation state
  -> BM25HierarchyRetriever over rag-units-v1.json
  -> route policy
  -> DeterministicAnswerComposer
  -> cited chat answer + source chip + optional confirmed action
```

Grounded support answers are composed from canonical RAG units. The packaged
LFM2.5-350M base model is included for optional model-backed features and
explicit tool support, not for normal Q&A answer synthesis.

## Contents

| File | Role |
| --- | --- |
| `lfm25-350m-base-Q4_K_M.gguf` | LFM2.5-350M base model for optional model-backed app features and tool support. |
| `telco-tool-selector-v3.gguf` | Tool-support adapter for explicit tool paths that need model assistance. |
| `rag-units-v1.json` | Canonical RAG corpus used by the app's retriever and composer. |
| `page-link-table-v1.json` | Canonical in-app links used for source chips and navigation. |
| `knowledge-base.json` | Small sample KB retained for non-composer demo surfaces. |
| `model_manifest.json` | Machine-readable pack contract. |
| `checksums.sha256` | SHA-256 checksums for all shipped artifacts. |

## Download

```bash
hf auth login
hf download "$HF_REPO_ID" --local-dir models/telco
```

Then from the cookbook example:

```bash
cd examples/telco-triage-ios
TELCO_MODELS_DIR=models/telco ./bootstrap-models.sh
xcodegen generate
open TelcoTriage.xcodeproj
```

## Runtime Boundary

Normal support Q&A:

- model forwards: 0
- generation calls: 0
- Q&A LoRA adapters: 0
- citation source: selected `RAGUnit.canonicalURL`

Tool and optional model-backed app paths can use the packaged LFM artifacts when
explicitly invoked by the app.

## Access

This pack is intended for private POC delivery. Grant access through the
Hugging Face organization or use a gated/private repo. Uploads should use a
write token or a fine-grained token scoped to this repository.
