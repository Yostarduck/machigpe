shader_type canvas_item;
// Full-screen look of the record ability (driven by scripts/record/record_hud.gd):
// a night vision camera while recording (green tint, fisheye lens, film grain,
// vignette), a desaturated, tinted, scanlined image while rewinding.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float record_amount : hint_range(0.0, 1.0) = 0.0;
uniform float rewind_amount : hint_range(0.0, 1.0) = 0.0;

group_uniforms night_vision;
uniform vec4 night_vision_tint : source_color = vec4(0.35, 1.0, 0.4, 1.0);
// Brightness gain: night vision amplifies the light it gets.
uniform float night_vision_gain : hint_range(0.5, 4.0) = 1.15;
// Colour the brightest areas fade to, instead of clipping to flat green.
uniform vec4 night_vision_highlight : source_color = vec4(0.8, 1.0, 0.8, 1.0);
// Barrel distortion: 0 = flat, higher = rounder lens.
uniform float fisheye_strength : hint_range(0.0, 1.0) = 0.1;
uniform float grain_amount : hint_range(0.0, 0.5) = 0.12;
// Grain changes per second (film frames).
uniform float grain_fps : hint_range(1.0, 60.0) = 24.0;
// Distance from the centre where the vignette starts and where it is fully black.
uniform float vignette_start : hint_range(0.0, 1.0) = 0.7;
uniform float vignette_end : hint_range(0.0, 1.5) = 1.1;
// Brightness flicker of the image intensifier.
uniform float flicker_amount : hint_range(0.0, 0.2) = 0.03;
group_uniforms;

group_uniforms rewind;
uniform vec4 rewind_tint : source_color = vec4(0.55, 0.75, 1.0, 1.0);
// How much colour is removed while rewinding (1 = black and white, then tinted).
uniform float rewind_desaturation : hint_range(0.0, 1.0) = 0.75;
group_uniforms;

float random(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x; // width / height

	// Fisheye: radial barrel distortion, measured in a square space so the lens is round.
	// Scaled so the screen corners still sample inside the screen.
	vec2 centered = (SCREEN_UV - 0.5) * vec2(aspect, 1.0);
	float k = fisheye_strength * record_amount;
	float corner = dot(vec2(aspect, 1.0) * 0.5, vec2(aspect, 1.0) * 0.5);
	vec2 lens = centered * (1.0 + k * dot(centered, centered)) / (1.0 + k * corner);
	vec2 uv = lens / vec2(aspect, 1.0) + 0.5;

	// A slight horizontal wobble while rewinding, like a tape being scrubbed
	uv.x += sin(uv.y * 90.0 + TIME * 35.0) * 0.0012 * rewind_amount;
	vec3 color = texture(screen_texture, uv).rgb;

	// Rewind: desaturate, tint, scanlines, darker edges
	float rewind_vignette = smoothstep(0.4, 0.85, distance(SCREEN_UV, vec2(0.5)));
	float grey = dot(color, vec3(0.299, 0.587, 0.114));
	vec3 rewound = mix(color, vec3(grey) * rewind_tint.rgb, rewind_desaturation);
	rewound *= 0.88 + 0.12 * sin(FRAGCOORD.y * 1.6 + TIME * 25.0);
	rewound *= 1.0 - rewind_vignette * 0.45;
	color = mix(color, rewound, rewind_amount);

	// Record: night vision
	float luminance = dot(color, vec3(0.299, 0.587, 0.114));
	float flicker = 1.0 + flicker_amount * sin(TIME * 60.0) * sin(TIME * 7.3);
	float level = luminance * night_vision_gain;
	vec3 night = night_vision_tint.rgb * min(level, 1.0);
	night = mix(night, night_vision_highlight.rgb, smoothstep(0.85, 1.2, level) * 0.6);
	night *= flicker;
	// Grain: new noise every film frame, in screen pixels
	float frame = floor(TIME * grain_fps);
	night += (random(FRAGCOORD.xy + frame * vec2(17.0, 31.0)) - 0.5) * grain_amount;
	// Round vignette around the lens
	float vignette = smoothstep(vignette_start, vignette_end, length(centered));
	night *= 1.0 - vignette;
	color = mix(color, night, record_amount);

	COLOR = vec4(color, 1.0);
}
