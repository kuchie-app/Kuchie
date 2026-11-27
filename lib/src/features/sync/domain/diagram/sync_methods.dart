// What each sync method's diagram shows (design 3.9): its nodes, the lines
// between them, the data that moves while it syncs, and what it syncs.
// Plain data; sync_scene.dart turns a method and a status into a scene.

/// Text in English and Indonesian; the widget picks one with `localText`.
typedef SyncCopy = ({String en, String id});

enum SyncMethodKind {
  local,
  suwayomi,
  icloud,
  syncyomi,
  kosync,
  komga,
  kavita,
  drive,
}

enum NodeKind { phone, tablet, mac, android, ereader, hub, ghost, source }

/// The icon inside the centre node.
enum HubGlyph { server, cloud, syncyomi, kosync, media, drive }

/// What a moving token is: one shape always means one kind of data.
enum TokenKind {
  /// Library changes.
  cover,

  /// Reading progress, drawn with a tail.
  dot,

  /// Covers and dots taking turns.
  mix,

  /// Chapter pages.
  page,

  /// A whole-library bundle (SyncYomi).
  bundle,

  /// A position inside a chapter (KOReader Sync).
  mark,

  /// A periodic sync file (Google Drive).
  file,
}

/// How a line is drawn.
enum LinkRole {
  /// iPhone to the centre.
  sync,

  /// The centre to other devices.
  fan,

  /// Source to iPhone.
  source,

  /// Source to the server, for server downloads.
  source2,

  /// Source to another device, thin and dashed.
  sourceOther,

  /// iPhone to the "not connected" circle.
  ghost,
}

/// The pill icon at the top left of the card.
enum MethodPillIcon { phone, server, cloud }

/// Half the width and height of each node, in logical pixels; lines start
/// at their edge.
const nodeHalfSize = {
  NodeKind.phone: (24.0, 43.0),
  NodeKind.tablet: (33.0, 23.0),
  NodeKind.mac: (33.0, 27.0),
  NodeKind.android: (22.0, 41.0),
  NodeKind.ereader: (27.0, 38.0),
  NodeKind.hub: (28.0, 28.0),
  NodeKind.ghost: (26.0, 26.0),
  NodeKind.source: (13.0, 13.0),
};

/// Height of the diagram, in logical pixels.
const diagramHeight = 262.0;

class DiagramNode {
  const DiagramNode({
    required this.id,
    required this.kind,
    required this.x,
    required this.y,
    required this.label,
    this.sub,
  });

  /// `phone`, `hub` and `source` are fixed; other devices are `r`, `r1`, `r2`.
  final String id;
  final NodeKind kind;

  /// Fraction of the diagram's width.
  final double x;

  /// Logical pixels from the top.
  final double y;
  final SyncCopy label;
  final SyncCopy? sub;

  bool get isRound =>
      kind == NodeKind.hub || kind == NodeKind.ghost || kind == NodeKind.source;

  DiagramNode copyWith({
    double? x,
    double? y,
    SyncCopy? label,
    SyncCopy? sub,
  }) => DiagramNode(
    id: id,
    kind: kind,
    x: x ?? this.x,
    y: y ?? this.y,
    label: label ?? this.label,
    sub: sub ?? this.sub,
  );
}

class DiagramLink {
  const DiagramLink(this.a, this.b, this.role);

  final String a, b;
  final LinkRole role;
}

/// Data moving from [from] to [to]. Continuous flows keep [count] tokens on
/// the line; periodic ones send one token every [every] seconds.
class DiagramFlow {
  const DiagramFlow(
    this.from,
    this.to,
    this.token, {
    this.count = 1,
    this.speed = 0,
    this.lane = 0,
  }) : every = null,
       travel = null,
       delay = 0;

  const DiagramFlow.periodic(
    this.from,
    this.to,
    this.token, {
    required double this.every,
    required double this.travel,
    this.delay = 0,
  }) : count = 1,
       speed = 0,
       lane = 0;

