import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/components/companion_component.dart';
import 'package:my_game/game/components/player.dart';

void main() {
  for (final resetForFloor in [false, true]) {
    test(
      'Replaced shield owner ${resetForFloor ? 'floor reset' : 'cleanup'} preserves the current shield',
      () {
        final player = PlayerComponent(position: Vector2.zero());
        final a = CompanionComponent(companionId: 'orbit_03', player: player);
        final b = CompanionComponent(companionId: 'luna_fox', player: player);
        expect(a.activateSpecialSkill(), isTrue);
        player.update(3);
        a.update(3);
        expect(b.activateSpecialSkill(), isTrue);
        expect(player.activePetShieldOwner, same(b));

        // Pass A's original expiry while B still has three seconds left.
        player.update(1);
        a.update(1);
        b.update(1);
        if (resetForFloor) {
          a.resetForFloor();
        } else {
          a.cleanup();
        }
        expect(player.goldenShieldTimer, 3);
        expect(player.temporaryPetDamageAbsorption, .25);
        expect(player.damageAbsorption, .25);
        expect(player.activePetShieldOwner, same(b));

        b.cleanup();
        expect(player.goldenShieldTimer, 0);
        expect(player.temporaryPetDamageAbsorption, 0);
        expect(player.damageAbsorption, 0);
        expect(player.activePetShieldOwner, isNull);
      },
    );
  }

  for (final id in ['orbit_03', 'luna_fox', 'aegis_x9', 'cyber_drone']) {
    test(
      '$id PET shield survives the visual and expires at four seconds',
      () async {
        final player = PlayerComponent(position: Vector2.zero());
        final pet = CompanionComponent(companionId: id, player: player);
        await pet.onLoad();
        final passive = player.damageAbsorption;
        expect(pet.activateSpecialSkill(), isTrue);

        player.update(2.6);
        pet.update(2.6);
        expect(pet.overdriveTimer, 0);
        expect(player.goldenShieldTimer, closeTo(1.4, .001));
        expect(player.temporaryPetDamageAbsorption, .25);
        final hp = player.currentHp;
        player.takeDamage(40);
        expect(
          hp - player.currentHp,
          closeTo(40 * (1 - (passive > .25 ? passive : .25)), .001),
        );

        player.update(1.3);
        pet.update(1.3);
        expect(player.temporaryPetDamageAbsorption, .25);
        player.update(.11);
        pet.update(.11);
        expect(player.goldenShieldTimer, 0);
        expect(player.temporaryPetDamageAbsorption, 0);
        expect(player.damageAbsorption, passive);
        expect(player.activePetShieldOwner, isNull);
      },
    );
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
    final active = CompanionComponent(companionId: 'orbit_03', player: player);
    final inactive = CompanionComponent(
      companionId: 'luna_fox',
      player: player,
    );
    expect(active.activateSpecialSkill(), isTrue);
    inactive.cleanup();
    expect(player.goldenShieldTimer, 4);
    expect(player.damageAbsorption, .25);
    active.resetForFloor();
    expect(player.damageAbsorption, 0);
    expect(player.temporaryPetDamageAbsorption, 0);
  });
}
