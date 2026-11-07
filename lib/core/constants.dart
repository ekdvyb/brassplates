import 'package:flutter/material.dart';

class AppInfo {
  static const name = 'BRASSPLATES';
  static const tagline = 'Local-first. Encrypted. Yours.';
  static const publisher = 'ZEROBUG INC';
  static const packageId = 'com.zerobug.brassplates';
  static const version = '1.0.0';
  static const website = 'https://github.com/ekdvyb/brassplates';
  static const description =
      'BRASSPLATES is a local-first, end-to-end-encrypted personal IT workspace. '
      'Never lose your notes, how-tos, diagrams, tasks or server inventory again.';
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

const howToCategories = <String>[
  'SQL',
  'Network',
  'Servers',
  'FDMS',
  'Trading',
  'Active Directory',
  'Nextcloud',
  'Other',
];

const defaultTags = <String>[
  '#SQL',
  '#FDMS',
  '#Trading',
  '#Network',
  '#Diagrams',
];

const noteTemplates = <String, String>{
  'Blank note': '',
  'Server Setup':
      '## Server details\n\n- Hostname:\n- IP:\n- Purpose:\n\n## Steps\n\n1. ',
  'Incident Report': '## Summary\n\n## Impact\n\n## Timeline\n\n## Root cause\n\n## Resolution',
  'Daily Trading Check': '## Pre-open checks\n\n- [ ] Data feeds online\n- [ ] FDMS healthy\n- [ ] Backups verified\n',
  'How-To Draft': '## Goal\n\n## Prerequisites\n\n## Steps\n\n1. ',
};

/// Seed servers are examples only; users can edit or remove them.
const seedServers = <List<String>>[
  ['SQL-FDMS-01', '10.20.0.11', 'FDMS_PROD', 'fdms'],
  ['SQL-FDMS-02', '10.20.0.12', 'FDMS_REPORT', 'fdms'],
  ['SQL-TRD-01', '10.20.1.11', 'TRADING', 'trading'],
  ['SQL-TRD-02', '10.20.1.12', 'TRADING_ARCHIVE', 'trading'],
  ['SQL-AD-01', '10.20.2.11', 'AD_SUPPORT', 'other'],
];