  final String from, to;
  final TokenKind token;
  final int count;

  /// Trips per second.
  final double speed;

  /// Sideways offset from the line, in logical pixels, so two directions can
  /// share one line.
  final double lane;

  /// Seconds between tokens, for periodic flows.
  final double? every;

  /// Seconds a periodic token takes to cross.
  final double? travel;

  /// Seconds before the first periodic token.
  final double delay;

  bool get isPeriodic => every != null;
  String get route => '$from>$to';
}

/// One chip in "What syncs".
class LegendItem {
  const LegendItem(this.label, {required this.synced, this.note});

  final SyncCopy label;
  final bool synced;
  final SyncCopy? note;
}

/// Statuses a diagram can show. Local has only [local].
enum SyncStatusKind {
  local,
  analyzing,
  syncing,
  synced,
  waiting,
  action,
  serverDownload,
  moveToServer,
  saveOffline,
}

/// Status line and explanation for one status of one method.
typedef StatusCopy = ({SyncCopy status, SyncCopy explain});

class SyncMethodSpec {
  const SyncMethodSpec({
    required this.kind,
    required this.name,
    required this.description,
    required this.pill,
    required this.nodes,
    required this.links,
    required this.legend,
    required this.statuses,
    required this.defaultStatus,
    this.glyph,
    this.syncFlows = const [],
    this.copy = const {},
    this.available = false,
  });

  final SyncMethodKind kind;
  final SyncCopy name;

  /// One line in the method list.
  final SyncCopy description;
  final MethodPillIcon pill;
  final HubGlyph? glyph;
  final List<DiagramNode> nodes;
  final List<DiagramLink> links;

  /// What moves while it syncs.
  final List<DiagramFlow> syncFlows;
  final List<LegendItem> legend;
  final List<SyncStatusKind> statuses;
  final SyncStatusKind defaultStatus;

  /// Method-specific copy for syncing, synced and waiting.
  final Map<SyncStatusKind, StatusCopy> copy;

  /// Whether it can be chosen in this version; the rest say "Coming soon".
  final bool available;

  bool get hasSource => links.any((link) => link.a == 'source');
  bool get hasSourceToPhone =>
      links.any((link) => link.a == 'source' && link.b == 'phone');

  DiagramNode? node(String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }
}

const _sourceNode = DiagramNode(
  id: 'source',
  kind: NodeKind.source,
  x: .34,
  y: 40,
  label: (en: 'Source', id: 'Source'),
);
const _phoneNode = DiagramNode(
  id: 'phone',
  kind: NodeKind.phone,
  x: .14,
  y: 150,
  label: (en: 'iPhone', id: 'iPhone'),
  sub: (en: '42 series', id: '42 series'),
);

DiagramNode _hub(String label, SyncCopy sub) => DiagramNode(
  id: 'hub',
  kind: NodeKind.hub,
  x: .5,
  y: 150,
  label: (en: label, id: label),
  sub: sub,
);

DiagramNode _r1(NodeKind kind, SyncCopy label, SyncCopy sub, {double y = 82}) =>
    DiagramNode(id: 'r1', kind: kind, x: .85, y: y, label: label, sub: sub);

DiagramNode _r2(NodeKind kind, SyncCopy label, SyncCopy sub) =>
    DiagramNode(id: 'r2', kind: kind, x: .85, y: 194, label: label, sub: sub);

const _iPad = (en: 'iPad', id: 'iPad');
const _mac = (en: 'Mac', id: 'Mac');
const _kuchie = (en: 'Kuchie', id: 'Kuchie');

const _fanLinks = [
  DiagramLink('phone', 'hub', LinkRole.sync),
  DiagramLink('hub', 'r1', LinkRole.fan),
  DiagramLink('hub', 'r2', LinkRole.fan),
];

const _library = (en: 'Library', id: 'Library');
const _progress = (en: 'Progress', id: 'Progres');
const _downloads = (en: 'Downloads', id: 'Unduhan');

