import 'package:flutter/foundation.dart';

import 'account_storage.dart';
import 'chesscom_repository.dart';
import 'chesscom_service.dart';
import 'game_library.dart';

/// حالة شاشة الاستيراد: الواجهة ← هذا المتحكم ← Repository ← API.
class ChessComImportController extends ChangeNotifier {
  ChessComImportController({ChessComRepository? repository})
      : repo = repository ?? ChessComRepository();

  final ChessComRepository repo;

  ImportPeriod period = ImportPeriod.lastMonth;
  ({int year, int month})? month;

  bool loading = false;
  String? error;
  String progress = '';

  /// المباريات المجلوبة (الأحدث أولًا) وما هو موجود منها في المكتبة.
  List<LibraryGame> items = <LibraryGame>[];
  Set<String> existing = <String>{};
  Set<String> selected = <String>{};

  String username = '';
  SyncState? syncState;
  bool syncing = false;
  String? syncMessage;

  bool _cancel = false;
  int _token = 0;

  Future<void> init() async {
    final saved = await AccountStorage.getChessComUsername();

    if (saved != null) {
      username = saved;
      syncState = await repo.storage.syncState(saved);
      notifyListeners();
    }
  }

  void setPeriod(ImportPeriod p) {
    period = p;
    notifyListeners();
  }

  void setMonth(({int year, int month}) m) {
    month = m;
    notifyListeners();
  }

  void cancel() {
    _cancel = true;
  }

  Future<void> fetch(String rawUsername) async {
    final u = rawUsername.trim();

    if (u.isEmpty || loading) return;

    if (period == ImportPeriod.month && month == null) {
      error = 'اختر الشهر أولًا.';
      notifyListeners();
      return;
    }

    final token = ++_token;

    _cancel = false;
    loading = true;
    error = null;
    username = u;
    items = <LibraryGame>[];
    selected = <String>{};
    progress = 'جارٍ الاتصال بـ Chess.com...';
    notifyListeners();

    try {
      existing = await repo.storage.ids();

      await for (final batch
          in repo.fetchPeriod(u, period, month: month)) {
        if (_cancel || token != _token) break;

        items.addAll([
          for (final g in batch.games) LibraryGame.fromChessCom(g, u),
        ]);

        progress = 'جلب ${batch.month.label} — ${items.length} مباراة';
        notifyListeners();
      }

      await AccountStorage.saveChessComUsername(u);
      syncState = await repo.storage.syncState(u);

      if (items.isEmpty && !_cancel) {
        error = 'لم يتم العثور على مباريات في الفترة المحددة';
      }

      // الجديدة محدّدة افتراضيًا.
      selected = {
        for (final g in items)
          if (!existing.contains(g.id)) g.id,
      };
    } on ChessComException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'حدث خطأ غير متوقع أثناء الاتصال بـ Chess.com.';
    }

    loading = false;
    progress = '';
    notifyListeners();
  }

  bool get allSelected {
    final selectable = items.where((g) => !existing.contains(g.id));

    return selectable.isNotEmpty && selectable.every((g) => selected.contains(g.id));
  }

  void toggleAll(bool on) {
    selected = on
        ? {
            for (final g in items)
              if (!existing.contains(g.id)) g.id,
          }
        : <String>{};
    notifyListeners();
  }

  void toggle(String id) {
    if (existing.contains(id)) return;

    selected.contains(id) ? selected.remove(id) : selected.add(id);
    notifyListeners();
  }

  /// يستورد المحدَّد فقط (المكرر يُتجاهل).
  Future<ImportResult> importSelected() async {
    final chosen = [for (final g in items) if (selected.contains(g.id)) g];

    final r = await repo.saveGames(chosen);

    existing = await repo.storage.ids();
    selected = <String>{};
    notifyListeners();

    return r;
  }

  Future<void> syncNow(String rawUsername) async {
    final u = rawUsername.trim();

    if (u.isEmpty || syncing) return;

    syncing = true;
    syncMessage = null;
    error = null;
    notifyListeners();

    try {
      final r = await repo.sync(u);

      await AccountStorage.saveChessComUsername(u);
      username = u;
      syncState = await repo.storage.syncState(u);
      existing = await repo.storage.ids();
      syncMessage = r.added == 0
          ? 'لا توجد مباريات جديدة'
          : 'أُضيفت ${r.added} مباراة جديدة';
    } on ChessComException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'حدث خطأ غير متوقع أثناء المزامنة.';
    }

    syncing = false;
    notifyListeners();
  }
}
