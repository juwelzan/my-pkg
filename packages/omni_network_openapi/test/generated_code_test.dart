import 'package:omni_network/omni_network.dart';
import 'package:test/test.dart';

import 'golden/petstore.g.dart';

/// The golden output compiles and works against OmniNetwork.
void main() {
  late OmniMock mock;
  late OmniNetwork api;
  final petJson = {
    'id': 7,
    'name': 'Rex',
    'class': 'dog',
    'status': 'sold-out',
    'created_at': '2026-01-02T03:04:05.000Z',
    'weight': 12,
    'tags': ['a'],
    'owner': {'name': 'Ana', 'since': '2025-01-01T00:00:00.000Z'},
    'history': [
      {'at': '2026-01-01T00:00:00.000Z', 'note': 'vet'},
    ],
    'extra': {'k': 1},
    'variant': 3,
  };

  setUp(() {
    mock = OmniMock(basePath: '/v1')
      ..get('/pets', (_) => MockResponse.json([petJson]))
      ..get(
        '/pets/{petId}',
        (r) => MockResponse.json({
          ...petJson,
          'id': int.parse(r.pathParams['petId']!),
        }),
      )
      ..post(
        '/pets',
        (r) => MockResponse.json({
          ...petJson,
          ...r.json! as Map<String, Object?>,
        }, status: 201),
      )
      ..delete('/pets/{petId}', (_) => const MockResponse.status(204))
      ..get('/stats', (_) => MockResponse.json({'available': 2}));
    api = OmniNetwork(
      baseUrl: 'https://petstore.example.com/v1',
      transport: mock,
    );
  });
  tearDown(() => api.close());

  test('models decode and re-encode losslessly', () async {
    final pets = await api.call(PetStoreApi.listPets, query: {'limit': 1});
    final p = pets.single;
    expect(
      (p.id, p.name, p.class$, p.status),
      (7, 'Rex', 'dog', PetStatus.soldOut),
    );
    expect(p.createdAt, DateTime.utc(2026, 1, 2, 3, 4, 5));
    expect(p.weight, 12.0);
    expect(p.owner!.since!.year, 2025);
    expect(p.history!.single.note, 'vet');
    expect(p.variant, 3);
    final again = Pet.fromJson(p.toJson());
    expect(again.toJson(), p.toJson());
    expect(p.toJson()['status'], 'sold-out');
    expect(p.toJson().containsKey('vaccinated'), isFalse);
  });

  test('endpoints: path params, bodies, void and maps', () async {
    expect(
      (await api.call(PetStoreApi.showPetById, path: {'petId': 42})).id,
      42,
    );
    final created = await api.call(
      PetStoreApi.createPet,
      body: const NewPet(name: 'Tom', status: PetStatus.n2x).toJson(),
    );
    expect((created.name, created.status), ('Tom', PetStatus.n2x));
    // ignore: deprecated_member_use_from_same_package
    await api.call(PetStoreApi.deletePet, path: {'petId': 1});
    expect(await api.call(PetStoreApi.getStats), {'available': 2});
    expect(PetStoreApi.registry.all, hasLength(6));
    expect(
      PetStoreApi.registry.match(HttpMethod.get, '/pets/9'),
      same(PetStoreApi.showPetById),
    );
  });

  test('unknown enum values fail clearly', () {
    expect(() => PetStatus.fromJson('lost'), throwsFormatException);
  });
}