final localMethod = SyncMethodSpec(
  kind: SyncMethodKind.local,
  name: (en: 'Local', id: 'Lokal'),
  description: (
    en: 'Everything stays on this iPhone',
    id: 'Semua tersimpan di iPhone ini',
  ),
  pill: MethodPillIcon.phone,
  nodes: [
    _sourceNode.copyWith(x: .5),
    _phoneNode.copyWith(x: .3),
    const DiagramNode(
      id: 'hub',
      kind: NodeKind.ghost,
      x: .74,
      y: 150,
      label: (en: 'Sync', id: 'Sync'),
      sub: (en: 'Not connected', id: 'Belum terhubung'),
    ),
  ],
  links: const [
    DiagramLink('source', 'phone', LinkRole.source),
    DiagramLink('phone', 'hub', LinkRole.ghost),
  ],
  legend: const [
    LegendItem(
      _library,
      synced: true,
      note: (en: 'on iPhone', id: 'di iPhone'),
    ),
    LegendItem(
      _progress,
      synced: true,
      note: (en: 'on iPhone', id: 'di iPhone'),
    ),
    LegendItem(
      _downloads,
      synced: true,
      note: (en: 'on iPhone', id: 'di iPhone'),
    ),
    LegendItem((en: 'Across devices', id: 'Antar perangkat'), synced: false),
  ],
  statuses: const [SyncStatusKind.local],
  defaultStatus: SyncStatusKind.local,
  available: true,
);

final suwayomiMethod = SyncMethodSpec(
  kind: SyncMethodKind.suwayomi,
  name: (en: 'Suwayomi server', id: 'Server Suwayomi'),
  description: (en: 'Your own Suwayomi server', id: 'Server Suwayomi milikmu'),
  pill: MethodPillIcon.server,
  glyph: HubGlyph.server,
  nodes: [
    _sourceNode,
    _phoneNode,
    _hub('Server', (en: '130 series', id: '130 series')),
    _r1(NodeKind.tablet, _iPad, _kuchie),
    _r2(NodeKind.mac, _mac, (en: 'Suwayomi WebUI', id: 'WebUI Suwayomi')),
  ],
  links: const [
    ..._fanLinks,
    DiagramLink('source', 'phone', LinkRole.source),
    DiagramLink('source', 'hub', LinkRole.source2),
  ],
  syncFlows: const [
    DiagramFlow('phone', 'hub', TokenKind.mix, count: 3, speed: .55, lane: -5),
    DiagramFlow('hub', 'phone', TokenKind.dot, count: 2, speed: .4, lane: 5),
    DiagramFlow('hub', 'r1', TokenKind.mix, count: 2, speed: .5),
    DiagramFlow('hub', 'r2', TokenKind.mix, count: 2, speed: .45),
  ],
  legend: const [
    LegendItem(_library, synced: true),
    LegendItem(_progress, synced: true),
    LegendItem(
      _downloads,
      synced: true,
      note: (en: 'on the server', id: 'di server'),
    ),
    LegendItem((en: 'Other devices', id: 'Perangkat lain'), synced: true),
  ],
  statuses: const [
    SyncStatusKind.analyzing,
    SyncStatusKind.syncing,
    SyncStatusKind.synced,
    SyncStatusKind.waiting,
    SyncStatusKind.action,
    SyncStatusKind.serverDownload,
    SyncStatusKind.moveToServer,
    SyncStatusKind.saveOffline,
  ],
  defaultStatus: SyncStatusKind.synced,
  available: true,
  copy: const {
    SyncStatusKind.syncing: (
      status: (en: 'Syncing', id: 'Menyinkronkan'),
      explain: (
        en: 'Sending your library and progress to the server. Other devices on the same server get the changes too.',
        id: 'Mengirim library dan progres ke server. Perangkat lain yang memakai server yang sama ikut menerima perubahannya.',
      ),
    ),
    SyncStatusKind.synced: (
      status: (en: 'Synced', id: 'Tersinkron'),
      explain: (
        en: 'Your library and reading progress match on this iPhone, the server and your other devices.',
        id: 'Library dan progres bacamu sama di iPhone, server, dan perangkat lain.',
      ),
    ),
    SyncStatusKind.waiting: (
      status: (en: 'Waiting for the server', id: 'Menunggu server'),
      explain: (
        en: "The server can't be reached. You can still read straight from the source, and changes go out later.",
        id: 'Server tidak terjangkau. Kamu tetap bisa membaca langsung dari source, dan perubahan akan terkirim nanti.',
      ),
    ),
  },
);

