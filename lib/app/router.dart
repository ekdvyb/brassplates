import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/dashboard/dashboard_screen.dart';
import '../features/diagrams/diagram_editor_screen.dart';
import '../features/diagrams/diagrams_screen.dart';
import '../features/howto/howto_detail_screen.dart';
import '../features/howto/howto_screen.dart';
import '../features/notes/note_editor_screen.dart';
import '../features/notes/notes_screen.dart';
import '../features/planning/planning_screen.dart';
import '../features/search/search_screen.dart';
import '../features/servers/servers_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/tasks/tasks_screen.dart';
import '../features/trash/trash_screen.dart';
import 'shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/dashboard',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(currentPath: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/notes',
            builder: (context, state) => const NotesScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    NoteEditorScreen(noteId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/howto',
            builder: (context, state) => const HowToScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    HowToDetailScreen(howToId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/tasks',
            builder: (context, state) => const TasksScreen(),
          ),
          GoRoute(
            path: '/planning',
            builder: (context, state) => const PlanningScreen(),
          ),
          GoRoute(
            path: '/servers',
            builder: (context, state) => const ServersScreen(),
          ),
          GoRoute(
            path: '/diagrams',
            builder: (context, state) => const DiagramsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    DiagramEditorScreen(diagramId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/search',
            builder: (context, state) => const SearchScreen(),
          ),
          GoRoute(
            path: '/trash',
            builder: (context, state) => const TrashScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});
