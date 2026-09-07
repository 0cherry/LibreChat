import type { PdfKnowledgeDocument } from './pdf';
import { PDF_KNOWLEDGE_EXTRACTION_VERSION, serializePdfKnowledge } from './pdf';

describe('PDF knowledge serialization', () => {
  test('preserves source identity, outline hierarchy, and page anchors', () => {
    const document: PdfKnowledgeDocument = {
      version: PDF_KNOWLEDGE_EXTRACTION_VERSION,
      sourceSha256: 'abc123',
      pageCount: 2,
      outline: [
        { path: '1', level: 1, title: 'Scope', pageNumber: 1 },
        { path: '1.1', level: 2, title: 'Terms', pageNumber: 2 },
      ],
      pages: [
        { pageNumber: 1, text: 'First page' },
        { pageNumber: 2, text: 'Second page' },
      ],
    };

    expect(serializePdfKnowledge(document)).toBe(
      '[PDF_KNOWLEDGE version=pdf-knowledge-v1 pages=2 sha256=abc123]\n\n' +
        '[PDF_OUTLINE]\n' +
        '- 1 | page 1 | Scope\n' +
        '  - 1.1 | page 2 | Terms\n\n' +
        '[PDF_PAGE number=1]\n' +
        'First page\n\n' +
        '[PDF_PAGE number=2]\n' +
        'Second page\n',
    );
  });

  test('keeps page anchors when the PDF has no outline or visible text on a page', () => {
    const document: PdfKnowledgeDocument = {
      version: PDF_KNOWLEDGE_EXTRACTION_VERSION,
      sourceSha256: 'empty-page',
      pageCount: 1,
      outline: [],
      pages: [{ pageNumber: 1, text: '' }],
    };

    expect(serializePdfKnowledge(document)).toContain('[PDF_PAGE number=1]\n');
    expect(serializePdfKnowledge(document)).not.toContain('[PDF_OUTLINE]');
  });
});
