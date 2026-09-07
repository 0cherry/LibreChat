import type {
  ModelAttachmentCapabilities,
  ModelCapabilitiesConfig,
  ResolvedModelAttachmentCapabilities,
  ResolvedModelAttachmentMode,
} from './types/files';

export const visionModels = [
  'qwen-vl',
  'grok-vision',
  'grok-2-vision',
  'grok-3',
  'gpt-4o-mini',
  'gpt-4o',
  'gpt-4-turbo',
  'gpt-4-vision',
  'o4-mini',
  'o3',
  'o1',
  'gpt-5',
  'gpt-4.1',
  'gpt-4.5',
  'llava',
  'llava-13b',
  'gemini-pro-vision',
  'claude-3',
  'gemma',
  'gemini-exp',
  'gemini-1.5',
  'gemini-2',
  'gemini-2.5',
  'gemini-3',
  'moondream',
  'llama3.2-vision',
  'llama-3.2-11b-vision',
  'llama-3-2-11b-vision',
  'llama-3.2-90b-vision',
  'llama-3-2-90b-vision',
  'llama-4',
  'claude-opus-4',
  'claude-sonnet-4',
  'claude-haiku-4',
];

export function validateVisionModel({
  model,
  additionalModels = [],
  availableModels,
}: {
  model: string;
  additionalModels?: string[];
  availableModels?: string[];
}) {
  if (!model) {
    return false;
  }

  if (model.includes('gpt-4-turbo-preview') || model.includes('o1-mini')) {
    return false;
  }

  if (availableModels && !availableModels.includes(model)) {
    return false;
  }

  return visionModels.concat(additionalModels).some((visionModel) => model.includes(visionModel));
}

const additionalVisionModelMatchers = [
  /(?:^|[/_.-])(?:vl|vision)(?:$|[/_.-])/i,
  /(?:pixtral|idefics|molmo|minicpm-v)/i,
];

const escapeRegex = (value: string): string => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const matchesModelPattern = (pattern: string, model: string): boolean => {
  if (pattern.toLowerCase() === model.toLowerCase()) {
    return true;
  }
  if (!pattern.includes('*') && !pattern.includes('?')) {
    return false;
  }
  const regex = `^${escapeRegex(pattern).replace(/\\\*/g, '.*').replace(/\\\?/g, '.')}$`;
  return new RegExp(regex, 'i').test(model);
};

const getModelCapabilitiesOverride = (
  config: ModelCapabilitiesConfig,
  model: string,
): ModelAttachmentCapabilities | undefined => {
  const entries = Object.entries(config.models ?? {});
  const exact = entries.find(([pattern]) => pattern.toLowerCase() === model.toLowerCase());
  if (exact) {
    return exact[1];
  }

  let selected: ModelAttachmentCapabilities | undefined;
  let selectedSpecificity = -1;
  for (const [pattern, capabilities] of entries) {
    if (!matchesModelPattern(pattern, model)) {
      continue;
    }
    const specificity = pattern.replace(/[?*]/g, '').length;
    if (specificity > selectedSpecificity) {
      selected = capabilities;
      selectedSpecificity = specificity;
    }
  }
  return selected;
};

const resolveAttachmentMode = (
  configured: ModelAttachmentCapabilities[keyof ModelAttachmentCapabilities],
  detected: ResolvedModelAttachmentMode | undefined,
  fallback: ResolvedModelAttachmentMode,
): ResolvedModelAttachmentMode => {
  if (configured && configured !== 'auto') {
    return configured;
  }
  return detected ?? fallback;
};

/**
 * Resolves attachment behavior for a model when an endpoint opts into capability routing.
 * Explicit model/default configuration wins over provider-discovered metadata, followed by
 * conservative model-name detection. Unknown models never receive binary document parts.
 */
export function resolveModelAttachmentCapabilities(params: {
  config?: ModelCapabilitiesConfig;
  model?: string | null;
  detected?: Partial<ResolvedModelAttachmentCapabilities>;
}): ResolvedModelAttachmentCapabilities | undefined {
  const { config, detected } = params;
  if (!config) {
    return undefined;
  }

  const model = params.model?.trim() ?? '';
  const modelOverride = model ? getModelCapabilitiesOverride(config, model) : undefined;
  const configured = { ...config.default, ...modelOverride };
  const isVisionModel =
    validateVisionModel({ model: model.toLowerCase() }) ||
    additionalVisionModelMatchers.some((matcher) => matcher.test(model));

  return {
    images: resolveAttachmentMode(
      configured.images,
      detected?.images,
      isVisionModel ? 'native' : 'disabled',
    ),
    documents: resolveAttachmentMode(configured.documents, detected?.documents, 'extract_text'),
  };
}
