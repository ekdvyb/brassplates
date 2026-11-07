class SyncMeta {
  const SyncMeta({
    required this.version,
    required this.updatedAt,
    required this.hash,
    this.pending = false,
    this.deleted = false,
  });

  final int version;
  final DateTime updatedAt;
  final String hash;
  final bool pending;
  final bool deleted;

  Map<String, dynamic> toJson() => {
    'version': version,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'hash': hash,
    'deleted': deleted,
  };

  static SyncMeta fromJson(Map<String, dynamic> json, {bool pending = false}) =>
      SyncMeta(
        version: (json['version'] as num?)?.toInt() ?? 1,
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        hash: json['hash'] as String? ?? '',
        deleted: json['deleted'] as bool? ?? false,
        pending: pending,
      );
}

enum SyncAction { none, push, pull, conflict }

class ConflictResolver {
  const ConflictResolver();

  /// Latest write wins. If both sides changed since the last successful sync
  /// (the local row is still pending) the local copy is preserved as a
  /// conflict copy and the remote version is applied.
  SyncAction decide({required SyncMeta local, SyncMeta? remote}) {
    if (remote == null) return SyncAction.push;
    if (local.hash == remote.hash) return SyncAction.none;
    if (local.updatedAt.isAfter(remote.updatedAt)) return SyncAction.push;
    if (local.updatedAt.isBefore(remote.updatedAt)) {
      return local.pending ? SyncAction.conflict : SyncAction.pull;
    }
    return SyncAction.conflict;
  }
}
