import 'chesscom_service.dart';
import 'game_library.dart';

/// الفترات المدعومة عند جلب المباريات.
enum ImportPeriod { lastMonth, last3Months, last6Months, thisYear, month, all }

/// شهر في أرشيف Chess.com.
class ArchiveMonth {
  final int year;
  final int month;
  final String url;

  const ArchiveMonth(this.year, this.month, this.url);

  String get label => '$year/${month.toString().padLeft(2, '0')}';

  int get index => year * 12 + (month - 1);

  /// أرشيف يُقرأ من رابط ينتهي بـ /yyyy/MM.
  static ArchiveMonth? parse(String url) {
    final segs = url.split('/').where((e) => e.isNotEmpty).toList();

    if (segs.length < 2) return null;

    final y = int.tryParse(segs[segs.length - 2]);
    final m = int.tryParse(segs.last);

    if (y == null || m == null || m < 1 || m > 12) return null;

    return ArchiveMonth(y, m, url);
  }
}

class MonthBatch {
  final ArchiveMonth month;
  final List<ChessComGame> games;

  const MonthBatch(this.month, this.games);
}

class ImportResult {
  final int added;
  final int skipped;

  const ImportResult({required this.added, required this.skipped});
}

class SyncResult {
  final int added;
  final int skipped;
  final int months;

  const SyncResult({
    required this.added,
    required this.skipped,
    required this.months,
  });
}

/// الواجهة بين الـAPI والمكتبة: لا تعرف شيئًا عن الواجهة.
///
///   ChessComApiService → ChessComRepository → GameLibraryStorage
class ChessComRepository {
  ChessComRepository({
    ChessComService? service,
    GameLibraryStorage? storage,
    DateTime Function()? now,
  })  : service = service ?? ChessComService(),
        storage = storage ?? GameLibraryStorage.instance,
        _now = now ?? DateTime.now;

  final ChessComService service;
  final GameLibraryStorage storage;
  final DateTime Function() _now;

  Future<List<ArchiveMonth>> archives(String username) async {
    await service.getPlayer(username);

    final urls = await service.getGameArchives(username);

    return <ArchiveMonth>[
      for (final u in urls)
        if (ArchiveMonth.parse(u) != null) ArchiveMonth.parse(u)!,
    ];
  }

  /// الحد الأدنى لتاريخ المباراة لهذه الفترة (null = بلا حد).
  static DateTime? cutoffFor(ImportPeriod p, DateTime now) {
    switch (p) {
      case ImportPeriod.lastMonth:
        return now.subtract(const Duration(days: 30));
      case ImportPeriod.last3Months:
        return now.subtract(const Duration(days: 90));
      case ImportPeriod.last6Months:
        return now.subtract(const Duration(days: 180));
      case ImportPeriod.thisYear:
        return DateTime(now.year);
      case ImportPeriod.month:
      case ImportPeriod.all:
        return null;
    }
  }

  /// الأشهر المطلوبة لهذه الفترة، الأحدث أولًا.
  static List<ArchiveMonth> selectMonths(
    List<ArchiveMonth> all,
    ImportPeriod p, {
    required DateTime now,
    ({int year, int month})? month,
  }) {
    final cutoff = cutoffFor(p, now);

    final picked = all.where((a) {
      if (p == ImportPeriod.month) {
        return month != null && a.year == month.year && a.month == month.month;
      }

      if (cutoff == null) return true;

      return a.index >= cutoff.year * 12 + (cutoff.month - 1);
    }).toList();

    picked.sort((a, b) => b.index.compareTo(a.index));

    return picked;
  }

  /// يجلب الأشهر تدريجيًا (شهر بعد شهر، بطلبات متسلسلة) فلا يُحمَّل
  /// الأرشيف كله دفعة واحدة. يمكن للمستدعي التوقف في أي لحظة.
  Stream<MonthBatch> fetchPeriod(
    String username,
    ImportPeriod period, {
    ({int year, int month})? month,
  }) async* {
    final months = selectMonths(
      await archives(username),
      period,
      now: _now(),
      month: month,
    );

    final cutoff = cutoffFor(period, _now());

    for (final m in months) {
      var games = await service.getGamesFromArchiveUrl(m.url);

      if (cutoff != null) {
        games = [
          for (final g in games)
            if (g.endTime == null || !g.endTime!.isBefore(cutoff)) g,
        ];
      }

      yield MonthBatch(m, games);
    }
  }

  /// يحفظ مباريات جاهزة (من الشاشة) في المكتبة؛ المكرر يُتجاهل.
  Future<ImportResult> saveGames(List<LibraryGame> games) async {
    final added = await storage.add(games);

    return ImportResult(added: added, skipped: games.length - added);
  }

  /// يحفظ المباريات المحدَّدة في المكتبة؛ المكرر يُتجاهل.
  Future<ImportResult> importGames(
    String username,
    List<ChessComGame> games,
  ) async {
    final lib = [for (final g in games) LibraryGame.fromChessCom(g, username)];

    final added = await storage.add(lib);

    return ImportResult(added: added, skipped: lib.length - added);
  }

  /// مزامنة: تجلب فقط الأشهر منذ آخر مزامنة (الشهر الأخير يُعاد جلبه
  /// لأنه قد يكون ناقصًا)، وتحفظ الجديد فقط، دون تحليل أي شيء.
  Future<SyncResult> sync(String username) async {
    final all = await archives(username);

    final state = await storage.syncState(username);

    final List<ArchiveMonth> months;

    if (state == null || state.lastMonth.isEmpty) {
      months = selectMonths(all, ImportPeriod.last3Months, now: _now());
    } else {
      final last = state.lastMonth.split('/');
      final idx = (int.tryParse(last.first) ?? 0) * 12 +
          ((int.tryParse(last.last) ?? 1) - 1);

      months = [
        for (final a in all)
          if (a.index >= idx) a,
      ]..sort((a, b) => b.index.compareTo(a.index));
    }

    var added = 0;
    var skipped = 0;

    for (final m in months) {
      final games = await service.getGamesFromArchiveUrl(m.url);
      final r = await importGames(username, games);

      added += r.added;
      skipped += r.skipped;
    }

    final newest = months.isNotEmpty
        ? months.first
        : (all.isNotEmpty ? all.last : null);

    await storage.saveSyncState(
      username,
      SyncState(
        lastSyncMs: _now().millisecondsSinceEpoch,
        lastMonth: newest?.label ?? state?.lastMonth ?? '',
      ),
    );

    return SyncResult(added: added, skipped: skipped, months: months.length);
  }
}
