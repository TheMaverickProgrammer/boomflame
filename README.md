# Boomflame
Providing **extendable** animations for [Flame][FLAME] game engine.

![boomflame_logo](./branding/banner_medium.png)

- [Boomflame](#boomflame)
  - [Getting Started](#getting-started)
    - [Playing Animations](#playing-animations)
    - [Changing Animations](#changing-animations)
    - [Complex Animations (Nodes)](#complex-animations-nodes)
    - [Special Animation Events](#special-animation-events)
      - [On Specific Frames](#on-specific-frames)
    - [Attributes](#attributes)
      - [Animation State Attributes](#animation-state-attributes)
      - [Frame State Attributes](#frame-state-attributes)
        - [Going Further](#going-further)
    - [Frame Perfect Games](#frame-perfect-games)
  - [Terms](#terms)

## Getting Started
 
Boomsheets is an animation document format intended to be easily
read or written by anyone without technical knowledge or proprietary tooling.
Unlike other formats, it's intended to be open source and **extended**.

> [!NOTE]
> This means anyone can write an animation document with a plain text editor
> or generate them from their own tools.

The underlining spec enables **extension** with the help of meta-elements
called [`Attributes`](#Attributes). These elements begin with the `@` symbol
and can be used to trigger custom behavior without corrupting the playback and 
without making any code changes.

> [!TIP]
> To learn more about Boomsheets documents and format, 
> visit the [repo][BMS_URL].

### Playing Animations
Getting started is easy. `AnimationComponent` expects a `SpriteComponent` 
and the animation document to load and parse. This component will be a child
of the parent `SpriteComponent` and modify its parent when keyframes change.

```dart
// This import will be used for all following examples
import 'package:boomflame/boomflame.dart' as bf;

late SpriteComponent player;
late AnimationComponent playerAnim;

add(player = SpriteComponent(
    sprite: await Sprite.load('player.png'),
    children: [
        playerAnim = bf.AnimationComponent.framebased(
            'player.anim',
            state: 'dancing',
        )
    ],
));
```

And that's it! 

To understand why this is so simple, the constructor is doing a lot for us.

```dart
AnimationComponent(
    this.src, {
    String? state,
    String? prefix,
    AssetsCache? cache,
    this.stateNameSensitivity = CaseSensitivity.insensitive,
    this.mode = Mode.forward,
  })
```

`state` is the first animation in the document that you want to see on screen.
By default, all animation documents are stored under `/assets/anims/` but can
be changed directly by changing `AnimationComponent.prefix` and providing a 
different asset manager in the constructor.
`mode` tells the component how to play the animation and can be changed at
any time.

> [!TIP] 
> `Mode` enums can be combined using bitwise operators. 
> For example `Mode.reverse | Mode.loop` will loop the animation
> while playing it in reverse.

### Changing Animations
Changing animations is also simple.

```dart
if(isRunning) {
    playerAnim.setState('run', refresh: true);
}
```

Note the behavior of `refresh`.
If set to true, it will recalculate `currKeyframe` data,
apply itself to `player` sprite, and forces the `SpriteComponent` to
update its bounds and orientation before drawing. 

> [!WARNING]
> By default `refresh` is **false** out of caution. 
> Your game logic may change state multiple times before the draw call.
> Only set `refresh` to **true** if you expect the next frame to be visible
> by the time it is displayed on screen in the next draw. 

> [!TIP]
> If you need further control when to recalculate the frame,
> an explicit call to `refresh()` can be invoked.

```dart
  /// On success, sets the [currAnim] animation state.
  /// Optionally set [frame] to jump to a keyframe in that state.
  /// Default [mode] is [Mode.forward] and overwrites the previous value.
  /// If [refresh] param is true, [AnimationComponent.refresh] will run after.
  void setState(String state, {int? frame, Mode? mode, bool refresh = false});
```

### Complex Animations (Nodes)
Some sprites are split into multiple pieces to reduce texture complexity.
Some sprites are complicated and have multiple moving parts.
Some games may need to attach sprites in order to show the player which weapon
is equiped or what gear they are wearing.

Whatever your case may be, Boomsheets has a special element `point` which
tells each keyframe element the (x,y) pair it is from the origin and its name.

Using point data is easy. Let's see how we might attach a sword to our
hero's base sprite, right onto their hand coordinate:

```dart
final String rarity = 'common';

// Add a new sword sprite to the player sprite
await player.add(sword = SpriteComponent(
    sprite: await Sprite.load('swords_atlas.png'),
    children: [
        // Our sword atlas has many sword variations.
        // We want only the matching rarity state.
        swordsAnim = bf.AnimationComponent(
            'swords_atlas.anim',
            state: '$rarity_sword',
        )
    ],
));

// Stay in sync with parent AnimationComponent at the
// point named 'hand'.
playerAnim.syncPoint('hand', swordsAnim);
```

It's really that simple. `swordsAnim` is now in a list of children
of `playerAnim`. It will synchronize its time to the parent component's
amd update the anchor as well, relative to its parent's latest origin.

> [!NOTE]
> Every `AnimationComponent` can only have one parent at a time.

### Special Animation Events
You may want to trigger functions when some frames are freshly
displayed on screen for the first time, or has finished animating.

For example, you may want to make an explosion play a sound on the first frame
and delete itself from the game world when it completes.

```dart
// class Explosion
  @override
  void update(double dt) {
    super.update(dt);

    // Remember to always check if you have a valid state and document!
    if(anim.currKeyframe == null) return;

    if(anim.currKeyframe!.newThisFrame) {
        FlameAudio.play("kaboom.wav");
    }
  }
```

`newThisFrame` gaurantees that it will only be true when the keyframe data is
retrieved and stored into `currKeyframe`. Any subsequent call to `update(dt)`
will set this flag to **false**, event if the `mode` is set to `Mode.stop`.

Now let's remove the explosion after the animation has fully completed:
```dart
// class Explosion
  @override
  void update(double dt) {
    super.update(dt);

    //
    // same code here as before
    //

    if(anim.currKeyframe!.endedThisFrame) {
        removeFromParent();
    }
  }
```

Again with `endedThisFrame` we have the same gaurantees as before. Effortless!

#### On Specific Frames
Some animations impact the user's experience on specific keyframes.
For example, you may have a player animation with their foot making contact
on the fourth and eighth keyframe in the `Run` state. At that moment, you want
to play a footstep sound to increase immersion, but __only__ the first time the
foot has made contact with the ground! Otherwise the sound will repeat every
call to `update(dt)`! This is trivial with `AnimationComponent`.

```dart
if (stateIsRunning) {
    playerAnim.mode = bf.Mode.loop;
    final keyframeIndex = playerAnim.currKeyframe!.index;
    final newThisFrame = playerAnim.currKeyframe!.newThisFrame;

    if (newThisFrame) {
        switch (keyframeIndex) {
        case 4 || 8:
            FlameAudio.play("step.wav");
        }
    }
}
```

### Attributes
Your animation documents can contain meta-elements that have additional data.
Per the [underlining][YES_URL] spec, these elements must come _before_ the 
elements they affect and can be stacked in a row. 

This implies you can have many attributes and even multiples of the same name!

> [!TIP]
> This is useful for many reasons. Consider if your game has custom behavior
> that should happen when a frame is first displayed on the screen.

#### Animation State Attributes
Consider a custom level editor for your game. You may want to expose all the
animations that a player can choose from for one of the entities but you don't
want to expose animations that could break the level or should only be present
under special conditions, like a power-up. Here's how our `player_sheet.anim`
document might look like:

```r
# Note that we're omitting frame data in this document to be brief

@expose
anim super_jumpman_small_run
frame ...
frame ...

@expose
anim super_jumpman_big_run
frame ...
frame ...

anim super_jumpman_die
frame ...
frame ...
frame ...
frame ...
```

We can name our attributes anything. In this example, we have decided to expose
only the animations with `@expose` in to the editor. Here's how to code that:

```dart
game.uiLayer.states.set(
    playerAnim
        .doc?
        .states
        .values
        .toList()
        .where(
            (state)=>state.attrs.firstWithName('expose') != null
        )
    );
```

`firstWithName` is a special extension for `List<Attribute>` types only.
It returns `Attribute?` and will be `null` if the state element did not
have an attribute with that name.

#### Frame State Attributes

Attributes can also have their own sets of keys and arguments. 
In the previous example, our attribute only had a name and nothing else.
This is fine for simple use cases, but in larger projects, it is essential
to provide meaningful values such as booleans, numbers, or strings.

> [!NOTE] 
> Internally, all parsed values for keys are strings.
> Use `getKeyValue`, `getKeyValueAsInt`, `getKeyValueAsDouble`, 
> or `getKeyValueAsBool` to convert them to the proper type.

Let's see how we can use attributes to create new behavior for our frames
that we can inspect and act on in our game!

```r
# fighters/blackbelt_yuki.anim
anim charge_punch
@play_sound charge.wav volume=0.5
frame ...
frame ...
frame ...
@play_sound charge_complete.wav volume=0.5
@play_sound "karate yell.wav"
frame ...
```

In this example, we have a charging hard punch animation that plays a sound
when the animation begins and plays a chime when the charge is complete.

> [!TIP]
> We can read these attributes in our code to do what we want. And if
> we decide we should change the sound, volume, or even the frames they occur 
> on, we can open the text file and change the properties there without fuss.

Here's how adjustable volume could be implemented in your own game:

```dart
// class BaseFighter
@override
void update(double dt) {
    super.update(dt);

    if(anim?.currKeyframe == null) return;

    final attrs = anim!.currKeyframe!.data.attrs;
    final sfxList = attrs.allWithName('play_sound');

    for(final sfx in sfxList) {
        if(sfx.args.isEmpty) continue;
        final path = sfx.args[0];
        final volume = sfx.getKeyValueAsDouble('volume', 1.0);
        FlameAudio.play(path, volume: volume);
    }
}
```

> [!NOTE]
> The extension `allWithName` for `List<Attribute>` is provided to return every
> attribute with the same name. 

In our competitive fighter game example above,
we may have multiple sound effects playing on the same frame, so we support
this by iterating over all attributes `play_sound` instead of just one.

Attributes can have any number of arguments; called key-values or `KeyVal`s.
Named `KeyVal`s can be written in any order, but when we mix them with nameless
keys, we need to be careful and ensure all necessary values are present.

> [!IMPORTANT]
> In the previous example, notice that the first argument to `play_sound`
> attribute does not have a key. This is a "nameless" keyvalue. 
> Like named keyvals, we can have any number of them, but we must fetch
> such keys by index and convert the value ourselves.

##### Going Further
We can take this fighting game further by supporting attributes such as 
`@hitbox name, x, y, w, h` which we can stack on one keyframe in order
to represent all of the hit zones possible. Very powerful!

### Frame Perfect Games
While the underlining specification of the Boomsheets document uses frames,
they can be used with elapsed seconds which Flame uses in `update(dt)`.

Internally, `AnimationComponent` keeps both types of clocks: `Frametime` and
`Duration`. The former is syntatical sugar over an `int` type, while the latter
is what is used to convert `double dt` in `update(dt)` while preserving as much
precision as possible. But since `double` is a floating-point primitive,
it can be victim to drift and cause inaccuracies. For most people, this is a
non-issue and can be ignored. But for some, every frame counts.

If you're working with frame-perfect animations, there exists a special
constructor for you: `AnimationComponent.framebased(...)` as seen in the first
example. Internally, these components ignore `dt` and instead use `tick()`.
This means you must make sure your game's main loop is also limited to the
framerate you want, otherwise it will animate too quickly and at different
speeds on other people's devices!

## Terms
There are some new terms and ideas here to get adjusted to. 
They are provided here to help.

|Term|Explanation|
|:-:|:-|
|Document|A file or string buffer representing a collection of animation states and their keyframe data. Usually ends with `.anim` suffix.|
|Anim|A class in Dart representing a collection of keyframe data and attributes.|
|State|A named collection of keyframes in the animation document. Sometimes it is more convenient to describe the currently playing animation as a "state" to distinguish from animation "files". In the library, `Anim` class **is** the state plus other properties such as `totalDuration` which is used during playback.|
|Keyframe|A specific frame entry that begins a new subregion from the source texture atlas over a duration of time.
|frame|A measurement of time. A frame advances by one every `tick()`. This term is not related to `Keyframe` which represents subregion data in an animation state.|
|tick|A singular update in Flame with the absence of delta time. Delta time or `dt` for short is useful for simulations, physics-based algorithms, and network games to blend animations together to hide jitter or lag. Delta time causes trouble for frame-sensitive applications such as deterministic online fighter games, retro games, and network games. Yes, delta time can be used to _blend_ network game visuals to smooth latency, but network game _state_ should rely on integer frames in order to gaurantee synchronization!|
|Attributes| Meta-data. Custom elements that can add new behavior to your animations and tools.|
|Point|A named (x,y) coordinate relative to the keyframe it is nested under.|
|Origin|The center of the sprite in a keyframe. This is synonymous with Flame component's `anchor` field.|

[YES_URL]: https://github.com/TheMaverickProgrammer/dart_yes_parser/blob/master/spec/README.md
[BMS_URL]: https://github.com/TheMaverickProgrammer/boomsheets_dart
[FLAME]: https://flame-engine.org/