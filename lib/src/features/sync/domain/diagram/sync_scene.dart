import 'dart:math' as math;

import 'sync_methods.dart';

// A scene is one method in one status: how bright each part of the diagram
// is, what moves, how fast the ambient motion runs, and the card's text.
// Pure; the diagram widget eases between scenes.

/// Brightness targets, 0 to 1, that the diagram eases towards.
class SceneValues {
  const SceneValues({
    this.hub = 1,
    this.sync = 1,
    this.fan = 1,
    this.others = 1,
    this.source = .35,
    this.sourceHot = 0,
    this.source2 = .3,
    this.dashed = 0,
    this.broken = 0,
    this.lock = 0,
    this.check = 0,
  });

  /// The centre node.
  final double hub;

  /// iPhone to the centre.
  final double sync;

  /// The centre to other devices.
  final double fan;

  /// Other devices.
  final double others;

  /// Source to iPhone.
  final double source;

  /// Source to iPhone in the second accent, while reading from it.
  final double sourceHot;

  /// Source to the server.
  final double source2;

  /// Lines drawn dashed, for the local diagram.
  final double dashed;

  /// iPhone to the centre broken in the middle.
  final double broken;

  /// The lock on the centre node.
  final double lock;

  /// Check badges on the devices.
  final double check;

  List<double> get _all => [
    hub,
    sync,
    fan,
    others,
    source,
    sourceHot,
    source2,
    dashed,
    broken,
    lock,
    check,
  ];

  static SceneValues _from(List<double> v) => SceneValues(
    hub: v[0],
    sync: v[1],
    fan: v[2],
    others: v[3],
    source: v[4],
    sourceHot: v[5],
    source2: v[6],
    dashed: v[7],
    broken: v[8],
    lock: v[9],
    check: v[10],
  );

  /// Moves each value [k] of the way towards [target].
  SceneValues approach(SceneValues target, double k) {
    final from = _all, to = target._all;
    return _from([
      for (var i = 0; i < from.length; i++) from[i] + (to[i] - from[i]) * k,
    ]);
  }

  SceneValues copyWith({double? source}) {
    final v = _all;
    if (source != null) v[4] = source;
    return _from(v);
  }

  @override
  bool operator ==(Object other) {
    if (other is! SceneValues) return false;
    final a = _all, b = other._all;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_all);
}

enum PillTone { accent, muted, danger }

/// The Library title icon (design 3.1).
enum SyncIconKind { none, check, spin, wait, alert }

/// The card's main action.
enum SyncCta {
  connect,
  checking,
  syncing,
  syncNow,
  retry,
  signIn,
  viewQueue,
  pause,
  viewDownloads,
  comingSoon;

  bool get enabled => this != checking && this != syncing && this != comingSoon;

  /// Drawn as an outlined button.
  bool get secondary =>
      this == syncNow ||
      this == retry ||
      this == viewQueue ||
      this == pause ||
      this == viewDownloads;

  SyncCopy get label => switch (this) {
    connect => (en: 'Connect sync', id: 'Hubungkan sinkronisasi'),
    checking => (en: 'Checking…', id: 'Memeriksa…'),
    syncing => (en: 'Syncing…', id: 'Menyinkronkan…'),
    syncNow => (en: 'Sync now', id: 'Sinkronkan sekarang'),
    retry => (en: 'Try again', id: 'Coba lagi'),
    signIn => (en: 'Sign in again', id: 'Masuk lagi'),
    viewQueue => (en: 'View queue', id: 'Lihat antrean'),
    pause => (en: 'Pause', id: 'Jeda'),
    viewDownloads => (en: 'View downloads', id: 'Lihat unduhan'),
    comingSoon => (en: 'Coming soon', id: 'Segera hadir'),
  };
}

/// A counter the diagram runs while a status animates numbers up.
class SceneCounter {
  const SceneCounter({required this.total, required this.step, this.start = 0});

  final int total;

  /// Seconds per step.
  final double step;
  final int start;
}

/// How one status moves, for every method that has it.
class StatusSpec {
  const StatusSpec({
    required this.pill,
    required this.tone,
    required this.icon,
    required this.cta,
    this.values = const SceneValues(),
    this.still = false,
    this.spin = 0,
    this.ripple = 0,
    this.march = 0,
    this.leds = false,
    this.pulse = false,
    this.scan = false,
    this.drawOn = false,
    this.pending = false,
    this.flows,
    this.counter,
    this.copy,
  });

