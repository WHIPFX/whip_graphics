# whip_graphics

LED streetlights and [WHIP](https://github.com/WHIPFX/txAdmin-recipe)'s look for the city's light and sky.

## Features

- **LED streetlights.** Six of GTA's streetlight models and three traffic-light poles get flat LED heads with warm
  white light. A shot lamp loses only its lit face.
- **WHIP's look.** A colour grade that follows the game's hour and weather: warm days, a rose dusk and neutral nights.
  It's strongest in clear weather and lighter in overcast, rain, fog and snow.
- **Softer light.** Highlights roll off gently, light halos are a little larger, and lights glow at night. The glow
  needs the game's Post FX setting on High or above.
- **Makes way for other effects.** While another script's timecycle modifier is on, such as a camera filter, the
  look's day and night grade waits for it.

## Requirements

- Nothing else: it doesn't use `whip_core`.
- FiveM Legacy or GTA V Enhanced. The models come twice: `stream/` for Legacy and `stream_enhanced/` for Enhanced. An
  Enhanced server needs `setr whip_platform enhanced` in `server.cfg`, so the pack uses Enhanced's version of the
  look.

## Installation

WHIP's txAdmin recipe installs it in `resources/[assets]`.

By hand, put the `whip_graphics` folder in `resources/[assets]` and add this line to `server.cfg`:

```cfg
ensure [assets]
```

It overrides those nine models, so don't run it with another mod that changes the same streetlights.

## For players

| Command | Does |
| --- | --- |
| `/ledambient` | Turns the look off and on for you, to compare with GTA's own |

## License

This repository has no licence file of its own. whip_core's `NOTICE.md` lists this map pack as Rockstar Games'
material: made from Grand Theft Auto V and used under the Cfx.re Creator Platform License Agreement. WHIP's licence
doesn't cover it. WHIP is not affiliated with, endorsed or sponsored by Rockstar Games or Take-Two Interactive.
