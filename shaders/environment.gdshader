shader_type spatial;

render_mode world_vertex_coords, depth_prepass_alpha, cull_disabled, vertex_lighting;

uniform float CURVATURE;
uniform bool CURVATURE_ACTIVE;
uniform float CURVATURE_DISTANCE;

uniform sampler2D BASE_TEX : source_color, hint_default_white;
uniform vec4 color;
uniform float emission_energy = 0.0;

void vertex() {
	if (CURVATURE_ACTIVE == true) {
		NORMAL = (MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz;
		float dist = length(INV_VIEW_MATRIX[3].xyz - VERTEX) / CURVATURE_DISTANCE;
		VERTEX.y -= pow(dist, CURVATURE);
	}
}

void fragment() {
	vec4 tex = texture(BASE_TEX, UV);
	
	if (tex.a < 0.3) {
		discard;
	}
	
	ALBEDO = tex.rgb * color.rgb;
	EMISSION = tex.rgb * color.rgb * emission_energy;
	ALPHA  = tex.a;
}
