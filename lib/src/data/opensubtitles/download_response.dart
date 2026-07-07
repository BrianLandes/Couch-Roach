import 'package:json_annotation/json_annotation.dart';

part 'download_response.g.dart';

/// Response from OpenSubtitles `/download`: a temporary link plus the daily
/// quota state (used by the quota-aware queue).
@JsonSerializable()
class DownloadResponse {
  DownloadResponse({
    required this.link,
    this.fileName,
    this.requests,
    this.remaining,
    this.message,
    this.resetTime,
  });

  final String link;

  @JsonKey(name: 'file_name')
  final String? fileName;

  /// Downloads used today.
  final int? requests;

  /// Downloads remaining today.
  final int? remaining;

  final String? message;

  @JsonKey(name: 'reset_time')
  final String? resetTime;

  factory DownloadResponse.fromJson(Map<String, dynamic> json) =>
      _$DownloadResponseFromJson(json);
  Map<String, dynamic> toJson() => _$DownloadResponseToJson(this);
}
