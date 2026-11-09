import 'package:flutter/material.dart';

import '../../../domain/models/catalog_definition.dart';

IconData catalogIcon(String key) => switch (key) {
      'diagnosis' => Icons.medical_information_outlined,
      'procedure' => Icons.healing_outlined,
      'tcm' => Icons.spa_outlined,
      'pathology' => Icons.biotech_outlined,
      'legal' => Icons.gavel_outlined,
      _ => Icons.bookmark_outline,
    };

Color catalogColor(CatalogDefinition? definition, ThemeData theme) {
  if (definition != null && definition.color != 0) {
    return Color(definition.color);
  }
  return theme.colorScheme.primary;
}