final icloudMethod = SyncMethodSpec(
  kind: SyncMethodKind.icloud,
  name: (en: 'iCloud', id: 'iCloud'),
  description: (en: 'Across your Apple devices', id: 'Antar perangkat Apple'),
  pill: MethodPillIcon.cloud,
  glyph: HubGlyph.cloud,
  nodes: [
    _sourceNode,
    _phoneNode,
    _hub('iCloud', (en: 'your account', id: 'akunmu')),
    _r1(NodeKind.tablet, _iPad, _kuchie),
    _r2(NodeKind.mac, _mac, _kuchie),
  ],
  links: const [
    ..._fanLinks,
    DiagramLink('source', 'phone', LinkRole.source),
    DiagramLink('source', 'r1', LinkRole.sourceOther),
  ],
  syncFlows: const [
    DiagramFlow('phone', 'hub', TokenKind.mix, count: 3, speed: .6),
    DiagramFlow('hub', 'r1', TokenKind.mix, count: 2, speed: .55),
    DiagramFlow('hub', 'r2', TokenKind.mix, count: 2, speed: .5),
  ],
  legend: const [
    LegendItem(_library, synced: true),
    LegendItem(_progress, synced: true),
    LegendItem((en: 'Settings', id: 'Setelan'), synced: true),
    LegendItem(
      _downloads,
      synced: false,
      note: (en: 'each device its own', id: 'tiap perangkat sendiri'),
    ),
  ],
  statuses: const [
    SyncStatusKind.syncing,
    SyncStatusKind.synced,
    SyncStatusKind.waiting,
  ],
  defaultStatus: SyncStatusKind.synced,
  copy: const {
    SyncStatusKind.syncing: (
      status: (en: 'Syncing with iCloud', id: 'Menyinkronkan lewat iCloud'),
      explain: (
        en: 'Library, progress and settings go to your iCloud account, and Kuchie on your iPad and Mac picks them up.',
        id: 'Library, progres, dan setelan dikirim ke akun iCloud-mu, lalu diterima Kuchie di iPad dan Mac.',
      ),
    ),
    SyncStatusKind.synced: (
      status: (en: 'Synced with iCloud', id: 'Tersinkron dengan iCloud'),
      explain: (
        en: 'All your Apple devices have the same library and progress. Each one reads straight from the source.',
        id: 'Semua perangkat Apple-mu punya library dan progres yang sama. Setiap perangkat membaca langsung dari source.',
      ),
    ),
    SyncStatusKind.waiting: (
      status: (en: 'Waiting for iCloud', id: 'Menunggu iCloud'),
      explain: (
        en: 'No internet. Changes stay on this iPhone and go out once it connects again.',
        id: 'Tidak ada internet. Perubahan tersimpan di iPhone dan dikirim saat tersambung lagi.',
      ),
    ),
  },
);

