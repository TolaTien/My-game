import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/components/companion_component.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/services/audio_service.dart';

void main() {
  setUp(() {
    final previous = AudioService.instance;
    AudioService.setInstance(MockAudioService());
    addTearDown(() => AudioService.setInstance(previous));
  });

  for (final resetForFloor in [false, true]) {
    test(
      'Replaced shield owner ${resetForFloor ? 'floor reset' : 'cleanup'} preserves the current shield',
      () {
        final player = PlayerComponent(position: Vector2.zero());
        final a = CompanionComponent(companionId: 'aegis_x9', player: player);
        final b = CompanionComponent(companionId: 'cyber_drone', player: player);
        expect(a.activateSpecialSkill(), isTrue);
        player.update(3);
        a.update(3);
        expect(b.activateSpecialSkill(), isTrue);
        expect(player.activePetShieldOwner, same(b));

        // Pass A's four-second expiry while B's 4.5-second shield remains.
        player.update(1.5);
        a.update(1.5);
        b.update(1.5);
        if (resetForFloor) {
          a.resetForFloor();
        } else {
          a.cleanup();
        }
        expect(player.goldenShieldTimer, 3);
        expect(player.temporaryPetDamageAbsorption, .45);
        expect(player.damageAbsorption, .45);
        expect(player.activePetShieldOwner, same(b));

        b.cleanup();
        expect(player.goldenShieldTimer, 0);
        expect(player.temporaryPetDamageAbsorption, 0);
        expect(player.damageAbsorption, 0);
        expect(player.activePetShieldOwner, isNull);
      },
    );
  }

  for (final shield in [
    (id: 'comp_defense', absorption: .55, duration: 5.0),
    (id: 'aegis_x9', absorption: .35, duration: 4.0),
    (id: 'cyber_drone', absorption: .45, duration: 4.5),
  ]) {
    test(
      '${shield.id} PET shield survives the visual and expires at ${shield.duration} seconds',
      () async {
        final player = PlayerComponent(position: Vector2.zero());
        final pet = CompanionComponent(companionId: shield.id, player: player);
        await pet.onLoad();
        final passive = player.damageAbsorption;
        expect(pet.activateSpecialSkill(), isTrue);

        player.update(2.6);
        pet.update(2.6);
        expect(pet.overdriveTimer, 0);
        expect(player.goldenShieldTimer, closeTo(shield.duration - 2.6, .001));
        expect(player.temporaryPetDamageAbsorption, shield.absorption);
        final hp = player.currentHp;
        player.takeDamage(40);
        expect(
          hp - player.currentHp,
          closeTo(
            40 * (1 - (passive > shield.absorption ? passive : shield.absorption)),
            .001,
          ),
        );

        final beforeExpiry = shield.duration - 2.6 - .1;
        player.update(beforeExpiry);
        pet.update(beforeExpiry);
        expect(player.temporaryPetDamageAbsorption, shield.absorption);
        player.update(.11);
        pet.update(.11);
        expect(player.goldenShieldTimer, 0);
        expect(player.temporaryPetDamageAbsorption, 0);
        expect(player.damageAbsorption, passive);
        expect(player.activePetShieldOwner, isNull);
      },
    );
  }

  for (final id in ['orbit_03', 'luna_fox']) {
    test('$id special skill does not replace another companion shield', () {
      final player = PlayerComponent(position: Vector2.zero());
      final shield = CompanionComponent(companionId: 'aegis_x9', player: player);
      final pet = CompanionComponent(companionId: id, player: player);
      expect(shield.activateSpecialSkill(), isTrue);
      expect(pet.activateSpecialSkill(), isTrue);
      expect(player.activePetShieldOwner, same(shield));
      expect(player.goldenShieldTimer, 4);
      expect(player.temporaryPetDamageAbsorption, .35);

      pet.cleanup();
      expect(player.activePetShieldOwner, same(shield));
      expect(player.goldenShieldTimer, 4);
      expect(player.damageAbsorption, .35);
      shield.cleanup();
      expect(player.activePetShieldOwner, isNull);
      expect(player.damageAbsorption, 0);
    });
  }

  for (final id in ['cyber_drone', 'aegis_x9']) {
    test(
      '$id cleanup preserves defense changed after companion creation',
      () async {
        final player = PlayerComponent(position: Vector2.zero());
        player.damageAbsorption = .1;
        final pet = CompanionComponent(companionId: id, player: player);
        await pet.onLoad();
        expect(player.damageAbsorption, id == 'cyber_drone' ? .3 : .2);
        pet.activateSpecialSkill();
        player.damageAbsorption = .4;
        pet.update(2.6);
        pet.cleanup();
        expect(player.damageAbsorption, .4);
        expect(player.goldenShieldTimer, 0);
        expect(player.temporaryPetDamageAbsorption, 0);
      },
    );
  }

  test('Inactive companion cleanup does not remove another PET shield', () {
    final player = PlayerComponent(position: Vector2.zero());
    final active = CompanionComponent(companionId: 'aegis_x9', player: player);
    final inactive = CompanionComponent(
      companionId: 'luna_fox',
      player: player,
    );
    expect(active.activateSpecialSkill(), isTrue);
    inactive.cleanup();
    expect(player.goldenShieldTimer, 4);
    expect(player.damageAbsorption, .35);
    active.resetForFloor();
    expect(player.damageAbsorption, 0);
    expect(player.temporaryPetDamageAbsorption, 0);
  });
}
