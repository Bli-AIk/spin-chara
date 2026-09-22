// Player HP bar, ported from Arch-AIk/Undertale-Changer-Template
// Assets/Shaders/Sprites/HPBar.shadergraph and the SelectUIController.cs that
// drives it. The sprite it is applied to is a full-width bar (Resources/px.png,
// so texture_coords.x spans 0..1 across the whole bar); the shader paints every
// region itself and the sprite's own color is deliberately ignored.
//
// Region layout, left to right:
//   [0, crop)         colorOn     current HP
//   [crop, flash)     colorFlash  short damage trail or item healing preview
//   [flash, 1]        colorUnder  empty slot
//
// `isFlashing` mirrors the reference `_IsFlashing`: 0 is solid, 1 pulses.
// Missing HP is red; a white damage trail shrinks over 0.5 seconds.
extern float crop;
extern float flash;
extern float isFlashing;
extern float pulse_time;
extern vec4 colorOn;
extern vec4 colorUnder;
extern vec4 colorFlash;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    // step(edge, x) yields 1 when x >= edge, so feeding the coordinate as the
    // edge fills from the left.
    float u = texture_coords.x;
    float fill = step(u, crop);
    vec4 bar = mix(colorUnder, colorOn, fill);

    // Pulse only the preview region, leaving the actual HP fill unchanged.
    float band = max(0.0, step(u, flash) - fill);
    float weight = band * mix(1.0, abs(sin(pulse_time)), isFlashing);
    vec4 result = mix(bar, colorFlash, weight);
    result.a *= color.a * Texel(texture, texture_coords).a;
    return result;
}
