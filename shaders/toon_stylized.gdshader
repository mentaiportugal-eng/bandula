// =============================================================================
// Bandula — toon_stylized.gdshader
// Cel-shading suave de 2 bandas (Slime Rancher / Pixar) para o renderer
// Compatibility (WebGL 2): sol equatorial quente, sombras lilases/azuladas
// (nunca pretas), rim-light de Fresnel e brilho toon opcional (vidro, verniz).
// Cores por vértice (Luanda City Kit) multiplicam o albedo.
// =============================================================================
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

group_uniforms base;
uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = true;
uniform bool use_texture = false;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 uv_scale = vec2(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

group_uniforms cel_shading;
/** Fronteira luz/sombra (N·L). */
uniform float shadow_edge : hint_range(-1.0, 1.0) = 0.0;
/** Fronteira meio-tom/luz plena (segunda banda). */
uniform float mid_edge : hint_range(-1.0, 1.0) = 0.42;
uniform float band_softness : hint_range(0.001, 0.4) = 0.08;
/** Intensidade da banda intermédia. */
uniform float mid_tone : hint_range(0.0, 1.0) = 0.78;
/** Calor do sol equatorial sobre as zonas iluminadas. */
uniform vec4 sun_warmth : source_color = vec4(1.0, 0.94, 0.84, 1.0);
/** Cor das sombras (lilás/azulada) — preenche o lado escuro, nunca preto. */
uniform vec4 shadow_tint : source_color = vec4(0.58, 0.52, 0.92, 1.0);
uniform float shadow_fill : hint_range(0.0, 1.0) = 0.42;

group_uniforms rim_light;
uniform vec4 rim_color : source_color = vec4(1.0, 0.93, 0.82, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.28;
uniform float rim_power : hint_range(0.5, 8.0) = 3.5;

group_uniforms toon_gloss;
/** Brilho especular recortado (0 = desligado). Vidro e verniz usam ~0.6. */
uniform float gloss : hint_range(0.0, 1.0) = 0.0;
uniform float gloss_size : hint_range(0.5, 0.999) = 0.93;

group_uniforms emission;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 0.0;
group_uniforms;

void fragment() {
	vec4 base = albedo;
	if (use_vertex_color) {
		base.rgb *= COLOR.rgb;
	}
	if (use_texture) {
		base *= texture(albedo_texture, UV * uv_scale);
	}
	ALBEDO = base.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	// rim-light de Fresnel: contorno quente e suave
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = rim_color.rgb * fres * rim_strength * mix(vec3(0.35), base.rgb, 0.65)
		+ emission_color.rgb * emission_energy;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(shadow_edge - band_softness, shadow_edge + band_softness, ndl);
	float top = smoothstep(mid_edge - band_softness, mid_edge + band_softness, ndl);
	float band = lit * mix(mid_tone, 1.0, top) * ATTENUATION;
	vec3 sun = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += sun * sun_warmth.rgb * band;
	if (LIGHT_IS_DIRECTIONAL) {
		// sombra própria e projetada recebem lilás em vez de escurecer para preto
		DIFFUSE_LIGHT += sun * shadow_tint.rgb * shadow_fill * (1.0 - band);
	}
	if (gloss > 0.0) {
		vec3 h = normalize(VIEW + LIGHT);
		float s = smoothstep(gloss_size, gloss_size + 0.02, dot(NORMAL, h));
		SPECULAR_LIGHT += sun * s * gloss * ATTENUATION;
	}
}