  final SceneValues values;
  final SyncCopy pill;
  final PillTone tone;

  /// The pill's dot stays still.
  final bool still;
  final SyncIconKind icon;
  final SyncCta cta;

  /// Orbit speed, radians per second.
  final double spin;

  /// Seconds between ripples around the centre; 0 for none.
  final double ripple;

  /// Speed of the dashes moving along active lines; the sign is the direction.
  final double march;

  /// Server LEDs blink.
  final bool leds;

  /// A pulse runs iPhone → centre → devices every 6 seconds.
  final bool pulse;

  /// A pulse goes back and forth on iPhone → centre.
  final bool scan;

  /// Lines draw themselves in.
  final bool drawOn;

  /// Queued changes bounce beside iPhone.
  final bool pending;

  /// What moves, when not the method's own flows.
  final List<DiagramFlow>? flows;
  final SceneCounter? counter;

  /// Copy for statuses that read the same for every method.
  final StatusCopy? copy;
}

const _running = (en: 'Running', id: 'Berjalan');

const statusSpecs = <SyncStatusKind, StatusSpec>{
  SyncStatusKind.local: StatusSpec(
    values: SceneValues(
      hub: .5,
      sync: .35,
      fan: 0,
      others: 0,
      source: 1,
      sourceHot: 1,
      dashed: 1,
    ),
    pill: (en: 'No sync', id: 'Tanpa sync'),
    tone: PillTone.muted,
    still: true,
    icon: SyncIconKind.none,
    cta: SyncCta.connect,
    flows: [
      DiagramFlow('source', 'phone', TokenKind.page, count: 3, speed: .3),
    ],
    copy: (
      status: (en: 'Only on this iPhone', id: 'Hanya di iPhone'),
      explain: (
        en: 'Your library, progress and downloads are kept on this iPhone. Chapters come straight from the source through extensions.',
        id: 'Library, progres, dan unduhan tersimpan di iPhone ini. Chapter diambil langsung dari source lewat extension.',
      ),
    ),
  ),
  SyncStatusKind.analyzing: StatusSpec(
    values: SceneValues(fan: .35, others: .5, source: .4),
    pill: (en: 'Checking', id: 'Memeriksa'),
    tone: PillTone.accent,
    icon: SyncIconKind.spin,
    cta: SyncCta.checking,
    spin: .8,
    ripple: 1.6,
    scan: true,
    drawOn: true,
    flows: [],
    copy: (
      status: (en: 'Checking the server…', id: 'Memeriksa server…'),
      explain: (
        en: 'Comparing the library on this iPhone with the one on the server. Nothing has changed yet.',
        id: 'Membandingkan library di iPhone dan di server. Belum ada yang diubah.',
      ),
    ),
  ),
  SyncStatusKind.syncing: StatusSpec(
    pill: _running,
    tone: PillTone.accent,
    icon: SyncIconKind.spin,
    cta: SyncCta.syncing,
    spin: 2.4,
    ripple: 1.1,
    march: 40,
    leds: true,
    counter: SceneCounter(total: 50, step: .18),
  ),
  SyncStatusKind.synced: StatusSpec(
    values: SceneValues(check: 1),
    pill: (en: 'Active', id: 'Aktif'),
    tone: PillTone.accent,
    icon: SyncIconKind.check,
    cta: SyncCta.syncNow,
    spin: .25,
    ripple: 4,
    march: 8,
    pulse: true,
    flows: [],
  ),
  SyncStatusKind.waiting: StatusSpec(
    values: SceneValues(
      hub: .4,
      sync: .45,
      fan: .2,
      others: .35,
      source: 1,
      sourceHot: 1,
      broken: 1,
    ),
    pill: (en: 'Waiting', id: 'Menunggu'),
    tone: PillTone.muted,
    still: true,
    icon: SyncIconKind.wait,
    cta: SyncCta.retry,
    pending: true,
  ),
  SyncStatusKind.action: StatusSpec(
    values: SceneValues(hub: .85, sync: .35, fan: .3, others: .5, lock: 1),
    pill: (en: 'Action needed', id: 'Perlu tindakan'),
    tone: PillTone.danger,
    still: true,
    icon: SyncIconKind.alert,
    cta: SyncCta.signIn,
    flows: [],
    copy: (
      status: (en: 'Sign in again', id: 'Perlu masuk lagi'),
      explain: (
        en: 'Your server login expired. Sign in again to keep syncing.',
        id: 'Login ke server kedaluwarsa. Masuk lagi untuk melanjutkan sync.',
      ),
    ),
  ),
  SyncStatusKind.serverDownload: StatusSpec(
    values: SceneValues(sync: .6, fan: .6, others: .8, source2: 1),
    pill: _running,
    tone: PillTone.accent,
    icon: SyncIconKind.check,
    cta: SyncCta.viewQueue,
    spin: 1,
    leds: true,
    flows: [DiagramFlow('source', 'hub', TokenKind.page, count: 3, speed: .35)],
    copy: (
      status: (en: 'Downloading on the server', id: 'Mengunduh di server'),
      explain: (
        en: "The server downloads chapters from the source. This iPhone doesn't fill up.",
        id: 'Server mengunduh chapter dari source. iPhone tidak ikut penuh.',
      ),
    ),
  ),
  SyncStatusKind.moveToServer: StatusSpec(
    values: SceneValues(fan: .5, others: .8),
    pill: _running,
    tone: PillTone.accent,
    icon: SyncIconKind.spin,
    cta: SyncCta.pause,
    spin: 2,
    ripple: 1.4,
    march: 30,
    leds: true,
    flows: [DiagramFlow('phone', 'hub', TokenKind.page, count: 3, speed: .32)],
    counter: SceneCounter(total: 86, step: .45, start: 34),
    copy: (
      status: (en: 'Moving to the server', id: 'Memindahkan ke server'),
      explain: (
        en: 'The copy on this iPhone is deleted once the server has saved it.',
        id: 'Salinan di iPhone dihapus setelah server menyimpannya.',
      ),
    ),
  ),
  SyncStatusKind.saveOffline: StatusSpec(
    values: SceneValues(fan: .5, others: .8),
    pill: _running,
    tone: PillTone.accent,
    icon: SyncIconKind.spin,
    cta: SyncCta.viewDownloads,
    spin: -2,
    ripple: 1.4,
    march: -30,
    flows: [DiagramFlow('hub', 'phone', TokenKind.page, count: 3, speed: .32)],
    copy: (
      status: (en: 'Saving for offline', id: 'Menyimpan untuk offline'),
      explain: (
        en: 'Chapters are copied from the server to this iPhone so they can be read without internet.',
        id: 'Chapter disalin dari server ke iPhone supaya bisa dibaca tanpa internet.',
      ),
    ),
  ),
};

