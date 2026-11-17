# Source and asset attribution

Kuchie starts from the modified iOS client based on [Suwayomi-Tsumiru](https://github.com/Suwayomi/Suwayomi-Tsumiru) at upstream revision `c01ad2562fbc124d4f63a49664c6e3018c14616c`. The Mozilla Public License 2.0 and the original copyright notices apply to the covered files. Translation notices are bundled in `assets/licenses/`. The vendored reader list has its own license in `third_party/scrollable_positioned_list/`.

Kiri, the Kuchie mark and the app icon variants come from the Kuchie design chat assets. The name, repository, bundle and release configuration are managed by Kuchie.

The server API still recognizes existing metadata such as `tsumiru_server_instance_id`, `tsumiru.hidden`, `tsumiru_isHidden`, `tsumiru_global_search_scope`, `tsumiru_customCover` and `TSUMIRU` for the historical server WebUI flavor. These wire values are kept so existing server libraries and settings continue to work.

`lib/src/features/local_collection/data/remote_webview/` and its tests are adapted from [Mangayomi](https://github.com/kodjodevf/mangayomi) (revision `bc0b410`), licensed under the Apache License 2.0 (`assets/licenses/Apache-2.0.txt`); each file names its origin and Kuchie's changes. The embedded extension runtime is built from [1Selxo/M-Extension-Server](https://github.com/1Selxo/M-Extension-Server) (MPL 2.0) with the patches in `ios/MihonRuntime/patches/`.
