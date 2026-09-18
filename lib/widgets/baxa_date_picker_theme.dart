import 'package:flutter/material.dart';

/// Thème à passer au `builder:` de [showDatePicker] pour obtenir le rendu
/// validé (bandeau d'en-tête plein, jour sélectionné en rond plein, «
/// aujourd'hui » cerclé, bouton de confirmation plein) — seule [accent]
/// change d'un écran à l'autre : vert sur l'accueil, indigo sur l'écran de
/// programmation d'une fermeture.
///
/// Usage :
/// ```dart
/// showDatePicker(
///   ...,
///   builder: (context, child) =>
///       Theme(data: baxaDatePickerTheme(context, _green), child: child!),
/// );
/// ```
ThemeData baxaDatePickerTheme(BuildContext context, Color accent) {
  return Theme.of(context).copyWith(
    datePickerTheme: DatePickerThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      headerBackgroundColor: accent,
      headerForegroundColor: Colors.white,
      headerHeadlineStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 24,
      ),
      headerHelpStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: Colors.white.withValues(alpha: 0.75),
      ),
      weekdayStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: accent.withValues(alpha: 0.7),
      ),
      dayForegroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? Colors.white : null,
      ),
      dayBackgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? accent : null,
      ),
      todayForegroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? Colors.white : accent,
      ),
      todayBorder: BorderSide(color: accent, width: 1.4),
      cancelButtonStyle: TextButton.styleFrom(
        foregroundColor: Colors.black54,
      ),
      confirmButtonStyle: TextButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    ),
  );
}