/// Done out of total, for a running sync or transfer.
class SyncProgress {
  const SyncProgress(this.done, this.total);

  final int done, total;
}

/// The real numbers a scene shows. The defaults are the sample figures
/// that previews and the explainer use.
class SyncFigures {
  const SyncFigures({
    this.librarySize = 42,
    this.lastSuccessAt,
    this.pending = 3,
    this.progress,
    this.transfer,
  });

  static const sample = SyncFigures();

  final int librarySize;
  final DateTime? lastSuccessAt;

  /// Changes waiting to be sent.
  final int pending;
  final SyncProgress? progress;
  final SyncProgress? transfer;
}

/// What the status line adds after the status, formatted by the card.
sealed class StatusDetail {
  const StatusDetail();
}

final class AgoDetail extends StatusDetail {
  const AgoDetail(this.at);
  final DateTime at;
}

final class PendingDetail extends StatusDetail {
  const PendingDetail(this.count);
  final int count;
}

final class ProgressDetail extends StatusDetail {
  const ProgressDetail(this.progress);
  final SyncProgress progress;
}

class SyncScene {
  const SyncScene({
    required this.method,
    required this.status,
    required this.spec,
    required this.values,
    required this.flows,
    required this.copy,
    required this.figures,
    required this.cta,
    this.detail,
  });

  final SyncMethodSpec method;
  final SyncStatusKind status;
  final StatusSpec spec;
  final SceneValues values;
  final List<DiagramFlow> flows;
  final StatusCopy copy;
  final StatusDetail? detail;
  final SyncFigures figures;
  final SyncCta cta;

