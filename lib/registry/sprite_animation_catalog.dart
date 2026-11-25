import 'dart:ui' as ui;

enum SpriteMotion { idle, run, attack }

class SpriteFrame {
  final ui.Image image;
  final ui.Rect source;
  final ui.Offset anchor;
  final double worldHeight;

  const SpriteFrame({
    required this.image,
    required this.source,
    this.anchor = const ui.Offset(.5, 1),
    this.worldHeight = 50,
  });
}

class SpriteClip {
  final List<SpriteFrame> frames;
  final double frameDuration;
  final bool loop;

  SpriteClip(List<SpriteFrame> frames, this.frameDuration, {required this.loop})
    : assert(frames.isNotEmpty),
      assert(frameDuration > 0 && frameDuration.isFinite),
      frames = List.unmodifiable(frames);

  double get duration => frames.length * frameDuration;

  SpriteFrame frameAt(double elapsed, {double? normalizedProgress}) {
    if (frames.length == 1) return frames.first;
    if (normalizedProgress != null) {
      final progress = normalizedProgress.isNaN ? 0.0 : normalizedProgress;
      final index = (progress.clamp(0.0, 1.0) * frames.length).floor();
      return frames[index.clamp(0, frames.length - 1)];
    }
    if (elapsed.isNaN || elapsed <= 0) return frames.first;
    if (!elapsed.isFinite || (!loop && elapsed >= duration)) return frames.last;
    final position = loop ? elapsed % duration : elapsed;
    return frames[(position / frameDuration).floor().clamp(
      0,
      frames.length - 1,
    )];
  }
}

class HeroSpriteSet {
  final SpriteClip idle, run, attack;

  const HeroSpriteSet({
    required this.idle,
    required this.run,
    required this.attack,
  });
}

// Coordinates are original PNG pixels. Body anchors are the planted-foot
// baseline, measured independently of a weapon, cape or incorporated effect.
class SpriteRegion {
  final String path;
  final double left, top, right, bottom;
  ui.Rect get source => ui.Rect.fromLTRB(left, top, right, bottom);
  final double anchorX, anchorY, worldHeight;
  final int? backdrop;
  final int tolerance;
  final bool mirror;
  final List<ui.Rect> exclusions;
  final List<List<ui.Offset>> exclusionPolygons;

  const SpriteRegion(
    this.path,
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.anchorX,
    this.anchorY,
    this.worldHeight,
    this.backdrop,
    this.tolerance, {
    this.mirror = false,
    this.exclusions = const [],
    this.exclusionPolygons = const [],
  });
}

class SpriteClipSpec {
  final List<SpriteRegion> frames;
  final double interval;
  final bool loop;

  const SpriteClipSpec(this.frames, this.interval, {this.loop = false});
}

typedef HeroClipSpecs = ({
  SpriteClipSpec idle,
  SpriteClipSpec run,
  SpriteClipSpec attack,
});

const _heroes = 'assets/images/heroes';
const _skills = 'assets/images/skills';
const _nova = '$_heroes/nova_blade/nova_blade_sheet.png';
const _shadow = '$_heroes/shadow/shadow_01_sheet.png';
const _ember = '$_heroes/ember/ember_02_sheet.png';
const _valeria = '$_heroes/valenria/valeria_sheet.png';
const _garrick = '$_heroes/garrick/garrick_sheet.png';
const _kaelen = '$_heroes/kaelen/kaelen_sheet.png';
const _cyber = '$_skills/cyber_skill_effects.png';
const _valeriaSkills = '$_skills/valeria_skills.png';
const _novaFx = '$_skills/nova_energy_slash.png';
const _novaDash = '$_skills/nova_shadow_dash.png';
const _novaBurst = '$_skills/nova_quantum_burst.png';
const _storm = '$_skills/kaelen_storm_vortex.png';
const _dark = 0x0d1015;
const _slate = 0x141a26;
const _navy = 0x0d1736;
const _violet = 0x0d1046;
const _emberNavy = 0x0c1039;
const _cyberNavy = 0x02144a;

const nativeIdlePaths = {
  'nova_blade': '$_heroes/nova/nova.png',
  'ember_02': '$_heroes/ember/Ember-idle.png',
  'shadow_01': '$_heroes/shadow/idle/01.png',
};

