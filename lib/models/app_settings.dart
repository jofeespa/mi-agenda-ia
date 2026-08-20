import 'dart:convert';

import 'agenda_item.dart';

class AppSettings {
  const AppSettings({
    this.defaultAlertMode = AlertMode.soundAndVibration,
    this.defaultRingtoneUri,
    this.defaultRingtoneTitle,
    this.defaultAlarmDurationSeconds = 30,
    this.defaultRepeatMinutes = 0,
    this.defaultAdvanceMinutes = 0,
  });

  final AlertMode defaultAlertMode;
  final String? defaultRingtoneUri;
  final String? defaultRingtoneTitle;
  final int defaultAlarmDurationSeconds;
  final int defaultRepeatMinutes;
  final int defaultAdvanceMinutes;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'defaultAlertMode': defaultAlertMode.name,
        'defaultRingtoneUri': defaultRingtoneUri,
        'defaultRingtoneTitle': defaultRingtoneTitle,
        'defaultAlarmDurationSeconds': defaultAlarmDurationSeconds,
        'defaultRepeatMinutes': defaultRepeatMinutes,
        'defaultAdvanceMinutes': defaultAdvanceMinutes,
      };

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    AlertMode mode;
    try {
      mode = AlertMode.values.byName(
        map['defaultAlertMode'] as String? ??
            AlertMode.soundAndVibration.name,
      );
    } on ArgumentError {
      mode = AlertMode.soundAndVibration;
    }

    return AppSettings(
      defaultAlertMode: mode,
      defaultRingtoneUri: map['defaultRingtoneUri'] as String?,
      defaultRingtoneTitle: map['defaultRingtoneTitle'] as String?,
      defaultAlarmDurationSeconds:
          map['defaultAlarmDurationSeconds'] as int? ?? 30,
      defaultRepeatMinutes: map['defaultRepeatMinutes'] as int? ?? 0,
      defaultAdvanceMinutes: map['defaultAdvanceMinutes'] as int? ?? 0,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory AppSettings.fromJson(String source) =>
      AppSettings.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
