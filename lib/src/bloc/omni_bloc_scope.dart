import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../errors/omni_route_exception.dart';
import 'omni_bloc.dart';

/// Makes [registry] and its global Blocs available below. `OmniApp` inserts
/// this once above the router; it is public for tests and custom setups.
class OmniGlobalBlocScope extends StatelessWidget {
  const OmniGlobalBlocScope({
    super.key,
    required this.registry,
    required this.child,
  });

  final OmniBlocRegistry registry;
  final Widget child;

  static OmniBlocRegistry registryOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RegistryScope>()?.registry ??
      OmniBlocRegistry.empty;

  @override
  Widget build(BuildContext context) {
    final providers = registry.globalProviders();
    final inner = providers.isEmpty
        ? child
        : MultiBlocProvider(providers: providers, child: child);
    return _RegistryScope(registry: registry, child: inner);
  }
}

class _RegistryScope extends InheritedWidget {
  const _RegistryScope({required this.registry, required super.child});
  final OmniBlocRegistry registry;
  @override
  bool updateShouldNotify(_RegistryScope old) => old.registry != registry;
}

/// Provides a screen's [provide] list above [child]. Used by OmniRoute's
/// page builder so Blocs exist before the screen's own `build`/`initState`.
///
/// Blocs are created once per element: rebuilds do not recreate them, and
/// owned Blocs are closed by flutter_bloc when this widget is unmounted.
class OmniBlocScope extends StatelessWidget {
  const OmniBlocScope({super.key, required this.provide, required this.child});

  final List<Provide> provide;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (provide.isEmpty) return child;
    final seen = <Type>{};
    for (final p in provide) {
      if (!seen.add(p.type)) {
        throw OmniRouteException(
          OmniErrorCode.duplicateBlocRegistration,
          '${p.type} appears twice in one provide list.',
        );
      }
    }
    final registry = OmniGlobalBlocScope.registryOf(context);
    return MultiBlocProvider(
      providers: [for (final p in provide) p.toProvider(registry)],
      child: child,
    );
  }
}
