'use strict';

/**
 * Placeholder for the Node/Express/React stack.
 * Key-prefix resolution (ActionReference:, EntityReference:, etc.) is an OutSystems concept.
 * This stack uses direct name-based linking in linker.js instead.
 * merger.js only invokes this when blueprintDir is set in config.json — we don't set it.
 */
class KeyResolver {
  constructor(_sourceDir) {}

  build() {
    return {
      actionRefMap: new Map(),
      resolveActionRef: () => null,
      resolveEntityKey: () => null,
      resolveScreen: () => null,
      resolveWebBlock: () => null,
      resolvePlaceholder: () => null,
      inferSlotNameByPosition: () => null,
    };
  }
}

module.exports = { KeyResolver };
