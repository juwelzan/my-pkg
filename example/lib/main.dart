import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:omni_route/omni_route.dart';

void main() {
  OmniRoute.usePathUrls();
  runApp(const ExampleApp());
}

// ── Blocs ─────────────────────────────────────────────────────────────
sealed class AuthEvent {}
class LoggedIn extends AuthEvent {}
class LoggedOut extends AuthEvent {}

class AuthBloc extends Bloc<AuthEvent, bool> {
  AuthBloc() : super(false) {
    on<LoggedIn>((_, emit) => emit(true));
    on<LoggedOut>((_, emit) => emit(false));
  }
}

class StudentBloc extends Bloc<String, List<String>> {
  StudentBloc() : super(const ['Rahim', 'Karim', 'Ayesha', 'Nusrat']) {
    on<String>((name, emit) => emit([...state, name]));
  }
}

class StudentDetailBloc extends Bloc<void, String> {
  StudentDetailBloc(int id) : super('Student #$id');
}

// ── Guard ─────────────────────────────────────────────────────────────
class AuthGuard extends OmniGuard {
  const AuthGuard();
  @override
  Stream<Object?> refresh(BuildContext context) => context.read<AuthBloc>().stream;
  @override
  String? redirect(BuildContext c, GoRouterState s) {
    final loggedIn = c.read<AuthBloc>().state;
    final atLogin = s.matchedLocation == '/login';
    if (!loggedIn && !atLogin) {
      return Uri(path: '/login', queryParameters: {'from': s.uri.toString()}).toString();
    }
    if (loggedIn && atLogin) return s.uri.queryParameters['from'] ?? '/dashboard';
    return null;
  }
}

// ── App ───────────────────────────────────────────────────────────────
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => OmniApp(
        initialRoute: '/dashboard',
        guards: const [AuthGuard()],
        blocs: [
          OmniBloc<AuthBloc>((_) => AuthBloc(), global: true, lazy: false),
          OmniBloc<StudentBloc>((_) => StudentBloc()),
        ],
        routes: [
          OmniPage('/login', (_) => const LoginScreen()),
          OmniStatefulShell(
            builder: (context, state, shell) => HomeShell(shell: shell),
            branches: [
              StatefulShellBranch(routes: [
                OmniPage('/dashboard', (_) => const DashboardScreen()),
              ]),
              StatefulShellBranch(routes: [
                OmniPage('/students', (_) => const StudentListScreen(), routes: [
                  OmniPage(':id', (p) => StudentDetailScreen(id: p.pathInt('id'))),
                ]),
              ]),
              StatefulShellBranch(routes: [
                OmniPage('/settings', (_) => const SettingsScreen(), routes: [
                  OmniPage('profile', (_) => const ProfileScreen()),
                ]),
              ]),
            ],
          ),
        ],
        builder: (context, router) => MaterialApp.router(
          title: 'OmniRoute Example',
          routerConfig: router,
          theme: ThemeData(colorSchemeSeed: Colors.indigo),
        ),
      );
}

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
            NavigationDestination(icon: Icon(Icons.people), label: 'Students'),
            NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      );
}

// ── Screens ───────────────────────────────────────────────────────────
class LoginScreen extends OmniStatelessWidget {
  const LoginScreen({super.key});
  @override String get screenName => 'Login';
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => context.read<AuthBloc>().add(LoggedIn()),
            child: const Text('Log in'),
          ),
        ),
      );
}

class DashboardScreen extends OmniStatefulWidget {
  const DashboardScreen({super.key});
  @override String get screenName => 'Dashboard';
  @override State<DashboardScreen> createState() => _DashboardState();
}

class _DashboardState extends OmniState<DashboardScreen> {
  int taps = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.screenName)),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Tapped $taps times (kept across tabs)'),
            TextButton(onPressed: () => setState(() => taps++), child: const Text('Tap')),
            TextButton(
              onPressed: () => OmniRoute.to<StudentDetailScreen>(path: {'id': '101'}),
              child: const Text('Open student 101'),
            ),
          ]),
        ),
      );
}

class StudentListScreen extends OmniStatelessWidget {
  const StudentListScreen({super.key});
  @override String get screenName => 'Students';
  @override List<Provide> get provide => const [Provide<StudentBloc>()];
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(screenName)),
        body: BlocBuilder<StudentBloc, List<String>>(
          builder: (context, students) => ListView(children: [
            for (var i = 0; i < students.length; i++)
              ListTile(
                title: Text(students[i]),
                onTap: () => OmniRoute.push('/students/${101 + i}'),
              ),
          ]),
        ),
      );
}

class StudentDetailScreen extends OmniStatelessWidget {
  const StudentDetailScreen({super.key, required this.id});
  final int id;
  @override String get screenName => 'Student';
  @override String get title => 'Student $id';
  @override List<Provide> get provide => [Provide<StudentDetailBloc>.create((_) => StudentDetailBloc(id))];
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(child: Text(context.watch<StudentDetailBloc>().state)),
      );
}

class SettingsScreen extends OmniStatelessWidget {
  const SettingsScreen({super.key});
  @override String get screenName => 'Settings';
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(screenName)),
        body: ListView(children: [
          ListTile(title: const Text('Profile'), onTap: () => OmniRoute.go('/settings/profile')),
          ListTile(
            title: const Text('Log out'),
            onTap: () => context.read<AuthBloc>().add(LoggedOut()),
          ),
        ]),
      );
}

class ProfileScreen extends OmniStatelessWidget {
  const ProfileScreen({super.key});
  @override String get screenName => 'Profile';
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(screenName)),
        body: const Center(child: Text('Profile')),
      );
}