final syncyomiMethod = SyncMethodSpec(
  kind: SyncMethodKind.syncyomi,
  name: (en: 'SyncYomi', id: 'SyncYomi'),
  description: (
    en: 'Sync server for the Tachiyomi family of apps',
    id: 'Server sync untuk aplikasi keluarga Tachiyomi',
  ),
  pill: MethodPillIcon.server,
  glyph: HubGlyph.syncyomi,
  nodes: [
    _sourceNode,
    _phoneNode,
    _hub('SyncYomi', (en: 'sync server', id: 'server sync')),
    _r1(
      NodeKind.android,
      (en: 'Android', id: 'Android'),
      (en: 'Mihon', id: 'Mihon'),
    ),
    _r2(
      NodeKind.tablet,
      (en: 'Tablet', id: 'Tablet'),
      (en: 'Tachiyomi fork', id: 'Fork Tachiyomi'),
    ),
  ],
  links: const [..._fanLinks, DiagramLink('source', 'phone', LinkRole.source)],
  syncFlows: const [
    DiagramFlow.periodic(
      'phone',
      'hub',
      TokenKind.bundle,
      every: 3.6,
      travel: 1.3,
    ),
    DiagramFlow.periodic(
      'hub',
      'r1',
      TokenKind.bundle,
      every: 3.6,
      travel: 1.2,
      delay: 1.5,
    ),
    DiagramFlow.periodic(
      'hub',
      'r2',
      TokenKind.bundle,
      every: 3.6,
      travel: 1.3,
      delay: 1.9,
    ),
  ],
  legend: const [
    LegendItem(_library, synced: true),
    LegendItem((en: 'Categories', id: 'Kategori'), synced: true),
    LegendItem(_progress, synced: true),
    LegendItem(_downloads, synced: false),
  ],
  statuses: const [
    SyncStatusKind.syncing,
    SyncStatusKind.synced,
    SyncStatusKind.waiting,
  ],
  defaultStatus: SyncStatusKind.synced,
  copy: const {
    SyncStatusKind.syncing: (
      status: (
        en: 'Syncing with SyncYomi',
        id: 'Menyinkronkan dengan SyncYomi',
      ),
      explain: (
        en: 'Library, categories and progress go to the SyncYomi server as one bundle, and Mihon and other Tachiyomi-family apps fetch it.',
        id: 'Library, kategori, dan progres dikirim sebagai satu paket ke server SyncYomi, lalu diambil Mihon dan aplikasi keluarga Tachiyomi lainnya.',
      ),
    ),
    SyncStatusKind.synced: (
      status: (en: 'Synced with SyncYomi', id: 'Tersinkron dengan SyncYomi'),
      explain: (
        en: 'The library in Kuchie matches the other apps that use SyncYomi.',
        id: 'Library di Kuchie dan aplikasi lain yang memakai SyncYomi sudah sama.',
      ),
    ),
    SyncStatusKind.waiting: (
      status: (en: 'Waiting for SyncYomi', id: 'Menunggu SyncYomi'),
      explain: (
        en: "The SyncYomi server can't be reached. Changes go out in the next bundle.",
        id: 'Server SyncYomi tidak terjangkau. Perubahan dikirim dalam paket berikutnya.',
      ),
    ),
  },
);

