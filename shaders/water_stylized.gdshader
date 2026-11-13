// =============================================================================
// Bandula — water_stylized.gdshader
// Mar tropical da baía de Luanda: turquesa translúcido, ondulação suave,
// Fresnel que adensa a cor ao longe e brilhos a cintilar. Compatível com WebGL 2.
// =============================================================================
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 shallow_color : source_color = vec4(0.28, 0.86, 0.9, 0.78);
uniform vec4 deep_color : source_color = vec4(0.08, 0.55, 0.78, 0.92);
uniform float wave_height = 0.08;
uniform float wave_speed = 0.6;
uniform float sparkle_density = 900.0;
uniform float sparkle_strength : hint_range(0.0, 2.0) = 0.7;

void vertex() {
	VERTEX.y += sin(VERTEX.x * 0.08 + TIME * wave_speed) * cos(VERTEX.z * 0.07 + TIME * wave_speed * 0.8) * wave_height;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 c = mix(shallow_color.rgb, deep_color.rgb, fres);
	ALBEDO = c;
	ALPHA = mix(shallow_color.a, deep_color.a, fres);
	ROUGHNESS = 0.08;
	METALLIC = 0.1;
	float sp = sin(UV.x * sparkle_density + TIME * 1.3) * sin(UV.y * sparkle_density - TIME * 1.1);
	EMISSION = c * 0.12 + vec3(step(0.985, sp)) * sparkle_strength;
}
