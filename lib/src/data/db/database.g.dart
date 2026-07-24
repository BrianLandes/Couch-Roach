// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $LibraryItemsTable extends LibraryItems
    with TableInfo<$LibraryItemsTable, LibraryItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LibraryItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _mediaTypeMeta =
      const VerificationMeta('mediaType');
  @override
  late final GeneratedColumn<String> mediaType = GeneratedColumn<String>(
      'media_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _tmdbIdMeta = const VerificationMeta('tmdbId');
  @override
  late final GeneratedColumn<int> tmdbId = GeneratedColumn<int>(
      'tmdb_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _tmdbNameMeta =
      const VerificationMeta('tmdbName');
  @override
  late final GeneratedColumn<String> tmdbName = GeneratedColumn<String>(
      'tmdb_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _tmdbPosterPathMeta =
      const VerificationMeta('tmdbPosterPath');
  @override
  late final GeneratedColumn<String> tmdbPosterPath = GeneratedColumn<String>(
      'tmdb_poster_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _seasonMeta = const VerificationMeta('season');
  @override
  late final GeneratedColumn<int> season = GeneratedColumn<int>(
      'season', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _episodeMeta =
      const VerificationMeta('episode');
  @override
  late final GeneratedColumn<int> episode = GeneratedColumn<int>(
      'episode', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _filePathMeta =
      const VerificationMeta('filePath');
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
      'file_path', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _containerMeta =
      const VerificationMeta('container');
  @override
  late final GeneratedColumn<String> container = GeneratedColumn<String>(
      'container', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _videoCodecMeta =
      const VerificationMeta('videoCodec');
  @override
  late final GeneratedColumn<String> videoCodec = GeneratedColumn<String>(
      'video_codec', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _audioCodecMeta =
      const VerificationMeta('audioCodec');
  @override
  late final GeneratedColumn<String> audioCodec = GeneratedColumn<String>(
      'audio_codec', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _hasEmbeddedEnSubMeta =
      const VerificationMeta('hasEmbeddedEnSub');
  @override
  late final GeneratedColumn<bool> hasEmbeddedEnSub = GeneratedColumn<bool>(
      'has_embedded_en_sub', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("has_embedded_en_sub" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _subtitleOffsetMsMeta =
      const VerificationMeta('subtitleOffsetMs');
  @override
  late final GeneratedColumn<int> subtitleOffsetMs = GeneratedColumn<int>(
      'subtitle_offset_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _managedMeta =
      const VerificationMeta('managed');
  @override
  late final GeneratedColumn<bool> managed = GeneratedColumn<bool>(
      'managed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("managed" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _keepMeta = const VerificationMeta('keep');
  @override
  late final GeneratedColumn<bool> keep = GeneratedColumn<bool>(
      'keep', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("keep" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _missingMeta =
      const VerificationMeta('missing');
  @override
  late final GeneratedColumn<bool> missing = GeneratedColumn<bool>(
      'missing', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("missing" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _addedAtMeta =
      const VerificationMeta('addedAt');
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
      'added_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        mediaType,
        title,
        tmdbId,
        tmdbName,
        tmdbPosterPath,
        season,
        episode,
        filePath,
        container,
        videoCodec,
        audioCodec,
        hasEmbeddedEnSub,
        subtitleOffsetMs,
        managed,
        keep,
        missing,
        addedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_items';
  @override
  VerificationContext validateIntegrity(Insertable<LibraryItem> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('media_type')) {
      context.handle(_mediaTypeMeta,
          mediaType.isAcceptableOrUnknown(data['media_type']!, _mediaTypeMeta));
    } else if (isInserting) {
      context.missing(_mediaTypeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('tmdb_id')) {
      context.handle(_tmdbIdMeta,
          tmdbId.isAcceptableOrUnknown(data['tmdb_id']!, _tmdbIdMeta));
    }
    if (data.containsKey('tmdb_name')) {
      context.handle(_tmdbNameMeta,
          tmdbName.isAcceptableOrUnknown(data['tmdb_name']!, _tmdbNameMeta));
    }
    if (data.containsKey('tmdb_poster_path')) {
      context.handle(
          _tmdbPosterPathMeta,
          tmdbPosterPath.isAcceptableOrUnknown(
              data['tmdb_poster_path']!, _tmdbPosterPathMeta));
    }
    if (data.containsKey('season')) {
      context.handle(_seasonMeta,
          season.isAcceptableOrUnknown(data['season']!, _seasonMeta));
    }
    if (data.containsKey('episode')) {
      context.handle(_episodeMeta,
          episode.isAcceptableOrUnknown(data['episode']!, _episodeMeta));
    }
    if (data.containsKey('file_path')) {
      context.handle(_filePathMeta,
          filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta));
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('container')) {
      context.handle(_containerMeta,
          container.isAcceptableOrUnknown(data['container']!, _containerMeta));
    }
    if (data.containsKey('video_codec')) {
      context.handle(
          _videoCodecMeta,
          videoCodec.isAcceptableOrUnknown(
              data['video_codec']!, _videoCodecMeta));
    }
    if (data.containsKey('audio_codec')) {
      context.handle(
          _audioCodecMeta,
          audioCodec.isAcceptableOrUnknown(
              data['audio_codec']!, _audioCodecMeta));
    }
    if (data.containsKey('has_embedded_en_sub')) {
      context.handle(
          _hasEmbeddedEnSubMeta,
          hasEmbeddedEnSub.isAcceptableOrUnknown(
              data['has_embedded_en_sub']!, _hasEmbeddedEnSubMeta));
    }
    if (data.containsKey('subtitle_offset_ms')) {
      context.handle(
          _subtitleOffsetMsMeta,
          subtitleOffsetMs.isAcceptableOrUnknown(
              data['subtitle_offset_ms']!, _subtitleOffsetMsMeta));
    }
    if (data.containsKey('managed')) {
      context.handle(_managedMeta,
          managed.isAcceptableOrUnknown(data['managed']!, _managedMeta));
    }
    if (data.containsKey('keep')) {
      context.handle(
          _keepMeta, keep.isAcceptableOrUnknown(data['keep']!, _keepMeta));
    }
    if (data.containsKey('missing')) {
      context.handle(_missingMeta,
          missing.isAcceptableOrUnknown(data['missing']!, _missingMeta));
    }
    if (data.containsKey('added_at')) {
      context.handle(_addedAtMeta,
          addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LibraryItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LibraryItem(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      mediaType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}media_type'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      tmdbId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}tmdb_id']),
      tmdbName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tmdb_name']),
      tmdbPosterPath: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}tmdb_poster_path']),
      season: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}season']),
      episode: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}episode']),
      filePath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_path'])!,
      container: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}container']),
      videoCodec: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}video_codec']),
      audioCodec: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}audio_codec']),
      hasEmbeddedEnSub: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}has_embedded_en_sub'])!,
      subtitleOffsetMs: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}subtitle_offset_ms'])!,
      managed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}managed'])!,
      keep: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}keep'])!,
      missing: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}missing'])!,
      addedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}added_at'])!,
    );
  }

  @override
  $LibraryItemsTable createAlias(String alias) {
    return $LibraryItemsTable(attachedDatabase, alias);
  }
}

class LibraryItem extends DataClass implements Insertable<LibraryItem> {
  final int id;

  /// 'tv' or 'movie'.
  final String mediaType;
  final String title;
  final int? tmdbId;

  /// TMDB metadata cached on the row after matching (M2): the canonical title and
  /// poster path (build the URL with TmdbImages). Null until matched.
  final String? tmdbName;
  final String? tmdbPosterPath;
  final int? season;
  final int? episode;
  final String filePath;
  final String? container;
  final String? videoCodec;
  final String? audioCodec;
  final bool hasEmbeddedEnSub;

  /// User-set subtitle timing offset for this title, in milliseconds, applied
  /// as mpv's `sub-delay` during playback (positive delays the subtitles).
  /// Persisted per file so a re-watch keeps the correction; 0 means in sync.
  final int subtitleOffsetMs;

  /// Provenance: true when the app acquired this file (torrent), false when it
  /// was already sitting in a library folder. Informational — cleanup eligibility
  /// is driven by library-folder membership + [keep], not this flag.
  final bool managed;

  /// User-pinned "keep around": exempt from auto-cleanup even after a full
  /// watch (e.g. a movie to rewatch). Everything in the library folders is
  /// otherwise fair game to hydrate and then reap (see DECISIONS: auto-cleanup).
  final bool keep;

  /// Set when a scan no longer finds the file on disk (deleted, or its disk is
  /// offline). Flagged rather than deleted so watch history / keep survive a
  /// transient disappearance (e.g. an unplugged disk); the reaper is the only
  /// hard-deleter.
  final bool missing;
  final DateTime addedAt;
  const LibraryItem(
      {required this.id,
      required this.mediaType,
      required this.title,
      this.tmdbId,
      this.tmdbName,
      this.tmdbPosterPath,
      this.season,
      this.episode,
      required this.filePath,
      this.container,
      this.videoCodec,
      this.audioCodec,
      required this.hasEmbeddedEnSub,
      required this.subtitleOffsetMs,
      required this.managed,
      required this.keep,
      required this.missing,
      required this.addedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['media_type'] = Variable<String>(mediaType);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || tmdbId != null) {
      map['tmdb_id'] = Variable<int>(tmdbId);
    }
    if (!nullToAbsent || tmdbName != null) {
      map['tmdb_name'] = Variable<String>(tmdbName);
    }
    if (!nullToAbsent || tmdbPosterPath != null) {
      map['tmdb_poster_path'] = Variable<String>(tmdbPosterPath);
    }
    if (!nullToAbsent || season != null) {
      map['season'] = Variable<int>(season);
    }
    if (!nullToAbsent || episode != null) {
      map['episode'] = Variable<int>(episode);
    }
    map['file_path'] = Variable<String>(filePath);
    if (!nullToAbsent || container != null) {
      map['container'] = Variable<String>(container);
    }
    if (!nullToAbsent || videoCodec != null) {
      map['video_codec'] = Variable<String>(videoCodec);
    }
    if (!nullToAbsent || audioCodec != null) {
      map['audio_codec'] = Variable<String>(audioCodec);
    }
    map['has_embedded_en_sub'] = Variable<bool>(hasEmbeddedEnSub);
    map['subtitle_offset_ms'] = Variable<int>(subtitleOffsetMs);
    map['managed'] = Variable<bool>(managed);
    map['keep'] = Variable<bool>(keep);
    map['missing'] = Variable<bool>(missing);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  LibraryItemsCompanion toCompanion(bool nullToAbsent) {
    return LibraryItemsCompanion(
      id: Value(id),
      mediaType: Value(mediaType),
      title: Value(title),
      tmdbId:
          tmdbId == null && nullToAbsent ? const Value.absent() : Value(tmdbId),
      tmdbName: tmdbName == null && nullToAbsent
          ? const Value.absent()
          : Value(tmdbName),
      tmdbPosterPath: tmdbPosterPath == null && nullToAbsent
          ? const Value.absent()
          : Value(tmdbPosterPath),
      season:
          season == null && nullToAbsent ? const Value.absent() : Value(season),
      episode: episode == null && nullToAbsent
          ? const Value.absent()
          : Value(episode),
      filePath: Value(filePath),
      container: container == null && nullToAbsent
          ? const Value.absent()
          : Value(container),
      videoCodec: videoCodec == null && nullToAbsent
          ? const Value.absent()
          : Value(videoCodec),
      audioCodec: audioCodec == null && nullToAbsent
          ? const Value.absent()
          : Value(audioCodec),
      hasEmbeddedEnSub: Value(hasEmbeddedEnSub),
      subtitleOffsetMs: Value(subtitleOffsetMs),
      managed: Value(managed),
      keep: Value(keep),
      missing: Value(missing),
      addedAt: Value(addedAt),
    );
  }

  factory LibraryItem.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LibraryItem(
      id: serializer.fromJson<int>(json['id']),
      mediaType: serializer.fromJson<String>(json['mediaType']),
      title: serializer.fromJson<String>(json['title']),
      tmdbId: serializer.fromJson<int?>(json['tmdbId']),
      tmdbName: serializer.fromJson<String?>(json['tmdbName']),
      tmdbPosterPath: serializer.fromJson<String?>(json['tmdbPosterPath']),
      season: serializer.fromJson<int?>(json['season']),
      episode: serializer.fromJson<int?>(json['episode']),
      filePath: serializer.fromJson<String>(json['filePath']),
      container: serializer.fromJson<String?>(json['container']),
      videoCodec: serializer.fromJson<String?>(json['videoCodec']),
      audioCodec: serializer.fromJson<String?>(json['audioCodec']),
      hasEmbeddedEnSub: serializer.fromJson<bool>(json['hasEmbeddedEnSub']),
      subtitleOffsetMs: serializer.fromJson<int>(json['subtitleOffsetMs']),
      managed: serializer.fromJson<bool>(json['managed']),
      keep: serializer.fromJson<bool>(json['keep']),
      missing: serializer.fromJson<bool>(json['missing']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'mediaType': serializer.toJson<String>(mediaType),
      'title': serializer.toJson<String>(title),
      'tmdbId': serializer.toJson<int?>(tmdbId),
      'tmdbName': serializer.toJson<String?>(tmdbName),
      'tmdbPosterPath': serializer.toJson<String?>(tmdbPosterPath),
      'season': serializer.toJson<int?>(season),
      'episode': serializer.toJson<int?>(episode),
      'filePath': serializer.toJson<String>(filePath),
      'container': serializer.toJson<String?>(container),
      'videoCodec': serializer.toJson<String?>(videoCodec),
      'audioCodec': serializer.toJson<String?>(audioCodec),
      'hasEmbeddedEnSub': serializer.toJson<bool>(hasEmbeddedEnSub),
      'subtitleOffsetMs': serializer.toJson<int>(subtitleOffsetMs),
      'managed': serializer.toJson<bool>(managed),
      'keep': serializer.toJson<bool>(keep),
      'missing': serializer.toJson<bool>(missing),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  LibraryItem copyWith(
          {int? id,
          String? mediaType,
          String? title,
          Value<int?> tmdbId = const Value.absent(),
          Value<String?> tmdbName = const Value.absent(),
          Value<String?> tmdbPosterPath = const Value.absent(),
          Value<int?> season = const Value.absent(),
          Value<int?> episode = const Value.absent(),
          String? filePath,
          Value<String?> container = const Value.absent(),
          Value<String?> videoCodec = const Value.absent(),
          Value<String?> audioCodec = const Value.absent(),
          bool? hasEmbeddedEnSub,
          int? subtitleOffsetMs,
          bool? managed,
          bool? keep,
          bool? missing,
          DateTime? addedAt}) =>
      LibraryItem(
        id: id ?? this.id,
        mediaType: mediaType ?? this.mediaType,
        title: title ?? this.title,
        tmdbId: tmdbId.present ? tmdbId.value : this.tmdbId,
        tmdbName: tmdbName.present ? tmdbName.value : this.tmdbName,
        tmdbPosterPath:
            tmdbPosterPath.present ? tmdbPosterPath.value : this.tmdbPosterPath,
        season: season.present ? season.value : this.season,
        episode: episode.present ? episode.value : this.episode,
        filePath: filePath ?? this.filePath,
        container: container.present ? container.value : this.container,
        videoCodec: videoCodec.present ? videoCodec.value : this.videoCodec,
        audioCodec: audioCodec.present ? audioCodec.value : this.audioCodec,
        hasEmbeddedEnSub: hasEmbeddedEnSub ?? this.hasEmbeddedEnSub,
        subtitleOffsetMs: subtitleOffsetMs ?? this.subtitleOffsetMs,
        managed: managed ?? this.managed,
        keep: keep ?? this.keep,
        missing: missing ?? this.missing,
        addedAt: addedAt ?? this.addedAt,
      );
  LibraryItem copyWithCompanion(LibraryItemsCompanion data) {
    return LibraryItem(
      id: data.id.present ? data.id.value : this.id,
      mediaType: data.mediaType.present ? data.mediaType.value : this.mediaType,
      title: data.title.present ? data.title.value : this.title,
      tmdbId: data.tmdbId.present ? data.tmdbId.value : this.tmdbId,
      tmdbName: data.tmdbName.present ? data.tmdbName.value : this.tmdbName,
      tmdbPosterPath: data.tmdbPosterPath.present
          ? data.tmdbPosterPath.value
          : this.tmdbPosterPath,
      season: data.season.present ? data.season.value : this.season,
      episode: data.episode.present ? data.episode.value : this.episode,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      container: data.container.present ? data.container.value : this.container,
      videoCodec:
          data.videoCodec.present ? data.videoCodec.value : this.videoCodec,
      audioCodec:
          data.audioCodec.present ? data.audioCodec.value : this.audioCodec,
      hasEmbeddedEnSub: data.hasEmbeddedEnSub.present
          ? data.hasEmbeddedEnSub.value
          : this.hasEmbeddedEnSub,
      subtitleOffsetMs: data.subtitleOffsetMs.present
          ? data.subtitleOffsetMs.value
          : this.subtitleOffsetMs,
      managed: data.managed.present ? data.managed.value : this.managed,
      keep: data.keep.present ? data.keep.value : this.keep,
      missing: data.missing.present ? data.missing.value : this.missing,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LibraryItem(')
          ..write('id: $id, ')
          ..write('mediaType: $mediaType, ')
          ..write('title: $title, ')
          ..write('tmdbId: $tmdbId, ')
          ..write('tmdbName: $tmdbName, ')
          ..write('tmdbPosterPath: $tmdbPosterPath, ')
          ..write('season: $season, ')
          ..write('episode: $episode, ')
          ..write('filePath: $filePath, ')
          ..write('container: $container, ')
          ..write('videoCodec: $videoCodec, ')
          ..write('audioCodec: $audioCodec, ')
          ..write('hasEmbeddedEnSub: $hasEmbeddedEnSub, ')
          ..write('subtitleOffsetMs: $subtitleOffsetMs, ')
          ..write('managed: $managed, ')
          ..write('keep: $keep, ')
          ..write('missing: $missing, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      mediaType,
      title,
      tmdbId,
      tmdbName,
      tmdbPosterPath,
      season,
      episode,
      filePath,
      container,
      videoCodec,
      audioCodec,
      hasEmbeddedEnSub,
      subtitleOffsetMs,
      managed,
      keep,
      missing,
      addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LibraryItem &&
          other.id == this.id &&
          other.mediaType == this.mediaType &&
          other.title == this.title &&
          other.tmdbId == this.tmdbId &&
          other.tmdbName == this.tmdbName &&
          other.tmdbPosterPath == this.tmdbPosterPath &&
          other.season == this.season &&
          other.episode == this.episode &&
          other.filePath == this.filePath &&
          other.container == this.container &&
          other.videoCodec == this.videoCodec &&
          other.audioCodec == this.audioCodec &&
          other.hasEmbeddedEnSub == this.hasEmbeddedEnSub &&
          other.subtitleOffsetMs == this.subtitleOffsetMs &&
          other.managed == this.managed &&
          other.keep == this.keep &&
          other.missing == this.missing &&
          other.addedAt == this.addedAt);
}

class LibraryItemsCompanion extends UpdateCompanion<LibraryItem> {
  final Value<int> id;
  final Value<String> mediaType;
  final Value<String> title;
  final Value<int?> tmdbId;
  final Value<String?> tmdbName;
  final Value<String?> tmdbPosterPath;
  final Value<int?> season;
  final Value<int?> episode;
  final Value<String> filePath;
  final Value<String?> container;
  final Value<String?> videoCodec;
  final Value<String?> audioCodec;
  final Value<bool> hasEmbeddedEnSub;
  final Value<int> subtitleOffsetMs;
  final Value<bool> managed;
  final Value<bool> keep;
  final Value<bool> missing;
  final Value<DateTime> addedAt;
  const LibraryItemsCompanion({
    this.id = const Value.absent(),
    this.mediaType = const Value.absent(),
    this.title = const Value.absent(),
    this.tmdbId = const Value.absent(),
    this.tmdbName = const Value.absent(),
    this.tmdbPosterPath = const Value.absent(),
    this.season = const Value.absent(),
    this.episode = const Value.absent(),
    this.filePath = const Value.absent(),
    this.container = const Value.absent(),
    this.videoCodec = const Value.absent(),
    this.audioCodec = const Value.absent(),
    this.hasEmbeddedEnSub = const Value.absent(),
    this.subtitleOffsetMs = const Value.absent(),
    this.managed = const Value.absent(),
    this.keep = const Value.absent(),
    this.missing = const Value.absent(),
    this.addedAt = const Value.absent(),
  });
  LibraryItemsCompanion.insert({
    this.id = const Value.absent(),
    required String mediaType,
    required String title,
    this.tmdbId = const Value.absent(),
    this.tmdbName = const Value.absent(),
    this.tmdbPosterPath = const Value.absent(),
    this.season = const Value.absent(),
    this.episode = const Value.absent(),
    required String filePath,
    this.container = const Value.absent(),
    this.videoCodec = const Value.absent(),
    this.audioCodec = const Value.absent(),
    this.hasEmbeddedEnSub = const Value.absent(),
    this.subtitleOffsetMs = const Value.absent(),
    this.managed = const Value.absent(),
    this.keep = const Value.absent(),
    this.missing = const Value.absent(),
    this.addedAt = const Value.absent(),
  })  : mediaType = Value(mediaType),
        title = Value(title),
        filePath = Value(filePath);
  static Insertable<LibraryItem> custom({
    Expression<int>? id,
    Expression<String>? mediaType,
    Expression<String>? title,
    Expression<int>? tmdbId,
    Expression<String>? tmdbName,
    Expression<String>? tmdbPosterPath,
    Expression<int>? season,
    Expression<int>? episode,
    Expression<String>? filePath,
    Expression<String>? container,
    Expression<String>? videoCodec,
    Expression<String>? audioCodec,
    Expression<bool>? hasEmbeddedEnSub,
    Expression<int>? subtitleOffsetMs,
    Expression<bool>? managed,
    Expression<bool>? keep,
    Expression<bool>? missing,
    Expression<DateTime>? addedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mediaType != null) 'media_type': mediaType,
      if (title != null) 'title': title,
      if (tmdbId != null) 'tmdb_id': tmdbId,
      if (tmdbName != null) 'tmdb_name': tmdbName,
      if (tmdbPosterPath != null) 'tmdb_poster_path': tmdbPosterPath,
      if (season != null) 'season': season,
      if (episode != null) 'episode': episode,
      if (filePath != null) 'file_path': filePath,
      if (container != null) 'container': container,
      if (videoCodec != null) 'video_codec': videoCodec,
      if (audioCodec != null) 'audio_codec': audioCodec,
      if (hasEmbeddedEnSub != null) 'has_embedded_en_sub': hasEmbeddedEnSub,
      if (subtitleOffsetMs != null) 'subtitle_offset_ms': subtitleOffsetMs,
      if (managed != null) 'managed': managed,
      if (keep != null) 'keep': keep,
      if (missing != null) 'missing': missing,
      if (addedAt != null) 'added_at': addedAt,
    });
  }

  LibraryItemsCompanion copyWith(
      {Value<int>? id,
      Value<String>? mediaType,
      Value<String>? title,
      Value<int?>? tmdbId,
      Value<String?>? tmdbName,
      Value<String?>? tmdbPosterPath,
      Value<int?>? season,
      Value<int?>? episode,
      Value<String>? filePath,
      Value<String?>? container,
      Value<String?>? videoCodec,
      Value<String?>? audioCodec,
      Value<bool>? hasEmbeddedEnSub,
      Value<int>? subtitleOffsetMs,
      Value<bool>? managed,
      Value<bool>? keep,
      Value<bool>? missing,
      Value<DateTime>? addedAt}) {
    return LibraryItemsCompanion(
      id: id ?? this.id,
      mediaType: mediaType ?? this.mediaType,
      title: title ?? this.title,
      tmdbId: tmdbId ?? this.tmdbId,
      tmdbName: tmdbName ?? this.tmdbName,
      tmdbPosterPath: tmdbPosterPath ?? this.tmdbPosterPath,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      filePath: filePath ?? this.filePath,
      container: container ?? this.container,
      videoCodec: videoCodec ?? this.videoCodec,
      audioCodec: audioCodec ?? this.audioCodec,
      hasEmbeddedEnSub: hasEmbeddedEnSub ?? this.hasEmbeddedEnSub,
      subtitleOffsetMs: subtitleOffsetMs ?? this.subtitleOffsetMs,
      managed: managed ?? this.managed,
      keep: keep ?? this.keep,
      missing: missing ?? this.missing,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (mediaType.present) {
      map['media_type'] = Variable<String>(mediaType.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (tmdbId.present) {
      map['tmdb_id'] = Variable<int>(tmdbId.value);
    }
    if (tmdbName.present) {
      map['tmdb_name'] = Variable<String>(tmdbName.value);
    }
    if (tmdbPosterPath.present) {
      map['tmdb_poster_path'] = Variable<String>(tmdbPosterPath.value);
    }
    if (season.present) {
      map['season'] = Variable<int>(season.value);
    }
    if (episode.present) {
      map['episode'] = Variable<int>(episode.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (container.present) {
      map['container'] = Variable<String>(container.value);
    }
    if (videoCodec.present) {
      map['video_codec'] = Variable<String>(videoCodec.value);
    }
    if (audioCodec.present) {
      map['audio_codec'] = Variable<String>(audioCodec.value);
    }
    if (hasEmbeddedEnSub.present) {
      map['has_embedded_en_sub'] = Variable<bool>(hasEmbeddedEnSub.value);
    }
    if (subtitleOffsetMs.present) {
      map['subtitle_offset_ms'] = Variable<int>(subtitleOffsetMs.value);
    }
    if (managed.present) {
      map['managed'] = Variable<bool>(managed.value);
    }
    if (keep.present) {
      map['keep'] = Variable<bool>(keep.value);
    }
    if (missing.present) {
      map['missing'] = Variable<bool>(missing.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LibraryItemsCompanion(')
          ..write('id: $id, ')
          ..write('mediaType: $mediaType, ')
          ..write('title: $title, ')
          ..write('tmdbId: $tmdbId, ')
          ..write('tmdbName: $tmdbName, ')
          ..write('tmdbPosterPath: $tmdbPosterPath, ')
          ..write('season: $season, ')
          ..write('episode: $episode, ')
          ..write('filePath: $filePath, ')
          ..write('container: $container, ')
          ..write('videoCodec: $videoCodec, ')
          ..write('audioCodec: $audioCodec, ')
          ..write('hasEmbeddedEnSub: $hasEmbeddedEnSub, ')
          ..write('subtitleOffsetMs: $subtitleOffsetMs, ')
          ..write('managed: $managed, ')
          ..write('keep: $keep, ')
          ..write('missing: $missing, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }
}

class $WatchHistoryTable extends WatchHistory
    with TableInfo<$WatchHistoryTable, WatchHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WatchHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _libraryItemIdMeta =
      const VerificationMeta('libraryItemId');
  @override
  late final GeneratedColumn<int> libraryItemId = GeneratedColumn<int>(
      'library_item_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES library_items (id) ON DELETE CASCADE'));
  static const VerificationMeta _resumePositionSecMeta =
      const VerificationMeta('resumePositionSec');
  @override
  late final GeneratedColumn<int> resumePositionSec = GeneratedColumn<int>(
      'resume_position_sec', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _durationSecMeta =
      const VerificationMeta('durationSec');
  @override
  late final GeneratedColumn<int> durationSec = GeneratedColumn<int>(
      'duration_sec', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _completedMeta =
      const VerificationMeta('completed');
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
      'completed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("completed" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _lastWatchedAtMeta =
      const VerificationMeta('lastWatchedAt');
  @override
  late final GeneratedColumn<DateTime> lastWatchedAt =
      GeneratedColumn<DateTime>('last_watched_at', aliasedName, false,
          type: DriftSqlType.dateTime,
          requiredDuringInsert: false,
          defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        libraryItemId,
        resumePositionSec,
        durationSec,
        completed,
        lastWatchedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'watch_history';
  @override
  VerificationContext validateIntegrity(Insertable<WatchHistoryData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('library_item_id')) {
      context.handle(
          _libraryItemIdMeta,
          libraryItemId.isAcceptableOrUnknown(
              data['library_item_id']!, _libraryItemIdMeta));
    } else if (isInserting) {
      context.missing(_libraryItemIdMeta);
    }
    if (data.containsKey('resume_position_sec')) {
      context.handle(
          _resumePositionSecMeta,
          resumePositionSec.isAcceptableOrUnknown(
              data['resume_position_sec']!, _resumePositionSecMeta));
    }
    if (data.containsKey('duration_sec')) {
      context.handle(
          _durationSecMeta,
          durationSec.isAcceptableOrUnknown(
              data['duration_sec']!, _durationSecMeta));
    }
    if (data.containsKey('completed')) {
      context.handle(_completedMeta,
          completed.isAcceptableOrUnknown(data['completed']!, _completedMeta));
    }
    if (data.containsKey('last_watched_at')) {
      context.handle(
          _lastWatchedAtMeta,
          lastWatchedAt.isAcceptableOrUnknown(
              data['last_watched_at']!, _lastWatchedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WatchHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WatchHistoryData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      libraryItemId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}library_item_id'])!,
      resumePositionSec: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}resume_position_sec'])!,
      durationSec: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_sec']),
      completed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}completed'])!,
      lastWatchedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_watched_at'])!,
    );
  }

  @override
  $WatchHistoryTable createAlias(String alias) {
    return $WatchHistoryTable(attachedDatabase, alias);
  }
}

class WatchHistoryData extends DataClass
    implements Insertable<WatchHistoryData> {
  final int id;
  final int libraryItemId;
  final int resumePositionSec;
  final int? durationSec;
  final bool completed;
  final DateTime lastWatchedAt;
  const WatchHistoryData(
      {required this.id,
      required this.libraryItemId,
      required this.resumePositionSec,
      this.durationSec,
      required this.completed,
      required this.lastWatchedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['library_item_id'] = Variable<int>(libraryItemId);
    map['resume_position_sec'] = Variable<int>(resumePositionSec);
    if (!nullToAbsent || durationSec != null) {
      map['duration_sec'] = Variable<int>(durationSec);
    }
    map['completed'] = Variable<bool>(completed);
    map['last_watched_at'] = Variable<DateTime>(lastWatchedAt);
    return map;
  }

  WatchHistoryCompanion toCompanion(bool nullToAbsent) {
    return WatchHistoryCompanion(
      id: Value(id),
      libraryItemId: Value(libraryItemId),
      resumePositionSec: Value(resumePositionSec),
      durationSec: durationSec == null && nullToAbsent
          ? const Value.absent()
          : Value(durationSec),
      completed: Value(completed),
      lastWatchedAt: Value(lastWatchedAt),
    );
  }

  factory WatchHistoryData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WatchHistoryData(
      id: serializer.fromJson<int>(json['id']),
      libraryItemId: serializer.fromJson<int>(json['libraryItemId']),
      resumePositionSec: serializer.fromJson<int>(json['resumePositionSec']),
      durationSec: serializer.fromJson<int?>(json['durationSec']),
      completed: serializer.fromJson<bool>(json['completed']),
      lastWatchedAt: serializer.fromJson<DateTime>(json['lastWatchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'libraryItemId': serializer.toJson<int>(libraryItemId),
      'resumePositionSec': serializer.toJson<int>(resumePositionSec),
      'durationSec': serializer.toJson<int?>(durationSec),
      'completed': serializer.toJson<bool>(completed),
      'lastWatchedAt': serializer.toJson<DateTime>(lastWatchedAt),
    };
  }

  WatchHistoryData copyWith(
          {int? id,
          int? libraryItemId,
          int? resumePositionSec,
          Value<int?> durationSec = const Value.absent(),
          bool? completed,
          DateTime? lastWatchedAt}) =>
      WatchHistoryData(
        id: id ?? this.id,
        libraryItemId: libraryItemId ?? this.libraryItemId,
        resumePositionSec: resumePositionSec ?? this.resumePositionSec,
        durationSec: durationSec.present ? durationSec.value : this.durationSec,
        completed: completed ?? this.completed,
        lastWatchedAt: lastWatchedAt ?? this.lastWatchedAt,
      );
  WatchHistoryData copyWithCompanion(WatchHistoryCompanion data) {
    return WatchHistoryData(
      id: data.id.present ? data.id.value : this.id,
      libraryItemId: data.libraryItemId.present
          ? data.libraryItemId.value
          : this.libraryItemId,
      resumePositionSec: data.resumePositionSec.present
          ? data.resumePositionSec.value
          : this.resumePositionSec,
      durationSec:
          data.durationSec.present ? data.durationSec.value : this.durationSec,
      completed: data.completed.present ? data.completed.value : this.completed,
      lastWatchedAt: data.lastWatchedAt.present
          ? data.lastWatchedAt.value
          : this.lastWatchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WatchHistoryData(')
          ..write('id: $id, ')
          ..write('libraryItemId: $libraryItemId, ')
          ..write('resumePositionSec: $resumePositionSec, ')
          ..write('durationSec: $durationSec, ')
          ..write('completed: $completed, ')
          ..write('lastWatchedAt: $lastWatchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, libraryItemId, resumePositionSec,
      durationSec, completed, lastWatchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WatchHistoryData &&
          other.id == this.id &&
          other.libraryItemId == this.libraryItemId &&
          other.resumePositionSec == this.resumePositionSec &&
          other.durationSec == this.durationSec &&
          other.completed == this.completed &&
          other.lastWatchedAt == this.lastWatchedAt);
}

class WatchHistoryCompanion extends UpdateCompanion<WatchHistoryData> {
  final Value<int> id;
  final Value<int> libraryItemId;
  final Value<int> resumePositionSec;
  final Value<int?> durationSec;
  final Value<bool> completed;
  final Value<DateTime> lastWatchedAt;
  const WatchHistoryCompanion({
    this.id = const Value.absent(),
    this.libraryItemId = const Value.absent(),
    this.resumePositionSec = const Value.absent(),
    this.durationSec = const Value.absent(),
    this.completed = const Value.absent(),
    this.lastWatchedAt = const Value.absent(),
  });
  WatchHistoryCompanion.insert({
    this.id = const Value.absent(),
    required int libraryItemId,
    this.resumePositionSec = const Value.absent(),
    this.durationSec = const Value.absent(),
    this.completed = const Value.absent(),
    this.lastWatchedAt = const Value.absent(),
  }) : libraryItemId = Value(libraryItemId);
  static Insertable<WatchHistoryData> custom({
    Expression<int>? id,
    Expression<int>? libraryItemId,
    Expression<int>? resumePositionSec,
    Expression<int>? durationSec,
    Expression<bool>? completed,
    Expression<DateTime>? lastWatchedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (libraryItemId != null) 'library_item_id': libraryItemId,
      if (resumePositionSec != null) 'resume_position_sec': resumePositionSec,
      if (durationSec != null) 'duration_sec': durationSec,
      if (completed != null) 'completed': completed,
      if (lastWatchedAt != null) 'last_watched_at': lastWatchedAt,
    });
  }

  WatchHistoryCompanion copyWith(
      {Value<int>? id,
      Value<int>? libraryItemId,
      Value<int>? resumePositionSec,
      Value<int?>? durationSec,
      Value<bool>? completed,
      Value<DateTime>? lastWatchedAt}) {
    return WatchHistoryCompanion(
      id: id ?? this.id,
      libraryItemId: libraryItemId ?? this.libraryItemId,
      resumePositionSec: resumePositionSec ?? this.resumePositionSec,
      durationSec: durationSec ?? this.durationSec,
      completed: completed ?? this.completed,
      lastWatchedAt: lastWatchedAt ?? this.lastWatchedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (libraryItemId.present) {
      map['library_item_id'] = Variable<int>(libraryItemId.value);
    }
    if (resumePositionSec.present) {
      map['resume_position_sec'] = Variable<int>(resumePositionSec.value);
    }
    if (durationSec.present) {
      map['duration_sec'] = Variable<int>(durationSec.value);
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    if (lastWatchedAt.present) {
      map['last_watched_at'] = Variable<DateTime>(lastWatchedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WatchHistoryCompanion(')
          ..write('id: $id, ')
          ..write('libraryItemId: $libraryItemId, ')
          ..write('resumePositionSec: $resumePositionSec, ')
          ..write('durationSec: $durationSec, ')
          ..write('completed: $completed, ')
          ..write('lastWatchedAt: $lastWatchedAt')
          ..write(')'))
        .toString();
  }
}

class $SubtitleAttemptsTable extends SubtitleAttempts
    with TableInfo<$SubtitleAttemptsTable, SubtitleAttempt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SubtitleAttemptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _libraryItemIdMeta =
      const VerificationMeta('libraryItemId');
  @override
  late final GeneratedColumn<int> libraryItemId = GeneratedColumn<int>(
      'library_item_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES library_items (id) ON DELETE CASCADE'));
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _attemptedAtMeta =
      const VerificationMeta('attemptedAt');
  @override
  late final GeneratedColumn<DateTime> attemptedAt = GeneratedColumn<DateTime>(
      'attempted_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, libraryItemId, status, attemptedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'subtitle_attempts';
  @override
  VerificationContext validateIntegrity(Insertable<SubtitleAttempt> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('library_item_id')) {
      context.handle(
          _libraryItemIdMeta,
          libraryItemId.isAcceptableOrUnknown(
              data['library_item_id']!, _libraryItemIdMeta));
    } else if (isInserting) {
      context.missing(_libraryItemIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('attempted_at')) {
      context.handle(
          _attemptedAtMeta,
          attemptedAt.isAcceptableOrUnknown(
              data['attempted_at']!, _attemptedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SubtitleAttempt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SubtitleAttempt(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      libraryItemId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}library_item_id'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      attemptedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}attempted_at'])!,
    );
  }

  @override
  $SubtitleAttemptsTable createAlias(String alias) {
    return $SubtitleAttemptsTable(attachedDatabase, alias);
  }
}

class SubtitleAttempt extends DataClass implements Insertable<SubtitleAttempt> {
  final int id;
  final int libraryItemId;

  /// 'pending' | 'found' | 'not_found' | 'quota' | 'error'
  final String status;
  final DateTime attemptedAt;
  const SubtitleAttempt(
      {required this.id,
      required this.libraryItemId,
      required this.status,
      required this.attemptedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['library_item_id'] = Variable<int>(libraryItemId);
    map['status'] = Variable<String>(status);
    map['attempted_at'] = Variable<DateTime>(attemptedAt);
    return map;
  }

  SubtitleAttemptsCompanion toCompanion(bool nullToAbsent) {
    return SubtitleAttemptsCompanion(
      id: Value(id),
      libraryItemId: Value(libraryItemId),
      status: Value(status),
      attemptedAt: Value(attemptedAt),
    );
  }

  factory SubtitleAttempt.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SubtitleAttempt(
      id: serializer.fromJson<int>(json['id']),
      libraryItemId: serializer.fromJson<int>(json['libraryItemId']),
      status: serializer.fromJson<String>(json['status']),
      attemptedAt: serializer.fromJson<DateTime>(json['attemptedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'libraryItemId': serializer.toJson<int>(libraryItemId),
      'status': serializer.toJson<String>(status),
      'attemptedAt': serializer.toJson<DateTime>(attemptedAt),
    };
  }

  SubtitleAttempt copyWith(
          {int? id,
          int? libraryItemId,
          String? status,
          DateTime? attemptedAt}) =>
      SubtitleAttempt(
        id: id ?? this.id,
        libraryItemId: libraryItemId ?? this.libraryItemId,
        status: status ?? this.status,
        attemptedAt: attemptedAt ?? this.attemptedAt,
      );
  SubtitleAttempt copyWithCompanion(SubtitleAttemptsCompanion data) {
    return SubtitleAttempt(
      id: data.id.present ? data.id.value : this.id,
      libraryItemId: data.libraryItemId.present
          ? data.libraryItemId.value
          : this.libraryItemId,
      status: data.status.present ? data.status.value : this.status,
      attemptedAt:
          data.attemptedAt.present ? data.attemptedAt.value : this.attemptedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SubtitleAttempt(')
          ..write('id: $id, ')
          ..write('libraryItemId: $libraryItemId, ')
          ..write('status: $status, ')
          ..write('attemptedAt: $attemptedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, libraryItemId, status, attemptedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SubtitleAttempt &&
          other.id == this.id &&
          other.libraryItemId == this.libraryItemId &&
          other.status == this.status &&
          other.attemptedAt == this.attemptedAt);
}

class SubtitleAttemptsCompanion extends UpdateCompanion<SubtitleAttempt> {
  final Value<int> id;
  final Value<int> libraryItemId;
  final Value<String> status;
  final Value<DateTime> attemptedAt;
  const SubtitleAttemptsCompanion({
    this.id = const Value.absent(),
    this.libraryItemId = const Value.absent(),
    this.status = const Value.absent(),
    this.attemptedAt = const Value.absent(),
  });
  SubtitleAttemptsCompanion.insert({
    this.id = const Value.absent(),
    required int libraryItemId,
    required String status,
    this.attemptedAt = const Value.absent(),
  })  : libraryItemId = Value(libraryItemId),
        status = Value(status);
  static Insertable<SubtitleAttempt> custom({
    Expression<int>? id,
    Expression<int>? libraryItemId,
    Expression<String>? status,
    Expression<DateTime>? attemptedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (libraryItemId != null) 'library_item_id': libraryItemId,
      if (status != null) 'status': status,
      if (attemptedAt != null) 'attempted_at': attemptedAt,
    });
  }

  SubtitleAttemptsCompanion copyWith(
      {Value<int>? id,
      Value<int>? libraryItemId,
      Value<String>? status,
      Value<DateTime>? attemptedAt}) {
    return SubtitleAttemptsCompanion(
      id: id ?? this.id,
      libraryItemId: libraryItemId ?? this.libraryItemId,
      status: status ?? this.status,
      attemptedAt: attemptedAt ?? this.attemptedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (libraryItemId.present) {
      map['library_item_id'] = Variable<int>(libraryItemId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (attemptedAt.present) {
      map['attempted_at'] = Variable<DateTime>(attemptedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SubtitleAttemptsCompanion(')
          ..write('id: $id, ')
          ..write('libraryItemId: $libraryItemId, ')
          ..write('status: $status, ')
          ..write('attemptedAt: $attemptedAt')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(Insertable<Setting> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final String key;
  final String value;
  const Setting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(
      key: Value(key),
      value: Value(value),
    );
  }

  factory Setting.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  Setting copyWith({String? key, String? value}) => Setting(
        key: key ?? this.key,
        value: value ?? this.value,
      );
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting && other.key == this.key && other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        value = Value(value);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith(
      {Value<String>? key, Value<String>? value, Value<int>? rowid}) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SavedTitlesTable extends SavedTitles
    with TableInfo<$SavedTitlesTable, SavedTitle> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedTitlesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tmdbIdMeta = const VerificationMeta('tmdbId');
  @override
  late final GeneratedColumn<int> tmdbId = GeneratedColumn<int>(
      'tmdb_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _mediaTypeMeta =
      const VerificationMeta('mediaType');
  @override
  late final GeneratedColumn<String> mediaType = GeneratedColumn<String>(
      'media_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _posterPathMeta =
      const VerificationMeta('posterPath');
  @override
  late final GeneratedColumn<String> posterPath = GeneratedColumn<String>(
      'poster_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _favoritedAtMeta =
      const VerificationMeta('favoritedAt');
  @override
  late final GeneratedColumn<DateTime> favoritedAt = GeneratedColumn<DateTime>(
      'favorited_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _wantToWatchAtMeta =
      const VerificationMeta('wantToWatchAt');
  @override
  late final GeneratedColumn<DateTime> wantToWatchAt =
      GeneratedColumn<DateTime>('want_to_watch_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _keptAtMeta = const VerificationMeta('keptAt');
  @override
  late final GeneratedColumn<DateTime> keptAt = GeneratedColumn<DateTime>(
      'kept_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _notInterestedAtMeta =
      const VerificationMeta('notInterestedAt');
  @override
  late final GeneratedColumn<DateTime> notInterestedAt =
      GeneratedColumn<DateTime>('not_interested_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
      'source', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        tmdbId,
        mediaType,
        name,
        posterPath,
        favoritedAt,
        wantToWatchAt,
        keptAt,
        notInterestedAt,
        source
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_titles';
  @override
  VerificationContext validateIntegrity(Insertable<SavedTitle> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tmdb_id')) {
      context.handle(_tmdbIdMeta,
          tmdbId.isAcceptableOrUnknown(data['tmdb_id']!, _tmdbIdMeta));
    } else if (isInserting) {
      context.missing(_tmdbIdMeta);
    }
    if (data.containsKey('media_type')) {
      context.handle(_mediaTypeMeta,
          mediaType.isAcceptableOrUnknown(data['media_type']!, _mediaTypeMeta));
    } else if (isInserting) {
      context.missing(_mediaTypeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('poster_path')) {
      context.handle(
          _posterPathMeta,
          posterPath.isAcceptableOrUnknown(
              data['poster_path']!, _posterPathMeta));
    }
    if (data.containsKey('favorited_at')) {
      context.handle(
          _favoritedAtMeta,
          favoritedAt.isAcceptableOrUnknown(
              data['favorited_at']!, _favoritedAtMeta));
    }
    if (data.containsKey('want_to_watch_at')) {
      context.handle(
          _wantToWatchAtMeta,
          wantToWatchAt.isAcceptableOrUnknown(
              data['want_to_watch_at']!, _wantToWatchAtMeta));
    }
    if (data.containsKey('kept_at')) {
      context.handle(_keptAtMeta,
          keptAt.isAcceptableOrUnknown(data['kept_at']!, _keptAtMeta));
    }
    if (data.containsKey('not_interested_at')) {
      context.handle(
          _notInterestedAtMeta,
          notInterestedAt.isAcceptableOrUnknown(
              data['not_interested_at']!, _notInterestedAtMeta));
    }
    if (data.containsKey('source')) {
      context.handle(_sourceMeta,
          source.isAcceptableOrUnknown(data['source']!, _sourceMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tmdbId, mediaType};
  @override
  SavedTitle map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedTitle(
      tmdbId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}tmdb_id'])!,
      mediaType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}media_type'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      posterPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}poster_path']),
      favoritedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}favorited_at']),
      wantToWatchAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}want_to_watch_at']),
      keptAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}kept_at']),
      notInterestedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}not_interested_at']),
      source: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source']),
    );
  }

  @override
  $SavedTitlesTable createAlias(String alias) {
    return $SavedTitlesTable(attachedDatabase, alias);
  }
}

class SavedTitle extends DataClass implements Insertable<SavedTitle> {
  final int tmdbId;

  /// 'tv' or 'movie'.
  final String mediaType;

  /// TMDB display name + poster path, cached so list tiles render without a
  /// network round-trip.
  final String name;
  final String? posterPath;
  final DateTime? favoritedAt;
  final DateTime? wantToWatchAt;

  /// Set means the user pinned this whole title "keep": its library files are
  /// exempt from auto-cleanup after a watch — including episodes downloaded
  /// *after* it was pinned, since the reaper checks this show-level flag rather
  /// than each episode row. The show-level counterpart to `LibraryItems.keep`
  /// (which still pins an individual movie / loose file).
  final DateTime? keptAt;

  /// Set means the user marked this title "not interested": it's dropped from
  /// every discovery row on the landing page (recommendations, trending,
  /// personalized genre rows, …) but still turns up in search.
  final DateTime? notInterestedAt;

  /// How this entry got here when it wasn't a direct in-app action — e.g.
  /// 'alexa' for a title queued by voice (see the Alexa inbox drain). Null for
  /// the normal case (the user favorited/watchlisted it themselves).
  /// Informational: powers a "recently added via Alexa" surface later.
  final String? source;
  const SavedTitle(
      {required this.tmdbId,
      required this.mediaType,
      required this.name,
      this.posterPath,
      this.favoritedAt,
      this.wantToWatchAt,
      this.keptAt,
      this.notInterestedAt,
      this.source});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tmdb_id'] = Variable<int>(tmdbId);
    map['media_type'] = Variable<String>(mediaType);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || posterPath != null) {
      map['poster_path'] = Variable<String>(posterPath);
    }
    if (!nullToAbsent || favoritedAt != null) {
      map['favorited_at'] = Variable<DateTime>(favoritedAt);
    }
    if (!nullToAbsent || wantToWatchAt != null) {
      map['want_to_watch_at'] = Variable<DateTime>(wantToWatchAt);
    }
    if (!nullToAbsent || keptAt != null) {
      map['kept_at'] = Variable<DateTime>(keptAt);
    }
    if (!nullToAbsent || notInterestedAt != null) {
      map['not_interested_at'] = Variable<DateTime>(notInterestedAt);
    }
    if (!nullToAbsent || source != null) {
      map['source'] = Variable<String>(source);
    }
    return map;
  }

  SavedTitlesCompanion toCompanion(bool nullToAbsent) {
    return SavedTitlesCompanion(
      tmdbId: Value(tmdbId),
      mediaType: Value(mediaType),
      name: Value(name),
      posterPath: posterPath == null && nullToAbsent
          ? const Value.absent()
          : Value(posterPath),
      favoritedAt: favoritedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(favoritedAt),
      wantToWatchAt: wantToWatchAt == null && nullToAbsent
          ? const Value.absent()
          : Value(wantToWatchAt),
      keptAt:
          keptAt == null && nullToAbsent ? const Value.absent() : Value(keptAt),
      notInterestedAt: notInterestedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(notInterestedAt),
      source:
          source == null && nullToAbsent ? const Value.absent() : Value(source),
    );
  }

  factory SavedTitle.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedTitle(
      tmdbId: serializer.fromJson<int>(json['tmdbId']),
      mediaType: serializer.fromJson<String>(json['mediaType']),
      name: serializer.fromJson<String>(json['name']),
      posterPath: serializer.fromJson<String?>(json['posterPath']),
      favoritedAt: serializer.fromJson<DateTime?>(json['favoritedAt']),
      wantToWatchAt: serializer.fromJson<DateTime?>(json['wantToWatchAt']),
      keptAt: serializer.fromJson<DateTime?>(json['keptAt']),
      notInterestedAt: serializer.fromJson<DateTime?>(json['notInterestedAt']),
      source: serializer.fromJson<String?>(json['source']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tmdbId': serializer.toJson<int>(tmdbId),
      'mediaType': serializer.toJson<String>(mediaType),
      'name': serializer.toJson<String>(name),
      'posterPath': serializer.toJson<String?>(posterPath),
      'favoritedAt': serializer.toJson<DateTime?>(favoritedAt),
      'wantToWatchAt': serializer.toJson<DateTime?>(wantToWatchAt),
      'keptAt': serializer.toJson<DateTime?>(keptAt),
      'notInterestedAt': serializer.toJson<DateTime?>(notInterestedAt),
      'source': serializer.toJson<String?>(source),
    };
  }

  SavedTitle copyWith(
          {int? tmdbId,
          String? mediaType,
          String? name,
          Value<String?> posterPath = const Value.absent(),
          Value<DateTime?> favoritedAt = const Value.absent(),
          Value<DateTime?> wantToWatchAt = const Value.absent(),
          Value<DateTime?> keptAt = const Value.absent(),
          Value<DateTime?> notInterestedAt = const Value.absent(),
          Value<String?> source = const Value.absent()}) =>
      SavedTitle(
        tmdbId: tmdbId ?? this.tmdbId,
        mediaType: mediaType ?? this.mediaType,
        name: name ?? this.name,
        posterPath: posterPath.present ? posterPath.value : this.posterPath,
        favoritedAt: favoritedAt.present ? favoritedAt.value : this.favoritedAt,
        wantToWatchAt:
            wantToWatchAt.present ? wantToWatchAt.value : this.wantToWatchAt,
        keptAt: keptAt.present ? keptAt.value : this.keptAt,
        notInterestedAt: notInterestedAt.present
            ? notInterestedAt.value
            : this.notInterestedAt,
        source: source.present ? source.value : this.source,
      );
  SavedTitle copyWithCompanion(SavedTitlesCompanion data) {
    return SavedTitle(
      tmdbId: data.tmdbId.present ? data.tmdbId.value : this.tmdbId,
      mediaType: data.mediaType.present ? data.mediaType.value : this.mediaType,
      name: data.name.present ? data.name.value : this.name,
      posterPath:
          data.posterPath.present ? data.posterPath.value : this.posterPath,
      favoritedAt:
          data.favoritedAt.present ? data.favoritedAt.value : this.favoritedAt,
      wantToWatchAt: data.wantToWatchAt.present
          ? data.wantToWatchAt.value
          : this.wantToWatchAt,
      keptAt: data.keptAt.present ? data.keptAt.value : this.keptAt,
      notInterestedAt: data.notInterestedAt.present
          ? data.notInterestedAt.value
          : this.notInterestedAt,
      source: data.source.present ? data.source.value : this.source,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavedTitle(')
          ..write('tmdbId: $tmdbId, ')
          ..write('mediaType: $mediaType, ')
          ..write('name: $name, ')
          ..write('posterPath: $posterPath, ')
          ..write('favoritedAt: $favoritedAt, ')
          ..write('wantToWatchAt: $wantToWatchAt, ')
          ..write('keptAt: $keptAt, ')
          ..write('notInterestedAt: $notInterestedAt, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tmdbId, mediaType, name, posterPath,
      favoritedAt, wantToWatchAt, keptAt, notInterestedAt, source);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedTitle &&
          other.tmdbId == this.tmdbId &&
          other.mediaType == this.mediaType &&
          other.name == this.name &&
          other.posterPath == this.posterPath &&
          other.favoritedAt == this.favoritedAt &&
          other.wantToWatchAt == this.wantToWatchAt &&
          other.keptAt == this.keptAt &&
          other.notInterestedAt == this.notInterestedAt &&
          other.source == this.source);
}

class SavedTitlesCompanion extends UpdateCompanion<SavedTitle> {
  final Value<int> tmdbId;
  final Value<String> mediaType;
  final Value<String> name;
  final Value<String?> posterPath;
  final Value<DateTime?> favoritedAt;
  final Value<DateTime?> wantToWatchAt;
  final Value<DateTime?> keptAt;
  final Value<DateTime?> notInterestedAt;
  final Value<String?> source;
  final Value<int> rowid;
  const SavedTitlesCompanion({
    this.tmdbId = const Value.absent(),
    this.mediaType = const Value.absent(),
    this.name = const Value.absent(),
    this.posterPath = const Value.absent(),
    this.favoritedAt = const Value.absent(),
    this.wantToWatchAt = const Value.absent(),
    this.keptAt = const Value.absent(),
    this.notInterestedAt = const Value.absent(),
    this.source = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavedTitlesCompanion.insert({
    required int tmdbId,
    required String mediaType,
    required String name,
    this.posterPath = const Value.absent(),
    this.favoritedAt = const Value.absent(),
    this.wantToWatchAt = const Value.absent(),
    this.keptAt = const Value.absent(),
    this.notInterestedAt = const Value.absent(),
    this.source = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : tmdbId = Value(tmdbId),
        mediaType = Value(mediaType),
        name = Value(name);
  static Insertable<SavedTitle> custom({
    Expression<int>? tmdbId,
    Expression<String>? mediaType,
    Expression<String>? name,
    Expression<String>? posterPath,
    Expression<DateTime>? favoritedAt,
    Expression<DateTime>? wantToWatchAt,
    Expression<DateTime>? keptAt,
    Expression<DateTime>? notInterestedAt,
    Expression<String>? source,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tmdbId != null) 'tmdb_id': tmdbId,
      if (mediaType != null) 'media_type': mediaType,
      if (name != null) 'name': name,
      if (posterPath != null) 'poster_path': posterPath,
      if (favoritedAt != null) 'favorited_at': favoritedAt,
      if (wantToWatchAt != null) 'want_to_watch_at': wantToWatchAt,
      if (keptAt != null) 'kept_at': keptAt,
      if (notInterestedAt != null) 'not_interested_at': notInterestedAt,
      if (source != null) 'source': source,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavedTitlesCompanion copyWith(
      {Value<int>? tmdbId,
      Value<String>? mediaType,
      Value<String>? name,
      Value<String?>? posterPath,
      Value<DateTime?>? favoritedAt,
      Value<DateTime?>? wantToWatchAt,
      Value<DateTime?>? keptAt,
      Value<DateTime?>? notInterestedAt,
      Value<String?>? source,
      Value<int>? rowid}) {
    return SavedTitlesCompanion(
      tmdbId: tmdbId ?? this.tmdbId,
      mediaType: mediaType ?? this.mediaType,
      name: name ?? this.name,
      posterPath: posterPath ?? this.posterPath,
      favoritedAt: favoritedAt ?? this.favoritedAt,
      wantToWatchAt: wantToWatchAt ?? this.wantToWatchAt,
      keptAt: keptAt ?? this.keptAt,
      notInterestedAt: notInterestedAt ?? this.notInterestedAt,
      source: source ?? this.source,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tmdbId.present) {
      map['tmdb_id'] = Variable<int>(tmdbId.value);
    }
    if (mediaType.present) {
      map['media_type'] = Variable<String>(mediaType.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (posterPath.present) {
      map['poster_path'] = Variable<String>(posterPath.value);
    }
    if (favoritedAt.present) {
      map['favorited_at'] = Variable<DateTime>(favoritedAt.value);
    }
    if (wantToWatchAt.present) {
      map['want_to_watch_at'] = Variable<DateTime>(wantToWatchAt.value);
    }
    if (keptAt.present) {
      map['kept_at'] = Variable<DateTime>(keptAt.value);
    }
    if (notInterestedAt.present) {
      map['not_interested_at'] = Variable<DateTime>(notInterestedAt.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedTitlesCompanion(')
          ..write('tmdbId: $tmdbId, ')
          ..write('mediaType: $mediaType, ')
          ..write('name: $name, ')
          ..write('posterPath: $posterPath, ')
          ..write('favoritedAt: $favoritedAt, ')
          ..write('wantToWatchAt: $wantToWatchAt, ')
          ..write('keptAt: $keptAt, ')
          ..write('notInterestedAt: $notInterestedAt, ')
          ..write('source: $source, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StorageLocationsTable extends StorageLocations
    with TableInfo<$StorageLocationsTable, StorageLocation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StorageLocationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
      'path', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
      'label', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _enabledMeta =
      const VerificationMeta('enabled');
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
      'enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _priorityMeta =
      const VerificationMeta('priority');
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
      'priority', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns => [id, path, label, enabled, priority];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'storage_locations';
  @override
  VerificationContext validateIntegrity(Insertable<StorageLocation> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('path')) {
      context.handle(
          _pathMeta, path.isAcceptableOrUnknown(data['path']!, _pathMeta));
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
          _labelMeta, label.isAcceptableOrUnknown(data['label']!, _labelMeta));
    }
    if (data.containsKey('enabled')) {
      context.handle(_enabledMeta,
          enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta));
    }
    if (data.containsKey('priority')) {
      context.handle(_priorityMeta,
          priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StorageLocation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StorageLocation(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      path: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}path'])!,
      label: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}label']),
      enabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}enabled'])!,
      priority: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}priority'])!,
    );
  }

  @override
  $StorageLocationsTable createAlias(String alias) {
    return $StorageLocationsTable(attachedDatabase, alias);
  }
}

class StorageLocation extends DataClass implements Insertable<StorageLocation> {
  final int id;
  final String path;
  final String? label;
  final bool enabled;
  final int priority;
  const StorageLocation(
      {required this.id,
      required this.path,
      this.label,
      required this.enabled,
      required this.priority});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['path'] = Variable<String>(path);
    if (!nullToAbsent || label != null) {
      map['label'] = Variable<String>(label);
    }
    map['enabled'] = Variable<bool>(enabled);
    map['priority'] = Variable<int>(priority);
    return map;
  }

  StorageLocationsCompanion toCompanion(bool nullToAbsent) {
    return StorageLocationsCompanion(
      id: Value(id),
      path: Value(path),
      label:
          label == null && nullToAbsent ? const Value.absent() : Value(label),
      enabled: Value(enabled),
      priority: Value(priority),
    );
  }

  factory StorageLocation.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StorageLocation(
      id: serializer.fromJson<int>(json['id']),
      path: serializer.fromJson<String>(json['path']),
      label: serializer.fromJson<String?>(json['label']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      priority: serializer.fromJson<int>(json['priority']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'path': serializer.toJson<String>(path),
      'label': serializer.toJson<String?>(label),
      'enabled': serializer.toJson<bool>(enabled),
      'priority': serializer.toJson<int>(priority),
    };
  }

  StorageLocation copyWith(
          {int? id,
          String? path,
          Value<String?> label = const Value.absent(),
          bool? enabled,
          int? priority}) =>
      StorageLocation(
        id: id ?? this.id,
        path: path ?? this.path,
        label: label.present ? label.value : this.label,
        enabled: enabled ?? this.enabled,
        priority: priority ?? this.priority,
      );
  StorageLocation copyWithCompanion(StorageLocationsCompanion data) {
    return StorageLocation(
      id: data.id.present ? data.id.value : this.id,
      path: data.path.present ? data.path.value : this.path,
      label: data.label.present ? data.label.value : this.label,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      priority: data.priority.present ? data.priority.value : this.priority,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StorageLocation(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('label: $label, ')
          ..write('enabled: $enabled, ')
          ..write('priority: $priority')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, path, label, enabled, priority);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StorageLocation &&
          other.id == this.id &&
          other.path == this.path &&
          other.label == this.label &&
          other.enabled == this.enabled &&
          other.priority == this.priority);
}

class StorageLocationsCompanion extends UpdateCompanion<StorageLocation> {
  final Value<int> id;
  final Value<String> path;
  final Value<String?> label;
  final Value<bool> enabled;
  final Value<int> priority;
  const StorageLocationsCompanion({
    this.id = const Value.absent(),
    this.path = const Value.absent(),
    this.label = const Value.absent(),
    this.enabled = const Value.absent(),
    this.priority = const Value.absent(),
  });
  StorageLocationsCompanion.insert({
    this.id = const Value.absent(),
    required String path,
    this.label = const Value.absent(),
    this.enabled = const Value.absent(),
    this.priority = const Value.absent(),
  }) : path = Value(path);
  static Insertable<StorageLocation> custom({
    Expression<int>? id,
    Expression<String>? path,
    Expression<String>? label,
    Expression<bool>? enabled,
    Expression<int>? priority,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (path != null) 'path': path,
      if (label != null) 'label': label,
      if (enabled != null) 'enabled': enabled,
      if (priority != null) 'priority': priority,
    });
  }

  StorageLocationsCompanion copyWith(
      {Value<int>? id,
      Value<String>? path,
      Value<String?>? label,
      Value<bool>? enabled,
      Value<int>? priority}) {
    return StorageLocationsCompanion(
      id: id ?? this.id,
      path: path ?? this.path,
      label: label ?? this.label,
      enabled: enabled ?? this.enabled,
      priority: priority ?? this.priority,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StorageLocationsCompanion(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('label: $label, ')
          ..write('enabled: $enabled, ')
          ..write('priority: $priority')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $LibraryItemsTable libraryItems = $LibraryItemsTable(this);
  late final $WatchHistoryTable watchHistory = $WatchHistoryTable(this);
  late final $SubtitleAttemptsTable subtitleAttempts =
      $SubtitleAttemptsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $SavedTitlesTable savedTitles = $SavedTitlesTable(this);
  late final $StorageLocationsTable storageLocations =
      $StorageLocationsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        libraryItems,
        watchHistory,
        subtitleAttempts,
        settings,
        savedTitles,
        storageLocations
      ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('library_items',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('watch_history', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('library_items',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('subtitle_attempts', kind: UpdateKind.delete),
            ],
          ),
        ],
      );
}

typedef $$LibraryItemsTableCreateCompanionBuilder = LibraryItemsCompanion
    Function({
  Value<int> id,
  required String mediaType,
  required String title,
  Value<int?> tmdbId,
  Value<String?> tmdbName,
  Value<String?> tmdbPosterPath,
  Value<int?> season,
  Value<int?> episode,
  required String filePath,
  Value<String?> container,
  Value<String?> videoCodec,
  Value<String?> audioCodec,
  Value<bool> hasEmbeddedEnSub,
  Value<int> subtitleOffsetMs,
  Value<bool> managed,
  Value<bool> keep,
  Value<bool> missing,
  Value<DateTime> addedAt,
});
typedef $$LibraryItemsTableUpdateCompanionBuilder = LibraryItemsCompanion
    Function({
  Value<int> id,
  Value<String> mediaType,
  Value<String> title,
  Value<int?> tmdbId,
  Value<String?> tmdbName,
  Value<String?> tmdbPosterPath,
  Value<int?> season,
  Value<int?> episode,
  Value<String> filePath,
  Value<String?> container,
  Value<String?> videoCodec,
  Value<String?> audioCodec,
  Value<bool> hasEmbeddedEnSub,
  Value<int> subtitleOffsetMs,
  Value<bool> managed,
  Value<bool> keep,
  Value<bool> missing,
  Value<DateTime> addedAt,
});

final class $$LibraryItemsTableReferences
    extends BaseReferences<_$AppDatabase, $LibraryItemsTable, LibraryItem> {
  $$LibraryItemsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$WatchHistoryTable, List<WatchHistoryData>>
      _watchHistoryRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.watchHistory,
              aliasName: $_aliasNameGenerator(
                  db.libraryItems.id, db.watchHistory.libraryItemId));

  $$WatchHistoryTableProcessedTableManager get watchHistoryRefs {
    final manager = $$WatchHistoryTableTableManager($_db, $_db.watchHistory)
        .filter((f) => f.libraryItemId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_watchHistoryRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$SubtitleAttemptsTable, List<SubtitleAttempt>>
      _subtitleAttemptsRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.subtitleAttempts,
              aliasName: $_aliasNameGenerator(
                  db.libraryItems.id, db.subtitleAttempts.libraryItemId));

  $$SubtitleAttemptsTableProcessedTableManager get subtitleAttemptsRefs {
    final manager = $$SubtitleAttemptsTableTableManager(
            $_db, $_db.subtitleAttempts)
        .filter((f) => f.libraryItemId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_subtitleAttemptsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$LibraryItemsTableFilterComposer
    extends Composer<_$AppDatabase, $LibraryItemsTable> {
  $$LibraryItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mediaType => $composableBuilder(
      column: $table.mediaType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get tmdbId => $composableBuilder(
      column: $table.tmdbId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tmdbName => $composableBuilder(
      column: $table.tmdbName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tmdbPosterPath => $composableBuilder(
      column: $table.tmdbPosterPath,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get season => $composableBuilder(
      column: $table.season, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get episode => $composableBuilder(
      column: $table.episode, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get filePath => $composableBuilder(
      column: $table.filePath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get container => $composableBuilder(
      column: $table.container, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get videoCodec => $composableBuilder(
      column: $table.videoCodec, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get audioCodec => $composableBuilder(
      column: $table.audioCodec, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get hasEmbeddedEnSub => $composableBuilder(
      column: $table.hasEmbeddedEnSub,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get subtitleOffsetMs => $composableBuilder(
      column: $table.subtitleOffsetMs,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get managed => $composableBuilder(
      column: $table.managed, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get keep => $composableBuilder(
      column: $table.keep, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get missing => $composableBuilder(
      column: $table.missing, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnFilters(column));

  Expression<bool> watchHistoryRefs(
      Expression<bool> Function($$WatchHistoryTableFilterComposer f) f) {
    final $$WatchHistoryTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.watchHistory,
        getReferencedColumn: (t) => t.libraryItemId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$WatchHistoryTableFilterComposer(
              $db: $db,
              $table: $db.watchHistory,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> subtitleAttemptsRefs(
      Expression<bool> Function($$SubtitleAttemptsTableFilterComposer f) f) {
    final $$SubtitleAttemptsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.subtitleAttempts,
        getReferencedColumn: (t) => t.libraryItemId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SubtitleAttemptsTableFilterComposer(
              $db: $db,
              $table: $db.subtitleAttempts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$LibraryItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $LibraryItemsTable> {
  $$LibraryItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mediaType => $composableBuilder(
      column: $table.mediaType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get tmdbId => $composableBuilder(
      column: $table.tmdbId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tmdbName => $composableBuilder(
      column: $table.tmdbName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tmdbPosterPath => $composableBuilder(
      column: $table.tmdbPosterPath,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get season => $composableBuilder(
      column: $table.season, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get episode => $composableBuilder(
      column: $table.episode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get filePath => $composableBuilder(
      column: $table.filePath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get container => $composableBuilder(
      column: $table.container, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get videoCodec => $composableBuilder(
      column: $table.videoCodec, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get audioCodec => $composableBuilder(
      column: $table.audioCodec, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get hasEmbeddedEnSub => $composableBuilder(
      column: $table.hasEmbeddedEnSub,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get subtitleOffsetMs => $composableBuilder(
      column: $table.subtitleOffsetMs,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get managed => $composableBuilder(
      column: $table.managed, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get keep => $composableBuilder(
      column: $table.keep, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get missing => $composableBuilder(
      column: $table.missing, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnOrderings(column));
}

class $$LibraryItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LibraryItemsTable> {
  $$LibraryItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get mediaType =>
      $composableBuilder(column: $table.mediaType, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get tmdbId =>
      $composableBuilder(column: $table.tmdbId, builder: (column) => column);

  GeneratedColumn<String> get tmdbName =>
      $composableBuilder(column: $table.tmdbName, builder: (column) => column);

  GeneratedColumn<String> get tmdbPosterPath => $composableBuilder(
      column: $table.tmdbPosterPath, builder: (column) => column);

  GeneratedColumn<int> get season =>
      $composableBuilder(column: $table.season, builder: (column) => column);

  GeneratedColumn<int> get episode =>
      $composableBuilder(column: $table.episode, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<String> get container =>
      $composableBuilder(column: $table.container, builder: (column) => column);

  GeneratedColumn<String> get videoCodec => $composableBuilder(
      column: $table.videoCodec, builder: (column) => column);

  GeneratedColumn<String> get audioCodec => $composableBuilder(
      column: $table.audioCodec, builder: (column) => column);

  GeneratedColumn<bool> get hasEmbeddedEnSub => $composableBuilder(
      column: $table.hasEmbeddedEnSub, builder: (column) => column);

  GeneratedColumn<int> get subtitleOffsetMs => $composableBuilder(
      column: $table.subtitleOffsetMs, builder: (column) => column);

  GeneratedColumn<bool> get managed =>
      $composableBuilder(column: $table.managed, builder: (column) => column);

  GeneratedColumn<bool> get keep =>
      $composableBuilder(column: $table.keep, builder: (column) => column);

  GeneratedColumn<bool> get missing =>
      $composableBuilder(column: $table.missing, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  Expression<T> watchHistoryRefs<T extends Object>(
      Expression<T> Function($$WatchHistoryTableAnnotationComposer a) f) {
    final $$WatchHistoryTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.watchHistory,
        getReferencedColumn: (t) => t.libraryItemId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$WatchHistoryTableAnnotationComposer(
              $db: $db,
              $table: $db.watchHistory,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> subtitleAttemptsRefs<T extends Object>(
      Expression<T> Function($$SubtitleAttemptsTableAnnotationComposer a) f) {
    final $$SubtitleAttemptsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.subtitleAttempts,
        getReferencedColumn: (t) => t.libraryItemId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SubtitleAttemptsTableAnnotationComposer(
              $db: $db,
              $table: $db.subtitleAttempts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$LibraryItemsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LibraryItemsTable,
    LibraryItem,
    $$LibraryItemsTableFilterComposer,
    $$LibraryItemsTableOrderingComposer,
    $$LibraryItemsTableAnnotationComposer,
    $$LibraryItemsTableCreateCompanionBuilder,
    $$LibraryItemsTableUpdateCompanionBuilder,
    (LibraryItem, $$LibraryItemsTableReferences),
    LibraryItem,
    PrefetchHooks Function(
        {bool watchHistoryRefs, bool subtitleAttemptsRefs})> {
  $$LibraryItemsTableTableManager(_$AppDatabase db, $LibraryItemsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LibraryItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LibraryItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LibraryItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> mediaType = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<int?> tmdbId = const Value.absent(),
            Value<String?> tmdbName = const Value.absent(),
            Value<String?> tmdbPosterPath = const Value.absent(),
            Value<int?> season = const Value.absent(),
            Value<int?> episode = const Value.absent(),
            Value<String> filePath = const Value.absent(),
            Value<String?> container = const Value.absent(),
            Value<String?> videoCodec = const Value.absent(),
            Value<String?> audioCodec = const Value.absent(),
            Value<bool> hasEmbeddedEnSub = const Value.absent(),
            Value<int> subtitleOffsetMs = const Value.absent(),
            Value<bool> managed = const Value.absent(),
            Value<bool> keep = const Value.absent(),
            Value<bool> missing = const Value.absent(),
            Value<DateTime> addedAt = const Value.absent(),
          }) =>
              LibraryItemsCompanion(
            id: id,
            mediaType: mediaType,
            title: title,
            tmdbId: tmdbId,
            tmdbName: tmdbName,
            tmdbPosterPath: tmdbPosterPath,
            season: season,
            episode: episode,
            filePath: filePath,
            container: container,
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            hasEmbeddedEnSub: hasEmbeddedEnSub,
            subtitleOffsetMs: subtitleOffsetMs,
            managed: managed,
            keep: keep,
            missing: missing,
            addedAt: addedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String mediaType,
            required String title,
            Value<int?> tmdbId = const Value.absent(),
            Value<String?> tmdbName = const Value.absent(),
            Value<String?> tmdbPosterPath = const Value.absent(),
            Value<int?> season = const Value.absent(),
            Value<int?> episode = const Value.absent(),
            required String filePath,
            Value<String?> container = const Value.absent(),
            Value<String?> videoCodec = const Value.absent(),
            Value<String?> audioCodec = const Value.absent(),
            Value<bool> hasEmbeddedEnSub = const Value.absent(),
            Value<int> subtitleOffsetMs = const Value.absent(),
            Value<bool> managed = const Value.absent(),
            Value<bool> keep = const Value.absent(),
            Value<bool> missing = const Value.absent(),
            Value<DateTime> addedAt = const Value.absent(),
          }) =>
              LibraryItemsCompanion.insert(
            id: id,
            mediaType: mediaType,
            title: title,
            tmdbId: tmdbId,
            tmdbName: tmdbName,
            tmdbPosterPath: tmdbPosterPath,
            season: season,
            episode: episode,
            filePath: filePath,
            container: container,
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            hasEmbeddedEnSub: hasEmbeddedEnSub,
            subtitleOffsetMs: subtitleOffsetMs,
            managed: managed,
            keep: keep,
            missing: missing,
            addedAt: addedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$LibraryItemsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {watchHistoryRefs = false, subtitleAttemptsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (watchHistoryRefs) db.watchHistory,
                if (subtitleAttemptsRefs) db.subtitleAttempts
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (watchHistoryRefs)
                    await $_getPrefetchedData<LibraryItem, $LibraryItemsTable, WatchHistoryData>(
                        currentTable: table,
                        referencedTable: $$LibraryItemsTableReferences
                            ._watchHistoryRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$LibraryItemsTableReferences(db, table, p0)
                                .watchHistoryRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.libraryItemId == item.id),
                        typedResults: items),
                  if (subtitleAttemptsRefs)
                    await $_getPrefetchedData<LibraryItem, $LibraryItemsTable,
                            SubtitleAttempt>(
                        currentTable: table,
                        referencedTable: $$LibraryItemsTableReferences
                            ._subtitleAttemptsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$LibraryItemsTableReferences(db, table, p0)
                                .subtitleAttemptsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.libraryItemId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$LibraryItemsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LibraryItemsTable,
    LibraryItem,
    $$LibraryItemsTableFilterComposer,
    $$LibraryItemsTableOrderingComposer,
    $$LibraryItemsTableAnnotationComposer,
    $$LibraryItemsTableCreateCompanionBuilder,
    $$LibraryItemsTableUpdateCompanionBuilder,
    (LibraryItem, $$LibraryItemsTableReferences),
    LibraryItem,
    PrefetchHooks Function({bool watchHistoryRefs, bool subtitleAttemptsRefs})>;
typedef $$WatchHistoryTableCreateCompanionBuilder = WatchHistoryCompanion
    Function({
  Value<int> id,
  required int libraryItemId,
  Value<int> resumePositionSec,
  Value<int?> durationSec,
  Value<bool> completed,
  Value<DateTime> lastWatchedAt,
});
typedef $$WatchHistoryTableUpdateCompanionBuilder = WatchHistoryCompanion
    Function({
  Value<int> id,
  Value<int> libraryItemId,
  Value<int> resumePositionSec,
  Value<int?> durationSec,
  Value<bool> completed,
  Value<DateTime> lastWatchedAt,
});

final class $$WatchHistoryTableReferences extends BaseReferences<_$AppDatabase,
    $WatchHistoryTable, WatchHistoryData> {
  $$WatchHistoryTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $LibraryItemsTable _libraryItemIdTable(_$AppDatabase db) =>
      db.libraryItems.createAlias($_aliasNameGenerator(
          db.watchHistory.libraryItemId, db.libraryItems.id));

  $$LibraryItemsTableProcessedTableManager get libraryItemId {
    final $_column = $_itemColumn<int>('library_item_id')!;

    final manager = $$LibraryItemsTableTableManager($_db, $_db.libraryItems)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_libraryItemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$WatchHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $WatchHistoryTable> {
  $$WatchHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get resumePositionSec => $composableBuilder(
      column: $table.resumePositionSec,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationSec => $composableBuilder(
      column: $table.durationSec, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get completed => $composableBuilder(
      column: $table.completed, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastWatchedAt => $composableBuilder(
      column: $table.lastWatchedAt, builder: (column) => ColumnFilters(column));

  $$LibraryItemsTableFilterComposer get libraryItemId {
    final $$LibraryItemsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.libraryItemId,
        referencedTable: $db.libraryItems,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LibraryItemsTableFilterComposer(
              $db: $db,
              $table: $db.libraryItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$WatchHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $WatchHistoryTable> {
  $$WatchHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get resumePositionSec => $composableBuilder(
      column: $table.resumePositionSec,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationSec => $composableBuilder(
      column: $table.durationSec, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get completed => $composableBuilder(
      column: $table.completed, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastWatchedAt => $composableBuilder(
      column: $table.lastWatchedAt,
      builder: (column) => ColumnOrderings(column));

  $$LibraryItemsTableOrderingComposer get libraryItemId {
    final $$LibraryItemsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.libraryItemId,
        referencedTable: $db.libraryItems,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LibraryItemsTableOrderingComposer(
              $db: $db,
              $table: $db.libraryItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$WatchHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $WatchHistoryTable> {
  $$WatchHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get resumePositionSec => $composableBuilder(
      column: $table.resumePositionSec, builder: (column) => column);

  GeneratedColumn<int> get durationSec => $composableBuilder(
      column: $table.durationSec, builder: (column) => column);

  GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  GeneratedColumn<DateTime> get lastWatchedAt => $composableBuilder(
      column: $table.lastWatchedAt, builder: (column) => column);

  $$LibraryItemsTableAnnotationComposer get libraryItemId {
    final $$LibraryItemsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.libraryItemId,
        referencedTable: $db.libraryItems,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LibraryItemsTableAnnotationComposer(
              $db: $db,
              $table: $db.libraryItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$WatchHistoryTableTableManager extends RootTableManager<
    _$AppDatabase,
    $WatchHistoryTable,
    WatchHistoryData,
    $$WatchHistoryTableFilterComposer,
    $$WatchHistoryTableOrderingComposer,
    $$WatchHistoryTableAnnotationComposer,
    $$WatchHistoryTableCreateCompanionBuilder,
    $$WatchHistoryTableUpdateCompanionBuilder,
    (WatchHistoryData, $$WatchHistoryTableReferences),
    WatchHistoryData,
    PrefetchHooks Function({bool libraryItemId})> {
  $$WatchHistoryTableTableManager(_$AppDatabase db, $WatchHistoryTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WatchHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WatchHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WatchHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> libraryItemId = const Value.absent(),
            Value<int> resumePositionSec = const Value.absent(),
            Value<int?> durationSec = const Value.absent(),
            Value<bool> completed = const Value.absent(),
            Value<DateTime> lastWatchedAt = const Value.absent(),
          }) =>
              WatchHistoryCompanion(
            id: id,
            libraryItemId: libraryItemId,
            resumePositionSec: resumePositionSec,
            durationSec: durationSec,
            completed: completed,
            lastWatchedAt: lastWatchedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int libraryItemId,
            Value<int> resumePositionSec = const Value.absent(),
            Value<int?> durationSec = const Value.absent(),
            Value<bool> completed = const Value.absent(),
            Value<DateTime> lastWatchedAt = const Value.absent(),
          }) =>
              WatchHistoryCompanion.insert(
            id: id,
            libraryItemId: libraryItemId,
            resumePositionSec: resumePositionSec,
            durationSec: durationSec,
            completed: completed,
            lastWatchedAt: lastWatchedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$WatchHistoryTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({libraryItemId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (libraryItemId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.libraryItemId,
                    referencedTable:
                        $$WatchHistoryTableReferences._libraryItemIdTable(db),
                    referencedColumn: $$WatchHistoryTableReferences
                        ._libraryItemIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$WatchHistoryTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $WatchHistoryTable,
    WatchHistoryData,
    $$WatchHistoryTableFilterComposer,
    $$WatchHistoryTableOrderingComposer,
    $$WatchHistoryTableAnnotationComposer,
    $$WatchHistoryTableCreateCompanionBuilder,
    $$WatchHistoryTableUpdateCompanionBuilder,
    (WatchHistoryData, $$WatchHistoryTableReferences),
    WatchHistoryData,
    PrefetchHooks Function({bool libraryItemId})>;
typedef $$SubtitleAttemptsTableCreateCompanionBuilder
    = SubtitleAttemptsCompanion Function({
  Value<int> id,
  required int libraryItemId,
  required String status,
  Value<DateTime> attemptedAt,
});
typedef $$SubtitleAttemptsTableUpdateCompanionBuilder
    = SubtitleAttemptsCompanion Function({
  Value<int> id,
  Value<int> libraryItemId,
  Value<String> status,
  Value<DateTime> attemptedAt,
});

final class $$SubtitleAttemptsTableReferences extends BaseReferences<
    _$AppDatabase, $SubtitleAttemptsTable, SubtitleAttempt> {
  $$SubtitleAttemptsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $LibraryItemsTable _libraryItemIdTable(_$AppDatabase db) =>
      db.libraryItems.createAlias($_aliasNameGenerator(
          db.subtitleAttempts.libraryItemId, db.libraryItems.id));

  $$LibraryItemsTableProcessedTableManager get libraryItemId {
    final $_column = $_itemColumn<int>('library_item_id')!;

    final manager = $$LibraryItemsTableTableManager($_db, $_db.libraryItems)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_libraryItemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$SubtitleAttemptsTableFilterComposer
    extends Composer<_$AppDatabase, $SubtitleAttemptsTable> {
  $$SubtitleAttemptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get attemptedAt => $composableBuilder(
      column: $table.attemptedAt, builder: (column) => ColumnFilters(column));

  $$LibraryItemsTableFilterComposer get libraryItemId {
    final $$LibraryItemsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.libraryItemId,
        referencedTable: $db.libraryItems,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LibraryItemsTableFilterComposer(
              $db: $db,
              $table: $db.libraryItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SubtitleAttemptsTableOrderingComposer
    extends Composer<_$AppDatabase, $SubtitleAttemptsTable> {
  $$SubtitleAttemptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get attemptedAt => $composableBuilder(
      column: $table.attemptedAt, builder: (column) => ColumnOrderings(column));

  $$LibraryItemsTableOrderingComposer get libraryItemId {
    final $$LibraryItemsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.libraryItemId,
        referencedTable: $db.libraryItems,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LibraryItemsTableOrderingComposer(
              $db: $db,
              $table: $db.libraryItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SubtitleAttemptsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SubtitleAttemptsTable> {
  $$SubtitleAttemptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get attemptedAt => $composableBuilder(
      column: $table.attemptedAt, builder: (column) => column);

  $$LibraryItemsTableAnnotationComposer get libraryItemId {
    final $$LibraryItemsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.libraryItemId,
        referencedTable: $db.libraryItems,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LibraryItemsTableAnnotationComposer(
              $db: $db,
              $table: $db.libraryItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SubtitleAttemptsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SubtitleAttemptsTable,
    SubtitleAttempt,
    $$SubtitleAttemptsTableFilterComposer,
    $$SubtitleAttemptsTableOrderingComposer,
    $$SubtitleAttemptsTableAnnotationComposer,
    $$SubtitleAttemptsTableCreateCompanionBuilder,
    $$SubtitleAttemptsTableUpdateCompanionBuilder,
    (SubtitleAttempt, $$SubtitleAttemptsTableReferences),
    SubtitleAttempt,
    PrefetchHooks Function({bool libraryItemId})> {
  $$SubtitleAttemptsTableTableManager(
      _$AppDatabase db, $SubtitleAttemptsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SubtitleAttemptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SubtitleAttemptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SubtitleAttemptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> libraryItemId = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<DateTime> attemptedAt = const Value.absent(),
          }) =>
              SubtitleAttemptsCompanion(
            id: id,
            libraryItemId: libraryItemId,
            status: status,
            attemptedAt: attemptedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int libraryItemId,
            required String status,
            Value<DateTime> attemptedAt = const Value.absent(),
          }) =>
              SubtitleAttemptsCompanion.insert(
            id: id,
            libraryItemId: libraryItemId,
            status: status,
            attemptedAt: attemptedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$SubtitleAttemptsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({libraryItemId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (libraryItemId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.libraryItemId,
                    referencedTable: $$SubtitleAttemptsTableReferences
                        ._libraryItemIdTable(db),
                    referencedColumn: $$SubtitleAttemptsTableReferences
                        ._libraryItemIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$SubtitleAttemptsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SubtitleAttemptsTable,
    SubtitleAttempt,
    $$SubtitleAttemptsTableFilterComposer,
    $$SubtitleAttemptsTableOrderingComposer,
    $$SubtitleAttemptsTableAnnotationComposer,
    $$SubtitleAttemptsTableCreateCompanionBuilder,
    $$SubtitleAttemptsTableUpdateCompanionBuilder,
    (SubtitleAttempt, $$SubtitleAttemptsTableReferences),
    SubtitleAttempt,
    PrefetchHooks Function({bool libraryItemId})>;
typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SettingsTable,
    Setting,
    $$SettingsTableFilterComposer,
    $$SettingsTableOrderingComposer,
    $$SettingsTableAnnotationComposer,
    $$SettingsTableCreateCompanionBuilder,
    $$SettingsTableUpdateCompanionBuilder,
    (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
    Setting,
    PrefetchHooks Function()> {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SettingsCompanion(
            key: key,
            value: value,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) =>
              SettingsCompanion.insert(
            key: key,
            value: value,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SettingsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SettingsTable,
    Setting,
    $$SettingsTableFilterComposer,
    $$SettingsTableOrderingComposer,
    $$SettingsTableAnnotationComposer,
    $$SettingsTableCreateCompanionBuilder,
    $$SettingsTableUpdateCompanionBuilder,
    (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
    Setting,
    PrefetchHooks Function()>;
typedef $$SavedTitlesTableCreateCompanionBuilder = SavedTitlesCompanion
    Function({
  required int tmdbId,
  required String mediaType,
  required String name,
  Value<String?> posterPath,
  Value<DateTime?> favoritedAt,
  Value<DateTime?> wantToWatchAt,
  Value<DateTime?> keptAt,
  Value<DateTime?> notInterestedAt,
  Value<String?> source,
  Value<int> rowid,
});
typedef $$SavedTitlesTableUpdateCompanionBuilder = SavedTitlesCompanion
    Function({
  Value<int> tmdbId,
  Value<String> mediaType,
  Value<String> name,
  Value<String?> posterPath,
  Value<DateTime?> favoritedAt,
  Value<DateTime?> wantToWatchAt,
  Value<DateTime?> keptAt,
  Value<DateTime?> notInterestedAt,
  Value<String?> source,
  Value<int> rowid,
});

class $$SavedTitlesTableFilterComposer
    extends Composer<_$AppDatabase, $SavedTitlesTable> {
  $$SavedTitlesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get tmdbId => $composableBuilder(
      column: $table.tmdbId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mediaType => $composableBuilder(
      column: $table.mediaType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get posterPath => $composableBuilder(
      column: $table.posterPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get favoritedAt => $composableBuilder(
      column: $table.favoritedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get wantToWatchAt => $composableBuilder(
      column: $table.wantToWatchAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get keptAt => $composableBuilder(
      column: $table.keptAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get notInterestedAt => $composableBuilder(
      column: $table.notInterestedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnFilters(column));
}

class $$SavedTitlesTableOrderingComposer
    extends Composer<_$AppDatabase, $SavedTitlesTable> {
  $$SavedTitlesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get tmdbId => $composableBuilder(
      column: $table.tmdbId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mediaType => $composableBuilder(
      column: $table.mediaType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get posterPath => $composableBuilder(
      column: $table.posterPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get favoritedAt => $composableBuilder(
      column: $table.favoritedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get wantToWatchAt => $composableBuilder(
      column: $table.wantToWatchAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get keptAt => $composableBuilder(
      column: $table.keptAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get notInterestedAt => $composableBuilder(
      column: $table.notInterestedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnOrderings(column));
}

class $$SavedTitlesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavedTitlesTable> {
  $$SavedTitlesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get tmdbId =>
      $composableBuilder(column: $table.tmdbId, builder: (column) => column);

  GeneratedColumn<String> get mediaType =>
      $composableBuilder(column: $table.mediaType, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get posterPath => $composableBuilder(
      column: $table.posterPath, builder: (column) => column);

  GeneratedColumn<DateTime> get favoritedAt => $composableBuilder(
      column: $table.favoritedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get wantToWatchAt => $composableBuilder(
      column: $table.wantToWatchAt, builder: (column) => column);

  GeneratedColumn<DateTime> get keptAt =>
      $composableBuilder(column: $table.keptAt, builder: (column) => column);

  GeneratedColumn<DateTime> get notInterestedAt => $composableBuilder(
      column: $table.notInterestedAt, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);
}

class $$SavedTitlesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SavedTitlesTable,
    SavedTitle,
    $$SavedTitlesTableFilterComposer,
    $$SavedTitlesTableOrderingComposer,
    $$SavedTitlesTableAnnotationComposer,
    $$SavedTitlesTableCreateCompanionBuilder,
    $$SavedTitlesTableUpdateCompanionBuilder,
    (SavedTitle, BaseReferences<_$AppDatabase, $SavedTitlesTable, SavedTitle>),
    SavedTitle,
    PrefetchHooks Function()> {
  $$SavedTitlesTableTableManager(_$AppDatabase db, $SavedTitlesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedTitlesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedTitlesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedTitlesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> tmdbId = const Value.absent(),
            Value<String> mediaType = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> posterPath = const Value.absent(),
            Value<DateTime?> favoritedAt = const Value.absent(),
            Value<DateTime?> wantToWatchAt = const Value.absent(),
            Value<DateTime?> keptAt = const Value.absent(),
            Value<DateTime?> notInterestedAt = const Value.absent(),
            Value<String?> source = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SavedTitlesCompanion(
            tmdbId: tmdbId,
            mediaType: mediaType,
            name: name,
            posterPath: posterPath,
            favoritedAt: favoritedAt,
            wantToWatchAt: wantToWatchAt,
            keptAt: keptAt,
            notInterestedAt: notInterestedAt,
            source: source,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required int tmdbId,
            required String mediaType,
            required String name,
            Value<String?> posterPath = const Value.absent(),
            Value<DateTime?> favoritedAt = const Value.absent(),
            Value<DateTime?> wantToWatchAt = const Value.absent(),
            Value<DateTime?> keptAt = const Value.absent(),
            Value<DateTime?> notInterestedAt = const Value.absent(),
            Value<String?> source = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SavedTitlesCompanion.insert(
            tmdbId: tmdbId,
            mediaType: mediaType,
            name: name,
            posterPath: posterPath,
            favoritedAt: favoritedAt,
            wantToWatchAt: wantToWatchAt,
            keptAt: keptAt,
            notInterestedAt: notInterestedAt,
            source: source,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SavedTitlesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SavedTitlesTable,
    SavedTitle,
    $$SavedTitlesTableFilterComposer,
    $$SavedTitlesTableOrderingComposer,
    $$SavedTitlesTableAnnotationComposer,
    $$SavedTitlesTableCreateCompanionBuilder,
    $$SavedTitlesTableUpdateCompanionBuilder,
    (SavedTitle, BaseReferences<_$AppDatabase, $SavedTitlesTable, SavedTitle>),
    SavedTitle,
    PrefetchHooks Function()>;
typedef $$StorageLocationsTableCreateCompanionBuilder
    = StorageLocationsCompanion Function({
  Value<int> id,
  required String path,
  Value<String?> label,
  Value<bool> enabled,
  Value<int> priority,
});
typedef $$StorageLocationsTableUpdateCompanionBuilder
    = StorageLocationsCompanion Function({
  Value<int> id,
  Value<String> path,
  Value<String?> label,
  Value<bool> enabled,
  Value<int> priority,
});

class $$StorageLocationsTableFilterComposer
    extends Composer<_$AppDatabase, $StorageLocationsTable> {
  $$StorageLocationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get path => $composableBuilder(
      column: $table.path, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get label => $composableBuilder(
      column: $table.label, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get priority => $composableBuilder(
      column: $table.priority, builder: (column) => ColumnFilters(column));
}

class $$StorageLocationsTableOrderingComposer
    extends Composer<_$AppDatabase, $StorageLocationsTable> {
  $$StorageLocationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get path => $composableBuilder(
      column: $table.path, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get label => $composableBuilder(
      column: $table.label, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get priority => $composableBuilder(
      column: $table.priority, builder: (column) => ColumnOrderings(column));
}

class $$StorageLocationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $StorageLocationsTable> {
  $$StorageLocationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);
}

class $$StorageLocationsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $StorageLocationsTable,
    StorageLocation,
    $$StorageLocationsTableFilterComposer,
    $$StorageLocationsTableOrderingComposer,
    $$StorageLocationsTableAnnotationComposer,
    $$StorageLocationsTableCreateCompanionBuilder,
    $$StorageLocationsTableUpdateCompanionBuilder,
    (
      StorageLocation,
      BaseReferences<_$AppDatabase, $StorageLocationsTable, StorageLocation>
    ),
    StorageLocation,
    PrefetchHooks Function()> {
  $$StorageLocationsTableTableManager(
      _$AppDatabase db, $StorageLocationsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StorageLocationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StorageLocationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StorageLocationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> path = const Value.absent(),
            Value<String?> label = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<int> priority = const Value.absent(),
          }) =>
              StorageLocationsCompanion(
            id: id,
            path: path,
            label: label,
            enabled: enabled,
            priority: priority,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String path,
            Value<String?> label = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<int> priority = const Value.absent(),
          }) =>
              StorageLocationsCompanion.insert(
            id: id,
            path: path,
            label: label,
            enabled: enabled,
            priority: priority,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$StorageLocationsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $StorageLocationsTable,
    StorageLocation,
    $$StorageLocationsTableFilterComposer,
    $$StorageLocationsTableOrderingComposer,
    $$StorageLocationsTableAnnotationComposer,
    $$StorageLocationsTableCreateCompanionBuilder,
    $$StorageLocationsTableUpdateCompanionBuilder,
    (
      StorageLocation,
      BaseReferences<_$AppDatabase, $StorageLocationsTable, StorageLocation>
    ),
    StorageLocation,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$LibraryItemsTableTableManager get libraryItems =>
      $$LibraryItemsTableTableManager(_db, _db.libraryItems);
  $$WatchHistoryTableTableManager get watchHistory =>
      $$WatchHistoryTableTableManager(_db, _db.watchHistory);
  $$SubtitleAttemptsTableTableManager get subtitleAttempts =>
      $$SubtitleAttemptsTableTableManager(_db, _db.subtitleAttempts);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$SavedTitlesTableTableManager get savedTitles =>
      $$SavedTitlesTableTableManager(_db, _db.savedTitles);
  $$StorageLocationsTableTableManager get storageLocations =>
      $$StorageLocationsTableTableManager(_db, _db.storageLocations);
}