final kosyncMethod = SyncMethodSpec(
  kind: SyncMethodKind.kosync,
  name: (en: 'KOReader Sync', id: 'KOReader Sync'),
  description: (
    en: 'Reading position through a kosync server',
    id: 'Posisi baca lewat server kosync',
  ),
  pill: MethodPillIcon.server,
  glyph: HubGlyph.kosync,
  nodes: [
    _sourceNode,
    _phoneNode,
    _hub('KOReader Sync', (en: 'kosync server', id: 'server kosync')),
    const DiagramNode(
      id: 'r',
      kind: NodeKind.ereader,
      x: .85,
      y: 146,
      label: (en: 'E-reader', id: 'E-reader'),
      sub: (en: 'KOReader', id: 'KOReader'),
    ),
  ],
  links: const [
    DiagramLink('phone', 'hub', LinkRole.sync),
    DiagramLink('hub', 'r', LinkRole.fan),
    DiagramLink('source', 'phone', LinkRole.source),
  ],
  syncFlows: const [
    DiagramFlow('phone', 'hub', TokenKind.mark, count: 2, speed: .4, lane: -5),
    DiagramFlow('hub', 'r', TokenKind.mark, count: 2, speed: .4, lane: -5),
    DiagramFlow('r', 'hub', TokenKind.mark, count: 1, speed: .3, lane: -5),
    DiagramFlow('hub', 'phone', TokenKind.mark, count: 1, speed: .3, lane: -5),
  ],
  legend: const [
    LegendItem(
      (en: 'Reading position', id: 'Posisi baca'),
      synced: true,
      note: (en: 'per chapter', id: 'per chapter'),
    ),
    LegendItem(_library, synced: false),
    LegendItem(_downloads, synced: false),
  ],
  statuses: const [
    SyncStatusKind.syncing,
    SyncStatusKind.synced,
    SyncStatusKind.waiting,
  ],
  defaultStatus: SyncStatusKind.synced,
  copy: const {
    SyncStatusKind.syncing: (
      status: (en: 'Sending reading position', id: 'Mengirim posisi baca'),
      explain: (
        en: 'Only your position in each chapter goes to the KOReader Sync server, so you can continue in KOReader.',
        id: 'Hanya posisi baca per chapter yang dikirim ke server KOReader Sync, supaya bisa dilanjutkan di KOReader.',
      ),
    ),
    SyncStatusKind.synced: (
      status: (en: 'Reading position synced', id: 'Posisi baca tersinkron'),
      explain: (
        en: 'The chapter you are reading is on the same page on this iPhone and in KOReader.',
        id: 'Chapter yang sedang dibaca berada di halaman yang sama di iPhone dan KOReader.',
      ),
    ),
    SyncStatusKind.waiting: (
      status: (
        en: 'Waiting for the kosync server',
        id: 'Menunggu server kosync',
      ),
      explain: (
        en: 'Your position stays on this iPhone and goes out once the server can be reached.',
        id: 'Posisi baca disimpan di iPhone dan dikirim saat server terjangkau.',
      ),
    ),
  },
);

SyncMethodSpec _media(
  SyncMethodKind kind,
  String name,
  SyncCopy description,
) => SyncMethodSpec(
  kind: kind,
  name: (en: name, id: name),
  description: description,
  pill: MethodPillIcon.server,
  glyph: HubGlyph.media,
  nodes: [
    _phoneNode,
    _hub(name, (en: 'file collection', id: 'koleksi file')),
    _r1(NodeKind.mac, _mac, (en: '$name WebUI', id: 'WebUI $name'), y: 92),
    _r2(NodeKind.tablet, _iPad, _kuchie),
  ],
  links: _fanLinks,
  syncFlows: const [
    DiagramFlow('hub', 'phone', TokenKind.page, count: 3, speed: .35, lane: 5),
    DiagramFlow('phone', 'hub', TokenKind.dot, count: 2, speed: .5, lane: -5),
    DiagramFlow('hub', 'r2', TokenKind.page, count: 2, speed: .3),
  ],
  legend: const [
    LegendItem(
      (en: 'File collection', id: 'Koleksi file'),
      synced: true,
      note: (en: 'on the server', id: 'di server'),
    ),
    LegendItem(_progress, synced: true),
    LegendItem((en: 'Read directly', id: 'Baca langsung'), synced: true),
    LegendItem(
      (en: 'Extensions', id: 'Extension'),
      synced: false,
      note: (en: 'not needed', id: 'tidak perlu'),
    ),
  ],
  statuses: const [
    SyncStatusKind.syncing,
    SyncStatusKind.synced,
    SyncStatusKind.waiting,
  ],
  defaultStatus: SyncStatusKind.syncing,
  copy: {
    SyncStatusKind.syncing: (
      status: (en: 'Reading from $name', id: 'Membaca dari $name'),
      explain: (
        en: '$name keeps the manga files on your server. Kuchie reads pages straight from it and sends progress back.',
        id: '$name menyimpan file manga di servermu. Kuchie membaca halaman langsung dari server dan mengirim progres balik.',
      ),
    ),
    SyncStatusKind.synced: (
      status: (en: 'Synced with $name', id: 'Tersinkron dengan $name'),
      explain: (
        en: 'Reading progress in Kuchie matches $name and other apps on this server.',
        id: 'Progres baca di Kuchie sama dengan di $name dan aplikasi lain yang memakai server ini.',
      ),
    ),
    SyncStatusKind.waiting: (
      status: (en: "$name can't be reached", id: '$name tidak terjangkau'),
      explain: (
        en: 'Downloaded chapters can still be read. Progress goes out once the server can be reached.',
        id: 'Chapter yang sudah diunduh tetap bisa dibaca. Progres dikirim saat server terjangkau.',
      ),
    ),
  },
);