const nativeRunPaths = {
  'nova_blade': '$_heroes/nova/nova-run.png',
  'ember_02': '$_heroes/ember/Ember-run.png',
  'shadow_01': '$_heroes/shadow/run/01.png',
};

const nativeAttackPaths = {
  'nova_blade': '$_heroes/nova/nova-attack.png',
  'ember_02': '$_heroes/ember/Ember-attack.png',
  'shadow_01': '$_heroes/shadow/attack/01.png',
};

final shadowSequencePaths = Map<String, List<String>>.unmodifiable({
  for (final motion in SpriteMotion.values)
    motion.name: List<String>.unmodifiable([
      for (var i = 1; i <= 16; i++)
        '$_heroes/shadow/${motion.name}/${i.toString().padLeft(2, '0')}.png',
    ]),
});

final nativeHeroSpriteClips = <String, List<HeroClipSpecs>>{
  for (final id in ['nova_blade', 'ember_02'])
    id: List.unmodifiable(
      List.generate(5, (row) => _nativeAtlasClips(id, row)),
    ),
  'shadow_01': [
    (
      idle: _shadowSequence(SpriteMotion.idle, .12, 50, 1),
      run: _shadowSequence(SpriteMotion.run, .06, 50, 1),
      attack: _shadowSequence(SpriteMotion.attack, .04, 50, 1),
    ),
  ],
};

HeroClipSpecs _nativeAtlasClips(String id, int facingRow) {
  final nova = id == 'nova_blade';
  // The run sheets have separate back and side rows, plus one right diagonal.
  const runRows = [0, 5, 3, 5, 1];
  return (
    idle: _nativeAtlas(
      nativeIdlePaths[id]!,
      facingRow,
      5,
      256,
      nova ? 229 / 256 : 236 / 256,
      48,
      .18,
      loop: true,
    ),
    run: _nativeAtlas(
      nativeRunPaths[id]!,
      runRows[facingRow],
      8,
      256,
      nova ? 229 / 256 : 236 / 256,
      48,
      .065,
      loop: true,
    ),
    attack: _nativeAtlas(
      nativeAttackPaths[id]!,
      facingRow,
      5,
      512,
      nova ? 477 / 512 : 472 / 512,
      96,
      .09,
    ),
  );
}

SpriteClipSpec _nativeAtlas(
  String path,
  int row,
  int cols,
  int cell,
  double foot,
  double height,
  double interval, {
  bool loop = false,
}) {
  return SpriteClipSpec(
    [
      for (var col = 0; col < cols; col++)
        SpriteRegion(
          path,
          (col * cell).toDouble(),
          (row * cell).toDouble(),
          ((col + 1) * cell).toDouble(),
          ((row + 1) * cell).toDouble(),
          .5,
          foot,
          height,
          null,
          0,
        ),
    ],
    interval,
    loop: loop,
  );
}

SpriteClipSpec _shadowSequence(
  SpriteMotion motion,
  double interval,
  double height,
  double foot,
) {
  return SpriteClipSpec(
    [
      for (final path in shadowSequencePaths[motion.name]!)
        SpriteRegion(path, 0, 0, 256, 256, .5, foot, height, null, 0),
    ],
    interval,
    loop: motion != SpriteMotion.attack,
  );
}

