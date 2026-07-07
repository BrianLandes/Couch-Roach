import 'package:json_annotation/json_annotation.dart';

part 'subtitle_result.g.dart';

/// A downloadable subtitle file within a search result.
@JsonSerializable()
class SubtitleFile {
  SubtitleFile({required this.fileId, this.fileName});

  @JsonKey(name: 'file_id')
  final int fileId;

  @JsonKey(name: 'file_name')
  final String? fileName;

  factory SubtitleFile.fromJson(Map<String, dynamic> json) =>
      _$SubtitleFileFromJson(json);
  Map<String, dynamic> toJson() => _$SubtitleFileToJson(this);
}

/// The attributes of a subtitle search hit (OpenSubtitles `/subtitles`).
@JsonSerializable()
class SubtitleAttributes {
  SubtitleAttributes({
    this.language,
    this.downloadCount = 0,
    this.hearingImpaired = false,
    this.fromTrusted = false,
    this.release,
    this.files = const [],
  });

  final String? language;

  @JsonKey(name: 'download_count', defaultValue: 0)
  final int downloadCount;

  @JsonKey(name: 'hearing_impaired', defaultValue: false)
  final bool hearingImpaired;

  @JsonKey(name: 'from_trusted', defaultValue: false)
  final bool fromTrusted;

  final String? release;
  final List<SubtitleFile> files;

  factory SubtitleAttributes.fromJson(Map<String, dynamic> json) =>
      _$SubtitleAttributesFromJson(json);
  Map<String, dynamic> toJson() => _$SubtitleAttributesToJson(this);
}

/// One subtitle search result.
@JsonSerializable(explicitToJson: true)
class SubtitleResult {
  SubtitleResult({required this.id, required this.attributes});

  final String id;
  final SubtitleAttributes attributes;

  /// The primary downloadable file id, if any.
  int? get fileId =>
      attributes.files.isNotEmpty ? attributes.files.first.fileId : null;

  factory SubtitleResult.fromJson(Map<String, dynamic> json) =>
      _$SubtitleResultFromJson(json);
  Map<String, dynamic> toJson() => _$SubtitleResultToJson(this);
}

/// The `/subtitles` search response envelope.
@JsonSerializable(explicitToJson: true)
class SubtitleSearchResponse {
  SubtitleSearchResponse({this.data = const []});

  final List<SubtitleResult> data;

  factory SubtitleSearchResponse.fromJson(Map<String, dynamic> json) =>
      _$SubtitleSearchResponseFromJson(json);
  Map<String, dynamic> toJson() => _$SubtitleSearchResponseToJson(this);
}
