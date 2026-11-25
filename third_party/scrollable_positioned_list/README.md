# Scrollable Positioned List

Runtime sources from the [yakagami fork](https://github.com/yakagami/scrollable_positioned_list/tree/4641e83784aa852f131d543f79c63663f55e606f), revision `4641e83784aa852f131d543f79c63663f55e606f`, version `0.3.8+1`.

Tsumiru adds the optional `cacheExtent` argument for the Reader to bound offscreen layout. Leaving it unset preserves the upstream cache behavior. It also adds `ItemScrollController.anchorIndex` so the Reader can keep the strip still when a page above it resizes, without a rebuilding jump. Item positions are also reported again when the scroll metrics change without a scroll, such as an image above finishing loading, so a seek to a visible page does not use stale offsets. See [LICENSE](LICENSE) for the upstream terms and copyright.