final komgaMethod = _media(SyncMethodKind.komga, 'Komga', (
  en: 'Comics and manga server',
  id: 'Server komik dan manga',
));

final kavitaMethod = _media(SyncMethodKind.kavita, 'Kavita', (
  en: 'Personal reading server',
  id: 'Server bacaan pribadi',
));

final driveMethod = SyncMethodSpec(
  kind: SyncMethodKind.drive,
  name: (en: 'Google Drive', id: 'Google Drive'),
  description: (
    en: 'A periodic sync file in Drive',
    id: 'File sync berkala di Drive',
  ),
  pill: MethodPillIcon.cloud,
  glyph: HubGlyph.drive,
  nodes: [
    _sourceNode,
    _phoneNode,
    _hub('Google Drive', (en: 'sync file', id: 'file sync')),
    _r1(NodeKind.tablet, _iPad, _kuchie),
    _r2(NodeKind.mac, _mac, _kuchie),
  ],
  links: const [..._fanLinks, DiagramLink('source', 'phone', LinkRole.source)],
  syncFlows: const [
    DiagramFlow.periodic(
      'phone',
      'hub',
      TokenKind.file,
      every: 4.2,
      travel: 1.4,
    ),
    DiagramFlow.periodic(
      'hub',
      'r1',
      TokenKind.file,
      every: 4.2,
      travel: 1.3,
      delay: 1.8,
    ),
    DiagramFlow.periodic(
      'hub',
      'r2',
      TokenKind.file,
      every: 4.2,
      travel: 1.4,
      delay: 2.3,
    ),
  ],
  legend: const [
    LegendItem(_library, synced: true),
    LegendItem(_progress, synced: true),
    LegendItem(
      (en: 'Live', id: 'Langsung'),
      synced: false,
      note: (en: 'periodic', id: 'berkala'),
    ),
    LegendItem(_downloads, synced: false),
  ],
  statuses: const [
    SyncStatusKind.syncing,
    SyncStatusKind.synced,
    SyncStatusKind.waiting,
  ],
  defaultStatus: SyncStatusKind.synced,
  copy: const {
    SyncStatusKind.syncing: (
      status: (
        en: 'Uploading the sync file to Drive',
        id: 'Mengunggah file sync ke Drive',
      ),
      explain: (
        en: 'Kuchie keeps one file with your library and progress in your Drive, now and then. Other devices fetch that file.',
        id: 'Kuchie menyimpan satu file berisi library dan progres di Drive-mu secara berkala. Perangkat lain mengambil file itu.',
      ),
    ),
    SyncStatusKind.synced: (
      status: (
        en: 'Latest sync file in Drive',
        id: 'File sync terbaru di Drive',
      ),
      explain: (
        en: 'Your iPad and Mac use the same file as this iPhone.',
        id: 'iPad dan Mac memakai file yang sama dengan iPhone.',
      ),
    ),
    SyncStatusKind.waiting: (
      status: (en: 'Waiting for Drive', id: 'Menunggu Drive'),
      explain: (
        en: 'No internet. The sync file uploads once it connects again.',
        id: 'Tidak ada internet. File sync diunggah saat tersambung lagi.',
      ),
    ),
  },
);

/// In the order of the method list.
final syncMethods = <SyncMethodKind, SyncMethodSpec>{
  for (final method in [
    localMethod,
    suwayomiMethod,
    icloudMethod,
    syncyomiMethod,
    kosyncMethod,
    komgaMethod,
    kavitaMethod,
    driveMethod,
  ])
    method.kind: method,
};
