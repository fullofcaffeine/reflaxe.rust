#!/usr/bin/env node

/**
 * Why:
 *   The newcomer docs path is now part of the product surface. If README/start-here/index/examples
 *   silently drift apart, users end up bouncing through stale or dead links before they ever reach
 *   the right contract/example guidance.
 *
 * What:
 *   Validate the main entrypoint docs by checking two things:
 *   1. required cross-links are present in the files that define the newcomer path
 *   2. required status phrases are present where stale release-history wording would mislead users
 *   3. local markdown links in those files resolve on disk
 *
 * How:
 *   Keep the rules explicit and deterministic. This is not a full markdown linter; it is a narrow
 *   guard for the high-value entrypoint pages that the rest of the docs navigation depends on.
 */

const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..', '..');

const entrypointRules = [
  {
    file: 'README.md',
    requiredLinks: [
      'docs/start-here.md',
      'docs/install-via-lix.md',
      'docs/portable-near-native-guidance.md',
      'docs/examples-matrix.md',
      'docs/production-readiness.md',
      'docs/feature-support-matrix.md',
    ],
  },
  {
    file: 'docs/start-here.md',
    requiredLinks: [
      'install-via-lix.md',
      'workflow.md',
      'profiles.md',
      'portable-near-native-guidance.md',
      'examples-matrix.md',
      'production-readiness.md',
      'feature-support-matrix.md',
      'semantic-confidence-summary.md',
      'semver-release-posture.md',
    ],
  },
  {
    file: 'docs/index.md',
    requiredLinks: [
      'start-here.md',
      'install-via-lix.md',
      'workflow.md',
      'portable-near-native-guidance.md',
      'portable-vs-metal-authoring.md',
      'examples-matrix.md',
      'production-readiness.md',
      'feature-support-matrix.md',
      'semantic-confidence-summary.md',
      'semver-release-posture.md',
      'weekly-ci-evidence.md',
    ],
  },
  {
    file: 'docs/examples-matrix.md',
    requiredLinks: [
      'start-here.md',
      'profiles.md',
      'portable-near-native-guidance.md',
      'metal-profile.md',
      'perf-hxrt-overhead.md',
    ],
  },
  {
    file: 'docs/production-readiness.md',
    requiredLinks: [
      'semver-release-posture.md',
      'portable-near-native-guidance.md',
      'feature-support-matrix.md',
      'semantic-confidence-summary.md',
      'weekly-ci-evidence.md',
    ],
  },
  {
    file: 'docs/install-via-lix.md',
    requiredLinks: [
      'production-readiness.md',
      'feature-support-matrix.md',
    ],
  },
  {
    file: 'docs/ga-decision-record.md',
    requiredLinks: [
      'semver-release-posture.md',
    ],
    requiredPhrases: [
      'historical decision record, not the current release posture',
      '`0.x` posture: intentional until the graduation gate passes',
      'intentional pre-1.0 decision superseded it',
    ],
  },
  {
    file: 'docs/ga-caveat-classification.md',
    requiredLinks: [
      'semver-release-posture.md',
    ],
    requiredPhrases: [
      'Milestone 28 caveat input, not the current public release posture',
      'historical `1.0` direction was superseded by the intentional pre-1.0 posture',
      'explicit defers remain documented caveats and inputs to the measurable graduation gate',
    ],
  },
  {
    file: 'docs/road-to-1.0.md',
    requiredLinks: [
      'semver-release-posture.md',
    ],
    requiredPhrases: [
      'current public semver/package posture now lives',
      'intentional pre-1.0 line and measurable graduation gate',
    ],
  },
];

const markdownLinkRegex = /\[[^\]]+\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g;

function isExternal(target) {
  return (
    target.startsWith('http://') ||
    target.startsWith('https://') ||
    target.startsWith('mailto:') ||
    target.startsWith('#')
  );
}

function normalizeLinkTarget(target) {
  return target.split('#')[0];
}

function collectMarkdownLinks(filePath, content) {
  const links = [];
  for (const match of content.matchAll(markdownLinkRegex)) {
    const raw = match[1];
    if (!raw || isExternal(raw)) {
      continue;
    }
    links.push(raw);
  }
  return links;
}

function resolveLocalTarget(sourceFile, target) {
  const normalized = normalizeLinkTarget(target);
  if (!normalized) {
    return null;
  }
  return path.resolve(path.dirname(sourceFile), normalized);
}

function normalizePhraseText(text) {
  return text.replace(/\s+/g, ' ').trim();
}

const errors = [];

for (const rule of entrypointRules) {
  const absoluteFile = path.resolve(repoRoot, rule.file);
  const content = fs.readFileSync(absoluteFile, 'utf8');
  const normalizedContent = normalizePhraseText(content);
  const localLinks = collectMarkdownLinks(absoluteFile, content);
  const localLinkSet = new Set(localLinks.map(normalizeLinkTarget));

  for (const requiredLink of rule.requiredLinks) {
    if (!localLinkSet.has(requiredLink)) {
      errors.push(`${rule.file}: missing required link '${requiredLink}'`);
    }
  }

  for (const requiredPhrase of rule.requiredPhrases || []) {
    if (!normalizedContent.includes(normalizePhraseText(requiredPhrase))) {
      errors.push(`${rule.file}: missing required phrase '${requiredPhrase}'`);
    }
  }

  for (const target of localLinks) {
    const resolved = resolveLocalTarget(absoluteFile, target);
    if (resolved && !fs.existsSync(resolved)) {
      errors.push(`${rule.file}: dead local link '${target}'`);
    }
  }
}

if (errors.length > 0) {
  console.error('[docs] entrypoint navigation guard failed:');
  for (const error of errors) {
    console.error(`- ${error}`);
  }
  process.exit(1);
}

console.log('[docs] entrypoint navigation guard ok');
