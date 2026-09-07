# Paladin-backed document knowledge

This directory defines the provider-neutral ontology boundary for preserving PDF knowledge outside
the chat model. It adapts the proven structure from `emc-doc-validator` without coupling LibreChat
to EMC-specific entity names or rules.

## What is already active

LibreChat's built-in PDF parser emits `pdf-knowledge-v1` text with a source SHA-256, verified PDF
outline, and an explicit marker for every physical page. Text-only models therefore receive stable
page anchors instead of one flattened text blob. The parser deliberately does not invent headings
when the PDF has no trustworthy outline.

## Ontology boundary

`schema/ontology/librechat_knowledge.ontology` keeps four lifecycles separate:

1. `KnowledgeDocument`: ownership, source asset, checksum, and extraction version.
2. `KnowledgeSection`: page range and searchable source text.
3. `KnowledgeRegion`: source table/figure location, crop asset, and deterministic text.
4. `KnowledgeInterpretation`: model/prompt-versioned derived knowledge for a region.

The source PDF and deterministic extraction must remain authoritative. Re-running a vision model
creates or replaces a `KnowledgeInterpretation`; it must not overwrite the source region.

## Paladin version boundary

The installed runtime discovered during development is `D:\bin\paladin\0.8.4`. The
`emc-doc-validator` project metadata still targets the Paladin/ALIRA 0.5 SDK format and is rejected
by the 0.8.4 CLI. Reuse its data model and extraction behavior, but create a new 0.8.x project for
LibreChat rather than pointing 0.8.x at that existing project directory.

Validate the checked-in standalone schema with Paladin 0.8.x:

```powershell
Set-Location .\deploy\paladin-knowledge
alira-wb generate --dry-run
```

After review, use `apply-source schema/paladin.schema` for a direct author-and-apply operation, or
Paladin's checked migration flow (`mkmigrate`, then `migrate`) when the physical change needs
review. Target a dedicated `librechat-knowledge` project. Do not auto-migrate a shared Paladin
project during LibreChat startup.

## Adapter contract for File Search

Paladin should sit behind a server-side adapter, never be called directly by the browser. The
adapter verifies LibreChat's short-lived bearer token, enforces `OwnerId`, then maps the existing
LibreChat RAG contract:

| LibreChat request                 | Paladin operation                                                          |
| --------------------------------- | -------------------------------------------------------------------------- |
| `POST /text`                      | Deterministic extraction only; return `{ text }`                           |
| `POST /embed`                     | Store source asset and upsert document/section/region entities             |
| `POST /query`                     | Vector-search embedding fields, owner-filter results, return page metadata |
| `GET /documents/:file_id/context` | Read all owner-authorized sections in page order                           |
| `DELETE /documents`               | Delete relations/entities/assets for authorized file IDs                   |

The adapter must fail closed when ownership cannot be proven. Vector results from another owner
must be removed before any content is returned, and enough candidates should be requested to avoid
cross-owner rows starving the authorized result set. `OwnerId` is intentionally duplicated onto
every vector-searchable entity so authorization does not depend on returning a parent document
after untrusted search content has already crossed the adapter boundary.

Table/figure extraction and vision interpretation are the next adapter stage. They should use the
model-capability resolver already present in this branch: text-only models keep deterministic table
text, while vision-capable models may create `KnowledgeInterpretation` records.
