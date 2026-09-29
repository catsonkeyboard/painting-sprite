import 'package:shared_preferences/shared_preferences.dart';

/// 家长限流器：每日云端许愿配额（shared_preferences 持久化）。
///
/// 规则：
/// - 每日 0 点重置（按本地日期字符串判断）
/// - [spend] 在云端任务发起时扣 1；[refund] 失败时退还
/// - 配额用尽 → UI 引导用预设按钮（本地动画，零成本）
class WishQuota {
  static const _kDate = 'quota_date';
  static const _kUsed = 'quota_used';
  static const _kLimit = 'quota_limit';

  static const int defaultLimit = 10;

  static Future<SharedPreferences> _prefs() =>
      SharedPreferences.getInstance();

  /// 今日已用 / 上限。
  static Future<(int used, int limit)> status() async {
    final p = await _prefs();
    await _rolloverIfNeeded(p);
    return (p.getInt(_kUsed) ?? 0, p.getInt(_kLimit) ?? defaultLimit);
  }

  static Future<bool> get canWish async {
    final (used, limit) = await status();
    return used < limit;
  }

  /// 扣额度。超额返回 false（调用方引导本地动画）。
  static Future<bool> spend() async {
    final p = await _prefs();
    await _rolloverIfNeeded(p);
    final used = p.getInt(_kUsed) ?? 0;
    final limit = p.getInt(_kLimit) ?? defaultLimit;
    if (used >= limit) return false;
    await p.setInt(_kUsed, used + 1);
    return true;
  }

  /// 云端失败退还（孩子没看到视频就不算钱）。
  static Future<void> refund() async {
    final p = await _prefs();
    await _rolloverIfNeeded(p);
    final used = p.getInt(_kUsed) ?? 0;
    if (used > 0) await p.setInt(_kUsed, used - 1);
  }

  static Future<void> setLimit(int limit) async {
    final p = await _prefs();
    await p.setInt(_kLimit, limit);
  }

  /// 跨天自动清零。
  static Future<void> _rolloverIfNeeded(SharedPreferences p) async {
    final today = _today();
    if (p.getString(_kDate) != today) {
      await p.setString(_kDate, today);
      await p.setInt(_kUsed, 0);
    }
  }

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }
}
