shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = world_pos.xz;
	vec2 tile = p / 2.4;
	vec2 seam = abs(fract(tile) - 0.5);
	float grout = smoothstep(0.477, 0.495, max(seam.x, seam.y));
	float grain = sin(p.x * 1.9 + sin(p.y * 2.2)) * sin(p.y * 2.8) * 0.009;
	float variation = fract(sin(dot(floor(tile), vec2(12.9898,78.233))) * 43758.5453);
	vec3 stone = mix(vec3(0.21,0.28,0.32), vec3(0.29,0.36,0.39), variation);
	float radius = length(p);
	float ring = 1.0 - smoothstep(0.025, 0.05, abs(radius - 5.2));
	ring += 1.0 - smoothstep(0.025, 0.05, abs(radius - 11.2));
	float axis = (1.0 - smoothstep(0.018, 0.04, min(abs(p.x), abs(p.y)))) * step(5.2, radius);
	vec3 bronze = vec3(0.46,0.33,0.16);
	ALBEDO = mix(stone + grain, vec3(0.12,0.17,0.20), grout * 0.5);
	ALBEDO = mix(ALBEDO, bronze, clamp(ring + axis, 0.0, 1.0));
	ROUGHNESS = 0.82;
	METALLIC = clamp(ring + axis, 0.0, 1.0) * 0.45;
}