const heroSpriteClips = <String, HeroClipSpecs>{
  'nova_blade': (
    idle: SpriteClipSpec(
      [
        SpriteRegion(_nova, 16, 6, 57, 74, .52, .93, 52, _navy, 29),
        SpriteRegion(_nova, 76, 7, 118, 73, .54, .94, 51, _navy, 29),
      ],
      .24,
      loop: true,
    ),
    run: SpriteClipSpec(
      [
        SpriteRegion(_nova, 136, 7, 177, 73, .53, .94, 52, _navy, 29),
        SpriteRegion(_nova, 193, 6, 234, 74, .50, .93, 53, _navy, 29),
        SpriteRegion(_nova, 136, 77, 178, 141, .50, .94, 51, _navy, 29),
        SpriteRegion(_nova, 194, 77, 236, 141, .47, .94, 51, _navy, 29),
      ],
      .10,
      loop: true,
    ),
    attack: SpriteClipSpec([
      SpriteRegion(_nova, 247, 6, 308, 74, .48, .93, 53, _navy, 30),
      SpriteRegion(
        '$_heroes/nova_blade/nova_blade_attack.png',
        6,
        12,
        55,
        70,
        .50,
        .98,
        49,
        null,
        0,
      ),
      SpriteRegion(_nova, 336, 77, 406, 142, .49, .94, 51, _navy, 31),
    ], .10),
  ),
  'shadow_01': (
    idle: SpriteClipSpec(
      [
        SpriteRegion(_shadow, 5, 5, 41, 61, .53, .95, 52, _violet, 37),
        SpriteRegion(_shadow, 46, 5, 83, 61, .52, .95, 52, _violet, 36),
      ],
      .23,
      loop: true,
    ),
    run: SpriteClipSpec(
      [
        SpriteRegion(_shadow, 130, 64, 167, 121, .52, .93, 52, _violet, 38),
        SpriteRegion(_shadow, 131, 126, 173, 180, .46, .91, 50, _violet, 44),
        SpriteRegion(_shadow, 174, 126, 211, 180, .50, .91, 50, _violet, 42),
        SpriteRegion(_shadow, 214, 126, 252, 180, .45, .91, 50, _violet, 40),
      ],
      .10,
      loop: true,
    ),
    attack: SpriteClipSpec([
      SpriteRegion(_shadow, 130, 64, 167, 121, .52, .93, 52, _violet, 38),
      SpriteRegion(_shadow, 170, 64, 214, 122, .43, .93, 53, _violet, 41),
      SpriteRegion(_shadow, 87, 124, 127, 177, .43, .95, 49, _violet, 42),
    ], .10),
  ),
  'ember_02': (
    idle: SpriteClipSpec(
      [
        SpriteRegion(_ember, 43, 5, 82, 65, .52, .92, 53, _emberNavy, 44),
        SpriteRegion(_ember, 84, 5, 125, 65, .50, .92, 53, _emberNavy, 44),
      ],
      .24,
      loop: true,
    ),
    run: SpriteClipSpec(
      [
        SpriteRegion(_ember, 125, 5, 167, 65, .47, .92, 53, _emberNavy, 44),
        SpriteRegion(_ember, 166, 5, 210, 65, .44, .92, 53, _emberNavy, 44),
      ],
      .11,
      loop: true,
    ),
    attack: SpriteClipSpec([
      SpriteRegion(_ember, 210, 65, 253, 121, .45, .94, 50, _violet, 47),
      SpriteRegion(_ember, 170, 123, 211, 181, .45, .88, 52, _violet, 49),
    ], .13),
  ),
  'valeria': (
    idle: SpriteClipSpec(
      [SpriteRegion(_valeria, 24, 17, 136, 184, .62, .98, 53, _dark, 30)],
      .25,
      loop: true,
    ),
    run: SpriteClipSpec(
      [SpriteRegion(_valeria, 184, 27, 315, 184, .58, .97, 50, _dark, 30)],
      .11,
      loop: true,
    ),
    attack: SpriteClipSpec([
      SpriteRegion(_valeria, 0, 249, 201, 419, .41, .98, 54, _dark, 30),
      SpriteRegion(
        '$_heroes/valenria/valeria_attack.png',
        0,
        17,
        190,
        170,
        .39,
        .99,
        52,
        _dark,
        29,
      ),
    ], .15),
  ),
  'garrick': (
    idle: SpriteClipSpec(
      [SpriteRegion(_garrick, 24, 18, 138, 182, .54, .98, 53, _dark, 29)],
      .25,
      loop: true,
    ),
    run: SpriteClipSpec(
      [SpriteRegion(_garrick, 191, 37, 324, 182, .46, .98, 49, _dark, 29)],
      .11,
      loop: true,
    ),
    attack: SpriteClipSpec([
      SpriteRegion(_garrick, 3, 254, 164, 426, .46, .99, 56, _dark, 28),
      SpriteRegion(
        '$_heroes/garrick/garrick_attack.png',
        11,
        18,
        149,
        170,
        .45,
        .98,
        51,
        _dark,
        26,
      ),
      SpriteRegion(_garrick, 549, 21, 702, 180, .40, .99, 53, _dark, 29),
    ], .11),
  ),
  'kaelen': (
    idle: SpriteClipSpec(
      [SpriteRegion(_kaelen, 0, 11, 307, 277, .49, .99, 52, _slate, 26)],
      .25,
      loop: true,
    ),
    run: SpriteClipSpec(
      [
        SpriteRegion(
          _kaelen,
          555,
          40,
          853,
          279,
          .45,
          .98,
          52,
          _slate,
          26,
          exclusions: [
            ui.Rect.fromLTRB(802, 130, 853, 279),
            ui.Rect.fromLTRB(771, 175, 853, 279),
          ],
        ),
        SpriteRegion(
          _kaelen,
          930,
          43,
          1169,
          279,
          .42,
          .98,
          52,
          _slate,
          27,
          exclusions: [
            ui.Rect.fromLTRB(930, 43, 1030, 106),
            ui.Rect.fromLTRB(930, 198, 962, 279),
          ],
        ),
      ],
      .14,
      loop: true,
    ),
    attack: SpriteClipSpec([
      SpriteRegion(
        _kaelen,
        555,
        40,
        853,
        279,
        .48,
        .98,
        47,
        _slate,
        26,
        exclusions: [
          ui.Rect.fromLTRB(802, 130, 853, 279),
          ui.Rect.fromLTRB(771, 175, 853, 279),
        ],
      ),
      SpriteRegion(
        '$_heroes/kaelen/kaelen_attack.png',
        0,
        34,
        224,
        267,
        .58,
        .99,
        46,
        _slate,
        27,
        exclusions: [ui.Rect.fromLTRB(0, 227, 38, 267)],
      ),
      SpriteRegion(_kaelen, 537, 350, 862, 570, .49, .99, 44, _slate, 27),
    ], .11),
  ),
};

