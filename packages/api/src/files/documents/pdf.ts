import { createHash } from 'crypto';
import type { PDFDocumentProxy, TextItem } from 'pdfjs-dist/types/src/display/api';

export const PDF_KNOWLEDGE_EXTRACTION_VERSION = 'pdf-knowledge-v1';

export interface PdfKnowledgePage {
  readonly pageNumber: number;
  readonly text: string;
}

export interface PdfKnowledgeOutlineEntry {
  readonly path: string;
  readonly level: number;
  readonly title: string;
  readonly pageNumber: number | null;
}

export interface PdfKnowledgeDocument {
  readonly version: typeof PDF_KNOWLEDGE_EXTRACTION_VERSION;
  readonly sourceSha256: string;
  readonly pageCount: number;
  readonly pages: readonly PdfKnowledgePage[];
  readonly outline: readonly PdfKnowledgeOutlineEntry[];
}

type PdfOutlineNode = NonNullable<Awaited<ReturnType<PDFDocumentProxy['getOutline']>>>[number];

/** Extracts source-preserving PDF knowledge without guessing headings that the PDF does not prove. */
export async function extractPdfKnowledge(data: Uint8Array): Promise<PdfKnowledgeDocument> {
  const sourceSha256 = createHash('sha256').update(data).digest('hex');
  const { getDocument } = await import('pdfjs-dist/legacy/build/pdf.mjs');
  const loadingTask = getDocument({ data });
  const pdf = await loadingTask.promise;

  try {
    const pages = await extractPages(pdf);
    const outline = await extractOutline(pdf);
    return {
      version: PDF_KNOWLEDGE_EXTRACTION_VERSION,
      sourceSha256,
      pageCount: pdf.numPages,
      pages,
      outline,
    };
  } finally {
    await loadingTask.destroy();
  }
}

/** Serializes extracted knowledge with stable page anchors that remain visible to text-only models. */
export function serializePdfKnowledge(document: PdfKnowledgeDocument): string {
  const header = `[PDF_KNOWLEDGE version=${document.version} pages=${document.pageCount} sha256=${document.sourceSha256}]`;
  const outline = serializeOutline(document.outline);
  const pages = document.pages
    .map((page) => `[PDF_PAGE number=${page.pageNumber}]\n${page.text}`)
    .join('\n\n');
  const serialized = [header, outline, pages].filter(Boolean).join('\n\n');
  return `${serialized.replace(/\s+$/, '')}\n`;
}

async function extractPages(pdf: PDFDocumentProxy): Promise<PdfKnowledgePage[]> {
  const pages: PdfKnowledgePage[] = [];
  for (let pageNumber = 1; pageNumber <= pdf.numPages; pageNumber += 1) {
    const page = await pdf.getPage(pageNumber);
    try {
      const content = await page.getTextContent();
      const items = content.items.filter((item): item is TextItem => !('type' in item));
      pages.push({ pageNumber, text: textItemsToLines(items) });
    } finally {
      page.cleanup();
    }
  }
  return pages;
}

function textItemsToLines(items: readonly TextItem[]): string {
  const lines: string[] = [];
  let currentLine = '';

  for (const item of items) {
    const text = item.str.replace(/\s+/g, ' ').trim();
    if (text) {
      currentLine = currentLine ? `${currentLine} ${text}` : text;
    }
    if (item.hasEOL && currentLine) {
      lines.push(currentLine);
      currentLine = '';
    }
  }

  if (currentLine) {
    lines.push(currentLine);
  }
  return lines.join('\n');
}

async function extractOutline(pdf: PDFDocumentProxy): Promise<PdfKnowledgeOutlineEntry[]> {
  const root = await pdf.getOutline();
  if (!root?.length) {
    return [];
  }

  const entries: PdfKnowledgeOutlineEntry[] = [];
  await appendOutlineEntries(pdf, root, entries, []);
  return entries;
}

async function appendOutlineEntries(
  pdf: PDFDocumentProxy,
  nodes: readonly PdfOutlineNode[],
  entries: PdfKnowledgeOutlineEntry[],
  parentPath: readonly number[],
): Promise<void> {
  for (let index = 0; index < nodes.length; index += 1) {
    const node = nodes[index];
    const pathParts = [...parentPath, index + 1];
    const title = node.title.replace(/\s+/g, ' ').trim();
    if (title) {
      entries.push({
        path: pathParts.join('.'),
        level: pathParts.length,
        title,
        pageNumber: await resolveOutlinePage(pdf, node),
      });
    }
    if (node.items?.length) {
      await appendOutlineEntries(pdf, node.items, entries, pathParts);
    }
  }
}

async function resolveOutlinePage(
  pdf: PDFDocumentProxy,
  node: PdfOutlineNode,
): Promise<number | null> {
  const destination =
    typeof node.dest === 'string' ? await pdf.getDestination(node.dest) : node.dest;
  if (!Array.isArray(destination) || destination.length === 0) {
    return null;
  }
  try {
    return (await pdf.getPageIndex(destination[0])) + 1;
  } catch {
    return null;
  }
}

function serializeOutline(entries: readonly PdfKnowledgeOutlineEntry[]): string {
  if (!entries.length) {
    return '';
  }
  const lines = entries.map((entry) => {
    const page = entry.pageNumber == null ? '?' : entry.pageNumber;
    return `${'  '.repeat(entry.level - 1)}- ${entry.path} | page ${page} | ${entry.title}`;
  });
  return ['[PDF_OUTLINE]', ...lines].join('\n');
}
