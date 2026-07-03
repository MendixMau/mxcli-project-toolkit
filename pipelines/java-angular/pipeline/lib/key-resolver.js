'use strict';

/**
 * Placeholder for this stack. The OS pipeline's key-resolver.js resolves OutSystems XML key
 * prefixes (ActionReference:, EntityReference:, WebBlock:, Placeholder:) — none of which exist
 * here. merger.js only invokes this when a blueprintDir-equivalent config value is set, which
 * this pipeline's config.json intentionally does not set yet, so build() is never called in
 * practice today.
 *
 * TODO before relying on merger.js's enrichment pass for this stack: implement resolution for
 * - @Autowired service/repository wiring (Controller -> ServiceImpl -> Repository)
 * - MatDialog.open(ComponentClass) call sites -> target Angular component
 * - JPA @ManyToOne/@OneToMany/@JoinColumn -> association target entity
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
