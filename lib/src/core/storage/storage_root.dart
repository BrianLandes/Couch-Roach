/// A configured storage root — one library folder, typically one per disk.
/// [id] is null before the row is persisted; set once it's in the DB.
class StorageRoot {
  const StorageRoot({
    required this.path,
    this.id,
    this.label,
    this.enabled = true,
    this.priority = 0,
  });

  final int? id;
  final String path;
  final String? label;
  final bool enabled;
  final int priority;
}
