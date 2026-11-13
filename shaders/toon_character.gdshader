// =============================================================================
// Bandula — toon_character.gdshader
// Personagens «Universal Base Characters» (Quaternius) com a mesma luz toon do
// resto do jogo. A roupa é pintada no shader a partir de máscaras por vértice
// (geradas em tools/build_characters.gd a partir dos pesos dos ossos):
//   COLOR.r tronco · COLOR.g braço · COLOR.b antebraço · COLOR.a anca+coxa
//   UV2.x   perna (canela) · UV2.y pé
// Assim cada personagem tem tom de pele, camisa, calças/saia e sapatos próprios.
// =============================================================================
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

group_uniforms base;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
/** Multiplica a textura da pele (a textura original é bronzeada clara). */
uniform vec4 skin_tint : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.8;

group_uniforms outfit;
uniform vec4 shirt_color : source_color = vec4(0.95, 0.85, 0.3, 1.0);
uniform vec4 pants_color : source_color = vec4(0.2, 0.25, 0.45, 1.0);
uniform vec4 shoe_color : source_color = vec4(0.15, 0.12, 0.12, 1.0);
/** 0 = sem mangas · 1 = manga curta · 2 = manga comprida */
uniform int sleeves : hint_range(0, 2) = 1;
/** As calças cobrem a canela (falso = calções/saia). */
uniform bool long_legs = true;
/** Faixa na cintura da camisa/vestido (cor de destaque, estilo pano). */
uniform vec4 accent_color : source_color = vec4(0.9, 0.3, 0.2, 1.0);
uniform float accent_amount : hint_range(0.0, 1.0) = 0.0;
/** Quanto do relevo da textura passa para a roupa (dobras). */
uniform float cloth_detail : hint_range(0.0, 1.0) = 0.45;

group_uniforms cel_shading;
uniform float shadow_edge : hint_range(-1.0, 1.0) = 0.0;
uniform float mid_edge : hint_range(-1.0, 1.0) = 0.42;
uniform float band_softness : hint_range(0.001, 0.4) = 0.08;
uniform float mid_tone : hint_range(0.0, 1.0) = 0.78;
uniform vec4 sun_warmth : source_color = vec4(1.0, 0.94, 0.84, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.58, 0.52, 0.92, 1.0);
uniform float shadow_fill : hint_range(0.0, 1.0) = 0.42;

group_uniforms rim_light;
uniform vec4 rim_color : source_color = vec4(1.0, 0.93, 0.82, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.3;
uniform float rim_power : hint_range(0.5, 8.0) = 3.5;
group_uniforms;

float cut(float m) {
	float w = max(fwidth(m), 0.02);
	return smoothstep(0.5 - w, 0.5 + w, m);
}

void fragment() {
	vec3 tex = texture(albedo_texture, UV).rgb;
	vec3 col = tex * skin_tint.rgb;
	float lum = dot(tex, vec3(0.299, 0.587, 0.114));
	// dobras vêm do relevo da pele; a roupa interior pintada na textura (cinzenta/preta,
	// pouco saturada) é ignorada para não aparecer por baixo da roupa
	float sat = max(tex.r, max(tex.g, tex.b)) - min(tex.r, min(tex.g, tex.b));
	float fold = mix(1.0, clamp(lum / 0.32, 0.8, 1.2), cloth_detail * smoothstep(0.1, 0.2, sat));

	float shirt = cut(COLOR.r + (sleeves >= 1 ? COLOR.g : 0.0) + (sleeves >= 2 ? COLOR.b : 0.0));
	float pants = cut(COLOR.a + (long_legs ? UV2.x : 0.0));
	float shoes = cut(UV2.y);

	// faixa (cinto/pano) na fronteira tronco/anca
	float belt = cut(COLOR.r * 2.0) * cut(COLOR.a * 2.0) * accent_amount;
	vec3 shirt_c = mix(shirt_color.rgb, accent_color.rgb, belt);

	col = mix(col, shirt_c * fold, shirt);
	col = mix(col, pants_color.rgb * fold, pants);
	col = mix(col, shoe_color.rgb * mix(1.0, fold, 0.5), shoes);

	ALBEDO = col;
	ROUGHNESS = roughness;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = rim_color.rgb * fres * rim_strength * mix(vec3(0.35), col, 0.65);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(shadow_edge - band_softness, shadow_edge + band_softness, ndl);
	float top = smoothstep(mid_edge - band_softness, mid_edge + band_softness, ndl);
	float band = lit * mix(mid_tone, 1.0, top) * ATTENUATION;
	vec3 sun = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += sun * sun_warmth.rgb * band;
	if (LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += sun * shadow_tint.rgb * shadow_fill * (1.0 - band);
	}
}