  /// Periodic methods send occasional tokens, not a stream.
  bool get periodic => flows.any((flow) => flow.isPeriodic);

  /// Continuous methods have a satellite on the orbit.
  bool get continuous => !method.syncFlows.any((flow) => flow.isPeriodic);
}

/// [status] must be one of [method]'s statuses.
SyncScene sceneFor(
  SyncMethodSpec method,
  SyncStatusKind status, {
  SyncFigures figures = SyncFigures.sample,
}) {
  assert(method.statuses.contains(status), '${method.kind} has no $status');
  final spec = statusSpecs[status]!;
  var values = spec.values;
  var flows = spec.flows ?? const <DiagramFlow>[];
  if (status == SyncStatusKind.syncing) flows = method.syncFlows;
  if (status == SyncStatusKind.waiting) {
    flows = method.hasSourceToPhone
        ? const [
            DiagramFlow('source', 'phone', TokenKind.page, count: 3, speed: .3),
          ]
        : const [];
    if (!method.hasSource) values = values.copyWith(source: 0);
  }
  final copy = spec.copy ?? method.copy[status]!;
  final StatusDetail? detail = switch (status) {
    SyncStatusKind.synced when figures.lastSuccessAt != null => AgoDetail(
      figures.lastSuccessAt!,
    ),
    SyncStatusKind.waiting when figures.pending > 0 => PendingDetail(
      figures.pending,
    ),
    SyncStatusKind.syncing when figures.progress != null => ProgressDetail(
      figures.progress!,
    ),
    SyncStatusKind.moveToServer ||
    SyncStatusKind.serverDownload ||
    SyncStatusKind.saveOffline when figures.transfer != null => ProgressDetail(
      figures.transfer!,
    ),
    _ => null,
  };
  return SyncScene(
    method: method,
    status: status,
    spec: spec,
    values: values,
    flows: flows,
    copy: copy,
    detail: detail,
    figures: figures,
    cta: method.available || status == SyncStatusKind.local
        ? spec.cta
        : status == SyncStatusKind.syncing
        ? SyncCta.syncing
        : SyncCta.comingSoon,
  );
}

/// Text and fill on one device screen.
class NodeScreen {
  const NodeScreen(this.text, this.progress);

  final String text;
  final double progress;

  @override
  bool operator ==(Object other) =>
      other is NodeScreen && other.text == text && other.progress == progress;

  @override
  int get hashCode => Object.hash(text, progress);
}

/// What every device screen shows, and the labels that change with time.
class SceneScreens {
  const SceneScreens({
    required this.screens,
    required this.phoneSub,
    this.hubSub,
  });

  final Map<String, NodeScreen> screens;

  /// Replaces the centre node's caption, such as "Unreachable".
  final SyncCopy? hubSub;
  final SyncCopy phoneSub;

  NodeScreen screen(String id) => screens[id] ?? const NodeScreen('', 1);
}

