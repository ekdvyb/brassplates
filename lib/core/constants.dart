import 'package:flutter/material.dart';

class AppInfo {
  static const name = 'BRASSPLATES';
  static const tagline = 'Notes and tasks. Local-first.';
  static const packageId = 'com.zerobug.brassplates';
  static const version = '1.2.0';
  static const website = 'https://github.com/ekdvyb/brassplates';
  static const description =
      'BRASSPLATES is a local-first notes and to-do app. Your notes, tasks '
      'and pictures stay on your device; sync happens only through a folder '
      'you choose.';
}

class BrandColors {
  static const brass = Color(0xFFB5883E);
  static const brassLight = Color(0xFFD9B26A);
  static const charcoal = Color(0xFF1B1A18);
  static const charcoalSoft = Color(0xFF232120);
  static const charcoalCard = Color(0xFF2A2725);
  static const danger = Color(0xFFE05B5B);
  static const warning = Color(0xFFE0B84B);
  static const success = Color(0xFF5BBE7A);
  static const info = Color(0xFF5B8FE0);
}

const noteTemplates = <String, String>{
  'Blank note': '',
  'Checklist': '## To do\n\n- [ ] ',
  'Meeting notes': '## Notes\n\n## Decisions\n\n## Follow-ups\n\n- [ ] ',
  'Idea': '## Idea\n\n## Why it matters\n\n## Next step\n',
};
