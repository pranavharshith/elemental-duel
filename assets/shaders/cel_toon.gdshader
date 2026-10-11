shader_type spatial;
render_mode specular_disabled;

uniform vec4 base_color : source_color = vec4(1.0);
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 8.0) = 0.0;
uniform float shadow_band : hint_range(0.0, 1.0) = 0.32;
uniform float mid_band : hint_range(0.0, 1.0) = 0.68;

void fragment() {
	ALBEDO = base_color.rgb;
	ALPHA = base_color.a;
	ROUGHNESS = 0.88;
	EMISSION = emission_color.rgb * emission_energy;
}

void light() {
	float n_dot_l = max(dot(NORMAL, LIGHT), 0.0);
	float bands = mix(0.28, 0.68, step(shadow_band, n_dot_l));
	bands = mix(bands, 1.0, step(mid_band, n_dot_l));
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * bands;
}