const _fireBurst = SpriteRegion(
  _cyber,
  99,
  164,
  207,
  246,
  .52,
  .68,
  110,
  0x1d1b40,
  43,
);
const _earthBurst = SpriteRegion(
  _garrick,
  528,
  255,
  702,
  427,
  .50,
  .83,
  100,
  _dark,
  36,
);

const skillSpriteClips = <String, Map<int, SpriteClipSpec>>{
  'nova_blade': {
    1: SpriteClipSpec([
      SpriteRegion(
        _novaFx,
        111,
        11,
        224,
        129,
        .55,
        .57,
        98,
        _navy,
        36,
        exclusions: [ui.Rect.fromLTRB(111, 72, 149, 111)],
      ),
    ], .32),
    2: SpriteClipSpec([
      SpriteRegion(
        _novaDash,
        106,
        0,
        230,
        99,
        .54,
        .50,
        85,
        _violet,
        42,
        exclusions: [ui.Rect.fromLTRB(106, 71, 151, 99)],
      ),
      SpriteRegion(_novaDash, 119, 125, 230, 215, .52, .57, 91, _violet, 42),
    ], .12),
    3: SpriteClipSpec([
      SpriteRegion(_novaBurst, 139, 171, 227, 236, .50, .66, 65, _violet, 42),
      SpriteRegion(
        _novaBurst,
        76,
        15,
        230,
        154,
        .61,
        .77,
        117,
        _violet,
        43,
        exclusions: [ui.Rect.fromLTRB(76, 15, 142, 73)],
      ),
      SpriteRegion(
        _novaBurst,
        4,
        124,
        139,
        246,
        .50,
        .73,
        112,
        _violet,
        48,
        exclusions: [ui.Rect.fromLTRB(84, 124, 139, 154)],
      ),
    ], .15),
  },
  'shadow_01': {
    1: SpriteClipSpec([
      SpriteRegion(_cyber, 2, 23, 59, 55, .50, .52, 33, _cyberNavy, 35),
      SpriteRegion(_cyber, 63, 18, 128, 63, .50, .50, 36, _cyberNavy, 35),
    ], .10),
    2: SpriteClipSpec([
      SpriteRegion(_cyber, 139, 15, 213, 68, .56, .53, 61, _cyberNavy, 35),
      SpriteRegion(_cyber, 137, 65, 231, 121, .50, .55, 66, _cyberNavy, 36),
    ], .13),
    3: SpriteClipSpec([
      SpriteRegion(_cyber, 344, 23, 395, 61, .51, .54, 48, _cyberNavy, 35),
      SpriteRegion(
        _cyber,
        326,
        73,
        373,
        105,
        .47,
        .50,
        44,
        _cyberNavy,
        35,
        exclusions: [ui.Rect.fromLTRB(326, 98, 336, 105)],
      ),
      SpriteRegion(_cyber, 397, 13, 438, 66, .56, .54, 57, _cyberNavy, 36),
    ], .11),
  },
  'ember_02': {
    1: SpriteClipSpec([
      SpriteRegion(_ember, 124, 130, 169, 172, .55, .53, 37, _violet, 52),
      SpriteRegion(_ember, 206, 132, 253, 172, .61, .52, 36, _violet, 51),
    ], .10),
    2: SpriteClipSpec([
      SpriteRegion(_ember, 90, 181, 134, 225, .50, .97, 61, _violet, 57),
      SpriteRegion(_ember, 46, 185, 82, 225, .49, .98, 65, 0x171b62, 61),
    ], .14),
    3: SpriteClipSpec([_fireBurst], .38),
  },
  'valeria': {
    1: SpriteClipSpec([
      SpriteRegion(
        _valeriaSkills,
        10,
        13,
        343,
        111,
        .54,
        .50,
        52,
        _dark,
        33,
        mirror: true,
      ),
    ], .33),
    2: SpriteClipSpec([
      SpriteRegion(
        _valeriaSkills,
        409,
        0,
        688,
        145,
        .51,
        .71,
        96,
        _dark,
        29,
        // The original ring panel has Valeria composited in front of both
        // rings. Erase only her silhouette; the unobstructed ring sections
        // stay intact, while the removed center is hidden by the real player.
        exclusionPolygons: [
          [
            ui.Offset(120, 0),
            ui.Offset(143, 0),
            ui.Offset(153, 5),
            ui.Offset(159, 14),
            ui.Offset(161, 24),
            ui.Offset(158, 34),
            ui.Offset(166, 41),
            ui.Offset(170, 49),
            ui.Offset(168, 58),
            ui.Offset(162, 65),
            ui.Offset(166, 73),
            ui.Offset(165, 83),
            ui.Offset(162, 94),
            ui.Offset(162, 105),
            ui.Offset(159, 116),
            ui.Offset(156, 126),
            ui.Offset(150, 137),
            ui.Offset(147, 143),
            ui.Offset(130, 145),
            ui.Offset(124, 138),
            ui.Offset(117, 130),
            ui.Offset(113, 120),
            ui.Offset(110, 110),
            ui.Offset(108, 100),
            ui.Offset(105, 90),
            ui.Offset(103, 80),
            ui.Offset(104, 71),
            ui.Offset(108, 63),
            ui.Offset(106, 55),
            ui.Offset(108, 47),
            ui.Offset(115, 40),
            ui.Offset(114, 32),
            ui.Offset(116, 23),
            ui.Offset(115, 14),
            ui.Offset(117, 6),
          ],
        ],
      ),
    ], .45),
    3: SpriteClipSpec([
      SpriteRegion(_valeriaSkills, 729, 0, 963, 145, .55, .78, 104, _dark, 32),
    ], .48),
  },
  'garrick': {
    1: SpriteClipSpec([_earthBurst], .33),
    2: SpriteClipSpec([
      SpriteRegion(_garrick, 378, 273, 526, 420, .52, .54, 78, _dark, 32),
    ], .43),
    3: SpriteClipSpec([_earthBurst, _fireBurst], .18),
  },
  'kaelen': {
    1: SpriteClipSpec([
      SpriteRegion(
        '$_skills/kaelen_thunder_flash.png',
        744,
        27,
        894,
        265,
        .52,
        .51,
        112,
        _slate,
        37,
      ),
    ], .31),
    2: SpriteClipSpec(
      [
        SpriteRegion(_storm, 16, 14, 405, 228, .49, .55, 79, _slate, 39),
        SpriteRegion(_storm, 432, 0, 826, 292, .50, .66, 113, _slate, 39),
      ],
      .15,
      loop: true,
    ),
    3: SpriteClipSpec([
      SpriteRegion(
        '$_skills/kaelen_heaven_judgment.png',
        0,
        16,
        509,
        584,
        .50,
        .84,
        150,
        _slate,
        40,
      ),
    ], .45),
  },
};
