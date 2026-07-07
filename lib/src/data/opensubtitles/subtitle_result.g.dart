// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'subtitle_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SubtitleFile _$SubtitleFileFromJson(Map<String, dynamic> json) => SubtitleFile(
      fileId: (json['file_id'] as num).toInt(),
      fileName: json['file_name'] as String?,
    );

Map<String, dynamic> _$SubtitleFileToJson(SubtitleFile instance) =>
    <String, dynamic>{
      'file_id': instance.fileId,
      'file_name': instance.fileName,
    };

SubtitleAttributes _$SubtitleAttributesFromJson(Map<String, dynamic> json) =>
    SubtitleAttributes(
      language: json['language'] as String?,
      downloadCount: (json['download_count'] as num?)?.toInt() ?? 0,
      hearingImpaired: json['hearing_impaired'] as bool? ?? false,
      fromTrusted: json['from_trusted'] as bool? ?? false,
      release: json['release'] as String?,
      files: (json['files'] as List<dynamic>?)
              ?.map((e) => SubtitleFile.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$SubtitleAttributesToJson(SubtitleAttributes instance) =>
    <String, dynamic>{
      'language': instance.language,
      'download_count': instance.downloadCount,
      'hearing_impaired': instance.hearingImpaired,
      'from_trusted': instance.fromTrusted,
      'release': instance.release,
      'files': instance.files,
    };

SubtitleResult _$SubtitleResultFromJson(Map<String, dynamic> json) =>
    SubtitleResult(
      id: json['id'] as String,
      attributes: SubtitleAttributes.fromJson(
          json['attributes'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$SubtitleResultToJson(SubtitleResult instance) =>
    <String, dynamic>{
      'id': instance.id,
      'attributes': instance.attributes.toJson(),
    };

SubtitleSearchResponse _$SubtitleSearchResponseFromJson(
        Map<String, dynamic> json) =>
    SubtitleSearchResponse(
      data: (json['data'] as List<dynamic>?)
              ?.map((e) => SubtitleResult.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$SubtitleSearchResponseToJson(
        SubtitleSearchResponse instance) =>
    <String, dynamic>{
      'data': instance.data.map((e) => e.toJson()).toList(),
    };