/// Screens at [t] seconds into [scene], with [counter] steps of its counter.
SceneScreens screensFor(SyncScene scene, int counter, double t) {
  final total = math.max(1, scene.figures.librarySize);
  final status = scene.status, method = scene.method.kind;
  NodeScreen pair(int n) {
    final clamped = n.clamp(0, total);
    return NodeScreen('$clamped/$total', clamped / total);
  }

  int lag(int d, int k) => (d - k).clamp(0, total);
  final full = pair(total);
  final screens = <String, NodeScreen>{
    'phone': NodeScreen('$total', 1),
    'r1': full,
    'r2': full,
    'r': full,
  };
  SyncCopy? hubSub;
  final series = (en: '$total series', id: '$total series');
  var phoneSub = series;
  final media =
      method == SyncMethodKind.komga || method == SyncMethodKind.kavita;

  switch (status) {
    case SyncStatusKind.local:
      screens['phone'] = NodeScreen('$total', .3 + (t * .05) % .5);
      hubSub = (en: 'Not connected', id: 'Belum terhubung');
    case _ when method == SyncMethodKind.kosync:
      final synced = status == SyncStatusKind.synced;
      final syncing = status == SyncStatusKind.syncing;
      final percent = syncing
          ? 40 + math.min(42, counter)
          : synced
          ? 82
          : 61;
      final other = syncing
          ? 40 + (counter - 6).clamp(0, 42)
          : synced
          ? 82
          : 55;
      screens['phone'] = NodeScreen('$percent%', percent / 100);
      screens['r'] = status == SyncStatusKind.waiting
          ? const NodeScreen('?', 0)
          : NodeScreen('$other%', other / 100);
    case SyncStatusKind.syncing when scene.periodic:
      final flows = scene.flows;
      NodeScreen stale(DiagramFlow flow) =>
          t % flow.every! < flow.delay + flow.travel! && t < flow.every!
          ? pair(math.max(0, total - 4))
          : full;
      screens['r1'] = stale(flows[1]);
      screens['r2'] = stale(flows[2]);
      if (t % flows[0].every! < flows[0].travel!) {
        hubSub = method == SyncMethodKind.drive
            ? (en: 'Uploading file', id: 'Mengunggah file')
            : (en: 'Receiving bundle', id: 'Menerima paket');
      }
    case SyncStatusKind.syncing when media:
      final page = 1 + (t * 2).floor() % 24;
      screens['phone'] = NodeScreen('$page/24', page / 24);
    case SyncStatusKind.syncing:
      final done = scene.figures.progress?.done ?? counter;
      screens['phone'] = pair(done);
      screens['r1'] = pair(lag(done, 4));
      screens['r2'] = pair(lag(done, 8));
      phoneSub = (
        en: '${done.clamp(0, total)}/$total series',
        id: '${done.clamp(0, total)}/$total series',
      );
    case SyncStatusKind.waiting:
      final pending = scene.figures.pending;
      screens['phone'] = NodeScreen(pending > 0 ? '+$pending' : '$total', 1);
      screens['r1'] = screens['r2'] = screens['r'] = const NodeScreen('?', 0);
      hubSub = (en: 'Unreachable', id: 'Tidak terjangkau');
    case SyncStatusKind.analyzing:
      final dots = '.' * (1 + (t * 3).floor() % 3);
      screens['r1'] = screens['r2'] = NodeScreen(dots, 0);
      hubSub = (en: 'Checking', id: 'Memeriksa');
    case SyncStatusKind.action:
      hubSub = (en: 'Sign in again', id: 'Perlu masuk lagi');
    case SyncStatusKind.serverDownload:
      final transfer = scene.figures.transfer;
      final done = transfer?.done ?? 1 + (t / 1.6).floor() % 4;
      final of = transfer?.total ?? 4;
      hubSub = (en: 'Downloading $done/$of', id: 'Mengunduh $done/$of');
    case SyncStatusKind.moveToServer:
      final transfer = scene.figures.transfer;
      final of = transfer?.total ?? 86;
      final done = transfer?.done ?? counter;
      screens['phone'] = NodeScreen('${of - done}', (of - done) / of);
      hubSub = (en: 'Received $done/$of', id: 'Diterima $done/$of');
    case SyncStatusKind.saveOffline:
      final k = 1 + (t / 1.6).floor() % 3;
      screens['phone'] = NodeScreen('$k/3', (t / 1.6) % 1);
    case SyncStatusKind.synced:
      // In sync, the server holds the same library as this iPhone.
      if (method == SyncMethodKind.suwayomi) hubSub = series;
  }
  return SceneScreens(screens: screens, hubSub: hubSub, phoneSub: phoneSub);
}

/// The three explainer steps (design 3.9): local, connected, away.
final explainerSteps = <(SyncMethodSpec, SyncStatusKind, SyncCopy)>[
  (
    localMethod,
    SyncStatusKind.local,
    (
      en: 'Without sync, everything stays on your iPhone.',
      id: 'Tanpa sync, semuanya di iPhone.',
    ),
  ),
  (
    suwayomiMethod,
    SyncStatusKind.syncing,
    (
      en: 'With sync, your library and progress are copied too.',
      id: 'Dengan sync, library dan progres ikut tersalin.',
    ),
  ),
  (
    suwayomiMethod,
    SyncStatusKind.waiting,
    (
      en: "Server out of reach? You can still read.",
      id: 'Server tidak terjangkau? Tetap bisa baca.',
    ),
  ),
];
